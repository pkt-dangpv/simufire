# Estado sesión 2026-05-14

## Resumen ejecutivo
- ✅ **17/17 PASS** (suite interna, confirmado en esta sesión)
- ✅ **28/28 PASS** (reference checks, desde sesión 2026-05-13 tras fix φ)
- ✅ **Fix log TXT** — log arrancaba desde t=340s en vez de t=0 (bug resuelto)
- ✅ **Nuevos parámetros ThermalSystem** — `outside_open_upper_heat_boost` y `outside_lower_fresh_air_cooling_rate`
- **Cambios pendientes de commit** (working tree sucio)

---

## Cambios de código en esta sesión (no comprometidos a git)

### `sim/core/SimulationEngine.gd`

**Fix log paths (bug: log empezaba en t=340s, no en t=0):**
- `log_file_path`: `res://sim_log.txt` → `user://sim_log.txt`
- `csv_log_file_path`: `res://sim_log.csv` → `user://sim_log.csv`
- Causa raíz: el editor Godot mantiene lock de archivo sobre `res://sim_log.txt` (reconocido como recurso del proyecto). En Windows, ese lock causaba fallos silenciosos de escritura desde t=0 hasta que se liberaba el lock. El CSV no tenía el problema porque `.csv` no es tipo reconocido por Godot.

**Fix Python graph generator (bug: Python usaba ruta stale de res://):**
- `_launch_graph_generator()`: ahora pasa `--log log_writer.resolve_log_file_path()` explícito
- Antes: `PackedStringArray([script_path, "--latest-file", latest_path, "--copy-log"])` → Python usaba su propio default `res://sim_log.txt`
- Después: `PackedStringArray([script_path, "--latest-file", latest_path, "--log", log_path, "--copy-log"])`

**Nuevos @export vars:**
```gdscript
@export var outside_open_upper_heat_boost: float = 0.0
@export var outside_lower_fresh_air_cooling_rate: float = 0.0
```

### `sim/core/ThermalSystem.gd`

**Nuevos parámetros:**
```gdscript
var outside_open_upper_heat_boost: float = 0.0
# Boost fracción convectiva cuando ventana exterior está abierta.
# conv_fraction_eff = conv_fraction * (1 + outside_open_upper_heat_boost * open_factor)
# Default 0.0 — activar en JSON del caso para calibrar vs CFAST/FDS.

var outside_lower_fresh_air_cooling_rate: float = 0.0
# Tasa de enfriamiento de zona inferior por ingreso de aire fresco exterior.
# Solo actúa cuando outside_open_factor > 0.
# Default 0.0 — activar en JSON del caso para calibrar vs CFAST/FDS.
```

**Comportamiento:**
- Cuando `outside_open_factor > 0` y `outside_open_upper_heat_boost > 0`: aumenta `conv_fraction` del upper heat
- `outside_open_lower_warming_rate` ahora puede ser negativo: `lower_transfer_rate = maxf(0.0, lower_transfer_rate + outside_open_lower_warming_rate * outside_open_factor)`
- Enfriamiento lower: `room.temp_lower_c -= (room.temp_lower_c - ambient_c) * outside_lower_fresh_air_cooling_rate * outside_open_factor * dt`

### `view/Visualizer.gd`, `view/Visualizer3D.gd`
Modificados (cambios UI, no afectan física de simulación).

### Archivos eliminados
- `view/FirstPersonController.gd` — eliminado
- `view/FirstPersonController.gd.uid` — eliminado
- `view/RoomFireSmokeVisual.tscn` — eliminado

### Otros cambios (UI/escenas, no afectan física)
- `Main.gd`, `main.tscn`, `scenes/SimulationScene.tscn`
- `ui/hud.gd`, `ui/SimuFireTheme.gd`
- `sim/validation/cases/cfast_r0_window_360.json`
- `sim/validation/reports/cfast_r0_window_360.json`
- Traducciones `sim_log.*.translation` (todas)

---

## Estado AUDIT_REPORT.md (al 2026-05-14)

Última actualización del archivo: **2026-05-13** (sesión anterior, fix φ)

### Hallazgos resueltos o corregidos

| ID | Severidad | Estado | Descripción |
|---|---|---|---|
| SF-AUD-001 | Media | ✅ Corregido | Documentación separada de dos carriles de validación |
| SF-AUD-002 | Baja | ✅ Verde | Temperatura superior CFAST pasa en reference_checks |
| SF-AUD-003 | Baja | ✅ Verde | Altura de capa CFAST pasa en reference_checks |
| SF-AUD-005 | Alta (era Crítica) | ⚠️ Parcial | φ CO implementado; CO2/HCN/soot sin balance elemental |
| SF-AUD-007 | Media (era Alta) | ✅ Corregido | CO superior CFAST pasa con φ fix; 28/28 PASS |

### Hallazgos abiertos (15 activos)

| ID | Severidad | Descripción |
|---|---|---|
| SF-AUD-004 | Alta | HRR sin curvas experimentales por combustible/item |
| SF-AUD-006 | **Crítica** | HCN yield genérico; no depende de N del material |
| SF-AUD-008 | Alta | Soot/humo no separados; K=8700 aplicado a smoke_kg total |
| SF-AUD-009 | **Crítica** | No modelo two-zone completo conservativo (estratificación heurística) |
| SF-AUD-010 | Alta | Flujos por aberturas sin Bernoulli por capas (fracciones fijas) |
| SF-AUD-011 | Alta | Rotura de vidrio solo por temperatura; sin flux/gradiente/tipo/presión |
| SF-AUD-012 | **Crítica** | Flashover sin criterio de heat flux al suelo (~20 kW/m²) |
| SF-AUD-013 | **Crítica** | Backdraft sin LFL/UFL/mezcla/deflagración; solo energía+O2+T |
| SF-AUD-014 | Alta | Sin conducción 1D por material; paredes con capacidad global |
| SF-AUD-015 | Alta | Radiación con view factors simplificados; sin geometría de llama |
| SF-AUD-016 | Alta | Sin cinética de pirólisis ni MLR; ignición por umbral T/flux |
| SF-AUD-017 | **Crítica** | Supresión sin vapor, gotas, momentum, steam visibility |
| SF-AUD-018 | Alta | FEC irritantes (HCl/acroleína) ausente; sin sondas a altura fija |
| SF-AUD-019 | Alta | Independencia del timestep no validada; clamps dt-dependientes |
| SF-AUD-020 | Media | Overrides de escenario no clasificados como físicos/empíricos |

### Nuevo fallo NO registrado en AUDIT_REPORT.md
- **Bug log TXT t=0**: Resuelto en esta sesión (paths a `user://`). Debería añadirse como SF-AUD-021 o nota de corrección en AUDIT_REPORT.md.

---

## Estado validación (2026-05-14)

```
living_room_hallway:           PASS (33,94s)
layer150_tenability:           PASS (41,16s)
postfire_decay:                PASS (162,41s)
ul_exterior_water_knockdown:   PASS (25,8s)
confinement_open_close:        PASS (88,03s)
v1_backdraft_accumulation:     PASS (63,45s)
v2_sealed_room_o2_depletion:   PASS (43,53s)
v3_hallway_fed_exposure:       PASS (97,5s)
v4_co_remote_rooms:            PASS (71,23s)
v5_ventilation_hrr_spike:      PASS (55,73s)
v6_spread_to_hallway:          PASS (80,92s)
v7_underventilated_co_peak:    PASS (42,05s)
v8_suppression_reburn:         PASS (55,17s)
g1_gie_confinement_attack:     PASS (36,67s)
g2_gie_transitional_attack:    PASS (38,81s)
g3_gie_ppv_post_knockdown:     PASS (55,35s)
g4_gie_delayed_entry_hazard:   PASS (42,78s)
Resultado final: PASS — 17/17
```

---

## Historial de commits recientes (git log --oneline)

```
46b7cd1 (HEAD) Fix combustion φ; update scenarios & UI
cbcb18e Add first-person assets and object types
f64264f Editor UI theme, corridor tool & gas fix
69b14bb Add audit report and update validation
c31beeb Revert O2 carry; add/update validation baselines
75fee69 Add O₂ guard and natural vent inlet param
41e5763 First-person view, HVAC UI and validation
de9e059 Update FDS/SIMUFIRE data and simulation code
```

---

## Próximos pasos recomendados (por prioridad)

### Inmediato
1. **Commit los cambios actuales** — hay ~40 archivos modificados sin commit incluyendo el fix del log
2. **Crear ESTADO_SESION_2026-05-14.md** ← este archivo

### Auditoría (ordenado por severidad crítica)
1. **SF-AUD-013 — Backdraft**: añadir masa combustible no quemado, LFL/UFL, mezcla inflamable
2. **SF-AUD-012 — Flashover**: añadir criterio heat flux al suelo (~20 kW/m²)
3. **SF-AUD-009 — Estratificación**: consolidar ODE two-zone conservativo
4. **SF-AUD-006 — HCN**: añadir N por combustible + yield HCN dependiente de ventilación
5. **SF-AUD-017 — Supresión**: vapor, evaporación, steam visibility
6. **SF-AUD-005 (pendiente)** — completar balance elemental para CO2/soot
7. **SF-AUD-019 — Timestep**: validar independencia con barrido dt

### Calibración CFAST (abierta desde 2026-05-06)
- `cfast_r0_window_360.json`: temperatura upper aún ~30% baja vs CFAST
- Nuevos parámetros `outside_open_upper_heat_boost` y `outside_lower_fresh_air_cooling_rate` pueden ayudar a calibrar

---

## Ruta de ejecutables

```powershell
# Godot
F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe

# Suite validación completa
cd F:\OneDrive\Documentos\GitHub\simufire
.\sim\validation\run_all_cases.ps1 -GodotExe "F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe" -ContinueOnFailure

# Reference checks
.\sim\validation\run_reference_checks.ps1 -SkipCaseRuns

# Logs del simulador (user://)
C:\Users\dangp\AppData\Roaming\Godot\app_userdata\simufire\sim_log.txt
C:\Users\dangp\AppData\Roaming\Godot\app_userdata\simufire\sim_log.csv
```
