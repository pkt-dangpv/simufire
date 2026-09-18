# Diagnóstico y diseño: sobrepresión de recintos cerrados (F2.2)

> **Estado (2026-09-18): F2.2-DIAG cerrada. Solo diagnóstico y diseño.**
>
> `F2.2-DIAG` es **esta fase documental**. Las etapas de implementación son
> `F2.2A` (ecuaciones locales puras), `F2.2B` (solver acoplado de red), `F2.2C`
> (integración tras interruptor) y `F2.2D` (conexión de fuga, deformación y
> vidrio). `F2.2-DIAG` nunca designa una etapa de código.
> - **No hay código nuevo**: no se ha tocado `sim/`, ni el editor, ni los
>   escenarios, ni los casos, ni las tolerancias, ni la clasificación de huecos.
> - **F2.2A, F2.2B, F2.2C y F2.2D siguen sin implementar** (§19).
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
- **Pendiente antes de programar**: decidir si el vector de incógnitas de F2.2B
  contiene **solo** las presiones de referencia o también variables de zona
  (volumen de capa, temperaturas o energías), según la correspondencia
  definitiva con el estado canónico de `Phase3ZoneMassSystem`. CFAST integra las
  cuatro variables juntas (ec. 2.5-2.8), así que la opción "solo presiones"
  solo vale si las variables de zona las sigue llevando el motor con el mismo
  paso.

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

## 16. Conservación de masa y energía

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

## 18. Interruptor futuro y compatibilidad

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

## 19. Plan de implementación por etapas

| Etapa | Contenido | Entregable | Requisito previo |
| --- | --- | --- | --- |
| **F2.2A** | Evaluador puro de ecuaciones locales y residuos (§14) | `sim/core/CompartmentPressureEquations.gd`, validador, tests, mutaciones | F2.2-DIAG (este documento) |
| **F2.2B** | Solver puro acoplado de red, dueño de la iteración (§15) | `sim/core/PressureOpeningNetworkSolver.gd`, validador con red de 1, 2 y N recintos | F2.2A |
| **F2.2C** | Integración tras interruptor, un solo aplicador | Cambios en `SimulationEngine`, `GasExchangeSystem`, `OxygenExchangeSystem`, `ThermalSystem` | F2.2A+B en verde y comparación de sombra |
| **F2.2D** | Conexión de fuga (fase 1), deformación (fase 2) y vidrio (fase 3B) como fuentes de área | Adaptadores puros | F2.2C con la suite de referencia estable |

Ninguna etapa integra antes de tener los dos modelos puros validados. La regla
"integrar primero y corregir después" está expresamente prohibida. `F2.2-DIAG`
es la fase documental que cierra este documento y **no** produce código; no
debe confundirse con `F2.2D`, que es la conexión de fuga, deformación y vidrio.

## 20. Guardarraíles y mutaciones

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

## 21. Criterios cuantitativos de aceptación (candidatos)

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

## 22. Riesgos y decisiones pendientes

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
6. **Vector de incógnitas de F2.2B** (§13 y §15): solo presiones de referencia,
   o también variables de zona (volumen de capa, temperaturas o energías),
   según la correspondencia definitiva con el estado canónico de
   `Phase3ZoneMassSystem`.

## 23. Evidencia reproducible y comandos

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

## 24. Qué queda expresamente sin implementar

- El evaluador puro de ecuaciones locales (F2.2A) y el solver acoplado de red
  (F2.2B).
- La integración tras interruptor (F2.2C) y la conexión de fuga, deformación y
  vidrio (F2.2D).
- La corrección de la purga por fracción de hollín (RC-4), abierta desde
  2026-07-12.
- La representación de presiones negativas (criterios A y B de §21).
- La unificación de las escalas de referencia de las siete rutas físicas
  enumeradas en §4.2 y clasificadas en §4.3.
- HVAC, F2.1, modelo térmico de rotura de vidrio y modelo probabilista.
- Cualquier cambio de tolerancias, casos, resultados de referencia o
  clasificación de huecos.

**En esta fase no se ha modificado ni una línea de `sim/`, de los casos, de los
informes ni de los tests.**
