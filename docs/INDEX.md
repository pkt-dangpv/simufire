# SimuFire Documentation Index

Este índice separa la documentación vigente del histórico, bibliografía y artefactos archivados. La raíz del repositorio queda reservada para el proyecto Godot, configuración y entradas principales.

## Entradas Principales

- [COMMANDS.md](COMMANDS.md): comandos oficiales de producto, validación y ejecución.
- [HANDOFF_CURRENT_STATE.md](HANDOFF_CURRENT_STATE.md): estado actual para continuar desde otra máquina o sesión.
- [ESTADO_2026-09-10.md](ESTADO_2026-09-10.md): **punto de retomada vigente** de la línea visual y del editor (fases, pendientes, decisiones y trampas).
- [ESTADO_Y_PLAN_2026-09-09.md](ESTADO_Y_PLAN_2026-09-09.md): plan por fases con el porqué de cada tarea, marcado a medida que se cierran.
- [EDITOR_Y_ESCALA_2026-09-10.md](EDITOR_Y_ESCALA_2026-09-10.md): la tanda del editor y la escala en primera persona, con la causa de cada fallo.
- [HANDOFF_VISUAL_X8_2026-09-01.md](HANDOFF_VISUAL_X8_2026-09-01.md): registro de método de la línea visual; **X-8 se cerró el 2026-09-05** (z-fighting) y la bisección no llegó a hacer falta.
- [LOCAL_WORKSPACE.md](LOCAL_WORKSPACE.md): artefactos locales ignorados y limpieza segura.
- [RUN_WITHOUT_ARTIFACTS.md](RUN_WITHOUT_ARTIFACTS.md): cómo ejecutar checks y escenarios sin ensuciar la raíz.
- [ARTIFACT_POLICY.md](ARTIFACT_POLICY.md): política de artefactos, baselines y salidas locales.
- [LINK_AUDIT.md](LINK_AUDIT.md): auditoría y política práctica de enlaces Markdown.
- [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md): checklist para preparar publicaciones.
- [../CONTRIBUTING.md](../CONTRIBUTING.md): convenciones de organización, estilo y cambios.

## Validación

- [validation/SIMUFIRE_VALIDATION_SUMMARY_2026-05-31.md](validation/SIMUFIRE_VALIDATION_SUMMARY_2026-05-31.md): resumen de validación para terceros.
- [validation/STATUS_VALIDATION.md](validation/STATUS_VALIDATION.md): estado amplio de validación.
- [validation/CFAST_EQUIVALENCE_AUDIT_2026-06-19.md](validation/CFAST_EQUIVALENCE_AUDIT_2026-06-19.md): auditoría de equivalencia de los 15 fallos CFAST actuales.
- [validation/CFAST_GHANEKAR_MODEL_AUDIT_2026-06-19.md](validation/CFAST_GHANEKAR_MODEL_AUDIT_2026-06-19.md): auditoría de geometría/topología de modelos CFAST y Ghanekar.
- [validation/GAPS_INVENTORY.md](validation/GAPS_INVENTORY.md): inventario de gaps técnicos y científicos.
- [validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md](validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md): checklist maestro de credibilidad física del motor.
- [validation/GODOT_471_HEADLESS_CRASH_AUDIT.md](validation/GODOT_471_HEADLESS_CRASH_AUDIT.md): causa y regla obligatoria para evitar crashes de Godot en ejecuciones headless de agentes.
- [../sim/validation/](../sim/validation/): casos, baselines, reportes y herramientas del carril de validación científica.

## Arquitectura y Diseño

- [architecture/PROGRAM_FLOW.md](architecture/PROGRAM_FLOW.md): mapa vigente de arranque, editor, simulación, vistas, export y validación.
- [architecture/CONTRIBUTOR_GUIDE.md](architecture/CONTRIBUTOR_GUIDE.md): guía de orientación por área para nuevos colaboradores.
- [architecture/MODULE_BOUNDARIES.md](architecture/MODULE_BOUNDARIES.md): fronteras esperadas entre `sim`, `editor`, `view`, `ui`, `scripts` y `tools`.
- [architecture/LARGE_FILES_INVENTORY.md](architecture/LARGE_FILES_INVENTORY.md): inventario de archivos grandes y acciones recomendadas.
- [architecture/REFACTOR_PLAN.md](architecture/REFACTOR_PLAN.md): plan para modularizar archivos grandes sin cambiar comportamiento.
- [architecture/SIMUFIRE_ARCHITECTURE_TWO_ZONE.md](architecture/SIMUFIRE_ARCHITECTURE_TWO_ZONE.md): arquitectura two-zone.
- [architecture/TWO_ZONE_ENGINE_MIGRATION_PLAN.md](architecture/TWO_ZONE_ENGINE_MIGRATION_PLAN.md): plan de migración del motor two-zone.
- [architecture/PHASE_2E_DESIGN.md](architecture/PHASE_2E_DESIGN.md): diseño fase 2E.
- [architecture/PHASE_2E_CO2_DESIGN.md](architecture/PHASE_2E_CO2_DESIGN.md): diseño específico CO2 fase 2E.
- [architecture/ILV_COMBUSTION_REGIME_PLAN.md](architecture/ILV_COMBUSTION_REGIME_PLAN.md): plan para detectar y modelar combustión ILV, infraventilada y ventilada sin tocar motor todavía.

## Auditorías

- [audits/AUDIT_REPORT.md](audits/AUDIT_REPORT.md): auditoría técnica principal.
- [audits/AUDIT_REPORT_2026-05-16.md](audits/AUDIT_REPORT_2026-05-16.md): auditoría fechada.
- [audits/AUDITORIA_2026-05-20.md](audits/AUDITORIA_2026-05-20.md): auditoría general de mayo.
- [audits/AUDITORIA_REGRESION_2026-05-22.md](audits/AUDITORIA_REGRESION_2026-05-22.md): auditoría de regresión.
- [audits/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md](audits/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md): calibración FED/HCN.
- [audits/AUDITORIA_REALISMO_CFAST_2026-06-10.md](audits/AUDITORIA_REALISMO_CFAST_2026-06-10.md): realismo frente a CFAST.
- [audits/BEHAVIORAL_VALIDATION_AUDIT.md](audits/BEHAVIORAL_VALIDATION_AUDIT.md): validación conductual.
- [audits/CREDIBILITY_REPORT.md](audits/CREDIBILITY_REPORT.md): informe de credibilidad.
- [audits/PRODUCT_EDITOR_FP_3D_AUDIT.md](audits/PRODUCT_EDITOR_FP_3D_AUDIT.md): auditoría producto/editor/first-person/3D.
- [AUDITORIA_VISUAL_2026-08-29.md](AUDITORIA_VISUAL_2026-08-29.md): auditoría gráfica completa (humo en vanos, fachada propia, rellano y entradas).
- [PROMPT_MOTOR_PORTAL.md](PROMPT_MOTOR_PORTAL.md): el portal y la caja de escalera como recinto de verdad. Hoy la puerta de la vivienda da al ambiente, así que el humo que sale por ella no choca contra ningún techo ni sube por ninguna escalera: el rellano es decorado, no existe para el motor.
- [AUDITORIA_CODIGO_2026-09-11.md](AUDITORIA_CODIGO_2026-09-11.md): auditoría del código visual y de UI (estilo, código muerto y funciones duplicadas entre las vistas), medida con dos comprobadores; incluye el guardarraíl que aprobaba sin haber mirado.
- [AUDITORIA_EDITOR_2026-09-06.md](AUDITORIA_EDITOR_2026-09-06.md): auditoría del editor de escenarios (descubribilidad, acabado y funciones que faltan), medida sobre la escena y el script. **El §17 es el estado del editor al 2026-09-10.**
- [audit_issues/INDEX.md](audit_issues/INDEX.md): índice de issues técnicos derivados de auditorías.

## Encargos a la línea del motor

- [PROMPT_MOTOR_VIENTO_ALTURA.md](PROMPT_MOTOR_VIENTO_ALTURA.md): corrección de la velocidad del viento por la altura de la abertura (N-5, parte motor).
- [PROMPT_MOTOR_PATIO.md](PROMPT_MOTOR_PATIO.md): patios interiores (N-2, fase 5).
- [PROMPT_MOTOR_GRAFICAS.md](PROMPT_MOTOR_GRAFICAS.md): gráficas asíncronas y su supresión al salir.
- [PROMPT_MOTOR_HRR_RESIDUAL.md](PROMPT_MOTOR_HRR_RESIDUAL.md): `hrr_kw` residual en objetos tras la extinción.

## Roadmaps y Planificación

- [planning/MASTER_ROADMAP_CURRENT.md](planning/MASTER_ROADMAP_CURRENT.md): hoja de ruta activa para credibilidad física del motor, balances y validación restante.
- [planning/EDITOR_FLOW_CHECKLIST.md](planning/EDITOR_FLOW_CHECKLIST.md): checklist del flujo de editor.

## Histórico y Archivo

- [templates/](templates/): plantillas para ADRs, auditorías, release notes e issues técnicos.
- [sessions/](sessions/): histórico de sesiones consolidado.
- [sessions/root/](sessions/root/): estados de sesión que antes estaban en la raíz.
- [handoff/](handoff/): handoffs de sesiones y trabajo.
- [archive/root-artifacts/](archive/root-artifacts/): logs, salidas temporales y snapshots que antes estaban en la raíz.
- [literature/](literature/): bibliografía, PDFs y material de soporte externo.
