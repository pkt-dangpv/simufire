# G3-1 — Procedencia declarativa de las 23 cargas discrepantes

> **Actualización 2026-09-29.** El [cierre G3-1](G3_FUEL_OWNERSHIP_CLOSURE_2026-09-29.md)
> verifica los seis casos del preset de dos plantas contra los literales de
> `BuildingTemplate.gd`, clasifica las 23 filas como `legacy_unknown` con
> decisión «bloquear por procedencia desconocida» y los 7 presets sin
> objetos como `legacy_lumped` («mantener como agregado explícito»).

Fecha: 2026-09-27. Estado: **ubicación de los números clasificada;
significado físico sin resolver**. Esta matriz no cambia ningún JSON ni
convierte la diferencia en combustible oculto. Se obtiene del
[inventario reproducible](G3_FUEL_SOURCE_OWNERSHIP_AUDIT_2026-09-27.md)
y se interpreta junto al [gate dinámico](G3_FUEL_OWNERSHIP_DYNAMIC_GATE_2026-09-27.md).

## Qué puede afirmarse sobre la procedencia

| Grupo | Salas | Dónde se declaran los números | Qué **no** consta |
| --- | ---: | --- | --- |
| `compact_apartment_reference.json` | 5 | Literales del JSON, añadidos en `b3457e94` (2026-06-02); no se encontró un generador ni cambios posteriores en ese archivo. | Si el total de estancia incluye los muebles dibujados, otros contenidos o acabados. |
| `long_hallway_reference.json` | 6 | Igual: literales del JSON añadidos en `b3457e94`, sin cambios posteriores. | La propiedad material de la diferencia. |
| `two_storey_reference.json` | 6 | Igual: literales del JSON añadidos en `b3457e94`, sin cambios posteriores. | La propiedad material de la diferencia. |
| `preset_two_storey_house.json` | 6 | Totales y muebles coinciden con las declaraciones de `BuildingTemplate.create_two_storey_house()` (`sim/templates/BuildingTemplate.gd`, salas 0/3/8/9/10/12); el preset se añadió en `7f1a609f` (2026-07-21). El cambio posterior `00428a6a` sólo alteró `player_start`. | La plantilla no dice que la diferencia sea contenido no dibujado ni si su total debe sustituir a los objetos. |

Los tres nombres `*_reference.json` **no** constituyen por sí mismos un
ensayo medido NIST, un caso CFAST prescrito ni una autorización para
reinterpretar el combustible. Ninguno de los cuatro JSON declara un campo
de modo, fuente material o procedencia para la diferencia. La convención
de `create_simple_house()` —carga total y objetos cuya suma coincide— no
prueba la intención de `create_two_storey_house()`, donde no coinciden.

## Matriz completa

`ΔMJ = MJ estancia − suma MJ objetos`; análogamente para `ΔkW`. Todas las
diferencias son positivas. Las cifras pertenecen a **escenarios distintos**:
su suma no es una carga de un edificio ni energía que necesariamente vaya
a quemarse. Todas las filas conservan clasificación física
`legacy_unknown` **propuesta para revisión**, no persistida en el motor.

| Escenario | Sala | Nombre | MJ estancia | MJ objetos | ΔMJ | kW estancia | kW objetos | ΔkW |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| compact_apartment_reference.json | 0 | Salon cocina | 4300 | 2620 | 1680 | 2500 | 1620 | 880 |
| compact_apartment_reference.json | 1 | Pasillo distribuidor | 520 | 350 | 170 | 350 | 210 | 140 |
| compact_apartment_reference.json | 2 | Dormitorio | 2600 | 1700 | 900 | 1600 | 880 | 720 |
| compact_apartment_reference.json | 3 | Bano | 300 | 120 | 180 | 250 | 90 | 160 |
| compact_apartment_reference.json | 4 | Terraza lavadero | 450 | 260 | 190 | 300 | 180 | 120 |
| long_hallway_reference.json | 0 | Salon origen | 5200 | 2330 | 2870 | 3000 | 1260 | 1740 |
| long_hallway_reference.json | 1 | Pasillo largo | 1100 | 960 | 140 | 700 | 530 | 170 |
| long_hallway_reference.json | 2 | Dormitorio norte | 2400 | 900 | 1500 | 1500 | 520 | 980 |
| long_hallway_reference.json | 3 | Dormitorio central | 2500 | 1080 | 1420 | 1600 | 680 | 920 |
| long_hallway_reference.json | 4 | Cocina fondo | 3300 | 1440 | 1860 | 2300 | 1220 | 1080 |
| long_hallway_reference.json | 5 | Recibidor | 650 | 240 | 410 | 380 | 160 | 220 |
| preset_two_storey_house.json | 0 | Salon-comedor PB | 8500 | 3220 | 5280 | 4300 | 1790 | 2510 |
| preset_two_storey_house.json | 3 | Cocina PB | 4800 | 1850 | 2950 | 3000 | 1450 | 1550 |
| preset_two_storey_house.json | 8 | Dormitorio principal P1 | 5400 | 2100 | 3300 | 2800 | 1060 | 1740 |
| preset_two_storey_house.json | 9 | Dormitorio 2 P1 | 3800 | 850 | 2950 | 2200 | 480 | 1720 |
| preset_two_storey_house.json | 10 | Dormitorio 3 P1 | 3400 | 760 | 2640 | 2000 | 430 | 1570 |
| preset_two_storey_house.json | 12 | Estudio P1 | 2400 | 520 | 1880 | 1400 | 260 | 1140 |
| two_storey_reference.json | 0 | Salon PB | 5200 | 2450 | 2750 | 3000 | 1250 | 1750 |
| two_storey_reference.json | 2 | Cocina PB | 3000 | 1280 | 1720 | 2200 | 770 | 1430 |
| two_storey_reference.json | 3 | Pasillo PB | 480 | 160 | 320 | 280 | 90 | 190 |
| two_storey_reference.json | 5 | Dormitorio P1 | 2700 | 1740 | 960 | 1700 | 900 | 800 |
| two_storey_reference.json | 6 | Dormitorio infantil P1 | 2400 | 1080 | 1320 | 1500 | 680 | 820 |
| two_storey_reference.json | 7 | Bano P1 | 320 | 130 | 190 | 240 | 90 | 150 |

Por grupo: `3 120`, `8 200`, `19 000` y `7 260 MJ` de diferencia,
respectivamente; total aritmético entre escenarios `37 580 MJ`. Son
**magnitudes de ambigüedad**, no combustible validado ni emisión de CO.

## Decisión que falta, sin reescribir datos

Para cada grupo o sala, identificar la intención original mediante una
fuente verificable: ¿el total de estancia es el inventario completo y los
objetos sólo una muestra visual, existe una fuente adicional concreta
(acabados, muebles no dibujados, almacenamiento), o el total heredado es
un límite de fuego prescrito para referencia? Si no puede determinarse,
conservar `legacy_unknown` y el comportamiento histórico para esa familia,
pero **no** presentar CO por mueble ni FED cuantitativo como validado. La
clasificación final exige una decisión de diseño con procedencia; esta
matriz sólo fija lo que el repositorio permite demostrar hoy.
