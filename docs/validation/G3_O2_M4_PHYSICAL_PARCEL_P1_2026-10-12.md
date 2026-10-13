# G3 - M4-P1: núcleo aislado de parcelas físicas gas/O2

Contrato: 2026-10-12. Cierre: 2026-10-13. Base: `cc06ccde`.
**Cierre técnico del núcleo aislado, con cadena R2-1 verde.**
El contrato siguiente se escribió antes de programar. Este cierre no valida
la física del motor vivo ni autoriza integración o activación.
Autorización: «continúa» al núcleo aislado anunciado; sin wiring del motor.
CO/FED, producto y selección zonal viva siguen OFF/NO-GO.
[Diseño previo M4-B3](G3_O2_M4_PHYSICAL_COMPATIBILITY_2026-10-12.md).

## 1. Alcance y estado

Un módulo puro GDScript en sim/core, sin class_name, exports, escenas,
RoomModel, SimulationEngine ni consumidores de producto. No calcula caudales,
presión, interfaz, Cp, reacción, HRR, yields, mezcla turbulenta o FED.
Todas las parcelas y temperaturas de referencia son **entradas impuestas**.
No cambia M1/M2-T/M2-V/M3, M4-A1, el monitor ni los escenarios distribuidos.

Libro impuesto: generation, step y revision enteros no negativos, base
`physical_gas_mass_v1`, temperatura de referencia común positiva, salas y
eventos ya aplicados. Sala: m_upper, m_lower (kg gas), E_upper/E_lower
(kJ sensibles sobre la misma referencia), O_total y O_upper (kg O2).
O_lower=O_total-O_upper es derivado, no segunda autoridad. Todas las cantidades
son finitas; gas y energía sensibles no negativos. E=0 y O=0 si m=0.
Se exige 0<=O_z<=m_z, no el límite reference_dry_air_v1.
Es un gas con O2 y resto implícito; no composición completa de combustión.

Observable: fracción **másica** Y=O/m; zona ausente -> null. No se entrega
fracción molar ni número respiratorio. El estado no contiene geometría:
calor cambia E, no gas/O2. Deducir interfaz física es trabajo posterior.
E no admite gas por debajo de la referencia: rechazar, no poner un floor.
E es aquí un libro sensible impuesto, no un cierre termodinámico con EOS.
No decide energía interna frente a entalpía, Cp/Cv ni trabajo de presión
`p dV`. El acoplamiento gaseoso futuro deberá declarar y probar ese contrato;
conservar este libro no basta para demostrar conservación de energía física.

## 2. Operaciones y calendario impuesto

Evento: id/cause no vacíos, contexto generation/step/revision igual al libro,
base física exacta, copia esperada de todas las salas, paquetes y calor.
Un id ya visto se rechaza. Los ids y el reloj son entradas confiadas del
llamador sintético; no garantizan autoría ni cobertura de rutas reales.
La revisión impide usar una propuesta calculada antes de otra operación.
No hay avance automático de tick, reinicio, persistencia ni escritor vivo.

Paquete: id único en el evento, tipo transfer/boundary_in/boundary_out,
origen/destino (sala,capa) explícitos, q>=0 kg gas. Transferencia entre dos
extremos distintos; salida solo origen; entrada solo destino y frontera
con Y exterior [0,1] y e exterior>=0 kJ/kg. Las otras rutas rechazan frontera.
No hay consumo/reacción de oxígeno sin productos en este prototipo.

Para un donante interior se calculan **desde el snapshot previo**:

`dO = q * O_d/m_d`, `dE = q * E_d/m_d`.

La misma q,dO,dE sale del origen y llega al destino. Frontera de entrada:
dO=q*Y_ext y dE=q*e_ext. Salida exterior se registra como débito real, no
dilución equivalente de M2-V. Dos sentidos de una puerta son dos parcelas.
Sin κ en el transporte de fracción másica, ni promedios de sala ni remap
geométrico. No se llama al núcleo de referencia para convertir esta base.

Calor impuesto: id único, destino (sala,capa), delta E firmado y finito;
no modifica gas/O2. Donaciones de gas, O2 y energía se agregan por donante
antes de proponer. La energía retirada por calor negativo también cuenta.
Todo sale del estado previo: una entrada en el mismo evento no financia
salidas ni enfriamiento. No caps por paquete, reconciliación o clamps finales.
El calor positivo en zona ausente necesita un paquete que cree gas válido.

Propuesta: validar libro/evento completos -> calcular paquetes -> comprobar
donaciones -> validar todas las salas candidatas -> devolver copias aisladas
del libro nuevo y recibo. Cualquier rechazo devuelve solo razón, sin candidato,
recibo, cambio de revisión o id aplicado. El llamador decide aceptar el libro;
el módulo no guarda estado ni puede imponer atomicidad en el motor real.
Recibo: snapshots before/after, evento, parcelas aceptadas, calor y deltas
por zona de gas/energía/O2. Copias profundas, no alias con resultado/entrada.

## 3. Gates y campaña predeclarada

Comparación independiente: 1e-9 kg y 1e-6 kJ, solo diagnóstico; no autoriza
sobregiro, inventario negativo, cambio de base ni reparación de estado.

- Calor sin gas/O2, penacho impuesto lower->upper, transporte inverso,
  dos salas estratificadas y dos sentidos, frontera entrante/saliente.
- Zona ausente que nace desde donante, agotamiento/colapso completo,
  cero caudal, O2 rico válido sin techo ambiente, secuencia determinista.
- Tipo/base/unidad/schema incorrectos, NaN/inf/bool, estado no físico,
  donante ausente, cantidad negativa, entradas que financian salidas,
  salidas múltiples, enfriamiento combinado, contexto/revisión obsoletos,
  evento/contribución repetidos, copia esperada alterada y rechazo inmutable.
- Auditor Python separado: rehace donaciones y conversiones desde before,
  valida after/deltas contra cantidades de cada parcela y calor. No llama
  a propose; contraste con GD sobre muestras aceptadas. Corromper una ruta
  conservativa debe fallar aunque el total de edificio siga cerrando.
- Mutantes del GD real: débito de gas/O2/energía omitido, donante incorrecto,
  multiplicación molar sobre Y, calor que crea O2, donaciones sin agregación,
  gasto de entradas, validación capacidad/tipo/ausencia/contexto/duplicados
  retirada, alias de snapshots. Exigir control sano, fallo nombrado y
  restauración SHA-256. Error de script/nativo nunca es mutante muerto.

Fixture sin motor. Godot solo por monitor existente, ejecutable normal,
UI suprimida, JobObject propio, mínimo 6 GiB y una tanda a la vez.
Temporales externos. No terminar procesos ajenos ni rebajar el umbral.
Si sim/core cambia: referencia completa R2-1, guardarraíles, producto y global
autoritativa `pytest tests -q -p no:cacheprovider`, secuencialmente por monitor.
Informes solo generated_at; otros resultados no se ajustan para cerrar.
No exigir nueva identidad ON/OFF de un sistema que no tiene consumidores:
en su lugar congelar por hash todos los módulos vivos y buscar consumidores.

El inventario histórico M4-B tiene 64 GD y debe preservarse como evidencia.
Añadir un módulo puro hará 65: el test comparará todos sus archivos/filas
históricos y verificará la única adición aislada, no reescribirá la evidencia.
Preservar UID, stashes, main y ramas privadas. Publicación cuando cierre la
cadena; ningún GO a fuego/CO/FED por pruebas sintéticas de parcelas.

## 4. Retomada y límites

La próxima autoridad gaseosa de producto, la semántica O2 de la red,
ACH/M2-T/M2-V físicos, fuentes de combustible/productos y M4-C/D/E son
fases separadas. Reproducir paquetes impuestos no valida su magnitud, ley,
calendario, donantes vivos ni deposición por flotabilidad.
No se hacen comparaciones CFAST ni experimentales nuevas en esta entrega.

## 5. Implementación y falsación verificables

Implementación:
[PhysicalGasOxygenParcelModel.gd](../../sim/core/PhysicalGasOxygenParcelModel.gd).
Fixture sin motor, auditor Python independiente, runner y cierre por monitor.
Ningún sistema de simulación carga el módulo; no hay interruptor ni activación.

- Fixture final: **5 920 comprobaciones**, diez muestras auditadas y 256
  eventos de una secuencia determinista. Entrada, salida, dos sentidos,
  penacho, calor sin masa, colapso, nacimiento y O2 rico sin techo ambiente.
- Falsación final: **20/20 mutantes GD válidos muertos donde se declaró**,
  control sano y restauración SHA-256 del módulo/fixture/auditor. Una variante
  elimina las dos barreras contra repetición, no solo la primera.
- Focal offline: **315 passed**, 4,37 s (60 nuevas sobre las 255 M4 anteriores).
  Protecciones del cierre verifican también plan/bytes/assertions actuales,
  no aceptan solo el booleano «mutante muerto» del registro.
- Estilo general GDScript PASS; controles y mutantes por ejecutable normal,
  UI suprimida, sin timeouts/cuadros/procesos residuales ni terminación de
  procesos ajenos. Memoria antes del primer control: 6,87 GiB; cada lanzamiento
  mantiene el mínimo 6. No se afirma una memoria mínima medida de la campaña.

Fuentes del control y campaña final, SHA-256 raw:

| Archivo | SHA-256 |
| --- | --- |
| Módulo GD | b77eb33a29e9960f0878cfe6641dde9866864aa9e655a2cb73ba680759760478 |
| Fixture GD | 4c405f12d92ff52cae9f7a9d3b6936d650a7cbcef4c8222ce3e459e09a9de8f4 |
| Auditor Python | aa68306479c43917703072bf15166dea3ebc05414e8133d29b828b45f3d13f97 |

Registros externos aceptados bajo `%LOCALAPPDATA%/Temp/`:
`simufire_m4p1_control_fixed_20261012/` y
`simufire_m4p1_mutations_final_20261012/`. No publicar logs runs/ ni UID.

Intentos que no cuentan como cierre:

1. Primer control: 2 assertions fallaron. El arnés comparaba NaN con igualdad
   ordinaria y lo declaraba cambiado; la secuencia no se ejecutó por esa falla.
   Comparación estructural explícita de NaN corregida, sin tocar el modelo.
   No hubo error de script, fallo nativo ni cuadro. Repetición completa verde.
2. Primer focal: 1 failed / 292 passed. El test de sobregiro rechazaba antes
   por recibo mal compuesto. Se construyó el neto legal con entrada exterior
   compensadora y deltas pareados; ahora falla específicamente por donación.
3. Primera campaña: P15 sobrevivió. Quitar solo la guarda de repetición es
   equivalente porque la validación final rechaza seen duplicado. No se contó
   como muerte; mutante redefinido antes de repetir los veinte. P16 se fijó
   para compartir realmente book y receipt.after, no quitar una copia inocua.

4. Primera global: 2 failed / 5 054 passed, 74 skipped, 2 xfailed y 42
   subtests, 901,93 s. Ambos fallos eran del guardarraíl de consumidores:
   trataba el inventario lexical M4-B ya publicado como una nueva carga.
   Se admite únicamente ese archivo documental, con hash vigente y flags
   de no ejecución. Cinco pruebas nuevas rechazan hash alterado, integración,
   ejecución y loader añadido; los controles de cargas arbitrarias tracked
   y untracked siguen vigentes. Módulo/fixture/auditor no cambiaron. La
   selección completa del guardarraíl da 78 passed; la global se repitió.

## 6. Cadena final y retomada

[Resumen de evidencia versionado](G3_O2_M4_PHYSICAL_PARCEL_P1_EVIDENCE_2026-10-12.json).
Los registros completos permanecen en temporales externos, no en Git.

| Verificación | Resultado aceptado |
| --- | --- |
| Referencia monitorizada | 18/18 casos; 346/346 required, 78 gaps; 2 827,95 s |
| Corpus de referencia | 494 archivos, 493 idénticos raw; solo generated_at del JSON cambia |
| Producto monitorizado | 168 PASS; 569,46 s |
| Guardarraíles monitorizados | ALL PASS, R2-1 incluido; 2,88 s |
| Global autoritativa repetida | 5 061 passed, 74 skipped, 2 xfailed, 42 subtests; pytest 917,78 s |

Global: wrapper 921,54 s, returncode 0, stderr vacío; 6,990 GiB al inicio y
6,920 al final. Todas las tandas aceptadas: sin timeout, cuadros, excepciones
nativas, procesos ajenos detectados, limpieza forzada ni Godot residual;
process_quiescent=true. El mínimo de lanzamiento de 6 GiB no se rebajó.
La memoria inicial/final no demuestra un mínimo continuo de toda la tanda.
Nombre del registro final: `simufire_m4p1_global_fixed_20261013/result.json`.

Referencia/producto se ejecutaron sobre el mismo módulo, fixture y auditor
actuales. Tras reparar únicamente el guardarraíl Python se repitió la global,
no se adjudica una segunda ejecución de referencia o producto.
Después de actualizar documentos: 393 focales offline PASS (8,39 s), ocho
archivos Python con AST válido, enlaces locales de los cuatro documentos sin
errores, estilo GDScript PASS y guardarraíles/R2-1 monitorizados nuevamente PASS.
El inventario histórico de 64 GD conserva cada hash y escritura; solo se
añade este módulo puro (65). Se preservan 79 UID sin seguimiento y cuatro
stashes; no se publican UID, runs/, escenarios ni historia privada.
La identidad raw del corpus es del checkout medido; Git guarda texto LF.
No confundir el hash raw de un informe CRLF con el de su blob LF.
UID: comparación directa de los 79 pares ruta/hash contra el checkpoint de
referencia, sin diferencias. El resumen anterior usaba Sort-Object de
PowerShell; el JSON final declara orden Unicode de Python para su digest.
Ambos digests se conservan, pero no se confunde distinta ordenación con un
cambio de archivos. Los dos enlaces ajenos de Sky3D siguen fuera del alcance.

Siguiente gate: diseñar la autoridad de gas/energía/EOS y su prueba aislada
con calentador prescrito, sin combustible. Exigir balances de masa, energía,
volumen/presión y frontera, y definir entalpía/energía interna/trabajo antes
del acoplamiento. No iniciado en M4-P1. M4-C/D, fuego/productos y CO/FED
siguen NO-GO; esta entrega no valida caudales, materiales ni exposición.
