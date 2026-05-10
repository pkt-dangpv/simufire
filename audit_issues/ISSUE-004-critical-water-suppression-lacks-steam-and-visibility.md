# ISSUE-004: Supresion con agua sin vapor, momentum ni visibilidad post-aplicacion

Severidad: Critica para entrenamiento  
Area: ataque interior/exterior, agua, vapor, tenabilidad  
Hallazgo relacionado: SF-AUD-017

## Evidencia

- `sim/core/SimulationEngine.gd:204-208` define calor absorbido, decaimiento HRR y fracciones de enfriamiento.
- `sim/core/SimulationEngine.gd:1168-1214` aplica cooling y reduce HRR exponencialmente.
- No hay masa de vapor, evaporacion parcial, desplazamiento de O2, momentum del chorro, water mapping ni perdida temporal de visibilidad por vapor.

## Riesgo

Puede ensenar que aplicar agua siempre mejora inmediatamente visibilidad/tenabilidad o reduce el incendio de forma demasiado limpia. Es especialmente sensible para debates de ataque exterior, interior y coordinacion agua-ventilacion.

## Referencias recomendadas

- UL FSRI Impact of Fire Attack Utilizing Interior and Exterior Streams.
- UL FSRI Coordinated Fire Attack / Single-Family Homes.
- NIST/UL/FDNY Governors Island.

## Criterio de cierre

- Modelo de agua separa calor sensible, calor latente, fraccion evaporada, vapor generado, mojado de superficies y enfriamiento de gases.
- La visibilidad no mejora instantaneamente si hay vapor/soot persistente.
- Escenarios UL/FSRI calibrados reproducen descenso de temperatura y HRR sin ocultar efectos adversos.
