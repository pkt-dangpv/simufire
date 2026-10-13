# Caché de fichas estáticas de mobiliario — 2026-10-13

Estado: corrección visual verificada; pendiente prueba del usuario en FP.
Checkpoint: `0ba9361c`, main y rama shareable publicados.
El usuario confirma que FP ya es jugable tras retirar la segunda representación,
pero menos fluido en Play que en pausa. Autoriza reducir la preparación repetida
de las fichas sin tocar física ni bajar calidad.

## Cambio

Único archivo de producción: [FurnitureVisualLayout.gd](../../view/furniture/FurnitureVisualLayout.gd).
La normalización usa una caché previa a la de poses, por edificio y habitación.
Guarda índices y arquetipos de objetos reales y el atrezo generado. Las fichas
de los objetos reales se copian siempre de la instantánea actual: no se guardan
sus estados de fuego, temperaturas, potencia o combustible restante.
Las copias de atrezo también son independientes de la caché.

La clave incluye rectángulo, política de relleno, nombre/tipo/política de la
habitación y todos los campos de entrada salvo la lista dinámica ya existente.
Los campos desconocidos invalidan conservadoramente. Cambiar orden, añadir o
retirar objetos, renombrarlos o modificar sus medidas recompone las fichas.
Ambas cachés se limpian al reconstruir o recibir la señal de cambio de un asset,
se limitan a 128 entradas y no retienen vivo el modelo: propietario débil.

El generador de mobiliario, clasificador, algoritmo de colocación, dimensiones,
assets, transformaciones y representación de fuego/materiales no cambian.
Tampoco Main, FP, minimapa, escenas, sim/, física, dt ni frecuencia de refresco.
La verificación de existencia/identidad/metadatos del asset se mantiene en cada
pasada; no se promete eliminar ese coste ni impedir la recarga de modelos.
La caché beneficia a los tres consumidores de esta normalización: 3D, FP y minimapa.

## Controles y medición

[Evidencia y hashes raw/LF](PRODUCT_FURNITURE_STATIC_SPECS_CACHE_2026-10-13_EVIDENCE.json).

- Control nativo: 831 comprobaciones, incluidas las 730 previas, todas PASS.
  Compara byte a byte salidas y entradas contra preparación/colocación sin caché.
  El oráculo no llama a la preparación cacheada y el algoritmo de colocación
  mantiene su hash publicado. Diez viviendas, pasadas frías/calientes.
- Campos dinámicos presentes/ausentes, entradas inválidas intercaladas, cambio
  de nombre/tipo/relleno, orden/adición/retirada, campos desconocidos, dimensiones,
  copias, propietarios muertos, límites, invalidación explícita y por asset.
- 19/19 mutantes GD válidos detectados en aserciones predeclaradas, cero
  supervivientes/bajas por sintaxis y originales restaurados exactamente por SHA-256.
- Regresión del propietario FP: 1 442 PASS; 39 muebles, recursos/poses conservados,
  copia 3D oculta/no refrescada, vuelta a 3D, interacción y reloj.
- Focales offline: 43 passed; estilo GD y `git diff --check` limpios.
- Guardarraíles/R2-1 PASS; referencia 346/346 required y 78 gaps intacta.
  No procede regenerarla al no tocar sim/ ni sus informes.

Casa simple, mismas opciones de la medición anterior: apartamento 15/20,
noche, luces interiores y visibilidad activas. Banco headless con Main real,
180 ticks manuales de 1/60 s; tres segundos simulados; después sondas congeladas.
El monitor termina sin errores, cuadros, timeout ni procesos residuales.

La mediana de refresco de muebles pasa de 5,607 a 3,5945 ms, aproximadamente
un 36 % menos CPU. FP set_state: 6,4645 -> 4,5135 ms. La comparación antes/después
son corridas separadas, no una campaña renderizada ABBA ni garantía de FPS.
Dentro de la corrida final, preparación sin caché 2,334 ms y cacheada 0,5625 ms.
Las sondas son inclusivas y solapadas: no sumar sus tiempos como presupuesto
de frame. El paso físico sigue alrededor de 5,2 ms.
Callback Main: media 8,4506 -> 7,9275 ms, p95 15,549 -> 13,898; mediana
5,273 -> 5,503 y máximo 16,622 -> 16,663. No mejora uniforme en todas las
métricas ni cierre del coste total; las dos últimas no mejoran en estas corridas.

Producto completo: 168 PASS, exit 0, 514,74 s, monitor limpio, sin cuadros,
timeouts ni Godot residual. Se reutiliza el ejecutor seguro de etapas P1 para
ejecución/preservación, no como evidencia de integración física de esta UI.
Global autoritativa: 5 124 passed, 94 skipped, 2 xfailed y 42 subtests, cero
fallos, exit 0; 828,97 s pytest y 832,73 s de etapa monitorizada. Memoria
antes/después 6,60/6,96 GiB; stderr vacío, sin timeout, cuadros ni residuos.
Se conserva la cifra de omitidas: no se declaran ejecutadas ni PASS esas pruebas.
Durante la corrida se midió un descenso puntual a 5,977 GiB y se pidió margen;
no se rebajó la guarda ni se lanzó una tanda adicional, y la global terminó verde.
Enlaces de los documentos modificados y `git diff --check` limpios.

## Límites y siguiente paso

No se certifica igualdad de fluidez entre pausa y Play: Play añade física y
refresco dinámico. No se han medido FPS renderizados en esta entrega. Los avisos
GL de salida y el popup técnico permanecen pendientes separados; no se relaja
el rechazo del banco renderizado.
Después del cierre, probar Casa simple en FP/3D, Play y aperturas. Si la diferencia
sigue siendo molesta, medir el coste restante antes de otro cambio.
CO/FED siguen OFF/NO-GO; gas/energía/EOS no se inicia aquí.

Reproducir controles sin otro Godot y con al menos 6 GiB libres, usando
directorios externos nuevos:

```powershell
python -X utf8 scripts/verify_furniture_layout_cache.py --work "$env:TEMP/simufire_static_specs_control_new"
python -X utf8 scripts/verify_furniture_layout_cache.py --mutations --work "$env:TEMP/simufire_static_specs_mutations_new"
python -X utf8 scripts/verify_fp_furniture_owner.py --work "$env:TEMP/simufire_static_specs_fp_owner_new"
```
