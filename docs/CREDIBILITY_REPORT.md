# Informe de credibilidad de la suite de validación

**Fecha:** 2026-06-11  
**Base:** `reference_checks.json` (381 required)  
**Generado por:** `python tools/credibility_report.py`

---

## 1. Resumen ejecutivo

| Categoría | Required | % |
|---|---|---|
| A_PRIORI | 285 | 74.8% |
| CONSERVATION | 11 | 2.9% |
| FITTED | 11 | 2.9% |
| WINDOWED | 3 | 0.8% |
| VACUOUS | 71 | 18.6% |

**Checks con poder de detección real (A_PRIORI + CONSERVATION):** 296/381 (77.7%)

**Checks con baja credibilidad (FITTED + WINDOWED + VACUOUS):** 85/381 (22.3%)

## 2. Kill rate de mutation testing (R0-2)

**Kill rate global: 0/2 mutantes detectados (0% — objetivo: ≥90%)**

| Mutante | Estado | Fallos/Req | Kill% | Muestra checks muertos |
|---|---|---|---|---|
| M-HRR | **SURVIVED** | 0/0 | 0.0% | - |
| M-YHCN | **SURVIVED** | 0/0 | 0.0% | - |

> **Acción R1:** diseñar ≥1 check nuevo que detecte cada mutante SURVIVED: M-HRR, M-YHCN.

## 3. Los 20 checks required con menor credibilidad

| # | Nombre | Categoría | Razón | actual | expected | tol |
|---|---|---|---|---|---|---|
| 1 | `cfast_t240_o2_depleted` | FITTED | |diff|/tol=0.996 > 0.85 | 0.0632 | 0.085108 | 0.022 |
| 2 | `cfast_closed_t450_co_upper_ppm` | FITTED | |diff|/tol=0.992 > 0.85 | 1326.0 | 731.046 | 600.0 |
| 3 | `cfast_t360_hot_layer_m` | FITTED | |diff|/tol=0.982 > 0.85 | 0.64 | 0.1 | 0.55 |
| 4 | `cfast_hvac_t300_o2` | FITTED | |diff|/tol=0.975 > 0.85 | 0.0981 | 0.07371660000000001 | 0.025 |
| 5 | `cfast_hvac_t180_temp_upper_c` | FITTED | |diff|/tol=0.962 > 0.85 | 182.65 | 259.591 | 80.0 |
| 6 | `cfast_t350_hot_layer_m` | FITTED | |diff|/tol=0.940 > 0.85 | 0.57 | 0.1 | 0.5 |
| 7 | `cfast_hvac_t450_o2` | FITTED | |diff|/tol=0.932 > 0.85 | 0.0949 | 0.052955300000000004 | 0.045 |
| 8 | `ghanekar_kitchen_far_hall_fed_1_0_s` | FITTED | |diff|/tol=0.925 > 0.85 | 740.583333333391 | 624.0 | 126.0 |
| 9 | `cfast_chain_r2_o2_t600_o2` | FITTED | |diff|/tol=0.924 > 0.85 | 0.1698 | 0.119003 | 0.055 |
| 10 | `cfast_chain_r2_o2_t480_o2` | FITTED | |diff|/tol=0.874 > 0.85 | 0.1838 | 0.135705 | 0.055 |
| 11 | `cfast_closed_t120_pressure_pa` | FITTED | |diff|/tol=0.852 > 0.85 | 1192.38 | 1022.07 | 200.0 |
| 12 | `cfast_2r_r0_rmse_temp_upper_c` | WINDOWED | note matches /t=\[0,\s*\d+\]/ | 45.63823004066266 |  |  |
| 13 | `cfast_hvac_rmse_temp_upper_c` | WINDOWED | note matches /t=\[0,\s*\d+\]/ | 51.85683912133094 |  |  |
| 14 | `cfast_hvac_rmse_co_upper_ppm` | WINDOWED | note matches /t=\[0,\s*\d+\]/ | 247.1129853755119 |  |  |
| 15 | `cfast_supr_temp_t120_temp_upper_c` | VACUOUS | tol/|expected|=0.512 > 0.5 | 47.06 | 78.1626 | 40.0 |
| 16 | `cfast_closed_t210_co_upper_ppm` | VACUOUS | tol/|expected|=1.008 > 0.5 | 1046.0 | 594.979 | 600.0 |
| 17 | `cfast_slow_t1200_o2` | VACUOUS | tol/|expected|=0.713 > 0.5 | 0.0522 | 0.0350666 | 0.025 |
| 18 | `cfast_closed_t300_co_upper_ppm` | VACUOUS | tol/|expected|=0.908 > 0.5 | 1020.0 | 660.5329999999999 | 600.0 |
| 19 | `cfast_hvac_t180_co_upper_ppm` | VACUOUS | tol/|expected|=1.314 > 0.5 | 593.0 | 380.376 | 500.0 |
| 20 | `cfast_2r_hall_t120_temp_upper_c` | VACUOUS | tol/|expected|=0.987 > 0.5 | 38.58 | 60.7964 | 60.0 |

## 4. Overrides de física del motor en casos de validación (40)

Regla R1-3: ningún caso bajo `sim/validation/` debe contener claves de parámetros del motor (solo inputs del escenario).

| Caso | Clave | Valor |
|---|---|---|
| `carbon_balance_creation` | `background_species_exchange_kg_s_m2` | `0.0` |
| `carbon_balance_loss` | `background_species_exchange_kg_s_m2` | `0.0` |
| `cfast_bedroom_closed_door` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_corridor_chain` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_corridor_chain` | `phase2h_lower_cf_drain_coeff` | `0.56` |
| `cfast_door_close_midfire` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_hvac_o2l_g000` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_hvac_o2l_g100` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_hvac_residential` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_long_burnout_3600s` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_pool_fire_open` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_post_flashover_vented` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_r0_window_360` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_single_room_closed` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_slow_growth_sealed` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_suppression_water` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_two_floor_stairwell` | `two_zone_convective_heat_multiplier` | `1.18` |
| `cfast_two_room_door_open` | `outside_open_upper_heat_boost` | `0.75` |
| `cfast_two_room_door_open` | `phase2h_lower_cf_drain_coeff` | `0.56` |
| `cfast_two_room_door_open` | `doorway_o2_upper_routing_gain` | `1.0` |
| `cfast_window_break_t180` | `outside_open_upper_heat_boost` | `0.75` |
| `fds_simple_house_calibrated` | `hot_gas_species_carry_fraction` | `0.9` |
| `fds_simple_house_calibrated` | `background_species_exchange_kg_s_m2` | `0.032` |
| `fds_simple_house_default` | `hot_gas_species_carry_fraction` | `0.25` |
| `fds_simple_house_default` | `background_species_exchange_kg_s_m2` | `0.25` |
| `fed_thermal_layer_smoke_only` | `background_species_exchange_kg_s_m2` | `0.0` |
| `ghanekar_bedroom_hallway` | `background_species_exchange_kg_s_m2` | `0.009` |
| `ghanekar_bedroom_hallway` | `hot_gas_species_carry_fraction` | `0.13` |
| `ghanekar_bedroom_hallway` | `outside_open_upper_heat_boost` | `0.2` |
| `ghanekar_kitchen_living_room` | `fire_co_vent_limited_multiplier` | `110.0` |
| `ghanekar_kitchen_living_room` | `background_species_exchange_kg_s_m2` | `0.02` |
| `ghanekar_kitchen_living_room` | `hot_gas_species_carry_fraction` | `0.85` |
| `ghanekar_kitchen_sweep_v1` | `background_species_exchange_kg_s_m2` | `0.02` |
| `ghanekar_kitchen_sweep_v1` | `hot_gas_species_carry_fraction` | `0.3` |
| `ghanekar_kitchen_sweep_v2` | `background_species_exchange_kg_s_m2` | `0.02` |
| `ghanekar_kitchen_sweep_v2` | `hot_gas_species_carry_fraction` | `0.3` |
| `ghanekar_kitchen_sweep_v3` | `background_species_exchange_kg_s_m2` | `0.02` |
| `ghanekar_kitchen_sweep_v3` | `hot_gas_species_carry_fraction` | `0.3` |
| `ghanekar_kitchen_v2` | `background_species_exchange_kg_s_m2` | `0.02` |
| `ghanekar_kitchen_v2` | `hot_gas_species_carry_fraction` | `0.3` |

## 5. Recomendaciones prioritarias para R1

1. **Reclasificar 11 checks FITTED** a KNOWN_DEVIATION: revertir tolerancias a los valores a priori de §6.2 de la auditoría y reclasificar como Nivel III con ficha de causa.

2. **Endurecer o eliminar 71 checks VACUOUS**: los 2 con ratio > 5× (hot_layer_m) deben reformularse. Los checks de mínimo trivial (min: 1 ppm HCN) deben reemplazarse por bandas bilaterales.

3. **Publicar RMSE de ventana completa** en los 3 checks WINDOWED: añadir el RMSE total como métrica no-gating además del RMSE truncado.

4. **Linter R1-3**: activar la comprobación de overrides de física como check pre-commit (los 40 overrides detectados deben eliminarse antes de R2).

5. **Medir kill rate real** ejecutando `python tools/mutation_audit.py` — cada mutante SURVIVED define exactamente qué check diseñar.

---

*Generado por `tools/credibility_report.py` — R0-4 de la hoja de ruta R0–R5.*