extends SceneTree

## Mide si el mobiliario tiene SENTIDO, no si cabe.
##
## Nace de la queja del usuario -"muebles en sitios que no corresponden"- y de
## que `validate_furniture_layout` pasaba igual: esa red mide geometria (nada
## fuera de la sala, nada solapado, alturas reales) y un monton de cajas
## perfectamente alineado contra la pared del pasillo cumple las seis reglas.
##
## Aqui se mide otra cosa, y son las relaciones que hacen que un salon parezca
## un salon:
##
##   tele          en el semiplano de delante del sofa, y mirandolo
##   mesa de centro delante del sofa y cerca
##   mesilla       pegada al costado de la cama
##   silla         mirando a su mesa o a su escritorio
##   cocina        nevera, fregadero y fuegos en el MISMO paramento
##   nada          mirando a un muro que tiene delante a menos de un palmo
##
##   <godot> --headless --path . --script res://tools/probe_furniture_sense.gd

const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FurnitureVisualLayout := preload("res://view/furniture/FurnitureVisualLayout.gd")
const FurnitureRoomGrammar := preload("res://view/furniture/FurnitureRoomGrammar.gd")

## Distancia a la que una pieza se considera "de cara al muro".
const NOSE_TO_WALL_M: float = 0.35

var _totales: Dictionary = {}


func _initialize() -> void:
	var builder = BuildingTemplateScript.new()
	for preset in builder.get_preset_definitions():
		_probe(String(preset.get("id", "")), builder)
	print("")
	print("=== resumen: cumplidas / casos ===")
	for regla in _totales.keys():
		var d: Dictionary = _totales[regla]
		var casos: int = int(d["casos"])
		var ok: int = int(d["ok"])
		print("  %-34s %3d / %3d%s" % [
			regla, ok, casos,
			"" if casos == 0 or ok == casos else "   <-- %d fallan" % (casos - ok)])
	quit()


func _probe(preset_id: String, builder) -> void:
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(builder.create_by_name(preset_id))
	var rects: Dictionary = building.get_room_rects_m()
	for raw_id in rects.keys():
		var room_id: int = int(raw_id)
		var rect: Rect2 = rects[raw_id]
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		var objetos: Array = []
		for o in room.fuel_objects:
			objetos.append(o)
		var piezas: Array = FurnitureVisualLayout.normalize_room(building, room_id, rect, objetos, true)
		_check_room("%s/%s" % [preset_id, room.name], rect, piezas)
	building.free()


func _check_room(etiqueta: String, rect: Rect2, piezas: Array) -> void:
	var por_arq: Dictionary = {}
	for raw in piezas:
		var spec: Dictionary = raw
		var arq: String = String(spec.get("visual_archetype", ""))
		var lista: Array = por_arq.get(arq, [])
		lista.append(spec)
		por_arq[arq] = lista

	var sofa: Dictionary = _first(por_arq, ["lounge_sofa_long", "sofa"])
	var cama: Dictionary = _first(por_arq, ["bed", "bed_single", "bed_bunk"])
	var mesa: Dictionary = _first(por_arq, ["table"])
	var escritorio: Dictionary = _first(por_arq, ["desk"])

	if not sofa.is_empty():
		var tele: Dictionary = _first(por_arq, ["tv_stand"])
		if not tele.is_empty():
			_count(etiqueta, "tele delante del sofa", _in_front(sofa, tele, 6.0))
			_count(etiqueta, "tele mirando al sofa", _looks_at(tele, sofa, 60.0))
		var mesita: Dictionary = _first(por_arq, ["coffee_table"])
		if not mesita.is_empty():
			_count(etiqueta, "mesa de centro ante el sofa", _in_front(sofa, mesita, 1.8))

	if not cama.is_empty():
		var mesilla: Dictionary = _first(por_arq, ["side_table", "lamp_table"])
		if not mesilla.is_empty():
			_count(etiqueta, "mesilla junto a la cama", _beside(cama, mesilla, 1.1))

	for silla in Array(por_arq.get("chair_desk", [])):
		if not escritorio.is_empty():
			_count(etiqueta, "silla mirando al escritorio", _looks_at(silla, escritorio, 60.0))
	for silla in Array(por_arq.get("chair", [])):
		if not mesa.is_empty():
			_count(etiqueta, "silla mirando a la mesa", _looks_at(silla, mesa, 60.0))

	var cocina: Array = []
	for arq in ["kitchen_fridge", "kitchen_sink", "kitchen_stove", "kitchen_unit"]:
		for spec in Array(por_arq.get(arq, [])):
			cocina.append(spec)
	if cocina.size() >= 2:
		_count(etiqueta, "la cocina comparte paramento", _same_wall(rect, cocina))

	for raw in piezas:
		var spec: Dictionary = raw
		if String(spec.get("visual_archetype", "")) in ["rug", "pool", "curtain", "plant", "clutter"]:
			continue
		_count(etiqueta, "no mira a un muro pegado", not _nose_in_wall(rect, spec))


# --------------------------------------------------------------------------
# Medidas
# --------------------------------------------------------------------------

func _center(spec: Dictionary) -> Vector2:
	var pos: Vector2 = _v2(spec.get("position_m", Vector2.ZERO))
	var size: Vector2 = _v2(spec.get("size_m", Vector2.ZERO))
	return pos + size * 0.5


## Hacia donde mira la pieza. Cuidado: NO es `rotation_deg`, que es el giro de
## la malla. En una cama no coinciden -su largo va en la direccion en la que
## mira- y usar el de la malla daba a la cama un frente girado noventa grados.
func _facing(spec: Dictionary) -> Vector2:
	return FurnitureRoomGrammar.direction_of(
		float(spec.get("visual_facing_deg", spec.get("rotation_deg", 0.0))))


## `b` esta en el semiplano de delante de `a` y a menos de `max_m`.
func _in_front(a: Dictionary, b: Dictionary, max_m: float) -> bool:
	var d: Vector2 = _center(b) - _center(a)
	if d.length() > max_m:
		return false
	return d.normalized().dot(_facing(a)) > 0.35


## `a` mira hacia `b` dentro de un cono de `cono_deg` a cada lado.
func _looks_at(a: Dictionary, b: Dictionary, cono_deg: float) -> bool:
	var d: Vector2 = _center(b) - _center(a)
	if d.length_squared() < 0.0001:
		return true
	return rad_to_deg(acos(clampf(d.normalized().dot(_facing(a)), -1.0, 1.0))) <= cono_deg


## `b` esta al costado de `a`, no delante ni detras.
func _beside(a: Dictionary, b: Dictionary, max_m: float) -> bool:
	var d: Vector2 = _center(b) - _center(a)
	if d.length() > max_m:
		return false
	var frente: Vector2 = _facing(a)
	var lado := Vector2(frente.y, -frente.x)
	return absf(d.normalized().dot(lado)) > 0.6


## Todas las piezas comparten el paramento mas cercano.
func _same_wall(rect: Rect2, piezas: Array) -> bool:
	var lados: Dictionary = {}
	for spec in piezas:
		lados[_nearest_wall(rect, _center(spec))] = true
	return lados.size() == 1


## Una pieza con la cara contra el muro: mira a un paramento que tiene a menos
## de un palmo. Es lo que hace que un sofa parezca puesto de castigo.
func _nose_in_wall(rect: Rect2, spec: Dictionary) -> bool:
	var c: Vector2 = _center(spec)
	var f: Vector2 = _facing(spec)
	var size: Vector2 = _v2(spec.get("size_m", Vector2.ZERO))
	var media: float = maxf(size.x, size.y) * 0.5
	var distancia: float = INF
	if f.x > 0.5:
		distancia = rect.size.x - c.x
	elif f.x < -0.5:
		distancia = c.x
	elif f.y > 0.5:
		distancia = rect.size.y - c.y
	elif f.y < -0.5:
		distancia = c.y
	return distancia - media < NOSE_TO_WALL_M


func _nearest_wall(rect: Rect2, c: Vector2) -> String:
	var d: Dictionary = {
		"left": c.x, "right": rect.size.x - c.x,
		"top": c.y, "bottom": rect.size.y - c.y,
	}
	var mejor: String = "left"
	for lado in d.keys():
		if float(d[lado]) < float(d[mejor]):
			mejor = lado
	return mejor


func _first(por_arq: Dictionary, arquetipos: Array) -> Dictionary:
	for arq in arquetipos:
		var lista: Array = por_arq.get(arq, [])
		if not lista.is_empty():
			return lista[0]
	return {}


func _count(etiqueta: String, regla: String, ok: bool) -> void:
	var d: Dictionary = _totales.get(regla, {"casos": 0, "ok": 0})
	d["casos"] = int(d["casos"]) + 1
	if ok:
		d["ok"] = int(d["ok"]) + 1
	else:
		print("  %-40s %s" % [regla, etiqueta])
	_totales[regla] = d


func _v2(value: Variant) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		return Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	return Vector2.ZERO
