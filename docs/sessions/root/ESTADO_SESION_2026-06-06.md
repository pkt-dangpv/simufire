# Estado de Sesión — 2026-06-06

## Resumen
- ✅ Añadido runner dedicado TwoZoneV1:
  `sim/validation/run_two_zone_v1_checks.ps1`.
- ✅ Añadidos tests estructurales del runner:
  `tests/test_two_zone_v1_runner.py`.
- ✅ TwoZoneV1 queda validado con batería repetible:
  unitarios específicos, contrato runtime estricto, auditoría de reportes
  candidato y guardrails globales.

## TwoZoneV1 runner

Comando canónico:

```powershell
powershell -ExecutionPolicy Bypass -File sim\validation\run_two_zone_v1_checks.ps1 -TimeoutSeconds 900
```

El runner ejecuta:
- `python -m unittest` sobre los módulos específicos two-zone.
- `run_legacy_two_zone_compare.ps1 -Action compare -CandidateMode two-zone -TwoZoneV1`
  sin `-AllowContractFailure`.
- Auditoría explícita del JSON de contrato:
  `candidate_mode=two-zone`, `all_required_pass=true`, `required_count=18`,
  `failed_required_count=0`, `contract_errors=[]`.
- Auditoría de los 6 reportes candidatos en
  `sim/validation/reports/mode_comparison/two-zone-opening-flow-canonical-pressure`.
- Verificación de `engine_mode=two-zone`, `two_zone_v1_profile=true`,
  `two_zone_solver_enabled=1`, `two_zone_opening_flow_enabled=1`,
  `phase3_pressure_canonical_enabled=1`.
- Verificación de residual de transporte de carbono two-zone
  `peak_global_carbon_transport_residual_kg_abs <= 0.02 kg`.
- `python scripts/simulation/validation_guardrails.py`.

## Resultado 2026-06-06

- Runner dedicado TwoZoneV1 → **PASS**.
- Unitarios específicos dentro del runner → **61/61 PASS**.
- Contrato runtime TwoZoneV1 → **18/18 required PASS**, `0` errores de contrato.
- Auditoría de reportes candidato → **6/6 PASS**.
- Guardrails globales → **381/381 required PASS**, 6 gaps no-gating sincronizados.
- Unitarios completos → **196/196 PASS**.
- Product checks → **57/57 PASS**.
- `git diff --check` → **PASS** (solo avisos CRLF en working copy).

## Endurecimiento posterior

- `run_two_zone_v1_checks.ps1` ahora audita también el contrato agregado
  `legacy_two_zone_comparison.json`, además de los reportes candidato.
- Tests del runner ampliados a **9/9 PASS**.
- Audit-only del runner:
  `run_two_zone_v1_checks.ps1 -SkipUnitTests -SkipRuntimeCompare -SkipGuardrails`
  → **PASS**, confirma `18/18 required PASS`, `4/18` non-gating fuera de tolerancia
  y `6/6` reportes candidato PASS.
- El runner ahora exige frescura de artefactos cuando ejecuta runtime:
  `legacy_two_zone_comparison.json` y los 6 reportes candidato deben tener
  `LastWriteTime` posterior al inicio de la corrida (`freshAfter - 2s`).
- Pasada completa tras activar frescura → **PASS**:
  unitarios específicos `61/61`, contrato runtime `18/18`, auditoría contrato,
  auditoría candidatos `6/6` y guardrails `381/381`.
- Endurecimiento adicional: el runner compara el inventario exacto del manifest
  contra los casos del contrato y contra los reportes candidato. Si falta un
  caso o aparece un JSON extra, falla antes de copiar el artefacto estable.
- Audit-only tras inventario exacto → **PASS**; tests del runner siguen **9/9 PASS**.

## Pendientes reales

- Se mantienen 4 diferencias observacionales no-gating en el contrato two-zone:
  capa final en closed/HVAC, O2 upper final HVAC y temp upper stairwell.
- Se mantienen 6 gaps científicos no-gating en `reference_checks.json`:
  4 HVAC estructurales y 2 Ghanekar flashover empíricos.
- Ningún check required falla.
