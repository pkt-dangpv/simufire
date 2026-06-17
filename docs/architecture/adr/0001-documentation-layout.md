# ADR 0001: Documentation Layout

## Status

Accepted.

## Context

La documentación estaba distribuida entre raíz, `docs/`, histórico de sesiones, bibliografía externa y validación científica. Eso dificultaba encontrar la fuente vigente y hacía que el repositorio pareciera menos profesional.

## Decision

Organizar `docs/` por intención:

- `docs/validation/`
- `docs/audits/`
- `docs/architecture/`
- `docs/roadmaps/`
- `docs/planning/`
- `docs/sessions/`
- `docs/archive/`
- `docs/literature/`

La entrada principal será `docs/INDEX.md`.

## Consequences

Los enlaces internos deben mantenerse al mover documentos. La raíz del repositorio queda más limpia y la documentación tiene una ruta clara de descubrimiento.
