# ISSUE-008: Flujos por aberturas no estan resueltos por un solver conservativo unico

Severidad: Alta  
Area: ventilacion, masa, energia, especies  
Hallazgo relacionado: SF-AUD-010, SF-AUD-019

## Evidencia

- O2 se intercambia en `sim/core/OxygenExchangeSystem.gd`.
- CO/CO2/HCN/smoke se transportan en `sim/core/GasExchangeSystem.gd`.
- Calor/capa se mueve en `sim/core/ThermalSystem.gd`.
- Hay neutral plane aproximado en `ThermalSystem.gd:2050-2064` y ventilacion natural con inlet fraction fija en `GasExchangeSystem.gd:362-363`.

## Riesgo

El mismo flujo fisico puede tener masas, entalpias y especies inconsistentes. Esto afecta ventilacion tactica, puertas, ventanas, backdraft y toxicidad.

## Referencias recomendadas

- CFAST TN 1889v1.
- SFPE vent flow correlations.
- ASTM E1355.

## Criterio de cierre

- Un unico estado de flujo por abertura alimenta masa, energia y especies.
- Budgets de masa/energia/especies cierran por paso.
- Barrido dt demuestra estabilidad.
