extends Node
class_name FireModel

signal fire_state(state: Dictionary)

var sim_time: float = 0.0

var hrr_kw: float = 20.0
var growth_rate: float = 0.002

var o2: float = 0.21
var smoke_mass: float = 0.0

var temp_upper: float = 20.0
var temp_lower: float = 20.0

var layer_height: float = 2.4
var room_height: float = 2.5


func step(delta: float) -> void:
	sim_time += delta

	_update_fire_growth(delta)
	_consume_o2(delta)
	_produce_smoke(delta)
	_update_temperatures(delta)
	_update_layer_height()

	print("HRR: %.1f  Temp: %.1f" % [hrr_kw, temp_upper])

	fire_state.emit(get_state())

	


func _update_fire_growth(delta: float) -> void:
	var hrr_target: float = growth_rate * sim_time * sim_time * 1000.0
	var o2_limit: float = clamp(o2 / 0.21, 0.0, 1.0)

	hrr_kw = lerpf(hrr_kw, hrr_target * o2_limit, delta)


func _consume_o2(delta: float) -> void:
	var consumption: float = hrr_kw * 0.00002 * delta
	o2 = max(o2 - consumption, 0.05)


func _produce_smoke(delta: float) -> void:
	smoke_mass += hrr_kw * 0.0001 * delta


func _update_temperatures(delta: float) -> void:
	var ambient: float = 20.0
	var heat_gain: float = hrr_kw * 0.01 * delta
	var cooling: float = max(temp_upper - ambient, 0.0) * 0.02 * delta

	temp_upper += heat_gain - cooling
	temp_upper = clamp(temp_upper, ambient, 900.0)

	temp_lower = lerpf(temp_lower, ambient + (temp_upper - ambient) * 0.25, delta * 0.5)
	temp_lower = clamp(temp_lower, ambient, temp_upper)


func _update_layer_height() -> void:
	layer_height = room_height - smoke_mass * 0.02
	layer_height = clamp(layer_height, 0.3, room_height)


func get_state() -> Dictionary:
	return {
		"HRR": hrr_kw,
		"O2": o2,
		"TempUpper": temp_upper,
		"TempLower": temp_lower,
		"LayerHeight": layer_height
	}