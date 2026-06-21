extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var building: BuildingModel = BuildingModelScript.new()
	_expect(building.load_template_data(_make_template()), "BuildingModel rejected FP HUD template")

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateFPTechnicalHUD"
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	fp.set_active(true)
	await get_tree().physics_frame

	var state: Dictionary = _make_state()
	fp.set_state(state)
	await get_tree().process_frame

	var technical_panel := _find_child_by_name(fp, "TechnicalOverlayPanel") as Control
	var technical_label := _find_child_by_name(fp, "TechnicalOverlayLabel") as Label
	var status_label := _find_child_by_name(fp, "FirstPersonStatusLabel") as Label
	_expect(technical_panel != null and technical_panel.visible, "FP technical overlay was not visible")
	_expect(technical_label != null, "FP technical overlay label missing")
	_expect(status_label != null, "FP status label missing")
	if technical_label != null:
		_expect(technical_label.text.contains("210"), "standing temperature missing from FP technical overlay")
		_expect(technical_label.text.contains("740"), "CO ppm missing from FP technical overlay")
		_expect(technical_label.text.contains("1.9"), "CO2 percent missing from FP technical overlay")
		_expect(technical_label.text.contains("17.4"), "O2 percent missing from FP technical overlay")
		_expect(technical_label.text.contains("O₂u"), "standing O2 layer label missing from FP technical overlay")
		_expect(technical_label.text.contains("32"), "HCN ppm missing from FP technical overlay")
		_expect(technical_label.text.contains("0.42"), "FED missing from FP technical overlay")
		_expect(technical_label.text.contains("Vis FP"), "FP visibility missing from technical overlay")
		_expect(technical_label.text.contains("Reg ILC"), "ILC regime alert missing from FP technical overlay")
	if status_label != null:
		_expect(not status_label.text.contains("HRR"), "top FP status duplicated HRR while technical overlay was visible")
		_expect(not status_label.text.contains("Vis"), "top FP status duplicated visibility while technical overlay was visible")

	state["0"]["combustion_regime"] = "VENTILATION_CONTROLLED_BURNING"
	fp.set_state(state)
	fp._update_status_hud(true)
	await get_tree().process_frame
	if technical_label != null:
		_expect(technical_label.text.contains("Reg ILV"), "ILV regime alert missing after ventilation-limited transition")

	state["0"]["o2_upper"] = 0.017
	fp.set_state(state)
	fp._update_status_hud(true)
	await get_tree().process_frame
	if technical_label != null:
		_expect(technical_label.text.contains("Reg ILV CRIT"), "critical ILV low-O2 alert missing from FP technical overlay")
		_expect(technical_label.text.contains("Vis FP 1.6m"), "critical ILV did not clamp FP visibility in technical overlay")

	state["0"]["visibility_m"] = 0.04
	fp.set_state(state)
	fp._update_status_hud(true)
	await get_tree().process_frame
	if technical_label != null:
		_expect(technical_label.text.contains("Vis FP 0.1m"), "critical ILV raised sub-meter raw visibility instead of preserving it")

	fp._cycle_stance()
	if technical_label != null:
		_expect(technical_label.text.contains("105"), "crouch temperature did not update in FP technical overlay")
		_expect(technical_label.text.contains("O₂l"), "crouch O2 layer label missing from FP technical overlay")
	fp._cycle_stance()
	if technical_label != null:
		_expect(technical_label.text.contains("35"), "prone temperature did not update in FP technical overlay")

	fp.show_technical_overlay = false
	fp.show_visibility_readout = true
	fp.set_state(state)
	fp._update_status_hud(true)
	await get_tree().process_frame
	if status_label != null:
		_expect(status_label.text.contains("HRR"), "top FP status omitted HRR when technical overlay was hidden")
		_expect(status_label.text.contains("Vis"), "top FP status omitted visibility when technical overlay was hidden")
	var readout_panel := _find_child_by_name(fp, "VisibilityReadoutPanel") as Control
	var readout_label := _find_child_by_name(fp, "VisibilityReadoutLabel") as Label
	_expect(readout_panel != null and readout_panel.visible, "compact FP visibility readout was not visible")
	if readout_label != null:
		_expect(readout_label.text.contains("Vis FP"), "compact FP visibility readout text missing")

	fp.set_active(false)
	remove_child(fp)
	fp.free()
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
			"0": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 3.2}
		},
		"rooms_data": [
			{
				"id": 0,
				"name": "Salon HUD",
				"kind": "salon",
				"height_m": 2.5,
				"floor_level_z_m": 0.0,
				"fuel_energy_MJ": 120.0,
				"max_hrr_kw": 300.0,
				"fuel_objects": []
			}
		],
		"openings_data": [
			{"a": 0, "b": -1, "type": "door", "wall": "bottom", "width_m": 0.9, "height_m": 2.0, "open_fraction": 1.0}
		],
		"detectors": [],
		"victims": [],
		"player_start": {
			"room_id": 0,
			"position_m": {"x": 1.2, "y": 1.6},
			"floor_level_z_m": 0.0,
			"yaw_deg": 0.0
		},
		"exterior_walls": []
	}


func _make_state() -> Dictionary:
	return {
		"0": {
			"id": 0,
			"name": "Salon HUD",
			"kind": "salon",
			"height_m": 2.5,
			"hrr_kw": 120.0,
			"temp_upper_c": 210.0,
			"temp_lower_c": 35.0,
			"thermal_layer_m": 1.15,
			"temp_at_1_8m_c": 185.0,
			"temp_at_1_1m_c": 82.0,
			"temp_at_0_5m_c": 38.0,
			"co_upper_ppm": 740.0,
			"co2_upper_ppm": 18500.0,
			"o2": 0.174,
			"o2_upper": 0.174,
			"o2_lower": 0.209,
			"hcn_upper_ppm": 32.0,
			"fed": 0.42,
			"visibility_m": 7.4,
			"smoke_kg": 1.6,
			"smoke_layer_m": 1.25,
			"smoke_display_layer_m": 1.25,
			"combustion_regime": "FUEL_CONTROLLED",
			"fuel_objects": []
		}
	}


func _find_child_by_name(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	if root.name == node_name:
		return root
	for child in root.get_children():
		var hit := _find_child_by_name(child, node_name)
		if hit != null:
			return hit
	return null


func _finish() -> void:
	if _failures.is_empty():
		print("FP TECHNICAL HUD VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FP TECHNICAL HUD VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
