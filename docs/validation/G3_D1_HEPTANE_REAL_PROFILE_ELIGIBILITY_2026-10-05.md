# G3/D1 - Elegibilidad de propiedades térmicas reales del n-heptano

Fecha: 2026-10-05. Checkpoint de entrada: `64a6803e` (main = rama shareable).
Alcance: revisión de fuentes primarias, contrato de un adaptador posterior
y auditor offline. Sin cambios en `sim/`, escenarios, interruptores ni
informes de referencia. No se ejecuta Godot. El adaptador **no** se
implementa en esta fase.

Revisado el 06-10 por el
[gate del líquido](G3_D1_HEPTANE_LIQUID_ELIGIBILITY_2026-10-06.md): el NO-GO
del líquido pasa a GO parcial por conversión justificada, y la conversión
de escala se reclasifica como aproximada. El resto se mantiene.

## Decisión

| Pregunta | Decisión | Alcance exacto |
| --- | --- | --- |
| Cp de gas ideal | **GO parcial** | Cp° molar de gas ideal entre 298,16 y 470 K de la fuente (298,1355 a 469,9916 K en ITS-90). No cubre temperaturas de llama ni gas real. |
| Propiedad líquida como Cp isobárico | **NO-GO** | La fuente mide Csat sobre la curva de saturación. Falta el dato volumétrico que permite convertirlo. Los datos se conservan en su dominio nativo. |
| Conversión de escala térmica | **GO** | 1948 → 1968 → 1990 con dos fuentes primarias archivadas. Residuo declarado: 0,6 mK en etiquetas y 1e-4 relativo en Cp. |
| Compatibilidad con el contrato sintético actual | **NO-GO por diseño** | El helper rechaza las etiquetas reales. Hace falta un esquema real versionado; no se cambian etiquetas para pasar. |
| Presupuesto neto B | **NO-GO, gate aparte** | Sin evidencia independiente del calor neto absorbido por el líquido. |

Consecuencia práctica: el ledger sensible exige a la vez un perfil de
líquido y otro de vapor. Con el líquido en NO-GO, el GO parcial del gas no
permite todavía una corrida del ledger con propiedades reales en ambas
fases.

## Fuentes y verificación

Todas las páginas, ecuaciones y filas citadas se inspeccionaron sobre la
imagen renderizada de la página, no solo sobre la capa de texto OCR.

| Fuente | Papel | Localizadores usados | SHA-256 |
| --- | --- | --- | --- |
| [Douglas et al., NBS RP2526 (1954)](../literature/NIST/NBS_Heptane_Calorimetric_Properties_1954.pdf) | Calorimetría del heptano | pp. 140-152 (PDF = impresa − 138): escala p. 140-141, masa molar p. 145, ec. 8 p. 147, tabla 5 p. 149, ec. 12, 19 y tabla 6 p. 150, ec. 22-23 p. 151, tabla 10 p. 152 | `40138b0b…434bd3f9` |
| [Douglas, J. Res. NBS 73A (1969)](../literature/NIST/NBS_IPTS68_Conversion_Douglas_1969.pdf) | Escala 1948 → 1968 | p. 453, ec. 52-53 p. 461, ec. 77 p. 464, ec. 80 p. 465, tabla 4 pp. 468-469 (PDF = impresa − 450) | `11e9a97e…0e5a3c67` |
| [NIST TN 1265 (1990)](../literature/NIST/NIST_TN_1265_ITS90_Guidelines_1990.pdf) | Escala 1968 → 1990 | tabla 1, p. 5 (PDF p. 21); misma tabla en el texto de la ITS-90 reproducido, PDF p. 113 | `5c90691e…7e2b5c1b` |
| [Osborne y Ginnings, NBS RP1841 (1947)](../literature/NIST/NBS_Hydrocarbon_Heat_Capacity_Osborne_Ginnings_1947.pdf) | Relación entre Csat y Cp | p. 471 (PDF p. 19); tabla 2, PDF p. 20 | `0dcceb58…40abd288` |
| [Brooks, Howard y Crafton, NBS RP1271 (1940)](../literature/NIST/NBS_Aliphatic_Hydrocarbon_Properties_Brooks_1940.pdf) | Densidad del líquido | tabla 3, p. 44 (PDF p. 12) | `3f85b592…0e0e1082` |

Los hashes completos, tamaños y versiones están en el
[manifiesto](../literature/download_manifest_fire_literature.json)
(43 → 47 entradas) y en el
[registro de revisión](G3_D1_HEPTANE_REAL_PROFILE_INPUTS_2026-10-05.json).
Son originales del servidor de publicaciones del NIST, de las series
*Journal of Research* y *Technical Note*, igual que RP2526 ya archivada.
No se ha verificado la situación de cada autor ni derechos fuera de
EE. UU.

Búsquedas con resultado negativo o descartado:

- Mangum, J. Res. NIST 95 (1990): remite a la tabla del texto de la
  ITS-90 y no la reproduce. No sustituye a TN 1265.
- Willingham et al., NBS RP1670 (1945): presión de vapor. Revisada y no
  archivada: la ecuación 19 ya está impresa en RP2526 y el punto de
  ebullición independiente de Brooks la contrasta.
- Volumen del líquido entre 25 °C y el punto de ebullición: RP2526 lo
  interpola de un artículo de JACS de 1937 y no tabula los valores. Ese
  artículo no está en el servidor del NIST; no se descargó ni se archiva.
- Calorimetría original del gas (JACS, 1947): tampoco archivada. Por eso
  la masa molar y la escala de la ecuación del gas no se verifican en
  origen.
- Compilaciones SRD y ecuaciones de estado con licencia: excluidas por el
  límite de redistribución. No se usan como base ni como contraste.

## Qué es cada dato

| Dato | Clase | Límite |
| --- | --- | --- |
| Csat del líquido, tabla 5 | Valor tabulado a partir de mediciones de RP2526 | Error probable declarado ±0,1 % entre 280 y 360 K, hasta ±0,5 % a 500 K. Es un error probable, no una incertidumbre estándar. Entre 270 y 370 K la tabla lleva ajustes gráficos y prevalece sobre la ec. 8. |
| Ec. 8 (Csat) | Correlación ajustada | Coincide con la tabla en 380 y 390 K (0,002 y 0,001 J/(mol·K)); a 298,16 K da 0,119 más que la tabla. |
| Ec. 22 (Cp° gas) | Correlación ajustada a calorimetría de flujo citada, extrapolada a presión cero | Medida entre 357 y 466 K. Ajuste ±0,05 %, precisión de las medidas ±0,1 %. La fuente no declara exactitud. |
| Ec. 23 (Cp° gas, 288-370 K) | **Supuesto adoptado por la fuente** | Tangente de la ec. 22 en 370 K, elegida para concordar con la presión de vapor. No es una medición de Cp por debajo de 357 K. Sin incertidumbre declarada. |
| Tabla 10, 466-470 K | Extrapolación de 4 K tabulada por la fuente | Fuera del intervalo medido. |
| Tabla 6, (∂Cp/∂P)T | Medición citada | 6,07 a 357,10 K; 4,81 a 373,15 K; 1,13 a 466,10 K, en J/(mol·K·atm). |
| μ = T68 − T48, ec. 80 | Relación de definición entre dos escalas convencionales | Válida de 0 a 630,74 °C. |
| t90 − t68, TN 1265 | Valor tabulado | Resolución 1 mK cada 10 K. |
| Etiquetas ITS-90, factor de escala, Cp másico | **Conversión calculada aquí** | Ver residuos declarados. |
| Csat ≈ Cp(1 atm) «probablemente dentro del 0,2 %» | Estimación declarada por los autores de RP1841 | Solo para 5-45 °C. No es una medición. |
| Densidad a 20 y 25 °C y dD/dt | Medición de RP1271 | Solo ese intervalo de 5 K. |
| Masa molar y escala de la ec. 22 | **Supuesto de este gate** | Iguales a las del resto de RP2526; la fuente no lo dice para la calorimetría citada. |

## Gas: lo que puede incorporarse

Propiedad: capacidad calorífica isobárica molar del **gas ideal** (estado
hipotético). El helper actual ya exige `caloric_model: ideal_gas` para la
fase gas, así que la propiedad coincide con el modelo que declara el
contrato. Para un gas ideal Cp y los incrementos de entalpía no dependen
de la presión: la atmósfera estándar de la fuente solo afecta a la
entropía, y los 100 000 Pa de nuestra referencia son la etiqueta del
estado, no una corrección. La presión dinámica del recinto no interviene.

Tres tramos con evidencia distinta, que el adaptador debe conservar:

| Tramo (K de la fuente) | En ITS-90 (K) | Evidencia |
| --- | --- | --- |
| 298,16 - 370 | 298,1355 - 369,9636 | Supuesto adoptado por la fuente (ec. 23) |
| 370 - 466 | 369,9636 - 465,9903 | Correlación de mediciones citadas (ec. 22) |
| 466 - 470 | 465,9903 - 469,9916 | Extrapolación tabulada por la fuente |

Peso del supuesto, calculado y no ocultado: extrapolar la ec. 22 en lugar
de usar la ec. 23 da −1,199 J/(mol·K) a 298,16 K (−0,73 %) y −28,62 J/mol
en el incremento 298,16 → 370 K (−0,22 %). No es una incertidumbre
declarada por la fuente: es la diferencia entre dos formas de modelo.

Comprobaciones de transcripción y aritmética (no validación experimental):

- Ec. 22 frente a las diez filas impresas de 380 a 470 K: residuo máximo
  0,0045 J/(mol·K) en Cp y 0,36 J/mol en entalpía. Cotas predeclaradas
  0,02 y 2, las del auditor del 04-10.
- 298,16 → 470 K: 34 911,67 J/mol integrando las ecuaciones; 34 912
  impreso.

Límites que no se corrigen:

- **Gas real.** Con la tabla 6 de la misma fuente, el vapor puro a 1 atm
  tiene un Cp un 3,2 % mayor que el ideal a 357 K, un 2,4 % a 373 K y un
  0,5 % a 466 K. No se aplica; queda declarado como límite del modelo.
- **Por encima de 470 K no hay dato.** El perfil no llega a temperaturas
  de llama; solo cubre el calentamiento del vapor hasta 470 K.
- No hay validación frente a un ensayo de incendio.

## Escala de temperatura

La fuente usa la Escala Internacional de 1948 y escribe
°K = °C + 273,16. Son tres pasos distintos:

1. **Convenio del origen del kelvin**, 273,16 → 273,15 (Douglas 1969,
   p. 453). Restar 0,01 K solo arregla esto. No es la conversión de escala.
2. **IPTS-48 → IPTS-68** con μ(T) de la ec. 80. Las 37 filas impresas de
   la tabla 4 entre 273,15 y 480 K coinciden con la ecuación transcrita
   dentro de 0,00005 K, y su derivada dentro de 0,000005.
3. **IPTS-68 → ITS-90** con la tabla de TN 1265, interpolada linealmente.

Resultado: las etiquetas bajan entre 0,0084 K (470 K) y 0,0371 K (360 K).
El 298,16 K de la fuente es 298,1355 K en ITS-90, no 298,15 K. La
referencia del contrato, 298,15 K en ITS-90, cae en 298,1745 K de la
fuente y queda dentro del soporte.

Los incrementos de entalpía entre dos estados físicos no dependen de la
escala. Para conservarlos, Cp se multiplica por s = dT(fuente)/dT90, que
va de 0,99958 a 1,00040. Se calcula por secante de ±5 K; su irregularidad
de unas 5e-5 entre nodos vecinos es la resolución de 1 mK de la tabla
1968 → 1990, dentro del residuo declarado de 1e-4.

Supuesto declarado: la ec. 22 procede de otra calorimetría y la fuente la
expresa «en función de la temperatura absoluta» sin decir la escala. Se
asume la misma. El efecto está acotado en cualquier caso: 0,05 K de error
de etiqueta cambian Cp en 0,022 J/(mol·K), un 0,011 %.

## Masa molar, unidades y entalpía

- **Masa molar: 100,20 g/mol**, la que la fuente declara para pasar de
  masa a moles (p. 145) y la misma de NIST TN 2126-upd1. No es la nominal
  del motor (C=12, H=1: 100,0), que desviaría Cp un 0,2 %.
- **Unidades:** julio absoluto = julio. kJ/(kg·K) = J/(mol·K) dividido
  por la masa molar en g/mol. A 370 K: 197,28 / 100,20 = 1,968862.
- **Cero de entalpía**, distinto de la escala: la fuente tabula H° − E0
  desde el cristal a 0 K; el contrato usa h(T) − h(298,15 K). Solo se
  usan incrementos, así que el cero se desplaza restando. Entre el primer
  nodo y la referencia hay 0,0145 K: −0,02395 kJ/kg.
- **Signo:** h(T) − h(298,15 K) es negativo por debajo de la referencia y
  positivo por encima; la diferencia entre dos temperaturas es
  antisimétrica y aditiva.
- La fuente da 36 547 J/mol de vaporización a 298,16 K y saturación, más
  76 J/mol hasta gas ideal. El ledger sigue usando 36,65 kJ/mol de
  TN 2126-upd1. Son compatibles dentro de los ±0,20 kJ/mol declarados
  allí; no se reconcilian.

## Líquido: por qué no es Cp isobárico

La fuente (ec. 2 y 5) y su referencia principal definen la magnitud
medida como **Csat**, el calor por kelvin siguiendo la curva de saturación.
Hay tres magnitudes que no deben confundirse:

- Csat, lo que se tabula.
- (dH/dT) sobre saturación = Csat + v·dP/dT, lo que integra la columna de
  entalpía de la tabla 5.
- Cp a presión fija = Csat + αT·v·dP/dT en saturación, más un término de
  presión hasta 100 kPa que depende de la segunda derivada del volumen.

Prueba numérica con la propia fuente, de 298,16 a 370 K: integrar el Csat
impreso da 17 200,77 J/mol y la entalpía impresa sube 17 214. La
diferencia, 13,23 J/mol, la explica el término v·dP de la ec. 12
(13,34 J/mol); el cierre queda en 0,11 con una cota predeclarada de 4,3.
Tratar Csat como derivada de la entalpía falla la tabla de la fuente.

Lo que sí se sabe y dónde se acaba:

- v·dP/dT vale 0,042 J/(mol·K) a 298,16 K y 0,447 a 370 K (0,02 % y
  0,17 % de Csat). Las columnas de RP1841 lo dan de forma independiente
  entre 20 y 25 °C: 0,040 frente a 0,038 de la ec. 12.
- Con la densidad de RP1271, α = 1,2457e-3 K⁻¹ y αT = 0,368 a 22,5 °C:
  Cp − Csat en saturación es 0,016 J/(mol·K) a 298 K, un 0,007 %.
- El término de presión de la entalpía entre saturación y 100 kPa a
  298,15 K está acotado por v·ΔP = 13,85 J/mol.
- Contraste independiente de Csat: RP1841 da 223,82 J/(mol·K) a 22,5 °C
  sin convertir julios internacionales a absolutos; la tabla 5
  interpolada, 223,81. El factor entre ambos julios, del orden de 1,0002,
  no se verificó en una fuente archivada y no cambia la conclusión.
- La ec. 19 da 0,99992 atm en el punto de ebullición medido en RP1271.

**Dato que falta:** el volumen molar del líquido y sus derivadas primera y
segunda respecto a la temperatura entre 273 y 371 K, de una fuente
primaria verificable. La evidencia volumétrica archivada cubre solo
20-25 °C. La estimación «dentro del 0,2 %» de RP1841 vale para 5-45 °C y
es una declaración de los autores, no una medición; no llega al punto de
ebullición.

Por magnitud, el sesgo de usar Csat como Cp sería pequeño, comparable al
error probable de la fuente. La decisión es NO-GO porque no puede
justificarse como conversión con la evidencia archivada, no porque el
efecto sea grande.

Qué lo desbloquearía:

1. Una fuente primaria de densidad del líquido de 0 a 100 °C. Si su
   original no es redistribuible, bastaría acceso legítimo para
   verificarla y registrar localizador, hash y valores, sin archivar el
   PDF, como ya se hace con los originales FSRI.
2. O una decisión explícita del usuario de aceptar Csat como sustituto con
   sesgo declarado. Es una decisión de política, no una evidencia, y este
   gate no la toma.

Entretanto el líquido se conserva nativo: Csat y H sobre saturación, sin
conversión de escala aplicada ni perfil isobárico.

## Contrato del adaptador posterior (solo gas)

Identificador propuesto: `g3_heptane_ideal_gas_cp_adapter_v1`, que emite
el esquema `g3_real_ideal_gas_cp_v1`. Es diseño; nada de esto existe en
`sim/`.

| Punto del contrato | Valor |
| --- | --- |
| Sustancia | n-heptano, C7H16, CAS 142-82-5 |
| Propiedad y modelo | Cp° isobárico de gas ideal |
| Fuente y versión | RP2526, J. Res. NBS 53(3), 1954; ec. 22-23 p. 151, tabla 10 p. 152 |
| Unidades | J/(mol·K) absolutos → kJ/(kg·K) |
| Masa molar y base | 100,20 g/mol, declarada por la fuente |
| Escala térmica | Internacional de 1948 con 273,16 → ITS-90 |
| Ruta de presión y referencia | Gas ideal, independiente de la presión; 298,15 K y 100 000 Pa |
| Rango válido | 298,1355 a 469,9916 K (ITS-90), sin extrapolación |
| Entalpía y signo | h(T) − h(298,15 K), con signo; solo incrementos |
| Nodos | Tomados de las 19 temperaturas impresas de la tabla 10; no se remuestrea a otras |
| Valores en los nodos | Ec. 23 hasta 370 K y ec. 22 por encima; salto de 0,002236 J/(mol·K) en la unión sin suavizar |
| Interpolación | Lineal por tramos, la del cálculo canónico |
| Error de interpolación | ≤ 0,007 J/(mol·K): 0,005814 por la curvatura de la ec. 22 con nodos cada 10 K, más la mitad del salto de unión |
| Residuo de escala | 0,6 mK en etiquetas; 1e-4 relativo en Cp |
| Incertidumbre de la fuente | Ajuste ±0,05 %, precisión ±0,1 %; exactitud no declarada; sin dato en el tramo supuesto |
| Datos ausentes | Cp por encima de 470 K; corrección de gas real; masa molar y escala de la calorimetría original |

Reutilización del cálculo canónico sin física nueva.
`SensibleEnthalpyModel.evaluate` integra `samples`
(`temperature_k`, `cp_kj_kg_k`) por tramos lineales desde 298,15 K. El
perfil real entrega esa misma lista, con la misma unidad, referencia,
interpolación y modelo calórico. Solo cambia la capa de etiquetas:

| Campo | Sintético actual | Real propuesto |
| --- | --- | --- |
| `schema` | `g3_synthetic_isobaric_cp_v1` | `g3_real_ideal_gas_cp_v1` |
| `temperature_scale` | `synthetic_kelvin` | `ITS-90_kelvin` |
| `calibration_status` | `synthetic_not_material_calibration` | `primary_source_property_not_fire_validation` |
| `provenance` | empieza por `synthetic:` | hashes de fuente, de fuentes de escala y de revisión |
| Campos nuevos | — | `molar_mass_g_mol`, `native_support_k`, `evidence_tiers`, `declared_errors`, `witnesses` |

La fase de implementación tendría que extraer el bucle de integración del
helper a una función compartida, sin cambiar su aritmética, y añadir un
validador del esquema real que compruebe procedencia y límites. Toca
`sim/`, así que exige la cadena R2-1 completa por monitor y mutantes
ejecutados en Godot. Queda por decidir entonces cómo se etiqueta una
cadena con propiedad real y presupuesto sintético: el ledger y el
propietario sensible declaran hoy ámbito `synthetic_*`.

El perfil candidato completo, con sus 19 nodos, está en el
[resultado guardado](G3_D1_HEPTANE_REAL_PROFILE_AUDIT_2026-10-05.json).
Extremos y unión:

| K fuente | K ITS-90 | s | Cp, kJ/(kg·K) |
| --- | --- | --- | --- |
| 298,16 | 298,1355 | 1,000397 | 1,647025 |
| 370 | 369,9636 | 0,999874 | 1,968614 |
| 470 | 469,9916 | 0,999656 | 2,393769 |

Con el cálculo canónico sobre esos nodos, el incremento entre los estados
extremos es 34 911,26 J/mol frente a 34 911,67 de las ecuaciones y 34 912
impreso. Por tramo, el residuo máximo es 0,08 J/mol.

## Presupuesto B: límite que se mantiene

B neto sigue siendo un gate separado y en NO-GO. NIST TN 2162r1 y la
compilación MaCFP dan el flujo hacia un sensor refrigerado, no el calor
neto absorbido por el líquido
([evidencia térmica del 04-10](G3_D1_POOL_THERMAL_EVIDENCE_2026-10-04.md)).
No se multiplica ese flujo por una duración y no se deriva B de la pérdida
de masa: sería circular. Tampoco se implementa aquí un modelo térmico.

Evidencia independiente que falta:

1. Calor neto absorbido por el líquido, no flujo hacia un sensor frío.
2. Pérdidas en la superficie: rerradiación, reflexión y transmisión.
3. Historia de temperatura del líquido y perfil en profundidad del mismo
   ensayo.
4. Calor a las paredes del quemador y la bandeja refrigerada, y entalpía
   del combustible de alimentación.
5. Incertidumbre y repetibilidad publicadas del perfil de flujo.
6. Canales de flujo, masa y temperatura sincronizados en una misma
   corrida.

Un Cp real no aporta ninguno de estos seis puntos.

## Auditor, pruebas y sus límites

- `python -m scripts.simulation.audit_g3_heptane_real_profile` reproduce
  el resultado guardado. Solo lee; no escribe archivos ni invoca Godot.
  Reutiliza el auditor del 04-10 para la ec. 23, la ec. 22 y las filas
  hasta 370 K, sin duplicar su transcripción.
- `tests/test_g3_heptane_real_profile.py`: 107 pruebas. Los valores
  esperados se fijaron antes de escribir el auditor, a partir de las filas
  impresas y de un cálculo independiente sobre las tablas de escala
  impresas (interpolación de la tabla 4, no la ec. 80). Dos correcciones
  posteriores, hechas con el auditor ya escrito y antes de ejecutar las
  pruebas, por derivación analítica y no por ajuste al resultado: la cota
  de interpolación pasó de 0,006 a 0,007 al incluir el salto de unión
  (0,005814 + 0,002236/2 = 0,006932), y tres tolerancias de entalpía se
  ampliaron al presupuesto de error declarado.
- Controles negativos sobre el perfil candidato: confusión J/kJ y mol/kg,
  masa molar nominal o de otra tabla, valores de Csat como Cp, fase
  líquida, etiquetas nativas o solo desplazadas 0,01 K, referencia
  incompatible, extrapolación, nodos remuestreados, procedencia o límites
  alterados, NaN, infinito, booleanos y texto, pérdida del signo de la
  entalpía y discretización gruesa. Sobre el registro: semántica
  reetiquetada, filas alteradas, identidad y bytes de las fuentes.
- `python -m scripts.simulation.run_g3_heptane_real_profile_controls
  --basetemp <dir nuevo externo>`: 28 mutantes **del auditor offline en
  Python**, con la prueba del resultado guardado desactivada. 28/28
  muertos, cada uno por la prueba prevista; ninguno inválido.

Límites de esta verificación:

- Son controles offline. **No son mutantes ejecutados del motor** y no
  prueban ningún código GDScript.
- `canonical_enthalpy` es una reescritura en Python de la fórmula del
  helper. No es ese código y no se ha ejercitado en Godot.
- Comparar ecuaciones impresas con tablas impresas comprueba transcripción
  y aritmética, no la validez experimental de las correlaciones.
- El veredicto de compatibilidad está ligado al hash del helper actual;
  si `SensibleEnthalpyModel.gd` cambia, el auditor pide revisarlo.

## Verificación de cierre

Sobre los archivos finales, sin Godot:

- Auditor: salida 0 y resultado idéntico al guardado.
- Focal offline: **287 passed**, salida 0, 32,65 s, con basetemp externo
  nuevo. Incluye las 107 pruebas nuevas, las de los gates de fases,
  sensible, evidencia térmica, emisión y fuentes de CO, y las de
  guardrails.
- Mutantes offline del auditor: 28/28 muertos por 22 pruebas distintas,
  0 supervivientes, 0 inválidos; el archivo del auditor no se modifica.
- `validation_guardrails.py`: ALL GUARDRAILS PASS, R2-1 incluido.
- `sim/` sin cambios: los cinco módulos aislados conservan sus hashes y el
  helper Cp sigue en `0340a726…1672627`. Por eso no se regenera la
  referencia ni se repiten producto, referencia o la suite global; la
  cadena 3727 / 168 / 346 corresponde al checkpoint `64a6803e`, no a
  estas pruebas.
- Estilo GDScript PASS (no hay GDScript nuevo). Enlaces de los cuatro
  documentos propios PASS. El comprobador global falla por dos enlaces de
  `addons/sky_3d/ThirdParty.md`, ajenos y anteriores a esta fase.
- Manifiesto válido con 47 entradas; `git diff --check` limpio.

## Siguiente paso recomendado

Decidir el líquido antes de implementar nada: aportar una fuente primaria
de densidad de 0 a 100 °C, o decidir expresamente si se acepta Csat como
sustituto con sesgo declarado. Con el líquido resuelto, autorizar la fase
de implementación del esquema real en el helper, con cadena R2-1 y
mutantes en Godot.

No iniciados ni aprobados: adaptador en `sim/`, integración, B predictivo
y CO/FED, que siguen OFF y NO-GO.
