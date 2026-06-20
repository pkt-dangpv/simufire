# Phase 3: Two-Zone Doorway Pressure ODE — Plan Técnico

**Estado:** PENDIENTE DE APROBACIÓN. No implementar hasta aprobación explícita.
**Fecha:** 2026-06-20  
**Objetivo:** Cerrar gap Grupo C corridor_chain (2 FAILs: t180, t600 temp).  
**Baseline de partida:** 343/350 PASS, 7 FAIL requeridos.

---

## 1. Diagnóstico confirmado

### Qué ocurre en t=600

| Magnitud | CFAST | SF actual | Diferencia |
|----------|-------|-----------|-----------|
| HRR R0 | 300 kW (100%) | ~204 kW (68%) | −96 kW |
| O2u R0 | 11.2% | ~9.9% | −1.3 pp |
| Temp R0 upper | ~480°C | ~420°C | −60°C |
| Umbral throttle | 10% (LOWER_OXYGEN_LIMIT) | 15% (fire_o2_full_hrr_open) | − |

**El ciclo de retroalimentación:**  
SF quema menos → consume menos O2 → pero O2u sigue más bajo que CFAST → throttle sigue activo.  
Esto implica que la **tasa de reposición de O2u en SF es mucho menor que en CFAST**, independientemente del consumo.

### Por qué SF sub-repone O2u

O2 en la zona superior del cuarto de fuego se repone exclusivamente por:

1. **Plume entrainment** (`o2_upper_plume_entr_rate`): mueve O2 de `hot.o2_lower` → `hot.o2_upper` en cada paso.  
   — Barrido Phase 2F hasta rate=0.080: max +2.9°C. Plateau. Insuficiente.

2. **Canonical Part B** (`canonical_doorway_exchange`): trae `cold.o2_lower` → `hot.lower_energy_kj + hot.o2_lower`.  
   — Barrido Phase 2G hasta multiplier=3.0: max +2.4°C antes de romper t=300. Insuficiente.

**Lo que falta:** CFAST resuelve un ODE de presión que produce:
- Sobrepresión explícita en el cuarto de fuego por expansión del gas caliente.
- Caudal de entrada más alto a través de la zona baja del vano.
- Parte de ese caudal entra en la zona alta de la sala caliente (pluma inmediata) en proporción a la profundidad de la capa.

SF no tiene ODE de presión. `overpressure_pa` es una cantidad derivada empíricamente, no integrada. El resultado es que la velocidad del flujo de entrada en el vano es sistemáticamente inferior a CFAST.

---

## 2. Estado por sala/capa — inventario actual

### Existente en RoomModel (conservado entre pasos)

```
upper_gas_kg        — masa zona superior [kg]
upper_energy_kj     — entalpía zona superior sobre ambiente [kJ]
lower_gas_kg        — masa zona inferior [kg]
lower_energy_kj     — entalpía zona inferior sobre ambiente [kJ]
o2_upper            — fracción O2 zona superior [0..0.209]
o2_lower            — fracción O2 zona inferior [0..0.209]
o2                  — promedio bulk volumétrico
overpressure_pa     — sobrepresión [Pa], actualizado empíricamente
thermal_layer_m     — altura interfaz capa caliente/fría [m]
temp_upper_c        — temperatura zona superior (derivada de upper_energy_kj / upper_gas_kg / cp)
temp_lower_c        — temperatura zona inferior (derivada de lower_energy_kj / lower_gas_kg / cp)
```

### Lo que el ODE de presión necesita añadir/modificar

```
pressure_upper_pa   — NUEVO: presión absoluta en la zona superior (a altura thermal_layer_m) [Pa]
pressure_lower_pa   — NUEVO: presión absoluta en la zona inferior (a z=0) [Pa]
```

Alternativamente: un escalar `dp_fire_pa` (sobrepresión efectiva por encima de la presión hidrostática de la sala fría).

---

## 3. Flujos por vano — modelo actual vs propuesto

### Modelo actual (`build_interior_opening_flow_state`)

```
neutral_plane_f = f(T_hot_upper, T_cold_lower, T_hot_lower, h_thermal)
h_upper = neutral_plane_f × door_height
h_lower = (1 - neutral_plane_f) × door_height

bernoulli_upper_kg_s = Cd × W × (2/3) × h_upper^(3/2) × sqrt(2g × ΔT_upper / T_ref) × ρ_hot
bernoulli_lower_kg_s = Cd × W × (2/3) × h_lower^(3/2) × sqrt(2g × ΔT_lower / T_ref) × ρ_cold
```

**Problema:** El plano neutro asume que el cuarto frío tiene temperatura uniforme `cold.temp_lower_c` en toda la altura. Cuando el cuarto de fuego tiene sobrepresión real por expansión, el plano neutro sube → más sección de salida pero también más ΔP de entrada.

### Modelo propuesto: ODE de presión simplificado

#### 3A. dp_fire por sala (sobrepresión de fuego)

Física: en un volumen fijo, la liberación de calor produce expansión → aumento de presión.

```
dp_fire/dt = (γ - 1) × HRR_kw / V_room_m3

Con γ = 1.4 (gas ideal diatómico), V_room_m3 = volumen total de la sala.
```

Esta sobrepresión se disipa por los vanos abiertos (tasa de escape).

Implementación: integrar `dp_fire_pa` como variable de estado por sala, con pérdida proporcional a la sección total de apertura abierta:
```
dp_loss_pa_s = dp_fire_pa × vent_loss_coeff × sum(op.width_m × op.height_m × op.open_fraction) / V_room_m3
dp_fire_pa += ((γ-1) × hrr_kw / V_room_m3 - dp_loss_pa_s) × dt
dp_fire_pa = maxf(0.0, dp_fire_pa)
```

#### 3B. Plano neutro corregido con dp_fire

El plano neutro actual resuelve: `P_hot(z_n) = P_cold(z_n)` usando solo perfil hidrostático de temperatura.

Con dp_fire:
```
P_hot(z) = P_atm + dp_hot - ρ_hot_upper × g × (z - thermal_layer_m) para z > thermal_layer_m
           P_atm + dp_hot - ρ_hot_upper × g × (thermal_layer_m) - ρ_hot_lower × g × (thermal_layer_m - z) para z ≤ thermal_layer_m

P_cold(z) = P_atm + dp_cold - ρ_cold × g × (z - H_cold_interface) ... [análogo]
```

Neutral plane z_n donde P_hot(z_n) = P_cold(z_n).

La diferencia clave: `dp_hot - dp_cold` eleva z_n (plano neutro más alto) → más sección de salida superior Y mayor ΔP efectivo en la sección inferior → más caudal entrante.

#### 3C. Part D: fracción de inflow hacia zona superior (pluma directa)

El gas fresco que entra por el vano inferior es inmediatamente entrainado por la pluma del fuego. En función de la profundidad de la capa caliente (cuánto del vano está bajo la interfaz), una fracción de la masa entrante sube directamente a la zona superior:

```
hot_layer_in_door_frac = clamp(1.0 - hot_room.thermal_layer_m / door_height, 0.0, 1.0)
# Fracción del vano inferior que está dentro de la zona caliente del cuarto de fuego.
# = 0 cuando thermal_layer_m ≥ door_height (capa caliente está por encima del vano)
# = 1 cuando thermal_layer_m = 0 (toda la sala es zona caliente)

direct_upper_mass_kg = inflow_mass_kg × hot_layer_in_door_frac × doorway_plume_direct_upper_frac
# doorway_plume_direct_upper_frac: parámetro nuevo, default 0.0 (no-op)
```

Este gas va directamente a `hot.upper_gas_kg + hot.upper_energy_kj + hot.o2_upper` (vía mezcla conservativa), no a `hot.lower`.

---

## 4. Conservación masa/energía/O2

### Por vano, por paso

```
OUTFLOW (hot.upper → cold.upper):
  Δm_out = bernoulli_upper_kg_s × dt × Cd_corr      [kg]
  ΔE_out = Δm_out × cp × (T_hot_upper - T_amb)      [kJ]
  ΔO2_out = Δm_out × o2_upper_hot                    [kg O2]

  hot.upper_gas_kg  -= Δm_out     (≥ 0)
  hot.upper_energy_kj -= ΔE_out   (≥ 0)
  hot.o2_upper: conservado por mezcla (Part A existente)

  cold.upper_gas_kg  += Δm_out
  cold.upper_energy_kj += ΔE_out
  cold.o2_upper: mezcla ponderada (Part A existente)


INFLOW TO LOWER (cold.lower → hot.lower):  [Part B existente]
  Δm_in = bernoulli_lower_kg_s × dt × flow_frac × multiplier    [kg]
  Δm_direct = Δm_in × hot_layer_in_door_frac × plume_direct_frac [kg]  ← NUEVO Part D
  Δm_lower = Δm_in - Δm_direct                                          [kg]

  hot.lower_energy_kj += Δm_lower × cp × (T_cold_lower - T_amb)
  hot.o2_lower: mezcla ponderada con cold.o2_lower

  hot.upper_gas_kg += Δm_direct
  hot.upper_energy_kj += Δm_direct × cp × (T_cold_lower - T_amb)  ← entra frío, se calentará por fuego
  hot.o2_upper: mezcla ponderada con cold.o2_lower

  cold.lower_gas_kg -= Δm_in      (≥ 0)
  cold.lower_energy_kj -= Δm_in × (E_specific_cold_lower)  (≥ 0)
  cold.o2_lower: conservado (fracción no cambia al perder masa uniforme)


PRESIÓN (cuarto de fuego):
  dp_fire_pa += (γ-1) × hrr_kw / V × dt
  dp_fire_pa -= dp_loss × dt
  dp_fire_pa = maxf(0.0, dp_fire_pa)


INVARIANTE DE CONSERVACIÓN:
  total_mass_building = Σ(room.upper_gas_kg + room.lower_gas_kg)
  — debe ser constante salvo infiltración exterior e ILV.
  — energy_budget_enabled=true puede verificar residuales.
```

### Tabla de conservación por componente

| Componente | Antes de Phase 3 | Después de Phase 3 |
|------------|-----------------|-------------------|
| Masa upper | Part A conserva | Part D añade pero compensa con Part B; total conservado |
| Masa lower | Part B conserva (5% cap) | Part D extrae de lower antes de llegar; total conservado |
| Energía upper | Part A conserva energía | Part D añade E fría (E_amb); se mezcla conservativamente |
| O2 upper | Part A (hot→cold); Part B→plume (lento) | Part D (cold→hot.upper directo); conservado por mezcla |
| dp_fire | no integrada | integrada; pérdida por vanos conserva presión total |

---

## 5. Flags nuevos — todos default=false/0.0 (no-op garantizado)

### ThermalSystem.gd

```gdscript
# Phase 3A: ODE de presión por sala (fuego).
# default=false = no-op exacto. Activar per-caso vía engine_overrides.
var phase3a_pressure_ode_enabled: bool = false

# Coeficiente de disipación de dp_fire por área de apertura [1/s por m²/m³].
# Solo activo cuando phase3a_pressure_ode_enabled=true.
var phase3a_pressure_vent_loss_coeff: float = 1.0

# Phase 3B: plano neutro corregido con dp_fire (requiere phase3a).
# default=false = usa plano neutro actual (sin corrección dp).
var phase3b_neutral_plane_dp_correction: bool = false

# Phase 3D: fracción del inflow inferior que va directamente a zona superior via pluma.
# 0.0 = no-op exacto (todo el inflow va a hot.lower como antes).
# Activar per-caso. No afecta si canonical_doorway_exchange_enabled=false.
var canonical_doorway_plume_direct_upper_frac: float = 0.0
```

### SimulationEngine.gd

```gdscript
@export var phase3a_pressure_ode_enabled: bool = false
@export var phase3a_pressure_vent_loss_coeff: float = 1.0
@export var phase3b_neutral_plane_dp_correction: bool = false
@export var canonical_doorway_plume_direct_upper_frac: float = 0.0
```

### RoomModel (estado por sala)

```gdscript
var dp_fire_pa: float = 0.0    # NUEVO: sobrepresión acumulada por fuego [Pa]
```

---

## 6. Activación per-caso — corridor_chain

Secuencia de activación incremental (ver Sección 8 para rollback en cada paso):

```json
// cfast_corridor_chain.json — engine_overrides ACTUALES (baseline)
{
  "canonical_doorway_exchange_enabled": true,
  "canonical_doorway_lower_flow_frac": 1.0,
  "canonical_doorway_lower_inflow_multiplier": 1.0,
  "o2_upper_plume_entr_rate": 0.025,
  "doorway_thermal_counterflow_enabled": true,
  "doorway_thermal_counterflow_gain": 0.25
}

// Phase 3A añade:
  "phase3a_pressure_ode_enabled": true,
  "phase3a_pressure_vent_loss_coeff": 1.0,

// Phase 3B añade:
  "phase3b_neutral_plane_dp_correction": true,

// Phase 3D añade:
  "canonical_doorway_plume_direct_upper_frac": 0.3,  // calibrar: 0.1..0.8
```

---

## 7. Sentinels — lista completa

Para cada paso de implementación, verificar que TODOS los siguientes casos mantienen exactamente el mismo resultado que el baseline (343/350 PASS, 7 FAIL):

| Caso | Por qué es sentinel |
|------|---------------------|
| `cfast_bedroom_closed_door` | fire_o2_full_hrr_open=0.10 activado per-caso; no debe cambiar |
| `cfast_two_room_door_open` | canonical_doorway_exchange_enabled=true; sensible a cambios en doorway exchange |
| `cfast_hvac_residential` | HVAC O2 two-zone; sensible a cambios en o2_upper/o2_lower |
| `cfast_r0_window_360` | O2 upper vs bulk; debe permanecer como VALID_GAP sin cambio |
| `cfast_slow_growth_sealed` | sealed, sin doorways interiores; no debe ser afectado |
| `cfast_pool_fire_open` | vent_bernoulli_flow_multiplier=0.45; sensible a cambios en flujo Bernoulli |
| `cfast_single_room_closed` | sin doorways; no debe ser afectado |
| `cfast_multi_fuel_couch_tv` | múltiples fuegos, sin doorways interiores activos |

**Criterio de sentinel:** cada paso debe mantener exactamente los mismos resultados en TODOS estos casos con los flags nuevos en su valor default (false/0.0).

---

## 8. Estrategia incremental

### Paso 0 — No-op + observabilidad (OBLIGATORIO antes de cualquier código)

**Objetivo:** confirmar que las variables de estado nuevas no cambian ningún resultado.

- Añadir `dp_fire_pa: float = 0.0` a RoomModel.
- Añadir flags Phase 3A/3B/3D a ThermalSystem y SimulationEngine con defaults.
- No activar nada per-caso.
- Correr suite completa → verificar 343/350 exacto.
- Log: emitir `dp_fire_pa`, `neutral_plane_f`, `bernoulli_upper_kg_s`, `bernoulli_lower_kg_s` para R0 en corridor_chain (cada log_interval_s=10s).
- Comparar `neutral_plane_f` SF vs valor teórico CFAST a t=300, t=600.

**Sentinels:** todos los 350 checks deben ser bit-idénticos al baseline (los flags son puro no-op).

### Paso 1 — Phase 3A: ODE dp_fire per-caso corridor_chain

**Activar:** `phase3a_pressure_ode_enabled=true` solo en `cfast_corridor_chain.json`.

**Verificar:**
- dp_fire_pa en R0 a t=300, t=600: rango esperado 5–50 Pa.
- bernoulli_upper_kg_s, bernoulli_lower_kg_s: ¿cambian? (No deben hasta Phase 3B).
- Suite completa con flags=default: 343/350 exacto.
- corridor_chain con flag activo: anotar cambios de O2u, temp_upper R0.

### Paso 2 — Phase 3B: corrección plano neutro per-caso corridor_chain

**Activar:** `phase3b_neutral_plane_dp_correction=true` solo en `cfast_corridor_chain.json`.

**Verificar:**
- neutral_plane_f debe subir respecto a Paso 1 (cuarto de fuego overpressured → plano neutro más alto).
- bernoulli_lower_kg_s: debe aumentar (más ΔP en zona inferior).
- bernoulli_upper_kg_s: puede cambiar (menor h_upper por neutral plane más alto, pero mayor velocidad).
- O2u R0 a t=600: debe subir hacia 11.2% (objetivo).
- Suite completa con flags=default: 343/350 exacto.
- t=180, t=600 checks corridor_chain: anotar.

**Sentinel crítico:** `cfast_two_room_door_open` no debe cambiar con flags=default.

### Paso 3 — Phase 3D: plume direct upper frac per-caso corridor_chain

Solo si Phase 3B no cierra el gap completamente.

**Barrido:** `canonical_doorway_plume_direct_upper_frac` = 0.1, 0.2, 0.3, 0.4, 0.5.

**Guard rails:**
- t=180 corridor_chain temp: no puede empeorar más de 5°C (margen existente anotar en Paso 0).
- t=300 corridor_chain temp: no puede empeorar más de 5°C.
- Sentinels: two_room, HVAC, bedroom con flags=default sin cambio.

**Criterio de éxito parcial:** si corridor_chain t600 PASS pero t180 sigue FAIL (o viceversa), no elevar multiplier — reportar para análisis antes de continuar.

**Criterio de stop:** si frac > 0.5 y t600 sigue FAIL → reportar estructura, no escalar más. Clasificar como gap definitivo.

### Paso 4 — Calibración final

Si Pasos 2+3 resuelven t600 pero no t180 (o viceversa):
- Analizar perfil temporal O2u en R0 a t=0,60,120,180,300,600.
- Decidir si t180 gap es también estructural o calibrable.
- No escalar parámetros sin análisis explícito.

---

## 9. Rollback

Cada paso es rollback independiente:

- **Phase 3D rollback:** eliminar `canonical_doorway_plume_direct_upper_frac` del JSON de corridor_chain → 0.0 en defaults → no-op exacto.
- **Phase 3B rollback:** eliminar `phase3b_neutral_plane_dp_correction` del JSON → false por default → neutral plane formula sin cambios.
- **Phase 3A rollback:** eliminar `phase3a_pressure_ode_enabled` del JSON → false por default → dp_fire_pa permanece en 0.0 siempre → no afecta ningún flujo.
- **Variables de estado (dp_fire_pa):** en 0.0 permanente si Phase 3A=false → equivalente a no existir.

**Rollback total:** revertir los 4 campos añadidos a ThermalSystem + SimulationEngine + RoomModel. Suite completa debe volver a 343/350 exacto.

---

## 10. Riesgos y análisis de impacto

### Riesgo 1: Phase 3B rompe two_room con flags=default

`cfast_two_room_door_open` tiene `canonical_doorway_exchange_enabled=true`. Si Phase 3B cambia el neutral plane para rooms sin fuego activo (dp_fire_pa=0.0), puede afectar el resultado.

**Mitigación:** Phase 3B solo aplica cuando `dp_fire_pa > threshold_pa` (ej. 1.0 Pa). Con dp_fire_pa=0.0 (rooms sin fuego, o Phase 3A=false), la corrección es exactamente cero.

### Riesgo 2: dp_fire_pa inestable numéricamente

La ODE dp_fire puede acumular indefinidamente si el decay term no es suficiente.

**Mitigación:** clampar dp_fire_pa ≤ dp_fire_pa_max = 500 Pa (realista para fuegos de 300 kW en sala de 50m³). Si overshoot, los flujos Bernoulli estarán artificialmente altos → temperature gap invertido (SF > CFAST) → fácil de detectar.

### Riesgo 3: Phase 3D duplica flujo de Part B

Part B ya mueve `cold.o2_lower → hot.o2_lower`. Phase 3D mueve una fracción de ese mismo flujo directo a `hot.o2_upper`. Si ambos se aplican sin reducir Part B, se contabiliza el mismo gas dos veces.

**Mitigación:** Phase 3D reduce el inflow de Part B: `Δm_lower = Δm_in × (1 - plume_direct_frac × hot_layer_frac)`. Total conservado exactamente.

### Riesgo 4: t=180 empeora con Phase 3A/3B

Si dp_fire aumenta el flujo total a t=180, la sala de fuego podría quemar más y ser más caliente.

**Observar en Paso 1/2:** log temp_upper R0 a t=180. Si t=180 margin < 5°C, detener y analizar antes de proceder con Phase 3D.

---

## 11. Definición de éxito

**Éxito completo:** corridor_chain t180 Y t600 PASS, sin degradar ningún otro check. 343 → 345/350 PASS, 5 FAIL requeridos.

**Éxito parcial aceptable:** solo t600 PASS (345→344... no, 7→6 FAILs). Documentar t180 como VALID_GAP estructural separado.

**Fracaso definitivo:** ni t600 ni t180 mejoran significativamente con Phase 3A+3B+3D dentro de los guard rails. Clasificar corridor_chain como Phase 4 (require full pressure ODE + upper↔upper exchange). No escalar parámetros fuera de guard rails.

---

## 12. Archivos a tocar

| Archivo | Cambio |
|---------|--------|
| `sim/core/ThermalSystem.gd` | vars Phase 3A/3B/3D; `dp_fire_pa` ODE; `build_interior_opening_flow_state` modificado; `_apply_canonical_doorway_exchange` Part D |
| `sim/core/SimulationEngine.gd` | @export vars; configure() dict |
| `sim/validation/cases/cfast_corridor_chain.json` | activación per-caso Phase 3A+3B+3D |
| `sim/validation/reports/reference_checks.json` | regenerar tras cambio |
| `docs/validation/STATUS_VALIDATION.md` | actualizar Phase 3A/3B/3D |

**NO tocar:**
- `OxygenExchangeSystem.gd` — Phase 3D actúa solo en ThermalSystem.
- `cfast_two_room_door_open.json`, `cfast_hvac_residential.json`, `cfast_bedroom_closed_door.json` — sentinels.
- Ningún caso con flags en defaults → no-op garantizado.

---

## 13. Sin ILV. Sin M2 global.

`fire_o2_mass_tracking` permanece desactivado.  
`ach_infiltration` solo modificado per-caso en corridor_chain si se requiere (análisis explícito antes).  
ILV no se implementa en esta fase.
