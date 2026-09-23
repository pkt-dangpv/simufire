"""F2.2D3: contracts for prescribed glazing fallout in the pressure network."""
from __future__ import annotations

import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parent.parent
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
TRANSPORT = (ROOT / "sim/core/PressureNetworkTransportSystem.gd").read_text(encoding="utf-8")
OPENING = (ROOT / "sim/building/OpeningModel.gd").read_text(encoding="utf-8")
ADAPTER = (ROOT / "sim/core/GlazingFalloutNetworkAdapter.gd").read_text(encoding="utf-8")
VALIDATOR = ROOT / "tools/validate_glazing_fallout_network.gd"

FLAG = "glazing_fallout_enabled"
PASS_TOKEN = "GLAZING FALLOUT NETWORK VALIDATION PASS"
GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)


def _code_only(source: str) -> str:
    return "\n".join(
        line.split("  #", 1)[0]
        for line in source.splitlines()
        if not line.lstrip().startswith("#")
    )


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def test_flag_defaults_off_and_requires_the_authoritative_network():
    assert re.findall(rf"^@export var {FLAG}: bool = (\w+)$", ENGINE, re.M) == ["false"]
    assert f"if {FLAG} and not pressure_network_solver_enabled:" in ENGINE
    assert "glazing_fallout_requires_pressure_network" in ENGINE
    # F2.2D4B2B: el motor enciende el solver en UN solo sitio, y no en secreto.
    # Hasta D4B2A ningun camino lo encendia y la regla era que el texto no
    # apareciese. Ahora existe una ruta -la autorizacion experimental
    # explicita- y lo que se vigila es que sea la unica y que viva dentro de
    # ella, bajo el mapa de interruptores que devuelve el contrato.
    assert ENGINE.count("pressure_network_solver_enabled = true") == 1
    _activation = ENGINE.split(
        "func _apply_experimental_physics_authorization() -> void:", 1
    )[1].split("\nfunc ", 1)[0]
    assert "pressure_network_solver_enabled = true" in _activation
    assert "ExperimentalAuthorizationScript.REQUIRED_DEPENDENCY" in _activation
    assert (
        "if glazing_fallout_enabled and (not is_finite(time_s) or time_s < 0.0):"
        in TRANSPORT
    )


def test_engine_wires_d3_once_and_passes_authoritative_time():
    expected = (
        f"pressure_network_transport_system.{FLAG} = \\\n"
        f"\t\t\t{FLAG} and pressure_network_solver_enabled"
    )
    assert expected in ENGINE
    assert re.search(
        r"pressure_network_transport_system\.step\(\s*"
        r"building, dt, \{\}, sim_time_s\s*\)",
        ENGINE,
    )


def test_runtime_contract_is_separate_from_legacy_glass_state():
    assert "var glazing_panels: Array = []" in OPENING
    assert "var glazing_spatial: Array = []" in OPENING
    code = _code_only(ADAPTER)
    for forbidden in (
        "glass_broken", "mark_glass_broken", "open_fraction =", "set_open_fraction",
        "thermal_gap_fraction", "GlassFailureSystem", "glass_break_temp",
        "randf", "temperature", "temp_upper",
    ):
        assert forbidden not in code, forbidden


def test_adapter_consumes_3a_then_3b_and_never_reimplements_geometry():
    assert 'preload("res://sim/core/GlazingIntegrityModel.gd")' in ADAPTER
    assert 'preload("res://sim/core/GlazingOpeningGeometryModel.gd")' in ADAPTER
    assert "IntegrityModel.evaluate_panels(" in ADAPTER
    assert "GeometryModel.compute_open_geometry(" in ADAPTER
    code = _code_only(ADAPTER)
    for forbidden in ("free_cells", "_merge_cells", "fallout_fraction *", "min(", "average"):
        assert forbidden not in code, forbidden


def test_rectangles_become_large_openings_without_a_second_flow_law():
    assert '"flow_model": "large_opening"' in ADAPTER
    assert '"discharge_coeff": DISCHARGE_COEFFICIENT' in ADAPTER
    assert "const DISCHARGE_COEFFICIENT: float = 0.61" in ADAPTER
    code = _code_only(ADAPTER)
    for forbidden in ("sqrt(", "pow(", "bernoulli", "compute_flow", "delta_p"):
        assert forbidden not in code.lower(), forbidden


def test_host_placement_is_validated_and_panels_cannot_overlap():
    assert 'panel.has("host_x_m")' in ADAPTER
    assert 'panel \'%s\' lies outside the host opening' in ADAPTER
    assert "_check_panel_overlap(placements, errors)" in ADAPTER
    assert "if overlap_x and overlap_z:" in ADAPTER


def test_operational_opening_excludes_glazing_without_mutating_it():
    assert "var operationally_closed: bool = opening.is_closed()" in ADAPTER
    assert "if not operationally_closed:" in ADAPTER
    exclusion = ADAPTER.split("if not operationally_closed:", 1)[1].splitlines()[1:3]
    assert any("continue" in line for line in exclusion)
    snapshot = TRANSPORT.split("func build_snapshot", 1)[1]
    assert snapshot.index("GlazingAdapterScript.build_opening_elements(") < snapshot.index("if opening.is_closed()")
    assert "glazing_openings.append_array(glazing_elements)" in snapshot


def test_cracked_or_misaligned_multilayer_glass_cannot_be_bypassed_by_adapter():
    assert "GeometryModel.compute_open_geometry(" in ADAPTER
    assert 'if not bool(geometry["valid"]):' in ADAPTER
    assert 'output["elements"] = elements if errors.is_empty() else []' in ADAPTER


def test_exterior_glazing_gets_wind_once_at_rectangle_height():
    assert 'element["wind_dp_pa"] = _glazing_wind_dp_pa(' in TRANSPORT
    wind = TRANSPORT.split("func _glazing_wind_dp_pa", 1)[1].split("\nfunc ", 1)[0]
    assert wind.count("WindModelScript.wind_dp_pa(") == 1
    assert 'element["bottom_z_m"]' in wind and 'element["top_z_m"]' in wind


def test_no_distributed_scenario_enables_d3():
    hits: list[str] = []
    for pattern in ("*.tres", "*.tscn", "*.json", "*.cfg"):
        for path in ROOT.rglob(pattern):
            if any(part in {".git", "runs", "sim_out", "reports"} for part in path.parts):
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            if f"{FLAG} = true" in text or f'"{FLAG}": true' in text:
                hits.append(str(path.relative_to(ROOT)))
    assert hits == []


def test_validator_is_registered_in_product_checks():
    source = (ROOT / "scripts/check_product.py").read_text(encoding="utf-8")
    assert "validate_glazing_fallout_network.gd" in source
    assert PASS_TOKEN in source


def test_validator_passes():
    godot = _godot_exe()
    if godot is None:
        pytest.skip("Godot console executable not found")
    completed = run_godot(
        [str(godot), "--headless", "--path", str(ROOT), "--script", str(VALIDATOR)],
        timeout_s=900,
        allowed_exit_codes=(0,),
    )
    output = (completed.stdout or "") + (completed.stderr or "")
    assert PASS_TOKEN in output
    assert "SCRIPT ERROR" not in output
    assert "Parse Error" not in output
