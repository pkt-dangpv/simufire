# Phase 3 Sweep Results — corridor_chain

CFAST targets: t180=159.816+/-15.0C,  t600=168.796+/-30.0C

| Config                                                 |  t180 | t180 result              |  t600 | t600 result              |
|--------------------------------------------------------|-------|--------------------------|-------|--------------------------|
| baseline (no Phase 3)                                |  189.8 | FAIL d=+29.9C             |  105.8 | FAIL d=-63.0C             |
| 3A only (dp ODE)                                     |  189.8 | FAIL d=+29.9C             |  105.8 | FAIL d=-63.0C             |
| 3A+3B (dp + neutral plane)                           |  189.8 | FAIL d=+29.9C             |  105.9 | FAIL d=-62.9C             |
| 3D=0.1 (direct upper frac)                           |  188.8 | FAIL d=+29.0C             |  105.6 | FAIL d=-63.2C             |
| 3D=0.2                                               |  189.5 | FAIL d=+29.7C             |  105.5 | FAIL d=-63.3C             |
| 3D=0.3                                               |  188.8 | FAIL d=+29.0C             |  105.4 | FAIL d=-63.4C             |
| 3D=0.4                                               |  189.3 | FAIL d=+29.4C             |  105.3 | FAIL d=-63.5C             |
| 3D=0.5                                               |  188.7 | FAIL d=+28.9C             |  105.1 | FAIL d=-63.7C             |
| 3D=0.7                                               |  189.9 | FAIL d=+30.1C             |  104.9 | FAIL d=-63.9C             |
| 3D=1.0                                               |  189.1 | FAIL d=+29.3C             |  104.4 | FAIL d=-64.4C             |
| 3A+3B+3D=0.3                                         |  188.8 | FAIL d=+29.0C             |  105.5 | FAIL d=-63.3C             |
| 3A+3B+3D=0.5                                         |  188.7 | FAIL d=+28.9C             |  105.3 | FAIL d=-63.5C             |

## Conclusión

**Phase 3A, 3B, 3D no pueden resolver corridor_chain. Gap confirmado como estructural.**

| Mecanismo | Efecto en t180 | Efecto en t600 | Veredicto |
|-----------|---------------|----------------|-----------|
| 3A (dp ODE ~0.1 Pa) | 0.0°C | 0.0°C | Sin efecto (dp demasiado pequeño) |
| 3B (neutral plane dp) | 0.0°C | +0.1°C | Insignificante |
| 3D frac=0.5 (mejor t180) | -1.1°C | -0.7°C (peor) | Dirección incorrecta en t600 |
| 3D frac=1.0 | -0.7°C | -1.4°C (peor) | Ambas métricas estancadas o peores |

**Causa física:** al llegar t=600, la capa inferior del corredor también tiene O2 depleted (600s con fuego adyacente). Rutear ese aire al upper de la sala de fuego diluye aún más O2u → mayor throttle → temperatura más baja. El gap t=600 requiere que el fuego queme a 300 kW plenos (threshold O2=10% como CFAST), pero bajar `fire_o2_full_hrr_open` a 0.10 destruye t=180 (diagnosticado en Phase 2F).

**Clasificación:** VALID_GAP estructural Phase 3+. Misma clasificación que Grupo A (r0_window_360 ×3) y Grupo B (slow_growth_sealed ×2).

**No activar ningún flag Phase 3 per-case corridor_chain.** Los defaults siguen siendo false/0.0.
