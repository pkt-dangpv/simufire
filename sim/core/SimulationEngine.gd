extends RefCounted
class_name SimulationEngine

# ============================================================
# SIMULATION ENGINE
# ------------------------------------------------------------
# Responsabilidad:
# - coordinar el orden de simulación
# - aplicar fuego por sala
# - procesar intercambio por openings
# - aplicar deltas de humo / energía / O2
# - recalcular capa de humo
# - aplicar pérdidas térmicas
# - evaluar flashover
# - devolver snapshot final para HUD / visualizer
# ============================================================

var sim_time: float = 0.0
var debug_accum: float = 0.0

var building: BuildingModel
var smoke: SmokeModel


func _init(building_model: BuildingModel, smoke_model: SmokeModel) -> void:
	building = building_model
	smoke = smoke_model


func step(delta: float) -> void:
	sim_time += delta

	# 0) clamp inicial
	for room in building.rooms.values():
		room.clamp_state()

	# 1) fuego por sala
	for room in building.rooms.values():
		if room.fire != null:
			var vent_limit_hrr_kw: float = INF

			if room.hrr_kw > 200.0 and building._has_outside_opening(room.id):
				vent_limit_hrr_kw = building._estimate_vent_hrr_kw(room.id)

			room.fire.step(room, delta, vent_limit_hrr_kw)

	# 2) deltas de intercambio por openings
	var d_smoke: Dictionary = {}
	var d_energy: Dictionary = {}
	var d_o2: Dictionary = {}

	for op in building.openings:
		smoke.process_opening(
			op,
			building.rooms,
			building.outside_temp_c,
			building.OUTSIDE_ID,
			delta,
			d_smoke,
			d_energy,
			d_o2,
			Callable(self, "_mix_o2"),
			Callable(self, "_ventilate_o2_to_outside")
		)

	# 3) aplicar humo
	for id in d_smoke.keys():
		if id == building.OUTSIDE_ID:
			continue

		var rs: RoomModel = building.rooms.get(id)
		if rs != null:
			rs.add_upper_smoke(d_smoke[id])

	# 4) aplicar energía
	for id in d_energy.keys():
		if id == building.OUTSIDE_ID:
			continue

		var re: RoomModel = building.rooms.get(id)
		if re != null:
			re.add_upper_energy(d_energy[id])

	# 5) aplicar O2
	for id in d_o2.keys():
		if id == building.OUTSIDE_ID:
			continue

		var ro: RoomModel = building.rooms.get(id)
		if ro != null:
			ro.o2 = clampf(ro.o2 + d_o2[id], 0.0, building.o2_nominal)

	# 6) pérdidas térmicas
	for room in building.rooms.values():
		_apply_thermal_losses(room, delta)

	# 7) recalcular capa de humo
	for room in building.rooms.values():
		smoke.update_layer_height(room)

	# 8) flashover
	for room in building.rooms.values():
		_update_flashover(room)

	# 9) ignición secundaria
	_update_secondary_ignition()

	# 10) debug temporal
	debug_accum += delta
	if debug_accum >= 1.0:
		debug_accum = 0.0

		for room_id in [0, 1, 2]:
			var room: RoomModel = building.rooms.get(room_id)
			if room != null:
				print(
					"ROOM ", room.id,
					" HRR=", room.hrr_kw,
					" O2=", room.o2,
					" Smoke=", room.smoke_mass_kg,
					" Layer=", room.h_layer_m,
					" Upper=", room.temp_upper_c,
					" Lower=", room.temp_lower_c
				)

	# 11) clamp final
	for room in building.rooms.values():
		room.clamp_state()


# ============================================================
# HELPERS INTERNOS
# ============================================================

func _accum(dict: Dictionary, key: int, value: float) -> void:
	dict[key] = dict.get(key, 0.0) + value


func _mix_o2(
	from_id: int,
	from_room: RoomModel,
	to_id: int,
	to_room: RoomModel,
	dm: float,
	d_o2: Dictionary
) -> void:
	var air_from: float = building.air_density_kg_m3 * from_room.get_volume_m3()
	var air_to: float = building.air_density_kg_m3 * to_room.get_volume_m3()
	var denom: float = maxf(1.0, air_from + air_to)

	var mix: float = clampf(building.o2_mix_rate * (dm / denom) * 50.0, 0.0, 0.25)

	var o2a: float = from_room.o2
	var o2b: float = to_room.o2

	var new_a: float = lerpf(o2a, o2b, mix)
	var new_b: float = lerpf(o2b, o2a, mix)

	_accum(d_o2, from_id, new_a - o2a)
	_accum(d_o2, to_id, new_b - o2b)


func _ventilate_o2_to_outside(
	room_id: int,
	room: RoomModel,
	op: OpeningModel,
	dm: float,
	d_o2: Dictionary
) -> void:
	var vent: float = clampf(
		building.o2_vent_rate * op.open_fraction * (dm / maxf(0.01, smoke.max_spill_kg_s)),
		0.0,
		0.25
	)

	var new_o2: float = lerpf(room.o2, building.o2_nominal, vent)
	_accum(d_o2, room_id, new_o2 - room.o2)


func _apply_thermal_losses(room: RoomModel, delta: float) -> void:
	var excess_to_lower: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)
	room.temp_upper_c -= excess_to_lower * building.upper_to_lower_loss_rate * delta

	var excess_to_ambient: float = maxf(0.0, room.temp_upper_c - building.outside_temp_c)
	room.temp_upper_c -= excess_to_ambient * building.upper_to_ambient_loss_rate * delta

	var target_lower: float = minf(room.temp_upper_c, building.outside_temp_c + 120.0)
	room.temp_lower_c = lerpf(
		room.temp_lower_c,
		target_lower,
		building.lower_layer_warming_rate * delta
	)

	room.temp_upper_c = clampf(
		room.temp_upper_c,
		room.temp_lower_c,
		building.max_upper_temp_c
	)


func _update_flashover(room: RoomModel) -> void:
	if room == null:
		return

	room.pre_flashover = (
		room.temp_upper_c >= building.preflash_temp_c
		and room.h_layer_m <= building.preflash_layer_m
	)

	if room.flashover_triggered:
		return

	if room.temp_upper_c >= building.flashover_temp_c \
	and room.h_layer_m <= building.flashover_layer_m \
	and room.hrr_kw >= building.flashover_min_hrr_kw:
		room.flashover_triggered = true


func _update_secondary_ignition() -> void:
	for room in building.rooms.values():
		if room.fire != null:
			continue

		var hot: bool = room.temp_upper_c > 120.0
		var smoky: bool = room.smoke_mass_kg > 0.2

		if not (hot and smoky):
			continue

		var ignition_chance: float = clampf(
			(room.temp_upper_c - 120.0) / 200.0,
			0.0,
			0.6
		)

		if randf() > ignition_chance:
			continue

		var fire: FireModel = FireModel.new()
		room.fire = fire

		fire.growth_alpha_kw_s2 = 0.008
		fire.max_hrr_kw = 1500.0
		fire.secondary_hrr_gain_kw = 800.0
		fire.flashover_hrr_multiplier = building.flashover_hrr_multiplier
		fire.flashover_min_hrr_kw = building.flashover_min_hrr_kw
		fire.o2_nominal = building.o2_nominal
		fire.o2_min_for_flame = building.o2_min_for_flame
		fire.smoke_yield_kg_per_MJ = building.smoke_yield_kg_per_MJ

		print("IGNICION secundaria en room ", room.id)

func get_state() -> Dictionary:
	var out: Dictionary = {}
	out["sim_time_s"] = sim_time

	for rid in building.rooms.keys():
		var room: RoomModel = building.rooms[rid]
		out[str(rid)] = room.to_state_dict()

	return out