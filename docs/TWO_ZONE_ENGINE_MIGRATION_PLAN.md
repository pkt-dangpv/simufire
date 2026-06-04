# Plan de migracion del motor a two-zone

**Fecha:** 2026-06-04  
**Objetivo:** sustituir los estados y correcciones parciales de capas por un solver two-zone conservativo.

## Hallazgos previos

- `RoomModel.reset_dynamic_state()` no reinicia `co2_upper`, `co2_upper_kg` ni `hcn_upper_kg`.
- El guardrail `peak_c_balance_frac <= 1.05` comprueba un valor ya limitado a `<= 1.0` y no incluye carbono del humo.
- `fire_o2_upper_for_flame` tiene prioridad sobre `fire_o2_lower_for_flame`.
- `upper_gas_kg` ya existe: no debe duplicarse con otro estado upper.
- `pressure_pa_therm` y `co2_upper` son campos paralelos/tracer, no fuentes canonicas para flujos y masa.
- `ZoneFireSolver` debe convertirse en el ledger unico de masa, entalpia y especies.

## Pre-M1 obligatorio

1. [COMPLETADO] Corregir el reset de todos los estados upper/lower y cubrirlo con tests.
2. [COMPLETADO] Sustituir el guardrail de carbono por balance pre-clamp acumulado, incluyendo soot.
3. [COMPLETADO] Congelar baseline legacy y crear comparacion automatica legacy/two-zone.

### Evidencia de cierre Pre-M1

- Reset upper/lower cubierto por `tests/test_room_model_reset.py`.
- Ledger global SF-CBAL cubre combustible, especies, soot, productos no modelados,
  transporte pendiente, aperturas exteriores, ACH, PPV, HVAC y deposicion.
- Diagnosticos separados: exceso solicitado pre-clamp, exceso fisico post-clamp
  y residual puro de transporte.
- Casos runtime: transporte, ventilacion, HVAC, creacion espuria y perdida espuria.
- `c_balance_high_phi` conserva el exceso legacy visible sin convertir el clamp
  quimico en una falsa perdida de transporte.
- Referencia congelada en `sim/validation/baselines/contracts/legacy_two_zone_reference.json`:
  6 casos canonicos y 36 metricas, commit legacy `2f1ee08`.
- Manifiesto de comparacion en `sim/validation/legacy_two_zone_manifest.json`:
  18 metricas gating y 18 observacionales no-gating.
- `two_zone_solver_enabled=false` es el default y permanece no-op hasta M1.
- El runner fuerza y registra `engine_mode=legacy|two-zone`, evitando comparar
  accidentalmente dos reportes sin identificar el modo.
- Comparacion smoke Pre-M1: `18/18` gating PASS, `0/18` observacionales fuera
  de tolerancia y `0` errores de contrato.
- `validation_guardrails.py` valida tambien que la referencia congelada siga
  sincronizada con el manifiesto.

Comandos:

```powershell
# Regenerar la referencia legacy solo de forma intencional.
powershell -ExecutionPolicy Bypass -File sim/validation/run_legacy_two_zone_compare.ps1 -Action freeze

# Comparar el candidato two-zone contra la referencia congelada.
powershell -ExecutionPolicy Bypass -File sim/validation/run_legacy_two_zone_compare.ps1 -Action compare -CandidateMode two-zone
```

La deuda fisica legacy no se ha ocultado: los yields pueden solicitar y producir
mas carbono que el combustible disponible al incluir soot. M1 debe decidir la
formulacion conservativa; Pre-M1 solo la mide sin alterar los resultados legacy.

## Estado Pre-M1

**CERRADO.** M1 puede comenzar sobre el contrato congelado. La referencia legacy
no debe regenerarse durante M1 salvo decision explicita y documentada.

## M1 - Canonical two-zone core (v1.0.0-alpha)

- Reutilizar/migrar `upper_gas_kg` y anadir masa lower explicita.
- Mantener masa y entalpia canonicas de ambas zonas.
- Derivar temperaturas e interfaz desde masa, volumen y energia.
- Resolver penacho, mezcla, paredes y perdidas mediante ecuaciones acopladas.
- Mantener campos legacy como proyecciones de solo lectura.
- Activacion inicial por `two_zone_solver_enabled=false`.

## M2 - Combustion con O2 local (v1.0.0-beta)

- Sustituir booleanos O2 por un modo unico: `legacy`, `upper`, `lower`, `interface`.
- Evaluar `upper` sin activarlo globalmente antes del rebaseline.
- Actualizar O2 antes del HRR o usar predictor-corrector.
- Cerrar los cuatro gaps HVAC solo con corridas frescas que lo demuestren.

## M3 - Flujos de apertura two-zone (v1.0.0-rc)

- Completar `ZoneFireSolver` como ledger unico.
- Segmentar aperturas por plano neutro e interfaces de ambas salas.
- Permitir rutas upper-upper, upper-lower, lower-upper y lower-lower.
- Integrar ventanas, puertas, HVAC y presion canonica.
- Retirar flags Phase 2H solo tras demostrar paridad.

## M4 - Rebaseline y cierre (v1.0.0)

- Comparar legacy/two-zone en todos los casos.
- No ampliar tolerancias para absorber regresiones.
- Exigir conservacion de masa, energia, O2 y carbono.
- Sincronizar documentacion, conteos y reportes.
- Cerrar o reclasificar explicitamente los cuatro gaps HVAC.

## Orden aprobado

Estado canonico y conservacion -> combustion -> aperturas/HVAC -> rebaseline.
