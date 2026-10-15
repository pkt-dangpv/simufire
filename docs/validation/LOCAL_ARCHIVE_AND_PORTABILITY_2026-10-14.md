# Archivo local y portabilidad entre equipos — 2026-10-14

Los lanzadores dejan de depender de la letra de unidad del checkout y de rutas
con el nombre del usuario. Se han preparado también las evidencias locales que
no estaban publicadas en Git. No se han cambiado modelos físicos ni baselines.

## Copias archivadas

Tras terminar la sincronización del portátil, las 3.428 copias del inventario
anterior ya no estaban en las carpetas activas. El respaldo indicado por el
usuario, `_local_copies_backup_2026-10-14`, se había sincronizado dentro del
proyecto de SOBREMESA y estaba excluido mediante `.git/info/exclude`.

Ese respaldo contenía 52 copias, tres referencias Git antiguas y dos manifiestos:
57 archivos en total. Se verificaron ambos manifiestos y todos los hashes, se
creó un ZIP adicional y se verificaron sus entradas. Después se trasladó la
carpeta completa fuera del proyecto y de OneDrive y se verificaron otra vez
todos los archivos. No se efectuó ningún borrado permanente.

Además se localizaron y archivaron 560 copias de cachés y registros ignorados,
22.042.582 bytes. Todas tenían su original correspondiente. Se verificaron antes
de moverlas, se conservó otro ZIP de seguridad y se verificaron después del
traslado. Los originales de esas cachés y registros permanecen en el proyecto.

El respaldo externo se llama `simufire_copies_archive_2026-10-14` dentro de los
artefactos de esta conversación en SOBREMESA. Contiene `files/`,
`backup_before_move.zip` y `ARCHIVE_MANIFEST.json`. No se ha afirmado que ese
respaldo contenga físicamente las 3.428 copias del inventario previo: únicamente
se ha verificado el respaldo que llegó desde el portátil. Tampoco se ha leído
directamente el disco del portátil. El respaldo externo reside en SOBREMESA.
Las copias ignoradas están en `ignored_copies/`, con su propio ZIP, manifiesto
y registro de traslados completados.

## Evidencias preparadas para Git

[El paquete documental](../archive/local_evidence_2026-10-14/README.md) conserva
1.800 archivos originales (75.000.580 bytes) en un ZIP de 6.936.904 bytes.
Cada archivo y el ZIP tienen SHA-256; todas las entradas se leyeron de vuelta.
Los originales locales permanecen conservados. El auxiliar `parse_o2l_logs.py`
se guardó con sus bytes originales en el ZIP antes de preparar su versión portable.

Incluye los siete escenarios diagnósticos, 457 informes experimentales, 187
archivos de pruebas históricas, 47 archivos de ejecuciones, 195 logs científicos,
906 CSV/TXT exportados y el auxiliar original. Los siete casos también se han
preparado individualmente, sin prefijo `tmp_`, conservando sus contenidos.
No se han añadido al corpus oficial ni se han calificado como referencias aprobadas.

No se han reescrito las rutas antiguas de los logs: documentan el equipo de origen.
Las cachés, los historiales personales de asistentes y la configuración local
de herramientas no forman parte del paquete.

## Resolución de rutas

- Python calcula la raíz desde `__file__`; PowerShell desde `$PSScriptRoot`.
- `scripts/project_paths.py` y `scripts/project_paths.ps1` descubren Godot en
  cada máquina mediante argumento explícito, `GODOT_EXE`, PATH o escritorio local.
- Se migraron 37 lanzadores existentes: 25 Python, diez PowerShell y dos BAT.
  Los BAT de FDS usan `%ProgramFiles%` de la máquina en vez de una unidad fija.
- Se preparó `tools/archive/parse_o2l_logs.py` con una raíz relativa al archivo;
  el auxiliar local ignorado usa también esa resolución portable.
- Los dos enlaces a licencias del addon Sky3D que causaban la cruz roja de las
  comprobaciones de GitHub se corrigieron a enlaces relativos.

Las rutas absolutas de procedencia en informes históricos y la ruta sintética
de una prueba de diálogo de error permanecen intactas. No son dependencias de
ubicación del proyecto. Cada máquina necesita sus herramientas instaladas.
La configuración recomendada está en [LOCAL_WORKSPACE](../LOCAL_WORKSPACE.md)
y la decisión técnica en [ADR 0006](../architecture/adr/0006-portable-workspace-and-local-evidence.md).

## Verificación

- 78 pruebas y 25 subtests aprobados con pytest: `test_project_paths.py`,
  `test_check_product_monitored_launch.py` y `test_run_scenario_fail_closed.py`.
  Se usó un directorio temporal autorizado y se ejecutaron como pytest: los
  intentos previos con temporales restringidos o como unittest no cuentan como aprobados.
- 28 archivos Python parseados y once PowerShell sin errores de sintaxis.
- PowerShell: raíz calculada correctamente al reubicar los dos scripts Ghanekar
  en `C:`, selección explícita de Godot, variable de entorno y rechazo de una
  ruta explícita inexistente. No se ejecutaron barridos ni regeneraciones.
- Ejecución real de un escenario durante un segundo desde el checkout en `F:`:
  monitor sin fallos, manifiesto y artefactos completos, `RUN_SCENARIO PASS`.
- Copia de prueba de 2.335 archivos en `C:`: importación headless con código cero,
  sin fallos del monitor, seguida de la misma ejecución real durante un segundo
  con `RUN_SCENARIO PASS`, lanzada desde un directorio de trabajo ajeno al checkout.
- Comprobador general de enlaces Markdown y enlaces de todos los documentos
  tocados: aprobados.
- Guardrails sobre los informes existentes: 346/346 required PASS y todos los
  guardrails aprobados, incluida la vigencia de los informes. No es una nueva
  validación científica completa ni certifica todos los experimentos históricos.

Las comprobaciones de `C:` y `F:` se hicieron en SOBREMESA. No sustituyen una
prueba de la instalación de Godot del portátil. Los cambios quedan preparados
en el árbol de trabajo para revisión y publicación; este trabajo no crea un
commit ni realiza un push.
