# Auditoría gráfica completa — SimuFire

**Fecha:** 2026-08-29 · **Alcance:** todo el aparato visual — humo y fuego (`view/3d/smoke`, `view/3d/fire`), visor 3D dollhouse (`view/3d`), primera persona (`view/fp`), visor 2D y minimapa (`view/2d`, `ui/Minimap2D.gd`), materiales e iluminación.
**Motivo:** revisión pedida sobre tres síntomas concretos — humo poco natural en ventanas y puertas, exterior de las viviendas feo, rellano y entradas igual.
**Continuación de:** [AUDITORIA_VISUAL_2026-07-15.md](AUDITORIA_VISUAL_2026-07-15.md) (§9 recoge qué queda vivo de aquella).

Severidades: 🔴 alta (rompe la lectura de la escena) · 🟠 media (se nota en escenarios habituales) · 🟡 baja (pulido) · ℹ️ nota.
Marcas: **[CORREGIDO]** en esta pasada · **[ABIERTO]** pendiente.

---

## 0. Resumen ejecutivo

Los tres síntomas reportados no eran cuestión de "más detalle", sino tres carencias geométricas concretas:

1. **El humo en los vanos era un cajón sin fondo.** El puente de humo entre salas no tenía cara inferior, así que desde la altura de los ojos (bajo la capa, que es donde se mira) se veían dos telones paralelos en vez de una capa con panza. Además el plano neutro recortaba **siempre** el humo a media puerta, incluso con las dos salas totalmente invadidas, y en las ventanas el humo salía como una losa rectangular cortada a ras del dintel, sin ascender.
2. **El edificio del jugador no tenía fachada.** Sólo existían los tabiques de cada sala. Al asomarse a una ventana se veía el canto del forjado y un vacío hasta una calle situada 5,8 m más abajo, sin nada en medio.
3. **El rellano dependía de la puerta de la vivienda para tener luz** (con la puerta cerrada era una caja negra) y se generaba un portal completo por cada puerta exterior, con portales interpenetrados si había dos.

Esta pasada corrige esos tres bloques (§1, §2, §3) y documenta el resto del sistema gráfico (§4-§8), que está en bastante mejor estado del que sugerían los síntomas.

**Cambiado en esta pasada**

| Archivo | Cambio |
|---|---|
| `view/3d/smoke/SmokeBridgeMesh.gd` | Cara inferior (intradós) del puente de humo |
| `view/3d/smoke/SmokeOpeningCurtain3D.gd` | Plano neutro por lado y continuo; cortina exterior desplazada a la calle; penacho ascendente en huecos a fachada |
| `view/3d/Visualizer3D.gd` | Nodo `SmokeExteriorPlume_XX` por hueco exterior + `show_exterior_smoke_plume` |
| `view/fp/FirstPersonController.gd` | Lienzo de fachada propio con huecos recortados, zócalo, líneas de forjado y coronación; cota de suelo exterior única; vierteaguas; luz propia del rellano; un rellano por fachada y planta; rodapié lateral y felpudo |
| `tools/validate_fp_exterior_context.gd`, `tools/validate_fp_landing_stairs.gd` | Guardarraíles headless para lo anterior |

---

## 1. Humo en huecos (ventanas y puertas)

### 🔴 H-1. El puente de humo no tenía cara inferior — **[CORREGIDO]**
`SmokeBridgeMesh.create()` construía sólo cuatro cuadriláteros verticales (dos caras a cada lado del muro y dos testeros). Faltaba la tapa inferior que une el borde bajo de una sala con el de la otra, es decir, **justo la superficie que se ve al mirar un hueco desde debajo de la capa de humo**, que es la postura normal del jugador.

Consecuencias:
- La capa se leía como dos telones paralelos, no como un cuerpo con intradós.
- El shader ya tenía el término `bottom_sheet` (`smoke_volume.gdshader`), ponderado por `bottom_surface_strength` (0,28-0,46 en la cortina), pero era **código muerto**: se calcula a partir de `-NORMAL.y` y no había ninguna cara con normal hacia abajo.

Corrección: se añade el cuadrilátero inferior con el orden de vértices adecuado en cada orientación para que la normal apunte hacia abajo. El intradós sale inclinado cuando las dos salas tienen la interfaz a distinta altura, que es exactamente la cuña real de un vano.

### 🔴 H-2. El humo nunca llenaba la puerta entera — **[CORREGIDO]**
`_should_limit_horizontal_smoke_to_upper()` devolvía `true` para cualquier hueco de más de 0,75 m, y a continuación **los dos lados** se recortaban al plano neutro:

```gdscript
bottom_pair.x = maxf(bottom_pair.x, neutral_plane_m)
bottom_pair.y = maxf(bottom_pair.y, neutral_plane_m)
```

El plano neutro era además una fracción fija del hueco (0,58 → 0,44 según el desequilibrio). Resultado: en una vivienda ya invadida hasta el suelo, **todas** las puertas mostraban una franja limpia en su mitad inferior. Es lo contrario de lo que ve un interviniente: cuando las dos estancias están cargadas, el hueco pasa humo a plena altura.

Corrección (`_flow_limited_bottoms` + `_effective_neutral_m`):
- El plano neutro recorta **sólo el lado que expulsa**; el que recibe conserva su propia interfaz de capa. El puente sale en cuña (humo alto en la sala limpia, humo bajo en la cargada) en vez de una banda plana.
- El plano neutro **se hunde de forma continua** conforme la interfaz del lado que recibe baja hacia el umbral: cuando las dos salas están enhumadas hasta el suelo el vano pasa humo entero, sin salto seco (un umbral binario daría un pop visible).
- En huecos a fachada se mantiene siempre el plano neutro: en una ventana hay contracorriente aunque la sala esté llena.

### 🔴 H-3. El humo salía por la ventana en losa y se cortaba en el dintel — **[CORREGIDO]**
Para un hueco exterior el puente se centraba en el vano: media losa dentro de la sala (superpuesta al volumen de humo de la propia sala, doble alfa en la jamba) y media fuera, con el borde superior cortado a ras del dintel y sin ninguna componente ascendente. El humo saliendo de una ventana quedaba como un bloque rectangular flotando delante del hueco.

Corrección:
- El puente se desplaza hacia la calle (`blend_depth * 0,32`) porque la mitad interior no aporta información: esa zona ya la pinta el volumen de humo de la sala.
- Nuevo **penacho exterior** (`_update_exterior_plume`, nodo `SmokeExteriorPlume_XX`): columna que arranca en el dintel, se separa un palmo de la fachada, se inclina 12° hacia fuera, se ensancha al subir y crece en altura (0,55 → 3,6 m) con la carga de humo y el contexto de fuego de la sala. Se apaga con la cortina y respeta las mismas máscaras de visibilidad. Interruptor: `show_exterior_smoke_plume` (Visualizer3D, activado por defecto).

En primera persona esto es lo que se ve desde dentro al mirar por la ventana; en dollhouse es la firma clásica de un fuego ventilado.

### 🟠 H-4. La contracorriente de aire frío está apagada por defecto — **[ABIERTO]**
`show_cold_air_inflow_curtains = false` ([Visualizer3D.gd:101](../view/3d/Visualizer3D.gd)). La cortina de entrada de aire existe y está bien resuelta (`_update_lower_inflow`), pero al estar apagada el vano sólo enseña la mitad superior: se ve el humo saliendo y nada entrando. Con H-2 corregido, encenderla completa la lectura bidireccional del hueco. No se activa aquí porque es una decisión de producto (colorear el aire de azul es una convención, no una observación).

### 🟠 H-5. La cortina ignora la hoja de la puerta — **[ABIERTO]**
`SmokeOpeningCurtain3D` escala el humo por `effective_open_fraction()`, pero geométricamente ocupa siempre el ancho completo del vano. Con la puerta a medio abrir el humo atraviesa la hoja. Lo correcto sería estrechar el puente al hueco libre real (ancho × fracción) y desplazarlo al lado de la bisagra.

### 🟡 H-6. Los huecos exteriores no alimentan el derrame entre salas — **[ABIERTO, correcto hoy]**
`_same_floor_opening_smoke_spill_for_room()` ([Visualizer3D.gd:2205](../view/3d/Visualizer3D.gd)) excluye `is_exterior_opening()`. Es lo correcto (de fuera no entra humo), pero también impide modelar la **autoexposición** (humo que sale por una ventana y entra por la de la planta superior), que es un fenómeno real y visualmente muy expresivo. Queda como mejora futura, no como fallo.

### 🟡 H-7. El penacho vertical de escaleras sólo existe con las dos salas presentes — **[ABIERTO]**
`_update_vertical()` sale si `item_a` o `item_b` están vacíos. En un hueco vertical hacia una planta no representada en el estado, la escalera no muestra humo aunque la sala inferior esté cargada.

### ℹ️ H-8. `smoke_local_y` asume `meters_to_units = 1`
El shader normaliza con `VERTEX.y / volume_depth_m`, pero los vértices ya vienen multiplicados por `meters_to_units` en `SmokeBridgeMesh._build_mesh()` mientras `volume_depth_m` va en metros. Hoy no afecta (la escena no cambia la escala), pero es una bomba de relojería si alguien toca ese parámetro.

---

## 2. Exterior de las viviendas

### 🔴 E-1. El edificio del jugador no tenía envolvente — **[CORREGIDO]**
Fuera de los tabiques de cada sala (`_create_walls`, [FirstPersonController.gd:951](../view/fp/FirstPersonController.gd)) **no existía ninguna fachada**. Al asomarse a una ventana se veía: el canto del forjado, aire, y una calle 5,8 m más abajo (`exterior_floor_drop_m`). Todo el decorado exterior (calle, aceras, edificio de enfrente, skyline) estaba cuidado, pero flotaba respecto a un edificio que no estaba dibujado. De ahí la sensación de "mejorado pero feo": el fallo no estaba en el decorado sino en el primer plano.

Corrección (`_create_own_facade`, [FirstPersonController.gd:2617](../view/fp/FirstPersonController.gd)):
- Un **lienzo de fachada por plano de muro** con huecos exteriores, recortando las aberturas reales con `StairGeometry.split_rect_by_voids()` en coordenadas (eje del muro, altura). El recorte es por construcción: es imposible que un panel tape una ventana.
- Va desde la cota de calle hasta la coronación, así que tapa el vacío bajo la vivienda y cierra de paso la rendija perimetral entre plantas (véase E-4).
- Relieve para dar escala: zócalo, **líneas de forjado** (las plantas modeladas más las plantas inferiores implícitas cuando la vivienda está elevada) y cornisa.
- Se salta el frente ocupado por el rellano del portal, que ya tiene su propio cerramiento.
- Sin colisión: es puramente visual y no altera el movimiento del jugador.
- Ajustable: `exterior_own_facade_enabled`, `own_facade_thickness_m`, `own_facade_hole_margin_m`, `own_facade_side_margin_m`, `own_facade_plinth_height_m`, `own_facade_parapet_m`, `own_facade_storey_pitch_m`.

### 🟠 E-2. Cada fachada calculaba su propia cota de calle — **[CORREGIDO]**
`_create_exterior_scenery_city()` usaba `floor_level_m - exterior_floor_drop_m`, donde `floor_level_m` era la planta mínima **de los huecos de esa fachada**. En un edificio con ventanas sólo en planta alta por un lado, la calle de esa fachada quedaba a distinta altura que la de la otra. Ahora hay una única cota (`_exterior_ground_level_m()`), derivada de la base real del edificio, y la usan la ciudad, el entorno residencial y la fachada.

### 🟠 E-3. El vierteaguas estaba en código muerto — **[CORREGIDO]**
`_create_exterior_window_sill()` existía sin ningún llamador (en todo el repositorio), y su geometría estaba desfasada: colocaba una losa a 0,62 m de la fachada y medio metro por debajo del centro del hueco. Se ha eliminado y se genera un vierteaguas correcto dentro de `_create_exterior_window_reveal()`, apoyado en el lienzo nuevo. Las jambas, que quedaban a 0,205 m del muro, se recolocan a ras de fachada.

### 🟠 E-4. Rendija perimetral entre plantas — **[MITIGADO]**
Con forjados de `preset_two_storey_house` (planta baja 2,65 m + techo 0,08; planta 1 a 2,90 con solera 0,10) queda un anillo perimetral de ~7 cm sin cerrar entre el techo de una planta y el suelo de la siguiente: desde dentro se ve una rendija de luz exterior, y desde fuera se ve el interior. El lienzo de fachada la tapa en los frentes con ventanas; **sigue abierta** en los frentes sin huecos y en los encuentros interiores. La corrección de fondo es que el techo llegue hasta la cara inferior del forjado superior.

### 🟠 E-5. Decorado urbano completo generado detrás del rellano — **[ABIERTO]**
`_create_exterior_context()` agrupa fachadas por normal e incluye la de la puerta de entrada. En `compact_apartment_reference` la puerta está en `bottom` y las ventanas en `top`: la fachada `bottom` genera calle, aceras, bordillos, coches, árboles, edificio de enfrente con ventanas y skyline **detrás de la caja cerrada del rellano**, donde nadie los verá jamás. Es geometría desperdiciada, no un fallo visual. Basta con no generar decorado en frentes cuyo único hueco exterior sea la puerta del portal.

### 🟡 E-6. Tabiques exteriores con material interior por las dos caras — **[ABIERTO]**
`_wall_material_for_room()` pinta el muro con el color de la estancia por ambas caras. El lienzo nuevo tapa esto donde existe; donde no, la cara exterior del edificio sigue siendo "salón".

### ℹ️ E-7. Lo que ya estaba bien
La composición urbana (dos aceras con bordillo, calzada con marcas, portales modulados con altura y profundidad variables, ventanas encendidas según hora, coches y arbolado en capas, skyline procedural o con textura propia) y el entorno residencial (césped, camino, acera, calzada, casas con cubierta a dos aguas, setos) están bien resueltos y bien parametrizados. El problema era el primer plano, no el fondo.

---

## 3. Rellano de los pisos y entradas

### 🔴 R-1. El rellano dependía de la puerta de la vivienda para tener luz — **[CORREGIDO]**
La única luz del rellano era la `OmniLight3D` creada en `_create_opening_light()` para el hueco de la puerta, con energía proporcional a la apertura (`landing_light_closed_ratio = 0.12`) y alcance 3,6 m sobre un rellano de 5,4 × 3,3 m más la caja de escalera. Con la puerta cerrada el portal era prácticamente negro; con ella abierta, una mancha de luz junto al umbral y el resto en penumbra. La escalera de un portal está iluminada por sí misma.

Corrección (`_add_landing_lights`, [FirstPersonController.gd:1788](../view/fp/FirstPersonController.gd)): plafón propio del rellano bajo la luminaria ya modelada, más una luz en la caja de escalera, ambas independientes del estado de la puerta y ajustables (`landing_ambient_lights_enabled`, `landing_ambient_light_factor`).

### 🟠 R-2. Un portal completo por cada puerta exterior — **[CORREGIDO]**
`_create_landing_recess()` se llamaba por cada puerta exterior sin ninguna deduplicación. Dos puertas exteriores en la misma planta (o una por planta en un edificio de varias) generaban **portales completos superpuestos**: dos suelos, dos techos, dos cajas de escalera interpenetradas y z-fighting en todas las superficies. Los presets actuales tienen una sola puerta exterior por vivienda, así que el fallo estaba latente. Ahora se genera un rellano por fachada y planta, y el guardarraíl headless lo verifica con una plantilla de dos puertas.

### 🟠 R-3. Encuentros y detalle del rellano — **[CORREGIDO parcialmente]**
El zócalo y el rodapié sólo existían en la pared del fondo; las laterales llegaban al suelo a hueso. Se añade rodapié lateral y felpudo delante de la puerta de la vivienda. Sigue **abierto** el acabado del suelo (una losa de color plano; un despiece de baldosa o un cambio de tono por franjas daría mucho más).

### 🟡 R-4. La altura del portal es un valor fijo — **[ABIERTO]**
`landing_floor_height_m = 2.62` no se deriva de la altura real de la vivienda ni de su forjado. Si la sala mide 2,4 m, el rellano queda 22 cm más alto que la vivienda a la que sirve y el encuentro se nota al cruzar la puerta.

### 🟡 R-5. Entrada unifamiliar: porche correcto, transición dura — **[ABIERTO]**
`_create_single_family_entry_recess()` genera porche, felpudo, escalón, pilares, voladizo y lámpara, y está bien. Lo que rompe la escena es que el porche apoya directamente sobre el césped del generador residencial sin ningún acuerdo (ni bordillo, ni cambio de material, ni sombra propia).

### ℹ️ R-6. La escalera del portal está bien resuelta
Dos tiros en U con carriles separados, huecos coherentes entre plantas, mesetas intermedias, forjado inferior y techo superior cerrados (no se ve ni cielo ni pozo sin fondo), barandillas con balaustres y pasamanos inclinado. Es de lo mejor del visor FP y el validador headless lo protege.

---

## 4. Visor 3D (dollhouse)

### 🟠 V3-1. Pila de transparencias sin `render_priority` — **[ABIERTO]**
Sigue sin usarse `render_priority` en ningún material de `view/3d`. Por sala conviven volumen de humo, máscara de techo, gradiente de capa, capa caliente, isoterma 150 °C y ahora la cortina y el penacho de cada hueco, todos `TRANSPARENCY_ALPHA` y con `depth_draw_never` en los shaders de humo. Es el patrón clásico de *popping* de ordenación alfa según el ángulo de cámara. Hoy se disimula porque las capas caliente/150 °C están apagadas por defecto.

### 🟠 V3-2. La captura de pantalla incluye el HUD — **[ABIERTO]**
`capture_screenshot_to()` ([Visualizer3D.gd:348](../view/3d/Visualizer3D.gd)) oculta la leyenda pero sigue capturando el viewport raíz completo, con el HUD 2D encima. Para un export técnico debería renderizar la vista 3D limpia a un `SubViewport`.

### 🟡 V3-3. `is_screen_point_over_model` sigue intersecando y=0 — **[ABIERTO]**
El picking de salas ya desambigua por planta (`ScreenPicking3D.room_id_at_screen_pos` recorre los niveles de mayor a menor: el 🔴 V3-1 de julio está resuelto), pero `is_screen_point_over_model()` sigue evaluando el plano y=0, así que en plantas altas el gesto de órbita/zoom "sobre el modelo" se decide con la proyección equivocada.

### 🟡 V3-4. Selección de objetos por distancia al origen — **[ABIERTO]**
`_fuel_object_at_screen_pos` mide la distancia 2D al origen del nodo (34/32 px): los muebles grandes son difíciles de clicar por los bordes.

### ℹ️ V3-5. Ya corregido desde julio
Trabajo duplicado en `_update_dynamic_state` (ahora `_apply_selection_visuals` no rehace `_update_openings`), churn de materiales de marcador (`_set_marker_color` cachea en meta), poses de apertura (`_get_cached_opening_pose`), reconstrucción de la leyenda (hash de flags) y el nodo muerto `SmokeLayerEdge` (eliminado).

---

## 5. Primera persona (interior)

### 🟠 FP-1. Tabiques duplicados y coincidentes entre salas — **[ABIERTO]**
`_create_walls()` recorre las cuatro caras de **cada** sala sin comprobar si la cara es medianera. Dos salas contiguas generan dos cajas de muro **exactamente coplanarias** (ambas centradas en el borde compartido). Como `_wall_material_for_room()` da color distinto por tipo de estancia, la medianera cocina/pasillo parpadea entre los dos colores al mover la cámara: z-fighting de manual. Además duplica malla y colisión en todas las particiones interiores.

### 🟠 FP-2. Todo el interior es color plano sin textura — **[ABIERTO]**
`use_procedural_surface_noise = false` por defecto ([FirstPersonController.gd:88](../view/fp/FirstPersonController.gd)), y cuando se activa lo que se aplica es un `NoiseTexture2D` en escala de grises como `albedo_texture`, que **multiplica** el color base: oscurece y motea en vez de texturar. Es la causa de fondo del "se ve feo" transversal a interior, rellano y fachada. Lo correcto es un ruido de bajo contraste centrado en gris medio (o una textura de material real) y aplicarlo con UV en metros, no por cara.

### 🟠 FP-3. Geometría FP todavía paralela a la del 3D — **[PARCIAL]**
`StairGeometry` ya está extraída y compartida (el 🟠 FP-1 de julio está a medias), pero suelos, techos, muros y huecos siguen teniendo dos implementaciones independientes (`FirstPersonController` vs `Visualizer3D`). Cualquier ajuste hecho en una diverge visualmente de la otra.

### 🟡 FP-4. Consultas repetidas por frame físico — **[ABIERTO]**
`_find_current_room_id()` y `get_room_rects_m()` se recalculan varias veces por frame en overlay, HUD y humo.

### ℹ️ FP-5. Lo que está bien
Overlay de visibilidad, atenuación de luces por humo coherente con los regímenes ILV, HUD técnico con capa según postura, suavizado de temperatura con τ, presets día/noche, hojas de ventana con rotura de vidrio y el domo de cielo procedural (necesario porque GL Compatibility no dibuja el sky del Environment por cámara).

---

## 6. Visor 2D y minimapa

- 🟡 **V2-1.** `_get_draw_transform()` ya se cachea por frame en `_frame_tf`, pero quedan dos llamadas sueltas ([Visualizer.gd:376](../view/2d/Visualizer.gd) y [:429](../view/2d/Visualizer.gd)) que rehacen el merge de bounds.
- 🟡 **V2-2.** El fondo sigue siendo un `Rect2(-50,-50,4000,2500)` fijo: en viewports muy anchos no cubre.
- 🟡 **V2-3.** Escala de color SVV poco legible (>99 % gris, 90-99 % naranja, 5-90 % el mismo rojo): una sala al 95 % alarma igual que una al 10 %.
- ℹ️ La isoterma de 150 °C ya no se dibuja en salas frías (🟠 V2-1 de julio corregido).

---

## 7. Materiales e iluminación (transversal)

- 🟠 **M-1.** Todo el proyecto construye materiales con `StandardMaterial3D` de color plano, `roughness = 0.96` y sin mapas. Sin variación de superficie, cualquier geometría —por correcta que sea— se lee como maqueta de cartón. Es la palanca con mejor relación coste/beneficio que queda: una textura de ruido bien calibrada (FP-2) más una segunda capa de suciedad en suelos y rodapiés.
- 🟠 **M-2.** No hay oclusión ambiental de ningún tipo (ni SSAO —no disponible en GL Compatibility— ni AO horneado ni un simple oscurecimiento de encuentros). Todos los encuentros suelo-pared son aristas duras a pleno color; es el segundo motivo por el que las escenas parecen planas.
- 🟡 **M-3.** `_mat()` crea un `StandardMaterial3D` nuevo en cada llamada: la fachada, el rellano y el decorado generan decenas de materiales idénticos que podrían compartirse por color.
- ℹ️ **M-4.** La iluminación sí está bien pensada: sol direccional con sombras, relleno suave, luz por hueco atenuada por humo, luces de techo contenidas a su sala y luz de fuego con ley de potencia sobre el HRR.

---

## 8. Rendimiento

- ℹ️ Cadencias: 2D/HUD a 20 Hz, 3D a ~8 Hz, FP a 20 Hz con el humo compartido a 8 Hz. Correcto.
- 🟡 El decorado exterior, la fachada nueva y el rellano son geometría estática construida una vez por `rebuild`, sin coste por frame más allá del draw call. El lienzo de fachada añade del orden de 10-20 cajas por edificio.
- 🟠 Cada segmento de muro FP crea un `StaticBody3D` propio: en una vivienda de 8 salas son ~40 cuerpos con colisión duplicada en medianeras (FP-1).

---

## 9. Estado de la auditoría 2026-07-15

| Hallazgo de julio | Estado hoy |
|---|---|
| G-1 gráficas bloquean el hilo principal | Corregido (existe `tests/test_async_graph_generation.py`) |
| V3-1 picking contra y=0 en multi-planta | Corregido para salas; queda `is_screen_point_over_model` (§4 V3-3) |
| V2-1 isoterma 150 °C siempre dibujada | Corregido |
| V3-2 trabajo duplicado y churn de materiales | Corregido |
| V3-3 poses de apertura recalculadas | Corregido (caché) |
| V3-4 nodo `smoke_edge` muerto | Corregido (eliminado) |
| V3-5 leyenda reconstruida por `set_state` | Corregido (hash de flags) |
| V3-6 transparencias sin `render_priority` | **Abierto** (§4 V3-1) |
| V3-7 captura incluye el HUD | **Abierto** (§4 V3-2) |
| FP-1 geometría FP duplicada | Parcial (§5 FP-3) |
| V2-2 transform recalculado por llamada | Casi corregido (§6 V2-1) |

---

## 10. Prioridad de la siguiente pasada

| # | Hallazgo | Sev. | Área |
|---|---|---|---|
| 1 | FP-2/M-1 superficies sin textura utilizable | 🟠 | Materiales |
| 2 | FP-1 tabiques coincidentes con z-fighting | 🟠 | FP |
| 3 | M-2 sin oclusión ambiental ni acuerdo en encuentros | 🟠 | Materiales |
| 4 | H-5 la cortina de humo ignora la hoja de la puerta | 🟠 | Humo |
| 5 | E-4 rendija perimetral entre plantas (cerrarla en el techo) | 🟠 | FP |
| 6 | H-4 decidir si la contracorriente de aire se enseña por defecto | 🟠 | Humo |
| 7 | E-5 no generar decorado urbano detrás del rellano | 🟡 | FP |
| 8 | R-3/R-4 acabado del suelo del rellano y altura derivada | 🟡 | Rellano |
| 9 | V3-1 `render_priority` en la pila alfa | 🟡 | 3D |
| 10 | V3-2 captura 3D limpia a `SubViewport` | 🟡 | 3D |

---

## 11. Verificación

Los cambios de esta pasada **no se han podido ejecutar**: este entorno no tiene Godot y la 4.7.1 que usa el proyecto no está disponible para descarga (se descartó comprobar con una versión distinta porque los resultados no serían representativos). Lo que sí se ha hecho:

- Revisión estática del GDScript modificado (indentación, delimitadores, continuaciones de línea) y de la orientación de las normales del nuevo intradós en las dos orientaciones de muro.
- Los guardarraíles headless se han **ampliado** para cubrir lo nuevo, de modo que la ejecución en tu máquina los verifique:
  - `tools/validate_fp_exterior_context.gd`: existencia del lienzo, del zócalo y de la coronación; que ningún panel tapa el hueco de la ventana; que el frente del rellano queda libre.
  - `tools/validate_fp_landing_stairs.gd`: luces propias del rellano encendidas y **un solo** portal con dos puertas exteriores en la misma fachada.

Comando de verificación:

```powershell
python scripts/check_product.py
```

Revisión visual recomendada, con [CHECKLIST_VISUAL_REGRESION.md](CHECKLIST_VISUAL_REGRESION.md) delante: `preset_compact_apartment` (rellano y fachada de piso), `preset_two_storey_house` (fachada de dos plantas y rendija perimetral) y cualquier escenario con fuego declarado, mirando una ventana desde fuera en dollhouse y desde dentro en primera persona.
