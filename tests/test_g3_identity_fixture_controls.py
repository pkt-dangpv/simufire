"""Negative controls of the before/after identity fixtures.

The identity fixtures print a digest and no PASS marker, so the two generic
fail-closed contracts that look for a PASS marker skip them: those contracts
guard a success message, and here there is none to reach by mistake. What has
to hold instead is that the pinned comparison fails whenever the output is
absent, truncated or altered. That is shown here on the REAL output of each
fixture, and with a real change of behaviour in an isolated project copy.
"""
import json
import os
from pathlib import Path
import re

import pytest

from tests.g3_identity_output import identity_payload

ROOT = Path(__file__).resolve().parents[1]
# fixture, prefix, pinned report, sources to copy, (file, old, new) behaviour change
CASES = {
    "helper": {
        "fixture": "tests/fixtures/g3_sensible_enthalpy_identity.gd", "prefix": "G3_SENSIBLE_IDENTITY",
        "pinned": {"cases": 933, "valid": 565, "rejected": 368,
                   "sha256": "521425c77676e4523471a3070aa651b840144bd0cee51d37e542aec9fad950a8"},
        "sources": ["sim/fire/SensibleEnthalpyModel.gd"],
        "change": ("sim/fire/SensibleEnthalpyModel.gd", "integral += area", "integral += 0.5 * area"),
    },
    "chain": {
        "fixture": "tests/fixtures/g3_sensible_chain_identity.gd", "prefix": "G3_SENSIBLE_CHAIN_IDENTITY",
        "pinned": {"cases": 1985, "valid": 799, "rejected": 1186,
                   "sha256": "aa407250140841a203f4e3c07c415d6b24d2ca8d6338b0794b19b7ad9e2681c9"},
        "sources": ["sim/fire/SensibleEnthalpyModel.gd", "sim/fire/HeptaneRealCpProfiles.gd",
                    "sim/fire/FuelMassBudgetModel.gd", "sim/fire/PrescribedFuelReleaseModel.gd",
                    "sim/fire/PrescribedSensiblePhaseController.gd"],
        "change": ("sim/fire/FuelMassBudgetModel.gd",
                   "var oxidized_sensible: float = oxidized * mixed_specific",
                   "var oxidized_sensible: float = 0.0"),
    },
}
_OUTPUT = {}


def _godot():
    from scripts import godot_monitored_launch

    godot = Path(os.environ.get(
        "GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot executable unavailable")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0
    return godot


def _run(project: Path, fixture: str):
    from tests.godot_runtime_launcher import run_godot

    completed = run_godot([_godot(), "--headless", "--path", project, "--script", project / fixture],
                          timeout_s=300, allowed_exit_codes=(0, 1))
    return completed.stdout, completed.stderr


def _real_output(name: str):
    if name not in _OUTPUT:
        _OUTPUT[name] = _run(ROOT, CASES[name]["fixture"])
    return _OUTPUT[name]


def _digest_line(stdout: str, prefix: str) -> str:
    return next(line for line in stdout.splitlines() if line.startswith(prefix + " "))


@pytest.mark.parametrize("name", sorted(CASES))
def test_complete_real_output_matches_its_pin(name):
    stdout, stderr = _real_output(name)
    assert identity_payload(stdout, stderr, CASES[name]["prefix"]) == CASES[name]["pinned"]


@pytest.mark.parametrize("name", sorted(CASES))
def test_absent_output_fails_the_comparison(name):
    stdout, stderr = _real_output(name)
    prefix = CASES[name]["prefix"]
    line = _digest_line(stdout, prefix)
    for absent in ["", stdout.replace(line + "\n", "").replace(line, ""), prefix + "_DONE\n",
                   "\n".join(l for l in stdout.splitlines() if not l.startswith(prefix))]:
        with pytest.raises(AssertionError):
            identity_payload(absent, stderr, prefix)


@pytest.mark.parametrize("name", sorted(CASES))
def test_truncated_output_fails_the_comparison(name):
    stdout, stderr = _real_output(name)
    prefix = CASES[name]["prefix"]
    line = _digest_line(stdout, prefix)
    cut_line = stdout.replace(line, line[:len(line) // 2])
    no_marker = stdout.replace(prefix + "_DONE", "")
    cut_stream = stdout[:stdout.index(line) + len(line) - 3]
    short_digest = stdout.replace(line, line.replace(CASES[name]["pinned"]["sha256"],
                                                    CASES[name]["pinned"]["sha256"][:40]))
    marker_first = prefix + "_DONE\n" + stdout.replace(prefix + "_DONE", "")
    for truncated in [cut_line, no_marker, cut_stream, short_digest, marker_first]:
        assert truncated != stdout
        with pytest.raises(AssertionError):
            identity_payload(truncated, stderr, prefix)


@pytest.mark.parametrize("name", sorted(CASES))
def test_altered_output_fails_the_comparison(name):
    stdout, stderr = _real_output(name)
    prefix, pinned = CASES[name]["prefix"], CASES[name]["pinned"]
    line = _digest_line(stdout, prefix)
    digest = pinned["sha256"]
    flipped = digest[:-1] + ("0" if digest[-1] != "0" else "1")

    def rewritten(**fields):
        return stdout.replace(line, prefix + " " + json.dumps({**pinned, **fields}))

    # A report that is well formed but different never equals the pin.
    for altered in [stdout.replace(digest, flipped),
                    rewritten(valid=pinned["valid"] + 1, rejected=pinned["rejected"] - 1),
                    rewritten(cases=pinned["cases"] + 1, valid=pinned["valid"] + 1)]:
        assert identity_payload(altered, stderr, prefix) != pinned
    # A report that is not well formed is refused before any comparison.
    for malformed in [rewritten(cases=pinned["cases"] + 1), rewritten(sha256=digest.upper()),
                      rewritten(sha256=""), rewritten(extra=1), rewritten(valid=str(pinned["valid"])),
                      rewritten(valid=float(pinned["valid"])), stdout.replace(line, line + "\n" + line),
                      stdout.replace(line, prefix + " " + json.dumps([pinned]))]:
        with pytest.raises(AssertionError):
            identity_payload(malformed, stderr, prefix)
    for noise in ["SCRIPT ERROR: abort", "Parse Error: unexpected token"]:
        with pytest.raises(AssertionError):
            identity_payload(stdout, stderr + noise, prefix)
        with pytest.raises(AssertionError):
            identity_payload(stdout + noise, stderr, prefix)


@pytest.mark.parametrize("name", sorted(CASES))
def test_a_real_change_of_behaviour_moves_the_digest(name, tmp_path):
    """Isolated copy, one law changed: the corpus still completes and no longer matches."""
    case = CASES[name]
    for relative in case["sources"] + [case["fixture"]]:
        target = tmp_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / relative).read_bytes())
    (tmp_path / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Isolated identity control"\n', encoding="utf-8")
    stdout, stderr = _run(tmp_path, case["fixture"])
    assert identity_payload(stdout, stderr, case["prefix"]) == case["pinned"], "isolated control"
    path, old, new = case["change"]
    source = (tmp_path / path).read_text(encoding="utf-8")
    assert source.count(old) == 1
    (tmp_path / path).write_text(source.replace(old, new), encoding="utf-8", newline="\n")
    stdout, stderr = _run(tmp_path, case["fixture"])
    changed = identity_payload(stdout, stderr, case["prefix"])
    assert changed["sha256"] != case["pinned"]["sha256"]
    assert changed["cases"] == case["pinned"]["cases"]
    # The working sources were never touched.
    assert (ROOT / path).read_text(encoding="utf-8").count(new) == 0


def test_identity_fixtures_keep_no_pass_marker_and_their_generic_skips():
    """The digest is judged by its pin; a PASS marker would only let the fixture judge itself."""
    for case in CASES.values():
        source = (ROOT / case["fixture"]).read_text(encoding="utf-8")
        assert "PASS" not in source
        assert source.count('print("' + case["prefix"] + '_DONE")') == 1
        assert re.search(r"quit\(1\)", source) is None
