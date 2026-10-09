extends RefCounted

## DIAGNOSTIC BENCH. Couples ONE isolated prescribed HRR source to ONE room as a
## thermal source: energy to the room and an equivalent oxygen debit. Nothing else.
##
## It is not the combustion of the furniture. It consumes no fuel, produces no
## species and validates no temperature. The room has no FireModel and no fuel,
## so the room-fire route owns nothing here; this owner writes the room power
## after that route has run and the engine sink and ThermalSystem read it.
##
## The energy of a step is the integral the isolated source proposes; this
## module never interpolates the table. The power of a step is that energy over
## the WHOLE step, so no filter, cap, split or fire clock stands in between.
##
## Inside the declared regime the whole interval is accepted. At the first step
## in which a rule fails nothing is accepted, the state latches as
## `outside_declared_regime` until a reset, and every later interval is
## confirmed with zero: no queue, no unburned inventory, no hand-over to the
## room fire. The oxygen tolerance and the layer criterion are hypotheses of the
## bench, not validated limits of the object.
##
## No class_name and no @export: only SimulationEngine loads it, behind a
## switch that is not exported, off by default and reachable from fixtures only.

const SourceScript = preload("res://sim/fire/PrescribedObjectHrrSource.gd")

const VERSION: String = "prescribed_thermal_source_coupling_v1"
const CASE_SCHEMA: String = "g3_prescribed_thermal_source_case_v1"
const REPORT_SCHEMA: String = "g3_prescribed_thermal_source_report_v1"
const SCOPE: String = "diagnostic_coupling_bench_energy_and_equivalent_oxygen_not_the_combustion_of_the_object"

const STATE_INACTIVE: String = "inactive"
const STATE_FAILED: String = "failed"
const STATE_ARMED: String = "armed"
const STATE_REPLAYING: String = "replaying"
const STATE_OUTSIDE: String = "outside_declared_regime"
const STATE_COMPLETED: String = "completed"

const REGIME_LABEL: String = "PRESCRIBED_THERMAL_SOURCE"
const IDLE_LABEL: String = "EXTINGUISHED"

const CASE_KEYS: Array[String] = [
	"schema", "room_id", "source", "expected_source_fingerprint", "oxygen_kg_per_MJ",
	"radiative_fraction", "regime",
]
const RADIATIVE_KEYS: Array[String] = ["value", "class", "what"]
const RADIATIVE_CLASSES: Array[String] = ["assumed", "open_air_whole_test_estimate", "sensitivity"]
const REGIME_KEYS: Array[String] = ["oxygen_drop_tolerance", "layer_interface_min_m", "status"]
const REGIME_STATUS: String = "declared_hypothesis_not_a_validated_limit"

## What the engine must be for the declared routes to be the ones that run. Read
## by the engine from its own subsystems; any difference refuses the run.
const REQUIRED_ENVIRONMENT: Dictionary = {
	"oxygen_step_runs_after_the_fire": true,
	"fire_oxygen_mode": "legacy",
	"sink_takes_oxygen_from_the_lower_number": false,
	"phase2b_canonical_combustion_enabled": false,
	"fire_o2_canonical_enabled": false,
	"fire_o2_mass_tracking_enabled": false,
	"authoritative_transport_enabled": false,
	"canonical_zone_shadow_enabled": false,
	"energy_budget_enabled": true,
	"two_zone_convective_heat_multiplier": 1.0,
	"outside_open_upper_heat_boost": 0.0,
	"auto_finish_on_extinction": false,
}
const CALLABLES: Array[String] = [
	"oxygen_floor_MJ", "layer_interface_m", "energy_budget", "suppression_active",
]
const NOT_EVALUATED: Array[String] = [
	"co", "co2", "hcn", "smoke_and_visibility", "irritants", "fed", "svv",
	"fuel_mass", "gas_composition", "temperatures_as_validated_values",
]
const OXYGEN_REL_TOL: float = 1.0e-12
const OXYGEN_ABS_TOL_KG: float = 1.0e-15
const FRACTION_TOL: float = 1.0e-12

var _state: String = STATE_INACTIVE
var _failure: Array[String] = []
var _case: Dictionary = {}
var _room = null
var _hooks: Dictionary = {}
var _environment: Dictionary = {}
var _source: RefCounted = null
var _fingerprint: String = ""
var _support_end_s: float = 0.0
var _ignition_time_s: float = -1.0
var _oxygen_at_ignition: Dictionary = {}
var _exit: Dictionary = {}
var _pending: Dictionary = {}
var _last_step: Dictionary = {}
var _totals: Dictionary = {}
var _steps: int = 0
var _owned_room_fields: Dictionary = {}


# ---------------------------------------------------------------- life cycle

## Validates the case, the room and the engine, and opens a NEW source. On any
## refusal nothing is kept and the state is `failed`: the engine must not step.
func arm(room, environment: Variant, hooks: Variant, case: Variant) -> Dictionary:
	if _state != STATE_INACTIVE:
		# Refused without touching what is already there.
		return {"valid": false, "errors": ["this coupling was already armed; a run takes a new one"]}
	var errors: Array[String] = []
	if room == null:
		errors.append("the room of the case does not exist")
	if typeof(environment) != TYPE_DICTIONARY:
		errors.append("the engine did not describe itself")
	if typeof(hooks) != TYPE_DICTIONARY:
		errors.append("the engine gave no hooks")
	if typeof(case) != TYPE_DICTIONARY:
		errors.append("the case must be a record")
	if not errors.is_empty():
		return _refuse_arm(errors)
	var c: Dictionary = case
	if not _exact_keys(c, CASE_KEYS):
		return _refuse_arm(["case fields must be exactly %s" % str(CASE_KEYS)])
	if not _same_text(c["schema"], CASE_SCHEMA):
		errors.append("case schema must be %s" % CASE_SCHEMA)
	if typeof(c["room_id"]) != TYPE_INT or int(c["room_id"]) != int(room.id):
		errors.append("room_id must be the id of the room that was handed over")
	if typeof(c["expected_source_fingerprint"]) != TYPE_STRING:
		errors.append("expected_source_fingerprint must be text")
	if not _number(c["oxygen_kg_per_MJ"]) or float(c["oxygen_kg_per_MJ"]) <= 0.0:
		errors.append("oxygen_kg_per_MJ must be a positive finite number")
	errors.append_array(_radiative_errors(c["radiative_fraction"]))
	errors.append_array(_regime_errors(c["regime"]))
	errors.append_array(_environment_errors(environment))
	for name: String in CALLABLES:
		if typeof(hooks.get(name)) != TYPE_CALLABLE or not hooks[name].is_valid():
			errors.append("missing hook %s" % name)
	errors.append_array(_room_errors(room))
	if not errors.is_empty():
		return _refuse_arm(errors)
	var source: RefCounted = SourceScript.new()
	var opened: Dictionary = source.open(c["source"])
	if typeof(opened.get("valid")) != TYPE_BOOL or not opened["valid"]:
		var reasons: Array[String] = ["the source was refused"]
		for reason: Variant in opened.get("errors", []):
			reasons.append(str(reason))
		return _refuse_arm(reasons)
	var described: Dictionary = source.report()
	if described.get("source_fingerprint") != c["expected_source_fingerprint"]:
		return _refuse_arm(["the source is not the one the case names"])
	_source = source
	_fingerprint = String(described["source_fingerprint"])
	_support_end_s = float(described["support_s"][1])
	_case = c.duplicate(true)
	_case.erase("source")  # the owner keeps its own validated copy
	_room = room
	_hooks = hooks.duplicate()
	_environment = environment.duplicate(true)
	_totals = _zero_totals()
	_state = STATE_ARMED
	return {"valid": true, "errors": []}


## Starts the clock of the source. The clock of the source is its own and only
## confirmations move it; `fire_time_s` of the room is never read.
func ignite(sim_time_s: float) -> bool:
	if _state != STATE_ARMED:
		return false
	_ignition_time_s = sim_time_s
	_oxygen_at_ignition = {"room": float(_room.o2), "lower": float(_room.o2_lower), "upper": float(_room.o2_upper)}
	_state = STATE_REPLAYING
	return true


## Retires what this owner put in the room and forgets the source. Safe to call
## in any state, with or without a room that still exists.
func discard() -> void:
	if _room != null and is_instance_valid(_room):
		if _owned_room_fields.has("hrr_kw") and _room.hrr_kw == _owned_room_fields["hrr_kw"]:
			_room.hrr_kw = 0.0
			_room.burned_hrr_kw = 0.0
		if _owned_room_fields.has("chi_rad_normal") \
				and _room.chi_rad_normal == _owned_room_fields["chi_rad_normal"]["applied"]:
			_room.chi_rad_normal = _owned_room_fields["chi_rad_normal"]["previous"]
		if _owned_room_fields.has("combustion_regime") and _room.combustion_regime == REGIME_LABEL:
			_room.combustion_regime = IDLE_LABEL
	_owned_room_fields = {}
	_room = null
	_hooks = {}
	_source = null
	_pending = {}
	_last_step = {}
	_state = STATE_INACTIVE


# ---------------------------------------------------------------- one engine step

## After the room-fire route and before the oxygen sink. Proposes the interval,
## judges the regime and, only if everything holds, writes the power of the step.
func begin_step(dt: float) -> void:
	_pending = {}
	_last_step = {}
	if _state != STATE_REPLAYING and _state != STATE_OUTSIDE:
		return
	if not (dt > 0.0) or is_nan(dt) or is_inf(dt):
		_fail(["the step must last"])
		return
	var clock: float = _clock()
	if clock >= _support_end_s:
		if _state == STATE_REPLAYING:
			_state = STATE_COMPLETED
		return
	# Only the part of the step inside the support is proposed.
	var end_time_s: float = minf(clock + dt, _support_end_s)
	var offer: Dictionary = _source.propose(end_time_s)
	if not _positive(offer) or typeof(offer.get("proposal")) != TYPE_DICTIONARY:
		_fail(["the source refused an interval inside its support: %s" % str(offer.get("errors"))])
		return
	var proposal: Dictionary = offer["proposal"]
	var energy_kj: float = float(proposal["energy_kj"])
	_steps += 1
	_last_step = {
		"index": _steps - 1, "start_s": float(proposal["start_time_s"]), "end_s": float(proposal["end_time_s"]),
		"step_s": dt, "scheduled_kj": energy_kj, "accepted_kj": 0.0, "rejected_kj": 0.0, "power_kw": 0.0,
		"oxygen_committed_kg": 0.0, "oxygen_debited_kg": 0.0, "oxygen_zone_displacement_kg": 0.0,
		"to_the_gas_kj": 0.0, "radiative_term_kj": 0.0, "radiative_fraction_applied": null,
		"state_before": _state,
	}
	if _state == STATE_REPLAYING:
		var cause: Dictionary = _regime_failure(energy_kj, dt)
		if not cause.is_empty():
			_leave_regime(cause)
	if _state == STATE_OUTSIDE:
		_settle(proposal, 0.0)
		return
	# Inside the regime: the whole interval, over the WHOLE step.
	var committed_kg: float = energy_kj / 1000.0 * float(_case["oxygen_kg_per_MJ"])
	_pending = {"proposal": proposal, "energy_kj": energy_kj, "step_s": dt, "oxygen_committed_kg": committed_kg}
	_last_step["oxygen_committed_kg"] = committed_kg
	_write_room_power(energy_kj / dt)


## After the oxygen sink and BEFORE the heat. The debit that really happened is
## compared with the committed one; if it differs the power of the step is
## withdrawn before ThermalSystem reads it, so no heat is counted as valid.
func settle_oxygen() -> void:
	if _pending.is_empty() or _state != STATE_REPLAYING:
		return
	var committed_kg: float = float(_pending["oxygen_committed_kg"])
	var primary_kg: float = float(_room.o2_consumed_fire_kg_step)
	var room_inventory_kg: float = float(_room.o2_consumed_bulk_kg_step)
	var all_kg: float = float(_room.o2_consumed_kg_step_all)
	_last_step["oxygen_debited_kg"] = room_inventory_kg
	_last_step["oxygen_zone_displacement_kg"] = all_kg - primary_kg
	var tolerance: float = OXYGEN_ABS_TOL_KG + OXYGEN_REL_TOL * maxf(absf(committed_kg), absf(room_inventory_kg))
	if absf(room_inventory_kg - committed_kg) > tolerance or absf(primary_kg - room_inventory_kg) > tolerance:
		# The sink took something else, or from another inventory. It cannot be
		# given back: the engine does not restore. It is reported.
		_totals["oxygen_debited_without_heat_kg"] += all_kg
		_withdraw_room_power()
		_leave_regime({
			"cause": "oxygen_debit_is_not_the_committed_one",
			"committed_kg": committed_kg, "room_inventory_debit_kg": room_inventory_kg,
			"primary_sink_debit_kg": primary_kg, "all_sinks_debit_kg": all_kg,
		})
		_settle(_pending["proposal"], 0.0)
		_pending = {}
		return
	_totals["oxygen_debited_kg"] += room_inventory_kg
	_totals["oxygen_zone_displacement_kg"] += all_kg - primary_kg
	_settle(_pending["proposal"], float(_pending["energy_kj"]))


## After ThermalSystem. Reads what it really deposited and what it counted as
## radiated. A difference here cannot be undone: the run fails and stops.
func settle_heat() -> void:
	if _state == STATE_FAILED or _room == null or _pending.is_empty():
		return
	var accepted_kj: float = float(_pending["energy_kj"])
	_pending = {}
	var budget: Variant = _hooks["energy_budget"].call()
	var row: Variant = budget.get(_room.id) if typeof(budget) == TYPE_DICTIONARY else null
	if typeof(row) != TYPE_DICTIONARY or not row.has("e_fire_kj") or not row.has("q_fire_rad_kj") or not row.has("chi_rad"):
		_fail(["ThermalSystem did not report the heat of the step"])
		return
	var to_gas_kj: float = float(row["e_fire_kj"])
	var radiative_kj: float = float(row["q_fire_rad_kj"])
	var applied: float = float(row["chi_rad"])
	_last_step["to_the_gas_kj"] = to_gas_kj
	_last_step["radiative_term_kj"] = radiative_kj
	_last_step["radiative_fraction_applied"] = applied
	_totals["to_the_gas_kj"] += to_gas_kj
	_totals["radiative_term_kj"] += radiative_kj
	var declared: float = float(_case["radiative_fraction"]["value"])
	var errors: Array[String] = []
	if absf(applied - declared) > FRACTION_TOL:
		errors.append("ThermalSystem applied a radiative fraction of %s, the case declares %s" % [applied, declared])
	if not _near_energy(to_gas_kj + radiative_kj, accepted_kj):
		errors.append("heat to the gas plus the radiative term is %s kJ, accepted %s kJ" % [to_gas_kj + radiative_kj, accepted_kj])
	if not errors.is_empty():
		_fail(errors)


# ---------------------------------------------------------------- what it says

func state() -> String:
	return _state


func failure() -> Array[String]:
	return _failure.duplicate()


func last_step() -> Dictionary:
	return _last_step.duplicate(true)


## Read from the live instance every time; nothing is cached for a later run.
func report() -> Dictionary:
	var out: Dictionary = {
		"schema": REPORT_SCHEMA, "version": VERSION, "scope": SCOPE, "state": _state,
		"failure": _failure.duplicate(),
		"is_a_reproduction_of_the_input": _state == STATE_COMPLETED,
		"combustion_of_the_object": false, "fuel_consumed": false, "species_produced": false,
		"temperatures_validated": false, "product_activation": false,
		"not_evaluated": NOT_EVALUATED.duplicate(),
		"not_evaluated_means": "not computed for this room; the zeros kept inside the engine are neither measured zeros nor a safe condition",
		"gas_state": "diagnostic and incomplete: oxygen is debited and no combustion products or fuel mass are added",
		"radiative_term_is": "energy counted as radiated by ThermalSystem; where it lands is not modelled by this bench",
		"regime_criteria_are": REGIME_STATUS,
	}
	if _state == STATE_INACTIVE or (_state == STATE_FAILED and _source == null):
		return out
	out["room_id"] = int(_case["room_id"])
	out["source_fingerprint"] = _fingerprint
	out["oxygen_kg_per_MJ"] = float(_case["oxygen_kg_per_MJ"])
	out["oxygen_is"] = "equivalent demand prescribed by the bench, debited from the room inventory of the engine sink; not a validated stoichiometry and not the oxygen measured in the test"
	out["radiative_fraction"] = _case["radiative_fraction"].duplicate(true)
	out["regime"] = _case["regime"].duplicate(true)
	out["ignition_time_s"] = _ignition_time_s
	out["oxygen_at_ignition"] = _oxygen_at_ignition.duplicate()
	out["steps"] = _steps
	out["exit"] = _exit.duplicate(true)
	out["totals"] = _totals.duplicate()
	out["source_state"] = _source.snapshot() if _source != null else {}
	return out


# ---------------------------------------------------------------- private

func _clock() -> float:
	return float(_source.snapshot()["time_s"])


## The declared regime, judged with the state at the start of the step. Returns
## the cause of the exit, or nothing.
func _regime_failure(energy_kj: float, dt: float) -> Dictionary:
	# R4: one owner, no fuel, no water.
	if _room.fire != null:
		return {"cause": "the_room_has_a_room_fire"}
	if not _room_errors(_room).is_empty():
		return {"cause": "the_room_has_fuel"}
	if bool(_hooks["suppression_active"].call(int(_room.id))):
		return {"cause": "suppression_in_the_room"}
	# R2: the oxygen of the room and of the lower layer near their value at the ignition.
	var tolerance: float = float(_case["regime"]["oxygen_drop_tolerance"])
	var room_drop: float = float(_oxygen_at_ignition["room"]) - float(_room.o2)
	var lower_drop: float = float(_oxygen_at_ignition["lower"]) - float(_room.o2_lower)
	if room_drop > tolerance or lower_drop > tolerance:
		return {"cause": "oxygen_below_the_declared_tolerance", "room_drop": room_drop,
			"lower_layer_drop": lower_drop, "tolerance": tolerance}
	# R3: the hot layer must not wrap the source.
	var interface_m: float = float(_hooks["layer_interface_m"].call(_room))
	if interface_m < float(_case["regime"]["layer_interface_min_m"]):
		return {"cause": "hot_layer_below_the_declared_height", "interface_m": interface_m,
			"minimum_m": float(_case["regime"]["layer_interface_min_m"])}
	# R1: the sink must be able to debit the whole equivalent demand of the step.
	var floor_MJ: float = float(_hooks["oxygen_floor_MJ"].call(_room, dt, float(_case["oxygen_kg_per_MJ"])))
	if energy_kj / 1000.0 > floor_MJ:
		return {"cause": "the_oxygen_sink_cannot_debit_the_step", "scheduled_MJ": energy_kj / 1000.0,
			"sink_bound_MJ": floor_MJ}
	return {}


func _leave_regime(cause: Dictionary) -> void:
	_state = STATE_OUTSIDE
	if _exit.is_empty():
		_exit = cause.duplicate(true)
		_exit["source_time_s"] = _clock()
		_exit["step"] = _steps - 1


## Confirms the interval once, with everything or with nothing.
func _settle(proposal: Dictionary, accepted_kj: float) -> void:
	var done: Dictionary = _source.confirm(proposal, accepted_kj)
	if not _positive(done):
		_withdraw_room_power()
		_fail(["the source refused the confirmation: %s" % str(done.get("errors"))])
		return
	_last_step["accepted_kj"] = float(done["accepted_this_step_kj"])
	_last_step["rejected_kj"] = float(done["rejected_this_step_kj"])
	_last_step["state_after"] = _state
	_totals["scheduled_kj"] += float(done["scheduled_this_step_kj"])
	_totals["accepted_kj"] += float(done["accepted_this_step_kj"])
	_totals["rejected_kj"] += float(done["rejected_this_step_kj"])
	if _state == STATE_REPLAYING and _clock() >= _support_end_s:
		_state = STATE_COMPLETED
		_last_step["state_after"] = _state


func _write_room_power(power_kw: float) -> void:
	var declared: float = float(_case["radiative_fraction"]["value"])
	if not _owned_room_fields.has("chi_rad_normal"):
		_owned_room_fields["chi_rad_normal"] = {"previous": float(_room.chi_rad_normal), "applied": declared}
	_room.chi_rad_normal = declared
	_room.hrr_kw = power_kw
	_room.burned_hrr_kw = power_kw
	_room.combustion_regime = REGIME_LABEL
	_owned_room_fields["hrr_kw"] = power_kw
	_owned_room_fields["combustion_regime"] = true
	_last_step["power_kw"] = power_kw


func _withdraw_room_power() -> void:
	_room.hrr_kw = 0.0
	_room.burned_hrr_kw = 0.0
	_owned_room_fields["hrr_kw"] = 0.0
	_last_step["power_kw"] = 0.0


## At the end of the physics of the step, once every system has run. Measured,
## not assumed: what the room-fire route did in this room.
func end_step() -> void:
	if _state == STATE_FAILED or _state == STATE_INACTIVE or _room == null:
		return
	_totals["room_fire_fuel_consumed_MJ"] += float(_room.fuel_consumed_MJ_step)
	_totals["species_generated_kg"] += float(_room.co_generated_kg_step) + float(_room.co2_generated_kg_step) \
			+ float(_room.hcn_generated_kg_step) + float(_room.smoke_generated_kg_step)
	_totals["unburned_inventory_MJ"] = maxf(float(_totals["unburned_inventory_MJ"]), float(_room.retained_unburned_MJ))
	if _room.fire != null:
		_totals["steps_with_a_room_fire"] += 1


func _fail(reasons: Array[String]) -> void:
	_state = STATE_FAILED
	_failure.append_array(reasons)
	_pending = {}


func _refuse_arm(reasons: Array[String]) -> Dictionary:
	_state = STATE_FAILED
	_failure = reasons.duplicate()
	return {"valid": false, "errors": reasons.duplicate()}


func _zero_totals() -> Dictionary:
	return {
		"scheduled_kj": 0.0, "accepted_kj": 0.0, "rejected_kj": 0.0,
		"to_the_gas_kj": 0.0, "radiative_term_kj": 0.0,
		"oxygen_debited_kg": 0.0, "oxygen_zone_displacement_kg": 0.0, "oxygen_debited_without_heat_kg": 0.0,
		"room_fire_fuel_consumed_MJ": 0.0, "species_generated_kg": 0.0, "unburned_inventory_MJ": 0.0,
		"steps_with_a_room_fire": 0,
	}


func _room_errors(room) -> Array[String]:
	var errors: Array[String] = []
	if room.fire != null:
		errors.append("the room has a room fire: two owners of the same heat")
	if float(room.fuel_energy_MJ) != 0.0 or float(room.max_hrr_kw) != 0.0:
		errors.append("the room has a room fuel load")
	if not room.fuel_objects.is_empty():
		errors.append("the room has fuel objects")
	if float(room.retained_unburned_MJ) != 0.0:
		errors.append("the room holds unburned energy")
	return errors


func _radiative_errors(value: Variant) -> Array[String]:
	if typeof(value) != TYPE_DICTIONARY or not _exact_keys(value, RADIATIVE_KEYS):
		return ["radiative_fraction fields must be exactly %s" % str(RADIATIVE_KEYS)]
	var errors: Array[String] = []
	if not _number(value["value"]) or float(value["value"]) < 0.10 or float(value["value"]) > 1.0:
		errors.append("radiative_fraction.value must be a number from 0.10 to 1")
	if typeof(value["class"]) != TYPE_STRING or not RADIATIVE_CLASSES.has(value["class"]):
		errors.append("radiative_fraction.class must be one of %s: no value is a fraction measured in an enclosure" % str(RADIATIVE_CLASSES))
	if typeof(value["what"]) != TYPE_STRING or String(value["what"]).strip_edges().is_empty():
		errors.append("radiative_fraction.what must say where the value comes from")
	return errors


func _regime_errors(value: Variant) -> Array[String]:
	if typeof(value) != TYPE_DICTIONARY or not _exact_keys(value, REGIME_KEYS):
		return ["regime fields must be exactly %s" % str(REGIME_KEYS)]
	var errors: Array[String] = []
	if not _number(value["oxygen_drop_tolerance"]) or float(value["oxygen_drop_tolerance"]) <= 0.0:
		errors.append("regime.oxygen_drop_tolerance must be a positive finite number")
	if not _number(value["layer_interface_min_m"]) or float(value["layer_interface_min_m"]) < 0.0:
		errors.append("regime.layer_interface_min_m must be a finite number, zero or more")
	if not _same_text(value["status"], REGIME_STATUS):
		errors.append("regime.status must be %s" % REGIME_STATUS)
	return errors


func _environment_errors(environment: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in REQUIRED_ENVIRONMENT:
		var wanted: Variant = REQUIRED_ENVIRONMENT[key]
		var found: Variant = environment.get(key)
		if typeof(found) != typeof(wanted) or found != wanted:
			errors.append("engine %s must be %s, found %s" % [key, str(wanted), str(found)])
	return errors


func _near_energy(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= SourceScript.ENERGY_ABS_TOL_KJ \
			+ SourceScript.REL_TOL * maxf(absf(actual), absf(expected))


static func _exact_keys(value: Dictionary, keys: Array[String]) -> bool:
	if value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	return true


static func _number(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	return not is_nan(float(value)) and not is_inf(float(value))


static func _same_text(value: Variant, expected: String) -> bool:
	return typeof(value) == TYPE_STRING and value == expected


static func _positive(result: Variant) -> bool:
	return typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL and result["valid"]
