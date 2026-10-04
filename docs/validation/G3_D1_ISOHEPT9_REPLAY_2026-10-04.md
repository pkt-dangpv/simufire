# D1: replay numérico de masa ISOHept9, 0-500 s

Fecha: 2026-10-04. Rama `codex/g3-fed-co-zonal-shareable`, HEAD `cbab7b05`.
Estado: **cerrado técnicamente, cadena R2-1 completa en verde**.
No integrado ni activado. Sin commit/push.

## Alcance y contrato

Sigue el [gate y criterios predeclarados](G3_D1_ISOHEPT9_BENCHMARK_GATE_2026-10-03.md).
El [constructor offline](../../scripts/simulation/build_g3_measured_mass_replay.py)
verifica el manifiesto/hash original y conserva exactamente los 101 nodos
medidos de 0 a 500 s. No usa HRR, HOC ni O₂. El dato original completo
no se modifica ni recorta. Atribución/licencia NIST permanece con el CSV.

Para cada intervalo `[t_k,t_k+1)`, tasa = `(Mass1_k - Mass1_k+1) / dt`.
Es una media constante por intervalo; no una tasa instantánea medida.
La masa reconstruida entre nodos es lineal por **convención declarada**,
no una ley de evaporación. Nodo final a 500 s con tasa cero, sin intervalo
posterior. No extrapolación ni supuesto de extinción o masa agotada.

`PrescribedFuelReleaseModel.gd` añade exclusivamente la pareja:
`quantity=measured_reservoir_depletion` y
`interpolation=piecewise_constant_left`. Versión de fingerprint nueva
`prescribed_measured_depletion_v1`. El modo anterior conserva
`modeled_component_emission`, `piecewise_linear` y su versión v1.
Una pareja cruzada/incompatible falla; la masa medida no puede etiquetarse
como emisión de componente. Se mantienen unidades kg/s y errores explícitos.

Una sola autoridad de progreso y de integración en el proveedor, sin
segundo solver ni fórmula de combustión. Confirmación recomputada desde
el cursor actual; contabiliza aceptación/rechazo, no reemite el rechazo.
Fingerprint cubre programa/versión, no aprueba composición ni material.
El caller sigue obligado a restaurar/confirmar reservorio y cursor juntos.
La fixture hace ese commit local: **no** demuestra el aplicador del motor.

La [fixture JSON](../../tests/fixtures/g3_isohept9_measured_replay.json) no
es un `g3_mass_material_profile_v1`: falta deliberadamente material/energía
y usa masa de reservorio líquido, no inventario sólido. No se conecta a
`FuelMassBudgetModel`, no se transforma U ni se produce CO/HCN/calor.
Todas las autorizaciones del artefacto son false.

## Comprobaciones reales

- Fixture GDScript: **2459 checks**, error máximo `1.06581410364015e-14 kg`.
- Cuatro campañas: nodos medidos (100 pasos), subdivisión a 1,25 s (400),
  pasos irregulares que cruzan fronteras y consulta única 0-500 s.
  Conservan 19,359537 kg programados y 0,306292 kg restantes.
- Repetición/preview sin mutación, reinicio de snapshot conjunto,
  negativa de disponibilidad sintética sin cola, fingerprint, unidades,
  dominio, nodo terminal e intervalo omitido.
- El cap con aceptación 0,1 kg es **control sintético de rechazo**, no
  historial coherente del ensayo ni cantidad real emitida.
- Regresión focal conjunta: **110 passed**, exit 0. Incluye las tres
  fixtures reales del núcleo, proveedor sintético y replay.
- Modo lineal: trace API completo anterior/actual **byte idéntico**,
  con previews, acknowledgements, cursores y fingerprints, aceptación 50 %
  sintética en ocho intervalos. SHA del trace
  `20ef5dc3469e90dbb46db9828a159d004e34adf658855f4ecc2f16adbb5c2dfa`.
  Evidencia `runs/g3_linear_identity_20261004_001117/`.
- Once mutantes de replay y once históricos válidos detectados, controles
  PASS, originales intactos. No errores de sintaxis/runtime contados como
  detección. El arnés histórico solo adapta los anchors a la firma nueva
  de `_integral`, conserva los once defectos y sus oráculos.

Evidencia del replay con la fixture final:
`runs/g3_d1_measured_mutations_20261004_012742/`, repetida tras adaptar
la bandera de fallo a la convención del arnés global.
Evidencia histórica final: `runs/g3_d1_prescribed_mutations_20261004_001123/`.
No se cuenta precisión numérica como incertidumbre experimental.

## Cadena de cierre ejecutada

Referencia, producto y global se ejecutaron secuencialmente, sin cambiar
`sim/` desde el comienzo de la referencia, mediante los monitores existentes.

| Verificación | Resultado |
|---|---|
| Referencia monitorizada | 18/18 limpios, exit 0; comparador y guardarraíles exit 0 |
| Referencia científica | 346/346 required PASS, 78 gaps sin cambio |
| Identidad de casos | 18/18 informes byte idénticos a la copia previa externa |
| Resumen | Solo `generated_at`: 2026-10-03T17:00:57Z → 2026-10-03T23:02:13Z |
| Producto | 168/168 PASS; 81 solicitudes de lanzamiento limpias |
| Auditoría de fixtures + focalizada final | 415 passed, 8 skipped, exit 0 |
| Mutantes finales de replay | 11/11 válidos detectados; control PASS, originales intactos |
| Global final | 3426 passed, 39 skipped, 2 xfailed, 42 subtests passed; exit 0, 510,48 s |

La primera global **no pasó**: 3425 passed y un fallo de la auditoría estática
de fixtures, que exige `_failed`. La fixture ya registraba `_failures` y
salía con código 1; los mutantes lo demostraban. Se añadió la bandera y se
usó para guardar la salida, siguiendo el patrón histórico sin relajar el
auditor. Solo cambió la fixture bajo `tests/`, no `sim/`. Se repitieron su
auditoría, focalizada, once mutantes y la global completa con temporal nuevo.
Producto no invoca esa fixture; su resultado anterior permanece aplicable.

Referencia: `runs/reference_suite_monitored_20261004_001523/`.
Temporales/basetemp y copia previa:
`C:/Users/dangp/AppData/Local/Temp/simufire_hept9_replay_20261004_01/`.
Producto: `product.health.jsonl` en ese directorio, sin timeouts, cuadros,
fallos de infraestructura ni residuos. Memoria antes de producto 6,86 GiB,
antes de global final 6,98 GiB. APPDATA/TEMP/TMP del padre externos; el
arnés histórico `tests/godot_runtime_launcher.py` sigue forzando APPDATA a
`runs/godot_test_appdata` para sus fixtures y verifica la salud directamente.
No se afirma que todos los hijos usen APPDATA externo o ese log de producto.

SHA-256 del proveedor final:
`89a8c5ad8c663c9f417e23381c6cbf0d2c07bc5c56f5ad01ff7dc1ed6e0cd9fc`.
Núcleo intacto:
`783c13166fe9e263b470dd76b736114a6ee9e909dae27dc62ca4f6f5febcde82`.
No se repiten ni atribuyen los diez mutantes del núcleo de la fase anterior.
Resumen de ejecución: `runs/g3_d1_replay_closure_20261004/result.json`.
Guardarraíles finales ALL PASS, R2-1 incluido. Enlaces de los cuatro
documentos actualizados y `git diff --check` PASS; cero procesos Godot
al terminar. La compilación de los módulos nuevos se demuestra por las
fixtures reales; el checker de estilo de producto cubre el GDScript visual.

## Decisión científica y siguiente gate

GO técnico **solo al replay condicionado a masa medida**. No es una
predicción ni comparación independiente de evaporación:
las tasas proceden de la misma señal de masa que se reproduce. No valida
la emisión gaseosa, química parcial, HRR, CO/FED o muebles.

Actualización posterior: [base energética de referencia](G3_D1_HEPTANE_PHASE_BASIS_2026-10-04.md)
revisada y [ledger de fases cerrado técnicamente](G3_D1_PHASE_LEDGER_2026-10-04.md),
todavía sin integración. El [gate de emisión/B](G3_D1_ISOHEPT9_EMISSION_BASIS_2026-10-04.md)
delimita datos e hipótesis. Siguiente: diseño de caller puro conjunto con
contorno declarado; energía sensible/predicción física siguen pendientes.
La cola posterior a
500 s necesita revisión específica; no se ha filtrado ni utilizado.
Futuro producto exige contrato de gas combustible/zona/energía y dueño
atómico único, con calibración independiente para cada alcance.
