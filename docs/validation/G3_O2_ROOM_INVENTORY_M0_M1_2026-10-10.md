# G3 — Autoridad del oxígeno: M0 y M1, inventario de sala y tránsito

**Fecha:** 2026-10-10 · **Línea:** G3 (CO/FED), motor · **Estado:**
implementado tras un interruptor apagado por defecto; **no activado**.

**Alcance.** Las dos primeras etapas del plan de
[`G3_O2_AUTHORITY_2026-10-09.md`](G3_O2_AUTHORITY_2026-10-09.md): M0, las
pruebas, y M1, el inventario de O₂ de sala y su tránsito como estado del
motor. Nada de M2, M3 ni M4. Sin emisiones nuevas y sin producto.
**CO y FED siguen OFF/NO-GO.**

Registro: [`G3_O2_ROOM_INVENTORY_M1_2026-10-10.json`](G3_O2_ROOM_INVENTORY_M1_2026-10-10.json).

> **Lo que M2 sustituye de este documento.** Publicado el mismo día:
> [M2, una selección por recinto y paso](G3_O2_SELECTION_M2_2026-10-10.md).
> Este informe describe el motor de `718061f7` y se conserva como se
> publicó; su registro queda ligado a los archivos de ese commit.
>
> - **El recinto estanco con fuego ya no se rechaza.** Se debita de su
>   inventario. Desaparece el rechazo `fire_sink_outside_the_room_inventory`
>   y su control en la fixture.
> - **El débito presenta una selección.** La operación de consumo del
>   propietario exige la del recinto, paso y corrida.
> - **El fuego ya no lee un número de capa** con el modo encendido, y la
>   segunda escritura deja de declararse consumo: O2-1 y O2-4, que aquí
>   figuran como vigentes, dejan de existir en ese modo.
> - **`CombustionSystem.gd` ya no está intacto por huella.**
> - **El interruptor** también puede levantarlo el runner de escenarios de
>   diagnóstico por sus `engine_overrides`, cosa que aquí no se decía.
> - **«Los casos de casa … pasan por rutas que M1 rechaza»** se ha
>   comprobado: la que los corta es el venteo por sobrepresión.
> - **El hueco de −0,378 kg** que aquí sigue «sin medir» está medido: no
>   es tránsito.

## Decisión

- **Con el interruptor apagado, el motor es el de antes.** Nueve casos
  byte a byte, la referencia completa sin cambio de contenido y el
  diagnóstico del 09-10 vuelto a medir cifra a cifra. Ver «Verificación».
- **Con el interruptor encendido, el oxígeno de cada recinto es una
  cantidad conservada en kg de O₂**, con su tránsito, y el número de sala
  se deriva de ella. Los balances cierran a 9,8 · 10⁻¹⁵ kg en el peor
  paso de todos los casos, con el criterio en 1 · 10⁻⁹ kg.
- **Lo que M1 no cubre se rechaza por su nombre** y detiene la corrida:
  no hay vuelta callada a la ruta histórica ni recorte que lo tape.
- **No se activa.** El interruptor no está exportado, no entra en
  escenarios, editor, catálogo ni producto, y nada lo enciende fuera de
  una fixture.

| Componente del contrato | Estado tras M1 |
| --- | --- |
| Inventario de sala `M` y tránsito `T` como estado | **Hecho**, tras el interruptor |
| Un solo punto de escritura | **Hecho**: un propietario; el recinto rechaza cualquier otra escritura |
| `room.o2` derivado | **Hecho**, con la conversión molar declarada |
| Sumidero, selección del fuego, aceptación de calor | **Sin tocar**: M2 y M3 |
| Números de capa | **Auxiliares históricos**: M4 |
| Activación | **NO-GO**: es otra decisión, con su regeneración de referencia |

## Contrato ejecutable de M1

Se escribió antes de tocar el motor. Es lo que la fixture juzga.

| Pieza | Contrato |
| --- | --- |
| Estado por recinto | `M`, kg de O₂ del recinto. Vive en `RoomModel.o2_inventory_kg`. Es `NAN` mientras el recinto no está bajo autoridad |
| Estado de tránsito | `T`, kg de O₂ despachados y sin entregar. Una sola cola, **del propietario del inventario**: no pertenece al donante ni al receptor |
| Base de referencia | El contenido de referencia del recinto: `n_ref = V × 1,2 kg/m³ / M_aire` moles. No es la masa del gas caliente |
| Unidades | `M` y `T` en kg de O₂. `room.o2`, fracción **molar** de la mezcla de referencia |
| Inicialización | `M = x × n_ref × M_O₂`, con `M_O₂` = 31,998 g/mol y `M_aire` = 28,9647 g/mol. A 0,209, un recinto de 48 m³ guarda 13,299 kg, no 12,038 |
| Conversión de un paquete de gas | kg de O₂ = `x × (kg de gas / M_aire) × M_O₂`. Una fracción molar nunca se multiplica por una masa de gas |
| Derivación | `room.o2 = M / (n_ref × M_O₂)`, en cada escritura. Sin recorte |
| Operaciones | Débito del sumidero; intercambio con el exterior; intercambio entre dos recintos, inmediato o con tránsito; llegada de una entrega. Cada una con causa, cantidad en kg y validación previa |
| Validación | Cantidades finitas y no negativas; fracciones entre 0 y 1; el recinto bajo autoridad; ningún inventario resultante por debajo de cero; una entrega de esta corrida y sin entregar. Un valor desconocido no es un cero |
| Rechazo | La operación no escribe nada, queda anotada con su motivo y el inventario pasa a `rejected`: desde ahí no aplica nada y el motor deja de avanzar. No se reconcilia al final |
| Rutas soportadas | Sumidero sobre el inventario de sala, infiltración, intercambio de fondo entre recintos, intercambio activo con su retardo, llegada del tránsito, puerta que se abre y se cierra, reinicio |
| Campos que siguen siendo históricos | `o2_upper`, `o2_lower`, `upper_o2_mass_tracked`, los acumuladores `o2_*_kg_*` y la cola privada del sistema de oxígeno, que con el modo encendido queda vacía |

### Qué significa «sin tocar el sumidero»

- **Se redirige** el débito que el sumidero ya calcula en kg: misma
  demanda (`potencia × coeficiente × dt`), mismo coeficiente y mismo tope
  del 5 % del inventario por paso. Lo que cambia es a quién se le pide: al
  propietario, que lo aplica a `M`.
- **No se cambia** qué depósito elige el sumidero, ni su ley, ni su tope,
  ni el calor aceptado. Si en un paso el sumidero decide salir del
  inventario de sala —recinto estanco con fuego— M1 **no lo corrige: lo
  rechaza**. Eso es M2.
- **No se deduce ningún débito** de una variación de fracción. El recinto
  no convierte en inventario una fracción que alguien le escriba: la
  rechaza y la cuenta.
- **El tope cambia de unidades, no de ley.** Sigue siendo el 5 % del
  inventario; el inventario ahora está en kg de O₂ reales. Lo que el tope
  recorta queda anotado: pedido, aplicado y recortado. El calor no se
  revisa; eso es M3.

Una consecuencia que se dice: el débito va en kg reales y el inventario
también, así que por cada megajulio la fracción de sala baja un 9,5 %
menos que en la ruta histórica, que opera 0,209 como fracción másica. Es
la corrección de base que el contrato declaraba. Mueve los números de
oxígeno, y por eso M1 no se activa.

### El tránsito tiene signo

La ley histórica de la puerta acredita **ya** a la sala caliente el neto
de dos paquetes opuestos y retrasa ese mismo neto para la sala fría. M1
no cambia esa ley ni su retardo. Cada entrada del tránsito guarda los dos
paquetes: el que viaja hacia el receptor y el que ya se adelantó al
donante. Su neto puede ser negativo: oxígeno que el receptor aún tiene
que entregar. Lo que se conserva es `Σ M + Σ T`. Ningún paquete se cuenta
en dos sitios.

Es una **aproximación heredada**, no una decisión de M1. Cambiarla movería
retardos y concentraciones, y no está autorizado.

### Cómo no se cuentan dos veces las llegadas

- **Por recinto:** `M_final = M_inicial + entradas − salidas − consumo +
  llegadas`. Un intercambio con retardo se anota al despacharlo **solo en
  el donante**. El receptor no anota nada hasta que la entrada llega, y
  entonces anota la llegada, una vez.
- **Por edificio:** `Σ(M + T)_final = Σ(M + T)_inicial + exterior neto −
  consumo`. Una llegada saca de `T` lo mismo que mete en `M`: se cancela y
  no aparece. Los intercambios entre recintos se cancelan igual.

La fixture comprueba las dos formas en cada paso y, aparte, una tercera
que no lee ninguna operación.

## M0: las pruebas, antes de implementar

**Las pruebas fallan sobre el motor anterior por lo que falta.** La
fixture de aceptación se ejecutó contra los archivos del motor del commit
`7b2e12d9`, puestos byte a byte y restaurados después con huella
comprobada: 250 comprobaciones, **147 fallos**
repartidos en los 14 grupos, **0 errores de script** y sin marca de
aprobado. Lee todo lo del modo nuevo con `get`, `in` y `has_method`, para
que cada comprobación falle por la conducta ausente.

Una corrida anterior de esa misma comprobación **se descartó**: la
fixture usaba un formato de texto que GDScript no admite y abortaba una
función. Era un defecto del arnés, no una prueba fallida.

| Lo que el encargo pedía que fallara | Dónde se prueba | Mutante que lo confirma |
| --- | --- | --- |
| `M` solo es un contador reconstruido | B03: el número sigue al inventario; reescribir los acumuladores o las capas no mueve nada; `M` no sale de `número × masa de gas` | W02, L01 |
| Se omite el tránsito | B06: `Σ(M + T)` en cada paso con fuego real | T01 |
| Se escribe `room.o2` por una ruta que evita al propietario | B03 y B04: la escritura no se aplica, se cuenta y detiene la corrida | W01, W02 |
| Se convierte una fracción molar como si fuera másica | B02: oráculo con sus propias constantes | M01, M02 |
| Un reinicio conserva entregas pendientes | B12: tránsito vacío, generación nueva, misma corrida otra vez | R01, D02 |

**C1, C2 y C4**, en [`tests/test_oxygen_contract.py`](../../tests/test_oxygen_contract.py).
Las tres formas de O2-A **se conservan** como evidencia, con una nota que
dice qué demostró E1 de cada una. Se añaden las tres corregidas:

- **C1:** cierra sobre el número de sala con el débito aplicado a **ese**
  inventario, no con la suma de escrituras solapadas.
- **C2:** lo que pide el calor aceptado es lo que sale del inventario, y
  se declara una vez.
- **C4:** la demanda es el calor aceptado.

Sobre las trazas de casa de la corrida de identidad de hoy, con el
interruptor apagado:

| Caso | C1 corregida | C2 corregida | C4 corregida |
| --- | --- | --- | --- |
| `sofa_vent` | cumple | cumple | cumple |
| `o2_closed` | residuo −5,932 kg | calor − débito 6,077 kg | cumple |
| `o2_reopen_300` | residuo −5,582 kg | calor − débito 5,970 kg | cumple |
| `o2_stress_cap` | cumple | calor − débito 8,216 kg | faltan 2,582 kg |

Fallan donde el defecto existe y por lo que el defecto vale: la
rederivación sin anotar del recinto estanco, el depósito que el sumidero
no debita y el recorte del tope. **Son contratos, no regresiones**, y
siguen necesitando una traza para ejecutarse. Las mismas tres
afirmaciones, con el inventario de sala como autoridad y en cada paso,
las juzga la fixture.

De paso se corrigió un ancla: la prueba estática de O2-3 buscaba el tope
escrito como `0.05` y el código lo tiene como constante desde hace
tiempo, así que fallaba por no encontrar la línea. Sigue siendo un fallo
esperado, ahora por el defecto que nombra.

## M1: qué se implementó

| Archivo | Qué |
| --- | --- |
| [`sim/core/RoomOxygenInventory.gd`](../../sim/core/RoomOxygenInventory.gd) | **Nuevo.** El propietario: conversiones, operaciones validadas, la cola de tránsito, el rechazo y el informe. Sin `class_name` y sin `@export`; solo lo carga el motor con el interruptor encendido |
| [`sim/building/RoomModel.gd`](../../sim/building/RoomModel.gd) | `o2_inventory_kg`; `o2` y el inventario rechazan y cuentan cualquier escritura que no sea la del propietario mientras el recinto está bajo autoridad; una entrada única de escritura; el reinicio del recinto lo suelta |
| [`sim/core/OxygenExchangeSystem.gd`](../../sim/core/OxygenExchangeSystem.gd) | Con el propietario presente: el débito del sumidero, la infiltración, los dos intercambios de puerta y las llegadas pasan por él. Con él ausente, el bloque histórico tal cual |
| [`sim/core/GasExchangeSystem.gd`](../../sim/core/GasExchangeSystem.gd) | Sus cuatro escrituras del número de sala se rechazan por su nombre si tienen oxígeno que mover |
| [`sim/core/SimulationEngine.gd`](../../sim/core/SimulationEngine.gd) | El interruptor `o2_room_inventory_enabled`, sin `@export` y apagado por defecto; armado, retirada y fallo; el recorte final no toca un número derivado |

El interruptor no está en ningún otro archivo de `sim/`, `editor/`,
`ui/`, `view/`, `scenarios/`, `scenes/`, `tools/`, `addons/` ni
`assets/`, ni en `project.godot`, `Main.gd`, `check_product.py` o
`run_scenario.py`. Lo comprueba una prueba.

`PrescribedObjectHrrSource.gd` y `CombustionSystem.gd` quedan intactos
por huella.

### Escritores

Las 53 escrituras del diagnóstico siguen en su sitio: 18 del número de
sala, 33 de los dos números de capa y 2 del trazador de masa, que está
apagado. Las 18 del número de sala, con el modo encendido:

| Escritor del número de sala | Con el modo encendido |
| --- | --- |
| Sumidero de sala e infiltración (`OxygenExchangeSystem`, 1) | **Adaptado.** Dos operaciones del propietario |
| Intercambio de fondo entre recintos (2) | **Adaptado.** Una operación con los dos paquetes, sin banda muerta |
| Intercambio activo, su cola y las entregas que llegan (1, compartida) | **Adaptado.** Una operación al despachar, con el neto de la sala fría en el tránsito del propietario; al llegar, el propietario retira la entrada y acredita la misma cantidad. La escritura histórica no se alcanza |
| Rederivación desde las capas, recinto estanco con fuego (1) | **Rechazado por nombre**, en la ruta: `fire_sink_outside_the_room_inventory` |
| Hueco exterior con diferencia de temperatura, sus dos variantes (2) | **Rechazado por nombre**, donde escribiría: `exterior_opening_with_temperature_difference` |
| Venteo por sobrepresión, transporte del bucle de gases, entrega de parcelas, PPV (`GasExchangeSystem`, 4) | **Rechazados por nombre** si mueven oxígeno. Con delta cero no escriben |
| Red de presión (1) | **Rechazada al armar** |
| HVAC (1) y las cuatro mezclas de puerta del térmico (4) | **Rechazados por la guarda del recinto**, sin nombre de ruta: la escritura no se aplica, se cuenta y detiene la corrida. Probado el mecanismo con una escritura directa, no cada ruta |
| Recorte final del motor (1) | **Adaptado.** No escribe un número derivado |

Los números de capa los siguen escribiendo sus 33 escrituras históricas.
Ninguna puede llegar a `M`.

### Configuraciones rechazadas

| Qué | Cuándo | Cómo se ve |
| --- | --- | --- |
| Red de presión encendida | Al armar | `o2_room_inventory_rejected`; ningún recinto bajo autoridad; el motor no avanza |
| Banco diagnóstico del Test016 encendido | Al armar | Igual |
| Libro de balance de G3 encendido | Al armar | Igual |
| Modo de oxígeno del fuego distinto del histórico, o cualquiera de sus variantes | Al armar | Igual |
| Fuego en un recinto estanco | En el paso en que el sumidero sale del inventario de sala | `o2_room_inventory_failed`, ruta nombrada, y el motor deja de avanzar |
| Hueco exterior con un fuego detrás | En el paso en que la ruta escribiría | Igual |
| Cambiar el interruptor sin reiniciar, en cualquier sentido | En el paso siguiente | `o2_room_inventory_switch_changed_without_reset` |
| Uno de esos interruptores cambiado a mitad de corrida | Al abrir el paso | Rechazo con el mismo motivo que al armar |

**Un recinto sin hueco exterior no se rechaza por serlo.** En reposo, con
capas que se relajan o con una capa colapsada, es un caso soportado y
probado. Se rechaza cuando arde, que es cuando su sumidero toma otra
ruta.

**El banco del Test016 y M1 no conviven todavía**, y se justifica: el
banco deshace un paso rechazado restaurando números de oxígeno por
instantánea y pregunta la disponibilidad a los números de capa. Con el
inventario como autoridad eso tendría que restaurar `M` y `T` por el
propietario y leer la disponibilidad del inventario: es selección y
disponibilidad, M2 y M3. Su contrato y sus resultados no cambian.

### Aproximaciones

- **Base de referencia del recinto**, no la masa del gas caliente. Exacta
  mientras los moles del recinto no cambian.
- **Mezcla de referencia de aire seco** en todas las conversiones.
- **Sin composición de los productos:** la combustión no cambia los moles
  ni la masa molar del recinto.
- **Sin inventario zonal físico.** Los números de capa son
  auxiliares históricos: no son derivados conservativos ni una partición
  de `M`.
- **El tránsito es el neto con signo** de un intercambio a contracorriente,
  como lo retrasa la ley histórica.
- **Sin banda muerta en el transporte.** La ruta histórica descarta un
  crédito menor de 10⁻⁶ kg después de haber hecho el débito; aquí lo que
  sale de un recinto entra en el otro.
- **Sin techo.** Ningún número de sala se recorta a 0,209. En los casos
  medidos ninguno lo supera en más de 10⁻¹².

## Evidencia de que `M` y `T` son estado

- **Se actúa sobre `M` y el número lo sigue.** Un débito de 0,5 kg por el
  propietario baja `M` en 0,5 kg exactos y deja `room.o2` en el valor
  derivado.
- **No al revés.** Escribir `room.o2 = 0,10` no cambia ni el número ni
  `M`; escribir `o2_inventory_kg` tampoco. Las dos escrituras se cuentan y
  el paso siguiente detiene la corrida.
- **Los acumuladores no gobiernan.** Reescribir los cuatro no mueve `M`
  ni el número.
- **Las capas no gobiernan.** Con capas que se relajan o se reescriben,
  `M` y el número quedan bit a bit, con cero operaciones.
- **`M` no se puede reconstruir** como número de sala por masa de gas:
  difiere en más de 1 kg.
- **`T` es lo que hace cerrar el edificio.** Con fuego real hubo hasta
  0,1365 kg en tránsito; quitar la entrada de la cola rompe el
  balance (mutante T01).
- **Sobrevive a lo que debe y a nada más.** Un reinicio lo vacía, la
  generación cambia y los identificadores de entrega no se reutilizan.

## Balances y resultados

287 comprobaciones en 14 grupos, todas cumplidas, sobre el motor real.
Recintos de 48 y 38,4 m³, puerta de 0,9 × 2,0 m, valores de producto
salvo lo que cada caso declara.

Tres balances por paso; la tabla da **el peor paso** de cada caso, en kg:

1. **Por operaciones:** cada recinto cambia lo que el propietario le
   aplicó.
2. **Del edificio:** `Σ(M + T)` cambia en exterior neto menos consumo.
3. **Por forma cerrada, sin leer ninguna operación:** el consumo es la
   demanda de la potencia del paso, con su tope; el exterior es la ley de
   infiltración sobre lo que el recinto contiene cuando le toca.

| Caso | Paso | Por operaciones | Del edificio | Por forma cerrada |
| --- | --- | --- | --- | --- |
| Reposo, recinto sellado (H01) | 0,5 s | 0 | 0 | 0 |
| Demanda conocida de 20 kW, 120 s (H04) | 0,5 s | 1,9 · 10⁻¹⁵ | 3,9 · 10⁻¹⁵ | 3,9 · 10⁻¹⁵ |
| La misma (H10) | 0,25 s | 1,8 · 10⁻¹⁵ | 3,7 · 10⁻¹⁵ | 3,7 · 10⁻¹⁵ |
| Fuego real, dos salas, 120 s (H04) | 0,25 s | 3,5 · 10⁻¹⁵ | 7,2 · 10⁻¹⁵ | 7,2 · 10⁻¹⁵ |
| El mismo (H10) | 0,125 s | 4,3 · 10⁻¹⁵ | 9,8 · 10⁻¹⁵ | 9,8 · 10⁻¹⁵ |
| Transporte entre dos salas (H05) | 0,5 s | 1,7 · 10⁻¹⁵ | 3,6 · 10⁻¹⁵ | 3,6 · 10⁻¹⁵ |
| Puerta exterior, infiltración (H06) | 0,5 s | 1,4 · 10⁻¹⁵ | 1,4 · 10⁻¹⁵ | 1,4 · 10⁻¹⁵ |
| La misma | 0,25 s | 1,1 · 10⁻¹⁵ | 1,1 · 10⁻¹⁵ | 1,1 · 10⁻¹⁵ |
| Puerta cerrada, abierta, cerrada (H07) | 0,5 s | 1,7 · 10⁻¹⁵ | 3,6 · 10⁻¹⁵ | 3,6 · 10⁻¹⁵ |
| Demanda por encima del tope | 0,5 s | 1,1 · 10⁻¹⁵ | 2,7 · 10⁻¹⁵ | 2,7 · 10⁻¹⁵ |
| Dos capas que se relajan (H08) | 0,5 s | 0 | 0 | 0 |
| Capa baja colapsada (H09) | 0,5 s | 0 | 0 | 0 |

Criterio: 1 · 10⁻⁹ kg en cada paso. Peor de todos: 9,8 · 10⁻¹⁵ kg.

**Lo que da cada caso:**

- **Demanda conocida.** La potencia la escribe la fixture sobre el
  subpaso de oxígeno, sin fuego ni calor: 2,4 MJ piden 0,1824 kg y salen
  0,1824 kg con cada uno de los dos pasos. Nada recortado.
- **Fuego real.** 22,89 MJ y 1,7395 kg debitados con el paso de
  0,25 s; 22,81 MJ y 1,7335 kg con el de 0,125 s. En los dos, el
  débito es 0,076 kg por MJ del calor que el recinto declara, y lo que
  anota el acumulador es lo aplicado. 343 y 683 intercambios con
  retardo. **Las dos trayectorias no son iguales ni se exige**: la
  discretización no lo garantiza. Se exige que cada una cierre.
- **Transporte.** Sin fuego ni exterior, `Σ(M + T)` no cambia en ningún
  paso, leído solo del estado. La sala rica nunca gana y la pobre nunca
  supera a la que la alimenta.
- **Exterior.** Cada paso es `x + k (x_ext − x)` a 1,6 · 10⁻¹⁵, y el
  final es la forma cerrada. Nunca por encima del aire exterior.
- **Puerta.** Cerrada: ninguna operación y los dos inventarios bit a bit.
- **Tope.** De 7,6 kg pedidos se aplican 5,337 y se anotan 2,263
  como recortados. Aplicado más recortado es lo pedido. Un tope no es un
  rechazo: la corrida sigue siendo válida.
- **Reinicio (H11).** La misma corrida da la misma huella tras un
  reinicio, y otra vez después de revocar, quitar el edificio y dejar el
  motor sin preparar.
- **Sin enriquecimiento.** Ninguna concentración supera la de su fuente
  en ningún caso. No hay recorte que lo imponga.

## Controles negativos

Todos en la fixture, grupos B13 y B14. En todos el rechazo es explícito y
el estado queda como estaba.

| Control | Resultado |
| --- | --- |
| Red de presión encendida | No arma; motivo nombrado; ningún recinto bajo autoridad; el reloj no avanza |
| Banco del Test016 encendido | Igual |
| Modo de oxígeno `lower` | Igual |
| Recinto estanco con fuego | Rechazado en el primer paso con potencia; el sumidero no debita nada; nadie escribe el número por detrás |
| Puerta exterior con fuego | Válido 80 pasos sin fuego; rechazado en el paso 89 tras la ignición, por la ruta del hueco |
| Interruptor apagado o encendido a mitad de corrida | Rechazado; el reloj se para; nada se arma por detrás |
| Escritura directa de `room.o2` y de `M` | No se aplican; contadas; la corrida se detiene |
| Entrega aplicada dos veces | La segunda se rechaza y no acredita nada |
| Entrega de otra corrida | Rechazada |
| Traslado que una de las dos salas no puede pagar, con y sin retardo | Rechazado entero: ninguna sala cambia y nada entra en el tránsito |
| Cantidad desconocida, no numérica o negativa | Rechazada; no se lee como cero |
| Débito mayor que el inventario o que su propia demanda | Rechazado entero |
| Fracción inicial que no es una fracción (seis valores) | Rechazada; inventario intacto |
| Estado inicial declarado tras el primer paso | Rechazado |
| Después de un rechazo | Ninguna operación se aplica y el motor no simula más |

## Mutaciones

22 mutantes de código sobre el motor real, declarados antes de ejecutar
con el grupo que debía verlos. Control en verde. **22 de 22 muertos
donde se declaró**; ningún superviviente, ninguno inválido y ninguno
muerto solo en otro sitio. Cero bajas por sintaxis. Cada archivo se
restauró con huella SHA-256 comprobada. Evidencia en
`runs/g3_o2_room_inventory_mutations_20261010_005217`, fuera del repositorio publicado.

Los ocho declarados con el plan son D01, T01, W01, C01, R01, M01, L01, K01.
Los demás son controles del mismo contrato.

| | Defecto que inyecta | Archivo | Debía verlo | Resultado |
| --- | --- | --- | --- | --- |
| D01 | El débito del sumidero sale dos veces del inventario | `RoomOxygenInventory.gd` | B05 | Muerto en B05; 26 comprobaciones fallidas |
| T01 | Un intercambio con retardo cambia al donante y no deja nada en cola para el receptor | `RoomOxygenInventory.gd` | B06 | Muerto en B06; 15 comprobaciones fallidas |
| W01 | El recorte final del motor escribe el número de sala de un recinto bajo autoridad | `SimulationEngine.gd` | B04 | Muerto en B04; 58 comprobaciones fallidas |
| C01 | El receptor recibe oxígeno que el donante no pierde | `RoomOxygenInventory.gd` | B07 | Muerto en B07; 44 comprobaciones fallidas |
| R01 | Un reinicio conserva las entregas de la corrida anterior | `RoomOxygenInventory.gd` | B12 | Muerto en B12; 8 comprobaciones fallidas |
| M01 | El inventario inicial es la fracción molar por la masa de gas | `RoomOxygenInventory.gd` | B02 | Muerto en B02; 26 comprobaciones fallidas |
| L01 | La mezcla de los dos números de capa se escribe sobre el inventario | `OxygenExchangeSystem.gd` | B10 | Muerto en B10; 49 comprobaciones fallidas |
| K01 | Lo que recorta el tope del sumidero no llega al propietario | `OxygenExchangeSystem.gd` | B11 | Muerto en B11; 3 comprobaciones fallidas |
| M02 | El oxígeno de un paquete de gas es su fracción molar por su masa | `RoomOxygenInventory.gd` | B02 | Muerto en B02; 14 comprobaciones fallidas |
| W02 | Cualquier escritor puede fijar el número de sala de un recinto bajo autoridad | `RoomModel.gd` | B03 | Muerto en B03; 3 comprobaciones fallidas |
| E01 | Una entrega ya hecha se queda en la cola y vuelve a vencer | `RoomOxygenInventory.gd` | B06 | Muerto en B06; 14 comprobaciones fallidas |
| E02 | La misma entrega puede aplicarse dos veces | `RoomOxygenInventory.gd` | B14 | Muerto en B14; 3 comprobaciones fallidas |
| G01 | Se acredita una entrega de otra corrida | `RoomOxygenInventory.gd` | B14 | Muerto en B14; 1 comprobación fallida |
| P01 | Se aplica un traslado que el receptor no puede pagar: se escribe un inventario negativo | `RoomOxygenInventory.gd` | B14 | Muerto en B14; 3 comprobaciones fallidas |
| O01 | Cambia la ley de infiltración: el gas sale al número que el sumidero acaba de bajar | `OxygenExchangeSystem.gd` | B06 | Muerto en B06; 3 comprobaciones fallidas |
| B01 | El tope es el 5 % de una fracción molar por una masa de gas, no del inventario | `OxygenExchangeSystem.gd` | B11 | Muerto en B11; 2 comprobaciones fallidas |
| S01 | Un recinto estanco que arde se debita como si su sumidero tomara el inventario de sala | `OxygenExchangeSystem.gd` | B13 | Muerto en B13; 4 comprobaciones fallidas |
| X01 | El hueco exterior caliente deja de rechazarse por su nombre | `OxygenExchangeSystem.gd` | B13 | Muerto en B13; 2 comprobaciones fallidas |
| N01 | El inventario arma con la red de presión encendida | `RoomOxygenInventory.gd` | B13 | Muerto en B13; 6 comprobaciones fallidas |
| F01 | Una corrida que el inventario rechazó sigue avanzando | `SimulationEngine.gd` | B13 | Muerto en B13; 6 comprobaciones fallidas |
| Z01 | El interruptor cambia a mitad de corrida y la corrida sigue | `SimulationEngine.gd` | B13 | Muerto en B13; 2 comprobaciones fallidas |
| D02 | Un reinicio sin edificio, o sin estar listo, retorna antes de retirar el inventario y su tránsito | `SimulationEngine.gd` | B12 | Muerto en B12; 5 comprobaciones fallidas |

## La ruta histórica no ha cambiado

- **Identidad con el interruptor apagado:** ver «Verificación».
- **El diagnóstico del 09-10, vuelto a medir** sobre este árbol con el
  interruptor apagado: 13 hipótesis comparadas con su registro
  publicado, **idénticas cifra a cifra**. El registro publicado no se
  reescribe; su prueba pasa a ligarlo a los archivos de su commit.

## Verificación

Todo secuencial, un Godot cada vez y siempre bajo el monitor. Mínimo de
6 GiB disponibles sin rebajar: la cadena esperó a tener 6,6 antes de cada
paso y arrancó cada uno con entre 7,01 y 7,82.
`APPDATA`, `TEMP`, `TMP` y `basetemp` fuera del repositorio.

Orden: fixture, mutaciones, identidad con el interruptor apagado,
registro, regresiones, referencia, guardarraíles, producto y global. La
identidad va antes que las regresiones porque el registro lee sus trazas.

| Paso | Resultado |
| --- | --- |
| Fixture de aceptación sobre el motor de `7b2e12d9` | 250 comprobaciones, **147 fallos** en los 14 grupos, 0 errores de script |
| Fixture de aceptación sobre este árbol | **287 comprobaciones, 0 fallos**, sin errores de script |
| Mutaciones de código | 22 declaradas; control en verde; **22 muertas donde se declaró**; 0 supervivientes, 0 inválidas; fuentes restauradas por SHA-256 |
| [`test_g3_o2_room_inventory.py`](../../tests/test_g3_o2_room_inventory.py) | Dentro de las regresiones: registro ligado al código por huella, balances, mutaciones y contrato leído del código |
| Regresiones de G3, fixtures que fallan cerrado, contratos de oxígeno y de la red | **1619 passed, 30 skipped, 2 xfailed** |
| **Identidad con el interruptor apagado** | **9 de 9 casos byte a byte** contra la corrida de `7b2e12d9`: registros, trazas, instantáneas y eventos |
| Banco del Test016 | Su fixture de aceptación corre dentro de las regresiones, sobre este motor, en verde. Sus 43 mutaciones conservan sus anclas |
| Diagnóstico del 09-10 vuelto a medir, interruptor apagado | 13 hipótesis, idénticas cifra a cifra |
| **Referencia completa**, monitorizada | **346 de 346** requeridas PASS; los mismos 78 huecos |
| Corpus de la referencia | 382 archivos: 381 idénticos byte a byte. El único que cambia es `reference_checks.json`, y **solo en `generated_at`** |
| Tiempo de pared de la referencia | 3172 s, frente a 3084 s de la tanda del 09-10: +2,9 %. Por caso, entre −6 % y +10 %. No es una medida de rendimiento |
| Guardarraíles, con R2-1 | **Todos PASS** |
| `check_product.py` | **168 PASS** |
| Enlaces de la documentación | Ninguno roto en esta entrega. El comprobador sigue señalando dos, ajenos y anteriores, en `addons/sky_3d/ThirdParty.md` |
| `git diff --check` | Limpio |
| `python -m pytest tests -q -p no:cacheprovider` | **4424 passed, 56 skipped, 2 xfailed, 42 subtests passed** |

La referencia se regeneró porque `sim/` cambia. No se ha modificado
ninguna expectativa ni se ha establecido una línea base nueva.

**Tres contratos anteriores se tocan, de forma estrecha, y se dice:**

| Contrato | Qué decía | Qué se hizo y por qué |
| --- | --- | --- |
| El registro del diagnóstico del 09-10 pertenece a su código | Comparaba con los archivos de hoy | Compara con los de su commit, `7b2e12d9`. El motor ha cambiado; el registro es evidencia de su checkpoint y no se reescribe. Que la ruta histórica siga dando esas cifras se mide aparte |
| Fixtures que nombran el banco del Test016 | Tres | Cuatro. La de M1 no lo carga: levanta solo su interruptor, sin caso, para probar que la combinación se rechaza |
| Archivos que pueden nombrar el interruptor de la red | Lista cerrada | Se añaden la fixture de M1 y su prueba: la enciende en un control negativo. No la resuelve ni la aprueba |

La auditoría del diseño del banco del 08-10 cuenta una expresión del
sumidero y la encontró dos veces en la primera versión de M1. Se corrigió
**el código de M1**, que ahora la lee de un único sitio; ese contrato no
se tocó.

### Lo que no se ha ejecutado

- **Los casos de casa con el modo encendido.** Pasan por rutas que M1
  rechaza.
- **Ninguna comparación de potencia, extinción o exposición** entre el
  modo encendido y la ruta histórica.
- **Cada ruta rechazada por la guarda del recinto** —HVAC, mezclas de
  puerta del térmico—: está probado el mecanismo, no cada una.
- **Venteo, PPV y entrega de parcelas** con oxígeno que mover: su rechazo
  está en el código y se lee en una prueba; no hay un caso que lo dispare.

### Lo que salió mal por el camino

- **Una corrida de «antes de M1» se descartó**: el arnés tenía un formato
  de texto que GDScript no admite. Se corrigió y se repitió; la del
  registro es posterior y la hace el propio runner.
- **Las mutaciones se ejecutaron dos veces.** La primera tanda, 22 de 22,
  fue sobre una versión de M1 que repetía una expresión del sumidero. Al
  corregirla cambió el archivo, y la tanda del registro es la segunda,
  sobre el código que se publica.
- **Tres runners de mutación de otras entregas se invocaron por error**
  con una opción que no conocen, al comprobar anclas. El monitor no llegó
  a lanzar Godot, las fuentes quedaron intactas y queda una carpeta vacía
  en `runs/`.

**Salud.** Ningún proceso de Godot al cerrar y ninguno ajeno terminado.
La memoria estuvo por debajo de 6 GiB al empezar; ese tramo se dedicó a
leer el motor y a escribir el contrato.

## Límites

- **No está activado** y sus números no se han comparado con los de la
  ruta histórica en escenarios de producto: el efecto sobre potencia,
  extinción y exposición está sin cuantificar. Es condición para activar.
- **Los casos de casa no se han corrido con el modo encendido.** Un fuego
  de producto pasa por rutas que M1 rechaza —recinto estanco, hueco
  exterior—, así que el hueco de −0,378 kg de `o2_reopen_300` sigue
  **sin medir**. M1 da el instrumento: el tránsito ya es estado legible.
- **El fuego sigue leyendo el número inferior** mientras el sumidero
  debita la sala. M1 no lo toca.
- **Lo que el tope recorta sigue sin bajar el calor.** Ahora queda
  anotado.
- **Venteo, PPV, HVAC, hueco exterior caliente y red de presión** no
  están ni adaptados ni ejercitados más allá de su rechazo.
- **El tránsito con signo** es la ley histórica, no un modelo físico de
  un paquete que viaja.
- Nada de esto dice que los números vayan a parecerse más a un ensayo.

## Qué queda

| Etapa | Qué | Lo que M1 deja preparado |
| --- | --- | --- |
| M2 | Una selección por recinto y paso para fuego y sumidero; el recinto estanco debita el inventario; retirar la segunda escritura como consumo | El rechazo de hoy marca el sitio exacto; el propietario ya tiene la operación de débito |
| M3 | Disponibilidad antes de aceptar el calor | El recorte ya queda anotado por paso; la cota de masa ya lee el inventario y su tránsito |
| M4 | El reparto `M_alta` dentro de `M`, en lugar de los trazadores | El total ya no lo puede tocar ninguna capa |

## Siguiente encargo

**M2**, tras el mismo interruptor apagado:

- **Una selección por recinto y paso** —depósito, concentración y
  disponible— calculada una vez y usada por el fuego y por el sumidero.
- **La ruta de recinto estanco debita `M`**: el rechazo
  `fire_sink_outside_the_room_inventory` se sustituye por un débito del
  propietario, y desaparece la rederivación desde las capas.
- **La segunda escritura** sobre la capa alta deja de declararse consumo;
  decidir antes si es desplazamiento por productos o se retira.
- **Hasta M4 no hay reparto entre capas**: la concentración que lea el
  fuego en M2 sale del inventario de sala, y se dice.
- **Aceptación:** el fuego real con un solo depósito; `o2_closed` y
  `o2_reopen_300` corridos con el modo encendido, cerrando con el tránsito
  medido; C1 y C2 corregidas pasando sobre esas trazas.
- **Requiere tocar `CombustionSystem.gd`**, hoy protegido por huella, y
  convivir con el banco del Test016 o seguir rechazándolo.
- **Fuera de M2:** bajar el calor cuando el oxígeno no cabe (M3) y el
  reparto entre capas (M4).

M2 mueve qué oxígeno lee el fuego: es física, y su efecto en potencia y
extinción hay que medirlo antes de proponer activar nada.
