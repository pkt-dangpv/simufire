# Calibracion de transporte interior contra Ghanekar

Fecha: 2026-04-20

## Cambios aplicados

- Se anadio una estimacion de distancia entre recintos en [BuildingModel.gd](/F:/OneDrive/Documentos/GitHub/simufire/sim/BuildingModel.gd:54) para usar retardos de transporte interior.
- Se activo retardo interior para `humo`, `CO` y arrastre termico en [GasExchangeSystem.gd](/F:/OneDrive/Documentos/GitHub/simufire/sim/core/GasExchangeSystem.gd:238).
- El intercambio interior de `O2` paso a un modelo mixto en [OxygenExchangeSystem.gd](/F:/OneDrive/Documentos/GitHub/simufire/sim/core/OxygenExchangeSystem.gd:272): el dormitorio recibe el aire fresco en el mismo paso, mientras la penalizacion neta del pasillo se aplica con retardo.
- Para evitar sobrealimentar el dormitorio, el flujo de `O2` usa una reserva interna de masa comprometida en [OxygenExchangeSystem.gd](/F:/OneDrive/Documentos/GitHub/simufire/sim/core/OxygenExchangeSystem.gd:327), de forma que los siguientes intercambios ya ven un `O2` efectivo degradado aunque la lectura visible del pasillo aun no haya caido.
- Se ajustaron los parametros base en [SimulationEngine.gd](/F:/OneDrive/Documentos/GitHub/simufire/sim/core/SimulationEngine.gd:164):
  - `interior_transport_speed_m_s = 0.20`
  - `interior_o2_transport_delay_multiplier = 1.60`
  - `lower_layer_warming_rate = 0.0140`
- En transferencias diferidas se redujo el drenaje inmediato de energia/gas caliente con `delayed_upper_carry_fraction = 0.45` en [GasExchangeSystem.gd](/F:/OneDrive/Documentos/GitHub/simufire/sim/core/GasExchangeSystem.gd:241).

## Resultado en `ghanekar_bedroom_hallway`

Reporte: [ghanekar_bedroom_hallway.json](/F:/OneDrive/Documentos/GitHub/simufire/sim/validation/reports/ghanekar_bedroom_hallway.json:1)

Objetivos de referencia usados:

- `flashover @ 0.9 m`: `186 s`
- `hallway O2 < 20.4 %`: `198 s`
- `hallway CO > 200 ppm`: `204 s`
- `hallway CO > 1200 ppm`: `216 s`
- `hallway smoke start`: `198 s`

Resultado actual:

- `time_room_0_temp_0_9m_above_600c_s = 192.08 s`
- `time_room_2_o2_below_20_4pct_s = 171.00 s`
- `time_room_2_co_above_200ppm_s = 195.58 s`
- `time_room_2_co_above_1200ppm_s = 207.42 s`
- `time_room_2_smoke_start_s = 194.42 s`

Lectura:

- El comportamiento termico del dormitorio sigue dentro de una banda razonable y queda mucho mas cerca del benchmark que al inicio de la calibracion.
- El transporte de humo y CO al pasillo distal queda ya muy cerca del paper.
- El `O2` del pasillo mejora de forma estructural respecto a la version anterior, pero sigue adelantado. El gap restante ya apunta mas a limitaciones de sensor/altura y mezcla vertical que a una sola perilla global.

## Regresion interna

Reporte: [long_smoke_o2_debug.json](/F:/OneDrive/Documentos/GitHub/simufire/sim/validation/reports/long_smoke_o2_debug.json:1)

Chequeo rapido tras la calibracion:

- `time_room_1_smoke_start_s = 137.50 s`
- `time_room_0_smoke_layer_2m_s = 119.50 s`
- `time_room_0_l150_below_1_8m_s = 84.50 s`

No aparecen bloqueos ni degradaciones obvias en el caso largo interno.

## Siguiente frente recomendado

El siguiente salto de realismo ya no es un retardo global mas, sino separar observables por altura para gases toxicos y `O2` en pasillo. A partir de aqui, el frente con mas retorno es introducir una sonda de gases/tenabilidad a `0.9 m` y despues ampliar a `CO2`, `HCN` y `FED`.
