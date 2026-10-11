"""D1 offline input contracts; no Godot and no claim of material calibration."""

import copy
import hashlib
import inspect
import json
from pathlib import Path

import pytest

from scripts.simulation import validate_g3_mass_material_profile as profile


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/g3_mass_material_profile_synthetic.json"


def control():
    return profile.load_profile(FIXTURE)


def provenances(data):
    return [data["initial_mass"]["provenance"],
            data["material"]["composition_provenance"],
            data["material"]["chemical_heat"]["provenance"],
            data["release"]["provenance"]]


def external_stub():
    """A mock attribution to a synthetic file, NEVER experimental evidence."""
    data = control()
    data["kind"] = "external_candidate"
    for provenance in provenances(data):
        provenance.update({
            "type": "declared_model", "reference": "https://example.invalid/mock-test-only",
            "version": "test-mock-v1", "artifact": FIXTURE.relative_to(ROOT).as_posix(),
            "sha256": hashlib.sha256(FIXTURE.read_bytes()).hexdigest(),
        })
    return data


def changed(case):
    data = control()
    if case == "unknown_energy":
        data["fuel_energy_MJ"] = 20
    elif case == "wrong_initial_unit":
        data["initial_mass"]["unit"] = "MJ"
    elif case == "different_component":
        data["initial_mass"]["component_id"] = "whole_sofa_with_pillows"
    elif case == "effective_heat":
        data["material"]["chemical_heat"]["basis"] = "net_effective_calorimetry"
    elif case == "specimen_loss":
        data["release"]["quantity"] = "specimen_mass_loss"
    elif case == "bool_mass":
        data["initial_mass"]["value"] = True
    elif case == "excess_integral":
        data["initial_mass"]["value"] = 0.1
    elif case == "reversed_times":
        data["release"]["samples"][2]["time_s"] = 4
    elif case == "extrapolate":
        data["release"]["outside_domain"] = "hold_last"
    elif case == "wrong_hash":
        data = external_stub()
        data["initial_mass"]["provenance"]["sha256"] = "0" * 64
    else:
        raise AssertionError(case)
    return data


def test_synthetic_triangle_integral_independent_of_heat_and_no_mutation():
    data = control()
    before = copy.deepcopy(data)
    report = profile.validate_profile(data)
    assert report["valid"]
    assert report["decision"] == "synthetic_contract_complete"
    assert report["prescribed_emission_integral_kg"] == pytest.approx(0.5, abs=1e-15)
    assert data == before
    data["material"]["chemical_heat"]["value"] *= 2
    assert profile.validate_profile(data)["prescribed_emission_integral_kg"] == 0.5
    for key in ("production_activation", "engine_integration", "scientific_approval"):
        assert report[key] is False


def test_asymmetric_linear_integral_and_zero_release():
    data = control()
    data["release"]["samples"] = [
        {"time_s": 0, "rate_kg_s": 0.02},
        {"time_s": 3, "rate_kg_s": 0.08},
        {"time_s": 4, "rate_kg_s": 0.01},
    ]
    assert profile.validate_profile(data)["prescribed_emission_integral_kg"] == pytest.approx(0.195)
    data["initial_mass"]["value"] = 0
    for sample in data["release"]["samples"]:
        sample["rate_kg_s"] = 0
    assert profile.validate_profile(data)["valid"]


CASES = ["unknown_energy", "wrong_initial_unit", "different_component", "effective_heat",
         "specimen_loss", "bool_mass", "excess_integral", "reversed_times", "extrapolate", "wrong_hash"]


@pytest.mark.parametrize("case", CASES)
def test_incompatible_data_fail_closed(case):
    result = profile.validate_profile(changed(case))
    assert not result["valid"]
    assert result["errors"] and result["decision"] == "rejected"
    assert result["prescribed_emission_integral_kg"] is None


@pytest.mark.parametrize("bad", [None, [], "production", {}, True])
def test_malformed_profile_or_kind_returns_rejection_not_exception(bad):
    assert not profile.validate_profile(bad)["valid"]
    data = control()
    data["kind"] = bad
    assert not profile.validate_profile(data)["valid"]


@pytest.mark.parametrize("value", [float("nan"), float("inf"), -1, "1", 10 ** 1000])
def test_invalid_numbers_are_explicit_errors(value):
    data = control()
    data["initial_mass"]["value"] = value
    assert not profile.validate_profile(data)["valid"]


def test_missing_mass_is_not_completed_from_heat_or_legacy_energy():
    data = control()
    del data["initial_mass"]
    data["fuel_energy_MJ"] = 20
    result = profile.validate_profile(data)
    assert not result["valid"] and result["declared_initial_mass_kg"] is None


def test_composition_and_incomplete_or_predicted_curves_are_not_silently_accepted():
    for target, key, value in [
        ("composition", "N", 0.1), ("composition", "C", 0.8),
        ("release", "mode", "thermal_prediction"), ("release", "samples", []),
        ("release", "time_origin", ""), ("release", "unit", "g/s"),
    ]:
        data = control()
        block = data["material"]["mass_fractions"] if target == "composition" else data["release"]
        block[key] = value
        assert not profile.validate_profile(data)["valid"]
    data = control()
    data["release"]["samples"][0]["time_s"] = 1
    assert not profile.validate_profile(data)["valid"]


def test_external_manifest_is_not_scientific_or_product_approval():
    data = external_stub()
    report = profile.validate_profile(data)
    assert report["valid"]
    assert report["decision"] == "external_contract_complete_pending_scientific_review"
    assert not report["scientific_approval"] and not report["production_activation"]
    data["initial_mass"]["provenance"]["type"] = []
    assert not profile.validate_profile(data)["valid"]


@pytest.mark.parametrize("artifact", ["../outside", "docs/missing_artifact.pdf", str(FIXTURE)])
def test_artifact_must_be_present_relative_and_confined(artifact):
    data = external_stub()
    data["initial_mass"]["provenance"]["artifact"] = artifact
    assert not profile.validate_profile(data)["valid"]


def test_overflowing_integral_is_rejected():
    data = control()
    data["initial_mass"]["value"] = 1e308
    data["release"]["samples"] = [
        {"time_s": 0, "rate_kg_s": 1e308}, {"time_s": 1e308, "rate_kg_s": 1e308},
    ]
    result = profile.validate_profile(data)
    assert not result["valid"] and "release: integrated mass overflow" in result["errors"]


@pytest.mark.parametrize("text", ['{"id":1,"id":2}', '{"mass":NaN}', '{"mass":Infinity}'])
def test_json_parser_rejects_duplicates_and_nonfinite_tokens(text):
    with pytest.raises(ValueError):
        json.loads(text, object_pairs_hook=profile._unique_pairs, parse_constant=profile._invalid_constant)


@pytest.mark.parametrize("block", ["initial_mass", "material", "release"])
def test_malformed_nested_block_is_an_explicit_rejection(block):
    data = control()
    data[block] = []
    assert not profile.validate_profile(data)["valid"]


def test_cli_returns_machine_readable_result_and_missing_file_error(monkeypatch, capsys):
    monkeypatch.setattr("sys.argv", ["validator", str(FIXTURE)])
    assert profile.main() == 0
    assert json.loads(capsys.readouterr().out)["decision"] == "synthetic_contract_complete"
    monkeypatch.setattr("sys.argv", ["validator", str(ROOT / "tests/absent_d1_profile.json")])
    assert profile.main() == 1
    assert json.loads(capsys.readouterr().out)["decision"] == "rejected"


MUTATIONS = [
    ("unknown_energy", "if set(value) != set(keys):", "if False:"),
    ("wrong_initial_unit", '_exact(initial.get("unit"), "kg", "initial_mass.unit", errors)', "pass"),
    ("different_component", '_exact(initial.get("component_id"), component, "initial_mass.component_id", errors)', "pass"),
    ("effective_heat", '_exact(heat.get("basis"), "complete_oxidation_net", "chemical_heat.basis", errors)', "pass"),
    ("specimen_loss", '_exact(release.get("quantity"), "modeled_component_emission", "release.quantity", errors)', "pass"),
    ("bool_mass", 'isinstance(value, bool) or not isinstance(value, (int, float))', 'not isinstance(value, (int, float))'),
    ("excess_integral", 'elif emitted > mass + MASS_ABS_TOL_KG + REL_TOL * max(mass, emitted):', 'elif False:'),
    ("reversed_times", 'if parsed and time <= parsed[-1][0]:', 'if False:'),
    ("extrapolate", '_exact(release.get("outside_domain"), "reject", "release.outside_domain", errors)', 'pass'),
    ("wrong_hash", 'if hashlib.sha256(path.read_bytes()).hexdigest() != checksum:', 'if False:'),
]


@pytest.mark.parametrize("case,anchor,replacement", MUTATIONS)
def test_contract_guards_detect_valid_in_memory_mutants(case, anchor, replacement):
    source = inspect.getsource(profile)
    assert source.count(anchor) == 1
    namespace = {"__file__": str(Path(profile.__file__)), "__name__": "isolated_d1_mutant"}
    code = compile(source.replace(anchor, replacement), "isolated_d1_mutant", "exec")
    exec(code, namespace)
    data = changed(case)
    assert not profile.validate_profile(data)["valid"]  # oracle must pass on baseline
    assert namespace["validate_profile"](data, ROOT)["valid"]  # valid mutant escapes same oracle
