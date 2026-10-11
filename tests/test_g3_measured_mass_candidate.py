"""Measured mass audit: offline only, not an engine calibration test."""

import copy
from decimal import Decimal
import hashlib
import json
from pathlib import Path

import pytest

from scripts.simulation import audit_g3_measured_mass_candidate as candidate


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "docs/validation/G3_D1_ISOHEPT9_MASS_AUDIT_2026-10-03.json"


def test_archived_case_reproduces_report_without_claiming_physics_approval():
    actual = candidate.audit()
    assert actual == json.loads(REPORT.read_text(encoding="utf-8"))
    assert actual == candidate.audit()
    assert actual["row_count"] == 187
    assert actual["sample_steps_s"] == [5.0]
    assert actual["mass_at_ignition_kg"] == 19.665829
    assert actual["nominal_minus_ignition_kg"] == 0.334171
    assert actual["profile_generated"] is False
    for key in ("scientific_approval", "engine_integration", "production_activation"):
        assert actual[key] is False
    assert "rate_samples" not in actual


def test_measured_bulk_window_is_clean_but_the_tail_is_not_clipped():
    result = candidate.audit()
    bulk, steady, tail = result["windows"]
    assert bulk["window_s"] == [0, 500]
    assert bulk["net_measured_decrease_kg"] == 19.359537
    assert bulk["nonnegative_rate_compatible_without_processing"] is True
    assert steady["net_measured_decrease_kg"] == 14.336033
    assert tail["increase_interval_count"] == 44
    assert tail["negative_sample_count"] == 19
    assert tail["sum_mass_increases_kg"] == 0.485504
    assert tail["sum_positive_decreases_kg"] == 0.695812
    assert tail["net_measured_decrease_kg"] == 0.210308
    assert tail["nonnegative_rate_compatible_without_processing"] is False
    assert result["whole_record"]["sum_mass_increases_kg"] == 0.500412


def test_mass_secants_are_signed_and_exact_accounting_not_clamped_rates():
    rows = candidate.read_mass_rows("Time,Mass1,unused\n0,2,NaN\n5,1.8,Inf\n10,1.9,NaN\n")
    result = candidate.inspect_window(rows, 0, 10)
    assert result["net_measured_decrease_kg"] == 0.1
    assert result["sum_positive_decreases_kg"] == 0.2
    assert result["sum_mass_increases_kg"] == 0.1
    assert result["signed_secant_rate_range_kg_s"] == [-0.02, 0.04]
    assert result["nonnegative_rate_compatible_without_processing"] is False


@pytest.mark.parametrize("text", [
    "Time,Mass1\n0,1\n5,NaN\n",
    "Time,Mass1\n0,1\nInf,0\n",
    "Time,Mass1\n0,1\n0,0\n",
    "Time,Mass1\n5,1\n0,0\n",
    "Time,Mass1\n0,1\n5,0,extra\n",
    "Time,Mass1\n0,1\n5\n",
    "Time,Mass1,Mass1\n0,1,1\n5,0,0\n",
    "Time,HRR\n0,1\n5,0\n",
    "Time,Mass1\n0,1\n",
])
def test_invalid_selected_channels_or_shape_are_not_silently_repaired(text):
    with pytest.raises(ValueError):
        candidate.read_mass_rows(text)


@pytest.mark.parametrize("bounds", [(0, 4), (-1, 5), (5, 5), (5, 0)])
def test_no_interpolation_or_extrapolation_of_window_endpoints(bounds):
    rows = [(Decimal(0), Decimal(1)), (Decimal(5), Decimal(0))]
    with pytest.raises(ValueError):
        candidate.inspect_window(rows, *bounds)


def test_content_hash_preserves_eol_equivalence_but_detects_actual_change(tmp_path):
    path = tmp_path / "sample.csv"
    path.write_bytes(b"Time,Mass1\r\n0,1\r\n5,0\r\n")
    record = {"path": "sample.csv", "sha256_lf": hashlib.sha256(
        b"Time,Mass1\n0,1\n5,0\n").hexdigest()}
    candidate.confined_artifact(tmp_path, record, text=True)
    path.write_bytes(b"Time,Mass1\r\n0,2\r\n5,0\r\n")
    with pytest.raises(ValueError, match="content mismatch"):
        candidate.confined_artifact(tmp_path, record, text=True)


def test_binary_report_hash_does_not_normalize_eol(tmp_path):
    path = tmp_path / "sample.pdf"
    path.write_bytes(b"%PDF-1.7\r\n")
    record = {"path": "sample.pdf", "sha256_raw": hashlib.sha256(
        b"%PDF-1.7\n").hexdigest()}
    with pytest.raises(ValueError, match="content mismatch"):
        candidate.confined_artifact(tmp_path, record, text=False)


@pytest.mark.parametrize("path", ["../outside.csv", str(ROOT / "outside.csv")])
def test_artifacts_are_confined(tmp_path, path):
    with pytest.raises(ValueError, match="relative|escapes"):
        candidate.confined_artifact(tmp_path, {"path": path}, text=True)


@pytest.mark.parametrize("field,value", [
    ("scientific_approval", True),
    ("engine_integration", True),
    ("production_activation", True),
    ("rate_processing", "clamp_negative_rates"),
    ("schema", "unknown"),
])
def test_candidate_manifest_cannot_claim_approval_or_undisclosed_processing(
    tmp_path, field, value
):
    data = copy.deepcopy(json.loads(candidate.DEFAULT_MANIFEST.read_text(encoding="utf-8")))
    data[field] = value
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(ValueError):
        candidate.audit(path)


@pytest.mark.parametrize("column,unit", [("Time", "min"), ("Mass1", "g")])
def test_units_require_a_new_explicit_contract_not_implicit_conversion(tmp_path, column, unit):
    data = json.loads(candidate.DEFAULT_MANIFEST.read_text(encoding="utf-8"))
    data["columns_reviewed"][column]["unit"] = unit
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(ValueError, match="units"):
        candidate.audit(path)
