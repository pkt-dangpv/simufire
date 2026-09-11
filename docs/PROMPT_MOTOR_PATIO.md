# Prompt: patios interiores como conducto abierto al cielo

## Qué se pide, y por qué

El usuario quiere poder poner **patios interiores** en los escenarios: el patio
de luces del que están llenos los edificios españoles, al que dan las ventanas de
cocinas y baños, y que en un incendio se comporta como una chimenea.

Lo pidió así: *«patios interiores que producen salidas de humo y corrientes
convectivas hacia arriba sin que afecte aire por presión positiva hacia dentro de
la vivienda»*.

**Se le planteó que un patio real sí mete aire hacia las viviendas por debajo del
plano neutro** —es justamente el mecanismo por el que un patio propaga un
incendio a los vecinos de arriba— y **eligió la física completa**, con la
condición de que el patio esté siempre abierto por arriba. Que es lo razonable:
sin techo que le oponga resistencia el patio apenas se presuriza por encima de la
ambiente, así que el efecto que él quería evitar sale casi solo de la física, sin
tener que imponerlo a mano.

**No hay que imponer unidireccionalidad.** Si el modelo dice que por la planta
baja entra aire al patio y por la sexta sale humo hacia la vivienda, eso es lo
que tiene que pasar.

## Confirmado por el usuario el 2026-09-11, y los dos matices que faltaban

Lo describió así: *«es un tipo de chimenea sobre todo pero, si falta aire, cogerá
de ahí. pero no tendrá presión positiva como en una ventana a la calle»*. Las tres
partes son correctas y coinciden con lo que ya estaba encargado. Conviene dejar
escritos dos matices, porque cambian **qué hay que medir**.

**1. «Sin presión positiva» es cierto, y el motivo importa.** Una ventana a la
calle ve un depósito infinito con ΔP de viento: barlovento positivo, sotavento
negativo (coeficientes tipo Eurocode, que el motor ya aplica por `wall_side`). Un
patio está **abrigado**: el viento no entra, el Cp es ≈ 0 y, sobre la boca
horizontal, ligeramente negativo —succión suave, que *ayuda* al tiro—. El motor
ya hace lo correcto sin tocar nada: `_compute_wind_dp_pa` devuelve 0,0 cuando la
abertura no tiene `wall_side`, así que basta con **no darle `wall_side` a las
aperturas que dan al patio**. Verificado en `sim/core/GasExchangeSystem.gd`.

**2. «Si falta aire, cogerá de ahí» es cierto, pero lo que coge no es aire.** Este
es el matiz que decide si el modelo sirve. El patio es un depósito **finito** cuyo
único aporte entra por arriba, contracorriente del penacho que sube; en un conducto
con una sola boca ese contraflujo es de baja capacidad. Consecuencias, y las tres
son medibles:

- **El patio se llena de humo** y su propia columna caliente **se opone** a que
  siga saliendo: según el conducto se calienta, el ΔP que empuja hacia fuera de la
  sala del fuego baja. Un patio saturado deja de ventilar.
- El aire de reposición que una vivienda toma del patio por debajo del plano
  neutro viene **caliente y empobrecido en oxígeno**, no fresco a 20 °C. Es decir:
  **el patio no rescata a un fuego infraventilado; puede empeorarlo.**
- Y el peligro real del patio de luces no es la sala del fuego, es **la
  reentrada**: cuando la capa de humo del conducto desciende por debajo de una
  ventana de una planta alta, el humo entra en esa vivienda. Ese es el mecanismo
  por el que un patio propaga un incendio a los vecinos, y es lo que el modelo
  tiene que reproducir.

**Por eso no vale la chimenea de un solo sentido**, y por eso la decisión tomada
—física completa— es la correcta: un venteo unidireccional siempre saca humo y
nunca mete nada, así que no puede saturarse, no puede envenenar el aire de
reposición y no puede meter humo en el sexto. Perdería justo los tres efectos que
hacen interesante un patio.

**Una comprobación más, que se añade a las cinco de abajo:** con fuego en una
planta baja y la ventana al patio abierta, la **fracción de oxígeno de la zona-patio
tiene que bajar con el tiempo**, y el aire que entra a las viviendas altas tiene
que traer esa composición. Si el patio se mantiene a 0,209 de O2 pase lo que pase,
está modelado como «exterior» y no como zona, que es el atajo que hay que evitar.

## Qué hay ya, y es bastante

Casi todas las piezas existen:

- **Aperturas verticales.** `op.is_vertical` (líneas ~3054, ~3479): el
  intercambio va por flotabilidad y no por difusión de fondo, con el comentario
  SF-R7 explicándolo. Es lo que usan hoy los huecos de escalera.
- **Efecto chimenea.** Ya implementado sobre `room.floor_level_z_m` (línea ~1494):
  `ΔP_stack = ρ_ext · g · floor_level_z_m · (1 − T_ext / T_upper)`, con referencia
  al SFPE Handbook 5.ª ed. §9.1.
- **Aperturas al exterior** con su ΔP de viento por orientación de fachada.
- **Altura vertical entre salas** ya se deduce (`_H_z_ve`, línea ~3063).

Lo que no existe es la **zona-patio**: un recinto vertical que atraviesa las
plantas y cuyo extremo superior es aire exterior.

## Qué hacer

### 1. El patio es un recinto por planta, encadenado

La forma que menos inventa: el patio se representa como **una zona por planta**
—igual que una sala, con su superficie en planta y su altura— y las zonas
consecutivas se unen con **aperturas verticales de la superficie completa del
patio**. Es exactamente el patrón que ya funciona en el hueco de escalera, pero
sin resistencia entre plantas: el hueco es todo el patio.

Ventaja de hacerlo así y no como una zona única alta: se reaprovecha el modelo de
zonas, el reparto por capas y el efecto chimenea tal y como están, y el perfil
vertical de temperatura y humo sale solo.

### 2. Por arriba, ambiente

La zona del patio de la última planta lleva una **apertura al exterior,
horizontal, permanentemente abierta, con el área en planta del patio**. Es la
boca del patio.

Es lo que hace que el patio no se presurice: cualquier sobrepresión se descarga
al cielo con una resistencia mínima. Conviene comprobar que el modelo de
apertura exterior admite una boca horizontal —si el ΔP de viento asume una
fachada vertical con `wall_side`, la boca del patio no tiene `wall_side` y el
código actual devuelve 0,0 para ese caso, que como primera aproximación es
correcto: sobre una boca horizontal el viento produce succión, no presión
frontal—.

Si se quiere afinar más adelante: sobre una abertura horizontal a barlovento el
Cp es negativo y pequeño (succión suave), lo que **ayuda** al tiro. No es
necesario para esta entrega.

### 3. Las viviendas dan al patio por ventanas normales

Nada nuevo: aperturas entre la sala y la zona-patio de su misma planta, con su
área, su alféizar y su fracción de apertura. Que sean ventanas de cocina y baño
es cosa del escenario, no del motor.

**El punto que hay que cuidar** es que estas aperturas son *interiores* entre dos
zonas del modelo, no aperturas al exterior: el aire que entra a una vivienda
desde el patio viene con la composición del patio —posiblemente humo de la
vivienda de abajo—, no con aire fresco a 20 °C. Ese es todo el interés del
asunto y es donde un atajo lo arruinaría.

### 4. Lo que aporta la línea visual

- Geometría del patio en el editor (un rectángulo que atraviesa plantas, muy
  parecido al hueco vertical de escalera que ya se dibuja).
- El patio como espacio real en primera persona y en la maqueta, con el penacho
  saliendo por la boca.
- El dato de cuántas plantas tiene el edificio (tarea N-4), que fija la altura
  del conducto.

## Restricciones

- **Un escenario sin patio no puede cambiar en nada.** Igual que con el viento:
  la suite de referencia tiene que dar los mismos números. El patio es aditivo.
- **No imponer sentido único al flujo.** Ya está decidido: física completa.
- No confundir el patio con el hueco de escalera: la escalera es un recinto
  cerrado con puertas en cada rellano, el patio está abierto al cielo y las
  viviendas dan a él por ventanas. Comparten mecanismo (flotabilidad en vertical)
  y no comparten condiciones de contorno.

## Cómo comprobarlo

1. **Aditividad**: escenarios sin patio, mismos resultados antes y después.
2. **El plano neutro existe y se puede señalar.** En un edificio de, digamos, ocho
   plantas con fuego en la segunda, tiene que poder volcarse el sentido del flujo
   vivienda↔patio planta a planta y verse el cambio de signo a una altura. Esa
   tabla es el mejor guardarraíl posible de esta entrega, y además es la prueba
   de que el modelo hace lo que el usuario temía y aceptó.
3. **El humo sube.** Fuego en una planta baja, ventana al patio abierta: las
   plantas altas tienen que ver llegar productos de combustión por el patio, con
   retardo creciente con la altura.
4. **No se presuriza.** La sobrepresión de la zona-patio respecto a la ambiente
   debe mantenerse pequeña mientras la boca esté abierta. Si aparece
   sobrepresión relevante con la boca abierta, algo está mal en el área o en la
   resistencia de la boca.
5. **Tapar la boca lo cambia todo.** Como comprobación de que el modelo es
   sensible a lo que debe: cerrando la boca del patio, la sobrepresión y el
   reparto tienen que cambiar de forma clara. Sirve además para el día que se
   quiera modelar un patio cubierto.
