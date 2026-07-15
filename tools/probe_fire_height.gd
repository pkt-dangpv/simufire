extends SceneTree
## Sonda headless: reproduce el calculo de la llama 3D del salon con el
## escenario real y reporta si la geometria supera el techo de la sala.
## Uso: godot --headless --path . --script res://tools/probe_fire_height.gd

var _viz = null
var _building = null
var _ran: bool = false


func _initialize() -> void:
	var file := FileAccess.open("res://scenarios/simple_house_objects.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	_building = load("res://sim/BuildingModel.gd").new()
	var ok: bool = _building.load_template_data(data)
	print("[probe] building load: ", ok)

	_viz = load("res://view/3d/Visualizer3D.gd").new()
	_viz.building = _building
	root.add_child(_viz)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_probe()
	return true


func _run_probe() -> void:
	var room0 = _building.get_room(0)
	print("[probe] salon height_m=", room0.height_m, " floor_level=", room0.floor_level_z_m)

	var state: Dictionary = {
		"0": {
			"name": "Salon",
			"hrr_kw": 1752.0,
			"burned_hrr_kw": 1752.0,
			"temp_upper_c": 440.0,
			"smoke_kg": 4.0,
			"visibility_m": 1.1,
			"smoke_layer_m": 1.1,
			"hot_layer_m": 0.9,
			"layer_150c_m": 1.2,
			"fuel_objects": [
				{
					"id": "salon_sofa",
					"name": "Sofa 3 plazas",
					"kind": "sofa",
					"state": "flaming",
					"hrr_kw": 1200.0,
					"max_hrr_kw": 700.0,
					"position_m": Vector2(0.35, 1.3),
					"size_m": Vector2(0.9, 2.45),
					"rotation_deg": 90.0,
					"elevation_m": 0.38,
					"is_primary_ignition_source": true,
					"fuel_energy_MJ": 1100.0,
					"remaining_fuel_MJ": 400.0,
				},
			],
		},
	}
	for i in range(40):
		_viz.set_state(state)

	print("[probe] built=", _viz._built, " room_items keys=", _viz._room_items.keys())
	if not _viz._room_items.has(0):
		print("[probe] ABORT: sala 0 no esta en _room_items")
		return
	var item: Dictionary = _viz._room_items[0]
	var fire_root: Node3D = item.get("fire_root")
	var base_y: float = fire_root.position.y
	print("[probe] fire_root.position=", fire_root.position)
	print("[probe] fire_height_m=", item.get("fire_height_m"),
		" available=", item.get("fire_available_height_m"),
		" cap_w=", item.get("fire_cap_weight"))

	_viz._update_fire_animation()
	var fire_core: MeshInstance3D = item.get("fire_core")
	var fire_glow: MeshInstance3D = item.get("fire_glow")
	var core_top: float = base_y + fire_core.position.y + fire_core.scale.y * 0.5
	print("[probe] core scale=", fire_core.scale, " pos=", fire_core.position, " -> top_world_y=", core_top)
	if fire_glow != null:
		print("[probe] glow scale=", fire_glow.scale, " pos=", fire_glow.position)
	var roof_y: float = room0.floor_level_z_m + room0.height_m
	print("[probe] roof_y=", roof_y, " | core sobresale: ", core_top > roof_y + 0.01)

	var cap: MeshInstance3D = item.get("fire_cap")
	if cap != null and cap.visible:
		print("[probe] cap pos=", cap.position, " scale=", cap.scale)

	# Caso patologico: objeto ardiendo con elevation_m alta (llama plantada
	# en el techo si el visor no lo acota).
	var elevated_state: Dictionary = state.duplicate(true)
	var room_state: Dictionary = elevated_state["0"]
	var objs: Array = room_state["fuel_objects"]
	var obj: Dictionary = objs[0]
	obj["elevation_m"] = 2.3
	item["fire_anchor_id"] = ""
	for i in range(40):
		_viz.set_state(elevated_state)
	base_y = fire_root.position.y
	_viz._update_fire_animation()
	core_top = base_y + fire_core.position.y + fire_core.scale.y * 0.5
	var roof_y2: float = room0.floor_level_z_m + room0.height_m
	print("[probe] ELEVADO base_y=", base_y, " core_top=", core_top,
		" roof=", roof_y2, " | sobresale: ", core_top > roof_y2 + 0.01)
