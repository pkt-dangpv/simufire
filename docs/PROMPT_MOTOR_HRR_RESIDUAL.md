# Prompt: hrr_kw residual en fuel objects tras extinción de sala

## Disposición final (2026-09-16)

**`FALSE_POSITIVE / NOT_REPRODUCIBLE_WITH_REGRESSION`** — cerrado.

- **No es `FIXED`.** No se ha cambiado la combustión: el motor en el que se
  midió (2026-09-15; `d8e24628` solo añade el guardarraíl) ya no dejaba potencia en los muebles
  de una sala apagada. El síntoma del 2026-07-15 no se reproduce con el motor
  actual.
- **Evidencia:** 4 plantillas examinadas, 3 extinciones reales por falta de O₂,
  0 objetos con `hrr_kw > 0` en una sala sin fuego (tabla abajo).
- **Regresión:** guardarraíl `tools/validate_extinction_object_hrr.gd`
  (commit `d8e24628`, registrado en `scripts/check_product.py`). 4/5
  mutaciones detectadas; la superviviente (quitar la puesta a cero del reparto
  de quemado) queda neutralizada en el mismo tick por la ruta pasiva, así que la
  invariante observable —ningún mueble con potencia en una sala apagada— se
  sigue cumpliendo y es lo que el guardarraíl protege.
- **Pirólisis previa a la ignición (SF-AUD-016):** en los casos con propiedades
  termoquímicas explícitas (`heat_of_gasification_kj_kg` y
  `heat_of_combustion_kj_kg`) un objeto en `PYROLYZING` puede tener
  `hrr_kw > 0` sin llama en la sala. Es **comportamiento modelado**, no una
  fuga de HRR posterior a la extinción.
- Las secciones **«Causa probable»**, **«Qué hacer»** y **«Restricciones»** de
  más abajo son el diagnóstico histórico del 2026-07-15 y quedan **superadas**:
  la hipótesis no se confirmó y el «arreglo real» en `_extinguish_room_fire`
  no es necesario. Se conservan como registro.

## Medición (2026-09-15)

> **Medido el 2026-09-15: no se reproduce con el motor actual.** Sonda headless
> (motor real, paso 0,5 s) que vuelca los objetos en el tick en que la sala se
> apaga y registra cualquier objeto con `hrr_kw > 0` en una sala sin fuego:
>
> | Plantilla | Variante | Extinción | Objetos al apagarse | Fugas |
> |---|---|---|---|---|
> | simple_house | tal cual / exteriores cerradas | t=503,5 s, O₂ 0,049 | 7 en `pyrolyzing`, hrr 0 | 0 |
> | two_storey_house | tal cual / exteriores cerradas | t=836 s, O₂ 0,027 | 3 en `pyrolyzing`, hrr 0 | 0 |
> | ghanekar_bedroom_hallway | exteriores cerradas | t=608,5 s, O₂ 0,119 | 2 en `pyrolyzing`, hrr 0 | 0 |
> | ghanekar_bedroom_hallway, piso_mediterraneo | resto | no se apaga en 900 s | — | 0 |
>
> Por qué: el reparto de quemado (`_sync_explicit_objects_from_active_fire`,
> rama sin `burn_MJ`) ya pone `hrr_kw = 0` y hace la cascada de estados en cada
> tick, y la ruta pasiva (`_update_passive_fuel_object`) recorre todos los
> objetos —también `FLAMING`/`DECAYING`— y deja `hrr_kw = 0`. El snapshot lee
> `obj.hrr_kw` directamente, sin otra fuente.
>
> Única vía que aún deja `hrr_kw > 0` sin fuego en la sala: la pirólisis previa
> a la ignición de SF-AUD-016 (hasta el 35 % de `max_hrr_kw` en `PYROLYZING`),
> que solo existe con `heat_of_gasification_kj_kg` y `heat_of_combustion_kj_kg`
> explícitos; hoy solo en los casos `char_layer_loi_wood` y
> `secondary_ignition_demo`, ninguna plantilla ni escenario del editor. Es
> modelo, no fuga, y la vista ya ignora estados sin llama (`2e90fa0`).
>
> **Guardarraíl** `tools/validate_extinction_object_hrr.gd` (en
> `check_product.py`, ~45 s): sala sintética apagada + un paso pasivo → todos
> los muebles a 0 kW y ninguno en llama/decayendo; el apagado no impide
> reencender; y `simple_house` real hasta la extinción por O₂ + 20 s sin un solo
> tick con potencia en sala apagada. **4/5 mutaciones muertas**: la ruta pasiva
> sin poner a cero, la ruta pasiva saltando muebles en llama, la extinción sin
> soltar el fuego y la reignición bloqueada. Sobrevive quitar la puesta a cero
> del reparto de quemado: la ruta pasiva corre en el mismo tick y lo tapa, así
> que la invariante se cumple; lo que protege la red es la invariante, no esa
> línea.

## Síntoma observado (histórico, 2026-07-15)

Run del 2026-07-15 (escenario 6 salas, incendio en R0 Salón, extinción por agotamiento de O₂ hacia t≈700 s). Desde ese momento y hasta el final del run (t=1030 s):

- **Nivel sala (correcto):** `hrr_kw=0.00` y `burned_hrr_kw=0.00` en el CSV para R0, de forma sostenida. `pyrolysis_kw=0`, `HRRt=0`, `Burn=0`.
- **Nivel objeto (sospechoso):** el visor FP seguía mostrando una llama activa en R0 anclada a un mueble (el log de julio no permite saber si la llama venía del motor de entonces o solo de la vista). El visor FP calcula la visibilidad de la llama como `max(hrr sala, burned_hrr sala, hrr de cada fuel_object del snapshot)` — como los dos primeros eran 0, algún objeto del snapshot reportaba `hrr_kw > 0`.
- Estado final de R0 en el TXT: `FuelH=7 | FuelP=0 | Obj=salon_sofa:heating | FuelT=64-68`. Siete objetos en heating, ninguno pirolizando, dominante el sofá. El TXT solo registra el objeto dominante, así que no se puede ver desde el log cuál retiene el hrr rancio ni en qué estado está.

**Mitigación ya aplicada en la vista** (commit `2e90fa0`, `view/fp/FirstPersonController.gd` + `view/3d/Visualizer3D.gd`): la llama FP solo cuenta el hrr de objetos en estado `flaming`/`decaying`, y el hrr de objetos en otros estados no puntúa para elegir el objeto ancla. **Esto NO cubre el caso de un objeto congelado en `decaying` con hrr rancio** — si el leak deja objetos en ese estado, la llama fantasma volverá. El arreglo real es del motor.

## Causa probable (SUPERADA 2026-09-16: no confirmada, ver «Disposición final»)

`CombustionSystem._extinguish_room_fire()` (línea ~1827) resetea exhaustivamente el estado de combustión **de la sala**:

```gdscript
room.hrr_kw = 0.0
room.hrr_target_kw = 0.0
room.pyrolysis_kw = 0.0
room.burned_hrr_kw = 0.0
room.unburned_generation_kw = 0.0
room.flame_hrr_target_kw = 0.0
...
room.fire = null
```

pero **no toca `room.fuel_objects`**. Los objetos conservan el `obj.hrr_kw` y el `obj.state` que tuvieran en el último tick de combustión activa.

Después de la extinción:
- La función de reparto de quemado sólido (la que asigna `obj.hrr_kw = actual_solid_burn_kw * burn_MJ / consumed_MJ`, línea ~2131) deja de ejecutarse para esa sala (no hay demanda de combustible), así que nadie vuelve a escribir esos campos.
- La ruta de precalentamiento (línea ~1236-1310) sí hace `obj.hrr_kw = 0.0` (línea 1309) para los objetos que procesa — por eso el sofá aparece como `heating` con hrr 0 y temperatura descendiendo. Pero si esa ruta no procesa objetos en `FLAMING`/`DECAYING` (o los salta por `_should_skip_object_for_room`), esos se quedan congelados con hrr > 0 indefinidamente.

Contraste: `_mark_room_ignition_object()` (línea ~1854) sí recorre todos los objetos haciendo `obj.hrr_kw = 0.0` al iniciar — el patrón existe, solo falta en la extinción.

## Qué hacer (SUPERADO 2026-09-16: el punto 1 se hizo y no reprodujo el leak; los puntos 2–3 no proceden; el 4 lo cubre el guardarraíl)

1. **Confirmar el leak.** Reproducir un run con extinción por O₂ (o usar un caso de validación existente con backdraft/ventilation-limited) y volcar `[obj.id, obj.state, obj.hrr_kw]` de todos los objetos de la sala tras `_extinguish_room_fire`. Identificar qué objetos retienen hrr > 0 y en qué estado quedan.

2. **Arreglo en `_extinguish_room_fire`.** Recorrer `room.fuel_objects` y para cada objeto (saltando los que filtre `_should_skip_object_for_room` si aplica):
   - `obj.hrr_kw = 0.0`
   - Transicionar el estado si quedó en llama: `FLAMING`/`DECAYING` → la misma cascada que ya se usa en las líneas ~2145-2150:
     - `remaining_fuel_MJ <= 0.001` → `BURNED_OUT`
     - `surface_temp_c >= ignition_temp_c - 45` → `PYROLYZING`
     - `surface_temp_c >= temp_lower_c + 35` → `HEATING`
     - else → `COLD` (o dejar el que la cascada decida)
   - No tocar `surface_temp_c`, `exposure_s`, `remaining_fuel_MJ` ni el resto: el precalentamiento posterior ya los gestiona (y permite reignición si vuelve el O₂, p. ej. backdraft).

3. **Considerar un cinturón de seguridad** (opcional pero barato): invariante al final del tick de combustión por sala — si la sala no tiene fuego activo (`room.fire == null` y `hrr_kw == 0`), ningún objeto debe reportar `hrr_kw > 0`. Puede ser un reset defensivo o un `push_warning` bajo flag de debug, según el apetito.

4. **Test.** Caso: sala con varios fuel objects, incendio que se extingue por O₂ (no por combustible). Asserts tras la extinción:
   - `all(obj.hrr_kw == 0.0 for obj in room.fuel_objects)`
   - Ningún objeto en estado `FLAMING`
   - Si hay backdraft posterior (reignición), los objetos pueden volver a arder con normalidad (el reset no rompe la reignición).

## Restricciones (SUPERADAS 2026-09-16: no hay cambio de motor que restringir)

- Cambio localizado en `sim/fire/CombustionSystem.gd` (`_extinguish_room_fire` + test). No tocar el reparto de quemado ni el precalentamiento salvo que la confirmación del punto 1 revele que el leak está en otra ruta.
- Ojo con `_mark_legacy_proxy_burned_out` / `_sync_legacy_proxy_from_fire`: ya gestionan el proxy legacy dentro de la extinción; el loop nuevo no debe pisar lo que hacen con el proxy (saltar objetos `room_proxy_*` o ejecutar el loop antes de esas llamadas).
- Cuando esté arreglado en el motor, la mitigación de la vista (commit `2e90fa0`) puede quedarse — es coherente semánticamente (solo estados con llama alimentan el visual de llama) y sirve de defensa en profundidad.
