# G3 — procedencia reproducible de la referencia

Fecha: 2026-09-29. Alcance: metadatos de `reference_checks.json`, **no**
física del incendio ni resultados de los 532 checks.

## Causa y demostración

El informe anterior (`35d0f978`) se generó en el checkout principal. Sus
entradas de texto estaban físicamente en CRLF, aunque `.gitattributes`
especifica `* text=auto eol=lf`. En el worktree G3 están en LF. El validador
calculaba `bytes` y SHA-256 sobre los bytes físicos y escribía siete rutas
absolutas en `references`. Por ello, dos checkouts del mismo contenido
produjeron informes diferentes.

Comparación estructurada del informe anterior y el generado en G3 antes de
la corrección: 532 checks; cero cambios de nombre, métrica o veredicto; 38
artefactos únicos con distinta longitud/hash; siete rutas absolutas con
otra raíz. Los 38 artefactos son 28 JSON de caso, cinco CSV de CFAST y cinco
entradas `.in` de CFAST. Para **cada uno**, se verificó:

1. SHA-256 y longitud del archivo actual = registro LF del informe G3.
2. Al sustituir exclusivamente cada LF por CRLF, SHA-256 y longitud =
   registro del informe `35d0f978`.
3. La diferencia de longitud = número exacto de saltos de línea.

El test `test_historical_38_artifact_changes_are_exactly_lf_crlf` comprueba
las 38 filas de forma individual y falla indicando la ruta concreta. El
test no cambia los archivos. Las rutas afectadas son:

| Tipo | Artefactos (nombre bajo `sim/validation/`) |
| --- | --- |
| JSON | `cases/bv031_t2_growth_pure.json`, `cases/c_balance_high_phi.json`, `cases/cfast_two_floor_stairwell.json`, `cases/co_oxidation_post_flashover.json`, `cases/compact_apartment_smoke.json`, `cases/conservation_transport.json`, `cases/energy_budget_living_room.json`, `cases/g1_gie_confinement_attack.json`, `cases/g3_gie_ppv_post_knockdown.json`, `cases/glass_break_window_spike.json`, `cases/kitchen_grease_pool_fire.json`, `cases/mediterraneo_concrete_wall_conduction.json`, `cases/piso_mediterraneo_smoke.json`, `cases/ppv_attack_pressurized.json`, `cases/pu_sofa_fec_incapacitation.json`, `cases/pvc_curtain_hcl_release.json`, `cases/ranch_family_house_smoke.json`, `cases/ranch_radiation_target_ignition.json`, `cases/row_house_ground_floor_smoke.json`, `cases/tc_array_iso9705.json`, `cases/three_bed_apartment_smoke.json`, `cases/two_bed_apartment_smoke.json`, `cases/uk_bungalow_smoke.json`, `cases/v4_co_remote_rooms.json`, `cases/v5_ventilation_hrr_spike.json`, `cases/v6_spread_to_hallway.json`, `cases/v8_suppression_reburn.json`, `cases/wind_assisted_exterior_spread.json` |
| CSV | `cfast/cfast_fast_growth_closed_compartments.csv`, `cfast/cfast_pool_fire_open_compartments.csv`, `cfast/cfast_suppression_water_compartments.csv`, `cfast/cfast_two_floor_stairwell_compartments.csv`, `cfast/cfast_window_break_t180_compartments.csv` |
| IN | `cfast/cfast_fast_growth_closed.in`, `cfast/cfast_pool_fire_open.in`, `cfast/cfast_suppression_water.in`, `cfast/cfast_two_floor_stairwell.in`, `cfast/cfast_window_break_t180.in` |

## Contrato corregido

`_artifact_record` registra longitud y SHA-256 de los bytes **canónicos LF**
para `.csv`, `.in`, `.json` y `.log`. Para `.pdf` y demás formatos binarios
conserva los bytes exactos. Los paths de `references` son relativos al
repositorio y usan `/`. Esta normalización solo elimina pares CRLF; no
redondea números, transforma codificación ni altera los archivos fuente.

Pruebas negativas: un cambio de `1,2` a `1,3` en un CSV cambia el hash;
un PDF mantiene hash byte a byte. Las pruebas existentes de disposiciones
de gaps y mutaciones siguen exigiendo igualdad de artefactos y fallan ante
contenido alterado. El formato conserva los mismos campos `path`, `bytes`
y `sha256`; su dominio de bytes queda fijado aquí.

La actualización del informe versionado produce un **cambio de convención
único**: las 38 parejas longitud/hash pasan de CRLF físico a LF canónico,
y las siete rutas absolutas se vuelven relativas. No debe describirse como
«solo `generated_at`». Para afirmar identidad de resultados hay que
comparar explícitamente los 532 checks y las 346 decisiones requeridas.

Verificación focalizada: 54 tests PASS para portabilidad/P1R5/P1R8; la
selección G3 y procedencia más amplia dio 156 passed, 5 skipped. El
validador sobre las salidas ya existentes volvió a informar 346/346
required PASS y 78 gaps, sin lanzar Godot. Los 532 checks conservan métricas
y veredictos; el diff del informe sigue siendo 432 líneas añadidas y 432
eliminadas por la migración de metadatos. Esto **no sustituye** la próxima
corrida de referencia completa si se modifica la física en Gate B.

Estado global de esta sesión: producto 167/167 y guardarraíles ALL PASS,
pero pytest global tuvo 26 fallos de infraestructura por cuadros nativos
de error de Godot en el lanzador monitorizado (3033 passed, 35 skipped,
2 xfailed). Por tanto, **no se considera cerrado el gate de integración**
ni se prepara commit. Una prueba aislada del mismo lanzador reprodujo el
cuadro en 3,16 s con 7,14 GiB libres y `TEMP/TMP` exclusivos; producto
167/167 pasó usando la ruta de consola. La causa técnica del fallo nativo
no está demostrada. No quedan procesos Godot.
