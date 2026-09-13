extends Node
## Guardarrail de FP-6 (docs/AUDITORIA_VISUAL_2026-08-29.md §5).
##
## El humo debe ATENUAR el brillo de la luz de techo, no recortar su alcance.
## Cuando el alcance se encoge por debajo de la altura de la sala, la estancia
## contigua al fuego se lee como una caja negra aunque el observador este bajo
## la capa y con visibilidad de sobra. Aqui se fija ese contrato y, a la vez,
## se protege el comportamiento que SI se quiere conservar: en un regimen ILV
## critico la luz de techo practicamente se apaga.

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

const ROOM_H: float = 2.62
const ROOM_W: float = 4.0
const ROOM_D: float = 4.0

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "FP smoke lighting template rejected")

	var host := Node3D.new()
	host.name = "SmokeLightingHost"
	add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateFPSmokeLighting"
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame

	var light := fp.get_node_or_null("FirstPersonWorld/CeilingLight_1") as OmniLight3D
	_expect(light != null, "FP ceiling light for room 1 was not created")
	if light == null:
		host.free()
		building.free()
		_finish()
		return

	# --- Sala limpia: referencia ---
	fp.set_state(_make_state(30.0, 0.0, ROOM_H, ""))
	await _settle()
	var clean_energy: float = light.light_energy
	var clean_range: float = light.omni_range
	_expect(clean_energy > 0.1, "FP ceiling light did not start lit in a clean room")
	_expect(
		clean_range >= ROOM_H,
		"FP ceiling light does not even reach its own floor when clean (%.2f < %.2f)" % [clean_range, ROOM_H]
	)

	# --- Sala enhumada SIN fuego: es el caso de FP-6 ---
	fp.set_state(_make_state(9.0, 0.35, 1.95, ""))
	await _settle()
	var smoky_energy: float = light.light_energy
	var smoky_range: float = light.omni_range
	_expect(
		smoky_energy < clean_energy,
		"FP ceiling light was not dimmed by smoke (%.3f >= %.3f)" % [smoky_energy, clean_energy]
	)
	_expect(
		smoky_energy > 0.02,
		"FP ceiling light was extinguished in a smoke-filled room without fire (%.3f)" % smoky_energy
	)
	# El contrato de FP-6: el alcance no se recorta por debajo del alcance
	# limpio, y por tanto nunca por debajo de la altura de la sala.
	_expect(
		smoky_range >= clean_range - 0.001,
		"FP-6 regression: smoke shrank the ceiling light range (%.2f < %.2f)" % [smoky_range, clean_range]
	)
	_expect(
		smoky_range >= ROOM_H,
		"FP-6 regression: ceiling light range %.2f no longer reaches the floor %.2f m below it" % [smoky_range, ROOM_H]
	)

	# --- Regimen ILV critico: aqui SI debe apagarse casi del todo ---
	fp.set_state(_make_state(1.2, 2.4, 0.6, "VENTILATION_CONTROLLED_BURNING"))
	await _settle()
	_expect(
		light.light_energy < smoky_energy,
		"FP ceiling light did not dim further under a ventilation-limited regime"
	)

	host.free()
	building.free()
	_finish()


func _settle() -> void:
	for _i in range(6):
		await get_tree().process_frame


func _make_template() -> Dictionary:
	return {
		"version": 1,
		"building_type": "apartment",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {
			"0": {"x": 0.0, "y": 0.0, "w": 6.0, "h": ROOM_D},
			"1": {"x": 6.0, "y": 0.0, "w": ROOM_W, "h": ROOM_D}
		},
		"rooms_data": [
			{
				"id": 0, "name": "Salon", "kind": "salon", "height_m": ROOM_H,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 400.0, "max_hrr_kw": 900.0,
				"fuel_objects": []
			},
			{
				"id": 1, "name": "Dormitorio", "kind": "dormitorio", "height_m": ROOM_H,
				"floor_level_z_m": 0.0, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
				"fuel_objects": []
			}
		],
		"openings_data": [
			{"a": 0, "b": 1, "type": "door", "wall": "right", "offset_m": 1.6, "width_m": 0.92, "height_m": 2.05, "open_fraction": 1.0}
		],
		"detectors": [],
		"victims": [],
		"exterior_walls": []
	}


## Estado de la sala 1 (sin fuego nunca): solo cambia su carga de humo.
func _make_state(visibility_m: float, smoke_kg: float, layer_m: float, regime: String) -> Dictionary:
	return {
		"0": {
			"id": 0, "name": "Salon", "kind": "salon", "height_m": ROOM_H,
			"has_fire": false, "hrr_kw": 0.0,
			"temp_upper_c": 20.0, "o2": 0.209, "o2_upper": 0.209,
			"smoke_kg": 0.0, "visibility_m": 30.0,
			"smoke_layer_m": ROOM_H, "visible_smoke_layer_m": ROOM_H,
			"fuel_objects": []
		},
		"1": {
			"id": 1, "name": "Dormitorio", "kind": "dormitorio", "height_m": ROOM_H,
			"has_fire": false, "hrr_kw": 0.0,
			"temp_upper_c": 90.0, "o2": 0.19, "o2_upper": 0.19,
			"combustion_regime": regime,
			"smoke_kg": smoke_kg, "visibility_m": visibility_m,
			"smoke_layer_m": layer_m, "visible_smoke_layer_m": layer_m,
			"fuel_objects": []
		}
	}


func _finish() -> void:
	if _failures.is_empty():
		print("FP SMOKE LIGHTING VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP SMOKE LIGHTING VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
