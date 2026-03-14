extends Resource
class_name SmokeModel

@export var smoke_yield_kg_per_kw_s: float = 0.002
@export var smoke_density_kg_m3: float = 0.25
@export var min_layer_height_m: float = 0.20

# Transporte / spill entre compartimentos
@export var base_spill_kg_s_per_m2: float = 0.18
@export var temp_push_factor: float = 0.008
@export var max_spill_kg_s: float = 0.9
@export var max_fraction_out_per_s: float = 0.025
@export var layer_relax_down: float = 0.18
@export var layer_relax_up: float = 0.015


func generate_fire_smoke(room: RoomModel, hrr_kw: float, delta: float) -> void:
	if room == null:
		return

	var smoke_generated_kg: float = maxf(hrr_kw, 0.0) * smoke_yield_kg_per_kw_s * maxf(delta, 0.0)
	room.add_upper_smoke(smoke_generated_kg)


func update_layer_height(room: RoomModel) -> void:
	if room == null:
		return

	var base_density: float = maxf(0.05, smoke_density_kg_m3)

	# expansión térmica simplificada:
	# cuanto más caliente la capa upper, más volumen efectivo ocupa el humo
	var temp_factor: float = clampf(1.0 + maxf(0.0, room.temp_upper_c - 20.0) / 180.0, 1.0, 3.5)

	var smoke_volume_m3: float = (room.smoke_mass_kg / base_density) * temp_factor

	var floor_area_m2: float = room.get_floor_area_m2()
	if floor_area_m2 <= 0.01:
		floor_area_m2 = maxf(room.get_volume_m3() / maxf(0.1, room.height_m), 0.01)

	var upper_height_target_m: float = smoke_volume_m3 / maxf(0.01, floor_area_m2)

	# pequeño refuerzo de descenso cuando la sala ya está claramente caliente
	var descent_boost: float = 1.0
	if room.temp_upper_c > 120.0:
		descent_boost += clampf((room.temp_upper_c - 120.0) / 300.0, 0.0, 0.6)

	upper_height_target_m *= descent_boost

	var target_layer_m: float = clampf(
		room.height_m - upper_height_target_m,
		min_layer_height_m,
		room.height_m
	)

	room.h_layer_m = target_layer_m
	room.clamp_state()


func step_room_smoke(room: RoomModel, hrr_kw: float, delta: float) -> void:
	generate_fire_smoke(room, hrr_kw, delta)
	update_layer_height(room)


func estimate_smoke_volume_m3(room: RoomModel) -> float:
	if room == null:
		return 0.0

	return room.smoke_mass_kg / maxf(0.05, smoke_density_kg_m3)


func process_opening(
	op: OpeningModel,
	rooms: Dictionary,
	outside_temp_c: float,
	outside_id: int,
	delta: float,
	d_smoke: Dictionary,
	d_energy: Dictionary,
	d_o2: Dictionary,
	mix_o2_callable: Callable,
	ventilate_o2_callable: Callable
) -> void:
	if op == null:
		return

	if op.open_fraction <= 0.0:
		return

	var room_a: RoomModel = null
	var room_b: RoomModel = null

	if op.a != outside_id:
		room_a = rooms.get(op.a)

	if op.b != outside_id:
		room_b = rooms.get(op.b)

	var temp_a: float = outside_temp_c
	var temp_b: float = outside_temp_c
	var smoke_a: float = 0.0
	var smoke_b: float = 0.0
	var layer_a: float = 999.0
	var layer_b: float = 999.0

	if room_a != null:
		temp_a = room_a.temp_upper_c
		smoke_a = room_a.smoke_mass_kg
		layer_a = room_a.h_layer_m

	if room_b != null:
		temp_b = room_b.temp_upper_c
		smoke_b = room_b.smoke_mass_kg
		layer_b = room_b.h_layer_m

	var area_open_m2: float = maxf(0.0, op.width_m * op.height_m * clampf(op.open_fraction, 0.0, 1.0))
	if area_open_m2 <= 0.0:
		return

	var hot_to_cold_sign: float = signf(temp_a - temp_b)
	if hot_to_cold_sign == 0.0:
		hot_to_cold_sign = signf(smoke_a - smoke_b)

	if hot_to_cold_sign == 0.0:
		return

	var source_id: int = op.a if hot_to_cold_sign > 0.0 else op.b
	var dest_id: int = op.b if hot_to_cold_sign > 0.0 else op.a

	var source_room: RoomModel = room_a if source_id == op.a else room_b
	var dest_room: RoomModel = room_b if dest_id == op.b else room_a

	var source_temp: float = temp_a if source_id == op.a else temp_b
	var dest_temp: float = temp_b if dest_id == op.b else temp_a
	var source_layer: float = layer_a if source_id == op.a else layer_b

	var temp_diff: float = maxf(0.0, source_temp - dest_temp)
	var layer_factor: float = 1.0

	if source_room != null:
		var layer_ratio: float = clampf(1.0 - (source_layer / maxf(0.1, source_room.height_m)), 0.0, 1.0)
		layer_factor += lerpf(-layer_relax_up, layer_relax_down, layer_ratio)

	var spill_kg_s: float = area_open_m2 * base_spill_kg_s_per_m2 * (1.0 + temp_diff * temp_push_factor) * layer_factor
	spill_kg_s = clampf(spill_kg_s, 0.0, max_spill_kg_s)

	var moved_kg: float = spill_kg_s * maxf(delta, 0.0)
	if moved_kg <= 0.0:
		return

	if source_room != null:
		var max_allowed: float = source_room.smoke_mass_kg * max_fraction_out_per_s * maxf(delta, 0.0)
		moved_kg = minf(moved_kg, max_allowed)

	if moved_kg <= 0.0:
		return

	_accum(d_smoke, source_id, -moved_kg)
	_accum(d_smoke, dest_id, moved_kg)

	var moved_energy_kj: float = 0.0
	if source_room != null:
		var delta_temp_c: float = maxf(0.0, source_temp - dest_temp)
		var energy_per_kg_kj: float = 1.0 * delta_temp_c
		moved_energy_kj = moved_kg * energy_per_kg_kj

	_accum(d_energy, source_id, -moved_energy_kj)
	_accum(d_energy, dest_id, moved_energy_kj)

	if source_room != null and dest_room != null:
		mix_o2_callable.call(source_id, source_room, dest_id, dest_room, moved_kg, d_o2)
	elif source_room != null and dest_id == outside_id:
		ventilate_o2_callable.call(source_id, source_room, op, moved_kg, d_o2)
	elif dest_room != null and source_id == outside_id:
		ventilate_o2_callable.call(dest_id, dest_room, op, moved_kg, d_o2)


func _accum(dict: Dictionary, key: int, value: float) -> void:
	dict[key] = dict.get(key, 0.0) + value
