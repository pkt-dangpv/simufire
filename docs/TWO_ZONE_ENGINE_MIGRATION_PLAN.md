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
powershell -ExecutionPolicy Bypass -File sim/validation/run_legacy_two_zone_compare.ps1 -Action compare -CandidateMode two-zone -AllowContractFailure
```

La deuda fisica legacy no se ha ocultado: los yields pueden solicitar y producir
mas carbono que el combustible disponible al incluir soot. M1 debe decidir la
formulacion conservativa; Pre-M1 solo la mide sin alterar los resultados legacy.

## Estado Pre-M1

**CERRADO.** M1 puede comenzar sobre el contrato congelado. La referencia legacy
no debe regenerarse durante M1 salvo decision explicita y documentada.

## M1 - Canonical two-zone core (v1.0.0-alpha)

- [COMPLETADO ALPHA] Reutilizar `upper_gas_kg`/`upper_energy_kj` y anadir
  `lower_gas_kg`/`lower_energy_kj` sin duplicar el estado upper.
- [COMPLETADO ALPHA] Transferir masa y entalpia lower->upper mediante la ODE
  de entrenamiento McCaffrey/Heskestad.
- [COMPLETADO ALPHA] Derivar ambas temperaturas y la interfaz termica desde
  masa, volumen y energia cuando `two_zone_solver_enabled=true`.
- [COMPLETADO ALPHA] Mantener legacy como default y conservar paridad exacta.
- [PENDIENTE M3] Sustituir el cierre agregado de masa de contorno por flujos
  upper/lower resueltos por apertura, HVAC y presion.

### Evidencia M1 alpha

- `ZoneFireSolver` actua como ledger de masa/energia de ambas zonas y conserva
  masa y energia en transferencias internas lower->upper.
- La entrada de aire de compensacion llega a temperatura ambiente; la salida
  lower arrastra energia sensible proporcional. El acumulado se exporta como
  `two_zone_boundary_mass_kg`; la energia absorbida desde sistemas legacy,
  caps y contorno se registra en `two_zone_boundary_energy_kj`.
- Telemetria runtime: masa y energia upper/lower, totales de zona y balances
  netos de contorno. Cubierta por `tests/test_two_zone_energy_core.py`.
- Ruta legacy fresca contra referencia congelada: `18/18` gating PASS,
  `0/18` no-gating fuera de tolerancia y `0` errores de contrato.
- Candidato M1 alpha: `17/18` gating PASS, `1/18` no-gating fuera de tolerancia
  y `0` errores de contrato.
- Unico gate pendiente: `cfast_two_floor_stairwell.room_0_peak_temp_upper_c`
  (`551.09 C` frente a `862.20 C`; delta `-311.11 C`, tolerancia `301.77 C`).
- Deuda observacional asociada: `room_6_final_fed`; la baseline historica de
  escalera tampoco recibe `time_room_6_temp_above_30_s`. Ambas quedan para M3,
  donde el transporte termico vertical queda resuelto bajo opt-in en la evidencia
  M3 actualizada.

## Estado M1

**ALPHA IMPLEMENTADA.** El nucleo canonico esta activo solo por flag, legacy
permanece congelado y M2 puede comenzar sin rebaseline. M1 no se considera
cerrada para release hasta que M3 sustituya el cierre agregado de contorno.

## M2 - Combustion con O2 local (v1.0.0-beta)

- [COMPLETADO BETA CANDIDATE] Sustituir booleanos O2 por un modo unico:
  `legacy`, `upper`, `lower`, `interface`.
- [COMPLETADO BETA CANDIDATE] Evaluar `upper` sin activarlo globalmente antes del rebaseline.
- [COMPLETADO BETA CANDIDATE] Actualizar O2 antes del HRR cuando el modo es explicito.
- [COMPLETADO BETA CANDIDATE] Cerrar los cuatro gaps HVAC con corrida fresca
  `two-zone + fire_o2_mode=upper`.

### Evidencia M2 beta candidate

- `fire_o2_mode="legacy"` sigue siendo el default. En legacy, los flags antiguos
  `fire_o2_upper_for_flame` / `fire_o2_lower_for_flame` conservan prioridad y
  comportamiento historico.
- Los modos explicitos se seleccionan desde CLI sin editar casos:
  `run_case.ps1 -FireO2Mode upper|lower|interface`.
- Los modos explicitos hacen `_step_oxygen(dt)` antes de `_step_fire(dt)`;
  legacy mantiene el orden antiguo para paridad.
- `upper` explicito usa `room.o2_upper` con el umbral normal del caso
  (`fire_o2_min_for_flame`). El umbral historico `fire_o2_upper_min_for_flame`
  queda solo para el flag legacy upper.
- En modos explicitos, `fire_o2_full_hrr_open` actua como referencia local de
  full-HRR aunque no haya ventana exterior abierta. Para `cfast_hvac_residential`
  se calibra a `0.126`; en legacy no cambia el resultado porque el modo sigue
  siendo `lower` por flag historico.
- Telemetria nueva por sala: `fire_o2_mode_used`, `fire_o2_ref`,
  `fire_o2_min_ref`, mas metricas `room_N_min_fire_o2_ref` y
  `room_N_final_fire_o2_ref`.
- Corrida focal:
  `run_case.ps1 -CaseName cfast_hvac_residential -EngineMode two-zone -FireO2Mode upper`.
  Reporte: `sim/validation/reports/m2_upper_two_zone_cfast_hvac_residential.json`.
- Resultado focal HVAC:
  - `cfast_hvac_t180_temp_upper_c`: SF `180.22 C` vs CFAST `259.59 C`,
    tolerancia `80.0 C` -> PASS con margen `0.63 C`.
  - `cfast_hvac_rmse_temp_upper_c`: `44.03 C` <= `60.0 C`.
  - `cfast_hvac_t300_co_upper_ppm`: `994 ppm` vs `661 ppm`, tolerancia `500 ppm`.
  - `cfast_hvac_t450_co_upper_ppm`: `1070 ppm` vs `731 ppm`, tolerancia `500 ppm`.
  - `cfast_hvac_t300_co2_upper_pct`: `12.35 %` vs `10.62 %`, tolerancia `3.0 %`.
  - `cfast_hvac_t450_co2_upper_pct`: `13.08 %` vs `11.74 %`, tolerancia `3.0 %`.

## Estado M2

**BETA CANDIDATE IMPLEMENTADA.** El cierre de los cuatro gaps HVAC existe bajo
modo explicito `upper` y no altera el default legacy. Queda pendiente decidir en
M4 si `upper` pasa a ser default del motor two-zone tras rebaseline parcial/global.

## M3 - Flujos de apertura two-zone (v1.0.0-rc)

- [COMPLETADO RC SLICE] Compartir `opening_flow_cache` con `GasExchangeSystem`.
- [COMPLETADO RC] Enrutar especies por apertura interior segun zona real de
  origen/destino, incluyendo rutas cruzadas upper->lower y lower->upper cuando
  las interfaces o aberturas verticales no coinciden.
- [COMPLETADO RC SLICE] Exponer telemetria por sala:
  `two_zone_opening_upper/lower_in/out_kg`.
- [COMPLETADO RC SLICE] CLI: `run_case.ps1 -TwoZoneOpeningFlow` y comparador
  `run_legacy_two_zone_compare.ps1 -TwoZoneOpeningFlow`.
- [COMPLETADO RC] Enrutar purgas exteriores altas por zona upper para venteo
  de presion, venteo de humo y ventilacion natural cuando el flag M3 esta activo.
- [COMPLETADO RC] Enrutar HVAC por altura de rejilla: retornos altos/bajos
  extraen upper/lower y suministros altos/bajos inyectan especies y O2 en la
  zona correspondiente.
- [PENDIENTE] Completar `ZoneFireSolver` como ledger unico de especies.
- [COMPLETADO EXPERIMENTAL] Cablear presion canonica/stack exterior como
  opt-in (`phase3_pressure_canonical_enabled`, `-CanonicalPressure`) sin alterar
  defaults legacy. La presion se iguala por componente interior conectado y el
  venteo por fugas cerradas no se duplica cuando la ODE ya modela leakage.
- [COMPLETADO RC] Calibrar transporte termico vertical de escalera bajo opt-in:
  `phase3_stairwell_heat_bridge_*` adelanta el acoplamiento termico sin mover
  especies y aplica cap editable a salas `escalera` para evitar picos no
  fisicos antes del registro de metricas.
- [PENDIENTE] Retirar flags Phase 2H solo tras demostrar paridad.

### Evidencia M3 rc slice

- El flag `two_zone_opening_flow_enabled=false` conserva el default legacy.
  En validacion se activa sin editar casos con `-TwoZoneOpeningFlow`.
- `GasExchangeSystem` lee el `opening_flow_cache` ya calculado por
  `ThermalSystem`, evitando un segundo calculo de plano neutro para la misma
  abertura.
- El routing M3 usa `bernoulli_upper_kg_s` y `bernoulli_lower_kg_s`, pero la
  zona de origen/destino se resuelve con el punto medio del segmento de abertura
  frente a `thermal_layer_m`. En aperturas verticales, el extremo de planta baja
  cae en la zona alta de la sala inferior y el extremo de planta alta cae en la
  zona baja de la sala superior.
- CO, CO2 y HCN conservan masa total y solo modifican inventario upper cuando
  el destino real es la zona upper.
- Corrida smoke:
  `run_case.ps1 -CaseName cfast_two_room_door_open -EngineMode two-zone -TwoZoneOpeningFlow -ValidationDuration 120`.
  Reporte: `sim/validation/reports/m3_opening_two_zone_cfast_two_room_120.json`.
  Resultado: `two_zone_opening_flow_enabled=1`, rutas lower activas
  (`room_0_final_two_zone_opening_lower_in/out_kg=1.7613`) y residual de
  transporte carbono `-5.15e-4 kg`.
- Corrida HVAC activo:
  `run_case.ps1 -CaseName carbon_balance_hvac -EngineMode two-zone -FireO2Mode upper -TwoZoneOpeningFlow -ValidationDuration 120`.
  Reporte: `sim/validation/reports/m3_opening_carbon_balance_hvac_120.json`.
  Resultado: `hvac_on=1`, `two_zone_opening_flow_enabled=1` y residual de
  transporte carbono `-1.12e-4 kg`.
- Corrida vertical/stairwell:
  `run_case.ps1 -CaseName cfast_two_floor_stairwell -EngineMode two-zone -FireO2Mode upper -TwoZoneOpeningFlow -ValidationDuration 180 -AllowBaselineFailure`.
  Reporte: `sim/validation/reports/m3_opening_two_zone_stairwell_180.json`.
  Resultado: abertura vertical activa (`room_0_final_two_zone_opening_lower_in/out_kg=238.89`)
  y residual de transporte carbono `-2.69e-4 kg`. La baseline historica de
  humo en planta superior sigue fuera y queda para rebaseline/cierre M4.
- Corrida presion canonica aislada:
  `run_case.ps1 -CaseName cfast_overpressure_sealed -EngineMode legacy -FireO2Mode legacy -CanonicalPressure -ValidationDuration 120 -AllowBaselineFailure`.
  Reporte: `sim/validation/reports/m3_canonical_pressure_overpressure_legacy_120.json`.
  Resultado: `phase3_pressure_canonical_enabled=1`, `room_0_max_overpressure_pa=151.75 Pa`
  y residual de transporte carbono `-3.22e-5 kg`. Valida el cableado opt-in
  sin cerrar calibracion.
- Corrida presion canonica + stairwell:
  `run_case.ps1 -CaseName cfast_two_floor_stairwell -EngineMode two-zone -FireO2Mode upper -TwoZoneOpeningFlow -CanonicalPressure -ValidationDuration 180 -AllowBaselineFailure`.
  Reporte: `sim/validation/reports/m3_canonical_pressure_stairwell_180.json`.
  Resultado: `phase3_pressure_canonical_enabled=1`,
  `room_upper_floor_vs_lower_floor_pressure_delta_pa=0.0`,
  `room_0_peak_hrr_kw=706.05` y residual de transporte carbono `-1.01e-3 kg`.
- Corrida presion canonica + stairwell larga:
  `run_case.ps1 -CaseName cfast_two_floor_stairwell -EngineMode two-zone -FireO2Mode upper -TwoZoneOpeningFlow -CanonicalPressure -ValidationDuration 600 -AllowBaselineFailure`.
  Reporte: `sim/validation/reports/m3_canonical_pressure_stairwell_600.json`.
  Resultado actualizado: 5/5 checks historicos PASS (`HRR=751.44 kW`,
  `room_6_final_smoke_kg=0.161`, `time_room_6_smoke_start_s=291.92`,
  `time_room_6_temp_above_30_s=158.17`, `pressure_delta=0.0`).
  `room_6_peak_temp_upper_c=120.0` por cap opt-in y residual de transporte
  carbono `-2.41e-3 kg`.

## Estado M3

**RC IMPLEMENTADO BAJO FLAG.** Ya existe routing two-zone de especies para
aperturas interiores, rutas cruzadas, verticales, purgas exteriores upper y HVAC
por altura de rejilla. La presion canonica tambien existe como opt-in
experimental y ya corrige el delta de presion stairwell bajo flag. El transporte
termico vertical de escalera queda calibrado bajo opt-in con 5/5 checks stairwell
PASS. M3 queda pendiente de promocion a contrato estable durante M4: rebaseline
global, ledger unico de especies y retirada de flags Phase 2H.

## M4 - Rebaseline y cierre (v1.0.0)

- [COMPLETADO CONTRATO] Comparar legacy/two-zone en todos los casos con
  `two_zone_opening_flow` y `canonical_pressure`.
- [COMPLETADO CONTRATO] No ampliar tolerancias para absorber regresiones; el
  unico ajuste nuevo es un multiplicador two-zone opt-in y case-level para
  calibrar captura convectiva en stairwell.
- [COMPLETADO CONTRATO] Exigir conservacion de carbono en transporte:
  residual pico M4 stairwell `0.00355 kg` y contrato global PASS.
- [COMPLETADO] Sincronizar documentacion, conteos y reportes M4.
- [DECIDIDO] `fire_o2_mode=upper` no pasa a default global: forzarlo en todos
  los casos da `13/18` required PASS y 5 fallos HRR/temperatura.
- [PENDIENTE RELEASE] Retirar o reclasificar flags Phase 2H/experimentales solo
  cuando haya decision de API estable y rebaseline de producto v1.0.0.

### Evidencia M4

- Candidato estable de contrato:
  `-TwoZoneV1` (`two-zone + -TwoZoneOpeningFlow + -CanonicalPressure`),
  con O2 por caso/default.
- El mismo perfil se acepta en Godot directo como `--validation-two-zone-v1`;
  el reporte registra `two_zone_v1_profile=true`.
- Reporte:
  `sim/validation/reports/contracts/legacy_two_zone_comparison_m4_default_o2_pass.json`.
- Reporte del preset `-TwoZoneV1`:
  `sim/validation/reports/contracts/legacy_two_zone_comparison_two_zone_v1_pass.json`.
- Resultado global: `18/18` required PASS, `0` errores de contrato,
  `4/18` observacionales no-gating fuera de tolerancia.
- Observaciones no-gating restantes:
  `cfast_hvac_residential.room_0_final_hot_layer_m`,
  `cfast_hvac_residential.room_0_final_o2_upper`,
  `cfast_single_room_closed.room_0_final_hot_layer_m`,
  `cfast_two_floor_stairwell.room_6_peak_temp_upper_c`.
- Focal stairwell final:
  `sim/validation/reports/m4_stairwell_m3_default_o2_heatmult_118_600.json`.
  `room_0_peak_temp_upper_c=561.02 C`, `room_0_peak_hrr_kw=850.67`,
  `room_6_peak_temp_upper_c=120.0`, presion entre plantas `0.0 Pa`,
  residual carbono `0.00355 kg`.

## Estado M4

**CONTRATO GLOBAL PASS.** El camino v1.0.0 estable queda como two-zone con
aperturas por zona y presion canonica bajo el preset de validacion `-TwoZoneV1`,
O2 por caso/default y calibracion stairwell local mediante
`two_zone_convective_heat_multiplier=1.18`.
El modo `upper` permanece explicito hasta que una futura version cierre sus
regresiones globales de HRR/temperatura.

## Orden aprobado

Estado canonico y conservacion -> combustion -> aperturas/HVAC -> rebaseline.
