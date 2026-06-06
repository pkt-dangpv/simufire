import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def extract_function(text: str, func_name: str) -> str:
    pattern = rf"(?ms)^static func {re.escape(func_name)}\b.*?(?=^static func |\Z)"
    match = re.search(pattern, text)
    if not match:
        pattern = rf"(?ms)^func {re.escape(func_name)}\b.*?(?=^func |\Z)"
        match = re.search(pattern, text)
    if not match:
        raise AssertionError(f"No se encontró la función {func_name}")
    return match.group(0)


class LayerInterfaceSemanticSplitTests(unittest.TestCase):
    def test_flow_interface_does_not_use_smoke_spill_bridge(self):
        text = read("sim/core/LayerInterfaceModel.gd")
        body = extract_function(text, "get_flow_interface_height_m")

        self.assertNotIn(
            "get_effective_smoke_spill_layer_height_m",
            body,
            "flow_interface_m no debe depender del bridge óptico de SmokeModel",
        )
        self.assertIn(
            "get_thermal_layer_height_m",
            body,
            "flow_interface_m debe derivar de la capa térmica/zonal",
        )

    def test_smoke_spill_has_separate_helper(self):
        text = read("sim/core/LayerInterfaceModel.gd")

        self.assertIn(
            "get_smoke_spill_interface_height_m",
            text,
            "Debe existir helper separado para derrame de humo visible",
        )

        smoke_body = extract_function(text, "get_smoke_spill_interface_height_m")
        self.assertIn(
            "get_effective_smoke_spill_layer_height_m",
            smoke_body,
            "El bridge legacy debe vivir solo en smoke_spill_interface_m",
        )

    def test_smoke_model_spill_uses_smoke_spill_interface(self):
        text = read("sim/smoke/SmokeModel.gd")
        body = extract_function(text, "get_spill_layer_height_m")

        self.assertIn(
            "get_smoke_spill_interface_height_m",
            body,
            "SmokeModel.get_spill_layer_height_m debe usar smoke_spill_interface_m",
        )
        self.assertNotIn(
            "get_flow_interface_height_m",
            body,
            "SmokeModel.get_spill_layer_height_m no debe usar flow_interface_m",
        )

    def test_svv_thermal_does_not_use_h_layer_m(self):
        text = read("sim/core/ThermalSystem.gd")
        body = extract_function(text, "_compute_svv_pct_from_room")

        self.assertNotIn(
            "room.h_layer_m",
            body,
            "SVV térmico no debe usar room.h_layer_m; debe usar capa térmica/layer_150c",
        )
        self.assertIn(
            "get_thermal_layer_height_m",
            body,
            "SVV térmico debe usar LayerInterfaceModel.get_thermal_layer_height_m",
        )


if __name__ == "__main__":
    unittest.main()