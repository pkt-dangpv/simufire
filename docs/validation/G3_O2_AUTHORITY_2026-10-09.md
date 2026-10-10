# Autoridad del oxígeno: qué inventario puede mandar en SimuFire

Fecha: 2026-10-09. Base `2d71f697`.

Revisa y cierra la decisión de autoridad que el
[contrato de oxígeno](CONTRATO_O2_2026-09-24.md) dejó abierta y que
[E1](E1_O2_BASE_DE_MASA_2026-09-25.md) dejó en NO-GO para las masas de
capa. Sigue al
[diagnóstico de los dos límites de oxígeno del banco](G3_OBJECT_HRR_OXYGEN_LIMITS_2026-10-09.md).

**No se migra nada en esta entrega.** No se ha tocado `sim/`, no se ha
activado ningún modo, no hay línea base nueva y la referencia queda
intacta. Lo que hay es diagnóstico del motor actual, evidencia dinámica,
una recomendación y un plan.

> **Estado al 2026-10-10.** Las etapas M0 y M1 del plan están hechas, tras
> un interruptor apagado y sin activar:
> [M0 y M1, inventario de sala y tránsito](G3_O2_ROOM_INVENTORY_M0_M1_2026-10-10.md).
> Este documento describe el motor de `2d71f697` y se conserva como se
> publicó; su registro queda ligado a los archivos de su commit. Con el
> interruptor apagado, las hipótesis que su fixture ejercita vuelven a dar
> hoy las mismas cifras.
>
> **M2, también el 2026-10-10:**
> [una selección por recinto y paso](G3_O2_SELECTION_M2_2026-10-10.md).
> Dos cosas de este documento quedan **corregidas por medida**: el hueco
> de −0,378 kg de `o2_reopen_300` **no es tránsito** —la cola termina
> vacía—, y los casos de casa no corren con el modo encendido mientras el
> venteo por sobrepresión no esté integrado.
>
> **M2-V, también el 2026-10-10:**
> [el venteo por sobrepresión por el propietario](G3_O2_PRESSURE_VENTING_M2V_2026-10-10.md).
> El venteo está integrado y los dos casos de casa corren enteros. La
> causa del hueco de −0,378 kg queda demostrada con un control: es un
> crédito inmediato que la ruta histórica recorta al techo. Con el modo
> encendido ese crédito enriquece al recinto durante segundos: un defecto
> de transporte que el plan de este documento no tenía.

- Registro: [`G3_O2_AUTHORITY_DIAGNOSIS_2026-10-09.json`](G3_O2_AUTHORITY_DIAGNOSIS_2026-10-09.json).
- Fixture de diagnóstico, que no juzga: [`g3_o2_authority_diagnosis.gd`](../../tests/fixtures/g3_o2_authority_diagnosis.gd).
- Hipótesis, evaluación y casos de casa: [`run_g3_o2_authority_diagnosis.py`](../../scripts/simulation/run_g3_o2_authority_diagnosis.py).
- Pruebas: [`test_g3_o2_authority.py`](../../tests/test_g3_o2_authority.py).

CO y FED siguen OFF/NO-GO. El oxígeno del banco Test016 sigue siendo una
demanda equivalente por energía: no es oxígeno medido ni una
estequiometría.

## Decisión

**Recomendación: Inventario único de oxígeno por recinto, en kilogramos
de O₂, como única cantidad conservada.** Los tres números que hoy consulta
el motor pasan a ser derivados de él. El reparto entre capas se añade
después como un segundo estado **dentro** de ese total, de modo que nada
de lo que pase entre capas pueda crear ni borrar oxígeno del recinto.

Por qué, en cuatro hechos medidos en este árbol:

1. **El número de sala ya es hoy un libro cerrado** en la ruta en la que
   el sumidero debita la sala: cierra a 9 · 10⁻¹⁴ kg con una demanda
   conocida, a 3 · 10⁻¹⁴ kg con un fuego real, y el transporte entre
   salas lo conserva a 2 · 10⁻¹⁴ kg.
2. **Los números de capa no conservan nada.** Se relajan hacia el número
   de sala sin donante, se reescriben enteros cuando una capa colapsa y
   reciben una segunda escritura del tamaño del débito que no llega a
   ningún inventario.
3. **Las masas de gas de capa no sirven de base** en ninguno de los dos
   modos. Fuera de la red de presión se reescriben con la temperatura.
   Con la red se conservan, pero el oxígeno sobre ellas no.
4. **El fuego y el sumidero usan depósitos distintos**: el fuego lee el
   número de la capa inferior mientras el sumidero debita la sala.

| Alternativa | Decisión | Motivo |
| --- | --- | --- |
| A. Inventario único por recinto, valores de capa derivados | **GO como autoridad** | Es lo único que el motor conserva hoy; el reparto entre capas se construye encima |
| B. Inventarios por capa sobre `upper_gas_kg` y `lower_gas_kg` | **NO-GO** | Los bloqueos de E1 siguen vigentes en los dos modos |
| C. Autoridad restringida a una ruta, rechazando el resto | **Vigente hasta migrar** | Es lo que hace hoy el banco Test016; no es una solución general |

| Componente | Decisión | Qué cumple hoy | Qué falta |
| --- | --- | --- | --- |
| Inicialización | **GO, con implementación** | Los tres números parten de 0,209 y un recinto en reposo no cambia | El inventario en kg: 0,209 es fracción molar y hoy se multiplica por una masa |
| Base de masa | **GO** para la base de referencia del recinto; **NO-GO** para la masa de gas | Base constante, la misma en todos los escritores del número de sala | Declararla como aproximación; nada sobre masa de gas |
| Consumo único | **GO, con implementación** | En la ruta de sala el débito es exactamente 0,076 kg/MJ del calor aceptado | Retirar la segunda escritura y llevar la ruta de recinto estanco al inventario |
| Transporte | **GO parcial** | Intercambio interior e infiltración cierran, contando lo que está en tránsito | Hueco exterior con diferencia de temperatura, venteo, PPV y HVAC: sin ejercitar aquí |
| Mezcla y movimiento de capas | **NO-GO hoy** | Nada | El reparto conservativo entre capas |
| Disponibilidad y aceptación de calor | **NO-GO en el motor**; GO en el banco | El banco pregunta antes de aceptar | En el motor el tope recorta en silencio: 8,22 kg sin debitar en el caso de estrés |
| Ciclo de vida | **GO** | Reinicio limpio y misma corrida bit a bit | Nada |
| Migración desde las rutas históricas | **GO al plan; NO-GO a activar** | — | Interruptor apagado, identidad, casos encendidos y decisión aparte |

## Qué sigue vigente de E1

E1 respondió a una pregunta: si las masas de capa pueden sostener un
inventario de oxígeno. Respondió NO-GO en los dos modos. Cada motivo se
ha vuelto a mirar contra el código de hoy y, donde un control lo
discrimina, se ha medido.

Qué cambió desde el punto de E1 (`8a8e205b`): `ZoneFireSolver`,
`GasExchangeSystem`, `PressureNetworkTransportSystem` y `HVACSystem` no
tienen ni una línea distinta. `ThermalSystem` recibió las correcciones P3
y P3b. `OxygenExchangeSystem` y `SimulationEngine` recibieron
instrumentación, el banco y su consulta de solo lectura.

| Bloqueo de E1 | Qué midió E1 | Archivos | Comprobación de hoy | Situación |
| --- | --- | --- | --- | --- |
| Fuera de la red, la masa de la capa baja se reescribe en cada proyección | Salón sellado con fuego: −25,7 % y +22,60 kg en la frontera | `ZoneFireSolver.gd` | Recinto sellado y caliente **sin fuego**: 57,60 → 49,48 kg, −8,12 kg anotados en la frontera en el primer paso. Con fuego, dos salas: 103,68 → 90,37 kg | **Vigente y demostrado** |
| El sistema de oxígeno no usa esas masas: su base es volumen × 1,2 | Lectura de código | `OxygenExchangeSystem.gd` | Misma función, y los cierres de abajo solo salen con esa base | **Vigente y demostrado** |
| Con la red, el oxígeno en kg no se conserva aunque la masa de gas sí | −0,113 kg sellado y −5,10 kg con la puerta abierta | `PressureNetworkTransportSystem.gd`, `OxygenExchangeSystem.gd` | Fuego real, dos salas, red encendida como modo de diagnóstico: masa de gas constante a 1,4 · 10⁻¹³ kg y 0,406 kg de oxígeno sin explicar, el 24 % del débito | **Vigente y demostrado** |
| Con la red, dos propietarios del transporte interior (P3) | 64,59 kg por el térmico, 64,05 devueltos por la red | `ThermalSystem.gd` | Validador de propietario único, en verde hoy en `check_product` | **Corregido y demostrado** |
| La siembra radiativa movía gas sin su oxígeno (P3b) | −0,295 kg en un paso | `ThermalSystem.gd` | El mismo validador | **Corregido y demostrado**, solo con la red |
| La misma primitiva sin especies en siembra por conducción, penacho y escalera, también fuera de la red | Lectura de código | `ThermalSystem.gd` | Las tres llamadas siguen ahí | **No comprobado todavía**; código sin cambios |
| El sumidero superior recibe la demanda completa además de la sala (O2-4) | 8,74 kg además de 13,64 | `SimulationEngine.gd`, `OxygenExchangeSystem.gd` | Segunda escritura igual al débito: 1,7413 kg y 1,7413 kg | **Vigente y demostrado** |
| El fuego lee un depósito y el sumidero debita otro (O2-1) | Diagnóstico de la casa simple | `CombustionSystem.gd`, `OxygenExchangeSystem.gd` | 294 de 480 pasos con el fuego leyendo el número inferior, hasta 0,022 por encima del de sala | **Vigente y demostrado** |
| El tope del 5 % recorta el débito y el calor no se revisa (O2-3) | 0,943 kg en la casa FDS | `OxygenExchangeSystem.gd` | Caso de estrés: el calor aceptado pide 25,19 kg y se debitan 16,97 | **Vigente y demostrado** |
| El número de sala se rederiva de las capas sin anotarlo | −4,89 y −5,22 kg en los sellados | `OxygenExchangeSystem.gd` | `o2_closed`: 5,93 kg que ningún acumulador explica | **Vigente y demostrado** |
| Los mismos kg se aplican a la sala y al número inferior sobre bases distintas (O2-2) | Medido en la representación zonal | `OxygenExchangeSystem.gd` | No aislado en esta fase | **No comprobado todavía**; código sin cambios |
| Purga histórica de envolvente con sobrepresión inflada | 28 kg a 290 kPa | `GasExchangeSystem.gd` | No medido aquí | **No comprobado todavía**; código sin cambios |
| Fracción molar tratada como másica (P6) | Lectura de código | `PressureNetworkTransportSystem.gd`, `OxygenExchangeSystem.gd` | Aritmética de abajo | **Vigente** |
| La masa baja como estado en la ruta de producto (P1) | Prerrequisito de B | `ZoneFireSolver.gd` | No se ha hecho | **Vigente** |
| Reescribir C1, C2 y C4 antes de usarlas como gates (P5) | — | `tests/test_oxygen_contract.py` | Siguen como en O2-A | **Vigente**; entra en el plan |

Ningún bloqueo se retira por nombres ni por pasar la suite. Dos se
retiran porque están corregidos y tienen su validador. Tres no se han
vuelto a medir y se dicen.

**Lo que cambia respecto a E1.** E1 descartó la alternativa A «como
solución» porque un inventario de sala no da disponibilidad por capa.
Sigue siendo cierto de un inventario de sala **solo**. Lo que se propone
aquí es el inventario de sala como cantidad conservada y el reparto entre
capas como estado subordinado a él. La disponibilidad por capa se
recupera sin necesitar que la masa de gas de capa sea estado, que es
justo lo que E1 no pudo tener.

## Mapa real de estados y propietarios

| Representación | Unidad y significado | Base | Quién la escribe | Quién la lee | Qué es |
| --- | --- | --- | --- | --- | --- |
| `room.o2` | Adimensional, 0,209 en el aire. Es una fracción molar que el motor opera como másica | Volumen × 1,2 kg/m³, constante | Sumidero de sala e infiltración, hueco exterior, intercambio interior con su cola de entregas, venteo, PPV, HVAC, rederivación desde las capas, red de presión y el recorte final | El fuego en parte, el transporte, el banco, la clasificación de régimen, el registro | **Concentración que hace de inventario** en la ruta de sala |
| `room.o2_upper` | Igual | Parte geométrica de esa misma masa, por la altura de la interfaz | Segunda escritura del sumidero, arrastre a tasa fija, relajación, homogeneización, HVAC, red | El fuego si está inmerso, la exposición por capa, la validación frente a CFAST | **Trazador histórico** |
| `room.o2_lower` | Igual | Igual; y en la ruta de recinto estanco se acota con una base y se aplica con otra | Sumidero de penacho, drenaje, reposición por huecos, relajación, homogeneización | El fuego mientras la interfaz está sobre él, la exposición, el banco | **Trazador histórico** |
| `room.upper_o2_mass_tracked` | kg sobre la parte superior de la base constante | Parte geométrica | Solo con su interruptor, apagado | Nadie con él apagado | **Inerte**. Estar en kg no lo hace inventario |
| `upper_gas_kg`, `lower_gas_kg` | kg de gas por capa | Estado con la red; fuera de ella la baja es volumen × densidad a presión de referencia | Solver de zonas, térmico, intercambio de gases, red | Térmico, presión, humo, especies, red | **Inventario físico solo con la red**; fuera, valor derivado |
| `two_zone_boundary_mass_kg` | kg de gas que la proyección pone o quita | — | Proyección de zonas | Diagnóstico | **Acumulador de auditoría** de un intercambio sin propietario |
| `o2_consumed_bulk_kg_total` | kg debitados del inventario de sala | Base constante | Sumidero de sala | Auditoría | **Acumulador**, el único que casa con un inventario |
| `o2_consumed_fire_kg_total` | kg de la ruta primaria del paso | La de esa ruta | Sumidero | Auditoría | **Acumulador** |
| `o2_consumed_kg_total_all` | Suma de escrituras sobre números solapados | Varias | Sumidero | Auditoría | **No es una cantidad de inventario** |
| `o2_exterior_net_kg_total`, `o2_net_transport_kg_total` | kg que entran por exterior y por transporte | Base constante | Sistema de oxígeno | Auditoría | **Acumuladores completos** en lo medido |
| `o2_zone_sync_kg_total` | kg de rederivación | — | Solo la mezcla de puerta del térmico, apagada | Auditoría | **Acumulador que no anota** la rederivación del sistema de oxígeno |
| Cola de entregas pendientes | kg de O₂ en tránsito hacia una sala | Base constante | Intercambio interior | Solo el propio sistema; **no se registra** | **Parte del inventario** que hoy vive fuera del estado de sala |

Instrumentos de auditoría que ya existen: el libro pasivo de aceptación
por escritor, que ve 25 de las 53 escrituras y solo en fracciones; la
sonda de balance de G3; la sombra de masa zonal de P1R3, apagada; las
pruebas del contrato O2-A sobre traza; y el informe del banco. Ninguno es
autoridad.

Las 53 escrituras: 29 en el sistema de oxígeno, 11 en el térmico, 5 en
HVAC, 4 en el intercambio de gases, 3 en la red de presión y 1 en el
motor. Son las 52 de E1 más el paquete de siembra de P3b.

**Qué pasa cuando cambia algo:**

- **Temperatura.** Los tres números no reaccionan. La masa de gas sí:
  fuera de la red se reescribe y la diferencia se anota en la frontera.
- **Presión.** Fuera de la red no hay presión que conserve masa. Con la
  red la masa es estado y el oxígeno sigue sin serlo.
- **Geometría.** Cuando la interfaz se mueve cambian las partes de cada
  capa y nadie mueve oxígeno con ellas. Si la capa baja queda por debajo
  del 15 % de la altura, las dos capas se igualan al número de sala.
- **Régimen.** El depósito que debita el sumidero depende de si el
  recinto tiene huecos abiertos. El que lee el fuego depende de la altura
  de la interfaz. Son dos condiciones distintas.

### La concentración inicial

0,209 es la fracción **molar** de oxígeno del aire seco. La fracción
másica que le corresponde es 0,209 × 31,998 / 28,9647 = **0,2309**. El
motor multiplica 0,209 por una masa de aire: guarda 0,2508 kg de O₂ por
metro cúbico donde el aire seco a 1,2 kg/m³ tiene 0,2771. **Su inventario
es un 9,5 % más corto** que el del aire que dice representar.

El débito, en cambio, va en kilogramos reales: 0,076 kg/MJ. Así que por
cada megajulio el número cae un 10,5 % más de lo que caería la fracción
molar de un recinto con esos moles.

- **Evidencia:** el código y la aritmética, que está en el registro.
- **Hipótesis:** aire seco de 28,9647 g/mol.
- **Dato desconocido:** el motor no lleva humedad ni la composición de su
  gas. La masa molar de una mezcla quemada no la conoce, y la conversión
  exacta de fracción molar a másica la necesita.

No se corrige aquí. Cambiarlo mueve todos los números de oxígeno.

## Evidencia dinámica

Quince hipótesis, catorce escritas antes de ejecutar nada y una añadida
antes de correr su caso. Cada una se parte en afirmaciones separadas y
vale si valen todas.

**Tres lanzamientos, y se dice por qué.** El primero se descarta entero:
la fixture cargaba sus recintos antes de meter el edificio en el árbol,
el edificio cargó encima el preset de producto y lo que corrió fue la
casa. En el segundo el banco de los casos de demanda controlada armó pero
su reloj no arrancó, porque la fixture no levantaba el evento de
ignición. El tercero es el registro. Entre lanzamientos cambió la
fixture, nunca una hipótesis. Se corrigió además la evaluación de una
afirmación de H05, que sumaba dos salas cuyos desfases se cancelan.

Los kilogramos de esta sección son de tres clases y **no se suman entre
sí**: el número de sala por su base constante; los dos números de capa
por sus partes geométricas de esa base; y los dos números de capa por las
masas de gas de capa, que es la convención de la red.

Recintos: sala A de 48 m³ y sala B de 38,4 m³, 2,4 m de altura, puerta
de 0,9 × 2,0 m. Valores de producto salvo lo que cada caso declara.

| Caso | Qué se predijo | Resultado |
| --- | --- | --- |
| H01. Recinto sellado, sin fuego, 240 pasos | Nada cambia | **Cumplida.** Los tres números en 0,209 bit a bit; 57,6 kg de gas; todos los acumuladores a cero |
| H02. Recinto sellado y caliente, sin fuego | Los números no cambian y la masa de gas sí | **Cumplida.** 57,60 → 49,48 → 53,23 kg; −8,12 kg en la frontera; los números de capa sobre la masa de gas pierden hasta 1,70 kg sin que nadie haya escrito |
| H03. Lo mismo con la red (modo de diagnóstico) | La masa se conserva | **Cumplida.** 57,6 kg constantes con 14,3 kPa de sobrepresión; frontera 0 |
| H04. Dos salas cerradas al exterior, banco con 20 kW durante 120 s, sin infiltración | El número de sala cierra con el débito | **Cumplida.** 2,4 MJ, 0,1824 kg debitados, hueco máximo 8,9 · 10⁻¹⁴ kg contando hasta 0,022 kg en tránsito; segunda escritura 0,1824 kg que no aparece en el cierre |
| H05. Dos salas, sin fuego, una empieza en 0,15 | El transporte conserva la suma | **Cumplida.** 0,2453 kg pasan de una a otra; suma conservada a 1,8 · 10⁻¹⁴ kg. Los números de capa **no se transportan**: tras un paso la sala va en 0,150012 y sus capas siguen en 0,15 |
| H06. Una sala con puerta al exterior, sin fuego | Solo la ley de infiltración | **Cumplida.** Se aparta de ella 1,9 · 10⁻¹⁶; el cambio es el acumulador exterior a 1,4 · 10⁻¹⁴ kg |
| H07. Puerta cerrada, abierta y cerrada | Cerrada, nada cambia | **Cumplida.** 0 cambios, 160 y 0; suma conservada a 1,4 · 10⁻¹⁴ kg |
| H08. Dos capas con números distintos, sin fuego | Relajación, no intercambio | **Cumplida.** Sala fija en 0,18; la superior sube de 0,12 a 0,178 y la inferior baja de 0,20 a 0,180; sobre sus partes aparecen **0,43 kg** con todos los acumuladores a cero |
| H09. La capa baja queda en el 9 % de la altura | Las dos capas se reescriben | **Cumplida.** En el segundo paso las dos valen el número de sala exacto: **+4,62 kg** de golpe sobre sus partes, acumuladores a cero |
| H10. La mitad del paso | Mismos cierres y mismo débito | **Cumplida.** Huecos 8,9 · 10⁻¹⁴ y 9,2 · 10⁻¹⁴ kg; débito 0,1824 kg en los dos. El número final sí depende del paso: 0,206927 y 0,206922 |
| H11. Reinicio y reutilización | Limpio y repetible | **Cumplida.** 52 entregas en tránsito y una reserva antes; ninguna después; la misma corrida da la misma huella |
| H12. Fuego real, dos salas, 120 s | Depósitos distintos y doble escritura | **Cumplida.** 22,91 MJ; débito de sala 1,7413 kg, exactamente 0,076 kg/MJ; segunda escritura 1,7413 kg; el fuego lee el número inferior en los 480 pasos y en 294 se aparta más de 0,001 del de sala; mínimos: superior 0,067, sala 0,184, inferior 0,206; y aun así las salas cierran a 3,2 · 10⁻¹⁴ kg |
| H13. Casos de casa ya corridos | Ver abajo | **Una afirmación de siete no se cumple** |
| H14. Demanda controlada con la red | — | **No ejercitada**: el banco no arma con la red de presión |
| H15. Fuego real con la red (modo de diagnóstico) | Masa sí, oxígeno no | **Cumplida.** Masa de gas constante a 1,4 · 10⁻¹³ kg; el número de sala se reescribe desde las capas; sobre la masa de gas se pierden 1,251 kg cuando el débito menos el exterior es 1,657: **0,406 kg** de diferencia |

En el fuego real de H12 la masa de gas de las dos salas baja de 103,68 a
90,37 kg, con +28,50 y −20,45 kg anotados en la frontera. Los números de
capa sobre esa masa pierden 3,505 kg cuando el débito es 1,741. Es la
misma razón de E1, medida hoy.

**En tránsito.** Al final de H12 hay 0,133 kg de oxígeno camino de la
otra sala. Sin contarlos, la suma de las salas no cierra. Están en una
cola privada del sistema de oxígeno que el registro de simulación no
escribe.

### Los casos de casa

Salen de la corrida de identidad con el interruptor apagado del mismo
día, sobre un `sim/` idéntico al de este árbol. Seis salas, registro cada
segundo.

| Caso | Medida | Lectura |
| --- | --- | --- |
| `o2_closed`, puerta cerrada | Inventario de sala debitado: 0. Ruta primaria: 6,077 kg. El número de sala cambia −5,317 kg y los acumuladores explican +0,615 | **5,93 kg** que nadie anota: el número de sala se rederiva de las capas |
| `o2_reopen_300`, tras abrir | Débito de sala 3,531 kg; segunda escritura 3,401 kg; 333 s con el fuego leyendo el número inferior, hasta 0,023 por encima | O2-1 y O2-4 en geometría de producto |
| `o2_reopen_300`, cierre de la casa | Cada sala cierra con sus acumuladores a 4,5 · 10⁻⁴ kg. La casa no: −0,378 kg | **Predicción no cumplida.** El hueco es la suma de los acumuladores de transporte, −0,378 kg |
| `o2_stress_cap` | El calor aceptado, 331,46 MJ, pide 25,19 kg; se debitan 16,97 | **8,22 kg** nunca debitados: el tope recorta y el calor no se revisa |

Sobre el hueco de la casa: es lo que deja el oxígeno en tránsito, y en
H12 la misma cuenta cierra a 4,8 · 10⁻¹⁴ kg cuando el tránsito se mide.
En la casa **no está medido**, porque el registro no lo escribe. Queda
como compatible, no como demostrado.

> **Corregido el 2026-10-10, al medirlo.** No es tránsito. Con la cola de
> entregas medida paso a paso, termina vacía y los acumuladores de
> transporte de la casa suman −0,3778 kg: es oxígeno que la ruta
> histórica pierde, en los 13 s que siguen a la apertura de la puerta.
> Ver [M2](G3_O2_SELECTION_M2_2026-10-10.md). La frase de arriba se
> conserva como se publicó.

## Alternativas

| | A. Inventario por recinto | B. Inventarios por capa sobre masa de gas | C. Ruta restringida |
| --- | --- | --- | --- |
| Inicialización | Un valor por recinto, con la conversión molar a másica declarada | Dos valores, y una masa de capa que al inicio es cero en la superior | La de hoy |
| Consumo | Un débito sobre un depósito | Un débito por capa; exige saber qué capa alimenta la llama | El de hoy en la ruta de sala |
| Transporte interior y exterior | Ya conservativo a nivel de sala, con su tránsito | Necesita caudales por capa; solo existen con la red | El de hoy |
| Mezcla y movimiento de la interfaz | No afecta al total; el reparto se lleva aparte | Cada paso de gas entre capas tiene que llevar su oxígeno; hoy tres primitivas no lo hacen | No se trata |
| Presión y temperatura | La base de referencia no reacciona; es exacta si los moles del recinto no cambian | Fuera de la red, la masa se reescribe con la temperatura | No se trata |
| Zonas vacías o colapsadas | El total no se entera | Un denominador que tiende a cero | Hoy reescribe las capas |
| Reinicio | Cumple hoy | Sin implementar | Cumple hoy |
| Compatibilidad con las rutas históricas | Convive tras un interruptor | Obliga a llevar el producto a la red | Es la ruta histórica |
| Datos que faltan | Humedad y masa molar de la mezcla, para la conversión | Los mismos, más un modelo de presión en producto | Ninguno |
| Coste y riesgo | Bajo para el total; medio para el reparto | Alto: 53 escrituras y la ruta de producto entera | Nulo; no generaliza |

**Por qué no B, aunque sea lo que hace CFAST.** CFAST lleva la masa de
cada especie por capa y la masa de cada capa es estado, resuelta junto
con la presión. Aquí la masa de capa solo es estado con la red, que no es
la ruta de producto, y aun con ella el oxígeno no se conserva. Elegir B
por parecido sería poner la autoridad sobre un denominador que el motor
reescribe.

**Por qué no C como destino.** Rechazar las configuraciones incompatibles
es correcto en un banco de diagnóstico. En producto dejaría sin oxígeno
definido a todo recinto estanco.

**Lo que A no puede hacer y no se disimula.** Un inventario por recinto,
sin más, no distingue capas. Repartirlo por volumen sería inventar una
mezcla. Por eso el reparto es un estado propio y no una proporción.

## Contrato propuesto

### Qué se conserva

La masa de oxígeno de cada recinto, `M` en kg de O₂, más la que está en
tránsito hacia él, `T` en kg de O₂.

Para un recinto y un paso:

```
M(t+dt) = M(t) + entradas − salidas − consumo + llegadas del tránsito     [kg de O₂]
```

Para el edificio:

```
Σ (M + T) al final = Σ (M + T) al inicio + exterior neto − consumo        [kg de O₂]
```

- **Entradas y salidas:** kg de O₂ que cruzan un hueco, cada uno anotado
  con el mismo valor y signo contrario en los dos lados, o en `T` si
  llega más tarde.
- **Exterior neto:** infiltración, huecos exteriores, venteo y
  ventilación, con el aire exterior a su concentración.
- **Consumo:** un solo término, el débito del sumidero.
- **No hay más términos.** Un cambio de base, una conversión o una
  rederivación no son fuente ni sumidero.

El segundo estado, cuando se añada: `M_alta`, los kg de O₂ de `M` que
están en la capa superior. `M_baja = M − M_alta` es derivada. Arrastre
del penacho, movimiento de la interfaz, mezcla y colapso cambian `M_alta`
y nunca `M`: **se cancelan en el total por construcción**, no por
comprobación.

### Qué pasa a ser derivado

- `room.o2`: concentración del recinto, calculada desde `M`.
- `room.o2_upper` y `room.o2_lower`: concentraciones de capa, calculadas
  desde `M_alta` y `M − M_alta` y la parte de cada capa. Hasta que exista
  el reparto no hay estratificación de oxígeno que derivar: se declara.
- `room.upper_o2_mass_tracked`: se retira.
- Todos los acumuladores: auditoría, nunca estado.

### Las nueve preguntas

| Pregunta | Respuesta del contrato |
| --- | --- |
| Qué cantidad se conserva | kg de O₂ por recinto, más el tránsito |
| Qué campos son derivados | Los tres números y los acumuladores |
| Qué escritor puede consumir | Uno: el sumidero del sistema de oxígeno, sobre el depósito de la selección. La segunda escritura deja de existir como consumo |
| Qué concentración consulta el fuego | La del depósito de la selección, derivada del inventario |
| Qué base usa el transporte | kg de O₂ = concentración del donante × gas movido, en la misma base en que se expresa ese gas |
| Cómo se calcula la disponibilidad | Antes de escribir la potencia: lo que el depósito puede entregar en el paso frente a la demanda del calor propuesto |
| Qué pasa si el débito no cabe | Se acepta solo el calor que cabe, y combustible y productos bajan en la misma transacción. Sin deuda y sin recorte callado. En el banco, sale del régimen, como hoy |
| Cómo se evita que fuego y sumidero elijan depósitos distintos | Una sola selección por recinto y paso —depósito, concentración y disponible— que usan los dos |
| Qué necesita compromiso coherente | Selección, calor aceptado, débito y productos. Gas que cambia de capa y su oxígeno. Débito del donante y crédito del receptor, con su tránsito |

Si después de aceptar el calor el débito no se pudiera aplicar entero,
es un fallo y se detiene, como ya hace el banco. No se presenta como un
rechazo limpio.

### Lo que se mantiene separado

- **Demanda equivalente por energía:** kg/MJ por el calor aceptado. Es lo
  que usa el contrato.
- **Estequiometría de un combustible:** no entra. El motor no la tiene y
  el banco Test016 no la da.
- **Oxígeno medido en un ensayo:** no entra.

### Aproximaciones del contrato, dichas

- **Base de referencia.** `M` se convierte en concentración con los moles
  de referencia del recinto. Es exacto si los moles del recinto no
  cambian y aproximado en un recinto abierto y caliente, donde hay menos
  gas del que la base supone. Es una **aproximación**, no una hipótesis
  sobre el ensayo.
- **Masa molar.** Aire seco. La combustión cambia los moles totales y la
  masa molar; no se corrige. **Dato desconocido:** la composición.
- **El reparto entre capas** usa la parte geométrica que el sumidero ya
  usa. Es una **aproximación** del mismo orden que la base.

## Fuentes

Biblioteca local primero. La referencia técnica de CFAST está en
`docs/literature/NIST.TN.1889v1.pdf`: NIST TN 1889v1, CFAST versión
7.0.0, octubre de 2015, revisión `Gitv7-0-g4eddb8a`.

| Qué dice | Dónde | Cómo se usa aquí |
| --- | --- | --- |
| La masa de cada capa es estado: `dm/dt` igual a los caudales que entran | Ec. 2.2 | **Evidencia** de su contrato; aquí no se cumple fuera de la red |
| Presión, volumen de la capa alta y temperaturas se resuelven juntos con la ley de gases | Ec. 2.4 a 2.8 | Contraste con la proyección a presión de referencia |
| La composición inicial es 23 % de oxígeno en masa, 21 % en volumen, y la masa molar de la mezcla se toma como la del aire, 29 g/mol | Sección 2.2 | **Evidencia** de que másica y molar son distintas y de la aproximación de masa molar |
| Cada especie se acumula en las capas y se transporta con el gas | Sección 2.2 | Contrato de B |
| El calor se limita por el oxígeno que el penacho arrastra de la capa donde está el fuego, con 13,1 MJ por kg de O₂ y un límite inferior en fracción másica | Ec. 3.13 y 3.14 | **Evidencia** de que la disponibilidad es un caudal, no una concentración, y de que el depósito es la capa del fuego |
| El combustible que no arde se sigue y se transporta | Sección 3.2 | Lo que exige «la misma transacción» |

Lo que **no** se toma de CFAST: su reparto por capas sobre masa de gas,
porque aquí esa masa no es estado; ni su función de límite inferior, que
es una calibración y no un requisito de conservación.

0,076 kg/MJ equivale a 13,16 MJ por kg de O₂, a un 0,4 % del 13,1 de esa
fuente. Es una **demanda equivalente**, no una medida.

## Plan mínimo de implementación

Nada de esto se ha hecho. Cada etapa es un encargo y va tras un
interruptor sin exportar, apagado.

| Etapa | Qué | Propietario y archivos | Con el interruptor apagado | Con él encendido |
| --- | --- | --- | --- | --- |
| M0 | Convertir en pruebas de aceptación los cierres que hoy ya salen, y reescribir C1, C2 y C4 sobre el inventario de sala | `tests/` | — | — |
| M1 | `M` y `T` como estado; un solo punto por el que se escribe la sala; `room.o2` derivado; conversión molar declarada | `RoomModel`, `OxygenExchangeSystem`, `GasExchangeSystem` | Identidad byte a byte y referencia sin cambios | Cierres de H04 a H07, H10 y H11 |
| M2 | Una selección por recinto y paso para fuego y sumidero; retirar la segunda escritura; la ruta de recinto estanco debita el inventario | `CombustionSystem`, `OxygenExchangeSystem`, `SimulationEngine` | Igual | H12 con un solo depósito; `o2_closed` cerrando |
| M3 | Disponibilidad antes de aceptar el calor | `CombustionSystem` | Igual | `o2_stress_cap` sin oxígeno sin debitar |
| M4 | El reparto conservativo `M_alta` en lugar de los trazadores | `OxygenExchangeSystem`, `ThermalSystem` | Igual | H08 y H09 conservando el total; comparación con CFAST como caso encendido |

> **2026-10-10.** M0 y M1 están hechas. Dos precisiones que salieron al
> escribir el contrato ejecutable, ambas en
> [su informe](G3_O2_ROOM_INVENTORY_M0_M1_2026-10-10.md): el tránsito es
> una cantidad **con signo**, porque la ley histórica retrasa el neto de
> dos paquetes opuestos; y el banco del Test016 se rechaza junto con la
> red de presión, porque deshace sus pasos restaurando números que con el
> modo encendido son derivados. M2, M3 y M4 siguen sin hacer.
>
> **M2 está hecha** ([informe](G3_O2_SELECTION_M2_2026-10-10.md)), con una
> diferencia frente a la fila de la tabla: su aceptación pedía `o2_closed`
> cerrando, y ese caso **no corre** con el modo encendido porque lo
> rechaza el venteo por sobrepresión. Integrarlo es un paso que este plan
> no tenía y que va antes de M3. M3 y M4 siguen sin hacer.

### Pruebas predeclaradas para M1

- **Balances.** Hueco del presupuesto del edificio, contando el tránsito,
  ≤ 1 · 10⁻⁹ kg en cada paso. La tolerancia está cuatro órdenes por
  encima de lo medido hoy, 10⁻¹³ kg, y más de cinco por debajo del débito
  por paso del caso más pequeño, 7,6 · 10⁻⁴ kg.
- **Identidad.** Los nueve casos de identidad byte a byte y la referencia
  sin cambio de contenido, con el interruptor apagado.
- **Sin enriquecimiento.** Ninguna concentración derivada por encima de
  la exterior.
- **Controles negativos.** Red de presión encendida: rechazo explícito,
  como el banco. Recinto estanco hasta M2: rechazo explícito y dicho.
- **Mutaciones declaradas:** débito aplicado dos veces; tránsito sin
  contar; número de sala escrito sin pasar por el inventario; crédito sin
  débito; reinicio que deja tránsito; conversión con masa en vez de
  moles; un número de capa escrito sobre el inventario; un recorte que
  descarta sin anotar.

### Condiciones para activar o rechazar

Activar es otra decisión, con su regeneración de referencia. Antes hacen
falta: todos los cierres encendidos; la casa cerrando con el tránsito
medido; y el efecto sobre potencia, extinción y exposición cuantificado
frente al modo actual. Se rechaza si algún cierre depende de un recorte o
de una reconciliación.

### Datos frente a defectos

Ningún fallo de conservación de este informe depende de datos de ensayo:
todos se reproducen con recintos sintéticos. Los **datos** que faltan son
otros: humedad y composición para la masa molar, y una calibración del
límite de oxígeno si se quiere una. No bloquean M1.

## Límites de este trabajo

- La red de presión se ha usado como modo de diagnóstico declarado. No es
  la ruta de producto y aquí no se aprueba.
- No se ha ejercitado el hueco exterior con diferencia de temperatura, el
  venteo por sobrepresión, PPV ni HVAC.
- El hueco de la casa tras reabrir es compatible con el tránsito y no
  está medido.
- Tres bloqueos de E1 no se han vuelto a medir.
- La recomendación no dice que los números resultantes vayan a parecerse
  más a un ensayo. Dice qué se conserva.

## Verificación

`sim/` no se ha tocado: la referencia no se regenera y sus informes quedan
como estaban. Godot siempre bajo el monitor, de uno en uno, con 6 GiB de
mínimo sin rebajar y entre 7,6 y 7,9 al arrancar cada tanda. `APPDATA`,
`TEMP`, `TMP` y `basetemp` fuera del repositorio.

| Paso | Resultado |
| --- | --- |
| Fixture de diagnóstico, tercer lanzamiento | Completa, sin errores de script; 15 casos y tres aislamientos por subpaso |
| Hipótesis | 15: 13 como se predijo, 1 con una afirmación de siete no cumplida, 1 no ejercitada |
| [`test_g3_o2_authority.py`](../../tests/test_g3_o2_authority.py) | **31 passed** |
| Regresiones de G3, fixtures que fallan cerrado y contratos de oxígeno | **1563 passed, 27 skipped, 2 xfailed** |
| Guardarraíles, con R2-1 | **Todos PASS**; 346 de 346 requeridas y 78 huecos, los mismos |
| Enlaces de la documentación | Ninguno roto en esta entrega. El comprobador sigue señalando dos, ajenos y anteriores, en `addons/sky_3d/ThirdParty.md` |
| `git diff --check` | Limpio |
| `python -m pytest tests -q -p no:cacheprovider` | **4379 passed, 53 skipped, 2 xfailed, 42 subtests passed** |

Las pruebas nuevas vuelven a evaluar cada veredicto desde las cifras del
registro, comprueban que el registro pertenece al código actual por
huella, leen del código los hechos que este informe afirma —las 53
escrituras, la base constante, la reescritura de la masa baja, la
conversión de la red, la rederivación sin anotar, los dos depósitos y la
cola en tránsito— y prueban el evaluador con filas hechas a mano: un
débito que no llega, uno aplicado dos veces y un tránsito sin contar dan
el hueco que deben.

Los omitidos del contrato de fixtures suben en dos: la fixture de
diagnóstico no juzga y no lleva marca de aprobado.

**Dos contratos anteriores se amplían, de forma estrecha.** La primera
pasada de la cadena los dio en rojo y se dice:

| Contrato | Qué decía | Qué se hizo y por qué |
| --- | --- | --- |
| Fixtures que cargan el banco | Dos: la de aceptación y el diagnóstico de escrituras | Tres: se añade esta, que usa el banco como demanda conocida y no juzga |
| Archivos que pueden nombrar el interruptor de la red | Lista cerrada | Se añaden esta fixture y su prueba: encender la red en tres casos declarados es la única forma de volver a medir los bloqueos de E1 con la red. No la resuelven ni la aprueban |

**Lo que no se ha ejecutado:** la referencia completa y `check_product`,
porque `sim/` no cambia. La identidad con el interruptor apagado no
aplica: no hay interruptor nuevo.

**Salud.** Ningún proceso de Godot al cerrar y ninguno ajeno terminado.
La memoria estuvo por debajo de 6 GiB al empezar; ese tramo se dedicó a
la revisión sin Godot.

## Siguiente encargo

Alcance concreto: **M0 y M1**. Inventario de sala y tránsito como estado,
un solo punto de escritura y `room.o2` derivado, tras un interruptor sin
exportar y apagado, con identidad byte a byte y los cierres de H04 a H07,
H10 y H11 como aceptación. Sin tocar el sumidero, el fuego, las capas ni
la referencia. M2 en adelante, cada una en su encargo.

CO y FED siguen OFF/NO-GO. No se añaden emisiones ni se activa producto.
