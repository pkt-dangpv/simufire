# Simufire - Estado de sesion 2026-05-03

## Resumen corto

Se trabajo en dos frentes:

1. Auditoria y salida de `sim_log.csv`.
2. Primer visualizador 3D basico editable desde Godot, integrado en la escena activa.

## Auditoria de `sim_log.csv`

Resultado de auditoria:

- CSV estructuralmente sano: 22 columnas, 618 filas de datos, sin filas mal formadas.
- Sin encabezados duplicados.
- Sin valores faltantes.
- Sin formulas literales ni errores tipo Excel (`#REF!`, `#DIV/0!`, etc.).
- Tipos numericos parsean correctamente.
- Sin duplicados por `(time_s, room_id)`.
- Cada instante tiene las 6 habitaciones.

Puntos observados:

- `ventilation_response_factor` estaba siempre a `0.0`.
- `temp_at_0_9m_c` era identica a `temp_lower_c` en todas las filas.
- `co_upper_ppm` podia ser menor que `co_ppm` en varias filas.
- Algunos intervalos `time_s` no eran exactamente 10.0 s por redondeo/final de ejecucion.
- Valores extremos de incendio parecian fisicamente plausibles pero a revisar contra calibracion.

No se reescribio `sim_log.csv`.

## CSV junto a graficas

Cambio solicitado: al pulsar `Parar + graficas`, cuando el usuario elige carpeta para guardar graficas, tambien se copia el CSV alli.

Archivos tocados:

- `sim/core/SimulationLogWriter.gd`
  - Anade `resolve_csv_file_path()`.
- `sim/core/SimulationEngine.gd`
  - Pasa `--csv <ruta>` y `--copy-csv` a `scripts/generate_fire_graphs.py`.
- `scripts/generate_fire_graphs.py`
  - Anade argumentos `--csv` y `--copy-csv`.
  - Copia `sim_log.csv` en la carpeta final de graficas junto a `sim_log.txt`.

Verificado:

- `python .\scripts\generate_fire_graphs.py --help` muestra `--csv` y `--copy-csv`.
- Godot headless carga el proyecto con `--quit`.

## Visualizador 3D

Se creo `view/Visualizer3D.gd` con clase `Visualizer3D`.

Objetivo de esta primera version:

- Vista 3D basica en paralelo al 2D.
- Editable desde el inspector de Godot mediante `@export`.
- No reemplaza el visualizador 2D.

Elementos que genera:

- Suelos por estancia.
- Paredes extruidas.
- Marcadores de puertas y ventanas.
- Etiquetas de estancia.
- Humo.
- Fuego animado segun `hrr_kw`.
- Temperatura como color en paredes.

La integracion importante esta en la escena activa:

- `scenes/SimulationScene.tscn`
  - Anade `World3D`.
  - Anade `World3D/Visualizer3D`.
  - Anade contenedores editables:
    - `Rooms`
    - `Openings`
    - `Atmosphere`
    - `Labels`
    - `CameraRig`
    - `Camera3D`
    - `Sun`
    - `FillLight`
  - Anade boton `BtnView3D` con texto `Vista 3D`.

Tambien se habia integrado inicialmente en `main.tscn`, pero esa no es la escena de simulacion que abre el menu. La escena activa es:

- `project.godot`: `run/main_scene="res://scenes/MainMenu.tscn"`
- `scenes/MainMenu.gd`: abre `res://scenes/SimulationScene.tscn`

## Cambios de control/UI

Archivos tocados:

- `Main.gd`
  - Detecta `World3D/Visualizer3D`.
  - Mantiene `view_3d_enabled`.
  - Alterna visibilidad entre 2D y 3D.
  - Pasa `view_3d_enabled` al HUD.

- `ui/hud.gd`
  - Anade senal `view_3d_toggled(enabled: bool)`.
  - Anade soporte para `BtnView3D`.
  - Cambia el texto entre `Vista 3D` y `Vista 2D`.

## Ajustes visuales 3D posteriores

Se hicieron correcciones porque la primera vista salia demasiado roja:

- Las aperturas cerradas ya no son rojas; ahora son grises.
- La temperatura ya no se dibuja como capa horizontal.
- `show_hot_layer` y `show_layer_150c` quedan desactivados por defecto.
- La temperatura se pinta en las paredes con `hot_wall_color`.
- El fuego se dibuja como llama 3D animada, con nucleo y brillo.
- El fuego crece/decae suavemente con `hrr_kw`.
- El humo se suaviza con `smoke_visual_depth_m`.
- El humo debe nacer como capa fina pegada al techo y engrosar hacia abajo.
- Los nombres de las estancias pasan al suelo.
- La rotacion de camara se movio de `_unhandled_input` a `_input`.
- La camara rota con clic izquierdo arrastrando sobre el modelo 3D.
- La rueda hace zoom sobre el modelo.
- Se mantiene clic derecho como alternativa de rotacion.

## Verificaciones realizadas

Comandos Godot que cargaron:

- `Godot_v4.6.2-stable_win64_console.exe --headless --path ... --quit`
- `Godot_v4.6.2-stable_win64_console.exe --headless --path ... --import --quit`

Notas:

- La ejecucion completa de escena en headless con `--scene ... --quit-after` dio problemas del entorno/engine al escribir logs en `user://logs`, no se uso como validacion final.
- Hay errores conocidos de entorno al hacer `--import --quit`, como no poder guardar `editor_settings-4.6.tres`; no parecen relacionados con los cambios.

## Pendiente recomendado

1. Probar visualmente desde el editor o ejecutando la app normal:
   - Boton `Vista 3D` visible en la escena de simulacion.
   - Arrastre con clic izquierdo rota la maqueta.
   - Humo nace desde el techo y baja de forma progresiva.
   - Fuego crece/decae con HRR.
   - Paredes muestran temperatura sin tapar el humo.

2. Si la rotacion con clic izquierdo sigue fallando:
   - Revisar si algun `Control` del HUD consume toda la pantalla.
   - Como parche posible, aceptar siempre drag izquierdo en 3D sin filtrar por hit sobre el modelo.

3. Mejoras visuales proximas:
   - Sustituir paredes macizas por paredes con huecos reales en puertas/ventanas.
   - Anadir seleccion de estancia en 3D.
   - Separar materiales como recursos `.tres` para editarlos aun mas comodamente desde Godot.
   - Mejorar fuego con billboard/particulas si se quiere mas presencia visual.
