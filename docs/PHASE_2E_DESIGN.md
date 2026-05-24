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

| Check | Actual | Expected | Tol | Margen |
|-------|--------|----------|-----|--------|
| `g4_gie_delayed_entry_hazard_time_room_1_fed_above_0_1_s` | 198.4 s | 197.75 s | ±10 s | 0.65 s (6.5 % del tol) |
| `g4_gie_delayed_entry_hazard_room_1_peak_co_upper_ppm` | 62716.9 ppm | ≥2000 ppm | — | holgado |
| `g4_gie_delayed_entry_hazard_time_room_1_co_upper_above_1200_s` | (verificar en json) | 87.33 s | ±5 s | — |

El primer check tiene **margen de 0.65 s sobre una tolerancia de ±10 s**. Cualquier cambio
que retrase el FED en room_1 entre 10.65 s y más lo rompe.

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
5. Actualizar `docs/GAPS_INVENTORY.md` con nuevo conteo de gaps.

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

*Documento generado: 24 mayo 2026. Actualizar antes de iniciar implementación — el estado del
código puede haber cambiado. Siempre re-verificar líneas exactas antes de hacer edits.*
