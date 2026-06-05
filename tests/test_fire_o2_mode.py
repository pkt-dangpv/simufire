"""Structural and arithmetic checks for the M2 local combustion O2 contract."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ROOM = (ROOT / "sim" / "building" / "RoomModel.gd").read_text(encoding="utf-8")
COMBUSTION = (ROOT / "sim" / "fire" / "CombustionSystem.gd").read_text(encoding="utf-8")
OXYGEN = (ROOT / "sim" / "core" / "OxygenExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(encoding="utf-8")
CASE_RUNNER = (ROOT / "sim" / "validation" / "CaseRunner.gd").read_text(encoding="utf-8")
RUN_CASE = (ROOT / "sim" / "validation" / "run_case.ps1").read_text(encoding="utf-8")
COMPARE_RUNNER = (
    ROOT / "sim" / "validation" / "run_legacy_two_zone_compare.ps1"
).read_text(encoding="utf-8")


class TestFireO2Arithmetic(unittest.TestCase):
    def test_interface_sample_is_midpoint(self):
        lower, upper = 0.209, 0.071
        self.assertAlmostEqual(lower + (upper - lower) * 0.5, 0.14)

    def test_legacy_upper_blend_zero_is_bulk_o2(self):
        bulk, upper, blend = 0.16, 0.08, 0.0
        effective = bulk + (min(bulk, upper) - bulk) * blend
        self.assertAlmostEqual(effective, bulk)


class TestFireO2Structure(unittest.TestCase):
    def test_engine_exposes_single_mode_with_legacy_default(self):
        self.assertIn(
            '@export_enum("legacy", "upper", "lower", "interface") '
            'var fire_o2_mode: String = "legacy"',
            ENGINE,
        )

    def test_combustion_resolves_all_local_samples(self):
        self.assertIn('if mode == "upper":', COMBUSTION)
        self.assertIn("o2_ref = room.o2_upper", COMBUSTION)
        self.assertIn('elif mode == "lower":', COMBUSTION)
        self.assertIn("o2_ref = room.o2_lower", COMBUSTION)
        self.assertIn('elif mode == "interface":', COMBUSTION)
        self.assertIn("lerpf(room.o2_lower, room.o2_upper, 0.5)", COMBUSTION)

    def test_legacy_flags_remain_fallback_only(self):
        resolver = COMBUSTION.split("func _resolve_fire_o2_mode(", 1)[1].split("\nfunc ", 1)[0]
        explicit_index = resolver.index('if mode == "upper" or mode == "lower" or mode == "interface":')
        legacy_flag_index = resolver.index('context.get("fire_o2_upper_for_flame"')
        self.assertLess(explicit_index, legacy_flag_index)

    def test_legacy_upper_threshold_stays_legacy_only(self):
        selection = COMBUSTION.split("func _resolve_fire_o2_selection(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("not _has_explicit_fire_o2_mode(context)", selection)
        self.assertIn('context.get("fire_o2_upper_min_for_flame"', selection)

    def test_explicit_modes_step_oxygen_before_hrr(self):
        step = ENGINE.split("func step(delta: float) -> void:", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("var pre_hrr_o2_step: bool = _uses_pre_hrr_oxygen_step()", step)
        self.assertLess(step.index("if pre_hrr_o2_step:"), step.index("_step_fire(dt)"))
        self.assertIn("if not pre_hrr_o2_step:", step)

    def test_explicit_modes_use_local_full_hrr_o2_reference(self):
        opening_block = COMBUSTION.split("var early_opening_signal: float = clampf(", 1)[1]
        opening_block = opening_block.split("var full_hrr_o2", 1)[0]
        self.assertIn("1.0 if _has_explicit_fire_o2_mode(context) else 0.0", opening_block)
        self.assertIn("if _has_explicit_fire_o2_mode(context) else 0.0", COMBUSTION)

    def test_legacy_lower_consumption_is_preserved(self):
        self.assertIn("return fire_o2_lower_for_flame", OXYGEN)
        self.assertIn("not fire_uses_lower_o2", OXYGEN)
        self.assertIn("if fire_uses_lower_o2 and room.hrr_kw > 0.0:", OXYGEN)

    def test_room_and_state_expose_combustion_o2_sample(self):
        for field in ("fire_o2_mode_used", "fire_o2_ref", "fire_o2_min_ref"):
            self.assertIn(f"var {field}", ROOM)
            self.assertIn(f'"{field}"', STATE)

    def test_validation_cli_can_select_mode_without_editing_case(self):
        self.assertIn("--validation-fire-o2-mode=", CASE_RUNNER)
        self.assertIn("[string]$FireO2Mode", RUN_CASE)
        self.assertIn("-FireO2Mode $FireO2Mode", COMPARE_RUNNER)


if __name__ == "__main__":
    unittest.main(verbosity=2)
