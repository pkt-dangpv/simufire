# G3/D1 - Cp del n-heptano líquido y revisión de los supuestos del gas

Fecha: 2026-10-06. Checkpoint de entrada: `19239927` (main = rama shareable,
locales y remotas). Alcance: búsqueda de fuentes primarias, cálculos y
pruebas offline, biblioteca y documentación. Sin cambios en `sim/`,
escenarios, interruptores ni informes de referencia. No se ejecuta Godot.
El adaptador **no** se implementa. Csat **no** se acepta como sustituto de
Cp: se convierte.

Continúa y revisa el
[gate del 05-10](G3_D1_HEPTANE_REAL_PROFILE_ELIGIBILITY_2026-10-05.md).

Implementado en aislamiento el 06-10:
[esquemas reales en GDScript](G3_D1_HEPTANE_REAL_CP_IMPLEMENTATION_2026-10-06.md).
Este informe se conserva como registro del gate.

## Decisión

| Pregunta | Decisión | Alcance exacto |
| --- | --- | --- |
| Cp real del líquido | **GO parcial** | Cp isobárico a 100 kPa entre 280 K y el punto de ebullición a 100 kPa (371,139 K de la fuente): 279,9855 a 371,1029 K en ITS-90. Obtenido de Csat por una conversión justificada, no por reetiquetado. |
| Cp del gas y sus supuestos | **GO parcial condicionado, sin cambio de rango** | 298,16 a 470 K de la fuente. La calorimetría original no se obtuvo: masa molar y escala siguen como supuestos declarados y acotados. El tramo supuesto queda contrastado con una correlación oficial. |
| Compatibilidad conjunta | **GO parcial, solo diseño** | Dos perfiles de una misma familia de esquema real. Ventana común 298,1355 a 371,1029 K (ITS-90). |
| Contrato sintético actual | **NO-GO por diseño** | Sin cambio: hace falta el esquema real versionado. |
| Presupuesto neto B | **NO-GO, gate aparte** | Sin cambio. |

Lo que cambia respecto al 05-10: el líquido pasa de NO-GO a GO parcial, y
la conversión de escala se reclasifica de «GO» a **aproximada**, con su
residuo medido.

## Preguntas y respuestas

1. **Qué propiedad exige el helper.** Calor específico isobárico en
   kJ/(kg·K), por tramos lineales, con referencia 298,15 K y 100 000 Pa
   dentro del soporte. Para la fase líquida, `caloric_model:
   declared_liquid` y ruta `constant_pressure`.
2. **Fase, rango y ruta.** Líquido subenfriado a 100 kPa, desde la
   temperatura inicial del combustible hasta su punto de ebullición a esa
   presión.
3. **Qué faltaba para convertir Csat.** No una densidad, sino cuatro cosas:
   el volumen molar sobre isobaras, su derivada primera respecto a la
   temperatura, su derivada segunda, y la presión de vapor con su
   pendiente. Ahora están las cuatro.
4. **Qué parte del gas respalda su fuente original.** Ninguna nueva: el
   artículo original sigue sin obtenerse. Lo que mejora es el contraste.

## Búsqueda primaria

| Fuente | Qué aporta | Estado y derechos |
| --- | --- | --- |
| [Archivo ThermoML del NIST](../literature/data/NIST_THERMOML_HEPTANE_2008/PROVENANCE.json): densidad del n-heptano líquido, Schilling, Kleinrahm y Wagner, J. Chem. Thermodyn. 40 (2008) 1095 | 151 puntos (p, ρ, T): nueve isotermas de 233,15 a 393,15 K cada 20 K, de 0,1 a 30 MPa, densímetro de un flotador | **Archivado.** ThermoML/Data Archive, doi:10.18434/mds2-2422, versión 1.2.6, [NIST Open License](https://www.nist.gov/open/license): uso y redistribución con mención del NIST. |
| [Zábranský y Růžička, J. Phys. Chem. Ref. Data 23, 55 (1994)](https://srd.nist.gov/JPCRD/jpcrd469.pdf) | Reevaluación del Csat del heptano en ITS-90 a partir de los datos crudos del NBS y del Bureau of Mines; tabla de Csat y de Cp | **No archivado.** Copyright cedido a AIP y ACS. Solo localizador, hash y veinte valores citados como contraste. |
| [Scott, U.S. Bureau of Mines Bulletin 666 (1974)](../literature/Reviews_and_Models/USBM_Bulletin_666_Alkane_Ideal_Gas_Properties_1974.pdf) | Propiedades de gas ideal de los alcanos, 0 a 1500 K, valores correlacionados | **Archivado.** Publicación del Gobierno de EE. UU., copia de la biblioteca digital de la UNT. |
| NBS Circular 461 (1947) | Densidad solo a 20 y 25 °C | Resultado negativo; no se archiva. |
| Smith, Beattie y Kay, JACS 59, 1587 (1937) | Volúmenes que usó RP2526 | No obtenido: copia del editor no abierta. |
| Waddington, Todd y Huffman, JACS 69, 22 (1947) | Calorimetría original del gas | No obtenido: copia del editor no abierta; no está en los servidores del NIST ni de OSTI. |

No se encontró ninguna medición primaria de Cp isobárico del líquido a
100 kPa entre 280 y 371 K. El patrón calorimétrico es Csat por
construcción: los calorímetros adiabáticos llevan espacio de vapor. La
columna de Cp de la reevaluación de 1994 tampoco es una medición: sale de
Csat por la misma relación termodinámica.

Los datos de ThermoML son la captura que hace el NIST de los datos del
artículo. **El artículo original no se inspeccionó**, así que no se han
cotejado con su página impresa. La incertidumbre que traen (expandida al
95 %, 0,15 a 0,20 kg/m³) la evaluó el compilador del archivo, y la pureza
de la muestra, 99,3 % molar, es la declarada por el proveedor.

## La transformación y lo que exige

Csat es el calor por kelvin siguiendo la curva de saturación. De su
definición y de una relación de Maxwell:

    Cp(T, P0) = Csat + T·(∂V/∂T)p·(dPsat/dT) − T·∫[Psat→P0] (∂²V/∂T²)p dP

El primer término lleva de Csat a Cp a la presión de saturación; lo dan
RP1841 (p. 471) y la reevaluación de 1994 (ec. 9). El segundo lleva de la
presión de saturación a 100 kPa; RP1841 ya advierte que necesita la
derivada segunda del volumen. La identidad es exacta. Sus entradas no.

| K fuente | K ITS-90 | Psat, kPa | Término 1 | Término 2 | Cp − Csat | Cp, kJ/(kg·K) |
| --- | --- | --- | --- | --- | --- | --- |
| 280 | 279,9855 | 2,29 | 0,0065 | −0,0161 | −0,0096 | 2,179216 |
| 298,16 | 298,1355 | 6,10 | 0,0167 | −0,0194 | −0,0027 | 2,243777 |
| 310 | 309,9708 | 10,71 | 0,0290 | −0,0215 | 0,0075 | 2,289062 |
| 330 | 329,9650 | 24,82 | 0,0670 | −0,0236 | 0,0434 | 2,369941 |
| 350 | 349,9633 | 51,31 | 0,1404 | −0,0204 | 0,1200 | 2,457366 |
| 370 | 369,9636 | 96,69 | 0,2735 | −0,0019 | 0,2716 | 2,550294 |
| 371,139 | 371,1029 | 100,00 | 0,2836 | 0 | 0,2836 | 2,555858 |

Términos y diferencia en J/(mol·K). Los catorce nodos están en el
[resultado guardado](G3_D1_HEPTANE_LIQUID_AUDIT_2026-10-06.json).

Tres hechos que salen del cálculo:

- La corrección es **negativa** por debajo de unos 302 K: a baja
  temperatura domina el término de presión. Cp a 100 kPa es menor que Csat.
- Nunca pasa de 0,284 J/(mol·K), un 0,11 % de Csat.
- Por eso basta una exactitud modesta en las derivadas: un 1 % de error en
  la primera mueve Cp como mucho 0,003 J/(mol·K), y un 25 % en la segunda,
  0,006. Residuo de conversión declarado: 0,01 J/(mol·K).

Que el efecto sea pequeño no es el argumento para aceptar el dato. El
argumento es que ahora la transformación se puede hacer y acotar.

## Datos volumétricos: método y comprobaciones

Método del auditor, fijado antes de ejecutarlo:

- En presión: polinomio de segundo grado por los tres puntos de menor
  presión de cada isoterma. A 373,15 y 393,15 K el punto más bajo está en
  1,1 MPa, así que llegar a 0,1 MPa es una extrapolación de 1 MPa; frente a
  un polinomio cúbico cambia 0,004 y 0,008 kg/m³.
- En temperatura: polinomio cúbico por cuatro isotermas vecinas, derivado
  analíticamente. La tabla es escasa (20 K), así que la dependencia del
  método se mide: con tres y con cinco isotermas la derivada primera cambia
  como mucho un 0,44 % y la segunda un 8,9 %. Cotas predeclaradas: 1 % y
  25 %.
- La derivada primera se evalúa a la presión de saturación y la segunda a
  la presión media entre saturación y 100 kPa, como pide la identidad.

Comprobaciones con fuentes archivadas e independientes de ese archivo:

- **Pendiente de la densidad a 22,5 °C:** −0,8461 kg/(m³·K) frente a
  −0,849 de RP1271 (1940). Cociente 0,9965, dentro del 1 % que permite
  resolver RP1271.
- **Densidad absoluta a 20 °C:** un 0,047 % mayor que la de RP1271. Es una
  discrepancia real entre muestras y se conserva. No afecta a la decisión:
  desplaza la corrección en 0,0001 J/(mol·K).
- **v·dP/dT a 22,5 °C:** 0,0402 J/(mol·K) frente a 0,0401 de las columnas
  de RP1841.
- **Entalpía de saturación impresa, 298,16 → 370 K:** integrar Csat da
  17 199,94 J/mol; el término v·dP con el volumen medido, 14,25; la tabla
  impresa sube 17 214. Cierre: −0,19 J/mol, con cota predeclarada de 1,6.
- La ecuación empírica 12 de RP2526 daba 13,34 para ese término: 0,91 menos
  que el volumen medido, dentro de los 2 J/mol que la propia fuente
  declara.

## Coherencia entre Cp y entalpía

Integrar el Cp convertido entre 298,16 y 370 K da 17 205,71 J/mol. El
incremento isobárico a 100 kPa que se deduce de la columna de entalpía
impresa, corrigiendo el escalón de presión en cada extremo (8,69 y
0,22 J/mol), es 17 205,54. Residuo: 0,18 J/mol.

Integrar Csat como si fuera Cp a 100 kPa se queda 5,60 J/mol corto, un
0,03 %. Es pequeño y sistemático; la conversión lo elimina.

## Escala de temperatura: etiquetas y magnitud

La reevaluación de 1994 lo dice sin ambigüedad (pp. 56-57): al cambiar de
escala no solo cambia la temperatura a la que se asigna el calor
específico, **cambia la propia magnitud**, y ese cambio suele ser el mayor.
La conversión exacta rehace cada cociente calor/ΔT con las temperaturas
inicial y final convertidas, y exige los datos crudos. Aplicar la fórmula
de corrección a valores ya suavizados no es exacto.

Este gate y el del 05-10 convierten valores suavizados. Es por tanto una
**aproximación**, y se mide contra la conversión exacta publicada, a la
misma temperatura numérica:

| K | Solo etiquetas | Etiquetas y magnitud (este gate) | Exacta, JPCRD 1994 |
| --- | --- | --- | --- |
| 298,15 | +0,004 % | +0,044 % | +0,06 % |
| 310 | +0,005 % | +0,043 % | +0,04 % |
| 340 | +0,007 % | +0,012 % | +0,04 % |
| 370 | +0,007 % | −0,006 % | +0,05 % |

- Cambiar solo las etiquetas de los nodos deja fuera casi todo el efecto.
- La diferencia máxima con la conversión exacta es 0,056 %, a 370 K. No es
  solo escala: por encima de 360 K la reevaluación convirtió únicamente las
  temperaturas y volvió a correlacionar los datos crudos. Se declara 0,07 %
  como diferencia frente a la evaluación publicada; no es una tolerancia
  que valide.
- Para el gas no hay datos crudos ni conversión exacta publicada con la que
  medir. La aproximación es la misma; su residuo no está acotado por
  evidencia primaria, solo por el tamaño del efecto (≤ 0,05 % en Cp).

Esto corrige el informe del 05-10, que daba la conversión de escala por
cerrada con un residuo de 1e-4. Ese residuo cubre el redondeo de las
tablas de escala, no la aproximación de convertir valores suavizados.

## Contraste con la evaluación publicada

La reevaluación de 1994 no es una medición independiente: es una
evaluación crítica de los mismos datos primarios, más los del Bureau of
Mines. Sirve de contraste, no de base.

- Csat y Cp convertidos aquí quedan entre un 0,010 % y un 0,059 % por
  debajo de sus valores de referencia en 298,15, 330, 350 y 370 K. Su
  incertidumbre declarada hasta 370 K es 0,1 %.
- Su Cp es a la presión de saturación, no a 100 kPa. La diferencia entre
  ambas definiciones es el término 2: hasta 0,024 J/(mol·K).
- Su Cp − Csat es la resta de dos columnas ajustadas y redondeadas por
  separado; frente al término 1 de aquí difiere entre −0,026 y
  +0,027 J/(mol·K). Ese contraste no discrimina por debajo de 0,03.
- El Bureau of Mines, con otro calorímetro, queda hasta un 0,09 % por
  encima del NBS en las filas citadas.
- Su correlación de densidad (ec. 6), con los coeficientes tal como están
  impresos, da 0,456 g/cm³ a 298,15 K, no 0,68. No se usa.

Usar directamente su tabla de Cp sería científicamente preferible para el
Csat de partida, por su conversión exacta de escala. No se hace: es una
obra con derechos reservados y su tabla no puede incorporarse al
repositorio. Queda como opción si el usuario dispone de licencia.

## Gas: supuestos revisados

- **Calorimetría original no obtenida.** La masa molar y la escala con que
  se midió y ajustó la ecuación 22 siguen sin verificarse en origen.
- **Indicio, no verificación.** El mismo laboratorio usaba 100,198 g/mol,
  1 cal = 4,184 J y la escala de 1948 en su calorimetría del líquido de
  1947-1954 (citado en la reevaluación de 1994, p. 59). Si la del vapor
  usó esa masa molar, difiere de 100,20 en 2e-5. Sigue siendo un supuesto.
- **Contraste nuevo del tramo supuesto.** Bulletin 666 da, como valores
  correlacionados de gas ideal:

| K | Bulletin 666 | RP2526 | Diferencia |
| --- | --- | --- | --- |
| 298,15 | 165,18 | 164,97 | +0,13 % |
| 300 | 165,98 | 165,79 | +0,11 % |
| 400 | 210,66 | 210,57 | +0,05 % |

  En J/(mol·K), con 1 cal = 4,184 J. El incremento de entalpía de 300 a
  400 K es 18 828 J/mol en Bulletin 666 y 18 826,4 en RP2526.
- **Qué prueba y qué no.** La ecuación 23, que la fuente adoptó como
  supuesto, queda un 0,13 % por debajo de una correlación oficial;
  extrapolar la ecuación 22 quedaría un 0,86 % por debajo. Bulletin 666 usa
  los datos de calor específico del vapor existentes, así que por encima
  de 357 K no es independiente; por debajo lo es solo en parte. Son
  valores correlacionados, **no mediciones**.
- **Sin cambios:** el rango sigue en 298,16 a 470 K, no cubre temperaturas
  de llama, gas ideal no equivale a vapor real, y el extremo de 466 a
  470 K sigue siendo una extrapolación de la fuente.

Bulletin 666 llega a 1500 K, pero con valores correlacionados. Ampliar con
él el rango del gas sería otro gate y otra clase de evidencia; aquí no se
decide.

## Compatibilidad conjunta y requisitos del adaptador

Los dos perfiles candidatos tienen exactamente los mismos campos y
comparten referencia, unidad, escala, interpolación, ruta de presión y
masa molar. Ninguno pasa por el contrato del otro.

| | Líquido | Gas |
| --- | --- | --- |
| Esquema propuesto | `g3_real_liquid_isobaric_cp_v1` | `g3_real_ideal_gas_cp_v1` |
| `caloric_model` | `declared_liquid` | `ideal_gas` |
| Soporte ITS-90 | 279,9855 - 371,1029 K | 298,1355 - 469,9916 K |
| Nodos | 14, de las filas impresas más el punto de ebullición | 19, de las filas impresas |
| Magnitud de origen | Csat convertido a Cp a 100 kPa | Cp° de gas ideal |
| Error de interpolación | ≤ 0,025 J/(mol·K) | ≤ 0,007 J/(mol·K) |
| Conversión de escala | Aproximada; 0,07 % frente a la evaluación publicada | Aproximada; sin referencia exacta |

Niveles de evidencia del líquido, que el adaptador debe conservar:

- 280 a 360 K: tabla de la fuente, error probable declarado ±0,1 %.
- 360 a 370 K: la misma tabla; la fuente dice que el error crece por
  encima de 360 K y no da valor en 370 K. Se registra como ausente, no
  como 0,1 %.
- 370 a 371,139 K: interpolación hacia la fila de 380 K, que ya no
  pertenece a la parte ajustada de la tabla.

La entalpía de vaporización del ledger (NIST TN 2126-upd1, 298,15 K) parte
del líquido a 1 bar, la misma presión que el perfil del líquido. No se
recalcula aquí.

Requisitos para la fase de implementación, si se autoriza:

1. Extraer el bucle de integración del helper a una función compartida sin
   cambiar su aritmética, y añadir validadores de los dos esquemas reales.
2. Fijar procedencia por hash y rechazar remuestreo, extrapolación, fase
   cruzada, unidades, masa molar o referencia distintas, igual que los
   controles offline.
3. Conservar niveles de evidencia y errores declarados como campos del
   perfil, incluidas las incertidumbres ausentes.
4. Mantener la mención al NIST que exige la licencia de los datos de
   densidad, y no incorporar la tabla de la reevaluación de 1994.
5. Decidir cómo se etiqueta una cadena con propiedad real y presupuesto
   sintético: ledger y propietario sensible declaran hoy ámbito
   `synthetic_*`.
6. Toca `sim/`: cadena R2-1 completa por monitor y mutantes ejecutados en
   Godot.

Qué **no** puede implementarse con esta evidencia: líquido por debajo de
280 K o por encima de su punto de ebullición a 100 kPa, gas por encima de
470 K, corrección de gas real, B neto, y cualquier otro combustible.

## B neto y alcance del simulador

Sin cambios. B neto sigue en NO-GO y gate aparte: no se deduce de la
pérdida de masa, y el flujo hacia un sensor refrigerado no es el calor
neto absorbido por el líquido. Un Cp real del líquido no aporta ninguno de
los seis elementos que faltan, enumerados en el informe del 05-10.

El heptano es un combustible de referencia para una parte del modelo. Nada
de esto se traslada a sofás, madera, alfombras, CO o HCN.

## Auditor, pruebas y sus límites

- `python -m scripts.simulation.audit_g3_heptane_liquid_profile` reproduce
  el resultado guardado. Solo lee. Reutiliza el auditor del 05-10 para
  escala, presión de vapor, gas e integral canónica, y lee el archivo de
  densidad directamente, sin transcripción manual.
- `tests/test_g3_heptane_liquid_profile.py`: 93 pruebas. Los valores
  esperados se fijaron antes de escribir el auditor, con un cálculo
  independiente de distinta formulación (polinomio global de cuarto grado
  por mínimos cuadrados) y con las filas impresas. Dos tolerancias se
  ampliaron antes de la primera ejecución del auditor, por derivación: la
  del integral canónico frente a Simpson, al 1e-4 declarado del factor de
  escala, y la diferencia con la evaluación publicada, de 0,06 a 0,07 %
  por el redondeo a 0,01 % de sus desviaciones impresas.
- Controles: conversión mol/kg y J/kJ, masa molar nominal o de la
  evaluación, Csat sin convertir, fase gas, ruta de saturación, referencia
  a 1 atm, etiquetas nativas o desplazadas 0,01 K, extrapolación, nodos
  remuestreados, discretización gruesa, NaN e infinito, incertidumbre
  ausente rellenada, procedencia y límites alterados, signo de la entalpía,
  otro compuesto u otra propiedad en el archivo de densidad, y datos fuera
  del rango de presión o temperatura medido.
- `python -m scripts.simulation.run_g3_heptane_real_profile_controls
  --campaign liquid --basetemp <dir nuevo externo>`: 34 mutantes del
  auditor offline en Python, con la prueba del resultado guardado
  desactivada. 34/34 muertos. La campaña del gas, repetida tras extraer
  tres comprobaciones compartidas, sigue en 28/28.

Límites:

- Son controles offline. **No son mutantes ejecutados del motor** y no
  prueban código GDScript.
- El cálculo independiente y el auditor parten del mismo archivo de
  densidad: difieren en el método, no en los datos. La independencia de
  datos la dan RP1271, RP1841 y la columna de entalpía de RP2526.
- Las comparaciones con valores impresos comprueban transcripción y
  aritmética, no la validez experimental de las fuentes.

## Biblioteca

- Datos de densidad archivados con su
  [procedencia](../literature/data/NIST_THERMOML_HEPTANE_2008/PROVENANCE.json),
  sin modificar, y con la mención al NIST.
- Bulletin 666 archivado; manifiesto 47 → 48 entradas.
- La reevaluación de 1994 no se archiva: enlace, DOI y SHA-256 en el
  [registro de revisión](G3_D1_HEPTANE_LIQUID_INPUTS_2026-10-06.json), con
  veinte valores citados de sus tablas 2 y 4, menos de una décima parte.
  Es una decisión de derechos tomada con prudencia, no un permiso
  verificado: si el usuario prefiere no citar ni esos valores, basta
  retirarlos del registro y del contraste.

## Verificación de cierre

Sobre los archivos finales, sin Godot:

- Auditores del líquido, del gas y del 04-10: salida 0. Los dos primeros
  reproducen sus resultados guardados.
- Focal offline: **380 passed**, salida 0, 19,63 s, con basetemp externo
  nuevo. Incluye las 93 pruebas nuevas, las 107 del gas y las de fases,
  sensible, evidencia térmica, emisión, fuentes de CO y guardrails.
- Mutantes offline: líquido 34/34, muertos por 24 pruebas distintas; gas
  28/28, por 22. Ningún superviviente ni inválido; los auditores no se
  modifican.
- `validation_guardrails.py`: ALL GUARDRAILS PASS, R2-1 incluido.
- `sim/` sin cambios: los cinco módulos aislados conservan sus hashes. Por
  eso no se regenera la referencia ni se repiten producto, referencia o la
  suite global; la cadena 3727 / 168 / 346 corresponde al checkpoint
  `64a6803e`, no a estas pruebas.
- Estilo GDScript PASS (no hay GDScript nuevo). Enlaces de los cinco
  documentos propios PASS. El comprobador global sigue fallando por dos
  enlaces de `addons/sky_3d/ThirdParty.md`, ajenos y anteriores.
- Manifiesto válido con 48 entradas; `git diff --check` limpio.

## Siguiente paso recomendado

Con los dos perfiles en GO parcial, la decisión que queda es del usuario:
autorizar o no la fase de implementación del esquema real en el helper,
con los seis requisitos de arriba.

Mejoras opcionales, ninguna bloqueante: conseguir con acceso legítimo los
dos artículos de JACS para verificar en origen los supuestos del gas y los
volúmenes que usó la fuente; cotejar los datos de densidad con su artículo;
y abrir, si interesa, un gate distinto sobre el gas por encima de 470 K.

No iniciados ni aprobados: adaptador en `sim/`, integración, B predictivo y
CO/FED, que siguen OFF y NO-GO.
