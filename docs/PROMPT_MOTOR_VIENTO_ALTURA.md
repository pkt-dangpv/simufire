# Prompt: el viento no crece con la altura

## Qué hay hoy, y funciona

El modelo de viento está implementado y es correcto en lo que hace.
`GasExchangeSystem._compute_wind_dp_pa(op, building)` calcula, apertura por
apertura:

```gdscript
var v: float = building.wind_speed_m_s
...
if cos_inc >= 0.0:
    cp = 0.6 * cos_inc   # barlovento
else:
    cp = 0.4 * cos_inc   # sotavento (Cp negativo → succión)
return 0.5 * 1.2 * v * v * cp
```

con la normal exterior sacada de `op.wall_side` y la convención meteorológica
(`wind_direction_deg` = ángulo desde donde VIENE el viento). Referencia citada en
el propio fichero: EN 1991-1-4 §7.2.

Está dormido: hasta ahora ninguna interfaz exponía `wind_speed_m_s` y ningún
escenario del catálogo lo pone, así que en la práctica siempre ha valido 0. La
línea visual va a sacarlo al editor y al selector de escenarios (tarea N-5), y en
cuanto haya un mando la gente lo va a usar.

## El problema

**`v` es la misma para todas las aperturas del edificio, estén en la planta baja
o en la vigésima.** El viento real no se comporta así: crece con la altura sobre
el terreno, y en ciudad crece deprisa.

Esto importa aquí más que en otros simuladores por dos razones:

1. El usuario ha pedido expresamente que **se note la planta en la que estás**, y
   esta es la mitad física de esa sensación (la otra mitad es la vista, y es
   nuestra).
2. Los ensayos de NIST y FDNY en Governors Island midieron que con un viento
   impuesto de **9 a 11 m/s** y un recorrido de flujo por la planta del incendio
   aparecían más de 400 °C y 10 m/s en el pasillo y la escalera por encima del
   fuego. Es decir: la diferencia entre 8 m/s en la calle y 13 m/s en la planta
   15 es exactamente la diferencia entre un incendio incómodo y uno no
   soportable. No es un matiz estético.

## Qué hacer

### 1. La velocidad de entrada se define a 10 m

`building.wind_speed_m_s` pasa a significar, explícitamente, **la velocidad a la
altura de referencia de 10 m sobre el terreno**. Es la convención de la escala
Beaufort, de los avisos meteorológicos y del CTE DB-SE-AE (que define su
velocidad básica como la media de 10 minutos a 10 m en terreno tipo II). Sin esa
definición el número del mando no significa nada.

Conviene documentarlo en el propio `BuildingModel`, junto a la declaración.

### 2. Perfil de potencia por altura

En `_compute_wind_dp_pa`, sustituir `v` por la velocidad a la altura de la
apertura:

```
v(z) = v_10 · (z / 10)^α
```

- **α (exponente de rugosidad)**: 0,28 por defecto, que es el centro del rango
  urbano habitual (0,22 en periferia, 0,25 en ciudad típica, 0,33 en núcleo
  denso). Que sea un ajuste con nombre, no un número suelto: lo lógico es que
  acabe atado al entorno del escenario cuando exista esa noción.
- **Suelo**: `z` no puede tender a 0 o la potencia se dispara hacia abajo de
  forma poco física. Recortar con `z_efectiva = max(z, 2.0)`, que a 2 m da
  v ≈ 0,64·v₁₀ — razonable para una apertura a ras de calle.
- **Techo**: ninguno. Si alguien declara una planta 40, que sople lo que le toca.

### 3. De dónde sale `z`

`z` es la altura del **centro de la apertura sobre el terreno**:

```
z = base_del_edificio_sobre_terreno + room.floor_level_z_m + alféizar + op.height_m / 2
```

- `room.floor_level_z_m` ya existe y lo usa el efecto chimenea (línea ~1494), así
  que la mitad del camino está hecha.
- El alféizar: si `OpeningModel` no lo lleva hoy, empezar sin él —
  `room.floor_level_z_m + op.height_m/2` es una aproximación perfectamente buena
  para esto—. La diferencia entre una ventana y una puerta es de decímetros; la
  que importa es la de plantas.
- **`base_del_edificio_sobre_terreno` es un dato nuevo que aporta la línea
  visual** (tarea N-4): la planta en la que está la vivienda dentro de un
  edificio que puede tener muchas más de las dibujadas. Hasta que llegue, vale
  0,0 y el comportamiento es el de hoy más el perfil dentro del propio escenario.
  Dejadlo como campo del `BuildingModel` con ese valor por defecto y nosotros lo
  rellenamos.

## Restricciones

- **Con `wind_speed_m_s = 0` no puede cambiar absolutamente nada.** Hoy todos los
  escenarios del catálogo y todos los casos de validación tienen viento 0, así
  que el cambio debe ser un no-op medido para ellos: la suite de referencia tiene
  que dar exactamente los mismos números. Si algo se mueve con viento 0, es un
  fallo del cambio, no una mejora.
- Mantener `wind_effect_enabled` como está: es el interruptor que permite aislar
  el término.
- No tocar los Cp. El reparto barlovento/sotavento no está en discusión aquí.

## Cómo comprobarlo

1. **No-op con viento 0**: la suite de validación completa, antes y después, byte
   a byte donde sea posible.
2. **Monotonía**: mismo escenario, misma apertura, subiendo `floor_level_z_m` →
   `|ΔP_viento|` estrictamente creciente.
3. **Un valor de contraste**: con v₁₀ = 10 m/s y α = 0,28, una apertura a 45 m
   (planta 15, ~3 m por planta) debe dar v ≈ 15 m/s. Como ΔP va con v², la
   presión en esa planta es unas **2,3 veces** la de la calle. Ese factor es el
   que hace visible la petición del usuario, y es un buen aserto de guardarraíl.
4. **Recorte del suelo**: una apertura a 0,5 m no puede dar una velocidad mayor
   que otra a 3 m.
