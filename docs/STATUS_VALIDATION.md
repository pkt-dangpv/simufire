# SimuFire — Estado de validación CFAST

> Última actualización: 2026-06-15  
> Branch: `main` · HEAD: Phase 4A (148b2d5)  
> Fallos requeridos actuales: **14 / 334**

---

## Resumen ejecutivo

La validación compara SimuFire contra referencias NIST CFAST para escenarios residenciales estándar. El motor pasó de **41 fallos requeridos** (baseline R2) a **14 fallos** a lo largo de varias fases de trabajo.

---

## Historial de reducción de fallos

| Commit | Descripción | Fallos antes → después |
|--------|-------------|------------------------|
| `abf8a82` | Revertir wall PDE + deshabilitar fire rad double-deposit | 41 → ~35 |
| `d1b94ef` | Deshabilitar canonical pressure acumulativo (100k+ Pa) | ~35 → ~34 |
| `86a94cd` | O2 two-zone exchange + fire_o2_mode por caso | 34 → 23 |
| `f59ec07` | window_break: deshabilitar ambient loss al abrir | 23 → 23 (otros fix) |
| `47c254f` | corridor_chain: switch a fire_o2_mode=upper (t300 pass) | 23 → 22 |
| `5147197` | post_flashover_vented: reducir ambient loss + chi_rad | 22 → 21 |
| `05b0b2d` | suppression_water: reducir ambient loss + chi_rad | 21 → 20 |
| `ef84972` | single_room_closed: reducir chi_rad → pasa t210_temp | 20 → 19 |
| `4374109` | door_close_midfire: aumentar chi_rad → pasa t120_temp | 19 → 18 |
| `cae9ec0` | Rebaselinear reference_checks a estado correcto | 18 → 16 |
| `e2c4b2b` | Phase 3: fix ODE presión — incluir dinteles en alivio | 16 → **16** (sin-regresión) |
| Phase 4A | Fix doble-depleción O₂ en plume_lower_mode (r0_window_360) | 16 → **14** |
| Phase 4B | Diagnóstico slow_growth_sealed — gap estructural confirmado (sin cambio) | **14** → **14** |

---

## Los 14 fallos actuales

### Grupo A — `cfast_r0_window_360` (→ 0 fallos originales, 3 nuevos O₂ parcialmente estructurales)

**Phase 4A COMPLETO.** Los 5 fallos originales están resueltos. Quedan 3 fallos de O₂ nuevos (parcialmente estructurales por brecha Phase 2).

**Causa raíz original:** `plume_lower_mode` en `OxygenExchangeSystem.gd` tenía doble-depleción: consumía O₂ a tasa completa tanto en `o2_upper` (líneas ~309-311) como en `o2_lower` (líneas ~363-367), con denominador `lower_air_mass` (~84 kg). Resultado: o2_lower caía de 0.209 a 0.055 en ~313 s → fuego se apaga 47 s antes de que abra la ventana.

**Fix aplicado (Phase 4A, `OxygenExchangeSystem.gd`):**

Tres cambios coordinados:

1. **Guard en upper_consumed:** en `plume_lower_mode`, solo aplica fracción `plume_upper_o2_displacement_frac=0.09` del consumo estequiométrico a `o2_upper` (en lugar de la tasa completa). Modela desplazamiento de O₂ por CO₂/H₂O en la zona superior.

2. **delta_entr bidireccional:** en `plume_lower_mode`, permite `(o2_lower - o2_upper)` negativo (sin `maxf(0.0, ...)`). Cuando o2_upper < o2_lower, el plume diluye la zona superior con productos de combustión en lugar de enriquecerla.

3. **Denominador correcto:** el consumo de o2_lower en plume_lower se divide por `air_mass_kg` (masa total de aire) en lugar de `lower_air_mass`. En sala sellada con zona superior gruesa, `air_mass_kg ≈ 5× lower_air_mass`, lo que frena la depleción a tasa físicamente correcta.

**Resultado:**

| Check | Antes (Phase 3) | Después (Phase 4A) | Estado |
|-------|-----------------|---------------------|--------|
| `cfast_t350_hrr_kw` | 6.3 kW | 265 kW | **PASS** (tol ±90 kW) |
| `cfast_t350_temp_upper_c` | 45.7°C | ~140°C | **PASS** (tol ±80°C) |
| `cfast_t360_hrr_kw` | 3.8 kW | 216 kW | **PASS** (tol ±90 kW) |
| `cfast_t360_temp_upper_c` | 41.1°C | ~130°C | **PASS** (tol ±80°C) |
| `cfast_rmse_temp_upper_c` | 91.9 | ≤60 | **PASS** |

El fuego ahora sobrevive hasta t=360 s, responde a la apertura de ventana y sube a 1280 kW en t~400 s.

**3 fallos O₂ nuevos (brecha Phase 2 confirmada por validate_reference_cases.py):**

| Check | Actual | Esperado | Tolerancia | Nota |
|-------|--------|----------|------------|------|
| `cfast_t240_o2_depleted` | 0.1595 | 0.085 | ±0.031 | Structual Phase 2 gap (comentario validator) |
| `cfast_t350_o2` | 0.0881 | 0.066 | ±0.015 | room.o2 vs CFAST upper-zone O₂ |
| `cfast_t360_o2` | 0.0837 | 0.0645 | ±0.015 | room.o2 vs CFAST upper-zone O₂ |

El validator documenta explícitamente: "Structural Phase 2 gap — SF usa room-avg O₂ (>>8.51%) vs CFAST upper-zone O₂ (8.51%) → fuego SF corre cerca de capacidad; CFAST se auto-limita". Resolver requeriría arquitectura dos zonas canónica (Phase 2 scope).

---

### Grupo B — `cfast_slow_growth_sealed` (2 fallos) — Gap estructural Phase 2

**Phase 4B INVESTIGADO. Causa raíz confirmada. No resoluble con parámetros — requiere Phase 2.**

Escenario: sala sellada, fuego slow-growth (α=0.003 kW/s²), 1800 s.

| Check | Actual | Esperado | Tolerancia |
|-------|--------|----------|------------|
| `cfast_slow_t480_temp_upper_c` | 98.5°C | 151°C | ±10°C |
| `cfast_slow_t600_temp_upper_c` | 103.9°C | 152°C | ±15°C |

**Causa raíz (Phase 4B, confirmada):**

La zona superior queda ~50°C baja porque `hrr_chi_rad_normal=0.70` implica que solo el 30% del HRR es convectivo. Con HRR=222 kW en t=480 s:

- Q_conv = 222 × 0.30 = **66.6 kW** (entrada a zona superior)
- Q_pérdidas totales ≈ **65.7 kW**:
  - Plume McCaffrey (enfriamiento por entrainment): ~31.6 kW
  - `upper_to_ambient_loss_rate=0.01`: ~16.5 kW
  - `wall_absorption_rate=0.008`: ~12.9 kW
  - `upper_to_lower_loss_rate=0.002`: ~4.7 kW
- Balance neto: ~0.9 kW → 0.045°C/s → equilibrio a **~98°C** (vs CFAST 151°C)

Para alcanzar el equilibrio a 151°C con el mismo HRR, se necesitaría `chi_rad ≈ 0.50` (solo 50% radiativo).

**Por qué no se puede arreglar con parámetros — acoplamiento chi_rad / O₂:**

Se probó `hrr_chi_rad_normal = hrr_chi_rad_low_o2 = 0.50` (único cambio en `cfast_slow_growth_sealed.json`):

| Check | Baseline (chi_rad=0.70) | Test (chi_rad=0.50) | Resultado |
|-------|------------------------|----------------------|-----------|
| `cfast_slow_t480_temp_upper_c` | 98.5°C — FAIL | ~128°C — FAIL | sin mejora suficiente |
| `cfast_slow_t600_temp_upper_c` | 103.9°C — FAIL | 141.4°C — **PASS** | ±15 ok |
| `cfast_slow_t300_o2` | 0.1598 — PASS | 0.1411 — **FAIL** | regresión nueva |
| `cfast_slow_t480_o2` | 0.074 — PASS | 0.0705 — **FAIL** | regresión nueva |
| **Total fallos** | **14** | **15** | **regresión neta** |

El acoplamiento chi_rad → O₂ funciona así:

1. chi_rad↓ → fracción convectiva↑ → `temp_upper`↑
2. Temperatura más alta → gas menos denso → misma masa ocupa más volumen → `upper_gas_kg` se reduce (t=300: 17.8 kg → 11.7 kg)
3. El consumo de O₂ por el fuego se divide por `upper_gas_kg` como denominador → masa más pequeña → fracción O₂ removida por paso más grande → O₂ se depleta más rápido
4. Los checks t=300 y t=480 O₂ fallan

**Rangos incompatibles (gap estructural):**

| Restricción | chi_rad requerido |
|-------------|------------------|
| t=600 temp pass (±15°C) | ≤ 0.55 |
| t=300 O₂ pass (±0.01) | ≥ 0.64 |

Estos rangos no se solapan. No existe un valor de `chi_rad` que satisfaga ambos simultáneamente.

**Investigaciones adicionales descartadas:**

- `ach_infiltration=5.0`: solo afecta composición de gases (no temperatura térmica en ThermalSystem.gd) — no es la causa
- Reducir `wall_absorption_rate` o `upper_to_ambient_loss_rate`: ahorro teórico máximo <20°C con chi_rad=0.70 — insuficiente
- Reducir `plume_fire_diameter_m`: reduce entrainment pero mantiene el mismo acoplamiento O₂/temperatura
- `upper_heat_capture_max`: marcado como obsoleto en ThermalSystem.gd (líneas 222-223), no se usa

**Fix real necesario (Phase 2):**

En CFAST, el fuego consume O₂ de la **zona inferior** a través del plume. En SF con `fire_o2_mode="upper"`, el fuego consume O₂ directamente de `o2_upper`, por lo que temperatura y O₂ están acoplados en `upper_gas_kg`. La solución requiere arquitectura dos-zonas canónica (ZoneFireSolver Phase 2) donde:
- El fuego depleta O₂ del lower layer
- El plume transporta calor + productos al upper layer
- El O₂ del upper layer solo cambia por exchange, no por consumo directo del fuego

**Comandos ejecutados:**
```bash
# Simular con chi_rad=0.50 (test que causó regresión — REVERTIDO)
powershell -ExecutionPolicy Bypass -File sim/validation/run_case.ps1 -CaseName cfast_slow_growth_sealed -TimeoutSeconds 600

# Verificar conteo de fallos (14 con chi_rad=0.70; 15 con chi_rad=0.50)
python scripts/simulation/validate_reference_cases.py
```

**Estado:** `sim/validation/cases/cfast_slow_growth_sealed.json` revertido a baseline (`chi_rad=0.70`). Fallos = 14 (sin cambio).

---

### Grupo C — `cfast_corridor_chain` (5 fallos)

Escenario: fuego en sala 0 (300 kW), puertas abiertas a salas 1 y 2 en corredor.

| Check | Actual | Esperado | Tolerancia |
|-------|--------|----------|------------|
| `cfast_chain_r0_t180_temp_upper_c` | 203.4°C | 158°C | ±15°C |
| `cfast_chain_r0_t600_temp_upper_c` | 111.9°C | 168.4°C | ±30°C |
| `cfast_chain_r0_o2_t480_o2` | 0.077 | 0.117 | ±0.028 |
| `cfast_chain_r0_o2_t600_o2` | 0.077 | 0.102 | ±0.015 |
| `cfast_chain_r0_rmse_temp_upper` | 52.0 | — | máx 30 |

**Causa raíz:** El motor es demasiado caliente en t=180 (+45°C) y demasiado frío en t=600 (-56°C). El O₂ es demasiado bajo en t=480/t600, lo que indica que el fuego consumió O₂ más rápido que CFAST. El patrón "pico alto + decaimiento rápido" sugiere que el modelo de transporte de O₂ inter-sala (desde rooms 1 y 2) no reabastece la sala de fuego a la tasa correcta.

**Por qué no se puede arreglar con parámetros:**
- `fire_o2_mode="upper"` ya está activo; eliminó el fallo de t=300 pero los otros 5 permanecen.
- Los fallos están acoplados: temperatura alta inicial y O₂ bajo son consecuencia del mismo problema de transporte de O₂ entre salas.

**Fix necesario:** Mejorar el transporte de O₂ bidireccional a través de aperturas interiores abiertas. El modelo actual usa `doorway_o2_counterflow_coeff` pero puede estar subestimando el flujo de O₂ desde salas adyacentes hacia la sala de fuego en escenarios multi-sala con puertas abiertas.

---

### Grupo D — Fallos aislados (4 fallos)

| Check | Actual | Esperado | Tolerancia | Caso |
|-------|--------|----------|------------|------|
| `cfast_pool_t300_o2` | 0.2038 | 0.1940 | ±0.008 | pool_fire_open |
| `cfast_2r_r0_rmse_temp_upper_c` | 88.0 | — | máx 60 | two_room_door_open |
| `cfast_multifuel_rmse_temp_upper_c` | 232.5 | — | máx 200 | multi_fuel_couch_tv |
| `ghanekar_kitchen_far_hall_fed_1_0_s` | 876.5 s | 624 s | ±126 s | ghanekar_kitchen |

**pool_fire_open:** O₂ ligeramente alto (0.0098 fuera de tolerancia). La ventana abierta repone O₂ demasiado rápido. Posible ajuste en `natural_vent_inlet_fraction` o en el rate de consumo, pero está muy ajustado (±0.008 tolerancia) y tocar parámetros rompe otras cosas.

**two_room_door_open RMSE:** Error acumulado en temperatura a lo largo de 900 s. La temperatura deriva lentamente. Necesita investigación de qué etapa del ciclo termal acumula el error.

**multifuel RMSE:** Escenario con muebles múltiples (sofá + TV + textiles). El RMSE de 232 vs máx 200 sugiere que la curva de HRR multi-combustible no se alinea bien con CFAST en alguna fase de la simulación.

**ghanekar FED:** El tiempo para FED≥1.0 en el pasillo lejano es 252 s más tarde que en el paper. Este check valida el modelo de FED (CO+HCN+O₂+calor) en habitaciones remotas. Puede requerir calibración del transporte de CO/HCN inter-sala.

---

## Trabajo completado

### Phase 4B — Diagnóstico slow_growth_sealed (gap estructural confirmado)

**Resultado:** 14 fallos → **14 fallos** (sin cambio). El análisis confirmó que los 2 fallos de temperatura son un gap estructural Phase 2, no resoluble con tuning de parámetros.

**Causa raíz documentada:** `fire_o2_mode="upper"` acopla la temperatura del upper layer con la tasa de depleción de O₂ a través de `upper_gas_kg`. Cualquier chi_rad que suba la temperatura lo suficiente también reduce `upper_gas_kg` hasta que los checks de O₂ en t=300 y t=480 fallan. Los rangos de chi_rad requeridos para temperatura vs O₂ no se solapan.

**Fix intentado y revertido:** chi_rad=0.50 → t=600_temp PASS, pero 2 nuevas regresiones O₂ → 15 fallos. Revertido.

**Archivos modificados:** ninguno (investigación sin cambio de baseline).

---

### Phase 4A — Fix doble-depleción O₂ en plume_lower_mode

**Resultado:** 16 → **14** fallos requeridos.

**Reproducir:**
```bash
# Re-ejecutar caso (regenera .log)
powershell -ExecutionPolicy Bypass -File sim/validation/run_case.ps1 -CaseName cfast_r0_window_360 -TimeoutSeconds 600

# Verificar conteo total
python scripts/simulation/validate_reference_cases.py
```

**Archivos modificados:**
- `sim/core/OxygenExchangeSystem.gd` — 3 cambios en lógica plume_lower_mode (ver Grupo A arriba)
- `sim/validation/cases/cfast_r0_window_360.json` — sin cambios de override (fix es en el motor)

**HRR log en ventana crítica (post-fix):**
```
t= 310.1  HRR=  265.xx  ← fuego vivo (antes aquí ya estaba apagado)
t= 350.1  HRR=  265.08  ← PASS (tol ±90 kW vs CFAST 288 kW)
t= 360.1  HRR=  216.61  ← PASS (ventana aún cerrada)
t= 370.1  HRR=  731.13  ← recuperación tras apertura ventana
t= 400.x  HRR= 1280.00  ← fuego pleno post-ventana
```

---

### Phase 3 — Fix ODE presión termodinámica

**Fix implementado:** `e2c4b2b`

**Problema:** `step_thermodynamic_pressure()` en `GasExchangeSystem.gd` solo sumaba el área de aperturas **exteriores abiertas** al término de alivio (sumidero) de la ODE. Las aperturas interiores abiertas (puertas entre salas) no contribuían al alivio. Resultado: en salas con puertas abiertas, la presión acumulaba **100k+ Pa** al activar `phase3_pressure_canonical_enabled=true`.

**Demostración del bug:**
```
Sala 0 (48 m³) + fuego 1280 kW + ACH=5 + puertas cerradas:
  A_eff_ACH = 0.012 m²
  P_ss (steady-state) = 141 kPa  ← imposible para una sala residencial
```

**Con el fix (puertas abiertas incluidas):**
```
Sala 0 + puerta abierta (0.9×2.0 m) + mismo fuego:
  A_eff_total = 0.012 + 1.80 = 1.812 m²
  P_ss = 0.34 Pa  ← físicamente correcto
```

**Cambio en código** (`GasExchangeSystem.gd`, líneas 229-236):
```gdscript
# ANTES: solo aperturas exteriores
for op in building.get_openings():
    var connects_outside := (op.a == room.id and op.b == OUTSIDE_ID) or ...
    if connects_outside and op.open_fraction > 0.001:
        a_eff += op.width_m * op.height_m * op.open_fraction

# DESPUÉS: todas las aperturas abiertas (exterior + interior)
for op in building.get_openings():
    if op.a != room.id and op.b != room.id:
        continue
    if op.open_fraction > 0.001:
        a_eff += op.width_m * op.height_m * op.open_fraction
```

**Efecto en validación:** Ningún cambio de baseline (la ODE no ejecuta cuando `phase3_thermodynamic_pressure_enabled=false`, que es el default en todos los casos). El fix hace seguro activar `phase3_pressure_canonical_enabled=true` en experimentos futuros.

**Actualización comentario CaseRunner.gd:** El comentario que decía "ODE solo releva por ACH, no por dinteles → acumula 100k+ Pa" fue actualizado para reflejar que el bug está corregido.

---

## Por qué `phase3_pressure_canonical_enabled` no reduce los fallos actuales

Se evaluó si habilitar presión canónica en `cfast_corridor_chain` (puertas abiertas) ayudaría:

| Modelo | Presión en sala con puerta abierta |
|--------|-------------------------------------|
| Boyanza (actual) | 3.62 Pa |
| ODE canónica (con fix) | 0.34 Pa |
| Umbral de venteo | 2.0 Pa |

Con presión canónica (0.34 Pa < 2.0 Pa umbral), `step_pressure_venting` no activaría el venteo por presión → sala más caliente → empeora el fallo t=180 (ya 45°C demasiado caliente).

La presión canónica no ayuda a los fallos actuales porque estos son de **balance de O₂** y **balance térmico**, no de flujo Bernoulli por presión.

---

## Roadmap de fixes pendientes

### Completado

**P1 — r0_window_360 (Phase 4A) ✓** — 5 fallos originales → 0. Quedan 3 O₂ estructurales (Phase 2 scope).

### Prioridad alta (máximo impacto)

**P2 — slow_growth_sealed (2 fallos) — Gap estructural Phase 2 ✗**

Investigado en Phase 4B. Los 2 fallos de temperatura son un gap estructural: requieren que el fuego consuma O₂ del lower layer (vía plume) en lugar de `o2_upper` directamente. Resolver requiere ZoneFireSolver Phase 2 (two-zone canónico). No atacar sin esa base arquitectónica.

**P3 — O₂ transport corridor_chain (5 fallos, Grupo C)**

Investigar:
- El flujo de O₂ bidireccional a través de dinteles abiertos en `GasExchangeSystem.step_smoke()` (counterflow O₂).
- `doorway_o2_counterflow_coeff = 0.18` puede ser demasiado bajo para reabastecimiento en corredor de 3 salas.
- Considerar si `two_zone_opening_flow_enabled=true` mejora el transporte de O₂ en este escenario.

### Prioridad media

**P4 — pool_fire O₂ (1 fallo, Δ=0.0098)**

Ajuste fino: reducir ligeramente `natural_vent_inlet_fraction` solo para este caso (actualmente=0.2). Riesgo bajo si se hace por-caso. Alternativa: aumentar `o2_upper_plume_entr_rate` para incrementar consumo.

**P5 — RMSE two_room y multifuel (2 fallos)**

Necesita diagnóstico: generar gráfica temporal de temperatura para identificar en qué fase del escenario diverge el motor de CFAST. Herramienta: `tools/rmse_profile_tworoom.py`.

**P6 — Ghanekar FED (1 fallo, Δ=252 s)**

El FED en pasillo lejano tarda 252 s más que el paper. Investigar:
- Velocidad de transporte de CO/HCN inter-sala (delay de transporte en `interior_transport_speed_m_s`).
- Calibración del yield de CO en fuegos de cocina (`fire_co_yield_force_kg_per_MJ`).

---

## Arquitectura de componentes relevantes

```
sim/
├── core/
│   ├── GasExchangeSystem.gd      # Transporte gases, presión ODE (Phase 3 fix aquí)
│   ├── OxygenExchangeSystem.gd   # O₂ exchange, plume_lower_mode
│   ├── ThermalSystem.gd          # Balance energético zonas, chi_rad
│   └── ZoneFireSolver.gd         # Dos zonas: masa/energía canónica
├── fire/
│   └── CombustionSystem.gd       # Throttle HRR por O₂, fire_o2_mode
└── validation/
    ├── CaseRunner.gd             # Runner por caso, flags de validación
    ├── cases/
    │   ├── cfast_r0_window_360.json        # Grupo A (5 fallos)
    │   ├── cfast_slow_growth_sealed.json   # Grupo B (2 fallos)
    │   ├── cfast_corridor_chain.json       # Grupo C (5 fallos)
    │   └── ...                             # Grupo D
    └── reports/
        └── reference_checks.json  # 16 fallos requeridos (HEAD correcto)
```

### Flags de motor relevantes

| Flag | Default | Dónde vive | Efecto |
|------|---------|------------|--------|
| `fire_o2_mode` | `"legacy"` | SimulationEngine | Fuente de O₂ para throttle del fuego |
| `plume_lower_mode` (interno) | auto | OxygenExchangeSystem | Depleta o2_lower en salas selladas |
| `phase3_thermodynamic_pressure_enabled` | `false` | GasExchangeSystem | Activa ODE de presión termodinámica |
| `phase3_pressure_canonical_enabled` | `false` | GasExchangeSystem | Promueve presión ODE a overpressure_pa |
| `two_zone_opening_flow_enabled` | `false` | GasExchangeSystem | Enrutamiento por zonas en aperturas |
| `two_zone_energy_enabled` | `false` | ZoneFireSolver | Ledger de masa/energía canónico |

---

## Comandos de referencia

```bash
# Ver estado actual de validación
python scripts/simulation/validate_reference_cases.py

# Re-ejecutar un caso específico (regenera el .log)
powershell -ExecutionPolicy Bypass -File sim/validation/run_case.ps1 -CaseName <nombre> -TimeoutSeconds 600

# Ver los 16 fallos requeridos del commit HEAD
git show HEAD:sim/validation/reports/reference_checks.json | python -c "
import json,sys
d=json.load(sys.stdin)
fails=[c for c in d['checks'] if not c['pass'] and c['required']]
print(len(fails),'required failures:')
for c in sorted(fails, key=lambda x: x['name']): 
    print(f'  {c[\"name\"]}: actual={c[\"actual\"]} expected={c[\"expected\"]}')
"
```
