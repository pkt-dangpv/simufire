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

- 🟠 **Una herramienta de portal en el editor**, como la del patio: dibujar el
  rellano y que cree las zonas de todas las plantas encadenadas, con la puerta de
  cada vivienda dando a la suya. **Es lo único que falta**: la física ya está
  medida y sale del motor tal cual.
- ✅ **Saber a qué da cada abertura** (`view/geometry/OpeningKinds.gd`,
  2026-09-12), que es lo que permite no pintar penacho donde no lo hay.
- ✅ **El rellano ya está construido en la vista** y su huella se calcula antes de
  levantar nada (`_collect_landing_footprints`).

## Restricción

**Un escenario sin portal no puede cambiar en nada.** Igual que con el viento y
con el patio: la suite de referencia tiene que dar los mismos números. Esto es
aditivo.
