"""F2.2D4B2B: gating the experimental activation of opening physics."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parent.parent
AUTH_PATH = ROOT / "sim/building/ExperimentalRunAuthorization.gd"
AUTH = AUTH_PATH.read_text(encoding="utf-8")
CATALOG = (ROOT / "sim/building/OpeningPhysicsProfileCatalog.gd").read_text(encoding="utf-8")
SCHEMA = (ROOT / "sim/building/PrescribedOpeningPhysicsSchema.gd").read_text(encoding="utf-8")
SELECTION = (ROOT / "sim/building/OpeningProfileSelection.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
BUILDING = (ROOT / "sim/BuildingModel.gd").read_text(encoding="utf-8")
SERIALIZER = (ROOT / "editor/ScenarioSerializer.gd").read_text(encoding="utf-8")
DOCUMENT = (ROOT / "editor/ScenarioDocument.gd").read_text(encoding="utf-8")
EDITOR = (ROOT / "editor/ScenarioEditor.gd").read_text(encoding="utf-8")
CONTROLLER = (ROOT / "editor/OpeningPhysicsEditor.gd").read_text(encoding="utf-8")
PANEL = (ROOT / "editor/EditorPropertyPanel.gd").read_text(encoding="utf-8")
SCENE = (ROOT / "scenes/ScenarioEditorScene.tscn").read_text(encoding="utf-8")
VALIDATOR = ROOT / "tools/validate_experimental_physics_activation.gd"

PASS_TOKEN = "EXPERIMENTAL PHYSICS ACTIVATION VALIDATION PASS"
AUTH_KEY = "experimental_physics_authorization"
SWITCHES = (
    "pressure_network_solver_enabled",
    "closed_door_leakage_enabled",
    "closed_door_deformation_enabled",
    "glazing_fallout_enabled",
    "exterior_envelope_leakage_enabled",
)
FAMILIES = ("door_leakage", "frame_leakage", "deformation", "glazing")
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
    """Lines of code, with documentation and string literals blanked out."""
    kept = []
    for line in source.splitlines():
        if line.lstrip().startswith("#"):
            continue
        kept.append(re.sub(r'"[^"]*"', '""', line))
    return "\n".join(kept)


def _scenario_files() -> list[Path]:
    return sorted(ROOT.glob("scenarios/*.json")) + sorted(ROOT.glob("tests/fixtures/*.json"))


# ------------------------------------------------------------
# Las tres decisiones siguen separadas
# ------------------------------------------------------------


def test_the_three_decisions_stay_separate():
    # 1. configurar: sigue sin encender nada.
    config_code = _code_only(CONTROLLER) + _code_only(SELECTION)
    for switch in SWITCHES:
        assert switch not in config_code, switch
    # 2. autorizar: el contrato nombra los cuatro interruptores y su dependencia.
    for switch in SWITCHES:
        assert switch in AUTH, switch
    # 3. producto: la autorizacion no lo concede ni lo nombra como concedible.
    assert '"product_activation_granted": false' in AUTH
    assert "product_activation" not in _code_only(AUTH).replace(
        "product_activation_granted", ""
    ), "the authorization writes product_activation"


def test_the_switches_are_still_born_off():
    for switch in SWITCHES:
        assert re.findall(rf"^@export var {switch}: bool = (\w+)$", ENGINE, re.M) == ["false"]


def test_no_new_switch_was_added():
    audit = (ROOT / "scripts/simulation/audit_default_off_flags.py").read_text(encoding="utf-8")
    assert "EXPECTED_DECLARATION_COUNT = 81" in audit


def test_every_profile_is_still_barred_from_the_product():
    assert CATALOG.count('"product_activation": true') == 0
    assert CATALOG.count('"product_activation": false') == 15


# ------------------------------------------------------------
# Donde vive la autorizacion, y quien la escribe
# ------------------------------------------------------------


def test_the_authorization_lives_in_the_scenario():
    assert f'const AUTHORIZATION_KEY: String = "{AUTH_KEY}"' in AUTH
    # Viaja por el serializador y llega al modelo y al motor.
    assert "ExperimentalAuthorization.normalize(data)" in SERIALIZER
    assert "ExperimentalAuthorization.validate(data)" in SERIALIZER
    assert "ExperimentalAuthorization.declares(data)" in SERIALIZER
    assert "ExperimentalAuthorizationScript.validate(data)" in BUILDING
    assert "func experimental_authorization_scenario() -> Dictionary:" in BUILDING
    assert "func _apply_experimental_physics_authorization() -> void:" in ENGINE


WRITES_THE_KEY = re.compile(r"\w+\[(?:\w+\.)?AUTHORIZATION_KEY\]\s*=")


def test_only_grant_writes_the_authorization():
    """La clave solo se ESCRIBE en el contrato y en el documento del editor."""
    writers = sorted(
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*.gd")
        if "runs" not in path.parts
        and WRITES_THE_KEY.search(path.read_text(encoding="utf-8"))
    )
    # El contrato lo construye; el documento lo escribe en el escenario con su
    # paso de deshacer; el serializador solo lo COPIA tal cual a la plantilla
    # runtime; y el validador fabrica bloques a mano justamente para comprobar
    # que se rechazan. Nadie mas.
    assert writers == [
        "editor/ScenarioDocument.gd",
        "editor/ScenarioSerializer.gd",
        "sim/building/ExperimentalRunAuthorization.gd",
        "tools/validate_experimental_physics_activation.gd",
    ], writers
    # Y la del serializador es una copia profunda, no una referencia compartida.
    assert "ExperimentalAuthorization.declares(data)" in SERIALIZER
    assert SERIALIZER.count("ExperimentalAuthorization.AUTHORIZATION_KEY") == 4
    # El serializador, el modelo y el motor solo la COPIAN o la LEEN.
    assert "ExperimentalAuthorization.grant" not in SERIALIZER
    assert "ExperimentalAuthorizationScript.grant" not in BUILDING
    assert "ExperimentalAuthorizationScript.grant" not in ENGINE
    assert "static func grant(" in AUTH
    assert "static func revoke(" in AUTH
    assert "ExperimentalAuthorization.grant(" in DOCUMENT
    assert "ExperimentalAuthorization.revoke(" in DOCUMENT


def test_loading_or_saving_a_profile_is_not_an_authorization():
    # Ni el controlador de perfiles ni la politica de seleccion conocen la clave.
    for source in (CONTROLLER, SELECTION, PANEL):
        assert AUTH_KEY not in source
        assert "ExperimentalRunAuthorization" not in source


def test_the_document_owns_the_write_with_its_undo_step():
    assert 'begin("grant_experimental_authorization")' in DOCUMENT
    assert 'begin("revoke_experimental_authorization")' in DOCUMENT
    # Y el editor no escribe la clave a mano en la ruta nueva.
    handler = EDITOR.split("func _on_experimental_custom_action(", 1)[1].split(
        "\n\nfunc ", 1
    )[0]
    assert "editor_data[" not in handler


# ------------------------------------------------------------
# El consentimiento
# ------------------------------------------------------------


def test_the_consent_asks_the_four_things():
    assert "Simulación experimental; parámetros no validados para una vivienda." in AUTH
    assert "las familias de física que se activan y sus valores efectivos" in AUTH
    assert "incluido el dominio de presión" in AUTH
    assert "el motor no predice cuándo ocurren" in AUTH
    assert "const REQUIRED_ACKNOWLEDGEMENTS: Array[String] = [" in AUTH
    # Las cuatro, y la escena tiene una casilla para cada una.
    for check in (
        "ExperimentalAckExperimental",
        "ExperimentalAckFamilies",
        "ExperimentalAckLimits",
        "ExperimentalAckPrescribed",
    ):
        assert f'[node name="{check}" type="CheckBox"' in SCENE, check
    assert 'const EXPERIMENTAL_CHECK_NAMES: Array[String] = [' in EDITOR


def test_every_new_control_lives_in_the_scene_with_its_tooltip():
    for node in (
        "ExperimentalPhysicsDialog",
        "ExperimentalConsentLabel",
        "ExperimentalStatusLabel",
        "BtnExperimentalPhysics",
    ):
        assert f'[node name="{node}"' in SCENE, node
    for check in (
        "ExperimentalAckExperimental",
        "ExperimentalAckFamilies",
        "ExperimentalAckLimits",
        "ExperimentalAckPrescribed",
        "BtnExperimentalPhysics",
    ):
        block = SCENE.split(f'[node name="{check}"', 1)[1].split("[node ", 1)[0]
        assert "tooltip_text" in block, check


def test_the_run_button_asks_before_an_authorized_scenario_runs():
    handler = EDITOR.split("func _run_simulation_pressed() -> void:", 1)[1].split(
        "\n\n", 1
    )[0]
    assert "ExperimentalAuthorization.declares(editor_data)" in handler
    assert "_show_experimental_dialog()" in handler
    # Y la confirmacion vale solo para este arranque.
    assert "_experimental_acknowledged = true" in EDITOR
    assert "_experimental_acknowledged = false" in EDITOR


def test_the_editor_still_never_writes_a_switch():
    for path in ROOT.glob("editor/*.gd"):
        code = _code_only(path.read_text(encoding="utf-8"))
        for switch in SWITCHES:
            assert switch not in code, f"{path.name}: {switch}"


def test_no_label_calls_an_experimental_run_validated():
    readable = re.findall(r'text = "([^"]*)"', SCENE)
    readable += re.findall(r'tooltip_text = "([^"]*)"', SCENE)
    assert len(readable) > 50
    for piece in readable:
        lowered = piece.lower()
        for forbidden in ("calibrado", "calibrada", "realista", "estándar residencial"):
            assert forbidden not in lowered, piece
    assert "No es una validación física ni " in AUTH


# ------------------------------------------------------------
# Rechazos
# ------------------------------------------------------------


def test_validity_is_delegated_to_the_schema_not_reimplemented():
    # Quien rechaza bloqueado, desconocido, incompatible, version no publicada y
    # copia congelada alterada sigue siendo el esquema. El contrato de
    # autorizacion lo LLAMA; no copia ni una de esas reglas.
    assert "Schema.validate(opening, index)" in AUTH
    code = _code_only(AUTH)
    for forbidden in (
        "EVIDENCE_BLOCKED",
        "can_produce_configuration",
        "category_applies_to",
        "_compare_frozen_parameters",
    ):
        assert forbidden not in code, forbidden


def test_a_research_only_profile_needs_the_experimental_confirmation():
    assert "EVIDENCE_RESEARCH_ONLY" in AUTH
    assert "falta la confirmación experimental" in AUTH
    assert 'const EXPERIMENTAL_FIELD: String = "experimental_profiles_confirmed"' in AUTH


def test_the_authorization_expires_when_the_scenario_changes():
    assert "static func digest(" in AUTH
    assert ".sha256_text()" in AUTH
    assert "la huella no coincide con el escenario" in AUTH
    # Lo que justifica autorizar y lo que entra en la huella son lo mismo.
    assert "static func _family_fields(" in AUTH
    assert "return not _family_fields(opening, family).is_empty()" in AUTH
    assert "_canonical(_family_fields(" in AUTH


def test_the_engine_refuses_to_simulate_a_rejected_authorization():
    assert "var experimental_authorization_failure: String = \"\"" in ENGINE
    step = ENGINE.split("func step(delta: float) -> void:", 1)[1].split("\n\n", 1)[0]
    assert "experimental_authorization_failure.is_empty()" in step
    ready = ENGINE.split("func _ready() -> void:", 1)[1].split("\n\n", 1)[0]
    assert "_apply_experimental_physics_authorization()" in ready
    # Y al reiniciar se vuelve a resolver, no se hereda.
    reset = ENGINE.split("func reset_simulation(", 1)[1].split("\nfunc ", 1)[0]
    assert "_apply_experimental_physics_authorization()" in reset


# ------------------------------------------------------------
# La red y las leyes de caudal
# ------------------------------------------------------------


def test_the_network_dependency_is_reused_not_recreated():
    assert 'const REQUIRED_DEPENDENCY: String = "pressure_network_solver_enabled"' in AUTH
    # El contrato no copia ni una cuenta de caudal.
    code = _code_only(AUTH)
    for forbidden in ("sqrt(", "pow(", "dp_pa", "rho", "discharge", "* area"):
        assert forbidden not in code, forbidden


def test_the_authorization_never_touches_a_flow_law():
    for forbidden in (
        "compute_flows",
        "compute_segment_flow_from_dp",
        "build_door_segments",
        "compute_open_geometry",
        "evaluate_panels",
        "solve_pressure_network",
    ):
        assert forbidden not in AUTH, forbidden
    # El unico adaptador que toca, y solo por su constante de dominio.
    assert "ClosedDoorLeakageNetworkAdapter.gd" in AUTH
    assert "LeakageAdapter.PRESSURE_DOMAIN_MAX_PA" in AUTH
    assert AUTH.count("LeakageAdapter.") == 1


def test_the_envelope_leak_precedence_is_untouched():
    transport = (ROOT / "sim/core/PressureNetworkTransportSystem.gd").read_text(
        encoding="utf-8"
    )
    # La regla de D4B1: la propia SUSTITUYE a la global, nunca se suman.
    assert "Nunca se suman las dos" in transport
    body = transport.split("func _envelope_leak_area_m2(opening) -> float:", 1)[1].split(
        "\n\n", 1
    )[0]
    assert "+" not in body


# ------------------------------------------------------------
# D2 y D3 siguen siendo prescripcion
# ------------------------------------------------------------


def test_deformation_and_glazing_stay_prescriptions():
    assert "const PRESCRIBED_FAMILIES: Array[String] = [FAMILY_DEFORMATION, FAMILY_GLAZING]" in AUTH
    assert 'DEFORMATION_PROFILE_KEY: "",' in SCHEMA
    assert 'GLAZING_PROFILE_KEY: "",' in SCHEMA


def test_nothing_of_break1_or_the_probabilistic_model_appeared():
    for forbidden in ("BREAK1", "GlassFailureSystem"):
        assert forbidden not in AUTH, forbidden


# ------------------------------------------------------------
# Escenarios distribuidos
# ------------------------------------------------------------


def test_no_distributed_scenario_authorizes_or_configures_anything():
    files = _scenario_files()
    assert files
    for path in files:
        text = path.read_text(encoding="utf-8")
        assert AUTH_KEY not in text, path
        for key in PROFILE_KEYS:
            assert key not in text, f"{path}: {key}"
        assert "prescribed_physics_schema" not in text, path
        for switch in SWITCHES:
            assert switch not in text, f"{path}: {switch}"
        data = json.loads(text)
        assert AUTH_KEY not in data, path


# ------------------------------------------------------------
# Salida diagnostica
# ------------------------------------------------------------


def test_the_diagnostic_output_carries_the_provenance():
    for field in (
        '"profiles"',
        '"families"',
        '"switches"',
        '"scenario_digest"',
        '"domain_exceeded"',
        '"max_abs_dp_pa"',
        '"pressure_domain_max_pa"',
        '"not_a_validation"',
    ):
        assert field in AUTH, field
    for field in ('"profile_id"', '"profile_version"', '"effective"', '"units"', '"domain"'):
        assert field in AUTH, field
    assert 'summary["experimental_activation"]' in ENGINE
    # Solo cuando hay algo que contar: un escenario normal no gana el bloque.
    assert "if not _experimental_activation_report.is_empty():" in ENGINE


def test_out_of_domain_is_marked_and_not_clipped():
    assert "func _accumulate_experimental_domain_marks() -> void:" in ENGINE
    body = ENGINE.split("func _accumulate_experimental_domain_marks() -> void:", 1)[1].split(
        "\n\n", 1
    )[0]
    # Solo cuenta y toma el maximo: ni recorta ni reajusta un coeficiente.
    for forbidden in ("clamp", "min(", "= 50.0", "discharge"):
        assert forbidden not in body, forbidden
    assert "domain_exceeded_count" in body


# ------------------------------------------------------------
# Guardarrailes y validador
# ------------------------------------------------------------


def test_the_validator_is_registered():
    product = (ROOT / "scripts/check_product.py").read_text(encoding="utf-8")
    assert "validate_experimental_physics_activation.gd" in product
    assert PASS_TOKEN in product
    # Y los de las fases anteriores siguen registrados.
    for earlier in (
        "validate_closed_door_leakage_network.gd",
        "validate_closed_door_deformation_network.gd",
        "validate_glazing_fallout_network.gd",
        "validate_prescribed_physics_persistence.gd",
        "validate_opening_physics_profiles.gd",
        "validate_opening_profile_editor.gd",
    ):
        assert earlier in product, earlier


def test_consumer_list_stays_closed():
    consumers = sorted(
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*.gd")
        if "runs" not in path.parts
        and "ExperimentalRunAuthorization" in path.read_text(encoding="utf-8")
    )
    # Cinco consumidores y su validador. El contrato no se nombra a si mismo,
    # asi que no aparece en su propia lista.
    assert consumers == [
        "editor/ScenarioDocument.gd",
        "editor/ScenarioEditor.gd",
        "editor/ScenarioSerializer.gd",
        "sim/BuildingModel.gd",
        "sim/core/SimulationEngine.gd",
        "tools/validate_experimental_physics_activation.gd",
    ], consumers
    assert AUTH_PATH.exists()


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
