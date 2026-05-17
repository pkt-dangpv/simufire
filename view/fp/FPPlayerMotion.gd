extends RefCounted


static func read_input_vector() -> Vector2:
	var input_vec := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_vec.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_vec.y += 1.0
	if Input.is_key_pressed(KEY_A):
		input_vec.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_vec.x += 1.0
	return input_vec.normalized()


static func horizontal_direction(camera_basis: Basis, input_vec: Vector2) -> Vector3:
	var forward := -camera_basis.z
	var right := camera_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	return (right * input_vec.x + forward * -input_vec.y).normalized()


static func next_stance(current_stance: int, stance_count: int = 3) -> int:
	return (current_stance + 1) % maxi(1, stance_count)


static func stance_height(
	stance: int,
	_stand_stance: int,
	crouch_stance: int,
	prone_stance: int,
	stand_height_m: float,
	crouch_height_m: float,
	prone_height_m: float
) -> float:
	if stance == crouch_stance:
		return crouch_height_m
	if stance == prone_stance:
		return prone_height_m
	return stand_height_m


static func stance_speed(
	stance: int,
	_stand_stance: int,
	crouch_stance: int,
	prone_stance: int,
	stand_speed_m_s: float,
	crouch_speed_m_s: float,
	prone_speed_m_s: float
) -> float:
	if stance == crouch_stance:
		return crouch_speed_m_s
	if stance == prone_stance:
		return prone_speed_m_s
	return stand_speed_m_s


static func stance_label(stance: int, crouch_stance: int, prone_stance: int) -> String:
	if stance == crouch_stance:
		return "AGACHADO"
	if stance == prone_stance:
		return "RASTRO"
	return "DE PIE"
