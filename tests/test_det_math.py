"""sim/core/DetMath.gd: precisión frente a precisión arbitraria y determinismo entre hilos.

Arranca Godot (headless, monitorizado) con tests/fixtures/det_math_probe.gd. Las
referencias se calculan con `decimal` a 60 cifras, así que no dependen de la
biblioteca matemática de la máquina que corre el test.
"""

from __future__ import annotations

import decimal
import json
import math
import os
from pathlib import Path
import random
import re
import struct
import tempfile

import pytest

ROOT = Path(__file__).resolve().parents[1]
import sys  # noqa: E402

sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch  # noqa: E402
from scripts.project_paths import find_godot  # noqa: E402

FIXTURE = ROOT / "tests" / "fixtures" / "det_math_probe.gd"
D = decimal.Decimal
CTX = decimal.Context(prec=60)
PI = D("3.14159265358979323846264338327950288419716939937510582097494459")
# Exponentes de pow que usa sim/ (además de valores aleatorios).
SIM_EXPONENTS = [1.0 / 3.0, 2.0 / 3.0, 5.0 / 3.0, 0.4, 1.036, 1.33, 1.5, 4.0, 2.0, 0.5, -1.0, -2.5, 3.0]


def _hex(x: float) -> str:
    return struct.pack(">d", x).hex()


def _float(h: str) -> float:
    return struct.unpack(">d", bytes.fromhex(h))[0]


def _cases() -> dict[str, list[list[str]]]:
    rng = random.Random(20261015)
    cases: dict[str, list[list[float]]] = {name: [] for name in (
        "exp", "log", "pow", "sin", "cos", "tanh", "lerpf", "lerpf_godot", "inverse_lerp", "inverse_lerp_godot")}
    for _ in range(1500):
        cases["exp"].append([rng.uniform(-744.0, 709.0)])
        cases["exp"].append([rng.uniform(-6.0, 6.0)])
        cases["log"].append([10.0 ** rng.uniform(-307.0, 307.0)])
        cases["log"].append([rng.uniform(0.5, 2.0)])
        x = 10.0 ** rng.uniform(-3.0, 4.0)
        cases["pow"].append([x, rng.choice(SIM_EXPONENTS)])
        cases["pow"].append([x, rng.uniform(-6.0, 6.0)])
        cases["sin"].append([rng.uniform(-20.0, 20.0)])
        cases["cos"].append([rng.uniform(-20.0, 20.0)])
        cases["tanh"].append([rng.uniform(-6.0, 6.0)])
        cases["tanh"].append([rng.uniform(-1e-3, 1e-3)])
        a, b, t = rng.uniform(-1e3, 1e3), rng.uniform(-1e3, 1e3), rng.uniform(-0.5, 1.5)
        for name in ("lerpf", "lerpf_godot", "inverse_lerp", "inverse_lerp_godot"):
            cases[name].append([a, b, t])
    for x in (5e-324, 2.2250738585072014e-308, 1.0, 2.0, 0.5, 1e308):
        cases["log"].append([x])
    for x in (0.0, -0.0, 1e-300, -745.0, 709.7, 0.34657359027997264, 1.0397207708399179):
        cases["exp"].append([x])
    return {name: [[_hex(v) for v in args] for args in rows] for name, rows in cases.items()}


def _reference(name: str, args: list[float]) -> D:
    a = D(args[0])
    with decimal.localcontext(CTX):
        if name == "exp":
            return a.exp()
        if name == "log":
            return a.ln()
        if name == "pow":
            return (D(args[1]) * a.ln()).exp()
        if name == "tanh":
            e = (2 * a).exp()
            return (e - 1) / (e + 1)
        if name in ("sin", "cos"):
            r = a % (2 * PI)
            term = r if name == "sin" else D(1)
            total = term
            n = 1 if name == "sin" else 0
            while abs(term) > D("1e-70"):
                term = -term * r * r / ((n + 1) * (n + 2))
                total += term
                n += 2
            return total
    raise ValueError(name)


def _ulps(result: float, ref: D) -> float:
    exact = float(ref)
    if math.isinf(exact) or exact == 0.0:
        return 0.0 if result == exact else math.inf
    return float(abs(D(result) - ref) / D(math.ulp(exact)))


@pytest.fixture(scope="module")
def probe() -> tuple[dict, dict]:
    godot = find_godot()
    if godot is None:
        pytest.skip("Godot no encontrado (GODOT_EXE, PATH o escritorio)")
    cases = _cases()
    with tempfile.TemporaryDirectory(prefix="simufire_detmath_") as work:
        work_path = Path(work)
        (work_path / "in.json").write_text(json.dumps(cases), encoding="utf-8")
        environment = os.environ.copy()
        for name in ("APPDATA", "TEMP", "TMP"):
            path = work_path / name.lower()
            path.mkdir()
            environment[name] = str(path)
        result = godot_monitored_launch.run(
            [godot, "--headless", "--path", ROOT, "--script", FIXTURE, "--",
             f"--in={work_path / 'in.json'}", f"--out={work_path / 'out.json'}"],
            timeout_s=600, environment=environment)
        text = result.stdout + result.stderr
        assert result.launched and result.returncode == 0 and not result.faults, (
            result.returncode, result.faults, result.preexisting)
        assert "SCRIPT ERROR" not in text and "Parse Error" not in text, text[-2000:]
        out = json.loads((work_path / "out.json").read_text(encoding="utf-8"))
    return cases, out


# Precisión tipo fdlibm. pow llega a ~1,8 ulp por el atajo x⁴ = (x²)² y tanh a
# ~2,1 ulp con argumentos pequeños (expm1 de Kahan). Lo que importa para el motor
# es que el resultado sea el mismo en todas partes; estos límites vigilan que
# un cambio no estropee la precisión.
@pytest.mark.parametrize("name,limit", [
    ("exp", 1.0), ("log", 1.0), ("pow", 2.0), ("sin", 1.0), ("cos", 1.0), ("tanh", 2.5)])
def test_accuracy_against_arbitrary_precision(probe, name, limit):
    cases, out = probe
    worst = 0.0
    worst_args = None
    for args_hex, result_hex in zip(cases[name], out["main"][name]):
        args = [_float(h) for h in args_hex]
        ulps = _ulps(_float(result_hex), _reference(name, args))
        if ulps > worst:
            worst, worst_args = ulps, args
    assert worst <= limit, f"{name}: {worst:.3f} ulp en {worst_args}"


def test_worker_thread_gives_identical_bits(probe):
    _, out = probe
    assert out["worker_identical"] is True


@pytest.mark.parametrize("name", ["lerpf", "inverse_lerp"])
def test_interpolation_matches_godot_formula_on_this_platform(probe, name):
    _, out = probe
    assert out["main"][name] == out["main"][name + "_godot"]


# Funciones de Godot que dependen de la biblioteca matemática de C del build (o,
# en ARM, de cómo se compiló Godot) y que el motor no debe llamar directamente.
_FORBIDDEN = re.compile(
    r"(?<![\w.])(exp|exp2|expm1|log|log2|log10|pow|sin|cos|tan|asin|acos|atan|atan2|"
    r"sinh|cosh|tanh|asinh|acosh|atanh|lerp|lerpf|inverse_lerp|remap|smoothstep|ease)\(")


def _code_part(line: str) -> str:
    """Line without comment and without string literals."""
    out, quote, i = [], None, 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            break
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def test_sim_routes_transcendental_math_through_detmath():
    offenders = []
    for path in sorted((ROOT / "sim").rglob("*.gd")):
        if path.name == "DetMath.gd":
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if re.match(r"^\s*(static\s+)?func\s", line):
                continue
            code = _code_part(line)
            if _FORBIDDEN.search(code) or "**" in code:
                offenders.append(f"{path.relative_to(ROOT).as_posix()}:{number}: {line.strip()}")
    assert not offenders, "usar DetMath.<función>:\n" + "\n".join(offenders)
