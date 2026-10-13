extends RefCounted

## Read-only inventory shared by headless and real-window diagnostic fixtures.
static func read(main: Node) -> Dictionary:
	var pairs: Array = []
	var fp = main.first_person_controller
	for room_id: Variant in fp._furniture_nodes_by_room:
		var fp_nodes: Dictionary = fp._furniture_nodes_by_room[room_id].get("fuel_obj_nodes", {})
		var overview_nodes: Dictionary = main.visualizer_3d._room_items.get(room_id, {}).get("fuel_obj_nodes", {})
		for object_id: Variant in fp_nodes:
			if not overview_nodes.has(object_id):
				continue
			var a := fp_nodes[object_id] as Node3D
			var b := overview_nodes[object_id] as Node3D
			pairs.append({"room_id": room_id, "object_id": object_id,
				"fp_visible": a.is_visible_in_tree(), "overview_visible": b.is_visible_in_tree(),
				"positions_equal": a.global_position.is_equal_approx(b.global_position)})
	return {"matching_objects": pairs.size(), "pairs": pairs}
