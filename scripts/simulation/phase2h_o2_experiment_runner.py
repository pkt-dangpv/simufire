#!/usr/bin/env python3
"""Phase 2H O2 lower-layer experiment runner.

Creates temporary validation cases with Phase 2H lower-zone replenishment flags,
runs the CFAST-aligned cases, and prints O2l at the known gap timestamps.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


ROOT = Path(__file__).resolve().parents[2]
CASES_DIR = ROOT / "sim" / "validation" / "cases"
REPORTS_DIR = ROOT / "sim" / "validation" / "reports"

GODOT_CANDIDATES = [
    Path("C:/Users/dangp/Desktop/Godot_v4.7.1-stable_win64_console.exe"),
    Path("F:/OneDrive/Escritorio/Godot_v4.7.1-stable_win64_console.exe"),
]

O2_TARGETS = [
    ("cfast_r0_window_360", 0, 350.0, "cfast_t350_o2_lower", 0.204932, 0.015),
    ("cfast_r0_window_360", 0, 420.0, "cfast_t420_o2_lower", 0.187821, 0.015),
    ("cfast_single_room_closed", 0, 300.0, "cfast_closed_t300_o2_lower", 0.204932, 0.015),
    ("cfast_single_room_closed", 0, 450.0, "cfast_closed_t450_o2_lower", 0.204932, 0.015),
    ("cfast_two_room_door_open", 0, 180.0, "cfast_2r_r0_t180_o2_lower", 0.182583, 0.015),
    ("cfast_two_room_door_open", 0, 300.0, "cfast_2r_r0_t300_o2_lower", 0.095180, 0.015),
    ("cfast_two_room_door_open", 0, 450.0, "cfast_2r_r0_t450_o2_lower", 0.090873, 0.015),
    ("cfast_hvac_residential", 0, 180.0, "cfast_hvac_t180_o2_lower", 0.204932, 0.015),
    ("cfast_hvac_residential", 0, 300.0, "cfast_hvac_t300_o2_lower", 0.204932, 0.015),
    ("cfast_hvac_residential", 0, 450.0, "cfast_hvac_t450_o2_lower", 0.204932, 0.015),
]


def find_godot(requested: str | None) -> Path | None:
    if requested:
        path = Path(requested)
        if path.exists():
            return path.resolve()
    env_path = os.environ.get("GODOT_EXE")
    if env_path and Path(env_path).exists():
        return Path(env_path).resolve()
    for path in GODOT_CANDIDATES:
        if path.exists():
            return path.resolve()
    return None


def build_case(
    base_case: str,
    exp_case: str,
    gain: float,
    interior_drain_gain: float,
    interior_drain_max_scale: float,
) -> Path:
    base_path = CASES_DIR / f"{base_case}.json"
    out_path = CASES_DIR / f"{exp_case}.json"
    data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    overrides = dict(data.get("engine_overrides", {}))
    overrides["phase2h_o2_doorway_two_zone_enabled"] = True
    overrides["phase2h_cold_room_lower_routing_enabled"] = True
    overrides["phase2h_lower_replenish_gain"] = gain
    overrides["phase2h_interior_no_exterior_drain_gain"] = interior_drain_gain
    overrides["phase2h_interior_no_exterior_drain_max_scale"] = interior_drain_max_scale
    overrides["log_file_path"] = f"res://sim/validation/reports/{exp_case}.log"
    data["engine_overrides"] = overrides
    out_path.write_text(json.dumps(data, indent="\t", ensure_ascii=False), encoding="utf-8")
    return out_path


def run_case(godot: Path, case_name: str, timeout_s: int) -> tuple[bool, str]:
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--", f"--validation-case={case_name}"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
    except subprocess.TimeoutExpired:
        return False, "timeout"
    output = (result.stdout or "") + (result.stderr or "")
    return result.returncode == 0, output[-3000:]


def parse_o2l(log_path: Path, room_id: int, target_s: float) -> float:
    if not log_path.exists():
        return math.nan
    time_s: float | None = None
    best_dt = math.inf
    best_o2l = math.nan
    time_re = re.compile(r"^TIME=([0-9.]+) s")
    room_re = re.compile(rf"^ROOM {room_id}\([^)]*\) \| (.*)$")
    o2l_re = re.compile(r"(?:^| \| )O2l=([0-9.]+)")
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        time_match = time_re.match(line)
        if time_match:
            time_s = float(time_match.group(1))
            continue
        if time_s is None:
            continue
        room_match = room_re.match(line)
        if not room_match:
            continue
        o2l_match = o2l_re.search(line)
        if not o2l_match:
            continue
        dt = abs(time_s - target_s)
        if dt < best_dt:
            best_dt = dt
            best_o2l = float(o2l_match.group(1))
    return best_o2l


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=None)
    parser.add_argument("--gains", type=float, nargs="+", default=[0.25])
    parser.add_argument("--interior-drain-gains", type=float, nargs="+", default=[0.0])
    parser.add_argument("--interior-drain-max-scales", type=float, nargs="+", default=[1.40])
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--cases", nargs="+", default=None)
    parser.add_argument("--skip-run", action="store_true")
    args = parser.parse_args()

    godot = find_godot(args.godot)
    if godot is None and not args.skip_run:
        print("ERROR: Godot not found")
        return 1

    selected_cases = set(args.cases) if args.cases else None
    selected_targets = [
        target for target in O2_TARGETS
        if selected_cases is None or target[0] in selected_cases
    ]
    cases = sorted({case for case, *_ in selected_targets})
    temp_cases: list[Path] = []
    try:
        for gain in args.gains:
            for interior_drain_gain in args.interior_drain_gains:
                for interior_drain_max_scale in args.interior_drain_max_scales:
                    tag = (
                        f"p2h_g{int(round(gain * 100)):03d}"
                        f"_d{int(round(interior_drain_gain * 100)):03d}"
                        f"_s{int(round(interior_drain_max_scale * 100)):03d}"
                    )
                    if not args.skip_run:
                        for case in cases:
                            exp_case = f"{case}_{tag}"
                            temp_cases.append(
                                build_case(
                                    case,
                                    exp_case,
                                    gain,
                                    interior_drain_gain,
                                    interior_drain_max_scale,
                                )
                            )
                            print(
                                f"RUN gain={gain:.2f} interior_drain={interior_drain_gain:.2f} "
                                f"max_scale={interior_drain_max_scale:.2f} {case}",
                                flush=True,
                            )
                            ok_run, run_output = run_case(godot, exp_case, args.timeout)
                            if not ok_run:
                                print(f"FAIL {exp_case}")
                                if run_output:
                                    print(run_output)
                                return 1

                    print(
                        f"\nO2 lower results for gain={gain:.2f}, "
                        f"interior_drain={interior_drain_gain:.2f}, "
                        f"max_scale={interior_drain_max_scale:.2f}"
                    )
                    print("check,actual,expected,tolerance,pass")
                    for case, room_id, target_s, check, expected, tol in selected_targets:
                        exp_case = f"{case}_{tag}"
                        actual = parse_o2l(REPORTS_DIR / f"{exp_case}.log", room_id, target_s)
                        ok = not math.isnan(actual) and abs(actual - expected) <= tol
                        print(f"{check},{actual:.4f},{expected:.4f},{tol:.4f},{ok}")
    finally:
        for path in temp_cases:
            try:
                path.unlink()
            except OSError:
                pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
