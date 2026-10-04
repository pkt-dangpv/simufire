"""Audit measured mass without clipping, smoothing, HRR inversion or a profile.

This inspects a reduced experimental signal, not a predictive fuel law.
Unused CSV channels may contain NaN; Time and Mass1 must be finite.
"""

from __future__ import annotations

import argparse
import csv
from decimal import Decimal, InvalidOperation
import hashlib
import io
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / "docs/literature/data/NIST_FSE_2008/PROVENANCE.json"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def confined_artifact(root: Path, record: dict, *, text: bool) -> tuple[Path, bytes]:
    declared = Path(record["path"])
    if declared.is_absolute():
        raise ValueError("artifact must be repository-relative")
    path = (root / declared).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError("artifact escapes repository")
    data = path.read_bytes()
    checked = data.replace(b"\r\n", b"\n") if text else data
    key = "sha256_lf" if text else "sha256_raw"
    if sha256(checked) != record[key]:
        raise ValueError(f"artifact content mismatch: {record['path']}")
    return path, data


def finite_decimal(value: str, label: str) -> Decimal:
    try:
        number = Decimal(value)
    except (InvalidOperation, TypeError, ValueError) as exc:
        raise ValueError(f"invalid {label}") from exc
    if not number.is_finite():
        raise ValueError(f"nonfinite {label}")
    return number


def read_mass_rows(text: str) -> list[tuple[Decimal, Decimal]]:
    reader = csv.reader(io.StringIO(text))
    header = next(reader, [])
    if len(set(header)) != len(header):
        raise ValueError("duplicate CSV column")
    if not {"Time", "Mass1"}.issubset(header):
        raise ValueError("required Time/Mass1 columns missing")
    time_index, mass_index = header.index("Time"), header.index("Mass1")
    rows = []
    for line, values in enumerate(reader, 2):
        if len(values) != len(header):
            raise ValueError(f"malformed CSV row {line}")
        time = finite_decimal(values[time_index], f"Time at row {line}")
        mass = finite_decimal(values[mass_index], f"Mass1 at row {line}")
        if rows and time <= rows[-1][0]:
            raise ValueError("Time must strictly increase; no sorting or deduplication")
        rows.append((time, mass))
    if len(rows) < 2:
        raise ValueError("need at least two measured samples")
    return rows


def inspect_window(rows: list[tuple[Decimal, Decimal]], start, end) -> dict:
    start = finite_decimal(str(start), "window start")
    end = finite_decimal(str(end), "window end")
    if start >= end:
        raise ValueError("invalid window")
    selected = [(t, m) for t, m in rows if start <= t <= end]
    if len(selected) < 2 or selected[0][0] != start or selected[-1][0] != end:
        raise ValueError("window endpoints must be actual measured samples")
    changes = [(t1, t2, m1 - m2, (m1 - m2) / (t2 - t1))
               for (t1, m1), (t2, m2) in zip(selected, selected[1:])]
    losses = sum((d for _, _, d, _ in changes if d > 0), Decimal(0))
    gains = sum((-d for _, _, d, _ in changes if d < 0), Decimal(0))
    net = selected[0][1] - selected[-1][1]
    assert losses - gains == net  # exact decimal accounting, not physical approval
    return {
        "window_s": [float(start), float(end)],
        "sample_count": len(selected),
        "start_mass_kg": float(selected[0][1]),
        "end_mass_kg": float(selected[-1][1]),
        "net_measured_decrease_kg": float(net),
        "sum_positive_decreases_kg": float(losses),
        "sum_mass_increases_kg": float(gains),
        "increase_interval_count": sum(d < 0 for _, _, d, _ in changes),
        "negative_sample_count": sum(m < 0 for _, m in selected),
        "largest_increase_kg": float(max((max(-d, Decimal(0))
                                         for _, _, d, _ in changes))),
        "negative_rate_intervals": [
            {"start_s": float(t1), "end_s": float(t2),
             "measured_increase_kg": float(-d)}
            for t1, t2, d, _ in changes if d < 0
        ],
        "signed_secant_rate_range_kg_s": [
            float(min(rate for _, _, _, rate in changes)),
            float(max(rate for _, _, _, rate in changes)),
        ],
        "nonnegative_rate_compatible_without_processing": all(
            d >= 0 for _, _, d, _ in changes
        ) and all(m >= 0 for _, m in selected),
    }


def audit(manifest_path: Path = DEFAULT_MANIFEST, root: Path = ROOT) -> dict:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest["schema"] != "g3_measured_mass_candidate_v1":
        raise ValueError("unknown measured mass schema")
    if manifest["rate_processing"] != "none":
        raise ValueError("this audit accepts only an unprocessed candidate")
    for field in ("scientific_approval", "engine_integration", "production_activation"):
        if manifest[field] is not False:
            raise ValueError("candidate cannot claim approval or activation")
    for column, unit in (("Time", "s"), ("Mass1", "kg")):
        if manifest["columns_reviewed"][column]["unit"] != unit:
            raise ValueError("unexpected units; no automatic conversion")
    path, data = confined_artifact(root, manifest["source"], text=True)
    confined_artifact(root, manifest["license"], text=True)
    confined_artifact(root, manifest["report"], text=False)
    rows = read_mass_rows(data.decode("utf-8"))
    ignition = [mass for time, mass in rows if time == 0]
    if len(ignition) != 1:
        raise ValueError("need a measured sample at ignition")
    entire = inspect_window(rows, rows[0][0], rows[-1][0])
    return {
        "schema": "g3_measured_mass_audit_v1",
        "case_id": manifest["case_id"],
        "source_path": path.relative_to(root.resolve()).as_posix(),
        "source_revision": manifest["revision"],
        "source_sha256_lf": sha256(data.replace(b"\r\n", b"\n")),
        "row_count": len(rows),
        "sample_steps_s": sorted({float(b[0] - a[0])
                                  for a, b in zip(rows, rows[1:])}),
        "mass_at_ignition_kg": float(ignition[0]),
        "nominal_table_mass_kg": manifest["experiment"]["initial_mass_table_kg"],
        "nominal_minus_ignition_kg": float(
            Decimal(str(manifest["experiment"]["initial_mass_table_kg"])) - ignition[0]
        ),
        "whole_record": entire,
        "windows": [inspect_window(rows, a, b)
                    for a, b in manifest["audit_windows_s"]],
        "decision": "measured_mass_candidate_not_engine_profile",
        "rate_processing": "none",
        "profile_generated": False,
        "scientific_approval": False,
        "engine_integration": False,
        "production_activation": False,
        "limits": [
            "Signed measured changes are not emitted component masses.",
            "Secants are interval averages, not piecewise-linear rate nodes.",
            "No clipping, smoothing, interpolation or HRR inversion applied.",
            "Liquid experiment does not validate solid pyrolysis or CO/FED.",
            "Uncertainty, component attribution and phase/energy basis remain open.",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = json.dumps(audit(args.manifest), indent=2, ensure_ascii=False,
                        allow_nan=False) + "\n"
    if args.output:
        args.output.write_text(result, encoding="utf-8", newline="\n")
    else:
        print(result, end="")


if __name__ == "__main__":
    main()
