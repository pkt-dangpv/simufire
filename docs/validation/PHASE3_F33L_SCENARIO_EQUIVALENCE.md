# Phase 3 F3.3l - Corridor-chain scenario equivalence

Date: 2026-07-23

## Decision

GO for the validation correction. STOP before commit.

The committed `cfast_corridor_chain.json` did not reproduce the three-room
CFAST topology. Opening overrides are matched by exact `a -> b` direction in
both runners, but the historical correction used `1 -> 2` and `0 -> 4`.
The template stores those doors as `2 -> 1` and `4 -> 1`, so neither override
was applied.

The runtime consequently kept five Hall connections open:

- Salon `0 -> 1`;
- Kitchen `4 -> 1`;
- Bedroom 1 `2 -> 1`;
- Bedroom 2 `3 -> 1`;
- Bathroom `5 -> 1`.

CFAST has only Salon-Hall and Hall-Bedroom 1.

## Correction

The case now:

- keeps `0 -> 1` open at 0.9 m;
- keeps `2 -> 1` open and applies the CFAST width of 0.9 m;
- closes `3 -> 1`, `4 -> 1` and `5 -> 1`;
- keeps the exterior openings closed;
- writes the text and CSV reports from the same official run.

No engine coefficient, expected value or tolerance changed.

`tests/test_cfast_corridor_chain_topology.py` fixes the direction and
open/closed contract so this mismatch cannot silently return.

## Runtime proof

The 180 s F3.3k connection ledger contains only:

- `opening:0`, rooms `0 <-> 1`;
- `opening:2`, rooms `1 <-> 2`.

Each connection appears in both directions and in the opening/pressure
families. No route exists for rooms 3, 4 or 5.

Current topology-equivalent canonical accepted-route totals:

| Direction | Mass | Sensible enthalpy |
|---|---:|---:|
| R0 -> Hall | 59.806 kg | 4.491 MJ |
| Hall -> R0 | 54.474 kg | 1.304 MJ |
| Hall -> R2 | 55.186 kg | 1.332 MJ |
| R2 -> Hall | 51.854 kg | 0.428 MJ |

The net R0-Hall gain is `5.332 kg / 3.188 MJ`, versus CFAST
`7.250 kg / 6.302 MJ`. Hall-R2 net mass is close (`3.332 kg` versus
`3.434 kg`), but SimuFire exports much less enthalpy (`0.905 MJ` versus
`2.049 MJ`). The low Hall-R2 export masks part of the R0-Hall source deficit.

Net direct Hall gain remains `2.283 MJ`, versus CFAST `4.253 MJ`.

## Required checks

Godot 4.7.1 official run, 600 s:

| Check | Before | F3.3l | CFAST | Tolerance | Result |
|---|---:|---:|---:|---:|---|
| R0 temp 180 s | 188.85 C | 146.60 C | 159.82 C | 15 C | FAIL -> PASS |
| R0 temp 300 s | 146.87 C | 117.53 C | 166.27 C | 20 C | PASS -> FAIL |
| R0 temp 600 s | 105.58 C | 94.56 C | 168.80 C | 30 C | FAIL |
| R0 O2 upper 480 s | 0.0995 | 0.1401 | 0.1123 | 0.028 | PASS |
| R0 O2 upper 600 s | 0.0987 | 0.1329 | 0.0957 | 0.015 | PASS -> FAIL |

The two R2 O2 point checks remain non-gating deviations. RMSE remains within
its non-gating 60 C limit (`52.16 C`).

Group C therefore changes from two to three required VALID_GAP:

- remove `cfast_chain_r0_t180_temp_upper_c`;
- add `cfast_chain_r0_t300_temp_upper_c`;
- keep `cfast_chain_r0_t600_temp_upper_c`;
- add `cfast_chain_r0_o2_t600_o2`.

The global state changes from `348/353 PASS, 5 VALID_GAP` to
`347/353 PASS, 6 VALID_GAP`. This is accepted as a scenario-correctness
improvement. Hiding the additional physical gap would be worse than the lower
score.

## Physical interpretation

The old 180 s overshoot was partly sustained by non-CFAST room reservoirs.
Once those branches close, R0 loses heat too early and retains too much upper
O2 late. The remaining owner is coupled:

- insufficient hot-mass and enthalpy residence at R0-Hall;
- incorrect late combustion/O2 coupling;
- not excessive Hall-R2 mass export;
- not a scenario geometry or runner mismatch.

## Verification contract

- Godot 4.7.1 official case run: PASS.
- Connection-ledger proof: exactly two active interior connections.
- CSV: 366 rows, 115 legacy columns, 0 physics FAIL, 55 D2PRE WARN.
- Focused validation and Phase 3 tests: `322/322 PASS`.
- Physics suite: `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`.
- ILV suite: `15 PASS / 14 CTRL / 0 FAIL`.
- Gap inventory: `347/353 PASS`, 6 VALID_GAP, 71 non-gating.
- Validation guardrails: `10/10 PASS`.
- Expected values and tolerances: unchanged.
- Reports regenerated only for `cfast_corridor_chain`.
- HVAC: untouched and deferred.

## Next phase

F3.3m must build a time-windowed R0-to-Hall source correspondence at
60/120/180/300/600 s. It should separate:

1. source upper inventory and temperature;
2. opening versus pressure mass flow;
3. accepted lower/upper routing;
4. combustion/O2 throttling;
5. net enthalpy delivered to Hall.

Do not implement another gain or authority promotion until that audit assigns
the early mass deficit and late O2/enthalpy deficit to explicit owners.
