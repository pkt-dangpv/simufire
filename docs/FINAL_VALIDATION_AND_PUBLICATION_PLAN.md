# Plan final de correccion, validacion y publicacion

**Fecha de registro:** 2026-05-31  
**Estado base:** post Phase 3, antes del cierre final/publicacion  
**Objetivo:** dejar SimuFire en estado publicable: codigo auditado, validacion reproducible, gaps restantes justificados o cerrados, y resultados del simulador listos para informe tecnico.

## 1. Estado canonico actual

- Phase 2B cerrada: estratificacion CO2 anadida y checks requeridos en PASS.
- Phase 2C cerrada: HVAC low-supply/high-return two-zone O2 feed activado solo por `engine_overrides`; el fuego sobrevive en `cfast_hvac_residential`.
- Phase 3 cerrada: `pressure_pa_therm` por ODE termodinamica paralela; `cfast_closed_t120_pressure_pa` requerido y en PASS.
- Validacion requerida actual: **379/379 required PASS**.
- Gaps CFAST conocidos actuales: **4 non-gating**, todos estructurales Phase 2C HVAC post-t=240s:
  - `cfast_hvac_t300_co_upper_ppm`
  - `cfast_hvac_t450_co_upper_ppm`
  - `cfast_hvac_t300_co2_upper_pct`
  - `cfast_hvac_t450_co2_upper_pct`
- Bloqueo de publicacion no contabilizado en `known_gap_count`: **HCN/FED no esta validado con calidad publicable**, aunque HCN ya existe en codigo y contribuye al FED.

## 2. Principios de cierre

- No cerrar un gap ampliando tolerancias sin corrida fresca, diff registrado y justificacion fisica.
- No convertir ningun mecanismo experimental en default global si fue disenado como opt-in.
- Todo cierre debe regenerar logs/reportes, ejecutar guardrails y actualizar documentacion.
- Los resultados de tenabilidad/FED no se publican como cuantitativos hasta validar HCN, CO, CO2, O2, calor y sus componentes de FED.
- Los gaps estructurales que queden abiertos deben ser no-gating, trazables y explicados como limite del modelo, no como fallo silencioso.

## 3. Phase 4A - HVAC CO/CO2 diagnostic result

**Problema:** con Phase 2C, SF mantiene HRR maximo mientras CFAST modera combustiones por su dinamica two-zone. Esto desplaza CO/CO2 upper layer en t=300 y t=450.

**Decision 2026-05-31:** rechazar el mecanismo `fire_o2_upper_hrr_blend` dentro de la ruta `fire_o2_lower_for_flame`.

**Evidencia:**

- CO2_upper en t=450 queda saturado/capado cerca de 30% para todos los blends.
- CO2_upper en t=300 con blend=1.0 sigue en 18.82% vs CFAST 10.62%, diff=8.2% > tol=3%.
- CO_upper en t=450 con blend=1.0 queda en 2856 ppm vs limite CFAST+tol=1231 ppm.
- `cfast_hvac_t300_o2_upper` required se rompe: SF 0.098 -> 0.135, diff 0.024 -> 0.061 > tol=0.025.
- `cfast_hvac_t180_temp_upper_c` required se rompe: diff=84.2 C > tol=80 C.

**Resultado:**

- El cambio experimental en `CombustionSystem.gd` debe quedar revertido.
- `tools/phase4a_blend_sweep.py` se conserva como artefacto diagnostico, no como solucion activa.
- Los 4 gaps CO/CO2 HVAC siguen siendo estructurales y non-gating.
- El estado objetivo se mantiene en **379/379 required PASS, 4 known gaps**.

**Conclusion tecnica:** la brecha no se resuelve con un blend escalar de O2 para HRR. Es una divergencia de supuestos two-zone: SF usa `o2_lower` repuesto por HVAC para sostener llama, mientras CFAST modera combustion por agotamiento de zona superior.

## 4. Phase 4B - HCN/FED toxicity validation

**Estado 2026-05-31:** Observabilidad COMPLETADA. FED decomposition COMPLETADA. Calibración COMPLETADA y documentada.

**Verdad actual:** HCN esta implementado, pero no esta validado al nivel necesario para publicar tenabilidad. Existe deuda documental porque algunas notas antiguas hablan de "HCN no implementado"; eso debe corregirse.

**Logros Phase 4B (completados):**

- HCN logging (`HCN=`/`HCNu=`) en .log y CSV — `hcn_ppm` y `hcn_upper_ppm` por sala.
- `peak_hcn_ppm`/`peak_hcn_upper_ppm` tracked en CaseRunner — checks required en 2 baselines.
- Checks HCN non-gating (`min: 10 ppm`) en `victim_fed_incapacitation` y `pu_sofa_fec_incapacitation` — promovidos a required (actual ~2000 ppm).
- **FED decomposition**: `fed_co`, `fed_hcn`, `fed_hypoxia`, `fed_heat` en RoomModel (acumulación separada), ThermalSystem.step_fed() (per-component deltas), SimulationStateBuilder (export), SimulationLogWriter (CSV + ROOM log línea `FED=X(CO:X HCN:X O2:X Q:X)`).
- Documentación obsoleta corregida: `MEMORIA_PARAMETROS_CONCORDANCIA_2026-04-19.md` línea ~509.
- **379/379 PASS** mantenida; 13 unit tests OK; todos guardrails PASS.

**Riesgo principal:** FED es una magnitud de seguridad humana. Si HCN esta subcalibrado, oculto en logs, o mezclado sin desglose, el FED total puede parecer plausible y ser erroneo.

**Plan:**

1. ~~Limpiar documentacion obsoleta~~ ✅ COMPLETADO 2026-05-27
   - ~~eliminar o corregir cualquier frase "HCN no implementado"~~;
   - ~~distinguir "implementado" de "validado"~~;
   - ~~marcar HCN/FED como bloqueo de publicacion hasta cierre Phase 4B~~.
2. ~~Auditoria de combustibles~~ ✅ COMPLETADO
   - inventariados: PU sofa 0.000154 kg/MJ, secondary 0.000100, PVC 0.0, secondary_ignition 0.000200, default wood 0.000040.
3. ~~Observabilidad~~ ✅ COMPLETADO 2026-05-27
   - ~~loguear `hcn_upper_ppm`, `hcn_lower_ppm` y no solo `hcn_ppm`~~;
   - ~~separar componentes FED: CO, HCN, hypoxia/O2, heat/thermal~~;
   - ~~exponer FEC/FED por victima y por altura de respiracion~~.
4. Validacion quimica: ❌ PENDIENTE
   - agregar checks HCN contra salidas CFAST si estan disponibles (`ULHCN`, `LLHCN` o equivalentes);
   - agregar checks Ghanekar para HCN/FED cuando haya datos experimentales o derivados trazables;
   - agregar guardrail de conservacion de masa/carbono que incluya HCN.
5. ~~Validacion de tenabilidad~~ ✅ COMPLETADO 2026-05-31 — ver `docs/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md`
   - ~~verificar que el multiplicador de hiperventilacion por CO2 afecta correctamente a CO y HCN;~~
   - ~~comparar tiempos de incapacitation/FED=1.0 en casos `pu_sofa`/victim;~~
   - ~~analizar ratios FED_CO vs FED_HCN vs FED_O2 vs FED_heat contra literatura (Purser SFPE: HCN 20-30% en residencial).~~ pu_sofa_fec: 19.7% (room_0) y 25.1% (room_1) — dentro del rango.
6. ~~Calibracion~~ ✅ COMPLETADO 2026-05-31
   - ~~calibrar yields por material antes de tocar formulas FED;~~ yield PU sofa=0.000154 kg/MJ documentado
   - ~~no cambiar defaults globales sin rebaseline completa;~~
   - ~~registrar tolerancias como `diff + margen` con justificacion.~~

**Criterio de cierre Phase 4B:**

- ~~No queda documentacion que afirme que HCN no existe.~~ ✅
- ~~HCN upper/lower y componentes FED aparecen en logs/reportes.~~ ✅
- ~~Checks HCN/FED nuevos estan en PASS o, si no hay dato suficiente, quedan como non-gating con limite publicado.~~ ✅
- ~~Los escenarios de tenabilidad explican cuanto del FED viene de CO, HCN, O2/CO2 y calor.~~ ✅ Documentado en `AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md`
- ~~El informe final declara explicitamente el nivel de confianza del FED.~~ ✅ Declarado en `PUBLICATION_READINESS_AUDIT_2026-05-31.md`

## 5. Auditoria de codigo y orden del repositorio

**Objetivo:** asegurar que el cierre no sea solo numerico; el codigo debe quedar mantenible.

**Plan:**

1. Revisar sistemas principales:
   - `sim/fire/CombustionSystem.gd`
   - `sim/fire/ThermalSystem.gd`
   - `sim/fire/GasExchangeSystem.gd`
   - `sim/core/SimulationStateBuilder.gd`
   - `sim/core/SimulationLogWriter.gd`
2. Revisar scripts de validacion:
   - `scripts/simulation/validate_reference_cases.py`
   - `scripts/simulation/validation_guardrails.py`
   - `scripts/simulation/gap_inventory_check.py`
   - runners/sweeps Phase 4A/4B.
3. Eliminar duplicacion o flags muertos.
4. Confirmar que todos los defaults nuevos son no-op salvo override explicito.
5. Separar claramente:
   - fisica del motor,
   - configuracion de casos,
   - checks de validacion,
   - generacion de informes.
6. Revisar nombres, unidades y comentarios: Pa, ppm, kg, kg/MJ, fraccion molar/volumetrica, segundos.

## 6. Validacion completa antes de publicar

**Suite minima:**

```bash
python scripts/simulation/validate_reference_cases.py
python scripts/simulation/validation_guardrails.py
python tests/test_guardrails.py
```

**Adicional para cierre final:**

- Reejecutar casos CFAST clave con logs frescos.
- Reejecutar casos Ghanekar/FED/tenability.
- Comparar `reference_checks.json` contra documentacion.
- Confirmar que no quedan logs antiguos usados como fuente de verdad.
- Guardar tabla final:
  - required pass/fail,
  - non-gating gaps,
  - tolerancias cambiadas,
  - commits/cambios de motor relevantes,
  - limites declarados.

## 7. Informe publicable

El informe final debe incluir:

- resumen ejecutivo del estado del simulador;
- metodologia de validacion;
- matriz de casos: CFAST, Ghanekar, tenability, guardrails;
- resultados por magnitud: temperatura, HRR, O2, CO, CO2, HCN, presion, FED/FEC;
- tabla de gaps cerrados y gaps estructurales restantes;
- incertidumbre y limites del modelo;
- cambios de motor por fase;
- reproducibilidad: comandos, version/commit, rutas de artefactos.

**Regla de publicacion:** si HCN/FED no esta cerrado, el informe puede publicar validacion termica/gases generales, pero no debe presentar FED como resultado cuantitativo final.

## 8. Orden recomendado de ejecucion

1. Guardar estado actual y crear rama de cierre.
2. Cerrar o decidir Phase 4A HVAC.
3. Ejecutar Phase 4B HCN/FED.
4. Auditar codigo y scripts.
5. Regenerar validacion completa.
6. Escribir informe final publicable.
7. Hacer review final de consistencia: docs, logs, reports, checks y codigo.

## 9. Definicion de terminado

El proyecto se considera listo para publicacion cuando:

- todos los required checks pasan en corrida fresca;
- `known_gap_count` coincide entre JSON y docs;
- los gaps restantes son no-gating, aceptados y explicados;
- HCN/FED esta implementado, visible, validado o explicitamente limitado;
- guardrails y unit tests pasan;
- el codigo principal fue revisado sin deuda critica;
- el informe final reproduce los resultados desde comandos documentados.
