"""Reviewed channel/energy attribution, NOT an evaporation or runtime solver.

Conditional work uses the measured decrease and the reviewed reference latent
enthalpy. It is NOT a measured heat input and must never become an inferred B.
Semantic channel attribution is a manual review of TN 1603, not PDF parsing.
"""
from __future__ import annotations

import csv
from decimal import Decimal
import io
import json
from pathlib import Path

from scripts.simulation import audit_g3_heptane_phase_basis as phase
from scripts.simulation import audit_g3_measured_mass_candidate as measured


ROOT = Path(__file__).resolve().parents[2]
SAVED = ROOT / "docs/validation/G3_D1_ISOHEPT9_EMISSION_AUDIT_2026-10-04.json"
GROUPS = {
    "time": ["Time"],
    "room_species_and_soot": [
        "O2Front", "CO2Front", "COFront", "UHFront", "O2Rear", "CO2Rear",
        "CORear", "UHRear", "O2Move", "CO2Move", "COMove", "UHMove",
        "YsootF", "YsootR", "I/Io",
    ],
    "gas_sampling_probe_temperature": ["TFSampPtRh", "TRSampPtRh", "TRMoveSamp"],
    "floor_ceiling_heat_flux_not_pan_net_heat": [
        "HFRFL", "HFFFL", "HFOFL", "HFRCE", "HFCCE", "HFFCE",
    ],
    "heat_flux_gauge_temperature_not_fuel": [
        "THFRFL", "THFFFL", "THFOFL", "THFRCE", "THFCCE", "THFFCE",
    ],
    "enclosure_inner_surface_temperature_not_fuel": [
        "TSHFRFL", "TSHFFFL", "TSHFOFL", "TSHFRCE", "TSHFCCE", "TSHFFCE",
    ],
    "enclosure_outer_surface_temperature_not_fuel": [
        "TSXHFRFL", "TSXHFFFL", "TSXHFRCE", "TSXHFCCE", "TSXHFFCE",
    ],
    "pan_load_cell_mass_not_species_analyzer": ["Mass1", "Mass2"],
    "room_thermocouple_tree_temperature_not_fuel": [
        "TR3", "TR30", "TR60", "TR90", "TR105", "TR120", "TR135", "TR150",
        "TR180", "TR210", "TR237", "TF3", "TF30", "TF60", "TF90", "TF105",
        "TF120", "TF135", "TF150", "TF180", "TF210", "TF237",
    ],
    "exhaust_calorimetry_species": ["CalCO", "CalCO2", "CalO2"],
    "ideal_hrr_derived_from_mass_not_independent": ["IHRR"],
    "exhaust_hrr_not_pan_absorbed_heat": ["HRR2"],
}


def classify_channels(header):
    reviewed = [name for group in GROUPS.values() for name in group]
    if len(header) != len(set(header)):
        raise ValueError("duplicate CSV channel")
    if set(header) != set(reviewed):
        raise ValueError("missing or unreviewed CSV channel; attribution must be reviewed")
    return {name: list(channels) for name, channels in GROUPS.items()}


def audit(root=ROOT):
    root = Path(root).resolve()
    manifest_path = root / measured.DEFAULT_MANIFEST.relative_to(measured.ROOT)
    # Reuse strict source checks, signed signal audit and unchanged windows.
    mass_report = measured.audit(manifest_path, root)
    if (mass_report["case_id"] != "ISOHept9"
            or mass_report["source_revision"] != "e5de6811036d252b4f9085866f08da66efdda7d3"
            or mass_report["source_sha256_lf"] !=
            "66ad9437f81e93750e1d53b7f08b9e5c1068218ec809ed29d308fd9360dccce3"):
        raise ValueError("unreviewed experiment/revision/signal")
    manifest = phase.load_profile(manifest_path)
    phase_input = phase.load_profile(root / phase.INPUT.relative_to(phase.ROOT))
    phase_report = phase.audit(phase_input, root)
    if (manifest["report"]["sha256_raw"] !=
            "7ba8219496f8b52035fd97ed603182782e907034a94593bb51e7382c0cf453f5"
            or phase_report["source_sha256_raw"] !=
            "c964ba6afab1f029ed666fb9768fab2e7683b57c3169814d37693c386b6db21a"):
        raise ValueError("unreviewed apparatus or thermochemical source")
    _, raw = measured.confined_artifact(root, manifest["source"], text=True)
    text = raw.decode("utf-8")
    channels = classify_channels(next(csv.reader(io.StringIO(text))))
    rows = measured.read_mass_rows(text)
    # Retain exact decimal inputs rather than the rounded float audit output.
    selected = [(t, m) for t, m in rows if Decimal(0) <= t <= Decimal(500)]
    window = measured.inspect_window(rows, 0, 500)
    if not window["nonnegative_rate_compatible_without_processing"]:
        raise ValueError("predeclared window no longer supports an unprocessed replay")
    delta = selected[0][1] - selected[-1][1]
    latent = (Decimal(str(phase_input["values"]["fuel_vaporization_enthalpy"]))
              / (Decimal(str(phase_input["molar_mass_g_mol"])) / 1000))
    return {
        "schema": "g3_isohept9_emission_attribution_audit_v1",
        "case_id": mass_report["case_id"],
        "decision": "GO_conditional_reference_diagnostic_NO_GO_predictive_evaporation",
        "source_revision": mass_report["source_revision"],
        "source_sha256_lf": mass_report["source_sha256_lf"],
        "apparatus_report_sha256_raw": manifest["report"]["sha256_raw"],
        "phase_reference_sha256_raw": phase_report["source_sha256_raw"],
        "review_locators_printed_tn1603": {
            "pan_and_load_cells": "section 2.1.4 pp.9-10, Figures 2.4-2.5",
            "experiment": "Table 3.1 p.38, section 3.2 pp.40-41",
            "channel_attribution": "Table 2.5 p.32, Appendix A pp.145-146",
            "heat_flux": "section 2.2.6 pp.29-30",
            "uncertainty": "section 2.6 pp.35-36, Table 2.6",
        },
        "channel_count": sum(len(group) for group in channels.values()),
        "reviewed_channel_groups": channels,
        "conditional_reference_work": {
            "window_s": [0, 500],
            "measured_pan_decrease_kg": float(delta),
            "emission_assumption": "ALL_pan_decrease_is_reference_n_heptane_vapour",
            "assumption_status": "declared_for_diagnostic_NOT_measured_species_fraction",
            "reference_temperature_k": phase_input["reference_temperature_k"],
            "reference_pressure_pa": phase_input["reference_pressure_pa"],
            "latent_reference_kj_kg": float(latent),
            "conditional_phase_work_kj": float(delta * latent),
            "interpretation": "reference_transfer_cost_NOT_observed_heat_or_initial_B",
        },
        "independently_observed_pan_budget_B_kj": None,
        "observed_liquid_temperature_series": None,
        "observed_emitted_component_fraction": None,
        "sensible_energy_identified": False,
        "predictive_evaporation_approval": False,
        "experimental_batch_approval": False,
        "engine_integration": False,
        "production_activation": False,
    }


def main():
    try:
        result = audit()
    except (OSError, ValueError) as exc:
        print(json.dumps({"decision": "rejected", "error": str(exc)}))
        return 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
