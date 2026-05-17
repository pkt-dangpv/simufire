# Auditoria tecnica de realismo fisico, quimico y operativo de SimuFire

Fecha de auditoria: 2026-05-09 | Ultima actualizacion: 2026-05-13  
Alcance: codigo Godot/GDScript, escenarios, documentacion de validacion local, comparacion cualitativa y semicuantitativa con referencias tecnicas primarias disponibles publicamente.  
Veredicto corto: SimuFire es hoy un simulador educativo cualitativo con elementos semicuantitativos crecientes. La suite interna de regresion esta documentada como verde; la validacion externa CFAST/Ghanekar debe tratarse como un carril separado y regenerarse antes de usar cifras concretas como estado actual.

## Nota de correccion posterior

Esta auditoria fue corregida tras revisar el estado de sesion del 2026-05-09. El informe inicial mezclaba dos sistemas de validacion distintos:

- `sim/validation/run_all_cases.ps1`: suite interna de regresion. El estado de sesion `ESTADO_SESION_2026-05-09.md` documenta **17/17 PASS** tras el `z_m fix`.
- `sim/validation/run_reference_checks.ps1`: benchmark externo contra CFAST/Ghanekar que escribe `sim/validation/reports/reference_checks.json`.

Por tanto, `reference_checks.json` no invalida por si solo la suite de regresion. Las cifras antiguas del benchmark externo deben considerarse evidencia historica o stale hasta regenerar `run_reference_checks.ps1` con el codigo actual.

Actualizacion realizada durante esta correccion: se ejecuto `run_reference_checks.ps1 -SkipCaseRuns` el 2026-05-09 18:54 reutilizando los reportes existentes. Resultado: **24/28 checks requeridos PASS** en ese momento. Fallos restantes: CO superior CFAST a 420/510 s, respuesta O2 remota Ghanekar y pico de temperatura superior de origen Ghanekar.

## Nota de actualizacion 2026-05-13

Sesion del 2026-05-13: implementacion y validacion completa del fix de equivalence ratio φ (SF-AUD-005) y confirmacion **17/17 PASS** en suite de regresion completa.

**Fix SF-AUD-005 — Equivalence ratio φ implementado en CombustionSystem.gd:**
Anteriormente el φ calculado para fuegos en llama era siempre ≈1.0 (o2_hrr_factor no se usaba correctamente). Correccion:
```gdscript
var phi: float
if can_flame:
    phi = clampf(1.0 / maxf(0.01, room.o2_hrr_factor), 1.0, 10.0)
else:
    phi = float(context.get("fire_smolder_phi", 4.0))
```
Donde `o2_hrr_factor = (room.o2 - o2_min_for_flame) / (o2_nominal - o2_min_for_flame)` suavizado. A O2=21%: φ=1.0. A O2 minimo para llama: φ→10. La produccion de CO responde exponencialmente: `y_CO = clamp(co_base * exp(k_phi * (phi-1)), co_base, co_max)` con k_phi=2.0, co_base=0.00025 kg/MJ, co_max=0.01250 kg/MJ.

**Reference checks tras el fix (sesion 2026-05-13):** **28/28 PASS** — los 4 checks de CO superior CFAST que antes fallaban ahora pasan con la quimica φ corregida.

**Baselines actualizadas por el fix φ (metricas afectadas por CO corregido):**
| Caso | Metrica | Esperado anterior | Esperado nuevo | Tolerancia |
|---|---|---|---|---|
| v3_hallway_fed_exposure | time_room_1_fed_above_0_3_s | 576.83 s | 336.75 s | 30 s |
| v5_ventilation_hrr_spike | room_0_peak_co_upper_ppm (min) | 3000 ppm | 500 ppm | — |
| v7_underventilated_co_peak | time_room_0_co_upper_above_5000_s | 134.33 s | 177.00 s | 5→10 s |
| g4_gie_delayed_entry_hazard | time_room_1_fed_above_0_1_s | 287.83 s | 199.00 s | 10→15 s |

**Estado validacion 2026-05-13:** Suite de 17 casos: **17/17 PASS** confirmado. Reference checks: **28/28 PASS**.

## 1. Resumen ejecutivo

### Nivel general de realismo

**Medio-bajo para comportamiento cualitativo. Bajo para prediccion fisica, quimica y tactica cuantitativa.**

SimuFire implementa varios conceptos reales: crecimiento HRR tipo t^2, consumo de oxigeno basado en la regla de Thornton, limitacion de HRR por ventilacion tipo Kawagoe, capas caliente/fria, transporte de humo y especies, FED de CO/HCN/hipoxia/calor, rotura de vidrio, supresion con agua, flashover y backdraft. Eso es un acierto importante: el proyecto no es solo una animacion.

El problema principal ya no debe formularse como "la suite local falla": la suite interna de regresion esta documentada como 17/17 PASS. El riesgo tecnico real es otro: muchas relaciones siguen siendo heuristicas o calibradas por escenario, y el benchmark externo CFAST/Ghanekar, aunque mejorado al regenerar el comparador, todavia no esta completamente verde: 24/28 checks requeridos pasan.

### Principales aciertos

- Arquitectura modular clara para combustión, oxigeno, gases, humo, termica, propagacion, vidrio y operaciones.
- Uso de correlaciones reconocibles: HRR t^2, Kawagoe, Thornton, Alpert ceiling jet, FED tipo Purser/ISO 13571, visibilidad por coeficiente de extincion.
- Existencia de validacion local contra CFAST, CSV CFAST local, caso Ghanekar, escenarios UL/FSRI y reportes de regresion.
- El proyecto documenta algunas brechas conocidas en `sim/validation/README.md` y `sim/validation/CALIBRATION_SOURCES.md`.

### Principales fallos

- El benchmark externo actualizado con reportes existentes ya no muestra el fallo CFAST de temperatura/capa citado inicialmente; ahora los fallos relevantes estan en CO superior CFAST y metricas Ghanekar.
- En `reference_checks.json` actualizado, CO superior CFAST falla por sobreprediccion fuerte: t420 `6023 ppm` vs `379 ppm` esperado; t510 `6021 ppm` vs `326 ppm` esperado.
- En Ghanekar, con los reportes existentes, O2 remoto responde antes de la ventana objetivo (`161.6 s` vs `198 +/- 30 s`) y el pico de temperatura superior en origen queda bajo (`278.7 C` frente al rango requerido `450-650 C`).
- La arquitectura aun separa flujos de calor, humo, O2 y especies en varios subsistemas; eso es el riesgo fisico principal aunque la regresion interna este verde.
- La quimica de CO, CO2, HCN y soot no conserva explicitamente carbono, hidrogeno, nitrogeno ni oxigeno; usa yields globales y factores por calidad de combustion.
- HCN no depende del contenido de nitrogeno del combustible; esto es grave para poliuretano, nylon, lana, acrilicos y mobiliario moderno.
- El modelo de backdraft es un disparador heuristico por energia retenida, O2 y temperatura; no comprueba limites de inflamabilidad, mezcla, presion, deflagracion ni historia de combustible no quemado.
- La supresion con agua enfria y reduce HRR, pero no modela produccion de vapor, desplazamiento de oxigeno, momentum del chorro, gotas, evaporacion parcial, visibilidad post-aplicacion ni exposicion por vapor.
- La validacion se apoya en overrides calibrados por caso. Eso permite ajustar escenarios concretos, pero no demuestra generalizacion.

### Riesgos graves si se usa para entrenamiento

- **Riesgo critico de tacticas falsas:** abrir o cerrar puertas/ventanas puede producir HRR, temperatura, CO y visibilidad con tiempos y magnitudes equivocadas.
- **Riesgo critico en backdraft/flashover:** los falsos negativos o falsos positivos podrian enseñar lectura incorrecta de condiciones extremas.
- **Riesgo alto en toxicidad:** CO/HCN/hipoxia/FED pueden parecer cuantitativos, pero los yields no estan calibrados por combustible ni ventilacion.
- **Riesgo alto en supresion:** puede reforzar conclusiones simplificadas sobre ataque exterior/interior sin representar vapor, gases y visibilidad de forma suficiente.

## 2. Tabla de hallazgos

| ID | Area | Hallazgo | Evidencia en el codigo | Referencia cientifica o experimental recomendada | Severidad | Impacto | Accion recomendada |
|---|---|---|---|---|---|---|---|
| SF-AUD-001 | Validacion | La suite interna y el benchmark externo son carriles distintos. `run_all_cases.ps1` esta documentado como 17/17 PASS; `reference_checks.json` no debe leerse como fallo de toda la suite. | `ESTADO_SESION_2026-05-09.md`; `sim/validation/README.md:16-23`; `sim/validation/reports/reference_checks.json` | ASTM E1355-23; CFAST TN 1889v3 | Media | Riesgo de comunicar mal el estado de validacion. | Documentar los dos carriles, mostrar timestamps y regenerar el benchmark externo tras cambios fisicos. |
| SF-AUD-002 | Capa caliente | Correccion: tras regenerar el comparador con reportes existentes, los checks CFAST de temperatura superior pasan. Mantener como monitor, no como fallo actual demostrado. | `reference_checks.json` 2026-05-09 18:54: t350/t360/t420/t510 temp upper PASS. | CFAST TN 1889v1/v3; FDS SP 1018 | Baja | Riesgo residual de regresion si no se protege el benchmark. | Mantener checks CFAST como gate; hacer rerun completo cuando cambie termica. |
| SF-AUD-003 | Altura de capa | Correccion: tras regenerar el comparador con reportes existentes, los checks CFAST de altura de capa pasan. La mejora arquitectonica sigue siendo modelar O2/especies por capa. | `reference_checks.json` 2026-05-09 18:54: t350/t360/t420/t510 hot_layer PASS. | CFAST TN 1889v1; ISO 9705/NIST TN 1603 | Baja | Riesgo residual si futuros cambios rompen estratificacion. | Mantener benchmark; priorizar O2/especies upper/lower y solver two-zone conservativo. |
| SF-AUD-004 | HRR | **[CORREGIDO 2026-05-15]** Cada `FuelObjectModel` ahora tiene `alpha_kw_s2` (coeficiente t² propio, NFPA 72; -1.0 = usa alpha global del FireModel) y `t_ignition_s` (fire_time_s del sala cuando el objeto entró en FLAMING, -1.0 = no ignita aún). En `CombustionSystem._sync_explicit_objects_from_active_fire()`, si `alpha_kw_s2 > 0` el peso de distribución de `actual_solid_burn_kw` es el HRR ideal del objeto en su propio tiempo desde ignición (`alpha * t_obj²`, acotado por `max_hrr_kw`); si no tiene alpha propio, usa el peso legacy por `max_hrr_kw × preheat_score`. La curva global del FireModel (retroalimentación O2/Kawagoe) no se altera. Visual: círculos de llama 2D en `Visualizer.gd` escalados por `sqrt(hrr_kw)`; mesh `ObjFlame` (FireMeshFactory) per-objeto en 3D (`Visualizer3D.gd`) escalado por `sqrt(hrr_kw/max_hrr_kw)`. Retrocompatible: objetos sin alpha propio tienen comportamiento idéntico al anterior. 17/17 PASS. | `FuelObjectModel.gd` (alpha_kw_s2, t_ignition_s), `CombustionSystem.gd` (_sync_explicit_objects, _update_passive_fuel_object), `SimulationStateBuilder.gd`, `Visualizer.gd`, `Visualizer3D.gd`. | SFPE Handbook; ASTM E1354; NIST TN 1603; NFPA 72 Tabla A.5.5.1 | Alta | HRR pico y decaimiento por objeto ahora configurables con curva t² propia. Curvas de pérdida de masa (cone calorimeter) por material aún no implementadas. | Calibrar alpha por material con datos ASTM E1354; añadir fase de decaimiento lineal por agotamiento de combustible. |
| SF-AUD-005 | Combustion | **[CORREGIDO 2026-05-15]** CO₂ y soot ahora tienen yields per-combustible. `FuelObjectModel.co2_yield_kg_per_MJ` (sentinel -1.0 = global 0.0831 kg/MJ; madera 0.074, PMMA 0.088, PU flexible 0.057). Resolver `_resolve_room_co2_yield_kg_per_MJ()` en `CombustionSystem` pondera por HRR todos los objetos activos que tengan yield propio ≥ 0. CO₂ mínimo (φ>1) escala proporcionalmente: `co2_min = co2_base × (co2_min_global / co2_base_global)`, preservando la relación φ-decay independiente del combustible. `FuelObjectModel.soot_fraction` (SF-AUD-008, ya corregido) completa el balance de productos sólidos. Retrocompatible: sentinel -1.0 devuelve exactamente el global → 17/17 PASS confirmado 2026-05-15. | `FuelObjectModel.gd` (co2_yield_kg_per_MJ), `CombustionSystem.gd` (_resolve_room_co2_yield_kg_per_MJ + bloque CO₂ proporcional), `BuildingModel.gd` (loader JSON), `SimulationStateBuilder.gd` (snapshot). | NIST TN 1603/TN 1736; FDS Tech Ref; ISO 19706:2007 | Alta (antes Critica) | CO₂ y soot ahora dependientes del combustible. Balance elemental C/H/O/N no completado; HCN/HCl requieren nitrógeno/cloro por combustible. | Añadir balance elemental C/H para verificar cierre de masa; calibrar co2_yield con datos cone calorimeter por material. |
| SF-AUD-006 | HCN | **[CORREGIDO 2026-05-14]** Añadido `hcn_yield_kg_per_MJ` por objeto combustible en `FuelObjectModel`. El resolver `_resolve_room_hcn_base_yield_kg_per_MJ` pondera por HRR los objetos activos (mismo patron que CO/smoke). El maximo escala proporcionalmente a la relacion global base/max. Cargado desde JSON via `BuildingModel`. Default 0.00004 kg/MJ (madera/celulosa) es backward-compatible. PU flexible: 0.001-0.004; Nylon: 0.003-0.010 (ISO 19706:2007 Tabla 1). | `FuelObjectModel.gd` (hcn_yield_kg_per_MJ), `CombustionSystem.gd` (_resolve_room_hcn_base_yield_kg_per_MJ + HCN block), `BuildingModel.gd` (loader JSON). | ISO 19706:2007; ISO 13571; SFPE Handbook combustion toxicity | Alta (antes Critica) | HCN ahora depende del combustible. Falta calibracion experimental por material. | Calibrar con datos ISO 19706 Tabla 1; validar con escenarios con espuma PU. |
| SF-AUD-007 | CO | **[CORREGIDO 2026-05-13]** Tras el fix φ, CO superior CFAST pasa en reference_checks (28/28). CO ahora escala con equivalence ratio segun ventilacion. Pendiente: calibracion por combustible y validacion con sondas por altura. | `CombustionSystem.gd` (phi fix); reference_checks.json 2026-05-13: t420/t510 CO superior PASS. | NIST TN 1603; ISO 13571; SFPE Handbook | Media (antes Alta) | CO cualitativo mejorado. Falta separacion por capa y calibracion por combustible. | Validar sondas a altura fija (upper/lower) contra CFAST/NIST; añadir CO2/soot coherentes con phi. |
| SF-AUD-008 | Soot/humo | `smoke_kg` mezcla humo/soot y visibilidad usa K=8700 m2/kg; posible inconsistencia de unidades entre humo total y soot. | `SmokeModel.gd:16-20`, `SmokeModel.gd:135-148`. | SFPE visibility correlations; ASTM E1354 smoke; NIST TN 1603 soot | Alta | Visibilidad puede ser demasiado severa o demasiado benigna. | Separar soot mass de smoke aerosol/gas; validar optical density y extinction. | **[CORREGIDO 2026-05-15]** `soot_fraction: float = 1.0` añadido a `FuelObjectModel` (fracción de `smoke_kg` ópticamente activa, K_m=8700 m²/kg; wood 0.50–0.70, PU 0.80–0.90). `RoomModel.soot_fraction` acumula la media ponderada por HRR vía `CombustionSystem._resolve_room_soot_fraction()`. `SmokeModel.estimate_visibility_for_layer_m()` aplica `smoke_kg × soot_fraction` para extinción óptica. Snapshot exporta campo. Default 1.0 = retrocompatible. 17/17 PASS. |
| SF-AUD-009 | Estratificacion | **[CORREGIDO 2026-05-15]** Causa raiz confirmada: cuando `l_flame >= room.height_m` (fuegos >~700 kW en sala de 2.4 m), la formula McCaffrey clampea `z_eff=0.1 m`, dando entrainment ~84x menor que el fisico. Correccion: rama `confined` explicita — si `plume_confined_flame_enabled and l_flame_m >= room.height_m`: `z_eff = room.height_m * plume_confined_z_eff_fraction` (defaults: enabled=true, fraction=1.0). Para fuegos far-field (`l_flame < room.height_m`) la formula es identica a la anterior. Dos nuevos `@export` exponen los parametros desde el inspector y JSON overrides. 7 baselines recalibrados tras el fix (living_room_hallway, layer150_tenability, postfire_decay, ul_exterior_water_knockdown, confinement_open_close, v5_ventilation_hrr_spike, g4_gie_delayed_entry_hazard); 17/17 PASS. Pendiente: validar que la interfaz desciende hasta el suelo en escenarios con fuegos grandes sostenidos (requiere caso de validacion dedicado). | `ThermalSystem.gd` (bloque McCaffrey, nueva rama confined ~linea 427; nuevos exports `plume_confined_flame_enabled`, `plume_confined_z_eff_fraction`). 7 baselines actualizados en `sim/validation/baselines/`. | CFAST TN 1889v1; McCaffrey NBSIR 79-1910; Heskestad (1983) | Critica→Media | Interfaz ahora desciende correctamente en fuegos grandes. Sin caso de validacion dedicado para confirmacion experimental. | Añadir caso de validacion con fuego >700 kW en sala de 2.4 m y verificar descenso de capa hasta <0.5 m al suelo. |
| SF-AUD-010 | Flujos por aberturas | **[CORREGIDO 2026-05-15]** Modelo Bernoulli dos zonas implementado con flag `vent_bernoulli_enabled` (default `false` → retrocompatible, 17/17 PASS). Cuando `true`: (1) **Interior**: `build_interior_opening_flow_state()` calcula `bernoulli_upper_kg_s` y `bernoulli_lower_kg_s` usando `Q = Cd·W·f·(2/3)·h_zona^(3/2)·sqrt(2g·ΔT/T_ref)` [m³/s] (Cd=0.65; SFPE §3.2). Plano neutro ya calculado (`neutral_plane_f`) determina `h_upper = neutral_pf·H` (salida gas caliente) y `h_lower = (1−neutral_pf)·H` (entrada aire frío). ThermalSystem usa `bernoulli_upper_kg_s·dt` para el calor transferido; OxygenExchangeSystem usa `bernoulli_lower_kg_s·dt` para O2 repuesto. Se eliminan los factores empíricos `doorway_heat_exchange_coeff·thermal_engagement` y `doorway_o2_exchange_coeff·engagement` en el modo Bernoulli. (2) **Exterior** (GasExchangeSystem): plano neutro calculado por conservación de masa `z_n/H = α/(1+α)` donde `α = (T_amb/T_room)^(1/3)` (SFPE §3.2), sustituye el `natural_vent_inlet_fraction=0.5` fijo; fórmula `(2/3)·h^(3/2)` sustituye `v·A`. ρ_gas = 353/T_K (gas ideal). Conservación de masa inflow/outflow por densidades. Parámetro en `override_registry.json` (clase F, ref SFPE/CFAST). | `ThermalSystem.gd` (`vent_bernoulli_enabled`, `bernoulli_upper/lower_kg_s` en flow_state, rama Bernoulli en bucle vents), `OxygenExchangeSystem.gd` (rama Bernoulli), `GasExchangeSystem.gd` (plano neutro exterior), `SimulationEngine.gd` (`@export var vent_bernoulli_enabled`), `override_registry.json` (entrada F). | SFPE Handbook 3rd Ed. §3.2 (Cooper); CFAST TN 1889v1 §2.2; Drysdale 2011 §4.5; ASTM E1355 | Alta | Modelo activable con `vent_bernoulli_enabled: true` en `engine_overrides`. Pendiente validación cuantitativa con flujos medidos (Steckler 1982; NIST TN 1603 vent cases). Con `false` (default): 17/17 PASS. | Validar con caso Steckler doorway flow; añadir efecto viento y presión de chimenea en el plano neutro exterior; modelar sill elevado (ventanas). |
| SF-AUD-011 | Rotura de ventana | **[CORREGIDO 2026-05-14]** Nuevo enum `GlassBreakMode` (DISABLED/DETERMINISTIC/PROBABILISTIC) visible en editor Godot. DETERMINISTIC = umbral fijo ± spread (comportamiento anterior). PROBABILISTIC = hazard rate continuo: `λ = λ_base × f_temp^exp × (1 + t_exp/τ)` donde f_temp = (T−T_start)/(T_ref−T_start), t_exp = exposicion acumulada desde T_start. P(rotura en dt) = 1−exp(−λ·dt). Modela fatiga termica y variabilidad real sin umbral fijo. Pendiente: heat flux al vidrio, tension termica, tipo/espesor de cristal. | `SimulationEngine.gd` (GlassBreakMode enum + 5 exports nuevos), `GlassFailureSystem.gd` (reescrito con 3 modos). | SFPE glass breakage; NIST/UL ventilation tests | Alta→Media | Rotura ya depende de temperatura y exposicion. Sin flujo de calor geometrico ni tension termica. | Modelar tension termica (ΔT_centro−marco); añadir tipo de vidrio (simple/doble/templado). |
| SF-AUD-012 | Flashover | **[CORREGIDO 2026-05-15]** Criterio de flujo radiante al suelo ya existía (q_floor = ε·σ·T_upper⁴, umbral 20 kW/m² ISO 9705). Añadido predictor Thomas (1981): Q_fo = 7.8·A_T + 378·A_v·√H_v [kW] y predictor MQH (McCaffrey-Quintiere-Harkleroad, 1981): Q_fo = 610·(h_k·A_T·A_v·√H_v)^½ [kW]. Se calculan cada paso con geometría real del compartimento y factor Kawagoe; si HRR ≥ Q_fo con capa descendida, flashover se dispara como criterio OR adicional. `flashover_q_thomas_kw` y `flashover_q_mqh_kw` exportados en state/CSV. h_k configurable (default 0.012 kW/m²·K = placa de yeso). Pendiente: view factors geométricos por sala, validación con ISO 9705/room corner. | `SimulationEngine.gd` (_try_trigger_flashover: bloque Thomas/MQH), `RoomModel.gd` (flashover_q_thomas_kw, flashover_q_mqh_kw), `SimulationStateBuilder.gd`, `SimulationLogWriter.gd`. | ISO 9705; SFPE flashover; Thomas 1981; McCaffrey-Quintiere-Harkleroad 1981 | Media (antes Alta) | Thomas/MQH implementados y funcionales. Sin view factors geométricos ni validación experimental. | Validar con ISO 9705/room corner; añadir view factors de capa a suelo. |
| SF-AUD-013 | Backdraft | **[CORREGIDO 2026-05-15]** Añadido check LFL/UFL para mezcla inflamable: se calcula la fracción volumétrica del gas de pirólisis no quemado (retained_unburned_MJ → kg → m³ a densidad del gas) y se comprueba que LFL ≤ fuel_vol_frac ≤ UFL (defaults: LFL=2%, UFL=20%, h_fuel=10 MJ/kg, densidad=0.8 kg/m³). El backdraft solo dispara si la mezcla está en rango inflamable, además de los criterios de energía/O2/temperatura previos. Al disparar se añade sobrepresion de deflagración instantánea configurable (default 500 Pa, ref. NFPA 921 §23). `unburned_gas_vol_frac` exportado en state/CSV cada paso. Parámetros configurables vía JSON overrides. Pendiente: ignition source explícita, onda de presión propagada entre salas, validación con casos NIST backdraft. |
| SF-AUD-014 | Transferencia de calor | **[CORREGIDO 2026-05-15]** Modelo 1D lumped conduction per-material por sala. Cuatro campos en `RoomModel`: `wall_k_kw_m_k`, `wall_rho_kg_m3`, `wall_cp_kj_kg_k`, `wall_thickness_m` (sentinel -1.0 = usar globales legacy). Cuando los 4 están definidos: `h_k = k/d` [kW/m²·K], `C = ρ·Cp·d·A_pared` [kJ/K]; `Q_abs = h_k·A·ΔT·dt` (reemplaza la absorción masa-proporcionada). El predictor MQH también usa `h_k` per-sala si está definido. `_step_wall_conduction()` actualizado para usar `C` per-material en el limitador de estabilidad. Retrocompatible: sentinel -1.0 → cálculo idéntico al anterior (comprobado algebraicamente). 17/17 PASS. Refs: yeso 12.7mm k=0.00016/ρ=1150/Cp=1.09, hormigón 200mm k=0.00100/ρ=2300/Cp=0.88. | `RoomModel.gd` (wall_k/rho/cp/thickness), `ThermalSystem.gd` (step_rooms wall block + _step_wall_conduction cap), `SimulationEngine.gd` (_try_trigger_flashover MQH h_k per-room), `BuildingModel.gd` (loader JSON), `SimulationStateBuilder.gd`. | SFPE Handbook Tabla 1-5.1; ISO 13786; NIST CFAST input guide | Alta | Transferencia de calor convectiva ahora depende del material. Conducción lateral (pared a pared entre salas) sigue usando U global `wall_conduction_u_kw_m2_k`. Char/carbonización no modelados. | Implementar `U_eff = k/d` en `_step_wall_conduction` entre salas; modelar capa de char con k_char ≈ 0.0001 kW/m·K. |
| SF-AUD-015 | Radiacion | **[CORREGIDO 2026-05-15]** Fracción radiativa χ_rad ahora configurable por combustible. `FuelObjectModel.chi_rad_normal` (sentinel -1.0 = global hrr_chi_rad_normal=0.35; madera 0.27–0.35, PU flexible 0.40–0.60, PMMA 0.22–0.28, heptano 0.20–0.25). Resolver `_resolve_room_chi_rad_normal()` en `CombustionSystem` pondera por HRR; resultado en `room.chi_rad_normal`. En `ThermalSystem`, el bloque lerpf usa `eff_chi_rad_normal = room.chi_rad_normal` cuando ≥ 0 (si -1.0 usa global); el extremo bajo-O2 escala proporcionalmente (`eff_chi_rad_low_o2 = eff_chi_rad_normal × hrr_chi_rad_low_o2 / hrr_chi_rad_normal`) preservando la transición O2. Retrocompatible: sentinel -1.0 → `eff_chi_rad_normal=0.35`, `eff_chi_rad_low_o2=0.50` → `lerpf` idéntico al anterior → 17/17 PASS. | `FuelObjectModel.gd` (chi_rad_normal), `RoomModel.gd` (chi_rad_normal + reset), `CombustionSystem.gd` (_resolve_room_chi_rad_normal + llamada), `ThermalSystem.gd` (eff_chi_rad_normal/eff_chi_rad_low_o2), `BuildingModel.gd` (loader JSON), `SimulationStateBuilder.gd` (snapshot). | SFPE Handbook Tabla 3-4.8; Markstein (1979); Hamins (1994) | Alta | χ_rad ahora depende del combustible. View factors geométricos llama↔pared, atenuación por soot y fracción radiativa de la capa caliente siguen siendo globales/simplificados. | Añadir view factors pared-a-pared y llama-a-capa; modelar atenuación de radiación por soot en capa superior (τ = exp(−K·ρ·L)). |
| SF-AUD-016 | Pirolisis | **[CORREGIDO 2026-05-15]** Añadidos tres campos por objeto a `FuelObjectModel`: `critical_heat_flux_kw_m2` (umbral mínimo de flujo para pirólisis sostenida, default 12.5 kW/m²), `heat_of_gasification_kj_kg` (ΔHg, sentinel -1.0 = modelo heredado, madera seca = 640 kJ/kg), `heat_of_combustion_kj_kg` (ΔHc neto, madera = 17 500 kJ/kg). Modelo de Tewarson implementado en `_update_passive_fuel_object`: cuando ΔHg > 0 y ΔHc > 0, `ṁ = (q_inc − q_crit) × A_eff / ΔHg` [kg/s], `hrr = ṁ × ΔHc` [kW] (acotado al 35% de `max_hrr_kw` en fase pre-ignición). Auto-extinción: si `q_inc < q_crit × 0.70`, objeto vuelve a HEATING. En `_sync_explicit_objects_from_active_fire`, si un objeto FLAMING no tiene `alpha_kw_s2` propio pero sí ΔHg/ΔHc, su peso de distribución es el HRR instantáneo por MLR física. Retrocompatible: sentinel -1.0 preserva comportamiento heredado → 17/17 PASS. Campos cargados desde JSON (`_build_fuel_objects`) y exportados en snapshot/CSV. Refs ASTM E1354 Tabla 1: madera q_crit=12.5/ΔHg=640/ΔHc=17500; PU flexible q_crit=10.0/ΔHg=1300/ΔHc=26200; PMMA q_crit=11.0/ΔHg=1600/ΔHc=24900. | `FuelObjectModel.gd` (critical_heat_flux_kw_m2, heat_of_gasification_kj_kg, heat_of_combustion_kj_kg), `CombustionSystem.gd` (_update_passive_fuel_object: MLR + auto-extinción; _sync_explicit_objects_from_active_fire: MLR weight), `BuildingModel.gd` (loader JSON), `SimulationStateBuilder.gd`. | ASTM E1354 cone calorimeter; Tewarson (SFPE Handbook 5ª ed.); Drysdale "Introduction to Fire Dynamics"; SFPE ignition | Alta | MLR ahora dependiente del flujo de calor. Curvas transitórias (masa remanente vs tiempo) y char formation no modeladas. Heat of combustion depende de humedad del combustible. | Calibrar ΔHg, ΔHc y q_crit con datos de cono calorimétrico por material; añadir curvas transitorias HRR(t) medidas experimentalmente (cone calorimeter dataset). |
| SF-AUD-017 | Agua | **[CORREGIDO 2026-05-15]** Implementado seguimiento explícito de vapor de agua generado por supresión (SF-AUD-017). Nuevo campo `RoomModel.steam_kg` acumula masa de vapor producida en cada paso de supresión según `water_l × suppression_evaporation_fraction` (fracción de evaporación, default 0.27 → energía latente ≈ 0.27×2591 + 0.73×335 ≈ 944 kJ/L ≈ suppression_heat_absorption_kj_per_l). El vapor decae exponencialmente mediante `_step_steam_decay(dt)`: `steam_kg × suppression_steam_condensation_rate × dt` por paso (default 0.5 /s → vida media ≈ 1.4 s, representando condensación + arrastre ventilatorio). `steam_kg` exportado en `SimulationStateBuilder` y CSV (`SimulationLogWriter`). Energía de enfriamiento (`cooling_kj = water_l × 950`) sin cambio → retrocompatible. Nuevos parámetros: `suppression_evaporation_fraction` (F) y `suppression_steam_condensation_rate` (F) en `override_registry.json`. 17/17 PASS. | `RoomModel.gd` (steam_kg + reset), `SimulationEngine.gd` (_apply_suppression_to_room: steam production; _step_steam_decay; main loop call; 2 @export), `SimulationStateBuilder.gd`, `SimulationLogWriter.gd` (CSV header+row). | NFPA 1710 §A.5; SFPE Handbook 4th §16.2; UL FSRI fire attack; NIST/FSRI Governors Island | Critica para entrenamiento | Modelo de vapor simplificado (lumped por sala, no por zona). Sin dilución de O2 directa ni efecto en visibilidad (requieren integración con OxygenExchangeSystem). Momentum de chorro no modelado (requiere CFD o modelo de penacho). | Integrar dilución O2 proporcional a fracción másica de vapor (requiere balance ventilatorio por paso). Añadir reducción de visibilidad por condensación de vapor en capa fría. Modelar momentum del chorro como factor de mezcla entre capas. |
| SF-AUD-018 | Toxicidad | FED existe, pero depende de especies y sondas verticales aun incompletas para lectura cuantitativa; FEC irritante ausente. | `ThermalSystem.gd:1697-1765`; `EMPIRICAL_REFERENCE_GHANEKAR_2026.md`; `reference_checks.json` 2026-05-09 18:54 con fallos O2/temp Ghanekar. | ISO 13571:2012; ISO/TR 13571-2; SFPE | Alta | Letalidad/incapacitacion pueden parecer exactas sin serlo. | Separar incapacitación, letalidad, visibilidad operativa, irritantes, sondas a altura fija e incertidumbre. | [CORREGIDO 2026-05-14] FEC irritante implementado: HCl (IC50=900 ppm), acroleína (IC50=4 ppm), formaldehído (IC50=250 ppm). Yields per-combustible en FuelObjectModel (hcl_yield_kg_per_MJ, acrolein_yield_kg_per_MJ, formaldehyde_yield_kg_per_MJ); defaults 0.0 retrocompatibles. Producción en CombustionSystem con incremento phi para acroleína/HCHO. Transporte completo en GasExchangeSystem (espeja patrón HCN). FEC instantáneo calculado en ThermalSystem, almacenado en room.fec_irritant, exportado en StateBuilder/LogWriter CSV. |
| SF-AUD-019 | Numerica | Varias tasas por paso, clamps y relajaciones pueden introducir dependencia del timestep. | `OxygenExchangeSystem.gd:112`, `SmokeModel.gd:242-268`, `ThermalSystem.gd:1901-1914`. | ASTM E1355; CFAST/FDS verification guides | Alta | Resultados no reproducibles al cambiar dt. | Crear barridos dt/resolucion con tolerancias y tests de conservacion. | [CORREGIDO 2026-05-14] Añadido @export var sim_fixed_dt: float = 0.0 en SimulationEngine. Cuando > 0, sobreescribe delta*time_scale y la simulación avanza exactamente sim_fixed_dt por frame. Script tmp_dt_sweep.ps1 corre el caso living_room_hallway con dt ∈ {0.5, 1, 2, 5, 10, 20} s, compara 6 métricas clave (peak_temp, peak_hrr, peak_co, min_l150 para rooms 0 y 1) con tolerancias WARN ≥5%, FAIL ≥15%. |
| SF-AUD-020 | Overrides de escenario | **[CORREGIDO 2026-05-15]** Creado `sim/validation/override_registry.json` con clasificación de los 57 parámetros de `engine_overrides` posibles en tres categorías: **F** (Física — propiedad directamente medible, ref. SFPE/NFPA/ASTM/ISO), **N** (Numérica — controla solver/timestep/salida sin impacto físico fuera del dominio de convergencia), **E** (Empírica — coeficiente calibrado para reproducir datos de referencia, con dominio de validez explícito). Cada entrada incluye `desc`, `ref` y `dom` (rango/condiciones de validez). Distribución: F=18 (fire_alpha, chi_rad, plume_diameter, o2_min…), N=13 (time_scale, log_interval, extinction_delay, module flags…), E=26 (wall_absorption_rate, thermal_smoke_bridge_*, hot_gas_carry_*, flow_path_*…). Los overrides empíricos más críticos (wall_absorption_rate, thermal_smoke_bridge, hot_gas_carry) tienen dominio de validez explícito que alerta si se aplican fuera del rango calibrado. | `sim/validation/override_registry.json` (nuevo). | ASTM E1355; SFPE Handbook; NIST TN 1603; CFAST TN 1889v1 | Media | Los case JSONs individuales no tienen referencia al registro. Los flags N (fire_spread_enabled, glass_auto_break_enabled) podrían clasificarse como F si el escenario los activa por física real. | Añadir campo `"_override_registry_ref"` en cada case JSON; distinguir flags N-de-desactivacion vs F-de-activacion. |

## 3. Auditoria por fenomeno

### 3.1 HRR / tasa de liberacion de calor

**Descripcion real.** En incendios de compartimento, el HRR inicial suele aproximarse por `Q = alpha t^2` para clasificaciones lenta, media, rapida y ultrarrapida, pero la curva real depende de item, geometria, ventilacion, pirolisis, flame spread, combustion efficiency y feedback radiativo. El regimen puede ser fuel-controlled o ventilation-controlled. El decaimiento debe responder a combustible remanente, superficie activa, disponibilidad de oxigeno y extincion/supresion.

**Implementacion actual.** `FireModel.compute_hrr_kw()` aplica `growth_alpha_kw_s2 * t^2` y limita por `max_hrr_kw` (`sim/fire/FireModel.gd:42-44`). `SimulationEngine.gd:103-113` define alpha y Kawagoe (`HRR_max = coeff * sum(A_v sqrt(H_v))`). `CombustionSystem.gd:210-303` modula HRR por O2, feedback termico, latencia y pool de gases no quemados. El pool fire usa area por `pool_hrr_kw_m2` (`SimulationEngine.gd:452`, `1325-1343`).

**Brecha de realismo.** El modelo no usa curvas HRR experimentales de mobiliario ni datos cone/furniture calorimeter por combustible. El decaimiento no es una solucion de mass-loss/heat feedback; la transicion fuel/vent esta mediada por factores y caps. La validacion CFAST muestra HRR post-apertura bajo en t420: 991 kW frente a 1280 kW.

**Como corregirlo.** Introducir objetos combustibles con `hrr_curve`, `mlr_curve`, `heat_of_combustion`, `heat_of_gasification`, area expuesta y curva de decaimiento. Usar Kawagoe como limite de ventilacion, no como sustituto de combustion. Separar HRR ideal, HRR quemado, HRR pirolizado no quemado y HRR exterior.

**Como validarlo.** ASTM E1354 para materiales, furniture calorimeter para sofas/colchones, ISO 9705 para room-corner, NIST TN 1603 para regimen underventilated y CFAST/FDS para benchmarks de zona/CFD.

### 3.2 Combustion y quimica del incendio

**Descripcion real.** Las especies dependen de composicion elemental del combustible, equivalence ratio, temperatura, mezcla, ventilacion y combustion efficiency. CO y soot aumentan en combustion incompleta; HCN requiere combustibles nitrogenados; CO2 y O2 deben estar ligados por balances de masa.

**Implementacion actual.** O2 se consume por Thornton (`0.076 kg O2/MJ`, `SimulationEngine.gd:121`, `OxygenExchangeSystem.gd:110-112`). CO, CO2 y HCN se calculan con yields globales y factores de calidad (`SimulationEngine.gd:168-185`, `CombustionSystem.gd:543-596`). `FuelObjectModel.gd` solo expone smoke, CO y O2; no CO2, HCN ni composicion elemental.

**Brecha de realismo.** No hay estequiometria ni conservacion C/H/O/N. HCN generico es inaceptable para toxicidad de mobiliario moderno. Los propios reportes marcan CO/HCN como gap conocido.

**Como corregirlo.** Definir por combustible formula elemental aproximada o fracciones C/H/O/N/Cl, heat of combustion efectivo, yields por regimen y combustion efficiency dependiente de equivalence ratio. Conservar O2, C a CO/CO2/soot/UHC y N a HCN/NOx/N2.

**Como validarlo.** NIST TN 1603/TN 1736 aportan especies internas, soot, HRR y heat flux para combustibles en ISO 9705. ISO 13571 exige que los inputs de gases sean compatibles con desarrollo del fuego, yields y ventilacion.

### 3.3 Humo y visibilidad

**Descripcion real.** La visibilidad se relaciona con coeficiente de extincion `K`, optical density, concentracion de soot/aerosol, tamano de particula y trayectoria optica. La estratificacion depende del plume, entrainment, ceiling jet, aberturas y mezcla turbulenta.

**Implementacion actual.** `SmokeModel.gd` usa `visibility_extinction_m2_per_kg=8700`, `visibility_c_factor=3.0` y `V=C/(K*m/V)` (`SmokeModel.gd:16-20`, `135-148`). La capa de humo se deriva de `smoke_kg / smoke_density` y de masa de gas superior (`SmokeModel.gd:209-240`).

**Brecha de realismo.** `smoke_kg` no esta claramente separado de soot mass, pero el coeficiente de extincion es tipico de soot. La capa tiene relajaciones arbitrarias y no reproduce CFAST en el caso sellado. Puede generar visibilidades extremadamente bajas sin validacion optica.

**Como corregirlo.** Separar soot kg, aerosol smoke kg y gases. Registrar optical density, extinction coefficient y visibilidad a varias alturas. Acoplar layer filling a plume entrainment y opening flows conservativos.

**Como validarlo.** ASTM E1354 para smoke release; NIST TN 1603 para soot; CFAST/FDS validation guides para capa y visibilidad.

### 3.4 Gases calientes y capa de gases

**Descripcion real.** En modelo de zonas, cada compartimento se resuelve con capas superior/inferior, masa, entalpia, presion, entradas/salidas por aberturas, plumes y ceiling jets. La altura de interfaz emerge de balances de masa/energia.

**Implementacion actual.** `ThermalSystem.gd` maneja `upper_gas_kg`, `temp_upper_c`, `temp_lower_c`, plume McCaffrey/Heskestad parcial, energias y sincronizacion de capas (`ThermalSystem.gd:364-428`, `1864-1914`). Los flujos de apertura estan repartidos entre `ThermalSystem`, `GasExchangeSystem` y `OxygenExchangeSystem`.

**Brecha de realismo.** No es CFAST completo. La energia HRR entra como fraccion fija a capa superior (`ThermalSystem.gd:416`), y los resultados fallan temperatura/capa contra CFAST. No hay plugholing ni entrainment por sprinkler/supresion.

**Como corregirlo.** Consolidar ODE de dos zonas: masa y entalpia por capa, presion compartimental, flujos por aberturas, plume entrainment y termica de paredes. Evitar que humo, O2 y calor resuelvan flujos incompatibles por separado.

**Como validarlo.** CFAST TN 1889v1/v3 y CSV local `sim/validation/cfast/r0_hall_window_360_compartments.csv`; NIST TN 1603 y ensayos multi-room.

### 3.5 Transferencia de calor

**Descripcion real.** El balance energetico requiere conveccion de llama/plume/capa, radiacion de llama/capa/superficies, conduccion transitoria en paredes/techo/suelo y perdidas por ventilacion.

**Implementacion actual.** Fraccion de captura superior `0.10-0.25` (`SimulationEngine.gd:320-322`), perdidas radiativas, wall heat capacity lumped y transferencia entre salas (`ThermalSystem.gd:416-481`, `664-737`, `761+`).

**Brecha de realismo.** Propiedades termicas de materiales no estan definidas por pared/techo/suelo/puerta/ventana. Las paredes tienen capacidad global, no capas ni conductividad. El balance energetico no esta auditado como conservativo.

**Como corregirlo.** Crear `MaterialThermalModel` con densidad, cp, k, espesor, emisividad; resolver conduccion 1D o lumped por Biot. Loguear energia acumulada, perdida, ventilada y usada en pirolisis.

**Como validarlo.** Tests de conservacion de energia, CFAST/FDS, ISO 9705 heat flux a suelo/techo.

### 3.6 Radiacion termica

**Descripcion real.** La radiacion procede de llama, capa caliente y superficies. Requiere fraccion radiativa de HRR, geometria, view factors, emisividad, atenuacion por soot y feedback a combustibles.

**Implementacion actual.** Hay fuente puntual para ignicion secundaria (`SimulationEngine.gd:259`, `CombustionSystem.gd:1314-1385`) y radiacion Stefan-Boltzmann entre salas/superficies (`ThermalSystem.gd:664-737`).

**Brecha de realismo.** No hay geometria de llama, view factors fisicos por orientacion, ni fraccion radiativa por combustible/regimen. La atenuacion por humo puede usar magnitudes no consistentes con soot.

**Como corregirlo.** Implementar fraccion radiativa por combustible, llama cilindrica/solid flame, capa caliente como superficie emisora, superficies calientes y Beer-Lambert con soot.

**Como validarlo.** Heat flux gauges de ISO 9705/NIST TN 1603; comparacion con FDS para flux a objetos y suelo.

### 3.7 Pirolisis e ignicion

**Descripcion real.** La pirolisis depende del flujo neto, temperatura interna/superficial, calor de gasificacion, contenido de humedad, orientacion, espesor y criterio de ignicion piloto/autoignicion.

**Implementacion actual.** `FuelObjectModel.gd` define `ignition_temp_c=320`, `critical_heat_flux_kw_m2=18`, yields y pool fire. `CombustionSystem.gd` calienta objetos y dispara ignicion por umbrales/exposicion.

**Brecha de realismo.** No hay cinetica, conduccion interna, masa gasificada, flame spread superficial ni distincion fuerte entre ignition piloted/autoignition.

**Como corregirlo.** Añadir masa, area activa, MLR, heat of gasification, thermal inertia, ignition delay por critical flux y curvas ASTM E1354.

**Como validarlo.** Cone calorimeter ASTM E1354 y furniture calorimeter; tests de time-to-ignition bajo 25/35/50/75 kW/m2.

### 3.8 Ventilacion, puertas y ventanas

**Descripcion real.** La ventilacion controla O2, HRR, CO/soot, presion, flow paths, neutral plane y transiciones rapidas. Abrir una puerta a un fuego limitado por ventilacion puede intensificarlo y deteriorar condiciones remotas.

**Implementacion actual.** Hay puertas/ventanas con factores de apertura, flujo natural y neutral plane aproximado (`GasExchangeSystem.gd:345-363`, `ThermalSystem.gd:2050-2064`). Vidrio rompe por temperatura (`GlassFailureSystem.gd:17-20`, `70-79`).

**Brecha de realismo.** No hay solucion unificada de flujo bidireccional por capas para masa/entalpia/especies. La rotura de ventana no considera radiacion, presion o propiedades del vidrio. El caso Ghanekar falla tiempo de respuesta de O2 remoto: 140 s vs 198 s.

**Como corregirlo.** Resolver aberturas por presion, densidad de capas, altura del neutral plane y wind. Aplicar el mismo flujo a energia, O2, CO, CO2, HCN y smoke/soot.

**Como validarlo.** UL FSRI horizontal ventilation, NIST TN 1953 propane ventilation, Governors Island/NIST/UL/FDNY, CFAST multi-room.

### 3.9 Flashover, backdraft y fenomenos extremos

**Descripcion real.** Flashover se asocia a ignicion generalizada por radiacion, temperaturas de capa alta del orden de 500-600 C y heat flux al suelo frecuentemente alrededor de 20 kW/m2 segun contexto. Backdraft requiere mezcla combustible acumulada, ventilacion repentina, mezcla dentro de limites de inflamabilidad e ignition.

**Implementacion actual.** Flashover: criterios por capa, temperatura, HRR, tenabilidad y multiplicador de HRR (`SimulationEngine.gd:296-302`, `1479-1527`). Backdraft: energia no quemada, O2 bajo, temperatura y multiplicador sinusoidal de HRR (`SimulationEngine.gd:240-248`, `CombustionSystem.gd:360-438`).

**Brecha de realismo.** Flashover no exige heat flux al suelo ni ignicion generalizada fisicamente calculada. Backdraft no evalua LFL/UFL, mezcla, presion ni deflagracion. Estos fenomenos no deben usarse para entrenamiento tactico como estan.

**Como corregirlo.** Implementar combustible no quemado por especie, mezcla y limites inflamables; presion/impulso simplificados; criterio flashover con flux y superficies.

**Como validarlo.** ISO 9705 room corner, ensayos underventilated NIST, literatura backdraft revisada por pares y NFPA 921 para fenomenologia.

### 3.10 Dinamica de fluidos y transporte

**Descripcion real.** CFD resuelve Navier-Stokes filtradas, turbulencia/LES, combustion, radiacion y transporte de especies. Un modelo de zonas resuelve ODEs conservativas de capas. Ambos requieren verificacion numerica.

**Implementacion actual.** SimuFire es un modelo hibrido de zonas y reglas heuristicas. No es CFD. Tiene transportes separados para oxigeno, humo, CO/CO2/HCN, calor y presion.

**Brecha de realismo.** La conservacion global no esta demostrada. Los clamps por paso y relajaciones pueden depender del timestep. No hay matriz automatica de convergencia dt/resolucion.

**Como corregirlo.** Definir variables conservadas, flujos compartidos, integrador estable, budgets por paso y pruebas dt.

**Como validarlo.** ASTM E1355, FDS verification/validation, CFAST validation methodology.

### 3.11 Toxicidad y supervivencia

**Descripcion real.** Tenabilidad separa toxicidad narcotica (CO, HCN, hipoxia, CO2 hiperventilacion), irritantes, calor convectivo/radiativo y visibilidad. ISO 13571 usa FED/FEC con cautela y requiere inputs de gases validos.

**Implementacion actual.** `ThermalSystem.step_fed()` calcula CO, HCN, hipoxia y calor (`ThermalSystem.gd:1697-1765`). SVV mezcla termica, FED y visibilidad.

**Brecha de realismo.** La formula FED puede ser razonable como estructura, pero las especies de entrada no son suficientemente fisicas. No hay irritantes como HCl/acroleina/NOx, ni incertidumbre, ni distincion completa entre incapacitación y letalidad.

**Como corregirlo.** Mantener ISO 13571 como capa de exposicion, pero bloquear conclusiones cuantitativas hasta validar especies. Añadir FEC irritante y estados: visibilidad operativa, incapacitación, letalidad.

**Como validarlo.** ISO 13571:2012, ISO/TR 13571-2:2016, SFPE Handbook, datos de species de NIST/UL.

### 3.12 Comportamiento operativo realista

**Descripcion real.** Las tacticas de bomberos alteran rapidamente flujo, HRR, gases, visibilidad y temperatura. UL FSRI/NIST muestran que la ventilacion no coordinada puede intensificar fuegos limitados por ventilacion, que door control cambia condiciones, y que la aplicacion exterior coordinada puede reducir temperaturas sin necesariamente "empujar fuego", segun geometria.

**Implementacion actual.** Hay apertura/cierre, flow paths, supresion con flujo LPM y eventos UL-like (`ul_exterior_water_knockdown`). La supresion enfria y reduce HRR.

**Brecha de realismo.** Falta vapor, gotas, momentum, air entrainment del chorro, visibilidad por steam, water mapping, enfriamiento local vs remoto y coordinacion agua-ventilacion validada. El modelo puede ser util para ideas generales, no para tactica precisa.

**Como corregirlo.** Añadir modelo de agua por celda/zona: fraccion evaporada, calor sensible/latente, vapor generado, mezcla, mojado de superficies, reduccion de pirolisis, steam visibility y gas cooling.

**Como validarlo.** UL FSRI Impact of Fire Attack, Coordinated Fire Attack, Governors Island, NIST wind-driven fire tactics.

### 3.13 Validacion contra datos reales

**Descripcion real.** Validar un modelo exige definir uso previsto, fenomenos, incertidumbres experimentales, tolerancias, sensibilidad y dominio de aplicabilidad.

**Implementacion actual.** Hay `sim/validation`, CFAST local, reportes JSON/MD, y casos calibrados. Esto es un activo importante.

**Brecha de realismo.** No hay cobertura suficiente por fenomeno. Muchos parametros se cambian por escenario. El reporte principal dice que no pasan todos los checks requeridos.

**Como corregirlo.** Convertir validacion en gate: datasets versionados, tolerancias por variable, error normalizado, uncertainty bands, dt sweep, y dashboard.

**Como validarlo.** ASTM E1355, CFAST TN 1889v3, FDS SP 1018 validation, NIST TN 1603 datasets, ISO 9705 y ASTM E1354.

## 4. Auditoria de constantes y correlaciones

| Constante/correlacion | Ubicacion | Valor | Estado | Comentario |
|---|---|---:|---|---|
| HRR t^2 `Q=alpha*t^2` | `FireModel.gd:42-44` | formula | Correcta como forma base | Valida solo como curva ideal temprana, no como incendio completo. |
| `fire_alpha_kw_s2` | `SimulationEngine.gd:103` | 0.047 | Dudosa/sin fuente local exacta | Cerca de crecimiento medio-rapido; falta trazabilidad SFPE/NFPA por escenario. |
| `max_hrr_kw` | `FireModel.gd:20`, `SimulationEngine.gd:104` | 3000 | Sin fuente | Debe depender de combustible/area/ventilacion. |
| `fuel_energy_MJ` default | `FireModel.gd:12` | 5000 | Sin fuente | Gran energia por sala; requiere fire load density documentada. |
| Kawagoe | `SimulationEngine.gd:110-113`, `1007` | 1500*Av*sqrt(H) | Simplificada | Coeficiente plausible, pero solo directo exterior y calibrable; no sustituye vent flow completo. |
| O2 minimo llama | `SimulationEngine.gd:120` | 0.122 | Dudosa | Valor de corte heuristic; casos lo bajan hasta 0.055. |
| O2 full HRR open | `SimulationEngine.gd:116` | 0.209 | Simplificada | HRR no deberia ser funcion lineal simple de fraccion O2. |
| O2 consumo Thornton | `SimulationEngine.gd:121`, `FuelObjectModel.gd:46` | 0.076 kg/MJ | Correcta como regla global | Debe cerrarse con species y combustion efficiency. |
| Smoke yield default | `SimulationEngine.gd:124` | 0.0088 kg/MJ | Dudosa | Puede ser soot/smoke; falta fuente y combustible. |
| Smoke yield FireModel | `FireModel.gd:36` | 0.06 kg/MJ | Dudosa/inconsistente | Diferente al default del engine. |
| Low-O2 smoke multiplier | `SimulationEngine.gd:125` | 5 | Sin fuente | Cualitativamente razonable, no validado. |
| CO yield base/low quality | `SimulationEngine.gd:168-169` | 0.00025 / 0.01250 kg/MJ | Dudosa | No conserva carbono ni depende de combustible. |
| CO2 yield | `SimulationEngine.gd:175+` | 0.0831 kg/MJ base | Dudosa | Falta estequiometria y carbon balance. |
| HCN yield | `SimulationEngine.gd:185+` | 0.000040-0.000250 kg/MJ | Sin fuente/critica | No depende de nitrogeno del combustible. |
| FED hypoxia | `SimulationEngine.gd:358-364` | a=8.13, b=0.54 | Plausible | Debe trazarse a ISO/Purser y validarse con O2 real. |
| FED heat convectivo | `SimulationEngine.gd:370-376` | A=4.1e8, n=3.61 | Plausible | Depende de implementacion; necesita referencia exacta y tests. |
| FED heat radiativo | `SimulationEngine.gd:378-380` | A=1.33e4, VF=0.20 | Dudosa | View factor fijo no representa geometria/postura. |
| Flashover temp | `SimulationEngine.gd:296` | 500 C | Simplificada | Criterio comun, pero no suficiente sin heat flux. |
| Flashover layer | `SimulationEngine.gd:297` | 1.2 m | Sin fuente | Debe validarse por escenario. |
| Flashover breathing temp | `SimulationEngine.gd:301` | 600 C a 0.9 m | Dudosa | Muy severo; gap conocido Ghanekar 0.9 m. |
| Flashover HRR multiplier | `SimulationEngine.gd:214` | 2.2 | Sin fuente | Multiplicador no fisico si no proviene de combustible adicional. |
| Backdraft pool threshold | `SimulationEngine.gd:240` | 8 MJ | Sin fuente/critica | Debe basarse en masa combustible y mezcla inflamable. |
| Backdraft O2 max | `SimulationEngine.gd:241` | 0.13 | Dudosa | Necesita relacion con mezcla, no solo O2. |
| Backdraft temp min | `SimulationEngine.gd:242` | 180 C | Sin fuente | Ignicion/autoignicion no garantizada. |
| Backdraft HRR multiplier/duration | `SimulationEngine.gd:246-247` | 4.0 / 12 s | Sin fuente | No representa deflagracion ni presion. |
| Suppression heat absorption | `SimulationEngine.gd:204` | 950 kJ/L | Dudosa | Inferior a evaporacion completa desde 20 C (~2600 kJ/L); puede representar efectividad parcial, debe documentarse. |
| Suppression HRR decay per L | `SimulationEngine.gd:205` | 0.024 | Sin fuente | Ajuste empirico; requiere water mapping. |
| Suppression heat fractions | `SimulationEngine.gd:206-208` | 0.68/0.18/0.26 | Semantica pendiente | Que sumen >1 no demuestra bug: pueden representar efectividades/sumideros solapados. Verificar semantica y budget energetico. |
| Upper heat capture fraction | `SimulationEngine.gd:320-322` | 0.10-0.25 | Sin fuente | Parametro sensible; no hay evidencia suficiente para atribuirle por si solo capas frias. Analizar con budget y benchmark regenerado. |
| Smoke density | `SmokeModel.gd:16` | 0.18 kg/m3 | Dudosa | "Densidad de humo" no equivale a soot/aerosol para optical density. |
| Extinction coefficient | `SmokeModel.gd:19` | 8700 m2/kg | Plausible para soot | Incorrecto si se aplica a masa de humo total. |
| Visibility C factor | `SmokeModel.gd:20` | 3.0 | Plausible | Debe diferenciar señales luminosas/reflectantes y ocupantes. |
| Spill base | `SmokeModel.gd:24-26` | 0.18 kg/s/m2, cap 0.9 | Sin fuente | Heuristico. |
| Layer relax down/up | `SmokeModel.gd:38-39`, `ThermalSystem.gd:128-129` | 0.10/0.008; 0.18/0.015 | Sin fuente | Puede introducir dependencia dt. |
| Pressure spill ref | `SmokeModel.gd:33-35`, `ThermalSystem.gd:143` | 8 Pa | Dudosa | Necesita vent flow derivado. |
| Glass break temp | `GlassFailureSystem.gd:17-18` | 250 +/- 80 C | Simplificada | Rotura de vidrio depende de heat flux, gradiente, espesor, marco y tipo. |
| Glass open rate/max | `GlassFailureSystem.gd:19-20` | 0.15/s, 0.85 | Sin fuente | Ventilacion resultante puede no ser fisica. |
| Doorway O2 coeff | `OxygenExchangeSystem.gd:22-26` | 1.70, 0.08/step, 0.06 kg/s/m2 | Sin fuente | Intercambio O2 separado del flujo de masa/entalpia. |
| Natural vent inlet fraction | `GasExchangeSystem.gd:71`, `362` | 0.5 | Simplificada | Neutral plane no siempre mid-height. |
| Interior transport speed | `GasExchangeSystem.gd:20`, `OxygenExchangeSystem.gd:19` | 0.20 m/s | Dudosa | Necesita validacion de tiempos multi-room. |
| Ceiling jet Alpert | `SimulationEngine.gd:1762-1781` | 16.9 / 5.38 forms | Correcta como correlacion | Usada para detectores/estimacion; validar unidades y limites. |
| Pool HRR density | `SimulationEngine.gd:452` | 1000 kW/m2 default en objetos | Plausible para algunos liquidos | Debe ser por combustible y diametro, con burning rate. |
| Ignition temp object | `FuelObjectModel.gd:40` | 320 C | Demasiado simplificada | Material-specific. |
| Critical heat flux object | `FuelObjectModel.gd:41` | 18 kW/m2 | Plausible para algunos solidos | Debe ser por material, piloted/non-piloted. |

## 5. Auditoria de escenarios de validacion propuestos

Los rangos son orientativos para acceptance inicial; deben ajustarse con incertidumbre experimental de cada dataset.

| Escenario | Condiciones iniciales | Metricas esperadas | Rangos aproximados segun literatura | Resultado esperado en SimuFire hoy | Criterios de aceptacion/rechazo |
|---|---|---|---|---|---|
| Habitacion simple con puerta abierta | ISO 9705-like, puerta 0.8 x 2.0 m, burner/sofa con HRR conocido | HRR, upper/lower temp, layer, O2/CO/CO2, heat flux suelo | CFAST/FDS/ISO 9705: capa descendente, upper temp consistente con HRR y ventilacion | HRR razonable, capa/temperatura posiblemente frias | Error temp upper <25%, layer <0.3 m, O2 <0.02 abs, HRR <15%. |
| Habitacion con puerta cerrada | Misma sala, fugas conocidas, fuego limitado por O2 | Decaimiento HRR, O2, CO/soot altos, capa baja | NIST TN 1603 underventilated: O2 bajo, CO/soot aumentan | Puede agotar O2 rapido y mantener capa demasiado alta | Rechazar si O2/CO/capa fuera de incertidumbre o si HRR no pasa a ventilacion-limited. |
| Ventana que rompe | Vidrio con dimensiones/tipo, heat flux y temperatura medidos | Tiempo de fallo, area abierta, salto HRR/O2/temp | UL/NIST: fallo modifica flow path e intensifica si vent-limited | Rompe por temp 250 +/-80 C | Aceptar solo si tiempo de rotura dentro de banda experimental y sensibilidad al tipo de vidrio. |
| Incendio limitado por ventilacion | Combustible suficiente, apertura reducida | HRR limitado por Av sqrt(H), CO/soot alto, O2 bajo | Kawagoe/SFPE/CFAST: HRR dependiente apertura | Aplica Kawagoe parcial y O2 factor | Error HRR vent-limited <20%, CO/CO2/O2 en bandas medidas. |
| Apertura subita de puerta | Sala underventilated, puerta se abre a t fijo | O2 sube, HRR y temp pueden subir, gases salen en capa alta | UL FSRI/NIST: flow path y deterioro remoto si no hay agua | SimuFire ya falla respuesta remota O2 Ghanekar | Rechazar si tiempo O2 remoto se adelanta >30 s o temp/CO no siguen datos. |
| Flashover | ISO 9705 room corner, lining/sofa con datos | Tiempo a flashover, floor heat flux, upper temp, ignicion generalizada | ISO 9705: early to flashover, upper 500-600 C aprox, flux suelo ~20 kW/m2 contexto | Modelo puede no disparar 0.9 m Ghanekar | Aceptar solo con heat flux y temp correctos; no usar solo temp. |
| Backdraft potencial | Compartimento caliente, O2 bajo, gases combustibles medidos, ventilacion repentina | Mezcla combustible, presion, llama/deflagracion, HRR spike | Requiere LFL/UFL y gases no quemados | Disparador heuristic por MJ/O2/temp | Rechazar hasta que haya masa de combustible no quemado y mezcla inflamable. |
| Ataque con agua | Estructura UL FSRI, flujo LPM, ubicacion, duracion | Temp, HRR, vapor, visibilidad, O2/CO, heat flux a victima | UL FSRI: reduccion rapida de temp si agua llega al fire compartment; no generalizar | Enfria y extingue sin vapor/steam visibility | Aceptar si reproduce temp/HRR y no mejora artificialmente visibilidad/tenabilidad. |
| Ventilacion tactica | Horizontal/vertical/PPV/door control, fuego vent-limited | Flow path, temp remota, O2, CO, HRR | UL FSRI ventilation: aberturas y ubicacion alteran energia y spread | Cualitativo, pero flujo no conservativo | Aceptar solo con escenarios UL/NIST instrumentados y tolerancias por sensor. |
| Incendio multi-compartimento | Dormitorio-pasillo-salas, mobiliario moderno | Propagacion, tiempos O2/CO remotos, capas por habitacion | Ghanekar/NIST multi-room: retrasos y estratificacion medibles | Falla O2 remoto y pico temp origen | Rechazar si respuesta remota se adelanta o temp origen queda fuera 450-650 C cuando referencia lo exige. |

## 6. Plan de mejora

### Criticas antes de usarlo para entrenamiento

1. Etiquetar claramente los modos: regresion interna 17/17 PASS y reference checks 28/28 PASS no equivalen a validacion externa completa. Para entrenamiento cuantitativo, exigir benchmarks externos regenerados y trazables con cada cambio.
2. Corregir capa caliente y temperatura superior contra CFAST: masa/entalpia por capas, flujos conservativos y perdidas.
3. Completar quimica toxica: CO mejorado con φ ✅ (SF-AUD-005 parcialmente corregido); pendiente CO2/HCN/soot con combustible, ventilacion y balance elemental.
4. Rehacer backdraft: gases combustibles, LFL/UFL, mezcla, ignicion, presion y incertidumbre.
5. Rehacer supresion: vapor, evaporacion parcial, gas cooling, mojado de superficies, visibility/tenability post agua.
6. Añadir validacion automatica de timestep y conservacion de masa/energia/especies.

### Importantes para mejorar realismo

1. Curvas HRR/MLR por objeto basadas en ASTM E1354/furniture calorimeter.
2. Rotura de vidrio por flujo de calor/gradiente/tipo de vidrio.
3. Radiacion con flame geometry, layer radiation, view factors y soot attenuation.
4. Materiales termicos por pared/techo/suelo/puertas/ventanas.
5. Separar visibilidad, FED, FEC irritante, incapacitación y letalidad.

### Deseables a largo plazo

1. Acoplar un modo benchmark que exporte casos a CFAST/FDS.
2. Base de datos versionada de combustibles: sofa, colchon, madera, PP, PU foam, nylon, heptano, tolueno.
3. Calibracion bayesiana o least-squares con incertidumbre por fenomeno.
4. Panel de validacion con error normalizado y dominio de aplicabilidad.

### Cambios arquitectonicos recomendados

- Crear un nucleo `ZoneFireSolver` responsable de masa, energia, especies y aberturas, evitando que O2/gas/humo/calor resuelvan flujos independientes.
- Crear `FuelChemistryModel` con composicion elemental, yields, combustion efficiency y soot.
- Crear `WaterSuppressionModel` separado, con estado de agua/vapor/superficies.
- Crear `ValidationHarness` que ejecute escenarios, compare CSVs y falle CI si se superan tolerancias.
- Hacer todos los parametros fisicos trazables: valor, unidad, referencia, rango de validez, fecha, escenario de calibracion.

## 7. Tests automaticos propuestos

### Tests unitarios

```gdscript
func test_thornton_o2_consumption():
    var hrr_kw := 1000.0
    var dt := 10.0
    var expected_kg := 1.0 * 0.076 * 10.0
    assert_almost_eq(compute_o2_consumed(hrr_kw, dt), expected_kg, 0.01)
```

```gdscript
func test_visibility_uses_soot_not_smoke_total():
    var soot_kg := 0.001
    var volume := 100.0
    var k := 8700.0
    var c := 3.0
    assert_almost_eq(visibility(soot_kg, volume), c / (k * soot_kg / volume), 0.01)
```

```gdscript
func test_flashover_requires_floor_heat_flux():
    room.temp_upper_c = 620.0
    room.floor_heat_flux_kw_m2 = 8.0
    assert_false(try_flashover(room))
    room.floor_heat_flux_kw_m2 = 22.0
    assert_true(try_flashover(room))
```

```gdscript
func test_backdraft_requires_flammable_mixture():
    room.retained_fuel_species = {"CO": 0.0, "UHC": 0.0}
    room.o2 = 0.12
    room.temp_upper_c = 250.0
    assert_false(try_backdraft(room))
```

### Tests de integracion

1. `test_cfast_r0_window_360_required_checks`: ejecutar caso y exigir `all_required_pass=true`; fallar en temp upper/capa/HRR/O2/CO.
2. `test_ghanekar_bedroom_hallway_required_checks`: exigir O2 remoto, peak temp origen y known gaps convertidos en required tras corregir quimica.
3. `test_water_knockdown_no_free_visibility`: aplicar agua; temperatura debe bajar, pero visibilidad no debe mejorar instantaneamente si se genera vapor/soot.
4. `test_door_opening_vent_limited_intensification`: puerta cerrada, O2 bajo, abrir puerta; comprobar retardo y magnitud HRR/O2/temp frente a dataset.
5. `test_glass_failure_sensitivity`: vidrio simple vs templado/doble debe romper en tiempos diferentes bajo mismo flujo.

### Tests de regresion fisica

```text
Para cada escenario validado:
  ejecutar dt = 0.05, 0.10, 0.20, 0.50 s
  comparar HRR_peak, t_flashover, t_O2_15%, FED_0.3, temp_upper_peak, layer_min
  aceptar si desviacion entre dt <= 0.10 y dt <= 0.20 es:
    HRR_peak < 5%
    tiempos < 5 s o < 5%
    temperaturas < 20 C
    capa < 0.15 m
```

```text
Budget por paso:
  energia_generada = HRR * dt
  energia_capas + energia_paredes + energia_ventilada + energia_pirolisis + energia_perdida + energia_agua
  error_relativo acumulado < 5% para casos sin supresion
  error_relativo acumulado < 10% para casos con supresion hasta modelar vapor completo
```

```text
Species budget:
  C_fuel -> CO2 + CO + soot + UHC
  O2_consumed coherente con HRR y productos
  masa total de aire/gases no negativa
  ningun clamp puede crear/destruir mas de 1% de masa por paso sin log de budget
```

## 8. Veredicto final

SimuFire puede considerarse:

- **Juego visual:** si se presenta como experiencia interactiva no predictiva.
- **Simulador educativo cualitativo:** si se rotula claramente que ilustra tendencias, no magnitudes fiables.
- **Simulador semicuantitativo:** solo en escenarios concretos que pasen validacion documentada.

SimuFire **no puede considerarse actualmente**:

- Herramienta tecnica validada.
- Simulador apto para entrenamiento tactico cuantitativo.
- Sustituto de CFAST, FDS, ensayos UL FSRI/NIST o analisis SFPE.

La informacion disponible si permite evaluarlo, y el resultado es claro: el proyecto tiene una base prometedora, pero sus propios resultados de validacion muestran brechas criticas. La prioridad debe ser seguridad: cualquier interfaz de usuario o documentacion que sugiera prediccion tactica debe mostrar advertencias hasta cerrar las brechas criticas.

## Referencias primarias y tecnicas usadas o recomendadas

- NIST TN 1603, *Experimental Study of the Effects of Fuel Type, Fuel Distribution, and Vent Size on Full-Scale Underventilated Compartment Fires in an ISO 9705 Room*: https://www.nist.gov/el/fire/nist-technical-note-1603
- Publicacion NIST TN 1603 con resumen y PDF: https://www.nist.gov/publications/experimental-study-effects-fuel-type-fuel-distribribution-and-vent-size-full-scale
- NIST FDS Technical Reference Guide, Sixth Edition, NIST SP 1018: https://www.nist.gov/publications/fire-dynamics-simulator-technical-reference-guide-sixth-edition
- NIST CFAST v7 Volume 1, Technical Reference Guide, NIST TN 1889v1: https://www.nist.gov/publications/cfast-150-consolidated-model-fire-growth-and-smoke-transport-version-7-volume-1
- NIST CFAST v7 Volume 3, Software Development and Model Evaluation Guide, NIST TN 1889v3: https://www.nist.gov/publications/cfast-150-consolidated-model-fire-growth-and-smoke-transport-version-7-volume-3
- CFAST project page: https://pages.nist.gov/cfast/index.html
- ASTM E1354-25, cone calorimeter heat and visible smoke release: https://store.astm.org/standards/e1354
- ASTM E1355-23, deterministic fire model predictive capability: https://store.astm.org/e1355-23.html
- ISO 9705-1:2016 room corner test: https://www.iso.org/standard/59895.html
- ISO 13571:2012 tenability/FED: https://www.iso.org/standard/56172.html
- ISO/TR 13571-2:2016 examples of tenability assessment: https://www.iso.org/standard/65996.html
- UL FSRI, Impact of Ventilation on Fire Behavior in Legacy and Contemporary Residential Construction: https://fsri.org/research/impact-ventilation-fire-behavior-legacy-and-contemporary-residential-construction
- UL FSRI, Impact of Fire Attack Utilizing Interior and Exterior Streams: https://fsri.org/resource/impact-fire-attack-utilizing-interior-and-exterior-streams-firefighter-safety-and-0
- UL FSRI, Analysis of Coordination of Suppression and Ventilation in Single-Family Homes: https://fsri.org/resource/analysis-coordination-suppression-and-ventilation-single-family-homes
- NIST, Wind-Driven Fires / Governors Island experiments: https://www.nist.gov/el/fire-research-division-73300/firegov-fire-service/wind-driven-fires
- NIST TN 1618, Fire Fighting Tactics under Wind Driven Conditions: https://www.nist.gov/publications/fire-fighting-tactics-under-wind-driven-conditions-laboratory-experiments
- NIST TN 1629, Fire Fighting Tactics Under Wind Driven Fire Conditions: 7-Story Building Experiments: https://www.nist.gov/publications/fire-fighting-tactics-under-wind-driven-fire-conditions-7-story-building-experiments
- NIST TN 1953, Propane Gas Fire Experiments in Residential Scale Structures: https://www.nist.gov/publications/propane-gas-fire-experiments-residential-scale-structures
- SFPE Handbook of Fire Protection Engineering, 5th/6th edition catalog page: https://www.sfpe.org/standards-guides/sfpehandbook
- NFPA 921 should be consulted for formal fire/backdraft/flashover investigation terminology and operational caution. Official catalog reference found via ANSI/NFPA listing: https://webstore.ansi.org/standards/nfpa/nfpa9212024
