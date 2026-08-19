# Phase 3 H3.2-S0d6b0.2 Zonal Gas-Mass Reliability Audit

Date: 2026-08-19
Revised: 2026-08-19 (S0d6b0.2a) — **two inferences withdrawn, see section 0.**
Scope: **read-only.** No file under `sim/`, no runner, no case file, no report,
no physics, no engine flag, no expected value, tolerance, CTRL or VALID_GAP was
modified. The only additions are a read-only analyser and its contracts.

Question: **can `upper_gas_kg` and `lower_gas_kg` serve as the physical
denominator of a zonal O2 inventory?**

Decision: **INCOMPLETE / BLOCKED ON H3.2b** — justified by the static code trace
and by a non-circular runtime accumulator, **not** by the withdrawn identity.

---

## 0. Withdrawn inferences (S0d6b0.2a)

The first issue of this audit reached the right decision for two wrong reasons.
Both are retracted here. The original text is superseded, not deleted.

### 0.1 The EOS "proof" was tautological — WITHDRAWN

**Claimed:** that `gas_kg == volume_m3_eos * rho(T)` in 20 059/20 059 lower and
11 863/11 863 non-zero upper steps proved projection had reconstructed the mass.

**Reality:** `SimulationStateBuilder.gd:430-431` computes

```gdscript
var upper_volume_m3_eos: float = room.upper_gas_kg / maxf(0.05, upper_density_kg_m3)
var lower_volume_m3_eos: float = room.lower_gas_kg / maxf(0.05, lower_density_kg_m3)
```

The analyser then multiplied that exported volume by the same density and
recovered the input. **It is an algebraic round trip.** The counts measured
nothing but CSV rounding, and the "11 863 = exactly the non-zero upper steps"
coincidence I highlighted was an artefact of the analyser's own `mass > 0` guard,
not a discovery.

The identity survives only as `SELF_DERIVED_EOS_IDENTITY`, a check that the CSV
is internally consistent. It is explicitly labelled as proving nothing about
independence, conservation or projection, and a contract forbids it from driving
any verdict.

### 0.2 "40.86 % degenerate" was a misreading — WITHDRAWN

**Claimed:** `upper_gas_kg == 0` in 40.86 % of room-steps and permanently in
15 of 67 rooms constituted degeneracy, and that "FED reads exactly that value".

**Reality:** an absent upper layer is a **valid one-zone regime**, not a defect.
And `ThermalSystem.gd:4553` already gates on it:

```gdscript
var in_upper: bool = (thermal_exposure_factor >= 0.5 and room.upper_gas_kg > 0.1)
```

so FED, CO, CO2 and HCN all read the **lower** zone whenever the upper layer is
absent or below 0.1 kg. The statement that FED reads an undefined `o2_upper` was
false.

The figure is retained as an observed frequency of the one-zone regime, with no
defect implied.

### 0.3 What survives unchanged

The per-step causal balance remains **INCOMPLETE**, for the reason originally
given: the committed cases log at `log_interval_s = 10.0` while every
`*_mass_delta_kg_step` column covers a single sub-step.

---

## 1. Evidence availability

Telemetry behind `--phase3-zone-diagnostics` and
`--phase3-runtime-ownership-ledger` is rich: 231 columns, complete in all ten
committed cases, **zero missing sentinels**.

Two structural gaps remain:

| Gap | Consequence |
|---|---|
| **The exported residual cannot fail.** `SimulationEngine.gd:1842-1868` computes `residual = observed - sum(stages)` with `stages` including `reconcile` and `projection_clamp` | It closes by construction. Measured **identically zero in every row of all ten cases** |
| **Step deltas are sub-step samples; rows are 10 s apart** | A per-step causal balance is not reconstructable. Two separate drafts of the analyser made this mistake in different guises; both were withdrawn |

Aligning the log interval would require editing a committed case file or the
runner, both forbidden here.

### 1.1 Passive instrumentation that would close the gap

Proposed, **not implemented**:

1. Accumulate each stage delta into a `*_mass_delta_kg_total` column, so an
   interval difference is comparable with an interval difference.
2. Export the `ensured` and `pre_geometry` snapshots `ZoneFireSolver.gd:210,253`
   already builds, plus the per-step projection call count.
3. Emit the residual twice: physical stages only, and including closure.

---

## 2. Static trace — what the code proves

Every write to a zone mass inside `ZoneFireSolver`:

| Line | Statement | Nature |
|---|---|---|
| `:115` | `room.upper_gas_kg = maxf(0.0, room.upper_gas_kg)` | non-negativity clamp |
| `:117` | `room.lower_gas_kg = maxf(0.0, room.lower_gas_kg)` | non-negativity clamp |
| `:121` | `room.lower_gas_kg = maxf(0.0, room.volume_m3() * AIR_DENSITY_REF_KG_M3)` | **seeding** of an uninitialised room |
| `:163-165` | `lower -= moved; upper += moved` | plume transfer, conservative between zones |
| `:264` | `room.upper_gas_kg = max_upper_mass_kg` | **CAP, conditional**: only when `upper > volume * rho_upper` |
| `:266-268` | `upper_volume = upper_gas_kg / rho_upper; thermal_layer_m = height - depth` | **geometry derived FROM upper mass** |
| `:281` | `room.lower_gas_kg = maxf(0.0, target_lower_mass_kg)` | **UNCONDITIONAL overwrite** with `remaining_volume * rho_lower` |
| `:354-356` | `lower += upper; upper = 0.0` | collapse to one zone |

**Proven by code, not inferred:**

- **`CODE_PROVEN_UPPER_CAP`.** Upper mass is carried through untouched **unless**
  it exceeds the mass the whole room could hold at upper density. The cap is
  conditional, and the interface follows the upper mass rather than the reverse.
  Upper mass is therefore the independent zonal quantity.
- **`CODE_PROVEN_LOWER_RECONSTRUCTION`.** Lower mass is **always** overwritten
  with `remaining_volume * rho_lower`. It does not survive a projection call as
  an accumulated quantity. Whatever physical flows delivered to the lower zone is
  discarded at every projection.

Both writes accumulate their difference into `room.two_zone_boundary_mass_kg`
(`:265`, `:282`).

**Not proven, and not claimed:** how often `project_room_state` runs per
timestep. The call index exists in the trace but is not exported.

---

## 3. Non-circular runtime evidence

`two_zone_boundary_mass_kg` is a **cumulative** accumulator of exactly those two
rewrites. It is independent of the mass it corrects — unlike the withdrawn EOS
identity — and being cumulative it can be differenced across logged rows despite
the 10 s interval. It is the only non-circular runtime measurement available.

Scaled against each room's own nominal inventory (`volume * 1.2`), over the whole
run:

| Case | min `boundary_net / nominal` | max |
|---|---:|---:|
| `cfast_corridor_chain` | −0.71 | +7.18 |
| `cfast_hvac_residential` | −0.67 | +2.28 |
| `cfast_r0_window_360` | −0.21 | +4.52 |
| `cfast_slow_growth_sealed` | **−51.70** | +7.70 |
| `cfast_two_floor_stairwell` | −1.65 | +18.60 |
| `fuel_balance_diag_sealed` | −1.22 | +9.02 |
| `o2_stoich_diag_sealed` | −1.22 | +9.02 |
| `postfire_decay` | −12.90 | +17.17 |
| `ppv_attack_pressurized` | −7.45 | +29.59 |
| `v1_backdraft_accumulation` | −7.53 | **+33.65** |

Across all rooms: median **−0.67**, range **−51.70 to +33.65**, and
**|boundary / nominal| > 1 in 33 of 67 rooms**. Being a net figure, each of these
is a **lower bound** on how much mass projection actually rewrote.

**Reading, stated precisely.** `two_zone_boundary_mass_kg` is a **signed net
accumulator**: each rewrite is added with its own sign, so opposite corrections
**cancel**. Three consequences follow, and all three matter.

1. **It is not gross throughput.** The true gross volume of mass projection
   writes over a run can only be **larger** than the net figure, never smaller,
   because cancellation only ever reduces the running total. The numbers below
   are therefore a **lower bound** on projection activity.
2. **A large magnitude does prove material net cumulative intervention.** Reaching
   many times a room's own nominal air mass cannot arise from rounding or from a
   handful of small corrections; it requires sustained, systematically
   signed rewriting. That is a real finding, not a caveat.
3. **It does not prove the building fails to conserve mass at the end.** The
   accumulator measures what projection *rewrote*, not what the building *lost*.
   Net non-conservation of the building is a different quantity, it is not
   measured here, and this audit does not claim it.

---

## 4. Results — ten cases, 67 rooms, 20 059 room-steps

Sequential Godot 4.7.1 through `scripts/run_scenario.py`, zero failures, 231
columns each, zero residual processes.

### 4.1 Dimensions, reported separately

| Dimension | Result |
|---|---|
| `causal_status` | **INCOMPLETE in 10/10 cases** — sampling, not a defect finding |
| `zone_presence` | **52 TWO_ZONE_PRESENT, 15 UPPER_ZONE_ABSENT**, 0 LOWER_ZONE_ABSENT, 0 BOTH_ZONES_ABSENT, **0 NONFINITE_OR_INVALID** |
| `projection_evidence` | `CODE_PROVEN_LOWER_RECONSTRUCTION`, `CODE_PROVEN_UPPER_CAP`, `RUNTIME_TRACE_UNAVAILABLE` |

### 4.2 Observed frequencies — no defect implied

| Metric | Value |
|---|---|
| room-steps in the one-zone regime (`upper_gas_kg == 0`) | 8 196 / 20 059 (**40.86 %**) |
| room-steps below the FED upper gate (`upper_gas_kg <= 0.1`) | 8 226 / 20 059 (**41.01 %**) |
| rooms in the one-zone regime for the whole run | 15 / 67 |
| `lower_gas_kg == 0` | **0** |
| negative or non-finite masses | **0** |
| `SELF_DERIVED_EOS_IDENTITY` holds | all rooms — as it must, being a tautology |

In those 41 % of steps, `ThermalSystem.gd:4553` routes FED, CO, CO2 and HCN to
the **lower** zone. No consumer reads an undefined upper concentration today.

---

## 5. Risks and limitations

| Limitation | Handling |
|---|---|
| 10 s sampling | one-zone episodes are undercounted; the 40.86 % is a lower bound on frequency, and it is reported as a regime frequency, not a defect rate |
| Causal balance unavailable | reported INCOMPLETE; nothing is ever RELIABLE, enforced by contract |
| Boundary accumulator is signed and cumulative | opposite corrections cancel, so the reported figures are a **lower bound** on gross projection activity; a large magnitude proves material net cumulative intervention but **not** end-of-run building non-conservation |
| Projection call count not exported | per-step multiplicity unmeasured; listed as required instrumentation |
| `other` is a catch-all stage | unattributed mass could hide there; the generous reading was used |
| Ten cases, one duration each | strong evidence, not proof |

---

## 6. Answers

**1-3. Building and per-room conservation, and the projection share of ΔM.**
Not answerable. The causal balance is INCOMPLETE and the engine's own residual
cannot fail. No estimate is offered.

**4. Does `project_room_state` create or destroy mass materially?** Not measured.
What is **proven** is that it overwrites `lower_gas_kg` unconditionally and caps
`upper_gas_kg` conditionally, recording both in the boundary accumulator.

**5. Once or several times per timestep?** Not measurable — the call index is not
exported.

**6. Are upper and lower equally reliable?** No, and the asymmetry is structural
rather than statistical: upper mass is preserved except when capped and drives
the interface; lower mass is unconditionally reconstructed from the remaining
volume.

**7. Does EOS closure exist before projection or only after?** Unanswerable from
the CSV, because the exported EOS volumes are derived from the masses. Answering
it requires exporting the `pre_geometry` snapshot.

**8. Can the interface move the denominator without equivalent gas transport?**
Yes, proven by code: `:266-268` derives the interface from upper mass and `:281`
then reconstructs lower mass from whatever volume remains.

**9. Would a fixed O2 mass produce artificial `xO2` jumps?** For the lower zone,
yes — its denominator is rebuilt every projection from geometry. For the upper
zone in the one-zone regime the question does not arise today, because no
consumer reads it below 0.1 kg.

**10. Can S0d6b1 use the current masses?** No — see below.

---

## 7. Decision — INCOMPLETE / BLOCKED ON H3.2b

**The blocker is `lower_gas_kg`, and it is proven by code, not by statistics.**
`ZoneFireSolver.gd:281` overwrites it unconditionally with
`remaining_volume * rho_lower` at every projection. A stored `mO2_lower` divided
by that denominator would be divided by a quantity that is re-derived from
geometry and temperature each time, so `xO2_lower` would move whenever the
interface moved, with no oxygen having gone anywhere. FED reads `o2_lower` in
41 % of the sampled steps.

**`upper_gas_kg` is in better shape** — preserved unless capped, and the
interface follows it — but it cannot be used alone, and the causal balance that
would confirm it is unavailable.

**Not blocked because of the one-zone regime.** That was the withdrawn reading.
An absent upper layer is legitimate and already handled by the FED gate.

**Not blocked because of the EOS identity.** That was tautological.

### What unblocks S0d6b1

1. **H3.2b must make `lower_gas_kg` an accumulated quantity** rather than one
   reconstructed from the remaining volume at every projection.
2. **The instrumentation in section 1.1 must land**, so the causal balance this
   audit could not compute becomes computable and the question is not reopened on
   the same insufficient evidence.
3. **A zone-transition contract** is still needed for S0d6b: how `mO2_upper` is
   seeded when a layer is born, how O2 advects across a one-zone/two-zone
   transition, and what a consumer receives if it ever asks for a truly absent
   zone. `ThermalSystem.gd:4553` answers the last question for FED today; a new
   inventory must not silently change that.

---

## 8. What this phase did not do

No `sim/`, runner, case-file or report change. No physics, flag, expected value,
tolerance, CTRL or VALID_GAP touched. `Phase3O2Inventory.gd` was not created,
S0d6b1 and H3.2b were not started, and no alternative reference mass was invented
to work around the denominator. Godot was not re-run for the correction: it uses
the same ten runs.
