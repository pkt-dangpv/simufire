# Simufire - Estado de sesion
**Ultima actualizacion**: 26 abril 2026

## Objetivo de esta sesion
- Ejecutar varias simulaciones abriendo y cerrando ventanas.
- Comparar comportamiento del incendio en salon, cocina, dormitorios y caso Ghanekar.
- Detectar problemas de motor/reportes y dejar casos reproducibles.

## Casos nuevos
- `window_matrix_salon_confined`: salon sin ventanas abiertas.
- `window_matrix_salon_pulse`: salon, ventana abre 180 s, cierra 540 s, reabre 50% a 720 s.
- `window_matrix_cocina_pulse`: cocina, ventana abre/cierra y puerta principal abre a 650 s.
- `window_matrix_dormitorios_crossvent`: dormitorio 1 con ventilacion cruzada dormitorio 2 y salon.
- `window_matrix_salon_spread_enabled`: propagacion realista activada.
- `window_matrix_salon_spread_stress`: propagacion forzada con umbral bajo para verificar ignicion secundaria.
- `window_matrix_ghanekar_remote`: dormitorio Ghanekar con cierre/reapertura de ventana de origen y aperturas remotas.

## Cambios aplicados
- `CombustionSystem.gd`:
  - evita contar dos veces el proxy heredado cuando una sala ya tiene objetos combustibles explicitos;
  - expone el combustible remanente del proxy para reportar incendios ya extinguidos.
- `SimulationStateBuilder.gd`:
  - `remaining_fuel_MJ` conserva el remanente real del fuego despues de una extincion;
  - las salas no incendiadas reportan su combustible explicito remanente, no `0`.
- `SimulationEngine.gd`:
  - en modo `--validation-case`, `_exit_tree()` ya no escribe `sim_end forced` al final de logs normales.
- `FireSpreadSystem.gd`:
  - se integro un bloque de propagacion por precalentamiento/pirolisis que estaba muerto despues de un `return`.
- `ThermalSystem.gd` / `SimulationEngine.gd`:
  - se agrego una perdida radiativa no lineal de capa superior basada en Stefan-Boltzmann;
  - `max_upper_temp_c = 900 C` queda como failsafe numerico, no como disipador fisico primario;
  - se calibro la radiacion como guardarrail de alta temperatura: empieza en 880 C, con emisividad 0.90 y area efectiva 1.10.
- `RoomModel.gd`, `SimulationStateBuilder.gd`, `SimulationLogWriter.gd`, `CaseRunner.gd`:
  - se agregaron `temp_upper_raw_c`, `temp_upper_clamped`, tiempo/conteo de clamp y `upper_radiative_loss_kw`;
  - los logs ahora muestran `RawUp`, `Cap`, `CapT` y `Rad`;
  - los reportes registran pico raw, perdida radiativa maxima y tiempo acumulado de clamp.
- `CombustionSystem.gd`, `FireSpreadSystem.gd`, `SimulationStateBuilder.gd`, `SimulationLogWriter.gd`, `CaseRunner.gd`:
  - los objetos explicitos de cada habitacion ya se calientan, acumulan exposicion, pasan por `heating` / `pyrolyzing` / `flaming` y reportan combustible remanente;
  - la radiacion de capa caliente/humo hacia objetos usa flujo radiativo no lineal y un factor de participacion de humo;
  - el incendio activo de sala reparte consumo y HRR entre objetos explicitos sin cambiar la envolvente HRR calibrada;
  - propagacion y autoignicion pasiva usan el objeto dominante real, no solo un proxy de sala;
  - los logs/reportes agregan objeto dominante (`Obj`, estado, exposicion y MJ remanentes).
- `editor/ScenarioEditor.tscn`, `editor/ScenarioEditor.gd`, `editor/EditorGrid.gd`, `editor/ScenarioSerializer.gd`, `editor/ObjectLibrary.gd`:
  - se creo un editor 2D V1 separado del simulador con herramientas `Select`, `Room`, `Door`, `Window`, `Object`, `Ignite` y `Delete`;
  - el editor guarda/carga JSON, exporta un template runtime y usa una libreria inicial de objetos combustibles concretos (`sofa`, `bed`, `table`, `curtain`, `wardrobe`, `kitchen_unit`);
  - el serializer convierte entre datos JSON y tipos runtime (`Rect2`, `Vector2`) compatibles con `BuildingModel.load_template_data(data)`.
- `FuelObjectModel.gd`, `OpeningModel.gd`, `BuildingModel.gd`:
  - se agregaron campos opcionales de posicion/tamano/rotacion de objetos, `room_id` y `offset_m` en aperturas;
  - `BuildingModel.load_template_data(data)` acepta rectangulos/vectores en formato JSON y conserva los nuevos datos visuales sin afectar templates existentes.

## Verificacion ejecutada
Comando base:
`Godot_v4.6.2-stable_win64_console.exe --headless --path simufire -- --validation-case <case>`

Resultados principales:

| Caso | Peak HRR | Peak T upper | Peak radiacion | Clamp | Humo generado | Humo venteado | Salas con HRR |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| salon_confined | 1317.0 kW | 887.4 C | 745.7 kW | 0.0 s | 4.02 kg | 1.47 kg | R0 |
| salon_pulse | 2379.8 kW | 892.8 C | 3238.9 kW | 0.0 s | 34.81 kg | 30.66 kg | R0 |
| cocina_pulse | 1597.6 kW | 893.1 C | 2622.6 kW | 0.0 s | 21.44 kg | 15.94 kg | R4 |
| dormitorios_crossvent | 1355.3 kW | 891.8 C | 3230.3 kW | 0.0 s | 18.30 kg | 15.33 kg | R2 |
| salon_spread_enabled | 2379.8 kW | 891.2 C | 2578.2 kW | 0.0 s | 36.43 kg | 31.65 kg | R0 |
| salon_spread_stress | 2379.8 kW | 891.2 C | 2578.2 kW | 0.0 s | 36.85 kg | 31.97 kg | R0, R1 |
| ghanekar_remote | 1425.6 kW | 895.0 C | 1945.7 kW | 0.0 s | 15.89 kg | 9.85 kg | R0 |

## Observaciones
- Abrir la ventana del salon cambia el regimen: el peak HRR sube de ~1317 kW a ~2380 kW y el incendio sigue activo a 900 s.
- En confinamiento, el salon se extingue por falta de ventilacion a ~475.7 s.
- Cocina y dormitorio responden como casos ventilados moderados: siguen activos a 900 s, pero con HRR final menor que el salon.
- En `salon_spread_enabled` no hay ignicion secundaria: el pasillo acumula exposicion, pero no alcanza el umbral de 45 s.
- En `salon_spread_stress`, el pasillo prende correctamente y alcanza ~328.7 kW, validando que la ruta de propagacion funciona bajo condiciones forzadas.
- Ningun caso `window_matrix_*` registra `Cap=Y`; no aparecieron `ERROR`, `WARNING`, `SCRIPT ERROR`, `Invalid` ni `Failed` en sus logs.
- En `salon_spread_stress`, `pasillo_textiles` piroliza desde ~130.6 s y termina `flaming`; el mensaje de propagacion conserva ahora la exposicion acumulada real (~18.0 s en el caso stress).
- En `living_room_hallway`, el pasillo ya muestra `pasillo_textiles` como objeto dominante `pyrolyzing` sin romper baseline.

## Suite corta posterior
- `living_room_hallway`: PASS
- `layer150_tenability`: PASS
- `postfire_decay`: PASS
- `tmp_r2_window_open_start`: PASS

## Verificacion del editor V1
- Carga headless de `res://editor/ScenarioEditor.tscn`: PASS, sin errores de script.
- Smoke test editor-simulador: PASS. Se creo un escenario con 2 salas, puerta, ventana y sofa; `ScenarioSerializer.to_runtime_template(...)` cargo correctamente en `BuildingModel.load_template_data(...)`.
- Revalidacion posterior del simulador: `living_room_hallway` PASS.

## Problemas detectados / pendientes
1. La saturacion `900 C` queda resuelta en la matriz actual: todos los casos quedan entre 887.4 C y 895.0 C con `Clamp=0`.
2. La radiacion implementada es una aproximacion concentrada de alta temperatura, no un balance completo pared-gas-superficies como CFAST/FDS. Pendiente: comparar contra CFAST o FDS en un escenario equivalente.
3. La propagacion realista queda cerca pero no prende sala secundaria; revisar si el umbral de exposicion o el acoplamiento de pirolisis pasillo-salon es demasiado conservador.
4. El motor aun mantiene un modelo hibrido: fuego monolitico por sala + objetos combustibles explicitos. Ya no se duplican metricas, pero falta decidir si los objetos deben consumirse fisicamente en el incendio principal.
5. En esta sesion `git` no estaba en PATH y `rg` dio acceso denegado; se inspecciono con PowerShell.
6. El editor V1 todavia no integra un flujo de lanzamiento interactivo del simulador desde la UI; por ahora exporta el template runtime para cargarlo desde el motor.

## Nota bibliografica sobre el clamp
- NIST CFAST modela incendios compartimentados como capas de gases y resuelve balances de masa/energia; la documentacion tecnica explicita transferencia convectiva y radiativa entre capas, fuego y superficies.
- La radiacion se modela con dependencia de temperatura absoluta a la cuarta potencia (Stefan-Boltzmann) y emisividad/area efectiva. Por eso un limite duro de temperatura no es una explicacion fisica: la fisica debe entrar como perdida/redistribucion de energia.
- NIST Fire Dynamics situa el flashover con gases por encima de ~600 C y habitaciones en flashover cerca de ~1000 C; por tanto 900 C es plausible como limite numerico alto, pero no como ley fisica universal.

Fuentes consultadas:
- NIST SP 1026, CFAST Technical Reference Guide: https://www.nist.gov/publications/cfast-consolidated-model-fire-growth-and-smoke-transport-version-6-technical-reference
- NIST Fire Dynamics: https://www.nist.gov/el/fire-research-division-73300/firegov-fire-service/fire-dynamics
- Yuen & Chow (2004), `The role of thermal radiation on the initiation of flashover in a compartment fire`: https://doi.org/10.1016/j.ijheatmasstransfer.2004.05.017

## Artefactos generados
- Casos: `sim/validation/cases/window_matrix_*.json`
- Reportes: `sim/validation/reports/window_matrix_*.json`
- Logs: `sim/validation/reports/window_matrix_*.log`
- Editor V1: `editor/ScenarioEditor.tscn`
- Export runtime por defecto: `user://last_editor_runtime_template.json`
