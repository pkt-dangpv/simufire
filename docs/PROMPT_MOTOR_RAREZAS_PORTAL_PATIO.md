# Diagnóstico: dos rarezas del portal y del patio

> **(a) arreglada el 2026-09-15 detrás de un interruptor** (decisión del
> usuario): `exterior_opening_bernoulli_o2_enabled` (`SimulationEngine` →
> `OxygenExchangeSystem`, **false por defecto**). Encendido, una apertura
> exterior no vertical repone O₂ con el mismo Bernoulli de dos zonas que una
> puerta interior (`_step_outside_opening_o2_bernoulli`): el estado de flujo
> sale de `ThermalSystem.build_interior_opening_flow_state` con el exterior como
> sala virtual infinita a temperatura ambiente, lo que entra se contabiliza como
> O₂ exterior y repone la zona inferior. Solo O₂; humo, CO₂ y energía no cambian.
> Los huecos verticales al cielo (la boca del patio) siguen por la heurística.
>
> | 300 s | quemado | O₂ inferior a 240 s | factor O₂ |
> |---|---|---|---|
> | C calle, heurística | 344 MJ | 0,199 | 0,87 |
> | **C calle, Bernoulli** | **394 MJ** | **0,209** | **1,00** |
> | D portal (igual con y sin) | 401 MJ | 0,209 | 1,00 |
>
> C/D pasa de 0,86 a 0,98. Apagado, C sale idéntico byte a byte; D (sus
> exteriores están cerradas) no cambia al encender. Guardarraíl
> `tools/validate_exterior_opening_o2.gd` con C y D como fixtures
> (`tests/fixtures/exterior_o2_portal_*.json`), **13/13 mutaciones muertas**
> (desvío que nunca o siempre usa Bernoulli, interruptores encendidos por
> defecto, `configure` y motor que no lo pasan, motor que ignora el del
> escenario, editor que no lo enciende, `BuildingModel` que no lo carga o lo
> carga a true, zona inferior sin reponer, O₂ sin contabilizar como exterior y
> caudal de la capa alta en vez de la baja). Por la calle entra ahora menos
> O₂ en total (10,3 kg frente a 17,4) pero a la zona que lee el fuego.
>
> Nota para la auditoría de O₂: esta vía añade dos escrituras registradas con
> los propietarios de la vía exterior (`oes_exterior_opening` y
> `oes_exterior_opening_lower_replenish`). El recuento estático declarado en
> `SimulationEngine` (`writer_coverage`: 45/23/22) es de antes y no las incluye.
>
> **Dónde se enciende** (decisión del usuario): en los escenarios del editor,
> como el viento por altura y la capa fina.
> `ScenarioSerializer.EDITOR_EXTERIOR_OPENING_BERNOULLI_O2_ENABLED = true` va en
> el JSON de ejecución, `BuildingModel` lo carga y el motor lo aplica si lo pide
> él o el escenario (`_effective_exterior_opening_bernoulli_o2_enabled`). Las
> plantillas del catálogo y los casos de validación siguen con la heurística.
>
> **(b) cerrada documentada**: no es un fallo (ver abajo y `PROMPT_MOTOR_PATIO.md`).

Medido el 2026-09-15 con el motor de `main` en `011c6bab`, **sin tocar código**.
Escenarios: variantes C y D del portal (`PROMPT_MOTOR_PORTAL.md`, 2026-09-13) y el
patio de tres plantas (`PROMPT_MOTOR_PATIO.md`, 2026-09-11), 300 s, con
`scripts/run_scenario.py --phase3-zone-diagnostics`.

## (a) El fuego quema más con la puerta al portal que con la puerta a la calle

Anotado en el portal: D 401 MJ frente a C 344 MJ. Se reproduce igual.

Las dos variantes son idénticas salvo **a dónde da la puerta abierta de la
vivienda del fuego**: en C, al exterior; en D, al Portal R (caja cerrada de
4 × 4 × 2,90 m por planta, zaguán cerrado). Ventana cerrada en las dos.

| | C (puerta a la calle) | D (puerta al portal) |
|---|---|---|
| quemado a 300 s | 344 MJ | **401 MJ** |
| HRR pico | 2492 kW | 2768 kW |
| O₂ que entra desde el exterior (neto) | **17,4 kg** | 0,3 kg |
| O₂ que entra desde otras salas (neto) | 2,3 kg | 14,9 kg |
| O₂ inferior a 210–300 s | 0,196–0,202 | **0,209** |
| factor de O₂ del fuego a 210–300 s | 0,85–0,91 | **0,99–1,00** |
| capa térmica a 300 s | 1,62 m | 0,50 m |

**Entra más O₂ por la puerta a la calle (19,7 kg en total frente a 15,2), y aun
así el fuego quema menos.** No es cuánto aire entra, es **a qué zona llega**, y
el fuego lee la zona inferior (`fire_o2_mode`):

- **Apertura al exterior** — `OxygenExchangeSystem._step_outside_opening_o2`,
  que se usa siempre para cualquier apertura con `OUTSIDE_ID`, también con el
  solver de dos zonas: una fórmula empírica. La altura de entrada arranca en el
  8 % del hueco (`maxf(0.06, op.height_m * 0.08)`) y solo crece con el cuadrado
  del déficit de O₂; el intercambio se limita al 1–12 % de la masa de la sala
  **por paso**; y el aire entrante se mezcla contra la masa de la sala entera
  y, aparte, contra la zona inferior («dos inventarios, dos bases», dice el
  propio código).
- **Puerta interior** — `_step_interior_opening_o2` con
  `vent_bernoulli_enabled`: el caudal de Bernoulli de la capa baja entrante
  (`bernoulli_lower_kg_s` de `ThermalSystem.build_interior_opening_flow_state`),
  que repone la zona inferior con el aire de la sala vecina.

Resultado: una puerta a una caja de 46 m³ alimenta el fuego mejor que la misma
puerta a la calle, que es aire ilimitado. **Es una asimetría del motor, no
física.** Afecta a cualquier escenario con la sala del fuego ventilando al
exterior, que son casi todos.

## (b) En el patio, la vivienda de arriba «ve» el humo antes que la de en medio

Anotado en el patio: visibilidad < 10 m en Vivienda P2 a 84 s y en Vivienda P1
a 182 s. Se reproduce igual. **No es un fallo.**

- A los 84 s, Vivienda P2 tiene **1,8 g** de humo repartidos por toda la sala
  (la capa de humo sigue en el techo, 2,50 m). Esa concentración da 9,8 m de
  visibilidad: es óptica correcta. Diez metros es un umbral muy sensible.
- Por qué le llega antes que a P1: el humo sube por los huecos del patio (de
  2,5 × 2,5 m, la planta entera) y **se acumula en la zona de arriba**, bajo la
  salida al cielo. A los 80 s la zona-patio P2 tiene 20 g y la P1, 1 g; desde
  ahí entra por la ventana a la vivienda de arriba. Es el mismo llenado desde
  el techo que se vio en el portal (el rellano de arriba recibe humo antes que
  el de abajo). Vivienda P1 no pasa de 0,2 g hasta los 150 s.
- En masa las dos llegan casi a la vez (> 0,01 kg: P2 a 193 s, P1 a 216 s).

No es el plano neutro: la sobrepresión de la zona-patio P1 (4–13 Pa) es mucho
mayor que la de P2 (≈ 1,8 Pa), pero tiene muy poco humo que empujar.

Ficheros de la medición (cuaderno de la sesión): `C.json`, `D.json`,
`patio.json`, `leer_rarezas.py`.
