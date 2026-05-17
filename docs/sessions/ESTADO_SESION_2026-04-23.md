# Simufire - Estado de sesion
**Ultima actualizacion**: 23 abril 2026

## Resumen ejecutivo
- Se reviso la estructura del repo, los ficheros de sesion recientes, el motor principal y el log mas reciente.
- El estado documentado el 22 abril sigue reflejado en codigo:
  - `sim/core/SimulationEngine.gd` mantiene la calibracion de CO2 (`0.0831` / `0.0594`), la relajacion de `L150` (`0.05` / `0.01`), el registro de eventos y el lanzamiento automatico de `scripts/generate_fire_graphs.py`.
  - `sim/core/SimulationLogWriter.gd` mantiene `append_event()`.
  - `scripts/generate_fire_graphs.py` sigue parseando eventos y anotando inflexiones/FED.
- La corrida mas reciente sigue mostrando el problema principal abierto: acumulacion extrema de CO2/FED en edificio cerrado y propagacion amplia a casi todas las salas.

## Lectura rapida de la arquitectura

### Entrada principal
- `Main.gd` solo orquesta:
  - lee `BuildingModel` y `SimulationEngine`
  - avanza `engine.step(delta)`
  - reenvia el estado al HUD y al visualizador
- La fisica sigue concentrada en `SimulationEngine.gd` y sus subsistemas (`ThermalSystem`, `GasExchangeSystem`, `CombustionSystem`, `FireSpreadSystem`, `GlassFailureSystem`).

### Estado del escenario base
- `sim/templates/BuildingTemplate.gd` define una vivienda simple de 6 salas:
  - `0=Salon`, `1=Pasillo`, `2=Dormitorio1`, `3=Dormitorio2`, `4=Cocina`, `5=Bano`
- En `create_simple_house()`:
  - las puertas interiores arrancan abiertas
  - la puerta principal al exterior arranca cerrada
  - todas las ventanas exteriores arrancan cerradas
- Esto deja un caso base muy acoplado por interior y con muy poca descarga al exterior si no hay interaccion del usuario.

## Lo confirmado en codigo

### Registro y graficas
- `SimulationEngine._detect_and_log_opening_events()` sigue registrando cambios de puertas/ventanas usando `_prev_open_fracs`.
- `SimulationEngine._on_sim_finished()` y `_exit_tree()` siguen escribiendo `sim_end` y lanzando el generador de graficas.
- `scripts/generate_fire_graphs.py` sigue:
  - priorizando `sim_log.txt` del proyecto si existe
  - parseando lineas `EVENT ...`
  - generando graficas por habitacion en `graphs/<timestamp>/`

### Transporte y purga de especies
- `GasExchangeSystem.gd` elimina CO, CO2 y humo por infiltracion con:
  - `ach_rate = ach_infiltration / 3600.0`
- Existe purga extra por aperturas exteriores:
  - `_compute_outside_species_purge_fraction(...)`
  - solo actua si hay comunicacion abierta al exterior
- Existen terminos de limpieza post-incendio, pero en `SimulationEngine.gd` siguen exportados en cero:
  - `smoke_settling_base_per_s = 0.0`
  - `smoke_settling_bonus_per_s = 0.0`
  - `co_postfire_purge_base_per_s = 0.0`
  - `co_postfire_purge_bonus_per_s = 0.0`
- Con ventanas/puerta exterior cerradas, la depuracion de especies depende casi por completo de `ach_infiltration`.

### Acoplamiento termico interior
- `ThermalSystem.gd` sigue aplicando intercambio convectivo entre salas a traves de aperturas interiores abiertas usando `doorway_heat_exchange_coeff = 0.26`.
- La relajacion de `layer_150c_m` confirmada en el motor sigue siendo la ajustada el 22 abril:
  - `layer_150c_relax_down_per_s = 0.05`
  - `layer_150c_relax_up_per_s = 0.01`

## Evidencia del log actual
- Fichero revisado: `sim_log.txt` en la raiz del proyecto.
- El log termina con:

```text
EVENT t=1806.7 type=sim_end forced
```

- No aparecen eventos de:
  - `door_open`
  - `door_close`
  - `window_open`
  - `window_close`
  - `glass_break`

- Lectura del final de la corrida (`TIME=1800.1 s`):
  - `ROOM 0 (Salon)`: `HRR=120.00 kW`, `CO2=112549 ppm`, `FED=340.854`
  - `ROOM 1 (Pasillo)`: `HRR=25.05 kW`, `Up=128.70 C`, `CO2=109859 ppm`, `FED=338.002`
  - `ROOM 2 (Dormitorio1)`: `HRR=80.00 kW`, `CO2=112593 ppm`, `FED=346.351`
  - `ROOM 3 (Dormitorio2)`: `HRR=72.01 kW`, `CO2=114129 ppm`, `FED=355.290`
  - `ROOM 4 (Cocina)`: `HRR=100.00 kW`, `CO2=113416 ppm`, `FED=338.325`
  - `ROOM 5 (Bano)`: `HRR=16.00 kW`, `CO2=97546 ppm`, `FED=312.903`

## Interpretacion actual
- La calibracion del 22 abril sigue aplicada, pero la corrida actual no muestra una mejora suficiente en terminos de tenabilidad global.
- La ausencia de eventos de apertura sugiere una simulacion cerrada de punta a punta.
- Con el escenario base, eso significa:
  - fuerte propagacion interior por puertas abiertas
  - casi nula ventilacion al exterior
  - purga de CO2/CO dominada por `ACH`, que parece demasiado debil para estos niveles de produccion/acumulacion
- El problema ya detectado el 22 abril sigue vigente y hoy queda reforzado por el log mas reciente.

## Riesgos abiertos

### Alta prioridad
- `CO2/FED` siguen fuera de rango plausible en corrida cerrada.
- La depuracion exterior de especies no entra en juego si el usuario no abre ninguna salida al exterior.
- El caso base parte con demasiada conectividad interior para evaluar tenabilidad local del cuarto de origen de forma aislada.

### Media prioridad
- Revisar si la transferencia termica por puertas abiertas esta acelerando en exceso el calentamiento del pasillo y la ignicion secundaria.
- Revisar si la semantica de `SmokeLayer=0.00` en fases avanzadas sigue siendo la esperada (habitacion completamente tomada por humo) o si conviene mejorar su lectura en HUD/log.

### Baja prioridad
- Mantener alineados los documentos de sesion con los casos de validacion para distinguir mejor:
  - corrida interactiva base
  - casos automatizados de `sim/validation`

## Proxima sesion recomendada
1. Ejecutar un caso controlado y comparar contra el estado del 22 abril:
   - `living_room_hallway`
   - `postfire_decay`
   - corrida interactiva base
2. Instrumentar balance de masa de `CO2` por sala para separar:
   - produccion por combustion
   - salida por `ACH`
   - salida por aperturas exteriores
   - intercambio entre salas
3. Decidir si el escenario base debe seguir arrancando con todas las puertas interiores abiertas o si conviene un preset mas conservador para pruebas humanas.

## Comandos utiles

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_case.ps1 -CaseName living_room_hallway
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_case.ps1 -CaseName postfire_decay
Get-Content .\sim_log.txt -Tail 40
Select-String -Path .\sim_log.txt -Pattern '^EVENT'
```
