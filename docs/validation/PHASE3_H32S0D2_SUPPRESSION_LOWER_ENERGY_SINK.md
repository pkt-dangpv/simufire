# Phase 3 H3.2-S0d2 Experimental Suppression Lower Energy Sink

Date: 2026-08-05.

## Decision

**GO to keep `phase3_suppression_lower_energy_sink_enabled` as an experimental,
default-OFF flag. NO-GO to promote it.** The correction is proven safe and
proven to work, but it does not yet justify changing official physics, and it
does not close B1-lower.

S0d stays open, no integrator exists, HVAC stays deferred, species/O2 stay
pending, H3.2-S stays blocked, H3.2b and H3.3 are not started and no runtime
authority was granted.

## Diagnosis

| Question | Answer |
|---|---|
| Current `cooling_kj` | `water_l * suppression_heat_absorption_kj_per_l`, default `950.0 kJ/L`, with `water_l = flow_lpm * dt / 60 * effectiveness` |
| Intended split | upper `suppression_upper_heat_fraction = 0.68`, lower `suppression_lower_cooling_fraction = 0.18`; the remaining 0.14 is surface cooling and unmodelled loss |
| Maximum acceptable lower removal | `room.lower_energy_kj`. The legacy proxy caps a temperature drop over `max(1.0, rho * volume_m3)`, which is the whole-room air mass, not `lower_gas_kg`, so it is not a valid energy bound |
| Physical meaning of the sink | water sprayed into the lower layer absorbs sensible heat and evaporates; it is neither an exterior flow nor a wall exchange |
| Counterpart without inventing mass | `room.steam_kg`, already incremented at the same site, carried as metadata. No mass is added to any zone |
| Empty or near-empty `lower_gas_kg` | `lower_energy_kj` is zero, so the accepted amount is zero and the sink returns early. No division by zone mass, no NaN |
| Regimes | two-zone (default): `project_room_state` derives `temp_lower_c` from `lower_energy_kj`, so the legacy temperature write is dead. Legacy: the temperature write survives and `lower_energy_kj` is unused |
| Can it be fixed without touching legacy? | Yes. The correction is gated on the new flag **and** `two_zone_solver_enabled`; the legacy regime is untouched |

## Design

`_apply_suppression_lower_energy_sink()` runs before the legacy temperature
write and does nothing unless the flag is on and two-zone is active. It reuses
the legacy formula verbatim, re-expressed as energy over the same proxy mass:

```
requested_lower_cooling_kj = lower_drop_c * lower_mass_kg
accepted_lower_cooling_kj  = min(requested, max(0, room.lower_energy_kj))
zone_fire_solver.add_lower_energy(room, -accepted, ambient_c)
```

The owner event `suppression_lower_energy_sink` is a signed `local_source` whose
`lower_energy_delta_kj` is measured around that single mutation. The request is
never recorded as accepted: `requested`, `accepted`, `rejected` and
`available_lower_energy_kj` all travel as metadata. The legacy temperature write
is left in place; with the energy already reduced, the projection derives the
correct temperature from it.

The upper sink approved in S0d1 is untouched and still emitted exactly once.
Projection keeps its own ledger and is never counted as suppression.

## OFF/ON matrix

`OFF` is byte-identical to the S0d1 checkpoint wherever the pair is comparable.

| Case | Duration | OFF == ON | OFF == checkpoint | Note |
|---|---:|---|---|---|
| `cfast_suppression_water` | 150 s | identical | **yes** | suppression active |
| `v8_suppression_reburn` | 150 s | identical | **yes** | suppression not yet active |
| `cfast_suppression_water` | 60 s | identical | n/a | suppression declared, not active |
| `victim_fed_incapacitation` | 60 s | identical | n/a | control |
| `fuel_balance_diag_sealed` | 30 s | identical | **yes** | control |
| `v8_suppression_reburn` | 155 s | **differs** | n/a | first step inside the 150-160 s window |
| `v8_suppression_reburn` | 300 s | **differs** | n/a | suppression plus reburn |

### Why several suppression pairs stay identical

`cfast_suppression_water` keeps `temp_lower_c` pinned at exactly the ambient
`20.00 °C` for all 186 logged rows, so the legacy cap
`max(0, temp_lower_c - ambient_c)` is zero and the request itself is zero. This
is a **second, deeper reason** the lower sink is inert: not only is its output
discarded, its input is zero whenever the two-zone lower layer carries no
superheat. The correction honours that and removes nothing.

### Measured impact where it does fire

`v8_suppression_reburn`, first step inside the window (155 s, room 0):

| Quantity | OFF | ON |
|---|---:|---:|
| `requested_lower_cooling_kj` | — | 0.0559812 |
| `accepted_lower_cooling_kj` | — | 0.0485827 |
| `rejected_lower_cooling_kj` | — | 0.0073985 |
| `available_lower_energy_kj` | — | 0.0485827 |
| `temp_lower_c` | 20.02 | 20.00 |
| `suppression_upper_energy_sink` | −15.9391 kJ | −15.7438 kJ |

Accepted equals available exactly: the availability cap binds and the remainder
is reported as rejected rather than silently applied.

`v8_suppression_reburn` over 300 s, maximum absolute OFF−ON difference:

| Metric | max abs difference | where |
|---|---:|---|
| `temp_lower_c` | 9.77 °C | t=151.1 s, room 0 (29.77 -> 20.00) |
| `temp_upper_c` | 9.87 °C | t=151.1 s, room 0 (29.88 -> 20.01) |
| `hrr_kw` | 0.20 kW on ~702 kW | t=271.0 s, room 0 |
| `thermal_layer_m` | 0.014 m | t=212.0 s, room 1 |
| `o2` | 4.4e-4 | t=266.0 s, room 1 |
| `fed` | 0.0022 on ~10.34 | t=299.0 s, room 0 |
| `steam_kg` | 0.0 | unchanged everywhere |

Room 0 keeps `hrr_kw > 1 kW` until the end of the window in both runs, so the
extinction and reignition timing does not move. No NaN and no negative energy,
layer depth, O2 or steam value appears in any ON run.

The reading is that the correction does what it claims: during suppression the
lower layer actually loses its superheat instead of having the drop discarded,
while HRR, FED and O2 move by well under 0.1 %.

## Why this is not promoted

- Official suppression scenarios keep the lower layer at ambient, so the
  correction changes nothing there. It cannot be justified as a fix for the
  results the project validates against.
- Where it does fire, it shifts `temp_lower_c` by up to ~10 °C. That is the
  intended behaviour, but it moves a state variable that several expected values
  and tolerances depend on. Promoting it requires a baseline review that this
  phase is explicitly forbidden from doing.
- B1-lower therefore stays open. The remaining question is upstream: whether the
  two-zone projection should leave `temp_lower_c` pinned at ambient at all.

## STOP evidence

- Twelve sequential Godot 4.7.1 fixtures pass, including H1, H2.10, H3.2a,
  H3.2-M atomic acceptance, the coupled bundle shadow, the atomic parcel
  lifecycle and S0a/S0b/S0c/S0d1.
- The S0d2 fixture covers the flag default, OFF equivalence, ON energy removal,
  temperature survival past the sync, `accepted <= requested`,
  `accepted <= available`, non-negative energy, the empty-layer fail-safe, the
  accepted-not-requested owner value, single upper owner, no projection
  double-count, legacy invariance and deterministic IDs. A temporary inverted
  assertion exits 1 with no PASS marker.
- Focused `pytest` for S0a-S0d2 is `80 PASS`. The broad Phase 3/guardrail
  selection is `1403 PASS / 2 FAIL`: the expected R2-1 freshness failure from
  the dirty motor and the pre-existing layer-interface export test.
- Physics coherence is `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`; ILV coherence is
  `15 PASS / 14 CTRL / 0 FAIL`; the gap inventory is unchanged at
  `353 required + 6 VALID_GAP + 71 non-gating`. No Godot process remains.
- No official case sets the flag, no expected value, tolerance, CTRL entry or
  VALID_GAP was touched and no report was regenerated.
