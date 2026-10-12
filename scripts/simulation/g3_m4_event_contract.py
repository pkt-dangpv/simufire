"""M4-B1 OFFLINE event contract, not a live adapter or a physical flow law.

All quantities, stages, identities and reference geometries are imposed.
Physical gas packets are refused: no physical/reference mapping is approved.
No simulation import, rates, selection/reservation, persistence or activation.
Frozen books permit all-or-nothing proposals across both ends of a transfer.
"""
from dataclasses import dataclass, replace
import math

from scripts.simulation.g3_m4_partition_contract import Partition, mix, remap


TOL_KG = 1e-9  # receipt/conversion comparison only; never permission to overdraft
KAPPA = .031998 / .0289647
REFERENCE = "reference_dry_air_v1"
STAGES = ("oxygen", "thermal", "gas", "reconcile")


def _integer(value, name):
    if type(value) is not int or value < 0:
        raise ValueError(name)


def _text(value, name):
    if type(value) is not str or not value.strip():
        raise ValueError(name)


def _amount(value, name):
    if type(value) not in (int, float):
        raise ValueError(name)
    try:
        valid = math.isfinite(value) and value >= 0
    except OverflowError:
        valid = False
    if not valid:
        raise ValueError(name)


def _sum(values):
    try:
        return math.fsum(values)
    except OverflowError as error:
        raise ValueError("aggregate_not_finite") from error


@dataclass(frozen=True)
class Context:
    generation: int
    tick: int
    stage: str


@dataclass(frozen=True)
class Room:
    room_id: int
    partition: Partition
    interface_m: float
    height_m: float
    revision: int = 0


@dataclass(frozen=True)
class Endpoint:
    room_id: int
    zone: str


@dataclass(frozen=True)
class Opening:
    uid: str
    room_a: int
    room_b: int | None  # None denotes exterior


@dataclass(frozen=True)
class Parcel:
    contribution_id: str
    kind: str  # transfer / boundary_in / boundary_out / consume
    source: Endpoint | None
    target: Endpoint | None
    oxygen_kg: float  # accepted amount, not a request awaiting a cap
    gas_kg: float | None = None
    basis: str = REFERENCE
    exterior_fraction: float | None = None


@dataclass(frozen=True)
class Mix:
    contribution_id: str
    room_id: int
    fraction: float  # imposed alpha, not alpha(dt)


@dataclass(frozen=True)
class Remap:
    contribution_id: str
    room_id: int
    upper_base_kg: float
    interface_m: float
    representation: str = "geometric_only"
    covered_by_event_id: str | None = None


@dataclass(frozen=True)
class Event:
    context: Context
    physical_event_id: str
    cause: str
    expected_rooms: tuple[Room, ...]
    actions: tuple[Parcel | Mix | Remap, ...]
    opening_uid: str | None = None


@dataclass(frozen=True)
class Book:
    context: Context
    rooms: tuple[Room, ...]
    openings: tuple[Opening, ...] = ()
    seen: frozenset[tuple[int, int, str]] = frozenset()


@dataclass(frozen=True)
class Change:
    before: Room
    after: Room
    upper_delta_kg: float
    lower_delta_kg: float


@dataclass(frozen=True)
class Receipt:
    event: Event
    changes: tuple[Change, ...]


def _context(context):
    if type(context) is not Context:
        raise ValueError("invalid_context")
    _integer(context.generation, "generation")
    _integer(context.tick, "tick")
    if type(context.stage) is not str or context.stage not in STAGES:
        raise ValueError("stage")


def _room(room):
    if type(room) is not Room or type(room.partition) is not Partition:
        raise ValueError("invalid_room_snapshot")
    _integer(room.room_id, "room_id")
    _integer(room.revision, "revision")
    p = room.partition
    for value in (p.total_kg, p.upper_kg, p.upper_base_kg, p.lower_base_kg):
        _amount(value, "partition_amount")
    Partition(p.total_kg, p.upper_kg, p.upper_base_kg, p.lower_base_kg)
    _amount(room.interface_m, "interface")
    _amount(room.height_m, "height")
    if room.height_m == 0 or room.interface_m > room.height_m:
        raise ValueError("interface_outside_room")


def _book(book):
    if type(book) is not Book or type(book.rooms) is not tuple or type(book.openings) is not tuple:
        raise ValueError("invalid_book")
    _context(book.context)
    rooms = {}
    for room in book.rooms:
        _room(room)
        if room.room_id in rooms:
            raise ValueError("duplicate_room")
        rooms[room.room_id] = room
    if not rooms or type(book.seen) is not frozenset:
        raise ValueError("invalid_book")
    for key in book.seen:
        if type(key) is not tuple or len(key) != 3:
            raise ValueError("invalid_seen_key")
        _integer(key[0], "seen_generation")
        _integer(key[1], "seen_tick")
        _text(key[2], "seen_event_id")
    openings = {}
    for opening in book.openings:
        if type(opening) is not Opening:
            raise ValueError("invalid_opening")
        _text(opening.uid, "opening_uid")
        _integer(opening.room_a, "opening_room")
        if opening.room_b is not None:
            _integer(opening.room_b, "opening_room")
        if opening.uid in openings or opening.room_a == opening.room_b:
            raise ValueError("duplicate_or_self_opening")
        if opening.room_a not in rooms or (opening.room_b is not None and opening.room_b not in rooms):
            raise ValueError("opening_unknown_room")
        openings[opening.uid] = opening
    return rooms, openings


def _endpoint(endpoint, rooms):
    if type(endpoint) is not Endpoint:
        raise ValueError("endpoint_required")
    _integer(endpoint.room_id, "endpoint_room")
    if endpoint.room_id not in rooms or type(endpoint.zone) is not str or endpoint.zone not in ("upper", "lower"):
        raise ValueError("unknown_endpoint")
    p = rooms[endpoint.room_id].partition
    inventory = p.upper_kg if endpoint.zone == "upper" else p.lower_kg
    base = p.upper_base_kg if endpoint.zone == "upper" else p.lower_base_kg
    if base == 0:
        raise ValueError("absent_zone")
    return inventory, base


def _opening(event, parcel, openings):
    source = parcel.source.room_id if parcel.source is not None else None
    target = parcel.target.room_id if parcel.target is not None else None
    if parcel.kind == "transfer" and source != target and event.opening_uid is None:
        raise ValueError("cross_room_opening_required")
    if event.opening_uid is not None:
        _text(event.opening_uid, "opening_uid")
        if event.opening_uid not in openings:
            raise ValueError("unknown_opening")
        opening = openings[event.opening_uid]
        if {source, target} != {opening.room_a, opening.room_b}:
            raise ValueError("opening_endpoints_mismatch")


def _parcel(parcel, event, rooms, openings):
    if type(parcel.kind) is not str or parcel.kind not in ("transfer", "boundary_in", "boundary_out", "consume"):
        raise ValueError("unknown_parcel_kind")
    _amount(parcel.oxygen_kg, "oxygen_amount")
    source_required = parcel.kind != "boundary_in"
    target_required = parcel.kind in ("transfer", "boundary_in")
    if (parcel.source is not None) != source_required or (parcel.target is not None) != target_required:
        raise ValueError("parcel_endpoints")
    if parcel.kind == "transfer" and parcel.source == parcel.target:
        raise ValueError("self_transfer")
    source_inventory, source_base = _endpoint(parcel.source, rooms) if source_required else (None, None)
    if target_required:
        _endpoint(parcel.target, rooms)
    _opening(event, parcel, openings)
    if parcel.kind == "consume":
        if (parcel.basis != "oxygen_mass_kg" or parcel.gas_kg is not None
                or parcel.exterior_fraction is not None or event.opening_uid is not None):
            raise ValueError("consume_units")
    else:
        if type(parcel.basis) is not str or parcel.basis != REFERENCE:
            raise ValueError("physical_reference_mapping_not_established")
        _amount(parcel.gas_kg, "reference_gas_amount")
        if source_required:
            if parcel.exterior_fraction is not None:
                raise ValueError("unexpected_exterior_fraction")
            fraction = source_inventory / source_base
            if parcel.gas_kg > source_base / KAPPA:
                raise ValueError("gas_exceeds_donor_reference_content")
        else:
            _amount(parcel.exterior_fraction, "exterior_fraction")
            if parcel.exterior_fraction > 1:
                raise ValueError("exterior_fraction")
            fraction = parcel.exterior_fraction
        expected_kg = fraction * (parcel.gas_kg * KAPPA)
        if not math.isfinite(expected_kg) or abs(parcel.oxygen_kg - expected_kg) > TOL_KG:
            raise ValueError("oxygen_reference_conversion_mismatch")


def apply_event(book, event):
    """Return a NEW book/receipt after validating the entire event; never mutate.

    Parcel donors are sampled from the same expected pre-event snapshots.
    Incoming oxygen cannot fund any donation within this atomic event.
    One event is either parcels, one imposed mix, or one geometric-only remap.
    """
    rooms, openings = _book(book)
    if type(event) is not Event:
        raise ValueError("invalid_event")
    _context(event.context)
    if event.context != book.context:
        raise ValueError("wrong_generation_tick_or_stage")
    _text(event.physical_event_id, "physical_event_id")
    _text(event.cause, "cause")
    key = (event.context.generation, event.context.tick, event.physical_event_id)
    if key in book.seen:
        raise ValueError("physical_event_already_accepted")
    if type(event.actions) is not tuple or not event.actions or type(event.expected_rooms) is not tuple:
        raise ValueError("actions_and_snapshots_required")
    expected = {}
    for snapshot in event.expected_rooms:
        _room(snapshot)
        if snapshot.room_id in expected or rooms.get(snapshot.room_id) != snapshot:
            raise ValueError("stale_or_duplicate_snapshot")
        expected[snapshot.room_id] = snapshot
    touched, contributions = set(), set()
    for action in event.actions:
        if type(action) not in (Parcel, Mix, Remap):
            raise ValueError("unknown_action")
        _text(action.contribution_id, "contribution_id")
        if action.contribution_id in contributions:
            raise ValueError("duplicate_contribution")
        contributions.add(action.contribution_id)
        if type(action) is Parcel:
            _parcel(action, event, rooms, openings)
            touched.update(endpoint.room_id for endpoint in (action.source, action.target) if endpoint is not None)
        else:
            _integer(action.room_id, "action_room")
            touched.add(action.room_id)
    if touched != set(expected):
        raise ValueError("exact_participant_snapshots_required")

    after, deltas = {}, {}
    if all(type(action) is Parcel for action in event.actions):
        outgoing, gas_outgoing = {}, {}
        zonal = {room_id: {"upper": [], "lower": []} for room_id in touched}
        for parcel in event.actions:
            if parcel.source is not None:
                outgoing.setdefault(parcel.source, []).append(parcel.oxygen_kg)
                gas_outgoing.setdefault(parcel.source, []).append(parcel.gas_kg or 0.0)
                zonal[parcel.source.room_id][parcel.source.zone].append(-parcel.oxygen_kg)
            if parcel.target is not None:
                zonal[parcel.target.room_id][parcel.target.zone].append(parcel.oxygen_kg)
        for endpoint, amounts in outgoing.items():
            inventory, base = _endpoint(endpoint, rooms)
            if _sum(amounts) > inventory:
                raise ValueError("aggregate_donor_overdraft")
            if _sum(gas_outgoing[endpoint]) > base / KAPPA:
                raise ValueError("aggregate_reference_gas_overdraft")
        for room_id, zones in zonal.items():
            before = rooms[room_id]
            du, dl = _sum(zones["upper"]), _sum(zones["lower"])
            p = before.partition
            candidate = Partition(p.total_kg + _sum((du, dl)), p.upper_kg + du,
                                  p.upper_base_kg, p.lower_base_kg)
            after[room_id] = replace(before, partition=candidate, revision=before.revision + 1)
            deltas[room_id] = (du, dl)
    else:
        if len(event.actions) != 1 or type(event.actions[0]) not in (Mix, Remap) or event.opening_uid is not None:
            raise ValueError("mixed_representations_not_established")
        action = event.actions[0]
        before = rooms[action.room_id]
        if type(action) is Mix:
            _amount(action.fraction, "mix_fraction")
            if action.fraction > 1:
                raise ValueError("mix_fraction")
            result = mix(before.partition, action.fraction)
            next_interface = before.interface_m
        else:
            if action.representation != "geometric_only" or action.covered_by_event_id is not None:
                raise ValueError("interface_transfer_mapping_not_established")
            _amount(action.upper_base_kg, "remap_base")
            result = remap(before.partition, action.upper_base_kg)
            _amount(action.interface_m, "interface")
            if action.interface_m > before.height_m:
                raise ValueError("interface_outside_room")
            next_interface = action.interface_m
        after[action.room_id] = replace(before, partition=result.after, interface_m=next_interface,
                                        revision=before.revision + 1)
        deltas[action.room_id] = (result.upper_delta_kg, result.lower_delta_kg)

    changes = tuple(Change(rooms[i], after[i], *deltas[i]) for i in sorted(touched))
    candidate_book = replace(book, rooms=tuple(after.get(r.room_id, r) for r in book.rooms),
                             seen=book.seen | {key})
    _book(candidate_book)
    receipt = Receipt(event, changes)
    return candidate_book, receipt


def audit_receipt(receipt):
    """Read before/after and accepted legs independently, without apply_event.

    Checks budget/metadata, not origin of identities or physical routing.
    Imposed mix/remap results are checked algebraically, not as physical laws.
    """
    errors = []
    if type(receipt) is not Receipt or type(receipt.changes) is not tuple:
        return ["invalid_receipt"]
    try:
        if type(receipt.event) is not Event:
            raise ValueError("invalid_receipt_event")
        _context(receipt.event.context)
        _text(receipt.event.physical_event_id, "receipt_event_id")
        _text(receipt.event.cause, "receipt_cause")
        if type(receipt.event.actions) is not tuple or not receipt.event.actions:
            raise ValueError("receipt_actions")
        if type(receipt.event.expected_rooms) is not tuple:
            raise ValueError("receipt_snapshots")
        ids = set()
        for action in receipt.event.actions:
            if type(action) not in (Parcel, Mix, Remap):
                raise ValueError("receipt_action")
            _text(action.contribution_id, "receipt_contribution")
            if action.contribution_id in ids:
                raise ValueError("receipt_duplicate_contribution")
            ids.add(action.contribution_id)
        declared = {}
        for change in receipt.changes:
            _room(change.before)
            _room(change.after)
            if change.before.room_id != change.after.room_id or change.before.room_id in declared:
                errors.append("room_identity")
            declared[change.before.room_id] = change
            before, after = change.before.partition, change.after.partition
            if change.after.revision != change.before.revision + 1:
                errors.append("revision")
            if change.after.height_m != change.before.height_m:
                errors.append("height_changed")
            for actual, delta in ((after.upper_kg - before.upper_kg, change.upper_delta_kg),
                                  (after.lower_kg - before.lower_kg, change.lower_delta_kg),
                                  (after.total_kg - before.total_kg,
                                   change.upper_delta_kg + change.lower_delta_kg)):
                if type(delta) not in (int, float) or not math.isfinite(delta) or abs(actual - delta) > TOL_KG:
                    errors.append("budget")
            if abs(after.base_kg - before.base_kg) > TOL_KG:
                errors.append("reference_content_changed")
        expected = {room.room_id: room for room in receipt.event.expected_rooms}
        if (len(expected) != len(receipt.event.expected_rooms)
                or expected != {i: c.before for i, c in declared.items()}):
            errors.append("snapshot_mismatch")
        if all(type(a) is Parcel for a in receipt.event.actions):
            for change in receipt.changes:
                before, after = change.before.partition, change.after.partition
                if (before.upper_base_kg != after.upper_base_kg
                        or before.lower_base_kg != after.lower_base_kg
                        or change.before.interface_m != change.after.interface_m):
                    errors.append("parcel_geometry_changed")
            pairs = {i: {"upper": [], "lower": []} for i in declared}
            outgoing, gas_outgoing = {}, {}
            for parcel in receipt.event.actions:
                _amount(parcel.oxygen_kg, "receipt_oxygen")
                if parcel.kind not in ("transfer", "boundary_in", "boundary_out", "consume"):
                    raise ValueError("receipt_kind")
                if ((parcel.source is not None) != (parcel.kind != "boundary_in")
                        or (parcel.target is not None) != (parcel.kind in ("transfer", "boundary_in"))):
                    raise ValueError("receipt_endpoints")
                if parcel.kind == "consume":
                    if (parcel.basis != "oxygen_mass_kg" or parcel.gas_kg is not None
                            or parcel.exterior_fraction is not None):
                        raise ValueError("receipt_consume_units")
                else:
                    _amount(parcel.gas_kg, "receipt_gas")
                    if parcel.basis != REFERENCE:
                        raise ValueError("receipt_gas_basis")
                    if parcel.source is None:
                        _amount(parcel.exterior_fraction, "receipt_exterior")
                        fraction = parcel.exterior_fraction
                        if fraction > 1:
                            raise ValueError("receipt_exterior")
                    else:
                        p = declared[parcel.source.room_id].before.partition
                        fraction = p.fractions()[parcel.source.zone]
                        if fraction is None or parcel.exterior_fraction is not None:
                            raise ValueError("receipt_source")
                    oxygen_expected = fraction * parcel.gas_kg * (.031998 / .0289647)
                    if not math.isfinite(oxygen_expected) or abs(oxygen_expected - parcel.oxygen_kg) > TOL_KG:
                        errors.append("reference_conversion")
                if parcel.source is not None:
                    outgoing.setdefault(parcel.source, []).append(parcel.oxygen_kg)
                    gas_outgoing.setdefault(parcel.source, []).append(parcel.gas_kg or 0.0)
                for endpoint, sign in ((parcel.source, -1), (parcel.target, 1)):
                    if endpoint is not None:
                        pairs[endpoint.room_id][endpoint.zone].append(sign * parcel.oxygen_kg)
            for room_id, zones in pairs.items():
                for zone in ("upper", "lower"):
                    delta = getattr(declared[room_id], zone + "_delta_kg")
                    if abs(delta - math.fsum(zones[zone])) > TOL_KG:
                        errors.append("accepted_legs_mismatch")
            for endpoint, amounts in outgoing.items():
                p = declared[endpoint.room_id].before.partition
                inventory = p.upper_kg if endpoint.zone == "upper" else p.lower_kg
                base = p.upper_base_kg if endpoint.zone == "upper" else p.lower_base_kg
                if math.fsum(amounts) > inventory or math.fsum(gas_outgoing[endpoint]) > base / KAPPA:
                    errors.append("gross_donor_overdraft")
        else:
            if len(receipt.event.actions) != 1 or type(receipt.event.actions[0]) not in (Mix, Remap):
                raise ValueError("receipt_mixed_representations")
            if any(c.before.partition.total_kg != c.after.partition.total_kg for c in receipt.changes):
                errors.append("internal_total_changed")
            action = receipt.event.actions[0]
            if len(declared) != 1 or action.room_id not in declared:
                raise ValueError("receipt_redistribution_room")
            change = declared[action.room_id]
            p = change.before.partition
            if type(action) is Mix:
                _amount(action.fraction, "receipt_mix_fraction")
                if action.fraction > 1:
                    raise ValueError("receipt_mix_fraction")
                target = p.total_kg * (p.upper_base_kg / p.base_kg)
                expected_upper = (1 - action.fraction) * p.upper_kg + action.fraction * target
                if (change.before.interface_m != change.after.interface_m
                        or p.upper_base_kg != change.after.partition.upper_base_kg):
                    errors.append("mix_geometry_changed")
            else:
                if action.representation != "geometric_only" or action.covered_by_event_id is not None:
                    raise ValueError("receipt_interface_representation")
                _amount(action.upper_base_kg, "receipt_remap_base")
                _amount(action.interface_m, "receipt_remap_interface")
                if action.upper_base_kg > p.base_kg:
                    raise ValueError("receipt_remap_base")
                difference = action.upper_base_kg - p.upper_base_kg
                donor_fraction = (p.lower_kg / p.lower_base_kg if difference > 0
                                  else p.upper_kg / p.upper_base_kg if difference < 0 else 0)
                expected_upper = p.upper_kg + difference * donor_fraction
                if (change.after.interface_m != action.interface_m
                        or change.after.partition.upper_base_kg != action.upper_base_kg):
                    errors.append("remap_geometry_mismatch")
            if abs(change.after.partition.upper_kg - expected_upper) > TOL_KG:
                errors.append("redistribution_profile_mismatch")
    except (ValueError, TypeError, AttributeError, KeyError, OverflowError, ZeroDivisionError):
        errors.append("invalid_receipt_data")
    return sorted(set(errors))
