# Matriz de calibracion de parametros

## Objetivo

Convertir la memoria general en una hoja de trabajo accionable para calibrar `Simufire`.

## Regla de uso

- Primero se bloquea el `caso empirico`.
- Luego se calibra `ventilacion y geometria`.
- Despues `combustion y termica`.
- Luego `humo, O2 y CO`.
- Al final `tenabilidad avanzada`, `HVAC`, `FED` y efectos post-incendio.

## Convenciones

- `Actual`: valor actual del modelo o configuracion por defecto.
- `Rango inicial`: rango sugerido para barrido. Si no viene de un paper concreto, es una `inferencia` de calibracion.
- `Concordar con`: observable o curva que debemos hacer coincidir.
- `Fuente`: literatura principal del corpus local.
- `Caso`: caso empirico donde conviene tocarlo primero.

## Casos empiricos prioritarios

### Caso `ghanekar_bedroom_hallway`

- `flashover`: `3.1 +/- 0.3 min`
- respuesta de gases en pasillo: alrededor de `3.3 min`
- `IDLH`: `3.6 +/- 0.2 min`
- ventilacion inicial abierta: puerta principal abierta, ventana del compartimento retirada, rejillas HVAC abiertas

### Caso `ghanekar_kitchen_living_hallway`

- `flashover`: `14.9 +/- 0.5 min`
- `IDLH`: `10.7 +/- 1.7 min`
- mismo criterio: no usar la plantilla actual sin rehacer la ventilacion del ensayo

### Caso `nist_iso9705_under_vent`

- objetivo principal: transicion a fuego subventilado
- concordar `O2`, temperatura, estructura interna de la capa y aumento de `CO`
- prioridad: curvas y tiempos de transicion, no un unico numero final

### Caso `hvac_door_transport`

- objetivo principal: diferencia entre `HVAC on/off` y `door open/closed`
- concordar retrasos relativos y magnitud del transporte de especies
- hoy no se puede cerrar al cien por cien porque faltan `CO2/H2O/HVAC` explicitos

## Matriz P0 - Escenario y ventilacion del caso

| Pri | Parametro | Actual | Rango inicial | Concordar con | Fuente | Caso |
| --- | --- | --- | --- | --- | --- | --- |
| P0 | `open_fraction` puertas interiores | `1.0` en `simple_house` | `0.0-1.0` segun ensayo | cronologia de llegada de humo y tenabilidad remota | Ghanekar 2026, Occupant Tenability I-II | `ghanekar_*` |
| P0 | `open_fraction` ventanas exteriores | `0.0` en `simple_house` | `0.0-1.0` segun ensayo | ventilacion del recinto de fuego y HRR max por ventilacion | Ghanekar 2026, Impact of Ventilation | `ghanekar_*`, `legacy_vs_contemporary_ventilation` |
| P0 | puerta principal exterior | no existe en la plantilla base | anadir `0.0/1.0` | desacople actual entre interior muy abierto y exterior casi sellado | Ghanekar 2026, Coordination of Suppression and Ventilation | `ghanekar_*` |
| P0 | `width_m`, `height_m`, `sill_m` de aberturas | plantilla fija | geometria del ensayo | flujos por hueco, Kawagoe, derrame por dintel | NIST, FSRI | todos |
| P0 | `outside_temp_c` | `20 C` | `15-30 C` si el ensayo lo requiere | gradiente termico y flujo boyante | NIST/CFAST | todos |
| P0 | `ach_infiltration` | `0.5 1/h` | `0.2-2.0 1/h` inferencia | recuperacion de O2 y purga basal | NISTIR 4872, CFAST | `ghanekar_*`, `nist_iso9705_under_vent` |
| P0 | `window_leakage_area_m2` | `0.005 m2` | `0.001-0.02 m2` inferencia | sobrepresion y fuga neta en escenarios cerrados | NISTIR 4872, Air Moving Systems | `nist_iso9705_under_vent` |
| P0 | `pressure_vent_threshold_pa` | `2.0 Pa` | `0.5-5.0 Pa` inferencia | inicio de venteo pulsante por fugas | NISTIR 4872, Impact of Fixed Ventilation | `nist_iso9705_under_vent` |

## Matriz P1 - Parametros a calibrar primero

| Pri | Parametro | Actual | Rango inicial | Concordar con | Fuente | Caso |
| --- | --- | --- | --- | --- | --- | --- |
| P1 | `fire_alpha_kw_s2` | `0.12` | `0.03-0.20` inferencia | tiempo a crecimiento inicial y tiempo a flashover | Changing Residential Fire Dynamics, FSRI | `ghanekar_bedroom_hallway` |
| P1 | `fire_max_hrr_kw` | `3000` | `1200-5000` inferencia | `peak_hrr_kw`, techo de combustión | FSRI, NIST TN 1953 | `ghanekar_*` |
| P1 | `kawagoe_coeff` | `1500` | `900-1700` | limite por ventilacion exterior | NIST/CFAST, comentario actual del codigo | `ghanekar_*`, `nist_iso9705_under_vent` |
| P1 | `fire_o2_consumption_kg_per_MJ` | `0.076` | `0.065-0.085` | caida de `O2` y punto de estrangulamiento | Thornton/NIST, HVAC dataset | `ghanekar_*`, `hvac_door_transport` |
| P1 | `fire_o2_min_for_flame` | `0.10` | `0.08-0.15` inferencia | apagado por falta de oxigeno | NIST TN 1603, TN 1736 | `nist_iso9705_under_vent` |
| P1 | `fire_smoke_yield_kg_per_MJ` | `0.007` | `0.003-0.012` | masa de humo y altura de capa | FSRI, NIST, CFAST | `ghanekar_bedroom_hallway` |
| P1 | `fire_smoke_yield_low_o2_multiplier` | `5.0` | `2.0-8.0` inferencia | sobreproduccion de humo en subventilacion | NIST TN 1603, TN 1736 | `nist_iso9705_under_vent` |
| P1 | `co_base_yield_kg_per_MJ` | `0.00025` | `0.00015-0.0006` | `CO` en fase ventilada | NISTIR 5499, Occupant Tenability | `ghanekar_bedroom_hallway` |
| P1 | `co_max_yield_kg_per_MJ` | `0.0125` | `0.006-0.02` | `CO` en fase subventilada | NISTIR 5499, TN 1736 | `nist_iso9705_under_vent` |
| P1 | `base_spill_kg_s_per_m2` | `0.50` | `0.10-0.80` inferencia | tiempo de llegada de humo a pasillo | Smoke Movement in Rooms..., Modeling Smoke Movement | `ghanekar_bedroom_hallway` |
| P1 | `temp_push_factor` | `0.008` | `0.003-0.015` inferencia | aceleracion del derrame por salto termico | NISTIR 4872, CFAST | `ghanekar_bedroom_hallway` |
| P1 | `doorway_o2_exchange_coeff` | `1.70` | `0.8-2.5` inferencia | mezcla de `O2` entre recintos | HVAC dataset, NISTIR 4872 | `hvac_door_transport` |
| P1 | `doorway_o2_background_exchange_kg_s_m2` | `0.06` | `0.01-0.12` inferencia | acoplamiento basal entre recintos | HVAC dataset, Air Moving Systems | `hvac_door_transport` |
| P1 | `upper_to_lower_loss_rate` | `0.025` | `0.01-0.05` inferencia | temperatura de capa superior e inferior | CFAST, TN 1736 | `ghanekar_*`, `nist_iso9705_under_vent` |
| P1 | `upper_to_ambient_loss_rate` | `0.008` | `0.002-0.02` inferencia | enfriamiento global del recinto | CFAST, TN 1953 | `ghanekar_*` |
| P1 | `wall_absorption_rate` | `0.003` | `0.001-0.01` inferencia | inercia termica de cerramientos | evaluation of heat flux / CFAST | `ghanekar_*` |
| P1 | `plume_fill_depth_coeff` | `0.60` | `0.30-0.90` inferencia | formacion de capa caliente | CFAST/FDS referencias, TN 1736 | `ghanekar_bedroom_hallway` |
| P1 | `plume_fill_response_s` | `12.0 s` | `4-25 s` inferencia | retraso de llenado de capa superior | CFAST/FDS referencias | `ghanekar_bedroom_hallway` |
| P1 | `doorway_heat_exchange_coeff` | `0.26` | `0.10-0.50` inferencia | transporte de calor entre recintos | Smoke Movement / CFAST | `ghanekar_bedroom_hallway` |
| P1 | `smoke_heat_mix_coeff` | `0.025` | `0.005-0.08` inferencia | temperatura del humo transferido | CFAST, TN 1736 | `ghanekar_bedroom_hallway` |

## Matriz P2 - Ajuste fino despues de fijar P1

| Pri | Parametro | Actual | Rango inicial | Concordar con | Fuente | Caso |
| --- | --- | --- | --- | --- | --- | --- |
| P2 | `fire_subvent_o2_floor` | `0.085` | `0.03-0.10` inferencia | persistencia del fuego bajo deficit local de `O2` | NIST TN 1603, TN 1736 | `nist_iso9705_under_vent` |
| P2 | `fire_subvent_temp_start_c` | `140 C` | `80-220 C` inferencia | inicio del regimen subventilado asistido por calor | NIST TN 1603 | `nist_iso9705_under_vent` |
| P2 | `fire_subvent_temp_full_c` | `420 C` | `250-550 C` inferencia | saturacion del efecto subventilado | NIST TN 1603 | `nist_iso9705_under_vent` |
| P2 | `fire_subvent_fill_start_fraction` | `0.06` | `0.03-0.12` inferencia | onset por llenado de humo | TN 1736 | `nist_iso9705_under_vent` |
| P2 | `fire_subvent_fill_full_fraction` | `0.18` | `0.10-0.35` inferencia | saturacion por llenado de humo | TN 1736 | `nist_iso9705_under_vent` |
| P2 | `fire_starvation_o2_factor` | `0.003` | `0.001-0.02` inferencia | criterio de agonia del fuego | TN 1603 | `nist_iso9705_under_vent` |
| P2 | `fire_extinction_hrr_kw` | `8` | `3-20` inferencia | tiempo a extincion y cola del incendio | validacion interna + NIST | `postfire_decay`, `nist_iso9705_under_vent` |
| P2 | `fire_extinction_delay_s` | `360 s` | `60-600 s` inferencia | permanencia del fuego agonizante | validacion interna + NIST | `postfire_decay` |
| P2 | `thermal_feedback_coeff` | `0.15` | `0.0-0.35` inferencia | aceleracion termica y flashover | FSRI, residential flashover | `ghanekar_bedroom_hallway` |
| P2 | `thermal_feedback_max` | `1.5` | `1.0-2.0` inferencia | limite del refuerzo radiativo | FSRI, flashover | `ghanekar_bedroom_hallway` |
| P2 | `flashover_temp_c` | `500 C` | `450-650 C` | criterio de flashover del modelo | Ghanekar 2026, FSRI | `ghanekar_*` |
| P2 | `flashover_layer_m` | `1.2 m` | `0.8-1.8 m` | capa baja durante flashover | FSRI / tenability | `ghanekar_*` |
| P2 | `fire_flashover_hrr_multiplier` | `2.2` | `1.2-3.0` inferencia | salto de HRR tras flashover | FSRI, residential flashover | `ghanekar_bedroom_hallway` |
| P2 | `fire_flashover_min_hrr_kw` | `300` | `150-800` inferencia | robustez del trigger | FSRI | `ghanekar_*` |
| P2 | `pressure_spill_ref_delta_pa` | `8.0 Pa` | `2-15 Pa` inferencia | sensibilidad del derrame a sobrepresion | NISTIR 4872, fixed ventilation | `ghanekar_*` |
| P2 | `pressure_spill_max_multiplier` | `2.5` | `1.0-4.0` inferencia | techo del empuje por presion | NISTIR 4872 | `ghanekar_*` |
| P2 | `doorway_o2_smoke_weight` | `0.35` | `0.1-0.8` inferencia | cuanto pesa la capa frente a la presion en el intercambio | HVAC dataset | `hvac_door_transport` |
| P2 | `doorway_o2_pressure_weight` | `0.65` | `0.2-1.0` inferencia | idem | HVAC dataset | `hvac_door_transport` |
| P2 | `thermal_gradient_min_band_m` | `0.20 m` | `0.10-0.40 m` inferencia | perfil vertical de temperatura | TN 1736, CFAST | `ghanekar_*` |
| P2 | `thermal_gradient_max_band_m` | `0.70 m` | `0.40-1.20 m` inferencia | grosor maximo de la zona de gradiente | TN 1736, CFAST | `ghanekar_*` |
| P2 | `thermal_gradient_band_fraction` | `0.35` | `0.15-0.60` inferencia | forma del perfil vertical | TN 1736 | `ghanekar_*` |
| P2 | `floor_cooling_band_fraction` | `0.24` | `0.10-0.40` inferencia | enfriamiento cerca del suelo | tenability papers | `ghanekar_*` |
| P2 | `floor_cooling_band_max_m` | `0.35 m` | `0.15-0.60 m` inferencia | espesor de la banda fresca | tenability papers | `ghanekar_*` |
| P2 | `layer_150c_relax_down_per_s` | `0.35` | `0.1-0.7` inferencia | respuesta de `L150` | tenability papers | `ghanekar_*` |
| P2 | `layer_150c_relax_up_per_s` | `0.03` | `0.01-0.10` inferencia | histéresis de `L150` | tenability papers | `ghanekar_*` |

## Matriz P3 - Parametros que no conviene mover hasta que el modelo exista mejor

| Pri | Parametro o bloque | Actual | Accion recomendada | Motivo |
| --- | --- | --- | --- | --- |
| P3 | `smoke_settling_*` | `0.0` | dejar quieto de momento | es cola post-incendio, no fenomeno principal |
| P3 | `co_postfire_purge_*` | `0.0` | dejar quieto de momento | igual |
| P3 | `fire_spread_*` | activos | no calibrar aun | depende de que humo, termica y ventilacion ya estén bien |
| P3 | `glass_*` | desactivado | activar solo en casos que realmente rompan vidrio | no usarlo como parche de ventilacion |
| P3 | `lower_layer_warming_rate` | `0.012` | revisar si sigue sin uso real antes de tocar | ahora no es driver principal visible |

## Variables que faltan y hay que implementar

| Bloque | Falta | Para que hace falta | Fuente principal |
| --- | --- | --- | --- |
| Gases | `CO2` | tenabilidad, `FED`, HVAC dataset | Ghanekar 2026, Occupant Tenability, HVAC dataset |
| Gases | `H2O` | HVAC dataset y correlaciones de transporte | HVAC dataset |
| Gases | `HCN` | toxicidad real y `FED` | Ghanekar 2026, Occupant Tenability |
| Tenabilidad | `FED` | comparar contra literatura FSRI y tiempos de ocupante | Ghanekar 2026, Occupant Tenability |
| Tenabilidad | `time_to_idlh` | objetivo claro por caso | Ghanekar 2026 |
| Medicion | sondas por `room + height`, idealmente `x/y/z` | comparar contra ubicaciones de muestreo del paper | casi todos |
| HVAC | red de suministro/retorno y `on/off` | replicar experimentos HVAC | HVAC dataset, NISTIR 5227 |
| Geometria | puerta principal exterior explicita | comparacion realista con ensayos residenciales | Ghanekar 2026, FSRI |

## Orden de trabajo recomendado

1. Construir `ghanekar_bedroom_hallway` con ventilacion del ensayo y sonda de pasillo.
2. Barrer solo `P0` y `P1` hasta ajustar `smoke arrival`, `O2`, `CO`, `temp_at_1_8m` y `flashover`.
3. Construir `nist_iso9705_under_vent` para fijar el bloque subventilado.
4. Solo despues tocar `P2`.
5. Implementar `CO2`, `HCN`, `FED` y `HVAC`.

## Riesgos si no seguimos este orden

- compensar una geometria incorrecta con yields o coeficientes termicos
- ajustar `CO` contra un caso cuya ventilacion no corresponde
- usar `L150` como sustituto de `FED` mas alla de su dominio
- “arreglar” un caso rompiendo vidrio o propagando fuego cuando el problema real esta en puertas y ventilacion exterior

