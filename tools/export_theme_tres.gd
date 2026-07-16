extends SceneTree
## Exporta el tema generado por SimuFireTheme.build_theme() al recurso
## canonico editable en el inspector: ui/SimuFireTheme.tres (referenciado
## por MainMenu, SimulationScene y ScenarioEditorScene).
## Uso: godot --headless --path . --script res://tools/export_theme_tres.gd
## Re-ejecutar si se cambia build_theme() para regenerar el .tres.
## OJO: conservar la linea uid del header si ResourceSaver la pierde
## (uid://bnfl86slco45l — ScenarioEditorScene la referencia).

const OUT_PATH := "res://ui/SimuFireTheme.tres"


func _initialize() -> void:
	var theme: Theme = load("res://ui/SimuFireTheme.gd").build_theme()
	var err: int = ResourceSaver.save(theme, OUT_PATH)
	if err == OK:
		print("[export_theme] tema guardado en ", OUT_PATH)
	else:
		push_error("[export_theme] fallo al guardar: %d" % err)
	quit(0 if err == OK else 1)
