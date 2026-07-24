# Guardrails Status

Date: 2026-07-23.

## Current update

F3.3l changes the active required state to `347/353 PASS` with 6 VALID_GAP:
Group A x3 and Group C x3. The scenario-equivalence correction closes the
old Group C t=180 temperature failure and exposes t=300 temperature plus
t=600 O2 upper. Expected values and tolerances are unchanged. The current
source of truth is `docs/validation/GAPS_INVENTORY.md`.

## Hito de validación cerrado — 2026-06-21

**Baseline final: 345/350 PASS · 5/350 required FAIL (todos VALID_GAP, closed-as-gap).**
No se planifican más fases de motor en este hito. Los 5 fallos restantes están clasificados definitivamente como gaps estructurales Phase 2/3+ sin fix per-caso viable. Ver `docs/validation/GAPS_INVENTORY.md` §"Required failures closed-as-gap".

## Summary

`tests.test_guardrails` contains both pure unit tests and an integration smoke test that reads the real validation output at `sim/validation/reports/reference_checks.json`.

The pure guardrail behavior tests pass, but the real-json integration smoke currently returns exit code `1` in this workspace because the validation lane still has accepted required failures.

As of 2026-06-21, the documentation count, CFAST truth manifest and physics override linter are synchronized:

- `docs/validation/GAPS_INVENTORY.md` matches the 68 non-gating gaps reported by `reference_checks.json`.
- `truth/cfast/MANIFEST.json` was regenerated after the intentional `cfast_corridor_chain.in`/CSV update.
- Physics override linter passes.
- The remaining red status is driven by 5 required validation failures, all classified as VALID_GAP, plus one Phase 2E sentinel failure.

Current required failures:

| Group | Checks | Status |
|-------|--------|--------|
| A — `cfast_r0_window_360` | 3 O2 upper checks | VALID_GAP Phase 2; Phase 5A sweep found no viable per-case fix |
| C — `cfast_corridor_chain` | 2 temp_upper + 1 O2 upper | VALID_GAP Phase 3+; requires canonical mass/enthalpy/O2 exchange |

## Reproduction

```powershell
python -m unittest tests.test_guardrails -v
```

Observed failing test:

```text
tests.test_guardrails.TestValidationGuardrails.test_exit0_real_json
```

Observed assertion:

```text
AssertionError: 1 != 0
```

## Interpretation

This does not indicate that the product/editor runtime is broken. It means the validation guardrail script does not accept the current committed `reference_checks.json` state as green.

Because this check depends on validation report state, it is documented as a validation-lane check rather than included in lightweight product CI.

## Recommended Next Step

Run the guardrail script directly to inspect the required validation failures:

```powershell
python scripts/simulation/validation_guardrails.py
```

Then update validation expectations/reports only if the scientific mismatch is expected and reviewed.
