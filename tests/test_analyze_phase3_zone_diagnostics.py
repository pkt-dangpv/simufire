"""Tests for scripts/simulation/analyze_phase3_zone_diagnostics.py."""

import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "simulation"))

from analyze_phase3_zone_diagnostics import (
    F0_COLS,
    F0_SENTINEL_COLS,
    RoomSummary,
    _check_f0_columns,
    _classify,
    analyze_csv,
    main,
    summarize_room,
)


def _make_f0_df(n_rows=5, n_rooms=1, include_f0=True):
    """Return a minimal DataFrame that mimics a Phase 3+ F0 CSV."""
    rows = []
    for room in range(n_rooms):
        vol = 48.0 if room == 0 else 30.0
        initial_lower = vol * 1.2
        for i in range(n_rows):
            t = float(i * 60)
            upper_gas = 0.0 if i == 0 else 1.0 + i * 0.5
            lower_gas = initial_lower - (0.0 if i == 0 else i * 0.3)
            boundary = 0.0 if i == 0 else i * 2.5 * (1 if room == 0 else -0.1)
            upper_vol_eos = 0.0 if i == 0 else (i * 0.5)
            row = {
                "time_s": t,
                "room_id": room,
                "volume_m3": vol,
                "upper_gas_kg": upper_gas,
                "lower_gas_kg": lower_gas,
                "upper_energy_kj": upper_gas * 50.0,
                "lower_energy_kj": lower_gas * 45.0,
                "upper_volume_m3_eos": upper_vol_eos,
                "lower_volume_m3_eos": vol - upper_vol_eos,
                "volume_closure_error_m3": 1e-7 if i > 0 else 0.0,
                "two_zone_boundary_mass_kg": boundary,
                "two_zone_boundary_energy_kj": boundary * 10.0,
                "two_zone_boundary_mass_kg_step": boundary * 0.1 if i > 0 else 0.0,
                "two_zone_boundary_energy_kj_step": boundary * 1.0 if i > 0 else 0.0,
                "opening_upper_in_kg_step": 0.1 * i if room == 0 else 0.0,
                "opening_upper_out_kg_step": 0.05 * i if room == 0 else 0.0,
                "opening_lower_in_kg_step": 0.2 * i if room == 0 else 0.0,
                "opening_lower_out_kg_step": 0.15 * i if room == 0 else 0.0,
                "plume_entrained_kg_step": 0.08 * i,
                "oxygen_exchange_mass_delta_kg_step": -0.01 * i,
                "oxygen_exchange_energy_delta_kj_step": -0.1 * i,
                "combustion_mass_delta_kg_step": -0.005 * i,
                "combustion_energy_delta_kj_step": 5.0 * i,
                "thermal_mass_delta_kg_step": 0.0,
                "thermal_energy_delta_kj_step": -0.2 * i,
                "suppression_mass_delta_kg_step": 0.0,
                "suppression_energy_delta_kj_step": 0.0,
                "gas_exchange_mass_delta_kg_step": 0.0,
                "gas_exchange_energy_delta_kj_step": 0.0,
                "hvac_mass_delta_kg_step": 0.0,
                "hvac_energy_delta_kj_step": 0.0,
                "other_mass_delta_kg_step": 0.0,
                "other_energy_delta_kj_step": 0.0,
                "reconcile_mass_delta_kg_step": 0.0,
                "reconcile_energy_delta_kj_step": 0.0,
                "projection_clamp_mass_delta_kg_step": boundary * 0.05 if i > 0 else 0.0,
                "projection_clamp_energy_delta_kj_step": 0.0,
                "attribution_mass_residual_kg_step": 0.0,
                "attribution_energy_residual_kj_step": 0.0,
            }
            rows.append(row)

    df = pd.DataFrame(rows)
    if not include_f0:
        df = df.drop(columns=list(F0_SENTINEL_COLS), errors="ignore")
    return df


class TestCheckF0Columns(unittest.TestCase):
    def test_passes_with_all_sentinel_cols(self):
        df = _make_f0_df()
        _check_f0_columns(df, "test.csv")  # must not raise

    def test_raises_on_missing_sentinel_cols(self):
        df = _make_f0_df(include_f0=False)
        with self.assertRaises(ValueError) as ctx:
            _check_f0_columns(df, "legacy.csv")
        self.assertIn("not a Phase 3+ F0 diagnostic CSV", str(ctx.exception))
        self.assertIn("legacy.csv", str(ctx.exception))

    def test_error_lists_missing_column_names(self):
        df = _make_f0_df()
        df = df.drop(columns=["upper_gas_kg"])
        with self.assertRaises(ValueError) as ctx:
            _check_f0_columns(df, "partial.csv")
        self.assertIn("upper_gas_kg", str(ctx.exception))


class TestSummarizeRoom(unittest.TestCase):
    def setUp(self):
        self.df = _make_f0_df(n_rows=5, n_rooms=1)
        self.df_room = self.df[self.df["room_id"] == 0].reset_index(drop=True)

    def test_returns_room_summary(self):
        s = summarize_room("test.csv", self.df_room)
        self.assertIsInstance(s, RoomSummary)
        self.assertEqual(s.room_id, 0)
        self.assertEqual(s.row_count, 5)

    def test_t_start_and_end(self):
        s = summarize_room("test.csv", self.df_room)
        self.assertAlmostEqual(s.t_start_s, 0.0)
        self.assertAlmostEqual(s.t_end_s, 240.0, places=1)

    def test_upper_vf_computed_from_eos_volume(self):
        s = summarize_room("test.csv", self.df_room)
        # At last row (i=4): upper_volume_m3_eos = 4*0.5 = 2.0, volume_m3 = 48
        expected_final_vf = 2.0 / 48.0
        self.assertAlmostEqual(s.upper_vf_final, expected_final_vf, places=5)

    def test_upper_vf_zero_at_inactive_rows_excluded(self):
        s = summarize_room("test.csv", self.df_room)
        # min should come from first active row (i=1), not i=0 (zero upper_gas)
        self.assertGreater(s.upper_vf_min, 0.0)

    def test_boundary_mass_final_matches_last_row(self):
        s = summarize_room("test.csv", self.df_room)
        # room 0, last row (i=4): boundary = 4 * 2.5 = 10.0
        self.assertAlmostEqual(s.boundary_mass_kg_final, 10.0, places=4)

    def test_boundary_turnover_ratio(self):
        s = summarize_room("test.csv", self.df_room)
        # initial_lower = 48 * 1.2 = 57.6; |final boundary| = 10.0
        expected_ratio = 10.0 / 57.6
        self.assertAlmostEqual(s.boundary_turnover_ratio, expected_ratio, places=5)

    def test_opening_total_sum_positive(self):
        s = summarize_room("test.csv", self.df_room)
        self.assertGreater(s.opening_total_sum, 0.0)

    def test_plume_entrained_sum(self):
        s = summarize_room("test.csv", self.df_room)
        # sum of 0.08 * i for i in 0..4 = 0.08 * (0+1+2+3+4) = 0.8
        self.assertAlmostEqual(s.plume_entrained_sum, 0.8, places=5)

    def test_attribution_residual_zero(self):
        s = summarize_room("test.csv", self.df_room)
        self.assertAlmostEqual(s.attribution_residual_max_abs, 0.0, places=10)


class TestClassify(unittest.TestCase):
    def _make_summary(self, **kwargs):
        defaults = dict(
            csv_path="x.csv",
            room_id=0,
            row_count=10,
            t_start_s=0.0,
            t_end_s=600.0,
            upper_vf_min=0.05,
            upper_vf_min_t=60.0,
            upper_vf_max=0.3,
            upper_vf_max_t=600.0,
            upper_vf_final=0.2,
            upper_gas_kg_min=1.0,
            upper_gas_kg_min_t=60.0,
            upper_gas_kg_max=10.0,
            upper_gas_kg_max_t=600.0,
            upper_gas_kg_final=8.0,
            lower_gas_kg_final=40.0,
            upper_energy_kj_final=200.0,
            lower_energy_kj_final=1000.0,
            volume_closure_error_m3_max_abs=1e-7,
            volume_closure_error_m3_max_abs_t=60.0,
            boundary_mass_kg_final=0.0,
            boundary_mass_kg_peak=0.0,
            boundary_mass_kg_peak_t=0.0,
            boundary_energy_kj_final=0.0,
            boundary_mass_step_max_abs=0.0,
            boundary_mass_step_max_abs_t=0.0,
            opening_upper_in_sum=0.0,
            opening_upper_out_sum=0.0,
            opening_lower_in_sum=0.0,
            opening_lower_out_sum=0.0,
            opening_total_sum=0.0,
            plume_entrained_sum=0.0,
            plume_entrained_step_max=0.0,
            projection_clamp_mass_step_max_abs=0.0,
            projection_clamp_mass_step_max_abs_t=0.0,
            attribution_residual_max_abs=0.0,
            attribution_residual_max_abs_t=0.0,
            boundary_turnover_ratio=0.0,
        )
        defaults.update(kwargs)
        s = RoomSummary(**defaults)
        return s

    def test_no_flags_by_default(self):
        s = self._make_summary()
        self.assertEqual(_classify(s), [])

    def test_projection_dominant_flag(self):
        s = self._make_summary(boundary_mass_kg_final=5.0)
        self.assertIn("projection_dominant", _classify(s))

    def test_projection_dominant_negative_boundary(self):
        s = self._make_summary(boundary_mass_kg_final=-3.0)
        self.assertIn("projection_dominant", _classify(s))

    def test_opening_transport_dominant(self):
        s = self._make_summary(opening_total_sum=2.0, plume_entrained_sum=0.5)
        flags = _classify(s)
        self.assertIn("opening_transport_dominant", flags)
        self.assertNotIn("plume_dominant", flags)

    def test_plume_dominant(self):
        s = self._make_summary(opening_total_sum=0.5, plume_entrained_sum=2.0)
        flags = _classify(s)
        self.assertIn("plume_dominant", flags)
        self.assertNotIn("opening_transport_dominant", flags)

    def test_needs_motor_flux_ledger(self):
        s = self._make_summary(attribution_residual_max_abs=0.01)
        self.assertIn("needs_motor_flux_ledger", _classify(s))

    def test_multiple_flags_can_coexist(self):
        s = self._make_summary(
            boundary_mass_kg_final=50.0,
            opening_total_sum=5.0,
            plume_entrained_sum=1.0,
            attribution_residual_max_abs=0.1,
        )
        flags = _classify(s)
        self.assertIn("projection_dominant", flags)
        self.assertIn("opening_transport_dominant", flags)
        self.assertIn("needs_motor_flux_ledger", flags)


class TestAnalyzeCsv(unittest.TestCase):
    def _write_csv(self, df: pd.DataFrame, path: Path) -> None:
        df.to_csv(path, index=False)

    def test_returns_one_summary_per_room(self):
        df = _make_f0_df(n_rows=10, n_rooms=3)
        with tempfile.TemporaryDirectory() as tmpdir:
            p = Path(tmpdir) / "sim_log.csv"
            self._write_csv(df, p)
            results = analyze_csv(str(p))
        self.assertEqual(len(results), 3)
        self.assertEqual({s.room_id for s in results}, {0, 1, 2})

    def test_room_filter(self):
        df = _make_f0_df(n_rows=10, n_rooms=3)
        with tempfile.TemporaryDirectory() as tmpdir:
            p = Path(tmpdir) / "sim_log.csv"
            self._write_csv(df, p)
            results = analyze_csv(str(p), room_filter=1)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0].room_id, 1)

    def test_missing_file_raises(self):
        with self.assertRaises(FileNotFoundError):
            analyze_csv("/nonexistent/path/sim_log.csv")

    def test_no_f0_columns_raises_value_error(self):
        df = _make_f0_df(include_f0=False)
        with tempfile.TemporaryDirectory() as tmpdir:
            p = Path(tmpdir) / "legacy.csv"
            self._write_csv(df, p)
            with self.assertRaises(ValueError) as ctx:
                analyze_csv(str(p))
        self.assertIn("not a Phase 3+ F0 diagnostic CSV", str(ctx.exception))

    def test_room_filter_nonexistent_raises(self):
        df = _make_f0_df(n_rows=5, n_rooms=2)
        with tempfile.TemporaryDirectory() as tmpdir:
            p = Path(tmpdir) / "sim_log.csv"
            self._write_csv(df, p)
            with self.assertRaises(ValueError) as ctx:
                analyze_csv(str(p), room_filter=99)
        self.assertIn("room_id=99", str(ctx.exception))


class TestMainCli(unittest.TestCase):
    def _write_csv(self, df: pd.DataFrame, path: Path) -> None:
        df.to_csv(path, index=False)

    def test_main_exits_0_on_valid_csv(self):
        df = _make_f0_df(n_rows=5, n_rooms=2)
        with tempfile.TemporaryDirectory() as tmpdir:
            p = Path(tmpdir) / "sim_log.csv"
            self._write_csv(df, p)
            rc = main([str(p)])
        self.assertEqual(rc, 0)

    def test_main_exits_1_on_missing_file(self):
        rc = main(["/nonexistent/sim_log.csv"])
        self.assertEqual(rc, 1)

    def test_json_out_is_valid_json(self):
        df = _make_f0_df(n_rows=5, n_rooms=2)
        with tempfile.TemporaryDirectory() as tmpdir:
            p = Path(tmpdir) / "sim_log.csv"
            out = Path(tmpdir) / "out.json"
            self._write_csv(df, p)
            rc = main([str(p), "--json-out", str(out)])
            self.assertEqual(rc, 0)
            with open(out, encoding="utf-8") as f:
                data = json.load(f)
        self.assertIsInstance(data, list)
        self.assertEqual(len(data), 2)
        # Each record must have the key fields
        for rec in data:
            self.assertIn("room_id", rec)
            self.assertIn("flags", rec)
            self.assertIn("boundary_mass_kg_final", rec)

    def test_top_n_limits_output_rooms(self):
        df = _make_f0_df(n_rows=5, n_rooms=3)
        with tempfile.TemporaryDirectory() as tmpdir:
            p = Path(tmpdir) / "sim_log.csv"
            out = Path(tmpdir) / "out.json"
            self._write_csv(df, p)
            rc = main([str(p), "--top", "1", "--json-out", str(out)])
            self.assertEqual(rc, 0)
            with open(out, encoding="utf-8") as f:
                data = json.load(f)
        self.assertEqual(len(data), 1)

    def test_main_exits_1_on_legacy_csv(self):
        df = _make_f0_df(include_f0=False)
        with tempfile.TemporaryDirectory() as tmpdir:
            p = Path(tmpdir) / "legacy.csv"
            self._write_csv(df, p)
            rc = main([str(p)])
        self.assertEqual(rc, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
