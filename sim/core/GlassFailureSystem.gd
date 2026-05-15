extends RefCounted
class_name GlassFailureSystem

# ============================================================
# GLASS FAILURE SYSTEM  (SF-AUD-011)
# ------------------------------------------------------------
# Modos de rotura automatica (glass_break_mode):
#
#   DISABLED (0) — las ventanas nunca se rompen por temperatura.
#
#   DETERMINISTIC (1) — cada ventana recibe una temperatura de rotura
#     asignada una vez: glass_break_temp_c ± glass_break_temp_spread_c.
#     Se rompe al instante en que T_upper supera ese umbral.
#
#   PROBABILISTIC (2) — modelo de hazard rate continuo.
#     No hay umbral fijo. La tasa de rotura instantanea es:
#
#       f_temp  = clamp((T - T_start) / (T_ref - T_start), 0, ∞)^exp
#       λ(t)    = λ_base × f_temp × (1 + t_exp / τ_exp)
#
#     donde t_exp es el tiempo acumulado con T > T_start.
#     Probabilidad de rotura en dt:  P = 1 − exp(−λ × dt)
#
#     Esto modela la variabilidad real del cristal residencial:
#     - Mayor temperatura → rotura mas probable cada segundo
#     - Mayor exposicion acumulada → fatiga termica, probabilidad sube
#     - Sin umbral fijo → algunos cristales aguantan mas que otros
# ============================================================

const MODE_DISABLED      := 0
const MODE_DETERMINISTIC := 1
const MODE_PROBABILISTIC := 2

# Dependencias externas
var _building: BuildingModel

# Parametros
var glass_break_mode: int = MODE_DISABLED
var glass_break_temp_c: float = 250.0
var glass_break_temp_spread_c: float = 80.0
var glass_open_rate_per_s: float = 0.15
var glass_max_open_fraction: float = 0.85

# Parametros modo PROBABILISTIC
var glass_break_exposure_start_temp_c: float = 100.0
var glass_break_hazard_base_per_s: float = 0.008
var glass_break_hazard_temp_exp: float = 2.0
var glass_break_hazard_exposure_tau_s: float = 120.0

# Estado por ventana
## Temperatura de rotura asignada aleatoriamente (modo DETERMINISTIC).
var _glass_break_temps: Dictionary = {}
## Tiempo acumulado de exposicion a temperatura >= exposure_start_temp_c (modo PROBABILISTIC).
var _glass_exposure_s: Dictionary = {}
## Indices de aperturas que se han roto en el step actual.
var newly_broken_indices: Array[int] = []


func set_references(building: BuildingModel) -> void:
	_building = building


func configure(settings: Dictionary) -> void:
	glass_break_mode = int(settings.get("glass_break_mode", glass_break_mode))
	glass_break_temp_c = float(settings.get("glass_break_temp_c", glass_break_temp_c))
	glass_break_temp_spread_c = float(settings.get("glass_break_temp_spread_c", glass_break_temp_spread_c))
	glass_open_rate_per_s = float(settings.get("glass_open_rate_per_s", glass_open_rate_per_s))
	glass_max_open_fraction = float(settings.get("glass_max_open_fraction", glass_max_open_fraction))
	glass_break_exposure_start_temp_c = float(settings.get("glass_break_exposure_start_temp_c", glass_break_exposure_start_temp_c))
	glass_break_hazard_base_per_s = float(settings.get("glass_break_hazard_base_per_s", glass_break_hazard_base_per_s))
	glass_break_hazard_temp_exp = float(settings.get("glass_break_hazard_temp_exp", glass_break_hazard_temp_exp))
	glass_break_hazard_exposure_tau_s = float(settings.get("glass_break_hazard_exposure_tau_s", glass_break_hazard_exposure_tau_s))


func reset() -> void:
	_glass_break_temps.clear()
	_glass_exposure_s.clear()


# ============================================================
# STEP PRINCIPAL
# ============================================================

func step(dt: float) -> void:
	newly_broken_indices.clear()
	if glass_break_mode == MODE_DISABLED:
		return

	var openings: Array = _building.get_openings()
	for i in range(openings.size()):
		var op: OpeningModel = openings[i]
		if op.type != OpeningModel.Type.WINDOW:
			continue
		var indoor_id: int = -1
		if op.b == BuildingModel.OUTSIDE_ID:
			indoor_id = op.a
		elif op.a == BuildingModel.OUTSIDE_ID:
			indoor_id = op.b
		else:
			continue
		var room: RoomModel = _building.get_room(indoor_id)
		if room == null:
			continue

		match glass_break_mode:
			MODE_DETERMINISTIC:
				_step_deterministic(i, op, room, dt)
			MODE_PROBABILISTIC:
				_step_probabilistic(i, op, room, dt)


# ============================================================
# MODO DETERMINISTIC
# ============================================================
# Igual al modelo original: umbral fijo por ventana con spread aleatorio.
# El cristal se abre progresivamente al superar el umbral.

func _step_deterministic(idx: int, op: OpeningModel, room: RoomModel, dt: float) -> void:
	if not _glass_break_temps.has(idx):
		_glass_break_temps[idx] = glass_break_temp_c + randf_range(
				-glass_break_temp_spread_c * 0.5,
				glass_break_temp_spread_c)
	var break_temp: float = _glass_break_temps[idx]
	if room.temp_upper_c >= break_temp:
		var was_intact: bool = op.open_fraction < 0.001
		op.open_fraction = minf(glass_max_open_fraction,
				op.open_fraction + glass_open_rate_per_s * dt)
		if was_intact:
			newly_broken_indices.append(idx)


# ============================================================
# MODO PROBABILISTIC
# ============================================================
# Hazard rate:  λ = λ_base × f_temp^exp × (1 + t_exp / τ_exp)
# donde f_temp = clamp((T - T_start) / (T_ref - T_start), 0, 10)
# P(rotura en dt) = 1 - exp(-λ · dt)
# Una vez roto, se abre progresivamente igual que el modo deterministico.

func _step_probabilistic(idx: int, op: OpeningModel, room: RoomModel, dt: float) -> void:
	# Si ya esta abierto (roto), seguir abriendo
	if op.open_fraction >= 0.001:
		op.open_fraction = minf(glass_max_open_fraction,
				op.open_fraction + glass_open_rate_per_s * dt)
		return

	var temp: float = room.temp_upper_c
	var t_start: float = glass_break_exposure_start_temp_c
	var t_ref: float = maxf(t_start + 1.0, glass_break_temp_c)

	# Acumular exposicion
	if temp >= t_start:
		_glass_exposure_s[idx] = float(_glass_exposure_s.get(idx, 0.0)) + dt
	else:
		# Enfriamiento: la exposicion decae lentamente (la fatiga termica no es
		# completamente reversible, pero algo de recuperacion hay).
		var prev: float = float(_glass_exposure_s.get(idx, 0.0))
		_glass_exposure_s[idx] = maxf(0.0, prev - dt * 0.3)

	# Calcular tasa de hazard
	var f_temp: float = clampf((temp - t_start) / (t_ref - t_start), 0.0, 10.0)
	if f_temp <= 0.0:
		return
	var f_exp: float = pow(f_temp, glass_break_hazard_temp_exp)
	var t_exp_s: float = float(_glass_exposure_s.get(idx, 0.0))
	var tau: float = maxf(1.0, glass_break_hazard_exposure_tau_s)
	var lam: float = glass_break_hazard_base_per_s * f_exp * (1.0 + t_exp_s / tau)

	# Evento de Poisson en dt
	var p_break: float = 1.0 - exp(-lam * dt)
	if randf() < p_break:
		op.open_fraction = minf(glass_max_open_fraction,
				op.open_fraction + glass_open_rate_per_s * dt)
		newly_broken_indices.append(idx)
