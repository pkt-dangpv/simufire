# El editor y la escala — tanda del 10 de septiembre de 2026

Dieciséis puntos que reportó el usuario de una sentada: quince del editor y uno
del mundo en primera persona. Este documento dice qué se hizo, **por qué era
así** y qué queda.

**Suite:** `python scripts/check_product.py` → **52 OK** + el FAIL conocido de la
línea del motor (`test_exit0_real_json`, R2-1).

---

## 0. El de fondo: la escala en primera persona

> «las medidas de las habitaciones y objetos no se ven correctas. un salón de
> 20 m² debería creo que verse más grande»

**No era impresión.** Las medidas en metros estaban bien —el guardarraíl de
paridad geométrica las compara con 1 mm de tolerancia—; lo que estaba mal era
la óptica y el paso.

**El campo de visión estaba clavado en el código y era el doble de ancho de lo
que parecía.** `_camera.fov = 75.0`, pero Godot mide el `fov` sobre el eje que
**no** fija `keep_aspect`, y por defecto fija el alto: ese 75 era el
**vertical**. A 16:9 son **107,5° horizontales**, un gran angular de 14 mm. Con
esa apertura cada pared cae más lejos y más pequeña de lo que le toca y la
vivienda se lee como una maqueta.

**Y se andaba a 2,25 m/s.** Una persona pasea a 1,3–1,4 y va con paso vivo a
1,7. Cruzar un salón de 5 m tardaba 2,2 s en vez de 3,7: la casa se recorre en
dos zancadas y se percibe pequeña.

| | antes | ahora |
|---|---|---|
| Campo de visión horizontal | 107,5° (implícito) | **75°** (`fp_camera_fov_h_deg`, decisión del usuario) |
| Marcha de pie | 2,25 m/s | **1,40 m/s** |

El `fov` es ahora un `@export` **horizontal**, con `keep_aspect = KEEP_WIDTH`:
antes, redimensionar la ventana cambiaba la sensación de tamaño.

Herramienta para volver a juzgarlo: `tools/capture_scale_fov.gd` fotografía el
mismo salón de 24 m² con varios campos de visión.

---

## 1. Navegación de la cuadrícula

- **Las barras de scroll salían siempre**: estaban a `SHOW_ALWAYS` en la escena
  en vez de en automático.
- **La rueda pasaba a hacer zoom al terminar el scroll.** Un `ScrollContainer`
  solo se queda el evento de rueda *mientras le queda scroll*; al llegar al
  final deja de consumirlo y caía en el editor. Ahora la rueda solo hace zoom
  si el puntero **no** está sobre la interfaz.
- **Se puede arrastrar la cuadrícula con el botón izquierdo**: pinchar en
  cuadrícula vacía deselecciona *y* engancha el plano. Existía el arrastre con
  el botón central, que en un portátil no existe.
- **Regla de escala** abajo a la izquierda: la distancia redonda que mejor cabe
  en ~140 px, el paso de la rejilla y el zoom en porcentaje.

## 2. Organización de los menús

- **El viento salía en las tres pestañas.** `_sync_left_editor_tab_visibility`
  asigna cada control a una pestaña con una lista de nombres, y las filas del
  viento **no estaban en ninguna lista**: nadie las ocultaba nunca. Igual le
  pasaba a las plantas totales, al «3D en vivo» y a la ayuda del editor.
- **`DIBUJO` → `ESCENARIO`** (decisión del usuario).
- **Panel izquierdo reordenado y con secciones**: PLANTAS · EDIFICIO · ENTORNO ·
  opciones de la herramienta activa · AYUDA Y VISTA. El orden de los nodos era
  sedimento histórico: las opciones de herramienta caían *después* de los
  botones de guardar.
- **Pestaña LISTA agrupada**: estancias, pasillos, escaleras, aperturas,
  detectores, víctimas e inicio FP, con la cuenta en la cabecera, los objetos
  sangrados bajo su sala y los grupos vacíos escondidos.

## 3. Comportamiento al editar

- **Colocada una cosa, se vuelve a Selección.** Se compara la cuenta de
  elementos antes y después del clic, en un solo sitio, y vale para 2D y 3D.
  **Solo vuelve si de verdad creó algo**: un clic que no valía deja la
  herramienta puesta.
- **La ficha de la sala al girar.** Se colgaba de `rect_px.position`, la esquina
  del rectángulo **sin girar**: al girar la sala el polígono se movía y la ficha
  se quedaba fuera. Una sala girada ancla ahora su ficha en el **centro**, que
  sí gira con ella.
- **El balcón se dibuja como una sala**: a lo largo del muro el ancho, hacia
  fuera el vuelo, recortado al máximo **durante el arrastre** —la
  previsualización se pone naranja y lo dice—. Un clic sin arrastrar sigue
  dando la balconera de medidas corrientes.

## 4. Idiomas y configuración

**Traducción nativa de Godot** (decisión del usuario). El castellano de la
escena hace de clave: `Control` traduce solo su `text` y su `tooltip_text`, así
que **las 289 etiquetas y los 103 tooltips del editor no se tocaron**. Añadir un
idioma es añadir `i18n/<código>_strings.json` y una línea en
`UILocalization.AVAILABLE_LOCALES`.

> **La trampa**: el castellano necesita **su propia tabla, aunque sea la
> identidad**. Sin ella `TranslationServer` no encuentra traducción para «es»,
> cae al idioma de reserva —el inglés— y el programa arrancaba en castellano y
> se veía en inglés.

Los textos que se **arman en código** sí hay que marcarlos: **168 llamadas a
`tr()`, con 165 literales distintos**, en `editor/ScenarioEditor.gd` (mensajes de
estado, pistas de herramienta, descripciones de pestaña). `i18n/en_strings.json`
trae **233 entradas**; lo que no esté traducido se queda en castellano, que es el
original.

**Configuración** en la esquina superior derecha del inicio: selector rápido de
idioma y **⚙ CONFIGURACIÓN**. Persiste en `user://simufire.cfg`, y se guarda al
cambiar, no al salir.

**Calidad gráfica en tres niveles**, un solo mando:

| | sombras | suavizado | escala de render | decorado de calle |
|---|---|---|---|---|
| **Bajo** | apagadas | ninguno | 0,75× | 2 filas, atrezo al 35 % |
| **Medio** | 2048 | MSAA 2× | 1× | 4 filas, al 70 % |
| **Alto** | 4096 | MSAA 2× | 1× | 5 filas, completo |

**No cambia la física**: el fuego, el humo y las medidas son los mismos en los
tres niveles, y el panel lo dice.

## 5. Vista previa 3D del catálogo

Un `SubViewport` encima de la lista con la pieza elegida, montada con **el mismo
cargador que usa la vista 3D**: lo que se ve ahí es lo que se va a dibujar. Sus
tres medidas debajo, y si es modelo propio o caja a escala. El panel se desplaza
solo hasta la vista previa al elegir la herramienta de objeto.

> **`alto` en el catálogo de objetos NO es la altura, es la elevación** sobre el
> suelo —0 en un sofá, 0,95 en el mueble de baño colgado—. El accesor se llama
> ahora `elevation_m()`; la altura de verdad la sabe `FurnitureDimensions`, que
> es quien dibuja. Lo cazó el guardarraíl al primer intento.

---

## Guardarraíles nuevos

| guardarraíl | qué fija | mutaciones |
|---|---|---|
| `validate_editor_interaction.gd` | vuelta a Selección, balcón dibujado, ficha de la sala girada | 3 |
| `validate_localization.gd` | los dos idiomas, el guardado, las tres calidades, y que los textos de código traduzcan | 4 |
| `validate_object_preview.gd` | las 38 piezas previsualizables y la ficha honesta | 3 |
| `validate_corridors.gd` | la U como un pasillo, la unión automática, el tipo de abertura y la forma forzada | 4 |

---

## Lo que queda

- ~~**127 de los 165 literales `tr()` de `editor/ScenarioEditor.gd` sin traducir
  al inglés**~~ — **traducidos el 2026-09-11**. `i18n/en_strings.json` pasa de
  233 a **360 entradas** y no queda ninguno sin cubrir. Se comprobó además que
  los marcadores de formato coinciden uno a uno entre las dos lenguas: un `%d`
  de más o de menos no falla al traducir, falla al ejecutar.
- **103 tooltips largos del editor** sin entrada en la tabla: mismo caso.
- **Las descripciones de los escenarios** y el resumen de la portada se arman en
  código y solo están parcialmente marcados.

---

## 6. El visor del 3D en vivo y los pasillos (segunda pasada)

### El visor no escuchaba el ratón, y «Encuadrar» no encuadraba

No estaba mal ajustado: **el `SubViewportContainer` no tenía ningún manejador**.
Solo la cabecera (mover el panel) y el agarre (redimensionarlo). Y «Encuadrar»
hacía esto:

```gdscript
_preview_3d_camera.global_transform = source.global_transform  # la del visor 3D grande
```

No encuadraba: **copiaba** la cámara del visor grande, que en modo 2D no se
mueve nunca. El botón copiaba siempre lo mismo.

Ahora la cámara del visor es suya, en coordenadas esféricas: arrastrar gira, la
rueda acerca, y «Encuadrar» **calcula** la vista desde la caja de las salas de
la planta. Reconstruir el 3D ya **no** reencuadra: si lo hiciera, cada cambio en
el plano devolvería la cámara al ángulo de fábrica.

### Los pasillos: el gesto decidía a escondidas

`_build_corridor_layout` elegía entre recto y giro con un umbral:

```gdscript
if abs_dx >= maxf(width_m * 1.25, abs_dy * 2.0) or abs_dy < width_m * 0.60:
    # → tramo recto
```

Un arrastre en diagonal moderada cae ahí y **sale recto sin avisar**. Por eso
«hago un pasillo inclinado y no puedo hacer una U».

- **Se puede forzar la forma**: `L` gira, `R` recto, mientras se arrastra. La
  previsualización dice cuál va a salir, y si se pide una L que no cabe —un
  brazo más corto que el ancho del pasillo no es un brazo— lo dice en vez de
  ignorar la tecla.

### Y por qué los tramos NO se funden en una sola sala

El usuario propuso que los pasillos se hicieran solos y se unieran al juntar
los extremos. **Unirse ya se unían** (`_open_passages_to_neighbours` abre paso
con todo lo que toca), pero se leían como tres cajas.

**Fundirlos en una sola sala habría sido un error de física.** El motor es un
modelo de zonas: cada sala es una zona bien mezclada. Un pasillo en L de doce
metros como **una** zona dice que el humo aparece a la vez en los dos extremos,
y el tiempo que tarda el humo en recorrer un pasillo es justamente lo que un
pasillo aporta a un incendio. Por eso los modelos de zona encadenan pasillos, y
por eso este repo tiene el caso **«CFAST: Corridor Chain»**.

Lo que se arregló es la presentación, no la física:

- **Un tramo pegado a un pasillo adopta su nombre.** Una U es «Pasillo 3» tres
  veces, no «Pasillo 3», «Pasillo 5» y «Pasillo 7».
- **La junta entre tramos del mismo pasillo no se dibuja** como tabique: se
  repinta con el relleno. Una U se lee como una U.

### El agujero que había detrás: no se podía cambiar el tipo de una abertura

El paso entre tramos nace como `hueco`, y **no había forma de convertirlo en
puerta**: la ficha de la abertura enseñaba el tipo y no dejaba tocarlo. Ahora
hay selector de tipo, con dos reglas: en un hueco **vertical** no aparece —es un
hueco de forjado y no admite hoja— y una **ventana** solo cabe donde hay
fachada. Al pasar a hueco se fuerza alféizar 0 y abierto; al pasar a ventana, un
alféizar de 0,90 si no tenía.

Es lo que da lo que se pedía: se dibujan tramos, se unen solos, y si se quiere
separar uno, ese hueco pasa a puerta.

**Guardarraíl** `tools/validate_corridors.gd` (cuatro mutaciones cazadas).
Suite **52 OK**.

---

## 7. D-3 y D-4

### D-3 — la ficha de la sala la tapaban los muebles

Era el orden de dibujo, sin más:

```gdscript
rooms(canvas, ...)      # la sala Y su ficha
openings(canvas, ...)
objects(canvas, ...)    # los muebles, encima de la ficha
```

El dato que más se consulta era el más tapado. La ficha sale ahora a una pasada
propia, `room_labels()`, **la última de todas**: encima de muebles, aperturas,
detectores y víctimas.

### D-4 — el 3D en vivo se salía del fotograma: **arreglado de rebote, y medido**

Lo arregló el encuadre calculado de la §6. Medido proyectando las ocho esquinas
de la caja del edificio sobre el visor:

| salas | caja | esquinas dentro (antes) | esquinas dentro (ahora) |
|---|---|---|---|
| 4 | 8,5 × 7,5 m | 8/8 | 8/8 |
| **16** | 17,5 × 15,5 m | **1/8** | **8/8** |
| 30 | 26,5 × 19,5 m | 0/8 | 8/8 |

El umbral medido —entre 4 y 16 salas— coincide con el «~16 salas» de la
auditoría del 6 de septiembre. La comprobación queda en
`tools/validate_editor_interaction.gd`, y se probó restaurando el
comportamiento viejo: 7 de las 8 esquinas fuera con 16 salas.

**Fase 6: quedan D-1 (el tamaño: `editor/ScenarioEditor.gd` en **8713** líneas,
medido el 2026-09-10) y D-6 (las sondas de captura, que no pasan por el camino
real). D-5 se cerró el mismo día: el estado del editor está al día en el §17 de
`AUDITORIA_EDITOR_2026-09-06.md`.**

