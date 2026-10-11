"""The independent fuel / O2 / products book (design section 14) on synthetic ledgers.

Every test starts from a step that closes in energy, oxygen and carbon with the
engine's own constants, changes one term on purpose, and expects the finding
that names it. No Godot and no run directory is needed.
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "simulation"))

import analyze_g3_fuel_o2_products_balance as book  # noqa: E402


# A soot yield that, with the base CO2 yield, carries exactly the carbon of the fuel.
CLOSING_SMOKE_KG_PER_MJ = (
    book.FUEL_C_KG_PER_MJ - book.CO2_YIELD_MAX_KG_PER_MJ * book.C_IN_CO2
) / book.SOOT_CARBON_FRACTION


def ledgers(
    *, time_s: float = 1.0, dt: float = 0.1, fire: bool = True,
    pyrolysis_kw: float = 100.0, flame_kw: float = 100.0, smolder_kw: float = 0.0,
    solid_kw: float = 100.0, pool_burn_kw: float = 0.0, pool_before: float = 0.0,
    option_d: bool = False, **override,
) -> tuple[dict, dict]:
    """Ledger v3 and v2 rows of one step that closes, unless ``override`` changes a term."""
    mj = dt / 1000.0
    consumed = pyrolysis_kw * mj
    target = (flame_kw + smolder_kw) * mj
    generation = book.UNBURNED_GENERATION_FRACTION * max(0.0, consumed - target) if flame_kw > 0.0 else 0.0
    heat = (solid_kw + pool_burn_kw) * mj
    after_burn = pool_before + generation - pool_burn_kw * mj
    pool_after = after_burn * (1.0 - book.POOL_DECAY_PER_S * 2.0 * dt)
    v3 = {
        "schema_version": "g3_fuel_ledger_v3", "room_id": 0, "time_s": time_s, "dt_s": dt,
        "fire_present_before": fire, "ownership_mode": "explicit_owned",
        "consumed_MJ": consumed, "pyrolysis_kw": pyrolysis_kw,
        "flame_target_kw": flame_kw, "smolder_target_kw": smolder_kw,
        "actual_solid_burn_kw": solid_kw, "actual_pool_burn_kw": pool_burn_kw,
        "pool_generation_MJ": generation, "pool_before_MJ": pool_before, "pool_after_MJ": pool_after,
        "species": {
            "co_kg": 0.0, "co2_kg": book.CO2_YIELD_MAX_KG_PER_MJ * heat, "hcn_kg": 0.0,
            "smoke_kg": CLOSING_SMOKE_KG_PER_MJ * heat,
        },
        "objects": [
            {"id": "sofa", "is_proxy": False, "remaining_before_MJ": 50.0, "remaining_after_MJ": 50.0 - consumed},
            {"id": "proxy", "is_proxy": True, "remaining_before_MJ": 9.0, "remaining_after_MJ": 1.0},
        ],
    }
    if option_d:
        lag = target - solid_kw * mj
        v3["optd"] = {"objects": {"sofa": {"acc_MJ": max(lag, 0.0), "rel_MJ": max(-lag, 0.0)}}}
    v2 = {
        "schema_version": "g3_fuel_source_step_v2", "room_id": 0, "time_s": time_s,
        "room_o2_consumed_fire_kg_total_delta": book.O2_KG_PER_MJ * heat,
        "room_o2_consumed_kg_total_all_delta": book.O2_KG_PER_MJ * heat,
        "room_o2_exterior_net_kg_total_delta": 0.0,
    }
    for key, value in override.items():
        target_row = v2 if key in v2 else v3
        if key in ("co_kg", "co2_kg", "hcn_kg", "smoke_kg"):
            v3["species"][key] = value
        else:
            assert key in target_row, key
            target_row[key] = value
    return v3, v2


def codes(*steps: tuple[dict, dict]) -> set[str]:
    summary = book.summarize(book.book_step(v3, v2) for v3, v2 in steps)
    return {finding["code"].split("_")[0] for finding in summary["findings"]}


def test_a_step_that_closes_has_no_findings():
    summary = book.summarize([book.book_step(*ledgers())] * 20)
    assert summary["findings"] == []
    energy = summary["energy_MJ"]
    assert energy["C_debited"] == pytest.approx(0.2) and energy["B_solid"] == pytest.approx(0.2)
    assert energy["U_unowned"] == pytest.approx(0.0, abs=1e-12)
    assert summary["o2_kg"]["fire_debit"] == pytest.approx(0.076 * 0.2)
    assert summary["carbon_kg"]["untracked"] == pytest.approx(0.0, abs=1e-12)
    assert summary["carbon_kg"]["debited_with_fuel"] == pytest.approx(0.027 * 0.2)


def test_option_d_lag_and_release_close_without_findings_of_energy():
    rise = ledgers(solid_kw=60.0, option_d=True)       # R accrues 0.004 MJ
    fall = ledgers(solid_kw=140.0, option_d=True)      # and is released
    summary = book.summarize(book.book_step(*item) for item in (rise, fall))
    assert summary["has_R"] is True
    assert summary["energy_MJ"]["R_accrued"] == pytest.approx(0.004)
    assert summary["energy_MJ"]["R_released"] == pytest.approx(0.004)
    assert summary["energy_MJ"]["R_final"] == pytest.approx(0.0, abs=1e-12)
    found = {finding["code"].split("_")[0] for finding in summary["findings"]}
    assert not found & {"E0", "E1", "E2", "E3", "E4", "E5", "E6", "E8", "E9"}
    # The species of the closing step follow the heat; the target above it is still reported.
    assert "S1" in found


@pytest.mark.parametrize(
    ("change", "expected"),
    [
        ({"consumed_MJ": 0.012}, "E1"),                                   # fuel debited is not pyrolysis x dt
        ({"solid_kw": 60.0, "option_d": True, "optd": {"objects": {"sofa": {"acc_MJ": 0.001, "rel_MJ": 0.0}}}}, "E2"),
        ({"solid_kw": 60.0}, "E3"),                                       # heat below target, no balance
        ({"solid_kw": 140.0}, "E4"),                                      # heat above target, no balance
        ({"pyrolysis_kw": 150.0}, "E5"),                                  # pyrolysate with no owner
        ({"pool_generation_MJ": 0.02}, "E6"),                             # target + G above the fuel debited
        ({"fire": False}, "E7"),                                          # heat without a fire
        ({"pyrolysis_kw": 150.0, "pool_generation_MJ": 0.0005}, "E9"),    # pool generation off its rule
        ({"pool_before": 2.0, "pool_after_MJ": 1.9}, "P2"),               # lost more than decay allows
        ({"pool_before": 2.0, "pool_after_MJ": 2.0}, "P3"),               # lost less than decay requires
        ({"pool_before": 2.0, "pool_after_MJ": 2.1}, "P4"),               # grew without a source
        ({"pool_before": 2.0}, "P1"),                                     # decay has no destination
        ({"room_o2_consumed_fire_kg_total_delta": 0.0005}, "O0"),         # O2 debit truncated
        ({"room_o2_consumed_kg_total_all_delta": 0.0015}, "O1"),          # sinks beyond the fire
        ({"co2_kg": 0.0831 * 0.01 * 1.5}, "O2"),                          # more oxygen in products than debited
        ({"co2_kg": 0.0831 * 0.01 * 0.5}, "C0"),                          # carbon in no species
        ({"smoke_kg": 0.02 * 0.01}, "C1"),                                # carbon created
        ({"co2_kg": 0.0831 * 0.01 * 1.3}, "C2"),                          # gas carbon above the fuel burned
        ({"co2_kg": 0.0831 * 0.01 * 1.01}, "S0"),                         # CO2 above its yield on the heat
        ({"solid_kw": 60.0, "option_d": True}, "S1"),                     # species basis without heat
    ],
)
def test_changing_one_term_raises_the_finding_that_names_it(change, expected):
    assert expected not in codes(ledgers())
    assert expected in codes(ledgers(**change))


def test_objects_debited_differently_from_the_room_are_found():
    v3, v2 = ledgers()
    v3["objects"][0]["remaining_after_MJ"] = 50.0 - 0.004
    assert "E8" in codes((v3, v2))
    v3["ownership_mode"] = "legacy_lumped"       # no per-object ownership: nothing to compare
    assert "E8" not in codes((v3, v2))


def test_a_route_left_out_of_the_book_breaks_the_accounting_closure():
    step = book.book_step(*ledgers(pyrolysis_kw=150.0))
    assert "E0_accounting_closure" not in {f["code"] for f in book.summarize([step])["findings"]}
    without_pool_route = dict(step, G_MJ=0.0)     # the book forgets the fuel sent to the pool
    found = {f["code"] for f in book.summarize([without_pool_route])["findings"]}
    assert "E0_accounting_closure" in found


def test_pool_burn_is_a_route_of_heat_oxygen_and_carbon():
    burning = ledgers(pool_before=2.0, pool_burn_kw=20.0)
    summary = book.summarize([book.book_step(*burning)])
    assert summary["energy_MJ"]["B_pool"] == pytest.approx(0.002)
    assert summary["pool_MJ"]["burned"] == pytest.approx(0.002)
    assert summary["o2_kg"]["thornton_for_heat"] == pytest.approx(0.076 * 0.012)
    assert summary["carbon_kg"]["of_fuel_that_burned"] == pytest.approx(0.027 * 0.012)
    assert "O0" not in {f["code"].split("_")[0] for f in summary["findings"]}
    # Heat from the pool whose oxygen was not debited is found.
    solid_only = book.O2_KG_PER_MJ * 0.01
    assert "O0" in codes(ledgers(pool_before=2.0, pool_burn_kw=20.0,
                                 room_o2_consumed_fire_kg_total_delta=solid_only))


def test_pool_inventory_follows_generation_burn_and_decay():
    generating = book.book_step(*ledgers(pyrolysis_kw=150.0, pool_before=1.0))
    summary = book.summarize([generating])
    pool = summary["pool_MJ"]
    credited = 0.3 * 0.005
    assert pool["credited_G"] == pytest.approx(credited)
    assert pool["other_loss"] == pytest.approx((1.0 + credited) * book.POOL_DECAY_PER_S * 2.0 * 0.1)
    assert pool["end"] == pytest.approx(1.0 + credited - pool["other_loss"])
    assert pool["closure_start_plus_G_minus_burn_minus_loss_minus_end"] == pytest.approx(0.0, abs=1e-12)
    found = {finding["code"].split("_")[0] for finding in summary["findings"]}
    assert "P1" in found and not found & {"P0", "P2", "P3", "P4"}


def test_unowned_pyrolysate_is_split_by_flame_state_and_never_hidden():
    flaming = book.book_step(*ledgers(pyrolysis_kw=150.0))
    latent = book.book_step(*ledgers(pyrolysis_kw=150.0, flame_kw=0.0, smolder_kw=5.0, solid_kw=5.0))
    summary = book.summarize([flaming, latent])
    energy = summary["energy_MJ"]
    assert energy["U_while_flaming"] == pytest.approx(0.7 * 0.005)
    assert energy["U_while_not_flaming"] == pytest.approx(0.0145)   # nothing goes to the pool without a flame
    assert energy["U_unowned"] == pytest.approx(energy["U_while_flaming"] + energy["U_while_not_flaming"])
    owner = next(f for f in summary["findings"] if f["code"] == "E5_U_has_no_owner")
    assert owner["owner"] == "none" and owner["amount"] == pytest.approx(energy["U_unowned"])
    assert summary["carbon_kg"]["of_U"] == pytest.approx(0.027 * energy["U_unowned"])


def test_every_finding_carries_an_owner_amount_and_unit():
    summary = book.summarize([book.book_step(*ledgers(
        pyrolysis_kw=150.0, solid_kw=60.0, pool_before=2.0, co2_kg=0.002,
        room_o2_consumed_kg_total_all_delta=0.002))])
    assert len(summary["findings"]) >= 5
    for finding in summary["findings"]:
        assert set(finding) == {"code", "amount", "unit", "owner", "text"}
        assert finding["owner"] and finding["unit"] and "loss" not in finding["owner"].lower()


def _write_case(directory: Path, steps: list[tuple[dict, dict]]) -> Path:
    directory.mkdir(parents=True)
    with (directory / "g3_fuel_ledger_v3.jsonl").open("w", encoding="utf-8") as v3_file, \
            (directory / "fuel_source_ledger.jsonl").open("w", encoding="utf-8") as v2_file:
        for v3, v2 in steps:
            for room in (0, 1):                       # another room is interleaved and ignored
                v3_file.write(json.dumps(dict(v3, room_id=room)) + "\n")
                v2_file.write(json.dumps(dict(v2, room_id=room)) + "\n")
    (directory / "scenario.json").write_text(json.dumps({"engine_overrides": {"x": 1}}), encoding="utf-8")
    columns = ["time_s", "room_id", "co2_upper_ppm", "co2_upper_ppm_mass", "fuel_consumed_MJ_total", "hrr_kj_total",
               "retained_unburned_MJ", "co_generated_kg_total", "o2_consumed_fire_kg_total",
               "o2_consumed_kg_total_all", "smoke_generated_kg_total", "smoke_vented_kg_total",
               "smoke_deposited_kg_total", "co_exterior_removed_kg_total", "co_kg", "smoke_kg",
               "c_balance_frac", "carbon_conservation_error_kg"]
    with (directory / "sim_log.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(columns)
        writer.writerow([1.0, 0, 900.0, 400.0] + [0.0] * (len(columns) - 4))
        writer.writerow([1.0, 1, 50.0, 50.0] + [0.0] * (len(columns) - 4))
        writer.writerow([2.0, 0, 500.0, 2500.0] + [0.0] * (len(columns) - 4))
    return directory


def test_analyze_case_streams_room_zero_and_writes_the_step_book(tmp_path):
    steps = [ledgers(time_s=1.0, pyrolysis_kw=150.0), ledgers(time_s=1.1)]
    case = _write_case(tmp_path / "case", steps)
    report = book.analyze_case(case, tmp_path / "out" / "steps.csv")
    assert report["counts"]["steps"] == 2
    assert report["energy_MJ"]["C_debited"] == pytest.approx(0.025)
    assert report["engine_overrides"] == {"x": 1}
    two = report["co2_two_representations_ppm"]
    assert two["peak_upper_tracer_from_OES"] == 900.0 and two["peak_upper_from_mass_CombustionSystem"] == 2500.0
    assert two["largest_gap"] == {"time_s": 2.0, "tracer": 500.0, "from_mass": 2500.0, "gap": -2000.0}
    with (tmp_path / "out" / "steps.csv").open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    assert [float(row["time_s"]) for row in rows] == [1.0, 1.1]
    assert tuple(rows[0]) == book.STEP_FIELDS
    assert float(rows[0]["U_MJ"]) == pytest.approx(0.7 * 0.005)


def test_analyze_case_refuses_ledgers_that_do_not_match(tmp_path):
    shifted = ledgers(time_s=1.0)
    shifted[1]["time_s"] = 1.5
    with pytest.raises(ValueError, match="out of step"):
        book.analyze_case(_write_case(tmp_path / "shifted", [shifted]))

    case = _write_case(tmp_path / "short", [ledgers(time_s=1.0), ledgers(time_s=1.1)])
    lines = (case / "fuel_source_ledger.jsonl").read_text(encoding="utf-8").splitlines()
    (case / "fuel_source_ledger.jsonl").write_text("\n".join(lines[:2]) + "\n", encoding="utf-8")
    with pytest.raises(ValueError):
        book.analyze_case(case)

    wrong = _write_case(tmp_path / "schema", [ledgers()])
    text = (wrong / "g3_fuel_ledger_v3.jsonl").read_text(encoding="utf-8").replace("g3_fuel_ledger_v3", "other")
    (wrong / "g3_fuel_ledger_v3.jsonl").write_text(text, encoding="utf-8")
    with pytest.raises(ValueError, match="schema mismatch"):
        book.analyze_case(wrong)
