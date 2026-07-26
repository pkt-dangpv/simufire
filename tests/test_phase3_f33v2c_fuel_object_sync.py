from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
FIXTURE = ROOT / "tests/fixtures/phase3_f33v2c_fuel_object_sync.gd"
GODOT = Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe")


def test_evaluator_is_dictionary_only_and_bounded():
    start = COMBUSTION.index("func evaluate_phase3_canonical_fuel_object_sync")
    end = COMBUSTION.index("\nfunc ", start + 10)
    body = COMBUSTION[start:end]
    assert "room." not in body
    assert "obj." not in body
    assert "remaining_fuel_MJ" in body
    assert "allocation_residual_MJ" in body
    assert "seen.has(object_id)" in body
    assert "entries.sort_custom" in body
    assert "leftover_MJ" in body


def test_direct_godot_fixture():
    if not GODOT.exists():
        return
    completed = subprocess.run(
        [
            str(GODOT),
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            str(FIXTURE),
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    output = completed.stdout + completed.stderr
    assert completed.returncode == 0, output
    assert "PHASE3_F33V2C_FUEL_OBJECT_SYNC_PASS" in output
