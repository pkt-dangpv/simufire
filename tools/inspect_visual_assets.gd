extends SceneTree

const Inspection := preload("res://view/3d/furniture/FurnitureAssetInspection.gd")
const Dimensions := preload("res://view/furniture/FurnitureDimensions.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var kinds: Array = Dimensions.SPECS.keys()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visual-asset="):
			kinds = [arg.trim_prefix("--visual-asset=")]
	kinds.sort()
	var failures: int = 0
	for kind in kinds:
		var spec: Dictionary = Dimensions.spec_for(String(kind))
		var footprint := Vector2(float(spec["long_m"]), float(spec["deep_m"]))
		var report: Dictionary = Inspection.inspect(String(kind), footprint)
		print("VISUAL_ASSET_REPORT " + JSON.stringify(report))
		if not Array(report["errors"]).is_empty():
			failures += 1
	print("VISUAL_ASSET_INSPECTION_RESULT " + JSON.stringify({
		"assets": kinds.size(), "failures": failures, "writes": 0}))
	quit(0 if failures == 0 else 1)
