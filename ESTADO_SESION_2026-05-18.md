# Estado de Sesión — 2026-05-18

## Resultado de la sesión
✅ **R#6 — ZoneFireSolver Phase 1 COMPLETO**  
Suite: **40/40 PASS** (duracion total: 2517,58s)

---

## Roadmap — Estado actualizado

| # | Nombre | Estado |
|---|--------|--------|
| R#1 | Bernoulli default=true | ✅ COMPLETO |
| R#2 | Estratificación O₂/CO₂/HCN upper/lower | ✅ COMPLETO |
| R#3 | Conducción 1D Crank-Nicolson (PDE) | ✅ COMPLETO |
| R#4 | TargetModel masa térmica + sim_log_targets.csv | ✅ COMPLETO |
| R#5 | Energy conservation CI test | ✅ COMPLETO |
| R#6 | ZoneFireSolver Phase 1 — skeleton + registro | ✅ COMPLETO (esta sesión) |
| R#7 | Flujo vertical / multi-planta (chimney effect) | ✅ COMPLETO (sesión anterior) |

---

## R#6 — ZoneFireSolver Phase 1 — Detalle

### Objetivo
Crear la infraestructura base del coordinador de zona de incendio (`ZoneFireSolver`) para las fases 2 y 3 futuras. Phase 1 = esqueleto sin física activa.

### Archivos modificados / creados

#### `sim/core/ZoneFireSolver.gd` (NUEVO)
```gdscript
class_name ZoneFireSolver extends RefCounted
var zone_solver_phase: int = 1
var hot_gas_hcn_carry_fraction: float = 0.0
var hot_gas_irritant_carry_fraction: float = 0.0
var _building: BuildingModel = null
func set_building(b: BuildingModel) -> void: _building = b
static func get_resolved_upper_mass_kg(flow_state: Dictionary) -> float
static func get_resolved_hot_room_id(flow_state: Dictionary) -> int
func validate_conservation(...) -> Dictionary  # no-op en phase 1
```

#### `sim/core/ThermalSystem.gd`
- Añadido `var hot_gas_hcn_carry_fraction: float = 0.0` y `var hot_gas_irritant_carry_fraction: float = 0.0`
- HCN carry gateado: `if hot_gas_hcn_carry_fraction > 0.0:`
- HCL/acrolein/formaldehyde carry gateado: `if hot_gas_irritant_carry_fraction > 0.0:`
- **CO₂ tracking en `_transfer_hot_gas_contaminants`: CO₂_upper_kg eliminado completamente** (deferred a Phase 2+). Solo bulk `co2_kg` se transporta, sin split upper/lower.
- Zone_resolved write-back al `flow_state`:
  ```gdscript
  flow_state["zone_resolved_upper_mass_kg"] = gas_moved_kg
  flow_state["zone_resolved_hot_room_id"] = hot_room.id
  flow_state["zone_resolved_cold_room_id"] = cold_room.id
  ```

#### `sim/core/SimulationEngine.gd`
```gdscript
const ZoneFireSolverScript = preload("res://sim/core/ZoneFireSolver.gd")
var zone_fire_solver = ZoneFireSolverScript.new()
# en _sync_auxiliary_services():
zone_fire_solver.set_building(building)
```

### Bugs encontrados y resueltos

#### Bug 1 — Parse error `class_name` en modo headless
- **Síntoma**: `var zone_fire_solver: ZoneFireSolver = ZoneFireSolver.new()` → "Could not find type 'ZoneFireSolver'"
- **Fix**: usar `const ZoneFireSolverScript = preload("res://sim/core/ZoneFireSolver.gd")` + `var zone_fire_solver = ZoneFireSolverScript.new()`

#### Bug 2 (CRÍTICO) — v3_hallway_fed_exposure FAIL
- **Síntoma**: `time_room_1_fed_above_0_3_s = 313.9s` (expected 250.8±35, upper bound 285.8s)
- **Root cause**: `_transfer_hot_gas_contaminants` actualizaba `co2_upper_kg` en salas no-fuego (pasillo room_1). `compute_co2_lower_ppm()` computa `co2_lower_kg = co2_kg - co2_upper_kg`. Con `co2_upper_kg > 0` en pasillo → `co2_lower_kg` menor → `v_co2` (factor hiperventilación CO2) menor en FED formula → FED se acumula más lento → FAIL.
- **Fix correcto**: Eliminar TODO el tracking de `co2_upper_kg` en `_transfer_hot_gas_contaminants`. CO2 se sigue transportando en bulk (`co2_kg`), pero sin split upper/lower. Esto preserva exactamente el comportamiento pre-R6 para todos los casos que usan `compute_co2_lower_ppm`.
- **Verificación**: individual v3 PASS (exit 0, timestamp 084246), y 40/40 PASS en suite completa.

### Suite completa — resultados
```
living_room_hallway: PASS (36,14s)
layer150_tenability: PASS (41,47s)
postfire_decay: PASS (213,35s)
ul_exterior_water_knockdown: PASS (29,32s)
confinement_open_close: PASS (102,88s)
v1_backdraft_accumulation: PASS (73,61s)
v2_sealed_room_o2_depletion: PASS (50,27s)
v3_hallway_fed_exposure: PASS (103,21s)
v4_co_remote_rooms: PASS (80,04s)
v5_ventilation_hrr_spike: PASS (67,53s)
v6_spread_to_hallway: PASS (101,87s)
v7_underventilated_co_peak: PASS (47,5s)
v8_suppression_reburn: PASS (65,17s)
g1_gie_confinement_attack: PASS (46,12s)
g2_gie_transitional_attack: PASS (49,85s)
g3_gie_ppv_post_knockdown: PASS (66,15s)
g4_gie_delayed_entry_hazard: PASS (55,2s)
flashover_simple_house: PASS (31,01s)
glass_break_window_spike: PASS (23,69s)
pu_sofa_fec_incapacitation: PASS (83,61s)
pvc_curtain_hcl_release: PASS (63,36s)
compact_apartment_smoke: PASS (31,43s)
uk_bungalow_smoke: PASS (62,49s)
piso_mediterraneo_smoke: PASS (100,44s)
two_bed_apartment_smoke: PASS (63,71s)
three_bed_apartment_smoke: PASS (78,36s)
row_house_ground_floor_smoke: PASS (49,84s)
ranch_family_house_smoke: PASS (78,84s)
energy_budget_living_room: PASS (30,88s)
kitchen_grease_pool_fire: PASS (42,85s)
ranch_radiation_target_ignition: PASS (67,27s)
co_oxidation_post_flashover: PASS (50,46s)
hrr_tabulated_curve_sofa: PASS (60,3s)
char_layer_loi_wood: PASS (58,79s)
ppv_attack_pressurized: PASS (71,93s)
mediterraneo_concrete_wall_conduction: PASS (81,75s)
wind_assisted_exterior_spread: PASS (43,08s)
tc_array_iso9705: PASS (30,32s)
c_balance_high_phi: PASS (39,96s)
two_storey_smoke: PASS (43,56s)

Total: 40/40 PASS — 2517,58s
```

---

## Entorno técnico (referencia)

- **Godot**: `F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe` (headless)
- **Proyecto**: `F:\OneDrive\Documentos\GitHub\simufire`
- **Suite completa**: `sim/validation/run_all_cases.ps1 -GodotExe "..." -ContinueOnFailure`
- **Caso individual**: `sim/validation/run_case.ps1 -CaseName NAME -GodotExe "..."`
- **Preload pattern** (obligatorio en headless): `const XScript = preload("res://path/X.gd")`; nunca usar `class_name` como tipo en declaraciones de variables en SimulationEngine

---

## Próximos pasos sugeridos

1. **R#6 Phase 2** — ZoneFireSolver con física activa: coordinación de masa upper/lower real entre salas, CO₂ upper/lower tracking en transporte convectivo.
2. **R#6 Phase 3** — ZoneFireSolver con conservación: `validate_conservation()` activo, error budgets.
3. **HCN carry habilitado** (cuando se tengan baselines adecuados): subir `hot_gas_hcn_carry_fraction > 0.0` y recalibrar baselines.
