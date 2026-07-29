"""Contracts for the second real coupled-solver failure capture.

H2.5c patched the Jacobian to a centred difference using a 204-case synthetic
family perturbed from the single H2.5a capture. The family scored 95.6%; the
real `r0_window_360` scenario turned 1439 of 1441 steps into `iteration_cap`
and the patch was reverted. The family only ever contained one topology. This
capture versions the second one so that never happens silently again.
"""
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "tests" / "fixtures" / "data"
CORRIDOR = DATA / "coupled_solver_failure_corridor_chain.json"
R0 = DATA / "coupled_solver_failure_r0_window_360.json"
FIXTURE_PATH = (
    ROOT / "tests" / "fixtures"
    / "phase3_f33v3h25c_r0_window_solver_failure.gd"
)
FIXTURE = FIXTURE_PATH.read_text(encoding="utf-8")
SOLVER = (ROOT / "sim" / "core" / "Phase3CoupledPressureSolver.gd").read_text(
    encoding="utf-8"
)


def _decode(leaf) -> float:
    assert isinstance(leaf, dict) and "x" in leaf, leaf
    return struct.unpack("<d", bytes.fromhex(leaf["x"]))[0]


def _capture() -> dict:
    return json.loads(R0.read_text(encoding="utf-8"))


def _walk_leaves(node, path=""):
    if isinstance(node, dict):
        if "x" in node and "d" in node:
            yield path, node
            return
        for key, value in node.items():
            yield from _walk_leaves(value, f"{path}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from _walk_leaves(value, f"{path}[{index}]")


def test_capture_exists_and_shares_the_v1_schema():
    assert R0.exists(), "capture must be committed as test data"
    data = _capture()
    assert data["schema_version"] == "simufire_coupled_solver_failure_v1"
    # same schema as the first capture, so one replay path serves both
    assert json.loads(CORRIDOR.read_text(encoding="utf-8"))["schema_version"] \
        == data["schema_version"]


def test_capture_records_a_real_non_converged_solve():
    observed = _capture()["observed_failure"]
    assert observed["converged"] is False
    assert observed["limiting_reason"] == "damping_exhausted"
    assert _decode(observed["failure_code"]) > 0.0
    assert _decode(observed["iterations"]) >= 1.0


def test_every_numeric_leaf_is_bit_exact_and_readable():
    leaves = list(_walk_leaves(_capture()))
    assert leaves, "no encoded numeric leaves found"
    for path, leaf in leaves:
        assert len(leaf["x"]) == 16, f"{path}: not an 8-byte double"
        exact = _decode(leaf)
        readable = float(leaf["d"])
        scale = max(abs(exact), 1e-300)
        assert abs(exact - readable) / scale < 1e-8, path


def test_capture_carries_every_solver_input():
    data = _capture()["input"]
    for key in ("rooms", "openings", "sources", "dt", "reference_temp_c"):
        assert key in data, key
    assert _decode(data["dt"]) > 0.0
    for room in data["rooms"].values():
        for field in (
            "volume_m3", "floor_area_m2", "height_m",
            "upper_gas_kg", "lower_gas_kg", "upper_energy_kj", "lower_energy_kj",
        ):
            assert field in room, field
    for source in data["sources"].values():
        assert "mass_kg" in source and "energy_kj" in source


def test_topology_is_a_star_and_differs_from_the_corridor_capture():
    def busiest(path):
        data = json.loads(path.read_text(encoding="utf-8"))
        counts = {}
        for opening in data["input"]["openings"]:
            for room_id in (opening["room_a_id"], opening["room_b_id"]):
                counts[room_id] = counts.get(room_id, 0) + 1
        return max(counts.values()), len(data["input"]["openings"])

    r0_hub, r0_openings = busiest(R0)
    chain_hub, chain_openings = busiest(CORRIDOR)
    assert r0_openings == 4 and r0_hub == 4, "every r0 opening meets at one room"
    assert chain_hub < chain_openings or chain_openings <= 2, (
        "the corridor capture is a chain, not a star"
    )
    assert len(_capture()["input"]["rooms"]) == 5


def test_failure_mode_is_the_numerical_floor():
    """The reason this capture is worth keeping is that it fails differently.

    H2.5a stalls at 2.2e-4, far from the answer. This one reaches 1.147e-12
    against a 1.0e-12 tolerance and cannot take the last step, because that
    step is smaller than one ulp of the absolute-pressure iterate.
    """
    history = [_decode(x) for x in _capture()["observed_failure"]["residual_history"]]
    assert len(history) >= 2
    final = history[-1]
    assert 1.0e-12 < final < 1.0e-11, final
    assert history[0] / final > 1.0e8, "the solve got close before stalling"
    # one ulp near ambient pressure is coarser than the residual it still owes
    assert math.ulp(101325.0) > 1.0e-11


def test_the_two_captures_record_different_failure_modes():
    corridor = json.loads(CORRIDOR.read_text(encoding="utf-8"))["observed_failure"]
    r0 = _capture()["observed_failure"]
    corridor_final = _decode(corridor["residual_history"][-1])
    r0_final = _decode(r0["residual_history"][-1])
    # both are damping_exhausted, but at opposite ends of the residual scale;
    # a fix that only addresses one of them is not a fix
    assert corridor_final / r0_final > 1.0e6, (
        f"captures are not distinct: {corridor_final} vs {r0_final}"
    )


def test_fixture_replays_without_running_a_scenario():
    assert "PHASE3_F33V3H25C_R0_WINDOW_SOLVER_FAILURE_PASS" in FIXTURE
    for absent in ("SimulationEngine", "BuildingModel", "run_scenario"):
        assert absent not in FIXTURE, absent
    assert "Phase3CoupledPressureSolver.gd" in FIXTURE


def test_fixture_was_flipped_with_intent_when_h25e_fixed_it():
    # H2.5e moved the solve to gauge coordinates and this capture now converges.
    # The flip must be explained in the fixture, not silently applied.
    assert 'bool(result["converged"]),' in FIXTURE
    assert 'not bool(result["converged"]),' not in FIXTURE
    assert "F3.3v3h2.5e" in FIXTURE
    assert "quit(1)\n\t\treturn" in FIXTURE


def test_fixture_still_guards_the_original_failure_record():
    # the capture keeps recording what absolute coordinates did, so a regression
    # back to them is detectable rather than quietly re-baselined
    assert 'String(observed.get("limiting_reason", "")) == "damping_exhausted"' \
        in FIXTURE


def test_fixture_decodes_the_exact_bit_pattern_not_the_readable_decimal():
    body = FIXTURE.split("func _decode(", 1)[1].split("\nfunc ", 1)[0]
    assert "decode_double(0)" in body
    assert 'leaf.has("x")' in body


def test_fixture_does_not_claim_the_reverted_period_two_cycle():
    """The limit cycle belonged to the centred-difference candidate.

    That candidate was reverted, so nothing in the repository can reproduce the
    cycle. The fixture must not imply otherwise.
    """
    assert "period-2" in FIXTURE or "period-2 limit cycle" in FIXTURE, (
        "the fixture should explain what it is NOT reproducing"
    )
    assert 'String(observed.get("limiting_reason", "")) == "damping_exhausted"' \
        in FIXTURE


def test_h25c_central_difference_is_still_rejected():
    # H2.5c measured centred differences NO-GO and reverted them. H2.5e changed
    # the coordinates, not the quotient: the Jacobian must still be one-sided.
    assert ") / jacobian_step_pa" in SOLVER, "forward quotient must be intact"
    assert "/ (2.0 * jacobian_step_pa)" not in SOLVER
    assert '- float(evaluation["residual"][row_index])' in SOLVER
    # H2.5g added LM_RESCUE_ARMIJO_C, a documented global constant for the
    # fail-only recovery's sufficient-decrease test. What must stay absent is a
    # selectable Jacobian mode, which is what H2.5c was.
    for forbidden in ("jacobian_mode", "central_difference"):
        assert forbidden not in SOLVER.lower(), forbidden
