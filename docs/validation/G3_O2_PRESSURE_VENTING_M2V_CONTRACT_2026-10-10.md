# G3 — Autoridad del oxígeno: M2-V, contrato previo del venteo por sobrepresión

**Fecha:** 2026-10-10 · **Línea:** G3 (CO/FED), motor · **Estado:** contrato
y predicciones, **escritos antes de programar y antes de ejecutar nada**.
Base `461fa9c0`. El resultado está en
[`G3_O2_PRESSURE_VENTING_M2V_2026-10-10.md`](G3_O2_PRESSURE_VENTING_M2V_2026-10-10.md).

Este documento no se corrige después: lo que una predicción falle se dice
en el informe.

## Qué hace hoy la ruta histórica

`GasExchangeSystem.step_pressure_venting`, por recinto y paso, cuando su
sobrepresión supera el umbral y hay camino al exterior:

| Variable | Qué es, por cómo se calcula | Qué es, por cómo se usa |
| --- | --- | --- |
| `q_out_m3s` | m³/s de gas caliente por las aberturas exteriores o sus fugas, ley de orificio | Caudal de salida |
| `raw_vented_air_kg` | `q_out · rho_hot · dt`: **kg de gas caliente** que salen en el paso | Solo diagnóstico |
| `smoke_out_kg` | El menor de esa masa de gas y el 15 % de `room.smoke_kg`, que es **masa de partículas de humo** | Se resta de `room.smoke_kg`: **partículas de humo** retiradas |
| `frac_out` | `smoke_out_kg / room.smoke_kg`, adimensional | Fracción de humo, de capa alta y de alivio de presión |
| `air_frac_out` | `q_out · dt / V`, acotado a 0,10: **fracción de volumen** purgada | CO, CO₂, HCN y el resto de gases. **No el oxígeno** |
| `air_in_kg` | `0,40 · smoke_out_kg` | **kg de aire exterior** que se mezclan con el recinto |
| `room_mass_kg` | `máx(1, V) · 1,2`: **kg de gas de referencia** del recinto | Denominador de la mezcla |

Y la escritura del oxígeno:

```
room.o2 = clamp((room.o2 · room_mass_kg + outside_o2 · air_in_kg) / (room_mass_kg + air_in_kg), 0, o2_nominal)
```

Tres hechos de esa ley, que no se cambian:

- **`smoke_out_kg` es una cantidad híbrida**: una masa de gas acotada por
  una masa de partículas, y usada después como partículas. No es la masa
  de gas que sale.
- **El oxígeno no sale con el volumen purgado.** A los demás gases se les
  aplica `air_frac_out`; al oxígeno, no. Lo único que le pasa es que
  `air_in_kg` de aire exterior se mezclan con todo el recinto.
- **El denominador crece** (`room_mass_kg + air_in_kg`) y el resultado se
  **recorta** a `o2_nominal`.

## Contrato

**La dilución del venteo es una operación del propietario del inventario,
con una entrada y una salida.** Con `a = air_in_kg`, `m` el gas de
referencia del recinto, `M` su inventario, `x_ext` la fracción molar
exterior y `k = M_O2 / M_aire`:

| | Cantidad | Fórmula |
| --- | --- | --- |
| Entra | O₂ que llevan `a` kg de gas de referencia a la fracción molar exterior | `E = x_ext · (a / M_aire) · M_O2` |
| Se mezcla | Con **todo** el recinto, como dice la ley histórica | fracción de la mezcla `x_m = (M + E) / ((m + a) / M_aire · M_O2)` |
| Sale | `a` kg de **esa mezcla**: el recinto conserva su contenido de referencia `m` | `S = x_m · (a / M_aire) · M_O2 = (M + E) · a / (m + a)` |
| Queda | | `M' = M + E − S = (M + E) · m / (m + a)` |

Comprobación de que es la misma ley: `M' / (m · k) = (x · m + x_ext · a) /
(m + a)`. Es exactamente la mezcla histórica antes de su recorte.

Respuestas a lo que había que determinar:

- **Qué entra y qué sale.** Entra `E`, sale `S`; el neto es
  `E − S = (x_ext − x) · k · a · m / (m + a)`. Se registran los tres.
- **Qué concentración tiene el gas saliente.** La de **la mezcla**, `x_m`,
  no la del recinto antes de mezclar ni la del gas caliente que la ley de
  orificio expulsa.
- **¿La masa entrante se usa directamente?** En la entrada, sí: `a` kg a
  la fracción exterior. En la salida **no** basta con «`a` kg a la
  concentración del recinto»: eso daría un neto `(x_ext − x) · k · a`,
  mayor en el factor `(m + a) / m`, y no sería la ley histórica. La forma
  equivalente con la concentración previa es un intercambio de
  `a · m / (m + a)` kg, no de `a`. El contrato usa la primera forma
  (mezcla y desplazamiento) porque es la que la ley escribe.
- **Qué no se usa.** `smoke_out_kg` no entra en el propietario como masa
  de gas saliente; `raw_vented_air_kg` tampoco. No se añade una salida de
  oxígeno por el volumen purgado, que la ley histórica no tiene: sería
  cambiar la ley. No se introduce una reposición igual a la purga.
- **Base.** Fracciones molares y la conversión canónica de M1
  (`o2_kg_in_reference_gas`). En la ley histórica las dos fracciones se
  multiplican por masas de la misma base y se dividen por su suma, así que
  el número resultante es el mismo leído como molar; lo que cambia es el
  acumulador en kg, que la ruta histórica escribe como `Δx · room_mass_kg`
  (9,5 % corto) y aquí es el neto de la operación.
- **Sin recorte.** No hay recorte a `o2_nominal` ni a nada. Con `x ≤
  x_ext` la mezcla nunca supera `x_ext`. Con `x > x_ext` (un recinto
  enriquecido) la dilución lo **baja** hacia `x_ext`; la ruta histórica lo
  cortaría de golpe a 0,209.
- **Una vez.** Un evento de venteo, una operación. Los totales del
  propietario y los acumuladores del recinto reciben el neto una vez.

**Lo que este contrato representa y lo que no.** Es una **dilución
equivalente** sobre el contenido de referencia del recinto, que M1 fija en
`V · 1,2 kg/m³`. **No es una conservación de la masa de gas**: el gas
caliente que la ley de orificio saca (`raw_vented_air_kg`) y el aire que
la ley hace entrar (`0,40 · smoke_out_kg`) no son la misma masa, y los
demás gases se purgan con otra fracción (`air_frac_out`). Esa
incoherencia entre especies es de la ley histórica y **no se corrige
aquí**.

**Diferencia declarada.** La ley histórica usa `máx(1, V)` para el gas del
recinto y el propietario `máx(0,1, V)`. Coinciden en cualquier recinto de
1 m³ o más. La operación usa el contenido de referencia del propietario.

**Conflicto.** Ninguno: la ley existente se transforma al inventario de
referencia sin cambiar el contrato de M1, el caudal ni el transporte.

## Dónde puede fallar, y qué queda escrito

La operación valida: propietario armado, recinto bajo autoridad, cantidad
finita y no negativa, fracción exterior entre 0 y 1. No puede dejar un
inventario negativo: lo que sale es una parte de lo que hay después de
mezclar.

- **Se valida antes de mutar.** Antes de que el venteo escriba humo,
  especies, capa alta o alivio de presión, se pregunta al propietario si
  la operación se aplicaría. Si no, se rechaza por su nombre y **ese
  evento de venteo no escribe nada**.
- **Lo que ya está escrito para entonces**, y no se describe como
  atómico: la relajación de la sobrepresión del recinto (es el modelo de
  presión, anterior a la decisión de ventear), el caudal de diagnóstico
  `mdot_vent_kg_s` y los diagnósticos de fase 3.
- **La operación se aplica donde la ley histórica escribe**, después de
  las demás escrituras del evento. Entre la validación y la aplicación no
  corre ninguna otra operación del propietario.
- **Sin vuelta a la ruta histórica.** Con el modo encendido, si el
  propietario no acepta, el número de sala no se escribe.

## Qué no cambia

Umbral, caudal, coeficientes y límites del venteo; generación,
eliminación y transporte de humo y de las demás especies; el fuego; el
coeficiente de 0,076 kg/MJ y el tope del 5 %; retardos y ley de
intercambio entre recintos. Red de presión, banco del Test016, PPV, HVAC,
hueco exterior caliente, parcelas y transporte del bucle de gases siguen
rechazados.

## Predicciones, antes de ejecutar

| | Predicción |
| --- | --- |
| P1 | Sobre `461fa9c0`, la fixture del venteo llega a su fin sin errores de script y falla: el primer evento de venteo con cantidad detiene la corrida por `pressure_venting` |
| P2 | Sin venteo no hay ninguna operación exterior con causa `pressure_venting` |
| P3 | Con el recinto a la concentración exterior, entrada y salida son positivas e iguales: neto cero dentro del redondeo |
| P4 | Con el recinto empobrecido el neto es positivo e igual a `(x_ext − x) · k · a · m / (m + a)` |
| P5 | Con el recinto enriquecido el neto es negativo, el recinto sigue por encima de 0,209 y nada se recorta |
| P6 | Una cantidad no finita o negativa, o una fracción exterior fuera de [0, 1], se rechaza por su nombre; el inventario no cambia y el evento no retira humo |
| P7 | Los tres balances de M1, con el venteo en su forma cerrada, cierran a 1 · 10⁻⁹ kg en cada paso |
| P8 | `o2_closed` y `o2_reopen_300` corren **enteros** con el modo encendido (10800 pasos): el libro por escritor de M2 dice que el venteo es la única ruta sin integrar que necesitan |
| P9 | **Hueco histórico.** Los −0,3778 kg de `o2_reopen_300` son la suma de lo que `_apply_room_o2_mass_delta` descarta al recortar al techo; lo demás (recorte al suelo, deltas bajo el umbral de 10⁻⁶ kg, destinos inexistentes) suma menos de 10⁻⁶ kg. **Precisión que hago antes de medir:** espero el descarte en el **crédito inmediato** a la sala caliente del intercambio —calculado con su lectura efectiva, que ya descuenta lo que debe, y aplicado a su número, que sigue en el techo— y no en las entregas diferidas |
| P10 | **Control causal.** Con el recorte al techo retirado solo de `_apply_room_o2_mass_delta`, en una copia diagnóstica: la suma de los acumuladores de transporte más la cola queda dentro de 10⁻⁶ kg de cero en toda la corrida. A dónde va ese oxígeno entonces (un número de sala sobre 0,209, u otro recorte) se mide; no lo predigo |
| P11 | **Enriquecimiento con el modo encendido.** Lo espero: la misma entrega que la ruta histórica descarta, el propietario la acredita. Predigo que se explica por el tránsito: el recinto supera 0,209 mientras su lectura efectiva —inventario más lo que viaja hacia él, que es negativo— no lo hace. Magnitud y duración, sin predicción |
| P12 | Con el interruptor apagado, los nueve casos de identidad siguen byte a byte y la referencia no cambia |

Mutantes, con el grupo que debe verlos, en
`scripts/simulation/run_g3_o2_venting_mutations.py`, declarados antes de
ejecutarlos.
