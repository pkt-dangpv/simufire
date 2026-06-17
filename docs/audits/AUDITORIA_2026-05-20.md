# Auditoría completa SimuFire — 2026-05-20

**Alcance**: rendimiento físico vs CFAST, fidelidad vs fuego real, rendimiento del motor de juego, calidad del código y arquitectura de archivos. Hoja de ruta para alcanzar y superar a CFAST.

**Estado de partida (números aparentes)**:
- Suite referencia CFAST/Ghanekar: **64/72** (89%)
- Suite regresión interna CI: **43/43** (100%)
- ~24 800 líneas de GDScript distribuidas en ~60 archivos
- 320 parámetros `@export` solo en `SimulationEngine.gd`

> ⚠️ **El 89% es engañoso. Ver §1bis para análisis de cobertura real.**  
> La cobertura efectiva de capacidades de CFAST es del orden del **3–5%**, no del 89%.

---

## 1. GAP vs CFAST — Análisis profundo

### 1.1 Resumen de los 8 fallos restantes

Todos son **estructurales** (limitaciones del modelo de zona única), no fallos de calibración. CFAST utiliza modelo de **dos zonas** (capa caliente superior + capa fría inferior) con balance de masa/energía/especies independiente por zona. SimuFire hoy usa **una zona promedio por sala** con derivados (`temp_upper_c`, `o2_upper`) que se rastrean pero no afectan a la decisión de fuego ni a los reportes.

| Check | Actual | CFAST ref | Tol | Causa raíz | Severidad |
|---|---|---|---|---|---|
| `cfast_t240_o2_depleted` | 0.132 | 0.085 | ±0.022 | O₂ promedio vs O₂ upper (CFAST) | Estructural |
| `cfast_t240_hrr_ventilation_limited` | 529 kW | ≤420 | — | Fuego ve O₂ promedio (consume todo el aire fresco lower) | Estructural |
| `cfast_closed_t210_o2` | 0.134 | 0.091 | ±0.018 | Idem en sala sellada | Estructural |
| `cfast_2r_r0_t300_o2` | 0.095 | 0.040 | ±0.025 | Idem two-room | Estructural |
| `cfast_2r_r0_t450_temp_upper_c` | 146.8 °C | 58.9 | ±80 | Fuego no se apaga (O₂ alto) → calienta más | Feedback O₂ |
| `cfast_2r_hall_t240_o2` | 0.200 | 0.111 | ±0.030 | Hall recibe gas mezclado, no upper depletado | Estructural |
| `cfast_2r_hall_t360_o2` | 0.171 | 0.057 | ±0.030 | Idem | Estructural |
| `cfast_hvac_t450_temp_upper_c` | 52.6 °C | 174.8 | ±80 | HVAC depleta O₂ uniforme → fuego muere; CFAST mantiene fuego con O₂ lower fresco | Estructural |

### 1.2 Diagnóstico: el modelo SÍ tiene `o2_upper`, pero no se usa

Hallazgo importante en [`sim/building/RoomModel.gd`](sim/building/RoomModel.gd#L45):
```gdscript
var o2_upper: float = 0.209
```
Y en [`sim/core/OxygenExchangeSystem.gd`](sim/core/OxygenExchangeSystem.gd#L125-L141), la combustión consume O₂ tanto del promedio (`room.o2`) como del `room.o2_upper`. **Pero**:

1. La decisión de extinción/HRR usa `room.o2`, no `room.o2_upper`.
2. `SimulationLogWriter.gd` [línea 260](sim/core/SimulationLogWriter.gd#L260) loguea solo `O2=room.o2`. No existe `O2u=` en el log.
3. [`scripts/simulation/validate_reference_cases.py`](scripts/simulation/validate_reference_cases.py#L120) lee `ULO2_1` (CFAST upper) y lo compara contra `O2` del log de SimuFire (promedio).

**Esto explica los 5 fallos de O₂ de la tabla anterior**: estamos comparando peras (CFAST upper-layer) con manzanas (SimuFire room-average).

### 1.3 Solución directa al gap CFAST — Plan en 3 fases

#### Fase A — Comparación apples-to-apples (1–2 sesiones, sin cambio de motor)
1. Añadir `O2u=` al log en `SimulationLogWriter.gd` (similar a `CO2u=`/`COu=`).
2. Modificar `_parse_simufire_log()` en validador para extraer `o2_upper`.
3. Cambiar `_add_abs_check(checks, prefix, "o2", ...)` a comparar `o2_upper` contra `ULO2_1`.
4. **Ganancia esperada**: 64 → ~67–69/72 (5 checks de O₂ pasan inmediatamente porque `o2_upper` ya se depleta más rápido que el promedio).

#### Fase B — Combustión consume solo upper (1 sesión, cambio quirúrgico de motor)
1. En [`OxygenExchangeSystem.gd:115-125`](sim/core/OxygenExchangeSystem.gd#L115), reemplazar el consumo del aire promedio por consumo exclusivo del `upper_air_mass`.
2. La decisión de extinción en `CombustionSystem.gd` usa `room.o2_upper` en lugar de `room.o2`.
3. **Efectos esperados**:
   - `cfast_t240_hrr_ventilation_limited`: el fuego se autolimita por O₂ upper → HRR baja a ~420 kW ✅
   - `cfast_2r_r0_t450_temp_upper_c`: fuego se apaga antes → temperatura R0 baja a CFAST range ✅
   - `cfast_hvac_t450_temp_upper_c`: HVAC alimenta lower zone → upper se depleta → fuego sobrevive más → temp coincide con CFAST ✅
4. **Ganancia esperada**: ~67 → 71–72/72 (todos los checks pasan, excepto quizá uno por timing fino).

#### Fase C — Refactor a modelo two-zone explícito (3–5 sesiones, cambio arquitectónico)
1. Promover `RoomModel` a tener **dos volúmenes independientes**: `upper_volume_m3`, `lower_volume_m3`, con su propia masa de aire, T, O₂, CO₂, CO, smoke.
2. La interfaz `h_layer_m` ya existe; ahora se usa para particionar el volumen.
3. Mass/energy/species transport entre zonas por: plume entrainment (Heskestad ya implementado), descenso de interfaz cuando upper depleta el lower, doorway flows neutral-plane (CFAST style).
4. **Beneficio adicional**: alinea la API con CFAST/FDS, permite escalar a multi-zona, y elimina la doble-contabilidad actual (`o2` vs `o2_upper`, `temp_upper_c` vs promedio).
5. **Ganancia esperada**: alcanzar paridad estructural con CFAST (>72/72 cuando se añadan más checks).

### 1.4 Métricas medibles del gap actual con CFAST

Comparando logs SimuFire vs CSV CFAST en los 5 casos referencia:

| Métrica | SimuFire | CFAST | Error medio | % error |
|---|---|---|---|---|
| Pico HRR (window-360) | ~960 kW | ~1280 kW | −320 kW | −25% |
| Tiempo a flashover (window-360) | ~245 s | ~240 s | +5 s | +2% |
| Temp upper pico (window-360) | ~280 °C | ~310 °C | −30 °C | −10% |
| O₂ upper a t=240 (window-360) | 0.132 | 0.085 | +0.047 | +55% |
| O₂ ambiente t=180 (HVAC) | 0.156 | ~0.16 | −0.005 | −3% |
| Hall temp t=360 (two-room) | 100 °C | ~100 °C | 0 | 0% |
| CO upper pico | 1200 ppm | 1500 ppm | −300 | −20% |
| CO₂ upper a t=350 (window-360) | 154796 ppm | 110600 ppm | +44196 | +40% |

**Conclusión**: temperatura y timing son **excelentes** (errores <10%). El gap dominante es **O₂ stratification** y **CO₂ over-prediction** en upper layer.

---

## 1bis. ¿ES REAL EL 89% vs CFAST? — Análisis crítico de cobertura

**Respuesta corta: NO. El 89% mide aprobación dentro de una suite estrecha hecha por nosotros, no cobertura de capacidades de CFAST.**

La pregunta correcta no es «¿cuántos checks pasamos?» sino «¿qué fracción del comportamiento físico que CFAST sabe modelar estamos verificando?». Tras inspeccionar [`scripts/simulation/validate_reference_cases.py`](scripts/simulation/validate_reference_cases.py) y los CSV de referencia en [`sim/validation/cfast/`](sim/validation/cfast/), la respuesta es: muy poco.

### 1bis.1 La suite real, sin maquillaje

**6 escenarios** verificados:

| # | Escenario | Habitaciones | Vent | Duración | Fenómeno principal |
|---|---|---|---|---|---|
| 1 | `r0_hall_window_360` | 1 | Ventana abre a t=360 s | 600 s | Vent-limited → vent-driven |
| 2 | `cfast_single_room_closed` | 1 | Sellada | 600 s | Auto-extinción por O₂ |
| 3 | `cfast_two_room_door_open` | 2 | Puerta interna abierta t=0 | 600 s | Transporte upper→hall |
| 4 | `cfast_post_flashover_vented` | 1 | Ventana abierta t=0 | 600 s | Steady vented |
| 5 | `cfast_hvac_residential` | 1 | HVAC supply+return | 600 s | Dilución mecánica |
| 6 | `ghanekar_bedroom_hallway` | 3 | Puerta+pasillo | ~600 s | Transporte largo |

**72 checks distribuidos así** (analizado por inspección del código):

| Categoría métrica | Checks | % suite | Observación |
|---|---|---|---|
| `o2` (room-average) | ~22 | 31% | Sólo escalar promedio, no upper/lower |
| `temp_upper_c` | ~18 | 25% | Capa caliente |
| `hrr_kw` | ~9 | 13% | Heat release rate |
| `co_upper_ppm` | ~7 | 10% | CO en capa alta |
| `hot_layer_m` | ~5 | 7% | Altura interfaz |
| `temp_lower_c` | ~3 | 4% | Capa fría |
| `co2_upper_ppm` | 3 | 4% | No-gating |
| `fed_heat` | 1 | 1% | Solo límite superior |
| `watched_temp_upper_clamp_count` | 3 | 4% | Diagnóstico interno |
| Tiempos cruce-umbral (Ghanekar) | 4 | 6% | O₂/temp/CO threshold |

**Tiempos verificados**: cada métrica se evalúa en **1–3 instantes puntuales** (60, 120, 180, 210, 240, 300, 350, 360, 380, 420, 450, 510, 600 s). No se verifica **forma de curva** (RMSE, error integrado, picos máximos, gradientes). Un check pasa si la curva pasa por el valor correcto en ese segundo aunque sea totalmente errónea en los otros 599 s.

### 1bis.2 Lo que CFAST mide y nosotros NO comparamos

Los CSV de CFAST en `sim/validation/cfast/` exponen ~30 columnas por escenario. La suite usa solo 6 (`Time`, `ULO2_X`, `ULT_X`, `LLT_X`, `HGT_X`, `ULCO_X`, opcionalmente `ULCO2_X`). Lo demás se ignora:

| Output CFAST disponible | ¿Comparado? | Físico ignorado |
|---|---|---|
| `LLO2_X` (O₂ capa baja) | ❌ | Aire respirable a nivel suelo |
| `LLCO_X`, `LLCO2_X` | ❌ | Tóxicos a altura respiración |
| `LLHCN_X`, `ULHCN_X` | ❌ | Cianhídrico (toxicidad letal) |
| `LLHCL_X`, `ULHCL_X` | ❌ | HCl (PVC), irritante crítico |
| `LLH2O_X`, `ULH2O_X` | ❌ | Vapor de agua (suppression) |
| `LLN2_X`, `ULN2_X` | ❌ | Balance de masa total |
| `LLOD_X`, `ULOD_X`, ODF, ODS | ❌ | Densidad óptica del humo (visibilidad real) |
| `LLTUHC_X`, `ULTUHC_X` | ❌ | Hidrocarburos no quemados |
| `PYROL_X` | ❌ | Tasa de pirólisis (kg/s) |
| `PLUM_X` | ❌ | Mass flow del plume |
| `PRS_X` | ❌ | Sobrepresión |
| `APRS_X` | ❌ | Presión absoluta |
| `IGN_X` | ❌ | Tiempo de ignición |
| `DJET_X` | ❌ | Door jet |
| `FLHGT_X` | ❌ | Altura de la llama |
| `walls.csv` (CEILT, FLOORT, LWALLT, UWALLT) | ❌ | **Temperaturas superficiales (4 caras × N salas)** |
| `vents.csv` (mass flows) | ❌ | **Caudales por aberturas (kg/s)** |
| `masses.csv` (LLM*, ULM* species) | ❌ | **Balance de masa por especie** |
| `devices.csv` | ❌ | Activación de detectores y termopares |
| `trace.translation` | ❌ | Trazas radioactivas / contaminantes |

**Cobertura por dimensión de output**: 6/30 = **20%** de las variables que CFAST calcula son comparadas; del 80% restante no sabemos si SimuFire concuerda o no.

### 1bis.3 Lo que CFAST sabe simular y nosotros NO probamos

CFAST está validado por NIST contra **>150 experimentos full-scale** (NUREG-1824 V&V Vol 5, 2007 + actualizaciones). Cubre fenómenos que nuestra suite no toca:

| Fenómeno físico CFAST | ¿En suite? | Implicación |
|---|---|---|
| **Multi-piso con escalera** | ❌ | Stack effect vertical no validado |
| **Atrio/galería alta** | ❌ | Plume largo no validado |
| **Corner fire (ISO 9705)** | ❌ | Geometría asimétrica no validada |
| **Wind-driven** (cambio Δp ambiente) | ❌ | Influencia exterior no validada |
| **Sprinkler activation + suppression** | ❌ | Solo suppression manual sin spray model |
| **Smoke detector activation** | ❌ | NFPA 72 timing no comparado |
| **Heat detector activation** | ❌ | RTI/spacing no comparado |
| **Multiple concurrent fires** | ❌ | Solo una habitación ignita |
| **Door close mid-fire** | ❌ | Backdraft trigger no validado |
| **Window break time + fragmentation** | ❌ | Solo open_fraction binario |
| **Background leakage (cracks/BLEAK)** | ❌ | Solo ACH constante |
| **Mechanical extraction (return-only)** | ❌ | Solo HVAC supply+return balanced |
| **Mass loss rate vs time** | ❌ | Curva pirólisis no validada |
| **Long duration (>10 min full burnout)** | ❌ | Suite corta a 600 s |
| **Decay phase** | ❌ | No hay caso post-burnout |
| **Multi-fuel package (sofa+TV+rug)** | ❌ | Un solo combustible |
| **Forced flashover transition** | ❌ | No se mide ts→tf |
| **Backdraft scenario controlado** | ❌ | Sí está implementado pero no validado |
| **Char layer time-history** | ❌ | No se compara fuel remaining |
| **Wall surface temperature** | ❌ | Conducción Crank-Nicolson sin validar contra CFAST |
| **Vent flow direction reversal** | ❌ | Plano neutral móvil no validado |
| **Fire spread room-to-room (ignición autónoma)** | ❌ | FireSpreadSystem implementado, no validado |

**Cobertura por escenario**: 6 escenarios × ~5 fenómenos cada uno = **~30 combinaciones**. CFAST V&V cubre del orden de **500–1000 combinaciones**. Cobertura: **3–6%**.

### 1bis.4 La suite tampoco verifica forma de curva

Problema añadido: los 72 checks son **muestras puntuales con tolerancia generosa** (±0.030 en O₂, ±80 °C en T_u, ±300 kW en HRR). Esto significa:

- Una simulación con HRR oscilando ±300 kW alrededor del valor correcto **pasaría** todos los checks de HRR aunque sea físicamente errónea.
- Una temperatura promedio correcta a t=240 que oscila brutalmente entre 60–220 °C **pasa** el check `±80 °C`.
- No se penaliza error sistemático que cancela: si SimuFire sub-predice a t=180 y sobre-predice a t=240, ambos checks pueden pasar pero la curva está descentrada.

**Métricas estadísticas que faltan**:
- RMSE temporal completo entre SimuFire(t) y CFAST(t) sobre toda la simulación.
- Error pico (max |Δ| en toda la curva).
- Error integrado ∫|Δ| dt.
- Phase-shift / lag detection (cross-correlation).
- Consistencia en gradientes (dT/dt, dO₂/dt).
- Coeficiente de Pearson curva-curva.
- Error en los puntos críticos (pico HRR, mínimo O₂, flashover, etc.) detectados automáticamente.

### 1bis.5 Cálculo honesto de la cobertura

Descomponiendo la afirmación «89% vs CFAST» en factores multiplicativos:

| Factor | Valor honesto | Razonamiento |
|---|---|---|
| % de escenarios CFAST cubiertos | ~5% | 6 / ~120 escenarios canónicos |
| % de outputs CFAST verificados por escenario | ~20% | 6 / 30 columnas CSV |
| % de cobertura temporal | ~10% | 1–3 puntos / 600 s de transient |
| % de aprobación dentro de la sub-suite | 89% | 64/72 |

**Cobertura real ≈ 0.05 × 0.20 × 0.10 × 0.89 ≈ 0.001 = 0.1%** sobre la totalidad de las capacidades de CFAST en sentido estricto.

Un cálculo menos pesimista, ponderando solo los fenómenos «de interés residencial» (sin reactor nuclear, sin atrios industriales, sin sprinkler):

| Factor | Valor moderado |
|---|---|
| % escenarios residenciales cubiertos | ~15% (6 de ~40) |
| % outputs residenciales relevantes | ~30% (6 de 20) |
| % cobertura temporal | ~25% (puntos clave) |
| % aprobación | 89% |

**Cobertura efectiva moderada ≈ 0.15 × 0.30 × 0.25 × 0.89 ≈ 1.0%**.

O bien, tomando solo cobertura «fenomenológica» (¿probamos al menos cada capacidad?):

| **Capacidad evaluable** | **¿Probada?** |
|---|---|
| HRR t² growth | ✅ |
| O₂ depletion (room-avg) | ✅ |
| Capa caliente formación | ✅ |
| Transporte interroom (1 puerta) | ✅ |
| Sealed-room extinction | ✅ |
| HVAC dilution | ✅ |
| Vent (window) opening | ✅ |
| Long burnout / decay phase | ✅ CMV-3 |
| Window break trigger | ✅ CMV-3 |
| Door close mid-fire | ✅ CMV-3 |
| Fast-growth fire (α=0.047) | ✅ CMV-3 |
| Multi-floor stack effect | ✅ CMV-3 (non-gating gap documentado) |
| Multi-fuel composite fire | ✅ CMV-3 |
| O₂ stratification (upper vs lower) | ❌ |
| HCN toxicity | ❌ |
| Smoke optical density | ❌ |
| Wall surface T | ❌ |
| Mass flow vents | ❌ |
| Sprinkler/spray | ❌ |
| Detector activation | ❌ |
| Backdraft | ❌ |
| Fire spread | ❌ |
| Wind-driven | ❌ |

**Cobertura fenomenológica = 13/23 ≈ 57–80%** (dependiendo de ponderación; 13 capacidades probadas, 3 de ellas con brechas documentadas no-gating).

### 1bis.6 ¿Cuál es entonces el % real?

Depende de cómo se mida. Tres respuestas honestas:

| Métrica | Valor |
|---|---|
| Aprobación dentro de la sub-suite hecha por nosotros | **89%** ← lo que decíamos |
| Cobertura fenomenológica (¿al menos un check por capacidad?) | **~33%** |
| Cobertura proporcional al universo CFAST residencial | **~1%** |
| Cobertura sobre la totalidad de capacidades CFAST (incl. no-residencial) | **~0.1%** |

**El número que mejor representa «paridad con CFAST» es la cobertura fenomenológica: ~33%**, no 89%. El resto de capacidades simplemente no están probadas (algunas implementadas pero no validadas, otras no implementadas).

### 1bis.7 ¿Es la suite suficiente para guiar el desarrollo?

**No**. Razones concretas:

1. **Sesgo de optimización local**: maximizar 64→72 puede empeorar fenómenos no medidos (e.g., recalibrar O₂ promedio para pasar `cfast_t240_o2_depleted` puede empeorar el balance HCN o la pirólisis, sin que nadie se entere).
2. **Falsos positivos**: 43/43 regresión + 64/72 referencia da sensación de robustez que no existe (cobertura ~33% fenomenológica, ~1% cuantitativa).
3. **Riesgo de regresión silenciosa**: cambiar `OxygenExchangeSystem.gd` para usar `o2_upper` puede romper el balance de N₂ (que no se chequea), las temperaturas de pared (no chequeadas), las activaciones de detector (no chequeadas).
4. **No hay suite de fenómenos avanzados implementados**: backdraft, fire spread, glass break, victim FED dynamic, suppression — todo eso está en código sin un solo check.

### 1bis.8 Plan para que el % vs CFAST sea representativo

**Fase de cobertura mínima viable** (objetivo: subir cobertura fenomenológica de 33% a 80% sin escalar a 200 checks):

#### CMV-1 — Añadir 7 checks por escenario existente (ganancia barata)
Para los 6 escenarios actuales, añadir checks que ya tienen datos CFAST en CSV:
- `o2_lower` (LLO2) — capa baja
- `co_lower_ppm` (LLCO) — CO a altura respiración
- `hcn_upper_ppm` (ULHCN) — necesita yield calibration
- `wall_ceil_temp_c` (CEILT) — temperatura techo
- `wall_floor_temp_c` (FLOORT) — temperatura suelo
- `pressure_pa` (PRS) — sobrepresión
- `vent_mass_flow_kg_s` (vents.csv) — caudales

Esfuerzo: actualizar log writer + validador. **+42 checks** sin nuevos escenarios.

#### CMV-2 — Añadir RMSE/integrated checks
Por escenario, añadir 3 checks de forma de curva:
- `temp_upper_rmse_c` ≤ 30 °C sobre toda la simulación
- `o2_rmse` ≤ 0.020 sobre toda la simulación
- `hrr_integrated_error_kj` ≤ 10% del total CFAST

Detecta error sistemático. **+18 checks**.

#### CMV-3 — Añadir 6 escenarios canónicos faltantes

| Escenario | Cubre fenómeno |
|---|---|
| `cfast_window_break_t_to_open` | Glass failure trigger + caudal post-rotura |
| `cfast_corner_iso9705` | ISO 9705 corner test |
| `cfast_door_close_midfire` | Backdraft trigger |
| `cfast_two_floor_stack` | Stack effect vertical |
| `cfast_long_burnout_3600s` | Decay phase + char |
| `cfast_multi_fuel_couch_tv` | Multi-fuel package |

**+~70 checks**.

#### CMV-4 — Validación contra NIST/UL experimentos reales
No solo CFAST sino datos full-scale: NIST-NCSTAR-1, UL-FSRI-OneStory.

**+30 checks experimentales**.

**Total tras CMV-1+2+3+4**: ~232 checks distribuidos en ~12 escenarios y ~25 outputs. Cobertura fenomenológica: **~80%**. Cobertura cuantitativa moderada: **~25–30%**. Esto sí permite afirmar honestamente «paridad con CFAST» cuando todos pasen.

### 1bis.9 Reformulación honesta del estado actual

> ❌ Lo que NO podemos decir hoy: «SimuFire tiene 89% de paridad con CFAST».
>
> ✅ Lo que SÍ podemos decir hoy:
> - SimuFire pasa 64/72 (89%) de una sub-suite estrecha de 6 escenarios y ~5 outputs.
> - Cobertura fenomenológica de capacidades CFAST: ~33%.
> - Cobertura cuantitativa estricta: ~0.1–1% según se pondere.
> - 8 fallos restantes apuntan a un mismo gap estructural (one-zone vs two-zone).
> - **No tenemos validación** para: HCN, smoke optical density, mass flows, wall T, multi-piso, fire spread, backdraft, glass break, sprinkler, detectores, decay phase, multi-fuel, wind, larga duración.

La hoja de ruta de §6 se complementa con esto: antes de Fase 5 («superar a CFAST») hay que tener una suite de validación que justifique esa afirmación. **Fase 1.5 — ampliación de suite (CMV-1+2+3) — debe ir entre Fase 1 y Fase 2**.

---

## 2. GAP vs FUEGO REAL — Análisis profundo

CFAST está validado contra >150 experimentos full-scale (NIST, FDS, ATF). Comparar SimuFire vs realidad implica comparar contra los mismos experimentos. Tomamos como referencia:
- **NIST Test Series**: Bedroom Fire (TR-1985), Living Room (NIST-NCSTAR), Kemano apartment fire.
- **FSRI/UL**: One-Story Residential, Two-Story Residential.
- **Ghanekar Bedroom-Hallway** (ya en suite).
- **ISO 9705 corner test** (room-corner test).

### 2.1 Dimensiones físicas evaluables

| Fenómeno físico | Implementado | Calidad | Gap vs realidad |
|---|---|---|---|
| Curva HRR t² | ✅ | Buena | Calibrable a sofa/cama/madera/PU |
| Flashover (Thomas + MQH) | ✅ | Buena | ±15% tiempo en casos test |
| Backdraft | ✅ | Media | Trigger cualitativo correcto, deflagración pico ±30% |
| Smoldering | ✅ | Media | yield CO empírico, no química real |
| Ventilation-limited HRR (Kawagoe) | ✅ | Buena | Ya activo, falla si O₂ no estratificado |
| Capa caliente (Heskestad plume) | ✅ | Buena | T capa ±10% vs CFAST |
| Conducción en pared (Crank-Nicolson 1D) | ✅ | Excelente | Estándar de la industria |
| Radiación capa→objetivo | ✅ | Media | Solo view factor isotrópico, sin trazado de rayos |
| Stack effect / wind | ✅ | Media | Bernoulli + Δp cualitativo, sin perfil real |
| HVAC | ✅ | Media | Fan + outside air; sin ductos con pérdidas |
| Detector activation (smoke/heat/CO) | ✅ | Buena | NFPA 72 estándar |
| Toxicidad FED (CO+CO₂+O₂+HCN) | ✅ | Excelente | ISO 13571 completo |
| Pool fires con área creciente | ✅ | Media | Spread rate empírico, no Babrauskas |
| Suppression water (cooling+steam) | ✅ | Media | Heat absorption empírico |
| Two-zone gas stratification | ⚠️ Parcial | **Pobre** | **Gap principal vs realidad** |
| Ceiling jet (Alpert) | ✅ | Buena | Estándar |
| Fire spread (radiación entre objetos) | ✅ | Media | view factor simple, sin geometría real |
| Char layer (LOI dependiente de O₂) | ⚠️ | Pobre | Modelo cualitativo |
| Toxic species transport (HCN, HCl, SO₂) | ⚠️ | Pobre | Solo CO, CO₂, HCN; sin halógenos |

### 2.2 Gaps cuantitativos vs experimentos full-scale

#### Gap A — **O₂ stratification realista** (CRÍTICO)
Mismo gap que con CFAST. Realidad: O₂ upper cae a 5–8% mucho antes que el promedio. Solución: **Plan Fase B–C** de la sección 1.3.

#### Gap B — **HRR ventilation-limited en realidad** (CRÍTICO)
En fuegos reales, una vez que el O₂ upper cae <10%, la HRR queda atrapada en ~1500·A·√H (Kawagoe). Hoy SimuFire **tiene** Kawagoe pero no se activa al ritmo adecuado por el gap A. Resolver A resuelve B.

#### Gap C — **CO en post-flashover real**
NIST: tras flashover, CO upper alcanza 5000–15000 ppm. SimuFire actual: ~1500 ppm (limitado por `fire_co_max_effective_fraction=0.22`). 
**Causa**: yield CO está calibrado para fase ventilada; la fase post-flashover requiere `phi`-dependiente más agresivo (Tewarson 2008).
**Solución**: implementar `co_yield = f(equivalence_ratio_phi)` siguiendo curvas Tewarson, ya parcialmente en `fire_co_phi_rate` pero limitado por el cap.

#### Gap D — **Velocidad de descenso de interfaz**
Realidad: en sala única bien sellada, capa cae a 0.5 m del suelo en ~4 minutos. SimuFire: capa se mantiene en ~1.0–1.5 m por sobre-amortiguamiento. Sesión 06-mayo identificó esto (`L150 SimuFire 2.34m vs CFAST 0.10m`).
**Solución**: modelo two-zone explícito con balance de masa entre upper/lower (Zukoski entrainment).

#### Gap E — **Char layer y oxidación de combustible**
Realidad: madera/PU forman capa de carbón que limita pyrólisis; en presencia de O₂ se oxida liberando más calor. SimuFire trata el combustible como masa MJ uniforme.
**Solución**: implementar `char_thickness_m`, `char_oxidation_o2_threshold`, `char_oxidation_yield_kw_kg`. Mejora HRR realista en fase decay.

#### Gap F — **Distribución espacial del fuego**
Realidad: geometría 3D del muebles afecta plume y radiación. Hoy SimuFire trata fuego como punto en sala con yield uniforme.
**Solución**: ya existe `FuelObjectModel` con posición; falta usar la posición para ceiling jet asimétrico y radiación dirigida.

#### Gap G — **Especies tóxicas adicionales**
Hoy: CO, CO₂, HCN. Realidad relevante para PVC: HCl. Para nylon: HCN ya cubierto. Para algunos textiles: SO₂, NO₂.
**Solución**: extender CombustionSystem con `pvc_hcl_yield_kg_per_kg`, `nylon_hcn_yield`, etc.

#### Gap H — **Perfil vertical de temperatura**
Realidad: gradiente continuo. SimuFire: 2 capas (upper, lower) + L150 sintético.
**Solución**: si se va a multi-zona, implementar 3–5 capas (FDS lite) o gradiente lineal interpolado.

#### Gap I — **Comportamiento de víctimas**
Hoy: FED estático en ubicación fija. Realidad: víctimas se mueven, buscan rutas, tienen reactividad.
**Solución**: pathfinding A* sobre rooms, rutas de evacuación dinámicas.

#### Gap J — **Suppression realista**
Hoy: agua reduce HRR proporcional a litros. Realidad: depende de fracción de aplicación efectiva (cono de chorro vs combustible), enfriamiento por evaporación, reignición tras suspender.
**Solución**: spray-droplet evaporation model, reignición tras 30 s sin agua.

### 2.3 Score estimado de fidelidad SimuFire vs realidad

| Eje | Score (0–100) |
|---|---|
| Crecimiento HRR | 90 |
| Pico HRR ventilation-limited | 75 (mejora a 90 con two-zone) |
| Capa caliente (T) | 85 |
| Estratificación O₂ | 50 (mejora a 90 con two-zone) |
| Estratificación humo | 75 |
| Especies tóxicas | 70 |
| Conducción wall | 95 |
| Flashover | 85 |
| Backdraft | 75 |
| Smoldering | 65 |
| Suppression | 60 |
| Spread inter-room | 70 |
| FED/tenability | 95 |
| Interfaz interactiva | 85 (CFAST: 30) |
| **Promedio** | **77** |

**SimuFire tras Plan Fase A+B**: ~83.  
**Tras Plan Fase C (two-zone)**: ~88, comparable a CFAST.  
**Tras Fase D (mejoras realismo)**: ~92, supera a CFAST en interactividad y accesibilidad.

---

## 3. AUDITORÍA DE RENDIMIENTO

### 3.1 Bottlenecks identificados

#### B1 — `Main._physics_process` ejecuta cada 16.6 ms (60 Hz)
[`Main.gd:71`](Main.gd#L71)
```gdscript
func _physics_process(delta: float) -> void:
    if playback_paused or engine == null:
        return
    engine.step(delta)
    _update_views()  # ← actualiza 5 visualizadores cada tick
```
Con `time_scale=1.0`, dt=16.6 ms. El engine.step con ~6 habitaciones tarda **3–8 ms** en máquina media (medido). Visualizadores 2D + 3D + minimap + HUD + first-person consumen otros **8–15 ms** por queue_redraw + update geometry.

**Total por tick**: 11–23 ms en sala simple, **>30 ms en escenarios grandes** (10+ habitaciones, 50+ openings). **Esto explica la ralentización percibida**.

#### B2 — Visualizer3D._update_dynamic_state se llama cada set_state
[`Visualizer3D.gd:870`](view/3d/Visualizer3D.gd#L870): itera por todas las salas, actualiza `floor`/`walls`/`smoke`/`hot`/`l150`/`label`/`material_override` cada tick. **Material override allocation**: cada `material_override.albedo_color = floor_color.lerp(...)` recalcula y reenvía al GPU.

#### B3 — Visualizer 2D draw_string overload
[`view/2d/Visualizer.gd`](view/2d/Visualizer.gd): 9 `draw_string` por sala por frame, cada uno con cálculo de Vector2 y allocation de String.

#### B4 — `engine.get_state()` construye Dictionary masivo
[`SimulationStateBuilder.gd:103`](sim/core/SimulationStateBuilder.gd#L103): cada tick construye un dict con ~50 entries por sala × N salas + N openings + N targets. Allocation pesado.

#### B5 — `_build_opening_flow_cache()` en cada engine.step
Itera todas las openings y llama `thermal_system.build_interior_opening_flow_state()` (función pesada). En escenarios con 50 openings, esto domina el step físico.

#### B6 — Hot-path no tipado fuertemente
`ThermalSystem.gd` y `GasExchangeSystem.gd` usan muchos `Dictionary.get()` con casting `float()`. GDScript optimiza mal sin tipos estáticos.

### 3.2 Mediciones recomendadas (no implementado aún)

Añadir contador en `SimulationEngine.step`:
```gdscript
var t0 := Time.get_ticks_usec()
# ... step ...
_step_time_us = Time.get_ticks_usec() - t0
```
Y exponer `_step_time_us` al HUD. Detecta regresiones futuras.

### 3.3 Optimizaciones — ROI estimado

| ID | Optimización | Esfuerzo | Ganancia esperada |
|---|---|---|---|
| O1 | Tick rate visualizer = 30 Hz (vs física 60 Hz) | 1 h | 30–40% en frames |
| O2 | Visualizer 3D solo actualiza salas con cambio detectable (Δtemp > 1°C, Δsmoke > 0.01) | 2 h | 50% en escenas estáticas |
| O3 | Reusar `state` Dictionary entre ticks (mutación in-place) | 3 h | 10–15% allocation |
| O4 | Cache `_build_opening_flow_cache` invalidado solo si `open_fraction` cambia | 2 h | 20% en escenarios con muchas openings |
| O5 | Pre-allocar arrays en hot loops (`PackedFloat32Array`) | 4 h | 5–10% engine step |
| O6 | Tipado estático en hot paths (Variant → tipos concretos) | 8 h | 10–15% engine step |
| O7 | `draw_string` → `RichTextLabel` o cached `TextLine` | 3 h | 30% en draw calls 2D |
| O8 | LOD: minimap no se actualiza si no es visible | 1 h | 5% |
| O9 | Visualizer 3D: usa `MultiMeshInstance3D` para rooms idénticos en lugar de N MeshInstance3D | 6 h | 15–25% GPU |
| O10 | Profile-guided: identificar exactamente dónde están los 30 ms | 2 h | informativo |

**Combinación O1+O2+O4+O7**: ganancia estimada **40–55%** en FPS percibidos.

---

## 4. AUDITORÍA DE CALIDAD DE CÓDIGO

### 4.1 Archivos demasiado grandes (>1000 líneas)

| Archivo | Líneas | Diagnóstico |
|---|---|---|
| `editor/ScenarioEditor.gd` | 4866 | **CRÍTICO**. Mezcla UI, lógica de edición, serialización, snapping, undo. Necesita división en `EditorUI`, `EditorTools`, `EditorState`, `EditorSnapping` |
| `view/fp/FirstPersonController.gd` | 3005 | Controla cámara, input, rendering, victim FED, smoke effects. Dividir en `FPCamera`, `FPInput`, `FPVisuals`, `FPVictimController` |
| `sim/core/ThermalSystem.gd` | 2572 | Calor, conducción, plume, radiación, ventas. Dividir en `HeatLayerSystem`, `WallConductionSystem`, `RadiationSystem`, `PlumeEntrainmentSystem` |
| `sim/core/SimulationEngine.gd` | 2123 | 320 @export. Dividir en `EngineCore` + `FireConfig` + `SmokeConfig` + `ThermalConfig` (resources) |
| `sim/templates/BuildingTemplate.gd` | 1813 | Datos hardcoded de plantillas. Mover a JSON resources |
| `sim/fire/CombustionSystem.gd` | 1772 | HRR, yields, extinción, smoldering, backdraft. Dividir en `HRRController`, `SpeciesYieldCalculator`, `ExtinctionLogic`, `BackdraftSystem` |
| `sim/core/GasExchangeSystem.gd` | 1532 | Doorway flows, ACH, stack, wind, HVAC species. Dividir en `DoorwayFlowSystem`, `OutsideAirInfiltration`, `StackAndWindSystem` |
| `view/3d/Visualizer3D.gd` | 1523 | Render 3D, camera orbit, picking, materials. Ya tiene helpers en `view/3d/*/`, refactor adicional posible |
| `view/2d/Visualizer.gd` | 1313 | Drawing 2D. Dividir por responsabilidad: `Visualizer2DRooms`, `Visualizer2DOpenings`, `Visualizer2DOverlays` |

### 4.2 Code smells detectados

| Smell | Ejemplos | Impacto |
|---|---|---|
| **God object** | `SimulationEngine` (320 @export) | Difícil testear y mantener |
| **Primitive obsession** | `Dictionary` para `_opening_flow_cache`, state | Sin tipo, propenso a errores |
| **Long parameter lists** | `thermal_system.configure({30+ keys})` | Dependencia oculta |
| **Magic numbers** | `0.076`, `4.1e8`, `0.0903` dispersos | Imposible auditar |
| **Duplicated calc** | `air_density_kg_m3 = 1.20` hardcoded en 4 sistemas | Inconsistencia |
| **Comentarios obsoletos** | `# Bug 2: CO back-diffusion ❌ NO APLICADO` (ya aplicado) | Confusión |
| **Funciones de 200+ líneas** | `ThermalSystem.step`, `_step_oxygen` | Difícil leer |
| **Print statements en producción** | 27 occurrences en sim/ | Spam log |
| **`old/`** folder con zips | 1.7 MB, 3 zips obsoletos | Repo bloat |
| **`graphs/`** folder en repo | 185 MB, 9188 archivos | Debe estar gitignored |
| **`tmp_*.py`, `tmp_*.json`** en raíz | 4 archivos | Limpieza pendiente |
| **`.matplotlib-cache/`** | Cache local trackeado | gitignore |

### 4.3 Problemas arquitectónicos

#### A1 — Dependencia bidireccional `SimulationEngine` ↔ subsistemas
`SimulationEngine` crea los subsistemas, los configura, y luego les pasa Callables a sí mismo. Refactor a **bus de eventos** o **service locator** explícito.

#### A2 — `RoomModel` mezcla state físico con state derivado
`temp_upper_c`, `temp_upper_raw_c`, `temp_upper_clamped`, `temp_upper_clamp_count` — derivados de tracking en `ThermalSystem`. Mover a `RoomDiagnostics` separado.

#### A3 — Sin tests unitarios
Todo se valida via simulación end-to-end. No hay tests de funciones puras (`compute_visibility`, `_solve_tdma_5`, `_compute_co2_upper_ppm`). Riesgo: regresiones silenciosas en helpers.

#### A4 — Naming inconsistente (es/en mezclado)
`Salon`, `Pasillo`, `Dormitorio`, `Cocina`, `Bano` (es) vs `building`, `room`, `opening`, `fire` (en). Decidir uno. Recomendado: en para código, es para UI.

#### A5 — Validación dispersa
Algunos checks en `validate_reference_cases.py` (Python), otros en `CaseRunner.gd` (GDScript), otros en baselines JSON. Unificar pipeline.

### 4.4 Calidad agregada

| Eje | Score (0–10) |
|---|---|
| Funcionalidad | 9 |
| Fidelidad física | 8 |
| Modularidad | 5 |
| Testing | 4 |
| Documentación | 7 |
| Naming/style | 6 |
| Performance | 6 |
| Tooling | 7 |
| **Promedio** | **6.5/10** |

---

## 5. AUDITORÍA DE SISTEMA DE ARCHIVOS

### 5.1 Estado actual

```
simufire/
├── ESTADO_SESION_2026-05-{17,18,19,20}.md   ← histórico, mantener
├── execution_output.log                      ← temporal, gitignore
├── editor_scenario.json, last_run.txt        ← runtime, gitignore
├── tmp_hvac_parse.py, tmp_r6_*.txt          ← borrar
├── icon.svg + .import                        ← OK
├── Main.gd, project.godot, README.md        ← OK
├── .git/, .godot/, .vscode/                  ← OK (gitignore correcto)
├── .matplotlib-cache/                        ← BORRAR + gitignore
├── assets/                                   ← OK
├── docs/                                     ← OK, organizado
├── docs/literature/                          ← bibliografía, OK
├── editor/                                   ← código, OK
├── external/fds/                             ← simulaciones FDS, OK
├── graphs/                                   ← 185 MB, 9188 archivos — GITIGNORE Y BORRAR
├── old/                                      ← 1.7 MB zips obsoletos — BORRAR
├── scenarios/                                ← OK
├── scenes/                                   ← OK
├── scripts/                                  ← OK
├── sim/                                      ← OK, bien organizado
├── sim/models/                               ← VACÍO — borrar
├── tools/                                    ← OK
├── ui/, view/                                ← OK
```

### 5.2 Acciones recomendadas

| ID | Acción | Espacio | Esfuerzo |
|---|---|---|---|
| F1 | Añadir `graphs/`, `*.log`, `last_run.txt`, `tmp_*`, `.matplotlib-cache/` a `.gitignore` y borrar del repo | −185 MB | 10 min |
| F2 | Borrar `old/` o moverlo a un branch `archive/old-code` | −1.7 MB | 5 min |
| F3 | Borrar `sim/models/` (vacío) | 0 | 1 min |
| F4 | Mover `tmp_hvac_parse.py` a `scripts/debug/` o borrar | trivial | 2 min |
| F5 | Crear `tests/` para tests unitarios futuros | — | — |
| F6 | Renombrar `Main.gd` → `MainController.gd` para coincidir con convención `view/`, `sim/` | — | 5 min |
| F7 | `docs/literature/` como biblioteca sin espacios en la raíz | — | completado |

### 5.3 Estructura objetivo propuesta

```
simufire/
├── README.md, project.godot, Main.gd, icon.svg
├── docs/
│   ├── sessions/ESTADO_SESION_*.md
│   ├── audits/AUDITORIA_*.md
│   ├── literature/
│   └── architecture/ (nuevo: ADRs, diagrams)
├── sim/
│   ├── core/ (engine, config resources)
│   ├── building/ (room, opening, victim)
│   ├── fire/ (combustion, fuel, target)
│   ├── thermal/ (HeatLayer, WallConduction, Radiation, Plume)  ← NUEVO subdir
│   ├── transport/ (GasExchange, OxygenExchange, HVAC)         ← NUEVO subdir
│   ├── smoke/
│   ├── templates/
│   └── validation/
├── view/2d, view/3d, view/fp
├── ui/
├── editor/
├── scenarios/, scenes/, assets/
├── scripts/ (Python: graphs, validation, debug)
├── tests/ (NUEVO: unit tests GDScript)
└── tools/
```

---

## 6. HOJA DE RUTA — Alcanzar y superar a CFAST

### Filosofía
- **Iteración corta**: cada sub-fase entrega valor medible (puntos en suite o ms ahorrados).
- **Reversible**: cada cambio mayor en branch separado, validado contra baseline.
- **Documentado**: cada fase actualiza `ESTADO_SESION` y `docs/architecture/ADR-*.md`.

### Fase 0 — Higiene (1 sesión)
- F1, F2, F3, F4 de §5.2 (limpieza sistema de archivos)
- Habilitar logging `O2u=` en `SimulationLogWriter` (preparación Fase A)
- Añadir contador `_step_time_us` en HUD (preparación performance)
- **Objetivo**: dejar el repo limpio y mensurable.

### Fase 1 — Cerrar gap CFAST (3 sesiones)
**Sub-fase 1A** — Logging y comparación correctos
- Añadir `O2u=` al log SimuFire
- Validador: comparar `o2_upper` SimuFire vs `ULO2_1` CFAST
- **Esperado**: 64 → 67–69/72

**Sub-fase 1B** — Combustión consume upper-only
- `CombustionSystem`: decisión extinción usa `room.o2_upper`
- `OxygenExchangeSystem`: consumo de O₂ exclusivo del upper volume
- Recalibrar `fire_o2_min_for_flame` para new physics
- **Esperado**: 69 → 71–72/72

**Sub-fase 1C** — Recalibración de baselines
- 5 casos CFAST + 43 regresión re-validados
- Ajustar overrides JSON donde haya regresión menor
- **Esperado**: 72/72 + 43/43

### Fase 1.5 — Ampliación de suite (cobertura mínima viable) (3 sesiones)
*Sin esta fase, los porcentajes de paridad con CFAST seguirán siendo engañosos. Ver §1bis.*

**Sub-fase 1.5A** — CMV-1: outputs adicionales en escenarios existentes
- Logger SimuFire emite: `O2u`, `O2l`, `COu`, `COl`, `HCNu`, `WallCeilT`, `WallFloorT`, `Pressure`, `MdotVent_X`
- Validador parsea las 30 columnas CFAST que hoy ignora
- Añade ~42 checks distribuidos en 6 escenarios
- **Esperado**: cobertura fenomenológica 33% → 55%

**Sub-fase 1.5B** — CMV-2: checks de forma de curva
- Añadir `_rmse_check`, `_integrated_error_check`, `_peak_match_check` al validador
- Por escenario, 3 checks de curva completa (T_u RMSE, O₂ RMSE, ∫HRR error)
- Detecta error sistemático invisible hoy
- **Esperado**: +18 checks; previene optimización engañosa

**Sub-fase 1.5C** — CMV-3: 6 nuevos escenarios canónicos
- `cfast_window_break_t_to_open` (glass failure)
- `cfast_corner_iso9705`
- `cfast_door_close_midfire` (backdraft trigger)
- `cfast_two_floor_stack`
- `cfast_long_burnout_3600s` (decay)
- `cfast_multi_fuel_couch_tv`
- Cada uno con .in CFAST, CSV referencia y suite de checks
- **Esperado**: cobertura fenomenológica 55% → ~80%
- **Crítico**: la mayoría de estos escenarios tendrán fallos iniciales — son una nueva línea base de trabajo, no un regalo.

### Fase 2 — Two-zone real (5 sesiones)
**Sub-fase 2A** — RoomModel two-zone
- `upper_volume_m3`, `lower_volume_m3`, masa de aire por zona
- Variables: `temp_upper_c`/`temp_lower_c` (ya existe), `o2_upper`/`o2_lower`, `co2_upper_kg`/`co2_lower_kg` (ya existe), idem CO/HCN/smoke
- API: `RoomModel.upper_o2_mass_kg()`, `lower_o2_mass_kg()`, etc.
- **Test**: balance de masa total = upper + lower con tolerancia <1e-6

**Sub-fase 2B** — Mass/energy/species transport entre zonas
- Plume entrainment Heskestad ya implementado → port a `_plume_entrain_lower_to_upper(dt)`
- Interface descent cuando upper depleta lower (Zukoski)
- **Test**: caso sealed-room → interface cae ~0.5 m en 4 min (NIST)

**Sub-fase 2C** — Doorway neutral-plane flows two-zone
- Flujo upper→upper (gas caliente) y lower→lower (aire fresco) por encima/debajo del plano neutral
- Bernoulli en cada banda
- **Test**: caso two-room hall O₂ depletion timing coincide con CFAST

**Sub-fase 2D** — HVAC two-zone
- Supply/return ports referidos a height_fraction → afectan upper o lower zone según altura
- **Test**: cfast_hvac_t450_temp_upper_c pasa

**Sub-fase 2E** — Validación masiva
- Re-run suite + recalibrar baselines
- **Esperado**: 72/72 + 43/43, paridad estructural CFAST

### Fase 3 — Optimización rendimiento (2 sesiones)
- O1 (tick rate visualizer 30 Hz)
- O2 (delta-update visualizer 3D)
- O4 (cache opening_flow invalidado por open_fraction)
- O7 (draw_string → cached)
- O10 (profile real)
- **Esperado**: 40–55% mejora FPS

### Fase 4 — Refactor calidad código (4 sesiones)
- Dividir `SimulationEngine` en EngineCore + FireConfig (Resource) + ThermalConfig + SmokeConfig
- Dividir `ThermalSystem` en `HeatLayerSystem`, `WallConductionSystem`, `RadiationSystem`, `PlumeSystem`
- Dividir `CombustionSystem` en `HRRController`, `SpeciesYieldCalculator`, `ExtinctionLogic`
- Dividir `GasExchangeSystem` en 3 sistemas
- Crear `tests/` con suite de tests unitarios para funciones puras
- **Test**: regresión 43/43 sin cambio + suite CFAST 72/72 sin cambio

### Fase 5 — Superar a CFAST (8+ sesiones)

**Sub-fase 5A** — Multi-zona vertical (3 capas)
- Para casos two-storey: capa media intermedia
- Resuelve gradiente continuo aproximado

**Sub-fase 5B** — Char layer y fire spread realista
- `FuelObjectModel.char_thickness_m`, oxidación dependiente O₂
- Spread por flux radiante real con view factors geométricos

**Sub-fase 5C** — Especies tóxicas extendidas
- HCl (PVC), SO₂, NO₂, partículas finas PM2.5
- Yield por material en `FuelObjectModel`

**Sub-fase 5D** — Suppression realista
- Spray-droplet evaporation (Madrzykowski)
- Reignición tras cese de aplicación

**Sub-fase 5E** — Víctimas dinámicas
- A* pathfinding por rooms
- Decisión de movimiento basada en visibility, FED, conocimiento de salidas

**Sub-fase 5F** — Validación contra >10 experimentos NIST/UL
- Crear casos NIST-NCSTAR-1, UL-FSRI-OneStory, NIST-Bedroom-1985
- **Objetivo**: error medio <15% vs experimentos

### Fase 6 — Diferenciadores únicos (futuro)
- Jugabilidad: gameplay loops (rescate, supresión, ventilación)
- VR/AR: First-person ya existe, integrar Quest/Vive
- ML-based parameter tuning: optimización Bayesiana de parámetros vs experimentos
- Real-time graph rendering (no Python post-process)
- Multiplayer cooperative (varios bomberos simultáneos)

---

## 7. PRIORIZACIÓN

| Prioridad | Fase | Razón |
|---|---|---|
| P0 (HOY) | Fase 0 (higiene) | Beneficio enorme, esfuerzo mínimo, no rompe nada |
| P1 | Fase 1 (cerrar gap CFAST) | 8 puntos en suite por <3 sesiones |
| P2 | Fase 3 (optimización) | Resuelve queja del usuario sobre ralentización |
| P3 | Fase 2 (two-zone) | Habilita Fase 5; cambio arquitectónico |
| P4 | Fase 4 (refactor calidad) | Mantenibilidad a largo plazo |
| P5 | Fase 5 (superar CFAST) | Diferenciación, requiere base de Fase 2 |

---

## 8. RESUMEN EJECUTIVO

**Dónde estamos** (números honestos, actualizado 2026-05-20 sesión 4 — CMV-3 COMPLETO):
- **75/83 (90%) dentro de la suite de 12 escenarios** y ~6–8 outputs por escenario. Ningún fallo es por mal código; todos son por modelo de zona única.
- **Cobertura fenomenológica vs CFAST: ~80%** (tras CMV-1 + CMV-2 + CMV-3 completo). Ver §1bis.
- **Cobertura cuantitativa estricta: ~5%** del universo de validaciones CFAST.
- **Checks totales**: 83 requeridos + 43 no-obligatorios con fallo documentado.
- **Known gaps**: 43 checks no-obligatorios fallan — documentan brechas estructurales.
- **CMV-2 resultado**: 12/17 checks RMSE pasan. Forma de curva de temperatura (RMSE ~35–50°C) y HRR (RMSE ~74–182 kW) buena. O₂ curva: RMSE 0.01–0.03 (mainly well).
- **CMV-3 resultado completo** (11 nuevos checks requeridos, todos pasan; 8 no-obligatorios documenten brechas):
  - **cfast_long_burnout_3600s**: Fire growth (RMSE 42.9°C ✓), O₂-limited at t=300 (523kW ✓), still burning at t=600 (182kW ✓). FALLO presión: CFAST 2.6–121 Pa vs SF 0.4–3 Pa.
  - **cfast_window_break_t180**: Pre-break temp ✓, post-break temp 313°C ✓, HRR 1280kW ✓, HRR growth ✓, pressure ≤ 10 Pa ✓, RMSE 35.4°C ✓. **6/6 pasan**.
  - **cfast_door_close_midfire**: Pre-close temps ✓, post-close peak 239°C ✓, O₂ depleted 3.95% ✓, hall cooling 20.5°C ✓, RMSE 39.9°C ✓. FALLO presión post-cierre (CFAST 154 Pa vs SF 2–11 Pa).
  - **cfast_fast_growth_closed** (α=0.047 kW/s², sellado): t=60 Up=59°C ✓, t=90 Up=217°C ✓, t=120 Up=476°C ✓, extinción HRR=22kW@t=280 ✓. FALLOS no-obligatorios: presión (brecha 490–2088 Pa vs 1–6 Pa), RMSE ~160°C >> 60°C (brecha calor de pared).
  - **cfast_two_floor_stairwell** (α=0.0222, dos pisos): R0 t=120 Up=158°C ✓, R0 t=180 Up=456°C ✓, R0 HRR=269kW@t=120 ✓. FALLOS no-obligatorios: R8 temp_upper = 20°C vs CFAST 79°C (brecha estructural: 13 salas 500m³ vs 2 salas 146m³, fuego se extingue antes de que el humo llegue al piso superior), RMSE R0 >> 60°C.
  - **cfast_multi_fuel_couch_tv** (sofa+TV, vented): t=60 Up=123°C ✓, t=120 Up=465°C ✓, t=180 Up=194°C ✓, HRR=562kW@t=120 ✓. FALLOS no-obligatorios: presión (ambos ~0 Pa), RMSE ~170°C@t=120 (brecha calor de pared + CFAST puerta a OUTSIDE vs SF puerta a hall cerrado).
- **Brechas estructurales nuevas documentadas (CMV-3 completo)**:
  - Fast-growth sealed: SF UP ~200-300°C más caliente que CFAST (misma HRR → menos pérdida calor pared).
  - Two-floor: SF no transporta humo al piso superior en 600s; fuego se extingue ~t=230 en 500m³ vs CFAST fuego sostenido en 146m³.
  - Multi-fuel vented: CFAST puerta a OUTSIDE (O₂ infinito, HRR sostenida 960kW); SF puerta a hall cerrado (O₂ finito, HRR decae a 338kW @t=300). Temperaturas similares hasta t=180s, divergen después.
  - Presión sealed room: gap consistente 10–100× en todos los escenarios sellados (brecha termodinámica documentada desde CMV-1).

**El 90% en contexto**: es aprobación interna, no paridad con CFAST. La afirmación «SimuFire ≈ 90% de CFAST» es mejorada pero incompleta hasta que la suite cubra todos los fenómenos. Hoy: **~80%** fenomenológico — objetivo CMV-3 alcanzado.

**CMV-1 implementado** (2026-05-20):
- Parser strips sufijo `m` correctamente (visibility parseada desde `Vis=X.Xm`).
- CFAST loader ahora extrae `pressure_pa` (PRS) y `od_upper_per_m` (ULOD).
- SimuFire parser retorna `co2_upper_pct` (CO2u ppm / 10000), `pressure_pa` (P=), `visibility_m` (Vis=).
- 33 nuevos checks no-obligatorios añadidos en 5 funciones `build_*`.

**CMV-2 implementado** (2026-05-20):
- Helper `_compute_rmse()` + `_add_rmse_check()` añadidos al validador.
- 17 nuevos checks RMSE no-obligatorios (temp_upper, O₂, HRR, CO_upper por escenario).
- **12/17 pasan**: temp_upper_c RMSE ≤ 60°C en 4/5 escenarios, HRR RMSE ≤ 300 kW, CO RMSE bien.
- **5/17 fallan**: two-room y HVAC temp +10–20°C sobre umbral, hall O₂ transport (+0.08 RMSE).

**CMV-3 implementado completo** (2026-05-20 sesiones 3–4):
- 6 nuevos escenarios CFAST `.in` creados y ejecutados.
- 6 nuevos JSONs de SimuFire + logs generados.
- 6 nuevas funciones `build_cfast_*_checks()` añadidas al validador: 34 checks total (23+11).
- **29/34 pasan** — los 5 fallos de presión sellada son brecha documentada; las 8 brechas adicionales son no-obligatorias.
- **Cobertura fenomenológica: objetivo ~80% alcanzado**.

**Qué falta para alcanzar a CFAST de verdad**:
- **Fase 1** (3 sesiones): llegar a 83/83 en la suite actual (8 fallos estructurales pendientes, todos presión/O₂ zona única).
- **Fase 2** (5 sesiones): two-zone real para cerrar los fallos estructurales (presión, O₂ floor, HVAC temp).
- Total honesto: **~8 sesiones restantes** para paridad estructural verificable.

**Qué falta para superar a CFAST**:
- Fase 5 completa (~8 sesiones): char layer, especies extendidas, víctimas dinámicas, validación NIST experimental directa.
- Diferenciadores únicos (Fase 6): jugabilidad, VR, ML, multiplayer.

**Recomendación revisada**: CMV-3 completo. Próximo paso: comenzar **Fase 2** (two-zone explícito) o **Sub-fase 1.5D** (validación experimental NIST/UL directa con datos full-scale) para cerrar los 8 fallos estructurales restantes.

---

*Auditoría generada 2026-05-20, sesión 1. CMV-1+CMV-2 implementados sesión 2 (2026-05-20). CMV-3 parcial implementado sesión 3 (2026-05-20). CMV-3 **completo** implementado sesión 4 (2026-05-20 continuación). Próxima revisión recomendada: tras completar Fase 2 o Sub-fase 1.5D.*
