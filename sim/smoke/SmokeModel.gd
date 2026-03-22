extends RefCounted
class_name SmokeModel

# ============================================================
# SMOKE MODEL
# ------------------------------------------------------------
# Modelo simple de:
# - producción de humo en sala
# - descenso / relajación de capa
# - transferencia entre salas por aperturas
# ============================================================

var smoke_density_kg_m3: float = 0.9

# Producción / spill
var base_spill_kg_s_per_m2: float = 0.18
var temp_push_factor: float = 0.008
var max_spill_kg_s: float = 0.9
var max_fraction_out_per_s: float = 0.025

# Relajación de capa
var layer_relax_down: float = 0.18
var layer_relax_up: float = 0.015

# ============================================================
# ACTUALIZAR HUMO EN UNA SALA
# ============================================================

func step_room_smoke(room: RoomModel, dt: float) -> void:
	# Añadir humo generado por el fuego
	room.smoke_kg += room.smoke_prod_kg_s * dt

	# Convertir masa de humo en volumen aproximado
	var smoke_volume_m3: float = 0.0
	if smoke_density_kg_m3 > 0.0:
		smoke_volume_m3 = room.smoke_kg / smoke_density_kg_m3

	# Área de planta de la habitación
	var floor_area_m2: float = maxf(0.01, room.floor_area_m2())

	# Altura ocupada por humo
	var smoke_depth_m: float = smoke_volume_m3 / floor_area_m2

	# Altura objetivo de la capa limpia
	var target_layer_m: float = room.height_m - smoke_depth_m
	target_layer_m = clampf(target_layer_m, 0.0, room.height_m)

	# Relajación: baja rápido, sube más lento
	if target_layer_m < room.h_layer_m:
		room.h_layer_m = lerpf(room.h_layer_m, target_layer_m, clampf(layer_relax_down * dt, 0.0, 1.0))
	else:
		room.h_layer_m = lerpf(room.h_layer_m, target_layer_m, clampf(layer_relax_up * dt, 0.0, 1.0))

# ============================================================
# TRANSFERENCIA ENTRE SALAS / EXTERIOR
# ============================================================

func transfer_between_opening(building: BuildingModel, op: OpeningModel, dt: float) -> void:
	if op.open_fraction <= 0.0:
		return

	var room_a: RoomModel = null
	var room_b: RoomModel = null

	if op.a != BuildingModel.OUTSIDE_ID:
		room_a = building.get_room(op.a)

	if op.b != BuildingModel.OUTSIDE_ID:
		room_b = building.get_room(op.b)

	# Caso sala -> exterior
	if room_a != null and op.b == BuildingModel.OUTSIDE_ID:
		_transfer_outside(room_a, op, dt)
		return

	if room_b != null and op.a == BuildingModel.OUTSIDE_ID:
		_transfer_outside(room_b, op, dt)
		return

	# Caso entre salas
	if room_a == null or room_b == null:
		return

	_transfer_between_rooms(room_a, room_b, op, dt)

# ============================================================
# HELPERS INTERNOS
# ============================================================

func _transfer_outside(room: RoomModel, op: OpeningModel, dt: float) -> void:
	var area_open: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_open <= 0.0:
		return

	var temp_delta: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)
	var temp_drive: float = 1.0 + temp_delta * temp_push_factor

	var max_by_area: float = base_spill_kg_s_per_m2 * area_open * temp_drive
	var spill_kg_s: float = minf(max_by_area, max_spill_kg_s)

	var mass_out: float = spill_kg_s * dt
	var max_fraction_out: float = room.smoke_kg * max_fraction_out_per_s * dt

	mass_out = minf(mass_out, max_fraction_out)
	mass_out = minf(mass_out, room.smoke_kg)

	room.smoke_kg -= mass_out

func _transfer_between_rooms(room_a: RoomModel, room_b: RoomModel, op: OpeningModel, dt: float) -> void:
	var area_open: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_open <= 0.0:
		return

	# Impulso simple por diferencia térmica upper layer
	var temp_diff: float = room_a.temp_upper_c - room_b.temp_upper_c

	# Dirección del flujo
	var source: RoomModel = room_a
	var target: RoomModel = room_b

	if temp_diff < 0.0:
		source = room_b
		target = room_a
		temp_diff = -temp_diff

	var temp_drive: float = 1.0 + temp_diff * temp_push_factor
	var spill_kg_s: float = minf(base_spill_kg_s_per_m2 * area_open * temp_drive, max_spill_kg_s)

	var mass_transfer: float = spill_kg_s * dt
	mass_transfer = minf(mass_transfer, source.smoke_kg)
	mass_transfer = minf(mass_transfer, source.smoke_kg * max_fraction_out_per_s * dt)

	source.smoke_kg -= mass_transfer
	target.smoke_kg += mass_transfer