# P1R8 O2-OWNER-001 Final Disposition

Date: 2026-09-09

## Disposition

`O2-OWNER-001`: **VERIFIED_MODEL_LIMITATION**.

The current legacy fire path does not provide a conservative, coupled two-zone
oxygen owner for every topology. In rooms with an open interior connection,
combustion can select lower-zone oxygen while the legacy exchange path debits
bulk oxygen. This inconsistency is demonstrated by source tracing and runtime
evidence from sessions 114-123.

This is a final audit disposition, not a statement that the physical limitation
has been repaired. It closes the open audit classification by naming the
limitation and its consequences. It does not make a failed validation check
pass, alter a contract, or grant authority.

## Evidence

- The fail-first owner fixture demonstrates the open-interior mismatch and the
  distinct sealed-room path.
- Candidates A, B and C were tested and rejected because direct selector/debit
  alignment changed the established trajectory, failed exact transaction
  accounting, or promoted an unqualified ownership path.
- Z0 proved that a pure lower-to-upper conservative evaluator can close its
  local fuel, oxygen and product balances.
- Z1 proved default-OFF byte identity in all six controls. Its first enabled
  control exceeded the established 900 s timeout, so it supplied no admissible
  physical requalification evidence.
- The complete Z0/Z1 candidate was preserved under
  `runs/motor_post_audit_p1_remediation_session124/` and withdrawn from the
  runtime candidate before this disposition was recorded.

Primary records:

- `runs/motor_post_audit_p1_remediation_session114/ROOT_CAUSE_NARROWING.md`
- `runs/motor_post_audit_p1_remediation_session115/STOP_REPORT.md`
- `runs/motor_post_audit_p1_remediation_session116/O2_OWNER_CANDIDATE_B_DESIGN_STOP.md`
- `runs/motor_post_audit_p1_remediation_session117/STOP_REPORT.md`
- `runs/motor_post_audit_p1_remediation_session118/STOP_REPORT.md`
- `runs/motor_post_audit_p1_remediation_session119/STOP_REPORT.md`
- `runs/motor_post_audit_p1_remediation_session120/STOP_REPORT.md`
- `runs/motor_post_audit_p1_remediation_session121/O2_OWNER_CONSERVATIVE_TWO_ZONE_DESIGN.md`
- `runs/motor_post_audit_p1_remediation_session122/Z0_STOP_REPORT.md`
- `runs/motor_post_audit_p1_remediation_session123/Z1_ON_TIMEOUT_STOP.md`

## Frozen Consequences

- Runtime authority: NO-GO.
- H3.2b4: NO-GO.
- H3.3: NO-GO.
- HVAC: excluded.
- `fire_o2_canonical_enabled`, `fire_o2_upper_throttle_enabled` and all other
  authority/default flags remain unchanged.
- Cases, baselines, expected values, tolerances, minima and maxima remain
  unchanged.

P1R8 subsequently completed the separate contractual disposition lane. The six
former required failures and all 78 non-gating failures remain visible with
final dispositions; this did not repair O2 ownership or grant authority. Any
later two-zone O2 implementation is a new motor-development programme with its
own Z2-Z4 gates, not a continuation required to complete this audit.

## Review Boundary

The user approved this limitation disposition to stop converting the audit into
an open-ended physics implementation. P1R8 still requires an independent final
review before `CLEAN GO`; that reviewer must verify this evidence and may reject
the disposition if it overstates what the records prove.
