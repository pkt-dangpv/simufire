"""Prepare a bounded mass-only replay, NOT a material/emission profile.

Secant rates are constant on [t_k,t_k+1). This is numerical reconstruction
of measured depletion; it is not an independently predicted evaporation law.
"""

from __future__ import annotations

import argparse
from decimal import Decimal
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.simulation import audit_g3_measured_mass_candidate as measured  # noqa: E402


def rates_from_rows(rows):
    # Reuse strict CSV channel validation without sorting or inventing samples.
    parsed = measured.read_mass_rows("Time,Mass1\n" + "".join(
        f"{t},{m}\n" for t, m in rows))
    if parsed[0][0] != 0:
        raise ValueError("replay must start at ignition")
    if any(m < 0 for _, m in parsed):
        raise ValueError("negative measured mass; no clipping")
    samples = []
    for (t0, m0), (t1, m1) in zip(parsed, parsed[1:]):
        if m1 > m0:
            raise ValueError("measured mass increase; no clipping or smoothing")
        samples.append({"time_s": float(t0), "rate_kg_s": float((m0 - m1) / (t1 - t0))})
    samples.append({"time_s": float(parsed[-1][0]), "rate_kg_s": 0.0})
    return samples


def build(root: Path = ROOT):
    report = measured.audit(root / measured.DEFAULT_MANIFEST.relative_to(measured.ROOT), root)
    source = root / report["source_path"]
    all_rows = measured.read_mass_rows(source.read_text(encoding="utf-8"))
    rows = [(t, m) for t, m in all_rows if Decimal(0) <= t <= Decimal(500)]
    if rows[0][0] != 0 or rows[-1][0] != 500:
        raise ValueError("predeclared window endpoints absent")
    samples = rates_from_rows(rows)
    return {
        "schema": "g3_measured_mass_replay_fixture_v1",
        "scope": "numerical_reservoir_depletion_replay_only",
        "source_revision": report["source_revision"],
        "source_sha256_lf": report["source_sha256_lf"],
        "window_s": [0, 500],
        "mass_tolerance_kg": 1e-9,
        "tolerance_basis": "numerical_not_experimental_uncertainty",
        "quantity_attribution": "Measured liquid pan mass decrease; not modeled gaseous component emission",
        "scientific_approval": False,
        "engine_integration": False,
        "production_activation": False,
        "program": {
            "profile_id": "ISOHept9_mass_only_0_500s",
            "component_id": "observed_heptane_liquid_reservoir",
            "initial_mass_kg": float(rows[0][1]),
            "mode": "prescribed",
            "quantity": "measured_reservoir_depletion",
            "unit": "kg/s",
            "time_origin": "ignition",
            "interpolation": "piecewise_constant_left",
            "outside_domain": "reject",
            "samples": samples,
        },
        "observations": [{"time_s": float(t), "mass_kg": float(m)} for t, m in rows],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    text = json.dumps(build(), indent=2, allow_nan=False) + "\n"
    if args.output:
        args.output.write_text(text, encoding="utf-8", newline="\n")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
