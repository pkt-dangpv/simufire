# P1R1 Evidence Manifest Verifier Fail-Closed Remediation

Date: 2026-08-25

Status: REMEDIATED, PENDING INDEPENDENT REVIEW

Finding: `P1R1-EVID-004`

## Scope

Session 49 demonstrated that the exact-byte artifact verifier could return
PASS while a manifest declared false aggregate counters or unsupported
ordering semantics. This remediation changes only the verifier, its permanent
tests, this record, and the current handoff. It does not rewrite any historical
manifest or evidence file.

## Fail-First Evidence

The session-49 negative controls use the valid session-40 file list and tree.
No source artifact was changed.

- `file_count` 26 -> 999 and `total_bytes` 552,982 -> 0 returned exit 0 and
  PASS.
- `ordering` -> `case-insensitive locale collation` and `tree_contract` ->
  `not-the-binding-contract` returned exit 0 and PASS.

The prior verifier recomputed correct values but did not compare them with the
declarations it had read. Its result therefore hid the contradiction.

## Remediation

The verifier now:

- validates a non-empty manifest schema;
- validates supported `ordering`, `tree_ordering`, `tree_contract`,
  `hash_contract`, and `hash_convention` declarations;
- requires a supported bytewise ordering and tree contract;
- compares declared `file_count` when present;
- compares either `total_bytes` or `source_total_bytes` when present and rejects
  ambiguous dual declarations;
- preserves the session-36 integer-valued JSON float as a valid legacy numeric
  representation;
- compares `tree_manifest_bytes` when present;
- reports file mismatches separately from metadata mismatches so aggregate
  failures cannot corrupt the verified-file count;
- retains distinct exit codes: 0 PASS, 1 evidence mismatch, and 2 operational
  or unsupported contract.

Thirteen new test instances freeze the fail-first defects, historical aliases,
legacy numeric compatibility, tree-manifest length, unsupported metadata, and
missing-contract behavior. The complete verifier file now has 26 passing test
instances.

## Historical Compatibility Matrix

| Session | Exit | Files | File mismatches | Metadata mismatches | Bytewise tree |
|---|---:|---:|---:|---:|---|
| 36 | 1 | 18/18 | 0 | 0 | FAIL, expected historical defect |
| 40 | 0 | 26/26 | 0 | 0 | PASS |
| 41 | 0 | 8/8 | 0 | 0 | PASS |
| 45 | 0 | 68/68 | 0 | 0 | PASS |
| 47 | 0 | 5/5 | 0 | 0 | PASS |
| 48 | 0 | 32/32 | 0 | 0 | PASS |
| 49 | 0 | 14/14 | 0 | 0 | PASS |

The isolated counter mutation now returns exit 1 with exactly two metadata
mismatches. The isolated unsupported ordering mutation returns exit 2 before
producing a result JSON. No historical acceptance value was adapted.

## Inventory And Protected Scope

This remediation adds one tracked documentation file. Its post-remediation
inventory is therefore 2,302 tracked files and 446 scripts: 186 GDScripts, 242
Python files, 16 PowerShell files, and two batch files.

No path under physics, authority, cases, baselines, reports, CFAST truth, or
runtime resources changes. Expected values, tolerances, min/max fields,
defaults, validation check requirements, and historical evidence bytes remain
unchanged. Godot is not required because no GDScript or runtime path changes.

## Disposition

This session does not self-certify its own remediation. `P1R1-EVID-004` is
`REMEDIATED_PENDING_INDEPENDENT_REVIEW`. EVID-002 and EVID-003 remain pending
the same reviewer because session 49 did not satisfy separate-author
independence.

Only a reviewer who did not author this remediation may mark the three
findings FIXED and reopen P1R1-LANG. P1R1 remains incomplete. P1R2, H3.2b4,
H3.3, D1, and runtime authority remain frozen. D0 remains excluded and not
reverted. HVAC remains deferred and out of scope.
