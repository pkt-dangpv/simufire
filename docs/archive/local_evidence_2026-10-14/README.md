# Evidencias locales conservadas el 14 de octubre de 2026

Este paquete prepara material que estaba excluido de Git en la copia de SOBREMESA.
Es evidencia histórica; no añade casos al corpus oficial, no cambia baselines y no
certifica que los antiguos experimentos funcionen sin adaptación con el motor actual.

`evidence.zip` conserva los bytes originales bajo `original/`, con sus rutas relativas.
`file_manifest.json` y el manifiesto dentro del ZIP registran tamaño y SHA-256 de cada
archivo; `archive_manifest.json` registra el hash del ZIP. Todas las entradas se han
leído de vuelta y verificado. Los archivos locales originales se han conservado.

Incluye:

- 7 escenarios de diagnóstico y 457 informes JSON experimentales (tres informes
  tienen contenido idéntico a otros ya versionados y se conservan por su contexto).
- 187 archivos históricos de pruebas: 184 logs, un LEEME y dos JSON.
- 47 archivos de ejecuciones locales: manifiestos, resúmenes, eventos y datos brutos.
- 195 logs científicos originales, incluidas dos comparaciones con FDS.
- 906 CSV/TXT exportados en `graphs/`. Las imágenes PNG y páginas HTML permanecen
  en el almacenamiento local; no forman parte de este paquete de datos brutos.
- El auxiliar de análisis original, con su ruta histórica. La copia portable está
  en [tools/archive/parse_o2l_logs.py](../../../tools/archive/parse_o2l_logs.py).

Los siete escenarios también están disponibles sin descomprimir en [cases/](cases/).
`case_manifest.json` relaciona sus nombres preparados con los originales. Los nombres
que empezaban por `tmp_` se han preparado sin ese prefijo; los contenidos no cambian.
En particular, [d2_sensitivity_engine_defaults.json](cases/d2_sensitivity_engine_defaults.json)
conserva el diagnóstico citado en el historial de cambios y en la lista de validación,
que antes quedaba excluido por el patrón `tmp_*`.

Para ejecutar un diagnóstico desde la raíz del checkout, una vez configurado Godot:

```powershell
python scripts/run_scenario.py docs/archive/local_evidence_2026-10-14/cases/d2_sensitivity_engine_defaults.json --out-dir runs/d2_diagnostic
```

Es un experimento histórico, no una orden de regenerar o aprobar referencias oficiales.
Los parámetros y las métricas deben revisarse frente a la versión actual del motor.

Los logs y JSON conservan referencias a `C:` o `F:` como procedencia de la ejecución.
Esas cadenas no se usan para localizar el checkout al ejecutar los lanzadores actuales.
No se han reescrito los logs para hacerlos parecer portables ni se han alterado resultados.
No se incluyen cachés, historiales personales de asistentes ni configuraciones locales.
