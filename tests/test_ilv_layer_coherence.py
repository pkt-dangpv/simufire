import sys
import unittest
from pathlib import Path


_SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts" / "simulation"
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import check_ilv_layer_coherence  # noqa: E402


class TestILVLayerCoherence(unittest.TestCase):

    def test_passes_when_upper_o2_and_regime_are_consistent(self):
        rows = [{
            "time_s": "120.0",
            "room_id": "0",
            "hrr_kw": "350.0",
            "combustion_regime": "VENTILATION_CONTROLLED_BURNING",
            "o2_upper": "0.031",
            "o2_lower": "0.190",
            "o2_hrr_factor": "0.31",
            "visibility_m": "0.22",
        }]

        findings = check_ilv_layer_coherence.find_ilv_layer_coherence_issues(rows)

        self.assertEqual(findings, [])

    def test_flags_fuel_controlled_hrr_with_critical_upper_o2(self):
        rows = [{
            "time_s": "940.2",
            "room_id": "0",
            "hrr_kw": "3107.92",
            "combustion_regime": "FUEL_CONTROLLED",
            "o2_upper": "0.00334",
            "o2_lower": "0.20286",
            "o2_hrr_factor": "0.9294",
            "visibility_m": "0.08",
        }]

        findings = check_ilv_layer_coherence.find_ilv_layer_coherence_issues(rows)

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].kind, "upper-O2-critical-but-regime-fuel-controlled")

    def test_flags_high_hrr_throttle_when_upper_o2_is_critical(self):
        rows = [{
            "time_s": "360.0",
            "room_id": "0",
            "hrr_kw": "1295.31",
            "combustion_regime": "VENTILATION_STRESSED",
            "o2_upper": "0.00015",
            "o2_lower": "0.18603",
            "o2_hrr_factor": "0.90",
            "visibility_m": "0.07",
        }]

        findings = check_ilv_layer_coherence.find_ilv_layer_coherence_issues(rows)

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].kind, "upper-O2-critical-but-HRR-throttle-high")


if __name__ == "__main__":
    unittest.main()
