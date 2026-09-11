extends SceneTree
## Guardarrail de los pasillos y del tipo de abertura.
##
## Sale de tres cosas que reporto el usuario el 2026-09-10:
##
##  1. **Una U se dibuja con tres tramos pegados y tiene que leerse como UN
##     pasillo**: mismo nombre y sin la linea de tabique entre tramos. Siguen
##     siendo salas separadas a proposito -el motor es un modelo de zonas y el
##     tiempo que tarda el humo en recorrer un pasillo es justamente lo que un
##     pasillo aporta al incendio; fundirlos en una sola zona diria que el humo
##     aparece a la vez en los dos extremos-.
##  2. **Los tramos se unen solos** con un paso sin puerta, y ese paso **se
##     puede convertir en puerta**. Antes no habia forma: la ficha de la
##     abertura ensenaba el tipo y no dejaba tocarlo.
##  3. **La forma del pasillo se puede forzar.** El umbral decidia a escondidas
##     entre recto y giro, y un arrastre en diagonal moderada salia recto sin
##     avisar.
##
##   <godot> --headless --path . --script res://tools/validate_corridors.gd

var _editor: Node = null
var _frames: int = 0
var _fails: int = 0

func _eq(que, got, want) -> void:
	if str(got) == str(want): print("  ok   %s = %s" % [que, str(got)])
	else:
		print("  FAIL %s = %s (se esperaba %s)" % [que, str(got), str(want)]); _fails += 1

func _initialize() -> void:
	_editor = (load("res://scenes/ScenarioEditorScene.tscn") as PackedScene).instantiate()
	root.add_child(_editor)

func _nombres() -> Array:
	var out := []
	for r in _editor.editor_data.get("rooms_data", []):
		out.append(String(r.get("name","")))
	return out

func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 4: return false

	# Una U de tres tramos pegados
	_editor.current_tool = 2
	_editor._handle_press(Vector2(0.0, 0.0)); _editor._handle_release(Vector2(6.0, 0.0))
	_editor._handle_press(Vector2(6.0, 0.0)); _editor._handle_release(Vector2(6.0, 5.0))
	_editor._handle_press(Vector2(6.0, 5.0)); _editor._handle_release(Vector2(0.0, 5.0))
	var nombres: Array = _nombres()
	var bases := {}
	for n in nombres:
		bases[_editor.call("_corridor_base_name", n)] = true
	_eq("la U es UN pasillo", bases.size(), 1)
	_eq("y son tres tramos (zonas)", nombres.size(), 3)

	# La junta entre tramos no se dibuja como tabique
	var vista: Array = _editor._plan_rooms_view()
	var con_junta := 0
	for e in vista:
		if Dictionary(e).has("seams_px"): con_junta += 1
	_eq("los tramos ocultan su junta", con_junta >= 2, true)

	# Se unen solos con un hueco, y ese hueco se puede volver puerta
	var ops: Array = _editor.editor_data.get("openings_data", [])
	_eq("se unen solos", ops.size() >= 2, true)
	_eq("y nacen como hueco", String(Dictionary(ops[0]).get("type","")), "hole")
	_editor.selected_opening_index = 0
	_editor._props.show({"opening": ops[0], "opening_type_label": "Hueco",
		"opening_max_width_m": 3.0, "opening_max_offset_m": 10.0,
		"opening_accepts_balcony": false, "opening_balcony_max_width_m": 3.0})
	_editor._props._opening_type_option.select(0)
	_editor._apply_opening_properties()
	ops = _editor.editor_data.get("openings_data", [])
	_eq("el hueco se convierte en puerta", String(Dictionary(ops[0]).get("type","")), "door")

	# Forzar la L en un gesto que saldria recto
	_editor._corridor_forced_mode = "l"
	var l: Dictionary = _editor._build_corridor_layout(Vector2(20.0, 20.0), Vector2(24.0, 2.0) + Vector2(0.0, 18.0))
	_eq("L forzada en un gesto casi recto", String(l.get("mode","")), "l")
	_editor._corridor_forced_mode = "recto"
	var r: Dictionary = _editor._build_corridor_layout(Vector2(20.0, 20.0), Vector2(24.0, 24.0))
	_eq("recto forzado en una diagonal", String(r.get("mode","")), "straight")
	_editor._corridor_forced_mode = ""

	print("[validate_corridors] %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
	return true
