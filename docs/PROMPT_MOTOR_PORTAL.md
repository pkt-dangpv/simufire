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

## Lo que queda por medir

Lo del humo subiendo y lo de la caja presurizándose ya está arriba. Queda:

1. **Aditividad**: escenarios sin portal, mismos resultados que ahora. Es la
   condición de siempre y no se ha comprobado todavía.
2. **La vivienda deja de ventilar por ahí.** Con la puerta dando a un rellano
   cargado, la vivienda ya no tiene una salida a aire limpio infinito y el
   régimen de combustión debería notarlo. En la medición del 2026-09-12 la
   vivienda del fuego también tenía una ventana a la calle, así que ese efecto no
   quedó aislado.
3. **El portal de verdad tiene más de una vivienda por planta.** Se midió con
   una; con dos o tres puertas dando al mismo rellano, el reparto cambia.
4. **Cuánto importa el zaguán.** Se midió con su puerta a la calle CERRADA. Con
   ella abierta hay tiro de abajo arriba y el resultado puede ser otro.

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
- 🟠 **Queda la vista del portal por dentro**: en primera persona las zonas del
  portal apenas llevan pieza. Es el mismo paso que tuvo el patio después de su
  herramienta.
- ✅ **Saber a qué da cada abertura** (`view/geometry/OpeningKinds.gd`,
  2026-09-12), que es lo que permite no pintar penacho donde no lo hay.
- ✅ **El rellano ya está construido en la vista** y su huella se calcula antes de
  levantar nada (`_collect_landing_footprints`).

## Restricción

**Un escenario sin portal no puede cambiar en nada.** Igual que con el viento y
con el patio: la suite de referencia tiene que dar los mismos números. Esto es
aditivo.
