"""M4-A design witnesses only: no Godot, current engine or calibrated law."""

from dataclasses import FrozenInstanceError, replace
import importlib.util
from pathlib import Path
import random
import subprocess
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "scripts/simulation/g3_m4_partition_contract.py"
SPEC = importlib.util.spec_from_file_location("g3_m4_offline_partition", PATH)
model = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = model
SPEC.loader.exec_module(model)


def state():
    # Upper x=.10, lower x=.20. Room x=.175, NOT either tracer.
    return model.Partition(7, 1, 10, 30)


@pytest.mark.parametrize("bad", [True, "1", None, float("nan"), float("inf"), -float("inf")])
def test_state_rejects_nonnumeric_or_nonfinite_values(bad):
    with pytest.raises(ValueError):
        model.Partition(bad, 1, 10, 30)


@pytest.mark.parametrize("fields", [(-1, 0, 10, 30), (1, 2, 10, 30),
                                    (1, -1, 10, 30), (7, 1, 0, 40),
                                    (7, 1, 10, 0), (41, 10, 10, 30),
                                    (0, 0, 0, 0), (7, 1, -10, 50)])
def test_state_rejects_invalid_partitions_without_clamps(fields):
    with pytest.raises(ValueError):
        model.Partition(*fields)


def test_lower_is_derived_and_cannot_be_an_independent_authority():
    s = state()
    assert s.lower_kg == 6 and s.fractions() == {"room": .175, "upper": .1, "lower": .2}
    with pytest.raises(FrozenInstanceError):
        s.total_kg = 8


@pytest.mark.parametrize("new_upper, expected_upper", [(0, 0), (5, .5), (10, 1),
                                                       (20, 3), (30, 5), (40, 7)])
def test_remap_matches_independent_piecewise_integrals(new_upper, expected_upper):
    # Hand-integrated old profile: .10 over [0,10], .20 over [10,40].
    receipt = model.remap(state(), new_upper)
    assert receipt.after.upper_kg == expected_upper
    assert receipt.after.total_kg == 7
    assert receipt.after.lower_kg == 7 - expected_upper
    assert model.broken_invariants(receipt) == []


@pytest.mark.parametrize("upper_base", [0, 1e-8, 1, 10, 39, 40])
def test_uniform_profile_remains_uniform_under_remap(upper_base):
    receipt = model.remap(model.Partition(8, 2, 10, 30), upper_base)
    assert receipt.after.upper_kg == pytest.approx(.2 * upper_base, abs=1e-12)
    assert receipt.after.lower_kg == pytest.approx(.2 * (40 - upper_base), abs=1e-12)


@pytest.mark.parametrize("upper, lower, fraction", [(0, 40, 0), (40, 0, 1)])
def test_absent_zone_is_absent_not_an_epsilon_or_zero_concentration(upper, lower, fraction):
    s = model.Partition(7, 7 * fraction, upper, lower)
    f = s.fractions()
    assert f["lower" if fraction else "upper"] is None
    assert model.mix(s, 1).after == s


@pytest.mark.parametrize("alpha, expected", [(0, 1), (.5, 1.375), (1, 1.75)])
def test_imposed_mixing_conserves_total_and_moves_the_donor(alpha, expected):
    receipt = model.mix(state(), alpha)
    assert receipt.after.upper_kg == expected
    assert receipt.after.lower_kg == 7 - expected
    assert model.broken_invariants(receipt) == []
    if alpha == 1:
        assert receipt.after.fractions()["upper"] == receipt.after.fractions()["lower"]


def test_mixing_is_bidirectional_not_fresh_air_created_in_the_upper_layer():
    s = model.Partition(7, 3, 10, 30)
    receipt = model.mix(s, .5)
    assert receipt.upper_delta_kg == -.625
    assert receipt.lower_delta_kg == .625


@pytest.mark.parametrize("operation,args", [
    (model.remap, (-1,)), (model.remap, (41,)), (model.remap, (float("nan"),)),
    (model.mix, (-.1,)), (model.mix, (1.01,)), (model.mix, (True,)),
    (model.budget, (0, -7, "lower_sink")),
    (model.budget, (-2, 0, "upper_sink")),
    (model.budget, (10, 0, "overfill")),
    (model.budget, (0, 0, "")), (model.budget, (0, 0, 123)),
    (model.budget, (float("nan"), 0, "bad")),
])
def test_refused_candidate_changes_no_input_state(operation, args):
    s = state()
    before = (s.total_kg, s.upper_kg, s.upper_base_kg, s.lower_base_kg)
    with pytest.raises(ValueError):
        operation(s, *args)
    assert before == (s.total_kg, s.upper_kg, s.upper_base_kg, s.lower_base_kg)


@pytest.mark.parametrize("du,dl,cause", [(0, -.076, "imposed_reserved_sink"),
                                        (.1, -.1, "imposed_transfer"),
                                        (.03, .07, "imposed_external_budget")])
def test_explicit_budget_changes_room_and_partition_once(du, dl, cause):
    receipt = model.budget(state(), du, dl, cause)
    assert receipt.after.total_kg == pytest.approx(7 + du + dl)
    assert receipt.after.upper_kg == pytest.approx(1 + du)
    assert receipt.after.lower_kg == pytest.approx(6 + dl)
    assert model.broken_invariants(receipt) == []


def test_no_ambient_ceiling_discards_a_declared_oxygen_rich_state():
    s = model.Partition(12, 6, 10, 30)  # x_upper=.6 is valid algebra, not a fire case.
    assert model.mix(s, 0).after == s


def test_independent_tracer_relaxations_do_not_close_the_partition():
    # Analytic counterexample to two unequal relaxation rates, NOT a new engine run.
    upper = .1 + .03 * (.175 - .1)
    lower = .2 + .05 * (.175 - .2)
    assert upper * 10 + lower * 30 == pytest.approx(6.985)
    assert upper * 10 + lower * 30 != 7
    assert model.mix(state(), .05).after.total_kg == 7


def test_invalid_tiny_overdraft_is_not_legal_because_it_is_below_budget_tolerance():
    with pytest.raises(ValueError):
        model.Partition(1, -1e-12, 10, 30)


def test_creation_collapse_and_repeated_collapse_have_an_explicit_donor():
    empty_upper = model.Partition(8, 0, 0, 40)
    grown = model.remap(empty_upper, 10)
    assert grown.after.upper_kg == 2 and grown.after.lower_kg == 6
    collapsed = model.remap(grown.after, 0)
    assert collapsed.after == empty_upper
    repeated = model.remap(collapsed.after, 0)
    assert repeated.upper_delta_kg == repeated.lower_delta_kg == 0
    assert repeated.after == empty_upper


@pytest.mark.parametrize("field,value,expected", [
    ("room_delta_kg", .1, "P1_room_budget"),
    ("upper_delta_kg", 0, "P2_upper_budget"),
    ("lower_delta_kg", 0, "P3_lower_budget"),
    ("room_delta_kg", .1, "P4_pair_matches_total"),
    ("room_delta_kg", .1, "P5_internal_preserves_room"),
    ("upper_delta_kg", float("nan"), "P7_finite_receipt"),
])
def test_declared_corrupt_receipt_is_caught_at_the_named_invariant(field, value, expected):
    receipt = model.mix(state(), 1)
    assert expected in model.broken_invariants(replace(receipt, **{field: value}))


def test_changing_the_reference_base_is_not_mixing():
    receipt = model.mix(state(), 1)
    wrong = replace(receipt, after=replace(receipt.after, lower_base_kg=31))
    assert "P6_reference_base_unchanged" in model.broken_invariants(wrong)


def test_conservative_wrong_routing_requires_the_independent_oracle():
    good = model.remap(state(), 20)
    # Wrong reset-to-room average conserves total and even closes every ledger.
    wrong_after = replace(good.after, upper_kg=3.5)
    wrong = replace(good, after=wrong_after, upper_delta_kg=2.5, lower_delta_kg=-2.5)
    assert model.broken_invariants(wrong) == []  # Honest limit of budget-only checks.
    assert wrong.after.upper_kg != 3  # Analytic swept-profile oracle rejects it.


def test_long_deterministic_sequence_has_no_unowned_oxygen():
    rng = random.Random(20261012)
    s = state()
    for _ in range(10000):
        receipt = model.remap(s, rng.uniform(.01, 39.99))
        assert model.broken_invariants(receipt) == []
        receipt = model.mix(receipt.after, rng.random())
        assert model.broken_invariants(receipt) == []
        s = receipt.after
        assert s.total_kg == 7
        assert s.upper_kg + s.lower_kg == pytest.approx(7, abs=1e-12)


def test_design_model_is_not_imported_by_simulation():
    for path in (ROOT / "sim").rglob("*.gd"):
        assert "g3_m4_partition_contract" not in path.read_text(encoding="utf-8")


def test_document_does_not_claim_runtime_or_physical_validation():
    path = ROOT / "docs/validation/G3_O2_M4_PARTITION_CONTRACT_2026-10-12.md"
    prose = " ".join(path.read_text(encoding="utf-8").split())
    for phrase in ("M4 no está implementado en el motor", "CO/FED OFF/NO-GO",
                   "NO-GO a conectar el reparto al fuego", "Sin Godot"):
        assert phrase in prose


def _baseline_body(path, function):
    result = subprocess.run(["git", "show", f"993d98ec:{path}"], cwd=ROOT,
                            capture_output=True, check=True)
    text = result.stdout.decode("utf-8").replace("\r\n", "\n")
    return text.split(f"func {function}(", 1)[1].split("\nfunc ", 1)[0]


def test_baseline_selection_is_room_only_and_not_a_partition():
    source = _baseline_body("sim/core/RoomOxygenInventory.gd", "_select_for_step")
    assert '"deposit": DEPOSIT_ROOM_INVENTORY' in source
    assert "mole_fraction_from_o2_kg(held_kg, room.volume_m3())" in source
    assert "room.o2_upper" not in source and "room.o2_lower" not in source


def test_baseline_auxiliary_relaxations_still_write_both_layer_numbers():
    source = _baseline_body("sim/core/OxygenExchangeSystem.gd", "step")
    assert "room.o2_lower = lerpf(room.o2_lower, room.o2, clampf(0.05 * dt" in source
    assert "room.o2_upper = lerpf(room.o2_upper, _upper_relax_target, clampf(0.03 * dt" in source
    assert "if lower_frac < 0.15:" in source


def test_baseline_multiple_fire_rejection_is_not_a_gate_we_have_lifted():
    source = _baseline_body("sim/core/RoomOxygenInventory.gd", "_environment_errors")
    assert '"combustion_environment_not_supported:multiple_active_fires"' in source
    assert "int(fire_count) > 1" in source
