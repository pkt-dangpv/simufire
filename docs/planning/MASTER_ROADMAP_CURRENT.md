# Hoja de ruta activa de SimuFire

Fecha: 2026-07-25
Estado: fuente de verdad operativa para continuar trabajo
Alcance: credibilidad fisica del motor, balances de conservacion, validacion CFAST restante y limites de cambios globales.

## Regla principal

La prioridad actual es que el motor sea fisicamente auditable. No perseguir un baseline bonito si eso conserva datos incoherentes.

Cada cambio debe estar ligado a una de estas lineas:

1. Cerrar incoherencias fisicas con auditoria reproducible.
2. Mejorar instrumentacion y balances sin cambiar fisica accidentalmente.
3. Mantener validacion CFAST sin tocar tolerancias para esconder fallos.
4. Documentar explicitamente lo que queda como `VALID_GAP`, caso legacy/control o deuda Phase 3+.

Antes de tocar motor:

- confirmar `git status --short --branch`;
- revisar `docs/HANDOFF_CURRENT_STATE.md`;
- revisar `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`;
- ejecutar o justificar por que no se ejecuta `python scripts\simulation\validation_guardrails.py --verbose`;
- no modificar reports, baselines ni tolerancias para forzar PASS.

## Estado actual conocido

- Rama esperada: `main`; antes de esta nota estaba local ahead de `origin/main`.
- Handoff vigente: `docs/HANDOFF_CURRENT_STATE.md` rev 21.
- Ultimo estado documentado: C1 backdraft/pool-release path exercised, pero no clean promotion evidence; M5 post-backdraft HRR cut queda como proximo experimento de motor.
- Suite referencia: **347/353 PASS**.
- Los 6 FAIL restantes son los `VALID_GAP` conocidos:
  - Grupo A: O2 en `cfast_r0_window_360`.
  - Grupo C: temperatura y O2 upper en `cfast_corridor_chain`.
- F3.3l corrigió la topología real de `cfast_corridor_chain`.
- F3.3m cerró la correspondencia temporal R0→Hall: el caudal pasa de déficit
  temprano a superávit tardío y el aporte convectivo queda muy por debajo de
  CFAST.
- F3.3n valida el reparto receptor `flogo` sobre la topología corregida:
  forma las capas altas de Hall/R2 y acerca las cuatro direcciones a CFAST
  con conservación exacta. Queda default OFF y no autoriza el shadow.
- F3.3o descarta cambiar solo la fracción radiativa: duplica casi el calor
  sin aumentar el plume, sobrecalienta R0/Hall/R2 y empeora la masa upper.
- F3.3p reconstruye el balance lower y autoriza solo un experimento
  escalonado: a 600 s faltan 109.1 kg de plume frente a CFAST y las rutas
  pierden 123.4 kg de margen lower. F3.3n ayuda, pero no prueba por si solo
  que el colapso antiguo este cerrado.
- F3.3p1 reintrodujo temporalmente el contrato unificado
  `Q aceptado -> Qc -> calor + plume` con routing F3.3n. A 180 s cerro masa,
  interfaz y plume, pero sobrecalento R0 (`200.75 C` frente a `159.82 C`) y
  tambien Hall/R2. Fue NO-GO y se retiro sin ejecutar 300/600 s.
- F3.3q localiza un deficit de perdida de frontera de `3.414 MJ` hasta 180 s.
  El balance canonico cierra, pero el caso no transmite el hormigon de CFAST
  y el contrato usa `40.0 m2` de pared frente a `83.2 m2` de envolvente.
- F3.3r0 confirma que el material importa: el hormigon reduce el deficit de
  frontera de `3.414` a `0.730 MJ` y corrige la temperatura upper temprana.
  No es adoptable porque sobreenfria R0/Hall lower y R2 upper a 180 s.
- F3.3r1 cierra la atribucion: CFAST almacena unos `26.993 MJ` en superficies
  a 180 s; `13.392 MJ` son radiacion directa del fuego y `13.601 MJ` vienen
  del gas, frente a `14.163 MJ` inferidos por el balance de sala.
- El shadow material solo conserva `9.009 MJ` en pared y elimina `3.796 MJ`
  por decay ambiente sin superficie. Por eso el sink total puede coincidir
  mientras pared y lower zones quedan frios.
- F3.3r2 cierra el diseno de un shadow multi-superficie default OFF:
  techo, pared upper, pared lower y suelo; radiacion de combustion atomica;
  migracion conservativa al mover la interfaz; y un invariante unico
  gas/superficies/exterior.
- La implementacion se divide en F3.3r2a solver puro y fixtures, F3.3r2b
  estado/transacciones y F3.3r2c gates scratch 60/120/180 s. Solo r2a queda
  autorizado como siguiente paso. El parche de area completa sigue NO-GO.
- F3.3r2a ya entrega el solver puro: respuesta de hormigon a 60 s con error
  `3.07%` frente a la solucion semi-infinita y residual acumulado
  `5.96e-8 kJ` tras 10.000 pasos. No tiene wiring runtime.
- F3.3r2b/b1/b2 ya entregan estado, transaccion atomica, intercambio
  gas-superficie y topologia explicita default OFF.
- F3.3r2c cierra contabilidad multi-superficie pero falla correspondencia
  fisica a 180 s: masa/interfaz, temperaturas y radiacion aceptada.
- F3.3r2d atribuye el deficit radiativo de `4.268 MJ`: `3.814 MJ` vienen del
  throttle de decision O2, `0.454 MJ` de la trayectoria fuente y `0 MJ` del
  commit atomico. La interfaz alta desplaza `1.775 MJ` de pared upper a
  lower sin romper conservacion.
- Siguiente fase: F3.3s, auditoria pasiva de masa/interfaz/O2 hasta 180 s.
  No ajustar radiacion ni prescribir la interfaz CFAST.
- Physics coherence audit: suite con controles intencionales registrados (`v1_backdraft_accumulation`, `v1_m4_pool_release`). Reglas FAIL/gating: B1, C1, C2, A2, A3, D1, E1, S0. WARN: O1, O2E1.
- Tests Python: **157 PASS**.

## Cambio de enfoque

La linea M4/ILV ya no es el unico centro. El proyecto paso a una revalidacion fisica integral:

- HRR, combustible, energia y regimen de combustion.
- O2 por capa/sala y acoplamiento con HRR.
- CO/CO2/HCN, generacion local, transporte y balance de carbono.
- Humo/soot, visibilidad, FED y tenabilidad.
- Temperaturas upper/lower, capas, presion, plano neutro e isoterma 150 C.
- Modelo bizona, ventilacion por puertas/ventanas, flotabilidad y transporte multi-room/multi-planta.
- Paredes, radiacion, almacenamiento termico y reradiacion.

Documento maestro:

- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`

## Auditores vigentes

### Auditor fisico general

Archivos:

- `scripts/simulation/check_physics_coherence.py`
- `scripts/simulation/audit_physics_coherence_suite.py`
- `tests/test_check_physics_coherence.py`

Reglas vigentes:

| Regla | Severidad | Estado |
|---|---|---|
| `B1` inversion termica fuerte | FAIL | Gating |
| `C1` FED suma | FAIL | Gating |
| `C2` FED monotonica | FAIL | Gating |
| `A2` HRR sin combustible | FAIL | Gating |
| `A3` regimen vs O2 superior critico | FAIL | Gating |
| `D1` balance CO por sala/paso | FAIL | Gating |
| `E1` balance combustible solido | FAIL | Gating |
| `S0` conservacion humo global | FAIL | Gating |
| `O1` balance masa O2 bulk | WARN | Clean 11/11, no gating |
| `O2E1` cross-check Thornton HRR↔O2 | WARN | Clean 11/11, no gating |

### Auditor ILV por capas

Archivos:

- `scripts/simulation/check_ilv_layer_coherence.py`
- `scripts/simulation/audit_ilv_layer_coherence_suite.py`

Uso:

- Detecta HRR significativo con `o2_upper` critico y throttle/regimen incoherente.
- `fp_ilv_upper_throttle_off` sigue siendo control intencional y puede fallar si se incluye.

## Lineas cerradas

### M4 ILV upper-O2 throttle guard

Estado:

- `fire_o2_upper_throttle_enabled` existe como fix fisico gated.
- Default global: `false`.
- Activacion global: bloqueada hasta migracion coordinada.
- No mezclar con `fire_o2_canonical_enabled` sin plan explicito: ambos mecanismos compiten.
- Casos correctos con M4:
  - `fp_ilv_upper_throttle_on`
  - `layer_interface_single_room_window`
  - `v5_m4_ventilation_throttle`

Decisiones vigentes:

- `v5_ventilation_hrr_spike` queda como legacy/control pre-M4.
- `v5_m4_ventilation_throttle` es la referencia fisica corregida.
- No usar M4 para intentar cerrar Grupo A sin plan Phase 3+/O2 separado.

### S0 smoke global conservation

Estado: cerrado como `FAIL`/gating.

Cobertura:

- Valida `sum(smoke_kg) + smoke_in_transit_kg` contra generado menos venteado menos depositado.
- Corrigio contabilidad de ACH, purga por ventilacion natural, humo interior diferido y masa sub-threshold.
- Corpus fresco: 11/11 CSVs PASS, 0 findings.

### D1 CO balance

Estado: cerrado como `FAIL`/gating.

Invariante:

```text
delta_co = co_kg[t] - co_kg[t-1]
expected = delta(co_generated_kg_total)
           + delta(co_net_transport_kg_total)
           - delta(co_exterior_removed_kg_total)
residual = abs(delta_co - expected)
```

Correcciones relevantes:

- `GasExchangeSystem._purge_upper_species_to_exterior_direct`
- `ThermalSystem._flush_contaminant_deltas`
- `GasExchangeSystem._release_pending_interior_deliveries`

Nota: `co_net_transport_kg_total` es neto amplio e incluye intercambio, arrastre termico/hot-gas carry y entregas interiores diferidas. Exterior se contabiliza aparte.

### E1 fuel balance

Estado: corregido para usar combustible solido explicito.

Decision:

- E1 valida `solid_fuel_remaining_MJ` contra `fuel_consumed_MJ_total`.
- No usar `fuel_remaining_MJ` legacy visible como fuente principal: puede incluir retained/unburned/object state y dar falsos residuales.

### O2E1 Thornton cross-check HRR↔O2

Estado: **WARN**, no `FAIL`/gating todavia. La regla esta limpia en el corpus base; C1 backdraft/pool-release esta ejercitado pero no aporta evidencia limpia de promocion por zombie A3 post-evento.

Invariante:

```text
expected_o2   = delta(hrr_kj_total) * 7.6e-5   (Thornton: kg O2 / kJ HRR)
delta_o2_fire = delta(o2_consumed_fire_kg_total)
residual      = |delta_o2_fire - expected_o2|
tolerance     = max(1e-5, 0.05 * |expected_o2|)
```

Columnas clave:

- `hrr_kj_total` — acumulado por CombustionSystem como `maxf(0, hrr_kw) * dt`. Tracking-only.
- `o2_consumed_fire_kg_total` — acumulado por OES via path primario (una unidad Thornton por paso). Tracking-only.

Por que `*_fire` y no `*_all`: `o2_consumed_kg_total_all` acumula todas las rutas OES. En modo two-zone estandar (bulk + upper ambos activos), acumula 2× Thornton. El acumulador `*_fire` selecciona solo el path primario: bulk si corrio; de lo contrario lower/plume/upper segun el flag activo.

Resultado actual:

- Corpus base O2E1: PASS limpio.
- C1 backdraft/pool-release: `v1_m4_pool_release` ejercita el path (`backdraft_triggered=1` a t=350 s) pero deja 5 WARN post-evento por zombie A3.
- No cambio de fisica. O1 intacto.
- 157 tests PASS.

Criterios para promover a FAIL:

1. O2E1 PASS limpio en corpus que incluya: backdraft o pool-release, caso largo (≥ 600 s), caso multi-room con intercambio O2, caso con `effective_plume_lower` o `fire_uses_lower_o2` activos.
2. Revision de tolerancias bajo condiciones de O2 bajo y cap activo.
3. Plan explicito de promocion antes de tocar `severity`.

### O1 bulk O2 balance

Estado: **WARN-clean**, no `FAIL`/gating todavia.

Invariante:

```text
delta_bulk = (o2[t] - o2[t-1]) * air_mass_kg
expected   = -delta(o2_consumed_bulk_kg_total)
             + delta(o2_exterior_net_kg_total)
             + delta(o2_net_transport_kg_total)
             + delta(o2_zone_sync_kg_total)
residual   = abs(delta_bulk - expected)
```

Resultado actual:

- 11/11 PASS.
- 0 O1 findings.
- Max residual < `4e-4 kg`.
- Sigue como WARN hasta validarse en corpus mas amplio, largo y multi-planta.

Correcciones importantes:

- `SimulationStateBuilder` exporta `room.o2` real, no valor con correccion molar CO2 aplicada.
- O1 usa `o2_consumed_bulk_kg_total`, no `o2_consumed_kg_total_all`.
- `_apply_room_o2_mass_delta` acumula delta post-clamp real.

## Caveats conocidos

### CO2 upper dual tracking

`co2_upper_ppm` es tracer-derived (`co2_upper * 1e6`), mientras CO upper ppm es mass-derived.

Consecuencia:

- Reglas CO/CO2 ratio quedan bloqueadas.
- No implementar D2 hasta resolver o documentar la semantica dual de `co2_upper` / `co2_upper_kg`.

### O1 no sustituye balance zonal

O1 audita `room.o2` bulk. No cierra todavia la conservacion de `o2_upper` / `o2_lower`.

Pendiente:

- Balance zonal O2 por capa.
- Separacion clara de combustion, transporte y zone-sync.
- Reconciliacion con future two-zone canonico.

## Fallos CFAST vivos

Los 5 FAIL restantes siguen siendo estructurales y no pertenecen a D1/S0/O1:

| Grupo | Checks | Estado |
|---|---|---|
| A - `cfast_r0_window_360` | 3 checks O2 | VALID_GAP Phase 2/3+, requiere arquitectura O2/two-zone |
| C - `cfast_corridor_chain` | 2 checks temperatura | VALID_GAP Phase 3+, requiere presion/intercambio two-zone |

No cambiar tolerancias ni reclasificar estos FAIL sin decision cientifica explicita.

## Proxima linea recomendada

### Prioridad 1 - M5 post-backdraft HRR cut

Motivo: C1 backdraft/pool-release ya esta ejercitado, pero el caso no es evidencia limpia para promover O2E1 porque queda un zombie A3 post-evento.

Diagnostico:

- El backdraft principal de `v1_m4_pool_release` ocurre a t=350 s y agota el pool a t=355 s.
- Despues, `hrr_target_kw=0` pero `room.hrr_kw` cae con smoothing (`fire_hrr_fall_tau_s=20`), dejando HRR positivo con `o2_upper` critico.
- Esa cola produce A3/O2E1 WARNs post-evento y puede permitir reacumulacion de pool/segundo backdraft artificial.

Implementacion recomendada:

- Nuevo flag `fire_post_bd_hrr_cut_enabled`, default `false`.
- Activarlo primero solo en `v1_m4_pool_release`.
- En `CombustionSystem.gd`, despues de `room.backdraft_active` y antes de consumo/reacumulacion de pool, cortar `room.hrr_kw`, `room.hrr_target_kw` y `retained_generation_kw` cuando: no backdraft activo, no llama viable, no latencia viable, `retained_unburned_MJ < 0.001` y `fire_o2_ref < fire_o2_min_for_flame`.

Criterios de aceptacion:

- Backdraft principal preservado a t≈350 s.
- Sin segundo backdraft artificial.
- A3=0 y O2E1=0 WARN en `v1_m4_pool_release`.
- `check_physics_coherence.py` limpio para el caso.
- Guardrails globales estables por default-off.
- No tocar tolerancias ni `severity` de O2E1.

### Prioridad 1b - O2 + energia/HRR

Corpus diagnostico completado (2026-06-27). Resultados:

| Criterio | Caso | Resultado |
|---|---|---|
| C1 backdraft/pool-release | v1_m4_pool_release | ⚠️ Path ejercitado (CTRL) — O2E1 limpio durante backdraft; zombie A3 post-evento |
| C2 larga duracion ≥ 600 s | cfast_slow_growth_sealed | ✅ PASS total |
| C3 multi-room O2 exchange | cfast_two_room_door_open | O2E1 ✅ PASS; O1 247 WARNs (gap multi-room) |
| C4 effective_plume_lower | fp_ilv_open_partial_window | ✅ Ya en suite, PASS |

**Decision C1 cerrada (2026-06-27):** `v1_m4_pool_release` confirma que el motor ejecuta correctamente el path backdraft/pool-release (`backdraft_triggered=1` a t=350s, pico HRR 21 369 kW, pool agotado en t=355s, O2E1 limpio durante el evento). El zombie A3 que reaparece post-evento es un bug de motor separado — ambos casos marcados CTRL. **O2E1 permanece WARN.**

Bloqueo para O2E1 → FAIL:

- C1 "path exercised" pero no "clean promotion evidence": los 5 O2E1 WARN post-backdraft son consecuencia del zombie A3, no de un fallo de Thornton. La promocion requiere un caso backdraft/pool-release completo sin A3 zombie post-evento, o una politica de exclusion explicita aprobada.
- Requisito minimo para promover: (a) caso C1 que sale exit 0 en check_physics_coherence, o (b) decision documentada de que O2E1 WARN del zombie no bloquea la promocion porque ocurren fuera de la ventana de backdraft.

Proximo experimento para C1 limpio: M5 post-backdraft HRR cut. La politica de exclusion queda como alternativa secundaria, no preferida.

Otras reglas pendientes en el bloque O2/energia:

- HRR x dt vs consumo de combustible solido (ya cubierto parcialmente por E1 en sentido inverso).
- Coherencia entre `solid_pyrolysis_kw`, `fresh_flame_target_kw`, `smolder_hrr_target_kw`, `pool_release_hrr_target_kw` y `hrr_kw` — verificar que la suma de targets no exceda la generacion de pirolisis.
- Balance zonal O2 (`o2_upper`/`o2_lower`) — pendiente, ver caveat "O1 no sustituye balance zonal".

Restricciones vigentes:

- No anadir una segunda ruta fisica de consumo O2: OES ya aplica Thornton rate.
- `o2_consumed_kg_total_all` no es la fuente correcta para reglas de coherencia energetica: usar `o2_consumed_fire_kg_total`.

### Prioridad 2 - Corpus O1 ampliado

Mantener O1 como WARN hasta probar:

- escenarios largos;
- multi-room;
- multi-planta;
- ventilacion exterior con eventos;
- HVAC solo cuando el nucleo este estable.

### Prioridad 3 - CO2 semantics

Resolver/documentar `co2_upper_ppm` vs `co2_upper_kg` antes de reglas CO/CO2 ratio.

### Prioridad 4 - Phase 3+ two-zone canonico

Necesario a largo plazo para cerrar los VALID_GAP:

- `room.o2` derivado, no fuente independiente;
- combustion vinculada a capa fisica correcta;
- presion/doorway ODE;
- recalibracion completa de casos CFAST afectados.

## Criterios de no-regresion

Antes de commit de motor o validacion:

```powershell
python scripts\simulation\validation_guardrails.py --verbose
python scripts\simulation\audit_physics_coherence_suite.py
python scripts\simulation\audit_ilv_layer_coherence_suite.py --allow-findings
git diff --check
```

Para cierre de fase amplia:

```powershell
powershell -ExecutionPolicy Bypass -File sim\validation\run_full_reference_suite.ps1 -TimeoutSeconds 900
python -m unittest
```

Para cambios solo de documentacion:

```powershell
python scripts\check_docs_links.py
git diff --check
```

## Puntos de entrada vivos

- `docs/HANDOFF_CURRENT_STATE.md`: estado operativo actual.
- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`: checklist fisico maestro.
- `docs/validation/STATUS_VALIDATION.md`: fuente de verdad de validacion legacy.
- `docs/validation/GAPS_INVENTORY.md`: conteo de gaps non-gating.
- `docs/validation/GUARDRAILS_STATUS.md`: estado de guardrails.
- `docs/architecture/PHASE_5A_O2UPPER_SWEEP_RESULTS.md`: descarte per-case Grupo A.
- `docs/architecture/PHASE_3_DOORWAY_PRESSURE_ODE_PLAN.md`: plan pendiente para corridor_chain.
- `docs/architecture/ILV_COMBUSTION_REGIME_PLAN.md`: diseno ILV.
