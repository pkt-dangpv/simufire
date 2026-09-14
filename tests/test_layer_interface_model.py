"""Guardrails for canonical visible/thermal/flow layer interfaces."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
LAYER = (ROOT / "sim" / "core" / "LayerInterfaceModel.gd").read_text(encoding="utf-8")
SMOKE = (ROOT / "sim" / "smoke" / "SmokeModel.gd").read_text(encoding="utf-8")
GAS = (ROOT / "sim" / "core" / "GasExchangeSystem.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim" / "core" / "ThermalSystem.gd").read_text(encoding="utf-8")
OXYGEN = (ROOT / "sim" / "core" / "OxygenExchangeSystem.gd").read_text(encoding="utf-8")
HVAC = (ROOT / "sim" / "core" / "HVACSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim" / "core" / "SimulationLogWriter.gd").read_text(encoding="utf-8")
CASE_RUNNER = (ROOT / "sim" / "validation" / "CaseRunner.gd").read_text(encoding="utf-8")
RUN_ALL = (ROOT / "sim" / "validation" / "run_all_cases.ps1").read_text(encoding="utf-8")
CASE = (ROOT / "sim" / "validation" / "cases" / "layer_interface_single_room_window.json").read_text(
    encoding="utf-8"
)
BASELINE = (
    ROOT / "sim" / "validation" / "baselines" / "layer_interface_single_room_window.json"
).read_text(encoding="utf-8")
FED_SMOKE_ONLY_CASE = (
    ROOT / "sim" / "validation" / "cases" / "fed_thermal_layer_smoke_only.json"
).read_text(encoding="utf-8")
FED_SMOKE_ONLY_BASELINE = (
    ROOT / "sim" / "validation" / "baselines" / "fed_thermal_layer_smoke_only.json"
).read_text(encoding="utf-8")


def function_body(source: str, name: str) -> str:
    marker_static = f"static func {name}"
    marker_func = f"func {name}"

    if marker_static in source:
        start = source.index(marker_static)
    elif marker_func in source:
        start = source.index(marker_func)
    else:
        raise AssertionError(f"No se encontró la función {name}")

    tail = source[start:]

    next_static = tail.find("\nstatic func ", 1)
    next_func = tail.find("\nfunc ", 1)

    candidates = [i for i in (next_static, next_func) if i != -1]
    end = min(candidates) if candidates else len(tail)

    return tail[:end]


def csv_base_header(source: str) -> str:
    body = function_body(source, "_build_csv_header")
    match = re.search(r'var\s+header:\s*String\s*=\s*"([^"]+)"', body)
    if match is None:
        raise AssertionError("No se encontro el encabezado CSV base")
    if "return header" not in body:
        raise AssertionError("_build_csv_header no devuelve el encabezado construido")
    return match.group(1)


class TestLayerInterfaceModelContract(unittest.TestCase):
    def test_central_model_declares_all_semantic_heights(self):
        self.assertIn("class_name LayerInterfaceModel", LAYER)
        for fn in (
            "get_visible_smoke_layer_height_m",
            "get_thermal_layer_height_m",
            "get_flow_interface_height_m",
            "get_breathing_zone_exposure_factor",
        ):
            self.assertRegex(LAYER, rf"static func {fn}\(")
        for term in ("h_visible_smoke_layer_m", "h_thermal_layer_m", "h_flow_interface_m"):
            self.assertIn(term, LAYER)

    def test_flow_interface_uses_thermal_layer_not_smoke_spill_bridge(self):
        body = function_body(LAYER, "get_flow_interface_height_m")

        self.assertIn("get_thermal_layer_height_m(room, ambient_c)", body)
        self.assertNotIn("get_effective_smoke_spill_layer_height_m", body)
        self.assertNotIn("get_visible_smoke_layer_height_m", body)

    def test_exterior_opening_helper_uses_flow_interface(self):
        body = function_body(LAYER, "get_exterior_opening_hot_outflow_height_m")
        self.assertIn("get_flow_interface_height_m(room, smoke_model, ambient_c)", body)
        self.assertIn("lintel_m - maxf(sill_m, flow_interface_m)", body)


class TestFlowCallersUseCanonicalInterface(unittest.TestCase):
    def test_smoke_spill_and_transfer_use_flow_interface(self):
        self.assertIn("func get_spill_layer_height_m(room: RoomModel) -> float:", SMOKE)
        self.assertIn("LayerInterfaceModel.get_smoke_spill_interface_height_m(room, self, 20.0)", SMOKE)

        # Los transfers físicos entre salas sí deben seguir usando flow_interface_m.
        self.assertIn("LayerInterfaceModel.get_flow_interface_height_m(room_a, self, 20.0)", SMOKE)
        self.assertIn("LayerInterfaceModel.get_flow_interface_height_m(target, self, 20.0)", SMOKE)

    def test_gas_exchange_exterior_natural_vent_does_not_have_local_neutral_plane(self):
        self.assertNotIn("var _neutral_f", GAS)
        self.assertNotIn("var _alpha_b", GAS)
        self.assertIn("LayerInterfaceModel.get_exterior_opening_hot_outflow_height_m", GAS)

    def test_gas_exchange_segment_routing_uses_flow_interface(self):
        body = function_body(GAS, "_height_is_in_upper_zone")
        self.assertIn("LayerInterfaceModel.get_flow_interface_height_m(room, null, 20.0)", body)
        self.assertNotIn("room.thermal_layer_m", body)

    def test_thermal_opening_flow_state_exports_flow_interface(self):
        body = function_body(THERMAL, "build_interior_opening_flow_state")
        self.assertIn("var flow_interface_m: float = flow_interface_height_m(hot_room)", body)
        self.assertIn("spill_trigger_layer_m - flow_interface_m", body)
        self.assertIn("var h_thermal_np: float = flow_interface_m", body)
        self.assertIn('state["flow_interface_m"] = flow_interface_m', body)

    def test_engine_hooks_route_flow_subsystems_to_flow_interface(self):
        for hook_name in (
            "_build_gas_exchange_hooks",
            "_build_oxygen_exchange_hooks",
            "_build_hvac_hooks",
        ):
            body = function_body(ENGINE, hook_name)
            self.assertIn('Callable(thermal_system, "flow_interface_height_m")', body)
            self.assertNotIn('Callable(thermal_system, "effective_hot_layer_height_m")', body)

    def test_oxygen_and_hvac_fallbacks_use_canonical_flow_interface(self):
        self.assertIn("LayerInterfaceModel.get_flow_interface_height_m(room, null, building.outside_temp_c)", OXYGEN)
        self.assertIn("LayerInterfaceModel.get_flow_interface_height_m(indoor, null, building.outside_temp_c)", OXYGEN)
        self.assertIn("return LayerInterfaceModel.get_flow_interface_height_m(room, null, 20.0)", HVAC)

    def test_fed_exposure_uses_thermal_interfaces_not_visible_smoke_layer(self):
        step_body = function_body(THERMAL, "step_fed")
        height_body = function_body(THERMAL, "compute_fed_delta_for_height")
        helper_body = function_body(THERMAL, "_fed_breathing_zone_thermal_exposure_factor")

        self.assertNotIn("room.h_layer_m", step_body)
        self.assertNotIn("room.h_layer_m", height_body)
        self.assertIn("_fed_breathing_zone_thermal_exposure_factor", step_body)
        self.assertIn("_fed_breathing_zone_thermal_exposure_factor", height_body)
        self.assertIn("LayerInterfaceModel.get_breathing_zone_exposure_factor", helper_body)
        self.assertIn("room.thermal_layer_m", helper_body)
        self.assertIn("room.layer_150c_m", helper_body)

    def test_visible_smoke_cannot_trigger_fed_heat_when_thermal_layer_is_high(self):
        helper_body = function_body(THERMAL, "_fed_breathing_zone_thermal_exposure_factor")

        self.assertNotIn("h_layer_m", helper_body)
        self.assertIn("return 0.0", helper_body)
        self.assertIn("_warn_invalid_fed_layer_once(room, \"thermal_layer_m\"", helper_body)
        self.assertIn("_warn_invalid_fed_layer_once(room, \"layer_150c_m\"", helper_body)


class TestLayerInterfaceExportsAndGuardrails(unittest.TestCase):
    def test_state_exports_visible_thermal_flow_and_150c_layers(self):
        for field in (
            '"visible_smoke_layer_m": visible_smoke_layer_m',
            '"thermal_layer_m": thermal_layer_m',
            '"flow_interface_m": flow_interface_m',
            '"layer_150c_m": layer_150c_m',
        ):
            self.assertIn(field, STATE)

    def test_visibility_is_computed_from_visible_layer(self):
        self.assertIn("estimate_visibility_for_layer_m(room, visible_smoke_layer_m)", STATE)
        state_layer_section = STATE.split("var visibility_m", 1)[1].split("var kawagoe_factor", 1)[0]
        self.assertNotIn("estimate_visibility_for_layer_m(room, smoke_layer_m)", state_layer_section)

    def test_csv_exports_three_canonical_layers(self):
        header = csv_base_header(LOG)
        for column in ("visible_smoke_layer_m", "thermal_layer_m", "flow_interface_m", "layer_150c_m"):
            self.assertIn(column, header)
        self.assertIn('rs.get("visible_smoke_layer_m"', LOG)
        self.assertIn('rs.get("thermal_layer_m"', LOG)
        self.assertIn('rs.get("flow_interface_m"', LOG)

    def test_case_runner_captures_final_and_min_layer_metrics(self):
        for metric in (
            "visible_smoke_layer_m",
            "thermal_layer_m",
            "flow_interface_m",
            "min_visible_smoke_layer_m",
            "min_thermal_layer_m",
            "min_flow_interface_m",
        ):
            self.assertIn(metric, CASE_RUNNER)

    def test_engine_warns_on_persistent_flow_thermal_divergence(self):
        self.assertIn("func _check_layer_interface_guardrails(dt: float) -> void:", ENGINE)
        body = function_body(ENGINE, "_check_layer_interface_guardrails")
        self.assertIn("room.hrr_kw <= 100.0", body)
        self.assertIn("divergence_m <= 1.0", body)
        self.assertIn("accumulated_s <= 30.0", body)
        self.assertIn('log_writer.append_event(sim_time_s, "layer_interface_divergence"', body)

    def test_minimal_validation_case_exists_and_is_in_suite(self):
        self.assertIn('"layer_interface_single_room_window"', RUN_ALL)
        self.assertIn('"template": "simple_house"', CASE)
        self.assertIn('"type": "window"', CASE)
        self.assertIn('"two_zone_solver_enabled": true', CASE)
        self.assertIn('"two_zone_opening_flow_enabled": true', CASE)
        self.assertIn('"fire_alpha_kw_s2": 0.047', CASE)
        self.assertIn('"csv_log_file_path"', CASE)

    def test_minimal_validation_baseline_checks_layer_descent_contract(self):
        for metric in (
            "room_0_min_visible_smoke_layer_m",
            "room_0_min_thermal_layer_m",
            "room_0_min_flow_interface_m",
            "room_0_final_flow_interface_m",
            "room_0_final_visibility_m",
        ):
            self.assertIn(metric, BASELINE)

    def test_fed_smoke_only_validation_case_keeps_visible_and_thermal_layers_separate(self):
        self.assertIn('"fed_thermal_layer_smoke_only"', RUN_ALL)
        self.assertIn('"ignite_on_start": false', FED_SMOKE_ONLY_CASE)
        self.assertIn('"species": "smoke_kg"', FED_SMOKE_ONLY_CASE)
        self.assertIn('"two_zone_solver_enabled": true', FED_SMOKE_ONLY_CASE)
        self.assertIn('"two_zone_opening_flow_enabled": true', FED_SMOKE_ONLY_CASE)

        self.assertIn("room_0_min_visible_smoke_layer_m", FED_SMOKE_ONLY_BASELINE)
        self.assertIn("room_0_min_thermal_layer_m", FED_SMOKE_ONLY_BASELINE)
        self.assertIn("room_0_min_l150_m", FED_SMOKE_ONLY_BASELINE)
        self.assertIn("room_0_final_fed_heat", FED_SMOKE_ONLY_BASELINE)
        self.assertIn("room_0_final_fed", FED_SMOKE_ONLY_BASELINE)


if __name__ == "__main__":
    unittest.main()
