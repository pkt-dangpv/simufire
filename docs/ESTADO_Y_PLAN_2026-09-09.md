# SimuFire — estado y plan de trabajo

**Fecha:** 2026-09-09 · **HEAD:** 08dc041 · **Godot:** 4.7.1 · **Renderer:** `gl_compatibility`
**Estado:** auditoría cerrada · plan en marcha · **fase 0 completa** (G-3, los dos
prompts al motor y N-6·N-7) · **fases 1 y 3 completas** · **fase 2: parte visual hecha, falta el motor**

Documento conjunto. La **parte I** es la auditoría del estado actual del diseñador de
niveles y del aparato gráfico: once hallazgos, todos medidos o mirados hoy sobre el
árbol actual —cuando un hallazgo viene de una captura, la captura está tomada con
ventana real; cuando viene de una cifra, la cifra se ha vuelto a correr—. La **parte
II** son las siete peticiones nuevas, y para cada una se ha mirado antes qué hay ya en
el código, porque tres están a medio construir y una —el viento— ya está implementada
en el motor y solo le falta la interfaz. La **parte III** junta las dieciocho tareas en
un orden y en siete decisiones pendientes.

Queda fuera, por decisión tuya, el diseño de contenido de los escenarios: qué mueble va
en qué sala sigue en MOB-1, §14 de `AUDITORIA_VISUAL_2026-08-29.md`.

---

# Parte I · El estado, medido

## 1. Resumen

El **diseñador** está mucho mejor de lo que su documentación refleja y peor de lo
que su estructura aguanta: se ve profesional, tiene 11 guardarraíles y 8 sondas
propias, y en dos días ha ganado 3D en vivo, dibujo directo en 3D, catálogo de
mobiliario y revisión previa. El precio es que el monolito que se partió el día 7
volvió a crecer el día 8, y que el catálogo de objetos deja fuera el baño y la
cocina enteros.

El **aparato gráfico** tiene la arquitectura resuelta —el rellano es la mejor
vista del conjunto, y no por casualidad: es todo geometría propia— y el
mobiliario y el exterior sin resolver. El hallazgo que más cambia lo que viene:
**121 de los 140 modelos que ya están en el repo no se pueden dibujar**, y
ninguno de los 140 tiene textura.

| | diseñador | gráfico |
|---|---|---|
| suite | 42 OK, 1 FAIL conocido (R2-1, motor) | ídem |
| guardarraíles | 11 | 27 |
| sondas | 8 | 9 |
| hallazgos abiertos | 6 (2 rojos) | 5 (2 rojos) |

---

## 2. El diseñador de niveles

### 2.1 Lo que está sólido

- **13 herramientas** (selección, sala, pasillo en L, escalera, puerta, hueco,
  ventana, objeto, ignición, inicio FP, borrar, detector, víctima), todas con
  icono, texto entero, tooltip, unidad y foco de teclado. Lo impone
  `validate_editor_ui_affordances.gd` con 9 reglas.
- **Tres modos de trabajo** —2D, 3D y FP— y desde el día 8 se **dibuja
  directamente en 3D**, no solo se mira.
- **3D en vivo** en un panel movible y redimensionable, que sigue al ratón
  mientras se arrastra.
- **Plantas**: crear vacía o como copia de la actual, fantasma de la de abajo
  para alinear, escaleras que encadenan planta a planta y por las que el humo
  sube de verdad (`validate_editor_stairs_climbable.gd`).
- **Revisión del escenario antes de arrancar** (`ScenarioReview.gd`).
- **Panel de propiedades completo y con unidades**: X, Y, ancho, fondo, ángulo,
  altura de techo, carga de fuego (MJ) y HRR máximo (kW).
- **La UI está 100 % en escena**, con guardarraíl permanente que falla si un
  control se cuela por código.
- **Aspecto**: tema oscuro propio, marca, acento rojo, iconos en todo. Mirado hoy
  en captura: se ve profesional.

### 2.2 Hallazgos

#### 🔴 D-1. El monolito volvió, y por acumulación

`editor/ScenarioEditor.gd` está en **7990 líneas**. E-12 lo había dejado en 6871
el 7 de septiembre. Doce commits de función el día 8 lo devolvieron a donde
estaba:

```
6871  09-07  refactor: el arrastre gana un nombre     <- fin de E-12
7089  09-08  perf: cada vista rehace solo su mundo
7213  09-08  feat: el plano en 3D mientras lo dibujas
7496  09-08  feat: dibujar los muros en 3D
7900  09-08  feat: el mobiliario se coge del catálogo
7990  09-08  fix: coger una herramienta cuadra la vista
```

Pero **la forma del fichero no es la que sugiere "monolito"**: solo 2 funciones
pasan de 100 líneas. Son **408 funciones y 155 variables de estado en una sola
clase**. El problema es de anchura, no de longitud, y por eso partirlo por
"funciones largas" no habría servido.

Los dos bloques que piden módulo son justo los que llegaron después del corte:

| tema | funciones | líneas |
|---|---|---|
| objetos / mobiliario | 40 | 708 |
| 3D en vivo | 38 | 734 |
| salas | 34 | 568 |
| aperturas | 20 | 499 |
| plantas | 26 | 479 |

#### 🔴 D-2. El catálogo del editor cubre 14 de 38 arquetipos

`ObjectLibrary.get_object_kinds()` ofrece 14 objetos. Hay 38 arquetipos con
modelo. **No se puede colocar desde el diseñador**:

```
bathroom_cabinet, bathtub, bed_bunk, bed_single, bench, chair, chair_desk,
clutter, dryer, kitchen_fridge, kitchen_sink, kitchen_stove, lamp_floor,
lamp_table, lounge_sofa_long, plant, pool, shower, side_table, sink,
storage, textile_pile, toilet, washer
```

O sea: **un baño y una cocina no se pueden amueblar desde el editor**. Ni una
silla, ni una lámpara, ni una planta, ni una mesilla. Quien diseña un nivel tiene
que conformarse con sofá, sillón, cama, mesa, mesa de centro, escritorio,
cortina, armario, librería, cómoda, mueble de TV, alfombra, encimera y cubo.

#### 🟠 D-3. La ficha de la sala queda enterrada bajo los muebles

Confirmado en la captura y en el código. `EditorDraw2D.plan()` pinta en este
orden: fantasma → **salas** → aperturas → **objetos** → inicio FP → detectores →
víctimas. El nombre, las medidas y la superficie de cada sala se escriben a
desplazamientos **fijos** desde su esquina superior izquierda (+8/+18, +8/+32,
+8/+46 px) y no esquivan nada. Cualquier mueble que caiga en esa esquina se pinta
encima.

En la foto del plano, el sofá tapa `4.20 × 3.4?` y `38.5? m³` del Salón, y el
rótulo `Escalera PB` pelea con las guías y el cartel `ENTRA` de la propia
escalera. Es justo la información que uno mira mientras dibuja.

#### 🟠 D-4. El 3D en vivo tiene poco margen

Medido hoy con `probe_editor_3d_cost.gd` sobre el piso de referencia (5 salas, 7
aperturas, 10 objetos):

```
rehacer la malla 3D      74.1 ms      rehacer la vista: media 13.5 ms
rehacer el mundo FP      75.8 ms      un fotograma a 60 Hz: 16.7 ms
sin muebles ni adornos    9.4 ms      recolocar sin rehacer: 10.2 ms
```

Cabe en un fotograma **para el piso patrón**. Pero el coste crece con el tamaño:

```
 1 sala    1.6 ms       0 objetos/sala    5.0 ms
 2 salas   2.7 ms       1 objeto/sala     9.3 ms
 4 salas   5.4 ms       3 objetos/sala   14.7 ms
 8 salas   9.2 ms       6 objetos/sala   20.6 ms
16 salas  18.2 ms  <- ya no cabe en el fotograma
```

Unos **1,15 ms por sala** y **0,65 ms por objeto**. Un edificio de 16 salas
amuebladas se sale del presupuesto arrastrando. La estrategia está dimensionada
para el piso de referencia, no para lo que el editor deja construir.

> **Corregido el 2026-09-09, al ejecutar la fase 0.** La cifra absoluta no aguanta
> la precisión que le di. Cuatro pasadas de `probe_editor_3d_cost` sobre **la misma
> configuración** dieron 17,5 · 21,9 · 23,6 · 25,4 ms, y esta misma mañana la misma
> sonda dio 13,5 ms: **casi 8 ms de dispersión**, más que el efecto que se pretendía
> medir. Lo que sigue valiendo es la *forma* —el coste crece con las salas y con los
> objetos, porque esa comparación es dentro de una misma pasada— y lo que no vale es
> el «cabe / no cabe en el fotograma», que salió de una sola pasada. Para decidir
> sobre el margen hace falta antes arreglar la sonda: esto es D-6 otra vez, y de
> paso rebaja a D-4 de hallazgo medido a sospecha fundada.

#### 🟠 D-5. La documentación del editor se quedó en el día 7

`AUDITORIA_EDITOR_2026-09-06.md` acaba en el §16 (E-12, sexto corte, 09-07).
Desde entonces hay **14 commits** sobre `editor/` y `view/`. Menciones en el
documento: *3D en vivo* 0, *revisión* 0, *catálogo* 0, *dibujar en 3D* 0, *copia
de la planta* 0. Lo que el editor hace hoy no está escrito en ninguna parte
salvo en los mensajes de commit.

#### 🟡 D-6. Las sondas de captura no reproducen el camino real

`capture_editor_plan.gd` monta el escenario inyectando `editor_data` a mano —que
es lo correcto para fotografiar un arrastre sin ratón— pero **no pasa por
`_sync_floor_controls()`**. Resultado: todas las fotos salen con `Salas: 0` con
tres salas dibujadas, y con el mensaje de estado de otra acción ("Seleccionada
apertura 0") mientras se arrastra una sala.

Estuve a punto de dar el contador por roto. No lo está: al cargar un escenario de
verdad, `_load_from_path()` sí llama a `_sync_floor_controls()`. **Una sonda que
miente en un detalle obliga a verificar todo lo que enseña**, que es justo lo
contrario de para lo que está.

---

## 3. El aparato gráfico

### 3.1 Lo que está sólido

Mirado hoy en 20 vistas de referencia (piso patrón, limpio y en incendio, más la
maqueta):

- **La arquitectura interior se sostiene**: rodapié, jambas, puertas de
  cuarterones con manilla, ventanas con carpintería, montante y vierteaguas,
  luminaria de techo, suelo con juntas, zócalo de pasillo.
- **El rellano es la mejor vista del conjunto**: peldañeado con huella y
  contrahuella, barandilla con balaustres y pasamanos, dos puertas con marco,
  aplique encendido. Se lee como un portal español de verdad.
- **El cielo**: degradado, nubes y bruma en `fp_sky_dome.gdshader`.
- **6 shaders propios** (llama, tapa de techo, humo volumétrico, máscara de
  techo, cielo, superficies) y **4 presets FP** en `.tres`.
- **731 mandos `@export`**, con niebla real de cámara (Koschmieder) y ranuras de
  material y textura para sustituir lo procedural sin tocar código.
- **27 guardarraíles visuales**, incluida la paridad de geometría entre las dos
  vistas y el barrido de superficies del rellano.

### 3.2 Hallazgos

#### 🔴 G-1. 121 de los 140 modelos del repo no se pueden dibujar

En `assets/fp/furniture/gltfs/` hay **140 modelos `.glb`**. Con envoltorio
`.tscn` —lo único que el juego sabe cargar— hay **37**. Los otros 121 están en el
repositorio y no se pueden usar. Entre ellos:

- **Cocina**: microondas, cafetera, tostadora, batidora, campana (2), muebles
  altos (5), armarios bajos y de esquina, frigoríficos (3), vitrocerámica,
  barra y taburetes.
- **Salón**: tres televisores, sofá rinconera (2), sofá con chaise, sillón de
  descanso, mesas de centro (5), mesa redonda, mesa de cristal.
- **Baño**: espejo, mueble con cajones, lavabo cuadrado, inodoro cuadrado,
  ducha redonda.
- **Y además**: cama doble, cuatro plantas, seis alfombras, cojines, libros,
  perchero (2), ventilador de techo, papelera, ordenador (pantalla, teclado,
  ratón), portátil, radio, altavoces.

La sesión anterior iba camino de **comprar assets**. El kit que ya está en el
repositorio cubre casi todo lo que se echaba en falta; lo que falta no son
modelos, son 121 ficheros `.tscn` de tres líneas y sus ramas en el clasificador.

> Corrige lo que dije hoy mismo al cerrar el mueble de baño: **sí hay modelo de
> espejo** (`bathroomMirror.glb`), solo que sin envolver. De toallero no hay.

#### 🔴 G-2. Ningún mueble tiene textura

Medido sobre los materiales construidos, no sobre el fichero: el sofá sale con 2
superficies y la cama con 7, y **las nueve tienen `albedo_texture = null`**. No
hay una sola imagen en `assets/fp`, ni suelta ni embebida en los `.glb` (140
modelos en 2,9 MB: no caben texturas ahí).

El sofá del salón es literalmente el color plano `(0.97, 0.64, 0.62)`. Por eso se
lee como plástico salmón, y por eso la forma —que es correcta: tiene brazos,
respaldo, cojines y patas— no salva la credibilidad.

**Esto reencuadra MOB-1**: una parte de "los muebles no son creíbles" no es
colocación ni criterio, es que **no tienen material**.

#### 🟠 G-3. El borde de sombra sale dentado

Visible en la mancha de sol sobre la cama del dormitorio. Las tres causas están
en la configuración, y las tres son un valor:

```
project.godot   lights_and_shadows/directional_shadow/soft_shadow_filter_quality = 0
project.godot   (no hay ninguna clave msaa)          -> antialiasing desactivado
FirstPerson     exterior_sky_shadow_blur: float = 0.0
```

Sombra dura, sin filtro y sin antialiasing, en un renderer `gl_compatibility` que
además no ofrece TAA ni FSR. El mando para suavizar **ya existe** y está a cero.

> **Ampliado y RESUELTO el 2026-09-09.** Los ceros no eran un descuido, y la historia
> importa más que el hallazgo. El 20 de julio el filtro se puso en **calidad 3** con
> mapa de 4096 («bordes suaves y sin temblor»). El 1 de septiembre a la 01:03 se bajó
> a **0** para perseguir unas manchas que cambiaban al mover la cámara —y el propio
> commit avisaba: *«el piso patrón NO reproduce el artefacto… aquí no se puede dar por
> bueno»*—. Hora y media después se quitó el mapa de 4096 con el mensaje *«reopen X-8,
> the shadow hypothesis is disproven»*. El 5 de septiembre X-8 se cerró: **la causa era
> z-fighting**, no las sombras. O sea que el filtro se bajó persiguiendo un fallo que
> resultó ser otro, y **nunca se volvió a subir**.
>
> Restaurado a calidad 3 + mapa 4096, y añadido MSAA 4x, que es un problema distinto
> —el MSAA no suaviza el borde de una sombra, que es una consulta de textura, sino la
> silueta de la geometría—. Comprobado mirando: los bordes largos de la mancha de sol
> pasan de escalones a degradado, las diagonales de las chimeneas contra el cielo
> dejan de ser escalera, y **el suelo del rellano —donde se reportó el artefacto que
> motivó la marcha atrás— sale idéntico**, que es lo que cabía esperar si aquello era
> z-fighting. Coste medido con ventana real y vsync desactivado, dos pasadas por
> configuración: **1,24 → 1,82 ms por fotograma** sobre el piso de referencia, más de
> 500 fps en una gráfica integrada.
>
> El difuminado del sol se queda en 0: con el filtro en calidad 3 el suavizado ya lo
> da el filtro, y subirlo arriesga el tramado que sí está documentado.

#### 🟠 G-4. El exterior sigue sin pulir

EXT-1 se entregó así a propósito, pero conviene tenerlo medido: en la vista de
calle, los edificios vecinos son **bloques negros y grises sin una sola ventana**,
y la fachada propia es casi negra con un único hueco iluminado. La calzada, la
línea discontinua y el paso de cebra están; el alzado no.

**Medio cerrado el 2026-09-09.** La fachada de enfrente sí tenía ventanas, pero
el número de filas estaba topado a cuatro y la separación se calculaba dividiendo
la altura entre ellas: en una fachada de 45 m salían cuatro ventanas cada once
metros, que es exactamente «un muro liso». Ahora hay **una fila por planta real**,
con la altura de planta del edificio, y lo fija el guardarraíl de la altura.

Sigue abierto: los **retornos de esquina** y los **vecinos de nuestro lado** son
volúmenes ciegos (la fila de atrás lo es a propósito, ahí lo que se lee es la
silueta). Probé a darles bajos y balcones y lo revertí: en ninguna vista llegué a
verlos, y decorado que no se puede comprobar es como se colaron las tapias de
EXT-1.

**Y un hallazgo nuevo, de la misma medición:** `NearNeighbour` —los dos cuerpos
que deberían flanquear nuestro edificio— **no se construye nunca**. Las piezas se
generan y `_crosses_roadway` las descarta, porque desde EXT-1 la calle es un
**anillo alrededor de la manzana** y nuestro edificio es la manzana entera: no
queda sitio a los lados. O el anillo deja hueco para medianeras, o esos dos
cuerpos sobran. Sin decidir.

#### ✅ Cerrado el 2026-09-09 — tres tipologías y el fondo por manzana

Petición tuya: que el exterior sea un tipo de edificio distinto según la altura,
porque *«no es lo mismo la proporción de ancho y alto de uno de 20 plantas que
uno de 80»*, y que tape la vista de fondo. Las dos cosas están hechas, y la
segunda resultó no ser un problema de altura.

**Las tres tipologías** viven en `view/fp/FPUrbanTypology.gd`, y no son la misma
caja escalada: cada tramo trae sus piezas. Dentro de cada tramo los números se
interpolan, o 21 plantas y 49 se dibujarían igual.

| tramo | frente | fondo | esbeltez | ventanas | otras piezas |
|---|---|---|---|---|---|
| manzana (≤20) | 8,5 → 16 m | 6,6 → 13 m | 1:0,2 → 1:2,7 | hueco | zócalo, cornisa, balcones, bajo comercial |
| torre (21-50) | 24 → 34 m | 18 → 26 m | 1:2,5 → 1:4,2 | banda corrida | podio de 2 plantas, 1 retranqueo, remate |
| rascacielos (51-80) | 40 → 54 m | 30 → 40 m | 1:3,6 → 1:4,2 | banda corrida | podio de 5, 2 retranqueos, coronación, antena y baliza |

La banda corrida no es solo estilo: a 60 plantas, cuatro columnas de ventanas de
cuatro nodos cada una son mil nodos por módulo. Tabla completa en
`tools/probe_urban_typology.gd`.

**El fondo.** Aquí el diagnóstico cambió a mitad de camino. Mirando capturas no
había forma de saber si la superficie gris que se comía media ventana era un
edificio, el telón del skyline o el cielo: una foto no dice el nombre del nodo.
`tools/probe_exterior_occlusion.gd` lanza un abanico de rayos desde el hueco y sí
lo dice. Con eso:

- El decorado cubría **de −15 a +15 grados** y el resto era cielo.
- La causa no era la altura: **el fondo se construía por fachada**, y solo
  delante de las que tienen ventana. En diagonal no había nada construido.

Es la regla de EXT-1 otra vez —*una calle no se construye por fachadas, se
construye por manzana*—, que la calzada ya cumplía y el fondo no. Ahora la fila
de fondo es un **anillo de ocho orientaciones**, las cuatro diagonales incluidas
porque eran justo el agujero, en **dos filas desplazadas media pieza**, más un
**suelo de ciudad**: más allá del anillo de la calle tampoco había pavimento, y
al mirar hacia abajo en diagonal se veía el vacío.

**Medido**: de 27 rayos por debajo del horizonte, 27 tapados en las plantas 0, 5,
15, 35 y 65; y a +45 grados sigue habiendo cielo en las nueve direcciones,
porque taparlo todo también está mal. Lo fija `validate_exterior_occlusion`, en
la suite, probado con tres mutaciones (volver al fondo por fachada, quitar el
suelo, y disparar la altura de la fila de fondo).

**Y cuesta menos que antes**: 1,58 → 1,17 ms de fotograma medio en la planta 1.
Una torre son pocas piezas anchas con bandas, en vez de muchas estrechas con una
cajita por ventana.

**El color, cerrado el 2026-09-09.** Subir el albedo no hacía nada: el entorno
del FP tiene `ambient_light_source = 1`, o sea **ambiente desactivado**, así que
lo que no recibe sol directo se va a negro. Dentro de la vivienda da igual —hay
luces por todas partes—, pero en la calle dejaba las fachadas en sombra como
recortes negros. En vez de encender el ambiente global, que cambiaría también el
interior, el decorado urbano tiene su propio material con una emisión suave de su
color: el rebote del cielo. Mandos `city_sky_bounce_day` / `city_sky_bounce_night`.

**Y el dato que faltaba (2026-09-09).** Son **dos**: cuántas plantas tiene el
edificio y en cuál estamos. Hasta ahora el total se deducía —planta + dibujadas—,
así que el edificio terminaba siempre en el techo de la vivienda y **nunca había
nada por encima**. Ahora `building_total_floors` es un dato propio, en el editor
y en el menú, atado al otro por los límites de los dos mandos: el edificio no
puede tener menos plantas que la planta en la que se vive. La fachada propia sube
hasta el total y los vecinos lo miden. El resumen del menú lo dice entero: «piso,
planta 15 de 40».

**Plantas negativas, fuera.** Los dos mandos van de 0 en adelante y lo que venga
guardado por debajo se sube a 0.

#### 🟡 G-5. El fuego se lee flojo para lo que dice el HUD

En la vista de incendio del salón, con **HRR 850 kW y 340 °C**: una llama de
aproximadamente un metro en un extremo del sofá, el sofá teñido de rojo uniforme
y sin tizne, y la capa de humo presente solo como oscurecimiento general (la
visibilidad marca 3,2 m). El aparato de humo y llama está —hay cuatro shaders—
pero la magnitud de lo que se ve no acompaña a la del número.

No está diagnosticado: puede ser el tamaño de la llama, el tinte de estado, o
que la capa de humo no tenga representación propia a esa densidad.

#### ✅ Diagnosticado y arreglado el 2026-09-10 — no era ninguna de las tres

Medido con `tools/probe_fp_fire_scale.gd`, que monta el mundo FP y mide **la
malla construida**, no la fórmula: con el HUD en 850 kW se dibujaba una llama de
**0,60 m**. La fórmula de entonces decía 1,79 y Heskestad pide 1,95, así que el
tamaño se perdía por el camino.

**La causa**: el acercamiento al tamaño era un `lerp` de factor fijo que se
ejecutaba **una vez por estado de la simulación**, no por unidad de tiempo. Con
0,28 por estado hacen falta siete estados para llegar al 90 %, así que en
cualquier instante la llama estaba a un tercio de lo suyo —y cuanto más lento el
ritmo de estados, peor—. Ahora es una constante de tiempo (0,45 s al crecer,
0,22 al apagarse) que avanza con el reloj de física.

**Y la ley**: `0,18 + sqrt(HRR/1000) × 1,75` —dos números a ojo, sin diámetro de
fuego— pasa a ser la correlación de **Heskestad**, `L = 0,235·Q^(2/5) − 1,02·D`.

| HRR | antes | ahora |
|---|---|---|
| 120 kW | 0,26 m | 1,02 m |
| 400 kW | 0,43 m | 2,05 m |
| 850 kW | 0,60 m | 2,29 m (toca techo) |
| 1800 kW | 2,03 m | 2,29 m |

La red de fuego daba todo esto por bueno porque solo miraba que la llama
estuviera «escalada»; ahora comprueba que llega a lo que pide la correlación.

**Queda el tinte del mueble** —rojo plano, sin tizne—, aparcado a propósito: es
material de mobiliario y el kit se cambia entero.

---

## 4. Cómo se ha medido el estado

- **Vistas de referencia**: `tools/capture_visual_reference.gd`, ventana real a
  1600×900, 20 PNG (piso patrón limpio y en incendio, más la maqueta).
- **Editor**: `tools/capture_editor_ui.gd` (una foto al abrir) y
  `tools/capture_editor_plan.gd` (10 situaciones de dibujo, arrastres incluidos).
- **Coste del 3D**: `tools/probe_editor_3d_cost.gd`, hoy.
- **Materiales**: sonda propia que instancia el `.tscn` y recorre las superficies
  preguntando `albedo_texture`, porque mirar el fichero no distingue un modelo
  sin textura de uno con la textura embebida.
- **Estructura del editor**: recuento de funciones y variables sobre el fuente.
- **Suite completa**: `python scripts/check_product.py` → 42 OK y el FAIL
  conocido de la línea del motor (R2-1, informes por regenerar). Tras la fase 1
  son 45: entran `validate_building_height`, `validate_exterior_occlusion` y
  `validate_wind_controls`.

---


---

# Parte II · Lo que has pedido

## 5. Cómo está repartido el trabajo

Hay dos líneas, y varias de estas tareas cruzan la frontera:

- **Línea visual y editor** — `view/`, `editor/`, `ui/`, `scenes/`. Es `main`,
  el worktree principal. Es donde trabajo yo.
- **Línea del motor** — `sim/core/`. Va por su rama y se le habla escribiendo un
  `docs/PROMPT_MOTOR_*.md`. Todo lo que toque física entra por ahí.

En la tabla de abajo, la columna **línea** dice quién tiene que hacer cada cosa.
Las tareas marcadas `motor` conviene **encargarlas pronto aunque se integren
tarde**, porque la otra línea trabaja en paralelo y es el camino largo.

---

## 6. Las siete peticiones nuevas

### N-1 · Balcones colocables, sin poder salir a ellos
**Línea:** visual + editor · **Tamaño:** medio

**Lo que ya hay:** balcones, pero **solo en los edificios de enfrente**, como
decorado. `FPCityBlocks` los dibuja y `FirstPersonController` los gobierna con
`city_balconies_enabled` y `city_balcony_color`. En el edificio del jugador no
existe el concepto.

**Lo que falta:**
- Un tipo de elemento nuevo en el editor, colgado de una fachada, con su ancho,
  su vuelo y su antepecho.
- Geometría en la vista FP: losa en voladizo, antepecho o barandilla, y el
  encuentro con la fachada propia (`_create_own_facade`).
- **Que no se pueda salir**: la puerta del balcón se abre —importa para el fuego,
  es un hueco a fachada— pero el suelo del balcón no es transitable. Lo más
  limpio es no darle colisión de suelo y cerrar el hueco con un colisionador
  invisible en el plano de la fachada.
- Decidir si el balcón cambia el modelo de fuego. **Mi recomendación: sí.** Un
  balcón es un hueco de fachada con antepecho, y lo que cambia respecto de una
  ventana es la altura del alféizar y que el flujo sale a un espacio semiabierto.
  Como tipo de apertura basta con reutilizar `door` con un `sill_m` distinto.

**Pregunta abierta:** ¿el balcón es solo del edificio del jugador, o también
quieres poder poner balcones a las plantas de arriba y abajo de tu propio
edificio, que es lo que se ve al asomarse?

---

### N-2 · Patios interiores con tiro, sin sobrepresión hacia la vivienda
**Línea:** **motor** + visual + editor · **Tamaño:** grande — es la petición más cara

**Lo que ya hay, y es más de lo que parece:** el motor ya sabe hacer casi todo
lo que esto necesita.
- **Aperturas verticales** (`op.is_vertical`), cuyo intercambio va por
  flotabilidad y no por difusión.
- **Efecto chimenea** ya implementado sobre `floor_level_z_m`, con referencia
  documentada (SFPE Handbook, 5.ª ed. §9.1).
- Aperturas al exterior con su ΔP de viento por orientación de fachada.

**Lo que falta:** una zona nueva —el patio— que es un **conducto vertical abierto
al cielo por arriba**. Es decir, un hueco que atraviesa todas las plantas, cuyo
extremo superior es ambiente exterior, y al que las viviendas dan por ventanas.

**El punto delicado, y hay que decidirlo tú y yo:** pides que el patio *saque*
humo y tire hacia arriba **sin** meter aire a presión positiva hacia la vivienda.
Físicamente, un patio real sí desarrolla presión, y por debajo del plano neutro
sí entra aire hacia las viviendas: es justo lo que hace que un patio propague un
incendio a los vecinos de arriba. Hay dos caminos:

1. **El patio físico completo** — se modela como cualquier otro conducto, con su
   plano neutro, y a veces mete aire. Es lo correcto y es lo que hace peligroso a
   un patio de verdad.
2. **El patio como chimenea de un solo sentido** — se le impone que nunca
   sobrepase la presión ambiente, de modo que solo extrae. Es lo que has pedido,
   es más simple y es defendible como *modelo*, pero deja fuera el mecanismo por
   el que los patios matan gente en las plantas superiores.

**Mi recomendación: (1), con el matiz de que el patio esté siempre abierto por
arriba.** Un patio abierto al cielo apenas se presuriza por encima de la
ambiente, porque el techo no le opone resistencia; el efecto que quieres evitar
sale casi solo de la física, sin tener que imponerlo a mano. Pero es tu decisión
y cambia el encargo al motor, así que hay que cerrarla antes de escribir el
prompt.

**Reparto:**
- `motor`: la zona-conducto, su acoplamiento con las salas, el término de
  flotabilidad y el cierre superior a ambiente. Prompt propio.
- `editor`: herramienta de patio, que es un rectángulo que atraviesa plantas —se
  parece mucho al hueco vertical de la escalera, que ya existe.
- `visual`: el patio como espacio real en FP y en la maqueta, con su penacho de
  humo saliendo por arriba.

---

### N-3 · Que se note la altura al mirar por la ventana
**Línea:** visual · **Tamaño:** medio · **Depende de N-4**

**La causa exacta, localizada:**

```gdscript
// view/fp/FirstPersonController.gd:310
@export var exterior_floor_drop_m: float = 5.8
// :4090
func _exterior_ground_level_m() -> float:
    ...
    if _is_apartment_building():
        return base_y - maxf(0.0, exterior_floor_drop_m)
```

La calle se hunde **una constante de 5,8 m** por debajo de la vivienda, siempre.
Y `apartment_floor_number` —que existe, y está tanto en el editor como en el
menú— **no llega nunca a la vista**: buscándolo en todo el árbol solo aparece en
`ScenarioEditor.gd` y en `MainMenu.gd`. Por eso da igual la planta 0 que la 50.

**Lo que falta:**
- Que la cota del suelo salga de la planta: `drop = (planta − 1) × altura_planta`.
- Que a esa distancia el decorado siga teniendo sentido: desde la planta 15 no se
  ve el bordillo, se ven **cubiertas**. Hace falta que la manzana tenga tejados,
  y que a partir de cierta altura la mirada dé al horizonte y no a la calzada.
- Perspectiva aérea: cuanto más alto, más bruma de distancia. El cielo ya tiene
  banda de bruma (`sky_haze_*`), se puede reaprovechar.
- Que la sensación de altura no se pague con rendimiento: la calle lejana necesita
  menos detalle, no más.

**Pregunta abierta, y es de diseño, no técnica:** ¿qué quieres ver desde una
planta 20? ¿Las cubiertas de los vecinos y el horizonte? ¿Otros bloques altos
alrededor? ¿La calle sigue estando, muy abajo?

#### ✅ La cota, cerrada el 2026-09-09

`exterior_floor_drop_m` ya no existe. La calle cae **una altura de planta por
cada planta que hay debajo del forjado dibujado**, y la altura de planta sale
medida del propio edificio cuando tiene dos o más plantas. Medido con el piso
patrón: planta 0 → 0,00 m · planta 5 → −14,25 m · planta 15 → −42,75 m.

Capturas en `.test_tmp/ventana/` (asomarse recto, abajo y arriba, plantas 0 y
15): desde la 15 se mira **por encima de las cubiertas de los vecinos**, con el
cielo ocupando la mitad de arriba del hueco y la calle ya fuera del encuadre.
Eso responde por construcción la mitad de la pregunta abierta.

**Lo que sigue faltando de N-3:** la perspectiva aérea. Desde una planta alta el
telón del skyline se lee como un plano gris grande. La bruma de distancia
(`sky_haze_*`) no se ha tocado.

---

### N-4 · Altura del edificio y planta del incendio en el selector
**Línea:** visual + editor · **Tamaño:** medio · **Bloquea N-3 y la mitad de N-5**

**Lo que ya hay:** el menú tiene `ApartmentFloorRow` con su `SpinBox`, y el
editor guarda `apartment_floor_number`. Es la mitad de lo que pides —la planta—
pero no llega a ninguna parte y no hay noción de **altura total del edificio**.

**El tope de los vecinos, medido:**

```gdscript
// view/fp/FPCityBlocks.gd:278
var floors: int = clampi(int((height - 3.6) / 2.85), 1, 5)
```

Los edificios de alrededor están **limitados a 5 plantas** y su altura viene de
`facade_height_m`, que por defecto es 15 m. Tu propuesta —que los vecinos tengan
las mismas plantas que el edificio diseñado— es exactamente lo que hay que hacer
y además **resuelve el problema del exterior de raíz**: si el edificio de enfrente
tiene tus mismas plantas, mirar desde la 20 tiene una respuesta correcta sin
inventar un horizonte.

**Lo que falta:**
- Dos datos nuevos en el escenario: `plantas_totales` y `planta_del_incendio`.
- Que el editor los edite y el selector los ofrezca.
- Que la manzana los consuma: quitar el tope de 5 y derivar la altura de las
  plantas totales.
- Coherencia: la planta del incendio no puede pasarse de las plantas totales, y
  el editor ya sabe de plantas —hay que decidir si `plantas_totales` es un dato
  aparte o simplemente cuántas plantas tiene el escenario dibujado. **Mi
  recomendación: dato aparte.** Se dibujan 2 o 3 plantas y se declara que el
  edificio tiene 12; las que no se dibujan no arden, pero existen para la vista y
  para el tiro.

#### ✅ Cerrado el 2026-09-09 — decidido al revés de mi recomendación

**Las plantas del edificio son las dibujadas**, no un número declarado aparte, y
**los vecinos tienen esas mismas plantas**. Lo que sí es un dato es a qué altura
se planta esa pila: `apartment_floor_number` dice en qué planta cae el forjado
más bajo dibujado, y debajo quedan plantas de relleno que existen para la vista
—y para que los vecinos igualen la altura— pero que no se dibujan, no arden y no
salen en el HUD. Así el catálogo, que son pisos de una sola planta, sigue
pudiendo arrancar en la planta 15.

**La cuenta es la española y ahora está escrita**: 0 es la planta baja, los
positivos suben y los negativos son sótanos —el mando ya traía ese recorrido, de
−5 a 80, pero no lo decía en ninguna parte—. Está en el tooltip del editor, en el
del menú y en el resumen de la portada («piso, planta baja», «piso, sótano 2»).

Las cuentas viven en `view/geometry/BuildingLevels.gd` (`drawn_floor_count`,
`floor_to_floor_m`, `apparent_total_floors`, `street_drop_m`), que es donde ya
estaba la geometría compartida por las dos vistas.

**Los vecinos**: la fachada de enfrente medía 15 m constantes y los balcones
estaban topados a cinco plantas. Ahora la altura sale de las plantas que aparenta
nuestro edificio, y `opposite_facade_height_m` pasa a ser el mínimo. Medido:
planta 0 → vecinos de 15,0 m · planta 5 → 17,1 m · planta 15 → 45,6 m.

**Un mando de menos**: `own_facade_storey_pitch_m` y la altura de planta de
relleno eran lo mismo escrito dos veces. Ahora es `exterior_storey_pitch_m`, y
gobierna las tres cosas que tienen que cuadrar entre sí —las líneas de forjado de
nuestra fachada, la caída de la calle y la altura de los vecinos—.

**Guardarraíl** `tools/validate_building_height.gd`, en la suite: la calle baja
con la planta y baja lo que toca, los vecinos acompañan, hay una fila de ventanas
por planta —contada en lo construido, leyendo el índice de planta del nombre del
nodo— y una unifamiliar no se eleva por mucho que diga el mando. Comprobado con
tres mutaciones, una por cada constante vieja.

---

### N-5 · Viento: dirección y velocidad, en el editor y en el selector
**Línea:** visual + editor · **Tamaño:** pequeño en la UI, medio con la altura

**Aquí está la buena noticia del plan: el viento ya está en el motor.**

```gdscript
// sim/BuildingModel.gd:27-30
# Viento exterior (0 = sin viento). wind_direction_deg sigue la convención
# meteorológica: ángulo desde donde VIENE el viento (0=N, 90=E, 180=S, 270=O).
@export var wind_speed_m_s: float = 0.0
@export var wind_direction_deg: float = 0.0
```

Y `GasExchangeSystem` ya calcula, apertura a apertura:

> ΔP_viento = ½ × ρ × v² × Cp, con **Cp ≈ +0,6·cos** a barlovento (presión
> positiva, dificulta el venteo) y **Cp ≈ −0,4·|cos|** a sotavento (succión, lo
> facilita), según el ángulo entre el viento y la normal exterior de cada fachada.

Está implementado, tiene interruptor (`wind_effect_enabled`) y **ninguna interfaz
lo expone**: ni el editor, ni el menú, ni un solo escenario del catálogo pone
`wind_speed_m_s`. Está dormido.

**Lo que falta:**
- Dos mandos en el editor y dos en el selector: rosa de dirección y velocidad.
- Que `ScenarioSerializer` los guarde y `BuildingTemplate` los pase.
- **La corrección por altura**, que es lo que enlaza esta petición con N-3 y N-4:
  hoy `_compute_wind_dp_pa` usa `building.wind_speed_m_s` tal cual, **sin
  corregir por la altura de la apertura**. En la planta 20 sopla bastante más que
  en la calle, y ese es justamente el efecto que quieres que se note. Es un
  cambio en `sim/core/` → **prompt al motor**.

**El tope: 28 m/s (≈ 100 km/h).** Investigado, y con tres razones que apuntan al
mismo sitio:

| referencia | valor | qué es |
|---|---|---|
| Beaufort 9 — temporal | 20,8–24,4 m/s | 75–88 km/h |
| **Beaufort 10 — temporal fuerte** | **24,5–28,4 m/s** | **88–102 km/h** |
| Beaufort 11 — temporal muy fuerte | 28,5–32,6 m/s | ya es excepcional |
| Beaufort 12 — huracán | ≥ 32,7 m/s | fuera de "lo normal" |
| CTE DB-SE-AE, velocidad básica España | 26 / 27 / 29 m/s | zonas A / B / C, media de 10 min a 10 m, periodo de retorno 50 años |

El techo de Beaufort 10 (28,4 m/s) coincide casi exactamente con la velocidad
básica que el Código Técnico español usa para **dimensionar edificios**: es el
viento más fuerte que se considera rutinario. Por encima entra lo excepcional.
Redondeando: **0 – 28 m/s**, y en el mando se enseña también en km/h, que es como
la gente lee el viento.

**Pero el dato que más debería mandar en el diseño del mando es otro.** Los
ensayos de NIST y FDNY en Governors Island midieron que, con un viento impuesto
de **solo 9 a 11 m/s** (20–25 mph) y un recorrido de flujo por la planta del
incendio, aparecían más de 400 °C y 10 m/s de velocidad en el pasillo y en la
escalera *por encima* de la planta del fuego: condiciones no soportables ni con
equipo completo. **Lo interesante de este simulador ocurre entre 5 y 15 m/s**, no
en el tope. Así que el mando tiene que tener paso fino abajo —0,5 m/s hasta 15— y
puede ser más grueso arriba. Un tope de 28 que solo se use para la foto no sirve
de nada si a 8 m/s no se puede afinar.

**Fuentes:** [Beaufort — Met Office / RMetS](https://www.rmets.org/metmatters/beaufort-wind-scale) ·
[Beaufort — NOAA SPC](https://www.spc.noaa.gov/faq/tornado/beaufort.html) ·
[Zonas de viento CTE DB-SE-AE](https://www.dlubal.com/es/zonas-de-cargas-para-nieve-viento-y-sismos/viento-cte-db-se-ae.html) ·
[NIST — High Rise Fire Study](https://www.nist.gov/news-events/news/2009/05/high-rise-fire-study-provides-insight-deadly-wind-driven-fires) ·
[Wind-Driven Fire Research: Hazards and Tactics](https://www.fireengineering.com/fire-safety/wind-driven-fire-research-hazards-and-tactics/) ·
[Wind profile power law](https://en.wikipedia.org/wiki/Wind_profile_power_law)

Para la corrección por altura, la ley de potencia con exponente urbano
(α ≈ 0,25–0,33 en ciudad; 0,22 en periferia) da, por ejemplo, que 10 m/s de calle
son unos **15 m/s en la planta 15**. Es medio Beaufort más solo por subir.

#### ✅ Parte visual cerrada el 2026-09-09

Dos mandos en el editor y dos en el menú: **de dónde viene el viento** (ocho
rumbos) y **a qué velocidad** (0–28 m/s, paso 0,5, con los km/h en el resumen y
en el tooltip). La rosa vive en `ui/WindRose.gd`, escrita una vez para las dos
interfaces, porque la conversión es la trampa: el motor guarda los grados con la
convención meteorológica —de dónde **viene** el viento, no hacia dónde va— y
confundirlo invierte barlovento y sotavento. Por eso los mandos dicen «viento
del» y no «dirección».

**Ocho rumbos y no un ángulo libre**: es como se lee un parte, y la física del
motor solo distingue cuatro caras de edificio. Afinar a un grado sería precisión
fingida.

El resumen del menú lo dice entero: «viento 12,5 m/s (45 km/h) del SO».

**Guardarraíl** `tools/validate_wind_controls.gd`, en la suite, con cuatro
reglas: el dato sobrevive el viaje editor → normalización → JSON → `BuildingModel`;
el signo es el correcto a barlovento y a sotavento; a velocidad 0 no pasa nada
—que es el valor por defecto de todo el catálogo, así que encenderlo no cambia
nada de lo ya medido—; y **toda apertura exterior tiene lado canónico**. Esta
última no es teórica: `_compute_wind_dp_pa` hace `match op.wall_side` con
top/bottom/left/right y devuelve 0 para cualquier otra cosa, así que una apertura
con el lado vacío —o escrito «north»— se quedaría sin viento **sin avisar**. Hoy
las 67 aperturas exteriores del catálogo lo tienen; la red está para cuando
alguien dibuje una que no.

**Lo que falta es del motor**: corregir la velocidad por la altura de la
apertura. Encargado en `docs/PROMPT_MOTOR_VIENTO_ALTURA.md`.

---

### N-6 · El menú inicial es demasiado grande
**Línea:** visual · **Tamaño:** medio · **Bloquea N-4 y N-5**

**Medido hoy**, instanciando la escena: el `VBox` del menú pide **430 × 719 px**
en una ventana de 1280×720. O sea que **ya no cabe**, hoy, sin haber añadido
nada. La prueba de que se sabía es que `MainMenu.gd` tiene una función llamada
`_fit_window_to_screen()`.

El menú es un `CenterContainer` con un `VBox` de **ocho filas** en columna
—plantilla, tipo de edificio, planta del piso, climatización, iluminación, luces
interiores, rotura de vidrio, visibilidad— más tres botones.

**Y esto es lo que hace que N-6 vaya primero**: lo que pides añadir son cuatro
filas más (dirección del viento, velocidad del viento, plantas del edificio,
planta del incendio). Serían doce filas y unos 880 px de alto. **Añadir los
mandos nuevos antes de rehacer el menú empeora el problema que quieres
arreglar.**

---

### N-7 · Que se pueda elegir lo de siempre y lo nuevo sin saturar
**Línea:** visual · Es la forma que toma N-6, no una tarea aparte

El problema no es el número de mandos, es que **todos piden atención a la vez**.
Tres formas de resolverlo, de menos a más:

1. **Empezar y avanzado.** A primera vista, cuatro decisiones: escenario, tipo de
   edificio, planta del incendio y *Empezar*. Todo lo demás vive detrás de un
   «Ajustes avanzados» que se despliega. Es lo más barato y resuelve el 90 %.
2. **Por pestañas o pasos**: Escenario · Edificio · Ambiente (viento,
   iluminación, hora) · Física. Cada uno cabe de sobra.
3. **Preajustes con resumen.** «Piso, planta 3, sin viento, de noche» como una
   ficha que se elige de una lista, y un botón para retocar lo que sea. Los
   ajustes sueltos solo aparecen si los pides.

**Mi recomendación: (3) por encima de (1).** Los preajustes encajan con que ya
existe un selector de plantilla, dan una primera pantalla de cuatro cosas, y
hacen que cada mando nuevo que añadamos —viento incluido— no crezca la pantalla
inicial. La lista de ajustes sueltos se convierte en el sitio donde se retoca,
no en la puerta de entrada.

**Falta decidirlo contigo antes de tocar nada**, porque condiciona dónde caen los
mandos de N-4 y N-5.

#### ✅ Cerrado el 2026-09-09 — se hizo la opción (3)

La portada es ahora **logo · lista de escenarios · resumen · EMPEZAR / Retocar…**,
y los ocho mandos viven detrás de «Retocar» en un panel modal con velo, que se
cierra con «Listo» o con Escape. Medido con ventana real: el `VBox` pasa de
**719 px a 542**, y el panel de ajustes pide 357 aparte, así que **caben los
cuatro mandos de N-4 y N-5 sin volver a tocar la portada** —que era el motivo de
hacer esto primero—.

Piezas: `ui/ScenarioCard.tscn` (la ficha; las fichas se instancian por código
porque son CONTENIDO, no cromo) y el panel `TweakCenter` dentro de
`MainMenu.tscn`. El texto de cada ficha sale de `get_preset_definitions()`
—nombre y descripción—, no se inventa ninguna.

Dos cosas que importan para lo que viene:

- **El resumen de la portada** («piso, planta 3 · de noche · luces encendidas ·
  sin HVAC · cristales sin rotura») es lo que hace aceptable esconder los
  mandos. Cada mando nuevo tiene que añadir su trozo ahí, o «Retocar» se
  convierte en una caja negra.
- **La red vieja fijaba el diseño viejo**: `validate_main_menu_scene.gd` exigía
  `PresetRow` y las siete filas en la portada. Reescrita, y ahora incluye la
  regla que faltaba —**ningún `OptionButton` ni `SpinBox` cuelga del `VBox` de
  la portada**, y la portada tiene que caber en 720 px—. Comprobado con tres
  mutaciones: sin ellas, una red así solo sabe pasar.

---


---

# Parte III · El plan

## 7. Las dieciocho tareas, en una tabla

Lo único que solo puede dar el documento conjunto: las siete peticiones y los once
hallazgos ordenados por fase, con quién tiene que hacer cada uno.

| id | qué | tipo | línea | fase |
|---|---|---|---|---|
| **N-6·N-7** | El menú inicial no cabe (430 × 719 px) y satura | petición | visual | 0 ✅ |
| **G-3** | Borde de sombra dentado: tres valores a cero | 🟠 auditoría | visual | 0 ✅ |
| — | Escribir los prompts al motor (patios, viento por altura) | plan | coordinación | 0 ✅ |
| **N-4** | Plantas totales y planta del incendio en el selector | petición | visual + editor | 1 ✅ |
| **N-3** | Que se note la altura al mirar afuera | petición | visual | 1 ✅ (falta bruma) |
| **G-4** | Exterior sin alzado: los vecinos no tienen ventanas | 🟠 auditoría | visual | 1 ✅ |
| **N-5** | Viento: dirección y velocidad, con tope de 28 m/s | petición | visual + **motor** | 2 ✅ visual |
| **G-2** | Ningún mueble tiene textura — decisión de material | 🔴 auditoría | decisión | 3 |
| **G-1** | 121 de 140 modelos sin envoltorio: no se pueden dibujar | 🔴 auditoría | visual | 3 |
| **D-2** | El catálogo del editor cubre 14 de 38 arquetipos | 🔴 auditoría | editor | 3 |
| **N-1** | Balcones colocables, sin poder salir a ellos | petición | visual + editor | 4 |
| **N-2** | Patios interiores con tiro, sin sobrepresión | petición | **motor** + visual + editor | 5 |
| **D-1** | `ScenarioEditor.gd` volvió a 7990 líneas | 🔴 auditoría | editor | 6 |
| **D-3** | La ficha de la sala la tapan los muebles | 🟠 auditoría | editor | 6 |
| **D-4** | El 3D en vivo se sale del fotograma a ~16 salas | 🟠 auditoría | editor | 6 |
| **D-5** | La auditoría del editor se quedó en el día 7 | 🟠 auditoría | docs | 6 |
| **G-5** | El fuego se lee flojo para el HRR del HUD | 🟡 auditoría | visual | 6 ✅ |
| **D-6** | Las sondas de captura no pasan por el camino real | 🟡 auditoría | herramientas | 6 |

---

## 8. Lo que no conviene hacer por separado

Cuatro parejas que **no conviene hacer por separado**, porque son el mismo código
visto desde dos sitios:

- **N-3 + N-4** — «que se note la altura» y «altura del edificio en el selector»
  son la misma tarea. N-4 aporta el dato, N-3 lo gasta. Hacer N-3 sin N-4 obliga
  a inventarse la altura.
- **N-4 + G-4** — el alzado de los vecinos y sus plantas salen del mismo sitio
  (`FPCityBlocks`, el tope de 5 plantas). Arreglar G-4 mientras se hace N-4 sale
  casi gratis; hacerlo antes es trabajo tirado.
- **G-1 + D-2** — envolver los 121 modelos y llenar el catálogo del editor es una
  tarea con dos caras. Y **G-2 va antes que las dos**: si se decide cambiar de kit
  o texturizar, no tiene sentido haber envuelto 121 modelos del kit viejo.
- **N-6 + N-4 + N-5** — el menú es el sitio donde caen los mandos nuevos. Si el
  menú no se rehace primero, N-4 y N-5 lo empeoran.

Y una dependencia de calendario: **N-2 (patios) y la corrección de viento por
altura son del motor**. El prompt hay que escribirlo pronto aunque se integre
tarde, porque el motor trabaja en paralelo y es el camino largo.

---

## 9. Orden propuesto

### Fase 0 — desatascar el menú *(bloquea casi todo lo demás)* — ✅ COMPLETA
- ✅ **N-6 + N-7**: menú rehecho con preajustes en ficha y panel «Retocar». De
  719 px a 542. Ficha de cierre en la sección N-7.
- ✅ **G-3**: los tres valores del antialiasing y el filtro de sombra (`08c3705`).
- ✅ Los dos prompts al motor: `docs/PROMPT_MOTOR_PATIO.md` y
  `docs/PROMPT_MOTOR_VIENTO_ALTURA.md` (`bf166e7`).

### Fase 1 — la altura como dato de verdad
- **N-4**: `plantas_totales` y `planta_del_incendio` en el escenario, el editor y
  el menú nuevo.
- **N-3**: la cota del suelo derivada de la planta, en vez de la constante de
  5,8 m. Cubiertas, horizonte y bruma de distancia.
- **G-4**: de paso, alzado de los vecinos —quitando el tope de 5 plantas, que es
  la misma línea de código.

### Fase 2 — el viento
- ✅ **N-5, parte visual**: mandos en el editor y en el menú, y que lleguen al
  `BuildingModel` (que ya los espera).
- **N-5, parte motor**: prompt para la corrección de la velocidad por altura de
  la apertura. Se puede escribir ya, en la fase 0, para que vaya en paralelo.

### Fase 3 — el mobiliario — ✅ COMPLETA en lo que no depende del kit
- ❌ **G-2 y G-1 CANCELADOS** por decisión tuya (2026-09-09): las texturas y las
  mallas se cambian enteras por un kit nuevo, así que decidir material y
  envolver los 121 `.glb` sería trabajo tirado.
- ✅ **La colocación**, que es lo que el kit nuevo no arregla: orientación,
  parejas (`FurnitureRoomGrammar`), la cama de cabecero y la colocación por
  grupos. Silla-escritorio 0/14 → 14/14, cocina seguida 0/8 → 5/8, mesa de
  centro 7/10 → 10/10.
- ✅ **D-2**: el catálogo del editor pasa de 14 a **38 arquetipos** — ya se puede
  amueblar un baño y una cocina—. Era un `match` de 250 líneas; ahora es una
  tabla. Las cifras de fuego de las 24 piezas nuevas son estimaciones de
  ingeniería escaladas por clase de material, no ensayos, y están dichas como
  tales en el fichero.
- ✅ **Piezas colgadas**: `mount_h_m` en la ficha, las dos vistas la respetan, y
  lo colgado deja el suelo libre debajo (dos piezas solo chocan si comparten
  sitio en planta **y** franja de aire). El mueble de baño estrena el mecanismo.
- ⏳ **Pendiente y consciente**: las 7 plantillas que declaran la carga de fuego a
  granel y se amueblan con atrezo. Decisión tuya del 2026-09-06: se convierten a
  objetos de verdad cuando el motor esté terminado.

### Fase 4 — balcones — ✅ COMPLETA (2026-09-10)
- ✅ **Decisión tuya del 2026-09-10: solo en el edificio del jugador.** Las
  plantas de arriba y abajo de la fachada propia quedan lisas.
- ✅ **El dato**: `has_balcony`, `balcony_width_m`, `balcony_depth_m` y
  `balcony_parapet_m` colgados de la abertura, y solo de una abertura exterior
  y no vertical —en un tabique interior no hay fachada de la que colgar nada, y
  el dato se borra al normalizar en vez de arrastrarse—. El ancho a 0 significa
  «el del hueco más 0,80 m».
- ✅ **El editor**: casilla y tres medidas en la ficha de la abertura, que solo
  aparecen donde el balcón puede existir, y la huella del balcón dibujada en
  planta —es lo primero que se sale de la vivienda—.
- ✅ **La vista FP**: losa en voladizo, antepecho en U y pasamanos, colgados a la
  cota del suelo y por fuera del lienzo de fachada. Todo con `@export`.
- ✅ **No se puede salir**, que es lo que pediste: la losa y el antepecho no
  tienen colisión, y el hueco se cierra con un colisionador invisible en el
  plano de la fachada. Ya existía un `NoExitBoundary` alrededor del edificio,
  pero va por la **caja** del edificio: una fachada retranqueada deja hueco por
  delante. La barrera va por el hueco.
- ✅ **El balcón y el portal no comparten hueco**: el rellano es de la puerta de
  entrada, así que una puerta con balcón ya no genera portal, ni entrada, ni es
  el sitio donde aparece el jugador sin `player_start`.
- ✅ **Los dos límites**, a petición tuya (2026-09-10):
  - **El vuelo no puede ser incoherente**. Tope **2,00 m**: un balcón de
    vivienda es una losa en voladizo, y más allá pide vigas de canto o pilares
    hasta la calle, que ya no es un balcón. Y el **canto sube con el vuelo**
    (regla de predimensionado del voladizo, canto ≥ vuelo / 10): con canto fijo,
    dos metros de balcón se leen como una hoja de papel.
  - **El ancho no puede pasar de la fachada construida**, y no basta con que no
    sea más ancho: tiene que **caber**. Junto a la esquina se estrecha
    —centrado en su hueco, nunca corrido de sitio— para no asomar por el canto
    del edificio. La regla del recorte vive en `OpeningModel` y la usan los dos
    sitios que saben cosas distintas: el editor conoce el paramento de su sala,
    la vista conoce el lienzo entero.
  - Los topes viven en `OpeningModel` y los leen el serializador, el editor y la
    vista. Repartidos, bastaba tocar uno para que el editor dejase pedir algo
    que la vista no construye.
- ✅ Guardarraíl `tools/validate_balconies.gd` en la suite (48 OK), probado con
  seis mutaciones: quitar la barrera, dar colisión a la losa, ignorar el vuelo
  declarado, quitar el recorte del ancho, descentrar el recorte en vez de
  estrecharlo y quitar el tope de vuelo del dato.
- ⏳ **Ningún preajuste trae balcón todavía**: la pieza existe y el editor la
  pone, pero para verla hay que declararla. Convertir una ventana de
  `piso_mediterraneo` es una línea de datos, y es decisión tuya.

### Fase 5 — patios interiores
- **N-2**. La más cara, y la que más depende del motor. El prompt se escribe en
  la fase 0; la integración cae aquí.

### Fase 6 — la deuda que queda
- **D-1** (sacar «3D en vivo» y «objetos» a sus módulos), **D-3** (la ficha de la
  sala bajo los muebles), **D-4** (margen del 3D en vivo), **D-5** (documentación
  del editor), **D-6** (sondas), **G-5** (la magnitud del fuego).

---

## 10. Lo que necesito que decidas antes de empezar

1. ~~**N-7 · La forma del menú**~~ — **decidido: preajustes con resumen**, hecho
   el 2026-09-09.
2. **N-2 · El patio**: ¿física completa con plano neutro, o chimenea de un solo
   sentido impuesta? Cambia el encargo al motor.
3. **G-2 · El material del mobiliario**: ¿textura propia sobre el kit que ya
   tenemos, o cambiar a un kit texturizado? Va antes de envolver 121 modelos.
4. ~~**N-5 · El tope del viento**~~ — implementado a **28 m/s** con esa
   justificación; cambiarlo es una constante en `ui/WindRose.gd`.
5. **N-3 · Qué se ve desde arriba**: ¿cubiertas y horizonte, otros bloques altos,
   la calle muy abajo?
6. ~~**N-4 · Plantas totales**~~ — **decidido: son las dibujadas**, y los
   vecinos las mismas. Hecho el 2026-09-09.
7. **N-1 · Balcones**: ¿solo en el edificio del jugador, o también en las plantas
   de arriba y abajo, que es lo que se ve al asomarse?
