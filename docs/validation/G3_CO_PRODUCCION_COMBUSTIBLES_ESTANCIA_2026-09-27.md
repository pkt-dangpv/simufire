# G3 — CO producido por combustible y estancia (2026-09-27)

Estado: **diagnóstico, NO-GO para cambiar la física o activar FED zonal**. Esta
nota distingue tres magnitudes distintas: CO **generado** por el incendio,
CO **presente** en la estancia y concentración de CO a una **altura** concreta.
La primera no determina por sí sola las otras dos.

## Evidencia experimental primaria

El rendimiento `Y_CO` de las tablas NIST se expresa en **kg de CO por kg de
masa perdida por el combustible**. Es un promedio del ensayo o de una fase;
no es una tasa instantánea, no describe todos los productos vendidos bajo el
mismo nombre y no equivale a `kg/MJ` sin un calor efectivo de combustión
medido para ese ensayo.

| Ensayo | Especimen y condiciones | `Y_CO` (kg/kg) | Lectura correcta |
| --- | --- | ---: | --- |
| NIST TN 2303, pruebas 29–41 | Siete sofás/igniciones, al aire libre y bien ventilados | 0,030–0,037 **en el informe de 2025** | Valores globales de esos sofás, no de cualquier sofá ni de un recinto subventilado. La FCD actualizada no coincide exactamente. |
| NIST TN 2303, prueba 18 | Mesa auxiliar de aglomerado | 0,060 ± 0,043 **en el informe**; FCD: bajo detección | Solo perdió ≈ 0,04 kg; no mantuvo la combustión al retirar el ignitor. **No** sirve para calibrar una mesa que arde plenamente. |
| NIST TN 2303, prueba 28 | Alfombra de polipropileno **con dos cojines iniciadores** | 0,012 ± 0,040 **en el informe**; FCD: 0,01175 ± 0,00043 | Mezcla de combustibles; **no** es rendimiento aislado de alfombra. La discrepancia de incertidumbre entre publicaciones exige auditar el CSV. |
| NIST TN 2303, prueba 33 | Librería de aglomerado **con cojín iniciador** | 0,015 ± 0,001 | Ardió poco más allá del cojín; tampoco representa una librería desarrollada. |
| NIST TN 1453, tabla 25 | Cojines tapizados en sala, antes/después de flashover | 0,0144 ± 35 % / 0,051 ± 25 % | El mismo combustible cambia de fase y de rendimiento. |
| NIST TN 1453, tabla 25 | Librerías de aglomerado, antes/después de flashover | 0,024 ± 55 % / 0,046 ± 30 % | Proxi parcial para tablero, **no** para madera maciza. |

Fuentes: [NIST TN 2303, tablas 6 y 8, pp. 25–30](https://doi.org/10.6028/NIST.TN.2303)
y [NIST TN 1453, tabla 25, p. 77](https://nvlpubs.nist.gov/nistpubs/Legacy/TN/nbstechnicalnote1453.pdf).
TN 2303 mide piezas al aire libre, con ventilación abundante; TN 1453 añade
ensayos de sala y fases pre/post-flashover. No combinar sus números como si
fueran réplicas del mismo régimen.

La [base FCD de NIST](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items)
publica fichas y CSV por ensayo y fue actualizada después del informe. Por
ejemplo, la [ficha actual del sofá 29](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test029)
da 0,02671 ± 0,00096 kg/kg, frente a 0,030 ± 0,001 en la tabla 8 de TN
2303. La [ficha del sofá 30](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test030)
da 0,0306 ± 0,0011, frente a 0,033 ± 0,001. No mezclar cifras de versiones
sin registrar la metodología y fecha del reprocesado. Los cuatro CSV de las
pruebas 29/30/28/18 ya están fijados con SHA-256, pero el desfase de
rendimientos entre el informe y las fichas sigue sin conciliarse. Ninguno
de estos datos autoriza aún una ley de CO por objeto o recinto.

Si se quiere una **cantidad** en lugar de un rendimiento, las fichas FCD
actuales permiten multiplicar masa perdida por el rendimiento global **de
la misma ficha**: sofá 29, 52,116 × 0,02671 ≈ **1,39 kg de CO**; sofá 30,
77,888 × 0,0306 ≈ **2,38 kg**. La [mesa 18](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test018)
figura **por debajo del límite de detección** en la FCD: no se le asigna
un total fiable. La [alfombra más cojines 28](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test028)
da 3,313 × 0,01175 ≈ **0,039 kg** del conjunto, sin poder atribuirlo solo
a la alfombra. Son emisiones totales de ensayos específicos, no masas de CO
retenidas en una habitación.

### Ficha reproducible G3-2 (avance parcial)

Las tablas 2–3 de las fichas FCD actuales para [Test029](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test029),
[Test030](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test030),
[Test028](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test028)
y [Test018](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test018)
se han transcrito a una [ficha JSON versionada](G3_NIST_FCD_FURNITURE_SUMMARY_2026-09-27.json)
con masa perdida, calor total/efectivo, pico de HRR, rendimientos de O₂,
CO₂, CO y hollín, incertidumbre publicada del rendimiento de CO, composición
del espécimen y elegibilidad. Las páginas declaran el procesado
`NFRL_Report_8.7.1`, actualizado el 07-04-2026. La ficha **no** es un
catálogo físico del motor ni convierte valores desconocidos de HCN en cero.

El cálculo auditado `masa perdida × rendimiento de la misma prueba` da
1,392018 kg (29), 2,383373 kg (30) y 0,038928 kg (28). El tercero corresponde
al conjunto alfombra **más dos cojines**; la mesa 18 queda sin rendimiento
utilizable porque FCD lo declara bajo el límite de detección. Para los dos
sofás, `Y_CO / calor efectivo del mismo ensayo` equivale aritméticamente a
0,0017166 y 0,0016721 kg/MJ, respectivamente. Estos cocientes globales
**no** son curvas temporales ni coeficientes trasladables sin más a un sofá
de SimuFire, y las incertidumbres de las magnitudes derivadas no se han
estimado.

Los cuatro CSV oficiales se importaron sin modificar:
[Test029](../literature/NIST/FCD_Test029_2026-04-07.csv),
[Test030](../literature/NIST/FCD_Test030_2026-04-07.csv),
[Test028](../literature/NIST/FCD_Test028_2026-04-07.csv) y
[Test018](../literature/NIST/FCD_Test018_2026-04-07.csv). Sus SHA-256, filas,
ejes de tiempo y valores observados se fijan en la ficha JSON y en el
[auditor reproducible](../../scripts/simulation/audit_g3_nist_fcd_csv.py).
Los cuatro tienen muestreo de 1 s y nueve columnas; 29/30/28 contienen dos
`NaN` (HRR y O₂) en la última fila, 18 ninguno. Los picos e integrales
HRR hasta el evento «Fire Out», no hasta el final del archivo, reproducen
los valores redondeados de las cuatro fichas.

La columna `CO (Vol Fr)` es **fracción volumétrica seca en el escape de la
campana**, no concentración de una sala. La [guía oficial de la
FCD](https://www.nist.gov/system/files/documents/2020/11/19/FCD_User_Guide_v4a.pdf),
§3, sí proporciona la conversión de esa fracción y el caudal de escape a
CO neto emitido entre ignición y apagado:

```text
CO_escapado_kg_s(t) = [X_CO_escape(t) − X_CO_ambiente]
                     × m_escape_kg_s(t) × M_CO/M_aire
```

El [reconstructor de investigación](../../scripts/simulation/reconstruct_g3_nist_fcd_co.py)
usa `M_CO = 28,01`, `M_aire = 28,97 kg/kmol`, no recorta tasas negativas
por ruido y declara dos fondos candidatos, −60..−1 y −120..−1 s. Los
totales de CO neto en el escape obtenidos con el primero son:

| Ensayo | Reconstruido, fondo 60 s | Ficha: masa × rendimiento | Interpretación |
| --- | ---: | ---: | --- |
| Test029 | 1,38965 kg | 1,39202 kg | Sofá A completo, incluidos cojines |
| Test030 | 2,38497 kg | 2,38337 kg | Sofá B completo, incluidos cojines |
| Test028 | 0,03944 kg | 0,03893 kg | **Alfombra + cojines**, inseparables |
| Test018 | ≈0,00235 kg, solo diagnóstico | Bajo detección | Piloto activo; **no** calibrar mesa |

Para los tres ensayos con rendimiento publicado, las diferencias están
dentro de la incertidumbre expandida de `Y_CO` multiplicada por la masa
perdida. El fondo de 120 s da 1,39020, 2,38582 y 0,03897 kg en 29/30/28.
El caso 18 sigue bajo el límite de detección pese al número que devuelve la
operación algebraica; no convertirlo en un rendimiento de aglomerado. Las
series no son constantes: en Test029 el candidato de 60 s suma 0,0684,
0,3035, 0,3021 y 0,7156 kg en 0–299, 300–599, 600–1199 y 1200–2080 s.

Esto **no** verifica que `NFRL_Report_8.7.1` use exactamente nuestro intervalo
de fondo o cada detalle del procesado. [NIST TN
2077](https://doi.org/10.6028/NIST.TN.2077), §4.4, describe retardos de
transporte/análisis y la alineación temporal de señales; falta comprobar
cómo se aplicó a esta exportación. El CSV tampoco contiene pérdida de masa
del espécimen por segundo, así que **no** permite obtener `Y_CO(t)`.
La curva de escape reconstruida es un **candidato experimental para
contraste**, no una ley del sofá, una concentración respiratoria, ni una
calibración de SimuFire. El
[cotejo TN 2303 ↔ FCD 2026](G3_NIST_TN2303_FCD_RECONCILIATION_2026-09-28.md)
demuestra que masa perdida y THR de 29/30 son idénticos en ambas versiones;
el cambio de `Y_CO` está en el CO integrado informado o su tratamiento,
pero el paso concreto del reprocesado sigue sin documentación. TN 2303
§2.2.2 confirma que la masa transitoria se midió solo en Tests 1–24, no
en 28/29/30. La tabla 8 del informe sí ofrece HCN global de 2025, pero
las fichas/CSV 2026 no tienen HCN; no se mezclan versiones. Siguen faltando
ensayos de material aislado y de combustión subventilada. La
prueba `tests/test_g3_nist_fcd_furniture_summary.py` fija método, unidades,
números y exclusiones. G3-2 permanece **parcial/NO-GO**.

### Pasada del 29-09: procesado 2025/2026 y fuentes con `MLR(t)`

Detalle en [procesado y elegibilidad G3-2](G3_CO_FUENTES_ELEGIBILIDAD_2026-09-29.md).
NIST no publica código, registro de cambios ni metodología propia de
`NFRL_Report_8.7.1`: las fichas solo dan versión y fecha, el registro
`mds2-2314` termina en versiones de metadatos de 2020 y la guía vigente es
la v4a de 2020, ahora [guardada con SHA-256](../literature/NIST/FCD_User_Guide_v4a_2020.pdf).
Con los 48 CSV oficiales y las 48 fichas archivadas:

- el método de la guía (fondo de 60 s, ignición → «Fire Out») reproduce la
  FCD 2026 dentro de su `Uc` en 42 de 43 ensayos comparables;
- entre versiones, THR no cambia, pero la masa perdida sí en 31, 35 y 38, y
  el CO sale del redondeo impreso de 2025 en 13 ensayos;
- integrar el CO hasta el final del archivo es la única hipótesis probada
  compatible con 10 de esos 13 desfases (29 y 30 incluidos), pero falla en
  39, 45 y 47 y contradice el THR del Test029 si se interpreta como un
  «Fire Out» movido. **La causa sigue sin demostrar.** No se mezclan ni se
  promedian las versiones 2025 y 2026.

No se encontró ninguna fuente pública con series **numéricas** de pérdida de
masa y CO del mismo ensayo a escala de objeto. TN 2303 midió la masa de los
Tests 1–24 con células de carga, pero solo la publica en figuras; TN 1453
(ahora [guardado](../literature/NIST/NIST_TN_1453_Smoke_Component_Yields_Room_Scale.pdf))
remite sus series a un informe compañero no localizado; TN 1603 y TN 1761
cubren subventilación y φ controlada, pero con combustibles puros o
material en régimen estacionario; los datos de cono de FSRI tienen masa y CO
a 4 Hz, pero de un material y a escala de banco, y su calorímetro de muebles
no mide CO. G3-2 queda **NO-GO para `Y_CO(t)` por objeto** hasta obtener
la masa numérica de TN 2303 1–13/16/17/19–24 o series equivalentes en
recinto ventilado y viciado.

### Una sala amueblada de verdad

[Di Cristina et al., ensayo de sala amueblada de 3,6 × 3,6 × 2,42 m](https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=957121)
incluye sofá, butaca, mesa de centro, mesa auxiliar, librería, cojines y
decoración. Las tres pruebas solo cambian la barrera del sofá. La masa de CO
emitida por **toda la sala** se puede reconstruir de sus tablas 1 y 3:

| Configuración | Masa perdida | `Y_CO` global | CO total calculado | HRR pico / flashover |
| --- | ---: | ---: | ---: | --- |
| Sofá sin barrera | 114,1 kg | 0,032 kg/kg | ≈ 3,65 kg | 9063 kW / 5,7 min |
| Barrera parcial | 113,2 kg | 0,050 kg/kg | ≈ 5,66 kg | 6076 kW / 18,72 min |
| Barrera completa | 64,6 kg **estimados** | 0,044 kg/kg | ≈ 2,84 kg **estimados** | 929 kW / sin flashover |

Son totales del ensayo **hasta apagado**, no la masa que quedó dentro en un
instante; parte salió por la abertura y el conducto de medida. El último
valor hereda la estimación de masa perdida que hacen los autores. Tampoco
permiten asignar 3,65 kg al sofá: en el caso sin barrera ardieron otros
objetos. Las figuras 4, 6 y 7 muestran que HRR, tasa de CO y CO acumulado
cambian fuertemente en el tiempo: el rendimiento global no es una curva.

## Qué hace hoy SimuFire

En [`CombustionSystem.gd`](../../sim/fire/CombustionSystem.gd),
`_resolve_room_co_yield_kg_per_MJ()` (≈ línea 2876) obtiene **una media para la
estancia** ponderando los combustibles que aún conservan energía, también los
que no están ardiendo. Luego (≈ líneas 2025–2092) usa:

```text
phi_proxy = clamp(1 / o2_hrr_factor, 1, 10)  [o fijo si no hay llama]
Y_CO_room = clamp(Y_base_room · exp(k · (phi_proxy - 1)), Y_base_room, Y_max)
CO_generado_paso = Y_CO_room · base_de_energía_CO_paso
```

Hay multiplicadores de subventilación, postcombustión/latencia y un override
forzado para casos CFAST; después opera un límite de balance de carbono. El
`phi_proxy` **no** es la relación de equivalencia global medida en un ensayo.
La temperatura interviene en la evolución del incendio, pero no es variable
explícita de esta ley de rendimiento. Por tanto, hoy no hay una curva
experimental `Y_CO(combustible, HRR, O2, temperatura, ventilación, tiempo)`
ni contabilidad de `CO_generado_paso` atribuible a cada objeto.

La plantilla de salón de [`BuildingTemplate.gd`](../../sim/templates/BuildingTemplate.gd)
(≈ líneas 606–650) declara lo siguiente. `energía × yield` es **solo un
potencial nominal aritmético** si toda esa energía se consumiera con el yield
base, no la predicción del motor ni una medición:

| Objeto | Energía nominal | Yield base | Producto nominal |
| --- | ---: | ---: | ---: |
| Sofá | 1100 MJ | 0,00040 kg/MJ | 0,440 kg |
| Mesa de centro | 280 MJ | 0,00060 kg/MJ | 0,168 kg |
| Mueble TV | 520 MJ | 0,00025 kg/MJ | 0,130 kg |
| Librería | 1300 MJ | 0,00025 kg/MJ | 0,325 kg |
| Alfombra | 520 MJ | 0,00050 kg/MJ | 0,260 kg |
| Butaca | 580 MJ | 0,00040 kg/MJ | 0,232 kg |
| Aparador | 1700 MJ | 0,00025 kg/MJ | 0,425 kg |
| **Total teórico, no simulado** | **6000 MJ** | — | **1,980 kg** |

No comparar los 1,980 kg con los 3,65 kg de la sala NIST como error
porcentual: no son el mismo mobiliario, carga, ignición, ventilación ni
duración; además la ley viva amplifica y limita el rendimiento por paso.
Esta cuenta sí descubre una laguna del modelo: ni siquiera el total nominal
se forma sumando emisiones de objetos reales activos, sino aplicando una
media de habitación a otra base energética.

## Curva y presupuesto que faltan

La forma contable que hay que **medir y validar antes de adoptar** es:

```text
producción_CO(t) = suma_objetos [masa_perdida_i(t) × Y_CO_i(régimen_i(t))]
inventario_CO(t+dt) = inventario_CO(t) + producción - oxidación
                     + transporte_entrante - transporte_saliente
```

La masa consumida no puede inferirse solo de HRR bajo ventilación limitada:
puede continuar la pirólisis mientras la combustión efectiva y el HRR bajan.
Hay que medir/registrar por objeto masa o energía de combustible consumida,
HRR efectivo, estado llama/latencia, O2 disponible, temperatura relevante,
ventilación y `CO_generado_paso`. La relación de equivalencia física requiere
flujos de combustible y aire/O2; el `o2_hrr_factor` actual no la sustituye.
[Pitts (1995)](https://www.nist.gov/publications/global-equivalence-ratio-concept-and-formation-mechanisms-carbon-monoxide-enclosure)
advierte que el cociente global de equivalencia solo predice CO en condiciones
limitadas: también intervienen apagado químico del penacho, aire que entra en
una capa rica y pirólisis de madera en capas calientes pobres en O2. Así que
no se debe ajustar una sola exponencial por `O2` a un punto CFAST.

## Secuencia propuesta y gates

1. **Datos:** importar con procedencia los ensayos individuales de NIST TN
   2303/FCD (masa, HRR y CO por tiempo) y TN 1453 (fases y ventilación).
   Resolver la discrepancia entre TN 2303 y las fichas FCD actualizadas;
   guardar CSV, checksum, versión/fecha del procesado y unidades.
   Etiquetar los ensayos contaminados por ignitores/cojines y dejar sin
   calibrar mesa y alfombra donde falta aislamiento. Elegir un ensayo de
   salón amueblado de Di Cristina como validación **externa**, no como fuente
   y destino simultáneos de un ajuste.
2. **Contabilidad pasiva:** producir una traza por objeto y por estancia,
   conservando byte a byte la física OFF. Exigir que suma de objetos,
   generación de habitación, inventario y flujos cierren; separar CO
   producido de CO oxidado y de CO evacuado. No empezar el reparto zonal
   mientras este presupuesto no cierre.
3. **Ley de producción:** contrastar una base por familia material y régimen
   (llama ventilada, ventilación limitada, latencia) con curvas de tasa y
   acumulado, nunca solo el CO final. Definir incertidumbre y una opción
   explícita para materiales desconocidos. Cualquier cambio físico va
   detrás de flag OFF, con mutaciones y referencia intacta en OFF.
4. **Estancia:** validar HRR, pérdida de masa, CO emitido total y curva en el
   ensayo amueblado; repetir con puerta/ventana y sin ellas. Solo entonces
   estudiar advección, intercambio entre zonas y CO a altura respiratoria.

**Gate vigente:** la discrepancia SimuFire/CFAST de CO bajo no autoriza todavía
una transferencia artificial de CO a la zona inferior. Hay que cerrar antes
la fuente de CO y el presupuesto de masa de especie, y después contrastar
los valores zonales con ensayos medidos. Ver
[gate de transporte G3](G3_CO_CFAST_NIST_TRANSPORT_GATE_2026-09-27.md).
