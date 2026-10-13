"""Offline witnesses for M4-B limits; no engine/Godot or physical validation."""
import json
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.simulation import audit_g3_m4_layer_writers as audit
from scripts.simulation.g3_m4_partition_contract import Partition, budget, broken_invariants, remap


@pytest.mark.parametrize("text", [
    '# room.o2_upper = 0\n', 'var label = "o2_upper = 0"\n',
    "var label = '''\no2_lower = 0\n'''\n", 'room.co2_upper = 0\n',
    'if room.o2_upper == 0:\n\tpass\n', 'var s = "escaped \\" o2_lower = 0"\n',
])
def test_inventory_ignores_nonassignments(text):
    assert audit.scan(text, "synthetic.gd") == []


@pytest.mark.parametrize("operator", ["=", "+=", "-=", "*=", "/="])
def test_inventory_detects_compound_writes_and_keeps_function(operator):
    rows = audit.scan(f'func step():\n\troom.o2_upper {operator} 1 # comment\n', "synthetic.gd")
    assert len(rows) == 1
    assert rows[0]["line"] == 2 and rows[0]["function"] == "step"
    assert not rows[0]["declaration"]


def test_inventory_separates_initial_declaration_from_reset_write():
    rows = audit.scan('var o2_lower: float = 0.209\nfunc reset():\n\to2_lower = 0.209\n', "room.gd")
    assert [row["declaration"] for row in rows] == [True, False]


def test_current_inventory_matches_recorded_sources_and_every_direct_write():
    evidence = json.loads((ROOT / "docs/validation/G3_O2_M4_ADAPTER_DIAGNOSIS_EVIDENCE_2026-10-12.json")
                          .read_text(encoding="utf-8"))
    actual, historical = audit.inventory(), evidence["inventory"]
    # M4-P1 adds ONE isolated pure module. Preserve every historical source
    # and writer rather than rewriting the 64-file evidence from M4-B.
    addition = "sim/core/PhysicalGasOxygenParcelModel.gd"
    assert set(actual["source_hashes_lf"]) == set(historical["source_hashes_lf"]) | {addition}
    for path, sha in historical["source_hashes_lf"].items():
        assert actual["source_hashes_lf"][path] == sha
    assert actual["gd_file_count"] == historical["gd_file_count"] + 1
    for field in set(historical) - {"source_hashes_lf", "gd_inventory_lf_sha256", "gd_file_count"}:
        assert actual[field] == historical[field]
    assert audit.scan((ROOT / addition).read_text(encoding="utf-8"), addition) == []
    assert evidence["engine_integrated"] is False
    assert evidence["physical_validation"] is False


def test_same_room_delta_does_not_determine_layer_deltas():
    before = Partition(.3, .1, 1, 1)
    from_upper = budget(before, -.03, 0, "synthetic_upper_debit")
    from_lower = budget(before, 0, -.03, "synthetic_lower_debit")
    assert from_upper.after.total_kg == pytest.approx(from_lower.after.total_kg)
    assert from_upper.after.upper_kg != from_lower.after.upper_kg
    assert broken_invariants(from_upper) == broken_invariants(from_lower) == []


def test_stratified_doorway_sampling_cannot_preserve_frozen_room_average_law():
    # Imposed concentrations and 1 kg REFERENCE gas in each direction.
    # Not a Godot doorway experiment or a measured fire.
    kappa = .031998 / .0289647
    room_mean, upper_donor, incoming_lower = .2, .1, .21
    historical = kappa * (incoming_lower - room_mean)
    zonal = kappa * (incoming_lower - upper_donor)
    assert historical == pytest.approx(.0110472350827)
    assert zonal == pytest.approx(.121519585)
    assert zonal != pytest.approx(historical)
    # Homogeneous donor is the special case where both contracts coincide.
    homogeneous = Partition(.4, .2, 1, 1)
    zonal_uniform = kappa * (incoming_lower - homogeneous.fractions()["upper"])
    assert zonal_uniform == pytest.approx(historical)


def test_double_counted_plume_can_pass_conservation_checks():
    before = Partition(.3, .1, 1, 2)
    once = remap(before, 1.5)
    duplicate = budget(once.after, .05, -.05, "same_swept_parcel_again")
    assert once.after.upper_kg == pytest.approx(.15)
    assert duplicate.after.upper_kg == pytest.approx(.20)
    assert broken_invariants(once) == broken_invariants(duplicate) == []
    assert duplicate.after.total_kg == before.total_kg


def test_current_plume_shadow_quantity_is_not_molar_reference_conversion():
    source = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
    block = source.split("func _step_two_zone_plume_entrainment(", 1)[1].split("\nfunc ", 1)[0]
    assert '"o2_kg": moved_mass_kg * clampf(room.o2_lower, 0.0, 1.0)' in block
    assert "apply_lower_to_upper_transfer(room, transfer)" in block
    assert "o2_kg_in_reference_gas" not in block


def test_m2t_current_owner_still_samples_rooms_not_layers():
    source = (ROOT / "sim/core/RoomOxygenInventory.gd").read_text(encoding="utf-8")
    block = source.split("func exchange_reference_gas_between_rooms(", 1)[1].split("\nfunc ", 1)[0]
    assert "donor_before_kg * (exchanged_gas_kg / donor_reference_kg)" in block
    assert "receiver_before_kg * (exchanged_gas_kg / receiver_reference_kg)" in block
    assert "o2_upper" not in block and "o2_lower" not in block
