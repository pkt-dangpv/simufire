# Phase 3+ F3.2b7 post-opening combustion/O2/plume coupling

Date: 2026-07-20

## Decision

**Shadow mechanism GO. Canonical authority and Group A retirement NO-GO.**

F3.2b6 supplies enough fresh lower-zone oxygen after the exterior window
opens, but the combustion evaluator continued to read the depleted upper
reservoir. F3.2b7 couples combustion and plume transport to the lower air
reservoir only while a real canonical exterior counterflow request exists.
The feature is default OFF and does not write `RoomModel`, `FireModel`, FED or
official validation reports.

## Root cause

At 420 s in `cfast_r0_window_360`, F3.2b6 requested about 0.0091 kg O2 per
physical step from exterior counterflow. Full 1280 kW combustion needs about
0.0081 kg O2 per step. The fresh-air supply was therefore sufficient, but it
remained in the lower zone while combustion selected upper O2 and accepted
only 490 kW.

The first lower-source experiment recovered HRR but exposed a second issue.
Moving only stoichiometric combustion air left no excess plume O2 for the
upper zone. The canonical plume preview contained only the height-dependent
Heskestad term. F3.2b7 adds the source term `0.0018 * Qc` only when exterior
counterflow is active. The two terms remain separately visible in telemetry.

## Contract

- `phase3_canonical_post_opening_coupling_shadow_enabled` defaults to `false`.
- The lower source requires an explicit pre-step exterior counterflow request
  and non-empty lower inventory. Interior openings cannot activate it.
- Combustion O2 and plume air share one lower-air parcel. The lower O2 debit is
  the entrained O2; combustion consumes its accepted share and only the
  remainder reaches upper.
- The minimum plume mass is the accepted combustion O2 divided by the lower
  O2 fraction. The normal plume request may exceed that minimum.
- The Heskestad source term is opt-in inside this coupling and is zero before
  the exterior opening and in controls without exterior counterflow.
- O2, gas, energy and generated species remain in one atomic combustion
  bundle. No projection or residual bucket is used.

## Group A result

Room 0 values after the window opens:

| Time | Metric | F3.2b6 | F3.2b7 | CFAST |
|---:|---|---:|---:|---:|
| 370 s | upper O2 | 0.0775 | 0.0742 | 0.0638 |
| 370 s | interface | 0.442 m | 0.365 m | 0.100 m |
| 370 s | HRR | 204 kW | 603 kW | 240 kW |
| 380 s | upper O2 | 0.0810 | 0.0763 | 0.0616 |
| 380 s | interface | 0.752 m | 0.522 m | 0.522 m |
| 380 s | HRR | 313 kW | 1125 kW | 1280 kW |
| 400 s | upper O2 | 0.0802 | 0.0760 | 0.1072 |
| 400 s | interface | 1.345 m | 0.830 m | 0.968 m |
| 400 s | HRR | 340 kW | 1280 kW | 1280 kW |
| 420 s | upper O2 | 0.0928 | 0.0906 | 0.1320 |
| 420 s | interface | 1.574 m | 1.084 m | 1.020 m |
| 420 s | HRR | 490 kW | 1280 kW | 1280 kW |

The mechanism closes the HRR and interface feedback materially. It does not
yet reproduce the late upper-O2 recovery, and it advances HRR too strongly at
370 s. Those are authority blockers, not permission to tune a case-specific
multiplier. The three official Group A VALID_GAP entries remain unchanged
because the canonical state is still shadow-only.

## Controls and invariants

- Group A and no-fire controls retain all 115 legacy columns exactly.
- The open no-fire control retains 78 rows and all 466 columns shared with
  F3.2b6. Coupling and source-term fields remain zero.
- The 600 s `cfast_corridor_chain` control emits zero coupling activations and
  zero Heskestad source term, proving interior doors do not trigger F3.2b7.
- Persistent continuity, combustion, counterflow and coupled lower-O2
  residuals are exactly zero in the audited runs.
- The direct Godot 4.7.1 fixture covers closed source selection, lower-source
  selection, zero-lower-O2 extinction, atomic debit and source-term opt-in.
- Physics: 9 PASS / 15 CTRL / 5 WARN / 0 FAIL.
- ILV: 15 PASS / 14 CTRL / 0 FAIL.
- Gap inventory: 348/353 required PASS, 5 VALID_GAP, 71 non-gating gaps.
- Guardrails: 9/10; only R2-1 reports the expected dirty motor tree.

## Remaining limitations

The canonical evaluator still consumes a legacy HRR proposal, and the plume
preview still reads that proposal. Publication to live state remains
forbidden. Late upper O2 remains below CFAST even though HRR and interface are
close, so F3.2b7 is not a production calibration result.

## Next gate

Proceed to F3.3 as a default-OFF interior two-zone opening diagnosis and
implementation. Reuse explicit canonical upper-out/lower-in routes, carry
mass, enthalpy, O2 and species atomically, and validate
`cfast_two_room_door_open`, `cfast_corridor_chain` and the stairwell control.
Do not publish canonical state, retire Group A/C, change tolerances or begin
HVAC.
