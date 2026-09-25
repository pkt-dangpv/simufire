# Auditoría FDS — casa simple, 24 de septiembre de 2026

> **Pregunta:** ¿cómo se comporta SimuFire hoy frente al caso FDS de la casa
> simple, y qué parte de esa comparación es realmente equivalente?
>
> **Base:** [matriz G0/G2](../planning/MATRIZ_G0_G2_AMBITO_EVIDENCIA.md) ·
> [auditoría de crashes headless](GODOT_471_HEADLESS_CRASH_AUDIT.md) ·
> informe histórico `external/fds/SIMUFIRE_SIMPLE_HOUSE_FDS_COMPARISON.md`
>
> **Nada de `external/fds/` se ha sobrescrito.** Las cinco salidas archivadas se
> comprobaron por SHA-256 antes y después de ejecutar; `sha256sum -c` da OK en
> las cinco. Las corridas nuevas se escribieron en carpetas temporales aisladas
> porque `tools/run_scenario_headless.gd` redirige los `log_file_path` del caso
> al directorio de salida.
>
> **Esto no es una validación física.** FDS también es un modelo. Coincidir con
> él no demuestra que SimuFire acierte, y separarse de él no demuestra que se
> equivoque: demuestra que dos modelos con entradas distintas dan resultados
> distintos.

---

## 1. Procedencia del caso FDS

| dato | valor |
|---|---|
| Entrada | `external/fds/simufire_simple_house_default.fds` |
| Versión FDS | `FDS-6.10.1-0-g12efa16-release` (`_git.txt` y cabecera del `.out` coinciden) |
| Fecha de la corrida | **7 de mayo de 2026, 08:28:34** (cabecera del `.out`) |
| Malla | 50×35×12 = 21 000 celdas, 10,0 × 7,0 × 2,4 m, celda ≈ 0,20 m |
| Duración | `T_END = 260 s`; el `_hrr.csv` y el `_devc.csv` traen 261 filas, t = 0…260 s |
| Título / CHID | `simufire_simple_house_default`, coincide en `.fds`, `.out`, `.smv` y CSV |

Las salidas archivadas **sí corresponden** a esa entrada: mismo CHID, misma
duración, mismo intervalo de volcado (`DT_HRR = DT_DEVC = 1 s`) y 261 muestras
en ambos CSV.

Los dos casos SimuFire (`sim/validation/cases/fds_simple_house_default.json` y
`…_calibrated.json`) declaran `"template": "simple_house"`, `duration_s = 260`,
`ignite_on_start`, y se diferencian **solo** en `engine_overrides`: el
`calibrated` retira `fire_max_hrr_kw` y `fire_o2_independent`, sube los umbrales
de extinción (O₂ límite 8,5 % → 13,5 %) y activa el intercambio térmico
interior. Son el **mismo escenario con distinta parametrización del motor**, no
dos escenarios.

---

## 2. Tabla de equivalencia — qué se puede comparar y qué no

| variable | FDS | SimuFire | veredicto |
|---|---|---|---|
| **Geometría de salas** | 6 rectángulos, 2,4 m, idénticos al template | mismos rectángulos | **comparable** |
| **Puertas interiores** | 5 huecos de 0,7–0,9 m hasta 2,05 m de alto | 5 puertas de 0,7–0,9 m × 2,0 m, `open_fraction 1.0` | **comparable** |
| **Aberturas exteriores** | **ninguna**: el `.fds` no tiene ni un `&VENT`, el dominio es hermético | puerta y 5 ventanas exteriores con `open_fraction 0.0` | **comparable en intención**, pero ver §3 |
| **Fuego** | **prescrito**: PROPANO, `HRRPUA 3000`, rampa t² α = 0,047 kW/s², tope 3000 kW | **fuego de objetos**: 7 muebles con sus propias curvas, ignición y propagación | **no comparable**: son dos fuentes distintas |
| **Foco** | superficie fija de 1 × 1 m en (1,0–2,0 · 0,8–1,8 · 0–0,1) del Salón | objeto `salon_sofa` en el Salón | **comparable solo en tendencia** (misma sala, distinta geometría de fuente) |
| **Potencia máxima** | rampa hasta 3000 kW; lo que sale depende del O₂ | `fire_max_hrr_kw = 1100` en el caso `default`; sin tope en `calibrated` | **no comparable** |
| **T capa alta / baja** | sonda puntual a z = 2,10 m y z = 0,60 m | media de capa alta y de capa baja | **comparable solo en tendencia** |
| **O₂, CO, CO₂** | sonda puntual a **z = 1,60 m**, fracción volumétrica | media de sala (`o2`, `co_ppm`, `co2_ppm`) o media de capa | **comparable solo en tendencia**, y ver §2.1 |
| **Visibilidad** | `QUANTITY='VISIBILITY'` a 1,60 m, a partir de hollín local | `visibility_m` derivada del humo de **toda la sala** | **no comparable** en valor; el orden de llegada sí es indicativo |
| **Rendimiento de CO** | `CO_YIELD 0.02` kg/kg ÷ HoC 20 000 kJ/kg = **0,0010 kg/MJ** | 0,00025–0,0006 kg/MJ por objeto, × `fire_co_low_quality_yield_multiplier = 8.5` cuando hay mala combustión | **no comparable** |
| **Rendimiento de hollín/humo** | `SOOT_YIELD 0.08` = **0,0040 kg/MJ** | 0,008–0,018 kg/MJ por objeto | **no comparable** (SimuFire 2–4,5× más) |
| **Combustible** | propano, HoC 20 000 kJ/kg | tapizado, madera, textiles, plásticos | **no comparable** |
| **FED** | **no existe**: el `.fds` no declara ningún dispositivo FED | ISO 13571 completo | **no comparable: no hay referencia** |
| **Ventilación mecánica** | ninguna | `hvac_mode: "none"` | **comparable** |
| **Sobrepresión** | `ZONE_1` del `_hrr.csv` | `overpressure_pa` | **comparable en principio**, y el resultado es demoledor (§4.6) |

### 2.1 El problema de la altura de medida, medido

La sonda de especies de FDS está a **1,60 m**. En SimuFire esa cota cae unas
veces en la capa alta y otras en la baja, y cambia durante la corrida:

| sala | t=60 s | t=120 s | t=180 s | t=260 s |
|---|---|---|---|---|
| Salón | baja (interfaz 2,00 m) | baja (2,12) | **alta** (1,34) | **alta** (0,70) |
| Pasillo | baja (2,40) | baja (2,02) | baja (2,01) | **alta** (1,43) |
| Dormitorio1 | baja (2,40) | baja (2,40) | baja (1,99) | baja (1,70) |
| Dormitorio2 | baja (2,40) | baja (2,40) | baja (1,99) | **alta** (1,40) |
| Cocina | baja (2,40) | baja (2,40) | baja (2,13) | baja (1,91) |
| Baño | baja (2,40) | baja (2,40) | baja (1,99) | **alta** (1,42) |

Comparar el valor puntual de FDS a 1,60 m contra una media de sala de SimuFire
mezcla dos capas cuya diferencia interna es enorme: en el Salón a t = 260 s
SimuFire tiene O₂ al **0,09 %** arriba y al **20,90 %** abajo. Cualquier cifra
de error de especies que salga de esa comparación mide, sobre todo, esa
ambigüedad. **Las cifras de §4 se dan como tendencia, no como error de motor.**

---

## 3. El hallazgo que condiciona todo lo demás: el caso FDS se asfixia

El `.fds` no declara ni un `&VENT`, así que las seis caras del dominio son
paredes sólidas: **el caso es un recinto completamente hermético**. Con un fuego
prescrito que pide 3000 kW dentro de 168 m³, eso tiene dos consecuencias
medidas en el propio archivo:

1. **FDS no entrega la rampa prescrita.** `MLR_PROPANE` llega a 0,150 kg/s
   —exactamente los 3000 kW pedidos— pero el `HRR` liberado hace **pico en
   939,7 kW a t = 168 s** y cae a **183,7 kW en t = 260 s**. El resto es
   combustible sin quemar: el modelo de extinción de FDS corta la combustión por
   falta de oxígeno.
2. **La presión llega a +44 517 Pa** (`ZONE_1`), 0,44 bar sobre la ambiente. Una
   vivienda real pierde el acristalamiento muy por debajo de eso.

| t (s) | rampa prescrita (kW) | FDS entregado (kW) | SF default (kW) | SF calibrated (kW) |
|---:|---:|---:|---:|---:|
| 30 | 42 | 41 | 22 | 22 |
| 60 | 169 | 167 | 122 | 122 |
| 90 | 381 | 381 | 326 | 326 |
| 120 | 677 | 647 | 646 | 635 |
| 150 | 1058 | 871 | 1031 | 1070 |
| 180 | 1523 | **679** | 1526 | 1548 |
| 210 | 2073 | **462** | 2126 | 2132 |
| 240 | 2707 | **280** | 2808 | 2829 |
| 260 | 3000 | **184** | 3276 | 3300 |

Hasta ~120 s los tres coinciden dentro del 5 %. A partir de ahí **la divergencia
no mide precisión: mide que un modelo se apaga por falta de aire y el otro no.**

**Conclusión de método:** este caso FDS sirve como referencia para los primeros
~120 s. Después describe un experimento de asfixia en caja sellada, no un
incendio residencial. Ningún porcentaje de error calculado sobre el tramo
120–260 s puede presentarse como defecto demostrado del motor de SimuFire.

---

## 4. Resultados cuantitativos actuales

Corridas de hoy con el código actual, una cada vez, con el lanzador seguro,
salidas en carpetas temporales. Sin procesos residuales, sin fallos nativos.

### 4.1 Temperatura de capa alta (pico / final)

| sala | FDS | SF default | SF calibrated | lectura |
|---|---|---|---|---|
| Salón | 335 / 116 °C | 568 / 490 °C | 621 / 521 °C | SimuFire **+70 a +85 %** en pico y no enfría: FDS baja porque se apaga |
| Pasillo | 236 / 141 °C | 298 / 223 °C | 303 / 212 °C | mismo orden; SimuFire **+26 %** en pico |
| Dormitorio1 | 127 / 105 °C | 90 / 90 °C | 75 / 75 °C | SimuFire **−29 %** (default), **−41 %** (calibrated) |
| Dormitorio2 | 125 / 111 °C | 89 / 89 °C | 75 / 75 °C | igual |
| Cocina | 125 / 109 °C | 92 / 92 °C | 75 / 75 °C | igual |
| Baño | 121 / 95 °C | 88 / 88 °C | 73 / 73 °C | igual |

**Dirección clara y consistente:** SimuFire concentra demasiado calor en la sala
de origen y lleva demasiado poco a las salas de segundo salto. El `calibrated`
empeora las salas remotas respecto al `default` en temperatura final.

### 4.2 Tiempos de llegada

| sala | criterio | FDS | SF default | SF calibrated |
|---|---|---:|---:|---:|
| Salón | T alta > 60 °C | 53 s | 45 s | 46 s |
| Pasillo | T alta > 60 °C | 71 s | **121 s** | 86 s |
| Dormitorio1 | T alta > 60 °C | 102 s | **224 s** | **217 s** |
| Dormitorio2 | T alta > 60 °C | 104 s | **227 s** | 198 s |
| Cocina | T alta > 60 °C | 110 s | **231 s** | **242 s** |
| Baño | T alta > 60 °C | 106 s | **228 s** | 205 s |
| Salón | visibilidad < 3 m | 45 s | 20 s | 20 s |
| Pasillo | visibilidad < 3 m | 64 s | 51 s | 51 s |
| Dormitorio1 | visibilidad < 3 m | 89 s | 98 s | 84 s |
| Cocina | visibilidad < 3 m | 94 s | 103 s | 89 s |
| Salón | O₂ < 15 % | 114 s | 161 s | 152 s |
| Pasillo | O₂ < 15 % | 134 s | **246 s** | **249 s** |
| Dormitorio1 | O₂ < 15 % | 170 s | **nunca** | **nunca** |
| Cocina | O₂ < 15 % | 183 s | **nunca** | **nunca** |

**El humo llega a tiempo; el calor y el oxígeno no.** La llegada de humo a las
salas remotas está dentro de ±10 s de FDS —eso es nuevo, ver §5—, pero el calor
tarda **el doble** y el O₂ de las salas remotas nunca baja de 15 %. Los dos
transportes están desacoplados del de humo.

### 4.3 Oxígeno (mínimo por sala)

| sala | FDS | SF default | SF calibrated |
|---|---:|---:|---:|
| Salón | 9,79 % | **0,37 %** | **0,27 %** |
| Pasillo | 10,38 % | 14,00 % | 13,89 % |
| Dormitorio1 | 11,70 % | 17,78 % | 19,75 % |
| Dormitorio2 | 11,58 % | 16,95 % | 19,30 % |
| Cocina | 11,71 % | 18,36 % | 20,00 % |
| Baño | 11,54 % | 17,32 % | 19,53 % |

FDS reparte el agotamiento por toda la casa (9,8–11,7 %, un rango de 2 puntos).
SimuFire lo concentra en la sala de origen y deja el resto casi intacto (0,4 %
frente a 20 %, un rango de 20 puntos). El `calibrated` **empeora** esto: deja
las salas remotas aún más cerca del aire ambiente.

### 4.4 CO y CO₂

| sala | FDS CO máx | SF def | SF cal | FDS CO₂ (t=260) | SF def | SF cal |
|---|---:|---:|---:|---:|---:|---:|
| Salón | 0,067 % | **1,423 %** | **1,441 %** | 5,08 % | 7,29 % | 7,43 % |
| Pasillo | 0,063 % | **1,425 %** | **1,438 %** | 4,77 % | 7,31 % | 7,42 % |
| Dormitorio1 | 0,055 % | **1,375 %** | **1,316 %** | 4,32 % | 7,31 % | 7,42 % |
| Cocina | 0,055 % | **1,304 %** | **1,270 %** | 4,61 % | 7,17 % | 7,12 % |

El CO de SimuFire es **21–25× el de FDS**. Parte es entrada, no motor: el
rendimiento base de CO de FDS es 0,0010 kg/MJ y el de SimuFire 0,00025–0,0006
kg/MJ, pero el caso multiplica por **8,5** cuando la combustión es de baja
calidad, y SimuFire pasa casi toda la segunda mitad en ese régimen mientras FDS
ya se ha apagado. **No es un error medido del motor; es un factor de
calibración actuando sobre un fuego que no se extingue.**

Nótese además que a t = 260 s el CO de SimuFire es **prácticamente igual en las
seis salas** (1,30–1,43 %) mientras el O₂ va de 0,4 % a 20 %. Especies y oxígeno
siguen sin estar acoplados, que era ya el diagnóstico de mayo.

### 4.5 FED — no hay nada con lo que comparar

El `.fds` no declara ningún dispositivo FED. Los valores de SimuFire se dan solo
como registro: Salón 82,34 (default) y 76,50 (calibrated); Pasillo 1,49 / 1,22;
resto 0,48–1,18. **Ninguno está contrastado contra FDS ni contra ensayo.**

### 4.6 Sobrepresión — dos órdenes de magnitud

| t (s) | FDS `ZONE_1` | SF default | SF calibrated |
|---:|---:|---:|---:|
| 60 | 6 038 Pa | 1,1 Pa | 1,1 Pa |
| 120 | 28 066 Pa | 314,1 Pa | 308,7 Pa |
| 180 | 44 000 Pa | 5,2 Pa | 4,6 Pa |
| 260 | 36 854 Pa | 9,7 Pa | 9,6 Pa |

Los dos modelos sellados difieren en **2–4 órdenes de magnitud**, y SimuFire
además tiene un pico en 120 s y luego se desinfla. Ninguna de las dos curvas es
creíble como vivienda: FDS porque 0,44 bar rompería el edificio, SimuFire porque
no sostiene la presión que su propio balance de masa implicaría. Esto conecta
directamente con el NO-GO histórico de F2.1 sobre la magnitud física de la
sobrepresión.

### 4.7 La causa interna: la capa baja no se agota

Es el hallazgo más importante, y **no depende de que FDS tenga razón**. En el
Salón del caso `default`:

| t (s) | HRR (kW) | O₂ sala | O₂ capa alta | O₂ capa baja | `o2_hrr_factor` | modo |
|---:|---:|---:|---:|---:|---:|---|
| 60 | 122 | 0,2065 | 0,1934 | 0,2088 | 1,000 | `plume_lower` |
| 180 | 1 526 | 0,1230 | **0,0008** | 0,1887 | 1,000 | `plume_lower` |
| 210 | 2 126 | 0,0758 | 0,0008 | 0,1963 | 1,000 | `plume_lower` |
| 240 | 2 808 | 0,0250 | 0,0009 | **0,2090** | 1,000 | `plume_lower` |
| 260 | 3 276 | 0,0037 | 0,0009 | **0,2090** | 1,000 | `plume_lower` |

El fuego toma su aire de la **capa baja** (`fire_o2_mode_used = plume_lower`), y
esa capa **no se agota**: baja a 0,1887 en t = 180 s y luego **vuelve a subir
hasta 0,2090**, el valor inicial exacto, mientras la capa alta está en 0,08 % y
la sala entera en 0,37 %. Con `o2_hrr_factor = 1,000` durante toda la corrida,
el fuego nunca se entera de que le falta oxígeno y sigue la curva de crecimiento
hasta 3276 kW. Los umbrales de extinción del caso —O₂ límite 8,5 %, suelo
caliente 6,8 %— **nunca llegan a evaluarse contra una entrada que baje**.

> **Corregido el 24-09-2026 por el diagnóstico de O₂.** Esta sección decía que
> la capa baja «se comporta como un depósito infinito de aire». **Era una
> hipótesis y el diagnóstico la desmiente.** La capa baja no tiene capacidad
> infinita: contiene 3,49 kg de O₂ a t = 260 s, **14 segundos** de autonomía
> frente a una demanda de 0,249 kg/s. Lo que ocurre es lo contrario de un
> depósito que se vacía sin fondo: **nadie extrae de ella.** El sumidero de
> combustión se carga a `room.o2` mientras el limitador lee `room.o2_lower`.
> El balance global tampoco se conserva: hay un **residual de +6,15 kg**
> (26 % de la demanda). Los tres defectos medidos, los controles que los
> separan y la causa demostrada están en
> [el diagnóstico de O₂](DIAGNOSTICO_O2_CASA_SIMPLE_2026-09-24.md).

---

## 5. Contraste con el informe histórico (2026-05-04)

### 5.1 El informe no es reproducible con lo que hay en el repositorio

| afirmación histórica | comprobación de hoy |
|---|---|
| FDS: pico 1015,9 kW a 167 s, final 5,2 kW | **No reproducible.** El `_hrr.csv` archivado da **939,7 kW a 168 s** y final **183,7 kW**. Ninguna columna del fichero (`HRR`, `HRR_OX`, `Q_TOTAL`, `Q_CONV`) da 1015,9 ni 5,2 |
| SimuFire default: pico 720,9 kW a 168 s, final 46,2 kW | **No reproducible.** El CSV archivado `…_default_simufire.csv` da pico **4028,0 kW a 203 s** y final **281,6 kW** |
| SimuFire tuned: pico 779,1 kW a 161 s, final 39,6 kW | **No reproducible.** El archivado da **896,5 kW a 147 s** y final **12,4 kW** |
| Salón default: pico 882 °C, final 339 °C | archivado: **815 / 692 °C** |

**La causa está en las fechas.** El informe lleva fecha **4 de mayo de 2026** y
la corrida FDS archivada es del **7 de mayo de 2026**: el informe describe una
corrida FDS anterior que ya no está en el repositorio. Los CSV de SimuFire
archivados han sido además reescritos por corridas posteriores, porque los dos
casos declaran `csv_log_file_path` **dentro de `external/fds/`**. Cualquier
ejecución por una ruta que respete ese campo los sobrescribe en silencio.

**Consecuencia:** el informe de mayo debe leerse como registro histórico, no
como referencia verificable. Sus cifras no se pueden auditar hoy.

### 5.2 Qué diagnósticos siguen vigentes

| diagnóstico de mayo | hoy |
|---|---|
| «el tiempo de crecimiento coincide bastante bien» | **vigente** hasta ~120 s (dentro del 5 %) |
| «el Salón acumula demasiada energía en la capa superior» | **vigente y peor**: 568 °C frente a 335 °C de FDS |
| «el calor no se transporta de Pasillo a las salas remotas» | **vigente**: llegada a 60 °C al doble de tiempo |
| «O₂ y CO₂ no están acoplados como en FDS» | **vigente**, con la causa ahora identificada (§4.7) |
| «SimuFire mantiene O₂ demasiado alto fuera del Salón» | **vigente pero mejorado**: de 20,5–20,7 % a 16,9–18,4 % |
| «la llegada de humo a salas remotas sigue tardía» | **YA NO**. En mayo el humo llegaba a 216–221 s; hoy la visibilidad cae por debajo de 3 m a 95–103 s, contra 89–94 s de FDS |
| «SimuFire queda bajo en potencia pico» | **INVERTIDO**. Hoy SimuFire supera la rampa prescrita (3276 kW frente a 3000 kW pedidos) y no decae |

**Cambio más importante desde mayo:** el transporte de humo se ha arreglado y la
extinción por falta de oxígeno se ha roto. En mayo el HRR de SimuFire decaía a
46 kW al final; hoy termina en 3276 kW, su máximo.

> La prueba de identidad byte a byte entre dos corridas de SimuFire de la fase
> anterior **no es una comparación con FDS** y no se usa aquí como evidencia de
> nada más que de que el arreglo de D-2 no tocó este caso.

---

## 6. Límites de la evidencia

1. **FDS es un modelo.** Coincidir con él no valida física.
2. **El caso está sellado**, así que solo los primeros ~120 s describen algo
   parecido a un incendio residencial ventilado.
3. **El fuego no es el mismo**: prescrito t² de propano frente a fuego de
   objetos. Las diferencias de HRR, CO y humo son en buena parte de entrada.
4. **Las sondas no miden lo mismo**: punto a 1,60 m frente a medias de capa, con
   la cota cambiando de capa a mitad de corrida (§2.1).
5. **No hay referencia de FED ni de sobrepresión validada**, solo dos modelos
   discrepando.
6. **Una sola corrida FDS**, sin estudio de malla ni repeticiones: 0,20 m de
   celda es grueso para un penacho de 3 MW.
7. **El informe histórico no es auditable** (§5.1).

---

## 7. Conclusión

### Qué observable puede apoyar el ámbito de publicación

**Solo uno, y con condiciones:** el **tiempo de llegada del humo** a las salas de
la vivienda. Hoy cae dentro de ±10 s de FDS en las cuatro salas remotas y
adelantado en Salón y Pasillo, con un criterio homogéneo (visibilidad < 3 m).
Es el observable que un jugador percibe y el único donde SimuFire y FDS se
mantienen juntos durante toda la corrida.

**Pero coincidir en ese tiempo no es una validación cuantitativa.** Es un
acuerdo en **un umbral, en un instante, entre dos definiciones distintas de
visibilidad** —punto a 1,60 m frente a humo de toda la sala (§2)—, en seis
salas de un solo caso, sin repeticiones ni estudio de malla. Sostiene el ámbito
en el sentido débil de «no hay evidencia en contra»; no acredita exactitud.

**No lo apoyan, en su estado actual:** temperatura de salas remotas (−30 a
−40 %), oxígeno fuera de la sala de origen (nunca baja de 15 %), CO (21–25×),
sobrepresión (2–4 órdenes de magnitud) y FED (sin referencia alguna).

### Gaps prioritarios

1. **La capa baja de la sala en llamas no se agota** (§4.7). Es la causa raíz de
   que el fuego no se extinga, de que el Salón se sobrecaliente y de que el CO
   se dispare. Bloquea cualquier afirmación sobre incendios en recintos poco
   ventilados. **Máxima prioridad.**
2. **Transporte de calor de segundo salto**: el humo llega a tiempo y el calor
   tarda el doble. Los dos transportes deberían estar acoplados.
3. **Mezcla de O₂ entre estancias**: FDS reparte el agotamiento en 2 puntos
   porcentuales, SimuFire en 20.
4. **Sobrepresión**: sigue sin magnitud física creíble, coherente con el NO-GO
   de F2.1.

### Qué ensayo real haría falta

Ninguno de estos gaps se cierra con más FDS. Haría falta un **ensayo de
compartimento residencial instrumentado**, del tipo NIST/NFPA de una o dos
habitaciones con pasillo, que registre a la vez:

- HRR por calorimetría de consumo de oxígeno en el conducto de extracción;
- termopares en árbol vertical (al menos 6 cotas) en la sala de origen **y** en
  cada sala de segundo salto, que es donde SimuFire falla;
- O₂, CO y CO₂ a cota de respiración **y** en la capa alta, en las mismas salas,
  para poder comparar sin la ambigüedad de §2.1;
- presión diferencial en el recinto, para la familia de sobrepresión;
- y, para el único observable que hoy sostiene el ámbito, **medida óptica de
  obscuración** con la que anclar la visibilidad, en vez de derivarla del humo
  de toda la sala.

Sin eso, la comparación FDS seguirá diciendo únicamente en qué se parecen dos
modelos.

---

## 8. Archivos tocados por esta auditoría

| fichero | qué |
|---|---|
| `docs/validation/AUDITORIA_FDS_CASA_SIMPLE_2026-09-24.md` | este informe (nuevo) |
| `docs/planning/MATRIZ_G0_G2_AMBITO_EVIDENCIA.md` | enlace a este informe |

**Nada más.** No se ha cambiado física, parámetros, escenarios, casos FDS,
baselines, tolerancias, `reference_checks.json` ni el comparador
`external/fds/compare_simple_house_results.py`, que no hizo falta corregir
porque no interviene en estas medidas: las series se leyeron directamente de los
CSV archivados y de las corridas nuevas.

**R2-1 sigue en rojo** por los cambios pendientes de `sim/templates/` de la fase
anterior, y la suite de referencia completa **no se ha ejecutado** en esta fase.
La memoria libre osciló entre **4,61 y 4,70 GB**, por debajo del umbral
operativo de 6–8 GB.
