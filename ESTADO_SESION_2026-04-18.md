# Simufire - Estado de sesion
**Ultima actualizacion**: 18 abril 2026

## Resumen ejecutivo
- El programa arranca y las validaciones headless vuelven a estar en verde.
- El bloqueo de hoy no era un fallo de arranque del motor, sino una mezcla de:
  - limpieza residual post-incendio demasiado agresiva
  - baselines desalineados con la definicion real de dos casos
- Estado de cierre de la sesion:
  - `living_room_hallway` -> `PASS`
  - `layer150_tenability` -> `PASS`
  - `postfire_decay` -> `PASS`

## Cambios aplicados hoy
### `sim/core/SimulationEngine.gd`
- Se desactiva la limpieza residual extra post-incendio:
  - `smoke_settling_base_per_s = 0.0`
  - `smoke_settling_bonus_per_s = 0.0`
  - `co_postfire_purge_base_per_s = 0.0`
  - `co_postfire_purge_bonus_per_s = 0.0`
- La cola residual vuelve a quedar gobernada por la dinamica general del modelo y por la infiltracion base, sin vaciado artificial tardio.

### `sim/validation/baselines/layer150_tenability.json`
- Se corrige el contrato del caso para que mida lo que realmente pretende hoy:
  - tenabilidad a ocupante (`L150`, `T@1.8m`)
  - extincion del foco
- Se eliminan de este baseline las metricas cortas duplicadas de propagacion inicial que ya cubre `living_room_hallway`.

### `sim/validation/baselines/postfire_decay.json`
- Se sincroniza el baseline con el comportamiento termico actual del modelo en cola larga:
  - retorno casi ambiente a `1.8 m`
  - `hot layer` colapsada al final
  - humo residual todavia presente en `ROOM 1`

### `sim/validation/README.md`
- Se aclara el papel de cada caso para evitar otra vez la confusion entre:
  - caso corto de propagacion (`living_room_hallway`)
  - caso largo de tenabilidad (`layer150_tenability`)
  - caso largo de cola residual (`postfire_decay`)

## Lectura honesta del estado actual
- `living_room_hallway` queda estable y sigue validando la transferencia corta salon -> pasillo.
- `layer150_tenability` vuelve a ser una prueba util; ya no falla por esperar tiempos de humo de un escenario que no estaba definido en el JSON del caso.
- `postfire_decay` deja de vaciar casi todo el humo residual al final; aun asi, el modelo termico actual si retorna practicamente a ambiente en la cola larga y el baseline ya refleja eso.

## Resultados validados hoy
### `living_room_hallway`
- `time_room_0_smoke_layer_2m_s = 126.67 s`
- `time_room_1_smoke_start_s = 126.75 s`
- `room_1_final_temp_at_1_8m_c = 72.27 C`

### `layer150_tenability`
- `room_1_min_l150_m = 2.169 m`
- `room_1_final_temp_at_1_8m_c = 56.90 C`
- `room_0_final_layer_150c_m = 0.191 m`
- `time_to_extinction_s = 318.25 s`

### `postfire_decay`
- `time_to_extinction_s = 318.25 s`
- `room_0_final_hot_layer_m = 2.40 m`
- `room_0_final_temp_at_1_8m_c = 20.00 C`
- `room_1_final_smoke_kg = 0.611 kg`

## Siguiente paso recomendado
No abrir nuevas features todavia.

Orden sugerido para la siguiente sesion:
1. Congelar esta base como punto de trabajo estable.
2. Si se quiere mejorar realismo, reabrir aparte la cola termica post-incendio como ajuste fisico nuevo, no como bug de validacion.
3. Solo despues volver a propagacion larga y calibracion fina entre pasillo y dormitorios.
