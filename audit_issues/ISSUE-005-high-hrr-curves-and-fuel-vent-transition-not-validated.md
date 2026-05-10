# ISSUE-005: HRR y transicion fuel-controlled/ventilation-controlled no validados por combustible

Severidad: Alta  
Area: HRR, combustibles, ventilacion  
Hallazgo relacionado: SF-AUD-004

## Evidencia

- HRR base: `Q=alpha*t^2` en `sim/fire/FireModel.gd:42-44`.
- Alpha/cap globales en `sim/core/SimulationEngine.gd:103-104`.
- Kawagoe global en `sim/core/SimulationEngine.gd:110-113`.
- Decaimiento y pirolisis simplificados en `sim/fire/CombustionSystem.gd:210-303`.

## Riesgo

El simulador puede acertar tendencias pero fallar HRR pico, tiempos de crecimiento, transicion a ventilacion limitada y decaimiento. Eso afecta todas las variables: temperatura, gases, humo, flashover y tacticas.

## Referencias recomendadas

- SFPE Handbook.
- ASTM E1354 cone calorimeter.
- Furniture calorimeter datasets.
- NIST TN 1603.

## Criterio de cierre

- Combustibles principales tienen curvas HRR/MLR trazables.
- El HRR quemado se limita por ventilacion y combustion efficiency sin destruir el budget de masa.
- Tests de sofa/colchon/madera/liquido pasan rangos experimentales definidos.
