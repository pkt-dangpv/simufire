# Hoja de ruta activa de SimuFire

Fecha: 2026-06-18
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
- Baseline reciente: 334/350 required PASS, 16 required FAIL.

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
4. Si el conteo no es 16/350, actualizar primero el diagnostico antes de tocar motor.

Criterio de salida:

- lista actual de fallos confirmada;
- ningun cambio de codigo;
- decision del primer grupo a atacar.

## Prioridad 2 - Validacion CFAST: atacar por grupos

Orden recomendado:

### 2.1 Grupo A - `cfast_r0_window_360` O2

Fallos conocidos:

- `cfast_t240_o2_depleted`
- `cfast_t350_o2`
- `cfast_t360_o2`

Por que primero:

- Conecta directamente con Phase 8, hotfix de ventanas y limitacion por ventilacion.
- Es buen puente hacia ILV sin implementar ILV todavia.

Analisis requerido:

- revisar consumo O2 upper/lower;
- verificar si el hotfix cambia timing de ventilacion;
- comparar `open_fraction` vs `open_fraction_smooth`;
- comprobar si el fuego esta usando O2 promedio cuando deberia limitarse por capa.

No hacer:

- no ampliar tolerancias;
- no activar M1/M2 global sin suite completa;
- no meter ILV aqui salvo diagnostico.

### 2.2 Grupo B - `cfast_slow_growth_sealed` temperatura upper

Fallos conocidos:

- `cfast_slow_t480_temp_upper_c`
- `cfast_slow_t600_temp_upper_c`

Diagnostico ya documentado:

- bajar `chi_rad` mejora temperatura pero rompe O2;
- no hay valor unico de `chi_rad` que cierre ambos;
- probable gap estructural por consumo O2/capa y captura convectiva.

Trabajo real:

- decidir si se acepta como gap estructural o se ataca con arquitectura two-zone;
- no resolver con parametro de radiacion aislado.

### 2.3 Grupo C - `cfast_corridor_chain` curva termica

Fallos conocidos:

- `cfast_chain_r0_t180_temp_upper_c`
- `cfast_chain_r0_t300_temp_upper_c`
- `cfast_chain_r0_t600_temp_upper_c`

Diagnostico:

- O2 mejoro con Phase 4C/Phase 7;
- la curva termica sigue mal: pico temprano y caida posterior;
- M3 energy-only no basta.

Trabajo real:

- evaluar si el problema es intercambio puerta masa+energia o throttle por O2 upper;
- evitar gains unicos que arreglan t180 y rompen t300/t600.

### 2.4 Grupo D - Ghanekar bedroom/kitchen

Fallos relacionados:

- O2 bedroom hallway en varios tiempos.
- origin/kitchen/far hall si siguen en el reporte actual.
- CO/FED timings si reaparecen por corrida fresca.

Trabajo real:

- tratar como validacion empirica, no CFAST pura;
- separar transporte de gases, produccion CO y flashover local;
- no calibrar CO global para arreglar un caso.

### 2.5 Grupo E - HVAC y RMSE termicos

Fallos conocidos:

- `cfast_hvac_t300_o2`
- RMSE temp upper two-room/multifuel si siguen activos.

Trabajo real:

- confirmar si son estructurales o si hay regresion por stale logs;
- no priorizar antes de Grupo A salvo que el guardrail indique regresion nueva.

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

1. Ejecutar baseline verbose.
2. Elegir Grupo A (`cfast_r0_window_360` O2).
3. Hacer diagnostico sin tocar motor.
4. Solo si el diagnostico es claro, aplicar un cambio pequeno.

ILV queda preparado, pero no debe adelantarse a la validacion abierta salvo que el usuario lo priorice expresamente.
