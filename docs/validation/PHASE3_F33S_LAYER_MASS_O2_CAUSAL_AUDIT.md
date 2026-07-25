# Phase 3+ F3.3s layer-mass/interface/O2 causal audit

Date: 2026-07-25

Status: diagnostic GO, motor change NO-GO pending F3.3t.

## Scope

F3.3s identifies the first wrong owner in the 0-180 s canonical trajectory
without changing simulation state. It reads the existing F3.3r2d candidate
and committed CFAST exports. No new Godot run or motor telemetry was needed.

The audit changes no physics, case, report, expected value, tolerance, CTRL,
VALID_GAP, FED, HVAC or visual path.

Run it with:

```powershell
python scripts\simulation\analyze_phase3_f33s_layer_mass_o2.py `
  --json-out runs\phase3_f33r2d\f33s_layer_mass_o2_audit.json
```

The generated JSON stays under ignored scratch output and is not a validation
baseline.

## Method

At each CFAST export checkpoint from 10 to 180 s, the analyzer compares:

- upper/lower gas mass and interface;
- upper/lower O2 fraction and O2 inventory;
- HRR and canonical O2 decision factor;
- requested and accepted SimuFire plume flow;
- CFAST plume flow;
- cumulative plume and doorway transfer;
- every explicit SimuFire mass-residence owner;
- flame length, interface distance and the active plume branch.

The mass/interface threshold is the first of:

- mass error greater than `max(1 kg, 10% of CFAST layer mass)`;
- interface error greater than `0.10 m`.

The O2-fraction threshold is `0.01`. CFAST is exported every 10 s, so a
"first" checkpoint means the divergence is present no later than that
checkpoint, not that its exact onset is known to one simulation step.

## First divergence

The mass/interface state is already wrong at the first available 10 s
checkpoint:

| Metric at 10 s | SimuFire | CFAST | Delta |
|---|---:|---:|---:|
| Upper mass | 1.480 kg | 4.124 kg | -2.644 kg |
| Lower mass | 56.113 kg | 53.192 kg | +2.922 kg |
| Interface | 2.338 m | 2.225 m | +0.113 m |
| Upper O2 fraction | 0.2084 | 0.2042 | +0.0043 |
| HRR | 2.48 kW | 9.40 kW | -6.92 kW |
| Plume rate | 0.265 kg/s | 0.504 kg/s | -0.239 kg/s |
| Cumulative plume | 1.453 kg | 2.521 kg | -1.067 kg |

At that checkpoint:

- the exact upper/lower mass ledger residual is zero;
- projection/reconcile/legacy/other net mass is zero;
- doorway owners carry only about `0.20 kg` gross;
- canonical O2 HRR factor is `1.0`;
- requested plume equals accepted plume.

Projection, atomic acceptance, O2 throttling and doorway exchange therefore
cannot own the first divergence. The first wrong owner is the plume
request/source path. The early HRR trajectory is part of that source-path
error: SimuFire starts below CFAST even before any O2 decision throttle.

## Causal sequence

| Time | Upper mass delta | Interface delta | Upper O2 delta | SF/CFAST cumulative plume |
|---:|---:|---:|---:|---:|
| 10 s | -2.64 kg | +0.11 m | +0.004 | 1.5 / 2.5 kg |
| 60 s | -10.08 kg | +0.45 m | -0.005 | 15.8 / 29.9 kg |
| 70 s | -12.30 kg | +0.55 m | -0.011 | 16.5 / 36.2 kg |
| 80 s | -14.75 kg | +0.68 m | -0.020 | 16.8 / 43.0 kg |
| 90 s | -16.59 kg | +0.79 m | -0.029 | 16.8 / 49.8 kg |
| 180 s | -19.15 kg | +1.23 m | -0.067 | 18.8 / 97.7 kg |

The ordering is:

1. By 10 s, insufficient plume transfer creates a small upper layer and high
   interface while O2 concentration is still close to CFAST.
2. At 60 s, CFAST flame height exceeds its interface and CFAST continues to
   entrain about `0.593 kg/s`.
3. At 70 s, the upper O2-fraction error first exceeds `0.01`.
4. At 80-90 s, SimuFire remains in its far-field branch but
   `interface - flame_length` falls to `0.107-0.100 m`. Requested plume flow
   falls to `0.0075-0.0068 kg/s`, while CFAST remains at
   `0.700-0.647 kg/s`.
5. The undersized upper inventory then depletes O2 and the shared canonical
   combustion decision throttles HRR/radiation. That throttle is downstream,
   not the origin of the layer-mass error.

SimuFire's flame never formally crosses its own high interface at the 10 s
checkpoints. The defect is therefore not a missed boolean crossing alone.
The current far-field expression becomes nearly pinched as the flame
approaches the interface, while CFAST has already transitioned to a
flame/interface regime and keeps substantial entrainment.

## O2 inventory note

The analyzer exports direct CFAST upper/lower O2 masses. SimuFire's current
CSV exposes molar fractions plus gas masses, so its reported O2 inventory is
explicitly labelled a proxy (`gas_mass * molar_fraction`), not an exact
mass-fraction conversion. The causal decision uses O2 fractions, not that
proxy. This prevents molecular-weight conversion from being mistaken for a
transport residual.

## Prior experiment interaction

F3.3d2 already proved that adding only Heskestad's source term is insufficient:
it improves mass/interface but worsens temperatures and is a physical NO-GO.
F3.3s does not reopen that patch.

The next candidate must address both:

- the early HRR/source trajectory mismatch;
- the transition from far-field plume entrainment to the flame/interface
  region.

It must use one shared convective HRR contract and remain default OFF.

## STOP gate

- Read-only analysis: PASS.
- Focused analyzer tests: 9/9 PASS.
- Related F3.3 analyzer tests: 21/21 PASS.
- Broad Phase 3/F3.3/two-zone selection: 650 PASS plus the same 5
  pre-existing structural contract failures.
- Physics coherence: 9 PASS / 15 CTRL / 5 WARN / 0 FAIL.
- ILV coherence: 15 PASS / 14 CTRL / 0 FAIL.
- Validation guardrails: 10/10 PASS.
- Gap inventory: synchronized, 353 required with 6 documented VALID_GAP.
- Existing telemetry sufficient: PASS.
- Mass residence ledger closure: PASS, exact at all checkpoints.
- First incorrect owner identified: PASS, plume request/source path by 10 s.
- Projection as root cause: rejected.
- Doorway flow as root cause: rejected at first divergence.
- O2 throttle as root cause: rejected; concentration divergence starts at
  70 s.
- Flame/interface near-pinch identified: PASS, 80 s.
- Official state or baseline change: none.
- Group C retirement: NO-GO.
- Runtime authority: NO-GO.

## Next phase

F3.3t must be design-first, then a small default-OFF experiment. It should
define a continuous, region-aware plume-to-interface transition using the
same accepted/convective HRR source as the canonical combustion transaction.

Mandatory controls:

- no CFAST interface injection;
- no per-case coefficient fitted to the corridor;
- no source-term-only retry;
- OFF output exact;
- first run limited to 0-180 s;
- mass, O2 and energy ledgers exact;
- rollback if mass improves while upper/lower temperatures regress as in
  F3.3d2.
