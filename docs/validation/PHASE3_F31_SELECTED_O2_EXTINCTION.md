# Phase 3+ F3.1 selected-O2 extinction

Date: 2026-07-16

## Decision

F3.1 closes with two separate decisions:

- **GO** for the selected-O2 extinction invariant in `CombustionSystem`.
- **NO-GO** for publishing the Phase 3 shadow as authoritative room state.

The guard is useful and independently testable, but it does not by itself
remove every fire observed with near-zero upper-layer O2. In the affected
controls the configured combustion source is `plume_lower`, and lower-layer O2
remains near ambient while upper-layer O2 is exhausted. The guard correctly
follows the selected source; choosing the physically authoritative source is a
separate motor decision.

## Observed zombie-fire mechanisms

| Mechanism | Status after F3.1 |
|---|---|
| HRR smoothing, latent smolder or pool release survives after the selected O2 source reaches its extinction limit | Fixed |
| `plume_lower` selects `o2_lower` near 20.9% while `o2_upper` is near zero | Open |
| Analytic `fire_o2_independent` curve ignores O2 by design | Preserved |

Examples from the current reports:

- `cfast_two_floor_stairwell`: 41 rows with HRR above 10 kW and
  `o2_upper <= 1%`; the selected source is `plume_lower`.
- `fuel_balance_diag_sealed` and `o2_stoich_diag_sealed`: 34 such rows each;
  at 300 s HRR is about 3395 kW, `o2_upper` is about 0.09% and `o2_lower` is
  about 20.9%.
- `cfast_slow_growth_sealed`, which explicitly selects upper O2, has no such
  rows.

## Motor invariant

When the selected combustion O2 source is at or below its declared extinction
threshold, and the analytic O2-independent mode is not active:

1. Solid pyrolysis demand, fresh flame, smolder and retained-gas generation
   are zeroed before the retained pool is updated.
2. Pool/backdraft release cannot start in that tick.
3. Flame, smolder, pool, target, actual and burned HRR are zeroed atomically.
4. `fire_o2_extinguished` is set.
5. The `FireModel` remains attached so later reventilation can be handled by
   existing latent/re-ignition semantics.

The FDS-extinction path uses its configured extinction threshold. The regular
path uses `o2_min_for_flame`.

## Regression coverage

- `tests/test_f31_zero_o2_extinction.py` checks the explicit guard, complete
  heat-release reset, retained fire state and analytic-mode exemption.
- `tests/fixtures/f31_zero_o2_extinction.gd` executes three runtime controls:
  below threshold, just above threshold and O2-independent at zero O2.
- Runtime result: `F31_ZERO_O2_EXTINCTION_RUNTIME_PASS`.
- Focused Python result: 17 PASS.

A fresh 300 s shadow run of `fuel_balance_diag_sealed` retained all 366 rows
and all 115 legacy columns bit-identically. The visible upper-O2 zombie remains
because the selected source is lower O2, confirming that the guard neither
hides nor accidentally changes the source-selection problem.

## Why sealed authority is NO-GO

`Phase3ZoneMassSystem` remains a passive return-value ledger. The sealed
controls still report incomplete physical ownership:

- `phase3_shadow_needs_flux_owner = 1`;
- maximum mass residual: `0.08814274 kg`;
- maximum energy residual: `25.83801043 kJ`;
- combustion-owned mask reaches 6, but ownership is not complete.

Publishing that shadow into `RoomModel` would make an incomplete ledger
authoritative and risk double ownership of combustion, energy and O2. No
`phase3_canonical_zone_state_enabled` flag was added.

## Validation state

| Check | Result |
|---|---|
| Focused F3.1/fire-O2 tests | 17 PASS |
| Phase 3 + F3.1 + ILV tests | 290 PASS |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 PASS, 5 VALID_GAP |
| Guardrails | 9/10; only expected R2-1 while motor is dirty |
| Official reports/baselines/tolerances | Unchanged |

The full Python run has 892 PASS and 19 failures: 18 pre-existing structural
test debts plus `test_exit0_real_json`, which reflects the expected R2-1
freshness failure while the motor file is uncommitted.

## Next gate

Do not start F3.2 and do not enable canonical room-state authority.

The next motor phase is F3.1a: define and test the authoritative combustion O2
source for sealed/two-zone fires. It must be opt-in/default OFF, compare
upper/lower/plume-zone semantics in dedicated controls, preserve intentional
reventilation, and stop if corpus HRR/FED deltas cannot be attributed. No
global switch from `plume_lower` to `upper` is approved by this decision.
