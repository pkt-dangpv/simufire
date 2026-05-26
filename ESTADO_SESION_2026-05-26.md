# ESTADO SESIÓN — 2026-05-26

## Resumen de la sesión

Diagnóstico y corrección del bug en Sub-A (Phase 2E CO₂), seguido de la promoción de Sub-D + Sub-A a producción. Commit `8ce5d3f` consolidado en `origin/main`.

---

## Estado Git

```
HEAD → main = origin/main = 8ce5d3f  (working tree limpio)
```

Últimos commits:
```
8ce5d3f Phase 2E Sub-A PRODUCCION: supresion dilución co2_upper por inflow exterior (gain=0.20)
15aa7ac Add ESTADO_SESION_2026-05-25 session report
246b8ab feat(glass): glass_broken state + visual feedback en 2D/3D/FP/HUD + modo en menu
ff348a9 feat(phase2e-co2): Sub-D snap guard (CANDIDATO) + Sub-B exchange frac infra
ab1b140 Phase 2E CO2 design, validation and view refactor
```

---

## Estado de validación

- **Suite completa**: `python scripts/simulation/validate_reference_cases.py` → **292/292 PASS**
- **Gaps no-gating**: 65 (sin cambios respecto a sesión anterior)
- Guardrails: `python scripts/simulation/validation_guardrails.py`

---

## Phase 2E CO₂ — Estado final

### Sub-D (snap bi-zona guard)
- **Estado**: PRODUCCIÓN (`phase2e_co2_subd_enabled = true`)
- **Mecanismo**: cuando `lower_frac < 0.15 AND hrr_kw > 0.0`, omite el snap de `co2_upper` — la rama de producción continúa
- **Verificado Exp 1D**: t480=12.1% ∈ [6.91%, 12.91%] PASS; FED delta=0.000

### Sub-A (supresión dilución por inflow exterior)
- **Estado**: PRODUCCIÓN (`phase2e_co2_suba_enabled = true`, `phase2e_co2_upper_outflow_gain = 0.20`)
- **Mecanismo**: `effective_air_in = air_in × (1 − gain)` donde `gain=clamp(0,1)`
  - `gain=0.0` → igual que baseline (dilución completa)
  - `gain=0.20` → 80% del `air_in` mezcla con zona alta (20% supresión)
  - `gain=1.0` → sin dilución (aire fresco sólo a zona baja)
- **Física**: en el modelo bi-zona, el aire fresco entra por la parte baja del hueco y no mezcla directamente con la zona alta
- **Bug corregido esta sesión**: el modelo anterior (`lerpf(co2_upper, 0.0004, 0.25)` por step) destruía `co2_upper` a ~400 ppm en 150 pasos → peor que el baseline

### Resultados Exp 1E (Sub-D + Sub-A, gain=0.20)

| Check | CFAST ref | Baseline | Sub-D solo | **Sub-D+A 0.20** | Gate |
|-------|-----------|----------|------------|-----------------|------|
| t510 ppm | 52,300 | 16,182 | 25,047 | **38,356** | ∈[32k,72k] ✅ |
| t420 ppm | 60,800 | 41,438 | 65,992 | **80,512** | ∈[39k,83k] ✅ |
| t480 % | 9.91% | 1.0% | 12.1% | **12.14%** | ∈[6.91,12.91] ✅ |
| t120 % | 1.58% | 4.7% | 4.7% | **4.75%** | ≤5.58% ✅ |
| Sentinels | — | 5/5 | 5/5 | **5/5** | ✅ |
| FED Δ | — | — | 0.000 | **0.000** | ✅ |

Candidatos encontrados: gain=0.20, 0.22, 0.24 (resultados idénticos — diferencia subgranular respecto al step de simulación). Se eligió **gain=0.20** (más conservador, mayor margen vs t420 upper bound de 82,800 ppm).

---

## Archivos modificados en esta sesión (commit 8ce5d3f)

### `sim/core/OxygenExchangeSystem.gd`
- Reescrito bloque Sub-A en `_step_outside_opening_o2()` (líneas ~453-476)
- **Modelo nuevo**: dilution-suppression
  ```gdscript
  var suppression: float = clampf(phase2e_co2_upper_outflow_gain, 0.0, 1.0)
  var effective_air_in: float = air_in_kg * (1.0 - suppression)
  if effective_air_in > 0.0:
      indoor.co2_upper = clampf(
          (indoor.co2_upper * room_air_mass_kg + 0.0004 * effective_air_in) / (room_air_mass_kg + effective_air_in),
          0.0, 0.30)
  ```

### `sim/core/SimulationEngine.gd`
- `phase2e_co2_subd_enabled: bool = true` (antes `false`)
- `phase2e_co2_suba_enabled: bool = true` (antes `false`)
- `phase2e_co2_upper_outflow_gain: float = 0.20` (antes `0.0`)
- Comentarios de `@export` actualizados para reflejar modelo correcto y valores candidatos

### `scripts/simulation/phase2e_co2_experiment_1e_runner.py` (nuevo)
- Runner de Exp 1E: Sub-D + Sub-A gain sweep
- Modos: Baseline (reusa), Sub-D (reusa Exp 1D), Sub-D+Sub-A gains=[0.x]
- TABLA 1 (sentinels), FED delta, TABLA 2 (CO₂ gaps multi-modo), VEREDICTO con diagnóstico

---

## Infraestructura de experimentación Phase 2E

| Runner | Tag reportes | Propósito |
|--------|-------------|-----------|
| `phase2e_co2_experiment_1c_runner.py` | `_p2e1c` | Sub-B sweep (descartado) |
| `phase2e_co2_experiment_1d_runner.py` | `_p2e1d` | Sub-D solo (CANDIDATO) |
| `phase2e_co2_experiment_1e_runner.py` | `_p2e1e_aXX` | Sub-D + Sub-A (CANDIDATO gain=0.20) |

Parámetros de experimentos en `sim/validation/reports/`:
- `*_p2e1d.{json,log}` — Sub-D solo (referencia para Exp 1E)
- `*_p2e1e_a{gain}.{json,log}` — Sub-D+Sub-A por gain (pueden borrarse, son temporales)

---

## Configuración de producción (SimulationEngine.gd defaults actuales)

```gdscript
# Phase 2E Sub-A: dilution-suppression co2_upper por inflow exterior
@export var phase2e_co2_suba_enabled: bool = true
@export var phase2e_co2_upper_outflow_gain: float = 0.20

# Phase 2E Sub-B: CO₂ exchange frac infra (deshabilitado — no controla snap t480)
@export var phase2e_co2_subb_enabled: bool = false
@export var phase2e_co2_exchange_fraction: float = 0.25

# Phase 2E Sub-D: omite snap bi-zona en fuego activo
@export var phase2e_co2_subd_enabled: bool = true
```

---

## Siguiente paso recomendado

Con Phase 2E CO₂ completo (Sub-D + Sub-A en producción), los próximos pasos lógicos son:

1. **Revisar los 65 gaps no-gating** — verificar cuáles son los más relevantes para el gameplay (prioridad por impacto en FED/CO/visibilidad)
2. **Phase 2E Sub-C / Sub-E** (si existen en el roadmap) — revisar si hay otros mecanismos CO₂ pendientes
3. **Gameplay / Victoria-Derrota** — UI shell existe para WaterPanel/VentPanel/RescuePanel pero sin lógica conectada
4. **git push** si aún no se ha hecho (verificar con `git status`)

---

## Entorno de desarrollo

- **Godot**: `F:\OneDrive\Escritorio\Godot_v4.6.3-stable_win64_console.exe`
- **Workspace**: `F:\OneDrive\Documentos\GitHub\simufire`
- **Suite**: `python scripts/simulation/validate_reference_cases.py`
- **Guardrails**: `python scripts/simulation/validation_guardrails.py`
- **Runner individual**: Godot `--headless --path . -- --validation-case=NOMBRE`
