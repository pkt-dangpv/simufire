extends RefCounted
class_name FireModel

# ============================================================
# FIRE MODEL
# ------------------------------------------------------------
# Modelo simple del fuego.
# Aquí viven los parámetros propios del incendio, no del edificio.
# ============================================================

# FUEL
var fuel_energy_MJ: float = 5000.0
var remaining_fuel_MJ: float = 5000.0
var max_burn_rate_kw: float = 2000.0

# Crecimiento t²
var growth_alpha_kw_s2: float = 0.05

# Techo base del fuego
var max_hrr_kw: float = 3000.0

# Energía extra disponible tras transición / ignición secundaria simple
var secondary_hrr_gain_kw: float = 2500.0

# Flashover simple
var flashover_hrr_multiplier: float = 2.2
var flashover_min_hrr_kw: float = 300.0

# Oxígeno
var o2_nominal: float = 0.209
var o2_min_for_flame: float = 0.12
var o2_consumption_kg_per_MJ: float = 0.20

# Producción de humo
var smoke_yield_kg_per_MJ: float = 0.06

# ------------------------------------------------------------
# HRR ideal por curva t²
# ------------------------------------------------------------

func compute_hrr_kw(t_s: float) -> float:
	var raw_hrr_kw: float = growth_alpha_kw_s2 * t_s * t_s
	return minf(raw_hrr_kw, max_hrr_kw)