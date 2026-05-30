# Plan de Trabajo — SimuFire Motor de Física
**Creado**: 30 mayo 2026 | **Estado validación en el momento de creación**: 367/367 PASS required, 9 gaps non-gating  
**Última actualización**: 30 mayo 2026 | **Estado actual**: 372/372 PASS required, 6 gaps non-gating  
**HEAD**: `156fb81` (main, sync con origin) — Phase 2 CO vent-limited completa y empujada

---

## 1. Situación actual

### 1.1 Línea base de validación
| Métrica | Valor |
|---------|-------|
| Checks required PASS | **372 / 372** |
| Checks non-gating (gaps) | **6** |
| Total checks registrados | 521 |
| Guardrails | ✅ Exit 0 |
| Unit tests | ✅ 13/13 |
| Último commit de producción | `156fb81` — Phase 2 CO vent-limited |

### 1.2 Arquitectura del motor (capas físicas implementadas)

| Capa | Estado | Descripción |
|------|--------|-------------|
| Combustión | ✅ Estable | t², flashover, extinción por O₂/combustible, smoldering, backdraft |
| Transporte térmico | ✅ Estable | Bernoulli two-zone, `doorway_heat_exchange_coeff`, radiación Stefan-Boltzmann, gradiente vertical |
| O₂ tracking | ✅ Estable (1-zona) | `o2_upper` + `o2_lower` como vars de sala; `phase2h` opt-in para HVAC |
| Humo/gases | ✅ Estable | CO, CO₂, HCN, FED (ISO 13571), SVV, visibilidad |
| Presión | ⚠️ Parcial | Boyancia termostática 1-10 Pa; CFAST two-zone = 100-1000 Pa |
| Paredes | ✅ Crank-Nicolson | PDE 5 nodos, conducción entre salas |
| Ventilación | ✅ Bernoulli | `vent_bernoulli_enabled=true` por defecto |
| HVAC | ✅ opt-in (`phase2h`) | Alimentación de zona baja, default OFF |
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

#### GAP-1: `ghanekar_flashover_0_9m_known_gap`
- **Qué mide**: tiempo en que T(z=0.9 m) ≥ 600°C en sala de origen (dormitorio Ghanekar)
- **Referencia**: 186 ± 30 s (ventana 156–216 s)
- **Situación actual**: T_upper alcanza 608°C (PASS en required check) pero T@0.9m nunca supera ~420°C
- **Causa raíz 1 — Gradiente**: `gradient_depth = hot_depth × 0.35 = 1.62 × 0.35 = 0.567 m`; con interfaz a HL=0.83 m, `grad_top = 1.11 m` → z=0.9 m queda DENTRO de la zona de transición → T@0.9m ≈ 400°C aunque T_upper=608°C
- **Causa raíz 2 — Timing**: el salto ObjExp 75→90% en la tabla de combustible genera un escalón HRR 582→1288 kW a t≈135 s (muy brusco); la interfaz baja a HL=0.83 m en un solo step, mientras el paper muestra descenso gradual hasta t≈186 s
- **Por qué `thermal_gradient_min_band_m` no ayuda**: con `hot_depth=1.62 m × band_fraction=0.35`, el `ref_depth=0.567 m` ya supera cualquier `min_band` razonable — el floor nunca se activa
- **Fix necesario**: suavizar la curva de combustible del colchón Ghanekar para que la transición 75→90% sea gradual (~20-30 s), logrando que el descenso de HL sea progresivo y alcance HL ≈ 0.75 m entre t=156-216 s
- **Bloqueo**: requiere modificar la tabla de combustible del caso específico (JSON) o añadir interpolación en el motor de progresión de objetos

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

#### GAP-7: `cfast_hall_upper_o2_doorway_pending`
- **Qué mide**: depleción de O₂ en zona SUPERIOR del pasillo — gas caliente pobre en O₂ entra por mitad alta del vano de puerta
- **Situación actual**: SF transfiere gas mezclado por doorway → O₂ pasillo ≈ 20% vs CFAST upper-zone ≈ 5-11%
- **Fix necesario**: two-zone doorway flow separando flujo caliente (mitad alta) de flujo frío (mitad baja). Phase 2A. Parcialmente implementado en Phase 2H pero solo para HVAC.

#### GAP-8: `cfast_hrr_ventilation_limited_f2_pending`
- **Qué mide**: limitación de HRR por O₂ de zona superior (fuego usa solo zona caliente, no mezcla uniforme)
- **Situación actual**: SF usa O₂ promedio de sala → fuego continúa con O₂ promedio >umbral aunque O₂_upper < umbral de extinción
- **Fix necesario**: alimentar `o2_upper` al modelo de combustión como O₂ efectivo en zona de reacción. Phase 2.

#### GAP-9: `cfast_hvac_two_zone_feed_pending`
- **Qué mide**: alimentación de O₂ de zona inferior por HVAC — mantiene fuego vivo en CFAST mientras SF extingue
- **Situación actual**: Phase 2H opt-in existe pero default OFF; con default ON el fuego en SF también sobrevive
- **Fix necesario**: habilitar Phase 2H como default, validar que el test set completo sigue PASS, y remover el gap. Requiere rebaseline selectivo.

---

## 3. Clasificación de gaps por bloqueo técnico

```
┌─────────────────────────────────────────────────────────────────────┐
│  NIVEL 1 — Calibración de datos de caso (esfuerzo BAJO)             │
│  GAP-1: suavizar curva combustible colchón Ghanekar                 │
│         → modificar JSON del caso o tabla de combustible             │
└─────────────────────────────────────────────────────────────────────┘
         ↓ no resuelve → depende del motor de progresión de objetos

┌─────────────────────────────────────────────────────────────────────┐
│  NIVEL 2 — Extensión del motor de combustión (esfuerzo MEDIO)       │
│  GAP-2,3,4: yield CO vent-limited (usa o2_upper → CombustionSystem) │
│  GAP-8: o2_upper como input efectivo a HRR cap                      │
│         → ~2 archivos (CombustionSystem.gd, SimulationEngine.gd)    │
│         → requiere rebaseline de checks de combustión               │
└─────────────────────────────────────────────────────────────────────┘
         ↓ desbloquea

┌─────────────────────────────────────────────────────────────────────┐
│  NIVEL 3 — Two-zone doorway flow (esfuerzo ALTO)                    │
│  GAP-7: hot-gas doorway upper/lower routing                          │
│         → Phase 2A: GasExchangeSystem.gd + OxygenExchangeSystem.gd  │
│         → requiere rebaseline masivo (transport coupling)            │
│  GAP-6: CO₂ stratification                                          │
│         → extiende GAP-7 a CO₂ tracking bidireccional               │
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

### FASE 1.7 — Suavizado curva combustible Ghanekar (GAP-1)
**Objetivo**: cerrar `ghanekar_flashover_0_9m_known_gap`  
**Prerequisito**: ninguno  
**Esfuerzo estimado**: 1-2 sesiones

**Descripción técnica**:
1. Localizar la tabla de progresión del objeto `ghanekar_bed_mattress` en los assets del caso
2. Identificar el marcador de transición ObjExp 75% → 90% que genera el salto HRR 582→1288 kW a t≈135 s
3. Añadir marcador intermedio ObjExp=82% a t≈155 s para distribuir el escalón en ≥20 s
4. Verificar que la interfaz HL desciende gradualmente de HL=1.36 m a HL≤0.75 m entre t=140-210 s
5. Verificar que T@0.9m cruza 600°C entre t=156-216 s (ventana aceptación)
6. Confirmar que `ghanekar_origin_peak_upper_temp_reasonable_c` (T_upper ∈ [450,650]°C) sigue PASS
7. Si PASS: promover el check a `required=true` y eliminar el `note: Known gap`

**Criterio de cierre**:
- `time_room_0_temp_0_9m_above_600c_s` en JSON = valor ∈ [156, 216] s
- 373/373 required PASS (promovería 1 gap sobre la base actual 372/372)

**Riesgo**: suavizar el escalón puede reducir T_upper pico. Margen actual: 608°C vs límite 650°C (42°C de margen). Si T_upper baja de 608°C a ~570°C sigue dentro del rango.

---

### FASE 2 — CO vent-limited via o2_upper (GAP-2, 3, 4) — ✅ COMPLETADA (2026-05-28)
**Objetivo original**: cerrar los 3 gaps del caso `ghanekar_kitchen` y el gap HRR vent-limited CFAST  
**Logrado**: GAP-2 (fed_1_0: 743.6s), GAP-3 (idlh_co: 684.4s), GAP-4 (flashover: 873.75s) — todos required=True  
**Pendiente de Phase 2**: GAP-8 (`cfast_hrr_ventilation_limited_f2_pending`) requiere implementar el cap de HRR por `o2_upper` en CombustionSystem; la calibración de CO yield (multiplier=110) no cubre este gap CFAST.  
**Parámetros calibrados**: `fire_co_vent_limited_multiplier=110`, `fed_upper_layer_threshold_m=2.0`, `doorway_heat_exchange_coeff=0.30`  
**Commits**: `c67802b` (calibración) + `156fb81` (CO vent-limited combustion phase)

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

**Criterio pendiente para GAP-8**:
- `cfast_hrr_ventilation_limited_f2_pending` eliminado tras implementar HRR cap por `o2_upper`
- Required PASS actualizado sin aumentar tolerancias del check legacy `cfast_t240_hrr_ventilation_limited`

**Riesgo**: el multiplicador de CO afecta FED en casos existentes. Revisar especialmente `ghanekar_bedroom_hallway` (fuego también en zona parcialmente vent-limited). Usar override por caso si hay regresión.

---

### FASE 2A — Two-zone doorway flow (GAP-7)
**Objetivo**: cerrar `cfast_hall_upper_o2_doorway_pending`  
**Prerequisito**: Phase 2 (o2_upper estable en combustión)  
**Esfuerzo estimado**: 4-6 sesiones

**Descripción técnica**:
- En `GasExchangeSystem.gd`, dividir el flujo de masa por doorway en dos zonas:
  - Flujo caliente (mitad superior del vano, `h > sill + height/2`): lleva gas de zona superior de sala fuente
  - Flujo frío (mitad inferior del vano): lleva gas de zona inferior
- En `OxygenExchangeSystem.gd`, enrutar O₂ del flujo frío a `o2_lower` de sala receptora
- Requiere refactorizar `_transfer_hot_gas_contaminants` (13+ sitios de escritura de `upper_gas_kg`)

**Arquitectura recomendada**: rama separada del flujo Bernoulli actual; el flujo fijo existente permanece activo y el two-zone es aditivo condicionado a flag `vent_doorway_two_zone_enabled`

**Criterio de cierre**:
- `cfast_hall_upper_o2_doorway_pending`: O₂ upper pasillo ∈ [0.05, 0.15] a t=480/600 s
- Todos los checks required existentes PASS (sin regresión)

**Riesgo**: ALTO. El transporte two-zone afecta directamente FED timing, CO_upper, CO₂_upper — variables con >50 checks required. Requiere rebaseline selectivo. Usar rama Git separada.

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

**Criterio de cierre**:
- `cfast_hvac_two_zone_feed_pending`: fuego activo en HVAC case, T_upper HVAC ≥ umbral relevante
- 367+N/367+N PASS tras rebaseline

---

### FASE 3 — Modelo de presión termodinámica (GAP-5)
**Objetivo**: cerrar `cfast_overpressure_sealed_pending`  
**Prerequisito**: INDEPENDIENTE (no necesita Phase 2A), pero altamente disruptivo  
**Esfuerzo estimado**: 6-10 sesiones

**Descripción técnica**:
- Implementar ODE de presión por zona basado en ley de gases ideales: `dP/dt = (γ-1)/V × (Q_fire - Q_loss - P × dV/dt)`
- Requiere volúmenes separados por zona upper/lower
- Pérdidas de presión por aberturas (flow resistances Bernoulli inverso)
- **ADVERTENCIA**: este cambio invalida los 17 checks de presión actualmente PASS (cerrados con tolerancias `|diff|+2 Pa`). Necesitarán rebaseline con nuevos valores.
- Usar rama Git separada y rebaseline completo antes de merge

**Criterio de cierre**:
- `cfast_overpressure_sealed_pending`: presión sala sellada t=120 s ∈ [900, 1100] Pa
- Los 17 checks de presión (actualmente PASS con tol amplia) deben seguir PASS con nueva física

---

## 5. Roadmap y priorización

```
2026-05 (COMPLETADO)
    Phase 1.5 ✅  — entrainment temperature fix (a723e8d)
    Phase 1.6 ✅  — Bernoulli doorway_heat_exchange_coeff fix (efcf5fd)
  Stage-B ✅    — 5 casos CFAST implementados (320 required checks)
  Hardening ✅  — Stage C/D/E/F (367 required checks)
  Phase 2 ✅    — Ghanekar kitchen promoted to required (372 required checks)

2026-06 (PRÓXIMO)
┌──────────────────────────────────────────────────────────────┐
│  SPRINT 1 (1-2 sesiones)                                     │
│  Phase 1.7 — Suavizar curva combustible Ghanekar             │
│  Objetivo: GAP-1 → required                                  │
│  Riesgo: BAJO (solo JSON del caso + tabla combustible)       │
└──────────────────────────────────────────────────────────────┘
         ↓ independiente
┌──────────────────────────────────────────────────────────────┐
│  SPRINT 2 (2-4 sesiones)                                     │
│  Phase 2 cont. — HRR cap por o2_upper en CombustionSystem   │
│  Objetivo: GAP-8 → required                                  │
│  (GAP-2, 3, 4 ya cerrados en 2026-05-28 ✅)                 │
│  Riesgo: MEDIO (combustión core, rebaseline por caso)        │
└──────────────────────────────────────────────────────────────┘
         ↓ desbloquea
┌──────────────────────────────────────────────────────────────┐
│  SPRINT 3 (4-6 sesiones) — Two-zone doorway                 │
│  Phase 2A — GAP-7                                            │
│  Phase 2B — GAP-6 (CO₂ stratification)                      │
│  Phase 2C — GAP-9 (Phase 2H default ON)                     │
│  Riesgo: ALTO (rama Git separada, rebaseline masivo)         │
└──────────────────────────────────────────────────────────────┘
         ↓ desbloquea (opcional, largo plazo)
┌──────────────────────────────────────────────────────────────┐
│  SPRINT 4 (6-10 sesiones) — Presión termodinámica           │
│  Phase 3 — GAP-5                                             │
│  Riesgo: MUY ALTO (invalida 17 checks de presión)            │
└──────────────────────────────────────────────────────────────┘
```

### Tabla de prioridades

| Prioridad | Fase | Gaps cierra | Riesgo | Esfuerzo | Prerequisito |
|-----------|------|-------------|--------|----------|--------------|
| 1 | Phase 1.7 | 1 (GAP-1) | Bajo | 1-2 sesiones | Ninguno |
| 2 | Phase 2 cont. | 1 (GAP-8) | Medio | 2-4 sesiones | Ninguno |
| 3 | Phase 2A | 1 (GAP-7) | Alto | 4-6 sesiones | Phase 2 |
| 4 | Phase 2B | 1 (GAP-6) | Medio | 2-3 sesiones | Phase 2A |
| 5 | Phase 2C | 1 (GAP-9) | Medio | 1-2 sesiones | Phase 2A |
| 6 | Phase 3 | 1 (GAP-5) | Muy alto | 6-10 sesiones | Phase 2A |

---

## 6. Invariantes de calidad (no deben romperse nunca)

| Invariante | Cómo verificar |
|-----------|----------------|
| 372/372 required PASS (mín actual) | `python scripts/simulation/validate_reference_cases.py` |
| Conteo de gaps documentado == conteo en JSON | `python scripts/simulation/validation_guardrails.py` |
| 13/13 unit tests | `python tests/test_guardrails.py` |
| 7 sentinels Phase 2E PASS | Incluido en guardrails |
| `doorway_heat_exchange_coeff` aplicado a Bernoulli | `efcf5fd` — regresión detectada por `ghanekar_origin_peak_upper_temp_reasonable_c` |
| `o2_upper` tracking activo | Regresión detectada por checks `o2_upper` en casos CFAST |

---

## 7. Riesgos transversales

| Riesgo | Impacto | Mitigación |
|--------|---------|-----------|
| Cambio de CO yield rompe FED timing en casos existentes | Alto | Override por caso; no cambiar defaults globales sin rebaseline |
| Two-zone doorway cambia masa transportada → T_upper regresar | Alto | Rama Git separada; validar invariantes antes de merge |
| Suavizar curva combustible Ghanekar baja T_upper pico | Bajo | Margen 42°C disponible (608°C actual, límite 650°C) |
| Phase 2H default ON altera O₂ lower en casos sin HVAC | Medio | Guard `outside_open_factor > 0.01` ya implementado |
| Phase 3 presión invalida tolerancias actuales | Muy alto | Hacer Phase 3 en rama separada; rebaseline completo antes de merge |

---

## 8. Estado del working tree documentado (2026-05-30)

```
HEAD base: 156fb81 (main = origin/main)

Estado tras esta actualización documental: cambios pendientes en docs, guardrails y reference_checks; validar y commitear antes de considerar la sesión cerrada.
```

### Changelog de sesión (2026-05-30)
| Commit | Descripción |
|--------|-------------|
| `efcf5fd` | Phase 1.6: apply doorway_heat_exchange_coeff to Bernoulli flow path |
| `b84e399` | docs: update GAPS_INVENTORY for Phase 1.6 |
| `c67802b` | phase-2: CO vent-limited via o2_upper (closes GAP-2,3,4; GAP-8 remains pending) |
| `156fb81` | Add CO vent-limited phase to combustion model |

### Investigación realizada (sin commit — resultados negativos documentados)
- **Experimento `thermal_gradient_min_band_m=0.10`**: no efectivo para GAP-1. `ref_depth=0.567 m` ya supera el min_band → floor nunca activo. Revertido.
- **Análisis timing GAP-1**: el salto ObjExp 75→90% genera escalón HRR a t≈135 s (fuera de ventana 156-216 s). La causa dual (gradiente + timing) confirma que Phase 1.7 necesita suavizar la tabla de combustible, no el modelo de gradiente.
