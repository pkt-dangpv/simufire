# Motor Pre-Authority Audit Plan

Date: 2026-08-21

Status: BINDING USER STOP

## 1. Purpose

This audit is the mandatory boundary between passive H3.2b diagnostics and any
implementation of H3.2b4 or H3.3 runtime authority. Its purpose is to establish
whether the simulation motor is structurally sound, executable, maintainable,
numerically defensible and supported by tests that can genuinely fail.

The audit is finite. It does not promise to repair every finding. It ends with
one of three decisions: `GO`, `GO WITH EXPLICIT BLOCKERS`, or `NO-GO`. A `NO-GO`
is a completed audit, not permission to continue authority work.

H3.2b4 and H3.3 remain blocked until the user reviews the closure report and
explicitly authorizes continuation.

## 2. Start Boundary

The audit starts only after H3.2b1b has:

1. Passed its STOP gate.
2. Been committed with any R2-1 refresh in a separate commit.
3. Reached guardrails 10/10 with a clean working tree.
4. Been pushed to a reproducible remote checkpoint.
5. Recorded the Godot version, corpus blob OIDs and required command lines.

From that checkpoint until audit closure, physics behavior, authority wiring,
expected values, baselines and tolerances are frozen except for an approved P0
or P1 remediation commit.

## 3. Scope

The audit follows the runtime call graph rather than assuming directory names.
It includes all production GDScript reachable from the scenario runner and
`SimulationEngine`, including code under `sim/core`, `sim/models`,
`sim/building`, `sim/fire` and `sim/smoke`, plus any other module that reads or
writes motor state.

It also includes:

- Official scenario runners and their Godot entrypoints.
- Python scripts that generate, validate or interpret motor evidence.
- Godot fixtures and Python contracts used to approve motor phases.
- Default-OFF experimental flags, activation gates and summary/CSV exports.
- Mass, energy, pressure, O2, smoke and species ownership and conservation.
- CFAST comparison methodology and provenance of the committed corpus.

It excludes first-person visuals, UI, assets and general product polish. HVAC is
inventoried where it touches shared state but is not redesigned in this audit.

## 4. Audit Rules

- An independent reviewer must lead closure; the authoring agent may supply
  evidence but may not be the only reviewer.
- Godot syntax is verified by real parse/load and runtime fixtures. Text matching
  alone is not accepted as compilation evidence.
- A symbol is not deleted as dead code from `rg` or a static call graph alone;
  dynamic GDScript dispatch and scene references require a second proof.
- Similar physics code is not deduplicated until behavioral equivalence and
  ownership are demonstrated.
- No tolerance, expected value or baseline may be widened to make a gate pass.
- Diagnostic metrics never govern physics during the audit.
- Godot runs are sequential, console/headless, with explicit logs. A popup,
  crash, truncated manifest, wrong row count or residual process invalidates the
  affected run.
- Each finding must contain evidence, severity, affected files, consequence,
  disposition and verification status.

## 5. Severity Model

| Severity | Meaning | Audit consequence |
|---|---|---|
| P0 | Crash, corruption, false PASS, non-finite/invalid physical state, destructive state ownership conflict or unreproducible evidence | Must be fixed or final decision is NO-GO |
| P1 | Direct risk to runtime authority, conservation, tick ordering, deterministic replay, fallback visibility or validation truthfulness | Must be fixed or explicitly blocks H3.2b4/H3.3 |
| P2 | Maintainability, performance, duplication or coverage debt without demonstrated authority-path failure | Recorded backlog; does not extend the audit |
| P3 | Naming, formatting or cosmetic cleanup | Optional backlog; never extends the audit |

Severity is based on demonstrated consequence, not code appearance.

## 6. Phases

### A0 - Freeze And Reproduce

- Record HEAD, origin state, Godot executable/version, case blob OIDs and command
  lines.
- Run the agreed baseline suites and store row counts, durations and hashes.
- Confirm a clean tree and zero residual Godot processes.

Output: frozen checkpoint and reproducibility manifest.

### A1 - Syntax, Loading And Failure Semantics

- Parse/load every reachable production GDScript with Godot 4.7.1.
- Compile Python audit tooling and run its existing contracts.
- Audit exit codes, timeout behavior, PASS markers and fail-closed fixtures.
- Find scripts that can continue after `quit(1)`, swallow parse/runtime errors or
  report artifacts after a failed run.

Output: executable inventory with no unclassified parse/load failure.

### A2 - Code Quality And Runtime Cost

- Inventory long functions, nested/repeated loops and repeated work on the
  per-timestep call graph.
- Locate duplicate implementations, unused parameters, unreachable branches,
  write-only state, inert flags and orphan diagnostics.
- Inspect untyped dictionaries, unsafe casts, mutable shared containers,
  non-finite handling and accidental allocations/copies inside hot paths.
- Measure suspected hotspots before proposing optimization. Static size or
  nesting is a review trigger, not an automatic defect.

Output: code-quality and hotspot ledger, split into correctness, performance,
maintenance and cosmetic findings.

### A3 - Architecture, State Ownership And Tick Order

- Build a writer/reader map for room/layer mass, energy, pressure, O2, smoke and
  species.
- Trace the complete physical timestep, including repeated projections, clamps,
  delayed parcels, fallbacks and summary/log boundaries.
- Identify multiple owners, circular reconstruction, hidden correction and
  diagnostics that observe a different temporal boundary from the quantity they
  claim to measure.
- Verify every authority candidate has exactly one application point and an
  explicit rollback/fallback policy.

Output: authoritative tick diagram and ownership matrix with every writer
classified.

### A4 - Test And Validation Truthfulness

- Separate parser/runtime tests from structural source-text contracts.
- Mutation-test critical guards, negative controls and failure paths.
- Detect vacuous assertions, stale anchors, circular comparisons, metrics that
  cannot fail and default values misreported as measurements.
- Audit diagnostic flag activation: every flag requiring a service must have a
  runtime activation test or be marked for retirement.
- Verify CFAST comparisons use committed case provenance and distinguish model
  disagreement from instrumentation or sampling error.

Output: test-trust matrix and list of evidence that may or may not support
runtime authority.

### A5 - Runtime Stability, Determinism And Performance

- Execute the fixed representative corpus sequentially with complete manifests
  and expected row counts.
- Repeat selected single-room, multi-room, multi-floor, loop, exterior-opening,
  ILV/reignition and long post-fire scenarios.
- Measure determinism, wall time, peak memory where available, calls per step,
  fallback counts, non-finite values and residual processes.
- Compare against the frozen checkpoint. A performance regression above 20%
  requires explanation; it is not automatically a physics failure.

Output: runtime matrix and bounded performance baseline.

### A6 - Bounded Remediation

- Fix only P0 and authority-path P1 findings.
- Use small commits with a dedicated regression test and STOP gate per finding
  or tightly coupled finding group.
- Allow at most two remediation cycles during this audit.
- Move P2/P3 findings to the backlog without implementation.

Output: remediation commits or an explicit unresolved-blocker list.

### A7 - Independent Closure

- An independent reviewer checks the inventory, findings, remediation diffs and
  final runtime evidence.
- Re-run the mandatory gates from a clean tree.
- Publish the closure report and request the user's decision.

Output: `GO`, `GO WITH EXPLICIT BLOCKERS`, or `NO-GO`.

## 7. Required Deliverables

- This binding plan.
- A machine-readable file inventory and audit manifest.
- A findings ledger with stable IDs and severities.
- Syntax/load and fixture failure-semantics report.
- Code-quality, duplication and hotspot report.
- Tick-order diagram and state-ownership matrix.
- Test-trust and diagnostic-flag activation matrix.
- Runtime/determinism/performance matrix.
- Final closure report with accepted debt and explicit blockers.

Tools created for the audit must be read-only unless an output path is supplied,
deterministic and covered by negative controls where they can affect a verdict.

## 8. Exit Criteria

The audit is complete when all of the following are true:

1. One hundred percent of the defined runtime scope is inventoried.
2. Every reachable production script has classified parse/load status.
3. No known fixture can report PASS after its failure path.
4. Every motor-state writer in scope has an owner classification.
5. Every diagnostic flag is activation-tested or explicitly scheduled for
   retirement.
6. There is no open P0.
7. Every P1 is fixed or explicitly listed as a blocker to H3.2b4/H3.3.
8. The fixed runtime corpus has complete, reproducible evidence.
9. P2/P3 debt is recorded without extending the audit.
10. The independent closure review is complete and the user has received the
    decision.

Audit completion does not itself authorize H3.2b4 or H3.3. The user must grant
that authorization explicitly.

## 9. Timebox And Forced End

Target: eight focused audit work sessions. Hard cap: ten sessions or ten working
days, whichever is reached first.

- Sessions 1-4: A0-A5 evidence collection.
- Session 5: consolidated findings and severity review.
- Sessions 6-8: bounded P0/P1 remediation.
- Sessions 9-10: contingency, reruns and independent closure.

At the hard cap, the audit closes with the evidence available. Unresolved P0/P1
findings force `NO-GO`; they do not extend the audit indefinitely. Remaining
P2/P3 findings become backlog.

## 10. Prohibited Scope Drift

During this pause, do not:

- Start H3.2b4 or H3.3.
- Grant runtime authority to a shadow component.
- Redesign HVAC or visual systems.
- Perform broad style refactors.
- Regenerate baselines to absorb behavior changes.
- Tune physical constants or tolerances to improve agreement.
- Expand the corpus after A0 except to reproduce a P0/P1 finding; such a case is
  evidence for that finding, not a new permanent audit obligation.

## 11. Resume Rule

After the closure report, the user chooses one action:

- Authorize H3.2b4/H3.3 under the documented constraints.
- Authorize a named blocker-remediation phase while authority remains frozen.
- Stop or redirect motor development.

Silence, a green test suite or an agent handoff is not authorization to resume.
