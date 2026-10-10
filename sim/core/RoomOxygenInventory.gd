extends RefCounted

## G3 OXYGEN AUTHORITY, STAGES M1, M2 AND M2-V. Owner of the oxygen inventory of
## every room, of the oxygen in transit between rooms, and of the one selection
## per room and step that the fire and the sink share.
##
## What is conserved: `M`, kg of O2 in each room, and `T`, kg of O2 dispatched
## and not yet delivered. `M` lives in `RoomModel.o2_inventory_kg` and only this
## owner writes it. `T` lives here, in one queue that belongs to neither end of
## an exchange. `RoomModel.o2` is derived from `M` on every write.
##
## Units and base. 0.209 is a MOLE fraction of the reference mixture, dry air.
## A room holds `n_ref = V * 1.2 kg/m3 / M_air` moles of reference gas, and
## `M = x * n_ref * M_O2`. The base is the reference content of the room, not the
## mass of its hot gas: exact while the moles of the room do not change, an
## approximation in an open hot room. The oxygen a parcel of gas carries is
## `x * (kg of gas / M_air) * M_O2`: a mole fraction is never multiplied by a
## mass of gas directly.
##
## Every change of `M` is an operation with a cause, validated BEFORE anything is
## written. An operation that does not validate writes nothing, is recorded, and
## latches the owner as `rejected`: from then on nothing is applied and the
## engine stops stepping. There is no clamp and no final reconciliation.
##
## `T` is signed. The historical exchange through a doorway credits the hot room
## at once with the net of two opposite parcels and delays the same net for the
## cold room; that law is not changed here. An entry keeps both parcels: the one
## that travels to the receiver and the one already advanced to the donor. Its
## net can be negative: oxygen the receiver still has to hand over. Neither
## parcel is counted in two places: Sum(M) + Sum(T) is what is conserved.
##
## The layer numbers (`o2_upper`, `o2_lower`) are historical auxiliaries until
## stage M4. They are not a partition of `M` and nothing here reads them.
##
## SELECTION (M2). When a step opens, one selection is built for every room from
## its inventory: which deposit is consumed (the room inventory, the only one
## there is), its concentration as a mole fraction, and what is available. The
## fire reads the concentration; the sink debits the deposit and has to present
## that same selection. A selection is never rebuilt inside a step. Between the
## two consumers the inventory changes only by the arrivals of the transit, which
## the oxygen step delivers before the sink: the debit acts on what the deposit
## holds then, and the selection keeps what it held when the fire read it.
## A debit with no selection, or with the one of another room, step or run, is
## refused: with this mode on there is no historical fallback.
##
## AVAILABLE is what the room holds less what it still has to hand over: every
## negative entry in transit to it. A positive entry that has not arrived is not
## counted, so nothing is spent before it arrives and nothing is counted both in
## a room and in transit. It is never below zero. Stage M2 records it and does
## not act on it: fitting the heat to it is stage M3.
##
## DILUTION (M2-V). Pressure venting lets outside gas in, mixes it with the whole
## room and writes the mixture. Here that is one operation with an entry and an
## exit: the gas enters at the outside mole fraction, mixes with the reference
## content of the room, and the same mass of that mixture leaves, so the room
## keeps its reference content. It is an equivalent dilution on that content, not
## a conservation of the mass of gas, and nothing is clipped to a ceiling.
##
## No class_name and no @export: only SimulationEngine loads it, behind a switch
## that is not exported, off by default and reachable from fixtures only.

const VERSION: String = "room_oxygen_inventory_v3"
const REPORT_SCHEMA: String = "g3_room_oxygen_inventory_report_v3"
const SCOPE: String = "room_oxygen_inventory_transit_and_selection_stages_m1_m2_not_a_zonal_inventory"

const M_O2_KG_PER_MOL: float = 0.031998
const M_DRY_AIR_KG_PER_MOL: float = 0.0289647
const REFERENCE_GAS_DENSITY_KG_M3: float = 1.2
const MIN_ROOM_VOLUME_M3: float = 0.1
## Same threshold the historical queue uses to decide a delivery is due.
const DELIVERY_DUE_S: float = 0.000001

const STATE_INACTIVE: String = "inactive"
const STATE_ARMED: String = "armed"
const STATE_REJECTED: String = "rejected"

## The only deposit a selection can name until stage M4.
const DEPOSIT_ROOM_INVENTORY: String = "room_inventory"

const ENTRY_IN_TRANSIT: String = "in_transit"
const ENTRY_DELIVERED: String = "delivered"

## What the engine must be for the routes of M1 to be the ones that run. Read by
## the engine from its own subsystems; any difference refuses the run.
const REQUIRED_ENVIRONMENT: Dictionary = {
	"pressure_network_enabled": false,
	"diagnostic_bench_enabled": false,
	"balance_ledger_enabled": false,
	"oxygen_step_runs_after_the_fire": true,
	"fire_oxygen_mode": "legacy",
	"sink_takes_oxygen_from_the_lower_number": false,
	"phase2b_canonical_combustion_enabled": false,
	"fire_o2_canonical_enabled": false,
	"fire_o2_mass_tracking_enabled": false,
	"fire_blend_with_the_upper_number": 0.0,
	"fire_throttle_by_the_upper_number": false,
	"plume_lower_o2_depletion_fraction": 1.0,
}
const APPROXIMATIONS: Array[String] = [
	"reference content of the room (volume x 1.2 kg/m3), not the mass of its hot gas",
	"reference mixture of dry air, 28.9647 g/mol, for every conversion",
	"no chemical composition of the products: the moles of the room do not change with combustion",
	"no physical zonal inventory: the layer numbers are historical auxiliaries",
	"the transit is the signed net of a counterflow exchange, as the historical law delays it",
	"the fire reads the concentration of the whole room: no zonal availability until stage M4",
]
const SUPPORTED_ROUTES: Array[String] = [
	"fire_sink_room_inventory", "infiltration", "interior_background_exchange",
	"interior_active_flow", "transit_arrival", "pressure_venting",
]

var _state: String = STATE_INACTIVE
var _generation: int = -1
var _step_index: int = 0
var _rooms: Dictionary = {}
var _totals: Dictionary = {}
var _transit: Array[Dictionary] = []
var _next_delivery_id: int = 1
var _transit_dispatched_kg_total: float = 0.0
var _transit_arrived_kg_total: float = 0.0
var _step_operations: Array[Dictionary] = []
var _rejections: Array[Dictionary] = []
var _refused_after_rejection: int = 0
var _selections: Dictionary = {}
var _next_selection_id: int = 1


# ---------------------------------------------------------------- conversions

static func reference_gas_kg(volume_m3: float) -> float:
	return maxf(MIN_ROOM_VOLUME_M3, volume_m3) * REFERENCE_GAS_DENSITY_KG_M3


static func reference_mol(volume_m3: float) -> float:
	return reference_gas_kg(volume_m3) / M_DRY_AIR_KG_PER_MOL


## kg of O2 that `gas_kg` of reference gas carries at mole fraction `x`.
static func o2_kg_in_reference_gas(mole_fraction: float, gas_kg: float) -> float:
	return mole_fraction * (gas_kg / M_DRY_AIR_KG_PER_MOL) * M_O2_KG_PER_MOL


static func o2_kg_from_mole_fraction(mole_fraction: float, volume_m3: float) -> float:
	return mole_fraction * reference_mol(volume_m3) * M_O2_KG_PER_MOL


static func mole_fraction_from_o2_kg(o2_kg: float, volume_m3: float) -> float:
	return o2_kg / (reference_mol(volume_m3) * M_O2_KG_PER_MOL)


# ------------------------------------------------------------------ lifecycle

## Takes the rooms of `building` under authority, each with the oxygen its
## number declares as a mole fraction. Validates everything first: a run that
## does not arm leaves no room under authority.
func arm(building, generation: int, environment: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if _state != STATE_INACTIVE:
		errors.append("already_armed")
	if building == null:
		errors.append("no_building")
	errors.append_array(_environment_errors(environment))
	var candidates: Array = []
	if building != null:
		var outside: Variant = building.outside_o2
		if not _is_fraction(outside):
			errors.append("outside_mole_fraction_not_a_fraction")
		for room_id in building.get_rooms().keys():
			var room = building.get_room(room_id)
			if room == null:
				errors.append("room_missing:%s" % str(room_id))
				continue
			if not _is_positive(room.volume_m3()):
				errors.append("room_volume_not_positive:%d" % room.id)
			if not _is_fraction(room.o2):
				errors.append("room_mole_fraction_not_a_fraction:%d" % room.id)
			if candidates.has(room.id):
				errors.append("room_id_repeated:%d" % room.id)
			candidates.append(room.id)
	if not errors.is_empty():
		_reject("not_armed", {"errors": errors})
		return {"valid": false, "errors": errors}
	_generation = generation
	_state = STATE_ARMED
	for room_id in building.get_rooms().keys():
		var room = building.get_room(room_id)
		_rooms[room.id] = room
		_totals[room.id] = _empty_totals()
		room.o2_inventory_authority = true
		var initial_kg: float = o2_kg_from_mole_fraction(room.o2, room.volume_m3())
		_totals[room.id]["initial_kg"] = initial_kg
		_commit(room, initial_kg)
		_note({"kind": "initialize", "cause": "initial_state", "room": room.id, "after_kg": initial_kg})
	_select_for_step()
	return {"valid": true, "errors": errors}


## Declares the starting oxygen of a room as a mole fraction. Only before the
## first step: afterwards the inventory changes through its operations alone.
func declare_initial_mole_fraction(room, mole_fraction: Variant) -> Dictionary:
	if not _open():
		return _refused()
	if _step_index != 0:
		return _reject_operation("initial_state_declared_after_the_first_step", {"step": _step_index})
	if not _owns(room):
		return _reject_operation("room_not_under_authority", {})
	if not _is_fraction(mole_fraction):
		return _reject_operation("mole_fraction_not_a_fraction", {"room": room.id, "value": str(mole_fraction)})
	var initial_kg: float = o2_kg_from_mole_fraction(float(mole_fraction), room.volume_m3())
	_totals[room.id]["initial_kg"] = initial_kg
	_commit(room, initial_kg)
	_note({"kind": "initialize", "cause": "declared_initial_state", "room": room.id, "after_kg": initial_kg})
	_select_for_step()
	return {"applied": true, "reason": "", "inventory_kg": initial_kg}


## Releases every room and empties the transit. Called on every reset, also when
## the building is not ready: nothing of a run outlives it. Delivery ids are not
## reused, so an entry of an earlier run can never pass for one of this run.
func discard() -> void:
	for room in _rooms.values():
		if room != null:
			room.release_o2_inventory()
	_rooms.clear()
	_totals.clear()
	_transit.clear()
	_step_operations.clear()
	_selections.clear()
	_rejections.clear()
	_refused_after_rejection = 0
	_transit_dispatched_kg_total = 0.0
	_transit_arrived_kg_total = 0.0
	_step_index = 0
	_state = STATE_INACTIVE
	_generation = -1


## Opens a step. The environment is read again: a switch this mode does not
## cover that changes in the middle of a run refuses it, as it would at arming.
## Then the selections of the step are built, once, before any consumer runs.
func begin_step(environment: Dictionary) -> void:
	_step_index += 1
	_step_operations.clear()
	_selections.clear()
	if _state != STATE_ARMED:
		return
	var errors: Array[String] = _environment_errors(environment)
	if not errors.is_empty():
		_reject("environment_changed_after_arming", {"errors": errors})
		return
	_select_for_step()


# ------------------------------------------------------------------ selection

## One selection for every room, from what its inventory holds now. The only
## place where a selection is built.
func _select_for_step() -> void:
	_selections.clear()
	for room_id in _rooms.keys():
		var room = _rooms[room_id]
		var held_kg: float = room.o2_inventory_kg
		var owed_kg: float = 0.0
		for entry: Dictionary in _transit:
			if int(entry["receiver"]) == room_id:
				owed_kg -= minf(0.0, float(entry["net_kg"]))
		_selections[room_id] = {
			"id": _next_selection_id, "generation": _generation, "step": _step_index, "room": room_id,
			"deposit": DEPOSIT_ROOM_INVENTORY,
			"mole_fraction": mole_fraction_from_o2_kg(held_kg, room.volume_m3()),
			"inventory_kg": held_kg, "obligations_kg": owed_kg, "available_kg": maxf(0.0, held_kg - owed_kg),
			"served_to": [], "debited": false, "debited_kg": 0.0,
		}
		_next_selection_id += 1


## The selection of a room for the step that is open, the same one for every
## consumer. It is handed out, never rebuilt: a room with none is a refusal.
func selection_for(room, consumer: String) -> Dictionary:
	if not _open():
		_refused_after_rejection += 1
		return {"valid": false, "reason": "inventory_%s" % _state}
	if not _owns(room):
		_reject("room_not_under_authority", {"consumer": consumer})
		return {"valid": false, "reason": "room_not_under_authority"}
	var current: Variant = _selections.get(room.id)
	if current == null or int(current["step"]) != _step_index:
		_reject("no_selection_for_this_step", {"room": room.id, "consumer": consumer})
		return {"valid": false, "reason": "no_selection_for_this_step"}
	current["served_to"].append(consumer)
	var handed: Dictionary = current.duplicate(true)
	handed["valid"] = true
	return handed


## Why a debit cannot act on the selection it presents; empty when it can.
func _selection_error(room, selection: Variant) -> String:
	if typeof(selection) != TYPE_DICTIONARY or selection.get("valid") != true:
		return "debit_without_a_selection"
	if _whole(selection.get("generation")) != _generation:
		return "selection_of_another_run"
	if _whole(selection.get("room")) != room.id:
		return "selection_of_another_room"
	var current: Variant = _selections.get(room.id)
	if current == null:
		return "no_selection_for_this_step"
	if _whole(selection.get("step")) != _step_index or _whole(selection.get("id")) != int(current["id"]):
		return "selection_of_another_step"
	if str(selection.get("deposit")) != DEPOSIT_ROOM_INVENTORY or current["deposit"] != DEPOSIT_ROOM_INVENTORY:
		return "selection_of_another_deposit"
	if bool(current["debited"]):
		return "selection_already_debited"
	return ""


# ----------------------------------------------------------------- operations

## The debit of the fire sink, on the deposit of the selection it presents: the
## one of this room and this step, once. The sink decides how much it asks and
## how much its cap lets through; the owner applies what was let through and
## records what was not, so a cap never discards a quantity without a trace.
func consume(room, selection: Variant, requested_kg: Variant, applied_kg: Variant, cause: String) -> Dictionary:
	if not _open():
		return _refused()
	if not _owns(room):
		return _reject_operation("room_not_under_authority", {"cause": cause})
	var selection_error: String = _selection_error(room, selection)
	if selection_error != "":
		return _reject_operation(selection_error, {"cause": cause, "room": room.id})
	var current: Dictionary = _selections[room.id]
	if not _is_amount(requested_kg) or not _is_amount(applied_kg):
		return _reject_operation("quantity_not_a_finite_amount", {"cause": cause, "room": room.id})
	var requested: float = float(requested_kg)
	var applied: float = float(applied_kg)
	var before_kg: float = room.o2_inventory_kg
	if applied > requested:
		return _reject_operation("debit_larger_than_the_demand", {"cause": cause, "room": room.id,
			"requested_kg": requested, "applied_kg": applied})
	if applied > before_kg:
		return _reject_operation("debit_larger_than_the_inventory", {"cause": cause, "room": room.id,
			"applied_kg": applied, "inventory_kg": before_kg})
	var after_kg: float = before_kg - applied
	var totals: Dictionary = _totals[room.id]
	totals["consumption_requested_kg"] += requested
	totals["consumed_kg"] += applied
	totals["consumption_clipped_kg"] += requested - applied
	current["debited"] = true
	current["debited_kg"] = applied
	_commit(room, after_kg)
	_note({"kind": "consume", "cause": cause, "room": room.id, "requested_kg": requested,
		"applied_kg": applied, "clipped_kg": requested - applied, "before_kg": before_kg, "after_kg": after_kg,
		"selection_id": int(current["id"]), "deposit": String(current["deposit"]),
		"available_at_selection_kg": float(current["available_kg"])})
	return {"applied": true, "reason": "", "applied_kg": applied, "clipped_kg": requested - applied,
		"selection_id": int(current["id"])}


## `gas_kg` of reference gas exchanged with the outside: it enters at the
## outside mole fraction and leaves at `leaving_mole_fraction`, the one the law
## that moves the gas names.
func exchange_with_outside(
		room, gas_kg: Variant, outside_mole_fraction: Variant, leaving_mole_fraction: Variant, cause: String
	) -> Dictionary:
	if not _open():
		return _refused()
	if not _owns(room):
		return _reject_operation("room_not_under_authority", {"cause": cause})
	if not _is_amount(gas_kg):
		return _reject_operation("quantity_not_a_finite_amount", {"cause": cause, "room": room.id})
	if not _is_fraction(outside_mole_fraction) or not _is_fraction(leaving_mole_fraction):
		return _reject_operation("mole_fraction_not_a_fraction", {"cause": cause, "room": room.id})
	var in_kg: float = o2_kg_in_reference_gas(float(outside_mole_fraction), float(gas_kg))
	var out_kg: float = o2_kg_in_reference_gas(float(leaving_mole_fraction), float(gas_kg))
	var before_kg: float = room.o2_inventory_kg
	var after_kg: float = before_kg + in_kg - out_kg
	if after_kg < 0.0:
		return _reject_operation("exchange_leaves_a_negative_inventory", {"cause": cause, "room": room.id,
			"in_kg": in_kg, "out_kg": out_kg, "inventory_kg": before_kg})
	var totals: Dictionary = _totals[room.id]
	totals["outside_in_kg"] += in_kg
	totals["outside_out_kg"] += out_kg
	_commit(room, after_kg)
	_note({"kind": "outside", "cause": cause, "room": room.id, "gas_kg": float(gas_kg), "in_kg": in_kg,
		"out_kg": out_kg, "before_kg": before_kg, "after_kg": after_kg})
	return {"applied": true, "reason": "", "in_kg": in_kg, "out_kg": out_kg, "net_kg": in_kg - out_kg}


## Why `gas_kg` of outside gas cannot be mixed into `room`; empty when it can.
## Reads only: nothing is recorded and nothing is refused here.
func _dilution_error(room, gas_kg: Variant, outside_mole_fraction: Variant) -> String:
	if not _owns(room):
		return "room_not_under_authority"
	if not _is_amount(gas_kg):
		return "quantity_not_a_finite_amount"
	if not _is_fraction(outside_mole_fraction):
		return "mole_fraction_not_a_fraction"
	return ""


## Whether `dilute_with_outside` would apply now. A law that writes other state
## with the same event asks this BEFORE writing any of it.
func outside_dilution_would_apply(room, gas_kg: Variant, outside_mole_fraction: Variant) -> bool:
	return _open() and _dilution_error(room, gas_kg, outside_mole_fraction) == ""


## `gas_kg` of reference gas enter at the outside mole fraction, mix with the
## whole reference content of the room, and `gas_kg` of that mixture leave: the
## room keeps its reference content. What leaves is a share of what is there
## after mixing, so no inventory can go below zero and nothing is clipped.
func dilute_with_outside(room, gas_kg: Variant, outside_mole_fraction: Variant, cause: String) -> Dictionary:
	if not _open():
		return _refused()
	var error: String = _dilution_error(room, gas_kg, outside_mole_fraction)
	if error != "":
		return _reject_operation(error, {"cause": cause, "room": room.id if room != null else -1})
	var entering_kg: float = float(gas_kg)
	var before_kg: float = room.o2_inventory_kg
	var in_kg: float = o2_kg_in_reference_gas(float(outside_mole_fraction), entering_kg)
	var mixture_mole_fraction: float = (before_kg + in_kg) / o2_kg_in_reference_gas(
		1.0, reference_gas_kg(room.volume_m3()) + entering_kg
	)
	var out_kg: float = o2_kg_in_reference_gas(mixture_mole_fraction, entering_kg)
	var after_kg: float = before_kg + in_kg - out_kg
	var totals: Dictionary = _totals[room.id]
	totals["outside_in_kg"] += in_kg
	totals["outside_out_kg"] += out_kg
	totals["dilution_events"] += 1
	totals["dilution_gas_kg"] += entering_kg
	totals["dilution_in_kg"] += in_kg
	totals["dilution_out_kg"] += out_kg
	_commit(room, after_kg)
	_note({"kind": "outside", "cause": cause, "law": "dilution", "room": room.id, "gas_kg": entering_kg, "in_kg": in_kg,
		"out_kg": out_kg, "leaving_mole_fraction": mixture_mole_fraction, "before_kg": before_kg, "after_kg": after_kg})
	return {"applied": true, "reason": "", "in_kg": in_kg, "out_kg": out_kg, "net_kg": in_kg - out_kg,
		"leaving_mole_fraction": mixture_mole_fraction}


## Two parcels that cross a doorway. `donor_out_kg` leaves the donor for the
## receiver and `receiver_out_kg` leaves the receiver for the donor.
##
## With no delay both rooms change at once. With a delay the donor changes at
## once by the net of the two, and the same net with the opposite sign becomes
## ONE entry in transit for the receiver. Nothing is written unless both ends
## validate.
func exchange_between_rooms(
		donor, receiver, donor_out_kg: Variant, receiver_out_kg: Variant, delay_s: Variant, cause: String
	) -> Dictionary:
	if not _open():
		return _refused()
	if not _owns(donor) or not _owns(receiver) or donor == receiver:
		return _reject_operation("room_not_under_authority", {"cause": cause})
	if not _is_amount(donor_out_kg) or not _is_amount(receiver_out_kg) or not _is_amount(delay_s):
		return _reject_operation("quantity_not_a_finite_amount", {"cause": cause,
			"donor": donor.id, "receiver": receiver.id})
	var to_receiver_kg: float = float(donor_out_kg)
	var to_donor_kg: float = float(receiver_out_kg)
	var delayed: bool = float(delay_s) > DELIVERY_DUE_S
	var donor_before_kg: float = donor.o2_inventory_kg
	var receiver_before_kg: float = receiver.o2_inventory_kg
	var donor_after_kg: float = donor_before_kg + to_donor_kg - to_receiver_kg
	var receiver_net_kg: float = to_receiver_kg - to_donor_kg
	var receiver_after_kg: float = receiver_before_kg + receiver_net_kg
	if donor_after_kg < 0.0 or (not delayed and receiver_after_kg < 0.0):
		return _reject_operation("exchange_leaves_a_negative_inventory", {"cause": cause,
			"donor": donor.id, "receiver": receiver.id, "donor_after_kg": donor_after_kg,
			"receiver_after_kg": receiver_after_kg})
	var donor_totals: Dictionary = _totals[donor.id]
	donor_totals["interior_in_kg"] += to_donor_kg
	donor_totals["interior_out_kg"] += to_receiver_kg
	_commit(donor, donor_after_kg)
	var operation: Dictionary = {"kind": "interior", "cause": cause, "donor": donor.id, "receiver": receiver.id,
		"to_receiver_kg": to_receiver_kg, "to_donor_kg": to_donor_kg, "donor_before_kg": donor_before_kg,
		"donor_after_kg": donor_after_kg, "delayed": delayed}
	var delivery_id: int = -1
	if delayed:
		delivery_id = _next_delivery_id
		_next_delivery_id += 1
		_transit.append({
			"id": delivery_id, "generation": _generation, "state": ENTRY_IN_TRANSIT, "cause": cause,
			"donor": donor.id, "receiver": receiver.id, "delay_s": float(delay_s),
			"to_receiver_kg": to_receiver_kg, "advanced_to_donor_kg": to_donor_kg, "net_kg": receiver_net_kg,
			"dispatched_at_step": _step_index,
		})
		_transit_dispatched_kg_total += receiver_net_kg
		operation["delivery_id"] = delivery_id
		operation["in_transit_net_kg"] = receiver_net_kg
	else:
		var receiver_totals: Dictionary = _totals[receiver.id]
		receiver_totals["interior_in_kg"] += to_receiver_kg
		receiver_totals["interior_out_kg"] += to_donor_kg
		_commit(receiver, receiver_after_kg)
		operation["receiver_before_kg"] = receiver_before_kg
		operation["receiver_after_kg"] = receiver_after_kg
	_note(operation)
	return {"applied": true, "reason": "", "delayed": delayed, "delivery_id": delivery_id,
		"donor_net_kg": to_donor_kg - to_receiver_kg, "receiver_net_kg": receiver_net_kg}


## Advances the clock of every entry in transit and delivers the ones that are
## due. Returns what arrived, receiver by receiver, for the audit accumulators.
func advance_transit(dt: Variant) -> Array:
	var arrived: Array = []
	if not _open():
		_refused()
		return arrived
	if not _is_amount(dt):
		_reject_operation("quantity_not_a_finite_amount", {"cause": "transit_arrival"})
		return arrived
	var remaining: Array[Dictionary] = []
	for entry: Dictionary in _transit:
		if _state != STATE_ARMED:
			remaining.append(entry)
			continue
		entry["delay_s"] = maxf(0.0, float(entry["delay_s"]) - float(dt))
		if float(entry["delay_s"]) > DELIVERY_DUE_S:
			remaining.append(entry)
			continue
		var delivered: Dictionary = _deliver(entry)
		if bool(delivered["applied"]):
			arrived.append({"receiver": int(entry["receiver"]), "net_kg": float(entry["net_kg"]), "id": int(entry["id"])})
		else:
			remaining.append(entry)
	_transit = remaining
	return arrived


## One arrival: the entry leaves `T` and its net enters `M` of the receiver, the
## same quantity. An entry of another run, or one already delivered, is refused.
func _deliver(entry: Dictionary) -> Dictionary:
	if not _open():
		return _refused()
	if int(entry.get("generation", -2)) != _generation:
		return _reject_operation("delivery_of_another_run", {"id": entry.get("id"), "generation": entry.get("generation")})
	if String(entry.get("state", "")) != ENTRY_IN_TRANSIT:
		return _reject_operation("delivery_applied_twice", {"id": entry.get("id")})
	var receiver = _rooms.get(int(entry.get("receiver", -1)))
	if receiver == null:
		return _reject_operation("delivery_without_a_receiver", {"id": entry.get("id")})
	var net_kg: float = float(entry["net_kg"])
	var before_kg: float = receiver.o2_inventory_kg
	var after_kg: float = before_kg + net_kg
	if after_kg < 0.0:
		return _reject_operation("arrival_leaves_a_negative_inventory", {"id": entry.get("id"),
			"receiver": receiver.id, "net_kg": net_kg, "inventory_kg": before_kg})
	entry["state"] = ENTRY_DELIVERED
	_totals[receiver.id]["transit_arrived_kg"] += net_kg
	_transit_arrived_kg_total += net_kg
	_commit(receiver, after_kg)
	_note({"kind": "arrival", "cause": "transit_arrival", "room": receiver.id, "delivery_id": int(entry["id"]),
		"net_kg": net_kg, "before_kg": before_kg, "after_kg": after_kg})
	return {"applied": true, "reason": "", "net_kg": net_kg}


# -------------------------------------------------------------------- refusal

## A route this stage does not own. With nothing to move it is not a rejection;
## with a quantity it refuses the run and writes nothing.
func refuse_route(room, route: String, quantity: Variant, detail: Dictionary = {}) -> bool:
	if _state == STATE_INACTIVE:
		return false
	if _is_number(quantity) and float(quantity) == 0.0:
		return false
	if _state == STATE_REJECTED:
		_refused_after_rejection += 1
		return true
	var record: Dictionary = detail.duplicate(true)
	record["route"] = route
	record["room"] = room.id if room != null else -1
	record["quantity"] = str(quantity)
	_reject("route_not_supported_in_m1", record)
	return true


## A write of the room number that did not come from here was refused by the
## room and is counted there. One of them refuses the run.
func audit_room_numbers() -> void:
	if _state != STATE_ARMED:
		return
	for room in _rooms.values():
		if room.o2_unauthorized_write_count > 0:
			_reject("room_number_written_outside_the_owner", {"room": room.id,
				"writes": room.o2_unauthorized_write_count, "last_value": str(room.o2_unauthorized_write_last)})
			return
		var expected: float = mole_fraction_from_o2_kg(room.o2_inventory_kg, room.volume_m3())
		if room.o2 != expected:
			_reject("room_number_is_not_the_one_derived", {"room": room.id, "number": room.o2, "derived": expected})
			return


# ---------------------------------------------------------------------- reads

func state() -> String:
	return _state


func generation() -> int:
	return _generation


func owns_room(room) -> bool:
	return _owns(room)


func inventory_kg(room) -> float:
	return room.o2_inventory_kg if _owns(room) else NAN


func in_transit_kg(receiver_id: Variant = null) -> float:
	var total_kg: float = 0.0
	for entry: Dictionary in _transit:
		if receiver_id == null or int(entry["receiver"]) == int(receiver_id):
			total_kg += float(entry["net_kg"])
	return total_kg


## Mole fraction a doorway law reads from a room: its inventory with what is
## already on its way to it. Never below zero; no ceiling.
func effective_mole_fraction(room) -> float:
	if not _owns(room):
		return NAN
	return mole_fraction_from_o2_kg(maxf(0.0, room.o2_inventory_kg + in_transit_kg(room.id)), room.volume_m3())


## What the room will hold once the negative arrivals due within `dt` have been
## taken from it. Read by the mass bound of the fire sink.
func inventory_after_due_debits_kg(room, dt: float) -> float:
	if not _owns(room):
		return NAN
	var due_kg: float = 0.0
	for entry: Dictionary in _transit:
		if int(entry["receiver"]) == room.id and maxf(0.0, float(entry["delay_s"]) - dt) <= DELIVERY_DUE_S:
			due_kg += minf(0.0, float(entry["net_kg"]))
	return maxf(0.0, room.o2_inventory_kg + due_kg)


func report() -> Dictionary:
	var rooms: Dictionary = {}
	for room_id in _rooms.keys():
		var room = _rooms[room_id]
		var entry: Dictionary = _totals[room_id].duplicate(true)
		entry["inventory_kg"] = room.o2_inventory_kg
		entry["mole_fraction"] = room.o2
		entry["reference_gas_kg"] = reference_gas_kg(room.volume_m3())
		entry["reference_mol"] = reference_mol(room.volume_m3())
		entry["in_transit_to_it_kg"] = in_transit_kg(room_id)
		entry["writes_refused_by_the_room"] = room.o2_unauthorized_write_count
		rooms[room_id] = entry
	return {
		"schema": REPORT_SCHEMA, "version": VERSION, "scope": SCOPE, "state": _state,
		"generation": _generation, "step": _step_index,
		"units": {"inventory": "kg of O2", "transit": "kg of O2, signed net", "room_number": "mole fraction of the reference mixture"},
		"constants": {"m_o2_kg_per_mol": M_O2_KG_PER_MOL, "m_dry_air_kg_per_mol": M_DRY_AIR_KG_PER_MOL,
			"reference_gas_density_kg_m3": REFERENCE_GAS_DENSITY_KG_M3},
		"approximations": APPROXIMATIONS, "supported_routes": SUPPORTED_ROUTES,
		"rooms": rooms, "transit": _transit.duplicate(true), "in_transit_kg": in_transit_kg(),
		"transit_owner": "the inventory owner: one queue, neither the donor nor the receiver",
		"transit_dispatched_kg_total": _transit_dispatched_kg_total,
		"transit_arrived_kg_total": _transit_arrived_kg_total,
		"step_operations": _step_operations.duplicate(true),
		"selections": _selections.duplicate(true),
		"rejections": _rejections.duplicate(true), "refused_after_rejection": _refused_after_rejection,
	}


# ------------------------------------------------------------------- internals

func _commit(room, inventory_kg_value: float) -> void:
	room.commit_o2_inventory(inventory_kg_value, mole_fraction_from_o2_kg(inventory_kg_value, room.volume_m3()))


func _note(operation: Dictionary) -> void:
	operation["step"] = _step_index
	_step_operations.append(operation)


func _open() -> bool:
	return _state == STATE_ARMED


func _owns(room) -> bool:
	return room != null and _rooms.get(room.id) == room and room.o2_inventory_authority


func _refused() -> Dictionary:
	_refused_after_rejection += 1
	return {"applied": false, "reason": "inventory_%s" % _state}


func _reject_operation(reason: String, detail: Dictionary) -> Dictionary:
	_reject(reason, detail)
	return {"applied": false, "reason": reason}


func _reject(reason: String, detail: Dictionary) -> void:
	var record: Dictionary = detail.duplicate(true)
	record["reason"] = reason
	record["step"] = _step_index
	_rejections.append(record)
	_state = STATE_REJECTED


func _environment_errors(environment: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in REQUIRED_ENVIRONMENT.keys():
		if not environment.has(key):
			errors.append("environment_missing:%s" % key)
		elif typeof(environment[key]) != typeof(REQUIRED_ENVIRONMENT[key]) \
				or environment[key] != REQUIRED_ENVIRONMENT[key]:
			errors.append("environment_not_supported:%s=%s" % [key, str(environment[key])])
	return errors


func _empty_totals() -> Dictionary:
	return {
		"initial_kg": 0.0, "consumption_requested_kg": 0.0, "consumed_kg": 0.0, "consumption_clipped_kg": 0.0,
		"outside_in_kg": 0.0, "outside_out_kg": 0.0, "interior_in_kg": 0.0, "interior_out_kg": 0.0,
		"transit_arrived_kg": 0.0,
		# Of the exchange with the outside above, the part that is a dilution (M2-V).
		"dilution_events": 0, "dilution_gas_kg": 0.0, "dilution_in_kg": 0.0, "dilution_out_kg": 0.0,
	}


## An identifier read from a selection somebody hands in: a whole number, or -2.
static func _whole(value: Variant) -> int:
	return int(value) if typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(float(value))) else -2


static func _is_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))


## A quantity of oxygen or gas, or a delay: finite and never negative. Zero is a
## quantity; an unknown value is not zero.
static func _is_amount(value: Variant) -> bool:
	return _is_number(value) and float(value) >= 0.0


static func _is_positive(value: Variant) -> bool:
	return _is_number(value) and float(value) > 0.0


static func _is_fraction(value: Variant) -> bool:
	return _is_number(value) and float(value) >= 0.0 and float(value) <= 1.0
