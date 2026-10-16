"""Deshace, solo para comparar, el enrutado de sim/ por sim/core/DetMath.gd.

El 2026-10-15 todas las llamadas de sim/ a `exp`, `pow`, `sin`, `cos`, `tanh`,
`lerpf` e `inverse_lerp` pasaron a `DetMath.<función>` (números idénticos en
cualquier máquina; ver docs/validation/determinism/README.md), y cada archivo
afectado ganó la línea `const DetMath = preload(...)`. Las pruebas y registros
que comparan el código actual con un commit anterior, o que se anclan en un
fragmento exacto, usan `strip_detmath_routing` para seguir comprobando que no
cambió NADA más que ese enrutado.
"""

from __future__ import annotations

import re

DETMATH_PRELOAD_LINE = 'const DetMath = preload("res://sim/core/DetMath.gd")'
ROUTED_FUNCTIONS = ("exp", "pow", "sin", "cos", "tanh", "lerpf", "inverse_lerp")
_ROUTED_CALL = re.compile(r"\bDetMath\.(" + "|".join(ROUTED_FUNCTIONS) + r")\(")


def strip_detmath_routing(source: str) -> str:
    """Source as it was before the DetMath routing (same newlines as given)."""
    for newline in ("\r\n", "\n"):
        source = source.replace(DETMATH_PRELOAD_LINE + newline, "")
    return _ROUTED_CALL.sub(r"\1(", source)


def add_detmath_routing(fragment: str) -> str:
    """A pre-routing code fragment as it reads now (for exact-text anchors)."""
    pattern = re.compile(r"(?<![\w.])(" + "|".join(ROUTED_FUNCTIONS) + r")\(")
    return pattern.sub(r"DetMath.\1(", fragment)
