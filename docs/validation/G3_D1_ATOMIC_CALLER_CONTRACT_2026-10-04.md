# D1: contrato de unión atómica del proveedor y el ledger de fases

Fecha: 2026-10-04. Rama `codex/g3-fed-co-zonal-shareable`, HEAD `cbab7b05`.
Estado: **cierre técnico aislado completo; referencia/producto/global verdes (§10)**.
Continúa el [gate de atribución de emisión/B](G3_D1_ISOHEPT9_EMISSION_BASIS_2026-10-04.md).
Diseño inicial sin código/Godot (§9); implementación posterior aislada (§10).
Sin integración, commit o push en ninguna de las dos pasadas.

## 1. Decisión y límites

**GO a implementar y validar una autoridad aislada con controles sintéticos.**
NO-GO a conectar `SimulationEngine`, asignar perfiles a muebles, convertir
U/HRR a masa o activar CO/FED. No importar todavía un material ISOHept9
al caller: su acoplamiento condicionado necesita una entrada propia con
hipótesis, referencia y aproximación de masas atómicas declaradas.

Módulo aislado: `sim/fire/PrescribedPhaseBudgetController.gd`, `RefCounted`.
No una ley física nueva: compone las APIs existentes, sin duplicar integral,
cap térmico, química o estequiometría. El controlador tiene estado propio;
solo sus propuestas son puras. No describir un commit como función pura.
Atomicidad en memoria y en un hilo, sin señales, callbacks, `await`, nodos
o escrituras de archivo. No garantiza transacciones entre sistemas del
motor, persistencia atómica ni seguridad frente a un snapshot falsificado
de forma coherente.

Primera versión deliberadamente cerrada: todo combustible inicial líquido,
vapor y productos iniciales cero; O₂ y B iniciales declarados; Q inicial cero.
Sin nuevas entradas de calor/O₂, pérdidas o devolución Q a B. Así se puede
reconstruir el agregado sin inventar propietarios térmicos. Q sigue siendo
calor contabilizado, no energía sensible zonal ni HRR experimental.

## 2. Contexto inmutable y atribución

Contexto `g3_prescribed_phase_context_v1`, claves exactas:

- `schema`, `program`, `material`, `attribution`, `seed`.
- `program`: contrato ya validado por `PrescribedFuelReleaseModel`.
- `material`: contrato `g3_phase_reference_CHO_material_v1` validado por
  `FuelMassBudgetModel.propose_phase_reference`, sin pasar por la API v1.
- `attribution`: `input_component_id`, `modeled_component_id`,
  `input_quantity`, `rule`, `status`, `provenance`.
- `seed`: `initial_o2_kg`, `initial_thermal_budget_kj`,
  `energy_boundary_kind`, `energy_boundary_provenance`.

`input_component_id` y `input_quantity` deben coincidir exactamente con
el programa. Dos parejas permitidas, sin conversión implícita:

1. Emisión declarada/lineal: `same_declared_component`, identificadores
   iguales, `synthetic_declared_emission`.
2. Depleción medida/constante: `all_depletion_as_reference_vapour`,
   `conditional_not_measured_emission`; identificador de reservorio
   observado separado del componente de referencia modelado. Es hipótesis
   uno-a-uno para diagnóstico, no fracción gaseosa medida.

No aceptar factores de emisión ocultos, aliases de unidades, estados con
autorizaciones físicas o una regla ambigua. Números finitos/no negativos,
sin bool ni strings; identificadores/procedencias no vacíos; extras y campos
ausentes se rechazan. Unidades fijadas por nombres/contratos: kg, kJ, s.

`energy_boundary_kind`: `synthetic_independent_initial_budget` o
`declared_conditional_initial_budget`. Ninguno significa B medido. No
aceptar HRR, IHRR, Q o costes calculados como evidencia de B independiente.
El segundo es solo contorno de una prueba condicionada, nunca aprobación
de evaporación predictiva. En esta implementación inicial, solo controles
sintéticos, sin crear entrada NIST ni buscar un B que ajuste su curva.

El fingerprint del contexto incluye versión del controlador, programa,
material, atribución y seed completos, con claves ordenadas y precisión
numérica completa, después de validarlos. El fingerprint del proveedor
sigue siendo el suyo; no cambiar su algoritmo/versiones. Ambos identifican
bytes/convenciones, no certifican ciencia ni autoría.
Copias profundas al inicializar, leer o devolver resultados: modificar
después un argumento o snapshot no debe modificar contexto ni estado.

## 3. Un único agregado confirmado

Sobre raíz privada única `_owned`, sin setters por cada subsistema:

`schema`, `context_fingerprint`, `generation`, `physical_time_s`,
`progress`, `phase`, `totals`.

- `schema`: `g3_prescribed_phase_snapshot_v1`.
- `generation`: entero no negativo; nunca float/bool; no restituir un
  contador antiguo al restaurar. Rechazar overflow antes de escribir.
- `progress`: candidato íntegro del proveedor, con su fingerprint,
  tiempo de fuente, solicitada/aceptada/rechazada acumuladas.
- `phase`: los seis campos íntegros del ledger de fases.
- `totals`: `oxidized_fuel_kg`, `co2_kg`, `water_vapour_kg` acumulados.
  Cantidades del núcleo, no otra fórmula de producción. O₂ y calor
  acumulados se leen/reconstruyen de la fase y de la seed, no de otra cuenta.

Estado inicial: tiempo/generación/cuentas cero, progreso inicial canónico,
líquido igual a `program.initial_mass_kg`, O₂/B según seed y vapor/Q cero.
Solo devolver un estado inicial si proveedor, contexto y núcleo aceptan
sus entradas. Inicializar de nuevo una instancia ya inicializada se rechaza;
una fuente nueva requiere instancia nueva, no reutilizar contexto/cursor.

## 4. Coherencia antes de proponer, confirmar o restaurar

Verificar esquema exacto, tipos, finitud, fingerprints y relojes. Invocar
`Release.propose(program, progress, progress.time_s)` para validar las
cuentas y la integral acumulada, sin duplicarla. Para comprobar el dominio,
usar el último tiempo de muestras después de validar el programa.

Relaciones del agregado que deben cerrar con tolerancias numéricas:

- `progress.time_s = min(physical_time_s, source_domain_end_s)`.
- `scheduled = accepted + rejected`, comprobación canónica del proveedor.
- `liquid = initial_liquid - accepted`.
- `vapour + oxidized_total = accepted`.
- Masa inicial de combustible + O₂ inicial = líquido + vapor + O₂ actual
  + CO₂ acumulado + agua acumulada.
- Fase, productos, B restante y Q coinciden con la recomposición canónica
  del agregado descrita abajo. También exigir finitud del total A+B+Q;
  números individuales finitos no garantizan una suma finita.

**Recomposición, sin segunda estequiometría**: sobre la seed de referencia,
llamar al núcleo para transferir `progress.accepted_kg` y oxidar cero;
luego sobre ese candidato pedir liberación cero y oxidación
`totals.oxidized_fuel_kg`. Usar un dt positivo declarado para esta
comprobación algebraica, no como intervalo físico ni nueva simulación
temporal. Exigir aceptación completa de esas cantidades y comparar
candidato/CO₂/agua/Q con el agregado. El núcleo es el dueño de todos
los factores químicos y del coste de fase. No copiar sus helpers privados.

Esta recomposición es válida por el alcance cerrado: B/O₂ solo iniciales,
sin retorno de Q a B. No demuestra cada detalle del historial de pasos ni
autenticidad de un snapshot. Si se amplía a contornos/pérdidas/intercambios,
hay que versionar el contrato; no aplicar a escondidas la misma identidad.

Reusar `MASS_ABS_TOL_KG=1e-12`, `ENERGY_ABS_TOL_KJ=1e-9` y `REL_TOL=1e-12`
del núcleo; no knobs nuevos. Comparación numérica del agregado, no bit a
bit entre distintas sumas. El oráculo de masa medida a nodos conserva
su `1e-9 kg`, distinto de incertidumbre experimental.

## 5. Propuesta y commit: orden obligatorio

API implementada: `initialize(context)`, `snapshot()`,
`preview_step(end_time_s, oxidation_requested_kg)`,
`commit_step(end_time_s, oxidation_requested_kg, expected_generation)`,
`restore(snapshot, expected_generation)`.

`commit_step` **no acepta un candidato externo**. Recibe intención y
generación; vuelve a calcular desde el agregado vigente. Un preview
editado, viejo o perteneciente a otro objeto no puede aplicarse por copia.
Generación errónea es conflicto: nada cambia, no una aceptación parcial.
El preview informa `physical_dt_s` y `source_dt_s` separados; el pedido
de fase usa solo el primero. Estos campos permiten fijar ambos relojes
en los controles sin inferirlos de la masa aceptada.

Orden de `preview_step`:

1. Validar contexto/agregado y argumentos. dt físico = extremo - tiempo
   físico actual, no diferencia de cursores de fuente.
2. Extremo de fuente = menor entre extremo físico y fin de curva. Invocar
   `Release.propose` con ese extremo, siempre dentro de su dominio.
3. Invocar `Budget.propose_phase_reference` con dt físico, demanda del
   proveedor y pedido explícito de oxidación. **Solo B anterior**; no
   prestar Q presente/anterior, ni inferir pedido desde HRR.
4. Pasar únicamente `accepted_release_kg` del núcleo a
   `Release.acknowledge`, no solicitud ni `accepted_oxidation_kg`.
5. Construir una copia completa: candidatos de progreso/fase, productos
   y oxidación acumulados, tiempo físico y generación siguiente.
6. Validar candidato completo/coherencia/finitud. Si falla cualquiera,
   devolver rechazo sin candidato aplicable ni escribir sobre `_owned`.

`commit_step` verifica generación, recalcula ese preview y, solo si todo
pasa, sustituye **una vez** la referencia a `_owned` por el agregado nuevo.
Sin escrituras intermedias sobre su progreso, fase, generación o totales.
Snapshot/preview/report son copias; no referencias a estructuras privadas.

Paso cero: preview válido sin cantidades/avance; commit devuelve no-op,
sin cambiar generación ni agregado. Paso físico positivo confirmado
incrementa generación una vez incluso con liberación/oxidación cero.

Dos resultados diferentes:

- **Transacción inválida**: conserva todo, incluido cursor y generación.
- **Demanda físicamente limitada**: transacción válida; avanza reloj,
  registra el rechazo y solo debita/produce lo aceptado. No hay cola ni
  reemisión del déficit. No puede declararse replay íntegro de masa si
  hay rechazos; se informa la discrepancia, nunca se oculta con un cap.

## 6. Fin de curva, restauración e informes

Una fuente terminada no significa fuego extinguido. Cursor de fuente
queda en su fin y nuevos pasos físicos tienen demanda cero; dt físico
sigue positivo y permite oxidar vapor previamente liberado. Cruzar el
fin de curva consume solo su intervalo válido; no extrapola tasas,
no trunca el tiempo físico ni libera el líquido que quedó sin aceptar.

`restore` valida un snapshot completo de mismo contexto antes de escribir.
Restaura conjuntamente relojes, progreso, fase y totales; asigna generación
**actual +1**, no la guardada. Así invalida intenciones previas incluso
si vuelve a exactamente las mismas cuentas. No permite restaurar solo
cursor, fase o cuentas de productos. No restaura/modifica contexto.

Informe devuelto por cada operación, derivado del agregado confirmado
y del resultado de esa operación, no de un preview independiente.
No mantener otra copia persistente de la física como "último informe".
Campos: esquema/scope/fingerprints/generación,
tiempo físico/fuente, cantidades pedidas/aceptadas/rechazadas, B/coste/Q,
CO₂/agua/oxidación acumuladas y estado de fuente. Aprobaciones de ciencia,
evaporación predictiva, integración y activación siempre false. No hay
campo `fire_extinguished` inferido de la fuente ni concentración CO/FED.

## 7. Controles y mutantes predeclarados para la implementación

Material sintético: CHO=0,75/0,25/0, q_liq=19000, q_vap=20000,
L=1000 kJ/kg. Fuente constante de 0,1 kg/s entre 0 y 2 s, último nodo
2 s/tasa cero, líquido inicial 1 kg. Atribución de depleción a vapor
**sintética y condicionada**, no ensayo de heptano. Repetir el caller con
una curva lineal compatible para no romper el contrato anterior.

| ID | Control | Oráculo predeclarado |
| --- | --- | --- |
| A01 | Init, preview repetido, modificación de copias | Ningún avance/alias; estado inicial canónico |
| A02 | Paso 0-1 s, B=1000, O₂=10, oxidar 0,1 kg | Acepta 0,1; B=900; Q=2000; O₂=9,6; CO₂=0,275; agua=0,225; líquido=0,9; vapor=0 |
| A03 | Mismo paso, O₂=0 | Vapor=0,1, Q=0, coste=100; total A+B+Q=20000 |
| A04 | Mismo paso, B=50, O₂=10 | Acepta/oxida 0,05; rechaza 0,05; B=0; Q=1000; cursor=1 |
| A05 | B=0 desde inicio | Acepta cero, líquido intacto, rechazo/tiempo registrados |
| A06 | B=1000, O₂=0,2, pedido 0,1 | Libera 0,1; oxida 0,05; vapor=0,05; O₂=0 |
| A07 | Después de A04, siguiente intervalo con B=0/Q=1000 | No pide prestado Q, no reemite rechazo, acumula rechazado=0,15 al llegar a 2 s |
| A08 | Generación antigua y doble commit con la misma generación | Segundo intento rechazado; agregado byte idéntico al confirmado |
| A09 | Snapshot con cursor de otro avance/fase nueva | Rechazo de incoherencia, incluso si cuentas de proveedor cierran solas |
| A10 | Restore completo y reejecución de misma intención con generación nueva | Mismas cantidades/estado numérico, generación nueva; intención antigua rechazada |
| A11 | Material/seed/atribución cambiados con snapshot viejo | Fingerprint incompatible, sin escritura |
| A12 | Contexto/estado/intención inválidos, bool, NaN, infinito, extras, campos ausentes | Rechazo completo y sin excepción atribuida como PASS |
| A13 | Agotar curva con pedidos previos de oxidación cero y O₂ disponible, luego 2-3 s | Fuente cerrada; demanda cero; dt físico=1/fuente=0; oxidación/calor/productos del vapor posibles |
| A14 | Cruzar 1,5-2,5 s | Demanda=0,05 kg; dt físico=1/fuente=0,5; cursor=2; tiempo físico=2,5 |
| A15 | Paso cero, incluso con pedido de oxidación positivo | No emisión/oxidación, no generación ni avance |
| A16 | Productos/Q/B/cuentas alterados individualmente | Recomposición canónica detecta la alteración |
| A17 | Números individuales finitos cuyo agregado rebosa | Rechazo antes de commit |
| A18 | Curva lineal y constante, pasos divididos/irregulares, sin límites activos | Misma integral/cuentas finales dentro de tolerancia, no exigir bytes entre particiones |
| A19 | Compensar un rechazo mediante edición coherente del cursor, pero masa no correspondiente | Identidad líquido/aceptado y recomposición impiden el reinicio parcial |
| A20 | Publicación/estado de ciencia tras init, preview, commit, rechazo y restore | Describe estado confirmado; todas las autorizaciones false |

Con caps activos/oxidación al agotar fuente no exigir trayectoria temporal
idéntica al subdividir: el kernel no modela cinética y el vapor puede quedar
disponible en momentos distintos. Predeclarar pedidos por partición, comparar
balances y demostrar equivalencia solo en controles donde corresponde.

Campaña prevista de 18 defectos válidos: avanzar antes de validar; confirmar
solo progreso; confirmar solo fase; aceptar masa solicitada; usar oxidación
como aceptación del proveedor; ignorar generación; copiar candidato externo;
omitir vínculo líquido/aceptado; omitir material/seed del fingerprint; prestar
Q a B; reemitir rechazo; omitir producto acumulado; restaurar generación vieja;
dt tomado del cursor de fuente; impedir oxidación después de fin; extrapolar
fuente; alias de snapshot/contexto; autorización física en informe.
Cada uno debe producir un fallo científico/transaccional válido, no parseo,
timeout o fallo del monitor. Predeclaración del diseño; campaña posterior
con anchors concretos y resultados en §10, sin alterar sus criterios.

## 8. Cierre necesario del siguiente cambio de código

Primero fixture GDScript real del caller y los 20 grupos, comprobaciones
analíticas y recomposición; después campaña de mutaciones en copias y
restauración/hash de originales. Fijar recuentos tras medirlos, no inventarlos.
Mantener API v1/proveedor intactos por hash; comprobar aislamiento/no carga
desde motor, editor, escenarios o distribuidos. Si cambia alguno de los
módulos existentes, repetir su identidad completa y mutantes históricos.

Después referencia completa por monitor: 18 casos, 346 required/78 gaps,
informes de caso idénticos y resumen solo timestamp; guardarraíles incluido
R2-1, producto y global `pytest tests -q -p no:cacheprovider`, secuenciales,
APPDATA/TEMP/TMP/basetemp según monitor y temporales nuevos, al menos 6 GiB
antes de cada lanzamiento. Sin Godot directo ni pytest sobre la raíz.
No declarar cierre del caller hasta completar la cadena; no commit/push
sin autorización adicional. Diseño listo no equivale a código implementado.

## 9. Verificación histórica del diseño, antes de implementar

Revisados ambos módulos GDScript completos y sus contratos/fixtures actuales.
La recomposición se apoya en el alcance cerrado y en APIs públicas, no en
copiar química ni integral; el controlador propuesto aún no se ha compilado
o ejecutado porque todavía no existe.

Regresión focalizada **155 passed, 2 deselected**, exit 0, 1,62 s; las dos
excluidas son las fixtures de fases y replay que arrancan Godot. No hay
tests nuevos ni se atribuyen estos resultados a los 20 grupos del caller.
Primera selección genérica `not actual`: 154 PASS y 3 excluidas, incluido
por nombre un control offline de cambio de contenido; repetida con selección
explícita para incluirlo. Basetemp externo nuevo bajo
`C:/Users/dangp/AppData/Local/Temp/simufire_atomic_contract_20261004_u3k13knf/`.

Guardarraíles ALL PASS, R2-1 incluido sobre los informes existentes;
estilo GDScript visual y enlaces de cinco documentos PASS, diff check
limpio. No nueva referencia/producto/global. Núcleo/proveedor/resumen
conservan los hashes `1a25b848...`, `89a8c5ad...`, `b5c57953...`.
Sin procesos Godot lanzados en este gate, ni cambios en `sim/`, fixtures,
datos, informes, interruptores o escenarios. Trabajo previo preservado,
checkout principal fuera de alcance, sin commit/push.

## 10. Implementación aislada posterior y verificación (2026-10-04)

Controlador real GDScript implementado, fixture
`tests/fixtures/g3_atomic_phase_controller.gd` y contratos Python auxiliares.
Una raíz confirmada; previews sin escritura; commit recalculado; restauración
completa con generación vigente +1. Relojes separados, aceptación del núcleo,
productos acumulados y recomposición mediante los dos módulos canónicos.
No química/integral duplicadas, nuevas tolerancias o lectura de fuentes reales.
La restauración verifica tanto el agregado vigente como el snapshot solicitado.

Fixture: **361 comprobaciones / 20 grupos A01-A20 PASS**. Regresión conjunta:
**524 passed / 10 skipped**, exit 0 (19,52 s), incluidos los contratos de
salida fail-closed de fixtures. 26 tests nuevos: ejecución real, composición,
hashes congelados, aislamiento, 18 anchors y cuatro rechazos del clasificador.
Dos contratos históricos permiten únicamente al caller aislado consumir
núcleo/proveedor; el contrato nuevo prohíbe cargar el caller desde cualquier
recurso de producto, incluido proyecto, escenarios, herramientas y editor.
No se suprime la exigencia de aislamiento, se comprueba la frontera nueva.

Mutaciones: **18/18 válidas detectadas**, control PASS, cero supervivientes,
cero bajas por parseo/script error/timeout. Evidencia final:
`runs/g3_atomic_phase_mutations_20261004_133512/results.json`; 19 ejecuciones
monitorizadas y hashes de los cuatro originales intactos. Dos campañas
anteriores se abortaron por salidas incompletas de la fixture tras mutantes
que rechazaban un preview o exponían un alias; sus timeouts **no** cuentan
como detecciones. Se corrigieron esas salidas sin relajar los oráculos y
se repitió toda la campaña. Un intento adicional no pudo escribir el log
externo por permisos; tampoco se cuenta como campaña aprobada.
La primera corrida focalizada también señaló un error del oráculo de
overflow: B=8e307 y potencial líquido=7,6e307 aún sumaban un valor finito.
Se corrigió la entrada a B=1,1e308 para exigir realmente un total no finito;
no se modificó ni relajó la comprobación del módulo.

Hashes SHA-256 de los originales en la campaña final:

- Caller: `ce88db42f1f15325b1ae2a226a10fae01137993f8e4483f8115cd05394750667`.
- Fixture: `49823e0c71d4af8a6cb8c6559a051c82eb2c8da0e23eaffe9b948ef41b4a7a11`.
- Núcleo y proveedor: `1a25b848...` y `89a8c5ad...`, iguales a la entrada.

Referencia actual **PASS**: 18 casos / 346 required / 78 gaps, todos con
informe nuevo y sin incidencias del monitor; 18 informes byte idénticos
contra copia inmediatamente anterior, resumen solo `generated_at`
08:45:54Z -> 12:31:15Z del 04-10. ALL GUARDRAILS PASS, R2-1 incluido.
Evidencia: `runs/reference_suite_monitored_20261004_134027/`, 3040,2 s
acumulados por casos, mínimo disponible antes de lanzar 6,69 GiB.

**Cadena técnica completada tras liberar memoria**:

- Producto: **168/168 PASS**, exit 0. Log
  `product_resume.health.jsonl` bajo el temporal externo de esta fase:
  **81 solicitudes, 81 lanzamientos limpios**, ningún rechazo de memoria,
  timeout, aviso nativo, proceso ajeno o residual. Antes de reanudar 6,032 GiB.
- Global autoritativa: `python -m pytest tests -q -p no:cacheprovider`,
  **3535 passed / 41 skipped / 2 xfailed / 42 subtests passed**, exit 0,
  **516,80 s**. Memoria previa 6,372829 GiB; no otra tanda Godot concurrente.
  Basetemp nuevo `pytest_global_resume`, APPDATA `global_appdata`,
  TEMP/TMP `global_temp`, todos bajo el temporal externo
  `C:/Users/dangp/AppData/Local/Temp/simufire_atomic_caller_20261004__45gspjd/`.
  Los launchers de fixtures conservan su override interno de APPDATA bajo
  `runs/godot_test_appdata`; no afirmar que todo hijo usa el APPDATA externo.
- UTF-8 heredado mediante `PYTHONUTF8=1`; monitor con mínimo 6 GiB antes
  de cada lanzamiento, sin Godot directo ni pytest contra la raíz.

**Incidencias de intentos anteriores, ya superadas**. El primer producto abortó por
decodificación (padre con `-X utf8`, hijo Python con cp1252); repetido con
`PYTHONUTF8=1` heredado por todos los hijos, sin cambio de código. No se
atribuye aprobación al intento abortado. La repetición acabó exit 1 porque
la memoria cayó: **81 solicitudes, 27 lanzamientos limpios y 54 rechazados
por el umbral de 6 GiB**. Primer rechazo 5,75 GiB, mínimo de los rechazos
5,40 GiB; disponible al finalizar 5,58 GiB. Cero crashes/timeout/popups o
Godot residuales en los lanzamientos realizados. Registro externo:
`C:/Users/dangp/AppData/Local/Temp/simufire_atomic_caller_20261004__45gspjd/product_final.health.jsonl`.
Ese intento no fue producto aprobado ni demuestra un fallo del caller:
los rechazos no ejecutaron las pruebas. La global no se lanzó durante ese
bloqueo. Tras liberar memoria se repitió producto íntegro y luego global,
con los resultados verdes anteriores. No cambió `sim/`, por lo que la
referencia ya aprobada sigue vigente; no se regeneró por el cambio de entorno.
El cierre aislado no autoriza integración, commit o push.

Comprobación final posterior a global: ALL GUARDRAILS PASS, R2-1 incluido;
estilo visual, enlaces de los tres documentos y diff check PASS. Los cuatro
hashes GDScript siguen idénticos a la campaña final; los 18 informes de caso
siguen byte idénticos y el resumen solo cambia `generated_at` frente a la
copia previa. SHA-256 final del resumen:
`ee5a7b18a0710f0bfd15f51468f45255301f6088c6b59cc09d91745d934f3da9`.
Cero procesos Godot y cero cuadros de error. Sin commit/push.

Cierre offline posterior al bloqueo: **27 passed / 1 deselected** (solo
ejecución Godot del caller excluida), guardarraíles científicos con R2-1,
estilo visual, enlaces de los tres documentos y `git diff --check` PASS.
Los cuatro hashes GDScript de la campaña seguían intactos. En esa fase
de bloqueo se midieron **3,95 GiB**, por debajo del umbral, y no se relanzó
Godot hasta la liberación posterior. HEAD continúa `cbab7b05`, sin commit/push.

Mantener NO-GO a entrada real ISOHept9, evaporación predictiva, sensible,
contornos nuevos, U, muebles y CO/FED. El cierre técnico del caller no
resuelve la masa realmente emitida ni el origen térmico independiente de B.

## 11. Correcciones posteriores del caller (2026-10-05)

Las secciones anteriores son el registro de su fecha y no se reescriben.
Dos correcciones posteriores cambian cómo el caller **decide** aceptar un
estado, sin cambiar ninguna identidad, tolerancia, esquema, API pública
ni fingerprint de este contrato:

- [Guardas de tipo](G3_D1_TYPE_GUARD_HOTFIX_2026-10-05.md): `schema` y
  `context_fingerprint` se comprueban por tipo antes de compararse. Antes,
  un valor mal tipado abortaba la validación y `restore` aceptaba el
  snapshot.
- [Veredicto positivo explícito](G3_D1_POSITIVE_VERDICT_2026-10-05.md):
  §4 y §5 hablaban de "verificar" y "validar" el agregado; en el código
  eso equivalía a que la lista de errores quedara vacía. Ahora
  `_check_owned` devuelve un veredicto y `initialize`, `preview_step`,
  `commit_step` y `restore` exigen que sea positivo antes de continuar o
  escribir. Los hashes del caller citados en §10 son los de entonces.

Sigue vigente lo dicho en §1 y §4: la validación es coherencia del
agregado, no autenticidad de un snapshot.
