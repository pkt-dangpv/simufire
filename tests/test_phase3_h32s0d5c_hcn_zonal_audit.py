"""Structural contracts for the H3.2-S0d5c HCN zonal audit.

S0d5c is a NO-GO: no HCN physics change shipped. These contracts pin the
measurement that produced that verdict and pin the absence of a fix.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")


def test_no_hcn_physics_flag_exists():
    for forbidden in (
        "phase3_hcn_zonal_transport_consistency_enabled",
        "_hcn_lower_stock_kg",
        "_cap_hcn_lower_transfer",
    ):
        assert forbidden not in GAS, forbidden
        assert forbidden not in ENGINE, forbidden


def test_hcn_legacy_paths_are_untouched():
    # The bulk-only HCN writers must remain exactly as legacy wrote them.
    for line in (
        "hcn_delta_kg[room_a.id] -= net_hcn_a_to_b",
        "hcn_delta_kg[room_b.id] += net_hcn_a_to_b",
        "hcn_delta_kg[from_r.id] = float(hcn_delta_kg.get(from_r.id, 0.0)) - d_hcn",
        "inlet_room.hcn_kg = maxf(0.0, inlet_room.hcn_kg * (1.0 - mix_frac))",
        "inlet_room.hcn_kg = maxf(0.0, inlet_room.hcn_kg * (1.0 - ex_frac))",
    ):
        assert line in GAS, line
        preceding = GAS.split(line, 1)[0].rstrip().splitlines()[-1].strip()
        assert not preceding.startswith("if phase3_"), line


def test_hcn_threshold_is_derived_not_inherited():
    assert "const ZONAL_GUARD_MATERIAL_EPS_HCN_KG: float = 1.0e-7" in GAS
    eps = GAS.split("func _material_eps_for(", 1)[1].split("\nfunc ", 1)[0]
    assert 'if species == "hcn":' in eps
    assert "ZONAL_GUARD_MATERIAL_EPS_HCN_KG" in eps
    assert "return 0.0" in eps
    # Each species keeps a distinct constant; none reuses another's.
    values = re.findall(r"ZONAL_GUARD_MATERIAL_EPS\w*_KG: float = ([0-9.e-]+)", GAS)
    assert len(values) == 3
    assert len(set(values)) == 3


def test_hcn_threshold_derivation_is_documented_against_fed():
    block = GAS.split("## H3.2-S0d5c:", 1)[1].split("const ZONAL_GUARD_MATERIAL_EPS_HCN_KG", 1)[0]
    for token in ("FED", "3.12e-9", "2.4e-7", "ppm"):
        assert token in block, token
    # The upper bound must not be a bare rounded ppm.
    assert "sensibilidad FED" in block or "FED_HCN" in block


def test_hcn_is_traced_at_every_hcn_writer():
    for writer in (
        '_co_trace("inherited_pre_room_loop", room, {}, "hcn")',
        '_co_trace("accumulator_application", room, {',
        '_co_trace("ach_infiltration", room, {}, "hcn")',
        '_co_trace("outside_open_species_purge", room, {}, "hcn")',
        '_co_trace("postfire_species_purge", room, {}, "hcn")',
        '_co_trace("final_upper_clamp", room, {}, "hcn")',
        '_co_trace("parcel_delivery_clamp", target, {}, "hcn")',
        '_co_trace("pressure_vent_species", room, {}, "hcn")',
        '_co_trace("ppv_inlet_species", inlet_room, {}, "hcn")',
        '_co_trace("ppv_exhaust_species", inlet_room, {}, "hcn")',
    ):
        assert writer in GAS, writer
    # PPV exhaust had no observation point before this phase.
    assert GAS.count('_co_trace("ppv_exhaust_species"') == 3


def test_trace_reads_hcn_stocks():
    body = GAS.split("func _co_trace(", 1)[1].split("\nfunc ", 1)[0]
    assert 'elif species == "hcn":' in body
    assert "room.hcn_kg" in body and "room.hcn_upper_kg" in body


def test_all_three_thresholds_are_exported():
    body = GAS.split("func get_phase3_species_attribution_summary(", 1)[1]
    body = body.split("\nfunc ", 1)[0]
    for species in ('"co"', '"co2"', '"hcn"'):
        assert species in body, species
    # With nothing observed the export stays completely empty.
    assert "if summary.is_empty():" in body


def test_clamp_and_other_species_are_untouched():
    assert "room.hcn_upper_kg = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)" in GAS
    assert "room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)" in GAS
    assert "room.co2_upper_kg = clampf(room.co2_upper_kg, 0.0, room.co2_kg)" in GAS
    # The CO and CO2 experiments stay exactly as approved.
    assert "co_upper_delta_kg[from_id] -= co_moved_kg" in GAS
    assert "_cap_co2_lower_transfer(net_co2_a_to_b, room_a, room_b)" in GAS


def test_no_o2_or_hvac_work():
    hvac = (ROOT / "sim/core/HVACSystem.gd").read_text(encoding="utf-8")
    assert "_co_trace" not in hvac
    assert "zonal_guard" not in hvac
    oes = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
    assert "_co_trace" not in oes
    assert not (ROOT / "sim/core/Phase3PhysicalSourceIntegrator.gd").exists()


def test_no_new_csv_columns():
    for name in ("sim/core/SimulationLogWriter.gd", "sim/core/SimulationStateBuilder.gd"):
        text = (ROOT / name).read_text(encoding="utf-8")
        assert "zonal_guard" not in text
        assert "phase3_co_violation_trace" not in text
