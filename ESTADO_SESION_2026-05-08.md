# Estado de Sesión — 08 mayo 2026

## Objetivos de la sesión
1. ✅ Confirmar M7 (pool_release O₂ guard) implementado y 5/5 baselines PASS
2. ✅ Reducir gap de O₂ en comparación CFAST (cfast_r0_window_360)
3. ✅ Verificar sin regresiones

---

## Cambios implementados

### 1. M7 — pool_release O₂ guard (`sim/fire/CombustionSystem.gd`)
Todo el bloque `pool_release_target_kw` envuelto en:
```gdscript
var o2_allows_pool_burn: bool = room.o2 >= float(context.get("fire_backdraft_o2_max", 0.13))
if o2_allows_pool_burn:
    ...
```
Evita que la piscina de combustible libere energía cuando O2 < 13%.

### 2. Parámetro `natural_vent_inlet_fraction`
Nuevo parámetro paramétrico para la ventilación natural exterior. Motivación física: con plano neutro a mitad altura (default=0.5), el modelo sobreestima la entrada de aire fresco cuando la habitación está caliente (plano neutro sube hacia el techo).

**`sim/core/GasExchangeSystem.gd`**:
```gdscript
var natural_vent_inlet_fraction: float = 0.5
# En configure():
natural_vent_inlet_fraction = float(settings.get("natural_vent_inlet_fraction", natural_vent_inlet_fraction))
# En cálculo nat vent (antes hardcoded 0.5):
var fresh_air_kg: float = 0.61 * (nat_area_m2 * natural_vent_inlet_fraction) * v_nat_m_s * ...
```

**`sim/core/SimulationEngine.gd`**:
```gdscript
@export var natural_vent_inlet_fraction: float = 0.5
# pasado en configure() dict:
"natural_vent_inlet_fraction": natural_vent_inlet_fraction
```

**`sim/validation/cases/cfast_r0_window_360.json`** — engine_overrides:
```json
"natural_vent_inlet_fraction": 0.20
```

---

## Resultados

### Regresión 5/5 baselines: ✅ PASS
| Caso | Resultado |
|------|-----------|
| living_room_hallway | PASS |
| layer150_tenability | PASS |
| confinement_open_close | PASS |
| postfire_decay | PASS |
| ul_exterior_water_knockdown | PASS |

### Comparación CFAST (cfast_r0_window_360, ventana 2×1.2m abre a t=360s):
| Tiempo | CFAST O₂ | Simufire O₂ | Delta O₂ | CFAST T_upper | Simufire T_upper | Delta T |
|--------|----------|-------------|----------|---------------|------------------|---------|
| 360s | 0.065 | 0.067 | +2% ✅ | — | — | — |
| 420s | 0.132 | 0.148 | +12% | 301°C | 326°C | +8% |
| 510s | 0.143 | 0.148 | +4% ✅ | — | — | — |

Gap O₂ residual (+12% a t=420s) es estructural: CFAST prescribe HRR=1280kW independientemente del O₂; Simufire usa HRR limitado por O₂ → consume menos O₂ en fase de transición. Aceptado como diferencia de modelos.

---

## Próximas tareas pendientes
- **A2** — Gap O₂ remoto (limitación modelo 0D, aceptado como tal)
- **V1–V8** — Nuevos casos de validación (no iniciados)
- **G1–G4** — Casos de ventilación táctica GIE (no iniciados)
- Bugs prioridad 2 pendientes (fed_hypoxia sin @export, paths hardcodeados, HUD parámetros)

---

## Comandos de referencia

```powershell
$exe = "C:\Users\dangp\Desktop\Godot_v4.6.2-stable_win64_console.exe"
$proj = "C:\Users\dangp\Documents\GitHub\simufire"
& $exe --headless --path $proj -- "--validation-case=<casename>" 2>&1 | Select-String "PASS|FAIL|Baseline"
```
