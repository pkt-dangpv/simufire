# Evidencia portable de las pruebas del reloj

`evidence.zip` contiene 170 archivos de las pruebas realizadas en SOBREMESA:
controles del reloj, mutantes, gráficas, diez trazas físicas, perfiles renderizados,
regresiones y comprobación de la aplicación en OneDrive. Incluye los intentos
descartados y sus errores; no convierte sus resultados en mediciones aceptadas.

El archivo `archive_manifest.json` registra el SHA-256 del ZIP, su tamaño y el
número de archivos. Dentro del ZIP, `MANIFEST.json` registra la ruta, tamaño y
SHA-256 de cada archivo original. Puede descomprimirse en cualquier carpeta del
portátil para consultar las trazas y registros. Algunos scripts auxiliares y
metadatos conservan las rutas originales del equipo donde se ejecutaron.

Las pruebas reproducibles del proyecto están en `scripts/verify_product_dispatch.py`,
`scripts/verify_product_step_convergence.py` y los demás scripts versionados.
Las versiones de Python y dependencias utilizadas están en el resumen JSON de
la validación. Los entornos instalados, cachés de Godot, directorios temporales y
datos de usuario generados durante las pruebas quedan fuera de este paquete.

`uid_sidecars.zip` conserva los 111 identificadores de scripts generados en
esta máquina, con un manifiesto por archivo. También se registran directamente
87 identificadores del editor, vistas, herramientas y pruebas. Los 24 nuevos
identificadores del motor bajo `sim/` se mantienen como metadatos generados y
se conservan en el ZIP: el guardarraíl R2-1 considera su registro directo un
cambio del motor que requiere regenerar las referencias. No se ha modificado
ese guardarraíl ni se han retocado los informes para aparentar una regeneración.
Los UID que ya estaban versionados siguen versionados. Godot puede regenerar
los identificadores locales al importar el proyecto; el paquete permite
consultar o recuperar exactamente los originales de esta ejecución.

Resultados y límites:

- Reloj: 73.948 comprobaciones correctas; cinco mutantes detectados.
- Gráficas: 26 comprobaciones correctas; cinco mutantes detectados.
- Regresión inicial y repetición de los casos afectados por configuración:
  5.360 aprobados, 102 omitidos y dos fallos esperados; producto 168 aprobado.
- Aplicación en OneDrive: reloj, gráficas, 343 pruebas y 306 subtests aprobados.
- Pasos físicos 1/12, 1/30 y 1/40 s: comparación exploratoria no superada.
- FPS de primera persona: dos intentos descartados por errores de texturas al salir.

El informe principal es `../../PRODUCT_CLOCK_SOBREMESA_2026-10-14.md`.
