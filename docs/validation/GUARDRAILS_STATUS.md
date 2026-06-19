# Guardrails Status

Date: 2026-06-19.

## Summary

`tests.test_guardrails` contains both pure unit tests and an integration smoke test that reads the real validation output at `sim/validation/reports/reference_checks.json`.

The pure guardrail behavior tests pass, but the real-json integration smoke currently returns exit code `1` in this workspace.

As of 2026-06-19, the documentation count, CFAST truth manifest and physics override linter are synchronized:

- `docs/validation/GAPS_INVENTORY.md` matches the 75 non-gating gaps reported by `reference_checks.json`.
- `truth/cfast/MANIFEST.json` was regenerated after the intentional `cfast_corridor_chain.in`/CSV update.
- Validation cases no longer carry the `vent_bernoulli_flow_multiplier` physics override flagged by R1-3.
- The remaining red status is driven by 14 required validation failures plus one Phase 2E sentinel failure.

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
