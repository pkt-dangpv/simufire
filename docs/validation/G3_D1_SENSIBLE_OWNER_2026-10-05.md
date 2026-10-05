# G3/D1 — Propietario atómico sensible versionado

Fecha: 2026-10-05. Entrada: `167f5c1a`, rama
`codex/g3-fed-co-zonal-shareable`, integrada y subida. Continúa el
[ledger sensible](G3_D1_SENSIBLE_LEDGER_2026-10-04.md) y sucede, sin
modificarlo, al [caller de referencia](G3_D1_ATOMIC_CALLER_CONTRACT_2026-10-04.md).
No es integración en la simulación ni aprobación de CO/FED, evaporación
predictiva o propiedades de muebles. **Estado: cerrado técnicamente como
propietario sintético aislado; cadena completa verde (§11).** Contrato y
oráculos predeclarados en §1-§8; implementación y verificación desde §9.

## 1. Decisión y límites

Módulo nuevo `sim/fire/PrescribedSensiblePhaseController.gd`, `RefCounted`,
versión `prescribed_sensible_phase_controller_v1`. No se convierte el
caller de referencia en sensible: `PrescribedPhaseBudgetController.gd`,
el proveedor, el helper Cp y el ledger conservan sus bytes y contratos.

El propietario posee **conjuntamente** contexto, progreso de la fuente,
estado de fases, cuentas térmicas acumuladas, relojes y generación, bajo
una única raíz privada. `FuelMassBudgetModel.propose_phase_sensible` sigue
siendo una propuesta pura; la nueva pieza es la dueña del estado persistente.

Defecto que el diseño evita: **reconstruir el estado sensible desde la masa
acumulada**. Dos historias con igual masa liberada y oxidada pueden tener
calentamientos, entalpías y presupuestos distintos (§7). El caller de
referencia recompone B y Q desde `accepted_kg`; aquí eso sería falso, así
que las cuentas térmicas se **conservan** y solo se contrastan entre sí.

Reutilización obligatoria, sin segunda física:

- `PrescribedFuelReleaseModel`: demanda (`propose`) y reconocimiento de la
  liberación aceptada (`acknowledge`).
- `FuelMassBudgetModel.propose_phase_sensible`: propuesta física de cada paso
  y auditoría a dt=0 de cualquier estado guardado.
- `FuelMassBudgetModel.propose_phase_reference`: solo para recomponer la
  química de la masa oxidada acumulada (O₂, CO₂, agua, calor químico).
- Cp(T) e integral: únicamente a través del ledger. El propietario no
  nombra, carga ni evalúa el helper de propiedades; la temperatura de
  referencia se lee de la constante que expone el ledger.

Atomicidad en memoria y en un hilo, sin señales, `await`, nodos ni
archivos. No garantiza transacciones entre sistemas del motor ni
persistencia en disco. Entradas **sintéticas explícitas**: no se añaden
presupuestos, fuentes térmicas ni datos experimentales.

## 2. Esquemas cerrados y versionados

Todos exigen claves exactas: ausentes y adicionales se rechazan. Números
`int`/`float` finitos; nunca `bool`, cadenas, `null`, NaN o infinito.

**Contexto** `g3_prescribed_sensible_context_v1`: `schema`, `program`,
`material`, `attribution`, `seed`.

- `program`: contrato del proveedor, sin cambios. El propietario comprueba
  además que sus ocho campos de texto sean `String` antes de delegar.
- `material`: `g3_phase_sensible_material_v1` completo (identidad, material
  de referencia y los dos perfiles Cp sintéticos), validado por el ledger.
- `attribution`: las seis claves del caller de referencia y sus dos parejas
  permitidas. Nuevo: `modeled_component_id` debe ser exactamente
  `material.component_id`.
- `seed`: ver abajo.

**Semilla** `g3_prescribed_sensible_seed_v1`: `schema`, `initial_o2_kg`,
`initial_thermal_budget_kj`, `initial_liquid_sensible_kj`,
`energy_boundary_kind`, `energy_boundary_provenance`.

- O₂ y B iniciales no negativos. `initial_liquid_sensible_kj` es una
  **cuenta de entalpía con signo** respecto a la referencia, no una
  temperatura; debe caber en el soporte del perfil líquido para la masa
  inicial (lo decide el ledger) y ser cero si no hay líquido.
- Vapor, Q, productos y cuentas acumuladas iniciales: cero.
- `energy_boundary_kind`: solo `synthetic_independent_initial_budget`.
  Los perfiles Cp admitidos son sintéticos, así que no se ofrece un
  contorno "condicionado" que sugeriría una comparación experimental.
  B es cerrado: sin entradas posteriores, sin retorno de Q a B.

**Solicitud** `g3_prescribed_sensible_request_v1`: `schema`, `end_time_s`,
`oxidation_kg`, `heat_liquid_kj`, `heat_vapour_kj`,
`emitted_vapour_temperature_k`. Tiempo físico final absoluto; masas y calor
por paso, no tasas. Es una **intención**: nunca contiene un candidato.

**Snapshot** `g3_prescribed_sensible_snapshot_v1`: `schema`,
`context_fingerprint`, `generation`, `physical_time_s`, `progress`,
`phase`, `totals`.

- `progress`: candidato íntegro del proveedor (cinco claves).
- `phase`: estado `g3_phase_sensible_state_v1` íntegro (diez claves).
- `totals`: cuentas acumuladas de §4 (once claves).

## 3. Vinculación al contenido y serialización determinista

`component_id` no basta: dos materiales con el mismo nombre y distinto Cp,
calor de fase o procedencia son contenidos distintos. El fingerprint es

`sha256(VERSION + texto canónico del contexto completo)`

y cubre programa, material de referencia, ambos perfiles (muestras
incluidas), atribución, semilla y todas las procedencias y referencias.

Forma canónica, fijada antes de implementar:

- Claves ordenadas en todos los niveles; el orden de inserción no importa.
- El orden de los arrays **sí** es contenido (muestras del programa y Cp).
- Todo número se convierte a `float` de 64 bits y se escribe como sus
  **64 bits IEEE-754 en hexadecimal**, no como texto decimal; `10` y `10.0`
  son el mismo contenido, igual que para la física, que ya los trata con
  `float()`. El cero negativo se normaliza a cero.
- Las cadenas se escriben entrecomilladas y escapadas, y se comparan
  exactas, sin recortar ni normalizar mayúsculas. Un número nunca puede
  confundirse con una cadena: los números no llevan comillas.

Sondeo previo en Godot 4.7.1, en un proyecto aislado y por el monitor,
que motiva estas reglas (no es una prueba del propietario):

- `JSON.stringify` con precisión completa **no es inyectivo**: `1e300` y
  su vecino a 1 ulp producen el mismo texto, y `1e-300` se escribe con 16
  cifras. Por eso el fingerprint nuevo liga bits exactos. El proveedor y el
  caller de referencia siguen usando su serialización JSON; sus algoritmos
  y versiones no se tocan y conservan esa limitación.
- `10` y `10.0` se serializan distinto (`10` frente a `10.0`).
- Comparar `int` con `String` mediante `!=` es un **error de script**, no
  `true`. Toda comparación de texto del propietario comprueba antes el tipo.

El contexto se guarda ya en forma canónica y es el que se entrega al
proveedor y al ledger; así el fingerprint propio del proveedor coincide
también entre dos contextos que solo difieren en `int`/`float`. No se
cambia el algoritmo ni la versión del fingerprint del proveedor.

Controles exigidos: permutar el orden de claves en cada nivel no cambia el
fingerprint; cambiar `int` por `float` de igual valor tampoco; cualquier
cambio real (un Cp, una muestra, una procedencia, la atribución, un campo
de la semilla) lo cambia y hace que un snapshot ajeno se rechace sin
escritura.

**Qué verifica y qué no.** Verifica que un snapshot declara el mismo
contenido de contexto, con esta versión del propietario, que la instancia
que lo recibe. **No** es una firma criptográfica: no hay secreto, cualquiera
puede recalcularlo. No autentica al autor, no certifica la ciencia ni la
procedencia declarada, y no prueba que la historia guardada haya ocurrido:
un snapshot editado de forma coherente con las identidades de §4 se acepta.
Tampoco distingue dos enteros que redondean al mismo `float`.

## 4. Cuentas acumuladas e identidades

`totals` guarda lo necesario para contrastar la historia térmica sin
rehacerla. Cada cuenta es un valor informado por el ledger o una
diferencia exacta entre sus estados antes/después; no hay otra integral.

| Cuenta | Signo | Significado |
| --- | --- | --- |
| `oxidized_fuel_kg`, `co2_kg`, `water_vapour_kg`, `o2_consumed_kg` | ≥0 | Masa oxidada, productos y O₂ consumido |
| `heating_liquid_kj`, `heating_vapour_kj` | ≥0 | Calentamiento prescrito aceptado: B → S |
| `release_cost_kj` | ≥0 | B debitado por liberación |
| `released_liquid_sensible_kj` | ± | Sensible que abandona el líquido con la masa liberada |
| `emitted_vapour_sensible_kj` | ± | Sensible que entra al vapor con la emisión |
| `oxidized_sensible_kj` | ± | Sensible del vapor oxidado: S → Q |
| `chemical_oxidation_heat_kj` | ≥0 | Calor químico de oxidación: A → Q |

Con M0, O₂0, B0, S_l0 de la semilla y `acc`/`rej` del proveedor, un
agregado es coherente si cierran, con las tolerancias del núcleo
(`MASS_ABS_TOL_KG`, `ENERGY_ABS_TOL_KJ`, `REL_TOL`; ninguna nueva):

- Relojes: `progress.time_s = min(physical_time_s, fin de la curva)`.
- Proveedor: `Release.propose` acepta el progreso en su propio tiempo.
- Estado: el ledger acepta `phase` en una propuesta a dt=0 (esquema,
  identidad, soporte de S, fase ausente con S cero, total finito).
- Masa: `liquid + acc = M0`; `vapour + oxidized = acc`;
  `o2 + o2_consumed = O₂0`.
- Química: recomponer `oxidized_fuel_kg` con el núcleo de referencia da
  el mismo CO₂, agua, O₂ consumido y calor químico acumulados.
- **B**: `B + heating_liquid + heating_vapour + release_cost = B0`.
- **S líquido**: `S_l + released_liquid_sensible = S_l0 + heating_liquid`.
- **S vapor**: `S_v + oxidized_sensible = heating_vapour + emitted_vapour_sensible`.
- **Q**: `Q = chemical_oxidation_heat + oxidized_sensible`.
- **Coste**: `release_cost + released_liquid_sensible = acc·Lref + emitted_vapour_sensible`.
- **Total**: A+S+B+Q del estado, según el ledger, igual al de la semilla.

Las identidades se escriben como sumas frente a la semilla, no como
diferencias, para que la tolerancia relativa escale con las cuentas.
A, S, B, Q y el calor químico quedan distinguibles: Q no es HRR químico
(incluye sensible con signo) y B no recibe nada de Q.

Estas identidades detectan una edición aislada de cualquier cuenta y la
mezcla de fase y cuentas de dos historias. **No** fijan una historia
única: por diseño el calentamiento es un grado de libertad que se posee,
no que se deduce. Es comprobación de coherencia, no de autenticidad.

## 5. Operaciones

API: `initialize(context)`, `snapshot()`, `preview_step(request)`,
`commit_step(request, expected_generation)`,
`restore(snapshot, expected_generation)`.

**Inicialización.** Valida contexto, atribución, semilla, proveedor y
ledger; construye el agregado inicial (tiempo, generación y cuentas cero)
y lo comprueba completo. Solo entonces escribe contexto y agregado. Un
rechazo deja la instancia sin inicializar (`snapshot()` vacío). Reinicializar
se rechaza: otro contexto requiere otra instancia.

**Preview.** Sin efectos; todo lo devuelto son copias profundas. Orden:

1. Comprobar el agregado vigente y la solicitud. dt físico = extremo −
   tiempo físico actual; retroceder se rechaza.
2. Extremo de fuente = menor entre extremo físico y fin de la curva.
   `Release.propose` con ese extremo.
3. `propose_phase_sensible` con dt físico, demanda del proveedor, oxidación,
   calentamientos y temperatura de emisión. Solo el B vigente.
4. `Release.acknowledge` con la liberación **aceptada por el ledger**.
5. Candidato completo: progreso, fase, cuentas acumuladas, tiempo físico y
   generación siguiente.
6. Comprobar el candidato con todas las identidades de §4. Cualquier fallo
   devuelve rechazo sin candidato.

**Commit.** Recibe intención y generación esperada; **no acepta un
candidato**. Recalcula el preview desde el agregado vigente y sustituye la
raíz una sola vez. Un preview editado, antiguo o de otra instancia no puede
aplicarse.

**No-op.** dt físico cero: preview válido sin cantidades; el commit
devuelve `no_op`, sin cambiar generación ni un solo bit del agregado,
aunque se pidan masa o calor. La solicitud se valida igualmente. Un paso
de dt positivo sin demanda, calor ni oxidación sí es un paso: avanza reloj
y generación, y las cuentas quedan idénticas bit a bit.

**Restore.** Comprueba el agregado vigente y el snapshot completo contra
el contexto de la instancia antes de escribir. Restaura a la vez relojes,
progreso, fase y cuentas; asigna generación **vigente + 1**, nunca la
guardada. Sirve también como reinicio en una instancia nueva inicializada
con el mismo contenido. No restaura ni cambia el contexto.

## 6. Política de rechazos, agotamiento y relojes

Tiempo físico y progreso de la fuente son relojes separados; el pedido al
ledger usa solo el dt físico.

| Situación | Resultado |
| --- | --- |
| Esquema, tipo, NaN/Inf, tiempo hacia atrás | Transacción inválida: nada cambia |
| Generación distinta, no entera o negativa | Conflicto: nada cambia |
| Generación en el máximo (`int` de 64 bits) | Rechazo por desbordamiento antes de escribir |
| Calentamiento mayor que B, de una fase ausente o fuera de soporte | Transacción inválida completa; el reloj no avanza |
| Temperatura de emisión fuera de soporte, coste no positivo | Transacción inválida |
| Suma o cuenta no finita | Transacción inválida |
| Demanda limitada por B, inventario u O₂ | Transacción válida: avanza el reloj, se registra el rechazo y el déficit; sin cola ni reemisión |
| Líquido agotado | S líquido queda en cero exacto; calentarlo después es inválido |
| Fin del programa | El cursor de fuente se detiene; los pasos físicos siguen con demanda cero y permiten calentar y oxidar vapor |

No existe `fire_extinguished` ni se infiere extinción del fin de la fuente.
Q nunca financia liberación, ni en el mismo paso ni después.

Cada respuesta lleva un informe derivado del agregado confirmado:
alcance, versión, estado confirmado, cuentas A/S/B/Q y total según el
ledger, calor químico y sensible oxidado acumulados, atribución y estado de
la fuente. `scientific_approval`, `predictive_evaporation_approval`,
`engine_integration` y `production_activation` son siempre `false`.

## 7. Oráculos analíticos independientes

Fijados antes del GDScript, con álgebra racional en Python que no usa
ninguna función `.gd`. Material sintético del ledger: C=0,75, H=0,25,
O=0; O₂=4 kg/kg, CO₂=2,75, agua=2,25; q_l=19000, q_v=20000,
Lref=1000 kJ/kg; Cp líquido=2 y gas=1 kJ/(kg·K), soporte 273,15-498,15 K.
Fuente constante 0,1 kg/s de 0 a 2 s, M0=1 kg, O₂0=10 kg, B0=1000 kJ.
**No son propiedades medidas de ningún combustible ni de un incendio.**

Pareja 1, **igual masa y distinta historia térmica**:

| Paso | Historia caliente | Historia de referencia |
| --- | --- | --- |
| 0→1 s | calor líquido 20 kJ; emisión 398,15 K; sin oxidar | sin calor; emisión 298,15 K; sin oxidar |
| 1→2 s | calor vapor 5 kJ; emisión 348,15 K; oxidar 0,05 kg | sin calor; emisión 298,15 K; oxidar 0,05 kg |
| 2→3 s | fuente terminada; oxidar 0,15 kg | fuente terminada; oxidar 0,15 kg |

| Tras 2 s | Caliente | Referencia |
| --- | ---: | ---: |
| Líquido / vapor / O₂ (kg) | 0,8 / 0,15 / 9,8 | 0,8 / 0,15 / 9,8 |
| CO₂ / agua (kg) | 0,1375 / 0,1125 | 0,1375 / 0,1125 |
| B (kJ) | 764 | 800 |
| Q (kJ) | 1005 | 1000 |
| S líquido / S vapor (kJ) | 16 / 15 | 0 / 0 |
| Calentamiento líquido / vapor | 20 / 5 | 0 / 0 |
| Coste de liberación | 211 | 200 |
| Sensible emitido / del líquido liberado | 15 / 4 | 0 / 0 |
| Sensible oxidado / calor químico | 5 / 1000 | 0 / 1000 |
| Total A+S+B+Q | 20000 | 20000 |

Paso intermedio caliente (1 s): líquido 0,9, vapor 0,1, B=872, S_l=18,
S_v=10, coste 108. Tras 3 s: Q caliente = **4020**, de referencia = **4000**;
B 764 frente a 800; S_l 16 frente a 0; S_v cero en ambas. Una
restauración basada solo en masa haría iguales las dos continuaciones.

Pareja 2, **igual masa e igual calentamiento total, distinto orden**
(emisión a 298,15 K, sin oxidar):

| Tras 2 s | Calentar antes de liberar | Calentar después |
| --- | ---: | ---: |
| Calentamiento líquido (kJ) | 20 | 20 |
| Líquido / vapor (kg) | 0,8 / 0,2 | 0,8 / 0,2 |
| S líquido (kJ) | 16 | 160/9 |
| B (kJ) | 784 | 7040/9 |
| Coste de liberación (kJ) | 196 | 1780/9 |
| Sensible del líquido liberado (kJ) | 4 | 20/9 |

Ni siquiera masa más calentamiento total bastan para reconstruir el estado.

Otros oráculos:

- **Frío**: S_l0=−50 kJ, emisión 273,15 K, oxidar 0,1 kg en 0→1 s.
  Coste 102,5; B=897,5; S_l=−45; S_v=0; Q=1997,5; sensible oxidado −2,5;
  del líquido liberado −5; emitido −2,5; total 19950. Sin recorte de signo.
- **Tope de B**: B0=74, calor líquido 20, emisión 398,15 K, oxidar 0,05.
  Coste por kg 1080; acepta 0,05 y rechaza 0,05; déficit 54; B=0;
  S_l=19; Q=1005; total 19074. Paso siguiente: acepta 0 con Q=1005
  disponible; rechazado acumulado 0,15; pedir calor es transacción inválida.
- **Tope de O₂**: O₂0=0,2; libera 0,1; oxida 0,05; vapor 0,05; O₂=0.
- **Agotamiento**: M0=0,2, S_l0=8 kJ, emisión 298,15 K. Coste 96 por
  paso; tras 2 s líquido 0 y S_l=0 exacto, B=808, sensible del líquido
  liberado 8, total 4808. Después: calentar líquido inválido; calentar
  vapor 10 kJ válido (S_v=10, B=798).
- **Cruce del fin**: pasos 0→1,5 y 1,5→2,5: demanda 0,05; dt físico 1;
  dt de fuente 0,5; cursor 2; tiempo físico 2,5.

## 8. Falsación predeclarada

Fixture GDScript real `tests/fixtures/g3_sensible_phase_controller.gd`.
El recuento de comprobaciones se mide, no se anticipa.

| Grupo | Control |
| --- | --- |
| W01 | Inicialización canónica, rechazo atómico, reinicialización prohibida |
| W02 | Preview repetido, sin escritura, sin alias de contexto, solicitud, snapshot, candidato o informe |
| W03 | Historia caliente: oráculos de pasos 1 y 2 y cuentas acumuladas |
| W04 | Historia de referencia y pareja de orden: masas iguales, cuentas distintas |
| W05 | Restore de ambas historias, continuación distinta, reinicio en instancia nueva frente a ejecución continua |
| W06 | Commit frente a preview manipulado, antiguo o candidato pasado como solicitud |
| W07 | Conflictos de generación, doble commit, desbordamiento en commit y restore |
| W08 | Cambio de contenido con el mismo `component_id`; snapshot ajeno rechazado |
| W09 | Serialización: orden de claves, `int`/`float`, cambio real |
| W10 | Calentamiento contado una sola vez; sin doble cuenta tras restore |
| W11 | Tope de B con coste sensible, déficit, Q no financia, calor sin B |
| W12 | Tope de O₂, inventario y agotamiento del líquido |
| W13 | Fin de la fuente con evolución posterior; cruce del fin |
| W14 | No-op a dt cero; paso positivo inactivo con cuentas bit a bit |
| W15 | Fases ausentes y masas pequeñas sin borrado |
| W16 | Sensible negativo y límites de soporte |
| W17 | NaN/Inf, tipos y esquemas en solicitud, contexto, semilla y snapshot |
| W18 | Cuentas alteradas una a una, mezcla de historias, cursor reequilibrado |
| W19 | Agregados no finitos y desbordamiento de cuentas |
| W20 | Particiones equivalentes sin calentamiento; historia larga irregular |
| W21 | Informes: estado confirmado, A/S/B/Q distinguibles, autorizaciones `false` |
| W22 | Programa lineal declarado y vínculo `modeled_component_id` |

Mutantes previstos sobre el propietario; cada uno debe morir por un fallo
conductual de la fixture con salida 1. Errores de parser, de script,
recursos ausentes, timeouts o fallos del monitor **no** cuentan.

Restaurar descartando el sensible; confirmar solo progreso; confirmar
solo fase; reconocer la masa solicitada; ignorar la generación; restaurar
la generación guardada; omitir perfiles del fingerprint; omitir la semilla;
no ordenar claves; no canonizar números; contar dos veces el calentamiento;
no pasar el calentamiento al ledger; prestar Q a B; reemitir el rechazo;
usar el dt de fuente como físico; impedir oxidar tras el fin; extrapolar
la fuente; alias del snapshot; autorización en el informe; omitir las
identidades térmicas; generación que avanza a dt cero; ignorar la
temperatura de emisión; escribir un candidato externo; omitir el vínculo
del componente modelado; perder el sensible oxidado acumulado;
inicialización no atómica; omitir la concordancia de relojes; ignorar el
sensible inicial de la semilla.

Además: control verde, originales verificados por SHA-256 tras la campaña
y revisión individual de cada superviviente. No se relaja un contrato para
obtener verde.

## 9. Implementación

Orden real: contrato y oráculos Python (2 PASS, sin Godot) → sondeo de
serialización → propietario → fixture → mutaciones. El contrato cambió una
sola vez antes de escribir el GDScript, por el sondeo de §3: bits exactos
en lugar de texto decimal y comprobación de tipo previa a comparar texto.

- `sim/fire/PrescribedSensiblePhaseController.gd` (nuevo, 446 líneas).
  Dos variables: contexto canónico inmutable y la raíz `_owned`, que se
  sustituye entera en exactamente tres sitios (inicializar, confirmar,
  restaurar) y nunca se escribe por campos.
- `tests/fixtures/g3_sensible_phase_controller.gd`: W01-W22.
- `tests/test_g3_sensible_phase_controller.py`: oráculos, ejecución real,
  composición, raíz única, aislamiento, pins y clasificador de mutantes.
- `scripts/simulation/run_g3_sensible_owner_mutations.py`.

Durante la implementación se añadió una identidad que el contrato no
enumeraba: la masa inicial guardada en `phase` debe ser exactamente la del
programa. Sin ella, esa cifra podía editarse sin que ninguna suma lo notara.

Tres pruebas históricas cambian **solo su frontera de aislamiento**: los
contratos del núcleo de masa, del proveedor y del ledger sensible admitían
como único consumidor al caller de referencia (o a ninguno); ahora admiten
además al propietario nuevo. No se suprime la exigencia: el contrato nuevo
prohíbe cargar el propietario desde proyecto, escenas, escenarios, editor,
interfaz, herramientas y complementos, y comprueba que núcleo, proveedor y
ledger no tengan ningún otro consumidor.

Módulos anteriores sin cambios, fijados por SHA-256 (LF):

| Módulo | SHA-256 |
| --- | --- |
| `FuelMassBudgetModel.gd` | `8258e2aa9b2bdabe1a126672e04e4d663f34c76cb3b78935d7db9dba1924478f` |
| `SensibleEnthalpyModel.gd` | `0340a7263591276a3fb210c570d44eba97ce0326b5c90c539be72e29b1672627` |
| `PrescribedFuelReleaseModel.gd` | `89a8c5ad8c663c9f417e23381c6cbf0d2c07bc5c56f5ad01ff7dc1ed6e0cd9fc` |
| `PrescribedPhaseBudgetController.gd` | `ce88db42f1f15325b1ae2a226a10fae01137993f8e4483f8115cd05394750667` |

Como no cambian, sus campañas históricas de mutación no se repiten; sus
fixtures reales sí se ejecutan en la regresión focal y en la global.

## 10. Fixture y falsación

Fixture real: **22 grupos W01-W22, 4663 comprobaciones PASS**. Los 87
valores fijados a partir de §7 se contrastan dos veces: dentro de la fixture y desde
Python contra la tabla predeclarada; otra prueba exige que la tabla
incrustada en la fixture sea idéntica a la de Python. La fixture pasó en
su primera ejecución; por eso su valor lo da la campaña, no ese verde.

Campaña final sobre el código final: **40/40 mutantes detectados**,
control verde, **0 supervivientes, 0 inválidos**, cinco originales intactos
por SHA-256, ningún `SCRIPT ERROR` ni `Parse Error` en 41 ejecuciones
monitorizadas. Evidencia local:
`runs/g3_sensible_owner_mutations_20261005_080646/results.json`. Propietario
`63ea6042...`, fixture `9220ea38...` en esa campaña.

Los 28 defectos predeclarados en §8 son O01-O06, O08, O10, O13, O14 y
O17-O34. Se añadieron doce sin retirar ninguno: desbordamiento de
generación al restaurar (O07); material de referencia, atribución y
programa fuera del fingerprint (O09, O11, O12); texto decimal en vez de
bits (O15); identidad de contexto del snapshot sin comprobar (O16); masa
inicial del estado sin comprobar (O35); recomposición de productos omitida
(O36); esquemas de solicitud, semilla y snapshot sin comprobar (O37-O39);
`bool` admitido como número (O40).

**Campaña anterior, que no cuenta.** La primera dio 38 detectados y
**2 inválidos**, que no se contaron como detecciones:

- O24 (alias del snapshot) acabó en timeout. La fixture guardaba el estado
  "antes" con la misma referencia que el mutante devolvía, así que la
  comparación era ciega al alias y el fallo aparecía después como error de
  script. Defecto de la fixture: ahora todo estado recordado es una copia
  profunda y se comprueba también que la respuesta de un commit no pueda
  mutar al propietario.
- O32 (inicialización no atómica) acabó en error de script. Defecto del
  mutante: dejaba una raíz incompleta que rompía su propio informe. Se
  reformuló para escribir, antes de validar la semilla, un agregado
  estructuralmente completo, que es el defecto real.

Ningún oráculo ni contrato se relajó; se repitió la campaña entera.

Mutantes **no declarados por ser equivalentes**, revisados uno a uno:
escribir la raíz en un commit a dt cero (el candidato es idéntico al
estado); quitar la guarda de desbordamiento de generación en commit (el
candidato con generación negativa se rechaza igualmente); admitir tiempo
hacia atrás (ledger y proveedor rechazan el intervalo). Son defensas
redundantes; no se presentan como detecciones.

Regresión focal con todas las fixtures G3 reales, el auditor fail-closed
de fixtures y las auditorías de estructura y UID: **917 passed /
10 skipped**, 192,00 s, basetemp externo. El módulo nuevo aislado:
23 passed, sin skips.

## 11. Cadena final sobre el código final

Tandas largas secuenciales, siempre por los lanzadores vigentes
(`godot_monitored_launch.py`, `run_reference_suite_monitored.py`); nunca
Godot directo ni un proceso ajeno terminado. APPDATA/TEMP/TMP y basetemp
nuevos bajo el temporal externo
`C:/Users/dangp/AppData/Local/Temp/simufire_sensible_owner_20261005_01/`;
las fixtures conservan su APPDATA propio histórico bajo `runs/`.
Propietario y fixture idénticos por SHA-256 a los de la campaña final
durante toda la cadena.

**Referencia (R2-1, exigida al tocar `sim/`): PASS.** 18/18 ejecuciones,
todas salida 0, informe nuevo y errores de salud vacíos; 3210,8 s sumados;
mínimo disponible antes de lanzar 6,20 GiB. Comparador salida 0:
**346/346 required PASS, 78 gaps**. ALL GUARDRAILS PASS, R2-1 incluido.
Los **160 informes de caso** mantienen SHA-256 byte a byte frente a la
copia tomada antes de la tanda. En `reference_checks.json` cambia solo la
línea `generated_at`, confirmado también estructuralmente:
2026-10-04T21:04:52Z → 2026-10-05T07:08:24Z. SHA-256 del resumen:
`feef37d2f2226ebe3ba08122747526d70fa5fb19918c600af5619546fd8bc41b`.
Logs sin `SCRIPT ERROR`, `Parse Error` ni violación de acceso. Evidencia:
`runs/reference_suite_monitored_20261005_081445/suite_log.json`.

**Producto: PASS.** `python -X utf8 scripts/check_product.py`, umbral de
6 GiB activo: **168/168**, salida 0. Registro de salud: 81 solicitudes,
81 lanzamientos, ningún fallo, rechazo, timeout, cuadro de error ni
proceso residual. Memoria previa 6,304 GiB.

**Global autoritativa: PASS en el segundo intento.**
`python -m pytest tests -q -p no:cacheprovider`, con APPDATA/TEMP/TMP y
basetemp externos nuevos (`pytest_global_2`) y el umbral de 6 GiB activo:
**3667 passed / 41 skipped / 2 xfailed / 42 subtests passed**, salida 0,
**586,90 s**. stderr vacío, ningún `FAILED` ni `ERROR`, ningún timeout,
fallo nativo ni cuadro de error; ningún proceso Godot propio residual y
ningún proceso ajeno terminado. Memoria disponible 7,981 GiB al arrancar
y 7,803 GiB al terminar, después de que el usuario liberase memoria.
Árbol sin cambios por la tanda; propietario y fixture idénticos por
SHA-256 a los de la campaña final.

**Primer intento de la global, NO verde, que no cuenta.**
**9 failed / 3658 passed / 41 skipped / 2 xfailed / 42 subtests**,
salida 1, 544,68 s. Arrancó con 6,255 GiB y la memoria disponible bajó
durante la tanda. Causa comprobada fallo a fallo en su salida, no
supuesta: los nueve son **rechazos del umbral de 6 GiB, no ejecuciones
fallidas**. Las ocho fixtures Godot reales de G3 (caller, masa, replay,
referencia, proveedor, helper, ledger y el propietario nuevo) no llegaron
a lanzarse por su aserción de memoria, con 5,897-5,910 GiB medidos en
cada una; `test_run_scenario_fail_closed` recibió del lanzador "memory
gate: 5,91 GiB available" antes de su lanzamiento simulado, y así consta
también en su registro de salud. Ninguno de los nueve tiene otra causa.
Una prueba que no se ejecuta no cuenta como aprobada. No se relajó ningún
umbral, test ni contrato y no se terminó ningún proceso ajeno; no cambió
ningún archivo entre los dos intentos.

**Evidencia reutilizada, no repetida.** Referencia, producto, focal y
mutaciones no se volvieron a ejecutar para el cierre: se comprobó en sus
registros y por SHA-256 que el código actual es el que las produjo, que
ningún archivo de implementación o prueba es posterior a ellas y que el
`.gd` más reciente de `sim/` es anterior a `reference_checks.json`.
Guardarraíles (R2-1 incluido), estilo, enlaces y `git diff --check` sí se
ejecutaron de nuevo sobre el árbol final.

**Enlaces.** Los tres documentos de la fase: 0 errores. El verificador
completo sigue fallando en dos enlaces absolutos de
`addons/sky_3d/ThirdParty.md`; ese archivo y el verificador están
versionados y sin modificar desde antes de esta fase (`c4cc99bc`,
`01610b46`). Es un fallo preexistente, ajeno, y no se corrige aquí.

**Incidencias de entorno, sin cambio de código:**

- Con `PYTHONUTF8=1` y la consola en la página de códigos 850, el monitor
  no decodifica el aviso localizado de `tasklist` y el lanzamiento aborta
  antes de arrancar Godot. Se usa `chcp 65001` en la misma orden; nada se
  lanzó en el intento abortado.
- El primer sondeo de serialización acabó en timeout porque una
  comparación `int != String` aborta el script: es el hallazgo de §3, no
  un fallo del monitor, que cerró solo su propio proceso.

## 12. Hallazgo en propietarios congelados (no bloqueó; corregido después)

Reproducido en un proyecto aislado, por el monitor, con copias exactas:
un **número donde se espera texto** hace que tres módulos anteriores
aborten con `SCRIPT ERROR: Invalid operands 'int' and 'String' in operator
'!='` en lugar de devolver un rechazo:

| Módulo | Entrada | Lugar |
| --- | --- | --- |
| `PrescribedFuelReleaseModel` | `program.mode = 1` | `_program`, línea 115 |
| `FuelMassBudgetModel.propose_phase_reference` | `material.schema = 1` | línea 167 |
| `PrescribedPhaseBudgetController` | `context.schema = 1` | `initialize`, línea 30 |

Tras el error la función devuelve un valor sin clave `valid`. Con las
mismas entradas el propietario nuevo devuelve `valid=false` sin error.

Por qué **no bloquea** esta fase: el propietario valida el tipo de cada
campo de texto antes de compararlo o delegarlo (grupo W17), y
`propose_phase_sensible` ya protegía las cadenas del material de
referencia. Ningún camino del propietario alcanza esas líneas con un
tipo erróneo. Por qué **no se corrige** aquí: exige cambiar bytes de
módulos congelados, sus pins y repetir sus campañas históricas; es una
decisión aparte. Solo afecta a entradas mal tipadas, no a resultados con
entradas válidas. Evidencia: `probe2` bajo el temporal externo de la fase.
**Queda como pendiente separado y abierto: no está corregido ni cerrado
por esta fase**, y espera decisión del usuario.

**Actualización posterior (2026-10-05): corregido en una fase aparte.** El
[hotfix de guardas de tipo](G3_D1_TYPE_GUARD_HOTFIX_2026-10-05.md),
autorizado por el usuario, corrige este defecto en los tres módulos. Lo
escrito arriba es el registro de cuando se encontró y se mantiene tal
cual: el defecto existió en `48287607` y anteriores, no es que nunca
existiera. La reproducción completa mostró que era más amplio que estos
tres casos (también la API v1 `propose`, la identidad del progreso del
proveedor y la del snapshot del caller) y que en `restore` fallaba
**abierto**: un snapshot mal tipado podía escribirse y anular la
comprobación de coherencia. Los hashes de esos tres módulos que cita §9
son los de esta fase; el hotfix los cambia y prueba que solo añade las
guardas. El propietario sensible no se modificó.

Segundo límite heredado, ya citado en §3: el fingerprint del proveedor y
el del caller de referencia usan `JSON.stringify`, que no distingue algunos
`float` vecinos. El fingerprint nuevo no tiene esa limitación; el del
proveedor, que también viaja dentro de `progress`, sí. **Este límite
sigue abierto**: el hotfix no lo toca.

## 13. Límites que siguen abiertos

- **Coherencia, no autenticidad.** Un snapshot editado respetando todas las
  identidades se acepta (W18 lo fija como límite declarado), igual que otra
  historia coherente del mismo contexto. No hay firma ni registro de pasos.
- El tiempo físico posterior al fin de la fuente no está ligado a ninguna
  cuenta: adelantarlo en un snapshot no se detecta.
- Las identidades cierran con las tolerancias del núcleo. El redondeo se
  acumula con el número de pasos; se ha comprobado una historia irregular
  de 120 pasos con reinicio a la mitad, no historias arbitrariamente largas.
  Ediciones menores que esas tolerancias no se detectan.
- B es cerrado y sintético. Tras un tope de B no vuelve a aceptarse
  liberación; no hay entradas térmicas, pérdidas ni enfriamiento.
- El calentamiento es una energía prescrita que se acepta entera o rechaza
  toda la transacción; el propietario no decide un calentamiento parcial.
- No hay temperatura: no se invierte h→T ni se predice evaporación. Sin
  energía interna de EOS, trabajo pV, O₂ o productos calientes.
- Atomicidad solo en memoria y en un hilo. Sin persistencia en disco ni
  migración entre versiones de esquema: solo existe la v1.
- `int` y `float` de igual valor son el mismo contenido; dos enteros que
  redondean al mismo `float` también.
- Los 87 valores son álgebra sintética. Nada aquí valida un material, un
  incendio, CO o FED. **CO/FED siguen OFF y NO-GO para producto.**

## 14. Siguiente gate propuesto (no iniciado ni aprobado)

Con el propietario cerrado, la cadena helper → ledger → propietario queda
completa **como contrato sintético aislado**. Lo siguiente ya no es
software de contabilidad sino evidencia física, y requiere decisiones:

1. Adaptador versionado de un perfil Cp **real** (heptano, NBS RP 2526):
   escala de 1948 y referencia 298,16 K frente a 298,15 K, Csat con V·dP
   frente a Cp isobárico, mol frente a kg. Hoy solo se admiten perfiles
   sintéticos y no debe relajarse esa etiqueta para pasarlo.
2. Elegibilidad de un B neto independiente para un benchmark térmico
   limitado (TN 2162r1/MaCFP ofrecen flujo hacia sensor, no B del líquido).

Ninguna integración en `SimulationEngine`, EOS, transporte, editor o
producto antes de esos gates. No se inicia automáticamente.

## 15. Publicación (registro documental posterior)

Commit `c6b24cbc` (`feat(fire): add isolated sensible atomic phase owner`),
once archivos, ninguno de `runs/`, sidecars `.uid`, `demo/` ni
`project.godot`. Rama shareable subida sin forzar; main integrado por
fast-forward desde `167f5c1a` y subido. Las cuatro referencias (main y
shareable, locales y remotas) coinciden en `c6b24cbc`. El remoto no había
avanzado y no hubo divergencia ni conflicto.

Después de integrar: los 80 archivos ajenos del checkout principal y los
57 `.uid` del checkout de trabajo siguen idénticos por SHA-256 a los
inventarios tomados al empezar; ALL GUARDRAILS PASS con R2-1 también desde
main; ningún proceso Godot residual. No se ejecutó ninguna suite Godot en
el checkout principal, que conserva su `project.godot` modificado.

**Aclaración del hash del resumen.** El valor `feef37d2...` de §11 es el
del archivo tal como lo genera la suite, con fin de línea CRLF. Git lo
versiona en LF y su blob es
`0559f5bcc8d3ab99171957b73a14a1e207d8ef52052481af2f78df435d3aa3e6`.
Comprobado que ambos son idénticos tras normalizar el fin de línea; quien
verifique desde un checkout limpio verá el segundo.

Este registro solo añade documentación: no cambia fuentes, pruebas ni
informes, y no altera el estado de CO/FED (OFF/NO-GO) ni los pendientes.
