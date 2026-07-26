# Phase 3+ F3.3v3h0 coupled pressure solver design

Date: 2026-07-26

## Decision

**Design GO. Ready for H1.** No motor code was written in this phase.

One passive measurement was required before the architecture could be chosen,
and it was run: `scripts/simulation/analyze_phase3_f33v3h0_pressure_owner_attribution.py`.
Its result decides the design, so it is reported first.

The recommended architecture is a **damped-Newton solve for one pressure
unknown per room, over a residual that contains every pressure owner, with
fluxes derived from the orifice law at the solved pressure field and never
scaled after the fact**.

## 1. Evidence base: the canonical EOS is exactly affine

`derive_canonical_thermodynamic_state` computes

```text
p_r = (R / V_r) * (m_u * T_u + m_l * T_l),   T_z = T_ref + E_z / (m_z * cp)
```

Substituting `m_z * T_z = m_z * T_ref + E_z / cp` collapses this exactly to

```text
p_r = (R / V_r) * (M_r * T_ref + E_r / cp)
R   = P_ref / (rho_ref * T_ref) = 288.0351 J/(kg K)  at T_ref = 293.15 K
```

`p_r` is **affine in room total mass and room total energy**, with no zone
dependence and no cross terms. Three consequences follow, and all three were
verified numerically on a 180 s `cfast_corridor_chain` run:

| Consequence | Verification |
|---|---|
| Owner pressure contributions superpose **exactly** | attribution closes against the exported EOS to `1.37e-4 Pa`, which is the CSV `%.8f` print quantisation of cumulative totals, not a physical gap |
| An owner that only moves mass/energy **between zones of one room** contributes **exactly zero** pressure | `plume` and `interzone` measured at exactly `0.000000 Pa` in every interval of every room |
| Pressure is a near-singular cancellation of very large opposing owners | cancellation ratio `gross/|net|`: R0 `15612x`, Hall `1483x`, R2 `273x` |

### Measured owner spectrum, R0, peak per 10 s interval

| Owner | Peak `abs(dp)` (Pa) | Per step at `dt=0.0833 s` |
|---|---:|---:|
| `combustion` | 11701.4 | +87 |
| `other` — **multisurface gas/surface exchange, currently unlabeled** | 7533.2 | -36 |
| `interior_opening` | 3489.8 | -18.6 |
| `interior_pressure` | 1973.0 | -16.4 |
| `exterior` | 1776.0 | -14.8 |
| `plume`, `interzone`, `wall`, `ambient`, `parcel`, `reconcile` | 0.0 | 0 |
| **net** | **110** | **+0.92** |

At 80 s R0 sits at `p = 412.9 Pa`. Individual owners move it by **~42% of `p`
per timestep**; their sum moves it by **0.22%**. That ratio is the defining
numerical property of this system and it is what any solver must respect.

### This closes the F3.3v3g3 root cause quantitatively

F3.3v3g3 chose `alpha` to minimise

```text
J(alpha) = sum_e ( dp_e^pre + alpha * h_e )^2
```

where `h_e` contained **only** `interior_opening` + `interior_pressure`
(measured: ~4200 Pa/interval at 80 s). The neglected owners
(`combustion` + `other` + `exterior` = +4315 Pa/interval) are the **same order
of magnitude and opposite in sign**. At the interior-only optimum the true
end-of-step disequilibrium is therefore

```text
dp_e^end = dp_e^pre + alpha* h_e + d_oth,e  =  d_oth,e     (the entire neglect)
```

`d_oth` keeps one sign throughout fire growth because `combustion` is
monotonically positive, so the error is a **persistent forcing term**, not
noise. The iteration `p^{n+1} = p^n + d_oth^n` grows geometrically. That is
exactly the measured `1.08x -> 2.27x -> 5.65x` ratio, the 111-interval monotone
request growth and the 239-interval predicted/observed divergence.

**No choice of `alpha` fixes this**, which is why tuning, fixed
under-relaxation, clipping and new empirical caps are all correctly forbidden:
they are all attempts to correct a sign-level modelling error with a scalar.

## 2. Current tick order and pressure ownership

Verified against `SimulationEngine._physics_tick` (`sim/core/SimulationEngine.gd`).

```text
  1  _step_exterior_opening_smooth(dt)            opening geometry
  2  _build_opening_flow_cache()                  pre-step opening snapshot
  3  phase3.begin_step()                          canonical snapshot
  4  phase3.queue_canonical_exterior_boundary     QUEUED  (pressure owner)
  5  phase3.queue_canonical_exterior_counterflow  QUEUED  (pressure owner)
  6  phase3.queue_canonical_interior_opening      QUEUED  (pressure owner)   <-- g2/g3 live here
  7  _step_pool_fires / _step_oxygen
  8  _step_fire  -> combustion products           QUEUED  (pressure owner, largest)
  9  _step_co_oxidation / _step_targets
 10  thermal_system.step  -> plume, interzone,    QUEUED  (plume/interzone: NOT owners)
                             wall, multisurface           (multisurface: owner #2)
 11  _step_suppression / _step_steam_decay / glass
 12  _step_gas_exchange                           legacy transport (live path)
 13  _step_hvac                                   (out of scope)
 14  _step_passive_fuel / fire_spread
 15  thermal_system.reconcile_two_zone_building   projection reconcile
 16  _clamp_rooms                                 projection clamp + reseed risk
 17  phase3.finalize_step()                       ALL queued work resolves here
```

`finalize_step` resolves in this internal order:

```text
 17a  every queued request and atomic bundle, in queue order
 17b  _collapse_degenerate_zones(shadow)
 17c  _apply_canonical_exterior_boundary_requests(shadow, ...)   <-- LAST
```

Two structural facts follow, and together they are the whole problem:

- **Every interior transport decision is made at step 6 from pre-step
  pressure, but is committed at step 17a alongside owners whose magnitude is
  2-3x larger and which were not visible at step 6.**
- The exterior boundary at 17c is the only owner that reads the *updated*
  pressure. It is a relief valve gated by `pressure_vent_threshold_pa`, so
  below the threshold it cannot damp anything at all.

### Complete pressure-owner inventory

| # | Owner | Moves | Pressure owner? | Where decided | Where committed |
|---|---|---|---|---|---|
| 1 | Interior opening counterflow | room<->room mass+energy | **yes** | 6 | 17a |
| 2 | Interior signed pressure route | room<->room mass+energy | **yes** | 6 | 17a |
| 3 | Combustion products | mass+energy source | **yes, largest** | 8 | 17a |
| 4 | Multisurface gas/surface | energy sink | **yes, #2** | 10 | 17a |
| 5 | Exterior opening / leakage | room<->exterior | **yes** | 4,5 | 17c |
| 6 | Plume entrainment | lower->upper, same room | **no** (`dp = 0` exactly) | 10 | 17a |
| 7 | Inter-zone heat | upper<->lower, same room | **no** (`dp = 0` exactly) | 10 | 17a |
| 8 | Lumped wall / ambient | energy sink | yes, but inactive under multisurface | 10 | 17a |
| 9 | Projection / reconcile | reseed | must be **zero** | 15,16 | live only |
| 10 | HVAC | room<->room, room<->exterior | yes (future) | 13 | live only |

Thermal expansion/contraction is **not** a separate owner in this EOS: it is
exactly the `E_r / cp` term of owners 3, 4 and 8. It needs no separate
treatment, which removes a whole class of double-counting risk.

## 3. Current versus proposed flow

### Current (F3.3v3g2, committed, passive)

```text
   pre-step p  ──►  interior opening routes ─┐
   pre-step p  ──►  raw pressure demand    ──┼─► g2 solve (alpha)  ──► telemetry only
                                             │        ▲
                    combustion  ─────────────┤        │ sees ONLY these two
                    multisurface ────────────┤        │
                    exterior ────────────────┘        │
                                                      x  never enters the residual
                          all owners ──► finalize_step ──► p^{n+1}
```

### Proposed (F3.3v3h)

```text
   pre-step state x^n
        │
        ├─► evaluate NON-pressure owners once  (plume, interzone: zone split only)
        │
        ├─► assemble owner sources S_r  (combustion, multisurface, and any
        │                                explicit term), held fixed in the solve
        │
        └─► NEWTON on  R_r(p) = 0  for all rooms simultaneously
                 │        R_r contains: opening fluxes(p) + exterior fluxes(p) + S_r
                 │
                 ├─ flux law evaluated AT the solved p, per height band
                 ├─ neutral plane emerges from sign(dp_e(z)); never imposed
                 └─ converged p  ──► directional fluxes ──► one atomic bundle
                                          │
                                          └─► species / O2 advected at the
                                              converged flux (zero feedback:
                                              they do not enter p)
```

## 4. Minimal mathematical formulation

### State vector (question 1)

Per room `r`:

```text
x_r = ( m_u,r , m_l,r , e_u,r , e_l,r )   plus  o2_z,r  and  s_z,r,k  per species
```

Derived algebraically, never independent unknowns:

```text
M_r = m_u + m_l              E_r = e_u + e_l
p_r = (R / V_r) * ( M_r * T_ref + E_r / cp )        [exact, affine]
T_z = T_ref + e_z / (m_z * cp)
V_z = m_z * R * T_z / p_r     h_r = V_l,r / A_r     V_u + V_l = V_r identically
```

### Simultaneous unknowns (question 2)

Because `p_r` depends only on the affine combination
`Phi_r = M_r * T_ref + E_r / cp`, the pressure subsystem needs **one unknown
per room**:

```text
solve for  p = ( p_1 , ... , p_N )        N = rooms in the connected component
```

For `cfast_corridor_chain` that is `N = 3`. Everything else — the zone split,
species, O2 — is reconstructed after convergence. This is not an approximation;
it follows from the affine EOS.

### Residual (question 8)

Backward-Euler mass balance per room, containing **every** owner:

```text
R_r(p) = M_r^{n+1}(p) - M_r^n
         - dt * [  sum_e sigma_{r,e} * mdot_e(p)          interior openings
                 + mdot_ext,r(p)                          exterior / leakage
                 + S^m_r ]                                combustion mass source

with  M_r^{n+1}(p) = ( p_r * V_r / R - E_r^{n+1} / cp ) / T_ref
      E_r^{n+1}    = E_r^n + dt * ( sum_e sigma * hdot_e(p) + hdot_ext,r(p)
                                    + S^e_r )
```

`S^m_r`, `S^e_r` are the owner sources that do **not** depend on `p` within one
step (combustion products, multisurface exchange). They are evaluated once and
held fixed — that is legitimate operator splitting because they are *inside*
the residual, unlike g3 where they were outside it.

Convergence criterion, both dimensionless and both true residuals rather than
tuning knobs:

```text
rho_mass = max_r |R_r(p)| / ( dt * ( sum_e |mdot_e| + |mdot_ext,r| + |S^m_r| ) )
rho_p    = || p_used_in_fluxes - p(x^{n+1}) ||_inf / max(1 Pa, ||p||_inf)

accept when  rho_mass <= 1e-10  and  rho_p <= 1e-8
```

`rho_mass` normalises by **gross** throughput, so it stays meaningful exactly
where the net is a 273-15612x cancellation.

### Opening flux law and counterflow (questions 6, 7)

At opening `e` between rooms `a, b`, at height `z`:

```text
dp_e(z) = ( p_a - p_b ) + g * integral( rho_b(z') - rho_a(z') ) dz'
mdot_e(z) = C_d * W * sqrt( 2 * rho_src(z) * |dp_e(z)| ) * sign( dp_e(z) )
```

The neutral plane `z*` solves `dp_e(z*) = 0`. **Counterflow is preserved
structurally**, not by a constraint: the integration bands are split at `z*`
exactly as `_integrate_canonical_interior_opening` already does, so both
directions receive strictly positive mass whenever `z*` lies inside the opening
span. Directional flux is never produced by scaling a precomputed counterflow.

**The condition that rejects an unphysical one-way solution (question 7):**

```text
if  z_bot < z* < z_top   then   mdot_{a->b} > 0  AND  mdot_{b->a} > 0
```

A converged state violating this is rejected as non-physical. F3.3v3g3 violated
exactly this: `alpha` scaled the two directions independently, so at
`alpha = 1.0` it produced `out = 0.013084 kg, in = 0.000000 kg` while
`dp_e(z)` still changed sign inside the opening. Under the proposed formulation
that state is not representable, because direction is a consequence of
`sign(dp_e(z))` rather than a free variable.

### Regularisation

`d(mdot)/d(dp) = mdot / (2 * dp) -> infinity` as `dp -> 0`. F3.3v3g2 measured
the pressure-crossing bound active in **2008 of 2160 steps (93%)**, so the
near-singular regime is the normal regime, not an edge case. The flux law is
therefore linearised below a fixed physical threshold:

```text
if |dp| < dp_reg:   mdot = C_d * W * sqrt(2 * rho * dp_reg) * (dp / dp_reg)
```

`dp_reg` is a **numerical regularisation constant, not a physical tuning knob**:
it must be fixed once, globally, justified by the Jacobian conditioning it
buys, and reported in telemetry. It is never per case and never fitted to a
checkpoint.

### What stays explicit (question 3)

| Quantity | In the solve? | Why |
|---|---|---|
| Interior opening mass/energy flux | **inside** | depends on `p`, dominant coupling |
| Exterior / leakage flux | **inside** | depends on `p`, and is the relief mechanism |
| Combustion mass/energy source | source term, fixed | depends on O2 and fuel, not on `p` at leading order |
| Multisurface energy sink | source term, fixed | depends on surface temperature, not on `p` |
| Plume entrainment | **outside** | exactly zero pressure effect; affects only the zone split |
| Inter-zone heat | **outside** | exactly zero pressure effect |
| Species, O2 | **outside, after** | do not appear in `p`; advected at the converged flux with zero feedback error |
| HVAC | **outside** (future) | interface only, see section 9 |

Placing species and O2 outside the solve is exact, not an approximation,
because the EOS contains neither. This is what keeps the solve at one unknown
per room instead of `(2 + 2 + 7 + 1) x rooms`.

### Zone split, interface and species (question 10)

After `p` converges:

1. directional fluxes per height band are already known from `dp_e(z)`;
2. each band's source zone follows from the band position versus the source
   room interface — the existing slab machinery;
3. mass and energy are debited from the source zone and credited to the
   destination zone by the existing atomic route contract;
4. species and O2 ride the same routes at source-zone specific concentration;
5. plume and inter-zone heat are applied as intra-room transfers, which by
   construction do not perturb the converged `p`;
6. `V_u + V_l = V_r` and the interface follow from the EOS, exactly as today.

## 5. Numerical method comparison (question 9)

| Method | Splitting error | Behaviour at `dp -> 0` | Cost per step | Verdict |
|---|---|---|---|---|
| Explicit / current | O(neglected owners) = **O(100%)** | n/a | 1 eval | **rejected — this is g3** |
| Predictor-corrector, 1 correction | O(gain^2); with gain ~0.2 leaves ~4%, still ~10x the net | poor | 2 evals | **rejected** — 4% of a 42%-per-step gross is ~17x the net |
| Picard / fixed point | -> 0 if spectral radius < 1 | **diverges**; derivative unbounded | 4-8 evals | **first iterate only** |
| **Damped Newton, regularised** | **-> 0 to tolerance** | **conditioned by `dp_reg`** | 3-6 evals + `NxN` solve, `N<=6` | **recommended** |
| Adaptive substepping | reduces but never removes splitting | helps | up to `k x` everything | **fallback only** |
| Full DAE (CFAST/DASSL style) | -> 0 | robust | large | **rejected for scope** — would require restructuring the whole tick |

Estimated Picard gain from the measurement: at 80 s the interior owner moves
`~18.6 Pa/step` against a room-pair `dp` of `~85 Pa`, giving a gain around
`0.22` — convergent *there*. But with the crossing bound active in 93% of
steps, `dp` is frequently near zero, where the gain is unbounded. **Picard
alone is not robust; damped Newton with regularisation is required.** Picard
supplies a cheap first iterate.

The linear system is `N x N` with `N <= 6` for every scenario in scope. A dense
LU per Newton iteration is negligible; there is no reason to approximate the
Jacobian.

## 6. Where the solver lives (question 4)

A new **pure** `sim/core/Phase3CoupledPressureSolver.gd`, owned by
`Phase3ZoneMassSystem` and called from it.

- The solver receives dictionaries and arrays only: pre-step room states,
  opening descriptors, owner source terms. It reads no `RoomModel`, no
  `BuildingModel`, no engine flag and no persistent ledger.
- It returns a converged pressure field, directional fluxes, per-iteration
  residual history and a validity verdict. It emits no routes and mutates
  nothing — exactly the F3.3v3g1 contract that has held for three phases.
- `Phase3ZoneMassSystem` converts the returned fluxes into atomic routes, so
  the existing bundle, inventory-acceptance and conservation machinery is
  unchanged.

## 7. Tick order that avoids double counting (question 5)

The minimum reordering: **move the interior/exterior transport decision from
step 6 to a new step 16b, after every owner source is known and before
`finalize_step` commits.**

```text
  1-3   unchanged
  4-5   exterior/interior openings: DESCRIBE geometry only, queue nothing
  7-14  unchanged; combustion and multisurface now merely RECORD their sources
 15-16  unchanged
 16b    NEW: coupled solve over (interior + exterior fluxes | fixed sources)
         -> emit one atomic bundle for all opening transport
 17     finalize_step commits, exterior relief no longer needs to run last
```

Double counting is prevented by three rules:

1. every owner appears in **exactly one** of `{solve unknown, fixed source}`
   and never both — enforced by a source-registry test;
2. the legacy `_step_gas_exchange` path and the canonical path stay disjoint,
   as today;
3. delayed parcels keep their existing carve/deliver contract, and their
   in-flight inventory is excluded from the solve's source registry, because
   it has already been debited.

`_apply_canonical_exterior_boundary_requests` moving from 17c into the solve is
the only ordering change with physical consequence, and it is a strict
improvement: exterior relief becomes simultaneous with interior transport
rather than a post-hoc correction.

## 8. Reuse from g1/g2 without inheriting the g3 failure (question 11)

| Artifact | Reuse | Why it is safe |
|---|---|---|
| `compute_interior_pressure_network_components` | **yes, unchanged** | pure graph partition; order-invariant; nothing to do with alpha |
| Connected-component identity and ordering | **yes** | needed to size the `NxN` solve per component |
| `_fixed_gross_pressure_network_inventory_bound` | **yes, as a post-solve check only** | becomes a validity assertion, never a factor that scales a flux |
| Atomic route/bundle contract, inventory acceptance | **yes, unchanged** | proven exact in g3: bundle fraction was `1.0` with zero double-limit events |
| Residence ledgers, closure telemetry | **yes** | the measurement instrument for H0-H6 |
| `preview_fixed_gross_interior_pressure_skew` | **no** | fixed-gross recomposition presumes a precomputed counterflow to skew |
| `compute_fixed_gross_pressure_network_relaxation` | **no** | this is the alpha objective; it is the g3 failure |
| Any `alpha` blend of base and full routes | **no** | forbidden by construction |

The dividing line: **keep everything that partitions, validates or accounts;
discard everything that chooses a scalar multiplier for a precomputed flux.**

## 9. HVAC interface (future, not in scope)

HVAC is defined only as a future source-registry entry:

```text
S^m_r += mdot_hvac,r          S^e_r += hdot_hvac,r
```

If a future HVAC model makes flow depend on room pressure, it enters the solve
as an additional flux term with the same structure as an exterior opening. No
H-phase implements it, and no H-phase may block on it.

## 10. Telemetry gaps to close (question 12)

| Gap | Needed for | Phase |
|---|---|---|
| `multisurface` is unlabeled: the **#2 pressure owner** falls into `other` | attributing every delta | H1 (diagnostic-only family addition) |
| Per-**step** owner deltas; today only per-log-interval cumulative | proving step-level closure | H2 |
| Newton iteration count, residual per iteration, damping factor, regularisation-active count | proving convergence | H1 |
| Neutral-plane height per opening per step, plus a counterflow-preserved flag | proving question 7 | H2 |
| Jacobian condition number or a proxy | detecting stiffness before divergence | H2 |
| Predicted next-state versus observed next-state per owner | proving the g3 failure cannot recur | H2 |

The `multisurface` labeling gap is real and material: `other` peaks at
`7533 Pa` versus the largest owner at `11701 Pa`, i.e. **64% of the largest
owner is currently unattributed**. The analyzer reports this as a failing
verdict (`no_material_unlabeled_owner: false`) rather than hiding it.

## 11. Phase plan H0-H6

Costs are indicative: "session" is one working session, "run" is one headless
`cfast_corridor_chain` execution.

### H0 — design and tick map (this phase, complete)

- **Files**: this document; `analyze_phase3_f33v3h0_pressure_owner_attribution.py`; its test.
- **Flags**: none.
- **In/out**: 180 s residence-diagnostics run in; owner spectrum out.
- **Tests**: 6 analyzer contracts, all PASS.
- **Metrics**: closure `1.37e-4 Pa`; cancellation `273-15612x`; intra-room owners exactly `0`.
- **STOP**: affine premise proven, owner inventory complete, method chosen.
- **GO/NO-GO**: **GO**.
- **Rollback**: delete the analyzer; nothing else touched.
- **Cost**: 1 session + 1 run.

### H1 — pure solver primitive

- **Files**: new `sim/core/Phase3CoupledPressureSolver.gd`; new fixture; new structural test; diagnostic-only `multisurface` family addition in `Phase3ZoneMassSystem`.
- **Flags**: none — no runtime call site, exactly like F3.3v3g1.
- **In/out**: synthetic room/opening/source dictionaries in; converged `p`, fluxes, residual history out.
- **Tests**: single opening reaches equilibrium; three-room chain; disconnected components independent; opening-order invariance; `dp -> 0` regularisation; one-way rejection when `z*` is interior; Newton converges within the iteration cap; damping engages on overshoot; malformed input fails closed; **an analytic case with a known closed-form answer**.
- **Metrics**: iterations to `rho_mass <= 1e-10`; worst residual; damping activations.
- **STOP**: pure function, no call site, no flag, no report change.
- **GO/NO-GO**: GO if every fixture passes and the analytic case matches to `1e-10`. NO-GO if Newton needs more than ~10 iterations on any synthetic case — that would mean the formulation, not the implementation, is wrong.
- **Rollback**: delete the new file and its tests.
- **Cost**: 1-2 sessions, no runs.

### H2 — passive preview with predicted next state

- **Files**: `Phase3ZoneMassSystem` (call site), `SimulationEngine`, `SimulationLogWriter`, `SimulationStateBuilder`, both runners; new analyzer.
- **Flags**: `phase3_coupled_pressure_solver_shadow_enabled`, default OFF, depending on the existing canonical stack.
- **In/out**: real pre-step snapshots and owner sources in; predicted next state, full residual and convergence telemetry out. **Emits no routes.**
- **Tests**: flag default OFF and wiring; no caller applies the solved fluxes; OFF leaves the CSV schema and every value identical; predicted-versus-observed closure; counterflow-preserved flag.
- **Metrics**: `rho_mass`, `rho_p`, iteration count, predicted/observed error per owner, counterflow-preserved rate, regularisation-active rate.
- **STOP at 180 s**: all live columns identical OFF/ON; solver converges in **every** active step; predicted next-state error attributable to the fixed sources only and **not growing**; counterflow preserved in 100% of steps where `z*` is inside the opening.
- **GO/NO-GO**: NO-GO on any non-convergent step, any monotone growth of the prediction error, or any unexplained live difference.
- **Rollback**: revert the flag and call site; keep the analyzer and this document, as done for g3.
- **Cost**: 2 sessions, 2 runs.

### H3 — persistent shadow, single opening

- **Files**: as H2 plus the persistent apply path.
- **Flags**: `phase3_coupled_pressure_solver_persistent_shadow_enabled`, default OFF, separate from H2.
- **Scope**: deliberately a **two-room, one-opening** scenario first, so a divergence has exactly one possible source.
- **Durations**: 10, 30, 60 s, staged; a stage failure stops the next.
- **Tests**: replacement not addition; single bundle; no legacy write; inventory acceptance not duplicated.
- **Metrics**: the g3 STOP battery — pressure ratio versus baseline, monotone request growth, predicted/observed divergence streak, cap count, plus the H2 convergence metrics.
- **STOP**: pressure ratio versus baseline `<= 2.0` at every checkpoint; zero monotone-growth streaks `>= 10`; every conservation residual at its g3 invariant; counterflow preserved; EOS valid.
- **GO/NO-GO**: NO-GO on any g3-class signature. Because the residual now contains every owner, a recurrence would falsify the design premise itself and force a return to H0.
- **Rollback**: revert the persistent flag only; H2 preview survives.
- **Cost**: 2 sessions, 6 runs.

### H4 — corridor_chain 30/60/120/180/600 s

- **Files**: none new; analyzer extension only.
- **Flags**: as H3.
- **Metrics**: H3 battery plus CFAST correspondence — gross mass, net mass, net enthalpy — **evaluated only at 180 s and beyond**, because at 30 s the accepted baseline is itself `-51%` on gross.
- **STOP**: at 180 s, gross and net enthalpy within 5%; net mass within 25%; lower shadow gas positive; zero residuals. At 600 s, no drift in any convergence metric.
- **GO/NO-GO**: NO-GO if net mass does not improve on the F3.3v3f1 `-55.49%` baseline. Improving net mass is the entire physical purpose of this line of work.
- **Rollback**: as H3.
- **Cost**: 2 sessions, 10 runs.

### H5 — r0_window_360 and Group A/C

- **Files**: none new.
- **Flags**: as H3, still default OFF.
- **Metrics**: every required check, Physics, ILV, guardrails, gap inventory.
- **STOP**: Physics and ILV stay at 0 FAIL; guardrails 10/10; **no expected value, tolerance, CTRL envelope or VALID_GAP is touched**.
- **GO/NO-GO**: NO-GO if any required check regresses, or if closing a Group A/C gap needs a baseline change.
- **Rollback**: as H3.
- **Cost**: 2 sessions, 8 runs.

### H6 — authority decision

- **Files**: flag default flip only.
- **STOP**: a separate, explicit approval. Requires H5 GO, Group A/C improved or closed, 0 FAIL everywhere, guardrails 10/10, no new CTRL or VALID_GAP, and an explicit FED/O2/species before-after review.
- **GO/NO-GO**: authority is never implied by any earlier phase passing.
- **Rollback**: flip the flag back; the shadow path stays.
- **Cost**: 1 session.

## 12. Risks and rollback

| # | Risk | Signal | Mitigation | Rollback |
|---|---|---|---|---|
| 1 | Newton fails to converge near `dp = 0` | iteration cap hit | `dp_reg` regularisation; damping; Picard first iterate | fall back to the previous step's flux, flagged; never silently |
| 2 | The fixed sources are themselves `p`-dependent enough to matter | prediction error grows with iteration count | promote the offending source into the solve | H2 gate catches it before any state is written |
| 3 | `multisurface` remains unlabeled, so an owner is silently missing | `other` stays material in the attribution | H1 adds the family; analyzer verdict already fails today | diagnostic-only change, trivially revertible |
| 4 | Reordering the tick changes legacy behaviour | any live column differs OFF/ON | canonical path only; legacy `_step_gas_exchange` untouched | H2 STOP is exactly this check |
| 5 | Projection reseed recreates vented mass | `lower_reseed_count` non-zero | forbid reseed inside the solve; existing reseed telemetry | already instrumented |
| 6 | Species pumping via repeated carve/deliver | species residual non-zero | species advect at converged flux only, once | existing atomic contract |
| 7 | The `NxN` solve is too slow at scale | step time regression | `N <= 6` in scope; measure in H2 | component partition already bounds `N` |
| 8 | `dp_reg` becomes a de facto tuning knob | anyone proposes a per-case value | fixed global constant, justified by conditioning, reported | reject at review |
| 9 | The design premise is wrong and g3 recurs | pressure ratio grows at H3 | the residual now contains every owner, so recurrence falsifies the premise | return to H0 with the H3 measurement |

## 13. Final decision

**Ready for H1.**

The instrumentation that was missing at the start of this phase has been
obtained and is committed as a read-only analyzer with tests. The three
premises the architecture rests on are now measured rather than assumed:

1. the canonical EOS is exactly affine, so owner attribution superposes
   exactly — closure `1.37e-4 Pa`, which is CSV print precision;
2. plume and inter-zone heat are exactly pressure-neutral, so the solve does
   not need them and cannot double-count them;
3. owners cancel by `273x` to `15612x`, so any subset solve is wrong at the
   sign level — which explains F3.3v3g3 completely and rules out every
   alpha-shaped remedy.

One material gap remains and is deliberately scheduled rather than hidden: the
multisurface gas/surface exchange, the second-largest pressure owner at
`7533 Pa` peak, is still classified as `other`. H1 closes it with a
diagnostic-only family addition. It does not block H1 because it changes no
physics — only the label under which an already-measured quantity is reported.

Do not begin H2 in the same session as H1. Do not write a runtime call site in
H1.

## Reproduction

```powershell
python scripts\run_scenario.py `
  runs\phase3_f33t\cases\corridor_on.json `
  --out-dir runs\phase3_f33v3h0\180_owners `
  --duration 180 --timeout 1800 `
  --phase3-canonical-unfiltered-fire-growth-shadow `
  --phase3-canonical-fire-products-routing-shadow `
  --phase3-canonical-fuel-object-sync-shadow `
  --phase3-cfast-buoyancy-destination-shadow `
  --phase3-canonical-fixed-gross-pressure-network-shadow `
  --phase3-enthalpy-residence-diagnostics `
  --phase3-mass-residence-diagnostics

python scripts\simulation\analyze_phase3_f33v3h0_pressure_owner_attribution.py `
  --summary-only --json-out runs\phase3_f33v3h0\owner_attribution.json
```

The analyzer exits non-zero unless the affine-superposition premise closes, the
intra-room owners measure exactly zero, and the owner cancellation exceeds
`10x`. It reports the unlabeled-owner gap as a separate, currently failing
verdict without gating on it.
