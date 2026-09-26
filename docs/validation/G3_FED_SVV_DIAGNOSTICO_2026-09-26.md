# G3 — diagnóstico inicial de FED/CO y SVV (2026-09-26)

Estado: **abierto; sin cambio de física ni de interfaz en esta pasada**. Este
documento audita la coherencia interna del código y de CSV ya generados. No
valida una predicción fisiológica ni compara el motor con un ensayo humano.

## 1. Contrato observado en el código

- `ThermalSystem.step_fed()` y `compute_fed_delta_for_height()` eligen zona alta
  con `thermal_exposure_factor >= 0.5` y `upper_gas_kg > 0.1`. Debajo, CO sale
  de `compute_co_ppm()` (media de recinto); HCN, CO₂ y O₂ se toman de la zona
  baja. El selector es el mismo para el FED fijo de sala y el cálculo por
  altura, pero las concentraciones elegidas no tienen el mismo soporte zonal.
- `compute_co_lower_ppm()` existe y se exporta, pero **FED no lo usa**. Si no
  hay capa alta establecida devuelve la media. Con capa alta, calcula CO bajo
  a partir del inventario residual y lo multiplica por una heurística de
  estratificación que llega a cero cuando la zona alta ocupa al menos un
  tercio de la altura. Por ello, sustituir sin más la media por esta función
  tampoco queda justificado.
- CO₂ alto en FED usa por defecto el tracer `co2_upper`; la alternativa por
  masa `fed_co2_source_mass` sigue apagada. Bajo la capa, FED usa la masa de
  CO₂ inferior. El arreglo de acarreo integrado el 26-09 puede cambiar esa
  última entrada y `V_CO2`, sin resolver la dualidad tracer/masa.
- `room.fed` suma CO, HCN, hipoxia y calor; por tanto no equivale sin
  separación a un FED exclusivamente asfixiante. `room.svv_pct` es el mínimo
  heurístico de calor, FED acumulado y visibilidad; `svv_worst_pct` conserva
  el peor valor. No son probabilidades de supervivencia.
- `SimulationLogWriter.gd` rotula `SVV=...%` pero, cuando el estado contiene
  `svv_worst_pct` (lo incluye `SimulationStateBuilder.gd`), imprime **el peor
  histórico**, no el índice actual. Además conserva un cálculo alternativo de
  SVV para el fallback. La corrección previa de la UI no cerró este log.

## 2. Señal en informes existentes

Lectura sin modificar los CSV de `sim/validation/reports/`: filtro exploratorio
`thermal_layer_m > 1.8`, `co_ppm > 100` y
`co_lower_ppm < 0.1 * co_ppm`. Aparecen **8 471 filas en 24 CSV**. Este filtro
es una **aproximación**, no reproduce exactamente el selector de FED: el
factor de exposición térmica y `upper_gas_kg` no se infieren por completo del
CSV. Tampoco son 8 471 observaciones independientes ni evidencia experimental.

Ejemplo con muestras consecutivas de 1 s en `v4_co_remote_rooms.csv`, baño:

| t (s) | interfaz térmica (m) | CO medio (ppm) | CO bajo exportado (ppm) | FED_CO acumulado | aumento desde muestra anterior |
|---:|---:|---:|---:|---:|---:|
| 616 | 1,848 | 54 862 | 0 | 6,52471 | — |
| 617 | 1,964 | 54 783 | 0 | 6,56960 | 0,04489 |
| 618 | 1,999 | 54 705 | 0 | 6,61443 | 0,04483 |

La expresión de CO codificada, sin potenciación por CO₂, da aproximadamente
0,04486 por segundo para 54 783 ppm: coincide con el aumento de 617 s. Es una
prueba de coherencia **dentro de este motor**, no de que la concentración
respirada real sea cero o 54 783 ppm. El caso es de estrés y también muestra
CO₂ medio muy elevado; no se debe usar como caso fisiológico representativo.

La señal no se limita a ese caso: en `cfast_two_room_door_open.csv`, cocina a
520,1 s, la interfaz es 1,819 m, CO medio 343 ppm y CO bajo exportado 15 ppm.
En `cfast_two_floor_stairwell.csv`, escalera PB a 580,1 s, los valores son
1,910 m, 9 524 ppm y 0 ppm. Estas filas muestran la discrepancia de entradas;
no atribuyen por sí solas el FED final a una zona ni validan los datos CFAST.

## 3. Decisión y siguiente experimento

**NO-GO para cambiar el selector de CO o promover FED/SVV como cuantitativos.**
Hay dos incertidumbres distintas: qué concentración debe respirar una persona
por debajo de la interfaz y si `compute_co_lower_ppm()` representa esa
concentración, dado su factor heurístico. Cambiar solo el selector podría
convertir una sobreexposición en una infraexposición artificial.

Siguiente unidad de trabajo, antes de otro cambio de física:

1. Construir un fixture de dos zonas con concentraciones **impuestas** de CO,
   HCN, CO₂ y O₂, masa de capa estable y temperatura controlada. Probar a
   0,9/1,5/1,8 m, a ambos lados de la interfaz, y la misma sala sin capa alta.
   Registrar cada entrada y cada incremento de FED por especie; comparar con
   la fórmula implementada calculada independientemente.
2. Variar solo el inventario bajo de CO manteniendo constante el alto y el
   total cuando proceda. Medir el error que introduce el factor `strat` frente
   a la concentración zonal derivada directamente del inventario. No aceptar
   como referencia la salida del propio `compute_co_lower_ppm()`.
3. Separar en el informe el FED asfixiante, el térmico, el estado instantáneo
   de condiciones y el peor histórico. Revisar el log `SVV=%` como cambio de
   comunicación independiente, con identidad de los números físicos.
4. Solo después contrastar el rango de uso con datos experimentales
   comparables; no ajustar tolerancias ni informes oficiales para conseguir
   un PASS. El experimento interno puede demostrar coherencia, no realismo.

La ruta de trabajo y el gate de publicación siguen en
[MASTER_ROADMAP_CURRENT.md](../planning/MASTER_ROADMAP_CURRENT.md).

## 4. Fixture de concentraciones impuestas — 26-09

`tools/diagnose_fed_zone_selector.gd` fija una sala de 4 × 4 × 2,4 m, interfaz
termo-gaseosa a 1,6 m, 100 ppm de CO por inventario en la zona inferior y
1 000 ppm en la superior. Desactiva calor e hipoxia y deja HCN/CO₂ a cero:
el incremento restante es solo CO, sin potenciación. La ejecución con Godot
4.7.1, lanzador supervisado, terminó con salida 0, sin cuadro de error ni
procesos residuales.

| magnitud | resultado |
|---|---:|
| CO bajo impuesto por masa | 100,000000 ppm |
| CO alto impuesto por masa / exportado | 1 000,000000 / 1 000,000000 ppm |
| CO medio de sala | 343,366841 ppm |
| `compute_co_lower_ppm()` | **0,000000 ppm** |
| dosis CO de 1 s a 0,9 y 1,5 m | **0,0002342286** cada una |
| fórmula independiente con los 100 ppm impuestos abajo | 0,0000652521 |
| dosis CO de 1 s a 1,8 m / fórmula con 1 000 ppm arriba | 0,0007089151 / 0,0007089151 |

La dosis inferior calculada es **3,59 veces** la dosis de los 100 ppm impuestos
por masa. La salida `co_lower_ppm` es cero porque `strat` llega a cero con el
tercio superior ocupado, aunque el inventario bajo no es cero. Por tanto hay
dos desacuerdos internos, no uno: el selector FED usa la media bajo la capa,
y la función inferior exportada borra una concentración impuesta no nula. El
fixture demuestra incoherencia del modelo con sus propias entradas controladas;
no prueba que 100 ppm represente una exposición real.

Para corregirlo hace falta un contrato explícito de concentración respirada y
un guardarraíl que compare con el inventario zonal sin tomar `co_lower_ppm`
actual como verdad. Luego medir OFF byte a byte, el impacto sobre FED de los
escenarios y la referencia completa antes de activar nada en producto.
