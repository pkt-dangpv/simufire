extends RefCounted
class_name FuelObjectModel

# ============================================================
# FUEL OBJECT MODEL
# ------------------------------------------------------------
# Representa un combustible individual dentro de una sala.
# El motor podrá evaluar muchos objetos por recinto en lugar
# de asumir un único combustible monolítico por habitación.
# ============================================================

enum State {
	COLD,
	HEATING,
	PYROLYZING,
	FLAMING,
	DECAYING,
	BURNED_OUT
}

var id: String = ""
var name: String = ""
var kind: String = ""

# Ubicacion estructural para editores/visualizadores 2D.
var room_id: int = -1
var position_m: Vector2 = Vector2.ZERO
var size_m: Vector2 = Vector2.ONE
var rotation_deg: float = 0.0

# Geometría / exposición simplificadas
var footprint_m2: float = 0.0
var exposed_area_m2: float = 0.0
var elevation_m: float = 0.0

# Combustible
var fuel_energy_MJ: float = 0.0
var remaining_fuel_MJ: float = 0.0
var max_hrr_kw: float = 0.0
var ignition_temp_c: float = 320.0
var ignition_flux_kw_m2: float = 18.0

# Producción / consumo
var smoke_yield_kg_per_MJ: float = 0.00375
# Fracción de smoke_kg que es soot óptico (partículas extintas en visible, SF-AUD-008).
# K_m = 8700 m²/kg se aplica solo al soot, no al total de humo.
# 1.0 = toda la producción de humo es soot (conservador/retrocompatible).
# Madera flaming: 0.50-0.70 | PU flexible: 0.80-0.90 | PMMA: 0.60-0.75
var soot_fraction: float = 1.0
var co_yield_kg_per_MJ: float = 0.00025
# CO₂ yield base (combustion completa, φ=1). Sentinel -1.0 = usar global de contexto (SF-AUD-005).
# El modelo reduce este valor con φ (balance C: más CO → menos CO₂).
# Madera: 0.074 | PMMA: 0.088 | PU flexible: 0.057 | Global default: 0.0831 kg/MJ
var co2_yield_kg_per_MJ: float = -1.0
# HCN yield (kg/MJ). Depende del contenido de nitrogeno del combustible (SF-AUD-006).
# Madera/celulosa (~0.1% N): 0.00004  |  PU flexible (~5% N): 0.0010-0.0040
# Nylon (~12% N): 0.0030-0.0100      |  ISO 19706:2007 Tabla 1.
# 0.00004 = default residencial conservador (mezcla con predominio de celulosa).
var hcn_yield_kg_per_MJ: float = 0.00004
# Irritantes (SF-AUD-018) — yields en kg/MJ. Default 0.0 = sin contenido de Cl/irritante.
# HCl: PVC ~0.024 kg/MJ (Levin 1996); madera ~0 (sin Cl). IC50 sensory = 900 ppm.
# Acroleína: madera ~0.00002; poliuretano ~0.000025; IC50 sensory = 4 ppm.
# Formaldehído: madera ~0.000015; poliuretano ~0.00002; IC50 sensory = 250 ppm.
var hcl_yield_kg_per_MJ: float = 0.0
var acrolein_yield_kg_per_MJ: float = 0.0
var formaldehyde_yield_kg_per_MJ: float = 0.0
var o2_consumption_kg_per_MJ: float = 0.076
# Fracción radiativa del HRR en combustión bien ventilada (SF-AUD-015).
# Sentinel -1.0 = usar global hrr_chi_rad_normal del motor (default 0.35).
# Madera: 0.27-0.35 | PU flexible: 0.40-0.60 | PMMA: 0.22-0.28 | Heptano: 0.20-0.25
# Ref: SFPE Handbook Tabla 3-4.8; Markstein (1979); Hamins (1994)
var chi_rad_normal: float = -1.0

# Curva t² propia del objeto (SF-AUD-004).
# alpha_kw_s2 = -1.0 → usa el alpha global del FireModel de la sala.
# NFPA 72: lento=0.003, medio=0.012, rápido=0.047, ultra-rápido=0.188 kW/s².
var alpha_kw_s2: float = -1.0
# SF-AUD-033: curva HRR tabulada [[t_s, hrr_kw], ...] para este objeto.
# Cuando no está vacía, anula el modelo t² (alpha_kw_s2 se ignora).
# Interpolación lineal por tramos; se acotan por max_hrr_kw si > 0.
# t_s es tiempo desde la ignición del objeto (no el tiempo global de simulación).
var hrr_curve: Array = []
# SF-AUD-034: capa de carbonización (char layer) y LOI.
# Los materiales que forman char (madera, MDF, tejidos naturales) acumulan una
# capa aislante que reduce el flujo efectivo de calor al substrato virgen.
#
# char_growth_rate_m_per_kg: cuánto crece el char por kg de combustible quemado [m/kg].
#   Madera blanda ~0.003, madera dura ~0.0015, MDF ~0.002; 0.0 = sin char (plásticos).
# k_char_kw_m_k: conductividad térmica del char [kW/(m·K)].
#   0.0001 = 0.1 W/(m·K) — char de madera típico (SFPE Handbook §1-6).
#   Se usa para calcular la resistencia térmica R = char_thickness / k_char.
# loi_fraction: Limiting Oxygen Index (LOI) del material (fracción molar O2).
#   Madera 0.18–0.20, ABS 0.18, FR-ABS 0.28–0.35, Nylon 0.24; 0.0 = sin umbral.
#   Si O2_sala < loi_fraction, la llama no puede sostenerse.
# char_thickness_m: espesor actual del char [m] — ESTADO DINÁMICO, no configuración.
#   Inicializado a 0.0; aumenta durante la combustión activa.
var char_growth_rate_m_per_kg: float = 0.0
var k_char_kw_m_k: float = 0.0001
var loi_fraction: float = 0.0
var char_thickness_m: float = 0.0
# Instante de fire_time_s de la sala cuando este objeto entró en FLAMING.
# -1.0 = aún no ignita. Se asigna automáticamente al primer ciclo en FLAMING.
var t_ignition_s: float = -1.0

# Pirólisis física — modelo Tewarson/Drysdale (SF-AUD-016).
# heat_of_gasification_kj_kg = -1.0  →  usa el modelo empírico heredado (sin MLR física).
# Valores de referencia ASTM E1354 / SFPE Handbook 5ª ed.:
#   Madera seca:       q_crit=12.5 kW/m², ΔHg=640  kJ/kg, ΔHc=17 500 kJ/kg
#   PU flexible:       q_crit=10.0 kW/m², ΔHg=1300 kJ/kg, ΔHc=26 200 kJ/kg
#   PMMA:              q_crit=11.0 kW/m², ΔHg=1600 kJ/kg, ΔHc=24 900 kJ/kg
#   Nylon 6:           q_crit=15.0 kW/m², ΔHg=2400 kJ/kg, ΔHc=30 800 kJ/kg
var critical_heat_flux_kw_m2: float = 12.5
var heat_of_gasification_kj_kg: float = -1.0
var heat_of_combustion_kj_kg: float = -1.0

# Estado dinámico
var state: int = State.COLD
var surface_temp_c: float = 20.0
var incident_heat_flux_kw_m2: float = 0.0
var exposure_s: float = 0.0
var hrr_kw: float = 0.0
var autoignite_ready: bool = false
var ignited_by_object_id: String = ""
var is_primary_ignition_source: bool = false

# Fuego de charco (pool fire) — solo activo si pool_spread_rate_m2_s > 0.
# El área del charco crece a la tasa indicada hasta pool_max_area_m2 (0 = sin límite,
# se usa el área del suelo de la sala). La potencia calórica es:
#   HRR = pool_hrr_kw_m2 * pool_area_m2  (kW)
var pool_area_m2: float = 0.0           # área inicial / actual del charco (m²)
var pool_initial_area_m2: float = 0.0   # área inicial para reset
var pool_spread_rate_m2_s: float = 0.0  # tasa de expansión (m²/s); 0 = no es pool fire
var pool_hrr_kw_m2: float = 1000.0     # intensidad de quemado por área (kW/m²)
var pool_max_area_m2: float = 0.0       # límite de área (0 = usar suelo de la sala)
# SF-AUD-038: coeficiente k·β de Babrauskas (m⁻¹).  0 = modelo lineal clásico.
# Babrauskas SFPE §3.1: ṁ'' = ṁ''∞·(1−e^(−k·β·D)), D = diámetro equivalente.
# Típico: gasolina 2.1, queroseno 3.5, heptano 1.1, grasa cocina 0.8 m⁻¹.
var pool_k_beta_per_m: float = 0.0


func configure_from_legacy_room(room: RoomModel) -> void:
	if room == null:
		return

	id = "room_proxy_%d" % room.id
	name = "%s (proxy)" % room.name
	kind = room.kind
	room_id = room.id
	position_m = Vector2.ZERO
	size_m = Vector2(maxf(0.1, room.width_m), maxf(0.1, room.length_m))
	rotation_deg = 0.0
	fuel_energy_MJ = maxf(0.0, room.fuel_energy_MJ)
	remaining_fuel_MJ = fuel_energy_MJ
	max_hrr_kw = maxf(0.0, room.max_hrr_kw)
	footprint_m2 = room.floor_area_m2()
	exposed_area_m2 = footprint_m2
	ignition_temp_c = 320.0
	ignition_flux_kw_m2 = 18.0
	alpha_kw_s2 = -1.0
	t_ignition_s = -1.0
	critical_heat_flux_kw_m2 = 12.5
	heat_of_gasification_kj_kg = -1.0
	heat_of_combustion_kj_kg = -1.0


func reset_dynamic_state(ambient_temp_c: float = 20.0) -> void:
	remaining_fuel_MJ = fuel_energy_MJ
	state = State.COLD
	surface_temp_c = ambient_temp_c
	incident_heat_flux_kw_m2 = 0.0
	exposure_s = 0.0
	hrr_kw = 0.0
	autoignite_ready = false
	ignited_by_object_id = ""
	pool_area_m2 = pool_initial_area_m2


func has_remaining_fuel() -> bool:
	return remaining_fuel_MJ > 0.001


func can_ignite() -> bool:
	return has_remaining_fuel() and state != State.BURNED_OUT


func remaining_fraction() -> float:
	if fuel_energy_MJ <= 0.0:
		return 0.0
	return clampf(remaining_fuel_MJ / fuel_energy_MJ, 0.0, 1.0)
