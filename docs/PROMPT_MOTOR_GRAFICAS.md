# Prompt: coordinar motor — gráficas async, suprimir exit, preflight Python

## Qué se ha hecho

Se ejecutó un plan de 25 tareas para arreglar el sistema visual de SimuFire (docs/PLAN_TRABAJO_VISUAL_2026-07-15.md). El plan se dividió en 6 fases y se ejecutó a lo largo de varias sesiones. Aquí el resumen de lo que se hizo, fase por fase:

### Fase 0 — Preparación
- Se creó un checklist de regresión visual manual (docs/CHECKLIST_VISUAL_REGRESION.md)
- Se añadió `graphs/.gdignore` para que Godot no importe los PNG generados por matplotlib
- Se documentó la auditoría visual completa (docs/AUDITORIA_VISUAL_2026-07-15.md)

### Fase 1 — Pipeline de gráficas (parcial)
Se arreglaron los problemas que no tocan el motor:
- **T1.1**: Ventanas de gráficas y resumen técnico dimensionadas correctamente. La de gráficas usa `force_native = true` con `DisplayServer.screen_get_usable_rect()` para dimensionar. La de resumen técnico se encadena (aparece al cerrar las gráficas, no simultáneamente).
- **T1.4**: Carpeta única de salida, ventanas encadenadas (no superpuestas).
- **T1.5**: El script Python (`scripts/generate_fire_graphs.py`) ahora valida el mtime del CSV contra el log, usa timestamp de ejecución para el nombre de carpeta, y tiene un parser TXT robusto con `_find_val(prefix)` que busca por prefijo con word-boundary.
- **T1.6**: Orden fijo de PNGs (`hrr, temperaturas, capas, gases, fed_svv`), zoom unificado a 1.25×, drag mejorado con `mouse_exited` en scroll containers.

**NO se hicieron T1.2 y T1.3 porque tocan el motor.**

### Fase 2 — Picking/drag 3D multi-planta
- **T2.1**: `ScreenPicking3D` reescrito para iterar niveles de planta de arriba abajo, intersectando con el plano `y = floor_level_m * meters_to_units`.
- **T2.2**: Drag captura `_drag_floor_level_m` del elemento al iniciar y lo usa durante todo el arrastre.

### Fase 3 — Correcciones visuales rápidas
- **T3.1**: Isoterma 150°C solo aparece cuando `layer_150c_m < room_h - 0.01`.
- **T3.2**: Escala SVV de 5 niveles (verde ≥90%, ámbar ≥60%, naranja ≥20%, rojo ≥5%, gris agotado).
- **T3.3**: Screenshot 3D oculta `_legend_canvas` con `await RenderingServer.frame_post_draw`.
- **T3.4**: Fondo 2D cubre viewport completo usando transformada inversa.
- **T3.5**: FP overlay muestra "--" cuando faltan datos de CO₂/HCN en vez de un valor falso.

### Fase 4 — Rendimiento y deuda de duplicación
- **T4.1**: Eliminado doble update en selección 3D. Cache de materiales via node meta (mutar `albedo_color` en vez de crear material nuevo cada frame).
- **T4.2**: Cache de pose de openings — se computa una vez en `_create_opening`, se almacena en `_opening_items[index]["pose"]`, se reutiliza en 3 callers.
- **T4.3**: `_frame_tf` cacheado al inicio de `_draw()` en Visualizer 2D, usado por `_to_px`, `_point_to_px` y todas las funciones de dibujo.
- **T4.4**: Eliminados nodos `smoke_edge` muertos — creación, almacenamiento, parámetro de función, export `smoke_layer_edge_color` y función `_apply_smoke_edge_shader` completa (~50 líneas).
- **T4.5**: Extraído `view/geometry/StairGeometry.gd` con 8 funciones estáticas compartidas (`long_span_m`, `cross_span_m`, `ramp_width_m`, `top_landing_depth_m`, `point_along_run`, `vertical_void_rect`, `subtract_rect`, `split_rect_by_voids`). FP y 3D ahora delegan via wrappers de una línea.

### Fase 5 — Pulido y robustez (parcial)
- **T5.1**: `render_priority` escalonado para transparencias 3D: floor(0) < hot(1) < l150(2) < gradient(3) < smoke_volume(4) < ceiling_mask(5) < curtains(6).
- **T5.2**: Leyenda 3D incremental — hash de flags de visibilidad, solo reconstruye filas cuando cambian.
- **T5.3**: FP: eliminada llamada redundante a `_find_current_room_id()` en HUD (reutiliza `_current_room_id` de visibility overlay). Cache de `get_room_rects_m()` por rebuild (`_room_rects_cache`).
- **T5.4**: `free()` → `queue_free()` en `_clear_container`, `_prune_marker_nodes` y fuel objects.
- **T5.5**: Minimapa 2D activado durante modo primera persona.

**NO se hizo T5.6 porque toca el motor.**

### Commits del plan (en main)
```
e2c6210c chore(visual): fase 0 — preparación para arreglos visuales
5311b5ae fix(visual): fase 1 — pipeline de gráficas (sin motor)
1d02d009 fix(visual): fase 2 — picking/drag 3D multi-planta (T2.1, T2.2)
584b7510 fix(visual): fase 3 — correcciones visuales rápidas
aa2c5602 fix(visual): fase 4 — rendimiento y dedup geometria
65c57130 fix(visual): fase 5 — pulido y robustez (T5.1-T5.4)
79a3a2f3 feat(ui): activar minimapa 2D durante modo primera persona (T5.5)
```

---

## Qué falta

Quedan **3 tareas**, todas marcadas ⚠️ MOTOR. Se diseñaron para ejecutarse juntas en un solo commit coordinado con la línea del motor.

### T1.2 — Generación de gráficas sin congelar la UI

**El problema:** cuando el usuario pulsa "Salir y guardar con gráficas", `Main._on_graphs_dir_selected` llama a `engine.stop_and_generate_graphs()`, que internamente ejecuta `OS.execute()` con `wait_for_finish=true`. Esto congela la ventana de Godot durante 5-15 segundos mientras matplotlib genera los PNG. En Windows aparece "No responde".

**El flujo actual (Main.gd:440-454):**
```gdscript
func _on_graphs_dir_selected(dir_path: String) -> void:
    var launched: bool = engine.stop_and_generate_graphs("manual_stop_button", dir_path)
    # ← la UI se congela aquí dentro, OS.execute bloqueante
    _update_views()
    if not launched:
        _show_graphs_message("No se pudieron generar...")
        return
    var graphs_dir: String = engine.get_last_graphs_dir()
    if engine.was_last_graph_generation_ok() and graphs_dir != "":
        _show_graphs_window(graphs_dir)
    else:
        _show_graphs_message("No se pudieron generar...")
```

**El flujo interno del motor (SimulationEngine.gd:3069-3074, 3544-3631):**
```
stop_and_generate_graphs(details, graphs_root)
  → _finish_and_launch_graphs(details, graphs_root, wait_for_finish=true)
    → marca _graphs_launched = true
    → escribe JSON de exportación
    → _launch_graph_generator(graphs_root, wait_for_finish=true)
      → OS.execute("cmd.exe", ["/c", "python", ...args], output, true)  ← BLOQUEANTE
      → lee latest_graphs_dir.txt
      → actualiza _last_graphs_dir y _last_graph_generation_ok
```

**Lo que hay que hacer:**

En `SimulationEngine.gd`:
- Añadir variables de estado: `var _graph_gen_pid: int = -1`
- Modificar `stop_and_generate_graphs` para que use el modo no-bloqueante (`OS.create_process`) en vez de `OS.execute`. La función `_finish_and_launch_graphs` ya hace log final, JSON export, etc. Lo único que cambia es que `_launch_graph_generator` ya no espera.
- Añadir método `poll_graph_generation() -> int`:
  - Si `_graph_gen_pid <= 0`: devolver -2 (no lanzado)
  - Si `OS.is_process_running(_graph_gen_pid)`: devolver 0 (en progreso)
  - Si el proceso terminó: leer `user://latest_graphs_dir.txt`, actualizar `_last_graphs_dir` y `_last_graph_generation_ok`, devolver 1 (ok) o -1 (error)
- `stop_and_generate_graphs` devuelve `true` si el PID es válido (lanzado con éxito)

En `Main.gd`:
- Cambiar `_on_graphs_dir_selected` para que:
  1. Llame a `engine.stop_and_generate_graphs(...)` (ahora no-bloqueante)
  2. Si devuelve true: muestre un overlay modal "Generando gráficas…" (un ColorRect semitransparente con Label centrado, `mouse_filter = STOP` para bloquear input)
  3. Cree un Timer de 0.5s que llame a `engine.poll_graph_generation()`
  4. Cuando `poll` devuelva 1: ocultar overlay, llamar `_show_graphs_window(engine.get_last_graphs_dir())`
  5. Cuando `poll` devuelva -1: ocultar overlay, mostrar mensaje de error
  6. Timeout defensivo de 60s: si el timer ha corrido 120 veces sin resultado, matar el overlay y mostrar error con instrucción manual

### T1.3 — Respetar "salir sin gráficas"

**El problema:** `SimulationEngine._exit_tree()` (línea 3667-3671) siempre llama a `_finish_and_launch_graphs("forced")`. Cuando el usuario pulsa "Salir sin guardar" o "Volver al editor", Main.gd cambia de escena con `get_tree().change_scene_to_file(...)`, lo que dispara `_exit_tree` del motor, y las gráficas se generan de todas formas.

**El código actual (SimulationEngine.gd:3664-3671):**
```gdscript
func _exit_tree() -> void:
    if _is_validation_mode():
        return
    _finish_and_launch_graphs("forced")
```

**Los handlers de Main.gd que deberían suprimir (líneas 372-387):**
```gdscript
func _on_exit_without_graphs_requested() -> void:
    playback_paused = true
    if first_person_enabled:
        _set_first_person_enabled(false)
    get_tree().change_scene_to_file(MAIN_MENU_PATH)
    # ← _exit_tree del motor se dispara aquí y genera gráficas

func _on_return_to_editor_requested() -> void:
    playback_paused = true
    if first_person_enabled:
        _set_first_person_enabled(false)
    # ...
    get_tree().change_scene_to_file(SCENARIO_EDITOR_PATH)
    # ← _exit_tree del motor se dispara aquí y genera gráficas
```

**Lo que hay que hacer:**

En `SimulationEngine.gd`:
- Añadir `var _exit_graphs_suppressed: bool = false` junto a las otras variables de graficas (línea ~76)
- Añadir método público:
  ```gdscript
  func suppress_exit_graphs() -> void:
      _exit_graphs_suppressed = true
  ```
- Modificar `_exit_tree`:
  ```gdscript
  func _exit_tree() -> void:
      if _is_validation_mode() or _exit_graphs_suppressed:
          return
      _finish_and_launch_graphs("forced")
  ```

En `Main.gd`:
- En `_on_exit_without_graphs_requested()`: añadir `engine.suppress_exit_graphs()` antes de `change_scene_to_file`
- En `_on_return_to_editor_requested()`: añadir `engine.suppress_exit_graphs()` antes de `change_scene_to_file`

### T5.6 — Preflight de Python

**El problema:** si el usuario no tiene Python instalado, no se entera hasta que intenta generar gráficas al final de una simulación que puede haber durado minutos. Hay que avisarle desde el principio.

**Lo que hay que hacer:**

En `SimulationEngine.gd`:
- Añadir `var _python_available: bool = true` y `var _python_checked: bool = false`
- Añadir método (la ejecución es rápida, <200ms):
  ```gdscript
  func check_python_available() -> bool:
      if _python_checked:
          return _python_available
      _python_checked = true
      var output: Array = []
      var exit_code: int = -1
      if OS.get_name() == "Windows":
          exit_code = OS.execute("cmd.exe", ["/c", "python", "--version"], output, true)
          if exit_code != 0:
              exit_code = OS.execute("cmd.exe", ["/c", "py", "-3", "--version"], output, true)
      else:
          exit_code = OS.execute("python3", ["--version"], output, true)
          if exit_code != 0:
              exit_code = OS.execute("python", ["--version"], output, true)
      _python_available = exit_code == 0
      return _python_available
  ```
- Añadir getter `is_python_available() -> bool` que devuelva `_python_available`
- En `_launch_graph_generator`: consultar `_python_available` al inicio. Si es false, hacer `push_warning` y `return` inmediatamente en vez de intentar lanzar un proceso que va a fallar.

En `Main.gd`:
- En `_ready()` o al inicio de la simulación: llamar `engine.check_python_available()`
- Si devuelve false: mostrar un Label persistente en el HUD, discreto pero visible, tipo "⚠ Python no detectado — no se generarán gráficas". No un popup modal, solo un aviso.
- Opcionalmente: si Python no está disponible, cambiar el texto del botón de salida con gráficas para indicar que no funcionará, o desactivarlo.

---

## Restricciones

- **Solo tocar `SimulationEngine.gd` en las zonas indicadas.** No reescribir flujos de simulación, sistemas térmicos, intercambio de gases, etc.
- Las 3 tareas van en un **solo commit** porque tocan el mismo fichero del motor.
- Formato de commit: `fix(motor+visual): T1.2 async graphs, T1.3 suppress exit graphs, T5.6 python preflight`
- El motor tiene su propio desarrollo en paralelo. Revisar `git status` antes de commitear para no incluir cambios de motor no relacionados.

## Escenarios de prueba

1. **Con Python instalado, salir con gráficas** → overlay "Generando…", la UI no se congela, al terminar se abre el visor
2. **Sin Python, salir con gráficas** → error inmediato con mensaje accionable (y el usuario ya vio el aviso al iniciar)
3. **Salir sin guardar** → no genera gráficas, no crea carpeta, no escribe JSON
4. **Volver al editor** → idem, no genera gráficas
5. **Cerrar ventana del juego / Stop en editor** → sí genera gráficas (comportamiento existente preservado)
6. **Simulación termina por extinción natural** → sí genera gráficas (vía `_on_sim_finished`, no pasa por `_exit_tree`)
