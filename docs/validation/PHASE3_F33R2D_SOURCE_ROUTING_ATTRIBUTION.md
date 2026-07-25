# Phase 3+ F3.3r2d source and routing attribution

Date: 2026-07-25

Status: diagnostic GO, physical adoption NO-GO.

## Scope

F3.3r2d separates the two failures observed in the F3.3r2c 180 s gate:

1. why accepted direct fire radiation is below CFAST;
2. how the incorrect canonical interface redistributes that accepted energy
   between upper and lower wall surfaces.

The work is passive and remains under the existing default-OFF canonical
multi-surface shadow. It changes no physical equation, official case, report,
expected value, tolerance, CTRL, VALID_GAP, FED, HVAC or visual path.

The first scratch pair produced during the session was discarded because the
parent canonical flags were not enabled. The binding runs were regenerated
with Godot 4.7.1 and:

```powershell
python scripts\run_scenario.py `
  runs\phase3_f33r2c\cases\corridor_off.json `
  --out-dir runs\phase3_f33r2d\180_corridor_off `
  --timeout 900 `
  --phase3-cfast-buoyancy-destination-shadow

python scripts\run_scenario.py `
  runs\phase3_f33r2c\cases\corridor_cfast_boundary.json `
  --out-dir runs\phase3_f33r2d\180_corridor_cfast `
  --timeout 900 `
  --phase3-cfast-buoyancy-destination-shadow
```

No run beyond 180 s was made.

## Added observability

The opt-in CSV schema now distinguishes cumulative:

- requested fire radiation;
- pre-atomic accepted fire radiation;
- rejection by the combustion decision;
- rejection by the atomic inventory fraction;
- radiation finally routed to surfaces;
- wall-area migration energy;
- upper and lower gas-to-surface exchange.

The existing instantaneous combustion radiation and partition fields are
also written to the opt-in CSV. A repeated preparation in the same physical
step now preserves migration telemetry instead of overwriting it with zero.
The persistent surface state and all physical routes are unchanged.

The read-only analyzer is:

```powershell
python scripts\simulation\analyze_phase3_f33r2d_source_routing.py `
  --json-out runs\phase3_f33r2d\attribution.json
```

## Source attribution

The cumulative identity is:

```text
CFAST radiation - routed radiation
  = (CFAST radiation - requested radiation)
  + decision-rejected radiation
  + atomic-rejected radiation
```

| Time | CFAST | Requested | Routed | Upstream delta | Decision rejected | Atomic rejected |
|---:|---:|---:|---:|---:|---:|---:|
| 60 s | 1.250 MJ | 1.000 MJ | 1.000 MJ | 0.251 MJ | 0.000 MJ | 0.000 MJ |
| 120 s | 7.092 MJ | 6.647 MJ | 6.266 MJ | 0.445 MJ | 0.380 MJ | 0.000 MJ |
| 180 s | 13.392 MJ | 12.938 MJ | 9.124 MJ | 0.454 MJ | 3.814 MJ | 0.000 MJ |

At 180 s, decision rejection explains 89.4% of the `4.268 MJ`
shortfall. The atomic commit rejects no radiation and all source identities
close within `1e-4 kJ`.

The rejection is not an independent surface rule. At every checkpoint:

```text
combustion decision fraction == canonical O2 HRR factor
```

| Time | SimuFire canonical O2 ref | CFAST upper O2 | Accepted HRR | CFAST HRR |
|---:|---:|---:|---:|---:|
| 60 s | 0.1947 | 0.1968 | 150.3 kW | 169.2 kW |
| 120 s | 0.0845 | 0.1794 | 224.0 kW | 300.0 kW |
| 180 s | 0.0355 | 0.1667 | 68.2 kW | 300.0 kW |

The legacy requested HRR remains `300 kW` at 180 s. The canonical layer
state depletes its O2 reference and throttles the accepted source to 22.7%.
Restoring radiation independently would therefore break the shared
combustion-energy contract and hide the upstream layer/O2 error.

## Interface and routing attribution

The analyzer reroutes the observed accepted-radiation increments using the
CFAST interface only as a read-only counterfactual. It does not apply CFAST
state to SimuFire.

At 180 s:

| Metric | SimuFire | CFAST |
|---|---:|---:|
| Interface | 1.969 m | 0.736 m |
| Upper mass | 7.80 kg | 26.94 kg |
| Lower mass | 46.32 kg | 15.41 kg |

| Surface | Actual routing | CFAST-interface counterfactual | Delta |
|---|---:|---:|---:|
| Ceiling | 2.193 MJ | 2.193 MJ | 0.000 MJ |
| Upper wall | 1.150 MJ | 2.925 MJ | -1.775 MJ |
| Lower wall | 3.588 MJ | 1.812 MJ | +1.775 MJ |
| Floor | 2.193 MJ | 2.193 MJ | 0.000 MJ |

The wrong interface therefore redistributes `1.775 MJ` from upper wall to
lower wall without creating or destroying energy. Interface movement carries
`1.591 MJ` gross between wall classes through 180 s with zero migration
residual.

Gas-to-surface storage is almost entirely upper-zone driven:

| Time | Upper exchange | Lower exchange | Total |
|---:|---:|---:|---:|
| 60 s | 0.835 MJ | -0.010 MJ | 0.825 MJ |
| 120 s | 8.651 MJ | -0.029 MJ | 8.622 MJ |
| 180 s | 14.312 MJ | 0.035 MJ | 14.348 MJ |

The upper/lower split closes within numerical tolerance.

## STOP gate

- Source ledger: PASS.
- Atomic radiation routing: PASS, zero rejection.
- Gas/surface upper-lower split: PASS.
- Interface migration conservation: PASS.
- Legacy invariance: PASS, zero differences across 13,110 cells.
- Physical correspondence: NO-GO.
- Runtime authority: NO-GO.
- Group C retirement: NO-GO.

The multi-surface transaction is not the binding defect. The dominant error
is the canonical zone mass/interface trajectory, which produces a severely
under-sized upper inventory, excessive upper O2 depletion and source
throttling. The same interface independently misroutes wall radiation.

## Next phase

F3.3s must be a read-only layer-mass/O2 causal audit before another physical
experiment. It must reconstruct, by checkpoint and by owner:

- upper/lower gas mass and EOS volume;
- upper/lower O2 inventory;
- plume transfer and combustion O2 sink;
- doorway upper outflow and lower inflow;
- projection/reconciliation deltas;
- the first timestep where SimuFire diverges materially from CFAST.

Do not add radiation, O2 or interface coefficients. Do not inject the CFAST
interface into runtime state. Do not enable an official case, run beyond
180 s, retire Group C or promote the multi-surface shadow before that audit
identifies the first incorrect mass/O2 owner.
