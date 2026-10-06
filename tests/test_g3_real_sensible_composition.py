"""Isolated composition: real n-heptane profiles + sensible ledger + atomic owner.

The Godot fixture executes the GDScript. Its expectations come from an
independent Python restatement of the step law (independent METHOD; the
property DATA are the same approved profiles), and the hand values below come
from printed source rows. Nothing here is taken from the owner under test.

REAL with limits: the two property profiles. DECLARED: the prototype reference
chemistry and latent heat, the prescribed release and heating. SYNTHETIC: the
independent budget B. Not a validated fire, not an evaporation prediction.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import struct

import pytest

from scripts.simulation import audit_g3_heptane_real_profile as real
from scripts.simulation import build_g3_real_sensible_composition as build
from tests.g3_identity_output import identity_payload

ROOT = Path(__file__).resolve().parents[1]
FIRE = ROOT / "sim/fire"
OWNER = FIRE / "PrescribedRealSensiblePhaseController.gd"
BASE = FIRE / "PrescribedSensiblePhaseController.gd"
LEDGER = FIRE / "FuelMassBudgetModel.gd"
ADAPTER = FIRE / "HeptaneRealCpProfiles.gd"
FIXTURE = ROOT / "tests/fixtures/g3_real_sensible_composition.gd"
PREFIX = "G3_REAL_SENSIBLE_COMPOSITION"
CHECKS = 3670  # Measured on the real fixture; never anticipated.
# Digest of 1985 synthetic ledger proposals and owner transactions, bit for bit,
# captured on commit 472705f1 BEFORE the ledger and the owner were touched.
SYNTHETIC_CHAIN = {"cases": 1985, "valid": 799, "rejected": 1186,
                   "sha256": "aa407250140841a203f4e3c07c415d6b24d2ca8d6338b0794b19b7ad9e2681c9"}
# Whole-file SHA-256 (LF) of commit 472705f1. Undoing this phase's edits textually
# must give these back: nothing else in the two shared modules may have changed.
BEFORE = {
    "FuelMassBudgetModel": "7ab01e1628441c048d55a45a512fc85aed8347dbd8140a29c98160e82fcd3f12",
    "PrescribedSensiblePhaseController": "63ea60420fa7a1995195addbc22e1fcfa4c30288b4fbb46174df44b120c01383",
}
NOW = {
    "FuelMassBudgetModel": "79a3e8e6995bb1f7635b1827e581e64e8d4c379b0323694a333ad5c10119d2a4",
    "PrescribedSensiblePhaseController": "0987d14c90568e18d81e76e847c5d9f807eeb0d05a57d999db2bc8dcde4b1770",
    "PrescribedRealSensiblePhaseController": "c2437cf71e05dcd642ca63105950081f981ff2aafd470fc94350f957f193b863",
}

_REAL_CONTRACTS = '''const RealProperties = preload("res://sim/fire/HeptaneRealCpProfiles.gd")
## Two closed sensible contracts over the SAME laws. They differ in the schema
## names, the property provider and the declared scope; neither accepts the
## other's state, material or profiles. In both, B and the reference chemistry
## are declared inputs: the real contract makes the properties real, not them.
const SENSIBLE_SYNTHETIC: Dictionary = {"state_schema": "g3_phase_sensible_state_v1",
	"material_schema": "g3_phase_sensible_material_v1", "result_schema": "g3_phase_sensible_budget_v1",
	"scope": "synthetic_isobaric_ledger_not_material_calibration", "real_properties": false}
const SENSIBLE_REAL: Dictionary = {"state_schema": "g3_phase_real_sensible_state_v1",
	"material_schema": "g3_phase_real_sensible_material_v1",
	"result_schema": "g3_phase_real_sensible_budget_v1",
	"scope": "real_limited_properties_declared_chemistry_synthetic_budget_not_fire_validation",
	"real_properties": true}
'''
_REAL_ENTRY = '''	return _phase_sensible(state, request, material, SENSIBLE_SYNTHETIC)


## Same ledger with the approved real n-heptane profiles as property provider.
## Prescribed heating and release, declared reference chemistry and a synthetic
## independent budget: not a validated fire and not an evaporation prediction.
static func propose_phase_sensible_real(state: Variant, request: Variant, material: Variant) -> Dictionary:
	return _phase_sensible(state, request, material, SENSIBLE_REAL)


static func _phase_sensible(state: Variant, request: Variant, material: Variant, contract: Dictionary) -> Dictionary:
	var properties: GDScript = RealProperties if contract["real_properties"] else SensibleProperties
'''
_OLD_RESULT = ('"schema": "g3_phase_sensible_budget_v1", '
               '"scope": "synthetic_isobaric_ledger_not_material_calibration",')
# (text now, text at 472705f1, occurrences now)
LEDGER_EDITS = [
    (_REAL_CONTRACTS, "", 1),
    (_REAL_ENTRY, "", 1),
    ('_sensible_literal(s, "schema", contract["state_schema"], errors)',
     '_sensible_literal(s, "schema", "g3_phase_sensible_state_v1", errors)', 1),
    ('_sensible_literal(m, "schema", contract["material_schema"], errors)',
     '_sensible_literal(m, "schema", "g3_phase_sensible_material_v1", errors)', 1),
    ("properties.validate_profile(", "SensibleProperties.validate_profile(", 1),
    ("properties.evaluate(", "SensibleProperties.evaluate(", 3),
    ('"schema": contract["result_schema"], "scope": contract["scope"],', _OLD_RESULT, 2),
    ("_sensible_rejected(contract, ", "_sensible_rejected(", 8),
    ("_sensible_account(properties, ", "_sensible_account(", 6),
    ("static func _sensible_account(properties: GDScript, mass: float",
     "static func _sensible_account(mass: float", 1),
    ("static func _sensible_rejected(contract: Dictionary, errors: Array[String])",
     "static func _sensible_rejected(errors: Array[String])", 1),
]
_HOOKS = '''## Names of this owner version. A versioned successor overrides these hooks
## (`_label`, `_ledger`, `_admits`, `_confirmed`) only; the transaction, the
## accounts and every check stay here.
func _label(name: String) -> String:
	return {"version": VERSION, "context": CONTEXT_SCHEMA, "seed": SEED_SCHEMA,
		"request": REQUEST_SCHEMA, "snapshot": SNAPSHOT_SCHEMA, "phase": PHASE_SCHEMA, "scope": SCOPE}[name]


func _ledger(state: Dictionary, request: Dictionary, material: Dictionary) -> Dictionary:
	return Budget.propose_phase_sensible(state, request, material)


## Acceptance of an owned state. v1 decides as it always did: nothing reported.
func _admits(value: Variant, context: Dictionary, errors: Array[String]) -> bool:
	_check_owned(value, context, errors)
	return errors.is_empty()


## Reading of a preview before the write. v1 reads its verdict as it always did.
func _confirmed(proposal: Dictionary) -> bool:
	return proposal["valid"]


'''
BASE_EDITS = [
    (_HOOKS, "", 1),
    ('const SCOPE: String = "isolated_synthetic_sensible_owner_not_evaporation_prediction_or_EOS"\n', "", 1),
    ('''		# No accepted v1 context holds these; the real profiles of a successor do.
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_NIL:
			return "null"
''', "", 1),
    ('''	if not _admits(candidate, canonical, errors):
		return _failure(errors)
	_context = canonical
''', '''	_check_owned(candidate, canonical, errors)
	if not errors.is_empty():
		return _failure(errors)
	_context = canonical
''', 1),
    ('''	var current: bool = _admits(_owned, _context, errors)
	var r: Dictionary = _object(''', '''	_check_owned(_owned, _context, errors)
	var r: Dictionary = _object(''', 1),
    ('''	if not current or not errors.is_empty():
		return _failure(errors)
''', '''	if not errors.is_empty():
		return _failure(errors)
''', 1),
    ('''	if not _admits(candidate, _context, errors):
		return _failure(errors)
	return {"valid": true,''', '''	_check_owned(candidate, _context, errors)
	if not errors.is_empty():
		return _failure(errors)
	return {"valid": true,''', 1),
    ('''	if not _confirmed(proposal):
		return proposal
''', '''	if not proposal["valid"]:
		return proposal
''', 1),
    ('''	var current: bool = _admits(_owned, _context, errors)
	var requested: bool = _admits(saved, _context, errors)
	if not current or not requested:
		return _failure(errors)
''', '''	_check_owned(_owned, _context, errors)
	_check_owned(saved, _context, errors)
	if not errors.is_empty():
		return _failure(errors)
''', 1),
    ('_literal(c.get("schema"), _label("context"), ', '_literal(c.get("schema"), CONTEXT_SCHEMA, ', 1),
    ('_literal(seed.get("schema"), _label("seed"), ', '_literal(seed.get("schema"), SEED_SCHEMA, ', 1),
    ('_literal(r.get("schema"), _label("request"), ', '_literal(r.get("schema"), REQUEST_SCHEMA, ', 1),
    ('_literal(s.get("schema"), _label("snapshot"), ', '_literal(s.get("schema"), SNAPSHOT_SCHEMA, ', 1),
    ('"schema": _label("snapshot"), "context_fingerprint"', '"schema": SNAPSHOT_SCHEMA, "context_fingerprint"', 1),
    ("var ledger: Dictionary = _ledger(before, {",
     "var ledger: Dictionary = Budget.propose_phase_sensible(before, {", 1),
    (" = _ledger(", " = Budget.propose_phase_sensible(", 4),
    ('''		"scope": _label("scope"),
		"controller_version": _label("version"),''',
     '''		"scope": "isolated_synthetic_sensible_owner_not_evaporation_prediction_or_EOS",
		"controller_version": VERSION,''', 1),
    ('''func _fingerprint(context: Dictionary) -> String:
	return (_label("version") + _serialize(context)).sha256_text()''',
     '''static func _fingerprint(context: Dictionary) -> String:
	return (VERSION + _serialize(context)).sha256_text()''', 1),
    ('''func _seed_phase(context: Dictionary) -> Dictionary:
	var mass: float = float(context["program"]["initial_mass_kg"])
	return {"schema": _label("phase"),''',
     '''static func _seed_phase(context: Dictionary) -> Dictionary:
	var mass: float = float(context["program"]["initial_mass_kg"])
	return {"schema": PHASE_SCHEMA,''', 1),
]


def _source(path: Path) -> str:
    return path.read_bytes().replace(b"\r\n", b"\n").decode("utf-8")


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _undo(source: str, edits) -> str:
    for now, before, count in edits:
        assert source.count(now) == count, (now[:70], source.count(now))
        source = source.replace(now, before)
    return source


def undo_real_contract_edits(source: str) -> str:
    """The ledger as it was at 472705f1: the second closed contract taken out."""
    reverted = _undo(source, LEDGER_EDITS)
    head = "static func propose_phase_sensible(state: Variant, request: Variant, material: Variant) -> Dictionary:\n"
    assert reverted.count(head) == 1
    return reverted


def undo_successor_hooks(source: str) -> str:
    """The synthetic owner as it was at 472705f1: the four hooks taken out."""
    return _undo(source, BASE_EDITS)


def _run(fixture, allowed=(0,)):
    from scripts import godot_monitored_launch
    from tests.godot_runtime_launcher import run_godot

    godot = Path(os.environ.get(
        "GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot executable unavailable")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0
    completed = run_godot([godot, "--headless", "--path", ROOT, "--script", ROOT / fixture],
                          timeout_s=300, allowed_exit_codes=allowed)
    assert "SCRIPT ERROR" not in completed.stdout + completed.stderr
    assert "Parse Error" not in completed.stdout + completed.stderr
    return completed


# --- the shared modules changed only in the declared edits ----------------------

def test_shared_modules_changed_only_in_the_declared_edits():
    ledger, base = _source(LEDGER), _source(BASE)
    assert _sha(ledger) == NOW["FuelMassBudgetModel"]
    assert _sha(base) == NOW["PrescribedSensiblePhaseController"]
    assert _sha(_source(OWNER)) == NOW["PrescribedRealSensiblePhaseController"]
    assert _sha(undo_real_contract_edits(ledger)) == BEFORE["FuelMassBudgetModel"]
    assert _sha(undo_successor_hooks(base)) == BEFORE["PrescribedSensiblePhaseController"]


def test_synthetic_chain_is_bit_identical_before_and_after():
    completed = _run("tests/fixtures/g3_sensible_chain_identity.gd")
    assert identity_payload(completed.stdout, completed.stderr, "G3_SENSIBLE_CHAIN_IDENTITY") == SYNTHETIC_CHAIN


def test_synthetic_entry_keeps_its_names_and_the_two_contracts_are_closed():
    ledger = _source(LEDGER)
    assert ledger.count("static func propose_phase_sensible(") == 1
    assert ledger.count("static func propose_phase_sensible_real(") == 1
    assert ledger.count("return _phase_sensible(state, request, material, SENSIBLE_SYNTHETIC)") == 1
    assert ledger.count("return _phase_sensible(state, request, material, SENSIBLE_REAL)") == 1
    assert len(re.findall(r"(?<!propose)_phase_sensible\(", ledger)) == 3  # the shared core and its two entries
    # One provider per contract, chosen by the contract and by nothing a caller passes.
    assert ledger.count("RealProperties") == 2 and ledger.count("contract[\"real_properties\"]") == 1
    for name in ["g3_phase_sensible_state_v1", "g3_phase_sensible_material_v1", "g3_phase_sensible_budget_v1",
                 "g3_phase_real_sensible_state_v1", "g3_phase_real_sensible_material_v1",
                 "g3_phase_real_sensible_budget_v1"]:
        assert ledger.count('"' + name + '"') == 1, name
    core = ledger.split("static func _phase_sensible(", 1)[1].split("static func _sensible_closed(", 1)[0]
    # No second integral, stoichiometry or balance: the core still calls the canonical laws once.
    for call, count in [("propose_phase_reference(", 1), ("_accepted_masses(", 1), ("_oxidation_quantities(", 1),
                        ("_mass_element_balance(", 1), ("_check_balance(", 5)]:
        assert core.count(call) == count, call
    for forbidden in ["integral", "0.5 *", "8.0 / 3.0", "11.0 / 3.0", "clamp", "molar_mass", "minf(sl", "maxf(sl"]:
        assert forbidden not in core, forbidden
    assert "real_properties" not in core.split("var errors", 1)[1]  # the contract never branches a law


# --- the oracle is fixed outside the candidate ----------------------------------

def test_generated_expectations_are_current():
    assert build.stale() == []


def test_oracle_shares_no_code_with_the_candidate():
    source = Path(build.__file__).read_text(encoding="utf-8")
    # The only GDScript it names is the fixture it writes its block into.
    assert ".gd" not in source.replace("tests/fixtures/g3_real_sensible_composition.gd", "")
    for forbidden in ["run_godot", "godot_monitored_launch", "subprocess", "sim/fire", "res://"]:
        assert forbidden not in source, forbidden


def test_declared_prototype_chemistry_is_labelled_and_keeps_two_mass_bases():
    material = build.reference_material()
    assert material["atom_mass_basis"] == "nominal_C12_H1_O16"
    assert material["mass_fractions"] == {"C": 0.84, "H": pytest.approx(0.16, abs=1e-15), "O": 0.0}
    assert "not a heptane calibration" in material["provenance"]
    # Per-kilogram heats on the tabulated 100.20 g/mol: 4464.88 / 4501.53 / 36.65 kJ/mol.
    assert material["liquid_heat_kj_kg"] == pytest.approx(4464.88 / 0.10020, rel=2e-6)
    assert material["vapour_heat_kj_kg"] == pytest.approx(4501.53 / 0.10020, rel=2e-6)
    assert material["phase_enthalpy_kj_kg"] == pytest.approx(36.65 / 0.10020, rel=2e-4)
    assert material["vapour_heat_kj_kg"] - material["liquid_heat_kj_kg"] == pytest.approx(
        material["phase_enthalpy_kj_kg"], abs=1e-9)
    expected = build.expectations()
    assert expected["molar_mass_g_mol"] == [100.2, 100.2] and expected["nominal_molar_mass_g_mol"] == 100.0
    # Complete oxidation of the NOMINAL C7H16: 11 O2 per fuel, 352 / 100 kg per kg.
    main = expected["sequences"]["main"]["steps"][1]["step"]
    assert main["o2_consumed_kg"] == pytest.approx(0.03 * 352.0 / 100.0, rel=1e-12)
    assert main["co2_kg"] == pytest.approx(0.03 * 7 * 44.0 / 100.0, rel=1e-12)
    assert main["water_vapour_kg"] == pytest.approx(0.03 * 8 * 18.0 / 100.0, rel=1e-12)


def test_oracle_hand_values():
    expected = build.expectations()
    sequences = expected["sequences"]
    material = build.reference_material()
    latent, vapour_heat = material["phase_enthalpy_kj_kg"], material["vapour_heat_kj_kg"]
    main = sequences["main"]["steps"]
    # Step 1: 0.05 kg leaves 1 kg of liquid holding -5 + 100 kJ; what stays keeps 95 kJ/kg.
    assert main[0]["step"]["accepted_release_kg"] == pytest.approx(0.05, rel=1e-12)
    assert main[0]["phase"]["liquid_sensible_kj"] == pytest.approx(0.95 * 95.0, rel=1e-12)
    emitted = main[0]["phase"]["vapour_sensible_kj"] / 0.05
    assert main[0]["step"]["release_cost_kj_kg"] == pytest.approx(latent + emitted - 95.0, rel=1e-12)
    assert main[0]["phase"]["thermal_budget_kj"] == pytest.approx(600.0 - 100.0 - 0.05 * (latent + emitted - 95.0))
    # Step 2 burns 0.03 kg of the mixture: Q takes the chemical heat and the mixture's own sensible.
    mixed = main[1]["step"]["mixed_specific_kj_kg"]
    assert main[1]["phase"]["deposited_heat_kj"] == pytest.approx(0.03 * (vapour_heat + mixed), rel=1e-12)
    assert main[1]["step"]["temperature_average_specific_kj_kg"] < mixed - 0.5  # Cp grows with T
    # Zero duration: nothing prescribed is applied. Then the vapour is all burnt.
    assert main[2]["step"] == {"no_op": True} and main[2]["phase"] == main[1]["phase"]
    assert main[3]["phase"]["vapour_fuel_kg"] == 0.0 and main[3]["phase"]["vapour_sensible_kj"] == 0.0
    # Heating a phase that is not there is refused; the ramp then gives 0.05 + 0.5*0.05*4 kg.
    assert main[4]["accepted"] is False and main[4]["phase"] == main[3]["phase"]
    assert main[5]["step"]["requested_release_kg"] == pytest.approx(0.15, rel=1e-12)
    assert main[5]["step"]["source_dt_s"] == 5.0 and main[5]["step"]["physical_dt_s"] == 6.0
    for row in main:
        assert row["accounts"]["total_kj"] == pytest.approx(material["liquid_heat_kj_kg"] - 5.0 + 600.0, abs=1e-9)
    capped = sequences["budget_limited"]["steps"]
    assert capped[0]["phase"]["thermal_budget_kj"] == 0.0
    assert capped[0]["step"]["accepted_release_kg"] == pytest.approx(
        10.0 / capped[0]["step"]["release_cost_kj_kg"], rel=1e-12)
    assert capped[3]["step"]["accepted_release_kg"] == 0.0 and capped[3]["phase"]["deposited_heat_kj"] > 900.0
    assert capped[4]["accepted"] is False
    starved = sequences["oxygen_limited"]["steps"]
    assert starved[0]["step"]["accepted_oxidation_kg"] == pytest.approx(0.05 / 3.52, rel=1e-12)
    assert starved[0]["phase"]["o2_kg"] == 0.0 and starved[1]["step"]["accepted_oxidation_kg"] == 0.0
    cold, hot = sequences["history_cold"]["steps"][-1]["phase"], sequences["history_hot"]["steps"][-1]["phase"]
    for key in ["liquid_fuel_kg", "vapour_fuel_kg", "o2_kg"]:
        assert cold[key] == hot[key]
    assert hot["liquid_sensible_kj"] - cold["liquid_sensible_kj"] > 100.0
    assert hot["thermal_budget_kj"] < cold["thermal_budget_kj"] - 100.0
    assert [row["accepted"] for row in sequences["support"]["steps"]] == [False, False, True, False, False, True]
    gone = sequences["exhaust"]["steps"]
    assert gone[1]["phase"]["liquid_fuel_kg"] == 0.0 and gone[1]["liquid_kinds"] == []
    assert gone[2]["accepted"] is False and gone[3]["step"]["release_cost_kj_kg"] == latent
    tiny = sequences["small_mass"]["steps"]
    assert tiny[0]["step"]["accepted_release_kg"] == pytest.approx(5.0e-11, rel=1e-12)
    assert tiny[1]["phase"]["vapour_fuel_kg"] == 0.0


def test_analytic_case_agrees_with_printed_source_rows():
    """Printed H columns of the source tables, independent of both implementations."""
    analytic = build.expectations()["analytic"]
    h_liquid, h_next, h_gas = analytic["knot_enthalpies_kj_kg"]
    assert (analytic["liquid_knot_k"], analytic["next_liquid_knot_k"], analytic["gas_knot_k"]) == (
        pytest.approx(330.0, abs=0.04), pytest.approx(340.0, abs=0.04), pytest.approx(400.0, abs=0.04))
    # Gas: H(400) - H(298.16) = 108350 - 89219 J/mol; the reference sits 0.0145 K above 298.16.
    assert h_gas == pytest.approx((108350 - 89219 - 2.39) / 100.20, abs=0.06)
    # Liquid along saturation: H(330) - H(298.16) = 59952 - 52596 and H(340) = 62349 J/mol,
    # minus 0.0145 K at 2.244 kJ/(kg*K). The isobaric conversion moves it by a few hundredths.
    assert h_liquid == pytest.approx((59952 - 52596) / 100.20 - 0.0325, abs=0.05)
    assert h_next == pytest.approx((62349 - 52596) / 100.20 - 0.0325, abs=0.05)
    latent = build.reference_material()["phase_enthalpy_kj_kg"]
    first, second = analytic["steps"]
    assert first["release_cost_kj_kg"] == pytest.approx(latent + h_gas - h_liquid, rel=1e-14)
    assert first["release_cost_kj_kg"] == pytest.approx(365.77 + 190.90 - 73.38, abs=0.1)
    assert second["release_cost_kj_kg"] == pytest.approx(365.77 + 190.90 - 97.30, abs=0.1)
    assert second["request"][2] == pytest.approx(0.95 * (h_next - h_liquid), rel=1e-14)
    assert first["total_kj"] == second["total_kj"]
    for step in analytic["steps"]:
        phase = step["phase"]
        total = (step["potential_a_kj"] + phase["liquid_sensible_kj"] + phase["vapour_sensible_kj"]
                 + phase["thermal_budget_kj"] + phase["deposited_heat_kj"])
        assert total == pytest.approx(step["total_kj"], abs=1e-9)
    # The shared restatement and the stand-alone trapezoid sum agree to the last digits.
    content = build.profiles.approved_content()
    assert h_gas == pytest.approx(real.canonical_enthalpy(content[build.GAS]["samples"], analytic["gas_knot_k"]),
                                  rel=1e-14)


# --- the real GDScript -----------------------------------------------------------

def _leaves(value, path=()):
    if isinstance(value, dict):
        for key in value:
            yield from _leaves(value[key], path + (key,))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from _leaves(item, path + (index,))
    else:
        yield path, value


def _rebuilt(listed):
    """The context Godot held, from its leaves; numbers from their eight bytes."""
    root = {}
    for path, (kind, text) in listed:
        value = {"f64": lambda: struct.unpack("<d", bytes.fromhex(text))[0], "text": lambda: text,
                 "bool": lambda: text == "true", "null": lambda: None}[kind]()
        holder = root
        for key, following in zip(path, path[1:] + [None]):
            key = int(key) if isinstance(key, float) else key
            if following is None:
                if isinstance(holder, list):
                    assert key == len(holder)
                    holder.append(value)
                else:
                    holder[key] = value
                break
            empty = [] if isinstance(following, (int, float)) else {}
            if isinstance(holder, list):
                if key == len(holder):
                    holder.append(empty)
                holder = holder[key]
            else:
                holder = holder.setdefault(key, empty)
    return root


def test_real_gdscript_k01_k14():
    completed = _run("tests/fixtures/g3_real_sensible_composition.gd")
    lines = [line for line in completed.stdout.splitlines() if line.startswith(PREFIX + " {")]
    assert len(lines) == 1, completed.stdout + completed.stderr
    payload = json.loads(lines[0].split(" ", 1)[1])
    assert payload["failures"] == []
    assert payload["groups"] == [f"K{i:02}" for i in range(1, 15)]
    assert payload["checks"] == CHECKS
    assert PREFIX + "_PASS" in completed.stdout
    seen = payload["observations"]
    expected = build.expectations()
    analytic = expected["analytic"]
    material = build.reference_material()
    total = material["liquid_heat_kj_kg"] + analytic["knot_enthalpies_kj_kg"][0] + 600.0
    assert seen["analytic_total_1.0"] == pytest.approx(total, abs=1e-9)
    assert seen["analytic_total_2.0"] == pytest.approx(total, abs=1e-9)
    assert seen["mixing_rows_where_a_temperature_average_differs"] >= 3
    # Identity: equal exactly when the declared context is equal.
    identities, sequences = seen["identities"], expected["sequences"]
    assert set(identities) == set(sequences)
    assert all(re.fullmatch(r"[0-9a-f]{64}", value) for value in identities.values())
    for a in sequences:
        for b in sequences:
            assert (identities[a] == identities[b]) == (sequences[a]["context"] == sequences[b]["context"]), (a, b)
    assert len(set(identities.values())) == 9  # three sequences share the seed of `support`
    # Recomputed outside Godot from the content it held: sorted keys, IEEE-754 bits, version prefix.
    context = _rebuilt(seen["main_context_leaves"])
    assert build.fingerprint(context) == identities["main"]
    assert seen["identity_leaves"] == len(seen["main_context_leaves"])
    # That content is the declared context plus the two approved profiles, leaf by leaf.
    content = build.profiles.approved_content()
    declared = json.loads(json.dumps(sequences["main"]["context"]))
    declared["material"]["liquid_profile"] = content[build.LIQUID]
    declared["material"]["vapour_profile"] = content[build.GAS]
    ours, theirs = dict(_leaves(declared)), dict(_leaves(context))
    assert set(ours) == set(theirs) and len(ours) == len(seen["main_context_leaves"])
    for path, value in ours.items():
        if isinstance(value, float):
            # Godot does not always round a decimal literal as Python does: a few ulps.
            assert theirs[path] == pytest.approx(value, rel=1e-15, abs=1e-300), path
        else:
            assert theirs[path] == value and type(theirs[path]) is type(value), path
    assert sum(value is None for value in ours.values()) >= 3 and sum(value is False for value in ours.values()) >= 5


def test_fixture_takes_its_numbers_from_the_generated_block():
    source = FIXTURE.read_text(encoding="utf-8")
    begin, end = build.BEGIN.format(name=build.NAME), build.END.format(name=build.NAME)
    code = source.split(begin)[0] + source.split(end)[1]
    assert code.count("EXPECTED") >= 15
    # No expected energy is typed by hand next to the checks.
    assert re.findall(r"\b\d{3,}\.\d{3,}\b", code) == []
    for call in ["Owner.new()", "Budget.propose_phase_sensible_real(", "Mute.new()", "Loose.new()"]:
        assert call in code


# --- isolation, labels and the positive verdict ----------------------------------

def _product_resources():
    for folder in ["sim", "editor", "ui", "view", "scenes", "scenarios", "tools", "addons", "demo"]:
        for path in (ROOT / folder).rglob("*"):
            if path.is_file() and path.suffix in {".gd", ".tscn", ".tres", ".json", ".cfg"}:
                yield path
    yield ROOT / "Main.gd"
    yield ROOT / "project.godot"


def test_composition_is_not_loaded_by_engine_editor_scenarios_or_product():
    allowed = {
        "PrescribedRealSensiblePhaseController": {OWNER},
        "propose_phase_sensible_real": {LEDGER, OWNER},
        "HeptaneRealCpProfiles": {ADAPTER, LEDGER, OWNER},
        "g3_phase_real_sensible": {LEDGER, OWNER},
        "g3_prescribed_real_sensible": {OWNER},
    }
    texts = {path: path.read_text(encoding="utf-8", errors="replace") for path in _product_resources()
             if path.exists()}
    for token, files in allowed.items():
        users = {path for path, text in texts.items() if token in text}
        assert users <= files, (token, sorted(str(path.relative_to(ROOT)) for path in users - files))
        # The owner never names itself (it only `extends` its parent): nobody names it at all.
        assert users or token == "PrescribedRealSensiblePhaseController", token
    for name in ["SimulationEngine.gd", "CombustionSystem.gd"]:
        for path in (ROOT / "sim").rglob(name):
            text = path.read_text(encoding="utf-8", errors="replace")
            assert "FuelMassBudgetModel" not in text and "Prescribed" not in text, path.name


def test_owner_is_a_thin_successor_that_adds_no_law():
    source = _source(OWNER)
    assert source.startswith('extends "res://sim/fire/PrescribedSensiblePhaseController.gd"\n')
    assert re.findall(r'preload\("([^"]+)"\)', source) == ["res://sim/fire/HeptaneRealCpProfiles.gd"]
    assert re.findall(r"^var (\w+)", source, re.M) == []  # no state of its own: one inherited root
    assert re.search(r"^\t+_owned\b[^\n]*[^=!<>]=(?!=)", source, re.M) is None
    assert re.search(r"^\t+_context\b[^\n]*[^=!<>]=(?!=)", source, re.M) is None
    functions = re.findall(r"^(?:static )?func (\w+)\(", source, re.M)
    assert functions == ["_label", "_ledger", "_admits", "_confirmed", "_positive", "_failure", "preview_step",
                         "commit_step", "restore", "_report", "_phase_evidence"]
    assert source.count("super._failure(") == 2
    assert source.count("super.preview_step(request)") == 1
    assert source.count("super.commit_step(request, expected_generation)") == 1
    assert source.count("super.restore(saved, expected_generation)") == 1
    assert source.count("super._report()") == 1
    assert source.count("Budget.propose_phase_sensible_real(state, request, material)") == 1
    # No integral, stoichiometry, balance, tolerance, clipping or cooling of its own.
    for forbidden in ["integral", "cp_kj_kg_k", "mass_fractions", "8.0 / 3.0", "11.0 / 3.0", "clamp",
                      "_check_balance", "_compare(", "phase_enthalpy_kj_kg", "liquid_heat_kj_kg",
                      "vapour_heat_kj_kg", "FileAccess", "@export", "await ", "signal ", "extends Node",
                      "get_tree", "_enabled", "class_name", "SimulationEngine.", "print("]:
        assert forbidden not in source, forbidden
    assert re.findall(r"(?<!pre)load\(", source) == []
    assert re.search(r"1(?:\.0)?e-\d+", source) is None
    # Every flag it adds is false, and none it inherits is overridden.
    flags = re.findall(r'\[?"(\w*(?:approval|activation|integration)\w*)"\]? ?[:=] (\w+)', source)
    assert flags == [("co_fed_approval", "false"), ("fire_validation_approval", "false")]
    # Every `true` of the code, reviewed: the gate's only acceptance, the prescribed-temperature
    # label, the adapter-approved mark and a deep-copy argument.
    code = [line for line in source.splitlines() if not line.lstrip().startswith("#")]
    assert [line for line in code if re.search(r"\btrue\b", line)] == [
        "\t\treturn true", '\t\t"temperature_is_prescribed_not_predicted": true,',
        '\tevidence["approved_profile"] = true',
        '\tevidence["declared_errors"] = profile["declared_errors"].duplicate(true)']
    for label in ["real_limited_primary_source_property",
                  "declared_prototype_reference_nominal_CHO_not_heptane_calibration",
                  "prescribed_input_not_predicted_evaporation", "prescribed_input_per_step",
                  '"thermal_budget": BOUNDARY_KIND', '"mass_bases_reconciled": false',
                  '"total_uncertainty_quantified": false', '"temperature_inferred": false',
                  'if not _positive(Real.validate_profile(profile)):']:
        assert source.count(label) == 1, label
    for name in ["prescribed_real_sensible_phase_controller_v1", "g3_prescribed_real_sensible_context_v1",
                 "g3_prescribed_real_sensible_seed_v1", "g3_prescribed_real_sensible_request_v1",
                 "g3_prescribed_real_sensible_snapshot_v1", "g3_phase_real_sensible_state_v1"]:
        assert source.count('"' + name + '"') == 1, name
    assert "synthetic_independent_initial_budget" not in source  # inherited, never restated or renamed


def test_positive_verdict_is_decided_from_a_return_value_not_from_silence():
    source = _source(OWNER)
    admits = source.split("func _admits(", 1)[1].split("\n\n\n", 1)[0]
    assert "var audit: Variant = _check_owned(value, context, errors)" in admits
    assert "if errors.size() == reported and _positive(audit):\n\t\treturn true" in admits
    assert admits.count("return true") == 1 and admits.rstrip().endswith("return false")
    positive = source.split("static func _positive(", 1)[1].split("\n\n\n", 1)[0]
    assert 'typeof(result.get("valid")) == TYPE_BOOL' in positive and 'result["valid"]' in positive
    base = _source(BASE)
    # The synthetic owner still decides as before; this phase did not change its rule by analogy.
    assert "func _admits(value: Variant, context: Dictionary, errors: Array[String]) -> bool:\n" \
           "\t_check_owned(value, context, errors)\n\treturn errors.is_empty()\n" in base
    assert 'func _confirmed(proposal: Dictionary) -> bool:\n\treturn proposal["valid"]\n' in base
    # Every acceptance and the write go through the two hooks.
    assert base.count("_admits(") == 6 and base.count("_check_owned(") == 2
    assert base.count("_confirmed(") == 2
    assert len(re.findall(r"^\t+_owned = ", base, re.M)) == 3


def test_predeclared_mutations_cover_the_composition():
    from scripts.simulation import run_g3_real_sensible_composition_mutations as campaign

    sources = {path: path.read_text(encoding="utf-8") for path in campaign.TARGETS}
    variants = campaign.prepared_variants(sources)
    assert len(variants) == campaign.DECLARED == len(campaign.MUTATIONS) + len(campaign.oracle_controls())
    assert all(text != sources[path] for path, text in variants.values())
    assert len({(path, text) for path, text in variants.values()}) == campaign.DECLARED
    families = {name[0] for name in variants}
    assert families == {"L", "B", "C", "F"}  # ledger, base owner, composition owner, fixture controls
    needed = {ROOT / "sim/fire" / name for name in [
        "FuelMassBudgetModel.gd", "PrescribedFuelReleaseModel.gd", "SensibleEnthalpyModel.gd",
        "HeptaneRealCpProfiles.gd", "PrescribedSensiblePhaseController.gd",
        "PrescribedRealSensiblePhaseController.gd"]}
    assert needed | {FIXTURE} == set(campaign.ASSETS)
    assert campaign.PREFIX == PREFIX


@pytest.mark.parametrize("stdout, stderr, code", [
    ("", "", 1), (PREFIX + ' {"failures":["wrong"]}', "Parse Error", 1),
    (PREFIX + ' {"failures":["wrong"]}', "SCRIPT ERROR", 1),
    (PREFIX + ' {"failures":["wrong"]}', "", -1),
])
def test_infrastructure_errors_are_not_killed_mutants(stdout, stderr, code):
    from scripts.simulation.run_g3_fuel_mass_budget_mutations import classify

    with pytest.raises(RuntimeError):
        classify(stdout, stderr, code, PREFIX)
