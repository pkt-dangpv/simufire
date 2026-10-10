# G3 — Autoridad del oxígeno: M2, una selección por recinto y paso

**Fecha:** 2026-10-10 · **Línea:** G3 (CO/FED), motor · **Estado:**
implementado tras el mismo interruptor apagado de M1; **no activado**.

**Alcance.** La tercera etapa del plan de
[`G3_O2_AUTHORITY_2026-10-09.md`](G3_O2_AUTHORITY_2026-10-09.md), sobre el
inventario de sala de
[M0 y M1](G3_O2_ROOM_INVENTORY_M0_M1_2026-10-10.md): el fuego y el
sumidero comparten una selección de oxígeno por recinto y paso. Nada de M3
ni de M4. Sin emisiones nuevas y sin producto.
**CO y FED siguen OFF/NO-GO.**

Registro: [`G3_O2_SELECTION_M2_2026-10-10.json`](G3_O2_SELECTION_M2_2026-10-10.json).

## Decisión

- **Con el modo encendido hay una selección por recinto y paso**, del
  propietario del inventario. El fuego lee su concentración y el sumidero
  debita su depósito presentando esa misma selección. O2-1 y O2-4 dejan de
  existir **en este modo**.
- **Con el interruptor apagado el motor es el de antes.** Ver
  «Verificación».
- **El recinto estanco que arde deja de rechazarse:** se debita de su
  inventario como cualquier otro, y ninguna capa lo reescribe.
- **Los balances cierran** a 8,2 · 10⁻¹⁵ kg en el peor paso, con el
  criterio de M1, 1 · 10⁻⁹ kg, sin cambiar.
- **El efecto físico no es pequeño.** Al leer el fuego el mismo oxígeno
  que se debita, en dos salas la energía de 300 s baja de 142,4
  a 88,6 MJ. Es una medida, no una validación.
- **Los dos casos de casa no se pueden ejecutar enteros.** Con el modo
  encendido se rechazan a los 74,4 s por el venteo por
  sobrepresión del Salón (`pressure_venting`), una ruta que M1 no integró
  y que este encargo deja fuera. **No se ha desactivado** ni se ha
  sustituido el caso por una copia más simple. Su balance con el modo
  encendido, y C1 y C2 sobre esas trazas, **quedan sin hacer**.
- **El hueco histórico de −0,378 kg está medido y no es tránsito.** Al
  final de `o2_reopen_300` la cola de entregas está vacía. Es oxígeno que
  la ruta histórica de transporte pierde. La hipótesis publicada el 09-10
  queda refutada.

| Componente | Estado tras M2 |
| --- | --- |
| Selección única para fuego y sumidero | **Hecho**, tras el interruptor |
| Débito único, declarado una vez | **Hecho** |
| Ruta de recinto estanco | **Soportada** en el recinto sin fugas; en la casa la corta el venteo |
| Calor ajustado al oxígeno que cabe | **Sin tocar**: M3 |
| Reparto entre capas | **Sin tocar**: M4. Los números de capa siguen como auxiliares históricos |
| Venteo, PPV, HVAC, hueco exterior caliente, red de presión, banco del Test016 | **Rechazados**, como en M1 |
| Casos de casa con el modo encendido | **No ejecutables enteros** |
| Activación | **NO-GO** |

## Selección y orden real

Se escribió antes de programar. Es lo que la fixture juzga.

| Pieza | Contrato |
| --- | --- |
| Quién la posee | El propietario del inventario, [`RoomOxygenInventory.gd`](../../sim/core/RoomOxygenInventory.gd). Nadie más construye una |
| Cuándo se construye | Al abrir cada paso, antes de que corra ningún consumidor, y al armar. Una por recinto. **Nunca dentro de un paso** |
| Identidad | Identificador propio, recinto, corrida (generación) y paso. Los identificadores no se reutilizan |
| Depósito | `room_inventory`: el inventario de sala, el único que existe hasta M4 |
| Concentración | Fracción molar de la mezcla de referencia, derivada de `M` al abrir el paso. No de `o2_lower`, ni de `o2_upper`, ni de una masa de capa |
| Disponible | kg de O₂: lo que el recinto contiene menos lo que aún debe en tránsito. Ver abajo |
| Consumidores | El fuego, que la consulta, y el sumidero, que la presenta al debitar. Cada consulta queda anotada en la selección |
| Validez | El paso en que se construyó. Un débito con la de otro paso, otro recinto u otra corrida se rechaza por su nombre |

### Orden real

| | Qué pasa | Qué le pasa a `M` |
| --- | --- | --- |
| 1 | Se abre el paso: el propietario construye la selección de cada recinto | Nada |
| 2 | El fuego consulta la selección de su recinto y lee su concentración | Nada |
| 3 | El sistema de oxígeno entrega las llegadas del tránsito que vencen | Cambia por las llegadas |
| 4 | El sumidero pide **la misma** selección, calcula su demanda y su tope, y debita presentándola | Baja en el débito |
| 5 | Infiltración e intercambios entre recintos | Cambia por ellos |
| 6 | Cierre del paso: auditoría del propietario | Nada |

Entre el fuego y el sumidero el inventario **solo puede cambiar por las
llegadas del tránsito**. La coherencia se mantiene así:

- **La selección no se recalcula.** El sumidero recibe la que se construyó
  al abrir el paso, con la consulta del fuego ya anotada en ella.
- **El débito actúa sobre lo que el depósito contiene entonces**, no sobre
  la foto de la selección. La selección guarda lo que había cuando el
  fuego leyó; la diferencia es exactamente lo que llegó, y son operaciones
  del propietario.
- **El tope del sumidero no cambia:** 5 % de lo que el inventario contiene
  cuando el sumidero corre, como en M1.
- **No se adelantan las llegadas** para que los dos vean lo mismo: sería
  mover el tránsito, y no está autorizado.

### Qué significa «disponible»

`disponible = máx(0, M − obligaciones)`, donde las obligaciones son todas
las entradas negativas del tránsito hacia ese recinto: oxígeno que ya se
adelantó a otro y que este aún tiene que entregar.

- **No se gasta lo que no ha llegado:** una entrada positiva pendiente no
  cuenta.
- **Se respetan las obligaciones** que el contrato de tránsito de M1 deja
  anotadas.
- **Nunca es negativo**, y no es un recorte del estado: es una lectura.
- **Nada se cuenta dos veces:** lo que está en `M` y además se debe
  aparece una vez en `M` y se resta una vez.

**M2 lo anota y no actúa sobre él.** Ajustar el calor a lo disponible es
M3. En todos los casos medidos el débito quedó dentro de lo disponible.

El tránsito sigue siendo el de M1: un saldo con signo del intercambio
histórico, no un conjunto de masas físicas negativas. Su ley no se ha
tocado.

### Sin vuelta a la ruta histórica

Con el modo encendido, un recinto sin selección es un rechazo, también
para el fuego: no vuelve a leer un número de capa. El fuego no recibe
oxígeno, dice `o2_selection_refused` y la corrida ya está detenida. Ese
cero no es un valor físico: es la forma de fallar cerrado.

## Qué se implementó

| Archivo | Qué |
| --- | --- |
| [`sim/core/RoomOxygenInventory.gd`](../../sim/core/RoomOxygenInventory.gd) | Las selecciones: se construyen al abrir el paso, se entregan sin reconstruir y un débito tiene que presentar la de su recinto, paso y corrida, una sola vez. Tres ajustes del fuego que leen una capa pasan a rechazarse al armar |
| [`sim/fire/CombustionSystem.gd`](../../sim/fire/CombustionSystem.gd) | En el único punto donde el fuego elige su oxígeno: con el modo armado consulta la selección y lee su concentración. 16 líneas; nada más del archivo cambia |
| [`sim/core/OxygenExchangeSystem.gd`](../../sim/core/OxygenExchangeSystem.gd) | El sumidero pide la selección y debita con ella en toda ruta; desaparece el rechazo del recinto estanco; las escrituras sobre números de capa dejan de declararse consumo |
| [`sim/core/SimulationEngine.gd`](../../sim/core/SimulationEngine.gd) | Entrega el propietario al fuego solo con el modo armado |
| [`tools/run_scenario_headless.gd`](../../tools/run_scenario_headless.gd) | Una traza pasiva nueva, `o2_inventory_trace.jsonl`, solo con su opción de línea de comandos. No es `sim/` |

`CombustionSystem.gd` estaba protegido por huella hasta M1. Se levanta
**solo para este cambio**: antes `241398b06ac8…`, después
`621535487530…`. `PrescribedObjectHrrSource.gd` sigue congelado.

**No cambia:** la ley de crecimiento del fuego, el coeficiente de 0,076
kg/MJ, los filtros y umbrales de oxígeno, el tope del sumidero, los
rendimientos, el combustible, las especies, la aceptación de calor, el
transporte ni sus retardos.

**El interruptor es el de M1**, `o2_room_inventory_enabled`: sin
`@export` y apagado por defecto. Una precisión que M1 no decía: además de
una fixture, puede levantarlo el runner de escenarios de diagnóstico por
sus `engine_overrides`, como cualquier variable del motor. Así se han
corrido los casos de casa. Ningún escenario de producto, editor ni
catálogo lo nombra.

### La segunda escritura y los números de capa

Se retira **como consumo**. No se le da otro nombre: M2 no trae ningún
modelo que lo justifique.

| | Con el modo encendido |
| --- | --- |
| Débito físico | Uno, sobre `M`, por el propietario, con la selección del paso |
| Números de capa | Auxiliares históricos. Siguen su ley de siempre: el de la capa alta baja con la potencia; el de la baja, en recinto estanco, también. **Eso no es un débito y no se declara** |
| Mezcla y relajación de esos números | Las de siempre, sin cambios. No se ha añadido ninguna regla para compensar la trayectoria |
| Acumuladores | Los tres de consumo dicen lo mismo: lo que aplicó el propietario |

Por qué siguen escribiéndose los números de capa: los leen otros
consumidores que M2 no toca. El rendimiento de CO del fuego mira el de la
capa alta; la exposición y los extremos por recinto, el de la baja; y la
comparación con CFAST, los dos. Quitarles su ley movería emisiones.

Que no vuelven a declararse consumo ni gobiernan el depósito lo prueban
dos mutantes (S04 y S05) y, en el recinto estanco, que el inventario cambie
solo por operaciones del propietario mientras el número de la capa baja
también se escribe.

Hasta M4 el fuego lee **la concentración del recinto entero**. No hay
disponibilidad por capa validada, y los números de capa no son una
partición de `M`.

## Antes y después

La fixture de M2, sobre los archivos del motor de `718061f7` puestos byte
a byte y restaurados después: 79 comprobaciones,
**26 fallos**, 0 errores de script. Falla por lo que ese
motor hace:

- **El fuego lee un depósito y el sumidero debita otro.** En 480
  pasos de fuego real, el fuego leyó la concentración del inventario en
  1. El número de la capa baja era otro número en 286, y en los
  286 leyó ese.
- **El consumo se declara dos veces.** 1,7395 kg debitados y el doble
  declarado.
- **El recinto estanco que arde se rechaza** en su primer paso con
  potencia.

Una primera versión de esa corrida, con dos comprobaciones mal planteadas
por mí —una contaba solo cuando había selección y otra usaba un umbral
demasiado grueso—, se guardó aparte y no es la del registro.

## Aceptación

102 comprobaciones en 10 grupos, todas cumplidas, sobre el motor
real. Recintos de 48 y 38,4 m³, sofá de 700 kW, valores de producto.

| | Fuego real, dos salas | Recinto estanco |
| --- | --- | --- |
| Pasos | 480 | 480 |
| Pasos en que el fuego consultó su selección | 480 | 480 |
| Pasos en que leyó exactamente su concentración | 480 | 480 |
| Pasos en que esa concentración era la del inventario | 480 | 480 |
| Pasos en que el número de la capa baja era otro | 286 | 122 |
| De esos, pasos en que el fuego leyó la capa baja | 0 | 0 |
| Pasos con débito | 480 | 480 |
| Débitos sobre la selección que leyó el fuego | 480 | 480 |
| Calor | 21,60 MJ | 20,36 MJ |
| Débito | 1,6418 kg | 1,5474 kg |
| Recortado por el tope | 0,0 kg | 0,0 kg |
| Mayor tránsito | 0,1308 kg | — |
| Peor hueco por operaciones | 3,2 · 10⁻¹⁵ kg | 1,9 · 10⁻¹⁵ kg |
| Peor hueco del edificio | 8,2 · 10⁻¹⁵ kg | 1,9 · 10⁻¹⁵ kg |
| Peor hueco por forma cerrada | 8,2 · 10⁻¹⁵ kg | 1,9 · 10⁻¹⁵ kg |

- En los dos, el débito es 0,076 kg por MJ del calor del recinto y es lo
  único que se declara.
- En el recinto estanco el número de sala es el derivado del inventario
  en los 480 pasos, y **no** la mezcla de los dos números de capa, que
  fue otro número en 205.
- Los tres balances son los de M1: por operaciones, del edificio con su
  tránsito, y por forma cerrada sin leer ninguna operación.

**Identidad de una selección.** Un débito se rechaza, sin debitar nada,
con la selección del paso anterior, la de otro recinto, la de la corrida
anterior a un reinicio, ninguna, una vacía, una que nombra otro depósito,
una con identificador inventado y la misma por segunda vez.

**Ciclo de vida.** Tras un reinicio hay selecciones nuevas, de la corrida
nueva, sin consultar ni debitar; la misma corrida da la misma huella. Tras
revocar el modo no queda ninguna y el fuego vuelve a leer la capa baja.

## Casos de casa

`o2_closed` y `o2_reopen_300`, los controles de siempre, sin cambiar: la
casa de producto, un sofá en el Salón, su puerta cerrada y, en el
segundo, abierta a los 300 s.

### Con el modo encendido: rechazados por el venteo

| | `o2_closed` | `o2_reopen_300` |
| --- | --- | --- |
| Rechazo | A los 74,4 s, paso 893 | A los 74,4 s, paso 893 |
| Ruta | `pressure_venting`, Salón | `pressure_venting`, Salón |
| Pasos válidos hasta entonces | 892 | 892 |
| Peor hueco de los tres balances | 1,5 · 10⁻¹⁴ kg | 1,5 · 10⁻¹⁴ kg |
| Recintos y pasos en que el fuego leyó su selección | 5352 de 5352 | 5352 de 5352 |
| Débitos sobre esa selección | 892 de 892 | 892 de 892 |
| Calor hasta el rechazo | 3,70 MJ | 3,70 MJ |

Los dos casos son el mismo hasta los 300 s, y el rechazo llega antes.

**Qué pasa.** El Salón cerrado se presuriza al arder. Al superar el
umbral de venteo, el intercambio de gases saca humo por las fugas de las
ventanas y mete aire exterior en su lugar, diluyendo el oxígeno del
recinto. Esa dilución escribe el número de sala. Con el modo encendido la
escritura no se aplica y la corrida se detiene: en el paso del rechazo
habrían entrado 0,00020352150957 kg de aire.

**Lo que no se ha hecho, y por qué.** No se ha apagado el venteo, no se
ha subido su umbral, no se ha quitado la fuga de las ventanas y no se ha
corrido una casa más simple en su lugar. Cualquiera de esas cosas daría
un caso que cierra y que no es `o2_closed`.

**Lo que queda sin hacer por eso:** el balance de la casa con el modo
encendido y su tránsito, C1 y C2 corregidas sobre esas trazas, y el
efecto de M2 en potencia y extinción en geometría de producto.

El recinto estanco de la fixture sí corre entero porque no tiene ninguna
abertura ni fuga: sin camino al exterior no hay venteo.

### Qué rutas necesitan de verdad

Medido en la ruta histórica, con el libro pasivo por escritor que el
motor ya tiene. Escritores del número de sala:

**`o2_closed`**

| Escritor | Escrituras | Cambia el número desde | Con el modo encendido |
| --- | --- | --- | --- |
| Recorte final del motor | 64800 | — | No escribe nada |
| Venteo por sobrepresión | 3370 | 80 s | **Sin integrar: se rechaza** |
| Transporte del bucle de gases | 64800 | 10 s | No escribe nada |
| Sumidero de sala e infiltración | 64800 | 10 s | Integrado: pasa por el propietario |

**`o2_reopen_300`**

| Escritor | Escrituras | Cambia el número desde | Con el modo encendido |
| --- | --- | --- | --- |
| Recorte final del motor | 64800 | — | No escribe nada |
| Venteo por sobrepresión | 4491 | 80 s | **Sin integrar: se rechaza** |
| Transporte del bucle de gases | 64800 | 10 s | No escribe nada |
| Sumidero de sala e infiltración | 64800 | 10 s | Integrado: pasa por el propietario |

El intercambio entre recintos del sistema de oxígeno y su cola no están
en ese libro; M1 ya los puso detrás del propietario.

### Alcance mínimo adicional

Para correr estos dos casos enteros hace falta integrar: **venteo por sobrepresión**.
Nada más de lo que el libro ve.

- **Qué es integrar el venteo:** que su dilución sea una operación del
  propietario —entra aire exterior a su concentración, sale gas a la del
  recinto, por la conversión declarada— en lugar de una escritura del
  número. La ley del venteo, su umbral y su caudal no se tocan.
- **Qué hay que decidir antes:** la escritura histórica mezcla el aire
  que entra con todo el recinto y recorta a 0,209. Sin recorte, y con el
  gas que sale anotado como salida, es una operación más. Es una ruta de
  intercambio con el exterior, como la infiltración.
- **Riesgo que ya se ve:** ver el hueco histórico, abajo. El transporte
  histórico puede entregar oxígeno a una sala que ya está a la
  concentración del aire.

### El hueco histórico de −0,378 kg: medido, y no es tránsito

El diagnóstico del 09-10 dejó sin medir por qué la casa no cerraba tras
reabrir la puerta, y lo dio por «compatible con el tránsito». La traza
nueva mide la cola de entregas pendientes de la ruta histórica, que
ningún otro registro escribe:

| `o2_reopen_300`, ruta histórica | |
| --- | --- |
| Suma de los acumuladores de transporte de las seis salas, al final | −0,3778 kg |
| Oxígeno en la cola al final | 0,0000 kg |
| Mayor contenido de la cola durante la corrida | 1,688 kg, 1146 entradas |

**La cola termina vacía y faltan 0,3778 kg.** No es tránsito: es
oxígeno que el transporte histórico pierde.

- **Dónde:** en 160 pasos seguidos, entre 307,1 y 320,5 s, justo después
  de abrirse la puerta. Todos pierden; ninguno gana.
- **Con qué coincide:** en los 160 la sala contigua al Salón está en
  0,209, y la aritmética de cada paso es la de una entrega positiva que
  llega a una sala que ya está en el techo y se recorta. El propio código
  lo anota en ese punto.
- **Lo que no está hecho:** aislar esa causa con un control. Queda como
  **mecanismo coincidente**, no como causa demostrada.
- En `o2_closed`, con la puerta cerrada, la cola está siempre vacía y los
  acumuladores suman 4,3 · 10⁻¹¹ kg.

Con el modo encendido no hay ese recorte: una llegada se acredita entera
o se rechaza. Lo que haría esa misma entrega con el modo encendido —subir
una sala por encima de la concentración del aire— **no se ha podido ver**,
porque la casa se rechaza antes. Hay que mirarlo cuando el venteo esté
integrado.

Las trazas históricas son pasivas: las seis salidas de cada caso son
idénticas byte a byte a las de la corrida de identidad.

## Efecto físico

Mismo motor, mismo caso, con el modo apagado y encendido. 300 s. **Es una
medida, no un criterio**: no dice cuál se parece más a un ensayo.

| | Dos salas, apagado | Dos salas, encendido | Estanco, apagado | Estanco, encendido |
| --- | --- | --- | --- | --- |
| Pico de potencia (kW) | 762,5 | 636,1 | 610,7 | 594,0 |
| Energía acumulada (MJ) | 142,4 | 88,6 | 79,2 | 72,4 |
| Reloj del fuego (s) | 265,7 | 191,2 | 179,4 | 170,9 |
| Potencia al final (kW) | 537,1 | 113,1 | 8,9 | 6,1 |
| Menor oxígeno que leyó el fuego | 0,1765 | 0,1366 | 0,1226 | 0,1243 |
| Menor número de sala | 0,0710 | 0,1366 | 0,1241 | 0,1243 |
| Débito del recinto (kg) | 10,825 | 6,732 | 4,031 | 5,503 |
| Declarado como consumido (kg) | 16,497 | 6,732 | 6,198 | 5,503 |
| Lo que pide el calor (kg) | 10,825 | 6,732 | 6,019 | 5,503 |
| Recortado por el tope (kg) | 0,000 | 0,000 | 0,000 | 0,000 |

- **Dos salas.** Apagado, el fuego lee la capa baja, que apenas baja de
  0,176, mientras el número de sala cae a 0,071: arde sin notar
  el oxígeno que se le debita. Encendido lee lo que se debita: −38 %
  de energía y −17 % de pico.
- **Estanco.** Apagado ya leía un número que bajaba, el de la capa baja.
  El cambio es menor: −9 % de energía.
- **Extinción.** En ninguno de los cuatro se apaga el fuego en 300 s. No
  hay extinción ni reactivación que comparar.
- **Pasos rechazados:** ninguno en estos casos.

A 120 s, el mismo caso de dos salas en las tres rutas:

| | Ruta histórica | M1 | M2 |
| --- | --- | --- | --- |
| Energía (MJ) | 22,91 | 22,89 | 21,60 |
| Débito del recinto (kg) | 1,7413 | 1,7395 | 1,6418 |

La cifra histórica es la del diagnóstico del 09-10. M1 ya movía los
números al tratar 0,209 como fracción molar; M2 añade el cambio de
depósito.

### El déficit que queda para M3

**Unificar el depósito no cierra energía y oxígeno.** Cuando la demanda
supera el tope del sumidero, el oxígeno se recorta y el calor no baja.

- En los casos de fuego real de esta entrega el tope no llegó a actuar:
  recortado, 0 kg.
- En el control de tope de M1 —una demanda impuesta de 20 MW—, de 7,6 kg
  pedidos se debitan 5,337 y **2,263 kg quedan anotados como recortados**
  con el calor intacto. Sigue igual tras M2.
- En la ruta histórica, `o2_stress_cap` deja 8,22 kg sin debitar. No se
  ha corrido con el modo encendido.
- El débito quedó siempre dentro de lo disponible de su selección. Que
  pueda no caber, y qué hacer entonces, es M3.

## Mutaciones

**De la selección.** 15 mutantes de código sobre el motor real, declarados
antes de ejecutar con el grupo que debía verlos. Control en verde.
**15 de 15 muertos donde se declaró**; ningún superviviente, ninguno
inválido. Cada archivo restaurado con huella SHA-256 comprobada.

Las ocho familias pedidas con la etapa son S01, S02, S03, S04, S05, S06, S07, S08.

| | Defecto que inyecta | Archivo | Debía verlo | Resultado |
| --- | --- | --- | --- | --- |
| S01 | El sumidero vuelve a construir las selecciones a mitad de paso: la que debita no es la que leyó el fuego | `OxygenExchangeSystem.gd` | C01 | Muerto en C01; 4 comprobaciones fallidas |
| S02 | El fuego consulta la selección y recibe el número de la capa baja | `CombustionSystem.gd` | C02 | Muerto en C02; 4 comprobaciones fallidas |
| S03 | El sumidero toma su débito del número de la capa baja y el inventario de la selección no se debita | `OxygenExchangeSystem.gd` | C03 | Muerto en C03; 12 comprobaciones fallidas |
| S04 | La escritura sobre el número de la capa alta vuelve a declararse consumo | `OxygenExchangeSystem.gd` | C03 | Muerto en C03; 2 comprobaciones fallidas |
| S05 | En recinto estanco la mezcla de los números de capa se escribe sobre el inventario | `OxygenExchangeSystem.gd` | C04 | Muerto en C04; 9 comprobaciones fallidas |
| S06 | Un paso se abre con las selecciones del paso anterior | `RoomOxygenInventory.gd` | C01 | Muerto en C01; 19 comprobaciones fallidas |
| S07 | Lo que el recinto aún debe en tránsito no entra en lo que su selección da por disponible | `RoomOxygenInventory.gd` | C01 | Muerto en C01; 1 comprobación fallida |
| S08 | Con el modo encendido, un fuego sin selección vuelve a leer un número de capa | `CombustionSystem.gd` | C07 | Muerto en C07; 3 comprobaciones fallidas |
| S09 | El motor no entrega el propietario al fuego: lee como la ruta histórica con el modo encendido | `SimulationEngine.gd` | C02 | Muerto en C02; 14 comprobaciones fallidas |
| S10 | Un débito actúa sobre la selección de un paso anterior | `RoomOxygenInventory.gd` | C06 | Muerto en C06; 4 comprobaciones fallidas |
| S11 | La selección de la corrida anterior a un reinicio no se distingue de la de otro paso | `RoomOxygenInventory.gd` | C06 | Muerto en C06; 1 comprobación fallida |
| S12 | La selección de otro recinto no se distingue de la de otro paso | `RoomOxygenInventory.gd` | C06 | Muerto en C06; 1 comprobación fallida |
| S13 | La misma selección puede debitarse dos veces en un paso | `RoomOxygenInventory.gd` | C06 | Muerto en C06; 2 comprobaciones fallidas |
| S14 | Una selección que nombra otro depósito debita el inventario de sala | `RoomOxygenInventory.gd` | C06 | Muerto en C06; 2 comprobaciones fallidas |
| S15 | El modo arma con un ajuste del fuego que lee la capa alta y quedaría ignorado | `RoomOxygenInventory.gd` | C08 | Muerto en C08; 3 comprobaciones fallidas |

«Omitir el tránsito del balance» tiene dos formas: en la selección, S07; y
en el estado, el mutante T01 de M1, que sigue en su tanda.

Mutantes y control corren los grupos que juzgan, C01 a C09. El grupo C10
solo mide el efecto frente a la ruta histórica; la fixture entera es la
corrida de aceptación.

**Del inventario (M1), otra vez.** 21 mutantes sobre el motor de hoy:
**21 de 21 muertos donde se declaró**. Eran 22: sale «el recinto
estanco que arde no se rechaza», que con M2 ya no es un defecto.

## M1 sigue en pie y la ruta histórica no ha cambiado

- **La aceptación de M1, sobre el motor de hoy:** 281 comprobaciones, 0
  fallos. Eran 287: salen las seis del rechazo del recinto estanco.
- **El diagnóstico del 09-10, vuelto a medir** con el interruptor apagado:
  13 hipótesis, idénticas cifra a cifra.
- **El registro de M1 no se reescribe.** Es evidencia de su commit,
  `718061f7`, y su prueba pasa a ligarlo a esos archivos.

## Verificación

Todo secuencial, un Godot cada vez y siempre bajo el monitor, con su
mínimo de 6 GiB sin rebajar. La cadena esperó a tener 6,6 antes de cada
paso y arrancó cada uno con entre 7,65 y 8,98.
`APPDATA`, `TEMP`, `TMP` y `basetemp` fuera del repositorio.

Orden: mutaciones, identidad con el interruptor apagado, casos de casa,
registro, regresiones, referencia, guardarraíles, producto y global. La
identidad y la casa van antes que el registro, que las lee. Las dos
pasadas de pytest se repitieron después de corregir dos pruebas (ver «Lo
que salió mal por el camino»); las cifras de la tabla son las de la
pasada final, con el informe ya completo.

| Paso | Resultado |
| --- | --- |
| Fixture de M2 sobre el motor de `718061f7` | 79 comprobaciones, **26 fallos**, 0 errores de script |
| Fixture de M2 sobre este árbol | **102 comprobaciones, 0 fallos**, sin errores de script |
| Fixture de M1 sobre este árbol | **281 comprobaciones, 0 fallos** |
| Mutaciones de la selección | 15 declaradas; control en verde; **15 muertas donde se declaró**; 0 supervivientes, 0 inválidas |
| Mutaciones del inventario | 21 declaradas; **21 muertas donde se declaró**; 0 supervivientes, 0 inválidas |
| Restauración tras cada mutante | Por SHA-256, en las dos tandas |
| Regresiones de G3, fixtures que fallan cerrado, contratos de oxígeno y de la red | **1655 passed, 30 skipped, 2 xfailed** |
| **Identidad con el interruptor apagado** | **9 de 9 casos byte a byte** contra la corrida de `718061f7` |
| Diagnóstico del 09-10 vuelto a medir, interruptor apagado | 13 hipótesis, idénticas cifra a cifra |
| Banco del Test016 | Su fixture de aceptación corre dentro de las regresiones, en verde. Sus 43 mutaciones conservan sus anclas |
| Casos de casa, ruta histórica con la traza nueva | Las seis salidas de cada uno, idénticas byte a byte a las de la identidad |
| Casos de casa, modo encendido | **Rechazados** a los 74,4 s por `pressure_venting`. No es un fallo de la cadena: es el resultado |
| **Referencia completa**, monitorizada | **346 de 346** requeridas PASS; los mismos 78 huecos |
| Corpus de la referencia | 382 archivos: 381 idénticos byte a byte. El único que cambia es `reference_checks.json`, y **solo en `generated_at`** |
| Guardarraíles, con R2-1 | **Todos PASS** |
| `check_product.py` | **168 PASS** |
| Enlaces de la documentación | Ninguno roto en esta entrega. El comprobador sigue señalando dos, ajenos y anteriores, en `addons/sky_3d/ThirdParty.md` |
| `git diff --check` | Limpio |
| `python -m pytest tests -q -p no:cacheprovider` | **4460 passed, 56 skipped, 2 xfailed, 42 subtests passed** |

La referencia se regeneró porque `sim/` cambia. No se ha modificado
ninguna expectativa ni se ha establecido una línea base nueva.

**Contratos anteriores que se tocan, de forma estrecha, y se dice:**

| Contrato | Qué decía | Qué se hizo y por qué |
| --- | --- | --- |
| `CombustionSystem.gd` intacto por huella | Congelado hasta M1 | Se levanta solo para el punto donde el fuego elige su oxígeno. El registro guarda la huella de antes y la de después |
| El registro de M1 pertenece a su código | Comparaba con los archivos de hoy | Compara con los de su commit, `718061f7`. No se reescribe; la aceptación de M1 se vuelve a correr sobre el motor de hoy |
| El recinto estanco con fuego se rechaza | Control de la fixture de M1 y mutante S01 de su tanda | Salen los dos: ya es una ruta soportada. La juzgan la fixture y las mutaciones de M2 |
| El débito del propietario | Tres argumentos y la causa | Lleva además la selección. Las llamadas directas de la fixture de M1 la presentan |
| Quién nombra el modo en `sim/`, `tools/` y demás | Solo el motor | El fuego lee la clave que el motor le entrega y el runner de diagnóstico lee el informe para su traza. Ninguno nombra el interruptor |
| Fixtures que nombran el banco y la red de presión | Listas cerradas | Entra la fixture de M2, que levanta cada uno en un control negativo |

### Lo que no se ha ejecutado

- **Los dos casos de casa enteros con el modo encendido**, su balance con
  el tránsito y C1 y C2 sobre esas trazas. Los corta el venteo.
- **`o2_stress_cap` con el modo encendido.**
- **Ninguna comparación de exposición.** CO y FED siguen OFF/NO-GO.
- **Un control que aísle la causa del hueco histórico.**
- **El efecto de M2 en geometría de producto.**

### Lo que salió mal por el camino

- **La máquina estuvo limitada al 22 % de la frecuencia del procesador**
  durante buena parte del trabajo, con la sesión bloqueada: todo corría
  unas nueve veces más lento. El desarrollo, las fixtures y las primeras
  corridas de casa se hicieron así; la cadena de esta tabla, no.
- **Una tanda de casos de casa se interrumpió** al creer que la traza
  nueva era lo lento. No lo era. Al pararla, el orquestador siguió vivo y
  lanzó el caso siguiente; se detuvieron sus procesos, todos propios, y se
  borraron sus dos carpetas a medias.
- **Se lanzaron por descuido pruebas que arrancan Godot** con un caso de
  casa en marcha. Se negaron al ver el proceso y no lanzaron nada.
- **Dos comprobaciones de la fixture estaban mal planteadas** en su
  primera versión y se corrigieron antes de la corrida del registro.
- **El propietario nombraba una capa** en dos claves de entorno; lo cazó
  una prueba de M1 y se renombraron.
- **El trabajo se paró a media mañana para reiniciar el equipo**, con el
  árbol sin commitear. Toda la cadena de la tabla se corrió después, de
  una vez y sobre ese mismo árbol.
- **Dos pruebas estaban desfasadas y las cazó la primera pasada de pytest
  de la cadena**, que dio tres fallos y no el único esperado (el de este
  informe aún sin su verificación). Una, de M2, seguía afirmando que el
  hueco histórico de la casa era su tránsito: se había escrito antes de
  medirlo y ahora afirma lo medido. La otra, del banco del Test016, fijaba
  la huella de `CombustionSystem.gd`: la huella **no se ha movido**; la
  prueba compara ahora el archivo sin el bloque de M2 con la huella de
  siempre, de modo que cualquier otro cambio en ese archivo la rompe. Son
  cambios en `tests/`; el motor, las fixtures y el registro no cambiaron,
  y por eso no se repitieron mutaciones, identidad, casa ni referencia.

**Salud.** Ningún proceso de Godot al cerrar y ninguno ajeno terminado.

## Límites

- **No está activado.** Su efecto en geometría de producto no se ha
  podido medir: la casa se rechaza a los 74 s.
- **El fuego lee la concentración de todo el recinto.** Sin reparto entre
  capas, un fuego bajo una capa de humo ve el oxígeno medio, no el del
  aire que arrastra. Es la aproximación de M2 y no se disimula: M4.
- **El calor no se ajusta al oxígeno.** M3.
- **Los números de capa no conservan nada** y siguen alimentando el
  rendimiento de CO y la exposición.
- **El venteo sin integrar** deja fuera a todo recinto con fugas que se
  presurice, es decir, a la casa de producto.
- **La causa del hueco histórico** no está aislada con un control.
- Nada de esto dice que los números vayan a parecerse más a un ensayo.

## Qué queda

| | Qué | Estado |
| --- | --- | --- |
| Venteo por sobrepresión | Su dilución como operación del propietario | **Bloquea los casos de casa.** Fuera de M2 |
| M3 | Disponibilidad antes de aceptar el calor | Pendiente. La selección ya lleva lo disponible |
| M4 | El reparto `M_alta` dentro de `M` | Pendiente |
| Hueco exterior caliente, PPV, HVAC, red de presión, banco del Test016 | — | Rechazados |

## Siguiente encargo

Dos pasos, y el orden importa:

**Antes de M3, integrar el venteo.** Sin él no hay caso de producto en el
que medir M3: `o2_stress_cap`, que es donde el tope recorta, también es la
casa. Alcance: la dilución del venteo como operación de intercambio con
el exterior del propietario; los dos casos de casa enteros con el modo
encendido; su balance con el tránsito medido; C1 y C2 corregidas sobre
esas trazas; y qué hace el modo con la entrega positiva a una sala que ya
está a la concentración del aire.

**M3**, tras el mismo interruptor:

- **Antes de escribir la potencia**, comparar la demanda del calor
  propuesto con lo disponible de la selección del paso.
- **Si no cabe**, aceptar solo el calor que cabe, y que combustible y
  productos bajen en la misma transacción. Sin deuda y sin recorte
  callado.
- **El tope del 5 %** deja de recortar en silencio: o es la regla de
  disponibilidad, o desaparece. Hay que decidirlo.
- **Aceptación:** el control de tope sin oxígeno recortado; `o2_stress_cap`
  con el modo encendido sin oxígeno sin debitar; calor, combustible y
  débito describiendo la misma combustión.
- **Toca la aceptación de calor de `CombustionSystem.gd`**: es física, y
  su efecto en potencia y extinción hay que medirlo.
- **Fuera de M3:** el reparto entre capas (M4).
