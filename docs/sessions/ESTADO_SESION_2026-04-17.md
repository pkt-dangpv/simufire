# Simufire - Estado de sesion
**Ultima actualizacion**: 17 abril 2026

## Resumen ejecutivo
- El proyecto ya no esta en fase de "motor roto".
- El runtime de Godot arranca y las validaciones headless ejecutan correctamente.
- El estado real actual es de **regresion de calibracion**, no de bloqueo tecnico.
- La causa visible esta en el equilibrio entre:
  - intercambio local de `O2`
  - extincion por sofocacion
  - transferencia sostenida de humo/calor al pasillo

## Donde estamos hoy
- La arquitectura ya entro en una fase mas madura:
  - `Main.gd` esta limpio y orquesta `engine -> HUD/Visualizer`
  - `CombustionSystem.gd` ya absorbe parte de la logica de fuego
  - `SmokeModel.gd` concentra la logica de derrame/transferencia de humo
  - `CaseRunner.gd` ya da un banco de validacion reproducible
- El cuello de botella actual no es de estructura base, sino de **calibracion fisica**.
- Seguimos en el cierre de la **Fase 1** de la hoja de ruta y en el arranque real de la **Fase 2**:
  - nucleo fisico razonablemente estable
  - validacion cuantitativa todavia no cerrada

## Validacion ejecutada hoy
Motor usado:
- `F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe`

Casos ejecutados hoy:
- `living_room_hallway` -> `FAIL`
- `postfire_decay` -> `FAIL`
- `layer150_tenability` -> `FAIL`
- `long_smoke_o2_debug` -> ejecutado como diagnostico largo

Reportes:
- [living_room_hallway.json](/F:/OneDrive/Documentos/GitHub/simufire/sim/validation/reports/living_room_hallway.json:1)
- [postfire_decay.json](/F:/OneDrive/Documentos/GitHub/simufire/sim/validation/reports/postfire_decay.json:1)
- [layer150_tenability.json](/F:/OneDrive/Documentos/GitHub/simufire/sim/validation/reports/layer150_tenability.json:1)
- [long_smoke_o2_debug.json](/F:/OneDrive/Documentos/GitHub/simufire/sim/validation/reports/long_smoke_o2_debug.json:1)
- [long_smoke_o2_debug.log](/F:/OneDrive/Documentos/GitHub/simufire/sim/validation/reports/long_smoke_o2_debug.log:1)

## Lectura honesta del comportamiento actual
### Lo que si esta mejor que antes
- Ya no hay "succion global" de `O2` en toda la vivienda.
- `R2-R5` ya no se vacian artificialmente de `O2` sin recibir humo.
- El fuego no se queda en modo zombi largo como antes.
- La fase post-incendio limpia humo/CO razonablemente bien.

### Lo que ahora esta peor
- El foco principal se debilita y se extingue demasiado pronto.
- La llegada de humo al pasillo es mas tardia que el baseline.
- El pasillo queda menos caliente y menos comprometido termicamente.
- En la corrida larga el humo no progresa a `R2-R5`.

## Numeros clave observados hoy
### `living_room_hallway`
- Baseline esperado:
  - `time_room_0_smoke_layer_2m_s ~= 144.0 s`
  - `time_room_1_smoke_start_s ~= 144.17 s`
- Resultado actual:
  - `time_room_0_smoke_layer_2m_s = 152.75 s`
  - `time_room_1_smoke_start_s = 152.92 s`
  - `room_1_final_temp_at_1_8m_c = 45.68 C` (esperado `80.22 C`)

### `postfire_decay`
- La cola residual final esta bien controlada.
- El fallo principal es que el foco muere demasiado pronto:
  - `time_to_extinction_s = 567.92 s`
  - baseline esperado `733.92 s`

### `layer150_tenability`
- `R0` y `R1` quedan menos severos de lo esperado por el baseline actual.
- Datos representativos:
  - `room_0_final_layer_150c_m = 0.77 m`
  - `room_1_final_temp_at_1_8m_c = 34.78 C`
  - `room_1_peak_temp_upper_c = 184.08 C`

### `long_smoke_o2_debug`
- `TIME=150.1 s`
  - `ROOM 0 HRR=786.09`
  - `ROOM 0 SmokeLayer=2.03`
  - `ROOM 1 Smoke=0.0000`
- `TIME=340.1 s`
  - `ROOM 0 HRR=8.32`
  - `ROOM 1 Smoke=0.3669`
  - `ROOM 1 O2=0.1571`
- `TIME=570.1 s`
  - `ROOM 0 HRR=0.00`
- `TIME=700.0 s`
  - `ROOM 2-5` siguen a ambiente, sin humo ni CO

## Diagnostico tecnico actual
- El ajuste de mezcla local de `O2` fue correcto en direccion:
  - mejora la fisica local
  - evita drenaje irreal en habitaciones remotas
- Pero el modelo quedo demasiado estrangulado en la zona foco/pasillo:
  - el foco pierde sosten antes de transferir suficiente humo/calor
  - el pasillo no recibe energia suficiente durante tiempo suficiente
  - la propagacion larga deja de sostenerse

Hipotesis principal de trabajo:
- el balance actual entre
  - `doorway_o2_*`
  - `fire_starvation_o2_factor`
  - `fire_extinction_delay_s`
  - acoplamiento humo/calor por puerta
  esta cortando antes de tiempo el regimen subventilado util

## Estado de la organizacion del codigo
### Fortaleza actual
- Las responsabilidades estan mas claras que en sesiones anteriores.
- `Main.gd` ya no hace logica de modelo.
- `RoomModel.gd` y `BuildingModel.gd` estan razonablemente limpios.
- `CaseRunner.gd` da trazabilidad y regresion automatizable.

### Principal deuda estructural
- `sim/core/SimulationEngine.gd` sigue demasiado grande:
  - ~`1849` lineas
  - mezcla coordinacion, termica, `O2`, humo, presion, logging y serializacion de estado
- No bloquea el avance inmediato, pero si va a penalizar la calibracion fina si sigue creciendo.

## Backlog actualizado
### Prioridad inmediata
1. Recuperar `living_room_hallway` y `postfire_decay`.
2. Reajustar el equilibrio de combustion subventilada sin reintroducir la succion global de `O2`.
3. Volver a medir `layer150_tenability` despues de eso.

### Siguiente bloque cuando vuelvan los PASS
1. Congelar nuevos baselines.
2. Reabrir propagacion larga hacia `R2-R5`.
3. Seguir moviendo responsabilidades desde `SimulationEngine.gd` a subsistemas dedicados.

### Aun no toca
- Ocupantes complejos
- FED/FEC como salida fiable
- sistemas activos
- comparativas de producto/UI como si el modelo ya estuviera cerrado

## Siguiente paso recomendado para la sesion actual
- Trabajar en la regresion de calibracion de combustion/O2.
- Objetivo concreto:
  - mantener la mezcla local de `O2`
  - recuperar duracion del foco
  - adelantar de nuevo la entrada de humo al pasillo
  - evitar volver al fuego zombi o a la cola infinita

## Ajustes aplicados hoy en codigo
Archivos tocados:
- [SimulationEngine.gd](/F:/OneDrive/Documentos/GitHub/simufire/sim/core/SimulationEngine.gd:1)

Cambios aplicados en esta sesion:
- La limpieza residual post-incendio ya no actua mientras siga habiendo fuego activo en alguna sala del incidente.
- Se reajusto el intercambio local de `O2` por puertas:
  - `doorway_o2_exchange_coeff = 1.70`
  - `doorway_o2_smoke_weight = 0.35`
  - `doorway_o2_pressure_weight = 0.65`
- Se desacoplo parcialmente el transporte termico por puerta respecto al acoplamiento de `O2`:
  - `doorway_heat_exchange_coeff = 0.26`
  - el intercambio termico interior usa `thermal_engagement = engagement * 0.65`
  - se redujo el tope de masa caliente transferida en el intercambio convectivo interior
- Se reforzo ligeramente el derrame de humo por puerta:
  - `base_spill_kg_s_per_m2 = 0.29`
  - `max_fraction_out_per_s = 0.09`
- Se suavizo la extincion por sofocacion sostenida:
  - `fire_starvation_o2_factor = 0.003`
  - `fire_extinction_delay_s = 360`

## Resultado despues de estos ajustes
### Casos actuales
- `postfire_decay` -> `PASS`
- `living_room_hallway` -> `FAIL`
- `layer150_tenability` -> pendiente de rerun en esta ultima configuracion, pero seguia `FAIL` en la pasada anterior de hoy

### Mejora lograda hoy
- `postfire_decay` recuperado:
  - `time_to_extinction_s = 713.75 s`
  - dentro del baseline esperado `733.92 +/- 45 s`
- El incendio ya no se extingue tan pronto como al inicio de la sesion:
  - al arrancar hoy estaba en `567.92 s`
  - tras los ajustes intermedios subio a `591.92 s`
  - con el ajuste final quedo en `713.75 s`

### Estado actual del caso corto principal
`living_room_hallway` en la ultima corrida de hoy:
- `peak_hrr_kw_global = 952.70`
- `time_room_0_smoke_layer_2m_s = 150.17 s`
- `time_room_1_smoke_start_s = 150.33 s`
- `room_1_peak_temp_upper_c = 179.16 C`
- `room_1_final_temp_at_1_8m_c = 52.58 C`

Lectura:
- los tiempos de entrada de humo quedaron muy cerca del umbral de `PASS`
- el pico termico de `ROOM 1` ya se acerco al baseline
- pero el pasillo sigue quedando demasiado frio a `1.8 m` al final del caso corto

## Backlog actualizado tras la sesion
1. Revalidar `layer150_tenability` con la configuracion final de hoy.
2. Recuperar `living_room_hallway`:
   - falta sobre todo subir la severidad termica habitable del pasillo
   - sin volver a sobrecalentar artificialmente la capa alta
3. Si `living_room_hallway` vuelve a verde:
   - congelar nuevos baselines
   - reabrir el caso largo de propagacion sostenida hacia `R2-R5`

## Nota honesta para la proxima sesion
- El frente ya no es "duracion del foco" ni "cola zombi": ese tramo quedo bastante mejor cerrado.
- El problema dominante pasa a ser mas especifico:
  - **como traducir mejor humo + calor en severidad util dentro del pasillo**
  - sin volver al calentamiento excesivo del techo ni a la propagacion demasiado agresiva de sesiones anteriores.
