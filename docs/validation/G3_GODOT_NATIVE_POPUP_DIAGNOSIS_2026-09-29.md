# Caídas «nativas» de Godot en la suite global (2026-09-29)

Estado: **causa demostrada y lanzador corregido**; ni RAM ni física.

## Síntoma

La pasada anterior terminó con 3033 passed y 26 fallos «por cuadros nativos
de Godot» (exit 1, sin residuos). Una prueba aislada,
`tests/test_pressure_network_integration.py::test_validator_passes`, falló
en 3,16 s con 7,14 GiB libres, mientras `check_product.py` pasaba 167/167.

## Evidencia (solo lectura; sin cambiar configuración del equipo)

1. **Visor de eventos, System / Application Popup / ID 26**: tres ventanas
   emergentes hoy a las 13:11, 13:16 y 13:21, idénticas:
   `Godot_v4.7.1-stable_win64.exe - Error de la aplicación: la instrucción
   en 0x00007FF60E555854 hace referencia a la memoria en
   0x0000000000000058`. Mismo punto de código y desreferencia nula: un fallo
   determinista de arranque, no memoria insuficiente.
2. **Registro del sandbox de Codex** (`.codex/.sandbox/sandbox.2026-09-29.log`):
   a las 13:10 `python scripts/check_product.py` se ejecutó **dentro del
   sandbox restringido** y terminó con código 1. Las tres ventanas caen en
   esa ejecución, separadas 5 min, compatible con procesos colgados tras
   el cuadro hasta el límite de tiempo de cada comprobación. El mismo patrón
   de lanzamiento restringido está documentado el 2026-07-15 y el 2026-07-29
   (arranque degradado, `user://`/certificados) y desaparece fuera del sandbox.
3. **Los 26 fallos posteriores (13:33–13:37) no están en ese registro**: se
   ejecutaron fuera del sandbox. Sus `godot.log` rotados miden **0 bytes**
   (ni siquiera el banner de versión) y su salida es 1.
4. `Popen.kill()` en Windows es `TerminateProcess(handle, 1)`: un exit 1 es
   el propio monitor matando el proceso; un crash real saldría `0xC0000005`.
5. `mutation_audit._windows_godot_error_dialogs()` recorre **todas** las
   ventanas del escritorio y las identifica por título, sin proceso dueño ni
   línea base. Los cuadros de error duro no se cierran al matar el proceso
   que los causó: siguen abiertos hasta que alguien pulsa Aceptar.

## Reproducción determinista

Una ventana **oculta** (Tk retirada, nunca visible) con el título del cuadro
real, creada por un proceso auxiliar:

| Lanzador | Con ventana obsoleta | Sin ella |
| --- | --- | --- |
| Original | **FAIL en 3,18 s**, «popup detected», salida 1 del envoltorio y del hijo, `godot.log` de 0 bytes, **sin evento ID 26 nuevo**, sin residuos | 3/3 PASS en 5,04–5,16 s |
| Corregido | **No lanza Godot**: `PreexistingGodotErrorDialog` en 1,2 s, sin rotación de log | 3/3 PASS en 5,03 s |

Conclusión: tras el `check_product` ejecutado en el sandbox quedaron cuadros
abiertos; el monitor los atribuyó a cada ejecución sana posterior y la mató.
El defecto del lanzador era **atribuir ventanas preexistentes** a la
ejecución actual. El fallo nativo original (dirección `…E555854`) pertenece
al lanzamiento en entorno restringido; sin símbolos de Godot no se resuelve
la función exacta.

## Corrección

`tools/mutation_audit.py`: `_run_monitored` comprueba antes de lanzar que no
hay ningún cuadro de error de Godot abierto y, si lo hay, lanza
`PreexistingGodotErrorDialog` con el diagnóstico (aceptar el cuadro y mirar
el ID 26). **No** relaja nada durante la ejecución: un cuadro nuevo, un
timeout, un código de salida inesperado, una violación de acceso o un
proceso residual siguen fallando igual. Pruebas nuevas
(`tests/test_godot_monitor_stale_dialogs.py`) con un hijo Python inocuo:
cuadro previo → no se crea el proceso; cuadro durante la ejecución → falla
con salida 1; ejecución limpia → pasa. Mutante (quitar la comprobación
previa) detectado; fichero restaurado con SHA-256 idéntico.

## Reglas operativas

- Ejecutar Godot **fuera** del sandbox restringido del agente.
- Si aparece un cuadro, aceptarlo antes de relanzar; el lanzador ya se niega
  a arrancar mientras exista.
- `check_product.py` lanza Godot sin este monitor: no detecta cuadros ni
  residuos, por eso sus procesos quedaron colgados 5 min. Queda como deuda
  para una pasada propia; hoy no se ha modificado.
