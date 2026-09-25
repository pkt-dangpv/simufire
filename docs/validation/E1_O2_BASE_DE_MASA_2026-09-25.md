# E1 del contrato de O₂ — ¿pueden las masas de capa sostener el inventario?, 25 de septiembre de 2026

> **Pregunta:** ¿son `upper_gas_kg` / `lower_gas_kg` una base fiable para llevar
> O₂ en kg por capa (alternativa B del [contrato](CONTRATO_O2_2026-09-24.md)) en
> la ruta normal del producto? ¿Quién escribe O₂ y masa de gas durante un paso?
>
> **Base:** [contrato de O₂](CONTRATO_O2_2026-09-24.md) ·
> [diagnóstico](DIAGNOSTICO_O2_CASA_SIMPLE_2026-09-24.md) ·
> [fiabilidad de masa zonal, S0d6b0.2](PHASE3_H32S0D6B02_ZONAL_GAS_MASS_RELIABILITY.md) ·
> [diseño de autoridad de O₂, S0d6b](PHASE3_H32S0D6B_O2_AUTHORITY_DESIGN.md) ·
> [F2.2 §18.6 y R2-MASS](../PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md)
>
> **Dos tiempos.** La parte estática se hizo con **3,78 GB** libres de
> 15,33 GB, sin Godot y sobre las trazas de la fase anterior (`%TEMP%/diag_base`,
> `diag_ctrl_canonical`, `diag_ctrl_sealed_door`, `diag_ctrl_nofire`). Después,
> con **6,95 GB** libres, se ejecutaron seis fixtures pequeños en secuencia
> (§3.5), fuera del árbol y sin tocar la suite de referencia. **No se ha cambiado física, orden del paso, interruptores,
> perfiles, escenarios, casos FDS, baselines, tolerancias ni
> `reference_checks.json`.** Sin instrumentación temporal.
>
> HEAD `8a8e205b`. Las líneas citadas son las de ese árbol, con los cambios sin
> commit de G4/G5 presentes (ninguno toca los ficheros citados de `sim/core` ni
> `sim/fire`).

---

## 0. Decisión

| modo | ¿masas de capa como autoridad de O₂? | por qué, en una línea |
|---|---|---|
| **Red de presión OFF** — ruta de producto, los 5 escenarios G0 | **NO-GO** | `ZoneFireSolver.project_room_state()` **reescribe** `lower_gas_kg` con `volumen restante × densidad a presión de referencia` en cada proyección (`ZoneFireSolver.gd:360-369`). **Medido en este HEAD** (§3.5): Salón sellado con fuego, mínimo −25,7 % de masa y +22,60 kg anotados en la frontera sin propietario; con la puerta abierta, +332,6 kg y −169,6 kg |
| **Red de presión ON** — experimental | **NO-GO** | **Medido en este HEAD:** la masa de gas del edificio se conserva exactamente (201,600000 kg, frontera 0). Pero con la puerta abierta hay **dos propietarios** del transporte interior —`ThermalSystem` lleva 64,59 kg al Pasillo y la red devuelve 64,05— y el O₂ en kg **no** se conserva: −0,113 kg sin propietario en el recinto sellado y **−5,10 kg** (78 % del consumo) con la puerta abierta |

> **P3b (25-09, §8).** La siembra radiativa movía gas sin sus especies ni su
> O₂; ya es un único paquete. El 0,25 % de especies sin ruta de la red es la
> renovación ACH, medida paso a paso y con control. R2-1 vigila ahora también
> `sim/BuildingModel.gd`.
>
> **P3 cerrado (25-09, §7).** Los dos propietarios del transporte interior con
> la red ON eran un duplicado real y se han reducido a uno: la red. La masa por
> sala cierra a 1,8·10⁻¹³ kg. **La decisión sobre la base de O₂ no cambia**: el
> residuo de O₂ con la red ON persiste (−5,82 kg en la casa, puerta abierta) y
> O2-4 sigue abierto.

> **Actualización del mismo día — parte dinámica hecha.** Tras liberar memoria
> (6,95 GB libres) se ejecutaron seis fixtures pequeños, en secuencia y con el
> lanzador `scripts/run_scenario.py`. Resultados en §3.5. Donde el texto
> anterior dice «no medido» o «provisional», manda §3.5.

**La alternativa B no puede empezar sobre la ruta de producto tal como está.** El
prerrequisito es que la masa de la capa baja sea **estado** en la ruta normal
(§5, P1). La alternativa A no cumple la disponibilidad por capa y queda
descartada como solución. La C existe ya en parte como sombra
(`phase3_o2_zonal_mass_shadow_enabled`, P1R3, apagada por defecto) y puede servir
de ledger diagnóstico, no de física publicable.

**Tres correcciones al contrato O2-A que salen de este trabajo** (§4):

1. Los **9,263 kg** de «declarado − descontado» **no son el tope del 5 %**. Son
   una **segunda declaración** del mismo consumo por el sumidero de la capa
   superior. El tope del 5 % recorta **0,943 kg**.
2. **C1 falla en el caso base por usar el contador equivocado.** Con el consumo
   que de verdad se aplicó a `room.o2`, el Salón cierra con residual **0,0000 kg**.
3. **C3 no mide combustión perdida:** los 35,3 MJ de diferencia son el retardo de
   suavizado del HRR. El 5 % no tiene justificación en el contrato energético.

---

## 1. Qué ejecuta de verdad un paso

`SimulationEngine.step()` en este HEAD, con `fire_o2_mode = "legacy"`:

```
_step_exterior_opening_smooth · snapshots de sombra (solo diagnóstico)
_step_pool_fires
[_step_oxygen]            ← solo si fire_o2_mode ∈ {upper, lower, interface}
_step_fire                ← CombustionSystem: hrr_kw, combustible, productos
_step_co_oxidation · _step_targets
_step_oxygen              ← OxygenExchangeSystem (modo legacy)
thermal_system.step       ← penacho, proyección de zonas, puertas interiores
_step_suppression · _step_steam_decay
_step_gas_exchange        ← AQUÍ la red de presión (si ON) y el venteo histórico
_step_hvac · _step_passive_fuel
_clamp_rooms              ← clamps finales, colapso de capa quiescente
```

**Corrección al §1 del contrato:** presión y venteo **no** van antes de
`_step_pool_fires`; viven dentro de `_step_gas_exchange`
(`SimulationEngine.gd:4198`), después del térmico. Lo que va al principio son los
snapshots de las sombras de fase 3.

---

## 2. Mapa de escritores

### 2.1 Cómo se contó

El registro del motor declara 47 escrituras de estado O₂ en producción, 25
instrumentadas y 22 no (`SimulationEngine.gd:5005-5043`), con el método anotado
como *«single static pass; adversarial per-writer verification incomplete»* y
**números de línea de aquella pasada**. Se rehízo el barrido en este HEAD con

```
grep -rnE "\b[a-z_]+\.(o2|o2_upper|o2_lower|upper_o2_mass_tracked)\s*(=|\+=|-=|\*=)[^=]" sim
```

y aparecen **52** escrituras: las **47** del registro, que casan una a una con
las actuales, más **5 que el registro no cuenta**: las dos del rastreador en kg
(`OxygenExchangeSystem.gd:399, 714`) y las tres de la red de presión
(`PressureNetworkTransportSystem.gd:881-883`), añadidas después del recuento.
Fuera del bucle queda la reinicialización `RoomModel.gd:391`.

Columnas: **G0** indica si puede ejecutarse en los cinco escenarios del ámbito
(red OFF, HVAC inexistente —`hvac_exists = false` en los cinco—, interruptores
por defecto). «sí» = corre en cualquier sala con la condición indicada; «posible»
= depende de lo que haga el jugador o de la geometría; «no» = un interruptor
apagado lo impide. **Tipo**: *T* transfiere masa física (sumidero, fuente,
transporte), *S* solo sincroniza o re-deriva una representación, *C* clamp.
Todas escriben **fracción molar**; la base de masa es `volumen × 1,2 kg/m³`
salvo donde se indica.

### 2.2 Instrumentados (25)

| # | sitio | función | escribe | fase | condición / interruptor | origen → destino | tipo | G0 |
|---|---|---|---|---|---|---|---|---|
| 1 | `OES:474` | `step` | `room.o2` | O₂ | siempre; consumo solo si `hrr>0` y no plume/lower/2B | llama + ACH exterior → sala | T | sí |
| 2 | `OES:533` | `step` | `o2_upper` | O₂ | `hrr>0`, `lower_frac≥0,15`; **consumo estequiométrico completo** porque OES ve `two_zone_solver_enabled=false` (§4.1) | capa alta → llama | T | sí |
| 3 | `OES:610` | `step` | `o2_lower` | O₂ | `fire_uses_lower_o2` | capa baja → llama | T | no |
| 4 | `OES:646` | `step` | `o2_lower` | O₂ | `effective_plume_lower` (sala cerrada dentro y fuera, o `fire_o2_canonical_enabled`) | capa baja → llama; tope con masa de capa, aplica con masa de sala | T | posible |
| 5 | `OES:692` | `step` | `o2_upper` | O₂ | siempre | — | C | sí |
| 6 | `OES:704` | `step` | `o2_lower` | O₂ | siempre | — | C | sí |
| 7 | `OES:938` | `_step_outside_opening_o2` | `indoor.o2` | O₂ | abertura exterior abierta, red OFF, sin Bernoulli | exterior ↔ sala | T | sí |
| 8 | `OES:973` | `_step_outside_opening_o2` | `o2_lower` | O₂ | ídem, `air_in>0` | exterior → capa baja; **mismo `air_in` ya acreditado al bulk** | T | sí |
| 9 | `OES:1486` | `_step_outside_opening_o2_bernoulli` | `indoor.o2` | O₂ | `exterior_opening_bernoulli_o2_enabled` | exterior ↔ sala | T | no |
| 10 | `OES:1503` | ídem | `o2_lower` | O₂ | ídem | exterior → capa baja | T | no |
| 11 | `GES:1644` | `step_pressure_venting` | `room.o2` | gas | red OFF, sobrepresión sobre umbral | exterior → sala (`air_in = 0,40 × humo expulsado`) | T | sí |
| 12 | `GES:2387` | bucle de sala | `room.o2` | gas | siempre (con red ON los deltas son 0) | salas ↔ salas/exterior, 8 caminos agregados | T | sí |
| 13 | `GES:2923` | entrega de parcela | `target.o2` | gas | parcela interior diferida | sala → sala, con retardo | T | posible |
| 14 | `GES:4261` | `step_ppv` | `inlet_room.o2` | gas | PPV activa, red OFF; mezcla por `lerpf`, **sin balance de masa** | exterior → sala | T | posible (jugador) |
| 15 | `SimulationEngine:5222` | `_clamp_rooms` | `room.o2` | clamps | siempre, techo `o2_nominal` | — | C | sí |
| 16 | `Thermal:3389` | `_apply_doorway_thermal_counterflow` | `o2_lower` | térmico | `doorway_thermal_counterflow_enabled` | sala fría → capa baja caliente, reparto 50/50 declarado | T | no |
| 17 | `Thermal:3397` | ídem | `o2_upper` | térmico | ídem | ídem | T | no |
| 18 | `Thermal:3412` | ídem | `o2_lower` | térmico | ídem | donante | T | no |
| 19 | `Thermal:3435` | ídem | `hot.o2` | térmico | ídem | mezcla de reparación, sin donante | S | no |
| 20 | `Thermal:3452` | ídem | `cold.o2` | térmico | ídem | ídem | S | no |
| 21 | `Thermal:3499` | `_apply_canonical_doorway_exchange` | `o2_upper` | térmico | `canonical_doorway_exchange_enabled` | capa alta → capa alta | T | no |
| 22 | `Thermal:3598` | ídem | `o2_upper` | térmico | ídem | ídem | T | no |
| 23 | `Thermal:3615` | ídem | `o2_lower` | térmico | ídem | capa baja fría → capa baja caliente | T | no |
| 24 | `Thermal:3663` | ídem | `hot.o2` | térmico | ídem | mezcla | S | no |
| 25 | `Thermal:3684` | ídem | `cold.o2` | térmico | ídem | mezcla | S | no |

### 2.3 Los 22 **no instrumentados** — ninguno se declara seguro

Que no aparezcan en una traza **no prueba nada**: no hay contador que pudiera
verlos. Las líneas entre paréntesis son las del registro antiguo.

| # | sitio actual (registro) | escribe | condición / interruptor | origen → destino | tipo | G0 |
|---|---|---|---|---|---|---|
| U1 | `HVAC:213` (213) | `o2_upper` | HVAC + `hvac_two_zone_o2_enabled` | capa baja → capa alta, sin masa | S | no |
| U2 | `HVAC:302` (302) | `room.o2` | HVAC con caudal; `lerpf` | impulsión → sala | T | no |
| U3 | `HVAC:306` (306) | `o2_upper` | ídem | ídem | T | no |
| U4 | `HVAC:308` (308) | `o2_lower` | ídem; suelo `room.o2` | ídem | T | no |
| U5 | `HVAC:314` (314) | `o2_lower` | ídem | ídem | T | no |
| U6 | `OES:402` (389) | `o2_upper` | `fire_o2_mass_tracking_enabled` | rastreador kg → fracción | S | no |
| U7 | `OES:483` (470) | `o2_upper = room.o2` | `lower_frac < 0,15` | homogeneiza; crea/destruye O₂ zonal | S | sí |
| U8 | `OES:488` (475) | `o2_lower = max(o2, o2_lower)` | ídem + `phase2h_…` | ídem | S | no |
| U9 | `OES:490` (477) | `o2_lower = room.o2` | `lower_frac < 0,15` | ídem | S | sí |
| U10 | `OES:558` (545) | `o2_upper` | fuego y bi-zona válida | arrastre capa baja → alta **por tasa fija** (`0,010·dt`), sin descontar de la capa baja la masa equivalente | T | sí |
| U11 | `OES:593` (580) | `o2_lower` | ídem; suelo `room.o2` | drenaje de la capa baja, **otra escala** (0,20) que U10 | T | sí |
| U12 | `OES:675` (662) | `o2_lower` | fuego | infiltración exterior → capa baja | T | sí |
| U13 | `OES:679` (666) | `room.o2` | `effective_plume_lower` o 2B | bulk **re-derivado** de las capas; **no se anota en `o2_zone_sync_kg`** | S | posible |
| U14 | `OES:682` (669) | `o2_lower` | sin fuego | relaja hacia `room.o2` | S | sí |
| U15 | `OES:688` (675) | `o2_upper` | sin fuego | relaja hacia `room.o2` | S | sí |
| U16 | `OES:990` (964) | `o2_lower` | `phase2h_…` | refuerzo exterior | T | no |
| U17 | `OES:1154` (1128) | `room_a.o2` | vano interior abierto, red OFF | sala A → B (salida) | T | sí |
| U18 | `OES:1155` (1129) | `room_b.o2` | ídem | sala B → A (salida) | T | sí |
| U19 | `OES:1213` (1187) | `o2_lower` | `phase2h_…` | drenaje por contraflujo | T | no |
| U20 | `OES:1218` (1192) | `o2_lower` | flujo activo por vano, red OFF | sala fría → capa baja caliente; **los mismos kg ya se aplicaron al bulk** (O2-2) | T | sí |
| U21 | `OES:1258` (1232) | `o2_upper` | `doorway_o2_upper_routing_gain > 0` | capa alta → capa alta | T | no |
| U22 | `OES:1316` (1290) | `room.o2` | toda entrega de kg de O₂ al bulk (intercambio, parcela) | destino | T | sí |

### 2.4 Cinco escrituras fuera del registro

| sitio | escribe | condición | tipo | G0 |
|---|---|---|---|---|
| `OES:399` | `upper_o2_mass_tracked` (kg) | `fire_o2_mass_tracking_enabled` | S | no |
| `OES:714` | ídem | ídem | S | no |
| `PNTS:881` | `o2_upper = kg / upper_gas_kg` | red ON | S (deriva de kg) | no |
| `PNTS:882` | `o2_lower = kg / lower_gas_kg` | red ON | S | no |
| `PNTS:883` | `room.o2 = kg total / gas total` | red ON | S — **sobrescribe el bulk** | no |

### 2.5 Recuento para los cinco escenarios G0

- **Pueden correr: 24** de 47 (12 instrumentados y 12 no instrumentados; 6 de
  ellos solo «posible»), más la reinicialización. Todos en `OxygenExchangeSystem`, `GasExchangeSystem` y el
  clamp final.
- **No pueden correr: 23** (HVAC, contraflujo térmico, puerta canónica, Bernoulli
  exterior, `phase2h`, rastreador, sumidero de capa baja) y las 5 de fuera del
  registro.
- De los 24, **8 solo sincronizan o recortan** (S/C): cambian O₂ sin que ninguna
  masa se mueva.

### 2.6 Escritores de masa de gas

| sitio | operación | G0 | ¿conserva la suma del recinto? |
|---|---|---|---|
| `ZoneFireSolver.gd:369` | `lower_gas_kg = volumen restante × ρ(T) a presión de referencia` | **sí** (red OFF) | **no**: la diferencia va a `two_zone_boundary_mass_kg` sin propietario físico |
| `ZoneFireSolver.gd:343` | tope de la capa alta a `V × ρ_alta` | sí (red OFF) | no, condicional |
| `ZoneFireSolver.gd:150` | siembra `V × 1,2` si la sala está vacía | sí | no (siembra) |
| `ZoneFireSolver.gd:193-195` | penacho baja → alta | sí | **sí**, entre capas |
| `ZoneFireSolver.gd:437-439` | colapso alta → baja | sí | sí, entre capas |
| `Thermal:1505-1506` | gas caliente por vano interior | sí | sí, entre salas; **no lo apaga la red** |
| `Thermal:3593, 3636` | puerta canónica | no | sí entre salas; no lo apaga la red |
| `Thermal:2988, 3172` | intercambio de fondo | sí (OFF) | sí; la red sí lo apaga |
| `Thermal:1206` | mezcla exterior de capa alta | no: `outside_open_upper_mix_rate = 0,0` por defecto | propietario exterior anotado |
| `Thermal:1646` | siembra de capa alta vacía por radiación | sí | **no**: declarada corrección numérica (S0d1) |
| `Thermal:3320` | `cold.upper += 0,005` | no | no, sin donante |
| `Thermal:3839` | retirada de fracción de capa alta (venteo, humo exterior, PPV, HVAC) | sí (red OFF) | salida al exterior |
| `GES:2049/2224, 2915, 3292/3294` | transporte y parcelas | sí (OFF) | sí entre salas |
| `HVAC:490` | `max(upper, 0,35·aire)` | no | no |
| `PNTS:875-876` | estado final de la red | no (ON) | sí, por construcción |
| `SimulationEngine:5232-5255` | clamps ≥ 0; colapso quiescente vía `collapse_upper_into_lower` | sí | sí |
| `Thermal:952/964/975/2741/1884` (ramas sin bi-zona) | ganancia de penacho sin donante | no (`two_zone_solver_enabled = true`) | — |

---

## 3. Balance de masa por modo

### 3.1 Lo que no se pudo medir y por qué

> **Superado por §3.5**, que mide todo esto en este HEAD. El texto se conserva
> como registro de la parte estática.

**La reconstrucción paso a paso no es posible en esta fase.** Las trazas
registradas de la casa simple no tienen `upper_gas_kg` ni `lower_gas_kg`
(requieren `--phase3-zone-diagnostics`), y `air_mass_kg` es la constante
`volumen × 1,2`. Con 3,78 GB libres no se lanzó Godot. Queda **pendiente la
parte dinámica** (§5, P2).

Lo que sigue es evidencia **ya registrada** en fases anteriores, más el código.
**No se ha re-medido en `8a8e205b`**, y desde entonces entraron R3, D2, D3, D4 y
la activación controlada de física experimental.

### 3.2 Red OFF — ruta de producto

| recinto | fuente | masa total | por capa | entradas/salidas físicas | frontera (sin propietario) |
|---|---|---|---|---|---|
| sellado, **con fuego**, dos salas, 600 s | F2.2 §18.6, caso A0 | 96,000 → **79,035 kg a 100 s** → 95,459 a 600 s | sala del fuego 48,000 → **31,036 kg** a 100 s, 47,48 al enfriar | 0 (sellado) | −0,4039 y −0,1368 kg; residuo −0,5408 kg |
| sellado, caliente, **sin fuego**, 60 pasos | validador `R2-M9 OFF` | **baja** (el validador lo exige: `mass_after < mass_before`) | — | 0 | `< 0` exigido |
| sellado, a temperatura ambiente, sin fuego | código | constante: `ρ(T_amb) · V` es la masa inicial | — | 0 | 0 |
| diez casos CFAST, 67 salas | S0d6b0.2 §3 | — | — | — | neto de −51,7 a +33,65 veces la masa nominal de la sala |

**Transferencia entre capas frente a pérdida.** El penacho (`ZoneFireSolver:193`)
y el colapso (`:437`) mueven masa entre capas y conservan la suma. La pérdida no
sale por ninguna abertura: la anota la **proyección** en
`two_zone_boundary_mass_kg`. En el caso A0 la causa se aisló en R2-MASS: el
**100 %** de la pérdida venía de reescribir la masa baja (`:369`), el tope de la
alta aportó 0,0000 kg y los nueve propietarios físicos también 0,0000 kg.

**Es función de la temperatura, no una fuga.** Por eso la sala «recupera» masa al
enfriarse: `volumen × densidad a presión ambiente` devuelve menos masa cuanto más
caliente está el gas.

### 3.3 Red ON — experimental

| recinto | fuente | masa total | frontera |
|---|---|---|---|
| sellado, **con fuego**, dos salas, 600 s | F2.2 §18.6, A1 | **96,000000 kg** constantes; la sala del fuego en 48,000000 kg y 42 028 Pa a 100 s | **0,000000000 kg** |
| ídem con rendija 12/21 cm² y puerta abierta | A2–A4 | 96,000000 kg | 0 |
| portal de tres plantas, seis salas, 7 200 pasos | R2-MASS | **347,04 kg**, residuo −2,3·10⁻¹³ kg | 0 en todas |
| sellado, caliente, sin fuego, 60 pasos | `R2-M9 ON` | igual a 1·10⁻⁹ kg | 0 a 1·10⁻¹² kg |

Aquí la geometría sale del estado (`zone_geometry_from_state`) y la masa baja no
se reescribe (`ZoneFireSolver:360-367`, rama `canonical_mass_conservation_enabled`).

**Lo que estas medidas no pueden ver.** Todas cierran **la suma del edificio**.
Una sala que transfiere gas a otra por dos caminos a la vez también la cierra. Y
hay dos caminos: con la red encendida `ThermalSystem` **sigue moviendo** gas
caliente por los vanos interiores (`Thermal:1505`, y `:3593/:3636` con la puerta
canónica), porque ese bucle solo comprueba `op.open_fraction`, no
`authoritative_transport_enabled` (solo lo comprueban los intercambios de fondo,
`:2884` y `:3074`). Si ese camino actúa a la vez que la red, habría **dos
propietarios del transporte interior**. No está medido. En A1 la puerta estaba
cerrada y no podía verse.

### 3.4 Qué pasa con el O₂ encima de esas masas

Aunque la masa de gas se conserve, **el O₂ no se guarda en kg en ningún modo**:

- **OFF.** `OxygenExchangeSystem` no usa `upper_gas_kg` ni `lower_gas_kg`. Su
  base es `volumen × 1,2` repartida por fracción de volumen
  (`OES:369, 378-391`).
- **ON.** La red reconstruye los kg al empezar su paso como
  `o2_capa × gas_capa` (`PNTS:222-223`), los transporta y **vuelve a derivar las
  fracciones**, incluida `room.o2` (`PNTS:881-883`). Consecuencias, **derivadas
  del código y sin medir**:
  1. el consumo bulk que `OxygenExchangeSystem` descontó de `room.o2` en ese
     paso **se descarta**: la red recalcula `room.o2` desde las capas;
  2. el consumo que sí sobrevive es el del sumidero superior, calculado sobre
     `V × 1,2 × fracción` y reinterpretado sobre `upper_gas_kg`, otra base;
  3. el penacho mueve `m` kg de gas de la capa baja a la alta sin tocar las
     fracciones, así que el O₂ en kg cambia en `m · (x_alta − x_baja)` sin que
     nadie lo haya movido;
  4. la conversión trata la fracción molar como fracción másica, al revés que la
     sombra P1R3, que ya usa `Y = x · M_O₂ / M_mezcla`.

### 3.5 Medida dinámica en este HEAD (25-09, tras liberar memoria)

**Montaje.** Casa simple del producto (`scenarios/preset_simple_house.json`,
seis salas, 201,6 kg de gas), copiada **fuera del árbol** con estas únicas
diferencias: todas las aberturas cerradas —o solo la puerta Salón↔Pasillo
abierta—, `glass_auto_break_enabled = false` para que el recinto siga cerrado,
`pressure_network_solver_enabled` según el modo, 300 s y **registro en cada
paso** (`log_interval_s = 1/12`, 3 601 filas por sala). El resto son los valores
del motor por defecto, como en G0; fuego en el sofá del Salón. Lanzador:
`scripts/run_scenario.py` con `--phase3-zone-diagnostics`,
`--phase3-runtime-ownership-ledger`, `--phase3-physical-owner-ledger` y
`--phase3-projection-causal-diagnostics`. Seis corridas en secuencia, las seis
`PASS`, sin errores de la red, sin procesos residuales. Duración: unos 20 s cada
una.

Por paso y por sala se reconstruyó `ΔM = Σ etapas (alta/baja)` con las diez
etapas del motor. **El residuo máximo por paso es ≤ 3·10⁻⁸ kg** en todas las
corridas, que es el redondeo del CSV. La contabilidad de etapas cierra, así que
lo que sigue son movimientos atribuidos, no huecos del registro.

**Masa de gas.**

| corrida | edificio (kg) | Salón: final (mín.) | frontera sin propietario | movimiento físico atribuido |
|---|---|---|---|---|
| OFF, sellado, sin fuego | 201,600000 constante | 57,60 (57,60) | 0 | ninguno |
| ON, sellado, sin fuego | 201,600000 constante | 57,60 (57,60) | 0 | ninguno |
| **OFF, sellado, fuego** | 201,60 → 196,02 (**mín. 186,81**) | 52,02 (**42,83**, −25,7 %) | Salón **+22,60 kg** neto | Salón: 28,16 kg de capa alta **al exterior** por la purga histórica (`zone_upper_removed`), con **290 kPa** de sobrepresión; penacho alta/baja |
| **ON, sellado, fuego** | **201,600000** constante | 57,60 (57,60) | **0** | solo transferencia entre capas: Salón 36,67 kg de baja a alta; residuo ≤ 1,4·10⁻¹⁴ kg |
| **OFF, puerta abierta, fuego** | 201,60 → 199,20 (**mín. 165,72**) | 56,04 (**30,95**) | Salón **+332,6 kg**, Pasillo **−169,6 kg** | puerta 80,39 kg Salón→Pasillo; capa alta retirada al exterior 125,6 y 81,4 kg |
| **ON, puerta abierta, fuego** | **201,600000** constante | 57,05 (53,88) | **0** | `ThermalSystem` (`canonical_doorway_upper`, `Thermal:1505`) lleva **64,591 kg** del Salón al Pasillo y la red (etapa `gas_exchange`) devuelve **64,05 kg** |

Lecturas:

- **OFF: el balance lo rompe la proyección, confirmado en este HEAD.** Con la
  red apagada, la masa de una sala sellada con fuego baja un cuarto y la
  proyección anota **+22,6 kg** que ningún propietario físico aporta. Con la
  puerta abierta la frontera mueve **cientos de kg**, más que la masa de las dos
  salas. Además, el recinto «sellado» no lo es: la purga histórica de envolvente
  saca 28 kg a una sobrepresión de 290 kPa, la magnitud inflada ya documentada
  en F2.1.
- **ON: la masa se conserva en este HEAD, también con fuego.** Sin frontera y
  con residuo de máquina. Las transferencias entre capas suman cero.
- **ON: dos propietarios del transporte interior, confirmado.** La suma del
  edificio no lo detecta. Por etapas se ve: la ruta histórica del térmico y la
  red mueven el mismo gas en sentidos opuestos. P3 deja de ser un riesgo y pasa
  a ser un defecto medido.

**O₂ en kg sobre esas masas.** Inventario `Σ (x_alta · m_alta + x_baja · m_baja)`,
la convención de la red, comparado con el consumo del camino primario
(`o2_consumed_fire_kg_total`, que en las cuatro corridas con fuego coincide con
el estequiométrico del calor aceptado) y la infiltración exterior de OES.

| corrida | ΔO₂ zonal (kg) | consumo | exterior | **residuo sin propietario** | `_all` − primario |
|---|---:|---:|---:|---:|---:|
| OFF, sellado, fuego | −5,483 | 5,064 | +0,120 | **−0,539** | 0,456 |
| ON, sellado, fuego | −5,114 | 5,109 | +0,108 | **−0,113** | 0,460 |
| OFF, puerta abierta | −13,295 | 13,644 | +0,284 | +0,065 | **8,743** |
| ON, puerta abierta | −11,412 | 6,563 | +0,255 | **−5,104** | **6,073** |

- **Con la masa de gas exacta, el O₂ en kg sigue sin conservarse.** En el
  recinto sellado ON queda un residuo de −0,113 kg (2,2 % del consumo), y con la
  puerta abierta **−5,10 kg, el 78 % del consumo**. Así se ve que guardar
  fracciones sobre una masa conservada no basta: el inventario no existe como
  estado.
- **O2-4 confirmado con los valores de producto.** Con la puerta abierta y la red
  OFF —la situación normal de G0— el sumidero superior declara **8,74 kg**
  además de los 13,64 kg del camino primario, y la capa alta del Salón baja a
  **0,0008**. En los recintos sellados la rama es la de desplazamiento (9 %,
  0,46 kg), porque ahí `effective_plume_lower` está activo.
- **ON con la puerta abierta, candidatos del residuo** (no aislados uno a uno):
  el doble descuento de O2-4 ya no se queda en una representación aparte,
  porque la red reconstruye los kg desde `o2_upper` en cada paso, y los
  6,07 kg declarados de más son del mismo orden que los 5,10 perdidos; los
  64,6 kg que mueve el térmico cambian `x · m` en las dos salas sin mover O₂;
  el penacho mueve gas entre capas sin mover O₂. **No se atribuye una cifra a
  cada uno.**
- **C1 en la ruta de producto.** Con la puerta abierta y la red OFF, el bulk
  cierra con **−0,0002 kg** usando el consumo aplicado, igual que en la casa
  FDS. En los sellados el bulk no cierra (−4,89 / −5,22 kg) porque el consumo va
  a la capa baja y `room.o2` se re-deriva de las capas sin anotarlo (U13).

Trazas y scripts, fuera del árbol: `scratchpad/e1/` (`*.json` de los casos,
`mass_audit.py`, `o2_audit.py` y una carpeta por corrida).

---

## 4. Revisión de las pruebas O2-A antes de hacerlas gates

### 4.1 Hallazgo que cambia la lectura: el sumidero superior declara el consumo dos veces

`SimulationEngine` pasa `two_zone_solver_enabled` al térmico
(`SimulationEngine.gd:1332`) pero **no** a `OxygenExchangeSystem.configure()`
(`SimulationEngine.gd:1588-1640`, la clave no aparece). `OxygenExchangeSystem`
se queda con su valor por defecto, `false` (`OES:139`). Con eso, en cada paso con
fuego el sumidero de la capa alta toma la rama «sin bi-zona»
(`OES:515-518`) y descuenta de `o2_upper` **el consumo estequiométrico
completo**, además del que la vía bulk ya descuenta de `room.o2`. Ambos se suman
en `o2_consumed_kg_total_all`.

La traza base lo confirma. Diferencias de acumuladores por intervalo de 20 s:

| t (s) | sumidero superior / estequiométrico | bulk / estequiométrico | `o2_upper` |
|---:|---:|---:|---:|
| 20–120 | **1,000** | 1,000 | 0,2079 → 0,0456 |
| 140 | 0,536 | 1,000 | **0,0008** |
| 200 | 0,367 | 1,000 | 0,0008 |
| 260 | 0,342 | **0,516** | 0,0009 |

Si OES viera la bi-zona, la rama sería la de desplazamiento y la razón sería
**0,09** (`plume_upper_o2_displacement_frac`). El commit que introdujo la guarda
(`99dff662`) declara la intención —«when two_zone_solver_enabled, skip direct
o2_upper depletion by fire»— y no pasó la clave entonces ni la pasa ahora. La
hoja de ruta ya lo tenía anotado desde otro ángulo: *«`o2_consumed_kg_total_all`
acumula 2× Thornton en modo two-zone estándar… usar
`o2_consumed_fire_kg_total`»*.

Se propone registrarlo como **O2-4** —doble descuento del consumo sobre
`o2_upper`, con la capa alta vaciada a 0,0008 en 140 s— sin arreglarlo aquí.

### 4.2 C1 — conservación por sala

| corrida | con `_all` | con el consumo aplicado a `room.o2` (`bulk` = `fire_primary`) |
|---|---:|---:|
| base | +9,2626 kg | **+0,0000 kg** |
| puerta cerrada | +1,3151 | −2,1447 (`bulk`) / +1,0295 (`fire_primary`) |
| canonical | −0,9451 | −10,7571 (`bulk`) / −1,7553 (`fire_primary`) |

- **En la base, `room.o2` conserva exactamente** lo que su propio camino le hace.
  El fallo de C1 era la doble declaración de §4.1, no O₂ creado en el bulk.
- En los dos controles con penacho bajo el bulk se **re-deriva** de las capas
  (U13, `OES:679`) y ese cambio no se anota en `o2_zone_sync_kg_total`, que vale
  0 en las tres corridas. Ningún contador cierra.

**Corrección:** C1 debe cerrar sobre el **inventario que se declare
autoritativo**, con cada término aplicado a ese inventario: el consumo aplicado a
él, no uno declarado en otra representación, y un término explícito para toda
re-derivación. Mientras el bulk sea el inventario, `o2_consumed_kg_total_all` no
sirve.

### 4.3 C2 — un solo consumo

Tal como está compara `_all` con `bulk`. Tres problemas:

1. **Mide O2-4, no O2-3.** En la base, los 9,263 kg de diferencia son
   íntegramente la segunda declaración de §4.1.
2. **No puede ver O2-3.** El tope recorta `consumed` **antes** de sumarlo a los
   dos contadores (`OES:453-460`), así que lo recortado no aparece en ninguno. Su
   magnitud real sale de comparar con el calor aceptado:
   `hrr_kj_total × 7,6·10⁻⁵` = **20,941 kg** frente a 19,998 kg descontados:
   **0,943 kg (4,5 %)**, concentrados al final (bulk/estequiométrico = 0,516 a
   260 s).
3. **Falla por diseño con el enrutado canónico:** ahí el bulk no descuenta nada
   (0,000 kg) porque el consumo va a la capa baja. Si E2 unifica el enrutado, C2
   seguiría rojo aunque el arreglo fuese correcto.

**Corrección:** C2 compara el O₂ que exige la **combustión aceptada**
(`Δhrr_kj_total × r`, con la `r` del fuego) con el O₂ **descontado del inventario
autoritativo** —hoy, el de la vía que corrió; con B, la suma de los débitos en kg
de ambas capas—, y exige además que cada combustión se declare **una vez**. Es el
invariante O2E1 de la hoja de ruta, pero su tolerancia del 5 % **aceptaría** los
0,943 kg de la base (4,5 %). La tolerancia de C2 sale del suelo numérico medido
(§3.1 del contrato), no del 5 %.

### 4.4 C3 — combustible frente a calor

Integrando la traza base por segundo:

| término | MJ |
|---|---:|
| pirólisis (`pyrolysis_kw`) | 312,3 |
| objetivo de llama (`flame_hrr_target_kw`) | **312,3** |
| inquemados generados | 0,0 |
| bolsa retenida al final | 0,000 |
| calor aceptado (`hrr_kw`) | 277,0 |

El objetivo de llama coincide con la pirólisis y no hay inquemados. **Los 35,3 MJ
(11,3 %) son el retardo del suavizado:** `hrr_kw` sigue a `hrr_target_kw` con una
constante de subida de 6–10,8 s (`CombustionSystem.gd:1861-1872`), y un fuego que
crece hasta 3,3 MW acumula del orden de `τ × HRR` ≈ 35 MJ. El combustible se
descuenta al ritmo de la pirólisis (`:2248-2251`), el calor al ritmo suavizado.

Consecuencias:

- **El 5 % no tiene base.** El desfase depende de `τ` y del HRR, no de un
  porcentaje: pasa con holgura en la puerta cerrada (+0,5 %) y falla en la base
  (−11,3 %) por la misma causa.
- **C3 señala algo real, pero no lo que dice su nombre.** Los productos de
  carbono salen del combustible (`c_avail_kg = solid_fuel_demand_MJ × c_per_MJ`,
  `:2163`) y el O₂ del calor aceptado. **Productos y O₂ describen masas quemadas
  distintas** mientras dura el retardo. Eso sí rompe «la misma transacción».
- En el control canonical aparecen 3,3 MJ de pirólisis que no llegan a llama; con
  `fire_unburned_generation_fraction = 0,02` solo el 2 % pasa a la bolsa
  retenida y el resto **no tiene inventario**.

**Corrección:** C3 como identidad con términos con nombre

```
combustible = calor aceptado + Δ bolsa retenida + inquemado no retenido + calor diferido por suavizado
```

con tolerancia de redondeo, y dos invariantes aparte: el O₂ y los productos
siguen a la **misma** tasa en el mismo paso, y el término «inquemado no
retenido», si existe, se declara. No se da un número hasta tener ese contrato
escrito.

### 4.5 C5 — sin enriquecimiento espontáneo

Hoy compara `o2_lower` de la sala que arde con el O₂ **actual** más alto de las
demás salas. Es a la vez:

- **demasiado estricto:** una capa que conserva su O₂ inicial mientras sus
  vecinas se agotan queda «por encima de su fuente» sin crear nada;
- **demasiado laxo** si se añade el exterior como fuente: la infiltración está a
  0,209 y justificaría cualquier subida.

Forma corregida. Una capa solo puede **subir** hacia fuentes más ricas **que su
estado previo**, y como mucho lo que esas fuentes aportan en masa:

```
m_baja · x'_baja  ≤  m_baja · x_baja + Σ m_in,i · x_i − sumideros
```

Versión cualitativa, calculable ya con la traza, sin masas: marcar una subida de
`o2_lower` cuando ninguna sala vecina estaba, en el paso anterior, por encima del
valor previo de la capa.

| corrida | C5 actual | C5 corregido (cualitativo) |
|---|---:|---:|
| base | 49 s en falta | **10 de 31 subidas** sin fuente interior más rica; peor a t = 221 s: 0,20749 → 0,20889 con la vecina más rica en 0,19633 |
| canonical | 0 | 0 de 36 |
| puerta cerrada | 0 | 0 de 50 |
| sin fuego | 0 | 0 de 0 |

Sigue discriminando. Pero la forma cualitativa **ignora la infiltración
exterior**, que es una fuente real aunque diminuta (≈2·10⁻⁶ /s); las subidas
medidas en la base son del orden de 10⁻³ /s, tres órdenes por encima. El gate
definitivo es la forma en masa, y esa necesita caudales por capa y por paso, que
el CSV actual no tiene.

### 4.6 C4 — disponibilidad

Usa también `o2_consumed_kg_total_all` como demanda: hereda O2-4 y hoy
sobreestima lo pedido. Misma corrección que C2.

### 4.7 Qué se deja como está

No se ha tocado `tests/test_oxygen_contract.py`: ninguna prueba se ha relajado
ni se ha puesto en verde. Las correcciones anteriores son el trabajo previo a
convertirlas en gates.

---

## 5. Prerrequisitos para E2 y para B

**P1 · Masa baja como estado en la ruta de producto — prerrequisito de B.** La
operación que rompe el balance es `ZoneFireSolver.project_room_state()`,
`target_lower_mass_kg = lower_volume_m3 × lower_density_kg_m3` a presión de
referencia (`:360-369`), en modo **red OFF**, llamada por seis familias de
proyección; la más activa en A0 fue `thermal_post_combustion_sync`
(−21,69 kg a 100 s). La corrección existe (R2-MASS), pero **solo con la red**. Hay
dos caminos y la decisión es del usuario: **(a)** desacoplar la geometría desde
estado de la red —entonces un recinto sellado se presuriza y el venteo histórico
tiene que leer esa presión—, o **(b)** que la ruta de producto use la red, lo que
arrastra G2, R3 y la PPV no soportada. Sin P1, **B queda bloqueada**.

**P2 · Medida dinámica en este HEAD — hecha (§3.5).** Queda como
prerrequisito convertir el montaje en fixture versionado cuando se autorice
tocar `tests/`: el caso sellado, el de puerta abierta y los dos balances por
etapa.

**P3 · Un solo propietario del transporte interior con la red ON — hecho
(§7).** Duplicado demostrado y corregido solo con la red encendida; OFF
idéntico byte a byte.

**P4 · O2-4 clasificado antes de E2.** Decidir si el sumidero superior es consumo
o desplazamiento y si `OxygenExchangeSystem` debe recibir `two_zone_solver_enabled`.
Cambiarlo mueve baselines y es física: va en su propia etapa, con regeneración.
E2 debe saber sobre qué sumidero trabaja.

**P5 · Reescribir C1, C2 y C4 antes del gate de E2.** El gate de E2 pide «C2
dentro de tolerancia», y C2 tal como está **falla por diseño** con el sumidero
unificado (§4.3.3). Primero la forma de §4.3, luego E2.

**P6 · Una sola convención de conversión.** La red usa `kg = x × m_gas`; la sombra
P1R3 y el diseño S0d6b0.1 usan `kg = x × (M_O₂/M_mezcla) × m_gas`. B necesita una.

**P7 · Ledger sombra.** `phase3_o2_zonal_mass_shadow_enabled` (P1R3) ya lleva O₂
en kg por capa con conversión molar, apagado por defecto. Sirve de alternativa C
para diagnosticar; no es la solución de publicación.

**E2 (O2-1) puede empezar sin B** —trabaja en la representación actual—, pero
**no antes de P4 y P5**.

---

## 6. Estado y verificación

- **Memoria y procesos:** 3,78 GB libres al empezar la parte estática, sin
  Godot. Tras liberar memoria, 6,95 GB libres; **siete lanzamientos de Godot,
  secuenciales**: uno de prueba con registro cada 1 s (descartado) y los seis
  de §3.5. Todos `PASS`. Al terminar, 7,12 GB libres y **ningún proceso Godot
  vivo**. No se ejecutó la suite de referencia.
- **E1 no cambió código; P3 sí** (§7: `sim/core/ThermalSystem.gd`, un
  validador y una prueba nuevos). En E1, ningún fichero de `sim/`, `tools/`, `scenarios/` ni
  `tests/` modificado por esta fase; ninguna instrumentación temporal.
- **Trabajo previo sin commit conservado:** de los 23 ficheros sin commit al
  empezar (G4/G5, auditoría FDS, O2-A), 21 mantienen su SHA-256 (`sha256sum -c`).
  Cambian solo los dos que esta fase amplía: el contrato de O₂ (nota de
  cabecera, fila E1 y §9) y la hoja de ruta (una entrada añadida). Este
  documento es nuevo.
- **Verificación:** `git diff --check` limpio; enlaces de los tres documentos
  resueltos (los 193 avisos de `check_docs_links.py` están todos bajo `runs/`);
  pruebas estáticas de O₂ (contrato O2-A, S0d6, P1R3) 30 pasan, 5 omitidas y
  2 xfail; con `SIMUFIRE_O2_RUN_DIR` apuntando a la traza base las 5 pruebas de
  traza siguen fallando igual que en O2-A; guardarraíles 7/8, solo falla R2-1.
- **R2-1 sigue en rojo por causa preexistente** (`sim/templates/BuildingTemplate.gd`
  modificado y sin commitear desde G4/G5). Esta fase no lo toca ni lo
  oculta.

---

## 7. P3 — un único propietario del transporte interior con la red ON

**Montaje.** Dos salas (Salón 5×4 m con un sofá de 1 100 MJ / 700 kW, Pasillo
4×4 m, 2,4 m de altura), puerta de 0,9×2,0 m; variantes con la puerta cerrada,
con el fuego en el Pasillo (inversión de gradiente) y con dos plantas unidas por
un hueco vertical de 1,2 m. Motor por defecto, 1 440 pasos de 1/12 s. Arnés
temporal en `runs/p3_tmp/` (ignorado por git) que, tras cada `engine.step()`,
lee los eventos de propietario del térmico y las rutas de la transacción de la
red, sin tocar el motor; lanzador propio con temporales aislados, límite de
tiempo, corte ante error fatal y monitor que detiene Godot por debajo de 5 GB
libres. Control «solo red»: `doorway_heat_exchange_coeff = 0` **solo en el
arnés**, que anula la masa del transporte térmico sin cambiar código.

### 7.1 Qué eran los 64,59 y los 64,05 kg de §3.5

- **64,59 kg**: mecanismo `canonical_doorway_upper` de
  `ThermalSystem.step()` (`Thermal:1505`): gas de la **capa alta** de la sala
  caliente a la **capa alta** de la fría, por la abertura interior, con su
  entalpía (temperatura de mezcla de la fuente) y siete especies (CO, CO₂, HCN
  con su parte alta, humo, HCl, acroleína, formaldehído). Su caudal es
  `flow_state.bernoulli_upper_kg_s`, la salida de Bernoulli de dos zonas.
- **64,05 kg**: la etapa `gas_exchange`, que con la red ON es la transacción de
  `PressureNetworkTransportSystem`. Cada ruta lleva masa, entalpía, O₂,
  CO/CO₂/HCN por capa y humo/HCl/acroleína/formaldehído de la sala.

Que sus magnitudes se parezcan no prueba nada. Lo que lo prueba es esto:

### 7.2 Libro por abertura, sentido y capa (dos salas, puerta abierta, red ON)

| propietario | origen → destino | masa (kg) | entalpía (kJ) | CO₂ (g) | humo (g) |
|---|---|---:|---:|---:|---:|
| **térmico** | Salón.alta → Pasillo.alta | **24,770** | 1 626,9 | sin ruta: +199,7 | sin ruta: +20,6 |
| red | Salón.alta → Pasillo.alta / baja | 1,847 / 3,985 | 259,2 / 151,5 | 61,7 / 31,4 | 2,8 / 2,2 |
| red | Salón.baja → Pasillo.alta / baja | 10,264 / 3,350 | 429,3 / 41,0 | 3,1 / 0,3 | 43,7 / 3,6 |
| red | Pasillo.baja → Salón.baja | **39,557** | 386,8 | 21,9 | 12,2 |
| red | Pasillo.alta → Salón.baja / alta | 0,638 / 0,005 | 22,3 / 0,2 | 5,0 / 0,0 | 0,5 / 0,0 |
| **solo red** (control) | Salón.alta → Pasillo.baja | **21,013** | 2 933,3 | 713,2 | 40,4 |
| solo red | Salón.baja → Pasillo.baja | 17,064 | 642,9 | 16,1 | 44,1 |
| solo red | Pasillo.baja → Salón.baja / alta | **33,394** / 0,135 | 616,8 / 2,6 | 139,3 / 0,6 | 15,4 / 0,1 |

Las especies del térmico se obtienen por diferencia: lo que ganó la sala fría
menos lo que entregaron las rutas de la red.

- **La red sola ya lleva la salida caliente y el contraflujo físico** por la
  misma puerta: 21,0 kg de capa alta hacia fuera y 33,5 kg de aire frío hacia
  dentro.
- **El térmico actúa en 808 pasos, y en los 808 la red mueve gas en el mismo
  sentido entre las mismas salas; en 770, desde la misma capa alta.** No es un
  contraflujo distinto: es la misma componente de Bernoulli aplicada otra vez.
  Paso 403 (t = 33,6 s): el térmico empuja 21,8 g; la red lleva 1,5 g en ese
  sentido y **devuelve 21,5 g**: responde a la sobrepresión inyectada, no a un
  flujo propio.
- **Con los dos, la salida caliente se aplica dos veces** (24,8 + 5,8 = 30,6 kg
  frente a 21,0) y la red tiene que devolver el exceso (40,2 kg frente a 33,5).
- Mismo patrón con el fuego en la otra sala (24,47 kg térmicos en 800 pasos;
  +208,6 g de CO₂ sin ruta) y por el hueco vertical (237,2 kg y 10 812 kJ
  térmicos en 1 118 pasos, siempre en el mismo sentido que la red; +2 017 g de
  CO₂ y +195 g de humo sin ruta).
- **Cada transferencia del térmico es simétrica** (asimetría 0 en masa y en
  energía): por eso la suma del edificio no lo detectaba.

**Qué es de quién.** Masa, entalpía y especies por las aberturas: **la red**,
que ya lleva todas las magnitudes del térmico más el O₂. Calor sin gas
—radiación por aberturas, conducción por paredes, puente de escalera— y los
intercambios de fondo, que F2.2C ya aparta con la red: **ThermalSystem**, sin
cambios.

### 7.3 Segundo defecto que destapó el balance por sala

En el control «solo red», la sala fría ganó **1,4385 kg en un paso** sin ruta:
`_step_radiation_openings` siembra la capa alta vacía del receptor con
`superficie × 0,08 m × ρ` (`Thermal:1646`), sin donante. Fuera de la red la
proyección lo reconcilia; con la red nada lo hace. En la corrida por defecto no
se veía porque el transporte duplicado formaba antes la capa. Quitar el
duplicado sin corregir esto habría creado masa.

### 7.4 Cambio (solo con `authoritative_transport_enabled`)

1. En el bucle de aberturas interiores de `ThermalSystem.step()`, tras los
   intercambios de calor, `continue` antes del contraflujo térmico, la salida
   de la capa caliente con sus especies y la puerta canónica.
2. En la siembra por radiación, la capa mínima sale de la capa baja de la misma
   sala (`_ensure_minimal_upper_gas`, que usa `transfer_lower_to_upper`).

### 7.5 Resultados

| comprobación | antes | después |
|---|---|---|
| OFF, cuatro fixtures del arnés y dos trazas E1 | — | **idénticas byte a byte** (`cmp`) |
| OFF, huella IEEE754 del estado (validador O4) | `4f375edf…`, 142 eventos térmicos | igual, 142 eventos |
| ON, eventos de gas del térmico por aberturas interiores | 808 / 800 / 1 118 | **0** en los cuatro controles |
| ON, residuo de masa por sala y paso | hasta 1,44 kg (siembra) | **≤ 1,8·10⁻¹³ kg** |
| ON, masa del edificio | constante salvo la siembra | constante |
| ON, especies en la sala fría sin ruta de la red | +199,7 g CO₂ | −1,9 g CO₂ (0,25 %) |
| ON, siembra por radiación | +1,4385 kg creados | 1,4385 kg **tomados de la capa baja**, residuo −3·10⁻¹⁴ |
| Casa del producto, puerta abierta, red ON | 64,59 kg por el térmico | transporte entre salas solo en `gas_exchange`; edificio 201,600000 kg |

El 0,25 % de especies que queda probablemente sea la renovación ACH del bucle de
sala, un sumidero exterior fuera de la red. **No se ha verificado**, y no es P3.

**Limitación que queda, no introducida aquí:** sin capa alta en el receptor, la
red deposita el gas caliente en su capa **baja**, porque la capa de destino es
la del receptor a la altura de la banda. Ya estaba documentada como enrutado por
flotabilidad (F3.3F/H). Es el siguiente prerrequisito físico de la red, no un
problema de propiedad.

### 7.6 Pruebas

- `tools/validate_single_interior_transport_owner.gd`, 20 comprobaciones (O1
  puerta abierta, O2 hueco vertical, O3 puerta cerrada, O4 ruta OFF con huella,
  O5 siembra, O6 red, D1, D2, D3 y R3 apagados en `preset_simple_house`),
  registrado en `check_product.py`, y
  `tests/test_single_interior_transport_owner.py`.
- Contra el `ThermalSystem` de HEAD falla O1, O2 y O5. **M1** (guarda del bucle
  quitada) falla O1/O2 con 287 y 158 eventos; **M2** (guarda de la siembra
  quitada) falla O5 con +1,536 kg. Tras cada mutación se restauró el fichero y
  se verificó su SHA-256.
- Las tres listas de ficheros que pueden nombrar el interruptor de la red
  incluyen los dos nuevos.

### 7.7 O₂: sigue separado

Casa del producto, puerta abierta, red ON, **con** el arreglo: masa exacta, pero
el O₂ en kg pierde **5,82 kg** sin propietario, y `_all` (14,70 kg) es
exactamente el doble del consumo primario (7,35 kg). Ha desaparecido uno de los
candidatos de §3.5 —los 64,6 kg del térmico— y el residuo sigue, así que O2-4
queda como candidato principal. **No está aislado** y no se ha tocado:
`fire_o2_canonical_enabled` sigue apagado y el contrato de combustión no ha
cambiado.

---

## 8. P3b — especies en la siembra radiativa y el 0,25 % sin atribuir

### 8.1 Qué hace la siembra y qué la sigue

Con la red ON, `_step_radiation_openings` siembra la capa alta vacía del
receptor con `_ensure_minimal_upper_gas`, y este llama a
`ZoneFireSolver.transfer_lower_to_upper(room, m, T_amb)`. Esa primitiva mueve
**solo masa y entalpía** (`lower_gas_kg -= m`, `upper_gas_kg += m` y la energía
específica de la capa baja); no toca ninguna especie. Después, en el mismo
bucle, `sync_room_upper_layer` → `_sync_room_two_zone_layer` proyecta la
geometría, recorta `x_upper_kg ≤ x_kg`, colapsa la capa si la sala queda
quiescente (toda la masa baja y `co/co2/hcn_upper_kg = 0`, conservativo) y,
**solo con el fuego extinguido**, redistribuye especies de alta a baja por
fracción geométrica.

Representación de especies que usa la red (`build_snapshot`): CO, CO₂ y HCN por
capa (total más parte alta); O₂ como fracción por capa con la convención
masa-fracción `x · m`; humo, HCl, acroleína y formaldehído solo como total de
sala. **Ninguna es todavía un inventario autoritativo por capa.**

### 8.2 Defecto demostrado (reproducción aislada, red ON)

Estado real de la casa P3 justo antes de la siembra (Pasillo, paso 1121;
Salón, paso 1122); se llama **solo** a `_step_radiation_openings`:

| Pasillo | antes | después (P3) | después (P3b) |
|---|---:|---:|---:|
| masa alta / baja (kg) | 0 / 50,179360 | 1,438395 / 48,740965 | igual |
| energía alta / baja (kJ) | 0 / 998,179 | 28,685 / 969,566 | igual |
| CO₂ alta / baja (g) | 0 / 214,358 | **0 / 214,358** | 6,1446 / 208,2135 |
| CO alta (g) | 0 | **0** | 0,0293 |
| HCN alta (g) | 0 | **0** | 0,0029 |
| fracción de O₂ alta | 0,0 (rancia) | **0,0** | 0,205140 |
| O₂ `x · m` de la sala (kg) | 10,293796 | **−0,295072** | ±0 |

- **Masa y entalpía viajan juntas**: la sala conserva la masa (−7·10⁻¹⁵ kg) y
  gana exactamente los 0,0723 kJ que irradia el Salón; la capa alta recibe la
  entalpía específica de la baja (19,89 kJ/kg).
- **Las especies y el O₂ no viajaban.** Los 1,438 kg de gas subían sin su CO₂,
  su CO ni su HCN: estos quedaban asignados a la capa baja, que se
  concentraba, mientras la alta nacía limpia. La capa alta nacía además con la
  fracción de O₂ rancia (0,0), así que en la convención de la red —que
  reconstruye sus kg de O₂ como `x · m` en cada paso— la sala **perdía
  0,295 kg de O₂** en un solo paso. Es un defecto de representación, no de un
  inventario autoritativo, que no existe.
- **Control sin radiación:** el mismo estado no cambia nada.

En la corrida completa, el libro por capa de la sala fría (red por capa, ACH
por capa, paquete de siembra) cerraba con **−6,1448 g** de CO₂ en la capa alta
y **+6,1448 g** en la baja en el paso de la siembra, y el O₂ `x · m` de la sala
tenía −0,397 kg sin propietario.

### 8.3 Corrección local (red ON)

`_seed_upper_layer_as_one_packet()`, llamado desde la siembra radiativa solo con
`authoritative_transport_enabled`: tras `_ensure_minimal_upper_gas`, mide lo que
**de verdad** donó la capa baja y mueve en la misma operación la parte
proporcional de CO, CO₂ y HCN de la capa baja y su fracción de O₂, con la regla
con la que la red arma sus paquetes (`_bundle_for_source`). Los totales de sala
no cambian; la composición de la capa baja tampoco; humo, HCl, acroleína y
formaldehído, que solo existen como total de sala, no se tocan. `room.co2_upper`
(el trazador molar de CO₂, representación aparte) no se modifica.

Resultado en la corrida completa (puerta abierta e inversión): libro por capa de
CO₂ en la sala fría cerrado a **≤ 1·10⁻¹⁵ kg por paso**, con propietario para
cada cambio: red (capa baja), ACH (las dos capas), paquete de siembra. O₂ `x · m`
de la sala fría: resto +0,0013 kg (antes −0,397 kg). Hueco vertical y puerta
cerrada: sin siembra y resto 0.

**Pendiente, anterior a P3 y fuera de este cierre:** la misma primitiva sin
especies la usan la siembra por conducción de paredes (`:1778`, `:1828`), el
arrastre del penacho (`:2748`) y el puente de escalera (`:3797`), **también con
la red OFF**. Corregirlos cambia la ruta OFF; necesita su propia fase y
regeneración.

### 8.4 El 0,25 % de especies sin ruta de la red: ACH, medido

En la sala fría, el residuo `Δespecie − red` coincide paso a paso con la
renovación ACH de `GasExchangeSystem.step_smoke` (`especie × 0,5/3600 × dt`):

| especie | residuo acumulado | ACH predicho | diferencia | peor por paso |
|---|---:|---:|---:|---:|
| CO₂ | −1,8975 g | −1,8975 g | 8·10⁻¹³ g | 1·10⁻¹⁵ kg |
| CO | −0,0091 g | −0,0091 g | 6·10⁻¹⁶ g | 1·10⁻¹⁷ kg |
| HCN | −0,0009 g | −0,0009 g | 6·10⁻¹⁶ g | 1·10⁻¹⁸ kg |
| humo | −0,2141 g | −0,2141 g | 2·10⁻¹⁴ g | 1·10⁻¹⁶ kg |

Controles dinámicos: con `ach_infiltration = 0` (solo en el arnés) el residuo es
**exactamente 0** en todos los pasos; sin radiación sigue siendo exactamente el
de ACH; proyecciones y clamps no aportan nada. **Causa exacta: la renovación
ACH**, un intercambio con el exterior que tiene propietario, que retira de las
dos capas en proporción y que corre fuera de la red. No es un defecto de P3.
Queda anotado para la envolvente de la red (R3): cuando R3 esté encendida, ACH
y la envolvente serán dos canales exteriores a la vez.

### 8.5 R2-1: el hueco de `sim/BuildingModel.gd`

`CaseRunner` construye cada caso con `BuildingModel.load_template_data()`, pero
el fichero vive en la raíz de `sim/` y R2-1 no lo vigilaba: un cambio ahí movía
la validación con R2-1 en verde. Se añade a `_ENGINE_PATHS` en el mismo cierre,
con tres pruebas en `tests/test_guardrails.py`. `sim/ScenarioValues.gd` (editor
y vistas) y `sim/FireModel.gd` (sin referencias) quedan fuera con motivo.

### 8.6 Pruebas

- Validador ampliado a **61 comprobaciones**: O5b (paquete exacto: especies,
  O₂, entalpía), O7 (control sin radiación) y O6 en los cinco escenarios G0.
- **M3** (la siembra vuelve a mover gas sin especies) falla O5b en CO, CO₂,
  HCN, fracción de O₂ y O₂ de sala (−0,295 kg); M1 y M2 siguen fallando. Tras
  cada mutación se restauró el fichero y se verificó su SHA-256.
- OFF idéntico byte a byte: cuatro fixtures del arnés, dos trazas E1 y la
  huella `4f375edf…` del validador.

### 8.7 Referencia regenerada una vez (R2-1)

Tras cerrar las pruebas focalizadas, con 7,19 GB libres y ningún otro Godot, se
ejecutó `sim/validation/run_reference_checks.ps1` **una sola vez**, bajo un
monitor que cortaba el árbol de procesos por debajo de 5 GB o ante un fallo
nativo: 18 casos en 2 625 s, memoria mínima 5,66 GB, sin cortes ni fallos
nativos, `Resultado final: PASS`.

- **346/346 requeridos PASS y 78 huecos conocidos**, los mismos recuentos que la
  referencia del 23-09.
- `reference_checks.json` solo cambia en `generated_at`: **todas las métricas
  son idénticas**. Es lo esperable, porque P3 y P3b solo actúan con la red
  encendida y los casos de referencia corren con ella apagada; los cambios de
  G4/G5 en `BuildingTemplate.gd` y `BuildingModel.gd` no alcanzan a los casos.
- Guardarraíles 8/8 con R2-1 en verde **por esta regeneración, sin commit**:
  R2-1 ve el informe regenerado junto a los cambios de motor. En cuanto se
  commitee, informe y motor deben ir en el mismo commit o R2-1 volverá a rojo.
