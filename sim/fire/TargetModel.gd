extends RefCounted
class_name TargetModel

# ============================================================
# TARGET MODEL  — SF-AUD-029
# ------------------------------------------------------------
# Objeto pasivo receptor de calor (sensor de flujo o superficie
# expuesta). Calcula el flujo neto incidente desde la capa
# superior caliente mediante radiación de Stefan-Boltzmann.
#
# Sin masa de combustible; no genera HRR ni consume O₂.
# Usado para estimar ignición secundaria o exposición de
# bomberos a radiación.
#
# q_incident = angle_factor · ε · σ · T_upper⁴
# q_emit     = ε · σ · T_target⁴
# q_net      = max(q_incident − q_emit, 0)          [kW/m²]
# ============================================================

## Identificador único del target (e.g. "target_0", "wall_panel").
var id: String = "target"

## Sala en la que se encuentra el target.
var room_id: int = 0

## Altura del target sobre el suelo [m].
## (Por ahora solo informativo; el modelo usa la capa superior de la sala.)
var height_m: float = 1.0

## Área receptora del target [m²].
var area_m2: float = 0.25

## Emisividad superficial (0–1). 0.9 = superficie oscura típica.
var emissivity: float = 0.9

## Fracción del hemisferio visible orientada hacia la capa caliente.
## 0 = apunta al suelo (no recibe radiación superior),
## 0.5 = superficie vertical (ve medio hemisferio),
## 1.0 = apunta al techo (máxima exposición).
var angle_factor: float = 0.5

## Temperatura superficial actual del target [°C].
var temp_c: float = 20.0

## Flujo neto incidente en el paso actual [kW/m²].
var qnet_kw_m2: float = 0.0

## Flujo neto máximo alcanzado durante la simulación [kW/m²].
var peak_qnet_kw_m2: float = 0.0


func reset() -> void:
	temp_c = 20.0
	qnet_kw_m2 = 0.0
	peak_qnet_kw_m2 = 0.0
