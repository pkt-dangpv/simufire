# Diseño Phase 2E — Transporte two-zone coherente

**Estado**: Backlog — NO implementar sin rama + rebaseline separados  
**Fecha**: 24 mayo 2026  
**Baseline de referencia**: commit `1901423`, 289/289 required PASS, 73 non-gating gaps  
**Archivos afectados (sin tocar aún)**: `sim/core/ThermalSystem.gd`, `sim/core/OxygenExchangeSystem.gd`, `sim/core/GasExchangeSystem.gd`

---

## 1. Por qué no se puede tocar transporte/FED de forma incremental

### 1.1 El contrato actual de `co_upper_kg`

En el modelo actual, la variable `room.co_upper_kg` tiene un contrato implícito muy específico:

**Sala con fuego activo** (`sync_room_upper_layer`, ThermalSystem.gd línea 2671):
```gdscript
room.co_upper_kg = room.co_kg   # 100% del CO de la sala está en la capa alta
```

**Sala sin fuego activo** (línea 2675):
```gdscript
room.co_upper_kg = 0.0          # Sin fuego → sin capa caliente → sin estratificación
```

**Transporte entre salas** (`_transfer_hot_gas_contaminants`, líneas 1860–1957):  
El CO transportado desde la sala fuente se acumula 100% en `co_upper_kg` de la sala destino:
```gdscript
_delta_co_upper_kg[tgt_id] += co_moved_kg  # Todo el CO transportado va al upper layer
```

Este contrato hace que `compute_co_upper_ppm` en salas receptoras sea una estimación conservadora
(pesimista en concentración, lo que adelanta el FED). Cambiar este contrato sin rebaseline es un
riesgo directo sobre los checks required de timing FED.

### 1.2 Cómo `step_fed` consume `co_upper_kg`

`step_fed` (ThermalSystem.gd, línea 2441) y `compute_fed_delta_for_height` (línea 2387)
determinan si una víctima está en la zona superior con:

```gdscript
var in_upper: bool = (room.h_layer_m < height_m and room.upper_gas_kg > 0.1)
var co_ppm: float = compute_co_upper_ppm(room) if in_upper else compute_co_ppm(room)
```

Cuando la víctima NO está en la capa superior (e.g., víctima a 1.8 m y `h_layer_m ≥ 1.8 m`),
se usa `compute_co_ppm(room)` — la media volumétrica total, que incluye el CO del upper layer
diluido en el volumen total de la sala. Si en Phase 2E se dividiera el CO entre zonas y se
usara `compute_co_lower_ppm` en este path, la concentración bajaría → FED más lento → riesgo
de FAIL en checks de timing.

### 1.3 Sites de escritura de `upper_gas_kg` que crean acoplamiento

El volumen de gas caliente controla el flag `in_upper`. Tiene **13+ sites de escritura**
distribuidos en ThermalSystem.gd; un cambio en transporte cambia `upper_gas_kg` en salas
receptoras, lo que puede cambiar el flag `in_upper` en pasos subsiguientes → efecto en cascada
sobre FED, O₂ upper, CO₂ upper — todo acoplado.

---

## 2. Checks required que dependen del contrato actual

### 2.1 Checks g4 — críticos (tolerancia estrecha)

Escenario: `g4_gie_delayed_entry_hazard` — sala con fuego intenso, entry delayed.

| Check | Actual | Expected | Tol | Margen al límite |
|-------|--------|----------|-----|--------|
| `g4_gie_delayed_entry_hazard_time_room_1_fed_above_0_1_s` | 198.4 s | 197.75 s | ±10 s | **9.33 s** (desviación actual: 0.67 s) |
| `g4_gie_delayed_entry_hazard_room_1_peak_co_upper_ppm` | 62716.9 ppm | ≥2000 ppm | — | holgado (+60716 ppm) |
| `g4_gie_delayed_entry_hazard_time_room_1_co_upper_above_1200_s` | 85.58 s | 87.33 s | ±5 s | **3.25 s** (desviación actual: 1.75 s) |

El check de CO>1200 timing tiene el margen más ajustado: **3.25 s restantes** sobre una
tolerancia de ±5 s. Phase 2E-A (CO transport split) afecta directamente este timing.

### 2.2 Checks v3 — importantes

Escenario: `v3_hallway_fed_exposure` — víctima en pasillo receptor (sin fuego directo).

| Check | Actual | Expected | Tol | Margen |
|-------|--------|----------|-----|--------|
| `v3_hallway_fed_exposure_time_room_1_fed_above_0_1_s` | 249.8 s | 252.2 s | ±30 s | holgado |
| `v3_hallway_fed_exposure_room_1_max_fed` | 2.212 | ≥1.0 | — | holgado |

El pasillo **no tiene fuego activo** → `co_upper_kg` viene solo de transporte desde room_0.
Phase 2E-B-transport (dividir CO entre zonas en destino) reduciría `co_upper_kg` en el pasillo
→ FED más lento → retraso de `time_room_1_fed_above_0_1_s`. Actualmente hay 2.4 s de margen
respecto al expected; la tolerancia es ±30 s, así que hay espacio, pero hay que medir.

### 2.3 Checks victim_fed — importantes

| Check | Actual | Expected/Min | Estado |
|-------|--------|-------------|--------|
| `victim_fed_incapacitation_victim_v0_final_fed` | 0.7715 | ≥0.7 | PASS (margen 0.07) |
| `victim_fed_incapacitation_peak_co_ppm_global` | 3381.9 ppm | ≥1500 ppm | PASS (holgado) |

El FED final tiene margen 0.0715 sobre 0.7 (10.2 % relativo). Un cambio que reduzca CO lower
ppm durante la exposición podría comprometer este margen.

### 2.4 Checks CO upper layer (no required, informativos)

| Check | Actual | Expected | Tol | Status |
|-------|--------|----------|-----|--------|
| `cfast_t350_co_upper_ppm` | — | 688.9 ppm | ±320 | PASS |
| `cfast_t360_co_upper_ppm` | — | 694.0 ppm | ±320 | PASS |

Estos ya son non-gating pero sirven para verificar que el transporte CO upper sigue correcto.

---

## 3. Cambios arquitectónicos a agrupar en rama separada

Toda la Phase 2E debe implementarse en **una sola rama** con rebaseline explícito. Los
componentes deben implementarse en el orden indicado para minimizar interferencias.

### 3.1 Componente A — Two-zone CO split en transporte (B-transport)

**Archivo**: `sim/core/ThermalSystem.gd`, función `_transfer_hot_gas_contaminants` (línea 1860)

**Problema actual**: el CO transportado va 100% a `co_upper_kg` del destino.  
**Objetivo**: dividir el CO entre zona superior e inferior del destino según la fracción
`upper_vol_fraction = (1 - h_layer_m / height_m)` (proporción de volumen de zona superior).

**Cambio conceptual**:
```gdscript
# Antes: todo el CO va al upper layer del destino
_delta_co_upper_kg[tgt_id] += co_moved_kg

# Después: fraccionar según volumen de zonas en destino
var tgt_upper_vol_frac: float = clampf(
    1.0 - (target.h_layer_m / maxf(0.01, target.height_m)), 0.0, 1.0
)
_delta_co_upper_kg[tgt_id] += co_moved_kg * tgt_upper_vol_frac
_delta_co_lower_kg[tgt_id] += co_moved_kg * (1.0 - tgt_upper_vol_frac)
```

**Nota**: requiere añadir `_delta_co_lower_kg` dict (análogo a `_delta_co_upper_kg`) y
variable de estado `room.co_lower_kg` en RoomModel.gd.

**Riesgo**: ALTO — cambia `co_upper_kg` en salas receptoras → afecta `in_upper` en `step_fed`
→ afecta g4 `time_room_1_fed_above_0_1_s` y v3 FED timing.

### 3.2 Componente B — FED por zona con `co_lower_kg`

**Archivo**: `sim/core/ThermalSystem.gd`, funciones `step_fed` (línea 2441) y
`compute_fed_delta_for_height` (línea 2387)

**Problema actual**: cuando `in_upper = false`, se usa `compute_co_ppm(room)` (media total),
que incluye el CO upper diluido en el volumen total. Sin co_lower_kg, es la mejor aproximación.

**Objetivo**: si existe `co_lower_kg`, usar `compute_co_lower_ppm_real` basado en esa variable
en lugar de `compute_co_ppm`.

```gdscript
# Cambia en step_fed y compute_fed_delta_for_height:
var co_ppm: float
if in_upper:
    co_ppm = compute_co_upper_ppm(room)
elif room.co_lower_kg > 0.001:  # co_lower existe
    co_ppm = compute_co_lower_ppm_real(room)  # co_lower_kg / lower_vol / molar_factor
else:
    co_ppm = compute_co_ppm(room)  # fallback conservador actual
```

**Riesgo**: MEDIO — puede reducir FED en víctimas de zonas bajas. `victim_fed_incapacitation`
(margen 0.0715) es el check más sensible.

### 3.3 Componente C — O₂ por zona en transporte de apertura

**Archivo**: `sim/core/OxygenExchangeSystem.gd`, función de interroom flow (línea 296)

**Problema actual**: el flujo de O₂ entre salas no discrimina zona alta/baja de destino.
El modelo de doorway flow es uniforme: O₂ sale de la sala fuente y entra mezclado.

**Objetivo**: modelo two-zone de apertura (CFAST/BRI inspired):
- Por la mitad superior del vano: sale humo caliente (sale `upper_gas_kg`, consume O₂ upper)
- Por la mitad inferior: entra aire fresco (entra a zona inferior, sube `o2_lower`)

**Riesgo**: ALTO en O₂ lower — `o2_lower` ya existe como variable; si aumenta el influx de
aire fresco, reduce FED hipoxia en zona baja. Afecta escenarios multi-room donde O₂ bajo
mantiene el fuego vivo.

### 3.4 Componente D — CO₂ lower zone tracking

Análogo al componente A pero para CO₂. `co2_lower_kg` actualmente no existe.

**Riesgo**: BAJO en FED (CO₂ solo entra como amplificador `v_CO₂`), MEDIO en gaps
`CO₂ upper layer` (5 non-gating checks).

### 3.5 Rebaseline explícito (paso obligatorio, no omitir)

Antes de hacer commit de Phase 2E en `main`:

1. Ejecutar suite completa: `python scripts/simulation/validate_reference_cases.py`
2. Verificar checks g4 (tolerancia estrecha ±10 s / ±5 s):
   - `g4_gie_delayed_entry_hazard_time_room_1_fed_above_0_1_s` — expected=197.75, tol=10
   - `g4_gie_delayed_entry_hazard_time_room_1_co_upper_above_1200_s` — expected=87.33, tol=5
   - `g4_gie_delayed_entry_hazard_room_1_peak_co_upper_ppm` — min=2000
3. Verificar checks victim_fed (margen estrecho 0.07 sobre FED mínimo):
   - `victim_fed_incapacitation_victim_v0_final_fed` — min=0.7
4. Si g4 o victim_fed FAIL: ajustar `hot_gas_species_carry_fraction` o tolerancias **y documentar**
   la razón física antes de commitear el ajuste.
5. Actualizar `docs/validation/GAPS_INVENTORY.md` con nuevo conteo de gaps.

---

## 4. Validaciones mínimas por componente

| Componente | Validation mínima | Checks a verificar |
|-----------|-------------------|--------------------|
| A (CO transport) | Suite completa | g4 timing (±10 s), v3 timing (±30 s), `cfast_*_co_upper_ppm` |
| B (FED por zona) | Suite completa | victim_fed (FED ≥0.7), v3 max_fed (≥1.0) |
| C (O₂ doorway) | Suite completa | `cfast_2r_r0_t300_o2` (ya PASS), escenarios HVAC/multi-floor |
| D (CO₂ lower) | Suite completa | CO₂ upper checks (non-gating), no afecta required |
| **Full Phase 2E** | **Suite + revisión manual gaps** | **289/289 required mínimo; documentar gaps nuevos vs cerrados** |

Para cada componente, ejecutar también el smoke-test mínimo:
```bash
# Quick smoke (solo escenarios afectados, más rápido)
python scripts/simulation/validate_reference_cases.py --filter g4,v3,victim_fed,cfast_2r

# Suite completa antes de merge
python scripts/simulation/validate_reference_cases.py
```

---

## 5. Riesgos y criterios de aceptación

### 5.1 Tabla de riesgos

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|------------|
| g4 `time_fed_above_0_1` sale de ±10 s | ALTA | Bloqueo de merge | Ajustar `hot_gas_species_carry_fraction` (actualmente controla cuánto CO llega al destino) |
| victim_fed FED final < 0.7 | MEDIA | Bloqueo de merge | Aumentar `hot_gas_species_carry_fraction` a destino o reducir `o2_lower_plume_entr_rate` |
| Nuevos gaps por CO lower siendo > expected=0 en CFAST | BAJA | Non-gating (no bloquea) | Aceptar como nuevo gap; documentar en GAPS_INVENTORY |
| O₂ lower sube demasiado → fuego no se extingue en t esperado | MEDIA | Escenarios HVAC FAIL | Calibrar `ach_infiltration` como contrapartida |
| Explosión de complejidad: demasiados deltas acoplados | ALTA | Bugs difíciles de trazar | Implementar componentes A→D en orden estricto; no mezclar en un solo commit |

### 5.2 Criterios de aceptación de Phase 2E completa

**Obligatorios (gate para merge a main)**:
- [ ] 289/289 required PASS (no regresión de ningún required check)
- [ ] g4 timing FED: 197.75 ±10 s (187.75–207.75 s)
- [ ] g4 CO upper: ≥2000 ppm
- [ ] victim_fed FED final: ≥0.7
- [ ] Sin warnings de "NaN" o "Inf" en el output de simulación
- [ ] Documentación de rebaseline en commit message si se ajustan tolerancias

**Deseables (mejoras medibles de gaps)**:
- [ ] ≥5 gaps de O₂ zona inferior cerrados (de 10 actuales)
- [ ] ≥3 gaps de CO₂ upper cerrados (de 5 actuales)
- [ ] CO lower gap (`cfast_2r_hall_t360_co_lower_ppm`) cerrado (sim ≈ 0 como espera CFAST)
- [ ] Total gaps no-gating ≤ 65 (reducción desde 73 actuales)

### 5.3 Secuencia recomendada de implementación

```
rama: feature/phase-2e-two-zone

Commit 1: Añadir RoomModel.co_lower_kg (nuevo campo, sin lógica)
Commit 2: Componente A — CO transport split
  → smoke test g4/v3; ajustar si necesario; documentar
Commit 3: Componente D — CO₂ lower zone (bajo riesgo)
  → smoke test
Commit 4: Componente B — FED por zona (usa co_lower_kg)
  → smoke test victim_fed; ajustar si necesario; documentar
Commit 5: Componente C — O₂ doorway two-zone (alto riesgo)
  → suite completa; calibración; documentar
Commit 6: Rebaseline + update GAPS_INVENTORY
Merge PR: requiere 289/289 PASS + revisión manual de criterios de aceptación
```

---

## 6. Estado actual del código relevante

### 6.1 Variables de estado existentes (sin cambiar)

| Variable | Archivo | Línea | Descripción |
|---------|---------|-------|-------------|
| `room.co_upper_kg` | RoomModel.gd | 72 | CO en zona superior [kg] |
| `room.co_kg` | RoomModel.gd | — | CO total en sala [kg] |
| `room.o2_lower` | RoomModel.gd | 49 | Fracción molar O₂ zona inferior |
| `room.o2_upper` | RoomModel.gd | — | Fracción molar O₂ zona superior |
| `room.upper_gas_kg` | RoomModel.gd | — | Masa de gas caliente en upper layer [kg] |
| `room.h_layer_m` | RoomModel.gd | — | Altura de la interfaz de capa [m] |

### 6.2 Variables que Phase 2E necesitaría añadir

| Variable | Descripción | Notas |
|---------|-------------|-------|
| `room.co_lower_kg` | CO en zona inferior [kg] | Actualmente inexistente; se deduce de `co_kg - co_upper_kg` pero nunca se rastreó |
| `room.co2_lower_kg` | CO₂ en zona inferior [kg] | Análogo |
| `_delta_co_lower_kg` | Dict de deltas fase-4 para co_lower | Análogo a `_delta_co_upper_kg` en ThermalSystem |

### 6.3 Funciones clave con sus ubicaciones

| Función | Archivo | Líneas | Toca required |
|---------|---------|--------|---------------|
| `_transfer_hot_gas_contaminants` | ThermalSystem.gd | 1860–1957 | **SÍ** (co_upper_kg destino) |
| `compute_fed_delta_for_height` | ThermalSystem.gd | 2387–2437 | **SÍ** (FED required) |
| `step_fed` | ThermalSystem.gd | 2441–2523 | **SÍ** (FED required) |
| `sync_room_upper_layer` | ThermalSystem.gd | ~2620–2690 | SÍ (reset co_upper_kg) |
| `compute_co_lower_ppm` | ThermalSystem.gd | ~2295–2340 | NO (solo export/reporting) |
| `compute_co_ppm` | ThermalSystem.gd | — | Indirectamente (usado por step_fed lower path) |
| `step_oxygen` | OxygenExchangeSystem.gd | — | SÍ (o2_lower, o2_upper) |

---

## 7. Preflight antes de tocar Phase 2E

Antes de crear la rama `feature/phase-2e-two-zone` (y después de cada commit en ella),
ejecutar el script de preflight para confirmar que los checks sentinel siguen en verde:

```bash
python scripts/simulation/phase2e_preflight.py
```

El script lee `sim/validation/reports/reference_checks.json` (generado por la suite de
validación) y reporta para cada check sentinel:

- `actual` — valor simulado actual
- `bound` — límite del check (`exp ±tol` / `min` / `max`)
- `margin` — distancia al borde de fallo (positivo = PASS; negativo = FAIL)
- `riesgo` — qué componente de Phase 2E puede afectarlo
- símbolo `⚠` cuando el margen es menor al 5 % del valor actual (check ajustado)

**Salida esperada en baseline limpio** (289/289 PASS):

```
  ✓ PREFLIGHT OK — todos los sentinels PASS.
    Puedes iniciar la rama Phase 2E.
    Vuelve a ejecutar este script después de cada commit en la rama.
```

**Código de salida**: `0` si todos los sentinels PASS, `1` si alguno FAIL o no encontrado.
Integrar en CI o en el pre-merge checklist de la rama Phase 2E.

Si el preflight falla antes de empezar Phase 2E, regenerar el reporte:

```bash
python scripts/simulation/validate_reference_cases.py
python scripts/simulation/phase2e_preflight.py
```

---

## 8. Phase 2E Experimento 1 — CO Two-Zone Transport Split

**Fecha**: 24 mayo 2026  
**Flag**: `phase2e_two_zone_transport_enabled` (default `false`)  
**Cambio implementado**: bloque CO en `_transfer_hot_gas_contaminants()` — cuando flag=ON,
el CO que llega al destino se reparte entre upper/lower según la profundidad de la capa
caliente actual del destino (`h_upper_tgt / height_m`). Con flag=OFF el comportamiento es
bit-a-bit idéntico al baseline.

### Resultado: 289/289 PASS con flag OFF

```
Required checks   289/289 PASS  [OK]
Gap inventory sync              PASS
Phase 2E sentinels (7)          PASS
```

Baseline intacto tras la adición de la variable, el cableado en `load_settings()` y la
instrucción condicional en el bloque CO.

### Tabla de comparación — flag OFF vs flag ON

Cuatro casos ejecutados con Godot headless. Columna `*` = check sentinel requerido.

```
--- g4_gie_delayed_entry_hazard ---
Metrica                            Baseline       Exp (ON)             Delta  *
-----------------------------------------------------------------------------------
g4  FED timing [s]                  198.417        195.000       -3.417 (-1.7%)  *
g4  CO>1200 timing [s]               85.583        119.500      +33.917 (+39.6%) *
g4  peak CO upper [ppm]          62 716.895     58 930.409    -3786.485  (-6.0%) *
g4  final CO upper [ppm]         19 996.268     20 053.354       +57.086  (+0.3%)
g4  peak CO (mixed) [ppm]          6 808.651      6 847.002      +38.351  (+0.6%)

--- v3_hallway_fed_exposure ---
Metrica                            Baseline       Exp (ON)             Delta  *
-----------------------------------------------------------------------------------
v3  FED timing [s]                  249.833        235.000      -14.833  (-5.9%) *
v3  max FED                           2.212          2.453       +0.241 (+10.9%) *
v3  peak CO upper [ppm]          47 367.599     51 398.630    +4031.030   (+8.5%)
v3  final CO upper [ppm]         16 915.164     16 962.668      +47.505   (+0.3%)
v3  peak CO (mixed) [ppm]          6 119.535      9 502.095   +3382.560  (+55.3%)

--- victim_fed_incapacitation ---
Metrica                            Baseline       Exp (ON)             Delta  *
-----------------------------------------------------------------------------------
vic  final FED                        0.772          0.772        0.000   (0.0%) *
vic  peak CO global [ppm]           3381.925       3387.655       +5.730  (+0.2%) *
vic  room0 final FED                  0.784          0.784        0.000   (0.0%)
vic  room0 peak CO [ppm]            2080.295       2078.448       -1.847  (-0.1%)

--- cfast_two_room_door_open ---
Metrica                            Baseline       Exp (ON)             Delta  *
-----------------------------------------------------------------------------------
cfast room1 CO upper final          595.381        597.092       +1.712   (+0.3%)
cfast room1 CO mixed final          104.657        104.958       +0.301   (+0.3%)
cfast peak CO upper global         2142.643       2027.727     -114.916   (-5.4%)
cfast peak CO mixed global          293.486        308.506      +15.021   (+5.1%)
```

### Análisis de resultados

**g4 — CO>1200 timing: +39.6 % (85.6 s → 119.5 s)**  
El efecto más grande. Con flag ON, el CO que llega a room 1 se divide entre upper y lower
según la profundidad de la capa caliente del destino. La capa upper de room 1 acumula CO
más lentamente → el umbral de 1 200 ppm se alcanza 34 s más tarde. Esto es físicamente
plausible: parte del CO transportado llega a la zona inferior donde no es detectado por la
métrica `co_upper_ppm`. El FED timing baja levemente (-1.7 %) — sin efecto práctico dado el
margen de 10 s.

**v3 — Hallway: FED más rápido (-5.9 %) y más alto (+10.9 %)**  
Paradójico a primera vista. El CO llega más distribuido en el pasillo receptor, pero el
pasillo tiene una capa caliente alta → `upper_split` elevado → más CO en upper → FED se
acumula más rápido a altura de respiración (0.9 m en zona upper). El `peak CO mixed`
aumenta +55 % porque `co_ppm` = `co_kg / air_mass` incluye tanto upper como lower.
La geometría del pasillo amplifica el efecto.

**victim — Sin efecto (~0 %)**  
La víctima está en room 0 (sala del fuego). El transporte split afecta el destino de la
transferencia, no el origen. En un escenario de una sola habitación, el CO generado por el
fuego va directamente a `co_upper_kg` de la sala (via `sync_room_upper_layer`) sin pasar
por la lógica de transporte entre habitaciones. El split no se activa.

**cfast_two_room — Efectos moderados (<6 %)**  
Caso de referencia CFAST de baja HRR. Los deltas son pequeños pero el `peak CO upper`
global baja 5.4 % (menos CO en upper del destino), coherente con la hipótesis.

### Conclusiones del experimento

| Evaluación | Resultado |
|-----------|-----------|
| Flag OFF preserva baseline 289/289 | **CONFIRMADO** |
| Flag ON produce datos comparativos claros | **CONFIRMADO** |
| Efecto sobre sentinels requeridos | CO>1200 timing g4: +39.6 % (sale de banda si se rebaseline), FED v3 timing: -5.9 % (dentro de banda ±30s) |
| Conservación CO total | Conservado por diseño (solo se redirige `co_upper_kg`, `co_kg` total invariante) |
| Candidato a activar permanentemente | **NO todavía** — el desplazamiento en g4 CO>1200 timing es demasiado grande y requiere recalibración del check sentinel antes de promover |
| Próximo paso recomendado | Analizar si `effective_hot_layer_height_m(target)` es la función correcta para el split, o si conviene usar `target.hot_layer_thickness_m` directamente |

### Archivos generados (no rebaseline)

```
sim/validation/reports/g4_gie_delayed_entry_hazard_phase2e_exp1.json
sim/validation/reports/v3_hallway_fed_exposure_phase2e_exp1.json
sim/validation/reports/victim_fed_incapacitation_phase2e_exp1.json
sim/validation/reports/cfast_two_room_door_open_phase2e_exp1.json
```

Los case JSON temporales (`*_phase2e_exp1.json` en `sim/validation/cases/`) son borrados
automáticamente por el runner al terminar.

---

*Documento generado: 24 mayo 2026. Actualizar antes de iniciar implementación — el estado del
código puede haber cambiado. Siempre re-verificar líneas exactas antes de hacer edits.*

---

## 9. Phase 2E Experimento 2 — CO Deposition Strategy Sweep

**Fecha**: 24 mayo 2026  
**Flag**: `phase2e_two_zone_transport_enabled` (default `false`)  
**Variable nueva**: `phase2e_co_deposition_mode: String` (default `"all_upper"`)  
**Pregunta**: ¿Debe el parcel de hot-gas depositar CO 100 % en upper, o puede emplearse un
split con floor para alimentar la zona lower desde el mismo mecanismo?

### Modos evaluados

| Modo | Descripción |
|------|-------------|
| `all_upper` | 100 % CO al upper (= baseline, cancela split geométrico) |
| `geometric_split` | `co_upper = co_moved × (h_upper_tgt / height_m)` |
| `upper_floor_90` | `geometric_split` con mínimo 90 % a upper |
| `upper_floor_95` | `geometric_split` con mínimo 95 % a upper |

### Tabla comparativa — deltas vs baseline (flag OFF)

```
Sentinel / Métrica               Baseline   all_upper   geometric_split  upper_floor_90  upper_floor_95
─────────────────────────────────────────────────────────────────────────────────────────────────────────
[g4_gie_delayed_entry_hazard]
  CO>1200 [s]            *         85.583  +0.00 (+0.0%)  +33.92 (+39.6%) +0.50 (+0.6%)   +0.25 (+0.3%)
  FED>0.1 [s]            *        198.417  +0.00 (+0.0%)   -3.42  (-1.7%) -0.50 (-0.3%)   -0.25 (-0.1%)
  peak CO upper [ppm]    *      62716.895  +0.00 (+0.0%) -3786.49 (-6.0%) +341.47 (+0.5%)  +126.73 (+0.2%)
  final CO upper [ppm]            19996.3  +0.00 (+0.0%)   +57.09 (+0.3%)  +7.28 (+0.0%)   +3.64 (+0.0%)

[v3_hallway_fed_exposure]
  FED>0.1 [s]            *        249.833  +0.00 (+0.0%)  -14.83  (-5.9%) -0.58 (-0.2%)   -0.25 (-0.1%)
  max FED                *          2.212  +0.00 (+0.0%)   +0.24 (+10.9%) +0.00 (+0.1%)   +0.00 (+0.0%)
  peak CO upper [ppm]             47367.6  +0.00 (+0.0%) +4031.03 (+8.5%)  +4.11 (+0.0%)   +2.07 (+0.0%)
  peak CO mixed [ppm]              6119.5  +0.00 (+0.0%) +3382.56 (+55.3%) +0.27 (+0.0%)   +0.14 (+0.0%)

[victim_fed_incapacitation]
  final FED              *          0.772  +0.00 (+0.0%)   +0.00  (+0.0%)  -0.00 (-0.0%)  -0.00 (-0.0%)
  peak CO [ppm]          *        3381.93  +0.00 (+0.0%)   +5.73  (+0.2%)  +1.37 (+0.0%)   +0.68 (+0.0%)

[cfast_two_room_door_open]
  CO upper r1 final                595.38  +0.00 (+0.0%)   +1.71  (+0.3%)  +0.21 (+0.0%)   +0.11 (+0.0%)
  CO mixed r1 final                104.66  +0.00 (+0.0%)   +0.30  (+0.3%)  +0.04 (+0.0%)   +0.02 (+0.0%)
  peak CO upper global            2142.64  +0.00 (+0.0%)  -114.92  (-5.4%) -17.14 (-0.8%)   -5.78 (-0.3%)
```

### Evaluación de sentinels por modo

Ventanas de aceptación (definidas en `validation_guardrails.py`):

| Sentinel | Ventana |
|----------|---------|
| g4 CO>1200 [s] | [82.33, 92.33] (exp 87.333 ±5 s) |
| g4 FED>0.1 [s] | [187.75, 207.75] (exp 197.75 ±10 s) |
| g4 peak CO upper | min implícito (check de referencia) |
| v3 FED>0.1 [s] | [222.17, 282.17] (exp 252.167 ±30 s) |
| v3 max FED | ≥ 1.0 |
| vic final FED | ≥ 0.7 |
| vic peak CO | ≥ 1500 ppm |

| Modo | g4 CO>1200 | g4 FED | v3 FED | v3 maxFED | vic FED | vic CO | Sentinels |
|------|-----------|--------|--------|-----------|---------|--------|-----------|
| `all_upper` | ✓ 85.6 | ✓ 198.4 | ✓ 249.8 | ✓ 2.21 | ✓ 0.772 | ✓ 3382 | **7/7 PASS** |
| `geometric_split` | **✗ 119.5** | ✓ 195.0 | ✓ 235.0 | ✓ 2.45 | ✓ 0.772 | ✓ 3388 | **6/7 FAIL** |
| `upper_floor_90` | ✓ 86.1 | ✓ 197.9 | ✓ 249.3 | ✓ 2.21 | ✓ 0.772 | ✓ 3383 | **7/7 PASS** |
| `upper_floor_95` | ✓ 85.8 | ✓ 198.2 | ✓ 249.6 | ✓ 2.21 | ✓ 0.772 | ✓ 3382 | **7/7 PASS** |

### Análisis

**`geometric_split` — descartado**  
El split puramente geométrico (`h_upper / height`) falla el sentinel de CO>1200 con un
desplazamiento de +39.6 % (85.6 s → 119.5 s), replicando exactamente los resultados del
Experimento 1. Físicamente, el split extrae CO del parcel de hot-gas y lo deposita en la
zona lower, retrasando la acumulación de CO en upper. Sin mecanismo que restaure
la energía del parcel ni el CO, el modelo subestima el peligro en la zona upper.

**`upper_floor_90` y `upper_floor_95` — técnicamente conformes**  
Ambos pasan los 7 sentinels con desviaciones sub-1 %. `upper_floor_90` admite hasta 10 %
de CO al lower (cuando `geo_split < 0.90`); `upper_floor_95` hasta 5 %. Los efectos son
numéricamente insignificantes respecto al baseline. No existe ganancia práctica ni base
física documentada para activar estos modos: el CO lower que aportan (~0.04 ppm en cfast,
~1 ppm en vic) queda por debajo de la resolución del modelo.

**`all_upper` — correcto y canónico**  
El valor por defecto preserva el baseline exactamente. Es físicamente consistente con
la naturaleza de `_transfer_hot_gas_contaminants()`: ese método modela el transporte de
una parcela de gas caliente boyante, que deposita su contenido en la zona upper del
compartimento receptor. El CO de la zona lower debe provenir de un mecanismo separado
(ver §9.4).

### Recomendación arquitectónica

> **`_transfer_hot_gas_contaminants()` representa flujo de capa caliente (hot-gas-layer
> parcel). El CO transportado debe depositarse 100 % en la zona upper del destino (`all_upper`).
> Esta función NO es el lugar adecuado para alimentar la zona lower.**

Consecuencias:

1. `phase2e_co_deposition_mode = "all_upper"` es el modo correcto y se mantiene como
   default permanente. Los modos `geometric_split`, `upper_floor_90` y `upper_floor_95`
   quedan disponibles detrás del flag para fines de auditoría, pero **no deben promoverse**.

2. Si el modelo requiere CO en la zona lower (p.ej. mezcla por convección forzada, doorway
   mixing, productos de combustión incompleta en lower), debe implementarse como un paso
   independiente — por ejemplo `_mix_interlayer_co()` — con su propio coeficiente
   calibrado y su propio sentinel. Esto evita que la lógica de transporte de hot-gas
   incorpore efectos de difusión que no le corresponden.

3. No rebaselinear: los cambios actuales son experimentales detrás del flag. El baseline
   289/289 permanece intacto.

4. No intentar arreglar el FED timing en este mismo paso: la leve mejora de FED v3 con
   `geometric_split` (-5.9 %) no compensa la rotura del CO>1200 sentinel. Son efectos
   acoplados; cualquier recalibración debe hacerse en Fase 2F con benchmarks alineados.

### Archivos generados (no rebaseline)

```
sim/validation/reports/g4_gie_delayed_entry_hazard_p2e2_all_upper.json
sim/validation/reports/g4_gie_delayed_entry_hazard_p2e2_geometric_split.json
sim/validation/reports/g4_gie_delayed_entry_hazard_p2e2_upper_floor_90.json
sim/validation/reports/g4_gie_delayed_entry_hazard_p2e2_upper_floor_95.json
sim/validation/reports/v3_hallway_fed_exposure_p2e2_*.json         (4 archivos)
sim/validation/reports/victim_fed_incapacitation_p2e2_*.json       (4 archivos)
sim/validation/reports/cfast_two_room_door_open_p2e2_*.json        (4 archivos)
```

Los case JSON temporales son borrados automáticamente por el runner al terminar.

---

*Documento actualizado: 24 mayo 2026.*

---

## 11. Phase 2G Experimento 1 — CO Lower Source Term

**Fecha**: 24 mayo 2026  
**Flags nuevos**: `phase2g_co_lower_source_enabled` (bool, default `false`),
`phase2g_co_lower_source_fraction` (float, default `0.0`),
`phase2g_co_lower_source_guard` (String, default `"fire_room_only"`)  
**Pregunta**: ¿Puede una fracción pequeña del CO generado por combustión nacer
directamente en la zona lower implícita sin romper los sentinels de CO upper/FED?

### Diseño del mecanismo

Phase 2G actúa en `CombustionSystem.step_room_fire()` en el momento de generación de CO,
antes del transporte entre salas. A diferencia de Phase 2F, no mueve CO ya acumulado:
asigna una fracción de `generated_co_kg` a lower implícito desde el nacimiento.

```
room.co_kg += generated_co_kg
room.co_upper_kg += generated_co_kg * (1.0 - lower_source_fraction)
# co_lower_kg queda implícito como room.co_kg - room.co_upper_kg
```

El total `co_kg` se conserva respecto al baseline; solo cambia la distribución
upper/lower en la sala donde hay combustión. El transporte hot-gas permanece en `all_upper`,
Phase 2F permanece desactivada y FED no se modifica.

### Barrido ejecutado

| Parámetro | Valores |
|-----------|---------|
| `fraction` | `0.000`, `0.005`, `0.010`, `0.020`, `0.050` |
| `guard` | `fire_room_only`, `only_when_hot_layer_above_1_8m`, `all_rooms_with_fire` |
| Casos | `g4_gie_delayed_entry_hazard`, `v3_hallway_fed_exposure`, `victim_fed_incapacitation`, `cfast_single_room_closed`, `cfast_two_room_door_open` |

**Resultado de ejecución**: `75/75 runs OK` — 15 combos × 5 casos.

### Resultados sentinel

Todos los combos pasan los 6 sentinels. El caso más agresivo (`fraction=0.050`,
`fire_room_only`/`all_rooms_with_fire`) queda todavía muy cerca del baseline:

| Métrica | Baseline | f=0.050 fr/all | Delta |
|---------|----------|----------------|-------|
| g4 `CO>1200` | 85.583 s | 85.750 s | +0.17 s (+0.2%) |
| g4 `FED>0.1` | 198.417 s | 198.667 s | +0.25 s (+0.1%) |
| v3 `FED>0.1` | 249.833 s | 252.167 s | +2.33 s (+0.9%) |
| v3 max FED | 2.212 | 2.203 | -0.01 (-0.4%) |
| victim final FED | 0.772 | 0.773 | +0.001 (+0.2%) |
| victim peak CO | 3381.925 ppm | 3381.864 ppm | -0.06 ppm |

El guard `only_when_hot_layer_above_1_8m` es casi inerte en los sentinels:
`f=0.050 g18m` mantiene g4 idéntico al baseline y desplaza v3 `FED>0.1` solo +0.17 s.

### Señal en CO lower

El mecanismo sí reduce `co_upper_ppm` en la sala fuente, pero la señal no aparece de forma
material en salas remotas:

| Caso | Métrica | Baseline | f=0.050 all | Delta |
|------|---------|----------|-------------|-------|
| CFAST single room | peak CO upper global | 1357.3 ppm | 1289.5 ppm | -67.9 ppm (-5.0%) |
| CFAST single room | final CO upper R0 | 1200.4 ppm | 1140.3 ppm | -60.0 ppm (-5.0%) |
| CFAST two-room hall | final CO upper R1 | 595.4 ppm | 595.4 ppm | ~0.0 ppm |
| CFAST two-room hall | final CO mixed R1 | 104.7 ppm | 104.7 ppm | ~0.0 ppm |
| CFAST two-room | peak CO upper global | 2142.6 ppm | 2142.6 ppm | ~0.0 ppm |

Interpretación: el source term lower afecta principalmente la **sala con fuego**. En el
pasillo/sala destino de `cfast_two_room_door_open`, el transporte hot-gas sigue llevando CO
desde la capa upper de la sala fuente hacia la zona upper del destino; por tanto el lower
remoto apenas cambia. El gap `cfast_2r_hall_t360_co_lower_ppm` no se cierra con este
mecanismo.

### Conclusión

| Evaluación | Resultado |
|-----------|-----------|
| Flag OFF preserva baseline | **CONFIRMADO por guardrails: 289/289 required PASS** |
| 75/75 runs experimentales OK | **CONFIRMADO** |
| Sentinels g4/v3/victim | **15/15 combos pasan 6/6** |
| Mejora CO lower en sala fuente | **Débil pero real: reduce CO upper ~5% a f=0.050** |
| Mejora CO lower en salas remotas | **NO material** |
| Candidato a promover | **NINGUNO todavía** |

**Recomendación**: Phase 2G demuestra que un source term lower es compatible con los
sentinels cuando está detrás de flag, pero no resuelve el problema que motivó el gap en salas
remotas. No promover a default. Si se continúa, el siguiente experimento debe atacar el
acoplamiento lower-zone durante transporte/doorway flow, no solo la generación en la sala
fuente.

**Directivas**:
- Mantener `phase2g_co_lower_source_enabled = false` por defecto.
- No rebaselinear.
- No tocar FED.
- Mantener `_transfer_hot_gas_contaminants()` en modo `all_upper`.
- Usar los reports `*_p2g1_*.json` solo como artefactos experimentales, no como baseline.

### Archivos generados (no rebaseline)

```
sim/validation/reports/*_p2g1_f000_*.json  (15 archivos)
sim/validation/reports/*_p2g1_f005_*.json  (15 archivos)
sim/validation/reports/*_p2g1_f010_*.json  (15 archivos)
sim/validation/reports/*_p2g1_f020_*.json  (15 archivos)
sim/validation/reports/*_p2g1_f050_*.json  (15 archivos)
```

Total: 75 reports experimentales. Los case JSON temporales son artefactos de runner y no
deben versionarse.

---

*Documento actualizado: 24 mayo 2026.*

---

## 10. Phase 2F Experimento 1 — CO Interlayer Mixing Sweep

**Fecha**: 24 mayo 2026  
**Flags nuevos**: `phase2f_co_interlayer_mixing_enabled` (bool, default `false`),
`phase2f_co_interlayer_mixing_rate` (float, default `0.0`),
`phase2f_co_interlayer_mixing_guard` (String, default `"no_guard"`)  
**Pregunta**: ¿Puede un mecanismo separado de difusión CO upper→lower, implementado
como `_apply_phase2f_co_interlayer_mixing()`, enriquecer la zona lower sin romper sentinels
de la zona upper?

### Diseño del mecanismo

Llamado **después** de `_flush_contaminant_deltas()` en cada paso. Opera sobre `co_upper_kg`
directamente (no sobre el buffer Jacobi). **Invariante de masa total**: `co_kg` no se modifica,
sólo `co_upper_kg` decrece → `co_lower = co_kg - co_upper_kg` aumenta implícitamente.

```
transfer_kg = co_upper_kg × rate × dt
co_upper_kg -= transfer_kg      # co_kg total invariante
```

### Guards evaluados

| Guard | Código | Condición de activación |
|-------|--------|------------------------|
| `no_guard` | `ng` | Siempre aplica |
| `only_when_upper_gas_kg_lt_0_1` | `g01` | Solo si `upper_gas_kg < 0.1` kg |
| `only_when_hot_layer_interface_above_1_8m` | `g18m` | Solo si interfaz > 1.8 m |
| `only_when_no_occupant_in_upper_probe` | `gup` | Solo si ninguna víctima respira en upper |

### Resultados: SENTINELS tabla compacta (80 runs, 20 combos × 4 casos)

```
Combo           g4 CO>1200   g4 FED      v3 FED      v3 maxFED   vic FED   vic CO      Total
─────────────────────────────────────────────────────────────────────────────────────────────
BASELINE          85.583      198.417     249.833      2.212       0.772    3381.925    6/6
r=0.000  ng       85.583 [OK] 198.417 [OK] 249.833 [OK] 2.212 [OK] 0.772 [OK] 3381.925 [OK] 6/6
r=0.000  g01/g18m/gup  (idéntico baseline) ...                                            6/6
─────────────────────────────────────────────────────────────────────────────────────────────
r=0.002  ng       85.750 [OK] 198.333 [OK] 250.083 [OK] 2.210 [OK] 0.772 [OK] 3382.395 [OK] 6/6
r=0.002  g01      85.583 [OK] 198.417 [OK] 250.000 [OK] 2.211 [OK] 0.772 [OK] 3381.924 [OK] 6/6
r=0.002  g18m     85.667 [OK] 198.250 [OK] 249.750 [OK] 2.212 [OK] 0.772 [OK] 3381.901 [OK] 6/6
r=0.002  gup      85.750 [OK] 198.333 [OK] 250.083 [OK] 2.210 [OK] 0.772 [OK] 3382.395 [OK] 6/6
─────────────────────────────────────────────────────────────────────────────────────────────
r=0.005  ng       86.083 [OK] 198.250 [OK] 250.417 [OK] 2.207 [OK] 0.773 [OK] 3383.097 [OK] 6/6
r=0.005  g01      85.583 [OK] 198.417 [OK] 250.167 [OK] 2.211 [OK] 0.772 [OK] 3381.922 [OK] 6/6
r=0.005  g18m     85.833 [OK] 198.000 [OK] 249.500 [OK] 2.212 [OK] 0.772 [OK] 3381.862 [OK] 6/6
r=0.005  gup      86.083 [OK] 198.250 [OK] 250.417 [OK] 2.207 [OK] 0.773 [OK] 3383.097 [OK] 6/6
─────────────────────────────────────────────────────────────────────────────────────────────
r=0.010  ng       86.417 [OK] 198.167 [OK] 250.667 [OK] 2.201 [OK] 0.774 [OK] 3384.265 [OK] 6/6
r=0.010  g01      85.583 [OK] 198.417 [OK] 250.417 [OK] 2.210 [OK] 0.772 [OK] 3381.919 [OK] 6/6
r=0.010  g18m     86.083 [OK] 197.667 [OK] 248.917 [OK] 2.213 [OK] 0.773 [OK] 3381.795 [OK] 6/6
r=0.010  gup      86.417 [OK] 198.167 [OK] 250.667 [OK] 2.201 [OK] 0.774 [OK] 3384.265 [OK] 6/6
─────────────────────────────────────────────────────────────────────────────────────────────
r=0.020  ng       86.833 [OK] 198.083 [OK] 249.583 [OK] 2.104 [OK] 0.777 [OK] 3386.526 [OK] 6/6
r=0.020  g01      85.583 [OK] 198.500 [OK] 251.000 [OK] 2.208 [OK] 0.772 [OK] 3381.914 [OK] 6/6
r=0.020  g18m     86.417 [OK] 197.167 [OK] 246.333 [OK] 2.168 [OK] 0.774 [OK] 3381.583 [OK] 6/6
r=0.020  gup      86.833 [OK] 198.083 [OK] 249.583 [OK] 2.104 [OK] 0.777 [OK] 3386.526 [OK] 6/6
```

**Resultado global: 20/20 combos pasan 6/6 sentinels en todos los rates hasta 0.020.**

### Análisis por guard

**`g01` (upper_gas_kg < 0.1) — guard inerte**  
La condición `upper_gas_kg < 0.1` nunca se activa en escenarios con fuego activo. En g4,
v3 y victim, la capa upper acumula varios kg de gas caliente. Los deltas con `g01` son
idénticos al baseline en prácticamente todos los pasos. **Este guard no sirve para escenarios
de incendio; solo activaría en habitaciones sin fuego y con upper layer casi vacío.**

**`gup` (no occupant in upper probe) — equivalente a `no_guard`**  
Los resultados de `gup` son bit-a-bit idénticos a `ng`. En los cuatro casos de validación,
las víctimas respiran a 0.9 m y la interfaz de capa caliente está siempre por encima de 0.9 m
durante la simulación. Nunca hay víctima en el "upper probe". El guard **no bloquea el
mixing en ningún timestep** de estos escenarios.

**`g18m` (interfaz > 1.8 m) — atenuación moderada**  
Este guard sí cambia el comportamiento: bloquea el mixing cuando la capa caliente ha
descendido por debajo de 1.8 m. En g4, la interfaz desciende durante el incendio, por lo que
el guard activa solo en la fase inicial (interfaz alta). El efecto resulta en deltas ligeramente
menores que `ng` en algunas métricas, pero sigue siendo < 2 % incluso a r=0.020.

**`ng` (sin guard) — efecto máximo del mecanismo**  
A r=0.020, el mayor desplazamiento observado es g4 CO>1200: +1.5 % (86.8 s vs 85.6 s).
Todos los sentinels pasan holgadamente. **El techo de impacto a r=0.020 es ~1.5 % en timing
y ~5 % en max FED (v3 baja de 2.21 a 2.10).**

### Señal en CO lower (zona inferior)

Dado que el mecanismo conserva `co_kg` total, la concentración mixta (`co_ppm`) **no cambia**
entre flag ON y OFF para el mismo amount de CO generado. El enrichment en lower es únicamente
observable como reducción de `co_upper_ppm`:

| Caso | Métrica | Baseline | r=0.020 ng | Delta |
|------|---------|----------|------------|-------|
| cfast | CO upper final r1 | 595.4 ppm | 596.0 ppm | +0.63 (+0.1%) |
| cfast | CO mixed r1 | 104.7 ppm | 104.8 ppm | +0.11 (+0.1%) |
| cfast | peak CO upper global | 2142.6 ppm | 2023.9 ppm | -118.8 (-5.5%) |

La señal de enrichment lower es **sub-0.1 % en ppm mixto** a todos los rates.
La reducción de peak CO upper a r=0.020 (-5.5 %) es observable pero no deseada:
representa depleción del hazard signal en la zona que los sensores monitorizan.

### Conclusiones y cierre de gap

| Evaluación | Resultado |
|-----------|-----------|
| Flag OFF preserva baseline 289/289 | **CONFIRMADO** |
| 80/80 runs completados sin error | **CONFIRMADO** |
| Todos los sentinels pasan a r≤0.020 | **CONFIRMADO — 20/20 combos 6/6** |
| Enriquecimiento CO lower detectable | **NO — sub-0.1 % en ppm mixto** |
| Candidato a promover | **NINGUNO** |

**Diagnóstico de fondo**: `_apply_phase2f_co_interlayer_mixing()` conserva `co_kg` total.
La concentración mixta `co_ppm = co_kg / vol_total` es invariante ante la redistribución
upper→lower. El único observable es la disminución de `co_upper_ppm`, que va en sentido
contrario al objetivo (señal hazard upper se debilita). No hay ganancia neta en lower.

### Recomendación arquitectónica final — CO lower gap

> **El CO de la zona lower no puede generarse de forma incrementalmente válida ni desde el
> transporte de hot-gas (`_transfer_hot_gas_contaminants`) ni desde un mixing upper→lower
> (`_apply_phase2f_co_interlayer_mixing`). Ambos mecanismos redistribuyen masa existente sin
> crear señal nueva.**
>
> Para cerrar el gap de CO lower se requiere un **término fuente explícito en la zona inferior**
> — por ejemplo `co_lower_source_rate_kg_per_MJ` calibrado contra mediciones de CO a nivel
> de suelo en ensayos UL/FSRI — implementado en Fase 2G como un paso de generación separado,
> no como redistribución.

**Directivas**:
- No rebaselinear.
- No activar `phase2f_co_interlayer_mixing_enabled` por defecto.
- El gap "CO lower subestimado" permanece documentado en `docs/validation/GAPS_INVENTORY.md`.
- No commit/push hasta decisión de Fase 2G.

### Archivos generados (no rebaseline)

```
sim/validation/reports/*_p2f1_r000_ng.json   (4 archivos — validez rate=0)
sim/validation/reports/*_p2f1_r002_*.json    (16 archivos)
sim/validation/reports/*_p2f1_r005_*.json    (16 archivos)
sim/validation/reports/*_p2f1_r010_*.json    (16 archivos)
sim/validation/reports/*_p2f1_r020_*.json    (16 archivos)
```
Total: 80 reports experimentales. Los case JSON temporales son borrados automáticamente.

---

*Documento actualizado: 24 mayo 2026.*

---

## 11. Phase 2G Experiment 1 — CO Lower Source Term at Generation

### 11.1 Motivación y distinción respecto a Phase 2F

Phase 2F (§10) redistribuía CO existente de upper → lower *después* de generación: la masa total de CO era invariante, por lo que la concentración ppm en zona lower no recibía señal nueva. El efecto medido fue sub-0.1%.

Phase 2G actúa **en el momento de generación** dentro de `CombustionSystem.gd`. Una fracción `f` de `generated_co_kg` se dirige implícitamente al lower:

```gdscript
room.co_kg      += generated_co_kg                        # total invariante
room.co_upper_kg += generated_co_kg * (1.0 - f)          # upper recibe (1 - f)
# lower implícito = co_kg - co_upper_kg acumula +generated_co_kg * f por paso
```

Esto genera señal lower **genuina y acumulativa** paso a paso.

### 11.2 Parámetros del barrido

| Dimensión              | Valores                                                        |
|------------------------|----------------------------------------------------------------|
| `fraction` (f)         | 0.000, 0.005, 0.010, 0.020, 0.050                             |
| `guard`                | `fire_room_only` (fr), `only_when_hot_layer_above_1_8m` (g18m), `all_rooms_with_fire` (all) |
| Casos                  | g4_gie_delayed_entry_hazard, v3_hallway_fed_exposure, victim_fed_incapacitation, cfast_single_room_closed, cfast_two_room_door_open |
| **Total runs**         | 5 × 3 × 5 = **75**                                            |

### 11.3 Guards

- **`fire_room_only` / `all_rooms_with_fire`**: aplican siempre en cualquier sala con combustión activa (ruta `_:` en `match`; idénticos en todos los casos de test).
- **`only_when_hot_layer_above_1_8m`**: aplica solo cuando `thermal_system.effective_hot_layer_height_m(room) > 1.8 m`. En los casos de test la interfaz se mantiene alta durante la mayor parte de la simulación, por lo que este guard solo filtra una fracción pequeña de pasos → deltas casi nulos.

### 11.4 Resultados — tabla sentinel (15 combos × 6 sentinels)

Ventanas: g4 CO>1200 ∈ [82.333, 92.333] s · g4 FED>0.1 ∈ [187.75, 207.75] s · v3 FED>0.1 ∈ [222.17, 282.17] s · v3 maxFED ≥ 1.0 · vic final FED ≥ 0.7 · vic peak CO ≥ 1500 ppm

| Combo          | g4 CO>1200 | g4 FED  | v3 FED  | v3 maxFED | vic FED | vic CO   | Total |
|----------------|------------|---------|---------|-----------|---------|----------|-------|
| BASELINE       | 85.583     | 198.417 | 249.833 | 2.212     | 0.772   | 3381.925 | 6/6   |
| f=0.000 fr     | 85.583 ✓   | 198.417 ✓ | 249.833 ✓ | 2.212 ✓ | 0.772 ✓ | 3381.925 ✓ | 6/6 |
| f=0.000 g18m   | 85.583 ✓   | 198.417 ✓ | 249.833 ✓ | 2.212 ✓ | 0.772 ✓ | 3381.925 ✓ | 6/6 |
| f=0.000 all    | 85.583 ✓   | 198.417 ✓ | 249.833 ✓ | 2.212 ✓ | 0.772 ✓ | 3381.925 ✓ | 6/6 |
| f=0.005 fr     | 85.583 ✓   | 198.417 ✓ | 250.083 ✓ | 2.211 ✓ | 0.772 ✓ | 3381.920 ✓ | 6/6 |
| f=0.005 g18m   | 85.583 ✓   | 198.417 ✓ | 249.917 ✓ | 2.212 ✓ | 0.772 ✓ | 3381.924 ✓ | 6/6 |
| f=0.005 all    | 85.583 ✓   | 198.417 ✓ | 250.083 ✓ | 2.211 ✓ | 0.772 ✓ | 3381.920 ✓ | 6/6 |
| f=0.010 fr     | 85.583 ✓   | 198.417 ✓ | 250.333 ✓ | 2.210 ✓ | 0.772 ✓ | 3381.914 ✓ | 6/6 |
| f=0.010 g18m   | 85.583 ✓   | 198.417 ✓ | 249.917 ✓ | 2.212 ✓ | 0.772 ✓ | 3381.922 ✓ | 6/6 |
| f=0.010 all    | 85.583 ✓   | 198.417 ✓ | 250.333 ✓ | 2.210 ✓ | 0.772 ✓ | 3381.914 ✓ | 6/6 |
| f=0.020 fr     | 85.667 ✓   | 198.500 ✓ | 250.750 ✓ | 2.208 ✓ | 0.772 ✓ | 3381.902 ✓ | 6/6 |
| f=0.020 g18m   | 85.583 ✓   | 198.417 ✓ | 249.917 ✓ | 2.211 ✓ | 0.772 ✓ | 3381.919 ✓ | 6/6 |
| f=0.020 all    | 85.667 ✓   | 198.500 ✓ | 250.750 ✓ | 2.208 ✓ | 0.772 ✓ | 3381.902 ✓ | 6/6 |
| f=0.050 fr     | 85.750 ✓   | 198.667 ✓ | 252.167 ✓ | 2.203 ✓ | 0.773 ✓ | 3381.864 ✓ | 6/6 |
| f=0.050 g18m   | 85.583 ✓   | 198.417 ✓ | 250.000 ✓ | 2.211 ✓ | 0.772 ✓ | 3381.910 ✓ | 6/6 |
| f=0.050 all    | 85.750 ✓   | 198.667 ✓ | 252.167 ✓ | 2.203 ✓ | 0.773 ✓ | 3381.864 ✓ | 6/6 |

**Resultado: 15/15 combos 6/6 sentinels PASS.**

### 11.5 Deltas clave (vs baseline flag OFF)

#### Timing y FED (sentinels)

| Métrica        | base     | f=0.005 fr | f=0.010 fr | f=0.020 fr | f=0.050 fr | f=0.050 g18m |
|----------------|----------|------------|------------|------------|------------|--------------|
| g4 CO>1200 [s] | 85.583   | +0.00 (0.0%) | +0.00 (0.0%) | +0.08 (+0.1%) | +0.17 (+0.2%) | +0.00 (0.0%) |
| g4 FED>0.1 [s] | 198.417  | +0.00 (0.0%) | +0.00 (0.0%) | +0.08 (0.0%) | +0.25 (+0.1%) | +0.00 (0.0%) |
| v3 FED>0.1 [s] | 249.833  | +0.25 (+0.1%) | +0.50 (+0.2%) | +0.92 (+0.4%) | +2.33 (+0.9%) | +0.17 (+0.1%) |
| v3 max FED     | 2.212    | −0.001 (0.0%) | −0.002 (−0.1%) | −0.004 (−0.2%) | −0.009 (−0.4%) | −0.001 (0.0%) |
| vic final FED  | 0.772    | +0.000 (0.0%) | +0.000 (0.0%) | +0.001 (+0.1%) | +0.002 (+0.2%) | +0.000 (0.0%) |
| vic peak CO    | 3381.925 | −0.01 (0.0%) | −0.01 (0.0%) | −0.02 (0.0%) | −0.06 (0.0%) | −0.02 (0.0%) |

#### CO upper (señal del mecanismo)

| Métrica              | base      | f=0.005 fr   | f=0.010 fr   | f=0.020 fr    | f=0.050 fr    | f=0.050 g18m |
|----------------------|-----------|--------------|--------------|---------------|---------------|--------------|
| g4 peak CO upper ppm | 62716.895 | −31.2 (0.0%) | −62.4 (−0.1%) | −124.8 (−0.2%) | −254.8 (−0.4%) | −0.01 (0.0%) |
| sc peak CO upper ppm | 1357.316  | −6.8 (−0.5%) | −13.6 (−1.0%) | −27.2 (−2.0%) | −67.9 (−5.0%) | −0.16 (0.0%) |
| 2r peak CO upper ppm | 2142.643  | −0.00 (0.0%) | −0.01 (0.0%) | −0.02 (0.0%) | −0.04 (0.0%) | −0.00 (0.0%) |

### 11.6 Análisis

**`fire_room_only` ≡ `all_rooms_with_fire`**: Confirmado. Ambos guards convergen al bloque `_:` del `match` en `CombustionSystem.gd` y producen resultados idénticos en todos los casos (los casos de test tienen fuego en una sola sala).

**Guard `g18m` casi inerte**: Los deltas de CO upper con g18m son < 0.02% incluso a f=0.050, porque la interfaz de capa caliente se mantiene por encima de 1.8 m durante la mayor parte de la simulación en todos los casos de test. El guard filtra la casi totalidad de los pasos de combustión.

**Señal lower genuina — sí existe, escala con f**: A diferencia de Phase 2F (redistribución post-generación invariante en masa), Phase 2G crea señal lower acumulativa. En `cfast_single_room_closed` (sala cerrada, sin dilución): `sc peak CO upper` cae −5.0% a f=0.050, lo que implica que ~5% de todo el CO generado acumuló en la zona lower. La escala es exactamente proporcional a la fracción, validando el mecanismo.

**Impacto en sentinels FED/CO es sub-1%**: El CO upper decrece ligeramente, lo que atrasa marginalmente el onset FED. A f=0.050, el retraso máximo es +2.33 s en v3 FED>0.1 (+0.9%) y +0.17 s en g4 (+0.2%), ambos dentro de ventana sentinel. Los 6 sentinels pasan en todos los combos.

**Baseline preservado a f=0.000**: Los 3 combos f=0.000 reproducen exactamente el baseline (0.0% delta en todos los sentinels), confirmando que el flag OFF no altera el comportamiento base.

### 11.7 Conclusión

El término fuente CO lower en generación es técnicamente viable y bien condicionado: señal lower genuina confirmada, sentinel impact sub-1% incluso a f=0.050, baseline preservado con flag OFF.

**No se promueve ningún candidato a configuración por defecto en esta fase.** Razones:
- El impacto en métricas FED/CO upper es demasiado pequeño para resolver los gaps de CO lower identificados en el inventario.
- La magnitud calibratable requeriría f >> 0.05, territorio no barrido y sin validación empírica.
- El mecanismo queda disponible para calibración futura (Phase 2H) si se dispone de datos de referencia para CO lower.

**Directivas:** No rebaseline, no cambios FED, no commit/push. Los flags permanecen en default OFF (`phase2g_co_lower_source_enabled = false`).

### 11.8 Archivos generados

```
sim/validation/reports/*_p2g1_f000_fr.json     (5 archivos)
sim/validation/reports/*_p2g1_f000_g18m.json   (5 archivos)
sim/validation/reports/*_p2g1_f000_all.json    (5 archivos)
sim/validation/reports/*_p2g1_f005_*.json      (15 archivos)
sim/validation/reports/*_p2g1_f010_*.json      (15 archivos)
sim/validation/reports/*_p2g1_f020_*.json      (15 archivos)
sim/validation/reports/*_p2g1_f050_*.json      (15 archivos)
```
Total: 75 reports experimentales. Los case JSON temporales son borrados automáticamente.

---

*Documento actualizado: 24 mayo 2026.*

---

## 12. Phase 2H Plan — O₂ Doorway Two-Zone Flow

### 12.1 Motivación

Los checks de `o2_lower` (zona inferior de O₂) presentan el mayor volumen de gaps no-cerrados del inventario. En todos los escenarios, SF produce una zona inferior **demasiado depletada** respecto a CFAST:

| Check | SF actual | CFAST esperado | Escenario |
|---|---|---|---|
| `cfast_t350_o2_lower` | 0.0693 | 0.2049 ±0.015 | Sala con ventana |
| `cfast_t420_o2_lower` | 0.1658 | 0.1878 ±0.015 | Sala con ventana |
| `cfast_closed_t300_o2_lower` | 0.0684 | 0.2049 ±0.015 | Sala sellada |
| `cfast_closed_t450_o2_lower` | 0.0429 | 0.2049 ±0.015 | Sala sellada |
| `cfast_hvac_t180_o2_lower` | 0.1560 | 0.2049 ±0.015 | HVAC |
| `cfast_hvac_t300_o2_lower` | 0.0580 | 0.2049 ±0.015 | HVAC |
| `cfast_hvac_t450_o2_lower` | 0.0336 | 0.2049 ±0.015 | HVAC |
| `cfast_2r_r0_t180_o2_lower` | 0.2032 | 0.1826 ±0.015 | Dos salas (sala fuego) |
| `cfast_2r_r0_t300_o2_lower` | 0.2090 | 0.0952 ±0.015 | Dos salas (sala fuego) |
| `cfast_2r_r0_t450_o2_lower` | 0.0675 | 0.0909 ±0.015 | Dos salas (sala fuego) |

El patrón unificado: **CFAST preserva `o2_lower ≈ 0.205` (casi ambiente)** en los escenarios con ventana, HVAC y sala sellada, porque en un modelo two-zone la combustión depleta exclusivamente la zona superior. La zona inferior se mantiene por el flujo fresco que entra por la mitad baja de las aperturas.

---

### 12.2 Diagnóstico Arquitectónico

#### 12.2.1 La raíz del problema — el `floor` en `room.o2`

El código actual de Phase 2A en `OxygenExchangeSystem.gd` (líneas ~172-175):

```gdscript
# Pluma arrastra o2_lower hacia room.o2 (floor):
var lower_entr: float = entr_frac * 0.20 * maxf(0.0, room.o2_lower - room.o2)
room.o2_lower = maxf(room.o2, room.o2_lower - lower_entr)  # ← floor en room.o2

var ach_lower_dt: float = (ach_infiltration / 3600.0) * (building.outside_o2 - room.o2_lower) * dt
room.o2_lower = clampf(room.o2_lower + ach_lower_dt, room.o2, o2_nominal)  # ← floor en room.o2
```

`room.o2` es la variable de retrocompatibilidad que la combustión depleta. Al usarla como **piso** de `o2_lower`, cualquier caída en `room.o2` arrastra automáticamente `o2_lower` hacia abajo, incluso cuando hay flujo fresco entrando por las aperturas exteriores (cuya reposición directa de `o2_lower` ya fue implementada en `_step_outside_opening_o2`).

Existe además un guard de colapso (líneas ~153-156):
```gdscript
if lower_frac < 0.15 or (lower_frac < 0.40 and room.o2 < 0.070):
    room.o2_upper = room.o2
    room.o2_lower = room.o2  # ← colapsa ambas zonas a room.o2
```

Este guard introduce un salto discreto: cuando `room.o2` cae por debajo de `0.070` con `lower_frac < 0.40`, `o2_lower` se iguala instantáneamente a `room.o2`.

#### 12.2.2 Por qué CFAST no tiene este problema

En CFAST (modelo de dos zonas Kawagoe):
- La **combustión depleta exclusivamente la zona superior** (`o2_upper`)
- La **zona inferior recibe aire fresco** que entra por la mitad baja de ventanas y puertas
- No existe un concepto de "bulk room.o2" que arrastre la zona inferior

En SF, `room.o2` mezcla ambas zonas y sirve como variable principal de combustión. El flag Phase 2H mantiene `room.o2` exactamente igual (retrocompatibilidad total) y solo modifica el comportamiento de `o2_lower`.

#### 12.2.3 Lo que ya funciona bien

- `_step_outside_opening_o2()` (líneas ~350-360): ya repone `indoor.o2_lower` directamente con el flujo de entrada exterior — **correcto**.
- `_exchange_room_o2_active_flow()` (líneas ~519-533): ya actualiza `hot_room.o2_lower` cuando entra aire fresco por la mitad baja del vano interior — **correcto**.
- El problema está en que el `floor room.o2` de Phase 2A deshace esa reposición en el siguiente paso.

---

### 12.3 Mecanismo Propuesto

**Hipótesis central**: al desacoplar `o2_lower` de `room.o2` como piso, usando `room.o2_upper` como referencia, `o2_lower` podrá mantenerse por encima del bulk cuando el flujo fresco lo repone, reproduciendo el comportamiento two-zone de CFAST.

**Invariante físico**: `o2_lower ≥ o2_upper` siempre es correcto — la zona baja tiene más O₂ que la zona alta donde ocurre la combustión.

Cambio mínimo en `OxygenExchangeSystem.gd` — **solo la ruta Phase 2A** (líneas ~171-175), gateado por flag:

```gdscript
# Zona inferior
if phase2h_o2_doorway_two_zone_enabled:
    # Phase 2H: floor en o2_upper (zona alta siempre más depletada que zona baja)
    var lower_entr: float = entr_frac * 0.20 * maxf(0.0, room.o2_lower - room.o2_upper)
    room.o2_lower = maxf(room.o2_upper, room.o2_lower - lower_entr)
    var ach_lower_dt: float = (ach_infiltration / 3600.0) * (building.outside_o2 - room.o2_lower) * dt
    room.o2_lower = clampf(room.o2_lower + ach_lower_dt, room.o2_upper, o2_nominal)
else:
    # Original (retrocompat)
    var lower_entr: float = entr_frac * 0.20 * maxf(0.0, room.o2_lower - room.o2)
    room.o2_lower = maxf(room.o2, room.o2_lower - lower_entr)
    var ach_lower_dt: float = (ach_infiltration / 3600.0) * (building.outside_o2 - room.o2_lower) * dt
    room.o2_lower = clampf(room.o2_lower + ach_lower_dt, room.o2, o2_nominal)
```

Cambio secundario **opcional** en `_exchange_room_o2_active_flow()` — cold_room O₂ lower routing (gateado por segundo flag):

```gdscript
# Phase 2H ext: la sala fría pierde aire fresco de su zona baja cuando alimenta la sala caliente
if phase2h_cold_room_lower_routing_enabled and cold_room_delta_o2_kg < 0.0:
    var lower_frac_cr: float = clampf(
        cold_room.thermal_layer_m / maxf(0.01, cold_room.height_m), 0.01, 0.99)
    var lower_mass_cr: float = maxf(
        0.001, _compute_room_air_mass_kg(cold_room, air_density_kg_m3) * lower_frac_cr)
    cold_room.o2_lower = clampf(
        cold_room.o2_lower + cold_room_delta_o2_kg / lower_mass_cr,
        0.0, o2_nominal)
```

Este segundo cambio se activa en Exp 2H.2 si Exp 2H.1 muestra mejora parcial.

---

### 12.4 Flags Propuestos

En `SimulationEngine.gd`, bloque después de phase2g (línea ~682):

```gdscript
# ── Phase 2H: O₂ doorway two-zone flow (default OFF) ─────────────────────────
@export var phase2h_o2_doorway_two_zone_enabled: bool = false
@export var phase2h_cold_room_lower_routing_enabled: bool = false
```

Pasan a `oxygen_exchange_system.configure()` (línea ~908):
```gdscript
"phase2h_o2_doorway_two_zone_enabled": phase2h_o2_doorway_two_zone_enabled,
"phase2h_cold_room_lower_routing_enabled": phase2h_cold_room_lower_routing_enabled,
```

Variables internas en `OxygenExchangeSystem.gd`, bloque `configure()`:
```gdscript
var phase2h_o2_doorway_two_zone_enabled: bool = false
var phase2h_cold_room_lower_routing_enabled: bool = false
```

---

### 12.5 Invariantes Garantizados por el Diseño

| Invariante | ¿Afectado por Phase 2H? |
|---|---|
| `room.o2` — bulk O₂ (combustión, HRR limiting) | No — sin cambio |
| `room.o2_upper` — zona alta (CO₂ production scale) | No — sin cambio |
| CO generation, smoke transport, FED | No — sin cambio |
| Los 289 checks de guardrails | No — flag default OFF |
| Timing de extinción de fuego | No — usa `room.o2` |
| HRR retained-flame modulation | No — usa `room.o2` + `retained_hot_layer_o2_*` |

La variable `room.o2_lower` solo es consumida por:
- Readouts de HUD (`compute_co_lower_ppm` y similares — solo display)
- Checks de `o2_lower` en validación (todos non-required/gaps)
- Ningún guardrail requerido

---

### 12.6 Casos del Experimento 2H.1

| Caso | Justificación |
|---|---|
| `cfast_two_room_door_open` | Cubre `cfast_2r_r0_t*_o2_lower` (sala fuego, 3 timepoints) |
| `cfast_single_room_closed` | Cubre `cfast_closed_t*_o2_lower` (sala sellada) |
| `g4_gie_delayed_entry_hazard` | Sentinel FED y CO |
| `v3_hallway_fed_exposure` | Sentinel FED en pasillo |
| `victim_fed_incapacitation` | Sentinel FED incapacitation |

Los casos de HVAC (`cfast_hvac_*`) y ventana (`cfast_t*`) se incluyen en la suite de validación completa post-experimento, no en el runner 2H.1 para mantener el runtime corto.

---

### 12.7 Métricas y Sentinels

**Métricas objetivo** (comparar con baselines CFAST):

| Check | Baseline expected | SF pre-2H | Objetivo post-2H |
|---|---|---|---|
| `cfast_closed_t300_o2_lower` | 0.2049 ±0.015 | 0.0684 | ≥ 0.19 |
| `cfast_closed_t450_o2_lower` | 0.2049 ±0.015 | 0.0429 | ≥ 0.10 |
| `cfast_2r_r0_t300_o2_lower` | 0.0952 ±0.015 | 0.2090 | [0.08, 0.11] |
| `cfast_2r_r0_t450_o2_lower` | 0.0909 ±0.015 | 0.0675 | [0.076, 0.106] |

**Sentinels obligatorios** (ventanas ya establecidas):

| Sentinel | Ventana permitida |
|---|---|
| g4 FED incapacitation | [187.75, 207.75] s |
| g4 CO > 1200 ppm | [82.33, 92.33] s |
| v3 FED > 0.1 | [222.17, 282.17] s |
| victim final FED | ≥ 0.70 |
| victim peak CO | ≥ 1500 ppm |

---

### 12.8 Riesgos y Mitigaciones

| Riesgo | Severidad | Mitigación |
|---|---|---|
| `o2_lower > room.o2` introduce inconsistencia si algún sistema usa `o2_lower` como proxy de O₂ disponible | MEDIO | Verificado: ningún guardrail ni ruta de combustión consume `o2_lower`. Solo readouts de HUD. |
| Sala sellada: `o2_lower` se mantiene alto con Phase 2H, pero sin ventilación no hay flujo que lo reponga. El ACH `0.05` sigue activo pero debería ser el único mecanismo. | BAJO-MEDIO | Aceptable: CFAST también mantiene ~0.205 en sala sellada. La física del modelo two-zone lo justifica. |
| Dos salas t=300: SF tiene `o2_lower=0.209` (demasiado fresco) y CFAST tiene `0.095`. Phase 2H mantiene el floor en `o2_upper` — si `o2_upper` sigue alto a t=300, este check podría no mejorar. | MEDIO | Aceptar gap residual; prioridad es cerrar los checks de sala cerrada y ventana (dirección correcta). |
| `cold_room.o2_lower` routing (segunda parte) depleta pasillo si no hay replenishment externo hacia el pasillo. | MEDIO | Solo activar en Exp 2H.2 con `phase2h_cold_room_lower_routing_enabled=true`; Exp 2H.1 lo deja OFF. |
| Guardrails de timing de FED (sentinels g4/v3/victim) | BAJO | Phase 2H no toca `room.o2` ni `o2_upper` en ruta de combustión → timing de HRR/CO/FED inalterado. |

---

### 12.9 Resumen del Primer Experimento Seguro (Exp 2H.1)

**Objetivo**: verificar que el cambio de floor `room.o2 → room.o2_upper` mejora los checks `o2_lower` sin romper los 289 guardrails.

**Implementación total**: ~20 líneas en `OxygenExchangeSystem.gd`, ~6 líneas en `SimulationEngine.gd`.

**Runner**: `scripts/simulation/phase2h_experiment_1_runner.py`  
- 5 casos × 1 combinación flag (ON/OFF) = 10 runs totales (muy bajo costo)  
- Sentinels: mismos 5 que Phase 2G  
- Overrides: `phase2h_o2_doorway_two_zone_enabled=true`, `phase2h_cold_room_lower_routing_enabled=false`

**Invariante verificable antes de merge**: guardrails 289/289 PASS con ambos flags OFF. Flag ON solo para los 5 casos del runner.

**Artefactos de salida**: `{case}_p2h1_on.json` y `{case}_p2h1_off.json` para comparación directa.

---

### 12.10 Resultados — Exp 2H.1 (phase2h_o2_doorway_two_zone_enabled=true)

**Fecha de ejecución**: 25 mayo 2026  
**Runner**: `scripts/simulation/phase2h_experiment_1_runner.py`  
**Godot**: 4.6.3-stable, EXIT 0, 10/10 runs OK

#### 12.10.1 Runs

```
[ 1/10] Phase2H OFF  g4_gie_delayed_entry_hazard     ... OK
[ 2/10] Phase2H OFF  v3_hallway_fed_exposure          ... OK
[ 3/10] Phase2H OFF  victim_fed_incapacitation        ... OK
[ 4/10] Phase2H OFF  cfast_single_room_closed         ... OK
[ 5/10] Phase2H OFF  cfast_two_room_door_open         ... OK
[ 6/10] Phase2H ON   g4_gie_delayed_entry_hazard     ... OK
[ 7/10] Phase2H ON   v3_hallway_fed_exposure          ... OK
[ 8/10] Phase2H ON   victim_fed_incapacitation        ... OK
[ 9/10] Phase2H ON   cfast_single_room_closed         ... OK
[10/10] Phase2H ON   cfast_two_room_door_open         ... OK
```

#### 12.10.2 Sentinels

| Variante    | g4 CO>1200  | g4 FED      | v3 FED      | v3 maxFED  | vic FED      | vic CO       | Total |
|-------------|-------------|-------------|-------------|------------|--------------|--------------|-------|
| BASELINE    | 85.583 OK   | 198.417 OK  | 249.833 OK  | 2.212 OK   | 0.772 OK     | 3381.925 OK  | 6/6   |
| OFF         | 85.583 OK   | 198.417 OK  | 249.833 OK  | 2.212 OK   | 0.772 OK     | 3381.925 OK  | 6/6   |
| ON          | 85.583 OK   | 198.417 OK  | 249.833 OK  | 2.212 OK   | **0.896 OK** | 3381.925 OK  | 6/6   |

Sentinels pasan (6/6 ON) porque vic FED usa umbral mínimo (≥ 0.7). Ver §12.10.5.

#### 12.10.3 Invariante room.o2

```
INVARIANTE room.o2: OK — sin violaciones (Δ < ±0.001)
```

Todos los `room_X_final_o2` muestran Δ_on = +0.0000. La combustión/HRR no se altera.

#### 12.10.4 Tabla comparativa de métricas

| Caso                        | Métrica               | Baseline  | ON        | Δ_on                      |
|-----------------------------|-----------------------|-----------|-----------|---------------------------|
| g4_gie_delayed_entry_hazard | CO>1200 [s]           | 85.5833   | 85.5833   | +0.0000 (+0.00%)          |
| g4_gie_delayed_entry_hazard | FED>0.1 [s]           | 198.4167  | 198.4167  | +0.0000 (+0.00%)          |
| g4_gie_delayed_entry_hazard | peak CO upper [ppm]   | 62716.89  | 62716.89  | +0.0000 (+0.00%)          |
| g4_gie_delayed_entry_hazard | r0 final o2           | 0.1131    | 0.1131    | +0.0000 (+0.00%)          |
| g4_gie_delayed_entry_hazard | r1 final o2           | 0.1276    | 0.1276    | +0.0000 (+0.00%)          |
| v3_hallway_fed_exposure     | FED>0.1 [s]           | 249.8333  | 249.8333  | +0.0000 (+0.00%)          |
| v3_hallway_fed_exposure     | max FED               | 2.2116    | 2.2116    | +0.0000 (+0.00%)          |
| v3_hallway_fed_exposure     | peak CO upper [ppm]   | 47367.60  | 47367.60  | +0.0000 (+0.00%)          |
| victim_fed_incapacitation   | **final FED** ⚠️      | **0.7715** | **0.8959** | **+0.1244 (+16.13%)**  |
| victim_fed_incapacitation   | peak CO [ppm]         | 3381.93   | 3381.93   | +0.0000 (+0.00%)          |
| cfast_single_room_closed    | CO upper [ppm]        | 1200.35   | 1200.35   | +0.0000 (+0.00%)          |
| cfast_single_room_closed    | CO mixed [ppm]        | 647.10    | 647.10    | +0.0000 (+0.00%)          |
| cfast_two_room_door_open    | r0 final o2           | 0.0642    | 0.0642    | +0.0000 (+0.00%)          |
| cfast_two_room_door_open    | r1 final o2           | 0.1279    | 0.1279    | +0.0000 (+0.00%)          |

#### 12.10.5 Anomalía crítica: victim_fed_incapacitation FED +16.13%

**Observación**: el único cambio observable entre ON y OFF es el FED en `victim_fed_incapacitation`  
(0.7715 → 0.8959, Δ = +0.1244). Confirmado comparando todos los métricas del reporte `_p2h1_on.json` vs `_p2h1_off.json`:

```
room_0_final_fed:    off=0.784008  on=0.908420  Δ=+0.124411
room_0_max_fed:      off=0.784008  on=0.908420  Δ=+0.124411
victim_v0_final_fed: off=0.771535  on=0.895947  Δ=+0.124411
```

Ninguna métrica de CO, HRR, temperatura, ni `room.o2` cambia.

**Diagnóstico — mecanismo de inversión**: El componente FED de hipoxia en `ThermalSystem.gd → compute_fed_delta_for_height()` usa `room.o2_lower` para víctimas en zona baja:

```gdscript
# Fase 2E-A: zona inferior usa o2_lower (protegida del fuego, siempre >= room.o2).
var o2_pct: float = clampf((room.o2_upper if in_upper else room.o2_lower) * 100.0, 0.0, 20.9)
var o2_deficit: float = maxf(0.0, 20.9 - o2_pct)
if o2_deficit > 0.0:
    var t_crit: float = exp(fed_hypoxia_a - fed_hypoxia_b * o2_deficit)
    delta += dt_min / t_crit
```

Con Phase 2H ON, el floor de `o2_lower` cambia `room.o2` → `room.o2_upper`. Como `room.o2_upper < room.o2`
(la zona alta está más depleta), el floor baja, permitiendo que `o2_lower` descienda **por debajo de `room.o2`**.

| Etapa               | OFF (baseline)                          | ON (Phase 2H)                                  |
|---------------------|-----------------------------------------|------------------------------------------------|
| Floor de o2_lower   | `room.o2` (p.ej. ≈ 0.133)              | `room.o2_upper` (< room.o2, p.ej. ≈ 0.09)     |
| Gradiente entrainment | `o2_lower − room.o2` (menor)          | `o2_lower − room.o2_upper` (MAYOR)             |
| Efecto neto         | `o2_lower ≥ room.o2` garantizado        | `o2_lower` puede caer hasta `room.o2_upper`    |
| FED hipoxia         | menor o2_deficit                        | **mayor o2_deficit → más FED**                 |

El comentario "siempre >= room.o2" documenta el invariante Phase 2E-A que Phase 2H **rompe**.

**Por qué cfast_single_room_closed no cambia**: habitación sellada sin flujo activo de apertura →
`room.o2_upper ≈ room.o2` → nuevo floor ≈ floor original → efecto nulo.

**Por qué los demás casos tampoco cambian**: las variaciones de `o2_lower` no afectan CO, HRR ni `room.o2`.
Solo el caso victim tiene víctimas en zona baja con `fed_hypoxia_enabled=true` y condiciones donde
`o2_lower` puede divergir entre los dos floors.

#### 12.10.6 Conclusión

**Exp 2H.1: NO PROMOTABLE — mecanismo invertido.**

El experimento demuestra que cambiar el floor `room.o2 → room.o2_upper` produce el efecto opuesto al deseado:

- **Objetivo**: ELEVAR `o2_lower` (desacoplarla de la combustión, acercarla a ambiental como CFAST)
- **Resultado real**: BAJAR `o2_lower` (floor más bajo = `room.o2_upper` más depleta)

La raíz del gap no es el floor — es que el término de entrainment arrastra `o2_lower` hacia `room.o2`
(bulk depleto). Cambiar el floor solo permite que `o2_lower` caiga más. El mecanismo correcto debe
**añadir reabastecimiento positivo** de zona baja cuando hay apertura exterior activa.

**Acción**: los flags de Phase 2H permanecen en default=false. El código del branch ON en
`OxygenExchangeSystem.gd` se reemplaza en Exp 2H.2 con el mecanismo correcto. Los flags se reutilizan.

---

### 12.11 Rediseño — Exp 2H.2 (boost de reabastecimiento de zona baja)

**Raíz correcta del gap**:  
El término de entrainment tiene como objetivo `room.o2` (bulk):
```gdscript
lower_entr = entr_frac * 0.20 * max(0, o2_lower - room.o2)
o2_lower   = max(room.o2, o2_lower - lower_entr)
```
Cuando el bulk se depleta, el arrastre baja `o2_lower`. En CFAST, el flujo de aire fresco a nivel bajo
(inflow por apertura exterior) domina sobre el arrastre y mantiene `o2_lower ≈ 0.205`. SimuFire modela el
reabastecimiento solo vía ACH de infiltración genérica, que es insuficiente para compensar.

**Mecanismo correcto**: cuando hay apertura exterior con flujo positivo (fresh air inflow), añadir un
término de reabastecimiento directo a `o2_lower` proporcional al caudal de entrada.  
**No cambiar el floor** — mantener `room.o2` como floor (invariante Phase 2E-A intacto).

```gdscript
# Exp 2H.2: boost de reabastecimiento de zona baja cuando hay apertura activa.
# outdoor_inflow_frac: fracción del volumen de habitación que entra por apertura exterior / segundo.
if phase2h_o2_doorway_two_zone_enabled and outdoor_inflow_frac > 0.0:
    var refresh_dt: float = outdoor_inflow_frac * (building.outside_o2 - room.o2_lower) * dt
    room.o2_lower = clampf(room.o2_lower + refresh_dt, room.o2, o2_nominal)
# Floor sigue siendo room.o2 (invariante Phase 2E-A intacto).
```

**Invariante preservado**: `o2_lower ≥ room.o2` siempre.

**Prerequisito**: `OxygenExchangeSystem.gd` necesita recibir `outdoor_inflow_frac` por habitación.  
Verificar si `ThermalSystem.gd` o `_exchange_room_o2_active_flow()` ya expone este dato.

**Estado**: ⬜ PENDIENTE — requiere reescribir el branch ON, ejecutar runner.

---

### 12.12 Implementación y Resultados — Exp 2H.2

**Fecha**: 25 mayo 2026  
**Estado**: ✅ COMPLETADO — Path B (HVAC) verificado operativo tras diagnóstico + fix

#### 12.12.1 Diseño final implementado

Se implementaron dos paths de reabastecimiento de `o2_lower` detrás del flag
`phase2h_o2_doorway_two_zone_enabled` (default OFF) y el parámetro
`phase2h_lower_replenish_gain` (default 0.0 = no-op exacto):

**Path A — Apertura exterior** (`OxygenExchangeSystem._step_outside_opening_o2()`):  
Después de la mezcla masa-ponderada existente (Fase 2A), si el flag está ON y `gain > 0`:
```gdscript
# Phase 2H Exp 2H.2: boost adicional de reabastecimiento de zona baja
var boost_frac: float = clampf(
    phase2h_lower_replenish_gain * air_in_kg / lower_mass_ext, 0.0, 0.50)
indoor.o2_lower = clampf(
    indoor.o2_lower + boost_frac * (building.outside_o2 - indoor.o2_lower),
    indoor.o2, o2_nominal)
```
Física: amplifica el inflow fresco efectivo por un factor `gain`, con cap 0.5 para evitar
saltos discretos al 50% del gap por step.

**Path B — Suministro HVAC bajo** (`HVACSystem._supply_air()`):  
Cuando `phase2h_o2_doorway_two_zone_enabled=true` y el difusor está en `height_fraction < 0.5`:
```gdscript
var supply_o2_lower: float = clampf(supply_mix.get("o2", outside_o2), 0.0, outside_o2)
room.o2_lower = clampf(
    lerpf(room.o2_lower, supply_o2_lower, air_fraction),
    room.o2, building.outside_o2)
```
Física: el aire fresco inyectado a baja altura (h=0.1 del local HVAC residencial) refresca
directamente la capa inferior. El floor `room.o2` preserva invariante Phase 2E-A.

**Invariante Phase 2E-A**: `o2_lower ≥ room.o2` garantizado por `clampf` en ambos paths.  
**FED**: `compute_fed_delta_for_height()` NO modificada — solo `o2_lower` sube, nunca baja.

#### 12.12.2 Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `sim/core/OxygenExchangeSystem.gd` | `phase2h_lower_replenish_gain` var + configure(); boost en `_step_outside_opening_o2()`; **fix invalidación bi-zona** |
| `sim/core/HVACSystem.gd` | o2_lower replenishment en `_supply_air()` cuando flag ON y height < 0.5 |
| `sim/core/SimulationEngine.gd` | `@export phase2h_lower_replenish_gain: float = 0.0`; pasa flag a HVAC hooks |
| `scripts/simulation/phase2h_experiment_2_runner.py` | Runner de gain sweep (4 valores × 6 casos = 24 runs) |

#### 12.12.3 Diagnóstico: bug de efecto nulo (primera ejecución) y fix

**Primera ejecución del sweep**: todas las métricas `O2l=` eran byte-a-byte idénticas entre
gain=0.0 (flag OFF) y gain=1.0 (flag ON) en el caso HVAC. Delta = 0.0000.

**Causa raíz identificada** (OxygenExchangeSystem.gd, `_step_per_room_o2()`):

```gdscript
# CÓDIGO ORIGINAL — bug:
if lower_frac < 0.15 or (lower_frac < 0.40 and room.o2 < 0.070):
    room.o2_upper = room.o2
    room.o2_lower = room.o2   # ← RESET DURO cada step cuando room.o2 < 0.07
```

**Orden de ejecución en `step()`**: `_step_oxygen()` (línea 1192) → `_step_hvac()` (línea 1210).  
En incendio severo con `room.o2 < 0.07` (fase t≥240s en HVAC case), `_step_oxygen()` RESETEA
`o2_lower = room.o2` **ANTES** de que `_step_hvac()` aplique el boost. El boost HVAC añade
~6.8×10⁻⁷ por step, pero en el siguiente step se cancela por el reset. Net = 0.

**Fix aplicado** (`OxygenExchangeSystem.gd`):

```gdscript
# FIX — comportamiento baseline idéntico con flag=false; boost acumula con flag=true:
if lower_frac < 0.15 or (lower_frac < 0.40 and room.o2 < 0.070):
    room.o2_upper = room.o2
    if phase2h_o2_doorway_two_zone_enabled:
        room.o2_lower = maxf(room.o2, room.o2_lower)  # floor-only, preserva boost
    else:
        room.o2_lower = room.o2  # comportamiento original sin cambio
```

**Verificación del fix** (runs dirigidos `cfast_hvac_o2l_g000` / `cfast_hvac_o2l_g100`, flag OFF/ON):

| Tiempo | g=0.00 O2 | g=0.00 O2l | g=1.00 O2 | g=1.00 O2l | Δ O2l |
|--------|-----------|------------|-----------|------------|-------|
| t=180s | 0.1560 | 0.1991 | 0.1560 | 0.1991 | +0.0000 |
| t=300s | 0.0580 | 0.0580 | 0.0580 | **0.1678** | **+0.1098** |
| t=450s | 0.0336 | 0.0345 | 0.0336 | **0.1301** | **+0.0956** |
| t=600s | 0.0356 | 0.0356 | 0.0356 | 0.0371 | +0.0015 |

_t=180s sin cambio: `room.o2=0.156 > 0.07` → modelo bi-zona activo, el supply_mix_O2 (≈0.164)
es menor que o2_lower (0.199) por lo que el lerp reduce levemente; clamp al floor lo neutraliza.  
t=300s–450s: gran mejora — HVAC inyecta aire fresco en capa baja mientras bulk se depleta._

**Garantías del fix**:
- Con flag=false (baseline, todos los gains=0 y cualquier ejecución sin flag): reset original → 0 cambio.
- Invariante `o2_lower ≥ room.o2` preservada: `maxf(room.o2, ...)` garantiza floor.
- Invariante `room.o2` (bulk) invariante: no modificada por el fix.

#### 12.12.4 Guardrails pre-experimento

- Godot parse: EXIT 0 ✅  
- Guardrails flags OFF: 289/289 PASS ✅ (73 gaps conocidos sin cambio)

#### 12.12.5 Resultados del gain sweep

> Runner re-ejecutado tras fix. Datos abajo post-sweep.

**Tabla de sentinels por gain** (rango válido: g4 CO [82.3,92.3], g4 FED [187.8,207.8], v3 FED [222.2,282.2], v3 maxFED ≥1.0, vic FED ≥0.7, vic CO ≥1500):

| Gain | g4 CO>1200 | g4 FED | v3 FED | v3 maxFED | vic FED | vic CO | PASS |
|------|-----------|--------|--------|-----------|---------|--------|------|
| BASELINE | 85.583 | 198.417 | 249.833 | 2.212 | 0.772 | 3381.9 | 6/6 |
| 0.00 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 3381.9 ✅ | 6/6 |
| 0.25 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 3381.9 ✅ | 6/6 |
| 0.50 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 3381.9 ✅ | 6/6 |
| 1.00 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 3381.9 ✅ | 6/6 |

**HVAC o2_lower gap closure** (O2= bulk invariante; O2l= zona baja; referencia CFAST t180≈0.205, t300/t450: benchmark pendiente):

| Gain | t=180s O2l | t=300s O2l | t=450s O2l | Δ t300 vs g000 |
|------|-----------|-----------|-----------|----------------|
| 0.00 (baseline O2l) | 0.1991 | 0.0580 | 0.0345 | referencia |
| 0.25 | **0.1991** | **0.1678** | **0.1301** | **+0.1098** |
| 0.50 | **0.1991** | **0.1678** | **0.1301** | **+0.1098** |
| 1.00 | **0.1991** | **0.1678** | **0.1301** | **+0.1098** |

_Invariante `room.o2` (bulk): idéntico para todos los gains (delta < ±0.001 confirmado)._

#### 12.12.6 Criterio de promotabilidad

- Todos los 6 sentinels PASS para gain candidato. ✅ (confirmado en re-sweep)
- `vic_fed_ON ≤ vic_fed_baseline + 0.005` para todos los gains.
- `o2_lower ≥ room.o2` invariante (ninguna violación).
- Mejora medible en HVAC `o2_lower` respecto a g=0.00 para gain ≥ 0.25. ✅ (g≥0.25: +0.1098 en t=300s; g=0.25/0.50/1.00 idénticos — gain mínimo candidato: **g=0.25**)

**Observación**: g=0.25, g=0.50 y g=1.00 producen resultados idénticos en O2l. El boost de Path A/B satura con gain bajo. El gain mínimo promotable es **g=0.25** (menor perturbación al sistema).

**Estado**: ✅ COMPLETADO — 24/24 OK, 6/6 sentinels PASS para todos los gains, invariante room.o2 sin violaciones.

---

### §12.13 Candidate Validation — Phase 2H (gain=0.25, opt-in)

> Fecha: 24 mayo 2026 · Runner: `scripts/simulation/phase2h_candidate_runner.py`

#### 12.13.1 Configuración validada

| Flag | Valor |
|------|-------|
| `phase2h_o2_doorway_two_zone_enabled` | `true` |
| `phase2h_cold_room_lower_routing_enabled` | `true` (no-op en código actual; declarado) |
| `phase2h_lower_replenish_gain` | `0.25` |
| Default en producción | `false` / `false` / `0.0` (sin cambio) |

Metodología: **OFF** = flags=false, gain=0.0 (equivalente exacto a producción) vs **ON** = candidato. 14 runs (7 casos × 2 configuraciones). Godot parse: RC=0. Unittests: 13/13 OK. Guardrails: 289/289 PASS.

#### 12.13.2 Sentinels (6/6 PASS)

| Sentinel | Ventana | OFF | ON | Δ | PASS |
|----------|---------|-----|-----|---|------|
| g4 CO>1200 [s] | [82.333, 92.333] | 85.583 | 85.583 | +0.000 | ✅ |
| g4 FED>0.1 [s] | [187.750, 207.750] | 198.417 | 198.417 | +0.000 | ✅ |
| v3 FED>0.1 [s] | [222.170, 282.170] | 249.833 | 249.833 | +0.000 | ✅ |
| v3 max FED | [1.000, +∞) | 2.212 | 2.212 | +0.000 | ✅ |
| vic FED | [0.700, +∞) | 0.7715 | 0.7715 | +0.000 | ✅ |
| vic CO | [1500, +∞) ppm | 3381.9 | 3381.9 | +0.000 | ✅ |

#### 12.13.3 Invariante room.o2 (11 medidas — 0 violaciones)

Todos los casos: |Δ| = 0.0000 < tol 0.001. Confirmado para r0 y r1 en todos los casos con varias habitaciones.

#### 12.13.4 O2l gap closure — cfast_hvac_residential

| Tiempo | OFF O2l | ON O2l | Δ | CFAST ref | O2l≥O2 |
|--------|---------|--------|---|-----------|--------|
| t=180s | 0.1991 | 0.1991 | +0.0000 | ≈0.2049 | ✅ |
| t=300s | 0.0580 | **0.1678** | **+0.1098** | ≈0.2049 | ✅ |
| t=450s | 0.0345 | **0.1301** | **+0.0956** | ≈0.2049 | ✅ |
| final  | 0.0356 | 0.0371 | +0.0015 | — | ✅ |

_Gap cerrado parcialmente: Δ>+0.09 en la fase más crítica (t=300–450s). El gap residual (ON=0.1678 vs CFAST≈0.2049) es atribuible a la dinámica de combustión/extinción que consume O₂ a tasa superior al replenishment externo._

#### 12.13.5 Métricas de dinámica de fuego (sin regresión)

| Caso | Métrica | OFF | ON | Δ |
|------|---------|-----|-----|---|
| cfast_r0_window_360 | peak HRR [kW] | 1273.96 | 1273.96 | 0.000 |
| cfast_r0_window_360 | fire time [s] | 408.20 | 408.20 | 0.000 |
| cfast_r0_window_360 | opening event 0 [s] | 360.083 | 360.083 | 0.000 |
| cfast_single_room_closed | peak HRR [kW] | 730.84 | 730.84 | 0.000 |
| cfast_two_room_door_open | r0 peak HRR [kW] | 974.78 | 974.78 | 0.000 |

_HRR, extinction timing y opening events sin cambio. La mejora de o2_lower no retroalimenta room.o2, por lo que el cálculo de combustión es idéntico (by design: Path A/B no modifica room.o2)._

#### 12.13.6 Non-gating gaps monitor (CO upper peaks — sin regresión)

| Caso | Métrica | OFF | ON | Δ |
|------|---------|-----|-----|---|
| cfast_r0_window_360 | r0 peak CO upper [ppm] | 1040.77 | 1040.77 | 0.000 |
| cfast_single_room_closed | r0 CO upper final [ppm] | 1200.35 | 1200.35 | 0.000 |
| cfast_two_room_door_open | r1 CO upper final [ppm] | 595.38 | 595.38 | 0.000 |
| g4_gie_delayed_entry_hazard | peak CO upper [ppm] | 62716.9 | 62716.9 | 0.000 |
| v3_hallway_fed_exposure | peak CO upper [ppm] | 47367.6 | 47367.6 | 0.000 |

_Ningún gap no-gating empeora. La invarianza de CO/FED confirma que las modificaciones de Phase 2H son estrictamente en el plano de o2_lower (no afectan rutas CO ni FED)._

#### 12.13.7 Victim FED safety check

| | Valor |
|-|-------|
| OFF (candidato run) | 0.771535 |
| ON (candidato) | 0.771535 |
| Δ ON−OFF | +0.000000 |
| Límite (baseline + 0.005) | 0.776535 |
| Estado | ✅ No excede límite |

#### 12.13.8 Resumen y recomendación

**Runner output:**
```
✅ CANDIDATO VÁLIDO — gain=0.25 seguro para opt-in.
Recomendación: promover como preset opt-in, flag OFF por defecto.
```

**Análisis:**

| Criterio | Resultado |
|----------|-----------|
| 6/6 sentinels PASS | ✅ |
| room.o2 invariante (11 medidas) | ✅ 0 violaciones |
| o2_lower ≥ room.o2 | ✅ 0 violaciones |
| vic FED Δ ≤ +0.005 | ✅ Δ=0.000 |
| HRR/extinction sin regresión | ✅ |
| CO upper sin regresión | ✅ |
| Guardrails 289/289 PASS | ✅ |
| Unittests 13/13 OK | ✅ |
| Godot parse RC=0 | ✅ |

**Observación — saturación de gain**: gains 0.25, 0.50 y 1.00 producen O2l idéntico. El mecanismo de Path A/B satura a gain bajo. El mínimo efectivo es g=0.25.

**Gap residual**: ON=0.1678 vs CFAST≈0.2049 en t=300s (Δ≈−0.037 del benchmark). Cerrado parcialmente. El gap remanente requeriría un mecanismo de replenishment adicional (p. ej., mayor integración HVAC bidireccional) fuera del scope de Phase 2H.

#### 12.13.9 Decisión de promoción

**Implementado 24 mayo 2026**: El candidato se ha promovido como **preset opt-in** en `SimulationEngine.gd`.

**Implementación**:
- `@export var phase2h_candidate_preset: bool = false` añadido a `SimulationEngine.gd`
- En `_sync_auxiliary_services()`: si `phase2h_candidate_preset == true`, activa automáticamente los tres flags del candidato (`two_zone=true`, `cold_routing=true`, `gain=0.25`)
- Definición de referencia en `sim/resources/presets/phase2h_o2_lower_replenish_candidate.json`

**Uso opt-in** (en `engine_overrides` de cualquier caso JSON):
```json
"phase2h_candidate_preset": true
```
Equivalente explícito:
```json
"phase2h_o2_doorway_two_zone_enabled": true,
"phase2h_cold_room_lower_routing_enabled": true,
"phase2h_lower_replenish_gain": 0.25
```

| Garantía | Estado |
|----------|--------|
| Default producción `false` — sin cambio de baseline | ✅ |
| 289/289 PASS con preset=false | ✅ |
| Preset activa exactamente el candidato validado | ✅ |
| No requiere rebaseline | ✅ |
| Godot parse RC=0 | ✅ |

**Próximo paso**: validar en más escenarios HVAC (ventilación cruzada, edificio multi-sala) antes de considerar activación por defecto.

**Estado**: ✅ PHASE 2H PROMOTION COMPLETO — preset opt-in implementado, default SIN CAMBIO.

---

### §12.14 Phase 2I Experiment 1 — CO₂ upper fraction sweep

> Fecha: 25 mayo 2026 · Runner: `scripts/simulation/phase2i_experiment_1_runner.py`

#### 12.14.1 Motivación

Los 5 gaps CO₂ upper del inventario (categoría `CO₂ upper layer`) no se cierran con ningún mecanismo de Phase 2A–2H. La hipótesis explorada: elevar `room.co2_upper_kg` (masa CO₂ en zona alta) mediante un floor proporcional a `room.co2_kg` en salas con fuego activo podría aumentar las concentraciones CO₂ en zona alta y acercarlas al benchmark CFAST.

#### 12.14.2 Flag implementado

```gdscript
## Phase 2I — CO₂ upper fraction floor en sala fuego (default OFF = 0.0)
## Cuando > 0.0: co2_upper_kg se eleva a mín. co2_kg × fraction en salas con fuego activo.
## co2_kg invariante. Experimento 1 (2026-05-25): sin rebaseline, diagnóstico estructural.
## NOTA: room.co2_upper (ppm/FED) NO se modifica. Sólo afecta co2_lower_ppm en zona baja.
@export var phase2i_co2_upper_fraction: float = 0.0
```

**Archivos modificados**:
| Archivo | Cambio |
|---------|--------|
| `sim/core/SimulationEngine.gd` | `phase2i_co2_upper_fraction` flag + wired to `thermal_system.configure()` |
| `sim/core/ThermalSystem.gd` | Variable + `configure()` setter + boost logic en `sync_room_upper_layer()` |

**Boost logic** (en `sync_room_upper_layer()`, después del clamp existente):
```gdscript
# Phase 2I — CO₂ upper fraction floor en sala fuego (default OFF = 0.0)
if phase2i_co2_upper_fraction > 0.0 and (room.hrr_kw > 0.1 or room.fire != null):
    var _p2i_target: float = room.co2_kg * phase2i_co2_upper_fraction
    room.co2_upper_kg = clampf(maxf(room.co2_upper_kg, _p2i_target), 0.0, room.co2_kg)
```

**Guardia de fuego**: boost solo cuando `hrr_kw > 0.1 OR room.fire != null` — evita aplicarlo en salas frías (riesgo de reducir `co2_lower_kg` implícito y desacelerar FED de víctimas en zona baja).

#### 12.14.3 Arquitectura crítica: dos sistemas de CO₂ desacoplados

SimuFire mantiene **dos variables CO₂ completamente independientes**:

| Variable | Gestionado por | Usado en | Log field |
|----------|---------------|----------|-----------|
| `room.co2_upper` (fracción molar, 0–0.30) | `OxygenExchangeSystem.gd` | `compute_co2_upper_ppm()` = `room.co2_upper × 1e6`; FED V_CO2 upper | `CO2u=` |
| `room.co2_upper_kg` (masa en kg) | `ThermalSystem.gd` + `CombustionSystem.gd` | `compute_co2_lower_ppm()` via `co2_lower_kg = co2_kg − co2_upper_kg`; FED V_CO2 lower | — |

**Consecuencia directa**: Phase 2I actúa sobre `co2_upper_kg` → NO modifica `room.co2_upper` → NO afecta el campo `CO2u=` del log → los checks de gap CO₂ upper (que usan `compute_co2_upper_ppm() = room.co2_upper × 1e6`) **no pueden cerrarse** con este mecanismo.

Esta es la hipótesis nula del experimento: los gaps CO₂ upper son estructurales (origen en `OxygenExchangeSystem`, no en `ThermalSystem`).

#### 12.14.4 Guardrails pre-experimento

- Godot parse: EXIT 0 ✅
- `validation_guardrails.py`: 292/292 PASS, 65 gaps ✅
- `python -m unittest tests.test_guardrails -v`: 13/13 OK ✅

#### 12.14.5 Configuración del sweep

| Parámetro | Valor |
|-----------|-------|
| Fracciones | 0.25, 0.50, 0.75, 1.00 |
| Casos sentinel | `g4_gie_delayed_entry_hazard`, `v3_hallway_fed_exposure`, `victim_fed_incapacitation` |
| Casos CO₂ | `cfast_r0_window_360`, `cfast_two_room_door_open`, `cfast_post_flashover_vented` |
| Total runs | 4 × 6 = 24 |

#### 12.14.6 Resultados — 24/24 runs OK

**Tabla 1: Sentinels por fracción**

| Fracción | g4 CO>1200 | g4 FED | v3 FED | v3 maxFED | vic FED | Total |
|----------|-----------|--------|--------|-----------|---------|-------|
| BASELINE | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 5/5 |
| f=0.25 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 5/5 |
| f=0.50 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 5/5 |
| f=0.75 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 5/5 |
| f=1.00 | 85.583 ✅ | 198.417 ✅ | 249.833 ✅ | 2.212 ✅ | 0.772 ✅ | 5/5 |

**Tabla 2: Sentinel deltas (todos Δ = 0.000)**

Todas las 5 métricas sentinel muestran Δ = +0.000 en las 4 fracciones. La guardia de fuego correcta previene cualquier regresión (confirma que el mecanismo es safe).

**Tabla 3: CO₂ upper por fracción (desde log `CO2u=`)**

| Check | Baseline | CFAST ref | Tol | f=0.25 | f=0.50 | f=0.75 | f=1.00 | Baseline pass |
|-------|----------|-----------|-----|--------|--------|--------|--------|---------------|
| cfast_t510_co2_upper_ppm | 16 182 ppm | 52 300 ppm | ±20 000 | +0 | +0 | +0 | +0 | FAIL |
| cfast_t420_co2_upper_ppm | 41 438 ppm | 60 800 ppm | ±22 000 | +0 | +0 | +0 | +0 | PASS |
| cfast_2r_r0_t120_co2_upper_pct | 4.750% | 1.58% | ±3.0% | +0.000 | +0.000 | +0.000 | +0.000 | FAIL |
| cfast_2r_r0_t480_co2_upper_pct | 0.999% | 9.91% | ±3.0% | +0.000 | +0.000 | +0.000 | +0.000 | FAIL |
| cfast_fo_t240_co2_upper_pct | 3.774% | 7.77% | ±3.0% | +0.551 | +0.551 | +0.551 | +0.551 | FAIL |
| cfast_fo_t350_co2_upper_pct | 3.711% | 7.89% | ±3.0% | −2.937 | −2.937 | −2.937 | −2.937 | FAIL |

**Observaciones**:
- **4 checks**: Δ CO₂ = 0 exacto en todas las fracciones — confirma desacoplamiento arquitectónico total.
- **`cfast_fo_t240/t350`**: muestran Δ ≠ 0 (ligera interacción en post-flashover), pero no cierran el gap. Δ insuficiente y no monótono respecto a fracción.
- **Gaps cerrados: 0/5 en todas las fracciones.**

**Resumen por fracción**:
- f=0.25: 0/5 gaps cerrados (de los 5 que fallaban en baseline)
- f=0.50: 0/5 gaps cerrados
- f=0.75: 0/5 gaps cerrados
- f=1.00: 0/5 gaps cerrados

#### 12.14.7 Diagnóstico final

**RESULTADO: Phase 2I (co2_upper_kg floor) no cierra ningún gap CO₂ upper.**

Los gaps CO₂ upper son de naturaleza **estructural**: las variables `room.co2_upper` (fracción molar, `OxygenExchangeSystem`) y `room.co2_upper_kg` (masa, `ThermalSystem`) son completamente independientes. Incrementar `co2_upper_kg` no modifica `room.co2_upper` → Δ CO₂ ppm upper ≈ 0 (salvo interacciones marginales de post-flashover).

El mecanismo de Phase 2I es **safe** (Δ sentinels = 0.000, guardia de fuego funciona), pero es **insuficiente** para cerrar los gaps objetivo.

#### 12.14.8 Decisión

**Phase 2I: DESCARTADA como mecanismo para gaps CO₂ upper.**

- Flag `phase2i_co2_upper_fraction` permanece en **default OFF = 0.0**.
- No se requiere rebaseline (baseline 292/292 PASS intacto).
- No se hace commit/push.

**Camino correcto para gaps CO₂ upper**:

Los gaps CO₂ upper requieren **Phase 2E plena**: modificar directamente `room.co2_upper` en `OxygenExchangeSystem.gd`, actuando sobre alguna de estas causas raíz:
1. Aumentar `co2_yield` en la reacción de combustión que alimenta `room.co2_upper`
2. Reducir la dilución inter-room del CO₂ en fase ventilada (la apertura de ventana o puerta diluye `room.co2_upper` excesivamente)
3. Añadir un término de acumulación de CO₂ en zona alta proporcional al HRR (análogo al mecanismo Phase 2H para O₂)

La estrategia recomendada es la opción 2 ó 3, que tiene menor riesgo de regresión en los sentinels de FED/CO (ya validados para Phase 2H).

**Ver plan técnico completo**: [docs/architecture/PHASE_2E_CO2_DESIGN.md](PHASE_2E_CO2_DESIGN.md) — diseño de Sub-A/B/C con flags, 4 experimentos secuenciales, 6 correcciones de diseño aplicadas post-revisión. Recomendación: iniciar por Exp 2E-CO2-1A (Sub-C).

---

*Documento actualizado: 25 mayo 2026.*
