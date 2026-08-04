# Phase 3 H3.2-S0c Gas Physical-Owner Events

Date: 2026-08-04.

## Decision

**GO at STOP gate for passive GasExchangeSystem instrumentation only.** S0d is
not started, H3.2-S remains blocked, H3.2b still blocks H3.3 and no runtime
authority is granted to any solver.

## Scope

`phase3_physical_owner_ledger_enabled` is reused unchanged and stays default
OFF. When enabled, `GasExchangeSystem` keeps its own step-local event list with
the `gas:` ID namespace and exposes
`get_phase3_physical_owner_events()` / `get_phase3_physical_owner_summary()`.
`SimulationEngine` joins the thermal and gas lists **only for export**; each
subsystem keeps its own accumulator, so a duplicated ID stays detectable in the
combined fail-closed aggregate. `Phase3CoupledPressureSolver` is untouched and
the legacy CSV schema is unchanged.

The flag is a run-start diagnostic setting. Enabling it after parcels have
already been queued while it was OFF cannot reconstruct diagnostic parcel IDs
for those existing entries; their later lifecycle would therefore be
incomplete. Official runners set the flag before the first step, which is the
only supported mode for this ledger.

## Audited Mutation Sites

### Zone gas mass and sensible energy

`GasExchangeSystem` writes `upper_gas_kg` / `upper_energy_kj` at exactly four
sites and never writes `lower_gas_kg` / `lower_energy_kj`.

| Site | Owner | Classification | Accepted value |
|---|---|---|---|
| `remove_upper_layer_fraction` after pressure venting | `gas_pressure_vent_upper_removal` | exterior boundary | measured around the single callback |
| `remove_upper_layer_fraction` after exterior smoke vent | `gas_exterior_smoke_vent_upper_removal` | exterior boundary | measured around the single callback |
| `remove_upper_layer_fraction` after PPV inlet dilution | `gas_ppv_inlet_upper_removal` | exterior boundary | measured around the single callback |
| `remove_upper_layer_fraction` after PPV exhaust | `gas_ppv_exhaust_upper_removal` | exterior boundary | measured around the single callback |
| immediate inter-room smoke transport | `gas_immediate_upper_transport` | interior transport | one transfer quantity for debit and credit |
| delayed transport enqueue | `gas_delayed_parcel_upper` (`created`) | delayed parcel | source debit at the enqueue site |
| delayed transport delivery | `gas_delayed_parcel_upper` (`delivered`) | delayed parcel | parcel credit at the delivery site |
| delayed transport with a missing destination | `gas_delayed_parcel_upper` (`cancelled`) | delayed parcel | no room mutation; loss in metadata |
| background enthalpy coupling | `gas_background_upper_transport` | interior transport | one transfer quantity for debit and credit |

The generic `remove_upper_layer_fraction(room, fraction)` callback carries no
cause of its own. Provenance now comes from the caller, which is the only place
where it truly exists, and the accepted delta is measured around that single
mutation — never around a stage.

### Reused, never emitted twice

| Path | Existing observation |
|---|---|
| canonical doorway upper/lower/counterflow | H3.1 thermal transfer ledger |
| delayed parcel create/resolve/cancel/in-flight | `_phase3_shadow_parcel_*` and `get_phase3_runtime_parcel_inventory()` |
| `sync_room_upper_layer` projection and clamp | `ZoneFireSolver` projection trace and `two_zone_boundary_energy_kj` |
| thermal owners | S0b `ThermalSystem` events |
| exterior CO/CO2/HCN purges | `_record_phase3_shadow_exterior_purge_event` |
| doorway/background/vertical species events | `_record_phase3_shadow_*_species_event` |

### Declared missing coverage (blocks the S0d closure claim, not S0c)

1. **Species and O2 transported through the `*_delta_kg` accumulators.**
   Immediate transport species, doorway O2/species counterflow, background
   exchange, two-zone opening exchange, vertical-opening exchange and the O2
   smoke carry all write into per-room accumulators that are applied once, at
   the end of `step_smoke`, under `maxf(0.0, ...)`. When that clamp binds, the
   per-owner accepted share is not recoverable without inventing an allocation
   rule. This is recorded as absent coverage; no owner was fabricated.
2. **Bulk-room O2** has no zone in the legacy state, so it cannot satisfy the
   S0a zone identity for an exterior-boundary event. It appears only as
   metadata (`o2_exterior_delta_kg`, `parcel_o2_kg`, `o2_carry_kg`).
3. **Species-only exterior purges** (ACH infiltration, outside-open purge,
   post-fire purge, pressure-vent and PPV species dilution) mutate no zone mass
   or energy. Their CO/CO2/HCN side is already covered by the exterior purge
   ledger; HCl, acrolein, formaldehyde and smoke remain uncovered there.
4. **HVAC** also calls `remove_upper_layer_fraction` and stays deferred under
   the motor plan. Its upper-layer removal is therefore not owned.
5. `two_zone_opening_flow_enabled` species routes move species only; legacy does
   not move zone gas mass or enthalpy there, so no mass/energy owner exists.

## Physical Rules Enforced

- Interior transport debits and credits are the same accepted quantity, so the
  residual closes exactly at `0.0`.
- A delayed parcel is never recorded as consummated transport: `created` and
  `delivered` are separate lifecycle events and the class is structurally
  excluded from physical sources and from the transport residual.
- Delivery metadata carries `original_species_kg`, `delivered_species_kg` and
  `refunded_species_kg`; the refund equals the source-room mutation.
- Exterior events declare `room_to_exterior` explicitly and are signed as
  outflows.
- Numerical corrections are not promoted: projection stays with the existing
  trace.

## STOP Evidence

- Six official 30 s scenario pairs are byte-identical OFF/ON with identical row
  counts and the same 115 legacy columns: `cfast_corridor_chain`,
  `cfast_r0_window_360`, `fuel_balance_diag_sealed`, `o2_stoich_diag_sealed`,
  `v4_co_remote_rooms` and `victim_fed_incapacitation`. With the flag OFF the
  summary carries no ledger key at all.
- Their final-step combined ledgers hold 11–16 events, zero invalid events and
  zero duplicate IDs. The interior-transport residual is exactly `0.0 kg` and
  `0.0 kJ`; the interzone residual stays at the S0b magnitude, at most
  `3.553e-15 kg` and `3.553e-15 kJ`.
- The runtime census fixture drives `step_pressure_venting`, `step_ppv` and
  `step_smoke` for twelve steps on a building with an exterior window, a PPV
  opening and an interior door. Every instrumented family fires from a real
  legacy mutation: 60 exterior-boundary, 12 interior-transport and 36
  delayed-parcel events, with 23 parcels created, 13 delivered and 10 still in
  flight, so `created - delivered == in-flight`. No parcel is created or
  delivered twice and no event ID repeats.
- Two Godot fixtures, each with a runtime negative control that exits 1 and
  prints no PASS marker. Ten sequential Godot 4.7.1 fixtures pass, including
  H1, H2.10, H3.2a, H3.2-M atomic acceptance, the coupled bundle shadow, the
  atomic parcel lifecycle and S0a/S0b.
- `pytest -k "phase3 or guardrail"` is `1366 PASS / 2 FAIL`: the expected R2-1
  freshness failure from the dirty motor and the pre-existing layer-interface
  export test.
- Physics coherence is `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`; ILV coherence is
  `15 PASS / 14 CTRL / 0 FAIL`; the gap inventory is unchanged at
  `353 required + 6 VALID_GAP + 71 non-gating`. Guardrails are `9/10` with only
  the expected R2-1 failure. No Godot process remains.

## Interpretation Limit

The ledger attributes the listed gas mass and sensible-energy mutations without
changing any of them. It does not prove those mutations are physically correct,
it does not cover species or O2 ownership, and it is still not a non-circular
source vector for the coupled pressure solver.
