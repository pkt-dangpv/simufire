# Memoria de parametros y concordancia empirica

## Proposito

Esta memoria deja fijado el mapa actual del codigo tras la reestructuracion y lo cruza con la literatura descargada para definir:

- que variables del simulador tienen que concordar con estudios publicados,
- que parametros del modelo podemos mover ya,
- que parametros deberiamos mover mas tarde,
- y que variables faltan todavia para una validacion empirica honesta.

## Memoria de arquitectura actual

### Nucleo

- `sim/core/SimulationEngine.gd`: coordinador central. Mantiene el tiempo, sincroniza subsistemas y expone todos los `@export var` que hoy gobiernan la fisica simplificada.
- `sim/BuildingModel.gd`: geometria del edificio, condiciones exteriores y apertura entre recintos y exterior.
- `sim/building/RoomModel.gd`: estado dinamico por recinto.
- `sim/building/OpeningModel.gd`: huecos entre recintos o hacia el exterior.

### Subsistemas ya separados

- `sim/fire/CombustionSystem.gd`: HRR, consumo de combustible, humo y CO.
- `sim/core/OxygenExchangeSystem.gd`: consumo de O2, infiltracion y mezcla por aberturas.
- `sim/core/GasExchangeSystem.gd`: transporte de humo/CO, venteo al exterior y cola post-incendio.
- `sim/core/ThermalSystem.gd`: capa caliente, temperaturas, perfiles verticales e isoterma `150 C`.
- `sim/core/FireSpreadSystem.gd`: propagacion entre recintos.
- `sim/core/GlassFailureSystem.gd`: rotura y apertura progresiva de ventanas.
- `sim/core/SimulationStateBuilder.gd`: snapshot de estado exportable.
- `sim/validation/CaseRunner.gd`: ejecucion de casos y calculo de metricas de validacion.

### Estado actual del modelo

- El codigo esta bien reestructurado para calibracion por fenomenos.
- La mayoria de parametros globales siguen viviendo en `SimulationEngine`.
- El motor ya produce observables utiles para validacion zonal.
- El modelo sigue siendo fuerte en `O2`, `CO`, humo, capas y temperatura.
- El modelo sigue siendo debil en `CO2`, `HCN`, `FED`, `HVAC` real y sondas fisicas en posiciones concretas.

## Literatura revisada y fenomenos que cubre

### Literatura mas util para nuestro modelo actual

- `Evolution of combustion gas concentrations in full-scale residential fire environments`
- `Occupant Tenability in Single Family Homes Part I`
- `Occupant Tenability in Single Family Homes Part II`
- `Effect of Firefighting Intervention on Occupant Tenability during a Residential Fire`
- `Impact of Ventilation on Fire Behavior in Legacy and Contemporary Residential Construction`
- `Coordination of Suppression and Ventilation in Single-Family Homes`
- `Coordination of Suppression and Ventilation in Multi-Family Dwellings`
- `Experimental data from gas burner fires in residential structure with HVAC system`
- `Numerical Simulations of Gas Burner Experiments in a Residential Structure with HVAC System`
- `Smoke Movement in Rooms of Fire Involvement and Adjacent Spaces`
- `Modeling Smoke Movement Through Compartmented Structures`
- `Experimental Study of the Effects of Fuel Type, Fuel Distribution, and Vent Size on Full-Scale Underventilated Compartment Fires`
- `Experimental Study of the Three Dimensional Internal Structure of Underventilated Compartment Fires`
- `Propane Gas Fire Experiments in Residential Scale Structures`
- `Air Moving Systems and Fire Protection`
- `CFAST Technical Reference Guide`
- `Verification and Validation of CFAST`

### Literatura de apoyo tactico o de dano termico

- `Positive Pressure Ventilation Report`
- `Residential Flashover Prevention with Reduced Water Flow`
- `Impact of Fire Attack Utilizing Interior and Exterior Streams`
- `Impact of Fixed Ventilation on Fire Damage Patterns in Full-Scale Structures`
- `Evaluation of Heat Flux Profiles Through Walls in Support of Fire Model Validation`
- `Changing Residential Fire Dynamics`
- `Design Fire Characteristics for Dwellings`

### Incidencias del corpus local

- `docs/literature/Journals_OpenAccess/Effects_of_HVAC_on_Combustion_Gas_Transport_2022.pdf` no contiene el articulo completo sino una pagina de error del proveedor.
- `docs/literature/FSRI_ULRI/Measurement_of_Heat_Transfer_and_Fire_Damage_Patterns_2024.pdf` esta corrupto y no debe usarse como fuente.
- Para `HVAC` y validacion de paredes hay base suficiente en el resto del corpus, pero conviene sustituir esos dos ficheros cuando aparezca una descarga limpia.

## Observables que el simulador ya produce

### Estado por recinto

- `hrr_kw`
- `fire_time_s`
- `temp_upper_c`
- `temp_lower_c`
- `temp_at_1_8m_c`
- `temp_at_1_5m_c`
- `temp_at_1_1m_c`
- `o2`
- `smoke_kg`
- `smoke_prod_kg_s`
- `smoke_layer_m`
- `hot_layer_m`
- `thermal_layer_m`
- `layer_150c_m`
- `overpressure_pa`
- `co_ppm`
- `upper_gas_kg`
- `upper_energy_kj`
- `remaining_fuel_MJ`
- `window_open_max`
- `kawagoe_factor`
- `kawagoe_hrr_max_kw`

### Metricas de validacion ya instrumentadas

- tiempo a llegada de humo a otra sala
- tiempo a `smoke_layer <= 2.0 m`
- tiempo a `L150 < 1.8 m`
- tiempo a `temp at 1.8 m >= 150 C`
- `peak_hrr_kw`
- `peak_temp_upper_c`
- `peak_co_ppm`
- `time_to_extinction_s`
- `time_to_quiescent_s`

## Parametros del modelo ya expuestos y movibles

### Combustion y carga de fuego

Viven sobre todo en `SimulationEngine`, `FireModel`, `FuelObjectModel` y plantillas.

- `fire_alpha_kw_s2`
- `fire_max_hrr_kw`
- `fire_secondary_hrr_gain_kw`
- `fire_o2_nominal`
- `fire_o2_min_for_flame`
- `fire_o2_consumption_kg_per_MJ`
- `fire_smoke_yield_kg_per_MJ`
- `fire_smoke_yield_low_o2_multiplier`
- `fire_smoke_basis_min_fraction`
- `fire_smolder_hrr_fraction`
- `fire_smolder_smoke_multiplier`
- `fire_subvent_o2_floor`
- `fire_subvent_temp_start_c`
- `fire_subvent_temp_full_c`
- `fire_subvent_fill_start_fraction`
- `fire_subvent_fill_full_fraction`
- `fire_starvation_o2_factor`
- `co_base_yield_kg_per_MJ`
- `co_max_yield_kg_per_MJ`
- `fire_extinction_hrr_kw`
- `fire_extinction_delay_s`
- `fire_max_active_s`
- `fire_flashover_hrr_multiplier`
- `fire_flashover_min_hrr_kw`
- `thermal_feedback_coeff`
- `thermal_feedback_max`
- `fuel_energy_MJ` por sala
- `max_hrr_kw` por sala
- `fuel_objects` y sus propiedades futuras:
  - `fuel_energy_MJ`
  - `max_hrr_kw`
  - `ignition_temp_c`
  - `ignition_flux_kw_m2`
  - `smoke_yield_kg_per_MJ`
  - `co_yield_kg_per_MJ`
  - `o2_consumption_kg_per_MJ`

### Ventilacion y mezcla

- `kawagoe_coeff`
- `window_leakage_area_m2`
- `pressure_vent_threshold_pa`
- `ach_infiltration`
- `doorway_o2_exchange_coeff`
- `doorway_o2_smoke_weight`
- `doorway_o2_pressure_weight`
- `doorway_o2_background_exchange_kg_s_m2`
- `doorway_o2_background_max_fraction_per_step`
- `doorway_o2_background_pressure_ref_pa`
- `doorway_o2_background_min_factor`
- `open_fraction` por abertura
- `width_m`, `height_m`, `sill_m` por abertura
- `outside_temp_c`
- `outside_o2`

### Humo y transporte

- `smoke_density_kg_m3`
- `base_spill_kg_s_per_m2`
- `temp_push_factor`
- `max_spill_kg_s`
- `max_fraction_out_per_s`
- `layer_relax_down`
- `layer_relax_up`
- `target_smoke_resistance_coeff`
- `target_layer_block_start_m`
- `target_layer_block_full_m`
- `interior_spill_start_layer_m`
- `interior_spill_full_layer_m`
- `pressure_spill_min_delta_pa`
- `pressure_spill_ref_delta_pa`
- `pressure_spill_max_multiplier`
- `postfire_cleanup_hot_stop_c`
- `postfire_cleanup_cool_full_c`
- `postfire_cleanup_pressure_stop_pa`
- `postfire_cleanup_pressure_full_pa`
- `smoke_settling_base_per_s`
- `smoke_settling_bonus_per_s`
- `co_postfire_purge_base_per_s`
- `co_postfire_purge_bonus_per_s`

### Termica y tenabilidad

- `upper_to_lower_loss_rate`
- `upper_to_ambient_loss_rate`
- `wall_absorption_rate`
- `max_upper_temp_c`
- `doorway_heat_exchange_coeff`
- `smoke_heat_mix_coeff`
- `thermal_gradient_min_band_m`
- `thermal_gradient_max_band_m`
- `thermal_gradient_band_fraction`
- `floor_cooling_band_fraction`
- `floor_cooling_band_max_m`
- `survival_temp_threshold_c`
- `layer_150c_relax_down_per_s`
- `layer_150c_relax_up_per_s`
- `plume_fill_depth_coeff`
- `plume_fill_response_s`
- `plume_fill_max_fraction`

### Propagacion y eventos

- `fire_spread_enabled`
- `fire_spread_ignition_temp_c`
- `fire_spread_max_layer_m`
- `fire_spread_min_smoke_kg`
- `fire_spread_min_source_hrr_kw`
- `fire_spread_required_exposure_s`
- `fire_spread_exposure_decay_s`
- `flashover_temp_c`
- `flashover_layer_m`
- `glass_auto_break_enabled`
- `glass_break_temp_c`
- `glass_break_temp_spread_c`
- `glass_open_rate_per_s`
- `glass_max_open_fraction`

## Parametros que deben concordar con literatura

### 1. Geometria, ventilacion y configuracion del caso

Debe concordar:

- planta y volumen del recinto
- altura de techo
- ancho, alto y alfizar de cada abertura
- puertas interiores abiertas o cerradas
- puerta principal abierta o cerrada
- ventanas iniciales abiertas, cerradas o retiradas
- existencia de ventilacion fija o HVAC

Lo constrinen:

- `Ghanekar 2026`
- `Occupant Tenability I-II`
- `Coordination of Suppression and Ventilation`
- `Impact of Ventilation on Fire Behavior`
- `NIST TN 1953`
- `Air Moving Systems and Fire Protection`

Parametros a mover:

- `open_fraction` por abertura
- `width_m`, `height_m`, `sill_m`
- `window_leakage_area_m2`
- `ach_infiltration`
- `pressure_vent_threshold_pa`
- activacion de `glass_auto_break_enabled`

No deberiamos calibrar nada serio sin concordar esto antes.

### 2. Carga de fuego y crecimiento inicial

Debe concordar:

- energia disponible por recinto u objeto
- HRR inicial
- crecimiento del fuego
- techo de HRR controlado por combustible o ventilacion

Lo constrinen:

- `Changing Residential Fire Dynamics`
- `Design Fire Characteristics for Dwellings`
- `Impact of Ventilation on Fire Behavior`
- `Residential Flashover Prevention`
- `NIST TN 1603`
- `NIST TN 1953`

Parametros a mover:

- `fuel_energy_MJ`
- `max_hrr_kw`
- `fire_alpha_kw_s2`
- `fire_max_hrr_kw`
- `fire_secondary_hrr_gain_kw`
- `kawagoe_coeff`
- propiedades futuras de `fuel_objects`

### 3. Transicion a incendio ventilado o subventilado

Debe concordar:

- momento en que el fuego deja de ser fuel-controlled
- limitacion por ventilacion
- agotamiento de O2
- incremento relativo de humo y CO bajo deficit de oxigeno

Lo constrinen:

- `NIST TN 1603`
- `NIST TN 1736`
- `NISTIR 5499`
- `CFAST Technical Reference Guide`

Parametros a mover:

- `fire_o2_min_for_flame`
- `fire_o2_consumption_kg_per_MJ`
- `fire_subvent_o2_floor`
- `fire_subvent_temp_start_c`
- `fire_subvent_temp_full_c`
- `fire_subvent_fill_start_fraction`
- `fire_subvent_fill_full_fraction`
- `fire_starvation_o2_factor`
- `kawagoe_coeff`

### 4. Flashover

Debe concordar:

- tiempo a flashover
- criterio termico equivalente
- relacion entre flashover y descenso de capa

Lo constrinen:

- `Ghanekar 2026`
- `Impact of Ventilation on Fire Behavior`
- `Residential Flashover Prevention`
- `Changing Residential Fire Dynamics`

Parametros a mover:

- `flashover_temp_c`
- `flashover_layer_m`
- `fire_flashover_hrr_multiplier`
- `fire_flashover_min_hrr_kw`
- `thermal_feedback_coeff`
- `thermal_feedback_max`

Nota:

- El modelo actual usa un trigger simplificado de flashover. Antes de venderlo como empirico hay que compararlo contra tiempo a flashover y no solo contra temperatura de capa superior.

### 5. Transporte de humo y tiempo de llegada a pasillos/recintos remotos

Debe concordar:

- tiempo de llegada del humo
- velocidad de descenso de capa
- acumulacion en pasillo
- derrame por dintel y mezcla interzonal

Lo constrinen:

- `Ghanekar 2026`
- `Smoke Movement in Rooms of Fire Involvement and Adjacent Spaces`
- `Modeling Smoke Movement Through Compartmented Structures`
- `Improvement in Predicting Smoke Movement in Compartmented Structures`
- `Occupant Tenability I-II`

Parametros a mover:

- `smoke_density_kg_m3`
- `base_spill_kg_s_per_m2`
- `temp_push_factor`
- `max_spill_kg_s`
- `max_fraction_out_per_s`
- `target_smoke_resistance_coeff`
- `target_layer_block_start_m`
- `target_layer_block_full_m`
- `interior_spill_start_layer_m`
- `interior_spill_full_layer_m`
- `pressure_spill_min_delta_pa`
- `pressure_spill_ref_delta_pa`
- `pressure_spill_max_multiplier`
- `layer_relax_down`
- `layer_relax_up`

### 6. Temperatura de capa y temperatura a altura de respiracion

Debe concordar:

- `temp_upper_c`
- `temp_lower_c`
- perfil vertical
- temperatura a `1.8 m`, `1.5 m` y `1.1 m`
- isoterma de `150 C`

Lo constrinen:

- `Occupant Tenability I-II`
- `Effect of Firefighting Intervention on Occupant Tenability`
- `Ghanekar 2026`
- `NIST TN 1736`
- `NIST TN 1953`
- `CFAST` / `FDS` como referencia de consistencia

Parametros a mover:

- `upper_to_lower_loss_rate`
- `upper_to_ambient_loss_rate`
- `wall_absorption_rate`
- `doorway_heat_exchange_coeff`
- `smoke_heat_mix_coeff`
- `thermal_gradient_min_band_m`
- `thermal_gradient_max_band_m`
- `thermal_gradient_band_fraction`
- `floor_cooling_band_fraction`
- `floor_cooling_band_max_m`
- `plume_fill_depth_coeff`
- `plume_fill_response_s`
- `plume_fill_max_fraction`
- `survival_temp_threshold_c`
- `layer_150c_relax_down_per_s`
- `layer_150c_relax_up_per_s`

### 7. Oxigeno

Debe concordar:

- curva de caida de `O2`
- momento de minimo
- recuperacion por infiltracion o ventilacion
- diferencias entre puertas abiertas/cerradas y HVAC on/off

Lo constrinen:

- `Ghanekar 2026`
- `Occupant Tenability I-II`
- `Experimental data from gas burner fires in residential structure with HVAC system`
- `Numerical Simulations ... HVAC System`
- `NIST TN 1603`

Parametros a mover:

- `fire_o2_consumption_kg_per_MJ`
- `ach_infiltration`
- `doorway_o2_exchange_coeff`
- `doorway_o2_smoke_weight`
- `doorway_o2_pressure_weight`
- `doorway_o2_background_exchange_kg_s_m2`
- `doorway_o2_background_max_fraction_per_step`
- `doorway_o2_background_pressure_ref_pa`
- `doorway_o2_background_min_factor`
- `window_leakage_area_m2`

### 8. CO

Debe concordar:

- produccion de CO en fase ventilada
- incremento fuerte en fase subventilada
- transporte a pasillo y recintos remotos
- concentracion maxima y tiempo de llegada

Lo constrinen:

- `Ghanekar 2026`
- `Occupant Tenability I-II`
- `Effect of Firefighting Intervention on Occupant Tenability`
- `NISTIR 5499`
- `NIST TN 1736`

Parametros a mover:

- `co_base_yield_kg_per_MJ`
- `co_max_yield_kg_per_MJ`
- todos los parametros de mezcla y spill que controlan transporte
- `co_postfire_purge_base_per_s`
- `co_postfire_purge_bonus_per_s`

Nota:

- `CO` ya esta modelado y es de las mejores variables para calibrar de inmediato.

### 9. CO2, H2O y HCN

Debe concordar:

- `CO2` y `H2O` en casos HVAC y de tenabilidad
- `HCN` en casos de toxicidad y `FED`

Lo constrinen:

- `Ghanekar 2026`
- `Occupant Tenability I-II`
- `Effect of Firefighting Intervention on Occupant Tenability`
- `Experimental data from gas burner fires in residential structure with HVAC system`

Estado actual (**NOTA 2026-05-27: HCN implementado desde Phase R6, 2026-05-14. Ver AUDIT_REPORT.md SF-AUD-006. FED por componente (fed_co, fed_hcn, fed_hypoxia, fed_heat) implementado en Phase 4B 2026-05-27.**):

- `CO2`: no modelado [en 2026-04-19; implementado Phase 2B]
- `H2O`: no modelado [estado pendiente]
- `HCN`: no modelado [en 2026-04-19; implementado Phase R6 2026-05-14]

Accion:

- estos no son "parametros a mover", sino "variables a implementar".

### 10. FED, IDLH y tenabilidad toxicologica

Debe concordar:

- tiempo a `IDLH`
- `FED` acumulado
- tenabilidad en pasillo y recintos de refugio

Lo constrinen:

- `Ghanekar 2026`
- `Occupant Tenability I-II`
- `Effect of Firefighting Intervention on Occupant Tenability`
- casos FSRI tacticos de busqueda y rescate

Estado actual:

- no existe calculo de `FED`
- la tenabilidad actual se aproxima por `L150` y `temp_at_1_8m_c`
- falta integracion toxicologica real

Accion:

- implementar `FED` como observable derivado de `CO`, `CO2`, `HCN` y `O2`
- no calibrar tacticas de supervivencia con rigor hasta tenerlo

### 11. Presion y forzado por ventilacion

Debe concordar:

- sobrepresion del recinto caliente
- derrame por aberturas
- sensibilidad a huecos cerrados, fugas y ventilacion fija

Lo constrinen:

- `Coordination of Suppression and Ventilation`
- `Impact of Fixed Ventilation on Fire Damage Patterns`
- `Impact of Ventilation on Fire Behavior`
- `NISTIR 4872`
- `NISTIR 5227`

Parametros a mover:

- `pressure_vent_threshold_pa`
- `pressure_spill_min_delta_pa`
- `pressure_spill_ref_delta_pa`
- `pressure_spill_max_multiplier`
- `doorway_o2_pressure_weight`
- `doorway_o2_background_pressure_ref_pa`

### 12. HVAC

Debe concordar:

- diferencia entre `HVAC on` y `HVAC off`
- efecto de rejillas y conductos en tiempos de llegada y mezcla de especies
- dependencia con puerta de dormitorio abierta/cerrada

Lo constrinen:

- `Experimental data from gas burner fires in residential structure with HVAC system`
- `Numerical Simulations ... HVAC System`
- `Air Moving Systems and Fire Protection`

Estado actual:

- el modelo no tiene red HVAC explicita
- solo existe infiltracion global y mezcla por aberturas

Accion:

- implementar `HVAC state`, `supply/return vents`, `flow rate`, `vent position`
- no intentar calibrar estos papers solo con `ach_infiltration`

### 13. Propagacion del incendio

Debe concordar:

- paso de incendio del recinto origen a recintos adyacentes
- dependencia de temperatura, humo y exposicion

Lo constrinen:

- corpus FSRI de tacticas y vivienda completa
- `Impact of Ventilation on Fire Behavior`
- casos de flashover y propagacion del humo

Parametros a mover:

- `fire_spread_ignition_temp_c`
- `fire_spread_max_layer_m`
- `fire_spread_min_smoke_kg`
- `fire_spread_min_source_hrr_kw`
- `fire_spread_required_exposure_s`
- `fire_spread_exposure_decay_s`

Nota:

- esto deberia calibrarse despues de fijar bien termica, humo y ventilacion.

### 14. Rotura de vidrio

Debe concordar:

- si el caso experimental contempla rotura o retirada de ventana
- cuanto tarda en abrirse una fachada una vez rota

Lo constrinen:

- estudios FSRI con cambios de ventilacion
- casos donde la ventana se retira desde el inicio

Parametros a mover:

- `glass_auto_break_enabled`
- `glass_break_temp_c`
- `glass_break_temp_spread_c`
- `glass_open_rate_per_s`
- `glass_max_open_fraction`

Nota:

- no usar este subsistema para compensar una geometria mal definida en el caso.

### 15. Cola post-incendio y limpieza

Debe concordar:

- descenso residual de humo
- purga de CO
- retorno a cuasi-ambiente

Lo constrinen:

- validaciones internas de `postfire_decay`
- en literatura, de forma secundaria, casos de ventilacion y decaimiento

Parametros a mover mas tarde:

- `postfire_cleanup_hot_stop_c`
- `postfire_cleanup_cool_full_c`
- `postfire_cleanup_pressure_stop_pa`
- `postfire_cleanup_pressure_full_pa`
- `smoke_settling_base_per_s`
- `smoke_settling_bonus_per_s`
- `co_postfire_purge_base_per_s`
- `co_postfire_purge_bonus_per_s`

## Parametros que NO deberiamos mover al principio

- cualquier parametro de `postfire_cleanup`
- `glass_*`, salvo que el caso experimental lo requiera de verdad
- `fire_spread_*`
- `layer_150c_relax_*` si aun no hemos fijado antes termica y perfiles verticales

## Variables que faltan y hay que anadir

- `CO2`
- `H2O`
- `HCN`
- `FED`
- sonda fisica con `room_id`, `height_m`, `x`, `y` o al menos `room_id + height_m`
- metrica directa de `time_to_idlh`
- estado de `HVAC`
- `front_door` como abertura exterior explicita
- ventilacion fija o rejillas
- opcion de usar `casos empiricos` con geometria distinta a `simple_house`

## Orden recomendado de calibracion

### Fase 1 - escenario y ventilacion

- geometria
- puertas
- ventanas
- abertura exterior real
- `ach_infiltration`
- fuga en ventanas

### Fase 2 - combustiones y termica

- `fire_alpha_kw_s2`
- `fire_max_hrr_kw`
- `kawagoe_coeff`
- `thermal_feedback_*`
- `upper_to_lower_loss_rate`
- `upper_to_ambient_loss_rate`
- `wall_absorption_rate`
- `plume_fill_*`

### Fase 3 - humo, O2 y CO

- `fire_o2_consumption_kg_per_MJ`
- `doorway_o2_*`
- `fire_smoke_yield_*`
- `co_base_yield_kg_per_MJ`
- `co_max_yield_kg_per_MJ`
- `base_spill_kg_s_per_m2`
- `temp_push_factor`
- `pressure_spill_*`

### Fase 4 - tenabilidad real

- anadir `CO2`, `HCN`, `FED`
- definir `IDLH`
- validar pasillo y recintos de refugio

### Fase 5 - efectos avanzados

- `HVAC`
- propagacion entre recintos
- rotura de vidrio
- dano termico
- tacticas de intervencion

## Casos empiricos que deberiamos construir ya

- `ghanekar_bedroom_hallway`
- `ghanekar_kitchen_living_hallway`
- `nist_iso9705_under_vent`
- `hvac_door_transport`
- `legacy_vs_contemporary_ventilation`

## Conclusiones de trabajo

- El codigo ya esta reestructurado de forma suficientemente limpia como para calibrar por subsistemas.
- El cuello de botella ya no es la arquitectura, sino la ausencia de `casos empiricos` y de variables toxicas adicionales.
- Hoy podemos calibrar de forma seria `ventilacion`, `O2`, `CO`, `humo`, `temperatura`, `L150` y `tiempos de llegada`.
- No podemos afirmar concordancia realista de `FED`, `IDLH toxico`, `HVAC` o `HCN` porque el modelo todavia no los representa.
- La prioridad no es mover muchos coeficientes a la vez, sino alinear primero escenario, ventilacion y puntos de medida con cada paper de referencia.
