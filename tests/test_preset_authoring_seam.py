"""D-2: el contenido de autor del preset no puede filtrarse a la validación.

`sim/validation/cases/fds_simple_house_*.json` declaran `"template":
"simple_house"` y `CaseRunner` los construye con
`BuildingTemplate.create_by_name()`. Si esa ruta devolviera un objeto marcado
como foco de ignición, cambiaría cuál arde primero y movería una línea base
calibrada contra FDS. Por eso el contenido de autor —inicio en primera persona
y foco— vive en `PRESET_AUTHORING` y solo lo aplica `create_product_preset()`.

Estas pruebas son estáticas: leen el código, no lanzan Godot. Vigilan que la
separación siga en pie y que el generador de `scenarios/` siga usando la ruta
de producto, que es lo que hace que la corrección sobreviva a una exportación
futura.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "sim/templates/BuildingTemplate.gd"
EXPORTER = ROOT / "tools/export_presets_to_scenarios.gd"
EDITOR = ROOT / "editor/ScenarioEditor.gd"
BUILDING_MODEL = ROOT / "sim/BuildingModel.gd"
CASE_RUNNER = ROOT / "sim/validation/CaseRunner.gd"
SCENARIO_RUNNER = ROOT / "tools/run_scenario_headless.gd"

PRODUCT_CALLERS = (EXPORTER, EDITOR, BUILDING_MODEL)
VALIDATION_CALLERS = (CASE_RUNNER, SCENARIO_RUNNER)


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _builder_body(name: str) -> str:
    """El cuerpo de un `func <name>() -> Dictionary:` hasta el siguiente `func`."""
    source = _read(TEMPLATE)
    start = source.index("\nfunc %s() -> Dictionary:" % name)
    rest = source[start + 1:]
    end = rest.find("\nfunc ")
    return rest if end < 0 else rest[:end]


def test_the_authoring_layer_exists_and_declares_the_two_scenarios():
    source = _read(TEMPLATE)
    assert "const PRESET_AUTHORING" in source
    assert "func create_product_preset(preset_name: String) -> Dictionary:" in source
    authoring = source[source.index("const PRESET_AUTHORING"):]
    authoring = authoring[:authoring.index("\n}\n")]
    assert '"simple_house"' in authoring
    assert '"two_storey_house"' in authoring
    assert '"ignition_object_id": "salon_sofa"' in authoring


@pytest.mark.parametrize("builder", ["create_simple_house", "create_two_storey_house"])
def test_the_validated_builders_declare_no_ignition_focus(builder: str):
    """La plantilla desnuda es la que miden los casos: sin foco marcado."""
    assert "is_primary_ignition_source" not in _builder_body(builder)


def test_the_simple_house_builder_declares_no_player_start_either():
    """`create_simple_house` es la plantilla de los dos casos FDS calibrados.

    Se mantiene byte a byte como estaba: cualquier añadido aquí, aunque sea
    inerte para la física, rompe el argumento de identidad de §7.3.
    """
    body = _builder_body("create_simple_house")
    assert "player_start" not in body
    assert "ignition_room_id" not in body


@pytest.mark.parametrize("path", PRODUCT_CALLERS, ids=lambda p: p.name)
def test_product_entry_points_use_the_authored_preset(path: Path):
    source = _read(path)
    assert "create_product_preset(" in source, (
        "%s es una ruta de producto y debe pedir el preset con su contenido de autor"
        % path.name
    )
    assert "create_by_name(" not in source, (
        "%s ya no debe construir el preset desnudo" % path.name
    )


@pytest.mark.parametrize("path", VALIDATION_CALLERS, ids=lambda p: p.name)
def test_validation_entry_points_keep_the_bare_template(path: Path):
    source = _read(path)
    assert "create_by_name(" in source
    assert "create_product_preset(" not in source, (
        "%s construye casos de validación: no puede heredar contenido de autor"
        % path.name
    )


def test_the_fds_cases_still_build_from_the_shared_template():
    """Si dejaran de usar `template`, esta separación ya no haría falta."""
    for name in ("fds_simple_house_default", "fds_simple_house_calibrated"):
        case = json.loads(
            (ROOT / "sim/validation/cases" / (name + ".json")).read_text(encoding="utf-8"))
        assert case["template"] == "simple_house"


def test_the_distributed_scenario_declares_room_and_object():
    """Lo que D-2 pedía, en el JSON que se distribuye."""
    data = json.loads(
        (ROOT / "scenarios/preset_simple_house.json").read_text(encoding="utf-8"))
    assert data["ignition_room_id"] == 0
    marked = [
        obj["id"]
        for room in data["rooms_data"]
        for obj in room.get("fuel_objects", [])
        if obj.get("is_primary_ignition_source")
    ]
    assert marked == ["salon_sofa"]


@pytest.mark.parametrize(
    "name", ["preset_simple_house", "preset_two_storey_house"])
def test_the_distributed_scenarios_declare_a_first_person_start(name: str):
    data = json.loads(
        (ROOT / "scenarios" / (name + ".json")).read_text(encoding="utf-8"))
    start = data["player_start"]
    room_id = start["room_id"]
    rect = data["room_rect_m"][str(room_id)]
    local = start["position_m"]
    # `position_m` es local a la sala: tiene que caber dentro del rectángulo,
    # y con holgura para el radio de la cápsula del jugador (0,24 m).
    assert 0.24 <= local["x"] <= rect["w"] - 0.24
    assert 0.24 <= local["y"] <= rect["h"] - 0.24
    assert room_id != data["ignition_room_id"], "no se empieza dentro del fuego"


def test_the_exporter_writes_the_scenarios_from_the_product_path():
    """Una exportación futura tiene que reproducir el contenido de autor."""
    source = _read(EXPORTER)
    match = re.search(r"var data: Dictionary = builder\.(\w+)\(preset_id\)", source)
    assert match is not None, "no se encontró la llamada del generador"
    assert match.group(1) == "create_product_preset"
