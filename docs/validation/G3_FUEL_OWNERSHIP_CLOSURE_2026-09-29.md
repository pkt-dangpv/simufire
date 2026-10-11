# G3-1 — Cierre del diagnóstico de propiedad del combustible (2026-09-29)

Estado: **diagnóstico G3-1 cerrado; defectos de propiedad demostrados en el
motor; ninguna migración autorizada**. No se han modificado `sim/core`,
`sim/fire`, el catálogo, los escenarios distribuidos ni los interruptores.
G3-2 sigue **NO-GO** para `Y_CO(t)` por objeto ([informe del 29-09](G3_CO_FUENTES_ELEGIBILIDAD_2026-09-29.md)):
aquí no se usa `HRR/HOC` como masa perdida medida ni se mezclan datos NIST
de 2025 y 2026.

> **Actualización 2026-09-29.** El libro contable G3-3 y la corrección de
> energía y potencia en `explicit_objects` (OFF por defecto) están en
> [G3-3 y propiedad energética](G3_FUEL_LEDGER_OWNERSHIP_2026-09-29.md). Esta
> nota conserva el diagnóstico previo; ninguna de sus 23 + 7 decisiones cambia.

Entregables:

- [Matriz de decisión (23 + 7)](G3_FUEL_OWNERSHIP_CLOSURE_MATRIX_2026-09-29.json),
  regenerable con `python scripts/simulation/build_g3_fuel_ownership_matrix.py`.
- [Resumen dinámico de 9 casos](G3_FUEL_OWNERSHIP_DYNAMIC_CLOSURE_2026-09-29.json),
  de la tanda `runs/g3_fuel_ownership_matrix_20260929_085916/` (ignorada por
  Git), con `scripts/simulation/run_g3_fuel_ownership_matrix.py`.
- Analizador puro `scripts/simulation/analyze_g3_fuel_ownership.py` y
  pruebas `tests/test_g3_fuel_ownership_closure.py`.

## 1. Quién es hoy el propietario en el motor

Lectura de `sim/fire/CombustionSystem.gd`, confirmada por la tanda dinámica:

| Magnitud | Propietario efectivo |
| --- | --- |
| Tope de energía del fuego de sala | `room.fuel_energy_MJ` si es positivo; si es 0, **la suma del combustible restante de todos los objetos, ardan o no** (`_resolve_room_fuel_energy_MJ`). |
| Tope de HRR | `room.max_hrr_kw` si es positivo; si no, **la suma de `max_hrr_kw` de todos los objetos** (`_resolve_room_max_hrr_kw`). |
| Objetos explícitos | Seguidores: reciben cuotas de la demanda del fuego de sala (`_sync_explicit_objects_from_active_fire`); su HRR es una cuota del de sala. |
| Rendimientos CO/humo/hollín | Media ponderada de los objetos que conservan combustible, **ardan o no**, por `max_hrr_kw`, precalentamiento y estado; sin objetos con combustible, valor global del motor. |
| `room_proxy_<id>` | Refleja el fuego y se excluye de las sumas cuando hay objetos explícitos; en salas sin objetos es el único portador. |

## 2. Casos mínimos reproducidos (90 s, un Godot cada vez)

Tanda `g3_fuel_ownership_matrix_20260929_085916`: 9 casos con exit 0, sin
timeout, sin cuadros de error, sin Godot residual y `process_quiescent =
true`; 7,6–7,7 GiB libres antes de cada caso (umbral 6 GiB); última fila
CSV a 90,1 s. Los casos sintéticos comparten geometría, ignición,
ventilación y ajustes con G3-0; sus MJ son estímulos, no datos de muebles.

| Caso | Sala MJ | Objetos | Consumo fuego MJ | Quemado por objetos MJ | Sin dueño MJ | HRR máx kW | CO generado kg | Humo kg |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Sala vacía | 0 | — | 0 | 0 | 0 | 0 | 0 | 0 |
| Objeto único | 0 | sofá 3 MJ/100 kW | 2,999863 | 3,000000 | 0,000829 | 87,72 | 0,00084871 | 0,051679 |
| Dos objetos que arden | 0 | sofás 3 + 3 MJ, 50 kW cada uno | 5,738884 | 5,739845 | 0 | 102,59 | 0,01047424 | 0,061189 |
| Segundo objeto frío | 0 | sofá 3 MJ + silla 3 MJ que no prende | **5,996351** | 3,000000 | **2,985806** | **168,30** | **0,01192463** | 0,073464 |
| Objeto agotado con residuo de sala | 3 | sofá 1 MJ | 2,999863 | 1,000000 | **1,998060** | 87,72 | 0,00060710 | 0,041614 |
| Sala por debajo de objetos | 1 | sofá 3 MJ | 1,000000 | 0,999981 | 0 | 41,62 | 0,00022646 | 0,021173 |
| Agregado explícito de sala | 3 | — | 2,999863 | — | (dueño: proxy) | 87,72 | 0,00053081 | 0,038406 |
| Real ambiguo: salón de `compact_apartment_reference` | 4300 | 4 objetos, 2620 MJ | 11,915859 | 11,915857 | 0 | 320,27 | 0,00296878 | 0,129901 |
| Mismo, rendimientos de los 3 secundarios igualados al sofá | 4300 | idem | 11,915681 | 11,915679 | 0 | 320,27 | 0,00339804 | 0,143077 |

«Sin dueño» = MJ consumidos en pasos en los que ningún objeto explícito
quema, habiendo objetos declarados.

## 3. Qué queda demostrado

1. **No hay doble conteo de potencia ni de energía por paso** entre objetos
   y sala: la suma de HRR de objetos nunca supera el HRR de sala y el
   quemado explícito solo supera al consumo de sala en 1,37e-4 MJ (objeto
   único) y 9,6e-4 MJ (dos objetos), desincronía de 0,005–0,017 %.
2. **Combustible sin propietario.** Con sala 3 MJ y sofá 1 MJ, el sofá se
   agota a 39,08 s y el fuego sigue consumiendo 1,998060 MJ sin objeto; en
   esos pasos se genera el 66,5 % del CO y el 71,1 % del humo, con el
   rendimiento global del motor.
3. **Objeto inactivo que aporta energía, potencia y especies.** Sin carga
   de sala, la silla que nunca prende (estado final `heating`, 3,0 MJ
   intactos) entra en los topes del fuego: el HRR llega a 168,30 kW (346
   pasos por encima de los 100 kW del sofá) y, tras agotarse el sofá a
   56,25 s, el fuego consume 2,985806 MJ sin dueño. Quemado más remanente
   excede el inventario inicial en **2,996351 MJ**: los mismos MJ constan
   como quemados y como presentes en la silla (**doble conteo de
   inventario**). El CO generado es 14,05 veces el del objeto único y el
   82 % sale de pasos sin dueño; el humo, 1,42 veces.
4. **La carga de sala limita el inventario explícito.** Con sala 1 MJ y
   sofá 3 MJ, el fuego se detiene a 51,33 s y el sofá queda con 2,000019 MJ
   en estado `decaying`.
5. **El tope de HRR por objeto no se respeta.** En «dos objetos», el sofá B
   declara 50 kW y llega a 87,00 kW al agotarse el A: los objetos reciben
   cuotas del HRR de sala, no un tope propio.
6. **Caso real.** En 90 s ardieron los cuatro objetos del salón y no hubo
   MJ sin dueño: la ambigüedad de 1680 MJ del salón (4300 frente a 2620)
   **no se ejercita** hasta consumir los 2620 MJ de los objetos. Igualar los
   rendimientos de los tres objetos secundarios, que sí ardían, sube el CO
   un 14,46 % y el humo un 10,14 %; ponderar por energía quemada daría
   +10,70 %. Eso muestra que el peso de la media no es la energía quemada
   por cada objeto; no es una prueba de emisión de un objeto inactivo en el
   escenario distribuido.

El resultado 3 amplía el G3-0 (silla fría con sala reflejada de 200 MJ: CO
×2,92 por la media ponderada). Aquí, sin carga de sala, se suma además la
energía y la potencia de la silla al fuego.

## 4. Matriz de 23 discrepancias y 7 presets

Política escrita, sin inferir combustible por nombre o tipo de estancia:
`explicit_objects` solo con una fuente registrada que diga que los objetos
son el inventario completo; `legacy_lumped` cuando el agregado de sala es el
único combustible declarado; `legacy_unknown` cuando sala y objetos son
positivos y distintos sin significado registrado. Valores exactos, objetos,
hashes y camino de creación de cada caso en la [matriz JSON](G3_FUEL_OWNERSHIP_CLOSURE_MATRIX_2026-09-29.json).

| Grupo | Casos | Camino de creación | Evidencia | Clase | Decisión |
| --- | ---: | --- | --- | --- | --- |
| `compact_apartment_reference.json` salas 0–4 | 5 | literales del JSON, `b3457e94` (02-06-2026), sin generador | ninguna sobre la diferencia | `legacy_unknown` | bloquear por procedencia desconocida |
| `long_hallway_reference.json` salas 0–5 | 6 | idem | ninguna | `legacy_unknown` | bloquear |
| `two_storey_reference.json` salas 0, 2, 3, 5, 6, 7 | 6 | idem | ninguna | `legacy_unknown` | bloquear |
| `preset_two_storey_house.json` salas 0, 3, 8, 9, 10, 12 | 6 | `BuildingTemplate.create_two_storey_house()` → `create_product_preset` → `tools/export_presets_to_scenarios.gd` (`7f1a609f`); cargas y objetos aparecen juntos en `12d31cfb` (17-05-2026); **valores verificados contra los literales** | ninguna sobre la diferencia; plantilla usada por `cfast_two_floor_stairwell` y `two_storey_smoke` | `legacy_unknown` | bloquear |
| Presets sin objetos: `compact_apartment`, `piso_mediterraneo`, `ranch_family_house`, `row_house_ground_floor`, `three_bed_apartment`, `two_bed_apartment`, `uk_bungalow` | 7 | `BuildingTemplate.create_*()` vía `_make_room` → exportador; **valores verificados contra los literales** | solo `row_house` (cita EN 1991-1-2 con densidades por m², no cotejadas) y `uk_bungalow` (incrementos por moqueta, papel y madera, sin cálculo por sala) comentan su derivación | `legacy_lumped` | mantener como agregado explícito |

Resultado: **0 migrables**, 7 agregados explícitos a mantener y 23 casos
bloqueados. Ninguno de los 23 tiene una fuente que diga si el total de sala
incluye los objetos, contenido no dibujado, acabados o un límite prescrito.
Los 7 presets alimentan 11 casos de validación a través de su plantilla
(p. ej. `uk_bungalow_smoke`, `kitchen_grease_pool_fire`, `row_house_ground_floor_smoke`),
por lo que su agregado tampoco puede reescribirse sin cambiar referencias.

## 5. Contrato de propiedad propuesto (no implementado)

Cada sala declara un modo persistido: `explicit_objects`, `legacy_lumped` o
`legacy_unknown`.

- **MJ.** En `explicit_objects`, cada MJ consumido se debita de un solo
  objeto activo (en llama o pirólisis). El tope de energía y de HRR sale de
  los objetos **activos**, no de la sala ni de objetos fríos; cada objeto
  respeta su propio `max_hrr_kw` o su curva. Al agotarse los activos, el
  fuego se apaga salvo que prenda otro objeto o exista una fuente adicional
  **nombrada** (contenido, acabado) con MJ, material y procedencia. El total
  de sala es un derivado diagnóstico.
- **kg.** La masa perdida de un objeto solo existe si declara un calor
  efectivo con procedencia; si no, `kg = null`, no una conversión con un
  valor global. No se sustituye `MLR(t)` por `HRR/HOC` en régimen
  subventilado (G3-2).
- **Especies.** CO, CO₂, HCN y humo se generan por objeto con su energía
  quemada en ese paso; un objeto inactivo no aporta nada (G3-4).
- `legacy_lumped`: el proxy es el único propietario y no coexiste con
  objetos explícitos; salidas de CO/FED etiquetadas como no cuantitativas.
- `legacy_unknown`: comportamiento histórico idéntico byte a byte, etiquetado;
  sin CO por objeto ni FED cuantitativo.

Cláusulas comprobables (`contract_violations`, tolerancia relativa del 1 %
fijada antes de la tanda; la desincronía conocida es 0,005 %):

| Cláusula | Qué exige | Hoy |
| --- | --- | --- |
| C1 | sin doble conteo de HRR ni de energía por paso | cumple |
| C2 | todo MJ consumido tiene un objeto explícito dueño | **falla**: residuo de sala, silla fría |
| C3 | ninguna especie procede de energía sin dueño | **falla**: ídem |
| C4 | la sala vacía no crea combustible ni especies | cumple |
| C5 | la carga de sala no trunca el inventario explícito | **falla**: sala por debajo |
| C6 | un objeto inactivo no cambia CO ni humo | **falla**: silla fría |
| C7 | la energía de un objeto inactivo no se quema | **falla**: silla fría |
| C8 | quemado + remanente = inventario inicial (sin carga de sala) | **falla**: silla fría, +2,996 MJ |
| C9 | cada objeto respeta su `max_hrr_kw` | **falla**: dos objetos, silla fría |

Las pruebas fijan estas violaciones actuales en el resumen versionado: si el
motor cambia en cualquier sentido, la prueba falla y obliga a revisar la
tabla en lugar de aceptar el cambio en silencio. Además hay mutaciones
sintéticas para doble conteo, energía sin dueño, C8 y C9, una prueba de
deriva de la matriz y otra que detecta cambios en los literales de
`BuildingTemplate.gd`.

## 6. Parada antes de tocar el motor

Queda demostrado un defecto concreto: el fuego de sala usa como topes la
carga de sala o la suma de **todos** los objetos (incluidos los fríos) y
reparte la química por pesos que no son la energía quemada. Corregirlo
requiere:

1. un campo de modo persistido en escenario y editor, y la migración
   individual de cada sala;
2. un tope de energía y HRR derivado de los objetos activos, bajo un
   interruptor desactivado por defecto con identidad OFF byte a byte;
3. producción de especies por objeto (G3-4, bloqueada además por G3-2).

Referencias que podrían cambiar: las plantillas con objetos explícitos
alimentan 90 de los 101 casos de validación (`simple_house` 81,
`ghanekar_bedroom_hallway` 7, `two_storey_house` 2); cualquier cambio de
rendimientos o topes con objetos puede moverlos. Los 11 casos de plantillas
sin objetos solo cambiarían si se altera la ruta agregada. Nada de esto se ha
implementado; hace falta autorización explícita.

## 7. Decisión G3-1 → G3-3

- **GO** para instrumentar el libro contable pasivo G3-3 con esta
  clasificación y estas cláusulas como oráculo: el inventario de fuentes
  está completo y cada caso tiene clase, dueño y decisión.
- **NO-GO** para declarar cerrado G3-3, para migrar escenarios o para
  cualquier métrica cuantitativa de CO/FED por objeto: el gate de G3-3
  («mueble frío no emite ni altera la química; un solo propietario por MJ»)
  falla hoy en C2, C3, C5–C9. No se ha ajustado CO para compensarlo.
