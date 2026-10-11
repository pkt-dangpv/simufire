# G3-0 — Baseline controlado de combustible y CO (2026-09-27)

Estado: **diagnóstico reproducido; sin cambio de física**. No es una
calibración con NIST/CFAST ni valida rendimientos de un sofá real. Los cinco
controles los genera `scripts/simulation/run_g3_fuel_baseline.py` a partir de
la misma plantilla, ventilación y ajustes del motor. Sólo se altera la fuente
de combustible de la sala 0. Duración: 90 s solicitados, última observación
a 90,1 s, 91 snapshots por caso. El rendimiento de CO de la silla
(`0,004 kg/MJ`) es un **estímulo diagnóstico deliberadamente alto**, no un
valor propuesto para producto.

## Resultado de los cinco controles

| Fuente sala 0 | HRR máximo kW | MJ consumidos | CO generado total kg | CO final en sala kg |
| --- | ---: | ---: | ---: | ---: |
| Sólo carga agregada: 200 MJ, 100 kW | 104,34 | 6,209083 | 0,00127542 | 0,00067196 |
| Sofá 200 MJ, 100 kW; carga de sala reflejada | 104,33 | 6,208994 | 0,00204071 | 0,00117279 |
| Mismo sofá + silla adicional | 104,34 | 6,209362 | **0,00595885** | 0,00337968 |
| Sofá; carga agregada de sala = 0 | 104,33 | 6,208994 | 0,00204071 | 0,00117279 |
| Sala de ignición vacía | 0 | 0 | 0 | 0 |

La silla adicional terminó en estado **`heating`**, `hrr_kw = 0` y
`remaining_fuel_MJ = 200` de 200 iniciales. No ardió en este control. Aun
así, su presencia multiplicó el CO generado por **2,92** frente al sofá
solo, mientras HRR máximo y MJ consumidos variaron menos de 0,01 kW y
0,0004 MJ, respectivamente. El resultado es coherente con
`_resolve_room_co_yield_kg_per_MJ()`: pondera objetos con combustible
remanente aunque no participen en la combustión. **Es una demostración de
atribución incorrecta del rendimiento**, no de que todos los escenarios
actuales tripliquen CO.

La carga agregada reflejada y la carga agregada cero produjeron exactamente
las mismas métricas CSV del sofá en este control. No demuestra que cualquier
discrepancia de energía estancia/objetos sea inocua: aquí las cifras
agregadas positiva y explícita eran iguales; falta variar ambas y seguir
agotamiento y límites de HRR. La sala vacía funcionó como control negativo.

El observable opt-in `--fuel-object-state-snapshot` del runner escribe al
final el estado, HRR y combustible remanente de cada objeto **sin mutarlo**.
También muestra un `room_proxy_0` con estado `flaming` y HRR reflejado cuando
hay objetos explícitos, incluso con `fuel_energy_MJ = 0` en el caso
`sofa_objects_only`. Ese proxy se excluye de las sumas de objetos del motor;
su presencia en un snapshot **no** demuestra combustión doble. Sí es una
ambigüedad de presentación/propiedad que deberá resolverse en G3-1/G3-3.

## Salud, identidad y artefactos

Dos tandas de cinco casos en `runs/g3_fuel_source_baseline_20260927_151701/`
y `runs/g3_fuel_source_baseline_20260927_152031/`, excluidas de Git. Las
cinco corridas de la segunda tanda tuvieron exit 0, sin timeout, cuadros de
error ni procesos Godot residuales, y `process_quiescent = true`. La memoria
libre antes de cada una fue 6,37–6,43 GiB. Antes de alcanzar ese margen, el
gate de 6 GiB impidió iniciar una tanda, sin crear una corrida parcial.

Para los cinco pares, `sim_log.csv` y `events.json` fueron **idénticos byte a
byte** antes/después de añadir el snapshot opt-in. `summary.json` sólo varió
en `output_dir` (ruta del artefacto), y el resto del JSON coincidió. El nuevo
observable no alteró el resultado físico medido. Los hashes de escenarios,
logs de monitor y estados por objeto están en cada carpeta de corrida.

## G3-3 parcial: libro por paso, sólo observación

Una tercera tanda de los mismos cinco controles está en
`runs/g3_fuel_source_baseline_20260927_155129/` (ignorada por Git). La opción
`--fuel-source-ledger` escribe `fuel_source_ledger.jsonl` alrededor de cada
`engine.step()`, sin intervenir en él: deltas de energía consumida, CO
generado e inventariado en sala y combustible remanente/HRR de cada objeto.
La suma de 1.081 pasos por sala reconcilia con el último CSV a `1e-6` en
energía y CO. Los cinco monitores terminaron con exit 0, sin timeout, cuadro
de error ni Godot residual; `process_quiescent = true`. Frente a la tanda
anterior, los cinco pares de `sim_log.csv`, `events.json`,
`co_inventory_trace.jsonl` y snapshots finales son idénticos byte a byte.

| Control | Consumo sala MJ | Consumo objeto explícito MJ | Consumo proxy MJ | CO generado sala kg |
| --- | ---: | ---: | ---: | ---: |
| Sólo sala | 6,209083035 | 0 | 6,209083035 | 0,001275420 |
| Sofá reflejado | 6,208993909 | 6,208992317 | 6,208993909 | 0,002040709 |
| Sofá + silla fría | 6,209362280 | 6,209360689 | 6,209362280 | 0,005958850 |
| Sólo sofá explícito | 6,208993909 | 6,208992317 | 6,208993909 | 0,002040709 |
| Vacío | 0 | 0 | 0 | 0 |

La silla aparece en los **1.081 pasos**: consumo neto 0 MJ, máximo absoluto
de consumo **por paso** 0 MJ y HRR máximo 0 kW. El CO adicional no procede
de combustible consumido por ella. El sofá consume 6,20936 MJ en ese caso,
frente a 6,20899 MJ sin silla; la pequeña diferencia no explica el aumento
de CO de 0,00204 a 0,00596 kg. La función que calcula el rendimiento medio
de CO da peso a la silla con combustible aunque no arda; este control fija
esa atribución como defecto que habrá que corregir en G3-4.

El proxy refleja casi exactamente el consumo de la sala incluso cuando hay
sofá explícito. **No se debe sumar su columna a la de los objetos**: el
modelo lo excluye de las sumas explícitas, y esta traza no demuestra doble
combustión. La pequeña diferencia sala/sofá (≈ `1,59e-6 MJ`) queda abierta
para el presupuesto de energía, no se redondea a una identidad. La columna
diagnóstica `nominal_explicit_co_from_burn_kg` multiplica consumo por yield
base: **no** es CO esperado ni ecuación de conservación porque el motor
modifica el yield por régimen y puede oxidar/retener especies.

Esto **inicia pero no cierra G3-3**: aún faltan masa perdida/pirólisis,
O₂, CO₂, HCN, humo, oxidación, transferencia por zonas y residuo elemental
por paso. No se ha calibrado combustible ni cambiado física.

### Ampliación G3-3 del mismo día: especies y residuos de sala

La tanda `runs/g3_fuel_source_baseline_20260927_181842/` amplía la traza
opt-in al esquema `g3_fuel_source_step_v2`: inventarios de CO₂/HCN y sus
capas superiores, generación declarada por paso, humo, consumo/traslado de
O₂ y masas de gas por zona. Para CO y humo también toma los acumuladores
de transporte y salidas; el residuo se calcula **en cada paso**, no sólo al
final, con las mismas identidades que D1 y S1. En los cinco controles el
máximo absoluto fue `6,48e-19 kg` (CO) y `1,73e-17 kg` (humo). Estos son
cierres de contadores internos, **no** prueba de rendimientos reales.

Los cinco casos terminaron con exit 0, sin timeout, cuadros de error ni
procesos residuales. CSV, eventos, traza anterior de CO y snapshot final
coinciden byte a byte con la tanda `155129`. Las sumas de la nueva traza
reconcilian con el CSV para humo generado y O₂ consumido. `smoke_kg` se
imprime en el CSV con cuatro decimales: su comparación usa medio escalón
de redondeo (`5e-5 kg`), mientras el residuo por paso usa los valores
completos. La primera tentativa (`181729`) paró tras un caso porque usó
erróneamente `1e-6 kg` contra ese campo redondeado; no fue fallo nativo
ni físico y queda preservada como corrida incompleta.

Hay un segundo defecto de atribución visible: la silla que no arde cambia
el **humo generado** de `0,07491757` a `0,06959310 kg` (−7,11 %) sin
consumir MJ ni dar HRR. `_resolve_room_smoke_yield_kg_per_MJ()` pondera
objetos con combustible remanente de modo análogo al CO. No inferir lo mismo
de CO₂ o HCN: sus sumas de producción declarada por paso son prácticamente
iguales entre ambos casos (`0,430322 → 0,430344 kg` de CO₂ y
`0,000204071 → 0,000204079 kg` de HCN); sus inventarios finales pueden
variar por otras rutas. El contador `o2_consumed_kg_total_all` da
`0,773158 kg` frente a `0,386579 kg` de `o2_consumed_fire_kg_total` para
el sofá: son propietarios con semánticas distintas, **no** dos medidas
independientes de la demanda estequiométrica. Queda pendiente el gate O₂.

G3-3 sigue **parcial/NO-GO**: todavía no hay producción atribuida por objeto,
masa perdida, balance elemental C/N/O, oxidación trazada ni presupuesto
CO₂/HCN por zona y por ruta. No se ha tocado `sim/core` ni `sim/fire`.

## Gate siguiente

1. No corregir aún la química sin cerrar el dueño de la carga y el libro
   contable por objeto. Fijar este control como regresión diagnóstica: al
   adoptar la nueva fuente, la silla que no arde **no** debe alterar el CO
   producido por el sofá, con la misma fuente/HRR/ventilación.
2. Medir el caso de totales de estancia/objetos **desiguales** en una
   duración que ejercite el límite energético, separando `FireModel` del
   inventario explícito. No inferir que la coincidencia del caso espejo lo
   resuelve.
3. Clasificar procedencia de las 23 diferencias y las 71 salas sin objetos;
   no convertir diferencias en «contenido oculto» ni rellenar HCN/CO₂ con
   números inventados. Ver [inventario estático](G3_FUEL_SOURCE_OWNERSHIP_AUDIT_2026-09-27.md)
   y [subplan integral](../planning/G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md).
