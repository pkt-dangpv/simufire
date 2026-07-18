import io
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

from scripts.simulation.analyze_phase3_projection_trace import load_events, summarize


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "simulation" / "analyze_phase3_projection_trace.py"
FIXTURE = ROOT / "tests" / "fixtures" / "phase3_projection_trace.jsonl"


def _event(time_s: float, call: int, cause: str, mass: float, energy: float):
    event = {
        "sim_time_s": time_s,
        "room_id": 0,
        "call_index": call,
        "cause": cause,
        "total_mass_delta_kg": mass,
        "total_energy_delta_kj": energy,
    }
    for metric in (
        "ensure_mass_delta_kg",
        "ensure_energy_delta_kj",
        "temperature_projection_energy_delta_kj",
        "upper_cap_mass_delta_kg",
        "upper_cap_energy_delta_kj",
        "lower_projection_mass_delta_kg",
        "lower_projection_energy_delta_kj",
    ):
        event[metric] = 0.0
    event["lower_projection_mass_delta_kg"] = mass
    event["lower_projection_energy_delta_kj"] = energy
    return event


def test_load_events_reads_jsonl():
    assert load_events(FIXTURE)[0]["cause"] == "first"


def test_load_events_rejects_empty_trace():
    with patch.object(Path, "open", return_value=io.StringIO("\n")):
        with pytest.raises(ValueError, match="empty"):
            load_events(FIXTURE)


def test_load_events_reports_bad_line():
    with patch.object(Path, "open", return_value=io.StringIO("{}\nnot-json\n")):
        with pytest.raises(ValueError, match=":2"):
            load_events(FIXTURE)


def test_summary_groups_calls_per_room_step():
    summary = summarize(
        [
            _event(1.0, 0, "first", -1.0, -2.0),
            _event(1.0, 1, "second", 0.25, 0.0),
            _event(2.0, 0, "first", -0.5, -1.0),
        ]
    )
    assert summary["event_count"] == 3
    assert summary["step_count"] == 2
    assert summary["calls_per_step"] == {"1": 1, "2": 1}
    assert summary["cause_counts"] == {"first": 2, "second": 1}


def test_summary_finds_signed_absolute_peaks():
    summary = summarize(
        [
            _event(1.0, 0, "first", -1.0, -2.0),
            _event(1.0, 1, "second", 0.25, 0.0),
        ]
    )
    assert summary["metric_peaks"]["total_mass_delta_kg"]["value"] == -1.0
    assert summary["metric_peaks"]["total_energy_delta_kj"]["value"] == -2.0
    assert summary["step_mass_peak"]["total_mass_delta_kg"] == -0.75


def test_cli_reads_fixture_and_prints_summary():
    result = subprocess.run(
        [sys.executable, str(SCRIPT), str(FIXTURE)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert "Projection trace" in result.stdout
    assert "first: 1" in result.stdout
