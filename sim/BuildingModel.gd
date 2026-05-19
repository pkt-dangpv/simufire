extends Node
class_name BuildingModel

const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd")

# ============================================================
# BUILDING MODEL
# ------------------------------------------------------------
# Responsabilidad:
# - almacenar estructura del edificio
# - almacenar condiciones exteriores
# - cargar habitaciones y aperturas desde plantilla
# - ofrecer helpers geométricos / ventilación
#
# NO debe:
# - simular el incendio
# - crear fuego
# - llevar el tiempo
# - emitir estado para UI
# ============================================================

const OUTSIDE_ID: int = -1

# Condiciones exteriores
@export var outside_temp_c: float = 20.0
@export var outside_o2: float = 0.209
# Viento exterior (0 = sin viento). wind_direction_deg sigue la convención
# meteorológica: ángulo desde donde VIENE el viento (0=N, 90=E, 180=S, 270=O).
@export var wind_speed_m_s: float = 0.0
@export var wind_direction_deg: float = 0.0

# Coeficiente geométrico simple para límite por ventilación
@export var vent_hrr_coeff_kw_per_sqrt_m5: float = 1500.0

# Recursos
var building_template = preload("res://sim/templates/BuildingTemplate.gd").new()

@export_enum(
	"simple_house",
	"compact_apartment",
	"two_bed_apartment",
	"three_bed_apartment",
	"two_storey_house",
	"row_house_ground_floor",
	"ranch_family_house",
	"ghanekar_bedroom_hallway"
) var template_name: String = "simple_house"

# Datos estructurales
var room_rect_m: Dictionary[int, Rect2] = {}
var rooms: Dictionary = {}
var openings: Array = []
var building_type: String = "single_family"
var exterior_walls: Array = []
var hvac_data: Dictionary = {}
var hvac_exists: bool = false
var hvac_on: bool = false

## Habitación donde se iniciará el incendio (puede venir del escenario JSON).
var default_ignition_room_id: int = 0
## Tiempo máximo de simulación en segundos (0 = sin límite).
var sim_stop_time_s: float = 0.0
## Lista de detectores cargados desde la plantilla JSON.
## Cada detector es un Dictionary con campos:
##   id, room_id, type ("smoke"|"heat"|"co"), threshold,
##   triggered (bool), triggered_at_s (float).
var detectors: Array = []

## Lista de víctimas/ocupantes cargados desde la plantilla JSON.
## Cada víctima es un Dictionary:
##   id, room_id, name, x_m, y_m, height_m (plano respiratorio, default 0.9m),
##   fed (FED ISO 13571 acumulado), incapacitated (bool), incapacitated_at_s (float).
var victims: Array = []

## Ruta del archivo de template runtime exportado por el editor.
const EDITOR_RUNTIME_PATH: String = "user://last_editor_runtime_template.json"
const STARTUP_OPTIONS_PATH: String = "user://startup_sim_options.json"
const HVAC_MODE_NONE: String = "none"
const HVAC_MODE_OFF: String = "off"
const HVAC_MODE_ON: String = "on"

# ============================================================
# READY
# ============================================================

func _ready() -> void:
	if FileAccess.file_exists(EDITOR_RUNTIME_PATH):
		var file := FileAccess.open(EDITOR_RUNTIME_PATH, FileAccess.READ)
		if file != null:
			var text: String = file.get_as_text()
			file.close()
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				_load_from_template(parsed)
				return

	var startup_options: Dictionary = _load_startup_options()
	var selected_template_name: String = String(startup_options.get("template_name", template_name))
	var template_data: Dictionary = building_template.create_by_name(selected_template_name)
	if startup_options.has("hvac_mode"):
		template_data["hvac_mode"] = String(startup_options.get("hvac_mode", HVAC_MODE_NONE))
	template_name = selected_template_name
	_load_from_template(template_data)

# ============================================================
# GETTERS
# ============================================================

func get_room_rects_m() -> Dictionary[int, Rect2]:
	return room_rect_m


func get_room_centroid_m(room_id: int) -> Vector2:
	var rect: Rect2 = room_rect_m.get(room_id, Rect2())
	return rect.position + rect.size * 0.5


func estimate_room_connection_length_m(room_a_id: int, room_b_id: int) -> float:
	if not room_rect_m.has(room_a_id) or not room_rect_m.has(room_b_id):
		return 1.0

	return maxf(0.5, get_room_centroid_m(room_a_id).distance_to(get_room_centroid_m(room_b_id)))

func get_room(room_id: int) -> RoomModel:
	return rooms.get(room_id)

func get_rooms() -> Dictionary:
	return rooms

func get_openings() -> Array:
	return openings

func load_template_data(data: Dictionary) -> void:
	_load_from_template(data)


func get_hvac_data() -> Dictionary:
	return hvac_data


func is_hvac_available() -> bool:
	return hvac_exists


func is_hvac_on() -> bool:
	return hvac_exists and hvac_on


func set_hvac_on(enabled: bool) -> bool:
	if not hvac_exists:
		hvac_on = false
		hvac_data["on"] = false
		return false
	hvac_on = enabled
	hvac_data["on"] = hvac_on
	return true


func get_hvac_mode() -> String:
	if not hvac_exists:
		return HVAC_MODE_NONE
	return HVAC_MODE_ON if hvac_on else HVAC_MODE_OFF


func get_hvac_status_text() -> String:
	if not hvac_exists:
		return "Sin HVAC"
	return "HVAC ON" if hvac_on else "HVAC OFF"


func build_hvac_summary() -> Dictionary:
	return {
		"exists": hvac_exists,
		"on": hvac_on,
		"mode": get_hvac_mode(),
		"status": get_hvac_status_text(),
		"fan_flow_m3_s": float(hvac_data.get("fan_flow_m3_s", 0.0)),
		"off_passive_flow_m3_s": float(hvac_data.get("off_passive_flow_m3_s", 0.0)),
		"outside_air_fraction": float(hvac_data.get("outside_air_fraction", 0.0)),
		"supply_count": Array(hvac_data.get("supplies", [])).size(),
		"return_count": Array(hvac_data.get("returns", [])).size()
	}

# ============================================================
# CARGA DE PLANTILLA
# ============================================================

func _load_from_template(data: Dictionary) -> void:
	rooms.clear()
	openings.clear()
	room_rect_m.clear()
	exterior_walls.clear()
	detectors.clear()
	victims.clear()
	hvac_data = {}
	hvac_exists = false
	hvac_on = false
	if typeof(data.get("hvac_data", {})) == TYPE_DICTIONARY:
		hvac_data = Dictionary(data.get("hvac_data", {})).duplicate(true)
	if data.has("outside_temp_c"):
		outside_temp_c = float(data["outside_temp_c"])
	if data.has("outside_o2"):
		outside_o2 = float(data["outside_o2"])
	building_type = String(data.get("building_type", "single_family")).to_lower()
	if building_type != "apartment":
		building_type = "single_family"
	for raw_wall in data.get("exterior_walls", []):
		if typeof(raw_wall) != TYPE_DICTIONARY:
			continue
		var wall_data: Dictionary = raw_wall
		exterior_walls.append({
			"a": _vector2_from_variant(wall_data.get("a", Vector2.ZERO)),
			"b": _vector2_from_variant(wall_data.get("b", Vector2.ZERO)),
			"thickness_m": maxf(0.05, float(wall_data.get("thickness_m", 0.16)))
		})
	if data.has("wind_speed_m_s"):
		wind_speed_m_s = float(data["wind_speed_m_s"])
	if data.has("wind_direction_deg"):
		wind_direction_deg = float(data["wind_direction_deg"])
	# Detectores opcionales (humo, calor, CO).
	for det_data in data.get("detectors", []):
		if typeof(det_data) != TYPE_DICTIONARY:
			continue
		detectors.append({
			"id": String(det_data.get("id", "")),
			"room_id": int(det_data.get("room_id", -1)),
			"type": String(det_data.get("type", "smoke")),
			"threshold": float(det_data.get("threshold", 0.025)),
			"x_m": float(det_data.get("x_m", 0.0)),
			"y_m": float(det_data.get("y_m", 0.0)),
			"triggered": false,
			"triggered_at_s": -1.0
		})
	# Víctimas/ocupantes opcionales.
	for vic_data in data.get("victims", []):
		if typeof(vic_data) != TYPE_DICTIONARY:
			continue
		victims.append({
			"id": String(vic_data.get("id", "")),
			"room_id": int(vic_data.get("room_id", -1)),
			"name": String(vic_data.get("name", "Víctima")),
			"x_m": float(vic_data.get("x_m", 0.0)),
			"y_m": float(vic_data.get("y_m", 0.0)),
			"height_m": float(vic_data.get("height_m", 0.9)),
			"fed": 0.0,
			"incapacitated": false,
			"incapacitated_at_s": -1.0
		})
	if data.has("ignition_room_id"):
		default_ignition_room_id = int(data["ignition_room_id"])
	if data.has("stop_time_s"):
		sim_stop_time_s = float(data["stop_time_s"])

	var rects_data: Dictionary = data.get("room_rect_m", {})

	# Geometría 2D
	for k in rects_data.keys():
		room_rect_m[int(k)] = _rect2_from_variant(rects_data[k])

	# Habitaciones
	for room_data in data.get("rooms_data", []):
		var room_id: int = int(room_data["id"])
		var rect_m: Rect2 = room_rect_m.get(room_id, Rect2())

		_add_room_from_rect(
			room_id,
			String(room_data["name"]),
			String(room_data["kind"]),
			rect_m,
			float(room_data["height_m"])
		)
		# Carga de combustible — opcional en template (0.0 = usa default del engine)
		if room_data.has("fuel_energy_MJ"):
			rooms[room_id].fuel_energy_MJ = float(room_data["fuel_energy_MJ"])
		if room_data.has("max_hrr_kw"):
			rooms[room_id].max_hrr_kw = float(room_data["max_hrr_kw"])
		if room_data.has("floor_level_z_m"):
			rooms[room_id].floor_level_z_m = float(room_data["floor_level_z_m"])
		if room_data.has("fuel_objects"):
			rooms[room_id].fuel_objects = _build_fuel_objects(room_data["fuel_objects"])
		# SF-AUD-014: propiedades de material de pared (1D lumped conduction). Sentinel -1.0 = global.
		rooms[room_id].wall_k_kw_m_k = float(room_data.get("wall_k_kw_m_k", -1.0))
		rooms[room_id].wall_rho_kg_m3 = float(room_data.get("wall_rho_kg_m3", -1.0))
		rooms[room_id].wall_cp_kj_kg_k = float(room_data.get("wall_cp_kj_kg_k", -1.0))
		rooms[room_id].wall_thickness_m = float(room_data.get("wall_thickness_m", -1.0))

	# Aperturas
	for op_data in data.get("openings_data", []):
		var a: int = int(op_data["a"])
		var b: int = int(op_data["b"])
		var width_m: float = float(op_data["width_m"])
		var height_m: float = float(op_data["height_m"])
		var open_fraction: float = float(op_data.get("open_fraction", 1.0))
		var type_str: String = String(op_data.get("type", "door")).strip_edges().to_lower()

		var op_type: int = OpeningModel.Type.DOOR
		match type_str:
			"window":
				op_type = OpeningModel.Type.WINDOW
			"hole":
				op_type = OpeningModel.Type.HOLE

		var op: OpeningModel = OpeningModel.new(a, b, op_type, width_m, height_m, 1.0)
		op.set_open_fraction(open_fraction)
		op.opening_index = openings.size()

		if op_data.has("sill_m"):
			op.sill_m = float(op_data["sill_m"])
		if op_data.has("wall"):
			op.wall_side = String(op_data["wall"]).to_lower()
		if op_data.has("offset_m"):
			op.offset_m = float(op_data["offset_m"])
		if op_data.has("offset_is_fraction"):
			op.offset_is_fraction = bool(op_data["offset_is_fraction"])
		if op_data.has("swing_direction"):
			op.swing_direction = String(op_data["swing_direction"]).strip_edges().to_lower()
			if op.swing_direction != "out":
				op.swing_direction = "in"
		if op_data.has("hinge_side"):
			op.hinge_side = String(op_data["hinge_side"]).strip_edges().to_lower()
			if op.hinge_side != "right":
				op.hinge_side = "left"
		if op_data.has("ppv_flow_m3_s"):
			op.ppv_flow_m3_s = float(op_data["ppv_flow_m3_s"])
		if op_data.has("ppv_delta_p_pa"):
			op.ppv_delta_p_pa = float(op_data["ppv_delta_p_pa"])
		# SF-R7: apertura vertical (hueco suelo/techo entre plantas)
		if op_data.has("is_vertical"):
			op.is_vertical = bool(op_data["is_vertical"])

		openings.append(op)

	_normalize_hvac_data(String(data.get("hvac_mode", hvac_data.get("mode", HVAC_MODE_NONE))))

func reset_detectors() -> void:
	for det in detectors:
		det["triggered"] = false
		det["triggered_at_s"] = -1.0

func reset_victims() -> void:
	for vic in victims:
		vic["fed"] = 0.0
		vic["incapacitated"] = false
		vic["incapacitated_at_s"] = -1.0

# ============================================================
# CREACIÓN DE HABITACIONES
# ============================================================

func _add_room_from_rect(
	id: int,
	room_name: String,
	kind_name: String,
	rect_m: Rect2,
	height_m: float
) -> void:
	var room: RoomModel = RoomModel.new()

	room.id = id
	room.name = room_name
	room.kind = kind_name

	room.width_m = rect_m.size.x
	room.length_m = rect_m.size.y
	room.height_m = height_m
	room.reset_dynamic_state(outside_temp_c, outside_o2)

	rooms[id] = room


func _build_fuel_objects(raw_objects: Variant) -> Array:
	var result: Array = []
	if typeof(raw_objects) != TYPE_ARRAY:
		return result

	for entry in raw_objects:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var data: Dictionary = entry
		var obj = FuelObjectModelScript.new()
		obj.id = String(data.get("id", ""))
		obj.name = String(data.get("name", obj.id))
		obj.kind = String(data.get("kind", "generic"))
		obj.room_id = int(data.get("room_id", -1))
		obj.position_m = _vector2_from_variant(data.get("position_m", Vector2.ZERO), Vector2.ZERO)
		obj.size_m = _vector2_from_variant(data.get("size_m", Vector2.ONE), Vector2.ONE)
		obj.rotation_deg = float(data.get("rotation_deg", 0.0))
		obj.footprint_m2 = float(data.get("footprint_m2", 0.0))
		obj.exposed_area_m2 = float(data.get("exposed_area_m2", obj.footprint_m2))
		obj.elevation_m = float(data.get("elevation_m", 0.0))
		obj.fuel_energy_MJ = float(data.get("fuel_energy_MJ", 0.0))
		obj.remaining_fuel_MJ = float(data.get("remaining_fuel_MJ", obj.fuel_energy_MJ))
		obj.max_hrr_kw = float(data.get("max_hrr_kw", 0.0))
		obj.ignition_temp_c = float(data.get("ignition_temp_c", obj.ignition_temp_c))
		obj.ignition_flux_kw_m2 = float(data.get("ignition_flux_kw_m2", obj.ignition_flux_kw_m2))
		obj.smoke_yield_kg_per_MJ = float(data.get("smoke_yield_kg_per_MJ", obj.smoke_yield_kg_per_MJ))
		obj.co_yield_kg_per_MJ = float(data.get("co_yield_kg_per_MJ", obj.co_yield_kg_per_MJ))
		obj.hcn_yield_kg_per_MJ = float(data.get("hcn_yield_kg_per_MJ", obj.hcn_yield_kg_per_MJ))
		obj.hcl_yield_kg_per_MJ = float(data.get("hcl_yield_kg_per_MJ", obj.hcl_yield_kg_per_MJ))
		obj.acrolein_yield_kg_per_MJ = float(data.get("acrolein_yield_kg_per_MJ", obj.acrolein_yield_kg_per_MJ))
		obj.formaldehyde_yield_kg_per_MJ = float(data.get("formaldehyde_yield_kg_per_MJ", obj.formaldehyde_yield_kg_per_MJ))
		obj.o2_consumption_kg_per_MJ = float(data.get("o2_consumption_kg_per_MJ", obj.o2_consumption_kg_per_MJ))
		obj.is_primary_ignition_source = bool(data.get("is_primary_ignition_source", false))
		# SF-AUD-016: campos de pirólisis física (Tewarson). Sentinel -1.0 = modelo empírico heredado.
		obj.critical_heat_flux_kw_m2 = float(data.get("critical_heat_flux_kw_m2", obj.critical_heat_flux_kw_m2))
		obj.heat_of_gasification_kj_kg = float(data.get("heat_of_gasification_kj_kg", obj.heat_of_gasification_kj_kg))
		obj.heat_of_combustion_kj_kg = float(data.get("heat_of_combustion_kj_kg", obj.heat_of_combustion_kj_kg))
		# SF-AUD-008: fracción soot ópticamente activa (1.0 = todo el smoke_kg contribuye a extinción).
		obj.soot_fraction = clampf(float(data.get("soot_fraction", obj.soot_fraction)), 0.0, 1.0)
		# SF-AUD-005: CO₂ yield base por combustible. Sentinel -1.0 = usar global de contexto.
		obj.co2_yield_kg_per_MJ = float(data.get("co2_yield_kg_per_MJ", obj.co2_yield_kg_per_MJ))
		# SF-AUD-015: fracción radiativa (bien ventilado). Sentinel -1.0 = global del motor.
		obj.chi_rad_normal = float(data.get("chi_rad_normal", obj.chi_rad_normal))
		# Pool fire fields
		obj.pool_spread_rate_m2_s = float(data.get("pool_spread_rate_m2_s", 0.0))
		obj.pool_hrr_kw_m2 = float(data.get("pool_hrr_kw_m2", 1000.0))
		obj.pool_max_area_m2 = float(data.get("pool_max_area_m2", 0.0))
		obj.pool_area_m2 = float(data.get("pool_area_m2", 0.0))
		obj.pool_initial_area_m2 = obj.pool_area_m2
		obj.pool_k_beta_per_m = float(data.get("pool_k_beta_per_m", 0.0))
		# SF-AUD-004: curva t² propia del objeto. -1.0 = usa alpha global del motor.
		obj.alpha_kw_s2 = float(data.get("alpha_kw_s2", obj.alpha_kw_s2))
		# SF-AUD-033: curva HRR tabulada [[t_s, hrr_kw], ...].
		# Cuando presente, anula el modelo t². t_s relativo a ignición del objeto.
		if data.has("hrr_curve") and typeof(data["hrr_curve"]) == TYPE_ARRAY:
			obj.hrr_curve = (data["hrr_curve"] as Array).duplicate(true)
		# SF-AUD-034: char layer + LOI.
		obj.char_growth_rate_m_per_kg = float(data.get("char_growth_rate_m_per_kg", obj.char_growth_rate_m_per_kg))
		obj.k_char_kw_m_k = float(data.get("k_char_kw_m_k", obj.k_char_kw_m_k))
		obj.loi_fraction = float(data.get("loi_fraction", obj.loi_fraction))
		# char_thickness_m es estado dinámico; se inicializa a 0 en tiempo de ejecución.
		result.append(obj)

	return result


func _load_startup_options() -> Dictionary:
	if not FileAccess.file_exists(STARTUP_OPTIONS_PATH):
		return {}
	var file := FileAccess.open(STARTUP_OPTIONS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _normalize_hvac_data(requested_mode: String) -> void:
	var mode: String = requested_mode.strip_edges().to_lower()
	if mode.is_empty():
		mode = String(hvac_data.get("mode", HVAC_MODE_NONE)).to_lower()

	match mode:
		HVAC_MODE_ON:
			hvac_exists = true
			hvac_on = true
		HVAC_MODE_OFF:
			hvac_exists = true
			hvac_on = false
		HVAC_MODE_NONE:
			hvac_exists = bool(hvac_data.get("exists", false))
			hvac_on = bool(hvac_data.get("on", false)) if hvac_exists else false
		_:
			hvac_exists = bool(hvac_data.get("exists", false))
			hvac_on = bool(hvac_data.get("on", false)) if hvac_exists else false

	if not hvac_exists:
		hvac_on = false
		hvac_data["exists"] = false
		hvac_data["on"] = false
		hvac_data["mode"] = HVAC_MODE_NONE
		return

	_ensure_hvac_defaults()
	hvac_data["exists"] = true
	hvac_data["on"] = hvac_on
	hvac_data["mode"] = get_hvac_mode()


func _ensure_hvac_defaults() -> void:
	if not hvac_data.has("fan_flow_m3_s"):
		hvac_data["fan_flow_m3_s"] = 0.22
	if not hvac_data.has("off_passive_flow_m3_s"):
		hvac_data["off_passive_flow_m3_s"] = 0.014
	if not hvac_data.has("outside_air_fraction"):
		hvac_data["outside_air_fraction"] = 0.08
	if not hvac_data.has("smoke_filter_penetration"):
		hvac_data["smoke_filter_penetration"] = 0.72
	if not hvac_data.has("species_filter_penetration"):
		hvac_data["species_filter_penetration"] = 0.95
	if not hvac_data.has("condition_supply_air"):
		hvac_data["condition_supply_air"] = false
	if not hvac_data.has("supply_temp_c"):
		hvac_data["supply_temp_c"] = outside_temp_c
	if not hvac_data.has("conditioning_strength"):
		hvac_data["conditioning_strength"] = 0.45

	var returns: Array = _normalize_hvac_vents(hvac_data.get("returns", []))
	var supplies: Array = _normalize_hvac_vents(hvac_data.get("supplies", []))
	if returns.is_empty() or supplies.is_empty():
		var generated: Dictionary = _build_default_hvac_layout()
		if returns.is_empty():
			returns = generated.get("returns", [])
		if supplies.is_empty():
			supplies = generated.get("supplies", [])
	hvac_data["returns"] = returns
	hvac_data["supplies"] = supplies


func _normalize_hvac_vents(raw_vents: Variant) -> Array:
	var vents: Array = []
	if typeof(raw_vents) != TYPE_ARRAY:
		return vents
	for entry in raw_vents:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = Dictionary(entry).duplicate(true)
		var room_id: int = int(data.get("room_id", -1))
		if not rooms.has(room_id):
			continue
		data["room_id"] = room_id
		data["flow_fraction"] = maxf(0.0, float(data.get("flow_fraction", 1.0)))
		if data.has("flow_m3_s"):
			data["flow_m3_s"] = maxf(0.0, float(data.get("flow_m3_s", 0.0)))
		if data.has("height_m"):
			data["height_m"] = maxf(0.0, float(data.get("height_m", 0.0)))
		else:
			data["height_fraction"] = clampf(float(data.get("height_fraction", 0.92)), 0.0, 1.0)
		vents.append(data)
	return vents


func _build_default_hvac_layout() -> Dictionary:
	var returns: Array = []
	var supplies: Array = []
	var sorted_ids: Array[int] = []
	for key in rooms.keys():
		sorted_ids.append(int(key))
	sorted_ids.sort()

	for room_id in sorted_ids:
		var room: RoomModel = get_room(room_id)
		if room == null:
			continue
		var kind_name: String = room.kind.to_lower()
		if returns.size() < 2 and (kind_name == "pasillo" or kind_name == "salon"):
			returns.append({"room_id": room_id, "flow_fraction": 1.0, "height_fraction": 0.90})
		else:
			supplies.append({"room_id": room_id, "flow_fraction": 1.0, "height_fraction": 0.92})

	if returns.is_empty() and not sorted_ids.is_empty():
		var first_id: int = sorted_ids[0]
		returns.append({"room_id": first_id, "flow_fraction": 1.0, "height_fraction": 0.90})
		for i in range(supplies.size() - 1, -1, -1):
			if int(Dictionary(supplies[i]).get("room_id", -1)) == first_id:
				supplies.remove_at(i)

	if supplies.is_empty():
		for room_id in sorted_ids:
			if int(Dictionary(returns[0]).get("room_id", -1)) == room_id:
				continue
			supplies.append({"room_id": room_id, "flow_fraction": 1.0, "height_fraction": 0.92})

	return {
		"returns": returns,
		"supplies": supplies
	}


func _rect2_from_variant(value: Variant) -> Rect2:
	if typeof(value) == TYPE_RECT2:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return Rect2(
			float(data.get("x", 0.0)),
			float(data.get("y", 0.0)),
			float(data.get("w", data.get("width", 0.0))),
			float(data.get("h", data.get("height", 0.0)))
		)
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value
		if values.size() >= 4:
			return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return Rect2()


func _vector2_from_variant(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return Vector2(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)))
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value
		if values.size() >= 2:
			return Vector2(float(values[0]), float(values[1]))
	return fallback

# ============================================================
# HELPERS GEOMÉTRICOS
# ============================================================

func has_outside_opening(room_id: int) -> bool:
	for op in openings:
		if op.open_fraction <= 0.0:
			continue

		var to_outside: bool = (
			(op.a == room_id and op.b == OUTSIDE_ID) or
			(op.b == room_id and op.a == OUTSIDE_ID)
		)

		if to_outside:
			return true

	return false

func estimate_vent_hrr_kw(room_id: int) -> float:
	var sum_AH_sqrtH: float = 0.0

	for op in openings:
		if op.open_fraction <= 0.0:
			continue

		var connects_outside: bool = (
			(op.a == room_id and op.b == OUTSIDE_ID) or
			(op.b == room_id and op.a == OUTSIDE_ID)
		)

		if not connects_outside:
			continue

		var width: float = maxf(0.0, op.width_m)
		var height: float = maxf(0.0, op.height_m)
		var area_open: float = width * height * clampf(op.open_fraction, 0.0, 1.0)

		sum_AH_sqrtH += area_open * sqrt(height)

	if sum_AH_sqrtH <= 0.0:
		return 0.0

	return vent_hrr_coeff_kw_per_sqrt_m5 * sum_AH_sqrtH

func get_connected_openings(room_id: int) -> Array:
	var result: Array = []

	for op in openings:
		if op.a == room_id or op.b == room_id:
			result.append(op)

	return result

func get_neighbor_room_ids(room_id: int) -> Array[int]:
	var neighbors: Array[int] = []

	for op in openings:
		if op.open_fraction <= 0.0:
			continue

		if op.a == room_id and op.b != OUTSIDE_ID:
			neighbors.append(op.b)
		elif op.b == room_id and op.a != OUTSIDE_ID:
			neighbors.append(op.a)

	return neighbors


func get_opening_count() -> int:
	return openings.size()


func get_opening_at(index: int):
	if index < 0 or index >= openings.size():
		return null
	return openings[index]


func set_opening_fraction(index: int, open_fraction: float) -> bool:
	var op: OpeningModel = get_opening_at(index)
	if op == null:
		return false

	op.set_open_fraction(open_fraction)
	return true


func open_opening(index: int) -> bool:
	return set_opening_fraction(index, 1.0)


func close_opening(index: int) -> bool:
	return set_opening_fraction(index, 0.0)


func get_opening_label(index: int) -> String:
	var op: OpeningModel = get_opening_at(index)
	if op == null:
		return "Apertura"

	var prefix: String = "P"
	if op.type == OpeningModel.Type.WINDOW:
		prefix = "V"
	elif op.type == OpeningModel.Type.HOLE:
		prefix = "H"
	return "%s%02d %s-%s" % [
		prefix,
		index,
		_get_room_display_name(op.a),
		_get_room_display_name(op.b)
	]


func get_opening_status_text(index: int) -> String:
	var op: OpeningModel = get_opening_at(index)
	if op == null:
		return "Sin apertura seleccionada"

	var area_eff_m2: float = op.width_m * op.height_m * clampf(op.open_fraction, 0.0, 1.0)
	return "%s | %.0f%% | Aeff %.2f m2" % [
		op.state_label(),
		op.open_fraction * 100.0,
		area_eff_m2
	]


func build_opening_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for index in range(openings.size()):
		var op: OpeningModel = openings[index]
		if op == null:
			continue

		summaries.append({
			"index": index,
			"label": get_opening_label(index),
			"status": get_opening_status_text(index),
			"type": _opening_type_name(op),
			"state_label": op.state_label(),
			"open_fraction": op.open_fraction,
			"is_exterior": op.is_exterior_opening()
		})

	return summaries


func _opening_type_name(op: OpeningModel) -> String:
	if op == null:
		return "door"
	if op.type == OpeningModel.Type.WINDOW:
		return "window"
	if op.type == OpeningModel.Type.HOLE:
		return "hole"
	return "door"


func _get_room_display_name(room_id: int) -> String:
	if room_id == OUTSIDE_ID:
		return "Exterior"

	var room: RoomModel = get_room(room_id)
	if room == null:
		return "Sala %d" % room_id

	if room.name != "":
		return room.name
	return "Sala %d" % room.id
