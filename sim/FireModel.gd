extends Node

signal state_changed(state: Dictionary)

# =========================
# COMPARTIMENTO
# =========================
@export var room_volume_m3: float = 60.0
@export var room_height_m: float = 2.4
@export var air_density: float = 1.2
@export var ambient_temp_c: float = 20.0
@export var ambient_o2: float = 0.209

@export var opening_width_m: float = 0.9
@export var opening_height_m: float = 2.0

# =========================
# CONTROL
# =========================
var vent_open: float = 0.0
var water_flow: float = 0.0

# =========================
# ESTADO
# =========================
var h_layer_m: float = 1.8
var temp_upper_c: float = 60.0
var temp_lower_c: float = 20.0
var o2: float = 0.209

# =========================
# FUEGO
# =========================
@export var alpha_kw_s2: float = 0.0117
@export var hrr_max_kw: float = 5000.0

var fire_time_s: float = 0.0
var hrr_kw: float = 0.0

# =========================
# COMBUSTIBLE
# =========================
@export var fuel_load_MJ: float = 500.0
var fuel_remaining_MJ: float = 500.0

# potencia máxima que el combustible puede liberar
@export var fuel_burn_rate_MJ_s: float = 2.0

# =========================
# PARÁMETROS
# =========================
@export var o2_limit_start: float = 0.15
@export var o2_floor: float = 0.10

const HEAT_PER_KG_O2_KJ: float = 13100.0

@export var base_air_exchange_ach: float = 0.2
@export var vent_air_exchange_ach: float = 12.0

@export var upper_heat_gain_c_per_kj: float = 0.002
@export var lower_coupling_s: float = 0.02

@export var layer_drop_m_per_kj: float = 0.00003
@export var layer_recover_s: float = 0.04
@export var layer_target_m: float = 2.2

@export var water_hrr_reduction_max: float = 0.55
@export var water_upper_cool_c_per_s: float = 35.0

# =========================
# EVENTOS
# =========================
@export var flashover_temp_c: float = 600.0
@export var flashover_layer_m: float = 0.7

var flashover: bool = false

@export var backdraft_o2: float = 0.12
@export var backdraft_hrr_fuel_threshold_kw: float = 800.0

var backdraft_armed: bool = false

# =========================
# API UI
# =========================
func set_vent_open(v: float) -> void:
	vent_open = clampf(v, 0.0, 1.0)

func set_water_flow(v: float) -> void:
	water_flow = clampf(v, 0.0, 1.0)

func reset() -> void:

	fire_time_s = 0.0
	hrr_kw = 0.0

	o2 = ambient_o2
	temp_upper_c = maxf(ambient_temp_c, 60.0)
	temp_lower_c = ambient_temp_c

	h_layer_m = 1.8

	fuel_remaining_MJ = fuel_load_MJ

	flashover = false
	backdraft_armed = false

	emit_state()

# =========================
# LOOP
# =========================
func _physics_process(delta: float) -> void:

	step(delta)
	emit_state()

func step(delta: float) -> void:

	fire_time_s += delta

	# =====================
	# HRR t²
	# =====================

	var hrr_fuel_kw: float = alpha_kw_s2 * fire_time_s * fire_time_s
	hrr_fuel_kw = minf(hrr_fuel_kw, hrr_max_kw)

	# =====================
	# HRR ventilación
	# =====================

	var av: float = vent_open * opening_width_m * opening_height_m
	var hv: float = opening_height_m

	var hrr_vent_kw: float = 1500.0 * av * sqrt(hv)
	hrr_vent_kw = minf(hrr_vent_kw, hrr_max_kw)

	# =====================
	# HRR combustible
	# =====================

	var hrr_fuel_limit_kw: float = fuel_burn_rate_MJ_s * 1000.0

	# =====================
	# HRR final
	# =====================

	var hrr_base_kw: float = minf(hrr_fuel_kw, minf(hrr_vent_kw, hrr_fuel_limit_kw))

	# =====================
	# limitación O2
	# =====================

	var o2_factor: float = 1.0

	if o2 < o2_limit_start:
		o2_factor = clampf(o2 / o2_limit_start, 0.0, 1.0)

	# =====================
	# agua
	# =====================

	var water_factor: float = 1.0 - water_hrr_reduction_max * water_flow
	water_factor = clampf(water_factor, 0.1, 1.0)

	hrr_kw = hrr_base_kw * o2_factor * water_factor
	hrr_kw = clampf(hrr_kw, 0.0, hrr_max_kw)

	# =====================
	# consumo combustible
	# =====================

	var energy_MJ: float = hrr_kw * delta / 1000.0
	fuel_remaining_MJ = maxf(0.0, fuel_remaining_MJ - energy_MJ)

	if fuel_remaining_MJ <= 0.0:
		hrr_kw = 0.0

	# =====================
	# consumo O2
	# =====================

	var kg_o2_cons_s: float = hrr_kw / HEAT_PER_KG_O2_KJ

	var m_air: float = room_volume_m3 * air_density
	var m_o2: float = o2 * m_air

	m_o2 = maxf(0.0, m_o2 - kg_o2_cons_s * delta)

	# ventilación

	var ach: float = base_air_exchange_ach + vent_air_exchange_ach * vent_open
	var mix_rate: float = ach / 3600.0

	m_o2 += (ambient_o2 * m_air - m_o2) * (1.0 - exp(-mix_rate * delta))

	o2 = clampf(m_o2 / m_air, o2_floor, ambient_o2)

	# =====================
	# temperatura
	# =====================

	var energy_kj: float = hrr_kw * delta

	temp_upper_c += energy_kj * upper_heat_gain_c_per_kj
	temp_upper_c += (ambient_temp_c - temp_upper_c) * (1.0 - exp(-mix_rate * delta))
	temp_upper_c = maxf(temp_lower_c, temp_upper_c - water_upper_cool_c_per_s * water_flow * delta)

	temp_lower_c += (temp_upper_c - temp_lower_c) * (1.0 - exp(-lower_coupling_s * delta))

	# =====================
	# capa humo
	# =====================

	h_layer_m -= energy_kj * layer_drop_m_per_kj

	var rec: float = layer_recover_s * vent_open
	h_layer_m += (layer_target_m - h_layer_m) * (1.0 - exp(-rec * delta))

	h_layer_m = clampf(h_layer_m, 0.2, room_height_m)

	check_flashover()
	check_backdraft(hrr_fuel_kw)

# =========================
# EVENTOS
# =========================
func check_flashover() -> void:

	if flashover:
		return

	if temp_upper_c >= flashover_temp_c and h_layer_m <= flashover_layer_m:

		flashover = true

		if o2 > 0.14:
			hrr_kw = minf(hrr_max_kw, maxf(hrr_kw, hrr_max_kw * 0.85))

func check_backdraft(hrr_fuel_kw: float) -> void:

	if not backdraft_armed:

		if o2 <= backdraft_o2 and vent_open < 0.05 and hrr_fuel_kw >= backdraft_hrr_fuel_threshold_kw:
			backdraft_armed = true

		return

	if vent_open >= 0.35:

		hrr_kw = minf(hrr_max_kw, maxf(hrr_kw, hrr_max_kw * 0.95))
		temp_upper_c = maxf(temp_upper_c, 700.0)

		backdraft_armed = false

# =========================
# OUTPUT
# =========================
func emit_state() -> void:

	state_changed.emit({
		"h_layer_m": h_layer_m,
		"temp_upper_c": temp_upper_c,
		"temp_lower_c": temp_lower_c,
		"o2": o2,
		"hrr_kw": hrr_kw,
		"fuel_remaining_MJ": fuel_remaining_MJ,
		"flashover": flashover
	})
