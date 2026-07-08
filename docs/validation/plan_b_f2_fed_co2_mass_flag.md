# Plan B / F2 — Flag experimental `fed_co2_source_mass`

Fecha cierre: 2026-07-08  
Commit: `feat(validation): add experimental FED CO2 mass-source flag`  
Estado: **CERRADO como infraestructura experimental default OFF**

---

## Qué se hizo

Se añadió un flag per-caso `fed_co2_source_mass` (default `false`) que permite cambiar la
fuente de CO₂ usada en el cálculo de `v_co2` del FED ISO 13571:

- **OFF (default, producción):** `compute_co2_upper_ppm(room)` → `room.co2_upper × 1e6`  
  Tracer OES — mol fraction directa, sin error de densidad de gas caliente.

- **ON (experimental):** `compute_co2_upper_ppm_mass(room)` → `co2_upper_kg × 29e6 / (upper_zone_mass_kg × 44)`  
  Path mass-derived. Actualmente NO apto para producción (ver §Diagnóstico).

### Archivos modificados (motor)

| Archivo | Cambio |
|---------|--------|
| `sim/core/SimulationEngine.gd` (~L615) | `@export var fed_co2_source_mass: bool = false` |
| `sim/core/SimulationEngine.gd` (~L1069) | `"fed_co2_source_mass": fed_co2_source_mass` en settings dict |
| `sim/core/ThermalSystem.gd` (~L296) | `var fed_co2_source_mass: bool = false` |
| `sim/core/ThermalSystem.gd` (~L621) | `fed_co2_source_mass = bool(settings.get("fed_co2_source_mass", ...))` |
| `sim/core/ThermalSystem.gd` (~L3395) | `compute_fed_delta_for_height`: switch tracer/mass por flag |
| `sim/core/ThermalSystem.gd` (~L3455) | `step_fed`: switch tracer/mass por flag |

El flag sigue el patrón exacto de `fire_o2_upper_throttle_enabled` y demás flags per-caso.

---

## Experimento — resultados medidos (flag ON vs flag OFF)

Caso de prueba: `victim_fed_incapacitation` (víctima a 0.9 m, fuego 800 s).

| Métrica | Flag OFF (tracer) | Flag ON (mass) | Delta |
|---------|-------------------|----------------|-------|
| `victim_time_to_incapacitation_s` | 590.75 s | 590.83 s | +0.08 s |
| `room_0_max_fed` | 966.9 | ~astronomical | ver §Diagnóstico |
| `room_0_peak_co2_ppm_global` | 4.4 × 10⁵ | n/a (distintas zonas) | — |

**Impacto en víctima al 0.9 m:** +0.08 s — irrelevante. La víctima está en la zona inferior
durante la mayor parte de la simulación, donde se usa `compute_co2_lower_ppm` en ambos casos.

**Impacto en room FED (adulto canónico 1.8 m):** catastrófico con flag ON, ver abajo.

---

## Diagnóstico — por qué el path mass NO está listo para producción

### Fase activa del fuego (t < 300 s)
- `co2_upper_ppm_mass` (t < 300 s): 1.5 × 10⁵ – 4.2 × 10⁵ ppm
- `co2_upper_ppm` tracer: 2.1 × 10⁵ – 4.4 × 10⁵ ppm
- Ratio mass/tracer: 0.56–0.96 × → el tracer da v_co2 **más conservador**, lo cual es correcto.

### Post-extinción (t > 600 s) — BUG BLOQUEANTE

`co2_upper_kg` no se drena correctamente cuando el fuego se extingue. Al mismo tiempo,
`upper_zone_mass_kg` se reduce conforme la sala se enfría (el gas superior se contrae).

Resultado: `co2_upper_ppm_mass = co2_upper_kg / upper_zone_mass_kg × 29e6 / 44`
sube a valores físicamente imposibles (>50% vol, o sea >500 000 ppm) en la cola post-extinción.

Esto hace que `v_co2 = exp(0.1903 × 50 + 2.0004) / 7.1 ≈ 14 200` en cada step, y el FED
del adulto (1.8 m) acumula valores astronómicos. El path mass del FED es formalmente correcto
(exponential ISO 13571) pero la entrada `co2_upper_kg` tiene un bug de acumulación post-extinción.

**Root cause:** mismo bug familiar que F0 (bombeo concentrador CO₂ bulk, fix 82494f71) pero
aplicado al balance intra-room de `co2_upper_kg` tras extinción. El acumulador no drena porque:
- El fuego ya no produce CO₂.
- El transporte inter-room puede estar llevándose air mass pero no co2_upper_kg.
- `upper_zone_mass_kg` colapsa (enfriamiento) sin que `co2_upper_kg` colapsa a la misma tasa.

---

## Por qué se mantiene el flag (default OFF)

1. **Default OFF = no-op exacto.** Todos los checks, suites, baselines y guardrails producen
   resultados byte-a-byte idénticos al estado anterior al patch.

2. **Infraestructura lista para F3.** Cuando se corrija el bug `co2_upper_kg` post-extinción,
   activar el flag en casos de prueba no requiere más cambios en el motor.

3. **Documentación del bug activo.** La existencia del flag hace visible que el path mass existe
   pero tiene una condición bloqueante bien identificada.

---

## Qué NO hacer hasta que se cierre F3

- **No activar `fed_co2_source_mass: true` en ningún caso permanente** (ni baselines, ni
  `victim_fed_incapacitation`, ni casos de corredor o multi-room). El FED resultante es
  físicamente incorrecto.

- **No tocar baselines para aceptar la divergencia** — sería aceptar un bug como feature.

- **No cambiar el default global** a `true` — rompería todos los checks FED existentes.

- **No tocar D2PRE ni co2_upper_ppm CSV** — esos sistemas son independientes del FED path.

---

## Próximo paso (F3 — bloqueado)

**Prerequisito:** corregir el acumulador `co2_upper_kg` post-extinción en ThermalSystem.gd /
GasExchangeSystem.gd. El síntoma observable: en el CSV de `victim_fed_incapacitation`,
`co2_upper_ppm_mass` sube > 5 × 10⁵ ppm a t ≈ 630 s cuando el fuego está extinto.

El bug es de la misma familia que F0 (concentrador sin límite de equilibrio), pero intra-room
en la zona upper: el pool de `co2_upper_kg` no se vacea al ritmo que decrece `upper_zone_mass_kg`.

Una vez corregido: activar `fed_co2_source_mass: true` en casos de prueba, regenerar reports,
comparar con tracer path, y decidir si el path mass debe reemplazar o complementar al tracer.
