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
