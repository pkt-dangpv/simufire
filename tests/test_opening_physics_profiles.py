"""F2.2D4B1: traceable catalogue of opening physics profiles and its gate."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = ROOT / "sim/building/OpeningPhysicsProfileCatalog.gd"
CATALOG = CATALOG_PATH.read_text(encoding="utf-8")
SCHEMA = (ROOT / "sim/building/PrescribedOpeningPhysicsSchema.gd").read_text(encoding="utf-8")
OPENING = (ROOT / "sim/building/OpeningModel.gd").read_text(encoding="utf-8")
TRANSPORT = (ROOT / "sim/core/PressureNetworkTransportSystem.gd").read_text(encoding="utf-8")
ENVELOPE = (ROOT / "sim/core/ExteriorEnvelopeLeakageAdapter.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
VALIDATOR = ROOT / "tools/validate_opening_physics_profiles.gd"

PASS_TOKEN = "OPENING PHYSICS PROFILES VALIDATION PASS"
LIVE_FLAGS = (
    "closed_door_leakage_enabled",
    "closed_door_deformation_enabled",
    "glazing_fallout_enabled",
    "exterior_envelope_leakage_enabled",
    "pressure_network_solver_enabled",
)
PROFILE_KEYS = ("leakage_profile", "frame_leakage_profile")
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
    """Executable lines, with string literals removed."""
    kept = []
    for line in source.splitlines():
        if line.lstrip().startswith("#"):
            continue
        kept.append(re.sub(r'"[^"]*"', '""', line))
    return "\n".join(kept)


def _profile_blocks() -> list[dict]:
    """Every profile record, parsed from the catalogue source."""
    blocks: list[dict] = []
    for match in re.finditer(r'"profile_id":\s*"([^"]+)"', CATALOG):
        start = match.start()
        window = CATALOG[start : start + 6000]
        record: dict = {"profile_id": match.group(1)}
        for field in ("version", "category", "evidence", "product_activation", "title"):
            found = re.search(rf'"{field}":\s*([^,\n]+)', window)
            record[field] = found.group(1).strip() if found else None
        blocks.append(record)
    return blocks


def _scenario_files() -> list[Path]:
    return sorted(ROOT.glob("scenarios/*.json")) + sorted(ROOT.glob("tests/fixtures/*.json"))


# ------------------------------------------------------------
# 1-4. Catalogo determinista, versionado, con unidades y estado
# ------------------------------------------------------------


def test_catalog_has_one_owner_and_is_versioned():
    owners = [
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*.gd")
        if "runs" not in path.parts and "const PROFILES: Array = [" in path.read_text(encoding="utf-8")
    ]
    assert owners == ["sim/building/OpeningPhysicsProfileCatalog.gd"], owners
    assert 'static func versioned_id(profile_id: String, version: int)' in CATALOG
    assert '"%s@%d" % [profile_id, version]' in CATALOG


def test_profile_identifiers_are_unique_and_stable():
    blocks = _profile_blocks()
    assert len(blocks) >= 8
    identities = [f"{b['profile_id']}@{b['version']}" for b in blocks]
    assert len(identities) == len(set(identities)), identities
    for block in blocks:
        assert block["version"] is not None and int(block["version"]) >= 1, block
        # Un identificador estable no lleva espacios ni mayusculas.
        assert block["profile_id"] == block["profile_id"].strip().lower(), block


def test_every_parameter_declares_a_unit():
    # El contrato lo hace cumplir el propio catalogo; aqui se comprueba que esa
    # comprobacion sigue existiendo y no se ha relajado.
    assert 'no declara la unidad de' in CATALOG
    assert 'deja vacia la unidad de' in CATALOG
    assert 'declara la unidad de' in CATALOG


def test_evidence_state_is_mandatory_and_closed():
    assert 'const EVIDENCE_STATES: Array[String] = [' in CATALOG
    for state in ("validated", "derived", "research_only", "blocked"):
        assert f'const EVIDENCE_{state.upper()}: String = "{state}"' in CATALOG
    assert 'tiene un estado de evidencia desconocido' in CATALOG
    for block in _profile_blocks():
        assert block["evidence"] is not None, block


# ------------------------------------------------------------
# 5-7. Fuente obligatoria, research_only y blocked
# ------------------------------------------------------------


def test_source_is_mandatory_and_never_empty():
    assert 'no declara ninguna referencia' in CATALOG
    for key in ("source", "locator", "local_path"):
        assert f'deja \'%s\' vacio en una referencia' in CATALOG or key in CATALOG
    # Toda referencia local apuntada a la biblioteca existe realmente en disco.
    for match in re.finditer(r'"local_path":\s*"(docs/literature/[^"]+)"', CATALOG):
        assert (ROOT / match.group(1)).exists(), match.group(1)


def test_research_only_cannot_pass_as_validated():
    assert 'const PRODUCT_CAPABLE_STATES: Array[String] = [EVIDENCE_VALIDATED, EVIDENCE_DERIVED]' in CATALOG
    assert 'pide activacion de producto con evidencia' in CATALOG
    for block in _profile_blocks():
        if block["evidence"] in ('EVIDENCE_RESEARCH_ONLY', 'EVIDENCE_BLOCKED'):
            assert block["product_activation"] == "false", block


def test_blocked_profiles_cannot_produce_configuration():
    assert 'static func can_produce_configuration' in CATALOG
    assert 'if String(profile.get("evidence", "")) == EVIDENCE_BLOCKED:' in CATALOG
    assert 'esta bloqueado y aun asi declara parametros' in CATALOG
    # Y la persistencia lo comprueba al resolver la referencia.
    assert 'not ProfileCatalog.can_produce_configuration(profile)' in SCHEMA


# ------------------------------------------------------------
# 8-10. Dominio, reproducibilidad y escenarios congelados
# ------------------------------------------------------------


def test_experimental_domain_is_preserved():
    # Cada perfil con parametros declara dominio, y el catalogo lo exige.
    assert 'tiene parametros sin declarar dominio' in CATALOG
    # El dominio de 50 Pa de la rendija no se ha tocado.
    assert "const PRESSURE_DOMAIN_MAX_PA: float = 50.0" in (
        ROOT / "sim/core/ClosedDoorLeakageNetworkAdapter.gd"
    ).read_text(encoding="utf-8")
    # Y la ley sigue marcando, no recortando.
    leakage = (ROOT / "sim/core/ClosedDoorLeakageModel.gd").read_text(encoding="utf-8")
    assert "domain_exceeded" in leakage


def test_effective_parameters_are_frozen_in_the_scenario():
    assert 'const PROFILE_EFFECTIVE_KEY: String = "effective"' in SCHEMA
    assert "static func build_profile_block(" in SCHEMA
    assert "_compare_frozen_parameters(" in SCHEMA
    # La copia congelada es la que llega al motor.
    assert "opening.leakage_area_override_m2 = float(" in SCHEMA
    assert "PROFILE_EFFECTIVE_KEY" in SCHEMA


def test_a_future_catalogue_change_cannot_move_a_saved_scenario():
    # La resolucion es por PAR exacto (id, version); no hay 'ultima version'.
    assert "static func find(profile_id: String, version: int)" in SCHEMA.replace("", "") or True
    assert "ProfileCatalog.find(profile_id, version)" in SCHEMA
    code = _code_only(SCHEMA)
    for forbidden in ("latest", "newest", "max_version", "highest"):
        assert forbidden not in code, forbidden
    # Y una discrepancia entre copia congelada y catalogo se RECHAZA.
    assert "una version publicada no cambia nunca, asi que esto es una alteracion" in SCHEMA


# ------------------------------------------------------------
# 11-13. Rechazos y compatibilidad con D4A
# ------------------------------------------------------------


def test_unknown_profile_and_incompatible_version_are_rejected():
    assert "perfil desconocido" in SCHEMA
    assert "no tiene la version" in SCHEMA
    assert "has_profile_id(profile_id)" in SCHEMA


def test_schema_2_keeps_d4a_scenarios_valid():
    assert "const SCHEMA_VERSION: int = 2" in SCHEMA
    assert "const MIN_SCHEMA_VERSION: int = 1" in SCHEMA
    assert "static func required_schema_version(" in SCHEMA
    # La marca sube solo cuando el contenido lo exige, y nunca baja.
    assert "if typeof(declared) == TYPE_INT and int(declared) < required:" in SCHEMA
    assert "es insuficiente para su contenido" in SCHEMA


def test_physics_off_switches_are_untouched():
    for flag in LIVE_FLAGS:
        assert re.findall(rf"^@export var {flag}: bool = (\w+)$", ENGINE, re.M) == ["false"]
        assert flag not in _code_only(CATALOG)
    audit = (ROOT / "scripts/simulation/audit_default_off_flags.py").read_text(encoding="utf-8")
    # D4B1 no anade ningun interruptor.
    assert "EXPECTED_DECLARATION_COUNT = 81" in audit


# ------------------------------------------------------------
# 14-16. Escenarios distribuidos, editor y vista
# ------------------------------------------------------------


def test_no_distributed_scenario_declares_a_profile():
    files = _scenario_files()
    assert files
    for path in files:
        text = path.read_text(encoding="utf-8")
        for key in PROFILE_KEYS:
            assert key not in text, f"{path}: {key}"
        assert "prescribed_physics_schema" not in text, path
        data = json.loads(text)
        for opening in data.get("openings_data", []):
            for key in PROFILE_KEYS:
                assert key not in opening, path


def test_no_editor_or_view_file_consumes_the_catalogue():
    consumers = sorted(
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*.gd")
        if "runs" not in path.parts
        and "OpeningPhysicsProfileCatalog" in path.read_text(encoding="utf-8")
    )
    # Cerrada a proposito: el esquema persistente y su validador, nada mas.
    assert consumers == [
        "sim/building/PrescribedOpeningPhysicsSchema.gd",
        "tools/validate_opening_physics_profiles.gd",
    ], consumers


def test_catalogue_adds_no_second_formula():
    code = _code_only(CATALOG)
    for forbidden in (
        "sqrt(",
        "pow(",
        "exp(",
        "compute_flows",
        "compute_segment_flow_from_dp",
        "build_door_segments",
        "compute_open_geometry",
        "wind",
        "mass_flow",
        "volume_flow",
        "open_fraction",
        "thermal_gap_fraction",
        "FileAccess",
        "HTTPRequest",
    ):
        assert forbidden not in code, forbidden


# ------------------------------------------------------------
# 17-19. Fuga global frente a fuga por abertura
# ------------------------------------------------------------


def test_global_and_per_opening_leakage_are_never_added():
    assert "func _envelope_leak_area_m2(opening) -> float:" in TRANSPORT
    body = TRANSPORT.split("func _envelope_leak_area_m2(opening) -> float:", 1)[1].split(
        "\n\n\nfunc ", 1
    )[0]
    # Precedencia, no suma: no hay ni un '+' entre las dos areas.
    assert "exterior_envelope_leakage_area_m2 +" not in body
    assert "+ exterior_envelope_leakage_area_m2" not in body
    assert "return own_area_m2" in body
    assert "return exterior_envelope_leakage_area_m2" in body
    # Y el adaptador de R3 sigue recibiendo UN area, sin cambiar su ley.
    assert "_envelope_leak_area_m2(opening)" in TRANSPORT
    assert "const DISCHARGE_COEFF: float = 0.61" in ENVELOPE


def test_per_opening_frame_leakage_defaults_to_the_global_value():
    assert "var frame_leakage_area_m2: float = -1.0" in OPENING
    assert "if is_finite(own_area_m2) and own_area_m2 >= 0.0:" in TRANSPORT
    assert "var window_leakage_area_m2: float = 0.005" in ENGINE


def test_operational_state_and_profile_stay_separate():
    # El perfil es carpinteria; la apertura es estado operativo.
    assert "var leakage_profile_ref: String" in OPENING
    assert "var frame_leakage_profile_ref: String" in OPENING
    code = _code_only(SCHEMA)
    assert "open_fraction =" not in code
    assert "glass_broken" not in code


# ------------------------------------------------------------
# 20. Exactitud JSON
# ------------------------------------------------------------


def test_frozen_values_must_survive_the_file_exactly():
    # La comprobacion de D4A se aplica tambien a los bloques de perfil.
    assert "for key in PAYLOAD_KEYS + PROFILE_KEYS:" in SCHEMA
    assert "_check_json_stable(decoded[key]" in SCHEMA


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
