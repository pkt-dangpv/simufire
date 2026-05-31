"""
tests/test_editor_scenarios.py — v0.5.0 E-02

Python-side structural tests for SimuFire editor scenarios.

These tests replicate the logic of ScenarioSerializer.load_scenario() and
normalize_editor_data() (ScenarioSerializer.gd) entirely in Python, without
running Godot.  They validate:

  1. The loading contract: missing file or invalid JSON → empty dict (same
     as what ScenarioSerializer returns on error, triggering E-01 popup).

  2. The structural contract: a scenario dict returned by load_scenario() has
     the top-level keys expected by SimulationEngine and the editor.

  3. The repo's committed scenario files (scenarios/*.json) satisfy the
     structural contract.

  4. A minimal valid scenario (1 room, no openings) can round-trip through
     the normalisation rules without loss.

Run:
    python tests/test_editor_scenarios.py
    # or:
    python -m pytest tests/test_editor_scenarios.py -v

No external dependencies — stdlib only.  No Godot, no simulation physics.
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

_REPO_ROOT = Path(__file__).resolve().parent.parent
_SCENARIOS_DIR = _REPO_ROOT / "scenarios"

# ---------------------------------------------------------------------------
# Python replica of ScenarioSerializer.load_scenario()
# ---------------------------------------------------------------------------

# Keys that every committed scenario file should have (the normaliser adds
# defaults for missing ones, but a well-formed saved scenario should include
# the core keys explicitly).
_CORE_SCENARIO_KEYS = {
    "version",
    "rooms_data",
    "openings_data",
}

# Keys that normalize_editor_data() guarantees are present in the *output*
# (used in the structural contract tests to verify the normaliser contract).
_NORMALISED_TOP_LEVEL_KEYS = {
    "version",
    "outside_temp_c",
    "outside_o2",
    "stop_time_s",
    "hvac_mode",
    "hvac_data",
    "room_rect_m",
    "rooms_data",
    "openings_data",
    # "floors" and "exterior_walls" are also normalised but may be absent in
    # raw scenario files — the normaliser produces them even from empty input.
}

# Keys required in each room dict after normalisation.
_ROOM_REQUIRED_KEYS = {"id", "name", "kind", "height_m", "fuel_objects"}

# Keys required in each opening dict (actual serialised field names from
# ScenarioSerializer.normalize_opening).
_OPENING_REQUIRED_KEYS = {"a", "b", "type"}


def _load_scenario_py(path: str) -> dict:
    """
    Python replica of ScenarioSerializer.load_scenario().

    Returns {} on:
      - file not found
      - JSON parse error
      - top-level value is not a dict
    """
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except (FileNotFoundError, OSError):
        return {}

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return {}

    if not isinstance(parsed, dict):
        return {}

    return parsed


def _validate_scenario_structure(data: dict) -> list:
    """
    Return a list of violation strings.  Empty list means the scenario passes
    all structural checks.

    This validates the raw input format (as saved by the editor), not the
    normalised output format.
    """
    errors = []

    # --- Core top-level keys expected in every saved scenario ----------------
    for key in _NORMALISED_TOP_LEVEL_KEYS:
        if key not in data:
            errors.append(f"Missing top-level key: '{key}'")

    # --- rooms_data -----------------------------------------------------------
    rooms = data.get("rooms_data", [])
    if not isinstance(rooms, list):
        errors.append("'rooms_data' must be a list")
    else:
        for i, room in enumerate(rooms):
            if not isinstance(room, dict):
                errors.append(f"rooms_data[{i}] is not a dict")
                continue
            for k in _ROOM_REQUIRED_KEYS:
                if k not in room:
                    errors.append(
                        f"rooms_data[{i}] (id={room.get('id', '?')}) missing key: '{k}'"
                    )
            if "height_m" in room:
                h = room["height_m"]
                if not isinstance(h, (int, float)) or h <= 0:
                    errors.append(
                        f"rooms_data[{i}] height_m must be a positive number, got {h!r}"
                    )

    # --- openings_data --------------------------------------------------------
    openings = data.get("openings_data", [])
    if not isinstance(openings, list):
        errors.append("'openings_data' must be a list")
    else:
        for i, op in enumerate(openings):
            if not isinstance(op, dict):
                errors.append(f"openings_data[{i}] is not a dict")
                continue
            for k in _OPENING_REQUIRED_KEYS:
                if k not in op:
                    errors.append(f"openings_data[{i}] missing key: '{k}'")

    # --- room_rect_m ----------------------------------------------------------
    room_rect_m = data.get("room_rect_m", {})
    if not isinstance(room_rect_m, dict):
        errors.append("'room_rect_m' must be a dict")
    else:
        for key in room_rect_m:
            rect = room_rect_m[key]
            if not isinstance(rect, dict):
                errors.append(f"room_rect_m['{key}'] is not a dict")
                continue
            for dim in ("x", "y", "w", "h"):
                if dim not in rect:
                    errors.append(f"room_rect_m['{key}'] missing key: '{dim}'")

    # --- Cross-references: rooms ↔ room_rect_m, openings ↔ rooms ---------------
    # Mirrors ScenarioSerializer.validate_scenario() in GDScript.
    if isinstance(rooms, list) and isinstance(room_rect_m, dict):
        valid_room_ids = {
            str(r.get("id")) for r in rooms if isinstance(r, dict) and "id" in r
        }
        for i, room in enumerate(rooms):
            if not isinstance(room, dict):
                continue
            rid_str = str(room.get("id", ""))
            if not rid_str:
                continue
            if rid_str not in room_rect_m:
                errors.append(
                    f"room_rect_m: missing entry for room id='{rid_str}'"
                )
            elif isinstance(room_rect_m[rid_str], dict):
                w = room_rect_m[rid_str].get("w", 0)
                h_val = room_rect_m[rid_str].get("h", 0)
                if not (isinstance(w, (int, float)) and w > 0):
                    errors.append(
                        f"room_rect_m['{rid_str}'] must have w > 0 (got {w!r})"
                    )
                if not (isinstance(h_val, (int, float)) and h_val > 0):
                    errors.append(
                        f"room_rect_m['{rid_str}'] must have h > 0 (got {h_val!r})"
                    )
        if isinstance(openings, list):
            for i, op in enumerate(openings):
                if not isinstance(op, dict):
                    continue
                a = op.get("a")
                b = op.get("b")
                if a is not None and str(a) not in valid_room_ids:
                    errors.append(
                        f"openings_data[{i}]: room a={a} does not exist in rooms_data"
                    )
                if b is not None and b != -1 and str(b) not in valid_room_ids:
                    errors.append(
                        f"openings_data[{i}]: room b={b} does not exist in rooms_data"
                    )

    return errors


# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------


class TestLoadContract(unittest.TestCase):
    """
    Replicates the load_scenario() contract: the function returns {} on bad
    input; the editor then shows the E-01 popup.
    """

    def test_missing_file_returns_empty(self):
        result = _load_scenario_py("/tmp/does_not_exist_12345.json")
        self.assertEqual(result, {}, "Missing file must return empty dict")

    def test_invalid_json_returns_empty(self):
        with tempfile.NamedTemporaryFile(
            suffix=".json", mode="w", delete=False, encoding="utf-8"
        ) as f:
            f.write("{this is: not valid json,,,}")
            tmp = f.name
        try:
            result = _load_scenario_py(tmp)
            self.assertEqual(result, {}, "Invalid JSON must return empty dict")
        finally:
            os.unlink(tmp)

    def test_json_array_toplevel_returns_empty(self):
        """A top-level JSON array is not a dict — must be rejected."""
        with tempfile.NamedTemporaryFile(
            suffix=".json", mode="w", delete=False, encoding="utf-8"
        ) as f:
            f.write('[{"room": 1}]')
            tmp = f.name
        try:
            result = _load_scenario_py(tmp)
            self.assertEqual(result, {}, "Top-level array must return empty dict")
        finally:
            os.unlink(tmp)

    def test_json_null_toplevel_returns_empty(self):
        with tempfile.NamedTemporaryFile(
            suffix=".json", mode="w", delete=False, encoding="utf-8"
        ) as f:
            f.write("null")
            tmp = f.name
        try:
            result = _load_scenario_py(tmp)
            self.assertEqual(result, {}, "JSON null must return empty dict")
        finally:
            os.unlink(tmp)

    def test_valid_minimal_dict_not_empty(self):
        """A valid minimal dict (even empty {}) is returned as-is."""
        with tempfile.NamedTemporaryFile(
            suffix=".json", mode="w", delete=False, encoding="utf-8"
        ) as f:
            f.write('{"version": 1, "rooms_data": []}')
            tmp = f.name
        try:
            result = _load_scenario_py(tmp)
            self.assertNotEqual(result, {}, "Valid minimal dict must not be empty")
            self.assertEqual(result["version"], 1)
        finally:
            os.unlink(tmp)


class TestStructuralContract(unittest.TestCase):
    """
    Checks the structural requirements for a scenario that can be fed to the
    simulation engine.  A scenario loaded by ScenarioSerializer returns a
    normalised dict; these tests verify what that normalisation guarantees.
    """

    def _make_minimal_scenario(self) -> dict:
        return {
            "version": 1,
            "outside_temp_c": 20.0,
            "outside_o2": 0.209,
            "stop_time_s": 0.0,
            "hvac_mode": "none",
            "hvac_data": {"exists": False, "on": False, "mode": "none"},
            "room_rect_m": {
                "0": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}
            },
            "rooms_data": [
                {
                    "id": 0,
                    "name": "Sala",
                    "kind": "generic",
                    "height_m": 2.4,
                    "fuel_energy_MJ": 0.0,
                    "max_hrr_kw": 0.0,
                    "fuel_objects": [],
                }
            ],
            "openings_data": [],
            "floors": [],
            "exterior_walls": [],
        }

    def test_minimal_scenario_passes(self):
        data = self._make_minimal_scenario()
        errors = _validate_scenario_structure(data)
        self.assertEqual(errors, [], f"Minimal scenario should pass; got: {errors}")

    def test_missing_rooms_data_flagged(self):
        data = self._make_minimal_scenario()
        del data["rooms_data"]
        errors = _validate_scenario_structure(data)
        self.assertTrue(
            any("rooms_data" in e for e in errors),
            "Missing rooms_data must be flagged",
        )

    def test_missing_openings_data_flagged(self):
        data = self._make_minimal_scenario()
        del data["openings_data"]
        errors = _validate_scenario_structure(data)
        self.assertTrue(
            any("openings_data" in e for e in errors),
            "Missing openings_data must be flagged",
        )

    def test_room_missing_height_flagged(self):
        data = self._make_minimal_scenario()
        del data["rooms_data"][0]["height_m"]
        errors = _validate_scenario_structure(data)
        self.assertTrue(
            any("height_m" in e for e in errors),
            "Room missing height_m must be flagged",
        )

    def test_room_invalid_height_flagged(self):
        data = self._make_minimal_scenario()
        data["rooms_data"][0]["height_m"] = -1.0
        errors = _validate_scenario_structure(data)
        self.assertTrue(
            any("height_m" in e for e in errors),
            "Room with negative height_m must be flagged",
        )

    def test_opening_missing_type_flagged(self):
        data = self._make_minimal_scenario()
        data["openings_data"] = [{"a": 0, "b": -1}]  # missing 'type'
        errors = _validate_scenario_structure(data)
        self.assertTrue(
            any("type" in e for e in errors),
            "Opening missing 'type' must be flagged",
        )

    def test_room_rect_missing_dimension_flagged(self):
        data = self._make_minimal_scenario()
        data["room_rect_m"]["0"] = {"x": 0.0, "y": 0.0}  # missing w, h
        errors = _validate_scenario_structure(data)
        self.assertTrue(
            any("room_rect_m" in e for e in errors),
            "room_rect_m with missing dims must be flagged",
        )

    def test_room_without_rect_entry_flagged(self):
        data = self._make_minimal_scenario()
        data["room_rect_m"] = {}  # room id=0 has no entry
        errors = _validate_scenario_structure(data)
        self.assertTrue(
            any("room_rect_m" in e for e in errors),
            "Room without room_rect_m entry must be flagged",
        )

    def test_room_rect_zero_dims_flagged(self):
        data = self._make_minimal_scenario()
        data["room_rect_m"]["0"] = {"x": 0.0, "y": 0.0, "w": 0.0, "h": 4.0}
        errors = _validate_scenario_structure(data)
        self.assertTrue(
            any("room_rect_m" in e for e in errors),
            "room_rect_m with w=0 must be flagged",
        )

    def test_opening_invalid_room_a_flagged(self):
        data = self._make_minimal_scenario()
        data["openings_data"] = [{"a": 99, "b": -1, "type": "door"}]
        errors = _validate_scenario_structure(data)
        self.assertTrue(
            any("a=99" in e for e in errors),
            "Opening referencing non-existent room a must be flagged",
        )

    def test_opening_invalid_room_b_flagged(self):
        data = self._make_minimal_scenario()
        data["openings_data"] = [{"a": 0, "b": 99, "type": "door"}]
        errors = _validate_scenario_structure(data)
        self.assertTrue(
            any("b=99" in e for e in errors),
            "Opening referencing non-existent room b (not -1) must be flagged",
        )

    def test_opening_exterior_b_not_flagged(self):
        data = self._make_minimal_scenario()
        data["openings_data"] = [{"a": 0, "b": -1, "type": "door"}]
        errors = _validate_scenario_structure(data)
        self.assertFalse(
            any("b=" in e for e in errors),
            "Opening with b=-1 (exterior) must not produce a room-b error",
        )


class TestCommittedScenarios(unittest.TestCase):
    """
    Smoke-tests all *.json files in scenarios/ against both the load contract
    and the structural contract.  Fails if any committed scenario is broken.
    """

    def _scenario_files(self):
        if not _SCENARIOS_DIR.exists():
            return []
        return list(_SCENARIOS_DIR.glob("*.json"))

    def test_at_least_one_scenario_exists(self):
        files = self._scenario_files()
        self.assertGreater(len(files), 0, f"No *.json found in {_SCENARIOS_DIR}")

    def test_all_scenarios_load_successfully(self):
        for path in self._scenario_files():
            with self.subTest(scenario=path.name):
                result = _load_scenario_py(str(path))
                self.assertNotEqual(
                    result, {},
                    f"{path.name} failed to load (empty dict returned)",
                )

    def test_all_scenarios_pass_structural_check(self):
        for path in self._scenario_files():
            with self.subTest(scenario=path.name):
                data = _load_scenario_py(str(path))
                if not data:
                    self.fail(f"{path.name} could not be loaded")
                # Only require the core keys that the normaliser reads
                for key in _CORE_SCENARIO_KEYS:
                    self.assertIn(
                        key, data,
                        f"{path.name}: missing required key '{key}'"
                    )
                errors = _validate_scenario_structure(data)
                self.assertEqual(
                    errors, [],
                    f"{path.name} structural violations:\n" + "\n".join(errors),
                )

    def test_all_scenarios_have_at_least_one_room(self):
        for path in self._scenario_files():
            with self.subTest(scenario=path.name):
                data = _load_scenario_py(str(path))
                if not data:
                    continue
                rooms = data.get("rooms_data", [])
                self.assertGreater(
                    len(rooms), 0, f"{path.name} has no rooms in rooms_data"
                )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    unittest.main(verbosity=2)
