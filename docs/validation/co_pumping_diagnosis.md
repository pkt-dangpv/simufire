# CO pumping — Diagnóstico y plan de fix (follow-up de F0)

**Fecha:** 2026-07-07
**Estado:** DIAGNÓSTICO COMPLETO — root cause CONFIRMADO con datos. Sin tocar motor.
**Contexto:** F0 (commit `82494f71`) corrigió el bombeo concentrador para CO₂. Este documento
confirma que CO — y también HCN, HCl, acroleína y formaldehído — sufren el mismo bug
estructural en el transporte inter-room, y define el plan de fix.

---

## 1. Root cause — CONFIRMADO

### 1.1 Mecanismo (idéntico al de CO₂ pre-F0)

El transporte doorway en GES usa el proxy de fracción de humo
`min(kg_smoke_moved / source.smoke_kg, 1.0)`, que **satura a 1.0** cuando la sala fuente
tiene poco humo (~0.1 kg en fire room ventilada). Con el proxy saturado, cada tick exporta
el stock completo de la especie hacia la sala receptora sin cota de equilibrio. El hub
(pasillo) acumula porque su tasa de entrada >> tasa de salida.

### 1.2 Evidencia en datos (v4_co_remote_rooms, CSV post-F0)

- **Pico CO por sala:** room 1 = **237,186 ppm** vs fire room = 15,619 ppm (**15×**).
- **Ratio instantáneo receptor/fuente:** hasta **39×** (t=624s, room 1: 222,463 ppm
  con la fuente a 5,675 ppm). 2,370 filas con receptor > fuente.
- **Corpus:** 13 de 29 CSVs muestran pico CO receptor > 2× fire room. Peores:
  `v4_co_remote_rooms` (15×), `victim_fed_incapacitation` (8.8×: 144,621 vs 16,505),
  `pvc_curtain_hcl_release` (4.7×), `fuel/o2_stoich_diag_sealed` (4.3×),
  `flashover_simple_house` (3.1×).
- **No dispara PHY-P1** solo porque el yield de CO es ~50× menor que el de CO₂: el bombeo
  satura por debajo de 1e6 ppm. El mecanismo es el mismo.

### 1.3 Conexión con los 55 D2 de v4

En la ventana D2 (rooms 2/5, t=184–200s), el CO bulk receptor está 1.4–2× por encima de la
fuente en el mismo instante (p.ej. t=190: room 5 = 3,284 ppm vs fire = 1,628 ppm) y
`co_upper_ppm` receptor (7,6k–17k) infla el numerador del ratio CO/CO₂. El envelope
temporal `D2: 69` de v4 registra exactamente esta huella.

---

## 2. Mapa de código

### 2.1 GES doorway — `GasExchangeSystem.gd` L822–858 (BUG activo)

| Especie | Línea | Fórmula | Severidad |
|---|---|---|---|
| CO | 823–826 | `min(kg/smoke_kg,1) × co_upper_kg` (cap: `co_kg`) | Bombeo del stock **upper** completo/tick |
| CO₂ | 828–848 | **CORREGIDO F0** (headroom + cut_ratio) | — |
| HCN | 849–852 | `min(kg/smoke_kg,1) × hcn_kg` (stock **total**) | Idéntico a CO₂ pre-fix |
| HCl | 853–854 | ídem, stock total | ídem |
| Acroleína | 855–856 | ídem | ídem |
| Formaldehído | 857–858 | ídem | ídem |

Nota: CO mueve solo el stock upper (algo más suave que CO₂ pre-fix); HCN/HCl/acroleína/
formaldehído mueven el stock **total** — la forma más agresiva del bug.

### 2.2 GES delayed delivery — L1244–1290 (BUG activo)

`target.co_kg += entry["co_kg"]` y equivalentes HCN/HCl/etc. sin cota de headroom.
CO₂ ya tiene la cota con refund a la fuente (F0). El parcel ya lleva `"from"` (añadido en
F0), así que extender el refund a las demás especies es directo.

### 2.3 GES counterflow equalization — L923–1010 (NO es bug)

Intercambio difusivo bidireccional por diferencia de concentración (CO/CO₂/HCN/HCl/
acroleína). Dirección correcta (ecualiza), pero magnitud gateada por
`doorway_o2_counterflow_coeff` — insuficiente para contrarrestar el bombeo. No tocar.

### 2.4 ThermalSystem `_transfer_hot_gas_contaminants` — L2749–2775 (BUG activo para CO)

`co_moved = min(co_kg, co_upper_available × upper_fraction_moved × carry)` — sin cota de
concentración. CO₂ tiene el limitador justo debajo (L2779–2791, F0). El path HCN térmico
(L2807+) está **gateado OFF por defecto** (`hot_gas_hcn_carry_fraction = 0.0`) — no activo.

### 2.5 Cota física — la misma que F0, válida para cualquier especie

El limitador compara kg de especie por kg de aire (densidad ambiente 1.2 kg/m³, misma
convención que `compute_co_ppm`/`compute_co2_ppm`). Una advección desde la fuente
transporta gas a concentración ≤ la de la fuente; no puede subir al receptor por encima.
El argumento es independiente del peso molecular — **aplicar el mismo limitador a CO/HCN/
HCl/etc. es físicamente correcto**, sin calibración nueva.

---

## 3. Tabla de riesgos — impacto del fix

### 3.1 Baselines required afectadas (~15 checks se moverán)

| Check (required) | Actual | Riesgo |
|---|---|---|
| `victim_fed_incapacitation_peak_co_ppm_global` | 144,624 | **El artefacto bombeado está horneado en el baseline.** Caerá masivamente. |
| `victim_fed_incapacitation_victim_v0_final_fed` | 1.028 | Cae si la víctima está en receptor (FED_CO baja). |
| `v4_co_remote_rooms_room_1_peak_co_upper_ppm` | 25,538 | Baja (receptor). |
| `v4_co_remote_rooms_room_2_peak_co_upper_ppm` | 33,297 | Baja. |
| `v4..._time_room_1_co_upper_above_1200_s` / `time_room_2_co_upper_above_200_s` | — | Timings se desplazan. |
| `v3_hallway_fed_exposure_room_1_max_fed` | 2,910 | Baja (FED_CO del pasillo). |
| `v3..._time_room_1_co_upper_above_1200_s` / `fed_above_0_1/0_3` | — | Timings se desplazan. |
| `g4_gie_delayed_entry_hazard_room_1_peak_co_upper_ppm` (+timing) | 27,237 | Baja. |
| `g3_gie_ppv_post_knockdown_room_1_peak_co_upper_ppm` | 22,247 | Baja. |
| `ghanekar_kitchen_far_hall_fed_0_3/1_0_s`, `idlh_co_s` | — | Far hall = receptor; timings se desplazan. |
| `piso_mediterraneo_smoke_time_room_2_co_above_200_s` | 116.4 | Timing se desplaza. |
| `pu_sofa_fec_incapacitation_time_room_1_fec_above_0_05_s` | 79.1 | FEC de irritantes en receptor (HCl/acroleína/formaldehído bajan). |

### 3.2 Baselines NO afectadas (fire room = fuente; el limitador no capa la fuente)

`v7_underventilated_co_peak`, `v8_suppression_reburn`, `co_oxidation_post_flashover`,
`v5_*`, `wood_vc_reference`, `c_balance_high_phi`, `cfast_*_co_upper` (single/two-room con
CO de fire room), `pu_sofa`/`victim_fed` HCN/FEC de room 0, `pvc_curtain` HCl de room 0.

### 3.3 D2 / suites

| Ítem | Efecto esperado |
|---|---|
| v4 D2:55 | → ~0. **Retirar el envelope temporal `D2: 69`** (criterio de aceptación). |
| D2 de CTRLs en fire room (v1_m4:9, v5_m4:13, wood_vc:114, victim:8) | Sin cambio (pool release/VC en fuente). |
| D2PRE | Sin cambio directo (es CO₂ tracer vs mass; el tracer OES no se toca). Conteos de CTRL pueden moverse ±: re-medir envelopes. |
| D1 (CO mass balance) | Debe seguir verde — el limitador conserva masa (refund). Verificación obligatoria. |
| Semántica de v4 | El caso sigue demostrando riesgo CO remoto (los receptores seguirán con miles de ppm por acumulación legítima); los números serán físicamente defendibles. |

---

## 4. Plan de fix mínimo (1 fase, CO + HCN + HCl + acroleína + formaldehído)

**Decisión de alcance:** una sola fase para todas las especies del doorway GES.
Razones: (a) es el mismo patrón de 6 líneas por especie ya validado en F0; (b) HCN/HCl/
etc. tienen la forma más agresiva del bug (stock total); (c) el único baseline receptor
de irritantes (`pu_sofa time_room_1_fec`) se audita junto con los de CO en la misma
regeneración — dividir en fases duplicaría el ciclo de regen+audit. No hace falta fase
de instrumentación: los datos ya confirman el mecanismo.

1. **GES doorway (L822–858):** aplicar el patrón F0 por especie — headroom
   `max(0, c_src × air_tgt − stock_tgt)` y `cut_ratio` que recorta también el upper moved
   (CO usa su propio par bulk/upper; HCN igual; HCl/acroleína/formaldehído solo bulk).
2. **GES delivery (L1244+):** extender la cota con refund (patrón F0 CO₂) a CO, HCN y
   los tres irritantes. El parcel ya lleva `"from"`.
3. **ThermalSystem (L2749):** cota de headroom para CO antes de aplicar el delta
   (mismas 8 líneas que el bloque CO₂ de L2784–2791). HCN térmico: no tocar (gateado OFF).
4. **No tocar:** counterflow equalization, OES, producción (CombustionSystem), yields,
   tolerancias, thresholds D2/D2PRE.
5. **Retirar** `"D2": 69` del envelope de `v4_co_remote_rooms` si la medición post-fix
   lo confirma en ~0.

## 5. Checks tras el fix

1. Regenerar CSV+JSON de los casos afectados: los 7 de F0 + `victim_fed_incapacitation`,
   `g3_gie_ppv_post_knockdown`, `g4_gie_delayed_entry_hazard`, `ghanekar_kitchen`,
   `piso_mediterraneo`, `pu_sofa_fec_incapacitation`, `pvc_curtain_hcl_release`,
   `flashover_simple_house`, `fuel_balance_diag_sealed`, `o2_stoich_diag_sealed`,
   `two_storey_smoke`, `cfast_two_floor_stairwell` + `reference_checks.json`.
2. `audit_physics_coherence_suite.py` — exit 0; re-medir envelopes CTRL (D2/D2PRE/E1/O2E1
   pueden moverse); retirar v4 `D2: 69`.
3. `audit_ilv_layer_coherence_suite.py` — 15/14/0 esperado sin cambio.
4. `validation_guardrails.py` — PHY-P1 PASS sin allowlist; D1 lane verde.
5. `pytest tests/` — adaptar solo si cambian conteos de envelope.
6. `validate_reference_cases.py` — **listar cada delta de baseline con antes/después y
   justificación de corrección física. NO actualizar sin aprobación explícita.**
7. Conservación CO manual en v4 (mismo método que F0: suma en salas vs generado×12).

## 6. Criterios de aceptación

- CO receptor ≤ concentración fuente por advección: el ratio instantáneo receptor/fuente
  sostenido desaparece (hoy 39×; post-fix ~≤1 salvo acumulación legítima con fuente decayendo).
- v4 room 1 pico CO cae de 237k ppm a escala físicamente defendible.
- D2 en v4 → 0 y envelope `D2: 69` retirado (no ampliado).
- D1 (CO mass balance) sigue verde; conservación manual exacta.
- Baselines de fire room (§3.2) sin cambio fuera de tolerancia.
- Cada baseline movida (§3.1) documentada como corrección con antes/después, aprobada
  explícitamente antes de actualizar.
- PHY-P1 PASS, allowlist vacía. Ninguna tolerancia ampliada.

## 7. Decisión: ¿implementar ahora o documentar?

**Documentar ahora, implementar en sesión dedicada.** El fix de código es pequeño
(~60 líneas, patrón ya validado en F0), pero mueve ~15 baselines required, incluidos FED
y el `peak_co_ppm_global` de victim_fed — y la constraint vigente es "no tocar baselines
sin aprobación explícita". La sesión de implementación necesita: (1) aprobación previa del
proceso de actualización de baselines como correcciones, (2) ciclo completo de regen
(~15 casos, >1h de headless runs), (3) auditoría delta a delta. Hasta entonces, el
envelope temporal `D2: 69` en v4 mantiene el gate útil y este documento fija el alcance.
