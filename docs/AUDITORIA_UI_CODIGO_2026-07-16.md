# Auditoría: UI construida por código vs escenas de Godot

**Fecha:** 2026-07-16
**Motivo:** el menú principal que se ve en el editor de Godot (MainMenu.tscn) no corresponde con el que aparece en el juego. Regla acordada: lo que se ve y se toca debe estar reflejado en escenas/recursos editables desde Godot; el código solo debe rellenar datos y conectar señales.

## El patrón que causa la divergencia

Casi toda la UI usa un patrón "bind-or-build": el script busca los nodos en la escena (`get_node_or_null`) y, si no existen, los crea por código — y además **inyecta** controles nuevos que nunca se añadieron al `.tscn`. Resultado: la escena del editor muestra un esqueleto antiguo y el juego muestra la versión enriquecida. Además el estilo visual global se genera por código (`SimuFireThemeScript.build_theme()`), no con un recurso `Theme` editable.

## Inventario por pantalla

### 1. Menú principal — `scenes/MainMenu.tscn` + `MainMenu.gd` (16 `.new()`, 524 líneas)
| En la escena (.tscn) | Solo por código (runtime) |
|---|---|
| Logo, título, subtítulo | Fila "Tipo de edificio" |
| Fila Plantilla | Fila "Piso del apartamento" (SpinBox) |
| Fila HVAC | Fila "Iluminación" (Día/Noche) |
| Botones Iniciar/Editor/Salir | Fila "Luces interiores" |
| Estilos StyleBoxFlat del menú viejo | Fila "Rotura de cristales" |
| | Re-tematización completa (`_apply_main_menu_visual_style`) |

**Divergencia total**: `_ensure_start_options_ui()` inyecta las filas nuevas y `_apply_main_menu_visual_style()` pisa los estilos de la escena. Lo que se edita en el .tscn apenas afecta al juego.

### 2. HUD de simulación — `scenes/SimulationScene.tscn` + `ui/hud.gd` (15 `.new()`, 1041 líneas)
- **En escena (bien):** TimeControlsPanel con botones, OpeningsPanel, RoomsDataPanel, VictimsPanel, TimeLabel, ExitOptionsMenu.
- **Por código:** tarjetas por sala (contenido dinámico — legítimo), grid compacto de aperturas, botones FP/HVAC creados como fallback si faltan (ya están en escena: el fallback es código muerto a limpiar), estilos de tarjetas.

### 3. Orquestador — `Main.gd` (56 `.new()`, 1235 líneas)
Construye por código y NO existe en ninguna escena:
- Ventana del visor de gráficas (window + tabs + scrolls + zoom)
- Ventana del resumen técnico (window + pestañas + árbol de ficheros)
- FileDialog del directorio de gráficas
- **Minimap2D** (se instancia y posiciona por código en `_setup_minimap`; los offsets que ajusté para FP están hardcodeados)

### 4. HUD de primera persona — `view/fp/FirstPersonController.gd`
Todo por código: panel de estado FP, overlay técnico, readout de visibilidad, prompt de interacción ("F: cerrar puerta"). Nada visible en escena.

### 5. Leyenda 3D — `view/3d/Visualizer3D.gd`
CanvasLayer + PanelContainer + filas construidos por código (`_build_legend_ui`). Posición/estilo no editables en escena.

### 6. Editor de escenarios — `editor/ScenarioEditor.gd` (**199 `.new()`, 8111 líneas**)
`scenes/ScenarioEditorScene.tscn` es un contenedor casi vacío; el editor entero (paneles, inspector de objetos, toolbox, diálogos) se construye por código. Es el mayor volumen de UI-en-código del proyecto.

### 7. Tema global — `SimuFireTheme` (script)
Colores, fuentes y estilos se generan en `build_theme()` por código. No hay un `theme.tres` que se pueda abrir y editar en el inspector.

## Clasificación

- **(A) UI estática que debe vivir en escena:** filas del menú principal, ventanas de gráficas/resumen, minimapa, paneles FP, leyenda 3D. → migrar.
- **(B) Contenido dinámico legítimo por código:** tarjetas por sala, filas de víctimas, items de leyenda, opciones de OptionButtons. → se queda en código, PERO cada "plantilla de tarjeta" puede ser un `.tscn` pequeño instanciado con `PackedScene` para que su diseño sea editable.
- **(C) Estilo por código:** `SimuFireThemeScript.build_theme()`. → exportar a `assets/ui/simufire_theme.tres` y asignarlo en las escenas; el script queda solo como generador inicial.

## Plan de migración propuesto

| Fase | Qué | Esfuerzo | Resultado |
|---|---|---|---|
| U1 | **MainMenu**: mover las filas inyectadas al .tscn, borrar `_setup_ui` fallback, código solo rellena opciones y conecta señales | 0.5 d | El menú del editor = el del juego |
| U2 | **Tema**: generar `simufire_theme.tres` desde `build_theme()`, asignarlo a las escenas, retirar re-tematización runtime | 0.5 d | Colores/estilos editables en inspector |
| U3 | **Main**: `GraphsWindow.tscn` + `TechnicalSummaryWindow.tscn`; añadir nodo `Minimap2D` a SimulationScene con sus dos posiciones (3D/FP) como exports | 1 d | Ventanas y minimapa editables |
| U4 | **FP HUD**: escena `FPHud.tscn` (status, overlay técnico, readout, prompt) instanciada por el controller | 0.5-1 d | HUD FP editable |
| U5 | **Leyenda 3D**: nodos bajo Visualizer3D en SimulationScene | 0.25 d | Posición/estilo editables |
| U6 | **Plantillas de tarjeta** (sala/víctima/apertura) como PackedScene | 0.5 d | Diseño de tarjetas editable |
| U7 | **ScenarioEditor**: por su tamaño, fase propia y troceada (empezar por toolbox y diálogos) | 3-5 d | — |

Recomendación: U1+U2 primero (son la queja concreta y dan el mayor retorno), U3-U6 después, U7 cuando haya ventana larga.

## Regla para código nuevo

Ningún `Control` estático nuevo por código: se añade al `.tscn` y el script lo referencia con `@onready`/`get_node`. Por código solo: contenido dinámico (listas variables), instanciación de plantillas `PackedScene`, y wiring de señales. Los valores ajustables van como `@export`.
