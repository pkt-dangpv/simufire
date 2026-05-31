# Plan de Trabajo — SimuFire Motor de Física
**Creado**: 30 mayo 2026 | **Estado validación en el momento de creación**: 367/367 PASS required, 9 gaps non-gating  
**Última actualización**: junio 2026 | **Estado actual**: 376/376 PASS required, 6 gaps non-gating
**Base física**: `8c83ced` (main) — Phase 2C HVAC two-zone O₂ feed cerrada; Phase 3 diseño documentado

---

## 1. Situación actual

### 1.1 Línea base de validación
| Métrica | Valor |
|---------|-------|
| Checks required PASS | **373 / 373** |
| Checks non-gating (gaps) | **3** |
| Total checks registrados | 520 |
| Guardrails | ✅ Exit 0 |
| Unit tests | ✅ 13/13 |
| Último commit de producción | `e4564e3` — Phase 2A doorway hot-gas O₂ routing |

### 1.2 Arquitectura del motor (capas físicas implementadas)

| Capa | Estado | Descripción |
|------|--------|-------------|
| Combustión | ✅ Estable | t², flashover, extinción por O₂/combustible, smoldering, backdraft |
| Transporte térmico | ✅ Estable | Bernoulli two-zone, `doorway_heat_exchange_coeff`, radiación Stefan-Boltzmann, gradiente vertical |
| O₂ tracking | ✅ Estable + opt-in two-zone | `o2_upper` + `o2_lower` como vars de sala; `doorway_o2_upper_routing_gain` opt-in para doorway hot-gas; `phase2h` opt-in para HVAC |
| Humo/gases | ✅ Estable | CO, CO₂, HCN, FED (ISO 13571), SVV, visibilidad |
| Presión | ⚠️ Parcial | Boyancia termostática 1-10 Pa; CFAST two-zone = 100-1000 Pa |
| Paredes | ✅ Crank-Nicolson | PDE 5 nodos, conducción entre salas |
| Ventilación | ✅ Bernoulli | `vent_bernoulli_enabled=true` por defecto |
| HVAC | ✅ opt-in (`phase2h`) | Red retorno/suministro por alturas; benchmark CFAST usa impulsión baja + retorno alto, default SimuFire usa rejillas altas |
| Gradiente vertical | ✅ Estable | `estimate_temperature_at_height_m`, `thermal_gradient_band_fraction=0.35` |

### 1.3 Comandos de trabajo estándar
```powershell
# Correr caso individual
& "F:\OneDrive\Escritorio\Godot_v4.6.3-stable_win64_console.exe" --headless --path "F:\OneDrive\Documentos\GitHub\simufire" -- --validation-case=<NOMBRE>

# Suite completa
python scripts/simulation/validate_reference_cases.py

# Guardrails (salida compacta, exit 0 = OK)
python scripts/simulation/validation_guardrails.py

# Unit tests
python tests/test_guardrails.py
```

---

## 2. Inventario de gaps activos

### 2.1 Descripción técnica de cada gap

#### GAP-1: `ghanekar_flashover_0_9m_known_gap` — ✅ CERRADO (Phase 1.7, 2026-05-31)
- **Qué mide**: tiempo en que T(z=0.9 m) ≥ 600°C en sala de origen (dormitorio Ghanekar)
- **Referencia**: 186 ± 30 s (ventana 156–216 s)
- **Resultado**: `time_room_0_temp_0_9m_above_600c_s` = 166.75s ∈ [156,216]s ✅
- **Guardas**: `peak_temp_upper_c_global` = 620.5°C ∈ [450,650]°C; `time_room_2_o2_below_20_4pct_s` = 215.6s ∈ [168,228]s
- **Fix aplicado**: `fire_alpha_kw_s2=0.035` + `outside_open_upper_heat_boost=0.20` en `ghanekar_bedroom_hallway.json`
- **Promovido a**: required=True en `build_ghanekar_checks()`
- **Commit**: `cc48382`

#### GAP-2: `ghanekar_kitchen_far_hall_fed_1_0_s` — ✅ CERRADO (Phase 2, 2026-05-28)
- **Qué mide**: tiempo FED=1.0 en pasillo lejano, caso cocina Ghanekar
- **Resultado**: 743.6s ∈ [498, 750] s ✅ (fire_co_vent_limited_multiplier=110, fed_upper_layer_threshold_m=2.0)
- **Promovido a**: required=True en `build_ghanekar_kitchen_checks()`

#### GAP-3: `ghanekar_kitchen_far_hall_idlh_co_s` — ✅ CERRADO (Phase 2, 2026-05-28)
- **Qué mide**: tiempo CO>1200 ppm en pasillo lejano, caso cocina Ghanekar
- **Resultado**: 684.4s ∈ [540, 744] s ✅ (misma calibración que GAP-2)
- **Promovido a**: required=True

#### GAP-4: `ghanekar_kitchen_fire_room_flashover_s` — ✅ CERRADO (Phase 2, 2026-05-28)
- **Qué mide**: flashover en sala viva (R3=Living Room), caso cocina Ghanekar
- **Resultado**: 873.75s ∈ [864, 924] s ✅ (doorway_heat_exchange_coeff=0.30 + CO vent-limited)
- **Promovido a**: required=True

#### GAP-5: `cfast_overpressure_sealed_pending`
- **Qué mide**: presión termódinámica en sala sellada (100-1000 Pa)
- **Situación actual**: SF genera 1-10 Pa (modelo termostático) vs CFAST 100-2000 Pa (boyancia two-zone)
- **Fix necesario**: modelo de presión termodinámica completo — integración de la ley de gases ideales en los dos volúmenes de zona (upper/lower), con pérdida por infiltraciones. Phase 3.

#### GAP-6: `cfast_co2_stratification_pending`
- **Qué mide**: mol% CO₂ en zona superior — diferencia entre mezcla uniforme (SF) vs estratificación two-zone (CFAST)
- **Situación actual**: SF promedia CO₂ en volumen total; CFAST retiene CO₂ en zona caliente (~7-8% upper vs ~1% lower)
- **Fix necesario**: CO₂ upper/lower tracking bidireccional (transporte selectivo a zona superior, dilución diferente por zona). Phase 2.

#### GAP-7: `cfast_hall_upper_o2_doorway_pending` — ✅ CERRADO (Phase 2A, 2026-06-01)
- **Qué mide**: depleción de O₂ en zona SUPERIOR del pasillo — gas caliente pobre en O₂ entra por mitad alta del vano de puerta
- **Resultado**: checks hall O₂ comparan `sim_field="o2_upper"` vs CFAST ULO2 y pasan con tolerancias tight: t=120 diff=0.005, t=240 diff=0.015, t=360 diff=0.051 ≤ 0.060
- **Fix aplicado**: `doorway_o2_upper_routing_gain=1.0` opt-in en `cfast_two_room_door_open.json`; default 0.0 no-op
- **Commit**: `e4564e3`

#### GAP-8: `cfast_hrr_ventilation_limited_f2_pending` — ✅ CERRADO (Phase 2, 2026-05-31)
- **Qué mide**: limitación de HRR por O₂ de zona superior (fuego usa solo zona caliente, no mezcla uniforme)
- **Resultado**: stub eliminado; check real `cfast_t240_hrr_structural_ratio` actual=1.91 ≤ 2.5
- **Fix aplicado**: `fire_o2_upper_hrr_blend` opt-in en `CombustionSystem.gd` / `SimulationEngine.gd`; default 0.0 no-op
- **Commit**: `a21326e`

#### GAP-9: `cfast_hvac_two_zone_feed_pending`
- **Qué mide**: el benchmark CFAST `cfast_hvac_residential` usa impulsión de aire exterior baja (0.25 m) y retorno alto (2.30 m); esa configuración mantiene O₂ en zona inferior y puede sostener el fuego.
- **Situación actual**: Phase 2H opt-in existe pero default OFF; el modelo general de HVAC ya admite alturas de rejillas, pero el cierre del gap requiere promover/validar el caso low-supply/high-return.
- **Fix necesario**: habilitar Phase 2H como default solo para la configuración física correcta, validar que el test set completo sigue PASS, y remover el gap. Requiere rebaseline selectivo.

---

## 3. Clasificación de gaps por bloqueo técnico

```
┌─────────────────────────────────────────────────────────────────────┐
│  NIVEL 1 — Calibración de datos de caso (COMPLETADO)                │
│  GAP-1: Ghanekar 0.9m flashover cerrado en Phase 1.7 (`cc48382`)    │
└─────────────────────────────────────────────────────────────────────┘
         ↓ no resuelve → depende del motor de progresión de objetos

┌─────────────────────────────────────────────────────────────────────┐
│  NIVEL 2 — Extensión del motor de combustión (COMPLETADO)           │
│  GAP-2,3,4: yield CO vent-limited (usa o2_upper → CombustionSystem) │
│  GAP-8: o2_upper como input efectivo a HRR cap opt-in               │
│         → `fire_o2_upper_hrr_blend`; stub reemplazado por ratio     │
└─────────────────────────────────────────────────────────────────────┘
         ↓ desbloquea

┌─────────────────────────────────────────────────────────────────────┐
│  NIVEL 3 — Two-zone species routing                                 │
│  GAP-7: hot-gas doorway upper O₂ routing CERRADO                     │
│         → `doorway_o2_upper_routing_gain`; default no-op             │
│  GAP-6: CO₂ stratification                                          │
│         → extender patrón doorway a CO₂ upper/lower                 │
│  GAP-9: Phase 2H → default ON                                       │
│         → habilitar preset + rebaseline HVAC checks                 │
└─────────────────────────────────────────────────────────────────────┘
         ↓ desbloquea

┌─────────────────────────────────────────────────────────────────────┐
│  NIVEL 4 — Modelo de presión termodinámica (esfuerzo MUY ALTO)      │
│  GAP-5: overpressure sealed                                          │
│         → Phase 3: ODE presión por zona, integración ley gases ideal │
│         → rompe todos los checks de presión actuales (rebaseline)    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Fases planificadas

### FASE 1.7 — Ghanekar 0.9m flashover (GAP-1) — ✅ COMPLETADA (2026-05-31)
**Objetivo**: cerrar `ghanekar_flashover_0_9m_known_gap`  
**Resultado**: T@0.9m cruza 600°C a 166.75s, dentro de [156,216]s.  
**Cambios**: `fire_alpha_kw_s2=0.035` y `outside_open_upper_heat_boost=0.20` en `ghanekar_bedroom_hallway.json`.  
**Guardas PASS**: pico global 620.5°C ∈ [450,650]°C; respuesta O2 far hall 215.6s ∈ [168,228]s.  
**Estado**: promovido a required=True; base actual `373/373 PASS`, 3 gaps.

---

### FASE 2 — CO/HRR vent-limited via o2_upper (GAP-2, 3, 4, 8) — ✅ COMPLETADA (2026-05-31)
**Objetivo original**: cerrar los 3 gaps del caso `ghanekar_kitchen` y el gap HRR vent-limited CFAST  
**Logrado**: GAP-2 (fed_1_0: 743.6s), GAP-3 (idlh_co: 684.4s), GAP-4 (flashover: 873.75s) — todos required=True  
**Logrado GAP-8**: stub `cfast_hrr_ventilation_limited_f2_pending` eliminado; `cfast_t240_hrr_structural_ratio` confirma ratio SF/CFAST=1.91 ≤2.5 con `fire_o2_upper_hrr_blend` opt-in.
**Parámetros calibrados**: `fire_co_vent_limited_multiplier=110`, `fed_upper_layer_threshold_m=2.0`, `doorway_heat_exchange_coeff=0.30`  
**Commits**: `c67802b` (calibración) + `156fb81` (CO vent-limited combustion phase) + `a21326e` (HRR blend opt-in)

**Descripción técnica**:

#### 2.1 — CO yield vent-limited
- En `CombustionSystem.gd::step_room_fire()`, reemplazar `room.o2` por `room.o2_upper` como señal de calidad de combustión
- Activar rama `low_quality` de CO cuando `o2_upper < 0.12` (threshold configurable)
- Multiplicador de CO vent-limited: `fire_co_vent_limited_multiplier` (target: ×80–100 sobre baseline ventilado)
- Calibrar con `ghanekar_kitchen_living_room` como caso de referencia: objetivo CO_pico R2 ≥ 10,000 ppm

#### 2.2 — HRR limitado por O₂ upper
- En `SimulationEngine.gd::_step_fire_for_room()`, añadir cap de HRR cuando `room.o2_upper < fire_fds_extinction_o2_limit_ambient`
- Este cap reemplaza el O₂ promedio para la limitación de llama: `effective_o2 = min(room.o2, room.o2_upper)`
- Verificar que los 372 checks existentes no regresen (el cambio solo actúa cuando hay gradiente O₂ upper/lower)

**Archivos a modificar**: `sim/fire/CombustionSystem.gd`, `sim/core/SimulationEngine.gd`  
**Nuevo parámetro**: `fire_co_vent_limited_o2_threshold: float = 0.12`  
**Nuevo parámetro**: `fire_co_vent_limited_multiplier: float = 80.0`

**Criterio cumplido para GAP-2/3/4**:
- `ghanekar_kitchen_far_hall_fed_1_0_s`: actual ∈ [498, 750] s
- `ghanekar_kitchen_far_hall_idlh_co_s`: actual ∈ [540, 744] s
- `ghanekar_kitchen_fire_room_flashover_s`: actual ∈ [864, 924] s
- 372/372 required PASS con los 5 checks Ghanekar kitchen promovidos

**Criterio cumplido para GAP-8**:
- `cfast_hrr_ventilation_limited_f2_pending` eliminado tras implementar HRR blend opt-in por `o2_upper`
- Required PASS actualizado sin aumentar tolerancias del check legacy `cfast_t240_hrr_ventilation_limited`

**Riesgo**: el multiplicador de CO afecta FED en casos existentes. Revisar especialmente `ghanekar_bedroom_hallway` (fuego también en zona parcialmente vent-limited). Usar override por caso si hay regresión.

---

### FASE 2A — Doorway hot-gas O₂ upper routing (GAP-7) — ✅ COMPLETADA (2026-06-01)
**Objetivo**: cerrar `cfast_hall_upper_o2_doorway_pending`  
**Prerequisito**: Phase 2 (o2_upper estable en combustión)  
**Resultado**: 373/373 required PASS, gaps 4→3

**Cambios aplicados**:
- `OxygenExchangeSystem.gd`: nuevo `doorway_o2_upper_routing_gain` default 0.0. Cuando `gain>0`, mezcla `hot_room.o2_upper` en `cold_room.o2_upper` con tasa `gain × exchange_kg / cold_upper_mass`.
- Relax no-fire: con `gain>0`, la zona superior relaja hacia `outside_o2` en vez de hacia `room.o2`, evitando que el upper layer quede artificialmente depleto sin fuego.
- `SimulationEngine.gd`: parámetro exportado y reenviado en `configure()`.
- `cfast_two_room_door_open.json`: `doorway_o2_upper_routing_gain=1.0`.
- `validate_reference_cases.py`: checks hall O₂ usan `sim_field="o2_upper"` vs CFAST ULO2; tolerancias tight t120=0.020, t240=0.025, t360=0.060; RMSE ≤0.060.

**Criterio cumplido**:
- t=120: SF hall `o2_upper`=0.200 vs CFAST ULO2=0.195, diff=0.005 ≤0.020
- t=240: SF=0.097 vs CFAST=0.111, diff=0.015 ≤0.025
- t=360: diff=0.051 ≤0.060; residual estructural porque SF mantiene fuego activo mientras CFAST extingue por depleción O₂ upper

**Commit**: `e4564e3`

---

### FASE 2B — CO₂ two-zone tracking (GAP-6)
**Objetivo**: cerrar `cfast_co2_stratification_pending`  
**Prerequisito**: Phase 2A (doorway two-zone routing activo)  
**Esfuerzo estimado**: 2-3 sesiones

**Descripción técnica**:
- Añadir `co2_lower_kg` como variable de sala en `RoomModel.gd`
- Modificar generación de CO₂ en `CombustionSystem.gd`: todo el CO₂ generado va a zona superior
- Modificar transporte en `_transfer_hot_gas_contaminants`: CO₂ se mueve con flujo upper según two-zone routing (Phase 2A)
- `compute_co2_lower_ppm()` como nueva función en `ThermalSystem.gd`

**Criterio de cierre**:
- `cfast_co2_stratification_pending`: CO₂ upper ≥ 5% en sala fuego a t=240/350 s
- Los checks `cfast_fo_t240_co2_upper_pct` (actualmente tolerancia 4.5%) deben seguir PASS

---

### FASE 2C — Phase 2H como default ON (GAP-9)
**Objetivo**: cerrar `cfast_hvac_two_zone_feed_pending`  
**Prerequisito**: Phase 2A completada y estable  
**Esfuerzo estimado**: 1-2 sesiones

**Descripción técnica**:
- Cambiar `phase2h_o2_doorway_two_zone_enabled = false` a `true` en `SimulationEngine.gd` (o en preset de producción)
- Ejecutar suite completa; identificar y rebasar los checks que cambian por HVAC feed
- Actualizar `sim/resources/presets/phase2h_o2_lower_replenish_candidate.json`: status `accepted_opt_in` → `production`
- No generalizar el gap a todos los HVAC: el caso CFAST actual representa impulsión baja + retorno alto + aire exterior.

**Presets HVAC a implementar antes de llamar al modelo "residencial general"**:
| Preset | Configuración | Uso esperado |
|--------|---------------|--------------|
| `hvac_cfast_low_supply_high_return` | Supply 0.25 m, return 2.30 m, `outside_air_fraction=1.0` o caudal exterior explícito | Reproducir benchmark CFAST actual y cerrar GAP-9 |
| `hvac_us_forced_air_floor_supply` | Impulsiones bajas/suelo, retorno alto o central, recirculación dominante con posible aire exterior bajo | Vivienda norteamericana con forced-air clásico |
| `hvac_es_ceiling_ducts_recirc` | Impulsión alta + retorno alto, `outside_air_fraction=0.0` por defecto | Conductos de falso techo típicos en España: redistribuye humo/calor, no repone O₂ |
| `hvac_balanced_hrv_erv` | Aire exterior bajo/medio, extracción baños/cocina, caudal menor | Ventilación mecánica balanceada con recuperación |

**Criterio de cierre**:
- `cfast_hvac_two_zone_feed_pending`: fuego activo en HVAC case, T_upper HVAC ≥ umbral relevante
- 367+N/367+N PASS tras rebaseline

---

### FASE 3 — Modelo de presión termodinámica (GAP-5)
**Objetivo**: cerrar `cfast_overpressure_sealed_pending`  
**Prerequisito**: INDEPENDIENTE (no necesita Phase 2A), pero altamente disruptivo  
**Esfuerzo estimado**: 6-10 sesiones  
**Estado diseño**: DISEÑO TÉCNICO COMPLETO — pendiente de implementación (2026-06-XX)

---

#### 3.1 Motivación

El modelo actual de presión en SF (`step_pressure_venting`) calcula **boyancia únicamente** y produce 1–10 Pa.  
CFAST usa un modelo termodinámico two-zone (ley de gases ideales + ODE de masa/energía) y produce 100–2000 Pa en sala sellada.

| Caso | t (s) | SF actual (Pa) | CFAST esperado (Pa) |
|------|--------|----------------|---------------------|
| cfast_single_room_closed | 60 | 0.4 | 124 |
| cfast_single_room_closed | 120 | 2.0 | **1 022** ← criterio cierre |
| cfast_single_room_closed | 180 | 3.0 | 768 |
| cfast_fast_growth_closed | 60 | 1.2 | 490 |
| cfast_fast_growth_closed | 120 | 4.0 | **2 088** |

Hay **31 checks `pressure_pa`** en el suite (todos `required=False`, 30 PASS / 1 FAIL al 2026-06-XX).  
Los 31 tolerances actuales son `|diff|+2 Pa` (SF≈1–10 Pa, CFAST=0–2088 Pa) — pasan porque el gap es ≤ tol.

---

#### 3.2 Ecuación gobernante

La ODE de presión termodinámica para sala de volumen fijo con una zona de gases mezclados:

$$\frac{dP_{therm}}{dt} = \frac{(\gamma-1) \cdot \dot{Q}_{conv}}{V} - \frac{C_d \cdot A_{eff}}{V} \cdot P_{atm} \cdot \sqrt{\frac{2 \, P_{therm}}{\rho_{amb}}}$$

| Símbolo | Valor / Fuente |
|---------|---------------|
| $\gamma$ | 1.4 (gas diatómico ideal) |
| $\dot{Q}_{conv}$ | `hrr_kw × (1 - chi_rad) × 1000` [W] |
| $V$ | `room.volume_m3()` [m³] |
| $C_d$ | 0.61 (coeficiente de descarga estándar) |
| $A_{eff}$ | área efectiva de infiltración → ver §3.3 |
| $P_{atm}$ | 101 325 Pa (presión atmosférica) |
| $\rho_{amb}$ | 1.2 kg/m³ (densidad aire ambiente) |
| $P_{therm}$ | `room.pressure_pa_therm` [Pa] (nuevo campo) |

**Interpretación del término de fuga**: el gasto másico de infiltración es  
$\dot{m}_{fuga} = C_d A_{eff} \sqrt{2 \rho_{amb} P_{therm}}$ [kg/s]  
y el relieve de presión que produce es $P_{atm} \dot{m}_{fuga} / (\rho_{amb} V)$ [Pa/s].

Nota: para salas con aperturas grandes (`open_factor > 0`), la presión se ventea rápido y $P_{therm}$ converge a ~0 Pa — el comportamiento es correcto sin necesidad de lógica adicional.

---

#### 3.3 Derivación del área de infiltración desde ACH

El parámetro de entrada es `ach_infiltration` (default 0.5, sellada usa 5.0).  
La referencia estándar es ACH a 50 Pa (blower door). Se asume:

$$A_{eff} = \frac{ACH_{50} \cdot V / 3600}{C_d \cdot \sqrt{2 \cdot P_{ref50} / \rho_{amb}}}$$

con $P_{ref50} = 50$ Pa y $ACH_{50} \approx ach\_infiltration$ (conservador — CFAST usa el mismo parámetro como ACH natural).

Para `ach_infiltration=5.0`, $V=62$ m³: $A_{eff} \approx 0.0155$ m².  
Alternativamente, exponer `phase3_leak_area_m2` como override explícito en `engine_overrides` para ajuste fino por caso.

---

#### 3.4 Estrategia de implementación (campo paralelo)

**Invariante clave**: NO modificar `room.overpressure_pa` ni ningún sistema que lo consuma.  
Todo el downstream (smoke venting, doorway exchange, ThermalSystem, etc.) sigue usando `overpressure_pa` sin cambios.

**Campo nuevo en `RoomModel.gd`**:
```gdscript
var pressure_pa_therm: float = 0.0  # Phase 3: termodynamic pressure ODE
```
Reseteado a 0.0 en `reset_dynamic_state()`.

**Flag opt-in en `GasExchangeSystem.gd`**:
```gdscript
var phase3_thermodynamic_pressure_enabled: bool = false
var phase3_leak_area_m2: float = 0.0  # 0.0 = derivar de ach_infiltration
```
Registrado en `configure()` con los mismos patrones existentes.

**Nuevo método `step_thermodynamic_pressure(building, dt)`** en `GasExchangeSystem.gd`:
```gdscript
func step_thermodynamic_pressure(building: BuildingModel, dt: float) -> void:
    if not phase3_thermodynamic_pressure_enabled:
        return  # default no-op: NO CAMBIA NADA
    const GAMMA: float = 1.4
    const P_ATM: float = 101325.0
    const RHO_AMB: float = 1.2
    const CD: float = 0.61
    for room in building.get_rooms().values():
        if room == null:
            continue
        var V: float = room.volume_m3()
        if V <= 0.0:
            continue
        # Área efectiva de infiltración
        var A_eff: float = phase3_leak_area_m2
        if A_eff <= 0.0:
            var ach_vol_per_s: float = ach_infiltration * V / 3600.0
            A_eff = ach_vol_per_s / (CD * sqrt(2.0 * 50.0 / RHO_AMB))
        # ODE: dP/dt = source - sink
        var q_conv_w: float = room.hrr_kw * (1.0 - chi_rad) * 1000.0
        var dP_source: float = (GAMMA - 1.0) * q_conv_w / V
        var P: float = room.pressure_pa_therm
        var dP_leak: float = 0.0
        if P > 0.0:
            dP_leak = CD * A_eff * P_ATM * sqrt(2.0 * P / RHO_AMB) / V
        room.pressure_pa_therm = maxf(0.0, P + (dP_source - dP_leak) * dt)
```

**Invocación en `SimulationEngine.gd`** (después de `step_pressure_venting`):
```gdscript
gas_exchange_system.step_thermodynamic_pressure(building, dt)
```

**Salida de log** (en el método de logging de habitación): cuando `phase3_thermodynamic_pressure_enabled`, sustituir el campo `P=` con `room.pressure_pa_therm` en lugar de `room.overpressure_pa`.  
El parser `validate_reference_cases.py` lee `P=...Pa` sin cambios → cero modificaciones en validation stack.

---

#### 3.5 Checks afectados y estrategia de rebaseline

Con Phase 3 activado **solo en los casos sellados** (vía `engine_overrides`):

**Grupo A — casos sellados (Phase 3 ON): rebaseline necesario (7–10 checks)**

| Check | SF nuevo est. | CFAST | Tol nueva candidata |
|-------|--------------|-------|---------------------|
| `cfast_closed_t60_pressure_pa` | ~110 | 124 | ±30 Pa |
| `cfast_closed_t120_pressure_pa` | ~950–1050 | 1022 | **±80 Pa** (criterio cierre ±100 Pa) |
| `cfast_closed_t240_pressure_pa` | ~50 | 12.75 | ±20 Pa |
| `cfast_closed_t360_pressure_pa` | ~150 | 167.9 | ±40 Pa |
| `cfast_closed_t480_pressure_pa` | ~150 | 168.2 | ±40 Pa |
| `cfast_fastgrowth_t60_pressure_pa` | ~400 | 489.6 | ±120 Pa |
| `cfast_fastgrowth_t120_pressure_pa` | ~1800 | 2087.7 | ±350 Pa |
| `cfast_burnout_t60_pressure_pa` | ~110 | 124.0 | ±30 Pa |
| `cfast_burnout_t120_pressure_pa` | ~950–1050 | 1022.1 | ±80 Pa |
| `cfast_burnout_t180_pressure_pa` | ~650 | 768.4 | ±130 Pa |

Estimaciones de SF basadas en la ODE con `ach_infiltration=5.0`, `V≈62 m³`. **Requieren run de calibración antes de fijar tolerancias.**

**Grupo B — casos con aperturas (Phase 3 OFF por defecto): sin cambio**

Los otros 21 checks (`cfast_t350`, `cfast_t420`, `cfast_t510`, `cfast_2r_*`, `cfast_fo_*`, `cfast_hvac_*`, `cfast_doorclose_*`, `cfast_slow_*`, `cfast_multifuel_*`) permanecen con `phase3_thermodynamic_pressure_enabled=false` → `pressure_pa_therm=0.0` → log emite `overpressure_pa` (boyancia, 1–10 Pa) → tolerancias actuales invariantes.

**Nuevo check requerido** (criterio de cierre formal):
```python
# En build_cfast_single_room_closed_checks():
add_check("cfast_closed_t120_pressure_pa", t=120.0, field="pressure_pa",
          expected=1022.0, tol=100.0, required=True)
# Sustituye la versión actual required=False con tol=1022.1
```

**Stub a eliminar**:
```
cfast_overpressure_sealed_pending  →  REMOVED de build_stage_b_pending_checks()
```

---

#### 3.6 Invariantes que NO deben romperse

| Invariante | Verificación | Riesgo de ruptura |
|-----------|-------------|-------------------|
| 376/376 required PASS | `py scripts/simulation/validate_reference_cases.py` | Bajo: Phase 3 OFF por defecto |
| `room.overpressure_pa` sin cambio | Ningún sistema downstream toca `pressure_pa_therm` por defecto | Bajo: campo completamente paralelo |
| Smoke venting logic inalterada | Sigue usando `overpressure_pa` | Ninguno |
| Doorway exchange inalterado | ThermalSystem/GasExchangeSystem usan `overpressure_pa` | Ninguno |
| Víctima FED sin regresión | `victim_fed_incapacitation` case no activa Phase 3 | Ninguno |
| Guardrails PASS | `py scripts/simulation/validation_guardrails.py` | Bajo |
| 13/13 unit tests | `py tests/test_guardrails.py` | Bajo |

---

#### 3.7 Riesgos específicos de Phase 3

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|-----------|
| ODE numéricamente inestable (dt grande) | Media | Medio | Clamp `P ≥ 0`, semiplícito o Euler con dt≤0.1 s |
| ACH→A_eff mal calibrado → SF diverge de CFAST ×2 | Alta | Medio | Override explícito `phase3_leak_area_m2` en cases JSON |
| Presión alta activa el threshold de venting existente (2 Pa) → humo extra | Alta | **Alto** | Desactivar lógica de venting basada en `overpressure_pa` cuando Phase 3 ON, o usar umbral independiente `phase3_vent_threshold_pa` |
| t>180s SF>CFAST porque SF no modela extinción O2 en sellada | Media | Medio | Phase 2C flags ya disponibles; activar si necesario |
| Rebaseline de los 10 checks sellados rompe 376 required | Baja | Alto | Los 10 son `required=False`; promover solo `cfast_closed_t120_pressure_pa` |

**Riesgo crítico (item 3)**: cuando `pressure_pa_therm` alcanza 100–1000 Pa, el código existente en `step_pressure_venting` aplicará Bernoulli venting sobre `overpressure_pa` (que sigue siendo 1–10 Pa) — no hay conflicto. Pero si en el futuro se conectan los dos campos, habría interacción.

---

#### 3.8 Plan de activación por caso

```
engine_overrides en:
  cfast_single_room_closed.json:
    "phase3_thermodynamic_pressure_enabled": true
    "phase3_leak_area_m2": <calibrar>

  cfast_fast_growth_closed.json:
    "phase3_thermodynamic_pressure_enabled": true
    "phase3_leak_area_m2": <calibrar>

  cfast_long_burnout_3600s.json:
    "phase3_thermodynamic_pressure_enabled": true
    "phase3_leak_area_m2": <calibrar>

  (todos los demás: sin override → Phase 3 OFF)
```

---

#### 3.9 Criterio de cierre

- `cfast_closed_t120_pressure_pa` promocionado a `required=True` con `tol=100 Pa`: SF ∈ [922, 1122] Pa  
- 376+1 = **377/377 required PASS**  
- 6 gaps non-gating → 5 gaps (se elimina el 1 gap activo de overpressure)  
- `cfast_overpressure_sealed_pending` eliminado de `build_stage_b_pending_checks()`  
- Todos los checks Grupo B invariantes (mismas tolerancias que ahora)

---

## 5. Roadmap y priorización

```
2026-05 (COMPLETADO)
    Phase 1.5 ✅  — entrainment temperature fix (a723e8d)
    Phase 1.6 ✅  — Bernoulli doorway_heat_exchange_coeff fix (efcf5fd)
  Stage-B ✅    — 5 casos CFAST implementados (320 required checks)
  Hardening ✅  — Stage C/D/E/F (367 required checks)
  Phase 2 ✅    — Ghanekar kitchen required + HRR structural ratio gap closed
  Phase 1.7 ✅  — Ghanekar 0.9m flashover promoted to required (373 required checks)
  Phase 2A ✅   — Doorway hot-gas O₂ upper routing (gaps 4→3)
  Phase 2B ✅   — CO₂ upper/lower stratification (commits 231b400 + b9ad841)
  Phase 2C ✅   — HVAC two-zone O₂ feed (commit 29c3515; 376/376 required, 6 gaps)

2026-06 (PRÓXIMO)
┌──────────────────────────────────────────────────────────────┐
│  SPRINT SIGUIENTE (6-10 sesiones)                            │
│  Phase 3 — Presión termodinámica                             │
│  Objetivo: GAP-5 (cfast_overpressure_sealed_pending)         │
│  Riesgo: MEDIO-ALTO (ver §3.7; campo paralelo aisla riesgo)  │
│  Diseño técnico: completo (ver §3.1–3.9 arriba)              │
└──────────────────────────────────────────────────────────────┘
```

### Tabla de prioridades

| Prioridad | Fase | Gaps cierra | Riesgo | Esfuerzo | Estado |
|-----------|------|-------------|--------|----------|--------|
| ✅ | Phase 2B | 1 (GAP-6) | Medio | Completado | Cerrado |
| ✅ | Phase 2C | 1 (GAP-9) | Medio | Completado | Cerrado |
| 1 | Phase 3 | 1 (GAP-5) | Medio-Alto | 6-10 sesiones | Diseño listo |

---

## 6. Invariantes de calidad (no deben romperse nunca)

| Invariante | Cómo verificar |
|-----------|----------------|
| 376/376 required PASS (actual) | `py scripts/simulation/validate_reference_cases.py` |
| Conteo de gaps documentado == conteo en JSON | `python scripts/simulation/validation_guardrails.py` |
| 13/13 unit tests | `py tests/test_guardrails.py` |
| 7 sentinels Phase 2E PASS | Incluido en guardrails |
| `doorway_heat_exchange_coeff` aplicado a Bernoulli | `efcf5fd` — regresión detectada por `ghanekar_origin_peak_upper_temp_reasonable_c` |
| `o2_upper` tracking activo | Regresión detectada por checks `o2_upper` en casos CFAST |
| `fire_o2_lower_for_flame` default=false | Phase 2C: solo activa en cfast_hvac_residential.json |

---

## 7. Riesgos transversales

| Riesgo | Impacto | Mitigación |
|--------|---------|-----------|
| Cambio de CO yield rompe FED timing en casos existentes | Alto | Override por caso; no cambiar defaults globales sin rebaseline |
| Two-zone doorway cambia masa transportada → T_upper regresar | Alto | Rama Git separada; validar invariantes antes de merge |
| Suavizar curva combustible Ghanekar baja T_upper pico | Bajo | Margen 42°C disponible (608°C actual, límite 650°C) |
| Phase 2H default ON altera O₂ lower o sobregeneraliza el HVAC low-supply | Medio | Aplicar por preset/altura de rejilla; no usar el benchmark CFAST como modelo universal de HVAC residencial |
| Phase 3 presión – calibración ACH→A_eff incorrecta | Medio | Override `phase3_leak_area_m2` por caso; campo paralelo aisla riesgo de regresión |

---

## 8. Estado del working tree documentado (2026-06-XX)

```
HEAD: 8c83ced (main)
  "sync post-phase-2c: rebaseline cfast_hvac_residential.json (fire survives, HRR=1280kW); untrack stale .pyc"
  
main está 4 commits adelante de origin/main
Working tree: CLEAN
Validation: 376/376 PASS, 6 non-gating gaps, ALL GUARDRAILS PASS, 13/13 unit tests
```
