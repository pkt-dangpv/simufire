# Phase 3 H3.2-S0d6a O2 State Diagnosis

Date: 2026-08-07
Scope: **diagnosis only.** No physics, clamp, HVAC or integrator change. No new
simulation was run — every number below is read-only post-processing of the CSVs
the S0d6 campaign already produced.

Status reviewed 2026-08-19: **diagnosis accepted.** This closes S0d6a only. It
does not select an authoritative O2 representation, close H3.2-S, create the
source integrator or grant runtime authority. The next allowed slice is S0d6b,
a design-only authority/invariant contract evaluated before any physics change.

Verdict: **there is no authoritative O2 state.** The engine carries two de-facto
authorities — the bulk for combustion decisions, the zones for tenability — with
no rule reconciling them, and they disagree on **74.67 %** of logged rows.

## 1. The question

> Which of `room.o2`, `room.o2_upper`, `room.o2_lower` is authoritative, and why
> does `ThermalSystem` replace `room.o2`?

Authority is decided by who **reads** a state, not who writes it. So this phase
inventories consumers first.

## 2. Consumer map — who reads which state

| Consumer | Reads | Site |
|---|---|---|
| FED hypoxia (tenability) | `o2_upper` if in upper zone else `o2_lower` — **never `room.o2`** | `ThermalSystem.gd:4490` |
| Fire O2 reference / HRR throttle / extinction | one of **seven** modes selecting `o2`, `o2_upper`, `o2_lower`, a 50/50 lerp, `plume_lower`, `plume_upper` or `plume_blend` | `CombustionSystem.gd:2715-2765` |
| Flashover / re-ignition viability | **`room.o2`** | `SimulationEngine.gd:3975` |
| Backdraft gates | **`room.o2`** | `CombustionSystem.gd:1725, 1803` |
| Pool-fire burn gate | **`room.o2`** | `CombustionSystem.gd:1827` |
| LOI material ignition | **`room.o2`** | `CombustionSystem.gd:2661, 3488` |
| Latent-fire floor and viability margin | **`room.o2`** | `CombustionSystem.gd:3130, 3144` |
| CO oxidation gate | **`room.o2`** | `SimulationEngine.gd:3696` |
| CO vent multiplier / afterburn | `o2_upper` | `CombustionSystem.gd:2052, 2068` |
| Upper-zone HRR throttle | `minf(room.o2, room.o2_upper)` — **mixes two inventories** | `CombustionSystem.gd:1505` |
| Reported room minimum O2 | `minf(room.o2, room.o2_lower)` — **mixes two inventories** | `SimulationEngine.gd:4681` |
| CSV / technical summary | all three, exported **separately and unreconciled** | `SimulationStateBuilder.gd:244-246` |

**Two load-bearing authorities.** Every combustion-viability decision — can it
burn, can it re-ignite, can it flash over, can CO oxidise — reads `room.o2`.
Every tenability decision reads the zones. Nothing reconciles them, and two
consumers paper over the gap with `minf` across inventories, which is not a
physical operation on either.

## 3. The states disagree, measured

A volumetric blend of two values must lie between them. So a geometry-free test
falsifies the "bulk is a mixture of its zones" reading without assuming any room
dimensions: whenever `room.o2` falls outside
`[min(o2_lower, o2_upper), max(o2_lower, o2_upper)]`, it provably is not a
mixture of its own zones at that instant. The distance outside the bracket is a
**lower bound** on the inconsistency.

Across the ten S0d6 cases, 20 059 logged room-steps:

| Case | rows | outside bracket | > 1 % FED move | worst gap |
|---|---:|---:|---:|---:|
| `postfire_decay` | 11 406 | 10 396 | 8 813 | 2.63e−02 |
| `ppv_attack_pressurized` | 4 206 | 3 055 | 2 421 | 1.10e−02 |
| `v1_backdraft_accumulation` | 786 | 524 | 472 | 3.27e−02 |
| `cfast_two_floor_stairwell` | 793 | 402 | 259 | 1.99e−02 |
| `fuel_balance_diag_sealed` | 366 | 242 | 221 | 3.55e−02 |
| `o2_stoich_diag_sealed` | 366 | 242 | 221 | 3.55e−02 |
| `cfast_slow_growth_sealed` | 1 086 | 81 | 81 | 3.65e−02 |
| `cfast_hvac_residential` | 366 | 32 | 32 | **9.13e−02** |
| `cfast_corridor_chain` | 366 | **4** | 0 | 3.00e−05 |
| `cfast_r0_window_360` | 318 | 0 | 0 | 0 |
| **TOTAL** | **20 059** | **14 978 (74.67 %)** | **12 520 (62.42 %)** | **9.13e−02** |

The divergence is **not** one-directional: 31.22 % of rows have the bulk below
both zones, 43.45 % above both. The sealed diagnostics run over-depleted in the
bulk; `postfire_decay` runs over-rich.

### Worst instance

`cfast_hvac_residential`, room 0, t = 600.1 s:

```
room.o2   = 0.000650      <- combustion, re-ignition, LOI, backdraft read this
o2_upper  = 0.091950
o2_lower  = 0.209000      <- FED hypoxia reads this for a standing occupant
```

The same room, at the same step, is simultaneously **anoxic** to every combustion
decision and **at ambient in the breathing zone** to every tenability decision.
The bulk is `0.09130` of fraction outside the bracket of its own zones — roughly
**493 times** a 1 % move in `FED_hypoxia`.

## 4. Decision-level disagreement

Counting rows where the bulk says a flame cannot be sustained
(`room.o2 < fire_o2_min_for_flame = 0.122`) while the lower zone that FED reads
is still at or above `0.19`:

**399 of 20 059 rows (1.99 %)**, concentrated in `postfire_decay` (260),
`v1_backdraft_accumulation` (37), `cfast_hvac_residential` (37) and
`cfast_two_floor_stairwell` (24). First occurrence:
`cfast_hvac_residential` room 0 at t = 240.0 s, `room.o2 = 0.117170` against
`o2_lower = 0.209000`.

These are exactly the conditions under which re-ignition, backdraft and
post-fire behaviour are decided, which is why anomalies cluster there.

## 5. Why `ThermalSystem` replaces `room.o2` — and the S0d6 framing corrected

S0d6 reported `thermal_zone_sync_blend` as the largest **measured unowned
correction**, which it is. But this phase shows that framing was incomplete in an
important way: **the blend is not the cause of the divergence — it is the only
thing that repairs it.**

The evidence is in the two right-hand columns of the S0d6 campaign. `o2_zone_sync_kg`
is non-zero in exactly **one** of the ten cases, `cfast_corridor_chain`
(7.15 kg accumulated), and that case has by far the **fewest** excursions:
4 of 366 rows, worst gap 3.00e−05, and **zero** rows above a 1 % FED move. Every
case with zero sync shows one to two orders of magnitude more divergence.

So the mechanism is:

1. `room.o2` is depleted by combustion and ACH through `o2_mass_kg`
   (`OxygenExchangeSystem.gd:461`), on the **room** air mass.
2. `o2_upper` and `o2_lower` are updated by entirely separate rules —
   entrainment, plume depletion, zone ACH, exterior replenish — on **zone**
   masses, and `o2_lower` is documented as *"Variable persistente; NO derivada
   de o2"* (`RoomModel.gd:48`).
3. Nothing forces consistency. The only re-synchronisations are the volumetric
   blends at `ThermalSystem.gd:3409/3426/3637/3658` and the second one at
   `OxygenExchangeSystem.gd:666`, and both are **conditional**: the thermal ones
   need the doorway counterflow or canonical doorway paths, the OES one needs
   `effective_plume_lower or _phase2b_upper_active`.
4. Where no condition fires, nothing re-synchronises and the three states drift
   apart without limit — up to 9.13e−02 of fraction.

`ThermalSystem` therefore replaces `room.o2` **because it is the only place that
re-derives the bulk from the zones after a zonal transport**, and it books the
discrepancy into `o2_zone_sync_kg_*` precisely because the discrepancy has no
physical donor. That accumulator is honest labelling of a repair, not of a
transport — which is what `RoomModel.gd:204` says.

## 6. Answer

> Which state is authoritative?

**None.** The engine has two authorities:

- **`room.o2` is authoritative for combustion**: viability, extinction,
  re-ignition, flashover, backdraft, LOI and CO oxidation all gate on it.
- **`o2_upper` / `o2_lower` are authoritative for tenability**: FED hypoxia never
  reads `room.o2`.

There is no invariant, no reconciliation rule and no ordering guarantee between
them; re-synchronisation is conditional and, in nine of ten measured cases, never
fires. Two consumers bridge the gap with `minf` across inventories, which is a
reporting convenience, not physics.

This is the concrete sense in which the engine is **not yet a single conservative
model of O2**: it conserves zonal state and separately maintains a bulk, then
occasionally rebuilds one from the other with a numerical operation that is
material in 62 % of rows.

## 7. What was deliberately not done

No physics change. No clamp touched. No HVAC work. No integrator. No new flag, no
new instrumentation, no re-run of the campaign. No expected value, tolerance,
CTRL or VALID_GAP modified. The candidate remedies — electing one authority,
deriving the other, or forcing an invariant — are **not** proposed here; choosing
between them is a physics decision that needs its own gate.

## 8. Gate state and next work

**S0d6a closes as a diagnostic GO only.** It establishes that the current motor
does not have one conservative O2 state and that the conditional blends are
repairs, not the root cause. It does not make either representation authoritative.

The next allowed phase is **H3.2-S0d6b, design only**. It must compare, without
changing runtime behavior:

1. zonal O2 mass as the conserved authority with bulk derived from upper/lower;
2. bulk O2 mass as authority with an explicit conservative zonal partition; and
3. one atomic O2 state carrying bulk and zonal views under a single invariant.

The design must account for combustion selection modes, FED, extinction,
re-ignition, backdraft, LOI, exterior exchange, parcels and the two existing
conditional recompositions. It must reject `minf` between independent
inventories as a reconciliation rule and must not include HVAC implementation.

H3.2-S remains open, HVAC remains deferred, no integrator exists, H3.2b remains
an independent prerequisite for H3.3, and no runtime authority is granted.
