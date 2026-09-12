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

> **Nota de vigencia (2026-09-10).** Esta auditoría se escribió el 6 de
> septiembre y sus §7-§16 cubren las tandas del día 7. Lo que el editor ganó
> **los días 8, 9 y 10** —3D en vivo, dibujo directo en 3D, catálogo de
> mobiliario, revisión previa, copia de planta, idiomas, calidad gráfica— no
> estaba escrito en ninguna parte salvo en los mensajes de commit, y eso era el
> hallazgo **D-5** de `ESTADO_Y_PLAN_2026-09-09.md`. **Está al día desde el §17**,
> que es el estado del editor hoy.

---

## 1. Resumen

| # | Hallazgo | Sev. | La cifra | Estado |
|---|---|---|---|---|
| E-1 | Controles sin ninguna explicación | 🔴 | **62 de 99** | ✅ **corregido** (§7) |
| E-2 | Campos numéricos sin unidad | 🔴 | **36 de 36** | ✅ **corregido** (§7); un camino se quedó sin actualizar la unidad y lo destapó §12 |
| E-3 | Ningún panel tiene barra de desplazamiento | 🟠 | 31 secciones, repartidas en 3 pestañas | ✅ **corregido** (severidad rebajada, §7) |
| E-4 | No hay rehacer | 🔴 | 48 pasos de deshacer, 0 de rehacer | ✅ **corregido** (§7) |
| E-5 | El interruptor de la ayuda contextual está oculto | 🟠 | `visible = false` | ✅ **corregido** (§8); el diagnóstico era otro: abría por la pestaña equivocada |
| E-6 | Ningún atajo de teclado para las herramientas | 🟠 | **0** `shortcut`, 14 herramientas | ✅ **corregido** (§8): 15 teclas |
| E-7 | No hay navegación por teclado | 🟠 | **57** controles con `focus_mode = 0` | ✅ **corregido** (§8): eran 93 en ejecución, ahora 0 |
| E-8 | Se sale del editor sin avisar de cambios sin guardar | 🟠 | `_cancel_pressed()` cambia de escena y ya | ✅ **corregido** (§7) |
| E-9 | No hay copiar, pegar ni duplicar | 🟠 | — | ✅ **corregido** (§9); el hallazgo estaba mal medido: duplicar objeto ya existía, y con tres fallos |
| E-10 | Texto de ayuda sin tildes junto a etiquetas con tildes | 🟡 | 1 bloque, ~12 palabras | ✅ **corregido** (§8): ~270 tildes y eñes en 86 líneas |
| E-11 | Herramientas con abreviaturas y sin icono | 🟡 | **0** iconos; "SEL", "DETECT.", "VICT." | ✅ **corregido** (§8 nombres, §10 iconos) |
| E-12 | El script del editor es un monolito | 🟠 | 7435 líneas, 377 funciones, 1 `@onready` | ✅ **cerrado en lo que valía la pena** (§11–§16): 6871 líneas y cuatro módulos fuera |

**Los doce hallazgos están cerrados** (2026-09-07). Las secciones §7 a §16 cuentan
cada tanda, incluidas **cuatro correcciones a esta misma auditoría**: E-3 estaba
sobredimensionado (§7), E-5 no era un mando escondido sino una pestaña de
arranque equivocada (§8), E-9 decía «no hay nada» cuando el menú contextual ya
duplicaba objetos (§9) y el módulo de escaleras que saqué duplicaba el de la
línea visual (§13).

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

### Lo que quedaba al cerrar esa tanda

E-11 en su otra mitad (ningún icono en la barra de herramientas) y E-12 (el
monolito de 7435 líneas, que ya son 7997).

---

## 10. Los iconos, y mirar en vez de medir — 2026-09-07

### E-11, la mitad que faltaba

Catorce iconos de línea en `ui/icons`, SVG de 24 unidades de lienzo y 18 px de
salida, trazo blanco. El color lo pone el tema según el estado del botón, así que
**la herramienta activa enciende su icono con el mismo naranja que su etiqueta**.
Se sirven desde `TOOL_ICONS`, al lado de `TOOL_NAMES`, por la razón de la
sección 8: en la barra manda el script, no la escena.

Los SVG se importan sin abrir el editor de Godot —`godot --headless --path .
--import`— y sus `.import` van al repositorio como los del resto de recursos.

### Dos iteraciones, porque a 18 px un trazo de más es una mancha

`tools/probe_tool_icons.gd` los pega en una hoja de contactos ampliada ×6 sobre
el fondo del editor. Seis de los catorce no pasaron la primera mirada:

| Icono | Qué se leía | Qué se hizo |
|---|---|---|
| Detector | `(o)`: los arcos, pegados al punto | el punto abajo y las ondas abriéndose |
| Ignición | una gota de agua | mordisco lateral, que es lo que distingue fuego de agua |
| Víctima | tendida, un palo con un círculo | de pie; el ojo ya ocupa «primera persona» |
| Objeto | rectángulo con raya: una ficha | sofá en planta, como el editor dibuja los muebles |
| Puerta | el símbolo de plano salía banderín | la hoja y su pomo |
| Exterior | idéntico a Pasillo | trazo grueso, que es lo que dice «muro» |

Y una séptima en la siguiente pasada: **Ventana** partida solo en vertical se
confundía con el sofá de **Objeto**, que está a su lado en la barra. Cuatro hojas.

### El icono rompió la barra, y el guardarraíl lo dijo

Añadir 18 px a cada botón ensanchó la barra 52 px. Está centrada y crece sola con
su contenido, así que **se metió debajo del panel izquierdo**, donde los botones
dejan de poder pulsarse. La regla 9 lo cazó con el número exacto: barra en
`x 264..1016`, panel en `x 0..296`.

La barra pasa de 7 columnas a **5** (tres filas). No es solo que quepa: con cinco
columnas, cada herramienta nueva la hace crecer **hacia abajo**, que es espacio
que sobra, en vez de hacia los lados, que es donde están los paneles.

### Medir no es mirar

El guardarraíl comprueba que todo tenga explicación, unidad, foco, tilde, tecla,
icono y sitio. Nada de eso ve lo que el usuario dijo: *«no se ve profesional»*.
`tools/capture_editor_ui.gd` abre el editor con ventana real y guarda un PNG. La
primera captura enseñó dos cosas que ninguna regla estaba mirando:

- **La casilla «Ayuda contextual» se leía como una alarma.** `CheckBox` no estaba
  definido en el tema, y Godot cae al tipo padre: heredaba de `Button` el
  recuadro y el texto naranja de *pulsado*. Marcada parecía un error. Ahora la
  casilla marcada tiene el aspecto normal y el naranja se reserva a la marca,
  que es lo que dice «esto está encendido». Nadie lo había visto porque hasta la
  tanda anterior **el interruptor estaba en una pestaña que no era la de
  arranque** (E-5).
- **«Modo 2D: editor clasico activo.»** Una tilde suelta en la línea de estado,
  que la regla 6 no cazaba porque «clasico» no estaba en su lista. Está añadida,
  con cinco palabras más, y de paso se corrigieron las que quedaban fuera del
  editor en `i18n/es_ui.json`: «SIMULADOR TÁCTICO», «gráficas»,
  «Probabilística».

### El guardarraíl, regla 9

Cada herramienta lleva icono, le cabe el nombre entero —se compara el mínimo
combinado del botón con su ancho real, que es lo que se recorta cuando el icono
empuja— y la barra no se solapa con ningún panel lateral.

### Lo que quedaba al cerrar esa tanda

E-12: el monolito, 8000 líneas.

---

## 11. E-12, primer corte: borrar antes que mover — 2026-09-07

El plan para el monolito era sacar módulos por responsabilidad, como se hizo en
`view/`. Antes de mover nada conviene mirar **qué de esas 8032 líneas se ejecuta**,
y la respuesta fue incómoda: **476 no.**

### De dónde salían

La migración U7 dejó la UI del editor entera en la escena, y hay un guardarraíl
que lo vigila —`tools/validate_editor_scene_complete.gd` comprueba que ningún
nodo bajo `CanvasLayer` lo haya creado el código—. Pero los veintidós
`_ensure_*_in_existing_ui()` seguían trayendo cada uno su rama *«y si no está, lo
fabrico»*:

```gdscript
var row := section.get_node_or_null("FloorRow") as HBoxContainer
if row == null:
	row = HBoxContainer.new()      # ← nunca pasa, y lo prueba el guardarraíl
	row.name = "FloorRow"
	...
```

Más de la mitad de cada función, y con ella los textos, tamaños y márgenes que
**ya no manda nadie** porque la escena los trae escritos. Además había ocho
funciones huérfanas del viejo `_setup_ui()` —que ya ni existe—, incluidas dos
que solo llamaban a otra y una que era `pass`.

| | Antes | Ahora |
|---|---|---|
| `editor/ScenarioEditor.gd` | 8032 líneas | **7556** |
| Los 22 enlazadores | 644 líneas | 257 |
| Funciones muertas | 8 | 0 |
| `Control.new()` en el editor | 75 | 6, todos del diálogo modal de ayuda |

Los `_ensure_*_in_existing_ui` pasan a llamarse `_bind_*`: el nombre decía lo que
ya no hacen. Y donde faltaba un nodo, ahora se dice en vez de fabricarlo en
silencio, que es lo que producía la divergencia entre lo que se ve en Godot y lo
que se ve al jugar:

```gdscript
func _scene_control(parent: Node, path: String) -> Control:
	var control := parent.get_node_or_null(path) as Control
	if control == null:
		push_error("ScenarioEditor: falta %s bajo %s en ScenarioEditorScene.tscn" % [path, parent.name])
	return control
```

### Cómo se comprueba que un refactor no ha movido nada

`tools/probe_editor_ui_tree.gd` vuelca el árbol de la UI **en orden**, con la
clase de cada nodo, su visibilidad, su texto y —en las casillas numéricas— su
rango, su paso y su unidad. Una foto antes, otra después, y `diff`.

De 229 nodos, el volcado salió idéntico salvo en una cosa, y esa cosa era un
fallo que llevaba ahí desde siempre:

- **`CorridorWidthSpin` no cuelga de ninguna `CorridorWidthRow`**, sino
  directamente del `VBox`. El enlazador nuevo lo buscó donde no estaba y el
  `push_error` lo dijo en la primera ejecución. La rama muerta lo tapaba.
- **«Aplicar apertura» estaba en medio de sus propios campos.** Los
  `move_child()` del enlazador movían las filas «Abre hacia» y «Bisagra» al
  índice del botón, así que el orden en pantalla acababa siendo *Aplicar,
  Bisagra, Abre hacia* aunque la escena tuviera guardado el orden correcto. Al
  quitar los `move_child` manda la escena: los campos primero y el botón al
  final.

El resto de los `move_child()` que se quitaron —lista de elementos, planta del
piso, posiciones de objeto, detector y víctima— no cambiaron nada: eran no-ops
que reordenaban la escena a la posición que la escena ya tenía.

### Por qué borrar antes que mover

Sacar el panel de propiedades a su módulo son 58 variables de nodo y 599
referencias repartidas por el fichero. Hacerlo **sobre código muerto** es
mudanza de muebles rotos: se paga el traslado dos veces. Con el camino muerto
fuera, lo que quede de cada responsabilidad es lo que de verdad hay que mover.

### Lo que quedaba al cerrar ese corte

7556 líneas y 398 funciones, con el panel de propiedades como siguiente costura.

---

## 12. E-12, segundo corte: el panel de propiedades se va a su módulo

`editor/EditorPropertyPanel.gd`, 700 líneas. Se lleva **53 mandos** del lado
derecho y el reparto de lo que enseña cada uno.

### La costura

El módulo **solo sabe de mandos**. No conoce `editor_data`, ni qué hay
seleccionado, ni el deshacer:

- `show(state)` recibe en un diccionario lo que hay que enseñar y lo reparte.
- `read_room()`, `read_object()`, `read_opening()`… devuelven lo que el usuario
  ha tecleado, sin interpretarlo.
- `action_requested("room_apply")` **pide**; no hace. Los nueve botones del panel
  emiten una acción y el editor decide, porque es quien tiene los datos, el paso
  de deshacer y la línea de estado.

Lo que el panel no puede calcular por su cuenta va calculado desde el editor
dentro de `state`: el rectángulo de la sala, si es escalera, el texto del ángulo
de subida, la posición **visual** del objeto —que depende de su giro— y los topes
de ancho y desplazamiento de la apertura. Esa es la línea: la geometría y las
reglas se quedan donde están los datos; el panel pone widgets.

| | Antes | Ahora |
|---|---|---|
| `editor/ScenarioEditor.gd` | 7556 líneas | **7067** |
| Variables de nodo en el editor | 53 del panel | 0 |
| `_refresh_property_panel()` | 185 líneas | 43, y son de juntar datos |
| `editor/EditorPropertyPanel.gd` | — | 700 |

El total sube unas 200 líneas, y está bien que suba: son la cabecera del módulo,
las declaraciones y el diccionario de estado, o sea el precio escrito de la
frontera. Lo que baja es el fichero que había que leer entero para tocar
cualquier cosa.

### La red: una sonda que mira lo que enseña el panel

Mover 53 mandos a ciegas no es refactorizar, es apostar.
`tools/probe_editor_property_panel.gd` monta un escenario con una sala, una
escalera, un objeto encendido, una apertura, un detector, una víctima y un muro;
los selecciona uno a uno y vuelca, en cada caso, **el estado de todos los mandos
del panel**: visible, editable, valor, texto, opción elegida y unidad. Mil cien
líneas de foto.

De esas mil cien, el diff antes/después tiene **tres**, y las tres son un fallo
que llevaba ahí desde siempre:

> **El umbral del detector enseñaba la unidad equivocada.** Al seleccionar un
> detector de calor, el panel mostraba `57` con el sufijo `kg/m³`, que es la
> unidad del humo.

La causa es de manual: había **dos caminos** para rellenar la ficha del detector.
`_sync_detector_property_fields()` —el que se usa al arrastrar el detector por el
plano— sí llamaba a `_sync_detector_threshold_units()`; el bloque equivalente
dentro de `_refresh_property_panel()` —el que se usa al **seleccionarlo**, que es
lo que hace todo el mundo— no. Dos copias del mismo relleno, una con la línea y
otra sin ella. Al unificarlas en `fill_detector()` el fallo se fue solo.

Es exactamente el fallo que E-2 decía haber cerrado: *«teclear 2,4 donde iban
240 no lo avisa nadie»*. La unidad estaba puesta, pero el camino más usado no la
actualizaba.

### Lo que quedaba al cerrar ese corte

7067 líneas, con el dibujo del plano, la entrada de ratón y las escaleras como
siguientes costuras.

Y una regla que ese corte dejó escrita: **antes de mover, una sonda que
fotografíe lo que se va a mover**.

---

## 13. E-12, tercer corte: las escaleras salen del editor, y aparece una copia

`editor/StairPlanRules.gd`, 138 líneas de **funciones estáticas puras**: entran
un rectángulo, una dirección y un modo de giro, y sale un número o una palabra.
No tocan `editor_data`, ni la escena, ni la selección.

### El corte se hizo dos veces, y la segunda es la que importa

La primera versión del módulo se llamaba `editor/StairGeometry.gd` y traía las 18
funciones puras del editor. Al ir a escribir esto apareció el problema: **ya
existe `view/geometry/StairGeometry.gd`**, el módulo que comparten el mundo FP y
el visor 3D, y cinco de esas funciones —`long_span_m`, `cross_span_m`,
`ramp_width_m`, `top_landing_depth_m` y `vertical_void_rect`— ya estaban ahí,
**línea por línea iguales**.

O sea que el editor no tenía «geometría de escaleras»: tenía **una copia** de la
de la línea visual. Y eso es exactamente lo que la regla de esa línea prohíbe:
*al tocar geometría de una vista, el cambio va al módulo, no a la copia*. Si
alguien hubiera cambiado el hueco vertical en `view/geometry/`, el 3D habría
construido un hueco y el plano del editor habría seguido dibujando el viejo, sin
que nadie se enterara: no hay ningún guardarraíl que compare el editor con la
vista, porque nadie sabía que había dos.

Sacar el módulo lo destapó, y el arreglo es no tener módulo nuevo para eso: las
cinco se borran y el editor llama a `view/geometry/StairGeometry.gd`. Lo que
queda en `StairPlanRules` es lo que sí es del editor de planos: el vocabulario
—`MODE_AUTO` no es «sin decidir», es «180 si cabe, recta si no»—, lo que se
deduce de un arrastre o de una sala, y la pendiente que se enseña en el panel.

### Qué se fue y qué se quedó

De las 428 líneas de escalera repartidas por el editor, **más de la mitad no
necesitaban nada de él**. Se fueron 18 funciones: los tramos y el descansillo
(`long_span_m`, `cross_span_m`, `ramp_width_m`, `landing_depth_m`), la decisión
del giro (`can_use_180_landing`, `turn_degrees_for_mode`), el hueco vertical que
la escalera abre en el forjado (`vertical_void_rect`), la pendiente
(`slope_angle_deg`) y el vocabulario —auto, recta, 180—, que vive donde
significa algo: `MODE_AUTO` no es «sin decidir», es «180 si cabe, recta si no».

Se quedaron en el editor las que necesitan datos: crear la escalera y su planta
de arriba, copiarla entre niveles, mantener sincronizados los huecos verticales y
buscar **cuánto sube** —que se lee del hueco vertical o de la cota de la planta
siguiente, y eso es escenario, no geometría—. La pendiente quedó partida por esa
misma línea:

```gdscript
func _stair_slope_angle_deg(room_id: int, room: Dictionary, rect: Rect2) -> float:
	return StairGeometry.slope_angle_deg(
		rect,
		StairGeometry.run_direction_for_room(room),
		float(room.get("stair_turn_degrees", 0.0)),
		_stair_rise_for_room(room_id, room)   # ← lo único que hace falta del escenario
	)
```

| | Antes | Ahora |
|---|---|---|
| `editor/ScenarioEditor.gd` | 7067 líneas | **6929** |
| `editor/StairPlanRules.gd` | — | 138 |
| Funciones de escalera en el editor | 39 | 21 |
| Copias de `view/geometry/StairGeometry.gd` | 5 | **0** |

### La sonda que pregunta a los dos lados

`tools/probe_stair_geometry.gd` recorre una malla de seis rectángulos —incluido
uno vacío y uno demasiado estrecho para el descansillo—, cinco direcciones
—incluida una diagonal— y los modos de giro, con dos alturas de planta, y vuelca
cada resultado con **seis decimales**: 747 líneas de tabla.

Lo que la hace útil es que el mismo fichero pregunta a los dos lados: se le dice
`editor` y llama a los métodos del editor, o `modulo` y llama a las estáticas —a
las de `StairPlanRules` y, en las cinco compartidas, a las de
`view/geometry/StairGeometry.gd`—. Así la foto de antes y la de después salen del
mismo código, y comparar es un `diff` de verdad y no una traducción a ojo.

Salió **idéntica**, y esa igualdad dice dos cosas: que la mudanza no cambió
ningún número, y que **la copia del editor y el módulo de la línea visual
calculaban exactamente lo mismo** el día que se juntaron. Que es la única prueba
que se puede dar de que la duplicación aún no había divergido.

### Lo que quedaba al cerrar ese corte

6929 líneas, con el dibujo del plano y la entrada de ratón como costuras
difíciles.

---

## 14. E-12, cuarto corte: la geometría del plano, y una red de píxeles

`editor/PlanGeometry.gd`, 164 líneas y 16 funciones estáticas puras:
rectángulos girados, la caja de un objeto dentro de su sala, distancias a un
segmento y el largo de un paramento.

### Por qué esta antes que el dibujo

El corte que tocaba era el dibujo, y no salió: `_draw_*` no lee datos, lee
**estado de interacción** —zoom, arrastre en curso, herramienta, selección— y sus
colores son `@export`, que por la regla del repo tienen que seguir en el
inspector. Sacarlo bien pide una paleta y una vista de datos ya resueltos; hacerlo
mal es mover el fichero y dejar que el módulo llame de vuelta al editor, que es
un círculo con otro nombre.

Pero al mirar de qué depende el dibujo apareció algo mejor: **las funciones que
lo bloquean no son suyas**. Rectángulo girado, esquinas de un objeto, centro,
distancia a un segmento… las usan las **tres** cosas que trabajan sobre el
plano: el dibujo para pintar, los clics para saber qué has tocado y el panel para
enseñar la posición. Por eso estaban repartidas por el fichero. Sacarlas paga por
sí sola y deja el dibujo a tiro.

| | Antes | Ahora |
|---|---|---|
| `editor/ScenarioEditor.gd` | 6929 líneas | **6803** |
| `editor/PlanGeometry.gd` | — | 164 |
| Dueños de `GRID_M` | 1 constante suelta | el módulo, y el editor le da nombre corto |

### El fallo: `north` medía el lado equivocado

El editor calculaba el largo de un paramento así:

```gdscript
if wall == "top" or wall == "bottom":
	return rect.size.x
return rect.size.y
```

Comparación de cadena a pelo. Cualquier alias cardinal —`"north"`, `"south"`—
caía en el `return` de abajo y devolvía el lado **vertical** de una pared
horizontal. La línea visual ya se comió ese fallo una vez (el mundo FP plantaba
las ventanas del norte en la pared derecha) y lo cerró con
`WallSideGeometry.canonical()`; el editor seguía con su copia del problema.

Hoy no rompe nada, y conviene decirlo con precisión: **ningún escenario del repo
usa nombres cardinales** —los únicos `"north"` están en el fixture del validador
de paridad, que existe justo para probar los alias—. Era un fallo latente, de los
que esperan a que alguien cargue una plantilla escrita a mano. Ahora el editor
pasa por el mismo módulo que la vista.

### Dos redes, y una de ellas nueva

- **La tabla** (`tools/probe_plan_geometry.gd`), como la de las escaleras: tres
  rectángulos, nueve ángulos —incluidos 360 y 405—, tres tamaños de objeto y seis
  nombres de pared, con seis decimales. 2154 líneas. El diff antes/después tiene
  **cuatro**, y las cuatro son `wall_length(rect, "north")`, o sea el arreglo.
- **Los píxeles** (`tools/capture_editor_plan.gd`), que es la red que faltaba
  para el dibujo. Monta un piso con una de cada cosa, fija la cámara y el zoom a
  mano —nada de ratón— y guarda **nueve fotos**: el plano quieto, una sala
  seleccionada, un objeto, una apertura, y los arrastres de sala, escalera,
  pasillo y muro, más la planta alta con el fantasma de la de abajo. Las
  situaciones de arrastre se montan tocando el estado del editor, que es la única
  forma de fotografiar un arrastre sin manos.

  Antes de fiarse de ella hay que comprobar que el render es determinista: dos
  pasadas seguidas dan **los mismos bytes**. Lo es. Tras el corte, las nueve
  fotos siguen siendo byte a byte idénticas.

### Lo que quedaba al cerrar ese corte

6803 líneas, con el dibujo del plano ya con red pero sin decidir su frontera.

---

## 15. E-12, quinto corte: el dibujo se parte en decidir y pintar

`_draw()` pasa de 365 líneas repartidas en once funciones a **seis**:

```gdscript
func _draw() -> void:
	if _editor_view_mode != EditorViewMode.MODE_2D:
		return
	EditorDraw2D.plan(self, _plan_view())
	_draw_drag_preview()
```

`_plan_view()` junta el escenario con el estado de la interfaz y devuelve el
plano **ya resuelto**: posiciones en píxeles, colores elegidos y textos
escritos. `EditorDraw2D.plan()` lo pinta y no sabe de escenarios, ni de qué
planta se edita, ni de qué hay seleccionado. Lo que se está arrastrando ahora
mismo se queda en el editor —eso no es el plano, es la interacción.

### El precio, dicho sin adornos

| | Antes | Ahora |
|---|---|---|
| `editor/ScenarioEditor.gd` | 6803 líneas | **6851** |
| `editor/EditorDraw2D.gd` | 229 | 422 |

**El editor no adelgaza: engorda 48 líneas.** Los datos del plano ya viven ahí,
así que lo único que se puede mover es el pintado; y escribir «esta sala se ve
así» en un diccionario con sus claves es más largo que pintarla a pelo. Lo que
cambia es de qué son esas líneas: antes eran `draw_rect` y `draw_string`
mezclados con el filtro de planta y la elección de color; ahora son decisiones.

Probé la alternativa —que el pintor leyera el escenario directamente y así el
editor sí encogiera— y la descarté a medias: obligaba a reimplementar dentro del
pintor el filtro de planta, la búsqueda de sala por id, el nombre visible y el
tramo de cada apertura. Es decir, **una copia de la lógica del editor dentro del
módulo de dibujo**, que es exactamente el fallo que destapó el corte de las
escaleras. Entre un fichero 400 líneas más corto y una copia menos, la copia
menos.

### La sonda tenía dos agujeros, y los dos los enseñó ella misma

La red de píxeles del corte anterior falló dos veces antes de servir, y las dos
por lo mismo: **una foto sin manos no está quieta**.

1. **El cartel de la ayuda contextual.** La primera comparación dio ocho fotos
   iguales y una distinta… porque en una salió el cartelito que aparece donde
   reposa el ratón. No era el dibujo: era el puntero físico, parado sobre la
   escalera, y un temporizador que cruzó el fotograma en una pasada y no en la
   otra. La sonda ahora apaga la ayuda contextual antes de disparar.
2. **El ratón reescribiendo el arrastre.** Con un arrastre en curso, cualquier
   movimiento del ratón de verdad —y el sistema manda uno al abrirse la
   ventana— reescribe `drag_current_m` con la posición real del cursor. Se veía
   clarísimo cuando por fin se miró: el muro salía **en diagonal** y medía 10,51
   m en vez de los 8,00 que decía la pose. La sonda ahora vuelve a poner la pose
   en cada fotograma, no solo al empezar.

Y una lección sobre la comprobación de determinismo del corte anterior: dos
pasadas seguidas daban los mismos bytes, y aun así la sonda no era determinista.
Claro: entre esas dos pasadas **el cursor no se había movido**. Comprobar que
algo repite no es comprobar que no depende de nada.

Con los dos agujeros tapados, las nueve fotos salen **byte a byte iguales**
antes y después del corte, y el volcado del árbol de la UI también.

### Lo que quedaba al cerrar ese corte

6851 líneas, con la entrada de ratón como última costura.

---

## 16. E-12, sexto corte: el arrastre pasa a tener nombre

Las cuatro banderas del ratón —`is_dragging_exterior_wall`, `is_dragging_room`,
`is_dragging_room_geometry`, `is_dragging_object`— son **excluyentes**: no se
puede estar trazando un muro y girando un objeto a la vez. Cuatro booleanos
permiten dieciséis combinaciones para describir cinco situaciones; las once
sobrantes son estados que el código no sabe dibujar y que nada impedía.

Ahora son un estado:

```gdscript
enum Drag { NONE, EXTERIOR_WALL, ROOM_RECT, ROOM_GEOMETRY, OBJECT }
var drag: int = Drag.NONE
```

Con eso desaparece también una fragilidad silenciosa: `_handle_release()`
comprobaba primero la geometría de sala y después el objeto, así que si las dos
banderas hubieran estado encendidas a la vez, el arrastre del objeto **nunca
habría terminado** y nadie se habría enterado. Con un estado, la pregunta no se
puede hacer mal.

### La sonda de gestos, y el fallo que cazó en mi propio cambio

Ninguna red anterior tocaba esto: el árbol mira la UI, el volcado del panel mira
los mandos y las fotos miran el plano dibujado. `tools/probe_editor_mouse.gd` da
**gestos completos** —pulsar, mover, soltar, en metros del plano— con cada
herramienta, y vuelca lo que queda: selección, estado del arrastre, anclas y el
escenario entero en JSON ordenado. Incluye pasos `dump` a **mitad** del gesto,
que es donde vive la memoria de la máquina: con el arrastre abierto.

El diff antes/después salió con dos líneas distintas, y eran un fallo mío:

> Al soltar el objeto después de un movimiento de sala fallido, el editor dejaba
> de decir «Objeto movido» y el modo de objeto se quedaba colgado.

La causa es la traducción automática de las banderas. El código tenía abandonos
así:

```gdscript
func _update_dragged_room_geometry(pos_m: Vector2) -> void:
	if selected_room_id < 0:
		is_dragging_room_geometry = false   # apagar LA MIA
		return
```

**«Apagar mi bandera» no es «cancelar el arrastre».** Con cuatro booleanos,
apagar el propio era inofensivo si ya estaba apagado; con un estado único,
borrarlo a secas cancela el arrastre **de otro**. Los tres abandonos de ese tipo
pasan por `_cancel_drag_if(Drag.X)`, que solo cancela si el arrastre en curso es
el suyo.

Es el mismo patrón que en el corte del panel de propiedades: la unificación no
solo ahorra código, **obliga a responder una pregunta que las copias evitaban**.
Allí era «¿qué unidad tiene este umbral?»; aquí, «¿cancelar qué?».

### El precio

| | Antes | Ahora |
|---|---|---|
| `editor/ScenarioEditor.gd` | 6851 líneas | **6871** |
| Banderas de arrastre | 4 booleanos, 16 combinaciones | 1 estado, 5 valores |

Veinte líneas más, que son el `enum` con sus comentarios y el ayudante de
cancelación. No es un corte de tamaño: es de vocabulario.

### Lo que sigue pendiente

E-12 se puede dar por cerrado en lo que valía la pena. El fichero es **6871
líneas** frente a las 8032 del principio, con cuatro módulos fuera
—`EditorPropertyPanel`, `StairPlanRules`, `PlanGeometry` y las capas de dibujo
en `EditorDraw2D`— y una máquina de estados con nombres. Lo que queda dentro es
sobre todo la lógica del escenario —salas, aperturas, plantas, ficheros—, que es
de lo que trata el editor.

Y queda el activo que más va a durar: **seis sondas** que fotografían el editor
desde seis ángulos antes de tocarlo —árbol de la UI, mandos del panel, geometría
de escaleras, geometría del plano, gestos de ratón y nueve capturas de
pantalla—. Cinco de los seis cortes de hoy destaparon un fallo real, y ninguno
lo destapó leyendo el código: lo destapó un `diff`.

---

## 17. D-5 — el editor de hoy, del día 8 al 10 (2026-09-10)

Los §7-§16 acaban el 7 de septiembre, con E-12 y el sexto corte. Desde ahí hubo
tres días de trabajo y **ninguna línea de documentación**: el hallazgo D-5 de
`ESTADO_Y_PLAN_2026-09-09.md` lo midió contando menciones en este mismo fichero
—*3D en vivo* 0, *revisión* 0, *catálogo* 0, *dibujar en 3D* 0, *copia de la
planta* 0— y por eso «lo que el editor hace hoy no está escrito en ninguna parte
salvo en los mensajes de commit».

Este capítulo lo arregla. **No repite el porqué de cada decisión**: el relato de
la tanda del día 10, con las causas de cada fallo, está en
[EDITOR_Y_ESCALA_2026-09-10.md](EDITOR_Y_ESCALA_2026-09-10.md), y el plan que las
ordenó, en [ESTADO_Y_PLAN_2026-09-09.md](ESTADO_Y_PLAN_2026-09-09.md). Aquí queda
**qué hay**, que es lo que se consulta al volver.

### 17.1 Las tres vistas

El editor trabaja en **2D**, **3D** y **primera persona**, y desde el día 8 el 3D
no es solo para mirar: **se dibuja directamente en él**
(`validate_editor_draw_in_3d`). Además hay un **3D en vivo** en un panel movible
y redimensionable, con cámara propia en coordenadas esféricas —arrastrar gira, la
rueda acerca— y un «Encuadrar» que **calcula** la vista desde la caja de las
salas de la planta. Reconstruir el plano no reencuadra, a propósito: si lo
hiciera, cada cambio devolvería la cámara al ángulo de fábrica.

### 17.2 Las catorce herramientas

`enum Tool`: selección, sala, pasillo en L, escalera, puerta, hueco, ventana,
objeto, ignición, inicio FP, borrar, detector, víctima y **puerta de balcón**
(balconera, añadida el 10 de septiembre al final del enum para no renumerar el
resto). Todas con icono, texto entero, tooltip, unidad y tecla.

**Colocada una cosa, la herramienta vuelve a Selección** — y solo si de verdad
creó algo: se compara la cuenta de elementos antes y después del clic, en un
único sitio, y vale igual para 2D y para 3D.

### 17.3 Los pasillos

Un arrastre da un tramo recto o en L. **La forma se puede forzar** mientras se
arrastra: `L` gira, `R` recto, y la previsualización dice cuál va a salir. Antes
lo decidía a escondidas un umbral sobre el gesto, y una diagonal moderada salía
recta sin avisar.

Los tramos **se unen solos** (`_open_passages_to_neighbours`) y un tramo pegado a
un pasillo **adopta su nombre**, así que una U es «Pasillo 3» tres veces. La
junta entre tramos del mismo pasillo **no se dibuja** como tabique.

**No se funden en una sola sala, y es deliberado**: el motor es un modelo de
zonas y cada sala es una zona bien mezclada. Un pasillo en L de doce metros como
una sola zona diría que el humo aparece a la vez en los dos extremos, que es
justo lo que un pasillo aporta a un incendio. Por eso hay un caso «CFAST:
Corridor Chain» en el repositorio.

### 17.4 Las aberturas

Se puede **cambiar el tipo** de una abertura ya puesta —era imposible, y el paso
entre tramos de pasillo nace como hueco—, con dos reglas: en un hueco
**vertical** no aparece el selector, porque es un hueco de forjado y no admite
hoja, y una **ventana** solo cabe donde hay fachada. Al pasar a hueco se fuerza
alféizar 0 y abierto; al pasar a ventana, alféizar 0,90 si no tenía.

**Balcones** (fase 4, solo en el edificio del jugador): casilla y tres medidas en
la ficha de la abertura, con tope de vuelo y ancho recortado a la fachada
**durante el arrastre** —la previsualización se pone naranja y lo dice—. Se
dibuja como una sala: a lo largo del muro el ancho, hacia fuera el vuelo.

### 17.5 El mobiliario

El catálogo pasó de 14 a **38 arquetipos** el día 9 (era D-2: un baño y una
cocina no se podían amueblar). Cada pieza tiene **vista previa 3D** en un
`SubViewport` sobre la lista, montada con **el mismo cargador que usa la vista
3D** —lo que se ve ahí es lo que se va a dibujar—, sus tres medidas debajo y si
es modelo propio o caja a escala.

> **Trampa del catálogo**: `alto` **no es la altura, es la elevación** sobre el
> suelo —0 en un sofá, 0,95 en el mueble de baño colgado—. El accesor se llama
> `elevation_m()`; la altura de verdad la sabe `FurnitureDimensions`, que es
> quien dibuja.

### 17.6 Las plantas

Crear vacía o **como copia de la actual**, fantasma de la de abajo para alinear,
y escaleras que encadenan planta a planta por las que el humo sube de verdad.
Dos datos independientes: **plantas totales** del edificio y **planta actual**.
La convención de nombres es rasante `R`, y encima `R+1`, `R+2`; se genera en
`sim/building/FloorNaming.gd` y **solo ahí**, y los escenarios guardados con la
convención vieja (`PB`, `P1`) se reescriben al cargar.

### 17.7 La cuadrícula y los paneles

- La rueda hace zoom **solo si el puntero no está sobre la interfaz**: un
  `ScrollContainer` deja de consumir el evento al llegar al final de su
  recorrido, y el zoom se disparaba al terminar de bajar una lista.
- **Se arrastra el plano con el botón izquierdo** sobre cuadrícula vacía, además
  del botón central, que en un portátil no existe.
- **Regla de escala** abajo a la izquierda: distancia redonda, paso de rejilla y
  zoom en porcentaje.
- Panel izquierdo por secciones —PLANTAS · EDIFICIO · ENTORNO · opciones de la
  herramienta activa · AYUDA Y VISTA— y pestaña LISTA agrupada por tipo, con la
  cuenta en la cabecera y los objetos sangrados bajo su sala.
- La pestaña `DIBUJO` se llama **`ESCENARIO`**.
- **La ficha de la sala se pinta la última** (D-3), por encima de muebles,
  aperturas, detectores y víctimas. Una sala girada ancla su ficha en el
  **centro**, no en la esquina del rectángulo sin girar.

### 17.8 Idiomas y configuración

**Traducción nativa de Godot**: el castellano de la escena hace de clave, así que
las 289 etiquetas y los 103 tooltips de la escena **no se tocaron**. Añadir un
idioma es añadir `i18n/<código>_strings.json` y una línea en
`UILocalization.AVAILABLE_LOCALES`.

> **La trampa**: el castellano necesita **su propia tabla, aunque sea la
> identidad**. Sin ella `TranslationServer` cae al idioma de reserva y el
> programa arrancaba en castellano y se veía en inglés.

**Calidad gráfica** en tres niveles (sombras, suavizado, escala de render y
decorado de calle), persistida en `user://simufire.cfg` y guardada al cambiar, no
al salir. **No cambia la física**: el fuego, el humo y las medidas son los mismos
en los tres niveles, y el panel lo dice.

### 17.9 El tamaño, otra vez

E-12 dejó el fichero en 6871 líneas el 7 de septiembre. Hoy:

| | líneas |
|---|---:|
| `editor/ScenarioEditor.gd` | **8713** |
| `editor/EditorPropertyPanel.gd` | 708 |
| `editor/ScenarioSerializer.gd` | 475 |
| `editor/EditorDraw2D.gd` | 453 |
| `editor/EditorPreview3D.gd` | 305 |
| `editor/ObjectLibrary.gd` | 257 |
| `editor/ScenarioReview.gd` | 227 |
| `editor/EditorObjectCatalog.gd` | 179 |
| `editor/PlanGeometry.gd` | 164 |
| `editor/StairPlanRules.gd` | 138 |

Es **D-1**, y sigue abierto. La forma del problema no es la que sugiere
«monolito»: son ~408 funciones y 155 variables de estado en **una clase**, no
funciones largas. Los dos bloques que piden módulo son los que llegaron después
del corte de E-12 —«3D en vivo» y «objetos/mobiliario»—, y los dos ya tienen la
cabeza de puente fuera (`EditorPreview3D.gd`, `EditorObjectCatalog.gd`).

### 17.10 La red que lo sostiene

**17 guardarraíles de la suite tocan el editor**, seis de ellos nuevos de los
días 9 y 10:

| guardarraíl | qué fija |
|---|---|
| `validate_editor_scene_complete` | la UI 100 % en escena; falla si un control se cuela por código |
| `validate_editor_ui_affordances` | 9 reglas de icono, texto, tooltip, unidad y foco |
| `validate_editor_interaction` | vuelta a Selección, balcón dibujado, ficha de la sala girada, encuadre del 3D en vivo |
| `validate_corridors` | la U como un pasillo, la unión automática, el tipo de abertura, la forma forzada |
| `validate_localization` | los dos idiomas, el guardado, las tres calidades, y que los textos de código traduzcan |
| `validate_object_preview` | las 38 piezas previsualizables y la ficha honesta |
| `validate_object_catalog` | todo arquetipo se puede colocar; la carga de fuego es creíble |
| `validate_floor_naming` | `R`, `R+1`, y la reescritura de la convención vieja |
| `validate_editor_live_3d` · `validate_editor_draw_in_3d` | el panel y el dibujo en 3D |
| `validate_editor_corridors` · `validate_editor_floor_copy` · `validate_editor_review` | pasillos, copia de planta, revisión previa |
| `validate_editor_stairs_climbable` | la escalera dibujada se sube en FP |
| `validate_editor_object_drag` | arrastrar mobiliario |
| `validate_editor_to_sim_flow` | del editor al motor |
| `validate_editor_load_error_dialog` | el fichero que no carga lo dice |

Y **seis sondas** que fotografían el editor antes de tocarlo: árbol de la UI,
mandos del panel, geometría de escaleras, geometría del plano, gestos de ratón y
capturas de pantalla. Sigue valiendo lo que se aprendió el día 7: cinco de los
seis cortes de E-12 destaparon un fallo real, y **ninguno lo destapó leyendo el
código; lo destapó un `diff`**.

### 17.11 Lo que queda del editor

- **D-1**, el tamaño: sacar «3D en vivo» y «objetos» a sus módulos.
- **D-6**, las sondas de captura no pasan por el camino real
  (`capture_editor_plan.gd` no llama a `_sync_floor_controls()`, y las fotos
  salen con «Salas: 0» habiendo tres). Arrastra la fiabilidad de
  `probe_editor_3d_cost`, que da 8 ms de dispersión entre pasadas de la misma
  configuración.
- **La tabla de inglés a medias**: de los **165 literales `tr()` únicos** de
  `editor/ScenarioEditor.gd`, **127 no tienen entrada** en
  `i18n/en_strings.json` (que trae 233). No rompe nada —lo que falta cae al
  castellano, que es el original— y es rellenar tabla, no tocar código. Igual
  con los tooltips largos y las descripciones de escenarios.

**D-5 queda cerrado con este capítulo.**

---

## 18. D-6 — las sondas, por el camino real (2026-09-10)

El hallazgo, tal como se midió el 6 de septiembre: `capture_editor_plan.gd`
monta el escenario inyectando `editor_data` a mano —que es lo correcto para
fotografiar un arrastre sin ratón— pero **no pasa por `_sync_floor_controls()`**,
así que todas sus fotos salían con `Salas: 0` habiendo tres salas dibujadas, y
con el mensaje de estado de otra acción mientras se arrastraba una sala.

Y la frase que lo justificaba: **una sonda que miente en un detalle obliga a
verificar todo lo que enseña**, que es justo lo contrario de para lo que está.

### 18.1 No era una sonda: eran veintiuna

Al ir a añadir la llamada que faltaba apareció el tamaño real: **21 herramientas
de `tools/` asignaban `editor_data` a mano**, 34 veces entre todas, y cada una
reproducía el trozo del camino real que recordó quien la escribió. Una añadía la
planta, otra limpiaba la selección, otra ninguna de las dos.

### 18.2 Y dentro del editor la secuencia estaba tres veces

Lo que destapó el corte, que es lo de siempre en este fichero: adoptar un
escenario estaba escrito **tres veces** —cargar por ruta, cargar de la lista y
aplicar una instantánea del historial— y las tres copias habían divergido.

| paso | cargar por ruta | cargar de la lista | instantánea |
|---|:--:|:--:|:--:|
| bloquear la pose visual de los objetos | sí | sí | **no** |
| vaciar el historial | sí | **no** | n/a |
| normalizar plantas y clamp de la actual | sí | sí | sí |
| sincronizar el tiempo de parada | sí | sí | **no** |
| `_sync_floor_controls()` | sí | sí | sí |
| ventilación (HVAC) | sí | sí | sí |
| **casilla de luces** | sí | **no** | sí |
| tipo de edificio | sí | sí | sí |
| limpiar selección | sí | sí | sí |
| **cancelar el gesto y la puerta pendiente** | **no** | **no** | sí |

Cada hueco de esa tabla es un fallo que estaba puesto y esperando:

- **Cargar un escenario desde la lista dejaba la casilla de luces con el valor
  del escenario anterior**, y el dato ya decía otra cosa.
- **Y no vaciaba el historial**: un `Ctrl+Z` después de cargar se metía en el
  escenario de antes.
- **Ninguna de las dos cargas cancelaba el arrastre en curso** ni la puerta
  pendiente: cargar a mitad de un gesto dejaba el gesto vivo, con índices de
  unos datos que ya no existían.

### 18.3 La forma del arreglo

Un solo sitio: **`ScenarioEditor.adopt_scenario_data(datos, planta)`**, que hace
la unión de las tres columnas. Los tres caminos del editor la llaman y las 21
herramientas también, así que **el camino de la sonda es el camino real** en vez
de una copia suya que se queda atrás a la primera.

Lo que **no** entra dentro es vaciar el historial, y es la única excepción con
motivo: deshacer y rehacer llaman a esta función, y si vaciara el historial se
borrarían a sí mismos. Eso se queda en quien carga.

Es pública a propósito. Un guardarraíl que solo mira código no impide que la
siguiente herramienta vuelva a inyectar el diccionario; lo impide que haya un
sitio evidente al que llamar.

### 18.4 El guardarraíl

`tools/validate_probe_paths.gd`, en la suite. Tres reglas estáticas —que la
función exista, que el editor la llame al menos tres veces, y que **ninguna**
herramienta sustituya el diccionario entero— y una de comportamiento, que es la
que importa: monta el editor, adopta un piso de tres salas y **comprueba que el
contador dice «Salas: 3»**, y que en la planta alta vacía dice «Salas: 0».

Quedan fuera a propósito dos cosas que no son adoptar un escenario: **leer**
`editor_data` (así comprueba su resultado media suite) y **tocar una clave**
(`editor_data["rooms_data"] = …`), que es modificar un escenario ya adoptado.

Probado con cuatro mutaciones, las cuatro cazadas:

| mutación | qué dijo |
|---|---|
| una herramienta vuelve a inyectar el diccionario | `validate_editor_live_3d.gd:43 asigna editor_data a mano` |
| `_undo_stack.clear()` dentro de la función común | `vacía el historial: deshacer y rehacer la llaman` |
| un camino del editor se descuelga | `solo 2 llamadas: se esperan al menos 3` |
| la propia sonda monta el escenario a mano | **`el contador de la planta dice «… Salas: 0.» con 3 salas dibujadas`** |

La última es el síntoma original de D-6, reproducido letra por letra.

### 18.5 La otra mitad: la sonda que medía mal

`probe_editor_3d_cost.gd` daba **la media de 12 pasadas** y de ahí sacaba un
veredicto tajante: «cabe / no cabe en un fotograma». La corrección del 9 de
septiembre ya la había pillado —cuatro pasadas sobre la misma configuración
dieron 17,5 · 21,9 · 23,6 · 25,4 ms, y esa misma mañana 13,5: **casi 8 ms de
dispersión, más que el efecto que se pretendía medir**— y por eso D-4 se rebajó
de hallazgo medido a sospecha fundada.

Dos cosas estaban mal, y son distintas:

1. **La media no aguanta esa distribución.** Un parón del recolector mete una
   muestra de 60 ms y arrastra la media entera; la mediana no se entera. Ahora
   reporta **mediana con banda p10-p90**, sobre 24 muestras y tirando 3 de
   calentamiento.
2. **El veredicto no puede ser más preciso que la medida.** Ahora solo se da si
   **toda la banda** cae del mismo lado del fotograma. Si la banda cruza los
   16,7 ms, la sonda lo dice —*«ESTA MEDIDA NO DECIDE»*— en vez de inventarse un
   lado. Y en las tablas comparativas, una diferencia cuyas bandas se solapan se
   marca **«dentro del ruido»** en lugar de leerse como un efecto.

### 18.6 Lo que dijo en cuanto dejó de mentir

Primera pasada con la sonda arreglada, piso de referencia (5 salas, 7 aperturas,
10 objetos):

```
rehacer la vista 3D: primera 18.6 ms, mediana 20.1 ms (p10-p90 18.0-21.9, n=24)
-> no cabe en un fotograma, pero sí en una pausa corta
```

La banda entera está **por encima** de los 16,7 ms, así que ese veredicto sí se
sostiene — y es el contrario del que se dio en julio con una sola pasada de
13,5 ms.

Tres cosas más, que la sonda rota escondía:

- **Las aperturas no cuestan nada medible.** Con 4 salas fijas: 0 aperturas
  8,4 ms · 3 aperturas 9,1 ms · 6 aperturas 8,9 ms, todas **dentro del ruido**.
  Lo que cuesta es el mobiliario: de 0 a 6 objetos por sala, de 7,9 a 20,1 ms.
- **El coste por salas sí es real**, y ahí las bandas no se solapan: 1 sala
  3,1 ms · 2 salas 4,4 · 4 salas 7,5 · 8 salas 15,4 · 16 salas 26,1.
- **Y una que contradice lo que este mismo documento daba por bueno**: apagar
  los muebles para seguir al ratón **no ahorra nada medible**. Rehacer sin
  muebles da 19,1 ms (p10-p90 17,6-20,5) y rehacer entero 22,5 (20,0-25,4): las
  bandas se solapan. El camino que sí ahorra es el otro, **recolocar sin
  rehacer: 5,6 ms** (5,2-5,9), cuatro veces menos y sin solape. Queda anotado,
  no arreglado: es del visor, y a quién sigue el ratón se decide aparte.

**D-6 queda cerrado.**

---

## 19. D-1 — cuatro cortes, y una corrección a esta auditoría (2026-09-10)

D-1 decía: *sacar «3D en vivo» y «objetos» a sus módulos*. Lo primero ya estaba
hecho —`EditorPreview3D.gd` salió en la tanda del día 10— y lo segundo resultó
no ser lo que convenía cortar. Antes de tocar nada se midió, y la medida
contradice lo que esta auditoría dio por bueno.

### 19.1 Lo que dijo la medida

Para cada bloque de funciones se contó cuántos **miembros del editor ajenos al
bloque** usa —que es exactamente lo que habría que pasarle o pedirle si viviera
en otro fichero— y cuántas funciones de fuera lo llaman:

| bloque | func | líneas | mira hacia fuera a | lo llaman |
|---|---:|---:|---:|---:|
| **vista 3D** | 35 | 589 | **80** | 14 |
| objetos | 38 | 633 | 51 | 29 |
| aperturas | 30 | 834 | 48 | 29 |
| plantas | 35 | 697 | 45 | 57 |
| detectores/víctimas | 27 | 404 | 31 | 14 |
| escaleras | 23 | 365 | 24 | 11 |
| **pasillos** | 16 | 461 | **24** | 8 |
| catálogo/arrastre | 7 | 117 | 16 | 3 |
| cámara/rejilla | 5 | 81 | 6 | 3 |

**La «vista 3D» es el bloque peor acoplado del fichero**, no un módulo esperando
a salir: mira hacia fuera a 80 miembros del editor. Sacarla produciría un fichero
que llama al editor en cada línea, que es más difícil de leer que dejarla donde
está. Y **los pasillos son el bloque grande más limpio**: 461 líneas y solo 24
miembros hacia fuera.

Esto no invalida D-1 —el fichero sigue siendo demasiado ancho— pero sí cambia por
dónde se corta. La lección se parece a la de D-4: **una intuición sobre el
código, sin medir, apunta al bloque equivocado.**

Y hay un corte que la tabla dice que **no** merece la pena: el arrastre del
catálogo, 117 líneas y 7 funciones, es demasiado poco para un fichero propio.

### 19.2 Corte 1 — los tiradores de una caja girada

`editor/EditorHandles.gd`, 65 líneas. No había función larga que partir: había
**el mismo concepto escrito dos veces**, en tres niveles a la vez.

| | sala | objeto |
|---|---|---|
| dónde están | `_room_handle_points_m` | `_object_handle_points_m` |
| cuál pinchó el ratón | `_find_selected_room_handle_at` | `_find_selected_object_handle_at` |
| cómo se dibujan | `_room_handles_view` | `_object_handles_view` |

Las seis hacían lo mismo y solo cambiaban de dónde salían el centro, el tamaño y
el ángulo. **Una sala es una caja girada y un objeto también**: ésa es la
pregunta que las copias evitaban.

El módulo devuelve los puntos en un orden fijo —ancho, fondo, giro— y el editor
traduce ese orden a su `enum ObjectMouseMode` **en un solo sitio**,
`HANDLE_MODES`. Traerse el enum al módulo habría sido la copia que se acababa de
quitar.

Verificado comparando con la fórmula vieja escrita a mano sobre **162 cajas**
—tres centros × tres anchos × tres fondos × seis ángulos— con 1 µm de tolerancia,
más los casos degenerados: caja de ancho cero, lista vacía y un clic lejos de
todo. Idénticos.

Y de paso quedó arreglada una asimetría: la guarda de «caja sin medidas» estaba
solo en el lado de las salas, así que un objeto de tamaño cero ofrecía tres
tiradores encima del mismo punto.

### 19.3 Corte 2 — la geometría del pasillo

`editor/CorridorLayout.gd`, 253 líneas; el bloque de pasillos del editor pasa de
**461 a 243** líneas. Estático y puro, como `PlanGeometry` y `StairPlanRules`:
no conoce `editor_data`, ni la planta actual, ni la selección.

La frontera está en un sitio concreto y con nombre: las tres reglas que miran «lo
que ya hay» —el codo, el hueco y el recorte— reciben **los rectángulos ya
filtrados por planta**, que el editor reúne en `_corridor_obstacles()`. Eso es lo
que las vuelve comprobables de una en una, que es justo lo que un pasillo en L
necesitaba: sus reglas se pisan entre sí y a ojo no se distinguen.

De paso, `layout()` escribía cinco veces las mismas cuatro cuentas para «un tramo
recto por el eje que mande»; ahora es `_straight()`, una vez. `_build_corridor_layout`
era la tercera función más larga del fichero (102 líneas) y ya no está en él.

**Una bandera que nadie lee es adorno que no se puede comprobar**: al mover el
código añadí un `l_did_not_fit` para avisar de que la L pedida no cabía, y resultó
que el editor ya se enteraba comparando el modo que pidió con el que recibe
(`_corridor_forced_mode == "l" and mode != "l"`). La bandera se quitó.

### 19.4 Corte 3 — los marcadores de sala

`editor/RoomMarkers.gd`, 68 líneas; el bloque de detectores y víctimas pasa de
**404 a 287** líneas y de 27 funciones a 21.

Otro caso de dos copias, y de las descaradas: `_move_detector_to` y
`_move_victim_to` eran **idénticas letra por letra** salvo el nombre de la lista.
`_detector_index_for_id` / `_victim_index_for_id`, iguales salvo la clave.
`_find_detector_at` / `_find_victim_at`, iguales salvo la clave y el radio.

Un detector y una víctima son la misma forma de dato —`{id, room_id, x_m, y_m}`,
con la posición **local a su sala**— y por eso el código salía igual las dos
veces. Lo que cambia entre ellos es lo que se ve y lo que significan, no cómo se
buscan.

Lo que **no** se unificó, a propósito: la selección. `selected_detector_index` y
`selected_victim_index` son estados distintos porque se pueden seleccionar cosas
distintas, y meterlos en uno sería inventar una regla que el editor no tiene.

**Un cambio de comportamiento, pequeño y a la vista**: las salas de la planta se
reúnen ahora una vez, en `_room_origins_on_floor()`, y ese filtro descarta las
que no tienen rectángulo. La búsqueda ya lo hacía; **el dibujo no**, así que un
marcador de una sala sin rectángulo se pintaba en el origen del plano —una chincheta
fantasma en la esquina— y ahora no se pinta. Es lo que ya hacía la mitad que sí
comprobaba, y es la asimetría que las copias escondían.

### 19.5 Corte 4 — lo que quedaba de geometría del objeto

`world_to_object_local()` y `object_has_point()` se van a `PlanGeometry`, que es
donde ya vivía el resto de la geometría del objeto. El margen de acierto viaja
como argumento porque **depende del zoom**: pinchar una silla a 20 px/m y a 200
no es lo mismo, y eso es del editor, no de la geometría.

### 19.6 El precio, y lo que queda

| | antes | ahora |
|---|---:|---:|
| `editor/ScenarioEditor.gd` | 8739 líneas | **8471** |
| funciones en esa clase | 437 | 435 |
| funciones de más de 60 líneas | 16 | 15 |
| módulos de `editor/` | 12 | **15** |

**268 líneas fuera y cuatro conceptos duplicados menos.** El número de funciones
apenas se mueve, y conviene decirlo claro: **estos cortes son de duplicación, no
de anchura**. D-1 —437 funciones y 144 variables de estado en una clase— sigue
abierto, y para cerrarlo hacen falta más cortes de los que caben en una tanda.

La tabla del §19.1 dice por dónde seguir, y no es donde se pensaba:

1. **Escaleras** (23 funciones, 365 líneas, 24 hacia fuera): ya tienen casa,
   `StairPlanRules.gd`.
2. **Detectores y víctimas**, lo que queda (21 funciones, 287 líneas): crear,
   borrar y aplicar propiedades, que necesitan deshacer y línea de estado.
3. **Aperturas** (30 funciones, 834 líneas): el bloque más grande que queda, con
   48 miembros hacia fuera; hay que partirlo antes en geometría y en mando.
4. **La vista 3D no**, mientras siga en 78 miembros hacia fuera. Lo que ahí hace
   falta no es mudarla de fichero, es adelgazar lo que le pide al editor.

---

## 20. D-1, quinto corte: la capa de preguntas (2026-09-11)

Los cuatro cortes del §19 fueron de duplicación y apenas movieron la anchura: 437
funciones antes, 435 después. Para saber por dónde cortar de verdad hacía falta
otra medida, y ésta cambia el planteamiento.

### 20.1 El bloque grande no es un tema: es una capa

Se clasificaron las 431 funciones del fichero por **lo que hacen con el
escenario**, no por el tema del que hablan:

| | funciones | líneas |
|---|---:|---:|
| **preguntas puras** — leen `editor_data`, no escriben, no tocan escena ni selección | **58** | **1036** |
| mutan el escenario | 66 | 1798 |
| leen el escenario pero tocan UI o estado de interacción | 29 | 738 |

**Las 58 preguntas puras son el bloque grande que de verdad se puede sacar.** No
lo son «escaleras» ni «aperturas»: esos son temas, y sus funciones están
entretejidas con el estado del editor —de las 22 de escalera, todas menos dos
tocan `editor_data`, la selección o el panel—. Cortar por tema obliga a arrastrar
el estado; cortar por capa, no.

Esto corrige otra vez al §19.1: allí se midió el **acoplamiento por tema** y salió
que los pasillos eran el bloque más limpio. Era verdad y el corte valió, pero la
pregunta estaba mal hecha. La que sirve es: *¿esta función pregunta, o manda?*

### 20.2 El corte: las paredes

`editor/ScenarioWalls.gd`. Estático y puro: recibe el diccionario del escenario,
no lo guarda y no lo toca. Se lleva `shared_wall_between`, `shared_wall_segment`
y los tres accesores básicos —`room_rect`, `room_by_id`, `room_level_m`— que son
la cabeza de puente para los cortes siguientes.

**Y de paso colapsa la función más larga del fichero.** `_shared_wall_between`
eran **70 líneas con cuatro bloques casi idénticos**, uno por par de paredes
enfrentadas (derecha↔izquierda, izquierda↔derecha, abajo↔arriba, arriba↔abajo),
que solo se diferenciaban en el eje y en el signo. Cuatro copias de la misma
regla es como se acaba con una puerta que se puede poner entre dos salas por un
lado y no por el otro. Ahora son **cuatro entradas de una tabla** y una sola
regla que las recorre.

Verificado comparando con la fórmula vieja, copiada tal cual, sobre **2187 pares
de salas** —tres anchos × tres fondos × nueve desplazamientos en cada eje × tres
situaciones de clic—: 535 de ellos con conexión, 281 de esos con filtro de clic
activo, y **los 2187 idénticos**, hasta el micrómetro en el desplazamiento. Más
el caso que no puede fallar nunca: dos salas en plantas distintas no comparten
pared.

### 20.3 El precio

| | antes | ahora |
|---|---:|---:|
| `editor/ScenarioEditor.gd` | 8449 líneas | **8354** |
| funciones en esa clase | 431 | 429 |
| funciones de más de 60 líneas | 15 | **14** |
| preguntas puras que quedan dentro | 58 (1036 ln) | 56 (946 ln) |

Noventa y cinco líneas y la función más larga del fichero. Y, más importante que
el número: **la capa tiene sitio**. El siguiente corte no necesita inventar dónde
va, solo mudarse.

### 20.4 Corrección: las 1036 líneas eran mías y estaban infladas

El clasificador del §20.1 miraba **solo el cuerpo** de cada función. Una que no
escribe `editor_data` pero llama a `_add_opening` muta igual, y él la contaba
como pregunta pura. Con detección **transitiva** de mutación —quien llama a un
mutador, muta— la cifra real es:

| | funciones | líneas |
|---|---:|---:|
| lo que dije | 58 | 1036 |
| **lo que era** | **30** | **344** |

La diferencia son sobre todo `_open_passages_to_neighbours` y
`_open_passages_to_circulation` (92 líneas), que crean aperturas, y las que
convierten a píxeles.

Es el mismo error que cometí con el medidor de estilo, en el mismo día: **una
medida mal hecha infla la promesa**. Y esta vez la promesa ya estaba dada.

### 20.5 Lo que queda de D-1, por dónde

Las 56 preguntas puras que siguen dentro, las más gordas primero:
`_snap_rect_to_adjacent_rooms` (60), `_plan_ghost_view` (49),
`_open_passages_to_neighbours` (48), `_balcony_outline_px` (46),
`_open_passages_to_circulation` (44), `_corridor_seams_px` (34).

Un aviso para quien siga: las que acaban en `_view` o en `_px` **no son
preguntas puras del todo** —convierten a píxeles, y eso necesita el zoom y la
cámara—. La capa que se está sacando es la de metros; el paso a píxeles se queda
en el editor, que es quien sabe cómo se está mirando el plano.

---

## 21. D-1, la capa de preguntas entera, y por qué 7400 no sale por aquí

Petición del usuario: *«sigue con los cortes hasta las 7400 líneas»*. Se hicieron
tres cortes más, todos verificados, y el objetivo **no se alcanza por esta vía**.
Esto cuenta lo que salió y por qué se para aquí.

### 21.1 Los tres cortes

| corte | a dónde | líneas |
|---|---|---:|
| las preguntas básicas —quién es cada sala, cada objeto, cada id— | `editor/ScenarioQueries.gd` (nuevo) | −111 |
| la geometría de una pared: de dónde arranca, hacia dónde corre, cómo se saca un tramo | `editor/PlanGeometry.gd` | −63 |
| las preguntas sobre aperturas: dónde cae, cuánto puede medir, de qué planta es | `editor/ScenarioWalls.gd` | −91 |

`ScenarioQueries` es la base: `ScenarioWalls` se apoya en ella, y también le cedió
los accesores que se había quedado en el corte anterior. La capa ya tiene forma y
tiene dueño.

**8449 → 8091 líneas** contando el corte de las paredes del §20.

### 21.2 Y aquí es donde se acaba lo extraíble

Tras esos cortes quedan **16 preguntas puras, 215 líneas** — y de ésas, cuatro no
son movibles: `_apply_balcony_fields` **muta** la abertura que recibe (por
referencia, que en GDScript es mutar), `_room_handle_points_m` es de vista, y los
dos `_marker_*` son envoltorios de `RoomMarkers`.

Antes de seguir se midió el resto del fichero para buscar otra vía:

| bloque | func | líneas | ¿se puede sacar? |
|---|---:|---:|---|
| enlazar UI (`_bind_*`) | 17 | 377 | **No.** Asignan variables miembro del editor y conectan señales a sus propios métodos. |
| sincronizar UI (`_sync_*`, `_update_*`) | 32 | 543 | **No**, por lo mismo. |
| manejadores (`_on_*`) | 37 | 551 | **No**: son los extremos de las señales de la escena. |
| vistas del plano (`_view`, `_px`) | 18 | 433 | **A medias**: necesitan el zoom, la planta actual y la selección. Sacarlas obliga a una interfaz de cinco parámetros. |
| el resto | 306 | 5724 | la lógica del escenario, entretejida con su estado |

Yo mismo había estimado «preguntas + enlaces + vistas ≈ −1000». **Dos de los tres
bloques no eran extraíbles**, y lo supe al abrirlos, no al medirlos. La estimación
se hizo contando líneas por prefijo de nombre, que es exactamente la clase de
medida que esta auditoría lleva tres capítulos desaconsejando.

### 21.3 Lo que hace falta para bajar de verdad

Las **66 funciones que mutan el escenario** (1798 líneas) son el grueso, y no se
sacan de una en una: todas escriben en el mismo diccionario suelto. Bajar de las
~8000 líneas pide una decisión de diseño, no más cortes:

> **`editor_data` deja de ser un diccionario público y pasa a tener dueño**, con
> las mutaciones como métodos suyos.

Eso no es un refactor mecánico y **no se puede verificar por equivalencia**, que
es lo que ha hecho seguros los cortes de estos dos días. El riesgo es concreto y
ya mordió una vez esta semana: `adopt_scenario_data` bloqueaba la pose de los
muebles al deshacer, y eso no lo caza ninguna comparación de entrada y salida —
hizo falta darse cuenta de que *deshacer tiene que devolver el estado tal cual*.
Súmese que un `Dictionary` es una referencia y que «escribir de vuelta» a veces
no hace nada.

Por eso se para aquí y se deja la decisión tomada por quien corresponde.

### 21.4 Y la trampa de `--import`, que mordió

Al generar el `.uid` del módulo nuevo, `godot --headless --import` **borró
`lights_and_shadows/directional_shadow/size=4096` de `project.godot`** — el valor
que G-3 restauró a propósito el 9 de septiembre después de que se bajara
persiguiendo un fallo que resultó ser z-fighting.

La trampa está documentada desde entonces, y aun así casi se cuela, porque la
comprobación que hice no valía: comparé el fichero **justo después** de que el
comando devolviera, y Godot lo reescribe al salir. El `diff` dijo «idéntico» y
`git status` dijo lo contrario treinta segundos después.

La comprobación buena es la que ya decía el documento: **`git diff project.godot`
antes de commitear**, no un `diff` contra una copia. Restaurado con
`git checkout -- project.godot`.

### 21.5 Dónde queda el fichero

| | al empezar el día | ahora |
|---|---:|---:|
| `editor/ScenarioEditor.gd` | 8449 | **8091** |
| módulos de `editor/` | 15 | **17** |

Y la capa, con su frontera escrita: **si una función necesita escribir, no es de
este módulo**.

---

## 22. D-1: de quién es `editor_data` — DECIDIDO (2026-09-13)

El usuario delegó la decisión que el §21.3 dejó abierta. Se toma con lo medido
hoy sobre `editor/ScenarioEditor.gd`, que ha vuelto a crecer con el patio y el
portal: **8558 líneas y 414 funciones**.

| lo que escribe el escenario | sitios |
|---|---:|
| asignaciones a una clave de primer nivel (`editor_data["rooms_data"] = …`) | 66 |
| reasignaciones del diccionario entero (`editor_data = …`) | 7 |
| instantáneas de deshacer puestas a mano (`_push_undo_snapshot`) | 39 |
| guardarraíles o sondas que escriben directamente | **1** (`validate_editor_interaction.gd:140`) |
| módulos de `editor/` que lo leen | 7 |

### 22.1 La decisión

> **El dueño es un `ScenarioDocument` nuevo (`editor/ScenarioDocument.gd`,
> `RefCounted`). Tiene el diccionario del escenario y su historial. Es el único
> que escribe en él.**

Cinco reglas, que son la decisión:

1. **Las mutaciones son métodos del documento y no tocan la interfaz.** No ponen
   estado ni cambian la selección ni redibujan. Devuelven un resultado —ids
   creados, cuántas puertas se reconectaron, un motivo de rechazo— y es el editor
   quien lo convierte en mensaje y selección. Es la frontera que ya funcionó en
   la capa de preguntas, del lado de la escritura.
2. **El historial vive en el documento, y cada mutación es una transacción.** El
   método toma él mismo la instantánea antes de escribir. Las 39 llamadas a mano
   desaparecen, y con ellas la clase de fallo «esta acción no se puede deshacer
   porque alguien olvidó la instantánea».
3. **Deshacer restaura tal cual.** Es la lección del §21.3: la restauración no
   normaliza ni bloquea poses. Se hace con `restore(snapshot)`, que es un camino
   distinto de `adopt(data)`, el que carga un escenario de fuera.
4. **El documento avisa; el editor escucha.** Una señal `changed` sustituye a
   `_mark_editor_runtime_dirty()` y a los redibujos repartidos. El editor decide
   qué rehacer: el plano, el 3D en vivo o los mandos.
5. **Leer sigue siendo libre.** `editor_data` pasa a ser una propiedad de solo
   lectura que devuelve el diccionario del documento. Los siete módulos de
   `editor/` y las veintidós herramientas que lo leen no cambian. Escribir por
   esa vía queda prohibido y lo vigila un guardarraíl de texto, al estilo de
   `validate_probe_paths`: fuera de `ScenarioDocument` no puede aparecer
   `editor_data[...] =`, ni `editor_data = `, ni un `append`/`erase` sobre sus
   listas. La única escritura directa de un guardarraíl
   (`validate_editor_interaction.gd:140`) pasa a `adopt_scenario_data`, que ya es
   la entrada única desde D-6.

**Lo que NO se muda al documento:** la selección, la planta que se mira, el
arrastre en curso, la cámara, la puerta a medio poner. Es estado de la
interfaz, no del escenario. Mezclarlos es lo que hizo imposible verificar
deshacer por equivalencia.

### 22.2 Lo que se descartó, y por qué

- **Que el dueño sea `BuildingModel`.** No: es el formato de ejecución. Tipos
  distintos (`Rect2` frente a diccionarios), valores normalizados por
  `ScenarioSerializer.to_runtime_template`, y le faltan campos que solo
  existen para editar, como `stair_turn_mode` o los tiradores. La vista ya
  consume el template; el editor necesita el formato que no pierde nada.
- **Un módulo estático de mutadores sobre el diccionario suelto**, como
  `ScenarioWalls` pero escribiendo. Bajaría líneas, pero deja el diccionario
  público. Siguen vivos los dos riesgos del §21.3: que un `Dictionary` sea una
  referencia, y que «escribir de vuelta» a veces no haga nada. Y el historial
  seguiría siendo manual.
- **Seguir cortando preguntas.** El §21.2 ya midió que por ahí no queda nada.

### 22.3 Cómo se hace sin romper deshacer

No de golpe: **por familias de mutaciones, cada una con su sonda antes y
después**. La primera familia es la de **los conductos verticales**: escalera,
patio y portal. Tres razones:
- es la más reciente;
- es la que tiene la mejor cobertura (`validate_patio`, `validate_portal` y
  `validate_portal_view`, con diecinueve mutaciones muertas);
- sus funciones se llaman entre sí: `_add_vertical_opening`,
  `_create_room_at_level`, `_apply_stair_defaults_to_room`.

Cada familia se da por cerrada cuando se cumplen tres cosas:
- sus guardarraíles siguen verdes;
- **deshacer y rehacer devuelven el diccionario idéntico**, comparado byte a byte
  tras cada acción de la familia (sonda nueva);
- no quedan escrituras de esa familia fuera del documento.

Las 7400 líneas son una consecuencia, no el objetivo: el objetivo es que el
escenario tenga un único sitio que lo escribe.
