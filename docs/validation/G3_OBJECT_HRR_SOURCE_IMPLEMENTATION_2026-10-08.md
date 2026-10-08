# G3-2/G3-4 - Fuente aislada de HRR del objeto ensayado: implementación

Fecha: 2026-10-08. Checkpoint de entrada: `3a105ee0` (main = origin/main,
árbol limpio). Trabajo hecho en `runs/g3_shareable`, rama
`codex/g3-fed-co-zonal-shareable`, avanzada por fast-forward desde main.

El usuario autoriza el módulo aislado, sus datos, pruebas, controles,
documentación y la cadena de verificación. **No autoriza** conectarlo al
motor, al fuego de sala, al oxígeno, al transporte, al editor ni al
producto, ni aprobar otros objetos, CO o FED.

Esta fase implementa lo que la
[selección del 07-10](G3_OBJECT_FIRE_SOURCE_SELECTION_2026-10-07.md)
dejó propuesto. Selección y reproducción siguen siendo dos cosas:

- La **selección** decidió qué ensayo puede sostener una fuente prescrita.
- Esta **reproducción** comprueba que un módulo devuelve e integra bien la
  curva de ese ensayo. No valida ninguna predicción.

## Decisión

| Cuestión | Decisión |
| --- | --- |
| Reproducir el HRR medido del Test016, aislado | **GO**, técnicamente verificado |
| Predecir un incendio desde el material | **NO-GO**, sin cambios |
| Pérdida de masa como HRR entre un calor de combustión | **NO-GO** |
| Composición, rendimientos temporales, emisiones, CO o FED | **NO-GO** |
| Aplicar la curva en un recinto o con poco oxígeno | **NO-GO** |
| Otra silla, otro objeto u otro régimen | **NO-GO** |
| Acoplarlo al motor, al oxígeno o al producto | **No autorizado, no hecho** |

La repetición Test021 sigue reservada: no se ha leído, ajustado ni
contrastado nada con ella. No se usa ningún dato de FSRI ni ninguna
propiedad del heptano. B neto no se reabre.

**Es verificación de una entrada experimental, no validación
independiente.** La tabla devuelve la corrida de la que sale.

## Qué se ha implementado

| Archivo | Qué es |
| --- | --- |
| [`sim/fire/PrescribedObjectHrrSource.gd`](../../sim/fire/PrescribedObjectHrrSource.gd) | El módulo. Sin `class_name`, sin `@export`, sin cargas ni entrada y salida |
| [`scripts/simulation/build_g3_object_hrr_source.py`](../../scripts/simulation/build_g3_object_hrr_source.py) | Importador offline: construye la tabla y el oráculo |
| [`tests/fixtures/g3_object_hrr_source_test016.json`](../../tests/fixtures/g3_object_hrr_source_test016.json) | Tabla real del Test016, contabilidad del recorte y oráculo |
| [`tests/fixtures/g3_object_hrr_source.gd`](../../tests/fixtures/g3_object_hrr_source.gd) | Fixture GDScript: tablas sintéticas y la tabla real |
| [`tests/test_g3_prescribed_object_hrr_source.py`](../../tests/test_g3_prescribed_object_hrr_source.py) | Pruebas |
| [`scripts/simulation/run_g3_object_hrr_source_mutations.py`](../../scripts/simulation/run_g3_object_hrr_source_mutations.py) | Campaña de mutaciones |

Ningún módulo existente de `sim/` se ha editado.

## Propuesta de API y por qué

El programa de masa (`PrescribedFuelReleaseModel`) es un conjunto de
funciones sin estado que revalidan la tabla entera en cada llamada. Con
tres o cien muestras no cuesta nada. Con las 3769 de esta corrida, validar
y calcular la identidad en cada paso lo haría inservible para el uso que
tendría después.

Por eso el módulo es un **propietario en memoria**, como los controladores
de fase ya existentes: valida la tabla una vez, guarda su copia y lleva su
propio reloj y sus contadores. Sigue siendo puro en el sentido que importa
aquí: no lee ni escribe archivos, no conoce el motor ni ningún nodo, no
usa reloj de pared ni azar, y su único estado es la tabla validada más un
valor (reloj y contadores) que se sustituye entero o no se toca.

| Llamada | Qué hace |
| --- | --- |
| `open(source)` | Valida toda la fuente y toma una copia. Una fuente por propietario |
| `report()` | Identidad, unidades, soporte, energía de la tabla, desconocidos y aprobaciones |
| `hrr_kw(time_s)` | Valor de la tabla en un instante desde la ignición |
| `propose(end_time_s)` | Intervalo desde el reloj confirmado hasta un final absoluto. No entrega ni cuenta |
| `confirm(proposal, accepted_energy_kj)` | Cuenta el intervalo una vez y avanza el reloj |
| `snapshot()` | Reloj y contadores, como valor |
| `restore(snapshot)` | Rebobinado o reconstrucción explícitos |
| `reset()` | Reinicio explícito en la ignición |

Toda respuesta lleva `valid` y `errors`. Un rechazo es
`{"valid": false, "errors": [...]}` y nada más.

## Contrato

| Aspecto | Qué hace el módulo |
| --- | --- |
| Propietario | `owner_id` (el objeto entero, tal como se ensayó) y `run_id`, obligatorios. Viajan en cada propuesta y en cada instantánea |
| Entrada | HRR(t) numérico. Unidades declaradas y fijas: s, kW, kJ. Otra unidad se rechaza; el módulo no convierte |
| Procedencia | Nueve campos obligatorios: conjunto de datos, versión, licencia, archivo, su SHA-256, columna, eventos del soporte, importador y huella de la tabla auditada |
| Tiempo | Desde la ignición documentada. La tabla debe empezar en cero. No existe ningún campo de desplazamiento ni de escala |
| Interpolación | Lineal entre muestras. En un nudo devuelve la muestra |
| Energía | Integral exacta de cada tramo lineal, también cuando el intervalo cruza varios nudos |
| Conversión | Constante declarada `KJ_PER_KW_S = 1.0`: kW × s = kJ |
| Fuera del soporte | Se rechaza. No extrapola, no mantiene el último valor y no recorta el intervalo |
| Duración | Estrictamente positiva. Un intervalo vacío o hacia atrás se rechaza |
| Negativos | El módulo los rechaza. El recorte lo hace el importador y queda declarado en la fuente |
| Desconocidos | Tasa de pérdida de masa, rendimientos, composición y fracción radiante valen `null`. Declarar cualquiera como número, cero incluido, se rechaza |
| Campos | Conjunto cerrado. Una masa, un calor de combustión o un rendimiento añadidos se rechazan |
| Identidad | SHA-256 del contenido completo: propietario, corrida, unidades, convenios, procedencia, tiempos y valores. Los números entran bit a bit |

Propuesta y confirmación:

| Exigencia | Cómo se cumple |
| --- | --- |
| Proponer no entrega ni cuenta | `propose` no escribe nada; se comprueba comparando el estado antes y después |
| Confirmar cuenta una vez | Cada confirmación avanza la generación; la misma propuesta ya no vale |
| Aceptada y rechazada no negativas | Lo aceptado debe estar entre cero y lo propuesto |
| Aceptada + rechazada = programada | Se comprueba en cada confirmación y al restaurar |
| Lo rechazado no hace cola | Se anota en su contador. La siguiente propuesta lleva solo la energía de su intervalo |
| Una confirmación parcial no repite el intervalo | El reloj avanza hasta el final aunque se acepte una parte o nada |
| Propuesta obsoleta, repetida, alterada o ajena | Se reconstruye desde el estado actual y debe coincidir campo a campo; si no, se rechaza |
| Un error no deja cambios a medias | El estado se sustituye en una sola asignación, después de todas las comprobaciones |
| Reconstruir y reiniciar | `restore` y `reset` son explícitos, deterministas y retiran todas las propuestas anteriores |

La energía rechazada se llama solo eso. **No es un déficit de oxígeno:**
el módulo no sabe por qué el llamador no la aceptó, y lo declara
(`recorded_not_queued_no_physical_cause_attached`).

`restore` acepta una instantánea de la misma fuente, de este propietario o
de uno anterior. La energía contada después de la instantánea se descarta
porque el llamador lo pide. Es la única manera de volver a recorrer un
intervalo.

## Datos y procedencia

Entradas, todas ya auditadas el 07-10 y comprobadas otra vez aquí:

| Entrada | Comprobación |
| --- | --- |
| `docs/literature/NIST/FCD_Test016_2026-04-07.csv` | SHA-256 `11fc0edc…0d5ac4e1`, igual al registro |
| Licencia | El registro de datos declara la licencia abierta de NIST; el importador se niega si no consta verificada |
| Página archivada del Test016 | Eventos «Ignition» (0 s) y «Fire Out» (3768 s) iguales al registro |
| Tabla de la auditoría de selección | Huella `736c8f10…1df84842`, la guardada el 07-10 |

El importador toma la tabla de la auditoría tal cual, la vuelve a leer del
CSV como decimales exactos y exige que coincidan.

| Dato de la tabla | Valor |
| --- | --- |
| Soporte del CSV | −282 a 4005 s |
| Soporte aprobado | 0 a 3768 s, de «Ignition» a «Fire Out» |
| Muestras | 3769, una por segundo |
| Origen temporal | La ignición documentada; sin desplazamiento |
| Interpolación | Lineal |
| Lecturas negativas | 11, entre los 18 y los 157 s; la menor, −0,36 kW |
| Tratamiento | Puestas a cero por el importador y declarado |
| Identidad del contenido | `5ac5edf4…8310f090` |

Integrales, en kJ, por trapecios exactos entre lecturas consecutivas:

| Integral | kJ |
| --- | --- |
| Original, con signo | 115 092,405 |
| Tras el recorte | 115 093,655 |
| Diferencia | +1,250 |

Con la regla de la ficha, que suma las muestras, salen 115 092,81 y
115 094,06 kJ. Trapecio y suma difieren en la media de las dos lecturas
de los extremos, 0,405 kJ.

**No se ha ajustado nada para alcanzar el total publicado.** La tabla
conserva su propio total, 6,3 kJ por debajo del valor impreso, que está
redondeado a 0,1 MJ.

## Oráculos y tolerancias

El oráculo se calcula en el importador con **aritmética racional exacta**
sobre el texto decimal del CSV. Comparte con el módulo la tabla y nada
más: ni código, ni integración en coma flotante, ni ninguna salida del
módulo. Ningún valor esperado se ha tomado del módulo bajo prueba.

Contiene: valores en 14 nudos y en 10 instantes entre nudos; 13 intervalos
(dentro de un tramo, cruzando varios nudos, sobre lecturas recortadas, los
dos extremos y el soporte entero); el total; y cuatro particiones del
soporte completo (un intervalo, 63 de un minuto, 3768 de un segundo y 208
irregulares que no caen en nudos), cada una con aceptación completa y con
una regla declarada de aceptación parcial y nula.

Dos comparaciones que no se mezclan:

| | Tolerancia numérica | Incertidumbre experimental |
| --- | --- | --- |
| Qué mide | Que la integración es correcta | Que la tabla es la corrida publicada |
| Margen | 10⁻⁹ kJ más 10⁻¹² relativo: 1,2 · 10⁻⁷ kJ en el total | ± 6,4 MJ, incertidumbre expandida de la ficha |
| Se compara con | El oráculo exacto | 115,1 MJ de la ficha |
| Relación | 1,8 · 10⁻¹¹ del margen experimental | — |

El margen experimental es once órdenes de magnitud mayor y **no puede
ocultar un error de integración**: los controles de la campaña mueven un
número del oráculo una parte en mil millones y la fixture lo detecta.

## Pruebas

Tablas sintéticas con respuesta analítica (un triángulo, una tabla de
nudos desiguales, constantes) y la tabla real del Test016. Nueve grupos
en la fixture GDScript:

| Grupo | Qué cubre |
| --- | --- |
| G01 | Interpolación, nudos y extremos |
| G02 | Integración dentro de un tramo y a través de varios; unidades; el total no depende de cómo se parta el intervalo |
| G03 | Aceptación completa, parcial y nula; rechazo sin cola; una sola cuenta |
| G04 | Propuestas: sin efectos, obsoletas, repetidas, alteradas y de otro propietario, corrida o tabla |
| G05 | Fuera del soporte, duración nula o negativa, sin mantener el último valor |
| G06 | Validación de la fuente: campos, unidades, convenios, procedencia, desconocidos, tipos, NaN, infinito, negativos, tiempos repetidos o desordenados |
| G07 | Instantánea, restauración, reconstrucción y reinicio |
| G08 | Identidad del contenido completo, bit a bit |
| G09 | Test016 frente al oráculo exacto, con las cuatro particiones |

Cada rechazo se comprueba dos veces: que es explícito y con motivo, y que
el estado no ha cambiado. Una llamada que abortase devolvería un valor
vacío, que la fixture cuenta como fallo y no como rechazo.

Las pruebas offline comprueban además procedencia, licencia, que la
fixture se reconstruye byte a byte, que el importador se niega a usar la
corrida reservada u otro objeto, y que nada de producto nombra el módulo.

## Mutaciones

Declaradas en el script **antes** de ejecutar, cada una con el defecto que
inyecta. Una muerte es una fixture que llegó al final e informó de
comprobaciones fallidas. Un error de sintaxis o de script, un tiempo
agotado o un fallo del monitor se anotan como corrida inválida, nunca
como muerte.

| Familia | Mutantes | Defecto |
| --- | --- | --- |
| I | 3 | Interpolación: escalón, muestra siguiente, tramo equivocado |
| N | 5 | Integración: rectángulos, tramo entero, solo el primer tramo, acumulado sin acumular |
| U | 6 | Unidades: factor de MJ, de J y de kWh; unidad de potencia, tiempo o energía sin comprobar |
| L | 6 | Convenios declarados sin comprobar: interpolación, fuera de soporte, origen, régimen, magnitud, negativos |
| S | 5 | Soporte: recorte silencioso, extrapolación, último valor mantenido, tabla desplazada, intervalo vacío |
| D | 5 | Doble confirmación: generación sin comprobar o sin avanzar, reloj sin avanzar, energía contada dos veces, confirmación sin escribir |
| O | 4 | Propietario: sin comprobar, o sin comprobar objeto, corrida o identidad |
| Q | 3 | Cola: lo rechazado vuelve en la propuesta siguiente, el intervalo queda pendiente, lo rechazado no se anota |
| F | 8 | Identidad: sin propietario, corrida, procedencia, muestras, declaración de negativos o versión; números redondeados; orden de claves |
| V | 14 | Validación: negativos, recorte dentro del módulo, no finitos, booleanos, orden, desconocido como número o como cero, campos de más, procedencia, hash, propietario, una sola muestra, aceptar de más, segunda fuente |
| R | 4 | Restaurar sin comprobar o conservando la generación; reiniciar conservando energía o generación |
| P | 3 | Proponer mueve el reloj o cuenta energía; energía alterada sin comprobar |
| X | 7 | Controles: un número del oráculo, de la identidad, de la tabla o de una respuesta analítica movido |

## Resultados de la verificación

Todo secuencial, un Godot cada vez y siempre bajo el monitor. Mínimo de
6 GiB disponibles sin rebajar; `TEMP`, `TMP` y `basetemp` fuera del
repositorio. `APPDATA` también, salvo en las pruebas de pytest, cuyo
lanzador ya existente fija el suyo bajo `runs/`.

### Fixture GDScript y pruebas del módulo

- **18 148 comprobaciones en 9 grupos, 0 fallos**, salida 0 y ningún error
  de script. El número queda fijado en la prueba Python.
- Identidad calculada por el módulo en GDScript igual a la calculada
  offline en Python: `5ac5edf4…8310f090`.
- Pico: 621,46 kW a los 1143 s, igual a la lectura.
- `tests/test_g3_prescribed_object_hrr_source.py`: **22 passed**.

Energía, en kJ:

| Cantidad | Valor |
| --- | --- |
| Total de la tabla según el módulo | 115 093,654 999 999 85 |
| Total del oráculo exacto | 115 093,655 |
| Error del módulo | −1,5 · 10⁻¹⁰ |
| Tolerancia numérica en el total | 1,2 · 10⁻⁷ |
| Peor error de un contador en las ocho campañas | 1,9 · 10⁻¹⁰ |
| Tabla menos total publicado (115,1 MJ) | −6,345, el 0,1 % de ± 6,4 MJ |

Las cuatro particiones dan el mismo total programado bit a bit. La suma
de los pasos y los contadores de aceptado y rechazado coinciden con el
oráculo en todas, con aceptación completa y parcial.

### Mutaciones

Dos campañas completas. La primera no fue limpia y se cuenta entera.

| Campaña | Declarados | Ejecutados | Detectados | Inválidos | Supervivientes |
| --- | --- | --- | --- | --- | --- |
| Primera (`…_135150`) | 73 | 73 | 65 | 7 | 1 |
| Segunda (`…_135708`) | 73 | 73 | **73** | **0** | **0** |

Qué falló en la primera y qué se cambió:

- **Siete inválidos** (I03, N01 a N04, D03 y P01). El módulo mutado
  rechazaba una propuesta y la fixture abortaba al leer un campo de una
  respuesta vacía, en una sola línea. Un aborto no es una detección y
  no se contó como tal. Era un defecto de la fixture: ahora toda lectura
  de una respuesta tolera que falte el campo y lo convierte en una
  comprobación fallida. No cambió ningún valor esperado ni el número de
  comprobaciones.
- **Un superviviente** (X03). El control movía una parte en mil millones
  un valor de 0,405 kW: 4 · 10⁻¹⁰ kW, por debajo de la tolerancia
  absoluta declarada. La fixture hacía bien en no verlo; el control
  estaba mal dimensionado. Ahora mueve el mayor valor entre nudos
  (621,225 kW, 6 · 10⁻⁷ kW) y el script se niega a ejecutarlo si el
  desplazamiento no supera cien veces la tolerancia.

Ninguno de los dos cambios tocó el módulo ni una tolerancia. La segunda
campaña se ejecutó entera después de ambos.

Restauración: los tres archivos que la campaña muta nunca se editan (se
copian a un proyecto aislado por mutante) y su SHA-256 es igual antes y
después de cada campaña. Evidencia en
`runs/g3_object_hrr_source_mutations_20261008_135708/`: plan, resultado,
salida y salud de proceso de cada corrida.

### Regresiones de G3

Los 46 módulos `tests/test_g3_*.py` más el contrato de fixtures que
fallan cerrado: **1452 passed, 18 skipped**. Los 18 omitidos son los de
siempre: nueve fixtures antiguas sin marca de PASS, dos pruebas cada una.

Una primera pasada dio 1440 passed y 12 errores, todos por tiempo
agotado en dos fixtures antiguas del motor. Este worktree no tenía caché
de importación de Godot, porque nunca se había lanzado Godot en él. Se
generó con `--import` bajo el monitor, sin modificar ningún archivo
versionado, y se repitió la pasada entera. No guardaba relación con el
módulo nuevo.

### Referencia completa, guardarraíles, producto y global

Por añadir un archivo a `sim/` se ejecutó la cadena R2-1 entera, en este
orden y después de las mutaciones:

| Paso | Resultado |
| --- | --- |
| Referencia completa monitorizada | 18/18 corridas sanas, salida 0, informe nuevo en todas; 53 min |
| Comprobaciones requeridas | **346/346 PASS** |
| Huecos conocidos | **78**, los mismos |
| Guardarraíles, con R2-1 | **ALL GUARDRAILS PASS**, también en una pasada aparte |
| `check_product.py` | **168/168 PASS** |
| Global, `python -m pytest tests -q -p no:cacheprovider` | **4271 passed**, 49 skipped, 2 xfailed, 42 subtests; salida 0; 708,53 s |

Ninguna ciencia se ha rebaselineado. El módulo no participa en ninguna
corrida de referencia: nada del motor lo carga.

La global recoge 26 pruebas más que la base: las 22 del módulo y 4 del
contrato genérico de fixtures, que ahora cubre también la nueva. Los
omitidos son datos locales o corridas de diagnóstico ausentes y las
nueve fixtures antiguas sin marca de PASS; ninguno es de esta fase.

Los seis archivos de código, datos y pruebas de la entrega tienen el
mismo SHA-256 antes de la referencia y después de la global. Después de
la global solo se escribieron en la documentación los recuentos de la
propia global.

### Diferencias de los informes

Corpus `sim/validation/reports/` frente a la base `3a105ee0`, comparando
bytes y, aparte, contenido con los finales de línea normalizados:

| | Archivos |
| --- | --- |
| Versionados | 382 |
| Idénticos byte a byte | 381 |
| Distintos solo en LF/CRLF | 0 |
| Distintos en contenido | 1: `reference_checks.json` |

En `reference_checks.json` cambia una sola línea de 19 269:
`generated_at`, de `2026-10-07T23:07:18Z` a `2026-10-08T13:05:15Z`. Las
532 comprobaciones, las 346 requeridas y los 78 huecos son los mismos.
El archivo queda con CRLF en disco y Git lo normaliza a LF al guardarlo.

### Salud de los procesos

- Todo Godot se lanzó por el monitor seguro: uno cada vez, propiedad por
  Job Object, sin cuadros de error, sin procesos ajenos y sin residuos al
  terminar.
- Memoria disponible antes de cada corrida de referencia: entre 6,63 y
  7,39 GiB. El mínimo de 6 GiB no se rebajó. La cadena esperó más de
  hora y media a que hubiera memoria antes del primer lanzamiento.
- No se terminó ningún proceso ajeno.
- Los únicos tiempos agotados fueron los dos de la primera pasada de
  regresiones, ya explicados; el monitor cerró solo su propio proceso.

## Límites

- Una sola corrida de un solo objeto, al aire libre. La repetición
  reservada difiere de esta en más que su incertidumbre, así que la tabla
  no representa «una silla A», sino esta.
- El ignitor está dentro de la curva y no se separa.
- 11 lecturas negativas puestas a cero: +1,250 kJ sobre la integral con
  signo. Es un sesgo declarado, no una corrección.
- El módulo no sabe nada de masa, composición, especies ni reparto
  radiante. No puede alimentar un balance térmico ni un cálculo de CO.
- La tolerancia numérica se comprueba contra un oráculo que usa la misma
  tabla. Un error en la tabla lo detectaría la comparación con el CSV,
  no el oráculo.
- No hay validación predictiva. Test021 sigue sin usarse.

## Decisiones de acoplamiento, abiertas

Son del usuario y ninguna se ha tomado aquí:

1. Qué hace la fuente cuando el recinto no puede aportar el oxígeno que
   su curva pide, y de quién es esa energía no entregada. El módulo solo
   la anota como rechazada, sin causa.
2. Cómo se marca la salida del régimen de aire libre. La curva deja de
   valer en un recinto viciado y no debe seguir aplicándose en silencio.
3. Cómo conviven esta fuente y el fuego de sala bajo el contrato de
   propiedad C1–C9.
4. Reparto radiante y convectivo.
5. Quién guarda la instantánea del propietario y cuándo se restaura, si
   el motor llega a usarlo: el módulo no persiste nada.

## Siguiente acción

Ninguna dentro de esta fase: la fuente aislada queda cerrada. El
acoplamiento al recinto **no está autorizado** y no se ha empezado.

Reproducir:

```text
python -m scripts.simulation.build_g3_object_hrr_source --check
python -m pytest tests/test_g3_prescribed_object_hrr_source.py -q -p no:cacheprovider
python scripts/simulation/run_g3_object_hrr_source_mutations.py
```
