# Concordancia — Calibración Motor SimuFire vs Ghanekar (2026)

**Fecha**: 2026-04-20  
**Caso de validación**: `ghanekar_bedroom_hallway`  
**Duración simulada**: 420 s  
**time_scale**: 5.0  
**Referencia empírica**: Ghanekar et al. (2026), incendio residencial a escala real — dormitorio con hallway

---

## 1. Cambios aplicados en esta sesión

### 1.1 Parámetros de transporte (`transport_soft_plus`)

Parámetros identificados en el sweep anterior como la mejor variante, pero que nunca se habían aplicado a los defaults del motor:

| Parámetro | Anterior | Nuevo | Justificación |
|---|---|---|---|
| `doorway_o2_exchange_coeff` | 1.70 | 1.00 | Reduce transferencia O₂ por doorway |
| `doorway_o2_background_exchange_kg_s_m2` | 0.06 | 0.035 | Mezcla de fondo más suave |
| `base_spill_kg_s_per_m2` | 0.50 | 0.30 | Menos derrame de humo caliente |
| `temp_push_factor` | 0.008 | 0.005 | Menor empuje térmico |
| `ach_infiltration` | 0.50 | 1.10 | Infiltración pasiva + retorno HVAC |

### 1.2 Acoplamiento térmico capa baja

| Parámetro | Anterior | Nuevo | Justificación |
|---|---|---|---|
| `lower_layer_warming_rate` | 0.014 | 0.018 | Compensa enfriamiento de ACH elevado; permite que la capa baja alcance flashover (600 °C @ 0.9 m) |

### 1.3 Nuevas especies y métricas

- **CO₂**: Producción en combustión (yield interpolado con O₂), transporte completo (doorway, spill, ACH, presión)
- **FED**: Dosis fraccional efectiva según ISO 13571 (narcosis CO + factor hiperventilación CO₂)
- **SVV**: Clasificación de supervivencia de víctimas (ALTA/MEDIA/BAJA/MÍNIMA)

---

## 2. Resultados — Métricas de umbral vs Ghanekar

### 2.1 Métricas principales (5/5 dentro de rango)

| Métrica | Resultado | Objetivo | Rango | Estado |
|---|---|---|---|---|
| Flashover 600 °C @ 0.9 m (room 0) | **168.9 s** | 186 ± 18 s | 168–204 | ✅ |
| O₂ < 20.4 % hallway (room 2) | **202.7 s** | 198 ± 18 s | 180–216 | ✅ |
| CO > 200 ppm hallway (room 2) | **196.8 s** | 204 ± 18 s | 186–222 | ✅ |
| CO > 1200 ppm (IDLH) hallway (room 2) | **210.2 s** | 216 ± 12 s | 204–228 | ✅ |
| Inicio humo hallway (room 2) | **195.1 s** | 198 ± 18 s | 180–216 | ✅ |

### 2.2 Comparativa con calibración anterior

| Métrica | Anterior | Actual | Cambio |
|---|---|---|---|
| Flashover | 192.1 s ✅ | 168.9 s ✅ | −23.2 s (más temprano, sigue en rango) |
| O₂ hallway | 171.0 s ❌ | 202.7 s ✅ | +31.7 s (**CORREGIDO**, era 27 s fuera de rango) |
| CO 200 ppm | 195.6 s ✅ | 196.8 s ✅ | +1.2 s |
| CO 1200 ppm | 207.4 s ✅ | 210.2 s ✅ | +2.8 s |
| Humo hallway | 194.4 s ✅ | 195.1 s ✅ | +0.7 s |

### 2.3 Nuevas métricas (sin referencia Ghanekar directa)

| Métrica | Resultado | Notas |
|---|---|---|
| CO₂ > 5000 ppm hallway | 203.7 s | Detección precoz de CO₂ |
| FED > 0.3 hallway | 290.5 s | Inicio incapacitación |
| FED > 1.0 hallway | 363.7 s | Dosis letal |

---

## 3. Valores pico

### 3.1 Dormitorio (room 0 — origen del fuego)

| Variable | Valor |
|---|---|
| HRR pico | 1106 kW |
| Temp capa superior pico | 900 °C (clamped) |
| Temp @ 0.9 m final | 580.8 °C |
| Temp @ 1.8 m final | 603.6 °C |
| CO pico | 2467 ppm |
| CO₂ pico | 20 027 ppm (2.0 vol%) |
| O₂ final | 11.7 % |
| FED final | 0.735 |
| L150 mínimo | 0.062 m |

### 3.2 Hallway (room 2 — espacio adyacente clave)

| Variable | Valor |
|---|---|
| CO pico | 9223 ppm |
| CO₂ pico | 44 138 ppm (4.4 vol%) |
| O₂ final | 18.1 % |
| Temp capa superior pico | 62.8 °C |
| FED final | 1.889 |
| Humo final | 1.00 kg |

---

## 4. Clasificación SVV (Supervivencia de Víctimas) @ t = 420 s

| Habitación | FED | Zona SVV | Descripción |
|---|---|---|---|
| Room 0 (dormitorio) | 0.735 | **BAJA** (5–90 %) | FED 0.3–5, L150 < 0.5 m |
| Room 1 (contigua) | 1.745 | **MÍNIMA** (< 5 %) | FED > 1 |
| Room 2 (hallway) | 1.889 | **MÍNIMA** (< 5 %) | FED > 1 |
| Room 3 (alejada) | 0.230 | **MEDIA** (90–99 %) | FED 0.1–0.3 |
| Room 4 | 0.000 | **ALTA** (> 99 %) | Sin afectación |
| Room 5 | 0.999 | **BAJA** (5–90 %) | FED 0.3–5 |
| Room 6 | 0.000 | **ALTA** (> 99 %) | Sin afectación |

---

## 5. Limitaciones conocidas

1. **CO₂ absoluto**: El pico de CO₂ en dormitorio (2.0 vol%) es inferior al ΔCO₂ de Ghanekar (8.53 ± 1.85 vol%). Esto se debe a la combinación de alto ACH (1.10) y modelo de combustión simplificado sin descomposición pirolítica completa.
2. **HCN**: No se modela cianuro de hidrógeno. El FED es conservador (solo CO + CO₂ hiperventilación).
3. **Resolución espacial**: Modelo de dos capas; no captura gradientes continuos ni radiación inter-capa detallada.
4. **Flashover marginal**: Con `lower_layer_warming_rate = 0.018`, el flashover ocurre a 168.9 s, justo en el borde inferior del rango (168 s). Valores futuros de ACH podrían sacarlo del rango.

---

## 6. Archivos modificados

| Archivo | Cambios |
|---|---|
| `SimulationEngine.gd` | 5 params transporte + 2 params CO₂ yield + clamp CO₂/FED |
| `ThermalSystem.gd` | `lower_layer_warming_rate` 0.018, `compute_co2_ppm()`, `step_fed()` |
| `CombustionSystem.gd` | Producción CO₂ interpolada con O₂ |
| `GasExchangeSystem.gd` | Transporte completo CO₂ (doorway, spill, ACH, presión) |
| `RoomModel.gd` | Campos `co2_kg`, `fed` |
| `SimulationStateBuilder.gd` | `co2_ppm`, `fed` en estado |
| `SimulationLogWriter.gd` | CO₂ y FED en log |
| `CaseRunner.gd` | `co2_ppm`, `fed`, `peak_co2_ppm`, `max_fed` en métricas |
| `ghanekar_bedroom_hallway.json` | 3 nuevos umbrales (CO₂ 5000, FED 0.3, FED 1.0) |
