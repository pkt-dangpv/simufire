import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CASE_PATH = ROOT / "sim/validation/cases/cfast_corridor_chain.json"
CASE_RUNNER = (ROOT / "sim/validation/CaseRunner.gd").read_text(encoding="utf-8")
HEADLESS_RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(
    encoding="utf-8"
)


def _case() -> dict:
    return json.loads(CASE_PATH.read_text(encoding="utf-8"))


def _interior_overrides() -> dict[tuple[int, int], dict]:
    return {
        (int(entry["a"]), int(entry["b"])): entry
        for entry in _case()["opening_overrides"]
        if int(entry["b"]) >= 0
    }


def test_case_uses_template_direction_for_all_interior_overrides():
    overrides = _interior_overrides()
    assert set(overrides) == {(0, 1), (2, 1), (3, 1), (4, 1), (5, 1)}
    assert (1, 2) not in overrides
    assert (0, 4) not in overrides


def test_only_the_two_cfast_connections_are_open():
    overrides = _interior_overrides()
    assert overrides[(0, 1)]["open_fraction"] == 1.0
    assert overrides[(2, 1)]["open_fraction"] == 1.0
    assert overrides[(2, 1)]["width_m"] == 0.9
    for connection in ((3, 1), (4, 1), (5, 1)):
        assert overrides[connection]["open_fraction"] == 0.0


def test_case_writes_text_and_csv_reports_from_the_same_run():
    engine = _case()["engine_overrides"]
    assert engine["log_file_path"].endswith("/cfast_corridor_chain.log")
    assert engine["csv_log_file_path"].endswith("/cfast_corridor_chain.csv")


def test_both_runners_match_opening_overrides_by_exact_direction():
    case_block = CASE_RUNNER.split("func _apply_opening_overrides", 1)[1].split(
        "\nfunc ", 1
    )[0]
    headless_block = HEADLESS_RUNNER.split(
        "func _apply_opening_overrides", 1
    )[1].split("\nfunc ", 1)[0]
    for block in (case_block, headless_block):
        assert 'opening_data.get("a", -1)' in block
        assert 'opening_data.get("b", -1)' in block
        assert "a_id" in block
        assert "b_id" in block
