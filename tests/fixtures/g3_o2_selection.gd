extends SceneTree

## Acceptance of stage M2 of the oxygen authority, on the REAL SimulationEngine: one
## oxygen selection per room and step, shared by the fire and by the sink, on the
## room inventory of stage M1.
##
## What it judges: that there is one selection, that the fire reads its
## concentration and the sink debits its deposit, that there is one debit and it is
## declared once, that a sealed room that burns is debited like any other, and that
## the inventory and its transit still close. It also MEASURES, without judging,
## what the change does to the fire against the historical route.
##
## It validates no temperature, no fire behaviour, no CO, FED or SVV. The heat is
## not fitted to the oxygen here: that is stage M3.
##
## On an engine without stage M2 the same checks fail one by one for what that
## engine does: the fire reads a layer number while the sink debits the room, the
## consumption is declared twice, and a sealed room that burns is refused.
## Everything new is read with `get`, `in` and `has_method`.
const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const EngineScript = preload("res://sim/core/SimulationEngine.gd")

## Oracle constants, written here and not read from the owner.
const O_M_O2_KG_PER_MOL: float = 2.0 * 15.999 / 1000.0
const O_M_DRY_AIR_KG_PER_MOL: float = 28.9647 / 1000.0
const O_REFERENCE_DENSITY_KG_M3: float = 1.2
const O_OXYGEN_KG_PER_MJ: float = 0.076
const O_CAP_FRACTION_PER_STEP: float = 0.05
const O_DELIVERY_DUE_S: float = 0.000001

## Budget gap accepted in every step, declared with stage M1 and not changed.
const GAP_KG: float = 1.0e-9
const X_TOL: float = 1.0e-12
const AIR: float = 0.209
const ROOM_A: Dictionary = {"id": 0, "x": 0.0, "w": 5.0, "l": 4.0, "h": 2.4}
const ROOM_B: Dictionary = {"id": 1, "x": 5.0, "w": 4.0, "l": 4.0, "h": 2.4}
const DEPOSIT: String = "room_inventory"
const MAX_KEPT_FAILURES: int = 60

var _failed: bool = false
var _checks: int = 0
var _group_name: String = ""
var _groups: Array[String] = []
var _failures: Array[String] = []
var _failure_count: int = 0
var _failures_by_group: Dictionary = {}
var _observations: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_one_selection_and_one_debit()
	_sealed_room()
	_identity_of_a_selection()
	_no_historical_fallback()
	_still_refused()
	_life_cycle()
	# The mutation runner asks for the judged groups only; this one measures and judges nothing of the fire.
	if OS.get_environment("G3_O2_SELECTION_JUDGED_ONLY") != "1":
		_effect_against_the_historical_route()
	print("G3_O2_SELECTION " + JSON.stringify({"checks": _checks, "groups": _groups,
		"failures": _failures, "failure_count": _failure_count, "failures_by_group": _failures_by_group,
		"observations": _observations}, "", true, true))
	if _failed:
		quit(1)
	else:
		print("G3_O2_SELECTION_PASS")
		quit(0)


# ---------------------------------------------------------------- C01, C02, C03, C05

## Two rooms closed to the outside, door open, a real fire in room 0: the case in
## which, before this stage, the fire read the lower-layer number while the sink
## debited the room.
func _one_selection_and_one_debit() -> void:
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.25, "fire": true})
	var run: Dictionary = _measure(world, 480)
	var room = world["rooms"][0]
	var idle = world["rooms"][1]
	_group("C01 one selection per room and step, the same one for the fire and for the sink")
	_check(run["selections_read"], "the owner reports a selection for every room in every step")
	_check(run["one_per_room_and_step"], "exactly one per room, of this step and this run, on the room inventory")
	_check(run["ids_never_repeat"], "no identifier is used twice")
	_check(run["fire_was_served"] == run["steps"], "the fire consulted the selection of its room in every step (%d of %d)" % [run["fire_was_served"], run["steps"]])
	_check(run["sink_steps"] > 400, "the sink acted in most steps (%d)" % run["sink_steps"])
	_check(run["sink_was_served_the_same"] == run["sink_steps"], "in every step with power the sink was served that same selection (%d of %d)" % [run["sink_was_served_the_same"], run["sink_steps"]])
	_check(run["debit_names_the_selection"] == run["sink_steps"], "and its debit names that selection and its deposit (%d of %d)" % [run["debit_names_the_selection"], run["sink_steps"]])
	_check(run["idle_room_never_debited"], "the room with no power is consulted by the fire and never debited")
	_check(run["available_is_the_oracle"], "what is available is what the room holds less what it owes in transit")
	_check(_valid(world), "the run is valid")
	_group("C02 the fire reads the concentration of the selection, derived from the inventory")
	_check(run["fire_reads_the_selection"] == run["steps"], "the fire read exactly the selected concentration in every step (%d of %d)" % [run["fire_reads_the_selection"], run["steps"]])
	_check(run["selection_is_the_inventory"] == run["steps"], "and that concentration is the inventory of the room when the step opens (%d of %d)" % [run["selection_is_the_inventory"], run["steps"]])
	_check(run["fire_deposit_is_the_room_inventory"] == run["steps"], "the deposit the fire names is the room inventory (%d of %d)" % [run["fire_deposit_is_the_room_inventory"], run["steps"]])
	_check(run["fire_reads_the_inventory"] == run["steps"], "the fire read the concentration of the inventory the sink debits in every step (%d of %d)" % [run["fire_reads_the_inventory"], run["steps"]])
	_check(run["lower_number_apart"] > 100 and run["fire_reads_the_lower_number"] == 0,
		"and never the lower-layer number, which was a different number in %d steps (read in %d of them)" % [run["lower_number_apart"], run["fire_reads_the_lower_number"]])
	_group("C03 one debit, declared once")
	var heat_mj: float = room.hrr_kj_total / 1000.0
	_check(heat_mj > 5.0, "the room burned (%.2f MJ)" % heat_mj)
	_check(run["debits_per_step_at_most_one"], "never more than one debit of a room in a step")
	_check(absf(run["consumed_kg"] - O_OXYGEN_KG_PER_MJ * heat_mj) <= GAP_KG, "the debit is 0.076 kg per MJ of the heat the room reports")
	_check(absf(room.o2_consumed_kg_total_all - run["consumed_kg"]) <= GAP_KG, "the accumulator of everything declared as consumed is the debit, once (%s against %s)" % [str(room.o2_consumed_kg_total_all), str(run["consumed_kg"])])
	_check(absf(room.o2_consumed_bulk_kg_total - run["consumed_kg"]) <= GAP_KG and absf(room.o2_consumed_fire_kg_total - run["consumed_kg"]) <= GAP_KG,
		"the other two accumulators say the same")
	_check(_same(float(_totals_of(world, 0).get("consumed_kg", NAN)), run["consumed_kg"]), "and it is what the owner applied")
	_check(idle.o2_consumed_kg_total_all == 0.0, "nothing is declared in the room that does not burn")
	_check(room.o2_upper < room.o2 - 0.01, "while the upper-layer number did fall on its own (%.4f against %.4f): an auxiliary, not a debit" % [room.o2_upper, room.o2])
	_group("C05 the inventory and its transit still close in every step")
	_closes(run, "real fire")
	_check(run["largest_transit_kg"] > 1.0e-4 and run["delayed"] > 0, "oxygen was in transit")
	_check(run["debit_within_available"], "no debit exceeded what was available to its selection")
	_check(run["clipped_kg"] == 0.0, "nothing clipped by the cap of the sink")
	run["heat_MJ"] = heat_mj
	_observe("real_fire", run)
	_free(world)


# ---------------------------------------------------------------- C04

## One room with no opening at all and a real fire: refused by stage M1, because
## its sink took a layer number and rewrote the room number from the layers.
func _sealed_room() -> void:
	_group("C04 a sealed room that burns is debited from its inventory, and no layer rewrites it")
	var world: Dictionary = _world([ROOM_A], [], {"dt": 0.25, "fire": true})
	var room = world["rooms"][0]
	var start: float = _m(room)
	var run: Dictionary = _measure(world, 480)
	var heat_mj: float = room.hrr_kj_total / 1000.0
	_check(_valid(world), "the run is valid: a sealed room that burns is a supported route (%d steps)" % run["steps_before_a_refusal"])
	_check(heat_mj > 5.0, "the room burned (%.2f MJ)" % heat_mj)
	_closes(run, "sealed room")
	_check(absf(run["consumed_kg"] + run["clipped_kg"] - O_OXYGEN_KG_PER_MJ * heat_mj) <= GAP_KG, "debit plus what the cap clipped is 0.076 kg per MJ of the heat")
	_check(absf(start + run["outside_kg"] - run["consumed_kg"] - _m(room)) <= GAP_KG, "the inventory ends at start plus infiltration minus debit")
	_check(run["fire_reads_the_selection"] == run["steps"] and run["sink_was_served_the_same"] == run["sink_steps"] and run["sink_steps"] > 400,
		"the same selection for the fire and for the sink in every step")
	_check(absf(room.o2_consumed_kg_total_all - run["consumed_kg"]) <= GAP_KG and absf(room.o2_consumed_fire_kg_total - run["consumed_kg"]) <= GAP_KG,
		"declared once, although the lower-layer number is also written")
	_check(run["number_is_derived"] == run["steps"], "the room number is the one derived from the inventory in every step")
	_check(run["blend_apart"] > 100, "and not the blend of the two layer numbers, which was a different number in %d steps" % run["blend_apart"])
	_check(room.get("o2_unauthorized_write_count") == 0, "nobody wrote the room number behind the owner")
	run["heat_MJ"] = heat_mj
	_observe("sealed_room", run)
	_free(world)


# ---------------------------------------------------------------- C06

func _identity_of_a_selection() -> void:
	_group("C06 a debit acts only on the selection of its room, its step and its run, once")
	# 1. The selection of the previous step.
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5})
	var inv = _inv(world["engine"])
	if inv == null or not inv.has_method("selection_for"):
		_check(false, "the owner hands out selections")
		_free(world)
		return
	var room = world["rooms"][0]
	var old: Dictionary = inv.selection_for(room, "fixture")
	_check(old.get("valid") == true and old.get("deposit") == DEPOSIT and int(old.get("step", -1)) == 0, "a selection exists from the moment the inventory arms")
	_check(absf(float(old.get("mole_fraction", NAN)) - AIR) <= X_TOL and absf(float(old.get("inventory_kg", NAN)) - _m(room)) <= 1.0e-15,
		"with the concentration and the content of the room")
	_advance(world, 1)
	var m: float = _m(room)
	_refused(inv.consume(room, old, 0.01, 0.01, "fixture"), "selection_of_another_step", "the selection of the previous step")
	_check(_same(_m(room), m) and inv.state() == "rejected", "it debits nothing and the run is refused")
	_free(world)
	# 2. The selection of another room, no selection, a made-up one, another deposit.
	for case: Array in [["the selection of another room", "other", "selection_of_another_room"],
			["no selection", "none", "debit_without_a_selection"],
			["an empty selection", "empty", "debit_without_a_selection"],
			["a selection that names another deposit", "deposit", "selection_of_another_deposit"],
			["a selection with a made-up identifier", "id", "selection_of_another_step"]]:
		world = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5})
		inv = _inv(world["engine"])
		room = world["rooms"][0]
		var presented: Variant = inv.selection_for(room, "fixture")
		match String(case[1]):
			"other":
				presented = inv.selection_for(world["rooms"][1], "fixture")
			"none":
				presented = null
			"empty":
				presented = {}
			"deposit":
				presented["deposit"] = "lower_layer_number"
			"id":
				presented["id"] = int(presented["id"]) + 1000
		m = _m(room)
		_refused(inv.consume(room, presented, 0.01, 0.01, "fixture"), String(case[2]), String(case[0]))
		_check(_same(_m(room), m) and inv.state() == "rejected", "%s: it debits nothing and the run is refused" % case[0])
		_free(world)
	# 3. The same selection debited twice.
	world = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5})
	inv = _inv(world["engine"])
	room = world["rooms"][0]
	var selection: Dictionary = inv.selection_for(room, "fixture")
	m = _m(room)
	var once: Dictionary = inv.consume(room, selection, 0.01, 0.01, "fixture")
	_check(once.get("applied") == true and _same(_m(room), m - 0.01) and int(once.get("selection_id", -1)) == int(selection["id"]), "a selection is debited once")
	_refused(inv.consume(room, selection, 0.01, 0.01, "fixture"), "selection_already_debited", "the same selection again")
	_check(_same(_m(room), m - 0.01), "the second debit takes nothing")
	_free(world)
	# 4. The selection of another run.
	world = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.5})
	var engine = world["engine"]
	inv = _inv(engine)
	room = world["rooms"][0]
	var of_the_first_run: Dictionary = inv.selection_for(room, "fixture")
	engine.reset_simulation(0, false)
	m = _m(room)
	_refused(inv.consume(room, of_the_first_run, 0.01, 0.01, "fixture"), "selection_of_another_run", "the selection of the run before the reset")
	_check(_same(_m(room), m), "it debits nothing")
	_free(world)


# ---------------------------------------------------------------- C07

## With the mode on, a room with no selection is a refusal for the fire too: it does
## not go back to reading a layer number.
func _no_historical_fallback() -> void:
	_group("C07 with the mode on there is no historical fallback")
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.25, "fire": true})
	var engine = world["engine"]
	var inv = _inv(engine)
	var room = world["rooms"][0]
	_advance(world, 40)
	_check(room.hrr_kw > 0.0 and str(room.fire_o2_mode_used) == DEPOSIT, "the room burns and the fire names the room inventory")
	if inv == null or not ("_selections" in inv):
		_check(false, "the owner keeps the selections of the step")
		_free(world)
		return
	# The fire step alone, on a step the owner has opened and whose selections are gone.
	inv.begin_step(engine._o2_room_inventory_environment())
	(inv.get("_selections") as Dictionary).clear()
	room.o2_lower = 0.2085
	room.o2_upper = 0.19
	engine._step_fire(float(world["dt"]))
	var report: Dictionary = _report(engine)
	_check(report.get("state") == "rejected" and _reasons(report).has("no_selection_for_this_step"), "a fire with no selection to read refuses the run by name")
	_check(str(room.fire_o2_mode_used) == "o2_selection_refused", "the fire says its selection was refused (%s)" % str(room.fire_o2_mode_used))
	_check(room.fire_o2_ref == 0.0 and room.fire_o2_ref != room.o2_lower and room.fire_o2_ref != room.o2_upper,
		"and it read no layer number in its place")
	# The engine learns of the refusal when the step that follows closes, and stops.
	engine.step(float(world["dt"]))
	_check(engine.get("o2_room_inventory_failure") == "o2_room_inventory_failed", "the engine takes the refusal as a failure of the run")
	_check(str(room.fire_o2_mode_used) == "o2_selection_refused" and room.fire_o2_ref == 0.0, "in that step the fire still reads no layer number")
	var clock: float = engine.sim_time_s
	engine.step(float(world["dt"]))
	_check(engine.sim_time_s == clock, "nothing is simulated after the refusal")
	_free(world)


# ---------------------------------------------------------------- C08

func _still_refused() -> void:
	_group("C08 what stage M2 does not cover is still refused by name")
	for case: Array in [
			["pressure network", {"network_on": true}, "environment_not_supported:pressure_network_enabled=true"],
			["diagnostic bench", {"bench_on": true}, "environment_not_supported:diagnostic_bench_enabled=true"],
			["fire oxygen mode lower", {"fire_o2_mode": "lower"}, "environment_not_supported:fire_oxygen_mode=lower"],
			["upper-number blend of the fire", {"upper_blend": 0.5}, "environment_not_supported:fire_blend_with_the_upper_number=0.5"],
			["upper-number throttle of the fire", {"upper_throttle": true}, "environment_not_supported:fire_throttle_by_the_upper_number=true"]]:
		var options: Dictionary = {"dt": 0.5}
		options.merge(case[1])
		var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], options)
		var engine = world["engine"]
		var report: Dictionary = _report(engine)
		var named: bool = false
		for record: Dictionary in report.get("rejections", []):
			named = named or (record.get("errors", []) as Array).has(case[2])
		_check(engine.get("o2_room_inventory_failure") == "o2_room_inventory_rejected" and named, "%s: the inventory does not arm, by name" % case[0])
		_check((report.get("selections", {}) as Dictionary).is_empty(), "%s: no selection exists" % case[0])
		engine.step(world["dt"])
		_check(engine.sim_time_s == 0.0, "%s: the engine does not advance" % case[0])
		_free(world)
	# An exterior door with a fire behind it: still refused where its route would write.
	var open_world: Dictionary = _world([ROOM_A], [_outside_door()], {"dt": 0.25, "fire": true, "ignite": false})
	_advance(open_world, 80)
	open_world["engine"].ignite_room(0)
	var steps: int = 0
	while steps < 480 and str(open_world["engine"].get("o2_room_inventory_failure")) == "":
		open_world["engine"].step(open_world["dt"])
		steps += 1
	var rejections: Array = _report(open_world["engine"]).get("rejections", [])
	_check(rejections.size() == 1 and (rejections[0] as Dictionary).get("route") == "exterior_opening_with_temperature_difference",
		"exterior door with a fire: refused by the route of the opening (step %d)" % steps)
	_free(open_world)


# ---------------------------------------------------------------- C09

func _life_cycle() -> void:
	_group("C09 a reset or a revocation leaves no selection behind")
	var world: Dictionary = _world([ROOM_A, ROOM_B], [_door(1.0)], {"dt": 0.25, "fire": true})
	var engine = world["engine"]
	var room = world["rooms"][0]
	var first: Dictionary = _measure(world, 160)
	var report: Dictionary = _report(engine)
	var last_id: int = _largest_selection_id(report)
	_check(last_id > 0 and (report.get("selections", {}) as Dictionary).size() == 2, "first run: selections of the step that just ran")
	engine.reset_simulation(0, true)
	report = _report(engine)
	var selections: Dictionary = report.get("selections", {})
	var fresh: bool = selections.size() == 2
	for selection: Dictionary in selections.values():
		fresh = fresh and int(selection.get("step", -1)) == 0 and int(selection.get("generation", -1)) == int(report.get("generation", -2)) \
				and int(selection.get("id", -1)) > last_id and (selection.get("served_to", [0]) as Array).is_empty() \
				and selection.get("debited") == false and absf(float(selection.get("mole_fraction", NAN)) - AIR) <= X_TOL
	_check(fresh, "reset: new selections, of the new run, at step zero, never served or debited, with the air of the start")
	var second: Dictionary = _measure(world, 160)
	_check(_digest(first) == _digest(second) and _digest(first) != "", "reset: the same run gives the same inventories, numbers, transit and fire readings")
	_closes(second, "second run")
	# Revoked on the same engine: no owner, no selection, and the fire reads as it did before.
	_switch(engine, false)
	engine.reset_simulation(0, true)
	report = _report(engine)
	_check(report.get("state") == "inactive" and not report.has("selections") and engine.get("_o2_room_inventory") == null, "revoked: no owner and no selection")
	_advance(world, 120)
	_observations["revoked"] = {"fire_reads": str(room.fire_o2_mode_used), "oxygen_the_fire_read": room.fire_o2_ref,
		"lower_number": room.o2_lower, "room_number": room.o2, "power_kw": room.hrr_kw, "time_s": engine.sim_time_s,
		"declared_kg": room.o2_consumed_kg_total_all, "debit_kg": room.o2_consumed_bulk_kg_total}
	_check(str(room.fire_o2_mode_used) == "plume_lower" and absf(room.fire_o2_ref - room.o2_lower) < 1.0e-5 and absf(room.fire_o2_ref - room.o2) > 1.0e-4,
		"revoked: the fire reads the lower-layer number again, as the historical route does")
	_check(room.o2_consumed_kg_total_all > room.o2_consumed_bulk_kg_total * 1.5 and room.o2_consumed_bulk_kg_total > 0.0, "revoked: and the consumption is declared twice again, as the historical route does")
	_free(world)


# ---------------------------------------------------------------- C10 (measured, not judged)

## The same two cases with the mode off, on the same engine: what the historical
## route does and what changes. Nothing here is a criterion of the fire.
func _effect_against_the_historical_route() -> void:
	_group("C10 the effect against the historical route is measured (not a criterion)")
	for case: Array in [["two_rooms", [ROOM_A, ROOM_B], [_door(1.0)]], ["sealed_room", [ROOM_A], []]]:
		var both: Dictionary = {}
		for mode_on: bool in [false, true]:
			var world: Dictionary = _world(case[1], case[2], {"dt": 0.25, "fire": true, "inventory": mode_on})
			var engine = world["engine"]
			var room = world["rooms"][0]
			var peak_kw: float = 0.0
			var lowest_read: float = INF
			var lowest_number: float = INF
			var steps_with_power: int = 0
			var went_out_at_s: float = -1.0
			var steps: int = 0
			# 300 s, or until the mode refuses the run.
			while steps < 1200 and str(engine.get("o2_room_inventory_failure")) in ["", "<null>"]:
				engine.step(world["dt"])
				steps += 1
				peak_kw = maxf(peak_kw, room.hrr_kw)
				lowest_read = minf(lowest_read, room.fire_o2_ref)
				lowest_number = minf(lowest_number, room.o2)
				if room.hrr_kw > 0.0:
					steps_with_power += 1
					went_out_at_s = -1.0
				elif steps_with_power > 0 and went_out_at_s < 0.0:
					went_out_at_s = engine.sim_time_s
			var totals: Dictionary = _totals_of(world, 0)
			both["on" if mode_on else "off"] = {
				"steps": steps, "time_s": engine.sim_time_s, "peak_kw": peak_kw, "heat_MJ": room.hrr_kj_total / 1000.0,
				"fire_clock_s": room.get("fire_time_s"),
				"seconds_with_power": steps_with_power * float(world["dt"]), "power_at_the_end_kw": room.hrr_kw,
				"without_power_since_s": went_out_at_s, "fire_reads": str(room.fire_o2_mode_used),
				"lowest_oxygen_the_fire_read": lowest_read, "lowest_room_number": lowest_number,
				"room_number_at_the_end": room.o2, "lower_number_at_the_end": room.o2_lower, "upper_number_at_the_end": room.o2_upper,
				"debit_of_the_room_kg": room.o2_consumed_bulk_kg_total, "declared_as_consumed_kg": room.o2_consumed_kg_total_all,
				"clipped_by_the_cap_kg": float(totals.get("consumption_clipped_kg", 0.0)),
				"demand_of_the_heat_kg": O_OXYGEN_KG_PER_MJ * room.hrr_kj_total / 1000.0,
				"failure": str(engine.get("o2_room_inventory_failure")), "rejections": _report(engine).get("rejections", []),
			}
			_free(world)
		_check(float(both["off"]["heat_MJ"]) > 5.0, "%s: the historical route burned" % case[0])
		_check(both["on"]["failure"] == "" and int(both["on"]["steps"]) == 1200, "%s: the mode ran the whole 300 s without refusing" % case[0])
		_observations["effect " + String(case[0])] = both


# ---------------------------------------------------------------- judging helpers

func _refused(result: Dictionary, reason: String, label: String) -> void:
	_check(result.get("applied") == false and result.get("reason") == reason, "%s is refused as %s (%s)" % [label, reason, str(result.get("reason"))])


## The three budgets of a measured run, each within the accepted gap in every step.
func _closes(acc: Dictionary, label: String) -> void:
	_check(acc["inventory_read"], label + ": the inventory is read from the rooms")
	_check(acc["room_gap_kg"] <= GAP_KG, label + ": every room changes by its operations (worst %s kg)" % str(acc["room_gap_kg"]))
	_check(acc["building_gap_kg"] <= GAP_KG, label + ": inventories plus transit change by exterior minus debit (worst %s kg)" % str(acc["building_gap_kg"]))
	_check(acc["oracle_gap_kg"] <= GAP_KG, label + ": and by what the closed forms say, with no operation read (worst %s kg)" % str(acc["oracle_gap_kg"]))
	_check(acc["lowest_inventory_kg"] >= 0.0, label + ": no inventory below zero")


func _valid(world: Dictionary) -> bool:
	var report: Dictionary = _report(world["engine"])
	return report.get("state") == "armed" and (report.get("rejections", []) as Array).is_empty() \
			and world["engine"].get("o2_room_inventory_failure") == ""


# ---------------------------------------------------------------- measuring

## Steps the world and, in every step, reads the selections, what the fire read, the
## operations of the owner and the three budgets of stage M1.
## - by operations: every room changes by the operations the owner applied to it;
## - of the building: inventories plus transit change by exterior minus debit;
## - by closed form, with no operation read: the debit is the demand of the power
##   of the step, capped at 5 % of what the room holds when the sink runs, and the
##   exterior exchange is the infiltration law on that same content.
func _measure(world: Dictionary, steps: int) -> Dictionary:
	var acc: Dictionary = {"steps": 0, "steps_before_a_refusal": 0, "inventory_read": true, "selections_read": true,
		"one_per_room_and_step": true, "ids_never_repeat": true, "fire_was_served": 0, "sink_steps": 0, "sink_was_served_the_same": 0,
		"debit_names_the_selection": 0, "idle_room_never_debited": true, "available_is_the_oracle": true,
		"fire_reads_the_selection": 0, "selection_is_the_inventory": 0, "fire_deposit_is_the_room_inventory": 0, "lower_number_apart": 0,
		"fire_reads_the_inventory": 0, "fire_reads_the_lower_number": 0,
		"debits_per_step_at_most_one": true, "debit_within_available": true, "number_is_derived": 0, "blend_apart": 0,
		"room_gap_kg": 0.0, "building_gap_kg": 0.0, "oracle_gap_kg": 0.0, "largest_transit_kg": 0.0, "lowest_inventory_kg": INF,
		"operations": 0, "delayed": 0, "consumed_kg": 0.0, "clipped_kg": 0.0, "outside_kg": 0.0, "highest_x": 0.0,
		"lowest_oxygen_the_fire_read": INF, "peak_kw": 0.0, "digest_values": PackedFloat64Array()}
	var engine = world["engine"]
	var dt: float = float(world["dt"])
	var seen_ids: Dictionary = {}
	var burning = world["rooms"][0]
	for _i: int in range(steps):
		var before: Dictionary = _snapshot(world)
		engine.step(dt)
		acc["steps"] += 1
		if str(engine.get("o2_room_inventory_failure")) == "":
			acc["steps_before_a_refusal"] += 1
		var after: Dictionary = _snapshot(world)
		var report: Dictionary = _report(engine)
		var operations: Array = report.get("step_operations", [])
		var selections: Dictionary = report.get("selections", {})
		acc["operations"] += operations.size()
		acc["peak_kw"] = maxf(acc["peak_kw"], burning.hrr_kw)
		acc["lowest_oxygen_the_fire_read"] = minf(acc["lowest_oxygen_the_fire_read"], burning.fire_o2_ref)
		# --- what the fire read, against the inventory the sink debits and against the lower-layer number ---
		var inventory_x: float = _oracle_x(float(before["m"][burning.id]), burning.volume_m3())
		if absf(burning.fire_o2_ref - inventory_x) <= X_TOL:
			acc["fire_reads_the_inventory"] += 1
		if absf(float(before["lower"]) - inventory_x) > 0.001:
			acc["lower_number_apart"] += 1
			if absf(burning.fire_o2_ref - float(before["lower"])) <= X_TOL:
				acc["fire_reads_the_lower_number"] += 1
		# --- the selections of the step ---
		if selections.size() != (world["rooms"] as Array).size():
			acc["selections_read"] = false
		var debits_by_room: Dictionary = {}
		for operation: Dictionary in operations:
			if String(operation.get("kind", "")) == "consume":
				debits_by_room[int(operation["room"])] = debits_by_room.get(int(operation["room"]), []) + [operation]
		for room in world["rooms"]:
			var selection: Dictionary = selections.get(room.id, {})
			var debits: Array = debits_by_room.get(room.id, [])
			if debits.size() > 1:
				acc["debits_per_step_at_most_one"] = false
			if selection.is_empty():
				acc["selections_read"] = false
				continue
			var id: int = int(selection.get("id", -1))
			if seen_ids.has(id):
				acc["ids_never_repeat"] = false
			seen_ids[id] = true
			if int(selection.get("room", -1)) != room.id or int(selection.get("step", -1)) != int(report.get("step", -2)) \
					or int(selection.get("generation", -1)) != int(report.get("generation", -2)) or selection.get("deposit") != DEPOSIT:
				acc["one_per_room_and_step"] = false
			var held_kg: float = float(before["m"][room.id])
			var owed_kg: float = float(before["owed"].get(room.id, 0.0))
			if absf(float(selection.get("available_kg", NAN)) - maxf(0.0, held_kg - owed_kg)) > 1.0e-15 \
					or absf(float(selection.get("inventory_kg", NAN)) - held_kg) > 1.0e-15:
				acc["available_is_the_oracle"] = false
			var served: Array = selection.get("served_to", [])
			if room == burning:
				if served.count("fire") == 1:
					acc["fire_was_served"] += 1
				if room.fire_o2_ref == float(selection.get("mole_fraction", NAN)):
					acc["fire_reads_the_selection"] += 1
				if absf(float(selection.get("mole_fraction", NAN)) - _oracle_x(held_kg, room.volume_m3())) <= X_TOL:
					acc["selection_is_the_inventory"] += 1
				if str(room.fire_o2_mode_used) == DEPOSIT:
					acc["fire_deposit_is_the_room_inventory"] += 1
				if debits.size() == 1:
					acc["sink_steps"] += 1
					if served == ["fire", "sink"]:
						acc["sink_was_served_the_same"] += 1
					if int((debits[0] as Dictionary).get("selection_id", -1)) == id and (debits[0] as Dictionary).get("deposit") == DEPOSIT \
							and selection.get("debited") == true:
						acc["debit_names_the_selection"] += 1
					if float((debits[0] as Dictionary)["applied_kg"]) > float(selection.get("available_kg", -1.0)) + maxf(0.0, float(before["due"].get(room.id, 0.0))):
						acc["debit_within_available"] = false
			elif not debits.is_empty() or served.has("sink") or selection.get("debited") != false:
				acc["idle_room_never_debited"] = false
		# --- the three budgets ---
		var effects: Dictionary = _effects(world, operations)
		var expected_change_kg: float = 0.0
		for room in world["rooms"]:
			var m_before: float = float(before["m"][room.id])
			var m_after: float = float(after["m"][room.id])
			if is_nan(m_before) or is_nan(m_after):
				acc["inventory_read"] = false
				continue
			acc["room_gap_kg"] = maxf(acc["room_gap_kg"], absf(m_after - m_before - float(effects["by_room"][room.id])))
			acc["lowest_inventory_kg"] = minf(acc["lowest_inventory_kg"], m_after)
			acc["highest_x"] = maxf(acc["highest_x"], room.o2)
			acc["digest_values"].append(m_after)
			acc["digest_values"].append(room.o2)
			acc["digest_values"].append(room.fire_o2_ref)
			if absf(room.o2 - _oracle_x(m_after, room.volume_m3())) <= X_TOL:
				acc["number_is_derived"] += 1 if room == burning else 0
			var upper_share: float = clampf((room.height_m - engine.thermal_system.flow_interface_height_m(room)) / room.height_m, 0.01, 1.0)
			if room == burning and absf(room.o2 - (room.o2_upper * upper_share + room.o2_lower * (1.0 - upper_share))) > 0.001:
				acc["blend_apart"] += 1
			var held_kg: float = m_before + float(before["due"].get(room.id, 0.0))
			var demand_kg: float = float(room.hrr_kw) / 1000.0 * O_OXYGEN_KG_PER_MJ * dt
			var debit_kg: float = minf(demand_kg, held_kg * O_CAP_FRACTION_PER_STEP)
			var gas_kg: float = room.volume_m3() * (engine.ach_infiltration / 3600.0) * O_REFERENCE_DENSITY_KG_M3 * dt
			expected_change_kg += _oracle_parcel_kg(world["building"].outside_o2 - _oracle_x(held_kg, room.volume_m3()), gas_kg) - debit_kg
		if not acc["inventory_read"]:
			continue
		var total_change_kg: float = float(after["total"]) - float(before["total"])
		acc["building_gap_kg"] = maxf(acc["building_gap_kg"], absf(total_change_kg - (float(effects["outside_kg"]) - float(effects["consumed_kg"]))))
		acc["oracle_gap_kg"] = maxf(acc["oracle_gap_kg"], absf(total_change_kg - expected_change_kg))
		acc["largest_transit_kg"] = maxf(acc["largest_transit_kg"], absf(float(after["transit"])))
		acc["consumed_kg"] += float(effects["consumed_kg"])
		acc["clipped_kg"] += float(effects["clipped_kg"])
		acc["outside_kg"] += float(effects["outside_kg"])
		acc["delayed"] += int(effects["delayed"])
		acc["digest_values"].append(float(after["transit"]))
	return acc


## What the operations of a step did, room by room. A delayed exchange changes the
## donor only: the receiver changes when its entry arrives, and only then.
func _effects(world: Dictionary, operations: Array) -> Dictionary:
	var by_room: Dictionary = {}
	for room in world["rooms"]:
		by_room[room.id] = 0.0
	var out: Dictionary = {"by_room": by_room, "outside_kg": 0.0, "consumed_kg": 0.0, "clipped_kg": 0.0, "delayed": 0}
	for operation: Dictionary in operations:
		match String(operation.get("kind", "")):
			"consume":
				by_room[int(operation["room"])] -= float(operation["applied_kg"])
				out["consumed_kg"] += float(operation["applied_kg"])
				out["clipped_kg"] += float(operation["clipped_kg"])
			"outside":
				by_room[int(operation["room"])] += float(operation["in_kg"]) - float(operation["out_kg"])
				out["outside_kg"] += float(operation["in_kg"]) - float(operation["out_kg"])
			"interior":
				by_room[int(operation["donor"])] += float(operation["to_donor_kg"]) - float(operation["to_receiver_kg"])
				if bool(operation["delayed"]):
					out["delayed"] += 1
				else:
					by_room[int(operation["receiver"])] += float(operation["to_receiver_kg"]) - float(operation["to_donor_kg"])
			"arrival":
				by_room[int(operation["room"])] += float(operation["net_kg"])
	return out


## What the state shows before a step: the inventory of every room, the transit,
## what is due to every room within the step and what every room still owes.
func _snapshot(world: Dictionary) -> Dictionary:
	var report: Dictionary = _report(world["engine"])
	var dt: float = float(world["dt"])
	var m: Dictionary = {}
	var due: Dictionary = {}
	var owed: Dictionary = {}
	var total: float = 0.0
	for room in world["rooms"]:
		m[room.id] = _m(room)
		total += _m(room)
	var transit: float = 0.0
	for entry: Dictionary in report.get("transit", []):
		var receiver: int = int(entry["receiver"])
		transit += float(entry["net_kg"])
		owed[receiver] = float(owed.get(receiver, 0.0)) - minf(0.0, float(entry["net_kg"]))
		if maxf(0.0, float(entry["delay_s"]) - dt) <= O_DELIVERY_DUE_S:
			due[receiver] = float(due.get(receiver, 0.0)) + float(entry["net_kg"])
	return {"m": m, "due": due, "owed": owed, "transit": transit, "total": total + transit,
		"lower": float(world["rooms"][0].o2_lower)}


func _advance(world: Dictionary, steps: int) -> void:
	for _i: int in range(steps):
		world["engine"].step(float(world["dt"]))


func _digest(acc: Dictionary) -> String:
	var values: PackedFloat64Array = acc.get("digest_values", PackedFloat64Array())
	if values.is_empty():
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(values.to_byte_array())
	return context.finish().hex_encode()


func _largest_selection_id(report: Dictionary) -> int:
	var largest: int = -1
	for selection: Dictionary in (report.get("selections", {}) as Dictionary).values():
		largest = maxi(largest, int(selection.get("id", -1)))
	return largest


func _reasons(report: Dictionary) -> Array:
	var out: Array = []
	for record: Dictionary in report.get("rejections", []):
		out.append(record.get("reason"))
	return out


func _observe(name: String, acc: Dictionary) -> void:
	var kept: Dictionary = {}
	for key: String in acc.keys():
		if key != "digest_values":
			kept[key] = acc[key]
	_observations[name] = kept


# ---------------------------------------------------------------- reading the mode

func _switch(engine, value: bool) -> void:
	if "o2_room_inventory_enabled" in engine:
		engine.set("o2_room_inventory_enabled", value)


func _inv(engine):
	return engine.get("_o2_room_inventory")


func _m(room) -> float:
	var value: Variant = room.get("o2_inventory_kg")
	return float(value) if typeof(value) == TYPE_FLOAT else NAN


func _report(engine) -> Dictionary:
	if not engine.has_method("get_o2_room_inventory_report"):
		return {"state": "absent"}
	return engine.call("get_o2_room_inventory_report")


func _totals_of(world: Dictionary, room_id: int) -> Dictionary:
	return _report(world["engine"]).get("rooms", {}).get(room_id, {})


# ---------------------------------------------------------------- oracle

func _oracle_x(o2_kg: float, volume_m3: float) -> float:
	return o2_kg / ((volume_m3 * O_REFERENCE_DENSITY_KG_M3 / O_M_DRY_AIR_KG_PER_MOL) * O_M_O2_KG_PER_MOL)


func _oracle_parcel_kg(mole_fraction: float, gas_kg: float) -> float:
	return mole_fraction * (gas_kg / O_M_DRY_AIR_KG_PER_MOL) * O_M_O2_KG_PER_MOL


# ---------------------------------------------------------------- building

func _world(specs: Array, openings: Array, options: Dictionary) -> Dictionary:
	# The building enters the tree first: its `_ready` loads the product preset and
	# would replace a template loaded before it.
	var building = BuildingModelScript.new()
	root.add_child(building)
	var rooms: Array = []
	var rects: Dictionary = {}
	for spec: Dictionary in specs:
		var burning: bool = bool(options.get("fire", false)) and int(spec["id"]) == 0
		var room: Dictionary = {
			"id": int(spec["id"]), "name": "Sala%d" % int(spec["id"]), "kind": "salon" if burning else "pasillo",
			"floor_level_z_m": 0.0, "height_m": float(spec["h"]), "rotation_deg": 0.0,
			"fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0, "fuel_objects": [],
		}
		if burning:
			room["fuel_energy_MJ"] = 1100.0
			room["max_hrr_kw"] = 700.0
			room["fuel_objects"] = [{
				"id": "sofa", "kind": "mobiliario_tapizado", "name": "Sofa",
				"fuel_energy_MJ": 1100.0, "remaining_fuel_MJ": 1100.0, "max_hrr_kw": 700.0,
				"co_yield_kg_per_MJ": 0.0004, "smoke_yield_kg_per_MJ": 0.012,
				"o2_consumption_kg_per_MJ": 0.076, "elevation_m": 0.38,
				"exposed_area_m2": 3.6, "footprint_m2": 2.1, "ignition_flux_kw_m2": 16.0,
				"ignition_temp_c": 310.0, "is_primary_ignition_source": true,
				"position_m": {"x": 1.0, "y": 1.2}, "size_m": {"x": 0.9, "y": 2.35},
				"room_id": 0, "rotation_deg": 0.0,
			}]
		rooms.append(room)
		rects[str(int(spec["id"]))] = {"x": float(spec["x"]), "y": 0.0, "w": float(spec["w"]), "h": float(spec["l"])}
	building.load_template_data({
		"building_type": "house", "floors": [{"level_m": 0.0, "name": "PB"}], "rooms_data": rooms,
		"room_rect_m": rects, "openings_data": openings, "ignition_room_id": 0, "hvac_mode": "none",
	})
	var engine = EngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.sim_fixed_dt = float(options["dt"])
	if bool(options.get("network_on", false)):
		# Negative control: the pressure network is not a route of this mode.
		engine.pressure_network_solver_enabled = true
	if bool(options.get("bench_on", false)):
		# Negative control: only the switch of the diagnostic bench. The bench is never armed here.
		engine.g3_prescribed_thermal_source_enabled = true
	if options.has("fire_o2_mode"):
		engine.fire_o2_mode = String(options["fire_o2_mode"])
	if options.has("upper_blend"):
		engine.fire_o2_upper_hrr_blend = float(options["upper_blend"])
	if bool(options.get("upper_throttle", false)):
		engine.fire_o2_upper_throttle_enabled = true
	if bool(options.get("inventory", true)):
		_switch(engine, true)
	engine.suppress_exit_graphs()
	root.add_child(engine)
	engine.reset_simulation(0, bool(options.get("ignite", options.get("fire", false))))
	var models: Array = []
	for spec: Dictionary in specs:
		models.append(building.get_room(int(spec["id"])))
	return {"engine": engine, "building": building, "rooms": models, "dt": float(options["dt"])}


func _door(open_fraction: float) -> Dictionary:
	return {"a": 0, "b": 1, "type": "door", "width_m": 0.9, "height_m": 2.0, "sill_m": 0.0, "offset_m": 0.5,
		"offset_is_fraction": true, "open_fraction": open_fraction, "wall": "", "hinge_side": "left", "swing_direction": "in"}


func _outside_door() -> Dictionary:
	return {"a": 0, "b": -1, "type": "door", "width_m": 0.9, "height_m": 2.0, "open_fraction": 1.0, "offset_m": 0.5,
		"offset_is_fraction": true, "sill_m": 0.0, "wall": "bottom"}


func _free(world: Dictionary) -> void:
	world["engine"].queue_free()
	world["building"].queue_free()


# ---------------------------------------------------------------- checks

func _same(a: float, b: float) -> bool:
	return a == b or (is_nan(a) and is_nan(b))


func _group(title: String) -> void:
	_group_name = title.substr(0, 3)
	_groups.append(title)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed = true
		_failure_count += 1
		_failures_by_group[_group_name] = int(_failures_by_group.get(_group_name, 0)) + 1
		# A few of every group are kept, so that a flood in one does not hide the others.
		if int(_failures_by_group[_group_name]) <= 8 and _failures.size() < MAX_KEPT_FAILURES * 2:
			_failures.append(_group_name + " " + label)
