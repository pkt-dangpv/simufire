# Changelog

All notable changes to SimuFire should be recorded here.

## Unreleased
### Phase 3+ F3.3v3f3 dynamic fixed-gross candidate NO-GO (2026-07-26)

- Tested a default-OFF canonical-shadow candidate that dynamically replaced
  the additive opening plus pressure routes with fixed-gross directional
  transport. The experimental motor patch was reverted after the STOP gate.
- Proved exact isolation: 114/114 rows and all 115 non-shadow columns remained
  identical to F3.3v3f2.
- Rejected the candidate because pressure entered one-way positive feedback:
  cap events grew from 79 to 1676, requested net transport from `6.368 kg` to
  `804.659 kg`, and lower-zone shadow gas collapsed to zero.
- Added a read-only analyzer, regression tests and the binding NO-GO record.
  The next gate is design-only F3.3v3g0 for an implicit or under-relaxed
  interior pressure network; direct route replacement must not be retried.

### Phase 3+ F3.3v3g0 pressure-network design (2026-07-26)

- Mapped the current canonical ordering and identified the numerical mismatch:
  pressure relaxation is evaluated for the additive route response, while the
  rejected candidate applied fixed-gross routes with a different response.
- Designed a network-wide pressure objective over the actual fixed-gross
  route delta, with descent, no-crossing and source-inventory bounds.
- Split delivery into pure primitive, passive preview, staged persistent
  shadow and separate authority gates. F3.3v3g1 is the only approved next
  motor slice; no runtime, report or baseline changed in this design phase.

### Phase 3+ F3.3v3f2 fixed-gross cap ledger (2026-07-26)

- Added cumulative signed cap telemetry under the existing default-OFF
  F3.3v3f1 preview so normal CSV logging captures every physical timestep.
- Measured 79 R0 cap events: 44 positive and 35 negative. Pressure requests
  `6.368 kg` net out (87.35% of CFAST) but the per-step cap accepts only
  `3.245 kg` (44.51%).
- Proved the capped subset reverses its cumulative direction from requested
  `+1.173 kg` to accepted `-1.950 kg`, a `-3.123 kg` bias.
- Rejected a static same-pressure normalization as sufficient. The next gate
  is a default-OFF dynamic canonical-shadow replacement that lets accepted
  fixed-gross transport evolve the next-step pressure state.

### Phase 3+ F3.3v3f1 fixed-gross pressure-skew shadow (2026-07-26)

- Wired the F3.3v3f0 fixed-gross primitive into the canonical runtime as an
  opt-in, default-OFF telemetry preview. It never enters atomic bundles or
  changes either canonical or legacy state.
- Added 21 CSV fields for per-room step/cumulative directional mass,
  enthalpy, caps and mass/O2/species/energy closure, plus a reproducible
  OFF/ON analyzer.
- Verified 114/114 rows and all 807 shared columns are identical OFF versus
  ON; every atomic residual remains zero.
- At 180 s the preview gives `143.875 kg` gross doorway mass versus CFAST
  `146.174 kg` (-1.57%) and `6321.966 kJ` net enthalpy versus `6301.709 kJ`
  (+0.32%).
- Kept runtime authority NO-GO: R0 net outflow is only `3.245 kg` versus
  CFAST `7.290 kg`, with 79 directional cap events. The next gate must study
  a combined slab pressure/buoyancy solve rather than directly promoting the
  current post-hoc skew.

### Phase 3+ F3.3v3d-f0 doorway pressure/energy diagnosis (2026-07-26)

- Closed the canonical pressure inventory to less than `2.8e-5 Pa` and showed
  that pressure-sign reversal exists before the interior-pressure route.
- Assigned about 73% of the final R0 energy deficit to doorway transport:
  opening-only enthalpy matches CFAST, while the independent pressure route
  adds gross churn and excess enthalpy.
- Added and runtime-tested a pure fixed-gross directional-skew primitive. It
  remained dormant until F3.3v3f1.

### Phase 3+ F3.3v3c exterior leakage attribution (2026-07-26)

- Added a read-only parser for CFAST layer-resolved leakage output and its
  exact wall/floor leakage geometry.
- Measured CFAST R0 leakage area `0.008384 m2` versus SimuFire's single
  closed-opening area `0.005000 m2`; the representations are topologically
  different as well as unequal in area.
- Assigned `3.649 kg` (74.3%) of the 180 s exterior outflow deficit to lower
  gas and `1.263 kg` to upper gas.
- Rejected an area-only experiment because SimuFire pressure reverses sign at
  120, 130, 140 and 180 s while CFAST remains positive and venting outward.
  The next gate is pressure-inventory owner attribution.

### Phase 3+ F3.3v3b early mass/interface attribution (2026-07-26)

- Added a read-only R0 mass-budget analyzer using the existing canonical
  residence ledger plus committed CFAST doorway, leakage and pyrolysis
  exports.
- Closed the 180 s `3.961 kg` total-mass error to a `0.020 kg` decomposition
  residual: exterior net outflow deficit `+4.912 kg`, doorway net outflow
  deficit `+0.922 kg`, missing gas-source mass `-2.114 kg` and initial-state
  bias `+0.221 kg`.
- Rejected plume and EOS projection as net-mass owners. The canonical plume
  already exceeds CFAST by `11.161 kg`, projection net mass is zero and the
  residence ledger closes.
- Kept interface partition unresolved and runtime authority blocked. The next
  gate is exterior leakage topology and per-zone outflow correspondence, not
  a plume, HRR, projection or global-flow multiplier.

### Phase 3+ F3.3v2c fuel-object synchronization design (2026-07-26)

- Mapped legacy per-object fuel ownership and identified nested atomic
  interpolation as the missing prerequisite after aggregate F3.3v2b routing.
- Defined stable object identity, proxy exclusion, bounded weighted
  allocation, leftover redistribution and aggregate/object invariants.
- Defined default-OFF wiring, telemetry, fixtures, runtime STOP gates and
  rollback criteria. No motor behavior or validation artifact changed.
- Added the first implementation slice: a pure dictionary-only bounded
  allocator with stable-ID validation, deterministic ordering, inventory
  caps and leftover redistribution. It is not wired into the tick yet.
- Added F3.3v2c2 persistent nested interpolation, default-OFF engine/runner
  wiring, 20 closure fields and an OFF/ON analyzer.
- Verified byte-identical OFF behavior, seven stable objects, zero internal
  residuals and no live-column changes. Runtime authority remains blocked by
  a measured 0.58758433 MJ live/canonical object-fuel difference at 180 s.
- F3.3v2d diagnosed that difference as a source-term semantic mismatch, not
  an allocator failure: legacy object inventory follows ideal solid
  pyrolysis while canonical products follow smoothed accepted HRR. The next
  design must split pyrolysis debit from combusted-fuel equivalent.
- F3.3v3a added a default-OFF direct t-squared proposal experiment. It closes
  the 180 s object-fuel difference to 0.00000248 MJ with zero internal
  residuals, but improves R0 upper temperature by only 0.162 C. The remaining
  owner is early zone-mass/interface partition, not fire-source energy.

### Phase 3+ F3.3v2b canonical fire-products routing (2026-07-26)

- Routed the accepted F3.3v2 fuel, O2, species and energy bundle through the
  existing persistent atomic shadow transaction and F3.3t plume driver.
- Added a default-OFF flag, 12 route-closure CSV fields and a reproducible
  OFF/ON analyzer.
- Verified the OFF CSV is byte-identical, all 115 live columns stay unchanged
  with routing ON, and every fuel/O2/species/energy/plume residual is zero.
- Kept runtime authority and Group C retirement NO-GO until explicit fuel
  objects have an atomic synchronization contract.

### Phase 3+ F3.3v2 canonical fire products (2026-07-26)

- Added pure requested/accepted fuel, O2, species, carbon, energy and plume
  drivers derived from the accepted F3.3v1 proposal.
- Applied one common acceptance fraction to every product and separated
  O2/ventilation combustion quality from fuel exhaustion.
- Added a default-OFF flag, 46 opt-in CSV fields, a Godot fixture and a
  reproducible STOP-gate analyzer.
- Verified 728 shared columns remain identical and all exported fuel, O2,
  carbon, species and energy residuals are zero.
- Kept runtime authority and Group C retirement NO-GO because product routing
  and explicit fuel-object synchronization are not yet owned.

### Phase 3+ F3.3v1 canonical fire proposal experiment (2026-07-25)

- Added a pure, persistent t-squared fire proposal with explicit hard
  extinction, O2-inventory, Kawagoe-ventilation and fuel limits.
- Added a default-OFF shadow flag, 19 opt-in CSV fields, direct Godot fixture
  and a reproducible OFF/ON STOP-gate analyzer.
- Verified exact no-op behavior across 709 shared columns and a supported
  300 kW model-derived proposal with monotonic fuel and no zero-O2 flame.
- Kept runtime authority and Group C retirement NO-GO. No official case,
  physical report, expected, tolerance, CTRL, VALID_GAP, FED, HVAC or visual
  path changed.

### Phase 3+ F3.3v canonical fire proposal design (2026-07-25)

- Mapped the combustion tick and confirmed that legacy O2 changes the fire
  clock, pyrolysis, targets, retained fuel, smoothed HRR, fuel and species
  before the canonical transaction is evaluated.
- Selected a two-stage canonical contract: an O2-unconstrained proposal from
  persistent fire state, followed by explicit extinction, O2 inventory,
  ventilation and fuel limits in one atomic transaction.
- Rejected inverse-throttle reconstruction, forced 300 kW HRR and silent
  legacy fallback for unsupported fire modes.
- Defined F3.3v1-v4 implementation phases, state/telemetry, fixtures, STOP
  gates and rollback criteria. No motor physics, report, baseline, tolerance,
  CTRL, VALID_GAP, FED, HVAC or visual path changed.

### Phase 3+ F3.3u extended plume stability (2026-07-25)

- Extended the unchanged F3.3t OFF/ON candidate to deterministic 300 and
  600 s runs with Godot 4.7.1.
- Added a tested stability analyzer that checks prefix determinism, finite
  state, positive zone inventories, conservation, horizon RMSE and projected
  required checks without changing official reports.
- Confirmed all nine RMSE families improve through the 590 s CFAST horizon
  and the maximum residual remains `2.8e-7`.
- Rejected runtime authority: all four projected corridor checks fail, and
  the late canonical transaction can only accept a legacy HRR proposal already
  throttled to 137 kW versus CFAST 300 kW.
- Selected design-first F3.3v for an unthrottled canonical fire proposal.

### Phase 3+ F3.3t coupled plume experiment (2026-07-25)

- Added a default-OFF complete Heskestad plume preview driven by canonical
  accepted HRR and effective radiative fraction, with inventory-capped
  mass/enthalpy/O2 transfer and no second O2 throttle.
- Added direct Godot fixtures and a reproducible OFF/ON CFAST STOP-gate
  analyzer. The OFF run is byte-identical to F3.3r2d and all nine audited
  correspondence RMSE families improve over 0-180 s.
- Kept runtime authority and Group C retirement NO-GO. No official case,
  report, baseline, tolerance, CTRL, FED, HVAC or visual path changed.
- Selected F3.3u as an equation-free 300/600 s stability extension.

### Phase 3+ F3.3s layer-mass/O2 causal audit (2026-07-25)

- Added a tested, read-only analyzer for 10-180 s layer mass, interface, O2,
  HRR, plume geometry and explicit mass-residence owners.
- Located the first exported divergence at 10 s: upper mass is 2.64 kg low,
  interface is 0.11 m high and plume transfer is already 1.07 kg behind
  CFAST while O2 concentration, projection and atomic acceptance still close.
- Identified plume request/source as the first wrong owner. CFAST enters the
  flame/interface regime at 60 s, O2 concentration diverges at 70 s, and
  SimuFire pinches its far-field distance near 0.10 m at 80-90 s.
- Kept physics, reports and baselines unchanged. Selected design-first F3.3t
  for a default-OFF region-aware plume transition with aligned convective HRR.

### Phase 3+ F3.3r2d source/routing attribution (2026-07-25)

- Added opt-in cumulative attribution for requested, decision-rejected,
  atomic-rejected and routed fire radiation, wall-area migration and
  upper/lower gas-to-surface exchange.
- Added a tested read-only CFAST analyzer that closes the source ledger and
  reroutes accepted radiation with the reference interface without applying
  it to simulation state.
- Traced 89.4% of the 180 s radiation shortfall to canonical O2 decision
  throttling; the atomic surface transaction rejects no energy.
- Measured 1.775 MJ incorrectly shifted from upper wall to lower wall by the
  high simulated interface, with zero routing or migration residual.
- Kept physical adoption, official activation and Group C retirement NO-GO;
  selected a layer-mass/O2 causal audit as F3.3s.

### Phase 3+ F3.3r2c multi-surface correspondence (2026-07-25)

- Added opt-in cumulative room and per-surface correspondence telemetry for
  gas exchange, fire radiation, exterior removal, temperatures, storage and
  residuals.
- Added reproducible scratch-only corridor, topology, no-opening and material
  fixtures plus a tested CFAST STOP-gate analyzer.
- Closed the 180 s energy ledger and legacy invariance gates, but rejected
  physical adoption because accepted radiation, layer mass/interface,
  temperature and surface allocation do not correspond to CFAST.
- Stopped before 300/600 s and left every official case, report, baseline,
  tolerance, gap, FED, HVAC and visual path unchanged.
- Selected read-only source/interface/routing attribution as F3.3r2d before
  any further motor experiment.

### Phase 3+ F3.3r2b2 enclosure topology (2026-07-25)

- Added explicit per-room physical topology for ceiling, upper wall, lower
  wall and floor, with exterior, inter-room and adiabatic area fractions.
- Made missing or invalid metadata fail closed to adiabatic behavior without
  deriving physics from visual geometry, rectangles or openings.
- Connected only declared exterior area to the canonical surface solver using
  a fixed coefficient scaled by exposed fraction.
- Kept inter-room area visible but thermally inactive pending an atomic paired
  surface contract.
- Exported multi-surface topology and energy diagnostics only in the opt-in
  canonical shadow schema.
- Added direct mixed/invalid/adiabatic/loading/conservation fixtures and
  preserved all legacy values in a 10 s OFF/ON comparison.
- No official case, report, baseline, tolerance, gap, FED, HVAC or visual path
  changed. F3.3r2c correspondence remains scratch-only.

### Phase 3+ F3.3r2b1 gas/surface exchange (2026-07-25)

- Added a default-OFF preview/queue/commit transaction for signed upper- and
  lower-gas convection and longwave radiation into the four canonical
  surfaces.
- Applied gas exchange, direct fire radiation and explicit exterior removal
  under one atomic fraction and one combined energy invariant.
- Extended the pure surface solver with prescribed accepted-energy inputs so
  commit cannot recalculate a different flux from preview.
- Added direct full, partial, rejected, reverse-flow and explicit-exterior
  fixtures while preserving the F3.3r2b transaction.
- Kept runtime exterior surfaces adiabatic because authoritative enclosure
  topology does not yet exist; this missing metadata is explicit telemetry.
- No official case, CSV schema, baseline, tolerance, gap, FED or HVAC path
  changed. F3.3r2b2 boundary topology precedes correspondence.

### Phase 3+ F3.3r2b multi-surface transaction (2026-07-25)

- Added a default-OFF persistent ceiling, upper-wall, lower-wall and floor
  surface state owned by the canonical zone-mass system.
- Added energy-conserving interface-area migration, including valid zero-area
  wall states at room boundaries.
- Extended canonical combustion with accepted fire-radiation metadata and
  deposited it only after the shared atomic bundle fraction is known.
- Finalized radiation as the exact complement of the Thermal-owned
  convective route, preventing duplicate `chi_rad` source formulas.
- Added deterministic area-emissivity routing, atomic candidate-state commit,
  duplicate protection and mutual exclusion with the lumped wall path.
- Kept the flag OFF, the legacy CSV schema unchanged and every official case
  disabled. Gas/surface/exterior exchange remains F3.3r2b1 scope.

### Phase 3+ F3.3r2a pure surface solver (2026-07-25)

- Added an isolated five-node implicit finite-volume surface-energy solver
  with immutable inputs and explicit convection, gas-radiation,
  fire-radiation and exterior-loss ledger fields.
- Concentrated the default grid near the interior face for the 0-180 s
  validation window; the 60 s concrete surface response is within 3.07% of
  the semi-infinite analytical reference.
- Closed a 10,000-step conservation fixture to `5.96e-8 kJ` cumulative
  residual without temperature or energy clamps.
- F3.3r2a delivered the component completely unwired; F3.3r2b now references
  it only through a new default-OFF experimental path. No official case,
  report, baseline, tolerance, gap, FED or HVAC path changed.

### Phase 3+ F3.3r2 multi-surface shadow design (2026-07-25)

- Defined a default-OFF four-surface canonical shadow for ceiling,
  upper wall, lower wall and floor without changing runtime code.
- Assigned persistent state to `Phase3ZoneMassSystem` and numerical work to
  a new pure five-node surface-energy solver.
- Specified atomic routing of accepted combustion radiation, physical
  gas-to-surface exchange, exterior loss and interface-area migration under
  one gas/surface/exterior invariant.
- Split implementation into F3.3r2a pure fixtures, F3.3r2b state/transaction
  wiring and F3.3r2c 60/120/180 s scratch gates. Runtime authority and gap
  retirement remain NO-GO.

### Phase 3+ F3.3r1 boundary-partition audit (2026-07-24)

- Added a tested read-only analyzer that reconstructs CFAST ceiling,
  upper-wall, lower-wall and floor heat storage from their temperature
  histories and declared concrete effusivity.
- Estimated `26.993 MJ` total R0 surface storage at 180 s:
  `13.392 MJ` direct fire radiation plus `13.601 MJ` gas-driven uptake.
- Closed the independent gas-side correspondence to within `0.562 MJ`
  against the `14.163 MJ` F3.3q inferred boundary sink.
- Identified the remaining contract defects: direct combustion radiation
  never reaches the canonical wall reservoir, while `3.796 MJ` of ambient
  decay bypasses surface storage.
- Kept the full-area patch NO-GO and selected a design-only multi-surface
  shadow as F3.3r2. No motor or official validation artifact changed.

### Phase 3+ F3.3r0 material correspondence (2026-07-24)

- Ran a scratch-only concrete-material control after proving exact
  reproduction of the valid F3.3p1 canonical state across 552 shared fields.
- Reduced the 0-180 s boundary-sink deficit from `3.414 MJ` to `0.730 MJ`
  and corrected the early R0/Hall upper-temperature overshoot.
- Rejected direct material adoption because R0/Hall lower zones and R2 upper
  zone overcool late; a matched total sink is not a matched surface/zone
  contract.
- Removed all temporary runtime code. No official case, report, baseline,
  tolerance, gap, FED or HVAC path changed.
- Redirected F3.3r1 from full-area implementation to a read-only
  surface/zone boundary-partition audit.

### Phase 3+ F3.3q boundary-energy correspondence (2026-07-24)

- Added a tested, read-only analyzer for the R0 0-180 s source, storage,
  signed-doorway and boundary-energy balance.
- Measured `14.163 MJ` inferred CFAST boundary loss versus `10.749 MJ`
  canonical loss, with exact shadow ledger closure.
- Identified absent CFAST concrete mapping as the first mismatch and
  canonical wall area (`40.0 m2` versus `83.2 m2` enclosure) as the second.
- Selected a material-only scratch control as F3.3r0. No motor, official
  validation artifact, expected value, tolerance, gap, FED or HVAC path
  changed.

### Phase 3+ F3.3p1 coupled-Qc runtime experiment (2026-07-24)

- Tested a corrected shadow-only accepted-Qc source shared by combustion heat
  and the complete Heskestad plume while retaining F3.3n receiver routing.
- Preserved all legacy output and exact canonical mass, energy, O2 and
  species closure.
- Rejected the candidate at the mandatory 180 s STOP: R0 mass, interface and
  plume entered their CFAST envelopes, but upper temperature reached
  `200.75 C` versus `159.82 C`; Hall and R2 also overheated.
- Removed the temporary runtime surface and skipped 300/600 s. F3.3q is a
  read-only boundary-energy correspondence audit before another motor patch.

### Phase 3+ F3.3p coupled-Qc re-entry design (2026-07-24)

- Reconstructed the R0 lower-zone budget across the removed F3.3e1
  candidate, accepted F3.3n routing and committed CFAST slab outputs.
- Found that the 600 s plume shortfall (`109.09 kg`) closely matches the
  missing lower-route margin (`123.44 kg`), confirming a closed-loop
  source/neutral-plane/routing dependency rather than an isolated plume
  coefficient.
- Authorized one future default-OFF F3.3p1 experiment with explicit
  180/300/600 s STOP gates. No motor, official case, report, baseline,
  tolerance, gap, CTRL, FED or HVAC path changed.

### Phase 3+ F3.3h1 buoyancy-routing design (2026-07-22)

- Added the exact CFAST `flogo` `tanhsmooth` destination split as an internal,
  default-false contract shared by F3.3a and F3.3b.
- Preserved geometric source removal, gross flow, pressure, neutral plane and
  source payload. Direct mass, enthalpy, O2 and species split by one common
  lower/upper fraction; Poreh remains a distinct atomic bundle.
- Verified 455 Phase 3 tests and three isolated Godot 4.7.1 fixtures. No
  Engine/CLI/CSV/case surface or validation artifact changed. F3.3h2 is the
  separate 180 s runtime STOP.

### Phase 3+ F3.3h CFAST doorway-flow semantics (2026-07-22)

- Traced CFAST 7.7.5 and current official `master` from `wall_flow` through
  `flogo`, `spill_plume`, ODE accumulation and both standard output writers.
- Corrected the routing interpretation: source removal is geometric, direct
  receiver deposition uses a smooth temperature/buoyancy split, and Poreh is
  a separate receiver-internal transfer added to the ODE.
- Confirmed that `.out` and spreadsheet upper/lower vent flows contain direct
  `h_mflow` only, so the Group C comparison remains valid. Rejected the
  F3.3f1 source-preserving hypothesis and selected a pure CFAST-equivalent
  thermal split as F3.3h1. No motor or validation artifact changed.

### Phase 3+ F3.3g1 doorway-jet runtime experiment (2026-07-22)

- Preserved hydrostatic opening slabs through F3.3a/F3.3b and integrated the
  separate receiver-side Poreh routes with exact mass, enthalpy, O2 and
  species closure plus opening-order invariance.
- Rejected the runtime composition at the 180 s Group C STOP. The cool
  `upper -> lower` mixing branch dominated the hot branch by about 20x;
  upper mass fell `22.921 -> 21.745 kg` and interface rose
  `1.101 -> 1.158 m`, both away from CFAST.
- Removed the temporary Engine/CLI/CSV surface and skipped 300/590 s runs.
  Internal default-false slab/Poreh contracts remain. F3.3h must audit the
  exact CFAST `UFLW/UFLW2/UFLW3` source-to-output semantics before another
  runtime candidate.

### Phase 3+ F3.3g doorway-jet entrainment design (2026-07-22)

- Implemented the current CFAST/Poreh doorway-jet correlation as a pure
  receiver-side preview, including both hot `lower -> upper` mixing and the
  cool `upper -> lower` branch with CFAST's `0.25` factor.
- Added a pre-step receiver-inventory route builder. Gas mass, sensible
  enthalpy, O2 and seven species share one atomic accepted fraction and remain
  exactly conservative in the direct Godot fixture.
- Kept the candidate entirely outside Engine, CLI, CSV, cases and
  `RoomModel`. All Phase 3 tests are 439 PASS and the Godot 4.7.1 fixture
  passes. F3.3g1 must preserve per-slab geometry and test the paired direct
  transport plus induced mixing at the 180 s Group C STOP.

### Phase 3+ F3.3f2 destination-routing runtime experiment (2026-07-22)

- Wired the F3.3f1 selector temporarily behind a default-OFF Engine/CLI/CSV
  gate and verified the 180 s Group C STOP, then fully removed that runtime
  wiring after the candidate failed the binding physical criterion.
- Default OFF was byte-identical to the prior F3.3d1 checkpoint. With the
  candidate ON, R0 lower inflow improved from `46.143` to `54.555 kg` while
  total inflow stayed nearly unchanged, but upper inflow collapsed from
  `7.516` to `0.004 kg` versus CFAST `3.662 kg`.
- The candidate moved R0 upper mass/interface away from CFAST at 180 s despite
  exact mass, enthalpy, O2 and species closure. The 300/590 s runs were not
  started. The pure F3.3f1 selector and fixtures remain; runtime exposure does
  not. Next is a design-first audit of CFAST's separate doorway-jet entrainment
  owner, not a flow multiplier or Qc composition.

### Phase 3+ F3.3f1 destination-routing design (2026-07-22)

- Added a pure, optional and default-false source-preserving destination
  selector shared by the F3.3a opening and F3.3b signed-pressure previews.
- Kept source-zone selection, pressure integration, gross flow, neutral plane,
  atomic limiting and all transported payload formulas unchanged. The
  candidate has no Engine, CLI, CSV or case wiring yet.
- Verified lower-to-lower renewal, upper-to-upper hot transport, conservative
  empty-zone creation, exact OFF equivalence, all-quantity conservation and
  opening-order independence: 432 Phase 3 tests and the Godot fixture PASS.
  F3.3f2 is the separate default-OFF Group C runtime gate.

### Phase 3+ F3.3f lower-zone renewal correspondence (2026-07-22)

- Compared CFAST's explicit upper/lower doorway flows with the exact
  SimuFire accepted-route ledger over `0-180`, `180-300` and `300-590 s`.
- Rejected a doorway-flow magnitude fix: late SimuFire total inflow is about
  `223.5 kg` versus CFAST `168.4 kg`, but only `51.6 kg` reaches lower versus
  CFAST `166.8 kg`; `171.9 kg` is incorrectly deposited in upper.
- Located the binding contract in the destination midpoint-zone assignment.
  As the receiver interface falls, cool replacement flow is increasingly
  routed upper, creating a self-reinforcing lower-zone collapse. Selected a
  design-first, default-OFF destination-routing experiment as F3.3f1; no
  runtime, case, report, baseline, tolerance or gap changed.

### Phase 3+ F3.3e1 coupled Qc experiment (2026-07-22)

- Implemented and measured the default-OFF accepted-Qc heat/plume candidate,
  then fully rolled it back after the 600 s STOP gate.
- The candidate matched the first CFAST window closely (`24.03/24.87 MJ` and
  `98.36/97.72 kg`) and moved temperature, upper mass and interface toward
  CFAST at 180 s with exact mass/enthalpy closure.
- Rejected retention because lower-zone renewal could not sustain the plume:
  at 590 s lower gas and interface reached zero while upper gas rose to
  `41.37 kg` versus CFAST `25.25 kg`. F3.3f will audit lower doorway renewal
  and zone routing before this source contract can be retried.

### Phase 3+ F3.3e coupled Qc design (2026-07-22)

- Mapped the canonical fire source to one future authority:
  accepted total HRR -> effective radiative fraction -> accepted `Qc`, with
  the same `Qc` driving upper-zone convective energy and plume entrainment.
- Found that the current plume subtracts Heskestad flame length where the
  correlation requires the virtual origin. With CFAST's physical fire area
  (`D=0.6196 m`) and `Qc=195 kW`, the corrected equation reproduces its plume
  flow within 2.3% at 180, 300 and 590 s without tuning.
- Identified the existing post-evaluation cube-root plume scale as invalid for
  the linear source term. Approved only a future default-OFF F3.3e1 runtime
  experiment; no motor, case, report, baseline, tolerance or gap changed.

### Phase 3+ F3.3d2 plume source-term experiment (2026-07-22)

- Tested the missing Heskestad `0.0018 * Qc` source term as one default-OFF
  canonical plume candidate. It reduced the plume-mass error in all three
  CFAST windows and substantially improved Group C mass/interface state.
- Rejected and fully rolled back the candidate because it further cooled the
  already under-energized upper layer at both 180 s and 590 s. Exact mass and
  enthalpy closure remained zero throughout.
- Selected a design-first coupled convective-source/plume contract as F3.3e;
  no F3.3d2 code, official report, baseline, tolerance or gap change remains.

### Phase 3+ F3.3d1 mass residence ledger (2026-07-22)

- Added a default-OFF cumulative accepted-route gas-mass ledger by room, zone,
  direction and exclusive cause family, with exact upper/lower/room/building
  closure and 72 opt-in CSV fields.
- Preserved all 595 shared Group C columns across 366 rows while the ledger was
  enabled; five runtime controls and the deterministic Godot fixture close at
  `0.0 kg` residual.
- Measured accepted plume mass at only 64-72% of CFAST while a large radiation
  change moves plume mass by less than 2%. Plume entrainment/partition is the
  next experimental owner; no physics, report, baseline or gap changed.

### Phase 3+ F3.3d CFAST source/boundary audit (2026-07-21)

- Integrated CFAST convective source, signed doorway-slab enthalpy and layer
  energy against the exact F3.3c1 ledger over three common time windows.
- Confirmed the explicit 30% versus 65% convective-source mismatch, with an
  additional late O2-throttle deficit, but retained the scalar source NO-GO:
  the aligned-radiation control has nearly correct early energy in 32% too
  little upper gas and therefore overheats badly.
- Rejected wall/ambient and doorway loss as primary standalone fixes and
  selected an exact default-OFF mass-residence ledger (F3.3d1) as the next
  diagnostic gate. No motor physics or validation contract changed.

### Phase 3+ F3.3c1 enthalpy residence ledger (2026-07-21)

- Added a default-OFF cumulative accepted-route sensible-enthalpy ledger by
  room, zone, direction and cause family, with exact zone/room/building closure.
- Preserved all 527 shared F3.3b columns exactly in the 600 s Group C OFF/ON
  comparison; the opt-in ledger adds 68 diagnostic fields only when enabled.
- Quantified Group C R0 energy residence and confirmed the canonical budget is
  internally exact. F3.3d will compare source and boundary families with CFAST
  before any physical coefficient or owner changes.

### Phase 3+ F3.3c late-enthalpy audit (2026-07-21)

- Established from CFAST layer masses and sensible energies that Group C's
  late temperature undershoot is energy-residence dominated: F3.3b retains
  94.8% of CFAST upper mass but only 49.3% of upper sensible energy at 600 s.
- Rejected a scalar radiation/convection retune: a scratch CFAST-aligned
  `chi_rad=0.35` control fixes the late point but produces a severe early
  overshoot.
- Defined F3.3c1 as a default-OFF cumulative accepted-route enthalpy ledger;
  no motor physics, official report, baseline, tolerance or gap changed.

### Phase 3+ F3.3b signed interior pressure shadow (2026-07-21)

- Added a default-OFF signed canonical pressure component for horizontal
  interior openings, evaluated from one common snapshot and committed in the
  existing F3.3a atomic network bundle.
- Added a network-wide EOS relaxation cap that prevents one-step pressure
  reversal while conserving gas, enthalpy, O2 and all transported species.
- Added 19 opt-in diagnostics plus runtime coverage for direction, pressure
  reversal, order independence, vertical exclusion and complete conservation.
- Rejected the Group C pressure-flow hypothesis: R0 upper temperature worsens
  from `130.94/102.73 C` to `125.70/97.39 C` at 180/600 s. Authority and gap
  retirement remain NO-GO; F3.3c will audit late enthalpy residence.

### Phase 3+ F3.3a horizontal interior-opening shadow (2026-07-20)

- Added one default-OFF, opening-order-independent canonical network bundle
  for horizontal interior openings with exact hydrostatic integration.
- Transported gas, enthalpy, O2 and seven species under one global atomic cap;
  vertical and exterior ownership remained unchanged.
- Improved Group C early temperature but worsened its late undershoot, leaving
  authority and gap retirement at NO-GO.

### FP perpendicular facade visibility fix (2026-07-20)

- Prevented independent urban sets on perpendicular exterior walls from
  intersecting and occluding one another by applying an Inspector-editable
  maximum span to each opposite facade.
- Added a soft local fill per urban/residential facade so walls facing away
  from the directional sun retain readable daylight and night shading.
- Expanded the exterior Godot validator to cover perpendicular facades,
  volume separation and local-light coverage.

### FP procedural exterior rebuild (2026-07-20)

- Rebuilt apartment views with a full street section, modular opposite
  buildings, framed windows, entrances, cars, trees and separated skyline
  volumes instead of one flat facade and overlapping silhouette blocks.
- Rebuilt single-family exteriors with one authoritative garden/street layout,
  correctly scaled neighboring houses, gable roofs, paths, pavements, hedges
  and vegetation; removed the duplicate legacy road and toy-house geometry.
- Upgraded the house entrance with a pitched porch roof and exterior lamp, and
  added a Godot validator for composition ownership and geometric separation.
- Exposed the principal city, residential, porch and vegetation dimensions,
  counts and colors in the `FirstPersonController` Inspector; defaults preserve
  the validated layouts while allowing scene-level art direction in Godot.

### FP apartment landing stairwell (2026-07-20)

- Replaced the decorative single landing flight with a complete U-shaped
  stairwell that visibly continues to both the lower and upper floors.
- Split floor and ceiling slabs around the stair shaft, separated both lanes,
  enclosed adjacent levels and reserved a non-overlapping door band.
- Exposed floor height, stair-bay width, landings, lane gap and side clearance
  in the `FirstPersonController` Inspector.
- Added a Godot geometry validator for flight direction, solid intersections,
  floor openings and door clearance.

### Phase 3+ F3.2b7 post-opening coupling (2026-07-20)

- Added a default-OFF shadow coupling that selects the fresh lower-zone O2
  reservoir only during explicit canonical exterior counterflow.
- Bound combustion O2 and plume air in one atomic lower-to-upper transaction,
  including the opt-in Heskestad source term and 12 diagnostic CSV fields.
- Recovered Group A post-opening HRR from 490 to 1280 kW at 420 s and moved
  the canonical interface from 1.574 to 1.084 m versus 1.020 m in CFAST.
- Preserved all legacy output and exact conservation. Late upper O2 remains
  low and the 370 s HRR response is early, so authority and gap retirement
  remain NO-GO. F3.3 interior openings is the next gate.

### Phase 3+ F3.2b6 canonical exterior counterflow (2026-07-20)

- Added a default-OFF, shadow-only hydrostatic exterior-opening exchange with
  simultaneous canonical upper outflow and ambient lower inflow.
- Kept net pressure relief as a separate owner and applied both counterflow
  routes with one atomic acceptance fraction for mass, energy, O2 and species.
- Added 29 opt-in CSV diagnostics and deterministic coverage for equilibrium,
  inventory limits, pressure coexistence and duplicate ownership.
- Improved Group A post-opening reoxygenation, interface rise and HRR in the
  correct direction with exact conservation, but retained authority NO-GO:
  interface now overshoots while HRR remains far below CFAST.
- Defined F3.2b7 as the next gate for canonical post-opening combustion/O2/
  plume feedback. No baseline, tolerance, report or gap changed.

### Phase 3+ F3.2b5c equivalence diagnosis (2026-07-19)

- Repeated the Group A mass/energy/EOS-pressure matrix after canonical
  inter-zone and wall/ambient ownership. No motor behavior or validation
  baseline changed.
- Found that `chi_rad=0.35` plus the CFAST leakage area is the strongest
  simultaneous equivalence candidate, reducing mass RMSE to 2.69 kg, energy
  RMSE to 803 kJ and upper/lower temperature RMSE to 33.8/16.7 C.
- Rejected the lumped concrete-wall candidate and kept all equivalence inputs
  scratch-only pending boundary ownership.
- Identified the next blocker: the canonical exterior path has one net
  direction and cannot represent simultaneous upper outflow/lower fresh-air
  inflow. F3.2b6 must add bidirectional exterior counterflow before Group C.

### Phase 3+ F3.2b5b canonical wall/ambient energy (2026-07-19)

- Added a default-OFF persistent canonical wall reservoir driven only by
  canonical pre-step gas state, static room geometry and declared material or
  fallback wall properties.
- Replaced six legacy-derived shadow wall/ambient requests with one atomic
  energy bundle and explicit ambient boundary accounting. Gas-wall and total
  boundary residuals close exactly.
- Preserved every non-shadow output and a zero-energy no-fire equilibrium.
  Group A no longer drains canonical lower energy to zero, and its three
  shadow O2 checks remain inside their existing tolerances.
- Kept authority and Group A retirement at NO-GO. Earlier canonical mass,
  energy and pressure residuals remain; F3.2b5c must audit full equivalence
  before any production activation.

### Phase 3+ F3.2b5a canonical inter-zone heat transfer (2026-07-19)

- Added a default-OFF canonical upper/lower heat-transfer preview based only
  on persistent pre-step mass, energy, temperature and interface.
- Replaced the legacy shadow request with one energy-only atomic bundle when
  opted in. The reduced-capacity equilibrium bound prevents temperature
  crossing and closes the energy residual exactly.
- Removed the Group A canonical thermal inversion and reduced lower-zone
  temperature RMSE from about 93 C to 23 C while preserving all legacy output,
  volume closure and the three shadow O2 PASS results.
- Kept authority and Group A retirement at NO-GO. Pressure, total mass and
  total energy remain materially wrong, and the late lower zone is now too
  cold. F3.2b5b must establish canonical wall/ambient energy ownership.

### Phase 3+ F3.2b4 pressure-equivalence diagnosis (2026-07-19)

- Decomposed canonical EOS pressure into independent total-mass and sensible-
  energy terms. The Group A pressure curve is a cancellation between large
  state errors, not evidence that the canonical room state is ready.
- Ran isolated canonical-plume experiments for radiative split, equivalent
  leakage, concrete wall properties and their combinations. None closes
  pressure, mass, energy, interface and both zone temperatures together.
- Identified the remaining cross-state thermal contract: heat-loss requests
  are calculated from legacy temperatures and applied to canonical
  reservoirs. Canonical lower exceeds upper near 313 s but still receives
  about 4.63 MJ of requested downward heat afterwards.
- Kept motor, official reports, expected values, tolerances and gaps unchanged.
  Decision is diagnostic GO and authority/Group A NO-GO. F3.2b5a will create a
  pure canonical inter-zone heat-transfer preview before wall/ambient work.

### Default Godot runtime updated to 4.7.1 (2026-07-18)

- Updated active Python and PowerShell runners to prefer
  `Godot_v4.7.1-stable_win64_console.exe` from the local Desktop.
- Preserved explicit `--godot`, `-GodotExe` and `GODOT_EXE` overrides.
- Added a regression test that rejects stale 4.6.3 defaults in active runner
  code and verifies the project declares the Godot 4.7 feature.
- Repaired a pre-existing malformed string in `update_baselines_fixed.ps1`
  found while parsing every updated PowerShell entrypoint.
- Historical reports and session records remain labelled with the Godot
  version that originally produced them.

### Phase 3+ F3.2b3 canonical plume geometry (2026-07-18)

- Added `phase3_canonical_plume_shadow_enabled=false` and a pure plume preview
  driven by canonical pre-step mass, sensible energy, O2 and interface.
- Proved the premature one-zone transition was a cross-state error: the live
  plume used a `1.458 m` legacy interface while the receiving canonical state
  had a `0.260 m` interface, over-requesting entrainment by roughly 18x at the
  diagnostic sample.
- Preserved canonical lower gas through the Group A opening (`2.48 kg` at
  360 s instead of `0 kg`) while retaining all three shadow O2 PASS results,
  exact volume closure and all 115 legacy columns.
- Kept authority OFF. Pressure improves but remains outside the CFAST envelope;
  F3.2b4 must diagnose heat-source and leakage/boundary equivalence without a
  fitted pressure clamp or per-case tuning.

### Phase 3+ F3.2b2 canonical pressure relaxation (2026-07-18)

- Added a default-OFF equilibrium limiter for the canonical exterior bundle.
  It derives the exact accepted fraction from the two-zone EOS and scales gas,
  sensible energy, O2 and every species atomically.
- Added a conservative one-zone-to-two-zone transition: when a real exterior
  opening admits fresh air into an upper-only state, the first inflow recreates
  the lower zone. Closed-window leakage does not trigger this transition.
- Eliminated the Group A opening overshoot (`+26.9 kPa` to approximately
  `0 Pa`) while preserving all three shadow O2 PASS results and all 115 legacy
  columns.
- Kept authority OFF. The pre-opening canonical range remains about
  `-1.04..+2.81 kPa`, and the lower zone still reaches the one-zone limit near
  160 s. F3.2b3 must diagnose those remaining representation differences.

### Phase 3+ F3.2b1 closed combustion shadow transaction (2026-07-18)

- Added a default-OFF pure combustion evaluator driven by canonical pre-step
  O2 and persistent fire state. It does not write legacy room or fire state.
- Added one atomic shadow bundle for HRR, fuel, O2, generated species,
  convective heat and plume transport. All terms share one decision and one
  accepted fraction.
- Added 27 opt-in CSV diagnostics and a direct Godot fixture covering partial
  O2 throttling, lower-zone bootstrap, extinction and atomic closure.
- Verified all three Group A O2 checks pass in shadow without changing
  expected values or tolerances; 115 legacy columns remain identical.
- Kept authority OFF: the exterior-opening transient still reaches about
  `+26.9 kPa`, and the lower canonical zone collapses before the opening.
  F3.2b2 must address pressure relaxation and degenerate-zone transition
  before Group A gaps can be retired.

### Phase 3+ F3.2b0 persistent shadow diagnosis (2026-07-18)

- Added default-OFF step-to-step persistence for canonical mass, sensible
  energy, O2 and species without writing legacy room state.
- Added a passive upper-zone combustion O2 candidate, one canonical O2 demand
  request and conservative fusion of degenerate zero-mass zones.
- Verified exact continuity and normalization residuals plus byte-identical
  115-column legacy output.
- Recorded authority NO-GO: Group A improves at 240 s but over-depletes by
  350 s and reaches a nonphysical `-34.1 kPa` opening transient because legacy
  HRR/plume fluxes do not feed back from canonical O2.
- Assigned F3.2b1 to a closed combustion/plume transaction; an O2-only scale
  is explicitly forbidden.

### Phase 3+ F3.2a passive exterior boundary (2026-07-18)

- Added a default-OFF canonical exterior pressure/leakage bundle that moves
  gas, sensible energy, O2 and all parcel species with one inventory-limited
  fraction and never writes legacy room state.
- Suppressed only the legacy `pressure_venting` owner inside the parallel
  shadow; ACH, natural ventilation, smoke purge, post-fire purge and PPV remain
  independent visible contracts.
- Verified `-0.83..125.85 Pa`, zero boundary residuals, no lower-zone collapse
  and byte-identical 115-column legacy output on `cfast_r0_window_360`.
- Recorded passive-contract GO and authority/Group-A NO-GO: pre-opening upper
  O2 remains near legacy, so F3.2b must address canonical state continuity and
  combustion O2 coupling before promotion.

### Phase 3+ F3.1e passive thermodynamic closure (2026-07-18)

- Added a pure canonical closure that derives upper/lower temperature, shared
  pressure, EOS volumes and interface from conserved shadow mass and sensible
  energy without writing legacy room state.
- Added 17 shadow-gated closure/divergence CSV fields and completed passive
  atomic parcel refund telemetry for energy and O2.
- Verified exact mass, energy and room-volume closure in no-fire, 30 s fire and
  180 s fire controls. All 344 inherited CSV columns remain identical.
- Recorded passive GO and authority NO-GO. F3.2 exterior pressure/leakage is
  now the next default-OFF phase; no baseline, tolerance, report or gap changed.

### Phase 3+ F3.1d lower projection diagnosis (2026-07-17)

- Added opt-in per-call tracing around the legacy two-zone EOS projection and
  a read-only JSONL analyzer. Legacy CSV schema and physical outputs remain
  unchanged.
- Proved on a dedicated one-room control that the remaining F3.1c residual is
  created by fixed-reference-pressure projection, not a missing physical
  flux. The first post-combustion projection removes up to `0.05700088 kg` and
  `6.99578420 kJ`; later calls geometrically backfill ambient lower gas.
- Verified exact zero deltas in a 30 s no-fire control and the same emerging
  pattern in a 30 s fire control.
- Recorded diagnostic GO and authority NO-GO. F3.1e must derive pressure,
  zone volumes and interface from conserved mass/energy before F3.2 begins.
- Changed no baseline, tolerance, official report, CTRL or gap.

### Phase 3+ F3.1c single-room thermal ownership (2026-07-17)

- Added a dedicated scratch one-room control with no openings, HVAC, ACH,
  leakage or pressure flow to separate local ownership from boundary scope.
- Added passive owners for exact local upper/lower/wall thermal transfers and
  for the bulk-O2 debit used during invalid lower-zone homogenization.
- Removed the doorway-presence restriction from passive combustion heat and
  plume ownership. Ownership now follows the physical producer, not topology.
- Increased fire snapshots with combustion ownership mask 7 from 22 to 36/36
  and reduced maximum energy residual from `36.26236788` to `6.94237481 kJ`.
  Semantic conflicts, unresolved claims and legacy CSV differences remain 0.
- Recorded a PARTIAL GO only. The remaining `0.03016636 kg` and
  `6.94237481 kJ` peaks belong to lower-zone EOS projection/reconcile, so
  `needs_flux_owner` remains 1 and F3.2 stays blocked behind F3.1d.
- Changed no physical baseline, tolerance, official report, CTRL or gap.

### Phase 3+ F3.1b effective-boundary scope diagnosis (2026-07-17)

- Audited the sealed/open predicates used by Combustion, OxygenExchange,
  Thermal, GasExchange and the Engine opening-flow cache.
- Confirmed that `interior_transport_enabled=false` is not a building-wide
  transport switch. The two `*_diag_sealed` cases retain open interior doors
  and active legacy families, so they cannot authorize a sealed shadow state.
- Ran a genuinely closed 120 s scratch control. Combustion ownership reached
  mask 7 in 19 snapshots, but `needs_flux_owner` remained 1 in 24/25 snapshots;
  maximum residuals were `0.03571883 kg` and `14.49193968 kJ`.
- Recorded a NO-GO for adding a shared boolean scope or suppressing transport
  to force closure. F3.1c must use a dedicated one-room fixture and migrate the
  remaining single-room thermal owners before any boundary authority.
- Changed no motor code, physical baseline, tolerance, report, CTRL or gap.

### Phase 3+ F3.1a combustion O2 authority diagnosis (2026-07-17)

- Confirmed that the visible upper-O2 zombie is caused by mismatched source
  semantics: Combustion can select lower-zone O2 while OxygenExchange debits
  bulk O2 and the Phase 3 shadow independently rejects combustion heat scope.
- Reused the existing default-OFF `fire_o2_canonical_enabled` flag in isolated
  controls. Synchronized routing removed all zombie rows and kept O2E1/A3
  clean, including reventilation after opening.
- Recorded a NO-GO for global activation. HRR and fuel deltas are large, O2
  supply is not yet an atomic mass-flow contract and the shadow ownership mask
  remains 6 instead of 7.
- Defined F3.1b as a shared effective-boundary/scope contract across
  Combustion, OxygenExchange and Thermal shadow adapters. F3.2 remains blocked.
- Changed no motor code, baseline, tolerance, official report, CTRL envelope
  or VALID_GAP classification.

### Phase 3+ F3.1 selected-O2 extinction guard (2026-07-16)

- Added a strict combustion invariant: when the selected O2 source is at or
  below its extinction threshold, pyrolysis demand, retained-gas generation,
  flame, smolder, pool release and actual HRR are zeroed atomically.
- Preserved `fire_o2_independent` analytic behavior and retained the fire
  object for existing reventilation semantics.
- Added structural and Godot runtime regressions for below-threshold,
  just-above-threshold and O2-independent operation.
- Recorded a NO-GO for authoritative sealed Phase 3 state: the shadow still
  reports incomplete flux ownership and non-zero mass/energy residuals.
- Kept the visible `plume_lower` upper-O2 zombie open. In affected cases lower
  O2 remains near ambient, so source authority must be resolved separately in
  F3.1a before F3.2.

### Phase 3+ F3.0k.1g vertical transport audit (2026-07-16)

- Audited active two-zone vertical openings, legacy net/directed fallbacks,
  Thermal stairwell/doorway transfer and OES opening transport without
  changing motor code.
- Confirmed that an active two-zone vertical opening already reuses the
  F3.0k.1d `doorway_species_direct` atomic contract.
- Recorded a NO-GO for manufacturing a complete bundle around the legacy
  vertical helpers: their species-only flow, Thermal gas/energy flow and OES
  O2 flow use different solvers, thresholds, directions and caps.
- Identified the legacy downward O2 term as a mixing correction proportional
  to `mass_down^2 / room_air_mass`, not the O2 carried by the gas stream.
- Completed isolated 90 s two-zone/legacy controls and a 60 s no-fire control
  without crash, incomplete CSV or official-report changes. The existing
  350 s control confirms that doorway, vertical net, vertical directed,
  Thermal and O2 mechanisms coexist during one transient.
- F3.1 sealed authority plus zero-O2 extinction is now the next motor gate.

### Phase 3+ F3.0k.1f immediate horizontal transport audit (2026-07-16)

- Audited horizontal background diffusion and no-delay doorway counterflow
  without changing motor code.
- Confirmed that their exact species contracts close, but gas mass, enthalpy
  and O2 do not form one common pre-mutation payload. Species gradients,
  optional O2 diffusion and conditional hot-to-cold enthalpy can use different
  directions in the same step.
- Activated the normally dormant no-delay branch in a scratch control:
  11,622 immediate transfers in 60 s, non-zero counterflow, zero CO/CO2/HCN
  debit-credit residual and zero unknown connection identities.
- Recorded a NO-GO for manufacturing paired gas routes from the exchange
  coefficient. Vertical net/directed exchange is the next contract audit;
  exterior pressure/leakage remains F3.2 and HVAC remains F3.5.

### Phase 3+ F3.0k.1e delayed parcel atomic lifecycle (2026-07-16)

- Added one persistent shadow identity and accepted fraction for each delayed
  parcel across carve, flight, delivery, refund and cancellation.
- Bound upper gas mass, sensible enthalpy, signed O2, smoke, CO, CO2, HCN,
  HCl, acrolein and formaldehyde to the same atomic lifecycle while preserving
  all legacy physical writes.
- Added explicit created/delivered/refunded/cancelled/in-flight telemetry and
  mass, energy, O2 and species residuals. Duplicate delivery, orphan events,
  negative balances and incomplete resolutions remain visible.
- Removed an accidental O(rooms x in-flight parcels) telemetry multiplier by
  calculating parcel residuals once per step. The valid 120 s ON run completed
  in 36.3 s versus 22.5 s OFF.
- Verified 78 OFF/ON rows and 8,970 shared legacy cells with zero differences.
  Final lifecycle residuals were zero within floating-point precision, with no
  orphan, duplicate, invalid or incomplete parcel event.
- Recorded a passive GO only. Remaining immediate, vertical and exterior
  producers still require independent contracts; zero-O2 flaming continues to
  block F3.1 and HVAC remains deferred to F3.5.

### Phase 3+ F3.0k.1d direct doorway atomic bundle (2026-07-16)

- Migrated direct two-zone doorway shadow transport to one atomic route
  carrying exact pre-mutation gas mass, source-zone sensible enthalpy, O2 and
  CO/CO2/HCN under one accepted fraction.
- Scoped complete GES ownership to the exact `doorway_bulk` family and made
  semantic ownership resolution independent of producer registration order.
- Preserved legacy physics and default-OFF behavior. A 120 s OFF/ON pair kept
  78 rows and all 115 legacy columns with zero value differences; active
  doorway bundles had fraction 1.0 with zero rejection, duplicates or invalids.
- Left delayed parcels and other non-HVAC transport families unresolved until
  they have complete atomic lifecycles. Zero-O2 flaming remains a separate
  blocker for F3.1; HVAC remains deferred to F3.5.

### Phase 3+ F3.0k.1c atomic shadow bundle (2026-07-15)

- Added an ordered atomic shadow transaction whose multi-zone routes share one
  accepted fraction limited by aggregate source gas mass, sensible enthalpy,
  O2 and CO/CO2/HCN inventory.
- Added strict route/bundle validation, duplicate and invalid counters, and
  accepted/rejected telemetry. The shadow remains read-only with respect to
  `RoomModel`; legacy physics and the default-OFF CSV schema are unchanged.
- Migrated experimental CO oxidation to one upper-zone reactant/product
  bundle: CO sink, stoichiometric O2 sink (16/28) and CO2 source (44/28).
  Legacy still consumes no O2 and adds CO2 only to bulk state.
- Runtime OFF/ON pairs retained all 115 legacy columns with zero differences.
  Carbon and oxygen close exactly, including a dedicated fraction-0.5 runtime
  test for O2 and energy limiting.
- Recorded a partial GO only: all transport controls retain unresolved mask 7
  until exact opening/parcel producers migrate to the atomic API. F3.1 and the
  zero-O2 extinction fix remain pending; HVAC stays deferred to F3.5.

### Visual/UI graph pipeline closure (2026-07-15)

- Replaced the blocking manual graph-generation path with a tracked Python
  process, 0.5 s UI polling, exit-code and fresh-marker validation, a modal
  progress overlay and a defensive 60 s timeout.
- Preserved graph-viewer/technical-summary sequencing while generation runs
  asynchronously; legacy natural-finish and window-close generation remain.
- Added explicit exit suppression so "exit without graphs" and "return to
  editor" do not write graph exports or launch Python through `_exit_tree`.
- Added cached Python preflight with Windows `py -3` fallback and a persistent
  HUD warning when graph generation is unavailable.
- Added structural regression tests for async launch, polling, stale-marker
  rejection, Python fallback, exit suppression and UI timeout paths. No
  physical simulation behavior, baseline, tolerance or validation case changed.

### Phase 3+ F3.0k.1b passive semantic arbitration (2026-07-15)

- Added a provisional shadow-only owner policy for opening, interlayer and
  chemical CO/CO2/HCN claims. Raw conflicts remain visible, but duplicate
  Thermal opening-species requests are suppressed from shadow application
  when GES owns the connection; legacy physical writers are unchanged.
- Added accepted, suppressed and unresolved claim telemetry with quantity
  masks and amounts. Missing gas mass, enthalpy and O2 bundles remain
  explicitly unresolved instead of being reconstructed from stock deltas.
- Added an exact pre-mutation CO oxidation compatibility event: upper CO sink,
  bulk-only/lower CO2 source and carbon residual. The missing legacy O2 sink
  remains visible as unresolved.
- Reconfirmed no-op behavior with 78 OFF/ON rows and 115 identical legacy
  columns. Eight sequential Godot controls passed; physics and ILV remain at
  zero FAIL. No official report, baseline, tolerance, control or gap changed.
- Recorded a partial GO only. F3.1 authority remains blocked pending an atomic
  multi-zone bundle, explicit CO-oxidation O2 chemistry and the zero-O2
  extinction regression. HVAC remains deferred to F3.5.

### Phase 3+ F3.0k.1a semantic ownership claims (2026-07-15)

- Added a passive step-local semantic claim registry keyed by stable
  connection, room direction, zone direction and quantity. Producer,
  transport family and boundary kind remain metadata so parallel legacy
  owners are reported as conflicts.
- Propagated deterministic opening identities through Thermal and GES direct,
  background, vertical and delayed-parcel species paths. Exterior, interlayer
  and chemical boundaries use separate namespaces; parcels claim only when
  created.
- Added eight opt-in CSV fields for claim/conflict counts, quantity mask,
  contested mass/energy/O2/species and unknown connection identities.
- Runtime controls detect only the expected CO/CO2/HCN overlap (mask 56) on
  interior and PPV paths. Sealed and exterior-window controls remain clean;
  all cases have zero unknown connections.
- Reconfirmed no-op behavior with 78 OFF/ON rows and 115 identical legacy
  columns. No physical state, official report value, baseline, expected
  value, tolerance, control envelope or gap changed; only report freshness
  metadata is updated for R2-1. Canonical authority remains blocked pending
  F3.0k.1b and the zero-O2 extinction regression.

### Phase 3+ F3.0k non-HVAC cross-path audit (2026-07-15)

- Completed a source and runtime ownership audit across combustion, O2,
  ThermalSystem and all implemented GES shadow contracts without changing
  motor behavior or validation policy.
- Eight HVAC-disabled scratch controls covered sealed, horizontal doorway,
  delayed parcel, vertical, exterior and PPV paths. Every implemented
  CO/CO2/HCN contract closed with zero residual and no duplicate identities,
  while all eight retained `phase3_shadow_needs_flux_owner_flag=1`.
- Recorded a NO-GO for canonical authority: gas mass/enthalpy and O2 remain
  unowned on several paths, CO oxidation is unowned, and Thermal/GES legacy
  mechanisms can overlap semantically on one physical connection.
- Reconfirmed shadow no-op behavior with 78 OFF/ON rows, 115 identical shared
  legacy columns and zero differences. No official report, baseline, expected,
  tolerance, control envelope or gap was changed.
- Defined F3.0k.1 as the next gate: connection-level owner arbitration and
  passive ownership completion. HVAC remains deferred until F3.5.

### Phase 3+ F3.0j Thermal species shadow (2026-07-15)

- Added shadow-only ownership for exact pre-delta CO, CO2 and HCN transport
  from ThermalSystem doorway hot-gas carry and both background heat-exchange
  paths, plus the optional CO upper-to-lower mixing path.
- Preserved independent source and destination upper/lower splits with a
  conservative 2x2 routing matrix. Every route applies one inventory-limited
  debit/credit transaction and exposes requested, applied and rejected mass.
- Added 30 opt-in CSV fields for species totals, source/destination zonal
  margins, accepted/rejected mass, mechanism totals, event identities,
  duplicates and per-species residuals.
- Runtime OFF/ON validation retained 78/78 rows and 115 shared legacy columns
  with zero differences. ON recorded CO, CO2 and HCN with zero rejection,
  duplicate ownership or conservation residual.
- Projection/reconcile writes, exterior purge, smoke, irritants and HVAC are
  excluded. No physical state, FED result, official report value, baseline,
  expected value or tolerance changed.

### Phase 3+ workplan: HVAC deferred (2026-07-15)

- Deferred canonical HVAC ownership until the final Phase 3+ integration
  phase because the optional subsystem will be redesigned before migration.
- Reassigned F3.0j to exact ThermalSystem species transport, followed by a
  non-HVAC cross-path closure and controlled canonical authority promotion.
- Added an explicit deferral decision with scope boundaries, re-entry
  prerequisites and acceptance gates. Non-HVAC validation may not be used to
  claim HVAC conservation or retire existing HVAC findings.

### Phase 3+ F3.0i exterior-purge species shadow (2026-07-15)

- Added one shadow-only room-to-exterior contract for the eight active GES
  purge mechanisms: pressure venting, exterior smoke vent, natural
  ventilation, ACH infiltration, outside-open purge, post-fire purge and both
  PPV dilution/exhaust paths.
- Each event captures exact pre-mutation CO, CO2 and HCN totals plus the legacy
  upper/lower split. HVAC and thermal transport remain separate owners and no
  physical `RoomModel` state, purge coefficient, FED path or timestep order
  changed.
- Added cumulative telemetry for species, zones, mechanism totals, accepted
  and rejected shadow mass, event identity, duplicate ownership and separate
  CO/CO2/HCN residuals.
- Runtime OFF/ON validation retained 150/150 rows, 163 shared columns and zero
  value differences. The ventilated control resolved 1.144611 kg with zero
  rejection, duplicates or residual; a sealed control emitted no events.
- A PPV control accounted for 6.638345 kg as 6.071909 kg applied plus
  0.566436 kg explicitly rejected, with residual below floating-point noise.
  No official report, baseline, expected value or tolerance changed.

### Validation artifact integrity audit (2026-07-15)

- Added a read-only auditor for official validation CSV structure, snapshot
  completeness, fixed-step timing, final duration and technical run package
  atomicity.
- Audited 29 CSVs (48,884 rows) and 84 technical run packages: zero malformed,
  truncated, duplicate, partial or non-finite artifacts were found.
- Documented that same-stem CSV and report JSON files may come from separate
  runners and are not a valid same-run checksum. No motor, report, baseline,
  expected value or tolerance changed.

### Phase 3+ F3.0h vertical-opening species shadow (2026-07-15)

- Added shadow-only ownership for the two legacy vertical-opening species
  helpers. Net exchange preserves independent upper/lower CO directions;
  directed exchange preserves the exact upper/lower split. CO2 and HCN remain
  lower-only because these legacy paths mutate only their bulk stocks.
- Added explicit zonal events before legacy delta writes plus cumulative
  telemetry for net/directed CO, CO2 and HCN, rejection, opposite-zone
  directions and per-species conservation residuals.
- Runtime OFF/ON validation retained 12/12 rows in the short control and
  793/793 rows in the two-storey control, with 115 shared legacy columns and
  zero value differences. The real vertical path emitted 2,154 transfers with
  zero rejection, duplicate ownership or conservation residual.
- A deterministic Godot harness exercised both net and directed helpers,
  including simultaneous upper/lower CO movement in opposite room directions.
  A horizontal control kept every vertical metric at zero. No physical state,
  FED result, baseline, expected value or tolerance changed.

### Phase 3+ F3.0g immediate background/counterflow species (2026-07-15)

- Added shadow-only ownership for the exact CO, CO2 and HCN deltas produced by
  horizontal background diffusion and the no-delay doorway counterflow. GES
  records each value before its legacy delta write; Engine only forwards it.
- Preserved the legacy zonal semantics: background CO follows its upper share,
  background CO2/HCN are lower-only because their upper stocks are unchanged,
  and counterflow records both gross directions with their own upper/lower
  splits instead of collapsing them into one net value.
- Added cumulative transfer telemetry by mechanism/species, immediate request
  rejection, and separate CO/CO2/HCN conservation residuals for both immediate
  exchange and delayed parcels. Vertical openings, purge, HVAC and thermal
  transport remain explicit exclusions.
- OFF/ON validation retained 42 rows and 115 identical legacy columns; ON now
  exports 171 columns. Immediate and parcel residuals were zero in two-room,
  corridor, sealed, remote-CO, victim-FED and zombie-ILV controls. Victim
  incapacitation remained 206.1 s and all 7 zero-O2 flame hits remain visible.

### Phase 3+ F3.0f persistent delayed-species reservoir (2026-07-14)

- Added a shadow-only persistent reservoir for delayed CO, CO2 and HCN
  parcels. A monotonic parcel id now links carve, multi-step transit,
  delivery, headroom refund and cancellation without changing legacy physics.
- Preserved the exact legacy upper/lower species split as separate shadow
  requests. Engine only forwards lifecycle events; it contains no transport or
  headroom formulas.
- Added opt-in telemetry for in-flight species, cumulative lifecycle totals,
  active parcels, rejected zonal requests, orphan/duplicate/negative events and
  the conservation residual. Smoke, irritants, O2 and gas/energy parcels remain
  outside this contract.
- Checkpoint/OFF/ON validation retained 42 rows and 115 identical legacy
  columns. Two-room, corridor and remote-CO controls closed with zero residual,
  zero rejected zonal mass and zero lifecycle anomalies; v4 exercised 0.095 kg
  of real headroom refunds.
- The sealed control created no parcels, victim incapacitation remained at
  206.1 s and all 7 known zero-O2 flame hits remain visible.

### Phase 3+ F3.0e direct doorway species transport (2026-07-13)

- Added canonical shadow ownership for the immediate two-zone doorway transfer
  of CO, CO2 and HCN. GasExchangeSystem records one zonal result before applying
  that exact object to legacy transport deltas; Engine only translates it.
- Kept background exchange, exterior purge, HVAC, thermal transport and the
  delayed parcel conveyor explicitly unowned. Their residuals remain visible.
- Added doorway request/rejection telemetry. A controlled checkpoint/OFF/ON run
  retained 42 rows and 115 identical legacy columns, with matching source and
  destination species, zero rejection and zero duplicate ownership.
- Multi-room and remote-CO controls produced nontrivial direct requests while
  `needs_flux_owner` remained active for excluded transport. All 7 known
  zero-O2 flame hits remain unchanged.

### Phase 3+ F3.0d combustion species shadow contract (2026-07-13)

- Added one immutable post-carbon-clamp combustion result for CO, CO2 and HCN.
  The same object supplies exact legacy totals and the canonical upper/lower
  shadow split, so Engine does not reconstruct yields, phi scaling or clamps.
- CO follows the existing Phase 2G upper/lower split; CO2 and HCN enter the
  upper zone. The OES CO2 tracer, smoke and irritants remain out of scope.
- Added species request telemetry and ownership bit `4`. A 60 s OFF/ON run
  retained 42 rows and 115 identical legacy columns; CO, CO2 and HCN requests
  were nonzero with zero rejected mass or duplicate ownership.
- Verified a 720 s ventilation-controlled control and preserved all 7 known
  zero-O2 flame hits. F3.0d observes the legacy defect but does not fix it.

### Phase 3+ F3.0c zonal oxygen shadow contract (2026-07-13)

- Added pre-mutation O2-only shadow results for upper, explicit-lower and
  plume-lower combustion sinks. OxygenExchangeSystem records the exact accepted
  value before applying the same zonal fraction to legacy state.
- Left the bulk O2 path deliberately unowned because it has no canonical
  upper/lower split. Its residual remains visible instead of being distributed
  heuristically.
- Added requested/rejected O2 telemetry and extended the combustion ownership
  mask to `3` for energy plus zonal O2. Species remain unowned.
- OFF/ON validation retained 42 rows and 115 identical legacy columns. The
  sealed control had zero rejects and duplicates; all 7 zombie-ILV hits remain.

### Phase 3+ F3.0b shadow combustion energy contract (2026-07-13)

- Added an explicit energy-only combustion contract to the canonical shadow
  transaction. Thermal records the exact convective heat value before applying
  it to legacy upper-zone energy; Engine performs no HRR recalculation.
- Added zero-mass energy request support and telemetry for requested combustion
  energy plus an ownership bit mask (`1=energy`, `2=O2`, `4=species`). F3.0b
  reports mask `1`; O2 and species remain deliberately unowned.
- A 60 s OFF/ON run retained 42 rows and 115 identical shared legacy columns.
  Shadow mode reported two causes with zero rejected or duplicate requests.

### Phase 3+ F3.0a first shadow flux owner (2026-07-12)

- Selected plume entrainment as the first explicit owner; combustion remains
  deferred because HRR, O2 and species are currently split across multiple
  systems and cannot yet emit one non-duplicated result.
- Split `ZoneFireSolver.transfer_lower_to_upper()` into a pure preview and an
  exact apply operation. Thermal records the preview before legacy mutation;
  SimulationEngine alone translates it into a shadow request.
- The request moves lower-to-upper gas mass, sensible enthalpy and O2 together
  and is limited to rooms with no active opening.
- Added zone residuals, plume request mass, cause count and a passive
  zero-O2-flame diagnostic. The known ILV defect is now visible in shadow mode:
  7 hits in `cfast_multi_fuel_couch_tv` from 120-180 s, including about 971 kW
  at 0.08% upper O2.
- OFF remains identical to the previous F3.0 checkpoint; a 60 s OFF/ON run had
  42 rows, 115 shared legacy columns and zero differences.

### Phase 3+ F3.0 canonical shadow transaction (2026-07-12)

- Added `Phase3ZoneMassSystem`, an opt-in shadow-only transaction built from a
  pre-step snapshot and immutable requests carrying gas mass, sensible
  enthalpy, O2 and species.
- Added `phase3_canonical_zone_shadow_enabled=false` and a headless runner
  switch, `--phase3-canonical-shadow`.
- Shadow mode exports ten diagnostic columns covering state, legacy residuals,
  rejected mass, duplicate ownership and missing flux ownership. With the flag
  OFF the legacy CSV schema is unchanged.
- F3.0 deliberately emits no authoritative motor requests yet. Legacy changes
  are reported as `phase3_shadow_needs_flux_owner_flag`; the next phase connects
  one explicit sealed-room producer at a time.
- Runtime OFF/ON comparison: 115 shared legacy columns, 12 rows, zero value
  differences. Physics and ILV suites remain at zero FAIL.

### Phase 3+ clean start: canonical two-zone route selected (2026-07-12)

Documents and diagnostics updated to start the next motor phase from a clean
baseline.

- **Active route:** F3.0 shadow canonical two-zone state. The next motor work is
  a default-OFF shadow transaction built from pre-step snapshots and explicit
  flux requests. It must not change legacy physics, required baselines, FED, or
  CSV schema with the flag OFF.
- **Closed routes:** F2.1 ledger-aware projection and local pressure-vent fixes
  are NO-GO. They expose the same upstream problem: upper/lower gas inventory is
  not canonically owned, and `project_room_state()` can recreate mass via EOS
  projection.
- **Accepted diagnostics:** F2.2a pressure-vent diagnostics remain passive and
  are retained as part of the Phase 3+ baseline.
- **Docs added/updated:** `PHASE3_CURRENT_WORKPLAN.md`,
  `PHASE3_CANONICAL_TWO_ZONE_ARCHITECTURE.md`,
  `PHASE3_F22A_PRESSURE_VENT_DIAGNOSIS.md`, `GAPS_INVENTORY.md`,
  `MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`, `STATUS_VALIDATION.md`, and
  `HANDOFF_CURRENT_STATE.md`.

### Expansión de cobertura de coherencia: 17→29 casos con CSV (2026-07-06)

Cierra el último vector de la auditoría 2026-07-06 (cobertura ~16% del corpus). 12 casos representativos generados con `run_scenario.py` (headless), deduplicados e instalados en `sim/validation/reports/`. Subsistemas cubiertos por primera vez por las 13 reglas: HVAC, supresión de agua, rotura de cristales, multifuel, corridor chain, flashover, PPV, multi-planta (9 rooms), CO remoto, especies PVC/HCl, PU foam/FED y reburn.

- **Artefacto de logging descubierto y neutralizado:** el engine duplica las filas del último timestep en `sim_log.csv` (snapshot final). Un S0 "FAIL" con factor exactamente 2.0 en `v4_co_remote_rooms` resultó ser esto; el pipeline de instalación deduplica por (time_s, room_id). Los 17 CSVs preexistentes están limpios.
- **Resultados por caso:** `cfast_suppression_water` limpio (PASS). 4 casos solo-D2PRE (Plan B multi-room, WARN no gating): `cfast_corridor_chain` (269), `cfast_multi_fuel_couch_tv` (259), `glass_break_window_spike` (623), `g3_gie_ppv_post_knockdown` (2502). 7 casos registrados como CTRL con envelope: `cfast_hvac_residential` (gap instrumentación HVAC: HVACSystem extrae smoke/CO sin alimentar acumuladores → D1:58+S1:36, mismo root cause que el skip documentado de O1), `v4_co_remote_rooms`, `flashover_simple_house`, `v8_suppression_reburn` (familia zombie ILV sin M4), `two_storey_smoke` (O2E1:2 solo en los 2 últimos pasos, familia M1; S1 multi-planta limpio), `pvc_curtain_hcl_release` y `victim_fed_incapacitation` (zombie ILV + D2 por CO del material PVC/PU, misma clase que wood_vc_reference).
- **HALLAZGO MOTOR NUEVO — write-off de inventario de fuel:** en `victim_fed_incapacitation`, a t=650s `solid_fuel_remaining_MJ` cae 2200.15 MJ de golpe para igualar `fuel_remaining_MJ` tras la extinción — los dos inventarios divergen durante el incendio y se reconcilian sin pasar por ningún acumulador de consumo (E1 lo caza). Misma clase que el gap HVAC: acción real del motor sin instrumentar. Pendiente de diagnóstico en sesión de motor.
- **Suite ILV:** el zombie ILV aparece en TODOS los casos nuevos con depleción profunda de O₂ sin M4 (esperable: M4 es opt-in per-case). 8 envelopes ILV nuevos pinean la extensión actual del bug por caso — si un cambio de motor lo empeora >~25% o añade un kind nuevo, el gate salta.
- **Estado final:** physics 10 PASS / 12 CTRL / 7 WARN / 0 FAIL (29 CSVs, exit 0) · ILV 15 PASS / 14 CTRL / 0 FAIL (exit 0) · guardrails 10/10 (exit 0) · 31 + 242 tests PASS. Los 7 WARN son todos D2PRE (Plan B): los 3 previos + los 4 nuevos solo-D2PRE.

### Guardrails nuevos R2-1 (frescura de reports) y PHY-P1 (plausibilidad ppm) + bug motor descubierto (2026-07-06)

Cierra los vectores nº 5 y nº 6 de la auditoría 2026-07-06. Sin cambios de motor.

- **R2-1 Reports freshness (`validation_guardrails.py`):** falla si el motor/casos (`sim/core`, `sim/fire`, `sim/building`, `sim/resources`, `sim/validation/cases`) tiene cambios sin commitear con el reporte limpio, o si el último commit que tocó motor/casos es posterior al último que tocó `reference_checks.json`. Basado en git (mtimes no sobreviven un checkout); se omite con nota en entornos sin git o con clone shallow (CI) — nunca da falso FAIL por entorno. Verificado en negativo: editar un `.gd` → exit 1; restaurar → exit 0.
- **BUG DE MOTOR DESCUBIERTO — CO₂ bulk >100% en salas receptoras:** al diagnosticar el FED=3.47e9 de `v3_hallway_fed_exposure` (bound débil detectado en la auditoría), la causa NO es la fórmula de Purser fuera de rango: `room_1_peak_co2_ppm = 1.099e6 ppm` (109.9% de la mezcla, físicamente imposible) y CO bulk del pasillo 237222 ppm (9× el fire room). `fed_co=3.39e9` porque el sampling a altura de víctima lee esa concentración bulk imposible. Barrido completo: **7 casos afectados**, todos `room_N_peak_co2_ppm` en salas receptoras (1.02e6–2.10e6), nunca el fire room, nunca las métricas upper. Root cause probable: acumulación sin dilución correcta en el path bulk/lower del transporte inter-room. Diagnóstico de motor pendiente de sesión dedicada (constraint: no tocar sim/core sin plan).
- **PHY-P1 Metric plausibility (`validation_guardrails.py`):** ninguna métrica `*_ppm` de los reports puede superar 1e6 (100%). Allowlist `_KNOWN_PPM_VIOLATIONS` con las 7 parejas (caso, métrica) conocidas — el bug queda visible como deuda y NO puede crecer en silencio: cualquier caso o métrica nueva que supere el 100% dispara exit 1. Retirar entradas cuando el fix de motor las corrija.
- **Tests:** +10 en `tests/test_guardrails.py` (21→31): frescura (sync→0, motor dirty→1, motor+reporte regenerado→0, commit motor posterior→1, sin repo→omitido) y plausibilidad (limpio→0, violación nueva→1, conocida→0 con nota, métrica nueva en stem conocido→1, tmp_ ignorado).
- **Guardrails: 10/10 gates PASS, exit 0.**

### Endurecimiento CTRL: envelopes por regla y conteo en ambas audit suites (2026-07-06)

Cierra el vector de validación errónea nº 3 de la auditoría 2026-07-06: `KNOWN_INTENTIONAL_CONTROLS` absorbía TODOS los findings de un caso CTRL (cualquier regla, cualquier cantidad) — una regresión nueva sobre un caso CTRL era invisible. Sin cambios de motor, thresholds ni baselines; los resultados actuales de ambas suites no cambian.

- **`scripts/simulation/audit_physics_coherence_suite.py`** y **`audit_ilv_layer_coherence_suite.py`**: `KNOWN_INTENTIONAL_CONTROLS` pasa de `frozenset[str]` a `dict[str, dict[str, int] | None]` — cada CTRL declara su envelope `{regla/kind: conteo_max}` con los conteos medidos 2026-07-06 y ~25% de margen (jitter de regeneración de CSVs no hace flapping; una regresión real sí dispara).
- **Semántica:** un finding de regla no registrada, o un conteo por encima del max, reclasifica el caso a FAIL con mensaje "CTRL envelope excedido" **y gatea aunque los findings excedentes sean WARN** — el envelope es el gate. `v1_m4_pool_release` declara explícitamente que A3 NO está en su envelope (los zombie FAILs los eliminó M5; si reaparecen, FAIL).
- Stems ad-hoc por CLI (`--intentional`) mantienen envelope ilimitado (comportamiento legacy documentado).
- **Tests:** +7 en `test_check_physics_coherence.py` (209→216) y +7 en `test_audit_ilv_layer_coherence_suite.py` (19→26): dentro de envelope→exit 0, regla no registrada→exit 1, conteo excedido→exit 1, envelope None ilimitado, CLI legacy.
- **Estado verificado:** physics 9/5/3/0 exit 0 · ILV 12/5/0 exit 0 · guardrails 8/8 exit 0 · 216+26+21 tests PASS.

### Rehabilitación de gates: ILV suite, guardrails y CI vuelven a exit 0 (2026-07-06)

Auditoría completa detectó que 2 de las 3 suites-gate llevaban en exit 1 crónico (gate "quemado": un rojo nuevo era indistinguible del rojo permanente), incluido `tests.test_guardrails::test_exit0_real_json` que corre en CI. Sin cambios de motor, thresholds, severities ni baselines.

- **`scripts/simulation/audit_ilv_layer_coherence_suite.py`**: registrados 3 CTRL nuevos — `cfast_two_floor_stairwell` (42 findings), `fuel_balance_diag_sealed` y `o2_stoich_diag_sealed` (35 c/u). Los tres son el bug ILV lower-O2 conocido (zombie HRR con o2_upper≈0.09%) en configs selladas sin M4. Retirado `v1_m4_pool_release` (0 findings tras M5 — CTRL obsoleto). Resultado: 12 PASS / 5 CTRL / 0 FAIL, exit 0.
- **`scripts/simulation/gap_inventory_check.py`**: nueva allowlist `KNOWN_VALID_GAP_REQUIRED_FAILURES` (los 5 required FAIL VALID_GAP documentados en GAPS_INVENTORY.md §hito 2026-06-21). El gate de required pasa solo si los fallidos son subconjunto exacto de la lista; cualquier fallo required nuevo sigue disparando exit 1. Detecta entradas obsoletas (check que vuelve a PASS) y JSON corrupto (all_required_pass=False sin checks fallidos).
- **`scripts/simulation/validation_guardrails.py`**: usa la clasificación VALID_GAP para el gate de required ("PASS (5 VALID_GAP)"). Linter R1-3: nueva `_PHYSICS_OVERRIDE_EXEMPTIONS` con una entrada — `(cfast_pool_fire_open, vent_bernoulli_flow_multiplier)`, override intencional de Phase 9 C4 (commit b5c63ce9) anterior al linter; queda como deuda documentada visible, la exención es por (caso, clave) y no cubre otros overrides.
- **`scripts/simulation/phase2e_preflight.py`**: sentinels non-required que fallan se reportan como "GAP (non-gating)" con margen pero no gatean (coherente con la semántica de gap del validador). Los required siguen gateando. Desbloquea el FAIL crónico de `g4 FED timing` (non-required, en los 70 gaps).
- **`docs/validation/GAPS_INVENTORY.md`**: encabezado sincronizado 345/350→349/354 required, 69→70 gaps. Delta desde 2026-06-21: +4 required (baselines `v5_m4_ventilation_throttle`, Ruta B, los 4 PASS); gaps +3/−2 por corrimiento de timestamps de presión (mismo gap estructural Phase 3, sin gap cualitativo nuevo).
- **`tests/test_guardrails.py`**: 15→21 tests. Nuevos: VALID_GAP permitido→exit 0, required nuevo no permitido→exit 1 (gap_inventory y guardrails), VALID_GAP+nuevo→exit 1, sentinel non-required→exit 0, linter exención→0/violación→1/exención-limitada-a-clave→1.
- **Estado final verificado:** guardrails exit 0 (8/8 gates PASS) · ILV exit 0 · physics coherence exit 0 (9/5/3/0 sin cambios) · 209/209 + 21/21 tests · docs links exit 0.

- **`scripts/simulation/audit_physics_coherence_suite.py`**: añadido `"wood_vc_reference"` a `KNOWN_INTENTIONAL_CONTROLS`.
- **Razón:** Caso creado explícitamente en Plan A Fase A1 para demostrar que D2 dispara en VC profundo con fuel mixto/sintético (`co_base=0.004 kg/MJ`, `co_max=0.10`). 114 D2 WARNs (t=710–1800s, ratio 0.51→2.14) y 74 D2PRE WARNs (M1 colateral, rooms 0/1/4) son todos esperados por diseño. Es el caso de referencia canónico para D2.
- **Audit suite:** 9 PASS / 5 CTRL / 3 WARN / 0 FAIL.
- **WARNs restantes (los 3 son D2PRE, todos Plan B):** `cfast_slow_growth_sealed` (fire room, referencia M1), `fuel_balance_diag_sealed` (rooms 0–5, tracer transport divergence multi-room), `o2_stoich_diag_sealed` (ídem). No son gaps nuevos — documentan el alcance de Plan B en escenarios multi-room.

### D2 CTRL: v5_m4_ventilation_throttle clasificado como control intencional (2026-06-30)

- **`scripts/simulation/audit_physics_coherence_suite.py`**: añadido `"v5_m4_ventilation_throttle"` a `KNOWN_INTENTIONAL_CONTROLS`.
- **Diagnóstico:** 13 D2 WARNs (ratio 0.51–0.62, t=225–600s, room=0) son el mecanismo M4 en acción. El throttle M4 (`fire_o2_upper_throttle_enabled`) deprime el fuego a `ILV_LATENT`; el pool de gases no quemados (`retained_unburned_MJ` alcanza 0.12–0.17 MJ por ciclo) se libera en bursts de CO que elevan el ratio CO/CO₂ por encima del threshold 0.50 cada ~45s. Los WARNs son consecuencia directa del mecanismo bajo prueba, no un defecto.
- **Audit suite post-cambio:** 9 PASS / 4 CTRL / 4 WARN / 0 FAIL (17 CSVs). Exit code 0.
- WARNs restantes: `cfast_slow_growth_sealed` (D2PRE), `fuel_balance_diag_sealed` (D2PRE), `o2_stoich_diag_sealed` (D2PRE), `wood_vc_reference` (D2+D2PRE).

### Plan A Sesión 4 — Análisis sensibilidad D2 threshold (2026-06-30)

- **Sin cambios de código ni de thresholds.** Solo análisis y documentación.
- **Caso diagnóstico creado:** `sim/validation/cases/tmp_d2_sensitivity_engine_defaults.json` — sellado 1800s, engine defaults (co_base=0.00025, co_max=0.01250), sin pool release. Resultado: max D2 ratio = **0.2982** (phi=8.24). NUNCA alcanza 0.30 ni 0.50.
- **Hallazgo clave — bifurcación pool release:** D2 ratio > 0.50 ocurre SOLO con `fire_pool_release_max_fraction > 0` (CO del pool de gases no quemados, no sujeto al cap phi-scaling). Sin pool release, max ratio con engine defaults = 0.298. Con pool release: 0.566–0.800.
- **D2 threshold 0.50 es correcto:** detecta pool-release CO bursts (v5_m4_ventilation_throttle 225s, v1_m4_pool_release 285s) y combustibles mixtos (wood_vc_reference 710s). No dispara en VC limpio de madera SFPE.
- **Corrección a recomendación A2:** A2 recomendó bajar threshold a 0.20; descartado — causaría WARNs artificiales en casos diagnóstico a t=135s (room non-fire, M3 init).
- **Recomendación final: Opción 3 — mantener threshold 0.50 sin cambios.**
- **Descubrimiento:** `v5_m4_ventilation_throttle` genera 13 D2 WARNs actualmente (pool_release=0.18). Caso no está en CTRL — pendiente sesión futura.
- **Audit state actual:** 9 PASS / 5 WARN / 3 CTRL / 0 FAIL (17 CSVs). Nuevas WARNs: fuel_balance_diag_sealed D2PRE, o2_stoich_diag_sealed D2PRE, v5_m4_ventilation_throttle D2+D2PRE.

### Plan A Fase A2 — Análisis impacto defaults CO yield (2026-06-30)

- **Sin cambios de código.** Solo diagnóstico y documentación.
- **Hallazgo principal:** `FuelObjectModel.co_yield_kg_per_MJ = 0.00025` es irrelevante — ningún caso usa `fuel_objects` explícito. Los defaults reales son `SimulationEngine.co_base_yield_kg_per_MJ = 0.00025` y `co_max_yield_kg_per_MJ = 0.01250`.
- **Defaults engine son SFPE wood correctos:** 0.004 kg/kg ÷ 16 MJ/kg = 0.00025 kg/MJ (FC); 0.200 kg/kg ÷ 16 MJ/kg = 0.01250 kg/MJ (VC max). phi-scaling ya activo para 81 casos plain.
- **D2 threshold (0.5) inalcanzable con madera pura:** Max ratio molar con engine defaults = 0.236 (phi→∞, cap 0.01250 kg/MJ). Para disparar D2 a phi=2 se necesita co_base ≥ 0.00358 kg/MJ (14× SFPE wood FC).
- **Cambio global co_base 0.00025→0.004 sería físicamente incorrecto para madera** (0.064 kg/kg FC = 16× SFPE). FED CO 16× inflado para todos los 81 casos plain. No afecta 349/354 PASS (0 CO checks non-CFAST), pero invalida física.
- **Tres opciones post-A2:** (1) Bajar D2 threshold a ~0.20 — captura madera VC severa phi≥3 con engine defaults. (2) Añadir caso PU foam VC (co_base=0.002, co_max=0.03). (3) Mantener D2 como guardia de escenarios extremos solamente. Requiere sesión con plan explícito.
- **Recomendación:** Opción 1 o 3. NO tocar engine defaults de CO yield.

### Plan A Fase A1 — Caso diagnóstico `wood_vc_reference` (2026-06-30)

- **Caso creado:** `sim/validation/cases/wood_vc_reference.json` — madera VC realista sin force override.
  - Parámetros clave: `co_base_yield_kg_per_MJ: 0.004`, `co_max_yield_kg_per_MJ: 0.10`, `fire_co_phi_rate: 2.0`. Sellado, 1800s, alpha=0.003 kW/s².
  - Sin `fire_co_yield_force_kg_per_MJ` — phi-scaling activo.
- **Resultado:** D2 WARN dispara en **t=710s** — primer timestep con `regime=VENTILATION_CONTROLLED_BURNING`, ratio=0.5123 (threshold 0.5), phi=3.45, yld_co=0.04554 kg/MJ.
- **Ratio D2 evoluciona:** 0.51 (t=710s) → 2.13 (t=1790s). `yld_co` estabilizado en ~0.04563 kg/MJ (clamp activo: `co_max=0.10` vs raw exp muy alto a phi>5).
- **D2PRE también activo:** 74 WARNs — M1 o2_scale double-throttle opera también en este caso (esperado, no relacionado con Plan A).
- **Audit suite:** 0 FAIL / 13 PASS / 2 WARN / 2 CTRL — sin regresiones. `wood_vc_reference` clasificado WARN (correcto).
- **CSV producido:** `sim/validation/reports/wood_vc_reference.csv` (181 timesteps × 6 rooms, columnas CO/CO₂/phi/regime/yield).
- **Conclusión:** Motor phi→CO scaling funcional con configuración SFPE wood. D2 detecta subventilación gradual. Contrasta con `cfast_slow_growth_sealed` donde force override bloquea phi-scaling y D2 no dispara (intencional).

### Plan A — Diagnóstico CO yield en régimen VC (2026-06-30)

- **Sin cambios de código.** Solo diagnóstico y documentación.
- **Root cause identificado: tres capas** explican por qué CO/CO₂ ratio masa en `cfast_slow_growth_sealed` es ~0.004–0.008 en condiciones VC (phi 2.8–3.6), muy por debajo de SFPE wood (~0.3 masa / ~0.47 molar).
- **Capa 1 (primaria, intencional):** `fire_co_yield_force_kg_per_MJ: 0.0003` en `cfast_slow_growth_sealed.json` bypassa todo el escalado phi (`CombustionSystem.gd:705–707`). Yield fijo CFAST-compatible. Confirmado por CSV: `yld_co ≈ 0.000300` constante a todo phi (1.0–3.6). Valor phi-escalado a phi=2.79 sin force: ~0.0108 kg/MJ (36×).
- **Capa 2 (brecha silenciosa):** `co_base_yield_kg_per_MJ` default = 0.0 → CO = 0 kg en casos sin yield explícito. `FuelObjectModel.co_yield_kg_per_MJ = 0.00025` (default muy bajo, nivel CFAST; SFPE wood FC = 0.004 kg/MJ).
- **Capa 3 (clamp invertido):** `co_max_yield_kg_per_MJ` default = 0.0 → `clampf(scaled, base, 0.0)` = base → phi-scaling silenciosamente congelado en co_base. Solo `ghanekar_kitchen_living_room.json` tiene `co_max > co_base` → único caso con phi-scaling funcional.
- **Motor phi→CO: correcto.** Fórmula `co_base * exp(k*(phi-1))`, k=2.0 implementada en `CombustionSystem.gd:659–672`. La infra existe; las tres capas la anulan en corpus actual.
- **Plan A Fase A1 (pendiente):** Caso `wood_vc_reference.json` con `co_base=0.004`, `co_max=0.10`, sin force override → validar que D2 dispara en VC.
- **Plan A Fase A2 (pendiente):** Calibrar FuelObjectModel defaults vs SFPE. Requiere análisis impacto corpus.

### D2 Fase 3 — regla diagnóstica CO/CO₂ upper ratio (WARN, no gating) (2026-06-30)

- **Regla D2** añadida a `check_physics_coherence.py`. Campos: `co_upper_ppm` / `co2_upper_ppm_mass` (ambas mass-derived, mismo denominador de densidad caliente). Métrica: `ratio = co_upper_ppm / co2_upper_ppm_mass`. Threshold: `ratio > 0.5` (CO > 50% de CO₂ en moles — VC severo / post-FO). Severity: **WARN** — diagnóstico, no gating.
- **Skip conditions**: `co2_upper_ppm_mass` ausente (21 CSVs legacy); `co2_upper_ppm_mass < 1000 ppm` (CO₂ no establecido); `time_s < 60 s` (M3: mass path inicia en 0 kg).
- **`co2_upper_ppm` tracer excluido** como denominador — o2_scale double-throttle (M1) lo suprime y produciría ratios artificialmente altos.
- **Tests**: 26 tests `TestCheckD2` añadidos. Suite total: **209/209 PASS**.
- **Resultado en corpus**: 21 CSVs legacy → skip graceful, 0 findings. `cfast_slow_growth_sealed`: ratio = 0.006–0.008 → threshold 0.5 no disparado. **0 findings D2**. Audit suite: 13 PASS / 1 WARN (D2PRE) / 2 CTRL / 0 FAIL.
- **Observación calibración:** El ratio CO/CO₂ de generación (~0.004–0.005 masa) es muy inferior al rango SFPE para under-ventilated fires (~0.3 masa). SimuFire infra-estima CO en régimen VC — pendiente Plan A (calibración phi→CO yield en CombustionSystem).
- **Pendiente Plan B:** Fix motor para o2_scale double-throttle en OES tracer CO₂ (causa D2PRE WARNs). Requiere plan motor formal y validación FED. Prioridad baja — no bloqueante para corpus actual.

### D2 Diagnóstico — causa raíz D2PRE confirmada (2026-06-30)

- **Root cause identificado**: tres mecanismos compuestos explican la divergencia tracer vs mass path.
- **M1 (dominante):** OES `o2_scale = o2_upper/0.209` double-throttlea la producción del tracer. A t=700s o2_scale=0.301; HRR ya refleja disponibilidad de O₂ → doble descuento. Ratio producción mass/tracer: 2.56× a t=700s, 2.65× a t=1800s.
- **M2 (amplificador):** `compute_co2_upper_ppm_mass` usa densidad caliente (≈0.71 kg/m³ a 186°C); OES usa densidad ambiente 1.2 kg/m³ → ratio densidades 1.68× a t=700s (más correcto en mass path).
- **M3 (early-transient):** Tracer inicia en 400 ppm atmosférico; mass en 0 kg. Tracer > mass para t < 300s; inversión en ~t=290s.
- **dt_physics = 0.0833s:** `co2_generated_kg_step` es por paso físico; 120 pasos/10s → producción 0.155 kg/10s > ACH drain 0.082 kg/10s → co2_kg crece correctamente.
- **Track más fiable para tenabilidad:** mass path para t > 300s. D2 ratio (Fase 3) **desbloqueado** sobre mass path.
- Sin cambios de código. Solo diagnóstico.

### D2 Fase 2 — regla diagnóstica D2PRE (WARN, no gating) (2026-06-30)

- **Regla D2PRE** añadida a `check_physics_coherence.py`. Métrica: `rel_div = |co2_upper_ppm_mass − co2_upper_ppm| / max(co2_upper_ppm, 400)`. Threshold: `rel_div > 1.0` (mass >2× tracer o viceversa). Severity: **WARN** — no afecta exit code, no gating.
- **Skip graceful** en CSV legacy (pre-D2-Fase-1) que no tienen `co2_upper_ppm_mass`. Los 15 CSV legacy del corpus no registran ningún finding.
- **Tests**: 21 tests `TestCheckD2PRE` añadidos. Suite total: **183/183 PASS**.
- **Resultado diagnóstico sobre `cfast_slow_growth_sealed`**: **243 D2PRE WARNs** — room 0 (fire room) diverge sistemáticamente desde t~320s: tracer toca techo ~85k ppm y decrece por dilución, mass-derived continúa acumulando hasta >220k ppm. `rel_div` alcanza 2.2+ y crece indefinidamente. Exit code = 0.
- **Audit suite**: 13 PASS / 1 WARN (cfast_slow_growth_sealed con D2PRE) / 2 CTRL / 0 FAIL.
- **Conclusión D2**: El ratio CO/CO₂ (Fase 3) queda **bloqueado** por divergencia sistemática entre representaciones. La hipótesis de root cause es que el tracer ODE (`OxygenExchangeSystem`) pierde CO₂ por dilución de intercambio O₂/N₂, mientras el path mass-derived (`CombustionSystem`+`GasExchangeSystem`) acumula correctamente. Resolver antes de implementar D2 ratio.

### D2 Fase 1 — exportar co2_upper_ppm y co2_upper_ppm_mass al CSV (2026-06-30)

- **`compute_co2_upper_ppm_mass()`** añadida a `ThermalSystem.gd`. Fórmula: `co2_upper_kg * 29e6 / (upper_zone_mass_kg * 44.0)`. Guarda en `upper_gas_kg < 0.1` → fallback a tracer (400 ppm ambient). FED sin cambio: sigue usando `compute_co2_upper_ppm` (tracer).
- **`co2_upper_ppm`** (tracer) añadida al CSV — faltaba en SimulationLogWriter aunque estaba en el state dict.
- **`co2_upper_ppm_mass`** (mass-derived) añadida al CSV — nueva columna para D2-pre diagnóstico en Fase 2.
- **Callable registrado** en `SimulationEngine.gd`, declarado en `SimulationStateBuilder.gd`, exportado en `SimulationLogWriter.gd`. Header=115 columnas, body=115 appends — match confirmado.
- **Verificación**: `cfast_slow_growth_sealed` ejecutado headless (384 rows). `co2_upper_ppm` y `co2_upper_ppm_mass` presentes. Fallback correcto a 400 ppm en t=5s (sin zona caliente). Audit suite: 14 PASS / 2 CTRL / 0 FAIL — sin regresiones.
- **D2PRE y regla D2** quedan para Fase 2/3. `co2_upper_kg` init sin cambio (`RoomModel.gd` no tocado).

### S1 promoted to FAIL/gating (2026-06-30)

- **S1 promovida a FAIL/gating** en `_check_s1_smoke_per_room_balance` — cambio de `severity="WARN"` a `severity="FAIL"`. Criterios C-S1-1 a C-S1-6 todos cubiertos o documentados.
- **`cfast_two_floor_stairwell` añadido a KNOWN_INTENTIONAL_CONTROLS** en `audit_physics_coherence_suite.py`. El caso tiene A3/O2E1 por depleción de O2 en edificio sellado (mismo root cause que `v1_backdraft_accumulation`); S1 es limpia. Propósito del caso: cobertura C-S1-3 (transporte inter-planta).
- **Corpus final**: 14 PASS / 2 CTRL / 0 FAIL (S1 gating sin regresiones).
- **Tests**: 162/162 PASS. `TestCheckS1.test_residual_above_floor_triggers_fail` actualizado de WARN → FAIL.
- **validate_reference_cases**: 349/354 sin cambio.

### S1 C-S1-3 multi-floor coverage — cfast_two_floor_stairwell (2026-06-30)

- **C-S1-3 cubierto**: `cfast_two_floor_stairwell` (13 rooms, PB + P1, `stack_effect_enabled`) ejecutado headless. Se añadió `csv_log_file_path` al caso JSON (único cambio — faltaba en `engine_overrides`).
- **Resultado S1**: exit 0, sin WARNs. Transport inter-planta confirmado: `Escalera P1` (room 6) 0.101 kg, `Distribuidor P1` (room 7) 0.138 kg, dormitorios P1 0.021–0.026 kg — todos por encima del floor S1 (0.01 kg).
- **Corpus**: **15 PASS / 1 CTRL / 0 FAIL** — sin regresiones.
- **C-S1-2** (multi-room): ya cubierto por `cfast_two_room_door_open` (5.43 kg transport, 6 rooms).
- **C-S1-4 venting**: cubierto por `fp_ilv_open_partial_window` (45.97 kg), `cfast_slow_growth_sealed` (15.87 kg).
- **C-S1-4 deposition**: limitación de escala documentada — max 0.002 kg en corpus, por debajo del floor 0.01 kg. Físicamente plausible (soot settling bajo en escenarios ≤600 s). No bloquea promoción.
- **C-S1-5** (sin residuos compensados): cubierto — S1 exit 0 en ambos casos con transporte no trivial.
- S1 permanece **WARN**. No se tocó motor/GDScript. `validate_reference_cases` sin cambio (349/354 PASS).

### S1 smoke per-room balance — added as WARN (2026-06-30)

- **S1 implemented as WARN** in `scripts/simulation/check_physics_coherence.py`. Per-room invariant: `Δsmoke_kg = Δsmoke_generated_kg_total − Δsmoke_vented_kg_total − Δsmoke_deposited_kg_total + Δsmoke_net_transport_kg_total`. Uses cumulative per-room totals to be invariant to log_interval/timestep ratio.
- **No GDScript changes** — per-room accumulators (`smoke_generated_kg_total`, `smoke_vented_kg_total`, `smoke_deposited_kg_total`, `smoke_net_transport_kg_total`) were already instrumented in `RoomModel.gd`, populated by `GasExchangeSystem`/`ThermalSystem`, and exported to CSV.
- **Corpus audit (2026-06-30)**: 14 PASS / 0 WARN / 0 FAIL across all active cases. Graceful skip on legacy CSVs without S1 columns.
- **Tests**: 5 `TestCheckS1` tests PASS; 162/162 total tests PASS in `test_check_physics_coherence.py`.
- **S0 stale comment fixed** — module docstring and `_check_s0_smoke_global_conservation` docstring updated to reflect that S1 now exists.
- **S1 remains WARN** — promotion to FAIL/gating is a separate closure decision after sustained clean corpus evidence. `validate_reference_cases` unchanged at 349/354 PASS.
- **D2 still blocked** — CO/CO2 ratio rule remains blocked by `co2_upper_ppm` tracer-derived vs `co2_upper_kg` mass-derived dual-tracking. No change.

### O1/O2E1 gating closure and balance lane sync (2026-06-29)

- **O2E1 promoted to FAIL/gating** (`6db12f7`): Thornton HRR↔O2 cross-check now exits as FAIL after M5 produced clean C1 evidence. The rule uses `o2_consumed_fire_kg_total` against `hrr_kj_total * 7.6e-5 kg/kJ`; no physics or tolerances changed.
- **O1 canonical doorway gap closed** (`bd3e13e`): `_apply_canonical_doorway_exchange` no longer double-counts `_cde_net_hot` as direct `o2_net_transport_kg_total`; CDE affects bulk O2 through zone blend, and `o2_zone_sync_kg_total` now closes that balance. Missing `cold_room` zone sync tracking was added.
- **O1 promoted to FAIL/gating** (`6a8dd2a`, `41eb069`): bulk O2 balance is now gating after the canonical doorway case (`cfast_two_room_door_open`) audited clean.
- **Current physics coherence corpus**: 14 PASS / 0 FAIL in active cases. `validate_reference_cases` remains **349/354 PASS** with only the 5 pre-existing `VALID_GAP` failures.
- **Active gating balance lanes**: `S0`, `E1`, `D1`, `O2E1`, `O1`, plus M5 validation coverage. **Blocked lane**: `D2` (CO2 upper dual tracking — `co2_upper_ppm` tracer vs `co2_upper_kg` mass). **S1 added as WARN** (see 2026-06-30 entry).

### M5 post-backdraft HRR cut plan (2026-06-28)

- **Estado guardado, no implementado**: siguiente experimento de motor propuesto como `fire_post_bd_hrr_cut_enabled` (default `false`), activado solo en `v1_m4_pool_release` si se aprueba el cambio de codigo.
- **Causa exacta post-evento**: despues del backdraft principal (`backdraft_triggered=1` t=350 s, pool agotado t=355 s), `hrr_target_kw` cae a 0 porque `can_flame=false`, pero `room.hrr_kw` sigue bajando por la constante de suavizado (`fire_hrr_fall_tau_s=20`). Esa inercia produce filas A3/O2E1 en la fase zombie. Mas tarde, cuando `o2_upper` se recupera por encima del umbral M4, el motor puede volver a alimentar llama/pool y generar un segundo evento artificial.
- **Guard M5 recomendado**: insertar en `CombustionSystem.gd` despues del bloque `room.backdraft_active` y antes del consumo/reacumulacion del pool. Si `fire_post_bd_hrr_cut_enabled=true`, `not room.backdraft_active`, `not can_flame`, `not latent_viable`, `room.retained_unburned_MJ < 0.001` y `room.fire_o2_ref < fire_o2_min_for_flame`, cortar `room.hrr_kw`, `room.hrr_target_kw` y `retained_generation_kw` a 0.
- **Criterios de aceptacion esperados**: `v1_m4_pool_release` mantiene el backdraft principal a t≈350 s; no aparece segundo backdraft; A3=0; O2E1=0 WARN; physics coherence para el caso sale limpio. `validate_reference_cases` y guardrails globales no cambian porque el flag queda default-off.
- **Decision vigente**: O2E1 permanece WARN hasta que M5 produzca un C1 limpio o se apruebe una politica formal de exclusion. No tocar tolerancias ni severidad O2E1 en este paso.

### M4 pool-release path-exercise case `v1_m4_pool_release` (2026-06-27)

- **Caso `v1_m4_pool_release`**: path-exercise controlado que verifica que el motor ejecuta el camino backdraft/pool-release con M4 activo y gates relajados. Derivado de `v1_backdraft_accumulation` con overrides: `fire_o2_upper_throttle_enabled: true`, `fire_backdraft_pool_threshold_MJ: 0.35`, `fire_backdraft_o2_max: 0.20`, `fire_backdraft_temp_min_c: 100.0`, `fire_backdraft_lfl: 0.001`. No representativo de un backdraft real.
- **Backdraft ejercitado**: `backdraft_triggered=1` a t=350 s. `retained_unburned_MJ` acumuló hasta 0.371 MJ (pool exhaustado en t=355 s), HRR spike a 21.369 kW. Path de código backdraft/pool-release confirmado activo.
- **A3 zombie post-evento (CTRL)**: tras agotar el pool (t≥365 s) el motor vuelve a `FULLY_DEVELOPED` con `o2_upper=0.0008` — mismo zombie que `v1_backdraft_accumulation`. Los 8 A3 FAILs y 5 O2E1 WARNs son consecuencia del bug de motor (no de la física de backdraft). O2E1 no presenta WARNs durante la ventana de backdraft propiamente dicha (t=340-360 s).
- **CTRL registrados**: `v1_backdraft_accumulation` y `v1_m4_pool_release` añadidos a `KNOWN_INTENTIONAL_CONTROLS` en `audit_physics_coherence_suite.py` y `audit_ilv_layer_coherence_suite.py`. Physics coherence suite pasa a exit 0 (antes exit 1 por v1_backdraft sin registrar).
- **Decisión C1 cerrada — O2E1 permanece WARN**: C1 queda marcado "path exercised, not clean promotion evidence." O2E1 está limpio durante la ventana de backdraft (t=340-360 s); los 5 O2E1 WARNs post-evento son consecuencia del zombie A3 (bug de motor separado, no fallo Thornton). O2E1 no se promueve a FAIL hasta obtener un caso C1 que salga exit 0 en `check_physics_coherence.py`, o hasta que se apruebe formalmente una política de exclusión que descarte los WARNs del zombie como no-bloqueantes. Próximo paso: fix guard A3 en `CombustionSystem.gd` (vía A) o decisión de exclusión documentada (vía B).

### Corpus diagnóstico O2E1/O1 — 3 casos nuevos (2026-06-27)

- **Ampliación de corpus O2E1/O1**: tres casos nuevos corridos para cubrir los criterios WARN→FAIL antes de promover O2E1. Sin cambio de física, motor, tolerancias ni baselines. Solo se actualizan los JSON de caso (añadido `csv_log_file_path`, `enable_logging`) y se generan los CSVs.
- **`cfast_slow_growth_sealed` (C2) — PASS completo**: O2E1 y O1 PASS en 1800 s sellado. Confirma que el acumulador `o2_consumed_fire_kg_total` se mantiene dentro de la tolerancia Thornton bajo fuerte depleción de O2 y cap activo. Criterio C2 (larga duración ≥ 600 s) cubierto. Apto para suite permanente.
- **`cfast_two_room_door_open` (C3) — O2E1 PASS, O1 247 WARNs**: O2E1 sin hallazgos — criterio C3 (multi-room con intercambio O2) cubierto para O2E1. Los 247 O1 WARNs exponen un gap estructural: la fórmula O1 no captura completamente el flujo O2 vía `canonical_doorway_exchange_enabled`. Residual típico 0.11-0.12 kg vs. tolerancia 0.003-0.004 kg, en todos los rooms desde t=90 s. Gap documentado — O1 no debe ser gating en multi-room con canonical doorway hasta resolverlo.
- **`v1_backdraft_accumulation` (C1) — FAIL**: A3 (2 FAIL): motor mantiene `FULLY_DEVELOPED` con `o2_upper=0.0009` (0.09%), violando la transición de régimen con `fire_o2_min_for_flame=0.10`. Los 16 O2E1 WARNs son consecuencia directa: HRR acumula ~3425 kW mientras O2 está capeado a cero. `retained_unburned_MJ=0` en todo el CSV — el pool release nunca activa. Criterio C1 (backdraft/pool-release) NO cubierto.
- **Nueva incoherencia A3 identificada**: motor no transiciona régimen cuando O2 baja a 0.09% — el fuego debería estar LATENTE pero permanece FULLY_DEVELOPED. Esta incoherencia es capturada por la regla A3 existente. No se corrige en esta sesión.
- **Estado criterios WARN→FAIL**: C2 ✅ C3 ✅ C4 ✅ (fp_ilv_open_partial_window) — solo C1 pendiente.

### Physics validation — general coherence auditor and D1 CO balance (2026-06-25)

- **General physics coherence auditor** — added `check_physics_coherence.py` and `audit_physics_coherence_suite.py`, integrated into the full reference suite. Current gating rules cover strong thermal inversion (`B1`), FED arithmetic (`C1`), FED monotonicity (`C2`), HRR without fuel (`A2`), regime vs critical upper-layer O2 (`A3`), and per-step CO mass balance (`D1`).
- **Phase 3 pressure regression fixed** — removed the `ThermalSystem` branch that reset `pressure_pa_therm` when the Phase 3A pressure ODE was disabled. `cfast_closed_t120_pressure_pa` is restored and the reference suite is back to **349/354 PASS** with only the 5 accepted `VALID_GAP` failures.
- **CO/CO2/HCN diagnostic instrumentation** — CSV exports now include toxic-gas diagnostic fields needed for balance checks, including CO mass, per-step generated CO/CO2/HCN, carbon clamp/error fields, CO net transport and cumulative CO balance terms.
- **D1 CO balance is FAIL-gating** — D1 verifies per-room, per-step CO conservation using `co_kg`, cumulative generated CO, broad net CO transport and exterior CO removal. It started as WARN, found three untracked CO paths, and was promoted to FAIL after fresh CSVs produced 0 findings.
- **D1 tracking fixes** (`b41fcbd`) — instrumented `GasExchangeSystem._purge_upper_species_to_exterior_direct`, `ThermalSystem._flush_contaminant_deltas`, and `GasExchangeSystem._release_pending_interior_deliveries` so all relevant CO movement is included in the D1 balance.
- **E1 fuel balance uses explicit solid fuel** — E1 now validates `solid_fuel_remaining_MJ` against `fuel_consumed_MJ_total`, avoiding the legacy visible `fuel_remaining_MJ` field whose semantics can include retained/unburned/object state and produce false residuals.
- **S0 smoke global conservation is FAIL-gating** — S0 validates `Σ smoke_kg + smoke_in_transit_kg` against generated minus vented minus deposited smoke. Closure fixed missing ACH and natural-vent purge accounting, exposed delayed interior smoke in transit, and stopped sub-threshold smoke mass from being zeroed. Fresh audit: 11/11 CSVs PASS, 0 findings; 9 fresh-schema CSVs exercise S0/E1 and 2 legacy `p2h_diag_*` CSVs skip gracefully.
- **O1 bulk O2 balance is WARN-clean** — O1 now audits bulk `room.o2` mass using `air_mass_kg`, bulk-only O2 consumption, exterior net exchange, inter-room transport and zone-sync accumulators. It found and fixed stale/incorrect CSV semantics (`o2` must export actual `room.o2`) and post-clamp transport accounting. Current corpus: 11/11 PASS, 0 O1 findings, max residual < 4e-4 kg. O1 remains WARN, not FAIL-gating, until validated on broader long-duration/multi-floor cases.
- **O2E1 Thornton cross-check added and fixed (WARN, commits 90c436a → 88ce7d7)** — added cross-subsystem rule O2E1 comparing CombustionSystem HRR accumulator (`hrr_kj_total`) against OES O2 consumption via Thornton. Initial implementation used `o2_consumed_kg_total_all` which double-counted in standard two-zone mode (bulk + upper both accumulated → 2× Thornton, 1308 false WARNs). Fix: introduced `o2_consumed_fire_kg_total`, a tracking-only primary-path accumulator that captures exactly one Thornton unit per step (bulk when it ran; lower/plume/upper otherwise). O2E1 now uses this column. Corpus re-audit after fix (2026-06-27, 11 CSVs): **11/11 PASS, 0 WARN, 0 FAIL**. 157 unit tests PASS. Guardrails: 349/354 stable. O2E1 remains WARN, not gating.
- **Motor validation checklist** — added `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`, capturing the remaining validation items for HRR/energy, O2, toxic gases, smoke/visibility, FED, temperatures, two-zone behavior, ventilation, pressure, wall radiation and the future CFAST/reference battery.
- **Known toxic-gas caveat** — `co2_upper_ppm` is tracer-derived (`co2_upper * 1e6`), while CO upper ppm is mass-derived. CO/CO2 ratio rules remain blocked until the CO2 upper dual-tracking semantics are resolved.

### FP ILV HUD / Smoke Visibility (visual-only)

- **HUD ILV critical display** (`a6d44c0`) — FP technical HUD now shows `Reg ILC`, `Reg ILV` or `Reg ILV CRIT`, labels gases by layer (`O₂u/O₂l`, `COu`, `CO₂u`, `HCNu`), removes duplicated HRR/visibility from the top FP panel while the technical overlay is visible, and visually dampens FP flames in `ILV_LATENT` or critical upper-layer O₂. No simulation physics changed.
- **FP smoke visibility hardening** (`b59fa33`) — ILV-critical FP view now clamps effective display visibility to a severe default (`smoke_overlay_ilv_severe_visibility_m = 1.6` m), increases overlay opacity, and allows ceiling/opening lights to attenuate almost completely through smoke (`smoke_light_min_transmission = 0.01`). Tests cover `Reg ILV CRIT`, `Vis FP 1.6m`, damped fire light, and near-extinguished ceiling light under ILV smoke.
- **FP eye-height layer consistency** (`d69232c`) — FP technical HUD now selects gas labels/readings by eye height versus `smoke_layer_m`/`smoke_display_layer_m`, instead of mixing upper-layer gases with lower-layer visibility/temperature while crouched. Critical upper-layer O₂ can override the display label to `Reg ILV CRIT`. No simulation physics changed.
- **Overhead smoke visibility tightening** (`696f03f`) — FP smoke display no longer jumps back to clear `Vis FP 29m` merely because the camera is below the smoke plane when the upper layer is optically severe. Crouching still improves visibility, but ceiling smoke/lights remain obscured.
- **ILV layer coherence detector** — added `scripts/simulation/check_ilv_layer_coherence.py` plus unit tests. The check fails on exported CSV rows with significant HRR and critical `o2_upper` while the base regime remains fuel-controlled or `o2_hrr_factor` remains high from lower/global oxygen.
- **Open follow-up:** this is presentation-layer mitigation only. New manual QA logs show a motor/layer-coupling issue: HRR and base regime can remain high/`FUEL_CONTROLLED` with `o2_upper` near zero while `o2_lower` remains fresh. The next milestone is an ILV motor audit covering HRR/regime/O₂/gases/smoke by layer.

### ILV motor — Ruta B: v5_m4_ventilation_throttle reference case (2026-06-23)

- **Caso de referencia M4 `v5_m4_ventilation_throttle`** — nuevo caso headless que verifica que `fire_o2_upper_throttle_enabled: true` SUPRIME el spike HRR zombie en ventilación exterior. Semántica invertida respecto a `v5_ventilation_hrr_spike` (legacy control): el nuevo caso testea supresión (HRR ≤ 600 kW), no ocurrencia del spike.
- **`v5_ventilation_hrr_spike` sin cambios** — conservado como caso legacy/control que expone el bug ILV (spike 3245 kW, `time_hrr_above_1000_post_vent ≈ 164 s`). No se modifica ni se activa M4 en él.
- **Métricas verificadas** (física M4 desde `tmp_v5_m4.csv`): `peak_hrr ≈ 492 kW` (≤ 600 ✓), `min_o2_upper ≈ 6.37%` (≥ 5% ✓), `min_l150 ≈ 1.98 m` (≥ 1.90 ✓), `peak_co_upper ≈ 12386 ppm` (≥ 1000 ✓).
- **Archivos nuevos**: `sim/validation/cases/v5_m4_ventilation_throttle.json`, `sim/validation/baselines/v5_m4_ventilation_throttle.json`, `sim/validation/reports/v5_m4_ventilation_throttle.{json,csv}`.
- **Suite ampliada**: `validate_reference_cases.py` incluye el nuevo caso en `build_single_room_fire_checks()`. Guardrails suben de 350 a 354 checks (4 nuevos, todos PASS).

### ILV motor — Phase C: Motor credibility audit + primera migración M4 (2026-06-22)

- **Suite auditor `audit_ilv_layer_coherence_suite.py`** (`d635c83`) — wrapper batch sobre `check_ilv_layer_coherence.py`. Escanea todos los CSVs en `sim/validation/reports/`, reporta findings por archivo (total rows, finding counts, peor fila), sale con código 1 si hay findings salvo `--allow-findings`. 16 tests Python PASS. Resultados sobre 10 CSVs: 7 PASS, 3 FAIL (364 findings totales).
- **Mapa de daño — motor credibility audit**: 8 CSVs permanentes auditados. 3 casos con HRR zombie: `fp_ilv_upper_throttle_off` (258, control intencional), `tmp_v5_off` (95, spike calibrado sobre bug), `layer_interface_single_room_window` (11, hallazgo nuevo — ILV incidental en testbed de capas).
- **Primera migración M4 segura: `layer_interface_single_room_window`** (`ee9216c`) — `fire_o2_upper_throttle_enabled: true` activado permanentemente en caso de regresión de interfaz de capa. El caso no tiene `threshold_metrics` — es diagnóstico puro de alturas de capa. Todos los 7 baseline checks pasan: los mínimos de capa son idénticos (descenso ocurre antes de que M4 se active, t<130 s), los finales dentro de tolerancia. Zombie eliminado: HRR 1142→32 kW a t=180 s, `o2_upper` se recupera de 0.08% a 8.5%. Fix adicional: `two_zone_solver_enabled: true` añadido explícitamente al JSON del caso (y `fed_thermal_layer_smoke_only.json`), corrigiendo 2 failures pre-existentes en `test_layer_interface_model.py`. Suite auditor post-migración: 7/8 PASS (único FAIL = `fp_ilv_upper_throttle_off`, control intencional).

| Tiempo | HRR OFF | HRR M4 | o2_upper OFF | o2_upper M4 | Regime OFF | Regime M4 |
|--------|---------|--------|-------------|------------|-----------|----------|
| t=100s | 377.7 kW | 377.7 kW | 16.9% | 16.9% | FUEL_CONTROLLED | FUEL_CONTROLLED |
| t=130s | 662.3 kW | 336.1 kW | 4.2% | 6.5% | VCB | ILV_LATENT |
| t=160s | 959.3 kW | 79.9 kW | 0.08% | 6.6% | VCB | VCB |
| t=180s | **1142.2 kW** | **32.8 kW** | 0.08% | 8.5% | VCB | VCB |

- **Próximo caso pendiente**: `v5_ventilation_hrr_spike` (95 findings, HRR zombie 3245 kW). Requiere actualizar `threshold_metrics` antes de activar M4 — el spike está calibrado sobre el bug ILV.

### ILV motor — Phase 5 M4: fire_o2_upper_throttle_enabled (2026-06-22)

- **Motor guard `fire_o2_upper_throttle_enabled`** (`pending`) — Nuevo flag en `SimulationEngine` y `CombustionSystem`. Cuando está activo y el two-zone solver elige `o2_lower` como referencia de throttle (modo `plume_lower/blend`) pero `o2_upper` cae bajo el umbral crítico (`fire_o2_upper_throttle_critical=0.10`): reemplaza `o2_ref = minf(room.o2, room.o2_upper)`, forzando el throttle de HRR a respetar la zona superior. Fix de física real (no solo display/régimen).
- **Bug raíz corregido**: el flag se colocó erróneamente en `_sync_auxiliary_services()` (dict de `OxygenExchangeSystem`) en lugar de `_build_room_combustion_context()` (dict leído por `CombustionSystem.step_room_fire()`). Resultado: `CombustionSystem` siempre leía `fire_o2_upper_throttle_enabled=false` en escenarios headless.
- **Unit test 7/7 PASS** (`tools/validate_fire_o2_upper_throttle.gd`): bug secundario en el test era `fire_max_active_s` ausente del contexto (`context.get` usa default 0.0 → extinguía el fuego en step 0). Fix: agregar `"fire_max_active_s": 1800.0` + `"fire_extinction_delay_s": 90.0`.
- **Scenarios**: `fp_ilv_upper_throttle_on.json` / `fp_ilv_upper_throttle_off.json` — verificación before/after con `fire_o2_upper_throttle_enabled` per-caso. Coherence checker: 258 FAIL (throttle OFF) → 0 FAIL/1686 rows (throttle ON).
- **Efecto físico verificado**:

| Tiempo | HRR (OFF) | o2_upper (OFF) | o2_hrr (OFF) | HRR (ON) | o2_upper (ON) | o2_hrr (ON) |
|--------|-----------|----------------|--------------|----------|---------------|-------------|
| t=110s | 459 kW | 6.03% | 0.983 | 299 kW | 7.02% | 0.817 |
| t=120s | 550 kW | 0.08% | 0.971 | 184 kW | 5.08% | 0.612 |
| t=150s | 833 kW | 0.08% | 0.921 | 46 kW | 6.45% | 0.243 |
| t=200s | 1201 kW | 0.08% | 0.883 | (fuego apagado) | — | — |
| t=1400s | 1211 kW | 0.08% | 0.894 | N/A | — | — |

- **Flag scoped per-caso**: default `false`. El motor base no cambia. Baseline 345/350 PASS intacto (sin regresión).
- **EXP-1 (`cfast_ilv_open_window_repro` + M4, 2026-06-22) — REVERTIDO**: M4 y `fire_o2_canonical_enabled` son mecanismos en competencia. Canonical depleta `o2_lower` a ~13%; M4 sobreescribe con `min(room.o2, o2_upper) ≈ 9%` (más agresivo). Resultado: doble-freno, HRR oscila 100–750 kW vs 972 kW estable. Coherence=0, guardrails intactos, pero ±10% HRR no cumplido. M4 aplica en casos SIN canonical.
- **EXP-2 (`v5_ventilation_hrr_spike` + M4 standalone, 2026-06-22) — NO VIABLE**: M4 funciona correctamente (coherence OFF: 75 findings → M4: 0 findings). Pero el caso mide el spike como `threshold_metric: hrr >= 1000 post-vent`, que es precisamente el HRR zombie permitido por el bug. Con M4: HRR = 58–210 kW (vs 537→3232 kW OFF). El threshold_metric fallaría. El caso **testea comportamiento buggy como feature esperada**. Misma lógica aplica a todos los casos existentes con ventanas exteriores y `threshold_metrics` calibradas pre-M4.
- **CAMPAÑA M4 CERRADA (2026-06-22)**: activación en casos existentes bloqueada. M4 queda como fix gated (default `false`). Ruta futura: (A) nuevos escenarios ILV/FP con M4 como física correcta, o (B) pasada coordinada de validación que actualice los `threshold_metrics` afectados (~8-10 casos con ventana exterior). EXP-3 (`cfast_r0_window_360`) abortado — mismo patrón que EXP-2.

### ILV motor — Opción A + Opción C (en curso 2026-06-22)

- **Opción A — classifier fix** (`9e23f9e`) — `CombustionRegimeClassifier` rule 7.5: when `o2_upper < 5%` AND `hrr_kw >= 100`, reclassify as `VENTILATION_CONTROLLED_BURNING` regardless of `o2_hrr_factor`. Display/regime now reflects upper-zone starvation in open-room ILV. No HRR/O₂/physics change. Test 11/11 PASS.
- **Opción C — canonical O₂ routing per-case** (`56faa6e`) — `fire_o2_canonical_enabled: true` in `cfast_ilv_open_window_repro.json` only. Routes combustion O₂ consumption to `o2_lower` (the zone CombustionSystem reads for throttle), making HRR physically self-consistent with the two-zone plume path. Result: `o2_lower` depletes 19.7% → 13%, `o2_hrr_factor` drops 0.894 → 0.278, HRR throttles 1211 → 972 kW, `o2_upper` stabilises at ~7.9% via bidirectional entrainment. ILV coherence checker: 0 findings (was 258). Baseline 345/350 unaffected — flag scoped to repro case only.
- **FP/QA ILV base scenario** (`pending`) — `sim/validation/cases/fp_ilv_open_partial_window.json`: dedicated headless FP scenario for open-window ILV with `fire_o2_canonical_enabled: true` per-case. Verified: coherence checker 0/1686 findings, HRR throttled to ~972 kW at steady state (by design — canonical routing without secondary gain; manual QA target of ~3100 kW requires a future stress variant with `fire_secondary_hrr_gain_kw`). No motor defaults changed.

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
