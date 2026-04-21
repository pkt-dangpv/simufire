extends RefCounted
class_name FireSpreadSystem

# ============================================================
# FIRE SPREAD SYSTEM
# ------------------------------------------------------------
# Responsabilidad:
# - evaluar condiciones de propagación del incendio entre salas
# - gestionar la exposición acumulada para ignición por calor
# - disparar la ignición en salas adyacentes cuando se cumplen
#   los criterios (temperatura, capa, humo, HRR fuente)
# ============================================================

# Dependencias externas
var _building: BuildingModel
var _smoke_model: SmokeModel

# Parámetros de propagación
var fire_spread_enabled: bool = true
var fire_spread_ignition_temp_c: float = 340.0
var fire_spread_max_layer_m: float = 1.6
var fire_spread_min_smoke_kg: float = 0.08
var fire_spread_min_source_hrr_kw: float = 180.0
var fire_spread_required_exposure_s: float = 35.0
var fire_spread_exposure_decay_s: float = 12.0


func set_references(building: BuildingModel, smoke_model: SmokeModel) -> void:
	_building = building
	_smoke_model = smoke_model


func configure(settings: Dictionary) -> void:
	fire_spread_enabled = bool(settings.get("fire_spread_enabled", fire_spread_enabled))
	fire_spread_ignition_temp_c = float(settings.get("fire_spread_ignition_temp_c", fire_spread_ignition_temp_c))
	fire_spread_max_layer_m = float(settings.get("fire_spread_max_layer_m", fire_spread_max_layer_m))
	fire_spread_min_smoke_kg = float(settings.get("fire_spread_min_smoke_kg", fire_spread_min_smoke_kg))
	fire_spread_min_source_hrr_kw = float(settings.get("fire_spread_min_source_hrr_kw", fire_spread_min_source_hrr_kw))
	fire_spread_required_exposure_s = float(settings.get("fire_spread_required_exposure_s", fire_spread_required_exposure_s))
	fire_spread_exposure_decay_s = float(settings.get("fire_spread_exposure_decay_s", fire_spread_exposure_decay_s))


# ============================================================
# STEP PRINCIPAL
# ============================================================

func step(dt: float, ignite_callable: Callable) -> void:
	if not fire_spread_enabled:
		return

	for op in _building.get_openings():
		if op.open_fraction <= 0.0:
			continue

		if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
			continue

		var room_a: RoomModel = _building.get_room(op.a)
		var room_b: RoomModel = _building.get_room(op.b)

		if room_a == null or room_b == null:
			continue

		# Propagación A → B
		if room_a.fire != null and room_b.fire == null:
			if _update_fire_spread_exposure(room_a, room_b, dt):
				ignite_callable.call(op.b)
				print("[FireSpread] Ignición por calor: Room %d → Room %d (%.0f°C, %.1fs)" % [op.a, op.b, room_b.temp_upper_c, room_b.fire_spread_exposure_s])

		# Propagación B → A
		if room_b.fire != null and room_a.fire == null:
			if _update_fire_spread_exposure(room_b, room_a, dt):
				ignite_callable.call(op.a)
				print("[FireSpread] Ignición por calor: Room %d → Room %d (%.0f°C, %.1fs)" % [op.b, op.a, room_a.temp_upper_c, room_a.fire_spread_exposure_s])


func _update_fire_spread_exposure(source: RoomModel, target: RoomModel, dt: float) -> bool:
	if source == null or target == null:
		return false

	if source.fire == null or target.fire != null:
		target.fire_spread_exposure_s = 0.0
		return false

	var source_hot_enough: bool = source.hrr_kw >= fire_spread_min_source_hrr_kw
	var target_hot_enough: bool = target.temp_upper_c >= fire_spread_ignition_temp_c
	var target_layer_low_enough: bool = _smoke_model.get_visible_smoke_layer_height_m(target) <= fire_spread_max_layer_m
	var target_smoky_enough: bool = target.smoke_kg >= fire_spread_min_smoke_kg

	if source_hot_enough and target_hot_enough and target_layer_low_enough and target_smoky_enough:
		target.fire_spread_exposure_s += dt
	else:
		var decay_step: float = dt * fire_spread_required_exposure_s / maxf(1.0, fire_spread_exposure_decay_s)
		target.fire_spread_exposure_s = maxf(0.0, target.fire_spread_exposure_s - decay_step)

	return target.fire_spread_exposure_s >= fire_spread_required_exposure_s
