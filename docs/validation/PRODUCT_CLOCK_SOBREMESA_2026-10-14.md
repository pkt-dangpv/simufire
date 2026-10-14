# Reloj y paso temporal: pruebas en SOBREMESA, 14 de octubre de 2026

La corrección del reloj conserva el tiempo al cambiar de velocidad. La comparación numérica independiente **no respalda sustituir 1/60 s por 1/12, 1/30 o 1/40 s** en todo el escenario ensayado. Primera persona queda pendiente de una medición admitida: sus dos ejecuciones renderizadas terminan con errores de texturas de Godot.

## Código y alcance

Pruebas iniciales sobre `6633ff78444e8a77c1fcff48f558d04759d07d40`, en la rama `codex/motor-clock-validation`, dentro de `C:\Users\dangp\.codex\worktrees\motor-clock-validation\simufire`, fuera de OneDrive. Después se aplicó la corrección en la carpeta habitual de OneDrive, como se detalla a continuación. Los archivos del portátil no se han eliminado.

### Aplicación posterior en OneDrive

El usuario pidió aplicar la corrección en su carpeta habitual. Se integraron los siete commits locales de `1c2389c9`, los dieciséis commits pendientes del portátil disponibles en `origin/main` (`6633ff78`) y la corrección probada (`21c4e8d4`). La integración `06061172` se aplicó por avance directo a `main` en `F:\OneDrive\Documentos\GitHub\simufire`, preservando ambos historiales y los archivos locales. El estado anterior queda en `codex/backup-onedrive-main-20261014-153905`. No se ha hecho push al remoto.

Comprobaciones ejecutadas directamente en OneDrive: importación monitorizada sin errores; reloj **73.948/0**; gráficas **26/0**; Python **343 aprobadas y 306 subtests aprobados**; salvaguardas existentes aprobadas. Los bytes de los diez archivos editados de código y pruebas coinciden con los probados inicialmente. No se repitió toda la batería física ni la medición renderizada. Evidencia: `product_clock_onedrive_application_2026-10-14.json`, junto a este informe; registros completos en `onedrive_application/` bajo la ruta de evidencia indicada más abajo.

Equipo: Ryzen 5 5600X, 6 núcleos/12 hilos, RTX 3070, Windows 11 Home, aproximadamente 48 GiB de RAM. Godot 4.7.1 oficial. No se liberó RAM. Los lanzamientos nativos fueron secuenciales mediante el monitor existente, con comprobación de procesos previos, memoria disponible, errores y procesos residuales.

La evidencia detallada se conserva en:

`C:\Users\dangp\.codex\visualizations\2026\10\11\01a12c70-46e7-75e0-9d35-a476a3e6d676\motor_tests_2026-10-14`

No se modificó ningún archivo físico bajo `sim/`, ninguna referencia ni los criterios científicos oficiales. Estos casos nuevos son independientes del guion inédito del portátil; sus cifras no deben confundirse con las de aquel guion. No se activaron nuevas funciones experimentales ni se trasladó el motor a otro hilo.

## Corrección del reloj

Antes de corregir: cuatro callbacks de 1/60 s a ×1 y uno a ×20 debían acumular 0,40 s; se observaron 1,6666667 s. El acumulador anterior guardaba segundos reales y los reinterpretaba con la velocidad nueva.

`Main.gd` ahora acumula segundos simulados con la velocidad de cada callback y mantiene otro acumulador para el tiempo real de las gráficas. Al despachar, convierte el tiempo simulado al argumento que espera el motor. No cambia la ley física ni el paso objetivo de 1/12 s existente.

- Control nativo: **73.948 comprobaciones, cero fallos**. Incluye las siete velocidades, las 49 transiciones ordenadas con cinco fases pendientes, callbacks variables, paso fijo, pausa y tiempo real de las gráficas.
- Cinco defectos introducidos deliberadamente: **5/5 detectados en la aserción declarada**. No cuentan los errores de compilación ni de infraestructura como detecciones válidas. Restauración de los bytes originales verificada por SHA-256.
- Gráficas en primera persona: control nativo de **26 comprobaciones** y **5/5 defectos detectados**, con restauración exacta.

Son pruebas del despachador y de la interfaz. El reloj del control se observa mediante una sonda que hereda la clase real del motor; no es una validación de incendios ni una medición de FPS.

Evidencia: `clock_baseline/`, `clock_corrected/`, `clock_mutations/results.json`, `fp_chart_mutations/results.json`.

## Comparación numérica de pasos

Diez ejecuciones nativas: dos escenarios, cada uno con pasos de 1/60, 1/12, 1/30 y 1/40 s, más una repetición de 1/60 s. Casa simple de seis salas, apartamento en planta 15 de 20, sin viento, sin HVAC ni rotura de cristales, misma semilla, ignición en sala 0 y 180 segundos simulados. En el segundo escenario se cierra la puerta salón/pasillo a los 45 s y se reabre a los 90 s.

Las referencias de 1/60 s se repiten **exactamente** en ambos escenarios. Todas las ejecuciones producen valores finitos y conservan el reloj. Los SHA-256 de los archivos físicos permanecen iguales antes y después.

Cada candidato se compara una vez por segundo, en seis salas y once magnitudes: HRR, temperaturas superior e inferior, humo, CO superior, oxígeno superior e inferior, altura de humo, energías superior e inferior y calor liberado. Son 11.880 comparaciones por escenario.

| Escenario | Fuera de tolerancia, 1/12 s | 1/30 s | 1/40 s |
|---|---:|---:|---:|
| Puertas abiertas | 1.957 | 755 | 599 |
| Cierre y reapertura | 782 | 851 | 846 |
| Total de 23.760 por candidato | 2.739 | 1.606 | 1.445 |

Las tolerancias exploratorias se fijaron en `plan.json` antes de recopilar las trazas: suelo absoluto más porcentaje del valor de referencia. HRR 5 kW + 2%; temperaturas 5 °C + 2%; humo 0,002 kg + 5%; CO 20 ppm + 5%; oxígeno 0,002; altura 0,05 m + 2%; energías 100 kJ + 5%; calor liberado 50 kJ + 2%. **No son criterios oficiales calibrados de aceptación física.**

Ejemplo con 1/40 s y puertas abiertas: la temperatura superior en sala 4, a los 137 s, es 50,52 °C frente a 22,72 °C con 1/60 s. El HRR puede coincidir razonablemente mientras otras magnitudes espaciales difieren.

Conclusión limitada: no se ha demostrado equivalencia temporal con ninguno de los tres pasos mayores. Tampoco se demuestra que 1/60 s sea la solución física exacta. No procede dar por validada la agrupación del motor solo porque acelere el producto o conserve el reloj. La comparación usa velocidad ×1 y no valida todas las velocidades del producto.

Evidencia: `convergence_corrected_fixture/plan.json`, `result.json`, diez `trace.json` con registros y salud, y `convergence_reanalysis.json`. La revisión posterior del comparador rechaza valores no finitos y campos desordenados; su reanálisis coincide exactamente con los resultados originales.

El primer intento del guion falló por comparar un tipo enumerado de puerta con texto y agotó el tiempo del monitor. Se corrigió y se repitió toda la serie; aquel intento no se cuenta como fallo del motor. El guion ejecutado está archivado como `product_step_convergence.executed.gd`. Después se corrigió además el orden de la supresión de gráficas al cerrar, que `reset_simulation` reiniciaba.

## Rendimiento renderizado

Ventana real, renderizador Compatibility/OpenGL, RTX 3070. Tres fases de ocho segundos: pausa, marcha a ×1 y pausa; misma configuración y calidad, sin desactivar mobiliario ni minimapa. Es una prueba breve del arranque, con cámara fija; no cubre incendios avanzados ni toda la navegación.

| Vista 3D | Pausa inicial | Marcha | Pausa final |
|---|---:|---:|---:|
| FPS medios | 633,9 | 504,2 | 614,7 |
| Intervalo p95, ms | 2,478 | 3,017 | 2,113 |
| Intervalo máximo, ms | 3,464 | 229,945 | 3,422 |

En marcha: 95 pasos efectivos del motor; mediana 4,332 ms, p95 6,726 ms y máximo 8,108 ms por paso. La instrumentación distingue los callbacks sin paso del motor, evitando repetir su último coste como si fuese una ejecución nueva. El pico de intervalo de 229,945 ms convive con un pico medido de render CPU de 217,284 ms; estas medias altas de FPS no descartan tirones.

Primera persona: **dos intentos descartados**, ambos con dos mensajes `Texture with GL ID ... leaked 349524 bytes` al destruir el renderizador. No se silenció el error ni se publican sus FPS como una medición aprobada. La causa de esas fugas y el rendimiento admitido de FP siguen sin resolver; estas pruebas no justifican todavía una migración del motor a segundo plano.

Evidencia: `render_3d/result.json`, `render_fp/` y `render_fp_repeat/` con salida y salud completas.

## Regresiones

- Producto: **168/168 pruebas aprobadas**.
- Salvaguardas científicas existentes: **346/346 checks requeridos**, sentinelas, integridad CFAST, vigencia e inventario de gaps aprobados. Es verificación de los informes existentes, no una nueva ejecución de toda la suite física oficial.
- Batería general de Python: **5.360 casos aprobados, 102 omitidos y 2 fallos esperados**, combinando la ejecución completa con la repetición de los 64 casos afectados por el entorno. No es una única ejecución completamente verde.
- Limpieza del guion numérico: control nativo de un segundo aprobado; sin generar gráficas ni dashboard al salir.

La primera recogida de Python se detuvo por faltar `pandas`. Se instaló en la carpeta externa `python_dependencies`, con pandas 3.0.6 y numpy 2.5.4, sin instalación global. Con esa dependencia se recogieron 5.464 pruebas.

Evidencia: `product.log`, `guardrails.log`, `pytest_complete.log`, `final_checks.json`, `convergence_cleanup_smoke/`.

La ejecución completa terminó inicialmente con 5.296 aprobados, 52 fallos y 12 errores. Los 63 casos nativos reclamaban la ruta de consola para verificar su sustitución segura por el ejecutable normal; otro caso necesitaba `pypdf`. Se repitieron exactamente los 64 casos: **64/64 aprobados**, sin modificar código ni aserciones. Las dependencias externas incluyen pypdf 6.20.1. La selección y los resultados están en `pytest_retest_selection.json`, `pytest_retest_result.json`, `pytest_retest.xml` y `pytest_retest.log`.

Resumen verificable y SHA-256 de los archivos editados en las pruebas iniciales: `product_clock_sobremesa_2026-10-14.json`. Los archivos `.gd.uid` creados por la importación de Godot se conservan como archivos generados, fuera del cambio preparado. La corrección está ahora guardada en commits locales y aplicada a `main` de OneDrive; no se ha hecho push al remoto.
