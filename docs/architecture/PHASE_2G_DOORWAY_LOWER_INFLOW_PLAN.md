# Plan Phase 2G — Doorway lower inflow amplifier + gain balance

> Fecha: 2026-06-20
> Target: Grupo C `cfast_corridor_chain` (×2 FAILs: t180 + t600 temp_upper)
> Estado actual: superseded by Phase 2G results and current 345/350 PASS, 5 FAIL baseline. This plan is historical context only.

---

## Diagnóstico estructural

La infraestructura doorway YA EXISTE en `ThermalSystem.gd`:

- **Upper outflow** (líneas 1044–1128): mueve masa+energía de `hot_room.upper` → `cold_room.upper` vía Bernoulli (`bernoulli_upper_kg_s × doorway_heat_exchange_coeff`)
- **Thermal counterflow** (`_apply_doorway_thermal_counterflow`): transfiere energía pura `hot.upper` → `cold.upper` con `gain`
- **Part B lower inflow** (`_apply_canonical_doorway_exchange` línea ~2390): `bernoulli_lower_kg_s × canonical_doorway_lower_flow_frac × dt`, cap 5% de `cold_lower_mass`. Lleva energía + O₂ de `cold.lower` → `hot.lower`

El gap no es de mecanismo — es de **magnitud** del lower inflow. `canonical_doorway_lower_flow_frac=1.0` está al máximo; el `bernoulli_lower_kg_s` calculado es insuficiente para replicar el intercambio de CFAST (presión PDE completa vs Bernoulli simplificado).

### Datos del sweep Phase 2F (descartado)

| Rate plume | t=180 T | t=600 T | Δt600 |
|------------|---------|---------|-------|
| 0.025 (baseline) | 189.8°C | 105.8°C | — |
| 0.050 | 195.0°C | 107.8°C | +2.0°C |
| 0.080 | 195.4°C | 108.7°C | +2.9°C (decelera) |

Mejora t=600 < 3°C con rate×3. Gap a cerrar: 63°C. Lever ineficaz.

### Datos de O₂ en R0 a tiempos clave (baseline)

| t | O₂u | HRR | T actual | T CFAST | Estado |
|---|-----|-----|----------|---------|--------|
| 180s | 11.3% | 244 kW (81%) | 189.8°C | 159.8°C | FAIL +30°C |
| 300s | 10.9% | 207 kW (69%) | 147.0°C | 166.3°C | PASS (margen 0.7°C) |
| 480s | 10.0% | — | — | — | O₂ PASS (margen 0.016) |
| 600s | 9.9% | 178 kW (59%) | 105.8°C | 168.8°C | FAIL −63°C |

---

## Por qué el problema requiere dos palancas acopladas

| Tiempo | SF vs CFAST | Lever necesario | Efecto colateral si solo se usa ese lever |
|--------|-------------|----------------|-------------------------------------------|
| t=180 | SF +30°C | Extraer más calor de R0.upper | `gain` ↑ → también enfría t=300 (frágil) |
| t=300 | SF −19°C, margen 0.7°C | No empeorar | Cualquier cooling neto lo rompe |
| t=600 | SF −63°C | Sostener HRR (más O₂u) | O₂u ↑ → también sube HRR en t=180 (peor) |

**Combinación compensada**: `gain` ↑ (extrae calor upper, enfría t=180 y t=300) + lower inflow ↑ (más O₂u via pluma, sube HRR en t=300 y t=600). Si el efecto de cada lever se cancela en t=300, ambos FAILs podrían cerrarse simultáneamente.

---

## Cambio en sim/core — único punto de modificación

**Archivo**: `sim/core/ThermalSystem.gd`

### 1. Nueva variable (junto a `canonical_doorway_lower_flow_frac`, línea ~262)

```gdscript
var doorway_canonical_lower_inflow_multiplier: float = 1.0
```

### 2. Leer en `apply_settings()` (junto a los demás canonical params)

```gdscript
doorway_canonical_lower_inflow_multiplier = float(settings.get(
    "doorway_canonical_lower_inflow_multiplier",
    doorway_canonical_lower_inflow_multiplier))
```

### 3. Aplicar en `_apply_canonical_doorway_exchange` Part B (línea ~2390–2391)

```gdscript
# Antes:
var m_lower_kg_s: float = float(flow_state.get("bernoulli_lower_kg_s", 0.0)) \
        * canonical_doorway_lower_flow_frac

# Después:
var m_lower_kg_s: float = float(flow_state.get("bernoulli_lower_kg_s", 0.0)) \
        * canonical_doorway_lower_flow_frac \
        * doorway_canonical_lower_inflow_multiplier
```

El cap `minf(m_lower_kg, cold_lower_mass * 0.05)` permanece intacto — límite numérico de seguridad.

**Default=1.0 → no-op exacto**: `bernoulli_lower_kg_s × 1.0 × 1.0` = comportamiento actual. No hay flag boolean separado; el valor `1.0` es el guardrail de no-op.

---

## Conservación masa / energía / O₂

Part B ya es conservativa (Phase 7): actúa sobre `lower_energy_kj` (no `temp_lower_c`), preserva masa vía densidad. El multiplicador escala `m_lower_kg` uniformemente — la misma lógica de conservación aplica a cualquier valor.

| Campo | Sala caliente (R0) | Sala fría (R1) |
|-------|--------------------|----------------|
| `lower_energy_kj` | `+= m × (T_cold_lower − T_hot_lower)` | `-= m × max(0, T_cold_lower − ambient)` |
| `o2_lower` | mezcla ponderada con O₂ de R1.lower | sin cambio en Part B |
| `o2_upper` | sin cambio directo (replenishment via pluma, paso siguiente) | sin cambio |
| `upper_energy_kj` | sin cambio en Part B | sin cambio |

---

## Activación per-caso

Solo en `sim/validation/cases/cfast_corridor_chain.json`, **nunca global**:

```json
"doorway_canonical_lower_inflow_multiplier": 2.0,
"doorway_thermal_counterflow_gain": 0.30
```

(valores iniciales de experimento — ajustar según sweep)

---

## Protocolo de experimento

### Fase 1 — verificar no-op (OBLIGATORIA antes de activar en corridor_chain)

1. Implementar el cambio de motor con `doorway_canonical_lower_inflow_multiplier = 1.0` default
2. Sin tocar `corridor_chain.json`, correr suite completa (`run_reference_checks.ps1 -SkipCaseRuns`)
3. Confirmar `reference_checks.json` bit-identical → no-op garantizado
4. Si algún check cambia: **STOP**, investigar antes de continuar

### Fase 2 — sweep bidimensional (solo corridor_chain)

| Paso | gain | multiplier | Predicción |
|------|------|-----------|-----------|
| 0 (baseline) | 0.25 | 1.0 | t180=189.8, t300=147.0, t600=105.8 |
| 1 | 0.25 | 2.0 | t600 ↑, t180 ↑ (más O₂u) — cuantificar trade-off |
| 2 | 0.30 | 2.0 | t180 ↓ (más cooling), t300 ≈ neutral si compensan |
| 3 | 0.30 | 3.0 | t600 ↑↑, monitorear t300 |
| 4 | 0.35 | 3.0 | t180 ↓↓, riesgo t300 |
| 5 (si hace falta) | 0.28 | 4.0 | ajuste fino |

Parar si t300 falla (gap > 20°C) **o** t180 empeora > +10°C sobre baseline (199.8°C).

---

## Sentinels

| Check | Estado actual | Guard rail |
|-------|--------------|------------|
| `cfast_chain_r0_t180_temp_upper_c` | 189.8°C FAIL (+30°C) | No empeorar > +10°C (máx 199.8°C) |
| `cfast_chain_r0_t300_temp_upper_c` | 147.0°C PASS (margen 0.7°C) | **Crítico**: gap ≤ 20°C |
| `cfast_chain_r0_t600_temp_upper_c` | 105.8°C FAIL (−63°C) | Target: PASS (gap ≤ 30°C) |
| `cfast_chain_r0_o2_t480_o2` | 0.1002 PASS (margen 0.016) | O₂u sube → gap cierra (mejora esperada) |
| `cfast_2r_r0_rmse_temp_upper_c` (two_room) | 53.8°C PASS | multiplier=1.0 global → no-op garantizado |
| Resto 345 checks | todos PASS | Verificar en Fase 1 antes de activar |

---

## Riesgos

1. **t=300 frágil (margen 0.7°C)**: es el check más en riesgo. La combinación gain↑ + multiplier↑ debe balancearse — cuantificar paso 1 antes de seguir.

2. **O₂u amplification en early times**: multiplier ↑ → más O₂ en R0.lower → más O₂u via pluma → más HRR a t=180 → sube temp. Contrarresta el cooling del gain. Por eso el paso 1 (solo multiplier, sin gain) es diagnóstico.

3. **Cap 5% de `cold_lower_mass`**: con multiplier alto el cap puede activarse y limitar la transferencia efectiva. Si el cap es el cuello de botella, se puede subir a 8–10% como segundo ajuste de motor.

4. **Interacción M3b**: `doorway_thermal_counterflow_o2_return_fraction=0.0` en corridor_chain → sin doble conteo.

5. **Activación global accidental**: `doorway_canonical_lower_inflow_multiplier` es variable de instancia de ThermalSystem. Si se sobreescribe por `engine_overrides` globales afectaría todos los doorways interiores. Estricto per-case en `corridor_chain.json` únicamente.

---

## Rollback

1. Revertir `doorway_thermal_counterflow_gain` → `0.25` en `corridor_chain.json`
2. Eliminar `doorway_canonical_lower_inflow_multiplier` de `corridor_chain.json` (o fijarlo a `1.0`)
3. El código en `ThermalSystem.gd` permanece con default=1.0 (no-op)

---

## Fallback estructural

Si el sweep completo (hasta multiplier=5.0, gain=0.35) no cierra t=600 sin romper t=300 o t=180:

El gap requiere ODE de presión de dos zonas completo — mismo nivel que Phase 3 architecture. Clasificar Grupo C como **Phase 3 pending** y documentar que ningún lever per-caso ni amplificador Bernoulli es suficiente.

---

## Relación con otros documentos

- `docs/architecture/PHASE_2_TWO_ZONE_ARCHITECTURE_PLAN.md` — plan general Phase 2
- `docs/validation/STATUS_VALIDATION.md` — historial de sweeps anteriores (Phase 2F descartado)
- `docs/HANDOFF_CURRENT_STATE.md` — estado actual Grupo C
