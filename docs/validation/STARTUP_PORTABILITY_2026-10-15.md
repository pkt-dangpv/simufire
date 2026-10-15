# Arranque y rutas entre C: y F: — 2026-10-15

SimuFire arranca, muestra el menú, abre una partida, avanza al pulsar Play y
regresa al menú mediante la salida normal del HUD en las tres ubicaciones
probadas. Se verificaron el checkout principal en F:, una copia real en C:
con espacios, ñ y Ω, y una copia en F: con esos caracteres y una carpeta
llamada OneDrive español Ω. Todos los procesos Godot estuvieron monitorizados.

## Hallazgos y correcciones

- Cinco analizadores históricos de `tools/archive/root-scripts/` todavía usaban
  una ruta absoluta de F:. Ahora calculan la raíz desde `__file__` y muestran
  un mensaje accionable cuando falta el log. No intervienen en el arranque.
- El exportador PNG podía fallar al imprimir una ruta con Ω bajo cp1252.
  Se reprodujo `UnicodeEncodeError` con la versión anterior y se verificó la
  corrección configurando UTF-8 en stdout/stderr. El exportador HTML reutiliza
  ese módulo y recibe la misma configuración. También se indica cómo instalar
  las dependencias cuando falta matplotlib.
- Faltaba Plotly en el Python local. Se instaló para el usuario de SOBREMESA
  y se añadió [requirements-graphs.txt](../../requirements-graphs.txt).
  La instalación por máquina está documentada en [LOCAL_WORKSPACE](../LOCAL_WORKSPACE.md).

No se encontraron más rutas absolutas al proyecto o al usuario en el barrido
de programas versionados, incluidos los analizadores archivados. No se
reescribieron las rutas de procedencia en informes históricos ni las rutas
sintéticas de las pruebas.

## Pruebas aceptadas

| Grupo | Comprobaciones | Resultado |
|---|---:|---|
| Importación, arranque real, menú renderizado, editor → motor, escenario de 2 s y revisión de rutas/integridad | 18 | PASS |
| Analizadores históricos con datos sintéticos y ausencia de logs, en C: y F: | 20 | PASS |
| PowerShell: raíz ajena al directorio actual, rutas Unicode y selección/error de ejecutable | 6 | PASS |
| EMPEZAR → pausa inicial → Play → reloj avanzando → regreso al menú | 3 | PASS |
| Exportación real desde Godot a una ruta con espacios, ñ y Ω | 3 | PASS |
| **Total** | **50** | **PASS** |

Cada exportación real generó 31 archivos PNG y un HTML interactivo. Se usó
Python 3.14.4, matplotlib 3.10.8 y Plotly 7.1.0. Para mantener aislados los
datos de Godot sin alterar la selección de Python, las pruebas de exportación
seleccionaron explícitamente la instalación local mediante PATH y conservaron
su PYTHONUSERBASE. Los lanzadores no incorporan ninguna ruta fija de ese equipo.

La regresión adicional del exportador pasó con `PYTHONUTF8=0` y
`PYTHONIOENCODING=cp1252`: 25 PNG y marcador final válidos. Se comprobó también
el diagnóstico cuando falta una dependencia. Los resultados estructurados
están en [startup_portability_2026-10-15.json](startup_portability_2026-10-15.json).

## Alcance y límites

- Las pruebas de ambas unidades se hicieron en SOBREMESA, con Godot 4.7.1 y
  renderizador OpenGL Compatibility. No certifican la instalación física del
  portátil, su controlador gráfico o sus bibliotecas Python.
- La partida se abre en pausa por diseño. Un intento de prueba que esperaba
  avance automático antes de Play fue descartado.
- Otro intento retiró forzosamente la escena mientras se reproducía y provocó
  un popup de resumen cuando su ventana ya estaba fuera del árbol. Se conserva
  ese resultado; el PASS de salida corresponde al regreso normal al menú por
  el HUD. No se certifica aquí un cierre abrupto de ventana/editor.
- Un primer intento de exportación dejó que Python Install Manager eligiera
  otro runtime al aislar LOCALAPPDATA. No se contó como prueba válida de la
  instalación prevista; los tres PASS usan explícitamente el Python configurado.
- Los modelos físicos y baselines no se modificaron. Los guardrails sobre
  informes existentes conservan 346/346 required PASS; no se realizó una nueva
  validación científica completa.
- Las copias y datos de prueba se conservaron fuera del proyecto después de
  ejecutarlas. No se efectuaron borrados permanentes.

En el portátil, desde la raíz del checkout, las dependencias gráficas se pueden
instalar con el mismo Python que vaya a utilizar Godot:

```powershell
py -3 -m pip install --user -r requirements-graphs.txt
```
