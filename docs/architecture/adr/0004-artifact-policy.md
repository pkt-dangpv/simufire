# ADR 0004: Artifact and Baseline Policy

## Status

Accepted.

## Context

El repositorio acumuló logs, temporales, snapshots y salidas generadas en la raíz. Algunas baselines sí son parte del proyecto; otros artefactos solo sirven como histórico.

## Decision

- Caches, logs y salidas locales quedan ignorados por Git.
- Artefactos históricos conservados van a `docs/archive/`.
- Baselines científicas oficiales van a `sim/validation/baselines/`.
- Casos de validación oficiales van a `sim/validation/cases/`.
- Escenarios de usuario/producto van a `scenarios/`.

## Consequences

La raíz queda limpia. Si un artefacto generado se vuelve fuente oficial, debe moverse a una carpeta de dominio y documentarse.
