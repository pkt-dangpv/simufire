import csv
from pathlib import Path

from scripts.simulation.analyze_phase3_fire_products_routing import (
    ROUTING_FIELDS,
    analyze,
)


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOGGER = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    end = source.find("\nfunc ", start + len(marker))
    return source[start:] if end < 0 else source[start:end]


def _write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def test_routing_flag_is_default_off_and_requires_all_parents():
    flag = "phase3_canonical_fire_products_routing_shadow_enabled"
    assert f"@export var {flag}: bool = false" in ENGINE
    helper = _function(ENGINE, "_phase3_canonical_fire_products_routing_active")
    for parent in [
        "_phase3_canonical_multisurface_active()",
        "phase3_canonical_plume_shadow_enabled",
        "phase3_coupled_plume_shadow_enabled",
        "phase3_canonical_fire_proposal_shadow_enabled",
        "phase3_canonical_fire_products_shadow_enabled",
    ]:
        assert parent in helper


def test_cli_routing_flag_enables_product_parents():
    cli = "--phase3-canonical-fire-products-routing-shadow"
    assert cli in RUNNER
    assert cli in HEADLESS
    block = RUNNER[RUNNER.index("if args.phase3_canonical_fire_products_routing_shadow") :]
    for parent in [
        "--phase3-canonical-fire-proposal-shadow",
        "--phase3-canonical-fire-products-shadow",
        "--phase3-canonical-plume-shadow",
    ]:
        assert parent in block


def test_products_replace_legacy_transaction_inputs_only_when_active():
    body = _function(COMBUSTION, "evaluate_phase3_canonical_combustion_step")
    assert "if products_routing_active:" in body
    assert 'canonical_fire_products.get("accepted_o2_kg"' in body
    assert '"accepted_species_kg", {}' in body
    assert '"accepted_total_energy_kj", 0.0' in body
    assert '"canonical_fire_products_routing_active_flag"' in body


def test_atomic_bundle_still_owns_final_common_fraction():
    finalize = _function(SYSTEM, "finalize_canonical_combustion_bundle")
    assert "canonical_fire_products_routing_active_flag" in finalize
    assert "canonical_combustion_o2_sink" in finalize
    assert "canonical_combustion_species_source" in finalize
    assert "canonical_combustion_convective_heat" in finalize
    assert "canonical_combustion_plume" in finalize
    record = _function(SYSTEM, "_record_atomic_bundle_result")
    assert "_interpolate_combustion_state(" in record
    assert "canonical_fire_products_committed_fuel_MJ" in record


def test_routing_does_not_write_live_room_or_fire_objects():
    body = _function(COMBUSTION, "evaluate_phase3_canonical_combustion_step")
    routing = body[body.index("if products_routing_active:") :]
    assert "room.fire." not in routing
    assert "room.remaining_fuel" not in routing
    assert "_apply_species_generation_result" not in routing


def test_routing_schema_is_independently_gated():
    assert "configure_phase3_canonical_fire_products_routing_shadow" in LOGGER
    assert "if phase3_canonical_fire_products_routing_shadow_enabled:" in LOGGER
    fields = _function(LOGGER, "_phase3_fire_products_routing_fields")
    for field in ROUTING_FIELDS:
        assert field in fields


def test_analyzer_accepts_legacy_invariance_and_closed_routes(tmp_path):
    baseline = tmp_path / "baseline.csv"
    routed = tmp_path / "routed.csv"
    base_fields = ["time_s", "room_id", "hrr_kw", "phase3_shadow_old"]
    _write_csv(
        baseline,
        base_fields,
        [{"time_s": "1", "room_id": "0", "hrr_kw": "5", "phase3_shadow_old": "1"}],
    )
    routed_fields = base_fields + ROUTING_FIELDS + [
        "phase3_shadow_fire_products_object_sync_required_flag"
    ]
    row = {
        "time_s": "1",
        "room_id": "0",
        "hrr_kw": "5",
        "phase3_shadow_old": "2",
        **{field: "0" for field in ROUTING_FIELDS},
        "phase3_shadow_fire_products_routing_active_flag": "1",
        "phase3_shadow_fire_products_object_sync_required_flag": "0",
    }
    _write_csv(routed, routed_fields, [row])
    result = analyze(baseline, routed)
    assert result["pass"]
    assert result["legacy_mismatches"] == 0
    assert not result["runtime_authority_ready"]


def test_analyzer_rejects_live_column_change(tmp_path):
    baseline = tmp_path / "baseline.csv"
    routed = tmp_path / "routed.csv"
    _write_csv(baseline, ["time_s", "hrr_kw"], [{"time_s": "1", "hrr_kw": "5"}])
    fields = ["time_s", "hrr_kw", *ROUTING_FIELDS]
    row = {"time_s": "1", "hrr_kw": "6", **{field: "0" for field in ROUTING_FIELDS}}
    row["phase3_shadow_fire_products_routing_active_flag"] = "1"
    _write_csv(routed, fields, [row])
    result = analyze(baseline, routed)
    assert not result["pass"]
    assert result["legacy_mismatches"] == 1
