# Prompt: hrr_kw residual en fuel objects tras extinción de sala

## Síntoma observado

Run del 2026-07-15 (escenario 6 salas, incendio en R0 Salón, extinción por agotamiento de O₂ hacia t≈700 s). Desde ese momento y hasta el final del run (t=1030 s):

- **Nivel sala (correcto):** `hrr_kw=0.00` y `burned_hrr_kw=0.00` en el CSV para R0, de forma sostenida. `pyrolysis_kw=0`, `HRRt=0`, `Burn=0`.
- **Nivel objeto (sospechoso):** el visor FP seguía mostrando una llama activa en R0 anclada a un mueble. El visor FP calcula la visibilidad de la llama como `max(hrr sala, burned_hrr sala, hrr de cada fuel_object del snapshot)` — como los dos primeros eran 0, algún objeto del snapshot reportaba `hrr_kw > 0`.
- Estado final de R0 en el TXT: `FuelH=7 | FuelP=0 | Obj=salon_sofa:heating | FuelT=64-68`. Siete objetos en heating, ninguno pirolizando, dominante el sofá. El TXT solo registra el objeto dominante, así que no se puede ver desde el log cuál retiene el hrr rancio ni en qué estado está.

**Mitigación ya aplicada en la vista** (commit `2e90fa0`, `view/fp/FirstPersonController.gd` + `view/3d/Visualizer3D.gd`): la llama FP solo cuenta el hrr de objetos en estado `flaming`/`decaying`, y el hrr de objetos en otros estados no puntúa para elegir el objeto ancla. **Esto NO cubre el caso de un objeto congelado en `decaying` con hrr rancio** — si el leak deja objetos en ese estado, la llama fantasma volverá. El arreglo real es del motor.

## Causa probable

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

## Qué hacer

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

## Restricciones

- Cambio localizado en `sim/fire/CombustionSystem.gd` (`_extinguish_room_fire` + test). No tocar el reparto de quemado ni el precalentamiento salvo que la confirmación del punto 1 revele que el leak está en otra ruta.
- Ojo con `_mark_legacy_proxy_burned_out` / `_sync_legacy_proxy_from_fire`: ya gestionan el proxy legacy dentro de la extinción; el loop nuevo no debe pisar lo que hacen con el proxy (saltar objetos `room_proxy_*` o ejecutar el loop antes de esas llamadas).
- Cuando esté arreglado en el motor, la mitigación de la vista (commit `2e90fa0`) puede quedarse — es coherente semánticamente (solo estados con llama alimentan el visual de llama) y sirve de defensa en profundidad.
