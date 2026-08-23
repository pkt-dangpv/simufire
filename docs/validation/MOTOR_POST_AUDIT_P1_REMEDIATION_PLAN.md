# Motor Post-Audit P1 Remediation Plan

Date: 2026-08-23

Status: ACTIVE USER-AUTHORIZED CLEAN-CLOSURE PROGRAM; P1R0 COMPLETE

Session window: session 31 onward; no session cap

## 1. Purpose And Predecessor Decision

This program is the separately governed successor to the completed Motor
Pre-Authority Audit. It is not an extension or reopening of A0-A7.

The independent A7-R2 review completed in session 29/30 with `NO-GO`. Session
30/30 repaired and preserved the R2-F1 release-integrity counter contract, but
did not close any authority-path P1. The purpose of this program is to resolve,
retire or prove the remaining P1 blockers without granting runtime authority by
implication.

The user requires a clean audit before product development resumes. An
intermediate phase may return `NO-GO` or `STOP`, but that does not close this
program and does not move unresolved work to a backlog. The program closes only
with `CLEAN GO`, or when the user explicitly cancels or redirects it. A blocker
is never hidden through a baseline, expected value, tolerance, case,
default-flag change or severity downgrade.

Clean closure is broader than authority readiness. It requires all in-scope
findings and failing gates to have a final, evidenced disposition. H3.2b4,
H3.3 and runtime authority still require a separate user decision after clean
closure.

## 2. Start Boundary And Canonical Candidate

The proposed canonical remediation base is:

- Commit: `f9c3902b35e3f16170b35bf10085697e8021e7f1`.
- Remote ref: `origin/codex/r2f1-counter-contract`.
- Parent: `b1a9799c90a6830adb06cb53edc2f61a1161e54e`.
- Fixed audit comparison base:
  `ed2b6c0a1d458ff6edb92739cea27117195aa5cf` (the value of `origin/main`
  when this program was designed).
- Relationship to comparison base: five commits ahead, zero behind.

The optional post-audit probe design commit
`767db1ee5516c20e42c1282bca53616e4357a893` is deliberately excluded. It
remains preserved on `origin/codex/a7-r2-checkpoint`; it is not reverted or
discarded. Its `zone_at_height` design and any future implementation are not
part of this program.

P1R0 must STOP rather than adapt the checkpoint if any SHA, parent, ancestry,
tree or remote ref differs. If the five-commit candidate is later integrated
into `main`, P1R0 records the resulting commit and re-freezes provenance before
P1R1 begins. That integration does not move the fixed audit comparison base:
all before/after claims continue to use `ed2b6c0a1d45...`, never the moving
`origin/main` ref.

Opening this program does not authorize a commit, push, merge or implementation
phase. Each phase that can change tracked files requires a separate named user
GO.

## 3. Frozen Baseline

At the canonical candidate, the following values are frozen until independent
closure unless a STOP gate explicitly proves that a change is the direct fix
for the named P1:

| Item | Frozen value |
|---|---|
| Reference checks | 530, identical unique name set |
| Required checks | 350 |
| Failed required checks | 6 entry-state `VALID_GAP`; not acceptable at clean closure |
| Known non-gating gaps | 76 |
| Required passing checks | 344 |
| Cases tree | `56460c99bf08819e88fab5898da7a812edc48bc4` |
| Baselines tree | `5f1cf23ae140b0540e828be47c42d66b563ba583` |
| CFAST truth tree | `f437cc16a7c82752e24c07b808d7a36765b88144` |
| Guardrails | 10/10 PASS, including R2-1 and gap sync |
| Python suite comparison | 17 entry-state failures; zero failures required at clean closure |

The suite baseline is the set of test node IDs, not only the count. P1R0 must
capture the complete set on the fixed audit comparison commit
`ed2b6c0a1d45...` and the canonical candidate using the same Python version,
environment and command. The Windows sandbox-local full suite attempts from
2026-08-23 are inadmissible because pytest could not access its temporary
directory; the successful session-30 comparison is provisional until P1R0
reproduces it durably.

The session-19 runtime ledger reports 18/18 sequential cases, 81 runtime
evidence files and frozen tree hashes. The local session directory currently
contains 83 files when its STOP report and ledger are included. P1R0 must
inventory and archive the actual files; neither count may be assumed.

## 4. Authority And Scope Boundaries

Throughout P1R0-P1R8:

- H3.2b4, H3.3 and runtime authority remain `NO-GO` and frozen.
- D1 probe implementation is prohibited.
- D0 remains a separate optional design commit and must not enter the program
  branch.
- HVAC design, implementation and calibration are deferred and out of scope.
- HVAC rows already present in the fixed corpus may run as observational
  sentinels, but cannot be used to claim closure or to block a non-HVAC P1
  unless they expose a shared infrastructure failure.
- Physics behavior, authority wiring, default flags, cases, baselines,
  expected values, tolerances, minima and maxima remain frozen except for a
  separately authorized direct P1 fix. No planned P1 currently requires a
  case, baseline, expected-value or tolerance change.
- A green guardrail or suite never grants authority.
- Text-inspection contracts, parser/load tests and runtime tests must be
  reported as separate evidence layers.

The following are entry baselines, not accepted exit debt:

- The 17 failing Python tests must be repaired or replaced by stronger tests
  after root-cause classification. No test may be deleted, skipped, weakened or
  rewritten merely to obtain green output.
- Required validation must end with zero failed required checks. The current
  `VALID_GAP` allowlist is temporary audit evidence, not a clean result.
- Every non-gating gap must end as `FIXED`, `FALSE_POSITIVE`,
  `VERIFIED_MODEL_LIMITATION` or `USER_EXCLUDED_HVAC`, with evidence and an
  owner. `OPEN`, `PARTIAL`, `PENDING`, `UNKNOWN` and `NOT_RE_EVALUABLE` are not
  final clean states.
- P2 and P3 findings do not move automatically to backlog. Each must be fixed,
  disproved or explicitly excluded by the user before clean closure.

A legitimate contract retirement or gating reclassification requires primary
source provenance, an independent review and a dedicated commit. It cannot be
used as a substitute for a failing physical result. Any physics-changing defect
fix requires a separate design, regression, rollback and user GO; it does not
authorize H3.2b4 or H3.3.

## 5. P1 Register At Entry

These classifications are the session-29 A7-R2 result and must be independently
reconciled in P1R1. They are not conclusions inherited on trust.

| ID | Entry classification | Remediation lane |
|---|---|---|
| `A3-P1-001` hidden post-physics synchronization | OPEN | P1R2 |
| `A3-P1-002` incomplete O2 ownership and aggregate clamps | OPEN | P1R3 |
| `A4-P1-001` diagnostic flags lack runtime activation evidence | OPEN | P1R4 |
| `A4-P1-002` stale and unreproducible mutation evidence | OPEN | P1R5 |
| `A4-P1-003` incomplete check-to-case/source provenance | PARTIAL | P1R5 |
| `A6-P1-001` passive diagnostic stack cost | OPEN | P1R6 |
| `A14-P1-001` two CFAST internal-baseline failures | OPEN | P1R7 |
| `A15-P1-001` bedroom O2 historical semantics | PARTIAL | P1R5 owner; P1R7 verification |
| `A15-P1-002` kitchen upper-zone FED historical semantics | PARTIAL | P1R5 owner; P1R7 verification |
| `A17-P1-001` historical Godot import gate | NOT RE-EVALUABLE | P1R7 |

The R2-F1 counter test, fail-closed report publication and provisional Ghanekar
demotions are release-integrity remediations already present in the canonical
candidate. They are prerequisites, not authority-path P1 closures.

## 6. Phase Plan

### P1R0 - Canonical Freeze And Evidence Escrow

- Verify the exact candidate, parent chain, remote refs, clean tree and zero
  Godot processes.
- Decide, under a separate user authorization, whether the candidate is merged
  to `main` or remains the branch base. Record the result without rewriting
  history.
- Reproduce the Python suite on `origin/main` and the candidate under one
  environment; freeze the failure node-ID sets, durations and tool versions.
- Run guardrails and record all ten outcomes.
- Inventory the complete session-19 runtime package. Build a deterministic ZIP
  and manifest containing reports, CSV, Godot logs, process logs and hashes.
- Store the evidence on durable Windows storage and attach or otherwise escrow
  it outside any ephemeral reviewer container.
- Reconcile the 81-file runtime tree with the 83-file whole-session inventory.

Output: canonical checkpoint record, suite baseline, guardrail baseline and
durable evidence manifest. No physics or authority change.

STOP if the base differs, the session-19 package is incomplete, a hash cannot
be reproduced, the failure set differs without explanation, or an artefact
exists only in an ephemeral container.

### P1R1 - Independent Finding Requalification

- Rebuild the runtime call graph for all ten P1s from the canonical source.
- Inventory every tracked GDScript, Python, PowerShell, shell and batch script
  that can load, execute, validate, package or publish motor behavior. Record
  entry point, caller, side effects, authority relevance and test coverage;
  do not sample the inventory.
- Parse or compile every in-scope script with its declared language runtime.
  Run the Godot parser/load/import gate separately from runtime fixtures, run
  Python bytecode compilation separately from pytest, and use the native parser
  for each retained command script. A missing parser or interpreter must be
  provisioned or the script must be proved outside motor scope; it cannot end as
  `NOT_RE_EVALUABLE`.
- Review program structure for dependency cycles, orphan entry points, hidden
  writers, duplicated side effects, parser/runtime ambiguity and violations of
  the declared module and state-ownership boundaries. Static text inspection
  may locate candidates but cannot close a parser or runtime claim.
- Reclassify every P1 as `OPEN`, `PARTIAL`, `CLOSED`, `SUPERSEDED` or
  `NOT RE-EVALUABLE`, with code and evidence references.
- Define a failing regression or executable negative control before any code
  fix. A text grep alone is insufficient for a runtime claim.
- Freeze one acceptance contract per P1, including commands, artefacts and STOP
  conditions.
- Split P2 observations from demonstrated authority risks.

Output: current P1 ledger, signed-off acceptance matrix, complete script
inventory, parser/compile ledger and structural finding register. Evidence only;
any discovered defect receives an owning remediation lane before P1R8.

### P1R2 - Tick-Boundary Ownership

- Eliminate or relocate hidden post-physics auxiliary-service synchronization
  so configuration and service state have one explicit boundary before the
  physical step.
- Prove call order through runtime instrumentation at the first tick, steady
  ticks and finalization.
- Prove that default-OFF and inactive paths are behaviorally identical to the
  canonical candidate.
- Add a runtime regression that fails when synchronization returns after the
  physical mutation boundary.

Acceptance: no hidden post-physics configuration writer; deterministic ordering
across repeated runs; no changed physical outputs when the repaired path is
inactive; no new suite or guardrail failure.

### P1R3 - O2 Writer Ownership And Clamp Boundary

The first P1R3 session is design and falsification:

- Reconstruct all six O2 writer subsystems, aggregate clamps, lower/upper/bulk
  fields and read-only consumers.
- Account for every O2 delta exactly once per tick and name the owner of each
  accepted mutation.
- Specify transaction order, fallback behavior and degenerate-zone semantics.
- Do not implement until the ownership matrix and negative controls pass review.

Implementation follows only when separately authorized:

- Route O2 mutation through the approved owner boundary without enabling any
  new authority path or changing defaults.
- Keep clamps at the declared ownership boundary and expose rejected/accepted
  mass separately.
- Prove non-negative finite state, no double write, conservation closure and
  deterministic replay on the fixed non-HVAC corpus.

Acceptance: every O2 writer is owned or read-only; per-step and cumulative mass
close within the predeclared numerical contract; aggregate clamps cannot hide a
writer conflict; no expected, tolerance, baseline or case change.

### P1R4 - Diagnostic Flag Activation Or Retirement

- Inventory the 112 default-OFF diagnostic flags from source and runtime entry
  points; do not assume the session-18 count still holds.
- Assign every flag one disposition: runtime-backed, parser/load-only,
  text-contract-only, dead/retire, or out of runtime scope.
- Add a minimal activation fixture for each retained flag that requires a
  service or changes an observable diagnostic path.
- Retire dead flags only through separately reviewable removals. Never flip a
  default to obtain coverage.

Acceptance: every in-scope retained flag is activation-tested at runtime or has
an approved retirement commit; text contracts are not reported as runtime
evidence; inactive output remains unchanged.

### P1R5 - Mutation Trust And Reference Provenance

- Rebuild the mutation harness so each tracked mutant executes at least one
  required check and is detected by a negative control.
- Fail closed on zero evaluated checks, missing reports, stale inputs, duplicate
  names and truncated manifests.
- Give every required reference check an explicit case, source, measurement
  layer and artefact provenance record.
- Requalify the three Ghanekar demotions as validation-truth controls. Do not
  make the empirical measurements pass and do not implement the D1 probe.
- Close the A15 P1s only if the authority risk is removed by truthful non-gating
  classification and complete primary-source provenance. Each empirical gap
  must receive a final `FIXED`, `FALSE_POSITIVE` or
  `VERIFIED_MODEL_LIMITATION` disposition; it may not remain provisional or
  open as research debt.

Acceptance: no mutant can produce a vacuous PASS; all required checks have
machine-readable provenance; the three Ghanekar contracts remain visible and
unchanged in expected/tolerance while their provisional status is resolved by
independent evidence; no baseline or case changes.

P1R5 owns the closure decision for `A15-P1-001` and `A15-P1-002`. P1R7 verifies
that disposition against the historical evidence but does not silently replace
or duplicate the owner decision. A new contradiction in P1R7 reopens the named
P1 explicitly.

P1R4 and P1R5 are large because their inventories may contain about 112 flags
and 350 required checks respectively. Their scope cannot be sampled, reduced or
declared representative to manufacture a PASS. They continue across uniquely
numbered sessions until every item has a final disposition. Unclassified work
stays in the active lane; it does not disappear into P2 backlog.

### P1R6 - Passive Diagnostic Performance

- Reproduce OFF and full-passive timings on the same machine, Godot binary,
  case, process state and command, using at least three sequential pairs.
- Measure median wall time, spread, peak memory where available, calls per step
  and output volume.
- Attribute cost by diagnostic component before optimizing.
- Optimize only passive diagnostic work. Do not remove evidence required by a
  gate and do not trade correctness for speed.

Acceptance: full passive execution fits the frozen 240 s representative budget
and no unexplained paired regression exceeds 20 percent. If hardware prevents a
valid comparison, establish a valid like-for-like environment and rerun it; do
not manufacture a PASS from cross-machine timings or leave the finding
`NOT_RE_EVALUABLE` at clean closure.

### P1R7 - CFAST And Historical Evidence Disposition

- Reproduce the two non-HVAC internal-baseline warnings:
  `cfast_two_floor_stairwell` and `cfast_multi_fuel_couch_tv`.
- Separate parser, instrumentation, stale artefact and model-disagreement causes.
- Fix only a demonstrated implementation or evidence defect. Do not alter CFAST
  truth, cases, baselines, expected values or tolerances.
- Reconcile the bedroom O2 and kitchen FED historical claims with current
  reports and primary-source provenance, verifying the P1R5 owner disposition.
- Reassess the historical Godot import failure. It may close as a permanent
  historical limitation only if no current authority claim depends on the
  unavailable bisection and current behavior has complete reproducible evidence.

Acceptance: both CFAST cases complete without an unexplained internal-baseline
failure. Historical claims are reproducible or are retired from authority
evidence through independent review without deleting their record. No open
authority blocker or `NOT_RE_EVALUABLE` classification survives clean closure.

### P1R8 - Fresh Runtime Matrix And Independent Clean Closure

- Use an independent reviewer who did not author the latest remediation.
- Run the fixed 18-case corpus sequentially with Godot 4.7.1 console/headless,
  explicit per-case logs and complete manifests. HVAC rows remain observational.
- Re-run parser/load tests, runtime fixtures, mutation controls, the Python suite
  and all guardrails from a clean tree.
- Compare contract fields, cases, baselines, CFAST truth, suite failures,
  determinism, performance and process cleanup against P1R0.
- Reconcile all ten P1s and all program exit criteria.

Output: independent closure report with separate verdicts for program closure,
integration to `main`, and runtime authority.

Completion of P1R8 never grants H3.2b4, H3.3 or runtime authority. The user must
make that decision after reading the closure report.

P1R8 starts only when the working candidate already meets every clean exit
criterion. If independent review finds a defect, the relevant P1R lane reopens,
receives the next session number and returns to P1R8 only after remediation.

## 7. Runtime Rules

- Godot must be `4.7.1.stable.official.a13da4feb`, console/headless only.
- Runs are sequential. GUI/editor execution is forbidden.
- Each command has an explicit log, timeout and expected row/artifact count.
- A popup, crash, timeout, compile error, truncated manifest, wrong row count,
  stale output or residual Godot process invalidates the run.
- Import is a separate explicit command and may run only when the session prompt
  authorizes it.
- A runtime report must identify the engine, commit, case blob, command, start
  and end times, exit code and hashes.
- Unknown, absent and non-finite values must remain distinguishable; none may be
  silently serialized as a physical zero.

## 8. Change And Commit Rules

- One named P1 or tightly coupled P1 group per remediation commit.
- A failing regression or negative control precedes the fix.
- Every tracked edit is shown and audited before commit.
- No amend, rebase, force push or history rewrite after evidence is recorded.
- Commit and push are separate user approvals. Pushes go to review branches
  unless `main` is explicitly authorized.
- No broad refactor, style cleanup, opportunistic P2 fix or generated metadata
  churn.
- Protected paths and contract fields are checked before and after every commit.
- D0 and D1 paths are rejected by scope checks.

## 9. Evidence Durability

Every session writes under:

`runs/motor_post_audit_p1_remediation_sessionNN/`

The minimum package is:

- `STOP_REPORT.md`;
- a machine-readable ledger JSON;
- command and environment manifest;
- file and tree hashes;
- test node-ID result sets;
- runtime logs and reports when Godot runs;
- process inventory at entry and closure;
- diff and protected-scope audit when files change.

Hash labels are mandatory and use these conventions:

- `worktree_sha256` is SHA-256 over the exact bytes present at the recorded
  path, with byte length, encoding and line-ending mode recorded for text.
- `blob_oid` is the Git object ID after repository normalization. It is recorded
  separately and is never compared with `worktree_sha256`.
- Runtime and gitignored artefacts use exact-byte `worktree_sha256`; no newline,
  BOM or encoding normalization is allowed before hashing.
- Tree manifests are sorted bytewise by the UTF-8 encoding of the forward-slash
  relative path, equivalent to `LC_ALL=C` ordering: no locale collation and no
  case normalization. They contain UTF-8
  `relative_path<TAB>lowercase_exact_byte_sha256<LF>`. The manifest itself has
  an exact-byte SHA-256 and byte length.
- A report that says only `hash` or compares hashes from different conventions
  is incomplete and triggers STOP.

Gitignored evidence is not durable merely because it existed in a remote
container. Before session closure it must exist in the Windows workspace or be
attached as a complete archive with a verified SHA-256. Missing durability is a
STOP, not a documentation footnote.

## 10. Global STOP Conditions

STOP the current phase without adapting the plan when any of these occurs:

1. The checkpoint, parent chain, remote provenance or worktree is unexpected.
2. A protected case, baseline, expected value, tolerance, minimum or maximum
   changes.
3. A default flag changes or a new authority path becomes active.
4. D0, D1, H3.2b4, H3.3 or HVAC work enters the diff.
5. A new test failure appears outside the named negative control.
6. Guardrails fall below 10/10 without the named P1 being the demonstrated
   cause.
7. Runtime execution is invalid under Section 7.
8. Evidence exists only in an ephemeral environment or a manifest is
   incomplete.
9. A proposed fix needs corpus expansion, baseline regeneration or tolerance
   tuning.
10. The session cannot separate physical behavior from instrumentation or text
    inspection.

A STOP or `NO-GO` pauses the current lane. It does not close the program or
authorize an adjacent fix. The next authorized session resumes the owning lane
with the same unresolved finding.

## 11. Exit Criteria

The program is complete after P1R8 when:

1. The canonical checkpoint and all remediation commits have durable remote
   provenance.
2. Session-19 evidence and all new runtime evidence are complete and hashed.
3. All ten entry P1s and every newly discovered finding are independently
   `FIXED`, `FALSE_POSITIVE`, `VERIFIED_MODEL_LIMITATION` or closed through a
   user-approved scope exclusion.
4. There is no open, partial, pending, unknown or not-reevaluable P0, P1, P2 or
   P3 in the in-scope inventory.
5. Tick ordering and O2 ownership have executable runtime proof.
6. Every retained in-scope diagnostic flag is activation-tested or approved for
   retirement.
7. Mutation tests cannot pass vacuously and required checks have explicit
   provenance.
8. Performance meets its frozen acceptance contract under a reproducible
   like-for-like environment.
9. The two non-HVAC CFAST failures are resolved without baseline, expected or
   tolerance changes.
10. Every in-scope script parses or compiles under its declared runtime; the
    script inventory is complete; and the structural review has no unresolved
    ownership, dependency, entry-point or side-effect finding.
11. The fixed corpus is reproducible; the complete Python suite has zero
    failures and zero errors; every skip has an explicit valid reason;
    guardrails are 10/10; required validation has zero failed required checks
    without a `VALID_GAP` exception; and zero Godot processes remain.
12. Every non-gating gap has a final evidenced disposition and no gap remains
    `OPEN`, `PARTIAL`, `PENDING`, `UNKNOWN` or `NOT_RE_EVALUABLE`.
13. An independent reviewer issues `CLEAN GO` for the audit and separate
    integration and authority verdicts. Runtime authority remains a separate
    user decision.
14. The user has received the final STOP gate and chosen the next action.

## 12. Completion And Resume Rule

There is no session cap. Sessions continue with unique increasing numbers from
31; numbers are never silently reused or renumbered. Failed preflights and STOP
gates retain their session number in the permanent record and never change the
checkpoint.

The program remains active until every clean exit criterion is met. New findings
are added to the inventory, assigned an owner lane and resolved before another
P1R8 review. No severity class moves automatically to backlog.

After closure, only the user may choose to:

- integrate approved remediation commits;
- authorize H3.2b4/H3.3 under documented constraints; or
- stop or redirect motor development.

Silence, a green suite, 10/10 guardrails or completion of this plan is not
runtime-authority authorization.
