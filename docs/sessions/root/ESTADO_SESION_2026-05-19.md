# Estado de Sesión — 2026-05-19

## Resultado de la sesión
⚠️ Suite de referencia CFAST/Ghanekar: **47/72 PASS** (peor que antes del fix O₂ init/clamp — ver análisis abajo)  
Suite regresión completa: **43/43 PASS** — confirmada tras fix O₂ double-transport  
Estado: análisis de causas raíz en curso — próximos pasos definidos

---

## Lo hecho hoy (2026-05-19) — continuación de sesión

### 1. victim_fed_incapacitation — Caso CI #43
- Creado `sim/validation/cases/victim_fed_incapacitation.json`
- Creado `sim/validation/baselines/victim_fed_incapacitation.json`
- `run_all_cases.ps1` actualizado: 42 → **43 casos**
- Victim `v0` en R0, height_m=0.9, PU foam fire 800s; baseline: `victim_v0_final_fed >= 0.7`

### 2. HUD VictimsPanel — Tarea 7 completada
**`ui/hud.gd`**:
- `"VictimsPanel"` añadido a `HUD_PANEL_PATHS` → stylebox + MOUSE_FILTER_STOP automático
- `@onready var _victims_panel` y `_victims_vbox` como nodos de escena
- `_ensure_victims_panel()`: solo aplica font overrides al título
- `_rebuild_victims_panel()`: crea tarjetas PanelContainer por víctima (igual que room cards)
- `_update_victims_panel(state)`: actualiza "FED: x.xx" + "  INCAPACITADO" con color severity

**`scenes/SimulationScene.tscn`**:
Árbol completo añadido y editable en Godot editor:
```
UI/HUD/VictimsPanel (PanelContainer, offset: -392→-8 left/right, -280→-162 top/bottom)
  └─ MarginContainer (margins 6/5/6/5)
       └─ VBoxContainer (sep=4)
            ├─ VictimsPanelTitle (Label, "Víctimas")
            └─ VictimsRows (VBoxContainer, sep=3)
```

### 3. Auditoría de @export — 6 parámetros faltantes en SimulationEngine
Parámetros que `ThermalSystem.configure()` aceptaba pero sin `@export` ni paso en configure():

| Parámetro | Default | Subsistema |
|---|---|---|
| `hrr_rad_wall_fraction` | 0.0 | HRR radiante a paredes |
| `fed_heat_rad_view_factor_below` | 0.35 | FED calor radiante bajo capa |
| `wall_conduction_max_fraction_per_step` | 0.08 | Estabilidad numérica conducción |
| `wall_adjacency_tolerance_m` | 0.10 | Detección paredes adyacentes |
| `plume_confined_flame_enabled` | true | Modelo penacho confinado |
| `plume_confined_z_eff_fraction` | 1.0 | z_eff penacho confinado |

Todos añadidos como `@export` y pasados en `thermal_system.configure({...})`.

### 4. Fix O₂ double-transport — Bug arquitectural
**Diagnóstico**: `GasExchangeSystem._apply_background_species_exchange()` y `OxygenExchangeSystem.step()` aplicaban el mismo cálculo de difusión O₂ room-to-room por separado. Ambos usaban `(room_a.o2 - room_b.o2) * exchange_air_kg` con la misma tasa base (0.035 kg/s/m²). Resultado: O₂ difundía 2× más rápido de lo físicamente correcto.

**Fix**:
- `GasExchangeSystem.gd`: `background_o2_exchange_multiplier: 1.0` → **`0.0`** (default)
- `SimulationEngine.gd`: nuevo `@export var background_o2_exchange_multiplier: float = 0.0` + pasado en configure()
- O₂ room-to-room: **exclusivo de OxygenExchangeSystem**
- O₂ desde exterior (ventilación natural): se mantiene en GasExchangeSystem (no duplicado)
- `ghanekar_bedroom_hallway.json` override `3.0`: sigue funcionando, ahora de forma explícita

**Nota sobre CO₂**: El repo memory registraba "CO₂ double-transport pendiente". Al auditar, `OxygenExchangeSystem.gd` ya no tiene ninguna asignación `co2_kg` — solo comentarios indicando que "CO₂ exclusivo de GasExchangeSystem". Ese bug ya estaba corregido en sesiones anteriores, la nota de backlog era stale.

**Suite**: en ejecución con el fix activo al momento de cerrar esta sesión.

---

## Roadmap — Estado completo actualizado

| # | Nombre | Estado |
|---|--------|--------|
| R#1 | Bernoulli default=true | ✅ COMPLETO |
| R#2 | Estratificación O₂/CO₂/HCN upper/lower | ✅ COMPLETO |
| R#3 | Conducción 1D Crank-Nicolson (PDE) | ✅ COMPLETO |
| R#4 | TargetModel masa térmica + sim_log_targets.csv | ✅ COMPLETO |
| R#5 | Energy conservation CI test | ✅ COMPLETO |
| R#6 | ZoneFireSolver Phase 1–4 (Jacobi delta-acumulación) | ✅ COMPLETO (05-18) |
| R#7 | Flujo vertical / multi-planta (chimney effect) | ✅ COMPLETO |
| — | Victims: BuildingModel + Engine + ThermalSystem + StateBuilder | ✅ COMPLETO (05-18) |
| — | Victims: HUD VictimsPanel (display FED por víctima) | ✅ COMPLETO (hoy) |
| — | Victims: CI case #43 victim_fed_incapacitation | ✅ COMPLETO (hoy) |
| — | Editor: VictimsPanel en escena .tscn editable | ✅ COMPLETO (hoy) |
| — | Editor: 6 @export faltantes en SimulationEngine | ✅ COMPLETO (hoy) |
| — | Bug: O₂ double-transport eliminado | ✅ COMPLETO (hoy, suite pendiente) |

---

### 5. Investigación suite de referencia CFAST/Ghanekar (72 checks)

#### Historial de runs hoy
| Run | Configuración | Resultado |
|-----|--------------|-----------|
| Run 1 | `fire_o2_nominal=0.130` (3 casos cerrados) | 52/72 PASS |
| Run 2 | `fire_o2_nominal=0.170` (3 casos cerrados) | 52/72 PASS |
| Run 3 | Fix init/clamp + `fire_o2_nominal=0.170` | **47/72 PASS** ← actual |

#### Bug identificado y "arreglado" (pero el fix empeoró el resultado)
**`sim/core/SimulationEngine.gd`** tenía dos usos incorrectos de `fire_o2_nominal`:

| Línea | Antes | Después |
|-------|-------|---------|
| 1096 | `room.reset_dynamic_state(ambient_c, fire_o2_nominal)` | `room.reset_dynamic_state(ambient_c, o2_nominal)` |
| 1989 | `room.o2 = clampf(room.o2, 0.0, fire_o2_nominal)` | `room.o2 = clampf(room.o2, 0.0, o2_nominal)` |

El fix es físicamente correcto (los cuartos deben iniciar con O₂=0.209, no con el umbral del fuego). Pero el resultado empeoró **neto −5 checks** porque:

#### Análisis del impacto del fix (Run 3 vs Run 2)

**Mejoras con el fix:**
- `cfast_closed_t210_temp_upper_c` → PASA ahora (actual≈265°C vs expected 265.7°C ±80) ✅

**Nuevos fallos:**
- `cfast_closed_t210_o2`: actual=0.1261 vs expected=0.091 tol=0.018 ← antes pasaba con O₂=0.170 init (coincidencia)
- `cfast_closed_t210_co_upper_ppm`: actual=1368 vs expected=595 tol=600 ← CO demasiado alto
- `cfast_closed_t300_co_upper_ppm`: actual=1398 vs expected=661 tol=600
- `cfast_2r_hall_t240_temp_upper_c`: actual=102°C vs expected=163°C tol=60 ← hall demasiado frío
- `cfast_hvac_t180_co_upper_ppm`: actual=892 vs expected=380 tol=500
- `cfast_hvac_t300_co_upper_ppm`: actual=1398 vs expected=661 tol=500

#### Hipótesis de la causa real de los fallos
Hay **dos problemas distintos** entrelazados:

1. **O₂ en sala cerrada (t=210s)**: CFAST reporta O₂=0.091 upper-layer (zona caliente); SimuFire reporta O₂=0.126 bulk-room. La diferencia puede ser intrínseca a la arquitectura two-zone (CFAST) vs one-zone (SimuFire): el upper layer de CFAST concentra los productos de combustión, por lo que su O₂ es menor que el promedio del cuarto. El match previo era una **coincidencia numérica** producida por el bug de inicialización.

2. **CO upper (todas las salas, todos los tiempos)**: CO excede en ~2× el valor de CFAST en todos los casos cerrados/HVAC. Esto apunta a un problema en el modelo de producción de CO (exceso de φ, yield incorrecto, o acumulación sin sumidero). NO fue introducido por el fix de hoy — ya existía pero estaba enmascarado.

3. **Temperatura cerrada/HVAC en t≥300s**: La temperatura cae muy por debajo de CFAST después de t=210s. Esto sugiere que el fuego se extingue (por O₂ agotado) mucho antes de lo que CFAST predice. El modelo de throttling por O₂ puede estar demasiado agresivo en la fase de agotamiento.

#### FAILs persistentes (presentes en los 3 runs — gaps conocidos)
```
cfast_t240_o2_depleted         — ventilation-limited burning (gap estructural)
cfast_t240_hrr_ventilation_limited — HRR ventilación limitada (gap estructural)
cfast_fed_heat_not_explosive   — FED calórico modelo distinto
cfast_2r_r0_t300_o2           — O₂ room-0 two-room (dirección opuesta entre runs)
cfast_2r_r0_t450_temp_upper_c — temperatura room-0 two-room
cfast_2r_hall_t240_o2          — O₂ hall two-room (hall O₂ demasiado alto)
cfast_2r_hall_t360_o2          — O₂ hall two-room
ghanekar_far_hall_o2_response_time_s — timing O₂ far hall (≈30s fuera de tol)
```

#### Próximos pasos recomendados
1. **Auditar producción de CO** en `CombustionSystem.gd` / `GasExchangeSystem.gd` — el factor φ→CO yield probablemente sobreestima en ~2×
2. **Revisar throttling O₂ post-depletion**: ¿por qué la temperatura colapsa a 46°C a t=450s en sala cerrada? El fuego se extingue completamente mientras CFAST mantiene ~175°C.
3. **Entender discrepancia O₂ upper-layer**: CFAST two-zone vs SimuFire one-zone — los checks de O₂ en sala cerrada pueden requerir tolerancias distintas o comparación con O₂ promedio de CFAST.

---

## Backlog restante

### Bugs físicos / deuda técnica
| Ítem | Prioridad | Notas |
|---|---|---|
| Causa raíz zombie fire | Baja | `fire_max_active_s=1800s` es parche; ACH mantiene O₂ en 10.04% |
| Conducción 1D paredes (PDE en default) | Baja | Implementado (`wall_pde_enabled=true`) pero OFF por defecto |
| `_sync_auxiliary_services()` llamado innecesariamente | Baja | Doble llamada desde `_reset_log_file()` |
| Paths hardcodeados en Main.gd/Visualizer.gd | Baja | NodePaths escritos a mano |

### Física no implementada (inherente al modelo de zona)
| Ítem | Contexto |
|---|---|
| Balance elemental C/H/O/N | CFAST tampoco lo cierra; yields globales es el estándar de zona |
| HCN sin dependencia del N del polímero | Limitación conocida y documentada |
| Targets / flux gauges geométricos | SF-AUD pendiente; CFAST los tiene, SimuFire no |
| HVAC real (ductos, presurización) | 25% de CFAST; fuera de alcance actual |

---

## Estado de validación

| Check | Resultado | Fecha |
|---|---|---|
| Suite regresión completa (43 casos) | ✅ **43/43 PASS** | 05-19 |
| Reference checks CFAST/Ghanekar (72) — run 1 (o2_nom=0.130) | 52/72 PASS | 05-19 |
| Reference checks CFAST/Ghanekar (72) — run 2 (o2_nom=0.170) | 52/72 PASS | 05-19 |
| Reference checks CFAST/Ghanekar (72) — run 3 (fix init/clamp) | ⚠️ **47/72 PASS** | 05-19 |

---

## Nivel de realismo (valoración actualizada)

### vs CFAST (modelo de zona): ~62%
Los arreglos de hoy (+6 @export, -O₂ duplicate) no mueven el marcador global, pero mejoran la coherencia interna del motor.

### vs valores experimentales reales
Esta es la pregunta correcta. Estado honesto:

**Lo que simula con base física sólida:**
- Crecimiento HRR (t², Kawagoe, extinción O₂) — correlaciones NFPA/SFPE
- FED/FEC completo ISO 13571 — implementación directa de la norma
- Estratificación two-zone con McCaffrey plume — Heskestad, plano neutro Bernoulli
- φ (equivalence ratio) en combustión → CO/CO₂ dependientes de ventilación (Beyler 1986)
- PDE 1D de conducción (5 nodos Crank-Nicolson) cuando está habilitada
- Flashover con 4 criterios paralelos (T, q″, Thomas, MQH)
- Backdraft con LFL/UFL/overpressure (CFAST no lo tiene)
- Pirólisis Tewarson con q_crit/ΔHg/ΔHc por material

**Lo que sigue siendo zona/heurístico:**
- Yields de especies: globales por combustible, no derivados de composición química del polímero
- Geometría: sólido lumped (ni masa de humo heterogénea ni campo de velocidades)
- Supresión: enfriamiento + reducción HRR; sin vapor, sin impacto de chorro, sin redistribución de oxígeno
- Calibración per-case: los 43 PASS son con overrides ajustados — no generaliza automáticamente

**Conclusión práctica**: El simulador es adecuado para **entrenamiento táctico cualitativo y semicuantitativo** en los escenarios que tiene casos de regresión. No es adecuado para predicción cuantitativa en escenarios no calibrados ni para decisiones de seguridad.

---

## Entorno técnico
- **Godot**: `C:\Users\dangp\Desktop\Godot_v4.6.2-stable_win64_console.exe`
- **Proyecto**: `c:\Users\dangp\Documents\GitHub\simufire`
- **Suite completa**: `sim/validation/run_all_cases.ps1 -GodotExe "..." -ContinueOnFailure`
- **Caso individual**: `sim/validation/run_case.ps1 -CaseName NAME -GodotExe "..." -TimeoutSeconds 480`
