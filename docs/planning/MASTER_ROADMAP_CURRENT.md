# Hoja de ruta activa de SimuFire

Fecha: 2026-06-23
Estado: fuente de verdad operativa para continuar trabajo
Alcance: credibilidad del motor O2/HRR/ILV, validacion CFAST restante, escenarios FP/QA y limites de activacion M4.

## Regla principal

Durante la fase actual, la prioridad es credibilidad del motor. No perseguir un baseline bonito si eso conserva fisica falsa.

Cada cambio debe estar ligado a una de estas lineas:

1. Eliminar incoherencias fisicas reales, especialmente HRR alto con `o2_upper` critico.
2. Mantener o mejorar validacion sin tocar tolerancias para esconder fallos.
3. Crear escenarios nuevos que nazcan con la fisica correcta, en vez de recalibrar a ciegas casos legacy.
4. Documentar claramente que queda como VALID_GAP, caso legacy/control o deuda Phase 3+.

Antes de tocar motor:

- ejecutar o revisar `python scripts\simulation\validation_guardrails.py --verbose`;
- confirmar `git status --short --branch`;
- aislar el caso que se va a tocar;
- no modificar tolerancias ni reports para esconder fallos;
- si se activa M4 en un caso existente, comparar OFF/ON y revisar semantica de sus `threshold_metrics`.

## Estado actual conocido

- Rama esperada: `main`, sincronizada con `origin/main` tras push de `e944952`.
- Handoff vigente: `docs/HANDOFF_CURRENT_STATE.md` rev 15.
- Estado de validacion CFAST legacy: **345/350 PASS**, 5 required FAIL pre-existentes, todos VALID_GAP estructurales.
- Guardrails ampliados tras `v5_m4_ventilation_throttle`: **354 total**, 5 failures pre-existentes sin cambio.
- Auditor ILV suite: **8/8 PASS** en CSVs permanentes si se excluye el control intencional `fp_ilv_upper_throttle_off`.
- `fp_ilv_upper_throttle_off` sigue fallando por diseno: es control intencional para demostrar el bug HRR zombie.
- Python tests completos reportados: 244 tests, 5 failures + 1 error pre-existentes, sin regresion en la linea M4.

## Decision tecnica vigente

`fire_o2_upper_throttle_enabled` (M4) es el fix fisico gated para impedir HRR zombie cuando `o2_upper` esta critico.

Estado:

- Default global: `false`.
- Activacion global: **bloqueada** hasta migracion coordinada.
- Activacion junto a `fire_o2_canonical_enabled`: **no recomendada** sin plan explicito, porque M4 y canonical compiten y generan doble-freno.
- Activacion en casos legacy con threshold calibrado sobre HRR zombie: **no hacer silenciosamente**.
- Uso recomendado hoy: escenarios nuevos ILV/FP/QA disenados desde cero, o migraciones puntuales donde el caso no mida HRR como feature.

## Motor credibility: M4 y auditor ILV

### M4 completado

Commit base: `ba13139 fix(ilv): add fire_o2_upper_throttle_enabled motor guard (Phase 5 M4)`.

Causa raiz:

- `two_zone_solver_enabled=true` podia elegir `o2_ref = room.o2_lower` para HRR throttle.
- En salas con ventana exterior, `OxygenExchangeSystem.plume_lower_mode=false`, por lo que el consumo de O2 no depletaba `o2_lower`.
- Resultado: `o2_lower` fresco, `o2_hrr_factor` alto y HRR sostenido, mientras `o2_upper` caia a ~0.08%.

Fix:

- `CombustionSystem` aplica guardia si `fire_o2_upper_throttle_enabled=true`, `o2_upper < fire_o2_upper_throttle_critical` y el modo de O2 es `plume_lower`/`plume_blend`.
- En ese caso usa una referencia conservadora `min(room.o2, room.o2_upper)`.
- Keys ubicadas correctamente en `_build_room_combustion_context()`, no en `_sync_auxiliary_services()`.

Verificacion:

- Unit test Godot `tools/validate_fire_o2_upper_throttle.tscn`: 7/7 PASS.
- Control OFF: 258 findings, HRR zombie reproducido.
- M4 ON: 0 findings / 1686 rows, fuego se apaga alrededor de t=165 s.
- Guardrails legacy: sin regresion.

### Auditor de coherencia de suite

Commit: `d635c83 feat(ilv): add ILV layer-coherence suite auditor`.

Herramientas:

```powershell
python scripts\simulation\check_ilv_layer_coherence.py <csv> --room-id <id>
python scripts\simulation\audit_ilv_layer_coherence_suite.py --allow-findings
```

Uso:

- Detecta HRR significativo con `o2_upper` critico y throttle/regimen incoherente.
- Resume findings por CSV y localiza peor fila.
- Debe usarse antes y despues de cualquier migracion M4.

Estado post rev 15:

| CSV permanente | Estado | Notas |
|---|---|---|
| `cfast_ilv_audit` | PASS | Multi-room, sin HRR zombie |
| `fp_ilv_open_partial_window` | PASS | FP/QA fisico base |
| `fp_ilv_upper_throttle_on` | PASS | M4 activo, referencia de diseno |
| `ilv_open_window_repro` | PASS | Canonical activo |
| `layer_interface_single_room_window` | PASS | Migrado a M4 |
| `p2h_diag_off` | PASS | Sin exposicion exterior relevante |
| `p2h_diag_on` | PASS | Sin exposicion exterior relevante |
| `v5_m4_ventilation_throttle` | PASS | Nuevo caso M4 de supresion |
| `fp_ilv_upper_throttle_off` | FAIL intencional | Control de bug, no migrar |

## Migraciones M4 completadas

### `layer_interface_single_room_window`

Commits: `ee9216c`, `02ac871`.

Decision: activar `fire_o2_upper_throttle_enabled=true` permanentemente.

Motivo:

- El caso mide interfaz/capas, no HRR.
- OFF tenia 11 findings: HRR ~1142 kW con `o2_upper` ~0.08%.
- ON elimina HRR zombie sin romper metricas de capa.

Resultado:

- Coherence: 0 findings / 222 rows.
- Report: `all_pass=true`.
- Guardrails: sin regresion.

### `v5_m4_ventilation_throttle`

Commits: `21ba9ee`, `e944952`.

Decision: mantener `v5_ventilation_hrr_spike` como legacy/control y crear un caso nuevo M4.

Motivo:

- `v5_ventilation_hrr_spike` mide un spike HRR que resulta ser HRR zombie.
- Activar M4 en el caso original invertiria el sentido de sus checks.
- La ruta limpia es conservar trazabilidad legacy y crear una referencia corregida.

Nuevo caso:

- `sim/validation/cases/v5_m4_ventilation_throttle.json`
- `fire_o2_upper_throttle_enabled=true`
- Sin canonical.
- Baseline propio en `sim/validation/baselines/v5_m4_ventilation_throttle.json`.

Checks M4:

| Metrica | Regla | Estado |
|---|---|---|
| `room_0_peak_hrr_kw` | max 600 kW | PASS |
| `room_0_min_o2_upper` | min 0.05 | PASS |
| `room_0_min_l150_m` | min 1.90 m | PASS |
| `room_0_peak_co_upper_ppm` | min 1000 ppm | PASS |

Resultado:

- Baseline del caso: `all_pass=true`.
- Coherence: 0 findings / 726 rows.
- Guardrails ampliados: 354 total, 5 failures pre-existentes sin cambio.

## Casos legacy/control que NO migrar ahora

### `fp_ilv_upper_throttle_off`

Rol: control intencional para demostrar el bug HRR zombie.

No migrar. Debe seguir fallando en el auditor si se incluye como control. Usar `fp_ilv_upper_throttle_on` como pareja corregida.

### `v5_ventilation_hrr_spike`

Rol vigente: legacy/control de spike pre-M4.

No activar M4 directamente. El caso queda como referencia historica del comportamiento pre-M4. La fisica corregida vive en `v5_m4_ventilation_throttle`.

### Casos con `fire_o2_canonical_enabled=true`

No mezclar M4 con canonical sin plan. EXP-1 demostro doble-freno:

- canonical solo: HRR estable ~972 kW;
- canonical + M4: HRR oscila 100-750 kW y aparecen ciclos `ILV_LATENT`/`VENTILATION_CONTROLLED_BURNING`.

## Validacion CFAST: fallos vivos

Los fallos CFAST legacy restantes siguen fuera de la linea M4.

| Grupo | Checks | Estado |
|---|---|---|
| A - `cfast_r0_window_360` | 3 checks O2 | VALID_GAP Phase 2 confirmado por sweep |
| C - `cfast_corridor_chain` | 2 checks temperatura | VALID_GAP Phase 3+; requiere presion/intercambio two-zone |

No queda candidato per-case de bajo riesgo para cerrar esos 5 checks. No usar M4 para intentar cerrar Grupo A sin plan separado: mezcla una migracion ILV con gaps estructurales de validacion.

## Proxima linea recomendada

### Opcion A - Escenarios M4 nuevos (bajo riesgo)

Crear 1-2 escenarios ILV/FP/QA con M4 desde el principio:

- ventana parcial 25% / 75%;
- ACH moderado;
- sin canonical;
- baselines que midan supresion de HRR zombie, recuperacion de `o2_upper`, y ausencia de findings.

Objetivo: ampliar cobertura de fisica corregida sin tocar suite legacy.

### Opcion B - Migracion coordinada de casos con ventana (alto coste)

Inventariar todos los casos con:

- ventana exterior abierta o evento de apertura;
- `threshold_metrics`;
- HRR alto post-vent;
- `two_zone_solver_enabled=true` o seleccion O2 por capa.

Para cada caso:

1. correr OFF/ON con M4;
2. revisar si sus checks miden fisica valida o comportamiento bugged;
3. si miden bug, crear caso M4 paralelo o cambiar semantica con documentacion explicita;
4. solo despues considerar activacion global/perfil.

### Opcion C - Arquitectura Phase 3+ (alto coste, necesario a largo plazo)

Planificar two-zone canonico:

- `room.o2` como derivado de `o2_upper/o2_lower`, no fuente independiente;
- combustion vinculada a capa fisica correcta;
- intercambio por presion/doorway ODE;
- recalibracion completa de casos CFAST afectados.

Este es el camino para cerrar los VALID_GAP estructurales, pero no debe mezclarse con pequenas migraciones M4.

## Trabajo FP/visual

El bloque visual FP ILV/HUD/humo esta cerrado como mitigacion de presentacion:

- HUD por capa;
- `Reg ILV CRIT`;
- humo FP severo con visibilidad sub-metrica;
- luces/techo atenuados.

No confundir esos cambios con fisica. Las siguientes mejoras visuales quedan por debajo de motor credibility:

- volumen/niebla local;
- perdida de contraste por distancia;
- gradiente por altura;
- capturas comparativas FP.

## Criterios de no-regresion

Antes de commit de motor o caso de validacion:

```powershell
python scripts\simulation\validation_guardrails.py --verbose
python scripts\simulation\audit_ilv_layer_coherence_suite.py --allow-findings
python scripts\check_product.py
git diff --check
```

Para cambios solo de documentacion:

```powershell
python scripts\check_docs_links.py
git diff --check
```

Para migraciones M4 puntuales:

```powershell
python scripts\simulation\check_ilv_layer_coherence.py sim\validation\reports\<case>.csv --room-id <id>
python scripts\simulation\validate_reference_cases.py
python scripts\simulation\validation_guardrails.py
git diff --check
```

## Puntos de entrada vivos

- `docs/HANDOFF_CURRENT_STATE.md`: estado operativo de sincronizacion.
- `docs/validation/STATUS_VALIDATION.md`: fuente de verdad de validacion legacy.
- `docs/validation/GAPS_INVENTORY.md`: conteo de gaps non-gating.
- `docs/validation/GUARDRAILS_STATUS.md`: estado de guardrails.
- `docs/architecture/PHASE_5A_O2UPPER_SWEEP_RESULTS.md`: descarte per-case Grupo A.
- `docs/architecture/PHASE_3_DOORWAY_PRESSURE_ODE_PLAN.md`: plan pendiente para corridor_chain.
- `docs/architecture/ILV_COMBUSTION_REGIME_PLAN.md`: diseno ILV.
