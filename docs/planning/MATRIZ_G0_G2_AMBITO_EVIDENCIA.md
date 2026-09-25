# Matriz G0/G2 — ámbito de la primera versión y aplicabilidad de la evidencia

> **Fecha:** 24 de septiembre de 2026 · **Estado:** propuesta para aprobación
> **Gates cubiertos:** G0 (ámbito y evidencia) y G2 (puertas, vidrio y envolvente)
> **Base:** [plan de publicación vigente](../PLAN_PUBLICACION_2026-10-30.md) ·
> matriz científica por familia en
> [§23.2 del diseño de puertas](../PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md) y
> huecos de evidencia en §23.10 del mismo documento.
>
> Esta matriz **no repite** la revisión bibliográfica: la reutiliza, comprueba su
> vigencia y la vincula a los escenarios que se publicarían. No se ha leído
> ninguna fuente nueva y no se ha cambiado ningún valor.
>
> **Evidencia de contraste añadida el 24-09-2026:**
> [auditoría FDS de la casa simple](../validation/AUDITORIA_FDS_CASA_SIMPLE_2026-09-24.md).
> De los observables de §2.4, el único que hoy sostiene el ámbito frente a FDS
> es el **tiempo de llegada del humo** (±10 s en las salas remotas). Temperatura
> de salas remotas, oxígeno fuera de la sala de origen, CO, sobrepresión y FED
> **no** lo sostienen. La auditoría identifica además la causa raíz: en recinto
> sellado la capa baja de la sala en llamas no se agota, así que el fuego nunca
> se vuelve limitado por ventilación.

---

## 1. Qué significa cada columna

- **Demostrado** — hay contraste con datos experimentales apropiados, dentro de
  un dominio declarado.
- **Provisional** — el mecanismo está implementado y es reproducible, pero su
  magnitud procede de una heurística, de una extrapolación o de una referencia
  de orden de magnitud.
- **Fuera de ámbito** — no se publica ni se anuncia.

Tres cosas que **no** cuentan como validación experimental, y que en este
documento nunca se presentan como tal:

1. una suite en verde, que demuestra regresión frente a sus propias referencias;
2. una comparación con CFAST, que es otro modelo;
3. un ajuste de un parámetro contra la salida de SimuFire.

---

## 2. G0 · Ámbito propuesto para la primera versión

### 2.1 Escenarios

Cinco de los catorce distribuidos, elegidos por cubrir rutas distintas con
solapamiento mínimo. Ninguno declara perfil experimental ni autorización.

| escenario | geometría | por qué entra |
|---|---|---|
| `compact_apartment_reference` | 5 salas, 3 aberturas exteriores, 1 planta, foco declarado | vivienda compacta con ignición automática |
| `preset_simple_house` | 6 salas, 6 exteriores, 31 objetos, 16 700 MJ | carga de mobiliario realista; preset de menú |
| `long_hallway_reference` | 6 salas en línea, 3 exteriores, foco declarado | propagación por corredor entre salas |
| `preset_two_storey_house` | 13 salas, 11 exteriores, **2 plantas** | multiplanta y hueco de escalera |
| `two_storey_reference` | 8 salas, 5 exteriores, 2 plantas, foco declarado | multiplanta con ignición y fase post-extinción |

### 2.2 Tipos de edificio y aberturas

- **Dentro:** vivienda residencial de una o dos plantas; puertas interiores,
  puertas exteriores, ventanas y huecos verticales de forjado, en sus estados
  **operativos** (abierta, cerrada, fracción de apertura, vidrio roto por el
  jugador o por el guion del escenario).
- **Fuera:** naves, locales comerciales, edificios en altura, patios de luces
  como mecanismo calibrado, y **cualquier abertura con perfil experimental**.

### 2.3 Condiciones de incendio

- **Dentro:** incendio de mobiliario residencial con curva de HRR del catálogo
  de objetos; ventilación por aberturas operadas; propagación entre salas y
  entre plantas; fase de decaimiento y post-extinción.
- **Fuera:** flashover como predicción cuantitativa, backdraft, supresión por
  agua, HVAC como mecanismo validado, y regímenes fuera del dominio de los
  casos de referencia.

### 2.4 Resultados que ve el jugador

| salida | estado | cómo se anuncia |
|---|---|---|
| Temperaturas por zona, altura de capa, HRR | **provisional** | contrastado contra CFAST en la matriz de referencia; es comparación entre modelos, no validación experimental |
| O₂, CO, CO₂, HCN por zona | **provisional** | ídem; el reparto zonal de CO no está validado (véase §4) |
| Visibilidad | **provisional** | derivada de masa de humo con coeficientes de la literatura |
| Presión y venteo | **provisional** | ruta histórica; la red autoritativa **no corre** por defecto |
| **FED total y por componente** | **provisional, orientativo** | dosis acumulada; véase §4 |
| **Índice de condiciones (ahora / peor)** | **provisional, orientativo** | índice heurístico; la presentación ya está corregida |
| Detectores y víctimas | **provisional** | consumen FED; heredan su incertidumbre |

### 2.5 Qué física corre realmente en un escenario del ámbito

**Hecho verificado, y la afirmación más importante de este documento:** los cinco
interruptores nacen `false` y las cuatro familias de G2 dependen además de
`pressure_network_solver_enabled`, que también nace `false`.

En un escenario distribuido **no corre D1, ni D2, ni D3, ni R3, ni la red de
presión autoritativa**. Corre la ruta histórica de venteo. El ámbito propuesto
describe esa ruta, no la física de G2.

---

## 3. G2 · Aplicabilidad por familia

Matriz heredada de §23.2, vinculada al ámbito y con la decisión de producto.

### D1 · Fuga fría de puerta cerrada

| campo | contenido |
|---|---|
| Observable | caudal de aire por la rendija de una puerta interior cerrada |
| Parámetro del modelo | `ela_m2` (0,0012 / 0,0021 m² a 4 Pa, `Cd` 1); exponente 0,65; reparto 0,40/0,47/0,13; 8 bandas |
| Dominio de la evidencia | ELA definida a 4 Pa; dominio de presión 50 Pa (NBSIR p. 10) |
| Incertidumbre | fuentes **en conflicto** en el exponente (0,50 puerta vs 0,6-0,7 infiltración); reparto **sin ninguna fuente** |
| Pruebas actuales | validador D1, integración en red, 221 pruebas de regresión de la línea |
| Hueco | **no existe ni una puerta de paso residencial instalada medida**; tabla ASHRAE 2001 retirada y depreciada por NIST; 21 cm² en el 0,4 % inferior del rango medido |
| **Decisión** | **Solo experimental — NO-GO de producto** |

### R3 · Fuga de envolvente / marco exterior

| campo | contenido |
|---|---|
| Observable | caudal por el marco de una ventana exterior cerrada |
| Parámetro del modelo | `leak_area_m2` 0,005 m² geométricos, `Cd` 0,61 aparte |
| Dominio de la evidencia | ventana doméstica 1,2 × 1,0 m, permeabilidad a 100 Pa |
| Incertidumbre | los 0,005 m² son **heurística del propio motor**, 1,29× la ventana más permeable medida |
| Pruebas actuales | validador R3, precedencia de área propia sobre global probada |
| Hueco | falta permeabilidad **por unidad de longitud de rendija**; el rango medido está atado a un tamaño concreto |
| **Decisión** | **Solo experimental — NO-GO de producto** |

### D2 · Deformación prescrita de puerta

| campo | contenido |
|---|---|
| Observable | ELA adicional por deformación térmica de la hoja |
| Parámetro del modelo | **ninguno**: el perfil aporta procedencia; la magnitud la escribe el escenario |
| Dominio de la evidencia | puerta cortafuegos de **acero** en horno normalizado, 16 Pa arriba / 0,2 abajo |
| Incertidumbre | la topología es transferible; las magnitudes **no** lo son a madera residencial |
| Pruebas actuales | validador D2, contrato de prescripción |
| Hueco | **no existe ley temperatura-deformación defendible** para puerta residencial |
| **Decisión** | **Solo experimental — NO-GO de producto.** Es **prescripción**: el motor no predice cuándo se deforma, y no se convertirá en predicción automática |

### D3 · Caída prescrita de vidrio

| campo | contenido |
|---|---|
| Observable | área de ventilación por pérdida de paño |
| Parámetro del modelo | geometría de paño y capas; regla de camino libre; protección de borde 0,090 m; estados 0 / 0,1 / 1 |
| Dominio de la evidencia | panel radiante ~20 kW/m², 200–500 mm, 75 ensayos (16 muestras para los estados) |
| Incertidumbre | el **100 % de desprendimiento nunca se observó**; máximo medido 90 %. Templado **contradictorio** (Peng vs Wang) |
| Pruebas actuales | validador D3, geometría multicapa, integración en red |
| Hueco | faltan ensayos **en compartimento**; decisión de contrato `CRACKED → OPEN`; resolver el templado con un tercer ensayo |
| **Decisión** | **Solo experimental — NO-GO de producto.** Es **prescripción**: el motor no predice cuándo rompe |

### Resumen G2

| familia | candidata a producto | solo experimental | excluida |
|---|---|---|---|
| D1 | — | **✔** | — |
| R3 | — | **✔** | — |
| D2 | — | **✔** | — |
| D3 | — | **✔** | — |

**Ninguna familia es candidata a producto.** Los 15 perfiles mantienen
`product_activation = false`, y ningún escenario distribuido los declara.
La vía experimental de §23.3 sigue disponible, con consentimiento explícito,
huella y revocación, y **nunca se describe como validación residencial**.

---

## 4. FED / CO y SVV dentro del ámbito

**Separación que este documento exige mantener:**

- **Presentación — CERRADA.** La interfaz distingue índice calculado ahora y
  peor histórico, dice `n/d` cuando falta el dato, y se retiraron las etiquetas
  clínicas «FED=1 incap.» y «FED=3 letal». Verificado por validador y 17
  pruebas.
- **Validación científica — ABIERTA.** No se ha cerrado.

| magnitud | ¿anunciable en el ámbito? | condición |
|---|---|---|
| FED total | **Sí, como orientativo** | etiquetado «dosis acumulada»; sin desenlace clínico |
| FED por componente | **Sí, recomendado mostrarlo** | ya está en el estado (`SimulationStateBuilder.gd:356-359`); hoy el FED es mayoritariamente térmico y no se ve |
| Índice de condiciones | **Sí, como orientativo** | con el descargo ya implementado; **nunca** como probabilidad de supervivencia |
| Etiqueta `SVV=%` del log de texto | **No** | pendiente; advertir en la documentación |
| Reparto zonal de CO | **No se anuncia** | gate técnico GO para modo ON; **sin validación física del reparto** |

**Lo que no puede afirmarse:** que FED o el índice representen una predicción
fisiológica, ni que el reparto de CO entre zonas esté contrastado.

---

## 5. Qué evidencia cambiaría cada NO-GO

Reproducido de §23.10, sin añadir ni inventar nada:

| familia | ensayo que la desbloquearía |
|---|---|
| **D1** | permeabilidad de **puertas de paso residenciales instaladas** (ASTM E283 / ISO 5925-1), por sentido, 5–100 Pa, muestra declarada; **exponente medido** en esas mismas puertas; reparto inferior/laterales/dintel **medido** |
| **R3** | permeabilidad de marco **por unidad de longitud de rendija**; retirar los 0,005 m² heurísticos en favor de un dato |
| **D2** | ley **temperatura-deformación** para puerta residencial de madera, con incertidumbre |
| **D3** | ensayos **en compartimento** que cubran el rango de una vivienda; decisión de contrato sobre `CRACKED → OPEN`; tercer ensayo que resuelva Peng vs Wang |

Ninguna se desbloquea leyendo más: hacen falta **ensayos nuevos**.

---

## 6. Orden de trabajo y criterios de aceptación

| # | tarea | criterio de aceptación |
|---|---|---|
| 1 | **Aprobar este ámbito** (§2) | el usuario confirma escenarios, salidas y exclusiones |
| 2 | **Mostrar el desglose FED por componente** | los cuatro componentes visibles; FED total sin cambio numérico; identidad byte a byte del cálculo |
| 3 | **G1 · revisar los 78 gaps por relevancia del ámbito** | cada gap clasificado como dentro o fuera del ámbito, con justificación; ninguno cerrado por recuento |
| 4 | **G3 · cerrar el diagnóstico FED/CO** | decidir el selector zonal para modo ON, o declarar la media como aproximación documentada |
| 5 | **G4 · matriz visual reproducible** | recorrido registrado sobre los 5 escenarios: editor, ejecución, vistas, HUD, gráficas, guardar/cargar |
| 6 | **G5 · exportación Windows** | `export_presets.cfg`, build fuera del repositorio, instalación y arranque en máquina limpia |
| 7 | **Retirar la etiqueta `SVV=%` del log** | el log deja de usar vocabulario del índice antiguo |

**Independientes de la evidencia científica y ya ejecutables:** las tareas 5 y 6.
No dependen de ningún gate de G2 y descubren dependencias de producto pronto.

---

## 7. Lo que necesita aprobación

1. **El ámbito de §2** — en particular los cinco escenarios y las exclusiones.
2. **Que las cuatro familias queden solo experimentales** en la primera versión.
3. **Mostrar o no el desglose FED por componente** (tarea 2).
4. **Si la primera versión se distribuye empaquetada** o se ejecuta desde el
   proyecto Godot; cambia por completo el alcance de G5.
