extends RefCounted
class_name SmokeModel

# ============================================================
# SMOKE MODEL
# ------------------------------------------------------------
# Modelo de humo con cálculo por snapshot:
# - calcula masa generada
# - calcula masa que puede salir al exterior
# - calcula masa que puede pasar entre salas
# - NO aplica cambios directamente entre salas
#
# La aplicación real de deltas la hace SimulationEngine.
# ============================================================

var smoke_density_kg_m3: float = 0.18
var smoke_temp_expansion_upper_weight: float = 0.45
var smoke_temp_expansion_cap_c: float = 400.0

# Transferencia / derrame
var base_spill_kg_s_per_m2: float = 0.18
var temp_push_factor: float = 0.008
var max_spill_kg_s: float = 0.9
var max_fraction_out_per_s: float = 0.025
var target_smoke_resistance_coeff: float = 0.45
var target_layer_block_start_m: float = 1.10
var target_layer_block_full_m: float = 0.35
var interior_spill_start_layer_m: float = 2.0
var interior_spill_full_layer_m: float = 1.2
var pressure_spill_min_delta_pa: float = 0.5
var pressure_spill_ref_delta_pa: float = 8.0
var pressure_spill_max_multiplier: float = 2.5

# Suavizado de capa
var layer_relax_down: float = 0.10
var layer_relax_up: float = 0.008
var layer_recovery_gap_start_m: float = 0.20
var layer_recovery_gap_full_m: float = 1.00
var layer_recovery_boost_max: float = 6.0
var layer_recovery_low_hrr_threshold_kw: float = 120.0
var layer_recovery_low_hrr_boost: float = 1.6

# Histéresis simple para evitar parpadeo en el dintel
var spill_margin_m: float = 0.15
var thermal_smoke_bridge_min_kg: float = 0.03
var thermal_smoke_bridge_gap_start_m: float = 0.12
var thermal_smoke_bridge_gap_full_m: float = 0.90
var thermal_smoke_bridge_ref_kg_m3: float = 0.015
var thermal_smoke_bridge_max_weight: float = 0.28


# ============================================================
# GENERACIÓN DE HUMO
# ------------------------------------------------------------
# Devuelve la masa generada en este step.
# No toca otras salas.
# ============================================================

func add_generated_smoke(room: RoomModel, dt: float) -> float:
	return maxf(0.0, room.smoke_prod_kg_s) * dt


func estimate_smoke_layer_height_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	if room.smoke_kg <= 0.000001 or smoke_density_kg_m3 <= 0.0:
		return room.height_m

	var floor_area_m2: float = maxf(0.01, room.floor_area_m2())
	var smoke_volume_m3: float = room.smoke_kg / smoke_density_kg_m3
	var temp_expansion: float = _compute_smoke_temp_expansion(room)
	smoke_volume_m3 *= maxf(1.0, temp_expansion)

	var smoke_depth_m: float = smoke_volume_m3 / floor_area_m2
	return clampf(room.height_m - smoke_depth_m, 0.0, room.height_m)


func get_visible_smoke_layer_height_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	if room.h_layer_m < 0.0 or room.h_layer_m > room.height_m:
		return estimate_smoke_layer_height_m(room)

	return clampf(room.h_layer_m, 0.0, room.height_m)


func get_effective_smoke_spill_layer_height_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var visible_layer_m: float = get_visible_smoke_layer_height_m(room)
	var thermal_layer_m: float = clampf(room.thermal_layer_m, 0.0, room.height_m)
	if thermal_layer_m >= visible_layer_m:
		return visible_layer_m

	if room.smoke_kg <= thermal_smoke_bridge_min_kg:
		return visible_layer_m

	var upper_depth_m: float = maxf(0.05, room.height_m - thermal_layer_m)
	var upper_volume_m3: float = maxf(0.10, room.floor_area_m2() * upper_depth_m)
	var upper_smoke_concentration_kg_m3: float = room.smoke_kg / upper_volume_m3
	var concentration_factor: float = clampf(
		upper_smoke_concentration_kg_m3 / maxf(0.0001, thermal_smoke_bridge_ref_kg_m3),
		0.0,
		1.0
	)
	var gap_factor: float = clampf(
		inverse_lerp(
			thermal_smoke_bridge_gap_start_m,
			thermal_smoke_bridge_gap_full_m,
			visible_layer_m - thermal_layer_m
		),
		0.0,
		1.0
	)
	var bridge_weight: float = thermal_smoke_bridge_max_weight * concentration_factor * gap_factor
	return lerpf(visible_layer_m, thermal_layer_m, bridge_weight)


func get_spill_layer_height_m(room: RoomModel) -> float:
	return get_effective_smoke_spill_layer_height_m(room)


# ============================================================
# RECÁLCULO DE CAPA DESDE MASA
# ------------------------------------------------------------
# La interfaz visible de humo se deduce solo de la masa de humo.
# La capa térmica se calcula aparte en SimulationEngine.
# ============================================================


func recompute_layer_from_mass(room: RoomModel, dt: float) -> void:
	var floor_area_m2: float = maxf(0.01, room.floor_area_m2())
	var smoke_volume_m3: float = 0.0

	if room.smoke_kg > 0.000001 and smoke_density_kg_m3 > 0.0:
		smoke_volume_m3 = room.smoke_kg / smoke_density_kg_m3
		var temp_expansion: float = _compute_smoke_temp_expansion(room)
		smoke_volume_m3 *= maxf(1.0, temp_expansion)

	if smoke_volume_m3 <= 0.000001:
		room.smoke_kg = 0.0
		room.h_layer_m = room.height_m
		return

	var smoke_depth_m: float = smoke_volume_m3 / floor_area_m2

	var target_layer_m: float = clampf(
		room.height_m - smoke_depth_m,
		0.0,
		room.height_m
	)

	if target_layer_m < room.h_layer_m:
		room.h_layer_m = lerpf(
			room.h_layer_m,
			target_layer_m,
			clampf(layer_relax_down * dt * 2.0, 0.0, 1.0)
		)
	else:
		var relax_up_rate: float = layer_relax_up
		var recovery_gap_m: float = target_layer_m - room.h_layer_m
		if recovery_gap_m > layer_recovery_gap_start_m:
			var gap_factor: float = clampf(
				inverse_lerp(
					layer_recovery_gap_start_m,
					maxf(layer_recovery_gap_start_m + 0.05, layer_recovery_gap_full_m),
					recovery_gap_m
				),
				0.0,
				1.0
			)
			relax_up_rate *= lerpf(1.0, maxf(1.0, layer_recovery_boost_max), gap_factor)

		if room.hrr_kw <= layer_recovery_low_hrr_threshold_kw:
			relax_up_rate *= maxf(1.0, layer_recovery_low_hrr_boost)

		room.h_layer_m = lerpf(
			room.h_layer_m,
			target_layer_m,
			clampf(relax_up_rate * dt, 0.0, 1.0)
		)


# ============================================================
# HUMO QUE SALE AL EXTERIOR
# ------------------------------------------------------------
# Calcula cuánto humo saldría fuera usando el estado actual
# de la sala, pero NO modifica la sala.
# ============================================================

func compute_outside_vented_kg(
	room: RoomModel,
	op: OpeningModel,
	dt: float
) -> float:
	var area_open: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_open <= 0.0:
		return 0.0

	var lintel_m: float = op.lintel_height_m()
	var layer_m: float = get_effective_smoke_spill_layer_height_m(room)

	# Para flujo por puertas/ventanas debemos usar la interfaz de la capa
	# superior (zona caliente), no solo la visibilidad. CFAST segmenta el
	# flujo por la interfaz de zona y el plano neutro, y no por un umbral
	# óptico de humo.
	if layer_m >= (lintel_m - spill_margin_m):
		return 0.0

	if room.smoke_kg <= 0.000001:
		return 0.0

	var temp_delta: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)
	var temp_drive: float = 1.0 + temp_delta * temp_push_factor
	var pressure_drive: float = _compute_pressure_spill_multiplier(room)

	var spill_kg_s: float = minf(
		base_spill_kg_s_per_m2 * area_open * temp_drive * pressure_drive,
		max_spill_kg_s
	)

	var mass_out: float = spill_kg_s * dt
	mass_out = minf(mass_out, room.smoke_kg)
	mass_out = minf(mass_out, room.smoke_kg * max_fraction_out_per_s * dt)

	return maxf(0.0, mass_out)


# ============================================================
# TRANSFERENCIA ENTRE SALAS
# ------------------------------------------------------------
# Devuelve una lista de tránsitos de humo en la franja superior
# de la abertura. Si ambas capas invaden el dintel, la misma
# puerta puede derramar humo en ambos sentidos dentro del mismo
# step, con un presupuesto total compartido por la abertura.
#
# Cada tránsito tiene la forma:
# {
#   "from": id_or_-1,
#   "to": id_or_-1,
#   "kg": mass_to_transfer
# }
#
# NO modifica ninguna sala.
# ============================================================

func compute_room_transfers(
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel,
	dt: float
) -> Array[Dictionary]:
	var transfers: Array[Dictionary] = []

	if op.open_fraction <= 0.0:
		return transfers

	var lintel_m: float = op.lintel_height_m()

	# --------------------------------------------------------
	# Exceso de humo por encima del dintel
	# --------------------------------------------------------
	# El derrame de HUMO arranca cuando la interfaz visible desciende
	# hasta el dintel de la puerta.
	var smoke_a_layer_m: float = get_effective_smoke_spill_layer_height_m(room_a)
	var smoke_b_layer_m: float = get_effective_smoke_spill_layer_height_m(room_b)
	var a_trigger_layer_m: float = _interior_spill_trigger_layer_m(room_a, lintel_m)
	var b_trigger_layer_m: float = _interior_spill_trigger_layer_m(room_b, lintel_m)
	var a_excess_m: float = maxf(0.0, a_trigger_layer_m - smoke_a_layer_m)
	var b_excess_m: float = maxf(0.0, b_trigger_layer_m - smoke_b_layer_m)

	# Si no hay exceso en ninguna sala, no hay transferencia.
	if a_excess_m <= 0.0 and b_excess_m <= 0.0:
		return transfers

	# Si no hay masa de humo, tampoco.
	if room_a.smoke_kg <= 0.000001 and room_b.smoke_kg <= 0.000001:
		return transfers

	if a_excess_m > 0.0 and room_a.smoke_kg > 0.000001:
		var kg_a_to_b: float = _compute_transfer_mass_kg_continuous(
			room_a,
			room_b,
			op,
			dt,
			a_excess_m,
			a_trigger_layer_m
		)
		if kg_a_to_b > 0.0:
			transfers.append({
				"from": room_a.id,
				"to": room_b.id,
				"kg": kg_a_to_b
			})

	if b_excess_m > 0.0 and room_b.smoke_kg > 0.000001:
		var kg_b_to_a: float = _compute_transfer_mass_kg_continuous(
			room_b,
			room_a,
			op,
			dt,
			b_excess_m,
			b_trigger_layer_m
		)
		if kg_b_to_a > 0.0:
			transfers.append({
				"from": room_b.id,
				"to": room_a.id,
				"kg": kg_b_to_a
			})

	if transfers.size() <= 1:
		return transfers

	var total_requested_kg: float = 0.0
	for transfer in transfers:
		total_requested_kg += float(transfer.get("kg", 0.0))

	var opening_budget_kg: float = _compute_opening_mass_budget_kg(op, dt, room_a, room_b)
	if opening_budget_kg > 0.0 and total_requested_kg > opening_budget_kg:
		var scale: float = opening_budget_kg / total_requested_kg
		for transfer in transfers:
			transfer["kg"] = float(transfer.get("kg", 0.0)) * scale

	return transfers


# Wrapper heredado para compatibilidad con llamadas antiguas que solo
# esperaban un traspaso dominante por abertura.
func compute_room_transfer(
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel,
	dt: float
) -> Dictionary:
	var result: Dictionary = {
		"from": -1,
		"to": -1,
		"kg": 0.0
	}

	var transfers: Array[Dictionary] = compute_room_transfers(
		room_a,
		room_b,
		op,
		dt
	)
	if transfers.is_empty():
		return result

	var strongest: Dictionary = transfers[0]
	for transfer in transfers:
		if float(transfer.get("kg", 0.0)) > float(strongest.get("kg", 0.0)):
			strongest = transfer

	result["from"] = int(strongest.get("from", -1))
	result["to"] = int(strongest.get("to", -1))
	result["kg"] = float(strongest.get("kg", 0.0))
	return result

# ============================================================
# HELPERS
# ============================================================

func _compute_opening_mass_budget_kg(
	op: OpeningModel,
	dt: float,
	room_a: RoomModel = null,
	room_b: RoomModel = null
) -> float:
	var area_open: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_open <= 0.0:
		return 0.0

	var pressure_drive: float = maxf(
		_compute_pressure_spill_multiplier(room_a, room_b),
		_compute_pressure_spill_multiplier(room_b, room_a)
	)
	var spill_kg_s: float = minf(base_spill_kg_s_per_m2 * area_open * pressure_drive, max_spill_kg_s)
	return maxf(0.0, spill_kg_s * dt)

func _compute_transfer_mass_kg_continuous(
	source: RoomModel,
	target: RoomModel,
	op: OpeningModel,
	dt: float,
	source_excess_m: float,
	trigger_layer_m: float
) -> float:
	var area_open: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_open <= 0.0:
		return 0.0

	# --------------------------------------------------------
	# Factor continuo según exceso sobre dintel
	# --------------------------------------------------------
	# 0.0 -> apenas llega al dintel
	# 1.0 -> exceso significativo
	var full_layer_m: float = _interior_spill_full_layer_m(source, trigger_layer_m)
	var ref_depth_m: float = maxf(0.05, trigger_layer_m - full_layer_m)
	var spill_factor: float = clampf(source_excess_m / ref_depth_m, 0.0, 1.0)

	if spill_factor <= 0.0:
		return 0.0

	var temp_diff: float = maxf(0.0, source.temp_upper_c - target.temp_upper_c)
	var temp_drive: float = 1.0 + temp_diff * temp_push_factor
	var pressure_drive: float = _compute_pressure_spill_multiplier(source, target)

	# Si la sala destino ya tiene la capa muy baja, la abertura deja de aceptar humo
	# con la misma facilidad y el pasillo deja de actuar como sumidero infinito.
	var target_layer_factor: float = 1.0
	var target_smoke_layer_m: float = get_effective_smoke_spill_layer_height_m(target)
	if target_smoke_layer_m <= target_layer_block_start_m:
		target_layer_factor = inverse_lerp(
			target_layer_block_full_m,
			target_layer_block_start_m,
			clampf(target_smoke_layer_m, target_layer_block_full_m, target_layer_block_start_m)
		)
		target_layer_factor = clampf(target_layer_factor, 0.0, 1.0)
	if target_layer_factor <= 0.0:
		return 0.0

	var spill_kg_s: float = minf(
		base_spill_kg_s_per_m2 * area_open * temp_drive * pressure_drive * spill_factor * target_layer_factor,
		max_spill_kg_s
	)

	var resistance: float = 1.0 + target.smoke_kg * target_smoke_resistance_coeff
	var mass: float = (spill_kg_s * dt) / resistance
	mass = minf(mass, source.smoke_kg)
	mass = minf(mass, source.smoke_kg * max_fraction_out_per_s * dt)

	return maxf(0.0, mass)


func _interior_spill_trigger_layer_m(room: RoomModel, lintel_m: float) -> float:
	if room == null:
		return lintel_m

	return minf(lintel_m, clampf(interior_spill_start_layer_m, 0.0, room.height_m))


func _interior_spill_full_layer_m(room: RoomModel, trigger_layer_m: float) -> float:
	if room == null:
		return maxf(0.0, trigger_layer_m - 0.5)

	return minf(trigger_layer_m, clampf(interior_spill_full_layer_m, 0.0, room.height_m))


func _compute_pressure_spill_multiplier(source: RoomModel, target: RoomModel = null) -> float:
	if source == null:
		return 1.0

	var target_pressure_pa: float = target.overpressure_pa if target != null else 0.0
	var pressure_delta_pa: float = maxf(0.0, source.overpressure_pa - target_pressure_pa)
	if pressure_delta_pa <= pressure_spill_min_delta_pa:
		return 1.0

	var t: float = clampf(
		(pressure_delta_pa - pressure_spill_min_delta_pa) / maxf(
			0.1,
			pressure_spill_ref_delta_pa - pressure_spill_min_delta_pa
		),
		0.0,
		1.0
	)
	return lerpf(1.0, pressure_spill_max_multiplier, t)


func _compute_smoke_temp_expansion(room: RoomModel) -> float:
	if room == null:
		return 1.0

	var ambient_k: float = 293.15
	var effective_smoke_temp_c: float = lerpf(
		room.temp_lower_c,
		room.temp_upper_c,
		clampf(smoke_temp_expansion_upper_weight, 0.0, 1.0)
	)
	if smoke_temp_expansion_cap_c > 0.0:
		effective_smoke_temp_c = minf(effective_smoke_temp_c, smoke_temp_expansion_cap_c)

	return (effective_smoke_temp_c + 273.15) / ambient_k
