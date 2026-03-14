extends RefCounted
class_name FireModel

var sim_time_s: float = 0.0

# crecimiento t²
var growth_alpha_kw_s2: float = 0.0117
var max_hrr_kw: float = 3000.0
var min_hrr_kw: float = 10.0

# post-flashover
var secondary_hrr_gain_kw: float = 2500.0
var flashover_hrr_multiplier: float = 2.2
var flashover_min_hrr_kw: float = 300.0

# combustión / oxígeno
var o2_nominal: float = 0.209
var o2_min_for_flame: float = 0.12
var smoke_yield_kg_per_MJ: float = 0.12

# aporte térmico directo
var upper_heat_fraction: float = 1.0


func step(room: RoomModel, delta: float, vent_limit_hrr_kw: float = INF) -> void:
	if room == null:
		return

	sim_time_s += delta

	var current_hrr_cap_kw: float = max_hrr_kw
	if room.flashover_triggered:
		current_hrr_cap_kw += secondary_hrr_gain_kw

	var hrr_t2_kw: float = growth_alpha_kw_s2 * sim_time_s * sim_time_s
	hrr_t2_kw = minf(hrr_t2_kw, current_hrr_cap_kw)

	var o2_factor: float = _get_o2_factor(room.o2)

	var hrr_kw: float = hrr_t2_kw * o2_factor
	hrr_kw = maxf(min_hrr_kw, hrr_kw)
	hrr_kw = minf(hrr_kw, vent_limit_hrr_kw)

	if room.flashover_triggered:
		hrr_kw = minf(
			maxf(hrr_kw, flashover_min_hrr_kw * flashover_hrr_multiplier),
			current_hrr_cap_kw
		)

	room.hrr_kw = hrr_kw

	_consume_o2(room, delta)
	_generate_smoke(room, delta)
	_add_heat(room, delta)


func _get_o2_factor(room_o2: float) -> float:
	var factor: float = clampf(
		(room_o2 - o2_min_for_flame) / maxf(0.001, o2_nominal - o2_min_for_flame),
		0.0,
		1.0
	)
	return pow(factor, 0.8)


func _consume_o2(room: RoomModel, delta: float) -> void:
	var consumption: float = room.hrr_kw * 0.0000012 * delta
	room.consume_o2(consumption)


func _generate_smoke(room: RoomModel, delta: float) -> void:
	# kW * s = kJ ; /1000 = MJ
	var energy_MJ: float = room.hrr_kw * delta / 1000.0
	var smoke_mass_kg: float = energy_MJ * smoke_yield_kg_per_MJ
	room.add_upper_smoke(smoke_mass_kg)


func _add_heat(room: RoomModel, delta: float) -> void:
	var energy_kJ: float = room.hrr_kw * delta * upper_heat_fraction
	room.add_upper_energy(energy_kJ)