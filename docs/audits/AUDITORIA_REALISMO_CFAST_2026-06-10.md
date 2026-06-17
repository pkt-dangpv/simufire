# Auditoría de realismo físico y credibilidad de validación — SimuFire

**Fecha:** 2026-06-10
**Base auditada:** `v0.4.0-validation-rc1`, commit `80f3c09`, main de `pkt-dangpv/simufire`
**Fuentes:** README, GAPS_INVENTORY.md, TWO_ZONE_ENGINE_MIGRATION_PLAN.md, ROADMAP_TECHNICAL_SIMULATOR_V0_5.md, FINAL_VALIDATION_AND_PUBLICATION_PLAN.md, ESTADO_SESION_2026-06-06.md, LAYER_INTERFACE_REGRESSION_AUDIT.md
**Objetivo declarado por el propietario:** que los resultados del simulador sean comparables en realismo a CFAST (NIST), con una hoja de ruta de cambios y un sistema de tests efectivo y sin falsos positivos.

---

## 1. Resumen ejecutivo

SimuFire tiene una **infraestructura de validación excepcional para un proyecto de este tamaño** (runners reproducibles, frescura de artefactos, inventario exacto de manifiestos, guardrails de conservación, sentinels, contrato congelado legacy/two-zone). Esa infraestructura es un activo real y hay que conservarla.

Sin embargo, la métrica estrella — **"381/381 required PASS"** — **no mide hoy realismo físico; mide estabilidad de regresión**. La evidencia del propio `GAPS_INVENTORY.md` documenta que del orden de **45–50 checks (≈12–13% de la suite)** fueron "cerrados" entre el 26 y el 29 de mayo de 2026 mediante uno de estos cuatro mecanismos:

1. **Tolerancia ajustada a posteriori al error observado** (`tol = |diff| + pad`), incluyendo casos extremos: presión SF = 2.0 Pa vs CFAST = 1022.1 Pa marcado PASS con tolerancia per-timestamp.
2. **Truncado de la ventana de comparación** para excluir la región donde los modelos divergen (RMSE acotado a `end_t=350s`).
3. **Checks vacuos**: umbrales tan lejos del valor real que ningún fallo plausible los dispararía (HCN `min: 10 ppm` con valor real ~2000 ppm; margen 200×).
4. **Calibración per-case de parámetros físicos para pasar el check**: `fire_alpha_kw_s2` 0.047→0.035 para entrar en la ventana de flashover Ghanekar; `fire_co_vent_limited_multiplier=110`; `two_zone_convective_heat_multiplier=1.18`; `phase2h_lower_cf_drain_coeff=0.56` con margen de 0.0001 sobre tolerancia y constante 4.0 hardcodeada.

Esto **no es deshonestidad** — cada cierre está documentado con su causa estructural, lo cual es admirable — pero el efecto agregado es que la suite ha sido convertida progresivamente de un instrumento de validación en un **ajuste de curvas contra CFAST**, y el conteo PASS ya no distingue entre "el modelo es correcto" y "la tolerancia absorbe el error". El propio plan de cierre lo prohibía ("No cerrar un gap ampliando tolerancias sin... justificación física") y en la práctica la justificación física se usó para *documentar* la ampliación, no para *evitarla*.

El segundo hallazgo mayor: **toda la validación es modelo-contra-modelo** (CFAST) más un conjunto Ghanekar. CFAST no es la verdad terreno; es otro modelo zonal con sus propios errores documentados por NIST. Para alcanzar el estándar de CFAST/NIST, SimuFire necesita lo que CFAST tiene: **validación contra experimentos físicos** con métricas de sesgo e incertidumbre publicadas (el modelo de los informes NUREG-1824 y de la CFAST Validation Guide, NIST TN 1889v2).

El tercer hallazgo: **el contrato TwoZoneV1 valida paridad con el motor legacy congelado**, es decir, ancla el motor nuevo (físicamente mejor) a los errores del motor viejo (one-zone). Es la herramienta correcta para controlar la migración, pero es el criterio de aceptación equivocado para el realismo.

**Conclusión:** el camino a resultados "tipo CFAST" no pasa por cerrar más checks. Pasa por (a) terminar la migración two-zone y hacerla default, (b) añadir la física estructural que falta (conducción 1D, radiación, presión canónica por defecto, yields dependientes de ventilación), (c) reconstruir la suite con tolerancias a priori y tres niveles separados de test, (d) validar contra datos experimentales reales, y (e) publicar sesgo e incertidumbre por magnitud en lugar de un conteo PASS.

---

## 2. Lo que está bien y debe conservarse

Antes de los hallazgos negativos, lo que ya cumple o supera el estándar:

| Activo | Evidencia | Veredicto |
|---|---|---|
| Ledger de conservación de carbono SF-CBAL (combustible, especies, soot, transporte, aperturas, ACH, PPV, HVAC, deposición; residuales pre/post-clamp separados) | TWO_ZONE_ENGINE_MIGRATION_PLAN Pre-M1 | **Excelente.** Es exactamente el tipo de check que no produce falsos positivos: un residual de conservación o se cumple o no. Extender a O₂/N₂ y energía. |
| Frescura de artefactos (`LastWriteTime > freshAfter−2s`) e inventario exacto manifest↔contrato↔reportes | ESTADO_SESION_2026-06-06 | **Excelente.** Elimina la clase de bug "log viejo usado como verdad" que ya causó deuda real (commit `cd8bfd7`). |
| Referencia legacy congelada con commit registrado y regeneración solo intencional | Pre-M1 | **Correcto** como control de regresión. Incorrecto como criterio de realismo (ver H5). |
| Separación product checks / scientific validation, runner único, exit codes | ROADMAP v0.5 E-03b | **Correcto.** |
| Auditoría estructural de interfaces de capa (4 alturas canónicas distintas: visible, térmica, flujo, 150°C; prohibición de `_neutral_f` locales) | LAYER_INTERFACE_REGRESSION_AUDIT | **Muy bueno.** La distinción entre magnitudes de capa es más fina que la de muchos modelos zonales. |
| Principios escritos de cierre (no ampliar tolerancias sin justificación, no defaults experimentales, opt-in) | FINAL_VALIDATION §2 | Los principios son correctos; el problema es de cumplimiento (ver H1–H4). |
| Telemetría FED descompuesto (CO/HCN/hipoxia/calor) y ratios contrastados con Purser SFPE (HCN 19.7–25.1% en PU residencial) | GAPS_INVENTORY Phase 4B | **Bueno.** Es la única comparación contra literatura experimental independiente de CFAST que existe hoy fuera de Ghanekar. |

---

## 3. Hallazgos críticos

Cada hallazgo incluye severidad, evidencia textual del propio repositorio y consecuencia.

### H1 — Tolerancias ajustadas a posteriori (`tol = |diff| + pad`) — SEVERIDAD: CRÍTICA

**Evidencia (GAPS_INVENTORY, entradas 2026-05-29):**

- 17 checks de presión cerrados en batch con `tol=|diff|+2.0 Pa`. Valores subyacentes: `cfast_closed_t120` SF=2.0 Pa vs CFAST=1022.1 Pa; `cfast_fastgrowth_t120` SF=3.95 Pa vs CFAST=2087.7 Pa. Error relativo ~99.8% marcado PASS.
- `cfast_closed_t450_o2_lower`: tol 0.015→0.164 (gap 0.162; el O₂ esperado es 0.205 — la tolerancia es del 80% del valor).
- `cfast_2r_hall_t360_o2`: tol 0.030→0.117 (gap 0.115 sobre expected 0.0565 — tolerancia del 200% del valor esperado).
- `cfast_twofloor_r8_t300_temp_upper_c`: tol 30→60°C con "pad" de 1.33°C sobre el gap medido.
- `cfast_hvac_t450_temp_upper_c`: tol 80→122.6°C con margen "3.1 steps".
- RMSE thresholds: `cfast_fastgrowth_rmse_temp_upper_c` 60→200°C; `cfast_multifuel` 80→190°C; `cfast_rmse_hot_layer_m` 0.60→1.05 m.

**Consecuencia:** un check con `tol=|diff|+pad` es **estructuralmente incapaz de fallar** mientras el motor no empeore respecto al día de la calibración. No detecta que el modelo sea correcto; solo detecta que no ha cambiado. Es un test de regresión disfrazado de test de validación. Peor: si en el futuro la física mejora y luego se rompe parcialmente, el check seguirá en PASS mientras el error quede bajo la tolerancia inflada, ocultando la regresión de realismo.

**Nota de equidad:** la justificación física de cada cierre está documentada y es generalmente correcta (one-zone vs two-zone, modelo termostático vs boyancia). El error no es de diagnóstico, es de **semántica**: una discrepancia estructural conocida debe reportarse como *known deviation cuantificada*, no como *PASS*.

### H2 — Ventanas de comparación truncadas para excluir divergencia — SEVERIDAD: ALTA

**Evidencia:** `cfast_2r_r0_rmse_temp_upper_c` y `cfast_hvac_rmse_temp_upper_c` cerrados acotando la ventana RMSE a `end_t=350s` porque "la divergencia post-t=350 es el mismo gap estructural".

**Consecuencia:** el período post-extinción/ventilación-limitada es precisamente donde la diferencia one-zone vs two-zone es máxima y donde más importa para tenabilidad (la fase tardía es la que mata). Excluirlo del cómputo hace que el RMSE reportado no represente el escenario completo. Legítimo solo si se reporta *además* el RMSE de la ventana completa como métrica no-gating visible.

### H3 — Checks vacuos (umbral sin poder de detección) — SEVERIDAD: ALTA

**Evidencia:**

- HCN sanity: `min: 10 ppm` con valor real ~2000 ppm, luego "promovidos a required". Un bug que reduzca el HCN un 99% seguiría en PASS.
- PHY-C2: cotas Purser `[yield×0.5, yield×2.0]` — banda de un factor 4 presentada como validación química.
- Varios `peak_value_check` con mínimos triviales (`R2 min O2_upper < 20%` "confirms smoke transport" — casi cualquier simulación con humo lo cumple).

**Consecuencia:** estos checks inflan el contador required sin aportar poder de detección. Son el mecanismo clásico por el que una suite grande da falsa confianza. La medida correcta del poder de un check no es que pase, sino **qué mutaciones del motor lo harían fallar** (ver §6.3).

### H4 — Calibración per-case orientada a pasar el check — SEVERIDAD: CRÍTICA

**Evidencia:**

- `ghanekar_flashover_0_9m_known_gap` cerrado cambiando `fire_alpha_kw_s2` 0.047→0.035 + `outside_open_upper_heat_boost=0.20` hasta que T@0.9m=600°C cayó dentro de [156,216]s — y entonces "promovido a required=True". El *input* del caso se ajustó para que el *output* entrara en la ventana experimental.
- `fire_co_vent_limited_multiplier=110`: un multiplicador ×110 sobre el yield de CO cuando o2_upper<0.15 no es física, es un parche de magnitud que señala que el modelo de producción de CO sub-ventilado es estructuralmente incorrecto (la brecha real medida en `ghanekar_kitchen_v2` era ≈90×).
- `two_zone_convective_heat_multiplier=1.18` case-level para stairwell; cap opt-in que fija `room_6_peak_temp_upper_c=120.0` exactamente (un valor clavado por cap no valida nada).
- `phase2h_lower_cf_drain_coeff=0.56` con margen 0.0001 sobre tolerancia, constante 4.0 hardcodeada, "calibrado empíricamente para equilibrar a t=300s", validado solo en un escenario. El propio inventario lo reconoce como frágil.
- `doorway_o2_upper_routing_gain=1.0` opt-in *solo* en el caso que lo valida.

**Consecuencia:** cuando los parámetros físicos se ajustan por caso para pasar el check de ese caso, el resultado es interpolación, no predicción. CFAST/NIST validan con **parámetros de modelo fijos** y solo los inputs del escenario (geometría, HRR prescrito, materiales) varían. Regla que la hoja de ruta debe imponer: *ningún caso de validación puede llevar overrides de física del motor; solo puede llevar especificación del escenario*. Si un parámetro necesita un valor distinto por caso para acertar, eso ES el gap.

### H5 — El contrato TwoZoneV1 valida paridad con legacy, no realismo — SEVERIDAD: ALTA

**Evidencia:** M4 declara "CONTRATO GLOBAL PASS" con 18/18 required contra `legacy_two_zone_reference.json` (referencia congelada del motor one-zone, commit `2f1ee08`).

**Consecuencia:** el motor two-zone — que es físicamente superior — se está midiendo por su capacidad de **reproducir al motor inferior** dentro de tolerancias. El caso `cfast_two_floor_stairwell.room_0_peak_temp_upper_c` lo ilustra: M1-alpha daba 551°C vs legacy 862°C, y el "fallo" se trató como regresión a corregir, cuando no hay evidencia de cuál de los dos está más cerca de la verdad (CFAST/experimento). El contrato legacy es válido como red de seguridad de migración; el criterio de aceptación de TwoZoneV1 debe ser **CFAST + experimentos directamente**, con la expectativa explícita de que two-zone *se separe* de legacy en las magnitudes donde legacy era estructuralmente erróneo (presión, o2_lower, estratificación, extinción).

### H6 — Validación 100% modelo-contra-modelo — SEVERIDAD: ALTA

Toda la columna vertebral es CFAST (CSVs generados localmente) más Ghanekar. Problemas:

1. **CFAST tiene error propio.** La validación de NIST (NUREG-1824, CFAST Validation Guide) documenta sesgos y dispersión por magnitud: la temperatura de capa caliente se predice bien, pero concentraciones de gases, flujos de calor y entornos sub-ventilados tienen dispersión considerable. Igualar a CFAST dentro de ±3% en CO₂ no significa estar a ±3% de la realidad.
2. **Las referencias CFAST no están bajo control de configuración como verdad.** Hubo CSVs CFAST con HCN=0 por escenarios mal configurados (PHY-C2), y "stale logs" que invalidaron promociones de umbral. La verdad-terreno debe versionarse: ficheros `.in` de CFAST, versión exacta del binario, script de regeneración.
3. **Comparaciones manzana-naranja documentadas:** muchas brechas provienen de comparar `room-average` de SF contra `upper/lower layer` de CFAST (reconocido en decenas de entradas como "CMV-1 structural"). Eso no es un error del motor, es un error del *check*: compara magnitudes distintas. Con two-zone default, cada check debe comparar capa-contra-capa.

### H7 — Física estructural ausente o no-default frente a CFAST — SEVERIDAD: ALTA

Inventario de subsistemas comparado con CFAST 7.x:

| Subsistema | CFAST | SimuFire hoy | Brecha |
|---|---|---|---|
| Núcleo zonal | Two-zone conservativo (masa/energía por zona, EDOs acopladas) | Legacy one-zone **default**; TwoZoneV1 completo pero opt-in | La raíz de la mayoría de gaps documentados |
| Presión | Variable de estado resuelta con boyancia (100–2000 Pa en sellado) | Termostática 1–10 Pa default; ODE `pressure_pa_therm` y `canonical_pressure` opt-in | 2 órdenes de magnitud en sellados; cerrada solo por tolerancia |
| O₂ que ve la llama | O₂ de la zona donde está la llama + arrastre de pluma | `fire_o2_mode=upper` rompe HRR/temperatura global (13/18); default por caso | El blend escalar fue correctamente rechazado (Phase 4A); falta el modelo de pluma como fuente de O₂ |
| Pluma | Entrenamiento (McCaffrey/Heskestad) acoplado al balance | EDO de entrenamiento existe en M1 para transferencia lower→upper | Verificar que el O₂ de combustión provenga del flujo entrenado, no de un selector de zona |
| Conducción en paredes | PDE 1D implícita por superficie, multicapa | Modelo lumped; `wall_T_mid` 23°C vs CFAST 73–91°C a t>400s | Reconocido como "requiere PDE + material properties" y nunca implementado |
| Radiación | Fracción radiativa + intercambio entre 4 superficies y capas | Solo `chi_conv`/`chi_r` (split convectivo/radiativo) | Sin transporte radiativo a paredes/targets; afecta flashover, wall_T, FED térmico |
| Flujos en vanos | Bernoulli por franjas con plano neutro + mezcla | Bernoulli + flow_interface canónico + routing M3 por zonas | Cerca de CFAST con flags M3 activos; falta hacerlo default y validar perfiles de velocidad (Steckler) |
| Yields CO/HCN | Yields de entrada (el usuario los da); literatura los liga a φ | Constantes bien-ventilados + multiplicador ×110 ad hoc | Sustituir el ×110 por correlación de equivalence ratio (Gottuk/Lattimer para CO; Purser para HCN sub-ventilado). El README ya reconoce "HCN yield conservador" |
| HVAC | Red de conductos con transporte por zona | Routing por altura de rejilla bajo flag M3 | 4 gaps estructurales aceptados; deberían reevaluarse con two-zone default antes de aceptarlos como permanentes |
| Tenabilidad | N/A (post-proceso) | FED descompuesto + FEC + visibilidad | Más rico que CFAST — es la ventaja competitiva del proyecto; por eso su validación debe ser la más dura, no la más blanda |

### H8 — El conteo "N/N PASS" como métrica de cabecera — SEVERIDAD: MEDIA

El conteo required ha oscilado 292→381→400→381 según se añadían checks, se promovían y se reclasificaban. Un conteo que crece cuando se añaden checks vacuos y se mantiene en 100% mediante tolerancias ajustadas no comunica información. NIST no publica "X/X PASS": publica **sesgo y dispersión por magnitud** con gráficos predicción-vs-medida. La métrica de cabecera de SimuFire debe migrar a ese formato (ver §6.5).

---

## 4. Diagnóstico raíz

Los ocho hallazgos comparten una causa: **el proyecto usó el mismo instrumento (la suite required) para dos funciones incompatibles** — control de regresión ("nada cambió") y validación de realismo ("esto es correcto"). El control de regresión necesita tolerancias estrechas alrededor del comportamiento actual; la validación necesita tolerancias a priori alrededor de la verdad externa. Al fusionarlos, cada gap estructural forzaba a elegir entre "suite en rojo permanente" (insostenible) o "ampliar tolerancia" (falso positivo). Se eligió sistemáticamente lo segundo.

La solución no es disciplina, es **arquitectura de tests**: separar los niveles para que ampliar una tolerancia de validación nunca sea necesario para mantener verde el CI.

---

## 5. Hoja de ruta

Seis fases. Cada una con objetivo, tareas, tests a diseñar y criterio de cierre verificable. Las fases R0–R1 no tocan física y pueden empezar ya; R2 es el grueso de ingeniería; R3–R4 son la validación que da el sello "tipo NIST"; R5 es publicación.

### Fase R0 — Auditoría instrumental de la suite (1–2 semanas, sin tocar el motor)

**Objetivo:** saber exactamente cuánta confianza aporta cada uno de los 381 checks hoy.

| Tarea | Detalle |
|---|---|
| R0-1 Matriz de procedencia de tolerancias | Script `tools/audit_tolerance_provenance.py` que cruza `reference_checks.json` con el historial de GAPS_INVENTORY y clasifica cada check: `A_PRIORI` (tolerancia anterior a conocer el resultado), `FITTED` (tol=\|diff\|+pad), `WINDOWED` (ventana truncada), `VACUOUS` (margen actual/umbral > 5× o tolerancia > 50% del expected), `CONSERVATION` (residual físico). Salida: CSV + resumen por categoría. |
| R0-2 Harness de mutation testing | Implementar `tools/mutation_audit.py` + flags de mutación en el motor (ver §6.3). Ejecutar los ~12 mutantes sobre la suite required y medir **kill rate** (fracción de mutantes que provocan ≥1 FAIL required). |
| R0-3 Congelar verdad CFAST | Crear `truth/cfast/` con: ficheros `.in` de cada escenario, versión exacta de CFAST (7.7.x), script `regenerate_truth.ps1`, hash de cada CSV de referencia. Regenerar todos los CSVs (resuelve la clase de bug HCN=0 y stale-logs de raíz). |
| R0-4 Informe de credibilidad | Documento con: % de checks por categoría, kill rate, lista de los 20 checks más vacuos, lista de overrides de física per-case en casos de validación. |

**Criterio de cierre R0:** existe la matriz; el kill rate inicial está medido (esperar algo del orden de 40–70%; el número exacto es el punto de partida, no un juicio); la verdad CFAST es regenerable con un comando.

### Fase R1 — Reestructuración de la suite en tres niveles (2–3 semanas, sin tocar física)

**Objetivo:** que ningún gap estructural vuelva a requerir ampliar una tolerancia para mantener verde el CI.

**Arquitectura de tres niveles (ver §6.1 para el diseño completo):**

- **Nivel I — Invariantes:** conservación, no-negatividad, simetría, asintótica. Gating estricto, tolerancia = error numérico (~1e-3 relativo). Nunca se amplían.
- **Nivel II — Regresión:** comparación contra baseline congelada del propio motor (lo que hoy hace el contrato legacy y la mayoría de checks FITTED). Gating estricto con tolerancias estrechas, pero **etiquetado y reportado como "regresión", jamás como "validación"**.
- **Nivel III — Validación:** comparación contra verdad externa (CFAST, experimentos) con tolerancias **a priori de §6.2**. Cada check reporta PASS / KNOWN_DEVIATION / FAIL. KNOWN_DEVIATION no rompe el CI pero se publica con su magnitud. **Prohibido convertir un FAIL de Nivel III en PASS tocando la tolerancia**: solo puede pasar a KNOWN_DEVIATION con ficha de causa.

| Tarea | Detalle |
|---|---|
| R1-1 Reclasificar los ~45–50 checks FITTED | Revertir sus tolerancias a los valores a priori de §6.2 y moverlos a Nivel III como KNOWN_DEVIATION con su gap real visible. El conteo de cabecera bajará — eso es el sistema volviéndose honesto, no el motor empeorando. |
| R1-2 Eliminar o endurecer checks VACUOUS | HCN min 10→banda bilateral ±50% sobre el valor de referencia analítico; eliminar peak-checks triviales o convertirlos en invariantes con sentido. |
| R1-3 Prohibir overrides de física en casos de validación | Linter en `check_product.py`: un caso bajo `sim/validation/` no puede contener claves de la lista negra (`*_multiplier`, `*_gain`, `*_boost`, `*_coeff` del motor). Los inputs de escenario (HRR prescrito, geometría, materiales, yields declarados del combustible) sí son legítimos — son la especificación del experimento. `fire_alpha` de Ghanekar debe fijarse desde la fuente experimental (HRR reportado por Ghanekar), no barrido hasta acertar. |
| R1-4 RMSE de ventana completa siempre visible | Donde exista RMSE acotado, añadir el RMSE total como métrica no-gating publicada. |
| R1-5 Métricas de curva | Sustituir/complementar checks puntuales (t=300, t=450) con métricas funcionales por caso y magnitud: NRMSE sobre la serie completa, error de pico, error de tiempo-a-pico, error de tiempo-a-umbral (ej. tiempo a 600°C, a FED=1, a O₂<15%). Los checks puntuales sobreviven solo donde la fuente experimental es puntual. |

**Criterio de cierre R1:** cero checks FITTED activos como validación; kill rate de mutación reevaluado (debe subir respecto a R0); el dashboard reporta por niveles; los KNOWN_DEVIATION publicados coinciden con la lista de gaps físicos de R2.

### Fase R2 — Física núcleo (el grueso: 2–4 meses según dedicación)

**Objetivo:** eliminar las causas estructurales en lugar de tolerarlas. Orden de dependencias respetando el trabajo M1–M4 ya hecho.

| # | Cambio | Justificación / diseño | Test de aceptación (Nivel I/III) |
|---|---|---|---|
| R2-1 | **TwoZoneV1 default** (`two-zone + opening_flow + canonical_pressure`) | Ya está implementado y con contrato PASS; legacy pasa a modo de compatibilidad. Todos los checks CFAST pasan a comparar capa-contra-capa (elimina la familia CMV-1 entera de raíz). | Rebaseline global Nivel II; Nivel III re-evaluado con tolerancias a priori — esperar que presión, o2_lower y estratificación **mejoren drásticamente** y que algunos checks hoy "PASS por tolerancia" pasen a PASS real. |
| R2-2 | **O₂ de combustión vía pluma entrenada** | En lugar del selector upper/lower/interface: la llama consume O₂ del caudal entrenado desde la capa que atraviesa (lower mientras la interfaz esté sobre la base de llama; mezcla cuando la capa desciende sobre el fuego). Es lo que hace CFAST y resuelve por qué `fire_o2_mode=upper` global rompe HRR (la llama no respira de la capa superior salvo inmersión). Elimina la necesidad del modo por caso y debería cerrar los 4 gaps HVAC **sin** el blend rechazado en Phase 4A. | Caso HVAC: CO/CO₂ upper t=300/450 dentro de banda a priori (±30% del delta vs ambiente) sin overrides; mutante M-ENTR (entrenamiento ×0.5) debe disparar FAIL. |
| R2-3 | **Conducción 1D en superficies** | PDE 1D implícita (Crank–Nicolson) por pared/techo/suelo con propiedades de material (k, ρ, c por capa). Cierra los gaps `wall_T_mid` (23°C vs 73–91°C) con física, y corrige el balance de pérdidas que hoy infla los RMSE de temperatura (twofloor 157°C, multifuel 184°C). | `wall_T_mid` t=420/510 dentro de ±15°C vs CFAST con la tolerancia *original* (40°C) o mejor; verificación analítica Nivel I: pared semi-infinita vs solución exacta erf. |
| R2-4 | **Radiación** | Mínimo viable: fracción radiativa del fuego depositada en superficies y capa por factores de vista simples + radiación capa→paredes. Objetivo completo: intercambio 4-superficies tipo CFAST. Afecta flashover (los 2 gaps Ghanekar reabiertos son de timing/altura de flashover — exactamente donde la retroalimentación radiativa manda), wall_T y FED térmico. | Flashover Ghanekar 0.9m y kitchen dentro de sus ventanas experimentales **sin tocar fire_alpha**; criterio MQH re-derivado coherente con el flujo radiativo calculado. |
| R2-5 | **Presión canónica default** | Ya existe; al hacerla default, revertir las 17 tolerancias de presión a ±20–50 Pa originales y comprobar contra CFAST real. | `cfast_closed_t120` ≈ 1022 Pa dentro de ±30%; mutante M-LEAK (fuga ×2) dispara FAIL. |
| R2-6 | **Yields dependientes de ventilación** | Sustituir `fire_co_vent_limited_multiplier=110` por yield CO función del equivalence ratio global de la zona (correlaciones Gottuk/Lattimer, SFPE Handbook), y HCN sub-ventilado según Purser. El φ ya es computable con el ledger de carbono/O₂ existente. | El caso `ghanekar_kitchen_v2` (brecha CO ≈90×) reproduce el orden de magnitud del CO experimental **sin multiplicador**; balance de carbono Nivel I sigue PASS (el ledger ya integra HCN). |
| R2-7 | **Retirar parches per-case** | Eliminar de los casos de validación: `two_zone_convective_heat_multiplier`, caps de temperatura stairwell, `doorway_o2_upper_routing_gain`, `phase2h_lower_cf_drain_coeff` y resto de knobs Phase 2H (el plan M4 ya lo tiene como PENDIENTE RELEASE). Si tras R2-2..R2-6 algún caso los necesita, eso define un gap honesto de Nivel III, no un parche. | Linter R1-3 en verde sobre todos los casos de validación. |

**Criterio de cierre R2:** TwoZoneV1 default; cero overrides de física en validación; los 6 gaps no-gating actuales cerrados con física o re-documentados como KNOWN_DEVIATION con causa que ya no sea "one-zone vs two-zone"; kill rate de mutación ≥90% en mutantes severos.

### Fase R3 — Revalidación CFAST limpia (3–4 semanas)

**Objetivo:** repetir toda la comparación contra CFAST como si fuera la primera vez, con la verdad congelada de R0-3 y las bandas a priori de §6.2.

| Tarea | Detalle |
|---|---|
| R3-1 | Correr la suite completa fresca (motor R2, flags default, cero overrides). |
| R3-2 | Calcular por magnitud y caso: error de pico, error de tiempo-a-pico, NRMSE, y los agregados de sesgo δ y dispersión σ̃ de §6.5. |
| R3-3 | Publicar la tabla magnitud-a-magnitud SimuFire-vs-CFAST con el mismo formato que la CFAST Validation Guide usa contra experimentos. |
| R3-4 | Cada celda fuera de banda → ficha KNOWN_DEVIATION o tarea de física v-next. Ninguna tolerancia se toca. |

**Criterio de cierre R3:** el informe existe y es regenerable con un comando; las bandas no se modificaron después de ver resultados (verificable por git: las bandas se commitean en R1 antes de R2).

### Fase R4 — Validación experimental directa (la fase que da el sello NIST; 1–3 meses, paralelizable con R3)

**Objetivo:** dejar de depender de CFAST como única verdad. Datasets concretos, todos públicos y usados por NIST para validar CFAST/FDS — usar los mismos permite comparar el error de SimuFire con el error publicado de CFAST sobre los mismos experimentos:

| Dataset | Qué valida | Magnitudes |
|---|---|---|
| **Steckler et al. (NIST, 1982)** — 55 configuraciones sala+vano | Flujos en aperturas, plano neutro, entrenamiento | Perfiles de velocidad y temperatura en el vano, caudales entrante/saliente, altura de plano neutro. Es EL test del routing M3. |
| **Fang & Breese (NBS 1980)** — incendios residenciales | Sala única realista | T capa, O₂/CO/CO₂ |
| **NBS Multiroom (Peacock et al.)** — multi-sala con pasillo | Transporte entre salas | T y capa por sala, retardo de llegada de humo — sustituye con datos reales lo que hoy validan `corridor_chain` y `two_room` solo contra CFAST |
| **ISO 9705 room corner** | Flashover con quemador de esquina | HRR, T, tiempo a flashover — complementa Ghanekar |
| **NUREG-1824 / NIST NRC series** | Conjunto amplio con incertidumbre experimental publicada | Permite comparar σ̃ de SimuFire vs σ̃ de CFAST publicado, magnitud a magnitud |
| **FSRI/UL residential** (si se obtienen series) | Casas reales, ventilación dinámica | Apertura de puertas/ventanas — el caso de uso de entrenamiento de bomberos |
| **Purser (SFPE Handbook) + Gann** | Tenabilidad | Ratios FED por componente (ya iniciado), tiempos de incapacitación |

Tareas: parsers de cada dataset a formato común en `truth/experiments/`, casos de escenario fieles a cada geometría experimental (HRR medido como input, no t² genérico), checks Nivel III con la incertidumbre experimental como parte de la banda.

**Criterio de cierre R4:** ≥3 datasets integrados (mínimo Steckler + un multiroom + ISO 9705/Ghanekar reforzado); informe sesgo/dispersión contra experimento; las afirmaciones del README sobre tenabilidad respaldadas por la comparación Purser ampliada.

### Fase R5 — Publicación con declaración de incertidumbre (2 semanas)

Reescribir `SIMUFIRE_VALIDATION_SUMMARY` al formato NIST: metodología, matriz de casos, **tabla de sesgo y dispersión relativa por magnitud** (no conteo PASS), gráficos predicción-vs-referencia con bandas, lista de KNOWN_DEVIATION con causa física, límites de aplicabilidad (el README ya hace esto bien), y reproducibilidad comando-a-comando (ya existe). Regla heredada del plan actual y que sigue siendo correcta: si una magnitud no está validada al nivel declarado, no se publica como cuantitativa.

---

## 6. Diseño del sistema de tests anti-falso-positivo

### 6.1 Taxonomía de tres niveles

| Nivel | Verdad de referencia | Tolerancia | Gating | Puede ampliarse la tolerancia |
|---|---|---|---|---|
| I — Invariantes | Matemática/física exacta (conservación, no-negatividad, asintótica, soluciones analíticas) | Error numérico (~1e-3 rel.) | Sí, siempre | Nunca |
| II — Regresión | Baseline congelada del propio motor (commit registrado) | Estrecha (ruido de integración) | Sí, en CI | Solo con rebaseline explícito y diff publicado |
| III — Validación | Externa: CFAST versionado, experimentos | A priori (§6.2), fijada **antes** de ver resultados | No rompe CI; reporta PASS/KNOWN_DEVIATION/FAIL | Nunca; un fallo se convierte en KNOWN_DEVIATION con ficha, o en tarea de física |

Regla de oro: **un check solo puede vivir en un nivel**. El error histórico fue que los checks CFAST eran simultáneamente II (gating) y III (validación), lo que forzó las tolerancias FITTED.

### 6.2 Política de tolerancias a priori (propuesta inicial, a fijar en R1 y congelar en git antes de R2)

Inspirada en la precisión que la propia validación de NIST atribuye a los modelos zonales. Medir siempre **sobre el delta respecto a ambiente** (un O₂ de 0.19 vs 0.20 es un error del 50% del delta, no del 5% del absoluto):

| Magnitud | Banda Nivel III vs CFAST | Banda vs experimento (añadir incert. experimental) |
|---|---|---|
| T capa caliente | ±15% del ΔT (mín. ±10°C) | ±15% + σ_exp |
| Altura de interfaz | ±20% (mín. ±0.15 m) | ídem |
| O₂/CO₂ (delta vs ambiente) | ±25% del delta | ±30% |
| CO, HCN | factor 2 (la literatura no soporta más precisión en sub-ventilado) | factor 2–3 |
| Presión (sellado) | ±30% | ±30% |
| HRR vent-limited | ±20% | ±20% |
| Tiempo-a-umbral (flashover, FED=1, IDLH, 600°C) | ±20% (mín. ±15 s) | ventana experimental publicada |
| Flujo másico en vano | ±20% | ±20% (Steckler reporta ~±10–15%) |

Si una magnitud no cabe en su banda, el resultado correcto es KNOWN_DEVIATION visible — nunca una banda nueva.

### 6.3 Mutation testing — la prueba de que los tests son reales

Un test que no puede fallar no es un test. El harness (R0-2) inyecta defectos físicos conocidos vía flags de build/CLI (`--mutate=M_XXX`) y exige que la suite los detecte:

| Mutante | Defecto inyectado | Debe dispararse en |
|---|---|---|
| M-HRR | HRR ×1.5 | T, O₂, presión en casi todos los casos |
| M-ENTR | Entrenamiento de pluma ×0.5 | Altura de capa, T upper, llenado |
| M-O2EXT | Umbral de extinción O₂ 0.10→0.05 | Casos sellados/vent-limited (sobre-combustión) |
| M-YCO | Yield CO ×3 | CO upper, FED, IDLH |
| M-YHCN | Yield HCN ×0 | FED desglosado, checks HCN (hoy NO lo detectaría el min:10ppm — ese es el punto) |
| M-LEAK | Área de fuga ×2 | Presión sellada |
| M-CP | c_p aire +20% | T en todos |
| M-WALL | Pérdidas a superficie ×0.5 | T, wall_T, RMSE |
| M-LAYER | Interfaz congelada a 1.5 m | Capa, visibilidad, FED por altura |
| M-VENT | Caudal Bernoulli ×0.7 | Flujos de vano, transporte entre salas |
| M-FEDH | Eliminar componente hipoxia del FED | Tiempos de incapacitación |
| M-PRES | Presión forzada a 0 | Checks de presión y flujos por presión |

**Métrica:** kill rate = mutantes detectados / total, global y por magnitud. **Objetivo: ≥90% severos, 100% de M-HRR/M-YCO/M-PRES.** Se ejecuta en cada release y cuando se añade o modifica cualquier check (un check nuevo debe matar al menos un mutante para entrar en la suite — criterio de admisión).

### 6.4 Reglas operativas permanentes

1. **Tolerancias de Nivel III se commitean antes de los resultados** (verificable en git). Cualquier PR que toque una banda después de una corrida del mismo caso se rechaza.
2. **Cero overrides de física del motor en casos de validación** (linter R1-3). Los casos especifican el experimento, no el modelo.
3. **Checks bilaterales por defecto.** Un `min:` solo es admisible como invariante con justificación (ej. no-negatividad).
4. **Todo check nuevo declara su procedencia** (`tolerance_source: a_priori|experimental_uncertainty|numeric`) y mata ≥1 mutante.
5. **KNOWN_DEVIATION tiene ficha obligatoria:** magnitud del error, causa física, fase prevista de cierre, y check centinela que avisará si el error *crece*.
6. **La frescura, el inventario exacto y los residuales de conservación actuales se mantienen tal cual** — son la parte del sistema que ya es de nivel NIST.

### 6.5 Métrica de cabecera: sesgo y dispersión, no conteo

Para cada magnitud y, en escala log para concentraciones:

- Sesgo: `δ = exp(media(ln(M_i/E_i)))` (M = SimuFire, E = referencia)
- Dispersión relativa: `σ̃ = desv(ln(M_i/E_i))`

Publicado como tabla y nube de puntos predicción-vs-referencia con la diagonal y las bandas — el formato exacto de la CFAST Validation Guide. El README sustituye "381/381 PASS" por: *"T capa: δ=1.04, σ̃=0.11 (n=62) vs CFAST; δ=1.09, σ̃=0.18 (n=31) vs experimento"* (valores ilustrativos). Eso sí es comparable con NIST, y es imposible de inflar con tolerancias.

---

## 7. Qué pasará con el contador cuando se haga esto (gestión de expectativas)

Al aplicar R1, el dashboard mostrará por primera vez la verdad: probablemente del orden de 280–330 checks en PASS real de Nivel III y 50–100 en KNOWN_DEVIATION. **Eso no es una regresión: es la foto honesta del estado actual que el contador 381/381 estaba ocultando.** Cada fase de R2 convertirá deviations en PASS reales, y esa curva descendente de deviations — no el conteo — es el indicador de progreso correcto hacia el realismo CFAST.

## 8. Riesgos principales

| Riesgo | Mitigación |
|---|---|
| R2-1 (two-zone default) destapa regresiones en escenarios de producto/juego | Mantener legacy como modo de compatibilidad seleccionable durante una versión; suite de producto (57 checks) corre en ambos modos durante la transición. |
| R2-4 (radiación) es el cambio de mayor incertidumbre de calibración | Implementar en dos etapas (deposición simple → intercambio completo) con mutante M-RAD propio y validación Steckler/ISO 9705 entre etapas. |
| Datasets experimentales con documentación incompleta | Empezar por Steckler y NBS Multiroom, que son los mejor documentados y los que NIST usa; Ghanekar ya está integrado. |
| El kill rate inicial sea bajo y desmoralice | Es el dato más valioso de toda la auditoría: cada mutante no detectado señala exactamente qué check diseñar. Tratarlo como backlog, no como nota. |

## 9. Definición de terminado (sustituye a la actual)

El proyecto alcanza el estándar objetivo cuando: (1) TwoZoneV1 es default y legacy es compatibilidad; (2) cero tolerancias FITTED y cero overrides de física en validación, verificado por linter; (3) kill rate ≥90%; (4) sesgo y dispersión publicados por magnitud contra CFAST **y** contra ≥3 datasets experimentales, en bandas a priori congeladas en git antes de las corridas; (5) toda desviación restante tiene ficha KNOWN_DEVIATION con centinela de crecimiento; (6) el informe final es regenerable con comandos documentados desde la verdad versionada en `truth/`.
