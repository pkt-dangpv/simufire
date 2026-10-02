# G3-2 — TN 2303 (2025) frente a FCD reprocesada (2026)

Estado: **diagnóstico cerrado, causa del reprocesado abierta; NO-GO para
calibrar rendimientos instantáneos por objeto**. No se modifica la física.

> **Actualización 2026-09-29.** El cotejo se amplió a los 48 ensayos en
> [procesado y elegibilidad G3-2](G3_CO_FUENTES_ELEGIBILIDAD_2026-09-29.md).
> NIST no publica código ni notas de `NFRL_Report_8.7.1`. THR coincide en
> todos; la masa perdida cambió en 31, 35 y 38, así que la afirmación de
> abajo («el denominador no cambia») vale para 29/30, no para toda la serie.
> Integrar el CO hasta el final del archivo es compatible con 10 de los 13
> desfases, 29/30 incluidos, pero no con 39, 45 y 47: la causa sigue sin
> demostrar.

Fuentes primarias: [NIST TN 2303](../literature/NIST/NIST_TN_2303_Character_Burning_Items.pdf)
(SHA-256 `7844cfe9070e7385f7cfef28dde1b3740b83315ecd35be12377834d447a32c03`,
tablas 6 y 8, pp. impresas 26 y 30; §2.2.2–2.2.3, p. 10), fichas actuales
[Test029](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test029),
[Test030](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test030),
[Test028](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test028)
y [Test018](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test018)
(`NFRL_Report_8.7.1`, 07-04-2026), más los cuatro CSV crudos con SHA-256 en
[la ficha G3-2](G3_NIST_FCD_FURNITURE_SUMMARY_2026-09-27.json). Las tablas
del PDF se verificaron visualmente; sus unidades HCN son **×10⁻³ kg/kg**.
La transcripción comparativa está
[versionada aparte](G3_NIST_TN2303_FCD_RECONCILIATION_2026-09-28.json)
para no hacer pasar el HCN de 2025 por un dato de la FCD 2026.

## Comparación de magnitudes del mismo ensayo

| Test | Masa perdida TN / FCD (kg) | THR TN / FCD (MJ) | `Y_CO` TN 2025 / FCD 2026 (kg/kg) | CO total implícito TN → FCD (kg) | `Y_HCN` TN 2025 (kg/kg) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 29, sofá A + 2 cojines | 52,116 / 52,116 | 811 / 811 | 0,030 ± 0,001 / 0,02671 ± 0,00096 | 1,56348 → 1,39202 | 0,00020 ± 0,00002 |
| 30, sofá B + 2 cojines | 77,888 / 77,888 | 1426 / 1426 | 0,033 ± 0,001 / 0,0306 ± 0,0011 | 2,57030 → 2,38337 | 0,00025 ± 0,00003 |
| 28, alfombra **+ 2 cojines** | 3,3125 / 3,313 | 23,2 / 23,2 | 0,012 ± 0,040 / 0,01175 ± 0,00043 | ≈0,03975 → 0,03893 | 0,00046 ± 0,00005 |
| 18, mesa con piloto | 0,042 / bajo detección | 0,93 / 0,93 | 0,060 ± 0,043 / bajo detección | **No comparable** | 0,00286 ± 0,00047 |

En 29 y 30, el denominador gravimétrico y THR **no cambian**. El descenso
de `Y_CO` es ≈10,97 % y ≈7,27 %, respectivamente. Por tanto, atribuirlo a
otra masa perdida o a otro calor total sería falso: la diferencia está en
el CO integrado informado o en su tratamiento. No tenemos el código ni
las notas de cambio de `NFRL_Report_8.7.1` para demostrar **qué** paso del
tratamiento cambió. La reconstrucción independiente del escape desde los
CSV 2026 (1,38965 y 2,38497 kg con fondo candidato de 60 s) reproduce la
**versión actual**, no la de 2025. No promediar ambas versiones ni tomar el
desfase como variabilidad entre sofás.

Las cifras HCN de la tabla 8 son del **informe 2025**, no de las fichas
FCD 2026 ni de sus CSV: estos no incluyen una columna HCN. TN 2303 describe
un analizador FTIR de gases traza con respuesta del orden de 24 s y
sensibilidad práctica limitada por interferencias. Los rendimientos HCN
de 29/30 corresponden al conjunto sofá **más cojines**; el 28 mezcla
alfombra y cojines. El 18 no mantuvo combustión al retirar el piloto; su
valor de informe no calibra una mesa autónoma. Conservar `hcn: null` en
la ficha FCD 2026 es correcto; estos valores se citan separados por versión.

## ¿Existe pérdida de masa temporal para estos objetos?

TN 2303 §2.2.2 afirma que la masa inicial/final se determinó siempre, pero
la **pérdida de masa transitoria con células de carga solo se midió en
Tests 1–24**. El apéndice C representa esas series, no las de 28/29/30.
Los CSV públicos de 28/29/30 tienen HRR, caudal y fracciones volumétricas
en el escape, pero ninguna columna de masa del objeto o `MLR(t)`.
Por consiguiente, aunque podamos reconstruir una curva provisional de
`CO_escapado(t)` con la [guía FCD](https://www.nist.gov/system/files/documents/2020/11/19/FCD_User_Guide_v4a.pdf),
no podemos dividirla por una `MLR(t)` medida para obtener `Y_CO(t)`.
Sustituir `MLR(t)` por `HRR(t)/HOC_efectivo_global` presupondría precisamente
lo que se quiere comprobar y falla en pirólisis/subventilación.

## Gate para avanzar

1. Mantener como candidatos **de ensayo completo al aire libre** las curvas
   de HRR y CO de escape de 29/30; no separar cojines ni extrapolar a un
   incendio subventilado o a concentración respiratoria.
2. Resolver con fuente primaria los cambios de procesamiento 2025→2026
   (fondo, calibración, alineación o integración); ninguna causa está
   demostrada aún. Hasta entonces usar una versión declarada, no mezclar.
3. Buscar ensayos de mobiliario/material **con `MLR(t)` y CO(t) medidos**,
   más ensayos de recinto ventilado/subventilado, para formular y contrastar
   `Y_CO(t)` por régimen. HCN requiere su propia serie y procedencia.
4. Mantener Test028 como conjunto mixto y Test018 como control de exclusión.

No se ha hecho commit/push ni se ha modificado `sim/core`, `sim/fire`, el
editor o escenarios distribuidos en esta tarea de datos.
