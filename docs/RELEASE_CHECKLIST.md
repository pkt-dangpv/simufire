# Release Checklist

Usa esta lista antes de etiquetar o publicar una versión.

El [plan vigente](PLAN_PUBLICACION_2026-10-30.md) retira el 30 de octubre
como fecha objetivo. Esta lista solo se ejecuta para una release candidate
cuando G0-G5 tengan evidencia y decisión documentadas.

## Gates previos a la release candidate

- [ ] G0: declarar escenarios, regímenes, usuarios y salidas comprendidos en
  el ámbito; asociar cada afirmación física a evidencia y límite de validez.
- [ ] G1: revisar balances, pasos descartados, suite de referencia fresca y
  relevancia de cada gap para ese ámbito; no equiparar PASS con validación externa.
- [ ] G2: decidir por separado D1/R3/D2/D3 y sus interacciones usando datos
  experimentales, sensibilidad e incertidumbre. Mantener experimental lo que
  no supere el gate; no activarlo por calendario.
- [ ] G3: validar o acotar FED/CO y SVV, incluida la diferencia entre dosis,
  tenabilidad actual y peor estado histórico en UI y logs.
- [ ] G4: registrar prueba visual y funcional reproducible, escenarios largos,
  rendimiento, errores y procesos residuales en el equipo soportado.
- [ ] G5: producir y verificar exportación Windows reproducible en una
  instalación limpia, sin dependencias del entorno de desarrollo.
- [ ] G6: congelar física, ejecutar batería final y publicar limitaciones
  explícitas. Cualquier NO-GO bloquea o reduce el ámbito anunciado.

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
