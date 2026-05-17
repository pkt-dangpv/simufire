# ISSUE-001: Mantener benchmark CFAST de capa caliente/temperatura como guardrail

Severidad: Baja  
Area: gases calientes, capa superior, validacion CFAST  
Hallazgo relacionado: SF-AUD-002, SF-AUD-003

## Evidencia

- `ESTADO_SESION_2026-05-09.md` documenta suite interna `run_all_cases.ps1` con 17/17 PASS tras el `z_m fix`.
- `sim/validation/reports/reference_checks.json` es un benchmark externo CFAST/Ghanekar separado, no la suite interna.
- Se ejecuto `run_reference_checks.ps1 -SkipCaseRuns` el 2026-05-09 18:54 reutilizando reportes existentes. Los checks CFAST de temperatura superior y altura de capa pasan.
- Los fallos externos actuales ya no son temperatura/capa CFAST, sino CO superior CFAST y metricas Ghanekar.
- Codigo afectado: `sim/core/ThermalSystem.gd`, `sim/smoke/SmokeModel.gd`, `sim/core/GasExchangeSystem.gd`, `sim/core/OxygenExchangeSystem.gd`.

## Riesgo

El riesgo principal aqui es de regresion futura o de comunicar cifras obsoletas. Este issue ya no debe tratarse como fallo fisico actual de temperatura/capa con la evidencia disponible.

## Referencias recomendadas

- NIST CFAST TN 1889v1/v3.
- NIST TN 1603.
- ASTM E1355.

## Criterio de cierre

- Mantener los checks CFAST de temperatura/capa como gate.
- Si vuelven a fallar tras una rerun completa, registrar errores actuales y abrir issue fisico especifico.
- Se incluye barrido de timestep que demuestre estabilidad.
