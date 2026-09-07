# Auditoría del editor de escenarios — 2026-09-06

El usuario lo pidió así: *"en el editor de vivienda, no está muy bien hecho aún,
hay cosas que no sé decir qué hacen que no se vea profesional"*.

Esta auditoría no opina: **mide**. Cada hallazgo trae el número que lo sostiene y
lo que le cuesta a quien usa el editor. Las dos frases del usuario resultan ser
dos problemas distintos y se tratan por separado:

- *"no sé decir qué hacen"* → **descubribilidad**: §2.
- *"no se ve profesional"* → **acabado**: §3.

Y de paso salen dos cosas que él no dijo pero que un editor tiene y este no: §4.

Superficie auditada: `scenes/ScenarioEditorScene.tscn` (1921 líneas, 99 controles
interactivos), `editor/ScenarioEditor.gd` (7435 líneas, 377 funciones) y los
cuatro módulos de apoyo de `editor/`.

---

## 1. Resumen

| # | Hallazgo | Sev. | La cifra | Estado |
|---|---|---|---|---|
| E-1 | Controles sin ninguna explicación | 🔴 | **62 de 99** | ✅ **corregido** |
| E-2 | Campos numéricos sin unidad | 🔴 | **36 de 36** | ✅ **corregido** |
| E-3 | Ningún panel tiene barra de desplazamiento | 🟠 | 31 secciones, repartidas en 3 pestañas | ✅ **corregido** (severidad rebajada, ver §7) |
| E-4 | No hay rehacer | 🔴 | 48 pasos de deshacer, 0 de rehacer | ✅ **corregido** |
| E-5 | El interruptor de la ayuda contextual está oculto | 🟠 | `visible = false` | pendiente |
| E-6 | Ningún atajo de teclado para las herramientas | 🟠 | **0** `shortcut`, 14 herramientas | pendiente |
| E-7 | No hay navegación por teclado | 🟠 | **57** controles con `focus_mode = 0` | pendiente |
| E-8 | Se sale del editor sin avisar de cambios sin guardar | 🟠 | `_cancel_pressed()` cambia de escena y ya | ✅ **corregido** |
| E-9 | No hay copiar, pegar ni duplicar | 🟠 | — | pendiente |
| E-10 | Texto de ayuda sin tildes junto a etiquetas con tildes | 🟡 | 1 bloque, ~12 palabras | pendiente |
| E-11 | Herramientas con abreviaturas y sin icono | 🟡 | **0** iconos; "SEL", "DETECT.", "VICT." | pendiente |
| E-12 | El script del editor es un monolito | 🟠 | 7435 líneas, 377 funciones, 1 `@onready` | pendiente |

### Lo que sí está bien, y conviene no romper

No todo está por hacer, y esto es lo que sostiene el resto:

- **Valida antes de ejecutar.** `_run_simulation_pressed()` pasa por
  `Serializer.validate_scenario()` y, si algo falla, lo enumera en un diálogo
  modal en vez de arrancar una simulación rota. Es la decisión más importante
  del editor y está tomada bien.
- **La escena es la fuente de verdad.** El enlazado aborta con `push_error` si
  falta un nodo, en vez de seguir a medias. Y hay tres guardarraíles vivos:
  `validate_editor_scene_complete`, `validate_editor_to_sim_flow` y
  `validate_editor_load_error_dialog`.
- **Hay ayuda contextual sobre el plano** (carteles al dejar el cursor quieto) y
  una guía rápida paginada. El problema no es que no exista: es que no se ve
  (E-5).
- **Deshacer con instantáneas completas**, 48 pasos, sin depender de que cada
  acción sepa deshacerse. Es la implementación robusta.

---

## 2. Descubribilidad — *"no sé decir qué hacen"*

### 🔴 E-1. 62 de los 99 controles no dicen qué hacen

Contados sobre la escena: 99 controles interactivos, **37 con `tooltip_text` y
62 sin nada**. El reparto de los que no lo tienen:

| Tipo | Sin tooltip | Ejemplos |
|---|---|---|
| SpinBox | **36** | `CorridorWidthSpin`, `FloorLevelSpin`, `DetectorThresholdSpin`, `FuelEnergySpin`, `MaxHrrSpin` |
| OptionButton | 11 | `BuildingTypeOption`, `HVACOption`, `OpeningSwingOption`, `OpeningHingeOption` |
| LineEdit | 6 | `RoomKindEdit`, `PathEdit`, `DetectorIdEdit` |
| Button | 5 | `BtnAddFloor`, `BtnDeleteFloor`, `BtnApplyOpening` |
| CheckBox | 3 | `StairWallsCheck`, `StairRailingsCheck`, `InteriorLightsCheck` |
| ItemList | 1 | `ElementList` |

El patrón es claro y explica la frase del usuario: **las herramientas de la barra
superior sí están explicadas** —las 14 llevan tooltip— y **los parámetros no**.
Quien dibuja una sala sabe lo que hace; quien luego mira el panel derecho se
encuentra catorce casillas numéricas mudas.

Los peores, porque el nombre no basta ni sabiendo el dominio:

- `RoomKindEdit` es texto libre y el motor lo usa para decidir materiales,
  mobiliario y luces. Nada dice qué valores entiende.
- `DetectorThresholdSpin` cambia de significado con el tipo de detector
  (temperatura, humo, CO) y no lo advierte.
- `OpeningOffsetSpin` admite fracción o metros según cómo esté declarado el
  hueco. Un mismo campo con dos lecturas.
- `StairWallsCheck` y `StairRailingsCheck` afectan a lo que se construye en 3D,
  no en el plano donde estás mirando.

### 🔴 E-2. Ninguno de los 36 campos numéricos dice en qué unidad está

**0 de 36 SpinBox tienen `suffix`.** El editor mezcla metros, grados, megajulios,
kilovatios, segundos y partes por millón en la misma columna de casillas, todas
con el mismo aspecto y ninguna con unidad.

Un campo que pone `2,40` puede ser la altura de una sala en metros, y el de
debajo, `1100`, la carga de fuego en MJ. La diferencia entre teclear 2,4 y 240 en
el campo equivocado no la avisa nadie hasta que la simulación sale rara.

Es de lo más barato de arreglar de toda la lista —`suffix = " m"`— y de lo que
más cambia la sensación de estar ante una herramienta seria.

### 🟠 E-5. La ayuda contextual existe, funciona, y su interruptor está oculto

`HoverHelpRow` tiene `visible = false` en la escena. Dentro está `HoverHelpCheck`,
que arranca activado y con tooltip escrito. O sea: la función corre, el usuario
la sufre o la disfruta sin saber de dónde sale, y **no puede apagarla**.

O se enseña el interruptor, o se quita el interruptor y se documenta que la ayuda
va siempre. Lo que no puede quedarse es un mando escondido.

### 🟠 E-6. Catorce herramientas y ninguna tecla

**0 `shortcut` declarados en toda la escena.** Los únicos atajos son dos, escritos
a mano en `_input`: `Ctrl+Z` y `Supr`/`Retroceso`.

En un editor de planos se cambia de herramienta cada pocos segundos. Sin teclas,
cada cambio es un viaje del ratón a la barra superior y vuelta. Es la diferencia
entre dibujar y rellenar un formulario.

### 🟡 E-11. Abreviaturas en versalitas y ningún icono

Los catorce botones de herramienta: `SEL`, `EXTERIOR`, `SALA`, `PASILLO`,
`ESCALERA`, `PUERTA`, `HUECO`, `VENTANA`, `OBJETO`, `IGNICION`, `INICIO FP`,
`BORRAR`, `DETECT.`, `VICT.`

Dos de ellos están cortados a la mitad (`DETECT.`, `VICT.`) para caber en 72 px,
y uno es una sigla (`SEL`). **La escena no carga ni un icono** (`icon = ` aparece
0 veces). Una barra de herramientas de texto abreviado en mayúsculas es
exactamente lo que se lee como prototipo.

---

## 3. Acabado — *"no se ve profesional"*

### 🔴 E-3. Ningún panel se puede desplazar

**`ScrollContainer` aparece 0 veces en la escena.**

- El **panel izquierdo** apila **31 secciones directas** —cabecera con logo,
  pestañas, modos de vista, plantas, tipo de edificio, lista de elementos, ayuda,
  objetos, guardar/cargar/exportar, pasillo, escalera, aberturas, tiempo de
  parada, HVAC, luces, plantillas y estado— en un `VBoxContainer` de altura fija
  (`anchor_bottom = 1.0`, `offset_bottom = -76`). Solo las secciones que declaran
  altura mínima ya suman **322 px**, y son una minoría.
- El **panel derecho** apila cinco fichas de propiedades completas —sala, objeto,
  abertura, detector, víctima— con el mismo problema.

Consecuencia: en cuanto la ventana no es alta, **lo de abajo se corta y no hay
forma de llegar**. Y lo de abajo del panel izquierdo es, por este orden: guardar,
cargar, exportar, elegir plantilla y **la única línea de estado del editor**.

Es el hallazgo con más papeletas de ser lo que el usuario está viendo cuando dice
que no se ve profesional: una interfaz que se come sus propios controles.

### 🟠 E-7. No hay navegación por teclado en ningún sitio

**57 controles con `focus_mode = 0`.** Eso apaga el foco, y con él el tabulador.
En un panel de catorce casillas numéricas, no poder pasar de una a la siguiente
con Tab obliga a clicar cada una.

Se puso así, con toda probabilidad, para que el rectángulo de foco no ensuciara
el diseño. La solución no es apagar el foco: es darle un estilo en el tema.

### 🟠 E-8. Se sale del editor sin preguntar

`_cancel_pressed()` hace `change_scene_to_file(MAIN_MENU_PATH)` y nada más. No
hay diálogo, no hay comprobación de si hay cambios sin guardar.

Existe una variable `_editor_runtime_dirty`, pero **no es lo que parece**: solo
sirve para saber si hay que refrescar las vistas 3D. Nadie lleva la cuenta de si
el escenario tiene cambios sin guardar.

Perder media hora de plano por pulsar "volver" es la clase de cosa que decide si
alguien vuelve a usar una herramienta.

### 🟡 E-10. Tildes a medias

La guía rápida del editor, que es el texto más largo que el usuario va a leer
dentro de la aplicación, va sin tildes: *"Seleccion"*, *"Edicion"*, *"Simulacion"*,
*"Victima"*, *"pequeno"*, *"esta encima"*. Y convive con etiquetas que sí las
llevan: *"guía rápida"*, *"habitación"*, *"Iniciando simulación..."*.

Escribir sin tildes en el código es una convención razonable —evita problemas de
codificación en identificadores y comentarios—, pero **el texto que lee el
usuario no es código**.

---

## 4. Lo que no dijo el usuario y también falta

### 🔴 E-4. Hay deshacer pero no rehacer

`_undo_stack` guarda 48 instantáneas y `Ctrl+Z` funciona. **No hay pila de
rehacer**: lo que deshaces se pierde.

Con instantáneas completas el rehacer es casi gratis —una segunda pila y mover
el estado actual de una a otra al deshacer—, así que la ausencia llama más la
atención que la presencia.

### 🟠 E-9. No se puede copiar, pegar ni duplicar

No hay nada. Para hacer cuatro dormitorios iguales hay que dibujar cuatro veces y
ajustar cuatro veces sus propiedades. Lo único parecido que existe es
`_copy_stairs_from_level_to_level`, interno del alta de planta.

En un editor de plantas, duplicar es la operación que más se repite.

### 🟠 E-12. Un solo fichero de 7435 líneas

`editor/ScenarioEditor.gd`: **7435 líneas, 377 funciones, 45 `@export`**. La
función más larga es `_bind_existing_ui`, de **230 líneas**, y en todo el fichero
hay **un solo `@onready`**: los más de doscientos nodos de la escena se enlazan a
mano, uno a uno.

Esto no lo ve el usuario, pero es la razón por la que cada arreglo de los de
arriba cuesta más de lo que debería, y por la que es fácil romper algo al pasar
por ahí. Es el mismo camino que ya se recorrió en `view/`: sacar módulos por
responsabilidad —herramientas, panel de propiedades, entrada, capas— en vez de
reescribir.

---

## 5. Por dónde empezar

Ordenado por lo que devuelve cada hora invertida, no por severidad:

1. **Unidades en los 36 campos** (E-2). Es una línea por campo y es lo que más
   cambia la sensación de herramienta seria.
2. **Scroll en los dos paneles** (E-3). Un `ScrollContainer` en cada uno. Quita el
   fallo de "no llego a los botones".
3. **Tooltip en los 62 controles mudos** (E-1). Trabajo de escribir, no de
   programar, y ataca la frase literal del usuario.
4. **Aviso de cambios sin guardar** (E-8) y **rehacer** (E-4). Los dos son
   pequeños y los dos evitan perder trabajo.
5. **Teclas para las herramientas** (E-6) y **foco con estilo** (E-7).
6. **Iconos en la barra** (E-11) y **tildes en la ayuda** (E-10).
7. **Enseñar o quitar el interruptor de la ayuda contextual** (E-5).
8. **Trocear el monolito** (E-12), a medida que se toquen las zonas anteriores y
   no como una reescritura aparte.

Los puntos 1 a 3 se pueden fijar con guardarraíles en la suite, al estilo de los
de `view/`: que ningún SpinBox del editor se quede sin unidad, que ningún control
interactivo se quede sin tooltip y que los paneles sean desplazables. Sin eso, la
lista se vuelve a llenar sola.

---

## 6. Cómo se ha medido

Todo lo de arriba sale de contar sobre los ficheros, no de mirar la pantalla:

```
# controles, tooltips, unidades, tildes y tamaño del script
grep -cE '^\[node name=.*type="(Button|OptionButton|SpinBox|CheckBox|LineEdit|ItemList)"' scenes/ScenarioEditorScene.tscn
grep -c "tooltip_text"  scenes/ScenarioEditorScene.tscn
grep -c "^suffix"       scenes/ScenarioEditorScene.tscn
grep -c "^focus_mode = 0" scenes/ScenarioEditorScene.tscn
grep -c "ScrollContainer"  scenes/ScenarioEditorScene.tscn
grep -c "^icon = "         scenes/ScenarioEditorScene.tscn
grep -c "shortcut"         scenes/ScenarioEditorScene.tscn
wc -l editor/ScenarioEditor.gd
```

**Lo que esta auditoría NO ha hecho**: ejecutar el editor y usarlo. Todo lo
medido es estructura. Los defectos que solo aparecen al arrastrar una sala, al
encadenar dos herramientas o al cargar un escenario grande **no están aquí**, y
la lección de esta línea visual dice que esos son justo los que más duelen. Si al
usarlo hay algo que canta y no está en esta lista, una captura señalándolo vale
más que otra pasada de lectura.

---

## 7. Lo corregido el 2026-09-07

### Corrección a la propia auditoría: E-3 estaba sobredimensionado

Escribí que el panel izquierdo apila **31 secciones en altura fija**. Es cierto
que son 31 y que no había scroll, pero **omití que el panel está dividido en tres
pestañas** —Dibujo, Lista y Archivo—, así que nunca se muestran las 31 a la vez.
El scroll se había quitado a propósito en `33c59a3f`, el commit que introdujo esas
pestañas, con una función explícita que lo deshacía en tiempo de ejecución:
`_restore_panel_vbox_from_scroll()`.

O sea: la severidad era 🟠, no 🔴, y había una decisión detrás que no leí antes de
juzgarla. Aun así el scroll vuelve, porque **pestañas y scroll no son
alternativas**: las pestañas reparten y el scroll es la red por si la ventana es
baja. Con las dos cosas, nada queda inalcanzable. `_restore_panel_vbox_from_scroll`
se retira, que era quien lo impedía.

### Lo que se ha hecho

| Hallazgo | Antes | Ahora |
|---|---|---|
| E-1 | 37 de 99 controles con explicación | **99 de 99** |
| E-2 | 0 de 36 campos con unidad | **34 con sufijo fijo + 1 dinámico**; 1 sin unidad a propósito |
| E-3 | 0 `ScrollContainer` | los dos paneles se desplazan |
| E-4 | 0 pasos de rehacer | `Ctrl+Y` y `Ctrl+Mayús+Z`, 48 pasos |
| E-8 | se salía sin preguntar | diálogo «Salir sin guardar» / «Seguir editando» |

Detalles que merecen quedar escritos:

- **El umbral del detector es el único campo cuya unidad depende de otro
  control**: 0,025 son kg/m³ de humo, 57 son grados y 300 son ppm de CO. Con la
  casilla muda no había forma de saber cuál se estaba tecleando. Ahora la unidad
  y la explicación cambian con el tipo, y las tres salen de lo que declara
  `SimulationEngine`, no de lo que me pareciera.
- **`ApartmentFloorSpin` no lleva unidad y es correcto**: es un número de planta,
  no una medida. El guardarraíl lo exime por nombre, con el motivo escrito al
  lado, para que la excepción no se convierta en un agujero.
- **Rehacer sale casi gratis** porque el deshacer era por instantáneas completas:
  el estado actual pasa a la otra pila y ya. Deshacer y rehacer comparten cuerpo
  (`_apply_history_snapshot`) para que no se separen al tocar uno.
- **`_editor_runtime_dirty` no valía** para saber si hay cambios sin guardar
  —solo dice si hay que refrescar las vistas 3D—, así que hay una marca nueva,
  `_unsaved_changes`, que se levanta con cada acción y se baja al guardar o
  cargar.

### El guardarraíl

`tools/validate_editor_ui_affordances.gd`, en la suite. Tres reglas, y las tres
son de las que se rompen solas al añadir un control:

1. Todo control interactivo dice qué hace.
2. Todo campo numérico dice en qué unidad está.
3. Los dos paneles se pueden desplazar.

Sin él, esta lista se vuelve a llenar con el siguiente control que se añada.

### Lo que quedaba al cerrar esa tanda

E-5 (interruptor de ayuda oculto), E-6 (atajos), E-7 (foco de teclado), E-9
(copiar/pegar), E-10 (tildes), E-11 (iconos) y E-12 (el monolito).

---

## 8. El teclado y el texto — segunda tanda del 2026-09-07

### Corrección a la propia auditoría: E-5 no era un mando escondido

Escribí que `HoverHelpRow` tiene `visible = false` en la escena y que por tanto
el usuario **no puede apagar** la ayuda contextual. Lo primero es cierto; lo
segundo, no. El interruptor pertenece a la pestaña **Dibujo**, y
`_sync_left_editor_tab_visibility()` lo enseña en cuanto esa pestaña está activa.

Lo que pasaba de verdad es peor de explicar y más fácil de arreglar: **el editor
abría por la pestaña Archivo** (`_active_left_tab = EditorLeftTab.SCENARIO`). Lo
primero que se veía al entrar en un editor de planos era guardar, cargar y
exportar, y las herramientas de dibujo —con ellas las plantas, la lista de
elementos y el interruptor de la ayuda— quedaban a un clic de distancia sin que
nada lo indicara. Ahora abre por Dibujo, que es donde se trabaja.

Medir el `.tscn` no bastaba para verlo. Por eso hay una sonda,
`tools/probe_editor_visibility.gd`, que instancia el editor y dice qué se ve de
verdad al arrancar en vez de qué guarda la escena.

### La escena no es la fuente de verdad del texto ni del foco

Este es el hallazgo que más tiempo ahorra a la siguiente sesión. La convención
del repo —«la UI vive en la escena»— vale para la estructura, pero **el script
reescribe en tiempo de ejecución el texto, el tooltip y el foco de los mandos**:

| Lo que se toca en la escena | Quién lo pisa al arrancar |
|---|---|
| `text` de las 14 herramientas | `_bind_existing_ui()`, desde `i18n/es_ui.json` |
| `tooltip_text` de las herramientas | `_register_tool_button()` → `_tool_tooltip()` |
| `focus_mode` de botones, desplegables y listas | `_style_editor_controls()`, en cuatro sitios |
| texto de la guía rápida | `_editor_help_text()` |

O sea: quitar `focus_mode = 0` de los 57 controles de la escena no devolvía el
tabulador, y escribir `SELECCIÓN` en el botón no cambiaba lo que se leía. Las
correcciones de abajo están hechas donde manda —el script y el JSON de textos—,
y el guardarraíl **instancia el editor y lo arranca** en vez de leer el `.tscn`,
que era lo único que podía detectarlo.

### Lo que se ha hecho

| Hallazgo | Antes | Ahora |
|---|---|---|
| E-5 | se abría por Archivo, con el interruptor de ayuda en otra pestaña | abre por Dibujo; sonda que lo comprueba |
| E-6 | 0 atajos para 14 herramientas | 15 teclas, anunciadas en cada tooltip y en la guía |
| E-7 | 93 controles sin foco en ejecución | 0; `Tab` recorre el editor |
| E-10 | el texto de pantalla, sin tildes | ~270 tildes y eñes en 86 líneas de texto |
| E-11 | `SEL`, `DETECT.`, `VICT.` | `SELECCIÓN`, `DETECTOR`, `VÍCTIMA` (iconos, aún no) |

Detalles que merecen quedar escritos:

- **Los atajos y su anuncio salen de la misma tabla.** `TOOL_SHORTCUTS` la lee el
  teclado, `_tool_tooltip()` la escribe en cada herramienta y
  `_tool_shortcuts_line()` arma con ella la página «Teclas» de la guía. No pueden
  discrepar. Los dígitos siguen el orden de la barra y las letras son la inicial
  de lo que colocan (`D` detector, `V` víctima, `F` inicio FP, `I` ignición);
  `Esc` vuelve a Selección, y se añaden `Ctrl+S` guardar y `Ctrl+O` cargar.
- **Escribir «sala» en un nombre ya no cambia cuatro veces de herramienta.**
  `_keyboard_is_typing()` cede el teclado a `LineEdit`, `TextEdit` y `SpinBox`
  cuando tienen el foco. Sin eso, los atajos y el foco de teclado se estorban.
- **`SpinBox` nace sin foco**: no bastaba con dejar de apagarlo, había que
  pedirlo. Es la razón de que quedaran casillas inalcanzables con `Tab` aun
  después de limpiar la escena.
- **Los nombres cortados venían del JSON de textos**, no de la escena:
  `"editor.tool.detector": "Detect."`. Ahora hay una sola lista, `TOOL_NAMES`,
  que usan el botón y la guía, para que la ayuda no anuncie un nombre que el
  botón ya no lleva.
- **Las tildes se han puesto solo en el texto de pantalla.** El código y los
  comentarios siguen sin ellas, que es la convención del repo y no la lee nadie
  desde la aplicación.

### El guardarraíl, ampliado

`tools/validate_editor_ui_affordances.gd` pasa de tres reglas a siete. Las cuatro
nuevas:

4. Todo control se alcanza con el teclado (`focus_mode != 0`).
5. Cada herramienta dice su tecla y lleva el nombre entero, sin cortar.
6. El texto que lee el usuario lleva tildes. La lista `MISSPELLED` solo recoge
   palabras que **siempre** son falta —«habitacion», «victima»—; las ambiguas
   («esta», «mas», «solo») se quedan fuera a propósito, para que la regla no dé
   falsos positivos y acabe desactivada.
7. Las teclas anunciadas cambian de herramienta **de verdad**: la regla 5 mira el
   tooltip, esta pulsa las 15 teclas y comprueba `current_tool`. Anunciar un
   atajo que no responde es peor que no tenerlo.

### Lo que quedaba al cerrar esa tanda

E-9 (copiar, pegar y duplicar), E-11 en su otra mitad (ningún icono en la barra)
y E-12 (el monolito de 7435 líneas).

---

## 9. Copiar, pegar y duplicar — 2026-09-07

### Corrección a la propia auditoría: E-9 no era «no hay nada»

Escribí que para copiar «no hay nada» y que lo único parecido era
`_copy_stairs_from_level_to_level`. Es falso: el menú del botón derecho ya traía
**«Duplicar objeto»** desde antes de la auditoría. Lo miré por atajos y por el
panel, y no abrí el menú contextual.

Lo que sí era cierto es lo que importaba —**no se podía duplicar una
habitación**, que es la operación cara— y, al abrir esa función para
generalizarla, resultó que la que había tenía tres fallos:

- **No pasaba por deshacer.** `_duplicate_object_at_context()` no llamaba a
  `_push_undo_snapshot()`, así que un objeto duplicado por error no se podía
  deshacer, y el editor tampoco se marcaba como «con cambios sin guardar».
- **Clonaba el foco de ignición.** Duplicar el sofá que arde daba dos objetos con
  `is_primary_ignition_source = true`, y el escenario pasaba a contradecirse
  consigo mismo.
- **Repetía ids.** `_next_object_id()` devolvía `"obj_%03d" % (cuántos hay + 1)`,
  y lo mismo hacían los de detectores y víctimas. Basta borrar uno y crear otro
  para tener dos `obj_003`. Duplicar multiplica esas coincidencias, que es
  justamente lo que iba a hacer la función nueva.

### Lo que se ha hecho

Tres verbos, un solo camino: **Ctrl+C** copia la selección, **Ctrl+V** la pega
donde esté el cursor y **Ctrl+D** duplica al lado del original. Funcionan con
habitaciones, objetos, detectores y víctimas.

| | Antes | Ahora |
|---|---|---|
| Duplicar habitación | no existía | con sus objetos, detectores y víctimas |
| Duplicar objeto | menú contextual, sin deshacer | los tres verbos, con deshacer |
| Pegar | no existía | en el cursor, o donde se pulsó el botón derecho |

Las decisiones que merecen quedar escritas:

- **Una habitación se lleva lo que hay dentro** —objetos, detectores y víctimas—,
  que es lo que hacía cara la copia a mano. Sus posiciones son locales a la sala,
  así que basta apuntarlas a la copia para que caigan en el mismo sitio.
- **No se lleva sus puertas ni sus ventanas.** Una apertura une dos salas
  concretas por un paramento concreto; copiarla dejaría una puerta a ninguna
  parte. El editor lo dice en la línea de estado en vez de callárselo.
- **La copia cae en la planta que se está editando**, no en la del original. Es
  lo que convierte «duplicar una habitación» en «repetir la distribución de la
  planta baja en la primera».
- **El foco de ignición no se clona nunca**, ni al duplicar un objeto ni al
  duplicar la sala entera.
- **Duplicar no toca el portapapeles.** Quien copia una cosa y duplica otra
  espera que Ctrl+V siga pegando la primera.
- **Los nombres no encadenan sufijos**: «Salón» → «Salón (copia)» → «Salón
  (copia 2)», no «Salón (copia) (copia)».
- **Los ids ahora son el primer hueco libre**, no un contador. Arregla también la
  creación normal, que ya repetía ids sin que nadie lo hubiera notado.

### Un fallo simétrico que apareció al escribirlo

Duplicar una sala tiene que llevarse sus detectores y sus víctimas; **borrarla
tenía que dejárselos, y no lo hacía**. `_delete_room()` limpiaba las aperturas y
el punto de inicio del jugador, pero dejaba detectores y víctimas apuntando a un
`room_id` que ya no existe. Y `Serializer.validate_scenario()` no mira esas dos
listas, así que el escenario roto no se veía al validar: se veía al ejecutar.
Ahora se van con la sala.

### El guardarraíl, regla 8

La regla nueva monta una sala con un objeto encendido, un detector y una víctima,
la duplica y comprueba lo que ha salido: que la copia existe con su geometría,
que se lleva lo de dentro con ids nuevos, que **no** clona el foco de ignición,
que borrarla no deja huérfanos y que deshacer la revierte. Es la única regla que
toca los datos del editor, y lo hace sobre la instancia headless.

### Lo que sigue pendiente

E-11 en su otra mitad (ningún icono en la barra de herramientas) y E-12 (el
monolito de 7435 líneas, que ya son 7997). El segundo es el que encarece
todo lo demás.
