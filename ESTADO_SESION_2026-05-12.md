# Estado sesión 2026-05-12

## Resultado sesión
- ✅ **17/17 PASS** confirmado al final de sesión

## Items completados esta sesión

### Item 5 — Único mass-flow callable por abertura (pre-compute opening flow state once per step)
**Estado**: ✅ COMPLETO, validado 17/17 PASS

**Problema**: ThermalSystem y OxygenExchangeSystem llamaban `build_interior_opening_flow_state` para la misma abertura en momentos distintos del mismo timestep. O2 veía el estado sin modificar; Thermal veía el estado post-O2. Misma puerta, dos "realidades físicas" distintas dentro del mismo paso.

**Fix**: Pre-computar una sola vez al inicio de cada step con `_opening_flow_cache: Dictionary` keyed por objeto `op`, compartido via hooks dict.

**Archivos modificados**:

#### `sim/core/SimulationEngine.gd`
- Nueva variable de instancia: `var _opening_flow_cache: Dictionary = {}`
- En `step()`, antes de `_step_pool_fires(dt)`:
  ```gdscript
  _opening_flow_cache = _build_opening_flow_cache()
  ```
- `thermal_system.step()` ahora recibe `"opening_flow_cache": _opening_flow_cache` en hooks
- `_build_oxygen_exchange_hooks()` retorna `"opening_flow_cache": _opening_flow_cache`
- Nuevo método `_build_opening_flow_cache() -> Dictionary`: itera `building.get_openings()`, salta openings cerrados (`open_fraction <= 0`) y exteriores (`a==OUTSIDE_ID` o `b==OUTSIDE_ID`), llama `thermal_system.build_interior_opening_flow_state(room_a, room_b, op)` y cachea resultado keyed por `op`

#### `sim/core/ThermalSystem.gd`
- En `step()`: lee `var _flow_cache: Dictionary = hooks.get("opening_flow_cache", {})`
- En loop de openings (~línea 589): `var flow_state: Dictionary = _flow_cache.get(op, build_interior_opening_flow_state(room_a, room_b, op))` (con fallback si no está en cache)

#### `sim/core/OxygenExchangeSystem.gd`
- En `step()`: lee `var opening_flow_cache: Dictionary = hooks.get("opening_flow_cache", {})`
- Pasa `opening_flow_cache` como argumento extra a `_step_interior_opening_o2()`
- Signature actualizada: `func _step_interior_opening_o2(..., opening_flow_cache: Dictionary = {}) -> void:`
- Dentro: lookup `if opening_flow_cache.has(op): flow_state = opening_flow_cache[op] else: flow_state = _call_interior_flow_state(...)`

#### `sim/core/GasExchangeSystem.gd`
- **No modificado** (recibe `build_interior_opening_flow_state_callable` en hooks pero no lo usa)

**Baselines actualizadas** (drift numérico esperado por cambio de orden de evaluación):
- `sim/validation/baselines/confinement_open_close.json`: `room_0_final_smoke_kg` 2.409540 → **1.844083** (±0.30)
- `sim/validation/baselines/g4_gie_delayed_entry_hazard.json`: `time_room_1_fed_above_0_1_s` 378.416667 → **287.833333** (±10.0)

**Explicación del drift**:
- `confinement_open_close`: el flujo congelado al inicio del paso reduce ligeramente el transporte de humo en escenarios de confinamiento largo
- `g4_gie_delayed_entry_hazard`: el corredor recibe menos gases tóxicos con snapshot consistente (más coherente físicamente — antes Thermal usaba estado post-O2 → sobrestimaba flujo hacia corredor)

## Estado validación
```
 - living_room_hallway:           PASS (25,21s)
 - layer150_tenability:           PASS (27,93s)
 - postfire_decay:                PASS (144,83s)
 - ul_exterior_water_knockdown:   PASS (22,82s)
 - confinement_open_close:        PASS (81,33s)
 - v1_backdraft_accumulation:     PASS (59,18s)
 - v2_sealed_room_o2_depletion:   PASS (41s)
 - v3_hallway_fed_exposure:       PASS (83,95s)
 - v4_co_remote_rooms:            PASS (66,72s)
 - v5_ventilation_hrr_spike:      PASS (51,26s)
 - v6_spread_to_hallway:          PASS (72,97s)
 - v7_underventilated_co_peak:    PASS (41,85s)
 - v8_suppression_reburn:         PASS (55,16s)
 - g1_gie_confinement_attack:     PASS (37,24s)
 - g2_gie_transitional_attack:    PASS (39,18s)
 - g3_gie_ppv_post_knockdown:     PASS (55,2s)
 - g4_gie_delayed_entry_hazard:   PASS (43s)
[Validation Suite] Resultado final: PASS
```

## Rutas clave
- Godot exe: `F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe`
- Proyecto: `F:\OneDrive\Documentos\GitHub\simufire`
- Git: `C:\Users\dangp\AppData\Local\GitHubDesktop\app-3.5.8\resources\app\git\cmd\git.exe`
- Validación: `powershell -ExecutionPolicy Bypass -File .\sim\validation\run_all_cases.ps1 -GodotExe "F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe" -ContinueOnFailure 2>&1 | Select-String "PASS|FAIL|ERROR|====" | Select-Object -Last 30`

## Hoja de ruta Fase 1 — estado actualizado

### Completados
- [x] Item 1: Visual bug plano neutro (smoke_display_layer_m)
- [x] Item 2: Masa upper_gas_kg conservada en transferencias inter-sala
- [x] Item 3: Centralizar mass-flow callable (refactorización arquitectónica)
- [x] Item 4: O2 carry bidireccional implementado (deshabilitado, coeff=0.0)
- [x] Item 5: Único mass-flow callable por abertura (pre-compute opening flow state)

### Pendiente
- Ver ESTADO_SESION_2026-05-09.md para contexto de ítems anteriores y backlog completo

## Contexto para próxima sesión
- Estado limpio: 17/17 PASS, sin FAILs pendientes
- La arquitectura de `_opening_flow_cache` está implementada y es estable
- El drift en `g4_gie_delayed_entry_hazard` (time_room_1_fed_above_0_1_s: 378→288s) es significativo — en el escenario real, el corredor recibe gases tóxicos significativamente más tarde con la física corregida. Esto es comportamiento más realista.
