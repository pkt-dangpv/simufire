extends Node

# Exporta todas las plantillas predefinidas (presets en BuildingTemplate.gd)
# a archivos JSON editables en res://scenarios/. Así aparecen en el desplegable
# de Escenario del editor y pueden modificarse y guardarse como cualquier otro.
#
# Uso:
#   godot --headless --path . res://tools/export_presets_to_scenarios.tscn

const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")

const OUT_DIR := "res://scenarios"
const PREFIX := "preset_"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var builder = BuildingTemplateScript.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ok := 0
	var fail := 0
	print("=== EXPORT PRESETS -> SCENARIOS ===")
	for preset in builder.get_preset_definitions():
		if typeof(preset) != TYPE_DICTIONARY:
			continue
		var preset_id: String = String(preset.get("id", ""))
		if preset_id == "":
			continue
		var data: Dictionary = builder.create_by_name(preset_id)
		if data.is_empty():
			print("  FAIL  %s (create_by_name vacío)" % preset_id)
			fail += 1
			continue
		var out_path: String = "%s/%s%s.json" % [OUT_DIR, PREFIX, preset_id]
		if Serializer.save_scenario(out_path, data):
			print("  OK    %s" % out_path)
			ok += 1
		else:
			print("  FAIL  %s (no se pudo escribir)" % out_path)
			fail += 1
	print("=== HECHO: %d exportados, %d fallidos ===" % [ok, fail])
	get_tree().quit(0 if fail == 0 else 1)
