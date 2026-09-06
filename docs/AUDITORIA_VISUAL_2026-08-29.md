# Auditoría gráfica completa — SimuFire

**Fecha:** 2026-08-29 · **Alcance:** todo el aparato visual — humo y fuego (`view/3d/smoke`, `view/3d/fire`), visor 3D dollhouse (`view/3d`), primera persona (`view/fp`), visor 2D y minimapa (`view/2d`, `ui/Minimap2D.gd`), materiales e iluminación.
**Motivo:** revisión pedida sobre tres síntomas concretos — humo poco natural en ventanas y puertas, exterior de las viviendas feo, rellano y entradas igual.
**Continuación de:** [AUDITORIA_VISUAL_2026-07-15.md](AUDITORIA_VISUAL_2026-07-15.md) (§9 recoge qué queda vivo de aquella).
**Addendum 2026-08-31:** informe verificado en ejecución sobre Godot 4.7.1 con render real de la vista FP; se añaden FP-6 y FP-7 (§5), se reescribe §11 y se añaden el plan de cierre de toda la línea visual (§12) y su estado final tras ejecutarlo (§13).

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

### 🟠 H-4. La contracorriente de aire frío está apagada por defecto — **[CERRADO 2026-08-31: bug corregido, función apagada por decisión]**
`show_cold_air_inflow_curtains = false` ([Visualizer3D.gd:101](../view/3d/Visualizer3D.gd)). La cortina de entrada de aire existe y está bien resuelta (`_update_lower_inflow`), pero al estar apagada el vano sólo enseña la mitad superior: se ve el humo saliendo y nada entrando. Con H-2 corregido, encenderla completa la lectura bidireccional del hueco. No se activa aquí porque es una decisión de producto (colorear el aire de azul es una convención, no una observación).

**Medido el 2026-08-31.** Encender `show_cold_air_inflow_curtains` sobre el piso patrón cambiaba el 0,489 % de los píxeles: nada. Instrumentando `_update_lower_inflow` con **contadores** —no con muestreo, que en un primer intento me llevó a una conclusión equivocada— salió el dato limpio: **9 llamadas en toda la corrida, 0 con la condición cumplida, 0 cortinas de aire visibles**. La banda tenía altura de sobra (0,80-1,25 m) y el alfa llegaba a su tope; lo que fallaba era el enganche.

**Bug encontrado y corregido.** `has_fire_context` exigía `outflow_visible`, es decir, que la cortina de *salida* del mismo hueco hubiese superado su propio umbral de visibilidad en ese mismo fotograma. Con esa condición la contracorriente no llegaba a dibujarse nunca. La condición física es que haya humo empujando y desequilibrio entre las dos salas, que es justo lo que ya comprobaba el resto de la expresión. El acoplamiento con la malla de salida queda como opción (`opening_inflow_requires_outflow`, desactivada).

**Decisión: se queda apagada por defecto.** Ya con el enganche arreglado y la opacidad subida a 0,26, la cortina aporta el **0,36 %** de los píxeles en la casa de muñecas —donde el marcador verde de puerta abierta ocupa ese mismo volumen y la tapa— y entre el **0,02 % y el 0,09 %** en primera persona, donde el vano está en penumbra. Mirada de cerca, recortada y ampliada, no se lee en ninguna de las dos vistas. A eso se suma la objeción original, que sigue en pie: pintar el aire de azul es una convención, no una observación, y esto es una herramienta que entrena la observación.

Queda todo listo para revertir la decisión sin tocar código: basta encender `show_cold_air_inflow_curtains`. El tope de opacidad por defecto sube de 0,085 a **0,26** justamente para que ese interruptor baste por sí solo, sin tener que descubrir además que hacía falta subir otro valor.

### 🟠 H-5. La cortina ignora la hoja de la puerta — **[CORREGIDO 2026-08-31]**
`SmokeOpeningCurtain3D` escala el humo por `effective_open_fraction()`, pero geométricamente ocupa siempre el ancho completo del vano. Con la puerta a medio abrir el humo atraviesa la hoja. Lo correcto sería estrechar el puente al hueco libre real (ancho × fracción) y desplazarlo al lado de la bisagra.

**Corrección aplicada (F3.1), con una enmienda al diagnóstico.** El informe decía "desplazarlo al lado de la bisagra" y es al revés: la hoja gira **sobre** su bisagra, así que su proyección sobre el plano del hueco arranca justo ahí y tapa ese lado. El hueco libre queda del lado de la **cerradura**. `_leaf_free_gap()` devuelve ancho útil y desplazamiento leyendo `op.hinge_side`, y la cortina se estrecha y se corre hacia el lado por el que de verdad pasa el humo.

Un efecto secundario que había que resolver: la opacidad ya se multiplicaba por la fracción de apertura. Con la geometría llevando también esa fracción, media puerta se vería como media cortina a media densidad, contando la apertura dos veces. La atenuación de opacidad pasa a ser `open_frac ^ exponente`, con el exponente en el inspector (`opening_curtain_alpha_open_exponent`, 0,5 por defecto: 0 no atenúa nada, 1 recupera el comportamiento anterior). También son ajustables `opening_curtain_follows_leaf` y `opening_curtain_min_width_ratio`.

Guardarraíl: `tools/validate_3d_smoke_opening_curtain.gd`. Con `opening_curtain_follows_leaf` desactivado falla con los números del caso (ancho 1,60 contra 1,60 y desplazamiento 0,000).

### 🟡 H-6. Los huecos exteriores no alimentan el derrame entre salas — **[ABIERTO, correcto hoy]**
`_same_floor_opening_smoke_spill_for_room()` ([Visualizer3D.gd:2205](../view/3d/Visualizer3D.gd)) excluye `is_exterior_opening()`. Es lo correcto (de fuera no entra humo), pero también impide modelar la **autoexposición** (humo que sale por una ventana y entra por la de la planta superior), que es un fenómeno real y visualmente muy expresivo. Queda como mejora futura, no como fallo.

### 🟡 H-7. El penacho vertical de escaleras sólo existe con las dos salas presentes — **[NO REPRODUCIBLE, salvaguarda puesta 2026-08-31]**
`_update_vertical()` sale si `item_a` o `item_b` están vacíos. El informe deducía de ahí que un hueco vertical hacia una planta no representada en el estado dejaría la escalera sin humo.

**Al intentar reproducirlo, no ocurre.** `Visualizer3D` crea un item por **cada** sala del edificio en `rebuild_from_building()`, esté o no en el estado de la simulación: el estado sólo rellena esos items. Así que `item.is_empty()` no se da por una planta no simulada. El retorno temprano sólo saltaría con una apertura que apunte a una sala inexistente en el edificio, y ahí no llega a crearse el nodo de cortina, con lo que tampoco hay nada que dibujar. Probado también con el hueco vertical al exterior (`b = -1`, tipo claraboya): el nodo no existe.

Se deja una **salvaguarda** —si un extremo faltara, se toma como planta limpia en vez de ocultar el penacho— pero no se apunta como corrección de un fallo observable, y no se le pone guardarraíl porque no hay caso que fijar. Si alguna vez se permite una apertura hacia una planta fuera del modelo, este hallazgo vuelve a estar vivo.

### ℹ️ H-8. `smoke_local_y` asume `meters_to_units = 1` — **[CORREGIDO 2026-08-31]**
El shader normalizaba con `VERTEX.y / volume_depth_m`, pero los vértices ya vienen multiplicados por `meters_to_units` en `SmokeBridgeMesh._build_mesh()` mientras `volume_depth_m` va en metros. No afectaba con escala 1, pero era una bomba de relojería.

Corrección (F3.3): `smoke_volume.gdshader` recibe un uniforme `meters_to_units` y normaliza por `volume_depth_m * meters_to_units`. Se pasa desde los seis sitios que fijan `volume_depth_m` (cuatro en la cortina de vano, dos en el visor) y desde la factoría de materiales.

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

### 🟠 E-4. Rendija perimetral entre plantas — **[CORREGIDO 2026-08-31]**
Con forjados de `preset_two_storey_house` (planta baja 2,65 m + techo 0,08; planta 1 a 2,90 con solera 0,10) queda un anillo perimetral de ~7 cm sin cerrar entre el techo de una planta y el suelo de la siguiente: desde dentro se ve una rendija de luz exterior, y desde fuera se ve el interior. El lienzo de fachada la tapa en los frentes con ventanas; **sigue abierta** en los frentes sin huecos y en los encuentros interiores. La corrección de fondo es que el techo llegue hasta la cara inferior del forjado superior.

Corrección aplicada (F1.4): eso es justo lo que se hace ahora. `_ceiling_thickness_to_next_floor_m()` busca la planta más baja por encima del techo y estira la losa hasta la cara inferior de su forjado; si no hay planta encima se queda en el grosor nominal. Interruptor `@export interstitial_ceiling_seal_enabled` (activado). Ya no depende de que el frente tenga huecos, así que cierra también los frentes ciegos y los encuentros interiores.

Guardarraíl: `tools/validate_fp_interstitial_seal.gd`. Con el sellado desactivado reproduce exactamente el anillo del hallazgo: `0.070 m`.

### 🟠 E-5. Decorado urbano completo generado detrás del rellano — **[CORREGIDO 2026-08-31]**
`_create_exterior_context()` agrupa fachadas por normal e incluye la de la puerta de entrada. En `compact_apartment_reference` la puerta está en `bottom` y las ventanas en `top`: la fachada `bottom` genera calle, aceras, bordillos, coches, árboles, edificio de enfrente con ventanas y skyline **detrás de la caja cerrada del rellano**, donde nadie los verá jamás. Es geometría desperdiciada, no un fallo visual. Basta con no generar decorado en frentes cuyo único hueco exterior sea la puerta del portal.

Corrección aplicada (F5.3): eso es lo que se hace. Cada fachada anota si tiene algún hueco que dé de verdad a la calle —ventanas y huecos siempre; la puerta sólo en unifamiliar, donde sí da al porche— y las que no lo tienen se saltan el generador de paisaje. Interruptor `exterior_scenery_skip_landing_facades`.

### 🟡 E-6. Tabiques exteriores con material interior por las dos caras — **[CORREGIDO 2026-08-31]**
`_wall_material_for_room()` pinta el muro con el color de la estancia por ambas caras. El lienzo nuevo tapa esto donde existe; donde no, la cara exterior del edificio sigue siendo "salón".

Corrección aplicada (F2.4): un muro es una sola caja y no admite material por cara, así que se añade una chapa fina (`ExteriorWallSkin_*`, 2 cm, `exterior_wall_skin_thickness_m`) con material de fachada sobre la cara exterior de los tabiques que no tienen sala vecina. `_wall_face_is_exterior()` lo decide por tramos comparando el plano del tabique y el solape con las demás salas de la misma planta, así que un muro medio medianero y medio a fachada se resuelve bien. Donde ya hay lienzo de fachada la chapa queda dentro de él y no se ve: es el respaldo de los frentes que no generan lienzo.

### ℹ️ E-7. Lo que ya estaba bien
La composición urbana (dos aceras con bordillo, calzada con marcas, portales modulados con altura y profundidad variables, ventanas encendidas según hora, coches y arbolado en capas, skyline procedural o con textura propia) y el entorno residencial (césped, camino, acera, calzada, casas con cubierta a dos aguas, setos) están bien resueltos y bien parametrizados. El problema era el primer plano, no el fondo.

---

## 3. Rellano de los pisos y entradas

### 🔴 R-1. El rellano dependía de la puerta de la vivienda para tener luz — **[CORREGIDO]**
La única luz del rellano era la `OmniLight3D` creada en `_create_opening_light()` para el hueco de la puerta, con energía proporcional a la apertura (`landing_light_closed_ratio = 0.12`) y alcance 3,6 m sobre un rellano de 5,4 × 3,3 m más la caja de escalera. Con la puerta cerrada el portal era prácticamente negro; con ella abierta, una mancha de luz junto al umbral y el resto en penumbra. La escalera de un portal está iluminada por sí misma.

Corrección (`_add_landing_lights`, [FirstPersonController.gd:1788](../view/fp/FirstPersonController.gd)): plafón propio del rellano bajo la luminaria ya modelada, más una luz en la caja de escalera, ambas independientes del estado de la puerta y ajustables (`landing_ambient_lights_enabled`, `landing_ambient_light_factor`).

### 🟠 R-2. Un portal completo por cada puerta exterior — **[CORREGIDO]**
`_create_landing_recess()` se llamaba por cada puerta exterior sin ninguna deduplicación. Dos puertas exteriores en la misma planta (o una por planta en un edificio de varias) generaban **portales completos superpuestos**: dos suelos, dos techos, dos cajas de escalera interpenetradas y z-fighting en todas las superficies. Los presets actuales tienen una sola puerta exterior por vivienda, así que el fallo estaba latente. Ahora se genera un rellano por fachada y planta, y el guardarraíl headless lo verifica con una plantilla de dos puertas.

### 🟠 R-3. Encuentros y detalle del rellano — **[CORREGIDO 2026-08-31]**
El zócalo y el rodapié sólo existían en la pared del fondo; las laterales llegaban al suelo a hueso. Se añade rodapié lateral y felpudo delante de la puerta de la vivienda. Sigue **abierto** el acabado del suelo (una losa de color plano; un despiece de baldosa o un cambio de tono por franjas daría mucho más).

**[CERRADO 2026-08-31]** (F2.5) El suelo del rellano lleva despiece de baldosa: perfil de textura `NOISE_PROFILE_TILE` con la junta dibujada en el borde y proyección triplanar en metros, de modo que el lado de la baldosa es un parámetro real (`landing_tile_size_m`, 0,55 m) y no cuesta ni una malla más. Oscurecimiento de la junta en `landing_tile_grout_darkening`.

### 🔴 R-7. El frente del rellano estaba abierto al exterior — **[CORREGIDO 2026-08-29, 2ª pasada]**
Detectado al ver el portal en ejecución: sombras duras que barrían el rellano al moverse. La causa no era el sesgo de sombra sino un agujero real.

El rellano mide 5,40 m de ancho, pero su frente sólo lo cerraba **el muro de la propia vivienda**, que en los pisos de referencia mide 1,40 m. **Los 4 m restantes no tenían ningún cerramiento**: el portal estaba abierto de par en par a la intemperie y el sol entraba a plena luz en un espacio que debe ser interior. Además, el forjado, el techo y los laterales arrancaban a 0,08 m del plano del muro cuando la cara exterior del tabique está a 0,05 m, dejando **una rendija de 3 cm en todo el encuentro**.

Corrección: frente propio del rellano (`_create_landing_front_wall`) con el hueco de la puerta recortado, apoyado en la cara exterior del tabique sin quedar coplanar con él; y arranque del rellano derivado de `wall_thickness_m` en vez de la constante 0,08, con el muro de fondo recolocado para conservar su solape. Guardarraíl añadido en `validate_fp_landing_stairs.gd`.

### 🟡 R-8. Las paredes del rellano no tienen colisión — **[CORREGIDO 2026-08-31]**
`LandingBackWall`, `LandingSideWall` y el frente nuevo se añaden a `_world_root` sin `StaticBody3D`, así que el jugador puede atravesarlas y caer al vacío. Es previo y coherente con el resto del portal, pero conviene cerrarlo.

Corrección aplicada (F1.2), con un hallazgo de propina: `_add_box(..., with_collision = true)` colgaba el `CollisionShape3D` del `Node3D` padre, y **una forma fuera de un `CollisionObject3D` es inerte**. Es decir, el parámetro era un contrato falso: el descansillo intermedio de la escalera (`StairSwitchbackLanding`) creía tener colisión y no la tenía. Ahora `_add_box` reutiliza el padre si ya es un cuerpo y, si no, crea un `StaticBody3D` propio; las cuatro piezas del rellano pasan a `true`.

Guardarraíl: `_validate_landing_walls_are_solid()` en `tools/validate_fp_landing_stairs.gd`.

### 🟡 R-4. La altura del portal es un valor fijo — **[CORREGIDO 2026-08-31]**
`landing_floor_height_m = 2.62` no se deriva de la altura real de la vivienda ni de su forjado. Si la sala mide 2,4 m, el rellano queda 22 cm más alto que la vivienda a la que sirve y el encuentro se nota al cruzar la puerta.

Corrección aplicada (F5.4): la altura sale de la sala a la que sirve esa puerta, sumando su forjado (`_landing_height_for_opening`). Medido: vivienda de 2,40 → rellano 2,48; de 2,62 → 2,70; de 3,00 → 3,08, donde antes eran 2,62 en los tres casos. Se puede volver al valor fijo con `landing_height_follows_dwelling`. Hizo falta publicar `room_id` en `_opening_info()`, que no lo exponía.

### 🟡 R-5. Entrada unifamiliar: porche correcto, transición dura — **[CORREGIDO 2026-08-31]**
`_create_single_family_entry_recess()` genera porche, felpudo, escalón, pilares, voladizo y lámpara, y está bien. Lo que rompe la escena es que el porche apoya directamente sobre el césped del generador residencial sin ningún acuerdo (ni bordillo, ni cambio de material, ni sombra propia).

Corrección aplicada (F5.5): `_create_porch_ground_transition()` añade bordillo en los tres lados libres del porche y una franja de grava alrededor, con su propio perfil de textura. Todo ajustable: `house_porch_ground_transition_enabled`, altura y grosor del bordillo, ancho de la franja y su color.

### ℹ️ R-6. La escalera del portal está bien resuelta
Dos tiros en U con carriles separados, huecos coherentes entre plantas, mesetas intermedias, forjado inferior y techo superior cerrados (no se ve ni cielo ni pozo sin fondo), barandillas con balaustres y pasamanos inclinado. Es de lo mejor del visor FP y el validador headless lo protege.

---

## 4. Visor 3D (dollhouse)

### 🟠 V3-1. Pila de transparencias sin `render_priority` — **[CORREGIDO 2026-08-31]**
Sigue sin usarse `render_priority` en ningún material de `view/3d`. Por sala conviven volumen de humo, máscara de techo, gradiente de capa, capa caliente, isoterma 150 °C y ahora la cortina y el penacho de cada hueco, todos `TRANSPARENCY_ALPHA` y con `depth_draw_never` en los shaders de humo. Es el patrón clásico de *popping* de ordenación alfa según el ángulo de cámara. Hoy se disimula porque las capas caliente/150 °C están apagadas por defecto.

Corrección aplicada (F4.1): prioridad explícita en las nueve capas translúcidas —volumen de humo y penacho de sala, máscara de techo, gradiente de capa, capa caliente, isoterma 150 °C, y cortina, contracorriente y penacho exterior de cada hueco—, todas con su `@export` en el grupo **"Orden de transparencias"** para poder reordenarlas sin tocar código. Con prioridad explícita el orden deja de depender del ángulo de cámara.

### 🟠 V3-2. La captura de pantalla incluye el HUD — **[CORREGIDO 2026-08-31]**
`capture_screenshot_to()` ([Visualizer3D.gd:348](../view/3d/Visualizer3D.gd)) oculta la leyenda pero sigue capturando el viewport raíz completo, con el HUD 2D encima. Para un export técnico debería renderizar la vista 3D limpia a un `SubViewport`.

Corrección aplicada (F4.2): eso es lo que hace ahora. `_render_clean_screenshot()` monta un `SubViewport` que **comparte el mismo `World3D`** y una cámara clonada de la activa (fov, near/far, proyección, entorno y atributos), así que la imagen es exactamente la misma escena sin nada de interfaz: el HUD y la leyenda viven en capas de lienzo del viewport raíz y no entran ahí.

Verificado con ventana real y un HUD falso a pantalla completa: la captura sale a **1920 × 1080** (la resolución configurada, no la de la ventana) y contiene **cero** píxeles del HUD. Ajustable con `screenshot_use_clean_viewport`, `screenshot_size_px` (0,0 = tamaño del viewport) y `screenshot_transparent_background`. En `--headless` y con la opción desactivada se conserva el camino antiguo, que es lo que sigue cubriendo el guardarraíl existente.

### 🟡 V3-3. `is_screen_point_over_model` sigue intersecando y=0 — **[CORREGIDO 2026-08-31]**
El picking de salas ya desambigua por planta (`ScreenPicking3D.room_id_at_screen_pos` recorre los niveles de mayor a menor: el 🔴 V3-1 de julio está resuelto), pero `is_screen_point_over_model()` sigue evaluando el plano y=0, así que en plantas altas el gesto de órbita/zoom "sobre el modelo" se decide con la proyección equivocada.

Corrección aplicada (F4.3): acepta las cotas de planta y prueba contra cada una de la más alta a la más baja, igual que `room_id_at_screen_pos`. `Visualizer3D` se las pasa desde el edificio en las cuatro llamadas. Sin cotas mantiene el comportamiento anterior, así que ningún otro llamador se rompe.

### 🟡 V3-4. Selección de objetos por distancia al origen — **[CORREGIDO 2026-08-31]**
`_fuel_object_at_screen_pos` mide la distancia 2D al origen del nodo (34/32 px): los muebles grandes son difíciles de clicar por los bordes.

Corrección aplicada (F4.4): primero se busca el mueble cuya **silueta** contiene el clic —uniendo las cajas de todas sus mallas y proyectando las ocho esquinas— y entre los que lo contienen gana el más cercano a cámara. Si el clic no cae dentro de ninguno se conserva la búsqueda por proximidad de antes, para no perder el clic aproximado. El radio de gracia y el margen de la silueta son `@export` (`fuel_object_pick_radius_px`, `fuel_object_pick_margin_px`).

### ℹ️ V3-5. Ya corregido desde julio
Trabajo duplicado en `_update_dynamic_state` (ahora `_apply_selection_visuals` no rehace `_update_openings`), churn de materiales de marcador (`_set_marker_color` cachea en meta), poses de apertura (`_get_cached_opening_pose`), reconstrucción de la leyenda (hash de flags) y el nodo muerto `SmokeLayerEdge` (eliminado).

---

## 5. Primera persona (interior)

### 🟠 FP-1. Tabiques duplicados y coincidentes entre salas — **[CORREGIDO 2026-08-31]**
`_create_walls()` recorre las cuatro caras de **cada** sala sin comprobar si la cara es medianera. Dos salas contiguas generan dos cajas de muro **exactamente coplanarias** (ambas centradas en el borde compartido). Como `_wall_material_for_room()` da color distinto por tipo de estancia, la medianera cocina/pasillo parpadea entre los dos colores al mover la cámara: z-fighting de manual. Además duplica malla y colisión en todas las particiones interiores.

Corrección aplicada (F1.3): `_create_wall_segment_height()` registra la caja de cada tabique (centro y tamaño redondeados al centímetro) y no vuelve a construir una idéntica; las salas se recorren por id ascendente, así que el color de la medianera es estable entre reconstrucciones. El **rodapié sigue siendo por sala**: mira hacia dentro de cada estancia y se crea antes de la deduplicación. Cierra también el 🟠 de §8: la medianera deja de tener dos cuerpos de colisión.

Guardarraíl: `tools/validate_fp_party_walls.gd` (ninguna caja de tabique repetida, la medianera existe, y dos rodapiés en el plano compartido).

### 🟠 FP-2. Todo el interior es color plano sin textura — **[CORREGIDO 2026-08-31]**
`use_procedural_surface_noise = false` por defecto ([FirstPersonController.gd:88](../view/fp/FirstPersonController.gd)), y cuando se activa lo que se aplica es un `NoiseTexture2D` en escala de grises como `albedo_texture`, que **multiplica** el color base: oscurece y motea en vez de texturar. Es la causa de fondo del "se ve feo" transversal a interior, rellano y fachada. Lo correcto es un ruido de bajo contraste centrado en gris medio (o una textura de material real) y aplicarlo con UV en metros, no por cara.

Corrección aplicada (F2.1), en tres frentes:

1. **La rampa.** `NoiseTexture2D` con `color_ramp` de `1 − contraste` a blanco. Al multiplicarse sobre el albedo, el blanco deja el color base intacto y el ruido sólo lo rompe, en vez de bajarlo a la mitad y motearlo. Contraste por defecto 0,13.
2. **La escala.** `uv1_triplanar` + `uv1_world_triplanar` con `uv1_scale` derivada de `material_noise_size_m`: la textura se mide en metros, así que un tabique de 6 m y una jamba de 0,2 m tienen el mismo grano y el patrón encaja entre piezas contiguas.
3. **Estaba apagado y además los muros nunca lo pedían.** `use_procedural_surface_noise` pasa a `true`, y `_wall_material_for_room()` —que llamaba a `_mat()` sin semilla— ya la pasa: los paramentos verticales eran los únicos que jamás recibían ruido ni con la opción activada.

Suelos y rodapiés usan un perfil aparte (`NOISE_PROFILE_FLOOR`: más octavas, grano más grande y contraste multiplicado por `material_floor_dirt_boost`), que es la segunda capa de suciedad que pedía M-1.

### 🟠 FP-3. Geometría FP todavía paralela a la del 3D — **[CORREGIDO 2026-09-03]**
`StairGeometry` ya está extraída y compartida (el 🟠 FP-1 de julio está a medias), pero suelos, techos, muros y huecos siguen teniendo dos implementaciones independientes (`FirstPersonController` vs `Visualizer3D`). Cualquier ajuste hecho en una diverge visualmente de la otra.

Corrección aplicada (F5.1). **No se unifica lo que emite cada vista**: el mundo FP levanta arquitectura recorrible con colisión y el visor 3D dibuja una maqueta translúcida, y son dos cosas distintas a propósito. Lo que se unifica es el **reparto**, que es lo que estaba escrito dos veces. Cuatro módulos nuevos en `view/geometry/`, siguiendo el precedente de `StairGeometry`:

| Módulo | Qué recoge | Qué estaba duplicado |
|---|---|---|
| `BuildingLevels` | cota de una sala, si es hueco de escalera, hacia dónde sube, cota de la planta de encima, huecos verticales que perforan un forjado | las cinco consultas, en las dos vistas |
| `SlabGeometry` | reparto en losas de suelos y techos: el forjado de un hueco de escalera en planta alta (tiro único y ida y vuelta) y el troceado alrededor de los huecos verticales, con sus nombres | `_create_stairwell_upper_floor` frente a `_create_stairwell_upper_floor_visual`: misma aritmética, mismos umbrales (0,28 · 0,18 · 1,65 · 179°) y **los mismos nombres de nodo**, en dos sitios |
| `WallSideGeometry` | los cuatro lados de una sala: eje, opuesto, normales, por dónde tocan dos salas contiguas | `_shared_side_data` frente a `_shared_wall_pose`; `_inside_normal_for_side` frente a `_outside_normal_for_wall` |
| `OpeningPlacement` | dónde cae un hueco a lo largo de su paramento | `_opening_info_on_side` frente a `OpeningPose3D._center_axis`, carácter por carácter la misma regla |

**El techo no tenía pareja**: el visor 3D no dibuja techos arquitectónicos, sólo máscaras de humo. Lo que comparte con el suelo del FP es el troceado, y eso sí queda en `SlabGeometry`.

Dos divergencias reales que estaban ahí y salieron al juntarlas:

1. **`_find_next_floor_level_above` tenía dos contratos.** Sin planta encima, el mundo FP devolvía la propia cota y el visor devolvía −1,0. Los dos siguen vivos porque sus llamantes dependen de ello, pero ahora el valor de reserva es un parámetro explícito en la llamada, no una constante escondida en cada copia.
2. **Los alias cardinales de `wall_side`.** El modelo admite `north`/`south`/`east`/`west` (`BuildingModel` los normaliza en un sitio, `GasExchangeSystem` los rechaza en otro). El visor 3D los entendía; el mundo FP no, y una ventana declarada al norte se plantaba **sobre el paramento derecho**. Medido en el guardarraíl: 0,80 m de desplazamiento en el caso estrecho y 1,70 m en el ancho. Además el hueco nunca llegaba a recortar el muro, porque el lado que guardaba (`north`) no coincidía con ninguno de los cuatro que consulta `_opening_specs_for_side`.

Guardarraíl: `tools/validate_view_geometry_parity.gd`. Monta las dos vistas sobre el mismo edificio y compara **el reparto, no los píxeles**: losas del hueco de escalera (nombre y huella), troceado del suelo por el hueco vertical, y posición de cada hueco a lo largo de su paramento, con 1 mm de tolerancia. Dos casos, para recorrer las dos ramas del plan de losas. Con el código anterior del mundo FP falla con los números exactos del punto 2.

### 🟡 FP-4. Consultas repetidas por frame físico — **[NO REPRODUCIBLE 2026-08-31]**
`_find_current_room_id()` y `get_room_rects_m()` se recalculan varias veces por frame en overlay, HUD y humo.

**Ya no.** `get_room_rects_m()` se llama una sola vez y queda en `_room_rects_cache`; `_find_current_room_id()` se resuelve una vez por frame físico en `_current_room_id`, y su único otro uso es un fallback en `get_player_marker_state()` para cuando aún no se ha resuelto, con su comentario explicándolo. El hallazgo describía código anterior.

### 🟠 FP-6. La sala con humo y sin fuego se apaga por completo — **[CORREGIDO 2026-08-31]**
Verificado **en ejecución** (Godot 4.7.1 en la máquina del proyecto, capturas FP a 1600 × 900, 2026-08-31). La transmisión de humo de la sala escala la energía **y el alcance** de la luz de techo ([FirstPersonController.gd:4842](../view/fp/FirstPersonController.gd)):

```gdscript
light.light_energy = base_energy * transmission
light.omni_range = base_range * lerpf(0.50, 1.0, transmission)
```

Medido en un dormitorio de 4 × 4 × 2,62 m, capa a 1,95 m y 9 m de visibilidad (transmisión 0,529):

| Estado | Energía | Alcance |
|---|---|---|
| limpio | 0,599 | 3,23 m |
| con humo | 0,317 | **2,47 m** |

Con la luminaria en el techo a 2,62 m, un alcance de 2,47 m **no llega ni al suelo situado justo debajo** (2,62 > 2,47), y mucho menos a las esquinas (3,85 m). La sala se queda iluminada sólo por la ventana y se lee como una caja negra **aunque el observador esté por debajo de la interfase y el HUD marque 22 m de visibilidad**.

No es la niebla: con la representación de visibilidad desactivada (densidad forzada a 0) la pared sigue negra, y la captura con representación activada es indistinguible de la que no la tiene. Es iluminación.

Importa porque ése es justamente el estado de la sala contigua al incendio, por donde se mueve el usuario, y porque el término de densidad de `_light_smoke_transmission_for_room()` satura con sólo 0,018 kg/m³: dispara en casi cualquier escenario con humo. Matiza la nota FP-5.

Corrección aplicada (F1.1): el humo atenúa la **energía** pero ya no recorta el alcance. Nuevo `@export room_ceiling_light_smoke_range_min_factor` (1,0 por defecto = sólo se atenúa el brillo; valores menores reintroducen el recorte). `omni_range` es un corte duro, no una extinción: usarlo para modelar la absorción del humo deja a oscuras hasta el suelo que hay bajo la propia luminaria. La atenuación de energía se conserva intacta, así que el apagado casi total en régimen ILV crítico —que es correcto— sigue igual.

Medido sobre las capturas de referencia (§12.F0), luminancia media de la medianera del dormitorio enhumado: **18,9 → 32,4 (×1,71)**; la misma vista en estado limpio no cambia (57,5 → 57,5), es decir, la corrección sólo actúa en la ruta de humo. La sala sigue claramente más oscura que en limpio.

Guardarraíl: `tools/validate_fp_smoke_lighting.gd`. Con el comportamiento antiguo falla con el número exacto del hallazgo (`2.47 < 3.23`).

### ℹ️ FP-7. El humo entre salas de §1 no existe en primera persona — **[HALLAZGO ERRÓNEO, corregido 2026-08-31]**
**Este hallazgo era mío y era falso.** Lo deduje de que `FirstPersonController.gd` no menciona la cortina ni el penacho, y esa inferencia no vale: el humo no llega a primera persona desde el controlador FP, sino desde el propio `Visualizer3D`, que **corre como overlay en primera persona**. `Main._sync_view_mode()` hace `visualizer_3d_active = view_3d_enabled or first_person_enabled` y lo activa con `first_person_overlay = true`; en ese modo se ocultan salas, aperturas, etiquetas, sol y relleno, y queda visible justamente la capa de atmósfera. Además `show_smoke_geometry_in_first_person` y `show_smoke_opening_curtains_in_first_person` vienen activados.

Medido el 2026-08-31 montando FP y el visor como los monta `Main`:

| Comprobación | Resultado |
|---|---|
| Aportación del overlay de atmósfera en una sala enhumada | **28,3 %** de los píxeles |
| Aportación de la cortina de vano, mirando desde la sala limpia a la invadida | **2,0 %** de los píxeles |
| Aportación de la cortina, estando dentro del propio humo | 0 % (queda embebida en el volumen de la sala, que es lo correcto) |

Es decir: el cuerpo de humo y la cortina del vano **sí se ven donde está el jugador**. El código incluso trae calibración propia para ese caso (más opacidad, menos costados y más panza cuando `first_person_overlay`).

Lo único que faltaba de verdad era poder ajustar esa calibración sin tocar código: esos tres factores estaban cocidos. Ahora son `opening_curtain_first_person_alpha_factor`, `opening_curtain_first_person_side_visibility` y `opening_curtain_first_person_bottom_strength`, en el inspector del visor 3D.

### 🟡 FP-8. Los nodos homónimos pierden el nombre — **[CORREGIDO 2026-08-31]**
Descubierto al escribir el guardarraíl de FP-1. Godot renombra a `@MeshInstance3D@NN` —no a `Skirting_top2`— todo nodo cuyo nombre ya exista entre sus hermanos, porque `add_child()` se llama sin `force_readable_name`. El mundo FP cuelga decenas de `Skirting_top`, `Wall_right` y demás del mismo padre, así que **sólo el primero de cada nombre conserva su identidad**.

Dos consecuencias: el árbol es ilegible en el depurador remoto, y cualquier guardarraíl que cuente mallas por nombre encuentra únicamente la primera. Los validadores actuales pasan porque comprueban nombres que resultan ser únicos, pero es una trampa a la espera: `tools/validate_fp_party_walls.gd` ya tiene que identificar los rodapiés por geometría en vez de por nombre. La corrección es `add_child(node, true)` en los constructores, verificando antes que ningún validador dependa de encontrar sólo el primero.

Corrección aplicada (F5.6): las dieciséis llamadas que cuelgan mallas, cuerpos y luces del mundo FP pasan a `force_readable_name`. Ningún validador se rompe: la suite sigue en 30/31. Guardarraíl en `validate_fp_party_walls.gd`, que falla si aparece una malla con nombre `@...`; sin la corrección caza ocho.

### ℹ️ FP-5. Lo que está bien
Overlay de visibilidad, atenuación de luces por humo coherente con los regímenes ILV (con la salvedad de FP-6), HUD técnico con capa según postura, suavizado de temperatura con τ, presets día/noche, hojas de ventana con rotura de vidrio y el domo de cielo procedural (necesario porque GL Compatibility no dibuja el sky del Environment por cámara).

---

## 6. Visor 2D y minimapa

- 🟡 **V2-1.** — **[CORREGIDO 2026-08-31]** `_get_draw_transform()` ya se cacheaba por frame en `_frame_tf`, pero quedaban dos llamadas sueltas que rehacían el merge de límites en cada consulta de ratón. Ahora ambas pasan por `_current_draw_transform()`, que devuelve la del frame en curso y sólo la recalcula si aún no existe.
- 🟡 **V2-2.** — **[NO REPRODUCIBLE 2026-08-31]** El fondo **ya no** es un rectángulo fijo: `_draw_background()` toma `get_viewport_rect()`, lo lleva a coordenadas locales con la inversa de la transformada global y lo dibuja con 50 px de holgura, así que cubre cualquier viewport. No hay ningún `Rect2(-50,-50,4000,2500)` en `view/2d/`. El hallazgo describía código anterior.
- 🟡 **V2-3.** — **[NO REPRODUCIBLE 2026-08-31]** La escala tampoco es la descrita. `RoomStateVisuals2D.svv_color()` es una rampa de cinco tramos —≥90 % verde, ≥60 % ámbar, ≥20 % naranja, ≥5 % rojo y gris por debajo—, así que una sala al 95 % no alarma como una al 10 %: son verde y naranja. El hallazgo describía una versión anterior de la función.
- ℹ️ La isoterma de 150 °C ya no se dibuja en salas frías (🟠 V2-1 de julio corregido).

---

## 7. Materiales e iluminación (transversal)

- 🟠 **M-1.** — **[CORREGIDO 2026-08-31]** Todo el proyecto construía materiales con `StandardMaterial3D` de color plano, `roughness = 0.96` y sin mapas. Sin variación de superficie, cualquier geometría —por correcta que sea— se lee como maqueta de cartón. Resuelto con FP-2 (ruido con rampa, triplanar en metros y perfil de suciedad para suelos y rodapiés), extendido también a los materiales de fachada, que tampoco pedían semilla.
- 🟠 **M-2.** — **[CORREGIDO 2026-08-31]** No hay oclusión ambiental de ningún tipo (ni SSAO —no disponible en GL Compatibility— ni AO horneado ni un simple oscurecimiento de encuentros). Todos los encuentros suelo-pared son aristas duras a pleno color; es el segundo motivo por el que las escenas parecen planas.

  No se cierra en F2 a propósito, y conviene decir por qué: `StandardMaterial3D` no sabe oscurecer aristas sin un mapa de AO, y un mapa proyectado en triplanar de mundo no puede codificar dónde están las aristas. Las salidas reales son dos, y ambas cambian de categoría respecto al resto de F2: (a) mallas con color de vértice, que obliga a sustituir los `BoxMesh` por `ArrayMesh`; (b) un `ShaderMaterial` propio para muros, suelos y techos que oscurezca según la distancia a los bordes de la cara, con el tamaño de la caja entrando como `instance uniform` para que el ancho de la sombra se mida en metros y el material siga siendo único y cacheado.

  Se ha ejecutado la (b), con el visto bueno del usuario. `view/fp/fp_surface.gdshader` da a muros, suelos y techos el ruido triplanar en metros y la oclusión de contacto en un solo material: la distancia útil a la arista es la **segunda menor** de las tres distancias a las caras opuestas (sobre una cara, la primera es siempre ~0, la de la propia cara). El tamaño de la pieza entra como `instance uniform`, así que la franja se mide en metros en un tabique de 6 m y en una jamba de 0,2 m con el mismo material compartido.

  Medido sobre la captura de referencia del salón: el centro del paramento no se oscurece (101,2 → 100,3) y el contraste en la arista sube de **62,3 % a 69,7 %**. Es decir, añade sombreado de contacto sin apagar la superficie.

  Ajustable desde el inspector: `surface_contact_ao_enabled`, `surface_contact_ao_strength` y `surface_contact_ao_band_m`. Apagado, las superficies vuelven a `StandardMaterial3D`, lo que deja la comparación a un clic.

  Guardarraíl: `tools/validate_fp_surface_shading.gd`. Fija el contrato crítico —cada malla publica **su** tamaño por instancia— porque si eso se pierde no hay ningún error visible: el oscurecimiento simplemente pasaría de degradado a plano.
- 🟡 **M-3.** — **[CORREGIDO 2026-08-31]** `_mat()` creaba un `StandardMaterial3D` nuevo en cada llamada. Ahora cachea por color, semilla y perfil de ruido. Medido sobre el piso patrón: **910 → 144 materiales distintos** para 1003 mallas. Sólo se comparten los opacos y sin emisión: los transparentes y los emisivos se mutan en caliente (el tinte del cristal de una ventana, el brillo del fuego) y compartirlos los acoplaría entre sí.
- ℹ️ **M-4.** La iluminación sí está bien pensada: sol direccional con sombras, relleno suave, luz por hueco atenuada por humo, luces de techo contenidas a su sala y luz de fuego con ley de potencia sobre el HRR.

---

## 8. Rendimiento

- ℹ️ Cadencias: 2D/HUD a 20 Hz, 3D a ~8 Hz, FP a 20 Hz con el humo compartido a 8 Hz. Correcto.
- 🟡 El decorado exterior, la fachada nueva y el rellano son geometría estática construida una vez por `rebuild`, sin coste por frame más allá del draw call. El lienzo de fachada añade del orden de 10-20 cajas por edificio.
- 🟠 Cada segmento de muro FP crea un `StaticBody3D` propio: en una vivienda de 8 salas son ~40 cuerpos. La **colisión duplicada en medianeras está corregida** (FP-1, 2026-08-31); queda el cuerpo por segmento, que se revisará al unificar constructores (F5.1).

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
| FP-1 geometría FP duplicada | Corregido (§5 FP-3) |
| V2-2 transform recalculado por llamada | Casi corregido (§6 V2-1) |

---

## 10. Prioridad de la siguiente pasada

> **Tabla histórica.** Ordenaba la pasada siguiente cuando se escribió el informe; casi todo lo que lista está ya cerrado. El plan de ejecución está en §12 y el estado real de cada hallazgo, en **§13**. Se conserva para que se vea qué se priorizó y en qué orden se atacó de verdad.

| # | Hallazgo | Sev. | Área |
|---|---|---|---|
| 1 | FP-2/M-1 superficies sin textura utilizable | 🟠 | Materiales |
| 2 | FP-6 la sala con humo y sin fuego se apaga por completo | 🟠 | FP |
| 3 | FP-1 tabiques coincidentes con z-fighting | 🟠 | FP |
| 4 | M-2 sin oclusión ambiental ni acuerdo en encuentros | 🟠 | Materiales |
| 5 | H-5 la cortina de humo ignora la hoja de la puerta | 🟠 | Humo |
| 6 | E-4 rendija perimetral entre plantas (cerrarla en el techo) | 🟠 | FP |
| 7 | H-4 decidir si la contracorriente de aire se enseña por defecto | 🟠 | Humo |
| 8 | E-5 no generar decorado urbano detrás del rellano | 🟡 | FP |
| 9 | R-3/R-4 acabado del suelo del rellano y altura derivada | 🟡 | Rellano |
| 10 | V3-1 `render_priority` en la pila alfa | 🟡 | 3D |
| 11 | V3-2 captura 3D limpia a `SubViewport` | 🟡 | 3D |

---

## 11. Verificación

> **Ejecutado el 2026-08-31 en la máquina del proyecto.** `python scripts/check_product.py` da **25/26 suites OK**; el único fallo es `test_exit0_real_json`, el conocido de la línea motor por los `VALID_GAP`, ajeno a lo visual. Los guardarraíles visuales headless pasan todos, incluidos los dos ampliados en esta pasada (`validate_fp_exterior_context`, `validate_fp_landing_stairs`). Además se renderizó la vista FP con ventana real (headless no dibuja: `frame_post_draw` no dispara) sobre un piso de dos salas en estado limpio y en incendio; de ahí salen FP-6 y FP-7. Descartado por medición: la niebla **no** se arrastra al exterior al salir del edificio — fuera decae a 0,0001, lo que se ve durante ~1 s es el transitorio de `fp_fog_smooth_tau_s`.
>
> **Tercera ejecución, 2026-08-31 (fase F2):** suite 28/29 sin regresiones. El interior deja de ser color plano: ruido de superficie con rampa y proyección en metros, suelo del rellano con despiece de baldosa, cara exterior de los tabiques con material de fachada y 910 → 144 materiales distintos.
>
> **Segunda ejecución, 2026-08-31 (fases F0 y F1 del plan):** suite a **28/29** con los tres guardarraíles nuevos ya incorporados, mismo único fallo de la línea motor. Juego de capturas antes/después con `tools/capture_visual_reference.gd`: la corrección de FP-6 sube la luminancia media de la medianera enhumada de 18,9 a 32,4 (×1,71) sin tocar la escena limpia (57,5 → 57,5).

Cuando se redactó el informe los cambios **no se habían podido ejecutar**: aquel entorno no tenía Godot y la 4.7.1 que usa el proyecto no estaba disponible para descarga (se descartó comprobar con una versión distinta porque los resultados no serían representativos). Lo que sí se hizo entonces:

- Revisión estática del GDScript modificado (indentación, delimitadores, continuaciones de línea) y de la orientación de las normales del nuevo intradós en las dos orientaciones de muro.
- Los guardarraíles headless se han **ampliado** para cubrir lo nuevo, de modo que la ejecución en tu máquina los verifique:
  - `tools/validate_fp_exterior_context.gd`: existencia del lienzo, del zócalo y de la coronación; que ningún panel tapa el hueco de la ventana; que el frente del rellano queda libre.
  - `tools/validate_fp_landing_stairs.gd`: luces propias del rellano encendidas y **un solo** portal con dos puertas exteriores en la misma fachada.

Comando de verificación:

```powershell
python scripts/check_product.py
```

Revisión visual recomendada, con [CHECKLIST_VISUAL_REGRESION.md](CHECKLIST_VISUAL_REGRESION.md) delante: `preset_compact_apartment` (rellano y fachada de piso), `preset_two_storey_house` (fachada de dos plantas y rendija perimetral) y cualquier escenario con fuego declarado, mirando una ventana desde fuera en dollhouse y desde dentro en primera persona.

---

## 12. Plan de trabajo — cierre de todos los hallazgos visuales

**Redactado:** 2026-08-31, tras verificar el informe en ejecución (§11).
**Objetivo:** dejar en cero los hallazgos 🔴/🟠/🟡 abiertos de §1-§8. Los ℹ️ que no son fallo (H-6, FP-7) quedan como decisión explícita, no como deuda silenciosa.

### 12.0 Reglas del plan

Invariantes que ninguna fase puede saltarse:

1. **No se toca el motor.** Nada de `sim/`, `scripts/simulation/` ni casos de validación. Esta línea es independiente de la línea motor (programa P1 de codex, en su propio worktree).
2. **Todo lo que pueda gobernarse desde el editor de Godot, se gobierna desde el editor.** No sólo los parámetros como `@export` en su grupo del inspector: también ranuras de recurso (`StandardMaterial3D`, `Texture2D`) para poder sustituir lo procedural por material propio sin tocar código, y los ajustes del instrumental en su escena. Nada de constantes de aspecto enterradas en el script. La regla la impone `tests/test_godot_editability.py`, que falla si un mando desaparece del inspector.
3. **Cada fase cierra con `python scripts/check_product.py` en verde**, admitiendo como único fallo `test_exit0_real_json` (línea motor, `VALID_GAP`).
4. **Ningún hallazgo se marca [CORREGIDO] sin evidencia**: o un guardarraíl headless que lo protege, o una captura renderizada antes/después, y preferiblemente ambas.
5. **Un commit por fase**, con el informe actualizado en el mismo commit (marcas [CORREGIDO] + fecha).
6. Si una fase descubre que el diagnóstico del informe era incorrecto, **se corrige el informe antes de tocar el código**.

### 12.F0 Instrumental de verificación (prerrequisito) — **HECHO 2026-08-31**

El informe original no se pudo verificar por no tener Godot; el addendum de §11 se hizo con una sonda desechable. Antes de tocar nada, esa sonda se convierte en herramienta permanente:

- `tools/capture_visual_reference.gd` (+ `.tscn`): monta un piso patrón de dos salas (salón con ventana a fachada y puerta a rellano, dormitorio con ventana) y captura un juego fijo de vistas FP y 3D en estado limpio y en incendio, a un directorio dado.
- Se ejecuta **con ventana real**: en `--headless` no hay render (`frame_post_draw` no dispara) y las capturas salen vacías.
- Uso: juego de referencia antes de cada fase y comparación después. Es lo que convierte "se ve mejor" en un antes/después revisable.

Sin esto, las fases 2 y 3 (material y humo) no son verificables.

**Entregado:** `tools/capture_visual_reference.gd` + `.tscn`. Dieciocho vistas por pasada (ocho puntos de vista FP × limpio/incendio, más las dos de la casa de muñecas), con `--out=<dir>` y `--label=<prefijo>` para guardar juegos antes/después en el mismo directorio. Replica la configuración real de `scenes/SimulationScene.tscn` —sol, luz de relleno, rig de cámara y los cuatro overrides de iluminación FP— para que la captura corresponda con lo que ve el usuario y no con los defaults del script. Devuelve código 1 si falta alguna vista o si se lanza en `--headless`.

### 12.F1 Fase 1 — Lo que rompe la escena o el juego — **HECHO 2026-08-31**

| # | Hallazgo | Trabajo | Verificación |
|---|---|---|---|
| F1.1 | 🟠 FP-6 | Atenuar **energía** por humo pero no el alcance; acotar `omni_range` por abajo a la diagonal sala+altura. Ponderar la atenuación por la fracción del trayecto luz → superficie que cruza la capa, en vez del estado global de la sala. | Guardarraíl nuevo: con humo y sin fuego, `omni_range` ≥ diagonal de la sala y la energía baja pero no se anula. Capturas del addendum como antes/después. |
| F1.2 | 🟡 R-8 | `StaticBody3D` + `CollisionShape3D` en `LandingBackWall`, `LandingSideWall` y el frente nuevo. | Ampliar `validate_fp_landing_stairs.gd`: toda pared del rellano tiene cuerpo estático. Es lo que impide que el jugador atraviese el portal y caiga al vacío. |
| F1.3 | 🟠 FP-1 | Deduplicar medianeras en `_create_walls()`: una sola caja por cara compartida, con criterio estable de qué sala la pinta. Cierra de paso el 🟠 de §8 (colisión duplicada, ~40 cuerpos en 8 salas). | Guardarraíl: dos salas contiguas producen **una** malla de medianera y **un** cuerpo. Captura moviendo la cámara sobre la medianera (hoy parpadea). |
| F1.4 | 🟠 E-4 | Que el techo llegue a la cara inferior del forjado superior, cerrando el anillo de ~7 cm también en frentes sin huecos y en encuentros interiores. | Guardarraíl geométrico sobre `preset_two_storey_house`: sin holgura vertical entre techo de planta y suelo de la siguiente. Captura desde dentro mirando el encuentro. |

Fase 1 es la única que arregla algo **funcional** (F1.2) y algo que hace ilegible la escena de trabajo real del usuario (F1.1).

**Resultado:** los cuatro cerrados, cada uno con un guardarraíl nuevo que falla con el comportamiento anterior y con los números exactos del hallazgo (`2.47 < 3.23` en FP-6, `0.070 m` en E-4, dos cajas coincidentes en FP-1). Tres guardarraíles nuevos registrados en `check_product.py` (`FP smoke lighting`, `FP party walls`, `FP interstitial seal`) y uno ampliado (`FP landing stairs`). Suite: **28/29 en verde**, único fallo el conocido de la línea motor.

De propina salieron dos cosas que no estaban en el informe: el parámetro `with_collision` de `_add_box` era un contrato falso (ver R-8) y los nodos homónimos pierden el nombre (nuevo FP-8, §5). El primero se corrigió por ser la causa directa de R-8; el segundo queda abierto y planificado en F5.6.

### 12.F2 Fase 2 — Legibilidad del material (la palanca del "se ve feo") — **HECHA 2026-08-31**

Es la fase con mejor relación coste/beneficio: M-1 y FP-2 son la causa de fondo del síntoma transversal, y afectan a interior, rellano y fachada a la vez.

| # | Hallazgo | Trabajo |
|---|---|---|
| F2.1 | 🟠 FP-2 + 🟠 M-1 | Ruido de superficie utilizable: bajo contraste **centrado en gris medio** (que no oscurezca al multiplicar), UV en metros y no por cara (triplanar o UV2 escalada), activable por material. Segunda capa de suciedad en suelos y rodapiés. |
| F2.2 | 🟠 M-2 | Oclusión ambiental barata: no hay SSAO en GL Compatibility, así que oscurecimiento de encuentros por color de vértice o por gradiente en el propio shader de muro/suelo. Es el segundo motivo de que todo parezca plano. |
| F2.3 | 🟡 M-3 | Caché de materiales por color en `_mat()`: hoy la fachada, el rellano y el decorado crean decenas de `StandardMaterial3D` idénticos. |
| F2.4 | 🟡 E-6 | Cara exterior de los tabiques con material de fachada, no con el color de la estancia. |
| F2.5 | 🟡 R-3 | Acabado del suelo del rellano: despiece de baldosa o franjas de tono, en vez de losa de color plano. |

Verificación: juego completo de capturas F0 antes/después, más `check_product.py`. F2.1 y F2.2 son de calibración: se ajustan mirando las capturas, no a ciegas.

**Resultado:** cerradas F2.1 (FP-2 + M-1), F2.3 (M-3: 910 → 144 materiales distintos sobre 1003 mallas), F2.4 (E-6) y F2.5 (R-3, con el despiece de baldosa visible en la captura del rellano). Suite 28/29, único fallo el conocido de la línea motor.

**Todo el aspecto queda gobernado desde el inspector**, no desde el script: rugosidad, resolución y octavas del ruido, factores del perfil de suelo, lado y junta de la baldosa, grosor de la chapa de fachada, y un grupo nuevo **"Materiales propios FP"** con ranuras para material de muro, suelo, techo y fachada y para texturas de superficie y de baldosa — si pones un recurso, manda el recurso; si la dejas vacía, se genera por código. El caché de materiales se vacía en cada reconstrucción justamente para que un cambio en el inspector se vea. Cuatro pruebas nuevas en `tests/test_godot_editability.py` (12 en total) impiden que cualquiera de esos mandos vuelva a quedar cocido en el código.

**F2.2 (M-2) cerrada el 2026-08-31**, ya con la decisión tomada: `ShaderMaterial` propio para muros, suelos y techos, con el tamaño de la caja como `instance uniform`. Detalle y medición en §7.

Al calibrar aparecieron además dos errores en los puntos de vista del instrumental de F0, ya corregidos: la pared `bottom` de un rectángulo es el lado `y = y0 + alto` y su `offset_m` corre en sentido inverso al eje (el portal no estaba donde se le buscaba), y el jugador es un `CharacterBody3D` con gravedad, así que una vista colocada sobre el hueco de la escalera se cae por él y captura la calle.

### 12.F3 Fase 3 — Humo y su lectura — **PARTE TÉCNICA HECHA 2026-08-31**

| # | Hallazgo | Trabajo | Nota |
|---|---|---|---|
| F3.1 | 🟠 H-5 | Estrechar el puente al hueco libre real (ancho × fracción) y desplazarlo al lado de la bisagra, para que el humo no atraviese la hoja. | Guardarraíl: con `open_fraction` 0,5 el ancho de la cortina es la mitad y está desplazado. |
| F3.2 | 🟡 H-7 | `_update_vertical()` debe dibujar el penacho con **una** sala presente, tomando la ausente como limpia. | Hoy una escalera hacia una planta no representada no muestra humo aunque la de abajo esté cargada. |
| F3.3 | ℹ️ H-8 | Normalizar `smoke_local_y` por `meters_to_units` en vez de asumir 1. | No afecta hoy; es una bomba de relojería. Coste mínimo: se hace y se olvida. |
| F3.4 | 🟠 H-4 | **Decisión de producto**, no técnica: encender `show_cold_air_inflow_curtains` por defecto. A favor, con H-2 ya corregido completa la lectura bidireccional del vano; en contra, colorear el aire de azul es una convención, no una observación. | Se presenta con captura de las dos opciones y decide el usuario. |
| F3.5 | ℹ️ FP-7 | **CERRADA sin trabajo de implementación (2026-08-31)**: el supuesto de partida era falso. El visor 3D ya corre como overlay en primera persona y aporta el 28,3 % de los píxeles de una sala enhumada; la cortina de vano aporta el 2,0 % mirando desde la sala limpia. Sólo se han sacado al inspector los tres factores de calibración FP que estaban cocidos. Detalle en §5. | — |

**Resultado de la parte técnica:** F3.1 (H-5) cerrada con guardarraíl y con una enmienda al diagnóstico del informe —el hueco libre está del lado de la cerradura, no de la bisagra—; F3.3 (H-8) cerrada. F3.2 (H-7) **no era reproducible**: se deja salvaguarda y el hallazgo queda reclasificado en §1, no marcado como corregido. Suite 29/30, único fallo el conocido de la línea motor.

Quedan vivas las dos decisiones de producto, F3.4 (H-4) y F3.5 (FP-7).

### 12.F4 Fase 4 — Visor 3D y visor 2D — **HECHA 2026-08-31**

| # | Hallazgo | Trabajo |
|---|---|---|
| F4.1 | 🟠 V3-1 | `render_priority` explícito en la pila alfa por sala (volumen, máscara de techo, gradiente, capa caliente, isoterma, cortina, penacho). Hoy se disimula porque dos capas están apagadas por defecto; al encenderlas aparece el *popping*. |
| F4.2 | 🟠 V3-2 | Captura técnica a `SubViewport` limpio, sin HUD. |
| F4.3 | 🟡 V3-3 | `is_screen_point_over_model()` contra el plano de la planta activa, no contra y=0. |
| F4.4 | 🟡 V3-4 | Selección de mobiliario por AABB proyectado, no por distancia 2D al origen del nodo. |
| F4.5 | 🟡 V2-1 · V2-2 · V2-3 | Las dos llamadas sueltas a `_get_draw_transform()`; fondo derivado del viewport en vez de `Rect2` fijo; escala de color SVV con gradiente legible (hoy 5-90 % es el mismo rojo). |

**Resultado:** cerradas V3-1, V3-2 (verificada con ventana real: captura 1920 × 1080 con cero píxeles de HUD), V3-3, V3-4 y V2-1. **V2-2 y V2-3 no son reproducibles**: el fondo ya se deriva del viewport y la escala SVV ya es una rampa de cinco tramos; ambas descripciones corresponden a código anterior y quedan reclasificadas en §6, no marcadas como corregidas. Suite 30/31, único fallo el conocido de la línea motor.

### 12.F5 Fase 5 — Coherencia estructural y coste — **HECHA (F5.1 cerrada 2026-09-03)**

| # | Hallazgo | Trabajo |
|---|---|---|
| F5.1 | 🟠 FP-3 | Unificar los constructores de suelo, techo, muro y hueco entre `FirstPersonController` y `Visualizer3D`, como ya se hizo con `StairGeometry`. **Va al final a propósito**: hacerlo antes obligaría a rehacerlo tras las fases 1-3. |
| F5.2 | 🟡 FP-4 | Cachear `_find_current_room_id()` y `get_room_rects_m()` por frame físico. |
| F5.3 | 🟠 E-5 | No generar decorado urbano en frentes cuyo único hueco exterior sea la puerta del portal. |
| F5.4 | 🟡 R-4 | Derivar `landing_floor_height_m` de la altura real de la vivienda y su forjado. |
| F5.5 | 🟡 R-5 | Acuerdo entre el porche unifamiliar y el césped: bordillo, cambio de material o sombra propia. |
| F5.6 | 🟡 FP-8 | `add_child(node, true)` en los constructores para que los nodos homónimos no pierdan el nombre, comprobando antes que ningún validador dependa de encontrar sólo el primero. |

**Resultado:** cerradas F5.3 (E-5), F5.4 (R-4, medida), F5.5 (R-5) y F5.6 (FP-8, con guardarraíl). **F5.2 (FP-4) no era reproducible** y queda reclasificada en §5.

**F5.1 (FP-3) quedó desbloqueada** al resolverse FP-7 sin implementación: esperaba a FP-7 porque, si el humo entre salas bajaba a primera persona, convenía tener antes un constructor unificado, y el overlay ya lo resolvía. **Cerrada el 2026-09-03** con cuatro módulos compartidos en `view/geometry/` y un guardarraíl de paridad entre las dos vistas; el detalle está en la ficha de §5. Con ella se cierra F5 entera.

### 12.F6 Fuera del cierre — mejora, no fallo

- 🟡 **H-6 autoexposición**: humo que sale por una ventana y entra por la de la planta superior. El informe ya dice que el comportamiento actual es correcto. Es funcionalidad nueva y expresiva, y se trata como tal: **no** bloquea el cierre de esta línea.

### 12.7 Cobertura — ningún hallazgo se queda fuera

| Sección | Hallazgos abiertos | Destino |
|---|---|---|
| §1 Humo | H-4, H-5, H-6, H-7, H-8 | F3.4, F3.1, **F6**, F3.2, F3.3 |
| §2 Exterior | E-4, E-5, E-6 | F1.4, F5.3, F2.4 |
| §3 Rellano | R-3, R-4, R-5, R-8 | F2.5, F5.4, F5.5, F1.2 |
| §4 Visor 3D | V3-1, V3-2, V3-3, V3-4 | F4.1, F4.2, F4.3, F4.4 |
| §5 FP | FP-1, FP-2, FP-3, FP-4, FP-6, FP-7, FP-8 | F1.3, F2.1, F5.1, F5.2, F1.1, F3.5, F5.6 |
| §6 Visor 2D | V2-1, V2-2, V2-3 | F4.5 |
| §7 Materiales | M-1, M-2, M-3 | F2.1, F2.2, F2.3 |
| §8 Rendimiento | muros con cuerpo propio | F1.3 (misma causa que FP-1) |

Veintiséis hallazgos abiertos en la redacción del plan: veinticuatro se cierran en F1-F5, uno se decide (H-4, en F3.4), uno se acota (FP-7, en F3.5) y uno queda declarado como mejora futura (H-6, en F6). La ejecución de F1 cerró cuatro (FP-6, FP-1, E-4, R-8) y destapó uno nuevo (FP-8): quedan **veintitrés**.

### 12.8 Definición de terminado

La línea visual se considera cerrada cuando:

1. §1-§8 no tienen ningún hallazgo 🔴/🟠/🟡 en estado [ABIERTO], [PARCIAL] o [MITIGADO].
2. `python scripts/check_product.py` da verde salvo el fallo conocido de la línea motor.
3. Existe un juego de capturas de referencia por fase, comparable con el de F0.
4. Cada corrección tiene guardarraíl headless, o una justificación escrita de por qué no puede tenerlo.
5. Las dos decisiones de producto (H-4, FP-7) están resueltas por el usuario y anotadas aquí.

### 12.9 Orden de ataque recomendado

F0 → F1 → F2 → F3 → F4 → F5. **F0 y F1 hechos el 2026-08-31; siguiente, F2.** F1 primero porque contiene lo único funcionalmente roto (R-8) y lo que hace ilegible la sala contigua al fuego (FP-6); F2 inmediatamente después porque es lo que de verdad responde al síntoma "se ve feo"; F5.1 al final para no rehacer el trabajo de las fases anteriores.

---

## 12b. Correcciones tras ejecutar el simulador (2026-08-31, tarde)

Reportadas por el usuario tras correr el simulador de verdad, que es la prueba que ninguna captura sustituye. Tres síntomas: sombras y texturas raras en rellano y pasillo, dientes de sierra que cambian con el movimiento, y un penacho de humo que sale por el hueco como un cuadrado anaranjado.

### 🔴 X-1. Piezas decorativas finas proyectando sombra — **[CORREGIDO]**
Ninguna malla del mundo FP controlaba su proyección de sombra, así que el sol exterior las proyectaba **todas**, incluidas las piezas finas y casi coplanarias con el muro que recibe la sombra: rodapié (2,8 cm a 1,2 cm del muro), chapa de fachada (2 cm), bordillo y grava del porche. Con un mapa de sombra ortogonal que sigue a la cámara, eso es acne de sombra de manual, y **se mueve al andar**: exactamente lo que se ve en pasillos y en el rellano, que es donde más rodapié hay.

Corrección: esas piezas dejan de proyectar sombra (`_mark_decorative`), con interruptor `decorative_pieces_cast_shadows`. No cambian la lectura de la escena; sólo dejaban de estorbar.

### 🟠 X-2. Textura de superficie sin mipmaps — **[CORREGIDO]**
El shader de superficie declaraba `uniform sampler2D surface_noise : source_color, hint_default_white` sin cualificadores de filtro. La textura se proyecta en coordenadas de **mundo** y se repite cada 1,8 m, así que sin mipmaps dentellea y parpadea al mover la cámara, sobre todo en paramentos largos vistos de refilón —un pasillo, justamente—. Además `source_color` aplicaba conversión sRGB a lo que es una **máscara**, no un color.

Corrección: `filter_linear_mipmap_anisotropic, repeat_enable`, sin `source_color`; `generate_mipmaps` en la textura de ruido y `image.generate_mipmaps()` en la de baldosa, cuya junta de 3 px era lo primero en dentellear. El mismo cualificador se añade al shader de humo, que tenía el problema latente.

**Honestidad sobre la verificación:** el parpadeo es temporal y una captura fija no lo mide —medido, el ruido de alta frecuencia en las capturas no cambia—. Estas correcciones son correctas por sí mismas, pero **quien confirma que el síntoma desaparece es la siguiente ejecución del simulador**, no este informe.

### 🟠 X-3. El penacho exterior salía como una losa anaranjada — **[CORREGIDO]**
Tres causas sumadas:

1. **Color.** `_outflow_color()` mezclaba hasta un 58 % hacia el naranja caliente, así que el penacho no se parecía al humo de la sala de la que sale. Ahora parte del color del humo con un sesgo caliente pequeño y ajustable (`exterior_plume_hot_tint`, 0,18); con 0 sale exactamente del color del humo.
2. **Forma.** `side_visibility` estaba en 0,68: se leían las cuatro caras del volumen a la vez y el penacho parecía una caja. Baja a 0,34 y el borde se suaviza (0,52 → 0,72).
3. **Dinámica.** La turbulencia era constante (0,94) y la velocidad casi. Ahora ambas interpolan con el empuje: poca carga da columna lisa y lenta (laminar), mucha carga da revuelta y rápida. Cuatro parámetros en el inspector para el régimen.

Además, el penacho estaba **gateado por `curtain_visible`**, el mismo acoplamiento que mataba la contracorriente en H-4: dependía de que la cortina del hueco hubiese superado su propio umbral de visibilidad, y por eso aparecía y desaparecía de golpe en vez de crecer con el incendio. Ahora lo gobierna que haya humo saliendo (`exterior_plume_min_source_alpha`), con el acoplamiento anterior disponible en `exterior_plume_requires_curtain`.

Verificado en captura: con el enganche corregido el penacho se dibuja, y lo hace como una columna gris ahusada que sale del hueco, no como una losa naranja.

### 🟠 X-4. Los dientes de sierra eran el borde de sombra, no la textura — **[CORREGIDO 2026-09-01]**
Diagnosticado sobre el **vídeo del simulador** que grabó el usuario, extrayendo fotogramas con ffmpeg. Ampliado el pasillo, lo que parecía alias de textura es un **patrón de puntos a lo largo de un borde de sombra**: en GL Compatibility el difuminado de sombra se hace con un tramado por píxel, y con `shadow_blur = 1.4` sobre un mapa que reparte su resolución entre 42 m el borde se llena de puntos que **reptan al mover la cámara**. Eso es exactamente el síntoma descrito.

Corrección: `exterior_sky_shadow_blur` 1,4 → 0,6 y `exterior_sky_shadow_max_distance_m` 42 → 22, que concentra los texeles donde de verdad se mira. Ambos ya eran `@export`.

### 🟠 X-5. El ruido de pared se leía como humedades — **[CORREGIDO 2026-09-01]**
En el mismo fotograma del pasillo, la pared tiene manchas del tamaño de una persona: medido, un contraste p5-p95 del **56 %**. El patrón era demasiado grande (1,8 m) y demasiado contrastado (0,13) para leerse como enfoscado.

Corrección: contraste 0,13 → **0,06** y tamaño 1,8 → **0,85 m**. El grano pasa a ser de material en vez de mancha.

### 🔴 X-6. El instrumental de capturas no era determinista — **[CORREGIDO 2026-09-01]**
Descubierto al comparar dos capturas seguidas: **la misma versión, ejecutada dos veces, daba vistas FP distintas** (33,86 y 21,12 de diferencia media por canal), mientras la casa de muñecas salía idéntica (0,00). El jugador es un `CharacterBody3D` con gravedad y `move_and_slide()`: durante el reposo se desliza y cae, y cuánto lo haga depende del ritmo de fotogramas.

**Consecuencia sobre lo ya afirmado en este informe:** las comparaciones antes/después de vistas FP con diferencias pequeñas —del orden de unas décimas o pocos puntos porcentuales— no eran fiables y no deben leerse como prueba. Las diferencias grandes y repetidas sí (FP-6 subía la luminancia de 18,9 a 32,4, ×1,71), pero conviene rehacerlas ahora que el instrumental es estable. Las medidas de la casa de muñecas nunca estuvieron afectadas.

Corrección: el jugador se vuelve a fijar y se le anula la velocidad justo antes de capturar. Verificado: dos ejecuciones seguidas dan 0,00 de diferencia en las vistas estáticas y 0,06 en la del fuego, que tiene llama animada.

### 🟠 X-7. El humo del hueco a fachada era un cajón a caballo del muro — **[CORREGIDO 2026-09-01]**
Identificado por el usuario sobre su propia grabación, después de que yo persiguiese dos objetos equivocados: *"es un rectángulo tridimensional que está en la ventana, mitad dentro y mitad fuera de la habitación, y de ahí sale el penacho de humo exterior"*.

Es el **puente de humo del vano** (`SmokeCurtain_XX`), y tenía dos defectos de forma además del color ya corregido:

1. En un hueco a fachada el fondo se **forzaba** a un mínimo de 0,54 m (`blend_depth_m = maxf(blend_depth_m, 0.54)`), lo que convierte el puente en un volumen tan profundo como medio metro clavado en el muro.
2. Se desplazaba hacia la calle sólo un 32 % de ese fondo, así que quedaba literalmente **medio dentro y medio fuera**.

Corrección: en huecos a fachada el fondo se **acota** al espesor del hueco (`exterior_opening_curtain_depth_m`, 0,30 m) en vez de forzarse a un mínimo, y el desplazamiento hacia fuera sube a 0,55 del fondo (`exterior_opening_curtain_outward_shift`), de modo que la lámina queda pegada por fuera. La mitad interior no se echa en falta: ese volumen ya lo pinta el humo de la propia sala.

Verificado en captura con humo denso: el puente pasa de losa ancha metida en la habitación a lámina fina pegada al hueco, y lo que se lee es humo saliendo con su penacho encima.

**Nota de método.** Antes de acertar recoloreé el penacho exterior y luego la cortina, y llegué a proponer al usuario cinco zonas numeradas sobre su propio fotograma para que señalase el objeto. Fue eso lo que resolvió en un mensaje lo que tres rondas de deducción no habían resuelto. Con síntomas visuales, **pedir que señalen sobre la imagen es más barato que deducir**.

### ✅ X-8. Iluminación inestable en suelo y paredes al mover la cámara — **[CERRADA 2026-09-05: superficies superpuestas, confirmado en ejecución]**

> **Cierre.** El usuario confirma corriendo el simulador que el suelo del rellano, el techo del rellano y los pasillos de la vivienda quedaron arreglados. La causa era la que se había deducido: *«se superponía la capa trasera con la delantera»*, es decir dos caras compitiendo por el mismo píxel. Ni sombra, ni luces, ni material. El detalle del cierre está al final de esta ficha; lo que sigue es el registro completo de lo descartado por el camino.
El usuario lo describió con precisión y resultó ser **un solo fenómeno en dos sitios**: *"en el suelo del rellano aparece iluminación irregular cuando muevo la cámara, con formas redondas, cuadradas, líneas de sierra... de forma aleatoria"*, y lo mismo en las paredes del pasillo. No son dos problemas: son el mismo, y resultó ser superficies superpuestas peleando por el píxel.

**La primera hipótesis fue equivocada** y se registra porque costó varias rondas: se atribuyó al mapa de sombra del sol, que se recalcula siguiendo a la cámara. Tres causas acumuladas, atacadas juntas:

1. **El filtro de sombra estaba en calidad 3.** En GL Compatibility las calidades altas muestrean con un patrón **tramado y rotado por píxel**; el borde de sombra se llena de puntos que reptan al andar. `soft_shadow_filter_quality` 3 → **0**: sombra dura pero estable, que dentro de una vivienda es lo que interesa. `directional_shadow/size` se fija explícitamente en 4096.
2. **Acne de sombra.** Dentro de una vivienda los paramentos quedan casi rasantes a la luz del sol, el caso peor. `exterior_sky_shadow_bias` 0,08 → **0,18**.
3. **Densidad de texel.** Repartir el mapa entre 42 m dejaba muy pocos texeles donde se mira. Ya se había bajado a 22 m; ahora **15 m**. El decorado lejano no necesita sombra.

`exterior_sky_shadow_blur` pasa a 0: con el filtro en calidad 0 el difuminado no aporta y solo reintroduce inestabilidad.

**El usuario confirma que sigue igual tras estos cambios, así que la hipótesis de la sombra del sol queda descartada.** Lo que sigue es el registro de lo que se ha probado, para no repetirlo.

Reproducción intentada con la receta del usuario (plantilla `simple_house`, puerta abierta, cámara moviéndose en el pasillo), montando FP con el overlay 3D igual que `Main`:

| Prueba | Resultado |
|---|---|
| Cámara quieta, pasando el tiempo | **0,00 %** de píxeles inestables: la escena es perfectamente estática |
| Cámara moviéndose 2 cm y 0,4° | 10,66 % de píxeles saltan más de 30 niveles |
| Sombra del sol **apagada** | 11,46 %: **no mejora**, luego no es la sombra |
| Límite de luces por objeto 8 → 32 | 3,60 → 3,61 en pared plana: **sin efecto** |
| Oclusión de contacto apagada | 3,92: **sin efecto** |
| Ruido de superficie apagado | 3,59: **sin efecto** |

Y una advertencia sobre esas cifras: al girar 0,4° con 75° de campo la imagen se desplaza unos 8 px, así que **la métrica global mide sobre todo movimiento legítimo**, no artefactos. Los intentos de compensar ese movimiento saturaron el rango de búsqueda. Es decir: **el piso patrón no reproduce el fenómeno**, y las tres correcciones aplicadas antes de saberlo —mipmaps, ajustes de sombra y límite de luces— se hicieron sobre diagnósticos no confirmados.

Los cambios de sombra (bias 0,18, alcance 15 m, filtro sin tramado) se conservan porque son defendibles por sí mismos, pero **no están verificados como solución de esto**.

**Primer intento de bisección: fallido por culpa de la instrucción, no del usuario.** Se le pidió apagar cinco interruptores uno a uno desde el inspector remoto, con el juego corriendo. Ninguno tuvo efecto, y la razón es que **cuatro de los cinco solo se leen al construir el mundo**: `use_procedural_surface_noise` y `surface_contact_ao_enabled` se consultan al crear los materiales, `exterior_sky_light_cast_shadows` al crear la luz, y `room_ceiling_lights_enabled` al crear las luces de techo. Cambiarlos en caliente no hacía nada. Sólo `show_smoke_volume` se aplica de verdad en vivo, y ése sí queda descartado.

Es un caso claro de export que **parece** editable y no lo es, justo lo contrario de la regla del proyecto. Corregido: esas propiedades tienen ahora `set` que reconstruye el mundo si ya existe (`_rebuild_if_live()`), con guarda de reentrada, porque la reconstrucción vuelve a asignar algunas de ellas y sin la guarda el juego se cuelga —lo hizo, y lo cazó `validate_furniture_runtime` al agotar su tiempo—.

Con eso la bisección vuelve a ser viable **y ahora sí en caliente**: apagar uno cada vez desde el inspector remoto reconstruye la vivienda al instante.

**Segundo fallo de método, encontrado antes de volver a molestar al usuario (2026-09-01).** Los setters del commit anterior no bastaban: la reconstrucción que disparan pasa por `_apply_startup_lighting_options()`, y esa función **reescribe** `room_ceiling_lights_enabled` y `exterior_lighting_mode` desde el edificio. Es decir, apagar las luces de techo en el inspector las volvía a encender sola dentro de la misma reconstrucción. La trampa otra vez, ahora disfrazada de setter que sí funciona. Además la reconstrucción llamaba a `_place_at_entry()`, que devuelve al jugador a la puerta: en una bisección eso obliga a rehacer el camino hasta el artefacto en cada paso, justo cuando lo que se necesita es comparar dos estados desde el mismo punto de vista.

Corregido:

- `_rebuild_if_live()` ya no llama a `rebuild_from_building()`. Reconstruye el mundo y **conserva posición, guiñada y cabeceo**. En una reconstrucción pedida desde el inspector manda el inspector, no las opciones de arranque.
- El guard de reentrada cubre también `rebuild_from_building()`, `setup()` y `apply_preset()`. Sin eso, ahora que esas propiedades tienen setter, **cada reconstrucción normal disparaba otra reconstrucción anidada dentro de sí misma**, y aplicar un preset disparaba una por cada propiedad que asigna.
- Nueve interruptores más que solo se leían al construir pasan a aplicarse en vivo: `ambient_fill_enabled`, `room_ceiling_lights_cast_shadows`, `opening_lights_cast_shadows`, `exterior_context_enabled`, `exterior_lighting_mode`, `exterior_facade_fill_enabled`, `exterior_procedural_sky_enabled`, `exterior_own_facade_enabled`, `exterior_window_obstacles_enabled` y `opposite_facade_enabled`.
- Dos guardarraíles nuevos en `tests/test_godot_editability.py`: `test_build_time_fp_knobs_apply_live` exige setter con `_rebuild_if_live()` en cada uno de esos interruptores, y `test_live_rebuild_does_not_undo_the_inspector` prohíbe que la reconstrucción en vivo reaplique las opciones de arranque o reubique al jugador.

**Bisección propuesta, de corte grande a corte fino.** Cada paso es un solo booleano en el inspector remoto sobre `FirstPersonController`; la vivienda se reconstruye al instante y la cámara no se mueve, así que se compara desde el mismo sitio.

| Paso | Interruptor | Qué elimina | Si el artefacto desaparece |
|---|---|---|---|
| 1 | `Exterior FP > exterior_context_enabled` | todo el exterior de una vez: sol, ciudad, fachadas, luces de ventana y cúpula | es exterior → seguir con los pasos 2-4 |
| 2 | `exterior_sky_light_cast_shadows` | solo las sombras del sol | sombra del sol (hipótesis ya descartada una vez) |
| 3 | `exterior_window_obstacles_enabled` | edificios de enfrente y sus luces de ventana | recuento de luces omni por objeto |
| 4 | `exterior_own_facade_enabled` / `opposite_facade_enabled` | geometría de fachada casi coplanaria con el muro | z-fighting entre paramentos |
| 5 | `Iluminacion FP > room_ceiling_lights_enabled` | luces de techo de cada sala | luces interiores |
| 6 | `ambient_fill_enabled` | la omni ambiental global | el relleno ambiental |
| 7 | `Materiales FP > use_procedural_surface_noise` y `surface_contact_ao_enabled` | ruido de superficie y oclusión de contacto | material (ya medido sin efecto en banco) |

Si ningún paso lo elimina, no es iluminación: quedan como sospechosos el **z-fighting** entre superficies coincidentes y el orden de las transparencias del overlay 3D, que en primera persona mantiene visible `_atmosphere_root`.

**Tercer fallo de método: la reconstrucción en vivo tumbaba el depurador (2026-09-01).** Al primer intento real de la tabla anterior, el usuario cambió `exterior_sky_light_cast_shadows` y después `room_ceiling_lights_enabled`, y la conexión murió:

```
ERROR: Malformed packet received, not an Array.
ERROR: Remote debugger: Packet too large (1836020852 > 8388612 bytes). Disconnecting.
--- Debugging process stopped ---
```

El tamaño de paquete no es real: es basura leída de un stream ya desincronizado. La causa es que la reconstrucción corría **dentro de la llamada que asigna la propiedad**, y cuando esa llamada viene del inspector remoto quien la ejecuta es el depurador: liberar y recrear cientos de nodos en mitad de su callback le rompe el stream. Corregido aplazando la reconstrucción al final del frame (`_rebuild_if_live()` solo encola; el trabajo vive en `_rebuild_live_deferred()`), lo que además agrupa en una sola reconstrucción todos los interruptores que se toquen en el mismo frame. El guardarraíl `test_live_rebuild_does_not_undo_the_inspector` exige ahora las dos cosas: que el setter solo encole y que el trabajo diferido no reaplique las opciones de arranque.

**Vía alternativa sin depurador.** `FirstPersonController` existe como nodo en `scenes/SimulationScene.tscn`, así que estos interruptores se pueden dejar puestos en la escena y arrancar con F5: una relanzada por paso, pero cero riesgo de desconexión. Dos excepciones, porque `_apply_startup_lighting_options()` los impone desde el escenario en cada arranque: `room_ceiling_lights_enabled` y `exterior_lighting_mode` **no** se pueden fijar así. El primero se gobierna con la casilla de luces interiores del editor de escenarios (`interior_lights_on` en el JSON) y el segundo con el modo día/noche del escenario.

#### Dos hipótesis del usuario sobre el rellano, medidas (2026-09-03)

El usuario propuso mirar dos cosas concretas en el rellano: polígonos generados bajo el suelo, y luz entrando por una ventana de la cocina que se solapa. **Las dos eran ciertas**, y se midieron en vez de deducirlas, con `tools/validate_landing_surfaces.gd`, que monta el mundo FP y busca caras coplanarias y fuentes de luz.

Escenario: el que el usuario tenía cargado según `user://startup_sim_options.json` — `simple_house` forzado a **apartment, planta 1, día, luces interiores encendidas**. Importa: la nota de más arriba de que "el piso patrón no reproduce el fenómeno" se hizo con `simple_house` como unifamiliar, y **en unifamiliar no existe el rellano del portal**.

**1. Polígonos a la cota del suelo del rellano: tres piezas, confirmado.**

| Pieza | Solape con el suelo | Desnivel |
|---|---|---|
| `ExteriorContext/DoorPorch_05` | 1,80 × 1,13 m = **2,04 m²** | **0,0000 m** |
| `LandingStairSide_05_Lower_L` | 0,10 × 2,64 m = 0,26 m² | **0,0000 m** |
| `LandingStairSide_05_Lower_R` | 0,10 × 2,64 m = 0,26 m² | **0,0000 m** |

El grande es el **porche**. `_create_door_entrance()` lo planta a `floor_level_m - floor_thickness_m * 0.5`, que es exactamente la misma cota que usa el suelo del rellano, y se construía **sólo en pisos** (`if _is_apartment_building() or ... HOLE`), que es justo el caso en el que el rellano ya pone su propio solado. Dos losas idénticas, `y −0,100..0,000` las dos, justo delante de la puerta de la vivienda: donde el jugador sale y donde ve el artefacto. El z-buffer no puede decidir cuál está delante y el ganador cambia con el ángulo — formas irregulares que se mueven con la cámara, que es literalmente la descripción del usuario.

Las otras dos son los **costados de la caja de escalera de la planta inferior**. Remataban en `floor_level_m`, o sea en la cara **superior** del forjado en vez de en su intradós, y el costado izquierdo no cae dentro del ojo de la escalera: cruzaba la losa de delante a atrás en una banda de 10 cm. Una línea de sierra, también de la descripción.

Corregido: el porche no se construye donde un rellano ya pone el suelo, y la banda inferior de la caja baja `floor_thickness_m` para rematar contra el intradós, que es además donde apoya de verdad. Tras la corrección **no queda nada compartiendo plano con el suelo del rellano**.

Para saber si hay portal en un trozo de fachada hacía falta una consulta que antes no existía: el rellano se registraba al construir su puerta, así que la respuesta dependía del orden en que se recorren los huecos. Ahora `_collect_landing_footprints()` calcula la huella de cada rellano **antes** de construir nada.

**2. Luz que entra en el rellano: confirmado, pero la cocina no es la culpable principal.**

Aporte medio de cada omni sobre el suelo del rellano, muestreando una rejilla de 6 × 6 en su huella:

| Foco | Aporte | ¿De dónde? |
|---|---|---|
| `LandingAmbientLight_05` | 41,2 % | del propio rellano |
| `FP_AmbientFill` | 16,6 % | **de fuera, a través de la pared** |
| `CityFacadeFill_00` | 15,8 % | **de fuera, a través de la pared** |
| `ExteriorSoftFill` | 12,2 % | **de fuera, a través de la pared** |
| `LandingStairLight_05` | 7,4 % | del propio rellano |
| `CityFacadeFill_02` | 5,0 % | **de fuera, a través de la pared** |
| `WindowDaylight2` (**la ventana de la cocina**) | 1,2 % | **de fuera, a través de la pared** |
| resto (`CityFacadeFill_01`, `LandingLight`, `CeilingLight_4`, `WindowDaylight5`) | 0,6 % | |

**El 51,2 % de la luz del suelo del rellano entra de fuera atravesando las paredes**, porque ninguna de esas omnis proyecta sombra: `room_ceiling_lights_cast_shadows` y `opening_lights_cast_shadows` son `false` por defecto, y los rellenos globales tampoco.

La ventana de la cocina sí entra —su foco está a 0,50 m por fuera de la fachada, a una profundidad que cae dentro del portal y a 0,41 m de su caja— pero aporta **1,2 %**. El grueso son los tres rellenos globales, que suman **44,6 %**. Se deja escrito y **no se toca**: quitar el sombreado de esas omnis fue una decisión de coste, y encenderlo o acotarlas cambia el aspecto de toda la escena, no sólo del rellano.

Lo que sí conviene tener claro para X-8: **una fuga de luz da un brillo constante equivocado, no un parpadeo**. Lo que cambia con el movimiento de la cámara es el z-fighting. De las dos hipótesis, la que explica el síntoma es la primera.

Guardarraíl: `tools/validate_landing_surfaces.gd`, en la suite. Falla si algo comparte plano con el suelo del rellano en más de 0,02 m²; sin las correcciones caza las tres piezas con sus áreas exactas. Imprime además el reparto de luz, que no decide nada pero queda medido.

**Confirmado en ejecución el 2026-09-05.** Esto eliminaba tres superficies coplanarias reales del sitio exacto donde el usuario veía el artefacto, y con el techo y el pasillo corregidos después, el usuario da el suelo del rellano por bueno.

#### El techo del rellano y, sobre todo, la medianera del pasillo (2026-09-03)

Con el suelo del rellano ya limpio, el usuario reportó lo mismo en el techo, y añadió la observación que resultó ser la más importante: *"pasa en las paredes de las habitaciones que dan justo a la pared del pasillo, como si compartieran polígonos"*. Las dos, ciertas.

**Techo del rellano: el fallo espejo del suelo.** Los costados de la caja de escalera de la planta superior arrancaban en `floor_level_m + corridor_height_m`, que es el **intradós** del techo del rellano, así que su cara inferior quedaba en el mismo plano que la cara inferior de la losa: 0,10 × 2,64 m por costado, la misma banda que ya se había corregido abajo. Ahora las dos bandas se apartan el grosor de la losa —la inferior contra el intradós del forjado, la superior contra el trasdós del techo—, que es además donde apoyan de verdad.

**La medianera del pasillo: 13,44 m² de tabique duplicado.** Éste es grande y es general, no del rellano.

Cada sala pide sus cuatro lados, así que una medianera la piden las dos salas que la comparten. El descarte del duplicado (🟠 FP-1, julio) comparaba **la caja entera**: `_wall_box_key(center, size)`. Eso sólo casa cuando las dos salas parten el muro por los mismos sitios — y **un pasillo no lo hace nunca**. Su lado es una tirada continua a lo largo de varias habitaciones, mientras que cada habitación corta en su propio borde y en sus propios huecos. Las cajas salían con longitudes distintas, la comparación no casaba, y el tabique se levantaba dos veces: un sólido dentro de otro, con las dos caras peleándose por cada píxel.

Medido en el piso patrón, los dos planos del pasillo:

| Plano (mundo) | Duplicado |
|---|---|
| `x = −0,050..0,050` (pasillo ↔ salón y cocina) | 3,72 + 2,64 = **6,36 m²** |
| `x = 1,450..1,550` (pasillo ↔ dormitorios y baño) | 2,64 + 1,44 + 1,44 + 1,56 = **7,08 m²** |

Ejemplo concreto del primero: el pasillo levanta un tramo de `z −1,050..1,600`, y enfrente el salón levanta `z −1,050..0,500` y la cocina `z 0,500..1,600`. Los tres ocupan `x −0,050..0,050, y 0..2,400`. **13,44 m² de fábrica duplicada, justo las paredes del pasillo y de las habitaciones que dan a él.**

Corregido generalizando el descarte: en vez de comparar identidad de caja, se lleva por plano de tabique qué trozos ya tienen fábrica —en coordenadas (recorrido a lo largo del muro, altura)— y se levanta sólo el hueco que quede, reutilizando `StairGeometry.split_rect_by_voids`. La comparación de cajas era el caso particular en que el trozo pedido coincide entero con uno ya cubierto. Efecto lateral asumido, que ya venía de FP-1: cuando dos salas comparten muro, cada tramo toma el material de la primera sala por id que lo reclama, así que una medianera larga puede quedar a tramos. Es preferible a que se peleen dos fábricas.

Guardarraíl nuevo en `validate_landing_surfaces`: **dos tabiques no pueden ocupar el mismo sitio.** Compara sólo entre muros paralelos y en el mismo plano, así que dos muros perpendiculares que se cruzan en una esquina —que sí comparten volumen, y es correcto— quedan fuera por construcción. Con el criterio antiguo caza los seis duplicados con sus áreas exactas; desactivando el descarte entero, dieciocho.

El mismo validador aprendió a distinguir **caras que miran hacia el mismo lado** de las que sólo se encuentran: un tabique que apoya bajo un forjado comparte plano con él y eso es como se construye siempre; lo que se pelea por el píxel son dos caras mirando en la misma dirección. Sin esa distinción el guardarraíl marcaba todos los encuentros normales de muro y techo.

Queda apuntado, medido y **sin tocar**, como candidato para la bisección del usuario (paso 4 de la tabla): el plano de fachada acumula 37,83 m² de superficies coincidentes entre `WallMesh`, `ExteriorWallSkin` y `OwnFacade`. Están **enterradas** —la chapa de fachada queda dentro del lienzo de `OwnFacade`, y desde dentro de la vivienda manda la cara interior del muro—, así que no deberían verse; pero es lo que queda en la lista si el artefacto sobrevive a esto.

#### El portal, cerrado y bien plantado en cualquier planta (2026-09-03)

El usuario reportó *"en la zona del rellano, en la escalera, hay un hueco sin tapar; si miro arriba a la derecha parece que entra luz del exterior entre la pared y el techo"*, y pidió que el portal se construya bien **para todas las plantas y para cualquier escenario, de catálogo o dibujado por él**.

**Instrumento nuevo: detector de fugas.** El portal es un recinto cerrado salvo por la puerta de la vivienda y por el ojo de la escalera. Cualquier otra línea recta que salga de él sin tropezar con nada es una rendija. `validate_landing_surfaces` lanza ahora un abanico de rayos desde varios puntos a la altura de los ojos y mide si alguno escapa. Localizó las dos, con coordenadas:

| Fuga | Dónde | Causa |
|---|---|---|
| 7 rayos | `z = 6,805`, `y = 2,48` — fondo del portal, a la altura del techo | el forjado moría en 6,805 y el muro del fondo arrancaba en 6,810 |
| 5 rayos | `x ≈ 2,8..3,2`, `y ≈ 3,2..3,9` — arriba y a la derecha, sobre la caja de escalera | la caja de escalera no tenía cierre **frontal** en las plantas contiguas |

La primera tenía una segunda capa: la franja que quedaba entre el ojo de la escalera y el borde del forjado medía 2,5 cm, y `split_rect_by_voids` descarta por sana costumbre las esquirlas de menos de 8 cm. Esa franja **ni siquiera llegaba a construirse**.

Corregidas las dos, y de raíz: la huella de los forjados se **deriva del propio cerramiento** —cubre el recinto entero, muros incluidos— en vez de quedarse en el hueco libre y confiar en que dos cuentas distintas cuadren; y la caja de escalera se cierra por delante y por detrás en las plantas contiguas, quedando abierta sólo hacia el rellano de la planta actual, que es lo que se quería.

**El portal se plantaba encima de la propia vivienda.** Esto no lo reportó el usuario: lo encontró el barrido al pasar el validador por los cinco pisos de catálogo. En `compact_apartment` la puerta de entrada da a una fachada que tiene el lavadero a un lado y el baño al otro, ambos **más allá del plano de la puerta**, y el portal se plantaba encima de los dos: 1,36 + 1,57 = **2,93 m² de suelo duplicado** y los tabiques de la vivienda cruzando el rellano.

Estrecharlo no sirve: entre el lavadero y el baño quedan 1,40 m, menos que la caja de escalera. Lo que se hace es **apartar el portal hasta librar lo que estorba y unirlo a la puerta con un paso** del ancho del hueco, con su suelo, su techo y sus dos paramentos. Es además lo que ocurre en un edificio real: el núcleo común está donde cabe, y a la puerta de cada vivienda se llega por un pasillo. En una planta rectangular la separación es cero y no se construye ningún paso, así que los escenarios que ya iban bien no cambian.

**Sobre "dejar fijos los parámetros".** La regla del proyecto es que todo lo gobernable desde el editor se gobierne desde el editor, así que la respuesta no es congelar mandos sino que la construcción **se derive de ellos** y el guardarraíl lo imponga. El validador barre ahora siete configuraciones:

- los cinco pisos de catálogo, en plantas 1, 1, 3, 5 y 2;
- `compact_apartment` con `wall_thickness_m = 0,22` y `landing_recess_depth_m = 1,80`;
- `simple_house` con `floor_thickness_m = 0,24`, `ceiling_thickness_m = 0,18` y `landing_neighbor_doors = 4`.

Los dos últimos están precisamente para que la estanqueidad no dependa de que nadie toque un valor por defecto, que es la misma garantía que necesitan los pisos que dibuje el usuario. En los siete se comprueba: nada comparte plano con el suelo ni con el techo del portal, ningún tabique está duplicado, y ningún rayo escapa del cerramiento.

Coste: 8,6 s para los siete casos. El detector no busca el sólido más cercano, sólo si algo para el rayo, y sale en cuanto lo encuentra; sin eso no cabía en el tiempo que la suite da a una escena.

#### Cierre de X-8 (2026-09-05)

El usuario confirma en ejecución: **el suelo del rellano, el techo del rellano y los pasillos de la vivienda quedaron arreglados**, y describe la causa en sus propios términos — *«se superponía la capa trasera con la delantera»*—, que es exactamente el z-fighting entre superficies coincidentes. Los tres commits que lo cierran ya están en `origin/main`:

| Commit | Qué quitó |
|---|---|
| `cbadf310` | tres superficies coplanarias con el suelo del rellano — el porche de entrada (**2,04 m² a 0,0000 m de desnivel**, justo delante de la puerta) y los dos costados de la caja de escalera inferior |
| `1909339b` | **13,44 m²** de tabique duplicado entre el pasillo y las habitaciones que dan a él |
| `e6712cb7` | el fallo espejo en el techo del rellano, más el sellado del portal y su replanteo en cualquier planta |

**Lo que validó el diagnóstico** fue la distinción de §12b: una fuga de luz da un brillo constante equivocado, no un parpadeo; lo que cambia al mover la cámara es el z-fighting. De las dos hipótesis medidas, se siguió la que explicaba el síntoma y no la más llamativa — el 51,2 % de luz que entra atravesando paredes, que sigue ahí, medido y sin tocar, sin ser la causa de nada de esto.

**La bisección de §5 del handoff no llegó a hacer falta** y se conserva sólo como registro de método. Con ella caducan también sus dos sospechosos de reserva: los 37,83 m² coincidentes del plano de fachada (`WallMesh` / `ExteriorWallSkin` / `OwnFacade`) siguen medidos, enterrados y **sin tocar**, y el orden de transparencias del overlay 3D nunca llegó a examinarse. Ninguno de los dos tiene ya síntoma que lo respalde.

Lo que impide que vuelva no es el arreglo, son los guardarraíles: `validate_landing_surfaces` falla si algo comparte plano con el suelo o el techo del portal en más de 0,02 m², si dos tabiques ocupan el mismo sitio o si algún rayo escapa del cerramiento, y barre siete configuraciones — cinco pisos de catálogo en plantas distintas y dos con los mandos cambiados a propósito.

---

## 13. Estado final de la línea visual (2026-08-31)

Cierre de la ejecución del plan §12. Todo lo que sigue está verificado con `python scripts/check_product.py` (30 suites en verde; el único fallo es `test_exit0_real_json`, de la línea motor) y, donde tiene sentido, con capturas renderizadas y medidas.

### 13.1 Inventario completo

| Hallazgo | Sev. | Estado |
|---|---|---|
| H-1 puente de humo sin cara inferior | 🔴 | Corregido (28-ago) |
| H-2 el humo no llenaba la puerta | 🔴 | Corregido (28-ago) |
| H-3 losa de humo cortada en el dintel | 🔴 | Corregido (28-ago) |
| H-4 contracorriente apagada | 🟠 | Cerrado — bug del enganche corregido; función apagada por decisión |
| H-5 la cortina ignora la hoja | 🟠 | Corregido |
| H-6 autoexposición entre plantas | 🟡 | Mejora futura declarada, no fallo |
| H-7 penacho vertical con una sola sala | 🟡 | **No reproducible**; salvaguarda puesta |
| H-8 `smoke_local_y` y `meters_to_units` | ℹ️ | Corregido |
| E-1 sin envolvente exterior | 🔴 | Corregido (28-ago) |
| E-2 cota de calle por fachada | 🟠 | Corregido (28-ago) |
| E-3 vierteaguas en código muerto | 🟠 | Corregido (28-ago) |
| E-4 rendija perimetral entre plantas | 🟠 | Corregido |
| E-5 decorado urbano tras el rellano | 🟠 | Corregido |
| E-6 cara exterior con material interior | 🟡 | Corregido |
| R-1 rellano sin luz propia | 🔴 | Corregido (28-ago) |
| R-2 un portal por puerta exterior | 🟠 | Corregido (28-ago) |
| R-3 acabado del rellano | 🟠 | Corregido (rodapié 28-ago; suelo con despiece 31-ago) |
| R-4 altura del portal fija | 🟡 | Corregido |
| R-5 transición porche/césped | 🟡 | Corregido |
| R-7 frente del rellano abierto | 🔴 | Corregido (29-ago) |
| R-8 paredes del rellano sin colisión | 🟡 | Corregido |
| V3-1 pila alfa sin `render_priority` | 🟠 | Corregido |
| V3-2 la captura incluye el HUD | 🟠 | Corregido |
| V3-3 picking contra y=0 | 🟡 | Corregido |
| V3-4 selección por distancia al origen | 🟡 | Corregido |
| V2-1 transformada de dibujo duplicada | 🟡 | Corregido |
| V2-2 fondo 2D fijo | 🟡 | **No reproducible** |
| V2-3 escala de color SVV | 🟡 | **No reproducible** |
| M-1 materiales planos sin mapas | 🟠 | Corregido |
| M-2 sin oclusión ambiental | 🟠 | Corregido |
| M-3 materiales duplicados | 🟡 | Corregido |
| FP-1 medianeras coincidentes | 🟠 | Corregido |
| FP-2 interior sin textura | 🟠 | Corregido |
| FP-3 geometría FP/3D duplicada | 🟠 | Corregido (2026-09-03, con guardarraíl de paridad) |
| FP-4 consultas repetidas por frame | 🟡 | **No reproducible** |
| FP-6 sala con humo y sin fuego a negro | 🟠 | Corregido |
| FP-7 humo entre salas ausente en FP | ℹ️ | **Hallazgo erróneo**, era mío |
| FP-8 nodos homónimos sin nombre | 🟡 | Corregido |

**Balance:** de los 26 hallazgos abiertos cuando se escribió el plan, **23 cerrados**, **ninguno sigue abierto**, **1 es mejora futura** (H-6) y **4 resultaron no reproducibles** (H-7, V2-2, V2-3, FP-4). Aparecieron dos nuevos durante la ejecución: FP-8 (cerrado) y el contrato falso de `with_collision` en `_add_box` (cerrado con R-8).

### 13.2 Lo que enseña la tanda de "no reproducibles"

Cinco descripciones del informe no se sostuvieron al ejecutarlas, más una mía. No es casualidad: **la auditoría original se escribió sin poder abrir Godot** (§11), leyendo código, y cuatro de sus hallazgos describían versiones anteriores de funciones que ya se habían corregido. El sexto —FP-7— lo escribí yo deduciendo de una ausencia de referencias en un fichero, sin comprobar cómo se monta la escena en `Main`.

La regla que sale de aquí, y que ya está en §12.0: **ningún hallazgo se marca corregido sin guardarraíl o captura, y ninguno se da por cierto sin reproducirlo antes de tocar el código**. Reproducir primero habría ahorrado la mitad del trabajo de investigación de esta sesión.

Y un segundo aprendizaje, de H-4: **medir con contadores, no con muestreo**. Un primer diagnóstico de la contracorriente se hizo mirando unas pocas líneas de traza y llevó a la conclusión equivocada de que la cortina se dibujaba muy tenue; con contadores sobre toda la corrida quedó claro que no se dibujaba **ninguna** vez. Un `head` sobre una traza ordenada no es una muestra representativa.

### 13.3 Todo el aspecto se gobierna desde el editor

Ningún valor que decida cómo se ve la escena vive ya sólo en el código. Grupos nuevos o ampliados en el inspector:

| Nodo | Grupo | Qué gobierna |
|---|---|---|
| `FirstPersonController` | Materiales FP | Ruido de superficie (contraste, tamaño en metros, resolución, octavas, factores del perfil de suelo), rugosidad, baldosa del rellano (lado, junta, resolución), oclusión de contacto (activación, fuerza, ancho de la franja, nitidez triplanar) |
| `FirstPersonController` | Materiales propios FP | Ranuras de recurso para material de muro, suelo, techo y fachada, y para las texturas de superficie, de suelo y de baldosa. Vacío = generación procedural; con recurso, manda el recurso |
| `FirstPersonController` | Iluminación FP | Suelo del alcance de la luz de techo con humo (FP-6) |
| `FirstPersonController` | Exterior / Rellano | Sellado entre plantas, chapa de fachada, decorado urbano tras el rellano, altura del portal derivada, bordillo y grava del porche |
| `Visualizer3D` | Orden de transparencias | Prioridad de dibujado de las nueve capas translúcidas |
| `Visualizer3D` | Captura técnica | Viewport limpio, tamaño de la captura, fondo transparente |
| `Visualizer3D` | Humo en aperturas | Seguimiento de la hoja, ancho mínimo, exponente de opacidad, tope de la contracorriente, calibración de la cortina y del penacho en 3D y en primera persona, alto del penacho exterior |
| `Visualizer3D` | Interacción | Radio de selección de marcadores y de muebles, margen de silueta, holgura de "sobre el modelo" |
| `tools/capture_visual_reference` | Todos | Destino, prefijo, qué pasadas capturar, las vistas (editables como `Array[Dictionary]`), centro del plano, reposo, iluminación y estado de incendio del piso patrón |

`tests/test_godot_editability.py` (13 pruebas) falla si cualquiera de esos mandos vuelve al código.

**Criterio del barrido.** Sale al inspector todo lo que decide *cómo se ve o cómo se comporta* la escena: colores, tamaños en metros, opacidades, prioridades de dibujado, umbrales de interacción y el plano neutro del vano, que es el parámetro central de H-2. No salen las curvas de respuesta internas de los shaders de humo —los coeficientes de `density`, `flow_strength` o `turbulence`, del tipo `0.44 + alpha * 1.15`—: son la forma de una función, no un ajuste, y exponerlas llenaría el inspector de mandos que nadie puede calibrar a ojo. Queda dicho para que sea una decisión y no un olvido; si alguna hiciera falta, se saca igual que las demás.

### 13.4 Guardarraíles nuevos

Cinco validadores headless nuevos y dos ampliados, todos verificados fallando con el comportamiento anterior:

| Guardarraíl | Fija |
|---|---|
| `validate_fp_smoke_lighting` | FP-6: con humo y sin fuego la luz se atenúa pero no se recorta el alcance |
| `validate_fp_party_walls` | FP-1 (sin medianeras duplicadas, rodapié por sala) y FP-8 (ninguna malla anónima) |
| `validate_fp_interstitial_seal` | E-4: sin holgura vertical entre el techo de una planta y el forjado de la siguiente |
| `validate_fp_surface_shading` | M-2: cada malla publica **su** tamaño por instancia, que es lo que mide la franja de oclusión en metros |
| `validate_3d_smoke_opening_curtain` | H-5: la cortina sigue al hueco libre y se desplaza al lado de la cerradura |
| `validate_fp_landing_stairs` (ampliado) | R-8: toda pared del rellano tiene cuerpo estático |
| `validate_view_geometry_parity` | FP-3: las dos vistas reparten la misma geometría (losas del hueco de escalera, troceado por hueco vertical, colocación de cada hueco en su paramento) |
| `capture_visual_reference` | Instrumental de comparación antes/después, 20 vistas |

### 13.5 Lo que queda

1. **H-6** — autoexposición entre plantas. Funcionalidad nueva, declarada fuera del cierre.
2. ~~Confirmar en ejecución las correcciones de §12b~~ — **hecho el 2026-09-05**: el usuario da por arreglados el suelo del rellano, el techo del rellano y los pasillos. **X-8 cerrada**; la causa era superposición de superficies, no iluminación. La bisección de [HANDOFF_VISUAL_X8_2026-09-01.md](HANDOFF_VISUAL_X8_2026-09-01.md) no llegó a hacer falta y queda como registro de método.

3. 🔴 **MOB-1** — el mobiliario sigue sin ser creíble. **ABIERTO**, ver §14.
4. 🟠 **EXT-1** — el exterior que se ve por la ventana. **ENTREGADO sin pulir**, ver §15.

Con FP-3 y X-8 cerradas no queda ningún hallazgo de §1-§8 ni de la serie X. Sigue en pie H-6 (autoexposición entre plantas), que es funcionalidad nueva declarada fuera del cierre, **MOB-1**, y un cabo suelto sin ficha: la sala casi negra de la grabación de las 00:38.

---

## 14. 🔴 MOB-1. El mobiliario sigue sin ser creíble — **[ABIERTO]**

**Estado: NO corregido.** Se trabajó sobre ello el 2026-09-06 (commits `5f4fe75`,
`2fadc1f`, `4046c6d`) y el usuario, al ejecutarlo, lo rechaza:

> *"siguen muebles sin sentido. cosas que no parecen muebles en medio del
> pasillo y muebles en sitios que no corresponden"*

Se paró ahí por decisión suya, para seguir con otra cosa. Esto queda abierto.

### 14.1 Lo que sí quedó arreglado, y está medido

No hay que rehacerlo, pero tampoco basta:

- El **tamaño**. Los modelos de `assets/fp/furniture` no vienen a escala real
  (una cama mide 0,96 × 1,13 × 0,38 m en el fichero) y se escalaban para que su
  superficie coincidiera con `size_m`, que es la huella del modelo de **fuego**.
  Daba una encimera de 3,15 m convertida en un cubo de 1,46 y camas de 1,52 m de
  largo. Las medidas reales están en `view/furniture/FurnitureDimensions.gd`.
- **Solapes y salidas de sala**: 11 pares de piezas superpuestas → 0; 2 piezas
  fuera de su sala → 0; 1 atravesando el techo → 0.
- Dos errores de identidad por coincidencia de letras: la **mesilla** salía
  dibujada como una **silla** ("mesilla" contiene "silla") y las **cortinas**
  como una **bañera** ("cortinas" contiene "tina").
- Las cuatro vistas reparten igual (FP, maqueta 3D, plano 2D y minimapa).

### 14.2 Por qué los guardarraíles pasan y aun así se ve mal

Es la lección que importa para quien lo retome. `tools/validate_furniture_layout.gd`
mide **geometría**: que nada se salga de la sala, que nada se pise, que las
piezas de paramento estén contra un paramento, que las alturas sean las del
mueble real. Las 319 piezas del catálogo pasan todo eso.

**Nada de eso comprueba que una pieza tenga sentido donde está.** Un montón de
cajas perfectamente colocado contra la pared del pasillo cumple las seis reglas
y sigue siendo un objeto que no pinta nada ahí. El guardarraíl no sabe distinguir
"colocado sin solaparse" de "colocado con criterio", y esa distinción es justo
la que pedía el usuario.

### 14.3 Sospechosos, sin verificar

Ninguno está comprobado contra lo que el usuario ve; son los puntos por donde
empezar a mirar.

1. **"Cosas que no parecen muebles"** apunta a los arquetipos genéricos:
   `clutter`, `containers` y `textile_pile` son montones y bultos, no muebles, y
   `clutter` es además el **fallback** del clasificador — todo lo que no
   reconoce acaba siendo un montón de bultos. En el pasillo del piso patrón hay
   un `pasillo_caja` que viene del escenario, y el atrezo de pasillo pone
   alfombra, consola y planta. Conviene mirar en ejecución cuál de esos es el
   que se ve mal.
2. **"Muebles en sitios que no corresponden"** apunta a la regla de elección de
   paramento de `FurnitureRoomLayout._place_against_wall`: elige el muro **más
   cercano** a donde el escenario puso la pieza. Cuando la ficha del escenario
   trae una posición pensada para el modelo de fuego y no para la vista, "el más
   cercano" puede ser cualquiera. Y en el atrezo, las pistas de posición de
   `FurnitureRoomFurnisher` son fracciones del rectángulo de la sala, sin
   ninguna noción de qué pared es la buena (la que no tiene la puerta, la que da
   a la ventana, la que enfrenta al sofá).
3. **Falta la relación entre piezas.** Una mesilla va **junto a la cama**, la
   mesa de centro **delante del sofá**, la silla **contra el escritorio**, el
   televisor **enfrente** del sofá. Hoy cada pieza se coloca por su cuenta y
   solo se comprueba que no se toquen; nada las relaciona.
4. **Falta el criterio de "esta sala no lleva esto".** El atrezo se decide por
   tipo de sala y área, y el reparto del escenario no filtra nada.

### 14.4 Cómo retomarlo

Con síntomas visuales, la nota de método que ya se ganó dos veces en esta
auditoría: **pedir al usuario que señale sobre su propio fotograma** resuelve en
un mensaje lo que tres rondas de deducción no resuelven. Antes de tocar código,
conviene una captura del pasillo señalando qué objeto es el que no parece un
mueble y qué pieza está donde no toca.

Instrumental disponible: `tools/validate_furniture_layout.gd` con `VERBOSE = true`
vuelca las 319 piezas medidas con su arquetipo y sus dimensiones, y
`tools/probe_furniture_assets.gd` mide el tamaño nativo de cada modelo.

---

## 15. 🟠 EXT-1. El exterior por la ventana — **[ENTREGADO sin pulir]**

El usuario lo abrió así: *"por la ventana se ven calles que terminan en nada y
pocos edificios y mobiliario urbano"* y *"falta un cielo realista"*. Después,
sobre la primera pasada: *"las carreteras del exterior se cruzan sin ningún
sentido, no tienen continuidad"*. Y sobre la segunda: **"no está bien del todo
pero lo vamos a dejar. está mejorado"**.

Queda ahí: mejorado y sin cerrar, por decisión suya.

### 15.1 El defecto de fondo, y por qué costó dos pasadas

**Cada fachada montaba su propio exterior completo.** Una calzada de 46 m, dos
aceras y dos bordillos, orientados según esa fachada. Con dos o tres fachadas
eso son dos o tres calles enteras superpuestas: las aceras de una cruzaban la
calzada de otra, los bordillos partían los cruces por la mitad y las marcas de
carril seguían de largo por dentro de la intersección. En unifamiliar, lo mismo
con tres jardines, tres caminos de entrada y tres accesos de coche, uno de ellos
al jardín de atrás.

Y encima, cada decorado se anclaba en el **centro de las ventanas** de su
fachada, no en el muro: como cada fachada tiene las suyas donde le toca, cada
calle quedaba a una distancia distinta del edificio, así que no podían cerrar
por las esquinas ni aunque no se cruzaran.

La primera pasada no lo vio: se dedicó a poblar la calle -manzanas hasta los
extremos, retornos de esquina, mobiliario urbano- sobre una estructura que
estaba mal. Añadir cosas a un decorado que se cruza consigo mismo lo empeora.

**La regla que salió de aquí**: una calle no se construye por fachadas, se
construye por manzana. `view/fp/FPStreetGrid.gd` la calcula una vez, en anillos
concéntricos que no se solapan: acera, calzada y acera de enfrente en un piso;
jardín, acera, calle, acera y jardín de enfrente en una casa. Donde dos brazos
se encuentran no hay que hacer nada especial: la esquina ya es parte del anillo,
y eso es exactamente lo que es un cruce.

### 15.2 Lo que quedó hecho y medido

- **La calle es una.** De tres losas de calzada de 46 m cruzándose a un anillo
  de cuatro brazos. Marcas de carril cortadas antes del cruce, bordillos solo
  en los tramos rectos, pasos de cebra por fuera del cruce.
- **La calle no termina en nada.** Antes: calzada de 46 m con 34 m de fachadas
  al lado. Ahora lo edificado cubre el largo de cada brazo, con manzanas hasta
  los extremos, bocacalles, retornos de esquina y una fila de volúmenes detrás.
- **Mobiliario urbano**, que era cero: farolas, señales, papeleras, bancos,
  bolardos, alcorques, paso de cebra, marquesina, bajos comerciales con toldo y
  balcones.
- **El cielo**: bruma de horizonte, nubes procedurales en dos capas que derivan,
  sol con disco, halo y resplandor, y estrellas de noche.
- **Unifamiliar**: un jardín, un camino de entrada, un acceso de coche y un
  buzón —los tres últimos van con la puerta, que es una—, valla de parcela con
  hueco de cancela, y el porche que ya existía gana luz de verdad (el aplique
  estaba pintado de color pero no alumbraba) y barandilla.

### 15.3 Guardarraíles

`tools/validate_exterior_city.gd`, en la suite, sobre cinco escenarios -tres
pisos y dos casas-: dos tramos de calzada no pueden pisarse, una acera no puede
estar sobre el asfalto, lo edificado tiene que llegar hasta donde llega el
asfalto, nada puede cruzar la calzada, y tiene que haber mobiliario. Usa el
mismo umbral que el filtro de construcción a propósito: con otra manga cazaría
justo lo que el filtro deja pasar.

Dos guardarraíles viejos hubo que corregirlos porque **codificaban el diseño
equivocado**: `validate_fp_exterior_context` exigía "dos bordillos por
orientación de fachada" y "una calle y un camino de entrada", que es justo lo
que fallaba. Un test puede fijar un error tan bien como fija un acierto.

### 15.4 Dos intentos fallidos de lo mismo, y por qué

Merecen quedar escritos porque el error fue de planteamiento, no de código, y se
repitió.

Al cerrar los lados de la manzana sin fachada hice primero una **tapia corrida
alrededor de todo el vecindario**: la puse en los cuatro lados y a la distancia
de la acera de enfrente. En un piso eso queda detrás de las fachadas y no se ve
—que es el caso con el que lo comprobé—, pero en una casa las viviendas del
vecino están más lejos, porque hay un jardín delantero por medio: el relleno
caía delante de ellas y las tapaba.

Al corregirlo, lo **troceé en cuerpos del tamaño de una vivienda** dando por
hecho que a esa distancia bastaría con la silueta. No basta: sin cubierta, sin
puerta y sin ventanas, una caja del tamaño de una casa se lee como un cubo.

Las dos veces el error fue el mismo: tratarlo como *tapar un hueco* en vez de
por lo que es —**ahí también hay vecinos**—. Lo que funcionó fue extraer la fila
de casas a una función y pedirla desde los dos sitios que la necesitan: la
fachada que da a esa calle, y el lado que no tiene fachada.

### 15.5 Estado final

El usuario lo cierra así: **"no es perfecto pero vale"**. Queda entregado y sin
pulir, por decisión suya.

Si se retoma, la nota de método de esta auditoría, que ya se ganó tres veces:
**pedir una captura señalando qué es lo que canta** antes de tocar código.

Sonda: `tools/probe_exterior_city.gd` vuelca el recuento por familia y la
extensión de cada cosa, para día y noche.
