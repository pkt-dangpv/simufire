# Plan de trabajo — Arreglos del sistema visual

**Fecha:** 2026-07-15 · **Base:** [AUDITORIA_VISUAL_2026-07-15.md](AUDITORIA_VISUAL_2026-07-15.md)
**Regla del plan:** el motor (`sim/`) está en desarrollo activo en paralelo. Las tareas que tocan `SimulationEngine.gd` están marcadas ⚠️ MOTOR y agrupadas para hacerse en una ventana de coordinación única (o detrás de una interfaz nueva), nunca entremezcladas con el resto.

**Estado 2026-07-15:** implementación completa. T1.2, T1.3 y T5.6 se
cerraron en la ventana coordinada del motor. Queda únicamente la pasada manual
del checklist en ambas resoluciones; los gates automáticos están verdes.

Convención de IDs: referencia al hallazgo de la auditoría (G = gráficas, V2 = visor 2D, V3 = visor 3D, FP = primera persona).

---

## Resumen de fases

| Fase | Objetivo | Tareas | Toca motor | Esfuerzo est. |
|------|----------|--------|------------|---------------|
| 0 | Preparación y red de seguridad | T0.1–T0.3 | No | 0.5 d |
| 1 | Gráficas: que dejen de "fallar bastante" | T1.1–T1.6 | ⚠️ 2 tareas | 2–3 d |
| 2 | Picking/drag 3D multi-planta | T2.1–T2.3 | No | 1–1.5 d |
| 3 | Correcciones visuales rápidas (2D/3D/FP) | T3.1–T3.5 | No | 1 d |
| 4 | Rendimiento y deuda de duplicación | T4.1–T4.5 | No | 2–3 d |
| 5 | Pulido y robustez | T5.1–T5.6 | ⚠️ 1 tarea | 1–2 d |

Orden recomendado: 0 → 1 → 2 → 3. Las fases 4 y 5 son independientes entre sí y pueden intercalarse o posponerse.

---

## Fase 0 — Preparación (sin cambios funcionales)

### T0.1 Rama de trabajo y escenario de regresión visual
- Crear rama `fix/visual-audit` desde `main` para TODO este plan (el motor sigue en su propia línea; rebases frecuentes).
- Elegir/crear un escenario de referencia multi-sala y **multi-planta** (necesario para validar la Fase 2) y dejar anotados los pasos de humo/flashover esperados.

### T0.2 Checklist de verificación manual
Documento corto (puede ser sección de este mismo plan) con la pasada de humo: abrir 2D → 3D → FP → salir con gráficas → salir sin gráficas → volver al editor, en dos resoluciones (1280×720 y 1920×1080 con escala 125 %). Es el criterio de aceptación transversal de las fases 1–3.

### T0.3 Sacar `graphs/` del proyecto Godot (G-11)
- Mover el default de salida a una carpeta fuera de `res://` (p. ej. `user://graphs` o `<proyecto>/../simufire-output/graphs`) **o** añadir `graphs/.gdignore` para que Godot no importe los PNGs.
- Añadir `.matplotlib-cache/` a `.gitignore` si no está.
- *Aceptación:* generar gráficas no crea ficheros `.png.import` nuevos.

---

## Fase 1 — Pipeline de gráficas (prioridad máxima)

> Objetivo de la fase: pulsar "Salir y guardar + gráficas" produce una espera con feedback, una sola ventana bien dimensionada, con todos los ficheros en una carpeta; "salir sin gráficas" no genera nada.

### T1.1 🔴 G-2 — Arreglar dimensionado de las ventanas de gráficas y resumen técnico
**Ficheros:** `Main.gd` (solo vista, sin motor).
**Decisión previa (elegir una):**
- **(a) Ventanas nativas:** poner `_graphs_view_window` y `_technical_summary_window` como no embebidas (`Viewport.gui_embed_subwindows=false` en su ancestro o marcar las ventanas `force_native`/`transient=false` según versión de Godot). Ganan resize/maximizar del SO.
- **(b) Seguir embebidas pero dimensionar bien:** calcular tamaño en coordenadas del viewport estirado (`get_viewport().get_visible_rect().size`) en lugar de `get_window().size`, y bajar `min_size` a algo que quepa en 1280×720 (p. ej. 960×560).

Recomendación: **(a)** para el visor de gráficas (contenido grande, se beneficia de pantalla completa), **(b)** para el resumen técnico.
- Revisar `_graph_column_count()` y `_graph_texture_base_size()` para que usen el mismo espacio de coordenadas que la ventana.
- *Aceptación:* en 1280×720 y en 1920×1080 con escala de Windows 125 %, ambas ventanas se ven completas, con barra de título accesible y grid de 1–2 columnas correcto.

### T1.2 ✅ G-1 — Generación sin congelar la UI ⚠️ MOTOR (completada)
**Ficheros:** `SimulationEngine.gd` (`_launch_graph_generator`), `Main.gd`.
**Implementado:** proceso Python no bloqueante con PID y exit code, marcador
`latest_graphs_dir.txt` limpiado antes del lanzamiento, polling cada 0.5 s,
overlay modal, timeout de 60 s y validación de la carpeta resultante. El
resumen técnico permanece en cola hasta cerrar el visor de gráficas.
**Enfoque de mínima invasión al motor:** no reescribir el flujo del engine; cambiar solo el modo de espera:
1. En `Main._on_graphs_dir_selected`: mostrar inmediatamente un overlay modal "Generando gráficas…" (bloquea input, con spinner o texto animado).
2. Lanzar la generación con `OS.create_process` (ya existe la rama async) y **sondear** la finalización desde `Main` (timer 0.5 s): fin = aparece/actualiza `user://latest_graphs_dir.txt` con mtime posterior al lanzamiento, o el PID muere (`OS.is_process_running`).
3. Timeout defensivo (p. ej. 60 s) → mensaje de error con instrucción manual.
4. Alternativa si se prefiere no tocar el engine ahora: mover la llamada bloqueante a un `Thread` de Godot en `Main` que invoque `engine.stop_and_generate_graphs` — **descartada** si el motor no es thread-safe; validar antes.
- *Coordinación:* avisar en la línea del motor de que `_launch_graph_generator` cambia la semántica de `wait_for_finish`; es un diff pequeño y localizado (≈20 líneas).
- *Aceptación:* durante la generación se puede mover el ratón, la ventana no entra en "no responde", y al terminar se abre el visor. Si Python falta, el error aparece en <2 s con mensaje accionable.

### T1.3 ✅ G-3 — Respetar "salir sin gráficas" ⚠️ MOTOR (completada)
**Ficheros:** `SimulationEngine.gd` (`_exit_tree`), `Main.gd`, `hud.gd` (nada o casi nada).
**Implementado:** `suppress_exit_graphs()` se llama antes de volver al menú o
al editor. Cerrar la ventana o detener desde el editor conserva la generación
automática existente.
- Añadir en el engine un método/flag público `suppress_exit_graphs()` (o `set_exit_graphs_enabled(false)`).
- `Main._on_exit_without_graphs_requested` y `_on_return_to_editor_requested` lo activan antes de `change_scene_to_file`.
- `_exit_tree` lo consulta antes de `_finish_and_launch_graphs("forced")`. El comportamiento actual (generar al cerrar la ventana del juego / stop del editor) se conserva.
- *Coordinación:* mismo commit/ventana que T1.2 para tocar el motor una sola vez.
- *Aceptación:* "Salir sin guardar" y "Volver al editor" no crean carpeta en `graphs/` ni escriben `events.json`/`summary.json`; cerrar la ventana del juego sí sigue generando.

### T1.4 🟠 G-4 + G-5 — Una carpeta única y una sola ventana a la vez
**Ficheros:** `Main.gd`, `scripts/generate_fire_graphs.py` (script Python, fuera del motor).
- **Carpeta única:** que el script escriba también `summary.json`/`events.json`… no — mejor al revés, sin tocar el engine: el script ya conoce `out_root/<timestamp>`; hacer que `Main` (tras generar, cuando conoce `get_last_graphs_dir()`) **mueva/copie** `summary.json` y `events.json` de la raíz elegida a la carpeta timestamped, y que la pestaña "Archivos" (`_build_summary_files_tab`) liste esa carpeta final.
  - Alternativa más limpia (si se abre la ventana ⚠️ MOTOR de T1.2/T1.3): pasar a `_write_export_json` el subdirectorio final. Decidir según apetito de riesgo.
- **Ventanas:** encadenar, no superponer: al cerrar el visor de gráficas se ofrece/abre el resumen técnico (o pestaña "Resumen" dentro del propio visor de gráficas — opción preferida a medio plazo). Como mínimo: retrasar el popup del resumen hasta `close_requested` del visor.
- *Aceptación:* tras generar, existe una sola carpeta con PNGs + `sim_log.*` + `summary.json` + `events.json`; la pestaña Archivos lista rutas que existen; nunca hay dos popups simultáneos.

### T1.5 🟠 G-6 + G-7 — Fuentes de datos correctas en `generate_fire_graphs.py`
**Ficheros:** solo `scripts/generate_fire_graphs.py`.
- Si se pasa `--log` explícito y **no** se pasa `--csv`, no usar el CSV default: o ignorar CSV, o exigir que el mtime del CSV sea ≥ mtime del log (con margen) para aceptarlo; en caso contrario, log de aviso claro y usar el TXT.
- Nombre de carpeta: sustituir mtime por timestamp de ejecución (`datetime.now()`) + sufijo corto del run si está disponible; documentar que regenerar crea carpeta nueva.
- *Aceptación:* con un `sim_log.csv` viejo plantado a propósito en la raíz y CSV deshabilitado en el engine, las gráficas salen del TXT fresco y lo dicen por stdout.

### T1.6 🟡 G-8/G-9/G-10 — Robustez y pulido del visor
**Ficheros:** `scripts/generate_fire_graphs.py`, `Main.gd`.
- Python launcher: probar `py -3` como fallback de `python`; capturar stdout/stderr del proceso a `user://graphs_last_run.log` y, si exit≠0, mostrar las últimas líneas en `_show_graphs_message`.
- Orden de PNGs en el visor: orden fijo `hrr, temperaturas, capas, gases, fed_svv` (lista blanca con fallback alfabético).
- Zoom: guardar el `base_size` original una vez (no re-persistirlo en `_apply_graph_zoom`); unificar factor de zoom rueda/botones (1.25).
- Drag: gestionar el fin de arrastre dentro de la propia `Window` (conectar `gui_input` del root o `mouse_exited` del scroll) en lugar del fallback en `Main._input`.
- Parser TXT: anclar `_val` con regex `\bO2=` o buscar `" O2="`; los índices fijos pueden quedarse si el CSV es la vía principal, pero dejar comentario de contrato de formato.
- *Aceptación:* con Python del Store (alias) el error mostrado incluye la causa; el orden de gráficas es estable; zoom 100 % restaura tras resize.

---

## Fase 2 — Picking y arrastre 3D multi-planta

### T2.1 🔴 V3-1 — Rayo contra la planta correcta
**Ficheros:** `view/3d/interaction/ScreenPicking3D.gd`, `view/3d/Visualizer3D.gd` (llamadores).
- Generalizar `_floor_hit_m` a `floor_hit_at_level(camera, screen_pos, floor_level_m, …)`: intersección con el plano `y = floor_level_m * meters_to_units`.
- `room_id_at_screen_pos`: iterar los niveles de planta existentes **de arriba abajo**; para cada nivel, intersectar con su plano y comprobar solo las salas de ese nivel (`floor_level_z_m` ≈ nivel); devolver el primer acierto. Resuelve también la ambigüedad de rects solapados entre plantas.
- `is_screen_point_over_model`: aceptar acierto en cualquiera de los niveles (o simplemente el bounding en el nivel más cercano al de la cámara objetivo).
- *Aceptación:* en el escenario multi-planta de T0.1, clic en salas de planta 1 selecciona la sala correcta desde varios ángulos de cámara; clic en planta baja sigue funcionando.

### T2.2 🔴 V3-1 — Arrastre de elementos con la altura del elemento
**Ficheros:** `Visualizer3D.gd` (`_begin_element_drag`, `_update_element_drag`, `screen_to_floor_m`).
- Al iniciar el drag, capturar el `floor_level_m` del elemento (sala del objeto / víctima / player_start) y usar `floor_hit_at_level` con ese nivel durante todo el drag.
- `floor_clicked` debe emitir la posición en el plano de la sala clicada (nivel resuelto en T2.1).
- *Aceptación:* arrastrar un mueble en planta 1 lo mantiene bajo el cursor (sin deriva); igual para detectores/víctimas/player_start.

### T2.3 Verificación cruzada con el editor de escenarios
El editor (`editor/ScenarioEditor.gd`) consume estas señales de drag. Pasada manual: mover objetos en ambas plantas desde el editor y desde la simulación. Sin cambios de código esperados aquí, solo validación.

---

## Fase 3 — Correcciones visuales rápidas (independientes entre sí)

### T3.1 🟠 V2-1 — Isoterma 150 °C solo cuando exista
**Fichero:** `view/2d/Visualizer.gd` (`_draw_150c_line` y llamador).
- Guard equivalente al del humo: no dibujar si `layer_150c_m >= room_h - 0.01` (sin capa) o si `temp_upper_c < 150` (dato disponible en `rs`).
- *Aceptación:* en t=0 ninguna sala muestra línea roja; al desarrollarse el incendio aparece y desciende.

### T3.2 🟡 V2-4 — Escala de color SVV legible
**Fichero:** `view/2d/rooms/RoomStateVisuals2D.gd` (`svv_color`).
- Rampa de 4 tramos con verde para estado sano (p. ej. ≥90 % verde, 60–90 % ámbar, 20–60 % naranja, <20 % rojo; <5 % gris "agotado"). Consensuar umbrales con la semántica SVV del motor (solo colores, no cálculo).
- Separar color de FED del de SVV en `_draw_room_label` (dos colores o prefijos).
- *Aceptación:* barrido de SVV 100→0 muestra progresión monótona y distinguible.

### T3.3 🟡 V3-7 — Screenshot 3D sin HUD
**Fichero:** `view/3d/Visualizer3D.gd` (`capture_screenshot_to`).
- Ocultar `_legend_canvas` y pedir a `Main` ocultar HUD durante 1 frame (`await RenderingServer.frame_post_draw`) antes de capturar, o capturar desde un `SubViewport` dedicado si existe. Opción mínima: ocultar CanvasLayers propios + parámetro `include_hud:=false`.
- *Aceptación:* el PNG de export W-01 no contiene paneles de UI.

### T3.4 🟡 V2-3 — Fondo 2D cubriendo el viewport
**Fichero:** `view/2d/Visualizer.gd` (`_draw_background`).
- Usar `get_viewport_rect()` transformado a coordenadas locales (o un `ColorRect` de fondo bajo el Node2D y eliminar el draw_rect).
- *Aceptación:* sin huecos de fondo en ultrawide/zoom.

### T3.5 🟡 FP-3 — Datos ausentes en overlay técnico FP
**Fichero:** `view/fp/FirstPersonController.gd` (`_update_technical_overlay`).
- Sustituir el fallback 4000 ppm por "--" cuando falte la clave (helper `_fmt_or_dash(room_state, key, fmt)`).
- *Aceptación:* con un estado sin `co2_*`, el HUD muestra "CO₂ --" y no un valor plausible falso.

---

## Fase 4 — Rendimiento y deuda estructural

### T4.1 🟠 V3-2 — Eliminar el doble update y el churn de materiales
**Fichero:** `view/3d/Visualizer3D.gd`.
- Separar `_apply_selection_visuals()` en "solo tinte de selección" (barato) y dejar de llamar a `_update_openings`/`_update_room_safety_markers_3d` desde ahí; `_update_dynamic_state` ya los ejecuta.
- `_set_marker_color`: cachear el material por nodo (meta `"mat"`) y mutar `albedo_color`; crear material solo al instanciar el marcador.
- *Aceptación:* con el monitor de Godot, `Object.materials` estable durante la simulación; una sola pasada de openings/markers por `set_state` (verificable con contador temporal de debug).

### T4.2 🟠 V3-3 — Cachear poses de apertura
**Fichero:** `view/3d/Visualizer3D.gd`.
- Calcular `_opening_pose` una vez por rebuild y guardarla en `_opening_items[index]["pose"]` (ya se hace para curtains con `curtain_pose` — extender y reutilizar en spill y clearances). Cache de `get_room_rects_m()` por rebuild también.
- *Aceptación:* mismas imágenes antes/después (diff visual del escenario de referencia); tiempo de `_update_dynamic_state` reducido (medir con `Time.get_ticks_usec` en debug).

### T4.3 🟠 V2-2 — Cachear `_get_draw_transform()` en 2D
**Fichero:** `view/2d/Visualizer.gd`.
- Calcularlo una vez al inicio de `_draw()` (y en los handlers de input) y pasarlo/almacenarlo en un miembro `_frame_tf`; invalidar por cambio de viewport o de planta.
- *Aceptación:* render idéntico; sin llamadas repetidas (grep de `_get_draw_transform()` dentro de bucles = 0).

### T4.4 🟡 V3-4 — Retirar `smoke_edge` muerto (o revivirlo)
**Decisión:** si el "edge" de capa de humo no va a usarse, eliminar creación, item y `_apply_smoke_edge_shader`; si se quiere el efecto, conectarlo en `_update_smoke_volume` detrás de un export `show_smoke_layer_edge` (off por defecto).
- *Aceptación:* sin nodos `SmokeLayerEdge_*` huérfanos en el remote tree (o efecto funcionando bajo flag).

### T4.5 🟠 FP-1 — Unificar geometría FP ↔ 3D (la tarea grande; trocear)
No intentar el big-bang. Plan incremental:
1. **Extraer utilidades puras compartidas** a `view/3d/geometry/` (o `view/common/`): `_subtract_rect`, `_split_rect_by_voids`, `_rect_same`, `_stair_*` (span, ramp width, landing depth, point along run, void rect). Son funciones estáticas puras — riesgo bajo, elimina los duplicados literales.
2. FirstPersonController y Visualizer3D consumen esas utilidades (borrar copias locales).
3. (Opcional, más adelante) Extraer un `StairGeometryBuilder` que devuelva listas de cajas (tamaño/pos/rot) y que cada visor materialice con sus materiales/colisiones propios.
- *Aceptación paso 1–2:* escenario con escalera recta y con switchback se ve **idéntico** en 3D y FP antes/después (capturas comparadas); un solo sitio define los umbrales 0.72/1.05/0.18/179°.

---

## Fase 5 — Pulido y robustez

### T5.1 🟡 V3-6 — Transparencias: prioridades de render
Asignar `render_priority` escalonado (suelo < hot/l150 < gradiente < humo < máscara techo < curtains) y probar ángulos problemáticos. Si persisten artefactos, considerar `depth_draw_opaque` en las capas finas.
- *Aceptación:* órbita completa alrededor de una sala con humo denso sin popping evidente entre capas.

### T5.2 🟡 V3-5 — Leyenda 3D incremental
Reconstruir filas solo cuando cambie el conjunto de entradas (hash de flags), no en cada `set_state`.

### T5.3 🟡 FP-2 — Deduplicar consultas por frame en FP
Resolver `_find_current_room_id()` una vez por physics frame (miembro `_frame_room_id`) y reutilizarlo en overlay/HUD/smoke view; cachear `get_room_rects_m()` por rebuild.

### T5.4 🟡 V3-8 — `free()` → `queue_free()` defensivo
En `_clear_container`/`_rebuild_fuel_object_shape`/`_prune_marker_nodes` donde se libere durante updates de estado. Revisar que nada lea el nodo en el mismo frame tras liberarlo.

### T5.5 ℹ️ V2-5 — Decidir el minimapa en FP
O se muestra el minimapa en modo FP (y `_draw_live_player` cobra sentido), o se elimina ese código. Decisión de producto; implementación trivial en `Main._sync_view_mode`.

### T5.6 ✅ G-9 — Preflight de Python ⚠️ MOTOR (completada)
Chequeo cacheado al entrar en la escena de simulación. Prueba `python` y el
fallback Windows `py -3`; si ninguno está disponible, muestra un aviso
persistente en el HUD y la generación falla inmediatamente con mensaje
accionable. Se omite en modo validación.

---

## Ventana de coordinación con el motor (resumen ⚠️)

**CERRADA 2026-07-15.** Las tres tareas obligatorias se implementaron juntas,
sin tocar sistemas físicos, baselines, tolerancias ni casos de validación.

Un único paquete de cambios en `sim/core/SimulationEngine.gd`, idealmente en un solo commit coordinado con la línea del motor:
1. T1.2 — `_launch_graph_generator`: modo async con notificación de fin (≈20 líneas).
2. T1.3 — flag `suppress_exit_graphs` consultado en `_exit_tree` (≈6 líneas).
3. (Opcional) T1.4 — `_write_export_json` al subdirectorio final. Si genera fricción, usar la variante move/copy desde `Main` que no toca el motor.
4. (Opcional) T5.6 — preflight de Python.

Todo lo demás del plan **no toca `sim/`**.

---

## Verificación final (gate de cierre)

1. Pasada completa del checklist T0.2 en 2 resoluciones.
2. Escenario multi-planta: picking, drag y gráficas OK.
3. `git status` limpio de artefactos (`.png.import`, `.matplotlib-cache`).
4. Suite de validación del motor intacta (no debería verse afectada: solo `Main.gd`, `view/`, `ui/`, `scripts/generate_fire_graphs.py` y los puntos ⚠️ acordados).
