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
# La capa sale SIEMPRE de la masa real acumulada.
# ============================================================


func recompute_layer_from_mass(room: RoomModel, dt: float) -> void:
	if room.smoke_kg <= 0.000001:
		room.smoke_kg = 0.0
		room.h_layer_m = room.height_m
		return

	var smoke_volume_m3: float = 0.0
	if smoke_density_kg_m3 > 0.0:
		smoke_volume_m3 = room.smoke_kg / smoke_density_kg_m3

	var floor_area_m2: float = maxf(0.01, room.floor_area_m2())

	# Expansión térmica (ley de gases ideales): humo caliente ocupa más volumen
	# A 20°C → factor 1.0; a 300°C → factor ~1.96; a 600°C → factor ~2.98
	var temp_expansion: float = (room.temp_upper_c + 273.15) / 293.15
	var effective_volume_m3: float = smoke_volume_m3 * maxf(1.0, temp_expansion)

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

func compute_outside_vented_kg(room: RoomModel, op: OpeningModel, dt: float) -> float:
	var area_open: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_open <= 0.0:
		return 0.0

	var lintel_m: float = op.lintel_height_m()

	# Si la capa no ha llegado al dintel, no hay derrame de humo caliente.
	if room.h_layer_m >= (lintel_m - spill_margin_m):
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
# Devuelve un diccionario:
# {
#   "from": id_or_-1,
#   "to": id_or_-1,
#   "kg": mass_to_transfer
# }
#
# NO modifica ninguna sala.
# ============================================================

func compute_room_transfer(room_a: RoomModel, room_b: RoomModel, op: OpeningModel, dt: float) -> Dictionary:
	var result: Dictionary = {
		"from": -1,
		"to": -1,
		"kg": 0.0
	}

	if op.open_fraction <= 0.0:
		return result

	var lintel_m: float = op.lintel_height_m()

	# --------------------------------------------------------
	# Exceso de humo por encima del dintel
	# --------------------------------------------------------
	# Si h_layer está por debajo del dintel, hay humo "empujando"
	# en la parte alta de la apertura.
	var a_excess_m: float = maxf(0.0, lintel_m - room_a.h_layer_m)
	var b_excess_m: float = maxf(0.0, lintel_m - room_b.h_layer_m)

	# Si no hay exceso en ninguna sala, no hay transferencia.
	if a_excess_m <= 0.0 and b_excess_m <= 0.0:
		return result

	# Si no hay masa de humo, tampoco.
	if room_a.smoke_kg <= 0.000001 and room_b.smoke_kg <= 0.000001:
		return result

	var source: RoomModel = null
	var target: RoomModel = null
	var source_excess_m: float = 0.0

	# --------------------------------------------------------
	# Elegir dirección dominante
	# --------------------------------------------------------
	# 1) Mayor exceso sobre dintel
	# 2) Si están parecidos, mayor temperatura upper
	# 3) Si siguen parecidos, mayor masa de humo
	var excess_eps: float = 0.03
	var temp_eps: float = 5.0
	var smoke_eps: float = 0.1

	if a_excess_m > b_excess_m + excess_eps:
		source = room_a
		target = room_b
		source_excess_m = a_excess_m
	elif b_excess_m > a_excess_m + excess_eps:
		source = room_b
		target = room_a
		source_excess_m = b_excess_m
	else:
		if room_a.temp_upper_c > room_b.temp_upper_c + temp_eps:
			source = room_a
			target = room_b
			source_excess_m = a_excess_m
		elif room_b.temp_upper_c > room_a.temp_upper_c + temp_eps:
			source = room_b
			target = room_a
			source_excess_m = b_excess_m
		elif room_a.smoke_kg > room_b.smoke_kg + smoke_eps:
			source = room_a
			target = room_b
			source_excess_m = a_excess_m
		elif room_b.smoke_kg > room_a.smoke_kg + smoke_eps:
			source = room_b
			target = room_a
			source_excess_m = b_excess_m
		else:
			return result

	if source == null or target == null:
		return result

	var kg: float = _compute_transfer_mass_kg_continuous(source, target, op, dt, source_excess_m)
	if kg <= 0.0:
		return result

	result["from"] = source.id
	result["to"] = target.id
	result["kg"] = kg
	return result

# ============================================================
# HELPERS
# ============================================================

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