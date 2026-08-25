# P1R1 UID Integrity Remediation

Date: 2026-08-25

Status: COMPLETE FOR THE UID INTEGRITY SUBGATE; P1R1 REMAINS INCOMPLETE

## 1. Scope And Boundary

This record closes the four UID-integrity findings discovered during the P1R1
parser and structure review. It does not close P1R1, start P1R2, grant runtime
authority, or authorize H3.2b4 or H3.3.

The implementation checkpoint is:

- branch: `codex/p1r1-uid-integrity-remediation`;
- commit: `a3d4fbe034675ee5127488b46a7293524cd166c7`;
- parent: `65d04d8e40d9916d4f5f586ed5c012d0a6e1f21a`;
- fixed audit comparison base:
  `ed2b6c0a1d458ff6edb92739cea27117195aa5cf`.

No push, merge, rebase, amend, force operation, case change, baseline change,
expected-value change, tolerance change, min/max change, default change,
physics change, authority change, or runtime-flag change is part of this lane.
D0 remains excluded and not reverted, D1 remains frozen, and HVAC remains
deferred and outside acceptance.

## 2. Findings And Disposition

| ID | Severity | Final status | Evidence-based disposition |
|---|---|---|---|
| `P1R1-UID-001` | P1 | `FIXED` | Removed the reintroduced legacy `sim/models/OpeningModel.gd` source and sidecar. The canonical `sim/building/OpeningModel.gd` source and UID are unchanged. |
| `P1R1-UID-002` | P1 | `FIXED` | Removed the reintroduced legacy `sim/SmokeModel.gd` source and sidecar. The canonical `sim/smoke/SmokeModel.gd` source and UID are unchanged. |
| `P1R1-UID-003` | P2 | `FIXED` | Removed the byte-identical legacy `sim/models/default_fire_model.tres`. The canonical `sim/resources/default_fire_model.tres` is unchanged. |
| `P1R1-EVID-001` | P2 | `FIXED` | Preserved the historical session-38 record, documented its collation error, and added a versioned scanner and regression that use bytewise UTF-8 path ordering. |

The remediation deletes exactly these five legacy owners:

- `sim/models/OpeningModel.gd`;
- `sim/models/OpeningModel.gd.uid`;
- `sim/SmokeModel.gd`;
- `sim/SmokeModel.gd.uid`;
- `sim/models/default_fire_model.tres`.

No canonical owner was renamed, edited, assigned a new UID, hidden with
`.gdignore`, or replaced by a compatibility shim.

## 3. Permanent Fail-Closed Contract

The new `scripts/simulation/audit_godot_primary_uids.py` scanner uses
`git ls-files -z` and the Python standard library to inspect tracked
`*.gd.uid`, `*.tres`, and `*.tscn` primary owners. It parses sidecars and
resource headers strictly, does not confuse `ext_resource` references with
ownership, orders paths by their UTF-8 bytes, writes atomic JSON, and exits
nonzero for malformed or duplicate primary ownership.

`tests/test_audit_godot_primary_uids.py` contains 23 isolated parser and
ordering contracts plus one repository assertion requiring zero malformed
records and zero duplicate primary UID groups.

The unchanged repository assertion was demonstrated red before the deletion:

- 210 candidates;
- 141 primary records;
- zero malformed records;
- exactly three duplicate groups:
  `uid://ba5a2442c5xqj`, `uid://bxk6dy2teojx`, and
  `uid://dq61t07vrw0c7`.

After deleting only the five authorized paths, the same contract is green:

- 207 candidates;
- 138 primary records;
- zero malformed records;
- zero duplicate groups;
- primary-owner tree SHA-256:
  `f488e54016bcf43e39b0196ae62bac6dad674f5856d7e6179902b0fe5fb34b6c`.

All 24 scanner tests pass. The red and green outputs and both exact-byte JSON
inventories are retained under
`runs/motor_post_audit_p1_remediation_session45/`.

## 4. Historical Ordering Correction

Session 38 remains an immutable historical record. Its declared UID tree
SHA-256
`e4dc4fc14526b67ab724f7c5e3e132f8d58af4b00a44f36e91d9bb4d9ea3d0b6`
was produced with PowerShell case-sensitive collation, not the binding
bytewise UTF-8 ordering contract.

Reordering the same session-38 records bytewise by UTF-8 path yields
`0d1150f6777b546acc21e037ec5165eccc8118d71a2a169c412604b55055f7be`.
The old artefact is not rewritten. This record and the new scanner make the
semantic difference durable and executable.

## 5. Godot Import Gate

Three fresh isolated imports used only
`Godot_v4.7.1-stable_win64_console.exe --headless --path <worktree> --import`.
They ran sequentially with isolated APPDATA roots and explicit logs:

| Run | Worktree / APPDATA | Wall time | Exit | Errors | Warnings | Residual processes |
|---|---|---:|---:|---:|---:|---:|
| A1 | A / A | 24.939 s | 0 | 0 | 0 | 0 |
| A2 | A / A | 4.777 s | 0 | 0 | 0 | 0 |
| B | B / B | 18.948 s | 0 | 0 | 0 | 0 |

All three contain 186 `*.gd.uid` files, 3,665 exact bytes, and the same UID
tree SHA-256:
`ed5a9da6d86129ec3416e4da243ec10206b8134d1804fdeecb7deb5d295d2c38`.

A2 left the A worktree's 58 generated sidecars byte-identical and introduced
no additional path. A1 and B produced identical generated-path sets and
byte-identical stdout. Every per-file path, UID text, byte length, and SHA-256
matches across A1, A2, and B. Independently archived A and B UID sets are
byte-identical at 34,077 bytes with 186/186 round-trip entries and SHA-256
`413f44f15bb2b73633ed36e73667fe9af349f258b95fcdab33a463f61af4cadd`.

Both generated global class caches refer to OpeningModel and SmokeModel only
through their canonical paths. No legacy path appears.

## 6. Tests And Protected Contracts

- Focused Phase 3 fixtures and contracts: 159 passed. This count is not used
  as a substitute for the separate Godot import evidence above.
- UID scanner contracts: 24 passed.
- Full Python suite after implementation: 18 failed, 2,455 passed, 42
  subtests passed. The 18 failure node IDs are exactly the frozen entry set;
  there are zero new failures and zero hidden or removed baseline failures.
- Validation guardrails remain 10/10 PASS with six entry-state `VALID_GAP`
  records and 76 known gaps.

The full-suite pass count rises by 24 because this commit adds exactly 24 UID
scanner tests. The failure-set comparison is by canonical node ID, not count.

The implementation commit changes exactly seven paths: the scanner, its test,
and the five authorized deletions. `reference_checks.json`, per-case reports,
cases, baselines, CFAST truth, expected values, tolerances, min/max fields,
defaults, physics, authority, runtime flags, and all three canonical owners are
unchanged.

The session-41 inventory arithmetic described deletion-only scope: 2,299 to
2,294 tracked files, 444 to 442 tracked scripts, and 188 to 186 tracked
GDScripts. The implemented candidate also adds two tracked Python audit files,
so its final totals are 2,296 tracked files, 444 tracked scripts, 186 GDScripts,
240 Python files, 16 PowerShell files, and two batch files. This is an explained
scope effect, not an adapted acceptance target.

## 7. Rollback And Resume Gate

Rollback is by `git revert`, never history rewrite. Reverting the implementation
restores the five legacy owners and intentionally makes the permanent UID
contract red again; Godot import is then NO-GO until the duplicate ownership is
resolved.

The UID-integrity subgate is complete and all four findings above are `FIXED`.
P1R1 remains incomplete and resumes at the structural inventory and finding
requalification work already required by the binding plan. P1R2 remains
NO-GO and has not started. Runtime authority, H3.2b4, and H3.3 remain frozen and
require separate user decisions after an independent clean closure.
