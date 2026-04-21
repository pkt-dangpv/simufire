# Concordancia Ghanekar Bedroom - 2026-04-20

Caso ejecutado:
- `res://sim/validation/cases/ghanekar_bedroom_hallway.json`

Reportes:
- `res://sim/validation/reports/ghanekar_bedroom_hallway.json`
- `res://sim/validation/reports/ghanekar_bedroom_hallway.log`

Referencia empirica:
- `res://sim/validation/EMPIRICAL_REFERENCE_GHANEKAR_2026.md`

## Cambios introducidos para esta prueba

1. Nuevo template `ghanekar_bedroom_hallway` en `BuildingTemplate.gd`.
2. Pasillo separado en dos tramos:
   - `Hallway_Near`
   - `Hallway_Far`
3. Ventilacion inicial aproximada al paper:
   - ventana abierta en el dormitorio de fuego
   - puerta principal abierta al exterior
4. Nuevas metricas genericas por umbral en `CaseRunner.gd`.
5. Nueva salida termica a `0.9 m` en `SimulationStateBuilder.gd`.

## Benchmarks del paper

Dormitorio:
- `flashover = 3.1 +/- 0.3 min` -> `186 +/- 18 s`
- `tDeltaO2 hallway = 3.3 +/- 0.3 min` -> `198 +/- 18 s`
- `tDeltaCO hallway = 3.4 +/- 0.3 min` -> `204 +/- 18 s`
- `IDLH = 3.6 +/- 0.2 min` -> `216 +/- 12 s`

## Resultado del caso actual

Metricas del reporte:
- `time_room_0_temp_0_9m_above_600c_s`: no alcanzado antes de `420 s`
- `time_room_2_o2_below_20_4pct_s = 141.0 s` -> `2.35 min`
- `time_room_2_co_above_200ppm_s = 151.67 s` -> `2.53 min`
- `time_room_2_co_above_1200ppm_s = 158.58 s` -> `2.64 min`
- `time_room_2_smoke_start_s = 150.92 s` -> `2.52 min`

Valores destacados:
- `room_0_peak_hrr_kw = 1254.85`
- `room_0_peak_temp_upper_c = 900.0`
- `room_2_peak_temp_upper_c = 60.62`
- `room_2_peak_co_ppm = 8567.35`
- `room_2_final_o2 = 0.1718`

## Lectura de concordancia

### Lo que ha mejorado

Separar el pasillo en dos tramos ha retrasado de forma visible la llegada al punto proxy de medida:
- `O2`: de `88.42 s` a `141.0 s`
- `CO > 200 ppm`: de `123.25 s` a `151.67 s`
- `CO > 1200 ppm`: de `131.67 s` a `158.58 s`
- humo en pasillo: de `122.75 s` a `150.92 s`

### Lo que sigue sin concordar

1. El pasillo distal sigue respondiendo demasiado pronto.
   - Benchmark `tDeltaO2`: `198 +/- 18 s`
   - Modelo: `141.0 s`
   - Adelanto: ~`57 s`

2. El CO en pasillo sigue llegando demasiado pronto.
   - Benchmark `tDeltaCO`: `204 +/- 18 s`
   - Modelo con `CO > 200 ppm`: `151.67 s`
   - Adelanto: ~`52 s`

3. El proxy de `IDLH` por `CO > 1200 ppm` tambien llega antes de lo observado.
   - Benchmark `IDLH`: `216 +/- 12 s`
   - Modelo: `158.58 s`
   - Adelanto: ~`57 s`

4. El criterio de `flashover` del paper no se reproduce.
   - El dormitorio alcanza `900 C` en capa superior.
   - Pero `T(0.9 m)` no supera `600 C` dentro de la ventana simulada.
   - Eso apunta a una estratificacion vertical demasiado conservadora en la zona baja.

## Diagnostico tecnico

El desacople ya no parece venir solo de la geometria general. Ahora quedan dos sesgos fisicos principales:

1. Transporte al pasillo todavia demasiado rapido.
   - El modelo sigue mezclando cada tramo del pasillo como un volumen unico.
   - No existe retardo axial dentro de cada recinto.

2. Perfil vertical de temperatura demasiado frio a `0.9 m`.
   - El compartimento de fuego entra en regimen muy severo por `temp_upper_c`.
   - Pero la temperatura respirable/intermedia sube menos de lo que exige el criterio experimental de flashover.

## Parametros a mover despues de esta prueba

Prioridad alta:
- `doorway_o2_exchange_coeff`
- `doorway_heat_exchange_coeff`
- `base_spill_kg_s_per_m2`
- `temp_push_factor`
- `interior_spill_start_layer_m`
- `interior_spill_full_layer_m`

Prioridad alta para flashover a `0.9 m`:
- `thermal_gradient_min_band_m`
- `thermal_gradient_max_band_m`
- `thermal_gradient_band_fraction`
- `floor_cooling_band_fraction`
- `floor_cooling_band_max_m`
- `lower_layer_warming_rate`

Prioridad media:
- `fire_alpha_kw_s2`
- `thermal_feedback_coeff`
- `fire_smoke_yield_kg_per_MJ`
- `co_base_yield_kg_per_MJ`
- `co_max_yield_kg_per_MJ`

## Siguiente paso recomendado

1. Mantener este caso como benchmark empirico base.
2. Hacer un barrido corto sobre transporte al pasillo para empujar `tDeltaO2` y `tDeltaCO` hacia `~200 s`.
3. Despues recalibrar el perfil termico vertical para conseguir `T(0.9 m) > 600 C` alrededor de `186 s`.
4. Solo despues tiene sentido entrar en `CO2`, `HCN`, `IDLH` compuesto y `FED`.
