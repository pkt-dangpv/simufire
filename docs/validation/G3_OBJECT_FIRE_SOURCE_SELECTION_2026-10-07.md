# G3-2/G3-4 - Fuente de incendio por objeto: selección experimental

Fecha: 2026-10-07. Checkpoint de entrada: `9d55289a` (main = rama shareable,
locales y remotas, árboles limpios). Revisión **offline**. Sin cambios en
`sim/`, física activa, catálogo, escenarios ni interruptores, y sin Godot.

Se vuelve al objetivo original: inventario por objeto → fuente de incendio
→ especies → transporte → FED/SVV. La búsqueda del calor neto absorbido
por el combustible (B neto) **queda cerrada en esta vía como NO-GO**: ni
Sandia ni el ensayo de cono lo identifican. Sus benchmarks parciales se
conservan y aquí no se usan.

Dos cosas distintas, que este informe no mezcla:

1. **Reproducir** una fuente experimental prescrita: devolver la curva que
   se midió en un ensayo.
2. **Predecir** esa fuente a partir de material, temperatura, ventilación
   y oxígeno.

Esta fase solo trata la primera. No valida la segunda y no permite
imponer una curva medida al aire libre a un incendio subventilado.

> **Actualización del 08-10.** El módulo aislado que este informe dejó
> propuesto está implementado y verificado:
> [implementación de la fuente aislada de HRR](G3_OBJECT_HRR_SOURCE_IMPLEMENTATION_2026-10-08.md).
> Este informe sigue siendo la **selección** del ensayo; aquel es la
> **reproducción** de su curva. Ninguno de los dos es validación
> predictiva, y las decisiones de la tabla siguiente no han cambiado.

## Decisión

**Ensayo seleccionado: NIST Test016, una silla apilable A sola, bajo la
campana de 3 m** (TN 2303 y Fire Calorimetry Database, versión de 2026).
Su repetición, Test021, queda **reservada** y no se ha usado para elegir
nada.

Seis decisiones por candidato. Un GO en una no aprueba las demás.

| Observable | C1: silla A sola (Test016) | C2: sofá B con chaise y dos almohadas (Test030) | C3: sofá FSRI (R1) |
| --- | --- | --- | --- |
| 1. Reproducción prescrita de HRR | **GO**, una corrida, aire libre | **GO**, una corrida, aire libre, **solo como conjunto** | **GO parcial**, solo local; ignitor e incertidumbre sin documentar |
| 2. Reproducción prescrita de pérdida de masa | **NO-GO**: la serie solo existe como figura; el total es gravimétrico | **NO-GO**: no se midió en el tiempo | **GO parcial**, solo local; incertidumbre de la célula sin documentar |
| 3. Energía acumulada y calor efectivo | **GO parcial**: solo integrales del ensayo completo | **GO parcial**: solo integrales del ensayo completo | **GO parcial**, solo local: energía frente a masa en el tiempo |
| 4. Emisión medida de especies | **GO parcial**: totales de CO, CO₂ y O₂ en el conducto de escape | **GO parcial**: ídem, solo versión 2026; el cambio entre versiones sigue sin explicar | **NO-GO**: no hay especies |
| 5. Rendimiento temporal por masa | **NO-GO** | **NO-GO** | **NO-GO** |
| 6. Extrapolación a otro objeto o régimen | **NO-GO**: la repetición difiere más que la incertidumbre | **NO-GO**: ídem | **NO-GO** |

Ningún ensayo tiene masa y especies numéricas en el tiempo de la misma
corrida. `Y_CO(t)` por objeto sigue NO-GO, como el 29-09.

**Solo hay verificación de reproducción, no validación externa.** La
tabla devuelve la corrida de la que sale, por construcción. La repetición
reservada servirá para contrastar un modelo predictivo cuando exista; hoy
solo mide cuánto se parece un objeto a sí mismo.

CO/FED siguen OFF y NO-GO. Al cerrar esta selección ningún cambio del
motor quedaba autorizado. El 08-10 el usuario autorizó solo el módulo
aislado; conectarlo al motor sigue sin autorizar.

## Los tres candidatos

Tomados del [inventario del 29-09](G3_CO_FUENTES_ELEGIBILIDAD_2026-09-29.md),
sin reabrir la búsqueda. La corrida fuente de cada uno se fijó antes de
comparar curvas: la de número más bajo.

| Id | Clase pedida | Ensayo fuente | Reservados | Por qué entra |
| --- | --- | --- | --- | --- |
| C1 | Objeto individual con ignitor pequeño | NIST Test016, silla apilable A | Test021 | Único par de la campaña declarado «repetición» de un objeto solo |
| C2 | Conjunto combustible explícito | NIST Test030, sofá B con chaise y dos almohadas A | Test036, Test041 | Tres corridas del mismo conjunto; cambia dónde se colocan las almohadas y dónde se enciende |
| C3 | HRR y pérdida de masa de la misma corrida | FSRI, sofá «overstuffed», R1 | R2, R3 | Único con célula de carga numérica y HRR a 1 s |

**Por qué C1.** Es un solo objeto sin accesorios. El ignitor está
documentado y aporta 9,6 kJ, ocho cienmilésimas del calor liberado. Su
HRR es numérico, a 1 Hz y con incertidumbre publicada. La licencia
permite que todo sea reproducible desde el repositorio. Sus valores de
2025 y 2026 coinciden dentro del redondeo, así que el cambio sin explicar
entre versiones no le afecta. Y tiene una repetición que queda reservada.

**Por qué no C2.** Vale igual para HRR, pero solo como conjunto: una de
las dos almohadas es el primer elemento encendido y no se puede separar.
Sus totales de CO cambiaron entre versiones más que el redondeo.

**Por qué no C3.** Es el único con masa y HRR de la misma corrida, pero
no declara licencia, ignitor ni incertidumbre. No puede sostener una
prueba versionada.

El nombre no decidió nada: los dos sofás quedan detrás de una silla.

## Fuentes, versiones y derechos

| Fuente | Identificador y versión | Derechos | Consecuencia |
| --- | --- | --- | --- |
| NIST Fire Calorimetry Database, *Design Fires – Residential and Office Items* | doi:10.18434/mds2-2314, registro 1.0.2; fichas con `NFRL_Report_8.7.1`, actualizadas el 7 de abril de 2026 | El registro declara la licencia abierta de NIST. Comprobado el 07-10 | Los 48 CSV y las fichas ya están en el repositorio; los derivados se publican |
| NIST TN 2303 (marzo de 2025) | [PDF archivado](../literature/NIST/NIST_TN_2303_Character_Burning_Items.pdf) | Publicación de NIST | Montaje, tablas 4 a 6 y apéndices A y C; filas comprobadas por imagen |
| FSRI Materials and Products Database | [repositorio](https://github.com/ulfsri/fsri_materials_database), commit `a432697e` del 23-04-2026, que sigue siendo el último | **Sin licencia declarada**: campo vacío en la API y ningún archivo de licencia. El README solo pide citar | **Las series quedan en local.** Se publican enlace, commit, huellas y agregados escalares |

Las huellas SHA-256 de cada archivo están en el
[registro de entradas](G3_OBJECT_FIRE_SOURCE_INPUTS_2026-10-07.json). Las
tres repeticiones de FSRI se descargaron del repositorio público a
`runs/literature_local/fsri_materials_database_a432697e/`, que Git
ignora; R1 coincide byte a byte con la huella registrada el 29-09.

**Versiones.** Todo lo de NIST se declara como versión 2026. No se
combina ningún valor de TN 2303 (2025) con uno de las fichas (2026) en
una misma magnitud. La causa del cambio entre ambas **sigue sin
demostrar** y aquí no se explica. El bloqueo se aplica observable a
observable:

| Ensayo | Masa perdida | THR 2025 → 2026 (MJ) | Rendimiento de CO 2025 → 2026 | ¿Dentro del redondeo? |
| --- | --- | --- | --- | --- |
| Test016 | igual | 115 → 115,1 | 0,034 → 0,0339 | sí |
| Test021 | igual | 96,0 → 96,1 | 0,030 → 0,0299 | sí |
| Test030 | igual | 1426 → 1426 | 0,033 → 0,0306 | **no** |
| Test036 | igual | 1412 → 1412 | 0,032 → 0,0306 | **no** |
| Test041 | igual | 1413 → 1413 | 0,032 → 0,0316 | sí |

El cambio toca los totales de CO de dos corridas del sofá. No toca el HRR
de ninguna ni nada de la silla.

## Fichas de los ensayos

Los cinco de NIST: al aire libre bajo campana, 1 Hz, tiempo cero en el
evento «Ignition» de la ficha, ventana de integración de «Ignition» a
«Fire Out». Incertidumbres expandidas al 95 % tal como las imprime NIST.

| | Test016 | Test021 | Test030 | Test036 | Test041 |
| --- | --- | --- | --- | --- | --- |
| Objeto | silla A | silla A | sofá B + 2 almohadas | sofá B + 2 almohadas | sofá B + 2 almohadas |
| Campana | 3 m | 9 m × 12 m | 9 m × 12 m | 9 m × 12 m | 9 m × 12 m |
| Caudal base de escape (kg/s) | 2,46 ± 0,07 | 11,7 ± 0,4 | 20,9 ± 0,6 | 32,0 ± 1,0 | 39,1 ± 1,2 |
| Ignitor de propano | 128 W, 75 s, 9,6 kJ | 256 W, 60 s, 14,4 kJ | 128 W, 30 s, 3,9 kJ | 128 W, 43 s, 5,5 kJ | 128 W, 33 s, 4,2 kJ |
| Almohada como primer elemento | no | no | sí | sí | sí |
| Masa inicial (kg) | 9,68 ± 0,02 | 9,70 ± 0,02 | 96,58 ± 0,02 | 97,39 ± 0,02 | 97,76 ± 0,02 |
| Masa perdida (kg) | 3,241 ± 0,028 | 2,969 ± 0,028 | 77,888 ± 0,028 | 77,541 ± 0,028 | 77,132 ± 0,028 |
| Residuo | 67 % | 69 % | 19 % | 20 % | 21 % |
| Pico de HRR (kW) | 621 ± 32 | 690 ± 36 | 2994 ± 153 | 5153 ± 264 | 4036 ± 207 |
| Tiempo al pico (min) | 19,05 | 28,87 | 9,17 | 5,85 | 10,63 |
| Calor total (MJ) | 115,1 ± 6,4 | 96,1 ± 7,0 | 1426 ± 78 | 1412 ± 80 | 1413 ± 80 |
| Calor efectivo (MJ/kg) | 35,5 ± 2,0 | 32,4 ± 2,4 | 18,3 ± 1,0 | 18,2 ± 1,0 | 18,3 ± 1,0 |
| «Fire Out» (s) | 3768 | 2960 | 2211 | 2100 | 2358 |
| Extinción con agua antes de «Fire Out» | 62,68 min | 49,13 min | no consta | 34,95 min | 39,12 min |
| Soporte del CSV (s) | −282 a 4005 | −287 a 3083 | −375 a 2842 | −348 a 2479 | −341 a 2534 |

Canales del CSV, todos en el conducto de escape salvo la radiación: HRR,
canal de quemador, caudal másico de escape, fracciones en volumen de O₂,
CO₂ y CO en base seca, flujo radiante y coeficiente de extinción del
humo. **No hay masa en el CSV.**

FSRI, sofá «overstuffed» (tela y guata de poliéster, espuma de
poliuretano, bastidor de tablero OSB), tres repeticiones a 1 s en un
calorímetro abierto. Columnas usadas: célula de carga, HRR y calor total.
Las unidades no están en el archivo; se toman de la página del material.
No constan ignitor, campana, incertidumbre, qué es el tiempo cero ni cómo
se procesó el HRR. El HRR no tiene ningún valor negativo y sí entre 82 y
153 ceros exactos tras el inicio: llega ya tratado, no en bruto.

## Qué está medido y qué no

| Magnitud | NIST, silla y sofá | FSRI, sofá |
| --- | --- | --- |
| HRR(t) | **Medido**, calorimetría de consumo de oxígeno en el escape, 1 Hz | **Medido**, ya procesado; método sin documentar en lo revisado |
| Masa inicial y final | **Medido**, gravimétrico | — |
| Masa(t) | Silla: **solo figura** (C 16 y C 21), no digitalizada. Sofá: **no se midió** | **Medido**, célula de carga a 1 s; ruido de hasta 3 kg entre muestras consecutivas |
| CO, CO₂, O₂(t) | **Medido** en el conducto de escape, no junto al objeto | **Ausente** |
| Totales de especies y rendimientos | **Calculado** por NIST; reconstruido aquí | — |
| Calor efectivo del ensayo | **Calculado**: calor total entre masa perdida | **Calculado** |
| Ignitor | **Medido**: potencia, duración y energía | **Desconocido** |
| Composición elemental, humedad | **Desconocido** | **Desconocido**; materiales nominales |
| HCN | Solo un total de 2025; ninguna serie | **Ausente** |
| Hollín | Rendimiento por extinción láser; composición desconocida | **Ausente** |
| Parte combustible de la masa inicial | **Desconocido** | **Desconocido** |
| Retardos y respuesta de los analizadores | **Desconocido** en la ficha | **Desconocido** |

El auditor distingue cuatro estados que no son un número: *ausente* (no
existe la columna o la muestra), *desconocido* (existe pero no se dice),
*bajo detección* (la ficha lo imprime así, como en la mesa del Test018) y
*cero medido* (el quemador del Test021). Solo el último vale 0.

## Reproducción de las curvas

La tabla prescrita es el HRR del CSV entre «Ignition» y «Fire Out», sin
suavizar, desplazar ni escalar. Criterio fijado antes de evaluar: pico,
tiempo al pico y calor total dentro de la incertidumbre que imprime la
ficha.

| Ensayo | Pico reconstruido (kW) | Tiempo al pico (s) | Suma de la serie (MJ) | Después de «Fire Out» (MJ) | Muestras negativas | Sesgo al recortarlas (MJ) |
| --- | --- | --- | --- | --- | --- | --- |
| Test016 | 621,46 | 1143 | 115,09 | 0,02 | 11 de 3769 | +0,0013 |
| Test021 | 689,80 | 1732 | 96,06 | 0,12 | 651 de 2961 | +0,79 |
| Test030 | 2994,3 | 550 | 1425,60 | 12,15 | 64 de 2212 | +0,11 |
| Test036 | 5152,6 | 351 | 1411,83 | 2,61 | 58 de 2101 | +0,19 |
| Test041 | 4035,8 | 638 | 1413,18 | 1,50 | 67 de 2359 | +0,19 |

Las cinco devuelven pico, tiempo y total de su ficha. Tres notas:

- **Muestras negativas.** Son ruido del calorímetro, no un sumidero de
  calor. Una fuente no puede emitir potencia negativa, así que la tabla
  las pone a cero y **declara el sesgo**. En la silla seleccionada es
  0,0013 MJ. Bajo la campana grande llega a 0,79 MJ, un 0,8 % del total y
  una décima parte de su incertidumbre: pequeño, pero no nulo.
- **Fin del soporte.** En cuatro de las cinco corridas el ensayo acaba
  con agua. La tabla termina en «Fire Out» porque ahí terminan los
  totales publicados; en el Test030 quedan fuera 12 MJ.
- **Ignitor.** Va dentro de la curva y no se puede separar. Sus 128 W son
  menos de la mitad del ruido del HRR antes de la ignición (0,30 kW de
  desviación típica en el Test016).

El 1 % del calor de la silla tarda 641 s en liberarse; la mitad se ha
liberado a los 1183 s y el 90 % a los 1861 s.

## Lo que muestran las repeticiones

Comparación de valores impresos, sin alinear, escalar ni ajustar nada. La
diferencia se mide contra la suma cuadrática de las dos incertidumbres.

| Par | Pico | Calor total | Tiempo al pico | Masa perdida | Rendimiento de CO |
| --- | --- | --- | --- | --- | --- |
| Silla: Test021 frente a Test016 | **+11 %**, fuera | **−16,5 %**, fuera | **+589 s** | **−8,4 %**, fuera | **−11,8 %**, fuera |
| Sofá: Test036 frente a Test030 | **+72 %**, fuera | −1,0 %, dentro | −199 s | −0,4 %, fuera | 0 %, dentro |
| Sofá: Test041 frente a Test030 | **+35 %**, fuera | −0,9 %, dentro | +88 s | −1,0 %, fuera | +3,3 %, dentro |

- **La misma silla no da la misma curva.** Las dos corridas difieren más
  que su incertidumbre en pico, energía, masa y CO, y la segunda tarda
  casi diez minutos más en crecer. Cambian la campana, el ignitor y el
  caudal; la fuente no dice cuál de las tres cosas pesa.
- **El mismo sofá repite la energía y no la curva.** El calor total
  coincide al 1 %; el pico va de 3,0 a 5,2 MW según dónde se enciende.
- **FSRI**, sin incertidumbre publicada contra la que medir: el pico
  varía un 3,5 %, el calor total un 9,6 % y la masa perdida menos de un
  1 %.

Consecuencia: una tabla prescrita representa **una corrida**. No es «la
silla» ni «el sofá», y menos otro objeto.

## Energía, masa y calor efectivo

- **NIST.** Lo comprobable es un número por corrida: calor total entre
  masa perdida. Reconstruido: 35,51 ± 2,00 MJ/kg en el Test016 (ficha:
  35,5 ± 2,0). No hay calor efectivo en el tiempo porque no hay masa en
  el tiempo.
- **FSRI**, con masa y HRR de la misma corrida:

| Repetición | Pico (kW) | Calor total (MJ) | Masa perdida (kg) | Calor efectivo total (MJ/kg) | Del 10 al 50 % de la energía | Del 50 al 90 % |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | 2800 | 723 | 48,1 | 15,0 | 16,4 | 14,8 |
| R2 | 2899 | 760 | 47,7 | 15,9 | 16,9 | 15,0 |
| R3 | 2871 | 793 | 47,8 | 16,6 | 16,6 | 15,6 |

**El calor efectivo no es un número durante el ensayo:** en las tres
repeticiones la primera mitad libera entre un 6 y un 12 % más por
kilogramo que la segunda.

**Control con datos reales de «MLR = HRR/HOC».** Si se reconstruye la
masa como el HRR acumulado entre el calor efectivo total, se aparta de la
célula de carga de la misma corrida hasta 2,6 kg en R1, un 5,5 % de la
masa perdida (1,7 y 1,8 kg en R2 y R3). Y eso usando el calor efectivo de
esa misma corrida, que en un caso real no se conoce. El HRR entre un
calor de combustión es un cálculo; nunca una pérdida de masa medida.

## Especies

Reconstrucción propia con el método de la guía de la base de datos:
fracción en el escape menos el fondo de los 60 s previos, por el caudal
másico, de «Ignition» a «Fire Out». Criterio: dentro de la incertidumbre
de la ficha.

| Ensayo | CO (kg/kg): propio / ficha | CO₂ (kg/kg): propio / ficha | O₂ (kg/kg): propio / ficha |
| --- | --- | --- | --- |
| Test016 | 0,0342 / 0,0339 ± 0,0013 | 2,553 / 2,588 ± 0,096 | 2,520 / 2,559 ± 0,085 |
| Test021 | **0,0310** / 0,0299 ± 0,0011 | 2,373 / 2,362 ± 0,088 | 2,346 / 2,355 ± 0,079 |
| Test030 | 0,0306 / 0,0306 ± 0,0011 | 1,712 / 1,712 ± 0,062 | 1,401 / 1,402 ± 0,045 |
| Test036 | 0,0305 / 0,0306 ± 0,0011 | 1,696 / 1,697 ± 0,061 | 1,403 / 1,405 ± 0,045 |
| Test041 | 0,0317 / 0,0316 ± 0,0011 | 1,699 / 1,699 ± 0,061 | 1,391 / 1,387 ± 0,044 |

Catorce de quince dentro. El CO del Test021 queda un 3,7 % por encima,
en el borde mismo de la incertidumbre: la excede en tres millonésimas. Ya
se conocía desde el 29-09 y no se ajusta.

Lo que esto permite y lo que no:

- **Permite** contrastar totales de CO, CO₂ y O₂ consumido del ensayo
  completo, medidos en el conducto.
- **No permite** un rendimiento en el tiempo: falta la masa en el tiempo.
  Un rendimiento integrado es un número para una ventana, no una ley
  `Y_CO(t)`.
- **No es** una concentración junto al objeto ni en un recinto.

Un dato calculado, no una composición: el carbono que sale como CO y CO₂
es 0,71 kg por kilogramo de masa perdida en la silla y 0,48 en el sofá.
Describe lo que se quemó, no de qué está hecho el objeto.

## Conflictos de las fuentes, sin resolver

- **Composición de la silla A.** TN 2303 dice asiento y respaldo de
  plástico duro; la ficha de la base de datos dice tablero de partículas.
  La composición queda como **desconocida**.
- **Ignitor del Test016.** La ficha anota un reencendido a 0,75 min y un
  aumento del piloto a 120 ml/min a 1,12 min; TN 2303 imprime 128 W
  durante 75 s. En cualquier caso es una diezmilésima del calor.
- **Ignitor del Test021.** 256 W por 60 s son 15,4 kJ; la tabla imprime
  14,4 kJ.
- **Masa inicial del Test041.** La ficha imprime 97,76 kg en su tabla y
  97 960 g en su descripción, como TN 2303. La masa perdida sale de la
  tabla.
- **Etiquetas de la tabla 6 de TN 2303.** Llama A, B y C a los Test030,
  036 y 041; la tabla 4, el apéndice A y las fichas dicen sofá B los
  tres. Se sigue a estas últimas.
- **Canal de quemador del Test016.** Marca 0,71 kW antes de la ignición
  sin quemador declarado, mientras el HRR marca 0,12 kW. No se resta.

## Contrato para el siguiente cambio del motor

Propuesto el 07-10, entonces sin implementar ni autorizar. **Implementado
el 08-10 como módulo aislado**, con autorización del usuario limitada a
eso:
[informe de implementación](G3_OBJECT_HRR_SOURCE_IMPLEMENTATION_2026-10-08.md).
El contrato de abajo es el que se implementó. Nada de producto lo carga
y no está conectado al motor, al fuego de sala ni al oxígeno.

**Alcance exacto: reproducir el HRR del Test016, aislado.** Nada más.

**Por qué no sirven los contratos que ya existen:**

- El campo `hrr_curve` de `FuelObjectModel` no reproduce nada. Es un
  **peso de reparto** del fuego de sala entre objetos: el HRR lo decide
  el fuego de sala con su propio suavizado y sus topes, la curva se
  recorta por `max_hrr_kw` y fuera de su rango **mantiene el último
  valor** en lugar de terminar.
- `PrescribedFuelReleaseModel` es un programa de **masa**: exige masa
  inicial, kg/s y un componente con química CHO. Esta corrida no tiene
  serie numérica de masa ni composición aprobada. Meter el HRR ahí
  obligaría a inventar ambas.

**Cambio mínimo:** un módulo puro nuevo, hermano del programa de masa,
`sim/fire/PrescribedObjectHrrSource.gd`, sin `class_name` y sin que nada
de producto lo cargue. No se edita ningún módulo existente.

| Aspecto | Contrato |
| --- | --- |
| Propietario | Un único identificador: el objeto **tal como se ensayó**, entero |
| Entrada medida | HRR(t) de una corrida, 1 Hz, de «Ignition» a «Fire Out», con la huella del CSV |
| Entrada calculada | Integral de la tabla y sesgo del recorte de negativos, hechos fuera del motor |
| Entrada supuesta | Interpolación lineal entre muestras; los negativos son ruido |
| Desconocido, queda nulo | Tasa de pérdida de masa, rendimientos, composición, fracción radiante en recinto |
| Interpolación | Lineal por tramos |
| Tiempo | Origen en la ignición de la corrida; reloj propio de la fuente |
| Fuera del soporte | **Se rechaza.** Sin extrapolar y sin mantener el último valor |
| Muestras negativas | El módulo las rechaza; el recorte se hace y se declara al construir la tabla |
| Ignitor | Dentro de la curva, inseparable |
| Demanda y aceptación | Como el programa de masa: se propone un intervalo, se confirma lo aceptado, lo rechazado se anota y **no se pone en cola** |
| Identidad | Huella del contenido completo, propietario incluido |

**Presupuesto que puede comprobarse:** la energía entregada es la
integral de la tabla; lo aceptado más lo rechazado es lo programado; la
integral cae dentro de 115,1 ± 6,4 MJ.

**Lo que no puede comprobarse con esta fuente:** masa, energía química
del combustible, calentamiento sensible y calor de frontera. El HRR
calorimétrico no es ninguna de las cuatro, y un balance térmico no se
cierra por construirlo desde la masa.

**Decisiones pendientes antes de acoplarlo al oxígeno y al recinto**, que
son del usuario:

1. Qué hace la fuente cuando el recinto no puede aportar el oxígeno que
   su curva pide, y quién es el dueño de ese déficit.
2. Cómo se marca la salida del régimen de la fuente. La curva es de aire
   libre; en un recinto viciado deja de ser válida y no debe seguir
   aplicándose en silencio.
3. Cómo conviven esta fuente y el fuego de sala bajo el contrato de
   propiedad C1–C9.
4. Reparto radiante y convectivo.

**Sin aprobación, de forma explícita:** CO, FED, producto, cualquier otro
objeto y cualquier régimen que no sea aire libre.

## Auditor y pruebas

- [`audit_g3_object_fire_source.py`](../../scripts/simulation/audit_g3_object_fire_source.py):
  importador y auditor offline. Comprueba huellas, cabeceras con sus
  unidades y eje temporal; reconstruye las curvas sin ajuste físico;
  calcula los integrales y los contrasta con las fichas archivadas; y
  decide por observable. Reutiliza el lector de fichas y la tabla de
  versiones del 29-09.
- [Registro de entradas](G3_OBJECT_FIRE_SOURCE_INPUTS_2026-10-07.json),
  [auditoría guardada](G3_OBJECT_FIRE_SOURCE_AUDIT_2026-10-07.json) y
  [agregados de las series locales](G3_OBJECT_FIRE_SOURCE_LOCAL_AGGREGATES_2026-10-07.json).
- `tests/test_g3_object_fire_source.py`: 81 pruebas. Dos necesitan la
  copia local de FSRI y **se saltan, con ese motivo, si falta**; el resto
  no depende de ella.
- [`run_g3_object_source_control_mutations.py`](../../scripts/simulation/run_g3_object_source_control_mutations.py):
  28 variantes del auditor reescritas en memoria.

Controles negativos, cada uno con su variante:

| Riesgo | Qué se rechaza |
| --- | --- |
| MLR «medida» como HRR/HOC | Presentar como medida una tasa calculada |
| Rendimiento integrado como ley | Evaluar un rendimiento del ensayo en un instante |
| Conjunto asignado a una parte | Dar al sofá solo el ensayo del sofá con almohadas |
| Química ajena | Usar heptano para un mueble |
| Misma curva como entrada y prueba | Declarar predicción con la corrida de entrada |
| Reserva usada para ajustar | Ajustar con la corrida reservada, o contrastar con una ya ajustada |
| Mezcla de corridas o versiones | Energía de una corrida con masa de otra; 2025 con 2026 |
| Unidades | Cabecera con otra unidad; unidad no declarada |
| Ausente, desconocido, bajo detección y cero | Tomar cualquiera de los tres primeros como 0 |
| Soporte | Integrar fuera de la ventana; extrapolar la tabla |
| Procedencia | Bytes cambiados; eje temporal roto; archivo local que no es el revisado |
| Derechos | Aprobar como versionable una fuente sin licencia |
| Decisiones encadenadas | Que el GO de HRR apruebe masa, o que los totales aprueben un rendimiento temporal |

## Verificación

- Pruebas del módulo: **81 passed**. Sin la copia local: 79 passed y 2
  skipped.
- Variantes de control: el auditor sin cambios pasa y **28 de 28**
  detectadas.
- Con todas las pruebas offline de G3, 30 módulos: **839 passed**.
- `--check` del auditor: coincide con la auditoría guardada.
- `ALL GUARDRAILS PASS` con R2-1; estilo, enlaces y `git diff --check`.
- `sim/` sin cambios. Godot no se ha lanzado: nada de esta fase lo
  necesita.

Reproducir:

```text
python -m scripts.simulation.audit_g3_object_fire_source --check
python -m scripts.simulation.run_g3_object_source_control_mutations
```

## Límites de esta fase

- Los umbrales son incertidumbres publicadas o reglas del 29-09; ninguno
  se eligió aquí. Las sumas exploratorias se miraron antes de escribir el
  auditor, pero ningún criterio depende de ellas.
- La reconstrucción de especies es propia y simplificada; coincide con
  las fichas, no las sustituye.
- La masa en el tiempo de la silla no se ha digitalizado. Hacerlo daría
  una lectura de figura, no un dato, y no cambiaría ninguna decisión de
  esta fase.
- No se ha contactado con NIST, FSRI ni ningún autor.

## Siguiente acción

El 07-10 era del usuario: autorizar o no el módulo aislado descrito
arriba. **Lo autorizó el 08-10 y está hecho**, con su fixture real del
Test016, su campaña de variantes y la cadena R2-1 completa:
[informe de implementación](G3_OBJECT_HRR_SOURCE_IMPLEMENTATION_2026-10-08.md).

Lo siguiente vuelve a ser del usuario: las decisiones de acoplamiento
listadas arriba. El acoplamiento al recinto no está autorizado.

Dato mínimo que desbloquearía más: la serie numérica de la célula de
carga de los Test016 y Test021, que NIST midió y publicó solo como
figura. Con ella habría masa, HRR y especies de la misma corrida.
