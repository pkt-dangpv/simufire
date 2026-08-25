# P1R1 Session-36 Manifest Collation Correction

Date: 2026-08-25

Status: REMEDIATED, PENDING INDEPENDENT REVIEW

Finding: `P1R1-EVID-002`

## Scope

Session 47 found that the session-36 artifact manifest's 18 exact file hashes
are valid but its aggregate tree does not use the ordering stated by its own
contract. This correction preserves the historical evidence and separates the
two meanings explicitly. It changes no physics, authority, case, baseline,
expected value, tolerance, min/max, default, report, or historical run file.

## Source Provenance

The preserved source is:

- path:
  `runs/motor_post_audit_p1_remediation_session36/artifact_manifest.json`;
- byte length: 3,451;
- exact-byte SHA-256:
  `4efd8b2d23c644e8baed9c57218a33b4326c78658f5ee468538336fb1b4fcf2f`;
- listed files: 18;
- listed source bytes: 1,158,585;
- individual verification: 18/18 exact.

The historical manifest remains byte-identical and is not replaced by this
record.

## Correction

The manifest claims `ordinal/bytewise UTF-8 relative path with LF`, but its
file array places uppercase `STOP_REPORT.md` after lowercase paths. Hashing the
records in that stored order reproduces the historical value:

`e6d68e1578e93573774bd6e5a8f992c1b2a3b82a617d41f9ec15b33a4a4da703`

Sorting the same 18 paths by their UTF-8 bytes and hashing
`relative_path<TAB>lowercase_exact_byte_sha256<LF>` produces:

`33187f85215930be889b07d632d8ad53465913fecba552d6a84e213af548eec4`

The first hash is a reproducible historical manifest-order tree. The second is
the corrected bytewise UTF-8 tree. They are not interchangeable.

The machine-readable companion
`P1R1_SESSION36_MANIFEST_COLLATION_CORRECTION.json` embeds all 18 original
records in historical order and both complete hashes, so the correction does
not depend on prose or truncated digests.

## Executable Control

`scripts/simulation/verify_exact_byte_artifact_manifest.py` verifies exact file
lengths and SHA-256 values independently from aggregate ordering. It supports
the manifest field variants already present in sessions 36, 40, 41, 45, and
47, rejects ambiguous schemas and unsafe paths, and always recomputes the
aggregate tree in UTF-8 byte order.

The fail-first matrix is deliberate:

- session 36: exit 1, 18/18 files exact, zero file mismatches, tree ordering
  FAIL with both hashes visible;
- sessions 40, 41, 45, and 47: exit 0 and bytewise tree PASS.

Unit contracts freeze case-sensitive ordering, exact-byte failures, missing
files, path traversal rejection, alias handling, duplicate paths, atomic JSON,
and the tracked correction record.

## Inventory Effect

The remediation adds four tracked files: the verifier, its test, and the two
correction records. It therefore moves the committed candidate inventory from
2,297 to 2,301 tracked files and from 444 to 446 tracked scripts. GDScript remains 186;
Python moves from 240 to 242; PowerShell remains 16 and batch remains two.
P1R1-LANG must re-freeze these post-remediation counts rather than retain its
pre-remediation expectation silently.

The 2,297 starting total independently exposes `P1R1-EVID-003`: the session-45
UID remediation record stated 2,296 because it counted before its own new
documentation file was committed. That existing record is annotated in place;
the original claim remains visible in Git history. This documentary correction
also remains pending independent review.

## Disposition

This remediation does not mark `P1R1-EVID-002` `FIXED` by self-certification.
Its state is `REMEDIATED_PENDING_INDEPENDENT_REVIEW`. An independent review
must verify the source manifest SHA-256, all 18 records, both reconstructed tree
hashes, the fail-first matrix, and protected scope. Only then may the finding
become `FIXED` and P1R1-LANG restart.

P1R1 remains incomplete. P1R2, H3.2b4, H3.3, D1, and runtime authority remain
frozen. D0 remains excluded and not reverted. HVAC remains deferred and out of
scope.
