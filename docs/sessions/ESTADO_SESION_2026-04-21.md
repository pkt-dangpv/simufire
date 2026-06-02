# Simufire - Estado de sesion
**Ultima actualizacion**: 21 abril 2026

## Resumen ejecutivo
- Sesion dedicada a FED/SVV: cotejo con literatura y corrección de curva FED→SVV.
- La validación `ghanekar_bedroom_hallway` (10 salas, 420 s) pasa correctamente:
  - ROOM 0 (origen): SVV=0% en t=120s por criterio térmico (L150 ≤ 0.10m)
  - ROOM 1 (pasillo): SVV=0% en t=300s por FED acumulado ≥ 1.0
  - ROOM 2: SVV=0% en t=370s por FED ≥ 1.0
  - ROOM 3 (distante): SVV=95% en t=420s (zona segura)
  - ROOM 5 (lateral): SVV=0% en t=420s (FED=1.065)
- Todas las implementaciones anteriores (sesiones 20 abril) siguen activas.

## Cambios de esta sesion

### Cotejo literatura (completado)
Fuentes consultadas: ISO 13571 (via Jeong 2014 / Lund 5454.txt), NIST TN.1760, Fire-Hazard-CFD.

| Fórmula | Veredicto |
|---|---|
| FED_CO = 3.317e-5 × CO^1.036 × V_CO2 × Δt_min | ✅ Correcto (ISO 13571 Eq.2) |
| V_CO2 = exp(0.1903×CO2%+2.0004)/7.1 solo cuando CO2>2% | ✅ Correcto (ISO 13571 Eq.3) |
| FED_O2 = Δt / exp(8.13 − 0.54 × (20.9 − O2%)) | ✅ Correcto (Purser / ISO 13571 Table A.1) |
| FED=1.0 → incapacitación completa persona media | ✅ Confirmado (Jeong 2014 p.16) |
| FED_HCN (HCN_ppm/4.4 × Δt × V_CO2) | ❌ NO implementado — brecha conocida |

**Brecha FED_HCN**: en incendios residenciales con muebles tapizados (poliuretano) el HCN aporta
~20-30% adicional al FED. El modelo actual es cota inferior conservadora.

### Corrección curva FED → SVV
**Problema identificado**: la curva anterior era lineal (FED=1.0 daba SVV=5%, no 0%).
La literatura establece FED=1.0 como incapacitación completa para la persona media → SVV debe ser 0%.

**Corrección aplicada** en `sim/core/ThermalSystem.gd`, `view/Visualizer.gd` y
`sim/core/SimulationLogWriter.gd`:

```gdscript
# ANTES (lineal, incorrecta):
fed_svv = 0.90 - 0.85 * ((fed_val - 0.3) / 0.7)  # FED=1.0 → 5%
# + zona extra 1.0-1.5 → 5% → 0%

# AHORA (potencia 1.5, cóncava):
var t_fed = (fed_val - 0.3) / 0.7
fed_svv = 0.90 * pow(1.0 - t_fed, 1.5)  # FED=1.0 → 0%
```

La curva completa queda:
- FED < 0.1    → 99–100% (ALTA)
- FED 0.1–0.3  → 90–99%  (MEDIA)
- FED 0.3–1.0  → 0.90 × (1 − t)^1.5, donde t=(FED−0.3)/0.7  (BAJA → MÍNIMA)
- FED ≥ 1.0    → 0%       (MÍNIMA, incapacitación completa)

### Archivos modificados hoy
- `sim/core/ThermalSystem.gd` — curva FED→SVV (zona BAJA/MÍNIMA)
- `view/Visualizer.gd`        — ídem, fallback
- `sim/core/SimulationLogWriter.gd` — ídem, fallback

## Estado previo activo (sesion 20 abril)
### FED/SVV implementado ayer
- `sim/building/RoomModel.gd`: `var svv_pct: float = 100.0` + `var svv_worst_pct: float = 100.0`
- `sim/core/ThermalSystem.gd` `step_fed()`:
  - FED_CO con V_CO2 solo si CO2 > 2%
  - FED_O2 hipoxia: `delta_fed += dt_min / exp(8.13 - 0.54 * (20.9 - o2_pct))`
  - `_compute_svv_pct_from_room()`: min(thermal_svv, fed_svv)
  - `svv_worst_pct = minf(svv_worst_pct, svv_pct)` — monotónica
- `sim/core/SimulationEngine.gd` `_clamp_rooms()`: clamp svv_pct, svv_worst_pct
- `sim/core/SimulationStateBuilder.gd`: exporta svv_pct, svv_worst_pct
- `view/Visualizer.gd` + `sim/core/SimulationLogWriter.gd`: usan svv_worst_pct

### Criterio térmico SVV (L150)
- L150 ≥ 1.8m  → 100%
- L150 0.5–1.8m → 90–99%
- L150 0.10–0.5m → 5–90%
- L150 ≤ 0.10m  → 0%

## Pendiente / Próximas sesiones

### 1. FED_HCN (prioridad media)
Añadir componente HCN si se tiene concentración:
```gdscript
# FED_HCN = HCN_ppm / 4.4 × v_co2 × dt_min
```
Necesita: modelado de generación de HCN por yield de combustible.

### 2. CO back-diffusion — Bug 2 (prioridad media)
Ver bloque de código en `/memories/repo/simufire_state.md` sección "Aplicar Fix Bug 2".
Insertar en `SimulationEngine._step_smoke()`.

### 3. Recalibrar baseline `postfire_decay` si necesario
Tras sesión 17-18 los valores cambiaron; revisar si sigue PASS.

### 4. Backlog largo plazo
- Backdraft
- Densidad óptica / visibilidad (OD)
- Masa térmica de paredes
- Click en sala para selector en Visualizer

## Comando de validación
```powershell
$exe = "F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe"
& $exe --headless --path "F:\OneDrive\Documentos\GitHub\simufire" -- --validation-case=ghanekar_bedroom_hallway
# log en: F:\OneDrive\Documentos\GitHub\simufire\sim\validation\reports\ghanekar_bedroom_hallway.log
```
