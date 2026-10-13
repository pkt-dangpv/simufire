extends "res://view/fp/FirstPersonController.gd"

## Counterfactual only: enable after warm-up, keep existing meshes visible.
## Product scenes never use this script. Dynamic furniture visuals are stale
## while enabled, so this is NOT a proposed production fix or quality parity.
var diagnostic_freeze_furniture: bool = false


func _update_fp_furniture_visuals() -> void:
	if diagnostic_freeze_furniture:
		return
	super._update_fp_furniture_visuals()
