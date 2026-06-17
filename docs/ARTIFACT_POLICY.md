# Artifact Policy

Esta política define qué se versiona y qué se mantiene como salida local.

## Se Versiona

- Código fuente y escenas Godot necesarias.
- Escenarios oficiales en `scenarios/`.
- Casos y baselines oficiales en `sim/validation/`.
- Documentación vigente en `docs/`.
- Bibliografía local curada en `docs/literature/`.
- Artefactos históricos explícitos en `docs/archive/`.

## No Se Versiona

- Caches de Godot, Python o Matplotlib.
- Logs de ejecución.
- Salidas temporales `tmp_*`.
- Directorios `graphs/` y `runs/`.
- Exports generados localmente.
- Archivos `user://` copiados por accidente a la raíz.

## Excepciones

Puede conservarse un artefacto generado si cumple una de estas condiciones:

- es baseline oficial de validación;
- es evidencia histórica de una auditoría;
- es input reproducible de un experimento documentado;
- es bibliografía externa curada.

En esos casos debe moverse a una carpeta de dominio clara y enlazarse desde la documentación adecuada.
