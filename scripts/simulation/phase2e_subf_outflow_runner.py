#!/usr/bin/env python3
"""Phase 2E Sub-F — sweep phase2e_co2_upper_outflow_gain for cfast_fo checks.

Tests outflow gain values to fix:
  cfast_fo_t240_co2_upper_pct: actual~5.4% vs expected=7.77% (tol 3.0%)
  cfast_fo_t350_co2_upper_pct: actual~1.3% vs expected=7.89% (tol 3.0%)

Usage:
  python scripts/simulation/phase2e_subf_outflow_runner.py [--gains 0.20 0.10 0.05 ...]
  python scripts/simulation/phase2e_subf_outflow_runner.py --floor 0.0 --gains 0.20 0.10 0.05 0.02 0.01
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES_DIR = ROOT / "sim" / "validation" / "cases"
REPORTS_DIR = ROOT / "sim" / "validation" / "reports"

GODOT_CANDIDATES = [
    Path("C:/Users/dangp/Desktop/Godot_v4.7.1-stable_win64_console.exe"),
    Path("F:/OneDrive/Escritorio/Godot_v4.7.1-stable_win64_console.exe"),
]

BASE_CASE = "cfast_post_flashover_vented"

# CFAST reference and tolerance
CFAST_EXPECTED: dict[int, float] = {150: 3.7544, 240: 7.7738, 350: 7.8923}
TOLERANCE = 3.0  # percentage points


def find_godot(requested: str | None) -> Path | None:
    if requested:
        p = Path(requested)
        if p.exists():
            return p.resolve()
    env_path = os.environ.get("GODOT_EXE")
    if env_path and Path(env_path).exists():
        return Path(env_path).resolve()
    for p in GODOT_CANDIDATES:
        if p.exists():
            return p.resolve()
    return None


def build_case(gain: float, floor: float, label: str) -> tuple[str, Path]:
    base_path = CASES_DIR / f"{BASE_CASE}.json"
    case_name = f"_tmp_subf_og_{label}"
    out_path = CASES_DIR / f"{case_name}.json"
    log_name = f"cfast_fo_subf_og_{label}.log"

    data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    overrides = dict(data.get("engine_overrides", {}))
    overrides["phase2e_co2_upper_outflow_gain"] = gain
    if floor > 0.0:
        overrides["phase2e_co2_o2_scale_floor"] = floor
    overrides["log_file_path"] = f"res://sim/validation/reports/{log_name}"
    data["engine_overrides"] = overrides
    out_path.write_text(json.dumps(data, indent="\t", ensure_ascii=False), encoding="utf-8")

    return case_name, REPORTS_DIR / log_name


def run_case(godot: Path, case_name: str, timeout_s: int) -> bool:
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--", f"--validation-case={case_name}"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
    except subprocess.TimeoutExpired:
        return False
    return result.returncode == 0


def parse_co2u_pct(log_path: Path, target_s: float) -> float:
    if not log_path.exists():
        return math.nan
    time_re = re.compile(r"^TIME=([0-9.]+) s")
    room_re = re.compile(r"^ROOM 0\(")
    co2u_re = re.compile(r"\bCO2u=(\d+)ppm")
    best_dt = math.inf
    best_val = math.nan
    time_s: float | None = None
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = time_re.match(line)
        if m:
            time_s = float(m.group(1))
            continue
        if time_s is None:
            continue
        if not room_re.match(line):
            continue
        co2m = co2u_re.search(line)
        if not co2m:
            continue
        dt = abs(time_s - target_s)
        if dt < best_dt:
            best_dt = dt
            best_val = int(co2m.group(1)) / 10000.0
    return best_val


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=None)
    parser.add_argument(
        "--gains", type=float, nargs="+",
        default=[0.20, 0.10, 0.07, 0.05, 0.03, 0.01],
        help="outflow_gain values to sweep"
    )
    parser.add_argument("--floor", type=float, default=0.0, help="o2_scale_floor (0.0 = off)")
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--skip-run", action="store_true")
    args = parser.parse_args()

    godot = find_godot(args.godot) if not args.skip_run else None
    if godot is None and not args.skip_run:
        print("ERROR: Godot executable not found.")
        return 1

    print("=" * 70)
    print("Phase 2E Sub-F — outflow_gain sweep (cfast_fo scenario)")
    print("CFAST reference:", {t: f"{v:.4f}%" for t, v in CFAST_EXPECTED.items()})
    print(f"Tolerance: ±{TOLERANCE}%   floor={args.floor:.3f}")
    print("=" * 70)

    best_gain: float | None = None
    best_pass = -1

    try:
        for gain in args.gains:
            label = f"g{int(gain * 100):03d}"
            print(f"\n--- outflow_gain={gain:.3f} ({label}) ---")

            case_name, log_path = build_case(gain, args.floor, label)

            if not args.skip_run:
                ok = run_case(godot, case_name, args.timeout)
                tmp_case = CASES_DIR / f"{case_name}.json"
                tmp_case.unlink(missing_ok=True)
                if not ok:
                    print("  [WARN] Godot run failed or timed out")

            passes = 0
            for t in [150, 240, 350]:
                val = parse_co2u_pct(log_path, float(t))
                if math.isnan(val):
                    print(f"  t={t}s: N/A")
                    continue
                exp = CFAST_EXPECTED[t]
                gap = abs(val - exp)
                ok_str = "PASS" if gap <= TOLERANCE else "FAIL"
                if ok_str == "PASS":
                    passes += 1
                print(f"  t={t}s: actual={val:.4f}%  exp={exp:.4f}%  |gap|={gap:.4f}%  {ok_str}")

            print(f"  => {passes}/3 checks pass")
            if passes > best_pass:
                best_pass = passes
                best_gain = gain

    finally:
        for f in CASES_DIR.glob("_tmp_subf_og_*.json"):
            f.unlink(missing_ok=True)

    print("\n" + "=" * 70)
    if best_gain is not None:
        print(f"BEST outflow_gain: {best_gain:.3f}  ({best_pass}/3 checks pass)")
        if best_pass >= 2:
            print(f"\n→ Recommended: set in cfast_post_flashover_vented.json:")
            print(f'    "phase2e_co2_upper_outflow_gain": {best_gain}')
            if args.floor > 0.0:
                print(f'    "phase2e_co2_o2_scale_floor": {args.floor}')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
