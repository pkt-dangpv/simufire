# Limpieza de representación 3D y primera persona

Estado: autorizada el 07-10-2026; V0 verificado en runtime y V1 con prototipo
optativo. Migración del catálogo, edificio común y extracción FP pendientes.
No es una corrección de física. Cadena de publicación técnica completada el
08-10-2026 para viviendas, herramientas y prototipo; no para la reforma entera.

Entrega a la diseñadora:
[guía del sistema actual y objetivo de reforma](../architecture/GUIA_REFORMA_VISUAL_3D_FP_DISENADORA_2026-10-07.md).
Incluye alternativas de implementación, polígonos/UV/materiales y decisiones
abiertas; no autoriza borrar el sistema ni presenta V2 como implementada.
La entrega documental inicial se publicó por separado en `dd9390a9`.
El usuario autorizó después código, escenas, pruebas y viviendas, con commit
y push condicionados a una cadena completa verde; resultado registrado abajo.

## Problema comprobado en código

Un asset no llega directamente de su escena al juego. Pasa por clasificación,
dimensiones por arquetipo, ajuste a caja, distribución de sala y construcción
de vista. Se pueden aplicar giros y cambios de tamaño en varios de esos pasos.
No sabemos todavía qué asset concreto observó la diseñadora: no atribuimos
su incidencia a una única regla sin una reproducción.

| Elemento | Dueño actual | Qué hace |
| --- | --- | --- |
| Tamaño solicitado | `FurnitureDimensions` | Impone talla por arquetipo, a veces usando la huella del escenario |
| Malla importada | `FurnitureAssetLoader` | Puede girar 90°, escalar por eje y cambiar el origen; cocinas por módulos |
| Pose en sala | `FurnitureRoomLayout` / `FurnitureRoomGrammar` | Recoloca, gira, reduce o esconde atrezo; respeta algunas poses bloqueadas |
| Último ajuste | `FurniturePlacement3D` | Encoge y centra piezas no bloqueadas antes de dibujarlas |
| Paredes de maqueta | `RoomShellFactory` | Cuatro cajas de representación; no equivale al muro transitable FP |
| Paredes FP | `FirstPersonController._create_walls` | Divide muros por huecos y añade representación y colisión |
| Suelos / huecos | `SlabGeometry` | Reglas compartidas de losas y vacíos; consumidores 3D y FP |
| Escalera / portal real | `StairGeometry` / `PortalGeometry` | Reparte tramos y rellano desde salas y conexiones |
| Contexto fuera de vivienda | `FirstPersonController._create_landing_recess` y exterior | Generación visual adicional; no toda ella es un recinto del motor |

Los comentarios existentes que llaman «real» a una medida son una intención
de diseño, no una garantía de que coincida con el modelo de la artista.

## Resultado buscado

- La diseñadora puede abrir un banco de pruebas, comparar original y resultado
  y conocer exactamente quién cambió escala, orientación, origen y posición.
- Un contrato de asset declara unidades, ejes, pivote y políticas de ajuste.
  Ningún giro ni deformación se deduce silenciosamente de su lado más largo.
- La talla visual no es la huella combustible. No se cambian MJ, HRR, CO/FED,
  perfiles de física ni fixtures científicos para encajar una malla.
- Las dos vistas consumen la misma descripción geométrica. La maqueta puede
  ocultar techo o usar transparencia, pero no inventar otra planta.
- FP coordina cámara, movimiento e interacción; no concentra toda la generación
  de edificio, muebles, ciudad y materiales en un solo controlador.

## Orden de trabajo y gates

### V0 — Medir y explicar (fase actual)

Conservar WIP de viviendas, inventariar rutas y disponer de inspección y banco
visual usando el cargador real. Medir escena original, tamaño pedido, tamaño
dibujado y transformaciones aplicadas. Registrar por separado importación,
ajuste y distribución. No cambiar ni migrar assets por comparación de nombres.

Aceptación: el inspector identifica un giro de 90°, escala desigual y cambio
de origen en casos controlados; inspeccionar no modifica escenas ni escenarios.
El banco compara a un metro/unidad y sin autoamueblado.

### V1 — Contrato de asset y pose explícita

Fijar escenas en metros, raíz identidad, eje vertical +Y, frente declarado y
pivote de suelo o bisagra según categoría. Las correcciones de importación se
declaran en el wrapper, no se vuelven a inferir en ejecución. Definir políticas
distintas: conservar autoría, escala uniforme explícita, módulos y adaptación
paramétrica autorizada. No trasladar a puertas el pivote centrado de un sofá.

Separar colocación manual de autoamueblado. La pose manual conserva posición,
giro y talla; si no cabe, se avisa, no se corrige sin consentimiento. La pose
automática se resuelve una vez y se comparte, sin volver a ajustarla en FP/3D.
Debe conservarse tras guardar/cargar y al actualizar el estado del incendio.

Migrar primero un asset reproducible, comparar antes/después y luego el
catálogo. No apagar de golpe el ajuste antiguo: los GLB actuales tienen
tallas distintas y algunos dependen de él. Marcar compatibilidad legacy.

### V2 — Descripción común del edificio

Una entrada produce segmentos de pared, huecos, losas, techos, tramos y
rellanos con identificadores estables y cotas en metros. Las vistas construyen
mallas desde esa salida; FP crea también colisiones desde las mismas medidas.
Reutilizar geometría existente, no reescribirla con nuevas fórmulas paralelas.

Distinguir hall interior, portal modelado y contexto decorativo exterior.
El contexto no puede duplicar una escalera/portal existente ni cerrar un acceso.
Los elementos generados exponen procedencia: sala/hueco/regla que los creó.

### V3 — Extraer responsabilidades de FP

En cambios pequeños y verificables, extraer construcción de edificio, apertura,
mobiliario, contexto y materiales. Mantener contratos públicos mientras se
migran consumidores. Comparar poses, cajas de colisión e inventarios de nodos
antes/después; no aceptar un refactor por bajar el número de líneas solamente.

### V4 — Aceptación visual y navegación

Comparar original/runtime, editor 3D/FP, plantas y persistencia. Casos: objeto
asimétrico, pivot desplazado, pose girada, mueble que no cabe, puerta con ambas
bisagras, techo con hueco, hall explícito, portal decorativo y escalera en U.
Recorrer puertas y subir escaleras mediante la física real del jugador.
La comprobación headless no sustituye capturas y revisión humana de estética.

### V5 — Cierre y publicación

Cerrar primero aceptación nueva y contratos afectados; después producto y
pytest global secuenciales bajo monitor. Si se toca `sim/`, referencia completa
R2-1, 346 required PASS / 78 gaps y comparación de informes, sin rebaseline.
Conservar cambios ajenos, inspeccionar staged y publicar únicamente lo probado.
Las viviendas no se publican como terminadas antes de sus propios gates.

## Límites operativos

Godot bajo monitor, al menos 6 GiB disponibles, sin procesos ajenos concurrentes.
No ejecución ni limpieza global de procesos. No borrar assets ni reescribir
su importación masivamente. No cambiar por defecto física experimental.

Ruta de continuidad: [handoff](../HANDOFF_CURRENT_STATE.md).
Trabajo preservado: [viviendas](../validation/PLAYABLE_HOMES_SEPARATION_2026-10-07.md).
Guía de entrada para arte: [assets FP](../../assets/fp/README.md).

## Checkpoint de esta pasada

- Base `2e5d764a`, rama `codex/playable-homes-isolated`; WIP de viviendas
  conservado sin commit/push. No se eliminó ningún asset.
- La importación/aceptación de viviendas fue interrumpida por el usuario al
  cambiar de foco. Comprobación posterior: sin Godot en marcha.
- Escritos `FurnitureAssetInspection.gd`, inspector de catálogo y banco de
  comparación de arte. Usan el cargador existente, sin cambiar sus leyes.
- Fixture nuevo: controles de giro 90°, escala desigual, origen y AABB anidado;
  prueba Python con hashes de escenas/GLB antes/después. Ejecutado tras liberar
  memoria; resultado final registrado debajo.
- La importación para validar V0 fue rechazada antes de lanzar Godot:
  3,48 GiB disponibles frente al mínimo de 6. No equivale a un fallo del asset.
- V1 tiene prototipo optativo, descrito debajo. V2–V5 no iniciadas. No hay
  migración del catálogo ni refactor FP cerrado.

## Evidencia real de V0

Importación monitorizada y pruebas del inspector, catálogo y arranque del banco
con memoria liberada. 38 arquetipos inspeccionados; todos conservan el modo
legacy. Las cajas informadas por el cargador coinciden con las dibujadas, pero
no siempre con la talla solicitada. Ejemplos (X, altura Y, Z en metros):

| Pieza | Caja del archivo | Destino solicitado | Resultado |
| --- | --- | --- | --- |
| Cama | 0,956 × 0,375 × 1,125 | 2,00 × 0,55 × 1,50 | 2,00 × 0,55 × 1,50, giro interno +90° |
| Sofá | 0,980 × 0,460 × 0,410 | 2,10 × 0,85 × 0,90 | Escalas X/Y/Z: 2,143 / 1,848 / 2,195 |
| Frente cocina | Módulo 0,430 × 0,450 × 0,450 | 1,80 × 0,90 × 0,60 | 1,80 × 0,781 × 0,623, tres módulos |

No se conoce la dimensión física que quiso dar la autora a esos GLB. La tabla
demuestra ajustes del código, no una calibración de mobiliario.

El inspector inicial destruía mallas con materiales duplicados y producía
errores del renderer dummy. Se conservaron referencias a materiales hasta
destruir las instancias. Las primeras tres pruebas solo rechazaban errores
de script: ese verde era insuficiente. Ahora rechazan **cualquier `ERROR:`**,
además de fallo del monitor, y se han repetido. No se silenciaron mensajes.

## Prototipo V1 — Conservación de autoría

`VisualAssetContract.gd`, cargador y reparto de sala reconocen el contrato
`authored_meters_v1`, declarado en raíz del wrapper. Valida raíz identidad,
caja positiva/finita, centro horizontal y base en cero, frente -Z explícito.
No adivina el frente por el eje largo ni modifica silenciosamente un pivote.

El asset válido no recibe ajuste al destino, giro interno ni deformación.
Las vistas solo convierten metros a unidades. El reparto conserva centro y
giro de la ficha; el nuevo tamaño visual no se escribe a la ficha combustible.
Los consumidores FP/3D reciben una pose bloqueada y no hacen un segundo clamp.
Conflictos de límite de sala/paso de puerta se registran y avisan, sin encoger.

Una pieza sintética aislada en `assets/fp/examples/` verifica la implementación,
incluyendo los consumidores reales y actualización de estado con entradas
sintéticas. No está en el catálogo de objetos combustibles. Ningún wrapper
legacy ni GLB del catálogo se ha migrado. La elección de una pieza real y su
revisión con la diseñadora siguen pendientes.

Límites: no nueva interfaz de avisos; no hot-reload de cachés certificado; no
colisión exhaustiva entre poses manuales; no contratos de hojas o piezas
paramétricas; no persistencia editor-modelo de nuevas fichas visuales separadas.
No presentar V1 entero como cerrado.

Verificación inicial del 07-10-2026 (sustituida por la cadena del 08-10):

- 67 passed / 42 subtests: inspección y banco (3 pruebas Godot), aislamiento
  de viviendas y contratos estáticos de autoría/editor.
- Fixture de contrato: 41 comprobaciones, consumidores FP/3D con estado sintético.
- Inspector: 38 arquetipos, sin reescritura de escenas/GLB (hashes antes/después).
- Guardarraíl histórico runtime de muebles: PASS.
- Guardarraíl histórico de distribución: PASS, 320 piezas (277 de atrezo).
- Monitor de estas tandas: exit 0, sin fault, timeout, cuadro ni residuo.
- Dos errores de compilación propios durante el desarrollo (orden de
  `class_name` y uso de Dictionary como Rect2) detectados y corregidos;
  la tanda final se repitió sobre el código corregido.

## Cierre técnico de publicación — 08-10-2026

- Focal final: 70 passed / 42 subtests; inspector y banco, autoría/editor y
  viviendas. Catálogo de 38 arquetipos sin reescritura de escenas o GLB.
- Contrato sintético: 41 checks. Control modular inválido: tres checks; antes
  dejaba piezas y devolvía éxito, ahora rechaza y no dibuja ninguna. Se exige
  exactamente el mensaje de rechazo esperado; los casos normales no admiten
  ningún `ERROR:`. No se silenciaron errores genéricos.
- Diez viviendas: 2.804 comprobaciones sobre FP, 359 piezas visibles, 316
  de atrezo. Control causal de pieza fuera del recinto detectado.
- Referencia: 18/18 ejecuciones sanas, 346/346 required PASS, 78 gaps y R2-1
  verde. Comparación de 185 JSON del corpus contra `dd9390a9`: solo diferencias
  LF/CRLF; en `reference_checks.json` cambia únicamente `generated_at`.
- Producto completo: 168/168. Global autoritativa: 4.241 passed, 53 skipped,
  2 xfailed, 42 subtests, exit 0 en 671,31 s.

La referencia cubre los cambios finales en `sim/`. Después solo se corrigió
la ruta de rechazo modular de `view/` (tres líneas) y su control negativo;
focal, producto y global se ejecutaron de nuevo sobre ese estado final.
Todas las tandas Godot fueron secuenciales, con monitor, mínimo de 6 GiB y
temporales externos. Código estable por hash durante la cadena global.

V0 está verificado y V1 tiene un prototipo distribuible, no una migración real
del catálogo. Este cierre solo satisface el gate de publicación de esa entrega.
V2/V3, aceptación visual humana V4 y cierre integral V5 siguen pendientes.
Siguiente paso: revisar un asset real con la diseñadora y decidir geometría,
polígonos/UV y arquitectura compartida, sin borrar el sistema existente.
