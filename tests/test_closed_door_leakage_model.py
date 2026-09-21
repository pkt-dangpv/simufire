"""Pure closed-door leakage model: runtime and closed-consumer contracts.

The pure model is exercised with imposed pressure differences. D1 and D2 now
consume it through their declared pressure-network adapters; any undeclared
consumer remains a test failure.
"""

from __future__ import annotations

import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "sim" / "core" / "ClosedDoorLeakageModel.gd"
VALIDATOR = "res://tools/validate_closed_door_leakage_model.gd"
PASS_TOKEN = "CLOSED DOOR LEAKAGE MODEL VALIDATION PASS"
MODEL_SOURCE = MODEL.read_text(encoding="utf-8")

GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)

# Exact files allowed to mention the model. This stays fail-closed: each new
# consumer must be classified here deliberately.
ALLOWED_REFERENCES = {
    Path("sim/core/ClosedDoorLeakageModel.gd"),
    Path("tools/validate_closed_door_leakage_model.gd"),
    # Registers the isolated validator among the product checks.
    Path("scripts/check_product.py"),
    # Phase 2: the pure deformation model names the leakage model only in its
    # documentation (its own test forbids loading it), and its validator feeds
    # the combined segments to the leakage solver. Neither is engine code.
    Path("sim/core/ClosedDoorDeformationModel.gd"),
    Path("tools/validate_closed_door_deformation_model.gd"),
    # F2.2D1 (2026-09-18): la fuga fria SI esta integrada, en la red
    # autoritativa de presion. Estos son sus unicos consumidores, y la prueba
    # sigue fallando si aparece cualquier otro.
    Path("sim/core/ClosedDoorLeakageNetworkAdapter.gd"),
    Path("sim/core/Phase3CoupledPressureSolver.gd"),
    Path("sim/core/PressureNetworkTransportSystem.gd"),
    Path("sim/core/SimulationEngine.gd"),
    Path("sim/BuildingModel.gd"),
    Path("editor/ScenarioSerializer.gd"),
    Path("tools/validate_closed_door_leakage_network.gd"),
    # F2.2D2 (2026-09-20): prescribed deformation combines its additional ELA
    # with the cold segments, then delegates to this same canonical crack law.
    Path("sim/core/ClosedDoorDeformationNetworkAdapter.gd"),
    Path("tools/validate_closed_door_deformation_network.gd"),
    # F2.2D3 (2026-09-21): su validador enciende D1 junto al vidrio para
    # demostrar que ambas rutas coexisten sin sustituirse ni duplicarse. No es
    # un consumidor nuevo del motor; la referencia queda limitada al fixture.
    Path("tools/validate_glazing_fallout_network.gd"),
    # La carpinteria declara su clase, y su comentario nombra la tabla canonica.
    Path("sim/building/OpeningModel.gd"),
    # El auditor clasifica el interruptor `closed_door_leakage_enabled`.
    Path("scripts/simulation/audit_default_off_flags.py"),
    # F2.2-R2-MASS: R2-M11 comprueba QUE parametros emite el adaptador, porque
    # los checks de D1 comparan contra las constantes del modelo puro y por eso
    # no veian un adaptador que emitiera otro exponente.
    Path("tools/validate_canonical_mass_conservation.gd"),
    Path("tools/validate_canonical_mass_conservation.gd.uid"),
}


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def _run_validator(dump_path: Path | None = None):
    godot = _godot_exe()
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")
    command = [str(godot), "--headless", "--path", str(ROOT), "--script", VALIDATOR]
    if dump_path is not None:
        command += ["--", f"--dump={dump_path}"]
    return run_godot(command, timeout_s=300, allowed_exit_codes=(0,))


def test_model_is_pure_and_not_globally_registered():
    assert MODEL_SOURCE.startswith("extends RefCounted\n")
    # No global class registration until the integration phase.
    assert "class_name" not in MODEL_SOURCE
    for forbidden in (
        "@export",
        "get_tree",
        "Node",
        "BuildingModel",
        "RoomModel",
        "OpeningModel",
        "ScenarioSerializer",
        "FileAccess",
        "OS.",
        "randf",
        "randi",
        "Time.",
    ):
        assert forbidden not in MODEL_SOURCE, forbidden
    # Only static functions and constants: no instance state.
    assert re.search(r"^var ", MODEL_SOURCE, re.MULTILINE) is None
    assert re.search(r"^func ", MODEL_SOURCE, re.MULTILINE) is None
    # The operative door state is never written.
    assert re.search(r"open_fraction\s*=", MODEL_SOURCE) is None


def _static_function(name: str) -> str:
    return MODEL_SOURCE.split(f"static func {name}(", 1)[1].split("\nstatic func ", 1)[0]


def test_ela_convention_is_4_pa_with_unit_discharge_coefficient():
    # ELA at 4 Pa with Cd = 1.0 (NIST TN 1887r1, eq. 28-29): no discharge
    # coefficient in the API or the formula, so it cannot be applied twice.
    required = MODEL_SOURCE.split("const REQUIRED_PARAMS", 1)[1].split("\n]", 1)[0]
    for key in (
        "ela_reference_pressure_pa",
        "flow_exponent",
        "zero_pressure_regularization_pa",
        "pressure_domain_max_pa",
    ):
        assert f'"{key}"' in required, key
    assert "discharge" not in required
    forbidden = MODEL_SOURCE.split("const FORBIDDEN_PARAMS", 1)[1].split("\n]", 1)[0]
    for key in ("discharge_coefficient", "reference_pressure_pa", "linear_regime_pressure_pa"):
        assert f'"{key}"' in forbidden, key

    flow = _static_function("crack_volume_flow_m3_s")
    assert "discharge" not in flow
    assert "var reference_flow_m3_s: float = area_m2 * sqrt(2.0 * reference_pa / rho_source_kg_m3)" in flow
    assert "pow(abs_dp_pa / reference_pa, exponent)" in flow
    compute = _static_function("compute_flows")
    assert "discharge" not in compute
    assert "NIST_ELA_REFERENCE_PRESSURE_PA: float = 4.0" in MODEL_SOURCE
    validate = _static_function("_validate_params")
    assert 'float(params["ela_reference_pressure_pa"]) != NIST_ELA_REFERENCE_PRESSURE_PA' in validate
    assert '"entry_tight": 0.0012' in MODEL_SOURCE
    assert '"interior_tight": 0.0021' in MODEL_SOURCE
    assert "C_d = 1,0" in MODEL_SOURCE


def test_exponent_and_regularization_have_no_hidden_default():
    assert "const PROVISIONAL_FLOW_EXPONENT_CANDIDATE: float = 0.65" in MODEL_SOURCE
    # The provisional candidate is informative only.
    body = MODEL_SOURCE.split("const FORBIDDEN_PARAMS", 1)[1]
    assert "PROVISIONAL_FLOW_EXPONENT_CANDIDATE" not in body
    assert 'params.get("flow_exponent"' not in MODEL_SOURCE
    assert 'params.get("zero_pressure_regularization_pa"' not in MODEL_SOURCE
    # The old physical-sounding name survives only as a rejected key.
    assert MODEL_SOURCE.count("linear_regime_pressure_pa") == 1
    assert "laminar" not in MODEL_SOURCE.lower()


def test_solver_describes_the_crossing_without_deciding_deposition():
    compute = _static_function("compute_flows")
    for key in (
        "source_side",
        "source_zone",
        "source_density_kg_m3",
        "destination_side",
        "destination_zone_at_height",
        "destination_density_at_height",
        "z_m",
        "direction",
        "dp_pa",
        "volume_flow_m3_s",
        "mass_flow_kg_s",
        "mass_step_kg",
    ):
        assert f'"{key}"' in compute, key
    assert '"destination_zone"' not in MODEL_SOURCE
    assert 'flow["destination_zone_at_height"] = zone_at(destination, z_m)' in compute
    assert 'flow["destination_density_at_height"] = density_at(destination, z_m)' in compute
    # No buoyancy decision comparing source and receiver densities.
    assert "rho_source <" not in MODEL_SOURCE
    assert "rho_source >" not in MODEL_SOURCE


def test_the_model_has_only_its_declared_consumers():
    """Hasta F2.2D1 esta prueba exigia que NADIE cargara el modelo. Ahora la
    fuga fria esta integrada, asi que lo que se vigila es que la lista de
    consumidores sea exactamente la declarada: cualquier ruta nueva que se
    cuelgue del modelo sin pasar por aqui hace fallar la prueba."""
    offenders = []
    for folder in ("sim", "editor", "view", "tools", "scripts", "scenes", "ui"):
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.suffix not in {".gd", ".tscn", ".tres", ".py", ".json"}:
                continue
            relative = path.relative_to(ROOT)
            if relative in ALLOWED_REFERENCES:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            if "ClosedDoorLeakageModel" in text or "closed_door_leakage" in text:
                offenders.append(str(relative))
    assert offenders == []


def test_validator_passes_and_dump_is_byte_identical(tmp_path):
    first = tmp_path / "dump_first.json"
    second = tmp_path / "dump_second.json"
    completed_first = _run_validator(first)
    completed_second = _run_validator(second)
    for completed in (completed_first, completed_second):
        output = (completed.stdout or "") + (completed.stderr or "")
        assert PASS_TOKEN in output
        assert "SCRIPT ERROR" not in output
        assert "Parse Error" not in output
    assert first.read_bytes() == second.read_bytes()
    assert len(first.read_bytes()) > 1000
