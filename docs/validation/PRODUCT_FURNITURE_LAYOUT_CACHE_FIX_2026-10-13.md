# Corrección visual del reparto repetido de mobiliario

Fecha: 2026-10-13. Base: 77a67507. Autorización: «haz la corrección».
Estado: corrección implementada y verificada; publicación mediante commit de esta fase.

[Diagnóstico previo](PRODUCT_CPU_PROFILE_CASA_SIMPLE_2026-10-13.md) y
[evidencia compacta](PRODUCT_FURNITURE_LAYOUT_CACHE_FIX_EVIDENCE_2026-10-13.json).
El diagnóstico anterior permanece histórico, sin sobrescribir sus mediciones.

## Contrato predeclarado y cambio aplicado

Reutilizar solamente diferencias de pose producidas por layout_room. Las
fichas dinámicas siempre son las actuales y se copian; no almacenar el estado
de combustión como resultado reutilizable. El algoritmo original de reparto,
dimensiones, transform de autor, tiempos físicos, calidad y escenarios no cambian.

Cuatro archivos de producción, todos en view/: FurnitureVisualLayout,
FurnitureAssetLoader, Visualizer3D y FirstPersonController. Sin cambios de
Main, sim/, editor, modelos de arte ni escenarios. La rama de mobiliario oculto
del overlay comprueba visibilidad antes de normalizar.

Clave binaria exacta de rectángulo, bandas geométricas de aberturas, fichas
preparadas e identidades/declaraciones de recursos PackedScene. Excluye sólo
state, hrr_kw, remaining_fuel_MJ, temp_c, surface_temp_c, temperature_c,
incident_heat_flux_kw_m2, t_ignition_s e is_primary_ignition_source: ninguno
se lee al decidir la colocación. Campos desconocidos invalidan conservadoramente.
Lista, orden, tipos, poses y resultados de política de relleno cuentan.

Sólo se guardan diferencias de pose, copiadas profundamente; cada respuesta
las combina con las fichas frescas. WeakRef no retiene edificios; se eliminan
propietarios muertos. Máximo 128 salas y una versión por sala, con expulsión
FIFO; máximo 128 recursos retenidos para estabilizar sus identidades.
PackedScene.changed y reconstrucción de las vistas invalidan posiciones y
la caché de tamaños nativos. No se escriben assets ni se congelan datos de fuego.
Abrir/cerrar sin cambiar la geometría de paso reutiliza el reparto.

## Verificación y falsación

Oracle sin caché con el mismo algoritmo original (hash fijado), comparación
completa por var_to_bytes, entradas inmutables y salidas independientes.
Control final: 560 comprobaciones, cero fallos; nueve campos dinámicos,
geometría, aberturas, orden, relleno, propietarios, recursos y reconstrucción.
Incluye las diez viviendas distribuidas, en frío y con reutilización, y el
recurso de referencia de transform de autor.

11/11 mutantes GD válidos detectados en la comprobación declarada: sin
reutilización, claves incompletas, estado obsoleto, alias, recursos/rebuild
sin invalidar, propietario muerto y límite ausente. Ninguna muerte por error
de script/nativo; restauración SHA-256 y bytes de cada variante comprobados.
13 pruebas offline focalizadas aprobadas (cuatro de caché, nueve del banco).
Después de documentar: 54 guardas offline de contratos/inventarios PASS.
Producto: 168/168 PASS (570,36 s). Global autoritativa: 5 078 passed,
78 skipped, 2 xfailed y 42 subtests; exit 0 (909,61 s pytest, 913,36 s monitor).
Registros de salud limpios, stderr vacío, sin timeouts, cuadros, terminaciones
de limpieza, procesos ajenos ni Godot residual. Lanzamientos con 6,65/6,67 GiB;
el umbral de 6 GiB y los temporales externos permanecen intactos.

Guardarraíles ALL PASS, R2-1 incluido. Referencia vigente 346/346, 78 gaps;
sin regeneración ni cambio de generated_at: no se tocó sim/. El wrapper de
cierre existente se reutiliza sólo para ejecución monitorizada y conservación;
la admisión de esta corrección visual se vincula por separado a su control y
campaña actuales, no se confunde con la evidencia física de la fase anterior.

## Comparación CPU, misma Casa simple

Banco publicado sin cambios: seis salas, once aberturas; apartamento 15/20,
noche. 180 callbacks reales de Main, dt 1/60 y horizonte de 3 s. Después,
30 llamadas congeladas por métrica con tres calentamientos; acción real de
ventana en pausa. Estado físico congelado invariante y opciones originales
sin modificar. Sólo difieren los cuatro archivos visuales del inventario
de producto de 1 235 fuentes; los restantes, incluidos Main/sim, son idénticos.

| Mediana CPU (ms) | Antes | Después |
|---|---:|---:|
| Paso físico, 3D | 5,27 | 5,15 |
| Reparto de mobiliario, 3D | 311,79 | 3,81 |
| Refresco 3D completo | 317,33 | 7,11 |
| Refresco FP completo | 316,19 | 6,16 |
| Ventana en pausa, 3D | 322,13 | 13,53 |
| Ventana en pausa, FP | 648,35 | 10,62 |

Supera el objetivo predeclarado de diez veces el refresco caliente: 44,6× en
3D y 51,4× en FP. El callback real durante marcha baja su p95 de 322,81 a
52,00 ms en 3D y de 639,63 a 48,33 ms en FP; máximos actuales 63,74/55,55 ms.
Todos los estadísticos, incluidos máximos, quedan en la evidencia.

## Límites y siguiente paso

CPU headless, no FPS renderizados ni tiempos GPU. No afirmar 60 FPS ni que
la jugabilidad completa esté validada; siguen existiendo callbacks de unos
50 ms. El reparto en frío, cambios geométricos y expulsiones siguen recalculando.
La invalidación de recursos cubre señales changed y rebuild, no constituye
un sistema nuevo de importación/hot reload de arte.
Siguiente: comprobar Casa simple renderizada en 3D/FP y con Play, incluidas
puertas/ventanas; si persisten tirones, medir esa ruta sin tocar física por intuición.

## Intentos que no son el cierre

Una prueba offline inicial buscaba literalmente una etiqueta construida por
el helper: 1 failed/12 passed. Se corrigió la comprobación de admisión antes
de la campaña final. Un primer control/campaña con seis exclusiones dinámicas
pasó; se ampliaron a los nueve campos reales y se repitieron control y once
mutantes sobre los bytes finales. Esos registros anteriores no son evidencia
final. No se rebajó el mínimo de 6 GiB ni se lanzaron suites nativas en paralelo.
Las guardas offline adicionales tuvieron dos intentos de preparación fallidos:
52 passed/2 errors por directorio temporal del sandbox y, después, por padre
inexistente del basetemp. Ninguna aserción de código falló; con basetemp nuevo
directamente bajo Temp terminaron las 54, exit 0. La global monitorizada previa
ya era completa y válida, con temporales externos correctos.

## Conservación y retomada

UID generados y stashes ajenos se conservan; fuera del commit, igual que
runs/ y project.godot del checkout principal. CO/FED siguen OFF/NO-GO.
El gate gas/energía/EOS continúa pendiente tras la comprobación de jugabilidad.
Los registros finales externos se identifican por nombre y SHA-256 en la
evidencia compacta; el launcher/control y la campaña están versionados para repetirlos.
Hashes raw identifican los archivos ejecutados; hashes LF normalizan CRLF a
LF para contrastar el contenido versionado, sin confundir ambos contratos.
