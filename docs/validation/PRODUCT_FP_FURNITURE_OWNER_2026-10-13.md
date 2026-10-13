# Un propietario visible de mobiliario en FP — 2026-10-13

Estado: corrección visual verificada; jugabilidad FP sigue abierta.
Checkpoint: `599d8d0e`, main y shareable publicados.
El usuario autoriza retirar primero la segunda representación sólo en FP,
conservando 3D, muebles FP e interacción. No autoriza en esta fase la caché
de fichas estáticas propuesta en el [diagnóstico](PRODUCT_FP_RUNNING_DIAGNOSIS_2026-10-13.md).

## Cambio acotado

Único archivo de producción: [Visualizer3D.gd](../../view/3d/Visualizer3D.gd).
`show_fuel_objects_in_first_person` pasa a false por defecto. Las políticas
existentes de entrada y refresco ocultan las raíces de mobiliario de 3D en FP.
La guarda de actualización devuelve false antes del temporizador: ni normaliza
muebles ni actualiza las copias ocultas en los pasos de la vista 3D.
Las raíces se conservan para volver a 3D, donde se refrescan con la instantánea
actual. No se deshabilita el visualizador entero: sigue mostrando la atmósfera.

FirstPersonController sigue siendo el dueño de los muebles visibles en FP.
No se cambia su código, poses, geometría, materiales, colisiones o interacción.
Tampoco Main, minimapa, humo/fuego, gráfica, sim/, dt, calidad o escenarios.
No se congela el estado dinámico de los muebles FP.

La opción exportada sigue disponible como compatibilidad explícita para usar
Visualizer3D sin mobiliario FP propio. Activarla deliberadamente vuelve a
permitir ambas representaciones: no se declara exclusividad universal.
La escena distribuida no tiene un override de esa opción y usa el nuevo default.

## Verificación

[Evidencia, salud y hashes raw/LF](PRODUCT_FP_FURNITURE_OWNER_2026-10-13_EVIDENCE.json).
Los hashes LF permiten comparar el código probado con los blobs de Git.

Control headless con SimulationScene y Main reales, Casa simple y opciones
copiadas al APPDATA externo: tres viajes FP/3D y 30 refrescos por viaje.

- 1 442 comprobaciones del control de la campaña final, sin fallos.
- 39 identidades lógicas conservadas; posición mundial coincidente; sólo el
  propietario de la vista activa visible en cada fase.
- Nodos, transforms, referencias de mallas/materiales, color del material
  override y referencias/estado de colisiones FP conservados en los viajes.
  No es paridad de píxeles ni prueba universal de todo material de un asset.
- Estadísticas de caché sin actividad al refrescar sólo 3D oculto en FP;
  normalización/restauración activas en 3D. Interacción de apertura restaurada.
- Transiciones sin cambiar estado físico; 60 llamadas reales al dispatcher
  conservan un segundo simulado y pausa no avanza el reloj.
- Cinco mutantes GD válidos detectados donde se declaró, cero supervivientes,
  cero bajas por sintaxis, restauración exacta de Visualizer3D por SHA-256.
- Focales offline finales: 42 passed; estilo GD y `git diff --check` limpios.
- Control final repetido: 1 442 PASS sobre las fuentes finales.
- Producto completo repetido: 168 PASS, exit 0, 525,70 s, stderr vacío.
  Memoria antes/después 6,54/6,61 GiB; sin timeout, cuadros, procesos residuales
  ni terminación de procesos ajenos. Tandas nativas secuenciales y APPDATA/TEMP/TMP externos.
- Guardarraíles científicos/R2-1: ALL PASS, 346/346 required y 78 gaps.
  sim/ e informes intactos, sin regeneración de referencia.
- Global completa no repetida en esta entrega acotada. Tampoco se reutiliza
  una global anterior como si hubiese probado este código.

La primera campaña se detuvo en O02: murió por actividad del temporizador,
no por la aserción predeclarada. No se cuenta como campaña válida. Se fuerza
un tick debido para que el temporizador no esconda la ausencia de la guarda,
y se prueba la política de entrada antes de que un refresco esconda su fallo.
La segunda campaña completa mata O01–O05 en las aserciones declaradas.

La primera suite de producto termina con un único fallo: el contrato antiguo
de `tools/validate_furniture_runtime.gd` exige mostrar la copia 3D en FP.
Se actualiza de acuerdo con el comportamiento solicitado, no se elimina:
default oculto, no refresco oculto, opt-in visible explícito y restauración
de visibilidad/refresco 3D. Sus pruebas de poses/tamaño/materiales se conservan.
La suite completa repetida queda en verde; el primer intento no es PASS.
El ejecutor seguro de etapas P1 se reutiliza sólo para ejecutar producto y
preservar archivos/procesos, no como prueba de integración física de esta UI.

## Límites y retomada

Esta corrección retira una duplicación demostrada; no cierra la lentitud FP
ni prueba una mejora de FPS. No se repite aún un banco renderizado en esta fase.
Las corridas anteriores fueron rechazadas por avisos GL de salida, cuya causa
sigue abierta: no se relaja el rechazo ni se usan sus FPS como evidencia aceptada.
El control previo `--hide-overview-furniture` coincide ahora con el default:
no debe reutilizarse como si siguiera siendo una perturbación causal.

Probar Casa simple desde el checkout habitual: entrar en FP, Play, interactuar
con puertas/ventanas, volver a 3D y comprobar muebles/estado actual. Si sigue
lento, siguiente gate: costes de fichas estáticas con invalidación y datos
dinámicos frescos, sin congelar muebles ni reducir calidad; requiere aprobación.
Popup técnico y salida GL separados. Gas/energía/EOS después de producto;
CO/FED siguen OFF/NO-GO.

Control reproducible, sin otro Godot y con al menos 6 GiB disponibles:

```powershell
python -X utf8 scripts/verify_fp_furniture_owner.py --work "$env:TEMP/simufire_fp_owner_control_new"
python -X utf8 scripts/verify_fp_furniture_owner.py --mutations --work "$env:TEMP/simufire_fp_owner_mutations_new"
```
