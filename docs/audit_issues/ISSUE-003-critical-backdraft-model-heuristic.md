# ISSUE-003: Backdraft modelado por disparador heuristico no seguro para entrenamiento

Severidad: Critica  
Area: backdraft, ventilacion, gases combustibles  
Hallazgo relacionado: SF-AUD-013

## Evidencia

- Umbrales: `fire_backdraft_pool_threshold_MJ=8`, `fire_backdraft_o2_max=0.13`, `fire_backdraft_temp_min_c=180`, multiplicador HRR 4x durante 12 s en `sim/core/SimulationEngine.gd:240-248`.
- Evento sinusoidal en `sim/fire/CombustionSystem.gd:360-438`.
- No se comprueban LFL/UFL, mezcla combustible, presion, fuente de ignicion ni deflagracion.

## Riesgo

Puede generar falsos positivos o falsos negativos de backdraft. Esto es inaceptable para entrenamiento operacional porque altera la lectura de humo, ventilacion y entrada.

## Referencias recomendadas

- NFPA 921 para fenomenologia e investigacion.
- NIST underventilated compartment fire literature.
- Literatura revisada por pares sobre backdraft y gases no quemados.

## Criterio de cierre

- El backdraft requiere masa de combustibles no quemados, mezcla dentro de limites inflamables, O2 suficiente tras ventilacion, temperatura/fuente de ignicion y presion/impulso simplificados.
- Tests con escenarios sin mezcla inflamable no disparan backdraft.
- Tests con mezcla validada reproducen ventana temporal y severidad dentro de rangos documentados.
