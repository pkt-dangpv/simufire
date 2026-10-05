# G3/D1 — Veredicto positivo explícito en el caller de referencia

Fecha: 2026-10-05. Entrada: `089e35bf`, rama
`codex/g3-fed-co-zonal-shareable`. Cierra un límite que dejó abierto el
[hotfix de guardas de tipo](G3_D1_TYPE_GUARD_HOTFIX_2026-10-05.md) en su
§7. Afecta solo a `sim/fire/PrescribedPhaseBudgetController.gd`, el
propietario del [contrato atómico de referencia](G3_D1_ATOMIC_CALLER_CONTRACT_2026-10-04.md).
**Estado: cerrado técnicamente; cadena completa verde (§7).** Contrato y
reproducción fijados antes de implementar (§1-§3).

No cambia identidades físicas, tolerancias, esquemas, API pública,
mensajes históricos ni fingerprints. No certifica la autenticidad
histórica de un snapshot. No toca proveedor, ledger, helper Cp ni el
propietario sensible; tampoco motor activo, EOS, transporte, editor ni
producto. CO/FED siguen OFF y NO-GO. No inicia los gates físicos.

## 1. Límite

`_check_owned(value, context, errors)` devolvía `void`. Sus cinco
consumidores decidían con `errors.is_empty()`:

| Llamada | Qué valida | Qué habilita |
| --- | --- | --- |
| `initialize` | agregado inicial | escribir contexto y raíz |
| `preview_step` (1) | estado vigente | proponer un paso |
| `preview_step` (2) | candidato | devolver el candidato que `commit_step` escribe |
| `restore` (1) | estado vigente | restaurar |
| `restore` (2) | snapshot solicitado | escribirlo como raíz |

"No se registraron errores" no es lo mismo que "la validación terminó y
fue positiva". El hotfix anterior quitó los abortos conocidos, pero una
validación interrumpida que no añada errores volvía a ser aceptación.

## 2. Comprobación previa a implementar

Proyecto aislado con las fuentes exactas de `089e35bf`, por el monitor.

**Qué devuelve Godot 4.7.1 cuando una función tipada aborta** por un error
de script. No se presupone; se midió. El llamador sigue ejecutándose y
recibe el valor por defecto del tipo declarado:

| Retorno declarado | Valor recibido tras el aborto |
| --- | --- |
| `bool` | `false` |
| `Dictionary` | `{}` |
| `String` | `""` |
| `int` | `0` |
| `Variant` | `null` |

Un retorno tipado **no** garantiza que la función se ejecutó entera, pero
un `bool` abortado es `false`: sirve como veredicto si `true` solo puede
salir de la última sentencia.

**Reproducción del límite.** Sustitución controlada: una subclase de
prueba cuyo `_check_owned` no añade errores ni confirma nada. No es un
fallo de sintaxis, del monitor ni una caída nativa. Sobre `089e35bf`:

- `initialize` y `commit_step` devuelven `valid=true`.
- `restore` de un snapshot falsificado devuelve `valid=true` y **lo
  escribe**: presupuesto 900 → 5000 kJ, líquido 0,9 → 0,25 kg.

## 3. Contrato

**Validación completada y positiva.** `_check_owned` devuelve `true`. Solo
puede hacerlo su última sentencia, y solo si durante esa llamada no añadió
ningún error a la lista.

**Validación rechazada o incompleta.** Devuelve `false`: explícitamente
en cada salida anticipada, o por ser el valor que recibe el llamador si la
función no llega a su final.

**Cómo lo comprueba cada consumidor.** Ninguno llama ya a `_check_owned`
directamente ni mira la lista vacía. Todos pasan por
`_accepted(value, context, errors)`, que es positivo solo si se cumplen
las dos cosas a la vez:

- el veredicto recibido es un `bool` y es `true`;
- la lista de errores no creció durante la llamada.

Si no hay resultado positivo y ningún error lo explica, añade un
diagnóstico propio, de modo que el rechazo nunca queda sin motivo. Si el
validador ya explicó el rechazo, sus mensajes históricos se conservan y
el diagnóstico no se añade.

**Operaciones bloqueadas sin resultado positivo:**

| Operación | Exige | Sin ello |
| --- | --- | --- |
| `initialize` | agregado inicial aceptado | rechazo; no escribe contexto ni raíz; la instancia sigue sin inicializar y puede inicializarse después |
| `preview_step` | estado vigente aceptado y candidato aceptado | rechazo sin candidato; sigue siendo puro |
| `commit_step` | resultado explícito del preview: `valid` booleano y, si es `true`, candidato y paso presentes | rechazo; no sustituye la raíz ni cambia la generación |
| `restore` | estado vigente aceptado **y** snapshot solicitado aceptado | rechazo; snapshot, contexto y generación intactos |

Los conflictos de generación se siguen rechazando antes de validar nada.
Las entradas válidas no cambian: mismos resultados, mismas copias
profundas, misma atomicidad de una sola sustitución de raíz.

Es una corrección concreta de **la decisión de aceptación** de este
propietario. No protege contra cualquier fallo imaginable: un error que
aborte al propio consumidor antes de escribir sigue devolviendo un
resultado vacío en lugar de un rechazo estructurado, aunque no escribe.

## 4. Implementación

Un solo archivo de `sim/`: `PrescribedPhaseBudgetController.gd`, 34 líneas
añadidas y 16 quitadas. Doce ediciones exactas; una prueba las deshace
textualmente y recupera el SHA-256 que fijó el hotfix anterior
(`69f74112...`), de modo que no hay ningún otro cambio.

- `_check_owned(...) -> bool`. Cuenta los errores al entrar; sus cuatro
  salidas anticipadas devuelven `false` y su última sentencia es
  `return errors.size() == reported`. No contiene ningún `return true`.
- `_accepted(...) -> bool`, nuevo y único punto que consulta al
  validador. Acepta solo un veredicto `bool` verdadero de una llamada que
  no añadió errores; si no, añade
  `state validation ended without a positive verdict` cuando nada más
  explica el rechazo.
- `initialize`, `preview_step` (dos veces) y `restore` (dos veces) deciden
  por `_accepted`. En `restore` ya no se mira la lista de errores.
- `commit_step` exige del preview un `valid` booleano; si es `false` lo
  devuelve tal cual, como antes, y si no hay `valid=true` con candidato y
  paso presentes rechaza con
  `step preview returned no explicit positive result` sin escribir.

El veredicto se refiere a **esa llamada**: un error anterior en la lista
ya no corta la validación siguiente. En `restore`, cuando el estado
vigente es inválido, el snapshot solicitado se valida igualmente y aporta
sus propios mensajes. Es el único cambio visible en los textos de error y
solo ocurre en ese doble rechazo, que ya se rechazaba.

Sin cambios: API pública y firmas, esquemas, las tres raíces de escritura,
tolerancias (siguen viniendo del núcleo de masa), algoritmo y versión del
fingerprint, mensajes históricos, y las cuatro autorizaciones en `false`.
Proveedor, ledger, helper Cp y propietario sensible conservan sus hashes.

## 5. Pruebas

**Fixture normal** `tests/fixtures/g3_reference_caller_positive_verdict.gd`:
**8 grupos, 280 comprobaciones PASS y 0 errores de script**. Sustituye el
validador con una subclase de prueba; no edita el propietario ni depende
de errores de sintaxis, del monitor o de caídas.

| Grupo | Control |
| --- | --- |
| P01 | La sustitución no cambia nada: sin armar es idéntica al propietario real; 1, 2 y 2 consultas al validador por `initialize`, paso y `restore` |
| P02 | `initialize` sin veredicto: sin propietario ni contexto, entrada intacta; la misma instancia inicializa después al estado canónico |
| P03 | `preview_step`: sin veredicto del estado vigente no se construye candidato; sin veredicto del candidato se rechaza; tres previews idénticos, sin escritura ni generación |
| P04 | `commit_step`: sin veredicto no escribe; el conflicto de generación se rechaza antes de validar (0 consultas); después confirma con sus cifras |
| P05 | `restore`: exige veredicto del estado vigente y del snapshot; el snapshot falsificado de §2 **no se escribe**; snapshot, contexto y generación intactos; después restaura |
| P06 | `commit_step` ante nueve previews sin resultado positivo explícito: no escribe; un rechazo explícito pasa tal cual |
| P07 | El veredicto en sí: `true` solo para un estado coherente sin errores; cinco rechazos con `false` y explicación; un error previo no contamina la llamada |
| P08 | Sin autorizaciones ni cambios de esquema; entradas intactas |

Dos dobles distintos, porque el contrato tiene dos mitades. El
**silencioso** no añade error ni confirma: debe rechazarse con el
diagnóstico propio. El **contradictorio** afirma éxito pero añade un
error: también debe rechazarse, y sin el diagnóstico genérico.

Cuando el validador real explica el rechazo (por ejemplo `does not
close`), sus mensajes se conservan y el diagnóstico genérico no aparece.

**Control de aborto real**, fuera de la suite normal:
`tests/fixtures/g3_reference_caller_abort_control.gd`. Su doble provoca
un error de script auténtico a mitad del validador. Solo lo ejecuta el
runner, en proyecto aislado y por el monitor; ninguna prueba de pytest lo
lanza, y una prueba lo comprueba. Resultado: 48 comprobaciones PASS; el
llamador recibe `bool:false` con 0 errores añadidos, que la decisión
anterior habría tomado por aceptación; `initialize`, `preview_step`,
`commit_step` y `restore` rechazan con el diagnóstico y sin escribir,
incluido el snapshot falsificado. Emite **exactamente los 10 errores que
provoca**, todos en su línea marcada y ninguno en `sim/fire/`.

`tests/test_g3_reference_caller_positive_verdict.py` añade contratos sin
Godot: solo cambiaron las doce ediciones; el validador devuelve `true`
únicamente al final; ningún consumidor llama al validador directamente ni
escribe antes de su última puerta; `commit_step` comprueba el resultado
antes de escribir; API, esquemas, fingerprint y tolerancias intactos; el
caller sigue sin cargarse desde producto.

Pins: se mueve solo el del archivo del caller
(`69f74112...` → `41e6e36768eb386f5b9c6f9e9cb5b1e002227526cfef5d013926f8a595e4e6c6`).
La prueba del hotfix anterior que demostraba "solo cambiaron las guardas"
se encadena: deshace primero estas ediciones y después las guardas, hasta
el hash congelado original. Los demás módulos y las funciones del núcleo
siguen fijados sin cambios.

## 6. Falsación

`scripts/simulation/run_g3_positive_verdict_mutations.py`, con el
clasificador genérico estricto: solo cuenta un fallo de comportamiento de
la fixture con salida 1; un error de script nunca es una detección.

Campaña final sobre el código final, 20 ejecuciones monitorizadas con
salud limpia: control verde; **17/17 mutantes detectados**,
0 supervivientes, 0 inválidos; seis originales intactos por SHA-256.
Evidencia local:
`runs/g3_positive_verdict_mutations_20261005_201812/results.json`.

| Mutante | Qué reinstala |
| --- | --- |
| V01 | la puerta decide solo por lista de errores vacía |
| V02 | la puerta ignora los errores añadidos si el veredicto es `true` |
| V03 | `initialize` vuelve a decidir por lista vacía |
| V04 | `initialize` escribe tras un rechazo |
| V05, V06 | `preview_step` decide por lista vacía u omite validar el estado vigente |
| V07, V08 | `preview_step` decide por lista vacía u omite validar el candidato |
| V09 | `restore` decide por lista vacía sobre el estado vigente |
| V10, V11 | `restore` decide por lista vacía u omite validar el snapshot |
| V12 | `restore` escribe tras un rechazo |
| V13 | `commit_step` ignora el veredicto del preview |
| V14 | el validador confirma antes de las comprobaciones de coherencia |
| V15 | el veredicto final es `true` incondicional |
| V16, V17 | una salida anticipada devuelve `true` |

Las dos ejecuciones adicionales del runner no son mutantes ni cuentan como
detecciones: la **reproducción** sobre `089e35bf` (el estado falsificado
se escribía: reproducido) y el **control de aborto** de §5 (superado).

No declarados por ser equivalentes o no clasificables, revisados uno a uno:

- Decidir en `restore` o `preview_step` por `errors.is_empty()` *después*
  de pasar por la puerta: equivalente, porque la puerta garantiza un error
  en todo rechazo. Por eso los mutantes de "lista vacía" la esquivan.
- Quitar del todo la comprobación de candidato y paso en `commit_step`:
  produce un error de script al acceder al campo ausente, no un fallo de
  comportamiento. La comprobación está cubierta por P06.
- Devolver `true` en las dos salidas de recomposición canónica: no hay
  entrada conocida que las alcance tras pasar la validación del proveedor.

**Campaña histórica del caller**, repetida: control verde, **18/18**.
Un mutante necesitó re-anclarse: C08 omitía la validación acoplada con un
`return` vacío, que ya no compila en una función `bool`; ahora usa
`return true`, que es exactamente lo que aquel `return` significaba.

**Campaña de guardas de tipo**, repetida porque el caller es uno de sus
activos.

- *Primer intento, NO verde, no cuenta*: 10/12. G08 y G09, que retiran la
  guarda de tipo del snapshot, dejaron de morir. Causa analizada, no
  supuesta: con la guarda retirada el validador aborta, devuelve `false` y
  la nueva puerta rechaza sin escribir. El estado queda protegido aunque
  falte la guarda, así que la fixture no veía ninguna diferencia de estado
  (0 fallos) y solo quedaba el error de script, que por regla no cuenta.
  Es el efecto buscado por este arreglo, y a la vez un hueco de esa
  fixture para distinguir la guarda.
- *Corrección sin relajar el criterio*: la fixture de guardas exige ahora
  que el rechazo de una identidad mal tipada **se explique** como
  `snapshot/context identity mismatch` y no como veredicto ausente. Son 32
  comprobaciones más (3981 → 4013). G08 y G09 declaran ese fallo.
- *Repetición completa*: control verde, reproducción previa al hotfix
  detectada (809 fallos, 520 errores de script) y **12/12**, 0 inválidos.
  Evidencia: `runs/g3_type_guard_mutations_20261005_202227/results.json`.

No se repiten, porque sus activos no incluyen el caller y ningún byte suyo
cambió: masa, referencia, proveedor, réplica medida, ledger sensible y
propietario sensible. Sus fixtures reales sí se ejecutan en la focal y en
la global.

Regresión focal con todas las fixtures G3 reales, el auditor fail-closed
y las auditorías de estructura y UID: **977 passed / 10 skipped**,
198,84 s. Es anterior al refuerzo de la fixture de guardas; los tres
módulos afectados se repitieron después con Godot (74 passed) y la global
de §7 lo ejecuta todo. La fixture histórica del caller conserva sus 361
comprobaciones: con entradas válidas no cambia ningún resultado.

## 7. Cadena final sobre el código final

Tandas largas secuenciales, por `godot_monitored_launch.py` y
`run_reference_suite_monitored.py`; nunca Godot directo, ningún proceso
ajeno terminado y ninguna suite Godot en el checkout principal.
APPDATA/TEMP/TMP y basetemp nuevos bajo el temporal externo
`C:/Users/dangp/AppData/Local/Temp/simufire_positive_verdict_20261005_01/`;
las fixtures conservan su APPDATA propio histórico bajo `runs/`. Los nueve
activos (cinco módulos y cuatro fixtures) mantuvieron su SHA-256 desde la
última campaña hasta el final de la cadena.

**Referencia (R2-1, exigida al tocar `sim/`): PASS.** 18/18 ejecuciones,
salida 0, informe nuevo y errores de salud vacíos; stderr vacío;
3234,5 s sumados; mínimo disponible antes de lanzar 7,65 GiB; logs de
caso sin `SCRIPT ERROR`, `Parse Error` ni violación de acceso. Comparador
salida 0: **346/346 required PASS, 78 gaps**. ALL GUARDRAILS PASS, R2-1
incluido. Evidencia: `runs/reference_suite_monitored_20261005_202353/`.

Identidad de informes, tres nociones distintas que no se mezclan:

- *Bytes del archivo de trabajo.* Los **160 informes de caso** son
  idénticos byte a byte a la copia tomada antes de la tanda y a su blob de
  `HEAD`; no hay diferencia de fin de línea en ellos.
- *Fin de línea.* `reference_checks.json` sale de la suite con CRLF
  (SHA-256 `03d9f125...c38de`) y Git lo guarda en LF
  (`a4f154b2b4488a642cb04b37916cefad57e920f6d6a228ecd5f5f51e1a38cf1d`).
  Son dos secuencias de bytes con dos hashes; ninguno se presenta como el
  otro.
- *Contenido.* En ese resumen cambia una sola línea de 19 269,
  `generated_at` (2026-10-05T16:41:42Z → 2026-10-05T19:17:53Z), tanto
  frente a la copia previa como entre el blob nuevo y el de `HEAD`; la
  comparación estructural da esa única clave.

**Producto: PASS.** `python -X utf8 scripts/check_product.py`, umbral de
6 GiB activo: **168/168**, salida 0, stderr vacío. Registro de salud:
81 solicitudes, 81 lanzamientos, ningún fallo, rechazo, timeout, cuadro
de error, proceso residual ni proceso ajeno. Memoria previa 7,623 GiB.

**Global autoritativa: PASS.**
`python -m pytest tests -q -p no:cacheprovider`, basetemp externo nuevo:
**3727 passed / 41 skipped / 2 xfailed / 42 subtests passed**, salida 0,
**601,26 s**, stderr vacío, ningún `FAILED` ni `ERROR`, ningún timeout,
fallo nativo ni cuadro. Memoria 7,377 GiB al arrancar y 7,469 al
terminar; ningún Godot residual. Árbol sin cambios por la tanda.

Sobre el árbol final se ejecutaron de nuevo guardarraíles con R2-1,
estilo, `git diff --check` y enlaces de los documentos modificados. El
verificador completo de enlaces sigue fallando solo en los dos enlaces
preexistentes de `addons/sky_3d/ThirdParty.md`, ajenos y sin tocar.

**Evidencia nueva frente a reutilizada.** Todo lo citado en §5-§7 se
ejecutó en esta fase sobre el código final. No se reutiliza ninguna
campaña ni suite del hotfix anterior: las seis campañas que no se
repitieron (§6) no se atribuyen a esta fase, y sus cifras siguen siendo
las de su propio informe.

**Intento que no cuenta**: la primera campaña de guardas de tipo de esta
fase (10/12), descrita en §6.

## 8. Qué queda cerrado y qué sigue abierto

**Cerrado.** El límite "`_check_owned` sigue sin devolver su veredicto"
del hotfix anterior. En este propietario, aceptar o escribir un estado
exige ahora que su validación termine y devuelva un positivo explícito.

**Sigue abierto:**

- Es la decisión de aceptación de **este** propietario. No se revisó por
  analogía ningún otro validador. En particular, el propietario sensible
  decide con su propia lista de errores y no se ha modificado ni auditado
  aquí.
- `commit_step` confía en un resultado positivo explícito de
  `preview_step`; no vuelve a validar el candidato por su cuenta.
- Un error que aborte al propio consumidor, y no al validador, sigue
  devolviendo un resultado vacío en vez de un rechazo estructurado. No
  escribe, pero tampoco explica.
- Un snapshot coherente editado a mano sigue aceptándose: esto es
  coherencia, no autenticidad histórica.
- Precisión de los fingerprints heredados con `JSON.stringify`: sin tocar.
- El control de aborto y el clasificador reconocen el mensaje de error de
  Godot 4.7.1; otra versión del motor puede exigir revisarlos.
- Nada de esto valida un material, un incendio, CO ni FED. **CO/FED
  siguen OFF y NO-GO**; no hay integración nueva ni cambian plazos.
- Los gates físicos siguen **propuestos, no aprobados ni iniciados**:
  perfil Cp real de heptano y elegibilidad de un B neto independiente.
