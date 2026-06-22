import sys
import unittest
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts" / "simulation"
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import audit_ilv_layer_coherence_suite as suite  # noqa: E402


# Minimal CSV rows shared across tests
_ROW_CLEAN = {
    "time_s": "120.0", "room_id": "0", "hrr_kw": "350.0",
    "combustion_regime": "VENTILATION_CONTROLLED_BURNING",
    "o2_upper": "0.031", "o2_lower": "0.190", "o2_hrr_factor": "0.31",
    "visibility_m": "0.22",
}
_ROW_ZOMBIE = {
    "time_s": "275.0", "room_id": "2", "hrr_kw": "1211.0",
    "combustion_regime": "VENTILATION_CONTROLLED_BURNING",
    "o2_upper": "0.0008", "o2_lower": "0.1974", "o2_hrr_factor": "0.893",
    "visibility_m": "0.1",
}


class TestFileResult(unittest.TestCase):

    def _make_result(self, findings):
        from check_ilv_layer_coherence import Finding
        return suite.FileResult(
            path=Path("fake.csv"),
            total_rows=100,
            rooms={"0"},
            findings=findings,
        )

    def test_worst_finding_is_highest_hrr(self):
        from check_ilv_layer_coherence import Finding
        f_low  = Finding(time_s=10, room_id="0", kind="x", hrr_kw=200, regime="", o2_upper=0.01, o2_lower=0.19, o2_hrr_factor=0.8, visibility_m=1.0)
        f_high = Finding(time_s=20, room_id="0", kind="x", hrr_kw=999, regime="", o2_upper=0.01, o2_lower=0.19, o2_hrr_factor=0.8, visibility_m=1.0)
        result = self._make_result([f_low, f_high])
        self.assertEqual(result.worst_finding.hrr_kw, 999)

    def test_worst_finding_none_when_no_findings(self):
        result = self._make_result([])
        self.assertIsNone(result.worst_finding)

    def test_findings_by_kind_counts_correctly(self):
        from check_ilv_layer_coherence import Finding
        f1 = Finding(time_s=1, room_id="0", kind="A", hrr_kw=100, regime="", o2_upper=0.01, o2_lower=0.19, o2_hrr_factor=0.9, visibility_m=1.0)
        f2 = Finding(time_s=2, room_id="0", kind="A", hrr_kw=200, regime="", o2_upper=0.01, o2_lower=0.19, o2_hrr_factor=0.9, visibility_m=1.0)
        f3 = Finding(time_s=3, room_id="0", kind="B", hrr_kw=300, regime="", o2_upper=0.01, o2_lower=0.19, o2_hrr_factor=0.9, visibility_m=1.0)
        result = self._make_result([f1, f2, f3])
        self.assertEqual(result.findings_by_kind(), {"A": 2, "B": 1})


class TestAuditCsv(unittest.TestCase):

    def _write_csv(self, tmp_path: Path, rows: list[dict]) -> Path:
        import csv
        path = tmp_path / "test.csv"
        with open(path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
        return path

    def test_clean_csv_returns_no_findings(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            path = self._write_csv(Path(td), [_ROW_CLEAN])
            result = suite.audit_csv(path)
        self.assertEqual(result.finding_count, 0)
        self.assertIsNone(result.error)
        self.assertEqual(result.total_rows, 1)

    def test_zombie_csv_returns_findings(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            path = self._write_csv(Path(td), [_ROW_ZOMBIE])
            result = suite.audit_csv(path)
        self.assertGreater(result.finding_count, 0)
        self.assertIsNone(result.error)

    def test_missing_file_returns_error(self):
        result = suite.audit_csv(Path("nonexistent_file_xyz.csv"))
        self.assertIsNotNone(result.error)
        self.assertEqual(result.total_rows, 0)

    def test_kind_filter_excludes_other_kinds(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            path = self._write_csv(Path(td), [_ROW_ZOMBIE])
            result_filtered = suite.audit_csv(path, kind_filter="fuel-controlled")
        self.assertEqual(result_filtered.finding_count, 0)


class TestFindCsvs(unittest.TestCase):

    def test_excludes_tmp_by_default(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            p = Path(td)
            (p / "case_a.csv").write_text("x")
            (p / "tmp_exp.csv").write_text("x")
            found = suite.find_csvs(p)
        self.assertEqual([f.name for f in found], ["case_a.csv"])

    def test_includes_tmp_when_requested(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            p = Path(td)
            (p / "case_a.csv").write_text("x")
            (p / "tmp_exp.csv").write_text("x")
            found = suite.find_csvs(p, exclude_tmp=False)
        self.assertEqual(sorted(f.name for f in found), ["case_a.csv", "tmp_exp.csv"])


class TestMain(unittest.TestCase):

    def _write_csv(self, path: Path, rows: list[dict]) -> None:
        import csv
        with open(path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)

    def test_returns_0_for_clean_directory(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "clean.csv", [_ROW_CLEAN])
            rc = suite.main(["--reports-dir", td])
        self.assertEqual(rc, 0)

    def test_returns_1_for_findings(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "zombie.csv", [_ROW_ZOMBIE])
            rc = suite.main(["--reports-dir", td])
        self.assertEqual(rc, 1)

    def test_allow_findings_overrides_exit_code(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "zombie.csv", [_ROW_ZOMBIE])
            rc = suite.main(["--reports-dir", td, "--allow-findings"])
        self.assertEqual(rc, 0)

    def test_returns_2_for_missing_directory(self):
        rc = suite.main(["--reports-dir", "/nonexistent/path/xyz"])
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
