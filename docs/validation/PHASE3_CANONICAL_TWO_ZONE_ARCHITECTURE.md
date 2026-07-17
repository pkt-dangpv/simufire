# Phase 3+ canonical two-zone mass architecture

Date: 2026-07-17

## Decision

Start with **F3.0 shadow canonical state**. Passive F2.2a pressure-vent
diagnostics are accepted as diagnostic baseline work. Do not retry F2.1 and do
not add another local pressure or projection correction first.

The existing `upper_gas_kg`, `lower_gas_kg`, `upper_energy_kj`, and
`lower_energy_kj` fields look canonical, but they are not the sole source of
truth. Thermal, gas, oxygen, HVAC, combustion, delayed parcels, pressure vent,
and final clamps mutate overlapping representations. `project_room_state()`
then reconstructs lower mass from the EOS at reference pressure. That
reconstruction closes volume numerically by creating or deleting physical
mass, which is the common architectural cause exposed by Groups A and C.

F2.2a also proves that a local pressure-vent fix is unsafe while this backfill
contract remains: making the gas purge dimensionally correct merely exposes
the unstable room inventory and collapses the lower zone.

## Ownership

Add a new `Phase3ZoneMassSystem` owned and called by `SimulationEngine`.
`ZoneFireSolver` remains the home for correlations and pure calculations, but
must not own the transaction because flux requests originate in several
systems. `ThermalSystem` must not own it because mass transport, HVAC, oxygen,
and delayed parcels are not thermal implementation details.

The new component has one responsibility: apply one immutable pre-step state
plus a complete set of signed flux requests exactly once per fixed step.

```text
SimulationEngine
  snapshot all rooms and in-flight parcels
  collect physical requests without mutating canonical state
    CombustionSystem -> heat, O2 sink, species source
    ThermalSystem -> plume entrainment, wall/radiation heat
    Opening solver -> upper/lower gas and enthalpy flows
    GasExchangeSystem -> exterior/leakage and parcel requests
    HVACSystem -> supply/return gas, enthalpy and species
    Suppression -> heat/species sinks and steam source
  validate paired/internal requests
  Phase3ZoneMassSystem.apply(snapshot, ledger, dt)
  derive pressure, temperatures, volumes and interface
  publish legacy views
  run FED, detectors and logging
```

No subsystem may mutate canonical zone mass, energy, O2, or species while the
new mode is active. During migration, a subsystem either emits requests or
remains on the legacy path; it never does both.

## Canonical room state

Integrated state:

| Quantity | Representation |
|---|---|
| Upper/lower dry gas | `upper_gas_kg`, `lower_gas_kg` |
| Upper/lower sensible energy | kJ relative to one declared reference temperature |
| O2 upper/lower | kg, not mole fraction |
| CO2, CO, HCN and irritants upper/lower | kg per species and zone |
| Steam/suspended smoke where transported with gas | kg per zone |
| Room pressure | one gauge-pressure state or algebraic result from the pressure solve |
| In-flight parcels | mass/energy/species owned by the building ledger, not either room |

Derived state after the transaction:

| Quantity | Derivation |
|---|---|
| Upper/lower temperature | energy divided by gas mass and heat capacity |
| Upper/lower density | EOS from temperature, pressure and composition |
| Upper/lower volume | mass divided by density |
| Interface height | room geometry and upper volume |
| O2/CO2/CO/HCN ppm | zone species mass, molecular weight and zone gas state |
| Bulk species and bulk O2 | sum of upper and lower inventories |
| `thermal_layer_m` | compatibility view of the canonical interface |

The interface is derived, not independently integrated. Pressure may become an
ODE state when exterior leakage is active, but must still be solved from the
same room inventory. `pressure_pa_therm`, buoyancy pressure, and neutral plane
remain separate named quantities; none may silently replace another.

## Flux contract

Every request records source, destination, source zone, destination zone, gas
mass, sensible enthalpy, all transported species, O2, cause, and request id.
Exterior is an explicit reservoir. A delayed parcel transfers ownership from
the source room to the in-flight ledger at issue time and from the in-flight
ledger to the destination at delivery time. Delivery must not repeat the
source debit.

Sign convention:

- Positive values enter the destination zone.
- Interior transfers have equal and opposite room terms.
- Exterior/HVAC sources and sinks carry an explicit boundary id.
- Plume entrainment is an internal lower-to-upper transfer and sums to zero at
  room level.
- Numerical clamps are never physical fluxes. They are exported separately and
  must be zero within tolerance in an accepted canonical run.

### Semantic ownership identity

Request identity prevents applying one event twice, but it cannot detect two
different legacy mechanisms that represent the same physical transfer. The
shadow therefore also maintains a step-local semantic key:

```text
connection + source/destination rooms + source/destination zones + quantity
```

Producer, transport family and boundary kind are metadata, not key fields.
This lets ThermalSystem and GasExchangeSystem collide visibly when they claim
the same opening/route/quantity. Building openings use their deterministic
`opening_index`; exterior, interlayer and chemical boundaries use separate
stable namespaces. A delayed parcel claims semantic transport at issue time,
not again at delivery.

F3.0k.1a implements this registry passively. F3.0k.1b selects provisional
shadow owners and suppresses duplicate opening-species requests only inside
the shadow transaction; all legacy writers remain active. It also proves that
the current single-route request cannot honestly express an atomic multi-zone
gas/enthalpy/O2/species bundle. F3.0k.1c now supplies that atomic primitive and
uses it for exact shadow CO oxidation chemistry. F3.0k.1d migrates direct
doorway transport and F3.0k.1e gives delayed parcels one persistent
carve-to-resolution lifecycle. F3.0k.1f found that immediate horizontal
background/counterflow cannot honestly share one atomic payload because their
legacy species, O2 and enthalpy terms use different directions and activation
rules. F3.0k.1g confirms that active two-zone vertical openings already reuse
the direct doorway bundle, while the legacy vertical fallbacks remain
species-only and cannot absorb the separate Thermal/OES models. The first
authoritative boundary must therefore be sealed single-room F3.1; exterior
and interior-opening authority remain later phases.

## Mandatory invariants

Per step and cumulatively:

1. Building gas mass change equals exterior, HVAC, suppression and combustion
   boundary terms; internal openings and plume sum to zero.
2. Room upper plus lower plus in-flight ownership closes exactly once.
3. Energy change equals combustion, wall/radiation, transported enthalpy,
   suppression and declared boundary terms.
4. Every species and O2 closes independently; no concentration headroom rule
   may create or destroy stock.
5. O2 consumed by fire agrees with the HRR/stoichiometric contract used by
   O2E1, without a second availability throttle.
6. EOS volumes close to room volume within tolerance without changing mass.
7. Zone inventories remain non-negative. A request exceeding available stock
   is proportionally limited before application and the rejected amount is
   reported.
8. Internal opening fluxes are antisymmetric. Delayed parcels have one owner at
   every instant.
9. FED reads derived concentrations only after the canonical transaction.
10. Legacy D1, S1, O1, O2E1 and D2PRE ledgers remain reconcilable with the new
    canonical ledger during migration.

## Legacy migration

| Existing element | Canonical disposition |
|---|---|
| `two_zone_solver_enabled` | Parent compatibility switch until promotion |
| `upper/lower_gas_kg`, `upper/lower_energy_kj` | Reused as published state; written only by the canonical transaction when enabled |
| `thermal_layer_m` | Derived compatibility field |
| `project_room_state()` | Pure derivation/validation; no mass backfill |
| `reconcile_projected_temperatures()` | Removed from canonical path; legacy only |
| `plume_fill_depth_coeff` and retained-layer heuristics | Legacy path only; no canonical mass authority |
| `canonical_doorway_exchange_enabled` and opening-flow flags | Correlation inputs that emit flux requests |
| `phase3a_pressure_ode_enabled` / canonical pressure flags | Reworked to consume canonical mass/energy; never a parallel inventory |
| `phase2h_o2_doorway_two_zone_enabled` | Replaced by O2 mass carried in the same opening gas request |
| Delayed species parcels | Extended to gas mass plus enthalpy plus all species and explicit ownership |

## Implementation phases

### F3.0 - Shadow transaction

Add `phase3_canonical_zone_shadow_enabled`, default OFF. Snapshot state at the
start of the fixed step and collect immutable requests while the legacy engine
continues unchanged. Apply requests to a separate shadow state and export:
mass, energy, species, O2, volume closure, rejected requests, and the difference
from legacy state.

Initial scope is deliberately small: single-room sealed combustion and plume;
then exterior leakage; then one interior doorway. A shadow residual is not
gating until every active source in that case has an owner.

Files: new `sim/core/Phase3ZoneMassSystem.gd`, `SimulationEngine.gd`, request
adapters in the contributing systems, RoomModel diagnostic storage,
StateBuilder/LogWriter, and focused tests.

STOP gate: default OFF bit-identical; shadow mode changes no legacy column;
sealed-room mass/energy residuals close; requests are generated from pre-step
state; no observed post-mutation delta is reused as a request.

Rollback: any legacy output change with the flag OFF, circular request
construction, duplicate ownership, or unexplained residual above tolerance.

### F3.1 - Canonical single-room sealed mode

Add `phase3_canonical_zone_state_enabled`, default OFF and restricted to cases
without openings/HVAC. Make the shadow transaction authoritative for gas mass,
energy, plume, O2 and combustion. Derive temperature/interface without EOS
backfill.

Cases: `fuel_balance_diag_sealed`, `o2_stoich_diag_sealed`, then a dedicated
short sealed two-zone case. Include a zero-O2 fire extinction regression so the
known zombie-ILV behavior cannot migrate into the canonical path.

STOP gate: conservation per step, no negative zones, no boundary mass, O2E1
clean, fire cannot sustain flaming below its declared O2 limit, FED OFF-path
unchanged.

Status 2026-07-16: **partial GO / authority NO-GO**. The selected-O2 extinction
invariant is implemented and runtime-tested, but `phase3_canonical_zone_state_enabled`
was not added. The shadow still reports incomplete flux ownership and non-zero
mass/energy residuals. Affected visible zombie-fire cases select lower-zone O2
through `plume_lower` while upper-zone O2 is exhausted. F3.1a was assigned to
establish that combustion-zone O2 authority before canonical publication.

F3.1a status 2026-07-17: **semantic GO / global authority NO-GO**. The existing
default-OFF canonical O2 route proves that OES must debit the same source
selected by Combustion and removes the zombie in the selected controls. Global
activation is blocked because Combustion, OES and Thermal shadow do not share
one effective-boundary predicate. The shadow remains at ownership mask 6 and
`needs_flux_owner=1`. F3.1b must unify that scope and prove mask 7 before any
authoritative state or exterior work begins.

F3.1b status 2026-07-17: **scope implementation NO-GO**. The legacy engine has
no single effective-boundary switch: its O2, thermal, gas and cache paths use
different guards. The `*_diag_sealed` cases also retain open doors. A separate
closed control reached mask 7 but still had non-zero mass/energy residuals, so
boundary classification cannot produce complete ownership. F3.1c must first
close a dedicated one-room transaction and its remaining thermal terms.

### F3.2 - Exterior pressure and leakage

Use canonical room mass/energy to solve gauge pressure and exterior gas flow.
Separate gas flow from soot removal. Transport gas, enthalpy, O2 and species
with one fraction. Retire pressure vent mass deletion and EOS refill in this
mode.

Cases: `cfast_r0_window_360` plus sealed/opening pressure controls.

STOP gate: realistic pressure magnitude, gas flow bounded by inventory, Group
A moves in the expected direction without changing tolerances, no lower-zone
collapse, PHY-P1 and FED remain physical.

### F3.3 - Interior two-zone openings

Convert resolved upper outflow/lower inflow into antisymmetric canonical
requests. Move enthalpy, O2 and every species in the same transaction. Delayed
transport, if still required, moves complete gas parcels with explicit
in-flight ownership.

Cases: `cfast_two_room_door_open`, `cfast_corridor_chain`, and the multi-floor
stairwell control.

STOP gate: internal building mass and energy close, no parcel churn creates
boundary mass, Group C improves at both 180 s and 600 s, and D1/S1 remain clean.

### F3.4 - Non-HVAC species, suppression and FED

Migrate remaining non-HVAC species, suppression and FED. Switch the
experimental mass-derived CO2 FED source only after upper and lower CO2 close
and remain physical through extinction and cooling. HVAC is excluded from this
phase by the accepted deferral decision.

Cases: `victim_fed_incapacitation`, `v4_co_remote_rooms`, PU/PVC irritant
controls, all with HVAC absent or disabled.

STOP gate: no species pumping, D2PRE convergence improves, required FED deltas
are reviewed explicitly, and no baseline is updated before a separate approval
gate.

### HVAC-R0 - Redesign specification

Before any canonical HVAC code, approve a separate specification for
supply/return zones, gas mass, enthalpy, O2/species/smoke transport,
recirculation, filtration, exterior exhaust, pressure interaction and
D1/S1/O1/FED accounting. This phase changes no motor behavior.

### F3.5 - HVAC canonical integration

Integrate the redesigned optional HVAC subsystem last. HVAC requests use their
own identities and explicit boundary reservoirs; they must not reuse GES purge
or ThermalSystem transport ownership.

Cases: `cfast_hvac_residential`, a dedicated HVAC-disabled negative control,
one recirculation control and one exterior supply/exhaust control.

STOP gate: HVAC-off remains invariant; internal recirculation conserves mass,
energy and species; exterior terms close; existing D1/S1/O1/FED findings are
resolved or remain explicitly documented; baseline changes require separate
approval.

### F3.6 - Promotion and legacy retirement

Run the full corpus with canonical mode opt-in per case, promote invariants to
FAIL, then change defaults only after Groups A/C close and all baseline deltas
are classified. Remove legacy projection writers in a later cleanup commit,
not in the promotion commit.

## Risk table

| Risk | Detection | Response |
|---|---|---|
| Double debit or delivery of parcels | room + in-flight conservation | Stop; do not compensate in projection |
| Energy convention mismatch | temperature jump with mass residual near zero | Standardize reference enthalpy before proceeding |
| O2/fire ordering changes HRR | O2E1 and zero-O2 extinction case | Keep combustion request based on one pre-step O2 contract |
| Pressure solve destabilizes inventories | negative mass, large rejected flow, closure error | Roll back F3.2; reduce timestep or use bounded implicit solve |
| Species/FED semantic regression | D1/S1/D2PRE and victim timelines | Keep F3.4 flag OFF and review deltas separately |
| Legacy and canonical writers both active | non-zero duplicate-owner counter | Hard assertion in experimental mode |

## Immediate next step

Use `docs/validation/PHASE3_CURRENT_WORKPLAN.md` as the operational checklist.
F3.1 delivered selected-O2 extinction and F3.1a proved the selected-source/
debit-source invariant. F3.1b then rejected a manufactured shared boundary
boolean: scope and complete flux ownership are separate contracts. The next
step is F3.1c, using a dedicated one-room topology to own the remaining exact
single-room thermal terms until mask 7 and `needs_flux_owner=0` coexist. Do not
globally change `plume_lower`, publish the shadow into `RoomModel`, begin F3.2,
or modify `project_room_state()` until that closure. HVAC remains deferred to
F3.5 after its own redesign gate.
