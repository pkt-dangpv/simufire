extends RefCounted


static func visual_archetype(obj: Dictionary) -> String:
	var kind_text: String = String(obj.get("kind", "")).strip_edges().to_lower()
	var name_text: String = String(obj.get("name", "")).strip_edges().to_lower()
	var id_text: String = String(obj.get("id", "")).strip_edges().to_lower()
	var tokens: String = "%s %s %s" % [kind_text, name_text, id_text]

	# --- Kind explícito del editor (arquetipo ya resuelto) ---
	if kind_text == "coffee_table":
		return "coffee_table"
	if kind_text == "desk":
		return "desk"
	if kind_text == "tv_stand":
		return "tv_stand"
	if kind_text == "console":
		return "side_table"
	if kind_text == "dresser":
		return "dresser"
	if kind_text == "storage":
		return "storage"
	if kind_text == "plastic_bin":
		return "containers"

	# --- Sillas (antes que mesa/escritorio) ---
	if _has(tokens, ["silla oficina", "silla escritorio", "silla de escritorio", "office chair", "desk chair"]):
		return "chair_desk"
	if _has(tokens, ["silla", "chair", "taburete", "stool"]):
		return "chair"

	# --- Escritorio (antes que "mesa" genérica) ---
	if _has(tokens, ["escritorio", "desk"]):
		return "desk"

	# --- Camas ---
	if _has(tokens, ["litera", "bunk"]):
		return "bed_bunk"
	if _has(tokens, ["cama individual", "cama nido", "cama single", "single bed"]):
		return "bed_single"
	if _has(tokens, ["cama", "bed", "colchon", "colchón"]):
		return "bed"

	# --- Asientos ---
	if _has(tokens, ["sofa esquina", "sofá esquina", "chaise", "sofa rinconera", "corner sofa"]):
		return "lounge_sofa_long"
	if _has(tokens, ["sofa", "sofá", "couch"]):
		return "sofa"
	if _has(tokens, ["sillon", "sillón", "butaca", "armchair"]):
		return "armchair"
	if _has(tokens, ["banco", "bench"]):
		return "bench"

	# --- Baño ---
	if _has(tokens, ["bañera", "banera", "bathtub", "tina"]):
		return "bathtub"
	if _has(tokens, ["ducha", "shower"]):
		return "shower"
	if _has(tokens, ["inodoro", "retrete", "wc", "aseo", "toilet"]):
		return "toilet"
	# El fregadero antes que el lavabo: "kitchen sink" tambien contiene "sink",
	# y sin esto acababa dibujado como lavabo de bano.
	if _has(tokens, ["fregadero", "kitchen sink", "kitchen_sink"]):
		return "kitchen_sink"
	if _has(tokens, ["lavabo", "sink"]):
		return "sink"

	# --- Cocina (electrodomésticos antes que unidad genérica) ---
	if _has(tokens, ["nevera", "frigo", "frigorifico", "frigorífico", "fridge"]):
		return "kitchen_fridge"
	if _has(tokens, ["horno", "fogon", "fogón", "vitro", "vitroceramica", "stove", "cocina de gas", "hornalla"]):
		return "kitchen_stove"
	if _has(tokens, ["fregadero", "kitchen sink"]):
		return "kitchen_sink"
	if _has(tokens, ["lavadora", "washer", "washing"]):
		return "washer"
	if _has(tokens, ["secadora", "dryer"]):
		return "dryer"
	if _has(tokens, ["encimera", "bajos", "counter", "kitchen"]):
		return "kitchen_unit"
	if _has(tokens, ["despensa", "columna", "pantry"]):
		return "wardrobe"

	# --- Mesas ---
	if _has(tokens, ["mesa centro", "mesa de centro", "coffee table", "mesita de centro"]):
		return "coffee_table"
	if _has(tokens, ["mesilla", "mesita", "noche", "nightstand", "nochero"]):
		return "side_table"
	if _has(tokens, ["mesa", "table"]):
		return "table"

	# --- Muebles TV / almacenaje ---
	if _has(tokens, ["mueble tv", "television", "televisión", "tv stand", "tv"]):
		return "tv_stand"
	if _has(tokens, ["libreria", "librería", "estanteria", "estantería", "estante", "repisa", "shelf", "bookshelf", "bookcase"]):
		return "bookcase"
	if _has(tokens, ["armario", "ropero", "wardrobe", "closet"]):
		return "wardrobe"
	if _has(tokens, ["aparador", "comoda", "cómoda", "cajonera", "sideboard", "dresser", "zapatero"]):
		return "dresser"
	if _has(tokens, ["consola", "recibidor", "console"]):
		return "side_table"

	# --- Iluminación / decoración ---
	if _has(tokens, ["lampara de mesa", "lámpara de mesa", "lampara sobremesa", "table lamp"]):
		return "lamp_table"
	if _has(tokens, ["lampara", "lámpara", "lamp"]):
		return "lamp_floor"
	if _has(tokens, ["planta", "maceta", "plant"]):
		return "plant"

	# --- Textiles / alfombras / cortinas ---
	if _has(tokens, ["alfombra", "rug", "moqueta", "tapete"]):
		return "rug"
	if _has(tokens, ["cortina", "curtain"]):
		return "curtain"
	if _has(tokens, ["toalla", "pano", "paño", "textil", "textiles", "ropa", "sabana", "sábana"]):
		return "textile_pile"

	# --- Líquidos / plásticos ---
	if _has(tokens, ["grasa", "aceite", "liquido", "líquido", "pool"]):
		return "pool"
	if _has(tokens, ["cubo", "plastico", "plástico", "plasticos", "plásticos", "plastic", "bin", "trash", "papelera"]):
		return "containers"
	if _has(tokens, ["caja", "carton", "cartón", "box", "carro", "cart"]):
		return "clutter"

	# --- Fallbacks por kind de fuego ---
	if tokens.contains("mobiliario_tapizado"):
		return "sofa"
	if tokens.contains("mobiliario_madera"):
		return "dresser"
	if tokens.contains("mobiliario_mixto"):
		return "clutter"
	if tokens.contains("textiles"):
		return "textile_pile"
	if tokens.contains("plasticos") or tokens.contains("plásticos"):
		return "containers"
	if tokens.contains("liquido_combustible"):
		return "pool"
	if tokens.contains("resto"):
		return "clutter"
	return "clutter"


## Busca la palabra, no la cadena.
##
## Con `contains` a secas, "mesilla" contiene "silla" y "cortinas" contiene
## "tina": la mesilla de noche se clasificaba como SILLA y las cortinas como
## BANERA, y salian dibujadas como tales. Aqui la aguja tiene que empezar y
## acabar en un limite de palabra -principio, final, o un caracter que no sea
## una letra: espacio, guion bajo, cifra- y se admite la "s" del plural
## castellano, para que "cortina" siga casando con "cortinas".
static func _has(haystack: String, needles: Array) -> bool:
	for needle in needles:
		if _has_word(haystack, String(needle)):
			return true
	return false


static func _has_word(haystack: String, needle: String) -> bool:
	if needle == "":
		return false
	var from: int = 0
	while true:
		var at: int = haystack.find(needle, from)
		if at < 0:
			return false
		if not _is_letter_at(haystack, at - 1):
			var after: int = at + needle.length()
			if not _is_letter_at(haystack, after):
				return true
			# Plural castellano: "cortinas" para la aguja "cortina".
			if haystack.substr(after, 1) == "s" and not _is_letter_at(haystack, after + 1):
				return true
		from = at + 1
	return false


static func _is_letter_at(text: String, index: int) -> bool:
	if index < 0 or index >= text.length():
		return false
	var c: String = text.substr(index, 1)
	# Vale para acentos y ene: una letra cambia al pasarla a mayuscula o a
	# minuscula; un guion bajo, un espacio o una cifra no.
	return c.to_upper() != c.to_lower()


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
