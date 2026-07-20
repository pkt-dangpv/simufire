# Phase 3+ F3.2b5b canonical wall and ambient energy ownership

Date: 2026-07-19

## Scope

F3.2b5b replaces six legacy-derived thermal requests only inside the passive
canonical shadow:

- `thermal_upper_radiative_loss`
- `thermal_upper_to_ambient`
- `thermal_wall_absorption`
- `thermal_wall_emission`
- `thermal_lower_decay`
- `thermal_lower_fresh_air_cooling`

The opt-in flag is `phase3_canonical_wall_ambient_shadow_enabled=false`.
Legacy `RoomModel` state, FED, official reports, expected values, tolerances
and VALID_GAP classifications remain unchanged.

## Architecture decision

The legacy wall temperatures cannot be shared with the canonical shadow. Both
the lumped fallback wall and the optional five-node material wall are driven
by legacy gas temperatures, so reusing either state would preserve the
cross-state contract diagnosed in F3.2b4/F3.2b5a.

F3.2b5b therefore owns a separate persistent lumped canonical wall reservoir:

```text
canonical upper gas <-> canonical wall <-> ambient
canonical lower gas <-> canonical wall <-> ambient
```

The reservoir reuses declared room geometry, material heat capacity and
existing thermal-rate settings. It never reads legacy wall temperature or
legacy gas temperature. Gas-to-wall values are positive; wall-to-gas values
are negative. Direct ambient losses and wall decay are explicit boundary
terms.

Every gas-facing route is queued in one atomic energy bundle. A common finite-
reservoir equilibrium bound prevents the upper gas, lower gas and wall from
crossing their shared equilibrium in one step. The wall state is committed
only after the atomic result is known.

## Telemetry

The flag adds 25 CSV columns after the prior canonical shadow schema. They
include wall energy and temperature before/after, signed requested and
accepted upper/lower exchange, radiative and ambient terms, accepted fraction,
cumulative absorbed/emitted/ambient energy, clamp energy and two residuals:

```text
gas_wall_residual = delta(E_gas_from_wall) + delta(E_wall) + wall_decay
boundary_residual = delta(E_gas) + delta(E_wall) + E_removed_to_ambient
```

Both residuals are exactly zero in the direct fixture and Group A scratch run.

## Controls

The direct Godot fixture covers hot gas heating the wall, hot wall heating the
gas, equal temperatures, a finite-equilibrium cap, simultaneous upper/lower
exchange, 500 repeated conservative steps, duplicate bundles and an upstream
energy-loss conflict.

The 60 s no-fire OFF/ON control has 42 rows. All shared non-shadow columns are
identical; canonical wall energy, exchange, ambient removal and residual stay
exactly zero.

The Group A OFF/ON control has 228 rows. ON adds only the 25 opt-in columns.
No non-`phase3_*` shared column changes. The replacement intentionally changes
the downstream canonical shadow because its persistent energy state is now
different.

The new OFF run is also bit-identical to the accepted F3.2b5a ON run across
all 228 rows and 418 shared columns.

## Group A result

| Metric | F3.2b5a/OFF | F3.2b5b/ON | CFAST |
|---|---:|---:|---:|
| Upper temperature at 180 s | 162.31 C | 136.66 C | 259.59 C |
| Upper temperature at 300 s | 257.29 C | 158.88 C | 173.01 C |
| Lower temperature at 350 s | 22.79 C | 33.60 C | 66.53 C |
| Lower energy at 360 s | 0 kJ | 49.14 kJ | n/a |
| Shadow upper O2 at 240 s | 0.10007 | 0.10559 | 0.08511 |
| Shadow upper O2 at 350 s | 0.07395 | 0.06639 | 0.06598 |
| Shadow upper O2 at 360 s | 0.07379 | 0.06686 | 0.06451 |
| Wall temperature at 360 s | n/a | 25.71 C | n/a |
| Wall energy at 360 s | n/a | 9131.5 kJ | n/a |
| Wall boundary residual | n/a | 0 kJ | n/a |

The canonical lower reservoir no longer reaches zero at the opening. All
three Group A O2 checks are inside their existing tolerances when evaluated on
the shadow state. Temperature is materially improved late in the run, but the
upper layer remains too cool at 180 s and the lower layer remains too cool at
350-360 s.

The wider canonical state still reports material mass and energy residuals
from earlier unowned or mismatched paths. F3.2b5b does not claim to solve
those residuals.

## Verification

| Check | Result |
|---|---|
| Godot 4.7.1 direct fixture | PASS |
| New plus F3.2b5a structural tests | 21/21 PASS |
| Broad Phase 3/two-zone sweep | 404 PASS, 4 unrelated pre-existing structural failures |
| Physics coherence suite | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV suite | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 PASS, 5 VALID_GAP |
| Validation guardrails | 9/10; only R2-1 from dirty motor |
| Official reports or baselines changed | No |

One attempted scratch control inherited an official CSV path from its case
JSON. The generated file was copied to scratch and the official CSV was
immediately restored from HEAD before any suite was run.

## STOP gate

Decision: **mechanism GO; canonical authority and Group A retirement NO-GO**.

The next gate is F3.2b5c. It must rerun mass, energy and EOS pressure
equivalence with all canonical thermal owners active, quantify the remaining
unowned causes, and include independent fire/no-fire/opening controls. No
further thermal-rate tuning is allowed before that accounting is complete.
