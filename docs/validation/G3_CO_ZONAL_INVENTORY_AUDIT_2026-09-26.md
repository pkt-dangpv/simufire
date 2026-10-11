# G3 — contraste del inventario zonal de CO (2026-09-26)

Estado: **NO-GO para activar `fed_co_zonal_enabled` en producto**. Este
diagnóstico no cambia física, casos, baselines, tolerancias ni los 78 gaps.

## Método y equivalencia

Se añadió al ejecutor de escenarios `--co-inventory-trace`: solo bajo esta
opción emite `co_inventory_trace.jsonl` en el directorio de la corrida. Lee
`co_kg`, `co_upper_kg`, masas de gas y las concentraciones calculadas por el
motor después de cada paso; muestrea con `log_interval_s`. No escribe estado
físico. Para estos casos se pasó explícitamente `--fire-o2-mode upper`, porque
el runner oficial consume `validation_fire_o2_mode=upper` y el ejecutor
genérico no lo heredaba. Sin esa equivalencia, el HRR del pasillo difería y
la comparación con CFAST habría sido inválida.

Se ejecutaron bajo monitor Windows `cfast_single_room_closed`,
`cfast_bedroom_closed_door` y `cfast_two_room_door_open`. Los tres Godot
terminaron con código 0, sin timeout, cuadros de error ni procesos residuales.
En cada caso, **todas las líneas físicas** del log coinciden con el informe
oficial versionado; el ejecutor genérico solo agrega su evento final. En el
control de dos salas con/sin la traza, `sim_log.csv`, `sim_log.txt` y
`events.json` son idénticos byte a byte; `summary.json` solo difiere por
`output_dir`.

Regresión tras la instrumentación: 13 pruebas focalizadas PASS,
`check_product.py` 167/167 y suite global 3 012 passed, 9 skipped,
2 xfailed, 42 subtests. El primer intento global detectó que la traza leía
un interruptor reservado al adaptador de presión; se eliminó ese campo
diagnóstico sin relajar el guardarraíl, y la segunda pasada global quedó
verde. La suite oficial de referencia no se regeneró: ni `sim/core`, ni
`CaseRunner`, ni casos o baselines cambiaron; `reference_checks.json` mantiene
346/346 required y 78 gaps del commit anterior.

Los 1 278 snapshots de las seis salas por caso mantienen
`0 ≤ co_upper_kg ≤ co_kg`; ninguno requirió corregir una masa zonal inválida.
En estos tres casos con red de presión apagada, la masa inferior almacenada y
la masa geométrica del denominador del candidato concuerdan hasta un error
relativo máximo de 2,1×10⁻⁸. Eso **no** verifica el denominador con la red
de presión activada.

La comparación con CFAST usa `LLCO_n`/`ULCO_n` de los CSV originales del
repositorio, convertidos de porcentaje molar a ppm (×10 000). Es una
comparación entre modelos con sus escenarios emparejados, **no datos
experimentales de exposición humana**.

## Resultados decisivos

| Caso y zona | t (s) | CO bajo SimuFire por masa (ppm) | CO bajo CFAST (ppm) | CO alto SimuFire / CFAST (ppm) |
|---|---:|---:|---:|---:|
| Una sala cerrada, fuego | 240 | 0 | 0 | 833 / 619 |
| Dormitorio cerrado, fuego | 480 | 0 | 0 | 12 470 / 4 224 |
| Dos salas, fuego | 240 | ≈0 | 360 | 1 312 / 667 |
| Dos salas, fuego | 480 | 0,0058 | 579 | 1 616 / 617 |
| Dos salas, pasillo | 240 | 0,0026 | 0 | 776 / 491 |
| Dos salas, pasillo | 360 | 0,576 | 0 | 1 088 / 767 |

En la sala del fuego del caso de dos salas, a 240 s la interfaz de CFAST está
a 0,42 m y la de SimuFire a 1,82 m; **esa comparación no aísla transporte de
CO**. A 480 s están a 1,78 y 1,74 m, respectivamente: aun con geometría de
capa similar, CFAST tiene ~579 ppm en la zona baja y SimuFire ~0,006 ppm. Es
una discrepancia zonal real para ese caso, aunque no atribuye por sí sola la
causa a mezcla intercapas, generación, transferencia por puerta o a una
combinación. También hay discrepancias de CO alto; ajustar solo la muestra de
FED no las corrige.

## Defecto del comparador existente

Los checks `cfast_2r_hall_t240_co_lower_ppm` y
`cfast_2r_hall_t360_co_lower_ppm` de
`scripts/simulation/validate_reference_cases.py` seleccionan
`sim_field="co_avg_ppm"` aunque su nombre y nota dicen «lower-zone CO».
El agregado actual informa 119 y 255 ppm de **media de sala** contra 0 ppm
de CFAST; el inventario inferior trazado da 0,0026 y 0,576 ppm. Los dos
fallos registrados **no demuestran el gap de CO bajo que dicen demostrar**.
Tampoco se debe sustituir sin más el campo por el `co_lower_ppm` legacy: ese
export incluye un factor heurístico capaz de borrar masa no nula. Los dos
checks permanecen sin modificar en esta fase para no rebajar ni recontar el
corpus sin un contrato de observable zonal independiente y una nueva suite
completa.

## Decisión y siguiente gate

1. Mantener `fed_co_zonal_enabled=false` en producto. En la sala del fuego el
   inventario bajo podría subestimar de forma extrema la dosis bajo la capa;
   en el pasillo, usar la media podría sobreestimarla. Un único cambio de
   selector no resuelve ambas cosas.
2. Definir un observable de CO bajo por masa, sin `strat`, para el runner de
   referencia; hacer que el comparador lo consuma y renombrar o recalificar
   explícitamente los dos checks mal rotulados. No alterar los 78 gaps ni
   sus disposiciones sin la regeneración oficial y revisión de procedencia.
3. Diagnosticar propietarios de CO `upper→lower` y contrastar al menos tres
   casos con CO bajo no nulo de CFAST (dos salas, post-flashover ventado y
   corredor), con tiempos e interfaces comparables. `phase2f_co_interlayer_mixing`
   ya existe apagado; su existencia no autoriza ajustar una tasa a un punto.
4. Solo después reexaminar el selector FED, la incertidumbre de ocupantes a
   0,9/1,5/1,8 m y la presentación de SVV.

## Ampliación del 27-09: comparador reproducible y dos casos más

El comparador diagnóstico
[`audit_g3_co_inventory_against_cfast.py`](../../scripts/simulation/audit_g3_co_inventory_against_cfast.py)
lee la traza opt-in y los CSV CFAST originales, exige columnas `LLCO`/`ULCO`
de la sala correspondiente, comprueba duplicados, finitud, cotas de los
inventarios y recalcula las ppm bajas a partir de la masa cuando existe zona
superior. Emite hashes SHA-256 de ambas fuentes y diferencias **sin tolerancia
de aprobado**. Si `upper_gas_kg < 0,1`, el motor devuelve la media de sala en
lugar de una concentración inferior; el informe etiqueta ese punto como
`room_mean_no_upper_zone`, no como medida zonal. La traza de 26-09 no trae el
volumen para recalcular independientemente esa rama, así que el comparador
solo confirma que coincide con el exportador legacy.

Se añadieron corridas equivalentes de `cfast_post_flashover_vented` (O₂ de
fuego legacy) y `cfast_corridor_chain` (O₂ upper), secuenciales y bajo el
monitor de errores nativos. Ambas terminaron con exit 0, sin timeout, cuadro
de error ni Godot residual. Sus 287 y 427 líneas físicas, respectivamente,
coinciden con los logs oficiales versionados. En conjunto, el comparador
procesa **5 casos, 1 890 snapshots de sala y 28 puntos**. Cinco pruebas
sintéticas verifican el mapeo de sala y que inventarios o columnas inválidos
no produzcan un resultado silencioso.

| Caso y zona | t (s) | CO bajo SF por masa / CFAST (ppm) | Interfaz SF / CFAST (m) |
|---|---:|---:|---:|
| Post-flashover ventado, fuego | 300 | ≈0 / 101 | 1,99 / 0,80 |
| Corredor, fuego | 590 | 0,021 / 439 | 1,48 / 0,81 |
| Corredor, pasillo | 590 | ≈0 / 425 | 0,94 / 0,57 |
| Dos salas, fuego | 480 | 0,0058 / 579 | 1,74 / 1,78 |

El patrón de CO bajo casi nulo se repite en **tres escenarios que sí tienen
LLCO no nulo en CFAST**; ya no depende de un caso aislado. Salvo el último
punto, las alturas de interfaz difieren mucho, por lo que esas cifras no
separan error geométrico de transporte intercapas. Tampoco prueban que CFAST
sea una medición experimental. En los puntos indicados, la fracción de CO
almacenada abajo es aproximadamente 0, 0,000035, 0 y 0,000013 del total,
respectivamente. El siguiente experimento debe atribuir la escasez de CO
inferior a propietarios concretos de generación, puerta, mezcla y proyección
antes de modificar una ley de transporte.

**Pendiente:** el comparador diagnóstico no sustituye los checks oficiales
mal rotulados ni modifica `reference_checks.json` o las 78 disposiciones.
Falta un observable oficial de CO inferior por masa y una regeneración
completa antes de recalificar esos dos checks. `fed_co_zonal_enabled` sigue
apagado y la evaluación FED/SVV sigue abierta.
