# Minimapa: expulsión mutua del layout durante Play

Fecha: 2026-10-13. Base: 9468f486. Autorización: continuación del arreglo de
jugabilidad tras «va mejor pero sigue siendo injugable». Usuario: Casa simple,
3D y FP, desde el primer instante de Play.

Estado: hotfix focalizado implementado; no equivale a cierre de jugabilidad.
[Primera corrección](PRODUCT_FURNITURE_LAYOUT_CACHE_FIX_2026-10-13.md) permanece
histórica. [Registros y estadísticos](PRODUCT_MINIMAP_LAYOUT_THRASH_EVIDENCE_2026-10-13.json).

## Diagnóstico demostrado

Banco nuevo con ventana Windows real, GL Compatibility, AMD Radeon integrada,
1280×720 y las opciones guardadas originales. Tres fases de al menos ocho
segundos de reloj real: pausa antes, Play y pausa después. Una sonda llama
al método real de Main una vez por callback físico natural; desactiva sólo
el callback automático de Main para no duplicarlo. FP y las animaciones
mantienen sus callbacks normales. No cambia dt, 60 ticks/s, tope de ocho
pasos por fotograma, vsync ni calidad del caso normal.

Frames medidos por frame_post_draw. CPU/GPU de viewport mediante
[RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-set-measure-render-time),
con medición habilitada; cero de un contador se declara desconocido, no coste
nulo. El CPU de Main se mide aparte: el contador de render no incluye scripts.

3D antes: 60,05 FPS en pausa, 6,64 con Play y 60,09 al pausar de nuevo.
Motor mediano 5,23 ms por paso; Main acumula 93,05 ms medios por fotograma,
hasta ocho pasos. GPU mediana 3,82 ms: no demuestra saturación GPU como causa
de esta caída. Sólo avanza 6,73 s simulados en 8,03 s reales.

La caché registra 606 fallos y 504 aciertos durante Play. Las claves alternan
sólo su componente de fichas: once campos pasan de ausentes a presentes y
viceversa (room_id, elevation_m, fuel_energy_MJ, max_hrr_kw, alpha_kw_s2,
critical_heat_flux_kw_m2, heat_of_gasification_kj_kg, heat_of_combustion_kj_kg,
soot_fraction, co2_yield_kg_per_MJ y chi_rad_normal). Ninguna señal de recurso
changed. ui/Minimap2D construía fichas abreviadas desde el modelo en _draw,
mientras 3D/FP consumían las fichas completas. Con una versión por sala,
cada ruta expulsaba a la otra aunque los muebles no se movieran.

El banco headless anterior no garantizaba esta ruta renderizada: set_state
encola queue_redraw, no ejecuta el dibujo dentro de la llamada cronometrada.
Sus medidas anteriores no se borran ni se reinterpretan como FPS.

## Control causal antes de corregir

Minimapa oculto sólo en la copia diagnóstica, declarado como cambio visual del
control: 58,15 FPS durante Play, cero fallos de caché y 360 aciertos. Resto de
motor, renderer y opciones intactos; 8,02 s simulados en 8,01 s reales.
El máximo aislado de intervalo sigue siendo 118,69 ms, no se omite.
Este control no es el arreglo: el producto conserva su minimapa.

## Corrección de producción y pruebas

Un solo GD de producción: ui/Minimap2D.gd. El dibujo obtiene una copia profunda
de fuel_objects del estado recibido, igual que las otras vistas. Si no hay
una instantánea de array, conserva exactamente la reconstrucción histórica
desde RoomModel. Un array vacío válido no se sustituye por otro origen.
No cambia el layout, sus claves conservadoras, límites, poses, transforms,
materiales, shaders, geometría, fuego, física ni escenarios.

El control nativo ampliado alterna los dos consumidores durante 24 cambios
de estado; exige identidad completa, reutilización, copia independiente,
fallback y vacío autoritativo. 730 comprobaciones PASS. Los doce mutantes
GD válidos mueren en sus comprobaciones declaradas, con restauración SHA.
C12 devuelve el esquema histórico del minimapa: vuelve a fallar la identidad
de fichas y la reutilización. No cuenta un error de sintaxis como muerte.
23 focales offline PASS (bancos CPU/render y caché).
Tras documentar, otras 54 guardas offline de contratos/inventarios PASS.

## Resultado renderizado con minimapa visible

3D: 46,22 FPS durante Play, 60,06 antes y 60,05 después. Cero fallos de caché,
1 326 aciertos; 8,00 s simulados en 8,02 s reales. Main medio por fotograma
10,84 ms; p95 de intervalo 37,74 ms, máximo 121,87 ms. GPU mediana 3,58 ms.
La observación de caché cuesta 0,070 ms medios por fotograma tras corregir;
antes 0,333 ms frente a intervalos medios de 150,53 ms.

Mejora demostrada, no garantía de 60 FPS ni de incendios desarrollados:
sólo ocho segundos reales de Play, cámara inicial y este equipo/opciones.

## FP y límites de cierre

FP NO tiene una corrida renderizada aceptada. Todas las pruebas de ese banco
salen con código de proceso 0 y sin cuadros, timeouts ni procesos residuales,
pero stderr contiene dos errores de textura GL al salir, 349 524 bytes cada
una. No atribuirlos a NoiseTexture2D o al driver sin aislar la causa.

Datos provisionales de las trazas rechazadas: 6,94 -> 24,65 FPS durante Play;
348 -> 0 fallos de caché. No se cuentan como PASS ni como rendimiento limpio.
Los dos avisos ya existen antes del cambio del minimapa. Desconectar los
observadores, vaciar recursos retenidos, liberar nodos de forma síncrona
y esperar antes de salir no los eliminó. Ningún shader ni módulo FP se tocó.

Además, la sesión real del usuario dejó un error distinto al cerrar:
_show_technical_summary_window intenta popup_centered fuera del árbol desde
_exit_tree del motor. Pendiente separado; no explica el bloqueo desde Play.

## Cadena final y retomada

Producto 168/168 PASS (559,45 s); global 5 090 passed / 80 skipped /
2 xfailed / 42 subtests, exit 0 (916,42 s pytest, 921,18 s monitor).
Salud de estas regresiones limpia, stderr vacío; sin cuadros, timeouts,
terminaciones de limpieza ni procesos Godot residuales. No confundir esta
salud con el stderr de las corridas FP rechazadas descritas arriba.
Guardarraíles ALL PASS, R2-1 incluido; referencia 346/346 y 78 gaps intacta,
sin regenerar ni modificar generated_at. Wrapper histórico reutilizado
sólo para ejecución segura/conservación; el control y la falsación del
minimapa están vinculados por separado a los bytes actuales.
GO sólo al hotfix del minimapa; NO-GO al cierre general de jugabilidad o
validación renderizada de FP. Se publica este alcance acotado.

UID, cambios de project.godot y stashes ajenos quedan preservados y excluidos.
Los artefactos externos se identifican por ruta relativa a Temp y SHA-256.
Hashes raw atan el checkout ejecutado; LF normaliza CRLF para el blob Git.

Intentos no finales: primer timer contabilizó el delta previo y dejó una
pausa de 7,896 s; corrida rechazada, reloj corregido sin rebajar el gate.
Las cuatro corridas FP rechazadas se conservan, no se borran ni blanquean.

Siguiente: rendimiento sostenido/per-componentes de FP y causa de los dos
avisos GL, con controles independientes. No bajar calidad/cadencia ni activar
física para aparentar velocidad. Jugabilidad general sigue pendiente; gate
gas/energía/EOS aplazado y CO/FED OFF/NO-GO.
