extends Resource
class_name RoomModel

@export var id: int = 0
@export var name: String = "Room"
@export var kind: String = "generic"

@export var width_m: float = 4.0
@export var length_m: float = 5.0
@export var height_m: float = 2.5

@export var o2: float = 0.21
@export var smoke_mass_kg: float = 0.0
@export var temp_upper_c: float = 20.0
@export var temp_lower_c: float = 20.0
@export var h_layer_m: float = 2.5

@export var hrr_kw: float = 0.0

@export var flashover_triggered: bool = false
@export var pre_flashover: bool = false
@export var backdraft_risk: bool = false

@export var fire_time_s: float = 0.0
@export var hrr_max_kw: float = 3000.0
@export var t_alpha: float = 0.012

# runtime only
var fire: FireModel = null




func get_floor_area_m2() -> float:
	return width_m * length_m


func get_volume_m3() -> float:
	return width_m * length_m * height_m


func reset_room_state() -> void:
	o2 = 0.21
	smoke_mass_kg = 0.0
	temp_upper_c = 20.0
	temp_lower_c = 20.0
	h_layer_m = height_m
	hrr_kw = 0.0
	flashover_triggered = false
	pre_flashover = false
	backdraft_risk = false
	fire = null
	fire_time_s = 0.0
	hrr_max_kw = 3000.0
	t_alpha = 0.012


func clamp_state() -> void:
	o2 = clampf(o2, 0.0, 0.21)
	smoke_mass_kg = maxf(smoke_mass_kg, 0.0)

	temp_upper_c = clampf(temp_upper_c, 20.0, 1200.0)
	temp_lower_c = clampf(temp_lower_c, 20.0, temp_upper_c)

	h_layer_m = clampf(h_layer_m, 0.0, height_m)
	hrr_kw = maxf(hrr_kw, 0.0)


func add_upper_smoke(mass_kg: float) -> void:
	smoke_mass_kg += maxf(mass_kg, 0.0)
	clamp_state()


func add_heat_to_upper(delta_temp_c: float) -> void:
	temp_upper_c += delta_temp_c
	clamp_state()


func add_upper_energy(energy_kj: float) -> void:
	var room_volume_m3: float = maxf(get_volume_m3(), 0.1)
	var delta_temp_c: float = maxf(energy_kj, 0.0) / (room_volume_m3 * 1.2)

	temp_upper_c += delta_temp_c
	clamp_state()


func consume_o2(amount: float) -> void:
	o2 -= maxf(amount, 0.0)
	clamp_state()


func to_state_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"kind": kind,
		"width_m": width_m,
		"length_m": length_m,
		"height_m": height_m,
		"floor_area_m2": get_floor_area_m2(),
		"volume_m3": get_volume_m3(),
		"o2": o2,
		"smoke_mass_kg": smoke_mass_kg,
		"temp_upper_c": temp_upper_c,
		"temp_lower_c": temp_lower_c,
		"h_layer_m": h_layer_m,
		"hrr_kw": hrr_kw,
		"flashover_triggered": flashover_triggered,
		"pre_flashover": pre_flashover,
		"backdraft_risk": backdraft_risk,
		"has_fire": fire != null
	}