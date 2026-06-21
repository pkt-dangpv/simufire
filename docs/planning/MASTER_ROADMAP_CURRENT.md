# Hoja de ruta activa de SimuFire

Fecha: 2026-06-21
Estado: fuente de verdad operativa para continuar trabajo
Alcance: validacion CFAST restante, FP ILV/humo, auditoria de humo motor e ILV futuro.

## Regla principal

No hacer cambios por hacer. Cada cambio debe estar ligado a una de estas tres lineas:

1. Reducir fallos reales de validacion o documentar por que son estructurales.
2. Corregir discrepancias visibles de FP/HUD/humo sin esconder datos fisicos.
3. Preparar el modelo ILV/infraventilado/ventilado sin romper el motor actual.

Antes de tocar motor:

- ejecutar o revisar `python scripts\simulation\validation_guardrails.py --verbose`;
- confirmar `git status --short --branch`;
- aislar el caso que se va a tocar;
- no modificar tolerancias ni reports para esconder fallos.

## Estado actual conocido

- Rama esperada: `main`; al cierre de rev 8 queda `ahead 2` por commits FP locales pendientes de push.
- Handoff vigente: `docs/HANDOFF_CURRENT_STATE.md`.
- Estado de validacion documentado: `docs/validation/STATUS_VALIDATION.md`.
- Baseline vigente: **345/350 required PASS, 5/350 required FAIL**.
- Gaps non-gating sincronizados: **69**.
- Los 5 fallos restantes estan clasificados como VALID_GAP estructural Phase 2/3+.

## Validacion CFAST: fallos vivos

| Grupo | Checks | Estado |
|-------|--------|--------|
| A — `cfast_r0_window_360` | `cfast_t240_o2_depleted`, `cfast_t350_o2`, `cfast_t360_o2` | VALID_GAP Phase 2 confirmado por Phase 5A sweep |
| C — `cfast_corridor_chain` | `cfast_chain_r0_t180_temp_upper_c`, `cfast_chain_r0_t600_temp_upper_c` | VALID_GAP Phase 3+; requiere arquitectura de presion/intercambio two-zone |

No queda candidato per-case de bajo riesgo. Los grupos B, D y E ya estan resueltos:

- Grupo B `cfast_slow_growth_sealed`: PASS con Phase 4B wall reradiation durante fuego activo.
- Grupo D `cfast_bedroom_closed_door`: PASS con Phase 2E-bedroom.
- Grupo E: `cfast_hvac_t300_o2` PASS con Phase 2D; `cfast_two_room_door_open` RMSE PASS con Phase 2C-thermal; multifuel PASS tras equivalencia de topologia CFAST.

## Decision inmediata recomendada

1. Confirmar baseline/producto: `python scripts\check_product.py` y, para motor, `python scripts\simulation\validation_guardrails.py --verbose`.
2. Elegir una linea:
   - producto/UX: QA manual de FP ILV/humo y ajuste de severidad visual;
   - auditoria motor: diagnosticar si `smoke_kg`/`visibility_m` son fisicamente insuficientes en ILV;
   - arquitectura cientifica: solo con plan explicito para two-zone canonico / Phase 3+;
   - documentacion: mantener sincronizados handoff, roadmap, guardrails y gap inventory.
3. No iniciar ILV, M2 global ni cambios de doorway/O2 en `sim/core` sin aprobacion explicita.

## Hotfix temperatura FP — CERRADO

Commit: `497b663 feat(fp-hud): smooth HUD temperature at thermal layer crossing` — 2026-06-21.

Causa raiz confirmada (Causa 2): funcion escalon en `estimate_temperature_at_height_m` con `thermal_gradient_band_fraction=0.0`. Al cruzar `thermal_layer_m` por la altura del jugador, el HUD saltaba hasta cientos de grados en un paso.

Fix aplicado (HUD-only, sin tocar fisica):

- `HUD_LAYER_BLEND_HALF_M = 0.25` en `FirstPersonController.gd`.
- Helper `_hud_temp_at_height_m()`: lerp `temp_lower_c`/`temp_upper_c` en banda ±25 cm alrededor de `thermal_layer_m`.
- Las tres posturas usan el helper; el filtro `fp_hud_temperature_smoothing_tau_s=0.5 s` sigue activo.
- Test `validate_fp_technical_hud.gd` actualizado.
- Verificado: FP technical HUD Godot 1/1 OK; producto/editor OK.

Pendiente de Causa 1 (baja prioridad): algunas rutas termicas en `ThermalSystem.gd` usan `open_fraction` directo. No genera saltos detectables en el escenario de diagnostico (`tools/diag_fp_temp_jump.json`), pero podria importar en escenarios muy calientes con aperturas grandes.

## FP ILV / HUD / humo — VISUAL CERRADO, QA PENDIENTE

Commits locales pendientes de push:

- `a6d44c0 fix(fp-hud): clarify ILV critical display`
- `b59fa33 fix(fp): strengthen ILV smoke visibility`

Alcance aplicado:

- HUD FP sin duplicar datos: el panel superior oculta HRR/visibilidad cuando el panel tecnico esta visible.
- Regimen visible como `ILC`, `ILV` o `ILV CRIT`.
- Gases etiquetados por capa (`O₂u/O₂l`, `COu`, `CO₂u`, `HCNu`) para evitar confundir capa superior con promedio de sala.
- Llama FP atenuada visualmente en `ILV_LATENT` o con O2 superior critico, sin cambiar HRR ni fisica.
- Humo FP endurecido en ILV critico: visibilidad severa default `1.6 m`, overlay mas opaco y luces de techo/aperturas atenuadas casi a cero.

Verificacion:

- `git diff --check` OK.
- `python scripts\check_product.py`: FP fire visuals, FP technical HUD y Combustion regime PASS; unico fallo sigue siendo guardrail conocido por los 5 VALID_GAP.

Pendiente:

1. QA manual en Godot con escenario ILV real.
2. Ajustar `smoke_overlay_ilv_severe_visibility_m` si 1.6 m resulta demasiado o poco agresivo.
3. No confundir este fix con calibracion de motor: no cambia `smoke_kg`, yields, soot ni transporte.

## Auditoria humo motor — SIGUIENTE RECOMENDADO

Objetivo: determinar si la visibilidad irreal restante proviene de generacion fisica insuficiente, transporte/estratificacion o solo representacion.

Escenario recomendado:

- Caso ILV reproducible (`cfast_ilv_audit` o variante FP jugable).
- Registrar por segundo: `combustion_regime`, `hrr_kw`, `o2_upper`, `o2_lower`, `smoke_kg`, `visibility_m`, `smoke_layer_m`, `soot_fraction`, `CO`, `CO2`, `HCN`, `FED`.

Criterios de decision:

- Si `smoke_kg` y `visibility_m` ya son severos pero FP se ve limpio: continuar visualizacion avanzada.
- Si `smoke_kg` es bajo o `visibility_m` demasiado alto en ILV con CO/HCN altos: abrir calibracion motor de humo/soot.
- Si humo se genera pero se evacua/mezcla de forma irreal: auditar transporte y estratificacion.

## Humo visual avanzado — FUTURO PRODUCTO

Tras QA manual, posible siguiente bloque visual:

- niebla/volumen local en FP;
- perdida de contraste por distancia;
- gradiente por altura;
- atenuacion de geometria lejana, techo y luminarias por profundidad;
- pruebas headless o capturas comparativas si es viable.

## ILV / infraventilado / ventilado

Documento base: `docs/architecture/ILV_COMBUSTION_REGIME_PLAN.md`.

Principio de implementacion:

- No crear un motor paralelo.
- No sustituir `CombustionSystem.step_room_fire` de golpe.
- Primero clasificar y registrar; despues cambiar comportamiento.
- Reutilizar campos existentes: `pyrolysis_kw`, `hrr_kw`, `hrr_target_kw`, `smolder_hrr_target_kw`, `retained_unburned_MJ`, `unburned_gas_vol_frac`, `o2_hrr_factor`, `ventilation_response_factor`.

Estados objetivo:

- `FUEL_CONTROLLED`
- `VENTILATION_STRESSED`
- `ILV_LATENT`
- `VENTILATION_CONTROLLED_BURNING`
- `VENTILATION_INDUCED_GROWTH`
- `FULLY_DEVELOPED`
- `BACKDRAFT_RISK`
- `BACKDRAFT_EVENT`
- `EXTINGUISHED`

ILV queda preparado, pero no debe adelantarse a la validacion abierta salvo que el usuario lo priorice expresamente.

## Puntos de entrada vivos

- `docs/HANDOFF_CURRENT_STATE.md`: estado operativo de sincronizacion.
- `docs/validation/STATUS_VALIDATION.md`: fuente de verdad de validacion.
- `docs/validation/GAPS_INVENTORY.md`: conteo de gaps non-gating.
- `docs/validation/GUARDRAILS_STATUS.md`: estado de guardrails.
- `docs/architecture/PHASE_5A_O2UPPER_SWEEP_RESULTS.md`: descarte per-case Grupo A.
- `docs/architecture/PHASE_3_DOORWAY_PRESSURE_ODE_PLAN.md`: plan pendiente de aprobacion para corridor_chain.
- `docs/architecture/ILV_COMBUSTION_REGIME_PLAN.md`: diseno ILV.

## Criterios de no-regresion

Antes de commit de motor:

- `python scripts\simulation\validation_guardrails.py --verbose`
- `python scripts\check_product.py`
- `python scripts\check_docs_links.py`
- `git diff --check`

Para cambios solo de documentacion:

- `python scripts\check_docs_links.py`
- `git diff --check`
