#!/usr/bin/env python3
"""Multi-parametric physical-coherence checker for SimuFire CSV logs.

Each rule encodes one invariant that must hold in every valid simulation,
regardless of scenario or configuration.  Rules skip gracefully when the
required columns are absent (older CSV schema).

Rules — first slice
-------------------
B1  Thermal inversion   temp_upper_c must not fall more than 10 °C below
                        temp_lower_c.  The upper (hot) layer is always warmer
                        than the lower (cool) layer in a two-zone model.

C1  FED arithmetic      fed == fed_co + fed_hcn + fed_hypoxia + fed_heat
                        (tolerance 0.001).  FED is defined as the sum of its
                        component integrals; any mismatch is an arithmetic bug.

C2  FED monotonicity    fed must never decrease (per room, ordered by time_s).
                        FED is a cumulative integral of dose — once accumulated,
                        dose cannot be "un-accumulated".

Rules — second slice
--------------------
A2  HRR without fuel    hrr_kw > 20 while fuel_remaining_MJ ≈ 0 and neither
                        fire_smoldering nor fire_latent_active is active.
                        A non-trivial fire cannot sustain itself with no fuel
                        and no latent combustion source.

A3  Regime/O2 mismatch  combustion_regime is FUEL_CONTROLLED or FULLY_DEVELOPED
                        while o2_upper < 0.05.  These regimes require an
                        adequately oxygenated combustion zone; critical upper-
                        layer O2 starvation is physically incompatible.

Rules — third slice
-------------------
D1  CO balance residual Per room/log-interval: the change in co_kg between
                        consecutive CSV rows must equal the change in
                        co_generated_kg_total + co_net_transport_kg_total
                        − co_exterior_removed_kg_total over the same interval.
                        Uses cumulative totals (not per-step fields) so the
                        check is invariant to log_interval vs timestep ratio.
                        co_exterior_removed_kg_total tracks CO removed by
                        ACH/infiltration, pressure-relief ventilation, species
                        purge, and post-fire purge.  Tolerance: 5 % of
                        abs(expected), floor 1 × 10⁻⁶ kg.  Severity: WARN
                        (promote to FAIL once validated clean on the full
                        reference suite).  Skipped gracefully when cumulative
                        total columns are absent (older CSV schema).

Rules — fourth slice
--------------------
E1  Fuel balance        Per room/log-interval: the change in solid_fuel_remaining_MJ
                        must equal −Δfuel_consumed_MJ_total (what was drawn
                        from the solid fuel tank).  Uses fuel_consumed_MJ_total
                        (cumulative) to be invariant to log_interval vs
                        timestep ratio.  fuel_consumed_MJ_step is NOT used
                        here (it only captures the last simulation step, not
                        the sum over all steps since the previous log entry).
                        Also flags if solid_fuel_remaining_MJ increases between rows
                        (solid fuel is monotonically decreasing once fire
                        starts).  Tolerance: 1 % of abs(expected), floor
                        1 × 10⁻⁶ MJ.  Severity: FAIL.

Rules — fifth slice
-------------------
S0  Smoke global        At every logged timestep: the sum of smoke_kg across
    conservation        all rooms plus smoke_in_transit_kg must equal
                        smoke_generated_total_kg − smoke_vented_total_kg
                        − smoke_deposited_total_kg.
                        smoke_in_transit_kg is smoke queued in the interior
                        transport delay buffer (removed from source room, not
                        yet delivered to target room at log time).
                        These engine-level accumulators are written to every
                        CSV row (same value repeated for all rooms).
                        Limitation: S0 is a global check and cannot detect
                        compensated inter-room transport errors (smoke created
                        in one room and destroyed in another cancel out).
                        Per-room S1 would require per-room smoke_generated/
                        vented/deposited/net_transport accumulators, which are
                        not yet instrumented.
                        Tolerance: 5 % of abs(expected), floor 0.01 kg.
                        Severity: FAIL.

Rules — sixth slice
-------------------
O2E1 Thornton cross-check Per room/log-interval: the change in o2_consumed_kg_total_all
                        must equal the change in hrr_kj_total × Thornton constant
                        (0.076 kg O2 / MJ = 7.6 × 10⁻⁵ kg O2 / kJ).
                        o2_consumed_kg_total_all is accumulated by OES across ALL
                        combustion O2 depletion paths (bulk, upper, lower, plume).
                        hrr_kj_total is accumulated by CombustionSystem as
                        hrr_kw × dt each step.  Both use the same room.hrr_kw, so
                        perfect agreement is expected under stable conditions; the
                        check acts as a cross-subsystem regression guard — if OES
                        or CombustionSystem ever reads a different HRR value, or
                        applies the wrong Thornton constant, the residual grows.
                        OES caps per-step consumption at 5 % of bulk O2 mass and
                        20 % of upper O2 mass, so delta_o2_all may fall below
                        delta_hrr × Thornton in severely O2-depleted conditions;
                        tolerance is set wide enough (5 %) to absorb this.
                        Tolerance: 5 % of abs(expected), floor 1 × 10⁻⁵ kg.
                        Severity: WARN.  Not gating.
                        Skipped when hrr_kj_total is absent (older CSV schema).

Rules — seventh slice
---------------------
O1  O2 bulk balance     Per room/log-interval: the change in O2 mass bulk
                        must equal the sum of tracked O2 fluxes:
                        Δo2_bulk = (o2[t] − o2[t−1]) × air_mass_kg
                        expected = −Δo2_consumed_bulk_kg_total
                                   + Δo2_exterior_net_kg_total
                                   + Δo2_net_transport_kg_total
                        residual = |Δo2_bulk − expected|
                        o2_consumed_bulk_kg_total tracks O2 removed by
                        combustion from the room bulk store (OES stoichiometric
                        path).  o2_exterior_net_kg_total and
                        o2_net_transport_kg_total are the cumulative ACH/
                        exterior and inter-room fluxes respectively.
                        Skips rows where fire_o2_mode_used is plume_lower or
                        plume_blend AND hrr_kw > 0.1 — in that mode room.o2
                        is derived from zone layers, not the bulk accumulator.
                        Tolerance: floor 1 × 10⁻³ kg (1 g), plus relative
                        1 % of the more conservative of |expected| or O2
                        available mass (o2[t−1] × air_mass_kg).
                        Severity: WARN.  Not gating.

Usage
-----
  # Check all rules:
  python scripts/simulation/check_physics_coherence.py path/to/sim_log.csv

  # Restrict to specific rules:
  python scripts/simulation/check_physics_coherence.py path/to/sim_log.csv --rules C1,C2

  # Filter to one room:
  python scripts/simulation/check_physics_coherence.py path/to/sim_log.csv --room-id 0

Exit codes
----------
  0  No FAIL findings (WARN findings alone do not raise exit 1)
  1  One or more FAIL findings
  2  Invocation error (CSV not found, etc.)
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


# ---------------------------------------------------------------------------
# Finding
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Finding:
    time_s: float
    room_id: str
    rule_id: str
    severity: str   # "FAIL" | "WARN"
    metric: str
    value: float
    reason: str

    def format(self) -> str:
        return (
            f"t={self.time_s:.1f}s  room={self.room_id}  "
            f"[{self.rule_id}/{self.severity}]  "
            f"{self.metric}={self.value:.4g}  {self.reason}"
        )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _float(row: dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        v = row.get(key, default)
        return float(v) if v not in (None, "", "nan") else default
    except (TypeError, ValueError):
        return default


def _has_cols(headers: set[str], required: set[str]) -> bool:
    return required.issubset(headers)


# ---------------------------------------------------------------------------
# Required columns per rule (used for graceful skip)
# ---------------------------------------------------------------------------

REQUIRED_COLS: dict[str, set[str]] = {
    "A2": {"hrr_kw", "fuel_remaining_MJ", "fire_smoldering", "fire_latent_active"},
    "A3": {"combustion_regime", "o2_upper"},
    "B1": {"temp_upper_c", "temp_lower_c"},
    "C1": {"fed", "fed_co", "fed_hcn", "fed_hypoxia", "fed_heat"},
    "C2": {"fed"},
    "D1": {"co_kg", "co_generated_kg_total", "co_net_transport_kg_total", "co_exterior_removed_kg_total"},
    "E1": {"solid_fuel_remaining_MJ", "fuel_consumed_MJ_total"},
    "O1": {"o2", "air_mass_kg", "o2_consumed_bulk_kg_total", "o2_exterior_net_kg_total", "o2_net_transport_kg_total"},
    "O2E1": {"o2_consumed_fire_kg_total", "hrr_kj_total"},
    "S0": {"smoke_kg", "smoke_generated_total_kg", "smoke_vented_total_kg", "smoke_deposited_total_kg", "smoke_in_transit_kg"},
}

ALL_RULES: tuple[str, ...] = ("A2", "A3", "B1", "C1", "C2", "D1", "E1", "O1", "O2E1", "S0")


# ---------------------------------------------------------------------------
# Rule A2 — HRR without fuel
# ---------------------------------------------------------------------------

_A2_HRR_MIN_KW = 20.0
_A2_FUEL_DEPLETED_MJ = 0.001


def _check_a2_hrr_no_fuel(rows: list[dict[str, str]]) -> list[Finding]:
    findings: list[Finding] = []
    for row in rows:
        hrr = _float(row, "hrr_kw")
        if hrr <= _A2_HRR_MIN_KW:
            continue
        fuel = _float(row, "fuel_remaining_MJ")
        if fuel >= _A2_FUEL_DEPLETED_MJ:
            continue
        smoldering = _float(row, "fire_smoldering")
        latent = _float(row, "fire_latent_active")
        if smoldering != 0.0 or latent != 0.0:
            continue
        findings.append(Finding(
            time_s=_float(row, "time_s"),
            room_id=row.get("room_id", "?").strip(),
            rule_id="A2",
            severity="FAIL",
            metric="hrr_without_fuel_kw",
            value=round(hrr, 3),
            reason=(
                f"hrr_kw={hrr:.1f} with fuel_remaining={fuel:.4f} MJ, "
                f"fire_smoldering=0, fire_latent_active=0"
            ),
        ))
    return findings


# ---------------------------------------------------------------------------
# Rule A3 — Regime/O2 upper mismatch
# ---------------------------------------------------------------------------

_A3_REGIMES_INCOHERENT: frozenset[str] = frozenset({"FUEL_CONTROLLED", "FULLY_DEVELOPED"})
_A3_O2_UPPER_CRITICAL = 0.05


def _check_a3_regime_o2_starvation(rows: list[dict[str, str]]) -> list[Finding]:
    findings: list[Finding] = []
    for row in rows:
        regime = row.get("combustion_regime", "").strip()
        if regime not in _A3_REGIMES_INCOHERENT:
            continue
        o2_upper = _float(row, "o2_upper", default=0.21)
        if o2_upper < _A3_O2_UPPER_CRITICAL:
            findings.append(Finding(
                time_s=_float(row, "time_s"),
                room_id=row.get("room_id", "?").strip(),
                rule_id="A3",
                severity="FAIL",
                metric="regime_o2_upper_starvation",
                value=round(o2_upper, 5),
                reason=(
                    f"combustion_regime={regime} while o2_upper={o2_upper:.4f} "
                    f"< {_A3_O2_UPPER_CRITICAL} (critical starvation threshold)"
                ),
            ))
    return findings


# ---------------------------------------------------------------------------
# Rule B1 — Thermal inversion
# ---------------------------------------------------------------------------

_B1_THRESHOLD_C = 10.0


def _check_b1_thermal_inversion(rows: list[dict[str, str]]) -> list[Finding]:
    findings: list[Finding] = []
    for row in rows:
        temp_upper = _float(row, "temp_upper_c")
        temp_lower = _float(row, "temp_lower_c")
        inversion = temp_lower - temp_upper      # positive = upper is colder
        if inversion > _B1_THRESHOLD_C:
            findings.append(Finding(
                time_s=_float(row, "time_s"),
                room_id=row.get("room_id", "?").strip(),
                rule_id="B1",
                severity="FAIL",
                metric="temp_inversion_c",
                value=round(inversion, 3),
                reason=(
                    f"temp_upper={temp_upper:.1f} C is {inversion:.1f} C "
                    f"below temp_lower={temp_lower:.1f} C"
                ),
            ))
    return findings


# ---------------------------------------------------------------------------
# Rule C1 — FED arithmetic
# ---------------------------------------------------------------------------

_C1_TOLERANCE = 0.001


def _check_c1_fed_sum(rows: list[dict[str, str]]) -> list[Finding]:
    findings: list[Finding] = []
    for row in rows:
        fed = _float(row, "fed")
        if fed == 0.0:
            continue    # no dose accumulated yet — nothing to verify
        component_sum = (
            _float(row, "fed_co")
            + _float(row, "fed_hcn")
            + _float(row, "fed_hypoxia")
            + _float(row, "fed_heat")
        )
        diff = abs(fed - component_sum)
        if diff > _C1_TOLERANCE:
            findings.append(Finding(
                time_s=_float(row, "time_s"),
                room_id=row.get("room_id", "?").strip(),
                rule_id="C1",
                severity="FAIL",
                metric="fed_sum_error",
                value=round(diff, 6),
                reason=(
                    f"fed={fed:.5f} != "
                    f"fed_co+fed_hcn+fed_hypoxia+fed_heat={component_sum:.5f}"
                ),
            ))
    return findings


# ---------------------------------------------------------------------------
# Rule C2 — FED monotonicity
# ---------------------------------------------------------------------------

_C2_TOLERANCE = 0.0005


def _check_c2_fed_monotone(rows: list[dict[str, str]]) -> list[Finding]:
    by_room: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_room[row.get("room_id", "?").strip()].append(row)

    findings: list[Finding] = []
    for room_id, room_rows in by_room.items():
        room_rows.sort(key=lambda r: _float(r, "time_s"))
        prev_fed = -1.0
        for row in room_rows:
            fed = _float(row, "fed")
            if prev_fed >= 0.0 and fed < prev_fed - _C2_TOLERANCE:
                delta = fed - prev_fed
                findings.append(Finding(
                    time_s=_float(row, "time_s"),
                    room_id=room_id,
                    rule_id="C2",
                    severity="FAIL",
                    metric="fed_decrement",
                    value=round(delta, 6),
                    reason=f"FED decreased {prev_fed:.5f} -> {fed:.5f} (delta={delta:.5f})",
                ))
            prev_fed = fed
    return findings


# ---------------------------------------------------------------------------
# Rule D1 — CO balance residual
# ---------------------------------------------------------------------------

_D1_ABS_FLOOR_KG = 1e-6
_D1_REL_TOL = 0.05


def _check_d1_co_balance_residual(rows: list[dict[str, str]]) -> list[Finding]:
    """Per-room CO mass balance using cumulative totals.

    Between consecutive CSV rows (which may span many simulation steps):
        Δco_kg       = co_kg[t] − co_kg[t−1]
        Δco_gen      = co_generated_kg_total[t] − co_generated_kg_total[t−1]
        Δco_trans    = co_net_transport_kg_total[t] − co_net_transport_kg_total[t−1]
        Δco_ext_rm   = co_exterior_removed_kg_total[t] − co_exterior_removed_kg_total[t−1]
        expected     = Δco_gen + Δco_trans − Δco_ext_rm
        residual     = |Δco_kg − expected|

    co_exterior_removed_kg_total accumulates all CO removed by ACH/infiltration,
    pressure-relief ventilation, outside-open species purge, and post-fire purge —
    paths that subtract from co_kg without going through co_net_transport_kg_total.

    Using cumulative totals (not per-step fields) makes the check invariant to the
    ratio of log_interval to simulation timestep: per-step fields capture only the
    last step, but totals accumulate all steps between log entries.

    Tolerance: 5 % of abs(expected), floor 1 × 10⁻⁶ kg.
    Severity: WARN — promote to FAIL once validated clean on the full suite.
    """
    by_room: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_room[row.get("room_id", "?").strip()].append(row)

    findings: list[Finding] = []
    for room_id, room_rows in by_room.items():
        room_rows.sort(key=lambda r: _float(r, "time_s"))
        prev_co_kg: float = _float(room_rows[0], "co_kg")
        prev_gen_total: float = _float(room_rows[0], "co_generated_kg_total")
        prev_transport_total: float = _float(room_rows[0], "co_net_transport_kg_total")
        prev_ext_rm_total: float = _float(room_rows[0], "co_exterior_removed_kg_total")
        for row in room_rows[1:]:
            co_kg = _float(row, "co_kg")
            gen_total = _float(row, "co_generated_kg_total")
            transport_total = _float(row, "co_net_transport_kg_total")
            ext_rm_total = _float(row, "co_exterior_removed_kg_total")
            delta_co = co_kg - prev_co_kg
            delta_gen = gen_total - prev_gen_total
            delta_transport = transport_total - prev_transport_total
            delta_ext_rm = ext_rm_total - prev_ext_rm_total
            expected = delta_gen + delta_transport - delta_ext_rm
            residual = abs(delta_co - expected)
            # Reference magnitude: abs(expected), not abs(delta_co).
            # Using delta_co would inflate the threshold by the anomaly itself,
            # suppressing the very finding we are trying to raise.
            magnitude = max(abs(expected), _D1_ABS_FLOOR_KG)
            threshold = max(_D1_ABS_FLOOR_KG, _D1_REL_TOL * magnitude)
            if residual > threshold:
                findings.append(Finding(
                    time_s=_float(row, "time_s"),
                    room_id=room_id,
                    rule_id="D1",
                    severity="FAIL",
                    metric="co_balance_residual_kg",
                    value=round(residual, 9),
                    reason=(
                        f"delta_co={delta_co:.6g} kg  "
                        f"expected(dgen+dtrans-dext_rm)={expected:.6g} kg  "
                        f"residual={residual:.3g} kg  tol={threshold:.3g} kg"
                    ),
                ))
            prev_co_kg = co_kg
            prev_gen_total = gen_total
            prev_transport_total = transport_total
            prev_ext_rm_total = ext_rm_total
    return findings


# ---------------------------------------------------------------------------
# Rule E1 — Fuel balance residual
# ---------------------------------------------------------------------------

_E1_ABS_FLOOR_MJ = 1e-6
_E1_REL_TOL = 0.01


def _check_e1_fuel_balance_residual(rows: list[dict[str, str]]) -> list[Finding]:
    """Per-room fuel balance using cumulative totals.

    Between consecutive CSV rows (which may span many simulation steps):
        Δfuel_remaining  = solid_fuel_remaining_MJ[t] − solid_fuel_remaining_MJ[t−1]
        Δfuel_consumed   = fuel_consumed_MJ_total[t] − fuel_consumed_MJ_total[t−1]
        expected         = −Δfuel_consumed  (each MJ consumed depletes remaining by 1 MJ)
        residual         = |Δfuel_remaining − expected|

    fuel_consumed_MJ_total captures solid_fuel_demand_MJ accumulated over all
    simulation steps between log entries.  It is NOT hrr_kw*dt/1000 — pool
    release and backdraft contribute to HRR without drawing from the solid fuel
    tank that same step.

    Also flags: Δfuel_remaining > tolerance (solid fuel must be monotonically
    non-increasing once the fire is active; spontaneous fuel gain is unphysical).

    Tolerance: 1 % of abs(expected), floor 1 × 10⁻⁶ MJ.
    Severity: FAIL.
    Skipped gracefully when solid_fuel_remaining_MJ or fuel_consumed_MJ_total
    is absent (older CSV schema).
    """
    by_room: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_room[row.get("room_id", "?").strip()].append(row)

    findings: list[Finding] = []
    for room_id, room_rows in by_room.items():
        room_rows.sort(key=lambda r: _float(r, "time_s"))
        prev_remaining: float = _float(room_rows[0], "solid_fuel_remaining_MJ")
        prev_consumed_total: float = _float(room_rows[0], "fuel_consumed_MJ_total")
        for row in room_rows[1:]:
            remaining = _float(row, "solid_fuel_remaining_MJ")
            consumed_total = _float(row, "fuel_consumed_MJ_total")
            delta_remaining = remaining - prev_remaining
            delta_consumed = consumed_total - prev_consumed_total
            expected = -delta_consumed
            residual = abs(delta_remaining - expected)
            magnitude = max(abs(expected), _E1_ABS_FLOOR_MJ)
            threshold = max(_E1_ABS_FLOOR_MJ, _E1_REL_TOL * magnitude)

            if residual > threshold:
                findings.append(Finding(
                    time_s=_float(row, "time_s"),
                    room_id=room_id,
                    rule_id="E1",
                    severity="FAIL",
                    metric="fuel_balance_residual_MJ",
                    value=round(residual, 9),
                    reason=(
                        f"delta_remaining={delta_remaining:.6g} MJ  "
                        f"expected(-delta_consumed)={expected:.6g} MJ  "
                        f"residual={residual:.3g} MJ  tol={threshold:.3g} MJ"
                    ),
                ))
            # Monotone check: solid fuel cannot spontaneously increase.
            if delta_remaining > threshold:
                findings.append(Finding(
                    time_s=_float(row, "time_s"),
                    room_id=room_id,
                    rule_id="E1",
                    severity="FAIL",
                    metric="fuel_remaining_increased_MJ",
                    value=round(delta_remaining, 9),
                    reason=(
                        f"solid_fuel_remaining_MJ increased by {delta_remaining:.3g} MJ "
                        f"(solid fuel is monotonically non-increasing)"
                    ),
                ))
            prev_remaining = remaining
            prev_consumed_total = consumed_total
    return findings


# ---------------------------------------------------------------------------
# Rule O2E1 — Thornton cross-check (OES vs CombustionSystem)
# ---------------------------------------------------------------------------

_O2E1_THORNTON_KG_PER_KJ = 0.076 / 1000.0   # 7.6e-5 kg O2 / kJ
_O2E1_ABS_FLOOR_KG        = 1e-5
_O2E1_REL_TOL             = 0.05


def _check_o2e1_thornton_cross(rows: list[dict[str, str]]) -> list[Finding]:
    """Per-room Thornton stoichiometry cross-check.

    Between consecutive CSV rows (which may span many simulation steps):

        delta_hrr_kj   = hrr_kj_total[t] − hrr_kj_total[t−1]          [kJ]
        expected_o2    = delta_hrr_kj × 0.076 / 1000                   [kg]
        delta_o2_fire  = o2_consumed_fire_kg_total[t] − …[t−1]         [kg]
        residual       = |delta_o2_fire − expected_o2|

    hrr_kj_total is accumulated by CombustionSystem as hrr_kw × dt per step.
    o2_consumed_fire_kg_total is accumulated by OES as the "primary" O2
    depletion path: bulk when it ran (standard two-zone, homogeneous),
    otherwise the lower/plume/upper path that replaced it.  Exactly one
    Thornton unit per step — unlike o2_consumed_kg_total_all which double-
    counts in standard two-zone (bulk + upper both accumulate).

    The check acts as a cross-subsystem regression guard: if a future refactor
    causes OES or CombustionSystem to use a different HRR value, or applies
    the wrong Thornton constant, the residual grows.

    OES caps per-step consumption at 5 % of bulk O2 mass (plume/lower also
    capped), so delta_o2_fire may fall slightly below expected when O2-
    depleted.  Tolerance: 5 % of abs(expected), floor 1 × 10⁻⁵ kg.

    Skipped rows where both delta_hrr_kj and delta_o2_fire are zero (no fire,
    or pre-ignition steps).

    Severity: WARN.  Not gating.
    """
    by_room: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_room[row.get("room_id", "?").strip()].append(row)

    findings: list[Finding] = []
    for room_id, room_rows in by_room.items():
        room_rows.sort(key=lambda r: _float(r, "time_s"))
        prev = room_rows[0]
        for curr in room_rows[1:]:
            hrr_kj_curr   = _float(curr, "hrr_kj_total")
            hrr_kj_prev   = _float(prev, "hrr_kj_total")
            o2_fire_curr  = _float(curr, "o2_consumed_fire_kg_total")
            o2_fire_prev  = _float(prev, "o2_consumed_fire_kg_total")

            delta_hrr_kj  = hrr_kj_curr  - hrr_kj_prev
            delta_o2_fire = o2_fire_curr - o2_fire_prev

            # Skip pre-ignition and post-extinction rows where nothing changed.
            if delta_hrr_kj <= 0.0 and delta_o2_fire <= 0.0:
                prev = curr
                continue

            expected_o2 = delta_hrr_kj * _O2E1_THORNTON_KG_PER_KJ
            residual    = abs(delta_o2_fire - expected_o2)
            magnitude   = max(abs(expected_o2), _O2E1_ABS_FLOOR_KG)
            threshold   = max(_O2E1_ABS_FLOOR_KG, _O2E1_REL_TOL * magnitude)

            if residual > threshold:
                findings.append(Finding(
                    time_s=_float(curr, "time_s"),
                    room_id=room_id,
                    rule_id="O2E1",
                    severity="WARN",
                    metric="thornton_cross_residual_kg",
                    value=round(residual, 9),
                    reason=(
                        f"delta_hrr_kj={delta_hrr_kj:.4g} kJ  "
                        f"expected_o2(Thornton)={expected_o2:.4g} kg  "
                        f"delta_o2_fire(primary)={delta_o2_fire:.4g} kg  "
                        f"residual={residual:.3g} kg  tol={threshold:.3g} kg"
                    ),
                ))
            prev = curr
    return findings


# ---------------------------------------------------------------------------
# Rule O1 — O2 bulk mass balance
# ---------------------------------------------------------------------------

_O1_ABS_FLOOR_KG = 1e-3   # 1 g — below this residuals are floating-point noise
_O1_REL_TOL      = 0.01   # 1 % relative tolerance

# Modes where room.o2 is derived from zone layers (not the bulk accumulator).
_O1_LAYER_DERIVED_MODES: frozenset[str] = frozenset({"plume_lower", "plume_blend"})


def _check_o1_o2_bulk_balance(rows: list[dict[str, str]]) -> list[Finding]:
    """Per-room O2 bulk mass balance using cumulative totals.

    Between consecutive CSV rows (which may span many simulation steps):

        Δo2_bulk      = (o2[t] − o2[t−1]) × air_mass_kg              [kg]
        Δo2_consumed  = o2_consumed_bulk_kg_total[t] − …[t−1]
        Δo2_exterior  = o2_exterior_net_kg_total[t] − …[t−1]
        Δo2_transport = o2_net_transport_kg_total[t] − …[t−1]
        expected      = −Δo2_consumed + Δo2_exterior + Δo2_transport
        residual      = |Δo2_bulk − expected|

    o2_consumed_bulk_kg_total: cumulative O2 removed by combustion from the
    room bulk store (OES stoichiometric path, SF-O1C).  Does not include
    per-zone consumption (o2_upper, o2_lower) tracked in the _all columns.

    o2_exterior_net_kg_total: cumulative net O2 exchanged with the exterior
    (positive = room gained O2 from outside).  Includes ACH/infiltration,
    exterior openings, PPV, and pressure-venting.

    o2_net_transport_kg_total: cumulative net O2 transported between rooms
    (positive = room received from adjacent rooms).  Includes interior vanos,
    canonical doorway exchange, thermal counterflow, and GES background flow.

    Using cumulative totals (not per-step fields) makes the check invariant
    to the ratio of log_interval to simulation timestep.

    Skip conditions:
    1. rows where fire_o2_mode_used is 'plume_lower' or 'plume_blend' AND
       hrr_kw > 0.1 — room.o2 is zone-derived in those modes, bulk balance N/A.
       Non-fire rooms carry the label as a CombustionSystem artifact but use
       the true bulk value — include them.
    2. rows where hvac_exists == '1' — HvacSystem modifies room.o2 via lerpf
       (supply/return, HvacSystem.gd line 302) without contributing to any O2
       accumulator.  HVAC O2 instrumentation is out of scope; WARNs in
       scenarios with HVAC configured are expected and excluded here.

    Tolerance design:
      Floor: 1 × 10⁻³ kg (1 g).  The O1-D post-fix audit produced a maximum
      residual of 3.87 × 10⁻⁴ kg on the sealed diagnostic case; the floor is
      2.6× above that, providing margin for scenario-to-scenario variation
      while keeping all current validation cases clean.
      Relative: 1 % of the more conservative (smaller) of two references —
        ref_expected  = 1 % × |expected|   (proportional to the magnitude of
                                             tracked fluxes this interval)
        ref_available = 1 % × (o2[t−1] × air_mass_kg)  (proportional to the
                                             total O2 present at interval start)
      threshold = max(floor, min(ref_expected, ref_available)).
      When expected ≈ 0 and both refs collapse to near-zero, the floor
      dominates.  The available-mass cap prevents the threshold from growing
      without bound if expected becomes large.

    Severity: WARN.  Not gating — O1 has not been validated exhaustively
    across all scenario configurations; promote to FAIL once the full
    reference corpus is confirmed clean.
    """
    by_room: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_room[row.get("room_id", "?").strip()].append(row)

    findings: list[Finding] = []
    for room_id, room_rows in by_room.items():
        room_rows.sort(key=lambda r: _float(r, "time_s"))
        prev = room_rows[0]
        for curr in room_rows[1:]:
            # Skip fire-room rows where room.o2 is zone-derived.
            hrr = _float(curr, "hrr_kw")
            o2_mode = curr.get("fire_o2_mode_used", "").strip()
            if hrr > 0.1 and o2_mode in _O1_LAYER_DERIVED_MODES:
                prev = curr
                continue
            # Skip rows where HVAC is configured: HvacSystem modifies room.o2
            # via lerpf (supply/return, line 302 of HvacSystem.gd) without
            # contributing to any O2 accumulator.  HVAC instrumentation is out
            # of scope; WARNs in scenarios with HVAC are expected and documented.
            if curr.get("hvac_exists", "0") == "1":
                prev = curr
                continue

            o2_curr  = _float(curr, "o2")
            o2_prev  = _float(prev, "o2")
            air_mass = _float(curr, "air_mass_kg")

            consumed_curr  = _float(curr, "o2_consumed_bulk_kg_total")
            consumed_prev  = _float(prev, "o2_consumed_bulk_kg_total")
            exterior_curr  = _float(curr, "o2_exterior_net_kg_total")
            exterior_prev  = _float(prev, "o2_exterior_net_kg_total")
            transport_curr = _float(curr, "o2_net_transport_kg_total")
            transport_prev = _float(prev, "o2_net_transport_kg_total")

            delta_bulk      = (o2_curr - o2_prev) * air_mass
            delta_consumed  = consumed_curr - consumed_prev
            delta_exterior  = exterior_curr - exterior_prev
            delta_transport = transport_curr - transport_prev
            expected        = -delta_consumed + delta_exterior + delta_transport
            residual        = abs(delta_bulk - expected)

            # Tolerance: more conservative of two relative references, floored.
            o2_available    = abs(o2_prev * air_mass)
            ref_expected    = _O1_REL_TOL * abs(expected) if abs(expected) > 0.0 else _O1_REL_TOL * o2_available
            ref_available   = _O1_REL_TOL * o2_available if o2_available > 0.0 else _O1_ABS_FLOOR_KG
            threshold       = max(_O1_ABS_FLOOR_KG, min(ref_expected, ref_available))

            if residual > threshold:
                findings.append(Finding(
                    time_s=_float(curr, "time_s"),
                    room_id=room_id,
                    rule_id="O1",
                    severity="WARN",
                    metric="o2_bulk_balance_residual_kg",
                    value=round(residual, 9),
                    reason=(
                        f"delta_bulk={delta_bulk:.6g} kg  "
                        f"expected(-dcons+dext+dtrans)={expected:.6g} kg  "
                        f"residual={residual:.3g} kg  tol={threshold:.3g} kg"
                    ),
                ))
            prev = curr
    return findings


# ---------------------------------------------------------------------------
# Rule S0 — Smoke global conservation
# ---------------------------------------------------------------------------

_S0_ABS_FLOOR_KG = 0.01
_S0_REL_TOL = 0.05


def _check_s0_smoke_global_conservation(rows: list[dict[str, str]]) -> list[Finding]:
    """Global smoke mass conservation at every logged timestep.

    At each time_s: sum smoke_kg across all rooms plus smoke_in_transit_kg
    must equal the engine accumulators (same value in every row):
        expected = smoke_generated_total_kg − smoke_vented_total_kg
                   − smoke_deposited_total_kg
        residual = |sum_smoke_kg + smoke_in_transit_kg − expected|

    smoke_in_transit_kg accounts for smoke removed from source rooms but not
    yet delivered to target rooms via the interior transport delay buffer.

    Limitation: global check only — compensated inter-room transport errors
    are invisible.  Per-room S1 is pending per-room accumulator instrumentation.

    Tolerance: 5 % of abs(expected), floor 0.01 kg.
    Severity: FAIL.
    """
    by_time: dict[float, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_time[_float(row, "time_s")].append(row)

    findings: list[Finding] = []
    for time_s in sorted(by_time):
        time_rows = by_time[time_s]
        sum_smoke = sum(_float(r, "smoke_kg") for r in time_rows)
        # Global totals are identical across all rows of the same timestep.
        ref = time_rows[0]
        generated = _float(ref, "smoke_generated_total_kg")
        vented = _float(ref, "smoke_vented_total_kg")
        deposited = _float(ref, "smoke_deposited_total_kg")
        in_transit = _float(ref, "smoke_in_transit_kg")
        expected = generated - vented - deposited
        accounted = sum_smoke + in_transit
        residual = abs(accounted - expected)
        magnitude = max(abs(expected), _S0_ABS_FLOOR_KG)
        threshold = max(_S0_ABS_FLOOR_KG, _S0_REL_TOL * magnitude)

        if residual > threshold:
            findings.append(Finding(
                time_s=time_s,
                room_id="global",
                rule_id="S0",
                severity="FAIL",
                metric="smoke_balance_residual_kg",
                value=round(residual, 6),
                reason=(
                    f"sum_smoke_kg={sum_smoke:.6g} kg  "
                    f"in_transit={in_transit:.6g} kg  "
                    f"accounted={accounted:.6g} kg  "
                    f"expected(gen-vent-dep)={expected:.6g} kg  "
                    f"residual={residual:.3g} kg  tol={threshold:.3g} kg"
                ),
            ))
    return findings


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def find_physics_coherence_issues(
    rows: list[dict[str, str]],
    *,
    rule_ids: set[str] | None = None,
    room_id: str | None = None,
) -> list[Finding]:
    """Run enabled coherence rules on *rows* and return findings.

    Parameters
    ----------
    rows:
        CSV rows as dicts (from csv.DictReader or load_rows).
    rule_ids:
        Which rules to run.  None means all rules in ALL_RULES.
    room_id:
        If given, restrict analysis to this room.
    """
    if not rows:
        return []

    if room_id is not None:
        rows = [r for r in rows if r.get("room_id", "").strip() == room_id]
        if not rows:
            return []

    headers: set[str] = set(rows[0].keys())
    active: set[str] = set(ALL_RULES) if rule_ids is None else (rule_ids & set(ALL_RULES))

    findings: list[Finding] = []

    if "A2" in active and _has_cols(headers, REQUIRED_COLS["A2"]):
        findings.extend(_check_a2_hrr_no_fuel(rows))
    if "A3" in active and _has_cols(headers, REQUIRED_COLS["A3"]):
        findings.extend(_check_a3_regime_o2_starvation(rows))
    if "B1" in active and _has_cols(headers, REQUIRED_COLS["B1"]):
        findings.extend(_check_b1_thermal_inversion(rows))
    if "C1" in active and _has_cols(headers, REQUIRED_COLS["C1"]):
        findings.extend(_check_c1_fed_sum(rows))
    if "C2" in active and _has_cols(headers, REQUIRED_COLS["C2"]):
        findings.extend(_check_c2_fed_monotone(rows))
    if "D1" in active and _has_cols(headers, REQUIRED_COLS["D1"]):
        findings.extend(_check_d1_co_balance_residual(rows))
    if "E1" in active and _has_cols(headers, REQUIRED_COLS["E1"]):
        findings.extend(_check_e1_fuel_balance_residual(rows))
    if "O1" in active and _has_cols(headers, REQUIRED_COLS["O1"]):
        findings.extend(_check_o1_o2_bulk_balance(rows))
    if "O2E1" in active and _has_cols(headers, REQUIRED_COLS["O2E1"]):
        findings.extend(_check_o2e1_thornton_cross(rows))
    if "S0" in active and _has_cols(headers, REQUIRED_COLS["S0"]):
        findings.extend(_check_s0_smoke_global_conservation(rows))

    return findings


def load_rows(csv_path: Path) -> list[dict[str, str]]:
    with csv_path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check multi-parametric physical coherence in a SimuFire CSV log."
    )
    parser.add_argument("csv", help="Path to sim_log.csv or validation CSV.")
    parser.add_argument("--room-id", default=None, help="Restrict to this room_id.")
    parser.add_argument(
        "--rules",
        default=None,
        metavar="IDS",
        help="Comma-separated rule IDs (default: all).  Example: --rules C1,C2",
    )
    parser.add_argument(
        "--max-print", type=int, default=20,
        help="Max findings to print (default: 20).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    csv_path = Path(args.csv)
    if not csv_path.exists():
        print(f"ERROR: CSV not found: {csv_path}", file=sys.stderr)
        return 2

    rule_ids: set[str] | None = None
    if args.rules:
        rule_ids = {r.strip().upper() for r in args.rules.split(",") if r.strip()}

    rows = load_rows(csv_path)
    findings = find_physics_coherence_issues(rows, rule_ids=rule_ids, room_id=args.room_id)

    if not findings:
        scope = f"room_id={args.room_id}" if args.room_id is not None else "all rooms"
        print(f"Physics coherence PASS ({scope}, rows={len(rows)})")
        return 0

    fails = [f for f in findings if f.severity == "FAIL"]
    warns = [f for f in findings if f.severity == "WARN"]
    print(f"Physics coherence: {len(fails)} FAIL, {len(warns)} WARN")
    for finding in findings[:args.max_print]:
        print("  " + finding.format())
    if len(findings) > args.max_print:
        print(f"  ... {len(findings) - args.max_print} more")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
