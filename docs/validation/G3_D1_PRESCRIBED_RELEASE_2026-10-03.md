# G3-D1 — proveedor prescrito por intervalos

Estado (2026-10-03): **cerrado técnicamente, con cadena R2-1 verde**.
No integrado en producto, sin ley de muebles ni datos reales.
Rama `codex/g3-fed-co-zonal-shareable`, HEAD `cbab7b05`, sin commit/push.
Continúa el [contrato masa/material](G3_D1_MASS_MATERIAL_PROVIDER_CONTRACT_2026-10-03.md)
y el [núcleo puro](G3_D1_FUEL_MASS_BUDGET_2026-10-03.md).

## Código y límites

`sim/fire/PrescribedFuelReleaseModel.gd`: `RefCounted` con funciones
estáticas puras `initial_progress`, `propose` y `acknowledge`. Sin motor,
nodos, carga de datos o escritura sobre entradas. El resultado es demanda
kg/paso, **no masa realmente emitida ni HRR**. Ningún sistema lo carga.
No lee U/R, calor, O₂ ni el estado del objeto; no infiere masa desde MJ.

El adaptador offline `prepare_prescribed_program` en
`validate_g3_mass_material_profile.py` valida el perfil y copia un programa
de tasas independiente. Conserva la clasificación sintética/candidato
externo pendiente y todas las autorizaciones false. No aprueba un material
ni crea inventarios de sala. La fixture GDScript lee la misma JSON sintética;
una prueba Python exige igualdad de su programa con el del adaptador.

El proveedor verifica solo el contrato numérico del programa/cursor,
**no** vuelve a validar procedencia, composición o energía química. Esas
fronteras siguen perteneciendo al contrato offline y al núcleo. Un caller
que lo use directamente no recibe aprobación científica de esta API.

## Reloj, rechazo y reinicio: reglas predeclaradas

1. Programa: identificadores de perfil/componente, kg iniciales declarados,
   modo prescrito, emisión de componente kg/s, origen temporal, muestras
   lineales y rechazo fuera del dominio. No admite extras/alias de MJ.
2. `initial_progress` devuelve tiempo/cuentas cero. El fingerprint fija
   programa completo y versión del algoritmo (JSON de claves ordenadas y
   precisión numérica completa, SHA-256). Cambiar curva/componente o versión
   invalida el cursor; no se traduce a otra curva automáticamente.
3. `propose` integra solo `[tiempo confirmado, nuevo tiempo]`, recortando
   segmentos de la curva **al intervalo solicitado**, no el dominio para
   admitir extrapolación. Primer tiempo 0; extremos fuera del dominio o
   anteriores al cursor son errores, no clamps.
4. Proponer no avanza nada. El caller obtiene aceptación del núcleo y pasa
   esa **masa aceptada**, no la solicitada, a `acknowledge`. Se recalcula la
   demanda usando el progreso vigente, no se confía en un resultado viejo.
5. Confirmar avanza hasta el tiempo solicitado aunque acepte 0 kg. Se
   registran solicitado acumulado, aceptado y rechazado; no hay cola ni
   desplazamiento de la curva para reemitir lo rechazado. No es una predicción
   de cómo se retrasaría la pirólisis real por falta de energía.
6. Una segunda confirmación no nula del mismo extremo sobre el **nuevo**
   cursor es inválida. Sin intervalo nuevo la demanda es cero. El proveedor
   puro no puede impedir que un caller restaure deliberadamente un cursor
   viejo y lo aplique al inventario nuevo: la futura autoridad atómica debe
   poseer/confirmar juntos cursor, masa y productos.
7. Reinicio reproducible restaura **cursor y combustible** de un mismo
   snapshot; reiniciar solo el reloj no restaura combustible. No hay función
   que reinicie el motor ni persistencia global.

Invariante: `integral(0, tiempo) = solicitado = aceptado + rechazado`.
La masa de combustible la limita/debita el núcleo, no el proveedor. La
fixture confirma ambos candidatos solo cuando los dos son válidos; esta
composición de prueba no equivale a un aplicador transaccional del motor.

Tolerancias fijadas antes de Godot: `1e-12 kg`, relativo `1e-12`, energía
de fixture `1e-9 kJ`. La subdivisión se contrasta hasta esa precisión,
**no** se exige igualdad bit a bit entre distintas sumas flotantes.

## Controles ejecutados

Fixture sintética `tests/fixtures/g3_prescribed_fuel_release.gd`:
**247 comprobaciones, 83 grupos**, PASS. Triángulo 0,5 kg, parcial 0,04 kg,
curva asimétrica 0,195 kg; tiempos/cuentas inválidos y no finitos, cero paso,
extrapolación, cambio de programa, cap inicial y overflow. Previews
deterministas sin mutación ni avance implícito, reconocimiento repetido y
reinicio de ambos snapshots.

Fixture conjunta con `FuelMassBudgetModel`: pasos gruesos/irregulares,
O₂ abundante/cero/limitante, acumulación de combustible no oxidado, tope del
sólido y rechazo térmico. Reconstruye **masa total (incluye oxidante),
C/H/O y energía química** desde inventarios/productos, no solo residuos
emitidos por los módulos. Se mantiene aparte la calibración experimental.

Focalizada proveedor + contrato: **55 PASS**. Estáticos previos sin Godot:
54 PASS, una dinámica excluida (no eran cierre). Memoria antes de comenzar:
6,81 GiB; lanzamientos solo por monitor con mínimo 6 GiB.
Conjunta proveedor, contrato, auditor de masa y núcleo: **72 PASS** sobre
el código final (incluye las dos fixtures GDScript, sin exclusiones).

Mutaciones en copias aisladas: control PASS y **11/11 bajas válidas**,
sin supervivientes ni bajas por sintaxis/runtime; cuatro archivos originales
preservados byte a byte. Protecciones: avance de reloj, no reintentar
rechazo, aceptación <= solicitud, fingerprint, unidades, dominio, integral
lineal, tipo booleano, no reemitir el prefijo, cuentas de progreso y masa
inicial. Evidencia:
`runs/g3_d1_prescribed_mutations_20261003_180607/`.

SHA-256 del código probado:

- Proveedor: `7aeae0290abb20095ac9979038dafc34a596b2e861dd54c36930b2cb53ae81f8`.
- Núcleo (sin tocar): `783c13166fe9e263b470dd76b736114a6ee9e909dae27dc62ca4f6f5febcde82`.
- Fixture conjunta: `6cca266937113fabd10ac92b10f4ee2acaf678bb3b13e0779799df3a36895954`.

## Cadena de cierre ejecutada

Se regeneró la referencia completa porque se añadió código bajo `sim/`,
aunque no integrado; no se reutilizó la corrida anterior. No hubo cambios
de código durante las tandas. Referencia, producto y global, secuenciales:

| Verificación | Resultado |
|---|---|
| Referencia monitorizada | 18/18 limpios, exit 0; comparador 0, guardarraíles 0 |
| Contratos de referencia | 346/346 required PASS, los mismos 78 gaps |
| Informes de caso | 18/18 idénticos byte a byte a la copia previa |
| Resumen | Solo `generated_at`: copia previa 09:00:34Z → 17:00:57Z del 03-10; diff Git también solo esa clave |
| Guardarraíles | ALL PASS, R2-1 incluido |
| Producto | 168/168 PASS, 81 solicitudes de lanzamiento, cero fallos de infraestructura |
| Global autoritativa | `pytest tests -q -p no:cacheprovider`: 3382 passed, 37 skipped, 2 xfailed, 42 subtests passed; exit 0, 513,16 s |

Evidencia de referencia:
`runs/reference_suite_monitored_20261003_180950/`. Temporales/basetemp
externos en
`C:/Users/dangp/AppData/Local/Temp/simufire_d1_release_20261003_01/`, con copia
previa de los informes y `product.health.jsonl`. APPDATA/TEMP/TMP del padre
externos; el arnés histórico `tests/godot_runtime_launcher.py` sigue
forzando APPDATA a `runs/godot_test_appdata` en sus fixtures. No se presenta
esa excepción como aislada fuera del repositorio.

Hashes finales iguales a los del código probado. Enlaces y diff limpios;
cero procesos Godot al terminar. El checker de estilo de producto cubre
el GDScript visual, no estos módulos de `sim/fire`; su compilación se
demuestra por las fixtures reales, no por ese checker. Sin commit/push.

### Límites que permanecen

- El control con sólido 0,1 kg y programa inicial 1 kg es un **desajuste
  sintético de disponibilidad** para comprobar el cap y la contabilidad de
  rechazo. No acredita un historial de objeto/cursor coherente ni un
  reinicio real del motor. La integración debe verificar ambos estados.
- El fingerprint identifica el programa/versionado de tasas, no la
  composición, energía ni autorización del perfil completo. Esas identidades
  deben fijarse también en la futura autoridad de integración.
- Se revalida/recorre/hashéa la curva en cada llamada (coste lineal en sus
  muestras). No se ha medido rendimiento con 107 objetos ni se presenta
  como optimizado para producción.
- Fuera del dominio se rechaza la consulta. Agotar la curva no extingue
  el gas previamente liberado; el futuro controlador debe cerrar la fuente
  prescrita sin impedir que el núcleo oxide ese inventario existente.

## Próximo gate científico

Actualización del 04-10: [replay de masa ISOHept9](G3_D1_ISOHEPT9_REPLAY_2026-10-04.md)
añade formato constante por intervalo/cantidad medida al mismo proveedor,
manteniendo la API lineal byte idéntica. Cadena ampliada cerrada: referencia
346/346 y 78 gaps, producto 168/168 y global final 3426 passed, 39 skipped,
2 xfailed, 42 subtests. No es perfil material ni emisión gas validada.
Los resultados y hashes del 03-10 siguientes son históricos, no el cierre
de la ampliación. No se conecta el caso líquido al núcleo de combustión.

Primer benchmark de flujo de masa independiente y alcance estrecho,
con composición/energía atribuibles y fuentes revisadas. No adoptar
pérdida de espécimen como emisión de componente ni usar HOC efectivo como
químico sin resolver su base. No es obligatorio empezar por un sofá mixto.

Integración futura: identidad/especie de combustible, propiedades de gas,
destino zonal, coste térmico y dueño único/commit atómico. La química parcial,
las leyes predictivas de muebles, U y CO/FED siguen NO-GO. No cambia ningún
interruptor, perfil distribuido, escenario, ley de flujo o producción CO.
