# Changelog

All notable changes to SimuFire should be recorded here.

## Unreleased

### FP ILV HUD / Smoke Visibility (visual-only)

- **HUD ILV critical display** (`a6d44c0`) — FP technical HUD now shows `Reg ILC`, `Reg ILV` or `Reg ILV CRIT`, labels gases by layer (`O₂u/O₂l`, `COu`, `CO₂u`, `HCNu`), removes duplicated HRR/visibility from the top FP panel while the technical overlay is visible, and visually dampens FP flames in `ILV_LATENT` or critical upper-layer O₂. No simulation physics changed.
- **FP smoke visibility hardening** (`b59fa33`) — ILV-critical FP view now clamps effective display visibility to a severe default (`smoke_overlay_ilv_severe_visibility_m = 1.6` m), increases overlay opacity, and allows ceiling/opening lights to attenuate almost completely through smoke (`smoke_light_min_transmission = 0.01`). Tests cover `Reg ILV CRIT`, `Vis FP 1.6m`, damped fire light, and near-extinguished ceiling light under ILV smoke.
- **FP eye-height layer consistency** (`d69232c`) — FP technical HUD now selects gas labels/readings by eye height versus `smoke_layer_m`/`smoke_display_layer_m`, instead of mixing upper-layer gases with lower-layer visibility/temperature while crouched. Critical upper-layer O₂ can override the display label to `Reg ILV CRIT`. No simulation physics changed.
- **Overhead smoke visibility tightening** (`696f03f`) — FP smoke display no longer jumps back to clear `Vis FP 29m` merely because the camera is below the smoke plane when the upper layer is optically severe. Crouching still improves visibility, but ceiling smoke/lights remain obscured.
- **ILV layer coherence detector** — added `scripts/simulation/check_ilv_layer_coherence.py` plus unit tests. The check fails on exported CSV rows with significant HRR and critical `o2_upper` while the base regime remains fuel-controlled or `o2_hrr_factor` remains high from lower/global oxygen.
- **Open follow-up:** this is presentation-layer mitigation only. New manual QA logs show a motor/layer-coupling issue: HRR and base regime can remain high/`FUEL_CONTROLLED` with `o2_upper` near zero while `o2_lower` remains fresh. The next milestone is an ILV motor audit covering HRR/regime/O₂/gases/smoke by layer.

### Hito B — ILV latent observability milestone (cerrado 2026-06-21)

**Alcance cerrado:** observabilidad de régimen ILV en escenario de auditoría. El campo `fire_latent_active=true` y el régimen `ILV_LATENT` son visibles en `cfast_ilv_audit.csv`. No hay pool latent smoldering real con HRR positivo durante `ILV_LATENT` — eso es Fase 3. Validación 345/350 PASS intacta.

| Componente | Commit | Descripción |
|-----------|--------|-------------|
| Fase 0 auditoría | `c59aeba` | Escenario sellado + script diagnóstico read-only |
| Fase 1 clasificador | `922a56a` | `CombustionRegimeClassifier` 9 regímenes, `combustion_regime` en CSV |
| Fase 2 Paso 1 | `efcc492` | `fire_latent_active: bool` en `RoomModel`, upstream de `fire_smoldering` |
| Fase 2 Paso 2 | `fbf4d3e` | `thermal_hold` fix per-caso 40°C, idle reset, revert código muerto |

---

### Hito B — ILV Fase 2 Paso 2 (thermal_hold fix → ILV_LATENT en auditoría)

- **Thermal hold overrides** (`cfast_ilv_audit.json`) — `fire_latent_hold_upper_temp_c=40.0` y `fire_latent_hold_lower_temp_c=40.0`. Causa raíz: el engine default de 140°C/60°C excluía la sala sellada (pico ~70°C) del check `thermal_hold`, por lo que `latent_viable` nunca fue `true`. 40°C es alcanzable: `temp_upper=67°C` y `temp_lower=49°C` a t=406 s.
- **Idle reset `fire_latent_active`** (`CombustionSystem.gd` línea ~94) — `room.fire_latent_active = false` añadido junto a `room.fire_smoldering = false` en la rama idle/post-extinción, evitando que el campo quede stuck en `true` tras `_extinguish_room_fire`.
- **Revertido código muerto** (`CombustionSystem.gd`) — `fire_latent_smolder_o2_margin` nunca fue añadido al diccionario de contexto en `_build_room_combustion_context`; la variable `latent_smolder_margin` era inerte. Revertido a usar `latent_o2_viable_margin` directamente.
- **Resultado:** `fire_latent_active=1` durante 52 s (t=406.1–457.1 s), régimen `VENTILATION_CONTROLLED_BURNING → ILV_LATENT → EXTINGUISHED` en `cfast_ilv_audit.csv`. Post-extinción: `latent=0` correctamente. Clasificador 9/9 PASS. Baseline 345/350 PASS intacto.

### Hito B — ILV Fase 2 Paso 1 (observabilidad fire_latent_active)

- **`fire_latent_active: bool`** (`efcc492`) — nuevo campo en `RoomModel`, asignado desde `(not can_flame) AND latent_viable` sin gate de `hrr_kw`. Señal upstream de `fire_smoldering`; el clasificador ahora lee `fire_latent_active` para el régimen `ILV_LATENT`. Expuesto en dict de estado y CSV. Default `false`; ningún cambio de física. Con defaults el gap O2 (8.5–10.8 %) impide que `fire_latent_active` se active — Paso 2 cerrará ese gap.

### Hito B — ILV Auditoría Fase 0 (extinción directa)

- **Audit scenario** (`sim/validation/cases/cfast_ilv_audit.json`) — escenario sellado room 2 (dormitorio, ~36 m³), legacy fire path (`fuel_objects: []`), 900 s, sin infiltración ni spread. Reproduce extinción directa ILV para diagnóstico reproducible sin tocar física.
- **Audit script** (`scripts/simulation/audit_ilv_phase0.py`) — script diagnóstico read-only. Registra por segundo los campos ILV clave y reporta transiciones de régimen, condiciones en extinción y gap estructural `can_flame`/`latent_viable`. No modifica física ni validación.
- **Hallazgo Fase 0:** fuego pasa `VENTILATION_CONTROLLED_BURNING → EXTINGUISHED` a t=436 s, o2=10.9 %, sin pasar por `ILV_LATENT`. Causa raíz: `fire_smoldering` requiere `hrr_kw > 0.5`; el HRR cayó por debajo antes de que `fire_smoldering` pudiera activarse. Gap estructural: con `fire_o2_min_for_flame=0.10`, `can_flame=false` a o2<8.5 % pero `latent_viable=false` a o2<10.8 % — ventana 8.5–10.8 % bloquea llama y latencia simultáneamente.

### Hito B — ILV Clasificador (Fase 1 diagnóstico)

- **CombustionRegimeClassifier** (`922a56a`) — clasificador read-only de régimen de combustión. Lee campos existentes de `RoomModel` y escribe un nuevo campo `combustion_regime: String`. No modifica HRR, O₂, gases, temperaturas ni ningún check de validación. 9 regímenes: `FUEL_CONTROLLED`, `VENTILATION_STRESSED`, `VENTILATION_CONTROLLED_BURNING`, `VENTILATION_INDUCED_GROWTH`, `ILV_LATENT`, `FULLY_DEVELOPED`, `BACKDRAFT_RISK`, `BACKDRAFT_EVENT`, `EXTINGUISHED`. Campo expuesto en estado de sala (dict + CSV). Test headless 9 casos: `tools/validate_combustion_regime.gd`. Baseline validación: 345/350 PASS intacto.

## v0.4.0+ux-polish

### FP UX Polish

- **Camera stance easing** (`c7e3db8`) — `_apply_stance(immediate=false)` now lerps the camera toward the stance target height (tau = 80 ms) instead of snapping. `immediate=true` preserves snap on init. Test: `tools/validate_fp_stance_easing.gd` (stand/crouch/prone convergence in 30 physics frames).
- **Opening prompt text** (`a689f1d`) — four consistency and orthography fixes: `"Dejar pulsado F: elegir apertura"` → `"Mantén F: elegir grado"`; `"ventilacion"` → `"ventilación"`; `"Suelta para aplicar."` → `"Suelta F para aplicar."`; `"Suelta F: puerta 0% | manten F…"` → `"Suelta F: cerrar puerta 0% | mantén F…"` (added action verb, fixed accent).
- **FP corner collision diagnostic** — code inspection of `CharacterBody3D + CapsuleShape3D + move_and_slide()` stack found no reproducible issue. Room geometry (min 2.8 m free span) and doorway clearance (0.42 m) are well above the 0.48 m capsule diameter. No bug identified; no headless test added (no reproduction case). Debt closed as "sin issue reproducible".

## v0.4.0

### QA FP/UX

- Headless FP suite (Godot): victim states, detector alarm, fire visuals, player start, technical HUD — all PASS.
- `FPVisibilityOverlay` smoke layer transition confirmed continuous (42 cm band); no step-function issue.
- Known minor debt: `_apply_stance(immediate)` camera easing not implemented — resolved in v0.4.0+ux-polish.

## v0.4.0-validation-rc2

### Validation — 345/350 PASS, 5 VALID_GAP

- **Phase 2A** — zonal mass sync (`upper_gas_kg`/`lower_gas_kg`) for all rooms in `ThermalSystem`.
- **Phase 2B** — combustion O₂ routing: consumption and throttle from `o2_upper`; `fire_o2_mode="upper"` for bedroom case.
- **Phase 2C** — canonical doorway exchange in `cfast_two_room_door_open`; RMSE 53.8 °C (threshold ≤60 °C).
- **Phase 2D** — HVAC two-zone O₂ mass balance: return extracts from `o2_upper`, supply from `o2_lower`; `cfast_hvac_t300_o2` PASS.
- **Phase 2E-bedroom** — per-case O₂ calibration for `cfast_bedroom_closed_door`; all 5 O₂ checks PASS.
- **Phase 4B** — wall reradiation during active fire (`phase4b_wall_reradiation_during_fire_enabled`); `cfast_slow_growth_sealed` temperature checks PASS.
- **Phase 5A sweep** — 15-config per-case sweep for Group A (`cfast_r0_window_360`); confirmed VALID_GAP, no viable fix without canonical two-zone architecture.
- **Validation milestone closed 2026-06-21** — final baseline 345/350 PASS, 5/350 required FAIL (all VALID_GAP, structural Phase 2/3+). See `docs/validation/GAPS_INVENTORY.md`.

Required FAIL summary:

| Group | Checks | Root cause |
|-------|--------|------------|
| A — `cfast_r0_window_360` | 3 O₂ upper checks | Requires canonical two-zone O₂ architecture (Phase 2+) |
| C — `cfast_corridor_chain` | 2 temp_upper checks | Requires two-zone pressure/exchange ODE (Phase 3+) |

### Product / FP

- **HUD temperature blend** (`497b663`) — replaces step-function `temp_at_N_m_c` lookup with a display-side lerp (±25 cm band around `thermal_layer_m`). Eliminates HUD temperature jumps when the hot layer crosses player eye height. No physics changed.

### Documentation and Repository Structure

- Organized documentation into `docs/audits/`, `docs/architecture/`, `docs/roadmaps/`, `docs/validation/`, `docs/planning/`, `docs/handoff/`, `docs/archive/`, and `docs/literature/`.
- Added documentation entrypoints: `docs/INDEX.md`, `docs/COMMANDS.md`, `docs/LOCAL_WORKSPACE.md`, `docs/ARTIFACT_POLICY.md`, `docs/LINK_AUDIT.md`, and `docs/RELEASE_CHECKLIST.md`.
- Added architecture documents: `PROGRAM_FLOW.md`, `CONTRIBUTOR_GUIDE.md`, `MODULE_BOUNDARIES.md`, and `REFACTOR_PLAN.md`.
- Added ADRs for documentation layout, script/tool boundaries, validation lanes, artifact policy, and local literature.
- Added audit issue index and templates for future ADRs, audits, release notes, and technical issues.
- Moved root session notes, temporary artifacts, exploratory scripts, and local literature into documented archive/library locations.

### Tooling

- Added `scripts/check_docs_links.py` for lightweight Markdown link checks.
- Added `scripts/clean_workspace.ps1` for safe cleanup of ignored local artifacts.
- Added documentation and product Python GitHub Actions workflows.
- Added `tools/diag_fp_temp_jump.json` — diagnostic scenario for reproducing HUD temperature layer-crossing jumps.

## v0.4.0-validation-rc1

### Validation Status

- Legacy required checks documented as passing.
- Two-Zone M4 contract documented as opt-in and passing.
- Known non-gating HVAC and empirical flashover gaps documented.

### Notes

- See `docs/validation/SIMUFIRE_VALIDATION_SUMMARY_2026-05-31.md` and `docs/validation/STATUS_VALIDATION.md` for validation detail.
