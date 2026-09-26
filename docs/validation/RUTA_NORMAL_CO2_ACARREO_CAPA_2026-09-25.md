# Ruta normal — el acarreo de gas caliente sacaba CO₂ de la capa baja, 25 de septiembre de 2026

> **Pregunta:** en la ruta que ejecutan los escenarios distribuidos
> (`pressure_network_solver_enabled = false`), ¿dónde aparece por primera vez
> una pérdida, creación o duplicación no justificada de masa, especies o
> energía que alimente FED/SVV?
>
> **Base:** [E1 — base de masa](E1_O2_BASE_DE_MASA_2026-09-25.md) ·
> [S0d5b — transporte zonal de CO₂](PHASE3_H32S0D5B_CO2_ZONAL_TRANSPORT.md) ·
> [diseño fase 2E, §`all_upper`](../architecture/PHASE_2E_DESIGN.md) ·
> [auditoría Godot 4.7.1](GODOT_471_HEADLESS_CRASH_AUDIT.md)
>
> Punto de partida: HEAD = origin/main = `00428a6a`, árbol limpio, sin Godot
> ni Python vivos, 6,2–8,2 GB libres de 15,7 GB. Todas las ejecuciones de Godot
> fuera del sandbox y en secuencia.

---

## 0. Resultado

| | |
|---|---|
| **Defecto** | `ThermalSystem._transfer_hot_gas_contaminants()` dimensionaba el CO₂ de una parcela de **capa alta** sobre el CO₂ **total** de la sala y restaba de la **capa baja** del origen la parte que no estaba arriba, sin que ningún gas de esa capa se moviera; todo llegaba a la capa alta del receptor. CO y HCN, en la misma función, ya salían de la capa alta. |
| **Primer paso** | 417 (t = 34,75 s), Salón → Pasillo, en `preset_simple_house`. |
| **Magnitud (300 s)** | 6,713 kg de CO₂ sacados de capas bajas en 17 343 de 21 280 acarreos; el 49 % del CO₂ que movió el acarreo. |
| **Arreglo** | el CO₂ se dimensiona sobre la capa alta disponible y sale entero de ella, igual que el CO (una función `.gd`, 2 bloques). |
| **Efecto acotado** | solo cambian `co2_kg`, `co2_upper_kg` y FED (por V_CO₂). Masa, energía, temperaturas, O₂, CO, HCN, humo y HRR idénticos bit a bit. Red ON idéntica byte a byte. |
| **FED/SVV** | FED cambia de 0 % a +6,3 % por sala. **No se declara FED ni SVV validado.** |
| **Referencia** | 346/346 requeridos y 0 de 532 comprobaciones cambian, pero la regeneración **no pudo escribir** `reference_checks.json`: 51 huecos conocidos tienen fijada la huella de artefactos que ahora cambian (§9). **Sin commit**, a la espera de decisión. |

---

## 1. Qué ruta corre de verdad (medido, no supuesto)

Montaje igual a `tools/run_scenario_headless.gd` (edificio fuera del árbol,
motor al árbol, un frame, `reset_simulation`), paso 1/12 s, 3 600 pasos. El
arnés vuelca todas las propiedades `bool` del motor tras el reinicio.

| escenario | red | `two_zone_solver_enabled` | `fire_o2_mode` | ACH | aberturas |
|---|---|---|---|---|---|
| `preset_simple_house` (G0, 6 salas) | **OFF** | ON | `legacy` | 0,5 /h | 5 puertas interiores abiertas, 6 exteriores cerradas, vidrio sin rotura |
| control `tworoom` / `tworoom_nofire` | OFF | ON | `legacy` | 0,5 /h | 1 puerta abierta |
| `preset_two_storey_house` (G0, 13 salas) | OFF | ON | `legacy` | 0,5 /h | según preset |

32 interruptores `bool` activos; ninguno experimental (D1, D2, D3, R3, puerta
canónica, contraflujo térmico, `fire_o2_canonical_enabled` y red: apagados).
Activos relevantes: `two_zone_opening_flow_enabled`, `interior_transport_enabled`,
`radiation_opening_enabled`, `wall_conduction_enabled`, `wall_pde_enabled`,
`phase3_thermodynamic_pressure_enabled`, `vent_bernoulli_enabled`.

---

## 2. Instrumento

Temporal, fuera del árbol versionado (`runs/fase_ruta_normal/`, ignorado):

- **Motor por etapa.** Subclase de `SimulationEngine` que solo añade un
  observador al gancho que ya existe entre etapas
  (`_phase3_zone_runtime_record_stage_shared`). Tras cada etapa del paso vuelca,
  por sala: masa y energía por capa, temperaturas, O₂ por capa, CO/CO₂/HCN
  total y de capa alta, humo, irritantes, contadores declarados (generación,
  exterior, transporte, consumo de O₂) y el **inventario en tránsito** de las
  parcelas diferidas de GES.
- **Térmico por función.** Subclase de `ThermalSystem` que envuelve cada
  escritor zonal (penacho, `sync`, radiación, conducción, PDE, intercambios de
  fondo, puente de escalera, mezcla vertical, `flush`, `reconcile`, FED) con
  **atribución exclusiva** (delta propio = delta total − llamadas anidadas),
  reiniciada en cada etapa, y un registro por evento de
  `_transfer_hot_gas_contaminants`.
- **GES por camino.** Subclase de `GasExchangeSystem` que observa la creación
  de parcelas y los caminos zonales (`_move_upper/lower_zone_species`,
  intercambios netos y dirigidos, cola exterior, resultado de puerta).
- **No intrusión:** la corrida con las tres sondas produce un volcado **idéntico
  byte a byte** al de la corrida sin sondas (antes y después del arreglo).

---

## 3. Baseline (HEAD `00428a6a`, `preset_simple_house`, 300 s)

### 3.1 Totales del edificio: cierran

Con el tránsito incluido, cada especie cierra por paso a precisión de máquina:

| término | medido |
|---|---|
| CO que sale en `gas_exchange` | −0,065871 kg = contador exterior (0,065871) |
| humo | generado 5,424 − venteado 2,164 − depositado 0,001 = **+3,2597 kg** exacto |
| residuo por paso, etapas sin fuente | CO ≤ 9·10⁻¹⁶ kg, CO₂ ≤ 7·10⁻¹⁵, HCN ≤ 7·10⁻¹⁸ |
| combustión vs generación declarada | ≤ 7·10⁻¹⁵ kg |
| en tránsito al final | 1 436 parcelas; 0,199 kg CO, 1,288 kg CO₂ |

Sin el tránsito el CO de `gas_exchange` parecía perder 0,199 kg: **no era un
defecto**, eran parcelas en vuelo. Con la red OFF la masa de gas por capa no
es estado (proyección isobárica, decisión P1 pendiente), así que el balance
útil es el de especies y energía.

### 3.2 Inventarios por capa: la anomalía

| etapa | CO alta | CO₂ total | **CO₂ alta** | HCN alta |
|---|---:|---:|---:|---:|
| combustión | +4,146 | +31,21 | +31,21 | +0,0165 |
| **térmica** | −0,005 | −1·10⁻¹⁴ | **+6,628** | −1·10⁻⁵ |
| gas_exchange | −1,351 | −1,816 | −16,67 | −0,0082 |

En la etapa térmica el Pasillo gana **+4,21 kg de CO₂ total pero +7,64 kg en
su capa alta**, y el Salón pierde 3,28 kg de su capa **baja**. El CO no lo
hace. La atribución exclusiva cierra la etapa térmica **al 100 %** (residuo 0):

| escritor | CO₂ alta (kg) |
|---|---:|
| `_flush_contaminant_deltas` (acarreo de gas caliente) | **+6,713** |
| `reconcile_two_zone_building` (colapso de capa sin masa) | −0,085 |
| resto | 0 |

### 3.3 Por evento

| | |
|---|---|
| acarreos de gas caliente | 21 280 |
| con CO₂ sacado de la capa baja del origen | **17 343** |
| CO₂ acarreado | 13,710 kg, de ellos **6,713 kg (49 %) de capas bajas** |
| CO y HCN sacados de capas bajas | **0** |
| primer evento | paso **417**, Salón → Pasillo |

| origen → destino | acarreos | CO₂ de capa baja / total (kg) |
|---|---:|---|
| Salón → Pasillo | 5 412 | 3,283 / 8,961 |
| Pasillo → Cocina | 3 967 | 1,250 / 1,752 |
| Pasillo → Dormitorio1 | 3 967 | 0,915 / 1,263 |
| Pasillo → Baño | 3 967 | 0,637 / 0,871 |
| Pasillo → Dormitorio2 | 3 967 | 0,629 / 0,863 |

---

## 4. Mecanismo

`ThermalSystem.step()` mueve la parcela de **capa alta a capa alta**:

```gdscript
hot_room.upper_gas_kg = maxf(0.0, hot_room.upper_gas_kg - gas_moved_kg)
cold_room.upper_gas_kg = maxf(0.0, cold_room.upper_gas_kg + gas_moved_kg)
_transfer_hot_gas_contaminants(hot_room, cold_room, gas_moved_kg, ...)
```

y en `_transfer_hot_gas_contaminants`, con `f = gas_moved / upper_gas_before`:

| especie | antes | ¿de qué capa sale? |
|---|---|---|
| CO | `co_upper × f × carry` | alta |
| HCN | `hcn_upper × f × carry × 0,40` | alta |
| **CO₂** | **`co2_kg × f × carry`**, restando `co2_upper/co2_kg` de la alta | **alta y baja** |

La parte `co2_lower × f × carry` salía de la capa baja del origen sin gas de esa
capa que la llevase y entraba en la capa alta del receptor. En términos de
balance por capa: la capa baja del origen perdía CO₂ sin ningún flujo de capa
baja que lo justificase, y la alta del receptor lo ganaba sin fuente de capa
alta. El diseño de la fase 2E ya había fijado la semántica («la función
representa una parcela de gas de la capa caliente»), y el comentario de la
cabecera de `ZoneFireSolver` muestra el origen: el seguimiento de `co2_upper`
se añadió sobre un transporte que ya se dimensionaba con el total.

**Por qué nadie lo vio.** S0d5a/b/c vigilaban `co2_upper ≤ co2_kg`; esta ruta
nunca deja la capa baja negativa, y S0d5b anotó que «las rutas térmicas de CO₂
no crean violaciones». El invariante que lo detecta es otro: **una especie solo
sale de una capa con gas de esa capa**.

### 4.1 Por qué es el primero causal

Las especies aparecen en capas bajas antes (paso 5), pero por `gas_exchange`
hacia salas **sin capa alta** (masa alta 0): no hay otra capa donde
depositarlas; es representación, no creación. El primer traslado entre capas
sin portador es este (paso 417). El mismo patrón en las parcelas de humo de
GES empieza un paso después (418) y es menor (§7).

---

## 5. Arreglo

`sim/core/ThermalSystem.gd`, función `_transfer_hot_gas_contaminants`:

```diff
-	var co2_moved_kg: float = minf(source.co2_kg, source.co2_kg * upper_fraction_moved * carry)
+	var co2_upper_available_kg: float = clampf(source.co2_upper_kg, 0.0, source.co2_kg)
+	var co2_moved_kg: float = minf(source.co2_kg, co2_upper_available_kg * upper_fraction_moved * carry)
 ...
-		var co2_source_upper_kg: float = 0.0
-		if source.co2_kg > 0.0001:
-			var src_upper_frac: float = clampf(source.co2_upper_kg / source.co2_kg, 0.0, 1.0)
-			co2_source_upper_kg = co2_moved_kg * src_upper_frac
+		var co2_source_upper_kg: float = co2_moved_kg
```

- Es la misma regla que ya usaba el CO en esa función. El donante es la capa
  alta del origen; no hay clamp nuevo, tolerancia, reasignación ni métrica.
  El limitador de concentración F0 queda igual.
- **Sin interruptor.** Es la ruta que ejecuta `SimulationEngine.step()` →
  `ThermalSystem.step()` en todo escenario con la red apagada, así que el
  jugador lo recibe en todos los escenarios distribuidos sin configurar nada.
  Con la red ON la función no se llama (guarda P3), por eso esa ruta no cambia.

---

## 6. Después del arreglo

### 6.1 Conservación e identidades

| comprobación | resultado |
|---|---|
| CO₂ sacado de capas bajas por el acarreo, casa 300 s | 6,713 kg → **0** (21 280 acarreos, 21 065 desde orígenes con CO₂ bajo) |
| etapa térmica, CO₂ alta atribuida a `flush` | +6,713 → **−2·10⁻¹⁴** kg |
| cierre de especies por paso | igual que antes: ≤ 7·10⁻¹⁵ kg (CO₂) |
| campos de estado que cambian en algún paso y etapa | solo `co2_kg`, `co2_upper_kg`, `fed`, `fed_hcn` |
| casa con la **red ON** | **idéntica byte a byte** |
| casa **sin ignición** | idéntica byte a byte |
| dos salas **sin fuego** | idéntica byte a byte |
| sondas | no intrusivas (idéntico byte a byte con y sin ellas) |

### 6.2 Efecto en salidas (300 s)

**`preset_simple_house`** (FED a 1,8 m; kg de CO₂):

| sala | FED antes | FED después | Δ | CO₂ total | CO₂ baja | CO₂ alta |
|---|---:|---:|---:|---|---|---|
| Salón (fuego) | 106,1 | 106,1 | 0 % | 7,32 → 9,33 | 4,14 → 7,04 | 3,18 → 2,29 |
| Pasillo | 2,258 | 2,264 | +0,3 % | 3,84 → 3,68 | 0,73 → 1,44 | 3,11 → 2,25 |
| Dormitorio1 | 2,533 | 2,559 | +1,0 % | 5,05 → 4,30 | 0,55 → 0,94 | 4,50 → 3,36 |
| Dormitorio2 | 2,446 | 2,456 | +0,4 % | 3,37 → 3,27 | 0,09 → 0,24 | 3,28 → 3,03 |
| Cocina | 2,035 | 2,162 | **+6,3 %** | 6,45 → 5,68 | 2,58 → 2,82 | 3,87 → 2,86 |
| Baño | 2,407 | 2,413 | +0,3 % | 3,38 → 3,24 | 0,14 → 0,33 | 3,24 → 2,90 |

**`preset_two_storey_house`**: FED cambia solo en el Recibidor (+2,1 %); el
resto igual a 4 cifras. **Dos salas con fuego**: FED igual; CO₂ ±0,01 kg.

Las temperaturas, el HRR y el O₂ no cambian: el arreglo no toca masa ni
energía. FED sube en las salas donde el ocupante está bajo la interfaz, porque
su CO₂ de capa baja (factor de hiperventilación V_CO₂ de ISO 13571) ya no se
vacía hacia capas altas ajenas.

### 6.3 Empeoramiento que hay que decir

La capa baja del Salón (sala del fuego) acumula **7,04 kg** de CO₂ frente a
4,14. No lo crea el arreglo: lo mete `gas_exchange`, y el defecto térmico lo
estaba devolviendo a capas altas. La sonda de GES lo atribuye (300 s, después
del arreglo):

| camino de GES | Salón, capa baja | Pasillo, capa baja |
|---|---:|---:|
| `two_zone upper→lower`: chorro caliente del Salón depositado en la **capa baja** del Pasillo | 0 | **+10,69** |
| `two_zone lower→lower`: contraflujo físico Pasillo → Salón | **+9,02** | −5,38 |

Es un recirculado: capa alta del Salón → capa baja del Pasillo → capa baja del
Salón. Su causa es la **zona de destino del chorro caliente**
(`_resolve_opening_segment_route`), el mismo problema de enrutado por
flotabilidad que P3 dejó documentado para la red. Es el **segundo defecto** y
queda para su propia fase: no se toca aquí.

---

## 7. Defectos que quedan documentados, no corregidos

1. **Destino del chorro caliente en GES** (§6.3): gas de capa alta depositado en
   la capa baja del receptor. Mayor en masa que el corregido.
2. **Mismo patrón en las parcelas de humo de GES**
   (`GasExchangeSystem.step_smoke`, transporte por fracción de humo): CO₂ y HCN
   se dimensionan sobre el total de la sala y llegan enteros a la capa alta del
   receptor. Antes del arreglo: 3,106 kg de CO₂ de 12,69 y 0,005 kg de HCN de
   0,011 desde capas bajas, primero en el paso 418. Aquí la portadora es humo a
   nivel de sala, así que corregirlo exige decidir qué representa la parcela.
3. **S0d5a/S0d5b** siguen tras sus interruptores apagados (magnitud ~10⁻¹¹ kg).
4. **O2-4** (sumidero alto de O₂ con el consumo completo) sigue pendiente de la
   decisión P4. La masa baja como estado (P1) sigue pendiente.

---

## 8. Pruebas

- `tools/validate_hot_gas_layer_species_carry.gd` (22 comprobaciones),
  registrado en `scripts/check_product.py`, y
  `tests/test_hot_gas_layer_species_carry.py`:
  - **H1**: la función real con especies en las dos capas: capa baja del origen
    intacta (CO, CO₂, HCN), CO₂ con la fracción del CO, conservación, capa baja
    del receptor intacta;
  - **H1c**: control sin especies en la capa baja: el acarreo es el de siempre;
  - **H2**: `preset_simple_house`, red OFF, 3 600 pasos: 0 kg de capas bajas y
    el régimen ejercido.
- **Contra el código de HEAD falla** (4 fallos: H1 0,0432 kg de capa baja;
  fracción 0,18 frente a 0,072; H2 6,7131 kg; peor acarreo 0,0116 kg).
  **M2** (dimensionado arreglado pero resta proporcional, como antes) falla 3
  (H2 4,747 kg). Fichero restaurado y verificado por SHA-256 tras cada una.
- La huella OFF de `validate_single_interior_transport_owner.gd` (O4) cambia de
  `4f375edf…` a `a5ec9b8d…`; se re-fija con el motivo escrito (§6.1). Sus otras
  60 comprobaciones (ruta ON) pasan sin cambios.
- El validador nuevo lee `pressure_network_solver_enabled` para exigir red OFF
  en su caso de producto; se añade a la lista autorizada de
  `tests/test_pressure_network_solver.py`.

## 9. Referencia, CFAST/FDS y suites

### 9.1 Regeneración R2-1: ejecutada, **bloqueada al escribir el agregado**

`sim/validation/run_reference_checks.ps1`, una vez, bajo monitor (corte por
debajo de 5 GB o ante fallo nativo): 18 casos, 2 697 s, memoria mínima
7,57 GB, sin fallo nativo. Los 18 informes de caso se regeneraron. El
comparador `validate_reference_cases.py` abortó en `_apply_gap_dispositions`:

```
ValueError: stale gap source artifacts for cfast_2r_hall_rmse_o2
```

Cada uno de los 78 huecos conocidos tiene fijada en
`sim/validation/evidence/p1r8_gap_disposition_evidence.json` su evidencia:
valores **y el SHA-256 de sus artefactos de origen** (el `.json` y el `.log`
del caso). **51 huecos** citan informes cuyo contenido cambia (columnas de
CO₂), así que su huella ya no coincide. `reference_checks.json` **no se
escribió** y R2-1 sigue en rojo.

Para saber qué habría escrito, se ejecutó el mismo comparador **fuera del
árbol** y sin verificar esa evidencia (`runs/fase_ruta_normal/compare_refs.py`):

| | antes | después |
|---|---:|---:|
| requeridos PASS | 346/346 | **346/346** |
| huecos conocidos | 78 | 78 |
| comprobaciones con `actual` o veredicto distinto | — | **0 de 532** |
| huecos con algún valor distinto de su evidencia | — | **0** |
| huecos con solo la huella de artefacto distinta | — | **51** |

En los 18 informes, las métricas que cambian son solo de CO₂ (66), el balance
de carbono derivado de ellas (53) y FED/SVV (8).

**No se ha tocado la evidencia ni ningún informe para que pase.** Re-fijar las
51 huellas es un cambio de un registro revisado («subject to final independent
closure review») y queda para decisión del usuario.

### 9.2 La suite de referencia no ve esta magnitud

Las 24 comprobaciones de CO₂ contra CFAST usan el trazador molar
`room.co2_upper` (`compute_co2_upper_ppm`), que el arreglo no toca; ninguna
mira la capa baja, aunque CFAST la da (`LLCO2`). Por eso «0 cambios» no es una
mejora ni un empeoramiento medido por la suite. Comparación directa con CFAST
reconstruyendo el CO₂ por capa de SimuFire con las fórmulas del motor
(`runs/fase_ruta_normal/cfast_layers.py`; modelo contra modelo, no validación
experimental):

| caso · sala | RMSE CO₂ alta (ppm) | RMSE CO₂ baja (ppm) |
|---|---|---|
| dos salas · R0 | 89 795 → 89 678 (−0,1 %) | 70 392 → 70 344 (−0,1 %) |
| dos salas · Hall | 22 224 → **21 846 (−1,7 %)** | 2 974 → **3 108 (+4,5 %)** |
| corredor · R0 | 70 632 → 70 462 (−0,2 %) | 38 133 → 38 064 (−0,2 %) |
| corredor · Hall | 20 424 → 20 414 | 37 170 → 37 166 |
| corredor · Dormitorio | 32 953 → 32 956 | 488 → 490 |

Las diferencias con CFAST siguen siendo grandes y de otro origen (reparto de
CO₂ por capa en la sala del fuego, destino del chorro caliente §6.3). Ningún
caso FDS aplicable mide CO₂ por capa.

### 9.3 Suites

**Incidente durante la verificación, reparado.** Una primera invocación de
pytest desde la raíz del repo (sin `tests`) recogió `runs/p3_tmp/edit_test.py`
y `runs/p3_tmp/edit_guard_test.py` (casan con `*_test.py`): son scripts de
edición de P3b y su código a nivel de módulo reescribió
`tests/test_single_interior_transport_owner.py` (con un `or True` que
debilitaba una aserción y un literal roto) y `tests/test_guardrails.py`
(bloques duplicados). Ninguna prueba llegó a ejecutarse (la recolección
abortó). Reparado: `test_guardrails.py` vuelto a HEAD y
`test_single_interior_transport_owner.py` a HEAD más la huella re-fijada. Los
worktrees de `runs/` no cambiaron (sus modificaciones son del 31-08 al 08-09).
La suite se ejecuta siempre como `python -m pytest tests`.


| | resultado |
|---|---|
| validador nuevo | 22/22 PASS; falla con HEAD (4) y con M2 (3) |
| validador P3 | 61/61 PASS con la huella O4 re-fijada |
| pytest focalizado (nuevo, P3, red, D1, D2, EOS) | 44 PASS |
| `check_product.py` | 85 filas OK, **1 FAIL**: `test_guardrails::test_exit0_real_json`, que es R2-1 |
| guardarraíles | 346/346 requeridos PASS sobre el informe **antiguo**; **R2-1 FAIL** |
| suite global (`python -m pytest tests`) | **3 003 PASS, 3 FAIL**, 9 omitidas, 2 xfail, 42 subtests: R2-1 (`test_exit0_real_json`) y dos de `test_p1r7_internal_baseline_retirement`, que fijan el SHA-256 de los informes de `cfast_two_floor_stairwell` y `cfast_multi_fuel_couch_tv` en `sim/validation/baseline_gate_dispositions.json` (`current_report_sha256`); esos informes cambian con el arreglo (solo CO₂, carbono y FED) |

## 10. Estado y lo que falta para cerrar

**Sin commit.** El arreglo, su prueba y los 18 informes de caso regenerados
están en el árbol de trabajo. Para cerrar hace falta una decisión del usuario
sobre **dos registros revisados que fijan la huella de los informes de caso**:

1. `sim/validation/evidence/p1r8_gap_disposition_evidence.json`: `bytes` y
   `sha256` de los artefactos de 51 huecos (valores, veredictos y
   disposiciones idénticos, verificado arriba);
2. `sim/validation/baseline_gate_dispositions.json`: `current_report_sha256`
   de `cfast_two_floor_stairwell` y `cfast_multi_fuel_couch_tv`.

**Checkpoint de pausa (25-09):** guardar el trabajo en
`codex/wip-ruta-normal-co2-20260925`, sin incorporar la corrección a `main`.
El commit de esa rama es una copia recuperable del estado **NO APROBADO**, no
un cierre de física. No re-fijar las huellas durante este checkpoint.

**Orden para mañana:**

1. Verificar HEAD, rama, árbol, memoria y procesos. Usar únicamente
   `python -m pytest tests`, nunca pytest sin ruta: `runs/p3_tmp` contiene
   scripts de edición que coinciden con el patrón de recolección.
2. Auditar de forma independiente y sin escribir los 18 diffs de informe:
   identificar todos los campos cambiados y su causalidad. Revisar
   especialmente CO₂ por capa, balance de carbono y FED/SVV; 0/532 checks
   requeridos cambiados no equivale a invariancia de los informes. Comprobar
   que la suma de acarreos desde una misma capa en un paso no supera su
   inventario de CO₂, porque las lecturas del bucle usan estado pre-bucle.
3. Si no aparece otro defecto, conservar las huellas antiguas en el historial
   y actualizar **solo** `bytes`/`sha256` de los artefactos realmente cambiados
   en el registro de 51 huecos y los dos `current_report_sha256` del registro
   de baselines; no alterar valores, veredictos ni clasificaciones. Si aparece
   sobreacarreo o una diferencia no atribuida, corregir primero el motor y
   repetir la referencia completa antes de cualquier cambio de huellas.
4. Ejecutar el comparador normal para escribir `reference_checks.json`; exigir
   346/346, 78 gaps y R2-1 PASS. Repetir `check_product.py` y
   `python -m pytest tests -q -p no:cacheprovider` con Godot fuera del sandbox,
   memoria suficiente y tandas secuenciales. Solo entonces cerrar y proponer
   incorporar el motor a `main`.

Lista de los 51 huecos: `runs/fase_ruta_normal/stale_gap_artifacts.txt`
(fuera del árbol); afectan a los informes de `cfast_two_room_door_open` (13),
`cfast_r0_window_360` (12), `cfast_corridor_chain`, `cfast_post_flashover_vented`
y `cfast_hvac_residential` (5 cada uno), `cfast_slow_growth_sealed` y
`ghanekar_bedroom_hallway` (3), `ghanekar_kitchen_living_room` (2) y
`cfast_long_burnout_3600s`, `cfast_door_close_midfire`,
`cfast_multi_fuel_couch_tv` (1).

## 11. Revisión separada de informes y huellas — 26-09

Retomado desde el checkpoint `b08d634` en
`codex/wip-ruta-normal-co2-20260925`. Se comparó cada informe modificado con
`main`, sin usar los veredictos de la suite como sustituto del diff:

- **13 JSON y 5 CSV**, mismos esquemas y filas. En los JSON cambiaron 127
  campos, todos numéricos y todos bajo `metrics`: 66 de CO₂, 53 residuales de
  carbono derivados y 8 de FED. En los CSV solo cambian `co2_ppm`,
  `co2_upper_ppm_mass`, `carbon_conservation_error_kg`, `fed`, `fed_co` y
  `fed_hcn`. Los casos y las verdades CFAST no cambiaron.
- El cambio relativo mayor de FED entre informes es **−20,2 %** en
  `room_6_final_fed_co` de `cfast_two_floor_stairwell` (2,8603 → 2,2833).
  No se minimiza por estar fuera de los 532 checks: el CO₂ de la zona baja
  modifica `V_CO2`, que multiplica FED_CO y FED_HCN en `step_fed()`. Esto
  establece causalidad dentro del modelo, **no validación fisiológica**.
- Se localizaron las copias anteriores de los `.log` ignorados por Git en
  `runs/p1r8_session91_checkout/sim/validation/reports/`. Su SHA-256 y tamaño
  coinciden con el registro revisado anterior. Comparados línea a línea con
  los nuevos: mismas líneas, mismos campos; **solo cambia `CO2` en 2631
  segmentos**. No se re-fijó una huella sin comparar su contenido anterior.
- Traza independiente de `preset_simple_house` a 300 s: 21 280 acarreos en
  6076 grupos (paso, etapa, sala origen). Cero grupos extraen más CO₂ alto que
  el inventario anterior al bucle; el máximo es 0,575 % del inventario, con
  cuatro acarreos en ese grupo. La prueba es del escenario medido; no demuestra
  una cota universal para geometrías o parámetros arbitrarios.
- Los 51 checks conservan valores y veredictos. Se re-fijaron mecánicamente
  solo 162 campos `bytes`/`sha256` de sus 20 artefactos únicos (JSON y logs)
  y los dos `current_report_sha256` de baselines. Las huellas antiguas quedan
  en `main` y en el commit WIP previo; no se tocaron clasificaciones ni
  tolerancias. El comparador **normal, con verificación de evidencia activada**,
  ya escribe `reference_checks.json` con 346/346 requeridos y 78 gaps.

R2-1 sigue rojo **hasta que el informe actualizado se confirme junto al
motor**: ahora el último commit de motor es el WIP `b08d634`, y el último
commit del agregado en esta rama aún es `00428a6a`. No se interpreta ese rojo
como fallo de los casos ni se esquiva alterando fechas. Las 17 pruebas
focalizadas de ambos registros pasan. Pendiente antes de proponer `main`:
`check_product.py` y `python -m pytest tests -q -p no:cacheprovider`, con
memoria suficiente y Godot fuera del sandbox. Al revisar había 4,3–5,4 GB
libres, por debajo del umbral operativo de 6 GB; no se inició Godot.
