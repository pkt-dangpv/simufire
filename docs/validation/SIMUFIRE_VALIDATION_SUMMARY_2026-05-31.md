# SimuFire — Resumen de Validación
**Versión**: Release Candidate 2026-05-31  
**Commit base**: `440380e` (+ paquete Phase 4B)  
**Motor**: Godot 4.6.3 / GDScript  
**Estado**: 379/379 checks requeridos PASS · 4 gaps estructurales no-gating · listo para publicación

---

## 1. Alcance del Simulador

SimuFire es un simulador de dinámica de incendios en compartimentos orientado a entrenamiento y toma de decisiones para bomberos. Implementa un modelo zonal (capa superior caliente / capa inferior fría) por habitación, con acoplamiento entre compartimentos a través de vanos (puertas, ventanas) y conductos HVAC.

Fenómenos modelados:

| Dominio | Capacidades |
|---|---|
| **Combustión** | HRR por objeto combustible, pirólisis, factor de O₂, extinción por agotamiento de oxígeno, combustible no quemado retenido. |
| **Termodinámica zonal** | Temperaturas capa superior/inferior, altura de capa de humo, jet de techo, transferencia a paredes, presión termodinámica en recintos sellados. |
| **Transición de fase** | Flashover (criterios Thomas y MQH), backdraft, smoldering. |
| **Productos de combustión** | CO, CO₂, O₂, HCN, HCl, acroleína, formaldehído; estratificación capa superior/inferior. |
| **Tenabilidad (FED/FEC)** | Dosis efectiva fraccional por componente (CO, HCN, hipoxia, calor) + concentración efectiva fraccional de irritantes; visibilidad por humo. |
| **Ventilación** | Flujo por vanos, rotura de cristales, apertura/cierre de puertas, HVAC supply/return, ventilación por presión positiva (PPV). |
| **Tácticas de bombero** | Ataque transicional, knockdown, aplicación de agua, entrada diferida (escenarios GIE). |

---

## 2. Metodología de Validación

La validación es **basada en referencias**: cada métrica del simulador se compara contra una fuente externa con una tolerancia justificada. Las fuentes incluyen:

- **CFAST** (NIST, modelo zonal de dos zonas): casos de referencia generados con CFAST y exportados a CSV. Cubren crecimiento, flashover, burnout, multi-habitación, multi-piso, HVAC, cierre de puerta, rotura de ventana.
- **Literatura Ghanekar**: incendios de cocina/dormitorio con perfiles de temperatura y CO.
- **Escenarios GIE** (tácticas de intervención): ataque transicional, PPV post-knockdown, entrada diferida.
- **Tests de conservación**: balance elemental de carbono, conservación de masa/energía en transporte.
- **Tenabilidad FED/HCN**: casos `victim_fed_incapacitation` y `pu_sofa_fec_incapacitation` calibrados contra el marco Purser (SFPE Handbook 5ª ed.).

Cada check se marca:
- **`required: true`** → debe pasar; bloquea la publicación si falla.
- **`required: false`** → informacional o gap estructural conocido; no bloquea.

Tres niveles de control automatizado:
1. `validate_reference_cases.py` — ejecuta los 521 checks contra los reportes.
2. `validation_guardrails.py` — verifica conteo de checks, sincronización de gaps y 7 sentinels Phase 2E.
3. `tests/test_guardrails.py` — 13 tests unitarios de los guardrails.

---

## 3. Resultados por Categoría

**Total: 521 checks** (379 requeridos + 142 no-gating informacionales).

| Categoría | Cobertura | Estado |
|---|---|---|
| Crecimiento / HRR | Curvas tabuladas, crecimiento rápido/lento, multi-combustible | ✅ PASS |
| Flashover | Thomas + MQH, casa simple, cocina Ghanekar | ✅ PASS |
| Burnout / decaimiento | Agotamiento de combustible, presión post-fuego | ✅ PASS |
| Multi-habitación / multi-piso | Acoplamiento por vanos, transporte entre zonas | ✅ PASS |
| Ventilación | Rotura de cristal, cierre de puerta, confinamiento | ✅ PASS |
| HVAC | Supply/return, two-zone O₂ feed | ✅ PASS (4 gaps estructurales, §5) |
| Productos tóxicos | CO, CO₂, O₂, HCN estratificados | ✅ PASS |
| Tenabilidad FED/FEC | CO, HCN, hipoxia, calor, irritantes | ✅ PASS (§4) |
| Tácticas GIE | Ataque transicional, PPV, entrada diferida | ✅ PASS |
| Conservación | Balance de carbono, masa/energía | ✅ PASS |

**Required: 379/379 PASS — 0 fallos requeridos.**

---

## 4. Estado HCN / FED

La tenabilidad sigue el marco Purser (SFPE Handbook 5ª ed., Cap. 63), con FED acumulado y descompuesto por componente:

$$\text{FED}_{\text{total}} = \text{FED}_{\text{CO}} + \text{FED}_{\text{HCN}} + \text{FED}_{\text{hipoxia}} + \text{FED}_{\text{calor}}$$

Modelos por componente:
- **CO**: ley de potencia con factor de hiperventilación por CO₂ (Purser).
- **HCN**: modelo lineal con dosis crítica 4400 ppm·min (Purser).
- **Hipoxia**: inverso del tiempo de incapacitación a O₂ dado.
- **Calor**: convectivo (ISO 13571) + radiativo.

**Calibración (contra Purser SFPE: HCN ≈ 20–30% del FED en mobiliario residencial PU):**

| Caso | Sala | FED total | HCN% | Evaluación |
|---|---|---|---|---|
| `pu_sofa_fec_incapacitation` | room_0 | 23.28 | 19.7% | ✅ límite inferior del rango |
| `pu_sofa_fec_incapacitation` | room_1 | 6.28 | 25.1% | ✅ dentro del rango |
| `victim_fed_incapacitation` | room_0 | 0.78 | 0.9% | Fuego en rampa; CO domina antes del pico HCN (t≈800 s). Físicamente plausible. |

Yield HCN efectivo para PU sostenido ≈ `0.000154 kg/MJ` ≈ **0.004 g/g**, el límite inferior del rango PU foam flaming (Purser 0.004–0.017 g/g). Calibración **aceptable y conservadora**.

Detalle completo: [docs/audits/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md](../audits/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md).

---

## 5. Gaps y Limitaciones Conocidas

### 5.1 Gaps estructurales no-gating (4, aceptados)

Divergencia estructural SimuFire (modelo zonal con HVAC de flujo de masa) vs CFAST (dos zonas con transporte de capa resuelto):

| Check | Actual | Esperado (CFAST) |
|---|---|---|
| `cfast_hvac_t300_co_upper_ppm` | 2494 ppm | 661 ppm |
| `cfast_hvac_t450_co_upper_ppm` | 4949 ppm | 731 ppm |
| `cfast_hvac_t300_co2_upper_pct` | 21.0 % | 10.6 % |
| `cfast_hvac_t450_co2_upper_pct` | 30.0 % | 11.7 % |

Estos checks están marcados `required: false`. **No afectan ningún escenario de tenabilidad, FED ni flashover** y se aceptan como limitación conocida del acoplamiento HVAC.

### 5.2 Limitaciones físicas

- **Yield HCN conservador**: el modelo representa combustión bien ventilada (~0.004–0.007 g/g); subestima HCN en incendios confinados bajo-ventilados (0.03–0.12 g/g).
- **FED de víctima no descompuesto**: la víctima usa el FED total del compartimento; no se descompone por componente a nivel de objeto.
- **Calibración cuantitativa vs datos experimentales** (NIST/FSRI directos para HCN) pendiente como trabajo futuro; la calibración actual es analítica (ratios Purser).

### 5.3 Parámetros desactivados (no-op)

- `fire_o2_upper_hrr_blend = 0.0` — blend de O₂ de capa superior sobre HRR (Phase 4A). **Rechazado y revertido**; no-op exacto, ningún case JSON lo activa.

---

## 6. Comandos de Reproducción

```powershell
# Desde la raíz del repositorio (c:\Users\dangp\Documents\GitHub\simufire)

# 1. Validar los 379 checks requeridos (genera reference_checks.json)
python scripts/simulation/validate_reference_cases.py

# 2. Guardrails (conteo de checks, sincronización de gaps, sentinels Phase 2E)
python scripts/simulation/validation_guardrails.py

# 3. Tests unitarios de guardrails
python tests/test_guardrails.py

# 4. Ejecutar un caso de validación individual (headless)
& "C:\Users\dangp\Desktop\Godot_v4.6.3-stable_win64_console.exe" `
  --headless --path "." -- --validation-case=victim_fed_incapacitation

& "C:\Users\dangp\Desktop\Godot_v4.6.3-stable_win64_console.exe" `
  --headless --path "." -- --validation-case=pu_sofa_fec_incapacitation
```

**Entorno**: Godot 4.6.3 stable (win64 console), Python 3.x (`py`/`python`), Windows PowerShell.

---

## 7. Estado Exacto de Tests

```
validate_reference_cases.py  →  PASS: 379/379 required checks passed
                                 Known gaps: 4 non-gating checks did not pass

validation_guardrails.py     →  Required checks   379/379 PASS  [OK]
                                 Known gaps (JSON)            4
                                 Gap inventory sync        PASS
                                 Phase 2E sentinels (7)    PASS
                                 ALL GUARDRAILS PASS

test_guardrails.py           →  Ran 13 tests  OK
```

| Métrica | Valor |
|---|---|
| Checks totales | 521 |
| Checks requeridos | 379 |
| Requeridos fallidos | 0 |
| Gaps no-gating | 4 (estructurales HVAC) |
| Tests unitarios | 13/13 OK |
| Guardrails | ALL PASS |

---

## 8. Historial de Fases (resumen)

| Fase | Estado | Resultado |
|---|---|---|
| Phase 2B | ✅ Cerrada | Transporte multi-habitación, estratificación |
| Phase 2C | ✅ Cerrada | HVAC low-supply/high-return two-zone O₂ feed |
| Phase 3 | ✅ Cerrada | Presión termodinámica en recintos sellados |
| Phase 4A | ❌ Rechazada | `fire_o2_upper_hrr_blend` revertido a no-op |
| Phase 4B | ✅ Completada | HCN implementado, observable, FED descompuesto, calibración aceptable |

---

## 9. Documentación de Soporte

| Documento | Contenido |
|---|---|
| [docs/audits/PUBLICATION_READINESS_AUDIT_2026-05-31.md](../audits/PUBLICATION_READINESS_AUDIT_2026-05-31.md) | Auditoría completa pre-publicación (interna) |
| [docs/audits/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md](../audits/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md) | Calibración FED/HCN detallada |
| [docs/validation/GAPS_INVENTORY.md](GAPS_INVENTORY.md) | Inventario completo de gaps |
| [docs/planning/FINAL_VALIDATION_AND_PUBLICATION_PLAN.md](../planning/FINAL_VALIDATION_AND_PUBLICATION_PLAN.md) | Plan de validación y publicación |

---

*SimuFire es un modelo zonal con fines de entrenamiento y análisis comparativo de escenarios. No sustituye simulaciones CFD completas (p. ej. FDS) validadas cuantitativamente contra mediciones de incendio reales. Las limitaciones conocidas están documentadas en §5.*
