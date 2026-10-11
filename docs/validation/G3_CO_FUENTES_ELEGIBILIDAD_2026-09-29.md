# G3-2 — Procesado CO 2025/2026 y elegibilidad de fuentes (2026-09-29)

Estado: **G3-2 NO-GO para calibrar `Y_CO(t)` por objeto**. Causa del
cambio TN 2303 → FCD 2026 **no demostrada**. Esta pasada no cambia física,
`sim/core`, `sim/fire`, escenarios ni catálogo.

Datos versionados: [comparación de procesado](G3_NIST_TN2303_FCD_CO_PROCESSING_2026-09-29.json)
y [matriz de elegibilidad](G3_CO_SOURCE_ELIGIBILITY_MATRIX_2026-09-29.json).
Cálculo reproducible: [`compare_g3_nist_co_processing.py`](../../scripts/simulation/compare_g3_nist_co_processing.py).
Pruebas: `tests/test_g3_nist_co_processing_versions.py` y
`tests/test_g3_co_source_eligibility.py`.

## 1. ¿Qué publicó NIST sobre `NFRL_Report_8.7.1`?

Comprobado el 29-09-2026, sin encontrar código, notas de versión ni
metodología específica del script:

- Las 48 fichas FCD de *Design Fires – Residential and Office Items* solo
  declaran «Report Process Script Version NFRL_Report_8.7.1» y «Last Updated
  April 7, 2026». Se archivaron sin modificar en un
  [zip](../literature/NIST/FCD_DesignFires_Test001-048_pages_retrieved_2026-09-29.zip).
- El registro del repositorio de datos NIST
  [mds2-2314](https://data.nist.gov/od/id/mds2-2314) (formato NERDm) solo
  lista las versiones 1.0.0 (publicación inicial), 1.0.1 y 1.0.2
  (actualizaciones de metadatos), todas de 20-10-2020. No hay nota de 2026.
- El enlace de la FCD a la guía redirige a la
  [v4a, revisada el 23-10-2020](../literature/NIST/FCD_User_Guide_v4a_2020.pdf).
  Define los totales de especies entre «ignition» y «fire out» con la
  fracción ambiente `X°`; documenta un periodo de fondo de 60 s antes de
  la ignición para el humo y para la incertidumbre, y «below detection
  limit» si el valor es inferior a 3 incertidumbres típicas. No fija de
  forma explícita la ventana de `X°_CO` ni los retardos de los analizadores.
- TN 2303 §2.2.3 dice que CO y CO₂ se midieron con NDIR y que el rendimiento
  es la integral del flujo másico de especie dividida por el cambio de masa
  «over the duration of the experiment». Remite a Di Cristina Torres (2024)
  y a TN 2077 sin dar límites de integración, fondo ni versión del script.
- Una búsqueda web de `NFRL_Report` y del registro de cambios de la FCD no
  devolvió código ni notas. Eso **no prueba** que no existan.

## 2. Comparación cuantitativa de las dos versiones

Se transcribieron las tablas 6 y 8 de TN 2303 (2025) para los 48 ensayos y
se extrajeron de las fichas archivadas los valores de 2026; se importaron
los 48 CSV oficiales (`FCD_Test001…048_2026-04-07.csv`). Los cuatro CSV
importados antes (18/28/29/30) coinciden byte a byte con la descarga de hoy.
Criterios fijados **antes** de evaluar: para 2026, cociente dentro de la `Uc`
publicada; para 2025, dentro del redondeo impreso `±0,0005 kg/kg`.
Conjunto comparable: 43 ensayos con rendimiento y masa numéricos en ambas
versiones.

Hechos verificables:

- **THR no cambió** en ningún ensayo más allá del redondeo impreso (TN
  redondea 24,8 → 25,0, 41,7 → 42,0 y 82,5 → 83,0).
- **La masa perdida sí cambió en 3 ensayos**: 31 (15,730 → 14,914 kg),
  35 (48,107 → 48,557 kg) y 38 (29,414 → 30,130 kg). El cambio no se limita,
  pues, al CO integrado.
- En **13** ensayos el CO total 2026 queda fuera del redondeo impreso en
  2025: 22, 27, 29, 30, 33, 34, 35, 36, 38, 39, 40, 45 y 47.
- El método de la guía (fondo −60..−1 s, ignición → «Fire Out») reproduce
  la FCD 2026 dentro de su `Uc` en **42/43** ensayos (falla 21, +3,7 %); con
  fondo de 120 s, 43/43. Los resúmenes 2026 son coherentes con los CSV
  públicos y la fórmula documentada; 60 y 120 s **no** se distinguen con
  esta incertidumbre.

Hipótesis contrastadas sobre los mismos CSV 2026 (coincidencias con el
redondeo 2025 en los 13 ensayos discrepantes / en los 43):

| Hipótesis | Discrepantes | Total 2025 | Dentro de `Uc` 2026 |
| --- | ---: | ---: | ---: |
| H0 guía: fondo 60 s, ignición → «Fire Out» | 1/13 | 21/43 | 42/43 |
| H1: fondo 60 s, ignición → **fin del archivo** | **10/13** | 31/43 | 35/43 |
| H2: sin restar fondo | 3/13 | 19/43 | 37/43 |
| H3: fondo 120 s | 2/13 | 24/43 | 43/43 |
| H4a/H4b: CO desplazado ±20 s | 2/13 y 0/13 | 24 y 19/43 | 41 y 43/43 |
| H5: desde el inicio del archivo | 2/13 | 20/43 | 42/43 |

Lectura estricta:

- H1 es la **única** hipótesis probada compatible con la mayoría de los
  desfases (22, 27, 29, 30, 33, 34, 35, 36, 38, 40). Por ejemplo, 29 da
  0,03021 kg/kg (impreso 0,030) y 30 da 0,03325 (impreso 0,033).
- **No está demostrada.** Falla en 39, 45 y 47; en 15, 23 y 45 es H0, no
  H1, la compatible con 2025, y ninguna de las dos alcanza el redondeo
  2025 en 9 ensayos (desviaciones ≈1 %, comparables al ruido de la propia
  reconstrucción). No se dispone de las exportaciones de 2025 ni del código.
- La variante «se movió el evento Fire Out» queda **contradicha** en el
  Test029: hay 21,16 MJ de HRR después de «Fire Out», pero ambas versiones
  imprimen THR = 811 MJ y la misma duración de 34,67 min. Si H1 fuera
  cierta, 2025 habría integrado el CO en una ventana distinta de la del
  HRR, algo que ninguna fuente publicada dice.
- Conclusión: la causa **sigue desconocida**. Lo único demostrado es que
  los números de 2026 salen de los CSV públicos con el método de la guía y
  que el desfase se concentra en ensayos con emisión de CO tras «Fire Out».
  No se promedian versiones: SimuFire, si usa alguna, declara FCD 2026.

## 3. Ensayos con `MLR(t)` y CO(t) del mismo ensayo

Ninguna fuente pública encontrada ofrece **series numéricas** de pérdida de
masa del objeto y CO(t) del mismo ensayo a escala de objeto:

| Id | Fuente / ensayos | Combustible real | `MLR(t)` | CO(t) | Régimen | Decisión |
| --- | --- | --- | --- | --- | --- | --- |
| E01 | TN 2303/FCD 1–13 | almohadas solas o en grupos | células de carga, **solo figuras** (ap. C) | escape, CSV | aire libre | validación |
| E02 | TN 2303/FCD 16, 17, 19–24 | sillas individuales, ignitor 3–14 kJ | **solo figuras** | escape, CSV | aire libre | validación (mejor candidato si NIST publica la masa) |
| E03 | 14, 15, 18, 42, 43, 48 | portátiles (15 sobre almohada), mesa, ignitor dominante | — | escape, CSV; 14/18/42/43/48 bajo detección | aire libre | exclusión |
| E04 | 29, 30, 34–36, 40, 41 | sofás **con dos almohadas** | solo masa inicial/final | escape, CSV | aire libre | validación (total y curva FCD 2026) |
| E05 | 25–27, 31, 32, 37–39, 44–47 | juegos de sillas, butacas, colchones con almohadas/ropa | no medida | escape, CSV | aire libre | validación |
| E06 | 28, 33 | alfombra + 2 almohadas; librería + almohada | no medida | escape, CSV | aire libre | exclusión |
| E07 | FCD *Room Flashover … Barrier Fabrics* | salón amueblado completo | no en CSV | escape de campana | recinto ventilado → flashover | validación externa **reservada** |
| E08 | [TN 1453](../literature/NIST/NIST_TN_1453_Smoke_Component_Yields_Room_Scale.pdf) | sofá de cojines, librerías, PVC, cable | células de carga, figuras/tablas | NDIR/FTIR en sala y pasillo, figuras | ventilado pre/post-flashover y 2 ensayos viciados | validación por fase |
| E09 | [TN 1603](../literature/NIST/NIST_TN_1603_Underventilated_Compartment_Fires.pdf) | combustibles puros en bandejas | células de carga ±1 g, figuras | capa superior y escape, figuras | **subventilado** ISO 9705 | validación de régimen (no mobiliario) |
| E10 | [TN 1761](../literature/NIST/NIST_TN_1761_Smoke_Yields_ISO19700_Tube_Furnace.pdf) | material de los objetos de TN 1453 | inferida del avance | medias estacionarias | banco, φ controlada | validación de dependencia con φ |
| E11 | FSRI MaPD, cono | un material (ej. aglomerado), 0,01 m² | masa cada 0,25 s, canal bruto | CO cada 0,25 s, retardo 11 s | banco, aire libre | calibración **solo de familia material**, no objeto |
| E12 | FSRI MaPD, calorímetro de muebles | sofá completo | célula de carga 1 s | **sin CO** | aire libre | validación de MLR/HRR |
| E13 | Otros proyectos FCD | varios | esquema CSV sin masa | escape | varios | exclusión para `Y_CO(t)` |
| E14 | PDF local «NISTIR 5499» | libro de resúmenes de 1994 | — | — | — | exclusión |

Detalles, unidades, incertidumbre, ignitores y bloqueos están en la
[matriz JSON](G3_CO_SOURCE_ELIGIBILITY_MATRIX_2026-09-29.json). Notas:

- TN 1453 anuncia sus series crudas en un informe compañero (ref. 33,
  Peacock et al., «to be published, 2003») que **no se ha localizado**.
- TN 1761 mide masa total y supone MLR estacionaria; en post-flashover CO +
  CO₂ explican a menudo la mitad o menos del carbono del espécimen.
- FSRI: el API de GitHub no declara licencia de redistribucion. Los cinco
  archivos originales se revisaron localmente, pero no se incluyen en esta
  rama; la matriz conserva el commit de origen, nombres y SHA-256 para
  reproducir la auditoria tras obtenerlos directamente de FSRI. Los datos de
  cono son canales brutos (ganancia, offset, línea base, retardos) que exigen
  un protocolo de procesado documentado antes de usarse. Su régimen es llama
  bien ventilada a escala de banco; no calibra objetos ni subventilación sin validar el
  cambio de escala.

## 4. NO-GO y medición que falta

G3-2 sigue **parcial/NO-GO** para `Y_CO(t)` por objeto. Falta, en concreto:

1. La serie numérica de las células de carga de TN 2303 Tests 1–13, 16, 17
   y 19–24, en el eje temporal de los CSV FCD (hoy solo figuras del
   apéndice C). Con ella, sillas y almohadas individuales, con ignitor
   pequeño y al aire libre, serían candidatas a calibración por objeto en
   régimen ventilado.
2. Series crudas de TN 1453 (o un ensayo equivalente de mobiliario con
   célula de carga y CO en sala y vano) en recinto ventilado **y** viciado.
3. Las exportaciones de 2025 o un registro de cambios `NFRL_Report` que
   expliquen el paso TN 2303 → FCD 2026.

No se rellenan esos huecos con `HRR(t)/HOC`, figuras digitalizadas ni
parámetros supuestos. G3-1 y G3-3 mantienen sus gates abiertos; el FED
zonal sigue apagado.

> **Continuado el 07-10** en la
> [selección experimental de la fuente por objeto](G3_OBJECT_FIRE_SOURCE_SELECTION_2026-10-07.md):
> de esta matriz se evalúan E02, E04 y E12 como fuentes prescritas. El
> NO-GO de `Y_CO(t)` por objeto no cambia; lo que se admite es reproducir
> el HRR medido de una corrida.
