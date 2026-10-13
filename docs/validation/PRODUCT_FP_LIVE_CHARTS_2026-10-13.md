# Suspensión de la gráfica en FP — 2026-10-13

Estado: cambio de UI verificado; no cierra rendimiento ni jugabilidad de FP.
Checkpoint inicial: `58368210`, main y rama shareable publicados.
El usuario confirma que 3D funciona bien; FP mejora pero sigue lento.
Solicita retirar la gráfica en tiempo real para probar su efecto en FP.

## Cambio

Único archivo de producción: [Main.gd](../../Main.gd).
Al entrar en FP se ocultan la gráfica y su botón, se deshabilita el proceso
del subárbol y se suspende el muestreo antes de pedir `engine.get_state()`.
No basta con ocultarla: antes el histórico seguía creciendo aunque no se veía.
La sincronización común cubre también salir de FP directamente hacia 3D.
Al volver a 2D/3D se recupera la preferencia visible/oculta previa del usuario.
El tiempo de muestreo se reinicia, sin muestras de recuperación inventadas.

El histórico del overlay conserva lo anterior, pero no recibe muestras durante
FP. No sustituye los registros del motor ni altera las gráficas de fin de sesión.
Fuera de FP se mantiene el comportamiento anterior, incluido muestrear oculto.
No se cambian física, dt, escala temporal, calidad, minimapa, muebles ni escenarios.
El cuerpo de `_physics_process` permanece idéntico.

## Verificación

[Evidencia y hashes raw/LF](PRODUCT_FP_LIVE_CHARTS_2026-10-13_EVIDENCE.json).
Los hashes LF permiten contrastar el contenido con el blob de Git, aunque
el fichero probado en disco emplee otro final de línea.

- Control nativo: 26 comprobaciones PASS, sin errores de script ni del monitor.
- Cinco mutantes válidos detectados en sus aserciones declaradas; Main restaurado
  exactamente por SHA-256. Cero supervivientes y cero bajas por sintaxis.
- Focales offline: 35 passed; estilo GD y `git diff --check` limpios.
- `check_product.py`: 168 PASS, exit 0; 525,68 s, stderr vacío.
  Memoria antes/después 6,36/6,35 GiB; sin timeout, cuadros de error ni residuos.
- Guardarraíles científicos/R2-1: PASS, 346/346 required y 78 gaps.
  Sin cambios de sim/ ni de informes; no procede regenerar la referencia.
- No se repite la global completa en esta entrega de UI. El resultado global
  del hotfix anterior no se atribuye a este cambio.

El control usa Main heredado y la gráfica real, con vistas anuladas y un motor
sonda para contar llamadas y delta. Prueba el despacho y la suspensión del
overlay, no la física ni FPS. El runner reutiliza el monitor existente sin
rebajar el umbral de 6 GiB; APPDATA/TEMP/TMP externos y tandas secuenciales.
La suite de producto usa el ejecutor seguro de etapas existente; su admisión
del núcleo P1 congelado no sustituye el control propio de esta UI.

Primer intento offline: 33 PASS/1 fallo del extractor de funciones de la prueba,
que incluía comentarios y la función siguiente. Se corrigió el extractor y
se repitió: 35 PASS. Antes del primer lanzamiento se corrigió el montaje del
control para no evaluar rutas @onready de SimulationScene en un nodo aislado.

## Renderizado real y límites

Se ejecutó Casa simple en FP con la escena y Main de producción, ventana real,
minimapa visible y calidad/cadencia intactas. El proceso terminó con exit 0,
sin timeout, cuadros de error ni Godot residual, pero el banco rechaza la corrida:
dos texturas GL no liberadas al salir, de 349 524 bytes cada una. Es el mismo
tipo de aviso que [ya aparecía antes](PRODUCT_MINIMAP_LAYOUT_THRASH_2026-10-13.md).
No se ha aislado la causa y no se relaja el rechazo del banco.

La traza provisional marca 21,71 FPS en Play, aproximadamente 60 en pausa,
y 8 s simulados en 8,03 s reales. No es una medición aceptada ni demuestra
mejora o empeoramiento causal frente a las corridas anteriores. No se certifica
que la gráfica fuese la causa de la lentitud, ni que FP ya sea jugable.

## Retomada

Probar Casa simple desde la copia habitual: FP + Play sin gráfica, alternar
FP/3D/2D y verificar que la preferencia se restaura. Si sigue lento, aislar
otro coste de FP con controles por componente, sin cambiar física o calidad.
El cierre GL y el popup técnico fuera del árbol siguen pendientes separados.
Gas/energía/EOS continúa aplazado por producto; CO/FED OFF/NO-GO.

Control reproducible desde el checkout probado, con al menos 6 GiB libres
y sin otros Godot, usando directorios externos nuevos:

```powershell
python -X utf8 scripts/verify_fp_live_charts.py --work "$env:TEMP/simufire_fp_chart_control_new"
python -X utf8 scripts/verify_fp_live_charts.py --mutations --work "$env:TEMP/simufire_fp_chart_mutants_new"
python -X utf8 -m pytest tests/test_fp_live_charts.py tests/test_product_render_profile.py tests/test_furniture_layout_cache.py tests/test_async_graph_generation.py -q -p no:cacheprovider
```
