extends RefCounted

## Que hay en una calle, descrito como piezas.
##
## Este modulo no dibuja nada: devuelve una lista de cajas en coordenadas de
## la calle -distancia a lo largo, distancia hacia fuera, altura- y quien la
## llama las planta en el mundo. Asi la pregunta "que se ve por la ventana"
## queda separada de "como dibuja cajas esta vista".
##
## El problema que resuelve. El decorado anterior ponia una calzada de 46 m
## flanqueada por 34 m de fachadas: los doce metros que sobraban eran acera con
## nada detras, y por la ventana se veia el final del mundo. Ademas la vista se
## agotaba en una sola fila de edificios, sin nada que la cerrase por los lados
## ni nada detras.
##
## Lo que se anade, y por que:
##
##  - **Las manzanas cubren la calle entera**, partidas por bocacalles. Una
##    bocacalle no es un hueco: es lo que hace que una calle parezca larga.
##  - **Retornos en las esquinas**, perpendiculares a la calle. Es lo que
##    cierra la vista por los extremos; sin ellos se ve el canto de la ultima
##    fachada y detras el vacio.
##  - **Fila de manzanas por detras**, mas altas y desdibujadas, entre la
##    fachada de enfrente y el skyline. Da la profundidad que un plano recortado
##    no puede dar.
##  - **Vecinos a nuestro lado de la calle**, flanqueando nuestro edificio. Sin
##    ellos el nuestro es un bloque suelto en medio de la nada.
##  - **Mobiliario urbano**: farolas, senales, papeleras, bancos, bolardos,
##    alcorques y marquesina. Es lo que da escala: sin una farola de 4 m al
##    lado, un edificio de 15 puede ser de 40. El paso de cebra no esta aqui:
##    va con la calle, porque su sitio depende de donde caen los cruces.
##  - **Planta baja comercial** con escaparate y toldo, y **balcones** en las
##    plantas altas. Es lo que distingue una calle de una maqueta de bloques.
##
## Cada pieza es un diccionario:
##   name    nombre del nodo
##   t       desplazamiento a lo largo de la calle, en metros desde el centro
##   n       distancia hacia fuera desde nuestra fachada (positiva = alejandose)
##   y       altura del CENTRO de la caja sobre la rasante
##   w/h/d   ancho a lo largo de la calle, alto, fondo
##   color   color base
##   emission / energy  opcionales, para lo que se enciende de noche

## Ancho de una bocacalle. Menos que esto no se lee como calle sino como junta.
const SIDE_STREET_W_M: float = 7.0

## Fondo de una manzana de la fila de atras.
const BACK_BLOCK_DEPTH_M: float = 12.0


static func pieces(o: Dictionary) -> Array:
	var out: Array = []
	out.append_array(_front_details(o))
	out.append_array(_far_blocks(o))
	out.append_array(_corner_returns(o))
	out.append_array(_near_neighbours(o))
	out.append_array(_back_row(o))
	out.append_array(_street_furniture(o))
	return out


## --- Bajos y balcones del frente que se tiene delante ---
##
## Ese frente lo construye modulo a modulo quien llama -tiene sus ventanas, su
## portal y su cornisa-, pero le faltaba lo de la calle: el local en planta baja
## con su toldo y los balcones. Es justo el trozo que se mira desde la ventana.
static func _front_details(o: Dictionary) -> Array:
	var out: Array = []
	var modules: Array = Array(o.get("front_modules", []))
	if modules.is_empty():
		return out
	var facade_dist: float = float(o.get("facade_dist_m", 12.7))
	var height: float = float(o.get("facade_height_m", 15.0))
	for i in range(modules.size()):
		if typeof(modules[i]) != TYPE_DICTIONARY:
			continue
		var module: Dictionary = modules[i]
		out.append_array(_block_openings(
			"Front_%02d" % i,
			float(module.get("t", 0.0)),
			facade_dist,
			float(module.get("w", 4.0)),
			float(module.get("h", height)),
			o
		))
	return out


## --- Manzanas de enfrente, cubriendo la calle entera ---
##
## Se reparte el frente en manzanas del ancho pedido, separadas por bocacalles.
## El resto -ventanas, portal, cornisa- lo sigue poniendo quien llama, modulo a
## modulo; aqui va lo que faltaba: que haya frente en TODO el largo de la calle.
static func _far_blocks(o: Dictionary) -> Array:
	var out: Array = []
	if not bool(o.get("far_blocks_enabled", true)):
		return out
	var span: float = float(o.get("street_span_m", 46.0))
	var covered: float = float(o.get("front_span_m", 20.0))
	var facade_dist: float = float(o.get("facade_dist_m", 12.7))
	var height: float = float(o.get("facade_height_m", 15.0))
	var depth: float = float(o.get("block_depth_m", 10.0))
	var base: Color = o.get("block_color", Color(0.55, 0.52, 0.48, 1.0))

	# Lo que queda a cada lado del frente detallado que ya existe.
	var wing: float = (span - covered) * 0.5
	if wing <= 1.0:
		return out
	var per_side: int = maxi(1, int(round(wing / 14.0)))
	for side_i in range(2):
		var direction: float = -1.0 if side_i == 0 else 1.0
		var cursor: float = covered * 0.5
		for block_i in range(per_side):
			var remaining: float = wing - (cursor - covered * 0.5)
			if remaining <= 1.5:
				break
			# La bocacalle no puede comerse el ala entera. En una manzana
			# pequena el ala mide siete metros y una bocacalle de siete dejaba
			# cero de edificio: el remate de la calle volvia a quedarse vacio.
			var gap: float = minf(SIDE_STREET_W_M, wing * 0.35) if block_i == 0 else 0.0
			cursor += gap
			var block_w: float = minf(remaining - gap, wing / float(per_side))
			if block_w <= 2.0:
				break
			var seed: float = float(side_i * 31 + block_i * 17)
			var block_h: float = height * (0.78 + fposmod(seed * 0.271, 0.44))
			var block_d: float = depth * (0.9 + fposmod(seed * 0.117, 0.6))
			var tint: Color = base.lightened(fposmod(seed * 0.091, 0.12) - 0.05)
			out.append({
				"name": "SideStreetBlock_%d_%d" % [side_i, block_i],
				"t": direction * (cursor + block_w * 0.5),
				"n": facade_dist + block_d * 0.5,
				"y": block_h * 0.5,
				"w": block_w - 0.4,
				"h": block_h,
				"d": block_d,
				"color": tint,
			})
			out.append_array(_block_openings(
				"SideStreetBlock_%d_%d" % [side_i, block_i],
				direction * (cursor + block_w * 0.5),
				facade_dist,
				block_w - 0.4,
				block_h,
				o
			))
			cursor += block_w
	return out


## --- Retornos de esquina ---
##
## Perpendiculares a la calle, en los dos extremos. Son los que cierran la
## vista: sin ellos se ve el canto de la ultima fachada y detras el cielo.
static func _corner_returns(o: Dictionary) -> Array:
	var out: Array = []
	if not bool(o.get("corner_returns_enabled", true)):
		return out
	var span: float = float(o.get("street_span_m", 46.0))
	var facade_dist: float = float(o.get("facade_dist_m", 12.7))
	var height: float = float(o.get("facade_height_m", 15.0))
	var base: Color = o.get("block_color", Color(0.55, 0.52, 0.48, 1.0))
	var length: float = facade_dist + 8.0
	var corner_w: float = 6.5
	for side_i in range(2):
		var direction: float = -1.0 if side_i == 0 else 1.0
		var corner_h: float = height * (0.86 + 0.18 * float(side_i))
		out.append({
			"name": "CornerReturn_%d" % side_i,
			# Entera POR DETRAS del final de la calzada. Centrada en el extremo
			# se comia los ultimos 25 cm de asfalto: un canto de edificio
			# cruzando la calle, poco pero justo en el remate de la vista.
			"t": direction * (span * 0.5 + corner_w * 0.5 + 0.4),
			"n": facade_dist * 0.5 + 2.0,
			"y": corner_h * 0.5,
			"w": corner_w,
			"h": corner_h,
			"d": length,
			"color": base.darkened(0.06),
		})
	return out


## --- Vecinos a nuestro lado de la calle ---
##
## Nuestro edificio no esta solo en un solar: tiene medianeras. Se plantan dos
## cuerpos a los lados, alineados con nuestra fachada y algo mas atras, que es
## lo que se ve de reojo al asomarse.
static func _near_neighbours(o: Dictionary) -> Array:
	var out: Array = []
	if not bool(o.get("near_neighbours_enabled", true)):
		return out
	var own_half: float = float(o.get("own_facade_half_m", 11.0))
	var height: float = float(o.get("facade_height_m", 15.0))
	var base: Color = o.get("block_color", Color(0.55, 0.52, 0.48, 1.0))
	var depth: float = 11.0
	for side_i in range(2):
		var direction: float = -1.0 if side_i == 0 else 1.0
		var neighbour_w: float = 13.0 + 4.0 * float(side_i)
		var neighbour_h: float = height * (0.92 + 0.16 * float(side_i))
		out.append({
			"name": "NearNeighbour_%d" % side_i,
			"t": direction * (own_half + neighbour_w * 0.5 + 0.3),
			"n": -depth * 0.5 + 0.4,
			"y": neighbour_h * 0.5,
			"w": neighbour_w,
			"h": neighbour_h,
			"d": depth,
			"color": base.darkened(0.10 + 0.04 * float(side_i)),
		})
	return out


## --- Fila de atras ---
##
## Entre la fachada de enfrente y el skyline plano. Son volumenes sordos, sin
## ventanas: a esa distancia lo que se lee es la silueta.
static func _back_row(o: Dictionary) -> Array:
	var out: Array = []
	var count: int = int(o.get("back_block_count", 5))
	if count <= 0:
		return out
	var span: float = float(o.get("street_span_m", 46.0))
	var facade_dist: float = float(o.get("facade_dist_m", 12.7))
	var height: float = float(o.get("facade_height_m", 15.0))
	var base: Color = o.get("back_block_color", Color(0.45, 0.47, 0.52, 1.0))
	var row_dist: float = facade_dist + float(o.get("block_depth_m", 10.0)) + 9.0
	var pitch: float = (span * 1.25) / float(count)
	for i in range(count):
		var t: float = (float(i) + 0.5) / float(count) - 0.5
		var seed: float = float(i * 41 + 7)
		var block_h: float = height * (1.05 + fposmod(seed * 0.193, 0.85))
		out.append({
			"name": "BackBlock_%02d" % i,
			"t": t * span * 1.25,
			"n": row_dist + fposmod(seed * 0.37, 7.0) + BACK_BLOCK_DEPTH_M * 0.5,
			"y": block_h * 0.5,
			"w": pitch * 0.82,
			"h": block_h,
			"d": BACK_BLOCK_DEPTH_M,
			"color": base.lightened(fposmod(seed * 0.13, 0.10)),
		})
	return out


## --- Planta baja comercial y balcones de una manzana ---
static func _block_openings(prefix: String, t: float, facade_dist: float, width: float, height: float, o: Dictionary) -> Array:
	var out: Array = []
	var night: bool = bool(o.get("night", false))
	var shop_color: Color = o.get("shopfront_color", Color(0.18, 0.21, 0.24, 1.0))
	var lit: Color = o.get("shop_lit_color", Color(1.0, 0.86, 0.58, 1.0))
	var awning: Color = o.get("awning_color", Color(0.52, 0.20, 0.18, 1.0))
	if bool(o.get("shopfronts_enabled", true)) and width > 3.0:
		var shop_w: float = width * 0.62
		out.append({
			"name": "Shopfront_" + prefix,
			"t": t,
			"n": facade_dist - 0.06,
			"y": 1.35,
			"w": shop_w,
			"h": 2.30,
			"d": 0.10,
			"color": lit if night else shop_color,
			"emission": lit,
			"energy": 0.9 if night else 0.12,
		})
		out.append({
			"name": "Awning_" + prefix,
			"t": t,
			"n": facade_dist - 0.55,
			"y": 2.85,
			"w": shop_w + 0.5,
			"h": 0.12,
			"d": 1.05,
			"color": awning,
		})
	if bool(o.get("balconies_enabled", true)) and height > 6.0:
		var floors: int = clampi(int((height - 3.6) / 2.85), 1, 5)
		var balcony_color: Color = o.get("balcony_color", Color(0.28, 0.29, 0.30, 1.0))
		for f in range(floors):
			var y: float = 3.9 + float(f) * 2.85
			if y > height - 1.2:
				break
			out.append({
				"name": "Balcony_%s_%d" % [prefix, f],
				"t": t,
				"n": facade_dist - 0.45,
				"y": y,
				"w": minf(width * 0.55, 3.4),
				"h": 0.95,
				"d": 0.85,
				"color": balcony_color,
			})
	return out


## --- Mobiliario urbano ---
##
## Da escala y ritmo. Sin una farola de cuatro metros al lado, un edificio de
## quince puede ser de cuarenta: el ojo no tiene con que medirlo.
static func _street_furniture(o: Dictionary) -> Array:
	var out: Array = []
	var span: float = float(o.get("street_span_m", 46.0))
	var sidewalk: float = float(o.get("sidewalk_w_m", 2.6))
	var road: float = float(o.get("road_w_m", 7.5))
	var curb: float = float(o.get("curb_h_m", 0.14))
	var near_n: float = sidewalk * 0.45
	var far_n: float = sidewalk + road + sidewalk * 0.55
	var metal: Color = o.get("street_metal_color", Color(0.22, 0.24, 0.25, 1.0))
	var lamp_light: Color = o.get("lamp_light_color", Color(1.0, 0.86, 0.56, 1.0))
	var night: bool = bool(o.get("night", false))

	# Farolas alternadas a los dos lados: es como se colocan de verdad.
	var lamp_count: int = int(o.get("lamp_count", 6))
	for i in range(lamp_count):
		var t: float = (float(i) + 0.5) / float(lamp_count) * span - span * 0.5
		var on_near: bool = i % 2 == 0
		var n: float = near_n if on_near else far_n
		var prefix: String = "StreetLamp_%02d" % i
		out.append({"name": prefix + "_Post", "t": t, "n": n, "y": curb + 2.15,
			"w": 0.14, "h": 4.30, "d": 0.14, "color": metal})
		var arm_dir: float = 1.0 if on_near else -1.0
		out.append({"name": prefix + "_Arm", "t": t, "n": n + arm_dir * 0.45, "y": curb + 4.28,
			"w": 0.10, "h": 0.10, "d": 0.95, "color": metal})
		out.append({
			"name": prefix + "_Head", "t": t, "n": n + arm_dir * 0.88, "y": curb + 4.18,
			"w": 0.34, "h": 0.16, "d": 0.52,
			"color": lamp_light if night else Color(0.72, 0.74, 0.74, 1.0),
			"emission": lamp_light,
			"energy": 1.6 if night else 0.0,
		})

	# Alcorques con arbol: el arbol lo pone quien llama, aqui va el bordillo.
	for i in range(int(o.get("planter_count", 4))):
		var t: float = (float(i) + 0.5) / maxf(1.0, float(o.get("planter_count", 4))) * span - span * 0.5
		out.append({"name": "Planter_%02d" % i, "t": t + 1.8, "n": far_n, "y": curb + 0.08,
			"w": 1.10, "h": 0.18, "d": 1.10, "color": o.get("planter_color", Color(0.30, 0.28, 0.24, 1.0))})

	# Papeleras, bancos y bolardos.
	for i in range(int(o.get("bin_count", 3))):
		var t: float = span * (float(i) / maxf(1.0, float(int(o.get("bin_count", 3)) - 1)) - 0.5) * 0.72
		out.append({"name": "Bin_%02d" % i, "t": t, "n": near_n, "y": curb + 0.42,
			"w": 0.44, "h": 0.84, "d": 0.44, "color": o.get("bin_color", Color(0.20, 0.30, 0.24, 1.0))})
	for i in range(int(o.get("bench_count", 2))):
		var t: float = span * (0.28 if i == 0 else -0.34)
		out.append({"name": "Bench_%02d_Seat" % i, "t": t, "n": far_n, "y": curb + 0.44,
			"w": 1.80, "h": 0.08, "d": 0.50, "color": o.get("bench_color", Color(0.42, 0.30, 0.20, 1.0))})
		out.append({"name": "Bench_%02d_Back" % i, "t": t, "n": far_n + 0.22, "y": curb + 0.68,
			"w": 1.80, "h": 0.42, "d": 0.07, "color": o.get("bench_color", Color(0.42, 0.30, 0.20, 1.0))})
	for i in range(int(o.get("bollard_count", 8))):
		var t: float = (float(i) + 0.5) / maxf(1.0, float(int(o.get("bollard_count", 8)))) * span - span * 0.5
		out.append({"name": "Bollard_%02d" % i, "t": t, "n": sidewalk - 0.35, "y": curb + 0.42,
			"w": 0.16, "h": 0.84, "d": 0.16, "color": metal})

	# Senales de trafico.
	for i in range(int(o.get("sign_count", 2))):
		var t: float = span * (-0.40 if i == 0 else 0.40)
		var n: float = near_n if i == 0 else far_n
		out.append({"name": "TrafficSign_%02d_Post" % i, "t": t, "n": n, "y": curb + 1.15,
			"w": 0.07, "h": 2.30, "d": 0.07, "color": metal})
		out.append({"name": "TrafficSign_%02d_Plate" % i, "t": t, "n": n, "y": curb + 2.30,
			"w": 0.62, "h": 0.62, "d": 0.04, "color": o.get("sign_color", Color(0.86, 0.88, 0.90, 1.0))})

	# Marquesina de autobus en la acera de enfrente.
	if bool(o.get("bus_stop_enabled", true)):
		var stop_t: float = float(o.get("bus_stop_offset_m", 9.0))
		var glass: Color = o.get("bus_stop_glass_color", Color(0.62, 0.72, 0.78, 0.42))
		out.append({"name": "BusStop_Roof", "t": stop_t, "n": far_n, "y": curb + 2.42,
			"w": 3.60, "h": 0.10, "d": 1.35, "color": metal})
		out.append({"name": "BusStop_Back", "t": stop_t, "n": far_n + 0.60, "y": curb + 1.25,
			"w": 3.60, "h": 2.30, "d": 0.06, "color": glass})
		for side_i in range(2):
			out.append({
				"name": "BusStop_Side_%d" % side_i,
				"t": stop_t + (-1.72 if side_i == 0 else 1.72),
				"n": far_n, "y": curb + 1.25,
				"w": 0.08, "h": 2.30, "d": 1.30, "color": metal,
			})
		out.append({
			"name": "BusStop_Panel", "t": stop_t + 1.72, "n": far_n - 0.30, "y": curb + 1.40,
			"w": 0.08, "h": 1.70, "d": 0.95,
			"color": o.get("lamp_light_color", Color(1.0, 0.86, 0.56, 1.0)) if night else Color(0.30, 0.34, 0.36, 1.0),
			"emission": o.get("lamp_light_color", Color(1.0, 0.86, 0.56, 1.0)),
			"energy": 1.1 if night else 0.0,
		})
	return out
