# ADR 0003: Product and Scientific Validation Lanes

## Status

Accepted.

## Context

SimuFire tiene checks de producto/editor y validación científica. Mezclarlos vuelve confuso el diagnóstico: un fallo visual no significa fallo físico, y una divergencia científica no significa que el editor esté roto.

## Decision

Mantener carriles separados:

- Producto/editor: `python scripts/check_product.py`.
- Guardrails científicos rápidos: `python scripts/simulation/validation_guardrails.py`.
- Suite científica fresca: `sim/validation/run_reference_checks.ps1`.
- Two-Zone V1: `sim/validation/run_two_zone_v1_checks.ps1`.

## Consequences

Los informes deben indicar qué carril validan. CI puede ejecutar subconjuntos ligeros, pero no debe presentar un carril como sustituto del otro.
