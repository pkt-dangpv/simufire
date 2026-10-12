extends "res://tests/fixtures/g3_o2_venting.gd"

## All historical venting assertions remain. M2-T no longer creates live transit,
## so W08 needs an explicitly synthetic check of the remaining diagnostic API.
## This is NOT evidence of delayed O2 in product transport.
func _world(specs: Array, openings: Array, options: Dictionary) -> Dictionary:
	var world: Dictionary = super._world(specs, openings, options)
	# reset_simulation in the parent clears this suppression. Set it afterward;
	# diagnostic fixtures must not spawn graphs/dashboards when being freed.
	world["engine"].suppress_exit_graphs()
	return world


func _two_steps_and_a_neighbour() -> void:
	super._two_steps_and_a_neighbour()
	_group("V05 synthetic diagnostic transit while venting, not the live M2-T route")
	var world: Dictionary = _world([ROOM_A, ROOM_B], [], {"dt": 0.25})
	var owner = _inv(world["engine"])
	var a = world["rooms"][0]
	var b = world["rooms"][1]
	_check(_valid(world), "diagnostic world is valid")
	var before_a: float = _m(a)
	var before_b: float = _m(b)
	var before_total: float = before_a + before_b
	var answer: Dictionary = owner.exchange_between_rooms(a, b, 0.2, 0.05, 1.0, "synthetic_venting_regression")
	_check(bool(answer.get("applied", false)), "diagnostic dispatch applies")
	_check(bool(answer.get("delayed", false)), "diagnostic dispatch is explicitly delayed")
	_check(absf(_m(a) - (before_a - 0.15)) <= GAP_KG, "donor accounts for diagnostic net")
	_check(_m(b) == before_b, "future credit is not yet inventory")
	_check(absf(owner.in_transit_kg() - 0.15) <= GAP_KG, "diagnostic transit was actually queued")
	_check(absf(_m(a) + _m(b) + owner.in_transit_kg() - before_total) <= GAP_KG,
		"diagnostic inventory plus transit closes before venting")
	var dilution: Dictionary = owner.dilute_with_outside(a, 0.3, AIR, "pressure_venting")
	_check(bool(dilution.get("applied", false)), "venting with diagnostic transit applies")
	var diluted_total: float = before_total + float(dilution.get("net_kg", NAN))
	_check(absf(_m(a) + _m(b) + owner.in_transit_kg() - diluted_total) <= GAP_KG,
		"venting preserves inventory plus diagnostic transit")
	_check(owner.advance_transit(0.25).is_empty(), "diagnostic credit cannot arrive early")
	var arrivals: Array = owner.advance_transit(0.75)
	_check(arrivals.size() == 1, "diagnostic credit arrives once")
	_check(owner.in_transit_kg() == 0.0, "delivered diagnostic transit is empty")
	_check(absf(_m(b) - (before_b + 0.15)) <= GAP_KG, "receiver receives diagnostic net")
	_check(absf(_m(a) + _m(b) - diluted_total) <= GAP_KG, "diagnostic arrival preserves total")
	_free(world)
