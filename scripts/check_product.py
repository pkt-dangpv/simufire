"""check_product.py — Product/editor guardrails for SimuFire.

Runs editor/product tests plus lightweight Godot geometry checks. This script
is intentionally SEPARATE from the scientific validation pipeline:

  Product/editor checks:   python scripts/check_product.py        ← this file
  Scientific guardrails:   python scripts/simulation/validation_guardrails.py
  Scientific full suite:   python scripts/simulation/validate_reference_cases.py

The separation ensures that failures in editor tooling are visible and
tracked without polluting the scientific validation signal.

Exit codes:
    0 — all product tests PASS
    1 — one or more product tests FAIL
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
_GODOT_CANDIDATES = [
    Path("C:/Users/dangp/Desktop/Godot_v4.7.1-stable_win64_console.exe"),
    Path("F:/OneDrive/Escritorio/Godot_v4.7.1-stable_win64_console.exe"),
]

# En Windows, piped stdout puede usar cp1252; reconfigure para UTF-8 si disponible
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Godot no devuelve codigo de error cuando un script del que depende la
# comprobacion no compila: la comprobacion arranca, sus `new()` devuelven null,
# nadie apunta un fallo y el guardarrail imprime su PASS **sin haber mirado
# nada**. Cazado el 2026-09-11 en validate_landing_surfaces, y vale para las 49.
#
# Por eso el token de exito no basta: si en la salida hay un fallo de
# compilacion, la comprobacion no cuenta como pasada aunque lo diga.
_COMPILE_FAILURE_MARKERS = (
    "Parse Error:",
    "Compile Error:",
    "Failed to compile depended scripts",
    "Compilation failed",
    "Failed to load script",
)


def _compile_failure(output: str) -> str:
    for marker in _COMPILE_FAILURE_MARKERS:
        if marker in output:
            for line in output.splitlines():
                if marker in line:
                    return line.strip()
            return marker
    return ""


def _run_python_script(script_path: Path, success_token: str) -> tuple[int, int, int, str]:
    """
    Run a plain Python check script and look for its success token.
    Returns (exit_code, checks_run, failures, diagnostic).
    """
    result = subprocess.run(
        [sys.executable, str(script_path)],
        capture_output=True,
        text=True,
        cwd=str(_REPO_ROOT),
    )
    combined = (result.stdout or "") + (result.stderr or "")
    passed = result.returncode == 0 and success_token in combined
    return result.returncode, 1, 0 if passed else 1, "" if passed else combined.strip()


def _run_test(module_path: Path) -> tuple[int, int, int]:
    """
    Run a stdlib unittest module as a subprocess.
    Returns (exit_code, tests_run, failures+errors).
    """
    result = subprocess.run(
        [sys.executable, str(module_path)],
        capture_output=True,
        text=True,
        cwd=str(_REPO_ROOT),
    )
    combined = result.stderr + result.stdout
    tests_run = 0
    fails = 0
    for line in combined.splitlines():
        m = re.match(r"Ran (\d+) test", line)
        if m:
            tests_run = int(m.group(1))
        m = re.search(r"failures=(\d+)", line)
        if m:
            fails += int(m.group(1))
        m = re.search(r"errors=(\d+)", line)
        if m:
            fails += int(m.group(1))
    return result.returncode, tests_run, fails


def _find_godot() -> Path | None:
    env_path = os.environ.get("GODOT_EXE")
    if env_path:
        candidate = Path(env_path)
        if candidate.exists():
            return candidate

    for candidate in _GODOT_CANDIDATES:
        if candidate.exists():
            return candidate

    path_hit = shutil.which("godot")
    if path_hit:
        return Path(path_hit)
    return None


# Limite por defecto de las comprobaciones de Godot.
#
# Estaba en 60 s, y en esta maquina las mas pesadas tardan mas: medido el
# 2026-09-11, `validate_landing_surfaces` ~130 s y `validate_furniture_layout`
# ~101 s, y **lo mismo con el codigo de HEAD que con el actual**, asi que no era
# una regresion: el limite estaba mal puesto. Un limite generoso solo cuesta
# tiempo cuando algo se cuelga de verdad; uno corto convierte una comprobacion
# lenta en un fallo que no existe.
_GODOT_TIMEOUT_S: int = 300


def _run_godot_scene(scene_path: str, success_token: str, timeout_s: int = _GODOT_TIMEOUT_S) -> tuple[int, int, int, str]:
    """
    Run a small Godot headless product check scene.
    Returns (exit_code, checks_run, failures, diagnostic).
    """
    godot = _find_godot()
    if godot is None:
        return 1, 1, 1, "Godot not found. Set GODOT_EXE or add godot to PATH."

    # Un limite superado es UNA comprobacion fallida, no el final de la suite.
    # Antes reventaba con un TimeoutExpired sin capturar y se perdian los
    # resultados de todas las demas.
    try:
        result = subprocess.run(
            [
                str(godot),
                "--headless",
                "--path",
                str(_REPO_ROOT),
                scene_path,
            ],
            capture_output=True,
            text=True,
            cwd=str(_REPO_ROOT),
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        return 1, 1, 1, "se paso del limite de %d s (%s)" % (timeout_s, scene_path)
    combined = (result.stdout or "") + (result.stderr or "")
    broken = _compile_failure(combined)
    passed = result.returncode == 0 and success_token in combined and not broken
    diagnostic = ""
    if broken:
        diagnostic = "un script no compila, asi que el PASS no vale: " + broken
    elif not passed:
        diagnostic = combined.strip()
    return result.returncode, 1, 0 if passed else 1, diagnostic


def _run_godot_script(script_path: str, success_token: str, timeout_s: int = _GODOT_TIMEOUT_S) -> tuple[int, int, int, str]:
    """
    Run a headless Godot SceneTree script (--script) product check.
    Returns (exit_code, checks_run, failures, diagnostic).
    """
    godot = _find_godot()
    if godot is None:
        return 1, 1, 1, "Godot not found. Set GODOT_EXE or add godot to PATH."

    try:
        result = subprocess.run(
            [
                str(godot),
                "--headless",
                "--path",
                str(_REPO_ROOT),
                "--script",
                script_path,
            ],
            capture_output=True,
            text=True,
            cwd=str(_REPO_ROOT),
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        return 1, 1, 1, "se paso del limite de %d s (%s)" % (timeout_s, script_path)
    combined = (result.stdout or "") + (result.stderr or "")
    broken = _compile_failure(combined)
    passed = result.returncode == 0 and success_token in combined and not broken
    diagnostic = ""
    if broken:
        diagnostic = "un script no compila, asi que el PASS no vale: " + broken
    elif not passed:
        diagnostic = combined.strip()
    return result.returncode, 1, 0 if passed else 1, diagnostic


def _run_run_scenario_smoke() -> tuple[int, int, int, str]:
    """
    Exercise scripts/run_scenario.py end-to-end with a short headless run.
    Returns (exit_code, checks_run, failures, diagnostic).
    """
    scenario_path = _REPO_ROOT / "sim" / "validation" / "cases" / "victim_fed_incapacitation.json"
    with tempfile.TemporaryDirectory(prefix="simufire_run_scenario_") as tmpdir:
        result = subprocess.run(
            [
                sys.executable,
                str(_REPO_ROOT / "scripts" / "run_scenario.py"),
                str(scenario_path),
                "--duration",
                "5",
                "--out-dir",
                tmpdir,
                "--timeout",
                "90",
            ],
            capture_output=True,
            text=True,
            cwd=str(_REPO_ROOT),
            timeout=120,
        )
        combined = (result.stdout or "") + (result.stderr or "")
        passed = result.returncode == 0 and "[run_scenario] PASS" in combined
        diagnostic = "" if passed else combined.strip()
        return result.returncode, 1, 0 if passed else 1, diagnostic


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    W = 72
    print()
    print("=" * W)
    print("  Product Guardrails — SimuFire")
    print("  (Editor + product checks — independent of physics simulation)")
    print("=" * W)
    print()

    suites = [
        (
            "Editor/scenario JSON tests",
            _REPO_ROOT / "tests" / "test_editor_scenarios.py",
            "python tests/test_editor_scenarios.py",
        ),
        (
            "Guardrail script unit tests",
            _REPO_ROOT / "tests" / "test_guardrails.py",
            "python tests/test_guardrails.py",
        ),
        (
            "UI localization tests",
            _REPO_ROOT / "tests" / "test_ui_localization.py",
            "python tests/test_ui_localization.py",
        ),
        (
            "Godot editability tests",
            _REPO_ROOT / "tests" / "test_godot_editability.py",
            "python tests/test_godot_editability.py",
        ),
        (
            "ILV layer coherence unit tests",
            _REPO_ROOT / "tests" / "test_ilv_layer_coherence.py",
            "python tests/test_ilv_layer_coherence.py",
        ),
    ]

    rows = []
    diagnostics = []
    for label, path, command in suites:
        rc, count, fails = _run_test(path)
        rows.append((label, rc, count, fails))
        if rc != 0:
            diagnostics.append(command)

    # Estilo y salud del GDScript de la linea visual: codigo muerto, parametros
    # sin tipo, trazas olvidadas. Cada regla se puso tras encontrar su fallo.
    rc, count, fails, diagnostic = _run_python_script(
        _REPO_ROOT / "scripts" / "check_gdscript_style.py",
        "[check_gdscript_style] PASS",
    )
    rows.append(("Estilo del GDScript visual", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("python scripts/check_gdscript_style.py --detail")

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_stairs_geometry.tscn",
        "STAIR GEOMETRY VALIDATION PASS",
    )
    rows.append(("Stair geometry Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot stair geometry: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_view_geometry_parity.tscn",
        "VIEW GEOMETRY PARITY VALIDATION PASS",
    )
    rows.append(("View geometry parity Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot view geometry parity: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_object_catalog.gd",
        "OBJECT CATALOG VALIDATION PASS",
    )
    rows.append(("Catalogo de objetos del editor Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot catalogo de objetos: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_wind_controls.gd",
        "WIND CONTROLS VALIDATION PASS",
    )
    rows.append(("Mandos del viento Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot mandos del viento: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_exterior_occlusion.tscn",
        "EXTERIOR OCCLUSION VALIDATION PASS",
    )
    rows.append(("Fondo tapado desde la ventana Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot fondo tapado: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_building_height.tscn",
        "BUILDING HEIGHT VALIDATION PASS",
    )
    rows.append(("Altura del edificio Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot altura del edificio: " + (diagnostic or "failed"))

    # La comprobacion mas cara de la suite: monta el mundo FP siete veces y lanza
    # 2448 rayos en cada una (~130 s medidos el 2026-09-11). Le vale el limite
    # general; queda anotado para que nadie lo baje sin medir.
    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_landing_surfaces.tscn",
        "LANDING SURFACES VALIDATION PASS",
    )
    rows.append(("Landing surfaces Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot landing surfaces: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_landing_stairs.tscn",
        "FP LANDING STAIRS VALIDATION PASS",
    )
    rows.append(("FP landing stairs Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP landing stairs: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_exterior_context.tscn",
        "FP EXTERIOR CONTEXT VALIDATION PASS",
    )
    rows.append(("FP exterior context Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP exterior context: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_technical_summary.tscn",
        "TECHNICAL SUMMARY VALIDATION PASS",
    )
    rows.append(("Technical summary Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot technical summary: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_furniture_runtime.tscn",
        "FURNITURE RUNTIME VALIDATION PASS",
    )
    rows.append(("Furniture runtime Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot furniture runtime: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_exterior_city.tscn",
        "EXTERIOR CITY VALIDATION PASS",
    )
    rows.append(("Exterior city Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot exterior city: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_furniture_layout.tscn",
        "FURNITURE LAYOUT VALIDATION PASS",
    )
    rows.append(("Furniture layout Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot furniture layout: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_3d_door_opening_visuals.tscn",
        "3D DOOR OPENING VISUALS VALIDATION PASS",
    )
    rows.append(("3D door opening visuals Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot 3D door opening visuals: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_3d_technical_overlays.tscn",
        "3D TECHNICAL OVERLAYS VALIDATION PASS",
    )
    rows.append(("3D technical overlays Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot 3D technical overlays: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_3d_screenshot_export.tscn",
        "3D SCREENSHOT EXPORT VALIDATION PASS",
    )
    rows.append(("3D screenshot export Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot 3D screenshot export: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_runtime_template_schema.tscn",
        "RUNTIME TEMPLATE SCHEMA VALIDATION PASS",
    )
    rows.append(("Runtime template schema Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot runtime template schema: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_editor_load_error_dialog.tscn",
        "EDITOR LOAD ERROR DIALOG VALIDATION PASS",
    )
    rows.append(("Editor load error dialog Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor load error dialog: " + (diagnostic or "failed"))

    # Vista previa 3D del catalogo de mobiliario: cada pieza se puede
    # previsualizar y la ficha dice lo que se esta viendo.
    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_object_preview.gd",
        "[validate_object_preview] PASS",
    )
    rows.append(("Vista previa del catalogo Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot object preview: " + (diagnostic or "failed"))

    # Idioma de la interfaz y configuracion del programa: el castellano se ve
    # en castellano, el ingles en ingles, y lo elegido se guarda.
    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_localization.gd",
        "[validate_localization] PASS",
    )
    rows.append(("Idioma y configuracion Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot localization: " + (diagnostic or "failed"))

    # Pasillos: una U son tramos que se leen como un pasillo, se unen solos y
    # ese paso se puede convertir en puerta. Y la forma se puede forzar.
    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_corridors.gd",
        "[validate_corridors] PASS",
    )
    rows.append(("Pasillos y tipo de abertura Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot corridors: " + (diagnostic or "failed"))

    # Comportamiento del editor al colocar: vuelta a Seleccion, balcon
    # dibujado y la ficha de la sala pegada a la sala al girarla.
    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_editor_interaction.gd",
        "[validate_editor_interaction] PASS",
    )
    rows.append(("Comportamiento del editor Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor interaction: " + (diagnostic or "failed"))

    # N-2: la herramienta de patio. Un conducto que atraviesa todas las plantas
    # y remata abierto al cielo; si se rompe el encadenado deja de ser un patio.
    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_patio.gd",
        "[validate_patio] PASS",
    )
    rows.append(("Patio de luces Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot patio: " + (diagnostic or "failed"))

    # El portal: el rellano y la caja de escalera como recinto. Si la puerta del
    # piso vuelve a dar al ambiente, el humo deja de subir por la escalera.
    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_portal.gd",
        "[validate_portal] PASS",
    )
    rows.append(("Portal y caja de escalera Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot portal: " + (diagnostic or "failed"))

    # Las tres ranuras de textura propia del inspector. Una foto puesta a mano
    # manda sobre el interruptor de ruido procedural: si vuelven a compartir
    # puerta, la ranura se vacia en silencio y el mundo sale con el procedural.
    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_texture_overrides.gd",
        "[validate_texture_overrides] PASS",
    )
    rows.append(("Texturas propias Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot texturas: " + (diagnostic or "failed"))

    # El humo que sube por el patio, visto DESDE FUERA del patio. El resto del
    # humo de primera persona es de camara y deja el conducto limpio al mirarlo
    # por la ventana, que es justo donde tiene que leerse como una chimenea.
    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_patio_smoke.gd",
        "[validate_patio_smoke] PASS",
    )
    rows.append(("Humo del patio Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot humo del patio: " + (diagnostic or "failed"))

    # A QUE DA cada abertura. El modelo solo sabe si el otro lado es una sala o
    # el ambiente, y con eso la puerta de un piso -que da a un rellano cerrado-
    # era el mismo dato que la entrada de una unifamiliar a la calle.
    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_opening_kinds.gd",
        "[validate_opening_kinds] PASS",
    )
    rows.append(("Tipos de abertura Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot tipos de abertura: " + (diagnostic or "failed"))

    # Y por donde sale el penacho, medido sobre el visor construido.
    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_exterior_plume.tscn",
        "[validate_exterior_plume] PASS",
    )
    rows.append(("Penacho exterior Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot penacho: " + (diagnostic or "failed"))

    # D-6: las sondas montan el escenario por el camino real. El editor tiene
    # un solo sitio donde se adopta un escenario, y nadie inyecta el
    # diccionario a mano: si lo hace, las fotos y las medidas mienten.
    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_probe_paths.gd",
        "[validate_probe_paths] PASS",
    )
    rows.append(("Sondas por el camino real Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot probe paths: " + (diagnostic or "failed"))

    # N-1, balcones del edificio del jugador: se construye lo que se declara,
    # y al balcon NO se puede salir.
    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_balconies.tscn",
        "[validate_balconies] PASS",
    )
    rows.append(("Balcones del edificio Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot balconies: " + (diagnostic or "failed"))

    # La convencion de plantas -R, R+1, R+2- es la misma en el editor, el
    # serializador, el minimapa y el selector del 2D, y un escenario guardado
    # con la convencion vieja (PB / P1) se relee con la nueva.
    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_floor_naming.gd",
        "[validate_floor_naming] PASS",
    )
    rows.append(("Nombres de plantas Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot floor naming: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_main_menu_scene.gd",
        "[validate_main_menu] PASS",
    )
    rows.append(("Menu principal en escena Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot main menu scene: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_editor_scene_complete.gd",
        "[validate_editor_scene] PASS",
    )
    rows.append(("UI del editor 100% en escena Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor scene complete: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_editor_ui_affordances.gd",
        "[validate_editor_ui] PASS",
    )
    rows.append(("Mandos del editor explicados Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor UI affordances: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_fire_visuals.tscn",
        "FP FIRE VISUALS VALIDATION PASS",
    )
    rows.append(("FP fire visuals Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP fire visuals: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_3d_smoke_opening_curtain.tscn",
        "3D SMOKE OPENING CURTAIN VALIDATION PASS",
        timeout_s=180,
    )
    rows.append(("3D smoke opening curtain Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot 3D smoke opening curtain: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_interstitial_seal.tscn",
        "FP INTERSTITIAL SEAL VALIDATION PASS",
    )
    rows.append(("FP interstitial seal Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP interstitial seal: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_party_walls.tscn",
        "FP PARTY WALLS VALIDATION PASS",
    )
    rows.append(("FP party walls Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP party walls: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_surface_shading.tscn",
        "FP SURFACE SHADING VALIDATION PASS",
    )
    rows.append(("FP surface shading Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP surface shading: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_smoke_lighting.tscn",
        "FP SMOKE LIGHTING VALIDATION PASS",
    )
    rows.append(("FP smoke lighting Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP smoke lighting: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_technical_hud.tscn",
        "FP TECHNICAL HUD VALIDATION PASS",
    )
    rows.append(("FP technical HUD Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP technical HUD: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_victim_states.tscn",
        "FP VICTIM STATES VALIDATION PASS",
    )
    rows.append(("FP victim states Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP victim states: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_player_start.tscn",
        "FP PLAYER START VALIDATION PASS",
    )
    rows.append(("FP player start Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP player start: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_detector_alarm.tscn",
        "FP DETECTOR ALARM VALIDATION PASS",
    )
    rows.append(("FP detector alarm Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP detector alarm: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_stance_easing.tscn",
        "FP STANCE EASING VALIDATION PASS",
    )
    rows.append(("FP stance easing Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP stance easing: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_combustion_regime.tscn",
        "COMBUSTION REGIME VALIDATION PASS",
    )
    rows.append(("Combustion regime Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot combustion regime: " + (diagnostic or "failed"))

    # El 3D en vivo mientras se dibuja en planta: que se encienda, comparta mundo
    # y se rehaga al soltar cada cambio.
    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_editor_live_3d.tscn",
        "[validate_editor_live_3d] PASS",
    )
    rows.append(("3D en vivo del editor Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor live 3D: " + (diagnostic or "failed"))

    # La escalera que dibuja una persona, subida por una persona. Las otras
    # guardias de escalera prueban el rellano del bloque, que se construye solo.
    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_editor_stairs_climbable.tscn",
        "[validate_editor_stairs] PASS",
    )
    rows.append(("Escalera dibujada se sube en FP Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor stairs climbable: " + (diagnostic or "failed"))

    # Dibujar EN la vista 3D, no solo mirarla: arrastrar sobre el suelo traza
    # salas y muros igual que en planta.
    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_editor_draw_in_3d.tscn",
        "[validate_editor_draw_in_3d] PASS",
    )
    rows.append(("Dibujo directo en 3D del editor Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor draw in 3D: " + (diagnostic or "failed"))

    # Los pasillos, con las formas que se dibujan de verdad: giro, U y el
    # pasillo que va por la junta entre dos habitaciones.
    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_editor_corridors.tscn",
        "[validate_editor_corridors] PASS",
    )
    rows.append(("Pasillos del editor Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor corridors: " + (diagnostic or "failed"))

    # Crear planta: vacia o copia de la actual, y que la copia suba obra y no
    # personas.
    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_editor_floor_copy.tscn",
        "[validate_editor_floor_copy] PASS",
    )
    rows.append(("Copiar planta en el editor Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor floor copy: " + (diagnostic or "failed"))

    # La revision de antes de arrancar: avisar de lo que hace inutil una
    # simulacion, y callar cuando el plano esta bien.
    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_editor_review.tscn",
        "[validate_editor_review] PASS",
    )
    rows.append(("Revisión del escenario Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor review: " + (diagnostic or "failed"))

    # El mobiliario se coge del catalogo y se suelta en el plano.
    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_editor_object_drag.tscn",
        "[validate_editor_object_drag] PASS",
    )
    rows.append(("Arrastrar mobiliario Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor object drag: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_editor_to_sim_flow.tscn",
        "EDITOR TO SIM FLOW VALIDATION PASS",
    )
    rows.append(("Editor to sim flow Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor to sim flow: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_run_scenario_smoke()
    rows.append(("Run scenario reproducibility", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("run_scenario smoke: " + (diagnostic or "failed"))

    print(f"  {'Suite':<38}  {'Resultado':>12}")
    print(f"  {'-'*38}  {'-'*12}")
    for label, rc, count, fails in rows:
        if rc == 0:
            tag = f"{count}/{count} OK"
            icon = "OK"
        else:
            tag = f"FAIL ({fails} fallo(s))"
            icon = "!!"
        print(f"  {label:<38}  {tag:>12}  [{icon}]")

    all_ok = all(rc == 0 for _, rc, _, _ in rows)
    total = sum(c for _, _, c, _ in rows)

    print()
    print("-" * W)
    print()
    if all_ok:
        print(f"  ALL PRODUCT CHECKS PASS  ({total} tests)")
    else:
        print("  PRODUCT CHECK(S) FAILED:")
        for label, rc, _, fails in rows:
            if rc != 0:
                print(f"    - {label}: {fails} fallo(s)")
        print()
        print("  Para diagnóstico:")
        for diagnostic in diagnostics:
            print(f"    {diagnostic}")
    print("=" * W)
    print()

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
