# Simufire - Estado de sesion
**Ultima actualizacion**: 15 abril 2026

## Donde queda guardado
- Este estado queda en el repo, en [ESTADO_SESION_2026-04-15.md](/F:/OneDrive/Documentos/GitHub/simufire/ESTADO_SESION_2026-04-15.md:1).
- Como el proyecto esta dentro de `F:\OneDrive\...`, deberia quedar sincronizado online por OneDrive y abrirse en otro ordenador con la misma cuenta.
- Si mas adelante quieres dejarlo tambien fijo en GitHub, habria que hacer commit/push aparte.

## Estado actual del modelo
- Proyecto Godot/GDScript de incendio en vivienda.
- Escenario base: R0 salon, R1 pasillo, R2 dorm1, R3 dorm2, R4 cocina, R5 bano.
- Ventanas automaticas por temperatura desactivadas por defecto.
- El motor ya usa una capa superior acoplada con `upper_gas_kg` y `upper_energy_kj`.
- El O2 ya no se mueve solo entre habitaciones vecinas: ahora hay redistribucion por toda la red de puertas abiertas.
- El humo subventilado ya no depende solo del `HRR` efectivo: hay una base de pirolisis/smolder para que con poco O2 siga apareciendo humo y CO.

## Cambios importantes ya hechos
### `sim/core/SimulationEngine.gd`
- `glass_auto_break_enabled = false` por defecto.
- Aniadido modelo de capa superior con:
  - `upper_gas_kg`
  - `upper_energy_kj`
- `_step_temperature()` rehecho para trabajar con masa/energia reales de la capa superior.
- `_step_oxygen()` ampliado con mezcla conservativa por red completa de puertas abiertas:
  - `o2_network_iterations = 4`
- `_step_smoke()` ahora mueve humo, CO, masa caliente y energia entre salas de forma acoplada.
- Se elimino una perdida artificial de humo cuando la capa bajaba mucho.
- Ajuste reciente para incendio confinado:
  - `fire_smoke_yield_low_o2_multiplier = 7.5`
  - `fire_smoke_basis_min_fraction = 0.40`
  - `fire_smolder_hrr_fraction = 0.10`
  - `fire_smolder_smoke_multiplier = 2.8`
  - `base_spill_kg_s_per_m2 = 0.26`
  - `max_spill_kg_s = 1.4`
  - `max_fraction_out_per_s = 0.08`

### `sim/smoke/SmokeModel.gd`
- La altura de capa ya no depende solo de `smoke_kg`.
- La capa se recalcula usando tambien la masa real de gases calientes.
- Las puertas pueden derramar humo en ambos sentidos en el mismo step.

## Lo ultimo validado en log
Log de referencia:
- `C:\Users\dangp\AppData\Roaming\Godot\app_userdata\simufire\sim_log.txt`

Ultima corrida larga revisada:
- Hasta `TIME=440.1 s`

Comportamiento observado en esa ultima corrida:
- El problema anterior de "el humo se retrae y el fuego muere demasiado pronto" ya no aparece.
- Ahora el edificio si se carga de humo como incendio confinado.
- Pero el ajuste actual probablemente se ha ido demasiado al lado fuerte:
  - `TIME=320.1 s`
    - `ROOM 0 | HRR=170.56 | Smoke=1.5028 | O2=0.1055`
    - `ROOM 1 | HRR=82.88 | Smoke=2.9206 | Layer=0.25 | O2=0.1134`
  - `TIME=400.1 s`
    - `ROOM 0 | HRR=35.76 | Smoke=3.2238 | O2=0.1012`
    - `ROOM 1 | HRR=10.40 | Smoke=5.7243 | Layer=0.00 | O2=0.1018`
  - `TIME=440.1 s`
    - `ROOM 0 | HRR=19.54 | Smoke=4.6994 | O2=0.1007`
    - `ROOM 1 | HRR=4.94 | Smoke=6.3505 | Layer=0.00 | O2=0.1009`

## Diagnostico honesto actual
- Antes:
  - Poco humo
  - El incendio moria pronto
  - El humo no llenaba bien la vivienda
- Ahora:
  - El incendio confinado genera humo de forma mucho mas creible
  - El O2 bajo ya no "mata" visualmente el humo
  - Pero el modelo esta demasiado agresivo en acumulacion de humo y propagacion secundaria
  - El pasillo llega a llenarse por completo muy pronto (`Layer=0.00`)

## Siguiente paso recomendado
Prioridad siguiente:
- Mantener el comportamiento de incendio confinado cargado de humo
- Pero bajar la agresividad de propagacion y llenado total del pasillo

Toques probables para la proxima sesion:
1. Subir el umbral de ignicion secundaria o exigir mas exposicion sostenida antes de encender otras salas.
2. Bajar un poco la base de humo subventilado o el derrame maximo por puerta sin volver al problema anterior.
3. Revisar el pasillo: ahora hace de gran reservorio de humo y se satura demasiado rapido.
4. Rehacer la nota antigua de "sedimentacion de humo" si queremos una fase post-incendio mas realista.

## Nota de revision pendiente
- El finding antiguo sobre mezcla de O2 con dos `lerp` secuenciales ya no es la prioridad central del modelo.
- El problema dominante ahora mismo es de calibracion fisica del humo en incendio confinado, no de sesgo menor en la mezcla local.
