"""G3 diagnostic flame-target key (design section 13): the isolated property.

The key makes the flame target continuous around ``can_flame = 0.08`` to
isolate the effect of its jump. It is a diagnostic, not product physics: OFF
by default, not exported to the editor, absent from every distributed file.
These tests pin the function on its own: continuity, nothing changed outside
the declared window, OFF returning the original value, and the block being a
pure insertion in ``CombustionSystem.gd``.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

import pytest

from scripts.simulation import g3_diag_flame_target_patch as patch
from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/g3_diag_flame_target.gd"
COMBUSTION_PATH = ROOT / "sim/fire/CombustionSystem.gd"
COMBUSTION = COMBUSTION_PATH.read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
KEYS = ("fire_diag_flame_target_window", "fire_diag_flame_target_jump_fraction")
THRESHOLD = 0.08
GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
)


def _godot() -> Path | None:
    return next((path for path in GODOT_CANDIDATES if path is not None and path.exists()), None)


@pytest.fixture(scope="module")
def table() -> list[dict]:
    godot = _godot()
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")
    completed = run_godot(
        [str(godot), "--headless", "--path", str(ROOT), "--script", str(FIXTURE)],
        timeout_s=120, allowed_exit_codes=(0,),
    )
    line = next(item for item in completed.stdout.splitlines() if item.startswith("G3_DIAG_FLAME_TARGET "))
    payload = json.loads(line.split(" ", 1)[1])
    assert payload["threshold"] == THRESHOLD
    assert (payload["window_key"], payload["jump_key"]) == KEYS
    names = ("ideal", "smolder", "window", "jump", "offset", "original", "value")
    return [dict(zip(names, row)) for row in payload["rows"]]


def _inside(row: dict) -> bool:
    return row["window"] > 0.0 and 0.0 < row["offset"] < row["window"]


def _expected(row: dict) -> float:
    at_threshold = row["smolder"] + row["jump"] * (row["ideal"] * THRESHOLD - row["smolder"])
    at_top = row["ideal"] * (THRESHOLD + row["window"])
    return at_threshold + (at_top - at_threshold) * row["offset"] / row["window"]


def test_off_and_outside_the_window_return_the_original_value_exactly(table):
    outside = [row for row in table if not _inside(row)]
    assert len(outside) > 1000
    assert {row["window"] for row in outside} == {0.0, 0.002, 0.01}
    for row in outside:
        assert row["value"] == row["original"], row  # bit for bit, not approximately


def test_inside_the_window_it_is_the_declared_straight_line(table):
    inside = [row for row in table if _inside(row)]
    assert len(inside) > 400
    for row in inside:
        assert row["value"] == pytest.approx(_expected(row), abs=1e-9), row


def test_continuous_at_the_threshold_without_a_jump(table):
    """jump_fraction 0: just above 0.08 the flame target is the smolder target below it."""
    rows = [row for row in table if row["window"] > 0.0 and row["jump"] == 0.0 and row["offset"] == 1e-12]
    assert len(rows) == 18
    for row in rows:
        slope = (row["ideal"] * (THRESHOLD + row["window"]) - row["smolder"]) / row["window"]
        assert abs(row["value"] - row["smolder"]) <= abs(slope) * 2e-12 + 1e-12, row
        if row["smolder"] <= row["ideal"] * THRESHOLD:
            assert row["original"] - row["value"] == pytest.approx(row["ideal"] * THRESHOLD - row["smolder"], abs=1e-6)


def test_kept_jump_is_the_declared_fraction_of_the_original_one(table):
    for row in (r for r in table if r["window"] > 0.0 and r["offset"] == 1e-12):
        original_jump = row["ideal"] * THRESHOLD - row["smolder"]
        assert row["value"] - row["smolder"] == pytest.approx(row["jump"] * original_jump, abs=1e-6), row


def test_continuous_at_the_top_of_the_window_for_every_jump_fraction(table):
    for window, offset in ((0.002, 0.0019999), (0.01, 0.0099999)):
        rows = [row for row in table if row["window"] == window and row["offset"] == offset]
        assert len(rows) == 36
        for row in rows:
            gap = abs(row["ideal"] * THRESHOLD - row["smolder"]) * (1.0 - offset / window)
            assert abs(row["value"] - row["original"]) <= gap + 1e-9, row
            assert abs(row["value"] - row["original"]) < 0.0031 * row["ideal"] * THRESHOLD + 1e-3, row


def test_full_jump_fraction_is_the_original_rule(table):
    rows = [row for row in table if _inside(row) and row["jump"] == 1.0]
    assert len(rows) > 100
    for row in rows:
        assert row["value"] == pytest.approx(row["original"], abs=1e-9), row


def test_ramp_rises_with_flame_drive_and_never_exceeds_the_original(table):
    groups: dict[tuple, list[dict]] = {}
    for row in table:
        if _inside(row) and row["smolder"] <= row["ideal"] * THRESHOLD:
            groups.setdefault((row["ideal"], row["smolder"], row["window"], row["jump"]), []).append(row)
    assert len(groups) == 64  # 3 ideals x 3 smolders x 2 windows x 4 fractions, minus smolder > ideal x 0.08
    for rows in groups.values():
        rows.sort(key=lambda row: row["offset"])
        values = [row["value"] for row in rows]
        assert values == sorted(values)
        assert all(row["value"] <= row["original"] + 1e-9 for row in rows)


def test_the_block_is_a_pure_insertion_in_combustion_system():
    assert patch.matches(COMBUSTION_PATH)
    without = patch.stripped(COMBUSTION)
    assert "g3_diag" not in without.lower()
    assert len(COMBUSTION.splitlines()) - len(without.splitlines()) == sum(
        block.count("\n") for block in (patch.CONSTANTS, patch.CALL, patch.FUNCTION)
    )


def test_can_flame_classification_is_untouched_and_shares_the_threshold():
    assert COMBUSTION.count("var can_flame: bool = flame_drive > 0.08") == 1
    assert COMBUSTION.count("const G3_DIAG_CAN_FLAME_DRIVE: float = 0.08") == 1
    assert "can_flame" not in patch.FUNCTION
    assert "can_flame =" not in patch.CALL
    # The call sits in the can_flame branch, right after the original assignment.
    assert patch.CALL_ANCHOR + patch.CALL in COMBUSTION
    assert patch.CALL.count("if g3_diag_window > 0.0:") == 1


def test_smolder_at_the_threshold_uses_the_engine_expression():
    expression = "minf(residual_smolder_cap_kw,solid_pyrolysis_kw*smolder_fraction*lerpf(0.40,1.0,subvent_engagement))"
    compact = re.sub(r"\s+", "", COMBUSTION)
    assert compact.count(expression) == 2  # the rule below the threshold, and the diagnostic
    assert re.sub(r"\s+", "", patch.CALL).count(expression) == 1


def test_the_block_only_writes_the_flame_target():
    assigned = set(re.findall(r"^\s*(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)(?::\s*\w+)?\s*=[^=]", patch.CALL, re.MULTILINE))
    assert {name for name in assigned if not name.startswith("g3_diag_")} == {"fresh_flame_target_kw"}
    # It reads engine state but writes none: no member of the room, the fire or an object.
    for forbidden in ("room.", "fire.", "obj.", "context["):
        assert forbidden not in patch.CALL, forbidden


def test_engine_keys_are_not_exported_and_reach_the_context_only_when_on():
    for key in KEYS:
        assert f"var {key}: float = 0.0" in ENGINE
        assert f"@export var {key}" not in ENGINE
        assert ENGINE.count(f'context["{key}"]') == 1
    guard = ENGINE.index("if fire_diag_flame_target_window > 0.0:")
    assert all(guard < ENGINE.index(f'context["{key}"]') < guard + 400 for key in KEYS)
    # No other reader: CombustionSystem takes them from the context only.
    assert ENGINE.count("fire_diag_flame_target_window") == 4
    assert ENGINE.count("fire_diag_flame_target_jump_fraction") == 3


def test_no_distributed_or_product_file_sets_the_key():
    roots = ("scenarios", "scenes", "editor", "ui", "view", "i18n", "sim/templates", "sim/validation/cases",
             "sim/building", "sim/resources")
    hits = []
    for name in roots:
        for path in (ROOT / name).rglob("*"):
            if path.is_file() and path.suffix in (".json", ".gd", ".tscn", ".tres", ".cfg"):
                if "fire_diag_flame_target" in path.read_text(encoding="utf-8", errors="ignore"):
                    hits.append(path.relative_to(ROOT).as_posix())
    for path in (ROOT / "project.godot", ROOT / "Main.gd", ROOT / "scripts/check_product.py"):
        if "fire_diag_flame_target" in path.read_text(encoding="utf-8", errors="ignore"):
            hits.append(path.name)
    assert hits == []
    users = sorted(
        path.relative_to(ROOT).as_posix() for path in (ROOT / "sim").rglob("*.gd")
        if "fire_diag_flame_target" in path.read_text(encoding="utf-8", errors="ignore")
    )
    assert users == ["sim/core/SimulationEngine.gd", "sim/fire/CombustionSystem.gd"]
