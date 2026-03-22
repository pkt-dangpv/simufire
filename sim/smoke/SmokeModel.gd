extends RefCounted
class_name SmokeModel

# ============================================================
# SMOKE MODEL
# ------------------------------------------------------------
# Modelo de humo basado en conservación de masa:
#
# 1) El fuego genera masa de humo en la sala.
# 2) Esa masa puede transferirse a otras salas o salir al exterior.
# 3) La altura de capa se recalcula SIEMPRE desde la masa real.
#
# IMPORTANTE:
# - h_layer_m no debe cambiar "por magia".
# - La capa solo puede bajar si existe masa de humo detrás.
# ============================================================

# Densidad efectiva del humo (simplificada)
var smoke_density_kg_m3: float = 0.9

# Coeficientes de derrame / transferencia
var base_spill_kg_s_per_m2: float = 0.18
var temp_push_factor: float = 0.008
var max_spill_kg_s: float = 0.9
var max_fraction_out_per_s: float = 0.025

# Suavizado de la capa
var layer_relax_down: float = 0.1
var layer_relax_up: float = 0.008


# ============================================================
# 1) GENERACIÓN DE HUMO
# ------------------------------------------------------------
# Añade masa de humo a la sala según smoke_prod_kg_s.
# Devuelve la masa generada durante este step para poder
# contabilizarla en el SimulationEngine.
# ============================================================

func add_generated_smoke(room: RoomModel, dt: float) -> float:
	var generated_kg: float = maxf(0.0, room.smoke_prod_kg_s) * dt
	room.smoke_kg += generated_kg
	return generated_kg


# ============================================================
# 2) RECÁLCULO DE CAPA DESDE MASA
# ------------------------------------------------------------
# Convierte smoke_kg -> volumen -> profundidad de humo -> capa limpia.
#
# La capa se recalcula SIEMPRE desde la masa actual.
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
	var smoke_depth_m: float = smoke_volume_m3 / floor_area_m2

	var target_layer_m: float = room.height_m - smoke_depth_m
	target_layer_m = clampf(target_layer_m, 0.0, room.height_m)

	# La capa baja más rápido de lo que sube.
	if target_layer_m < room.h_layer_m:
		room.h_layer_m = lerpf(
			room.h_layer_m,
			target_layer_m,
			clampf(layer_relax_down * dt, 0.0, 1.0)
		)
	else:
		room.h_layer_m = lerpf(
			room.h_layer_m,
			target_layer_m,
			clampf(layer_relax_up * dt, 0.0, 1.0)
		)


# ============================================================
# 3) TRANSFERENCIA POR APERTURAS
# ------------------------------------------------------------
# Devuelve la masa total evacuada al exterior por esa apertura.
#
# Entre salas:
# - conserva masa
# Exterior:
# - la masa sale del sistema y se devuelve para contabilizarla
#   en smoke_vented_total_kg
# ============================================================

func transfer_between_opening(building: BuildingModel, op: OpeningModel, dt: float) -> float:
	if op.open_fraction <= 0.0:
		return 0.0

	var room_a: RoomModel = null
	var room_b: RoomModel = null

	if op.a != BuildingModel.OUTSIDE_ID:
		room_a = building.get_room(op.a)

	if op.b != BuildingModel.OUTSIDE_ID:
		room_b = building.get_room(op.b)

	# --------------------------------------------------------
	# Caso sala -> exterior
	# --------------------------------------------------------
	if room_a != null and op.b == BuildingModel.OUTSIDE_ID:
		return _transfer_outside(room_a, op, dt)

	if room_b != null and op.a == BuildingModel.OUTSIDE_ID:
		return _transfer_outside(room_b, op, dt)

	# --------------------------------------------------------
	# Caso entre salas
	# --------------------------------------------------------
	if room_a == null or room_b == null:
		return 0.0

	_transfer_between_rooms(room_a, room_b, op, dt)
	return 0.0


# ============================================================
# EXTERIOR
# ------------------------------------------------------------
# Solo sale humo si la capa ha alcanzado el dintel.
# Devuelve la masa evacuada fuera del sistema.
# ============================================================

func _transfer_outside(room: RoomModel, op: OpeningModel, dt: float) -> float:
	var area_open: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_open <= 0.0:
		return 0.0

	var lintel_m: float = op.lintel_height_m()

	# Si la capa aún no ha alcanzado la apertura, no sale humo caliente.
	if room.h_layer_m >= lintel_m or room.smoke_kg <= 0.000001:
		return 0.0

	var temp_delta: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)
	var temp_drive: float = 1.0 + temp_delta * temp_push_factor

	var max_by_area: float = base_spill_kg_s_per_m2 * area_open * temp_drive
	var spill_kg_s: float = minf(max_by_area, max_spill_kg_s)

	var mass_out: float = spill_kg_s * dt
	mass_out = minf(mass_out, room.smoke_kg)
	mass_out = minf(mass_out, room.smoke_kg * max_fraction_out_per_s * dt)

	if mass_out <= 0.0:
		return 0.0

	room.smoke_kg -= mass_out
	return mass_out


# ============================================================
# ENTRE SALAS
# ------------------------------------------------------------
# Conserva masa estrictamente:
# - lo que sale de source entra en target
#
# Regla simplificada:
# - una sala solo desborda si su capa ha bajado por debajo del dintel
# - si ambas desbordan, se mezclan parcialmente
# ============================================================

func _transfer_between_rooms(room_a: RoomModel, room_b: RoomModel, op: OpeningModel, dt: float) -> void:
	if op.open_fraction <= 0.0:
		return

	var lintel: float = op.lintel_height_m()

	var spill_margin: float = 0.08

	var a_spilling: bool = room_a.h_layer_m < (lintel - spill_margin) and room_a.smoke_kg > 0.000001
	var b_spilling: bool = room_b.h_layer_m < (lintel - spill_margin) and room_b.smoke_kg > 0.000001

	# Si ninguna desborda, no hay transferencia.
	if not a_spilling and not b_spilling:
		return

	# --------------------------------------------------------
	# CASO 1: Solo una sala desborda
	# --------------------------------------------------------
	if a_spilling and not b_spilling:
		var flow_ab: float = _compute_flow(room_a, room_b, op)
		_transfer_mass(room_a, room_b, flow_ab, dt)
		return

	if b_spilling and not a_spilling:
		var flow_ba: float = _compute_flow(room_b, room_a, op)
		_transfer_mass(room_b, room_a, flow_ba, dt)
		return

	# --------------------------------------------------------
	# CASO 2: Ambas desbordan
	# --------------------------------------------------------
	# Mezcla parcial conservando masa total.
	var total_smoke: float = room_a.smoke_kg + room_b.smoke_kg
	var avg_smoke: float = total_smoke * 0.5
	var mix_speed: float = clampf(0.05 * dt, 0.0, 1.0)

	room_a.smoke_kg = lerpf(room_a.smoke_kg, avg_smoke, mix_speed)
	room_b.smoke_kg = total_smoke - room_a.smoke_kg


# ============================================================
# HELPERS
# ============================================================

func _compute_flow(source: RoomModel, target: RoomModel, op: OpeningModel) -> float:
	var area: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)

	var temp_diff: float = maxf(0.0, source.temp_upper_c - target.temp_upper_c)
	var drive: float = 1.0 + temp_diff * temp_push_factor

	return minf(base_spill_kg_s_per_m2 * area * drive, max_spill_kg_s)


func _transfer_mass(source: RoomModel, target: RoomModel, flow_kg_s: float, dt: float) -> void:
	var mass: float = flow_kg_s * dt

	mass = minf(mass, source.smoke_kg)
	mass = minf(mass, source.smoke_kg * max_fraction_out_per_s * dt)

	if mass <= 0.0:
		return

	source.smoke_kg -= mass
	target.smoke_kg += mass