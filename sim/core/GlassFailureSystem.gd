extends RefCounted
class_name GlassFailureSystem

# ============================================================
# GLASS FAILURE SYSTEM
# ------------------------------------------------------------
# Responsabilidad:
# - evaluar rotura de cristal por temperatura
# - asignar temperatura de rotura aleatoria por ventana
# - abrir progresivamente las ventanas tras la rotura
# ============================================================

# Dependencias externas
var _building: BuildingModel

# Parámetros de rotura de cristal
var glass_break_temp_c: float = 250.0
var glass_break_temp_spread_c: float = 80.0
var glass_open_rate_per_s: float = 0.15
var glass_max_open_fraction: float = 0.85

# Estado: opening_index → temperatura de rotura asignada aleatoriamente al inicio.
var _glass_break_temps: Dictionary = {}


func set_references(building: BuildingModel) -> void:
	_building = building


func configure(settings: Dictionary) -> void:
	glass_break_temp_c = float(settings.get("glass_break_temp_c", glass_break_temp_c))
	glass_break_temp_spread_c = float(settings.get("glass_break_temp_spread_c", glass_break_temp_spread_c))
	glass_open_rate_per_s = float(settings.get("glass_open_rate_per_s", glass_open_rate_per_s))
	glass_max_open_fraction = float(settings.get("glass_max_open_fraction", glass_max_open_fraction))


func reset() -> void:
	_glass_break_temps.clear()


# ============================================================
# STEP PRINCIPAL
# ============================================================
# Cada ventana exterior recibe una temperatura de rotura aleatoria la primera
# vez que la capa superior supera glass_break_temp_c.  El cristal se abre
# progresivamente una vez alcanzada esa temperatura personalizada.
# La aleatoriedad modela variabilidad en calidad del cristal, sombreado, etc.

func step(dt: float) -> void:
	var openings: Array = _building.get_openings()
	for i in range(openings.size()):
		var op: OpeningModel = openings[i]
		if op.type != OpeningModel.Type.WINDOW:
			continue
		# Determinar cuál lado es interior
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
		# Asignar temperatura de rotura aleatoria una sola vez por ventana
		if not _glass_break_temps.has(i):
			_glass_break_temps[i] = glass_break_temp_c + randf_range(
					-glass_break_temp_spread_c * 0.5,
					glass_break_temp_spread_c)
		var break_temp: float = _glass_break_temps[i]
		# Abrir progresivamente una vez superada la temperatura de rotura
		if room.temp_upper_c >= break_temp:
			op.open_fraction = minf(glass_max_open_fraction,
					op.open_fraction + glass_open_rate_per_s * dt)
