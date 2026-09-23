"""Fase 1 FED/SVV: como se PRESENTAN el índice y la dosis, y solo eso.

Esta fase no toca el cálculo. Lo que estas pruebas vigilan es que la interfaz
deje de confundir el índice calculado ahora con su peor histórico, que no
fabrique ninguno de los dos cuando falta, y que no vuelva a atribuirles
desenlaces clínicos.
"""
from __future__ import annotations

import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parent.parent
PRESENTATION_PATH = ROOT / "ui/TenabilityPresentation.gd"
PRESENTATION = PRESENTATION_PATH.read_text(encoding="utf-8")
HUD_SUMMARY = (ROOT / "ui/HUDRoomSummary.gd").read_text(encoding="utf-8")
CHARTS = (ROOT / "ui/charts/NativeChartsWindow.gd").read_text(encoding="utf-8")
VISUALS_2D = (ROOT / "view/2d/rooms/RoomStateVisuals2D.gd").read_text(encoding="utf-8")
VISUALIZER = (ROOT / "view/2d/Visualizer.gd").read_text(encoding="utf-8")
PNG_GRAPHS = (ROOT / "scripts/generate_fire_graphs.py").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")

VALIDATOR = ROOT / "tools/validate_tenability_presentation.gd"
PASS_TOKEN = "TENABILITY PRESENTATION VALIDATION PASS"

GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)

# Superficies de presentación del índice. El log de texto queda FUERA de esta
# fase por enunciado y sigue pendiente (ver test al final).
PRESENTATION_SURFACES = (
    "ui/HUDRoomSummary.gd",
    "ui/charts/NativeChartsWindow.gd",
    "view/2d/Visualizer.gd",
    "view/2d/rooms/RoomStateVisuals2D.gd",
    "scripts/generate_fire_graphs.py",
)


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def _code_only(source: str) -> str:
    """Líneas de código, sin documentación ni comentarios."""
    kept = []
    for line in source.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("#") or stripped.startswith("##"):
            continue
        kept.append(line.split("  #", 1)[0])
    return "\n".join(kept)


# ------------------------------------------------------------
# No confundir actual con histórico
# ------------------------------------------------------------


def test_the_current_index_is_never_read_from_the_worst():
    """El defecto original: `svv_pct()` devolvía `svv_worst_pct`."""
    current = PRESENTATION.split(
        "static func current_index_pct(room_state: Dictionary) -> float:", 1
    )[1].split("\nstatic func ", 1)[0]
    assert "svv_pct" in current
    assert "svv_worst_pct" not in current, "el actual se lee del peor histórico"
    worst = PRESENTATION.split(
        "static func worst_index_pct(room_state: Dictionary) -> float:", 1
    )[1].split("\nstatic func ", 1)[0]
    assert "svv_worst_pct" in worst


def test_no_presentation_surface_shows_only_the_worst_as_if_current():
    """Cada superficie que enseña el índice enseña AMBOS, o ninguno."""
    for rel in PRESENTATION_SURFACES:
        code = _code_only((ROOT / rel).read_text(encoding="utf-8"))
        if "svv_worst_pct" not in code and "worst_index_pct" not in code:
            continue
        shows_both = (
            "compact_line" in code
            or "detail_lines" in code
            or ("current_index_pct" in code and "worst_index_pct" in code)
            # La gráfica sólo tiene la serie histórica en el CSV: se acepta
            # siempre que la nombre como histórica (se comprueba aparte).
            or rel.endswith("NativeChartsWindow.gd")
            or rel.endswith("generate_fire_graphs.py")
        )
        assert shows_both, f"{rel} enseña el peor histórico sin distinguirlo"


def test_the_old_ambiguous_accessor_is_gone():
    assert "static func svv_pct(" not in HUD_SUMMARY
    assert "current_index_pct" in HUD_SUMMARY
    assert "worst_index_pct" in HUD_SUMMARY


# ------------------------------------------------------------
# No fabricar un valor que falta
# ------------------------------------------------------------


def test_a_missing_field_is_reported_as_unavailable():
    assert 'const UNAVAILABLE_TEXT: String = "n/d"' in PRESENTATION
    for func in ("current_index_pct", "worst_index_pct"):
        body = PRESENTATION.split(
            f"static func {func}(room_state: Dictionary) -> float:", 1
        )[1].split("\nstatic func ", 1)[0]
        assert "return UNAVAILABLE" in body, func
        # Ni capa de 150 C, ni temperatura, ni el otro campo: nada que permita
        # reconstruir un número inventado.
        for forbidden in ("layer_150c", "temp_upper", "hot_layer", "height_m"):
            assert forbidden not in body, f"{func} fabrica desde {forbidden}"


def test_no_surface_rebuilds_the_index_from_the_layer():
    """Dos superficies replicaban la fórmula entera para rellenar huecos."""
    for rel in ("ui/HUDRoomSummary.gd", "view/2d/rooms/RoomStateVisuals2D.gd"):
        code = _code_only((ROOT / rel).read_text(encoding="utf-8"))
        assert "thermal_svv" not in code, rel
        assert "vis_svv" not in code, rel
        assert "fed_svv" not in code, rel


# ------------------------------------------------------------
# Nada de probabilidad médica
# ------------------------------------------------------------


def test_the_index_is_never_presented_as_survival_probability():
    """Se mira lo que el usuario LEE, no los comentarios.

    La documentación tiene que poder nombrar las etiquetas que prohíbe —si no,
    no puede explicar por qué se retiraron—, así que se examinan solo las
    cadenas del código.
    """
    for rel in PRESENTATION_SURFACES + ("ui/TenabilityPresentation.gd",):
        code = _code_only((ROOT / rel).read_text(encoding="utf-8"))
        readable = re.findall(r'"([^"]{3,})"', code)
        for piece in readable:
            lowered = piece.lower()
            for forbidden in (
                "% de supervivencia",
                "supervivencia estimada",
                "letal",
                "incap.",
            ):
                assert forbidden not in lowered, f"{rel}: {piece!r}"
            # La única mención admitida es la que lo NIEGA.
            if "probabilidad de supervivencia" in lowered:
                assert "no es una probabilidad de supervivencia" in lowered, (
                    f"{rel}: {piece!r}"
                )


def test_the_disclaimer_says_what_the_index_is_and_is_not():
    assert "Índice heurístico de condiciones" in PRESENTATION
    assert "No es una probabilidad de supervivencia" in PRESENTATION
    assert "TenabilityPresentationScript.DISCLAIMER" in HUD_SUMMARY


def test_fed_is_identified_as_accumulated_dose():
    assert "dosis acumulada" in PRESENTATION
    assert "dosis acumulada" in HUD_SUMMARY
    assert "dosis acumulada" in CHARTS or "dosis acumulada" in CHARTS.lower()


def test_the_clinical_thresholds_are_gone_but_the_curve_stays():
    for rel in ("ui/charts/NativeChartsWindow.gd", "scripts/generate_fire_graphs.py"):
        code = _code_only((ROOT / rel).read_text(encoding="utf-8"))
        assert "FED=1" not in code, rel
        assert "FED=3" not in code, rel
        # La curva FED sigue ahí.
        assert '"fed"' in code or 'r["fed"]' in code, rel


# ------------------------------------------------------------
# Gráficas
# ------------------------------------------------------------


def test_the_chart_labels_the_series_as_historical():
    assert "peor histórico" in CHARTS
    assert "Peor índice registrado" in CHARTS
    # Y no se inventa una serie «actual» que el CSV no trae.
    chart_block = CHARTS.split("const WANTED_COLS", 1)[0]
    assert '["svv_pct"' not in chart_block, "serie actual fabricada sin datos"


def test_visibility_is_charted_in_metres_apart_from_the_percentage_scale():
    assert '{"name": "Visibilidad (m)"' in CHARTS
    assert '["visibility_m", "Visibilidad", false, 1.0]' in CHARTS


def test_the_csv_contract_is_untouched():
    """Esta fase no cambia datos ni exportaciones."""
    wanted = CHARTS.split("const WANTED_COLS: Array = [", 1)[1].split("]", 1)[0]
    for column in ("fed", "svv_worst_pct", "visibility_m"):
        assert f'"{column}"' in wanted, column
    assert '"svv_pct"' not in wanted, "se añadió una columna al CSV"


# ------------------------------------------------------------
# El cálculo no se toca en esta fase
# ------------------------------------------------------------


def test_the_formulas_were_not_touched():
    """Los números de FED y del índice tienen que salir idénticos."""
    for marker in (
        "func step_fed(room: RoomModel, dt: float) -> void:",
        "func _compute_svv_pct_from_room(room: RoomModel) -> float:",
        "delta_co + delta_hcn + delta_hypoxia + delta_heat",
        "room.fed += maxf(0.0, delta_fed)",
        "room.svv_worst_pct = minf(room.svv_worst_pct, room.svv_pct)",
        "return clampf(minf(minf(thermal_svv, fed_svv), vis_svv) * 100.0, 0.0, 100.0)",
    ):
        assert marker in THERMAL, marker


def test_the_presentation_module_computes_nothing():
    code = _code_only(PRESENTATION)
    for forbidden in ("pow(", "exp(", "log(", "sqrt(", "layer_150c", "temp_upper"):
        assert forbidden not in code, forbidden


# ------------------------------------------------------------
# Lo que queda pendiente, escrito para que no se olvide
# ------------------------------------------------------------


def test_the_log_writer_remains_out_of_scope_and_pending():
    """`SimulationLogWriter` mantiene su propio cálculo y su etiqueta «SVV».

    Queda FUERA de esta fase por enunciado. Esta prueba lo fija como pendiente:
    si alguien lo toca, que sea a propósito y actualizando la documentación.
    """
    log_writer = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
    assert "SVV=%.0f%%" in log_writer
    assert "thermal_svv" in log_writer, "el cálculo duplicado del log sigue ahí"


def test_the_zonal_co_selection_is_untouched():
    """La asimetría del CO es de una fase posterior; aquí no se toca."""
    assert (
        "var co_ppm: float = compute_co_upper_ppm(room) if in_upper_layer "
        "else compute_co_ppm(room)"
    ) in THERMAL


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
        timeout_s=600,
        allowed_exit_codes={0},
    )
    assert PASS_TOKEN in completed.stdout, completed.stdout[-4000:]
