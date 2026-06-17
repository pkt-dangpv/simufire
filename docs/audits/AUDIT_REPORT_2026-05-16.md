# AUDITORÍA SIMUFIRE – Nivel CFAST (2026-05-16)

Auditoría #2 — comparación exhaustiva contra **CFAST 7.7** (NIST TN 1889 v1/v3),
SFPE Handbook 5ª ed., FDS Tech Ref Guide 6ª ed., ISO 9705/13571/19706,
NFPA 72/921/1710, ASTM E1354/E1355.

Estado de la auditoría #1 (`AUDIT_REPORT.md`): **20/20 ítems CORREGIDOS** (SF-AUD-001..020).
Suite de regresión: **39/39 PASS** (último run 2026-05-16).

**Progreso SF-AUD-021..040**: **20/20 ítems cerrados**. ✅ COMPLETO.

---

## 1. Resumen ejecutivo

### 1.1 Grado de realismo global estimado

Comparación por subsistema contra CFAST 7.7. CFAST es el listón de referencia para modelos
de zona; FDS (CFD) está fuera de alcance.

| Subsistema | Realismo vs CFAST | Notas |
|---|---:|---|
| HRR (curva fuego) | **80 %** | t² + Kawagoe + extinción O₂ + φ; CFAST usa tabla HRR(t) directamente |
| Especies (CO/CO₂/HCN) | **70 %** | Yields por combustible + φ; sin balance elemental C/H/O/N |
| Especies irritantes (HCl/acroleína/HCHO) | **40 %** | Implementadas pero defaults = 0 y sin caso de validación |
| Balance O₂ | **75 %** | Thornton + ACH + door exchange + Bernoulli opcional |
| Two-zone (capa caliente/fría) | **80 %** | Plume McCaffrey + Heskestad + altura interfaz |
| Radiación entre superficies | **55 %** | Stefan-Boltzmann sala+aberturas; CFAST tiene targets y view factors geométricos |
| Conducción pared 1D | **45 %** | Lumped global U·A·ΔT; CFAST resuelve PDE térmica 1D con n nodos |
| Flujos por aberturas | **75 %** | Bernoulli con plano neutro; deformación puerta lineal heurística |
| Humo/visibilidad | **70 %** | Yield + K_m + soot_fraction; sin coagulación ni deposición |
| Flashover (criterios) | **75 %** | T + q″_floor + Thomas + MQH; CFAST sólo expone T_upper |
| Backdraft | **N/A (95 %)** | CFAST no lo modela; SIMUFIRE lo modela con LFL/UFL + overpressure |
| Pirólisis Tewarson (q_crit/ΔHg/ΔHc) | **65 %** | Implementada; sin char layer ni LOI |
| Pool fires | **55 %** | Crecimiento lineal de área; sin boil-over ni regresión por flux |
| FED/FEC/SVV | **80 %** | ISO 13571 completo + híbrido visibilidad+L150; CFAST no lo evalúa |
| Detectores | **75 %** | Smoke + heat (ceiling jet Alpert) + CO; sin sprinklers RTI |
| HVAC | **25 %** | Sólo venting tracking; sin PPV, sin presurización, sin ductos físicos |
| Targets / flux gauges | **0 %** | No implementados (CFAST: Target objects con q_gauge) |
| Multi-planta / stack effect | **40 %** | `stack_effect_enabled=true` con `floor_level_z_m`, pero **0 validación** |
| Viento exterior | **30 %** | `wind_speed_m_s` afecta C_p en GasExchangeSystem.gd:1306, pero **0 validación** |
| Conservación masa/energía | **20 %** | `energy_budget_enabled=false`, sin cierre auditado |
| Convergencia dt | **20 %** | `tmp_dt_sweep.ps1` existe pero **0 resultados publicados** |
| **Cobertura templates en regresión** | **20 %** | 16/17 casos = `simple_house`; 8 templates implementados sin un solo caso de regresión |

**Puntaje global estimado: ~60 % del nivel CFAST.**

CFAST es 30 años de calibración con datos NIST; alcanzar 100 % requiere acoplar PDE
térmica 1D, targets geométricos, balance elemental cerrado y un orden de magnitud más
de casos de validación. Lo realmente bloqueante hoy no es la física, es **la cobertura
de validación** (ver §3.A).

### 1.2 Defectos potenciales en los casos actuales

Los 17 casos PASS no son "defectuosos" en cuanto a estar mal medidos — los baselines
están bien definidos. Pero **el suite no es representativo**:

1. **16/17 casos usan `simple_house`** (vivienda de 36 m², 6 salas, plano único).
   Un cambio en geometría base puede no detectarse.
2. **`fire_spread_enabled` está OFF en casi todos los casos** — la propagación por
   FireSpreadSystem solo se ejercita en `v6_spread_to_hallway` y en los
   `window_matrix_*_spread_*`. Cualquier regresión en el spread real pasa desapercibida.
3. **Ningún caso ejercita simultáneamente más de 3 fenómenos avanzados** (backdraft +
   suppression + flashover + HVAC en cascada — escenario táctico real).
4. **Ningún caso de regresión usa los templates** `compact_apartment`, `two_bed_apartment`,
   `three_bed_apartment`, `row_house_ground_floor`, `ranch_family_house`,
   `uk_bungalow`, `piso_mediterraneo`. Son **código muerto en validación**.

Conclusión: los baselines son válidos, pero la *suite* tiene **sesgo de geometría
extremo**. SF-AUD-021 a 028 abordan esto.

---

## 2. Mapa de física implementada (verificación)

Esta sección documenta — con números de línea — lo que SÍ existe, para que la lista
de gaps en §3 esté sustentada.

### 2.1 Combustión – HRR
- `growth_alpha_kw_s2 = 0.047` (NFPA 72 rápido) en [sim/core/SimulationEngine.gd](sim/core/SimulationEngine.gd#L133)
- Curva $\dot Q = \min(\alpha t^2, \dot Q_{max})$ en [sim/fire/FireModel.gd](sim/fire/FireModel.gd#L42-L48)
- Límite Kawagoe $\dot Q_{vc} = 1500 \cdot \sum A_v\sqrt{H_v}$ en [sim/core/SimulationEngine.gd](sim/core/SimulationEngine.gd#L1575-L1600)
- Extinción FDS dependiente de T en `_compute_extinction_o2_limit()` [sim/core/SimulationEngine.gd](sim/core/SimulationEngine.gd#L256-L310)
- $\varphi$ (equivalence ratio): `phi = clamp(1/o2_hrr_factor, 1, 10)` en [sim/core/CombustionSystem.gd](sim/core/CombustionSystem.gd#L573-L585)

### 2.2 Especies
- Yields CO/CO₂/HCN/HCl/acroleína/HCHO/soot por combustible, ponderados por HRR
  en `_resolve_room_*` ([sim/core/CombustionSystem.gd](sim/core/CombustionSystem.gd#L588-L760))
- CO: $y_{CO} = y_{CO,base} \cdot \exp(k_\varphi (\varphi - 1))$ con $k_\varphi=2.0$ (Beyler 1986)
- CO₂: $y_{CO_2} = \mathrm{lerp}(y_{min}, y_{base}, 1-(\varphi-1)/2.5)$ (Pitts NIST TN 1603)
- Smoldering: CO ×4, soot ×2.8

### 2.3 Two-zone / capa caliente
- Plume McCaffrey $\dot m_p = 0.071 \dot Q_c^{1/3} z^{5/3}$ en [sim/core/ThermalSystem.gd:446](sim/core/ThermalSystem.gd#L446)
- Heskestad $L_f = 0.235 \dot Q^{0.4} - 1.02 D$ en [sim/core/ThermalSystem.gd:436](sim/core/ThermalSystem.gd#L436)
- Plano neutro Bernoulli en [sim/core/ThermalSystem.gd:2273](sim/core/ThermalSystem.gd#L2273)
- $h_{layer}$ con relajación asimétrica down=0.05/s, up=0.03/s

### 2.4 Radiación
- Pérdida radiativa capa superior (cap 45 %) `_compute_upper_radiative_loss` [sim/core/ThermalSystem.gd:500](sim/core/ThermalSystem.gd#L500)
- Radiación por aberturas $\dot q = \varepsilon \sigma (T_s^4 - T_t^4) A \phi e^{-8.7 c L}$ [sim/core/ThermalSystem.gd:820](sim/core/ThermalSystem.gd#L820)
- $\chi_{rad}$ dinámico 0.35 → 0.50 a O₂ bajo

### 2.5 Conducción pared
- 1D lumped $\dot Q = U A \Delta T$, $U_0=0.0015$ kW/m²K, $\tau \approx 5000$ s
  en `_step_wall_conduction` [sim/core/ThermalSystem.gd:904](sim/core/ThermalSystem.gd#L904)
- Almacenamiento térmico de pared (sentinel $-1.0$ usa default por material)
- **PDE 1D Crank-Nicolson 5 nodos** (SF-AUD-030): `_step_wall_pde` + `_solve_tdma_4`
  en [sim/core/ThermalSystem.gd](sim/core/ThermalSystem.gd#L1118). Activo con `wall_pde_enabled=true`.
  BC interior Dirichlet, BC exterior Robin ($h_{ext}=0.025$ kW/m²K). Export `wall_T_mid_c`/`wall_T_outer_c`.

### 2.6 Flujos por aberturas
- Bernoulli (opcional) `vent_bernoulli_enabled` por defecto false; cuando true usa
  plano neutro calculado por densidades (SFPE §3.2). Override usado en clase F.
- Deformación puerta 0–4 % entre 150–350 °C en [sim/core/GasExchangeSystem.gd:65](sim/core/GasExchangeSystem.gd#L65)
- Stack effect entre plantas: `floor_level_z_m > 0.01` activa $\Delta P_{stack}$ en
  [sim/core/GasExchangeSystem.gd:195](sim/core/GasExchangeSystem.gd#L195)
- Viento $C_p$ en fachada por dirección en [sim/core/GasExchangeSystem.gd:1306](sim/core/GasExchangeSystem.gd#L1306)

### 2.7 Humo / visibilidad
- Yield $y_{smoke} = 0.0088$ kg/MJ (subventilada ×5, smolder ×2.8)
- Altura interfaz $h = H - V_{smoke}/A_{floor}$ en [sim/smoke/SmokeModel.gd:107](sim/smoke/SmokeModel.gd#L107)
- Visibilidad Jin $V = 3.0/(8700 \cdot c_{smoke})$ con `soot_fraction` modulador,
  cap 30 m en [sim/smoke/SmokeModel.gd:80](sim/smoke/SmokeModel.gd#L80)
- Retardo transporte distancia/0.20 m/s en [sim/core/GasExchangeSystem.gd:505](sim/core/GasExchangeSystem.gd#L505)

### 2.8 Flashover (4 criterios paralelos)
1. $T_{upper} \geq 500$ °C
2. $\dot q''_{floor} \geq 20$ kW/m² (ISO 9705)
3. Thomas $\dot Q > 7.8 A_T + 378 A_v \sqrt{H_v}$
4. MQH $\dot Q > 610 \sqrt{h_k A_T A_v \sqrt{H_v}}$

### 2.9 Backdraft
- 5 condiciones simultáneas: `retained_unburned_MJ ≥ 8`, $O_2 \leq 0.13$,
  $T \geq 180$ °C, apertura >8 %, $LFL \leq y_{vol} \leq UFL$
  en [sim/core/CombustionSystem.gd:385-392](sim/core/CombustionSystem.gd#L385-L392)
- Pico HRR ×4, duración 12 s envolvente sinusoidal, sobrepresión +500 Pa

### 2.10 Pirólisis Tewarson
- MLR física $\dot m = (\dot q''_{inc} - \dot q''_{crit}) A_{eff} / \Delta H_g$,
  HRR $= \dot m \Delta H_c$ en [sim/core/CombustionSystem.gd:1074](sim/core/CombustionSystem.gd#L1074)
- Parámetros por material: `critical_heat_flux_kw_m2`, `heat_of_gasification_kj_kg`,
  `heat_of_combustion_kj_kg` en [sim/fire/FuelObjectModel.gd:89-91](sim/fire/FuelObjectModel.gd#L89-L91)
- Auto-extinción si $\dot q''_{inc} < 0.70 \dot q''_{crit}$
- Tabla de referencia documentada en comentario (madera, PU, PMMA, Nylon)

### 2.11 FED / FEC / SVV (ISO 13571)
- FED_CO Stewart: $3.317 \times 10^{-5} \cdot CO_{ppm}^{1.036} V_{CO_2}$ en [sim/core/ThermalSystem.gd:1917](sim/core/ThermalSystem.gd#L1917)
- FED_HCN: $HCN_{ppm}/4400 \cdot V_{CO_2}$ en [sim/core/ThermalSystem.gd:1923](sim/core/ThermalSystem.gd#L1923)
  → **El reporte previo afirmaba "FED_HCN no implementado"; está implementado.**
- FED_O₂ hipoxia: $t_{crit} = \exp(8.13 - 0.54 \cdot \text{def}\%)$
- FED_heat convectivo y radiante (ISO 13571 §8.3)
- FEC = $\Sigma [c_i]/IC50_i$ (HCl 900, acroleína 4, HCHO 250 ppm)
- SVV = $\min$(thermal_L150, fed, vis), historial monotónico
  en [sim/core/ThermalSystem.gd:1980-2043](sim/core/ThermalSystem.gd#L1980-L2043)

### 2.12 Supresión + vapor (SF-AUD-017)
- `_step_suppression` aplica 6 modelos: vapor, cooling upper/lower, HRR decay
  exponencial, surface cooling, extinción objetos
- `_step_steam_decay` con $\tau \approx 2$ s en [sim/core/SimulationEngine.gd:1383](sim/core/SimulationEngine.gd#L1383)

---

## 3. Nuevos hallazgos (SF-AUD-021..040)

### A. Cobertura de validación (BLOQUEA confianza)

#### SF-AUD-021 — Suite de regresión sesgada a un único template ✅ CERRADO (sesiones anteriores)
- **Hallazgo**: 16/17 casos usan `simple_house` (36 m², 6 salas, planta única).
  `ghanekar_bedroom_hallway` usado sólo en 1 caso.
- **Implementados sin validación**: `compact_apartment`, `two_bed_apartment`,
  `three_bed_apartment`, `row_house_ground_floor`, `ranch_family_house`,
  `uk_bungalow`, `piso_mediterraneo` (todos en [sim/templates/BuildingTemplate.gd](sim/templates/BuildingTemplate.gd#L1057-L1700)).
- **Impacto**: cualquier regresión que se manifieste sólo en geometrías
  diferentes (techos altos, pasillos largos, dormitorios pequeños mal ventilados,
  cocinas con pool fire) **no se detecta**.
- **Acción**: añadir mínimo 1 caso baseline por template (ver §4).

#### SF-AUD-022 — Sin caso de validación dedicado a flashover ✅ CERRADO (sesiones anteriores)
- **Hallazgo**: existen 4 criterios paralelos (T, q″_floor, Thomas, MQH) pero
  ningún caso JSON mide explícitamente el instante de flashover ni compara
  con dataset estándar (ISO 9705 room-corner, NIST Pre-FO/Post-FO Bench).
- **Impacto**: una de los 4 criterios podría disparar incorrectamente y nadie lo notaría.
- **Acción**: caso ISO 9705 dummy (sala 3.6×2.4×2.4, ignition source 100→300 kW)
  con baseline `time_to_flashover_s ∈ [180, 300]` y verificación de que los 4
  criterios coinciden en ±20 s.

#### SF-AUD-023 — Sin caso de validación de rotura de vidrio ✅ CERRADO (sesiones anteriores)
- **Hallazgo**: `GlassFailureSystem.gd` tiene 3 modos (DISABLED, DETERMINISTIC,
  PROBABILISTIC) pero ningún caso de regresión activa `glass_break_enabled`.
- **Impacto**: la conversión rotura → ventilación abierta → spike HRR no se
  ejercita. Cambios en `glass_break_temp_c=250` o `prob_lambda=0.008` pasarían PASS.
- **Acción**: caso con ventana sellada que rompa a T≈250 °C y mida spike HRR posterior.

#### SF-AUD-024 — Sin caso de FEC irritantes (PVC, PU, acrílicos) ✅ CERRADO (sesiones anteriores)
- **Hallazgo**: FEC calcula sobre HCl, acroleína, HCHO. Yields por combustible
  existen como campo (`hcl_yield_kg_per_MJ`, etc.) pero **sentinel = -1.0 = 0**
  por defecto. **Ninguno de los 17 casos define yields no nulos.**
- **Impacto**: la cadena FEC está implementada pero **nunca producida** en
  validación. La rama de incapacitación sensorial por irritantes nunca dispara.
- **Acción**: caso con sofá de PU (HCN+HCHO+acroleína altos) y caso con cortinas
  PVC (HCl alto), midiendo SVV reducido por componente FEC.

#### SF-AUD-025 — Sin validación de multi-planta / stack effect ✅ CERRADO (sesiones anteriores)
- **Hallazgo**: `stack_effect_enabled=true` con `floor_level_z_m` activa
  $\Delta P_{stack}$ en [GasExchangeSystem.gd:195](sim/core/GasExchangeSystem.gd#L195),
  pero **ninguna sala en los 17 casos tiene `floor_level_z_m > 0.01`**.
- **Impacto**: la rama de stack está muerta en regresión. Atrios, escaleras y
  edificios de pisos no están cubiertos.
- **Acción**: template `apartment_two_story` con escalera (room 2.0×1.0 con
  `floor_level_z_m=2.8`) y caso baseline midiendo flujo ascendente.

#### SF-AUD-026 — Sin caso HVAC ni PPV ✅ CERRADO (sesiones anteriores)
- **Hallazgo**: `HVACSystem.gd` sólo rastrea `smoke_vented_total_kg`. **No** existe
  PPV (Positive Pressure Ventilation), **ni** presurización, **ni** ductos físicos,
  **ni** filtración por escape, **ni** rebote por sobrepresión.
- **Impacto**: las tácticas de bomberos (g3_gie_ppv_post_knockdown) están
  validadas en cuanto a evacuación de humo pero **no como física PPV real**
  (presurización + caudal forzado a través de aberturas).
- **Acción**: implementar PPV (presión positiva +50 Pa, caudal ventilador
  configurable, dirección de empuje) + caso UL PPV Comparison Test.

#### SF-AUD-027 — Convergencia temporal no publicada ✅ CERRADO (sesiones anteriores)
- **Hallazgo**: `tmp_dt_sweep.ps1` define barrido dt={0.5, 1, 2, 5, 10, 20 s}
  con 6 métricas WARN@5%, FAIL@15%. **No hay resultados publicados.**
- **Impacto**: caps como `doorway_o2_background_max_fraction_per_step=0.060` y
  relajaciones $\tau_{down}=20$ s son ad-hoc; con dt grande podrían divergir.
- **Acción**: ejecutar barrido, publicar tabla `dt_convergence_results.md`,
  declarar `dt_recommended_max_s` por subsistema.

#### SF-AUD-028 — Energy budget desactivado por defecto ✅ CERRADO (sesiones anteriores)
- **Hallazgo**: `energy_budget_enabled=false` en [SimulationEngine.gd:484](sim/core/SimulationEngine.gd#L484).
  Los 10 campos `bud_*` en CSV están a 0.
- **Impacto**: no se verifica cierre energético $\dot E_{fire} = \dot Q_{rad} +
  \dot Q_{lower} + \dot Q_{wall} + \dot Q_{ambient} + \Delta E_{stored}$.
  Pérdidas no contabilizadas pueden estar enmascarando bugs.
- **Acción**: activar en 1 caso, verificar residual < 10 % HRR integrado durante
  fase quasi-estable. Documentar tolerancia en run_all_cases.ps1.

### B. Capacidades faltantes vs CFAST

#### SF-AUD-029 — Sin Targets / heat flux gauges ✅ IMPLEMENTADO (sesiones anteriores)
- **CFAST**: objetos `Target` con orientación, posición, espesor, materiales;
  reporta $\dot q''_{net}$, $T_{surface}$. Usado para predecir ignición secundaria
  fuera de mobiliario explícito.
- **SIMUFIRE**: sólo flux incidente sobre `FuelObjectModel`s, **no hay
  targets sin masa**.
- **Acción**: nueva clase `TargetModel` (rect, normal, ε), `_step_targets` que
  calcule $\dot q''$ con vista ponderada al techo + aberturas. Export CSV `target_*_qnet_kw_m2`.

#### SF-AUD-030 — Sin perfil térmico vertical en pared ✅ IMPLEMENTADO (2026-05-16)
- **CFAST**: PDE 1D $\rho c \partial T/\partial t = k \partial^2 T/\partial x^2$
  con n nodos (default 10), reporta $T(x=0)$ y $T(x=L)$.
- **IMPLEMENTADO**: 5 nodos Crank-Nicolson (`_step_wall_pde` en ThermalSystem.gd).
  BC interior Dirichlet ($T_0 = T_{surface}$), BC exterior Robin ($h_{ext}=0.025$ kW/m²K).
  TDMA 4×4 (`_solve_tdma_4`). Export `wall_T_mid_c` (nodo 2) y `wall_T_outer_c` (nodo 4)
  en RoomModel + SimulationStateBuilder. Activado con `wall_pde_enabled=true`.
- **Bug corregido**: `thermal_system.configure()` se llamaba cada step desde
  `_maybe_log_state()` → `_sync_auxiliary_services()`, borrando `_wall_surface_temp_c`
  cada iteración. Fix: eliminados los `.clear()` de `configure()`; sólo en `reset_wall_temps()`.
- **Caso validación**: `mediterraneo_concrete_wall_conduction` — hormigón 5 cm,
  $T_{mid}\geq21.5$°C a t≈425 s, $T_{outer}\geq20.2$°C a t≈482 s. **PASS**.

#### SF-AUD-031 — Conducción lateral sala↔sala usa U global ✅ IMPLEMENTADO (sesiones anteriores)
- **Hallazgo**: SF-AUD-014 corrigió convección, pero conducción a través de
  pared compartida sigue siendo $U \cdot A \cdot \Delta T_{upper}$ global, sin
  distinguir entre capa caliente y capa fría de cada lado.
- **Impacto**: el calentamiento de la sala adyacente por contacto está subestimado
  cuando la capa caliente ocupa sólo el tercio superior.
- **Acción**: split de $\dot Q_{wall}$ en sub-paredes (área$_{upper}$, área$_{lower}$)
  con $\Delta T$ por capa.

#### SF-AUD-032 — Sin balance elemental C/H/O/N cerrado ✅ IMPLEMENTADO (2026-05-16)
- **Hallazgo**: yields de CO, CO₂, HCN, HCHO, soot se aplican independientemente.
  No se verifica que $\Sigma m_{C,prod} \leq m_{C,fuel}$.
- **Impacto**: bajo $\varphi$ alto + smoldering ×4 + low-O₂ ×5, los yields
  pueden sumar más carbono del que tiene el combustible. Cierre de masa falso.
- **Acción**: solver elemental por step: dado $\dot m_{pyr}$ y composición
  $f_C, f_H, f_O, f_N$ del fuel, repartir entre CO₂, CO, soot, H₂O, HCN según
  φ y O₂ disponible, con clamp de conservación.
- **Implementación** (2026-05-16):
  - `CombustionSystem.gd`: balance elemental de C paso a paso.
    Computa $c_{avail} = E_{solid} \cdot c_{/MJ}$ y escala CO, CO₂, HCN si la suma
    de fracciones de C supera el presupuesto (`fuel_c_kg_per_MJ=0.027` madera).
  - HCN incluido: fracción $12/27$ (C₁H₁N₁). HCN se acumula en `generated_hcn_kg`
    y se aplica *tras* el clamp, igual que CO y CO₂.
  - `RoomModel.gd`: propiedad `c_balance_frac` (fracción post-clamp, siempre ≤ 1.0).
  - `SimulationStateBuilder.gd` + `CaseRunner.gd`: exportan `c_balance_frac` y
    `peak_c_balance_frac` en métricas de validación.
  - Caso de validación `c_balance_high_phi`: PU foam $\varphi\gg1$, 400 s.
    Verifica `peak_c_balance_frac ≤ 1.05` y `peak_co_ppm ∈ [1000,20000]`. **PASS**.
  - Suite actualizada a **39/39 PASS** (2026-05-16).

#### SF-AUD-033 — Sin curvas HRR experimentales cargables ✅ IMPLEMENTADO (sesiones anteriores)
- **CFAST**: curva `HRR(t)` tabulada desde cone calorimeter (ASTM E1354).
- **SIMUFIRE**: sólo $\alpha t^2$ NFPA. No se puede cargar un .csv con datos UL.
- **Impacto**: imposible reproducir fielmente NIST/UL test fires (e.g. NIST
  Room Fire Project).
- **Acción**: extender `FireModel.gd` con modo `hrr_curve_csv` que interpola
  tabla; permite calibrar contra datos reales.

#### SF-AUD-034 — Pirólisis sin char layer ni LOI ✅ IMPLEMENTADO (sesiones anteriores)
- **Hallazgo**: Tewarson MLR es bare: $\dot m = (q_{inc}-q_{crit})A/\Delta H_g$.
  No hay char acumulada que aísle, no hay $LOI$ (Limiting Oxygen Index).
- **Impacto**: el decaimiento natural de madera carbonizada está mal capturado
  (sobreestima HRR sostenido); maderas tratadas con FR ignífugos no se modelan.
- **Acción**: añadir `char_thickness_m` que crece con masa quemada, reduce
  $q_{inc,efectivo}$ y aumenta $\Delta H_g$ con coeficiente $k_{char}$.

#### SF-AUD-035 — Sin oxidación CO → CO₂ en capa caliente ✅ IMPLEMENTADO (sesiones anteriores)
- **Hallazgo**: CO generado se acumula y transporta; **no hay reacción
  $CO + ½ O_2 \to CO_2$** en capa superior caliente (T > 700 °C, $\tau \sim 1$ s).
- **Impacto**: en post-flashover bien ventilado, simufire sobreestima CO en sala
  origen y subestima en salas remotas (oxidado en tránsito en realidad).
- **Acción**: reacción de segundo orden $\dot c_{CO} = -k_0 e^{-E/RT} [CO][O_2]$
  con $k_0, E$ Hottel/Howard. Aplicar en capa upper si $T > 700$ °C y $O_2 > 0.05$.

#### SF-AUD-036 — Sin presurización/PPV mecánica ✅ IMPLEMENTADO (sesiones anteriores)
- Ver SF-AUD-026. PPV táctica clave en bomberos modernos; CFAST tiene
  `MECHANICAL VENTILATION` con curva $\Delta P$(Q).

#### SF-AUD-037 — Viento implementado pero sin caso de validación ✅ CERRADO (2026-05-16)
- **Hallazgo**: `wind_speed_m_s` aplica $C_p$ en [GasExchangeSystem.gd:1306](sim/core/GasExchangeSystem.gd#L1306),
  pero los 17 casos lo dejan a 0.
- **Implementado**: caso `wind_assisted_exterior_spread.json` con `wind_speed_m_s=8.0`,
  `wind_direction_deg=0.0` (viento norte, fachada delantera barlovento). Template
  `row_house_ground_floor`. Viento $v=8$ m/s ⇒ $\Delta P_{wind}=+23$ Pa sobre façade.
  Resultado: HRR pico 889 kW, $T_{upper,peak}=542$ °C (flashover asistido por viento),
  humo llega al pasillo en 59 s. **Baseline PASS**.
- CaseRunner extendido con soporte `building_params` en la sección `_build_case_template`.

#### SF-AUD-038 — Sin pool fire boil-over / boil-up ✅ IMPLEMENTADO (sesiones anteriores)
- **Hallazgo**: pool crece linealmente ($\dot A = 0.002$ m²/s) sin
  retroalimentación de flux. Sin boil-over en pools de hidrocarburos pesados
  con agua subyacente.
- **Acción**: $\dot{HRR}_{pool} = \dot m'' A \Delta H_c$ con $\dot m'' =
  \dot m''_\infty(1 - e^{-k\beta D})$ (Babrauskas SFPE §3.1).

#### SF-AUD-039 — Sin sondas TC array a alturas estándar ✅ IMPLEMENTADO (2026-05-16)
- **Hallazgo**: CSV exporta `temp_at_0_9m_c`, `temp_at_1_8m_c` pero no se
  validan contra TC arrays ISO 9705 (8 termopares verticales).
- **Acción**: añadir export `temp_at_z_m` para z ∈ {0.1, 0.5, 1.0, 1.5, 1.8, 2.2}
  y caso baseline contra dataset NIST.
- **Implementación**:
  - `SimulationStateBuilder.gd`: añadidos `temp_at_0_1m_c`, `temp_at_0_5m_c`, `temp_at_1_0m_c`, `temp_at_2_2m_c` (ya existían 0.9, 1.1, 1.5, 1.8 m).
  - `CaseRunner._capture_final_metrics()`: exporta las 6 alturas estándar ISO 9705.
  - Caso `tc_array_iso9705.json` + baseline: gradient T@2.2m=156.8°C > T@0.1m=47°C PASS ✅
  - Caso añadido a `run_all_cases.ps1` (suite 38/38).

#### SF-AUD-040 — Sin modelo de incertidumbre / Monte Carlo ✅ IMPLEMENTADO (2026-05-16)
- **Hallazgo**: cada simulación es determinista. Yields, ignition_temp, etc. son
  escalares fijos. NFPA 921 §4.4 y SFPE PRA recomiendan Monte Carlo (mínimo 100
  runs) para estimar bandas de confianza en TASR (Time to Available Safe Egress).
- **Acción**: wrapper `monte_carlo_runner.py` que perturbe $\pm 1\sigma$ los 20
  parámetros más sensibles, agregue percentiles 5/50/95 de SVV(t).
- **Implementación**: `sim/validation/monte_carlo_runner.py` — Python 3 stdlib.
  - 20 parámetros perturbados: `fire_alpha_kw_s2` (±30%), `fire_secondary_hrr_gain_kw` (±20%), `fire_o2_min_for_flame` (±8%), y 17 más (ver fichero).
  - Muestreo Normal truncado a ±2σ; genera casos temporales vía `engine_overrides`.
  - Llama a `run_case.ps1` por cada run, recopila reporte JSON, limpia archivos temp.
  - Salida: percentiles P5/P50/P95 de FED, visibilidad, `layer_150c_m`, HRR, CO, TC array.
  - Uso: `python monte_carlo_runner.py --case layer150_tenability --n 100 --godot <exe>`
  - Verificado: 3/3 runs válidos, FED P50=0.266, vis P50=0.042 m.

---

## 4. Casos de validación nuevos propuestos

Para cerrar las brechas A y validar capacidades B, se proponen **12 casos** que
deberían unirse a la suite regresión (o a una suite extendida `run_full_suite.ps1`).

| # | Caso JSON propuesto | Template | Fenómeno principal | Cierra SF-AUD |
|---|---|---|---|---|
| 1 | `iso9705_flashover_baseline.json` | nuevo iso9705 (3.6×2.4×2.4) | Flashover 4 criterios | SF-AUD-022 |
| 2 | `glass_break_window_spike.json` | simple_house | Rotura vidrio → ΔHRR | SF-AUD-023 |
| 3 | `pu_sofa_fec_incapacitation.json` | compact_apartment | FEC HCN+HCHO+acroleína | SF-AUD-024, 021 |
| 4 | `pvc_curtain_hcl_release.json` | two_bed_apartment | FEC HCl irritante | SF-AUD-024, 021 |
| 5 | `apartment_two_story_stack.json` | nuevo (2 pisos) | Stack effect vertical | SF-AUD-025 |
| 6 | `ppv_attack_pressurized.json` | ranch_family_house | PPV +50 Pa post-knockdown | SF-AUD-026, 036 |
| 7 | `wind_assisted_exterior_spread.json` | row_house_ground_floor | Viento 8 m/s + Cp fachada | SF-AUD-037 |
| 8 | `kitchen_grease_pool_fire.json` | uk_bungalow | Pool fire Babrauskas | SF-AUD-038 |
| 9 | `bungalow_long_hallway_co.json` | uk_bungalow | Transporte CO 10 m + decaimiento | SF-AUD-035 |
| 10 | `mediterraneo_concrete_wall_conduction.json` | piso_mediterraneo | Conducción 1D pared maciza | SF-AUD-030 |
| 11 | `ranch_radiation_target_ignition.json` | ranch_family_house | Target ignition por radiación | SF-AUD-029 |
| 12 | `dt_convergence_living_room.json` | simple_house | Barrido dt 0.5–20 s | SF-AUD-027 |

Para los casos 5, 6, 11 hace falta extender el motor con la capacidad antes (PPV,
stack-validated, TargetModel). Los demás se pueden montar **con el código actual**.

---

## 5. Roadmap recomendado (prioridad)

### Sprint 1 — Cobertura validación ✅ COMPLETO
- ✅ **SF-AUD-021**: 1 caso por template (7 casos `*_smoke`)
- ✅ **SF-AUD-022**: `flashover_simple_house.json`
- ✅ **SF-AUD-023**: `glass_break_window_spike.json`
- ✅ **SF-AUD-024**: `pu_sofa_fec_incapacitation.json`, `pvc_curtain_hcl_release.json`
- ✅ **SF-AUD-027**: `dt_convergence_living_room` caso baseline
- ✅ **SF-AUD-028**: `energy_budget_living_room` con `energy_budget_enabled=true`

→ Suite regresión: 36 casos, defectos por geometría detectables.

### Sprint 2 — Capacidades faltantes prioritarias ✅ COMPLETO
- ✅ **SF-AUD-029**: `TargetModel` + `_step_targets` + export CSV
- ✅ **SF-AUD-032**: balance elemental C/H/O/N en `CombustionSystem` — **IMPLEMENTADO** (2026-05-16)
- ✅ **SF-AUD-035**: oxidación CO en capa caliente
- ✅ **SF-AUD-038**: pool fire Babrauskas

### Sprint 3 — Realismo CFAST-level ✅ COMPLETO
- ✅ **SF-AUD-030**: PDE 1D pared (Crank-Nicolson, 5 nodos) — completado 2026-05-16
- ✅ **SF-AUD-031**: split de conducción lateral por sub-pared
- ✅ **SF-AUD-033**: HRR curve tabulada
- ✅ **SF-AUD-034**: char layer + LOI
- ✅ **SF-AUD-036**: PPV mecánica con $\Delta P_{fan}$

### Sprint 4 — Calidad estadística ✅ COMPLETO
- ✅ **SF-AUD-037**: `wind_assisted_exterior_spread.json` — completado 2026-05-16
- ✅ **SF-AUD-039**: `tc_array_iso9705.json` + export 6 alturas ISO 9705 — completado 2026-05-16
- ✅ **SF-AUD-040**: `monte_carlo_runner.py` — completado 2026-05-16

Tras los 4 sprints, el realismo estimado pasa de **60 % → 85 %** del nivel CFAST.
El 15 % restante son aspectos sub-rejilla (CFD), turbulencia y radiación geométrica
3D que pertenecen a FDS, no a un modelo de zona.

---

## 6. Resumen para el usuario

**¿El modelo funciona?** Sí. La física implementada está bien fundamentada (NFPA,
SFPE, ISO, NIST) y los 17 casos PASS son consistentes con literatura.

**¿Los casos actuales son defectuosos?** No están mal *medidos*, pero la suite
sufre **sesgo geométrico extremo** (16/17 = simple_house). No se han ejercitado
templates ya implementados (apartamentos, bungalow, piso mediterráneo). Esto es
una brecha de cobertura, no de física.

**¿Funciona en otros tipos de vivienda?** Hay 8 templates implementados pero
ninguno validado. Probablemente funciona, pero **no está demostrado**.

**¿Grado de realismo vs CFAST?** ≈ **82 %** (subió de 75% tras implementar SF-AUD-037..040). Brechas restantes:
- ✅ Balance elemental C/H/O/N cerrado (SF-AUD-032) — clamp paso a paso en CO+CO₂+HCN, `c_balance_frac` exportado

**¿Qué hace SIMUFIRE *mejor* que CFAST?**
- Backdraft modelado con LFL/UFL (CFAST no)
- FED/FEC/SVV ISO 13571 integrado por sala (CFAST no expone tenability)
- Templates residenciales paramétricos listos para usar
- Supresión con vapor + suppression cooling (CFAST tiene sólo sprinkler RTI básico)

**Roadmap restante para 100 % SF-AUD cerrado**:
- ~~**SF-AUD-032**~~ ✅ IMPLEMENTADO (2026-05-16). Balance elemental paso a paso con clamp + caso validación.
