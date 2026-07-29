# Godot 4.7.1 Headless Crash Audit

Date: 2026-07-29

Status: root cause isolated to the agent execution environment and procedure,
not to SimuFire physics.

## Symptom

During the H2.5j session Windows displayed four native error dialogs:

```text
Godot_v4.7.1-stable_win64.exe - Application Error
The instruction at 0x...5854 referenced memory at 0x58.
```

Windows recorded them as `System / Application Popup / Event ID 26` at:

- 16:45:20
- 16:46:50
- 16:47:42
- 16:48:24

The scenario matrix had already completed at 16:40:29. The crashes occurred
during the subsequent direct-fixture and negative-control phase.

## Root Cause

The console executable is a small launcher:

```text
Godot_v4.7.1-stable_win64_console.exe    198,152 bytes
Godot_v4.7.1-stable_win64.exe        178,997,256 bytes
```

The launcher starts the graphical Godot binary even for `--headless` work.
When the agent launched Godot inside its restricted Windows sandbox, every
direct fixture reported:

```text
ERROR: Failed to read the root certificate store.
at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
```

Five sandboxed fixture launches reproduced that degraded initialization path
five times. The same five launches outside the sandbox produced:

- 5/5 PASS;
- 0 certificate-store errors;
- identical logs;
- no residual Godot process;
- no new `Application Popup` event.

The original native popups followed a deliberately failing mutation fixture.
That test had already emitted its expected failure and exit code, but the child
Godot process then faulted during teardown. Treating the fixture's output/exit
contract as sufficient without checking the child-process teardown was an agent
procedure error.

The exact internal Godot destructor responsible for the `0x58` access is not
available because Windows produced no WER dump. The measured causal boundary is
nevertheless clear: restricted/sandboxed Godot initialization plus direct
fixture teardown, not simulation physics.

## Data Integrity

The H2.5j scenario results are not truncated:

- 10/10 runs have `status=completed`;
- 10/10 have a matching run token and PASS marker;
- 10/10 reached or exceeded the requested `sim_time_s`;
- all manifests identify Godot 4.7.1 and
  `res://tools/run_scenario_headless.tscn`;
- the four Windows crash events occurred after the matrix.

A controlled 10 s H2 run inside and outside the sandbox produced identical
SHA-256 hashes for:

- `sim_log.csv`;
- `sim_log.txt`;
- `events.json`.

`summary.json` differs only because it embeds the different output directory.
This confirms that the sandbox problem is a process-initialization/teardown
issue, not a change in simulated physics.

The two gate-defining 120 s ON scenarios were then repeated sequentially
outside the sandbox:

| Scenario | Manifest | Godot errors | Residual process | New popup | Artifact comparison |
| --- | --- | ---: | ---: | ---: | --- |
| `corridor_chain` | completed, 120.083 s | 0 | 0 | 0 | CSV/log/events byte-identical |
| `r0_window_360` | completed, 120.083 s | 0 | 0 | 0 | CSV/log/events byte-identical |

The nine critical solver fixtures were also repeated outside the sandbox:
9/9 PASS, zero certificate errors, zero other Godot errors and no residual
process. No new event ID 26 appeared after the original four.

## Binding Execution Rule

On this Windows workspace:

1. Never launch Godot from the restricted agent sandbox.
2. Request unsandboxed execution for every Godot process, including fixtures.
3. Keep the Godot editor closed during motor validation.
4. Run Godot processes sequentially; wait for the child process to disappear
   before launching the next one.
5. Use `scripts/run_scenario.py` for scenarios. Never launch
   `tools/run_scenario_headless.gd` with `--script`.
6. Direct fixtures may use `--script` only because they extend `SceneTree`.
7. Give each direct fixture an explicit `--log-file`.
8. For negative controls, verify all three:
   - expected non-zero exit;
   - zero false PASS markers;
   - no new Windows `Application Popup` event or residual Godot process.
9. Any certificate-store error invalidates the execution environment and the
   run must be repeated outside the sandbox.
10. A native popup before a completed manifest invalidates that scenario run.
    A teardown popup after the manifest is still a tooling defect and must be
    recorded, even when the simulation artifacts are complete.

## Scope

No motor, solver, scenario, baseline, tolerance, CTRL or VALID_GAP changed
during this audit.
