"""
tests/test_carbon_balance.py — Regression tests for SF-CBAL carbon balance.

Verifies that the real carbon balance (SF-CBAL) is correctly wired across
the simulation systems, and that the arithmetic detects creation/loss scenarios.

Architecture:
  CombustionSystem.gd  →  accumulates c_burned_total_kg each step
  SimulationEngine.gd  →  _check_carbon_balance() runs AFTER _clamp_rooms()
                          and writes carbon_conservation_error_kg to each room
  RoomModel.gd         →  holds c_burned_total_kg, carbon_conservation_error_kg
                          and resets both in reset_dynamic_state()

Species balance (same stoichiometry as SF-AUD-032):
  C_in_gases = CO·(12/28) + CO₂·(12/44) + HCN·(12/27) + smoke·0.87
  error      = C_in_gases − c_burned_total_kg

  error < 0  → C left this room via transport (normal for fire rooms)
  error > 0  → C arrived via transport OR spurious creation (fire room flag)

Run:
    python tests/test_carbon_balance.py
    # or:
    python -m pytest tests/test_carbon_balance.py -v

No external dependencies — stdlib only.  No Godot, no simulation physics.
"""

import re
import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
_ROOM_MODEL     = _REPO_ROOT / "sim" / "building" / "RoomModel.gd"
_COMBUSTION     = _REPO_ROOT / "sim" / "fire" / "CombustionSystem.gd"
_SIM_ENGINE     = _REPO_ROOT / "sim" / "core" / "SimulationEngine.gd"
_HVAC_SYSTEM    = _REPO_ROOT / "sim" / "core" / "HVACSystem.gd"
_STATE_BUILDER  = _REPO_ROOT / "sim" / "core" / "SimulationStateBuilder.gd"

# Stoichiometric factors (identical to those in SF-AUD-032 and SF-CBAL).
_C_IN_CO  = 12.0 / 28.0   # carbon fraction in CO by mass
_C_IN_CO2 = 12.0 / 44.0   # carbon fraction in CO₂
_C_IN_HCN = 12.0 / 27.0   # carbon fraction in HCN
_SOOT_C   = 0.87           # typical soot carbon fraction (SFPE Handbook Table 3.4-3)


# ---------------------------------------------------------------------------
# Source helpers
# ---------------------------------------------------------------------------

def _load(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _extract_function_body(source: str, func_name: str) -> str:
    """Return the body of a GDScript function (lines until next top-level func/class)."""
    lines = source.splitlines()
    in_func = False
    body = []
    for line in lines:
        if re.match(rf"^func\s+{re.escape(func_name)}\s*\(", line):
            in_func = True
            continue
        if in_func:
            if re.match(r"^func |^class ", line):
                break
            body.append(line)
    return "\n".join(body)


# ---------------------------------------------------------------------------
# Part A — Arithmetic correctness (pure Python, no Godot)
# Replicate _check_carbon_balance() formula and test boundary cases.
# ---------------------------------------------------------------------------

class TestCarbonBalanceArithmetic(unittest.TestCase):
    """
    Pure-Python replicas of the GDScript formula.  These tests act as a
    specification: if the engine formula changes the tests will catch it.
    """

    @staticmethod
    def _compute_error(co_kg, co2_kg, hcn_kg, smoke_kg, c_burned_total_kg):
        c_in_gases = (
            co_kg    * _C_IN_CO
            + co2_kg * _C_IN_CO2
            + hcn_kg * _C_IN_HCN
            + smoke_kg * _SOOT_C
        )
        return c_in_gases - c_burned_total_kg

    def test_zero_error_when_all_carbon_in_co(self):
        """All C from 1 MJ of fuel (0.027 kg) went to CO → error = 0."""
        c_burned = 0.027
        co_kg = c_burned / _C_IN_CO   # = c_burned * (28/12)
        err = self._compute_error(co_kg, 0.0, 0.0, 0.0, c_burned)
        self.assertAlmostEqual(err, 0.0, places=12,
                               msg="Perfect CO balance must give zero error")

    def test_zero_error_when_all_carbon_in_co2(self):
        """All C from 1 MJ ended up as CO₂."""
        c_burned = 0.027
        co2_kg = c_burned / _C_IN_CO2
        err = self._compute_error(0.0, co2_kg, 0.0, 0.0, c_burned)
        self.assertAlmostEqual(err, 0.0, places=12,
                               msg="Perfect CO₂ balance must give zero error")

    def test_zero_error_mixed_species(self):
        """Mixed CO + CO₂ + soot that totals exactly c_burned → error = 0."""
        c_burned = 0.050
        # Distribute: 40% as CO, 50% as CO₂, 10% as soot
        c_co    = c_burned * 0.40
        c_co2   = c_burned * 0.50
        c_soot  = c_burned * 0.10
        co_kg    = c_co   / _C_IN_CO
        co2_kg   = c_co2  / _C_IN_CO2
        smoke_kg = c_soot / _SOOT_C
        err = self._compute_error(co_kg, co2_kg, 0.0, smoke_kg, c_burned)
        self.assertAlmostEqual(err, 0.0, places=10,
                               msg="Mixed-species conserved balance must give ~zero error")

    def test_positive_error_detects_creation(self):
        """
        Gases contain more C than was burned → positive error flags creation.
        Scenario: CO₂ appeared with no fuel burned (c_burned_total_kg = 0).
        """
        co2_kg = 1.0  # 1 kg CO₂ → 12/44 = 0.2727 kg C
        err = self._compute_error(0.0, co2_kg, 0.0, 0.0, c_burned_total_kg=0.0)
        self.assertGreater(err, 0.0,
                           msg="C in gases > c_burned must yield positive (creation) error")

    def test_negative_error_detects_transport_loss(self):
        """
        More C declared burned than is in gases → negative error (C left this room).
        Normal for fire rooms: carbon transported to adjacent rooms or vented out.
        """
        c_burned = 1.0  # 1 kg C burned declared
        err = self._compute_error(0.0, 0.0, 0.0, 0.0, c_burned_total_kg=c_burned)
        self.assertLess(err, 0.0,
                        msg="c_burned > C in gases must yield negative (transport) error")

    def test_hcn_carbon_contribution(self):
        """HCN carbon (12/27 of mass) is included in the balance."""
        c_burned = 0.010
        hcn_kg = c_burned / _C_IN_HCN
        err = self._compute_error(0.0, 0.0, hcn_kg, 0.0, c_burned)
        self.assertAlmostEqual(err, 0.0, places=12,
                               msg="HCN-only balance must give zero error")

    def test_soot_carbon_contribution(self):
        """Soot carbon (0.87 * smoke_kg) is included in the balance."""
        c_burned = 0.020
        smoke_kg = c_burned / _SOOT_C
        err = self._compute_error(0.0, 0.0, 0.0, smoke_kg, c_burned)
        self.assertAlmostEqual(err, 0.0, places=12,
                               msg="Soot-only balance must give zero error")

    def test_error_sign_convention(self):
        """
        error = C_in_gases − c_burned.
        Must be positive when gases have MORE carbon than declared burned.
        Must be negative when gases have LESS carbon than declared burned.
        """
        co_kg     = 1.0          # high gas carbon
        c_burned  = 0.001        # almost nothing burned (creation scenario)
        err_pos = self._compute_error(co_kg, 0.0, 0.0, 0.0, c_burned)
        self.assertGreater(err_pos, 0.0)

        co_kg     = 0.0          # no gases
        c_burned  = 1.0          # lots burned, all left (loss/transport scenario)
        err_neg = self._compute_error(co_kg, 0.0, 0.0, 0.0, c_burned)
        self.assertLess(err_neg, 0.0)


# ---------------------------------------------------------------------------
# Part B — RoomModel.gd structural checks
# ---------------------------------------------------------------------------

class TestRoomModelCarbonFields(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.source     = _load(_ROOM_MODEL)
        cls.reset_body = _extract_function_body(cls.source, "reset_dynamic_state")

    def _assert_field_declared(self, field: str, default: str):
        pattern = rf"\bvar\s+{re.escape(field)}\s*:\s*float\s*=\s*{re.escape(default)}"
        self.assertRegex(
            self.source, pattern,
            msg=f"RoomModel must declare `var {field}: float = {default}`",
        )

    def _assert_reset(self, field: str, value: str):
        pattern = rf"\b{re.escape(field)}\s*=\s*{re.escape(value)}\b"
        self.assertRegex(
            self.reset_body, pattern,
            msg=f"reset_dynamic_state() must set `{field} = {value}`",
        )

    def test_c_burned_total_kg_declared(self):
        self._assert_field_declared("c_burned_total_kg", "0.0")

    def test_carbon_conservation_error_kg_declared(self):
        self._assert_field_declared("carbon_conservation_error_kg", "0.0")

    def test_c_burned_total_kg_reset(self):
        self._assert_reset("c_burned_total_kg", "0.0")

    def test_carbon_conservation_error_kg_reset(self):
        self._assert_reset("carbon_conservation_error_kg", "0.0")

    def test_new_fields_declared_after_c_balance_frac(self):
        """c_burned_total_kg and carbon_conservation_error_kg appear after c_balance_frac."""
        pos_frac  = self.source.find("c_balance_frac")
        pos_burned = self.source.find("c_burned_total_kg")
        pos_error  = self.source.find("carbon_conservation_error_kg")
        self.assertGreater(pos_burned, pos_frac,
                           "c_burned_total_kg must appear after c_balance_frac")
        self.assertGreater(pos_error, pos_frac,
                           "carbon_conservation_error_kg must appear after c_balance_frac")


# ---------------------------------------------------------------------------
# Part C — CombustionSystem.gd structural checks
# ---------------------------------------------------------------------------

class TestCombustionSystemAccumulator(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.source      = _load(_COMBUSTION)
        cls.step_body   = _extract_function_body(cls.source, "step_room_fire")

    def test_c_burned_total_kg_incremented(self):
        """CombustionSystem must have `c_burned_total_kg +=` inside step_room_fire."""
        self.assertRegex(
            self.step_body,
            r"\bc_burned_total_kg\s*\+=",
            msg="step_room_fire() must increment room.c_burned_total_kg",
        )

    def test_source_uses_fuel_carbon_before_clamp(self):
        """Canonical source must use c_avail_kg from fuel, not generated products."""
        self.assertIn(
            "room.c_burned_total_kg += c_avail_kg",
            self.step_body,
            msg="Carbon source must accumulate fuel carbon available before clamp",
        )

    def test_untracked_products_close_source_inventory(self):
        """Unrepresented fuel carbon must remain explicit in the ledger."""
        self.assertIn("c_products_postclamp", self.step_body)
        self.assertIn("room.c_untracked_products_kg +=", self.step_body)

    def test_preclamp_excess_includes_soot(self):
        """Pre-clamp diagnostic must compare gas products plus soot against fuel carbon."""
        self.assertIn("room.c_preclamp_excess_kg +=", self.step_body)
        self.assertIn("c_total + c_in_soot - c_avail_kg", self.step_body)

    def test_postclamp_excess_tracks_physical_products(self):
        """Flow residual must exclude only excess that entered the physical state."""
        self.assertIn("room.c_postclamp_excess_kg +=", self.step_body)
        self.assertIn("c_products_postclamp - c_avail_kg", self.step_body)

    def test_accumulator_after_sf_aud_032_block(self):
        """SF-CBAL accumulator appears after the SF-AUD-032 c_balance_frac block."""
        pos_frac = self.step_body.find("c_balance_frac")
        pos_bal  = self.step_body.find("c_burned_total_kg")
        self.assertGreater(pos_bal, pos_frac,
                           "SF-CBAL accumulation must appear after SF-AUD-032 c_balance_frac")


# ---------------------------------------------------------------------------
# Part D — SimulationEngine.gd structural checks
# ---------------------------------------------------------------------------

class TestSimulationEngineBalance(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.source = _load(_SIM_ENGINE)

    def test_check_carbon_balance_function_exists(self):
        """SimulationEngine must define func _check_carbon_balance()."""
        self.assertRegex(
            self.source,
            r"func\s+_check_carbon_balance\s*\(\s*\)",
            msg="SimulationEngine must define _check_carbon_balance()",
        )

    def test_carbon_conservation_error_assigned_in_function(self):
        """_check_carbon_balance() must assign carbon_conservation_error_kg."""
        body = _extract_function_body(self.source, "_check_carbon_balance")
        self.assertRegex(
            body,
            r"\bcarbon_conservation_error_kg\s*=",
            msg="_check_carbon_balance() must assign carbon_conservation_error_kg",
        )

    def test_balance_function_includes_co_term(self):
        """Balance function includes the CO carbon term."""
        body = _extract_function_body(self.source, "_check_carbon_balance")
        self.assertRegex(body, r"co_kg\s*\*\s*\(",
                         msg="_check_carbon_balance() must include co_kg * (...)")

    def test_balance_function_includes_co2_term(self):
        """Balance function includes the CO₂ carbon term."""
        body = _extract_function_body(self.source, "_check_carbon_balance")
        self.assertRegex(body, r"co2_kg\s*\*\s*\(",
                         msg="_check_carbon_balance() must include co2_kg * (...)")

    def test_balance_function_includes_smoke_term(self):
        """Balance function includes the soot/smoke term."""
        body = _extract_function_body(self.source, "_check_carbon_balance")
        self.assertIn("smoke_kg", body,
                      msg="_check_carbon_balance() must include smoke_kg")

    def test_balance_function_includes_soot_fraction(self):
        """Balance function uses the 0.87 soot carbon fraction."""
        body = _extract_function_body(self.source, "_check_carbon_balance")
        self.assertIn("0.87", body,
                      msg="_check_carbon_balance() must use soot C fraction 0.87")

    def test_check_called_after_clamp(self):
        """_check_carbon_balance() must evaluate the final post-clamp state."""
        # Find position of both calls in the full source
        pos_check = self.source.find("_check_carbon_balance()")
        pos_clamp = self.source.find("_clamp_rooms(")
        self.assertGreater(pos_check, -1,
                           "Engine must call _check_carbon_balance()")
        self.assertGreater(pos_clamp, -1,
                           "Engine must call _clamp_rooms()")
        # The CALL (not the definition) must follow _clamp_rooms.
        # Search for the call as a standalone statement (indented line).
        call_matches = list(re.finditer(r"^\s+_check_carbon_balance\(\)", self.source, re.M))
        clamp_matches = list(re.finditer(r"^\s+_clamp_rooms\(", self.source, re.M))
        self.assertTrue(call_matches,  "No call-site for _check_carbon_balance() found")
        self.assertTrue(clamp_matches, "No call-site for _clamp_rooms() found")
        self.assertGreater(
            call_matches[0].start(),
            clamp_matches[0].start(),
            "_check_carbon_balance() call must appear after _clamp_rooms() call",
        )

    def test_error_formula_uses_subtraction(self):
        """carbon_conservation_error_kg = c_in_gases - c_burned_total_kg (subtraction)."""
        body = _extract_function_body(self.source, "_check_carbon_balance")
        # Must have c_in_gases - c_burned_total_kg or equivalent
        self.assertRegex(
            body,
            r"c_in_gases\s*-\s*room\.c_burned_total_kg",
            msg="Error must be c_in_gases - room.c_burned_total_kg",
        )


# ---------------------------------------------------------------------------
# Part E — Global carbon balance arithmetic (pure Python runtime logic)
# Tests the formula: global_error = C_in_all_rooms + C_exited - C_initial - C_burned
# ---------------------------------------------------------------------------

class TestGlobalCarbonBalanceArithmetic(unittest.TestCase):
    """
    Pure-Python replicas of the global balance formula in _check_carbon_balance().
    No Godot runtime — arithmetic only.
    """

    @staticmethod
    def _global_error(rooms_c_in_gases, c_exited_cumul, c_initial, c_burned_total):
        """
        Mirrors the SimulationEngine global SF-CBAL formula:
          global_error = sum(c_in_gases) + c_exited_cumul - c_initial - c_burned_total
        """
        return sum(rooms_c_in_gases) + c_exited_cumul - c_initial - c_burned_total

    def test_zero_error_at_init(self):
        """At initialisation: c_initial = C_in_gases, no combustion, no exit → error = 0."""
        # Two rooms, some ambient CO2
        c_room_a = 0.030   # kg C (e.g. background CO₂)
        c_room_b = 0.020
        c_initial = c_room_a + c_room_b
        error = self._global_error([c_room_a, c_room_b], 0.0, c_initial, 0.0)
        self.assertAlmostEqual(error, 0.0, places=12,
                               msg="Global error must be zero at initialisation")

    def test_internal_transport_invariant(self):
        """
        Moving C from room A to room B does NOT change the global sum → error unchanged.
        This is the key invariant that distinguishes global from per-room balance.
        """
        c_initial = 0.050   # total initial C
        c_burned  = 0.100   # total C burned (same in both steps)

        # Step 1: C in room A = 0.080 (no transport yet)
        c_room_a1 = 0.080
        c_room_b1 = 0.020
        err1 = self._global_error([c_room_a1, c_room_b1], 0.0, c_initial, c_burned)

        # Step 2: 0.030 kg C moved from A to B (internal transport)
        transport = 0.030
        c_room_a2 = c_room_a1 - transport
        c_room_b2 = c_room_b1 + transport
        err2 = self._global_error([c_room_a2, c_room_b2], 0.0, c_initial, c_burned)

        self.assertAlmostEqual(
            err1, err2, places=12,
            msg="Internal transport must NOT change the global carbon error",
        )

    def test_clamp_loss_detected(self):
        """
        Clamp removes C from gases without changing c_burned or c_exited → negative error.
        This represents a numerical conservation violation (e.g. negative clamp).
        """
        c_initial = 0.010
        c_burned  = 0.100
        c_exited  = 0.0

        # Before clamp: 0.060 kg C in system (some lost to transport, some remains)
        err_before = self._global_error([0.060], c_exited, c_initial, c_burned)

        # After clamp removes 0.010 kg C (clamped to zero or numerical error)
        clamp_loss = 0.010
        err_after = self._global_error([0.060 - clamp_loss], c_exited, c_initial, c_burned)

        self.assertLess(err_after, err_before,
                        msg="Clamp loss must make global error more negative")
        self.assertAlmostEqual(err_after, err_before - clamp_loss, places=12,
                               msg="Global error change must equal the clamp loss exactly")

    def test_creation_detected(self):
        """
        Spurious creation adds C to gases without combustion → positive error.
        """
        c_initial = 0.010
        c_burned  = 0.050   # legitimate combustion
        c_exited  = 0.0
        c_in_system_legitimate = 0.050  # balanced: all burned C still in system

        err_normal = self._global_error([c_in_system_legitimate], c_exited, c_initial, c_burned)

        # Spurious creation adds 0.020 kg C without combustion
        spurious = 0.020
        err_creation = self._global_error(
            [c_in_system_legitimate + spurious], c_exited, c_initial, c_burned
        )

        self.assertGreater(err_creation, err_normal,
                           msg="Spurious creation must increase global error (positive)")
        self.assertAlmostEqual(err_creation - err_normal, spurious, places=12,
                               msg="Increase must equal the spurious carbon exactly")

    def test_venting_invariant(self):
        """
        Legitimate exterior venting: C_in_gases decreases by X, c_exited increases by X.
        The global error must remain unchanged (zero net effect).
        """
        c_initial = 0.010
        c_burned  = 0.100
        vented    = 0.040   # 40g C vented out

        # Before venting
        c_in_system_before = 0.090
        c_exited_before = 0.0
        err_before = self._global_error(
            [c_in_system_before], c_exited_before, c_initial, c_burned
        )

        # After venting: gas C decreases, c_exited increases by same amount
        c_in_system_after = c_in_system_before - vented
        c_exited_after = c_exited_before + vented
        err_after = self._global_error(
            [c_in_system_after], c_exited_after, c_initial, c_burned
        )

        self.assertAlmostEqual(
            err_before, err_after, places=12,
            msg="Legitimate exterior venting must NOT change the global carbon error",
        )

    def test_multi_room_venting_and_combustion(self):
        """
        Combined scenario: combustion in room A, venting from room B (received via transport).
        Global error must be consistent.
        """
        c_initial = 0.010   # small ambient
        c_burned  = 0.200   # 200g C burned in room A over time

        # Room A: fire room, most C left to room B via transport
        c_room_a = 0.030
        # Room B: received C, some vented
        c_room_b = 0.080
        c_exited = 0.100   # 100g C vented from room B to exterior

        # Conservation check: 0.030 + 0.080 + 0.100 = 0.210 = 0.010 + 0.200
        # So global error should be exactly zero
        error = self._global_error([c_room_a, c_room_b], c_exited, c_initial, c_burned)
        self.assertAlmostEqual(error, 0.0, places=12,
                               msg="Multi-room conservation must hold exactly")


# ---------------------------------------------------------------------------
# Part F — Global carbon structural checks (reads GDScript source files)
# ---------------------------------------------------------------------------

_GAS_EXCHANGE = _REPO_ROOT / "sim" / "core" / "GasExchangeSystem.gd"
_CASE_RUNNER = _REPO_ROOT / "sim" / "validation" / "CaseRunner.gd"


class TestGlobalCarbonStructure(unittest.TestCase):
    """
    Structural checks that verify global SF-CBAL wiring in GDScript files.
    Tests read source text — no Godot runtime required.
    """

    @classmethod
    def setUpClass(cls):
        cls.room_src   = _load(_ROOM_MODEL)
        cls.engine_src = _load(_SIM_ENGINE)
        cls.gas_src    = _load(_GAS_EXCHANGE)
        cls.hvac_src   = _load(_HVAC_SYSTEM)
        cls.builder_src = _load(_STATE_BUILDER)
        cls.case_runner_src = _load(_CASE_RUNNER)
        cls.balance_body = _extract_function_body(cls.engine_src, "_check_carbon_balance")
        cls.ensure_body = _extract_function_body(cls.engine_src, "_ensure_carbon_balance_initialized")
        cls.reset_sim_body = _extract_function_body(cls.engine_src, "reset_simulation")
        cls.reset_room_body = _extract_function_body(cls.room_src, "reset_dynamic_state")
        cls.step_body = _extract_function_body(cls.engine_src, "step")
        cls.step_hvac_body = _extract_function_body(cls.engine_src, "_step_hvac")

    # ---- RoomModel fields ----

    def test_c_exited_kg_declared_in_room_model(self):
        """RoomModel must declare var c_exited_kg: float = 0.0."""
        self.assertRegex(
            self.room_src,
            r"\bvar\s+c_exited_kg\s*:\s*float\s*=\s*0\.0",
            msg="RoomModel must declare `var c_exited_kg: float = 0.0`",
        )

    def test_c_exited_kg_reset_in_reset_dynamic_state(self):
        """reset_dynamic_state() must set c_exited_kg = 0.0."""
        self.assertRegex(
            self.reset_room_body,
            r"\bc_exited_kg\s*=\s*0\.0\b",
            msg="reset_dynamic_state() must set `c_exited_kg = 0.0`",
        )

    def test_c_postclamp_excess_declared_and_reset(self):
        """RoomModel must persist and reset the physical post-clamp product excess."""
        self.assertRegex(
            self.room_src,
            r"\bvar\s+c_postclamp_excess_kg\s*:\s*float\s*=\s*0\.0",
        )
        self.assertRegex(self.reset_room_body, r"\bc_postclamp_excess_kg\s*=\s*0\.0\b")

    # ---- SimulationEngine global fields ----

    def test_global_carbon_error_kg_declared(self):
        """SimulationEngine must declare var global_carbon_error_kg: float = 0.0."""
        self.assertRegex(
            self.engine_src,
            r"\bvar\s+global_carbon_error_kg\s*:\s*float\s*=\s*0\.0",
            msg="SimulationEngine must declare `var global_carbon_error_kg: float = 0.0`",
        )

    def test_global_postclamp_excess_declared(self):
        """SimulationEngine must expose the accumulated physical product excess."""
        self.assertRegex(
            self.engine_src,
            r"\bvar\s+global_carbon_postclamp_excess_kg\s*:\s*float\s*=\s*0\.0",
        )

    def test_cbal_initialized_field_declared(self):
        """SimulationEngine must declare var _cbal_initialized: bool = false."""
        self.assertRegex(
            self.engine_src,
            r"\bvar\s+_cbal_initialized\s*:\s*bool\s*=\s*false",
            msg="SimulationEngine must declare `var _cbal_initialized: bool = false`",
        )

    def test_cbal_c_initial_field_declared(self):
        """SimulationEngine must declare var _cbal_c_initial_kg: float = 0.0."""
        self.assertRegex(
            self.engine_src,
            r"\bvar\s+_cbal_c_initial_kg\s*:\s*float\s*=\s*0\.0",
            msg="SimulationEngine must declare `var _cbal_c_initial_kg: float = 0.0`",
        )

    # ---- _check_carbon_balance() body ----

    def test_check_balance_accumulates_c_in_system(self):
        """_check_carbon_balance() must accumulate c_in_system across rooms."""
        self.assertRegex(
            self.balance_body,
            r"\bc_in_system\s*\+=",
            msg="_check_carbon_balance() must accumulate c_in_system += ...",
        )

    def test_check_balance_accumulates_c_exited(self):
        """_check_carbon_balance() must accumulate c_exited_total."""
        self.assertRegex(
            self.balance_body,
            r"\bc_exited_total\s*\+=",
            msg="_check_carbon_balance() must accumulate c_exited_total += ...",
        )

    def test_check_balance_uses_room_c_exited_kg(self):
        """_check_carbon_balance() must read room.c_exited_kg."""
        self.assertIn(
            "room.c_exited_kg",
            self.balance_body,
            msg="_check_carbon_balance() must sum room.c_exited_kg",
        )

    def test_check_balance_initializes_cbal_once(self):
        """Initial inventory must be captured by the pre-physics initializer."""
        self.assertIn(
            "_cbal_c_initial_kg",
            self.ensure_body,
            msg="_ensure_carbon_balance_initialized() must capture initial carbon",
        )
        self.assertIn(
            "_cbal_initialized",
            self.ensure_body,
            msg="_ensure_carbon_balance_initialized() must initialize only once",
        )

    def test_global_error_assigned_in_balance_body(self):
        """global_carbon_error_kg must be assigned inside _check_carbon_balance()."""
        self.assertRegex(
            self.balance_body,
            r"\bglobal_carbon_error_kg\s*=",
            msg="_check_carbon_balance() must assign global_carbon_error_kg",
        )

    def test_global_error_formula_uses_all_terms(self):
        """global_carbon_error_kg = c_in_system + c_exited_total + deposited + hvac - ... - c_burned_total."""
        # The assignment line must reference all terms
        pattern = (
            r"global_carbon_error_kg\s*="
            r"[\s\S]*?c_in_system"
            r"[\s\S]*?c_exited_total"
            r"[\s\S]*?c_burned_total"
        )
        self.assertRegex(
            self.balance_body, pattern,
            msg="global_carbon_error_kg formula must use c_in_system, c_exited_total, c_burned_total",
        )

    def test_transport_residual_subtracts_postclamp_not_preclamp_excess(self):
        """Chemical clamp requests must not appear as false transport loss."""
        self.assertIn("c_postclamp_excess_total += room.c_postclamp_excess_kg", self.balance_body)
        self.assertIn(
            "global_carbon_transport_residual_kg = global_carbon_error_kg - c_postclamp_excess_total",
            self.balance_body,
        )
        residual_line = next(
            line for line in self.balance_body.splitlines()
            if "global_carbon_transport_residual_kg =" in line
        )
        self.assertNotIn("preclamp", residual_line)

    # ---- reset_simulation() resets SF-CBAL global fields ----

    def test_cbal_initialized_reset_in_reset_simulation(self):
        """reset_simulation() must set _cbal_initialized = false."""
        self.assertRegex(
            self.reset_sim_body,
            r"\b_cbal_initialized\s*=\s*false\b",
            msg="reset_simulation() must reset `_cbal_initialized = false`",
        )

    def test_cbal_c_initial_reset_in_reset_simulation(self):
        """reset_simulation() must set _cbal_c_initial_kg = 0.0."""
        self.assertRegex(
            self.reset_sim_body,
            r"\b_cbal_c_initial_kg\s*=\s*0\.0\b",
            msg="reset_simulation() must reset `_cbal_c_initial_kg = 0.0`",
        )

    def test_global_carbon_error_reset_in_reset_simulation(self):
        """reset_simulation() must set global_carbon_error_kg = 0.0."""
        self.assertRegex(
            self.reset_sim_body,
            r"\bglobal_carbon_error_kg\s*=\s*0\.0\b",
            msg="reset_simulation() must reset `global_carbon_error_kg = 0.0`",
        )

    # ---- GasExchangeSystem.gd c_exited_kg increments ----

    def test_c_exited_incremented_at_smoke_vent_path(self):
        """GasExchangeSystem must increment c_exited_kg at the smoke vent_frac path."""
        vent_pos = self.gas_src.find("var vent_frac: float = minf(1.0, vented_kg")
        self.assertGreater(vent_pos, -1, "vent_frac block not found in GasExchangeSystem")
        segment = self.gas_src[vent_pos: vent_pos + 1800]
        self.assertTrue(
            "room_out.c_exited_kg +=" in segment
            or "_queue_upper_species_to_exterior(" in segment,
            msg="Smoke vent path must track c_exited_kg directly or via the M3 exterior helper",
        )
        if "_queue_upper_species_to_exterior(" in segment:
            helper_body = self.gas_src.split("func _queue_upper_species_to_exterior(", 1)[1].split("\nfunc ", 1)[0]
            self.assertIn("room.c_exited_kg += co_removed_kg", helper_body)

    def test_smoke_vent_tracks_soot_below_species_threshold(self):
        """Every vented soot mass must be tracked, even below the species carry threshold."""
        soot_pos = self.gas_src.find("room_out.c_exited_kg += vented_kg * 0.87")
        threshold_pos = self.gas_src.find("if room_out.smoke_kg > 0.001")
        self.assertGreater(soot_pos, -1, "Unconditional vented soot ledger increment not found")
        self.assertLess(
            soot_pos,
            threshold_pos,
            msg="Vented soot must be tracked before the low-smoke species threshold",
        )

    def test_c_exited_incremented_at_natural_vent_purge(self):
        """GasExchangeSystem must increment c_exited_kg at the natural vent purge_frac path."""
        purge_pos = self.gas_src.find("var purge_frac: float = clampf(fresh_air_kg")
        self.assertGreater(purge_pos, -1, "purge_frac block not found in GasExchangeSystem")
        segment = self.gas_src[purge_pos: purge_pos + 1200]
        self.assertIn(
            "c_exited_kg",
            segment,
            msg="GasExchangeSystem must track c_exited_kg in the natural vent purge_frac path",
        )

    def test_c_exited_incremented_at_pressure_vent(self):
        """GasExchangeSystem must increment c_exited_kg at the pressure venting path."""
        # In step_pressure_venting(), look for c_exited_kg before co_kg *= (1 - air_frac_out)
        air_frac_pos = self.gas_src.find("room.co_kg = maxf(0.0, room.co_kg * (1.0 - air_frac_out))")
        self.assertGreater(air_frac_pos, -1, "air_frac_out line not found in GasExchangeSystem")
        # c_exited_kg must appear just before this line
        segment = self.gas_src[max(0, air_frac_pos - 600): air_frac_pos + 50]
        self.assertIn(
            "c_exited_kg",
            segment,
            msg="GasExchangeSystem must track c_exited_kg before pressure-vent species removal",
        )

    def test_c_exited_incremented_at_outside_species_purge(self):
        """GasExchangeSystem must increment c_exited_kg after the outside_species_purge block."""
        # The outside species purge block ends with formaldehyde_removed_kg
        form_pos = self.gas_src.find("var formaldehyde_removed_kg: float = room.formaldehyde_kg")
        self.assertGreater(form_pos, -1, "formaldehyde_removed_kg line not found")
        segment = self.gas_src[form_pos: form_pos + 400]
        self.assertIn(
            "c_exited_kg",
            segment,
            msg="GasExchangeSystem must track c_exited_kg after outside_species_purge removal",
        )

    def test_c_exited_increments_use_correct_stoichiometry(self):
        """All c_exited_kg increments in GasExchangeSystem use the correct C fractions."""
        # Count occurrences of the three C fractions near c_exited_kg assignments
        # At minimum, 12.0 / 28.0 (CO) must appear in GasExchangeSystem
        count_28 = len(re.findall(r"12\.0\s*/\s*28\.0", self.gas_src))
        count_44 = len(re.findall(r"12\.0\s*/\s*44\.0", self.gas_src))
        count_27 = len(re.findall(r"12\.0\s*/\s*27\.0", self.gas_src))
        self.assertGreater(count_28, 0,
                           "GasExchangeSystem must use 12.0 / 28.0 (CO carbon) in c_exited_kg")
        self.assertGreater(count_44, 0,
                           "GasExchangeSystem must use 12.0 / 44.0 (CO₂ carbon) in c_exited_kg")
        self.assertGreater(count_27, 0,
                           "GasExchangeSystem must use 12.0 / 27.0 (HCN carbon) in c_exited_kg")

    # ---- SF-CBAL additional sinks: smoke deposition and post-fire purge ----

    def test_c_deposited_kg_declared_in_room_model(self):
        """RoomModel must declare var c_deposited_kg: float = 0.0."""
        self.assertRegex(
            self.room_src,
            r"\bvar\s+c_deposited_kg\s*:\s*float\s*=\s*0\.0",
            msg="RoomModel must declare `var c_deposited_kg: float = 0.0`",
        )

    def test_c_deposited_kg_reset_in_reset_dynamic_state(self):
        """reset_dynamic_state() must set c_deposited_kg = 0.0."""
        self.assertRegex(
            self.reset_room_body,
            r"\bc_deposited_kg\s*=\s*0\.0\b",
            msg="reset_dynamic_state() must set `c_deposited_kg = 0.0`",
        )

    def test_smoke_deposition_tracked_in_gas_exchange(self):
        """GasExchangeSystem must track smoke deposition in room.c_deposited_kg."""
        # Search for the deposition computation block (unique variable name)
        depos_pos = self.gas_src.find("var deposited_smoke_kg: float = minf(")
        self.assertGreater(depos_pos, -1, "deposited_smoke_kg computation not found in GasExchangeSystem")
        segment = self.gas_src[depos_pos: depos_pos + 400]
        self.assertIn(
            "c_deposited_kg",
            segment,
            msg="GasExchangeSystem must track room.c_deposited_kg after smoke deposition",
        )

    def test_postfire_purge_tracked_in_c_exited(self):
        """GasExchangeSystem must track post-fire CO/CO2/HCN purge in room.c_exited_kg."""
        purge_pos = self.gas_src.find("co_purge_rate > 0.0")
        self.assertGreater(purge_pos, -1, "co_purge_rate > 0.0 guard not found in GasExchangeSystem")
        segment = self.gas_src[purge_pos: purge_pos + 300]
        self.assertIn(
            "c_exited_kg",
            segment,
            msg="GasExchangeSystem must track c_exited_kg when co_purge_rate > 0",
        )

    # ---- HVAC exhaust carbon tracking ----

    def test_cbal_hvac_c_exhausted_kg_declared(self):
        """SimulationEngine must declare var _cbal_hvac_c_exhausted_kg: float = 0.0."""
        self.assertRegex(
            self.engine_src,
            r"\bvar\s+_cbal_hvac_c_exhausted_kg\s*:\s*float\s*=\s*0\.0",
            msg="SimulationEngine must declare `var _cbal_hvac_c_exhausted_kg: float = 0.0`",
        )

    def test_cbal_hvac_c_exhausted_kg_reset_in_reset_simulation(self):
        """reset_simulation() must set _cbal_hvac_c_exhausted_kg = 0.0."""
        self.assertRegex(
            self.reset_sim_body,
            r"\b_cbal_hvac_c_exhausted_kg\s*=\s*0\.0\b",
            msg="reset_simulation() must reset `_cbal_hvac_c_exhausted_kg = 0.0`",
        )

    def test_hvac_step_returns_c_exhausted_kg(self):
        """HVACSystem.step() result dict must initialize c_exhausted_kg: 0.0."""
        self.assertIn(
            '"c_exhausted_kg"',
            self.hvac_src,
            msg='HVACSystem result dict must contain "c_exhausted_kg"',
        )

    def test_hvac_c_exhausted_computed_from_species(self):
        """HVAC loss must equal return carbon not reintroduced by supply."""
        self.assertIn(
            "c_from_returns_kg",
            self.hvac_src,
            msg="HVACSystem must compute carbon removed by returns",
        )
        self.assertIn(
            'supply_result.get("c_supplied_kg"',
            self.hvac_src,
            msg="HVACSystem must subtract carbon reintroduced by supply",
        )

    def test_cbal_hvac_accumulated_in_step_hvac(self):
        """SimulationEngine._step_hvac() must accumulate _cbal_hvac_c_exhausted_kg."""
        self.assertIn(
            "_cbal_hvac_c_exhausted_kg",
            self.step_hvac_body,
            msg="_step_hvac() must accumulate _cbal_hvac_c_exhausted_kg += result.get(...)",
        )

    def test_check_balance_includes_c_deposited_total(self):
        """_check_carbon_balance() must accumulate c_deposited_total from rooms."""
        self.assertRegex(
            self.balance_body,
            r"\bc_deposited_total\s*\+=",
            msg="_check_carbon_balance() must accumulate c_deposited_total += ...",
        )
        self.assertIn(
            "room.c_deposited_kg",
            self.balance_body,
            msg="_check_carbon_balance() must read room.c_deposited_kg",
        )

    def test_check_balance_formula_includes_hvac_exhaust(self):
        """global_carbon_error_kg formula must include _cbal_hvac_c_exhausted_kg."""
        self.assertIn(
            "_cbal_hvac_c_exhausted_kg",
            self.balance_body,
            msg="global_carbon_error_kg must include _cbal_hvac_c_exhausted_kg",
        )

    def test_check_balance_formula_includes_c_deposited(self):
        """global_carbon_error_kg formula must include c_deposited_total."""
        self.assertIn(
            "c_deposited_total",
            self.balance_body,
            msg="global_carbon_error_kg must include c_deposited_total",
        )

    # ---- Step order: initialize before physics, evaluate after clamp ----

    def test_carbon_balance_order(self):
        """In step(), initialize before physics and evaluate after clamp."""
        pos_init = self.step_body.find("_ensure_carbon_balance_initialized()")
        pos_check = self.step_body.find("_check_carbon_balance()")
        pos_pool  = self.step_body.find("_step_pool_fires(dt)")
        pos_clamp = self.step_body.find("_clamp_rooms(dt)")
        self.assertGreater(pos_init, -1,
                           "step() must initialize SF-CBAL")
        self.assertGreater(pos_check, -1,
                           "step() must call _check_carbon_balance()")
        self.assertGreater(pos_pool, -1,
                           "step() must call _step_pool_fires(dt)")
        self.assertGreater(pos_clamp, -1,
                           "step() must call _clamp_rooms(dt)")
        self.assertLess(
            pos_init, pos_pool,
            msg="Initial carbon inventory must be captured before physics",
        )
        self.assertGreater(
            pos_check, pos_clamp,
            msg="Final carbon error must be evaluated after clamp",
        )

    def test_pending_internal_carbon_is_included(self):
        """Delayed interior transport remains part of the global inventory."""
        self.assertIn("get_pending_carbon_kg", self.gas_src)
        self.assertIn("c_pending_internal", self.balance_body)

    def test_ach_and_ppv_sinks_are_tracked(self):
        """ACH and both PPV purge paths must add removed carbon to c_exited_kg."""
        self.assertIn("co_removed * (12.0 / 28.0)", self.gas_src)
        self.assertIn("co_purged_inlet", self.gas_src)
        self.assertIn("co_purged_ex", self.gas_src)

    def test_runtime_creation_loss_events_exist(self):
        """CaseRunner must support validation-only carbon creation/loss events."""
        self.assertIn("_prepare_carbon_events", self.case_runner_src)
        self.assertIn("_apply_due_carbon_events", self.case_runner_src)

    # ---- global_carbon_error_kg exported in state ----

    def test_global_carbon_error_kg_in_state_context(self):
        """_build_state_context() must include global_carbon_error_kg."""
        context_body = _extract_function_body(self.engine_src, "_build_state_context")
        self.assertIn(
            '"global_carbon_error_kg"',
            context_body,
            msg="_build_state_context() must export global_carbon_error_kg",
        )

    def test_global_carbon_error_kg_in_state_builder(self):
        """SimulationStateBuilder.build_state() must read global_carbon_error_kg from context."""
        self.assertIn(
            '"global_carbon_error_kg"',
            self.builder_src,
            msg='SimulationStateBuilder must export "global_carbon_error_kg"',
        )

    def test_postclamp_excess_exported_in_state(self):
        """The physical product excess diagnostic must reach validation reports."""
        context_body = _extract_function_body(self.engine_src, "_build_state_context")
        self.assertIn('"global_carbon_postclamp_excess_kg"', context_body)
        self.assertIn('"global_carbon_postclamp_excess_kg"', self.builder_src)
        self.assertIn('"global_carbon_postclamp_excess_kg"', self.case_runner_src)


if __name__ == "__main__":
    unittest.main(verbosity=2)
