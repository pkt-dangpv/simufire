# Estado de Sesión — 2026-06-05

## Resumen
- ✅ **PHY-B1 COMPLETO**: gap HVAC-1 sobrepresión reducido 22% → 9%
- HEAD previo: `cce59d5` (v0.7.0 roadmap cerrado)
- **381/381 guardrails PASS · 57/57 product checks PASS**

## Cambios realizados

### PHY-B1 — Sobrepresión sellada: chi_conv 0.65 → 0.70

**Diagnóstico**: `phase3_chi_conv` controla la fracción convectiva del HRR en la ODE de presión
termodinámica (`dp_source = (γ-1) · Q_conv / V`). El valor 0.65 generaba P_ss ≈ 1475 Pa; el valor
SFPE/CFAST estándar es 0.70 (chi_rad = 0.30), que da P_ss ≈ 1711 Pa.

**Archivos modificados**:
- `sim/core/GasExchangeSystem.gd`: `var phase3_chi_conv: float = 0.65` → `0.70` (línea 94)
- `sim/core/SimulationEngine.gd`: `@export var phase3_chi_conv: float = 0.65` → `0.70` (línea 675)
- `sim/validation/baselines/cfast_overpressure_sealed.json`: [1032,1918] → [1454,1968] (±15% de 1711 Pa)
- `docs/ROADMAP_TECHNICAL_SIMULATOR_V0_5.md`: sección PHY-B añadida, PHY-B1 marcado COMPLETO

**Resultados**:
| Métrica | Antes | Después |
|---------|-------|---------|
| `room_0_max_overpressure_pa` | 1475.27 Pa | 1710.69 Pa |
| Gap vs CFAST (~1888 Pa) | ~22% | ~9% |
| Baseline `min` | 1032 Pa | 1454 Pa |
| Baseline `max` | 1918 Pa | 1968 Pa |

**Raíz técnica**: El valor 0.65 correspondía a chi_rad=0.35 (madera SFPE old); el estándar actual
CFAST 6.x usa chi_r=0.30 (chi_c=0.70). P_ss ∝ chi_conv², por lo que (0.70/0.65)² ≈ 1.162 explica
exactamente el +16% observado.

**Commit esperado**: `feat(phys): PHY-B1 phase3_chi_conv 0.65→0.70 — gap HVAC-1 22%→9%`

## Estado validación
- `python scripts/simulation/validation_guardrails.py` → **381/381 PASS**
- `python scripts/check_product.py` → **57/57 PASS**
- Gap HVAC-1 residual: ~9% (vs CFAST, estimado)

## Próximos candidatos v0.8.0
- PHY-B2: gap HVAC-2 CO₂ estratificación capa superior ~5-12% baja
- PHY-B3: gap HVAC-3 O₂ pasillo superior recuperación ~8% alta
- PHY-B4: gap HVAC-4 HRR vent-limited plateau ~10% alto

## Actualización Codex — two-zone M1/M2

### Estado
- ✅ **M1 alpha cerrada**: núcleo two-zone con masas/energías upper/lower, solver conservativo y telemetría de comparación legacy/two-zone.
- ✅ **M2 beta candidata implementada**: selector `fire_o2_mode` (`legacy`, `upper`, `lower`, `interface`) conectado a combustión, oxígeno, estado y CLI de validación.
- ⚠️ `upper` todavía **no queda como default global**; se activa por `-FireO2Mode upper` hasta rebaseline/decisión de M4.

### Evidencia focal M2
- Caso: `cfast_hvac_residential`
- Comando focal: `run_case.ps1 -CaseName cfast_hvac_residential -EngineMode two-zone -FireO2Mode upper`
- Reporte: `sim/validation/reports/m2_upper_two_zone_cfast_hvac_residential.json`
- Resultado: cerrados los 4 gaps objetivo HVAC de CO/CO₂ con `fire_o2_full_hrr_open = 0.126`; queda fuera de M2 el gap de presión HVAC t450.

### Validación actual
- `python -m unittest discover tests -v` → **161/161 PASS**
- `python scripts/check_product.py` → **57/57 PASS**
- `python scripts/simulation/validation_guardrails.py` → **381/381 PASS**
- Godot 4.6.3 headless `--quit-after 1` → **PASS**
- `git diff --check` → **PASS**

## Actualización Codex — M3 opening-flow slice

### Estado
- ✅ **M3 RC extendido implementado bajo flag**: `two_zone_opening_flow_enabled` enruta especies por zona real de origen/destino usando el `opening_flow_cache` compartido.
- ✅ Rutas cruzadas upper/lower: el segmento de abertura se compara contra `thermal_layer_m`; las aberturas verticales de escalera resuelven planta baja/planta alta como extremos distintos.
- ✅ Purgas exteriores/HVAC: venteo exterior alto usa inventario upper; HVAC extrae/inyecta especies y O2 por altura de retorno/suministro.
- ✅ CLI de validación: `run_case.ps1 -TwoZoneOpeningFlow`; el comparador legacy/two-zone también acepta `-TwoZoneOpeningFlow`.
- ✅ Telemetría por sala: `two_zone_opening_upper_in/out_kg` y `two_zone_opening_lower_in/out_kg`.
- ✅ Presión canónica cableada como opt-in experimental: `phase3_pressure_canonical_enabled` y CLI `run_case.ps1 -CanonicalPressure` / comparador `-CanonicalPressure`.
- ✅ Presión canónica mejorada: igualación por componente interior conectado y sin doble conteo de fugas cerradas en `step_pressure_venting`.
- ✅ Transporte térmico vertical de escalera cerrado bajo opt-in: `phase3_stairwell_heat_bridge_*` adelanta la llegada térmica sin mover especies, con cap final editable para evitar picos no físicos en salas `escalera`.
- ⚠️ M3 queda listo como RC bajo flags; la promoción a contrato estable y retirada de flags legacy queda para M4/rebaseline global.

### Evidencia M3
- Corrida smoke: `cfast_two_room_door_open`, `-EngineMode two-zone`, `-TwoZoneOpeningFlow`, `-ValidationDuration 120`.
- Reporte: `sim/validation/reports/m3_opening_two_zone_cfast_two_room_120.json`.
- Resultado: `two_zone_opening_flow_enabled=1`, rutas lower activas (`room_0_final_two_zone_opening_lower_in/out_kg=1.7613`), residual transporte carbono `-5.15e-4 kg`.
- Corrida HVAC activo: `carbon_balance_hvac`, `-EngineMode two-zone`, `-FireO2Mode upper`, `-TwoZoneOpeningFlow`, `-ValidationDuration 120`.
- Reporte: `sim/validation/reports/m3_opening_carbon_balance_hvac_120.json`.
- Resultado: `hvac_on=1`, residual transporte carbono `-1.12e-4 kg`.
- Corrida escalera: `cfast_two_floor_stairwell`, `-EngineMode two-zone`, `-FireO2Mode upper`, `-TwoZoneOpeningFlow`, `-ValidationDuration 180`, `-AllowBaselineFailure`.
- Reporte: `sim/validation/reports/m3_opening_two_zone_stairwell_180.json`.
- Resultado: abertura vertical activa (`room_0_final_two_zone_opening_lower_in/out_kg=238.89`), residual transporte carbono `-2.69e-4 kg`; baseline histórica de humo planta superior sigue pendiente de M4/rebaseline.
- Corrida presión canónica aislada: `cfast_overpressure_sealed`, `-EngineMode legacy`, `-FireO2Mode legacy`, `-CanonicalPressure`, `-ValidationDuration 120`, `-AllowBaselineFailure`.
- Reporte: `sim/validation/reports/m3_canonical_pressure_overpressure_legacy_120.json`.
- Resultado: `phase3_pressure_canonical_enabled=1`, `room_0_max_overpressure_pa=151.75 Pa`, residual transporte carbono `-3.22e-5 kg`; valida el cableado, no cierra calibración.
- Corrida presión canónica + stairwell: `cfast_two_floor_stairwell`, `-EngineMode two-zone`, `-FireO2Mode upper`, `-TwoZoneOpeningFlow`, `-CanonicalPressure`, `-ValidationDuration 180`, `-AllowBaselineFailure`.
- Reporte: `sim/validation/reports/m3_canonical_pressure_stairwell_180.json`.
- Resultado: `phase3_pressure_canonical_enabled=1`, `room_upper_floor_vs_lower_floor_pressure_delta_pa=0.0`, `room_0_peak_hrr_kw=706.05`, residual transporte carbono `-1.01e-3 kg`.
- Corrida presión canónica + stairwell larga: `cfast_two_floor_stairwell`, `-EngineMode two-zone`, `-FireO2Mode upper`, `-TwoZoneOpeningFlow`, `-CanonicalPressure`, `-ValidationDuration 600`, `-AllowBaselineFailure`.
- Reporte: `sim/validation/reports/m3_canonical_pressure_stairwell_600.json`.
- Resultado actualizado: **5/5 checks históricos PASS** (`HRR=751.44 kW`, `room_6_final_smoke_kg=0.161`, `time_room_6_smoke_start_s=291.92`, `time_room_6_temp_above_30_s=158.17`, `pressure_delta=0.0`); `room_6_peak_temp_upper_c=120.0` por cap opt-in y residual transporte carbono `-2.41e-3 kg`.

### Validación actualizada
- `python -m unittest discover tests -v` → **188/188 PASS**
- `python scripts/check_product.py` → **57/57 PASS**
- `python scripts/simulation/validation_guardrails.py` → **381/381 PASS**
- Godot 4.6.3 headless `--quit-after 1` → **PASS**
- `git diff --check` → **PASS** (solo avisos CRLF en working copy)
