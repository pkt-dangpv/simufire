# Release Checklist

Usa esta lista antes de etiquetar o publicar una versión.

## Preparación

- Confirmar versión objetivo y commit base.
- Revisar `README.md`.
- Revisar `docs/INDEX.md` y `docs/COMMANDS.md`.
- Ejecutar `python scripts/check_docs_links.py`.
- Ejecutar `git diff --check`.

## Limpieza Local

- Previsualizar limpieza: `powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1 -WhatIf`.
- Limpiar si procede: `powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1`.
- No borrar `.godot/` si el editor está abierto.

## Producto

- Ejecutar `python scripts/check_product.py`.
- Revisar cualquier salida en `runs/` o `graphs/` antes de archivarla o descartarla.

## Validación Científica

- Ejecutar guardrails rápidos: `python scripts/simulation/validation_guardrails.py`.
- Si hubo cambios físicos o de validación, ejecutar suite fresca: `sim/validation/run_reference_checks.ps1`.
- Actualizar `docs/validation/STATUS_VALIDATION.md` si cambia el estado.
- Actualizar `docs/validation/GAPS_INVENTORY.md` si cambia el inventario.

## Documentación

- Actualizar changelog o nota de release si existe.
- Confirmar que nuevos documentos están enlazados desde `docs/INDEX.md`.
- Confirmar que comandos nuevos están en `docs/COMMANDS.md`.

## Cierre

- Revisar `git status --short`.
- Confirmar que no hay logs, caches ni temporales en raíz.
- Crear tag o release notes según el flujo del proyecto.
