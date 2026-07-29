# Headless Scenario Fail-Closed Contract

Date: 2026-07-29

## Supported entrypoint

Technical scenario runs use:

```text
scripts/run_scenario.py
  -> Godot 4.7.1 --headless
  -> res://tools/run_scenario_headless.tscn
```

`tools/run_scenario_headless.gd` extends `Node` and belongs to that scene. It is
not a `SceneTree`/`MainLoop` script and must not be launched with `--script`.

## Completion certificate

Process exit zero is necessary but insufficient. Each Python invocation creates
a random `run_token` and passes it to the scene. A run is accepted only when:

1. Godot exits successfully.
2. Current output contains `RUN_SCENARIO PASS token=<run_token>`.
3. All required artifacts exist.
4. `run_manifest.json` has the expected schema and `status=completed`.
5. Its token, runner entrypoint and scenario match the current invocation.
6. Its duration matches the request and `sim_time_s >= duration_s`.
7. Current process output and `godot.log` contain no fatal parse/script-load
   signature.

The manifest is written after technical export and acts as the final completion
certificate. A stale manifest fails on its token even if every output file
already exists.

## Failure behavior

Timeout, non-zero exit, missing or stale marker, stale manifest, wrong scenario,
wrong duration, truncated simulation, missing artifact and fatal GDScript load
errors all return non-zero. Result artifact paths are printed only after the
contract passes.

Warnings do not fail the run. Existing official artifacts are never deleted as
part of validation.

## Scope

This contract changes runner provenance only. It does not alter simulation
state, physics, solver behavior, validation baselines, expected values,
tolerances, CTRL envelopes or VALID_GAP classifications.
