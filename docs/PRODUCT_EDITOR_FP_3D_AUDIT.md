# Auditoría de producto — Editor / Sistema FP / Visualización 3D
**Fecha**: 2026-05-31 | **Versión base**: v0.4.1 (commit 7b24f68)  
**Validación**: 379/379 PASS · 4 gaps no-gating · Guardrails ALL PASS · 13/13 tests OK

---

## 1. Mapa de arquitectura

```
MainMenu.tscn ──────────────────────────────────────────────────────┐
   │  [Nuevo escenario]                                              │
   │  [Editor]                                                       │
   │  [Salir]                                                        │
   ▼                                                                 │
ScenarioEditorScene.tscn                                             │
   └── ScenarioEditor.gd  (7 399 líneas, 340 funciones)             │
       ├── EditorGrid.gd         — cuadrícula 2D y snap              │
       ├── ObjectLibrary.gd      — catálogo de objetos combustibles   │
       ├── ScenarioSerializer.gd — save/load JSON editor ↔ runtime    │
       ├── Visualizer3D.gd       — vista 3D editable en el editor    │
       └── FirstPersonController.gd — modo FP en el editor           │
                                                                     │
   [Ejecutar simulación] ─────────────────────────────────────────► SimulationScene.tscn
                                                                        └── Main.gd  (799 líneas)
                                                                            ├── BuildingModel.gd
                                                                            ├── SimulationEngine.gd
                                                                            ├── Visualizer.gd        (2D)
                                                                            ├── Visualizer3D.gd      (3D)
                                                                            ├── FirstPersonController.gd
                                                                            └── hud.gd

Transporte editor → simulación:
  ScenarioEditor → ScenarioSerializer.to_runtime_template() → user://last_editor_runtime_template.json
  SimulationScene (Main.gd._apply_startup_engine_options()) → SimulationEngine.apply_runtime_options()
```

---

## 2. Inventario de módulos y estado

### 2.1 Editor de escenarios (`editor/`)

| Módulo | Archivo | Tamaño | Estado |
|--------|---------|--------|--------|
| Editor principal | `ScenarioEditor.gd` | 7 399 líneas / 340 funciones | ✅ Extenso y funcional |
| Cuadrícula | `EditorGrid.gd` | ~150 líneas | ✅ Completo |
| Biblioteca de objetos | `ObjectLibrary.gd` | ~200 líneas | ✅ Completo |
| Serialización | `ScenarioSerializer.gd` | 366 líneas | ✅ Completo |

**Herramientas de editor disponibles** (enum `Tool`):
- `SELECT`, `EXTERIOR_WALL`, `ROOM`, `CORRIDOR_L`, `STAIRS`, `DOOR`, `HOLE`, `WINDOW`
- `OBJECT` (combustibles), `IGNITION`, `PLAYER_START`, `DELETE`, `DETECTOR`, `VICTIM`

**Capacidades confirmadas**:
- Crear/editar habitaciones rectangulares con rotación libre
- Pasillos, escaleras (múltiples pisos), paredes exteriores
- Puertas, ventanas, huecos con offset y fracción de apertura
- Objetos combustibles: posición, tamaño, rotación, tipo, ignición
- Detectores (tipo, umbral), víctimas, marcador de inicio FP
- Modos de vista: 2D, 3D, FP (dentro del editor)
- Guardar/cargar escenario (FileDialog nativo)
- Exportar template runtime
- Ejecutar simulación (→ cambia escena a SimulationScene)
- Undo/redo (48 pasos)
- HVAC option, lighting option, glass break option
- Floor management (múltiples pisos)
- Arrastrar y reposicionar objetos en vista 3D del editor
- Hover help y status bar

**Estado general**: Muy completo. No hay funciones stub sin implementar dentro de este módulo. La presencia de 340 funciones en un único archivo de 7 400 líneas es la deuda técnica principal (ver §5).

---

### 2.2 Visualización 2D (`view/2d/`)

| Módulo | Archivo | Estado |
|--------|---------|--------|
| Visualizador principal | `Visualizer.gd` | ✅ Completo (1 658 líneas) |
| Plano de planta | `floors/FloorPlan2D.gd` | ✅ Completo |
| Visuals de sala 2D | `rooms/RoomStateVisuals2D.gd` | ✅ Completo |
| Layout labels 2D | `rooms/RoomLabelLayout2D.gd` | ✅ Completo |
| Geometría aperturas 2D | `openings/OpeningGeometry2D.gd` | ✅ Completo |
| Minimapa | `ui/Minimap2D.gd` | ✅ Completo |

**Capacidades**: overlay de temperatura, CO, CO₂, HCN, O₂, humo, FED, visibilidad, HRR; estado de aperturas (abierta/cerrada/vidrio roto); badges de alertas; panel de detalle por sala.

---

### 2.3 Visualización 3D (`view/3d/`)

| Módulo | Archivo | Estado |
|--------|---------|--------|
| Visualizador principal | `Visualizer3D.gd` | ✅ Completo (2 688 líneas / 124 funciones) |
| Geometría de sala | `geometry/RoomShellFactory.gd` | ✅ Completo |
| Cámara orbital | `camera/CameraOrbit3D.gd` | ✅ Completo |
| Picking 3D | `interaction/ScreenPicking3D.gd` | ✅ Completo |
| Pose de apertura 3D | `openings/OpeningPose3D.gd` | ✅ Completo |
| Animación humo | `smoke/SmokeAnimation3D.gd` | ✅ Completo |
| Capas de humo | `smoke/SmokeLayerVisuals.gd` | ✅ Completo |
| Cortina humo en apertura | `smoke/SmokeOpeningCurtain3D.gd` | ✅ Completo (481 líneas) |
| Malla puente humo | `smoke/SmokeBridgeMesh.gd` | ✅ Completo |
| Sprites puff humo | `smoke/SmokePuffSpriteFactory.gd` | ✅ Completo |
| Material volumen humo | `smoke/SmokeVolumeMaterialFactory.gd` | ✅ Completo |
| Animación fuego | `fire/FireAnimation3D.gd` | ✅ Completo |
| Material fuego | `fire/FireMaterialFactory.gd` | ✅ Completo |
| Malla fuego | `fire/FireMeshFactory.gd` | ✅ Completo |
| Colocación mobiliario 3D | `furniture/FurniturePlacement3D.gd` | ✅ Completo |
| Formas procedurales | `furniture/FurnitureShapeBuilder.gd` | ✅ Completo |
| Visuals estado mobiliario | `furniture/FurnitureStateVisuals.gd` | ✅ Completo |
| Clasificador visual | `furniture/FurnitureVisualClassifier.gd` | ✅ Completo |
| Cargador de assets | `furniture/FurnitureAssetLoader.gd` | ✅ Completo |

**Capacidades**: geometría procedural de salas, escaleras, contexto exterior (ciudad/residential), iluminación Sun+FillLight, vidrio roto con grietas, animación de humo volumétrico + sprites + cortinas en aperturas, fuego animado con columna de humo, mobiliario 3D procedural y desde assets, drag-and-drop de elementos en el editor 3D, marcadores de detectores/víctimas/inicio FP, selección visual con halo.

---

### 2.4 Sistema FP (`view/fp/`)

| Módulo | Archivo | Tamaño | Estado |
|--------|---------|--------|--------|
| Controlador FP | `FirstPersonController.gd` | 2 934 líneas / 135 funciones | ✅ Funcional |
| Overlay visibilidad | `FPVisibilityOverlay.gd` | ~150 líneas | ✅ Completo |
| Visuals aperturas FP | `FPOpeningVisuals.gd` | ~200 líneas | ✅ Completo |
| Interacción aperturas | `FPOpeningInteraction.gd` | ~180 líneas | ✅ Completo |
| Movimiento jugador | `FPPlayerMotion.gd` | ~200 líneas | ✅ Completo |

**Capacidades**:
- Construcción procedural completa del mundo 3D desde `BuildingModel`
- Geometría: suelos, techos, muros (con rodapié), escaleras (tramo recto y switchback), rellano
- Contexto exterior: ciudad de día/noche con edificios, iluminación y vistas de ventana
- Posturas: de pie / agachado / tumbado con velocidades distintas
- Interacción con aperturas: ciclo por pasos (0/25/50/75/100%), hold para ajuste fino
- Overlay de visibilidad: opacidad según humo + postura (altura de capa)
- Atenuación de luces por humo en sala
- Marcadores de detectores y víctimas (cambian color según estado de activación)
- Vidrio roto: sustitución de panel por fragmentos visuales
- Input: WASD + ratón, agacharse (C), tumbarse (Z), salir (Escape/Tab)

**Limitaciones actuales**:
- No hay render de llama/fuego propio en FP (se usa la geometría 3D del Visualizer3D cuando está activo)
- No incluye lógica táctica de intervención (agua, PPV, rescate); el alcance actual es simulador técnico.
- No hay pathfinding para víctimas; son marcadores estáticos

---

### 2.5 Escenas Godot

| Escena | Descripción | Estado |
|--------|-------------|--------|
| `scenes/MainMenu.tscn` | Menú principal (3 botones + opciones de preset) | ✅ Completo |
| `scenes/ScenarioEditorScene.tscn` | Editor de planta con UI | ✅ Completo |
| `scenes/SimulationScene.tscn` | Simulación + HUD + Visualizers | ✅ Completo |
| `assets/fp/furniture/*.tscn` | 16 assets de mobiliario FP | ✅ Completos |
| `assets/fp/openings/door_panel.tscn` | Panel de puerta FP | ✅ Completo |
| `assets/fp/openings/window_panel.tscn` | Panel de ventana FP | ✅ Completo |

---

### 2.6 UI de simulación (`ui/`)

| Módulo | Archivo | Estado |
|--------|---------|--------|
| HUD principal | `hud.gd` | ✅ Completo (944 líneas) |
| Vista de acción apertura | `HUDOpeningActionView.gd` | ✅ Completo |
| Resumen apertura | `HUDOpeningSummary.gd` | ✅ Completo |
| Labels de reproducción | `HUDPlaybackLabels.gd` | ✅ Completo |
| Resumen de sala | `HUDRoomSummary.gd` | ✅ Completo |
| Minimapa 2D | `Minimap2D.gd` | ✅ Completo |
| Tema visual | `SimuFireTheme.gd` | ✅ Completo |

**Señales HUD disponibles**: `play_requested`, `pause_requested`, `slower_requested`, `faster_requested`, `stop_and_generate_requested`, `exit_without_graphs_requested`, `view_3d_toggled`, `first_person_toggled`, `hvac_toggled`, `opening_fraction_requested`.

---

### 2.7 Flujo de datos editor → simulación

```
editor_data (Dictionary interno ScenarioEditor)
    │
    ▼
ScenarioSerializer.normalize_editor_data()
    │
    ├─→ save_scenario() → user://editor_scenario.json     (guardado manual)
    │
    └─→ save_runtime_template()
           → user://last_editor_runtime_template.json     (exportar / ejecutar)
                │
                ▼
        SimulationScene (Main.gd)
            → _apply_startup_engine_options()
            → engine.apply_runtime_options(options)
            → BuildingModel se construye desde el template
```

**Estado del flujo**: ✅ Completo y funcional. La ruta de datos está probada (los casos de validación usan el mismo mecanismo de template JSON).

---

## 3. Búsqueda de incompletos

### 3.1 TODOs / FIXMEs explícitos
No hay TODO/FIXME/HACK activos en ficheros `.gd` del directorio `sim/`.

### 3.2 Scripts huérfanos
Ninguno. Todos los `.gd` están referenciados desde al menos una escena `.tscn` o precargados por otro script.

### 3.3 Assets sin consumir
- 1 único escenario de ejemplo en `scenarios/simple_house_objects.json` — no es un bug, es deliberado.
- `view/furniture/FurnitureVisualLayout.gd` tiene solo `.gd.uid` sin aparecer explícitamente en una escena `.tscn`, pero es precargado por `Visualizer3D.gd`.

### 3.4 Capacidades fuera de alcance
- **HUD táctico de intervención**: no forma parte del simulador técnico actual.
- **Pathfinding de víctimas**: marcadores estáticos; no hay sistema de movimiento.
- **Criterios de victoria/derrota**: no implementados; la salida prevista es análisis técnico.
- **Mapa de huida / navegación táctica**: no implementado.

---

## 4. Riesgos técnicos

| Riesgo | Severidad | Descripción |
|--------|-----------|-------------|
| **Monolito ScenarioEditor.gd** | Alta | 7 400 líneas / 340 funciones en un solo archivo. Dificulta mantenimiento, test unitario y contribuciones externas. Candidato a descomposición en módulos especializados. |
| **Acoplamiento editor↔Visualizer3D** | Media | El editor instancia y controla directamente el Visualizer3D y el FirstPersonController. Cambios en sus interfaces pueden romper el editor sin aviso. |
| **Transporte via archivos de usuario** | Media-Baja | `user://last_editor_runtime_template.json` es el canal entre editor y simulación. Si se corrompe o no existe, la simulación carga sin datos. No hay validación de esquema en destino. |
| **Sin test de UI** | Media | Todo el código de editor/UI es código Godot sin cobertura de test automatizado. Regresiones visuales o de flujo solo detectables manualmente. |
| **FP sin fuego propio** | Baja-Media | En modo FP puro no hay visualización de llama; el fuego aparece como emisión volumétrica de humo/calor. Requiere integrar `FireAnimation3D` en la geometría FP o una alternativa de billboard. |
| **Sin gestión de errores de carga de escenario** | Baja | Si el JSON del editor está malformado, `ScenarioSerializer.load_scenario()` hace `push_error` pero el editor continúa con datos vacíos sin informar al usuario con popup. |
| **Víctimas sin movimiento** | Baja | Las víctimas son marcadores estáticos; no existe motor de pathfinding. Para entrenamiento real se necesitaría movilidad básica o al menos animación de estado (consciente/incapacitado/muerto). |

---

## 5. Deuda técnica catalogada

| ID | Deuda | Impacto | Esfuerzo |
|----|-------|---------|---------|
| DT-01 | `ScenarioEditor.gd` monolito (7 400 líneas) | Alto (mantenibilidad) | Alto (refactor multi-sesión) |
| DT-02 | Sin validación de esquema al cargar template en SimulationScene | Medio (robustez) | Bajo |
| DT-03 | Popup de error en carga fallida de escenario (editor) | Medio (UX) | Bajo |
| DT-04 | Sin test de flujo editor→simulación | Medio (regresión) | Medio |
| DT-06 | Fuego no visible en modo FP | Bajo-Medio (inmersión) | Medio |
| DT-07 | Víctimas estáticas | Medio (entrenamiento) | Alto |
| DT-08 | Pantalla de resumen técnico post-simulación | ✅ Implementado en W-02: métricas técnicas, víctimas, detectores y archivos exportados | Cerrado |
| DT-09 | Internacionalización parcial (mezcla ES/EN en UI) | Bajo | Bajo-Medio |

---

## 6. Propuesta de fases

### v0.5.0 — Editor Foundation (robustez y mantenibilidad)

**Objetivo**: convertir el editor en código mantenible sin cambiar comportamiento externo.

| Tarea | Descripción | Prioridad |
|-------|-------------|-----------|
| DT-03 | Error popup en carga fallida | Alta |
| DT-02 | Validación básica de esquema runtime template | Alta |
| DT-09 | Unificar idioma UI (castellano consistente) | Media |
| DT-01 parcial | Extraer módulo de serialización de UI (propiedades por tipo de elemento) de `ScenarioEditor.gd` a `editor/UIPropertyPanels.gd` | Media |
| DT-01 parcial | Extraer módulo de dibujo 2D `editor/EditorDraw2D.gd` (funciones `_draw_*`) | Media |
| — | Test de smoke del flujo editor→export→simulación | Alta |

**Criterio de cierre**: editor funciona igual que antes, tiene test de flujo, código distribuido en ≤5 módulos de editor, errores de carga son visibles al usuario.

---

### v0.5.1 — FP System Polish

**Objetivo**: modo primera persona completo y robusto para sesiones de entrenamiento.

| Tarea | Descripción | Prioridad |
|-------|-------------|-----------|
| DT-06 | Integrar `FireAnimation3D` o billboard en mundo FP | Alta |
| — | HUD FP: temperatura en postura actual, FED acumulado, CO ppm | Alta |
| — | Indicador de visibilidad numérico en FP (metros de visión efectiva) | Alta |
| — | Sonido de advertencia de detector (opcional / asset minimalista) | Media |
| — | Estado visual de víctima en FP: material según estado incapacitación | Media |
| DT-07 parcial | Estado de víctima derivado de FED (incapacitada/muerta visualmente) | Media |
| — | Guardar posición inicial FP desde editor y restaurarla al iniciar | Baja |

**Criterio de cierre**: un instructor puede poner a un alumno en FP, reconocer humo/fuego/temperatura, leer CO/FED, y ver el estado de las víctimas sin necesitar el HUD 2D.

---

### v0.5.2 — 3D Visualization Polish

**Objetivo**: vista 3D completa para análisis y presentación.

| Tarea | Descripción | Prioridad |
|-------|-------------|-----------|
| — | Capa de gradiente vertical en 3D (visualizar upper/lower layer) | Alta |
| — | Overlay de temperatura en paredes (heatmap de color) | Media |
| — | Leyenda de colores en HUD 3D | Media |
| — | Exportar captura de pantalla 3D al directorio de gráficas | Media |
| — | Etiqueta de FED en sala en vista 3D | Baja |
| — | Animación de apertura de puertas en vista orbital 3D (actualmente solo en FP) | Baja |

**Criterio de cierre**: la vista 3D orbital es autónomamente legible — un observador sin acceso a la vista 2D puede seguir la dinámica del incendio.

---

### v0.6.0 — Integrated Technical Workflow

**Objetivo**: ciclo completo de herramienta técnica: escenario → simulación → FP/3D visualization → export técnico.

| Tarea | Descripción | Prioridad |
|-------|-------------|-----------|
| — | Export técnico post-simulación (CSV magnitudes, JSON eventos, capturas picos) | Alta |
| DT-08 | ✅ Pantalla de resumen técnico: tiempo a FED=1.0, tiempo a flashover, pico CO/HCN/O2, visibilidad mínima y detectores. Sin gameplay. | Alta |
| — | Escenarios predefinidos ampliados (piso compacto, pasillo largo, 2 plantas) | Media |
| — | Reproducibilidad: `run_scenario.py <json>` headless + export | Media |
| DT-09 | Internacionalización completa (todas las cadenas UI en castellano) | Baja |

**Fuera de alcance (no implementar)**: HUD táctico (agua/PPV/rescate), criterios victoria/derrota, pathfinding de víctimas, modo instructor/alumno.

**Criterio de cierre**: un investigador puede ejecutar un escenario, obtener los datos técnicos en formato estándar y reproducir el resultado con un único comando.

---

## 7. Resumen ejecutivo

El motor de física de SimuFire está validado y publicado (v0.4.0). SimuFire es un **simulador técnico de dinámica de fuego y gases**; no un videojuego de entrenamiento táctico.

La capa de producto (editor, FP, 3D) está **sustancialmente construida** como herramienta técnica.

**Qué funciona hoy**:
- Editor visual completo: crear plantas, colocar objetos, configurar fuego, guardar/cargar, lanzar simulación.
- Vista 2D con todos los campos del motor (temperatura, gases, FED, visibilidad, presión).
- Vista 3D orbital con geometría procedural, humo animado, fuego, mobiliario y contexto exterior.
- Modo primera persona con construcción procedural del mundo, posturas, interacción con aperturas, overlay de visibilidad por humo.

**Qué falta para producto técnico completo**:
1. Overlay técnico de magnitudes en FP (CO/O²/FED/T/visibilidad).
2. Fuego visible en FP.
3. Estado visual de víctimas derivado de FED (sin gameplay).
4. Export técnico post-simulación (CSV, JSON eventos).
5. Robustez del editor (popup en carga fallida, tests de flujo).
6. Descomposición del monolito `ScenarioEditor.gd`.

**Fuera de alcance (no implementar)**: HUD táctico de agua/PPV/rescate, criterios victoria/derrota, pathfinding.

**Riesgo principal**: el monolito de editor (7 400 líneas) acumula deuda técnica que hará costosos los cambios futuros. Es el candidato más urgente de refactor antes de añadir funcionalidad nueva en v0.6.0.

---

## 8. Comandos de referencia

```powershell
# Validar motor (no tocar)
python scripts/simulation/validate_reference_cases.py
python scripts/simulation/validation_guardrails.py
python tests/test_guardrails.py

# Abrir editor de escenarios (desde Godot)
# → MainMenu → Editor

# Estructura de módulos a crear en v0.5.0
editor/
  ScenarioEditor.gd           (coordinador — reducir a <2 000 líneas)
  EditorGrid.gd               (existente)
  ObjectLibrary.gd            (existente)
  ScenarioSerializer.gd       (existente)
  UIPropertyPanels.gd         (NUEVO: propiedades por tipo de elemento)
  EditorDraw2D.gd             (NUEVO: funciones _draw_*)
  EditorFloorManager.gd       (NUEVO: gestión de plantas)
  EditorSelection.gd          (NUEVO: lógica de selección)
```
