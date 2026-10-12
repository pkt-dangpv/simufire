"""F3.1 regression checks for strict selected-O2 extinction."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestF31ZeroO2Extinction(unittest.TestCase):
    def test_selected_o2_guard_is_explicit(self):
        step = _function(COMBUSTION, "step_room_fire")
        self.assertIn("selected_o2_extinguished", step)
        self.assertIn("o2_ref <= o2_min_ref", step)
        self.assertIn("not o2_independent", step)

    def test_guard_clears_all_combustion_heat_release(self):
        guard = _function(COMBUSTION, "_apply_selected_o2_extinction_guard")
        for assignment in (
            "room.flame_hrr_target_kw = 0.0",
            "room.smolder_hrr_target_kw = 0.0",
            "room.pool_release_hrr_target_kw = 0.0",
            "room.hrr_target_kw = 0.0",
            "room.hrr_kw = 0.0",
            "room.burned_hrr_kw = 0.0",
        ):
            self.assertIn(assignment, guard)

    def test_retained_generation_is_cut_before_pool_update(self):
        step = _function(COMBUSTION, "step_room_fire")
        cutoff = step.index("if selected_o2_extinguished:\n\t\tsolid_pyrolysis_kw = 0.0")
        # M3 keeps the pool proposal local until oxygen acceptance. The cutoff
        # must precede that computation, not merely its eventual room commit.
        pool_update = step.index("proposed_pool_MJ = minf")
        self.assertLess(cutoff, pool_update)
        for assignment in ("solid_pyrolysis_kw = 0.0", "solid_fuel_demand_MJ = 0.0",
                           "fresh_flame_target_kw = 0.0", "smolder_target_kw = 0.0",
                           "retained_generation_kw = 0.0"):
            self.assertIn(assignment, step[cutoff:pool_update])
        self.assertIn("if not m3_acceptance:\n\t\troom.retained_unburned_MJ = proposed_pool_MJ", step)

    def test_guard_marks_o2_extinction_without_destroying_fire_state(self):
        guard = _function(COMBUSTION, "_apply_selected_o2_extinction_guard")
        self.assertIn("room.fire_o2_extinguished = true", guard)
        self.assertNotIn("room.fire = null", guard)
        self.assertNotIn("_extinguish_room_fire", guard)

    def test_analytic_o2_independent_mode_remains_exempt(self):
        step = _function(COMBUSTION, "step_room_fire")
        selection = step.split("selected_o2_extinguished", 1)[1].split("\n", 1)[0]
        self.assertIn("not o2_independent", selection)


if __name__ == "__main__":
    unittest.main()
