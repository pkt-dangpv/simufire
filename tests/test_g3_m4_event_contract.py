"""Imposed offline M4-B1 events; no simulation consumer, Godot or physical data."""
from dataclasses import FrozenInstanceError, asdict, replace
import math
from pathlib import Path
import sys
import types

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.simulation import g3_m4_event_contract as c
from scripts.simulation.g3_m4_partition_contract import Partition


def _book():
    return c.Book(c.Context(7, 1, "oxygen"), (
        c.Room(1, Partition(4, 1, 10, 10), 1.5, 3),
        c.Room(2, Partition(4, 2, 10, 10), 1.5, 3),
    ), (c.Opening("door-0", 1, 2), c.Opening("door-1", 1, 2), c.Opening("window-0", 1, None)))


def _parcel(book, contribution="out", source=None, target=None, gas=1):
    # Build endpoints in the CURRENT module; mutant modules have their own types.
    source = c.Endpoint(1, "upper") if source is None else source
    target = c.Endpoint(2, "upper") if target is None else target
    rooms = {r.room_id: r for r in book.rooms}
    p = rooms[source.room_id].partition
    fraction = p.fractions()[source.zone]
    return c.Parcel(contribution, "transfer", source, target, fraction * gas * c.KAPPA, gas)


def _event(book, actions=None, event_id="physical-0", opening="door-0"):
    if actions is None:
        actions = (_parcel(book),)
    participants = set()
    for action in actions:
        if type(action) is c.Parcel:
            participants.update(e.room_id for e in (action.source, action.target) if e is not None)
        else:
            participants.add(action.room_id)
    return c.Event(book.context, event_id, "imposed_synthetic_event",
                   tuple(r for r in book.rooms if r.room_id in participants), actions, opening)


def _refused(book, event, reason=None):
    original = asdict(book)
    with pytest.raises(ValueError, match=reason):
        c.apply_event(book, event)
    assert asdict(book) == original


def test_paired_transfer_samples_declared_zone_not_room_mean():
    book = _book()
    after, receipt = c.apply_event(book, _event(book))
    amount = .1 * c.KAPPA
    assert after.rooms[0].partition.upper_kg == pytest.approx(1 - amount)
    assert after.rooms[1].partition.upper_kg == pytest.approx(2 + amount)
    assert sum(r.partition.total_kg for r in after.rooms) == pytest.approx(8)
    assert book == _book() and c.audit_receipt(receipt) == []
    assert after.rooms[0].interface_m == book.rooms[0].interface_m


def test_counterflow_samples_both_donors_from_same_pre_event_state():
    book = _book()
    forward = _parcel(book)
    reverse = _parcel(book, "return", c.Endpoint(2, "lower"), c.Endpoint(1, "lower"))
    after, receipt = c.apply_event(book, _event(book, (forward, reverse)))
    assert after.rooms[0].partition.total_kg == pytest.approx(4 + (.2 - .1) * c.KAPPA)
    assert after.rooms[1].partition.total_kg == pytest.approx(4 - (.2 - .1) * c.KAPPA)
    assert c.audit_receipt(receipt) == []


@pytest.mark.parametrize("renamed_contribution", [False, True])
def test_same_physical_event_is_not_accepted_twice_even_with_new_contribution(renamed_contribution):
    book = _book()
    after, _ = c.apply_event(book, _event(book))
    name = "renamed" if renamed_contribution else "out"
    _refused(after, _event(after, (_parcel(after, name),)), "physical_event_already_accepted")


def test_same_event_cannot_be_replayed_as_remap_in_another_stage():
    book = _book()
    after, _ = c.apply_event(book, _event(book))
    thermal = replace(after, context=replace(after.context, stage="thermal"))
    remap = c.Remap("geometry", 1, 12, 1.2)
    _refused(thermal, _event(thermal, (remap,), opening=None), "physical_event_already_accepted")


def test_two_registered_doors_between_same_rooms_are_distinct():
    book = _book()
    after, _ = c.apply_event(book, _event(book))
    again, receipt = c.apply_event(after, _event(after, event_id="physical-1", opening="door-1"))
    assert len(again.seen) == 2 and c.audit_receipt(receipt) == []


@pytest.mark.parametrize("field,value", [("generation", 8), ("tick", 2), ("stage", "thermal")])
def test_wrong_live_context_is_refused(field, value):
    book = _book()
    event = _event(book)
    _refused(book, replace(event, context=replace(event.context, **{field: value})), "wrong_generation")


@pytest.mark.parametrize("field,value", [
    ("generation", True), ("tick", 1.0), ("tick", -1), ("stage", []), ("stage", "fire"),
])
def test_context_types_and_stage_vocabulary_are_explicit(field, value):
    book = _book()
    _refused(book, replace(_event(book), context=replace(book.context, **{field: value})))


def test_stale_inventory_geometry_and_revision_are_each_refused():
    book = _book()
    event = _event(book)
    old = book.rooms[0]
    alternatives = (replace(old, partition=Partition(4, 1.1, 10, 10)),
                    replace(old, interface_m=1.4), replace(old, revision=1))
    for stale in alternatives:
        _refused(book, replace(event, expected_rooms=(stale, book.rooms[1])), "stale")


@pytest.mark.parametrize("defect", ["missing", "duplicate", "extra", "mutable"])
def test_exact_immutable_participant_snapshots_are_required(defect):
    book = _book()
    event = _event(book)
    if defect == "missing":
        snapshots = (book.rooms[0],)
    elif defect == "duplicate":
        snapshots = (book.rooms[0], book.rooms[0], book.rooms[1])
    elif defect == "extra":
        only_first = c.Parcel("debit", "consume", c.Endpoint(1, "upper"), None, .1, basis="oxygen_mass_kg")
        event = _event(book, (only_first,), opening=None)
        snapshots = book.rooms
    else:
        snapshots = list(book.rooms)
    _refused(book, replace(event, expected_rooms=snapshots))


@pytest.mark.parametrize("opening", [None, "unknown", "window-0", "op_1_2_door"])
def test_cross_room_transfer_requires_registered_matching_opening(opening):
    book = _book()
    _refused(book, _event(book, opening=opening))


@pytest.mark.parametrize("basis", ["physical_gas_kg", "mole_fraction_times_gas_kg", "kg", False, []])
def test_physical_or_ambiguous_gas_basis_is_not_automatically_converted(basis):
    book = _book()
    parcel = replace(_parcel(book), basis=basis)
    _refused(book, _event(book, (parcel,)), "physical_reference_mapping_not_established")


@pytest.mark.parametrize("field,value", [
    ("oxygen_kg", True), ("oxygen_kg", -.1), ("oxygen_kg", math.nan), ("oxygen_kg", math.inf),
    ("oxygen_kg", "0.1"), ("gas_kg", False), ("gas_kg", -1), ("gas_kg", math.inf),
    ("gas_kg", None), ("gas_kg", 10 ** 1000),
])
def test_nonfinite_wrong_type_or_negative_quantities_are_atomic_refusals(field, value):
    book = _book()
    _refused(book, _event(book, (replace(_parcel(book), **{field: value}),)))


def test_mole_fraction_cannot_be_multiplied_by_gas_mass_without_molar_conversion():
    book = _book()
    _refused(book, _event(book, (replace(_parcel(book), oxygen_kg=.1),)), "conversion_mismatch")


def test_aggregate_donor_cannot_spend_same_inventory_multiple_times():
    book = _book()
    leg = _parcel(book, gas=6)
    _refused(book, _event(book, (leg, replace(leg, contribution_id="second"))), "aggregate_donor_overdraft")


def test_incoming_parcel_cannot_finance_simultaneous_donation():
    book = _book()
    book = replace(book, rooms=(replace(book.rooms[0], partition=Partition(.01, .01, 10, 10)), book.rooms[1]))
    incoming = c.Parcel("in", "boundary_in", None, c.Endpoint(1, "upper"),
                        .209 * c.KAPPA, 1, exterior_fraction=.209)
    debit = c.Parcel("out", "consume", c.Endpoint(1, "upper"), None, .1, basis="oxygen_mass_kg")
    # The candidate net inventory would be positive; gross donation still overdrafts.
    assert book.rooms[0].partition.upper_kg + incoming.oxygen_kg - debit.oxygen_kg > 0
    _refused(book, _event(book, (incoming, debit), opening=None), "aggregate_donor_overdraft")


def test_receiver_overfill_does_not_commit_the_valid_donor_or_identity():
    book = _book()
    book = replace(book, rooms=(book.rooms[0], replace(book.rooms[1], partition=Partition(12, 10, 10, 10))))
    _refused(book, _event(book), "capacity")
    assert not book.seen and book.rooms[0].revision == 0


@pytest.mark.parametrize("endpoint", [c.Endpoint(7, "upper"), c.Endpoint(True, "upper"),
                                      c.Endpoint(1, "room"), c.Endpoint(1, [])])
def test_unknown_or_untyped_endpoint_cannot_be_replaced_by_room_average(endpoint):
    book = _book()
    _refused(book, _event(book, (replace(_parcel(book), source=endpoint),)))


@pytest.mark.parametrize("side", ["source", "target"])
def test_absent_zone_is_not_ambient_or_an_epsilon_reservoir(side):
    book = _book()
    absent_room = 1 if side == "source" else 2
    book = replace(book, rooms=tuple(replace(r, partition=Partition(4, 0, 0, 20), interface_m=3)
                                    if r.room_id == absent_room else r for r in book.rooms))
    parcel = c.Parcel("p", "transfer", c.Endpoint(1, "upper"), c.Endpoint(2, "upper"), 0, 0)
    _refused(book, _event(book, (parcel,)), "absent_zone")


@pytest.mark.parametrize("kind", ["boundary_in", "boundary_out", "consume"])
def test_boundary_and_consumption_are_explicit_not_net_deltas(kind):
    book = _book()
    endpoint = c.Endpoint(1, "lower")
    if kind == "boundary_in":
        parcel = c.Parcel("p", kind, None, endpoint, .209 * c.KAPPA, 1, exterior_fraction=.209)
        delta = parcel.oxygen_kg
    elif kind == "boundary_out":
        parcel = c.Parcel("p", kind, endpoint, None, .3 * c.KAPPA, 1)
        delta = -parcel.oxygen_kg
    else:
        parcel = c.Parcel("p", kind, endpoint, None, .4, basis="oxygen_mass_kg")
        delta = -.4
    after, receipt = c.apply_event(book, _event(book, (parcel,), opening=None))
    assert after.rooms[0].partition.total_kg == pytest.approx(4 + delta)
    assert after.rooms[1] == book.rooms[1] and c.audit_receipt(receipt) == []


@pytest.mark.parametrize("defect", ["unknown", "same_endpoint", "missing_source", "extra_exterior", "bad_consume"])
def test_parcel_shapes_and_units_are_not_inferred(defect):
    book = _book()
    parcel = _parcel(book)
    if defect == "unknown":
        parcel = replace(parcel, kind="net_room_delta")
    elif defect == "same_endpoint":
        parcel = replace(parcel, target=parcel.source)
    elif defect == "missing_source":
        parcel = replace(parcel, source=None)
    elif defect == "extra_exterior":
        parcel = replace(parcel, exterior_fraction=.209)
    else:
        parcel = replace(parcel, kind="consume", target=None)
    _refused(book, _event(book, (parcel,)))


@pytest.mark.parametrize("actions", [(), [], (None,)])
def test_missing_mutable_or_unknown_actions_are_refused(actions):
    book = _book()
    _refused(book, replace(_event(book), actions=actions))


def test_duplicate_contribution_is_refused_before_book_update():
    book = _book()
    parcel = _parcel(book)
    _refused(book, _event(book, (parcel, parcel)), "duplicate_contribution")


@pytest.mark.parametrize("representation,covered", [("physical_transfer", None), ("unknown", None),
                                                    ("geometric_only", "another-event")])
def test_remap_requires_declared_geometric_only_contribution_without_claimed_transfer(representation, covered):
    book = _book()
    action = c.Remap("geometry", 1, 12, 1.2, representation, covered)
    _refused(book, _event(book, (action,), opening=None), "interface_transfer_mapping_not_established")


def test_remap_and_transfer_cannot_be_combined_without_coverage_mapping():
    book = _book()
    _refused(book, _event(book, (_parcel(book), c.Remap("g", 1, 12, 1.2))), "mixed_representations")


@pytest.mark.parametrize("action,expected", [(c.Mix("m", 1, .5), 1.5), (c.Remap("r", 1, 12, 1.2), 1.6)])
def test_imposed_mix_and_remap_have_separate_analytical_results(action, expected):
    book = _book()
    after, receipt = c.apply_event(book, _event(book, (action,), opening=None))
    assert after.rooms[0].partition.upper_kg == pytest.approx(expected)
    assert after.rooms[0].partition.total_kg == 4 and c.audit_receipt(receipt) == []


def test_room_can_collapse_and_reappear_only_through_explicit_reference_remap():
    book = _book()
    collapsed, _ = c.apply_event(book, _event(book, (c.Remap("r", 1, 0, 3),), opening=None))
    assert collapsed.rooms[0].partition.fractions()["upper"] is None
    revived, receipt = c.apply_event(collapsed, _event(collapsed, (c.Remap("r2", 1, 10, 1.5),),
                                                     event_id="physical-1", opening=None))
    assert revived.rooms[0].partition.upper_kg == 2 and c.audit_receipt(receipt) == []


@pytest.mark.parametrize("defect", ["delta", "state", "leg", "revision", "height", "snapshots", "nan", "empty"])
def test_independent_receipt_audit_detects_validly_typed_corruption(defect):
    book = _book()
    _, receipt = c.apply_event(book, _event(book))
    first, second = receipt.changes
    if defect == "delta":
        receipt = replace(receipt, changes=(replace(first, upper_delta_kg=0), second))
    elif defect == "state":
        p = first.after.partition
        wrong = replace(first.after, partition=Partition(p.total_kg, p.upper_kg + .01, 10, 10))
        receipt = replace(receipt, changes=(replace(first, after=wrong), second))
    elif defect == "leg":
        parcel = replace(receipt.event.actions[0], oxygen_kg=.05)
        receipt = replace(receipt, event=replace(receipt.event, actions=(parcel,)))
    elif defect in ("revision", "height"):
        wrong = replace(first.after, **({"revision": 0} if defect == "revision" else {"height_m": 4}))
        receipt = replace(receipt, changes=(replace(first, after=wrong), second))
    elif defect == "snapshots":
        receipt = replace(receipt, event=replace(receipt.event, expected_rooms=(book.rooms[0],)))
    elif defect == "nan":
        receipt = replace(receipt, changes=(replace(first, upper_delta_kg=math.nan), second))
    else:
        receipt = replace(receipt, event=replace(receipt.event, actions=()))
    assert c.audit_receipt(receipt)


def test_receipt_audit_does_not_call_event_application(monkeypatch):
    _, receipt = c.apply_event(_book(), _event(_book()))
    monkeypatch.setattr(c, "apply_event", lambda *args: pytest.fail("audit reran application"))
    assert c.audit_receipt(receipt) == []


def test_books_receipts_and_nested_state_are_frozen():
    after, receipt = c.apply_event(_book(), _event(_book()))
    for obj, field, value in ((after, "rooms", ()), (after.rooms[0], "revision", 0),
                               (after.rooms[0].partition, "upper_kg", 0), (receipt, "changes", ())):
        with pytest.raises(FrozenInstanceError):
            setattr(obj, field, value)


def test_repeat_synthetic_internal_packets_keep_total_within_accounting_tolerance():
    book = _book()
    for index in range(500):
        source, target = (c.Endpoint(1, "upper"), c.Endpoint(2, "upper"))
        if index % 2:
            source, target = target, source
        event = _event(book, (_parcel(book, source=source, target=target, gas=.1),), event_id=f"p-{index}")
        book, receipt = c.apply_event(book, event)
        assert c.audit_receipt(receipt) == []
    assert abs(sum(r.partition.total_kg for r in book.rooms) - 8) <= c.TOL_KG


def test_model_is_offline_and_does_not_load_simulation_or_define_activation():
    source = (ROOT / "scripts/simulation/g3_m4_event_contract.py").read_text(encoding="utf-8")
    for token in ("subprocess", "RoomModel", "SimulationEngine", "enabled =", "def main("):
        assert token not in source


@pytest.mark.parametrize("defect", ["rooms_list", "seen_set", "duplicate_room", "duplicate_opening",
                                  "unknown_opening_room", "self_opening", "bad_seen", "bad_revision"])
def test_invalid_book_is_rejected_before_any_proposal(defect):
    book = _book()
    event = _event(book)
    if defect == "rooms_list":
        book = replace(book, rooms=list(book.rooms))
    elif defect == "seen_set":
        book = replace(book, seen=set())
    elif defect == "duplicate_room":
        book = replace(book, rooms=(book.rooms[0], book.rooms[0]))
    elif defect == "duplicate_opening":
        book = replace(book, openings=(book.openings[0], book.openings[0]))
    elif defect == "unknown_opening_room":
        book = replace(book, openings=(c.Opening("door", 1, 3),))
    elif defect == "self_opening":
        book = replace(book, openings=(c.Opening("door", 1, 1),))
    elif defect == "bad_seen":
        book = replace(book, seen=frozenset({(True, 1, "p")}))
    else:
        book = replace(book, rooms=(replace(book.rooms[0], revision=True), book.rooms[1]))
    _refused(book, event)


@pytest.mark.parametrize("kind", ["mix", "remap"])
@pytest.mark.parametrize("amount", [True, math.inf, -1, "1", 10 ** 1000])
def test_redistribution_inputs_reject_wrong_types_without_native_or_overflow_failure(kind, amount):
    book = _book()
    action = c.Mix("m", 1, amount) if kind == "mix" else c.Remap("r", 1, amount, 1.5)
    _refused(book, _event(book, (action,), opening=None))


def test_aggregate_reference_gas_overflow_is_named_and_atomic_even_with_zero_oxygen():
    room = c.Room(1, Partition(0, 0, 9e307, 0), 0, 3)
    book = c.Book(c.Context(1, 1, "oxygen"), (room,))
    # Each parcel fits, the summed gas does not; zero O2 must not hide it.
    actions = tuple(c.Parcel(str(i), "boundary_out", c.Endpoint(1, "upper"), None, 0, 8e307)
                    for i in range(3))
    _refused(book, _event(book, actions, opening=None), "aggregate_not_finite")


def test_receipt_gas_units_and_quantity_are_audited_not_only_oxygen_deltas():
    _, receipt = c.apply_event(_book(), _event(_book()))
    for wrong in (replace(receipt.event.actions[0], gas_kg=2),
                  replace(receipt.event.actions[0], basis="physical_gas_kg")):
        assert c.audit_receipt(replace(receipt, event=replace(receipt.event, actions=(wrong,))))


@pytest.mark.parametrize("field", ["base_split", "interface"])
def test_parcel_receipt_cannot_change_geometry_without_changing_oxygen(field):
    _, receipt = c.apply_event(_book(), _event(_book()))
    change = receipt.changes[0]
    p = change.after.partition
    if field == "base_split":
        wrong = replace(change.after, partition=Partition(p.total_kg, p.upper_kg, 11, 9))
    else:
        wrong = replace(change.after, interface_m=1.4)
    corrupted = replace(receipt, changes=(replace(change, after=wrong), receipt.changes[1]))
    assert "parcel_geometry_changed" in c.audit_receipt(corrupted)


@pytest.mark.parametrize("action", [c.Mix("m", 1, .5), c.Remap("r", 1, 12, 1.2)])
def test_receipt_checks_the_imposed_profile_not_only_internal_conservation(action):
    _, receipt = c.apply_event(_book(), _event(_book(), (action,), opening=None))
    change = receipt.changes[0]
    p = change.after.partition
    wrong = replace(change.after, partition=Partition(p.total_kg, p.upper_kg + .05,
                                                      p.upper_base_kg, p.lower_base_kg))
    corrupted = replace(change, after=wrong, upper_delta_kg=change.upper_delta_kg + .05,
                        lower_delta_kg=change.lower_delta_kg - .05)
    assert c.audit_receipt(replace(receipt, changes=(corrupted,))) == ["redistribution_profile_mismatch"]


# Mutate the actual Python contract IN MEMORY, never any source or engine file.
# Each named witness must fail by an assertion, not syntax/import/runtime error.
MUTATIONS = (
    ("identity", "if key in book.seen:", "if False and key in book.seen:",
     "duplicate"),
    ("context", "if event.context != book.context:", "if False and event.context != book.context:",
     "context"),
    ("conversion", "expected_kg = fraction * (parcel.gas_kg * KAPPA)",
     "expected_kg = fraction * parcel.gas_kg", "valid_packet"),
    ("room_average", "fraction = source_inventory / source_base",
     "fraction = rooms[parcel.source.room_id].partition.total_kg / rooms[parcel.source.room_id].partition.base_kg",
     "valid_packet"),
    ("gross_donor", "if _sum(amounts) > inventory:", "if False and _sum(amounts) > inventory:",
     "incoming_credit"),
    ("opening", 'raise ValueError("cross_room_opening_required")', "pass", "opening"),
    ("duplicate_part", "if action.contribution_id in contributions:",
     "if False and action.contribution_id in contributions:", "duplicate_part"),
    ("stale", "if snapshot.room_id in expected or rooms.get(snapshot.room_id) != snapshot:",
     "if snapshot.room_id in expected:", "stale"),
    ("representation", 'if action.representation != "geometric_only" or action.covered_by_event_id is not None:\n'
     '                raise ValueError("interface_transfer_mapping_not_established")',
     'if False:\n                raise ValueError("interface_transfer_mapping_not_established")', "representation"),
    ("mutable_book", "@dataclass(frozen=True)\nclass Book:", "@dataclass(frozen=False)\nclass Book:",
     "frozen"),
    ("audit", 'errors.append("accepted_legs_mismatch")', "pass", "receipt"),
    ("mix_omitted", "result = mix(before.partition, action.fraction)",
     "result = mix(before.partition, 0)", "mix_result"),
)


def _witness(name):
    if name == "duplicate":
        test_same_physical_event_is_not_accepted_twice_even_with_new_contribution(True)
    elif name == "context":
        test_wrong_live_context_is_refused("generation", 8)
    elif name == "valid_packet":
        try:
            test_paired_transfer_samples_declared_zone_not_room_mean()
        except ValueError as error:
            # Rejection of the predeclared valid reference packet is a contract failure.
            if str(error) != "oxygen_reference_conversion_mismatch":
                raise  # A loader/type error is NOT a valid scientific kill.
            raise AssertionError("valid_packet_refused") from error
    elif name == "incoming_credit":
        test_incoming_parcel_cannot_finance_simultaneous_donation()
    elif name == "opening":
        test_cross_room_transfer_requires_registered_matching_opening(None)
    elif name == "duplicate_part":
        test_duplicate_contribution_is_refused_before_book_update()
    elif name == "stale":
        test_stale_inventory_geometry_and_revision_are_each_refused()
    elif name == "representation":
        test_remap_requires_declared_geometric_only_contribution_without_claimed_transfer("physical_transfer", None)
    elif name == "frozen":
        test_books_receipts_and_nested_state_are_frozen()
    elif name == "receipt":
        # Alter accepted legs without changing their correctly converted quantity:
        # another valid packet size, so only the independent leg budget detects it.
        _, receipt = c.apply_event(_book(), _event(_book()))
        parcel = replace(receipt.event.actions[0], gas_kg=.5, oxygen_kg=.05 * c.KAPPA)
        assert c.audit_receipt(replace(receipt, event=replace(receipt.event, actions=(parcel,))))
    elif name == "mix_result":
        test_imposed_mix_and_remap_have_separate_analytical_results(c.Mix("m", 1, .5), 1.5)
    else:
        raise RuntimeError("unregistered witness")


@pytest.mark.parametrize("name,old,new,witness", MUTATIONS, ids=[m[0] for m in MUTATIONS])
def test_actual_contract_mutant_is_detected_by_declared_witness(name, old, new, witness, monkeypatch):
    path = ROOT / "scripts/simulation/g3_m4_event_contract.py"
    original = path.read_bytes()
    source = original.decode("utf-8")
    assert source.count(old) == 1
    _witness(witness)  # The original control must pass the SAME witness first.
    # Also pass in an unmodified in-memory module, ruling out loader/type artifacts.
    control_name = "_g3_m4b1_control_" + name
    control = types.ModuleType(control_name)
    monkeypatch.setitem(sys.modules, control_name, control)
    exec(compile(source, str(path) + "::control", "exec"), control.__dict__)
    monkeypatch.setattr(sys.modules[__name__], "c", control)
    _witness(witness)
    module_name = "_g3_m4b1_mutant_" + name
    module = types.ModuleType(module_name)
    monkeypatch.setitem(sys.modules, module_name, module)
    compiled = compile(source.replace(old, new), str(path) + "::" + name, "exec")
    exec(compiled, module.__dict__)
    monkeypatch.setattr(sys.modules[__name__], "c", module)
    with pytest.raises((AssertionError, pytest.fail.Exception)):
        _witness(witness)
    assert path.read_bytes() == original
