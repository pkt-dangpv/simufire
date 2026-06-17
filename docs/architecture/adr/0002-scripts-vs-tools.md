# ADR 0002: Scripts vs Tools

## Status

Accepted.

## Context

El proyecto mezcla comandos oficiales, validadores Godot, experimentos científicos y scripts exploratorios.

## Decision

- `scripts/`: comandos oficiales o casi oficiales ejecutables desde consola.
- `tools/`: validadores, escenas headless y utilidades técnicas.
- `tools/archive/`: scripts exploratorios conservados por trazabilidad.

Los comandos públicos se documentan en `docs/COMMANDS.md`.

## Consequences

Antes de promover un script a `scripts/`, debe tener rutas relativas a la raíz, errores comprensibles y documentación mínima.
