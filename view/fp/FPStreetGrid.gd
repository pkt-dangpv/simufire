extends RefCounted

## La calle que rodea la manzana, calculada UNA vez.
##
## El problema que resuelve. Cada fachada montaba su propia calle completa
## -calzada de 46 m, dos aceras y dos bordillos-, orientada segun esa fachada.
## Con dos o tres fachadas eso son dos o tres calles enteras superpuestas: las
## aceras de una cruzaban la calzada de otra, los bordillos partian los cruces
## por la mitad y las marcas viales seguian de largo por dentro de la
## interseccion. Por la ventana se veian carreteras cruzandose sin sentido.
##
## Una calle no se construye por fachadas: se construye por manzana. El
## edificio ocupa un solar, alrededor hay una acera, alrededor de esa acera la
## calzada, y al otro lado la acera de enfrente. Cada una es un ANILLO cerrado,
## y donde dos brazos de calzada se encuentran no hay que hacer nada especial:
## la esquina ya es parte del anillo, y eso es exactamente lo que es un cruce.
##
## Lo unico que hay que tratar aparte es lo que NO debe entrar en el cruce:
##  - las marcas de carril, que se cortan antes de llegar
##  - los bordillos, que solo corren por los tramos rectos
##  - los pasos de cebra, que van justo por fuera del cruce, que es donde estan
##
## Todo se devuelve en coordenadas de mundo (planta XZ). Este modulo no dibuja.

## Un anillo partido en cuatro rectangulos que NO se solapan.
##
## Es la pieza de la que sale todo. Las esquinas se las quedan las bandas
## superior e inferior; las laterales van justo entre ellas. Sin esta reparticion
## los cuatro rectangulos se pisarian en las cuatro esquinas, que es la version
## en pequeno del problema que se venia arrastrando.
static func ring(inner: Rect2, width_m: float) -> Array[Rect2]:
	var w: float = maxf(0.01, width_m)
	return [
		Rect2(inner.position.x - w, inner.position.y - w, inner.size.x + w * 2.0, w),
		Rect2(inner.position.x - w, inner.position.y + inner.size.y, inner.size.x + w * 2.0, w),
		Rect2(inner.position.x - w, inner.position.y, w, inner.size.y),
		Rect2(inner.position.x + inner.size.x, inner.position.y, w, inner.size.y),
	]


## Reparto completo de la calle alrededor de una manzana.
##
## `building_rect` es la huella del edificio en planta. Devuelve los tres
## anillos y, para cada lado, lo que necesita el decorado que se apoya en el.
static func layout(building_rect: Rect2, sidewalk_w_m: float, road_w_m: float) -> Dictionary:
	var sidewalk: float = maxf(0.4, sidewalk_w_m)
	var road: float = maxf(2.0, road_w_m)
	var block: Rect2 = building_rect.grow(sidewalk)
	var road_inner: Rect2 = block
	var road_outer: Rect2 = block.grow(road)
	var far_inner: Rect2 = road_outer

	return {
		"building": building_rect,
		"block": block,
		"road_inner": road_inner,
		"road_outer": road_outer,
		"near_walk": ring(building_rect, sidewalk),
		"road": ring(road_inner, road),
		"far_walk": ring(far_inner, sidewalk),
		"sidewalk_w_m": sidewalk,
		"road_w_m": road,
	}


## Marcas de carril: discontinua por el eje de cada brazo, cortada antes del
## cruce. En un cruce no hay linea discontinua, y dibujarla es de las cosas que
## mas delatan que la calle es un decorado.
static func lane_marks(grid: Dictionary, dash_m: float, gap_m: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var block: Rect2 = grid["block"]
	var road: float = float(grid["road_w_m"])
	var axis_offset: float = road * 0.5
	var clearance: float = road * 0.75
	var sides: Array = [
		{"axis": "x", "fixed": block.position.y - axis_offset, "start": block.position.x, "end": block.position.x + block.size.x},
		{"axis": "x", "fixed": block.position.y + block.size.y + axis_offset, "start": block.position.x, "end": block.position.x + block.size.x},
		{"axis": "z", "fixed": block.position.x - axis_offset, "start": block.position.y, "end": block.position.y + block.size.y},
		{"axis": "z", "fixed": block.position.x + block.size.x + axis_offset, "start": block.position.y, "end": block.position.y + block.size.y},
	]
	var pitch: float = maxf(0.6, dash_m + gap_m)
	for side in sides:
		var start: float = float(side["start"]) + clearance
		var end: float = float(side["end"]) - clearance
		var length: float = end - start
		if length <= dash_m:
			continue
		var count: int = maxi(1, int(floor(length / pitch)))
		for i in range(count):
			var t: float = start + (float(i) + 0.5) / float(count) * length
			if String(side["axis"]) == "x":
				out.append({"x": t, "z": float(side["fixed"]), "long": dash_m, "across": 0.11, "along_x": true})
			else:
				out.append({"x": float(side["fixed"]), "z": t, "long": dash_m, "across": 0.11, "along_x": false})
	return out


## Pasos de cebra: uno por brazo, justo por fuera del cruce, que es donde se
## cruza una calle de verdad.
static func crossings(grid: Dictionary, stripe_w_m: float, stripe_gap_m: float, stripes: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var block: Rect2 = grid["block"]
	var road: float = float(grid["road_w_m"])
	var setback: float = road * 0.85
	var pitch: float = stripe_w_m + stripe_gap_m
	var arms: Array = [
		{"along_x": true, "fixed": block.position.y - road * 0.5, "at": block.position.x + setback},
		{"along_x": true, "fixed": block.position.y + block.size.y + road * 0.5, "at": block.position.x + block.size.x - setback},
		{"along_x": false, "fixed": block.position.x - road * 0.5, "at": block.position.y + block.size.y - setback},
		{"along_x": false, "fixed": block.position.x + block.size.x + road * 0.5, "at": block.position.y + setback},
	]
	for arm in arms:
		for i in range(stripes):
			var offset: float = (float(i) - float(stripes - 1) * 0.5) * pitch
			if bool(arm["along_x"]):
				out.append({
					"x": float(arm["at"]) + offset, "z": float(arm["fixed"]),
					"long": stripe_w_m, "across": road - 0.4, "along_x": true,
				})
			else:
				out.append({
					"x": float(arm["fixed"]), "z": float(arm["at"]) + offset,
					"long": stripe_w_m, "across": road - 0.4, "along_x": false,
				})
	return out


## Bordillos: solo por los tramos rectos, retranqueados del cruce. Un bordillo
## que sigue de largo por dentro de una interseccion parte el cruce en dos.
static func curbs(grid: Dictionary, curb_w_m: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var road: float = float(grid["road_w_m"])
	var clearance: float = road * 0.75
	for edge_data in [
		{"rect": Rect2(grid["block"]), "inset": 0.0},
		{"rect": Rect2(grid["road_outer"]), "inset": -curb_w_m},
	]:
		var rect: Rect2 = Rect2(edge_data["rect"]).grow(float(edge_data["inset"]))
		var x0: float = rect.position.x
		var x1: float = rect.position.x + rect.size.x
		var z0: float = rect.position.y
		var z1: float = rect.position.y + rect.size.y
		if x1 - x0 > clearance * 2.0:
			out.append(Rect2(x0 + clearance, z0 - curb_w_m * 0.5, x1 - x0 - clearance * 2.0, curb_w_m))
			out.append(Rect2(x0 + clearance, z1 - curb_w_m * 0.5, x1 - x0 - clearance * 2.0, curb_w_m))
		if z1 - z0 > clearance * 2.0:
			out.append(Rect2(x0 - curb_w_m * 0.5, z0 + clearance, curb_w_m, z1 - z0 - clearance * 2.0))
			out.append(Rect2(x1 - curb_w_m * 0.5, z0 + clearance, curb_w_m, z1 - z0 - clearance * 2.0))
	return out


## Datos del lado hacia el que mira una fachada: por donde corre la calle, hasta
## donde llega y a que distancia queda la acera de enfrente.
##
## `outward` es la direccion que va del edificio hacia la calle.
static func side_for(grid: Dictionary, outward: Vector2) -> Dictionary:
	var block: Rect2 = grid["block"]
	var road: float = float(grid["road_w_m"])
	var sidewalk: float = float(grid["sidewalk_w_m"])
	# `outward` es planta: su y es la Z del mundo.
	var along_x: bool = absf(outward.x) < absf(outward.y)
	var span: float = (block.size.x if along_x else block.size.y) + (road + sidewalk) * 2.0
	var far_line: float = road + sidewalk
	return {
		"along_x": along_x,
		"span_m": span,
		"far_offset_m": far_line,
		"road_center_offset_m": road * 0.5,
	}
