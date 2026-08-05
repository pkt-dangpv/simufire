"""Structural contracts for the H3.2-S0d4 zonal guard audit.

S0d4 is a NO-GO for shipping CO/CO2/HCN attribution. These contracts pin the
measurement that produced that verdict and pin the absence of the enrichment.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
LEDGER = (ROOT / "sim/core/Phase3PhysicalOwnerLedger.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_h32s0d3_species_attribution.gd"
).read_text(encoding="utf-8")

FLAG = "phase3_species_attribution_diagnostics_enabled"


def test_zonal_guard_is_measured_at_the_legacy_clamp():
    body = GAS.split("func step_smoke(", 1)[1].split("\nfunc ", 1)[0]
    assert body.count("_record_zonal_guard(") == 3
    for species in ("co", "co2", "hcn"):
        assert f'_record_zonal_guard("{species}", room.{species}_kg, room.{species}_upper_kg)' in body
    # Every guard call must precede the clamp it observes.
    assert body.index('_record_zonal_guard("co"') < body.index(
        "room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)"
    )


def test_zonal_guard_is_off_by_default_and_observes_only():
    body = GAS.split("func _record_zonal_guard(", 1)[1].split("\nfunc ", 1)[0]
    statements = [
        line.strip()
        for line in body.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    guard = next(line for line in statements if line.startswith("if "))
    assert guard == f"if not {FLAG}:"
    # It may only count. No repair, no attribution, no split.
    for forbidden in ("clampf(", "room.", "= maxf(0.0, upper", "share", "repair"):
        assert forbidden not in body
    assert "zonal_guard_upper_over_bulk_count" in body
    assert "zonal_guard_max_excess_kg" in body


def test_zonal_guard_counts_are_pure_counters():
    body = GAS.split("func _record_zonal_guard(", 1)[1].split("\nfunc ", 1)[0]
    assert "upper_kg > bulk_kg" in body
    assert "upper_kg < 0.0" in body
    # The guard must not derive a lower stock it would then have to defend.
    code = "\n".join(
        line for line in body.splitlines() if not line.strip().startswith(("#", "##"))
    )
    assert "lower" not in code


def test_species_attribution_is_still_measurement_only():
    # S0d4 ships no attribution: the ledger contract stays unextended.
    for forbidden in (
        "species_delta_kg",
        "counterparty_species_delta_kg",
        "attribution_complete",
        "aggregate_clamp_multi_owner",
    ):
        assert forbidden not in LEDGER, forbidden
    assert "species_delta_kg" not in GAS


def test_no_owner_event_carries_a_zonal_species_payload():
    recorder_calls = re.findall(
        r"_record_phase3_physical_owner_event\((.*?)\n\t*\)", GAS, re.S
    )
    joined = "\n".join(recorder_calls)
    for forbidden in ('"upper":', '"lower":', "species_delta_kg"):
        assert forbidden not in joined


def test_no_invented_distribution_anywhere_in_the_diagnostic():
    for func_name in (
        "_record_species_attribution(",
        "_record_species_attribution_o2(",
        "_record_zonal_guard(",
    ):
        body = GAS.split(f"func {func_name}", 1)[1].split("\nfunc ", 1)[0]
        for forbidden in ("proportional", "fifo", "priority", "weight", "split"):
            assert forbidden not in body.lower(), (func_name, forbidden)


def test_physics_paths_are_unchanged_by_the_audit():
    # S0d4 diagnoses the CO transport debit, it does not repair it: the legacy
    # statement must still be the unconditioned default. S0d5a later added the
    # symmetric upper debit, but only inside an explicit flag-gated branch.
    assert "co_delta_kg[from_id] -= co_moved_kg" in GAS
    assert "co2_upper_delta_kg[from_id] -= co2_upper_moved_kg" in GAS
    assert "hcn_upper_delta_kg[from_id] -= hcn_upper_moved_kg" in GAS
    repair = "co_upper_delta_kg[from_id] -= co_moved_kg"
    if repair in GAS:
        preceding = GAS.split(repair, 1)[0].rstrip().splitlines()[-1].strip()
        assert preceding == "if phase3_co_zonal_transport_consistency_enabled:"


def test_no_integrator_no_hvac_no_solver_no_csv():
    assert not (ROOT / "sim/core/Phase3PhysicalSourceIntegrator.gd").exists()
    for name in (
        "sim/core/Phase3CoupledPressureSolver.gd",
        "sim/core/HVACSystem.gd",
        "sim/core/SimulationLogWriter.gd",
        "sim/core/SimulationStateBuilder.gd",
    ):
        text = (ROOT / name).read_text(encoding="utf-8")
        assert "phase3_species_attribution" not in text
        assert "zonal_guard" not in text


def test_telemetry_never_governs_gas_physics():
    for line in GAS.splitlines():
        if re.search(r"\b(if|elif|while)\b", line) and FLAG in line:
            assert f"if not {FLAG}:" in line


def test_fixture_covers_the_zonal_guard():
    for label in (
        "three guard applications",
        "two upper-over-bulk violations",
        "max excess is the worst violation",
        "no negative upper stock",
        "guard never repairs",
        "guard never attributes",
        "zonal guard is silent when OFF",
    ):
        assert label in FIXTURE, label
