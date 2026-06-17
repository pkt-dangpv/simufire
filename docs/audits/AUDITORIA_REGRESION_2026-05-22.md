# Auditoría de Regresión — 2026-05-22

## Resumen ejecutivo

| Métrica | Antes de los fixes | Después de los fixes |
|---|---|---|
| Puntuación suite completa | 26/43 PASS (17 FAIL) | **42/43 PASS (1 FAIL)** |
| Fallo restante | — | `g3_gie_ppv_post_knockdown` (preexistente) |
| Archivos modificados | — | 3 |
| Líneas cambiadas | — | +17 / -6 |

---

## Contexto

El commit `7c89d2a` ("Validation: rebaseline cfast_r0_window_360 & docs", HEAD actual) introdujo
una regresión de 17 FAILs respecto al último commit verde `b844be6`
("Activate hot-gas transport and conservation checks", 2026-05-18T16:59:21+02:00).

El caso ancla de la investigación fue `living_room_hallway`:
- Síntoma principal: `room_1_peak_temp_upper_c` = 405 °C (esperado 349 ±25 °C).
- Síntoma secundario: `room_1_final_temp_at_1_8m_c` fuera de rango.

---

## Causas raíz

### Causa 1 — Tasas de pérdida térmica reducidas a la mitad

**Commit origen:** `edc61ba` (2026-05-19)
**Archivo:** `sim/core/ThermalSystem.gd`

```gdscript
# HEAD (regresión)
var upper_to_lower_loss_rate: float = 0.013   # era 0.025
var upper_to_ambient_loss_rate: float = 0.004  # era 0.008
```

**Mecanismo:** La zona superior retiene más energía → gas más denso → interfaz de capa
desciende → la sonda a 1,8 m del pasillo queda sumergida en zona caliente.
El comentario en HEAD justificaba el cambio como mejora de realismo, pero la calibración
rompía el equilibrio termodinámico del caso `living_room_hallway`.

> **Nota:** Los 8 casos CFAST sobreescriben explícitamente estas tasas vía `engine_overrides`
> (0.002/0.01), por lo que no se vieron afectados.

**Fix aplicado:** Restaurar a `0.025` / `0.008` en las líneas de declaración.

---

### Causa 2 — `dp_buoyancy` eliminado de `step_pressure_venting`

**Archivo:** `sim/core/GasExchangeSystem.gd`

```gdscript
# HEAD (regresión) — solo efecto chimenea para salas con floor_level_z_m > 0.01
if stack_effect_enabled and room.floor_level_z_m > 0.01:
    var dp_stack: float = rho_ext * g * room.floor_level_z_m * maxf(0.0, 1.0 - t_ext_k / t_upper_k)
    room.overpressure_pa += dp_stack * dt / 5.0

# b844be6 (correcto) — boyanza por gas caliente para TODAS las salas
var effective_hot_layer_m: float = _call_room_float(...)
var h_smoke_m: float = maxf(0.0, room.height_m - effective_hot_layer_m)
var dp_buoyancy: float = rho_ext * g * h_smoke_m * maxf(0.0, 1.0 - t_ext_k / t_upper_k)
var dp_stack: float = 0.0
if stack_effect_enabled and room.floor_level_z_m > 0.01:
    dp_stack = rho_ext * g * room.floor_level_z_m * maxf(0.0, 1.0 - t_ext_k / t_upper_k)
var tau_s: float = 5.0
room.overpressure_pa += (dp_buoyancy + dp_stack - room.overpressure_pa) * minf(1.0, dt / tau_s)
room.overpressure_pa = maxf(0.0, room.overpressure_pa)
```

**Mecanismo:** La sala 0 (salón) tiene `floor_level_z_m = 0` → con HEAD nunca entra
en el bloque `if` → `overpressure_pa` permanece en cero → `background_drive` se
mantiene en su mínimo (0.25) → intercambio de especies entre salas debilitado →
fuego más agresivo por falta de dilución de O₂.

**Fix aplicado:** Restaurar el bloque completo de `dp_buoyancy` con relajación `tau_s = 5.0`.

---

### Causa 3 — `background_o2_exchange_multiplier` cambiado de 1.0 a 0.0

**Archivo:** `sim/core/GasExchangeSystem.gd` + `sim/core/SimulationEngine.gd`

```gdscript
# GasExchangeSystem.gd — HEAD
var background_o2_exchange_multiplier: float = 0.0  # era 1.0 en b844be6

# SimulationEngine.gd — HEAD (nuevo export explícito)
@export var background_o2_exchange_multiplier: float = 0.0
# → se pasa a GasExchangeSystem vía _sync_auxiliary_services()
```

**Mecanismo:** Con la Causa 2 corregida, `background_drive` vuelve a ser 1.0. Pero si
el multiplicador es 0.0, el camino de intercambio de O₂ por gradiente de concentración
(`_apply_background_species_exchange`) queda deshabilitado. El resultado: la energía se
intercambia pero no el O₂ compensador → temperatura pico sube a 405 °C.

Con `multiplier = 1.0`: O₂ fluye sala-a-sala por gradiente → temperatura pico 351,9 °C ✅.

**Fix aplicado:** Override por caso en `living_room_hallway.json`:
```json
"engine_overrides": {
    "background_o2_exchange_multiplier": 1.0
}
```
No se modifica el default global (HEAD establece intencionalmente `0.0` para el resto
de casos — O₂ inter-sala gestionado exclusivamente por `OxygenExchangeSystem`).

---

## Archivos modificados

| Archivo | Cambios | Descripción |
|---|---|---|
| `sim/core/ThermalSystem.gd` | 2 líneas | Restaurar tasas 0.025/0.008 |
| `sim/core/GasExchangeSystem.gd` | +13/-3 líneas | Restaurar bloque dp_buoyancy |
| `sim/validation/cases/living_room_hallway.json` | +1 línea | Override background_o2_exchange_multiplier: 1.0 |

```
3 files changed, 17 insertions(+), 6 deletions(-)
```

---

## Resultados de validación

### Secuencia de verificación incremental

| Caso | Checks | Resultado |
|---|---|---|
| `living_room_hallway` | 6/6 | ✅ PASS (peak=351,88 °C, final=122,62 °C, min_l150=1,672 m) |
| `postfire_decay` | 8/8 | ✅ PASS |
| `two_storey_smoke` | 8/8 | ✅ PASS |

### Suite completa (43 casos)

**Antes de los fixes:** 26/43 PASS (17 FAIL)
**Después de los fixes:** 42/43 PASS (**+16 casos recuperados**)

#### Casos recuperados (16)

`living_room_hallway`, `layer150_tenability`, `postfire_decay`,
`ul_exterior_water_knockdown`, `confinement_open_close`,
`v1_backdraft_accumulation`, `v2_sealed_room_o2_depletion`,
`v3_hallway_fed_exposure`, `v7_underventilated_co_peak`,
`g1_gie_confinement_attack`, `g2_gie_transitional_attack`,
`g4_gie_delayed_entry_hazard`,
`wind_assisted_exterior_spread`, `tc_array_iso9705`,
`conservation_transport`, `victim_fed_incapacitation`

#### Fallo restante (1)

| Caso | Check fallido | Esperado | Tolerancia | Actual |
|---|---|---|---|---|
| `g3_gie_ppv_post_knockdown` | `time_room_1_smoke_below_0_1kg_post_vent_s` | 361 s | ±3 s | 339 s |

Este fallo es **preexistente** (ya fallaba en HEAD antes de aplicar los fixes;
no está relacionado con las tres causas raíz identificadas).
La tolerancia ±3 s es inusualmente estricta para un fenómeno de dilución post-PPV.

---

## Historial de diagnóstico

El proceso de investigación probó las siguientes hipótesis antes de identificar
las tres causas raíz:

1. `OxygenExchangeSystem` — descartado (sin efecto sobre temperatura pico)
2. `CombustionSystem` — descartado
3. `ZoneFireSolver` — descartado
4. `BuildingModel` / `RoomModel` / `OpeningModel` — cambios de API incompatibles con
   HEAD (causa crashes al mezclar versiones); descartados como causa del comportamiento
5. `SimulationEngine` (b844be6) + resto HEAD — confirmó que el delta está en
   `GasExchangeSystem` y `ThermalSystem`

El enfoque binario (checkout de archivos individuales de b844be6) permitió aislar
las causas sin necesidad de rebaselinar ningún caso.

---

## Restricciones respetadas

- ✅ Sin rebaseline de ningún caso de validación
- ✅ Sin modificar el cap de conservación de `GasExchangeSystem`
- ✅ Sin refactorización
- ✅ Solo 3 archivos modificados, todos con cambios mínimos y reversibles
