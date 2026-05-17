# ISSUE-002: Quimica toxica no especifica por combustible ni conservativa

Severidad: Critica  
Area: combustion, CO, CO2, HCN, soot, FED  
Hallazgo relacionado: SF-AUD-005, SF-AUD-006, SF-AUD-007, SF-AUD-018

## Evidencia

- CO/CO2/HCN se calculan con yields globales y factores de calidad: `sim/fire/CombustionSystem.gd:543-596`.
- HCN no depende de nitrogeno del combustible; `sim/fire/FuelObjectModel.gd` no contiene composicion elemental ni yield HCN por objeto.
- `sim/validation/reports/reference_checks.json` actualizado el 2026-05-09 18:54 falla CO superior CFAST: t420 `6023 ppm` vs `379 ppm` esperado; t510 `6021 ppm` vs `326 ppm` esperado.
- La referencia empirica actualizada (`sim/validation/EMPIRICAL_REFERENCE_GHANEKAR_2026.md`) deja claro que cerrar Ghanekar requiere sonda a `0.9 m`, HCN, retardo de linea de muestreo y mezcla vertical/local, no solo promedios por sala.

## Riesgo

FED puede parecer cuantitativo aunque sus entradas no sean confiables. En mobiliario sintetico, HCN y CO pueden dominar incapacitación; un valor generico puede producir falsos seguros o falsas alarmas.

## Referencias recomendadas

- ISO 13571:2012 e ISO/TR 13571-2:2016.
- NIST TN 1603/TN 1736 para especies, soot y combustion efficiency.
- SFPE Handbook, combustion toxicity.

## Criterio de cierre

- Cada combustible define composicion elemental o familia quimica, heat of combustion, soot yield, CO yield, CO2 yield y HCN yield/rango.
- El solver registra budget de C/O/N por paso.
- Ghanekar CO/HCN dejan de ser known gaps y pasan criterios requeridos.
