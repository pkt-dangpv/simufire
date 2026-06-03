extends Node

const LoadErrorDialogScript := preload("res://editor/EditorLoadErrorDialog.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var canvas := CanvasLayer.new()
	canvas.name = "CanvasLayer"
	add_child(canvas)

	var helper: EditorLoadErrorDialog = LoadErrorDialogScript.new()
	var shown: bool = helper.show_error(
		self,
		"Error al cargar escenario",
		"No se pudo cargar el escenario.",
		"C:/tmp/escenario_roto.json"
	)
	_expect(shown, "load error dialog was not shown")

	var dialog := canvas.get_node_or_null("LoadErrorDialog") as AcceptDialog
	_expect(dialog != null, "LoadErrorDialog node was not created under CanvasLayer")
	if dialog != null:
		_expect(dialog.title == "Error al cargar escenario", "dialog title mismatch")
		_expect(dialog.ok_button_text == "Aceptar", "dialog OK button text mismatch")
		_expect(dialog.dialog_text.contains("No se pudo cargar el escenario."), "dialog text missing error message")
		_expect(dialog.dialog_text.contains("C:/tmp/escenario_roto.json"), "dialog text missing path")
		_expect(dialog.visible, "dialog was not made visible")

	var second_shown: bool = helper.show_error(
		self,
		"Error al ejecutar escenario",
		"El escenario no tiene habitaciones."
	)
	_expect(second_shown, "second load error dialog call failed")
	var second_dialog := canvas.get_node_or_null("LoadErrorDialog") as AcceptDialog
	_expect(second_dialog == dialog, "helper did not reuse the existing LoadErrorDialog")
	if second_dialog != null:
		_expect(second_dialog.title == "Error al ejecutar escenario", "dialog title was not updated")
		_expect(second_dialog.dialog_text == "El escenario no tiene habitaciones.", "dialog text was not updated")
	_expect(_count_load_error_dialogs(canvas) == 1, "more than one LoadErrorDialog was created")

	_finish()


func _count_load_error_dialogs(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child.name == "LoadErrorDialog":
			count += 1
	return count


func _finish() -> void:
	if _failures.is_empty():
		print("EDITOR LOAD ERROR DIALOG VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("EDITOR LOAD ERROR DIALOG VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
