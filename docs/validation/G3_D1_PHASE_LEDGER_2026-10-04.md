# D1: ledger puro con fases, contrato previo

Fecha: 2026-10-04. Rama `codex/g3-fed-co-zonal-shareable`, HEAD `cbab7b05`.
Estado: prototipo técnico cerrado; cadena R2-1 completa en verde.
Sin integración ni activación. No commit/push.
Continúa el [gate energético](G3_D1_HEPTANE_PHASE_BASIS_2026-10-04.md).

## Alcance predeclarado

Extender `FuelMassBudgetModel.gd` con `propose_phase_reference`, separado de
`propose` v1. Modelo puro de un componente CHO y oxidación completa: sin
temperaturas reales, presión variable, ley de evaporación, tiempo químico,
CO/HCN, transporte o lectura de datos. Ninguna conexión al motor/producto.
Las masas nominales C=12,H=1,O=16 siguen explícitas. No importar el lote
ISOHept9, el calor efectivo de un mueble o cuentas U/R del motor.

Estado: `initial_fuel_mass_kg`, `liquid_fuel_kg`, `vapour_fuel_kg`, `o2_kg`,
`thermal_budget_kj`, `deposited_heat_kj`. Pedido: `dt_s`, `release_kg`,
`oxidation_kg`, masas por paso, no tasas. Material versionado declara fases
líquido/gas, referencia 298,15 K / 1 bar, agua gaseosa, base neta de oxidación
completa, CHO, q_liq, q_vap, L_ref y procedencia. Exigir q_vap-q_liq=L_ref
con tolerancias numéricas ya existentes; no añadir un knob para cerrar energía.

Transferencia acotada por líquido y **presupuesto B previo al paso**. Oxidación
acotada por vapor disponible y O₂. Q del mismo paso nunca alimenta liberación.
No crear crédito térmico futuro ni cola del pedido rechazado. Estado/candidato
inmutables hasta commit del caller; el prototipo no prueba dicho aplicador.

Compartir con v1 las cantidades de oxidación y la verificación de masa/
elementos; no duplicar su fórmula ni mapear líquido a `solid_fuel_kg` para
invocar v1. Conservar los campos/resultados/errores de la API v1.

Potencial A=m_liq*q_liq+m_vap*q_vap; B'=B-r*L_ref; Q'=Q+b*q_vap.
Exigir conservación conjunta A+B+Q además de masa/elementos, transferencia
de fase y oxidación. Q no es HRR del ensayo ni energía sensible de la zona.
Solo el ledger aislado conserva este total; no se afirma balance global del
motor. La energía sensible y la atribución del ensayo siguen pendientes.

## Oráculos predeclarados

Control sintético: CHO 0,75/0,25/0, q_liq=19000, q_vap=20000,
L_ref=1000 kJ/kg. No propiedad medida de heptano/sofá. Probar:

- Liberación sin O₂: masa/potencial en vapor, calor de oxidación cero.
- 0,1 kg liberados y oxidados: coste 100 kJ, calor 2000 kJ, neto 1900 kJ.
- O₂ limitante, B cero/limitante, vapor previo sin líquido, inventario agotado.
- B cero con vapor previo: oxidar vapor sí, usar Q para liberar líquido no.
- Paso cero, entradas inválidas/no finitas/bool, fases/base/unidades implícitas
  incompatibles y estado con masa restante superior a inicial.
- Preservar A+B+Q con vapor no oxidado; subdivisión, reinicio y rechazo sin
  alias de diccionarios. Caps numéricos no son una predicción de evaporación.
- Mutaciones válidas: calor líquido aplicado al vapor, coste borrado, fase
  no debitada, O₂ ignorado, calor sin oxidación, total no verificado, presupuesto
  prestado de Q, esquema/fase relajados. Errores de sintaxis no cuentan.

La referencia v1 se captura antes de cambiar el núcleo; comparar trazas API
completas en casos válidos/inválidos y modos prescrito/térmico byte a byte.
Repetir sus diez mutantes históricos y sus fixtures originales, sin borrar
contratos. La extracción de helpers puede cambiar anchors, no los defectos.

## Resultado focal del prototipo

Implementado `propose_phase_reference` en `sim/fire/FuelMassBudgetModel.gd`.
Comparte con v1 caps, estequiometría, productos y verificaciones de masa/
elementos; no llama a v1 ni convierte líquido en sólido. Tolerancias sin
cambios. Solo datos sintéticos: ninguna propiedad NIST importada al motor.
El potencial de referencia no sustituye energía sensible de una sala.

Fixture real `tests/fixtures/g3_phase_reference_budget.gd`: **502 checks**.
Campaña final **12/12 mutantes nuevos detectados**, sin errores de sintaxis
contados como muerte; **10/10 históricos detectados**. Fuentes originales
intactas por SHA-256. La primera campaña dejó vivo P10 (sin gate de Hess):
el balance del paso rechazaba también las entradas incoherentes, ocultando
la ausencia del gate de entrada. Se añadió el rechazo con pedido cero;
P10 muere y se repitieron los doce sobre la fixture final. No se relajó código.
El mutante sin chequeo total se distingue por un total no finito mientras
inventarios y potenciales individuales son finitos; un flujo normal por sí
solo no demuestra que ese guardarraíl esté presente.

Traza completa v1: **1298 propuestas**, modos prescrito/térmico, dos CHO,
caps, pasos cero y rechazos de entradas inválidas. Identidad byte a byte:
SHA-256 de ambas trazas `51231d0eb69c0afed2b8e8e4388b15125364151e894c879d49419533a5b0bbc0`.
Núcleo antes `783c13166fe9e263b470dd76b736114a6ee9e909dae27dc62ca4f6f5febcde82`;
después `1a25b8486454085aefc53fa371c38650c0582852a0dadae9ffec49e0ba324f97`.
Proveedor prescrito intacto: `89a8c5ad8c663c9f417e23381c6cbf0d2c07bc5c56f5ad01ff7dc1ed6e0cd9fc`.
La extracción del helper solo cambió el anchor M10, no su defecto ni oráculo.

Evidencia local (excluida de commits):

- `runs/g3_budget_v1_identity_20261004_094242/`.
- `runs/g3_d1_phase_mutations_20261004_094359/` (final).
- `runs/g3_d1_phase_mutations_20261004_094303/` (primer intento, P10 vivo).
- `runs/g3_d1_mass_mutations_20261004_094449/` (históricos).

Focal conjunta de nueve suites: **473 passed, 10 skipped**, exit 0,
15,22 s. Incluye ledger, proveedor, replay, fuentes, contrato/identificabilidad
y auditor fail-closed de fixtures. Las exclusiones son fixtures sin marcador
PASS, no corridas científicas fallidas. Primera focal reducida 39/39 PASS.
El recuento dinámico queda fijado a 502 en el test después de esta corrida;
pin final y auditor de fixtures: **330 passed, 10 skipped**, exit 0, 3,91 s.
Enlaces de los tres documentos y diff check limpios. Godot siempre monitorizado, sin corridas
paralelas; memoria >=6 GiB. Temporales externos nuevos bajo
`C:/Users/dangp/AppData/Local/Temp/simufire_phase_ledger_20261004_01`.
Excepción conocida: el launcher de fixtures fija APPDATA en
`runs/godot_test_appdata`, no en el directorio externo suministrado.

## Cadena de cierre completada

Referencia `runs/reference_suite_monitored_20261004_094854/`: **18/18**,
todos exit 0, informes nuevos y sin errores de salud. Suma de tiempos por
caso 3413,0 s; comparador y guardarraíles exit 0. **346/346 required PASS,
78 gaps**, ALL GUARDRAILS PASS incluido R2-1. Los 18 informes de caso
son idénticos byte a byte al backup. El resumen conserva bytes y campos,
salvo su única línea `generated_at`: `2026-10-03T23:02:13Z` pasa a
`2026-10-04T08:45:54Z`. SHA-256 final del resumen:
`b5c57953cf2bf3e5bddb21f95a8e7e7ac3c3e7f7a9ddd6c3f3110ae608af5dd6`.
Logs sin SCRIPT ERROR, Parse Error, ERROR: ni access violation. El control
de crecimiento rápido tardó 451,5 s frente a 44,5 en la tanda anterior,
pero su salida es idéntica y la salud limpia; no se ajustó ningún timeout
ni tolerancia por la duración. No es evidencia de rendimiento del ledger.

Después, `python -X utf8 scripts/check_product.py`: **168/168 PASS**,
exit 0. Registro `product.health.jsonl`: **81/81** solicitudes lanzadas,
ningún fallo, rechazo, timeout, cuadro de error o proceso residual;
quiescencia verdadera al terminar cada solicitud. Antes: 6,71 GiB libres.
Durante la suite se observó 5,22 GiB transitoriamente; no hubo lanzamiento
rechazado ni fallo de salud. El umbral de 6 GiB se aplica **antes** de cada
lanzamiento, no es una afirmación de RAM mínima durante su ejecución.
Se pidió liberar memoria y se volvió a medir; preflight global 6,61 GiB.

Global autoritativa `python -m pytest tests -q -p no:cacheprovider`, con
basetemp externo nuevo: **3484 passed, 41 skipped, 2 xfailed,
42 subtests passed**, exit 0, 602,04 s. Incluye el pin dinámico de 502 y
las pruebas del gate energético anteriormente solo verificadas offline.
No se lanzó pytest sobre la raíz. Referencia, producto y global secuenciales;
no cambios en núcleo/fixtures entre tandas, ni Godot directo.
Logs de producto/global y temporales: directorio externo indicado arriba,
`product.stdout.log`, `product.health.jsonl`, `pytest_global.stdout.log`
y `pytest_global_final/`. Los logs de referencia viven en su run indicado.
No commit/push; HEAD sigue `cbab7b05`, checkout principal fuera de alcance.

La referencia anterior se preservó en `reference_before/` del temporal
externo indicado. `reference_checks.json` anterior: generated_at
`2026-10-03T23:02:13Z`, SHA-256
`5f4c78a376b003d7a5668d847758561b2d3c07b2a90136bce456d82418734dfc`.
No se atribuyen resultados previos a este núcleo: las tres tandas anteriores
son nuevas y posteriores a su modificación. **GO técnico al ledger puro**,
no validación física experimental. **NO-GO** a integración, evaporación,
atribución al lote ISOHept9, U del motor, muebles y CO/FED. Antes de un
ensayo físico falta resolver masa realmente emitida, energía sensible y
origen independiente de B; no financiar la curva medida con un presupuesto
inventado ni ocultar su déficit aplicando un cap. El replay no está unido
al ledger y el caller/aplicador atómico tampoco queda validado aquí.

Salida final tras la global: guardarraíles repetidos ALL PASS con R2-1,
enlaces de los cuatro documentos editados sin roturas y `git diff --check`
limpio. Archivos nuevos del alcance sin whitespace final. Núcleo, proveedor
y resumen conservan sus SHA-256 congelados; los 18 informes siguen byte
idénticos al backup también después de pytest. Cero procesos/cuadros de
Godot, 6,87 GiB disponibles en el checkpoint final. HEAD `cbab7b05`
sin commits nuevos; se preserva el resto del trabajo previo sin limpiar
el árbol. Evidencia de producto/global guardada fuera del repositorio.

Continuación: [atribución de emisión y B revisada](G3_D1_ISOHEPT9_EMISSION_BASIS_2026-10-04.md).
Permite diseñar un caller puro condicionado con masa/contorno explícitos;
no identifica B físico o sensible ni aprueba evaporación predictiva.
La hipótesis no se convierte en certificado del lote. No cambia este
núcleo ni los resultados de su cadena R2-1.

Diseño posterior del [caller atómico aislado](G3_D1_ATOMIC_CALLER_CONTRACT_2026-10-04.md)
listo para implementar con controles sintéticos; el caller sigue sin código.
No confundir sus controles predeclarados con los 502 checks ejecutados aquí.
