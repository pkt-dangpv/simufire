# FP lento en Play: diagnóstico — 2026-10-13

Checkpoint: `a01327cd`, publicado. Usuario: 3D perfecto, FP fluido en pausa
pero aún lento en Play. Gráfica FP suspendida. Este encargo es diagnóstico:
Main, sim/, view/, ui/, escenas, calidad y física quedan intactos.
No es una corrección de producto ni cierra jugabilidad.

[Evidencia, salud y límites](PRODUCT_FP_RUNNING_DIAGNOSIS_2026-10-13_EVIDENCE.json).
Casa simple real, apartamento 15/20, noche, luces y visibilidad activas.
Opciones copiadas, original intacto. Monitor existente, mínimo 6 GiB, runtimes
externos y tandas nativas secuenciales. Sin cuadros nativos ni procesos residuales.

## Hallazgos aceptados, sin causa única de FPS demostrada

1. **Dos representaciones de 39 muebles.** Control headless de la escena:
   mismos IDs por sala, ambos propietarios visibles y posiciones globales iguales.
   Visualizer3D mantiene `show_fuel_objects_in_first_person = true`, mientras FP
   construye/actualiza sus propios muebles. El inventario no prueba que todas
   sus mallas/materiales sean intercambiables o que retirarlas tenga paridad visual.
2. **El refresco de muebles domina el coste CPU visual medido.** La preparación
   de fichas estáticas/amueblado se vuelve a hacer antes de consultar la caché
   de poses. Main solicita FP a 0,05 s; el overlay 3D tiene otra cadencia.
3. **Setters redundantes en colisiones.** Treinta refrescos sin cambiar forma
   producen 660 señales, todas de once BoxShape3D. Los once BoxMesh no se
   reconstruyen al asignar el mismo tamaño: esa hipótesis no se confirmó.

Último control CPU headless, 30 llamadas de estado congelado tras calentamiento:

| Operación | Mediana |
|---|---:|
| FP set_state | 6,62 ms |
| Muebles FP | 5,50 ms |
| Normalización/layout de muebles | 4,04 ms |
| Preparación de fichas | 2,29 ms |
| Tokens/metadatos de assets | 0,71 ms |
| Exportar estado para vistas | 2,68 ms |
| Puertas/ventanas FP | 0,39 ms |
| Callback movimiento/animación FP | 0,15 ms |
| HUD FP | 0,07 ms |
| Visibilidad FP | 0,04 ms |

Sondas independientes y solapadas: **no sumar como presupuesto de fotograma**;
no son FPS/GPU. Paso del motor alrededor de 5,5 ms, no coste cero ni modificado.
El estado del motor permanece intacto durante las sondas congeladas.

## Control de colisiones: ineficiencia real, no gran ganancia CPU probada

Guarda de igualdad exacta: 660 señales -> cero, tamaños/arrays de malla idénticos.
Un cambio positivo de 1 cm sigue admitido y se restaura. ABBA natural, cuatro
escenas frescas, 180 ticks del Main real por caso y 3 s simulados: una copia
diagnóstica del método añade sólo dos guardas; conserva 418 propiedades antes
de ready. Controles 1 320 señales, guardas cero; cuatro estados finales del
motor idénticos byte a byte. CPU medio del callback: controles 9,33/9,23 ms,
guardas 9,32/9,22. No mejora clara allí ni FPS medidos.
`physics_monitor_cached_us` es un monitor periódico que puede conservar arranque:
archivado, **no usado como duración de este tick ni como presupuesto**.

## Renderizado: indicios rechazados

Tres corridas reales terminan con los dos avisos GL conocidos (texturas de
349 524 bytes). Nativo exit 0, sin cuadros/residuos, pero se mantiene el rechazo
por `ERROR:`. Cargar la escena runtime en vez de preload no elimina los avisos;
ese experimento del banco se revierte. No tocar producto basándose en él.

Contrafactuales declarados: congelar refresco de muebles FP tras calentamiento
mantiene mallas visibles pero estado visual obsoleto, **no es arreglo propuesto**;
ocultar muebles del overlay conserva las 39 piezas propias de FP visibles,
pero la paridad completa sigue pendiente. Trazas provisionales: baseline runtime
20,71 FPS, congelación 24,44, overlay sin muebles 24,63. Salidas rechazadas,
dispersión y pausas/catch-up en congelación impiden certificar una mejora causal.

## Verificación y retomada

37 offline PASS, tres controles finales headless aceptados; estilo, enlaces y
diff-check limpios. Guardarraíles/R2-1 PASS, 346/346 y 78 gaps, sin regenerar
referencia. Producto/global anteriores no se atribuyen a este diagnóstico ni
se repiten aquí. No cambio de producción ni activación física; CO/FED OFF/NO-GO.

Corrección propuesta, **no implementada ni autorizada por este diagnóstico**:

1. Un propietario visual del mobiliario en FP: conservar su representación,
   retirar sólo la segunda copia en ese modo. Probar vuelta a 3D, poses,
   materiales, colliders e interacción antes de decidir paridad.
2. Evitar regenerar fichas estáticas con cada estado: caché acotada e invalidación
   por recinto/geometría/asset/rebuild. No congelar HRR, combustible, temperatura,
   ennegrecimiento o aparición de objetos.
3. Guardas de tamaño como mejora secundaria, sin prometer FPS.
4. Prueba real, cierre GL aparte y costes diferidos/render si sigue lento;
   comprobar también que el observador no introduce sesgo de rendimiento.

Pedir autorización para corregir representación visual. Gas/energía/EOS queda
aplazado hasta resolver prioridad de producto.
