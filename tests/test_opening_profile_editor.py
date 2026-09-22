"""F2.2D4B2A: configuring experimental opening physics from the editor."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parent.parent
CATALOG = (ROOT / "sim/building/OpeningPhysicsProfileCatalog.gd").read_text(encoding="utf-8")
SELECTION_PATH = ROOT / "sim/building/OpeningProfileSelection.gd"
SELECTION = SELECTION_PATH.read_text(encoding="utf-8")
SCHEMA = (ROOT / "sim/building/PrescribedOpeningPhysicsSchema.gd").read_text(encoding="utf-8")
CONTROLLER_PATH = ROOT / "editor/OpeningPhysicsEditor.gd"
CONTROLLER = CONTROLLER_PATH.read_text(encoding="utf-8")
PANEL = (ROOT / "editor/EditorPropertyPanel.gd").read_text(encoding="utf-8")
EDITOR = (ROOT / "editor/ScenarioEditor.gd").read_text(encoding="utf-8")
DOCUMENT = (ROOT / "editor/ScenarioDocument.gd").read_text(encoding="utf-8")
SCENE = (ROOT / "scenes/ScenarioEditorScene.tscn").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
VALIDATOR = ROOT / "tools/validate_opening_profile_editor.gd"

PASS_TOKEN = "OPENING PROFILE EDITOR VALIDATION PASS"
LIVE_FLAGS = (
    "closed_door_leakage_enabled",
    "closed_door_deformation_enabled",
    "glazing_fallout_enabled",
    "exterior_envelope_leakage_enabled",
    "pressure_network_solver_enabled",
)
PROFILE_KEYS = (
    "leakage_profile",
    "frame_leakage_profile",
    "deformation_profile",
    "glazing_profile",
)
GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def _code_only(source: str) -> str:
    kept = []
    for line in source.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        kept.append(re.sub(r'"[^"]*"', '""', line))
    return "\n".join(kept)


def _scenario_files() -> list[Path]:
    return sorted(ROOT.glob("scenarios/*.json")) + sorted(ROOT.glob("tests/fixtures/*.json"))


# ------------------------------------------------------------
# Separacion entre configuracion y activacion
# ------------------------------------------------------------


def test_the_editor_never_writes_a_switch():
    for source in (CONTROLLER, SELECTION, PANEL):
        code = _code_only(source)
        for flag in LIVE_FLAGS:
            assert flag not in code, flag
    # Y los cinco siguen naciendo apagados.
    for flag in LIVE_FLAGS:
        assert re.findall(rf"^@export var {flag}: bool = (\w+)$", ENGINE, re.M) == ["false"]


def test_configuring_never_touches_the_operational_state():
    code = _code_only(CONTROLLER)
    for forbidden in ("open_fraction =", "glass_broken", "thermal_gap_fraction"):
        assert forbidden not in code, forbidden
    # El controlador lo dice y el validador lo mide.
    assert "Configurar no es activar" in CONTROLLER


def test_the_status_line_says_it_is_not_active():
    assert "física no activada en simulación normal" in SELECTION
    assert "CONFIGURED_NOT_ACTIVE_TEXT" in CONTROLLER
    assert "OpeningPhysicsStatusLabel" in SCENE
    assert "OpeningPhysicsStatusLabel" in PANEL


# ------------------------------------------------------------
# Arquitectura: la vista no es propietaria de fisica
# ------------------------------------------------------------


def test_no_editor_or_view_file_carries_a_flow_formula():
    offenders: list[str] = []
    for folder in ("editor", "view", "ui", "scenes"):
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*.gd"):
            code = _code_only(path.read_text(encoding="utf-8"))
            for forbidden in (
                "compute_flows",
                "compute_segment_flow_from_dp",
                "build_door_segments",
                "compute_open_geometry",
                "evaluate_panels",
                "solve_pressure_network",
                "build_snapshot",
            ):
                if forbidden in code:
                    offenders.append(f"{path.relative_to(ROOT).as_posix()}: {forbidden}")
    assert offenders == [], offenders


def test_the_view_does_not_import_the_transport_or_the_solver():
    offenders: list[str] = []
    for folder in ("editor", "view", "ui"):
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*.gd"):
            text = path.read_text(encoding="utf-8")
            for forbidden in (
                "PressureNetworkTransportSystem.gd",
                "Phase3CoupledPressureSolver.gd",
                "ClosedDoorLeakageNetworkAdapter.gd",
                "GlazingFalloutNetworkAdapter.gd",
                "ExteriorEnvelopeLeakageAdapter.gd",
            ):
                if forbidden in text:
                    offenders.append(f"{path.relative_to(ROOT).as_posix()}: {forbidden}")
    # `ScenarioSerializer` conserva el adaptador de D1 desde 2026-09-18 para
    # normalizar la clase de fuga; es la unica excepcion, y esta documentada.
    assert offenders == [
        "editor/ScenarioSerializer.gd: ClosedDoorLeakageNetworkAdapter.gd"
    ], offenders


def test_the_new_editor_files_carry_no_flow_maths():
    # Estos dos son los ficheros por los que la fisica podria colarse en la
    # interfaz, asi que se les exige no hacer ni una cuenta de caudal.
    for path, source in ((CONTROLLER_PATH, CONTROLLER), (SELECTION_PATH, SELECTION)):
        code = _code_only(source)
        for forbidden in ("sqrt(", "pow(", "exp(", "* dp", "dp_pa", "rho"):
            assert forbidden not in code, f"{path.name}: {forbidden}"


def test_the_selection_policy_owns_the_labels_not_the_panel():
    # El panel no puede tener su propia tabla de estados de evidencia.
    code = _code_only(PANEL)
    for state in ("validated", "derived", "research_only", "blocked"):
        assert state not in code, state
    assert "EVIDENCE_LABEL" in SELECTION
    assert "EVIDENCE_NOTE" in SELECTION


def test_consumer_lists_stay_closed():
    selection_consumers = sorted(
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*.gd")
        if "runs" not in path.parts
        and "OpeningProfileSelection" in path.read_text(encoding="utf-8")
    )
    assert selection_consumers == [
        "editor/OpeningPhysicsEditor.gd",
        "tools/validate_opening_profile_editor.gd",
    ], selection_consumers
    controller_consumers = sorted(
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*.gd")
        if "runs" not in path.parts
        and "OpeningPhysicsEditor.gd" in path.read_text(encoding="utf-8")
    )
    # El validador de D4B1 tambien lo nombra: su regla 11 exige que el UNICO
    # consumidor del catalogo dentro de `editor/` sea este controlador.
    assert controller_consumers == [
        "editor/ScenarioEditor.gd",
        "tools/validate_opening_physics_profiles.gd",
        "tools/validate_opening_profile_editor.gd",
    ], controller_consumers


# ------------------------------------------------------------
# Politica de seleccion
# ------------------------------------------------------------


def test_blocked_is_shown_but_disabled():
    assert "set_item_disabled(index, true)" in PANEL
    assert "set_item_tooltip(index, String(row[" in PANEL
    assert 'EVIDENCE_BLOCKED' in SELECTION
    assert "perfil bloqueado" in SELECTION


def test_research_only_requires_the_experimental_confirmation():
    assert "requires_experimental" in SELECTION
    assert "exige confirmar antes el modo experimental" in SELECTION
    assert "OpeningPhysicsExperimentalCheck" in SCENE
    assert "experimental_confirmed" in CONTROLLER


def test_product_activation_is_never_hidden():
    assert "PRODUCT_LABEL_OFF" in SELECTION
    assert "product_activation = false" in SELECTION
    assert "OpeningPhysicsProductLabel" in SCENE


def test_the_editor_never_calls_a_profile_calibrated_or_safe():
    # Se mira lo que el usuario LEE: los textos de la escena y las constantes de
    # vocabulario. La documentacion queda fuera a proposito, porque nombra por
    # fuerza las palabras que prohibe.
    readable: list[str] = re.findall(r'text = "([^"]*)"', SCENE)
    readable += re.findall(r'tooltip_text = "([^"]*)"', SCENE)
    readable += re.findall(r'"([^"]*)"', _code_only_keeping_strings(SELECTION))
    assert len(readable) > 50
    for piece in readable:
        lowered = piece.lower()
        for forbidden in ("calibrado", "calibrada", "realista", "estándar residencial"):
            assert forbidden not in lowered, piece


def _code_only_keeping_strings(source: str) -> str:
    """Lines of code, with the documentation stripped but the strings kept."""
    return "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )


# ------------------------------------------------------------
# Esquema 3 y migraciones
# ------------------------------------------------------------


def test_schema_3_adds_the_two_provenance_slots():
    assert "const SCHEMA_VERSION: int = 3" in SCHEMA
    assert "const MIN_SCHEMA_VERSION: int = 1" in SCHEMA
    assert 'const DEFORMATION_PROFILE_KEY: String = "deformation_profile"' in SCHEMA
    assert 'const GLAZING_PROFILE_KEY: String = "glazing_profile"' in SCHEMA
    assert "const SCHEMA_2_PROFILE_KEYS" in SCHEMA
    # Las dos nuevas no aportan numero al motor.
    assert 'DEFORMATION_PROFILE_KEY: "",' in SCHEMA
    assert 'GLAZING_PROFILE_KEY: "",' in SCHEMA


def test_the_marker_only_goes_up():
    assert "if typeof(declared) == TYPE_INT and int(declared) < required:" in SCHEMA
    assert "required = maxi(required, 2 if SCHEMA_2_PROFILE_KEYS.has(key) else 3)" in SCHEMA


def test_compatibility_is_owned_by_the_catalogue():
    assert "static func category_applies_to(" in CATALOG
    assert "static func incompatibility_reason(" in CATALOG
    assert "ProfileCatalog.category_applies_to(category, opening_data)" in SCHEMA
    # Y no se reimplementa en el editor.
    code = _code_only(CONTROLLER)
    assert "is_vertical" not in code
    assert "Catalog.category_applies_to" in CONTROLLER


# ------------------------------------------------------------
# Escenarios distribuidos
# ------------------------------------------------------------


def test_no_distributed_scenario_declares_or_activates_anything():
    files = _scenario_files()
    assert files
    for path in files:
        text = path.read_text(encoding="utf-8")
        for key in PROFILE_KEYS:
            assert key not in text, f"{path}: {key}"
        assert "prescribed_physics_schema" not in text, path
        for flag in LIVE_FLAGS:
            assert flag not in text, f"{path}: {flag}"
        data = json.loads(text)
        for opening in data.get("openings_data", []):
            for key in PROFILE_KEYS:
                assert key not in opening, path


def test_no_switch_was_added():
    audit = (ROOT / "scripts/simulation/audit_default_off_flags.py").read_text(encoding="utf-8")
    assert "EXPECTED_DECLARATION_COUNT = 81" in audit


# ------------------------------------------------------------
# La escena, y que se llegue con el teclado
# ------------------------------------------------------------


def test_every_new_control_lives_in_the_scene():
    for node in (
        "OpeningPhysicsExperimentalCheck",
        "OpeningPhysicsSlotOption",
        "OpeningPhysicsProfileOption",
        "OpeningPhysicsList",
        "OpeningPhysicsEntryKindOption",
        "OpeningPhysicsEntryIdEdit",
        "OpeningPhysicsEntryTimeSpin",
        "OpeningPhysicsEntryAreaSpin",
        "BtnApplyOpeningPhysicsProfile",
        "BtnAddOpeningPhysicsEntry",
        "BtnRemoveOpeningPhysicsEntry",
    ):
        assert f'[node name="{node}"' in SCENE, node
    # Nada se construye en runtime: el guardarrail de escena completa lo mide,
    # y aqui se comprueba que el panel solo BUSCA nodos, no los crea.
    assert ".new()" not in _code_only(PANEL)


def test_every_new_numeric_control_declares_its_unit():
    for spin, suffix in (
        ("OpeningPhysicsEntryTimeSpin", " s"),
        ("OpeningPhysicsEntryAreaSpin", " m²"),
        ("OpeningPhysicsEntryFractionSpin", " %"),
        ("OpeningPhysicsEntryXSpin", " m"),
        ("OpeningPhysicsEntryZSpin", " m"),
        ("OpeningPhysicsEntryWidthSpin", " m"),
        ("OpeningPhysicsEntryHeightSpin", " m"),
        ("OpeningPhysicsEntryLeafCountSpin", " hojas"),
    ):
        block = SCENE.split(f'[node name="{spin}"', 1)[1].split("[node ", 1)[0]
        assert f'suffix = "{suffix}"' in block, spin
        assert "tooltip_text" in block, spin


def test_the_scene_guardrails_are_still_registered():
    product = (ROOT / "scripts/check_product.py").read_text(encoding="utf-8")
    assert "validate_editor_scene_complete.gd" in product
    assert "validate_editor_ui_affordances.gd" in product
    assert "validate_opening_profile_editor.gd" in product


# ------------------------------------------------------------
# El documento sigue siendo el dueño de los datos
# ------------------------------------------------------------


def test_the_document_owns_the_write():
    assert "func replace_opening(opening_index: int, opening: Dictionary) -> bool:" in DOCUMENT
    assert 'begin("edit_opening_physics")' in DOCUMENT
    assert "_doc.replace_opening(selected_opening_index" in EDITOR
    # El editor no escribe openings_data a mano en la ruta nueva.
    handler = EDITOR.split("func _commit_opening_physics(", 1)[1].split("\n\nfunc ", 1)[0]
    assert 'editor_data["openings_data"]' not in handler


# ------------------------------------------------------------
# Validador Godot
# ------------------------------------------------------------


def test_validator_passes():
    godot = _godot_exe()
    if godot is None:
        pytest.skip("Godot executable not available")
    completed = run_godot(
        [
            godot,
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            f"res://{VALIDATOR.relative_to(ROOT).as_posix()}",
        ],
        timeout_s=900,
        allowed_exit_codes={0},
    )
    assert PASS_TOKEN in completed.stdout, completed.stdout[-4000:]
