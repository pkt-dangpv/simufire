# Referencia Empirica - Ghanekar 2026

Referencia:
- Shruti Ghanekar, "Evolution of combustion gas concentrations in full-scale residential fire environments", Fire Safety Journal 162 (2026) 104724.

## PROCEDENCIA VERIFICADA (2026-08-22, sesion 26)

**El articulo primario esta en el repositorio y ha sido leido integramente.**

| campo | valor |
|---|---|
| ruta versionada | `docs/literature/Evolution of combustion gas concentrations in full-scale residential fire.pdf` |
| seguimiento | **trackeado en Git**, no ignorado |
| blob Git | `d91a0b8b54e33111b582e7aa0f2f779a7767f752` |
| SHA-256 | `1B2A1B00EE4ADECEA86771694260AAF8233637E69679B794C8BA1A6B44675030` |
| tamano | 4 302 995 bytes, PDF-1.7, 9 paginas |
| introducido por | commit `1ba0ee74` (2026-04-19); reubicado por `686b09fa` (2026-06-17) |
| DOI | `10.1016/j.firesaf.2026.104724` |
| version | **Version of Record** (`jav:journal_article_version = VoR` embebido, sello CrossMark, maquetacion final) |
| licencia | **CC BY-NC-ND 4.0, acceso abierto**, (c) 2026 The Author |
| fechas | recibido 2025-11-19; revisado 2026-01-28; aceptado 2026-03-11; en linea 2026-03-17 |

> **Procedencia historica OBSOLETA, conservada solo como rastro:**
> `F:\OneDrive\Escritorio\Evolution of combustion gas concentrations in full-scale residential fire.pdf`.
> Esa ruta **ya no es la fuente** y **no es accesible**: la unidad `F:` no esta
> montada en la maquina actual, y OneDrive resuelve a `C:\Users\dangp\OneDrive`.
> No debe citarse como origen de ninguna cifra.

> **RETRACTACION (sesion 26).** Las sesiones 22 y 23 afirmaron que *"el PDF
> primario no esta en el repositorio"* y que las cifras publicadas procedian de
> una transcripcion local *"no contrastada"*. **Ambas afirmaciones eran falsas**:
> el articulo llevaba trackeado en Git desde el 2026-04-19, cuatro meses antes.
> El error fue mirar solo la ruta `F:` declarada, no el propio repositorio.
> La transcripcion **ya ha sido contrastada** contra el articulo en la sesion 25:
> todos los valores de referencia de este documento resultaron **VERIFICADOS**
> (ver mas abajo), con una unica contradiccion material, la atribucion de especie
> del IDLH de cocina.

**Incertidumbres que siguen abiertas** (redefinidas contra la fuente real, no
contra la transcripcion):

1. **Retardo de muestreo.** Los `16-23 s` (p.3 §2.2) son un retardo
   **extremo a extremo** que agrupa transito por la linea y respuesta del
   analizador; no es descomponible y **la longitud de la linea no se publica**.
   El articulo **no declara** si los tiempos publicados fueron corregidos por el
   retardo **ni declara que no lo fueran**: es un **NO DECLARADO**. No debe
   afirmarse ninguna de las dos cosas. Magnitud relevante: excede toda la
   desviacion tipica del conjunto dormitorio (12-18 s).
2. **Dos lineas de muestreo.** El caudal se divide en dos (una con columna
   desecante Drierite al ULTRAMAT-23, otra al TDLAS de HCN) y solo se publica
   **un** rango de retardo agregado; **no hay valor por linea**.
3. **Base seca.** El tren de muestreo **elimina la humedad sin cuantificarla**
   (p.8 §4), asi que toda concentracion publicada es **en base seca**. SimuFire
   no tiene tratamiento seco/humedo alguno. Sesgo sistematico sin cuantificar.
4. **Detalle del estimador `tDelta`** no publicado: grado del polinomio, regla de
   iteracion y convergencia, tolerancia numerica de "interseccion" y ventana
   exacta de background. El metodo es reproducible **en especie**, no bit a bit.

**Lo que ya NO es una incertidumbre.** La sesion 23 sostuvo que faltaba
transcribir un *"umbral de deteccion del analizador"* que definiese la respuesta
inicial y que sin el el contrato de O2 no era satisfacible. **Esa premisa es
falsa**: el articulo no define la respuesta inicial mediante ningun umbral. Ver
la seccion "Definicion real de la respuesta inicial" mas abajo.

## Por que importa para Simufire

Este paper aporta datos de escala real para contrastar la evolucion temporal de:
- `O2`
- `CO2`
- `CO`
- `HCN`
- tiempos a `flashover`
- tiempos a `IDLH`
- tiempos a `FED`

Eso lo convierte en una referencia mucho mas fuerte que nuestros baselines actuales, que hoy validan contra escenarios internos del repo.

## Escenario experimental del paper

### Estructura
- Vivienda unifamiliar de una planta, `160 m2`, tipo ranch.
- Altura de techo: `2.45 m`.
- Cuatro dormitorios, dos banos y zona abierta cocina-salon.
- HVAC apagado pero con rejillas abiertas para movimiento pasivo de aire y gases.

### Medicion
- Punto de muestreo en el extremo del pasillo a `0.9 m` de altura.
- Frecuencia de muestreo: `1 Hz`.
- Tiempo de transporte del gas hasta analizadores: `16-23 s`.

**Ampliado contra la fuente (sesion 26), p.2-3 §2.2:**
- Tren de muestreo: bomba de diafragma, toma de acero inoxidable, filtros HEPA de
  `5 um` y `3 um`, condensador (serpentin en bano de agua-hielo) y division en
  **dos lineas**: una sobre columna desecante Drierite al **Siemens ULTRAMAT-23**
  (CO2 y CO por **NDIR**, O2 por sensor **paramagnetico**), otra al sistema
  **TDLAS** de infrarrojo medio para HCN.
- Rangos y resolucion: CO `0-5 vol%` a `0.001 vol%`; CO2 y O2 `0-25 vol%` a
  `0.01 vol%`. Incertidumbre relativa `+/-1 %` frente a gas patron (**no se
  declara si es del valor leido o de fondo de escala**).
- HCN: **limite de deteccion 1 ppm**, **limite de cuantificacion 3 ppm**,
  incertidumbre relativa `4.1 %` a `1500 ppm`.
- **`1 Hz` es la cadencia de registro, no la resolucion temporal de un evento.**
  El tiempo de respuesta del analizador (T90) **no se publica**. La resolucion
  efectiva queda acotada por la incertidumbre de medida del retardo
  (**"al menos 3.4 s"**), por el convenio de simultaneidad de `5 s` y por el
  redondeo de todos los tiempos publicados a `0.1 min` (`6 s`): del orden de
  **`+/-5-6 s`** en el mejor caso.
- El retardo `16-23 s` se midio cronometrando la respuesta del analizador a una
  descarga de `3-5 s` de gas patron sobre la toma (patrones: `2.51 vol% CO,
  12.60 vol% CO2, balance N2` y `50 ppm HCN, balance N2`).
- **Ubicacion del punto de muestreo, justificacion del articulo** (p.2 §2.1):
  `0.9 m` representa la altura de un ocupante **de rodillas o gateando**; el
  emplazamiento es el **menos influido por la meteorologia exterior**; fue el
  **primero en responder** de todos los medidos en el estudio mayor; y **no esta
  en la trayectoria directa de flujo**, pero **el gas se estanca contra la
  pared**, por lo que la exposicion toxica puede superar alli a la termica.
  *Esta ultima observacion es la mas relevante para SimuFire: la sonda publicada
  esta en una zona de estancamiento de pared, que un modelo de dos zonas bien
  mezcladas no representa.*
- **Base seca:** el condensador y el desecante eliminan la humedad **sin
  cuantificarla** (p.8 §4), asi que todas las concentraciones publicadas son
  **en base seca**.

### Ventilacion inicial
- Puerta principal abierta en todos los experimentos.
- Ventana del compartimento de fuego abierta/removida desde el inicio:
  - dormitorio: `1.8 m x 0.6 m`
  - cocina: `0.9 m x 0.9 m`

### Definicion de flashover
- Se considera `flashover` cuando la temperatura a `0.9 m` en el compartimento de fuego supera `600 C`.
- Verificado contra la fuente (p.4 §2.3, refs [29-31]). Instrumentacion: array
  vertical de **8 termopares tipo K de union desnuda, 1.27 mm**, mas confirmacion
  visual por video. **Nota:** la altura del criterio (`0.9 m`) **coincide** con la
  de la sonda de gases.

### Definicion real de la respuesta inicial (`tDelta`) — p.4 §2.3

**No es un umbral de concentracion.** Es un criterio de **ultima interseccion con
el baseline**, en cuatro operaciones:

1. `cambio` = diferencia absoluta entre la concentracion medida y la
   **concentracion de background promedio**;
2. se infiere un **baseline lineal** sobre la ventana desde el inicio del
   background hasta el instante de intervencion;
3. mediante un **ajuste polinomico iterativo**;
4. el **ultimo indice temporal anterior a la intervencion en el que el cambio
   intersecta ese baseline** es el tiempo de respuesta inicial.

Se calcula **por gas**. Ademas, `t_dO2` ancla la ventana de promediado de la tasa
de cambio **para todos los gases**, no cada gas la suya.

**No existe en el articulo ningun umbral en `vol%` o `ppm` que defina la
respuesta inicial.** Los unicos umbrales del articulo sirven a la tenabilidad
(IDLH, FED) o son limites instrumentales. Corroboracion con los propios datos del
articulo: **ya hay cambio medible antes de `t_dO2`** — dormitorio CO2
`0.06 +/- 0.01 vol%`, HCN `9 +/- 13 ppm` (p.6 §3.3), con dispersion superior a su
propia media; eso es incompatible con un umbral fijo.

**Consecuencia practica:** el suelo de discriminacion real de HCN en estos
ensayos es del orden de **10-20 ppm**, no el `1 ppm` del limite de deteccion.

**Prohibido inventar un umbral.** La recalificacion debe implementar el
**estimador**, no sustituirlo por un corte en `vol%`. La observacion de la sesion
22 de que un corte de `0.10-0.15 vol%` "cae cerca" de la ventana publicada es una
coincidencia de un metodo distinto y no debe convertirse en contrato.

### Definicion de FED y de IDLH — p.4 §2.3 y p.7 §3.4

- **FED**: modelo de **Purser** [11] (SFPE Handbook, 5a ed.) aplicado a
  `O2`, `CO2`, `CO` y `HCN`. Es una **dosis asfixiante**; **no incluye termino
  termico**. `FED = 1` = colapso y perdida de consciencia por asfixia en el 50 %
  de la poblacion; `FED = 0.3` = limite conservador para poblacion general segun
  **ISO 13571** [32]; `FED = 3` = incapacitacion de los mas sanos [33]. El
  articulo escribe `FED_IN` en §3.4 y en la Fig. 6 sin definir que abrevia "IN".
- **IDLH (NIOSH)**: `CO2` 40 000 ppm, `CO` **1200 ppm**, `HCN` 50 ppm; `O2` por
  debajo de `19.5 vol%`, aplicado como **descenso mayor de `1.4 vol%`**. La regla
  de combinacion es **O logico** entre especies, **no** una dosis acumulada.
- **Los `+/-` publicados** son **desviacion tipica muestral** entre ensayos,
  declarada como incertidumbre expandida con **factor de cobertura k = 1**
  (p.4 §3), sobre 10 ensayos de dormitorio y 6 de cocina. **Es aproximadamente
  un intervalo del 68 %, no una banda del 95 %**, no incluye la incertidumbre
  instrumental ni el retardo, y con `n = 6` la propia desviacion esta mal
  determinada.

## Benchmarks extraidos del paper

### Dormitorio
- `time_to_flashover = 3.1 +/- 0.3 min`
- `time_to_vent_failure = 3.8 +/- 0.4 min`
- `time_to_intervention = 4.9 +/- 0.3 min`

- Respuesta inicial en pasillo a `0.9 m`:
  - `tDeltaO2 = 3.3 +/- 0.3 min`
  - `tDeltaCO2 = 3.3 +/- 0.3 min`
  - `tDeltaCO = 3.4 +/- 0.3 min`
  - `tDeltaHCN = 3.3 +/- 0.2 min`

- Cambio maximo antes de intervencion:
  - `DeltaO2 = -9.25 +/- 1.65 vol%`
  - `DeltaCO2 = +8.53 +/- 1.85 vol%`
  - `DeltaCO = +1.42 +/- 0.50 vol%`
  - `DeltaHCN = +97 +/- 47 ppm`

- Tenabilidad:
  - `time_to_IDLH = 3.6 +/- 0.2 min`
  - `time_to_FED_0_3 = 3.7 +/- 0.2 min`
  - `time_to_FED_1 = 3.7 +/- 0.2 min`

### Cocina / salon
- `time_to_flashover = 14.9 +/- 0.5 min`
- `time_to_vent_failure = 15.2 +/- 1.8 min`
- `time_to_intervention = 16.8 +/- 0.9 min`

- Respuesta inicial en pasillo a `0.9 m`:
  - `tDeltaO2 = 6.7 +/- 1.4 min`
  - `tDeltaCO2 = 6.8 +/- 1.6 min`
  - `tDeltaCO = 8.0 +/- 2.2 min`
  - `tDeltaHCN = 9.8 +/- 3.5 min`

- Cambio maximo antes de intervencion:
  - `DeltaO2 = -19.88 +/- 1.27 vol%`
  - `DeltaCO2 = +19.79 +/- 0.77 vol%`
  - `DeltaCO > +4.83 +/- 0.46 vol%`
  - `DeltaHCN = +660 +/- 211 ppm`

- Tenabilidad:
  - `time_to_IDLH = 10.7 +/- 1.7 min`
  - `time_to_FED_0_3 = 9.1 +/- 2.0 min`
  - `time_to_FED_1 = 10.4 +/- 2.1 min`

## Contraste de esta transcripcion contra el articulo (sesion 25-26)

Todos los valores de las secciones "Dormitorio" y "Cocina / salon" de arriba
—eventos de la Tabla 1, las cuatro especies de la Tabla 2 en ambos escenarios,
los cambios maximos (incluido el `>` del CO de cocina) y los tiempos de
tenabilidad— fueron contrastados uno a uno y resultaron **VERIFICADOS
exactamente**. Tambien lo fueron altura de techo, inventario de salas, estado del
HVAC, ubicacion y altura de la sonda, `1 Hz`, el rango `16-23 s`, las dimensiones
de ventana y el criterio de flashover.

Los seis valores que sostienen contratos:

| valor en contrato | publicado | fuente | veredicto |
|---|---|---|---|
| O2 pasillo lejano dormitorio `198 +/- 18 s` | `3.3 +/- 0.3 min` | p.5 Tabla 2 | **VERIFICADO** |
| O2 pasillo lejano cocina `402 +/- 84 s` | `6.7 +/- 1.4 min` | p.5 Tabla 2 | **VERIFICADO** |
| FED 0.3 cocina `546 +/- 120 s` | `9.1 +/- 2.0 min` | p.7 §3.4 | **VERIFICADO** |
| FED 1.0 cocina `624 +/- 126 s` | `10.4 +/- 2.1 min` | p.7 §3.4 | **VERIFICADO** |
| flashover cocina `894 +/- 30 s` | `14.9 +/- 0.5 min` | p.4 Tabla 1 | **VERIFICADO** |
| **IDLH de CO cocina `642 +/- 102 s`** | `10.7 +/- 1.7 min`, pero es el tiempo gobernado por **O2** | p.7 §3.4 | **CONTRADICHO** |

### La unica contradiccion material: el IDLH de cocina no es de CO

`10.7 +/- 1.7 min` es el tiempo hasta el **primer** cruce de IDLH por cualquier
especie, y el articulo lo atribuye a **baja concentracion de O2** (descenso mayor
de `1.4 vol%`) **tres veces**: resumen (p.1), §3.4 (p.7) y §5 (p.8).

Con la intervencion de cocina en `16.8 min` (p.4 Tabla 1), el articulo da los
cruces relativos a la intervencion:

| especie | aritmetica | tiempo tras ignicion |
|---|---|---|
| **O2** | `16.8 - 6.1` | **`10.70 min` = `642 s`** — reproduce el titular exactamente |
| HCN | `16.8 - 2.3` | `14.50 min` = `870 s` |
| **CO** | `16.8 - 2.2` | **`14.60 min` ~ `876 s`** |

Comprobacion independiente sobre el dormitorio: reconstruyendo su `3.6 min` a
partir de los cuatro subgrupos de p.7 §3.4 sale
`(4*3.5 + 4*3.5 + 4.1 + 3.6)/10 = 3.57 ~ 3.6 min`. Es decir, la magnitud
publicada es "tiempo hasta la **primera** especie que cruza", no un tiempo por
especie.

**No se deriva tolerancia** para una entrada de CO corregida: `t_CO =
t_intervencion - delta_CO` es una diferencia **pareada** por ensayo y la
covarianza **no esta publicada**, asi que la dispersion muestral no es
recuperable. Una cuadratura ingenua de `0.9` y `0.7 min` **no** la sustituye.

## Erratas e inconsistencias del propio articulo

Se registran **sin corregirlas** ni inferir cual fue el criterio realmente
aplicado cuando el articulo es ambiguo.

1. **Erratas de unidades, p.7 §3.4.** Imprime `40 000 ppm (40 vol%)` y
   `1200 ppm (1.2 vol%)`. En realidad `40 000 ppm = 4 vol%` y
   `1200 ppm = 0.12 vol%`: **ambos parentesis estan 10x altos**. Cual de las dos
   formas se aplico realmente **no se puede determinar** desde el texto, y el
   articulo no lo repite en ningun otro sitio. Nuestro observable usa `1200 ppm`.
2. **Areas de ventilacion incoherentes.** Aberturas declaradas (p.2 §2.1):
   ventana de dormitorio `1.8 x 0.6 = 1.08 m2`, ventana de cocina
   `0.9 x 0.9 = 0.81 m2`, puerta principal impresa como `0.9 x 0.9 = 0.81 m2`.
   Areas combinadas declaradas (p.6-7 §3.3): `2.97 m2` (dormitorio) y `2.28 m2`
   (cocina). Con **una sola** puerta comun, las areas combinadas deben diferir en
   la diferencia de ventanas: difieren en `0.69 m2` mientras que las ventanas
   difieren en `0.27 m2`. La cifra de dormitorio cuadra **exactamente** con una
   puerta estandar de `0.9 x 2.1 m` (`1.08 + 1.89 = 2.97`), lo que sugiere que la
   dimension impresa de la puerta es una errata; pero entonces la de cocina no
   cierra. **Al menos uno de los cuatro numeros impresos es incorrecto.**
3. **Factor post-flashover.** El articulo dice que la ventilacion post-flashover
   del dormitorio fue **`2` veces** la de cocina; con sus propias areas,
   `4.09 / 2.69 = 1.52`. En cambio la razon de combustible **si** cuadra
   exactamente: `923 / 234 = 3.94`.
4. **Deriva en el encuadre del FED.** p.4 §2.3 define `FED = 1` como colapso en
   el "50 % de la poblacion" y `FED = 0.3` por subpoblaciones vulnerables;
   p.7 §3.4 reetiqueta la misma escalera como "incapacitacion" y convierte `0.3`
   en umbral de incapacitacion para poblacion general. Los dos pasajes no
   concuerdan.

## Lo que esto dice sobre nuestro simulador actual

### Lo comparable hoy
- Simufire modela `O2`, `CO`, `CO2` y `FED` asfixiante/termico.
- El caso `ghanekar_bedroom_hallway` replica los rasgos principales del ensayo de dormitorio: techo de `2.45 m`, ventana del dormitorio abierta, puerta exterior abierta y transporte por pasillo.
- El pasillo se divide en dos zonas numericas (`Hallway_Near` y `Hallway_Far`); la union entre ambas se trata como frontera amplia, no como puerta fisica.
- **[CORREGIDO 2026-08-22, sesion 23]** Simufire **si modela `HCN`**: la version
  anterior de esta linea afirmaba que no, y es falso contra el artefacto congelado
  (`room_2_peak_hcn_ppm = 56.96`, con columnas `HCN=`/`HCNu=` en el log y
  descomposicion `fed_hcn`). Lo que **sigue faltando** es la **sonda localizada a
  `0.9 m`** para especies y el **retardo de linea de muestreo**. Existe ya
  `temp_at_0_9m_c` (temperatura resuelta en altura), pero **no** un equivalente
  para `O2`/`CO`/`HCN`.

### Estado de calibracion actual
- Ultima corrida de `ghanekar_bedroom_hallway`:
  - `time_room_2_o2_below_20_4pct_s = 176.7 s`
  - `time_room_2_co_above_200ppm_s = 276.3 s`
  - `room_2_peak_co_ppm = 518.9 ppm`
  - `room_2_peak_co2_ppm = 8221.6 ppm`
  - `peak_temp_upper_c_global = 611.1 C`
- `run_reference_checks.ps1` mantiene 28/28 checks obligatorios en `PASS`.
- El check de O2 remoto queda dentro de la ventana del paper (`198 +/- 30 s`).
- El CO remoto supera 200 ppm, pero todavia llega tarde frente al objetivo no bloqueante (`204 +/- 45 s`).

> **[OBSOLETO — corregido 2026-08-22, sesion 23]** Las tres lineas anteriores y los
> valores de "Ultima corrida" de arriba son de una corrida antigua y **ya no
> describen el runtime**. Contra la corrida congelada autoritativa de la sesion 19:
>
> | metrica | valor obsoleto arriba | valor fresco congelado |
> |---|---:|---:|
> | `time_room_2_o2_below_20_4pct_s` | 176.7 s | **232.5 s** |
> | dentro de `198 +/- 30 s` = [168, 228] | si | **NO** |
> | `room_2_peak_co_ppm` | 518.9 ppm | 1069.5 ppm |
>
> El check de O2 remoto **falla**; fue demovido a gap non-gating en la sesion 23
> y P1R5 lo finaliza como **VERIFIED_MODEL_LIMITATION**. No se cambio ni el
> `expected` ni la tolerancia, y la clasificación no concede validación empírica.
> Ademas, `28/28 obligatorios en PASS` no describe el estado actual: el corpus
> vigente es de 350 required con 6 fallos clasificados como VALID_GAP.

### Interpretacion honesta
- La tendencia fisica ya es coherente: combustible sintetico moderno produce mas humo/CO y el flow-path arrastra gases al pasillo remoto.
- La calibracion no debe leerse como una replica completa de la sonda experimental del paper.
- Para cerrar Ghanekar del todo hace falta modelar medicion a `0.9 m`, `HCN`, retardo de linea de muestreo y mezcla vertical/local, no solo promedios por sala.

## Brechas de modelo mas relevantes

1. Medimos por sala promediada, no en una sonda localizada a `0.9 m`.
2. **[CORREGIDO 2026-08-22, sesion 23; REENCUADRADO sesion 26]** `HCN` **si
   existe** y esta instrumentado, asi que la brecha no es su ausencia. Pero
   tampoco es, sin mas, "crecimiento del incendio demasiado rapido". La corrida
   congelada da flashover de cocina a `495.3 s` frente a `894 +/- 30 s`
   publicados (rango por ensayo `846-948 s`), lo que situa el valor unos **13
   sigma muestrales** por debajo de la media y unos `351 s` por debajo del ensayo
   mas rapido observado. **Antes de atribuirlo al crecimiento hay tres problemas
   de equivalencia sin resolver:**
   - **Volumen de control.** El evento publicado es el flashover del
     compartimento **abierto combinado cocina-salon** (unas `5.4x` el dormitorio
     en volumen, p.4 §3), alcanzado **solo tras propagarse desde la encimera** al
     salon. Nuestro caso enciende `Living_Dining` (R3) directamente con
     `fire_spread_enabled=false`, sin etapa de propagacion. Si son volumenes de
     control distintos, `495.3 s` puede ser fisicamente correcto y simplemente
     **no comparable** con `894 s`. El articulo da solo la **razon** `5.4x`: los
     volumenes absolutos **no se publican** y la frontera del compartimento nunca
     se define, asi que la razon no es reconstruible.
   - **Criterio.** Nuestro caso de cocina mide `temp_upper_c >= 600 C`, mientras
     que el articulo usa `T(0.9 m) > 600 C`. La capa superior esta mas caliente
     que el nivel de `0.9 m`, asi que **ese criterio cruza antes por
     construccion**. El caso hermano de dormitorio **ya usa** el observable
     correcto `temp_at_0_9m_c`.
   - **Origen del reloj.** En cocina `t = 0` es la **autoignicion del aceite**
     (p.4 §2.3), no el encendido del quemador de propano de `4 kW`; todo el
     precalentamiento del aceite queda fuera del reloj publicado.

   Ademas, los fuegos de cocina publicados fueron **acelerados a proposito** con
   un rollo de papel de cocina, bolsas de patatas y vasos de papel/plastico junto
   a la sarten (p.2 §2.1): `894 s` es ya una realizacion **rapida**, lo que hace
   `495 s` **mas** dificil de reconciliar, no menos.

   **`894 s` no debe usarse como objetivo de calibracion hasta resolver la
   equivalencia.** El rediseno del caso de cocina sigue **NO autorizado**.
3. Falta retardo de linea de muestreo (`16-23 s`) y postproceso de sonda.
4. Nuestro criterio de `flashover` no es el del paper:
   - paper: `T(0.9 m) > 600 C`
   - Simufire: umbral interno por `temp_upper_c` y descenso de capa.
5. La mezcla vertical/local en pasillos sigue siendo aproximada por zonas.

**Anadidas en la sesion 26, contra la fuente primaria:**

6. **El `fed` de SimuFire no es el FED del articulo.** El publicado es dosis
   **asfixiante** de Purser sobre `O2/CO2/CO/HCN`, **sin termino termico**.
   SimuFire acumula `fed = fed_co + fed_hcn + fed_hypoxia + fed_heat`. En la
   corrida congelada, pasillo lejano de cocina (R2):
   `0.0971317 + 0.0121828 + 0.1059437 + 0.0215422 = 0.2368004`, de modo que el
   valor **equivalente al articulo** es `0.2152582` y el termino termico es el
   **9.10 %** del total de SimuFire. Quitar el termino que el articulo no tiene
   **aleja** el pasillo del umbral `0.3` (del `78.9 %` al `71.8 %`), no lo
   acerca: la brecha de magnitud del peligro es **peor** de lo registrado, no
   mejor. En el caso de dormitorio `fed_heat` de R2 es exactamente `0.0`, asi que
   el desajuste solo muerde en cocina.
7. **Base seca frente a base humeda.** Las concentraciones publicadas son en base
   seca (humedad eliminada y **no cuantificada**); SimuFire no distingue seco de
   humedo en ningun punto. Sesgo sistematico sin cuantificar en **todos** los
   contratos de especies.
8. **No hay observable de tamano de fuego.** El articulo **no publica** tasa de
   liberacion de calor, perdida de masa, calorimetria ni series de temperatura en
   el punto de muestreo. El tiempo de flashover y las concentraciones son los
   **unicos** observables de validacion; no hay forma de comprobar si una curva
   de gases correcta procede de un fuego correcto. Tampoco hay **datos de altura
   de capa**, asi que el comportamiento de la interfaz en la sonda (nunca por
   debajo de `1.200 m` en la corrida congelada) no es contrastable.
9. **El experimento 18 es un outlier que si entra en las medias publicadas.** Sus
   ventanas de salon fallaron a `11.5 min`, **antes** de su flashover a
   `15.8 min` — el unico ensayo de cocina con ese orden —, invierte el orden de
   especies (`HCN 3.1 min` frente a `O2 6.3 min`) y saturo el sensor de CO. Aun
   asi contribuye a las medias de flashover, fallo de ventilacion e IDLH que
   usamos como objetivos; la media de fallo de ventilacion `15.2 +/- 1.8 min`
   esta contaminada por el.
10. **El sensor de CO se satura.** En los experimentos 11, 12 y 18 —la mitad del
    conjunto de cocina— el CO alcanzo su limite superior de `5 vol%`, por lo que
    el maximo de cocina se publica solo como **"mayor que"** `4.83 +/- 0.46 vol%`.
    Toda cifra de CO de cocina de este articulo es una **cota inferior**.
11. **El orden flashover-respuesta del dormitorio no es utilizable.** El desfase
    publicado es `+0.2 min = 12 s` despues del flashover, **menor** que el
    retardo de `16-23 s` cuyo tratamiento no se declara. No debe convertirse en
    criterio de aceptacion. El de cocina (`-8.2 min`, respuesta **antes** del
    flashover) **si** es robusto a cualquier tratamiento plausible del retardo.

## Siguiente paso recomendado

*(Lista historica, conservada y anotada en la sesion 26. Nada de esto esta
autorizado todavia: la sonda a `0.9 m` esta en **GO solo para diseno**, el
rediseno del caso de cocina sigue en **NO-GO**, y HVAC esta **diferido**.)*

1. Crear un caso nuevo de validacion empirica inspirado en este paper:
   - `ghanekar_bedroom_hallway_0_9m`
   - `ghanekar_kitchen_hallway_0_9m`
2. Anadir sonda de gases a altura fija:
   - `O2`
   - `CO`
   - despues `CO2` y `HCN`
3. Implementar postproceso de tenabilidad:
   - umbrales `IDLH`
   - `FED`
4. Ajustar primero ventilacion y transporte al pasillo antes de recalibrar yields toxicos.

**Condiciones que la sesion 26 anade a esa lista, ya no negociables:**

- El punto 2 **no basta por si solo** para el contrato de O2: en la corrida
  congelada la interfaz nunca baja de `1.200 m`, asi que una sonda a `0.9 m`
  devuelve la zona **inferior** durante toda la corrida, y la sesion 22 midio que
  eso falla **peor** (`290 s`) que el observable bulk actual (`232.5 s`). El
  defecto dominante es la **definicion**, no la altura.
- El punto 2 debe implementar el **estimador de ultima interseccion con el
  baseline**, y **no** un umbral inventado en `vol%`.
- El punto 3 debe usar FED **asfixiante** (sin termino termico) para ser
  comparable con el articulo.
- El punto 4 **no puede apoyarse en las areas de ventilacion del articulo tal
  como estan impresas**: son internamente incoherentes (ver "Erratas e
  inconsistencias").
- Cualquier diseno debe **declarar el marco temporal** (analizador o laboratorio)
  y arrastrar los `16-23 s` como sistematico declarado, porque la fuente no lo
  resuelve.
- Antes de tocar el caso de cocina hay que **resolver la equivalencia de volumen
  de control y de criterio**, y conviene obtener los informes tecnicos de UL FSRI
  que el propio articulo cita como descripcion completa del metodo y del
  combustible: refs [25] y [26], `doi:10.54206/102376/DPTN2682` (Parte I,
  dormitorio) y `doi:10.54206/102376/ZKXW6893` (Parte II, cocina y salon).
- Comprobacion externa util que ofrece el articulo (p.5 §3.1, ref [34], Forrest
  et al.): en una vivienda de dos plantas y **a la misma altura de `0.9 m`**, CO y
  HCN suben **1-2 min despues** del cambio de O2. Es el orden de especies que un
  simulador correcto deberia reproducir.

## Decision de producto / validacion

Hasta tener esos casos, los `PASS` actuales deben leerse como:
- "coincide con checks obligatorios internos y referencias CFAST/Ghanekar seleccionadas"

y no como:
- "coincide con evidencia experimental residencial a escala real".
