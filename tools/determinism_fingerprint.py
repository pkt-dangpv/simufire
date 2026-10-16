"""Huella de determinismo del motor: generar en cada máquina/build y comparar.

Generar (headless, ~5 min con --worker):
    python -X utf8 tools/determinism_fingerprint.py run --out <huella.json> [--worker]
Comparar dos huellas (sale con 1 si difieren):
    python -X utf8 tools/determinism_fingerprint.py compare <a.json> <b.json>

El escenario es siempre el mismo: `tools/determinism_fingerprint_options.json`
copiado a un `user://` aislado en una carpeta temporal, para que ni las opciones
ni los datos de usuario de la máquina entren en la corrida. Godot se resuelve
con --godot, GODOT_EXE, PATH o el escritorio (scripts/project_paths.py).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch  # noqa: E402
from scripts.project_paths import find_godot  # noqa: E402

SCRIPT = ROOT / "tools" / "determinism_fingerprint.gd"
OPTIONS = ROOT / "tools" / "determinism_fingerprint_options.json"
PREFIX = "DETERMINISM_FINGERPRINT "


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def run(args: argparse.Namespace) -> int:
    godot = find_godot(args.godot)
    if godot is None:
        print("Godot no encontrado: usa --godot o GODOT_EXE", file=sys.stderr)
        return 2
    out = Path(args.out).resolve()
    work = Path(tempfile.mkdtemp(prefix="simufire_fingerprint_"))
    environment = os.environ.copy()
    for name in ("APPDATA", "TEMP", "TMP"):
        path = work / name.lower()
        path.mkdir()
        environment[name] = str(path)
    userdata = work / "appdata" / "Godot" / "app_userdata" / "SimuFire"
    userdata.mkdir(parents=True)
    shutil.copyfile(OPTIONS, userdata / "startup_sim_options.json")
    command = [godot, "--headless", "--path", ROOT, "--script", SCRIPT, "--",
               f"--steps={args.steps}", f"--checkpoint-every={args.checkpoint_every}"]
    if args.worker:
        command.append("--worker")
    result = godot_monitored_launch.run(command, timeout_s=args.timeout_s, environment=environment)
    text = result.stdout + result.stderr
    lines = [line for line in result.stdout.splitlines() if line.startswith(PREFIX)]
    problems = [line for line in text.splitlines() if "SCRIPT ERROR" in line or "Parse Error" in line]
    if not result.launched or result.returncode != 0 or result.faults or problems or len(lines) != 1:
        (work / "stdout.log").write_text(result.stdout, encoding="utf-8")
        (work / "stderr.log").write_text(result.stderr, encoding="utf-8")
        print(f"corrida no válida: rc={result.returncode} faults={result.faults} "
              f"preexisting={result.preexisting} errores={len(problems)}; registros en {work}",
              file=sys.stderr)
        return 2
    data = json.loads(lines[0][len(PREFIX):])
    data["host"] = {
        "machine": platform.machine(),
        "platform": platform.platform(),
        "processor": platform.processor(),
        "godot_executable_name": godot.name,
        "godot_executable_sha256": _sha256_file(godot),
        "options_sha256": _sha256_file(OPTIONS),
        "script_sha256": _sha256_file(SCRIPT),
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
    shutil.rmtree(work, ignore_errors=True)
    print(f"huella escrita en {out}")
    _print_summary(data)
    return 0


def _print_summary(data: dict) -> None:
    print(f"  {data['processor_name']} | Godot {data['godot_version']['string']} | "
          f"editor={data['editor_build']} plantilla={data['template_build']}")
    math = data["math"]
    differing = [name for name in math["main"] if math["main"][name] != math["worker"][name]]
    det = [name for name in differing if name.startswith("det_")]
    godot = [name for name in differing if not name.startswith("det_")]
    print(f"  DetMath distinta entre hilos: {det or 'ninguna'} | Godot distinta entre hilos (información): {godot or 'ninguna'}")
    runs = data["runs"]
    if "worker" in runs:
        first = _first_mismatch(runs["main"]["checkpoints"], runs["worker"]["checkpoints"])
        print(f"  corrida en hilo trabajador frente a principal: "
              f"{'idéntica' if first is None else f'distinta desde el paso {first}'}")


def _first_mismatch(a: list, b: list) -> int | None:
    for left, right in zip(a, b):
        if left["chain_sha256"] != right["chain_sha256"]:
            return left["step"]
    return None if len(a) == len(b) else min(len(a), len(b))


def compare(args: argparse.Namespace) -> int:
    a = json.loads(Path(args.a).read_text(encoding="utf-8"))
    b = json.loads(Path(args.b).read_text(encoding="utf-8"))
    same = True
    for label, data in (("A", a), ("B", b)):
        print(f"{label}: {data['processor_name']} | {data['host']['platform']} | "
              f"Godot {data['godot_version']['string']} | ejecutable {data['host']['godot_executable_sha256'][:12]}")
    if a["host"]["options_sha256"] != b["host"]["options_sha256"] or a["steps"] != b["steps"]:
        print("AVISO: escenario o número de pasos distintos; la comparación no es válida")
        same = False
    for thread in ("main", "worker"):
        for name, value in a["math"][thread].items():
            other = b["math"][thread].get(name)
            if other == value:
                continue
            if name.startswith("det_"):
                same = False
                print(f"  DetMath {thread}/{name}: DISTINTA")
            else:
                print(f"  (información) Godot {thread}/{name}: distinta; el motor no la usa")
    for run_name in sorted(set(a["runs"]) & set(b["runs"])):
        first = _first_mismatch(a["runs"][run_name]["checkpoints"], b["runs"][run_name]["checkpoints"])
        if first is None:
            print(f"  corrida {run_name}: idéntica en los {a['steps']} pasos")
        else:
            same = False
            print(f"  corrida {run_name}: DISTINTA desde el punto de control del paso {first}")
    print("RESULTADO:", "IDÉNTICAS" if same else "DISTINTAS")
    return 0 if same else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    run_parser = sub.add_parser("run", help="generar una huella en esta máquina")
    run_parser.add_argument("--out", required=True, help="archivo JSON de salida")
    run_parser.add_argument("--godot", help="ejecutable de Godot (si no, GODOT_EXE, PATH o escritorio)")
    run_parser.add_argument("--steps", type=int, default=7200, help="pasos de 1/12 s (7200 = 10 min)")
    run_parser.add_argument("--checkpoint-every", type=int, default=600)
    run_parser.add_argument("--worker", action="store_true", help="repetir la corrida en un hilo trabajador")
    run_parser.add_argument("--timeout-s", type=int, default=3600)
    run_parser.set_defaults(func=run)
    compare_parser = sub.add_parser("compare", help="comparar dos huellas")
    compare_parser.add_argument("a")
    compare_parser.add_argument("b")
    compare_parser.set_defaults(func=compare)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
