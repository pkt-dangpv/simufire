"""F2.2D4A: persistent contract for prescribed door and glazing physics."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "sim/building/PrescribedOpeningPhysicsSchema.gd"
SCHEMA = SCHEMA_PATH.read_text(encoding="utf-8")
SERIALIZER = (ROOT / "editor/ScenarioSerializer.gd").read_text(encoding="utf-8")
BUILDING = (ROOT / "sim/BuildingModel.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
TRANSPORT = (ROOT / "sim/core/PressureNetworkTransportSystem.gd").read_text(encoding="utf-8")
OPENING = (ROOT / "sim/building/OpeningModel.gd").read_text(encoding="utf-8")
VALIDATOR = ROOT / "tools/validate_prescribed_physics_persistence.gd"

PASS_TOKEN = "PRESCRIBED PHYSICS PERSISTENCE VALIDATION PASS"
SCHEMA_KEY = "prescribed_physics_schema"
PAYLOAD_KEYS = ("deformation_tracks", "glazing_panels", "glazing_spatial")
LIVE_FLAGS = (
    "closed_door_leakage_enabled",
    "closed_door_deformation_enabled",
    "glazing_fallout_enabled",
    "exterior_envelope_leakage_enabled",
    "pressure_network_solver_enabled",
)
GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)


def _code_only(source: str) -> str:
    return "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def _scenario_files() -> list[Path]:
    return sorted(ROOT.glob("scenarios/*.json")) + sorted(
        ROOT.glob("tests/fixtures/*.json")
    )


# ------------------------------------------------------------
# Contrato del esquema
# ------------------------------------------------------------


def test_schema_declares_one_version_and_one_owner():
    # F2.2D4B1 subio el esquema a 2 para los perfiles del catalogo. El 1 de D4A
    # sigue siendo valido y es el minimo admitido: un escenario sin perfiles se
    # guarda como 1 y no gana ninguna clave.
    assert "const SCHEMA_VERSION: int = 3" in SCHEMA
    assert "const MIN_SCHEMA_VERSION: int = 1" in SCHEMA
    assert f'const SCHEMA_KEY: String = "{SCHEMA_KEY}"' in SCHEMA
    for key in PAYLOAD_KEYS:
        assert f'"{key}"' in SCHEMA
    # Un solo propietario del esquema: nadie mas define la clave de version.
    owners = [
        path
        for path in ROOT.rglob("*.gd")
        if "runs" not in path.parts
        and f'String = "{SCHEMA_KEY}"' in path.read_text(encoding="utf-8")
    ]
    assert owners == [SCHEMA_PATH]


def test_schema_reuses_the_pure_models_and_owns_no_physics():
    code = _code_only(SCHEMA)
    # Delega: integridad, geometria multicapa y seleccion temporal viven en D3;
    # las pistas, en el modelo puro de D2.
    assert 'preload("res://sim/core/ClosedDoorDeformationModel.gd")' in SCHEMA
    assert 'preload("res://sim/core/GlazingFalloutNetworkAdapter.gd")' in SCHEMA
    assert "DeformationModel.validate_tracks(" in code
    assert "GlazingAdapter.build_opening_elements(" in code
    # No reimplementa ninguna ley ni ningun transporte.
    for forbidden in (
        "sqrt(",
        "pow(",
        "compute_flows",
        "compute_segment_flow_from_dp",
        "build_door_segments",
        "compute_open_geometry",
        "evaluate_panels",
        "mass_flow",
        "volume_flow",
        "wind_dp",
        "discharge_coeff",
        "thermal_gap_fraction",
    ):
        assert forbidden not in code, forbidden
    # No toca el estado operativo.
    assert "open_fraction =" not in code


def test_persistence_never_writes_a_switch():
    code = _code_only(SCHEMA)
    for flag in LIVE_FLAGS:
        assert flag not in code
        assert flag not in _code_only(SERIALIZER)
    # Los cinco siguen naciendo apagados en el motor.
    for flag in LIVE_FLAGS:
        assert re.findall(rf"^@export var {flag}: bool = (\w+)$", ENGINE, re.M) == [
            "false"
        ]


def test_the_schema_is_wired_into_both_owners_exactly_once():
    assert BUILDING.count("PrescribedPhysicsSchemaScript.validate(") == 1
    assert BUILDING.count("PrescribedPhysicsSchemaScript.apply_to_opening(") == 1
    assert SERIALIZER.count("PrescribedPhysicsSchema.normalize(opening)") == 1
    assert SERIALIZER.count("PrescribedPhysicsSchema.validate(op, i)") == 1


def test_consumer_list_stays_closed():
    consumers = sorted(
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*.gd")
        if "runs" not in path.parts
        and "PrescribedOpeningPhysicsSchema.gd" in path.read_text(encoding="utf-8")
    )
    # El propio modulo no se nombra a si mismo: la lista son sus consumidores.
    # F2.2D4B1 anade UNO deliberado: el validador del catalogo comprueba que un
    # perfil se congela en el escenario y que un perfil bloqueado o manipulado
    # se rechaza, y eso solo se puede comprobar a traves de este esquema.
    # F2.2D4B2A anade otros dos: el controlador con el que el editor configura
    # una abertura -que le pide al esquema que normalice y valide cada borrador-
    # y su validador.
    assert consumers == [
        "editor/OpeningPhysicsEditor.gd",
        "editor/ScenarioSerializer.gd",
        "sim/BuildingModel.gd",
        # F2.2D4B2B: el contrato de autorizacion le DELEGA entera la validez
        # de cada perfil en vez de reimplementarla, y su validador la usa.
        "sim/building/ExperimentalRunAuthorization.gd",
        "tools/validate_experimental_physics_activation.gd",
        "tools/validate_opening_physics_profiles.gd",
        "tools/validate_opening_profile_editor.gd",
        "tools/validate_prescribed_physics_persistence.gd",
    ], consumers


# ------------------------------------------------------------
# D1, D2 y D3 intactas
# ------------------------------------------------------------


def test_d1_d2_d3_consumption_is_unchanged():
    # El unico lector de las declaraciones sigue siendo el transporte, y sigue
    # estando detras de su interruptor. D4A no ha abierto una segunda puerta.
    assert (
        "if glazing_fallout_enabled and GlazingAdapterScript.has_declaration(opening):"
        in TRANSPORT
    )
    assert (
        "if closed_door_deformation_enabled \\\n\t\t\t\t\tand not Array(opening.deformation_tracks).is_empty():"
        in TRANSPORT
    )
    for flag in ("closed_door_leakage_enabled", "closed_door_deformation_enabled", "glazing_fallout_enabled"):
        assert f"if {flag} and not pressure_network_solver_enabled:" in ENGINE
    # Las tres listas siguen viviendo en OpeningModel y nadie mas las declara.
    for key in PAYLOAD_KEYS:
        assert f"var {key}: Array = []" in OPENING


def test_no_new_flow_or_transport_route_was_added():
    # Quien LEE las declaraciones dentro del motor sigue siendo el mismo trio de
    # antes de D4A, y las tres lecturas siguen detras de su interruptor. La
    # persistencia solo las ESCRIBE, y lo hace fuera de `sim/core`.
    readers = sorted(
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "sim/core").rglob("*.gd")
        if any(f"opening.{key}" in path.read_text(encoding="utf-8") for key in PAYLOAD_KEYS)
    )
    assert readers == [
        "sim/core/ClosedDoorDeformationNetworkAdapter.gd",
        "sim/core/GlazingFalloutNetworkAdapter.gd",
        "sim/core/PressureNetworkTransportSystem.gd",
    ], readers
    # Y quien las ESCRIBE en el motor de produccion es solo el esquema. Los
    # validadores de `tools/` las montan a mano y quedan fuera, a proposito.
    writers = sorted(
        path.relative_to(ROOT).as_posix()
        for path in list((ROOT / "sim").rglob("*.gd")) + list((ROOT / "editor").rglob("*.gd"))
        if "sim/core" not in path.as_posix()
        and any(
            f"opening.{key} =" in path.read_text(encoding="utf-8") for key in PAYLOAD_KEYS
        )
    )
    assert writers == ["sim/building/PrescribedOpeningPhysicsSchema.gd"], writers


def test_flag_inventory_is_unchanged():
    audit = (ROOT / "scripts/simulation/audit_default_off_flags.py").read_text(
        encoding="utf-8"
    )
    # D4A added none; the later G3 FED candidate raised the inventory to 82.
    assert "EXPECTED_DECLARATION_COUNT = 82" in audit


# ------------------------------------------------------------
# Escenarios distribuidos
# ------------------------------------------------------------


def test_no_distributed_scenario_declares_or_enables_prescribed_physics():
    files = _scenario_files()
    assert files, "no distributed scenario was found"
    for path in files:
        text = path.read_text(encoding="utf-8")
        assert SCHEMA_KEY not in text, path
        for key in PAYLOAD_KEYS:
            assert key not in text, f"{path}: {key}"
        for flag in LIVE_FLAGS:
            assert flag not in text, f"{path}: {flag}"
        data = json.loads(text)
        for opening in data.get("openings_data", []):
            assert opening.get("leakage_class", "none") == "none", path
            assert "leakage_area_override_m2" not in opening, path


def test_legacy_scenarios_stay_outside_the_new_schema():
    # Un escenario anterior a D4A no declara nada, luego carga con la fisica
    # apagada por el contrato de ausencia, sin necesidad de migrarlo.
    for path in _scenario_files():
        data = json.loads(path.read_text(encoding="utf-8"))
        for opening in data.get("openings_data", []):
            assert not any(opening.get(key) for key in PAYLOAD_KEYS), path


# ------------------------------------------------------------
# Documentacion del defecto encontrado
# ------------------------------------------------------------


def test_the_numeric_findings_are_documented_where_they_are_enforced():
    # Los dos defectos del formato quedan escritos junto al codigo que los cierra.
    assert "15 cifras significativas" in SCHEMA
    assert "JSON.parse_string` devuelve TODO numero como `float`" in SCHEMA
    assert "_as_integer(" in SCHEMA
    assert 'data["ignition_room_id"] = int(data["ignition_room_id"])' in SERIALIZER


# ------------------------------------------------------------
# Validador Godot
# ------------------------------------------------------------


def test_validator_passes():
    godot = _godot_exe()
    if godot is None:
        pytest.skip("Godot executable not available")
    completed = run_godot(
        [godot, "--headless", "--path", str(ROOT), "--script", f"res://{VALIDATOR.relative_to(ROOT).as_posix()}"],
        timeout_s=900,
        allowed_exit_codes={0},
    )
    assert PASS_TOKEN in completed.stdout, completed.stdout[-4000:]
