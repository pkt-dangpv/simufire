extends RefCounted

const SmokeBridgeMesh := preload("res://view/3d/smoke/SmokeBridgeMesh.gd")

const DEFAULT_SMOKE_COLOR := Color(0.38, 0.40, 0.42, 0.20)
const DEFAULT_HOT_OUTFLOW_COLOR := Color(1.0, 0.46, 0.16, 0.24)
const DEFAULT_COLD_INFLOW_COLOR := Color(0.18, 0.52, 1.0, 0.09)
const MIN_CURTAIN_ALPHA: float = 0.012
const MIN_INFLOW_ALPHA: float = 0.010


static func update(item_dict: Dictionary, op: OpeningModel, room_items: Dictionary, settings: Dictionary) -> void:
	var curtain := item_dict.get("smoke_curtain") as MeshInstance3D
	if curtain == null:
		return
	var inflow := item_dict.get("air_inflow_curtain") as MeshInstance3D
	var plume := item_dict.get("smoke_exterior_plume") as MeshInstance3D

	var pose: Dictionary = Dictionary(item_dict.get("curtain_pose", {}))
	if pose.is_empty() or op == null:
		_hide_opening_layers(curtain, inflow, plume)
		return

	var first_person_overlay: bool = bool(settings.get("first_person_overlay", false))
	var open_frac: float = op.effective_open_fraction()
	if open_frac <= 0.0 \
			or not bool(settings.get("show_smoke_volume", true)) \
			or not bool(settings.get("show_smoke_opening_curtains", true)) \
			or (first_person_overlay and not bool(settings.get("show_smoke_geometry_in_first_person", false))):
		_hide_opening_layers(curtain, inflow, plume)
		return

	var item_a: Dictionary = room_items.get(op.a, {})
	var item_b: Dictionary = room_items.get(op.b, {})
	if item_a.is_empty() and item_b.is_empty():
		_hide_opening_layers(curtain, inflow, plume)
		return

	var context: Dictionary = _context_from(pose, settings)
	context["opening_curtain_flow_strength"] = float(settings.get("opening_curtain_flow_strength", 0.42))
	context["opening_curtain_flow_speed"] = float(settings.get("opening_curtain_flow_speed", 0.24))
	context["opening_curtain_edge_band"] = float(settings.get("opening_curtain_edge_band", 0.55))
	context["opening_curtain_edge_softness"] = float(settings.get("opening_curtain_edge_softness", 0.40))
	context["show_exterior_smoke_plume"] = bool(settings.get("show_exterior_smoke_plume", true))
	context["opening_curtain_follows_leaf"] = bool(settings.get("opening_curtain_follows_leaf", true))
	context["opening_curtain_min_width_ratio"] = float(settings.get("opening_curtain_min_width_ratio", 0.12))
	context["opening_curtain_alpha_open_exponent"] = float(settings.get("opening_curtain_alpha_open_exponent", 1.0))
	context["opening_inflow_max_alpha"] = float(settings.get("opening_inflow_max_alpha", 0.085))
	context["opening_curtain_first_person_alpha_factor"] = float(settings.get("opening_curtain_first_person_alpha_factor", 0.72))
	context["opening_curtain_first_person_side_visibility"] = float(settings.get("opening_curtain_first_person_side_visibility", 0.08))
	context["opening_curtain_first_person_bottom_strength"] = float(settings.get("opening_curtain_first_person_bottom_strength", 0.46))
	context["opening_curtain_alpha_factor"] = float(settings.get("opening_curtain_alpha_factor", 0.52))
	context["exterior_plume_min_height_m"] = float(settings.get("exterior_plume_min_height_m", 0.55))
	context["exterior_plume_max_height_m"] = float(settings.get("exterior_plume_max_height_m", 3.60))
	context["exterior_plume_alpha_factor"] = float(settings.get("exterior_plume_alpha_factor", 0.62))
	context["exterior_plume_first_person_alpha_factor"] = float(settings.get("exterior_plume_first_person_alpha_factor", 0.78))
	context["neutral_plane_calm_fraction"] = float(settings.get("neutral_plane_calm_fraction", 0.58))
	context["neutral_plane_driven_fraction"] = float(settings.get("neutral_plane_driven_fraction", 0.44))
	context["neutral_plane_exterior_calm_fraction"] = float(settings.get("neutral_plane_exterior_calm_fraction", 0.62))
	context["neutral_plane_exterior_driven_fraction"] = float(settings.get("neutral_plane_exterior_driven_fraction", 0.40))
	context["opening_inflow_requires_outflow"] = bool(settings.get("opening_inflow_requires_outflow", false))
	context["exterior_plume_hot_tint"] = float(settings.get("exterior_plume_hot_tint", 0.18))
	context["exterior_plume_laminar_turbulence"] = float(settings.get("exterior_plume_laminar_turbulence", 0.30))
	context["exterior_plume_turbulent_turbulence"] = float(settings.get("exterior_plume_turbulent_turbulence", 1.15))
	context["exterior_plume_min_speed"] = float(settings.get("exterior_plume_min_speed", 0.10))
	context["exterior_plume_max_speed"] = float(settings.get("exterior_plume_max_speed", 0.62))
	context["exterior_plume_edge_softness"] = float(settings.get("exterior_plume_edge_softness", 0.72))
	context["exterior_plume_side_visibility"] = float(settings.get("exterior_plume_side_visibility", 0.34))
	context["exterior_plume_requires_curtain"] = bool(settings.get("exterior_plume_requires_curtain", false))
	context["exterior_plume_min_source_alpha"] = float(settings.get("exterior_plume_min_source_alpha", 0.05))
	context["opening_curtain_hot_tint"] = float(settings.get("opening_curtain_hot_tint", 0.18))
	context["opening_curtain_side_visibility"] = float(settings.get("opening_curtain_side_visibility", 0.22))
	context["exterior_opening_curtain_depth_m"] = float(settings.get("exterior_opening_curtain_depth_m", 0.30))
	context["exterior_opening_curtain_outward_shift"] = float(settings.get("exterior_opening_curtain_outward_shift", 0.55))
	context["exterior_door_curtain_outward_shift"] = float(settings.get("exterior_door_curtain_outward_shift", 0.0))
	if bool(pose.get("is_vertical", false)) or op.is_vertical:
		_hide_layer(inflow)
		_hide_layer(plume)
		_update_vertical(curtain, pose, item_a, item_b, open_frac, context)
	else:
		_update_horizontal(curtain, inflow, plume, pose, op, item_a, item_b, open_frac, context)


static func _update_horizontal(
	curtain: MeshInstance3D,
	inflow: MeshInstance3D,
	plume: MeshInstance3D,
	pose: Dictionary,
	op: OpeningModel,
	item_a: Dictionary,
	item_b: Dictionary,
	open_frac: float,
	context: Dictionary
) -> void:
	var height_a: float = _room_height(item_a, 2.4)
	var height_b: float = _room_height(item_b, height_a)
	var bottom_a: float = _smoke_bottom(item_a, height_a, height_b)
	var bottom_b: float = _smoke_bottom(item_b, height_b, height_a)
	var alpha_a: float = _smoke_alpha(item_a)
	var alpha_b: float = _smoke_alpha(item_b)
	var source_alpha: float = _horizontal_source_alpha(alpha_a, alpha_b, item_a.is_empty() or item_b.is_empty())
	# Cuando la geometria ya lleva la fraccion de apertura, atenuar ademas la
	# opacidad por el mismo factor la contaria dos veces: media puerta se veria
	# como media cortina a media densidad. El exponente lo decide el inspector.
	var curtain_alpha: float = source_alpha * pow(
		clampf(open_frac, 0.0, 1.0),
		clampf(float(context.get("opening_curtain_alpha_open_exponent", 1.0)), 0.0, 1.0)
	)

	var pose_size: Vector3 = Vector3(pose["size"])
	var thin_axis_is_x: bool = pose_size.x <= pose_size.z
	var full_width_m: float = maxf(pose_size.x, pose_size.z)
	# H-5: la hoja tapa parte del vano. El humo pasa por el hueco libre, que
	# esta del lado de la CERRADURA: la hoja gira sobre su bisagra y su
	# proyeccion sobre el plano del hueco arranca justo ahi.
	var leaf_gap: Vector2 = _leaf_free_gap(op, full_width_m, open_frac, context)
	var opening_width_m: float = leaf_gap.x
	var leaf_shift_m: float = leaf_gap.y
	var door_height_m: float = pose_size.y
	var blend_depth_m: float = maxf(
		minf(pose_size.x, pose_size.z),
		float(context.get("smoke_opening_blend_depth_m", 1.55)) * lerpf(0.58, 1.0, open_frac)
	)
	if op.is_exterior_opening():
		# En un hueco a fachada el puente NO debe ser un volumen a caballo del
		# muro: forzarle 0,54 m de fondo lo convierte en un cajon que asoma
		# medio dentro y medio fuera de la habitacion, que es justo lo que se
		# ve como "un rectangulo tridimensional en la ventana". Lo que hay que
		# ensenar es humo LLENANDO el hueco, y por encima el penacho que sale.
		# Asi que aqui el fondo se ACOTA al espesor del propio hueco.
		blend_depth_m = clampf(
			float(context.get("exterior_opening_curtain_depth_m", 0.30)),
			0.05,
			blend_depth_m
		)

	var pos3: Vector3 = Vector3(pose["position"])
	var opening_bottom_m: float = pos3.y - door_height_m * 0.5
	var opening_top_m: float = pos3.y + door_height_m * 0.5
	var bottom_pair: Vector2 = _oriented_bottoms(item_a, item_b, bottom_a, bottom_b, opening_bottom_m, opening_top_m, thin_axis_is_x)
	var flow_direction: float = _horizontal_flow_direction(item_a, item_b, thin_axis_is_x)
	var neutral_plane_m: float = _horizontal_neutral_plane_m(op, item_a, item_b, opening_bottom_m, opening_top_m, context)
	var has_missing_side: bool = item_a.is_empty() or item_b.is_empty()
	bottom_pair = _flow_limited_bottoms(
		bottom_pair,
		flow_direction,
		opening_bottom_m,
		opening_top_m,
		neutral_plane_m,
		has_missing_side
	)
	var curtain_bottom_m: float = minf(bottom_pair.x, bottom_pair.y)
	var curtain_depth_m: float = maxf(0.0, opening_top_m - curtain_bottom_m)
	var smoke_min_visible_depth_m: float = float(context.get("smoke_min_visible_depth_m", 0.05))
	var curtain_visible: bool = curtain_depth_m > smoke_min_visible_depth_m and curtain_alpha > MIN_CURTAIN_ALPHA
	curtain.visible = curtain_visible

	var curtain_center_y: float = curtain_bottom_m + curtain_depth_m * 0.5
	var meters_to_units: float = float(context.get("meters_to_units", 1.0))
	# En un hueco a fachada la mitad interior del puente se superpone al
	# volumen de humo de la sala (doble alfa en la jamba) y solo la mitad
	# exterior aporta informacion: se desplaza el puente hacia la calle.
	var outward_sign: float = 0.0
	var curtain_shift := Vector3.ZERO
	if absf(leaf_shift_m) > 0.0001:
		if thin_axis_is_x:
			curtain_shift.z = leaf_shift_m
		else:
			curtain_shift.x = leaf_shift_m
	if op.is_exterior_opening():
		outward_sign = _exterior_outward_sign(item_a if not item_a.is_empty() else item_b, pos3, thin_axis_is_x)
		# Con 0,32 el puente queda a caballo del muro: medio dentro y medio
		# fuera, que es lo que se lee como un cajon metido en la ventana. La
		# mitad interior ademas no aporta nada, porque ese volumen ya lo pinta
		# el humo de la sala. Con 0,55 el puente queda pegado por fuera y lo
		# que se ve es humo saliendo.
		# Una VENTANA da a la calle: empujar la lamina hacia fuera hace que se
		# lea como humo saliendo. Una PUERTA exterior de vivienda da al rellano,
		# que es un espacio cerrado: alli el mismo empujon deja la lamina
		# flotando en mitad del portal y vuelve a leerse como un rectangulo. Por
		# eso cada tipo tiene su propio desplazamiento.
		var shift_key: String = "exterior_door_curtain_outward_shift" if op.type == OpeningModel.Type.DOOR else "exterior_opening_curtain_outward_shift"
		var shift_default: float = 0.0 if op.type == OpeningModel.Type.DOOR else 0.55
		var shift_m: float = blend_depth_m * float(context.get(shift_key, shift_default)) * outward_sign
		if thin_axis_is_x:
			curtain_shift.x = shift_m
		else:
			curtain_shift.z = shift_m
	if curtain_visible:
		curtain.mesh = SmokeBridgeMesh.create(
			thin_axis_is_x,
			opening_width_m,
			blend_depth_m,
			bottom_pair.x - curtain_center_y,
			bottom_pair.y - curtain_center_y,
			opening_top_m - curtain_center_y,
			meters_to_units
		)

	var first_person_overlay: bool = bool(context.get("first_person_overlay", false))
	var fire_context_t: float = _fire_context_strength(item_a, item_b)
	if curtain_visible:
		# La cortina se dibuja tambien en primera persona (el visor 3D corre como
		# overlay), y alli necesita su propia calibracion: se mira desde debajo
		# de la capa y a un metro del vano, no desde fuera de la casa (FP-7).
		var fp_alpha_factor: float = float(context.get("opening_curtain_first_person_alpha_factor", 0.72))
		var shader_alpha: float = clampf(
			curtain_alpha * (
				fp_alpha_factor if first_person_overlay
				else float(context.get("opening_curtain_alpha_factor", 0.52))
			),
			0.035,
			0.38
		)
		_apply_smoke_material(
			curtain,
			_curtain_color(context, fire_context_t),
			shader_alpha,
			{
				"density": clampf(0.44 + curtain_alpha * 1.15 + fire_context_t * 0.20, 0.34, 1.18),
				"turbulence": 0.88,
				"drift_speed": 0.14 + fire_context_t * 0.08,
				"volume_depth_m": maxf(curtain_depth_m, 0.05),
				"meters_to_units": float(context.get("meters_to_units", 1.0)),
				"edge_softness": float(context.get("opening_curtain_edge_softness", 0.62)),
				"bottom_waviness": 0.48,
				"edge_band_strength": float(context.get("opening_curtain_edge_band", 0.55)),
				"side_visibility": float(context.get(
					"opening_curtain_first_person_side_visibility" if first_person_overlay else "opening_curtain_side_visibility",
					0.08 if first_person_overlay else 0.22
				)),
				"bottom_surface_strength": float(context.get("opening_curtain_first_person_bottom_strength", 0.46)) if first_person_overlay else 0.28,
				"top_visibility": 0.0,
				"vertical_gradient_strength": 0.74,
				"lower_density_floor": 0.24,
				"flow_strength": clampf((0.14 + absf(alpha_a - alpha_b) * 0.55 + fire_context_t * 0.10) * (float(context.get("opening_curtain_flow_strength", 0.42)) / 0.42), 0.0, 1.0),
				"flow_speed": float(context.get("opening_curtain_flow_speed", 0.24)) + fire_context_t * 0.10,
				"flow_direction": flow_direction,
			},
			clampf(curtain_alpha * 0.52, 0.035, 0.38)
		)
		curtain.position = _to_world(
			Vector3(
				pos3.x + curtain_shift.x,
				float(context.get("floor_level_m", 0.0)) + curtain_center_y,
				pos3.z + curtain_shift.z
			),
			meters_to_units,
			Vector2(context.get("origin_offset_m", Vector2.ZERO))
		)

	_update_lower_inflow(
		inflow,
		context,
		thin_axis_is_x,
		opening_width_m,
		blend_depth_m,
		opening_bottom_m,
		neutral_plane_m,
		pos3,
		open_frac,
		source_alpha,
		absf(_flow_score(item_a) - _flow_score(item_b)),
		fire_context_t,
		-flow_direction,
		curtain_visible
	)

	_update_exterior_plume(
		plume,
		context,
		op,
		thin_axis_is_x,
		opening_width_m,
		opening_top_m,
		pos3,
		open_frac,
		source_alpha,
		fire_context_t,
		outward_sign,
		curtain_visible
	)


## Planta no representada en el estado: se asume limpia, a la altura y la
## cota que sugiere la planta conocida, para que el hueco vertical siga
## teniendo dos extremos con los que construir el penacho (H-7).
static func _absent_floor_item(known: Dictionary) -> Dictionary:
	var height_m: float = _room_height(known, 2.4)
	var known_floor_m: float = float(known.get("floor_level_m", 0.0))
	return {
		"floor_level_m": known_floor_m + height_m,
		"height_m": height_m,
		"smoke_alpha": 0.0,
		"smoke_bottom_m": height_m,
	}


## Hueco libre que deja la hoja: devuelve (ancho_util, desplazamiento) sobre
## el eje del vano. Con la puerta entornada el humo no atraviesa la hoja,
## pasa por el hueco que queda al lado de la cerradura.
static func _leaf_free_gap(
	op: OpeningModel,
	full_width_m: float,
	open_frac: float,
	context: Dictionary
) -> Vector2:
	if not bool(context.get("opening_curtain_follows_leaf", true)):
		return Vector2(full_width_m, 0.0)
	if op == null or op.is_vertical:
		return Vector2(full_width_m, 0.0)
	var frac: float = clampf(open_frac, 0.0, 1.0)
	var min_ratio: float = clampf(float(context.get("opening_curtain_min_width_ratio", 0.12)), 0.0, 1.0)
	var ratio: float = maxf(frac, min_ratio)
	if ratio >= 0.999:
		return Vector2(full_width_m, 0.0)
	var free_width_m: float = full_width_m * ratio
	# hinge_side nombra el lado de la bisagra; el hueco queda en el contrario.
	var hinge_left: bool = String(op.hinge_side).strip_edges().to_lower() != "right"
	var latch_sign: float = 1.0 if hinge_left else -1.0
	return Vector2(free_width_m, (full_width_m - free_width_m) * 0.5 * latch_sign)


static func _update_lower_inflow(
	inflow: MeshInstance3D,
	context: Dictionary,
	thin_axis_is_x: bool,
	opening_width_m: float,
	blend_depth_m: float,
	opening_bottom_m: float,
	neutral_plane_m: float,
	pos3: Vector3,
	open_frac: float,
	source_alpha: float,
	drive_delta: float,
	fire_context_t: float,
	flow_direction: float,
	outflow_visible: bool
) -> void:
	if inflow == null:
		return
	if not bool(context.get("show_cold_air_inflow_curtains", false)):
		inflow.visible = false
		return

	var smoke_min_visible_depth_m: float = float(context.get("smoke_min_visible_depth_m", 0.05))
	var inflow_top_m: float = clampf(neutral_plane_m - 0.015, opening_bottom_m, neutral_plane_m)
	var inflow_depth_m: float = maxf(0.0, inflow_top_m - opening_bottom_m)
	# H-4: esto exigia que la cortina de SALIDA hubiese superado su propio
	# umbral de visibilidad en el mismo fotograma. Medido con contadores sobre
	# el piso patron: 9 llamadas, 0 con esa condicion cumplida, 0 cortinas de
	# aire visibles. La contracorriente no se dibujaba nunca, y no por su
	# opacidad sino por este enganche.
	#
	# La condicion fisica es que haya humo empujando y desequilibrio entre las
	# dos salas, que es justo lo que comprueba el resto de la expresion. El
	# acoplamiento con la malla de salida queda como opcion del inspector.
	var requires_outflow: bool = bool(context.get("opening_inflow_requires_outflow", false))
	var has_fire_context: bool = (outflow_visible or not requires_outflow) \
		and source_alpha > 0.045 \
		and (fire_context_t > 0.040 or drive_delta > 0.12 or source_alpha > 0.11)
	# El tope decide si la contracorriente se lee o no: con 0,085 la cortina se
	# dibuja pero a un 3-8 % de opacidad, es decir, practicamente invisible.
	var inflow_max_alpha: float = float(context.get("opening_inflow_max_alpha", 0.085))
	var inflow_alpha: float = clampf(
		(source_alpha * 0.10 + drive_delta * 0.020 + fire_context_t * 0.030) * open_frac,
		0.0,
		maxf(0.0, inflow_max_alpha)
	)
	inflow.visible = has_fire_context and inflow_depth_m > smoke_min_visible_depth_m and inflow_alpha > MIN_INFLOW_ALPHA
	if not inflow.visible:
		return

	var inflow_center_y: float = opening_bottom_m + inflow_depth_m * 0.5
	var meters_to_units: float = float(context.get("meters_to_units", 1.0))
	inflow.mesh = SmokeBridgeMesh.create(
		thin_axis_is_x,
		opening_width_m,
		blend_depth_m * 0.82,
		opening_bottom_m - inflow_center_y,
		opening_bottom_m - inflow_center_y,
		inflow_top_m - inflow_center_y,
		meters_to_units
	)
	var shader_alpha: float = clampf(inflow_alpha, 0.018, maxf(0.02, inflow_max_alpha * 2.1))
	_apply_smoke_material(
		inflow,
		Color(context.get("cold_air_inflow_color", DEFAULT_COLD_INFLOW_COLOR)),
		shader_alpha,
		{
			"density": clampf(0.12 + drive_delta * 0.08 + fire_context_t * 0.10, 0.10, 0.32),
			"turbulence": 0.46,
			"drift_speed": 0.14,
			"volume_depth_m": maxf(inflow_depth_m, 0.05),
			"meters_to_units": float(context.get("meters_to_units", 1.0)),
			"edge_softness": 0.58,
			"bottom_waviness": 0.18,
			"edge_band_strength": 0.16,
			"side_visibility": 0.24,
			"bottom_surface_strength": 0.06,
			"top_visibility": 0.0,
			"vertical_gradient_strength": 0.14,
			"lower_density_floor": 0.34,
			"flow_strength": clampf(0.18 + drive_delta * 0.36 + fire_context_t * 0.16, 0.16, 0.46),
			"flow_speed": 0.28 + fire_context_t * 0.10,
			"flow_direction": flow_direction,
		},
		clampf(inflow_alpha * 0.50, 0.010, 0.055)
	)
	inflow.position = _to_world(
		Vector3(pos3.x, float(context.get("floor_level_m", 0.0)) + inflow_center_y, pos3.z),
		meters_to_units,
		Vector2(context.get("origin_offset_m", Vector2.ZERO))
	)


static func _update_vertical(
	curtain: MeshInstance3D,
	pose: Dictionary,
	item_a: Dictionary,
	item_b: Dictionary,
	open_frac: float,
	context: Dictionary
) -> void:
	# H-7: basta con que UNA de las dos plantas este representada. Antes, un
	# hueco vertical hacia una planta ausente del estado no mostraba humo
	# aunque la de abajo estuviese cargada. La ausente se toma como limpia.
	if item_a.is_empty() and item_b.is_empty():
		curtain.visible = false
		return
	if item_a.is_empty():
		item_a = _absent_floor_item(item_b)
	elif item_b.is_empty():
		item_b = _absent_floor_item(item_a)

	var smoke_min_visible_depth_m: float = float(context.get("smoke_min_visible_depth_m", 0.05))
	var floor_a_m: float = float(item_a.get("floor_level_m", 0.0))
	var floor_b_m: float = float(item_b.get("floor_level_m", 0.0))
	var lower_item: Dictionary = item_a if floor_a_m <= floor_b_m else item_b
	var upper_item: Dictionary = item_b if floor_a_m <= floor_b_m else item_a
	var lower_floor_m: float = minf(floor_a_m, floor_b_m)
	var upper_floor_m: float = maxf(floor_a_m, floor_b_m)
	var lower_height_m: float = _room_height(lower_item, 2.4)
	var upper_height_m: float = _room_height(upper_item, 2.4)
	var lower_bottom_m: float = _smoke_bottom(lower_item, lower_height_m, lower_height_m)
	var upper_bottom_m: float = _smoke_bottom(upper_item, upper_height_m, upper_height_m)
	var lower_alpha: float = _smoke_alpha(lower_item)
	var upper_alpha: float = _smoke_alpha(upper_item)
	var lower_depth_m: float = maxf(0.0, lower_height_m - lower_bottom_m)
	var upper_depth_m: float = maxf(0.0, upper_height_m - upper_bottom_m)
	var curtain_alpha: float = maxf(lower_alpha * 0.92, upper_alpha * 0.58) * open_frac
	if lower_depth_m <= smoke_min_visible_depth_m and upper_depth_m <= smoke_min_visible_depth_m:
		curtain.visible = false
		return

	var start_local_m: float = clampf(
		lower_bottom_m,
		maxf(0.12, lower_height_m - 1.45),
		maxf(0.16, lower_height_m - 0.04)
	)
	var start_abs_m: float = lower_floor_m + start_local_m
	var top_abs_m: float = upper_floor_m + maxf(0.45, upper_height_m - 0.08)
	var plume_height_m: float = maxf(0.0, top_abs_m - start_abs_m)
	curtain.visible = plume_height_m > smoke_min_visible_depth_m and curtain_alpha > MIN_CURTAIN_ALPHA
	if not curtain.visible:
		return

	var pose_size: Vector3 = Vector3(pose["size"])
	var opening_width_m: float = maxf(0.18, pose_size.x)
	var opening_depth_m: float = maxf(0.18, pose_size.z)
	var meters_to_units: float = float(context.get("meters_to_units", 1.0))
	var pos3: Vector3 = Vector3(pose["position"])
	var center_abs_y_m: float = start_abs_m + plume_height_m * 0.5

	curtain.mesh = SmokeBridgeMesh.create_vertical(opening_width_m, opening_depth_m, plume_height_m, meters_to_units)
	var first_person_overlay: bool = bool(context.get("first_person_overlay", false))
	var shader_alpha: float = clampf(curtain_alpha * (0.82 if first_person_overlay else 0.58), 0.035, 0.44)
	_apply_smoke_material(
		curtain,
		Color(context.get("smoke_color", DEFAULT_SMOKE_COLOR)),
		shader_alpha,
		{
			"density": clampf(0.62 + curtain_alpha * 1.34 + lower_depth_m * 0.08, 0.54, 1.42),
			"turbulence": 0.96,
			"drift_speed": 0.24,
			"volume_depth_m": maxf(plume_height_m, 0.05),
			"meters_to_units": float(context.get("meters_to_units", 1.0)),
			"edge_softness": 0.42,
			"bottom_waviness": 0.66,
			"edge_band_strength": 0.62,
			"side_visibility": 0.24 if first_person_overlay else 0.58,
			"bottom_surface_strength": 0.08,
			"top_visibility": 0.0,
			"vertical_gradient_strength": 0.90,
			"lower_density_floor": 0.18,
			"flow_strength": 0.86,
			"flow_speed": 0.62,
			"flow_direction": 0.0,
		},
		clampf(curtain_alpha * 0.52, 0.035, 0.40)
	)
	curtain.position = _to_world(
		Vector3(pos3.x, center_abs_y_m, pos3.z),
		meters_to_units,
		Vector2(context.get("origin_offset_m", Vector2.ZERO))
	)


static func _context_from(pose: Dictionary, settings: Dictionary) -> Dictionary:
	return {
		"smoke_opening_blend_depth_m": float(settings.get("smoke_opening_blend_depth_m", 1.55)),
		"smoke_min_visible_depth_m": float(settings.get("smoke_min_visible_depth_m", 0.05)),
		"meters_to_units": float(settings.get("meters_to_units", 1.0)),
		"origin_offset_m": settings.get("origin_offset_m", Vector2.ZERO),
		"smoke_color": settings.get("smoke_color", DEFAULT_SMOKE_COLOR),
		"hot_smoke_outflow_color": settings.get("hot_smoke_outflow_color", DEFAULT_HOT_OUTFLOW_COLOR),
		"cold_air_inflow_color": settings.get("cold_air_inflow_color", DEFAULT_COLD_INFLOW_COLOR),
		"show_cold_air_inflow_curtains": bool(settings.get("show_cold_air_inflow_curtains", false)),
		"floor_level_m": float(pose.get("floor_level_m", 0.0)),
		"first_person_overlay": bool(settings.get("first_person_overlay", false)),
	}


static func _room_height(item: Dictionary, fallback_m: float) -> float:
	return float(item.get("height_m", fallback_m)) if not item.is_empty() else fallback_m


static func _smoke_bottom(item: Dictionary, own_height_m: float, fallback_m: float) -> float:
	return float(item.get("smoke_bottom_m", own_height_m)) if not item.is_empty() else fallback_m


static func _smoke_alpha(item: Dictionary) -> float:
	return float(item.get("smoke_alpha", 0.0)) if not item.is_empty() else 0.0


static func _horizontal_source_alpha(alpha_a: float, alpha_b: float, has_missing_side: bool) -> float:
	if has_missing_side:
		return maxf(alpha_a, alpha_b) * 0.88
	return maxf(alpha_a, alpha_b) * 0.72 + minf(alpha_a, alpha_b) * 0.28


## Reparto del vano entre salida de humo y entrada de aire.
##
## El plano neutro solo recorta el lado que EXPULSA: el que recibe conserva su
## propia interfaz de capa, de modo que el hueco se lee como una cuna (humo
## alto en el lado limpio, humo bajo en el lado cargado) en vez de como una
## banda plana a media puerta. Si las dos salas estan enhumadas hasta el
## umbral no hay contracorriente que dibujar y la puerta pasa humo a plena
## altura, que es lo que se ve en una vivienda ya invadida.
static func _flow_limited_bottoms(
	bottoms: Vector2,
	flow_direction: float,
	opening_bottom_m: float,
	opening_top_m: float,
	neutral_plane_m: float,
	has_missing_side: bool
) -> Vector2:
	if opening_top_m - opening_bottom_m <= 0.75:
		return bottoms
	if has_missing_side:
		# Hueco a fachada: siempre hay plano neutro (sale humo arriba, entra
		# aire abajo), tambien con la sala enhumada hasta el suelo.
		return Vector2(maxf(bottoms.x, neutral_plane_m), maxf(bottoms.y, neutral_plane_m))
	if flow_direction > 0.0:
		return Vector2(maxf(bottoms.x, _effective_neutral_m(bottoms.y, opening_bottom_m, neutral_plane_m)), bottoms.y)
	if flow_direction < 0.0:
		return Vector2(bottoms.x, maxf(bottoms.y, _effective_neutral_m(bottoms.x, opening_bottom_m, neutral_plane_m)))
	var balanced_neutral: float = _effective_neutral_m(minf(bottoms.x, bottoms.y), opening_bottom_m, neutral_plane_m)
	return Vector2(maxf(bottoms.x, balanced_neutral), maxf(bottoms.y, balanced_neutral))


## Plano neutro efectivo. Solo hay contracorriente mientras el lado que
## RECIBE conserva aire limpio bajo el dintel: segun su interfaz de capa baja
## hacia el umbral, el plano neutro se hunde con ella y el vano acaba pasando
## humo a plena altura, sin el salto seco de un umbral binario.
static func _effective_neutral_m(
	receiving_bottom_m: float,
	opening_bottom_m: float,
	neutral_plane_m: float
) -> float:
	var band_m: float = maxf(0.15, neutral_plane_m - opening_bottom_m)
	var logged_t: float = clampf((neutral_plane_m - receiving_bottom_m) / band_m, 0.0, 1.0)
	return lerpf(neutral_plane_m, opening_bottom_m, logged_t)


## Signo (+1/-1) del eje fino del vano que apunta hacia el exterior, deducido
## de la posicion del hueco respecto al centro de su sala.
static func _exterior_outward_sign(item: Dictionary, pos3: Vector3, thin_axis_is_x: bool) -> float:
	if item.is_empty():
		return 0.0
	var rect := Rect2(item.get("rect", Rect2()))
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return 0.0
	var room_axis: float = rect.position.x + rect.size.x * 0.5 if thin_axis_is_x else rect.position.y + rect.size.y * 0.5
	var opening_axis: float = pos3.x if thin_axis_is_x else pos3.z
	if absf(opening_axis - room_axis) < 0.001:
		return 0.0
	return 1.0 if opening_axis > room_axis else -1.0


## Penacho exterior. El humo que sale por una ventana no se queda en una losa
## rectangular delante del hueco: sube pegado a la fachada, se inclina hacia
## fuera y se abre. Sin esto, el puente de humo terminaba en un corte plano a
## la altura del dintel, que es lo que se percibe como "poco natural".
static func _update_exterior_plume(
	plume: MeshInstance3D,
	context: Dictionary,
	op: OpeningModel,
	thin_axis_is_x: bool,
	opening_width_m: float,
	opening_top_m: float,
	pos3: Vector3,
	open_frac: float,
	source_alpha: float,
	fire_context_t: float,
	outward_sign: float,
	curtain_visible: bool
) -> void:
	if plume == null:
		return
	# El penacho dependia de que la cortina del hueco hubiese superado SU umbral
	# de visibilidad, igual que la contracorriente (H-4). Eso lo hace aparecer y
	# desaparecer de golpe en vez de crecer con el incendio. Lo que debe
	# gobernarlo es que haya humo saliendo, que es lo que mide source_alpha.
	var requires_curtain: bool = bool(context.get("exterior_plume_requires_curtain", false))
	if not bool(context.get("show_exterior_smoke_plume", true)) \
			or op == null \
			or not op.is_exterior_opening() \
			or (requires_curtain and not curtain_visible) \
			or source_alpha <= float(context.get("exterior_plume_min_source_alpha", 0.05)) \
			or absf(outward_sign) < 0.5:
		_hide_layer(plume)
		return

	var drive_t: float = clampf(source_alpha * 1.35 + fire_context_t * 0.85, 0.0, 1.0)
	var plume_alpha: float = clampf(source_alpha * 0.68 * open_frac, 0.0, 0.32)
	var height_m: float = lerpf(
		float(context.get("exterior_plume_min_height_m", 0.55)),
		float(context.get("exterior_plume_max_height_m", 3.60)),
		drive_t
	) * lerpf(0.60, 1.0, open_frac)
	plume.visible = plume_alpha > MIN_CURTAIN_ALPHA and height_m > 0.30
	if not plume.visible:
		return

	var meters_to_units: float = float(context.get("meters_to_units", 1.0))
	var depth_m: float = clampf(opening_width_m * 0.55, 0.35, 1.30)
	var span_m: float = maxf(0.25, opening_width_m * 0.92)
	plume.mesh = SmokeBridgeMesh.create_vertical(
		depth_m if thin_axis_is_x else span_m,
		span_m if thin_axis_is_x else depth_m,
		height_m,
		meters_to_units
	)

	var first_person_overlay: bool = bool(context.get("first_person_overlay", false))
	var shader_alpha: float = clampf(
		plume_alpha * float(context.get(
			"exterior_plume_first_person_alpha_factor" if first_person_overlay else "exterior_plume_alpha_factor",
			0.78 if first_person_overlay else 0.62
		)),
		0.030,
		0.36
	)
	# El humo que sale por un hueco es el MISMO humo de la sala: parte de su
	# color y solo admite un sesgo caliente pequeno. Antes se mezclaba hasta un
	# 58 % hacia el naranja y el penacho se leia como una losa anaranjada sin
	# relacion con la habitacion de la que sale.
	var plume_color: Color = _plume_color(context, fire_context_t)
	# Regimen: con poco empuje la columna sale lisa (laminar) y lenta; con
	# mucho, revuelta y rapida. drive_t ya combina carga de humo y contexto de
	# fuego, que es el mejor proxy de presion disponible aqui.
	var turbulence: float = lerpf(
		float(context.get("exterior_plume_laminar_turbulence", 0.30)),
		float(context.get("exterior_plume_turbulent_turbulence", 1.15)),
		drive_t
	)
	var speed_t: float = lerpf(
		float(context.get("exterior_plume_min_speed", 0.10)),
		float(context.get("exterior_plume_max_speed", 0.62)),
		drive_t
	)
	_apply_smoke_material(
		plume,
		plume_color,
		shader_alpha,
		{
			"density": clampf(0.40 + plume_alpha * 1.20 + fire_context_t * 0.26, 0.32, 1.10),
			"turbulence": turbulence,
			"drift_speed": speed_t,
			"volume_depth_m": maxf(height_m, 0.05),
			"meters_to_units": float(context.get("meters_to_units", 1.0)),
			"edge_softness": float(context.get("exterior_plume_edge_softness", 0.72)),
			"bottom_waviness": 0.30,
			"edge_band_strength": 0.20,
			# Costados menos visibles: con 0,68 las cuatro caras del volumen se
			# leian a la vez y el penacho parecia una caja.
			"side_visibility": float(context.get("exterior_plume_side_visibility", 0.34)),
			"bottom_surface_strength": 0.10,
			"top_visibility": 0.0,
			"vertical_gradient_strength": 0.30,
			"lower_density_floor": 0.70,
			"flow_strength": clampf(0.24 + drive_t * 0.56, 0.0, 0.90),
			"flow_speed": 0.30 + speed_t * 0.60,
			"flow_direction": 0.0,
		},
		clampf(plume_alpha * 0.50, 0.030, 0.32)
	)

	# El penacho arranca en el dintel, a un palmo de la fachada, y se inclina
	# hacia fuera con la altura; el centro se recoloca para que la base siga
	# anclada al hueco pese a la inclinacion.
	var lean_rad: float = deg_to_rad(12.0) * outward_sign
	var lean_offset_m: float = height_m * 0.5 * sin(absf(lean_rad)) * outward_sign
	var stand_off_m: float = (0.26 + depth_m * 0.5) * outward_sign
	var center_y_m: float = opening_top_m - 0.12 + height_m * 0.5 * cos(lean_rad)
	var plume_pos := Vector3(pos3.x, float(context.get("floor_level_m", 0.0)) + center_y_m, pos3.z)
	if thin_axis_is_x:
		plume_pos.x += stand_off_m + lean_offset_m
		plume.rotation = Vector3(0.0, 0.0, -lean_rad)
	else:
		plume_pos.z += stand_off_m + lean_offset_m
		plume.rotation = Vector3(lean_rad, 0.0, 0.0)
	plume.position = _to_world(plume_pos, meters_to_units, Vector2(context.get("origin_offset_m", Vector2.ZERO)))


static func _horizontal_neutral_plane_m(
	op: OpeningModel,
	item_a: Dictionary,
	item_b: Dictionary,
	opening_bottom_m: float,
	opening_top_m: float,
	context: Dictionary = {}
) -> float:
	# Altura del plano neutro dentro del vano, como fraccion de su alto: donde
	# se separan el humo que sale por arriba y el aire que entra por abajo. Con
	# mas desequilibrio entre salas el plano baja, porque el hueco pasa mas
	# humo. Es el parametro central de H-2, asi que vive en el inspector.
	var drive: float = clampf(absf(_flow_score(item_a) - _flow_score(item_b)) / 2.0, 0.0, 1.0)
	var calm: float = float(context.get("neutral_plane_calm_fraction", 0.58))
	var driven: float = float(context.get("neutral_plane_driven_fraction", 0.44))
	if op != null and op.is_exterior_opening():
		calm = float(context.get("neutral_plane_exterior_calm_fraction", 0.62))
		driven = float(context.get("neutral_plane_exterior_driven_fraction", 0.40))
	var neutral_fraction: float = lerpf(calm, driven, drive)
	return lerpf(opening_bottom_m, opening_top_m, neutral_fraction)


static func _horizontal_flow_direction(item_a: Dictionary, item_b: Dictionary, thin_axis_is_x: bool) -> float:
	var score_a: float = _flow_score(item_a)
	var score_b: float = _flow_score(item_b)
	if absf(score_a - score_b) < 0.035:
		return 0.0
	if item_a.is_empty() or item_b.is_empty():
		return 1.0 if score_a >= score_b else -1.0
	var rect_a := Rect2(item_a.get("rect", Rect2()))
	var rect_b := Rect2(item_b.get("rect", Rect2()))
	var axis_a: float = rect_a.position.x + rect_a.size.x * 0.5 if thin_axis_is_x else rect_a.position.y + rect_a.size.y * 0.5
	var axis_b: float = rect_b.position.x + rect_b.size.x * 0.5 if thin_axis_is_x else rect_b.position.y + rect_b.size.y * 0.5
	var a_on_negative_side: bool = axis_a <= axis_b
	var source_is_a: bool = score_a >= score_b
	return 1.0 if source_is_a == a_on_negative_side else -1.0


static func _flow_score(item: Dictionary) -> float:
	if item.is_empty():
		return 0.0
	var alpha: float = float(item.get("smoke_alpha", 0.0))
	var temp_c: float = maxf(0.0, float(item.get("temp_upper_c", 20.0)) - 20.0)
	var pressure_pa: float = float(item.get("overpressure_pa", 0.0))
	var hrr_kw: float = maxf(0.0, float(item.get("hrr_kw", 0.0)))
	return alpha * 2.0 \
		+ clampf(temp_c / 500.0, 0.0, 1.2) \
		+ clampf(sqrt(hrr_kw / 1200.0), 0.0, 0.80) \
		+ clampf(pressure_pa / 35.0, -0.35, 0.65)


static func _fire_context_strength(item_a: Dictionary, item_b: Dictionary) -> float:
	var alpha_t: float = maxf(_smoke_alpha(item_a), _smoke_alpha(item_b))
	var temp_t: float = maxf(
		maxf(0.0, float(item_a.get("temp_upper_c", 20.0)) - 35.0),
		maxf(0.0, float(item_b.get("temp_upper_c", 20.0)) - 35.0)
	)
	var hrr_t: float = maxf(
		maxf(0.0, float(item_a.get("hrr_kw", 0.0))),
		maxf(0.0, float(item_b.get("hrr_kw", 0.0)))
	)
	return clampf(
		maxf(
			alpha_t * 1.25,
			maxf(clampf(temp_t / 360.0, 0.0, 1.0), clampf(sqrt(hrr_t / 1500.0), 0.0, 1.0))
		),
		0.0,
		1.0
	)


## Color de la cortina del vano. El humo que cruza un hueco es el MISMO humo
## de la sala: parte de su color y solo admite un sesgo caliente pequeno. Antes
## se mezclaba hasta un 58 % hacia el naranja y el vano se leia como una caja
## anaranjada sin relacion con la habitacion de la que sale.
static func _curtain_color(context: Dictionary, fire_context_t: float) -> Color:
	var base := Color(context.get("smoke_color", DEFAULT_SMOKE_COLOR))
	var hot := Color(context.get("hot_smoke_outflow_color", DEFAULT_HOT_OUTFLOW_COLOR))
	var tint: float = clampf(float(context.get("opening_curtain_hot_tint", 0.18)), 0.0, 1.0)
	return base.lerp(hot, clampf(fire_context_t * tint, 0.0, tint))


static func _outflow_color(context: Dictionary, fire_context_t: float) -> Color:
	var base := Color(context.get("smoke_color", DEFAULT_SMOKE_COLOR))
	var hot := Color(context.get("hot_smoke_outflow_color", DEFAULT_HOT_OUTFLOW_COLOR))
	return base.lerp(hot, clampf(fire_context_t * 0.48, 0.0, 0.58))


## Color del penacho exterior: el del humo de la sala, con un sesgo caliente
## pequeno y ajustable. Es humo de la misma habitacion, no una llamarada.
static func _plume_color(context: Dictionary, fire_context_t: float) -> Color:
	var base := Color(context.get("smoke_color", DEFAULT_SMOKE_COLOR))
	var hot := Color(context.get("hot_smoke_outflow_color", DEFAULT_HOT_OUTFLOW_COLOR))
	var tint: float = clampf(float(context.get("exterior_plume_hot_tint", 0.18)), 0.0, 1.0)
	return base.lerp(hot, clampf(fire_context_t * tint, 0.0, tint))


static func _hide_opening_layers(curtain: MeshInstance3D, inflow: MeshInstance3D, plume: MeshInstance3D = null) -> void:
	_hide_layer(curtain)
	_hide_layer(inflow)
	_hide_layer(plume)


static func _hide_layer(node: MeshInstance3D) -> void:
	if node != null:
		node.visible = false


static func _oriented_bottoms(
	item_a: Dictionary,
	item_b: Dictionary,
	bottom_a_m: float,
	bottom_b_m: float,
	opening_bottom_m: float,
	opening_top_m: float,
	thin_axis_is_x: bool
) -> Vector2:
	var bottom_a_clamped: float = clampf(bottom_a_m, opening_bottom_m, opening_top_m)
	var bottom_b_clamped: float = clampf(bottom_b_m, opening_bottom_m, opening_top_m)
	if item_a.is_empty() or item_b.is_empty():
		return Vector2(bottom_a_clamped, bottom_a_clamped)

	var rect_a := Rect2(item_a.get("rect", Rect2()))
	var rect_b := Rect2(item_b.get("rect", Rect2()))
	var axis_a: float = rect_a.position.x + rect_a.size.x * 0.5 if thin_axis_is_x else rect_a.position.y + rect_a.size.y * 0.5
	var axis_b: float = rect_b.position.x + rect_b.size.x * 0.5 if thin_axis_is_x else rect_b.position.y + rect_b.size.y * 0.5
	return Vector2(bottom_a_clamped, bottom_b_clamped) if axis_a <= axis_b else Vector2(bottom_b_clamped, bottom_a_clamped)


static func _apply_smoke_material(
	node: MeshInstance3D,
	smoke_color: Color,
	shader_alpha: float,
	shader_params: Dictionary,
	fallback_alpha: float
) -> void:
	var shader := node.material_override as ShaderMaterial
	if shader != null:
		shader.set_shader_parameter("smoke_color", Color(smoke_color.r, smoke_color.g, smoke_color.b, shader_alpha))
		for key in shader_params.keys():
			shader.set_shader_parameter(String(key), shader_params[key])
		return

	var material := node.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(smoke_color.r, smoke_color.g, smoke_color.b, fallback_alpha)


static func _to_world(meters: Vector3, meters_to_units: float, origin_offset_m: Vector2) -> Vector3:
	return Vector3(
		(meters.x + origin_offset_m.x) * meters_to_units,
		meters.y * meters_to_units,
		(meters.z + origin_offset_m.y) * meters_to_units
	)
