# Checklist de flujo del editor — SimuFire v0.5.0
**Versión**: v0.5.0 | **Fecha última revisión**: 2026-06-01
**Cubre**: E-01 (popup de carga), E-02 (validación estructural en carga y en ejecución), E-03/E-03b (checklist + product guardrails), E-04 (@export `max_undo_steps` / `pixels_per_meter`), E-04b (EditorLoadErrorDialog extraído), E-05 (UI castellano), E-06 (EditorDraw2D — 11 helpers puros extraídos), E-08 (paneles compactos con pestañas)

---

## Requisitos previos

| Ítem | Valor |
|------|-------|
| Godot ejecutable | `Godot_v4.6.3-stable_win64_console.exe` |
| Proyecto | `res://` → raíz del workspace simufire |
| Archivo de prueba corrupto | Crear manualmente `test_corrupto.json` con contenido `{not valid json` |
| Archivo de prueba válido | `scenarios/simple_house_objects.json` (ya existe) |
| Guardrails previos | `python scripts/simulation/validation_guardrails.py` → ALL PASS |

---

## Bloque A — Arranque del editor

| # | Paso | Resultado esperado | PASS / FAIL |
|---|------|--------------------|-------------|
| A1 | Abrir Godot → ejecutar proyecto (`F5` o botón Play) | MainMenu aparece con opciones: Nuevo escenario, Editor, Salir | ☐ |
| A2 | Pulsar **Editor** | ScenarioEditorScene carga. Panel lateral compacto visible con pestañas **Dibujo / Lista / Archivo**. La pestaña **Archivo** aparece activa por defecto. Canvas 2D en blanco. Status bar en la parte inferior. | ☐ |
| A3 | Verificar que el Inspector de Godot muestra `ScenarioEditor` con la propiedad **Editor UI → Load Error Dialog Title** | Campo de texto editable con valor `"Error al cargar escenario"` | ☐ |

---

## Bloque B — Crear escenario desde cero

| # | Paso | Resultado esperado | PASS / FAIL |
|---|------|--------------------|-------------|
| B1 | Seleccionar herramienta **Sala** en el panel de herramientas | Cursor cambia a modo habitación | ☐ |
| B2 | Clicar y arrastrar en el canvas para crear una habitación de ~5×4 m | Habitación rectangular aparece en el canvas | ☐ |
| B3 | Seleccionar herramienta **Puerta** o **Ventana** y colocar en la pared de la habitación | Apertura visible en el borde de la habitación | ☐ |
| B4 | Seleccionar herramienta **Objeto** y colocar un objeto combustible dentro de la habitación | Objeto aparece; el panel derecho muestra propiedades (nombre, combustible MJ, HRR) | ☐ |
| B5 | Seleccionar herramienta **Ignición** y marcar la sala como punto de ignición | Indicador de ignición visible en la sala | ☐ |
| B6 | Seleccionar herramienta **Detect.** y colocar un detector en la sala | Marcador de detector visible | ☐ |
| B7 | Seleccionar herramienta **Vict.** y colocar una víctima en la sala | Marcador de víctima visible. Nota: es un sensor de exposición (FED/CO/T), no un objeto de rescate. | ☐ |
| B8 | Abrir pestaña **Archivo** y activar HVAC desde la opción de HVAC | Opción HVAC activa (On/Off disponible) | ☐ |

---

## Bloque C — Guardar y cargar escenario

| # | Paso | Resultado esperado | PASS / FAIL |
|---|------|--------------------|-------------|
| C1 | Abrir pestaña **Archivo** y pulsar **Guardar** (o escribir ruta en el campo de path y pulsar Guardar) | FileDialog abre. Seleccionar ruta y guardar. Status bar: "Plantilla guardada en …" | ☐ |
| C2 | Pulsar **Nuevo** o limpiar el canvas (si existe el botón) para descartar el escenario actual | Canvas queda vacío | ☐ |
| C3 | En pestaña **Archivo**, pulsar **Cargar** → seleccionar el archivo guardado en C1 | Status bar: "Plantilla cargada desde …". Habitación, aperturas, objetos, detector y víctima reaparecen. | ☐ |
| C4 | El número de habitaciones y aperturas tras la carga coincide con lo guardado | Sin habitaciones perdidas ni duplicadas | ☐ |

---

## Bloque D — Flujo E-01: popup en carga fallida

| # | Paso | Resultado esperado | PASS / FAIL |
|---|------|--------------------|-------------|
| D1 | Escribir en el campo de path una ruta inexistente (p.ej. `C:/tmp/no_existe_9999.json`) → pulsar **Cargar** | **AcceptDialog** visible con título "Error al cargar escenario" y mensaje "Archivo no encontrado." + la ruta. Status bar actualizada. | ☐ |
| D2 | Pulsar **Aceptar** en el popup | Dialog se cierra. Editor permanece funcional. El escenario anterior no se pierde. | ☐ |
| D3 | Crear `test_corrupto.json` con contenido `{not valid json` → cargarlo | **AcceptDialog** visible con mensaje "El archivo no contiene un escenario válido." | ☐ |
| D4 | Pulsar **Aceptar** en el popup | Dialog se cierra. Editor permanece funcional. | ☐ |
| D5 | Modificar el campo Inspector **Load Error Dialog Title** a `"Fallo de carga"` → repetir D1 | El popup ahora muestra el nuevo título | ☐ |
| D6 | Crear `test_altura_invalida.json` con `{"version":1,"rooms_data":[{"id":0,"name":"R","kind":"generic","height_m":-1.0,"fuel_objects":[]}],"openings_data":[],"room_rect_m":{"0":{"x":0,"y":0,"w":5,"h":4}}}` → intentar cargarlo | **AcceptDialog** visible con mensaje sobre `height_m`. El escenario inválido **no** se aplica al editor. | ☐ |
| D7 | Desde un editor con 0 habitaciones, pulsar **Iniciar simulación** | **AcceptDialog** visible con mensaje "El escenario no tiene habitaciones." La escena **no** cambia. | ☐ |

---

## Bloque E — Lanzar simulación

| # | Paso | Resultado esperado | PASS / FAIL |
|---|------|--------------------|-------------|
| E1 | Con un escenario con al menos 1 habitación cargado, pulsar **Iniciar simulación** (botón inferior) | El editor valida el escenario (no debe haber errores estructurales), exporta `user://last_editor_runtime_template.json` y carga `SimulationScene.tscn`. Status bar: "Iniciando simulación…" | ☐ |
| E2 | La simulación arranca sin errores en la consola de Godot | Ningún `ERROR:` en el log de Godot durante el inicio de la simulación | ☐ |
| E3 | El HUD 2D muestra el plano de planta con la habitación creada | Planta visible, sala correctamente dimensionada | ☐ |
| E4 | Pulsar **Play** en el HUD de simulación | La simulación avanza en tiempo real (HRR sube, humo aparece si hay objetos) | ☐ |

---

## Bloque F — Vistas FP / 3D (si aplica en v0.5.0)

| # | Paso | Resultado esperado | PASS / FAIL |
|---|------|--------------------|-------------|
| F1 | En SimulationScene, pulsar botón **3D** en el HUD | Vista 3D orbital muestra la geometría del escenario | ☐ |
| F2 | En SimulationScene, pulsar botón **FP** en el HUD | Primera persona activa en la posición del marcador de inicio. Fuego y mobiliario 3D siguen visibles desde la cámara FP. El minimapa y las tarjetas 2D de salas/víctimas no se solapan con el HUD FP. | ☐ |
| F3 | Moverse con WASD y verificar que el humo se renderiza correctamente a medida que avanza la simulación | Opacidad del humo aumenta con el tiempo | ☐ |
| F4 | Regresar a la vista 2D con `Escape` o el botón de salir de FP | Vista 2D restaurada | ☐ |

---

## Bloque G — Verificación de Godot editability

Estas propiedades deben ser visibles/editables desde el Inspector de Godot sin tocar código:

| Propiedad | Nodo | Grupo Inspector | Estado |
|-----------|------|----------------|--------|
| `load_error_dialog_title` | `ScenarioEditor` | `Editor UI` | ✅ @export (v0.5.0 E-01) |
| `show_walls` | `Visualizer3D` | `Visibility` | ✅ @export existente |
| `show_smoke_volume` | `Visualizer3D` | `Visibility` | ✅ @export existente |
| `smoke_visible_threshold_kg` | `Visualizer3D` | `Dynamics` | ✅ @export existente |
| `default_room_height_m` | `Visualizer3D` | `Geometry` | ✅ @export existente |
| `show_fuel_objects_in_first_person` | `Visualizer3D` | `Visibility` | ✅ @export (v0.5.1 FP-01 fix) |
| `fp_fuel_object_update_interval_s` | `Visualizer3D` | `Visibility` | ✅ @export (v0.5.1 FP performance) |
| `show_technical_overlay` | `FirstPersonController` | `Technical Overlay` | ✅ @export (v0.5.1 FP-02) |
| `show_visibility_readout` | `FirstPersonController` | `Technical Overlay` | ✅ @export (v0.5.1 FP-03) |
| `show_fire_fp` | — | — | ✅ N/A — fuego FP visible vía `World3D` compartido con `Visualizer3D`; controlado por `show_hrr_columns` (v0.5.1 FP-01 ✅) |
| `max_undo_steps` | `ScenarioEditor` | `Editor UI` | ✅ @export (v0.5.0 E-04) |
| `pixels_per_meter` | `ScenarioEditor` | `Editor UI` | ✅ @export (v0.5.0 E-04) |

---

## Resultados del test automatizado E-02

Ejecutar antes de commit:

```powershell
python tests/test_editor_scenarios.py    # 21 tests
python scripts/check_product.py          # 34 tests (editor + guardrail scripts)
```

Resultado esperado:

```
...
Ran 21 tests in X.XXXs
OK

ALL PRODUCT CHECKS PASS  (34 tests)
```

---

## Criterio de cierre v0.5.0 — Editor Robustness (E-01..E-06)

- [ ] Todos los bloques A–E se ejecutan sin FAIL.
- [ ] Popup E-01 (bloque D) funciona correctamente.
- [ ] `python tests/test_editor_scenarios.py` → OK (todos los tests).
- [ ] `python scripts/check_product.py` → ALL PRODUCT CHECKS PASS (34 tests).
- [ ] `python scripts/simulation/validation_guardrails.py` → ALL GUARDRAILS PASS.
- [ ] 379/379 required PASS sigue intacto.
- [ ] UI del editor completamente en castellano (E-05).
- [ ] `editor/EditorDraw2D.gd` existe con 11 helpers estáticos puros (E-06).

---

## Bugs detectados durante el proceso (a registrar en ROADMAP)

_Rellenar durante la ejecución manual del checklist._

| # | Descripción | Bloque | Severidad |
|---|-------------|--------|-----------|
| — | — | — | — |
