# G3/D1 - Revisión del gate de B neto

Fecha: 2026-10-07. Checkpoint de entrada: `f8a9505f` (main = rama shareable,
locales y remotas, árboles limpios). Revisión científica **offline** del
[gate del 06-10](G3_D1_NET_THERMAL_BUDGET_GATE_2026-10-06.md). Sin cambios
en `sim/`, referencias, escenarios ni interruptores, y sin Godot.

## Decisión

**El GO parcial a B neto del 06-10 se retira.** La banda que lo sostenía es
la lectura de las galgas multiplicada por un rango de reflexión. No acota
ninguno de los demás términos que actúan entre el plano de las galgas y el
líquido, y coincidir con una demanda construida a partir de la masa no los
acota.

| Pregunta | Decisión | Uso permitido |
| --- | --- | --- |
| Sandia como contraste | **GO parcial** | Flujo en el plano de las galgas y tasa de masa como observables documentados |
| Calor en el plano de la galga | **GO parcial** | Magnitud medida, sin incertidumbre combinada; contrasta un flujo simulado en ese plano y a esa temperatura de galga |
| B neto | **NO-GO: no identificado** | Ninguno. Ni valor puntual ni intervalo |
| Balance estacionario | **NO-GO: inconcluso** | El residuo no identifica sus componentes |
| Balance transitorio | **NO-GO** | |
| Predicción térmica | **NO-GO** | |
| Predicción de emisión | **NO-GO** | |

Sandia sigue siendo un benchmark útil, pero de otra cosa: de lo que leen
las galgas, no de lo que absorbe el líquido.

## Qué cubría realmente la banda

Cuatro objetos que el gate anterior no separó lo bastante:

| Objeto | Qué es | Estado |
| --- | --- | --- |
| 1. Lectura en el plano de las galgas | Flujo total integrado que leen las galgas, en su plano y a su temperatura | **Medido** |
| 2. Banda condicional | La lectura por uno menos un rango de reflexión | Calculado; vale solo si todos los demás términos de frontera son cero |
| 3. B neto | Calor neto que cruza la frontera del líquido | **No identificado** |
| 4. Demanda | Masa por entalpía de los perfiles aprobados | Diagnóstico; se construye con la masa |

Para SNL011, la banda de 84,2 a 93,5 kW era el objeto 2 presentado como
intervalo del objeto 3.

Reconstrucción del argumento anterior:

| | Qué había |
| --- | --- |
| Medido | Lectura de 11 galgas, tasa de masa, temperatura de la superficie, temperatura del líquido antes de la ignición |
| Calculado | Integral por anillos, entalpías con los perfiles aprobados |
| Supuesto | Alimentación a la temperatura previa a la ignición; inventario de líquido de 19 mm |
| Acotado | Solo la reflexión, y con un rango que no es cota |
| Desconocido | Cuatro términos, agrupados en un bloque y sin cota |

El error de clasificación fue llamar «tasa acotada» a un resultado en el
que el criterio laxo del 20 % hacía de cota. Un criterio de contraste no
convierte términos desconocidos en cotas físicas.

## Evidencia nueva

**El propio laboratorio analizó estos ensayos y no cierra el balance del
heptano.** Luketa, *Assessment of Simulation Predictions of Hydrocarbon
Pool Fire Tests*, SAND2010-2511 (2010), con discusión con el
experimentalista. Difusión ilimitada; archivado.

Lo que aporta, término a término:

| Término | Qué dice el laboratorio | Localizador |
| --- | --- | --- |
| Colocación de la galga | En ensayos de 1 ft, una galga a 1,27 cm sobre la superficie leyó un 20 % más que a ras. No lo traslada a 2 m: «solo más ensayos a 2 m podrían determinarlo» | p.21 |
| Lectura de la galga | Explora ±30 % «para tener en cuenta todos estos factores» y lo declara cuestión abierta | p.21 |
| Cúpula de vapor | Absorción espectral significativa por hollín frío, CO₂, H₂O y vapor de combustible, que reduce lo que llega a la superficie | p.40 |
| Reflexión | Medida en reposo: 0,02 a 0,1. La ebullición puede aumentarla; el lecho de vidrio induce ebullición vigorosa | p.20, p.30 |
| Transmisión por el líquido | El heptano es semitransparente; explora 0,10 a 0,30 | p.30, p.31 |
| Fondo de la bandeja | Sin aislar. Estima 0,2 kW/m² con un coeficiente supuesto; considera probable 1 a 2 kW/m²; supone 2 | p.27 |
| Emisión de la superficie | 1,1 kW/m² con emisividad unidad a 371 K, como cota superior | p.27 |
| Conducción por el borde | La supone despreciable | p.11 |
| Profundidad del combustible | Unos 45 a 55 mm | p.15 |
| Termopar del fondo | Sube unos 10 °C con vidrio y unos 20 °C sin él | p.31, figura 16 p.37 |

**Su balance para el heptano** (tabla 10, comprobada sobre la imagen de la
página): con 30,0 kW/m² ± 30 %, transmitancia y reflexión en sus rangos y
pérdidas, calcula 0,046 y 0,035 kg/m²s frente a 0,061 medidos: **−25 % y
−43 %**. Es el único combustible que queda fuera del 25 %. Concluye que
hacen falta más ensayos para saber si las lecturas de las galgas son bajas
«por condensación, evaporación o colocación».

El gate anterior obtenía un cierre del 13 % porque no restaba ninguno de
esos términos.

### Resultados negativos

| Búsqueda | Resultado |
| --- | --- |
| Artículo de los espectros (Suo-Anttila y otros, Proc. Combust. Inst. 32, 2009) | Localizado; acceso cerrado. **No obtenido.** No se compra acceso |
| Datos brutos de SNL011, 012 y 029 | No están en OSTI ni en MaCFP. **No encontrarlos no demuestra que no existan:** el informe dice que todos los canales se archivaron |
| Ensayos de 1 ft sobre colocación de la galga | Citados por el laboratorio sin referencia. No localizados |

No se contactó a ningún autor. La petición que haría falta está al final.

## Correcciones al gate del 06-10

| Punto | Decía | Es | Efecto |
| --- | --- | --- | --- |
| Inventario de líquido | 19 mm sobre el deflector, 41 kg | Profundidad de 45 a 55 mm, 97 a 118 kg | La escala del almacenamiento estaba subestimada entre 2,4 y 2,9 veces |
| Recalentamiento del vapor | 47 kW, «término de primer orden» | **Retirado como evidencia** | Tomaba la lectura de un termopar en vapor irradiado como temperatura del vapor, y una ruta de energía como la única |
| Rango de reflexión | 0 a 10 % | 2 a 10 %, medido en reposo | El extremo superior no es cota si hay ebullición |
| Altura de la galga | 26 mm | 26 mm en el texto del informe; 12,7 mm en su figura 4 y en la evaluación | Sin reconciliar: altura aceptada `null` |
| Criterio estricto | 3,6 % | **Retirado** | El 1,9 % de la masa es de un ensayo de JP8 de seis minutos; el 3 % es del fabricante |
| Criterio laxo | Sostenía la «tasa acotada» | Solo umbral de contraste | No acota ningún término |

Sobre el recalentamiento: el vapor a unos 200 °C sale de un termopar
envainado bajo unos 30 kW/m² de radiación y sin corrección. Y aunque el
vapor estuviera a esa temperatura, su entalpía podría venir de absorción
de radiación, de mezcla turbulenta desde arriba o de las piezas calientes.
Una temperatura no atribuye por sí sola esa energía a una ruta. No se
afirma ninguna magnitud para la absorción bajo la galga.

## Balance

Volumen de control: la fase líquida en la bandeja, sistema abierto a
presión constante. Signo positivo hacia el líquido.

`B = (lo que cruza la frontera) = ṁ·[L_ref + h_gas(T_sup) − h_líq(T_alim)] + dS_líq/dt`

Tres grupos, que el gate anterior mezclaba en un solo bloque:

### Términos de frontera: actúan sobre B

| Término | Signo | Clase | Rango o cota | Dependencias y límites |
| --- | --- | --- | --- | --- |
| Paso del plano de la galga a la superficie | Indeterminado | **Desconocido** | `null` | Hollín frío, gases y vapor; colocación. A 1 ft la galga lee de más; para el heptano el laboratorio sospecha que lee de menos |
| Convección galga-superficie | Indeterminado | **Desconocido** | `null` | Se espera menos del 10 % del total a 2 m, por la literatura; no medido |
| Reflexión | Reduce | Rango del laboratorio | 2 a 10 % de la lectura | En reposo. No cubre la ebullición |
| Emisión de la superficie | Reduce | **Acotado** | 0 a 1,074 kW/m² | Cuerpo negro a 371 K. Parte puede estar ya en la lectura: la galga trabaja cerca de esa temperatura |
| Fondo de la bandeja y suelo | Reduce | Supuesto del laboratorio | 0,2 a 2 kW/m² | Coeficiente y diferencia de temperatura supuestos. No es una cota medida |
| Conducción por el borde | Aumenta | Supuesto del laboratorio | `null` | Dada por despreciable; no medida |

Cinco de los seis bloquean la identificación. Solo la emisión está
acotada.

### Redistribución interna: no cambia B por sí sola

**Transmisión por el líquido** (10 a 30 %). Lo que atraviesa el líquido lo
absorben el vidrio o la bandeja y vuelve al líquido, salvo lo que se
pierde por el fondo y lo que almacenan esos sólidos. Restarlo entero, como
hace el modelo del laboratorio, es un extremo. No se resta aquí: ya está
en el término del fondo. Así no se cuenta dos veces.

### Términos de la demanda: no son pérdidas de frontera

| Término | Clase | Valor | Límites |
| --- | --- | --- | --- |
| Almacenamiento en el líquido | Estimado sobre una figura | 0,7 a 2,2 kW | Un termopar a 7 mm del fondo, leído en una curva: 0,2 a 0,5 K/min en la ventana. No incluye vidrio ni acero. No es cota |
| Temperatura de alimentación | Supuesta igual a la previa a la ignición | 26 a 33 °C | Medida solo antes de encender |
| Temperatura de la superficie | Medida | 84 °C | Un valor para el combustible |
| Tasa de masa | Medida | 181 a 201 g/s | Incertidumbre `null` para el heptano |

El almacenamiento **suma a la demanda**; no se resta de lo recibido.

### Resultado por ensayo

| | SNL011 | SNL012 | SNL029 |
| --- | --- | --- | --- |
| 1. Lectura en el plano de las galgas | 93,5 kW | 99,4 kW | 93,0 kW |
| 2. Banda condicional (reflexión 10 a 2 %) | 84,2 a 91,6 kW | 89,5 a 97,4 kW | 83,7 a 91,2 kW |
| 3. **B neto** | **no identificado** | **no identificado** | **no identificado** |
| 4. Demanda | 85,2 a 90,0 kW | 88,9 a 94,0 kW | 82,7 a 87,2 kW |
| Demanda más almacenamiento estimado | 85,9 a 92,3 kW | 89,7 a 96,2 kW | 83,4 a 89,4 kW |

Dos escenarios de supuestos, **que no son intervalos identificados**:

| Escenario | SNL011 | Qué supone |
| --- | --- | --- |
| La galga lee lo que llega a la superficie | 74,5 a 91,0 kW | Los dos términos desconocidos valen cero |
| Con la exploración del laboratorio (±30 %) | 49,3 a 118,5 kW | Su rango de estudio, que él mismo llama cuestión abierta |

El segundo abarca del −47 al +27 % de la lectura. Esa es la anchura que
el laboratorio considera compatible con lo que sabe, y no sirve para
validar una entrada térmica.

**El residuo no identifica sus componentes.** La banda condicional menos
la demanda queda entre −5,9 y +6,5 kW en SNL011, con el cero dentro. Eso
dice que el bloque faltante podría ser pequeño. No dice cuánto vale cada
término, ni que se compensen por una razón física. Y usar ese residuo para
fijar lo recibido sería ajustar el calor con la masa que luego debería
validarlo.

## Incertidumbre: qué es cada cifra

| Clase | Qué hay |
| --- | --- |
| Experimental | Galga 3 % (fabricante); termopares del líquido ±3 °C |
| Variación entre ensayos | Tres ensayos: 29,6 a 31,7 kW/m² y 181 a 201 g/s |
| Error de modelo | Entalpía de gas ideal sin desviación de gas real: 1,6 % de la demanda |
| Intervalo de supuestos | Reflexión 2 a 10 %; fondo 0,2 a 2 kW/m²; exploración del ±30 %; ritmo de almacenamiento leído en figura |
| Sensibilidad | −0,50 %/K en la alimentación; +0,42 %/K en la superficie |
| Criterio de aceptación | Umbral de contraste del 20 % |

- **No se combina nada en un total.** Los intervalos de supuestos no
  tienen distribución, y los términos de la galga no son independientes
  entre sí.
- **La incertidumbre total de B es `null`.** La de la masa del heptano y
  la combinada del flujo, también.
- El 20 a 40 % citado para galgas en incendios y el ±30 % explorado **no
  son incertidumbre de B**.
- Una sensibilidad pequeña no prueba que el valor supuesto sea correcto.

## Alternativas examinadas

Tres, como máximo. Ninguna identifica hoy B neto.

| Alternativa | Qué es | Valoración |
| --- | --- | --- |
| Beji, Helson, Rogaume y Luche, Fire Saf. J. (2021) | **Evaporación controlada sin llama, transitoria.** n-heptano al 99 %, 250 ml en bandeja de acero aislada de 98 mm, cono de atmósfera controlada con O₂ por debajo del 2 al 5 %, 25 y 50 kW/m² nominales. Masa cada segundo y cuatro termopares en el líquido; ocho ensayos de heptano | **La mejor localizada para la pregunta del calentamiento:** la entrada es impuesta y el estado del líquido queda registrado. Todavía no identifica el calor neto: el flujo medio queda entre un 5 y un 30 % por debajo del nominal al bajar el nivel, y la tasa pico queda entre un 39 y un 46 % por debajo de flujo entre latente. Los autores sospechan acumulación de vapor. Datos en figuras |
| NIST 0,30 m (Hamins y otros, 1994) | Incendio de piscina, estacionario | Examinada el 06-10: pérdida al agua y reflexión medidas, superficie sin medir, no cierra con propiedades reales |
| Ensayos de 1 ft de Sandia | Colocación de la galga y flujo en profundidad | Citados sin referencia; no localizados |

El ensayo de cono **no es validación de un incendio**. Sirve porque separa
el calentamiento del líquido de la llama.

## Qué falta y qué lo resolvería

| Dato que falta | Qué deja indeterminado | Qué lo resolvería |
| --- | --- | --- |
| Flujo a ras de la superficie a 2 m | El paso de la galga a la superficie; B entero | Ensayo con galgas a ras y elevadas a la vez, o los ensayos de 1 ft con su informe |
| Transmitancia integrada bajo la galga | La absorción en la cúpula | El artículo de los espectros con sus datos tabulados por altura |
| Calorimetría del fondo | La pérdida al recipiente | Flujo o temperaturas a ambos lados del fondo |
| Series del peine y del termopar del fondo | El almacenamiento y la alimentación en la ventana | Los canales brutos de 1 Hz |
| Incertidumbre de la masa en las ventanas del heptano | El criterio estricto | Los registros de la báscula |

Petición preparada y **no enviada** (a Sandia National Laboratories, Fire
Science and Technology, autores de SAND2010-6377 y SAND2010-2511):

> Canales de 1 Hz de los ensayos SNL011, SNL012 y SNL029 de la serie C6 de
> 2007: las doce galgas de la bandeja, los treinta termopares del peine,
> el termopar del fondo de la bandeja y la báscula del bidón. Espectros
> tabulados por altura en la cúpula de vapor del ensayo de heptano. Informe
> o datos de los ensayos de 1 ft sobre colocación de la galga y flujo a
> 50 mm de profundidad.

Para el ensayo de cono haría falta pedir a sus autores las series
digitales de masa y temperatura y el mapa de flujo sobre la superficie.

## Auditor y pruebas

`python -m scripts.simulation.audit_g3_net_thermal_budget` imprime ahora
la revisión; con `--history`, la auditoría del 06-10, que **se conserva y
sigue reproduciéndose**; con `--check` compara las dos con sus resultados
guardados. El [registro de la revisión](G3_D1_NET_THERMAL_BUDGET_REVIEW_INPUTS_2026-10-07.json)
va fijado por hash y apunta al registro que revisa.
[Resultado](G3_D1_NET_THERMAL_BUDGET_REVIEW_AUDIT_2026-10-07.json).

La regla está en el código: B solo se identifica si **todos** los
términos de frontera están medidos o acotados, incluido el paso de la
galga a la superficie. El cierre con la demanda no interviene.

`tests/test_g3_net_thermal_budget_review.py`, 31 pruebas offline nuevas.
Impiden:

| Control | Qué detecta |
| --- | --- |
| Promover la banda | Con cualquier término de frontera sin acotar, B es NO-GO |
| Desconocido como cero | Los rangos `null` no se sustituyen; un escenario que los pone a cero lo declara y no es intervalo identificado |
| Reclasificar sin evidencia | Cambiar la clase de un término se rechaza |
| Criterio laxo como identificabilidad | La decisión no recibe cierre, residuo ni umbral |
| Entrada inferida de la masa | El cálculo de lo recibido no admite masa ni demanda |
| Mezcla de corridas o geometrías | Cada ensayo usa su lectura; las alternativas no entran en el balance |
| Almacenamiento como pérdida | Está en la demanda; moverlo a la frontera se rechaza |
| Incertidumbre de otro combustible | La de la masa es `null`; ponerle el 1,9 % se rechaza |
| Extrapolación | Temperaturas fuera de soporte rechazadas |
| Doble conteo y signos | Cada término se resta una vez y en su sentido |
| Procedencia | Trece alteraciones del registro rechazadas; los dos PDF vinculados por sus bytes |

Los oráculos se fijaron a mano antes de extender el auditor. **Una
expectativa se corrigió después:** el escenario resta la emisión tal como
está escrita en el registro, 1,0743 kW/m², y no el valor de cuerpo negro
sin redondear. La diferencia es de 0,00014 kW sobre la bandeja; el auditor
exige por separado que ambos coincidan dentro de 0,00005 kW/m².

## Verificación

Fase offline. No se lanzó Godot: `sim/` no cambia.

- Auditor: reproduce la historia del 06-10 y la revisión del 07-10.
- Pruebas: **31 passed** nuevas; con las del gate anterior y las de los
  gates de los que depende, **365 passed**.
- Guardarraíles: ALL GUARDRAILS PASS, R2-1 incluido.
- Enlaces de los documentos modificados, `git diff --check` y manifiesto
  (49 → 50 entradas): correctos.
- Módulos de `sim/fire` con los mismos SHA-256 que en el checkpoint.

## Biblioteca y derechos

- **Archivado:** Luketa, SAND2010-2511, 60 páginas, 973 671 bytes,
  SHA-256 `2083866a…ded368e`, «Approved for public release; further
  dissemination unlimited»
  ([PDF local](../literature/Sandia/SNL_SAND2010-2511_Assessment_Simulation_Hydrocarbon_Pool_Fire_Tests_2010.pdf),
  [OSTI](https://www.osti.gov/biblio/984087)).
- **Solo enlazado:** Beji y otros (2021),
  [versión de autor en la Universidad de Gante](https://biblio.ugent.be/publication/8702056),
  marcada con copyright.
- **Solo localizador, no obtenido:** Suo-Anttila y otros (2009),
  [doi:10.1016/j.proci.2008.06.044](https://doi.org/10.1016/j.proci.2008.06.044).
- El informe de Sandia archivado el 06-10 y los stashes siguen intactos.

## Siguiente acción

Decisión del usuario, no iniciada.

1. **Autorizar o no el envío de la petición de datos** a Sandia. Es lo
   único que resolvería el bloqueo de B neto en este benchmark.
2. Si interesa antes el calentamiento del líquido que B en incendio,
   **abrir un gate propio del ensayo de cono**, como evaporación controlada
   sin llama.

El contrato de frontera térmica del 06-10 **no queda autorizado para
implementación**. Una reproducción estacionaria con la banda condicional
sería una prueba contable del ledger, no una validación de evaporación, y
no resuelve el bloqueo físico.

No se implementa la frontera térmica ni evaporación, no se conecta al
incendio activo y no se activa CO/FED.
