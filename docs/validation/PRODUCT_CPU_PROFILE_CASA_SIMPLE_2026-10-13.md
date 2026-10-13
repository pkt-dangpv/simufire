# Casa simple: diagnóstico CPU previo a rendimiento renderizado

Fecha: 2026-10-13. Base: e0b301da. Estado: diagnóstico CPU cerrado;
corrección visual y benchmark renderizado pendientes.

El usuario informa: 3D/FP fluido en pausa, tirón pequeño al abrir/cerrar
ventanas, caída muy fuerte con Play (estima 5 FPS; no medidos).
Antes de continuar el gate termodinámico, aislar el coste del camino real.
No se autoriza una corrección física por esa percepción.

Opciones guardadas leídas: Casa simple, apartamento planta 15 de 20, noche,
luces interiores ON, visibilidad ON, sin HVAC ni viento. No se modifican.
Primera medición con copia externa de esas opciones, no una casa diferente.
No se ha encontrado plantilla de editor en la ruta userdata predeterminada.

## Hipótesis y predicciones previas

1. Paso físico caro: el coste registrado del paso dominará el callback de
   Main incluso en 2D. Verificar, no atribuirlo automáticamente al solver.
2. Refresco visual caro: callbacks de estado/FP consumen una parte importante
   del tiempo y la acción en pausa reproduce el pico sin avanzar sim_time.
3. GPU/render: si los callbacks CPU son baratos, queda pendiente una medida
   renderizada. Un perfil headless no permite descartarlo ni estimar FPS.

Main llama engine.step y después refresca vistas/gráficas. Abrir/cerrar
solicita _update_views completo. En FP set_state incluye todas las aberturas,
muebles, humo, fuego, luces y HUD. El coste no se presume solo por la lista.

## Método limitado

Fixture independiente carga SimulationScene.tscn sin modificar Main, sim/,
escenas ni vistas. Desactiva solo el callback automático de Main y llama
su callback real 180 veces con dt=1/60 s. Las vistas mantienen sus cadencias
de producto. Comprueba exactamente tres segundos de avance de simulación.

Mide callbacks completos y el contador ya existente _step_time_us. Este
último no incluye todo el código posterior a su asignación y no permite
atribuir automáticamente la diferencia a las vistas.

Después mide 30 llamadas con estado congelado, tras tres warm-ups, de estado,
vistas, minimapa, HUD y subrutinas FP. No son 30 frames reales. Compara el
estado del motor antes/después para impedir que esas mediciones muevan física.
Alterna una ventana 30 veces en pausa por el handler real; exige sim_time fijo.

Cada vista se lanza por separado y secuencialmente, con temporales externos,
monitor existente, ejecutable normal y mínimo de lanzamiento 6 GiB. Sin
procesos ajenos, cambios de calidad ni optimización en esta entrega.

Reportar mediana/p95/máximo/media en ms por llamada. 16,67 ms es un presupuesto
orientativo de frame a 60 FPS, no una predicción de FPS desde estas muestras.
No medir GPU, latencia de input, cámara/movimiento completo ni draw calls en
headless. No atribuir PASS nuevo de referencia/producto/global a este ensayo.

Primeros controles: 2D paso físico mediano 5,112 ms; 3D set_state 322,303 ms;
FP mobiliario 312,386 ms y acción de ventana en pausa 642,419 ms. Tres
lanzamientos sanos. Son evidencia inicial, no FPS renderizados.

Predicción refinada antes del siguiente control: si domina el reparto de
mobiliario, llamar directamente normalize_room en todas las salas tendrá un
coste próximo al refresco completo. Actualizar salas sin esa rama reducirá
fuertemente el coste. Si no ocurre, medir las escrituras/creaciones de nodos.
No ocultar muebles ni simplificar producto como supuesto arreglo.
Se amplía solo el fixture con estos dos controles y se repiten las tres
vistas para que la evidencia final esté ligada a los mismos bytes publicados.

## Resultados finales

[Evidencia resumida](PRODUCT_CPU_PROFILE_CASA_SIMPLE_EVIDENCE_2026-10-13.json).
Tres lanzamientos finales secuenciales sobre el mismo fixture/launcher y
los mismos 1 235 hashes de archivos de runtime. Seis salas y once aberturas;
las veinte plantas son una opción del contexto visual, no veinte plantas
simuladas en este preset. No atribuir el coste a un solver de veinte plantas.
Equipo: Ryzen 7 5700U, 8 núcleos/16 hilos; AMD Radeon integrada, controlador
31.0.21923.11000. Este ensayo no mide su GPU. Árbol: 4 951 nodos (2D),
5 206 (3D) y 5 210 (FP); no confundir nodos con draw calls.

Medianas en ms por llamada (no FPS):

| Operación | 2D | 3D | FP |
| --- | ---: | ---: | ---: |
| Paso físico registrado | 5,21 | 5,27 | 5,40 |
| Construcción del estado de vista | 2,70 | 2,73 | 2,81 |
| set_state del visualizador 3D | — | 317,33 | 317,69 |
| set_state de FP | — | — | 316,19 |
| Mobiliario FP | — | — | 320,53 |
| Solo normalize_room de todas las salas | — | 311,79 | 313,72 |
| Actualizar salas sin rama de mobiliario | — | 0,66 | 0,67 |
| Acción de ventana en pausa | 5,62 | 322,13 | 648,35 |

Las llamadas se muestrean por separado: no sumar medianas ni restarlas como
si fueran partes del mismo frame. Hay variabilidad de carga del equipo:
FP set_state alcanza un máximo de 3 154,64 ms en las llamadas congeladas;
los p95/máximos completos se conservan, no se eliminan como ruido.

En el callback real en marcha, p95: 10,91 ms (2D), 322,81 ms (3D) y
639,63 ms (FP). Media: 6,61 / 45,54 / 135,19 ms respectivamente. La mediana
del callback ronda 5 ms porque muchas llamadas no vencen la cadencia de
refresco: usarla sola ocultaría los bloqueos periódicos.

Controles sanos: exactamente 180 callbacks y tres segundos simulados por
vista; estado de motor idéntico antes/después de los probes congelados;
abrir/cerrar en pausa no avanza tiempo. Todos returncode 0, stderr vacío,
sin errores de script, timeouts, cuadros, Godot residual, procesos ajenos
detectados o limpieza forzada; process_quiescent=true.

Registros raw fuera del repositorio, bajo LOCALAPPDATA/Temp:
simufire_product_cpu_2d_final_20261013/result.json,
simufire_product_cpu_3d_final_20261013/result.json y
simufire_product_cpu_fp_final_20261013/result.json. Sus hashes y los siete
archivos de código más relevantes figuran en la evidencia versionada.

## Causa y corrección siguiente

Queda demostrada una causa importante de bloqueo CPU: ambos visualizadores
vuelven a repartir los muebles a cada actualización de estado. El reparto
incluye búsquedas de huecos en cuadrícula y pasadas de separación; por sí
solo reproduce unos 312 ms. No es necesario calcular presión/combustión
para reproducir el bloqueo. No se demuestra que todo coste futuro del motor
sea pequeño ni se descartan cuellos GPU una vez corregido este.

La ruta de abrir/cerrar provoca un refresco completo; por eso reproduce el
coste en pausa. La colocación reserva la banda geométrica de la abertura,
no depende de open_fraction (doors_for_room, líneas 260–314). Cambiar la
apertura no exige resolver de nuevo dónde están todos los muebles.

Corrección recomendada, todavía no implementada:

1. Separar distribución/poses estables de estado dinámico. Reutilizar poses
   mientras no cambien los datos que realmente necesita el algoritmo.
2. Invalidar por geometría, aberturas geométricas, lista/tipos/tamaños/poses
   de objetos, política de relleno y contrato/dimensiones de assets; no por
   temperatura, humo, HRR, combustible restante o fracción de apertura por sí sola.
3. Seguir actualizando colores, carbonización, llamas, luces, hojas, colisiones,
   HUD y demás estado dinámico. No congelar el aspecto para ganar rendimiento.
4. Evitar calcular mobiliario oculto del overlay FP antes de comprobar que
   se va a mostrar. No basta hacer eso: FP también repite el reparto.
5. Probar identidad de salida frente a normalize_room sin caché, invalidación,
   copias independientes, cambio de edificio y reinicios; preservar los
   transforms de autor y detectar mutantes que devuelvan poses obsoletas.
6. Repetir este banco y después medir FPS/tiempos de frame renderizados,
   con cámara, resolución, modo y estado de fuego declarados.

No implementar esta corrección bajo un encargo de diagnóstico. No modificar
la física ni ralentizar/reducir sus pasos para ocultar el problema visual.

## Verificación y preservación

Nueve pruebas offline del arnés pasan; selección final con regresiones M4:
87 passed, cero fallos. Enlaces de los tres documentos y AST de dos Python
limpios. Guardarraíles monitorizados ALL PASS, R2-1 incluido.
Fuentes de producto y sim/ intactas;
79 UID del worktree y cuatro stashes preservados. Opciones de usuario intactas.
No se ejecutan ni se adjudican nuevas suites de referencia/producto/global;
sus resultados vigentes pertenecen a M4-P1. La referencia sigue siendo
346/346 con 78 gaps y debe comprobarse su guardarraíl de frescura al cerrar.
No publicar runs/, UID ni modificaciones ajenas del checkout principal.
