# Estado sesión 07 mayo 2026

## RESUMEN EJECUTIVO
Sesión de correcciones físicas (C1, A1, A4, A5, M2) + re-calibración de dos baselines.
Al finalizar: **todos los 5 baselines PASS**.

---

## ESTADO VALIDACIÓN (al cierre)

| Caso | Resultado | Nota |
|------|-----------|------|
| living_room_hallway | ✅ PASS | re-calibrado esta sesión |
| postfire_decay | ✅ PASS | — |
| confinement_open_close | ✅ PASS | — |
| layer150_tenability | ✅ PASS | re-calibrado esta sesión |
| ul_exterior_water_knockdown | ✅ PASS | — |

---

## CAMBIOS APLICADOS ESTA SESIÓN

### C1 — Plano neutro por balance de presión de dos zonas
**Archivo**: `sim/core/ThermalSystem.gd`, función `build_interior_opening_flow_state()`, ~línea 2044  
**Cambio**: reemplazó `neutral_plane_f = T_hot/(T_hot+T_cold)` por cálculo con balance de presiones:
```gdscript
h_n = h_thermal × (1/T_lower − 1/T_src) / (1/T_snk − 1/T_src)
```
**Efecto**: redujo flujo inter-sala → room_1 en living_room_hallway pasó de 308°C→264°C (más físico).  
**Consecuencia**: re-calibración de `living_room_hallway` y `layer150_tenability`.

### A1 — Peso yield CO₂
**Archivo**: `sim/core/SimulationEngine.gd`  
**Cambio**: `co2_completion_yield_weight: float = 0.75` (era 0.55)

### A4 — Doble bridge smoke_layer_m eliminado
**Archivo**: `sim/core/SimulationStateBuilder.gd`  
**Cambio**: `smoke_layer_m` ahora llama `smoke_model.get_effective_smoke_spill_layer_height_m(room)` directamente (sin puente intermedio antiguo).

### A5 — Anchura transición extinción
**Archivo**: `sim/core/SimulationEngine.gd`  
**Cambio**: `fire_fds_extinction_transition_width: float = 0.020` (era 0.030)

### M2 — Atenuación de radiación por humo (Beer-Lambert)
**Archivo**: `sim/core/ThermalSystem.gd`, función `_step_radiation_openings()`  
**Cambio**: reemplazó atenuación binaria (`if smoke > threshold: atten=0.55`) por Beer-Lambert:
```gdscript
exp(-8.7 × c_smoke_kg_m3 × path_len_m)
```
NOTA: el parámetro `radiation_smoke_attenuation_factor=0.55` en ThermalSystem.gd ~línea 71 **ya no se usa** (Beer-Lambert lo reemplaza).

### Re-calibración layer150_tenability
**Archivo**: `sim/validation/baselines/layer150_tenability.json`
```json
{
  "room_1_min_l150_m":           {"expected": 1.95,  "tolerance": 0.15},
  "room_1_final_temp_at_1_8m_c": {"expected": 112.6, "tolerance": 15.0},
  "room_0_final_layer_150c_m":   {"expected": 2.34,  "tolerance": 0.20}
}
```

### Re-calibración living_room_hallway
**Archivo**: `sim/validation/baselines/living_room_hallway.json`
```json
"room_1_peak_temp_upper_c": {"expected": 264.0, "tolerance": 25.0}
```
(era expected=308.0)

---

## ESTADO DE ARCHIVOS CLAVE

### sim/core/SimulationEngine.gd — @export defaults modificados esta sesión
```gdscript
var co2_completion_yield_weight: float = 0.75  # era 0.55 (A1)
var fire_fds_extinction_transition_width: float = 0.020  # era 0.030 (A5)
```

### sim/validation/cases/fds_simple_house_default.json — overrides activos
```json
"fire_fds_extinction_transition_width": 0.045,
"fire_pool_release_max_fraction": 0.0
```
IMPORTANTE: `fire_pool_release_max_fraction: 0.0` deshabilita pool burning para evitar consumo excesivo de O₂ (fix Run 12 sesión 05-mayo).

### sim/fire/CombustionSystem.gd — pool_release block (~líneas 375-390)
Sin guard de `can_flame` ni O₂ (M7 completamente revertido). Estado:
```gdscript
var release_tau_s: float = lerpf(
    float(context.get("fire_pool_release_tau_slow_s", 180.0)),
    float(context.get("fire_pool_release_tau_fast_s", 18.0)),
    room.ventilation_response_factor
)
var pool_release_cap_kw: float = fire.max_hrr_kw \
        * float(context.get("fire_pool_release_max_fraction", 0.18)) \
        * lerpf(0.55, 1.0, opening_signal)
pool_release_target_kw = minf(
    room.retained_unburned_MJ * 1000.0 / maxf(1.0, release_tau_s),
    pool_release_cap_kw
) * clampf(release_drive, 0.0, 2.0)
```

---

## PENDIENTES ABIERTOS

### M7 — pool_release backdraft accumulation (PENDIENTE)
**Problema original**: pool drena continuamente, impidiendo acumulación de retained_unburned_MJ al umbral de 8 MJ para backdraft.  
**Intentos fallidos**: guard `if can_flame:` y guard `if room.o2 > 0.13:` → ambos revertidos porque causaban FAIL en living_room_hallway.  
**Conclusión**: el FAIL no era por M7 sino por C1 (ya resuelto con re-calibración). Por tanto, M7 puede reintentarse ahora que living_room_hallway tiene el baseline correcto de 264°C.  
**Próximo intento**: aplicar guard `if room.o2 > float(context.get("fire_backdraft_o2_max", 0.13)):` y verificar que living_room_hallway siga PASS con baseline 264°C.

### C2 — Capa fría vs CFAST (PENDIENTE, NO INICIADO)
Brecha ~50-62% en temperatura capa superior en `cfast_r0_window_360`. Causa estructural: SimuFire mantiene h_layer cerca del techo; CFAST colapsa interfaz casi al suelo.  
Posibles vías: incrementar tasa de descenso de h_layer en fase O₂-starved, mejorar mass-flow vs área de ventana.  
Los overrides del caso `cfast_r0_window_360.json` están sobre-amortiguados tras los fixes de buoyancy del 04-mayo.

### A2 — O₂ remote gap (LIMITACIÓN ESTRUCTURAL ACEPTADA)
Antes de C1: O₂ remoto 17.8%; después: 14.26%; FDS referencia: 10.4%.  
No hay mejora posible sin cambios arquitecturales al modelo 0D.

### V1-V8 — Nuevos casos de validación (NO INICIADOS)
### G1-G4 — Ventilación táctica GIE (NO INICIADOS)

---

## CALIBRACIÓN FDS (estado Run 12, 05-mayo-2026)

### fds_simple_house_default.json — Run 12 overrides
```json
"fire_fds_extinction_enabled": true,
"fire_fds_extinction_o2_limit_ambient": 0.085,
"fire_fds_extinction_hot_o2_floor": 0.068,
"fire_fds_extinction_transition_width": 0.045,
"fire_fds_extinction_pyrolysis_floor": 0.01,
"fire_o2_hrr_fall_tau_s": 6.0,
"fire_max_hrr_kw": 1100.0,
"doorway_heat_exchange_coeff": 1.0,
"doorway_source_upper_weight": 0.92,
"fire_co_low_quality_yield_multiplier": 7.0,
"fire_co_max_effective_fraction": 0.40,
"fire_unburned_generation_fraction": 0.02,
"fire_pool_release_max_fraction": 0.0,
"hot_gas_species_carry_fraction": 0.40,
"hot_gas_species_max_fraction_per_step": 0.14,
"background_species_exchange_kg_s_m2": 0.250,
"background_species_max_fraction_closed": 0.040,
"background_species_path_multiplier_max": 6.0,
"doorway_o2_exchange_coeff": 2.50,
"doorway_o2_background_exchange_kg_s_m2": 0.18,
"doorway_o2_background_max_fraction_per_step": 0.060
```

### Resultados t=260s vs FDS
| Variable | FDS | SimuFire |
|----------|-----|---------|
| R0 O₂ | 9.89% | 8.88% |
| R0 CO | 606 ppm | 507 ppm (-16%) |
| R0 CO₂ | 5.19% | 5.48% ✅ |
| R1 O₂ | 10.4% | 13.47% (brecha estructural 0D) |

---

## COMANDO DE VALIDACIÓN
```powershell
$exe = "F:\OneDrive\Escritorio\Godot_v4.6.2-stable_win64_console.exe"
foreach ($c in @("living_room_hallway","postfire_decay","confinement_open_close","layer150_tenability","ul_exterior_water_knockdown")) {
    $out = & $exe --headless --path "F:\OneDrive\Documentos\GitHub\simufire" -- "--validation-case=$c" 2>&1
    $line = ($out | Select-String "Baseline (PASS|FAIL)")
    Write-Host "$c => $line"
}
```

---

## HISTORIAL SESIONES PREVIAS
Ver archivos `ESTADO_SESION_2026-05-03.md` y anteriores para historial completo de cambios de sesiones previas.
