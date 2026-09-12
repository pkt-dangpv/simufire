# Prompt: el portal y la caja de escalera como recinto de verdad

## Qué se pide, y por qué

El usuario lo dijo así el 2026-09-12, hablando del penacho de humo:

> *«quita el penacho de la puerta de entrada. ahi el humo debe primero chocar
> contra el techo y luego hacer efecto chimenea por la escalera»*

Es correcto y es exactamente lo que hoy **no puede pasar**. No por la vista: por
el modelo.

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

## Qué hay que medir antes de darlo por bueno

1. **Aditividad**: escenarios sin portal, mismos resultados que ahora.
2. **El humo llega al rellano y se queda bajo su techo.** Fuego en la vivienda,
   puerta abierta: la capa del rellano tiene que engordar, no desaparecer.
3. **Y sube.** Los rellanos de plantas altas ven llegar productos con retardo
   creciente, como pasó en el patio (48 / 62 / 71 s en tres plantas).
4. **La caja cerrada se presuriza y la ventilada no.** Es la comprobación que
   distingue este encargo del patio; si las dos dan lo mismo, el remate no está
   ofreciendo resistencia.
5. **La vivienda deja de ventilar por ahí.** Con la puerta dando a un rellano
   cargado, la vivienda ya no tiene una salida a aire limpio infinito: el régimen
   de combustión tiene que notarlo.

## Lo que aporta la línea visual

- 🟠 **Una herramienta de portal en el editor**, como la del patio: dibujar el
  rellano y que cree las zonas de todas las plantas encadenadas, con la puerta de
  cada vivienda dando a la suya.
- ✅ **Saber a qué da cada abertura** (`view/geometry/OpeningKinds.gd`,
  2026-09-12), que es lo que permite no pintar penacho donde no lo hay.
- ✅ **El rellano ya está construido en la vista** y su huella se calcula antes de
  levantar nada (`_collect_landing_footprints`).

## Restricción

**No hace falta esperar al motor para saber si esto funciona.** Con el patio se
montó a mano un escenario de tres plantas y se midió: el motor ya lo hacía. Aquí
toca la misma comprobación antes de escribir ninguna herramienta, y **está por
hacer**: hasta que se mida, que el portal salga sin tocar el motor es una
conjetura razonable por analogía, no un resultado.
