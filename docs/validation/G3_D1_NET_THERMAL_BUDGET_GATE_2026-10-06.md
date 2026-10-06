# G3/D1 - Gate del presupuesto térmico neto del combustible (B neto)

Fecha: 2026-10-06. Checkpoint de entrada: `314f0be8` (main = rama shareable,
locales y remotas, árboles limpios). Gate científico **offline**: fuentes,
balance y auditor en Python. Sin cambios en `sim/`, referencias, escenarios
ni interruptores, y sin Godot.

Continúa la [composición aislada](G3_D1_REAL_SENSIBLE_COMPOSITION_2026-10-06.md),
donde B es sintético, y revisa el NO-GO de B del
[gate térmico del 04-10](G3_D1_POOL_THERMAL_EVIDENCE_2026-10-04.md) con
fuentes primarias nuevas.

## Decisión

Cinco decisiones separadas. Un GO en una no aprueba la siguiente.

| Pregunta | Decisión | Condiciones y rango |
| --- | --- | --- |
| Elegibilidad del benchmark | **GO parcial** | Sandia SAND2010-6377, piscina abierta de n-heptano de 2 m a nivel constante, media cuasi estacionaria, tres ensayos. |
| Identificabilidad de B neto | **GO parcial como tasa estacionaria acotada; NO-GO como valor puntual** | El flujo medido y la demanda diagnóstica coinciden dentro del 13 % en el peor extremo; cuatro términos quedan sin medir. Solo en las condiciones de ese benchmark. |
| Balance estacionario o transitorio | **Estacionario; NO-GO transitorio** | No hay series temporales tabuladas del líquido de heptano ni del flujo. |
| Predicción térmica | **NO-GO** | El almacenamiento en el líquido no es identificable. |
| Predicción de emisión | **NO-GO** | El flujo no sigue a la masa entre ensayos; no se autoriza ninguna regla B/L. |

Respuesta a las dos preguntas del encargo:

1. **¿Hay un presupuesto térmico independiente y contrastable?** Sí, con
   límites: una tasa media estacionaria, dentro de una banda de un 10 %, en
   un benchmark. No un valor puntual ni una curva en el tiempo.
2. **¿Sirve para predecir calentamiento o emisión?** No todavía. Las
   condiciones que faltan están al final.

Todas las aprobaciones siguen en `false`. CO/FED siguen OFF y NO-GO.

## Qué es B

B es el **calor neto que cruza la frontera del volumen de control del
combustible líquido** desde su entorno. Como tasa:

`Ḃ = Q_rad,abs + Q_conv + Q_cond,pared − Q_rerrad − Q_pérdidas`

- Volumen de control: solo la fase líquida, sistema abierto a presión
  constante. Entra líquido de alimentación; sale vapor a la temperatura de
  la superficie.
- **No es** el HRR, ni el calor químico de oxidación, ni el flujo que lee
  un sensor, ni un calor latente deducido de la masa perdida, ni la
  entalpía que transporta la materia que entra o sale.

Balance de ese volumen, en entalpía:

`Ḃ = ṁ · [L_ref + h_gas(T_sup) − h_líq(T_alim)] + dS_líq/dt`

Correspondencia con el ledger, sin contar nada dos veces:

| Término físico | Dónde se contabiliza |
| --- | --- |
| `ṁ · [L_ref + h_gas(T_sup) − h_líq(T_alim)]` | Coste de liberación. Calentar la alimentación hasta la superficie está **dentro** de este coste; no es «calentamiento». |
| `dS_líq/dt` | Calentamiento prescrito del líquido (cuenta S). |
| Calor de oxidación | Cuenta Q. Nunca vuelve a B. |

**Entalpía, no energía interna.** Es un sistema abierto e isobárico: el
trabajo de flujo va en la entalpía, y por eso se usa Cp. Para el
almacenamiento del líquido la diferencia es despreciable: P·dv por kelvin
es 8·10⁻⁵ veces Cp.

**Qué representa hoy B en el código.** En el ledger y el propietario real
B es una reserva cerrada: se fija una vez en el seed, solo decrece y no
tiene entrada por paso. No es un flujo físico transitorio. Lo que haría
falta para una frontera térmica está en el contrato del final.

## Dos estimaciones que no se mezclan

| | Independiente | Demanda |
| --- | --- | --- |
| De dónde sale | Flujo de calor medido, con las correcciones que las fuentes permiten | Masa medida por la entalpía de los perfiles aprobados |
| ¿Usa la pérdida de masa? | **No** | Sí |
| Qué es | Candidato a entrada | Reconstrucción diagnóstica: lo que B tendría que ser |
| Uso permitido | Contrastar un B futuro | Solo comprobar; nunca alimentar B |

La pérdida de masa es un observable de validación. No construye el B que
luego pretendería predecirla.

## Candidatos

Se compararon tres. Se eligió el más identificable.

| | Sandia, 2 m | NIST, 0,30 m | NIST, alcoholes 0,30 m |
| --- | --- | --- | --- |
| Fuente | Blanchat y Suo-Anttila, SAND2010-6377 (2011) | Hamins y otros, Combust. Sci. Technol. 97 (1994); perfil tabulado en TN 2162r1 | Kim, Lee y Hamins, Fire Saf. J. 107 (2019); TN 2162r1 |
| Combustible | n-heptano «100 %», pureza no indicada | n-heptano | metanol, etanol, acetona |
| Recipiente | Bandeja de 2 m, 19 mm de líquido sobre deflector, con y sin lecho de vidrio | Quemador de acero de 0,30 m, 0,15 m de fondo, agua a 289 K en la base | Igual que el anterior |
| Presión | Unos 24,6 inHg (Albuquerque, ~83 kPa) | No indicada | No indicada |
| Alimentación | Nivel constante, bombeo desde bidón sobre báscula | Gravedad, nivel constante, depósitos sobre células de carga | Gravedad, nivel constante |
| Flujo de calor | 12 galgas de flujo total en anillos de igual área, 26 mm sobre el líquido, mantenidas cerca de la temperatura de ebullición | Galga Gardon fría barrida por el radio, en el plano del borde | Galga Gardon fría, 13 mm sobre el líquido |
| Temperatura del líquido | Peine de 30 termopares; meseta de 84 °C | Supuesta igual a la de ebullición; no medida para heptano | Series tabuladas (apéndice G de TN 2162r1) |
| Pérdidas | No medidas | Agua de refrigeración medida; conducción por la pared estimada | En un único resto sin medir |
| Masa | Misma corrida que el flujo | Otras corridas (quemadores de anillos) | Misma campaña |
| Repetibilidad | 4 ensayos, 3 con masa impresa | Al menos 5 repeticiones de masa; flujo repetido 2 veces | Varias |
| Incertidumbre | Galga 3 % (fabricante); 20 a 40 % citado para incendios; sin cifra combinada | Señal de la galga 10 %; célula de carga 5 % | 9 a 11 % |
| Derechos | «Further dissemination unlimited»: archivado | Portada del NIST sin copyright, página escaneada con aviso editorial: **solo enlazado** | Artículo de revista: solo enlazado |
| Resultado | **Elegido** | Segunda condición, aparte | Descartado |

**Por qué Sandia.** Flujo y masa son medias de la misma ventana del mismo
ensayo. La integral espacial tiene soporte de diseño. Las galgas trabajan
cerca de la temperatura de la superficie, lo que reduce el sesgo de galga
fría. Y la temperatura del líquido está medida.

**Por qué no el NIST de 0,30 m como principal.** Flujo y masa vienen de
corridas distintas, la temperatura de la superficie no está medida para
heptano, y los términos menores solo se publican como cocientes respecto de
una magnitud derivada de la masa. Se usa como segunda condición.

**Por qué se descartan los alcoholes.** Son la única familia archivada con
series del líquido, pero no hay perfiles de propiedades aprobados para
esos combustibles, y su balance del lado del combustible deja todas las
pérdidas en un resto sin medir: la integral de la galga supera lo necesario
para vaporizar la masa entre un 22 y un 40 %.

TN 2162r1 y MaCFP, ya archivados, no cierran el balance por sí solos: el
heptano hereda su flujo de la publicación de 1994, no tiene serie del
líquido y no se mide la carga del agua de refrigeración en los ensayos con
líquidos. **No se multiplica el flujo por un tiempo para crear B.**

No se combinan canales de ensayos distintos como una corrida sincronizada.
El cuarto ensayo de Sandia (SNL030) tiene flujo pero no masa impresa, y
queda fuera del balance.

## Balance del benchmark elegido

Procedencia de cada término:

| Término | Clase | Detalle |
| --- | --- | --- |
| Flujo de calor a las galgas | **Medido** | Media temporal de la ventana válida, misma corrida que la masa. |
| Integral sobre la bandeja | **Calculado** | Seis anillos de igual área; sin extrapolar. Reproduce las medias impresas. |
| Tasa de masa | **Medido** | En el bidón de alimentación; equivale a la pérdida solo como media sobre ciclos de llenado. |
| Temperatura de la superficie | **Medido** | 84 °C, un valor para el combustible; ±3 °C de termopar. |
| Temperatura de alimentación | **Medido antes de la ignición** | 33, 32 y 26 °C. En estacionario no está tabulada para heptano. |
| Entalpía de alimentación y del vapor | **Calculado con modelo** | Perfiles reales aprobados. |
| Reflexión en la superficie | **Medido en laboratorio** | ~0,1 a 1 µm y 20°; ~0,04 a 60°; nula a mayor longitud de onda. Sin total hemisférico: se acota entre 0 y 10 %. |
| Re-radiación de la superficie | **Cota modelada** | La galga trabaja cerca de la temperatura de la superficie: casi toda está ya en la lectura. |
| Absorción en la cúpula de vapor bajo la galga | **Desconocido** | Se midieron espectros, pero no se tabula una transmitancia integrada para esos 26 mm. |
| Pérdidas a la bandeja y al suelo | **Desconocido** | No medidas. |
| Almacenamiento en el líquido | **Desconocido** | Sin serie temporal del líquido de heptano. |
| Diferencia convectiva entre galga y superficie | **Desconocido** | El informe la nombra y no la cuantifica. |
| Calor químico | **Demostrablemente fuera** | La oxidación ocurre fuera del volumen de control. |

Los cuatro términos desconocidos **no se rellenan** para que cierre.

Resultado por ensayo:

| | SNL011 | SNL012 | SNL029 |
| --- | --- | --- | --- |
| Lecho de vidrio | sí | sí | no |
| Ventana válida | 10 a 15,5 min | 8 a 12 min | 15 a 17 min |
| Flujo medio en la bandeja | 29,77 kW/m² | 31,65 kW/m² | 29,61 kW/m² |
| Potencia a las galgas | 93,5 kW | 99,4 kW | 93,0 kW |
| **Independiente** (reflexión 10 a 0 %) | 84,2 a 93,5 kW | 89,5 a 99,4 kW | 83,7 a 93,0 kW |
| Tasa de masa | 193,5 g/s | 201,0 g/s | 181,3 g/s |
| Entalpía por kg | 452,7 kJ/kg | 454,9 kJ/kg | 468,5 kJ/kg |
| **Demanda** (±3 K en cada temperatura) | 85,2 a 90,0 kW | 88,9 a 94,0 kW | 82,7 a 87,2 kW |
| Diferencia relativa | −6,5 a +9,8 % | −4,8 a +11,8 % | −4,0 a +12,5 % |
| Bloque desconocido que resultaría | −5,9 a +8,4 kW | −4,5 a +10,5 kW | −3,5 a +10,3 kW |

Las temperaturas caben en los perfiles aprobados: 299 a 306 K para el
líquido de alimentación y 357 K para la superficie. **No se extrapola ni
se recorta nada.**

### Criterios, fijados con las incertidumbres de las fuentes

Se escribieron antes de ejecutar el auditor, después de una estimación a
mano del orden de magnitud. No se ajustaron al resultado.

| Criterio | Umbral | Resultado |
| --- | --- | --- |
| Estricto | Raíz de la suma de cuadrados de galga (3 %) y masa (1,9 %): 3,6 % | **No se cumple** en ningún ensayo |
| Laxo | 20 %, el extremo inferior del 20 a 40 % que el informe cita para galgas en incendios | **Se cumple** en los tres |
| Valor puntual | Estricto en todos los ensayos y todos los términos medidos o nulos | No |
| Tasa acotada | Laxo en todos los ensayos y todos los términos sin medir nombrados | Sí |

Dos advertencias sobre el criterio estricto. El 1,9 % de la masa está
dado para un ensayo de JP8 promediado seis minutos; las ventanas del
heptano duran de dos a cinco minutos y medio y su incertidumbre no se
indica. Y el informe no da una incertidumbre combinada del flujo a la
superficie. **No hay incertidumbre total, y no se inventa una.**

### Lo que el benchmark no deja afirmar

- **El flujo no sigue a la masa entre ensayos.** Sin el lecho de vidrio la
  masa baja un 6,3 % y el flujo solo un 0,5 %. Entre los dos ensayos con
  lecho, el flujo sube un 6,3 % y la masa un 3,9 %. Con tres medias no se
  sostiene una proporcionalidad.
- **El plano de la galga no puede ser la frontera.** El vapor llega a unos
  200 °C a la altura de la galga. Recalentarlo solo hasta el final del
  soporte del gas (470 K) consume 47 kW, la mitad de lo que leen las
  galgas. Por encima de 470 K el perfil del gas no tiene soporte y el
  auditor rechaza el cálculo. La frontera tiene que estar en la superficie
  del líquido, y lo que absorbe la cúpula de vapor es un término de primer
  orden que no está medido.

### Sensibilidades

| Magnitud | Efecto sobre la demanda o el balance |
| --- | --- |
| Temperatura de alimentación | −0,50 % por kelvin |
| Temperatura de la superficie | +0,42 % por kelvin |
| Almacenamiento en los 41 kg de líquido | 1,5 kW por cada K/min: 1,7 % de la potencia a las galgas |
| Reflexión | Hasta el 10 % de la estimación independiente |
| Bases de propiedades sin reconciliar | 1,6 % (abajo) |

## Segunda condición: NIST 0,30 m

Otro laboratorio, otra escala, galga fría y canales de corridas distintas.
Se mantiene aparte; no se promedia con el benchmark elegido.

| Magnitud | Valor |
| --- | --- |
| Potencia integrada a la galga (del 04-10) | 1,241 kW |
| Menos reflexión (5 a 8 % del 80 % radiativo), re-radiación (0,04) y pérdida al agua (0,03); más conducción por la pared (0,3 kW/m²) | |
| **Independiente** | 1,102 a 1,132 kW |
| Masa | 2,6 g/s |
| Temperatura de superficie, dos valores publicados, ninguno aceptado | 65 °C y el final del soporte del líquido (98 °C) |
| Temperatura de alimentación, no indicada | 289 a 296 K |
| **Demanda**, con el almacenamiento publicado (0,04) | 1,191 a 1,394 kW |
| Diferencia relativa | −20,9 a −4,9 % |
| Criterio estricto (11,2 %) y laxo (20 %) | **No cumple ninguno** en su peor extremo |

Con propiedades reales, la estimación independiente se queda entre un 5 y
un 21 % por debajo de la demanda. El artículo declara buen acuerdo, pero
con valores de propiedades que no indica. Sus términos menores se publican
normalizados por una magnitud derivada de la masa, y así se declara.

Consecuencia: la identificabilidad parcial **no se generaliza** a otra
escala ni a otro montaje.

## Bases de propiedades pendientes

No se reconcilian en silencio; se cuantifica su efecto.

- **Calor latente.** El coste por kg compone el latente declarado a
  298,15 K con las entalpías de los dos perfiles. Al final del soporte del
  líquido eso da 323,3 kJ/kg de vaporización. El valor de manual en el
  punto de ebullición es 316,0 kJ/kg. La diferencia, 7,3 kJ/kg, es el 1,6 %
  de la demanda. Es coherente con no aplicar la desviación de gas real,
  que el perfil del gas declara.
- **Latente de TN 2126 frente al de la fuente del gas:** 0,27 kJ/kg, el
  0,06 % de la demanda. Irrelevante aquí; sigue sin reconciliar.
- **Base de masa nominal frente a 100,20 g/mol:** afecta al O₂ y a los
  productos, no a B. No interviene en este balance.
- **Presión.** El ensayo es a ~83 kPa y el perfil del líquido a 100 kPa.
  La temperatura de la superficie usada es la medida, no un punto de
  ebullición impuesto.

## Auditor y controles

`python -m scripts.simulation.audit_g3_net_thermal_budget` reproduce el
[resultado guardado](G3_D1_NET_THERMAL_BUDGET_AUDIT_2026-10-06.json) a
partir del [registro revisado](G3_D1_NET_THERMAL_BUDGET_INPUTS_2026-10-06.json).
No escribe archivos, no arranca Godot y no toca el motor. Con `--check`
compara con el guardado.

El registro entero va fijado por hash: valores, localizadores,
clasificación de cada término, criterios y aprobaciones. El PDF archivado
va fijado por separado.

`tests/test_g3_net_thermal_budget.py`, 51 pruebas. Son controles Python
offline, no mutaciones del motor. Los valores a mano se obtuvieron de las
tablas impresas antes de ejecutar el auditor.

| Control | Qué detecta |
| --- | --- |
| Unidades | kg/s por g/s, W/m² por kW/m², J/kg por kJ/kg, un porcentaje por una fracción y una energía acumulada tratada como tasa |
| Signos | Pérdida sumada, ganancia restada, alimentación más fría que abarata |
| Doble conteo | Calentamiento de la alimentación o latente sumados dos veces |
| Sensor frente a absorbido | La lectura de la galga nunca se rotula como B; reetiquetar los desconocidos como medidos no da un valor puntual |
| Integración espacial | Un anillo sin galga útil o anillos que no cubren la bandeja |
| Sincronización | Masa sin ventana; ensayo sin masa fuera del balance |
| Mezcla de corridas | Masa o galgas de otro ensayo bajo la misma etiqueta |
| Circularidad | La estimación independiente no admite masa y no cambia al duplicarla |
| Incertidumbre ausente | `null` no se combina ni se sustituye por cero |
| Datos y procedencia | Catorce alteraciones del registro rechazadas; bytes del PDF vinculados |
| Extrapolación | Ocho temperaturas fuera de soporte rechazadas |
| Aprobaciones | Promover cualquiera se rechaza |

## Contrato de la siguiente implementación

Hay GO parcial, así que se concreta el contrato. **No se implementa
aquí.** Sería un sucesor versionado y aislado, no una integración.

**Objetivo acotado.** Reproducción estacionaria aislada del benchmark de
Sandia a través del ledger real: B entra como tasa independiente con su
banda, la emisión se prescribe con la masa medida, y el observable es si
B alcanza para pagarla.

1. **Entrada de frontera por paso.** B deja de ser solo una reserva
   inicial. La petición lleva un calor de frontera no negativo por paso.
   Cuenta B: `B_después = B_antes + frontera − calentamiento − coste de
   liberación`.
2. **Clase y procedencia obligatorias.** Cada entrada declara si es tasa
   independiente medida, modelo o sintética, con su fuente y su ventana.
   Una entrada derivada de la pérdida de masa se rechaza.
3. **Incertidumbre explícita.** Banda inferior y superior. Ausente es
   `null`; nunca cero por defecto.
4. **Volumen de control declarado.** Superficie del líquido. La
   temperatura del vapor emitido es la de la superficie, dentro del
   soporte del gas.
5. **Alimentación.** El ledger es un inventario cerrado. Para un ensayo a
   nivel constante el inventario representa el suministro a su
   temperatura; no se prescribe calentamiento mientras el almacenamiento
   no esté medido.
6. **Q no vuelve a B.** Sin realimentación de la oxidación dentro del
   ledger.
7. **Observable no circular.** `release_budget_deficit_kj` y la liberación
   aceptada frente a la pedida. Con el extremo inferior de la banda, el
   déficit de SNL011 sería de 3,4 kW; con el superior, cero. Ese intervalo
   es el oráculo, fijado aquí antes de implementar.
8. **Prohibido.** Calcular la emisión como B/L, promediar con la segunda
   condición, presentar la banda como incertidumbre total y cualquier
   aprobación de predicción.

## Qué falta para predecir

Términos no identificables, su efecto y qué los resolvería:

| Término | Efecto | Qué lo resolvería | Acción concreta |
| --- | --- | --- | --- |
| Absorción en la cúpula de vapor | Reduce B; primer orden | Transmitancia integrada entre la galga y la superficie | Revisar el artículo de los espectros (Suo-Anttila y otros, citado como 2008 en el informe) |
| Pérdidas a la bandeja y al suelo | Reduce B | Calorimetría del recipiente | Buscar un ensayo con carga de refrigeración medida y masa de la misma corrida |
| Almacenamiento en el líquido | 1,7 % por K/min; decide el transitorio | Serie temporal del peine de termopares | Pedir o localizar los datos brutos de SNL011, 012 y 029 |
| Diferencia convectiva galga-superficie | Signo no determinado | Medida con y sin soplado | Sin fuente identificada |
| Temperatura de alimentación en estacionario | 0,5 % por kelvin | El mismo peine | Misma petición de datos brutos |

Condiciones adicionales para usar B de forma predictiva:

- **Calentamiento:** series sincronizadas de la entrada térmica y del
  estado del líquido. Un benchmark estacionario solo aprueba un balance
  estacionario.
- **Emisión:** una ley de fase y de transferencia en la superficie:
  presión de vapor, condición de equilibrio o de transporte y reparto
  entre almacenamiento y evaporación. Aunque haya calor disponible, sin
  eso no se predice la evaporación.
- **«B/L = masa evaporada» no se autoriza.** Solo vale como identidad
  diagnóstica en estacionario, con almacenamiento nulo demostrado, y el
  propio benchmark muestra un 6 % de masa que el flujo no explica.
- **Transferencia a recintos o muebles:** no se sigue de una piscina
  abierta de 2 m.

## Biblioteca y derechos

- **Archivado:** SAND2010-6377, 84 páginas, 10 652 080 bytes, SHA-256
  `9722f122…c62860bd`, con aviso «Approved for public release; further
  dissemination unlimited»
  ([PDF local](../literature/Sandia/SNL_SAND2010-6377_Hydrocarbon_Characterization_Results_2011.pdf),
  [OSTI](https://www.osti.gov/biblio/1018470)). Las filas de heptano se
  verificaron sobre la imagen de las páginas: la extracción de texto
  desalinea las etiquetas de las últimas filas de las tablas 5 y 6.
- **Solo enlazado:** Hamins y otros (1994),
  [reimpresión servida por el NIST](https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=909794).
  La portada dice que no está sujeta a copyright; la página escaneada
  lleva un aviso de la editorial. Ante la duda no se archiva. Se
  transcriben una quincena de números con su localizador, no tablas
  completas.
- **Solo enlazado:** Kim, Lee y Hamins (2019),
  [manuscrito de autor](https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=928848).
- **Examinado y no usado:** SAND2007-2391, el plan de ensayos previo; no
  contiene resultados.

Discrepancias de la fuente conservadas, no corregidas: la tabla 12 de
Sandia imprime 193,3 g/s como media con lecho cuando sus dos ensayos
promedian 197,25; y su tabla 3 da un calor de gasificación de manual de
541 kJ/kg, que no se usa.

## Verificación

Fase offline. No se lanzó Godot ni la cadena completa: `sim/` no cambia.

- Auditor: reproduce el resultado guardado.
- Pruebas: **51 passed** nuevas; con las de los gates térmicos y de
  propiedades de los que depende, **334 passed**.
- Guardarraíles: ALL GUARDRAILS PASS, R2-1 incluido.
- Enlaces de los documentos modificados, `git diff --check` y manifiesto
  de bibliografía (48 → 49 entradas): correctos.
- Módulos de `sim/fire` con los mismos SHA-256 que en el checkpoint.

La cadena del cierre anterior (fixture 3670, mutantes 94/94 y 228/228,
referencia 346/346, producto 168/168, global 3981) es de la composición;
**no es evidencia del B físico** y no se repite aquí.

## Siguiente gate

Decisión del usuario, no iniciada. Dos caminos, sin orden entre ellos:

- Implementar el contrato anterior como reproducción estacionaria aislada.
- Resolver antes los términos desconocidos con los datos brutos o el
  artículo de los espectros.

No se implementa la frontera térmica, no se conecta al incendio activo y
no se activa CO/FED.
