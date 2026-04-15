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

var smoke_density_kg_m3: float = 0.9

# Transferencia / derrame
var base_spill_kg_s_per_m2: float = 0.18
var temp_push_factor: float = 0.008
var max_spill_kg_s: float = 0.9
var max_fraction_out_per_s: float = 0.025

# Suavizado de capa
var layer_relax_down: float = 0.10
var layer_relax_up: float = 0.008

# Histéresis simple para evitar parpadeo en el dintel
var spill_margin_m: float = 0.15


# ============================================================
# GENERACIÓN DE HUMO
# ------------------------------------------------------------
# Devuelve la masa generada en este step.
# No toca otras salas.
# ============================================================

func add_generated_smoke(room: RoomModel, dt: float) -> float:
	return maxf(0.0, room.smoke_prod_kg_s) * dt


# ============================================================
# RECÁLCULO DE CAPA DESDE MASA
# ------------------------------------------------------------
# La interfaz de capa se deduce del volumen real ocupado por los
# gases calientes. La masa de humo sigue actuando como suelo
# mínimo para no perder una capa ya contaminada.
# ============================================================


func recompute_layer_from_mass(room: RoomModel, dt: float) -> void:
	var floor_area_m2: float = maxf(0.01, room.floor_area_m2())
	var smoke_volume_m3: float = 0.0
	var hot_gas_volume_m3: float = 0.0

	if room.smoke_kg > 0.000001 and smoke_density_kg_m3 > 0.0:
		smoke_volume_m3 = room.smoke_kg / smoke_density_kg_m3
		var temp_expansion: float = (room.temp_upper_c + 273.15) / 293.15
		smoke_volume_m3 *= maxf(1.0, temp_expansion)

	if room.upper_gas_kg > 0.000001:
		var ambient_k: float = 293.15
		var upper_k: float = maxf(ambient_k, room.temp_upper_c + 273.15)
		var hot_gas_density_kg_m3: float = 1.2 * ambient_k / upper_k
		hot_gas_volume_m3 = room.upper_gas_kg / maxf(0.05, hot_gas_density_kg_m3)

	var effective_volume_m3: float = maxf(smoke_volume_m3, hot_gas_volume_m3)
	if effective_volume_m3 <= 0.000001:
		room.smoke_kg = 0.0
		room.h_layer_m = room.height_m
		return

	var smoke_depth_m: float = effective_volume_m3 / floor_area_m2

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
		room.h_layer_m = lerpf(
			room.h_layer_m,
			target_layer_m,
			clampf(layer_relax_up * dt, 0.0, 1.0)
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
	dt: float,
	effective_layer_m: float = -1.0
) -> float:
	var area_open: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_open <= 0.0:
		return 0.0

	var lintel_m: float = op.lintel_height_m()
	var layer_m: float = room.h_layer_m if effective_layer_m < 0.0 else effective_layer_m

	# Si la capa no ha llegado al dintel, no hay derrame de humo caliente.
	if layer_m >= (lintel_m - spill_margin_m):
		return 0.0

	if room.smoke_kg <= 0.000001:
		return 0.0

	var temp_delta: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)
	var temp_drive: float = 1.0 + temp_delta * temp_push_factor

	var spill_kg_s: float = minf(base_spill_kg_s_per_m2 * area_open * temp_drive, max_spill_kg_s)

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
	dt: float,
	layer_a_m: float = -1.0,
	layer_b_m: float = -1.0
) -> Array[Dictionary]:
	var transfers: Array[Dictionary] = []

	if op.open_fraction <= 0.0:
		return transfers

	var lintel_m: float = op.lintel_height_m()

	# --------------------------------------------------------
	# Exceso de humo por encima del dintel
	# --------------------------------------------------------
	# Si h_layer está por debajo del dintel, hay humo "empujando"
	# en la parte alta de la apertura.
	var effective_a_layer_m: float = room_a.h_layer_m if layer_a_m < 0.0 else layer_a_m
	var effective_b_layer_m: float = room_b.h_layer_m if layer_b_m < 0.0 else layer_b_m
	var a_excess_m: float = maxf(0.0, lintel_m - effective_a_layer_m)
	var b_excess_m: float = maxf(0.0, lintel_m - effective_b_layer_m)

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
			a_excess_m
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
			b_excess_m
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

	var opening_budget_kg: float = _compute_opening_mass_budget_kg(op, dt)
	if opening_budget_kg > 0.0 and total_requested_kg > opening_budget_kg:
		var scale: float = opening_budget_kg / total_requested_kg
		for transfer in transfers:
			transfer["kg"] = float(transfer.get("kg", 0.0)) * scale

	return transfers


func compute_room_transfer(
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel,
	dt: float,
	layer_a_m: float = -1.0,
	layer_b_m: float = -1.0
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
		dt,
		layer_a_m,
		layer_b_m
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

func _compute_opening_mass_budget_kg(op: OpeningModel, dt: float) -> float:
	var area_open: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_open <= 0.0:
		return 0.0

	var spill_kg_s: float = minf(base_spill_kg_s_per_m2 * area_open, max_spill_kg_s)
	return maxf(0.0, spill_kg_s * dt)

func _compute_transfer_mass_kg_continuous(
	source: RoomModel,
	target: RoomModel,
	op: OpeningModel,
	dt: float,
	source_excess_m: float
) -> float:
	var area_open: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_open <= 0.0:
		return 0.0

	# --------------------------------------------------------
	# Factor continuo según exceso sobre dintel
	# --------------------------------------------------------
	# 0.0 -> apenas llega al dintel
	# 1.0 -> exceso significativo
	var ref_depth_m: float = 0.50
	var spill_factor: float = clampf(source_excess_m / ref_depth_m, 0.0, 1.0)

	if spill_factor <= 0.0:
		return 0.0

	var temp_diff: float = maxf(0.0, source.temp_upper_c - target.temp_upper_c)
	var temp_drive: float = 1.0 + temp_diff * temp_push_factor

	var spill_kg_s: float = minf(
		base_spill_kg_s_per_m2 * area_open * temp_drive * spill_factor,
		max_spill_kg_s
	)

	var resistance: float = 1.0 + target.smoke_kg * 0.20
	var mass: float = (spill_kg_s * dt) / resistance
	mass = minf(mass, source.smoke_kg)
	mass = minf(mass, source.smoke_kg * max_fraction_out_per_s * dt)

	return maxf(0.0, mass)
