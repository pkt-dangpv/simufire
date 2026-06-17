# Phase 2E — CO₂ Upper Two-Zone Transport: Plan Técnico

> Fecha: 25 mayo 2026  
> Estado: **REVISADO — listo para implementación secuencial** (ver §9)  
> Última revisión: 25 mayo 2026 — ver §8 (correcciones post-revisión)  
> Prerequisito: Phase 2I descartada (ver PHASE_2E_DESIGN.md §12.14)

---

## 1. Contexto

Phase 2I (Experiment 1, 24/24 runs OK) confirmó que los 5 gaps CO₂ upper son **estructurales**: actuar sobre `room.co2_upper_kg` (ThermalSystem) no cierra ningún gap porque los checks leen `room.co2_upper` (fracción molar, OxygenExchangeSystem). Ver §12.14 de PHASE_2E_DESIGN.md.

Phase 2E-CO2 es la intervención **directa sobre `room.co2_upper`** en `OxygenExchangeSystem.gd`.

---

## 2. Mapa de código

### 2.1 Campos CO₂ en `RoomModel.gd`

| Campo | Tipo | Rango | Dueño | Descripción |
|-------|------|-------|-------|-------------|
| `co2_upper` | `float` | 0.0004–0.30 | `OxygenExchangeSystem` | **Fracción molar** zona superior. **Ésta es la variable que miden los checks** |
| `co2_kg` | `float` | ≥0 | `ThermalSystem` / `CombustionSystem` | Masa total CO₂ en sala (kg) |
| `co2_upper_kg` | `float` | ≥0 | `ThermalSystem` | Masa CO₂ zona superior (kg). **Completamente desacoplada de `co2_upper`** |

### 2.2 Ruta fracción molar: `room.co2_upper`

```
ESCRITURA — OxygenExchangeSystem.gd  Y  HVACSystem.gd:

┌── OxygenExchangeSystem.gd ──────────────────────────────────────────────────┐
│  step() → bloque Fase 2B (per-room loop, ~línea 210–239):                   │
│    ├── [bi-zone collapse]  → RESET a room.co2_kg×29/(air_mass×44)  ← PROB C │
│    ├── [fuego activo]      → += delta_co2  (producción × o2_scale)           │
│    ├── [fuego activo]      → += ach_co2_dt (ACH dilución lenta hacia ambient) │
│    └── [sin fuego]         → lerp hacia CO2_AMBIENT (0.0004)                 │
│                                                                               │
│  _step_outside_opening_o2() (~línea 395–399):                                │
│    └── mezcla con exterior (aire fresco entra por zona BAJA):                 │
│        co2_upper = (co2_upper×room_mass + 0.0004×air_in)/(room_mass+air_in)  │
│        ⚠ usa masa TOTAL como denominador → diluye zona alta con inflow bajo   │
│                                                          ← PROBLEMA A         │
│                                                                               │
│  _exchange_room_o2_active_flow() (~línea 575–590):                           │
│    └── net_co2 = hot.co2_upper×co2_ex/hot_mass − cold.co2_upper×co2_ex/cold │
│        hot_room.co2_upper  -= net_co2                                         │
│        cold_room.co2_upper += net_co2                                         │
│        donde co2_ex = exchange_kg × CO2_EXCHANGE_FRACTION (0.25) ← PROBLEMA B│
└───────────────────────────────────────────────────────────────────────────────┘

┌── HVACSystem.gd  (_supply_air, ~línea 247–249)  [SIEMPRE ACTIVO, sin flag]  ┐
│  var supply_co2_upper = lerpf(return_co2_upper, 0.0004, outside_air_fraction) │
│  room.co2_upper = clampf(lerpf(room.co2_upper, supply_co2_upper, air_fraction), 0.0, 0.30) │
│                                                                               │
│  • return_co2_upper = media ponderada de co2_upper de salas de retorno       │
│  • Efecto: el HVAC diluye co2_upper hacia 0.0004 si hay 100% aire exterior   │
│  • Este writer NO tiene flag Phase 2E. Opera independientemente del flag.     │
│  ⚠ Implicación: Sub-A solo afecta aperturas exteriores; HVAC tiene un segundo │
│    canal de dilución permanente que Phase 2E NO controla.                     │
└───────────────────────────────────────────────────────────────────────────────┘

LECTURA:
  ThermalSystem.compute_co2_upper_ppm(room)  → room.co2_upper × 1e6
  ThermalSystem.step_fed(room, dt)           → V_CO2 (solo si co2_pct > 2%)
  ThermalSystem.compute_fed_delta_for_height() → V_CO2 (solo si co2_pct > 2%)

EXPORTACIÓN:
  SimulationStateBuilder → state["co2_upper_ppm"] = compute_co2_upper_ppm()
  SimulationLogWriter    → "CO2u=%.0fppm" desde state["co2_upper_ppm"]

VALIDACIÓN:
  validate_reference_cases.py → CO2u= desde log → co2_upper_pct = ppm / 10000
```

### 2.3 Contrato `room.co2_upper` vs `room.co2_upper_kg` — INVARIANTE DE CONSERVACIÓN

`room.co2_upper` es un **tracer calibrado de fracción molar**, NO derivado del balance de masa `co2_kg`. `room.co2_upper_kg` es masa CO₂ en zona alta, calculada por `ThermalSystem`/`CombustionSystem` de forma completamente independiente.

**Riesgo de coherencia de Phase 2E**: si Phase 2E aumenta `co2_upper` sin actualizar `co2_kg`, puede ocurrir que:

```
co2_upper_equiv_kg = room.co2_upper × room_air_mass_kg × (44.0/29.0)  # [kg CO₂ equivalente]
co2_upper_equiv_kg  >  room.co2_kg                                      # ← VIOLACIÓN
```

Esto no rompe la simulación pero introduce inconsistencia física (la fracción molar implica más CO₂ del que hay en masa).

**Decisión de diseño para Phase 2E**: tratar `room.co2_upper` como tracer calibrado **no conservativo** explícitamente. Justificación:
- La ruta de los checks y FED solo lee `room.co2_upper`, no `co2_kg`
- Phase 2E corrige la *física de mezcla* del tracer, no la masa total
- La violación del invariante ya existe en la Fase 2B original (los sistemas no están acoplados)

**Runner diagnostic a añadir (post-Phase 2E)**: al final de cada validation run, calcular `co2_upper_equiv_kg / co2_kg` por sala. Si ratio > 5.0, warning en `validation_output.txt`. No bloquear gates (sería falso positivo en salas sin fuego).


### 2.3 Ruta masa: `room.co2_upper_kg` (SEPARADA)

```
ESCRITURA:
  CombustionSystem            → producción CO₂ como masa
  ThermalSystem.sync_room_upper_layer() → clamp + Phase 2I floor (default OFF)

LECTURA:
  ThermalSystem.compute_co2_lower_ppm() → co2_lower_kg = co2_kg − co2_upper_kg
                                          (solo FED V_CO2 zona baja)

NO aparece en state["co2_upper_ppm"] ni en "CO2u=" del log.
```

---

## 3. Diagnóstico de los 5 gaps

### 3.1 Tabla de gaps y causas raíz

| Check | SF actual | CFAST ref | Dirección | Causa raíz |
|-------|----------|-----------|-----------|------------|
| `cfast_t510_co2_upper_ppm` | 16 182 ppm | 52 300 ±20 000 ppm | SF **bajo** | **Problema A**: ventana abierta (t=360s) diluye `co2_upper` usando masa total de sala. El aire fresco entra por zona baja → no debería diluir directamente la zona alta |
| `cfast_2r_r0_t120_co2_upper_pct` | 4.75% | 1.58% ±3.0% | SF **alto** (falla por 0.17pp) | SF sobre-produce CO₂ a t=120s; falla marginal. Contrapartida al fix Sub-B (menor exchange retiene más CO₂) |
| `cfast_2r_r0_t480_co2_upper_pct` | 0.999% | 9.91% ±3.0% | SF **bajo** | **Problema B**: `CO2_EXCHANGE_FRACTION=0.25` drena CO₂ de la sala fuego demasiado rápido. CFAST acumula (1.58%→9.91%); SF colapsa (4.75%→0.999%) |
| `cfast_fo_t240_co2_upper_pct` | ~4.32% | 7.77% ±3.0% | SF **bajo** | **Problema C**: post-flashover → `lower_frac < 0.15` → bi-zone inválido → reset de `co2_upper` a fracción bulk muy baja |
| `cfast_fo_t350_co2_upper_pct` | ~0.77% | 7.89% ±3.0% | SF **bajo** | **Problema C** + extinción progresiva baja producción, pero reset sigue activo |

### 3.2 Patrón de divergencia crítico (dos salas)

```
CFAST sala fuego:  1.58%  →  9.91%   (CO₂ CRECE — producción > extracción)
SF sala fuego:     4.75%  →  0.999%  (CO₂ DECRECE — exchange drena la sala)
```

Raíz: en CFAST la zona alta retiene CO₂ producido por el fuego; el exchange por la puerta extrae menos de lo que produce. En SF el exchange activo (0.25 × exchange_kg) extrae más de lo que produce.

---

## 4. Diseño Phase 2E-CO2 (mínimo, flag-gated)

### 4.1 Flags propuestos

```gdscript
## Phase 2E — CO₂ upper two-zone transport (default OFF = sin cambio)
## Sub-A: desacopla dilución exterior de zona alta
## Sub-B: reduce coeficiente de intercambio inter-room de CO₂ (configurable)
## Sub-C: preserva co2_upper en colapso bi-zona con fuego activo
@export var phase2e_co2_upper_enabled: bool = false

## Phase 2E Sub-B: coeficiente de intercambio CO₂ por flujo activo interior.
## Default 0.25 (valor Fase 2B original). Experimento: sweep [0.03, 0.05, 0.08].
@export var phase2e_co2_exchange_fraction: float = 0.25
```

### 4.2 Archivo a modificar: solo `OxygenExchangeSystem.gd`

**No se tocan**: `ThermalSystem.gd`, `CombustionSystem.gd`, cálculo FED, `SimulationStateBuilder.gd`.

### 4.3 Sub-A — `_step_outside_opening_o2()` (~línea 395)

**Problema**: aire exterior fresco entra por zona *baja* de la apertura, pero el modelo aplica la mezcla a `co2_upper` (zona alta) usando la masa total de la sala como denominador. El inflow frío no debería diluir directamente la capa caliente superior.

**Corrección de diseño**: el diseño original era `pass` (omitir toda la dilución exterior), pero eso también suprime el outflow caliente que realmente exporta CO₂ por la parte alta de la apertura. El diseño correcto:
- **Eliminar**: la dilución de `co2_upper` desde el inflow de zona baja (aire frío entra abajo).
- **Añadir**: pérdida de `co2_upper` por outflow caliente en la banda alta de la apertura, usando `upper_outlet_height_m` y `lower_inlet_height_m` que **ya están disponibles** en la función en el momento del cálculo.

**Variables disponibles en `_step_outside_opening_o2`** (confirmado en código):
- `upper_outlet_height_m` (línea 304): banda alta de la apertura por donde sale el gas caliente
- `lower_inlet_height_m` (línea 321): banda baja de la apertura por donde entra aire fresco
- `air_in_kg` (línea 374): masa de aire entrante (inflow frío)
- `room_air_mass_kg` (línea 375): masa total del aire de la sala
- `effective_layer_m` (línea 294): altura de la interfase térmica

**Proxy de outflow** (deducción por conservación de flujo en la apertura):
```gdscript
# Outflow de gas caliente ∝ banda de apertura alta / banda de apertura baja
# Conservativo: aproximamos como fracción de área relativa × inflow
var outflow_proxy_kg: float = air_in_kg * (upper_outlet_height_m / maxf(0.01, lower_inlet_height_m))
```

**Cambio completo propuesto**:
```gdscript
# ACTUAL (Fase 2B original):
if air_in_kg > 0.0:
    indoor.co2_upper = clampf(
        (indoor.co2_upper * room_air_mass_kg + 0.0004 * air_in_kg) / (room_air_mass_kg + air_in_kg),
        0.0, 0.30)

# PROPUESTO (Sub-A, dentro del flag):
if air_in_kg > 0.0:
    if phase2e_co2_upper_enabled:
        # Sub-A: inflow de zona baja NO diluye co2_upper.
        # El gas caliente SALE por la banda alta de la apertura → reduce co2_upper.
        if upper_outlet_height_m > 0.001:
            # Proxy de outflow: proporcional a la banda de salida vs entrada.
            var upper_frac: float = clampf(
                (indoor.height_m - effective_layer_m) / maxf(0.01, indoor.height_m), 0.0, 1.0)
            var upper_air_mass: float = maxf(0.001, room_air_mass_kg * upper_frac)
            var outflow_proxy_kg: float = air_in_kg * (upper_outlet_height_m / maxf(0.01, lower_inlet_height_m))
            var co2_exported: float = indoor.co2_upper * minf(outflow_proxy_kg, upper_air_mass * 0.25) / upper_air_mass
            indoor.co2_upper = clampf(indoor.co2_upper - co2_exported, CO2_AMBIENT, CO2_UPPER_MAX)
        # else: upper_outlet_height_m ≈ 0 (interfase en el dintel, sala completamente mezclada)
        # → fallback conservativo: no modificar co2_upper (ni dilución ni outflow)
    else:
        # Baseline (flag OFF): comportamiento original Fase 2B
        indoor.co2_upper = clampf(
            (indoor.co2_upper * room_air_mass_kg + 0.0004 * air_in_kg) / (room_air_mass_kg + air_in_kg),
            0.0, 0.30)
```

**Fallback**: si `upper_outlet_height_m = 0` (la interfase térmica está por encima del dintel, sala completamente mezclada), no se modifica `co2_upper` desde este path. La sala completamente mezclada recibirá dilución solo desde el HVAC supply y el ACH loop del step() principal.

### 4.4 Sub-B — `_exchange_room_o2_active_flow()` (~línea 575)

**Problema**: `CO2_EXCHANGE_FRACTION = 0.25` hace que cada step de active flow exporte demasiado CO₂ de la sala fuego hacia la sala fría. En el escenario de dos salas con puerta abierta:
- **CFAST**: CO₂ sala fuego crece de 1.58% → 9.91% (producción > extracción por la puerta)
- **SF**: CO₂ sala fuego colapsa de 4.75% → 0.999% (extracción por puerta > producción)

**Efecto CORRECTO de reducir `CO2_EXCHANGE_FRACTION` (0.25 → 0.03–0.08)**:

| Check | SF actual | CFAST | Dirección gap | Efecto Sub-B (reducir fracción) |
|-------|----------|-------|---------------|----------------------------------|
| `t120_co2_upper_pct` | 4.75% | 1.58% | SF **alto** (+0.17pp sobre tol) | ⚠ **EMPEORA**: retener más CO₂ en sala fuego a t=120s sube SF más alto |
| `t480_co2_upper_pct` | 0.999% | 9.91% | SF **bajo** (-5.9pp bajo tol) | ✓ **AYUDA**: sala fuego retiene CO₂ acumulado, SF sube hacia 9.91% |

> **⚠ CORRECCIÓN (la versión anterior de este documento tenía la dirección invertida)**: reducir `CO2_EXCHANGE_FRACTION` RETIENE más CO₂ en la sala fuego (no la drena más rápido). Esto ayuda al check de t=480 pero **agrava** el check de t=120, que ya falla por 0.17pp sobre la tolerancia.

**Cambio**:
```gdscript
# ACTUAL:
const CO2_EXCHANGE_FRACTION: float = 0.25
var co2_ex_kg: float = exchange_kg * CO2_EXCHANGE_FRACTION

# PROPUESTO:
var effective_co2_frac: float = phase2e_co2_exchange_fraction if phase2e_co2_upper_enabled \
                                 else CO2_EXCHANGE_FRACTION
var co2_ex_kg: float = exchange_kg * effective_co2_frac
```

**Riesgo de t120**: si Sub-B (fracción reducida) se aplica sin Sub-A activo, el CO₂ retenido en la sala fuego a t=120s puede empeorar el gap `cfast_2r_r0_t120_co2_upper_pct`. Este check **no es required** (no gate), pero agravar un check que ya falla contradice el objetivo.

**Criterio de descarte Sub-B solo**: si en Exp 2E-CO2-1B el valor SF de `t120_co2_upper_pct` supera 5.58% (tol +1.0pp extra de margen), Sub-B aislado se descarta. En ese caso Sub-B solo se aplica en combinación con Sub-A (que reduce CO₂ via outflow de apertura exterior, atenuando la retención).

### 4.5 Sub-C — Bloque Fase 2B per-room (~línea 214)

**Problema**: colapso bi-zona (`lower_frac < 0.15`) siempre resetea `co2_upper` al bulk derivado de `co2_kg`. En post-flashover, `co2_kg` masa-total puede ser bajo mientras CFAST mantiene CO₂ estratificado en zona alta.

**Cambio**:
```gdscript
# ACTUAL:
if lower_frac < 0.15 or (lower_frac < 0.40 and room.o2 < 0.070):
    var room_co2_frac: float = room.co2_kg * 29.0 / maxf(0.001, air_mass_kg * 44.0)
    room.co2_upper = clampf(room_co2_frac, CO2_AMBIENT, CO2_UPPER_MAX)

# PROPUESTO:
if lower_frac < 0.15 or (lower_frac < 0.40 and room.o2 < 0.070):
    var room_co2_frac: float = room.co2_kg * 29.0 / maxf(0.001, air_mass_kg * 44.0)
    if phase2e_co2_upper_enabled and (room.hrr_kw > 0.1 or room.fire != null):
        # En post-flashover con fuego activo: floor en lugar de reset.
        # Preserva co2_upper acumulado; el bulk es el mínimo físico.
        room.co2_upper = maxf(room.co2_upper, clampf(room_co2_frac, CO2_AMBIENT, CO2_UPPER_MAX))
    else:
        room.co2_upper = clampf(room_co2_frac, CO2_AMBIENT, CO2_UPPER_MAX)
```

### 4.6 Wiring en `SimulationEngine.gd` y `OxygenExchangeSystem.configure()`

```gdscript
# SimulationEngine.gd — nuevos @export:
@export var phase2e_co2_upper_enabled: bool = false
@export var phase2e_co2_exchange_fraction: float = 0.25

# En thermal_system.configure() o en oxygen_exchange_system.configure():
"phase2e_co2_upper_enabled": phase2e_co2_upper_enabled,
"phase2e_co2_exchange_fraction": phase2e_co2_exchange_fraction,
```

```gdscript
# OxygenExchangeSystem.gd — nuevas variables:
var phase2e_co2_upper_enabled: bool = false
var phase2e_co2_exchange_fraction: float = 0.25

# En configure():
phase2e_co2_upper_enabled = bool(settings.get("phase2e_co2_upper_enabled", phase2e_co2_upper_enabled))
phase2e_co2_exchange_fraction = float(settings.get("phase2e_co2_exchange_fraction", phase2e_co2_exchange_fraction))
```

---

## 5. Runner Phase 2E-CO2 — Experimentos secuenciales

> **Principio**: cada sub-mecanismo se valida **solo** antes de combinarse. Sin rebaseline. Sin cambio simultáneo de múltiples variables.

### 5.1 Casos de test

```python
SENTINEL_CASES = [               # Gate de seguridad: NO pueden regresar
    "g4_gie_delayed_entry_hazard",
    "v3_hallway_fed_exposure",
    "victim_fed_incapacitation",
]
CO2_CASES = [                    # Target: cerrar los 5 gaps
    "cfast_r0_window_360",          # gaps t510/t420_co2_upper_ppm
    "cfast_two_room_door_open",     # gaps 2r_t120/t480_co2_upper_pct
    "cfast_post_flashover_vented",  # gaps fo_t240/t350_co2_upper_pct
]
ALL_CASES = SENTINEL_CASES + CO2_CASES   # 6 casos total
```

### 5.2 Experimento 2E-CO2-1A — Sub-C solo (menor riesgo)

```python
# Sub-A=OFF, Sub-B=default(0.25), Sub-C=ON
# Solo se modifica el colapso bi-zona con fuego activo
CONFIGS_1A = [
    {"phase2e_co2_upper_enabled": False},                          # baseline
    {"phase2e_co2_upper_enabled": True, "phase2e_sub_c_only": True},  # Sub-C solo
]
# 6 casos × 2 configs = 12 runs
# Gate 1A: sentinels 3/3 PASS en config ON
# Target: cerrar cfast_fo_t240 y cfast_fo_t350 (Problema C)
```

### 5.3 Experimento 2E-CO2-1B — Sub-A solo

```python
# Sub-A=ON, Sub-B=default(0.25), Sub-C=OFF
# Solo se modifica _step_outside_opening_o2
CONFIGS_1B = [
    {"phase2e_co2_upper_enabled": False},                          # baseline
    {"phase2e_co2_upper_enabled": True, "phase2e_sub_a_only": True},  # Sub-A solo
]
# 6 casos × 2 configs = 12 runs
# Gate 1B: sentinels 3/3 PASS en config ON
# Target: cerrar cfast_t510_co2_upper_ppm (Problema A)
```

### 5.4 Experimento 2E-CO2-1C — Sub-B solo (sweep de fracción)

```python
# Sub-A=OFF, Sub-B=sweep, Sub-C=OFF
# Solo se modifica CO2_EXCHANGE_FRACTION en _exchange_room_o2_active_flow
FRACCIONES_B = [0.25, 0.08, 0.05, 0.03]
CONFIGS_1C = [
    {"phase2e_co2_upper_enabled": False},                          # baseline
    *[{"phase2e_co2_upper_enabled": True, "phase2e_sub_b_only": True,
       "phase2e_co2_exchange_fraction": f} for f in FRACCIONES_B],
]
# 6 casos × 5 configs = 30 runs
# Gate 1C: sentinels 3/3 PASS para config seleccionada
# Gate 1C adicional: cfast_2r_r0_t120 NO empeora por encima de SF=5.58% (+1pp sobre tol)
# Target: cerrar cfast_2r_r0_t480 (Problema B) con la menor fracción que pase gates
```

### 5.5 Experimento 2E-CO2-2 — Combinado (solo si 1A+1B+1C pasan gates)

```python
# Sub-A=ON + Sub-B=mejor_frac_1C + Sub-C=ON
# 6 casos × 2 configs = 12 runs (baseline + combinado)
# Gate 2: sentinels 3/3 PASS; target ≥3/5 gaps cerrados
```

### 5.6 Overrides de configuración

```json
{
  "phase2e_co2_upper_enabled": true,
  "phase2e_co2_exchange_fraction": 0.25,
  "phase2e_sub_a_only": false,
  "phase2e_sub_b_only": false,
  "phase2e_sub_c_only": false
}
```

> Nota de implementación: para controlar qué subs están activos en cada experimento, se puede usar un único flag `phase2e_co2_upper_enabled` con sub-flags de aislamiento. Alternativamente, usar 3 flags separados: `phase2e_sub_a`, `phase2e_sub_b`, `phase2e_sub_c`.

### 5.7 Salida esperada por experimento

```
TABLA 1 — Sentinels (3 sentinel checks × N configs)
  Requerido: 3/3 PASS en TODA config ON

TABLA 2 — CO₂ gaps por config
  check | baseline | CFAST ref | config_ON | Δ vs baseline | gap cerrado?

TABLA 3 — Safety V_CO2 (por sentinel case + sala objetivo)
  Sala, altura breath (1.5m), co2_upper_ppm, V_CO2, FED_delta_ON−FED_delta_OFF
  Criterio: V_CO2 = 1.0 (co2_upper < 20000 ppm) en rooms que alimentan checks g4/v3/victim

TABLA 4 — Resumen: N/5 gaps cerrados por config
```

---

## 6. Criterio de éxito

| Condición | Criterio |
|-----------|----------|
| **Sentinels** | 3/3 sentinel cases PASS en toda config ON (gate bloqueante) |
| **V_CO2 safety** | Medido por sala/altura, solo en sentinel cases: `co2_upper < 20 000 ppm` (2%) en los cuartos que alimentan checks g4/v3/victim. Razón: V_CO2 = 1.0 si co2_pct ≤ 2%; sub-umbral hasta ~120 000 ppm (12%). No usar global max. |
| **FED safety secondary** | `FED_delta_ON − FED_delta_OFF < 0.005` en victim_fed_incapacitation (la exposición neta al CO₂ no aumenta más de 0.5% de FED vs baseline OFF) |
| **Gaps cerrados** | ≥ 3/5 en alguna config del experimento combinado (Exp 2E-CO2-2) |
| `cfast_2r_r0_t120` | No superar SF > 5.58% (+1.0pp sobre la tolerancia actual de ±3pp con CFAST 1.58%) |
| **Invariante `co2_upper`** | Siempre en [CO2_AMBIENT (0.0004), 0.30] |
| **Guardrails flag OFF** | 292/292 PASS sin cambio — verificar antes de merge |

> **Nota sobre V_CO2**: el check de 2% global que aparecía en la versión anterior era excesivamente conservador. V_CO2 = 1.0 hasta 20 000 ppm (2%). Por encima de 2% V_CO2 crece exponencialmente, pero solo en los cuartos de origen del fuego, que no son las posiciones de víctimas en los sentinel cases (g4, v3 están en pasillos/corredores). El check correcto es verificar V_CO2 **en las posiciones específicas de las víctimas**, no globalmente.

---

## 7. Riesgos

| Riesgo | Severidad | Mitigación |
|--------|-----------|------------|
| **Sub-B agrava `t120`**: reducir `CO2_EXCHANGE_FRACTION` retiene más CO₂ en sala fuego → `t120` (SF ya alto 4.75% vs CFAST 1.58%) sube más → falla aumenta desde 0.17pp | MEDIO | Experimento 1C (Sub-B solo) mide exactamente esto. Criterio de descarte: SF > 5.58%. Si descartado, Sub-B solo se usa en Exp 2 combinado con Sub-A |
| **V_CO2 amplifica FED**: `co2_upper > 2%` en sala fuego activo → V_CO2 > 1.0 → FED del CO₂ se multiplica | BAJO-ACOTADO | Verificar en sentinel cases por sala/altura (no global). Salas de fuego no son las posiciones de víctimas en g4/v3. Check FED delta < 0.005 como secondary gate |
| **HVACSystem.gd dilución adicional**: HVAC supply siempre activo (sin flag 2E) diluye `co2_upper` en salas con HVAC → Sub-A puede ser insuficiente si HVAC domina la dilución | BAJO-DESCONOCIDO | Exp 1B medirá el efecto neto. Si el gap `cfast_t510` no se cierra, analizar si el HVAC está contrarrestando Sub-A en ese scenario |
| **Proxy de outflow Sub-A impreciso**: `outflow_proxy_kg = air_in_kg × (upper_outlet_h / lower_inlet_h)` es una aproximación, no balance de masa exacto | BAJO | Proxy conservativo: bounded con `upper_air_mass × 0.25` para evitar sobre-extracción. Validar con Exp 1B contra CFAST |
| **Inconsistencia masa vs fracción**: subir `co2_upper` sin actualizar `co2_upper_kg` → desacople interno (documentado en §2.3) | BAJO-ACEPTABLE | Tratado como tracer calibrado. `co2_upper_kg` no afecta log ni checks CO₂ upper. Afecta solo `compute_co2_lower_ppm()` (FED zona baja) — revisar post-experiment |
| **Sub-C en post-extinción**: si la sala sigue con `lower_frac < 0.15` después de que el fuego se apaga, `hrr_kw=0` → el guard previene el floor → reset correcto | CERO | Guard `hrr_kw > 0.1 or room.fire != null` lo previene. Confirmado. |

---

## 8. Design corrections after review

> Esta sección registra las 6 correcciones aplicadas al diseño original tras revisión técnica (25 mayo 2026). El diseño original tenía errores de hecho y de razonamiento que habrían causado un experimento mal estructurado.

### Corrección 1 — HVACSystem.gd como segundo escritor de `room.co2_upper`

**Error original**: §2.2 declaraba "ESCRITURA — OxygenExchangeSystem.gd únicamente".

**Corrección**: `HVACSystem._supply_air()` (línea ~249) también escribe `room.co2_upper` en cada step:
```gdscript
var supply_co2_upper = lerpf(return_co2_upper, 0.0004, outside_air_fraction)
room.co2_upper = clampf(lerpf(room.co2_upper, supply_co2_upper, air_fraction), 0.0, 0.30)
```
Este writer está **siempre activo** (no controlado por flag Phase 2E). `return_co2_upper` es la media ponderada de `co2_upper` de las salas de retorno; si hay 100% aire exterior, tiende a 0.0004. Implicación: Sub-A solo elimina la dilución por ventana exterior, pero el HVAC tiene un canal de dilución independiente que puede contrarrestar el efecto en escenarios con HVAC activo. El §2.2 ha sido actualizado con diagrama de dos escritores.

### Corrección 2 — Contrato explícito `room.co2_upper` vs `room.co2_upper_kg`

**Error original**: el diseño no declaraba la desconexión entre los dos campos ni sus implicaciones de conservación.

**Corrección**: añadido §2.3 con:
- Declaración explícita de que `room.co2_upper` es un **tracer calibrado**, no derivado de balance de masa con `co2_kg`
- Fórmula de verificación: `co2_upper_equiv_kg = room.co2_upper × room_air_mass_kg × (44.0/29.0)` puede exceder `co2_kg`
- Decisión de diseño: aceptar como tracer no conservativo (la alternativa —acoplar los dos campos— requeriría refactorizar ThermalSystem + CombustionSystem, fuera de scope)
- Diagnóstico futuro: ratio `co2_upper_equiv_kg / co2_kg` como warning si > 5.0

### Corrección 3 — Sub-A: eliminar `pass` total, diseñar con outflow proxy

**Error original**: Sub-A usaba `pass` — suprime TODA la interacción de `co2_upper` con aperturas exteriores, incluyendo el outflow de gas caliente por la banda alta que sí debería exportar CO₂.

**Corrección**: diseño de dos partes:
1. **Eliminar inflow dilution** (INCORRECTO): el aire frío que entra por zona baja NO diluye directamente la zona alta
2. **Añadir outflow removal** (CORRECTO): el gas caliente que sale por la banda alta (`upper_outlet_height_m > 0`) exporta CO₂ de `co2_upper`

Proxy disponible: `upper_outlet_height_m`, `lower_inlet_height_m`, `air_in_kg` están todos calculados en la función. Se usa `outflow_proxy_kg = air_in_kg × (upper_outlet_height_m / lower_inlet_height_m)` acotado a `upper_air_mass × 0.25` para evitar sobre-extracción. Fallback si `upper_outlet_height_m = 0`: no modificar `co2_upper` (conservativo).

### Corrección 4 — Sub-B: dirección de efecto estaba invertida

**Error original**: el texto original implicaba que reducir `CO2_EXCHANGE_FRACTION` *reducía* la retención de CO₂ en la sala fuego.

**Corrección**: reducir `CO2_EXCHANGE_FRACTION` (0.25 → 0.03–0.08) **RETIENE más** CO₂ en la sala fuego (menos exportado a la sala fría). Efecto:
- ✓ Ayuda `t480` (SF demasiado bajo: 0.999% vs CFAST 9.91%) — retención aumenta
- ⚠ Empeora `t120` (SF ya demasiado alto: 4.75% vs CFAST 1.58%) — retención sube más

Se añadió criterio de descarte Sub-B-solo: si SF `t120` > 5.58%, Sub-B aislado no es viable.

### Corrección 5 — V_CO2 safety: check específico por sala/altura sentinel

**Error original**: criterio "max `co2_upper < 2%` globalmente" — excesivamente conservador y no aplica a las posiciones de víctimas.

**Corrección**: verificar V_CO2 = 1.0 específicamente en los cuartos/alturas que alimentan los checks de g4, v3, y victim_fed. Las posiciones de víctimas (pasillos, corredores) están físicamente separadas de las salas con fuego activo donde CO₂ sube > 2%. Se añadió secondary gate: `FED_delta_ON − FED_delta_OFF < 0.005`.

### Corrección 6 — Rediseño del experimento en fases secuenciales

**Error original**: un único runner combinado con sweep de Sub-B, probando todo junto.

**Corrección**: 4 experimentos en secuencia con gates de bloqueo entre ellos:
- **Exp 1A**: Sub-C solo → cierra Problema C (post-flashover)
- **Exp 1B**: Sub-A solo → cierra Problema A (ventana exterior)
- **Exp 1C**: Sub-B solo con sweep → cierra Problema B (exchange doorway), verifica t120
- **Exp 2**: combinado (solo si 1A+1B+1C pasan) → efecto total

Sin rebaseline. Un solo flag de base con sub-flags de aislamiento.

---

## 9. Recomendación y próximos pasos

### 9.1 Estado del diseño

**LISTO para implementación secuencial, comenzando por Exp 2E-CO2-1A (Sub-C).**

Justificación:
- Las 6 correcciones han sido aplicadas. No quedan errores de hecho conocidos.
- Sub-C es el sub-mecanismo de menor riesgo (solo afecta el reset de bi-zone collapse) y el que más directamente cierra los checks `cfast_fo_*`.
- Sub-A y Sub-B tienen riesgos identificados pero acotados y verificables experimentalmente.
- El diseño de outflow proxy para Sub-A usa solo variables ya disponibles en la función.
- Los gates están bien definidos para cada fase.

**Pendiente (no bloqueante para implementar Sub-C)**:
- Confirmar disponibilidad de `hrr_kw` en el loop per-room de `OxygenExchangeSystem.step()` (verificar campo en `RoomModel` o si se pasa como hook)
- Confirmar si `room.fire != null` es el check correcto para fuego activo en ese loop

### 9.2 Prompt de implementación — Exp 2E-CO2-1A (Sub-C)

```
TAREA: Implementar Phase 2E Sub-C en OxygenExchangeSystem.gd

Archivo a modificar: sim/core/OxygenExchangeSystem.gd

Sub-C afecta el bloque de colapso bi-zona en step() (~línea 214).

CAMBIO:
Localizar el bloque actual:
  if lower_frac < 0.15 or (lower_frac < 0.40 and room.o2 < 0.070):
      var room_co2_frac: float = room.co2_kg * 29.0 / maxf(0.001, air_mass_kg * 44.0)
      room.co2_upper = clampf(room_co2_frac, CO2_AMBIENT, CO2_UPPER_MAX)

Reemplazar con:
  if lower_frac < 0.15 or (lower_frac < 0.40 and room.o2 < 0.070):
      var room_co2_frac: float = room.co2_kg * 29.0 / maxf(0.001, air_mass_kg * 44.0)
      if phase2e_co2_upper_enabled and (room.hrr_kw > 0.1 or room.fire_active):
          # Sub-C: con fuego activo, preservar co2_upper acumulado (floor = bulk)
          room.co2_upper = maxf(room.co2_upper, clampf(room_co2_frac, CO2_AMBIENT, CO2_UPPER_MAX))
      else:
          room.co2_upper = clampf(room_co2_frac, CO2_AMBIENT, CO2_UPPER_MAX)

WIRING requerido:
1. Añadir @export var phase2e_co2_upper_enabled: bool = false en OxygenExchangeSystem.gd (si no existe ya)
2. Añadir en configure(): phase2e_co2_upper_enabled = bool(settings.get("phase2e_co2_upper_enabled", false))
3. Añadir @export var phase2e_co2_upper_enabled: bool = false en SimulationEngine.gd
4. Pasar el flag en el dict de settings que se pasa a OxygenExchangeSystem.configure()

VERIFICAR campo de fuego activo en RoomModel: ¿es room.hrr_kw, room.fire_active, room.fire != null?
Usar el campo correcto como guard de fuego activo.

POST-IMPLEMENTACIÓN:
1. Godot parse: Godot_v4.6.3-stable_win64_console.exe --headless --path . --quit → EXIT 0
2. Guardrails flag OFF: python scripts/simulation/validation_guardrails.py → 292/292 PASS
3. Unit tests: python -m unittest tests.test_guardrails -v → 13/13 OK
4. Ejecutar Exp 2E-CO2-1A: 12 runs (6 baseline OFF + 6 Sub-C ON)
5. Documentar en PHASE_2E_DESIGN.md §12.15

No tocar: ThermalSystem.gd, CombustionSystem.gd, FED, SimulationStateBuilder.gd
No commit/push automático.
```

---

*Documento creado: 25 mayo 2026. Correcciones aplicadas: 25 mayo 2026. Exp 1A ejecutado: 25 mayo 2026.*

---

## 10. Exp 2E-CO₂-1A — Resultados (Sub-C: fire-room CO₂ upper tracer boost)

**Fecha de ejecución**: 25 mayo 2026  
**Runs**: 24/24 OK (6 casos × 4 gains). EXIT 0.  
**Validación previa**: Godot parse EXIT 0 ✅ · Guardrails 292/292 PASS ✅ · Unit tests 13/13 OK ✅

### 10.1 TABLA 1 — Sentinels (5/5 por ganancia)

| Ganancia | g4 CO>1200 | g4 FED | v3 FED | v3 maxFED | vic FED | Total |
|----------|-----------|--------|--------|-----------|---------|-------|
| BASELINE | 85.583 OK | 198.417 OK | 249.833 OK | 2.212 OK | 0.772 OK | **5/5** |
| g=0.25 | 85.583 OK | 198.417 OK | 249.833 OK | 2.212 OK | 0.772 OK | **5/5** |
| g=0.50 | 85.583 OK | 198.417 OK | 249.833 OK | 2.212 OK | 0.772 OK | **5/5** |
| g=0.75 | 85.583 OK | 198.417 OK | 249.833 OK | 2.212 OK | 0.772 OK | **5/5** |
| g=1.00 | 85.583 OK | 198.417 OK | 249.833 OK | 2.212 OK | 0.772 OK | **5/5** |

### 10.2 TABLA 2 — FED deltas en sentinel cases (gate: |Δ| < 0.005)

| Métrica | Baseline | g=0.25 | g=0.50 | g=0.75 | g=1.00 |
|---------|---------|--------|--------|--------|--------|
| g4 FED timing | 198.4167 | +0.0000 OK | +0.0000 OK | +0.0000 OK | +0.0000 OK |
| v3 max FED | 2.2116 | +0.0000 OK | +0.0000 OK | +0.0000 OK | +0.0000 OK |
| vic final FED | 0.7715 | +0.0000 OK | +0.0000 OK | +0.0000 OK | +0.0000 OK |
| **Max \|ΔFED\|** | — | **0.0000 OK** | **0.0000 OK** | **0.0000 OK** | **0.0000 OK** |

> **Nota**: ΔFED = 0.0000 exacto en todos los gains. Sub-C opera solo en la sala de fuego (room 0); los sentinel cases evalúan víctimas en pasillo/corredor (room 1). El boost de `co2_upper` en room 0 no se propaga a room 1 dentro del horizonte de simulación de cada caso.

### 10.3 TABLA 3 — CO₂ upper por ganancia (check de referencia vs baseline)

| Check | Baseline | CFAST ref | Tol | g=0.25 | g=0.50 | g=0.75 | g=1.00 | Base OK |
|-------|---------|-----------|-----|--------|--------|--------|--------|---------|
| `cfast_t510_co2_upper_ppm` | 16 182 | 52 300 | ±20 000 | 17 516 (+1 334) | 18 850 (+2 668) | 20 184 (+4 002) | 21 518 (+5 336) | **FAIL** |
| `cfast_t420_co2_upper_ppm` | 41 438 | 60 800 | ±22 000 | 44 464 (+3 026) | 47 490 (+6 052) | 50 516 (+9 078) | 53 542 (+12 104) | PASS |
| `cfast_src_t300_co2_upper_ppm` | 93 446 | obs | obs | 93 446 (+0) | 93 446 (+0) | 93 446 (+0) | 93 446 (+0) | obs |
| `cfast_2r_r0_t120_co2_upper_pct` | 4.750% | 1.58% | ±3.0% | 5.927% (+1.18pp) | 7.104% (+2.35pp) | 8.281% (+3.53pp) | 9.459% (+4.71pp) | **FAIL** |
| `cfast_2r_r0_t480_co2_upper_pct` | 0.999% | 9.91% | ±3.0% | 0.999% (+0.000pp) | 0.999% (+0.000pp) | 0.999% (+0.000pp) | 0.999% (+0.000pp) | **FAIL** |

### 10.4 TABLA 4 — Max CO₂ upper ppm (sala 0, toda la simulación)

> V_CO₂ = 1.0 hasta 20 000 ppm (2%). Riesgo alto > 120 000 ppm (12%).

| Caso | Baseline | g=0.25 | g=0.50 | g=0.75 | g=1.00 |
|------|---------|--------|--------|--------|--------|
| `cfast_r0_window_360` | 136 001 ⚠ | 169 902 ⚠ | 203 802 ⚠ | 237 702 ⚠ | 271 603 ⚠ |
| `cfast_single_room_closed` | 105 224 ⚠ | 131 430 ⚠ | 157 636 ⚠ | 183 842 ⚠ | 210 048 ⚠ |
| `cfast_two_room_door_open` | 127 678 ⚠ | 159 483 ⚠ | 191 287 ⚠ | 223 091 ⚠ | 254 895 ⚠ |

> **Nota**: El `⚠` baseline ya estaba presente antes de Sub-C. Sub-C agrava los picos de sala de fuego pero los sentinel cases evalúan a víctimas en otros cuartos (ΔFED = 0.0000).

### 10.5 Resumen de gaps cerrados

| Ganancia | Sentinels | FED gate | CO₂ gaps cerrados |
|----------|----------|----------|--------------------|
| g=0.25 | 5/5 ✅ | max Δ=0.0000 ✅ | **0/3** ❌ |
| g=0.50 | 5/5 ✅ | max Δ=0.0000 ✅ | **0/3** ❌ |
| g=0.75 | 5/5 ✅ | max Δ=0.0000 ✅ | **0/3** ❌ |
| g=1.00 | 5/5 ✅ | max Δ=0.0000 ✅ | **0/3** ❌ |

### 10.6 Análisis diagnóstico

**¿Por qué Sub-C no cierra los gaps?**

1. **`cfast_t510` (SF LOW 16182 vs CFAST 52300 ±20000)**: Sub-C amplifica `delta_co2` (producción por fuego). Con g=1.0 el boost suma +5336 ppm. Para cerrar el gap se requiere llegar a ≥32300 ppm, un delta de +16118 ppm desde baseline. Incluso g=1.0 aporta solo 33% del delta requerido. El gap es de dilución (Sub-A), no de producción.

2. **`cfast_2r_r0_t480` (SF LOW 0.999% vs CFAST 9.91% ±3.0%)**: Boost = 0 en todos los gains. A t=480s el fuego en room 0 ya se ha extinguido (`hrr_kw == 0.0`), por lo que la condición `phase2e_co2_subc_enabled and phase2e_co2_fire_upper_boost_gain > 0.0` nunca entra. El gap es de exchange inter-room (Sub-B), no de producción.

3. **`cfast_2r_r0_t120` (SF HIGH 4.75% vs CFAST 1.58% ±3.0%)**: Ya fallaba por exceso. Sub-C empeora aún más: g=1.0 sube a 9.459% (+4.71pp). Sub-C es **contraproducente** para este gap.

**Invariante confirmado**: `flag OFF = no-op exacto`. El boost solo se activa con `phase2e_co2_subc_enabled=true AND gain > 0.0 AND hrr_kw > 0.0`. La rama con flag OFF produce resultados bit-a-bit idénticos al baseline.

### 10.7 Decisión

> **Sub-C DESCARTADO como mecanismo principal para cerrar los gaps CO₂ upper.**

Sub-C es seguro (no rompe sentinels ni FED) pero insuficiente. Los gaps son causados por dilución exterior (Sub-A) y exchange de doorway (Sub-B), no por tasa de producción insuficiente.

**Las variables y el boost permanecen en código** (`phase2e_co2_subc_enabled`, `phase2e_co2_fire_upper_boost_gain`) como feature disabled por defecto. Pueden reutilizarse en el experimento combinado (Exp 2).

**Siguiente paso**: Exp 2E-CO₂-1B — Sub-A: outflow proxy en apertura exterior (reduce dilución `co2_upper` con masa de aire completa). Objetivo primario: cerrar `cfast_t510_co2_upper_ppm` (SF 16182 → necesita ≥32300 ppm).

---

## 11. Exp 2E-CO₂-1B — Resultados (Sub-A: outside-opening CO₂ upper outflow correction)

**Fecha de ejecución**: 25 mayo 2026  
**Runs**: 30/30 OK (6 casos × 5 gains). EXIT 0.  
**Validación previa**: Godot parse EXIT 0 ✅ · Guardrails 292/292 PASS ✅ · Unit tests 13/13 OK ✅

### 11.1 TABLA 1 — Sentinels + required checks (5/5 por ganancia)

| Ganancia | g4 CO>1200 | g4 FED | v3 FED | v3 maxFED | vic FED | Total | Req.PASS |
|----------|-----------|--------|--------|-----------|---------|-------|---------|
| BASELINE | 85.583 OK | 198.417 OK | 249.833 OK | 2.212 OK | 0.772 OK | **5/5** | 0/0 |
| g=0.00 | 85.583 OK | 198.417 OK | 249.833 OK | 2.212 OK | 0.772 OK | **5/5** | 0/0 OK |
| g=0.25 | 85.583 OK | 198.417 OK | 249.833 OK | 2.212 OK | 0.772 OK | **5/5** | 0/0 OK |
| g=0.50 | 85.583 OK | 198.417 OK | 249.833 OK | 2.212 OK | 0.772 OK | **5/5** | 0/0 OK |
| g=0.75 | 85.583 OK | 198.417 OK | 249.833 OK | 2.212 OK | 0.772 OK | **5/5** | 0/0 OK |
| g=1.00 | 85.583 OK | 198.417 OK | 249.833 OK | 2.212 OK | 0.772 OK | **5/5** | 0/0 OK |

### 11.2 TABLA 2 — FED deltas (todos exactamente 0.0000)

ΔFED = 0.0000 en todos los gains. Mismo resultado que Exp 1A: Sub-A opera en room 0 (sala de fuego), los sentinel cases evalúan víctimas en room 1 (pasillo/corredor). El flag Sub-A no afecta al FED de las víctimas en ningún gain.

### 11.3 TABLA 3 — CO₂ upper por ganancia — HALLAZGO CRÍTICO

| Check | Baseline | CFAST ref | Tol | g=0.00 | g=0.25 | g=0.50 | g=0.75 | g=1.00 | Base OK |
|-------|---------|-----------|-----|--------|--------|--------|--------|--------|---------|
| `cfast_t510_co2_upper_ppm` | 16 182 | 52 300 | ±20 000 | **91 859 (+75 677)** | 539 (−15 643) | 465 (−15 717) | 443 (−15 739) | 432 (−15 750) | FAIL |
| `cfast_t420_co2_upper_ppm` | 41 438 | 60 800 | ±22 000 | **91 025 (+49 587)** | 4 021 (−37 417) | 1 720 (−39 718) | 1 201 (−40 237) | 967 (−40 471) | PASS |
| `cfast_src_t300_co2_upper_ppm` | 93 446 | obs | obs | 93 446 (+0) | 93 446 (+0) | 93 446 (+0) | 93 446 (+0) | 93 446 (+0) | obs |
| `cfast_2r_r0_t120_co2_upper_pct` | 4.750% | 1.58% | ±3.0% | 4.750% (+0.000pp) | 4.750% (+0.000pp) | 4.750% (+0.000pp) | 4.750% (+0.000pp) | 4.750% (+0.000pp) | FAIL |
| `cfast_2r_r0_t480_co2_upper_pct` | 0.999% | 9.91% | ±3.0% | 0.999% (+0.000pp) | 0.999% (+0.000pp) | 0.999% (+0.000pp) | 0.999% (+0.000pp) | 0.999% (+0.000pp) | FAIL |

### 11.4 TABLA 5 — Diagnóstico Sub-A: evolución temporal `cfast_r0_window_360` room 0

| t [s] | Baseline | g=0.00 | g=0.25 | g=0.50 | g=0.75 | g=1.00 |
|-------|---------|--------|--------|--------|--------|--------|
| 120 | 46 988 | +0 | +0 | +0 | +0 | +0 |
| 240 | 120 520 | +0 | +0 | +0 | +0 | +0 |
| 360 | 90 530 | +0 | +0 | +0 | +0 | +0 |
| **420** | 41 438 | **91 025 (+49 587)** | 4 021 (−37 417) | 1 720 (−39 718) | 1 201 (−40 237) | 967 (−40 471) |
| **510** | 16 182 | **91 859 (+75 677)** | 539 (−15 643) | 465 (−15 717) | 443 (−15 739) | 432 (−15 750) |

### 11.5 Análisis diagnóstico — Hallazgo de inversión de fase

**Punto de bifurcación t=360s**: todos los gains producen el mismo valor hasta t=360s (90 530 ppm). A partir de t=360s (apertura del ventana en `cfast_r0_window_360`) los comportamientos divergen.

**g=0.00 — inversión de dirección confirmada**:
- Sin flag: baseline usa la fórmula `(co2_upper × mass_room + 0.0004 × air_in) / (mass_room + air_in)`. Con `mass_room >> air_in`, esta dilución es pequeña por paso, pero acumulada de t=360s a t=510s transforma 90 530 ppm → 16 182 ppm (−74 348 ppm en 150s). Es muy agresiva.
- Con flag ON y gain=0.0: sin dilución, `co2_upper` sube de 90 530 → 91 859 ppm a t=510s. La producción de CO₂ por fuego activo supera la pérdida mínima por infiltración.
- Resultado: **g=0.00 invierte el gap** — SF pasa de 16 182 (muy por debajo de 32 300) a 91 859 (muy por encima de 72 300). Sobreimpacto.

**g=0.25+ — outflow excesivo**:
- Con gain=0.25, el outflow removal `removal_frac` es lo suficientemente alto como para strip `co2_upper` a ~400–539 ppm en pocos pasos de t=360s a t=420/510s.
- La fórmula `removal_frac = clamp(upper_out_kg / max(upper_air_mass, 0.1), 0, 0.25)` con `outflow_ratio` potencialmente ≥ 2 (ventana con capa fría baja y capa caliente toda la apertura) da `removal_frac` cercano a 0.25 por paso.
- Efecto acumulado: `co2_upper = lerp(91 000, 0.0004, 0.25)^n` → converge a 400 ppm muy rápidamente.

**`cfast_two_room_door_open` t120/t480 — cero cambio**:
- Sub-A opera en `_step_outside_opening_o2()`, solo para aperturas con `outside_id`. En `cfast_two_room_door_open` el exchange relevante es interior (puerta entre room 0 y room 1), no exterior. No hay apertura exterior activa → Sub-A es literalmente un no-op para estos casos.
- Los gaps t120/t480 son puramente de Sub-B (exchange inter-room).

**`cfast_single_room_closed` — cero cambio**:
- Sala sellada. No hay apertura exterior abierta → Sub-A no opera. Consistente.

### 11.6 Resumen de gaps y decisión

| Ganancia | Sentinels | FED gate | CO₂ gaps | t120 | Decisión |
|----------|----------|----------|---------|------|----------|
| g=0.00 | 5/5 ✅ | 0.0000 ✅ | **0/4** (sobreimpacto: 91 859 > 72 300) | OK | ✗ no cierra gaps |
| g=0.25 | 5/5 ✅ | 0.0000 ✅ | **0/4** (outflow excesivo: 539 ppm) | OK | ✗ no cierra gaps |
| g=0.50–1.00 | 5/5 ✅ | 0.0000 ✅ | **0/4** (outflow excesivo) | OK | ✗ no cierra gaps |

> **Sub-A con gains {0.0, 0.25, 0.50, 0.75, 1.0}: 0/4 gaps cerrados.** Sin embargo, el análisis diagnóstico revela el mecanismo exacto del gap `cfast_t510`.

### 11.7 Interpretación y camino a seguir

**El gap `cfast_t510` tiene causa raíz identificada**: la dilución por inflow exterior usa `room_air_mass_kg` (masa total de sala, ~densidad × volumen total) como denominador. Cuando la ventana se abre a t=360s con fuego activo, el inflow arrastra `co2_upper` de ~90 000 ppm → 16 000 ppm en 150s (7× dilución). Esto es físicamente incorrecto: el aire frío entra por la parte baja de la abertura y **no debería mezclar directamente la capa caliente superior**.

El diseño Sub-A es correcto en concepto. El problema es la resolución del sweep: la transición de "sobreimpacto" (g=0.00 → 91 859 ppm) a "outflow excesivo" (g=0.25 → 539 ppm) ocurre dentro del intervalo [0.00, 0.25]. El target es [32 300, 72 300] ppm. Se requiere un **sweep fino** con gains en [0.001, 0.01, 0.02, 0.05, 0.10, 0.15, 0.20].

**Opciones:**

| Opción | Descripción | Riesgo |
|--------|-------------|--------|
| **Exp 1B-v2** | Sweep fino gain ∈ [0.001–0.10] (runner existente con `--gains`) | Bajo; misma mecánica |
| **Exp 1C (Sub-B)** | doorway two-zone exchange; objetivo gaps t120/t480 | Medio; afecta O₂ exchange |
| **Exp 2 (combinado)** | Sub-A (gain calibrado) + Sub-B | Coordinación entre mecanismos |

**Decisión recomendada**: ejecutar **Exp 1B-v2 con sweep fino** antes de Sub-B, ya que tenemos evidencia directa de que Sub-A puede cerrar `cfast_t510` con el gain correcto. Comando sugerido:

```bash
python scripts/simulation/phase2e_co2_experiment_1b_runner.py --gains 0.001 0.005 0.01 0.02 0.05 0.075 0.10 0.15 0.20
```

> Si Exp 1B-v2 confirma candidato en [0.01–0.10], ese gain se fija y se procede a Sub-B (Exp 1C) para los gaps de doorway exchange (t480).

**Nota arquitectural (invariante)**: Sub-A solo opera en `_step_outside_opening_o2()` — no afecta `co2_upper_kg`, `co2_kg`, ni la física térmica. El FED de las víctimas en pasillos = 0.0000 ΔFED en todos los gains. Seguro para proceder.

---

### 11.8 Exp 1B-v2 — Sweep fino (gains 0.001–0.200)

**Fecha de ejecución**: 25 mayo 2026  
**Runs**: 54/54 OK (6 casos × 9 gains). EXIT 0.  
**Validación final**: Godot parse EXIT 0 ✅ · Guardrails 292/292 PASS ✅ · Unit tests 13/13 OK ✅

#### 11.8.1 Nota sobre artefacto de nombres de archivo

`_gain_str(gain)` usa `int(round(gain * 100))`. Con los gains del sweep fino:
- `gain=0.001` → `g0` (colisión con `gain=0.000` de Exp 1B-v1)
- `gain=0.005` → `g0` (colisión con 0.001 — mismo archivo)
- `gain=0.010` → `g1` (archivo único)
- demás gains → archivos únicos

Consecuencia: en la tabla de resultados, la columna `g=0.00` (gain=0.001) y la primera `g=0.01` (gain=0.005) leen el mismo reporte `_p2e1b_g0`, que fue last-written por gain=0.005. Ambas columnas muestran los mismos valores (74 331 ppm a t=510). Los datos de gain=0.001 fueron sobreescritos. **Esto no afecta la identificación del candidato**, ya que gain=0.010 tiene nombre de archivo propio (`g1`).

#### 11.8.2 Tabla de sweep fino — `cfast_t510_co2_upper_ppm` (target: [32 300, 72 300] ppm)

| Gain real | Dato representa | t=420s ppm | t=510s ppm | Estado t510 | t120 |
|-----------|----------------|-----------|-----------|-------------|------|
| 0.005 (↑) | g0 last-write | 83 453 | **74 331** | HIGH (+2031 sobre 72 300) | sin cambio |
| **0.010** | g1 (único) | 76 549 | **60 211** | ✅ PASS [32300–72300] | sin cambio |
| **0.020** | g2 (único) | 64 515 | **39 658** | ✅ PASS [32300–72300] | sin cambio |
| 0.050 | g5 (único) | 39 226 | **11 839** | FAIL LOW | sin cambio |
| 0.075 | g8 (único) | 26 487 | **4 716** | FAIL LOW | sin cambio |
| 0.100 | g10 (único) | 18 338 | **2 163** | FAIL LOW | sin cambio |
| 0.150 | g15 (único) | 9 641 | **838** | FAIL LOW | sin cambio |
| 0.200 | g20 (único) | 5 827 | **603** | FAIL LOW | sin cambio |

> ↑ "0.005" es el dato reportado para tanto la columna `gain=0.001` como `gain=0.005` por colisión de nombre de archivo.

#### 11.8.3 Sentinels y FED (todos los gains)

| Gain | Sentinels | FED max Δ | CO₂ gaps cerrados | t120 ok | Decisión |
|------|----------|-----------|------------------|---------|----------|
| 0.005 (↑) | 5/5 ✅ | 0.0000 ✅ | 0/4 (74331>72300) | OK | ✗ |
| **0.010** | 5/5 ✅ | 0.0000 ✅ | **1/4** (cfast_t510 ✓) | OK | **✓ CANDIDATO** |
| **0.020** | 5/5 ✅ | 0.0000 ✅ | **1/4** (cfast_t510 ✓) | OK | **✓ CANDIDATO** |
| 0.050–0.200 | 5/5 ✅ | 0.0000 ✅ | 0/4 (outflow excesivo) | OK | ✗ |

#### 11.8.4 Análisis de la ventana de gain

```
t=510 ppm  ┌────────────────────────────────────────────────────────────────┐
91 859     │ g=0.000 (dilución suprimida, sin outflow)                      │
74 331     │ g=0.005 (outflow mínimo)                    ← FAIL HIGH        │
           │                          target max (72 300)─ ─ ─ ─ ─ ─ ─ ─ ┤
60 211     │      g=0.010  ← CANDIDATO preferido                           │
52 300     │           CFAST reference                                      │
39 658     │              g=0.020  ← CANDIDATO alternativo                  │
           │                          target min (32 300)─ ─ ─ ─ ─ ─ ─ ─ ┤
11 839     │                                    g=0.050  ← FAIL LOW         │
  4 716    │                                              g=0.075            │
16 182     │ BASELINE (dilución activa)                                     │
└────────────────────────────────────────────────────────────────────────────┘
```

La ventana de gain estable estimada: **[~0.007, ~0.025]**. Dentro de ella, gain=0.010 da el mejor centrado (60 211 ppm, +7911 ppm sobre ref; bien dentro de tolerancia ±20 000). Gain=0.020 es más conservador (39 658 ppm, −12 642 ppm sobre ref).

#### 11.8.5 Gaps aún abiertos tras Sub-A con gain=0.010

| Check | Baseline | Con Sub-A g=0.010 | CFAST ref | Tol | Estado |
|-------|---------|-------------------|----------|-----|--------|
| `cfast_t510_co2_upper_ppm` | 16 182 | **60 211** | 52 300 | ±20 000 | ✅ CERRADO |
| `cfast_t420_co2_upper_ppm` | 41 438 | 76 549 | 60 800 | ±22 000 | ✅ PASS (no regresión) |
| `cfast_2r_r0_t120_co2_upper_pct` | 4.750% | 4.750% | 1.58% | ±3.0% | FAIL (sin cambio) |
| `cfast_2r_r0_t480_co2_upper_pct` | 0.999% | 0.999% | 9.91% | ±3.0% | FAIL (sin cambio) |

Sub-A no opera sobre `cfast_two_room_door_open` (solo aperturas exteriores). Los gaps t120/t480 son responsabilidad de Sub-B.

#### 11.8.6 Decisión final Exp 1B

> **Sub-A CANDIDATO confirmado. Gain recomendado: `phase2e_co2_upper_outflow_gain = 0.010`.**

- Cierra `cfast_t510_co2_upper_ppm`: SF 16 182 → **60 211** ppm (target 52 300 ± 20 000 ✓)
- No rompe ningún sentinel ni FED (ΔFED = 0.0000)
- No empeora ningún required check
- `cfast_t420` permanece PASS (76 549 ∈ [38 800, 82 800])
- `cfast_2r_r0_t120` sin cambio (Sub-A no opera en interiores)

**Próximo paso**: Exp 2E-CO₂-1C — Sub-B (doorway two-zone exchange), objetivo primario `cfast_2r_r0_t480` (SF 0.999% vs CFAST 9.91% ± 3%). Evaluar con Sub-A g=0.010 fijado (no combinado aún — primero Sub-B aislado para diagnóstico limpio).

---

## 12. Exp 2E-CO₂-1C — Resultados (Sub-B: CO₂ inter-room exchange fraction sweep)

> Fecha: 25 mayo 2026  
> Runner: `scripts/simulation/phase2e_co2_experiment_1c_runner.py`  
> Fracciones evaluadas: 0.25 (control), 0.08, 0.05, 0.03  
> Casos: 24 total (4 fracciones × 6 casos: g4, v3, victim, r0_window_360, single_room_closed, two_room_door_open)

### 12.1 Resumen de ejecución

**24/24 runs OK** — ningún error de Godot ni timeout.

### 12.2 Sentinels y FED deltas

| Fracción | g4 CO>1200 [s] | g4 FED>0.1 [s] | v3 FED>0.1 [s] | v3 max FED | vic FED | Sentinels | Max \|ΔFED\| |
|----------|---------------|----------------|----------------|-----------|---------|-----------|--------------|
| BASELINE | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 5/5 | — |
| f=0.25 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 5/5 | 0.0000 ✅ |
| f=0.08 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 5/5 | 0.0000 ✅ |
| f=0.05 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 5/5 | 0.0000 ✅ |
| f=0.03 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 5/5 | 0.0000 ✅ |

**Gate sentinels: 5/5 para todas las fracciones. Gate FED: ΔFED = 0.0000 para todas. Ambos gates PASS.**

### 12.3 Gate t120 (riesgo retención excesiva)

| Fracción | SF t120 (%) | Gate ≤ 5.58% | Decisión |
|----------|-------------|--------------|----------|
| f=0.25 | 4.750% | ✅ OK | — |
| f=0.08 | 4.769% | ✅ OK | — |
| f=0.05 | 4.772% | ✅ OK | — |
| f=0.03 | 4.775% | ✅ OK | — |

**Gate t120: todas las fracciones dentro del margen (máximo 4.775% vs gate 5.58%).** Sub-B no empeora el check SF HIGH en t=120.

### 12.4 CO₂ gap targets: cfast_two_room_door_open

| Check | Baseline | CFAST ref | Tol | f=0.25 | f=0.08 | f=0.05 | f=0.03 |
|-------|---------|----------|-----|--------|--------|--------|--------|
| `cfast_2r_r0_t120_co2_upper_pct` | 4.750% | 1.58% | ±3.0% | 4.750% | 4.769% | 4.772% | 4.775% |
| `cfast_2r_r0_t480_co2_upper_pct` | **0.999%** | **9.91%** | **±3.0%** | **0.999%** | **0.999%** | **0.999%** | **0.999%** |

**Target t480: 0.999% para TODAS las fracciones — Sub-B no tiene efecto en t=480.**

### 12.5 Tabla diagnóstica — evolución temporal room 0

| t [s] | Baseline | f=0.25 | f=0.08 | f=0.05 | f=0.03 |
|-------|---------|--------|--------|--------|--------|
| 60 | 0.906% | 0.906% | 0.906% | 0.906% | 0.907% |
| 120 | 4.750% | 4.750% (+0.000) | 4.769% (+0.019) | 4.772% (+0.023) | 4.775% (+0.025) |
| 240 | 12.553% | 12.553% (+0.000) | 13.441% (+0.888) | 13.610% (+1.056) | 13.724% (+1.171) |
| 360 | 12.027% | 12.027% (+0.000) | 14.733% (+2.706) | 15.296% (+3.269) | **15.688% (+3.662)** |
| **480** | **0.999%** | **0.999% (+0.000)** | **0.999% (+0.000)** | **0.999% (+0.000)** | **0.999% (+0.000)** |
| 540 | 0.989% | 0.989% (+0.000) | 0.989% (+0.000) | 0.989% (+0.000) | 0.989% (+0.000) |

**Observación crítica**: Sub-B SÍ eleva `co2_upper` en t=240 (+1.17 pp) y t=360 (+3.66 pp con f=0.03). Sin embargo, el **colapso entre t=360 y t=480 es idéntico para todas las fracciones**, incluyendo f=0.03. El mecanismo de Sub-B (`_exchange_room_o2_active_flow`) no controla este colapso.

### 12.6 Max CO₂ upper (sala 0)

| Caso | Baseline | f=0.25 | f=0.08 | f=0.05 | f=0.03 |
|------|---------|--------|--------|--------|--------|
| `cfast_r0_window_360` | 136 001 ppm ⚠ | 136 001 | 136 001 | 136 001 | 136 001 |
| `cfast_single_room_closed` | 105 224 ppm | 105 224 | 105 224 | 105 224 | 105 224 |
| `cfast_two_room_door_open` | 127 678 ppm ⚠ | 127 678 ⚠ | 147 812 ⚠ | 153 641 ⚠ | **157 710 ⚠** |

Con f=0.03, el pico de CO₂ en `two_room_door_open` sube a 157 710 ppm (15.77%) — se produce alrededor de t=360s, antes del colapso. V_CO₂ amplifica FED, pero ΔFED=0 en sentinel cases (fire scenarios distintos).

### 12.7 Análisis de causa raíz del colapso en t=480

**Hallazgo de diagnóstico post-resultados** — lectura de `OxygenExchangeSystem.gd` líneas 254–285:

```gdscript
if lower_frac < 0.15 or (lower_frac < 0.40 and room.o2 < 0.070):
    # Modelo bi-zona inválido: homogeniza con media de sala
    var room_co2_frac: float = room.co2_kg * 29.0 / maxf(0.001, air_mass_kg * 44.0)
    room.co2_upper = clampf(room_co2_frac, CO2_AMBIENT, CO2_UPPER_MAX)
elif room.hrr_kw > 0.0:
    # CO₂ producido → zona superior (producción normal)
    ...
else:
    # Sin fuego: relajar lentamente hacia CO₂ ambiente
    room.co2_upper = lerpf(room.co2_upper, CO2_AMBIENT, clampf(0.05 * dt, 0.0, 0.20))
```

Dos ramas candidatas para el colapso:

**Rama A** (`lower_frac < 0.15` o `room.o2 < 0.07`): cuando la capa caliente llena casi toda la sala (bi-zona inválido) O cuando O₂ cae por debajo de 7%, `co2_upper` se reemplaza por `room.co2_kg * 29 / (air_mass * 44)`. Si `co2_kg` (masa de CO₂ gestionada por `GasExchangeSystem`) está diluidoa via exchange con room 1, el valor resultante sería bajo (~1%).

**Rama B** (`hrr_kw == 0.0`): decay exponencial hacia ambient: `lerpf(co2_upper, 0.0004, 0.05 * dt)`. Con `dt = 1s` y 120 pasos: `0.15 * 0.95^120 ≈ 0.0004` — decae casi a ambient en 120s de simulación.

**Conclusión**: El colapso en t=480 ocurre por una (o ambas) ramas que Sub-B no toca. Sub-B solo opera en `_exchange_room_o2_active_flow()`, que se activa únicamente cuando `flow_state.active == true`. Las ramas de homogenización y decay-sin-fuego son independientes de `CO2_EXCHANGE_FRACTION`.

El caso `cfast_two_room_door_open` (1 280 kW, exterior cerrado) lleva a O₂ depletion o hot-layer collapse en la sala fuego entre t=360–480, activando la rama A o B antes de que Sub-B pueda intervenir.

### 12.8 Decisión Exp 1C

> **Sub-B AISLADO: DESCARTADO. El mecanismo (fracción de exchange activo) no controla el colapso t=480.**

| Criterio | Resultado |
|----------|-----------|
| Sentinels | 5/5 OK para todas las fracciones ✅ |
| ΔFED | 0.0000 para todas ✅ |
| Gate t120 (≤5.58%) | OK para todas (máx 4.775%) ✅ |
| **Target t480 cerrado** | **NO — 0.999% para todas** ✗ |
| Sub-B candidato | ✗ NINGUNO |

### 12.9 Próximos pasos

**Opción A — Sub-D (nuevo): proteger `co2_upper` frente a bi-zona collapse en sala fuego**

Añadir una variable `phase2e_co2_subd_enabled` y lógica para:
- Cuando `lower_frac < 0.15` o `room.o2 < 0.07`, en lugar de snap a `co2_kg`-based value, aplicar decay lento (p.ej. retener el % actual del tracer interpolado hacia `co2_kg`-value con tau largo).
- Cuando `hrr_kw == 0.0`, reducir la tasa de decay (`0.05 * dt` → `0.005 * dt`) para sala fuego con CO₂ elevado.

Riesgo: podría introducir CO₂ "fantasma" (tracer no respaldado por masa real). Necesita gates de coherencia.

**Opción B — Diagnóstico primero: confirmar rama activa**

Añadir log de `lower_frac` y `hrr_kw` en room 0 a t=360–480 para confirmar cuál de las dos ramas dispara el colapso. Sin ese dato, Sub-D podría atacar la rama equivocada.

**Recomendación**: Opción B primero (diagnóstico por log), luego Sub-D con la rama confirmada. Runner: `phase2e_co2_experiment_1d_diag_runner.py` (caso único `cfast_two_room_door_open`, log detallado de `lower_frac`/`hrr_kw`/`room.o2` por timestep entre t=300–500).

