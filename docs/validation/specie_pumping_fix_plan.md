# Specie Pumping Fix — Plan de implementación y baseline migration

**Fecha:** 2026-07-07
**Estado:** PLAN CERRADO — sin tocar motor todavía.
**Precedentes:** F0 CO₂ limiter (commit `82494f71`), diagnóstico en
[co_pumping_diagnosis.md](co_pumping_diagnosis.md).
**Alcance:** CO, HCN, HCl, acroleína, formaldehído. **Decisión de fase: todas las
especies juntas** (§6).

---

## 1. Plan de patch exacto

Principio rector: **replicar el patrón F0 ya validado, sin refactorizar el bloque CO₂
existente** (queda byte-idéntico → riesgo de regresión CO₂ cero).

### 1.1 `GasExchangeSystem.gd` — doorway send (función del transporte interior, L822–858)

Tras la línea de cada especie, aplicar la cota de equilibrio con el mismo patrón que el
bloque CO₂ (L829–848). Las masas de aire fuente/destino (`*_src_air_kg`, `*_tgt_air_kg`
a 1.2 kg/m³) se calculan **una vez** y se comparten entre especies (el bloque CO₂ ya las
declara; renombrar a `spec_src_air_kg`/`spec_tgt_air_kg` o declarar equivalentes — no
tocar las líneas CO₂ en sí).

**CO (L823–827):**
```gdscript
# co_moved_kg ya calculado (min(kg/smoke_kg,1) × co_upper_kg, cap co_kg)
var co_tgt_stock_kg: float = maxf(0.0, target.co_kg + float(co_delta_kg[to_id]))
var co_headroom_kg: float = maxf(
    0.0,
    source.co_kg / spec_src_air_kg * spec_tgt_air_kg - co_tgt_stock_kg
)
co_moved_kg = minf(co_moved_kg, co_headroom_kg)
co_delta_kg[from_id] -= co_moved_kg
```
Nota: CO usa un único valor para bulk y upper (el parcel lleva `co_kg == co_upper_kg`),
así que no necesita `cut_ratio` separado — capar `co_moved_kg` capa ambos.
La resta a `co_delta_kg[from_id]` se mueve DESPUÉS del cap (hoy está en L827, antes).

**HCN (L849–852):** patrón CO₂ completo (bulk + upper con `cut_ratio`):
```gdscript
hcn_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.hcn_kg
var hcn_tgt_stock_kg: float = maxf(0.0, target.hcn_kg + float(hcn_delta_kg[to_id]))
var hcn_headroom_kg: float = maxf(
    0.0,
    source.hcn_kg / spec_src_air_kg * spec_tgt_air_kg - hcn_tgt_stock_kg
)
var hcn_cut_ratio: float = 1.0
if hcn_moved_kg > hcn_headroom_kg and hcn_moved_kg > 0.000001:
    hcn_cut_ratio = hcn_headroom_kg / hcn_moved_kg
    hcn_moved_kg = hcn_headroom_kg
hcn_delta_kg[from_id] -= hcn_moved_kg
hcn_upper_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.hcn_upper_kg * hcn_cut_ratio
hcn_upper_delta_kg[from_id] -= hcn_upper_moved_kg
```

**HCl / acroleína / formaldehído (L853–858):** solo bulk, sin upper — cap simple:
```gdscript
hcl_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.hcl_kg
hcl_moved_kg = minf(hcl_moved_kg, maxf(
    0.0, source.hcl_kg / spec_src_air_kg * spec_tgt_air_kg
    - maxf(0.0, target.hcl_kg + float(hcl_delta_kg[to_id]))
))
hcl_delta_kg[from_id] -= hcl_moved_kg
```
(ídem `acrolein_moved_kg`, `formaldehyde_moved_kg` con sus deltas.)

### 1.2 `GasExchangeSystem.gd` — `_release_pending_interior_deliveries` (L1244–1292)

Extender el patrón refund del bloque CO₂ (L1248–1274) a CO, HCN, HCl, acroleína y
formaldehído. El parcel ya lleva `"from"` (F0).

**⚠ CRÍTICO — contabilidad D1:** el lane D1 audita el balance de masa CO usando
`co_net_transport_kg_total`. El patrón CO₂ hace `src_room.co2_kg += refund` sin tocar
acumuladores porque CO₂ no tiene lane. Para CO, el refund DEBE contabilizarse en ambos
extremos o D1 gatea al primer tick con recorte:
```gdscript
var co_parcel_kg: float = float(entry.get("co_kg", 0.0))
var co_upper_parcel_kg: float = float(entry.get("co_upper_kg", 0.0))
if co_parcel_kg > 0.0:
    var co_src_room: RoomModel = building.get_room(int(entry.get("from", -1)))
    if co_src_room != null:
        var co_headroom_kg: float = maxf(
            0.0,
            co_src_room.co_kg / (maxf(0.1, co_src_room.volume_m3()) * 1.2)
                * (maxf(0.1, target.volume_m3()) * 1.2) - target.co_kg
        )
        if co_parcel_kg > co_headroom_kg:
            var co_cut: float = co_headroom_kg / co_parcel_kg
            var co_refund_kg: float = co_parcel_kg - co_headroom_kg
            co_src_room.co_kg += co_refund_kg
            co_src_room.co_net_transport_kg_total += co_refund_kg   # ← D1
            co_src_room.co_upper_kg = minf(
                co_src_room.co_upper_kg + co_upper_parcel_kg * (1.0 - co_cut),
                co_src_room.co_kg
            )
            co_parcel_kg = co_headroom_kg
            co_upper_parcel_kg *= co_cut
# la aplicación al target (L1244-1247) usa co_parcel_kg/co_upper_parcel_kg capados;
# el += co_net_transport del target ya usa el delta real post-cap (patrón existente).
```
HCN: mismo patrón con `hcn_kg`/`hcn_upper_kg` (sin acumulador de transporte — no hay lane).
HCl/acroleína/formaldehído: versión bulk-only (refund a `src.hcl_kg`, sin upper).

### 1.3 `ThermalSystem.gd` — `_transfer_hot_gas_contaminants` (L2749–2750)

Cota de headroom para CO antes de acumular deltas, calcada del bloque CO₂ (L2784–2791):
```gdscript
var co_upper_available_kg: float = clampf(source.co_upper_kg, 0.0, source.co_kg)
var co_moved_kg: float = minf(source.co_kg, co_upper_available_kg * upper_fraction_moved * carry)
var co_tgt_stock_kg: float = maxf(0.0, target.co_kg + _delta_co_kg.get(tgt_id, 0.0))
var co_headroom_kg: float = maxf(
    0.0,
    source.co_kg / (maxf(0.1, source.volume_m3()) * 1.2)
        * (maxf(0.1, target.volume_m3()) * 1.2) - co_tgt_stock_kg
)
co_moved_kg = minf(co_moved_kg, co_headroom_kg)
```
El flush (L2862–2864) actualiza `co_net_transport_kg_total` desde el delta real → D1
consistente sin cambios adicionales.

### 1.4 NO tocar

- Bloques CO₂ existentes (F0) — byte-idénticos.
- Counterflow equalization GES L923–1010 (difusión ecualizadora, no es bug).
- HCN térmico L2807+ (gateado OFF, `hot_gas_hcn_carry_fraction = 0.0`).
- OES, CombustionSystem, yields, tolerancias, thresholds D2/D2PRE, severities.
- `_step_co_oxidation` (SimulationEngine L2096) — consume CO en fire room (>700°C,
  per-case flag default OFF). Watch item §5.7, no patch.

Tamaño estimado: ~70 líneas nuevas en 2 archivos.

---

## 2. Casos a regenerar

### 2.1 CSVs del corpus de coherencia (audit suites) — 13

`v4_co_remote_rooms`, `victim_fed_incapacitation`, `flashover_simple_house`,
`fuel_balance_diag_sealed`, `o2_stoich_diag_sealed`, `two_storey_smoke`,
`cfast_two_floor_stairwell`, `cfast_corridor_chain`, `cfast_multi_fuel_couch_tv`,
`cfast_two_room_door_open`, `pvc_curtain_hcl_release`, `g3_gie_ppv_post_knockdown`,
`v1_backdraft_accumulation` (CTRL: receptor 10.8k vs 4k — envelope re-medir).
(`run_scenario.py` con `--timeout` suficiente + dedupe del último timestep.)

### 2.2 Reports JSON de validación (Godot `--validation-case=`) — ~18

Los 7 de F0 (`confinement_open_close`, `postfire_decay`, `row_house_ground_floor_smoke`,
`secondary_ignition_demo`, `v3_hallway_fed_exposure`, `v4_co_remote_rooms`,
`v6_spread_to_hallway`) + `victim_fed_incapacitation`, `g3_gie_ppv_post_knockdown`,
`g4_gie_delayed_entry_hazard`, `ghanekar_kitchen`, `piso_mediterraneo`,
`pu_sofa_fec_incapacitation`, `pvc_curtain_hcl_release`, `cfast_2r_hall`,
`cfast_corridor_chain`, `cfast_multi_fuel_couch_tv`, `cfast_two_room_door_open`.

### 2.3 Al final

`reference_checks.json` fresco (satisface R2-1) vía run completo de
`validate_reference_cases.py`.

---

## 3. Baselines que se espera que cambien

### 3.1 Se moverán (≈15 required — TODAS en dirección receptor-baja / timing-tardío)

| Check | Actual | Delta esperado |
|---|---|---|
| `victim_fed_incapacitation_peak_co_ppm_global` | 144,624 | ↓ masivo (es el artefacto) |
| `victim_fed_incapacitation_victim_v0_final_fed` | 1.028 | ↓ (víctima en receptor) |
| `v4_co_remote_rooms_room_1_peak_co_upper_ppm` | 25,538 | ↓ |
| `v4_co_remote_rooms_room_2_peak_co_upper_ppm` | 33,297 | ↓ |
| `v4..._time_room_1_co_upper_above_1200_s` | 135.1 | → más tarde o menor duración |
| `v4..._time_room_2_co_upper_above_200_s` | 179.4 | ídem |
| `v3_hallway_fed_exposure_room_1_max_fed` | 2,910 | ↓ |
| `v3..._time_room_1_co_upper_above_1200_s` | 135.1 | desplaza |
| `v3..._time_room_1_fed_above_0_1_s` / `_0_3_s` | 235.1 / 247.5 | más tarde |
| `g4_gie..._room_1_peak_co_upper_ppm` | 27,237 | ↓ |
| `g4_gie..._time_room_1_co_upper_above_1200_s` | 91.7 | desplaza |
| `g3_gie..._room_1_peak_co_upper_ppm` | 22,247 | ↓ |
| `ghanekar_kitchen_far_hall_fed_0_3_s` / `_1_0_s` | 626.8 / 665.3 | más tarde |
| `ghanekar_kitchen_far_hall_idlh_co_s` | 545.2 | más tarde |
| `piso_mediterraneo_smoke_time_room_2_co_above_200_s` | 116.4 | desplaza |
| `pu_sofa_fec..._time_room_1_fec_above_0_05_s` | 79.1 | más tarde (irritantes) |

Non-required que también se moverán: `g4..._time_room_1_fed_above_0_1_s`,
`ghanekar_far_hall_co_known_gap`, `cfast_2r_hall_t*_co_lower_ppm`,
`tmp_r2_window_open_start_room_2_final_fed`.

### 3.2 Guard set — NO deben moverse (fire room = fuente, el limitador no capa la fuente)

`v7_underventilated_co_peak_*`, `v8_suppression_reburn_room_0_peak_co_upper_ppm`,
`co_oxidation_post_flashover_room_0_*`, `v5_*_peak_co_upper_ppm`, `wood_vc_reference` (D2),
`c_balance_high_phi_room_0_peak_co_ppm`, `cfast_*` de fire room (t350/t360/closed/bed),
`pu_sofa` room 0 (HCN/FEC/HRR/temp), `victim_fed` room 0 (HCN/HRR/c_balance),
`pvc_curtain` room 0 (HCl/FEC/HRR/temp), todos los checks de HRR/temp/O2/smoke.

**Un movimiento en el guard set = bandera de regresión → parar y diagnosticar, no
actualizar.**

---

## 4. Criterios para aceptar un baseline delta como corrección física

Un delta se acepta y se actualiza SOLO si cumple los 5:

1. **Dirección correcta:** concentración/FED/FEC de receptor baja, o timing de umbral se
   retrasa/acorta. Un receptor que SUBE, o un fire room que cambia → regresión, parar.
2. **Plausibilidad post-fix:** en el instante del pico, la concentración del receptor no
   supera la de la fuente (re-ejecutar la query del diagnóstico: ratio sostenido ≤ ~1;
   hoy 39×). Acumulación residual con fuente decayendo es legítima y se documenta.
3. **Conservación intacta:** lane D1 verde en las audit suites + verificación manual CO
   en v4 (suma en salas + exterior_removed vs generado ×12, método F0).
4. **Semántica del caso preservada:** v4 sigue demostrando riesgo CO remoto (room 1
   mantiene co_upper > 1200 ppm una duración significativa); ghanekar sigue alcanzando
   IDLH; victim_fed sigue alcanzando FED≥1 o se re-discute el caso. Si un caso pierde su
   razón de ser, es decisión de rediseño explícita — no una actualización silenciosa.
5. **Trazabilidad:** cada delta con antes/después + justificación en el doc de sesión, y
   **aprobación explícita del usuario antes de commitear** el `reference_checks.json` y
   los baselines actualizados.

---

## 5. Checks obligatorios (en orden)

1. **Regen** §2.1 + §2.2.
2. `audit_physics_coherence_suite.py` → **exit 0**. Envelopes: SOLO conteos D2 pueden
   cambiar (↓). **D2PRE debe quedar igual** (es CO₂ tracer vs mass — no tocamos CO₂;
   un cambio en D2PRE = regresión). A3/E1/O2E1/S1/D1 sin cambio.
3. **Retirar `"D2": 69` del envelope de v4** si la medición confirma ~0. Si no baja de
   ~10, diagnosticar antes de retirar — no ampliar.
4. `audit_ilv_layer_coherence_suite.py` → **exit 0**, 15/14/0 esperado sin cambio (ILV
   es HRR/O2, no especies).
5. `validation_guardrails.py` → PHY-P1 PASS con allowlist vacía; único FAIL admisible:
   los 5 stale checks cfast_hvac/cfast_chain (pendiente separado — **no mezclar**).
6. `pytest tests/` → 272/273 (el fallo pre-existente `test_exit0_real_json`); adaptar
   tests solo si cambian conteos de envelope, nunca tolerancias.
7. `validate_reference_cases.py` → **delta review completo**: tabla antes/después de
   cada check movido, clasificado contra §3.1 (esperado) / §3.2 (regresión). Presentar
   al usuario ANTES de actualizar baseline alguno.
8. **Watch items:** (7a) casos con `co_oxidation_enabled` — el CO capado en receptores
   puede alterar marginalmente CO₂ vía oxidación; verificar que
   `co_oxidation_post_flashover` (fire room) no se mueve. (7b) FED con V_CO₂: sin efecto
   esperado (CO₂ no se toca), verificar v3/victim FED solo baja por el término CO.

---

## 6. Decisión de fase: TODAS las especies juntas

**Una sola fase.** Razones:
- El patch de irritantes (HCl/acroleína/formaldehído) es la variante más simple del
  patrón (bulk-only, sin upper ni lane de balance) — el coste marginal de código es ~15
  líneas.
- Partir en dos fases duplica el ciclo caro (regen ~18 casos + delta review + aprobación
  de baselines) para ahorrar exactamente **1 baseline required de riesgo**
  (`pu_sofa time_room_1_fec`) — los otros ~14 son de CO y se mueven igual en la fase 1.
- HCN/HCl/etc. tienen la forma MÁS agresiva del bug (stock total); dejarlos fuera deja
  el corpus inconsistente (CO capado, HCN bombeando) y complica el siguiente delta review.
- El riesgo específico de irritantes está acotado: solo 1 check required receptor; los
  demás checks de pvc/pu_sofa son de fire room (guard set).

## 7. Secuencia de ejecución propuesta (sesión de implementación)

1. Patch §1 (motor, 2 archivos). 2. Regen §2. 3. Suites §5.2–5.6. 4. Delta review §5.7
→ tabla al usuario. 5. **STOP — aprobación de baselines.** 6. Actualizar baselines
aprobados + `reference_checks.json` + retirar envelope D2 v4 + docs. 7. Suites de nuevo,
todo verde. 8. Commit único
`fix(validation): cap species bulk transport by source concentration` (sin push).
