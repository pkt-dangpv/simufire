from pathlib import Path
from scripts.simulation.analyze_phase3_fuel_object_sync import analyze
from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOGGER = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
FIXTURE = ROOT / "tests/fixtures/phase3_f33v2c_fuel_object_sync.gd"
GODOT = Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe")


def test_evaluator_is_dictionary_only_and_bounded():
    start = COMBUSTION.index("func evaluate_phase3_canonical_fuel_object_sync")
    end = COMBUSTION.index("\nfunc ", start + 10)
    body = COMBUSTION[start:end]
    assert "room." not in body
    assert "obj." not in body
    assert "remaining_fuel_MJ" in body
    assert "allocation_residual_MJ" in body
    assert "seen.has(object_id)" in body
    assert "entries.sort_custom" in body
    assert "leftover_MJ" in body


def test_direct_godot_fixture():
    if not GODOT.exists():
        return
    completed = run_godot(
        [
            str(GODOT),
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            str(FIXTURE),
        ],
        timeout_s=60,
        allowed_exit_codes=(0,),
    )
    output = completed.stdout + completed.stderr
    assert completed.returncode == 0, output
    assert "PHASE3_F33V2C_FUEL_OBJECT_SYNC_PASS" in output


def test_sync_flag_is_default_off_and_parent_gated():
    flag = "phase3_canonical_fuel_object_sync_shadow_enabled"
    assert f"@export var {flag}: bool = false" in ENGINE
    assert "_phase3_canonical_fire_products_routing_active()" in ENGINE
    assert "--phase3-canonical-fuel-object-sync-shadow" in RUNNER


def test_nested_ledger_uses_atomic_fraction_and_derives_aggregate():
    assert "func _interpolate_fuel_object_ledger(" in SYSTEM
    body = SYSTEM[SYSTEM.index("func _interpolate_combustion_state(") :]
    assert "_interpolate_fuel_object_ledger(" in body
    assert 'result["remaining_fuel_MJ"] = committed_object_fuel_MJ' in body
    assert "canonical_fuel_object_sync_atomic_residual_MJ" in SYSTEM


def test_sync_schema_is_independently_gated():
    assert "configure_phase3_canonical_fuel_object_sync_shadow" in LOGGER
    assert "if phase3_canonical_fuel_object_sync_shadow_enabled:" in LOGGER
    assert '"aggregate_residual_MJ"' in LOGGER
    assert '"phase3_shadow_fuel_object_sync_" + field_name' in LOGGER


def test_analyzer_separates_shadow_closure_from_live_authority(tmp_path):
    import csv

    baseline = tmp_path / "base.csv"
    candidate = tmp_path / "candidate.csv"
    base_fields = ["time_s", "room_id", "hrr_kw", "fuel_consumed_MJ_step"]
    with baseline.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=base_fields)
        writer.writeheader()
        writer.writerow({
            "time_s": "1",
            "room_id": "0",
            "hrr_kw": "5",
            "fuel_consumed_MJ_step": "0.2",
        })
    from scripts.simulation.analyze_phase3_fuel_object_sync import FIELDS, PREFIX
    fields = base_fields + [PREFIX + field for field in FIELDS]
    row = {field: "0" for field in fields}
    row.update({
        "time_s": "1",
        "room_id": "0",
        "hrr_kw": "5",
        "fuel_consumed_MJ_step": "0.2",
    })
    row[PREFIX + "active_flag"] = "1"
    row[PREFIX + "supported_flag"] = "1"
    row[PREFIX + "object_count"] = "7"
    row[PREFIX + "identity_signature"] = "123"
    row[PREFIX + "eligible_count"] = "1"
    row[PREFIX + "requested_debit_MJ"] = "0.1"
    row[PREFIX + "live_delta_MJ"] = "-0.5"
    with candidate.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerow(row)
    result = analyze(baseline, candidate)
    assert result["pass"]
    assert result["shadow_closed"]
    assert not result["runtime_authority_ready"]
    assert result["diagnosis"] == "aggregate_source_term_mismatch"
    assert result["per_object_allocator_exonerated"]
    assert result["fuel_semantics_split_required"]
    assert result["source_mismatch_rows"] == 1
    assert result["max_legacy_minus_canonical_debit_MJ"] == 0.1


def test_analyzer_keeps_per_object_diagnosis_when_source_debits_match(tmp_path):
    import csv

    baseline = tmp_path / "base.csv"
    candidate = tmp_path / "candidate.csv"
    base_fields = ["time_s", "room_id", "fuel_consumed_MJ_step"]
    with baseline.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=base_fields)
        writer.writeheader()
        writer.writerow({
            "time_s": "1",
            "room_id": "0",
            "fuel_consumed_MJ_step": "0.1",
        })
    from scripts.simulation.analyze_phase3_fuel_object_sync import FIELDS, PREFIX
    fields = base_fields + [PREFIX + field for field in FIELDS]
    row = {field: "0" for field in fields}
    row.update({
        "time_s": "1",
        "room_id": "0",
        "fuel_consumed_MJ_step": "0.1",
    })
    row[PREFIX + "active_flag"] = "1"
    row[PREFIX + "supported_flag"] = "1"
    row[PREFIX + "object_count"] = "2"
    row[PREFIX + "identity_signature"] = "123"
    row[PREFIX + "eligible_count"] = "2"
    row[PREFIX + "requested_debit_MJ"] = "0.1"
    row[PREFIX + "live_delta_MJ"] = "-0.5"
    with candidate.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerow(row)
    result = analyze(baseline, candidate)
    assert result["shadow_closed"]
    assert result["diagnosis"] == "per_object_correspondence_unresolved"
    assert not result["per_object_allocator_exonerated"]
    assert not result["fuel_semantics_split_required"]
