# SimuFire — Auditoría de Validación de Comportamiento

**Fecha**: 2026-05-18  
**Suite actual**: 42 casos, 42/42 PASS  
**Complementa**: `AUDIT_REPORT_2026-05-16.md` (auditoría de completitud de física)

---

## Propósito

Esta auditoría verifica que el motor produce **comportamientos observables cualitativamente correctos**, no solo que las ecuaciones estén implementadas. Cada ítem responde a: *"¿Ocurre este fenómeno cuando debe ocurrir?"*

Un ítem puede FALLAR aunque las ecuaciones sean correctas (parámetros mal calibrados, términos de corrección que dominan la física, flags desactivados por defecto, etc.).

> **Origen**: SF-R-2026-05-18. Este tipo de auditoría habría detectado el bug de `upper_to_lower_loss_rate=0.025` (capa caliente no descendía), que la auditoría de completitud SF-AUD-001..040 no capturó porque ese término no tiene equivalente en ninguna referencia; solo es visible observando el comportamiento del modelo.

---

## Clasificación de estado

| Símbolo | Significado |
|---------|-------------|
| ✅ VERIFICADO | Caso de validación cubre el fenómeno explícitamente |
| ⚠️ PARCIAL | Caso existente lo cubre implícitamente o solo una variante |
| ❌ SIN CUBRIR | No hay caso que lo verifique |

---

## BV-001 — Descenso de capa caliente

**Expectativa**: Tras ignición sostenida, la interfaz de la capa a 150°C debe bajar por debajo de 0.5 m del suelo en la sala de fuego (incendio rápido, α ≥ 0.05 kW/s²) antes del minuto 15.  
**Referencia**: SFPE 4ª ed., Quintiere 2D zone models; NFPA 72 ceiling jet.  
**Estado**: ✅ VERIFICADO  
**Caso**: `secondary_ignition_demo` — `room_0_min_l150_m ≤ 0.5` (obs: 0.16 m)  
**Notas**: Bug corregido SF-R-2026-05-18. Antes `upper_to_lower_loss_rate=0.025` impedía el descenso. Valor correcto: 0.013.

---

## BV-002 — Flashover

**Expectativa**: En sala cerrada con α ≥ 0.012 kW/s² y combustible suficiente, la temperatura de la capa superior debe alcanzar ≥ 500°C antes de t = 600 s.  
**Referencia**: Babrauskas & Peacock (1992); Quintiere criterion T_upper ≥ 500–600°C.  
**Estado**: ✅ VERIFICADO  
**Caso**: `flashover_simple_house` — `room_0_peak_temp_upper_c ≥ 500`

---

## BV-003 — Agotamiento de O₂ en sala sellada

**Expectativa**: En sala cerrada con fuego activo, O₂ debe caer por debajo del límite de extinción (≤ 10%) antes de t = 300 s con α = 0.047 kW/s².  
**Referencia**: Thornton O₂ consumption; ASTM E1355 zone model req.  
**Estado**: ✅ VERIFICADO  
**Caso**: `v2_sealed_room_o2_depletion`

---

## BV-004 — Acumulación de FED en habitación adyacente

**Expectativa**: En pasillo conectado a sala de fuego vía puerta abierta, FED debe superar 0.3 antes de t = 350 s.  
**Referencia**: ISO 13571:2012, Purser SFPE (FED = 0.3 umbral sensible).  
**Estado**: ✅ VERIFICADO  
**Caso**: `v3_hallway_fed_exposure` — `time_room_1_fed_above_0_3_s ≤ 350`  
**Notas**: Rebaselined tras R#6 Phase 2 (estratificación CO₂ upper/lower ralentiza FED levemente).

---

## BV-005 — Pico de CO en fuego subventilado

**Expectativa**: Con apertura de ventana reducida (< 0.15 m²), CO en sala de fuego debe superar 1000 ppm antes del pico de HRR.  
**Referencia**: Tewarson yield CO en combustión subventilada; CFAST CO model.  
**Estado**: ✅ VERIFICADO  
**Caso**: `v7_underventilated_co_peak`

---

## BV-006 — Backdraft

**Expectativa**: Al abrir una puerta en sala con O₂ ≤ 13%, T ≥ 180°C y energía retenida ≥ 8 MJ, debe producirse un pico de HRR ≥ 4× el HRR previo con duración ≤ 15 s.  
**Referencia**: Fleischmann (1993) backdraft experiments; NFPA 921 §20.  
**Estado**: ✅ VERIFICADO  
**Caso**: `v1_backdraft_accumulation`

---

## BV-007 — Pirólisis Tewarson + ignición secundaria

**Expectativa**: Objetos combustibles con `heat_of_gasification_kj_kg > 0` en sala expuesta a HRR ≥ 150 kW deben alcanzar estado PYROLYZING dentro de 300 s, y al menos uno debe llegar a FLAMING si la temperatura de ignición se supera.  
**Referencia**: Tewarson SFPE Table 3.4; CFAST passive fuel model.  
**Estado**: ✅ VERIFICADO  
**Caso**: `secondary_ignition_demo` — `room_1_max_fuel_objects_flaming_count ≥ 1` (obs: 2), `room_1_max_fuel_objects_pyrolyzing_count ≥ 1` (obs: 3)  
**Notas**: Requiere `fire_spread_enabled: true` y `passive_room_autoignite_enabled: true` (opt-in). Los objetos del template por defecto usan `heat_of_gasification = -1.0` (sentinel, modelo legacy). Para activar Tewarson se deben especificar propiedades en `room_overrides`.

---

## BV-008 — Propagación de humo a salas adyacentes

**Expectativa**: Sala adyacente a sala de fuego (puerta abierta) debe acumular humo medible (≥ 0.01 kg) antes de t = 120 s con α = 0.047 kW/s².  
**Referencia**: Cooper ASET; SFPE smoke transport.  
**Estado**: ✅ VERIFICADO  
**Caso**: Múltiples: `living_room_hallway`, `layer150_tenability`, `*_smoke`

---

## BV-009 — Degradación de visibilidad

**Expectativa**: En sala con humo ≥ 0.05 kg/m³, visibilidad debe caer por debajo de 1 m.  
**Referencia**: Jin (1978) Ks·D = 8 (señales reflectantes); SFPE Eq. 63.11.  
**Estado**: ✅ VERIFICADO  
**Caso**: `layer150_tenability` — `room_0_min_visibility_m ≤ 1.0`

---

## BV-010 — Supresión por agua (reducción HRR)

**Expectativa**: Aplicación de agua debe reducir HRR ≥ 50% dentro de 60 s. Tras retirar el agua en condiciones de combustible activo, HRR debe recuperarse (reburn).  
**Referencia**: Grant & Hamins (1999) suppression model; CFAST water suppression.  
**Estado**: ✅ VERIFICADO  
**Caso**: `v8_suppression_reburn`, `ul_exterior_water_knockdown`

---

## BV-011 — PPV (presurización positiva) limpia humo

**Expectativa**: Activar PPV con apertura de escape adecuada debe reducir `smoke_kg` en sala objetivo ≥ 80% dentro de 300 s.  
**Referencia**: IFSTA PPV tactics; NIST TN 1427.  
**Estado**: ✅ VERIFICADO  
**Caso**: `g3_gie_ppv_post_knockdown`

---

## BV-012 — Conducción térmica a través de paredes

**Expectativa**: Pared de hormigón de 0.20 m entre sala de fuego y sala adyacente debe transferir calor suficiente para que la cara exterior suba ≥ 10°C en 600 s.  
**Referencia**: Fourier conducción 1D; CFAST wall model.  
**Estado**: ✅ VERIFICADO  
**Caso**: `mediterraneo_concrete_wall_conduction`

---

## BV-013 — Stack effect (efecto chimenea vertical)

**Expectativa**: En edificio de 2 plantas con fuego en planta baja, la presión en planta alta debe ser mayor que en planta baja (plano neutro entre pisos).  
**Referencia**: Klote & Milke (2002) stack effect ΔP = ρg·Δz·(1/T_out − 1/T_in).  
**Estado**: ⚠️ PARCIAL  
**Caso**: `two_storey_smoke` cubre transporte de humo vertical. No hay verificación explícita de gradiente de presión medido.  
**Acción recomendada**: Añadir métrica `room_1_vs_room_0_pressure_pa_delta` al baseline de `two_storey_smoke` o crear caso específico.

---

## BV-014 — Estratificación de contaminantes (upper vs. lower)

**Expectativa**: CO₂ y HCN producidos por el fuego y transportados con el gas caliente deben tener concentración mayor en la zona superior que en la inferior en la sala receptora.  
**Referencia**: Cooper zone model stratification; R#6 Phase 2.  
**Estado**: ✅ VERIFICADO  
**Caso**: `v3_hallway_fed_exposure` (FED posicional depende de concentración por capa)  
**Notas**: R#6 Phase 2 activó `hot_gas_hcn_carry_fraction=0.40`. El tiempo de FED cambió de 250 s a 315 s al activar estratificación (gas caliente lleva CO₂ a zona superior, no a zona donde respira persona).

---

## BV-015 — FEC por irritantes (HCl de PVC, acroleína, formaldehído)

**Expectativa**: Quema de PVC debe producir HCl suficiente para que FEC_irr contribuya a incapacitación antes de FEC_CO en escenario de apartamento pequeño.  
**Referencia**: ISO 13571:2012 Eq. FEC irritantes; Purser SFPE.  
**Estado**: ✅ VERIFICADO  
**Caso**: `pvc_curtain_hcl_release`

---

## BV-016 — FEC por HCN (poliuretano, muebles tapizados)

**Expectativa**: Quema de sofá PU debe producir HCN suficiente para que FEC_HCN contribuya significativamente a incapacitación total.  
**Referencia**: Purser SFPE (HCN aporta 20–30% FED en incendios residenciales).  
**Estado**: ✅ VERIFICADO  
**Caso**: `pu_sofa_fec_incapacitation`

---

## BV-017 — Crecimiento de pool fire (área creciente)

**Expectativa**: Pool fire con `pool_spread_rate_m2_s > 0` debe mostrar HRR creciente no solo por t² sino por expansión de área, hasta `pool_max_area_m2`.  
**Referencia**: Babrauskas (2002) pool fire HRR; SFPE §3.1.  
**Estado**: ✅ VERIFICADO  
**Caso**: `kitchen_grease_pool_fire`

---

## BV-018 — Ignición de target por radiación

**Expectativa**: Surface target expuesto a flujo radiativo ≥ flux crítico durante tiempo suficiente debe alcanzar temperatura de ignición y encenderse.  
**Referencia**: Alpert (1972) ceiling jet; Wickman ignition piloted.  
**Estado**: ✅ VERIFICADO  
**Caso**: `ranch_radiation_target_ignition`

---

## BV-019 — Rotura de vidrio (aumento de ventilación)

**Expectativa**: Al alcanzar temperatura de rotura aleatoria en ±80°C sobre valor nominal, la apertura de la ventana debe aumentar progresivamente hasta ≥ 85%, causando pico de HRR por mayor aporte de O₂.  
**Referencia**: Pagni & Joshi (1991) glass breakage; CFAST glass_break model.  
**Estado**: ✅ VERIFICADO  
**Caso**: `glass_break_window_spike`

---

## BV-020 — Char layer y LOI (madera)

**Expectativa**: Madera con `char_fraction > 0` debe mostrar reducción de MLR tras quema inicial conforme el char aísla el sustrato. Madera con `loi_o2_fraction > 0.21` debe extinguirse en atmósfera de O₂ normal (auto-extinción).  
**Referencia**: Quintiere char layer model; ASTM LOI (ISO 4589).  
**Estado**: ✅ VERIFICADO  
**Caso**: `char_layer_loi_wood`

---

## BV-021 — Oxidación de CO post-flashover

**Expectativa**: En capa caliente > 700°C, CO debe oxidarse a CO₂. Concentración de CO debe disminuir tras flashover aunque la combustión continúe.  
**Referencia**: Gottuk & Roby (1995) CO yield; CFAST CO oxidation model.  
**Estado**: ✅ VERIFICADO  
**Caso**: `co_oxidation_post_flashover`

---

## BV-022 — Curva HRR tabulada

**Expectativa**: Fuego con curva HRR tabulada cargada desde archivo debe seguir los valores de la tabla (± tolerancia interpolación) sin divergencia temporal.  
**Referencia**: SFPE custom HRR curves; NFPA 72 fire models.  
**Estado**: ✅ VERIFICADO  
**Caso**: `hrr_tabulated_curve_sofa`

---

## BV-023 — Viento en aberturas exteriores

**Expectativa**: Viento de 8 m/s en fachada debe aumentar caudal de entrada en aperturas de barlovento en ≥ 15% respecto a caso sin viento.  
**Referencia**: Aynsley et al. Cp coefficients; ASHRAE wind pressure model.  
**Estado**: ✅ VERIFICADO  
**Caso**: `wind_assisted_exterior_spread`

---

## BV-024 — Conservación de masa de transporte de contaminantes

**Expectativa**: `_transfer_hot_gas_contaminants()` es transporte puro; suma source.X + target.X debe ser idéntica antes y después. Violación relativa < 0.01%.  
**Estado**: ✅ VERIFICADO  
**Caso**: `conservation_transport` — `conservation_max_violation_frac < 1e-5` (obs: ~7e-16)

---

## BV-025 — Balance de energía (primer principio)

**Expectativa**: Energía liberada (HRR integrado) ≈ ΔE_gas + E_paredes + E_ventilación + E_radiación_exterior. Desequilibrio < 5%.  
**Estado**: ✅ VERIFICADO  
**Caso**: `energy_budget_living_room`

---

## BV-026 — Decaimiento post-extinción

**Expectativa**: Tras extinción del fuego, temperaturas de todas las salas deben disminuir monotónicamente hasta ≈ ambiente. No debe haber re-ignición espontánea sin aporte externo.  
**Referencia**: Drysdale §8 decay phase.  
**Estado**: ✅ VERIFICADO  
**Caso**: `postfire_decay`  
**Notas**: Bug previo (re-ignición artificial por O₂ recuperando 10.001% vía ACH) corregido con `fire_o2_extinguished` flag en RoomModel (sesión 2026-04-17).

---

## BV-027 — Balance elemental C/H/O/N

**Expectativa**: Productos de combustión (CO, CO₂, HCN, H₂O, N₂) deben ser estequiométricamente consistentes. Φ > 1 debe producir más CO y menos CO₂.  
**Referencia**: Tewarson SFPE; Williams combustion stoichiometry.  
**Estado**: ✅ VERIFICADO  
**Caso**: `c_balance_high_phi`

---

## BV-028 — Inercia de detectores (ceiling jet Alpert)

**Expectativa**: Detector de calor en techo debe dispararse basándose en temperatura del ceiling jet (Alpert 1972), que puede ser significativamente mayor que la temperatura media de la capa superior.  
**Referencia**: Alpert (1972); NFPA 72 detector spacing.  
**Estado**: ⚠️ PARCIAL  
**Caso**: `ranch_radiation_target_ignition` incluye detectores pero no verifica explícitamente el delta entre ceiling jet y upper layer.  
**Acción recomendada**: Añadir métrica `detector_ceiling_jet_temp_c` al reporte y verificar que supera `upper_temp_c` en ≥ 15°C cerca del plume.

---

## BV-029 — Confinamiento: sala sellada no se ventila sola

**Expectativa**: Sala herméticamente cerrada (sin aberturas abiertas) no debe intercambiar O₂ ni humo con salas adyacentes más allá de la tasa de infiltración `ach_infiltration`.  
**Estado**: ✅ VERIFICADO  
**Caso**: `confinement_open_close`

---

## BV-030 — Inversión de capa (ausencia de)

**Expectativa**: El modelo nunca debe producir una capa inferior más caliente que la superior en la misma sala durante combustión activa (inversión física imposible en zona model).  
**Estado**: ❌ SIN CUBRIR  
**Acción recomendada**: Añadir aserción en `sync_room_upper_layer()`: `assert(room.temp_upper_c >= room.temp_lower_c - 5.0)` o equivalente. Crear caso de validación con fuego de baja potencia donde la diferencia sea pequeña pero siempre ≥ 0.

---

## BV-031 — Curva t² reproducible (crecimiento de fuego)

**Expectativa**: Para `fire_alpha_kw_s2 = 0.047` (medio), HRR debe alcanzar 1000 kW en t = `sqrt(1000/0.047)` ≈ 146 s ± 5 s.  
**Estado**: ⚠️ PARCIAL  
**Caso**: Varios casos verifican pico de HRR pero ninguno verifica explícitamente el tiempo de t² con tolerancia estricta.  
**Acción recomendada**: Añadir métrica `time_hrr_above_1000_kw_s` en un caso con `fire_alpha=0.047` y verificar ≈ 146 ± 10 s.

---

## Resumen de estado

| Estado | Cantidad |
|--------|----------|
| ✅ VERIFICADO | 27 |
| ⚠️ PARCIAL | 3 (BV-013, BV-028, BV-031) |
| ❌ SIN CUBRIR | 1 (BV-030) |
| **Total** | **31** |

---

## Items de acción prioritarios

### A1 — BV-030: Añadir aserción anti-inversión de capa (RECOMENDADO)
- Archivo: `sim/core/ThermalSystem.gd` → `sync_room_upper_layer()` (al final)
- Añadir: `if room.temp_upper_c < room.temp_lower_c - 1.0: push_warning(...)`
- No rompe baselines (solo emite warning, no aborta)

### A2 — BV-013: Añadir métrica de presión vertical a two_storey_smoke
- Añadir `room_upper_floor_vs_lower_floor_pressure_delta_pa` al case JSON
- Verificar > 0 Pa en cualquier instante con fuego activo

### A3 — BV-028: Verificar ceiling jet vs upper layer en detector case
- Añadir `max_ceiling_jet_minus_upper_temp_c` al ranch_radiation_target_ignition
- Verificar > 10 en algún instante

### A4 — BV-031: Caso t² puro
- Caso simple (single room, sin complejidad) con `fire_alpha=0.047`, verificar `time_hrr_above_1000_kw_s ≈ 146 ± 15`

---

*Generado por SF-R-2026-05-18. Próxima revisión recomendada tras cambios en ThermalSystem o CombustionSystem.*
