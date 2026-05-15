extends RefCounted


static func visual_archetype(obj: Dictionary) -> String:
	var kind_text: String = String(obj.get("kind", "")).strip_edges().to_lower()
	var name_text: String = String(obj.get("name", "")).strip_edges().to_lower()
	var id_text: String = String(obj.get("id", "")).strip_edges().to_lower()
	var tokens: String = "%s %s %s" % [kind_text, name_text, id_text]

	if tokens.contains("sofa") or tokens.contains("sillon") or tokens.contains("sillón") or tokens.contains("armchair") or tokens.contains("couch"):
		return "sofa"
	if tokens.contains("cama") or tokens.contains("bed") or tokens.contains("colchon"):
		return "bed"
	if tokens.contains("mesa") or tokens.contains("table") or tokens.contains("desk"):
		return "table"
	if tokens.contains("cortina") or tokens.contains("curtain"):
		return "curtain"
	if tokens.contains("armario") or tokens.contains("wardrobe"):
		return "wardrobe"
	if tokens.contains("libreria") or tokens.contains("librería") or tokens.contains("shelf") or tokens.contains("bookshelf") or tokens.contains("bookcase"):
		return "storage"
	if tokens.contains("alfombra") or tokens.contains("rug") or tokens.contains("moqueta") or tokens.contains("tapete"):
		return "rug"
	if tokens.contains("textil") or tokens.contains("textiles") or tokens.contains("ropa"):
		return "textile_pile"
	if tokens.contains("liquido") or tokens.contains("grasa") or tokens.contains("pool"):
		return "pool"
	if tokens.contains("plastico") or tokens.contains("plastic"):
		return "containers"
	if tokens.contains("cocina") or tokens.contains("kitchen"):
		return "kitchen_unit"
	if tokens.contains("mobiliario_tapizado"):
		return "sofa"
	if tokens.contains("mobiliario_madera"):
		return "storage"
	if tokens.contains("mobiliario_mixto"):
		return "clutter"
	if tokens.contains("resto"):
		return "clutter"
	return "clutter"


static func shape_needs_rebuild(node: Node3D, kind_name: String, size_m: Vector2) -> bool:
	if node == null:
		return true
	if String(node.get_meta("kind_name", "")) != kind_name:
		return true
	if absf(float(node.get_meta("size_x", -1.0)) - size_m.x) > 0.001:
		return true
	if absf(float(node.get_meta("size_y", -1.0)) - size_m.y) > 0.001:
		return true
	return false
