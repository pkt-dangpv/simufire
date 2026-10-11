# SimuFire — guía para decidir la reforma de representación 3D y primera persona

Fecha: 7 de octubre de 2026.
Destinataria: diseñadora gráfica y persona que implemente el nuevo generador.
Estado: documento de decisión y entrega; no describe una reforma terminada.

## 1. Qué queremos conseguir

Queremos que puedas diseñar la representación de las viviendas sin tener que
adivinar cómo el juego transforma tus modelos ni buscar reglas repartidas por
todo el proyecto. El objetivo es un sistema que genere superficies de paredes,
suelos, techos, huecos, pasillos, portales y escaleras con sus materiales y
texturas, y que coloque los assets con medidas y orientación previsibles.

Puedes proponer otra organización, sustituir el generador visual o conservar
lo que resulte útil. No está decidida la técnica de construcción de mallas,
el programa de modelado ni quién programará el generador. Este documento
sirve tanto si vas a programarlo en Godot como si vas a entregar modelos,
texturas y especificaciones para que lo implementemos nosotros.

Lo esencial: **rediseñar cómo se ve y se recorre la vivienda no es rehacer
la física del incendio**. Debe quedar claro dónde acaba una cosa y empieza otra.

## 2. Tres sistemas que no debemos confundir

| Sistema | Qué contiene | Qué significa reformarlo |
| --- | --- | --- |
| Datos del edificio y simulación | Salas, cotas, conexiones, aperturas, combustibles y estado del incendio | Cambiar estos datos puede cambiar volumen, ventilación, fuego o gases |
| Representación | Mallas, texturas, materiales, modelos, luces y efectos visuales | Es el objeto principal de esta reforma |
| Primera persona, FP | Cámara, movimiento, postura, colisiones e interacción | Tiene que seguir permitiendo recorrer el edificio y usar sus aperturas |

La simulación vive principalmente en `sim/`; la presentación en `view/`.
FP significa primera persona, no otro motor de incendio.

Una textura de madera no convierte por sí sola una superficie en combustible.
Un sofá decorativo no equivale a un sofá con masa y emisiones en el motor.
Una pared dibujada no crea por sí sola una frontera para el humo. Esas relaciones
deben ser explícitas; no se deben inferir de un material, nombre o color.

## 3. Cómo se construye una vivienda hoy

### 3.1. No existe un único modelo 3D de la vivienda

El escenario describe salas y aperturas. `BuildingModel` y los modelos de
sala/apertura permiten consultarlas. Las vistas generan nodos y geometría a
partir de esos datos y añaden mobiliario y contexto.

La base habitual de las salas es un rectángulo de planta, una altura y una
cota. En la representación, la planta ocupa X/Z y la altura ocupa Y.
Esto **no es todavía un editor general de habitaciones con cualquier polígono**.
Generar polígonos para las mallas actuales es una reforma visual; admitir
habitaciones de planta arbitraria exigiría acordar también el contrato de
datos y sus consumidores. No dar esa segunda ampliación por incluida.

### 3.2. Hay dos representaciones con diferencias deliberadas

- La vista 3D de maqueta permite ver la distribución desde fuera: algunas
  paredes son transparentes y se pueden ocultar elementos para inspeccionarla.
- FP construye un entorno transitable, con paramentos partidos por huecos,
  suelos, techos y colisiones. No puede tratar un muro como una caja cerrada
  si el jugador debe cruzar una puerta.

Actualmente comparten parte de la geometría, pero no un generador completo.
`RoomShellFactory` construye la envolvente de maqueta con cuatro paredes de
caja; esa envolvente no equivale a los muros transitables de FP. Esta diferencia
figura como intencional en el código histórico, no como una unificación ya hecha.

La reforma puede mantener estilos distintos de visualización. Lo que buscamos
es que ambos estilos partan de las mismas medidas, huecos y cotas, no que
ambas vistas tengan idéntica transparencia, iluminación o cámara.

### 3.3. Mapa de archivos para empezar

Todas las rutas enlazadas son relativas a la raíz de este checkout del proyecto.

| Elemento | Dónde está hoy | Responsabilidad actual |
| --- | --- | --- |
| Edificio | [BuildingModel](../../sim/BuildingModel.gd) | Lectura y acceso al modelo del edificio |
| Sala | [RoomModel](../../sim/building/RoomModel.gd) | Datos de cada recinto |
| Apertura | [OpeningModel](../../sim/building/OpeningModel.gd) | Datos de conexiones y aperturas |
| Maqueta 3D | [Visualizer3D](../../view/3d/Visualizer3D.gd) | Coordina representación, cámara y actualización visual |
| Envolvente de maqueta | [RoomShellFactory](../../view/3d/geometry/RoomShellFactory.gd) | Suelo, cuatro paredes de caja y rótulo |
| Mundo FP | [FirstPersonController](../../view/fp/FirstPersonController.gd) | Movimiento e interacción, además de mucha construcción de escena |
| Lados de pared | [WallSideGeometry](../../view/geometry/WallSideGeometry.gd) | Lados, normales y coincidencia entre salas |
| Posición de huecos | [OpeningPlacement](../../view/geometry/OpeningPlacement.gd) | Colocación de aperturas sobre paramentos |
| Losas y vacíos | [SlabGeometry](../../view/geometry/SlabGeometry.gd) | Reparto de suelos y techos con huecos |
| Escaleras | [StairGeometry](../../view/geometry/StairGeometry.gd) | Tramos, mesetas y ojo de escalera |
| Portal modelado | [PortalGeometry](../../view/geometry/PortalGeometry.gd) | Reparte rellano y escalera en un recinto de portal |
| Plantas y cotas | [BuildingLevels](../../view/geometry/BuildingLevels.gd) | Consultas de nivel sobre el edificio |

En `FirstPersonController`, buscar `_create_walls`, `_create_ceilings`,
`_create_stairs` y `_create_landing_recess`. Es una clase grande con funciones
de varias responsabilidades; no es necesario leerla entera para empezar con
una habitación de referencia.

### 3.4. Hall, portal y contexto exterior no significan lo mismo

1. **Pasillo o hall interior:** una sala del escenario, con las conexiones
   que realmente describe el modelo.
2. **Portal modelado:** uno o más recintos del edificio. La representación
   reparte su superficie entre rellano y escalera; esa subdivisión visual no
   convierte automáticamente cada parte en una nueva sala del simulador.
3. **Contexto decorativo exterior:** piezas que las vistas pueden añadir junto
   a la vivienda, como un rellano, fachada o calle, sin que todos esos espacios
   formen parte de los recintos simulados.

El nuevo sistema debe distinguir los tres. No puede añadir un portal decorativo
encima de uno ya modelado, cerrar una salida o mostrar un espacio como si
estuviera simulado cuando solo es decorado. La geometría debería identificar
qué sala o regla la originó para poder localizar cualquier problema.

## 4. Por qué los assets cambian de tamaño y giro

### 4.1. La ruta actual del mobiliario

El archivo de la artista no llega sin cambios a la pantalla. La ruta incluye:

1. Clasificar la pieza y elegir un arquetipo, por ejemplo cama o sofá.
2. Resolver una talla mediante [FurnitureDimensions](../../view/furniture/FurnitureDimensions.gd).
3. Cargar el wrapper `.tscn` y el modelo que contiene mediante
   [FurnitureAssetLoader](../../view/3d/furniture/FurnitureAssetLoader.gd).
4. Ajustar tamaño, ejes y origen según la política del cargador.
5. Resolver distribución mediante [FurnitureRoomLayout](../../view/furniture/FurnitureRoomLayout.gd)
   y [FurnitureRoomGrammar](../../view/furniture/FurnitureRoomGrammar.gd).
6. Construir la pieza para la vista; algunas poses no bloqueadas pueden pasar
   por [FurniturePlacement3D](../../view/3d/furniture/FurniturePlacement3D.gd),
   que también ajusta su encaje.

[FurnitureVisualLayout](../../view/furniture/FurnitureVisualLayout.gd) es la
entrada compartida de distribución visual de sala. Los wrappers de mobiliario
están en `assets/fp/furniture/`; muchos instancian archivos GLB dentro de
`assets/fp/furniture/gltfs/`. Puertas y ventanas tienen escenas en
`assets/fp/openings/`; no constituyen por sí solas la pared que las aloja.

### 4.2. Transformaciones existentes, no suposiciones

La política histórica, `legacy_fit`, puede:

- Girar internamente 90° para alinear el lado largo del asset con el destino.
- Escalar de manera distinta X, Y y Z, con límites de deformación.
- Recentrar la caja del modelo y apoyar su base en Y=0.
- Repetir módulos en piezas como los frentes de cocina.

La distribución automática puede añadir otro giro o cambiar una posición;
algunas piezas y elementos de atrezo pueden reducirse o esconderse. Bloquear
la pose de distribución no garantizaba, por sí solo, conservar la talla
original del modelo al pasar por el cargador.

Por eso corregir el GLB a ciegas puede compensar una regla del juego y provocar
otro problema después. Primero hay que decidir quién manda sobre cada dato.

### 4.3. Medidas comprobadas en esta sesión

Dimensiones en metros: X, altura Y, Z. «Destino» significa talla solicitada por
el código; no es una medición del mueble real ni una intención confirmada de
su autora. La caja es la envolvente geométrica del modelo.

| Pieza | Caja original | Destino solicitado | Resultado observado |
| --- | --- | --- | --- |
| Cama | 0,956 × 0,375 × 1,125 | 2,00 × 0,55 × 1,50 | Talla de destino, con giro interno de +90° |
| Sofá | 0,980 × 0,460 × 0,410 | 2,10 × 0,85 × 0,90 | Escalas X/Y/Z de 2,143 / 1,848 / 2,195 |
| Frente de cocina | Módulo 0,430 × 0,450 × 0,450 | 1,80 × 0,90 × 0,60 | Tres módulos: conjunto de 1,80 × 0,781 × 0,623 |

Se inspeccionaron 38 arquetipos. Estas medidas demuestran ajustes del sistema.
Todavía no tenemos un asset concreto identificado por la diseñadora como
reproducción de su incidencia, ni conocemos su programa de exportación.

## 5. Materiales y texturas hoy

Hay materiales procedurales, colores elegidos por tipo de sala y materiales
propios de assets. FP ofrece overrides para pared, suelo, techo y fachada;
su selección y creación están dentro de `FirstPersonController`, entre otras
funciones `_wall_material_for_room`, `_floor_material_for_room` y
`_ceiling_material_for_room`. La maqueta también construye materiales propios.

No basta con entregar una textura y esperar que se aplique uniformemente a
todas las superficies: hay que definir qué material la usa, cómo se asigna y
qué coordenadas de textura recibe la malla generada.

Además, hay actualizaciones visuales por estado del incendio. Al reformarlas,
el quemado, selección o efecto de humo no debe sustituir accidentalmente el
material artístico ni cambiar la pose. Habrá que decidir cómo se superponen
esos efectos y comprobar los consumidores actuales.

## 6. Qué debe permitir el nuevo generador de polígonos y texturas

Esta sección describe requisitos, **no un generador ya implementado**.
La diseñadora y quien programe pueden elegir cómo cumplirlos.

### 6.1. Entrada y salida claras

Entrada: geometría del edificio en metros, identificadores de salas y
aperturas, niveles, configuración visual y materiales elegidos. La fuente
autoritativa sigue siendo el escenario; no se deduce una planta nueva de un
conjunto de mallas decorativas.

Salida: superficies o mallas con sus materiales, coordenadas de textura,
transformaciones y procedencia; además, información de colisión para FP
coherente con los mismos huecos y cotas. No es obligatorio usar la malla
de máximo detalle como colisión.

Una posible separación, con nombres orientativos y no API acordada:

```text
Datos del edificio
    -> descripción geométrica común en metros
        -> generador de mallas + UV + materiales
        -> colisiones y puntos de interacción FP
        -> reglas de presentación de maqueta / FP
```

La descripción debe contemplar paredes compartidas, jambas, dinteles,
espesor, losas, techos y vacíos. No generar dos tabiques superpuestos sin
una regla explícita ni cerrar con triángulos el hueco de una puerta.

### 6.2. Polígonos, normales y huecos

- Superficies con caras orientadas y normales correctas; no ocultar errores
  de orientación activando siempre material de doble cara.
- Puertas y ventanas con hueco real en representación y colisión.
- Techos y forjados con los vacíos que necesita la escalera.
- Sin caras coplanares duplicadas que parpadeen ni grietas visibles entre piezas.
- Separación entre caras exteriores, interiores y cantos cuando sus materiales
  o coordenadas de textura sean distintos.
- Reconstrucción determinista: mismos datos y configuración producen la misma
  geometría relevante, sin poses distintas por cambiar de vista.

No se impone triangulación manual, una biblioteca concreta, mallas paramétricas,
piezas modulares ni otra técnica. Lo que debe conservarse es el resultado
geométrico y su trazabilidad.

### 6.3. UV y escala de textura

UV son las coordenadas que indican qué parte de una textura corresponde a
cada punto de la superficie. Hay que declarar una política, no dejarla como
efecto secundario de estirar un objeto.

- Densidad visual consistente: por ejemplo, una textura que represente un
  metro de pared debe mantener esa escala en paredes largas y cortas.
  El valor concreto lo elige arte; un metro es un ejemplo, no una obligación.
- Política de repetición o atlas declarada, sin deformar azulejos para cubrir
  cualquier tamaño de habitación.
- Continuidad de textura al dividir un muro por una puerta cuando proceda;
  no reiniciar arbitrariamente el patrón en cada fragmento.
- Orientación explícita en suelo, pared, techo, peldaños y cantos.
- Materiales por superficie o categoría con una alternativa visible y un aviso
  si falta el recurso, en lugar de esconder el problema.

Arte decidirá qué mapas necesita cada material: color, normal, rugosidad u
otros. Deben documentarse rutas, escala de uso, convención de mapas, licencia
y configuración de importación. No se exige generar imágenes nuevas en esta fase.

### 6.4. Unidades, ejes y pivotes de assets

Para las piezas nuevas, establecer unidades y ejes explícitos. La propuesta
actual es metros, +Y arriba y frente declarado. No adivinar el frente por
el lado más largo de la caja.

El pivote depende de la función: centro apoyado en suelo para mobiliario,
bisagra para una hoja de puerta, origen de ensamblaje para un módulo.
No aplicar el contrato de un sofá a todos los elementos arquitectónicos.

Separar cuatro políticas: conservar tamaño del autor; escala uniforme
autorizada; repetición modular; adaptación paramétrica diseñada. Cada pieza
debe declarar cuál usa. Evitar ajustes desiguales o giros inferidos en ejecución.

### 6.5. Colocación manual y automática

La colocación manual conserva la pose elegida. Si un mueble no cabe, invade
un paso o colisiona con otro, se informa; no se encoge o gira silenciosamente.

El autoamueblado sigue siendo útil, pero debe ser una política separada.
Resuelve una pose y ambas vistas la consumen sin volver a encajarla.
Guardar/cargar, cambiar de planta y actualizar estado del incendio deben
preservar el resultado. Las fichas visuales independientes y su persistencia
todavía necesitan diseño; no se presentan como resueltas.

## 7. Qué puedes decidir libremente y qué hay que coordinar

Puedes proponer estructura de carpetas y módulos, técnica de malla,
materiales, UV, estética, resolución, modularidad, escenas de prueba y
flujo de trabajo. También puedes proponer empezar un renderer desde cero.
Los nombres de los módulos nuevos no están impuestos por esta guía.

Hay que coordinar cambios en medidas del escenario, conexiones físicas,
combustibles, apertura de puertas y ventanas, puntos de interacción y contrato
de carga/guardado. Un cambio visual no debe modificar automáticamente ninguno
de esos datos. Si hay un error real de planta, se corrige como dato del edificio
con sus pruebas, no mediante un desplazamiento invisible del renderer.

Se pueden conservar cámara, movimiento y módulos útiles aunque se sustituya
todo el constructor de mallas. Reutilizar una regla geométrica correcta evita
inventar una segunda interpretación de la misma puerta o escalera.

Si solo vas a producir arte, la entrega puede ser: materiales y texturas,
escenas de referencia, medidas, ejes, pivotes y reglas de ensamblaje.
Nosotros implementaremos el generador a partir de esa especificación.
Si vas a programar, conviene acordar primero la entrada y salida anteriores.

## 8. ¿Borrar, comentar o sustituir el sistema actual?

No se ha autorizado un borrado general. Hoy representación y colisiones están
entrelazadas; eliminar el controlador FP quitaría más que las paredes visibles.
Comentar grandes bloques tampoco deja una separación clara ni verificable.

Propuesta de transición, modificable al acordar el diseño:

1. Crear un punto de entrada visual nuevo y una escena mínima independiente.
2. Mantener el constructor actual como alternativa durante la comparación.
3. Sustituir por partes o mediante una selección de renderer de presentación;
   esa selección no es un interruptor de física experimental.
4. Verificar huecos, colisiones, interacción, medidas y aspecto.
5. Integrar el nuevo constructor en las vistas y retirar las rutas obsoletas
   cuando dejen de tener consumidores y exista evidencia de equivalencia.

Git conserva el sistema anterior. No es necesario guardar código muerto
comentado indefinidamente para poder recuperarlo.

## 9. Herramientas y prototipo que ya están preparados

### 9.1. Banco original frente a resultado del juego

Incluido en la entrega técnica del 08-10-2026.
Abrir [el banco](../../tools/preview_visual_asset.tscn) en Godot,
seleccionar el nodo raíz, elegir `archetype` y ejecutar esa escena.

- Izquierda: wrapper original.
- Derecha: resultado del cargador del juego para `requested_footprint_m`.
- Cuadrícula en metros; rojo +X, azul +Z.

No ejecuta el incendio ni distribuye muebles por una sala. Aísla carga y ajuste;
no representa todavía todo el recorrido desde el editor. El arranque headless
está probado, pero su aspecto necesita revisión humana.

`tools/inspect_visual_assets.gd` produce medidas
y transformaciones usando el cargador real, sin reescribir escenas ni GLB.

### 9.2. Contrato optativo de conservación de autoría

Está implementado un prototipo para **mobiliario**, declarado en la raíz local
del wrapper:

```text
metadata/simufire_transform_mode = "authored_meters_v1"
metadata/simufire_front_axis = "-z"
```

Exige raíz identidad, medidas finitas y positivas, centro horizontal en el
origen y base en Y=0, con tolerancia de 1 mm. La escena fuente puede tener
correcciones explícitas en sus hijos; el wrapper final debe cumplir el contrato.
No certifica contratos de puertas, cocinas modulares ni escenas heredadas.

En este modo no se ajusta al tamaño solicitado ni se gira internamente. Las
vistas solo convierten metros a unidades. Los conflictos de límite de sala y
paso de puerta se publican como avisos, sin mover la pose manual.

La referencia es [authored_meter_reference.tscn](../../assets/fp/examples/authored_meter_reference.tscn),
una caja asimétrica de 1,2 × 1,0 × 0,4 m, no un mueble real ni combustible.
En el banco elegir `authored_meter_reference`: cambiar el tamaño solicitado
no debe cambiar esa caja.

Los 38 arquetipos inspeccionados siguen en `legacy_fit`. No se han migrado
retrospectivamente. Reiniciar el banco tras cambiar un wrapper: el hot-reload
de cachés no está certificado. No hay todavía panel de avisos del editor,
colisiones exhaustivas entre poses manuales ni nuevas fichas visuales persistidas.

Código del prototipo: [VisualAssetContract.gd](../../view/3d/furniture/VisualAssetContract.gd).
Detalles de uso: [guía de assets](../../assets/fp/README.md).

## 10. Primer ejemplo recomendado, sin imponer la arquitectura

Antes de una vivienda completa, construir una escena con una habitación,
suelo y techo, una puerta, una ventana, dos materiales de pared y un asset
asimétrico. Elegir medidas explícitas y una textura de comprobación con
cuadrícula o números para detectar estiramientos y giros.

Mostrar esa misma geometría como maqueta y desde FP. Comprobar desde ambos
lados la abertura de puerta, sus colisiones y su interacción. Después añadir
dos salas contiguas, un hall y una escalera de dos plantas con rellanos y huecos.

Este ejemplo sirve para decidir el diseño con algo visible y medible; no
obliga a continuar con los nombres ni las técnicas del prototipo actual.

## 11. Cómo sabremos que la reforma funciona

La aceptación debe combinar pruebas automáticas y revisión con la diseñadora:

- Modelo original y runtime mantienen la talla, orientación y pivote acordados.
- Maqueta y FP coinciden en planta, cotas, huecos y poses; solo difiere su estilo.
- Texturas mantienen escala y orientación al cambiar longitud o dividir paredes.
- El jugador atraviesa puertas, no atraviesa muros y sube/baja las escaleras
  mediante su movimiento y colisiones reales, no solo por existir nodos.
- Bisagras a ambos lados, barridos de hojas y ventanas funcionan sin tapar pasos.
- Cambiar estado visual, guardar/cargar y reconstruir no mueve las piezas.
- No se duplican portales ni se confunde decorado con recintos simulados.
- No se alteran parámetros de incendio, gases, energía o combustible para
  compensar errores de dibujo.
- Se miden coste de reconstrucción, memoria y complejidad de escena; los
  presupuestos concretos se acuerdan, no están fijados por esta guía.

Una prueba headless verde detecta errores y permite comparar geometría, pero
no certifica estética, iluminación, legibilidad ni sensación de navegación.

## 12. Estado real de entrega y precauciones

Este documento se redactó en `runs/playable_homes`, rama
`codex/playable-homes-isolated`, sobre la base `2e5d764a`. El usuario autorizó
publicar la entrega documental por separado en `dd9390a9`. Después autorizó
publicar el código, escenas de prueba y viviendas si toda la cadena pasaba.
La entrega técnica del 08-10 incluye esos archivos; no sustituye la decisión
de diseño ni presenta la reforma completa como terminada.

Cadena final: focal 70 pruebas y 42 subtests; contrato sintético 41 checks,
rechazo modular tres checks; 38 arquetipos inspeccionados sin reescribir assets.
Diez viviendas verificadas en FP: 2.804 checks, 359 piezas, 316 de atrezo.
Referencia 346/346, 78 gaps, R2-1 verde, corpus sin cambios de contenido;
producto 168/168 y global 4.241 passed / 53 skipped / 2 xfailed / 42 subtests.
Son controles del inspector y prototipo, no de un generador arquitectónico nuevo.

Pendiente: elegir y revisar un asset real, migración del catálogo, descripción
geométrica común, nuevo sistema de polígonos/UV/materiales, extracción FP,
aceptación visual y navegación. La cadena automática de esta entrega sí pasó.

Esta entrega separa diez viviendas jugables en `scenarios/playable/` de
los casos históricos del motor; aceptación automática completada, revisión
humana y navegación integral pendientes. Parte del mobiliario
añadido es solo visual. Las viviendas con carga de fuego agregada no se han
convertido por ello en inventarios físicos completos por objeto. CO/FED
conservan sus pendientes y no quedan validados por esta reforma.

Para las tandas automáticas: Godot mediante el monitor del proyecto, suites
secuenciales y mínimo de 6 GiB disponibles. No terminar procesos ajenos.
Si se cambia `sim/`, la publicación requiere además la referencia completa
R2-1 y comparación de informes; los cambios de carga de viviendas lo requirieron
y se verificaron en esta entrega.
No borrar archivos ajenos ni rebaselinear ciencia para hacer pasar una vista.

## 13. Decisiones que esperamos de la diseñadora

1. ¿Programarás el generador, entregarás arte/especificaciones o combinarás ambos?
2. ¿Qué conservarías y qué sustituirías del constructor visual actual?
3. ¿Qué técnica propones para paredes, huecos, losas y escaleras?
4. ¿Cómo quieres editar materiales, UV y sus escalas sin modificar código general?
5. ¿Qué contratos de unidades, ejes, pivotes y módulos necesitas por categoría?
6. ¿Qué aspectos deben poder configurarse por sala y por vivienda?
7. ¿Qué escena mínima usarás para que podamos revisar tu propuesta juntas/os?
8. ¿Qué necesitas que preparemos nosotros para empezar?

No hace falta resolver todas las preguntas antes de explorar una escena aislada.
Sí acordar los límites de integración antes de reemplazar el mundo jugable.

## 14. Documentos de continuidad

- [Plan de reforma V0–V5](../planning/VISUAL_3D_FP_CLEANUP_2026-10-07.md).
- [Guía práctica de assets FP](../../assets/fp/README.md).
- [Separación de viviendas jugables](../validation/PLAYABLE_HOMES_SEPARATION_2026-10-07.md).
- [Estado de trabajo y handoff](../HANDOFF_CURRENT_STATE.md).
- [Responsabilidades de presentación](../../view/README.md).

Este documento no congela la solución. Describe el punto de partida,
las limitaciones conocidas y las condiciones que debe respetar la propuesta.
