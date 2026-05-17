# ISSUE-007: Pirolisis e ignicion dependen de umbrales simplificados

Severidad: Alta  
Area: pirolisis, ignicion, propagacion  
Hallazgo relacionado: SF-AUD-016

## Evidencia

- `sim/fire/FuelObjectModel.gd:40-46`: ignicion 320 C, critical heat flux 18 kW/m2, yields simples.
- `sim/fire/CombustionSystem.gd:804-996`: calentamiento/ignicion por exposicion heuristica.
- No hay mass-loss rate, heat of gasification, conduccion interna ni distincion robusta piloto/autoignicion.

## Riesgo

La propagacion secundaria, flashover y decaimiento pueden estar determinados por reglas de juego en vez de fisica de combustibles.

## Referencias recomendadas

- ASTM E1354.
- ISO 9705 room corner.
- SFPE ignition and flame spread chapters.

## Criterio de cierre

- Objetos principales tienen masa, area, thermal inertia, critical flux, heat of gasification y curva MLR.
- Time-to-ignition bajo flujos 25/35/50/75 kW/m2 coincide con datos dentro de tolerancia.
