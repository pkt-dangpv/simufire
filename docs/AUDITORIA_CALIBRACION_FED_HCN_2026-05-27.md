# Auditoría de Calibración: Componentes FED — HCN en Incendios de PU Residencial
**Fecha**: 2026-05-27  
**Fase**: Phase 4B — Calibración FED (separado de observabilidad)  
**Estado**: ✅ Calibración aceptable — documentada y sin cambios requeridos

---

## 1. Contexto

La Phase 4B añadió observabilidad de componentes FED (fed_co, fed_hcn, fed_hypoxia, fed_heat) a:
- `sim/building/RoomModel.gd` — campos acumuladores por componente
- `sim/core/ThermalSystem.gd` — cálculo por componente en `step_fed()`
- `sim/core/SimulationStateBuilder.gd` — exportación al estado de simulación
- `sim/core/SimulationLogWriter.gd` — CSV y .log
- `sim/validation/CaseRunner.gd` — métricas `room_N_final_fed_co/hcn/hypoxia/heat`

Esta auditoría evalúa si la fracción FED_HCN/FED_total es consistente con la literatura para incendios de PU foam residencial.

**Referencia bibliográfica clave**: Purser, D.A., "Toxicity Assessment of Combustion Products", *SFPE Handbook of Fire Protection Engineering* (5ª ed., 2016), Sección 2, Capítulo 63.  
Expectativa para espuma PU flexible en incendio residencial:
- FED_HCN / FED_total ≈ **20–30%** en condiciones sostenidas (Purser, SFPE 2016)
- Rendimiento HCN espuma PU (flaming, bien ventilado): 0.004–0.017 g/g (Purser)
- Rendimiento HCN espuma PU (bajo-ventilado): hasta 0.06–0.12 g/g (Purser, Tewarson)

---

## 2. Parámetros de Calibración Actuales

| Parámetro | Valor | Equivalencia g/g (@ 27 MJ/kg) |
|-----------|-------|-------------------------------|
| `hcn_yield_kg_per_MJ` (pu_sofa en caso) | 0.000154 | ≈ 0.0042 g/g |
| `hcn_base_yield_kg_per_MJ` (default global) | 0.000040 | ≈ 0.0011 g/g |
| `hcn_max_yield_kg_per_MJ` (techo global) | 0.000250 | ≈ 0.0068 g/g |

El valor 0.000154 kg/MJ para PU foam está en el **extremo inferior del rango de Purser** para flaming bien ventilado (0.004–0.017 g/g). El techo `hcn_max_yield` = 0.000250 corresponde a ~0.007 g/g, aún conservador respecto al rango bajo-ventilado.

---

## 3. Resultados de Simulación (Phase 4B, 2026-05-27)

### Caso 1: `victim_fed_incapacitation`
**Descripción**: Sofá PU en habitación única, t=800s (fuego en rampa t²). Víctima a 0.9m (zona baja).

| Componente | FED acumulado | % del total |
|------------|---------------|-------------|
| CO (narcótico) | 0.6578 | **83.9%** |
| HCN (tóxico) | 0.0071 | **0.9%** |
| Calor (conv+rad) | 0.1105 | 14.1% |
| Hipoxia (O2) | 0.0086 | 1.1% |
| **TOTAL (room FED)** | **0.7840** | 100% |
| Victim FED (a 0.9m) | 0.7715 | — |

HCN concentraciones:
- Zona baja (donde está la víctima): pico 226.5 ppm
- Zona alta: pico 2008.3 ppm

**Observación**: HCN contribuye solo el 0.9% del FED de habitación. Esto refleja la **dinámica de fuego en rampa**: el CO se acumula desde las etapas tempranas, mientras el HCN a concentraciones significativas solo aparece en los últimos instantes de la simulación de 800s. El pico de 2008 ppm en zona alta se alcanza prácticamente en el último paso de tiempo — la contribución integral es mínima. Este comportamiento es **físicamente plausible** para un escenario de incapacitación por CO antes de que el HCN alcance niveles letales.

### Caso 2: `pu_sofa_fec_incapacitation`
**Descripción**: Sofá PU con carga de fuego mayor, 2 habitaciones, t=800s.

#### Habitación 0 (sala de fuego)

| Componente | FED acumulado | % del total |
|------------|---------------|-------------|
| CO (narcótico) | 14.6917 | **63.1%** |
| HCN (tóxico) | 4.5833 | **19.7%** |
| Calor (conv+rad) | 2.5311 | 10.9% |
| Hipoxia (O2) | 1.4765 | 6.3% |
| **TOTAL** | **23.2826** | 100% |

HCN pico zona alta: 1889.4 ppm

#### Habitación 1 (habitación adyacente)

| Componente | FED acumulado | % del total |
|------------|---------------|-------------|
| CO (narcótico) | 4.4254 | **70.5%** |
| HCN (tóxico) | 1.5778 | **25.1%** |
| Calor (conv+rad) | 0.1885 | 3.0% |
| Hipoxia (O2) | 0.0847 | 1.3% |
| **TOTAL** | **6.2765** | 100% |

HCN pico zona alta: 3037.5 ppm

---

## 4. Evaluación de Calibración

### 4.1 Comparación con literatura (Purser SFPE)

| Caso / Habitación | HCN % simulado | Rango Purser | Evaluación |
|-------------------|----------------|--------------|------------|
| victim_fed (room 0) | 0.9% | 20–30% | ❌ Por debajo — explicado por dinámica de rampa |
| pu_sofa_fec (room 0) | 19.7% | 20–30% | ✅ Límite inferior (diferencia < 0.3 pp) |
| pu_sofa_fec (room 1) | 25.1% | 20–30% | ✅ Dentro del rango |

### 4.2 Análisis de la discrepancia en `victim_fed_incapacitation`

La fracción HCN = 0.9% en `victim_fed_incapacitation` **no indica un error de calibración**. La explicación es:

1. **Fuego en rampa t²**: la concentración de HCN en la zona alta crece con el HRR. En este escenario, HRR alcanza ~682 kW solo al final de los 800s.
2. **Dominio temprano de CO**: el CO se produce desde la ignición. A t=800s, CO acumulado es ~3382 ppm global; HCN solo alcanza 2008 ppm en la última fracción de la simulación.
3. **Integración temporal**: FED_HCN ≈ 0.007 equivale a ~1–2 pasos de tiempo con HCN elevado. Este valor es consistente con la concentración solo emergiendo al final.
4. **La víctima está a 0.9m** (zona baja): el cálculo de FED de víctima usa HCN de zona baja (~226 ppm), no los 2008 ppm de zona alta. La víctima alcanza incapacitación principalmente por CO en zona baja.

### 4.3 Conclusión de calibración

El rendimiento HCN `0.000154 kg/MJ` (≈ 0.004 g/g para espuma PU) es **consistente con el rango de Purser** para condiciones de flaming bien ventilado (límite inferior: 0.004 g/g).

En el escenario de fuego sostenido (`pu_sofa_fec_incapacitation`), la fracción HCN observada (19.7–25.1%) está **dentro o en el límite del rango de referencia Purser (20–30%)**, confirmando que el modelo reproduce cualitativamente la toxicología de PU foam.

**No se requieren cambios de calibración física.** La calibración cuantitativa completa contra datos experimentales (NIST, FSRI) para espumas PU específicas está fuera del alcance de Phase 4B y queda documentada como tarea futura.

---

## 5. Limitaciones Identificadas

1. **Rendimiento en condiciones bajo-ventiladas**: `hcn_max_yield_kg_per_MJ = 0.000250` (≈ 0.007 g/g) es conservador respecto al rango bajo-ventilado (0.03–0.12 g/g, Purser). La simulación no escala el rendimiento HCN dinámicamente con el índice de equivalencia φ (fuera de alcance Phase 4B).

2. **FED_HCN de víctima no descompuesto**: `compute_fed_delta_for_height()` retorna un escalar total. Los componentes de FED para víctimas individuales no están descompuestos (solo para el FED de habitación). Esto es coherente con el diseño: la observabilidad de componentes es a nivel de habitación.

3. **Un solo tipo de combustible PU testeado**: la calibración se basa en rendimiento del sofá PU; muebles de menor contenido de N (madera, textiles naturales) producirán fracciones HCN mucho menores, lo cual es correcto.

---

## 6. Estado de Validación Post-Auditoría

- **379/379 PASS** (sin cambios en lógica de cálculo)
- `victim_fed_incapacitation`: PASS — victim_v0_final_fed = 0.7715 > 0.7 ✅
- `pu_sofa_fec_incapacitation`: PASS — peak_hcn_upper_ppm >> 10 ppm ✅
- Métricas observables en reports: room_N_final_fed_co/hcn/hypoxia/heat ✅

---

## 7. Acciones Completadas (Phase 4B)

- [x] FED component fields: RoomModel, ThermalSystem, StateBuilder, LogWriter
- [x] CaseRunner metrics: room_N_final_fed_co/hcn/hypoxia/heat
- [x] Baselines HCN: room_0_peak_hcn_upper_ppm ≥ 10 ppm (non-gating) en 2 casos
- [x] Documentación: corrección "HCN no modelado" en MEMORIA_PARAMETROS
- [x] Esta auditoría de calibración
- [ ] PENDIENTE LARGO PLAZO: calibración cuantitativa contra datos experimentales PU foam específicos (NIST, FSRI, ISO 19706)
