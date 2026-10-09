# G3-4 - Los dos límites de oxígeno del banco Test016: diagnóstico y corrección

Fecha: 2026-10-09. Checkpoint de entrada: `1a39332a` (main = origin/main =
rama `codex/g3-fed-co-zonal-shareable`, árboles limpios). Trabajo hecho en
`runs/g3_shareable`.

El usuario autoriza diagnosticar los dos límites de oxígeno que dejó
escritos el
[banco diagnóstico](G3_OBJECT_HRR_SOURCE_COUPLING_BENCH_2026-10-08.md) y,
si se demuestra un defecto corregible dentro de ese banco, corregirlo de
forma aislada. **No autoriza** cambiar la física histórica con el banco
apagado, activar producto ni añadir emisiones.

Los dos límites:

1. El motor aplica a su número de oxígeno de la capa superior un segundo
   débito del mismo tamaño que el de sala. ¿Qué es?
2. En un recinto estanco el banco rechazaba el primer paso y dejaba
   oxígeno escrito sin calor aceptado.

La relación HRR/O₂ sigue siendo una **demanda equivalente prescrita**:
no es el consumo experimental exacto ni una estequiometría validada. El
banco sigue sin ser la combustión del mueble. CO y FED siguen OFF/NO-GO.

## Decisión

| | Qué | Decisión |
| --- | --- | --- |
| A | Interpretar el segundo débito e informarlo sin sumarlo | **Decisión A: GO.** Hecho |
| B | Que un paso rechazado no deje oxígeno de la fuente | **Decisión B: GO.** Hecho, como restricción explícita |
| C | Modificar el propietario físico del oxígeno | **Decisión C: NO-GO.** Diagnóstico y plan, sin tocar nada |

- **A.** El segundo débito no es un segundo consumo. Es la misma demanda
  escrita otra vez sobre un número auxiliar que representa una parte del
  mismo aire. El banco lo informa aparte, con un nombre que no afirma un
  desplazamiento, y declara que no se suma.
- **B.** El residuo era real y se ha reproducido. El banco pregunta ahora
  al sumidero, sin efectos, qué inventario debitaría, **antes** de
  escribir la potencia. Si no es el de sala, rechaza el intervalo sin
  haber escrito nada.
- **C.** Que el motor deje de escribir dos veces exige cambiar la ruta
  histórica del oxígeno. No está autorizado y depende de una decisión del
  usuario que sigue abierta. Se entrega el plan.

Con el interruptor apagado el motor es idéntico byte a byte al anterior.

## Gate A: los tres números de oxígeno

Reconstruido leyendo el código y siguiendo pasos reales con la sonda de
solo lectura que el motor ya tiene para el libro G3. No se ha añadido
ningún observable a `sim/`.

Los tres son números adimensionales que valen 0,209 en aire ambiente. El
motor los convierte en kilogramos multiplicándolos por una masa de aire.
Es una convención de contabilidad: 0,209 es la fracción en volumen del
aire, no su fracción en masa.

| Número | Masa de aire con la que se convierte | Qué lo escribe en el paso del oxígeno |
| --- | --- | --- |
| `room.o2`, de sala | 1,2 kg/m³ por el volumen del recinto | Sumidero de sala (tope del 5 % por paso) y renovación exterior, en una sola escritura acotada. En la ruta de penacho **se sobrescribe**, recompuesto desde los otros dos |
| `room.o2_upper`, capa superior | La del recinto por una fracción geométrica: la altura sobre la interfaz entre la altura total, con un mínimo de 0,01 | Sumidero superior (tope del 20 % por paso), arrastre del penacho desde la capa inferior, y sin fuego una relajación hacia el de sala |
| `room.o2_lower`, capa inferior | Ninguna propia. El sumidero de penacho acota con la masa de la capa inferior y aplica con la del recinto entero | Drenaje hacia el superior por la regla de arrastre, sumidero de penacho, renovación propia, y sin fuego una relajación hacia el de sala |

**No existe un inventario autoritativo.** Ya lo decía el
[contrato de oxígeno](CONTRATO_O2_2026-09-24.md) y el código lo anota en
el propio sitio de la escritura: nada liga el número superior y el
inferior al de sala. Medido aquí: en el caso base el número de sala llega
a quedar 0,00185 por debajo de la media ponderada de las dos capas. Los
tres no son una partición de una misma masa, y este informe no fabrica
una sumándolos.

Cuando la capa inferior ocupa menos del 15 % de la altura, el motor
abandona las dos capas e iguala ambos números al de sala.

### Un paso real

Caso base, paso de 2,5 s, primer paso. La fuente entrega 1,021 25 kJ, que
con 0,076 kg/MJ son 7,7615 · 10⁻⁵ kg.

| | Sumidero de sala | Sumidero superior |
| --- | --- | --- |
| Pedido | 7,7615 · 10⁻⁵ kg | 7,7615 · 10⁻⁵ kg |
| Aplicado por la escritura | 7,7615 · 10⁻⁵ kg | 7,7615 · 10⁻⁵ kg |
| Masa de aire de su número | 2400 kg | 24 kg |
| Variación de su número | 0,209 → 0,208 999 968 | 0,209 → 0,208 996 766 |
| Tope del paso | 25,08 kg, no actúa | 1,003 kg, no actúa |

La interfaz está en el techo, así que la capa superior es el 1 % del
recinto. La misma masa sobre una base cien veces menor mueve el número
cien veces más. Después el arrastre mezcla las dos capas: el número
superior sube un poco y el inferior baja.

El contador del motor que suma todos los sumideros da para ese paso
1,5523 · 10⁻⁴ kg, la suma de las dos columnas.

### Qué es el segundo débito

| Pregunta | Respuesta | Evidencia |
| --- | --- | --- |
| ¿Reduce un inventario independiente? | **No** | Su base es una parte geométrica del mismo aire del que ya debitó el de sala |
| ¿Se repite sobre una representación solapada? | **Sí** | La misma demanda, entera, en 1508 de 1508 pasos |
| ¿Solo modifica un observable auxiliar? | No solo | Ver la fila siguiente |
| ¿Afecta al régimen? | **Sí**, por el número inferior | El arrastre drena el inferior hacia el superior; la regla R2 del banco vigila el inferior |
| ¿Afecta al inventario de sala o a la energía? | **No** | Número de sala y potencia idénticos bit a bit con la otra rama |
| ¿Afecta a presión o transporte? | No determinado | No se ha medido; el banco tiene un solo recinto |

**Por qué se escribe entero.** El sumidero superior tiene dos ramas. Una
aplica toda la demanda; la otra, pensada para dos zonas, aplica un 9 %.
Toma la primera cuando no sabe que hay dos zonas, y el motor **nunca le
entrega ese indicador** al sistema de oxígeno. Es el defecto O2-4 que ya
describió [E1](E1_O2_BASE_DE_MASA_2026-09-25.md), reencontrado aquí por
otra vía.

Control causal: con el indicador puesto a mano solo en el sistema de
oxígeno, los 1508 pasos toman la otra rama y el segundo número recibe
0,787 kg, el 9,00 %. **Es un control, no un arreglo**: demuestra de qué
depende la rama y no que el 9 % sea correcto.

| | Rama histórica | Con el indicador |
| --- | --- | --- |
| Débito de sala, kg | 8,747 117 78 | 8,747 117 78 |
| Escrito sobre el número superior, kg | 8,747 117 78 | 0,787 240 60 |
| Energía aceptada, kJ | 115 093,655 | 115 093,655 |
| Serie del número de sala | — | idéntica bit a bit |
| Serie de potencia | — | idéntica bit a bit |
| Mínimo del número superior | 0,206 885 | 0,208 808 |
| Mínimo del número inferior | 0,207 976 | 0,208 906 |
| Mínimo del número de sala | 0,206 084 | 0,206 084 |

**Consecuencia para el banco.** El segundo número no toca lo que el banco
contrata, que es el débito de sala y la energía. Sí baja el número
inferior, que el banco vigila, así que puede adelantar la salida del
régimen. Es el lado prudente: el banco deja de entregar antes, no después.

### Qué significan los kilogramos publicados

| Cifra | Qué mide | Qué no es |
| --- | --- | --- |
| `oxygen_debited_kg` del banco | El débito contratado: lo que el sumidero quitó del inventario de sala | Oxígeno medido en el ensayo |
| `upper_layer_number_written_kg` del banco | Lo que el motor escribió **otra vez** sobre su número superior, en kg de la base de ese número | Un segundo consumo, ni un desplazamiento |
| Contador del motor de todos los sumideros | La suma de las escrituras sobre números solapados | Un inventario. En el caso base da 17,494 kg, el doble de un solo consumo |

Las dos cifras del banco **no se suman**. El informe lo declara en
`oxygen_numbers.never_add`. El banco publicaba antes la segunda como
`oxygen_zone_displacement_kg`; ese nombre afirmaba una interpretación que
no estaba demostrada y se ha retirado.

## Gate B: el paso rechazado

### Reproducción

Recinto de 60 m³ sin ninguna apertura, banco publicado en `1a39332a`,
junto a un motor gemelo con el interruptor apagado.

| | Paso de 2,5 s | Paso de 1,0 s |
| --- | --- | --- |
| Estado tras el primer paso | fuera del régimen | fuera del régimen |
| Energía aceptada y calor al gas | 0 | 0 |
| Débito del inventario de sala | 0 | 0 |
| Escrito sobre el número inferior, kg | 7,7615 · 10⁻⁵ | 3,078 · 10⁻⁵ |
| Escrito sobre el número superior, kg | 6,985 · 10⁻⁶ | 2,770 · 10⁻⁶ |
| Pasos con algún número distinto del gemelo | **40 de 40** | **40 de 40** |
| Diferencia del número de sala, primer paso | −1,21 · 10⁻⁶ | −4,69 · 10⁻⁷ |
| Diferencia del número de sala, paso 40 | −1,19 · 10⁻⁶ | −4,66 · 10⁻⁷ |

El residuo existe, no se disipa en 40 pasos y escala con la energía del
intervalo rechazado: lo escrito sobre el número inferior es exactamente
esa energía por 0,076.

**La cifra que publicaba el banco no era un inventario.** Daba
8,460 · 10⁻⁵ kg «debitados sin calor», que es 7,7615 · 10⁻⁵ más
6,985 · 10⁻⁶: dos escrituras sobre números con bases distintas, 72 kg y
0,72 kg. La diferencia real del número de sala frente al gemelo equivale
a 8,699 · 10⁻⁵ kg sobre su propia base. Son tres cifras y ninguna es «el
oxígeno consumido».

### Causa

1. El banco juzgaba el régimen con el estado del inicio del paso. Para el
   oxígeno preguntaba **cuánto** puede debitar el sumidero, con una cota
   de masa que toma el mínimo entre rutas. No preguntaba **de dónde**.
2. Escribía la potencia del paso en el recinto.
3. El sistema de oxígeno veía un recinto con potencia, estanco para él y
   con dos capas válidas, y tomaba su ruta de penacho: no debita el
   inventario de sala, escribe sobre el número inferior y el superior, y
   recompone el de sala desde ellos.
4. El banco comparaba después. Veía 0 kg en el inventario de sala frente
   a lo comprometido, retiraba la potencia antes del calor y salía del
   régimen. Las tres escrituras ya estaban hechas.

Además de los débitos, ese paso recorría la contabilidad de capas «con
fuego» en lugar de la de «sin fuego» que recorre el gemelo.

### Comportamiento exigido, fijado antes de corregir

- Un intervalo aceptado tiene su débito equivalente y su calor.
- Un intervalo rechazado no deja consumo de la fuente ni calor.
- Programada = aceptada + rechazada.
- Sin cola, sin combustible pendiente, sin inquemados y sin relevo.
- El reloj de la fuente sigue con su contrato.
- La invalidez queda enclavada hasta un reinicio.
- La ventilación y la mezcla del recinto siguen siendo las del motor: no
  se exige congelar el recinto, sino que sea el del gemelo.

### Corrección

| Archivo | Cambio |
| --- | --- |
| [`sim/core/OxygenExchangeSystem.gd`](../../sim/core/OxygenExchangeSystem.gd) | Función nueva `fire_sink_plan`: dice qué ruta tomaría el sumidero en un recinto, repitiendo una a una las condiciones del paso. No escribe nada y el paso no la llama |
| [`sim/core/SimulationEngine.gd`](../../sim/core/SimulationEngine.gd) | Un quinto enganche que entrega esa pregunta al banco |
| [`sim/fire/PrescribedThermalSourceCoupling.gd`](../../sim/fire/PrescribedThermalSourceCoupling.gd) | Pregunta la ruta y el coeficiente **antes** de escribir la potencia; informe reclasificado |

No se devuelve oxígeno, no se restaura el recinto y no se ajusta ningún
acumulador. El intervalo se rechaza antes de que exista nada que deshacer.

**Restricción explícita.** El banco solo acepta un intervalo si el
sumidero debitaría el inventario de sala con el coeficiente declarado.
Queda fuera el recinto estanco para el sumidero, es decir, sin apertura
al exterior ni al interior que supere el 1 % de su referencia, mientras
tenga dos capas válidas.

- *Por qué.* El contrato del banco es `O₂ = energía × coeficiente` sobre
  el inventario de sala. La ruta de penacho escribe un número que no
  tiene una masa propia: acota con una y aplica con otra. Sobre ella ese
  contrato no se puede enunciar.
- *Qué caso deja de estar soportado.* Ninguno que lo estuviera: ese
  recinto ya salía del régimen en el primer paso. Lo que cambia es que
  ahora sale limpio.
- *No es una prueba omitida.* El control negativo se ejecuta: el recinto
  estanco, junto a su gemelo, en la fixture de aceptación.
- *Prudencia.* La pregunta es qué haría el sumidero **si** hubiera
  potencia. Un intervalo de energía cero en un recinto estanco también se
  rechaza.

**Lo que no se puede garantizar.** El banco no puede deshacer una
escritura del motor. Si el sumidero hiciera algo distinto de lo que dijo,
el banco retira la potencia antes del calor, **falla**, detiene la
simulación y lista lo escrito número a número, sin sumarlo. No lo
presenta como un rechazo limpio. La pregunta y el paso usan las mismas
condiciones en el mismo paso, y coinciden en todos los pasos aceptados de
la fixture; el caso se prueba forzando una respuesta falsa.

Un coeficiente declarado distinto del que usa el sumidero se detecta por
la misma pregunta, también antes de escribir.

## Campaña causal

Hipótesis escritas en
[el lanzador](../../scripts/simulation/run_g3_object_hrr_oxygen_diagnosis.py)
antes de ejecutar, cada una con lo que discrimina, lo que la confirmaría
y lo que la refutaría. Los mismos predicados juzgan las dos corridas.
Registros:
[antes](G3_OBJECT_HRR_OXYGEN_DIAGNOSIS_BEFORE_2026-10-09.json), sobre
`1a39332a`, y
[después](G3_OBJECT_HRR_OXYGEN_DIAGNOSIS_AFTER_2026-10-09.json).

| | Hipótesis | Antes | Después |
| --- | --- | --- | --- |
| A1 | El número superior recibe la demanda entera porque el sumidero no sabe de dos zonas | Se cumple | Se cumple |
| A2 | Los números superior y de sala se solapan y no son una partición | Se cumple | Se cumple |
| A3 | La segunda escritura no llega al inventario de sala ni a la energía | Se cumple | Se cumple |
| A4 | Sí llega a la regla del régimen, por el número inferior | Se cumple | Se cumple |
| A5 | El contador de todos los sumideros es una suma de escrituras solapadas | Se cumple | Se cumple |
| A6 | Pedido, aplicado y variación del estado son tres cifras, y coinciden si no hay tope | Se cumple | Se cumple |
| B1 | Sin fuente y con energía cero el motor es el mismo | Se cumple | Se cumple |
| B2 | En el recinto estanco el sumidero toma otra ruta después de escrita la potencia | Se cumple | **Refutada: ya no hay escritura** |
| B3 | Un paso rechazado no deja rastro de la fuente | **Falsa: el defecto** | **Se cumple** |
| B4 | El rastro escala con la energía del intervalo rechazado | Se cumple | **Refutada: ya no hay rastro** |
| B5 | Tras salir por una regla no se debita nada, tampoco al recuperar el oxígeno | Se cumple | Se cumple |

Que B2 y B4 dejen de cumplirse y B3 pase a cumplirse estaba declarado
antes de la segunda corrida.

Casos de la campaña: fuente deshabilitada, fuente habilitada con energía
cero, recinto abierto que completa, recinto estanco, recinto con rendija,
recuperación posterior del oxígeno sin reactivación, y dos pasos de
tiempo, 2,5 y 1,0 s.

Lo que la campaña no convierte en explicación: el control de A1 hace
desaparecer el segundo débito entero, pero solo prueba de qué depende la
rama.

## Antes y después

El mismo recinto estanco de 60 m³, junto a su gemelo con el interruptor
apagado, 40 pasos:

| | Antes, 2,5 s | Después, 2,5 s | Antes, 1,0 s | Después, 1,0 s |
| --- | --- | --- | --- | --- |
| Causa de la salida | El débito no es el comprometido | El sumidero no debitaría el inventario de sala | Igual | Igual |
| Momento en que se decide | Después del sumidero | Antes de escribir la potencia | Igual | Igual |
| Potencia escrita en el recinto | Sí, y retirada después | No | Sí | No |
| Escrito sobre el número inferior, kg | 7,7615 · 10⁻⁵ | 0 | 3,078 · 10⁻⁵ | 0 |
| Escrito sobre el número superior, kg | 6,985 · 10⁻⁶ | 0 | 2,770 · 10⁻⁶ | 0 |
| Pasos distintos del gemelo | 40 de 40 | **0 de 40** | 40 de 40 | **0 de 40** |
| Energía aceptada y calor al gas | 0 | 0 | 0 | 0 |
| Energía rechazada del primer paso, kJ | 1,021 25 | 1,021 25 | — | — |

Después de la corrección los tres números de oxígeno del recinto son los
del gemelo bit a bit en los 40 pasos. En la fixture de aceptación se
comparan además las dos temperaturas de capa en los 20 pasos que
siguen al rechazo.

**Lo que no ha cambiado**, comparado registro contra registro:

| Caso | Serie del número de sala | Serie de potencia | Energía aceptada | Débito contratado | Totales de la sonda |
| --- | --- | --- | --- | --- | --- |
| Abierto, 2,5 s | idéntica | idéntica | 115 093,655 kJ | 8,747 117 78 kg | idénticos |
| Abierto, 1,0 s | idéntica | idéntica | igual | igual | idénticos |
| Abierto, 2,5 s, otra rama | idéntica | idéntica | igual | igual | idénticos |
| Con rendija | — | — | 2 650,24 kJ | — | sale a los 800 s, igual |

El recinto con rendija sigue saliendo por la capa a los 800 s, no debita
nada desde entonces y no se reactiva al restituir el oxígeno. La fuente
con energía cero sigue siendo indistinguible de no tener fuente: 0 de 720
números distintos. En el recinto abierto la renovación exterior sigue
reponiendo oxígeno mientras la fuente entrega: la corrección no congela
nada.

**Un sumidero que no hace lo que dijo.** Forzando en la fixture una
respuesta falsa en el recinto estanco, el banco queda en `failed`, el
calor al gas y el término radiativo son 0, el motor deja de avanzar y el
informe lista, sin sumarlas, las tres cifras: 0 kg en el inventario de
sala, 7,7615 · 10⁻⁵ kg por la ruta primaria y 6,985 · 10⁻⁶ kg sobre el
número superior.

## Decisión C: NO-GO, con su plan

Para que el motor deje de escribir la demanda dos veces hay que cambiar
la ruta histórica del oxígeno. Eso mueve los números de capa de **toda**
corrida con fuego, también con el banco apagado, y por tanto la
referencia. No está autorizado aquí.

Tampoco es solo técnico. Qué número manda es la decisión de autoridad que
el [contrato de oxígeno](CONTRATO_O2_2026-09-24.md) dejó abierta para el
usuario, y [E1](E1_O2_BASE_DE_MASA_2026-09-25.md) ya midió que usar las
masas de capa como autoridad es NO-GO.

**Alternativa descartada dentro del banco.** Hacer que el sumidero tome
la rama del 9 % solo en el recinto del banco sería aislado e idéntico con
el banco apagado. No se ha hecho: elige entre dos alternativas físicas no
validadas, y mueve la salida del régimen hacia el lado menos prudente.

| Paso del plan | Propietario | Archivos | Pruebas |
| --- | --- | --- | --- |
| 1. Decidir la autoridad del oxígeno | Usuario | [contrato de oxígeno](CONTRATO_O2_2026-09-24.md) | — |
| 2. Entregar el indicador de dos zonas al sistema de oxígeno, tras un interruptor apagado | `SimulationEngine`, al configurar el sistema de oxígeno | `sim/core/SimulationEngine.gd` | Identidad con el interruptor apagado; contratos de oxígeno existentes |
| 3. Medir el efecto con el interruptor encendido | `OxygenExchangeSystem.step`, sumidero superior | Solo diagnóstico | Las hipótesis A1 a A6 de este informe, repetidas; casos `o2_closed` y `o2_reopen_300` |
| 4. Decidir si se activa | Usuario | Referencia | Referencia completa y nueva línea base, con su justificación |

El banco no necesita ese cambio para cumplir su contrato.

## Resultados de la verificación

Todo secuencial, un Godot cada vez y siempre bajo el monitor. Mínimo de
6 GiB disponibles sin rebajar: la cadena esperó a tener 6,6 antes de cada
paso y arrancó cada uno con entre 7,50 y 8,01. `TEMP`, `TMP` y `basetemp`
fuera del repositorio, y `APPDATA` también salvo en las pruebas de
pytest, cuyo lanzador ya existente fija el suyo bajo `runs/`.

### Diagnóstico, fixture y pruebas

- Campaña causal: los dos registros, el de antes sobre `1a39332a` y el de
  después sobre el código final, salen **como se declaró** antes de
  ejecutar. El de después se regeneró con el código que se publica.
- Fixture de aceptación sobre el motor real: **179 327 comprobaciones en
  11 grupos, 0 fallos**, sin errores de script. Eran 147 317; el número
  queda fijado en la prueba.
- [`tests/test_g3_object_hrr_oxygen_limits.py`](../../tests/test_g3_object_hrr_oxygen_limits.py):
  **14 passed**. Vuelve a evaluar las hipótesis fuera de GDScript sobre
  los dos registros, detecta el residuo en el de antes y su ausencia en
  el de después, y fija por lectura del código que la consulta repite las
  condiciones del paso, no escribe y solo la llama el banco.
- [`tests/test_g3_object_hrr_thermal_coupling.py`](../../tests/test_g3_object_hrr_thermal_coupling.py):
  **22 passed**.

La prueba de comportamiento del residuo falla sobre el código anterior:
40 de 40 pasos distintos del gemelo. Está en el registro de antes y la
prueba lo exige ahí.

### Mutaciones de código

Declaradas antes de ejecutar, cada una con el defecto que inyecta y el
grupo de la fixture donde debe verse. Mutan en el árbol de trabajo uno de
los tres archivos y lo restauran, verificado por SHA-256, tras cada
mutante.

| Campaña | Declarados | Detectados | Donde se esperaba | Inválidos | Supervivientes |
| --- | --- | --- | --- | --- | --- |
| Sobre el código final (`…_20261009_141333`) | 43 | **43** | **43** | **0** | **0** |

Eran 36. Los siete nuevos y los dos redefinidos:

| Mutante | Defecto que inyecta | Dónde se ve |
| --- | --- | --- |
| O02, redefinido | La potencia no se retira cuando el sumidero no hizo lo que dijo | B06 |
| O06 | El banco no pregunta la ruta: vuelve el residuo del recinto estanco | B06 |
| O07 | El banco no pregunta el coeficiente | B06 |
| O08 | Se acepta el calor tras una ruta incompatible | B06 |
| O09 | La consulta del sistema de oxígeno oculta la ruta de penacho | B06 |
| O10 | Preguntar escribe sobre el número inferior | B06 |
| R11, redefinido | Un sumidero que no hizo lo que dijo se presenta como salida limpia del régimen | B06 |
| S03 | La segunda escritura se suma al débito contratado | B02 |
| S04 | El informe deja de decir que las dos cifras no se suman | B10 |

Por familia: potencia 5, oxígeno 10, régimen y enclavamiento 11, calor 2,
armado 5, ciclo de vida 6, informe 4. Por archivo: 34 en el banco, 6 en
el motor y 3 en el sistema de oxígeno. Una muerte es una fixture que
llegó al final e informó de fallos; un error de sintaxis o de script se
habría anotado como inválido y no hubo ninguno. Los originales quedaron
intactos por SHA-256 tras la campaña, y los 13 archivos de la entrega
tienen la misma huella antes y después de toda la cadena.

### Regresiones de G3 y contratos afectados

Los módulos `tests/test_g3_*.py`, el contrato de fixtures que fallan
cerrado y los dos contratos de oxígeno: **1530 passed, 25 skipped,
2 xfailed**. Los omitidos son 20 del contrato de fixtures, dos más que
antes porque la fixture de diagnóstico no juzga y no tiene marca de
aprobado, y 5 del contrato de oxígeno, que pide una corrida externa.

Contratos históricos:

| Contrato | Qué decía | Qué se hizo |
| --- | --- | --- |
| Aislamiento de la fuente | Solo el banco la nombra | **Respetado**: la fixture de diagnóstico llega a ella a través del banco |
| Callables del banco | Cuatro | Cinco: se añade la consulta al sumidero. Cambio de contrato, justificado por el Gate B |
| Informe del banco | Esquema v1 con `oxygen_zone_displacement_kg` y `oxygen_debited_without_heat_kg` | Esquema v2. La primera clave cambia de nombre porque «desplazamiento» era falso en la rama medida; la segunda se retira porque sumaba dos números solapados |
| Sistema de oxígeno | `step()` sin cambios | **Respetado**: `step()` no llama a la consulta y el indicador de dos zonas sigue sin entregarse |

### Identidad con el interruptor apagado

Nueve casos de control (`sofa_vent`, `o2_closed`, `o2_reopen_300` y otros
seis) contra la corrida de la base anterior
(`…_ledgeroff_20261008_224311`). Siete archivos por caso, byte a byte:
**9 de 9 idénticos** (`…_ledgeroff_20261009_145803`).

### Referencia, guardarraíles, producto y global

| Paso | Resultado |
| --- | --- |
| Referencia completa monitorizada | 18 casos, salida 0, informes frescos, sin errores |
| Comprobaciones requeridas | **346 de 346 PASS** |
| Huecos conocidos | **78**, los mismos, inventario sincronizado |
| Guardarraíles, con R2-1 | **Todos PASS** |
| `check_product.py` | **168 pruebas, todas PASS**, sin procesos de Godot al terminar |
| `python -m pytest tests -q -p no:cacheprovider` | **4346 passed, 51 skipped, 2 xfailed, 42 subtests** |

Una global previa, antes de regenerar la referencia, dio 4345 passed y un
único fallo: el guardarraíl R2-1, que es justo lo que exige cuando `sim/`
cambia y el informe no. Tras regenerar, pasa.

Corpus `sim/validation/reports/` contra `1a39332a`: 382 archivos
seguidos, **381 idénticos byte a byte** y ninguno distinto solo por fin
de línea. El único con cambio es `reference_checks.json`, y su única
diferencia es `generated_at`, en una línea de 19 269.

### Salud

Ningún proceso de Godot al cerrar. Ningún proceso ajeno terminado. La
memoria bajó de 6 GiB una vez, antes de la cadena, por el navegador del
usuario: se trabajó sin Godot hasta que volvió, sin rebajar el umbral.

## Límites que siguen

- El oxígeno es una demanda equivalente prescrita con el coeficiente del
  sumidero del motor. No es oxígeno medido ni una estequiometría.
- Los números de capa del motor siguen recibiendo la demanda dos veces
  con la configuración por defecto. El banco lo informa y no lo corrige.
- El banco no soporta el recinto estanco. No hay resultado para él.
- `δ` y el criterio de capa siguen siendo hipótesis del banco.
- Ninguna temperatura está validada. CO, CO₂, HCN, humo, FED y SVV: no
  evaluados. Test021 sigue reservado y sin usar.

## Siguiente gate

Ninguno de código en este banco. Lo que sigue bloqueado es lo mismo que
antes: datos, una serie numérica de masa y un ensayo en recinto, y la
decisión de autoridad del oxígeno si se quiere retirar la doble
escritura. CO y FED siguen OFF/NO-GO.
