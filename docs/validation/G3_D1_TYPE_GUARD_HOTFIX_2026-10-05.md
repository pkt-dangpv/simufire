# G3/D1 — Hotfix de guardas de tipo en los propietarios anteriores

Fecha: 2026-10-05. Entrada: `48287607`, rama
`codex/g3-fed-co-zonal-shareable`. Corrige el pendiente separado que dejó
abierto el [propietario sensible](G3_D1_SENSIBLE_OWNER_2026-10-05.md) en
su §12. Autorizado expresamente por el usuario para modificar tres módulos
hasta entonces congelados, **solo** con este fin.
**Estado: cerrado técnicamente; cadena completa verde (§6).**

No cambia leyes de masa, estequiometría, energía, Cp ni liberación;
tampoco tolerancias, valores físicos, esquemas, reglas de aceptación de
entradas válidas ni fingerprints heredados. No toca motor activo, EOS,
transporte, editor ni producto. CO/FED siguen OFF y NO-GO. No inicia los
gates físicos de heptano ni de presupuesto B.

## 1. Defecto

En Godot 4.7.1 comparar con `!=` o `==` un `int`, `float`, `bool`,
`Array`, `Dictionary` u `Object` con un `String` no devuelve un booleano:
es `SCRIPT ERROR: Invalid operands ... in operator`, que aborta la función
en curso. Tres propietarios comparaban campos de texto sin comprobar antes
su tipo, así que un valor mal tipado no producía un rechazo sino un aborto
y un resultado sin clave `valid`.

`null` nunca fue parte del defecto (se compara sin error y ya se
rechazaba), ni los campos que ya comprobaban `typeof` antes de comparar.

## 2. Reproducción antes del arreglo

Proyecto aislado con las fuentes exactas de `48287607` obtenidas con
`git show`, por el monitor existente, con la fixture nueva de §4. Es
ejecución real, no un rechazo del monitor ni un error de parser:

- **3981 comprobaciones, 777 fallidas, 520 errores de script**, salida 1.
- Ningún error de script en la fixture: los 520 están en los tres módulos.
- Tipos que abortan: `int` 67, `bool` 62, `Array` 62, `Dictionary` 62,
  `float` 31, `Object` 15.

El defecto era más amplio que los tres casos documentados. Sitios, todos
alcanzables desde la API pública:

| Módulo | Línea en `48287607` | Comparación sin guarda | Errores |
| --- | ---: | --- | ---: |
| `PrescribedFuelReleaseModel` | 45 | `progress.fingerprint` frente al del programa | 19 |
| `PrescribedFuelReleaseModel` | 115 | `mode`, `unit`, `outside_domain` | 93 |
| `PrescribedFuelReleaseModel` | 117, 118 | `interpolation` y `quantity` (`==`) | 37 + 37 |
| `FuelMassBudgetModel.propose` (v1) | 63 | `chemical_energy_basis` | 10 |
| `FuelMassBudgetModel.propose_phase_reference` | 167 | los seis literales del material | 87 |
| `PrescribedPhaseBudgetController.initialize` | 30 | `context.schema` | 10 |
| `PrescribedPhaseBudgetController._check_owned` | 155 | `schema` y `context_fingerprint` del snapshot | 6 |

Los 221 errores restantes son consecuencias en el propio proveedor: tras
abortar `_program`, sus tres entradas públicas acceden a `valid` sobre un
resultado vacío (líneas 30, 41 y 84).

**Consecuencia más grave: fallo abierto en `restore`.** `_check_owned` no
devuelve nada; si aborta en la línea 155 no añade ningún error, y `restore`
interpreta la lista vacía como snapshot válido. Reproducido: un snapshot
con `schema = 1`, presupuesto 5000 kJ y líquido 0,25 kg **fue escrito** en
un propietario cuyo estado real era 900 kJ y 0,9 kg. A partir de ahí su
propio `schema` ya no es texto y toda comprobación posterior del estado
aborta del mismo modo: la validación de coherencia queda anulada. Lo mismo
ocurría con un `context_fingerprint` mal tipado. `initialize`, en cambio,
abortaba antes de escribir y no dejaba estado parcial.

## 3. Cambio

Ocho líneas de comparación en siete sitios. En cada una se antepone la
comprobación de tipo a la comparación existente; los mensajes de error no
cambian. Diff total de `sim/`: 12 líneas añadidas y 8 quitadas.

```gdscript
if typeof(x) not in [TYPE_STRING, TYPE_STRING_NAME] or x != literal:
```

- No se convierte nada: ni `str()` ni `String()` sobre un campo sin
  validar. Un objeto que solo se *imprime* como el literal se rechaza.
- No se captura ni se ignora ningún error.
- Las dos comparaciones `==` del proveedor y la doble comparación del
  snapshot usan una variable booleana previa, `textual`.
- No hay funciones nuevas ni constantes nuevas: las otras nueve funciones
  del núcleo, su bloque de constantes y el bloque de la API sensible
  conservan sus bytes.

**`StringName` se sigue aceptando, sin ampliarlo.** Antes del arreglo un
`StringName` igual al literal se comparaba sin error, se aceptaba y
producía el mismo fingerprint (comprobado sobre `48287607`). Exigir
`String` estricto habría cambiado la aceptación de una entrada que ya era
válida, así que las guardas admiten los dos tipos de texto del lenguaje.
Los campos que ya exigían `String` (identificadores, procedencias) no se
tocan.

**Fingerprints heredados sin cambios**, en algoritmo, versión y valor:
los cinco valores observados antes del arreglo son idénticos después.
Sigue vigente su límite de precisión con `JSON.stringify`.

No se refactoriza `_check_owned` para que devuelva su resultado: quitar el
aborto alcanzable cierra el fallo abierto y cualquier cambio mayor saldría
del alcance. El propietario sensible no se modifica.

## 4. Pruebas

Fixture real `tests/fixtures/g3_type_guard_contracts.gd`, **12 grupos,
3981 comprobaciones PASS y 0 errores de script** sobre el código corregido.
Cada grupo corre en su propia llamada diferida y marca su final, de modo
que un módulo que aborte no impide el informe ni puede acortar un grupo
sin que se note.

| Grupo | Control |
| --- | --- |
| T01 | Proveedor: los ocho campos de texto del programa, por sus tres entradas |
| T02 | Proveedor: identidad del programa en el progreso |
| T03 | Núcleo v1: base de energía química y sus campos de texto vecinos |
| T04 | Ledger de referencia: seis literales y procedencia |
| T05 | Ledger sensible: control de regresión de la composición |
| T06 | Caller: `initialize` inválido no deja propietario; después sí inicializa |
| T07 | Caller: `restore` inválido sobre instancia viva no cambia nada; después opera |
| T08 | Caller: un tipo erróneo no desactiva la comprobación de coherencia |
| T09 | Propietario sensible: composición sin regresión |
| T10 | Fingerprints heredados: mismos valores que antes del arreglo |
| T11 | `StringName` sigue aceptándose con el mismo fingerprint |
| T12 | Validación por tipo, no por conversión: objeto impostor rechazado |

Valores mal tipados usados: `1`, `-3`, `2.5`, `true`, `false`, `[]`,
`["prescribed"]`, `{}`, `{"mode": "prescribed"}` y el objeto impostor.
Controles que no cambian: texto válido aceptado con los mismos números,
texto desconocido y vacío rechazados como antes, `null` y campo ausente
rechazados como antes. En cada rechazo se exige `valid=false`, lista de
errores no vacía, candidato vacío y entradas idénticas a su copia.

En el caller: tras 35 restauraciones rechazadas siguen intactos snapshot,
generación y contexto (el preview es idéntico al previo), y a continuación
se confirman un paso y una restauración válidos con sus cifras esperadas.

`tests/test_g3_type_guard_contracts.py` añade, sin Godot:

- **Solo cambiaron las guardas**: deshacer textualmente las ediciones
  reproduce los SHA-256 que estaban congelados (`89a8c5ad...`,
  `8258e2aa...`, `ce88db42...`). No se generaliza ni se borra ningún pin.
- Toda comparación de texto de los tres módulos lleva guarda, con recuento
  fijo (4, 2 y 2): una comparación nueva obliga a revisarla.
- Sin conversión a texto, mismos mensajes de rechazo, mismos algoritmos y
  versiones de fingerprint.

Pins que se mueven, y solo estos:

| Pin | Antes | Ahora |
| --- | --- | --- |
| `PrescribedFuelReleaseModel.gd` | `89a8c5ad...` | `db58278f2fff141d31148301095d41234f3732a66fa4140f74abfbaff483897d` |
| `FuelMassBudgetModel.gd` | `8258e2aa...` | `7ab01e1628441c048d55a45a512fc85aed8347dbd8140a29c98160e82fcd3f12` |
| `PrescribedPhaseBudgetController.gd` | `ce88db42...` | `69f74112d52ca77c7c4c3c07987d21747920b970d3e1221fa03464d6170942ed` |
| función `propose` | `098b4e02...` | `f33942b3...` |
| función `propose_phase_reference` | `499eb994...` | `8e0d764e...` |

Sin cambios y aún fijados: las otras nueve funciones del núcleo, sus
constantes, `SensibleEnthalpyModel.gd` (`0340a726...`) y
`PrescribedSensiblePhaseController.gd` (`63ea6042...`).

## 5. Falsación

**Campaña propia de las guardas.** Un mutante que reinstala una omisión
produce por construcción el error de script que se está corrigiendo, y el
clasificador genérico nunca cuenta un error de script como detección. Por
eso `scripts/simulation/run_g3_type_guard_mutations.py` usa una regla más
estrecha, no más laxa. Un mutante muere solo si se cumple todo:

- la fixture llegó a su final e imprimió su informe: sin error de parser,
  sin timeout y sin fallo del monitor;
- salió con 1 y con fallos de comportamiento, **incluido el que el mutante
  declara de antemano**;
- todo error de script está **en el archivo del módulo mutado**: ninguno
  en la fixture ni en otro módulo, y si los hay al menos uno es el error
  de operandos de la comparación reinstalada.

Cualquier otra cosa es inválida, nunca una detección: "hubo un error de
script" no basta. Los casos del clasificador, incluido el mismo error
objetivo situado en otro módulo, se fijan en
`tests/test_g3_type_guard_contracts.py`.

La regla se endureció una vez durante el cierre. La primera campaña
(`runs/g3_type_guard_mutations_20261005_154301`, 12/12) admitía errores
en cualquier módulo aislado de `res://sim/fire/`; al revisarla se exigió
el archivo mutado y **se repitió la campaña entera** con esa regla. Solo
la repetición cuenta; sus cifras coinciden con las de la primera.

Resultado sobre el código final, 14 ejecuciones monitorizadas con salud
limpia: control verde; **reproducción previa al arreglo detectada** (§2);
**12/12 mutantes detectados** por su fallo declarado, 0 supervivientes,
0 inválidos; seis originales intactos por SHA-256. Evidencia local:
`runs/g3_type_guard_mutations_20261005_174652/results.json`.

| Mutante | Qué reinstala | Fallos | Errores de script |
| --- | --- | ---: | ---: |
| G01 | literales del programa sin guarda | 252 | 213 |
| G02 | `interpolation` y `quantity` sin guarda | 168 | 166 |
| G03 | solo `quantity` sin guarda | 84 | 83 |
| G04 | identidad del progreso sin guarda | 57 | 37 |
| G05 | base de energía del núcleo v1 sin guarda | 30 | 10 |
| G06 | literales del material de referencia sin guarda | 180 | 87 |
| G07 | `schema` del contexto sin guarda | 30 | 10 |
| G08 | identidad del snapshot sin guarda (fallo abierto) | 60 | 6 |
| G09 | solo `context_fingerprint` del snapshot sin guarda | 45 | 6 |
| G10 | conversión con `str()` en el proveedor | 9 | 0 |
| G11 | conversión con `str()` en la referencia | 18 | 0 |
| G12 | conversión con `str()` en el caller | 4 | 0 |

Los tres mutantes de conversión mueren sin ningún error de script, solo
por el objeto impostor: prueban que la corrección valida el tipo y no
"acepta lo que se parezca al texto".

**Campañas históricas repetidas** con sus fixtures y su clasificador
estricto, sin cambios en estos. Cuatro mutantes necesitaron re-anclarse
porque su línea ganó una guarda (proveedor M04 y M05; referencia P08 y
P09). Conservan su significado: M04 sigue anulando la condición entera
(`if false:`); M05, P08 y P09 siguen eximiendo un único literal y
mantienen la guarda de tipo para los demás. Los cuatro murieron por las
mismas fixtures que antes.

| Campaña | Módulo mutado | Resultado |
| --- | --- | --- |
| Masa v1 | `FuelMassBudgetModel` | control verde, 10/10 |
| Referencia de fases | `FuelMassBudgetModel` | control verde, 12/12 |
| Proveedor prescrito | `PrescribedFuelReleaseModel` | control verde, 11/11 |
| Réplica de masa medida | `PrescribedFuelReleaseModel` | control verde, 11/11 |
| Caller de referencia | `PrescribedPhaseBudgetController` | control verde, 18/18 |
| Ledger sensible | `FuelMassBudgetModel` | control verde, 23/23 |

La campaña de masa y la de referencia son distintas: comparten módulo y
runner pero no fixture, mutantes ni contrato.

**Campaña del propietario sensible.** Se repite porque cambian sus
dependencias, no su módulo.

- *Primer intento, INCOMPLETO, no cuenta.* Se detuvo al lanzar O13: el
  umbral del monitor rechazó el lanzamiento con 5,99 GiB disponibles.
  Llevaba control verde y 12 de los 40; no hubo supervivientes ni
  inválidos, simplemente no se ejecutó el resto. Causa comprobada en su
  salida, no supuesta.
- *Repetición completa desde cero*, tras liberar memoria el usuario
  (8,16 GiB al arrancar): control verde, **40/40 mutantes detectados**,
  0 supervivientes, 0 inválidos, cinco originales intactos por SHA-256,
  41 registros de salud limpios y ningún `SCRIPT ERROR` ni `Parse Error`.
  No se sumaron los 12 del intento interrumpido. Evidencia local:
  `runs/g3_sensible_owner_mutations_20261005_174235/results.json`.

Regresión focal con todas las fixtures G3 reales, el auditor fail-closed
de fixtures y las auditorías de estructura y UID: **949 passed /
10 skipped**, 236,67 s. Las fixtures históricas conservan sus recuentos
fijados (proveedor 247, masa 271, caller 361, ledger 915, propietario
sensible 4663, entre otros): con entradas válidas no cambia ningún
resultado observado.

La focal anterior se ejecutó antes de endurecer el clasificador y de
ampliar sus pruebas; la global de §6 volvió a ejecutar todo, incluido el
módulo nuevo completo.

## 6. Cadena final sobre el código final

Tandas largas secuenciales, por `godot_monitored_launch.py` y
`run_reference_suite_monitored.py`; nunca Godot directo, ningún proceso
ajeno terminado y ninguna suite Godot en el checkout principal.
APPDATA/TEMP/TMP y basetemp nuevos bajo el temporal externo
`C:/Users/dangp/AppData/Local/Temp/simufire_type_hotfix_20261005_01/`;
las fixtures conservan su APPDATA propio histórico bajo `runs/`. Los seis
activos (cinco módulos y la fixture nueva) mantuvieron su SHA-256 durante
toda la cadena.

**Referencia (R2-1, exigida al tocar `sim/`): PASS.** 18/18 ejecuciones,
salida 0, informe nuevo y errores de salud vacíos; stderr vacío;
3224,8 s sumados; mínimo disponible antes de lanzar 8,14 GiB; logs de
caso sin `SCRIPT ERROR`, `Parse Error` ni violación de acceso. Comparador
salida 0: **346/346 required PASS, 78 gaps**. ALL GUARDRAILS PASS, R2-1
incluido. Evidencia: `runs/reference_suite_monitored_20261005_174751/`.

Identidad de informes, sin normalizar nada para afirmarla:

- **160 informes de caso**: archivo de trabajo idéntico byte a byte a la
  copia tomada antes de la tanda **y** a su blob de `HEAD`.
- **`reference_checks.json`**: frente a la copia previa cambia una sola
  línea de 19 269, `generated_at`
  (2026-10-05T07:08:24Z → 2026-10-05T16:41:42Z); la comparación
  estructural da esa única clave. El archivo de trabajo, tal como lo
  genera la suite, lleva CRLF y su SHA-256 es `7c624a59...e1ba2`. Git lo
  versiona en LF: ese blob es
  `217ad1849a18837c8364aae7eccf4dbcf1f4fe2a31b7b78e95daa52cd16cd2a7` y
  frente al blob de `HEAD` (`0559f5bc...`) cambia la misma única línea.
  Son dos hashes de dos secuencias de bytes distintas, no el mismo.

**Producto: PASS.** `python -X utf8 scripts/check_product.py`, umbral de
6 GiB activo: **168/168**, salida 0, stderr vacío. Registro de salud:
81 solicitudes, 81 lanzamientos, ningún fallo, rechazo, timeout, cuadro
de error, proceso residual ni proceso ajeno. Memoria previa 8,091 GiB.

**Global autoritativa: PASS.**
`python -m pytest tests -q -p no:cacheprovider`, basetemp externo nuevo:
**3700 passed / 41 skipped / 2 xfailed / 42 subtests passed**, salida 0,
**593,69 s**, stderr vacío, ningún `FAILED` ni `ERROR`, ningún timeout,
fallo nativo ni cuadro. Memoria 8,016 GiB al arrancar y 7,955 al
terminar; ningún Godot residual. Árbol sin cambios por la tanda.

Sobre el árbol final: guardarraíles con R2-1 PASS, estilo PASS,
`git diff --check` limpio y enlaces de los cuatro documentos modificados
sin errores. El verificador completo de enlaces sigue fallando solo en
los dos enlaces preexistentes de `addons/sky_3d/ThirdParty.md`, ajenos a
esta fase y sin tocar.

**Evidencia nueva frente a reutilizada.**

- *Ejecutado en el cierre, tras liberar memoria*: campaña completa del
  propietario sensible, campaña de guardas con la regla endurecida
  (incluye otra vez la reproducción previa al arreglo), referencia,
  producto, global y comprobaciones finales.
- *Reutilizado sin repetir*: las seis campañas históricas de §5 y la
  focal. Se comprobó en sus registros y por SHA-256 que los módulos y
  fixtures actuales son los que las produjeron, que ninguna de sus
  ejecuciones contiene errores de script y que sus originales quedaron
  intactos. Entre ellas y el cierre solo cambiaron el clasificador de la
  campaña de guardas y sus pruebas, que no son activos de esas campañas.

**Intentos que no cuentan**, ya descritos: la campaña del propietario
sensible interrumpida por memoria (12 de 40) y la primera campaña de
guardas, anterior al endurecimiento de su regla.

## 7. Límites que siguen abiertos

- **Precisión de los fingerprints heredados.** Proveedor y caller siguen
  serializando con `JSON.stringify`, que no distingue algunos `float`
  vecinos. Este hotfix no lo toca.
- **`_check_owned` sigue sin devolver su veredicto.** El fallo abierto se
  cierra quitando el aborto alcanzable, no rediseñando el validador. Una
  prueba estática exige guarda en toda comparación de texto de los tres
  módulos, pero un aborto futuro de otra clase volvería a no añadir
  errores. No se ha encontrado ninguno.
  **Actualización posterior: cerrado en una fase aparte**, la del
  [veredicto positivo explícito](G3_D1_POSITIVE_VERDICT_2026-10-05.md).
  Este punto se conserva como el límite que este hotfix dejó abierto.
  Esa fase reforzó además la fixture de este hotfix: retirar la guarda
  del snapshot (G08, G09) ya no permite escribir un estado, así que esos
  dos mutantes mueren ahora porque el rechazo deja de explicarse como
  desajuste de identidad. La fixture pasa de 3981 a 4013 comprobaciones;
  las cifras de §2, §4 y §5 son las de la versión de este hotfix.
- **Texto admitido.** `String` y `StringName` en los literales que ya los
  admitían; solo `String` en identificadores y procedencias, como antes.
  La diferencia entre campos es heredada y no se unifica aquí.
- **Alcance de la revisión.** Solo los tres módulos aislados. No se
  auditó el mismo patrón en el motor activo, el editor ni el producto.
- El clasificador de los mutantes de guardas reconoce el mensaje de error
  de Godot 4.7.1; otra versión del motor puede exigir revisarlo.
- Nada de esto valida un material, un incendio, CO ni FED. **CO/FED
  siguen OFF y NO-GO**; no se integra física nueva ni cambian plazos.
- Los gates físicos siguen **propuestos, no aprobados ni iniciados**:
  perfil Cp real de heptano y elegibilidad de un B neto independiente.
