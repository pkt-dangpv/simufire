# Hoja de ruta activa de SimuFire

Fecha: 2026-06-19
Estado: fuente de verdad para continuar trabajo
Alcance: validacion CFAST pendiente, hotfix de aperturas/temperatura FP e ILV.

## Regla principal

No hacer cambios por hacer. Cada cambio debe estar ligado a una de estas tres lineas:

1. Reducir fallos reales de validacion o documentar por que son estructurales.
2. Corregir saltos visibles/fisicos derivados de aperturas exteriores y HUD FP.
3. Preparar el modelo ILV/infraventilado/ventilado sin romper el motor actual.

Antes de tocar motor:

- ejecutar o revisar `python scripts\simulation\validation_guardrails.py --verbose`;
- confirmar `git status --short --branch`;
- aislar el caso que se va a tocar;
- no modificar tolerancias ni reports para esconder fallos.

## Estado actual conocido

- Rama esperada: `main`.
- Ultimo plan ILV documentado: `docs/architecture/ILV_COMBUSTION_REGIME_PLAN.md`.
- Handoff vigente: `docs/HANDOFF_CURRENT_STATE.md`.
- Estado de validacion documentado: `docs/validation/STATUS_VALIDATION.md`.
- Baseline reciente: 335/350 required PASS, 15 required FAIL.
- Commit de validacion reciente: `9dfc74d feat(validation): reduce corridor chain thermal failures to 2`.
- Commit documental reciente: `31957c0 docs(validation): classify multifuel RMSE as venting topology gap`.

## Actualizacion 2026-06-19

Trabajo completado:

- Grupo A `cfast_r0_window_360`: diagnosticado como gap Phase 2.
- Grupo B `cfast_slow_growth_sealed`: diagnosticado como gap Phase 2.
- Grupo C `cfast_corridor_chain`: t300 resuelto con `doorway_thermal_counterflow_gain=0.25`; t180/t600 siguen como gaps estructurales M3/Phase 2.
- Grupo D `cfast_bedroom_closed_door`: diagnosticado como gap Phase 2; corregida atribucion anterior desde ghanekar.
- Grupo E:
  - `cfast_2r_r0_rmse_temp_upper_c`: C3/RMSE acumulado.
  - `cfast_hvac_t300_o2`: C2/Phase 2C.
  - `cfast_multifuel_rmse_temp_upper_c`: C3 topologia vented/sealed confirmada.

Reglas actuales:

- No perseguir los 15 fallos con cambios de tolerancia, reports o reclasificacion.
- No tocar `sim/core` sin autorizacion explicita.
- No iniciar ILV todavia salvo decision expresa.
- Cualquier experimento per-case debe aislar un caso, correrlo fresco y comparar contra `STATUS_VALIDATION.md`.

## Donde se dejo antes del hotfix

La linea activa era validacion CFAST/two-zone, no ILV.

Secuencia relevante:

- Phase 5 M1/M2: infraestructura de trazado/consumo O2 upper, no promovida globalmente.
- Phase 5 M3/M3b: intercambio termico/O2 por puertas, parcialmente util pero insuficiente.
- Phase 6: infraestructura de `canonical_doorway_exchange_enabled`.
- Phase 7: fix de conservacion de energia en Part B (`lower_energy_kj`).
- Phase 8: auditoria global M1/M2; activacion global revertida por regresiones. Se dejo `canonical_o2_upper_updated` como infraestructura futura.

Conclusion de esa linea: el problema no era un parametro suelto, sino el acoplamiento estructural entre consumo de O2, capas, puertas y calor. La siguiente fase debe elegir un grupo de fallos y resolverlo con cambios pequenos y medidos.

## Hotfix ya aplicado

Commit de referencia: `69d6b55 feat(hotfix): exterior opening transition smoothing`.

Que arreglo:

- Suavizado `open_fraction_smooth` para aperturas exteriores.
- Evita saltos instantaneos en presion, O2 y humo al abrir/cerrar ventanas o puertas exteriores.
- No resolvio por completo los saltos de temperatura percibidos en FP.

Pendiente del hotfix:

- Algunas rutas termicas pueden seguir usando `open_fraction` directo.
- El HUD FP muestra temperatura directa cada 0.05 s, sin suavizado visual.
- Si la interfaz de capa caliente cruza la altura del usuario, el HUD puede saltar entre temperatura baja/mezclada/alta.

Diagnostico recomendado antes de tocar comportamiento:

- En la sala FP registrar `temp_at_1_8m_c`, `temp_upper_c`, `temp_lower_c`, `thermal_layer_m`, `open_fraction`, `open_fraction_smooth`.
- Separar dos decisiones:
  - fisica: usar apertura suavizada tambien en rutas termicas si procede;
  - interfaz: suavizar el numero mostrado en HUD sin alterar la simulacion.

## ILV / infraventilado / ventilado

Problema detectado: cuando el incendio entra en ILV puede apagarse directamente, pero en condiciones reales deberia poder pasar a estado latente si quedan temperatura, combustible y productos no quemados.

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

## Prioridad 1 - Reconstruir baseline actual

Objetivo: saber exactamente que falla hoy antes de arreglar.

Pasos:

1. Ejecutar `python scripts\simulation\validation_guardrails.py --verbose`.
2. Guardar salida en artefacto local ignorado, no versionado.
3. Comparar con `docs/validation/STATUS_VALIDATION.md`.
4. Si el conteo no es 15/350, actualizar primero el diagnostico antes de tocar motor.

Criterio de salida:

- lista actual de fallos confirmada;
- ningun cambio de codigo;
- decision del primer grupo a atacar.

## Prioridad 2 - Validacion CFAST: estado de grupos

Los grupos A-E ya fueron diagnosticados. No repetir diagnostico salvo que una corrida fresca cambie el baseline.

### 2.1 Grupo A - `cfast_r0_window_360` O2

Estado:

- `cfast_t240_o2_depleted`
- `cfast_t350_o2`
- `cfast_t360_o2`

Veredicto: gap Phase 2. No hay fix per-case de bajo riesgo. No tocar sin arquitectura two-zone.

### 2.2 Grupo B - `cfast_slow_growth_sealed` temperatura upper

Fallos conocidos:

- `cfast_slow_t480_temp_upper_c`
- `cfast_slow_t600_temp_upper_c`

Veredicto:

- Gap Phase 2 confirmado.
- Bajar `chi_rad` mejora temperatura pero rompe O2.
- No hay valor unico de `chi_rad` que cierre ambos.

### 2.3 Grupo C - `cfast_corridor_chain` curva termica

Estado:

- `cfast_chain_r0_t180_temp_upper_c`
- `cfast_chain_r0_t600_temp_upper_c`

Veredicto:

- `cfast_chain_r0_t300_temp_upper_c` resuelto con `doorway_thermal_counterflow_gain=0.25`.
- t180/t600 siguen como gaps estructurales M3/Phase 2.
- No seguir ajustando gain para perseguir t180/t600.

### 2.4 Grupo D - `cfast_bedroom_closed_door` O2

Estado:

- `cfast_bed_o2_*` x5.

Veredicto: gap Phase 2. La atribucion anterior a ghanekar era incorrecta; el caso real es `cfast_bedroom_closed_door`.

### 2.5 Grupo E - HVAC y RMSE termicos

Estado:

- `cfast_hvac_t300_o2`
- `cfast_2r_r0_rmse_temp_upper_c`
- `cfast_multifuel_rmse_temp_upper_c`

Veredicto:

- HVAC: C2/Phase 2C.
- two_room RMSE: C3/RMSE acumulado.
- multifuel RMSE: C3 topologia vented/sealed.

Trabajo futuro opcional:

- Experimento separado en `cfast_multi_fuel_couch_tv` con apertura exterior parcial/door-to-outside, verificando temperatura, HRR y O2 de todo el caso.
- Diagnostico por etapas de `cfast_two_room_door_open`.

## Prioridad 3 - Hotfix temperatura FP

Objetivo: eliminar saltos rapidos de temperatura visibles sin ocultar un fallo fisico real.

Fase 3.1 - Diagnostico sin cambios:

- anadir logging temporal o usar debug existente;
- capturar sala, postura, temperatura mostrada, temperaturas upper/lower y altura de capa;
- reproducir con ventana cerrando/abriendo.

Fase 3.2 - Decision:

- Si el salto viene de rutas termicas con `open_fraction` directo, corregir fisica para usar `open_fraction_smooth` donde corresponda.
- Si el salto viene de cruce de capa cerca de altura FP, anadir suavizado solo de display.
- Si ambos ocurren, hacer primero fisica y despues HUD.

Fase 3.3 - Verificacion:

- comparar antes/despues en el mismo escenario;
- revisar que validacion CFAST no empeora;
- revisar visualmente FP.

## Prioridad 4 - ILV diagnostico

Objetivo: preparar ILV sin romper validaciones actuales.

Fase 4.1 - Reproducir apagado directo:

- crear o elegir escenario que entra en baja ventilacion;
- registrar O2, HRR real/target, pirolisis, smolder, energia retenida y temperatura.

Fase 4.2 - Clasificador no invasivo:

- anadir clasificador de regimen sin cambiar HRR ni gases;
- registrar estado por sala cada segundo;
- validar que no parpadea entre estados.

Fase 4.3 - Ajustar latencia:

- revisar `_can_sustain_latent_fire`;
- permitir `ILV_LATENT` cuando no hay llama sostenida pero quedan calor, combustible y smolder/pirolisis;
- conservar extincion si baja temperatura o se agota combustible.

Fase 4.4 - Reventilacion:

- usar `retained_unburned_MJ` y evento de apertura para crecimiento inducido;
- acotar energia y duracion;
- backdraft solo si se cumplen condiciones, nunca automatico.

## Prioridad 5 - Documentacion y sync entre maquinas

Mantener vivos solo estos puntos de entrada:

- `docs/planning/MASTER_ROADMAP_CURRENT.md`: esta hoja de ruta.
- `docs/HANDOFF_CURRENT_STATE.md`: estado operativo de sincronizacion.
- `docs/validation/STATUS_VALIDATION.md`: detalle historico y tecnico de validacion.
- `docs/architecture/ILV_COMBUSTION_REGIME_PLAN.md`: diseno ILV.
- `docs/INDEX.md`: indice.

Los planes antiguos cerrados no deben usarse para decidir trabajo nuevo.

## Criterios de no-regresion

Antes de commit de motor:

- `python scripts\simulation\validation_guardrails.py --verbose`
- `python scripts\check_product.py`
- `python scripts\check_docs_links.py`
- `git diff --check`

Para cambios solo de documentacion:

- `python scripts\check_docs_links.py`
- `git diff --check`

## Decision inmediata recomendada

Siguiente sesion de trabajo:

1. Confirmar `git status --short --branch` y baseline 15/350.
2. Elegir una linea:
   - producto/UX: hotfix FP temperatura;
   - validacion acotada: experimento multifuel vented/sealed;
   - diagnostico largo: two_room RMSE;
   - arquitectura: Phase 2/Phase 2C solo con plan explicito.
3. No tocar motor ni ILV sin decision expresa.

ILV queda preparado, pero no debe adelantarse a la validacion abierta salvo que el usuario lo priorice expresamente.
