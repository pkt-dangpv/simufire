"""Contracts for the H3.2-S0d6b0.2a zonal gas-mass analyser.

The analyser must not repeat three mistakes an earlier draft made:

1. It claimed `gas_kg == volume_m3_eos * rho(T)` proved projection had
   reconstructed the mass. That is a tautology: `SimulationStateBuilder.gd:430`
   computes `volume_m3_eos = gas_kg / rho`. The identity survives only as a CSV
   self-consistency check and must never drive a verdict.
2. It called `upper_gas_kg == 0` DEGENERATE. A room with no hot layer is a valid
   one-zone regime, and `ThermalSystem.gd:4553` already gates on it.
3. It computed a per-step causal balance from 10 s-interval samples.
"""

from __future__ import annotations

import csv
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/simulation/analyze_zonal_gas_mass_reliability.py"


def _load():
    spec = importlib.util.spec_from_file_location("zgmr", MODULE_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


zgmr = _load()
COLUMNS = list(zgmr.REQUIRED)


def _write_csv(tmp_path: Path, rows: list[dict], name: str = "case") -> Path:
    d = tmp_path / name
    d.mkdir(parents=True, exist_ok=True)
    p = d / "sim_log.csv"
    with p.open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=COLUMNS)
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, 0.0) for c in COLUMNS})
    return p


def _row(t: float, up: float, lo: float, tu: float = 20.0, tl: float = 20.0,
         vol: float = 48.0, **extra) -> dict:
    """Mirrors SimulationStateBuilder.gd:430-431 exactly: the exported EOS volume
    IS the mass divided by the density, so the identity holds by construction."""
    vu = up / zgmr.rho_at(tu) if up > 0 else 0.0
    vl = lo / zgmr.rho_at(tl) if lo > 0 else 0.0
    base = {
        "time_s": t, "room_id": 0, "upper_gas_kg": up, "lower_gas_kg": lo,
        "upper_volume_m3_eos": vu, "lower_volume_m3_eos": vl,
        "volume_closure_error_m3": 0.0,
        "two_zone_boundary_mass_kg": 0.0, "two_zone_boundary_mass_kg_step": 0.0,
        "attribution_mass_residual_kg_step": 0.0,
        "volume_m3": vol, "temp_upper_c": tu, "temp_lower_c": tl,
    }
    for s in zgmr.PHYSICAL_STAGES + zgmr.CLOSURE_STAGES:
        base[f"{s}_mass_delta_kg_step"] = 0.0
    base.update(extra)
    return base


# --------------------------------------------------------------------------
# 1. The tautology, demonstrated and quarantined
# --------------------------------------------------------------------------

def test_eos_identity_is_a_tautology_and_proves_nothing():
    # Demonstrate the circularity numerically, independent of any CSV.
    for mass, temp in ((13.2, 121.14), (57.6, 20.0), (0.37, 640.0)):
        rho = zgmr.rho_at(temp)
        volume_eos = mass / rho            # SimulationStateBuilder.gd:430
        recovered = volume_eos * rho       # what the withdrawn check computed
        assert recovered == pytest.approx(mass, rel=1e-15)
    # The engine really does derive the volume from the mass.
    builder = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
    assert "room.upper_gas_kg / maxf(0.05, upper_density_kg_m3)" in builder
    assert "room.lower_gas_kg / maxf(0.05, lower_density_kg_m3)" in builder


def test_identity_is_labelled_self_derived_and_never_a_verdict(tmp_path):
    rows = [_row(t, 5.0, 50.0, tu=300.0) for t in (0.0, 10.0, 20.0)]
    room = zgmr.analyse_csv(_write_csv(tmp_path, rows))["rooms"]["0"]
    assert room["self_derived_eos_identity_holds"] is True
    note = room["self_derived_eos_identity_note"].lower()
    assert "self-consistency" in note
    assert "proves nothing" in note
    # It must not appear in, or influence, any dimension.
    assert room["zone_presence"] == "TWO_ZONE_PRESENT"
    assert room["causal_status"] == "INCOMPLETE"


def test_no_projection_dependent_verdict_from_self_contained_columns(tmp_path):
    rows = [_row(t, 5.0, 50.0, tu=300.0) for t in (0.0, 10.0, 20.0)]
    res = zgmr.analyse_csv(_write_csv(tmp_path, rows))
    blob = repr(res)
    assert "PROJECTION_DEPENDENT" not in blob
    src = MODULE_PATH.read_text(encoding="utf-8")
    assert "PROJECTION_DEPENDENT" not in src
    for withdrawn in ("eos_forced_upper", "eos_forced_lower", "eos_forced_share"):
        assert withdrawn not in src, withdrawn


def test_negative_control_reinstating_the_false_inference_breaks_this_suite():
    # If anyone reintroduces the withdrawn inference, the guards above fail.
    src = MODULE_PATH.read_text(encoding="utf-8")
    mutated = src.replace(
        '"self_derived_eos_identity_holds"', '"eos_forced_share"'
    ).replace("CODE_PROVEN_UPPER_CAP", "PROJECTION_DEPENDENT")
    assert mutated != src, "the anchors this control relies on have moved"
    assert "eos_forced_share" in mutated and "PROJECTION_DEPENDENT" in mutated
    # The two contracts above key on exactly these tokens being absent.
    assert "eos_forced_share" not in src
    assert "PROJECTION_DEPENDENT" not in src


# --------------------------------------------------------------------------
# 2. Zone presence is not a defect
# --------------------------------------------------------------------------

def test_absent_upper_zone_is_a_regime_not_a_defect(tmp_path):
    rows = [_row(t, 0.0, 57.6) for t in (0.0, 10.0, 20.0, 30.0)]
    room = zgmr.analyse_csv(_write_csv(tmp_path, rows))["rooms"]["0"]
    assert room["zone_presence"] == "UPPER_ZONE_ABSENT"
    assert room["upper_absent_steps"] == 4
    assert room["upper_absent_share"] == 1.0
    assert "DEGENERATE" not in repr(room)


def test_negative_or_nonfinite_mass_is_invalid(tmp_path):
    rows = [_row(0.0, 5.0, 50.0), _row(10.0, -1.0, 50.0)]
    room = zgmr.analyse_csv(_write_csv(tmp_path, rows))["rooms"]["0"]
    assert room["zone_presence"] == "NONFINITE_OR_INVALID"
    assert room["invalid_steps"] == 1


def test_both_zones_absent_is_its_own_category(tmp_path):
    rows = [_row(t, 0.0, 0.0) for t in (0.0, 10.0)]
    room = zgmr.analyse_csv(_write_csv(tmp_path, rows))["rooms"]["0"]
    assert room["zone_presence"] == "BOTH_ZONES_ABSENT"


def test_two_zone_present_when_both_have_mass(tmp_path):
    rows = [_row(t, 5.0, 50.0) for t in (0.0, 10.0)]
    room = zgmr.analyse_csv(_write_csv(tmp_path, rows))["rooms"]["0"]
    assert room["zone_presence"] == "TWO_ZONE_PRESENT"


# --------------------------------------------------------------------------
# 3. The FED contract, anchored to the real guard
# --------------------------------------------------------------------------

def test_fed_gate_is_anchored_to_the_engine_guard():
    thermal = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
    assert ("var in_upper: bool = (thermal_exposure_factor >= 0.5 "
            "and room.upper_gas_kg > 0.1)") in thermal
    assert zgmr.FED_UPPER_GATE_KG == 0.1
    # And FED picks the lower zone whenever that gate is false.
    assert "room.o2_upper if in_upper else room.o2_lower" in thermal


def test_counts_steps_below_the_fed_gate(tmp_path):
    rows = [_row(0.0, 0.0, 50.0), _row(10.0, 0.05, 50.0), _row(20.0, 5.0, 50.0)]
    room = zgmr.analyse_csv(_write_csv(tmp_path, rows))["rooms"]["0"]
    assert room["upper_below_fed_gate_steps"] == 2   # 0.0 and 0.05 are <= 0.1
    assert room["zone_presence"] == "TWO_ZONE_PRESENT"


# --------------------------------------------------------------------------
# 4. Causal status stays INCOMPLETE
# --------------------------------------------------------------------------

def test_causal_status_is_incomplete_with_interval_sampling(tmp_path):
    p = _write_csv(tmp_path, [_row(0.0, 5.0, 50.0), _row(10.0, 6.0, 49.0)])
    res = zgmr.analyse_csv(p)
    assert res["causal_status"] == "INCOMPLETE"
    assert "sub-step" in res["causal_status_reason"]
    for room in res["rooms"].values():
        assert room["causal_status"] == "INCOMPLETE"
        for key in room:
            assert "residual" not in key, key


def test_nothing_is_ever_reliable(tmp_path):
    rows = [_row(t, 5.0, 50.0) for t in (0.0, 10.0, 20.0)]
    res = zgmr.analyse_csv(_write_csv(tmp_path, rows))
    assert "RELIABLE" not in repr(res)
    # The word may appear in prose explaining why it is never emitted, but it
    # must never occur in executable code.
    src = MODULE_PATH.read_text(encoding="utf-8")
    body = src.split('"""', 2)[2]
    code = "\n".join(
        line for line in body.splitlines() if not line.lstrip().startswith("#")
    )
    assert "RELIABLE" not in code.replace("RELIABILITY", "")


# --------------------------------------------------------------------------
# 5. Projection evidence comes from code and the boundary accumulator
# --------------------------------------------------------------------------

def test_projection_evidence_is_code_proven_not_csv_inferred(tmp_path):
    rows = [_row(t, 5.0, 50.0) for t in (0.0, 10.0)]
    res = zgmr.analyse_csv(_write_csv(tmp_path, rows))
    assert res["projection_evidence"] == [
        "CODE_PROVEN_LOWER_RECONSTRUCTION",
        "CODE_PROVEN_UPPER_CAP",
        "RUNTIME_TRACE_UNAVAILABLE",
    ]


def test_code_claims_match_zone_fire_solver():
    solver = (ROOT / "sim/core/ZoneFireSolver.gd").read_text(encoding="utf-8")
    # Lower mass is overwritten unconditionally from the remaining volume.
    assert "room.lower_gas_kg = maxf(0.0, target_lower_mass_kg)" in solver
    assert "var target_lower_mass_kg: float = lower_volume_m3 * lower_density_kg_m3" in solver
    # Upper mass is capped only when it exceeds the whole-room mass.
    assert "if room.upper_gas_kg > max_upper_mass_kg and room.upper_gas_kg > ZONE_MASS_EPS_KG:" in solver
    assert "room.upper_gas_kg = max_upper_mass_kg" in solver
    # Both record their correction in the boundary accumulator.
    assert "room.two_zone_boundary_mass_kg += room.upper_gas_kg - upper_mass_before_kg" in solver
    assert "room.two_zone_boundary_mass_kg += room.lower_gas_kg - lower_mass_before_kg" in solver
    # And the interface follows the upper mass, not the reverse.
    assert "var upper_volume_m3: float = room.upper_gas_kg / maxf(0.05, upper_density_kg_m3)" in solver


def test_boundary_accumulator_is_reported_and_is_not_self_derived(tmp_path):
    rows = [_row(0.0, 5.0, 50.0, two_zone_boundary_mass_kg=0.0),
            _row(10.0, 5.0, 50.0, two_zone_boundary_mass_kg=0.25,
                 two_zone_boundary_mass_kg_step=0.25)]
    room = zgmr.analyse_csv(_write_csv(tmp_path, rows))["rooms"]["0"]
    assert room["boundary_mass_net_kg"] == pytest.approx(0.25)
    # Run-length quantities only; both endpoints of a cumulative accumulator.
    assert room["total_mass_net_kg"] == pytest.approx(0.0)
    assert room["boundary_net_over_nominal"] == pytest.approx(0.25 / (48.0 * 1.2))
    # It comes from the engine, not from the masses in the same row.
    assert "two_zone_boundary_mass_kg" in zgmr.REQUIRED


def test_never_mixes_sub_step_deltas_with_interval_differences():
    # Summing *_step columns and dividing by an interval mass difference mixes
    # two time bases. That error was made twice and must not return.
    src = MODULE_PATH.read_text(encoding="utf-8")
    assert "abs_boundary_step_kg" not in src
    assert "abs_total_mass_delta_kg" not in src
    body = src.split('"""', 2)[2]
    code = "\n".join(
        line for line in body.splitlines() if not line.lstrip().startswith("#")
    )
    assert '"boundary_mass_net_kg": boundary_net' in code
    assert '"total_mass_net_kg"' in code
    # The only *_step column still read is the engine residual, and it is used
    # solely to show that it cannot fail -- never divided by anything.
    step_reads = {
        line.split('_f(row, "', 1)[1].split('"', 1)[0]
        for line in code.splitlines() if '_f(row, "' in line
    }
    assert {c for c in step_reads if c.endswith("_step")} == {
        "attribution_mass_residual_kg_step",
    }, step_reads


# --------------------------------------------------------------------------
# 6. Housekeeping
# --------------------------------------------------------------------------

def test_gas_law_matches_the_engine():
    assert zgmr.AIR_DENSITY_REF_KG_M3 == 1.2
    assert zgmr.rho_at(20.0) == pytest.approx(1.2, rel=1e-9)
    assert zgmr.rho_at(600.0) == pytest.approx(1.2 * 293.15 / 873.15, rel=1e-9)
    solver = (ROOT / "sim/core/ZoneFireSolver.gd").read_text(encoding="utf-8")
    assert "AIR_DENSITY_REF_KG_M3 * ambient_k / upper_k" in solver


def test_engine_residual_is_detected_as_uninformative(tmp_path):
    p = _write_csv(tmp_path, [_row(0.0, 5.0, 50.0), _row(10.0, 6.0, 49.0)])
    assert zgmr.analyse_csv(p)["engine_residual_identically_zero"] is True
    src = MODULE_PATH.read_text(encoding="utf-8")
    assert set(zgmr.CLOSURE_STAGES) == {"reconcile", "projection_clamp"}
    assert "cannot fail" in src


def test_missing_columns_report_incomplete(tmp_path):
    d = tmp_path / "bare"
    d.mkdir()
    p = d / "sim_log.csv"
    p.write_text("time_s,room_id,o2\n0,0,0.209\n", encoding="utf-8")
    res = zgmr.analyse_csv(p)
    assert res["status"] == "INCOMPLETE"
    assert res["reason"] == "missing_columns"
    assert res["rooms"] == {}


def test_analyzer_is_read_only_except_for_json_out():
    src = MODULE_PATH.read_text(encoding="utf-8")
    assert src.count("write_text") == 1
    assert "Path(a.json_out).write_text(" in src
    body = src.split('"""', 2)[2]
    for forbidden in ("subprocess", "os.remove", "shutil"):
        assert forbidden not in body, forbidden
