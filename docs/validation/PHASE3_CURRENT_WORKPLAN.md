# Phase 3+ current workplan

Date: 2026-07-25

## Current baseline

- Guardrails: 10/10 PASS.
- Physics coherence: 0 FAIL.
- ILV suite: 0 FAIL.
- Default local runtime and test executable: Godot `4.7.1` console.
- Required validation: 347/353 PASS.
- Active VALID_GAP: 6 checks.
  - Group A: `cfast_r0_window_360` x3.
  - Group C: `cfast_corridor_chain` x3.

This phase starts from a clean rule: no more per-case tuning for Groups A/C
and no more local pressure/projection fixes. The remaining gaps require a
canonical two-zone mass/energy/O2/species transaction.

## Documents of record

- Architecture: `docs/validation/PHASE3_CANONICAL_TWO_ZONE_ARCHITECTURE.md`
- F0 diagnostics: `docs/validation/PHASE3_F0_ZONE_DIAGNOSTICS.md`
- F2.2a pressure diagnosis: `docs/validation/PHASE3_F22A_PRESSURE_VENT_DIAGNOSIS.md`
- HVAC deferral decision: `docs/validation/PHASE3_HVAC_DEFERRED_DECISION.md`
- F3.0k cross-path audit: `docs/validation/PHASE3_F30K_CROSS_PATH_AUDIT.md`
- F3.0k.1a semantic claims: `docs/validation/PHASE3_F30K1A_SEMANTIC_OWNERSHIP.md`
- F3.0k.1b passive arbitration: `docs/validation/PHASE3_F30K1B_PASSIVE_ARBITRATION.md`
- F3.0k.1c atomic bundle: `docs/validation/PHASE3_F30K1C_ATOMIC_BUNDLE.md`
- F3.0k.1d direct doorway bundle: `docs/validation/PHASE3_F30K1D_DIRECT_DOORWAY_ATOMIC.md`
- F3.0k.1e parcel lifecycle: `docs/validation/PHASE3_F30K1E_DELAYED_PARCEL_ATOMIC.md`
- F3.0k.1f immediate transport audit: `docs/validation/PHASE3_F30K1F_IMMEDIATE_TRANSPORT_AUDIT.md`
- F3.0k.1g vertical transport audit: `docs/validation/PHASE3_F30K1G_VERTICAL_TRANSPORT_AUDIT.md`
- F3.1 selected-O2 extinction: `docs/validation/PHASE3_F31_SELECTED_O2_EXTINCTION.md`
- F3.1a O2 authority diagnosis: `docs/validation/PHASE3_F31A_COMBUSTION_O2_AUTHORITY.md`
- F3.1b effective-boundary scope diagnosis: `docs/validation/PHASE3_F31B_EFFECTIVE_BOUNDARY_SCOPE.md`
- F3.1c single-room ownership: `docs/validation/PHASE3_F31C_SINGLE_ROOM_THERMAL_OWNERSHIP.md`
- F3.1d projection/reconcile trace: `docs/validation/PHASE3_F31D_LOWER_PROJECTION_RECONCILE.md`
- F3.1e thermodynamic closure: `docs/validation/PHASE3_F31E_THERMODYNAMIC_CLOSURE.md`
- F3.2a exterior boundary shadow: `docs/validation/PHASE3_F32A_EXTERIOR_BOUNDARY_SHADOW.md`
- F3.2b0 persistent shadow: `docs/validation/PHASE3_F32B_PERSISTENT_SHADOW.md`
- F3.2b1 combustion transaction: `docs/validation/PHASE3_F32B1_COMBUSTION_TRANSACTION.md`
- F3.2b2 pressure relaxation: `docs/validation/PHASE3_F32B2_PRESSURE_RELAXATION.md`
- F3.2b3 canonical plume: `docs/validation/PHASE3_F32B3_CANONICAL_PLUME.md`
- F3.2b4 pressure equivalence: `docs/validation/PHASE3_F32B4_PRESSURE_EQUIVALENCE.md`
- F3.2b5a inter-zone heat: `docs/validation/PHASE3_F32B5A_INTERZONE_HEAT.md`
- F3.2b5b wall/ambient energy: `docs/validation/PHASE3_F32B5B_WALL_AMBIENT_ENERGY.md`
- F3.2b5c equivalence diagnosis: `docs/validation/PHASE3_F32B5C_EQUIVALENCE.md`
- F3.2b6 exterior counterflow: `docs/validation/PHASE3_F32B6_EXTERIOR_COUNTERFLOW.md`
- F3.2b7 post-opening coupling: `docs/validation/PHASE3_F32B7_POST_OPENING_COUPLING.md`
- F3.3a interior-opening shadow: `docs/validation/PHASE3_F33A_INTERIOR_OPENING_SHADOW.md`
- F3.3b signed interior-pressure shadow: `docs/validation/PHASE3_F33B_INTERIOR_PRESSURE_SHADOW.md`
- F3.3c late-enthalpy audit: `docs/validation/PHASE3_F33C_LATE_ENTHALPY_AUDIT.md`
- F3.3c1 enthalpy ledger: `docs/validation/PHASE3_F33C1_ENTHALPY_RESIDENCE_LEDGER.md`
- F3.3d CFAST correspondence: `docs/validation/PHASE3_F33D_CFAST_SOURCE_BOUNDARY_CORRESPONDENCE.md`
- F3.3d1 mass ledger: `docs/validation/PHASE3_F33D1_MASS_RESIDENCE_LEDGER.md`
- F3.3d2 source-term experiment: `docs/validation/PHASE3_F33D2_PLUME_SOURCE_TERM_EXPERIMENT.md`
- F3.3e coupled Qc design: `docs/validation/PHASE3_F33E_COUPLED_QC_DESIGN.md`
- F3.3e1 coupled Qc experiment: `docs/validation/PHASE3_F33E1_COUPLED_QC_EXPERIMENT.md`
- F3.3f lower-zone renewal correspondence: `docs/validation/PHASE3_F33F_LOWER_RENEWAL_CORRESPONDENCE.md`
- F3.3f1 destination-routing design: `docs/validation/PHASE3_F33F1_DESTINATION_ROUTING_DESIGN.md`
- F3.3f2 destination-routing experiment: `docs/validation/PHASE3_F33F2_DESTINATION_ROUTING_EXPERIMENT.md`
- F3.3g doorway-jet entrainment design: `docs/validation/PHASE3_F33G_DOORWAY_JET_ENTRAINMENT_DESIGN.md`
- F3.3g1 doorway-jet integration experiment: `docs/validation/PHASE3_F33G1_DOORWAY_JET_INTEGRATION_EXPERIMENT.md`
- F3.3h CFAST doorway-flow semantics: `docs/validation/PHASE3_F33H_CFAST_DOORWAY_FLOW_SEMANTICS.md`
- F3.3h1 buoyancy-routing design: `docs/validation/PHASE3_F33H1_BUOYANCY_ROUTING_DESIGN.md`
- F3.3h2 runtime experiment: `docs/validation/PHASE3_F33H2_BUOYANCY_RUNTIME_EXPERIMENT.md`
- F3.3i input correspondence: `docs/validation/PHASE3_F33I_INPUT_CORRESPONDENCE_AUDIT.md`
- F3.3j Hall residence audit: `docs/validation/PHASE3_F33J_HALL_RESIDENCE_AUDIT.md`
- F3.3k connection audit: `docs/validation/PHASE3_F33K_CONNECTION_RESIDENCE_AUDIT.md`
- F3.3l scenario equivalence: `docs/validation/PHASE3_F33L_SCENARIO_EQUIVALENCE.md`
- F3.3m source correspondence: `docs/validation/PHASE3_F33M_SOURCE_CORRESPONDENCE.md`
- F3.3n buoyancy runtime: `docs/validation/PHASE3_F33N_BUOYANCY_RUNTIME.md`
- F3.3o radiative-fraction experiment: `docs/validation/PHASE3_F33O_RADIATIVE_FRACTION_EXPERIMENT.md`
- F3.3p coupled-Qc re-entry design: `docs/validation/PHASE3_F33P_COUPLED_QC_REENTRY_DESIGN.md`
- F3.3p1 coupled-Qc experiment: `docs/validation/PHASE3_F33P1_COUPLED_QC_EXPERIMENT.md`
- F3.3q boundary-energy correspondence: `docs/validation/PHASE3_F33Q_BOUNDARY_ENERGY_CORRESPONDENCE.md`
- F3.3r0 material correspondence: `docs/validation/PHASE3_F33R0_MATERIAL_CORRESPONDENCE.md`
- F3.3r1 boundary partition: `docs/validation/PHASE3_F33R1_BOUNDARY_PARTITION_AUDIT.md`
- F3.3r2 multi-surface shadow design: `docs/validation/PHASE3_F33R2_MULTISURFACE_SHADOW_DESIGN.md`
- F3.3r2a pure surface solver: `docs/validation/PHASE3_F33R2A_SURFACE_SOLVER.md`
- F3.3r2b state/radiation transaction: `docs/validation/PHASE3_F33R2B_MULTISURFACE_TRANSACTION.md`
- F3.3r2b1 gas/surface exchange: `docs/validation/PHASE3_F33R2B1_GAS_SURFACE_EXCHANGE.md`
- Gap inventory: `docs/validation/GAPS_INVENTORY.md`
- Handoff: `docs/HANDOFF_CURRENT_STATE.md`

## Closed routes

| Route | Decision | Reason |
|---|---|---|
| JSON/per-case tuning for Group A/C | Closed | Sweeps and experiments did not close both target checks without breaking guards. |
| F2.1 ledger-aware projection | NO-GO | Lower gas collapsed and volume closure exploded when projection became honest. |
| Local pressure-vent patch | NO-GO | Pressure/vent path mixes gas mass, smoke stock and EOS backfill; fixing one term locally is unsafe. |
| Retrying `project_room_state()` compensation | Closed | It hides mass creation/deletion instead of giving ownership to physical fluxes. |

## Active route

F3.0 shadow canonical two-zone state through F3.0j are implemented. F3.0k
completed the non-HVAC cross-path audit with a NO-GO for authority. Direct
doorway transport, delayed parcels and immediate horizontal background/
counterflow, legacy vertical-opening transport and all GES exterior purge
paths plus ThermalSystem hot-gas transport for CO/CO2/HCN now have separate
contracts, and those contracts close exactly. The remaining blocker is
incomplete mass/energy/O2 ownership plus semantic overlap between Thermal and
GES legacy paths.
F3.0k.1a provides a stable pre-mutation connection key and proves the overlap
at runtime. F3.0k.1b now selects provisional shadow owners and suppresses the
duplicate Thermal opening-species request only inside the passive shadow.
It also records the exact legacy CO sink/CO2 source for CO oxidation.

F3.0k.1c now provides an ordered atomic route bundle with one fraction limited
by aggregate source-zone gas mass, energy, O2 and species. CO oxidation is the
first migrated producer and has explicit shadow O2 chemistry with zero carbon
and oxygen residual. Legacy physics remains unchanged.

F3.0k.1d migrates the exact direct two-zone doorway family. Its air mass,
zonal enthalpy, O2 and species now share one atomic accepted fraction, while
legacy physics remains unchanged.

F3.0k.1e gives delayed parcels one persistent atomic lifecycle. Gas mass,
enthalpy, signed O2, smoke and all transported toxic species share the carve
fraction through flight and terminal resolution. OFF/ON legacy output is
identical and lifecycle conservation closes. Remaining unresolved scope is
background/counterflow, vertical and exterior producers.

F3.0k.1f audited background/counterflow and returned NO-GO for a complete
atomic migration. Their species, O2 and enthalpy terms do not share one
direction or activation rule, and no legacy gas-mass mutation exists for the
gross counterflow.

F3.0k.1g confirms that active two-zone vertical openings already reuse the
F3.0k.1d doorway bundle. The legacy vertical net/directed fallbacks remain
species-only because Thermal gas/energy and OES O2 use different solvers,
thresholds and directions. A new complete vertical bundle is NO-GO.

F3.1 delivered the selected-O2 extinction invariant, but sealed state
authority returned NO-GO. F3.1a then proved that OES must debit the same O2
source selected by Combustion. The existing default-OFF canonical-routing flag
removes the upper-O2 zombie and closes O2E1/A3 in the selected controls.

Global activation remains NO-GO. F3.1b proves that the mismatch cannot be
closed by one shared boolean: the legacy systems activate different transport
families, and the two diagnostic cases are not physically sealed. Even a
genuinely closed scratch control reaches mask 7 while `needs_flux_owner`
remains 1.

F3.1c gives explicit owners to every exact local thermal term exercised by the
dedicated one-room fixture and to the invalid-lower-zone bulk O2 debit. F3.1d
then traces every projection call and proves that the remaining residual is a
legacy state-definition mutation, not missing physical transport. Fixed
reference-pressure EOS projection overwrites lower inventory; repeated calls
geometrically backfill ambient mass.

F3.1e now provides a passive pure thermodynamic closure. Canonical mass and
energy remain authoritative; temperature, shared pressure, zone volumes and
interface are derived without writing legacy state. Exact post-step closure
holds in all three one-room controls, while legacy projection divergence stays
explicit telemetry.

F3.2a now provides one default-OFF exterior pressure/leakage transaction. It
uses the F3.1e state after explicit internal shadow fluxes, transports gas,
energy, O2 and species atomically and suppresses only the duplicate legacy
pressure owner inside shadow. The passive contract closes exactly and legacy
physics is invariant, but Group A does not move: its O2 checks precede the open
window and canonical state is reseeded from legacy each timestep.

F3.2b0 now persists the canonical state and proves exact continuity, but its
open-loop combustion candidate is not authoritative. Group A improves at
240 s, then over-depletes and develops nonphysical pressure because HRR, plume
and species still come from legacy physics.

F3.2b1 now closes that loop in the passive shadow. One canonical pre-step O2
decision governs HRR, fuel, the O2 sink, pollutant sources, convective heat and
plume transport. All three Group A O2 checks pass in shadow and transaction
residuals close exactly. Authority remains NO-GO because the lower canonical
zone collapses before the window opens and the opening transient reaches about
`+26.9 kPa`. That result defined F3.2b2 as exterior-opening pressure
relaxation plus a conservative degenerate-zone transition.

F3.2b2 now prevents the exterior orifice step from crossing ambient pressure.
The exact EOS equilibrium fraction scales the complete atomic boundary bundle,
and real exterior inflow can recreate lower from an upper-only state. The old
`+26.9 kPa` opening spike becomes approximately zero, Group A stays 3/3 PASS
in shadow and legacy output remains identical. Authority is still NO-GO: the
pre-opening canonical pressure remains `-1.04..+2.81 kPa`, and lower reaches
the one-zone limit near 160 s. That result defined F3.2b3.

F3.2b3 proves the early one-zone transition is a cross-state plume error. The
legacy plume correlation consumed legacy interface geometry while its mass,
enthalpy and O2 request was applied to canonical zones. A default-OFF pure
preview now uses canonical pre-step thermodynamics. Group A lower remains
`2.48 kg` at 360 s instead of collapsing, all three shadow O2 checks still
pass, volume closure is exact and all 115 legacy columns remain identical.

Authority remains NO-GO. The canonical interface is still above CFAST and the
pressure trajectory remains outside its envelope. Internal plume transfer
cannot set total room pressure because it conserves room mass and energy.
F3.2b4 decomposes canonical EOS pressure into mass and sensible-energy terms.
The apparently close pressure curve is cancellation between large independent
errors: at 160 s SimuFire has about 11.10 kg too much gas and about 3.05 MJ too
little energy relative to CFAST. Radiation, leakage and concrete-wall
experiments do not close pressure, mass, energy and zone temperatures
together.

The binding blocker is another cross-state contract. Thermal loss requests
are calculated from legacy temperatures and masses, then applied to canonical
reservoirs. Canonical lower becomes hotter than upper near 313 s, but the
legacy gradient continues sending heat downward; about 4.63 MJ is requested
after inversion. F3.2b4 is diagnostic GO and authority NO-GO. F3.2b5 must
provide canonical thermal-transfer and wall/ambient previews before pressure
authority or Group A retirement can be reconsidered.

F3.2b5a now replaces the downward legacy shadow request with a pure canonical
pre-step transfer. A reduced-capacity equilibrium cap and one energy-only
atomic bundle eliminate the canonical lower-hotter-than-upper inversion and
close energy conservation exactly. Group A lower-temperature RMSE improves
from about 93 C to 23 C while all three shadow O2 checks remain PASS.

Authority remains NO-GO. Total pressure, mass and energy errors barely move,
and the late canonical lower zone is underheated at about 20-23 C versus
roughly 67 C in CFAST. This is evidence for missing wall/ambient reservoir
ownership, not permission to tune the inter-zone coupling.

F3.2b5b now gives the shadow a separate persistent canonical wall reservoir
and replaces six legacy-derived wall/ambient requests. One atomic energy
bundle plus explicit ambient accounting closes gas-wall and total boundary
residuals exactly. The no-fire equilibrium is exact and all non-shadow output
is invariant. In Group A the lower reservoir retains 49.14 kJ at 360 s instead
of reaching zero, and the three shadow O2 checks remain inside their existing
tolerances.

Authority remains NO-GO. The upper layer is still too cool at 180 s, the lower
layer remains too cool late, and material mass/energy/pressure residuals from
earlier ownership gaps remain. That result defined F3.2b5c as a full
mass/energy/EOS-pressure equivalence audit plus independent controls, with no
thermal-rate tuning before the accounting was complete.

F3.2b5c completes that accounting. The strongest simultaneous equivalence
candidate is `chi_rad=0.35` plus the CFAST leakage area, but it remains
scratch-only. Pressure agreement by itself is still insufficient, and the
lumped concrete-wall candidate is rejected.

F3.2b6 now adds the missing canonical bidirectional exterior opening. A
hydrostatic neutral-plane solve creates equal opposing gross routes while the
existing pressure bundle remains the sole net-mass owner. Mass, energy, O2
and species close exactly, no-fire equilibrium is exact and legacy output is
invariant.

Group A reoxygenation, interface rise and HRR all move in the correct
direction after the window opens, but authority remains NO-GO. By 420 s the
canonical interface overshoots CFAST (`1.574` versus `1.020 m`) while HRR is
still far too low (`490` versus `1280 kW`). The remaining blocker is the
post-opening canonical combustion/O2/plume feedback, not another exterior
flow multiplier.

F3.2b7 now selects lower canonical O2 only while explicit exterior
counterflow is active and binds combustion air to plume transport. Completing
the Heskestad source term inside that opt-in path recovers full HRR and brings
the 420 s interface to `1.084 m` versus `1.020 m` in CFAST, with exact
conservation and invariant legacy output. Late upper O2 remains low and the
370 s HRR response is early, so authority and Group A retirement remain
NO-GO. The mechanism is sufficient to proceed to F3.3 shadow work; it is not
permission to publish the canonical state.

F3.3a now owns horizontal interior-opening transport inside the passive
canonical shadow. A common pre-step snapshot and one globally capped atomic
network bundle move gas, enthalpy, O2 and all seven species independently of
opening order. The exact piecewise hydrostatic integral handles one-zone
receivers and leaves vertical/exterior ownership unchanged. Legacy output is
bit-identical and all building residuals close.

Authority and Group C retirement remain NO-GO. R0 improves strongly at 180 s
but worsens at 600 s, showing that equal-gross buoyant counterflow fixes the
early thin-layer error but cannot supply the signed pressure/enthalpy coupling
needed late. F3.3b is the next target; it must diagnose a canonical network
pressure owner rather than tune the F3.3a exchange rate.

F3.3b now adds that signed component from the same canonical snapshot and
inside the same atomic network bundle. A single network relaxation fraction
prevents connected pressure differences from crossing in one explicit step;
gas, enthalpy, O2 and all seven species remain exactly conservative. Legacy
output and official validation reports remain unchanged.

The Group C hypothesis is rejected. R0 upper temperature moves from F3.3a's
`130.94/102.73 C` at 180/600 s to `125.70/97.39 C`, farther from both CFAST
targets. Signed transport removes more upper enthalpy, so neither a doorway
multiplier nor additional pressure relief is justified. F3.3b is diagnostic
shadow GO, but authority and Group C retirement remain NO-GO. F3.3c must audit
late upper-energy residence term by term before another motor mechanism is
designed.

F3.3c has now established that the late deficit is energy-residence dominated.
At 600 s F3.3b retains 94.8% of the CFAST upper mass but only 49.3% of its
upper sensible energy. A CFAST-aligned `chi_rad=0.35` scratch control fixes the
late temperature but recreates a severe early overshoot, so scalar case tuning
is rejected. Exact cause attribution remains blocked because several accepted
energy routes were exported only as current-step values. F3.3c1 now supplies
the missing exact ledger. In Group C all 527 shared OFF/ON columns are
identical and every zone/room/building residual is `0.0 kJ`. R0 accepts
40.711 MJ combustion heat through 600 s and exports most of it through gross
interior opening flow, ambient and wall paths. Group A closes equally cleanly.

F3.3d has now compared the exact canonical source and sink families against
time-resolved CFAST convective HRR, signed doorway-slab enthalpy and layer
energy. SimuFire's source is only 34-44% of CFAST because the case retains 30%
convective heat versus CFAST's 65%, with additional late O2 throttling. Wall
and doorway losses are lower than CFAST in absolute terms and are not the
primary late-energy cause.

The source mismatch cannot be corrected alone. In the existing
`chi_rad=0.35` control, 180 s upper energy is within 3% of CFAST but upper mass
is 32% low and the interface is 0.37 m too high, producing an early thermal
overshoot. Its late temperature match also hides roughly 24% deficits in both
upper energy and mass. F3.3d therefore selects upper/lower mass partition as
the next owner, while keeping radiation, wall and doorway coefficient changes
at NO-GO.

F3.3d1 now supplies that default-OFF cumulative accepted mass-residence ledger.
It distinguishes plume, interior/exterior opening, parcel, collapse/reconcile,
legacy and unclassified routes. Group C preserves all 595 shared columns and
every upper/lower/room/building residual is exactly `0.0 kg`.

The ledger selects the next owner. Accepted SimuFire plume mass is only 64-72%
of CFAST across the three common windows, while the `chi_rad=0.35` source
control changes plume mass by less than 2%. Early net doorway mass is already
close to CFAST. Late signed-pressure lower outflow and exterior net inflow are
secondary churn, not permission to retune opening coefficients.

F3.3d2 tested the missing Heskestad source term as the sole plume change. It
improved plume mass, upper/lower mass and interface while preserving exact
closure, but it worsened upper temperature at both 180 s and 590 s. The
candidate is fully rolled back. This proves that the convective-energy and
plume-mass deficits cannot be corrected independently.

F3.3e has completed that design. The current preview uses flame length where
Heskestad requires a virtual origin and then applies one cube-root scale to
both the cubic-root height term and the linear source term. With CFAST's
physical `D=0.6196 m`, `Qc=195 kW` and exported interface, the corrected
equation predicts its plume flow within 2.3% at 180/300/590 s without tuning.

The selected contract is accepted total HRR -> effective `chi_rad` -> one
accepted `Qc`. That same value drives `Qc*dt` upper energy and both Heskestad
plume terms before atomic inventory limiting. The late 300-590 s source still
has a separate O2/HRR deficit (41.23 MJ available at 65% convective versus
CFAST 56.55 MJ), which the plume contract is forbidden to hide.

F3.3e1 implemented that contract and passed its 180 s gate. The first CFAST
window nearly closed in both Qc energy and plume mass, and all three state
metrics moved toward CFAST with exact ledgers. The 600 s run is nevertheless
NO-GO: lower gas and interface collapse to zero by 590 s while upper mass
overshoots CFAST by 16.12 kg. All F3.3e1 runtime code was rolled back.

F3.3f has now completed that comparison. The missing renewal is not a gross
flow-magnitude deficit. In the late window SimuFire accepts about `223.49 kg`
of interior opening plus pressure inflow versus CFAST `168.39 kg`. The zone
split is inverted: SimuFire deposits only `51.60 kg` in lower and `171.89 kg`
in upper, while CFAST deposits `166.82 kg` in lower and `1.58 kg` in upper.

The binding owner is the destination midpoint-zone assignment shared by
F3.3a and F3.3b. Once the receiver interface falls, cool incoming slabs are
classified as upper; lower renewal falls, plume drains lower further and the
same rule routes even more inflow upper. Conservation remains exact, so a
flow multiplier or pressure gain would amplify the wrong route.

F3.3f1 has now completed the design and direct-fixture gate. The optional pure
selector preserves direct source-layer identity: lower source enters lower and
upper source enters upper. This matches CFAST's separation between direct
vent transport and a distinct doorway-jet entrainment term. Existing geometric
destination routing remains the exact default.

The candidate changes no flow magnitude, pressure integration, neutral plane,
source payload or atomic acceptance. It has no Engine, CLI, CSV or case wiring.
Direct hot/cold, one-zone, pressure, conservation and opening-order fixtures
pass, as do all 432 Phase 3 tests.

F3.3f2 temporarily wired that selector and stopped at 180 s. OFF remained
byte-identical and all ledgers closed exactly. ON improved R0 lower inflow
from `46.143` to `54.555 kg` with nearly unchanged total flow, but upper inflow
collapsed from `7.516` to `0.004 kg`. Upper mass and interface both moved away
from CFAST. The runtime wiring was fully removed and no 300/590 s run was made.

F3.3g completed the pure Poreh contract. F3.3g1 then preserved each opening
slab and tested source-preserving direct transport plus separate receiver-side
mixing at the 180 s Group C STOP. The mechanism remained exactly conservative,
but the cool `upper -> lower` branch dominated and upper mass/interface moved
away from CFAST. Runtime wiring was removed and no longer run was made.

F3.3h has closed the source-to-output correspondence. CFAST removes a slab
from its geometric source zone, splits direct receiver deposition by source
temperature versus receiver layer temperatures, and applies Poreh as a
separate receiver-internal transfer. Published upper/lower vent flows contain
the direct term only; the ODE contains direct plus Poreh.

F3.3h1 now provides that pure/default-false CFAST `flogo` temperature split.
Source removal, gross flow, pressure, payload and Poreh ownership are
unchanged; exact split, conservation and order fixtures pass.

F3.3h2 is now the current target. Temporarily expose the tested internal
candidate with the full F3.3b stack and both residence ledgers, prove OFF byte
identity, run Group C only to 180 s and compare direct flow and Poreh/zone
evolution in their separate CFAST conventions. Remove runtime wiring after the
STOP decision.

## Binding priority decision: HVAC last

HVAC is not part of the remaining F3.0 shadow sequence. It stays on the legacy
path until its behavior has been redesigned and approved. The canonical route
may advance using HVAC-disabled cases, but all closure claims must be labelled
non-HVAC and existing HVAC findings must remain visible.

The revised order is:

1. F3.0j ThermalSystem species transport. Completed.
2. F3.0k non-HVAC cross-path conservation audit. Completed NO-GO.
3. F3.0k.1a semantic claim telemetry. Completed, passive GO.
4. F3.0k.1b passive arbitration and CO-oxidation compatibility. Completed, partial GO.
5. F3.0k.1c atomic multi-zone bundle and explicit O2 chemistry. Completed, partial GO.
6. F3.0k.1d direct doorway atomic producer. Completed, passive GO.
7. F3.0k.1e delayed parcel atomic lifecycle. Completed, passive GO.
8. F3.0k.1f horizontal background/counterflow audit. Completed NO-GO.
9. F3.0k.1g vertical net/directed contract audit. Completed NO-GO; active two-zone path reuses F3.0k.1d.
10. F3.1 selected-O2 extinction guard. Completed GO; sealed state authority NO-GO.
11. F3.1a sealed/two-zone combustion O2-source authority diagnosis. Completed; semantic GO, global authority NO-GO.
12. F3.1b effective-boundary/scope contract diagnosis. Completed NO-GO before motor code.
13. F3.1c canonical one-room fixture and remaining thermal ownership. Completed, partial GO.
14. F3.1d lower-zone EOS projection/reconcile diagnosis. Completed, diagnostic GO / authority NO-GO.
15. F3.1e pure canonical thermodynamic closure. Completed, passive GO / authority NO-GO.
16. F3.2a passive exterior pressure/leakage contract. Implemented; STOP gate recommends passive GO / authority and Group A NO-GO.
17. F3.2b0 persistent canonical continuity and passive O2 candidate. Implemented; persistence GO / authority NO-GO.
18. F3.2b1 closed combustion/plume shadow transaction. Implemented; passive mechanism GO / authority NO-GO, Group A shadow 3/3 PASS.
19. F3.2b2 canonical exterior-opening pressure relaxation and degenerate-zone transition. Implemented; passive mechanism GO / authority NO-GO.
20. F3.2b3 canonical plume geometry and one-zone residence. Implemented; passive mechanism GO / authority NO-GO.
21. F3.2b4 canonical pressure source/boundary equivalence. Completed; diagnostic GO / authority NO-GO.
22. F3.2b5a canonical inter-zone heat transfer. Implemented; mechanism GO / authority NO-GO.
23. F3.2b5b canonical wall/ambient energy ownership. Implemented; mechanism GO / authority NO-GO.
24. F3.2b5c mass/energy/pressure equivalence and independent controls. Completed; diagnostic GO / authority NO-GO.
25. F3.2b6 canonical bidirectional exterior opening. Implemented; shadow mechanism GO / authority NO-GO.
26. F3.2b7 canonical post-opening combustion/O2/plume feedback. Implemented; shadow mechanism GO / authority NO-GO.
27. F3.3a horizontal interior-opening shadow. Implemented; mechanism GO / authority and Group C NO-GO.
28. F3.3b signed canonical inter-room pressure coupling. Implemented; diagnostic shadow GO / authority and Group C NO-GO.
29. F3.3c Group C late-enthalpy residence audit. Completed diagnostic GO; energy-residence dominance confirmed.
30. F3.3c1 cumulative accepted-route enthalpy ledger. Implemented; exact closure and legacy invariance verified, default OFF.
31. F3.3d CFAST source/boundary correspondence audit. Completed diagnostic GO; source mismatch confirmed, sink-only fixes rejected, mass partition selected.
32. F3.3d1 cumulative accepted-route mass-residence ledger. Implemented; exact closure and legacy invariance verified, default OFF.
33. F3.3d2 canonical plume source-term experiment. Completed NO-GO and fully rolled back; mass improved but both temperature checkpoints regressed.
34. F3.3e coupled convective-source/plume Qc contract. Design completed; formula/authority GO, no runtime code.
35. F3.3e1 default-OFF coupled Qc runtime experiment. NO-GO and rolled back after lower-zone collapse at 590 s.
36. F3.3f lower-zone renewal/doorway-routing correspondence. Completed diagnostic GO; destination routing selected, flow magnitude rejected.
37. F3.3f1 source-preserving destination-routing contract. Design/direct fixture GO; no runtime wiring.
38. F3.3f2 default-OFF destination-routing runtime experiment. Completed NO-GO at 180 s; runtime wiring removed.
39. F3.3g receiver-side doorway-jet entrainment contract. Design/direct fixture GO.
40. F3.3g1 per-slab runtime integration. Completed NO-GO at 180 s; runtime surface removed.
41. F3.3h CFAST doorway-flow source-to-output correspondence. Completed diagnostic GO.
42. F3.3h1 pure CFAST buoyancy-routing contract. Design/direct fixture GO.
43. F3.3h2 default-OFF 180 s runtime experiment. Current target.
44. F3.4 remaining non-HVAC species, suppression and FED.
45. HVAC-R0 redesign specification.
46. F3.5 HVAC canonical integration as the last subsystem.
47. F3.6 final corpus promotion and legacy retirement.

Do not change this order from an implementation prompt. Re-prioritizing HVAC
requires an explicit planning decision and synchronized documentation updates.

The first implementation must be default OFF and read-only with respect to
legacy physics. It should build a shadow state from:

1. A pre-step snapshot.
2. Explicit flux requests.
3. One transaction applied exactly once.
4. Residuals against the legacy post-step state.

No request may be derived by observing a mutation after it already happened.
That would make the ledger circular.

### F3.0 delivered

- New `Phase3ZoneMassSystem.gd` with immutable request identity and cause.
- Pre-step shadow snapshot for mass, energy, O2 and CO/CO2/HCN by zone.
- Proportional inventory limiting, rejected-mass telemetry and duplicate-id
  detection.
- Ten opt-in CSV fields; legacy schema and values remain unchanged when OFF.
- No authoritative request adapters yet. `needs_flux_owner` is the expected
  signal until a subsystem provides a pre-mutation physical output.

## F3.0a delivered

- Pure preview plus exact apply for lower-to-upper plume transfer.
- Request carries gas mass, enthalpy and O2 under one accepted fraction.
- Adapter is shadow-only and restricted to rooms without active openings.
- Zero-O2 flaming is visible but remains a legacy motor debt.
- Legacy outputs are invariant OFF and ON.

## F3.0b minimum scope

1. Produce a passive combustion result before any consumer mutates zonal state.
2. Assign exactly one owner each for convective heat, O2 sink and species.
3. Reconcile ordering between CombustionSystem, OxygenExchangeSystem and
   ThermalSystem without reading post-mutation deltas.
4. Start with energy only if O2/species cannot yet share a safe contract; do
   not present partial ownership as full combustion closure.

## F3.0b delivered

- `ThermalSystem` emits the exact convective-energy value it already applies,
  before mutating `upper_energy_kj`; Engine performs translation only.
- The request is exterior-to-upper, has zero gas mass, and owns no O2 or
  species. `phase3_shadow_combustion_owned_mask=1` means energy only
  (`energy=1`, `O2=2`, `species=4`).
- The adapter remains restricted to rooms without active openings and is
  shadow-only/default OFF.
- O2 and species were deliberately deferred: combustion selects yields and O2
  references, while OES owns the actual O2 mutation. Reading either after the
  step would make the ledger circular.
- A 60 s OFF/ON control had 42 rows, 115 shared legacy columns and zero value
  differences. The ON run had two owned causes, zero rejected requests and
  zero duplicate owners.

## F3.0c delivered

- `OxygenExchangeSystem` owns the accepted upper, explicit-lower and
  plume-lower O2 removals. Each result is calculated from the same before/after
  fractions used by legacy and is recorded before assignment.
- Requests are zone-to-exterior, O2-only. Engine translates the result without
  reading HRR, Thornton accumulators or post-step deltas.
- The bulk O2 path remains deliberately unowned because it has no canonical
  upper/lower split. In legacy modes that apply bulk plus upper depletion, the
  zonal request is partial and the remaining shadow residual stays visible.
- `phase3_shadow_combustion_owned_mask` is a true bit mask: energy=1,
  zonal O2=2, species=4.
- Runtime OFF/ON retained 42 rows and 115 identical legacy columns. The sealed
  control reached mask 3 with zero rejected or duplicate requests. The zombie
  ILV control retained all 7 zero-O2 flame hits.

## F3.0d delivered

- `CombustionSystem` emits one result after the carbon clamp and before species
  writes. Exact totals preserve legacy arithmetic; upper/lower maps define the
  canonical zonal source without creating a second request.
- CO follows the Phase 2G split. CO2 and HCN enter upper. The CO2 tracer,
  irritants and smoke remain outside this contract.
- Engine translates results only. Pool/backdraft energy already feeds the
  accepted generation values upstream, so it is not added again.
- OFF remained identical to F3.0c and ON changed no legacy value across 42 rows
  and 115 columns. A VC control reached ownership mask 7 with zero duplicates;
  the zombie-ILV control retained all 7 known hits.

## F3.0e delivered

- Ownership is limited to the immediate canonical two-zone opening path.
  GasExchangeSystem computes one `doorway_species_direct` object with explicit
  source/destination zones, records it pre-mutation and applies the same object
  to legacy CO/CO2/HCN delta dictionaries.
- Engine performs translation only. It contains no opening-flow, concentration,
  headroom, cut-ratio, parcel or net-transport formulas.
- Background/counterflow, exterior purge, HVAC, thermal transport and all
  delayed parcel paths remain unowned and visible through residuals.
- Exact checkpoint/OFF/ON proof: 42 rows, 115 legacy columns, zero differences.
  Two-room, corridor and remote-CO controls had nontrivial requests, zero
  rejected species and zero duplicate ownership. Zombie ILV retained 7 hits.

## F3.0f delivered

- Delayed parcels receive one monotonic identity at carve. That identity
  survives across timesteps and terminates at delivery/refund or cancellation.
- GES emits exact lifecycle events from the values already applied by legacy.
  Total and upper species maps preserve the real CO/CO2/HCN zonal split;
  `Phase3ZoneMassSystem` derives only the complementary lower map.
- The persistent reservoir is not reset by `begin_step`; full simulation reset
  clears GES and shadow together. Engine forwards events without formulas.
- Telemetry reports in-flight CO/CO2/HCN, lifecycle totals, active parcels,
  request rejection, anomalies and conservation residual. OFF schema remains
  at 115 columns; ON has 157 and changes no shared value.
- Two-room, corridor and v4 controls closed exactly. The v4 control exercised
  0.095449 kg of refunds. No control produced rejection, orphan delivery,
  duplicate identity or negative balance.
- Smoke, irritants, O2 and parcel gas/energy remain unowned. This phase is
  passive and does not authorize canonical writes to `RoomModel`.

## F3.0g delivered

- `GasExchangeSystem` records the exact horizontal background deltas before
  writing the legacy dictionaries. Signed net values choose the real source;
  CO carries its upper share while bulk-only CO2/HCN remain lower-zone.
- The no-delay counterflow records both gross directions for CO, CO2 and HCN,
  including each source's upper share. It is not collapsed to a net value and
  cannot overlap the delayed parcel branch.
- Engine forwards events without transport formulas. The shadow component
  splits upper/lower, limits by its own inventory and exports cumulative
  mechanism totals, rejection and per-species conservation.
- OFF/ON proof retained 42 rows and 115 identical legacy columns; ON has 171.
  Background and counterflow residuals were zero in all audited controls.
  Parcel conservation is now also exported separately for CO, CO2 and HCN.
- Small shadow rejection remains intentionally visible while producers outside
  the ledger are unresolved. No legacy state, FED result, baseline or
  tolerance changed. The 7 known zero-O2 flame hits remain visible.
- Vertical-opening exchange, exterior purge, HVAC, thermal transport, smoke,
  irritants and O2 counterflow remain outside ownership.

## F3.0h delivered

- Both legacy vertical helpers emit exact events before their delta writes.
  Net CO is split into independent upper and complementary lower movement, so
  the two zones may travel in opposite room directions without cancellation.
- Directed CO preserves the existing upper/lower split. CO2 and HCN are
  lower-only because neither helper mutates their upper stocks. Smoke,
  irritants and O2 remain explicitly outside this contract.
- The canonical two-zone opening path returns before the legacy vertical
  branch, preventing overlap with F3.0e. Delayed and horizontal paths retain
  their own identities from F3.0f/F3.0g.
- OFF/ON proof retained 12 rows in the short control and 793 rows in the real
  two-storey control, with 115 shared legacy columns and zero differences.
  The real path emitted 2,154 vertical requests with zero rejection,
  duplicate ownership or per-species residual.
- A deterministic Godot harness exercised net and directed branches for CO,
  CO2 and HCN, including one opposite-zone CO direction. A horizontal control
  kept every vertical metric at zero.
- Exterior purge, HVAC, thermal transport, smoke, irritants and O2
  counterflow remain outside ownership.

## F3.0i delivered

- GES owns one explicit room-to-exterior event stream for eight purge
  mechanisms: pressure venting, exterior smoke vent, natural ventilation,
  ACH, outside-open purge, post-fire purge and PPV inlet/exhaust.
- Every event is recorded before the associated legacy stock or delta write.
  Exact total and upper CO/CO2/HCN values are carried; the lower map is the
  bounded complement. No purge mass is inferred from post-step stock.
- Events have per-step identities and mechanism names. The shadow transaction
  reports requested, accepted and rejected mass, upper/lower totals,
  mechanism totals, duplicates and separate species residuals.
- OFF/ON proof retained 150 rows and 163 shared columns with zero differences.
  A real ventilated control closed 1.144611 kg exactly; a sealed control
  emitted zero. PPV closed `requested = applied + rejected` to floating-point
  precision while exposing 0.566436 kg of inventory rejection.
- At the F3.0i checkpoint, HVAC and Thermal species transport remained
  explicitly unowned and could not reuse a GES purge identity. F3.0j has now
  assigned the Thermal owner; HVAC remains deferred until F3.5. Smoke,
  irritants and O2 are also outside the purge phase.

## F3.0j delivered

- `ThermalSystem` emits exact pre-delta events for CO, CO2 and HCN from its
  main doorway hot-gas carry and both background heat-exchange paths.
- Optional Phase 2F CO interlayer mixing has a separate upper-to-lower event.
- The contract preserves different source and destination zonal splits through
  a conservative 2x2 route matrix; it never infers a flux from final stocks.
- Projection/reconcile writes, exterior purge, smoke, irritants and HVAC are
  explicitly excluded.
- A 120 s OFF/ON control retained 78 rows and 115 shared legacy columns with
  zero differences. ON recorded all three species, zero rejection, zero
  duplicates and zero conservation residual.

## STOP gate for F3.0

Required before commit:

- `phase3_canonical_zone_shadow_enabled=false` is bit-identical to HEAD for a representative run.
- CSV schema is unchanged with the flag OFF.
- Shadow mode changes no existing legacy columns.
- No physical state is mutated by the shadow transaction.
- Every request is built from pre-step state or an explicit solver output.
- No parcel, gas mass, O2 or species has duplicate ownership.
- Guardrails PASS.
- Physics suite has 0 FAIL.
- ILV suite has 0 FAIL.
- New focused tests PASS.

## Rollback criteria

Rollback the F3.0 attempt if:

- any default-OFF behavior changes;
- the ledger needs post-mutation deltas to close;
- residuals are hidden by a projection/clamp bucket;
- zero-O2 flaming behavior is reproduced in canonical shadow without being
  visible as a failure signal;
- a subsystem emits a request from a separately reconstructed value instead of
  reusing the exact pre-mutation result applied to legacy.

## F3.0k audit decision

The eight-case runtime matrix closed every implemented species contract with
zero residual and no duplicate request identities, but every case retained
`phase3_shadow_needs_flux_owner_flag=1`. Source audit found unowned gas/energy
and O2 paths, unowned CO oxidation and semantic overlap between Thermal and
GES doorway/background mechanisms. See `PHASE3_F30K_CROSS_PATH_AUDIT.md`.

## F3.0k.1a delivered

- One step-local semantic key now joins connection, room direction, zonal
  direction and quantity before legacy mutation. Producer, transport family
  and boundary kind remain metadata so parallel owners collide visibly.
- Stable identities cover building openings, exterior purge, room interlayer
  movement and chemical generation. Delayed parcels claim only at creation.
- Eight shadow-only CSV fields report claim/conflict count, quantity mask,
  contested amounts and unknown connection identities.
- Runtime controls report mask 56 (CO + CO2 + HCN) on interior doorway,
  corridor, stairwell, remote-CO and PPV paths. Sealed and exterior-window
  controls report zero conflicts. All controls report zero unknown identity.
- OFF/ON retained 78 rows and 115 identical legacy columns; ON has 245.
- This is passive telemetry only. It does not choose an owner, suppress a
  legacy path or authorize F3.1.

## F3.0k.1b delivered

- Provisional owners are explicit for opening, interlayer, combustion and
  chemical-conversion quantities. Raw conflicts remain visible.
- GES-owned opening CO/CO2/HCN claims suppress the parallel Thermal request
  only inside the shadow transaction. Legacy physical writers remain active.
- Accepted, suppressed and unresolved claims have separate counts, masks and
  amounts. Missing gas mass, enthalpy and O2 use unresolved mask 7.
- CO oxidation now emits an exact upper CO sink and lower compatibility CO2
  source before legacy mutation. Carbon closes exactly; the absent legacy O2
  sink remains unresolved.
- Eight runtime controls have zero unresolved multi-producer conflict. The
  OFF/ON pair retained 78 rows and 115 identical legacy columns; ON has 260.
- Complete ownership is NO-GO because one accepted fraction cannot yet bind
  the observed multi-zone gas/energy/O2/species routes. F3.1 is not authorized.

## F3.0k.1c delivered

- Ordered simple requests and atomic bundles now share one shadow transaction
  queue, preserving producer order.
- Each atomic bundle validates every route, aggregates demand by source zone,
  computes one fraction from gas, energy, O2 and species inventory, then
  applies all routes with that fraction.
- CO oxidation now owns an upper CO + O2 reactant route and an upper CO2
  product route. The shadow uses 16/28 kg O2 and 44/28 kg CO2 per kg CO;
  legacy O2 and bulk-only CO2 writes remain unchanged.
- Runtime OFF/ON controls retain all 115 legacy columns with zero differences.
  The eight-case non-HVAC matrix completes, but every transport control still
  reports unresolved mask 7 because its producers have not migrated.
- The valid 120 s oxidation control closes carbon and oxygen exactly. A 300 s
  ON attempt timed out at 282 s, so long-run shadow performance remains a
  watch item.
- F3.1 remains unauthorized. Zero-O2 flaming is still an independent blocker.

## F3.0k.1e delivered

- Delayed parcel creation emits one atomic carve bundle with gas, sensible
  energy, signed O2, smoke and seven transported species.
- The inventory-limited accepted fraction persists in the in-flight reservoir
  and is reused for delivery, refund or terminal cancellation.
- Lifecycle telemetry closes mass, energy, O2 and species independently.
- The 120 s OFF/ON control retained all 115 legacy columns with zero
  differences. Runtime and anomaly gates are clean.
- Commit: `4f718791`.

## F3.0k.1g audit decision

- The active two-zone vertical path already emits the F3.0k.1d doorway atomic
  contract; it does not require a second vertical owner.
- Legacy vertical net/directed helpers own exact species deltas only.
- Their upward species path has no matching legacy gas/enthalpy mutation.
- Their downward O2 expression is a separate bulk mixing correction and is
  not the O2 content of the downward mass flow.
- Thermal doorway/stairwell and OES opening flows remain separate contracts.
- Therefore a new complete legacy vertical bundle is NO-GO.

## F3.3h2 runtime decision

- The temporary default-OFF runtime gate reproduced the exact F3.3d1
  checkpoint OFF: 114 rows, 667 columns and SHA-256
  `6F7FD18D3C451D2AE615D695B066A08F9F593DF5708E864DD50067CECF09ED70`.
- At the mandatory 180 s STOP, R0 direct lower/upper inflow was
  `53.712/0.223 kg` versus CFAST `65.782/3.662 kg`.
- Poreh moved `1.019 kg` from R0 upper to lower. Upper mass and interface
  regressed despite a small upper-temperature improvement.
- All transaction residuals were zero and all 115 legacy columns were
  invariant.
- Decision: runtime candidate NO-GO. No 300/590 s run was made and all
  temporary Engine/CLI/CSV wiring was removed.
- Binding record:
  `PHASE3_F33H2_BUOYANCY_RUNTIME_EXPERIMENT.md`.

## F3.3j Hall residence decision

- The aggregate CFAST Hall balance was reconstructed over 0-180 s and compared
  with the exact SimuFire accepted-route mass and enthalpy ledgers.
- F3.3k later found that the gross direct comparison used non-equivalent
  topologies: five active SimuFire Hall connections versus two in CFAST.
  The `138.650 kg` result remains valid for the configured six-room case but
  is not a CFAST correspondence result.
- SimuFire's direct net sensible enthalpy is only `1.654 MJ` versus CFAST
  `4.253 MJ`, or `38.88%`.
- SimuFire direct upper net mass is `-9.015 kg` versus CFAST `+12.993 kg`.
  The separate Poreh route moves `20.734 kg` lower-to-upper and nearly masks
  that `22.008 kg` routing error without adding room energy.
- Wall, ambient and exterior losses total `0.865 MJ`; they cannot own the
  `2.599 MJ` direct-flow enthalpy deficit.
- Decision: the binding owner is connection-level hot-mass and enthalpy
  transport. Projection/collapse and boundary cooling are secondary.
- No physical code or runtime surface changed.
- Binding record:
  `PHASE3_F33J_HALL_RESIDENCE_AUDIT.md`.

## F3.3k connection audit decision

- A default-OFF per-connection ledger now exports accepted opening/pressure
  mass and enthalpy only to `summary.json`; no CSV or legacy physics changes.
- It exposed a direction-exact override bug in `cfast_corridor_chain.json`.
  Hall-R2 width is not applied, and Kitchen, Bedroom 2 and Bathroom remain
  connected to Hall although CFAST contains no such compartments.
- Equivalent topology reduces SimuFire Hall inflow from `138.650 kg` to
  `88.168 kg`; CFAST receives `128.253 kg`.
- Equivalent-topology net direct Hall enthalpy is `2.275 MJ` versus CFAST
  `4.253 MJ`.
- R0-Hall net gain is `3.581 MJ` versus CFAST `6.302 MJ`. Hall-R2 exports
  less energy than CFAST, so it is not the primary sink.
- The source deficiency combines about `31.5%` low R0-to-Hall mass with
  `98.05 C` source gas versus CFAST `121.29 C`.
- A 600 s legacy scratch control closes the current t=180 failure but exposes
  t=300 and leaves t=600 failing. Group C remains at two gaps.
- Official case and reports remain unchanged. Temporary physical experiment
  wiring was removed.
- Binding record:
  `PHASE3_F33K_CONNECTION_RESIDENCE_AUDIT.md`.

## F3.3l scenario-equivalence decision

- Corrected the direction-exact opening overrides in the official
  `cfast_corridor_chain` case.
- Runtime now has exactly the two CFAST doors. The F3.3k ledger contains only
  `opening:0` (`R0 <-> Hall`) and `opening:2` (`Hall <-> R2`).
- Added the official CSV output path so the CFAST and physics gates consume
  the same run.
- R0 temperature at 180 s closes; temperature at 300 s and O2 upper at 600 s
  become required failures; temperature at 600 s remains failing.
- Expected values and tolerances are unchanged.
- Group C changes from two to three VALID_GAP. Required status becomes
  `347/353 PASS`, 6 VALID_GAP.
- The lower score is accepted because it removes a false scenario match and
  exposes the actual coupled mass/enthalpy/O2 deficit.
- Binding record:
  `PHASE3_F33L_SCENARIO_EQUIVALENCE.md`.

## F3.3m source-correspondence decision

- The five checkpoint runs separate a transient mass error from a persistent
  source-energy error.
- R0-to-Hall gross mass evolves from 54% low at 0-60 s to 10% high at
  300-600 s. A global opening or pressure gain is NO-GO.
- R0 upper mass is close to CFAST after 180 s, but its temperature and total
  sensible energy remain low. At 600 s SimuFire has slightly more upper mass
  and about 46% less room sensible energy.
- Current geometric destination routing sends no R0-to-Hall gas into the Hall
  upper zone. CFAST `flogo` sends 90-100%, and the passive Hall upper zone
  never forms in SimuFire.
- Reverse Hall-to-R0 routing sends too little mass to R0 lower late:
  `122.74 kg` versus CFAST `166.82 kg` over 300-600 s despite comparable gross
  return mass.
- Total fire HRR is close, but the canonical convective source is only
  35-45% of CFAST due to known radiative-fraction and O2-acceptance mapping
  differences.
- No motor, case, report, baseline, tolerance or gap changed.
- Binding record:
  `PHASE3_F33M_SOURCE_CORRESPONDENCE.md`.

## F3.3n buoyancy-runtime decision

- The existing exact CFAST `flogo` receiver split is available behind
  `phase3_cfast_buoyancy_destination_shadow_enabled`, default OFF.
- OFF is byte-identical to F3.3m and ON preserves all 115 legacy columns.
- At 600 s every useful destination fraction moves toward CFAST:
  R0-to-Hall `0 -> 77%` versus `99.7%`, Hall-to-R0 `28.5 -> 14.8%`
  versus `2.3%`, Hall-to-R2 `0 -> 85.1%` versus `99.8%`, and R2-to-Hall
  `0 -> 5.2%` versus `8.3%`.
- Hall and R2 form upper layers without any mass, energy, O2 or species
  residual. R0 lower remains non-degenerate.
- R0 upper temperature improves only `3.5 C` at 600 s and transported
  enthalpy remains well below CFAST. Receiver routing is therefore a
  necessary mechanism, not the remaining thermal fix.
- Decision: mechanism GO, authority and Group C retirement NO-GO.
- Binding record:
  `PHASE3_F33N_BUOYANCY_RUNTIME.md`.

## F3.3o isolated radiative-fraction decision

- A temporary default-OFF candidate changed only shadow convective heat from
  the historical case fraction `0.30` to CFAST `0.65`.
- OFF is byte-identical to F3.3n. ON preserves all 115 legacy columns.
- At 180 s accepted R0 combustion heat increases from `10.996` to
  `23.670 MJ`, while plume transfer is nearly unchanged:
  `72.03 -> 71.20 kg`.
- R0 upper temperature overshoots from `129.4` to `224.2 C` versus CFAST
  `159.8 C`; upper mass regresses from `23.80` to `19.34 kg` versus
  `26.94 kg`.
- Hall and R2 also overheat. All canonical residuals remain exactly zero and
  zero-O2 flame remains zero.
- Decision: physical-correspondence NO-GO. No 600 s run. Temporary helper,
  flag, CLI and test removed.
- Binding record:
  `PHASE3_F33O_RADIATIVE_FRACTION_EXPERIMENT.md`.

## F3.3p1 coupled-Qc runtime decision

- The corrected candidate keeps the CFAST physical pair inside the canonical
  shadow and leaves all 115 legacy columns invariant.
- At 180 s R0 upper/lower mass, lower temperature, interface and plume enter
  their CFAST gates.
- R0 upper temperature overshoots to `200.75 C` versus `159.82 C`, exceeding
  the mandatory error gate by about `9.9 C`.
- Hall and R2 also overheat despite exact mass, energy, O2 and species
  closure.
- The source-energy deficit is largely removed; remaining attribution points
  to boundary-energy storage/loss and signed inter-room enthalpy over time.
- Decision: runtime NO-GO. No 300/600 s run. Temporary runtime surface
  removed.
- Binding record:
  `PHASE3_F33P1_COUPLED_QC_EXPERIMENT.md`.

## F3.3q boundary-energy decision

- CFAST inferred boundary loss is `14.163 MJ` over 0-180 s; the canonical
  shadow records `10.749 MJ`, a `3.414 MJ` deficit.
- Canonical inferred and observed balances agree, so the atomic energy ledger
  is correct.
- The validation case does not map CFAST concrete properties and therefore
  uses the lumped fallback wall path.
- Canonical wall conductance/capacity uses `40.0 m2`, only 48.1% of the
  geometric R0 enclosure (`83.2 m2`).
- A direct ambient decay removes another `4.817 MJ` but is not homologous to
  CFAST surface conduction and must not be tuned to hide the mismatch.
- Decision: diagnostic GO. Motor, authority and Group C retirement remain
  NO-GO.
- Binding record:
  `PHASE3_F33Q_BOUNDARY_ENERGY_CORRESPONDENCE.md`.

## F3.3r0 material-correspondence decision

- Gate 0 reproduced the valid F3.3p1 canonical state exactly across 552
  shared fields.
- Existing room material overrides reduced the 0-180 s boundary shortfall
  from `3.414` to `0.730 MJ`.
- R0 and Hall upper temperatures improved substantially.
- R0/Hall lower zones and R2 upper overcooled late; the single material wall
  reservoir remained far colder than CFAST's separate surface classes.
- Decision: diagnostic GO, runtime/adoption NO-GO. Do not modify the official
  case and do not increase canonical wall area.
- Binding record:
  `PHASE3_F33R0_MATERIAL_CORRESPONDENCE.md`.

## F3.3r1 boundary-partition decision

- The CFAST surface histories imply `26.993 MJ` stored by 180 s.
- Direct combustion radiation owns `13.392 MJ`; the remaining
  `13.601 MJ` gas-driven storage matches the independently inferred
  `14.163 MJ` gas boundary sink within `0.562 MJ`.
- The material shadow instead stores `9.009 MJ`, while direct ambient decay
  bypasses surfaces with `3.796 MJ`.
- The near-matched gas sink and cold wall are therefore consistent: the
  source and storage topology, not another wall coefficient, is incomplete.
- Decision: diagnostic GO. Full-area patch and runtime authority remain
  NO-GO.
- Binding record:
  `PHASE3_F33R1_BOUNDARY_PARTITION_AUDIT.md`.

## F3.3r2 multi-surface shadow design

- The new canonical shadow stores ceiling, upper-wall, lower-wall and floor
  energy independently under a default-OFF flag.
- `Phase3ZoneMassSystem` remains the persistent-state authority; a new pure
  five-node surface solver performs only numerical conduction work.
- Accepted combustion radiation is added to the existing atomic combustion
  contract and routed by deterministic area/emissivity weights.
- Gas convection/radiation, direct fire radiation and surface-to-exterior
  loss remain separate ledger paths.
- Interface movement migrates wall area with the donor nodal energy profile.
- The old lumped wall/ambient path and the new path are mutually exclusive.
- F3.3r2a implements only the pure solver and fixtures. F3.3r2b adds
  state/transaction wiring. F3.3r2c runs 60/120/180 s scratch gates.
- Runtime authority, official case activation and Group C retirement remain
  NO-GO.
- Binding record:
  `PHASE3_F33R2_MULTISURFACE_SHADOW_DESIGN.md`.

## F3.3r2a pure surface-solver decision

- Added a pure five-node implicit finite-volume solver with no runtime caller.
- Immutable surface snapshots and explicit accepted fluxes produce a proposed
  state plus a complete energy residual.
- Direct fire radiation, gas radiation, gas convection and exterior removal
  remain separate fields.
- The 60 s concrete surface response is within `3.0688%` of the analytical
  semi-infinite solution.
- A 10,000-step mixed-flux fixture closes to `5.9642e-8 kJ` cumulative
  residual.
- Decision: numerical GO. Runtime authority and official case activation
  remain NO-GO.
- Binding record:
  `PHASE3_F33R2A_SURFACE_SOLVER.md`.

## F3.3r2b multi-surface transaction decision

- Added default-OFF persistent ceiling, upper-wall, lower-wall and floor
  state without adding a CLI switch or enabling an official case.
- Interface-area migration mixes donor and recipient nodal profiles by area
  and conserves total surface energy in both directions.
- Accepted fire radiation uses the existing combustion atomic fraction and
  is committed to all candidate surfaces exactly once.
- The final radiative source is the exact complement of the Thermal-owned
  accepted convective route, so fire-energy partition closes even when
  existing two-zone/opening modifiers are active.
- Full, partial and rejected direct transactions route 30, 15 and 0 kJ.
- The new owner and F3.2b5b lumped wall owner are mutually exclusive.
- Decision: state/radiation transaction GO. Thermal authority and official
  case activation remain NO-GO.
- Gas/surface convection, gas radiation and exterior surface loss remain
  F3.3r2b1 scope; F3.3r2c correspondence is not authorized yet.
- Binding record:
  `PHASE3_F33R2B_MULTISURFACE_TRANSACTION.md`.

## F3.3r2b1 gas/surface/exterior transaction decision

- Canonical pre-step gas and persistent surface snapshots now feed a pure
  preview; queueing and physical evaluation are separate.
- Signed upper/lower gas exchange is resolved through one atomic bundle.
- The accepted fraction scales convection, gas radiation and exterior
  removal before one four-surface commit combines them with accepted fire
  radiation.
- Full, partial, rejected and reverse transfers close the combined
  gas/surface/exterior energy invariant in the direct fixture.
- The generic API supports explicit per-surface exterior Robin boundaries.
- Runtime exterior exchange remains adiabatic because no authoritative
  enclosure topology exists in `RoomModel`; the missing metadata is exposed
  and no visual geometry is used as physics.
- Decision: transaction GO. Thermal authority, official activation and
  F3.3r2c correspondence remain NO-GO.
- Binding record:
  `PHASE3_F33R2B1_GAS_SURFACE_EXCHANGE.md`.

## Next prompt target

Design and implement F3.3r2b2 explicit enclosure boundary topology under the
existing default-OFF multi-surface flag. Define physical per-surface exterior,
inter-room and adiabatic fractions without reading visual meshes or inventing
fallbacks. Populate the F3.3r2b1 `exterior_by_surface` contract, prove mixed
boundary conservation and preserve OFF output. Do not enable an official
case, run F3.3r2c correspondence, alter reports, expected/tolerances or gaps.
HVAC remains deferred.
