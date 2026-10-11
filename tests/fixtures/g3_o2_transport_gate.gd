extends "res://tests/fixtures/g3_o2_m3_diagnosis.gd"

## M2-T diagnosis ONLY. Uses the published engine without changing its code.
## Direct owner operations do not step the fire. The last control DOES step
## the whole engine and repeats the declared debt injection of M3.

var _transport_cases: Dictionary = {}


func _run() -> void:
	_out_dir = OS.get_environment("G3_O2_M3_DIAGNOSIS_OUT")
	_exchange_case("equal", 0.209, 0.209, 2.0)
	_exchange_case("hot_poor", 0.10, 0.209, 2.0)
	_exchange_case("hot_rich", 0.209, 0.10, 2.0)
	_exchange_case("no_delay", 0.10, 0.209, 0.0)
	_case("obligation with the door closed", {
		"what": "published M3 control repeated: owner injects debt at 100 s; this is not a natural doorway event",
		"rooms": 2, "door": false, "dt": 0.25, "steps": 1200,
		"fire": SOFA, "at_s": 100.0, "owe_all_but_kg": 0.02, "delay_s": 1.0,
	})
	print("G3_O2_TRANSPORT_GATE " + JSON.stringify({
		"exchanges": _transport_cases, "engine_cases": _summaries,
	}, "", true, true))
	quit(0)


func _exchange_case(label: String, xa: float, xb: float, delay: float) -> void:
	var world: Dictionary = _world({"rooms": 2, "door": false, "dt": 0.25, "fire": SOFA})
	var engine = world["engine"]
	var owner = engine.get("_o2_room_inventory")
	var a = world["rooms"][0]
	var b = world["rooms"][1]
	owner.declare_initial_mole_fraction(a, xa)
	owner.declare_initial_mole_fraction(b, xb)
	var gas: float = minf(owner.reference_gas_kg(a.volume_m3()), owner.reference_gas_kg(b.volume_m3())) * 0.04
	var before: Dictionary = owner.report()
	var result: Dictionary = owner.exchange_between_rooms(
		a, b, owner.o2_kg_in_reference_gas(a.o2, gas), owner.o2_kg_in_reference_gas(b.o2, gas),
		delay, "transport_gate_declared_owner_operation"
	)
	var dispatched: Dictionary = owner.report()
	owner.begin_step(engine.call("_o2_room_inventory_environment"))
	var selections: Dictionary = owner.report().get("selections", {})
	var halfway: Array = owner.advance_transit(delay * 0.5)
	var before_due: Dictionary = owner.report()
	var arrived: Array = owner.advance_transit(delay * 0.5)
	_transport_cases[label] = {
		"gas_kg": gas, "delay_s": delay, "before": before, "answer": result,
		"dispatched": dispatched, "next_selections": selections, "halfway": halfway,
		"before_due": before_due, "arrived": arrived, "delivered": owner.report(),
	}
	engine.queue_free()
	world["building"].queue_free()
