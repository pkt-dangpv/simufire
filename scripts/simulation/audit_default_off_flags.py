"""Audit P1R4 default-OFF engine controls and their runtime evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / "sim/core/SimulationEngine.gd"
DECLARATION_RE = re.compile(
    r"^@export var (?P<name>[A-Za-z0-9_]+): bool = false:?\s*$", re.MULTILINE
)

MISSING_ACTIVATION_FIXTURE = "tests/fixtures/p1r4_missing_diagnostic_activation.gd"
MISSING_ACTIVATION_TOKEN = "P1R4_MISSING_DIAGNOSTIC_ACTIVATION_PASS"

# One selected runtime proof per retained diagnostic. Several flags legitimately
# share a fixture because they form one dependency-gated diagnostic stack.
RUNTIME_ACTIVATIONS: dict[str, tuple[str, str]] = {
    "energy_budget_enabled": (MISSING_ACTIVATION_FIXTURE, MISSING_ACTIVATION_TOKEN),
    "conservation_check_enabled": (MISSING_ACTIVATION_FIXTURE, MISSING_ACTIVATION_TOKEN),
    "phase3_zone_diagnostics_enabled": (
        "tests/fixtures/phase3_h32b1_causal_only_activation.gd",
        "PHASE3_H32B1_CAUSAL_ONLY_ACTIVATION_PASS",
    ),
    "phase3_runtime_ownership_ledger_enabled": (
        "tests/fixtures/phase3_h32b1_causal_only_activation.gd",
        "PHASE3_H32B1_CAUSAL_ONLY_ACTIVATION_PASS",
    ),
    "phase3_physical_owner_ledger_enabled": (
        "tests/fixtures/phase3_h32s0b_thermal_physical_owners.gd",
        "PHASE3_H32S0B_THERMAL_PHYSICAL_OWNERS_PASS",
    ),
    "phase3_species_attribution_diagnostics_enabled": (
        "tests/fixtures/phase3_h32s0d3_species_attribution.gd",
        "PHASE3_H32S0D3_SPECIES_ATTRIBUTION_PASS",
    ),
    "phase3_projection_causal_diagnostics_enabled": (
        "tests/fixtures/phase3_h32b1_causal_only_activation.gd",
        "PHASE3_H32B1_CAUSAL_ONLY_ACTIVATION_PASS",
    ),
    "phase3_residual_projection_shadow_enabled": (
        "tests/fixtures/phase3_h32b3_residual_projection_shadow.gd",
        "PHASE3_H32B3_RESIDUAL_PROJECTION_SHADOW_PASS",
    ),
    "phase3_zone_transition_diagnostics_enabled": (
        "tests/fixtures/phase3_h32b1b_zone_transition.gd",
        "PHASE3_H32B1B_ZONE_TRANSITION_PASS",
    ),
    "phase3_o2_attribution_diagnostics_enabled": (
        "tests/fixtures/phase3_h32s0d6_o2_attribution.gd",
        "PHASE3_H32S0D6_O2_ATTRIBUTION_PASS",
    ),
    "phase3_co_zonal_transport_consistency_enabled": (
        "tests/fixtures/phase3_h32s0d5a_co_zonal_transport.gd",
        "PHASE3_H32S0D5A_CO_ZONAL_TRANSPORT_PASS",
    ),
    "phase3_co_first_violation_trace_enabled": (
        "tests/fixtures/phase3_h32s0d5a2_co_violation_trace.gd",
        "PHASE3_H32S0D5A2_CO_VIOLATION_TRACE_PASS",
    ),
    "phase3_co2_zonal_transport_consistency_enabled": (
        "tests/fixtures/phase3_h32s0d5b_co2_zonal_transport.gd",
        "PHASE3_H32S0D5B_CO2_ZONAL_TRANSPORT_PASS",
    ),
    "phase3_canonical_zone_shadow_enabled": (
        "tests/fixtures/p1r3_zonal_o2_mass_migration.gd",
        "P1R3_ZONAL_O2_MASS_MIGRATION_PASS",
    ),
    "phase3_canonical_exterior_boundary_shadow_enabled": (
        MISSING_ACTIVATION_FIXTURE,
        MISSING_ACTIVATION_TOKEN,
    ),
    "phase3_canonical_persistence_shadow_enabled": (
        "tests/fixtures/phase3_f32b_persistent_shadow.gd",
        "PHASE3_F32B_PERSISTENT_SHADOW_PASS",
    ),
    "phase3_o2_zonal_mass_shadow_enabled": (
        "tests/fixtures/p1r3_zonal_o2_mass_migration.gd",
        "P1R3_ZONAL_O2_MASS_MIGRATION_PASS",
    ),
    "phase3_canonical_combustion_shadow_enabled": (
        "tests/fixtures/phase3_f32b1_combustion_transaction.gd",
        "PHASE3_F32B1_COMBUSTION_TRANSACTION_PASS",
    ),
    "phase3_canonical_pressure_relaxation_shadow_enabled": (
        "tests/fixtures/phase3_f32b2_pressure_relaxation.gd",
        "PHASE3_F32B2_PRESSURE_RELAXATION_PASS",
    ),
    "phase3_canonical_plume_shadow_enabled": (
        "tests/fixtures/phase3_f32b3_canonical_plume.gd",
        "PHASE3_F32B3_CANONICAL_PLUME_PASS",
    ),
    "phase3_canonical_interzone_heat_shadow_enabled": (
        "tests/fixtures/phase3_f32b5a_interzone_heat.gd",
        "PHASE3_F32B5A_INTERZONE_HEAT_PASS",
    ),
    "phase3_canonical_wall_ambient_shadow_enabled": (
        "tests/fixtures/phase3_f32b5b_wall_ambient.gd",
        "PHASE3_F32B5B_WALL_AMBIENT_PASS",
    ),
    "phase3_canonical_multisurface_shadow_enabled": (
        "tests/fixtures/phase3_f33r2a_surface_energy_solver.gd",
        "PHASE3_F33R2A_SURFACE_ENERGY_SOLVER_PASS",
    ),
    "phase3_coupled_plume_shadow_enabled": (
        "tests/fixtures/phase3_f33t_coupled_plume.gd",
        "PHASE3_F33T_COUPLED_PLUME_PASS",
    ),
    "phase3_canonical_fire_proposal_shadow_enabled": (
        "tests/fixtures/phase3_f33v1_fire_proposal.gd",
        "PHASE3_F33V1_FIRE_PROPOSAL_PASS",
    ),
    "phase3_canonical_unfiltered_fire_growth_shadow_enabled": (
        "tests/fixtures/phase3_f33v1_fire_proposal.gd",
        "PHASE3_F33V1_FIRE_PROPOSAL_PASS",
    ),
    "phase3_canonical_fire_products_shadow_enabled": (
        "tests/fixtures/phase3_f33v2_fire_products.gd",
        "PHASE3_F33V2_FIRE_PRODUCTS_PASS",
    ),
    "phase3_canonical_fire_products_routing_shadow_enabled": (
        MISSING_ACTIVATION_FIXTURE,
        MISSING_ACTIVATION_TOKEN,
    ),
    "phase3_canonical_fuel_object_sync_shadow_enabled": (
        "tests/fixtures/phase3_f33v2c_fuel_object_sync.gd",
        "PHASE3_F33V2C_FUEL_OBJECT_SYNC_PASS",
    ),
    "phase3_canonical_exterior_counterflow_shadow_enabled": (
        "tests/fixtures/phase3_f32b6_exterior_counterflow.gd",
        "PHASE3_F32B6_EXTERIOR_COUNTERFLOW_PASS",
    ),
    "phase3_canonical_post_opening_coupling_shadow_enabled": (
        "tests/fixtures/phase3_f32b7_post_opening_coupling.gd",
        "PHASE3_F32B7_POST_OPENING_COUPLING_PASS",
    ),
    "phase3_canonical_interior_opening_shadow_enabled": (
        "tests/fixtures/phase3_f33a_interior_opening_shadow.gd",
        "PHASE3_F33A_INTERIOR_OPENING_SHADOW_PASS",
    ),
    "phase3_canonical_interior_pressure_shadow_enabled": (
        "tests/fixtures/phase3_f33b_interior_pressure_shadow.gd",
        "PHASE3_F33B_INTERIOR_PRESSURE_SHADOW_PASS",
    ),
    "phase3_canonical_fixed_gross_pressure_skew_shadow_enabled": (
        "tests/fixtures/phase3_f33v3g2_pressure_network_preview.gd",
        "PHASE3_F33V3G2_PRESSURE_NETWORK_PREVIEW_PASS",
    ),
    "phase3_canonical_fixed_gross_pressure_network_shadow_enabled": (
        "tests/fixtures/phase3_f33v3g2_pressure_network_preview.gd",
        "PHASE3_F33V3G2_PRESSURE_NETWORK_PREVIEW_PASS",
    ),
    "phase3_coupled_pressure_solver_shadow_enabled": (
        MISSING_ACTIVATION_FIXTURE,
        MISSING_ACTIVATION_TOKEN,
    ),
    "phase3_coupled_interior_bundle_shadow_enabled": (
        "tests/fixtures/phase3_h32m_coupled_bundle_shadow.gd",
        "PHASE3_H32M_COUPLED_BUNDLE_SHADOW_PASS",
    ),
    "phase3_enthalpy_residence_diagnostics_enabled": (
        "tests/fixtures/phase3_f33c1_enthalpy_residence_ledger.gd",
        "PHASE3_F33C1_ENTHALPY_RESIDENCE_LEDGER_PASS",
    ),
    "phase3_mass_residence_diagnostics_enabled": (
        "tests/fixtures/phase3_f33d1_mass_residence_ledger.gd",
        "PHASE3_F33D1_MASS_RESIDENCE_LEDGER_PASS",
    ),
    "phase3_connection_residence_diagnostics_enabled": (
        "tests/fixtures/phase3_f33k_connection_residence_ledger.gd",
        "PHASE3_F33K_CONNECTION_RESIDENCE_LEDGER_PASS",
    ),
    "phase3_cfast_buoyancy_destination_shadow_enabled": (
        MISSING_ACTIVATION_FIXTURE,
        MISSING_ACTIVATION_TOKEN,
    ),
}

OUT_OF_RUNTIME_SCOPE = {
    "auto_finish_on_extinction",
    "canonical_doorway_exchange_enabled",
    "co_oxidation_enabled",
    "doorway_thermal_counterflow_enabled",
    "fed_co2_source_mass",
    "fire_fds_extinction_enabled",
    "fire_o2_canonical_enabled",
    "fire_o2_independent",
    "fire_o2_lower_for_flame",
    "fire_o2_mass_tracking_enabled",
    "fire_o2_stoich_consumption_enabled",
    "fire_o2_upper_for_flame",
    "fire_o2_upper_throttle_enabled",
    "fire_post_bd_hrr_cut_enabled",
    "fire_spread_enabled",
    "hvac_two_zone_o2_enabled",
    "passive_room_autoignite_enabled",
    "phase2e_co2_subb_enabled",
    "phase2e_co2_subc_enabled",
    "phase2e_two_zone_transport_enabled",
    "phase2f_co_interlayer_mixing_enabled",
    "phase2g_co_lower_source_enabled",
    "phase2h_candidate_preset",
    "phase2h_cold_room_lower_routing_enabled",
    "phase2h_o2_doorway_two_zone_enabled",
    "phase3_conservative_lower_return_enabled",
    "phase3_pressure_canonical_enabled",
    "phase3_stairwell_heat_bridge_enabled",
    "phase3_suppression_lower_energy_sink_enabled",
    "phase3a_pressure_ode_enabled",
    "phase3b_neutral_plane_dp_correction",
    "phase4b_wall_reradiation_during_fire_enabled",
    "plume_flame_region_entrainment_enabled",
    "wall_layer_aware_conduction",
}

FORBIDDEN_RUNTIME_MARKERS = ("SCRIPT ERROR:", "ERROR:", "FATAL:", "CRASH")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def discover() -> dict[str, int]:
    source = ENGINE.read_text(encoding="utf-8")
    return {
        match.group("name"): source.count("\n", 0, match.start()) + 1
        for match in DECLARATION_RE.finditer(source)
    }


def static_audit() -> dict:
    declared = discover()
    classified = set(RUNTIME_ACTIVATIONS) | OUT_OF_RUNTIME_SCOPE
    errors: list[str] = []
    if len(declared) != 75:
        errors.append(f"expected 75 declarations, found {len(declared)}")
    if set(declared) != classified:
        errors.append(
            "classification mismatch: missing=%s extra=%s"
            % [sorted(set(declared) - classified), sorted(classified - set(declared))]
        )
    if set(RUNTIME_ACTIVATIONS) & OUT_OF_RUNTIME_SCOPE:
        errors.append("runtime and out-of-scope partitions overlap")

    records = []
    for name, line in sorted(declared.items(), key=lambda item: item[1]):
        if name in RUNTIME_ACTIVATIONS:
            fixture_rel, token = RUNTIME_ACTIVATIONS[name]
            fixture = ROOT / fixture_rel
            if not fixture.is_file():
                errors.append(f"missing fixture for {name}: {fixture_rel}")
                fixture_hash = None
            else:
                source = fixture.read_text(encoding="utf-8")
                if token not in source:
                    errors.append(f"missing success token for {name}: {token}")
                fixture_hash = _sha256(fixture)
            records.append(
                {
                    "flag": name,
                    "line": line,
                    "default": False,
                    "disposition": "runtime-backed",
                    "fixture": fixture_rel,
                    "success_token": token,
                    "fixture_sha256": fixture_hash,
                }
            )
        else:
            records.append(
                {
                    "flag": name,
                    "line": line,
                    "default": False,
                    "disposition": "out of runtime scope",
                    "reason": (
                        "live physics, HVAC, fire behavior, or case lifecycle control; "
                        "not a passive P1R4 diagnostic"
                    ),
                }
            )
    return {
        "schema_version": 1,
        "source": ENGINE.relative_to(ROOT).as_posix(),
        "source_sha256": _sha256(ENGINE),
        "declaration_count": len(declared),
        "runtime_backed_count": len(RUNTIME_ACTIVATIONS),
        "out_of_runtime_scope_count": len(OUT_OF_RUNTIME_SCOPE),
        "parser_load_only_count": 0,
        "text_contract_only_count": 0,
        "dead_retire_count": 0,
        "records": records,
        "errors": errors,
        "pass": not errors,
    }


def run_runtime(godot: Path, log_dir: Path) -> list[dict]:
    log_dir.mkdir(parents=True, exist_ok=True)
    unique = sorted(set(RUNTIME_ACTIVATIONS.values()))
    results = []
    for fixture_rel, token in unique:
        fixture = ROOT / fixture_rel
        log = log_dir / (fixture.stem + ".log")
        started = time.perf_counter()
        completed = subprocess.run(
            [
                str(godot),
                "--headless",
                "--path",
                str(ROOT),
                "--log-file",
                str(log),
                "--script",
                f"res://{fixture_rel}",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=180,
            check=False,
        )
        wall_s = time.perf_counter() - started
        output = completed.stdout + completed.stderr
        markers = [marker for marker in FORBIDDEN_RUNTIME_MARKERS if marker in output]
        passed = completed.returncode == 0 and token in output and not markers
        results.append(
            {
                "fixture": fixture_rel,
                "success_token": token,
                "exit_code": completed.returncode,
                "wall_s": wall_s,
                "token_present": token in output,
                "forbidden_markers": markers,
                "log": log.relative_to(ROOT).as_posix(),
                "log_sha256": _sha256(log) if log.is_file() else None,
                "pass": passed,
                "output_tail": output[-2000:],
            }
        )
        print(f"{'PASS' if passed else 'FAIL'} {fixture_rel} {wall_s:.3f}s")
        if not passed:
            break
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", type=Path)
    parser.add_argument("--runtime", action="store_true")
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--log-dir", type=Path)
    args = parser.parse_args()

    report = static_audit()
    if args.runtime:
        if args.godot is None or not args.godot.is_file():
            report["errors"].append("--runtime requires an existing --godot path")
        else:
            log_dir = args.log_dir or ROOT / "runs/p1r4_flag_activation_logs"
            runtime = run_runtime(args.godot.resolve(), log_dir.resolve())
            report["runtime"] = runtime
            if len(runtime) != len(set(RUNTIME_ACTIVATIONS.values())) or any(
                not item["pass"] for item in runtime
            ):
                report["errors"].append("runtime fixture campaign incomplete or failed")
    report["pass"] = not report["errors"]
    rendered = json.dumps(report, indent=2, sort_keys=True)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
