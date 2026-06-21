extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "BuildingModel rejected FP fire template")

	var host := Node3D.new()
	host.name = "ValidateFPFireHost"
	add_child(host)

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "FirstPersonController"
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame

	var fire_root := fp.get_node_or_null("FirstPersonWorld/FPFire/Fire_00") as Node3D
	_expect(fire_root != null, "FP fire root was not created")
	if fire_root == null:
		_finish()
		return
	_expect(not fire_root.visible, "FP fire starts visible before simulation state")

	fp.set_state(_make_fire_state(Vector2(1.0, 0.9), 900.0))
	_expect(fire_root.visible, "FP fire did not become visible for active HRR")
	_expect_vec3_close(
		fire_root.position,
		_expected_anchor(Vector2(1.0, 0.9), Vector2(1.4, 0.8)),
		0.08,
		"FP fire was not anchored to burning furniture"
	)
	var core := fire_root.get_node_or_null("Core") as MeshInstance3D
	_expect(core != null and core.scale.y > 0.05, "FP fire core was not animated/scaled")
	var light := fire_root.get_node_or_null("FireLight") as OmniLight3D
	_expect(light != null and light.light_energy > 0.1, "FP fire light did not receive energy")
	var normal_light_energy: float = light.light_energy if light != null else 0.0

	fp.set_state(_make_fire_state(Vector2(1.0, 0.9), 900.0, "VENTILATION_CONTROLLED_BURNING", 0.017))
	_expect(fire_root.visible, "FP ILV critical fire should remain visible as a weak flame")
	if light != null:
		_expect(
			light.light_energy < normal_light_energy * 0.55,
			"FP ILV critical fire light was not damped by low upper-layer O2"
		)

	fp.set_state(_make_fire_state(Vector2(1.0, 0.9), 900.0, "ILV_LATENT", 0.017, true))
	if light != null:
		_expect(light.light_energy <= 0.01, "FP ILV latent fire light should be hidden")

	fp.set_state(_make_fire_state(Vector2(2.0, 1.6), 1100.0))
	_expect_vec3_close(
		fire_root.position,
		_expected_anchor(Vector2(2.0, 1.6), Vector2(1.4, 0.8)),
		0.08,
		"FP fire did not follow moved fuel-object snapshot"
	)

	for _i in range(14):
		fp.set_state(_make_no_fire_state(Vector2(2.0, 1.6)))
	_expect(not fire_root.visible, "FP fire remained visible after HRR dropped to zero")
	if light != null:
		_expect(light.light_energy <= 0.01, "FP fire light remained energized after HRR dropped to zero")

	host.free()
	building.free()
	_finish()


func _make_template() -> Dictionary:
	return {
		"version": 1,
		"building_type": "single_family",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {
			"0": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 3.0}
		},
		"rooms_data": [
			{
				"id": 0,
				"name": "Salon FP",
				"kind": "salon",
				"height_m": 2.5,
				"floor_level_z_m": 0.0,
				"fuel_energy_MJ": 420.0,
				"max_hrr_kw": 1200.0,
				"fuel_objects": [
					{
						"id": "fp_sofa",
						"name": "Sofa FP",
						"kind": "sofa",
						"room_id": 0,
						"position_m": {"x": 1.0, "y": 0.9},
						"size_m": {"x": 1.4, "y": 0.8},
						"rotation_deg": 0.0,
						"visual_pose_locked": true,
						"footprint_m2": 1.12,
						"fuel_energy_MJ": 240.0,
						"max_hrr_kw": 1200.0,
						"is_primary_ignition_source": true
					}
				]
			}
		],
		"openings_data": [
			{"a": 0, "b": -1, "type": "door", "wall": "bottom", "width_m": 0.9, "height_m": 2.0, "open_fraction": 1.0}
		],
		"detectors": [],
		"victims": [],
		"player_start": {
			"room_id": 0,
			"position_m": {"x": 0.7, "y": 2.4},
			"floor_level_z_m": 0.0,
			"yaw_deg": 0.0
		},
		"exterior_walls": []
	}


func _make_fire_state(
	position_m: Vector2,
	hrr_kw: float,
	combustion_regime: String = "FUEL_CONTROLLED",
	o2_upper: float = 0.209,
	fire_latent_active: bool = false
) -> Dictionary:
	return {
		"0": {
			"has_fire": true,
			"hrr_kw": hrr_kw,
			"o2": o2_upper,
			"o2_upper": o2_upper,
			"combustion_regime": combustion_regime,
			"fire_latent_active": fire_latent_active,
			"visibility_m": 30.0,
			"smoke_kg": 0.0,
			"smoke_layer_m": 2.5,
			"fuel_objects": [
				_fuel_object_snapshot(position_m, "flaming", hrr_kw)
			]
		}
	}


func _make_no_fire_state(position_m: Vector2) -> Dictionary:
	return {
		"0": {
			"has_fire": false,
			"hrr_kw": 0.0,
			"visibility_m": 30.0,
			"smoke_kg": 0.0,
			"smoke_layer_m": 2.5,
			"fuel_objects": [
				_fuel_object_snapshot(position_m, "cold", 0.0)
			]
		}
	}


func _fuel_object_snapshot(position_m: Vector2, state_name: String, hrr_kw: float) -> Dictionary:
	return {
		"id": "fp_sofa",
		"name": "Sofa FP",
		"kind": "sofa",
		"room_id": 0,
		"position_m": {"x": position_m.x, "y": position_m.y},
		"size_m": {"x": 1.4, "y": 0.8},
		"elevation_m": 0.0,
		"state": state_name,
		"hrr_kw": hrr_kw,
		"max_hrr_kw": 1200.0,
		"is_primary_ignition_source": true
	}


func _expected_anchor(position_m: Vector2, size_m: Vector2) -> Vector3:
	var origin_offset := Vector2(-2.0, -1.5)
	return Vector3(
		position_m.x + size_m.x * 0.5 + origin_offset.x,
		0.34,
		position_m.y + size_m.y * 0.5 + origin_offset.y
	)


func _finish() -> void:
	if _failures.is_empty():
		print("FP FIRE VISUALS VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP FIRE VISUALS VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_vec3_close(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	if actual.distance_to(expected) > tolerance:
		_failures.append("%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])
