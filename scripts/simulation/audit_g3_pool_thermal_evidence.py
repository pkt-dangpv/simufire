"""Offline measurement eligibility/geometry audit; never a thermal solver.

Integrates a declared radial gauge profile only over its measured support.
It cannot turn cold-gauge heat flux into net heat absorbed by liquid, infer
latent heat from MLR, invent missing temperatures, or activate runtime physics.
Manual semantic review is pinned separately from source byte integrity.
"""
from __future__ import annotations

import csv
from decimal import Decimal, InvalidOperation
import hashlib
import io
import json
import math
from pathlib import Path
from urllib.parse import quote

from scripts.simulation.audit_g3_measured_mass_candidate import confined_artifact
from scripts.simulation.validate_g3_mass_material_profile import load_profile


ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "docs/literature/data/NIST_POOL_FIRES_2024/PROVENANCE.json"
SAVED = ROOT / "docs/validation/G3_D1_POOL_THERMAL_AUDIT_2026-10-04.json"
REVISION = "213206ec45b91b2bd7d5f344ebd519662404892b"
REVIEW_SHA256 = "5ef2bc78b491e39149c50306f5158c9ccc109e72a8fb06ab80481925d2dd6b64"
DATA = "docs/literature/data/NIST_POOL_FIRES_2024/"
REMOTE = f"https://raw.githubusercontent.com/MaCFP/macfp-db/{REVISION}/"
EXPERIMENTS = "Liquid_Pool_Fires/NIST_Pool_Fires/Experimental_Data/"
ARTIFACTS = {
    "report": ("docs/literature/NIST/NIST_TN_2162r1_Medium_Scale_Pool_Fires.pdf",
               "c0ba84b39fa6e790f1242bdf594492010c9463b8f5cb61a3616036d6958d11ba"),
    "documentation": (DATA + "SOURCE_DOCUMENTATION.md",
                      "195bb63d33e444140b22f69c24fc9c4e43feab76804c4575947957d104591be6"),
    "license": (DATA + "LICENSE_MaCFP.txt",
                "6c620fe0b123c62fd0e8e0bef732d15949efafb55db144398e18bcd60e9e66f7"),
    "inventory": (DATA + "EXPERIMENTAL_INVENTORY.json",
                  "635a3db89babee94cf65d9d56efc105b09dd943b645f50b9ad59958e939b57fe"),
    "boundary_csv": (DATA + "Heptane_30_cm_HRR_Sung_2024.csv",
                     "7952de10a66394764ed0879249c69acd00e830c4aa7713e1fa9ab35dcf8ee98e"),
}
EXPECTED_ROWS = [
    [r, 1.3, q, None, 1] for r, q in zip(
        [0, 2, 4, 5, 6, 8, 10, 12, 13, 14, 15],
        [21.6, 20.9, 19.4, 20.1, 19.0, 18.6, 17.8, 16.2, 14.4, 15.6, 20.1])
]


def finite_number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("finite numeric value required")
    try:
        value = float(value)
    except (ValueError, OverflowError) as exc:
        raise ValueError("nonfinite value") from exc
    if not math.isfinite(value):
        raise ValueError("nonfinite value")
    return float(value)


def integrate_gauge_profile(rows, pool_radius_m):
    """Exact radial integral for piecewise-linear q(r), no edge extrapolation."""
    radius = finite_number(pool_radius_m)
    if radius <= 0 or not isinstance(rows, list) or len(rows) < 2:
        raise ValueError("positive pool radius and profile required")
    points = []
    for row in rows:
        if not isinstance(row, list) or len(row) != 2:
            raise ValueError("r_m, q_kw_m2 pairs required")
        r, q = map(finite_number, row)
        if r < 0 or q < 0 or r > radius:
            raise ValueError("negative/out-of-pool profile")
        if points and r <= points[-1][0]:
            raise ValueError("r must strictly increase; no sorting or clipping")
        points.append((r, q))
    if points[0][0] != 0:
        raise ValueError("profile must start at the center; no interpolation to zero")
    terms = [
        2 * math.pi * (b - a) / 6 * (qa * (2 * a + b) + qb * (a + 2 * b))
        for (a, qa), (b, qb) in zip(points, points[1:])
    ]
    power = math.fsum(terms)
    if not math.isfinite(power):
        raise ValueError("nonfinite integrated gauge power")
    return {
        "covered_radius_m": points[-1][0],
        "covered_area_fraction": (points[-1][0] / radius) ** 2,
        "axisymmetric_piecewise_linear_gauge_power_kw": power,
        "edge_extrapolation": False,
        "liquid_net_B_kj": None,
        "integrated_uncertainty_kw": None,
    }


def inspect_boundary_csv(text):
    reader = csv.reader(io.StringIO(text))
    if next(reader, None) != ["Time", "HRR", "MLR", "MLRPUA", "X_RAD"]:
        raise ValueError("unreviewed boundary channels")
    if next(reader, None) != ["s", "kW", "kg/s", "kg/s/m2", "none"]:
        raise ValueError("unreviewed boundary units")
    rows = []
    for raw in reader:
        if len(raw) != 5:
            raise ValueError("malformed boundary row")
        try:
            values = [Decimal(v) for v in raw]
        except InvalidOperation as exc:
            raise ValueError("invalid boundary number") from exc
        if any(not v.is_finite() or v < 0 for v in values):
            raise ValueError("nonfinite/negative boundary value")
        rows.append(values)
    if len(rows) != 2 or [r[0] for r in rows] != [Decimal(0), Decimal(600)]:
        raise ValueError("reviewed boundary has two endpoints, not a transient signal")
    if rows[0][1:] != rows[1][1:] or any(v <= 0 for v in rows[0][1:4]):
        raise ValueError("boundary must retain constant positive fields")
    if not 0 <= rows[0][4] <= 1:
        raise ValueError("invalid radiative fraction")
    return {"row_count": 2, "kind": "constant_boundary_NOT_transient_measurement",
            "hrr_kw": float(rows[0][1]), "mlr_kg_s": float(rows[0][2]),
            "mlrpua_kg_s_m2": float(rows[0][3]), "x_rad": float(rows[0][4])}


def inspect_inventory(records):
    if not isinstance(records, list) or not records:
        raise ValueError("experimental inventory required")
    names = []
    for record in records:
        if not isinstance(record, dict) or record.get("type") != "file":
            raise ValueError("only experimental source files allowed")
        name = record.get("name")
        if (not isinstance(name, str) or record.get("path") != EXPERIMENTS + name
                or record.get("download_url") != REMOTE + quote(EXPERIMENTS + name, safe="/")):
            raise ValueError("wrong inventory revision/path")
        names.append(name)
    if len(names) != len(set(names)):
        raise ValueError("duplicate inventory file")
    heptane = sorted(n for n in names if n.startswith("Heptane"))
    if heptane != sorted([
        "Heptane_30_cm_HRR_Sung_2024.csv",
        "Heptane_30_cm_TC_r=0_cm_Sung_2024.csv",
        "Heptane_30_cm_U_r=0_Sung_2024.csv",
    ]):
        raise ValueError("heptane inventory needs a new semantic review")
    return heptane


def audit(record=None, root=ROOT):
    root = Path(root).resolve()
    if record is None:
        record = load_profile(root / INPUT.relative_to(ROOT))
    if (not isinstance(record, dict)
            or set(record) != {"schema", "revision", "retrieved_at", "artifacts", "review"}
            or record["schema"] != "g3_nist_pool_thermal_review_v1"
            or record["revision"] != REVISION or record["retrieved_at"] != "2026-10-04"):
        raise ValueError("unreviewed thermal source/revision")
    artifacts = record["artifacts"]
    if not isinstance(artifacts, dict) or set(artifacts) != set(ARTIFACTS):
        raise ValueError("incomplete or extra artifacts")
    content = {}
    for key, (path, sha) in ARTIFACTS.items():
        source = artifacts[key]
        checksum = "sha256_raw" if key == "report" else "sha256_lf"
        if (not isinstance(source, dict) or set(source) != {"path", "url", checksum}
                or source["path"] != path or source[checksum] != sha
                or not isinstance(source["url"], str)):
            raise ValueError("unreviewed artifact identity")
        if key == "report":
            expected_url = "https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2162r1.pdf"
        elif key == "inventory":
            expected_url = ("https://api.github.com/repos/MaCFP/macfp-db/contents/"
                            + EXPERIMENTS.rstrip("/") + "?ref=" + REVISION)
        else:
            remote_path = {"documentation": "Liquid_Pool_Fires/NIST_Pool_Fires/Documentation/README.md",
                           "license": "LICENSE", "boundary_csv": EXPERIMENTS + Path(path).name}[key]
            expected_url = REMOTE + remote_path
        if source["url"] != expected_url:
            raise ValueError("unreviewed artifact URL")
        _, raw = confined_artifact(root, source, text=key != "report")
        content[key] = raw
    # Compare to the complete manually reviewed transcription, without accepting
    # bool-as-number equality. This pins attribution, not merely file hashes.
    reviewed_bytes = json.dumps(record["review"], sort_keys=True, allow_nan=False).encode("utf-8")
    if hashlib.sha256(reviewed_bytes).hexdigest() != REVIEW_SHA256:
        raise ValueError("unreviewed semantics or promotion of physical approval")
    review = record["review"]
    if review["heptane_flux_rows"] != EXPECTED_ROWS:
        raise ValueError("changed manual flux transcription")
    boundary = inspect_boundary_csv(content["boundary_csv"].decode("utf-8"))
    files = inspect_inventory(json.loads(content["inventory"]))
    radius = finite_number(review["pool_diameter_m"]) / 2
    profile = [[finite_number(row[0]) / 100, finite_number(row[2])]
               for row in review["heptane_flux_rows"]]
    integral = integrate_gauge_profile(profile, radius)
    return {
        "schema": "g3_pool_thermal_evidence_audit_v1",
        "decision": "GO_independent_gauge_observables_NO_GO_liquid_net_budget",
        "revision": REVISION, "report_sha256_raw": ARTIFACTS["report"][1],
        "profile_source": "manual_Table_F38_transcription_not_raw_acquisition",
        "profile_sample_count": len(profile),
        "profile_repeat_per_location": 1, "profile_sd_kw_m2": None,
        "independent_of_mass_loss_inversion": True,
        "gauge_profile_diagnostic": integral,
        "boundary_csv": boundary, "heptane_inventory": files,
        "tn_table2_ideal_hrr_kw": review["tn_table2_ideal_hrr_kw"],
        "cross_source_hrr_substitution": False,
        "surface_temperature_conflict": review["surface_temperature_conflict"],
        "height_conflict": review["height_conflict"],
        "liquid_cp_T_identified": False, "sensible_energy_identified": False,
        "physical_benchmark_approval": False,
        "engine_integration": False, "production_activation": False,
    }


def main():
    try:
        result = audit()
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(json.dumps({"decision": "rejected", "error": str(exc)}))
        return 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
