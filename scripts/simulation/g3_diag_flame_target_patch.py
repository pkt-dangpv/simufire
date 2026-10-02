#!/usr/bin/env python3
"""The diagnostic flame-target block of ``CombustionSystem.gd``, as text.

Design section 13. The block lives in ``sim/fire/CombustionSystem.gd``; this
module holds the same three insertions so that the **pre-option-D** copy of
that file, used for the ON-pre control in a diagnostic project copy under
``runs/``, receives exactly the same code. ``apply`` never touches the
worktree's ``sim/``: it is only pointed at such a copy.

``matches`` is what the tests use to prove the worktree file carries the
block verbatim.
"""

from __future__ import annotations

from pathlib import Path


CONSTANTS_ANCHOR = '''const G3_OWNERSHIP_SWITCH: String = "fire_explicit_object_fuel_ownership_enabled"
'''
CONSTANTS = '''
# G3 DIAGNÓSTICO (OFF por defecto; NO es física de producto). Hace continuo el
# objetivo de llama alrededor del umbral can_flame para aislar el efecto de su
# salto. Solo se fija desde engine_overrides de un escenario de diagnóstico.
# Diseño: G3_ENERGY_DELAY_DESIGN §13.
const G3_DIAG_FLAME_TARGET_WINDOW: String = "fire_diag_flame_target_window"
const G3_DIAG_FLAME_TARGET_JUMP_FRACTION: String = "fire_diag_flame_target_jump_fraction"
# El mismo umbral que `can_flame = flame_drive > 0.08`; aquí no se decide can_flame.
const G3_DIAG_CAN_FLAME_DRIVE: float = 0.08
'''

CALL_ANCHOR = '''	if can_flame:
		fresh_flame_target_kw = minf(
			solid_pyrolysis_kw,
			ideal_hrr_kw * clampf(flame_drive, 0.0, 1.0)
		)
'''
CALL = '''		# G3 DIAGNÓSTICO (clave ausente o 0: no se ejecuta nada de esto). Dentro de
		# la ventana (umbral, umbral + ancho) sustituye el objetivo de llama por una
		# recta que une el valor del umbral con el original en el borde superior.
		# No cambia can_flame, pirólisis, filtro, recorte de D, O2 ni especies.
		var g3_diag_window: float = float(context.get(G3_DIAG_FLAME_TARGET_WINDOW, 0.0))
		if g3_diag_window > 0.0:
			# El rescoldo que la regla da justo por debajo del umbral.
			var g3_diag_smolder_kw: float = 0.0
			if latent_viable:
				g3_diag_smolder_kw = minf(
					residual_smolder_cap_kw,
					solid_pyrolysis_kw * smolder_fraction * lerpf(0.40, 1.0, subvent_engagement)
				)
			var g3_diag_jump_fraction: float = clampf(
				float(context.get(G3_DIAG_FLAME_TARGET_JUMP_FRACTION, 0.0)), 0.0, 1.0
			)
			var g3_diag_original_kw: float = fresh_flame_target_kw
			fresh_flame_target_kw = minf(
				solid_pyrolysis_kw,
				g3_diag_flame_target_kw(
					g3_diag_original_kw, ideal_hrr_kw, flame_drive,
					g3_diag_smolder_kw, g3_diag_window, g3_diag_jump_fraction
				)
			)
			if g3_fuel_ledger_enabled and flame_drive < G3_DIAG_CAN_FLAME_DRIVE + g3_diag_window:
				_g3_ledger_note(room, {"diag_flame_target": {
					"window": g3_diag_window,
					"jump_fraction": g3_diag_jump_fraction,
					"flame_drive": flame_drive,
					"ideal_kw": ideal_hrr_kw,
					"smolder_at_threshold_kw": g3_diag_smolder_kw,
					"original_target_kw": g3_diag_original_kw,
					"target_kw": fresh_flame_target_kw,
				}})
'''

FUNCTION_ANCHOR = '''func _g3_ledger_note(room: RoomModel, values: Dictionary) -> void:
'''
FUNCTION = '''## G3 DIAGNÓSTICO (no es física de producto). Objetivo de llama con la clave:
## fuera de la ventana (umbral, umbral + ancho) devuelve el original sin tocar;
## dentro, la recta entre
##   - el umbral:  rescoldo + fracción_de_salto · (ideal · umbral − rescoldo)
##   - el borde:   ideal · (umbral + ancho), el valor de la regla original.
## Con fracción 0 es continuo en el umbral; con fracción 1 es la regla original.
static func g3_diag_flame_target_kw(
	original_kw: float,
	ideal_kw: float,
	flame_drive: float,
	smolder_at_threshold_kw: float,
	window: float,
	jump_fraction: float
) -> float:
	var outside_window: bool = (
		flame_drive <= G3_DIAG_CAN_FLAME_DRIVE
		or flame_drive >= G3_DIAG_CAN_FLAME_DRIVE + window
	)
	if window <= 0.0 or outside_window:
		return original_kw
	var at_threshold_kw: float = lerpf(
		smolder_at_threshold_kw, ideal_kw * G3_DIAG_CAN_FLAME_DRIVE, jump_fraction
	)
	var at_window_top_kw: float = ideal_kw * (G3_DIAG_CAN_FLAME_DRIVE + window)
	return lerpf(
		at_threshold_kw, at_window_top_kw, (flame_drive - G3_DIAG_CAN_FLAME_DRIVE) / window
	)


'''


def patched(source: str) -> str:
    """``source`` with the three insertions; raises if an anchor is not unique."""
    for anchor in (CONSTANTS_ANCHOR, CALL_ANCHOR, FUNCTION_ANCHOR):
        if source.count(anchor) != 1:
            raise ValueError(f"anchor found {source.count(anchor)} times: {anchor[:40]!r}")
    source = source.replace(CONSTANTS_ANCHOR, CONSTANTS_ANCHOR + CONSTANTS)
    source = source.replace(CALL_ANCHOR, CALL_ANCHOR + CALL)
    return source.replace(FUNCTION_ANCHOR, FUNCTION + FUNCTION_ANCHOR)


def stripped(source: str) -> str:
    """``source`` without the three insertions (the inverse of ``patched``)."""
    for block in (CONSTANTS, CALL, FUNCTION):
        if source.count(block) != 1:
            raise ValueError("diagnostic block missing or duplicated")
        source = source.replace(block, "")
    return source


def matches(path: Path) -> bool:
    """Whether the file carries exactly the block and is otherwise untouched by it."""
    source = Path(path).read_text(encoding="utf-8")
    return patched(stripped(source)) == source


def apply(path: Path) -> None:
    path = Path(path)
    path.write_text(patched(path.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
