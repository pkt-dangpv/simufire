# Phase 3+ F3.1b effective boundary scope diagnosis

Date: 2026-07-17

## Decision

F3.1b closes as a **NO-GO before implementation**. A shared scope cannot be
represented honestly by one sealed/open boolean with the current legacy
transport contracts. No motor code, baseline, tolerance, official report,
CTRL envelope or VALID_GAP changed.

The proposed success gate also combines two independent questions:

1. whether combustion heat, O2 and species have owners (`mask=7`);
2. whether every other mass/energy mutation in the step has an owner
   (`needs_flux_owner=0`).

Fixing boundary classification can address the first question, but cannot
close residuals from thermal losses, projection or unowned transport. Claiming
otherwise would hide missing fluxes.

## Predicate inventory

| Consumer | Current activation rule | Conflict |
|---|---|---|
| Combustion auto O2 source | two-zone interface relative to fire base | Does not inspect active boundary transport |
| OES legacy plume-lower debit | interface plus raw interior/exterior opening factors | Does not use the same transport-family switches as other systems |
| OES canonical debit | `fire_o2_canonical_enabled` plus `fire_o2_mode_used` | Semantically aligned, but intentionally not global |
| OES opening exchange | iterates open geometry; `interior_transport_enabled` mainly changes delayed delivery | The flag does not mean no immediate O2 exchange |
| Thermal opening heat/mass | iterates raw `open_fraction` and independent thermal flags | Not disabled by the GES interior transport flag |
| Thermal shadow sealed scope | rejects `effective_open_fraction > 0.01` | Includes thermal gap even when the physical loop still checks raw `open_fraction` |
| Engine opening-flow cache | raw open interior geometry | Independent of GES `interior_transport_enabled` |
| GES transport | several direct, background, delayed and purge families | No single switch owns every family |
| HVAC | building availability/on state and passive/off flow | Deferred; must reject canonical authority |

`interior_transport_enabled=false` therefore cannot be treated as a building-
wide boundary switch. It does not disable Thermal opening transport and does
not remove every immediate OES/GES path.

## Misnamed sealed controls

`fuel_balance_diag_sealed` and `o2_stoich_diag_sealed` use the six-room
`simple_house` template. Five interior doors are open by default. Their
overrides disable selected GES/two-zone paths, but do not close the openings or
disable all Thermal/OES exchange families. These cases are useful combustion
diagnostics, but they are not valid authoritative single-room sealed fixtures.

Classifying room 0 as sealed from those two flags would knowingly disagree
with the motor and violate the F3.1b NO-GO criteria.

## Runtime precheck

A fresh isolated 120 s control used room 0 from `cfast_single_room_closed`,
with its interior door and exterior window physically closed, canonical O2
routing ON and the Phase 3 shadow ON.

| Metric | Result |
|---|---:|
| Godot exit | 0 |
| Room-0 snapshots | 25 |
| Snapshots with combustion mask 7 | 19 |
| Snapshots with `needs_flux_owner=1` | 24 |
| Maximum absolute mass residual | `0.03571883 kg` |
| Maximum absolute energy residual | `14.49193968 kJ` |

At about 100 s, thermal door deformation makes
`effective_open_fraction > 0.01`. The shadow sealed predicate then stops
recording combustion heat and the mask falls from 7 to 6. The actual Thermal
opening loop still checks raw `open_fraction`, which remains zero. The shadow
and physical activation guards therefore disagree even in this closed control.

More importantly, `needs_flux_owner` remains 1 while the mask is already 7.
This proves that a corrected scope predicate alone cannot close the sealed
state transaction.

Evidence is isolated under `runs/phase3_f31b/precheck_single_room_closed/`.
No official validation artifact was overwritten.

## Rejected implementation

The following patch was deliberately not made:

- no new `phase3_effective_boundary_scope_enabled` flag;
- no helper that labels the diagnostic cases sealed from
  `interior_transport_enabled=false`;
- no suppression of Thermal/OES transport to force the label to become true;
- no unconditional combustion heat request to manufacture mask 7;
- no relabeling of `needs_flux_owner`.

Each option either changes physical transport, duplicates a legacy guard or
makes the telemetry claim more ownership than the ledger actually has.

## Next phase: F3.1c

F3.1c must separate source ownership from boundary authority:

1. Add a dedicated one-room canonical fixture with no interior opening
   objects, no HVAC, no exterior opening flow and explicitly declared ACH.
2. Inventory and migrate the remaining single-room thermal terms that explain
   the mass/energy residual: wall absorption/emission, ambient/radiative loss,
   layer projection/reconcile and any pressure/leakage term active in the
   fixture.
3. Record combustion heat independently of whether a doorway later opens;
   the combustion source exists regardless of boundary topology.
4. Reach mask 7 and `needs_flux_owner=0` in that genuinely single-room fixture.
5. Only then introduce an effective-boundary registry derived from registered
   transport owners, not from a parallel list of flags.

F3.2 remains blocked. The existing default-OFF canonical O2 route remains the
provisional selected-source/debit-source contract, but it is not promoted.

## Validation

| Check | Result |
|---|---:|
| Focused Phase 3/F3.1 tests | 257 PASS / 0 FAIL |
| Physics coherence suite | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence suite | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 required PASS; 5 VALID_GAP |
| Validation guardrails | 10/10 PASS |
| Full `tests/` suite with host-owned `--basetemp` | 893 PASS / 18 FAIL |

The full-suite failures are not F3.1b regressions: F3.1b changed no motor or
test source. Seventeen are the known structural failures present before this
work; the additional async-graph UI assertion belongs to the concurrent visual
worktree changes and is outside this motor STOP gate. Running pytest against
the repository root or inside the restricted Windows temp directory also
produces unrelated collection/cleanup permission errors, so the authoritative
full-suite command for this gate targeted `tests/` and used a fresh host-owned
base temp directory.

## STOP gate

Decision: **NO COMMIT for F3.1b motor code because no motor code was created**.
The documentation may be committed after review. Roll back any future attempt
that labels the six-room diagnostics sealed, suppresses real transport to
close telemetry, or equates mask 7 with complete mass/energy ownership.
