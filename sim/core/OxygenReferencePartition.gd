extends RefCounted

## M4-A1 PURE reference-content partition. NOT loaded by any simulation system.
## One room total M and subordinate upper U; lower L=M-U. Bases are kg O2 at
## reference mole fraction 1, NOT masses of hot gas. No rates, fuel, fire, EOS,
## transport, RoomModel writes, class_name or exports. Invalid candidates are
## refused before any result state is supplied; inputs are never mutated.

const FIELDS: Array[String] = ["total_kg", "upper_kg", "upper_base_kg", "lower_base_kg"]


static func make_state(total: Variant, upper: Variant, upper_base: Variant, lower_base: Variant) -> Dictionary:
	var state: Dictionary = {"total_kg": total, "upper_kg": upper,
		"upper_base_kg": upper_base, "lower_base_kg": lower_base}
	var reason: String = validate(state)
	if not reason.is_empty():
		return _refuse(reason)
	return {"valid": true, "state": state}


static func validate(state: Variant) -> String:
	if typeof(state) != TYPE_DICTIONARY or state.size() != FIELDS.size():
		return "state_schema"
	for field: String in FIELDS:
		if not state.has(field) or not _finite_number(state[field]):
			return "state_number:" + field
	var total: float = float(state["total_kg"])
	var upper: float = float(state["upper_kg"])
	var upper_base: float = float(state["upper_base_kg"])
	var lower_base: float = float(state["lower_base_kg"])
	var base: float = upper_base + lower_base
	if upper_base < 0.0 or lower_base < 0.0 or base <= 0.0 or not is_finite(base):
		return "state_bases"
	if total < 0.0 or upper < 0.0 or upper > total:
		return "state_inventory"
	if upper > upper_base or total - upper > lower_base:
		return "state_capacity"
	return ""


static func observables(state: Variant) -> Dictionary:
	var reason: String = validate(state)
	if not reason.is_empty():
		return _refuse(reason)
	var total: float = float(state["total_kg"])
	var upper: float = float(state["upper_kg"])
	var upper_base: float = float(state["upper_base_kg"])
	var lower_base: float = float(state["lower_base_kg"])
	return {"valid": true, "room": total / (upper_base + lower_base),
		"upper": upper / upper_base if upper_base > 0.0 else null,
		"lower": (total - upper) / lower_base if lower_base > 0.0 else null,
		"lower_kg": total - upper}


static func remap(state: Variant, new_upper_base: Variant) -> Dictionary:
	var reason: String = validate(state)
	if not reason.is_empty():
		return _refuse(reason)
	if not _finite_number(new_upper_base):
		return _refuse("remap_number")
	var total: float = float(state["total_kg"])
	var upper: float = float(state["upper_kg"])
	var old_upper_base: float = float(state["upper_base_kg"])
	var old_lower_base: float = float(state["lower_base_kg"])
	var base: float = old_upper_base + old_lower_base
	var new_upper: float = float(new_upper_base)
	if new_upper < 0.0 or new_upper > base:
		return _refuse("remap_range")
	var difference: float = new_upper - old_upper_base
	var after_upper: float = upper
	if new_upper == 0.0:
		after_upper = 0.0
	elif new_upper == base:
		after_upper = total
	elif difference >= 0.0:
		after_upper = upper + (total - upper) * (difference / old_lower_base)
	else:
		after_upper = upper * (new_upper / old_upper_base)
	var after: Dictionary = {"total_kg": total, "upper_kg": after_upper,
		"upper_base_kg": new_upper, "lower_base_kg": base - new_upper}
	var moved: float = after_upper - upper
	return _candidate(state, after, "interface_remap", moved, -moved)


static func mix(state: Variant, fraction: Variant) -> Dictionary:
	var reason: String = validate(state)
	if not reason.is_empty():
		return _refuse(reason)
	if not _finite_number(fraction):
		return _refuse("mix_number")
	var alpha: float = float(fraction)
	if alpha < 0.0 or alpha > 1.0:
		return _refuse("mix_range")
	var total: float = float(state["total_kg"])
	var upper: float = float(state["upper_kg"])
	var base: float = float(state["upper_base_kg"]) + float(state["lower_base_kg"])
	var target: float = total * (float(state["upper_base_kg"]) / base)
	var after_upper: float = upper + alpha * (target - upper)
	var after: Dictionary = state.duplicate(true)
	after["upper_kg"] = after_upper
	var moved: float = after_upper - upper
	return _candidate(state, after, "imposed_mixing", moved, -moved)


static func budget(state: Variant, upper_delta: Variant, lower_delta: Variant, cause: Variant) -> Dictionary:
	var reason: String = validate(state)
	if not reason.is_empty():
		return _refuse(reason)
	if not _finite_number(upper_delta) or not _finite_number(lower_delta):
		return _refuse("budget_number")
	if typeof(cause) != TYPE_STRING or String(cause).strip_edges().is_empty():
		return _refuse("budget_cause")
	var du: float = float(upper_delta)
	var dl: float = float(lower_delta)
	var upper: float = float(state["upper_kg"]) + du
	var lower: float = float(state["total_kg"]) - float(state["upper_kg"]) + dl
	var after: Dictionary = state.duplicate(true)
	after["total_kg"] = upper + lower
	after["upper_kg"] = upper
	return _candidate(state, after, String(cause), du, dl)


static func _candidate(before: Dictionary, after: Dictionary, cause: String, du: float, dl: float) -> Dictionary:
	var reason: String = validate(after)
	if not reason.is_empty():
		return _refuse(reason)
	return {"valid": true, "state": after.duplicate(true),
		"receipt": {"before": before.duplicate(true), "after": after.duplicate(true),
			"cause": cause, "upper_delta_kg": du, "lower_delta_kg": dl, "room_delta_kg": du + dl}}


static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func _refuse(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}
