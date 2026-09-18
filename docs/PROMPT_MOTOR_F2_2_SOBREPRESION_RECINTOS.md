# Diagnóstico y diseño: sobrepresión de recintos cerrados (F2.2)

> **Estado (2026-09-18): F2.2-DIAG cerrada. Solo diagnóstico y diseño.**
>
> `F2.2-DIAG` es **esta fase documental**. Las etapas de implementación son
> `F2.2A` (ecuaciones locales puras), `F2.2B` (solver acoplado de red), `F2.2C`
> (integración tras interruptor) y `F2.2D` (conexión de fuga, deformación y
> vidrio). `F2.2-DIAG` nunca designa una etapa de código.
> - **No hay código nuevo**: no se ha tocado `sim/`, ni el editor, ni los
>   escenarios, ni los casos, ni las tolerancias, ni la clasificación de huecos.
> - **F2.2A implementada el 2026-09-18** (§14.1): `sim/core/CompartmentPressureEquations.gd`,
>   modelo puro **sin integrar**.
> - **F2.2B cerrada el 2026-09-18** (§15.2): **promueve** el solver puro que ya
>   existía, `sim/core/Phase3CoupledPressureSolver.gd`, con la entrada canónica
>   `solve_pressure_network`. **Sigue sin integrar**: nadie aplica su resultado.
> - **F2.2C cerrada el 2026-09-18** (§16): la red es autoritativa dentro del
>   paso real del motor, detrás del interruptor único
>   `pressure_network_solver_enabled`, **apagado por defecto**. Ningún escenario
>   distribuido lo enciende.
> - **F2.2D sigue sin implementar**: las puertas cerradas siguen siendo
>   estancas, y la deformación y el vidrio siguen sin integrarse (§19).
> - Los modelos puros de las fases 1, 2, 3A y 3B siguen **sin integrar**, y no
>   pueden integrarse antes de F2.2 (§15).

## 1. Estado y checkpoint

| Concepto | Valor |
| --- | --- |
| Rama | `main` |
| HEAD al empezar | `cc917ac4` (6 por delante de `origin/main`, árbol limpio) |
| Procesos Godot al empezar | 0 |
| Fases cerradas | 1 (fuga pura), 2 (deformación prescrita), 3A (integridad de vidrio), 3B (geometría multicapa) |
| Fase de este documento | F2.2-DIAG (diagnóstico y diseño), cerrada el 2026-09-18 |
| Implementación en marcha | F2.2A, F2.2B y F2.2C cerradas el 2026-09-18 (§14.1, §15.2 y §16) |
| Mediciones nuevas | 22 corridas headless bajo `runs/pressure_f2_2_20260917/` (sin versionar) |
| Fuente nueva | NIST TN 1889v2 (guía de usuario de CFAST) |

Las mediciones de este documento son **nuevas** (2026-09-17; correcciones de
redacción y criterios el 2026-09-18, sin repetir mediciones). Cuando se cita
una cifra heredada (evidencia P1R8, `reference_checks.json`, diagnóstico F2.2a
de 2026-07-12) se dice expresamente.

## 2. Problema observado

`sim/validation/reports/reference_checks.json` (regenerado hoy) compara la
presión de SimuFire con la de CFAST en 31 comprobaciones. Extracto:

| Comprobación | SimuFire [Pa] | CFAST [Pa] | Pasa |
| --- | ---: | ---: | :---: |
| `cfast_closed_t360_pressure_pa` | 2 417,58 | 167,939 | no |
| `cfast_closed_t480_pressure_pa` | 2 006,96 | 168,174 | no |
| `cfast_slow_t600_pressure_pa` | 4 392,48 | 65,149 | no |
| `cfast_t350_pressure_pa` | 403 945,54 | 167,461 | no |
| `cfast_doorclose_r0_t300_pressure_pa` | 550 260,20 | 154,307 | no |
| `cfast_hvac_t450_pressure_pa` | 977 652,03 | 168,371 | no |
| `cfast_2r_r0_t360_pressure_pa` | 198,42 | **−38,719** | no |
| `cfast_fo_t350_pressure_pa` | 972,22 | **−6,009** | no |
| `cfast_t420_pressure_pa` | 1,82 | −5,464 | sí (tolerancia 20) |

Tres rasgos que el diagnóstico tiene que explicar, y que explica:

1. La escala: de cientos de Pa a **casi 1 MPa**, según el caso.
2. La **discontinuidad**: el mismo motor publica 403 945 Pa en un caso y 1,82 Pa
   en otro del mismo escenario, sin transición física.
3. CFAST publica presiones **negativas** que SimuFire no puede representar.

## 3. Alcance y exclusiones

**Dentro**: de dónde sale la presión publicada, qué presión gobierna realmente
los flujos, por qué difieren de CFAST, y qué arquitectura hace falta.

**Fuera** (no se ha tocado ni se propone tocar ahora): HVAC, F2.1, integración
de fuga, deformación o vidrio, modelo térmico de rotura, editor,
serialización, escenarios, tolerancias, casos y clasificación de huecos.
El interruptor de HVAC sigue excluido por decisión del usuario
(`USER_EXCLUDED_HVAC` en las disposiciones), aunque sus cifras se citan como
síntoma del mismo defecto.

## 4. Propietarios actuales de la presión

Hay **dos campos de presión por sala**, y un tercer valor publicado que elige
entre ellos.

| Campo | Declarado en | Qué es | Quién lo escribe |
| --- | --- | --- | --- |
| `RoomModel.overpressure_pa` | `sim/building/RoomModel.gd:283` | Presión manométrica de la capa superior respecto al exterior | `GasExchangeSystem.step_pressure_venting`, `_promote_...`, `_equalize_...`, `step_ppv`, `OxygenExchangeSystem` |
| `RoomModel.pressure_pa_therm` | `sim/building/RoomModel.gd:286` | Campo paralelo de la ODE de presión "termodinámica" | `GasExchangeSystem.step_thermodynamic_pressure` |
| `state["overpressure_pa"]` | `SimulationStateBuilder.gd:262` | **Lo que ven el CSV, los informes y las comprobaciones CFAST** | `pressure_pa_therm if > 0 else overpressure_pa` |

### 4.1 Escritores

| Ruta | Efecto | Unidad y signo |
| --- | --- | --- |
| `GasExchangeSystem.step_thermodynamic_pressure` (líneas 303-350) | Integra `pressure_pa_therm` por Euler explícito | Pa, manométrica, `maxf(0, …)` |
| `_promote_thermodynamic_pressure_to_overpressure` (línea 358) | `overpressure_pa = pressure_pa_therm` (solo con `phase3_pressure_canonical_enabled`) | Pa, ≥ 0 |
| `_equalize_thermodynamic_pressure_components` (línea 410) | Media ponderada por volumen en cada componente conexo | Pa, ≥ 0 |
| `step_pressure_venting` (líneas 1495-1505) | **Legado**: relaja `overpressure_pa` hacia `dp_buoyancy + dp_stack` con τ = 5 s | Pa, ≥ 0 |
| `step_pressure_venting` (línea 1624) | Tras purgar: `overpressure_pa *= (1 − frac_out·0,9)` | Pa, ≥ 0 |
| `OxygenExchangeSystem` (línea 1011) | `overpressure_pa *= (1 − min(0,55, air_in/room_air))` | Pa, ≥ 0 |
| `GasExchangeSystem.step_ppv` (línea 4303) | `overpressure_pa = max(overpressure_pa, dp_ppv_pa)` | Pa, ≥ 0 |
| `RoomModel.reset` (línea 493) | Pone ambos campos a 0 al reiniciar la simulación | — |

No existe ningún camino que escriba un valor negativo: **todos** los escritores
pasan por `maxf(0.0, …)`.

### 4.2 Lectores

| Ruta | Para qué usa la presión | Referencia que inventa |
| --- | --- | --- |
| `GasExchangeSystem.step_pressure_venting:1509` | Umbral de purga | `pressure_vent_threshold_pa` = 2 Pa |
| `GasExchangeSystem.step_pressure_venting:1530` | Bernoulli hacia el exterior por apertura | `eff_press = P − ΔP_viento` |
| `GasExchangeSystem:2686` | Limpieza posincendio | `postfire_cleanup_pressure_full_pa` |
| `GasExchangeSystem:3136` | Mezcla entre salas | `clamp(max(P_a, P_b)/1,5)` |
| `GasExchangeSystem:3834, 3907` | Transporte de especies al exterior y entre salas | `outside_open_species_pressure_ref_pa` |
| `OxygenExchangeSystem:888, 914, 1045` | Entrada de aire y O₂ | umbral 0,2 Pa y `max(P_a, P_b)` |
| `ThermalSystem:1396, 2912, 3085, 5092` | Derrame de gases calientes y sentido del intercambio | `pressure_spill_ref_delta_pa · 0,35` |
| `Phase3ZoneMassSystem:9122` | Sombra canónica de presión interior | — |
| `SimulationStateBuilder:262` | Publica el estado | — |
| `SimulationLogWriter:806, 1147` | CSV | — |
| `CaseRunner.gd:1029-1035` | `room_N_max_overpressure_pa`, `..._pressure_pa_therm` | — |
| `scripts/generate_fire_graphs.py:300` | Gráficas | — |

### 4.3 Recuento explícito de lectores

La tabla anterior tiene **12 rutas de lectura**. No todas son equivalentes, así
que el documento las cuenta siempre así:

| Grupo | Rutas | Sistemas | Nombres |
| --- | ---: | ---: | --- |
| **Sistemas que modifican física** | 7 | 3 | `GasExchangeSystem` (umbral de purga, Bernoulli exterior, limpieza posincendio, mezcla entre salas, transporte de especies), `OxygenExchangeSystem` (entrada de aire y O₂), `ThermalSystem` (derrame y sentido del intercambio) |
| **Maquinaria de sombra** | 1 | 1 | `Phase3ZoneMassSystem:9122` |
| **Publicación y observadores** | 4 | 4 | `SimulationStateBuilder`, `SimulationLogWriter`, `CaseRunner`, `scripts/generate_fire_graphs.py` |

Cuando este documento dice "las rutas físicas" se refiere a las **7 rutas** de
los **3 sistemas** de la primera fila. Las de sombra y observación leen la
presión pero no fabrican caudal.

**Cada ruta física aplica su propia escala de referencia y produce su propio
caudal.** No hay un solo intercambio por abertura: hay tantos como rutas.

## 5. Convenciones actuales de unidades y signo

- **Unidad**: Pa en todos los campos y parámetros (`pressure_vent_threshold_pa`,
  `pressure_spill_ref_delta_pa`, `fire_backdraft_deflagration_overpressure_pa`…).
  No se ha encontrado ninguna confusión Pa/kPa: la energía sí se mueve en kJ/kW,
  pero no se mezcla con la presión.
- **Referencia**: manométrica respecto al exterior. La ODE usa `P_ATM = 101325`
  solo como factor en el término de fuga, no como estado.
- **Signo**: solo positiva. Un recinto que se enfría **no puede** bajar de 0 Pa.
- **Cota**: `overpressure_pa` se documenta como "presión de la capa superior",
  pero se consume como si fuese un valor uniforme del recinto, y
  `ClosedDoorLeakageModel` lo trataría como presión **en el suelo**
  (`p_floor_pa`). Tres cotas distintas para el mismo número.

## 6. Orden real de ejecución

`SimulationEngine.step` (líneas 3492-3626), en cada paso:

1. `_step_exterior_opening_smooth` (fracciones de apertura suavizadas).
2. Sombras canónicas de zona (si están encendidas).
3. `_step_pool_fires` → `_step_oxygen` (pre-HRR) → `_step_fire` →
   `_step_co_oxidation` → `_step_targets` → `_step_oxygen` (post-HRR).
4. `thermal_system.step` (temperaturas, capas, derrames).
5. `_step_suppression`, `_step_steam_decay`, rotura de vidrio.
6. `_step_gas_exchange` (líneas 3858-3890):
   1. si `phase3_pressure_canonical_enabled`: `step_thermodynamic_pressure`;
   2. `step_pressure_venting` (**calcula presión y purga en el mismo bucle**);
   3. si no es canónico: `step_thermodynamic_pressure` **después** del venteo;
   4. `step_ppv`, `step_smoke`.
7. `_step_hvac`, `_step_passive_fuel`, `_step_detectors`, `_step_victims`.

Consecuencias del orden:
- En el camino por defecto, la ODE se integra **después** de purgar, así que la
  purga nunca ve la presión de la ODE y la ODE nunca ve el efecto de la purga.
- La presión se calcula **dentro** del bucle que la consume: no hay una etapa
  "resolver presión" separada de "mover masa".
- La temperatura ya está actualizada cuando se calcula la presión, así que la
  presión es una función de estado del paso anterior, no una incógnita
  acoplada.

## 7. Casos reproducidos y resultados

Herramienta: `python scripts/run_scenario.py <caso> --out-dir runs/… --phase3-zone-diagnostics`
(sondas nuevas, copias de casos existentes con sobrescrituras de motor; ninguna
escribe en `sim/validation/reports/`). Sala de referencia: 5 × 4 × 2,4 m
(48 m³), fuego de madera hasta 1 280 kW, `phase3_leak_area_m2 = 0,03`.

`P_pub` es la presión publicada (`state["overpressure_pa"]`), `P_ODE` es
`pressure_pa_therm` y `P_flujo` es `overpressure_pa`, la que gobierna los
caudales.

| Sonda | Caso | `P_pub` máx [Pa] | t [s] | `P_ODE` máx [Pa] | `P_flujo` máx [Pa] | T_sup máx [°C] | O₂ final |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A | Sellado **sin fuego** | 0,00 | — | 0,00 | 0,000 | 20,0 | 0,2090 |
| B | Sellado con fuego (reproduce `cfast_single_room_closed`) | 7 280,53 | 220 | 7 280,46 | **8,481** | 275,2 | 0,0500 |
| B′ | Igual con `phase3_pressure_canonical_enabled` | 2 227,92 | 140 | 2 227,92 | 2 227,920 | 293,2 | 0,0421 |
| D | Igual con ventana exterior abierta | 622,22 | 310 | 622,22 | **2,015** | 348,1 | 0,1453 |
| E1 | Dos salas, puerta abierta | 356,40 | 310 | 491,64 | 3,202 | 299,7 | 0,0467 |
| E2 | Dos salas, puerta cerrada (`cfast_bedroom_closed_door`) | 0,00 | — | 0,00 | 0,000 | 20,0 | 0,2090 |
| F | Cierre de puerta a mitad de incendio | **567 022,25** | 320 | 567 003,11 | 7,103 | 188,5 | 0,0408 |
| G1 | Crecimiento rápido, recinto cerrado | 8 377,73 | 170 | 8 377,48 | 3,173 | 564,9 | 0,1112 |
| G2 | Crecimiento lento, recinto sellado | 7 129,57 | 340 | 7 129,80 | 7,745 | 228,4 | 0,0196 |
| G3 | **Sin fuego**, edificio **inicializado en equilibrio** con el exterior a 0 °C | 0,00 | — | 0,00 | 0,000 | 0,0 | 0,2090 |

Serie temporal de la sonda B (sala 0):

| t [s] | `P_pub` [Pa] | `P_ODE` [Pa] | `P_flujo` [Pa] | `P_boyanza` [Pa] | T_sup [°C] | T_inf [°C] | HRR [kW] | O₂ | ṁ_vent [kg/s] |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0,00 | 0,00 | 0,000 | 0,000 | 20,0 | 20,0 | 0,0 | 0,2090 | 0,0000 |
| 30 | 3,47 | 3,42 | 0,056 | 0,089 | 26,9 | 20,0 | 15,9 | 0,2088 | 0,0000 |
| 60 | 67,81 | 67,42 | 0,575 | 0,723 | 41,5 | 20,4 | 71,0 | 0,2076 | 0,0000 |
| 120 | 1 192,38 | 1 189,01 | 2,006 | 2,530 | 115,9 | 22,7 | 301,7 | 0,1976 | 0,0058 |
| 240 | 7 109,60 | 7 111,19 | 7,182 | 7,955 | 274,2 | 29,9 | 717,7 | 0,1403 | 0,0093 |
| 300 | 3 867,69 | 3 873,56 | 8,396 | 8,624 | 250,5 | 37,0 | 520,0 | 0,1126 | 0,0102 |
| 360 | 1 270,11 | 1 271,83 | 6,749 | 6,776 | 179,3 | 37,5 | 301,4 | 0,0878 | 0,0099 |
| 480 | 428,12 | 428,19 | 4,058 | 4,091 | 100,8 | 33,4 | 176,8 | 0,0612 | 0,0084 |
| 600 | 420,26 | 420,26 | 3,635 | 3,710 | 88,4 | 31,9 | 175,3 | 0,0500 | 0,0081 |

Sobre G3: el escenario fija `outside_temp_c = 0` y el edificio **arranca ya a
0 °C** (primera fila del CSV: `temp_upper_c = temp_lower_c = 0,00`,
`air_mass_kg = 57,60`, constante hasta 600 s). **No** es una historia de
enfriamiento desde 20 °C. Por tanto 0 Pa es el resultado **físicamente
correcto**, y la sonda demuestra **ausencia de deriva numérica en equilibrio
frío**, no incapacidad de producir depresión. La incapacidad de representar
presiones negativas está demostrada por otras dos vías: los `maxf(0.0, …)` de
**todos** los escritores (§4.1) y los casos CFAST que sí publican presión
negativa (§2 y §21).

Dos hechos que cierran el diagnóstico:

- `P_pub ≡ P_ODE` en todas las filas: **lo que se compara con CFAST es la ODE**.
- `P_flujo ≈ P_boyanza` en todas las filas: la presión que mueve masa es
  **solo** el término de flotabilidad, tres órdenes de magnitud menor.

### 7.1 Caso C: qué haría hoy el modelo puro de fuga

Sonda `runs/pressure_f2_2_20260917/probe_leak.gd`: lee el CSV de la sonda B y
llama a `ClosedDoorLeakageModel.compute_flows` con las dos presiones. **No se
aplica ningún caudal al motor.** Puerta de 0,92 × 2,05 m, exponente 0,65,
ELA a 4 Pa.

| t [s] | Presión usada | `p_floor` [Pa] | ELA | ṁ bruto [kg/s] | máx \|ΔP\| [Pa] | Renovaciones/h equivalentes |
| ---: | --- | ---: | --- | ---: | ---: | ---: |
| 120 | publicada | 1 192,38 | 12 cm² | 0,1432 | 1 194,04 | 8,95 |
| 120 | publicada | 1 192,38 | 21 cm² | 0,2506 | 1 194,04 | 15,66 |
| 120 | de flujo | 2,01 | 12 cm² | 0,0024 | 3,67 | 0,15 |
| 240 | publicada | 7 109,60 | 12 cm² | 0,4295 | 7 115,99 | 26,84 |
| 240 | publicada | 7 109,60 | 21 cm² | 0,7516 | 7 115,99 | 46,97 |
| 240 | de flujo | 7,18 | 12 cm² | 0,0054 | 13,58 | 0,34 |
| 240 | de flujo | 7,18 | 21 cm² | 0,0095 | 13,58 | 0,59 |
| 300 | de flujo | 8,40 | 12 cm² | 0,0060 | 15,67 | 0,38 |

- Con la presión **publicada**, una rendija de 12 cm² movería casi **27
  renovaciones por hora**: una puerta cerrada ventilaría más que una abierta.
- Con la presión **de flujo**, 0,34–0,59 renovaciones/h, que es el orden
  esperable de una puerta cerrada.
- `máx |ΔP|` casi **duplica** `p_floor` (7,18 → 13,58 Pa) porque el modelo puro
  añade su propia columna hidrostática sobre una presión que **ya es**
  flotabilidad: ese es el doble conteo (§10, H-1).

## 8. Comparación con CFAST

CFAST resuelve, por compartimento, un sistema de EDO para presión, volumen de
capa y temperaturas (TN 1889v1, ec. 2.2-2.8, p. 8-9):

```text
dP/dt = (γ − 1)/V · ( ḣ_l + ḣ_u )                              (2.5)
```

donde `ḣ_i` es **toda** la entalpía que entra o sale de la capa: fuego,
conducción a paredes, radiación y el flujo por aberturas. La presión es una
incógnita del mismo sistema que la masa y la energía, resuelto con un método
implícito por rigidez (TN 1889v1, p. 9). El caudal por una abertura vertical se
obtiene integrando Bernoulli entre el plano neutro y los bordes del segmento
(ec. 4.1-4.5, p. 17-18, coeficiente C = 0,7), y **la fuga se declara como una
abertura pequeña explícita** (TN 1889v1, p. 3; TN 1889v2, p. 21).

SimuFire hace otra cosa (`GasExchangeSystem.gd:303-350`):

```text
dP/dt = (γ − 1)·χ_conv·HRR / V  −  C_d·A_eff/V · P_atm · sqrt(2P/ρ_amb)
```

Diferencias estructurales, no de calibración:

| Concepto | CFAST | SimuFire |
| --- | --- | --- |
| Fuente | Entalpía neta de las dos capas | Solo `χ_conv · HRR` |
| Pérdida a paredes | Incluida en `ḣ` | **Ausente** |
| Radiación | Incluida en `ḣ` | **Ausente** |
| Salida por aberturas | Entalpía del flujo resuelto | Término volumétrico *ad hoc* |
| Densidad del término de salida | Gas del recinto | `ρ_amb` = 1,2 fija |
| Factor del sumidero | `γ·P` | `P_atm` (falta `γ`, y `P` se sustituye por la atmosférica) |
| Masa | Conservada | **No se contabiliza**: la ODE no quita ni un gramo |
| Acoplamiento | Presión, capas y temperaturas en un solo sistema | Presión calculada aparte, después de la temperatura |
| Integración | Implícita, rígida | Euler explícito |
| Signo | Puede ser negativa | Recortada a ≥ 0 |
| Fugas | Abertura explícita | Área efectiva implícita (`phase3_leak_area_m2` o ACH) |

Del par fuente/sumidero de SimuFire sale una **solución cuasiestacionaria
cerrada**:

```text
P_eq = (ρ_amb / 2) · [ (γ − 1) · χ_conv · HRR / (C_d · A_eff · P_atm) ]²
```

Contrastada con la sonda B (`A_eff = 0,03 m²`, χ = 0,70):

| t [s] | HRR [kW] | `P_ODE` medida [Pa] | `P_eq` analítica [Pa] | Error |
| ---: | ---: | ---: | ---: | ---: |
| 120 | 301,7 | 1 189,0 | 1 245,5 | +4,8 % |
| 180 | 662,7 | 5 765,9 | 6 007,8 | +4,2 % |
| 220 | 729,6 | 7 280,5 | 7 283,1 | +0,04 % |
| 300 | 520,0 | 3 873,6 | 3 699,6 | −4,5 % |
| 480 | 176,8 | 428,2 | 427,5 | −0,2 % |

La presión publicada **no es una acumulación numérica**: es el equilibrio exacto
de una ecuación equivocada, con `P ∝ HRR² / A_eff²`.

## 9. Evidencia bibliográfica

| Fuente | Ubicación | Qué fija |
| --- | --- | --- |
| NIST TN 1889v1, *CFAST Technical Reference Guide* | §1.5, p. 2 | Las ecuaciones son conservación de masa y energía; el momento solo aparece como Bernoulli en las aberturas |
| ídem | §2.1, ec. 2.2-2.4, p. 8 | `dm_i/dt = ṁ_i`; primer principio con trabajo de expansión; gas ideal `P V_i = m_i R T_i` |
| ídem | §2.1, ec. 2.5, p. 9 | `dP/dt = (γ−1)/V (ḣ_l + ḣ_u)`: **una sola presión por compartimento** |
| ídem | ec. 2.6-2.8, p. 9 | Volumen de capa y temperaturas comparten la misma `dP/dt` |
| ídem | §2.1, p. 9 | El sistema es **rígido**: la presión se ajusta mucho más rápido que el resto; hacen falta métodos implícitos o con jacobiano |
| ídem | §2.1, p. 8 y ec. 2.1, p. 8 | `c_p = 1012 J/(kg·K)`, `γ = 1,4`, `R = 289,14 J/(kg·K)` |
| ídem | §4.1, ec. 4.1-4.5, p. 17-18 | Flujo por aberturas verticales: segmentos acotados por el plano neutro y las interfaces; `C = 0,7`; `ρ` del compartimento aguas arriba |
| ídem | §4.1, fig. 4.1 y ec. 4.6-4.7, p. 18 | Cuatro caminos `u→u`, `u→l`, `l→u`, `l→l` y penacho de derrame |
| ídem | §1.5, p. 3 | "Leakage is modeled by explicitly creating a small vertical or horizontal opening" |
| NIST TN 1889v2, *CFAST User's Guide* | p. 21 (índice 34 del PDF) | Las conexiones horizontales sirven para representar fugas entre compartimentos o al exterior |
| NIST TN 1887r1, *CONTAM User Guide* | ec. 28-29, p. 266 | Convención ELA ya adoptada en la fase 1: `C_d = 1,0` a 4 Pa |
| Caso `sim/validation/cfast/cfast_single_room_closed.in` | `&COMP … LEAK_AREA_RATIO = 0.00017, 5.2E-05` | La referencia CFAST **no** es un recinto perfectamente estanco: fuga ≈ 43,2 m² · 1,7e-4 + 20 m² · 5,2e-5 ≈ **0,0084 m²** |

El último punto importa: los 168 Pa de CFAST salen de un recinto con ~84 cm² de
fuga. SimuFire, con **más** fuga declarada (300 cm²), publica 2 417 Pa.

## 10. Hipótesis

| # | Hipótesis | Ruta implicada | Predicción observable | Caso | Resultado | Estado |
| --- | --- | --- | --- | --- | --- | --- |
| H-1 | Doble conteo de flotabilidad | `step_pressure_venting:1497-1501` + `ClosedDoorLeakageModel.pressure_at` | `P_flujo ≈ ΔP_boyanza` y el modelo puro añade otra columna | B, C | `P_flujo/ΔP_boyanza` = 0,63-1,00; `máx\|ΔP\|` 13,58 Pa frente a `p_floor` 7,18 Pa | **Confirmada** |
| H-2 | Presión calculada sin conservar masa | `step_thermodynamic_pressure` | La ODE sube y baja sin que cambie la masa del recinto | B | La ODE no escribe masa en ningún sitio; `air_mass_kg` no responde a `P_ODE` | **Confirmada** |
| H-3 | La purga no actualiza masa y energía de forma coherente | `step_pressure_venting:1546-1624` | La masa purgada se fija por la fracción de **hollín**, no de gas | D | Bernoulli bruto 77,13 kg contra 4,74 kg realmente purgados (factor 16) | **Confirmada** |
| H-4 | Presión derivada de la temperatura pero tratada como estado acumulable | `step_pressure_venting:1500` | Relajación de primer orden con τ fijo hacia un objetivo de flotabilidad | B | τ = 5 s codificado; el objetivo es `dp_buoyancy + dp_stack` | **Confirmada** |
| H-5 | Confusión entre presión absoluta y manométrica | `step_thermodynamic_pressure:345` | `P_atm` aparece como factor del sumidero en vez de `γ·P` | análisis + §8 | El sumidero usa 101 325 Pa fijos; falta `γ`; el estado sigue siendo manométrico | **Confirmada (parcial)**: no hay error de referencia en el estado, sí en el coeficiente |
| H-6 | Error de unidades Pa/kPa | todo el inventario §4 | Un factor 1 000 exacto entre campos | inventario | No aparece: HRR en kW se convierte a W explícitamente | **Descartada** |
| H-7 | Dependencia del paso temporal | `step_thermodynamic_pressure` | `P` cambia al reducir `dt` | B con dt = 1/6, 1/12, 1/24, 1/48 s | 7 275,8 / 7 280,5 / 7 283,0 / 7 284,2 Pa (0,12 %) | **Descartada** |
| H-8 | Volumen o masa de capa incorrectos | `volume_m3()` | `P` escala con `V` | S_height5m (48 → 100 m³) | `P` sube (7 280 → 16 984 Pa) pero por el fuego (más O₂), no por `V`: `P_eq` es independiente de `V` | **Descartada como causa directa** |
| H-9 | Presión relajada hacia un objetivo físico incorrecto | `step_pressure_venting:1500` | El objetivo es una presión hidrostática, no termodinámica | B | Confirmado en la serie: `P_flujo ≈ P_boyanza` | **Confirmada** |
| H-10 | Presión de referencia inadecuada en las aperturas | §4.2 | Cada consumidor divide por una constante distinta | inventario | 1,5 / 0,35·ref / `outside_open_species_pressure_ref_pa` / 0,2 Pa | **Confirmada** |
| H-11 | Diferencia estructural intencionada frente a CFAST | disposiciones de huecos | Los huecos están clasificados como limitación de modelo | `gap_dispositions.json` | `VERIFIED_MODEL_LIMITATION`, no gating | **Confirmada como clasificación**, pero la magnitud no está justificada físicamente |
| H-12 | Signo: el motor no puede representar depresión | todos los escritores (§4.1) | Ningún camino puede escribir un valor < 0 | inspección de código + `cfast_two_room_door_open` | Todos los escritores pasan por `maxf(0.0, …)`; CFAST publica −186,5 Pa (300 s) y −38,7 Pa (360 s) en R0 de ese caso, y SimuFire publica +198,4 Pa | **Confirmada** |
| H-15 | Deriva numérica en equilibrio sin fuego | `step_thermodynamic_pressure`, `step_pressure_venting` | Un edificio inicializado en equilibrio se queda en 0 Pa | A, G3 | 0,00 Pa durante 600 s, con temperatura y masa de aire constantes | **Descartada** (no hay deriva) |
| H-13 | El campo publicado no es el que gobierna los flujos | `SimulationStateBuilder:262` | `P_pub ≡ P_ODE ≫ P_flujo` | B, D, F, G | Factor 860 (B), 309 (D), 79 800 (F) | **Confirmada** |
| H-14 | La sensibilidad al área de fuga es la de la fórmula, no ruido | `step_thermodynamic_pressure` | `P ∝ 1/A²` | S_leak000/0084/010 | 44 022 / 82 651 / 656 Pa, coherente con `P_eq` en cada caso | **Confirmada** |

## 11. Causas raíz

No hay una sola. Son **cinco**, y las cinco hay que resolverlas.

**RC-1. Se publica una presión que no gobierna nada.**
`SimulationStateBuilder.gd:262` publica `pressure_pa_therm` siempre que sea
positiva. Todas las comprobaciones CFAST de presión miran ese campo, mientras
los flujos usan `overpressure_pa`. De ahí la discontinuidad del §2: cuando la
ODE está apagada o vale 0 se publica la otra presión, tres órdenes de magnitud
menor.

**RC-2. La ODE no es la ecuación de CFAST y su equilibrio es irreal.**
Fuente solo convectiva del fuego, sin pérdidas a paredes ni radiación;
sumidero volumétrico *ad hoc* con `P_atm` en vez de `γ·P` y densidad ambiente;
sin contabilidad de masa. Su equilibrio es `P ∝ HRR²/A_eff²`, reproducido
analíticamente con error < 5 % (§8). Con `A_eff` derivada de ACH = 0,5 el
equilibrio llega a **506 kPa** (sonda S_ach05_leak000).

**RC-3. La presión que sí gobierna los flujos es flotabilidad disfrazada.**
`overpressure_pa` relaja hacia `ρ_ext·g·h_humo·(1 − T_ext/T_sup) + término de
chimenea` con τ = 5 s. Es una diferencia hidrostática de columna, usada como
presión manométrica uniforme del recinto. Cualquier consumidor que añada su
propia columna (el modelo puro de fuga lo hace) cuenta la flotabilidad **dos
veces**.

**RC-4. La purga no conserva masa ni energía.**
`frac_out = smoke_out_kg / smoke_kg` es una fracción de **partículas de hollín**
que se usa para retirar **gas y energía** de la capa superior, mientras las
especies usan otra fracción (`air_frac_out`, limitada al 10 % del volumen) y la
presión se relaja con un tercer factor (`1 − 0,9·frac_out`). Medido en D: 77,13
kg de Bernoulli bruto contra 4,74 kg efectivamente purgados. Es el mismo
defecto que ya documentó
[`docs/validation/PHASE3_F22A_PRESSURE_VENT_DIAGNOSIS.md`](validation/PHASE3_F22A_PRESSURE_VENT_DIAGNOSIS.md)
el 2026-07-12 y que sigue abierto.

**RC-5. No hay una presión única ni un intercambio único.**
**Siete rutas físicas**, repartidas en **tres sistemas** (`GasExchangeSystem`,
`OxygenExchangeSystem`, `ThermalSystem`), leen la presión con escalas de
referencia distintas y cada una fabrica su propio caudal (§4.2 y §4.3). A ellas
se suman una ruta de sombra y cuatro de observación, que leen pero no mueven
masa. Además el estado se recorta a ≥ 0, así que la depresión no existe.

## 12. Requisitos físicos de la solución

1. **Conserva masa**: la suma de lo que sale de un recinto entra en otro o en el
   exterior, sin fracciones inventadas.
2. **Conserva energía**: la entalpía viaja con la masa, con la temperatura de
   origen.
3. **Presión manométrica** respecto al exterior a una **cota declarada**
   (se propone el suelo del recinto), con signo, sin recortes.
4. **Separa** la presión uniforme del recinto del término hidrostático
   `−∫ρ g dz`; nadie vuelve a sumar flotabilidad por su cuenta.
5. **No duplica flotabilidad**: el perfil `P(z)` es la única fuente de
   diferencias por altura.
6. **Converge** de forma independiente del paso, dentro de tolerancia.
7. **Una sola presión para todos los consumidores** y **un solo caudal por
   abertura**, con dirección y magnitud únicas.
8. Masa, entalpía, humo, O₂ y especies viajan **juntas** en el mismo
   intercambio.
9. Funciona con recinto estanco, con fuga, con abertura grande y con varios
   compartimentos.
10. Con el interruptor apagado, la física heredada **no cambia** ni un byte.

## 13. Arquitectura recomendada

**Presión y caudales son un solo problema acoplado.** La ecuación de presión
de CFAST (ec. 2.5) depende de la entalpía que entra y sale por las aberturas, y
esa entalpía depende de las presiones. Por eso el reparto **no** es una cadena
"primero presión, después caudales": es un bucle de punto fijo cuyo dueño es
F2.2B.

```text
  estado de zonas (masa, energía, temperatura, volumen) + fuentes + dt
            │
            ▼
  ┌──────────────────────── [F2.2B] PressureOpeningNetworkSolver ────────────────────────┐
  │  propone estado candidato (presiones de referencia y, si procede, variables de zona)  │
  │            │                                                                          │
  │            ▼                                                                          │
  │  perfiles hidrostáticos P(z)  →  ΔP por segmento  →  caudales y entalpías candidatos   │
  │            │                                                                          │
  │            ▼                                                                          │
  │  [F2.2A] CompartmentPressureEquations.evaluate_compartment_residual(…)                │
  │            │  residuos de presión, masa y energía por recinto                         │
  │            ▼                                                                          │
  │  actualiza las incógnitas  ──────────────► (realimentación: vuelve a proponer)        │
  │            │                                                                          │
  │            └── converge cuando residuos y cambios de presión bajan de tolerancia      │
  └───────────────────────────────────────────────────────────────────────────────────────┘
            │
            ▼  presiones + perfiles + caudales + entalpías, todo del mismo punto fijo
  [F2.2C] integración tras interruptor: un único aplicador que reparte
            masa, entalpía, O₂, humo y especies
            │
            ▼
  [F2.2D] fuentes de área: fuga de puerta (fase 1), deformación (fase 2),
            desprendimiento de vidrio (fase 3B)
```

Principios:

- **F2.2A no resuelve la presión**: evalúa las ecuaciones locales de un recinto
  para un estado candidato y devuelve residuos. No inventa caudales ni decide la
  presión final.
- **F2.2B es el dueño de la iteración**: propone, construye perfiles, calcula
  ΔP y caudales, llama al evaluador, actualiza y repite. La presión definitiva y
  los caudales definitivos salen **a la vez**, del mismo punto fijo.
- Ambos son **puros**: reciben el estado, devuelven resultados y no mutan nada.
  El motor aplica.
- El área de una abertura es un **dato de entrada**, venga de una puerta, de una
  rendija o de un rectángulo de vidrio desprendido. El solver no sabe de vidrio.
- La presión y los caudales se resuelven **antes** de mover masa, en una etapa
  propia, no dentro del bucle de purga.
- Ya existe maquinaria de sombra reutilizable en `Phase3ZoneMassSystem`
  (`coupled_pressure_solver_shadow_enabled`,
  `phase3_canonical_fixed_gross_pressure_network_shadow_enabled`,
  `--phase3-coupled-pressure-solver-capture`). F2.2B debería **medirse contra
  ella** antes de sustituir nada.
- **Vector de incógnitas: decidido el 2026-09-18** (§13.1). Es la **opción A**,
  una presión manométrica de referencia por recinto, porque la ecuación de
  estado canónica de SimuFire es **afín** en la masa y la energía totales del
  recinto. Las variables de zona no son incógnitas: son estados conservados que
  avanzan con los flujos candidatos dentro del mismo paso.

### 13.1 Estado canónico y vector de incógnitas (decidido el 2026-09-18)

La decisión no se copió del diseño anterior: se comprobó contra las ecuaciones
2.4-2.8 de TN 1889v1, contra `sim/building/RoomModel.gd`, contra
`sim/core/Phase3ZoneMassSystem.gd` y contra `sim/core/Phase3CoupledPressureSolver.gd`.

#### Correspondencia CFAST ↔ SimuFire

| Variable de CFAST | Equivalente en SimuFire | Unidad | Papel | Propietario actual | Papel en F2.2B | Ambigüedades encontradas |
| --- | --- | --- | --- | --- | --- | --- |
| `P`, presión del compartimento (ec. 2.5) | `gauge_pressure_pa` deducida de la EOS canónica; hoy `RoomModel.overpressure_pa` y `pressure_pa_therm` | Pa | **Derivada** de masa y energía; manométrica respecto al exterior | `GasExchangeSystem` (dos campos distintos) | **Única incógnita** por recinto | Hoy hay dos campos y ninguno sale de la EOS (§11, RC-1 y RC-2) |
| `m_i`, masa de cada capa (ec. 2.2) | `RoomModel.upper_gas_kg`, `lower_gas_kg` | kg | **Estado conservado** | `Phase3ZoneMassSystem` (sombra) y rutas heredadas | Avanza con los flujos candidatos, no se itera | El camino heredado la reconstruye por EOS (prohibido desde 2026-07-12) |
| `T_i`, temperatura de capa (ec. 2.7-2.8) | Derivada: `T_z = T_ref + E_z /(m_z · c_p)` | K | **Derivada** | `ZoneFireSolver`, `ThermalSystem` | Coeficiente del paso | `RoomModel.temp_upper_c` y `temp_lower_c` son campos aparte que pueden divergir de `E_z/m_z` |
| `c_v m_i T_i`, energía interna (ec. 2.3) | `RoomModel.upper_energy_kj`, `lower_energy_kj`, con `c_p = 1,0 kJ/(kg·K)` y origen en la temperatura ambiente | kJ | **Estado conservado** | ídem que la masa | Avanza con las entalpías candidatas | SimuFire usa `c_p` y energía **sensible relativa al ambiente**, no `c_v·T` absoluta |
| `V_i`, volumen de capa (ec. 2.6) | Derivado: `V_z = m_z R T_z / p_abs` | m³ | **Derivado** | `Phase3CoupledPressureSolver._thermodynamic_state` | Coeficiente congelado dentro de un solve | `RoomModel.thermal_layer_m` es un campo paralelo que no siempre coincide |
| Altura de interfaz | Derivada: `interface_m = V_inferior / área_suelo` | m | **Derivada** | ídem | Perfil hidrostático | ídem que `V_i` |
| `ḣ_i`, entalpía añadida (ec. 2.5) | `sources.*_enthalpy_kw` más la entalpía de las aberturas | kW | Fuente | Combustión, paredes, radiación, aberturas | Entra en el residuo de energía | Hoy ninguna ruta suma las tres cosas en el mismo sitio |
| `ṁ_i`, masa añadida (ec. 2.2) | `sources.*_mass_kg_s` más los caudales de aberturas | kg/s | Fuente | ídem | Entra en el residuo de masa | ídem |
| `R`, constante del gas | `R = P_ref /(ρ_ref · T_ref)` = 101325/(1,2 · 293,15) ≈ **288,02 J/(kg·K)** | J/(kg·K) | Constante | `Phase3CoupledPressureSolver` y `Phase3ZoneMassSystem` | Constante | CFAST usa 289,14 J/(kg·K) (ec. 2.1): **0,4 % de diferencia**, asumida por coherencia interna |
| `γ = c_p/c_v` | No aparece: la EOS afín sustituye a la forma `dP/dt` | — | — | — | — | La ODE heredada sí usa `γ`, pero se abandona (§11, RC-2) |

#### Ecuación de cierre

La EOS canónica de SimuFire es **exactamente afín** en la masa y la energía
totales del recinto (documentada en `Phase3CoupledPressureSolver.gd`, líneas
28-36):

```text
T_z      = T_ref + E_z / (m_z · c_p)                        [K]
p_abs    = (R / V) · (M · T_ref + E / c_p)                  [Pa]
p_gauge  = (R / V) · ((M − M_ref) · T_ref + E / c_p)        [Pa]
M_ref    = p_ext_abs · V / (R · T_ref)                      [kg]
```

con `M = m_sup + m_inf`, `E = E_sup + E_inf`, `c_p = 1,0 kJ/(kg·K)` y `T_ref`
la temperatura ambiente del escenario. La forma manométrica se escribe alrededor
de `M_ref` para no restar dos números próximos a 101 325 Pa.

#### Vector de incógnitas: opción A

**Una presión manométrica de referencia por recinto.** La justificación no es
estética:

1. La EOS es **afín** en `M` y `E`, así que la presión de un recinto es una
   función explícita de su inventario: no hace falta iterarla junto a la masa y
   la energía, basta con iterar la presión hasta que el inventario que producen
   los caudales candidatos la reproduzca.
2. Las contribuciones de cada propietario **se superponen sin términos
   cruzados**, así que hay exactamente una incógnita por recinto.
3. Masa y energía **siguen siendo estados conservados**: avanzan en el mismo
   paso con los caudales y entalpías candidatos, que a su vez dependen de la
   presión. Ese es el acoplamiento, y por eso el punto fijo es de F2.2B.
4. Las variables de zona derivadas (temperaturas, volúmenes de capa, interfaz,
   densidades) se recalculan del inventario; dentro de un solve quedan
   congeladas como coeficientes, que es una linealización documentada, no una
   omisión de propietarios.
5. **La EOS no crea masa**: es cierre y residuo diagnóstico. Reconstruir masa
   desde la EOS sigue prohibido (diagnóstico de 2026-07-12).

CFAST integra cuatro variables (`P`, `V_u`, `T_u`, `T_l`) porque su estado
primario es ese; SimuFire tiene cuatro estados primarios equivalentes
(`m_sup`, `m_inf`, `E_sup`, `E_inf`) y deriva de ellos `P`, `V_u`, `T_u` y `T_l`.
No hay contradicción: es el mismo sistema con otro juego de variables
independientes. Lo que **no** se admite es llevar los dos juegos a la vez como
estado conservado, porque entonces habría dos verdades para la misma sala; por
eso `temp_upper_c`, `temp_lower_c` y `thermal_layer_m` son, para F2.2A y F2.2B,
**derivadas** y nunca entradas independientes.

#### Qué recibe F2.2A

- `previous_state`: identificador, geometría (`floor_z_m`, `height_m`,
  `floor_area_m2`), `upper_gas_kg`, `lower_gas_kg`, `upper_energy_kj`,
  `lower_energy_kj`.
- `candidate_state`: lo mismo **más** `gauge_pressure_pa`, la presión candidata
  que propone F2.2B.
- `sources`: `upper_mass_kg_s`, `lower_mass_kg_s`, `upper_enthalpy_kw`,
  `lower_enthalpy_kw` (todo lo que no entra por aberturas).
- `opening_fluxes`: lista de `{opening_id, segment_id, zone, mass_flow_kg_s,
  enthalpy_flow_kw}` **ya resueltos por F2.2B**.
- `outside`: `pressure_abs_pa`, `temp_k`, `density_kg_m3`.
- `dt_s`.

#### Incompatibilidad encontrada

`Phase3CoupledPressureSolver._thermodynamic_state` **rechaza energías de zona
negativas**, así que el camino canónico actual no puede representar una sala
por debajo de la temperatura ambiente, que es justo el caso de la depresión por
enfriamiento (§21, criterio A). F2.2A **sí** admite energía de zona negativa
—la energía es sensible y relativa al ambiente— y exige únicamente que la
temperatura absoluta resultante sea mayor que 0 K y que la presión absoluta sea
positiva. Reconciliar ambos criterios es trabajo de F2.2B/F2.2C y queda
anotado en §22.

## 14. F2.2A: evaluador puro de ecuaciones locales

Nombre provisional: `sim/core/CompartmentPressureEquations.gd`.

**No resuelve nada.** Recibe un estado candidato y los flujos candidatos por
aberturas, y responde si ese candidato satisface la conservación de masa y
energía y las ecuaciones termodinámicas del recinto.

```text
evaluate_compartment_residual(
  previous_state,        # estado del recinto al principio del paso
  candidate_state,       # incluye candidate_gauge_pressure_pa y variables de zona
  sources,               # fuentes de masa y energía ajenas a las aberturas
  opening_fluxes,        # flujos candidatos de masa y entalpía de este recinto
  outside,
  dt_s
) -> {
  valid,
  errors,
  pressure_residual_pa,      # o su equivalente adimensional, ver más abajo
  mass_residual_kg,          # masa acumulada del paso [kg]
  energy_residual_kj,        # energía acumulada del paso [kJ]
  pressure_profile: [{z_m, gauge_pressure_pa, density_kg_m3, zone}],
  diagnostics,
}
```

Entradas explícitas:

- `previous_state`: `gauge_pressure_pa`, `mass_upper_kg`, `mass_lower_kg`,
  `energy_upper_kj`, `energy_lower_kj`, `temp_upper_k`, `temp_lower_k`,
  `interface_height_m`, `volume_m3`, `floor_z_m`, `height_m`.
- `candidate_state`: **la presión candidata** (`candidate_gauge_pressure_pa`) y
  las mismas variables de zona que se estén tratando como incógnitas.
- `sources`: `enthalpy_source_kw` (fuego, conducción a paredes y radiación, ya
  netos) y `mass_source_kg_s`.
- `opening_fluxes`: por abertura y segmento, `mass_flow_kg_s` y
  `enthalpy_flow_kw` con signo, tal como los ha propuesto F2.2B.
- `outside`: `pressure_pa`, `temp_k`, `density_kg_m3`, `wind_dp_pa` por cara y
  altura del edificio.
- `dt_s`.

Salidas: residuos y perfil hidrostático. **Nunca** caudales: no los calcula ni
los inventa. Tampoco declara una presión definitiva: la presión final es la que
F2.2B acepta cuando el punto fijo converge.

`pressure_residual_pa` es el desajuste de la ec. 2.5 de CFAST expresado en Pa
por paso; si al programarlo resulta más estable normalizarlo, el documento
admite un equivalente adimensional, pero la unidad tiene que quedar declarada.

Estas variables son una **propuesta**: la lista definitiva sale de las
ec. 2.5-2.8 de CFAST (presión, volumen de capa y dos temperaturas) y habrá que
confirmarla contra el estado canónico de zonas de la fase 3 antes de programar
(§13, pendiente del vector de incógnitas).

### 14.1 Contrato implementado (2026-09-18)

`sim/core/CompartmentPressureEquations.gd`, sin `class_name`, cargado solo por
su validador y sus tests. **Sigue sin integrar**: no lo llama `SimulationEngine`,
ni `GasExchangeSystem`, ni `OxygenExchangeSystem`, ni `ThermalSystem`, ni
`Phase3ZoneMassSystem`, ni el editor, ni la vista, ni los escenarios, ni los
casos de validación, y no se ha añadido ningún interruptor.

**Firma**

```text
evaluate_compartment_residual(previous_state, candidate_state, sources,
                              opening_fluxes, outside, dt_s) -> Dictionary
```

**Salida**: `valid`, `errors`, `room_id`, `pressure_residual_pa`,
`pressure_residual_normalized`, `mass_residual_kg`, `energy_residual_kj`,
`mass_residual_by_zone_kg`, `energy_residual_by_zone_kj`, `pressure_profile`
y `diagnostics`. Una entrada inválida devuelve `valid = false`, los errores
concretos, residuos `NaN` y perfil vacío: **no corrige nada en silencio**.

**Ecuaciones implementadas** (todas en kelvin, con `c_p = 1,0 kJ/(kg·K)`,
`P_ref = 101 325 Pa`, `ρ_ref = 1,2 kg/m³`, `g = 9,81 m/s²` y
`R = P_ref /(ρ_ref · T_ref) ≈ 288,035 J/(kg·K)`):

| Magnitud | Fórmula | Unidad |
| --- | --- | --- |
| Temperatura de zona | `T_z = T_ref + E_z /(m_z · c_p)` | K |
| Presión absoluta | `p_abs = (R / V) · (M · T_ref + E / c_p)` | Pa |
| Presión manométrica | `p_gauge = (R / V) · ((M − M_ref) · T_ref + E / c_p)` | Pa |
| Masa de referencia | `M_ref = p_ext_abs · V /(R · T_ref)` | kg |
| Volumen de zona | `V_z = m_z · R · T_z / p_abs` | m³ |
| Interfaz | `interface_m = V_inferior / área_suelo` | m |
| Perfil | `p(z) = p_suelo − g · Σ(ρ_zona · tramo)` | Pa |
| Residuo de masa | `(m_z^cand − m_z^prev) − dt · (fuente_z + Σ flujos_z)` | kg |
| Residuo de energía | `(E_z^cand − E_z^prev) − dt · (fuente_z + Σ entalpías_z)` | kJ |
| Residuo de presión | `p_gauge^cand − p_gauge(EOS del inventario candidato)` | Pa |

`pressure_residual_normalized` divide el residuo de presión por
`max(1, |p_gauge(EOS)|)`; es adimensional y está declarado como tal.

**Convención de signo, única para fuentes y flujos**: **positivo = entra** en
el recinto y en la zona indicada; negativo = sale. La presión manométrica puede
ser positiva, cero o **negativa**: no hay ni un solo recorte de signo, y la cota
de referencia es el **suelo** (`reference_z_m = floor_z_m`).

**Lo que no hace**: no calcula caudales, no itera, no declara convergencia, no
elige la presión final, no muta sus entradas, no toca `RoomModel`, no usa nodos,
escena, editor, singletons, archivos ni aleatoriedad, y no lee los interruptores
`phase3_thermodynamic_pressure_enabled` ni `phase3_pressure_canonical_enabled`.

**Estados rechazados**: `dt_s` no finito o ≤ 0; NaN o infinito en cualquier
campo; falta de un campo obligatorio; `room_id` vacío o distinto entre estados;
geometría no positiva o cambiada dentro del paso; masa de zona negativa;
recinto sin masa; energía en una zona sin masa; temperatura de zona ≤ 0 K;
presión absoluta candidata ≤ 0; volúmenes de zona que no cierran el volumen del
recinto; zona desconocida, `opening_id` vacío o flujo repetido; interfaz
declarada fuera del recinto.

**Zona degenerada**: una zona con masa ≤ 1e-12 kg no tiene temperatura ni
densidad propias; se extiende la densidad de la zona ocupada para que el perfil
tenga densidad a cualquier cota, **sin inventar masa**, y se marca en
`diagnostics` (`upper_degenerate`, `lower_degenerate`).

**Determinismo**: los flujos se ordenan por `(opening_id, segment_id, zone)`
antes de sumarse, así que el resultado no depende del orden de entrada ni
siquiera con sumas catastróficamente sensibles al orden.

**La interfaz no es una entrada**: es derivada. Si el llamante declara una
(`declared_interface_height_m`), solo se valida que caiga dentro del recinto y
se informa `declared_interface_divergence_m`; nunca se usa como estado, para no
tener dos verdades de la misma sala.

### 14.2 Pruebas de F2.2A

- **`tools/validate_compartment_pressure_equations.gd`**, registrado en
  `check_product.py`, con 12 grupos y 163 comprobaciones: equilibrio ambiente,
  enfriamiento sellado, calentamiento sellado, fuentes, flujos candidatos, dos
  zonas, zona degenerada, entradas inválidas, pureza y determinismo, presión
  absoluta, límites del contrato y volcado determinista.
- **`tests/test_compartment_pressure_equations.py`**: pureza, que no es un
  solver, que el signo nunca se recorta, estado canónico y unidades, residuos
  con `dt`, perfil hidrostático desde el suelo, independencia del orden, no
  integración y volcado idéntico byte a byte.
- **Resultados numéricos medidos** (volcado `341b5c8b…`):

| Caso | `p_gauge` de la EOS | Referencia analítica | Residuos |
| --- | ---: | ---: | --- |
| Equilibrio ambiente (57,6 kg a 293,15 K) | −0,0000 Pa | 0 Pa | masa 0,0, energía 0,0 |
| Enfriamiento sellado a 273,15 K | **−6 912,8433 Pa** | `101325·(273,15/293,15 − 1)` = **−6 912,8433 Pa** | masa 0,0; energía −1 152 kJ (denuncia el sumidero no declarado) |
| Calentamiento sellado a 313,15 K | **+6 912,8433 Pa** | +6 912,8433 Pa | simétrico del anterior |
| Dos zonas (493,15 K arriba, 298,15 K abajo) | +5 750,8615 Pa | — | interfaz 1,6041 m; ρ 0,7538 y 1,2468 kg/m³ |

  El error relativo del enfriamiento sellado frente al gas ideal es de 2e-11,
  muy por debajo del 1 % exigido en §21.

### 14.3 Mutaciones de F2.2A

**19 mutaciones, 19 muertas** por fallos funcionales (arnés local sin versionar
en `runs/f22a_20260918/mutate_equations.py`):

| Mutación | Muere por |
| --- | --- |
| N01 recorta a cero el residuo de presión | 10 candidata imposible con residuo negativo |
| N02 recorta a cero la presión de la EOS | 02 el modelo mantiene el signo negativo |
| N03 invierte el signo de un caudal | 05 los flujos de entrada y salida cuadran la masa |
| N04 invierte el signo de una entalpía | 05 los flujos cuadran la energía |
| N05 trata kW como kJ (se salta `dt`) | 04 fuente de 12 kW durante 4 s da 48 kJ |
| N06 trata kg/s como kg | 04 fuente de 0,5 kg/s durante 4 s añade 2 kg |
| N07 una sola densidad para las dos capas | 06 la pendiente superior es ρ_sup·g |
| N08 referencia de presión en el techo | 06 el nodo del suelo lleva la presión candidata |
| N09 ignora la fuente de masa | 04 la fuente de masa |
| N10 ignora la fuente de entalpía | 04 la fuente de entalpía |
| N11 muta `candidate_state` | 09 las entradas no se modifican |
| N12 declara `valid` con una entrada NaN | 08 `dt = 0` se rechaza |
| N13 usa Celsius en la temperatura de zona | 05 estado válido (temperatura ≤ 0 K) |
| N14 usa Celsius en la temperatura de referencia | 01 el residuo de presión deja de ser cero |
| N15 discontinuidad artificial en la interfaz | 06 la pendiente inferior es ρ_inf·g |
| N16 el orden de los flujos cambia el resultado | 05 suma sensible al orden idéntica byte a byte |
| N17 volumen de zona con la temperatura equivocada | 05 los volúmenes de zona no cierran |
| N18 acepta masa de zona negativa | 08 masa de zona negativa con total positivo |
| N19 acepta una presión absoluta imposible | 10 candidata en el cero absoluto |

Una vigésima mutación —desactivar la comprobación de "energía sin masa" en la
zona inferior— se retiró por **equivalente**: el cierre de volumen ya rechaza
por sí solo cualquier zona que tenga energía sin masa.

## 15. F2.2B: solver puro acoplado de red

Nombre provisional: `sim/core/PressureOpeningNetworkSolver.gd`. **Es el dueño
del solve.** Su bucle:

1. Propone presiones de referencia (y, si procede, variables de zona) como
   estado candidato.
2. Construye los perfiles hidrostáticos `P(z)` de cada recinto y del exterior.
3. Calcula `ΔP(z)` y los caudales de cada **segmento** de cada abertura.
4. Agrega masa y entalpía netas por recinto.
5. Llama a `CompartmentPressureEquations.evaluate_compartment_residual` (F2.2A).
6. Actualiza las incógnitas con los residuos devueltos.
7. Repite hasta que residuos y cambios de presión bajen de tolerancia, o hasta
   agotar el presupuesto de iteraciones.

```text
solve_pressure_network(rooms, openings, outside, sources, dt_s, tolerances) -> {
  valid, errors,
  rooms: [{
    room_id,
    gauge_pressure_pa,            # presión convergida, en la cota de referencia
    reference_z_m,
    pressure_profile: [{z_m, gauge_pressure_pa, density_kg_m3, zone}],
    net_mass_kg_s, net_enthalpy_kw,
    mass_residual_kg,             # acumulado del paso [kg]
    energy_residual_kj,           # acumulado del paso [kJ]
  }],
  openings: [{
    opening_id, neutral_plane_z_m, net_mass_kg_s,
    segments: [{z_from_m, z_to_m, dp_pa, direction,
                mass_flow_kg_s, enthalpy_flow_kw,
                source_room_id, source_zone,
                destination_room_id, destination_zone}],
  }],
  iterations, converged, failure_reason,
  max_mass_residual_kg, max_energy_residual_kj,
}
```

La salida lleva **a la vez** presiones convergidas, perfiles por altura,
caudales, plano neutro, masa y entalpía por intercambio, residuos por recinto,
iteraciones, convergencia y motivo de fallo. Ningún consumidor recibe una
presión "ya resuelta" antes de que existan los caudales que la sostienen.

- Segmentación por bordes de la abertura, interfaces de las dos salas y **plano
  neutro**, como CFAST (ec. 4.1-4.5).
- Iteración sobre la red completa: las incógnitas son las presiones de los
  recintos (y, pendiente de decisión, sus variables de zona), y los residuos de
  masa y energía que devuelve F2.2A son lo que se anula.
- El exterior es un nodo de presión fija (con viento y altura).
- Una sola dirección y magnitud por segmento; los consumidores reciben el
  resultado, no lo recalculan.
- La convergencia se declara con un residuo de masa por recinto, no por número
  de iteraciones.

### 15.2 Implementación: promoción del solver existente (2026-09-18)

**No hay un segundo solver.** El nombre conceptual de la etapa sigue siendo
`PressureOpeningNetworkSolver`, pero la implementación promovida **conserva el
nombre histórico** `sim/core/Phase3CoupledPressureSolver.gd` y su
`class_name Phase3CoupledPressureSolver`, para no romper la evidencia y los
tests de la fase 3. `PressureOpeningNetworkSolver.gd` **no existe** y un test lo
comprueba.

#### Dos entradas, un solo núcleo

| Entrada | Quién la usa | Qué hace |
| --- | --- | --- |
| `solve_coupled_pressure(rooms, openings, sources, dt, reference_temp_c, options)` | Envoltura **histórica** de la maquinaria de sombra de la fase 3 | Marco de una sola planta: suelos en 0, exterior a la temperatura de referencia, sin viento. Sin cambios de comportamiento |
| `solve_pressure_network(rooms, openings, outside, sources, dt_s, options)` | Entrada **canónica** de F2.2B | Identificadores de texto, cota absoluta, exterior con temperatura y viento, fuentes por zona en tasas, salida por segmentos y estado candidato |

La canónica **delega en la histórica**: mismas ecuaciones, mismo Jacobiano,
misma ley de flujo, misma integración por bandas. Está prohibido duplicarlas y
un test cuenta que cada función del núcleo aparece una sola vez.

#### F2.2A es el evaluador autoritativo

El solver carga `sim/core/CompartmentPressureEquations.gd` (su **único**
`preload`) y somete a F2.2A el estado candidato de **cada recinto** antes de
aceptar el resultado y antes de declarar convergencia. Los residuos que publica
son los que devuelve F2.2A, no una copia privada. Si F2.2A rechaza un
candidato, el resultado sale con `valid = false`,
`failure_reason = "compartment_equations_rejected_candidate"` y el error
concreto. El aritmética interna del solver (residuo de la EOS para el Jacobiano)
se conserva porque es la misma ecuación afín: quien manda al final es F2.2A.

#### Energía sensible negativa

Criterio unificado con F2.2A. La energía de zona es **sensible y relativa a la
temperatura de referencia**, así que puede ser negativa. Se acepta si y solo si
la masa de la zona es positiva, `T_z = T_ref + E_z /(m_z·c_p)` es finita y mayor
que 0 K, la presión absoluta es finita y positiva, los volúmenes derivados
cierran el volumen del recinto, no hay masa negativa y ninguna zona sin masa
tiene energía. **Nunca** se recorta, ni se toma el valor absoluto, ni se rechaza
por el signo. El fixture histórico que exigía "energía negativa siempre
inválida" se sustituyó por este contrato, añadiendo el caso positivo de una sala
por debajo del ambiente con presión manométrica negativa.

`Phase3ResidualProjection.gd` mantiene su propio criterio antiguo: queda fuera
del alcance de F2.2B y anotado como decisión para F2.2C.

#### Convención vertical

- La presión de referencia de cada recinto vive en su **suelo** (`floor_z_m`).
- Los perfiles y las aberturas se expresan en **cota absoluta** del edificio.
- Una abertura declara `bottom_z_m`/`top_z_m` (absoluta) **o**
  `bottom_m`/`top_m` con `height_reference = "local"`. Mezclar las dos formas se
  **rechaza**, y una cota local entre recintos con suelos distintos también,
  porque sería ambigua.
- La columna hidrostática de cada lado se integra desde su propio suelo; el
  exterior se integra desde el suelo del recinto al que da, que es donde está
  definida su presión manométrica. Con todos los suelos en 0 esto reproduce la
  fórmula histórica **byte a byte**.
- Trasladar el edificio entero en vertical no cambia ningún caudal (probado).

#### Exterior y viento

El exterior es un **nodo de presión impuesta**, no una sala: aporta
`pressure_abs_pa`, `temp_k` y, por abertura, `wind_dp_pa`. Su densidad sale de
su propia temperatura y la entalpía sensible que transporta el aire que entra es
`c_p·(T_ext − T_ref)`, que solo vale 0 cuando el exterior está a la temperatura
de referencia. El viento es el desplazamiento manométrico del nodo exterior de
**esa** abertura y se aplica **una sola vez**; una abertura interior con viento
se rechaza. **Todavía no se conecta al viento del motor**: es interfaz pura.

#### Criterios de convergencia

Se declara convergencia solo si se cumplen **todos** a la vez:

- el núcleo de Newton convergió (residuo normalizado bajo su tolerancia);
- F2.2A acepta el estado candidato de **todos** los recintos;
- cierre de presión de F2.2A ≤ `pressure_tolerance_pa` (1e-6 Pa por defecto);
- residuo de masa ≤ `mass_tolerance_kg` (1e-9 kg);
- residuo de energía ≤ `energy_tolerance_kj` (1e-6 kJ);
- ninguna banda interior queda sin clasificar por zonas.

El criterio de presión es el **cambio que todavía se debe**, que es exactamente
el cierre de F2.2A en Pa; el tamaño del último paso aceptado se publica como
diagnóstico (`pressure_change_history_pa`, `max_pressure_change_pa`) porque un
paso de Newton puede ser grande y aterrizar justo en la solución. Agotar
iteraciones, bajar el residuo o producir un candidato finito **no** son
convergencia: el resultado sale con `converged = false` y un `failure_reason`
visible, y nunca se aplica nada.

#### Resultado canónico

Por red: `valid`, `errors`, `converged`, `failure_reason`, `failure_code`,
`solver_limiting_reason`, `iterations`, `residual_history`,
`pressure_change_history_pa`, `max_pressure_change_pa`, `max_mass_residual_kg`,
`max_energy_residual_kj`, `max_pressure_residual_pa` y
`owed_pressure_change_pa`.

Por recinto: `room_id`, `reference_z_m`, `gauge_pressure_pa`, `pressure_abs_pa`,
`pressure_profile`, `candidate_upper_gas_kg`, `candidate_lower_gas_kg`,
`candidate_upper_energy_kj`, `candidate_lower_energy_kj`, `net_mass_kg_s`,
`net_enthalpy_kw`, `mass_residual_kg`, `energy_residual_kj`,
`pressure_residual_pa`, `equations_valid`, `equations_errors` y el
`diagnostics` de F2.2A.

Por abertura: `opening_id`, `room_a_id`, `room_b_id`, `neutral_plane_z_m`,
`neutral_plane_inside`, `net_mass_kg_s`, `wind_dp_pa` y sus segmentos.

Por segmento: `segment_id`, `z_from_m`, `z_to_m`, `sample_z_m`, `dp_pa`,
`direction`, `source_room_id`, `source_zone`, `destination_room_id`,
`destination_zone`, `source_density_kg_m3`, `mass_flow_kg_s`,
`enthalpy_flow_kw` y `regularized`. F2.2C no tendrá que reconstruir el
transporte por zonas: ya viene resuelto.

#### Estado candidato

Se construye de forma conservativa, zona a zona:
`m_z' = m_z + dt·fuente_z + entradas − salidas`, y lo mismo con la energía. Lo
que sale de un recinto entra exactamente en el otro, no hay ninguna purga por
fracción de hollín, y **humo, O₂ y especies no viajan todavía** en F2.2B.

#### Comparación con la sombra, antes y después

| Corpus | Resultado |
| --- | --- |
| 18 casos del solver histórico (6 capturas reales incluidas), volcado canónico | **byte a byte idéntico** (`2fbc21ef…`) antes y después de la promoción |
| 13 fixtures `phase3_f33v3h*` ejecutados uno a uno en Godot headless | 13/13 PASS antes; 13/13 PASS después |
| 308 tests Python del solver histórico | 308/308, con los asserts estructurales actualizados a la grafía absoluta |

Las únicas diferencias documentadas son de **contrato**, no numéricas: el
fixture y el test que exigían rechazar la energía negativa por su signo ahora
exigen el contrato físico, y los asserts que fijaban `interface_m` ahora fijan
`interface_z_m`.

#### Pruebas de F2.2B

`tools/validate_pressure_network_solver.gd`, registrado en `check_product.py`,
con 16 grupos y 487 comprobaciones: equilibrio sellado, enfriamiento
(−6 912,84 Pa), calentamiento simétrico, fuga exterior en los dos sentidos, dos
recintos con conservación global, contraflujo con plano neutro interior, dos
plantas con traslación vertical, viento, independencia del orden, once modos de
fallo explícito, independencia del paso recorriendo el mismo intervalo con 1, 2
y 4 pasos, comparación con la entrada histórica, reevaluación independiente con
F2.2A y estados de referencia, incluido un **estado capturado** de
`cfast_two_room_door_open` (R0 a 360 s). Eso último es una reproducción **de
estado**, no de la curva temporal del caso.

`tests/test_pressure_network_solver.py` fija el contrato estático: un solo
solver, F2.2A como autoridad, criterios de convergencia, energía negativa,
convención vertical, exterior y viento, transporte por segmentos, estado
candidato conservativo y **no integración**.

#### Mutaciones de F2.2B

**25 mutaciones, 24 muertas** por fallos funcionales (arnés local sin versionar
en `runs/f22b_20260918/mutate_solver.py`, que ejecuta el validador de F2.2B, el
de F2.2A y los tests estáticos):

| Mutación | Muere por |
| --- | --- |
| P01 presión manométrica publicada recortada a cero | 02 el enfriamiento sellado deja de cerrar |
| P02 energía negativa rechazada por el signo | 02 el recinto frío deja de converger |
| P03 exterior siempre a la temperatura de referencia | contrato estático del exterior |
| P04 ΔP invertido | 04 la fuga deja de aliviar la presión |
| P05 densidad del destino en vez de la del origen | 06 la densidad aguas arriba |
| P06 entalpía sin signo | 04 el residuo de energía se dispara |
| P07 kW tratados como kJ | 09 el cierre de presión se rompe |
| P08 `dt` omitido en la fuente de masa | 09 el cierre de presión se rompe |
| P09 masa debitada sin crédito | 04 el cierre de presión se rompe |
| P10 energía debitada sin crédito | 04 el cierre de presión se rompe |
| P11 viento sumado dos veces | 08 el interior nunca supera la presión del viento |
| P12 cotas locales y absolutas mezcladas en silencio | 07 el motivo exacto del rechazo |
| P13 cotas locales entre plantas distintas aceptadas | 07 cotas locales entre plantas |
| P14 el datum se ignora en la columna hidrostática | 07 trasladar el edificio cambia los caudales |
| P15 plano neutro fijado en el suelo | 06 el plano neutro a una altura razonable |
| P16 bandas sin partir en las interfaces | 11 independencia del paso |
| P17 convergencia declarada solo por iteraciones | 10b la puerta con tolerancia cero |
| P18 residuo de energía ignorado | 10b tolerancia de energía cero |
| P19 residuo de masa ignorado | 10b tolerancia de masa cero |
| P20 no se consulta a F2.2A | 15 el solver pregunta a F2.2A |
| P21 un caudal alterado después del solve | 04 el residuo de masa lo denuncia |
| P22 el orden de las aberturas no se normaliza | test estructural de orden |
| P24 temperatura ≤ 0 K aceptada | contrato estático de energía negativa |
| P25 las ecuaciones igualan la densidad de las dos capas | 06 la pendiente superior (validador de F2.2A) |

**P23 sobrevive y se declara como tal**: quita la guarda que rechaza un
*iterante* de Newton cuya presión absoluta sería ≤ 0. Con masas no negativas y
temperaturas positivas, la EOS nunca produce un estado así, y F2.2A rechaza
igualmente cualquier candidato con presión absoluta no positiva, de modo que el
corpus actual no puede alcanzarla. La guarda se conserva por defensiva, y aquí
queda dicho que ninguna prueba la mata.

### 15.1 Unidades del solver

| Magnitud | Unidad | Dónde |
| --- | --- | --- |
| Masa | kg | `mass_residual_kg`, masa por intercambio |
| Caudal másico | kg/s | `mass_flow_kg_s`, `net_mass_kg_s`, `mass_source_kg_s` |
| Entalpía transportada | kW | `enthalpy_flow_kw`, `net_enthalpy_kw`, `enthalpy_source_kw` |
| Energía acumulada del paso | kJ | `energy_residual_kj`, `max_energy_residual_kj`, `energy_upper_kj`, `energy_lower_kj`. El residuo energético **nunca** se expresa en kg |
| Tasa residual de energía, si alguna vez hace falta | kW | `energy_residual_kw`, declarado aparte y nunca mezclado con `energy_residual_kj` |
| Presión | Pa | presiones, perfiles y `ΔP` |

Los criterios de §21 dicen expresamente si hablan de **balance por paso en kJ**
o de **tasa en kW**.

## 16. F2.2C: integración autoritativa (2026-09-18)

### 16.1 Interruptor y frontera del paso

- Interruptor **único**: `pressure_network_solver_enabled`, `@export` en
  `SimulationEngine`, **`false` por defecto**, clasificado como física viva
  fuera del alcance P1R4 en `audit_default_off_flags.py`. El recuento de flags
  sube de 76 a 77. No hay interruptores auxiliares por magnitud.
- **Apagado**: el motor recorre exactamente la ruta histórica. El adaptador no
  se ejecuta y `pressure_network_last_result` queda vacío. Comprobado byte a
  byte en un escenario real de 600 s con fuego, humo, especies y O₂, y en la
  suite de referencia completa.
- **Encendido**: el adaptador `sim/core/PressureNetworkTransportSystem.gd`
  resuelve presión y transporte dentro de `_step_gas_exchange`, **antes** de
  cualquier ruta histórica de transporte y después de la física local del paso
  (combustión, térmica). Por eso el snapshot ya incorpora esos efectos y las
  **fuentes del solver son nulas**: declararlos otra vez sería contarlos dos
  veces.

### 16.2 Seis operaciones separadas

`build_snapshot` → `build_solver_input` → `solve` → `build_transport_transaction`
→ `validate_transaction` → `commit_transaction`. El adaptador **no** es un
solver: no tiene Bernoulli, ni Jacobiano, ni plano neutro, ni recorte de
presiones propio, y llama una sola vez a `solve_pressure_network`.

### 16.3 Propietarios de la presión

| Escritor histórico | OFF | ON |
| --- | --- | --- |
| `GasExchangeSystem.step_thermodynamic_pressure` | igual que siempre | no se ejecuta |
| `GasExchangeSystem` promoción e igualación | igual | no se ejecuta (cuelga del anterior) |
| `GasExchangeSystem.step_pressure_venting` (relajación y factor posterior) | igual | no se ejecuta |
| `GasExchangeSystem.step_ppv` | igual | rechazo explícito si la PPV actuaría |
| `OxygenExchangeSystem` (dilución de presión) | igual | no se ejecuta: cuelga del bucle de aberturas |
| `ThermalSystem` ODE de presión de fase 3A | igual | no se ejecuta |
| `CombustionSystem` sobrepresión de deflagración | igual | no escribe presión |
| `RoomModel.reset` | igual | igual |
| **Red autoritativa** | no existe | **único propietario**: publica `overpressure_pa` con signo y refleja `pressure_pa_therm` |

### 16.4 Las siete rutas históricas

| Ruta | Qué es | Con ON |
| --- | --- | --- |
| 1. Purga o venteo por presión | presión + transporte al exterior | anulada |
| 2. Bernoulli con el exterior (O₂) | transporte por abertura | anulada |
| 3. Limpieza postincendio | ventilación por aberturas | anulada (factor 0) |
| 4. Mezcla entre recintos | transporte por abertura | anulada |
| 5. Especies al exterior y entre recintos | transporte por abertura | anulada |
| 6. Entrada de O₂ exterior y O₂ entre recintos | transporte por abertura | anulada |
| 7. Derrame de gases por puertas (térmico) | transporte por abertura | anulado |

Siguen ejecutándose una sola vez, porque **no** son transporte por aberturas:
combustión, generación y deposición de humo, química de CO/CO₂, radiación,
conducción a cerramientos, extinción y la renovación **ACH**, que representa
fugas del edificio no modeladas como abertura y no toca la presión.

### 16.5 Transacción atómica

Se transportan, desde la **zona de origen real** de cada segmento: masa de gas,
energía sensible, O₂ y las especies con estado zonal (CO, CO₂, HCN). El humo,
el HCl, la acroleína y el formaldehído **solo tienen masa global** en
`RoomModel`, así que se transportan con **mezcla completa** del recinto, que es
la semántica que ya usaba la ruta histórica de purga por aire. Queda declarado
como limitación: representarlos por zonas exigiría ampliar el estado.

- Todos los inventarios se leen del snapshot: el estado ya modificado de un
  recinto nunca es el origen de la siguiente abertura.
- Las salidas se agrupan por `(recinto, zona)` y, si piden más masa de la
  disponible, se escalan **colectivamente**, así que el resultado no depende del
  orden de aberturas ni de segmentos.
- El O₂ viaja como masa y las fracciones se **derivan** de las masas finales.
- La masa superior de una especie nunca supera su total, y ninguna queda
  negativa fuera de la tolerancia declarada (1e-9 kg, corregida de forma
  determinista).
- El exterior aporta su composición de contorno; una salida no se reinyecta por
  ninguna segunda ruta.

### 16.6 Política de fallo

Una solución no convergida, una presión absoluta imposible, una transacción no
finita, un inventario final imposible o un error de conservación dejan el paso
**sin aplicar nada**: el estado anterior queda íntegro, `pressure_network_failure`
nombra el motivo y se emite un `push_error`. **No hay vuelta atrás silenciosa** a
las rutas históricas.

### 16.7 PPV, ACH y limpieza postincendio

- **PPV**: no está representada como fuente ni como contorno del solver. Con la
  red encendida, si la PPV fuese a actuar, se rechaza con
  `failure_reason = "ppv_unsupported"`. No se simula compatibilidad.
- **ACH**: renovación ambiental independiente de las aberturas modeladas; sigue
  activa, no escribe presión y no duplica ningún caudal de la red.
- **Limpieza postincendio**: es ventilación por aberturas, así que con ON su
  factor es 0.

### 16.8 Pruebas de F2.2C

`tools/validate_pressure_network_integration.gd` (registrado en
`check_product.py`) con 16 grupos y 91 comprobaciones: la red no corre con el
flag apagado; equilibrio sellado; dos recintos iguales; dos recintos con
diferencia de presión (conservación de masa, energía, humo y CO); abertura
exterior en los dos sentidos; abertura bidireccional con origen zonal correcto;
limitación colectiva; energía sensible negativa; estado imposible sin commit;
O₂ conservado con fracciones derivadas; especies conservadas con coherencia
total/superior; ninguna escritura tardía sobre la presión canónica; PPV
rechazada; transacción inválida que no toca ninguna sala; puerta que se cierra y
deja de formar parte de la red sin salto de kPa.

La conservación se comprueba sobre la **transacción**, que es el nivel en el que
tiene que ser exacta; el paso completo del motor incluye además física local
legítima (deposición, ACH, química) que no es transporte.

`tests/test_pressure_network_integration.py` fija el contrato estático:
interruptor único apagado, ningún escenario lo enciende, orden de ejecución,
política de fallo, las ocho compuertas, el adaptador no es un segundo solver,
atomicidad, estado transportado y propietario único de la presión.

> **Corregido el 2026-09-18 por F2.2D1.** Esta sección decía además «puertas
> cerradas estancas», y esa prueba se ha reescrito: una puerta cerrada sigue
> siendo estanca **salvo** que el escenario encienda `closed_door_leakage_enabled`
> y le declare una clase de fuga, en cuyo caso aporta rendijas ELA, y solo
> rendijas. F2.2C tenía además dos defectos que D1 corrige: el identificador de
> abertura hacía colisionar dos puertas iguales entre las mismas salas, y la red
> leía `effective_open_fraction()`, que sumaba la deformación térmica heredada.

## 16.bis. F2.2D1: fuga fría de puerta cerrada (2026-09-18)

Integrada el mismo día, detrás de `closed_door_leakage_enabled`, apagado por
defecto y **dependiente** del interruptor de la red: pedir fuga sin red es un
error de configuración explícito, no algo que se ignore.

El diseño, la geometría, las mediciones de los casos A, Aw y B, las dos
limitaciones medidas y la campaña de 26 mutaciones están en
[`PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md`](PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md)
§16, que es donde vive el modelo de fuga. Aquí solo interesa lo que le toca a la
red:

- la red es **heterogénea**: un elemento declara su `flow_model`, y una entrada
  sin él es una abertura grande, exactamente como en F2.2B y F2.2C;
- la rendija se integra **dentro del residuo de Newton**, no después de
  resolver la presión;
- un `flow_model` desconocido se **rechaza**, y un elemento que no es abertura
  grande no entra en la integración de Bernoulli;
- `commit_count` cuenta las aplicaciones del aplicador atómico, que es la
  invariante de F2.2C —un solo dueño, una sola aplicación por paso— hecha
  comprobable desde fuera.

El recuento de interruptores del auditor pasa de 77 a **78**: §16.1 describe el
salto de 76 a 77 que hizo F2.2C, y `closed_door_leakage_enabled` añade el
siguiente.

> **Corregido el 2026-09-18 por F2.2C-R1.** Hasta esa fase, la presión exterior
> absoluta se reutilizaba como cero de la manométrica en **todas** las plantas,
> sin ajustar la columna. Eso era un defecto, no un convenio: un recinto a 6 m en
> equilibrio con su exterior publicaba −70,61 Pa. La convención correcta, el
> perfil `p_ext(z)` y el significado exacto de `gauge_pressure_pa` están en §17.

## 17. Conservación de masa y energía

- Cada intercambio produce una tupla `{masa, entalpía, O₂, humo, especies}` con
  un único origen y un único destino.
- El aplicador resta del origen exactamente lo que suma al destino.
- El hollín deja de gobernar la purga de gas: la fracción de gas sale del caudal
  másico, y el hollín viaja como una especie más, proporcional a su
  concentración.
- Residuos por paso publicados como diagnóstico, con guardarraíl (§20).
- La ecuación de estado se usa como **cierre diagnóstico**, no como fuente para
  reconstruir masa (requisito heredado del diagnóstico de 2026-07-12).

## 17. Convergencia y seguridad numérica

- El sistema es rígido (TN 1889v1, p. 9): el paso del motor (1/12 s) no puede
  resolver la presión con Euler explícito en casos de fuga pequeña.
  Se propone integración implícita o subpasos con control de residuo.
- Criterio de parada: residuo de masa por recinto (kg) ≤ tolerancia, residuo de
  energía por recinto (kJ) ≤ tolerancia **y** cambio de presión entre
  iteraciones (Pa) ≤ tolerancia. Los tres a la vez: converger en presión con
  residuo de masa alto es el fallo que el guardarraíl del §20 tiene que cazar.
- El punto fijo es de F2.2B (§15). F2.2A no se declara convergido por su cuenta
  ni devuelve una presión definitiva.
- Límite de iteraciones y detección de no convergencia con `failure_reason`.
  Un límite numérico solo puede **parar y avisar**, nunca sustituir a la física.
- Ningún recorte de presión en el estado: si aparece una presión imposible, es
  un fallo que hay que ver, no que ocultar.

## 19. Interruptor futuro y compatibilidad

- **Recomendación pendiente de autorización** (§22, decisión 3): un **único**
  interruptor nuevo, apagado por defecto, con el nombre provisional
  `pressure_network_solver_enabled`, declarado en `SimulationEngine` y
  clasificado en `audit_default_off_flags.py` y en
  `tests/test_p1r4_flag_activation_inventory.py` (el recuento sube de 76 a 77).
- Apagado: el camino heredado se ejecuta tal cual, byte a byte.
- Encendido: la presión del solver sustituye a `overpressure_pa` **y** a
  `pressure_pa_therm` como única fuente; `SimulationStateBuilder` deja de elegir
  entre campos.
- **Un solo interruptor porque presión y caudales son inseparables** (§13).
  Queda prohibido un interruptor que encienda la presión nueva dejando los
  caudales heredados, o al revés: eso reproduciría exactamente el
  desacoplamiento diagnosticado en RC-1 y RC-5.
- `phase3_thermodynamic_pressure_enabled` y `phase3_pressure_canonical_enabled`
  quedan marcados como obsoletos y se retiran solo cuando el solver pase las
  comprobaciones de referencia.

## 20. Plan de implementación por etapas

| Etapa | Contenido | Entregable | Requisito previo |
| --- | --- | --- | --- |
| **F2.2A** ✅ **hecha el 2026-09-18, sin integrar** | Evaluador puro de ecuaciones locales y residuos (§14, §14.1) | `sim/core/CompartmentPressureEquations.gd`, `tools/validate_compartment_pressure_equations.gd`, `tests/test_compartment_pressure_equations.py`, 19/19 mutaciones | F2.2-DIAG (este documento) |
| **F2.2B** ✅ **hecha el 2026-09-18, sin integrar** | Solver puro acoplado de red, dueño de la iteración (§15, §15.2) | `sim/core/Phase3CoupledPressureSolver.gd` **promovido** (entrada `solve_pressure_network`), `tools/validate_pressure_network_solver.gd`, `tests/test_pressure_network_solver.py`, 25 mutaciones | F2.2A |
| **F2.2C** ✅ **hecha el 2026-09-18** | Integración tras el interruptor único, un solo aplicador (§16) | `sim/core/PressureNetworkTransportSystem.gd`, compuertas en `SimulationEngine`, `GasExchangeSystem`, `OxygenExchangeSystem`, `ThermalSystem` y `CombustionSystem`, validador y tests | F2.2A+B en verde y comparación de sombra |
| **F2.2D** | Conexión de fuga (fase 1), deformación (fase 2) y vidrio (fase 3B) como fuentes de área | Adaptadores puros | F2.2C con la suite de referencia estable |

Ninguna etapa integra antes de tener los dos modelos puros validados. La regla
"integrar primero y corregir después" está expresamente prohibida. `F2.2-DIAG`
es la fase documental que cierra este documento y **no** produce código; no
debe confundirse con `F2.2D`, que es la conexión de fuga, deformación y vidrio.

## 21. Guardarraíles y mutaciones

Pruebas que la solución tendrá que superar, cada una diseñada para matar un
defecto concreto:

| Guardarraíl | Detecta |
| --- | --- |
| Recinto que se enfría publica presión negativa | Signo invertido o recortado a 0 |
| Presión de un caso conocido dentro de una banda absoluta | Pa tratados como kPa |
| `P(z)` construido solo con el perfil; el consumidor no suma columna | Doble flotabilidad |
| Suma de masas de todos los recintos + exterior constante | Masa creada o perdida |
| Suma de entalpías coherente con fuentes y sumideros | Energía creada o perdida |
| Barajar el orden de las aberturas no cambia el resultado | Dependencia del orden |
| Halvar el paso cambia la presión menos que la tolerancia | Dependencia del paso |
| Abrir una ventana grande descarga la presión en un tiempo acotado | Presión que no se descarga |
| 12 cm² no puede dar el caudal de una puerta abierta | Rendija tratada como puerta |
| Una puerta abierta no puede dar el caudal de una rendija | Apertura grande tratada como rendija |
| El humo y el O₂ viajan con el mismo caudal | Presión distinta por especie |
| Convergencia declarada solo con residuo bajo | Solver que miente |
| Interruptor apagado: dump byte a byte idéntico | El interruptor altera la referencia |

Mutaciones mínimas del arnés: invertir el signo de `ΔP`, multiplicar la presión
por 1 000, sumar la flotabilidad dos veces, purgar sin restar masa, usar la
fracción de hollín como fracción de gas, fijar el plano neutro en el suelo,
saltarse la iteración y declarar convergencia, ignorar una abertura, usar la
densidad ambiente en vez de la del recinto aguas arriba, y aplicar el solver con
el interruptor apagado.

## 22. Criterios cuantitativos de aceptación (candidatos)

No son definitivos: son **candidatos** respaldados por CFAST, por la resolución
temporal del motor (1/12 s) y por la sensibilidad medida en §7.

| Escenario | Criterio candidato | Tipo | Respaldo |
| --- | --- | --- | --- |
| Recinto sin fuego, sellado, **inicializado en equilibrio** | \|P\| ≤ 1 Pa durante 600 s | numérico (ausencia de deriva) | Sondas A y G3: 0,00 Pa con masa y temperatura constantes |
| **A. Enfriamiento de un recinto realmente sellado** (masa y volumen constantes, 293,15 K → 273,15 K) | `P_gauge` final = `101325 · (273,15/293,15 − 1) ≈ −6,9 kPa`, con signo correcto y acuerdo con el gas ideal dentro del 1 % | físico | Ec. de estado (TN 1889v1, ec. 2.4, p. 8). **No** se le aplica ninguna banda de decenas de Pa: sin fuga, la depresión es de kPa |
| **B. Recinto con fuga o conectado al exterior** | Ver §21.1: depresión de decenas de Pa reproducida con el signo correcto | físico | `cfast_two_room_door_open`, R0, 300-420 s |
| Sellado con fuego (fuga 84 cm²) | P dentro de un factor 2 de CFAST en t = 360 y 480 s; nunca > 5 kPa | físico | CFAST 167,9 y 168,2 Pa |
| Recinto con fuga de 12-21 cm² | Renovaciones equivalentes entre 0,1 y 2 h⁻¹ mientras P < 20 Pa | físico | Sonda C con la presión de flujo: 0,34-0,59 h⁻¹ |
| Abertura exterior grande | P por debajo de 10 Pa en menos de 10 s tras abrir | físico | Sonda D: la presión de flujo ya se queda en 2,0 Pa |
| Dos recintos conectados | Signo del caudal coherente con el signo de ΔP en cada cota; presiones igualadas con τ < 30 s | físico | CFAST ec. 4.1-4.5 |
| Cierre de puerta | Sin salto de presión por encima de 1 kPa en el paso del cierre | numérico | Sonda F: hoy 567 kPa |
| Conservación de masa | `mass_residual_kg` **por paso** ≤ 1e-9 de la masa del recinto | numérico | Precisión doble |
| Conservación de energía | `energy_residual_kj` **por paso** ≤ 1e-9 de la energía del recinto; si se mide como tasa, `energy_residual_kw` con el mismo umbral relativo, declarado aparte | numérico | ídem |
| Independencia del paso | Halvar `dt` cambia la presión máxima menos del 2 % | numérico | Sonda B: 0,12 % en la ODE actual, ya independiente |
| Regresión | Con el interruptor apagado, todos los informes byte a byte idénticos salvo `generated_at` | regresión | Práctica de las fases 1-3B |
| Hueco estructural aceptado | La diferencia con CFAST en los casos con extinción distinta sigue clasificada como hueco, pero con **magnitud acotada** | hueco | `gap_dispositions.json` |

### 21.1 Criterio B: la depresión medida por CFAST

No es un "caso análogo": es un caso concreto de la suite.

| Concepto | Valor |
| --- | --- |
| Caso | `cfast_two_room_door_open` (`sim/validation/cfast/cfast_two_room_door_open.in`) |
| Recinto | `R0`, 5,0 × 4,0 × 2,4 m (48 m³) |
| Conexión | Puerta a `Hall` de 0,9 m de ancho, de 0,0 a 2,0 m, abierta |
| Fuga | `LEAK_AREA_RATIO = 0,00017` (paredes) y `5,2e-5` (suelo) en ambos recintos: ≈ 0,0084 m² en R0 |
| Fuego | Madera, rampa tabulada hasta 1 280 kW, en R0 |
| Condiciones térmicas en el tramo | 300 s: T_sup 237,3 °C, T_inf 134,1 °C, interfaz 0,583 m; 360 s: T_sup 99,8 °C, T_inf 70,4 °C, interfaz 0,857 m |
| Valores esperados (CFAST) | 240 s: **+163,079 Pa**; 300 s: **−186,460 Pa**; 360 s: **−38,719 Pa**; 420 s: **−0,308 Pa**; 480 s: **+6,017 Pa** |
| SimuFire hoy | 360 s: **+198,42 Pa** (signo contrario) |

Criterio candidato: reproducir el **cambio de signo** entre 240 y 300 s y
mantenerse dentro de un factor 2 del valor de CFAST en 360 y 420 s. Aquí la
depresión es de decenas de Pa, y no de kPa, precisamente porque la puerta y la
fuga alivian la contracción; por eso este criterio y el A son distintos y no se
mezclan.

Distinción explícita: los criterios **físicos** comparan con CFAST o con el
orden de magnitud experimental; los **numéricos** comprueban el solver; los de
**regresión** protegen la física heredada; los **huecos** se documentan y no
bloquean, pero dejan de ser una excusa para 500 kPa.

## 23. Riesgos y decisiones pendientes

| Riesgo | Mitigación |
| --- | --- |
| El estado canónico de zonas todavía reconstruye masa por EOS | F2.2A y F2.2B solo leen; la sustitución de la reconstrucción se decide en F2.2C |
| El vector de incógnitas puede cambiar la interfaz de F2.2A | La interfaz de §14 recibe el estado candidato completo, no solo la presión, para que ampliarlo no rompa la firma |
| El solver implícito puede ser caro en escenarios grandes | Medir con `--phase3-coupled-pressure-solver-capture` antes de integrar |
| Cambiar la presión cambia humo, O₂ y temperatura a la vez | La suite de referencia completa se regenera solo al integrar, no en las fases puras |
| Las tolerancias actuales de los casos CFAST de presión son enormes (hasta 7 200 Pa) | No se tocan en F2.2-DIAG; se revisan al final de F2.2C, como cambio documentado aparte |

Decisiones que necesitan autorización antes de programar:

1. **Cota de referencia** de la presión manométrica: se propone el **suelo** de
   cada recinto (es lo que espera `ClosedDoorLeakageModel.p_floor_pa`).
2. **Retirada** de `phase3_thermodynamic_pressure_enabled` y
   `phase3_pressure_canonical_enabled`, y qué publica `state["overpressure_pa"]`
   durante la transición.
3. **Un interruptor o dos**: uno solo para presión y caudales, o separados.
4. Si F2.2B debe **sustituir** la maquinaria de sombra de `Phase3ZoneMassSystem`
   o construirse encima de ella.
5. Qué hacer, cuando el solver esté encendido, con **todas las rutas
   enumeradas en §4.2** que hoy inventan su propia escala de referencia (las
   siete rutas físicas de §4.3; las de sombra y observación solo leen).
6. ~~Vector de incógnitas de F2.2B~~ **decidido el 2026-09-18**: opción A,
   una presión manométrica de referencia por recinto (§13.1).
7. ~~Energía de zona negativa en el solver~~ **resuelta el 2026-09-18**: el
   solver promovido usa el mismo contrato físico que F2.2A (§15.2). Queda
   pendiente el mismo criterio en `Phase3ResidualProjection.gd`, que sigue
   rechazándola por el signo; se decide en F2.2C.
8. ~~Reutilización de `Phase3CoupledPressureSolver`~~ **resuelta el 2026-09-18**:
   se **promueve** ese componente como implementación de F2.2B, conservando su
   nombre histórico (§15.2). No hay un segundo solver.
9. **Qué hace F2.2C con la envoltura histórica** cuando el interruptor esté
   encendido: la maquinaria de sombra sigue llamando a `solve_coupled_pressure`
   y no puede aplicar resultados; hay que decidir si se migra a la entrada
   canónica o se retira.

## 24. Evidencia reproducible y comandos

Todo bajo `runs/pressure_f2_2_20260917/` (sin versionar):

```bash
python runs/pressure_f2_2_20260917/make_cases.py
bash  runs/pressure_f2_2_20260917/run_all.sh
python runs/pressure_f2_2_20260917/analyze.py        # tabla del §7

# sensibilidad al paso (dt = 1/6, 1/24, 1/48 s)
python scripts/run_scenario.py runs/pressure_f2_2_20260917/cases/B_closed_fire.json \
  --out-dir runs/pressure_f2_2_20260917/out/S_step_0.0208 --step 0.0208333333333333 \
  --phase3-zone-diagnostics

# caso C: modelo puro de fuga sobre las presiones medidas, sin integrar
APPDATA=<carpeta nueva> Godot_v4.7.1-stable_win64_console.exe --headless --path . \
  --script res://runs/pressure_f2_2_20260917/probe_leak.gd -- \
  --csv=<…/B_closed_fire/sim_log.csv> --out=<…/leak_flows.csv>
```

Entradas de referencia (SHA-256):

| Archivo | Bytes | SHA-256 |
| --- | ---: | --- |
| `sim/validation/cases/cfast_single_room_closed.json` | 2 594 | `044d10c3dd3a586223a036822965613cdf2b58b48428be2380b11fadcf902861` |
| `sim/validation/cfast/cfast_single_room_closed.in` | 2 324 | `73ad7629e75478e9f539634a35fe208e39d43cc79d99c7695a54434cfc4043c5` |
| `sim/validation/cfast/cfast_single_room_closed_compartments.csv` | 36 315 | `27a04487ad0ae9a008d3dff62ffbd9ff84f47c6284e6c49ca8f6c87eb530e16b` |
| `docs/literature/NIST/NIST_TN_1889v2_CFAST_Users_Guide.pdf` | 1 730 244 | `a2f638938e83ec8008946bdbc5b2e29e3700d4cf4162a2c01fcc2532810afb85` |

Los hashes de los tres primeros son los mismos que registró la evidencia P1R8,
así que la entrada no ha cambiado desde entonces.

## 25. Qué queda expresamente sin implementar

> **Actualizado el 2026-09-18.** F2.2A, F2.2B y F2.2C están implementadas e
> integradas (§14.1, §15.2 y §16): `pressure_network_solver_enabled` existe,
> está apagado por defecto y, cuando se enciende, la red es el único dueño de
> la presión y del transporte por aberturas. **F2.2D1** (fuga fría de puerta
> cerrada) se integró ese mismo día detrás de `closed_door_leakage_enabled`,
> que además exige el interruptor de la red. Las frases de versiones anteriores
> que decían que nada de esto estaba integrado, que no existía el interruptor o
> que F2.2 había que resolverla antes de integrar **ya no son ciertas**.

Lo que sigue sin implementar:

- **F2.2D2**: la deformación prescrita de puerta caliente
  (`ClosedDoorDeformationModel`) no está conectada a la red. D1 dejó de leer
  `effective_open_fraction()` justamente para que `thermal_gap_fraction` no se
  colara como abertura de Bernoulli; D2 tendrá que darle sus propios segmentos.
- **F2.2D3**: el vidrio (`GlazingIntegrityModel`, `GlazingOpeningGeometryModel`)
  tampoco está conectado, y su modelo térmico y su modelo probabilista **no
  existen**.
- **F2.2D4**: la calibración de las clases de ELA, del reparto por cotas y del
  exponente. Los tres valores de D1 son **provisionales**.
- La corrección de la purga por fracción de hollín (RC-4), abierta desde
  2026-07-12.
- La representación de presiones negativas (criterios A y B de §21).
- La unificación de las escalas de referencia de las siete rutas físicas
  enumeradas en §4.2 y clasificadas en §4.3.
- HVAC, F2.1, modelo térmico de rotura de vidrio y modelo probabilista.
- Cualquier cambio de tolerancias, casos, resultados de referencia o
  clasificación de huecos.
- La activación en escenarios normales: ningún escenario del producto enciende
  la red ni la fuga.
- `Phase3ResidualProjection` conserva su limitación independiente sobre energía
  negativa, que ni F2.2C ni F2.2D1 han tocado.

**La frase de la versión de diagnóstico —«en esta fase no se ha modificado ni
una línea de `sim/`»— valía para F2.2-DIAG. Desde F2.2A el motor sí ha
cambiado, y cada fase lo dice en su propia sección.**

## 17. F2.2C-R1: referencia hidrostática multiplanta y convergencia del portal (2026-09-18)

> **Estado: cerrada.** El portal de tres plantas converge en las tres variantes,
> 0 pasos descartados de 7 200. La hipótesis de partida —que el fallo venía de la
> columna exterior— resultó **cierta como defecto pero falsa como causa**, y la
> causa real quedó demostrada antes de tocar ninguna tolerancia.

### 17.1 Lo que se midió antes de cambiar nada

El encargo exigía reproducir el fallo y clasificarlo, no agruparlo bajo «no
converge». Reproducción exacta con `runs/f22c_r1_20260918/diagnose.gd`:

| variante | pasos sin aplicar | código |
|---|---|---|
| **P0** puertas estancas, sin rendijas | **2 476 / 7 200 (34,4 %)** | `solver_compartment_equations_rejected_candidate` |
| **P1** con la fuga fría de D1 | **4 228 / 7 200 (58,7 %)** | el mismo |
| **P2** puertas abiertas | 0 / 7 200 | — |

Las 2 476 de P0 tienen **un solo** mensaje, sin una sola excepción:

```
candidate_state lower_gas_kg must be >= 0
```

Primer fallo en **t = 177,08 s**, último a los 600 s, hasta **697 fallos
consecutivos**. En ese primer paso el rellano superior (sala 6, suelo a 5,8 m)
entra con `lower_gas_kg = 0,0000` y `upper_gas_kg = 51,38` —la capa caliente
ocupa todo el recinto— y el paso le pide donar **−0,023 kg**, que son
exactamente los 0,278 kg/s netos de `op_7` por el paso de tiempo.

### 17.2 La causa raíz, demostrada

`op_7` es un **hueco vertical de escalera** (`is_vertical = true`).
`OpeningModel` lo documenta desde SF-R7: «cuando `is_vertical = true`, el flujo
está impulsado por flotabilidad térmica en lugar de por Bernoulli horizontal con
plano neutro», y la ruta histórica tiene su rama dedicada.

**F2.2C perdió esa distinción.** El adaptador metía el hueco en la red como un
vano de Bernoulli anclado al suelo de `room_a`, con lo que el vano quedaba entre
z = 2,9 y 4,3 m, es decir **entero por debajo del suelo de la sala 6**, que está
a 5,8 m. El perfil de esa sala se extrapolaba 2,9 m por debajo de su propia
losa, toda esa cota caía del lado «inferior», y su zona inferior vacía tenía que
donar el caudal completo.

A eso se sumaban tres cosas más, que el diagnóstico fue destapando en orden:

1. **El datum exterior era global.** `reference_mass_kg` se construía con la
   presión exterior de la cota de referencia en todas las plantas.
2. **La etiqueta de zona podía elegir la zona vacía.** En un borde la decidía un
   empate de coma flotante.
3. **El residuo no conoce el inventario por zonas.** El solver trabaja con
   totales de sala y F2.2A valida **por zona**: entre ambas cosas cabe un estado
   que parece bueno en total y es imposible por zonas.

Conviene registrar que **la primera corrección empeoró el portal al 64,4 %**. El
modelo nuevo de hueco mueve mucho más gas que el vano mal colocado al que
sustituía (≈5 kg/s frente a 0,28), así que vaciaba antes la zona inferior. El
defecto (3) seguía intacto, y es el que finalmente cerró el caso.

### 17.3 Lo que M1–M6 midieron, antes y después

| fixture | qué separa | antes | después |
|---|---|---|---|
| **M1** | recintos sellados a 0, 3 y 6 m | gauge **−35,30** y **−70,61 Pa** (= ρ·g·z) | 0 Pa |
| **M2** | una abertura exterior por planta | **0,25** y **0,50 kg/s** inventados | 0 |
| **M3** | columna interior isoterma | chimenea espuria | sin intercambio |
| **M4** | columna interior caliente | no converge | converge |
| **M5** | edificio desplazado +20 m | absolutas incoherentes | invariante |
| **M6** | conexión entre plantas | no converge | converge en los dos órdenes |

En total, de **47 fallos** a **99 comprobaciones PASS**.

### 17.4 Convención exterior, ya inequívoca

El contorno se declara con una presión absoluta **en una cota**:

```
outside = {pressure_abs_pa, reference_z_m, temp_k, reference_temp_k}
```

y la presión a cualquier otra cota es

```
p_ext(z) = p_ext(z_ref) - rho_ext * g * (z - z_ref)
```

`sim/core/ExteriorPressureProfile.gd` es el **único dueño** de esa fórmula. La
usan F2.2A, el solver, el adaptador y los validadores; copiarla en cada sistema
es exactamente lo que produjo el defecto.

**`reference_z_m` ausente significa 0 m**, que es lo que valía implícitamente en
todos los casos históricos, y por eso un escenario de una sola planta a cota
cero da exactamente los mismos números que antes.

**Convención declarada:** densidad exterior **constante**, evaluada a la
temperatura del contorno. Es la aproximación que ya usaba el motor. Su magnitud
es `g·H·ρ·(ρ·g·z/P)`: a 5 m de altura y 2,5 m de columna son **0,02 Pa**. Las
tolerancias de M3 y M5 **se derivan de esa fórmula**, no se eligen: el defecto
que esta fase corrige valía ρ·g·z, tres órdenes de magnitud más.

### 17.5 Qué significa exactamente `gauge_pressure_pa`

```
p_gauge_floor = p_room(floor_z) - p_ext(floor_z)
```

Es decir, **el exterior de su propio suelo**, no el de la cota de referencia. Por
tanto:

```
p_room_abs_floor = p_ext(floor_z) + p_gauge_floor
M_ref_room       = p_ext(floor_z) * V / (R * T_ref)
```

Y como cada manométrica se mide contra un exterior distinto, comparar dos
recintos de plantas distintas necesita devolverlas a la misma cota:

```
dp(z) = (p_a - p_b) + [p_ext(suelo_a) - p_ext(suelo_b)]
        - g * integral ( rho_a - rho_b ) dz'
```

El corchete vale **exactamente cero** cuando los dos suelos están a la misma
altura, así que ningún escenario de una planta cambia ni un bit.

**Consecuencia medida y verificada:** subir un edificio 10 m dejando la
referencia en el suelo sube toda manométrica en **117,679800000 Pa**, frente a
ρ·g·h = **117,679800000 Pa**, con la presión absoluta intacta. La prueba 07 de
F2.2B afirmaba lo contrario —«subir el edificio no cambia ninguna presión»— y
eso *era* el defecto; ahora exige esa igualdad y añade la invariancia que sí es
cierta: mover el edificio **y** su referencia juntos no cambia nada.

### 17.6 El hueco de suelo/techo, clase de elemento propia

`sim/core/VerticalShaftFlowModel.gd`. Dos términos, físicamente distintos:

1. **Neto por presión**, que es lo que acopla las dos presiones en el residuo:
   `m_p = Cd · A · sqrt(2 · rho_origen · |dp|)`.
2. **Intercambio por flotabilidad**, solo si el gas de abajo es **más ligero**:
   `m_b = Cd · A · sqrt(2 · g · sqrt(A) · |d_rho| · rho_media)`.
   La raíz del área es la escala de longitud: no hay altura de vano, hay un
   agujero. Sube esa masa y baja esa masa; no es caudal neto.

Lo decide la **densidad**, no la temperatura: con gases de distinta composición
la temperatura sola mentiría. Si lo de abajo pesa más, la estratificación es
estable y el intercambio es cero.

Cada lado se evalúa **en su propio borde** —el techo del de abajo y el suelo del
de arriba—, y cuando las plantas no son contiguas el hueco atraviesa la losa y
su columna entra en el balance. Un hueco contra el exterior se rechaza; entre
dos recintos de la misma planta, también.

### 17.7 Una zona sin inventario no dona

Dos reglas, y las dos hacían falta:

- la **etiqueta** de zona a una cota cae a la otra zona cuando la geométrica
  está vacía (antes lo decidía un empate de coma flotante);
- la **donación** se reparte entre las dos zonas según lo que cada una puede
  entregar en el paso. Ni se inventa masa ni se recorta caudal: cambia de dónde
  sale.

### 17.8 Estabilización numérica: la que ya existía

El hueco usa **la misma** linealización por debajo de `dp_regularization_pa` que
el vano de Bernoulli ya usaba, porque la derivada del orificio no está acotada
en el origen y dos huecos en serie hacen oscilar a Newton. **No se ha añadido
ningún knob, ni subido ninguna tolerancia, ni ampliado el número de
iteraciones.** Las tolerancias canónicas siguen siendo 1e−6 Pa, 1e−9 kg y
1e−6 kJ, y hay una prueba que las fija.

### 17.9 Resultado

| variante | antes | después |
|---|---|---|
| **P0** | 34,4 % | **0 / 7 200** |
| **P1** | 58,7 % | **0 / 7 200** |
| **P2** | 0 % | **0 / 7 200** |

Sin fallbacks, sin aplicaciones parciales, sin presiones absolutas inválidas y
sin residuos fuera de tolerancia.

### 17.10 Las otras dos incidencias siguen abiertas y separadas

Ninguna se ha tocado en esta fase, y **no deben mezclarse** con ella:

- **R2 — pérdida histórica de masa.** Una sala pierde alrededor de un tercio de
  su masa de gas mientras se calienta (48,0 → 31,0 kg en 100 s). Con la red
  **apagada** pierde lo mismo al kilogramo (31,0356 frente a 31,0348), así que
  la ruta propietaria es histórica y está **sin identificar**. Efecto: las
  medidas de fuga de D1 son una **cota inferior**. No atribuible a la rendija ni
  al solver.
- **R3 — envolvente exterior cerrada ausente.** Con la red activa, una ventana
  exterior cerrada es inerte y el caso Aw coincide exactamente con A. F2.2C
  desactivó la purga exterior histórica (`window_leakage_area_m2`) y la red
  canónica no incorporó un elemento equivalente. Hace falta una fase separada de
  fuga de envolvente **dentro** de la red; no se debe resolver reactivando la
  purga histórica en paralelo.

### 17.11 Qué queda bloqueado hasta cerrar esas dos

**D2 (deformación), D3 (vidrio) y D4 (activación y calibración) no se han
iniciado.** El orden de trabajo es: R2, después R3, y solo entonces D2/D3/D4.
