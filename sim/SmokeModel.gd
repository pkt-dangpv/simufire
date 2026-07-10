extends RefCounted

var smoke_density_kg_m3: float = 0.9

# Transporte de humo entre compartimentos
var base_spill_kg_s_per_m2: float = 0.18
var temp_push_factor: float = 0.008
var max_spill_kg_s: float = 0.9

# Muy importante: limita cuánto humo puede salir por segundo
var max_fraction_out_per_s: float = 0.025

# Relajación de la capa
# baja rápido cuando entra humo, sube muy lento cuando sale
var layer_relax_down: float = 0.18
var layer_relax_up: float = 0.015


func generate_fire_smoke(room: RoomModel, hrr_kw: float, delta: float, smoke_yield_kg_per_MJ: float) -> float:
	var e_MJ: float = (hrr_kw * delta) / 1000.0
	var dm_smoke: float = maxf(0.0, smoke_yield_kg_per_MJ * e_MJ)
	room.add_upper_smoke(dm_smoke)
	return dm_smoke


func update_layer_height(room: RoomModel) -> void:
	var smoke_volume_m3: float = room.smoke_mass_kg / maxf(0.05, smoke_density_kg_m3)
	var floor_area_m2: float = room.volume_m3 / maxf(0.1, room.height_m)
	var upper_height_target_m: float = smoke_volume_m3 / maxf(0.01, floor_area_m2)

	var target_layer_m: float = clampf(room.height_m - upper_height_target_m, 0.2, room.height_m)

	# Asimetría importante:
	# - si la capa baja: reacciona relativamente rápido
	# - si la capa sube: reacciona muy lento
	if target_layer_m < room.h_layer_m:
		room.h_layer_m = lerpf(room.h_layer_m, target_layer_m, layer_relax_down)
	else:
		room.h_layer_m = lerpf(room.h_layer_m, target_layer_m, layer_relax_up)

	room.h_layer_m = clampf(room.h_layer_m, 0.2, room.height_m)


func process_opening(
	op: OpeningModel,
	rooms: Dictionary,
	outside_temp_c: float,
	outside_id: int,
	delta: float,
	d_smoke: Dictionary,
	d_energy: Dictionary,
	d_o2: Dictionary,
	mix_o2_cb: Callable,
	vent_o2_cb: Callable
) -> void:
	var A: RoomModel = rooms.get(op.a)
	if A == null:
		return

	var B_is_outside: bool = (op.b == outside_id)

	var B: RoomModel = null
	if not B_is_outside:
		B = rooms.get(op.b)
		if B == null:
			return

	var lintel: float = op.lintel_height_m()

	# Parte de la abertura sumergida en la capa upper de A
	var upper_in_open_A: float = maxf(0.0, lintel - A.h_layer_m)
	var eff_h_A: float = clampf(upper_in_open_A, 0.0, op.height_m)
	var area_A: float = op.width_m * eff_h_A * op.open_fraction

	# Parte de la abertura sumergida en la capa upper de B
	var area_B: float = 0.0
	var Tu_B: float = outside_temp_c

	if not B_is_outside:
		var upper_in_open_B: float = maxf(0.0, lintel - B.h_layer_m)
		var eff_h_B: float = clampf(upper_in_open_B, 0.0, op.height_m)
		area_B = op.width_m * eff_h_B * op.open_fraction
		Tu_B = B.temp_upper_c

	if area_A <= 0.0 and area_B <= 0.0:
		return

	var Tu_A: float = A.temp_upper_c
	var dT: float = Tu_A - Tu_B

	var area_effective: float = maxf(area_A, area_B)
	var flow_kg_s: float = base_spill_kg_s_per_m2 * area_effective
	flow_kg_s *= (1.0 + temp_push_factor * absf(dT))
	flow_kg_s = minf(flow_kg_s, max_spill_kg_s)

	var dm: float = flow_kg_s * delta

	# Clave para que no "se vacíe" la habitación:
	# solo puede salir una fracción pequeña del humo por segundo
	var max_fraction_out: float = clampf(max_fraction_out_per_s * delta, 0.0, 0.03)

	if dT >= 0.0:
		# A -> B / exterior
		var take: float = minf(dm, A.smoke_mass_kg * max_fraction_out)

		_accum(d_smoke, op.a, -take)

		if not B_is_outside:
			_accum(d_smoke, op.b, +take)

		# energía asociada al humo desplazado
		var dE_kJ: float = take * 1.5 * maxf(0.0, dT)
		_accum(d_energy, op.a, -dE_kJ)

		if not B_is_outside:
			_accum(d_energy, op.b, +dE_kJ)

		if not B_is_outside:
			mix_o2_cb.call(op.a, A, op.b, B, dm, d_o2)
		else:
			vent_o2_cb.call(op.a, A, op, dm, d_o2)

	else:
		# B -> A
		if B_is_outside:
			return

		var take2: float = minf(dm, B.smoke_mass_kg * max_fraction_out)

		_accum(d_smoke, op.b, -take2)
		_accum(d_smoke, op.a, +take2)

		var dE_kJ2: float = take2 * 1.5 * maxf(0.0, -dT)
		_accum(d_energy, op.b, -dE_kJ2)
		_accum(d_energy, op.a, +dE_kJ2)

		mix_o2_cb.call(op.b, B, op.a, A, dm, d_o2)


func _accum(dict: Dictionary, key: int, value: float) -> void:
	dict[key] = dict.get(key, 0.0) + value
