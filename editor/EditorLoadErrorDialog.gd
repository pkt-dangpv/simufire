class_name EditorLoadErrorDialog
extends RefCounted

# Manages the lazy-created AcceptDialog used to show scenario load/run errors.
# Owned by ScenarioEditor — created on first use via show_error() and reused thereafter.

var _dialog: AcceptDialog = null


func _ensure(owner: Node, title: String) -> void:
	var canvas: CanvasLayer = owner.get_node_or_null("CanvasLayer") as CanvasLayer
	var parent: Node = canvas if canvas != null else owner
	_dialog = parent.get_node_or_null("LoadErrorDialog") as AcceptDialog
	if _dialog == null:
		_dialog = AcceptDialog.new()
		_dialog.name = "LoadErrorDialog"
		parent.add_child(_dialog)
	_dialog.title = title
	_dialog.ok_button_text = "Aceptar"


## Show the error dialog centered on screen.
## Returns true if the dialog was shown; false if unavailable (caller should fall back to status bar).
func show_error(owner: Node, title: String, message: String, path: String = "") -> bool:
	_ensure(owner, title)
	if _dialog == null:
		return false
	var full_msg: String = message
	if path != "":
		full_msg += "\n\n" + path
	_dialog.dialog_text = full_msg
	_dialog.popup_centered()
	return true
