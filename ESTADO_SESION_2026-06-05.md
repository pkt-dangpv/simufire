# Estado de Sesión — 2026-06-05

## Resumen
- ✅ **PHY-B1 COMPLETO**: gap HVAC-1 sobrepresión reducido 22% → 9%
- HEAD previo: `cce59d5` (v0.7.0 roadmap cerrado)
- **400/400 guardrails PASS · 57/57 product checks PASS**

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
- `python scripts/simulation/validation_guardrails.py` → **400/400 PASS**
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
- ✅ **M3 RC slice implementado**: `two_zone_opening_flow_enabled` enruta especies en aperturas interiores upper→upper y lower→lower usando el `opening_flow_cache` compartido.
- ✅ CLI de validación: `run_case.ps1 -TwoZoneOpeningFlow`; el comparador legacy/two-zone también acepta `-TwoZoneOpeningFlow`.
- ✅ Telemetría por sala: `two_zone_opening_upper_in/out_kg` y `two_zone_opening_lower_in/out_kg`.
- ⚠️ M3 no está cerrado completo: faltan rutas cruzadas upper/lower por interfaces desalineadas, ventanas exteriores/HVAC y presión canónica.

### Evidencia M3
- Corrida smoke: `cfast_two_room_door_open`, `-EngineMode two-zone`, `-TwoZoneOpeningFlow`, `-ValidationDuration 120`.
- Reporte: `sim/validation/reports/m3_opening_two_zone_cfast_two_room_120.json`.
- Resultado: `two_zone_opening_flow_enabled=1`, upper/lower routed `1.7613 kg`, residual transporte carbono `-5.4e-4 kg`.

### Validación actualizada
- `python -m unittest discover tests -v` → **170/170 PASS**
- `python scripts/check_product.py` → **57/57 PASS**
- `python scripts/simulation/validation_guardrails.py` → **381/381 PASS**
- Godot 4.6.3 headless `--quit-after 1` → **PASS**
