# Simufire — Estado del proyecto
**Última actualización**: 13 abril 2026

## Proyecto
- Godot/GDScript, simulación de incendios en apartamento
- Workspace: `c:\Users\dangp\Documents\GitHub\simufire`

## Estructura del edificio
- R0=Salón (origen del fuego), R1=Pasillo, R2=Dorm1, R3=Dorm2, R4=Cocina, R5=Baño
- Todas las ventanas cerradas (`open_fraction=0.0`)
- `window_leakage_area_m2=0.005`, `time_scale=5.0`

## Parámetros clave (`SimulationEngine.gd`)
- `fire_extinction_hrr_kw=8.0`
- `fire_extinction_delay_s=120.0`
- `fire_max_active_s=1800.0` ← **añadido esta sesión**
- `thermal_feedback_coeff=0.15`
- `wall_absorption_rate=0.003`
- `pressure_vent_threshold_pa=2.0`

## Cambios implementados (sesión 13 abril)
### `sim/core/SimulationEngine.gd`
1. **Fix 1**: En el bloque `remaining_fuel_MJ <= 0`, añadido `room.fire = null` (era un bug silencioso — el objeto fire persistía)
2. **Fix 2**: Añadido `@export var fire_max_active_s: float = 1800.0` — mata cualquier fuego activo >30 min
3. Nuevo bloque de extinción por tiempo máximo:
   ```gdscript
   if room.fire_time_s >= fire_max_active_s:
       room.hrr_kw = 0.0
       room.smoke_prod_kg_s = 0.0
       room.fire = null
       continue
   ```

## Verificación en log (2570s run)
- ✅ R0 extinguido a t=1040s (combustible agotado + contador de baja HRR)
- ✅ R1 extinguido a t=1890s (fire_max_active_s funcionó, fire_time_s≈1800s)
- ✅ Temperaturas vuelven a 20°C tras extinción
- ✅ Sin errores de compilación

## Causa raíz del fuego zombi R1 (aún sin resolver completamente)
- Tras flashover, `max_hrr_kw` sube a 5500 kW (con bonus `secondary_hrr_gain_kw=2500`)
- Con O2=0.1004: `o2_factor = (0.1004-0.10)/(0.209-0.10) ≈ 0.00367`
- `hrr = 5500 × 0.00367 ≈ 20 kW` → siempre por encima del umbral de 8 kW
- ACH (stack effect) mantiene O2 justo en 0.1004, impidiendo extinción por O2
- `fire_max_active_s` es un **parche** — no resuelve la causa raíz

## Próximos pasos pendientes
1. **[PRIORITARIO]** Añadir sedimentación/deposición de humo — actualmente tras la extinción la masa de humo es completamente estática (R0: ~4.8 kg congelado, no disipa). Es físicamente incorrecto.
2. **[MEJORA]** Investigar por qué el combustible de R1 no se agota naturalmente (20 kW × 1800s = 36 MJ consumidos — revisar `remaining_fuel_MJ` input vs. consumo real).
3. **[OPCIONAL]** Resolver causa raíz zombi: ajustar parámetros de combustible secundario o reducir `secondary_hrr_gain_kw` para que `max_hrr_kw` resulte en HRR < 8 kW con O2 bajo.

## Log de referencia
- `C:\Users\dangp\AppData\Roaming\Godot\app_userdata\Simufire\sim_log.txt`
- Última run: 2570s simulados (~43 min), `time_scale=5.0`
