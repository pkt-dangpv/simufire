# Simufire - Estado de sesion
**Ultima actualizacion**: 25 abril 2026

## Objetivo de esta sesion
- Revisar por que las ultimas tareas quedaban horas sin cerrar.
- Recuperar el estado real de validaciones y tareas pendientes.
- Dejar el runner protegido para que una validacion rota no vuelva a generar bucles largos.

## Causa principal del bloqueo
- Dos corridas de `tmp_r2_window_open_start` quedaron generando logs enormes en `%TEMP%/simufire-godot-logs`.
- Causa tecnica: el codigo tenia llamadas invalidas a `maxf()` con 3 argumentos en:
  - `sim/core/GasExchangeSystem.gd`
  - `sim/core/OxygenExchangeSystem.gd`
- Godot registraba errores de compilacion, pero el proceso seguia vivo y `CaseRunner`/`Main` continuaban intentando avanzar la simulacion con subsistemas `Nil`.
- Resultado: bucle de errores y logs de aproximadamente 8.7 GB + 1.7 GB.

## Cambios aplicados
- Corregidas las llamadas a `maxf()` anidando la comparacion de tres valores.
- `CaseRunner.gd` ahora:
  - valida que `SimulationEngine` tenga subsistemas operativos antes de iniciar;
  - aborta si el estado es vacio o si el tiempo simulado no avanza;
  - ejecuta las validaciones en bucle rapido, sin depender de tiempo real.
- `Main.gd` ahora no avanza la simulacion normal cuando se lanza con `--validation-case`.
- `run_case.ps1` ahora:
  - tiene `-TimeoutSeconds` por defecto a 300 s;
  - mata el proceso de Godot si supera el timeout;
  - ya no oculta un `Baseline FAIL` con exit code 2.
- `run_all_cases.ps1` propaga `-TimeoutSeconds` a cada caso.
- `GasExchangeSystem.gd` limita el nuevo intercambio de especies de fondo a puertas donde alguna sala conectada tiene abertura exterior abierta, evitando romper casos base cerrados.

## Verificacion realizada
- Caso temporal:
  - `tmp_r2_window_open_start`: termina en unos 19 s con timeout de 120 s.
- Suite oficial:
  - `living_room_hallway`: PASS
  - `layer150_tenability`: PASS
  - `postfire_decay`: PASS
  - duracion total aproximada: 61 s

## Limpieza
- Eliminados los dos logs temporales gigantes del bucle anterior en `%TEMP%/simufire-godot-logs`.
- No quedan procesos Godot vivos tras las corridas.

## Estado del caso `tmp_r2_window_open_start`
- La ventana exterior remota en `R2` ya no deja a `R2` tan aislada en especies:
  - `R2 peak_co2_ppm`: ~15599 ppm
  - `R2 final_co2_ppm`: ~3382 ppm
  - `R2 final_smoke_kg`: ~0.485 kg
- La parte termica remota sigue muy limitada:
  - `R2 peak_temp_upper_c`: 20 C
- Interpretacion: el ajuste mejora transporte de contaminantes por la ruta hacia la ventana, pero no modela todavia transporte termico apreciable hacia la habitacion con ventana abierta.

## Pendientes reales
1. Decidir si `tmp_r2_window_open_start` debe convertirse en caso oficial con baseline o quedarse como caso exploratorio.
2. Si se quiere mas realismo en ventana remota, falta modelar mejor el acoplamiento termico/through-flow, no solo especies.
3. Pendiente historico: sedimentacion/deposicion de humo post-incendio.
4. Pendiente historico: revisar consumo de combustible/fuego zombi en salas secundarias sin depender solo de `fire_max_active_s`.

## Actualizacion posterior
- Se anadio acoplamiento termico suave para rutas interiores con abertura exterior remota:
  - `outside_open_background_heat_exchange_kg_s_m2`
  - `outside_open_background_heat_max_fraction_per_step`
  - `outside_open_background_heat_carry_factor`
- El caso `tmp_r2_window_open_start` ahora tiene baseline propia en `sim/validation/baselines/`.
- Verificacion final:
  - `tmp_r2_window_open_start`: PASS
  - `living_room_hallway`: PASS
  - `layer150_tenability`: PASS
  - `postfire_decay`: PASS
- Resultado representativo:
  - `R2 peak_temp_upper_c`: ~43.7 C
  - `R2 final_temp_at_1_8m_c`: ~20.35 C
  - `R2 peak_co2_ppm`: ~15781 ppm
  - `R2 final_smoke_kg`: ~0.495 kg
- La suite oficial sigue en PASS tras el cambio.

## Actualizacion sedimentacion post-incendio
- Se activo la deposicion lenta de humo post-incendio:
  - `smoke_settling_base_per_s = 0.00004`
  - `smoke_settling_bonus_per_s = 0.00018`
- El modelo mantiene CO/CO2 separados: la deposicion reduce masa de humo particulado, no borra gases toxicologicos.
- `SimulationStateBuilder` y `CaseRunner` ahora exponen:
  - `smoke_deposited_total_kg`
  - `smoke_generated_total_kg`
  - `smoke_vented_total_kg`
- `postfire_decay` actualizo su baseline:
  - `R0 final_smoke_kg`: ~0.494 kg
  - `R1 final_smoke_kg`: ~0.368 kg
  - `smoke_deposited_total_kg`: ~0.612 kg
- Validacion posterior:
  - `living_room_hallway`: PASS
  - `layer150_tenability`: PASS
  - `postfire_decay`: PASS
  - `tmp_r2_window_open_start`: PASS

## Actualizacion ventilacion remota y extincion falsa
- Problema detectado: con una ventana abierta en `R2`, el fuego de `R0` podia caer a 0 HRR cerca de 480 s porque la combustion solo veia aberturas exteriores locales. La ruta `R0 -> R1 -> R2 -> exterior` no alimentaba la respuesta de ventilacion de `R0`.
- Se anadio un factor de ruta ventilada por puertas interiores abiertas:
  - `fire_remote_vent_path_enabled`
  - `fire_remote_vent_path_decay_per_door`
  - `fire_remote_vent_path_min_signal`
  - `fire_remote_vent_path_max_doors`
- `OxygenExchangeSystem` usa ahora ese factor para acelerar el intercambio de O2 entre habitaciones conectadas a una salida exterior remota.
- `CombustionSystem` usa `outside_open_path_factor` junto con la ventana local para reactivar gases retenidos y mantener la combustion ventilada.
- `SimulationStateBuilder` y `CaseRunner` exponen metricas finales de HRR, O2, combustible, gases retenidos, respuesta de ventilacion y `outside_open_path_factor`.
- Se corrigio la metrica `time_to_extinction_s`: ahora solo se registra cuando no queda ningun `has_fire`, no cuando el HRR cruza momentaneamente el umbral.
- `tmp_r2_window_open_start` actualizo su baseline para comprobar que el fuego de `R0` sigue activo al final:
  - `R0 final_hrr_kw`: ~90 kW
  - `R0 final_o2`: ~0.112
  - `R0 outside_open_path_factor`: 0.405
- Validacion final:
  - `tmp_r2_window_open_start`: PASS
  - `living_room_hallway`: PASS
  - `layer150_tenability`: PASS
  - `postfire_decay`: PASS
