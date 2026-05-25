# Estado de sesión — 2026-05-25

## Resumen ejecutivo

Sesión con dos líneas paralelas de trabajo:

1. **Phase 2E CO₂ — Sub-B descartado, Sub-D implementado y validado como CANDIDATO.**
2. **Glass failure refactor completo** — estado `glass_broken` en modelo, visual de cristal roto en 3D, HUD actualizado, selector de modo en menú.

**Resultado final: 292/292 PASS, 65 gaps** (3 nuevos checks required añadidos vs 289 de sesión anterior).

---

## Lo que se hizo esta sesión

### 1. Phase 2E Exp 1C — Sub-B investigado y descartado

**Mecanismo Sub-B**: reducir `CO2_EXCHANGE_FRACTION` en `_exchange_room_o2_active_flow` (default 0.25 → sweep 0.03/0.05/0.08) para retener más CO₂ en la sala fuego.

**Resultado**: Sub-B DESCARTADO. El colapso de `co2_upper` a t=480 en `cfast_two_room_door_open` se produce por las ramas de homogenización bi-zona (Rama A: `lower_frac < 0.15`) y decay sin fuego (Rama B: `hrr_kw == 0.0`), que son **independientes** del exchange activo. Ningún valor de `CO2_EXCHANGE_FRACTION` afecta la gate t480.

| Sub-B fraction | Gate t480 (target 9.91±3%) | Sentinels | FED delta |
|----------------|----------------------------|-----------|-----------|
| 0.25 (baseline) | 1.0% → FAIL | 5/5 OK | 0.000 |
| 0.08 | 1.0% → FAIL | 5/5 OK | 0.000 |
| 0.05 | 1.0% → FAIL | 5/5 OK | 0.000 |
| 0.03 | 1.0% → FAIL | 5/5 OK | 0.000 |

Diagnóstico confirmado por log: en t=380, `HotLayer=0.30m`, `lower_frac=0.12 < 0.15` → Rama A → snap `co2_upper` de 119,907 ppm a 6,520 ppm.

Archivo creado: `scripts/simulation/phase2e_co2_experiment_1c_runner.py` (untracked).
`docs/PHASE_2E_CO2_DESIGN.md` sección 12.8 añadida.

---

### 2. Phase 2E Sub-D — Implementación y validación (Exp 1D)

**Mecanismo Sub-D** (`phase2e_co2_subd_enabled`): cuando bi-zona inválida (`_bi_zone_invalid=true`) Y sala tiene fuego activo (`hrr_kw > 0.0`), omite el snap de `co2_upper` a valor-masa. La rama de producción continúa; `co2_upper` permanece en el valor acumulado.

**Implementación — archivos modificados:**

| Archivo | Cambio |
|---------|--------|
| `sim/core/OxygenExchangeSystem.gd` | `phase2e_co2_subd_enabled: bool = false`; `_bi_zone_invalid` extraído como var; `_subd_skip_snap` guard; `phase2e_co2_subb_enabled` + `phase2e_co2_exchange_fraction` (infraestructura no-op) |
| `sim/core/SimulationEngine.gd` | `@export var phase2e_co2_subd_enabled: bool = false`; `@export var phase2e_co2_subb_enabled: bool = false`; wired en `configure()`; `apply_runtime_options()` añadido |
| `docs/PHASE_2E_CO2_DESIGN.md` | Sección 12.9 — diseño Sub-D, decisión Exp 1C |

**Lógica exacta en OxygenExchangeSystem.gd:**
```gdscript
var _bi_zone_invalid: bool = lower_frac < 0.15 or (lower_frac < 0.40 and room.o2 < 0.070)
var _subd_skip_snap: bool = phase2e_co2_subd_enabled and room.hrr_kw > 0.0 and _bi_zone_invalid
if _bi_zone_invalid and not _subd_skip_snap:
    # snap original — homogeniza co2_upper a valor-masa
    ...
elif room.hrr_kw > 0.0:
    # rama producción — delta CO₂ por combustión
    ...
```

**Resultados Exp 1D (Sub-D ON):**

| Gate / Check | CFAST ref | Baseline OFF | Sub-D ON | Resultado |
|--------------|-----------|--------------|----------|-----------|
| Sentinels 5/5 | — | 5/5 | 5/5 | ✅ OK |
| FED delta | — | — | 0.000 | ✅ OK |
| Gate t120 (≤5.58%) | 1.58% | 4.7% | 4.7% | ✅ OK |
| Gate t480 ∈[6.91%,12.91%] | 9.91% | 1.0% | **12.1%** | ✅ PASS |
| cfast_t510 (±20000 ppm) | 52300 ppm | 16182 ppm | 25047 ppm | ⚠️ FAIL (Δ=-27253) |
| Runs sin error | — | — | 6/6 | ✅ OK |

**Tabla diagnóstico snap (room 0):**

| t(s) | HRR | HotLayer | CO2u-OFF (ppm) | CO2u-ON (ppm) | Δ |
|------|-----|----------|----------------|---------------|---|
| 370 | — | 0.63m | 119,907 | 119,907 | 0 |
| **380** | — | **0.30m** | **6,520** | **120,709** | **+114,189 ← SNAP ELIMINADO** |
| 420 | — | — | 10,100 | 121,576 | +111,476 |
| 480 | — | — | 9,990 | 121,380 | +111,390 |

**VEREDICTO: Sub-D CANDIDATO — todos los gates pasan.**

El check `cfast_t510` falla (non-gating), probablemente porque entre t=480-510 el fuego se debilita hasta `hrr_kw ≈ 0` y Sub-D deja de aplicar (rama B decay activa). No bloquea la candidatura.

Archivo creado: `scripts/simulation/phase2e_co2_experiment_1d_runner.py` (untracked).

---

### 3. Glass Failure System — Refactor completo

**Objetivo**: desacoplar el estado de cristal roto del valor `open_fraction`. Antes, `open_fraction >= 0.001` se usaba como proxy de "cristal roto". Ahora hay estado explícito.

#### Cambios por archivo:

**`sim/building/OpeningModel.gd`**
- `var glass_broken: bool = false`
- `func mark_glass_broken() -> void` — sólo actúa si `type == Type.WINDOW`
- `get_opening_summary()` incluye `"glass_broken": glass_broken`

**`sim/core/GlassFailureSystem.gd`**
- Modo determinista y probabilista usan `op.mark_glass_broken()` en lugar de comprobar `op.open_fraction >= 0.001`
- `was_intact: bool = not op.glass_broken` (antes era `< 0.001`)
- Comentarios actualizados para reflejar semántica correcta ("area efectiva", no "abre")

**`sim/BuildingModel.gd`**
- `get_opening_summary()` exporta `"glass_broken": op.glass_broken`

**`view/fp/FirstPersonController.gd`**
- `@export var window_glass_shard_color: Color` y `window_glass_crack_color`
- `_create_window_broken_detail()` — geometría de cristal roto (shards triangulares en 3D)
- Marco de ventana con cuatro listones (`LeafFrameTop/Bottom/Left/Right`) y manilla (`LeafHandle`)
- `_set_window_leaf_broken()` — alterna visibilidad del detalle roto vs. cristal intacto
- `handle_sign` (antes `_handle_sign`) — renombrado a público para uso en métodos de dibujo

**`ui/HUDOpeningSummary.gd`**
- Muestra `"RT"` (rota) como state_short cuando `glass_broken == true`
- Color naranja (`SimuFireThemeScript.ORANGE`) para ventanas rotas

---

### 4. Runtime Options / Selector modo cristal en menú

**Objetivo**: permitir seleccionar el modo de rotura de cristales desde el menú principal, persistir la selección en `user://startup_sim_options.json`, y aplicarla al engine antes de la simulación.

**`scenes/MainMenu.gd`**
- `_glass_break_option: OptionButton` y `_glass_break_modes: Array[int]`
- `GlassBreakRow` con 3 opciones: Sin rotura (0) / Umbral temp. (1) / Probabilistica (2)
- Lee/escribe `glass_break_mode` en `user://startup_sim_options.json`
- `_populate_glass_break_option()` + `_move_before_first_button()` para layout

**`Main.gd`**
- `const STARTUP_OPTIONS_PATH: String = "user://startup_sim_options.json"`
- `_apply_startup_engine_options()` — carga opciones y las aplica al engine al iniciar simulación
- `_load_startup_options() -> Dictionary` — lee y parsea el JSON
- `_is_validation_mode() -> bool` — detecta modo headless (args `--validation-case`) para no aplicar opciones

**`sim/core/SimulationEngine.gd`**
- `func apply_runtime_options(options: Dictionary)` — acepta `glass_break_mode: int`, lo clampea a `[DISABLED, PROBABILISTIC]`, llama `_sync_auxiliary_services() + glass_failure_system.reset()` si cambió algo

---

## Estado final del código

### Suite de validación
- **292/292 required checks PASS** (vs 289/289 al inicio de sesión — 3 nuevos checks añadidos, glass-break related)
- **65 known gaps** no-gating (sin cambio)

### Archivos modificados sin commitear

| Archivo | Categoría | Cambio principal |
|---------|-----------|-----------------|
| `sim/core/OxygenExchangeSystem.gd` | Motor CO₂ | Sub-D + Sub-B flags + lógica |
| `sim/core/SimulationEngine.gd` | Motor | Sub-D/Sub-B @export; `apply_runtime_options()` |
| `docs/PHASE_2E_CO2_DESIGN.md` | Docs | Sub-B diagnosis + Sub-D diseño |
| `sim/building/OpeningModel.gd` | Modelo | `glass_broken` state |
| `sim/core/GlassFailureSystem.gd` | Motor | Usa `glass_broken` |
| `sim/BuildingModel.gd` | Modelo | Exporta `glass_broken` en summary |
| `view/fp/FirstPersonController.gd` | Vista 3D | Visual cristal roto |
| `ui/HUDOpeningSummary.gd` | HUD | "RT" + naranja para rota |
| `scenes/MainMenu.gd` | UI | Selector modo cristal |
| `Main.gd` | Core | Startup options loader |

### Archivos nuevos sin trackear

| Archivo | Descripción |
|---------|-------------|
| `scripts/simulation/phase2e_co2_experiment_1c_runner.py` | Sub-B sweep (descartado) |
| `scripts/simulation/phase2e_co2_experiment_1d_runner.py` | Sub-D candidato |

---

## Análisis de situación — Phase 2E CO₂

### Estado del mecanismo Sub-D

Sub-D es **CANDIDATO** pero **no activado en producción** (`default=false`). La flag existe como `@export` en el inspector Godot. Para promoverlo a producción:
1. Verificar que los 3 checks nuevos incluyen validación de Sub-D en producción, o
2. Crear experimento Sub-D + Sub-A combinados para cerrar el gap residual t=510

### Gap residual t=510

`cfast_t510_co2_upper_ppm`: Sub-D ON = 25,047 ppm vs CFAST = 52,300 ppm (Δ = -27,253, outside ±20,000).

Hipótesis: entre t=480-510 el HRR cae a ≈0 en sala fuego → Sub-D deja de proteger (`hrr_kw > 0.0` ya no se cumple) → Rama B decay activa → `co2_upper` cae. Si Sub-A mantiene el CO₂ durante el período post-fire, la combinación cerraría el gap.

**Sub-A** (`phase2e_co2_suba_enabled`): ya existe como var en `OxygenExchangeSystem.gd` (infraestructura, sin lógica activa). Necesita definición de mecanismo.

---

## Parámetros de referencia

- **Godot exe**: `F:\OneDrive\Escritorio\Godot_v4.6.3-stable_win64_console.exe`  
  (fallback: `C:\Users\dangp\Desktop\Godot_v4.6.3-stable_win64_console.exe`)
- **Workspace**: `F:\OneDrive\Documentos\GitHub\simufire`
- **Suite de validación**:
  ```powershell
  cd F:\OneDrive\Documentos\GitHub\simufire
  python scripts/simulation/validate_reference_cases.py
  ```
- **Guardrails rápidos**:
  ```powershell
  python scripts/simulation/validation_guardrails.py
  ```
- **Experimento Sub-D**:
  ```powershell
  python scripts/simulation/phase2e_co2_experiment_1d_runner.py
  ```

---

## Próximos pasos

| Prioridad | Tarea | Estado |
|-----------|-------|--------|
| 1 | Git commit — motor + glass UI (TODO: separar en ≥2 commits) | ⬜ pendiente |
| 2 | Sub-D + Sub-A combined experiment — cerrar gap cfast_t510 | ⬜ pendiente |
| 3 | Definir mecanismo Sub-A (decay lento post-fire en sala fuego) | ⬜ pendiente |
| 4 | Decidir si promover Sub-D a producción o esperar Sub-D+Sub-A | ⬜ pendiente |
| 5 | Phase 2E-C rediseño (Opción B — split CO transporte desde origen) | ⬜ no iniciado |
| 6 | V4–V8 casos de validación | ⬜ no iniciado |
