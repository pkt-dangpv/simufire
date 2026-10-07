# G3/D1 - Ensayo de evaporación sin llama en cono como benchmark

Fecha: 2026-10-07. Checkpoint de entrada: `94a4122b` (main = rama shareable,
locales y remotas, árboles limpios). Revisión científica **offline**. Sin
cambios en `sim/`, referencias, escenarios ni interruptores, y sin Godot.

Ensayo evaluado: Beji, Helson, Rogaume y Luche, *Fire Safety Journal* 121
(2021) 103317. 250 ml de n-heptano en una bandeja de acero aislada, bajo un
cono a 25 y 50 kW/m² nominales, dentro de un calorímetro de cono de
atmósfera controlada con poco oxígeno: el líquido se evapora sin arder.

## Decisión

Cinco decisiones separadas. Un GO en una no aprueba las demás.

| Pregunta | Decisión | Qué queda permitido |
| --- | --- | --- |
| 1. Elegibilidad de los observables | **GO parcial** | Masa acumulada por unidad de área y dos temperaturas puntuales en el centro, como **digitalización de figuras**. Sin masa inicial, sin nivel medido, sin temperatura de superficie |
| 2. Irradiación incidente | **GO parcial** | La consigna nominal, comprobada en un punto antes de cada ensayo, y un rango geométrico **calculado** sobre la superficie. Durante el ensayo no se midió |
| 3. Calor neto absorbido | **NO-GO: no identificado** | Ninguno como entrada. De diez términos de frontera, nueve sin medida ni cota |
| 4. Validación del calentamiento | **GO parcial, muy limitado** | La temperatura puntual **inferior** dentro del soporte, en los cinco ensayos con temperatura, como contraste de transferencia entre niveles de irradiación. **NO-GO** para energía almacenada, temperatura media y temperatura de superficie |
| 5. Validación de la emisión | **NO-GO** | Ninguno como predicción independiente. La masa acumulada queda como observable reservado |

**B neto sigue NO-GO, no identificado.** Este ensayo conoce la potencia
nominal del calentador; no conoce el calor que absorbe el líquido.

## Fuente y derechos

- **Versión revisada:** versión aceptada, 37 páginas, del
  [repositorio de la Universidad de Gante](https://biblio.ugent.be/publication/8702056);
  SHA-256 `1c82a821…945ff`. Volumen, número de artículo y año comprobados
  en Crossref y en el registro de Gante.
- **Revisión:** texto completo, y por imagen el montaje (figuras 1 y 2),
  las tablas 1 a 6 y las figuras 4, 6 y 7.
- **Derechos:** el registro de Gante la marca «sin licencia, con
  copyright». El acceso es abierto; la redistribución no está autorizada.
  **No se incorpora al repositorio**: solo el enlace.
- **Versión publicada:** restringida en Gante y cerrada en la editorial;
  no obtenida ni comprada.
- **Material suplementario y datos públicos: no localizados.** No es lo
  mismo que «no existen». Buscado en: el propio texto (sin declaración de
  datos), Crossref (sin relación a conjunto de datos), los registros de
  Gante y HAL (solo el artículo), DataCite, Zenodo, OpenAlex (siete
  trabajos que lo citan, ninguno publica datos) y los tres repositorios de
  MaCFP. La búsqueda queda cerrada aquí.

## Qué entrada está realmente medida

| Objeto | Qué es | Estado |
| --- | --- | --- |
| Irradiación nominal | Consigna del cono, comprobada con una galga Schmidt-Boelter en el centro de la posición inicial de la superficie, antes de cada ensayo | **Nominal.** La lectura de esa comprobación y su incertidumbre no se publican |
| Irradiación incidente | Lo que llega a la superficie mientras baja | **Calculado**, por geometría. No hay galga durante el ensayo |
| Calor neto absorbido | Lo que cruza la frontera del líquido | **No identificado** |
| Demanda | Lo que la masa evaporada y el líquido calentado tuvieron que recibir | **Diagnóstico.** Se construye con los observables que habría que predecir |

Lo único medido durante el ensayo es la masa, seis termopares, el oxígeno
y el caudal de nitrógeno. De eso se publica, y solo como curvas, la tasa
de masa promediada cada 15 s y dos de los seis termopares.

## Matriz de ensayos

Doce ensayos; ocho de heptano. Los campos comunes del montaje y cada
ensayo están clasificados uno a uno en el
[registro](G3_D1_CONE_EVAPORATION_BENCHMARK_INPUTS_2026-10-07.json).

| Ensayo | Irradiación nominal | Extracción | Aislado | Gas en el conducto, °C | Curvas | Nota |
| --- | --- | --- | --- | --- | --- | --- |
| H25#1 | 25 | Sí | Sí | 126 ± 8 | Masa y temperatura | Evaporación residual al final; los autores la atribuyen a derrame dentro del recinto |
| H25#2 | 25 | Sí | Sí | 126 ± 6 | Masa y temperatura | |
| H25#3 | 25 | Sí | Sí | No disponible | Solo masa | Sin curva de temperatura |
| H25#4 | 25 | **No** | Sí | 125 ± 7 | Masa y temperatura | Variante |
| H25#5 | 25 | Sí | **No** | 116 ± 14 | Masa y temperatura | Variante; placa de vermiculita bajo la bandeja |
| H50#1 | 50 | Sí | Sí | 164 ± 13 | Masa y temperatura | Evaporación residual, atribuida a derrame |
| H50#2 | 50 | Sí | Sí | 168 ± 11 | Masa y temperatura | Residual visible en la figura; los autores no lo nombran |
| H50#3 | 50 | Sí | Sí | 174 ± 7 | Masa y temperatura | |
| M25#1, M25#2, M50#1, M50#2 | 25 y 50 | Sí | Sí | 119 a 170 | Masa y temperatura | Metanol: sin perfil aprobado; fuera del análisis |

| Magnitud | Valor | Clase |
| --- | --- | --- |
| Irradiación | 25 y 50 kW/m² | Nominal |
| Comprobación previa de la irradiación | Lectura e incertidumbre | **Desconocido** |
| Irradiación durante el ensayo | | **Desconocido** |
| Cono | Radios 80 y 40 mm, altura 68 mm; 25 mm entre el borde de la bandeja y el cono | Nominal |
| Bandeja | Lado interior 98 ± 2 mm, fondo 40 ± 2 mm, pared 2,1 ± 0,2 mm, acero inoxidable | Medido |
| Aislamiento | Silicato cálcico, unos 18 mm a los lados y 57 mm abajo | Nominal |
| Temperatura de la bandeja | | **Desconocido**: sin termopar |
| Carga | 250 ml; labio de unos 15 mm | Nominal |
| Masa inicial de cada ensayo | | **Desconocido** |
| Nivel inicial | 25 mm | Calculado |
| Temperatura inicial | 15 a 19 °C, rango para todos los ensayos | Medido |
| Termopares en el líquido | Centro a 6 y 19 mm del fondo; otros dos a 1 cm de la pared | Nominal |
| Termopares publicados | Solo los del centro; los de pared «bastante similares», sin mostrar | |
| Temperatura de superficie | | **Desconocido**: no medida |
| Balanza | Resolución 0,01 g; registro cada 1 s | Nominal |
| Área usada para la tasa por unidad de área | | **Desconocido** |
| Atmósfera | N₂ a 145 ± 5 l/min; O₂ medio no superior al 5 %, típicamente bajo el 2 % | Medido; serie sin publicar |
| Presión, caudal de extracción | | **Desconocido** |
| Concentración de vapor de combustible | | **Desconocido**: no medida |
| Temperatura del gas sobre el líquido | | **Desconocido**: medida, sin publicar |
| Propiedades del líquido de la tabla 1 | 684 kg/m³ a 25 °C, 2,24 kJ/(kg K), 315 kJ/kg, 98,5 °C | Supuesto: tomadas de otro artículo |
| Reflectividad | 0,08 | Supuesto: tomada de otro artículo |
| Factor de vista medio | 0,95 al inicio y 0,70 al final | Calculado por los autores, sin el borde |

Inconsistencias del propio artículo, que el registro conserva:

- El termopar superior está a 19 mm en el montaje y en el pie de la
  figura 6, y a 20 mm en el texto de resultados.
- El lado de la bandeja es 98 ± 2 mm en el texto y 95 en el dibujo. El
  tiempo de evaporación de 168 s que citan solo sale con 0,10 m × 0,10 m.
- La temperatura inicial declarada es de 15 a 19 °C, pero en el primer
  marcador el termopar superior lee de 20 a 22 °C a 25 kW/m² y de 24 a
  30 °C a 50 kW/m². **El líquido no es uniforme cuando empieza el
  registro.**
- El «± » de la temperatura del conducto no se define.
- No se afirma que las curvas de masa y de temperatura con la misma
  etiqueta sean de la misma corrida; el protocolo inicia a la vez todas
  las adquisiciones. Aquí se emparejan solo por etiqueta.

El oxígeno bajo es el medio para que no arda. **No valida combustión
subventilada residencial.**

## Datos: solo figuras

No hay series digitales. Las curvas están en tres mapas de bits
incrustados en el PDF, con un marcador cada 15 s.

| | Figura 4, masa | Figuras 6 y 7, temperatura |
| --- | --- | --- |
| Paneles | a (25 kW/m²) y b (50 kW/m²) | a y b de cada una |
| Ejes | 0 a 800 s y 0 a 60 g/(m² s); 0 a 400 s y 0 a 120 g/(m² s) | 0 a 150 °C; de 150 a 500 s de ancho |
| Resolución vertical | 0,22 y 0,44 g/(m² s) por píxel | 0,55 °C por píxel |
| Separación de marcadores | 9 y 18 píxeles | 14 a 48 píxeles |

**Método.** Cada marcador se localiza casando su forma (círculo, cruz o
asterisco, tal como los dibuja la leyenda) en la columna de su instante.
Los píxeles pintados con el color de otra curva se tratan como
desconocidos. Un marcador tapado por completo se entrega como el rango que
puede ocupar, no como un punto; uno que no aparece queda sin valor.

**Error de lectura.** 1,5 píxeles, 3 si el marcador está parcialmente
tapado: 0,3 a 0,7 g/(m² s) en la tasa y 0,8 °C en la temperatura. Es
resolución del mapa de bits. **No es incertidumbre instrumental**, que el
artículo no da. La frecuencia de adquisición de 1 s no se recupera.

**Comprobaciones.** Los picos digitalizados, 48,4 y 86,6 g/(m² s),
coinciden con los 48 y 86 de la tabla 3. La línea horizontal del punto de
ebullición se lee a 98,7 °C frente a 98,5. Las lecturas se revisaron
superpuestas a la figura.

**La masa acumulada se conserva.** La figura da la tasa, que ya es una
derivada promediada. Una media de 15 s por 15 s es exactamente la masa
perdida en el bloque, así que se suma, sin suavizado propio y sin volver a
derivar. El artículo no dice si cada media se dibuja al principio, en
medio o al final de su bloque: las tres lecturas se conservan como rango.

**Qué se publica.** La serie digitalizada **no** entra en el repositorio:
deriva de figuras con copyright y publicarla es una decisión del
proyecto. Se publican el
[script](../../scripts/simulation/digitise_g3_cone_benchmark_figures.py),
la huella de la serie y unos pocos
[agregados escalares](G3_D1_CONE_EVAPORATION_BENCHMARK_AGGREGATES_2026-10-07.json).
Quien tenga el PDF del repositorio de Gante reproduce la serie y comprueba
la huella.

## Corpus

Criterios fijados antes de digitalizar ningún valor:

1. Solo n-heptano: es el combustible con perfiles aprobados.
2. Solo la configuración de referencia: extracción en marcha y soporte
   aislado.
3. **Todas** las repeticiones que cumplen 1 y 2, a los dos niveles. No se
   elige por ajuste.
4. Un ensayo entra en el corpus de calentamiento solo si se muestran sus
   dos temperaturas del centro.

Resultado: H25#1, H25#2, H50#1, H50#2 y H50#3 con masa y temperatura;
H25#3 solo con masa. Fuera: H25#4 y H25#5 por ser variantes, y el metanol.

## De la consigna a la superficie

Factor geométrico medio sobre la superficie, con el punto de calibración
igual a 1. Emisor difuso y uniforme, como en la expresión de los autores.

| Nivel del líquido | Centro | Media de área | Media de área con la sombra del borde |
| --- | --- | --- | --- |
| 25 mm, inicial nominal | 1,000 | 0,911 | 0,838 |
| 19 mm, termopar superior | 0,945 | 0,848 | 0,758 |
| 6 mm, termopar inferior | 0,821 | 0,722 | 0,614 |
| 0 mm, bandeja vacía | 0,765 | 0,670 | 0,557 |

- **Los 0,95 y 0,70 de los autores no salen como media de área.** Salen
  0,911 y 0,670. El cociente sí se reproduce: 0,735 frente a 0,737. Su
  media sobrestima la irradiación media en torno a un 4 %.
- **La sombra del borde**, que ellos mencionan y no calculan, quita otro
  8 % al inicio y otro 17 % al final. Calculada aquí por cuadratura
  directa del hemisferio, que sin borde coincide con la expresión cerrada
  dentro de 0,001.
- El lado de la bandeja, entre 95 y 100 mm, mueve estas cifras menos de
  0,01.

Único rango que no depende de la masa: **0,56 a 0,91** de la consigna,
entre bandeja vacía con borde e inicio sin borde. El valor en cada
instante depende del nivel, y el nivel se reconstruye con la masa.

Esto es geometría, no medida. No incluye la reflexión de la pared de
acero hacia el líquido, la atenuación por el vapor ni la no uniformidad
real de la espiral.

## Balance

Volumen de control: el líquido de la bandeja, abierto por su superficie, a
presión constante. Calor que entra al líquido, positivo.

```text
calor neto = variación de la energía sensible del líquido que queda
           + masa emitida × [entalpía del vapor a la temperatura de superficie
                             − entalpía del líquido en su estado inicial]
```

La bandeja, el aislamiento y el gas quedan fuera. La masa evaporada se
cuenta una vez: el término por kilogramo ya incluye calentarla desde el
estado inicial.

### Frontera: qué se sabe de cada término

| Término | Identificación | Evidencia |
| --- | --- | --- |
| Consigna en el punto de calibración | Nominal | Comprobación descrita; lectura e incertidumbre sin publicar |
| Distribución sobre la superficie y con el nivel | Rango calculado | Tabla anterior; depende de un nivel no medido |
| Sombra del borde y reflexión de la pared | Rango calculado | Sombra calculada aquí; reflexión desconocida |
| Atenuación por el vapor | **Desconocido** | Propuesta por los autores; concentración sin medir |
| Reflexión en la superficie | Supuesto | 0,08, de otro artículo |
| Emisión de la superficie | **Acotado** | Como mucho cuerpo negro al punto de ebullición, 1,1 kW/m² |
| Convección con el gas | **Desconocido** | Termopares de gas sin publicar; puesta a cero en las simulaciones |
| Intercambio con la bandeja | **Desconocido** | Sin termopar en la bandeja |
| Transmisión hasta el fondo | **Desconocido** | Coeficiente de absorción explorado en dos órdenes de magnitud |
| Pérdida por el aislamiento | Supuesto | Despreciada por la similitud de un ensayo sin aislar |

Uno acotado, nueve que bloquean. La regla es la del gate anterior: B se
identifica solo si todos los términos están medidos o acotados.

**La bandeja no es despreciable.** Con las dimensiones del texto y las
propiedades del acero de la tabla 4, la bandeja tiene 17,7 kJ/(m² K) por
unidad de área de piscina, frente a 39,9 de la carga de líquido: **un
44 %**. Al principio es un sumidero; cuando el nivel baja, la pared
irradiada por el cono queda por encima del líquido y puede ser fuente.
Sin temperatura de la bandeja, ese intercambio no tiene ni signo ni
tamaño.

### Dependencias

- El **nivel** se reconstruye con la masa. Todo lo que use el nivel
  —irradiación local, inmersión de los termopares— depende de la masa y
  **no puede validar una predicción de la masa**.
- La **demanda** usa la masa y las temperaturas. No valida ninguna de las
  dos.
- La masa inicial de cada ensayo no se publica. El total evaporado es lo
  único que la sustituye, y también sale de la masa.

No se completa ninguna pérdida desconocida con un ajuste que haga cerrar
la masa.

### Demanda del ensayo completo

Al final la bandeja está vacía, así que no hay energía almacenada que
suponer. Es el balance con menos hipótesis del ensayo.

| Ensayo | Evaporado, kg/m² | Sobre la carga nominal | Fin de la caída, s | Demanda media, kW/m² | Demanda sobre consigna |
| --- | --- | --- | --- | --- | --- |
| H25#1 | 15,7 a 16,8 | 0,83 a 0,98 | 495 | 11,8 a 17,7 | 0,47 a 0,71 |
| H25#2 | 13,7 a 14,2 | 0,72 a 0,83 | 465 | 11,1 a 15,9 | 0,44 a 0,64 |
| H25#3 | 14,0 a 14,8 | 0,74 a 0,86 | 495 | 10,0 a 15,5 | 0,40 a 0,62 |
| H50#1 | 15,8 a 17,1 | 0,83 a 1,00 | 270 | 21,4 a 33,1 | 0,43 a 0,66 |
| H50#2 | 15,3 a 16,5 | 0,81 a 0,96 | 270 | 20,3 a 31,8 | 0,41 a 0,64 |
| H50#3 | 14,2 a 14,8 | 0,75 a 0,86 | 255 | 19,7 a 30,2 | 0,39 a 0,60 |

- La entalpía por kilogramo va de 354 a 521 kJ/kg. El intervalo es ancho
  porque **la temperatura de superficie no se midió**: va de 25 °C, lo
  más bajo que cubre el perfil de gas aprobado, a los 98,5 °C del
  artículo. La masa emitida con la superficie más fría no queda cubierta.
- El líquido recibió, en el ensayo completo, **entre el 39 y el 71 % de
  la consigna por el tiempo**.
- Frente al rango geométrico de 0,56 a 0,91, eso es entre 0,43 y 1,27
  veces lo incidente calculado. **Ni excluye ni demuestra que se absorba
  todo lo que llega.**

Esto es una reconstrucción con la masa. Sirve para decir cuánto calor
tuvo que entrar; no es una entrada independiente y no acota los términos
de frontera uno a uno.

## Calentamiento, evaporación y fase final

### Ventanas

Fijadas por soporte y por inmersión, antes de evaluar ningún candidato:

- **Soporte.** El perfil líquido aprobado acaba en 371,10 K, 97,95 °C. El
  punto de ebullición del artículo, 98,5 °C, **queda fuera**. Un termopar
  deja de tener soporte en el último marcador en que su lectura, con su
  rango, sigue dentro. No se recorta ninguna lectura al límite ni se
  extrapola Cp: la meseta se informa tal como se lee, por encima.
- **Inmersión.** Un termopar es temperatura de líquido solo mientras la
  masa todavía sitúa la superficie por encima de él más medio diámetro de
  la perla. Depende de la masa y se declara.

| Ensayo | Superior: fin de soporte | Superior: inmersión confirmada | Inferior: fin de soporte | Inferior: inmersión confirmada |
| --- | --- | --- | --- | --- |
| H25#1 | 135 s | 90 s | 345 s | 360 s |
| H25#2 | 135 s | **nunca** | 360 s | 315 s |
| H50#1 | 60 s | 45 s | 180 s | 180 s |
| H50#2 | 60 s | 30 s | 180 s | 180 s |
| H50#3 | 75 s | **nunca** | 180 s | 165 s |

- **Primera ventana**, los dos termopares con soporte e inmersión: solo
  existe en tres ensayos y dura 30 a 90 s.
- **Segunda ventana**, solo el inferior: existe en los cinco, hasta 165 a
  345 s.
- **Fase final**: ninguna temperatura de líquido con soporte. Solo masa.

**El GO de calentamiento queda limitado al termopar inferior dentro de su
ventana.**

### Por qué el termopar superior casi no sirve

Las repeticiones no evaporan la misma masa: de 13,9 a 16,1 kg/m², un 15 %
de diferencia, sin contar los residuos finales. El artículo atribuye las
diferencias de duración a derrames antes del ensayo y **no da la masa
inicial**. En nivel equivalente son de 20 a 25 mm.

En H25#2 y H50#3, el nivel que da su propia masa empieza a 20 a 21 mm: a
la altura del termopar superior. Sin embargo sus curvas de temperatura
casi coinciden con las de los otros ensayos. O el termopar no estaba donde
la masa dice, o la masa que falta no se perdió antes de empezar. Con lo
publicado no se puede decidir.

### Dos termopares no son una temperatura media

Con dos puntos, la energía almacenada solo admite una horquilla, y bajo un
supuesto que los termopares no prueban: que la temperatura no decrece con
la altura. Criterio fijado de antemano: el contraste de energía discrimina
solo si la horquilla de la demanda es más estrecha que el rango geométrico
contra el que se compararía, 0,48 de anchura relativa.

| Ensayo y ventana | Hasta | Demanda sobre consigna | Anchura relativa |
| --- | --- | --- | --- |
| H25#1, primera | 90 s | 0,23 a 1,09 | 1,29 |
| H50#1, primera | 45 s | 0,16 a 1,12 | 1,50 |
| H50#2, primera | 30 s | 0,01 a 1,22 | 1,98 |
| H25#1, segunda | 345 s | 0,43 a 0,79 | 0,59 |
| H25#2, segunda | 315 s | 0,40 a 0,72 | 0,56 |
| H50#1, segunda | 180 s | 0,39 a 0,76 | 0,65 |
| H50#2, segunda | 180 s | 0,37 a 0,76 | 0,69 |
| H50#3, segunda | 165 s | 0,36 a 0,73 | 0,68 |

**Ninguna de las ocho discrimina.** En la primera ventana la demanda es
compatible con absorber una quinta parte de la consigna y con absorberla
entera. El extremo inferior puede salir casi nulo porque la horquilla deja
que todo el líquido empiece tan caliente como la lectura inicial más alta.

### La meseta no marca el nivel

- El termopar inferior llega a leer **108 a 109 °C** antes de volver a
  unos 99 °C. Diez grados por encima del punto de ebullición, con líquido
  todavía en la bandeja según la masa. En ese tramo la lectura no es la
  temperatura del líquido.
- En H25#1 el termopar inferior deja la meseta 30 s **antes** de que
  termine la evaporación; en H25#2, 15 s **después**. Quedan 6 mm de
  líquido bajo ese termopar, que tardarían más de un minuto en irse.
- Los autores leen la meseta como inmersión en una capa de vaporización y
  de ahí deducen su espesor. Es una interpretación; el nivel no se midió.
- Las líneas verticales de las figuras 6 y 7 (135 y 395 s; 80 y 215 s)
  son su estimación del paso de la superficie, calculada con la masa, una
  por panel y sin decir de qué ensayo.

## La discrepancia del 39 al 46 %

**Qué compara.** La tabla 3 compara el **pico** de la tasa de masa
promediada cada 15 s con la consigna dividida por el calor latente. Es
decir, supone que al final todo el calor nominal evapora, sin calentar
nada, sin pérdidas y con la superficie donde se calibró.

Se reproduce: 48 frente a 79,4 y 86 frente a 158,7 g/(m² s) dan −39,5 y
−45,8 %.

**Qué pasa al cambiar solo la geometría**, con la bandeja casi vacía:

| Irradiación usada | 25 kW/m² | 50 kW/m² |
| --- | --- | --- |
| Consigna | −39,5 % | −45,8 % |
| Factor de los autores, 0,70 | −13,6 % | −22,6 % |
| Media de área, 0,670 | −9,8 % | −19,2 % |
| Media de área con borde, 0,557 | **+8,6 %** | −2,8 % |
| Lo anterior con reflexión supuesta de 0,08 | +18,0 % | +5,7 % |

El residuo **cambia de signo** según un tratamiento geométrico y óptico
que nadie midió.

| Causa | Estado |
| --- | --- |
| Menor factor de vista al bajar la superficie | Calculado por los autores: 5 a 30 % |
| Reflexión, emisión y conducción a la pared | Dicen que no son sustanciales, por cálculos preliminares que no muestran |
| Acumulación de vapor que limita la evaporación por gradiente de concentración | **Propuesta** como probable; concentración sin medir |
| Sombra del borde | Mencionada; no calculada por ellos |
| Atenuación de la radiación por el vapor | **Propuesta**; sin medir |
| Rebaja del 20 % de la consigna en las simulaciones | **Ajuste** hecho después para casar la masa; no es una medida |

**No discrimina entre falta de energía y limitación de transferencia.**
Un único dato apunta, sin demostrarlo: el termopar superior se estabiliza
junto al punto de ebullición, lo que es compatible con una superficie
saturada, donde manda el calor y no la difusión. Pero ese termopar no es
la superficie. La explicación sugerida por los autores sigue siendo una
hipótesis, y aquí no se convierte en mecanismo.

## Contrato de benchmark

| | |
| --- | --- |
| Entradas independientes | Consigna nominal, geometría declarada de cono y bandeja, carga nominal de 250 ml, rango inicial declarado, perfiles aprobados |
| **No** son entradas | Calor neto absorbido, irradiación sobre la superficie durante el ensayo, masa inicial de cada ensayo, temperatura de superficie |
| Estado inicial | 15 a 19 °C declarados; no uniforme en el primer marcador; nivel solo nominal |
| Observables de contraste | Masa acumulada por unidad de área en los marcadores; temperatura del centro a 6 mm en su ventana; a 19 mm solo en la primera ventana de tres ensayos |
| Condiciones de contorno desconocidas | Temperatura de la bandeja, gas y vapor sobre el líquido, irradiación durante el ensayo |
| Rango | n-heptano, 250 ml, bandeja cuadrada de 98 mm, 25 y 50 kW/m² nominales, líquido de unos 290 K al final del soporte |
| Incertidumbres conocidas | Rango de lectura de la digitalización, dispersión entre repeticiones, tolerancias dimensionales |
| Incertidumbres ausentes | Galga, termopares, deriva de la balanza, área de la tasa, incertidumbre total de cualquier magnitud. **Quedan `null`, no cero** |
| Parámetros calibrables | Fracción absorbida de la consigna, transporte efectivo en el líquido, profundidad de absorción, nivel inicial de cada ensayo |
| Reparto | Las curvas de un nivel de irradiación pueden calibrar; solo las del otro, sin leer durante la calibración, sirven de contraste. Ninguna curva hace las dos cosas |
| No se puede afirmar | Calor neto del combustible, una ley de emisión, temperatura media o de superficie, validez con llama o con oxígeno, CO o FED |

### Qué modelo aislado podría contrastarse, y qué no

El único contraste que este ensayo admite hoy:

- **Modelo:** una columna de líquido resuelta en profundidad, aislada.
- **Entrada térmica:** la consigna por el rango geométrico, por una
  fracción absorbida **calibrada**. No es B.
- **Observable:** la temperatura a 6 mm en su ventana, en el nivel de
  irradiación que no se usó para calibrar.
- **Parámetros no identificados:** la fracción absorbida, el transporte
  efectivo, la profundidad de absorción y el nivel inicial. Cuatro, contra
  una curva por ensayo.
- **Qué no podría afirmarse:** que el calor neto es correcto, que la
  emisión es correcta, ni que la temperatura media lo es.

Los propios autores hicieron este ejercicio con FDS: multiplicaron la
conductividad por 10 a 20 y rebajaron la consigna un 20 % para casar la
masa, y a 25 kW/m² el termopar inferior siguió calentándose más deprisa
que el medido.

**Este gate no autoriza implementar ese modelo.** No resolvería el bloqueo
de B y añadiría cuatro parámetros calibrados. Si se quiere, es una
decisión aparte.

## Qué falta

**Para B neto, el dato mínimo no existe en este ensayo.** No se midió ni
la irradiación durante la evaporación, ni la temperatura de la bandeja, ni
la de la superficie, ni la concentración de vapor. Las series digitales
originales afinarían los observables; no identificarían el calor neto.

Lo que sí resolvería una petición de datos: la masa inicial de cada
ensayo, la sincronía entre masa y temperatura, la uniformidad lateral y el
lado del gas.

Petición preparada. **No enviada.**

> Para los autores de Fire Saf. J. 121 (2021) 103317, T. Beji (Universidad
> de Gante) y T. Rogaume (Institut Pprime, Universidad de Poitiers).
>
> Solicitamos, para los ocho ensayos de n-heptano (H25#1 a H25#5 y H50#1 a
> H50#3):
>
> 1. La masa registrada cada segundo y la masa inicial de cada ensayo.
> 2. Los seis termopares de cada ensayo como series: los cuatro del
>    líquido y los dos del gas, con su tipo y su incertidumbre.
> 3. La lectura de la galga en la calibración previa a cada ensayo y la
>    incertidumbre de la galga.
> 4. El área usada para la tasa por unidad de área y la forma del promedio
>    de 15 s.
> 5. La serie de oxígeno y cualquier medida de temperatura de la bandeja o
>    de concentración de vapor, si existe.
> 6. La altura real de los termopares, 19 o 20 mm, y su tolerancia.
> 7. Las condiciones de uso y redistribución de esos datos.

## Auditor y pruebas

- [Auditor](../../scripts/simulation/audit_g3_cone_evaporation_benchmark.py),
  con su [registro](G3_D1_CONE_EVAPORATION_BENCHMARK_INPUTS_2026-10-07.json),
  sus [agregados](G3_D1_CONE_EVAPORATION_BENCHMARK_AGGREGATES_2026-10-07.json)
  y su [resultado](G3_D1_CONE_EVAPORATION_BENCHMARK_AUDIT_2026-10-07.json).
  No contiene ningún solver térmico ni ajusta nada a los datos.
- [Digitalizador](../../scripts/simulation/digitise_g3_cone_benchmark_figures.py):
  lee una copia local del PDF, la rechaza si no es la revisada y escribe
  la serie fuera del control de versiones.
- [Pruebas](../../tests/test_g3_cone_evaporation_benchmark.py): 62,
  offline.
- [Variantes de control](../../scripts/simulation/run_g3_cone_benchmark_control_mutations.py):
  20 reglas del auditor reescritas en memoria, sin tocar el repositorio.

Los controles usan oráculos sintéticos o de forma cerrada, que no
dependen de las curvas: fijan lo que el auditor debe rechazar, no lo que
los datos deben mostrar. Las pruebas que fijan hallazgos leídos después en
la auditoría están aparte y se declaran como tales.

| Control | Qué rechaza el auditor |
| --- | --- |
| Potencia nominal como B neto | Presentar una magnitud con otro papel que el de su evidencia |
| Flujo incidente como absorbido | Pasar de incidente a absorbido con términos sin identificar |
| Corridas o ventanas mezcladas | Canales de corridas distintas como síncronos; lecturas fuera de su ventana |
| Dependencia circular | Validar la masa con algo construido con la masa |
| Digitalización como dato bruto | Una serie que no se declara digitalización, o que se ofrece como bruta |
| Temperatura de sensor como media | Dos puntos como temperatura media o de superficie |
| Signos y doble conteo | Oráculos de líquido uniforme, de enfriamiento y de bandeja vacía |
| Unidades, tasas y acumulados | Gramos por kilogramos; una lectura ausente sumada como cero; derivar una tasa sin declarar el método |
| Incertidumbre ausente como cero | Un total con una parte ausente es `null` |
| Extrapolación de propiedades | Evaluar el líquido en el punto de ebullición o el vapor bajo su soporte; recortar al límite |
| Emisión aprobada por el calentamiento | Cada decisión lee solo sus hechos |

## Verificación

| Comprobación | Resultado |
| --- | --- |
| Checkpoint y módulos congelados | `94a4122b`; hashes de `sim/fire/` sin cambio |
| Auditor contra su resultado guardado | Coincide |
| Agregados contra la digitalización local | Coinciden |
| Pruebas focales del ensayo de cono | 62 passed con la copia local; 60 passed y 2 skipped sin ella |
| Con los gates de los que depende | 603 passed |
| Guardarraíles | ALL GUARDRAILS PASS, R2-1 incluido |
| Enlaces de los documentos modificados y `git diff --check` | Correctos |
| Variantes de control | 20 de 20 detectadas; el auditor sin cambios pasa |
| Godot | No lanzado |

Las dos pruebas que se saltan sin la copia local son las que redigitalizan
el PDF y recalculan los agregados. Se saltan con su motivo; no cuentan
como aprobadas.

## Biblioteca y derechos

- **Solo enlazado:** el artículo, por su
  [registro de Gante](https://biblio.ugent.be/publication/8702056). No se
  añade al manifiesto de descargas porque no se incorpora.
- **No publicada:** la serie digitalizada. Publicarla queda a decisión del
  usuario.
- Se conservan sin cambio la
  [revisión de Sandia](G3_D1_NET_THERMAL_BUDGET_REVIEW_2026-10-07.md) y
  sus límites.

## Siguiente acción

Decisiones del usuario, no iniciadas:

1. **Autorizar o no el envío de la petición de datos** a los autores. No
   se ha contactado con nadie.
2. Decidir si la serie digitalizada puede publicarse en el repositorio.
3. Decidir si interesa el modelo de columna descrito arriba, sabiendo que
   no identifica B.

Sigue pendiente, del gate anterior, la petición a Sandia, tampoco enviada.

No se implementa evaporación en `sim/`, no se conecta al incendio activo,
no se envían solicitudes y no se activa CO/FED.
