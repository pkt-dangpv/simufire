# Phase 3+ F3.3r2a pure surface-energy solver

Date: 2026-07-25

Status: GO for the isolated numerical component. Runtime wiring and thermal
authority remain NO-GO.

## Scope

F3.3r2a adds:

- `sim/core/Phase3SurfaceEnergySolver.gd`;
- `tests/fixtures/phase3_f33r2a_surface_energy_solver.gd`;
- `tests/test_phase3_f33r2a_surface_energy_solver.py`.

The solver is not referenced by `SimulationEngine`, `RoomModel` or
`Phase3ZoneMassSystem`. It does not change the simulation tick, CSV schema,
official cases, reports, expected values, tolerances or active gaps.

## Numerical contract

The component is a pure five-node finite-volume implicit solver. Its input is:

- an immutable surface snapshot;
- material properties and area;
- explicit interior convection;
- explicit gas radiation;
- explicit accepted fire radiation;
- explicit exterior Robin exchange;
- timestep.

It returns a proposed post-step snapshot and an energy ledger. It never
mutates the input dictionary.

The default node-depth fractions are:

```text
[0.00, 0.03, 0.05, 0.10, 1.00]
```

The grid resolves the concrete penetration depth relevant to the 0-180 s
validation window. The grid is stored in the surface state and may be
replaced by another strictly increasing five-value grid in future phases.

No temperature or energy clamp is applied. Invalid material, geometry,
timestep, grid or non-finite state fails closed. This prevents a numerical
limit from hiding an energy residual.

## Energy identity

For one surface step:

```text
delta(surface storage)
  - interior convection
  - gas radiation
  - accepted fire radiation
  + exterior removal
  = residual
```

Internal node conduction is assembled as equal and opposite pairwise
conductance and cannot create or remove energy.

Gas radiation and fire radiation remain separate ledger fields. This is
required because future runtime wiring must debit gas radiation from gas but
must route accepted combustion radiation directly from the atomic combustion
transaction.

## STOP gate results

Godot runtime:

```text
Godot Engine v4.7.1.stable
PHASE3_F33R2A_SURFACE_ENERGY_SOLVER_PASS
```

| Check | Result |
|---|---:|
| Constant ambient | exact no-op |
| Radiation-only deposit | 100.000000 kJ stored for 100.000000 kJ input |
| Semi-infinite concrete surface at 60 s | 27.932920 C |
| Analytical semi-infinite reference | 28.184077 C |
| Relative temperature-rise error | 3.0688% |
| Allowed early-time error | <=5% |
| 10,000-step cumulative residual | 0.000000059642 kJ |
| Input snapshot mutation | none |
| Invalid material | fails closed |
| Full project parse | PASS |

Python:

- F3.3r2a structural contract: 10/10 PASS;
- combined F3.3q/r1/r2a focused tests: 27/27 PASS.

Repository suites:

- Physics coherence: 9 PASS / 15 CTRL / 5 WARN / 0 FAIL;
- ILV: 15 PASS / 14 CTRL / 0 FAIL;
- guardrails before commit: 9/10, with only R2-1 triggered by the new
  uncommitted `sim/core` file.

R2-1 is expected repository-freshness behavior. No reference artifact should
be regenerated because the solver has no runtime caller.

## Decision

F3.3r2a is GO. The numerical and conservation contract is strong enough for
the next isolated phase.

F3.3r2b may add default-OFF state and transaction wiring, but must not enable
the shadow in an official case. Its first STOP gate must prove:

1. default-OFF output is bit-identical;
2. the old lumped wall path and new multi-surface path are mutually
   exclusive;
3. accepted combustion radiation uses the atomic combustion acceptance
   fraction;
4. interface wall-area migration conserves nodal energy;
5. duplicate or rejected transactions cannot commit surface energy.

No 60/120/180 s correspondence run is authorized until F3.3r2b passes those
direct transaction fixtures.
