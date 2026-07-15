# Phase 3+ HVAC deferral decision

Date: 2026-07-15
Status: accepted and binding for the current Phase 3+ workplan

## Decision

HVAC canonical ownership is deferred until the end of the Phase 3+ migration.
The current `HVACSystem` remains on the legacy path and is not the next shadow
producer. F3.0j is reassigned to ThermalSystem species transport.

This is intentional, not an omitted task. HVAC is optional in most scenarios
and its behavior is expected to be redesigned before canonical integration.
Encoding its current extraction and supply semantics now would create a
contract that may immediately become obsolete.

## Scope rule until HVAC re-entry

- Canonical shadow closure and authority promotion use cases with HVAC off.
- HVAC scenarios remain legacy regression controls; they are not evidence of
  canonical conservation.
- Any report of "complete Phase 3 conservation" must say "non-HVAC" until the
  deferred phase is closed.
- No HVAC extraction may be mislabeled as GES exterior purge or ThermalSystem
  transport to make a residual disappear.
- Existing HVAC findings, skips and control envelopes remain visible. They may
  not be retired on the strength of non-HVAC validation.
- No per-case tolerance or baseline update may substitute for HVAC ownership.

## Revised execution order

1. F3.0j: exact ThermalSystem CO/CO2/HCN shadow transport.
2. F3.0k: non-HVAC cross-path ownership and conservation closure.
3. F3.1: authoritative single-room sealed mode, including zero-O2 flame
   extinction regression.
4. F3.2: canonical exterior pressure and leakage; target Group A.
5. F3.3: canonical interior two-zone openings; target Group C.
6. F3.4: remaining non-HVAC species, suppression and FED integration.
7. HVAC-R0: user-approved redesign specification, without motor changes.
8. F3.5: HVAC canonical supply/return integration as the last subsystem.
9. F3.6: final corpus promotion and legacy retirement.

## HVAC redesign prerequisites

Do not implement F3.5 until a separate STOP gate approves:

- supply and return topology, including explicit source/destination zones;
- dry-gas mass flow and transported enthalpy;
- O2, CO, CO2, HCN, smoke and irritant transport semantics;
- recirculation, filtration and exterior exhaust ownership;
- interaction with pressure, neutral plane and openings;
- D1/S1/O1/FED accounting and required CSV telemetry;
- behavior when HVAC is disabled or absent;
- migration strategy for existing HVAC cases and controls.

## F3.5 acceptance gate

- Default behavior remains unchanged until an explicit opt-in flag is enabled.
- Every HVAC boundary and recirculation request has one identity and one owner.
- Internal recirculation conserves gas, energy and every transported species.
- Exterior supply/exhaust closes against explicit boundary reservoirs.
- No overlap exists with GES purge, ThermalSystem transport or opening flow.
- `cfast_hvac_residential` and dedicated HVAC-off/on controls pass their
  approved contracts without hiding D1/S1/O1/FED findings.
- Baseline changes, if any, require a separate before/after approval gate.

## Reversal

This decision can be changed only by an explicit planning decision that also
updates this file, `PHASE3_CURRENT_WORKPLAN.md`,
`PHASE3_CANONICAL_TWO_ZONE_ARCHITECTURE.md` and `HANDOFF_CURRENT_STATE.md`.
An implementation prompt alone is not sufficient to re-prioritize HVAC.
