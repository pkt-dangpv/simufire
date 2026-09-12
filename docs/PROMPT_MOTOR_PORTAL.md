# Prompt: el portal y la caja de escalera como recinto de verdad

## Qué se pide, y por qué

El usuario lo dijo así el 2026-09-12, hablando del penacho de humo:

> *«quita el penacho de la puerta de entrada. ahi el humo debe primero chocar
> contra el techo y luego hacer efecto chimenea por la escalera»*

Es correcto, y con los escenarios tal y como se dibujan hoy **no pasa**. No por
la vista ni por falta de motor: **porque el rellano no está en el modelo**. La
puerta de la vivienda da al ambiente, así que lo que sale por ella se va a la
calle y no se acumula en ninguna parte.

Y sí puede pasar: al medirlo (§ *MEDIDO*) resultó que el motor hace la física
entera en cuanto el rellano existe como recinto. Lo que falta es dibujarlo.

## Lo que hay hoy, medido

En las once plantillas de `scenarios/`, la puerta de entrada de la vivienda está
siempre como `door` contra `b = -1`, el ambiente. Da igual que el edificio sea un
bloque de pisos o una unifamiliar: **es el mismo dato**. En
`preset_piso_mediterraneo` conviven las dos puertas exteriores a la vez —la del
portal y una balconera a la calle— y nada en el fichero las separa.

Consecuencias:

1. **Para el motor**, lo que sale por la puerta de la vivienda se va al ambiente:
   temperatura de la calle, O₂ de la calle, y presión de viento según la fachada.
   No se acumula en ningún sitio, no choca contra ningún techo y no sube por
   ninguna escalera.
2. **Para la vista**, hasta el 2026-09-12 esa puerta echaba penacho de humo a la
   calle igual que la entrada de un chalet. Eso ya está corregido
   (`view/geometry/OpeningKinds.gd`): la puerta del portal no ventila al aire
   libre. Pero corregir la mentira no añade la física.

El rellano **sí existe en la vista**: el mundo de primera persona le construye
losa, escalera, plafón y caja. Es decorado. En el modelo no hay ninguna sala ahí.

## Qué se propone

La misma representación que resolvió el patio (ver
[PROMPT_MOTOR_PATIO.md](PROMPT_MOTOR_PATIO.md)), que **funcionó sin tocar el
motor** porque solo usa piezas que ya existen:

1. **Una zona de rellano por planta**, con la huella del rellano que la vista ya
   calcula, y la altura de la caja.
2. **Encadenadas con huecos verticales** entre plantas consecutivas: es el ojo de
   la escalera, y es lo que produce el tiro.
3. **La puerta de cada vivienda da a la zona de rellano de su planta**, no a
   `-1`.
4. **El portal remata abajo en la calle**: el zaguán tiene su puerta a la vía
   pública, que sí es `b = -1`. Arriba, si hay claraboya o trampilla, un hueco
   vertical al exterior; si no la hay, el conducto queda **cerrado por arriba**, y
   ahí está la diferencia importante con el patio.

## La diferencia con el patio, que es la que manda

Un patio está **abierto al cielo**: apenas se presuriza, y por eso el usuario
aceptó la física completa sin miedo a la sobrepresión hacia las viviendas.

Una caja de escalera **está cerrada por arriba** salvo que tenga exutorio. Eso
cambia el resultado, y en la dirección peligrosa: el humo que entra se acumula
bajo el techo del último rellano y **presuriza la caja**, que es justo el
mecanismo por el que una escalera sin ventilar mata gente en plantas altas. No
hay que suavizarlo.

De ahí que el orden correcto sea: primero medir el caso cerrado, luego el caso
con exutorio, y comprobar que la diferencia entre los dos es grande. Si sale
pequeña, algo está mal en el área o en la resistencia del remate.

## MEDIDO el 2026-09-12: el motor ya lo hace

Igual que con el patio, antes de escribir ninguna herramienta se montó a mano el
escenario y se midió. **Sale sin tocar el motor.** Tres plantas, una vivienda y
un rellano por planta, los rellanos encadenados por el ojo de la escalera, la
puerta de cada vivienda dando al suyo, el zaguán con su puerta a la calle
cerrada, y fuego en la vivienda de la planta baja (300 s de simulación).

| | rellano P0 | rellano P1 | rellano P2 |
|---|---|---|---|
| **Caja cerrada** · T máx | 539 °C | 286 °C | 155 °C |
| **Caja cerrada** · sobrepresión máx | 1,5 Pa | 6,0 Pa | **11,4 Pa** |
| **Caja cerrada** · humo máx | — | 0,054 kg | 0,135 kg |
| **Con exutorio** · T máx | 414 °C | 330 °C | 117 °C |
| **Con exutorio** · sobrepresión máx | 0,8 Pa | 5,5 Pa | **3,7 Pa** |
| **Con exutorio** · humo máx | — | 0,033 kg | 0,043 kg |

Lo que dicen estos números:

1. **El humo entra en el rellano y sube.** La temperatura cae con la altura
   (539 → 286 → 155 °C), que es el gradiente de una chimenea, y el humo llega a
   los rellanos altos con el fuego a 554 °C en la vivienda.
2. **La caja cerrada se presuriza, y por arriba.** La sobrepresión crece con la
   altura hasta 11,4 Pa en el último rellano. Es el mecanismo que mata en plantas
   altas, y sale solo: nadie lo ha impuesto.
3. **El exutorio lo alivia, y mucho.** Los mismos 11,4 Pa bajan a 3,7 —un tercio—
   y el humo acumulado arriba pasa de 0,135 a 0,043 kg. La diferencia entre las
   dos variantes es grande, que era justamente la condición para fiarse del
   modelo.

**Un matiz de honradez sobre el enunciado.** El usuario pidió que el humo
*«choque contra el techo»*. Un modelo de dos zonas no resuelve el chorro de techo
como tal: lo que se ve es **la capa alta del rellano calentándose y engordando**,
que es su equivalente en este modelo. No es lo mismo y conviene no confundirlo.

Ficheros del experimento: `make_portal.py` y `leer_portal.py` en el cuaderno de
la sesión; el escenario tiene 6 salas y 9 aperturas (10 con exutorio).

## MEDIDO OTRA VEZ, dibujado con la herramienta (2026-09-12)

El mismo edificio, pero el portal **dibujado con la herramienta del editor**
(tecla `O`) y exportado por el camino real. Tres cosas nuevas:

**1. El ojo no puede ser la huella de la escalera.** La herramienta nació
encadenando las zonas con el hueco que calcula una escalera: 2,46 × 3,0 m, casi
todo el rellano. Con eso el rellano de arriba se clava en **900,0 °C**, más que la
propia vivienda en llamas (554 °C). Con un ojo de 1,4 × 1,4 m, en el mismo
escenario, sale el tiro de una caja de escalera. El motor toma el área del hueco
como paso libre, y los tramos de una escalera de obra lo tapan casi entero. La
herramienta usa ahora `PORTAL_EYE_SIDE_M = 1,40`, y lo conserva al redimensionar.
La vista no usa esa medida, porque dibuja el hueco con la geometría de la
escalera.

**2. Las dos variantes, con el portal de la herramienta:**

| | Portal R | Portal R+1 | Portal R+2 | vivienda R+2 |
|---|---|---|---|---|
| **Cerrada** · sobrepresión máx | 1,5 Pa | 5,7 Pa | **9,6 Pa** | |
| **Cerrada** · humo máx | 0,045 kg | 0,061 kg | 0,104 kg | **0,26 kg** |
| **Con exutorio** 1 × 1 m · sobrepresión máx | 0,7 Pa | 5,9 Pa | **4,9 Pa** | |
| **Con exutorio** · humo máx | 0,018 kg | 0,033 kg | 0,045 kg | **0,03 kg** |

La caja cerrada se presuriza por arriba y **devuelve el humo a la vivienda alta**,
que lo recibe a los 178 s. El exutorio parte la sobrepresión de arriba por dos y
divide por nueve el humo que entra en esa vivienda. La diferencia es grande, que
era la condición.

**3. Para la línea del motor: el tope de 900,0 °C aparece por tercera vez.** Salió
en el patio (Patio P1, `PROMPT_MOTOR_PATIO.md`), con el ojo grande de arriba, y
también **en la variante con exutorio**: Portal R marca 900,0 °C y Portal R+2
554 °C. Con la caja cerrada las temperaturas son 346 / 119 / 96 °C. Queda como
observación, no como conclusión: **en las configuraciones con un hueco vertical
grande o abierto al cielo, la temperatura de las zonas no es de fiar**. Las
presiones y el humo sí se mueven en la dirección esperada.

Y una diferencia con la medición hecha a mano, sin explicar todavía. Con el mismo
ojo, la caja cerrada da 346 / 119 / 96 °C y 9,6 Pa, frente a 539 / 286 / 155 °C
y 11,4 Pa. La forma es la misma y los números no; la herramienta, además, carga
las zonas con los campos de escalera (`stair_has_walls`, dirección de subida).

## MEDIDO el 2026-09-13: las cuatro preguntas que quedaban

Seis variantes del mismo edificio, **todas dibujadas con la herramienta** y
exportadas por el camino del editor, 300 s cada una. Condiciones comunes:
- fuego en la vivienda 1 de la planta baja, con su puerta al rellano abierta;
- en las demás viviendas, puertas y ventanas cerradas;
- caja cerrada por arriba.

Ficheros: `export_variante.gd` y `leer_variantes.py`, en el cuaderno de la
sesión.

| variante | fuego: HRR pico · quemado | humo Portal R+2 | sobrepresión R+2 | viviendas vecinas |
|---|---|---|---|---|
| **A** sin portal, ventana abierta | 2250 kW · 348 MJ | — | — | 0 kg |
| **B** portal, ventana abierta | 2250 kW · 376 MJ | 0,161 kg | 4,6 Pa | 0 kg |
| **C** sin portal, ventana cerrada | 2492 kW · 344 MJ | — | — | 0 kg |
| **D** portal, ventana cerrada | 2768 kW · 401 MJ | **0,303 kg** | **11,6 Pa** | 0 kg |
| **E** portal, dos viviendas por planta | 2250 kW · 379 MJ | 0,245 kg | 4,2 Pa | 0 kg |
| **F** portal, zaguán abierto | 2250 kW · 374 MJ | 0,158 kg | 3,8 Pa | 0 kg |

**1. Aditividad: se cumple por construcción.** Entre la medición del 2026-09-12
(`d622e096`) y hoy no ha cambiado ni una línea de `sim/`, de
`editor/ScenarioSerializer.gd` ni del lanzador `tools/run_scenario_headless.gd`.
Lo nuevo solo actúa en un escenario que tiene portal: la herramienta, su guarda
en el editor y la vista. Un escenario sin portal da los mismos números. La
comparación directa en una copia del repositorio en `d622e096` no se pudo
montar: un PDF de `docs/literature` tiene un nombre demasiado largo para Windows.

**2. Cuando la vivienda solo ventila hacia el rellano (B → D), el portal se lo
lleva todo.** Con la ventana cerrada, todo lo que sale del fuego va a la caja:
- el humo del rellano de arriba casi se duplica (0,161 → 0,303 kg);
- la sobrepresión de arriba pasa de 4,6 a 11,6 Pa.

El fuego, en cambio, **no se ahoga**. Quema más, no menos (376 → 401 MJ, pico
2768 kW), con los regímenes casi idénticos (59 % limitado por ventilación en
las dos). En cinco minutos, la caja de escalera tiene aire de sobra que
ofrecerle. Queda como observación, no como conclusión: el fuego apenas se nota
entre A y C, y la puerta a un portal de ~46 m³ por planta alimenta más que la
misma puerta al aire libre (D frente a C: 401 frente a 344 MJ), lo que merece
mirarlo desde la línea del motor.

**3. Con dos viviendas por planta (B → E) el portal es más grande y se reparte.**
El portal pasa de 4 × 4 a 4 × 8 m. Llega más humo arriba (0,161 → 0,245 kg),
porque la caja tiene más volumen que llenar antes de que la capa baje, pero con
un poco menos de presión (4,6 → 4,2 Pa).

**4. El zaguán abierto (B → F) alivia poco.** La sobrepresión de arriba baja de
4,6 a 3,8 Pa. El humo que llega arriba es prácticamente el mismo (0,161 → 0,158
kg), y los tiempos de llegada no cambian (155 s arriba). No aparece el tiro de
abajo arriba que se esperaba: con la caja cerrada por arriba, abrir abajo no
crea una chimenea.

**Y dos observaciones para la LÍNEA DEL MOTOR**, que salen de esta tanda:

- **Una puerta cerrada es estanca.** En las seis variantes, ninguna vivienda
  vecina recibe ni un gramo de humo; su sobrepresión es de 0,00–0,01 Pa aunque
  la caja esté a 11 Pa al otro lado. Una puerta real deja pasar humo por sus
  rendijas, y ese es justamente el mecanismo por el que una escalera cargada
  mata en las plantas altas con las puertas cerradas. **Con el modelo de hoy, el
  riesgo de las viviendas altas con puertas cerradas sale en cero**, y la
  reentrada medida el 2026-09-12 solo aparecía porque aquellas puertas estaban
  abiertas.
- **El tope de 900,0 °C aparece otra vez**, en Portal R de la variante B, con
  la caja cerrada. Las variantes D, E y F no lo tocan (780 / 374 / 345 °C). Ya
  no se puede atribuir solo al exutorio ni al ojo grande. Las temperaturas de
  las zonas del portal siguen sin ser de fiar; las masas de humo y las presiones
  se mueven de forma coherente entre variantes.

El humo llega antes al rellano de arriba que al de abajo (155 s frente a 172 s
en B). Es el llenado desde el techo: la capa se forma arriba y va bajando.

## Lo que aporta la línea visual

- ✅ **La herramienta de portal en el editor** (2026-09-12, tecla `O`). Crea una
  zona `escalera` llamada «Portal …» por cada planta que existe, encadenadas
  por un ojo de 1,4 m y cerradas por arriba. La puerta de entrada de cada
  vivienda que cae sobre el rellano pasa a dar a él sin moverse de sitio; la
  balconera no se toca. Abajo pone la puerta del zaguán a la calle, cerrada y en
  el lado libre. No abre huecos solo: al portal se entra por una puerta.
  Guardarraíl `tools/validate_portal.gd`, con 24 comprobaciones; once mutaciones
  lo tumban.
- ✅ **En la vista, el zaguán es puerta de calle** y la primera persona ya no
  planta delante un rellano de decorado, con escalera, ascensor y puertas de
  vecinos a la calle.
- ✅ **La vista del portal por dentro** (2026-09-12). Las fotos de
  `tools/capture_portal.gd` enseñaron tres fallos: la caja abierta al cielo, el
  portal a oscuras y, el peor, **la puerta del piso dando directamente contra los
  tramos**. La escalera ocupaba toda la zona, y en las plantas de arriba no había
  forjado delante de la puerta. `view/geometry/PortalGeometry.gd` reparte ahora
  cada zona en una **franja de rellano de 1,30 m** junto a las puertas y la
  escalera en el resto, subiendo en sentido contrario. El lado se decide por
  votación entre todas las plantas, para que los tramos casen con el hueco. La
  primera persona, la maqueta 3D y los huecos de forjado leen ese mismo reparto.
  La última zona lleva techo y cada rellano, su luz (grupo «Portal dibujado» del
  inspector), que se atenúa con el humo. El zaguán pasa a un lateral, centrado
  en el rellano: en la pared de enfrente quedaba detrás de los tramos, bajo la
  meseta. Guardarraíl `tools/validate_portal_view.gd`. Para el motor nada cambia:
  cada zona sigue siendo una sala entera con su ojo de 1,4 m.
- ✅ **El plano 2D del editor** (2026-09-13) dibuja las guías de escalera sobre la
  parte de los tramos y marca la franja de rellano. El hueco vertical, el que se
  pincha para seleccionarlo, y la pendiente del panel salen del mismo reparto.
  `PortalGeometry.split` es la regla pura, y `ScenarioWalls.portal_layout` la
  aplica sobre el diccionario del editor con el mismo voto de puertas.
  `validate_portal_view` comprueba que el plano y la vista dan el mismo hueco y
  la misma escalera. Al mirar la foto del plano salió un fallo que venía de la
  herramienta: **el portal se dibujaba girado −90°** encima de sí mismo, porque
  la subida y el `rotation_deg` salían del gesto de arrastre. Nace ahora sin
  giro, con la subida del reparto real, y no se deja girar: lo orientan las
  puertas de las viviendas.
- ✅ **Saber a qué da cada abertura** (`view/geometry/OpeningKinds.gd`,
  2026-09-12), que es lo que permite no pintar penacho donde no lo hay.
- ✅ **El rellano ya está construido en la vista** y su huella se calcula antes de
  levantar nada (`_collect_landing_footprints`).

## Restricción

**Un escenario sin portal no puede cambiar en nada.** Igual que con el viento y
con el patio: la suite de referencia tiene que dar los mismos números. Esto es
aditivo.
