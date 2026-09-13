extends SceneTree
## Guardarrail de las TEXTURAS PROPIAS.
##
## El mundo se pinta con ruido procedural, pero hay tres ranuras en el inspector
## para traer texturas de material real sin tocar codigo:
##
##   surface_noise_texture_override  -> muros, techos y volumenes
##   floor_noise_texture_override    -> pavimentos de vivienda
##   landing_tile_texture_override   -> baldosa del rellano y el portal
##
## Lo que se fija aqui:
##
##  1. **Cada ranura llega a su superficie**, y solo a la suya: si las tres
##     colgaran del mismo campo, el suelo saldria con la textura del muro y
##     nadie veria un error, solo un mundo raro.
##  2. **Una textura propia manda sobre `use_procedural_surface_noise`.** Ese
##     interruptor apaga el ruido GENERADO, no una foto elegida a mano. Iban por
##     la misma puerta, asi que la ranura se vaciaba en silencio justo para quien
##     traia texturas propias (medido, no supuesto).
##  3. **Sin ranura puesta se sigue usando el procedural**, que es el aspecto por
##     defecto del producto.
##  4. **Una pieza marcada como "sin textura" (`noise_seed < 0`) sigue sin ella.**
##     Asi es como el decorado, los cristales y todo lo pequeno dicen que van de
##     color plano. Una ranura elige QUE textura se usa, no A QUIEN se le pone.
##
## Lo que este guardarrail NO puede decir es si la textura SE VE bien: el albedo
## se MULTIPLICA por ella, asi que una foto oscura oscurece el color de la sala.
## Eso se juzga mirando, no midiendo.
##
##   <godot> --headless --path . --script res://tools/validate_texture_overrides.gd

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

var _frames: int = 0
var _fails: int = 0


func _eq(que: String, got, want) -> void:
	if str(got) == str(want):
		print("  ok   %s = %s" % [que, str(got)])
	else:
		print("  FAIL %s = %s (se esperaba %s)" % [que, str(got), str(want)])
		_fails += 1


## Una textura de un color plano, para poder reconocerla luego de un vistazo.
func _tex(color: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Que ranura se ha reconocido en una textura, por su color.
func _etiqueta(tex: Texture2D) -> String:
	if tex == null:
		return "ninguna"
	var img: Image = tex.get_image()
	if img == null:
		# Un `NoiseTexture2D` se genera en segundo plano: que aun no tenga imagen
		# ya dice que es el procedural, no una de las nuestras.
		return "procedural"
	var c: Color = img.get_pixel(0, 0)
	if c.r > 0.7 and c.g < 0.3 and c.b < 0.3:
		return "muro"
	if c.g > 0.7 and c.r < 0.3 and c.b < 0.3:
		return "suelo"
	if c.b > 0.7 and c.r < 0.3 and c.g < 0.3:
		return "rellano"
	return "procedural"


func _nuevo(con_override: bool, ruido: bool) -> FirstPersonController:
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.use_procedural_surface_noise = ruido
	if con_override:
		fp.surface_noise_texture_override = _tex(Color(1.0, 0.0, 0.0, 1.0))
		fp.floor_noise_texture_override = _tex(Color(0.0, 1.0, 0.0, 1.0))
		fp.landing_tile_texture_override = _tex(Color(0.0, 0.0, 1.0, 1.0))
	root.add_child(fp)
	return fp


## Las tres ranuras, leidas por el mismo camino que usa cada superficie.
func _reparto(fp: FirstPersonController) -> String:
	var partes: Array[String] = []
	for perfil in [fp.NOISE_PROFILE_SURFACE, fp.NOISE_PROFILE_FLOOR, fp.NOISE_PROFILE_TILE]:
		partes.append(_etiqueta(fp._noise_texture(4100, perfil)))
	return ",".join(partes)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	# ── 1. Cada ranura a su superficie ──
	var con: FirstPersonController = _nuevo(true, true)
	_eq("cada ranura pinta su superficie", _reparto(con), "muro,suelo,rellano")

	# ── 2. Sin ranuras, el aspecto por defecto ──
	var sin: FirstPersonController = _nuevo(false, true)
	_eq("sin ranuras, ruido procedural", _reparto(sin), "procedural,procedural,procedural")

	# ── 3. Una textura propia manda sobre el interruptor de ruido ──
	var apagado: FirstPersonController = _nuevo(true, false)
	var quiere: Array[String] = []
	for perfil in [apagado.NOISE_PROFILE_SURFACE, apagado.NOISE_PROFILE_FLOOR, apagado.NOISE_PROFILE_TILE]:
		quiere.append("si" if apagado._wants_surface_texture(4100, perfil) else "no")
	_eq("con el ruido apagado la textura propia sigue puesta", ",".join(quiere), "si,si,si")

	# Y el interruptor sigue sirviendo para lo suyo cuando no hay ranuras.
	var apagado_sin: FirstPersonController = _nuevo(false, false)
	_eq("y sin ranuras el interruptor apaga", apagado_sin._wants_surface_texture(4100, apagado_sin.NOISE_PROFILE_SURFACE), false)

	# ── 4. Una pieza que NO pide textura sigue sin llevarla ──
	#
	# `noise_seed < 0` es como el decorado, los cristales y todo lo pequeno dicen
	# "yo voy de color plano". Una ranura elige QUE textura se usa, no a quien se
	# le pone: si se saltara esa marca, poner una textura de muro texturizaria de
	# golpe cada cachivache del mundo.
	_eq("una pieza sin semilla no lleva textura", con._wants_surface_texture(-1, con.NOISE_PROFILE_SURFACE), false)

	# ── 5. Y llega hasta la geometria construida, no solo a la funcion ──
	_eq("el muro construido la lleva", _muro_construido(true), "muro")
	_eq("y sin ranura lleva la procedural", _muro_construido(false), "procedural")

	if _fails == 0:
		print("[validate_texture_overrides] PASS")
	else:
		push_error("[validate_texture_overrides] FAIL (%d)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


## El camino entero: construir una vivienda y mirar que textura lleva su muro.
func _muro_construido(con_override: bool) -> String:
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data({
		"version": 1, "building_type": "apartment", "apartment_floor_number": 1,
		"exterior_walls": [], "floors": [{"name": "R", "level_m": 0.0}],
		"room_rect_m": {"1": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}},
		"rooms_data": [{
			"id": 1, "name": "Salon", "kind": "salon", "rotation_deg": 0.0,
			"height_m": 2.5, "floor_level_z_m": 0.0, "fuel_objects": [],
		}],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {"room_id": 1, "x_m": 2.0, "y_m": 2.0}, "ignition_room_id": 1,
	})
	var host := Node3D.new()
	root.add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	if con_override:
		fp.surface_noise_texture_override = _tex(Color(1.0, 0.0, 0.0, 1.0))
	host.add_child(fp)
	fp.setup(building)
	fp.set_active(true)

	var encontrado: String = "sin muro"
	var pend: Array = [host]
	while not pend.is_empty():
		var node: Node = pend.pop_back()
		for child in node.get_children():
			pend.append(child)
		var mi := node as MeshInstance3D
		if mi == null or not String(mi.name).begins_with("Wall"):
			continue
		var material: Material = mi.get_active_material(0)
		var tex: Texture2D = null
		var sm := material as ShaderMaterial
		if sm != null:
			tex = sm.get_shader_parameter("surface_noise") as Texture2D
		var std := material as StandardMaterial3D
		if std != null:
			tex = std.albedo_texture
		encontrado = _etiqueta(tex)
		break

	host.queue_free()
	building.free()
	return encontrado
