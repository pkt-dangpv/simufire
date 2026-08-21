"""Structural contracts for the H3.2b2 pure residual projection primitive.

H3.2b2 creates a primitive and wires it nowhere. These contracts pin the
properties that make that claim checkable rather than asserted:

* the equation of state is the CANONICAL one -- the same reference constants as
  `Phase3CoupledPressureSolver`, reproduced rather than imported, so this file
  is not a second definition of air;
* no `valid: true` result may contain NaN or INF anywhere, and an absent zone
  omits the fields that have no meaning for it rather than filling them;
* a one-zone interface is an EXACT geometric boundary, not a rounded quantity;
* purity -- static functions only, no member state, no external write;
* zero call sites anywhere in the repository;
* geometry derived FROM the inventories, never the inventories from geometry;
* the right-prism assumption stated in the API rather than hidden inside it;
* an explicit, ordered validity contract with fail-closed reason codes;
* the thermal limit is NOT applied here -- H3.2b5 owns it;
* the volume-closure bound is derived from floating-point arithmetic, not from
  a physical tolerance and not fitted to make the fixture pass;
* no forbidden vocabulary and no scenario-configurable constant.
"""

from pathlib import Path
import re
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]
PRIMITIVE_PATH = ROOT / "sim/core/Phase3ResidualProjection.gd"
FIXTURE_PATH = ROOT / "tests/fixtures/phase3_h32b2_residual_projection.gd"
SOURCE = PRIMITIVE_PATH.read_text(encoding="utf-8")
FIXTURE = FIXTURE_PATH.read_text(encoding="utf-8")
SOLVER = (ROOT / "sim/core/ZoneFireSolver.gd").read_text(encoding="utf-8")
COUPLED = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(encoding="utf-8")


def _strip_comments(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )


CODE = _strip_comments(SOURCE)


def _func(text: str, name: str) -> str:
    return text.split("func %s(" % name, 1)[1].split("\nstatic func ", 1)[0]


def _fixture_func(name: str) -> str:
    return FIXTURE.split("func %s(" % name, 1)[1].split("\nfunc ", 1)[0]


# --------------------------------------------------------------------------
# The canonical equation of state
# --------------------------------------------------------------------------

def test_no_second_definition_of_air_is_introduced():
    # The first issue of this primitive hard-coded a dry-air specific gas
    # constant of 287.052874, which manufactured a 345.5 Pa disagreement with
    # the canonical solver out of nothing.
    # Banned in code. The comment block that records the correction names the
    # old value deliberately, and that note must survive.
    assert "AIR_R_SPECIFIC_J_KG_K" not in CODE
    assert "287.052874" not in CODE
    assert not re.search(r"const\s+\w*GAS_CONSTANT\w*\s*:", SOURCE)
    assert "287.052874" in SOURCE, "the superseded value stays on the record"


def test_reference_constants_are_exactly_the_canonical_ones():
    for line in ("const AIR_PRESSURE_REF_PA: float = 101325.0",
                 "const AIR_DENSITY_REF_KG_M3: float = 1.2"):
        assert line in SOURCE, line
        assert line in COUPLED, "the canonical solver must carry the same value"
    assert "const AIR_CP_KJ_KG_K: float = 1.0" in SOURCE
    assert "const AIR_CP_KJ_KG_K: float = 1.0" in SOLVER
    assert "const AIR_CP_KJ_KG_K: float = 1.0" in COUPLED


def test_gas_constant_is_derived_per_call_the_canonical_way():
    body = _func(SOURCE, "derive")
    assert "var reference_temp_k: float = ambient_temp_c + KELVIN_OFFSET_C" in body
    assert "AIR_PRESSURE_REF_PA \\" in body
    assert "/ (AIR_DENSITY_REF_KG_M3 * reference_temp_k)" in body
    # The canonical solver derives it the same way.
    assert "AIR_PRESSURE_REF_PA \\" in COUPLED
    assert "/ (AIR_DENSITY_REF_KG_M3 * reference_temp_k)" in COUPLED
    # It depends on ambient, so it is not presented as a universal constant.
    assert "not a universal constant" in SOURCE


def test_the_primitive_stays_autonomous_and_does_not_import_the_solver():
    # Same convention, reproduced -- never called or imported.
    assert "Phase3CoupledPressureSolver" not in CODE
    for forbidden in ("preload(", "load(", "extends Phase3"):
        assert forbidden not in CODE, forbidden


def test_the_ambient_identity_is_stated_and_proved_in_the_source():
    assert "THE AMBIENT IDENTITY" in SOURCE
    assert "AIR_PRESSURE_REF_PA" in SOURCE.split("THE AMBIENT IDENTITY", 1)[1][:600]


def test_the_ambient_bound_is_derived_not_fitted():
    assert "const AMBIENT_PRESSURE_ROUNDING_BUDGET: int = 8" in SOURCE
    rationale = SOURCE.split("## Rounding budget for the ambient identity", 1)[1]
    rationale = rationale.split("const AMBIENT", 1)[0]
    assert "six roundings" in rationale
    assert "exact in real arithmetic" in rationale


def test_pressure_and_density_follow_the_stated_equations():
    body = _func(SOURCE, "derive")
    assert "(gas_constant / room_volume_m3) * mass_temperature_sum" in body
    assert "pressure_abs_pa / (gas_constant * upper_temp_k)" in body
    assert "pressure_abs_pa / (gas_constant * lower_temp_k)" in body
    assert "upper_mass_kg / upper_density_kg_m3" in body


def test_temperature_uses_the_engine_convention_and_constant():
    body = _func(SOURCE, "derive")
    assert "reference_temp_k \\" in body
    assert "+ upper_energy_kj / (upper_mass_kg * AIR_CP_KJ_KG_K)" in body
    assert "+ lower_energy_kj / (lower_mass_kg * AIR_CP_KJ_KG_K)" in body


def test_the_closure_proof_is_written_down_and_holds_for_any_gas_constant():
    assert "V_upper + V_lower = (K/p) * (p * V_room / K) = V_room" in SOURCE
    assert "for ANY value of `K`" in SOURCE


# --------------------------------------------------------------------------
# No NaN or INF in a valid result
# --------------------------------------------------------------------------

def test_nan_appears_only_in_the_fallible_auxiliary_helper():
    helper = _func(SOURCE, "floor_area_from_volume_m2")
    assert "return NAN" in helper
    # Nowhere else in the file.
    rest = CODE.replace(_strip_comments(helper), "")
    assert "NAN" not in rest


def test_the_fallible_helper_is_documented_as_such():
    helper = _func(SOURCE, "floor_area_from_volume_m2")
    assert "FALLIBLE AUXILIARY API, not a result" in helper
    assert "is_nan()" in helper


def test_absent_zone_omits_the_fields_that_have_no_meaning():
    body = _func(SOURCE, "_zone")
    absent_block = body.split("if not present:", 1)[1].split("return {", 1)[1]
    absent_block = absent_block.split("}", 1)[0]
    for forbidden in ("temperature_k", "density_kg_m3"):
        assert forbidden not in absent_block, forbidden
    for required in ('"present": false', '"mass_kg": 0.0',
                     '"energy_kj": 0.0', '"volume_m3": 0.0'):
        assert required in absent_block, required


def test_present_zone_always_carries_both_derived_fields():
    body = _func(SOURCE, "_zone")
    present_block = body.rsplit("return {", 1)[1]
    for required in ('"present": true', '"temperature_k": temperature_k',
                     '"density_kg_m3": density_kg_m3', '"volume_m3": volume_m3'):
        assert required in present_block, required


def test_a_present_zone_is_checked_finite_and_positive_before_emission():
    body = _func(SOURCE, "_present_zone_is_sound")
    assert "not is_finite(temperature_k) or temperature_k <= 0.0" in body
    assert "not is_finite(density_kg_m3) or density_kg_m3 <= 0.0" in body
    assert "not is_finite(volume_m3)" in body
    caller = _func(SOURCE, "derive")
    assert caller.count("_present_zone_is_sound(") == 2
    assert "return _invalid(REASON_NON_FINITE_RESULT)" in caller


def test_an_invalid_result_carries_no_derived_field():
    body = _strip_comments(_func(SOURCE, "_invalid"))
    for forbidden in ("pressure", "temperature_k", "density", "volume_m3",
                      "interface", "gas_constant", "reference_temp"):
        assert forbidden not in body, forbidden
    assert '"valid": false' in body
    # And nothing non-finite either: the only numbers are exact zeros.
    assert "NAN" not in body and "INF" not in body


# --------------------------------------------------------------------------
# Exact one-zone interface
# --------------------------------------------------------------------------

def test_one_zone_interface_is_exact_by_construction():
    body = _func(SOURCE, "derive")
    branch = body.split("# INTERFACE.", 1)[1]
    assert "if not upper_present:" in branch
    assert "interface_height_m = room_height_m" in branch
    assert "interface_raw_m = room_height_m" in branch
    assert "elif not lower_present:" in branch
    assert "interface_height_m = 0.0" in branch
    assert "interface_raw_m = 0.0" in branch
    # The exact branches must not round, clamp or approximate.
    exact_part = branch.split("else:", 1)[0]
    for forbidden in ("clampf", "snapped", "round(", "is_equal_approx"):
        assert forbidden not in exact_part, forbidden


def test_the_exact_boundary_corrects_no_mass_or_energy():
    body = _func(SOURCE, "derive")
    branch = body.split("# INTERFACE.", 1)[1].split("else:", 1)[0]
    for forbidden in ("mass_kg =", "energy_kj =", "volume_m3 ="):
        assert forbidden not in branch, forbidden
    assert "corrects no mass and no energy" in SOURCE


def test_interface_uses_the_canonical_lower_depth_form():
    body = _func(SOURCE, "derive")
    assert "interface_raw_m = lower_volume_m3 / floor_area_m2" in body
    # Same form as the canonical solver.
    assert "lower_volume_m3 / floor_area_m2" in COUPLED
    assert "algebraically identical to" in SOURCE


def test_the_two_zone_interface_is_still_bounded_and_fails_closed():
    body = _func(SOURCE, "derive")
    branch = body.split("# INTERFACE.", 1)[1].split("else:", 1)[1]
    assert "DOUBLE_EPSILON * room_height_m" in branch
    assert "return _invalid(REASON_INTERFACE_OUT_OF_BUDGET)" in branch
    assert "clampf(interface_raw_m, 0.0, room_height_m)" in branch


def test_the_only_clamp_is_the_two_zone_interface_projection():
    body = _func(SOURCE, "derive")
    assert len(re.findall(r"clampf\(", body)) == 1


# --------------------------------------------------------------------------
# Purity
# --------------------------------------------------------------------------

def test_every_function_is_static():
    for line in SOURCE.splitlines():
        if line.startswith("func ") or line.startswith("\tfunc "):
            raise AssertionError("non-static function: %s" % line)
    assert "static func derive(" in SOURCE


def test_there_is_no_member_state():
    for line in CODE.splitlines():
        if line.startswith("var ") or line.startswith("@export") \
                or line.startswith("@onready") or line.startswith("signal "):
            raise AssertionError("member state: %s" % line)
        assert not line.strip().startswith("static var"), line


def test_no_class_name_registration():
    assert "class_name" not in CODE


def test_no_external_writes_and_no_engine_coupling():
    for forbidden in ("RoomModel", "BuildingModel", "SimulationEngine",
                      "ZoneFireSolver", "ThermalSystem", "GasExchangeSystem",
                      "HVACSystem", "get_node", "get_tree", "Engine.",
                      "ProjectSettings"):
        assert forbidden not in CODE, forbidden


def test_returns_a_fresh_dictionary_and_mutates_no_argument():
    body = _func(SOURCE, "derive")
    for arg in ("upper_mass_kg", "upper_energy_kj", "lower_mass_kg",
                "lower_energy_kj", "floor_area_m2", "room_height_m",
                "ambient_temp_c"):
        assert not re.search(r"^\s*%s\s*[-+*/]?=[^=]" % arg, body, re.M), arg


# --------------------------------------------------------------------------
# Zero call sites
# --------------------------------------------------------------------------

## UPDATED 2026-08-20 by H3.2b3. H3.2b2 shipped with zero consumers anywhere.
## H3.2b3 adds the first one, and it is the read-only shadow the H3.2b0 plan
## always intended. The gate is therefore tightened rather than loosened: the
## shadow is named explicitly, and the contract below still forbids any OTHER
## consumer under sim/ -- in particular any call site that would let the
## primitive's output reach room state.
SHADOW_CONSUMER = "sim/core/Phase3ResidualProjectionShadow.gd"

ALLOWED_REFERENCES = {
    "sim/core/Phase3ResidualProjection.gd",
    SHADOW_CONSUMER,
    "tests/fixtures/phase3_h32b2_residual_projection.gd",
    "tests/test_phase3_h32b2_residual_projection.py",
    "tests/fixtures/phase3_h32b3_residual_projection_shadow.gd",
    "tests/test_phase3_h32b3_residual_projection_shadow.py",
    "CHANGELOG.md",
    "docs/HANDOFF_CURRENT_STATE.md",
    "docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md",
    "docs/validation/PHASE3_H32B2_RESIDUAL_PROJECTION_PRIMITIVE.md",
    "docs/validation/PHASE3_H32B3_SHADOW_COMPARE.md",
    "docs/validation/PHASE3_H32B_RESIDUAL_PROJECTION_DESIGN.md",
}


def _git_grep(pattern):
    proc = subprocess.run(
        ["git", "grep", "-l", "--untracked", pattern],
        cwd=ROOT, capture_output=True, text=True,
    )
    if proc.returncode not in (0, 1):
        pytest.skip("git unavailable in this environment")
    return {line.strip().replace("\\", "/")
            for line in proc.stdout.splitlines() if line.strip()}


def _references_the_primitive(path: str) -> bool:
    """True if the file names the PRIMITIVE, not merely the shadow.

    `Phase3ResidualProjectionShadow` contains the primitive's name as a
    substring, so a plain search cannot tell "wires the shadow" apart from
    "calls the primitive". The engine does the former and must never do the
    latter.
    """
    text = (ROOT / path).read_text(encoding="utf-8", errors="ignore")
    return "Phase3ResidualProjection" in text.replace("Phase3ResidualProjectionShadow", "")


def test_the_only_consumer_is_the_read_only_shadow():
    tracked = _git_grep("Phase3ResidualProjection")
    unexpected = tracked - ALLOWED_REFERENCES - {"sim/core/SimulationEngine.gd"}
    assert not unexpected, "unexpected reference: %s" % sorted(unexpected)
    # Exactly one thing under sim/ calls the primitive, and it is the shadow.
    consumers = {q for q in tracked
                 if q.startswith("sim/")
                 and q != "sim/core/Phase3ResidualProjection.gd"
                 and _references_the_primitive(q)}
    assert consumers == {SHADOW_CONSUMER}, sorted(consumers)
    # The engine wires the shadow but never touches the primitive itself.
    assert not _references_the_primitive("sim/core/SimulationEngine.gd")
    # And that one consumer never writes room state with what it derives. The
    # ban is on the code; the doc comment saying it never touches a RoomModel
    # must survive.
    shadow = (ROOT / SHADOW_CONSUMER).read_text(encoding="utf-8")
    assert "RoomModel" not in _strip_comments(shadow)
    assert '"shadow_applied": false' in shadow
    # --untracked is required: a call site added in a new, not-yet-committed
    # file would be invisible to a plain `git grep` and this gate would pass
    # vacuously.
    assert "tests/fixtures/phase3_h32b2_residual_projection.gd" in tracked


def test_only_the_shadow_and_tests_load_the_primitive():
    loaders = _git_grep("Phase3ResidualProjection.gd")
    for path in loaders:
        assert path in ALLOWED_REFERENCES, path
        if path.startswith("sim/"):
            assert path in {"sim/core/Phase3ResidualProjection.gd",
                            SHADOW_CONSUMER}, path
    # Only the shadow preloads it under sim/.
    assert SHADOW_CONSUMER in loaders


def test_no_flag_is_introduced():
    assert "@export" not in SOURCE
    for name in ("enabled", "_enabled", "phase3_residual_projection"):
        assert "var %s" % name not in CODE


# --------------------------------------------------------------------------
# Geometry: stated, not hidden
# --------------------------------------------------------------------------

def test_geometry_is_an_explicit_argument_not_an_inference():
    body = _func(SOURCE, "derive")
    assert "floor_area_m2: float" in SOURCE
    assert "room_height_m: float" in SOURCE
    assert "floor_area_m2 * room_height_m" in body


def test_the_constant_cross_section_assumption_is_documented():
    assert "CONSTANT" in SOURCE and "HORIZONTAL CROSS-SECTION" in SOURCE
    assert "width_m" in SOURCE and "length_m" in SOURCE
    assert "would not be exact" in SOURCE


def test_geometry_is_derived_from_inventories_not_the_reverse():
    body = _func(SOURCE, "derive")
    for line in _strip_comments(body).splitlines():
        if re.search(r"(mass_kg|energy_kj)\s*=", line) and "==" not in line:
            assert "volume" not in line and "area" not in line, line


# --------------------------------------------------------------------------
# Validity contract
# --------------------------------------------------------------------------

REASONS = (
    "REASON_OK", "REASON_NON_FINITE_INPUT", "REASON_INVALID_GEOMETRY",
    "REASON_INVALID_AMBIENT", "REASON_NEGATIVE_MASS", "REASON_NEGATIVE_ENERGY",
    "REASON_ENERGY_WITHOUT_MASS", "REASON_BOTH_ZONES_ABSENT",
    "REASON_NON_FINITE_RESULT", "REASON_NON_POSITIVE_PRESSURE",
    "REASON_VOLUME_CLOSURE_OUT_OF_BUDGET", "REASON_INTERFACE_OUT_OF_BUDGET",
)


def test_every_reason_code_exists_and_is_a_constant():
    for reason in REASONS:
        assert "const %s: String" % reason in SOURCE, reason


def test_validation_order_is_fixed_and_documented():
    body = _func(SOURCE, "_validate_inputs")
    order = [reason for reason in REASONS if reason in body]
    assert order.index("REASON_NON_FINITE_INPUT") < order.index("REASON_INVALID_GEOMETRY")
    assert order.index("REASON_INVALID_GEOMETRY") < order.index("REASON_NEGATIVE_MASS")
    assert order.index("REASON_NEGATIVE_MASS") < order.index("REASON_NEGATIVE_ENERGY")
    assert order.index("REASON_NEGATIVE_ENERGY") < order.index("REASON_ENERGY_WITHOUT_MASS")
    assert order.index("REASON_ENERGY_WITHOUT_MASS") < order.index("REASON_BOTH_ZONES_ABSENT")
    assert "VALIDATION ORDER is fixed" in SOURCE


def test_energy_without_mass_is_rejected_not_repaired():
    body = _func(SOURCE, "_validate_inputs")
    assert "upper_mass_kg == 0.0 and upper_energy_kj > 0.0" in body
    assert "lower_mass_kg == 0.0 and lower_energy_kj > 0.0" in body
    assert "energy_kj = 0.0" not in CODE
    for word in ("sink", "repair", "redistribut"):
        assert word not in CODE.lower(), word


def test_negative_energy_is_still_rejected():
    body = _func(SOURCE, "_validate_inputs")
    assert "upper_energy_kj < 0.0 or lower_energy_kj < 0.0" in body
    assert "REASON_NEGATIVE_ENERGY" in body


def test_absent_zone_presence_is_a_strictly_positive_mass():
    body = _func(SOURCE, "derive")
    assert "upper_present: bool = upper_mass_kg > 0.0" in body
    assert "lower_present: bool = lower_mass_kg > 0.0" in body
    for species in ("o2", "co2", "co_", "hcn", "smoke", "species"):
        assert species not in CODE.lower(), species


def test_both_zones_absent_is_invalid():
    body = _func(SOURCE, "_validate_inputs")
    assert "upper_mass_kg == 0.0 and lower_mass_kg == 0.0" in body
    assert "REASON_BOTH_ZONES_ABSENT" in body


# --------------------------------------------------------------------------
# The thermal limit belongs to H3.2b5
# --------------------------------------------------------------------------

def test_no_thermal_limit_is_applied_here():
    assert '"thermal_limit_applied": false' in SOURCE
    assert "max_upper_temp_c" not in SOURCE
    assert "minf(" not in CODE
    assert "H3.2b5" in SOURCE


def test_temperature_is_reported_unlimited():
    assert "UNLIMITED" in SOURCE


# --------------------------------------------------------------------------
# Numerical bound: derived, not fitted, not physical
# --------------------------------------------------------------------------

def test_the_closure_bound_is_derived_from_floating_point():
    assert "const DOUBLE_EPSILON: float = 2.220446049250313e-16" in SOURCE
    assert "const VOLUME_CLOSURE_ROUNDING_BUDGET: int = 16" in SOURCE
    rationale = SOURCE.split("## Rounding budget for the volume closure", 1)[1]
    rationale = rationale.split("const VOLUME", 1)[0]
    # The gas constant added two roundings to the dependency path.
    assert "fourteen rounding operations" in rationale
    assert "the gas constant (multiply, divide = 2)" in rationale
    assert "never a physical tolerance" in rationale


def test_the_bound_scales_with_the_room_and_is_not_absolute():
    body = _func(SOURCE, "derive")
    assert "DOUBLE_EPSILON * room_volume_m3" in body
    assert "DOUBLE_EPSILON * room_height_m" in body


def test_out_of_budget_fails_closed_rather_than_being_nudged():
    body = _func(SOURCE, "derive")
    assert "return _invalid(REASON_VOLUME_CLOSURE_OUT_OF_BUDGET)" in body
    assert "return _invalid(REASON_INTERFACE_OUT_OF_BUDGET)" in body


def test_corrections_are_literal_zero_not_a_computed_difference():
    assert '"mass_correction_kg": 0.0,' in SOURCE
    assert '"energy_correction_kj": 0.0,' in SOURCE
    assert not re.search(r'"mass_correction_kg":\s*[a-z_]', SOURCE)


# --------------------------------------------------------------------------
# Vocabulary and configurability
# --------------------------------------------------------------------------

def test_no_forbidden_vocabulary_in_code():
    for word in ("alpha", "blend", "backfill", "seed", "cap", "tuning"):
        hit = re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % word, CODE)
        assert hit is None, "%s appears in code: %r" % (word, hit)


def test_no_scenario_configurable_constant():
    constants = re.findall(r"^const (\w+)", SOURCE, re.M)
    physical = {"AIR_CP_KJ_KG_K", "AIR_PRESSURE_REF_PA",
                "AIR_DENSITY_REF_KG_M3", "KELVIN_OFFSET_C"}
    numerical = {"DOUBLE_EPSILON", "VOLUME_CLOSURE_ROUNDING_BUDGET",
                 "AMBIENT_PRESSURE_ROUNDING_BUDGET"}
    for name in constants:
        assert name in physical or name in numerical or name.startswith("REASON_"), name


def test_no_csv_runner_or_report_surface():
    for forbidden in ("csv", "sim_log", "summary.json", "run_manifest",
                      "reference_checks", "VALID_GAP", "baseline"):
        assert forbidden not in SOURCE.lower(), forbidden


# --------------------------------------------------------------------------
# The fixture is real, fails closed, and proves what it claims
# --------------------------------------------------------------------------

def test_fixture_expected_count_matches_the_tests_it_runs():
    declared = int(re.search(r"const EXPECTED_TESTS: int = (\d+)", FIXTURE).group(1))
    init_body = FIXTURE.split("func _init() -> void:", 1)[1].split("\n\n", 1)[0]
    called = re.findall(r"^\t(_test_\w+)\(\)", init_body, re.M)
    assert len(called) == declared, (len(called), declared)
    assert len(set(called)) == len(called), "a test is invoked twice"
    for name in called:
        assert "func %s(" % name in FIXTURE, name


def test_fixture_fails_closed_on_an_aborted_run():
    assert "_completed.size() != EXPECTED_TESTS" in FIXTURE
    assert "quit(1)" in FIXTURE
    assert "if _failed:" in FIXTURE


def test_fixture_touches_only_the_primitive():
    preloads = re.findall(r'preload\("([^"]+)"\)', FIXTURE)
    assert preloads == ["res://sim/core/Phase3ResidualProjection.gd"], preloads


def test_fixture_determinism_is_binary_not_approximate():
    body = _fixture_func("_identical_bytes")
    assert "var_to_bytes(a)" in body and "var_to_bytes(b)" in body
    # No approximate comparison and no NaN special case anywhere in it.
    for forbidden in ("is_equal_approx", "is_nan", "NAN"):
        assert forbidden not in body, forbidden
    # And the determinism test must use it, not a field-by-field walk.
    determinism = _fixture_func("_test_binary_determinism_and_idempotence")
    assert "_identical_bytes(" in determinism
    assert "_same_dict" not in FIXTURE, "the NaN-equivalent comparator must be gone"
    assert "_same_float" not in FIXTURE


def test_fixture_determinism_covers_two_zone_and_both_one_zone_cases():
    body = _fixture_func("_test_binary_determinism_and_idempotence")
    assert "[10.0, 2000.0, 45.0, 90.0]" in body      # two zones
    assert "[0.0, 0.0, 60.0, 600.0]" in body         # upper absent
    assert "[60.0, 600.0, 0.0, 0.0]" in body         # lower absent
    # Idempotence still feeds the returned inventories back in.
    assert 'first["upper"]["mass_kg"]' in body
    assert 'first["lower"]["energy_kj"]' in body
    # And the comparator is shown to be able to separate two results.
    assert "really does separate two different results" in body


def test_fixture_walks_valid_results_recursively_for_non_finite_values():
    walker = _fixture_func("_has_non_finite")
    assert "value is Dictionary" in walker
    assert "value is Array" in walker
    assert "not is_finite(value)" in walker
    body = _fixture_func("_test_valid_results_contain_no_nan_or_inf")
    assert "_has_non_finite(r)" in body
    # The walker is self-tested, so a silently broken walker cannot make the
    # check pass vacuously.
    assert "really does detect a nested NAN" in body
    assert "and does not fire on finite content" in body


def test_fixture_checks_the_absent_zone_contract_in_both_directions():
    body = _fixture_func("_test_absent_zone_omits_derived_fields")
    assert "not absent.has(forbidden)" in body
    assert "present.has(forbidden)" in body
    assert "temperature_k" in body and "density_kg_m3" in body


def test_fixture_requires_exact_one_zone_interfaces():
    body = _fixture_func("_test_one_zone_interface_is_exact")
    assert 'float(no_upper["interface_height_m"]) == HEIGHT_M' in body
    assert 'float(no_lower["interface_height_m"]) == 0.0' in body
    # Exactness, never approximation, for the one-zone cases.
    assert "is_equal_approx" not in body


def test_fixture_checks_the_canonical_eos_and_the_ambient_identity():
    eos = _fixture_func("_test_eos_matches_the_canonical_solver_form")
    assert "total_mass_kg * reference_temp_k" in eos
    assert "total_energy_kj / ResidualProjection.AIR_CP_KJ_KG_K" in eos
    ambient = _fixture_func("_test_ambient_room_derives_reference_pressure")
    assert "AIR_DENSITY_REF_KG_M3" in ambient
    assert "AIR_PRESSURE_REF_PA" in ambient
    assert "AMBIENT_PRESSURE_ROUNDING_BUDGET" in ambient


def test_fixture_covers_every_mandated_state():
    for name in ("_test_ordinary_two_zone", "_test_upper_absent",
                 "_test_lower_absent", "_test_equal_temperatures",
                 "_test_hot_upper_cold_lower", "_test_very_small_but_valid_masses",
                 "_test_energy_without_mass_fails_closed",
                 "_test_negative_mass_and_energy_fail_closed",
                 "_test_non_finite_inputs_fail_closed",
                 "_test_invalid_geometry_fails_closed",
                 "_test_both_zones_absent_fails_closed",
                 "_test_volume_closure_matches_an_independent_derivation",
                 "_test_binary_determinism_and_idempotence",
                 "_test_negative_control_invalid_carries_no_derived_field",
                 "_test_transition_is_two_independent_evaluations"):
        assert "func %s(" % name in FIXTURE, name


def test_fixture_makes_no_claim_about_the_runtime_transition_counters():
    body = _fixture_func("_test_transition_is_two_independent_evaluations")
    assert "H3.2b1b" in body
    assert "asserts nothing about the runtime transition counters" in body
