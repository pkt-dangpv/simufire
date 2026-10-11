"""M2-T code isolation and predeclared mutation contracts. Launches no Godot.

Behaviour is judged by g3_o2_transport_acceptance.gd, not by text assertions.
Historical debt APIs remain for explicit diagnostic injections only.
"""

from pathlib import Path
import subprocess

import pytest

from scripts.simulation import run_g3_o2_transport_mutations as mutations

ROOT = Path(__file__).resolve().parents[1]
BASE = "920affb7"
OWNER = "sim/core/RoomOxygenInventory.gd"
OXYGEN = "sim/core/OxygenExchangeSystem.gd"


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def base(path: str) -> str:
    return subprocess.run(["git", "show", f"{BASE}:{path}"], cwd=ROOT,
                          capture_output=True, check=True).stdout.decode().replace("\r\n", "\n")


def body(source: str, method: str) -> str:
    section = source.split(f"func {method}(", 1)[1].split("\nfunc ", 1)[0]
    return "\n".join(line for line in section.splitlines() if not line.lstrip().startswith("#")).rstrip()


def test_live_callers_use_one_owner_operation_and_never_the_historical_debt_api():
    callers = []
    for path in (ROOT / "sim").rglob("*.gd"):
        source = path.read_text(encoding="utf-8")
        code = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
        if ".exchange_between_rooms(" in code:
            callers.append(path.relative_to(ROOT).as_posix())
    assert callers == [], "legacy signed-debt API must have no simulation caller"
    source = text(OXYGEN)
    assert source.count("room_o2_inventory.exchange_reference_gas_between_rooms(") == 2
    active = body(source, "_exchange_owned_o2_active_flow")
    assert "_estimate_interior_transport_delay_s" not in active
    assert "effective_mole_fraction" not in active
    assert 'cold_room.o2_net_transport_kg_step += float(moved["receiver_net_kg"])' in active


def test_pair_reads_both_current_inventories_and_has_no_queue_or_clamp():
    pair = body(text(OWNER), "exchange_reference_gas_between_rooms")
    for forbidden in ("clampf(", "o2_nominal", "effective_mole_fraction", "o2_lower", "o2_upper", "_transit.append"):
        assert forbidden not in pair
    assert "exchanged_gas_kg > minf(donor_reference_kg, receiver_reference_kg)" in pair
    first_write = pair.index('_totals[donor.id]["interior_in_kg"]')
    for anchor in ("receiver_before_kg", "donor_before_kg", "receiver_after_kg < 0.0", 'if not _transit.is_empty():'):
        assert pair.index(anchor) < first_write
    assert pair.count("_commit(donor, donor_after_kg)") == 1
    assert pair.count("_commit(receiver, receiver_after_kg)") == 1


@pytest.mark.parametrize("path", [
    "sim/fire/CombustionSystem.gd", "sim/fire/PrescribedObjectHrrSource.gd",
    "sim/core/GasExchangeSystem.gd", "sim/core/SimulationEngine.gd", "sim/building/RoomModel.gd",
])
def test_fire_other_species_gas_state_and_activation_are_unchanged(path):
    assert text(path) == base(path)


@pytest.mark.parametrize("method", ["dilute_with_outside", "outside_dilution_would_apply", "consume"])
def test_owner_dilution_and_sink_are_frozen(method):
    assert body(text(OWNER), method) == body(base(OWNER), method)


@pytest.mark.parametrize("method", ["_step_owned_room_inventory", "_estimate_interior_transport_delay_s"])
def test_sink_and_general_transport_delay_are_frozen(method):
    assert body(text(OXYGEN), method) == body(base(OXYGEN), method)


def test_all_mutations_are_real_unique_replacements_with_predeclared_groups():
    originals, variants = mutations.machinery.prepared(mutations.MUTATIONS, (OWNER, OXYGEN))
    assert len(variants) == len(mutations.MUTATIONS) == 12
    for name, (relative, variant) in variants.items():
        assert variant != originals[relative].decode("utf-8")
        assert mutations.MUTATIONS[name][4] in {"T01", "T02", "T03", "T04", "T05"}


def test_report_declares_other_species_delay_and_diagnostic_legacy_scope():
    source = text(OWNER)
    assert '"live_transport_policy": "symmetric_reference_gas_immediate_o2_only"' in source
    assert '"legacy_signed_transit_scope": "explicit_diagnostic_injection_only"' in source
    assert "other species keep their delays" in source
