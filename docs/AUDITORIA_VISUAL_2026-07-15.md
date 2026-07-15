# Auditoría del sistema visual — SimuFire

**Fecha:** 2026-07-15 · **Alcance:** visor 2D (`view/2d`, `ui/Minimap2D.gd`), visor 3D (`view/3d`), primera persona (`view/fp`), pipeline de gráficas finales (`Main.gd`, `SimulationEngine.gd`, `scripts/generate_fire_graphs.py`).
**Solo lectura:** no se ha tocado ni una línea de código. El motor (`sim/`) queda fuera del alcance salvo los puntos de integración con la vista.

Severidades: 🔴 alta (fallo visible/comportamiento roto) · 🟠 media (fallo en escenarios concretos o deuda con impacto) · 🟡 baja (pulido/robustez) · ℹ️ nota.

---

## 1. Gráficas al final de la simulación (lo que más falla)

### 🔴 G-1. La generación bloquea el hilo principal — la app se "congela"
`Main._on_graphs_dir_selected()` ([Main.gd:441](../Main.gd)) llama a `engine.stop_and_generate_graphs(...)` que acaba en `OS.execute("cmd.exe", ["/c","python", ...])` **síncrono** ([SimulationEngine.gd:3537-3545](../sim/core/SimulationEngine.gd)). Todo el proceso de matplotlib (6 salas × 5 PNGs ≈ varios segundos, más si es la primera importación de matplotlib, que puede tardar 5-10 s) corre con la UI congelada, sin spinner ni mensaje. Para el usuario es indistinguible de un cuelgue, y si hace clic durante la espera Windows marca la ventana como "no responde".

### 🔴 G-2. Ventana de gráficas embebida + `stretch canvas_items` → tamaño/recorte erróneos
`project.godot` usa `window/stretch/mode="canvas_items"` con viewport base **1280×720**. Godot embebe las `Window` hijas por defecto (`embed_subwindows=true`), y las ventanas embebidas viven en el **espacio de coordenadas estirado del viewport**, no en píxeles de SO. Pero `_show_graphs_window()` dimensiona con `get_window().size` (píxeles reales del SO) menos 40/60 ([Main.gd:690-695](../Main.gd)), y fija `min_size = 1280×680` — prácticamente el viewport base entero. Resultado según resolución/escala: ventana desbordada, recortada o con la barra de título inaccesible, y el grid de columnas (`_graph_column_count()` decide 1-2 columnas con ese mismo ancho inconsistente) queda mal calculado. **Aplica igual al resumen técnico** (1180×760, min 980×620, [Main.gd:426-434](../Main.gd)). Este desajuste explica gran parte del "falla bastante".

### 🔴 G-3. "Salir SIN gráficas" genera gráficas igualmente
`hud.gd` ofrece "Salir sin guardar" → `Main._on_exit_without_graphs_requested()` cambia de escena ([Main.gd:370-374](../Main.gd)). Al liberarse la escena, `SimulationEngine._exit_tree()` llama incondicionalmente a `_finish_and_launch_graphs("forced")` ([SimulationEngine.gd:3603-3607](../sim/core/SimulationEngine.gd)), que escribe `events.json`/`summary.json` y lanza Python en segundo plano hacia `graphs/`. Lo mismo ocurre con "volver al editor". El único guard es `_graphs_launched`/modo validación. Contradice la opción elegida por el usuario y deja artefactos inesperados.

### 🟠 G-4. Los ficheros se reparten en dos carpetas y la pestaña "Archivos" apunta a rutas inexistentes
Con carpeta elegida por el usuario: `_write_export_json()` escribe `summary.json` y `events.json` en la **raíz elegida** ([SimulationEngine.gd:3496-3500](../sim/core/SimulationEngine.gd)), mientras el script Python crea `raíz/<timestamp>/` con los PNGs y ahí copia `sim_log.txt`/`sim_log.csv`. La pestaña "Archivos" del resumen técnico lista `output_dir/sim_log.csv` y `output_dir/sim_log.txt` ([Main.gd:663-666](../Main.gd)) — rutas donde esos ficheros **no existen**.

### 🟠 G-5. Dos ventanas emergentes compiten a la vez
En el mismo flujo síncrono, `technical_summary_ready` dispara `_show_technical_summary_window()` y justo después `_on_graphs_dir_selected` hace `_show_graphs_window()`. Dos `popup_centered` casi simultáneos, superpuestos, tras varios segundos de congelación (G-1). UX confusa: el usuario suele ver primero el resumen tapado por las gráficas.

### 🟠 G-6. `generate_fire_graphs.py` puede graficar datos de una ejecución vieja
El engine pasa `--csv` solo si `enable_csv_log` está activo ([SimulationEngine.gd:3522-3527](../sim/core/SimulationEngine.gd)). Si el CSV está desactivado, el script usa su default de módulo `CSV_PATH` (raíz del proyecto o `user://`) y **lo prefiere sobre el `--log` fresco** si existe y no está vacío ([generate_fire_graphs.py:596-601](../scripts/generate_fire_graphs.py)): curvas de una simulación antigua con líneas de evento de la nueva, y carpeta con el timestamp (mtime) del CSV viejo.

### 🟠 G-7. Nombre de carpeta = mtime del fichero de log
`sim_time_label` sale de `os.path.getmtime` ([generate_fire_graphs.py:102-103, 256-257](../scripts/generate_fire_graphs.py)). No identifica la simulación; regenerar desde el mismo log sobrescribe silenciosamente, y dos fuentes (TXT vs CSV) dan labels distintos para el mismo run.

### 🟡 G-8. Parser TXT frágil (fallback)
Columnas por índice fijo `parts[6..13]`; `_val()` usa `find(prefix+"=")`, de modo que buscar `"O2="` también casa dentro de `"CO2="` si el orden de columnas cambiara; FED/SVV con regex sobre `parts[13:]`. Cualquier evolución del formato del log degrada a ceros en silencio. El CSV mitiga esto, pero el TXT sigue siendo la vía de fallback y la única fuente de eventos.

### 🟡 G-9. Lanzamiento de Python en Windows poco robusto
`cmd.exe /c python`: puede resolver al alias de Microsoft Store (exit 9009 → solo un mensaje genérico "revisa Python y matplotlib"); la salida de error del script no se muestra al usuario en ningún caso; rutas con espacios/acentos en la carpeta elegida dependen del re-parseo de comillas de `cmd`.

### 🟡 G-10. Detalles del visor de gráficas
- Orden alfabético de PNGs: `capas, fed_svv, gases, hrr, temperaturas` — HRR (la gráfica principal) queda en medio ([Main.gd:1049-1062](../Main.gd)).
- Zoom "100%" no restaura el layout si la ventana cambió de tamaño: `_graph_texture_base_size` depende del tamaño actual de la ventana y se re-persiste en cada `_apply_graph_zoom` ([Main.gd:960-1008](../Main.gd)).
- Ctrl+rueda escala 1.12 por paso vs botones 1.25 — sensación inconsistente.
- El fallback de arrastre en `Main._input` ([Main.gd:130-140](../Main.gd)) no recibe eventos originados dentro de la `Window` embebida (viewport propio); si el puntero sale del `ScrollContainer` con el botón pulsado, el drag puede quedar "pegado" hasta el siguiente clic dentro.

### ℹ️ G-11. Dependencia y caché
matplotlib es una dependencia dura no verificada en arranque; `.matplotlib-cache/` se crea en la raíz del repo. `graphs/` con PNGs + `.import` de Godot está dentro de `res://` (Godot importa cada PNG generado, ensuciando el proyecto).

---

## 2. Visor 2D (`view/2d/Visualizer.gd`)

### 🟠 V2-1. La isoterma 150 °C se dibuja siempre, incluso en salas frías
`_draw_150c_line()` fuerza `h_m = room_h - 0.02` cuando `layer_150c_m ≥ room_h - 0.01` ([Visualizer.gd:777-792](../view/2d/Visualizer.gd)) — y el valor por defecto cuando no hay capa es exactamente `room_height`. Resultado: línea roja pegada al techo del gauge en **todas** las salas desde t=0, indistinguible de una capa térmica real incipiente. La línea de humo tiene guard (`smoke_kg > threshold`); la de 150 °C no.

### 🟠 V2-2. `_get_draw_transform()` recalculado decenas de veces por frame
Cada `_to_px`/`_point_to_px`/apertura rehace bounds-merge de todas las salas + `get_viewport_rect()` ([Visualizer.gd:1627-1658](../view/2d/Visualizer.gd)); `_draw_openings` lo pide dos veces por puerta (tf y tf2). Con redraw a 20 Hz (`VIEW_RUNNING_UPDATE_INTERVAL_S = 0.05`) y muebles+labels+markers, es O(salas²) efectivo por frame. Funciona hoy, escala mal.

### 🟡 V2-3. Fondo de tamaño fijo
`_draw_background()` pinta `Rect2(-50,-50,4000,2500)` ([Visualizer.gd:441-442](../view/2d/Visualizer.gd)). En viewports más anchos que ~4000 px (ultrawide con escala) el fondo no cubre y se ve el clear color.

### 🟡 V2-4. Escala de color SVV poco legible
`svv_color()`: >99 % gris claro, 90-99 % **naranja**, 5-90 % el mismo rojo, <5 % gris oscuro ([RoomStateVisuals2D.gd:59-66](../view/2d/rooms/RoomStateVisuals2D.gd)). Una sala al 95 % (casi perfecta) ya alarma en naranja y no se distingue 80 % de 10 %. Además ese color se aplica a la línea que empieza por "FED" (mezcla semántica FED/SVV en el label).

### ℹ️ V2-5. Minimapa: marcador de jugador FP inalcanzable
`Minimap2D._draw_live_player()` solo dibuja si `fp_player.active`, pero el minimapa se oculta precisamente en modo FP (`minimap_2d.visible = view_3d_enabled and not first_person_enabled`, [Main.gd:322-323](../Main.gd)) y `set_state` solo se le llama en modo 3D orbital. Código muerto o feature a decidir (¿minimapa visible en FP?).

### ℹ️ V2-6. Otros
- `_draw_openings`: el filtro de planta de aperturas del minimapa mira solo `op.a` ([Minimap2D.gd:83](../ui/Minimap2D.gd)).
- Etiquetas: hasta 10+ líneas en detalle "full"; `fit_lines` recorta con "..." correctamente.
- El selector de plantas 2D y el del minimapa no comparten estado (el minimapa sigue al player_start) — coherente pero conviene documentarlo.

---

## 3. Visor 3D (`view/3d/Visualizer3D.gd`)

### 🔴 V3-1. Picking contra el plano y=0 → roto en plantas superiores
`ScreenPicking3D._floor_hit_m()` interseca el rayo **solo con y=0** ([ScreenPicking3D.gd:74-91](../view/3d/interaction/ScreenPicking3D.gd)). Consecuencias en edificios multi-planta:
- Clic sobre una sala de planta 1 selecciona la sala de planta baja que quede bajo el rayo proyectado (o ninguna).
- `floor_clicked` y todo el **arrastre de objetos/detectores/víctimas/player_start** (`screen_to_floor_m`) calculan posiciones de suelo con la altura equivocada → el elemento arrastrado se desplaza con un offset creciente respecto al cursor.
- `room_id_at_screen_pos` ni siquiera desambigua por planta cuando dos rects se solapan en XZ: devuelve el primer id ordenado.
- `is_screen_point_over_model` también usa y=0, así que en plantas altas el gesto de órbita/zoom "sobre el modelo" se evalúa mal.

### 🟠 V3-2. Trabajo duplicado y churn de materiales en cada update
`_update_dynamic_state()` llama `_update_openings()` y luego `_apply_selection_visuals()`, que **vuelve a** llamar `_update_openings()` y re-ejecuta `_update_room_safety_markers_3d` para todas las salas ([Visualizer3D.gd:1520-1526, 1770-1775](../view/3d/Visualizer3D.gd)). Además `_set_marker_color()` crea un `StandardMaterial3D` nuevo por marcador y pasada ([Visualizer3D.gd:2971-2980](../view/3d/Visualizer3D.gd)). A 8 Hz (0.12 s) con varios detectores/víctimas es churn constante de materiales y trabajo O(2×) por frame.

### 🟠 V3-3. Recomputación de poses de apertura O(salas×aperturas) por update
`_same_floor_opening_smoke_spill_for_room()` ([Visualizer3D.gd:2180-2258](../view/3d/Visualizer3D.gd)) y `_fuel_visual_opening_clearances_for_room()` ([Visualizer3D.gd:3251-3281](../view/3d/Visualizer3D.gd)) llaman `_opening_pose()` (que a su vez pide `building.get_room_rects_m()`) para cada apertura de cada sala en cada `set_state`. Las poses son estáticas salvo rebuild: cacheables.

### 🟡 V3-4. Nodo `smoke_edge` muerto
Se crea una caja `SmokeLayerEdge_XX` por sala ([Visualizer3D.gd:721-724](../view/3d/Visualizer3D.gd)) pero ambas ramas de `_update_smoke_volume` la dejan `visible = false` (líneas 2070-2071 y 2122-2123) y `_apply_smoke_edge_shader()` no tiene llamadores. Nodos + material por sala sin uso.

### 🟡 V3-5. Leyenda reconstruida en cada `set_state`
`_update_legend()` hace queue_free + rebuild de todas las filas aunque nada cambie ([Visualizer3D.gd:559-593](../view/3d/Visualizer3D.gd)). Hoy `show_legend=false` por defecto, pero si se activa son allocations a 8 Hz.

### 🟡 V3-6. Pila de transparencias sin `render_priority`
Por sala conviven hasta 5-6 cajas alfa solapadas (volumen de humo, gradiente, hot layer, l150, máscara de techo, plume) más cortinas por apertura, todas `TRANSPARENCY_ALPHA` sin prioridad de render y con inset de solo 4 cm. Es el patrón clásico de artefactos de ordenación alfa en Godot (popping según ángulo de cámara). Las capas hot/l150 están off por defecto, lo que hoy lo disimula.

### 🟡 V3-7. `capture_screenshot_to` captura el viewport raíz completo
Incluye el HUD 2D superpuesto ([Visualizer3D.gd:290-308](../view/3d/Visualizer3D.gd)); el nombre y el uso (W-01 export) sugieren vista 3D limpia.

### ℹ️ V3-8. Otros
- `_clear_container()` usa `child.free()` inmediato, también durante `_rebuild_fuel_object_shape` en pleno update de estado — funciona, pero `queue_free()` sería lo defensivo.
- Picking de objetos/marcadores por distancia 2D al **origen** del nodo (34/32 px): muebles grandes son difíciles de clicar por los bordes.
- El fallback `elif _has_selection(): clear_selection()` al pulsar fuera del modelo emite `room_clicked(-1)` — coherente con el 2D.

---

## 4. Primera persona (`view/fp`)

En conjunto es el visor más cuidado (overlay de visibilidad bien parametrizado, HUD técnico con capa según postura, presets). Hallazgos:

### 🟠 FP-1. Mundo FP re-implementado en paralelo al 3D
`FirstPersonController._rebuild_world()` construye suelos, muros, techos, escaleras, voids… con su propia copia del código: `_subtract_rect`, `_split_rect_by_voids`, `_stair_vertical_void_rect`, `_stair_ramp_width_m`, etc. son **duplicados literales** de Visualizer3D ([FirstPersonController.gd:1042-1143](../view/fp/FirstPersonController.gd) vs [Visualizer3D.gd:1098-1199](../view/3d/Visualizer3D.gd)). Tres representaciones del mismo edificio (2D, 3D, FP) con dos implementaciones de geometría: cualquier ajuste de escaleras/voids hecho en una divergirá visualmente de la otra (los umbrales mágicos 0.72/1.05/0.18/179° ya viven en ambos sitios).

### 🟡 FP-2. Consultas repetidas por frame físico
`_find_current_room_id()` (+ `get_room_rects_m()`) se ejecuta en `_update_visibility_overlay` y otra vez en `_update_status_hud` cada physics frame, y `_compute_fp_smoke_view` vuelve a pedir los rects ([FirstPersonController.gd:2965-3005, 3216-3250](../view/fp/FirstPersonController.gd)). Barato hoy, pero es trabajo redundante 60×/s.

### 🟡 FP-3. Fallback de CO₂ inventado en el overlay técnico
`room_state.get(co2_source_key, room_state.get("co2_upper_ppm", 4000.0))` ([FirstPersonController.gd:3080](../view/fp/FirstPersonController.gd)): si el estado no trae la clave, el HUD muestra un 0.4 %vol constante en vez de "--". Mejor señalizar dato ausente que fabricarlo.

### ℹ️ FP-4. Correcto y destacable
- El humo volumétrico en FP se reutiliza del Visualizer3D en modo overlay (sin duplicar esa parte) con parámetros de shader específicos FP — bien.
- La atenuación de luces por humo (`_update_smoke_light_attenuation`, `_light_smoke_transmission_for_*`) es coherente con el overlay (mismos regímenes ILV).
- El suavizado de temperatura del HUD con τ y reset por cambio de sala/postura está bien resuelto.
- FP no sufre el bug de picking V3-1 (no usa rayo a suelo).

---

## 5. Integración de vistas (`Main.gd`)

- ℹ️ Cadencias: 2D/HUD a 20 Hz, 3D a ~8 Hz (`VIEW_3D_RUNNING_UPDATE_INTERVAL_S = 0.12`). En FP, `set_state` del FirstPersonController va a 20 Hz pero el Visualizer3D (humo/fuego compartidos) a 8 Hz — el humo FP "late" a menos frecuencia que el HUD; disimulado por los lerp internos de humo, aceptable.
- ℹ️ En pausa no hay updates de vista salvo interacción (los `_update_views()` de los handlers) — correcto, pero los pulsos de flashover/backdraft (usan `sin(sim_time_s)`) se congelan en pausa; coherente aunque discutible visualmente.

---

## 6. Resumen y priorización sugerida

| # | Hallazgo | Sev. | Área |
|---|----------|------|------|
| G-1 | Generación de gráficas congela la UI (OS.execute síncrono) | 🔴 | Gráficas |
| G-2 | Ventanas embebidas vs stretch `canvas_items`: tamaño/recorte erróneos | 🔴 | Gráficas |
| G-3 | "Salir sin gráficas" las genera igualmente vía `_exit_tree` | 🔴 | Gráficas |
| V3-1 | Picking/drag 3D contra plano y=0 (roto multi-planta) | 🔴 | 3D |
| G-4/G-5 | Ficheros repartidos en dos carpetas + dos popups simultáneos | 🟠 | Gráficas |
| G-6/G-7 | CSV viejo preferido sobre log fresco; carpeta por mtime | 🟠 | Gráficas |
| V2-1 | Isoterma 150 °C dibujada siempre | 🟠 | 2D |
| V3-2/V3-3 | Doble trabajo + churn de materiales + poses recalculadas por update | 🟠 | 3D |
| FP-1 | Geometría FP duplicada respecto al 3D | 🟠 | FP |
| resto | G-8…G-11, V2-2…V2-6, V3-4…V3-8, FP-2/FP-3 | 🟡/ℹ️ | — |

**Si solo se atacan cinco cosas** (cuando toque, sin tocar el motor): (1) hacer la generación de gráficas asíncrona con diálogo de progreso —o al menos un "Generando…" modal—; (2) decidir embebido vs ventanas nativas (`_graphs_view_window.transient/exclusive` o `embed_subwindows=false` para esas dos ventanas) y dimensionarlas en el espacio de coordenadas correcto; (3) respetar "salir sin gráficas" con un flag que `_exit_tree` consulte; (4) unificar el destino de ficheros en `raíz/<timestamp>/` y que la pestaña Archivos liste esa carpeta; (5) intersectar el rayo de picking con el plano del suelo de la planta activa (o física real) en Visualizer3D.
