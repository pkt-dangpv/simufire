import json
from pathlib import Path

from scripts.simulation import analyze_phase3_f33u_extended_stability as audit


def test_finite_zone_state_rejects_non_finite():
    row = {
        "phase3_shadow_upper_gas_kg": "1",
        "phase3_shadow_lower_gas_kg": "2",
        "phase3_shadow_thermo_temp_upper_c": "30",
        "phase3_shadow_thermo_temp_lower_c": "20",
        "phase3_shadow_thermo_interface_m": "1",
        "phase3_shadow_persistent_post_upper_o2_fraction": "0.2",
        "phase3_shadow_persistent_post_lower_o2_fraction": "nan",
    }
    assert not audit._finite_zone_state({10: row})


def test_zone_minima_excludes_initial_snapshot():
    rows = {
        0: {
            "phase3_shadow_upper_gas_kg": "0",
            "phase3_shadow_lower_gas_kg": "0",
            "phase3_shadow_persistent_post_upper_o2_fraction": "0",
            "phase3_shadow_persistent_post_lower_o2_fraction": "0",
        },
        10: {
            "phase3_shadow_upper_gas_kg": "2",
            "phase3_shadow_lower_gas_kg": "3",
            "phase3_shadow_persistent_post_upper_o2_fraction": "0.1",
            "phase3_shadow_persistent_post_lower_o2_fraction": "0.2",
        },
    }
    result = audit._zone_minima(rows)
    assert result["upper_gas_kg"] == 2.0
    assert result["lower_gas_kg"] == 3.0


def test_required_projection_uses_existing_expected_and_tolerance():
    rows = {
        180: {"phase3_shadow_thermo_temp_upper_c": "150"},
        300: {"phase3_shadow_thermo_temp_upper_c": "140"},
        600: {
            "phase3_shadow_thermo_temp_upper_c": "100",
            "phase3_shadow_persistent_post_upper_o2_fraction": "0.12",
        },
    }
    checks = {
        name: {"expected": 150, "tolerance": 20, "valid_gap": True}
        for name, _, _ in audit.REQUIRED_PROJECTIONS
    }
    checks["cfast_chain_r0_o2_t600_o2"] = {
        "expected": 0.10,
        "tolerance": 0.01,
        "valid_gap": True,
    }
    result = audit._required_projection(rows, checks)
    assert result["cfast_chain_r0_t180_temp_upper_c"]["pass"]
    assert not result["cfast_chain_r0_t600_temp_upper_c"]["pass"]
    assert not result["cfast_chain_r0_o2_t600_o2"]["pass"]


def test_late_hrr_owner_identifies_prethrottled_legacy_proposal():
    rows = {
        590: {
            "phase3_shadow_combustion_legacy_hrr_kw": "137",
            "phase3_shadow_combustion_accepted_hrr_kw": "137",
            "phase3_shadow_combustion_canonical_o2_hrr_factor": "0.69",
            "phase3_shadow_combustion_legacy_o2_hrr_factor": "0.44",
            "phase3_shadow_combustion_decision_fraction": "1",
        }
    }
    cfast = [{"Time": "590", "HRR_1": "300"}]
    result = audit._late_hrr_owner(rows, cfast)
    assert result["proposal_limited_upstream"]
    assert result["canonical_accepted_hrr_kw"] == 137.0


def test_read_reference_checks_indexes_by_name(tmp_path: Path):
    path = tmp_path / "checks.json"
    path.write_text(
        json.dumps({"checks": [{"name": "a"}, {"name": "b"}]}),
        encoding="utf-8",
    )
    assert list(audit._read_reference_checks(path)) == ["a", "b"]


def test_print_report_separates_stability_from_authority(capsys):
    report = {
        "horizons": {
            "590": {
                "all_metrics_improved": True,
                "ledger_pass": True,
                "max_residuals": {"mass": 1e-8},
            }
        },
        "prefix_determinism": {"on": True},
        "finite_zone_state": True,
        "positive_zone_inventory": True,
        "late_hrr_owner": {
            "legacy_proposal_hrr_kw": 137.0,
            "decision_fraction": 1.0,
            "cfast_hrr_kw": 300.0,
        },
        "required_projections": {
            "gap": {
                "pass": False,
                "actual": 1.0,
                "expected": 2.0,
                "tolerance": 0.5,
            }
        },
        "stability_gate_pass": True,
        "next_owner": "late canonical O2-to-HRR coupling",
    }
    audit.print_report(report)
    output = capsys.readouterr().out
    assert "stability gate: PASS" in output
    assert "runtime authority: NO-GO" in output
    assert "Group C retirement: NO-GO" in output
