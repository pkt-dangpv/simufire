extends RefCounted
class_name BuildingViewMirror
## Copia del edificio que leen las vistas mientras el motor avanza en otro hilo.
##
## Con el motor en un hilo trabajador, el hilo principal no puede tocar el
## `BuildingModel` real mientras dura un paso: las salas, aperturas y muebles
## cambian a mitad de lectura (y un Array o Dictionary que crece mientras otro
## hilo lo recorre cuelga el programa). Las vistas leen el edificio por todas
## partes (~130 lecturas en FP, visor 3D, 2D, HUD y minimapa); en lugar de
## reescribirlas, se les da esta copia, que solo se toca en el hilo principal.
##
## - `_init` clona una vez todo el grafo de objetos del edificio (salas,
##   aperturas, muebles, fuego): mismas clases, mismos métodos, mismos datos.
## - `sync` copia de nuevo todas las variables de script del real a la copia.
##   Solo con el motor parado (entre pasos). ~1,5 ms en la casa sencilla.
## - `forward_view_edits` lleva al real lo que las vistas cambiaron en la copia
##   (fracción de apertura de puertas y ventanas, HVAC): se aplica entre pasos,
##   igual que antes se aplicaba antes del paso siguiente.
##
## Se copian todas las variables, no una lista: una vista nueva que lea otro
## campo lo ve actualizado sin tocar nada aquí. No toca `sim/`.

var building: BuildingModel = null
var _real: BuildingModel = null
## instance_id del objeto real -> su copia.
var _copies: Dictionary = {}
## Script -> nombres de sus variables de script (get_property_list es caro).
var _names_by_script: Dictionary = {}
## Objetos ya copiados en este `sync` (un objeto con dos referencias, o un
## ciclo, se copia una sola vez).
var _synced_this_pass: Dictionary = {}
var _synced_open_fraction: PackedFloat64Array = PackedFloat64Array()
var _synced_hvac_on: bool = false


func _init(real: BuildingModel) -> void:
	_real = real
	building = _clone_object(real) as BuildingModel
	_remember_view_editable_values()


## Libera la copia (es un Node fuera del árbol: nadie más la libera).
func dispose() -> void:
	if building != null and is_instance_valid(building):
		building.free()
	building = null
	_copies.clear()


## Copia el estado del real a la copia. Solo con el motor parado.
func sync() -> void:
	if building == null or _real == null:
		return
	_synced_this_pass.clear()
	_sync_object(_real, building)
	_synced_this_pass.clear()
	_remember_view_editable_values()


## Aplica al real los cambios que las vistas hicieron en la copia desde el
## último `sync`. Solo con el motor parado. Devuelve si había alguno.
func forward_view_edits() -> bool:
	if building == null or _real == null:
		return false
	var changed: bool = false
	var count: int = mini(building.get_opening_count(), _synced_open_fraction.size())
	for index in range(count):
		var op: OpeningModel = building.get_opening_at(index)
		if op != null and op.open_fraction != _synced_open_fraction[index]:
			_real.set_opening_fraction(index, op.open_fraction)
			changed = true
	if building.hvac_on != _synced_hvac_on:
		_real.set_hvac_on(building.hvac_on)
		changed = true
	return changed


func _remember_view_editable_values() -> void:
	var count: int = building.get_opening_count()
	_synced_open_fraction.resize(count)
	for index in range(count):
		var op: OpeningModel = building.get_opening_at(index)
		_synced_open_fraction[index] = op.open_fraction if op != null else 0.0
	_synced_hvac_on = building.hvac_on


func _script_variable_names(o: Object) -> Array[StringName]:
	var script: Script = o.get_script()
	if _names_by_script.has(script):
		return _names_by_script[script]
	var names: Array[StringName] = []
	for property: Dictionary in o.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(StringName(property["name"]))
	_names_by_script[script] = names
	return names


## Instancia la misma clase. Algunos modelos (OpeningModel) exigen argumentos
## en `_init`: se pasan vacíos, porque todas sus variables se copian después.
func _new_like(o: Object) -> Object:
	var script: Script = o.get_script()
	if script == null:
		return ClassDB.instantiate(o.get_class())
	for method: Dictionary in script.get_script_method_list():
		if String(method["name"]) != "_init":
			continue
		var args: Array = []
		var required: int = Array(method["args"]).size() - Array(method.get("default_args", [])).size()
		for i in range(required):
			var arg_type: int = int(method["args"][i]["type"])
			args.append(null if arg_type == TYPE_NIL or arg_type == TYPE_OBJECT else type_convert(null, arg_type))
		return script.callv("new", args)
	return script.new()


func _clone_object(o: Object) -> Object:
	var id: int = o.get_instance_id()
	if _copies.has(id):
		return _copies[id]
	var copy: Object = _new_like(o)
	_copies[id] = copy
	for name: StringName in _script_variable_names(o):
		copy.set(name, _copy_value(o.get(name)))
	return copy


## Un valor para la copia: los objetos se cambian por su copia y los Array y
## Dictionary se duplican (nunca se comparten con el real). Los Packed*Array y
## String son copia en escritura, seguros entre hilos.
func _copy_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_OBJECT:
			if value == null or not is_instance_valid(value):
				return null
			if value is Node:
				# Un nodo no se clona; hoy el grafo no tiene ninguno salvo el edificio.
				push_warning("BuildingViewMirror: el edificio referencia un nodo; la copia lo comparte")
				return value
			var object: Object = value
			if _copies.has(object.get_instance_id()):
				var copy: Object = _copies[object.get_instance_id()]
				_sync_object(object, copy)
				return copy
			return _clone_object(object)
		TYPE_ARRAY:
			var source: Array = value
			var array_copy: Array = source.duplicate(false)
			for i in range(source.size()):
				var element: Variant = source[i]
				var element_type: int = typeof(element)
				if element_type == TYPE_OBJECT or element_type == TYPE_ARRAY or element_type == TYPE_DICTIONARY:
					array_copy[i] = _copy_value(element)
			return array_copy
		TYPE_DICTIONARY:
			var source_dict: Dictionary = value
			var dict_copy: Dictionary = source_dict.duplicate(false)
			for key: Variant in source_dict.keys():
				var entry: Variant = source_dict[key]
				var entry_type: int = typeof(entry)
				if entry_type == TYPE_OBJECT or entry_type == TYPE_ARRAY or entry_type == TYPE_DICTIONARY:
					dict_copy[key] = _copy_value(entry)
			return dict_copy
	return value


func _sync_object(o: Object, copy: Object) -> void:
	var id: int = o.get_instance_id()
	if _synced_this_pass.has(id):
		return
	_synced_this_pass[id] = true
	for name: StringName in _script_variable_names(o):
		var value: Variant = o.get(name)
		var value_type: int = typeof(value)
		if value_type != TYPE_OBJECT and value_type != TYPE_ARRAY and value_type != TYPE_DICTIONARY:
			# Valores simples, String y Packed*Array: se copian tal cual.
			copy.set(name, value)
			continue
		if value_type == TYPE_OBJECT and value != null and is_instance_valid(value) \
				and not (value is Node) and _copies.has(value.get_instance_id()):
			var current: Object = _copies[value.get_instance_id()]
			_sync_object(value, current)
			if copy.get(name) != current:
				copy.set(name, current)
			continue
		copy.set(name, _copy_value(value))
