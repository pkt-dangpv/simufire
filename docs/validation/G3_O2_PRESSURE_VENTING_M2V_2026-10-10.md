# G3 — Autoridad del oxígeno: M2-V, el venteo por sobrepresión como operación del propietario

**Fecha:** 2026-10-10 · **Línea:** G3 (CO/FED), motor · **Estado:**
implementado tras el mismo interruptor apagado de M1 y M2; **no activado**.

**Alcance.** Integrar la ruta `pressure_venting`, que cortaba los dos casos
de casa de [M2](G3_O2_SELECTION_M2_2026-10-10.md), como operación del
propietario del inventario de oxígeno; correr esos casos enteros; y aislar
la causa del hueco histórico de −0,378 kg. Sin cambiar la ley de caudal del
venteo. Nada de M3 ni de M4, sin emisiones nuevas y sin producto.
**CO y FED siguen OFF/NO-GO.**

Contrato y predicciones, escritos antes de programar:
[`G3_O2_PRESSURE_VENTING_M2V_CONTRACT_2026-10-10.md`](G3_O2_PRESSURE_VENTING_M2V_CONTRACT_2026-10-10.md).
Registro: [`G3_O2_PRESSURE_VENTING_M2V_2026-10-10.json`](G3_O2_PRESSURE_VENTING_M2V_2026-10-10.json).

**Un balance que cierra no demuestra que la distribución del gas sea
realista.** Este informe separa las dos cosas y la segunda no la afirma.

## Decisión

| | Estado |
| --- | --- |
| **Integración técnica** | **Cerrada.** El venteo actualiza `M` solo por su propietario, con entrada, salida y neto anotados; sin recorte y sin vuelta a la ruta histórica |
| **Conservación contable** | **Cierra.** 1,1 · 10⁻¹⁴ kg en el peor paso de la fixture y 2,1 · 10⁻¹⁴ kg en el de las casas, con el criterio de 1 · 10⁻⁹ kg sin relajar |
| **Casos de casa** | **Completos.** `o2_closed` y `o2_reopen_300` corren los 10800 pasos con el modo encendido, sin ningún rechazo. C1 y C2 se cumplen sobre esas trazas |
| **Control causal** | **Demostrado.** El hueco histórico es, kilogramo a kilogramo, lo que una escritura recorta al techo; quitando ese recorte en una copia diagnóstica el hueco desaparece |
| **Límites físicos** | **Abiertos, tres.** La dilución es equivalente, no una conservación de la masa de gas; el oxígeno y los demás gases se purgan con fracciones distintas; y con el modo encendido el Pasillo es más rico que el aire exterior durante 22 s. Ninguno se corrige aquí |
| **Para empezar M3** | **GO, acotado**, y **NO-GO** para lo que lea el número de sala de un recinto que no arde como concentración física. Ver «Decisión sobre M3» |
| Activación | **NO-GO** |

- **Con el interruptor apagado el motor es el de antes.** Ver
  «Verificación».
- **El venteo no era lo único.** Lo era para correr las casas. Al
  correrlas enteras aparece lo que M2 dejó anotado como riesgo: el
  transporte histórico acredita oxígeno a una sala que ya está a la
  concentración del aire. La ruta histórica lo tira; el propietario lo
  conserva. Es el mismo defecto visto desde los dos lados.
- **O2-3 sigue abierto.** El tope del 5 % no actuó en ninguna de las dos
  casas; eso no lo cierra.

## Contrato del venteo y conversiones

El contrato completo, con lo que representa cada variable de la ley
histórica, está en el documento previo. En resumen, con `a = air_in_kg`,
`m` el gas de referencia del recinto, `M` su inventario, `x_ext` la
fracción molar exterior y `k = M_O2 / M_aire`:

| | Fórmula |
| --- | --- |
| Entra | `E = x_ext · (a / M_aire) · M_O2` |
| Fracción de la mezcla | `x_m = (M + E) / ((m + a) / M_aire · M_O2)` |
| Sale, `a` kg de esa mezcla | `S = x_m · (a / M_aire) · M_O2` |
| Queda | `M' = M + E − S = (M + E) · m / (m + a)` |

- **Es la misma ley.** `M' / (m · k) = (x · m + x_ext · a) / (m + a)`: la
  mezcla histórica, sin su recorte.
- **El gas sale a la fracción de la mezcla**, no a la del recinto antes de
  mezclar. Usar la masa entrante directamente a la concentración previa
  daría un neto mayor en el factor `(m + a) / m`; el mutante W13 es eso y
  muere.
- **`smoke_out_kg` no entra en el propietario** como masa de gas saliente,
  ni la masa de gas caliente que saca la ley de orificio. No se añade una
  salida de oxígeno por el volumen purgado, que la ley histórica no tiene.
- **Es una dilución equivalente** sobre el contenido de referencia del
  recinto. **No es una conservación de la masa de gas.**
- **Fracción molar, sin recorte.** La conversión es la canónica de M1.

## Qué se implementó

| Archivo | Efecto concreto |
| --- | --- |
| [`sim/core/RoomOxygenInventory.gd`](../../sim/core/RoomOxygenInventory.gd) | Operación nueva `dilute_with_outside`: valida, calcula entrada, mezcla y salida con las conversiones de M1 y escribe `M` una vez. Consulta de solo lectura `outside_dilution_would_apply`. Totales de la dilución por recinto (eventos, gas, entrada, salida), dentro del intercambio exterior. `pressure_venting` pasa a las rutas soportadas |
| [`sim/core/GasExchangeSystem.gd`](../../sim/core/GasExchangeSystem.gd) | En `step_pressure_venting`, con el modo encendido: pregunta al propietario antes de escribir nada del evento; aplica la dilución donde la ley histórica escribía el número; el acumulador exterior del recinto recibe el neto que aplicó el propietario. Desaparece el rechazo de la ruta. La expresión del aire entrante sube unas líneas, sin cambiar |
| [`tools/run_scenario_headless.gd`](../../tools/run_scenario_headless.gd) | La traza pasiva añade el tránsito por recinto receptor y, si una copia diagnóstica del sistema de oxígeno los declara, sus contadores. No es `sim/` |

**No se ha tocado** `CombustionSystem.gd`, `OxygenExchangeSystem.gd`,
`SimulationEngine.gd`, `RoomModel.gd` ni `PrescribedObjectHrrSource.gd`.
No hay interruptor nuevo: es `o2_room_inventory_enabled`, sin `@export` y
apagado.

**No cambia:** umbral, caudal, coeficientes y límites del venteo; humo y
demás especies; el fuego; el coeficiente de 0,076 kg/MJ y el tope del
5 %; retardos y ley de intercambio entre recintos.

### Dónde puede fallar y qué queda escrito

- La operación valida propietario armado, recinto bajo autoridad,
  cantidad finita y no negativa y fracción exterior entre 0 y 1. No puede
  dejar un inventario negativo: lo que sale es parte de lo que hay tras
  mezclar. «Cantidad insuficiente» no existe en una dilución.
- **Se pregunta antes de mutar.** Un evento que el propietario no
  aceptaría se rechaza por su nombre y **no escribe** humo, especies, capa
  alta ni alivio de presión.
- **No es atómico respecto a todo.** Para entonces ya están escritos la
  relajación de la sobrepresión del recinto, que es el modelo de presión y
  es anterior a la decisión de ventear, el caudal de diagnóstico
  `mdot_vent_kg_s` y los contadores de diagnóstico de fase 3. La fixture
  lo comprueba así, no como «nada cambió».

## Predicciones y resultado

| | Predicción | Resultado |
| --- | --- | --- |
| P1 | Sobre `461fa9c0` la fixture falla sin errores de script | **Cumplida.** 41 fallos de 102, 0 errores de script |
| P2 | Sin venteo no hay operación de venteo | **Cumplida** |
| P3 | A la concentración exterior, entrada y salida se cancelan | **Cumplida.** Neto −6,5 · 10⁻¹⁹ kg en tres eventos |
| P4 | Empobrecido: neto positivo, la forma cerrada | **Cumplida.** +7,0 · 10⁻⁴ kg |
| P5 | Enriquecido: neto negativo y nada se recorta | **Cumplida.** −2,5 · 10⁻⁴ kg; el recinto baja de 0,23 a 0,229996 y no a 0,209 |
| P6 | Cantidad o fracción no válida: rechazo sin débito, y el evento no retira humo | **Cumplida** |
| P7 | Los tres balances cierran a 1 · 10⁻⁹ kg | **Cumplida.** Peor 2,1 · 10⁻¹⁴ kg |
| P8 | Las dos casas corren enteras | **Cumplida.** 10800 pasos cada una |
| P9 | El hueco es el recorte al techo, en el crédito inmediato a la sala caliente | **Cumplida, las dos partes.** 0,3778 kg; por las entregas diferidas, nada |
| P10 | Sin ese recorte, acumuladores más cola dentro de 10⁻⁶ kg de cero | **Cumplida.** Peor 1,1 · 10⁻¹¹ kg |
| P11 | Con el modo encendido hay enriquecimiento y lo explica el tránsito | **Cumplida.** Hasta +0,0112; la lectura efectiva no supera el aire en ningún paso |
| P12 | Con el interruptor apagado, identidad y referencia intactas | Ver «Verificación» |

Ninguna predicción falló. La que venía afinada antes de medir, P9, corrige
lo que dejó escrito M2: el recorte no está en las entregas diferidas.

## Antes y después

La fixture de M2-V, sobre los archivos del motor de `461fa9c0` puestos byte
a byte y restaurados después: 102 comprobaciones,
**41 fallos**, 0 errores de script. En el recinto
que ventea la corrida se detiene en el paso
283 de 720, con
0 operaciones de venteo. El grupo que pide que sin venteo no
haya operación pasa también antes: eso no ha cambiado.

## Aceptación

126 comprobaciones en 10 grupos, todas cumplidas, sobre el motor
real. Recinto de 48 m³ con una ventana cerrada y un sofá de 700 kW; el
venteo sale por la fuga del marco, como en la casa.

| | Un recinto que ventea | Dos recintos, 0,25 s | Dos recintos, 0,125 s |
| --- | --- | --- | --- |
| Pasos | 720 | 600 | 1200 |
| Eventos de venteo, una operación cada uno | 385 | 242 | 488 |
| Gas que entra | 0,1780 kg | 0,1120 kg | 0,1131 kg |
| O₂ que entra | 0,0411 kg | 0,0259 kg | 0,0261 kg |
| O₂ que sale | 0,0353 kg | 0,0233 kg | 0,0233 kg |
| Neto | +0,0058 kg | +0,0026 kg | +0,0028 kg |
| Peor evento contra su forma cerrada | 1,8 · 10⁻¹⁵ kg | 1,8 · 10⁻¹⁵ kg | 1,8 · 10⁻¹⁵ kg |
| Gas del evento contra 0,40 del humo retirado | 1,1 · 10⁻¹⁷ kg | 1,0 · 10⁻¹⁷ kg | 1,1 · 10⁻¹⁷ kg |
| Mayor tránsito | — | 0,2195 kg | 0,1169 kg |
| Peor residuo por operaciones | 2,9 · 10⁻¹⁵ kg | 4,5 · 10⁻¹⁵ kg | 4,9 · 10⁻¹⁵ kg |
| Peor residuo del edificio con tránsito | 2,9 · 10⁻¹⁵ kg | 9,0 · 10⁻¹⁵ kg | 1,1 · 10⁻¹⁴ kg |
| Peor residuo contra las formas cerradas | 2,9 · 10⁻¹⁵ kg | 9,0 · 10⁻¹⁵ kg | 1,1 · 10⁻¹⁴ kg |

- **El oráculo no llama al propietario.** El gas de cada evento sale del
  humo que el venteo retiró, leído del contador pasivo que la ley ya
  lleva, y no de la operación; entrada, salida y resto son la forma
  cerrada escrita en la fixture.
- **Alcance del tercer balance.** En el recinto sin vecinos el contenido
  que encuentra el venteo se reconstruye con las formas cerradas del paso
  de oxígeno. Con vecino, el intercambio interior del mismo paso lo ha
  movido antes, y ese contenido se toma del registro del evento: ahí el
  oráculo comprueba la aritmética de la dilución, no el paso entero.
- **Signo.** Tres eventos con el recinto a 0,209, a 0,15 y a 0,23: neto
  cero, positivo y negativo. El de 0,23 sigue por encima de 0,209 después.
- **Una vez.** Nunca dos operaciones de venteo de un recinto en un paso;
  los totales del propietario y el acumulador exterior del recinto dicen
  lo que dijeron las operaciones.
- **La selección de M2 no se toca.** En cada paso guarda lo que el recinto
  tenía al abrirlo, se sirve al fuego y al sumidero y a nadie más, y sus
  identificadores son consecutivos: nadie construye una a mitad de paso.
- **Rechazo entero.** Cantidad que no es un número, negativa, infinita,
  un texto, ninguna; fracción exterior fuera de [0, 1]; recinto de otro
  propietario. Ninguna debita nada. Y la ley del venteo, cuando el
  propietario no puede anotar su evento, no retira humo ni gases ni alivia
  presión, tampoco en el evento siguiente con el propietario ya detenido.
- **Ciclo de vida.** Tras un reinicio no queda venteo de la corrida
  anterior y la misma corrida da la misma huella. Revocado el modo, o sin
  propietario, el venteo es el histórico y escribe el número de sala.

### Efecto en un recinto que ventea, medido y no validado

300 s, el mismo recinto con el modo apagado y encendido.

| | Apagado | Encendido |
| --- | --- | --- |
| Pico de potencia (kW) | 603,0 | 618,2 |
| Energía acumulada (MJ) | 67,11 | 72,86 |
| Menor número de sala | 0,1272 | 0,1242 |
| Humo venteado (kg) | 1,180 | 1,264 |
| Acumulador exterior del recinto (kg) | 0,1313 | 0,1500 |
| Recortado por el tope (kg) | — | 0,000 |

Los dos acumuladores exteriores no están en la misma unidad: el histórico
es un cambio de fracción por una masa de gas, y el del modo encendido son
kilogramos de O₂. No se comparan.

## Casos de casa: completos, con el modo encendido

`o2_closed` y `o2_reopen_300`, con sus escenarios y eventos de siempre. No
se ha desactivado el venteo, no se ha subido su umbral, no se ha quitado
ninguna fuga y no se ha corrido una casa más simple en su lugar.

| | `o2_closed` | `o2_reopen_300` |
| --- | --- | --- |
| Pasos ejecutados, de 10800 | **10800** | **10800** |
| Último instante | 900,0 s | 900,0 s |
| Rechazos | Ninguno | Ninguno |
| Peor residuo por operaciones, de cualquier recinto y paso | 3,3 · 10⁻¹⁵ kg | 5,0 · 10⁻¹⁵ kg |
| Peor residuo del edificio con el tránsito | 1,6 · 10⁻¹⁴ kg | 2,1 · 10⁻¹⁴ kg |
| Peor residuo contra las formas cerradas | 1,6 · 10⁻¹⁴ kg | 2,1 · 10⁻¹⁴ kg |
| Residuo acumulado de la casa en los 900 s, con el tránsito | −1,7 · 10⁻¹² kg | 9,1 · 10⁻¹³ kg |
| Oxígeno de la casa: inicio → final | 46,547 → 40,595 kg | 46,547 → 37,837 kg |
| Consumo (débito del sumidero) | 6,647 kg | 9,563 kg |
| Recortado por el tope del 5 % | 0,000 kg | 0,000 kg |
| Infiltración, neto | +0,632 kg | +0,796 kg |
| Venteo: eventos | 3678 | 4406 |
| Venteo: entre | 74,4 y 388,2 s | 74,4 y 476,3 s |
| Venteo: gas que entra | 0,744 kg | 0,791 kg |
| Venteo: O₂ que entra | 0,1717 kg | 0,1827 kg |
| Venteo: O₂ que sale | 0,1087 kg | 0,1257 kg |
| Venteo: neto | +0,0630 kg | +0,0570 kg |
| Peor evento contra su forma cerrada | 1,8 · 10⁻¹⁵ kg | 1,8 · 10⁻¹⁵ kg |
| Mayor tránsito | 0,000 kg, 0 entradas | 2,253 kg, 1146 entradas |
| Tránsito al final | 0,000 kg | 0,000 kg |
| Recintos y pasos en que el fuego leyó su selección | 64800 de 64800 | 64800 de 64800 |
| Débitos sobre esa selección | 5030 de 5030 | 10702 de 10702 |
| Débitos por encima de lo disponible | 0 | 0 |
| C1 (inventario = inicio − débito + transporte + exterior) | **Cumple**; peor residuo 3,2 · 10⁻⁹ kg | **Cumple**; peor residuo −8,2 · 10⁻⁹ kg |
| C2 (débito = 0,076 kg/MJ del calor, declarado una vez) | **Cumple**; diferencia 0 kg | **Cumple**; diferencia 8,0 · 10⁻¹⁰ kg |

La traza escribe una fila por paso con el inventario de cada recinto, el
tránsito con signo y sus entregas pendientes, las operaciones con su
entrada y su salida, la concentración derivada y la selección usada. La
evaluación deja además, junto a cada corrida, `o2_budget_by_step.csv` con
los tres residuos, el tránsito, el consumo, lo recortado, la infiltración,
el venteo, la potencia y la energía de cada paso.

### Balance por recinto, `o2_reopen_300`

kg de O₂. Residuo = final − (inicio − débito + exterior + transporte).

| Recinto | m³ | Inicio | Débito | Exterior | Transporte | Final | Fracción final | Residuo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Salón (arde) | 48,0 | 13,299 | 9,563 | 0,481 | 5,811 | 10,028 | 0,1576 | 4,5 · 10⁻¹² |
| Pasillo | 25,2 | 6,982 | 0,000 | 0,108 | −1,585 | 5,505 | 0,1648 | −3,0 · 10⁻¹² |
| Dormitorio 1 | 25,2 | 6,982 | 0,000 | 0,071 | −1,128 | 5,925 | 0,1774 | −3,2 · 10⁻¹² |
| Dormitorio 2 | 16,8 | 4,655 | 0,000 | 0,053 | −0,841 | 3,866 | 0,1736 | −2,0 · 10⁻¹⁴ |
| Cocina | 36,0 | 9,974 | 0,000 | 0,090 | −1,445 | 8,620 | 0,1806 | 2,7 · 10⁻¹² |
| Baño | 16,8 | 4,655 | 0,000 | 0,051 | −0,812 | 3,894 | 0,1748 | −2,8 · 10⁻¹⁴ |

### Balance por recinto, `o2_closed`

| Recinto | m³ | Inicio | Débito | Exterior | Transporte | Final | Fracción final | Residuo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Salón (arde) | 48,0 | 13,299 | 6,647 | 0,695 | 0,000 | 7,347 | 0,1155 | −1,7 · 10⁻¹² |
| Pasillo | 25,2 | 6,982 | 0,000 | 0,000 | 0,000 | 6,982 | 0,2090 | −8,9 · 10⁻¹⁶ |
| Dormitorio 1 | 25,2 | 6,982 | 0,000 | 0,000 | 0,000 | 6,982 | 0,2090 | 0 |
| Dormitorio 2 | 16,8 | 4,655 | 0,000 | 0,000 | 0,000 | 4,655 | 0,2090 | 0 |
| Cocina | 36,0 | 9,974 | 0,000 | 0,000 | −0,000 | 9,974 | 0,2090 | 0 |
| Baño | 16,8 | 4,655 | 0,000 | 0,000 | 0,000 | 4,655 | 0,2090 | 0 |

Con la puerta cerrada solo cambia el Salón: los demás recintos no
intercambian con él y están a la concentración exterior.

### El fuego, apagado y encendido

**Es una medida, no un criterio.** No dice cuál se parece más a un ensayo.

| | `o2_closed`, apagado | `o2_closed`, encendido | `o2_reopen_300`, apagado | `o2_reopen_300`, encendido |
| --- | --- | --- | --- | --- |
| Pico de potencia (kW) | 559,2 | 569,1 | 559,2 | 569,1 |
| Energía acumulada (MJ) | 79,96 | 87,46 | 125,02 | 125,83 |
| Segundos con potencia | 396,2 | 419,2 | 859,9 | 891,8 |
| Menor oxígeno que leyó el fuego | 0,1065 | 0,1086 | 0,1073 | 0,1110 |
| Número de sala del Salón al final | 0,1167 | 0,1155 | 0,1518 | 0,1576 |
| Débito del recinto (kg) | 0,000 | 6,647 | 3,531 | 9,563 |
| Declarado como consumido (kg) | 6,624 | 6,647 | 13,439 | 9,563 |
| Lo que pide el calor (kg) | 6,077 | 6,647 | 9,501 | 9,563 |
| Extinción | A los 396,2 s | A los 419,2 s | A los 860,0 s | A los 891,9 s |
| Reactivación | No | No | No | No |

- **`o2_closed`.** La energía pasa de 80,0 a 87,5 MJ y el fuego
  dura 23 s más. **No se ha aislado** cuánto se debe a cada cosa que
  cambia con el modo: el depósito que lee el fuego (M2), la base molar
  del inventario (M1) y la dilución sin recorte (M2-V).
- **El débito de sala de la ruta histórica** es 0 en `o2_closed` porque
  ahí el recinto cerrado debita un número de capa, no el de sala; y lo
  declarado como consumido supera a lo que pide el calor porque se
  declara dos veces. Son O2-1 y O2-4, que M2 retiró con el modo
  encendido.
- **`o2_reopen_300`.** 125,0 frente a 125,8 MJ: en los dos el sofá
  se consume casi entero.
- **Reactivación:** ninguna en ningún caso.
- **Las trazas de la ruta histórica son pasivas:** las seis salidas de
  cada caso son idénticas byte a byte a las de la corrida de identidad.

## Hueco histórico: control causal

M2 dejó medido que al final de `o2_reopen_300` faltan 0,3778 kg con la cola
vacía, y que eso **coincidía** con el recorte al techo. Una coincidencia no
es una causa. Aquí se aísla.

**El mecanismo que se predijo, antes de medir.** Cuando se abre la puerta
del Salón, el Pasillo le cede oxígeno; su débito viaja en la cola y
tarda en llegar. Mientras tanto su lectura efectiva —su número con lo que
ya debe— es baja, y con esa lectura intercambia con los dormitorios, la
cocina y el baño, que están a 0,209: el neto sale a su favor. Ese crédito
se le aplica **en el acto** a su número, que sigue en 0,209 porque su
débito no ha llegado: se recorta al techo y se pierde. Las otras salas sí pagan su parte, más
tarde.

### La copia que solo cuenta

Una copia diagnóstica del sistema de oxígeno cuenta, llamada a llamada,
lo que `_apply_room_o2_mass_delta` recibió, lo que aplicó y lo que tiró.
No cambia ninguna escritura: las seis salidas de la corrida son idénticas
byte a byte a las de la identidad.

| `o2_reopen_300`, ruta histórica | |
| --- | --- |
| Llamadas | 136858 |
| Se le pidió aplicar | 39,6959 kg |
| Aplicó | 39,3181 kg |
| **Tirado al recortar al techo** | **0,3778234130 kg**, en 7788 llamadas |
| …en el crédito inmediato a la sala caliente | 0,3778234130 kg |
| …en el intercambio de fondo | 4,9 · 10⁻¹² kg |
| …en las entregas diferidas | 0 |
| …en el Pasillo | 0,3778234130 kg |
| Tirado al recortar al suelo | 0,0 kg |
| Descartado por estar bajo el umbral de 10⁻⁶ kg | 0,0 kg, 0 llamadas |
| Redondeo de las escrituras no recortadas | 9,5 · 10⁻¹² kg |
| Pasos con descarte | 160, entre 307,1 y 320,5 s |
| **Hueco al final** | **−0,3778234130 kg** |
| Hueco más lo tirado, al final | −9,5 · 10⁻¹² kg |
| Hueco más lo tirado, peor paso | 9,5 · 10⁻¹² kg |

**El hueco es el descarte, en cada paso y no solo al final**, hasta el
redondeo de las demás escrituras. Las otras tres causas posibles suman
cero. Con la puerta cerrada, en `o2_closed`, la misma copia cuenta
1,5 · 10⁻¹¹ kg —el redondeo de salas que están exactamente a 0,209,
en ningún paso por encima de 10⁻¹² kg— y el hueco es −4,3 · 10⁻¹¹ kg.

### El control: quitar ese recorte

La misma copia con el techo retirado de esa única escritura. **No es la
ruta histórica y no es un arreglo del transporte.** Su diff queda junto a
la corrida y el archivo se restaura con su huella comprobada.

| `o2_reopen_300`, copia de control | |
| --- | --- |
| Hueco al final | −1,1 · 10⁻¹¹ kg |
| Mayor hueco de toda la corrida | 1,1 · 10⁻¹¹ kg |
| Pasos en que el hueco crece | 0 |
| Tirado al techo por esa escritura | 8,8 · 10⁻¹³ kg |
| Oxígeno que esas escrituras dejan por encima de 0,209 | 0,670 kg, en el Pasillo |
| Pasos en que algún número de sala termina sobre 0,209 | 0 |
| Transporte del bucle de gases, cambio del número sumado | −0,00711 (en la corrida distribuida, según el registro de M2: 3,3 · 10⁻¹⁵) |
| Recorte final del motor | 0,0 |

- **Causa demostrada:** con el recorte, el hueco; sin él, ninguno.
- **A dónde va entonces ese oxígeno**, que no se predijo: ningún número de
  sala termina un paso por encima de 0,209. Lo vuelve a cortar, más tarde
  en el mismo paso, el transporte del bucle de gases, que tiene su propio
  recorte a 0,209 y cuyo corte **no entra** en los acumuladores de
  transporte. El hueco desaparece de las cuentas, no del motor.
- **Lo que no está hecho:** reconstruir en kg, sala a sala, cuánto corta
  ese segundo escritor. Su cifra es una suma de fracciones de todas las
  salas; si fuera toda del Pasillo serían unos 0,21 kg. La
  dinámica de la copia de control ya no es la histórica y no se ha ido
  más lejos.
- **Corrige lo publicado en M2**, que situaba el recorte en «entregas
  positivas» diferidas. Es el crédito inmediato.

## Enriquecimiento con el modo encendido

**Lo hay.** El propietario no tira ese crédito: lo acredita.

| Recinto | Entre | Pasos | Mayor exceso de fracción | Mayor exceso | Pasos en que su lectura efectiva también supera el aire |
| --- | --- | --- | --- | --- | --- |
| Pasillo | 307,4 – 329,4 s | 265 | +0,01116 | 0,3728 kg a los 320,5 s | 0 |
| Dormitorio 1 | 309,6 – 324,2 s | 176 | +0,00012 | 0,0040 kg a los 320,7 s | 0 |
| Dormitorio 2 | 309,6 – 319,7 s | 122 | +0,00009 | 0,0019 kg a los 316,9 s | 0 |
| Cocina | 309,7 – 328,0 s | 221 | +0,00011 | 0,0053 kg a los 324,1 s | 0 |
| Baño | 309,5 – 326,3 s | 203 | +0,00019 | 0,0042 kg a los 322,5 s | 0 |

- **De dónde sale:** 1772 créditos inmediatos al donante de un
  intercambio cuando ya estaba a la concentración exterior o por encima,
  1,139 kg en total; 1,117 kg al Pasillo. Ninguna llegada
  del tránsito, ninguna infiltración y ningún venteo acreditan a un
  recinto en ese estado.
- **Qué lo explica:** el tránsito y la ley histórica, no el contrato de
  referencia. El Pasillo recibe ya lo que gana y todavía no ha entregado lo
  que debe: su inventario más lo que viaja hacia él —que es negativo—
  **no supera el aire exterior en ningún paso**. `M` más `T` se conserva.
- **Magnitud y duración:** el Pasillo llega a 0,2202, con
  0,373 kg de más, y vuelve a 0,209 o menos a los
  329,4 s. El máximo es casi lo que la ruta histórica tira:
  0,378 kg. Las otras cuatro salas, del orden de cien veces menos.
- **El recinto que arde no se enriquece** en ninguna de las dos casas. Con
  la puerta cerrada no se enriquece ninguno.
- **No se ha escondido:** sin recorte, sin pérdida contable y sin
  redistribuir nada.

**Es un defecto de transporte y no se corrige aquí.** Un recinto a la
concentración del aire no puede hacerse más rico que el aire
intercambiando con recintos que no lo son. La ley histórica acredita en el
acto un neto calculado con una lectura que ya descuenta una deuda, y
retrasa la deuda. Arreglarlo es cambiar esa ley —cuándo se acredita y
cuándo se debita— y es una fase aparte.

## Límites físicos

- **Dilución equivalente, no conservación de la masa de gas.** El gas
  caliente que sale por la ley de orificio y el aire que la ley hace
  entrar no son la misma masa.
- **El oxígeno y los demás gases se purgan con fracciones distintas.** CO,
  CO₂ y HCN salen con la fracción de volumen purgada; el oxígeno solo se
  diluye con `0,40 · smoke_out_kg`. Es la ley histórica.
- **`smoke_out_kg` es una cantidad híbrida:** una masa de gas acotada por
  el 15 % de una masa de partículas. El aire que entra hereda esa cota.
- **Contenido de referencia fijo.** `M = x · n_ref · M_O2` con el recinto a
  1,2 kg/m³, como en M1: exacto mientras los moles del recinto no cambien,
  una aproximación en un recinto caliente que ventea.
- **Enriquecimiento transitorio** de recintos que no arden, arriba.
- **Los números de capa** siguen siendo auxiliares históricos hasta M4.

## El déficit que queda para M3

- **En las dos casas el tope del 5 % no actuó:** 0 kg recortados en 0
  pasos, y el débito es 0,076 kg por MJ del calor del Salón hasta el
  redondeo. En ellas el calor no supera lo que respalda el débito.
- **Eso no cierra O2-3.** En el control de tope de M1 —una demanda impuesta
  de 20 MW— quedan 2,263 kg anotados como recortados con el calor
  intacto, y `o2_stress_cap` deja 8,22 kg sin debitar en la ruta
  histórica. Son cifras de M1 y del diagnóstico del 09-10, no vueltas a
  medir aquí; la fixture de M1 sí se ha vuelto a correr, en verde. **El calor todavía puede superar lo que respalda el débito de
  oxígeno.**
- **No se ha ajustado** calor, combustible ni productos. No se ha tocado
  la química ni los rendimientos.
- **Ningún débito superó lo disponible** de su selección en las casas.

## Decisión sobre M3

Es del usuario. Lo que este trabajo permite decir:

- **GO para empezar M3 en su alcance estrecho:** ajustar el calor de un
  recinto que arde al oxígeno de su propia selección. Ya hay casos de
  producto donde medirlo, corren enteros y cierran; y en ellos el recinto
  que arde no se enriquece.
- **NO-GO, hasta decidir la ley de transporte, para todo lo que lea el
  número de sala de un recinto que no arde como concentración física:** la
  exposición (hipoxia en FED), el reparto entre capas de M4, y cualquier
  caso con fuego en una sala que a la vez recibe créditos inmediatos y
  debe oxígeno en tránsito —dos fuegos, o un fuego en el Pasillo—. No se
  ha corrido ningún caso así; por el mismo mecanismo, lo que el fuego
  leería podría estar por encima del aire durante segundos.
- **Condición para M3:** que su aceptación incluya una comprobación de que
  el recinto que arde no supera la concentración exterior, y que rechace o
  declare el caso en que sí.

## Mutaciones

**Del venteo.** 16 mutantes de código sobre el motor real, declarados
antes de ejecutar con el grupo que debía verlos. Control en verde.
**16 de 16 muertos donde se declaró**; ningún superviviente,
ninguno inválido, ninguno muerto por sintaxis. Cada archivo restaurado
con huella SHA-256 comprobada.

Las diez familias pedidas con la etapa son W01, W02, W03, W04, W05, W06, W07, W08, W09, W10.

| | Defecto que inyecta | Archivo | Debía verlo | Resultado |
| --- | --- | --- | --- | --- |
| W01 | El venteo retira humo y gases y su dilución no llega al inventario | `GasExchangeSystem.gd` | V02 | Muerto en V02; 13 comprobaciones fallidas |
| W02 | La entrada se le quita al recinto y la salida se le da | `RoomOxygenInventory.gd` | V03 | Muerto en V03; 20 comprobaciones fallidas |
| W03 | El oxígeno que entra se acredita dos veces | `RoomOxygenInventory.gd` | V03 | Muerto en V03; 21 comprobaciones fallidas |
| W04 | El oxígeno que sale se debita dos veces | `RoomOxygenInventory.gd` | V03 | Muerto en V03; 21 comprobaciones fallidas |
| W05 | La fracción molar exterior se multiplica directamente por la masa de gas | `RoomOxygenInventory.gd` | V03 | Muerto en V03; 12 comprobaciones fallidas |
| W06 | Lo que deja la dilución se recorta a 0,209 en silencio, como la escritura histórica | `RoomOxygenInventory.gd` | V04 | Muerto en V04; 2 comprobaciones fallidas |
| W07 | Un evento de venteo diluye el recinto dos veces | `GasExchangeSystem.gd` | V06 | Muerto en V06; 8 comprobaciones fallidas |
| W08 | Un intercambio diferido cambia al donante y no deja nada en tránsito, mientras el recinto ventea | `RoomOxygenInventory.gd` | V05 | Muerto en V05; 6 comprobaciones fallidas |
| W09 | Con el modo encendido el venteo escribe además el número de sala | `GasExchangeSystem.gd` | V07 | Muerto en V07; 17 comprobaciones fallidas |
| W10 | El venteo sigue siendo una ruta que el propietario rechaza | `GasExchangeSystem.gd` | V02 | Muerto en V02; 24 comprobaciones fallidas |
| W11 | No se pregunta al propietario antes de escribir: un evento rechazado deja humo, gases y presión escritos | `GasExchangeSystem.gd` | V08 | Muerto en V08; 2 comprobaciones fallidas |
| W12 | El acumulador exterior del recinto es el cambio de su número por su masa, no lo que aplicó el propietario | `GasExchangeSystem.gd` | V06 | Muerto en V06; 2 comprobaciones fallidas |
| W13 | El gas sale a la fracción que el recinto tenía antes de mezclar: la masa entrante usada directamente | `RoomOxygenInventory.gd` | V03 | Muerto en V03; 5 comprobaciones fallidas |
| W14 | Las selecciones del paso se construyen otra vez cuando un recinto ventea | `GasExchangeSystem.gd` | V07 | Muerto en V07; 2 comprobaciones fallidas |
| W15 | El propietario contesta que cualquier dilución se aplicaría: nada se detiene antes de escribir | `RoomOxygenInventory.gd` | V08 | Muerto en V08; 10 comprobaciones fallidas |
| W16 | El evento anota su neto como entrada y ninguna salida | `RoomOxygenInventory.gd` | V02 | Muerto en V02; 11 comprobaciones fallidas |

«Omitir el tránsito del balance» es aquí el mismo cambio que el mutante
T01 de M1, sobre un recinto que ventea mientras intercambia con su vecino.

Mutantes y control corren los grupos que juzgan, V01 a V09. El grupo V10
solo mide el efecto frente a la ruta histórica.

**De la selección (M2), otra vez.** 15 mutantes sobre el motor de hoy:
**15 de 15 muertos donde se declaró**.

**Del inventario (M1), otra vez.** 21 mutantes: **21 de 21 muertos
donde se declaró**.

## M1 y M2 siguen en pie y la ruta histórica no ha cambiado

- **La aceptación de M1, sobre el motor de hoy:** 281 comprobaciones, 0
  fallos.
- **La aceptación de M2, sobre el motor de hoy:** 102 comprobaciones, 0
  fallos.
- **El diagnóstico del 09-10, vuelto a medir** con el interruptor apagado:
  13 hipótesis, idénticas cifra a cifra.
- **El registro de M2 no se reescribe.** Es evidencia de su commit,
  `461fa9c0`, y su prueba pasa a ligarlo a esos archivos.

## Verificación

Todo secuencial, un Godot cada vez y siempre bajo el monitor, con su
mínimo de 6 GiB sin rebajar. La cadena esperó a tener 6,6 antes de cada
paso y arrancó cada uno con entre 7,43 y 8,40, comprobando además
que el procesador no estuviera limitado y que no quedara ningún Godot
vivo. `basetemp` de pytest fuera del repositorio; `APPDATA`, `TEMP` y
`TMP` fuera de él o en la carpeta de evidencia de cada corrida, bajo
`runs/`, que no se versiona.

Orden: mutaciones, identidad con el interruptor apagado, casos de casa y
controles causales, registro, regresiones, referencia, guardarraíles,
producto, enlaces y global. Las cifras de pytest de la tabla son las de
la pasada final, con el informe ya completo.

| Paso | Resultado |
| --- | --- |
| Fixture de M2-V sobre el motor de `461fa9c0` | 102 comprobaciones, **41 fallos**, 0 errores de script |
| Fixture de M2-V sobre este árbol | **126 comprobaciones, 0 fallos**, sin errores de script |
| Fixture de M1 sobre este árbol | **281 comprobaciones, 0 fallos** |
| Fixture de M2 sobre este árbol | **102 comprobaciones, 0 fallos** |
| Mutaciones del venteo | 16 declaradas; control en verde; **16 muertas donde se declaró**; 0 supervivientes, 0 inválidas |
| Mutaciones de la selección | 15 declaradas; **15 muertas donde se declaró**; 0 supervivientes, 0 inválidas |
| Mutaciones del inventario | 21 declaradas; **21 muertas donde se declaró**; 0 supervivientes, 0 inválidas |
| Restauración tras cada mutante y cada copia diagnóstica | Por SHA-256 |
| **Identidad con el interruptor apagado** | **9 de 9 casos byte a byte** contra la corrida de `461fa9c0` |
| Diagnóstico del 09-10 vuelto a medir, interruptor apagado | 13 hipótesis, idénticas cifra a cifra |
| Casos de casa, modo encendido | **Los dos enteros**, 10800 pasos, sin rechazos; los tres balances dentro de 1 · 10⁻⁹ kg en cada paso |
| Casos de casa, ruta histórica con la traza | Las seis salidas de cada uno, idénticas byte a byte a las de la identidad |
| Copia diagnóstica que solo cuenta | Las seis salidas de cada caso, idénticas byte a byte a las de la identidad |
| Regresiones de G3, fixtures que fallan cerrado, contratos de oxígeno y de la red | **1704 passed, 30 skipped, 2 xfailed** |
| **Referencia completa**, monitorizada | **346 de 346** requeridas PASS; los mismos 78 huecos |
| Corpus de la referencia | 382 archivos: 381 idénticos byte a byte, ninguno con cambio solo de fin de línea. El único que cambia es `reference_checks.json`, y **solo en `generated_at`** |
| Guardarraíles, con R2-1 | **Todos PASS** |
| `check_product.py` | **168 PASS** |
| Enlaces de la documentación | Ninguno roto en esta entrega. El comprobador sigue señalando dos, ajenos y anteriores, en `addons/sky_3d/ThirdParty.md` |
| `git diff --check` | Limpio |
| `python -m pytest tests -q -p no:cacheprovider` | **4509 passed, 56 skipped, 2 xfailed, 42 subtests passed** |

La referencia se regeneró porque `sim/` cambia. No se ha modificado
ninguna expectativa ni se ha establecido una línea base nueva.

**Contratos anteriores que se tocan, de forma estrecha, y se dice:**

| Contrato | Qué decía | Qué se hizo y por qué |
| --- | --- | --- |
| El venteo por sobrepresión se rechaza | Una de las cinco rutas rechazadas por nombre en M1 y M2 | Sale de ese conjunto: es una ruta soportada. Las otras cuatro siguen rechazadas y una prueba lo fija |
| Ramas del intercambio de gases detrás del propietario | Cuatro | Cinco: la quinta toma del propietario el acumulador exterior del venteo |
| El registro de M2 pertenece a su código | Comparaba con los archivos de hoy | Compara con los de su commit, `461fa9c0`. No se reescribe; la aceptación de M2 se vuelve a correr sobre el motor de hoy |
| La casa con el modo encendido «se informa como salió» | En el registro de M2, rechazada a los 74,4 s | Ese registro y su prueba no cambian: son de su commit. El resultado de hoy está en el registro de M2-V |

### Lo que no se ha ejecutado

- **Ningún otro caso de casa con el modo encendido.** `o2_stress_cap`,
  los de puerta exterior abierta, PPV o HVAC siguen sin correr: pasan por
  rutas rechazadas o por el tope, que es M3.
- **La reconstrucción en kg, sala a sala, de lo que corta el segundo
  escritor en la copia de control.**
- **El paso entero por forma cerrada con vecinos:** con intercambio
  interior en el mismo paso, el oráculo del venteo comprueba la aritmética
  de la dilución sobre el contenido anotado en el evento.
- **Ninguna comparación de exposición.** CO y FED siguen OFF/NO-GO.
- **Ninguna validación física del venteo** contra un ensayo.

### Lo que salió mal por el camino

- **La primera versión de la fixture medía mal el humo retirado:** leía el
  acumulador de humo del recinto, que también cuenta lo que sale por otras
  rutas, y daba catorce fallos falsos. Se cambió por el contador pasivo
  que la propia ley del venteo lleva, antes de cualquier corrida de
  registro.
- **Una comprobación del rechazo entero estaba mal planteada:** ese
  contador se incrementa antes de la decisión de ventear, así que no sirve
  para decir que un evento rechazado «no retiró humo». Se comprueba con el
  acumulador de humo, la masa de humo, el CO₂ y el alivio de presión.
- **Se lanzaron por descuido pruebas que arrancan Godot** con un caso de
  casa en marcha. Se negaron al ver el proceso y no lanzaron nada; la
  corrida de casa se repitió después dentro de la cadena.
- **Las corridas de casa y de control se hicieron dos veces:** una para
  ver los resultados y otra, de una vez y con el árbol ya final, dentro de
  la cadena. Las cifras del registro son las de la segunda.

**Salud.** Ningún proceso de Godot al cerrar, ninguno ajeno terminado,
sin tiempos agotados ni cuadros de error.

## Siguiente paso propuesto

**Ninguno está autorizado.** En el orden en que los haría:

1. **Decidir la ley del crédito y el débito entre recintos**, en una fase
   separada y antes de cualquier gate de exposición: que el crédito
   inmediato y su deuda se apliquen a la vez, o que el crédito no pueda
   llevar a un recinto por encima de quien se lo da. Cambia el transporte
   histórico y mueve la referencia con el interruptor apagado si se hace
   también ahí; hay que decidir si es solo para el modo encendido.
2. **M3**, en su alcance estrecho, que puede ir antes o después del punto
   1: el calor ajustado al oxígeno de la selección del recinto que arde, y
   qué hacer con el tope del 5 %.
3. **Las rutas que siguen rechazadas** —hueco exterior caliente, PPV,
   parcelas, transporte del bucle de gases, HVAC— cuando un caso de
   producto las necesite. El libro por escritor dice que estas dos casas
   no las necesitan.
