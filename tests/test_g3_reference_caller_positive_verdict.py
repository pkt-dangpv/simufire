"""Reference caller: acceptance needs an explicit positive verdict (2026-10-05).

`_check_owned` used to return nothing and its consumers took an empty error
list as acceptance, so a validation that stopped without adding an error let a
state through. It now returns an explicit verdict that every consumer requires.
This is a fix of the caller's acceptance decision only: no physical identity,
tolerance, schema, public API, message or fingerprint changes.
"""
import hashlib
import json
import os
from pathlib import Path
import re

import pytest

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "sim/fire/PrescribedPhaseBudgetController.gd"
FIXTURE = ROOT / "tests/fixtures/g3_reference_caller_positive_verdict.gd"
ABORT_FIXTURE = ROOT / "tests/fixtures/g3_reference_caller_abort_control.gd"
PREFIX = "G3_REFERENCE_CALLER_POSITIVE_VERDICT"
ABORT_PREFIX = "G3_REFERENCE_CALLER_ABORT_CONTROL"
CHECKS = 280  # Measured on the real fixture; never anticipated.
MUTANTS = 17
CURRENT = "41e6e36768eb386f5b9c6f9e9cb5b1e002227526cfef5d013926f8a595e4e6c6"
# Bytes of the caller after the type-guard hotfix and before this fix.
PREVIOUS = "69f74112d52ca77c7c4c3c07987d21747920b970d3e1221fa03464d6170942ed"
DIAGNOSTIC = "state validation ended without a positive verdict"
CONSUMERS = ["initialize", "preview_step", "commit_step", "restore"]

# (text before this fix, text after this fix). Undoing them must give PREVIOUS.
VERDICT_EDITS = [
    ("\t_check_owned(candidate, c, errors)\n\tif not errors.is_empty():\n\t\treturn _failure(errors)\n",
     "\tif not _accepted(candidate, c, errors):\n\t\treturn _failure(errors)\n"),
    ("\t_check_owned(_owned, _context, errors)\n\tvar end: float = ",
     "\tvar current: bool = _accepted(_owned, _context, errors)\n\tvar end: float = "),
    ("\t\terrors.append(\"physical time cannot go backwards\")\n\tif not errors.is_empty():\n",
     "\t\terrors.append(\"physical time cannot go backwards\")\n\tif not current or not errors.is_empty():\n"),
    ("\t_check_owned(candidate, _context, errors)\n\tif not errors.is_empty():\n\t\treturn _failure(errors)\n",
     "\tif not _accepted(candidate, _context, errors):\n\t\treturn _failure(errors)\n"),
    ("\tif not proposal[\"valid\"]:\n\t\treturn proposal\n",
     "\t# An explicit preview result is required. A rejection passes through; anything\n\t# short of valid=true with its candidate and step never reaches the write.\n\tif typeof(proposal.get(\"valid\")) == TYPE_BOOL and not proposal[\"valid\"]:\n\t\treturn proposal\n\tif typeof(proposal.get(\"valid\")) != TYPE_BOOL or typeof(proposal.get(\"candidate\")) != TYPE_DICTIONARY or typeof(proposal.get(\"step\")) != TYPE_DICTIONARY:\n\t\treturn _failure([\"step preview returned no explicit positive result\"])\n"),
    ("\t_check_owned(_owned, _context, errors)\n\t_check_owned(saved, _context, errors)\n\tif not errors.is_empty():\n",
     "\tvar current: bool = _accepted(_owned, _context, errors)\n\tvar requested: bool = _accepted(saved, _context, errors)\n\tif not current or not requested:\n"),
    ("func _check_owned(value: Variant, context: Dictionary, errors: Array[String]) -> void:\n",
     "## Explicit verdict. True only from the last statement, when every check ran and\n## this call reported nothing; every early exit is false.\nfunc _check_owned(value: Variant, context: Dictionary, errors: Array[String]) -> bool:\n\tvar reported: int = errors.size()\n"),
    ("\tif not errors.is_empty():\n\t\treturn\n\tvar source: Dictionary = ",
     "\tif errors.size() != reported:\n\t\treturn false\n\tvar source: Dictionary = "),
    ("\t\terrors.append(\"invalid source progress\")\n\t\treturn\n",
     "\t\terrors.append(\"invalid source progress\")\n\t\treturn false\n"),
    ("\t\terrors.append(\"invalid canonical release recomposition\")\n\t\treturn\n",
     "\t\terrors.append(\"invalid canonical release recomposition\")\n\t\treturn false\n"),
    ("\t\terrors.append(\"invalid canonical oxidation recomposition\")\n\t\treturn\n",
     "\t\terrors.append(\"invalid canonical oxidation recomposition\")\n\t\treturn false\n"),
    ("\t_compare(initial_total, final_total, true, \"aggregate A+B+Q\", errors)\n",
     "\t_compare(initial_total, final_total, true, \"aggregate A+B+Q\", errors)\n\treturn errors.size() == reported\n\n\n## An empty error list is not acceptance: an interrupted check adds no error.\n## Accept only an explicit true verdict from a check that reported nothing.\nfunc _accepted(value: Variant, context: Dictionary, errors: Array[String]) -> bool:\n\tvar reported: int = errors.size()\n\tvar verdict: Variant = _check_owned(value, context, errors)\n\tif typeof(verdict) == TYPE_BOOL and verdict and errors.size() == reported:\n\t\treturn true\n\tif errors.size() == reported:\n\t\terrors.append(\"state validation ended without a positive verdict\")\n\treturn false\n"),
]


def _source() -> str:
    return MODEL.read_bytes().replace(b"\r\n", b"\n").decode("utf-8")


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def undo_verdict_edits(source: str) -> str:
    for before, after in VERDICT_EDITS:
        assert source.count(after) == 1, after
        source = source.replace(after, before, 1)
    return source


def _function(source: str, name: str) -> str:
    match = re.search(r"^(?:##[^\n]*\n)*func " + name + r"\([\s\S]*?(?=\n\n\n|\Z)", source, re.M)
    assert match, name
    return match.group()


def test_actual_positive_verdict_p01_p08():
    from scripts import godot_monitored_launch
    from tests.godot_runtime_launcher import run_godot
    godot = Path(os.environ.get(
        "GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot executable not found")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0
    completed = run_godot([godot, "--headless", "--path", ROOT, "--script", FIXTURE],
                          timeout_s=180, allowed_exit_codes=(0,))
    output = (completed.stdout or "") + (completed.stderr or "")
    # The normal suite substitutes the validator; it never provokes a script error.
    assert "SCRIPT ERROR" not in output and "Parse Error" not in output
    payload = json.loads(next(line.split(" ", 1)[1] for line in completed.stdout.splitlines()
                              if line.startswith(PREFIX + " {")))
    assert payload["failures"] == []
    assert payload["groups"] == [f"P{i:02}" for i in range(1, 9)]
    assert payload["checks"] == CHECKS
    assert PREFIX + "_PASS" in completed.stdout


def test_only_the_verdict_edits_changed():
    source = _source()
    assert _sha(source) == CURRENT
    # Undoing the edits reproduces the bytes pinned by the type-guard hotfix.
    assert _sha(undo_verdict_edits(source)) == PREVIOUS


def test_validator_returns_an_explicit_verdict_only_at_its_end():
    body = _function(_source(), "_check_owned")
    assert "func _check_owned(value: Variant, context: Dictionary, errors: Array[String]) -> bool:" in body
    returns = re.findall(r"^\t+return\b.*$", body, re.M)
    # Every early exit is negative; the single positive exit is the last statement.
    assert returns[:-1] == ["\t\treturn false"] * 4
    assert returns[-1] == "\treturn errors.size() == reported"
    assert body.rstrip().endswith("return errors.size() == reported")
    assert "return true" not in body
    assert body.count("var reported: int = errors.size()") == 1


def test_acceptance_needs_the_verdict_and_an_unchanged_error_list():
    body = _function(_source(), "_accepted")
    assert "var verdict: Variant = _check_owned(value, context, errors)" in body
    assert "if typeof(verdict) == TYPE_BOOL and verdict and errors.size() == reported:" in body
    assert body.count("return true") == 1 and body.rstrip().endswith("return false")
    # A rejection is never left without a reason.
    assert 'errors.append("' + DIAGNOSTIC + '")' in body


def test_every_consumer_goes_through_the_acceptance_gate():
    source = _source()
    # The validator is consulted from the gate only, never judged by an empty list.
    assert source.count("_check_owned(") == 2  # Its definition and the gate.
    assert source.count("_accepted(") == 6     # Its definition and five consumer calls.
    expected = {"initialize": 1, "preview_step": 2, "commit_step": 0, "restore": 2}
    for name in CONSUMERS:
        body = _function(source, name)
        assert body.count("_accepted(") == expected[name], name
        assert "_check_owned(" not in body, name
    for name in ["initialize", "restore"]:
        body = _function(source, name)
        gate = body.rindex("_accepted(")
        # Nothing is written before the last gate of the operation.
        assert body.index("_owned = ") > gate, name
    assert _function(source, "initialize").index("_context = ") > _function(source, "initialize").index("_accepted(")
    assert "_owned = " not in _function(source, "preview_step")
    restore = _function(source, "restore")
    assert "if not current or not requested:" in restore
    assert "errors.is_empty()" not in restore


def test_commit_requires_an_explicit_preview_result_before_writing():
    body = _function(_source(), "commit_step")
    explicit = body.index('typeof(proposal.get("valid")) != TYPE_BOOL')
    assert 'typeof(proposal.get("candidate")) != TYPE_DICTIONARY' in body
    assert 'typeof(proposal.get("step")) != TYPE_DICTIONARY' in body
    assert body.index("_owned = ") > explicit
    assert 'proposal["valid"]:' in body and 'if not proposal["valid"]:' not in body
    # A generation conflict is still refused before anything is validated.
    assert body.index("_generation_matches(") < body.index("preview_step(")


def test_public_api_schemas_and_fingerprint_are_untouched():
    source = _source()
    public = [name for name in re.findall(r"^(?:static )?func (\w+)\(", source, re.M) if not name.startswith("_")]
    assert public == ["initialize", "snapshot", "preview_step", "commit_step", "restore"]
    for signature in ["func initialize(context: Variant) -> Dictionary:",
                      "func preview_step(end_time_s: Variant, oxidation_requested_kg: Variant) -> Dictionary:",
                      "func commit_step(end_time_s: Variant, oxidation_requested_kg: Variant, "
                      "expected_generation: Variant) -> Dictionary:",
                      "func restore(saved: Variant, expected_generation: Variant) -> Dictionary:"]:
        assert signature in source
    assert source.count('(VERSION + JSON.stringify(context, "", true, true)).sha256_text()') == 1
    for literal in ['"prescribed_phase_controller_v1"', '"g3_prescribed_phase_context_v1"',
                    '"g3_prescribed_phase_snapshot_v1"']:
        assert literal in source
    # Tolerances still come from the mass kernel; none is declared here.
    assert "Budget.ENERGY_ABS_TOL_KJ" in source and "Budget.MASS_ABS_TOL_KG" in source
    assert re.search(r"1(?:\.0)?e-\d+", source) is None
    flags = re.findall(r'"(\w*(?:approval|activation|integration)\w*)": (\w+)', source)
    assert len(flags) == 4 and all(value == "false" for _, value in flags)


def test_other_modules_are_not_part_of_this_fix():
    pins = {
        "PrescribedFuelReleaseModel": "db58278f2fff141d31148301095d41234f3732a66fa4140f74abfbaff483897d",
        "FuelMassBudgetModel": "7ab01e1628441c048d55a45a512fc85aed8347dbd8140a29c98160e82fcd3f12",
        # Helper pin moved on 2026-10-06: its loop became the shared `integrate`; synthetic results are bit-identical.
        "SensibleEnthalpyModel": "272de43f4a2b9fb1801c3924b08489c4b9d4d8c89026e576e3b4a8e62e796750",
        "PrescribedSensiblePhaseController": "63ea60420fa7a1995195addbc22e1fcfa4c30288b4fbb46174df44b120c01383",
    }
    for name, expected in pins.items():
        raw = (ROOT / f"sim/fire/{name}.gd").read_bytes().replace(b"\r\n", b"\n")
        assert hashlib.sha256(raw).hexdigest() == expected, name


def test_caller_is_still_not_loaded_by_product():
    for folder in ["sim", "editor", "ui", "view", "scenes", "scenarios", "tools", "addons"]:
        for path in (ROOT / folder).rglob("*"):
            if path != MODEL and path.is_file() and path.suffix in {".gd", ".tscn", ".tres", ".json", ".cfg"}:
                assert "PrescribedPhaseBudgetController" not in path.read_text(encoding="utf-8", errors="replace")
    assert "PrescribedPhaseBudgetController" not in (ROOT / "project.godot").read_text(encoding="utf-8")


def test_abort_control_is_kept_out_of_the_normal_suite():
    control = ABORT_FIXTURE.read_text(encoding="utf-8")
    assert control.count("# ABORT LINE") == 1
    assert "not part of the normal suite" in control
    # No test module launches it: it deliberately emits script errors.
    for path in (ROOT / "tests").glob("test_*.py"):
        text = path.read_text(encoding="utf-8")
        if path.name != Path(__file__).name:
            assert ABORT_FIXTURE.name not in text, path.name
    normal = FIXTURE.read_text(encoding="utf-8")
    assert "ABORT LINE" not in normal and "number != text" not in normal


def test_predeclared_verdict_mutants_have_one_real_anchor_each():
    from scripts.simulation import run_g3_positive_verdict_mutations as campaign
    source = MODEL.read_text(encoding="utf-8")
    variants = campaign.prepared_variants(source)
    assert len(variants) == len(campaign.MUTATIONS) == MUTANTS
    assert [name[:3] for name in variants] == [f"V{i:02}" for i in range(1, MUTANTS + 1)]
    assert all(mutant != source for mutant in variants.values())
    assert len(set(variants.values())) == MUTANTS
    assert MODEL.read_text(encoding="utf-8") == source
    assert campaign.MODEL == MODEL and campaign.FIXTURE == FIXTURE and campaign.PREFIX == PREFIX
    # The embedded reproduction targets the commit before this fix, whose validator was void.
    assert campaign.PREFIX_COMMIT.startswith("089e35bf")
    assert "-> void:" in campaign.REPRODUCTION_FIXTURE


def _report(prefix, payload):
    return prefix + " " + json.dumps(payload)


def _error(message, location):
    return f"SCRIPT ERROR: {message}\n   at: f ({location})\n   GDScript backtrace (most recent call first):\n"


OPERAND = "Invalid operands 'int' and 'String' in operator '!='."
CONTROL_SITE = "res://tests/fixtures/g3_reference_caller_abort_control.gd"


@pytest.mark.parametrize("stdout, stderr, code", [
    ("", "", 1),
    (_report(PREFIX, {"failures": ["behavioural"]}), "Parse Error", 1),
    (_report(PREFIX, {"failures": ["behavioural"]}), _error(OPERAND, "res://sim/fire/x.gd:1"), 1),
    (_report(PREFIX, {"failures": ["behavioural"]}), "", 0),
    (_report(PREFIX, {"failures": []}), "", 1),
])
def test_verdict_mutants_use_the_strict_classifier(stdout, stderr, code):
    from scripts.simulation.run_g3_positive_verdict_mutations import verdict_of
    verdict, payload, reason = verdict_of(stdout, stderr, code)
    assert verdict == "invalid" and payload == {} and reason


def test_only_a_behavioural_failure_kills_a_verdict_mutant():
    from scripts.simulation.run_g3_positive_verdict_mutations import verdict_of
    assert verdict_of(_report(PREFIX, {"failures": ["no write"]}), "", 1)[0] == "killed"
    assert verdict_of(_report(PREFIX, {"failures": []}) + "\n" + PREFIX + "_PASS", "", 0)[0] == "pass"


def test_reproduction_counts_only_when_the_forged_state_was_written():
    from scripts.simulation.run_g3_positive_verdict_mutations import REPRODUCTION_PREFIX, reproduction_verdict
    wrote = {"completed": True, "initialize_valid": True, "commit_valid": True, "restore_forged_valid": True,
             "budget_before": 900.0, "budget_after": 5000.0, "liquid_after": 0.25}
    assert reproduction_verdict(_report(REPRODUCTION_PREFIX, wrote), "", 0)[0] == "reproduced"
    kept = {**wrote, "restore_forged_valid": False, "budget_after": 900.0}
    assert reproduction_verdict(_report(REPRODUCTION_PREFIX, kept), "", 0)[0] == "not_reproduced"
    for stdout, stderr, code in [("", "", 0), (_report(REPRODUCTION_PREFIX, wrote), "SCRIPT ERROR", 0),
                                 (_report(REPRODUCTION_PREFIX, wrote), "", 1)]:
        assert reproduction_verdict(stdout, stderr, code)[0] == "invalid"


def test_abort_control_accepts_only_the_aborts_it_provokes():
    from scripts.simulation.run_g3_positive_verdict_mutations import abort_control_verdict
    passed = _report(ABORT_PREFIX, {"failures": [], "provoked_aborts": 2}) + "\n" + ABORT_PREFIX + "_PASS"
    provoked = _error(OPERAND, CONTROL_SITE + ":39") * 2
    assert abort_control_verdict(passed, provoked, 0, 39)[0] == "pass"
    # Wrong count, wrong line, another file, another error, a failing control or no error at all.
    assert abort_control_verdict(passed, _error(OPERAND, CONTROL_SITE + ":39"), 0, 39)[0] == "invalid"
    assert abort_control_verdict(passed, _error(OPERAND, CONTROL_SITE + ":40") * 2, 0, 39)[0] == "invalid"
    owner = _error(OPERAND, "res://sim/fire/PrescribedPhaseBudgetController.gd:157")
    assert abort_control_verdict(passed, _error(OPERAND, CONTROL_SITE + ":39") + owner, 0, 39)[0] == "invalid"
    other = _error("Invalid access to property or key 'x'.", CONTROL_SITE + ":39") * 2
    assert abort_control_verdict(passed, other, 0, 39)[0] == "invalid"
    assert abort_control_verdict(passed, "", 0, 39)[0] == "invalid"
    failing = _report(ABORT_PREFIX, {"failures": ["written"], "provoked_aborts": 2})
    assert abort_control_verdict(failing, provoked, 1, 39)[0] == "failed"
    assert abort_control_verdict("", provoked, 0, 39)[0] == "invalid"
