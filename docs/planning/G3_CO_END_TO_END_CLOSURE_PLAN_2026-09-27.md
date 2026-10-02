# G3 — Subplan de cierre del CO, combustible, transporte y exposición

Fecha: 2026-09-27. Estado: **plan, no implementación**. Responsable científico
del cierre: pendiente de asignar. No cambia interruptores, escenarios ni
física. El selector `fed_co_zonal_enabled` permanece apagado y **NO-GO** para
producto hasta superar los gates que correspondan al alcance publicado.

Avance del 27-09: G3-0 tiene cinco controles dinámicos terminados y un
defecto de atribución de CO reproducido (objeto sin arder → 2,92 veces más
CO); G3-1 tiene inventario estático de los 14 JSON y 13 pruebas focalizadas.
Avance del 28-09: G3-0 añade cuatro [controles de topología](../validation/G3_CO_TOPOLOGY_BASELINE_2026-09-28.md)
con puerta cerrada/abierta, apertura escalonada de puerta y ventana y
camino entre plantas. Los balances de sala cierran a la resolución del
CSV. Un snapshot opt-in posterior midió directamente el CO pendiente de
entrega: explica el residuo global final de los cuatro casos con error
máximo `4,6e-8 kg`. No cierra todavía el presupuesto por paso/zona ni
valida la concentración frente a un ensayo. G3-0 sigue parcial.
G3-2 tiene una primera [ficha FCD versionada](../validation/G3_NIST_FCD_FURNITURE_SUMMARY_2026-09-27.json)
de cuatro ensayos: dos sofás completos candidatos solo para aire libre,
una alfombra con cojines no aislable y una mesa bajo límite de detección.
Los resúmenes por sí solos **no** son curvas de emisión. Los cuatro CSV
crudos están [importados y auditados](../validation/G3_CO_PRODUCCION_COMBUSTIBLES_ESTANCIA_2026-09-27.md):
reproducen picos e integrales HRR; la fórmula de la guía FCD permite una
reconstrucción **provisional** de CO neto en el escape. Los totales de 29,
30 y 28 concuerdan con sus fichas dentro de la incertidumbre; 28 mezcla
alfombra y cojines, y 18 está bajo detección y con piloto activo. La
versión 2026 del procesado y el fondo elegido no están verificados, y no
hay pérdida de masa temporal para calcular `Y_CO(t)`. HCN, regímenes
subventilados y familias restantes siguen pendientes. El
[cotejo TN 2303/FCD](../validation/G3_NIST_TN2303_FCD_RECONCILIATION_2026-09-28.md)
fija que 29/30 conservaron masa y THR mientras cambió `Y_CO`; TN 2303
midió masa transitoria solo en Tests 1–24. HCN global existe en la tabla
2025, **no** en los CSV/fichas 2026: se mantiene separado y no calibrado.
Avance del 29-09 ([procesado y elegibilidad](../validation/G3_CO_FUENTES_ELEGIBILIDAD_2026-09-29.md)):
NIST no publica código ni notas de `NFRL_Report_8.7.1`; con los 48 CSV y
fichas archivados, el método de la guía reproduce la FCD 2026 en 42/43
ensayos, THR no cambia entre versiones, la masa sí en 31/35/38, y la causa
del cambio de CO sigue **sin demostrar** (integrar hasta fin de archivo
explica 10 de 13 desfases, no todos). Una matriz de 14 fuentes no encuentra
`MLR(t)` numérica y CO(t) del mismo ensayo a escala de objeto: G3-2 queda
**NO-GO para `Y_CO(t)` por objeto**. Falta la masa numérica de TN 2303
Tests 1–13/16/17/19–24, las series crudas de TN 1453 (o equivalentes en
recinto ventilado y viciado) y las exportaciones 2025 o su registro de
cambios. El único candidato de calibración es material a escala de banco
(cono FSRI), sin validez por objeto ni subventilada.
G3-3 se ha iniciado con un libro **pasivo** de combustible y CO por paso:
confirma que la silla consume 0 MJ en los 1.081 pasos del control, aunque
altere el CO de la sala. La ampliación v2 registra también CO₂/HCN, humo,
O₂ y gas zonal; CO y humo cierran sus contadores de sala por paso en el
corpus, y la silla fría altera el humo generado en −7,11 %. Aún no hay
fuente por objeto ni cierre elemental/de transporte de todas las especies.
G3-1 añade un control dinámico con cargas desiguales: estancia 3 MJ / sofá
1 MJ libera otros 1,998060 MJ **después** de agotarse el sofá; estancia
1 MJ / sofá 3 MJ se limita a 1 MJ y deja ≈2 MJ en el objeto. Confirma la
precedencia de la estancia, no la procedencia de las 23 diferencias reales.
Véase [gate G3-1](../validation/G3_FUEL_OWNERSHIP_DYNAMIC_GATE_2026-09-27.md).
La [matriz de procedencia](../validation/G3_FUEL_PROVENANCE_MATRIX_2026-09-27.md)
ubica los 23 valores: 17 literales en tres JSON de referencia y seis
reproducidos por la plantilla de dos plantas. Su **significado físico**
sigue sin declararse; ninguna fila se promociona de `legacy_unknown`.
**No** se ha clasificado aún la procedencia de las cargas ni se ha cambiado
la física. Véanse [baseline G3-0](../validation/G3_FUEL_SOURCE_DYNAMIC_BASELINE_2026-09-27.md)
y [checkpoint G3-1](../validation/G3_FUEL_SOURCE_OWNERSHIP_AUDIT_2026-09-27.md).
Avance del 29-09 ([cierre G3-1](../validation/G3_FUEL_OWNERSHIP_CLOSURE_2026-09-29.md)):
matriz individual de 23 discrepancias (`legacy_unknown`, bloqueadas) y 7
presets sin objetos (`legacy_lumped`, se mantienen); 0 migrables. Nueve
casos dinámicos demuestran energía sin dueño tras agotarse un objeto
(1,998 MJ), un objeto frío que entra en los topes de energía y HRR del
fuego (+2,996 MJ de inventario contado dos veces, HRR 168 kW, CO ×14,05),
la carga de sala que trunca al objeto (2,0 MJ sin quemar) y HRR por objeto
por encima de su máximo declarado; no hay doble conteo de HRR por paso.
Contrato de propiedad C1–C9 propuesto y fijado en pruebas. **GO** para
instrumentar G3-3 como libro pasivo; **NO-GO** para cerrarlo o migrar sin
autorizar un cambio del motor bajo interruptor OFF.
Avance posterior del 29-09 ([G3-3 y propiedad energética](../validation/G3_FUEL_LEDGER_OWNERSHIP_2026-09-29.md)),
tres decisiones separadas: **G3-3 instrumentado** (libro v3 por paso y
propietario, inerte byte a byte y con cierre numérico `1e-9 MJ`/paso en 9
casos); **propiedad energética corregida en `explicit_objects`** detrás de
`fire_explicit_object_fuel_ownership_enabled` (OFF por defecto; solo salas
sin carga de sala; 0 MJ sin dueño, sin calor sin combustible y topes por
objeto respetados; OFF idéntico en 9/9; 4/4 mutantes detectados); y **CO/FED
no validados**: C6 sigue fallando (CO ×2,92 con silla fría y mismo
combustible) porque la química no se ha tocado.
Revisión Gate A/B del 29-09: la [procedencia del informe de referencia](../validation/G3_REFERENCE_PROVENANCE_PORTABILITY_2026-09-29.md)
se normaliza a LF canónico y rutas relativas tras probar las 38 diferencias
CRLF/LF archivo por archivo; es un cambio de metadatos, no de checks. El
[presupuesto energético](../validation/G3_ENERGY_BUDGET_DIAGNOSIS_2026-09-29.md)
localiza en los nueve controles todo el desfase `consumido − calor sólido`
en el suavizado del HRR, con generación de pool cero. El modo ON deja
0,933784 MJ de pirólisis del sofá sin destino modelado; **NO-GO para
declarar cerrada la física energética o activar el modo en producto**.
Diseñar y falsar un inventario intermedio, una pérdida explícita o una
liberación distinta requiere una fase propia, antes de G3-4 química.
Revisión posterior del 29-09: los 26 fallos «nativos» de la suite global
fueron cuadros obsoletos de un `check_product` lanzado en el sandbox, que el
monitor atribuía a cada ejecución sana y mataba ([diagnóstico](../validation/G3_GODOT_NATIVE_POPUP_DIAGNOSIS_2026-09-29.md));
el lanzador se niega ahora a arrancar con un cuadro previo y la suite
global pasa una vez (3062 passed, 35 skipped, 2 xfailed). El
[diseño del destino de la energía retrasada](../validation/G3_ENERGY_DELAY_DESIGN_2026-09-29.md)
mide el origen del cociente (subida τ≈10,8 s frente a bajada τ=20 s) y
propone inventario `R` por objeto con liberación en la cola y paso al pool
al extinguirse, con pruebas F1–F7; **pendiente de aprobación, sin implementar**.

## Objetivo y definición de cierre

Poder explicar, reproducir y contrastar, en el alcance de viviendas y
combustibles que se declare para producto, esta cadena completa:

```text
inventario combustible → pérdida de masa/pirólisis y HRR → CO/CO₂/HCN/humo
→ oxidación y transporte de gas/especies → concentración por zona y altura
→ dosis FED y presentación de SVV
```

«Cerrado» no significa que todos los 38 arquetipos tengan datos medidos o
que SimuFire coincida exactamente con CFAST. Significa que **cada afirmación
de producto** tiene un rango de validez y evidencia explícitos; cada caso
distribuido tiene una fuente de combustible inequívoca; los balances y las
regresiones cierran; y los casos fuera de alcance están identificados, no
ocultos detrás de un rendimiento global. Si falta un ensayo indispensable,
la rama afectada termina como **LIMITADA/NO-GO**, nunca como validada por
suponer un número. La fecha de publicación depende de este resultado.

## Baseline y reglas para todas las fases

- Tomar checkpoint de Git, flags, escenarios, Godot y memoria antes de correr
  nada. Preservar los cambios locales ajenos. Ejecutar Godot de una sola
  tanda, bajo el monitor seguro usado por el proyecto; no iniciar la suite
  completa con memoria insuficiente ni dejar procesos residuales.
- Congelar antes de modificar física las trazas de escenarios con y sin
  muebles, estados de cada objeto, HRR, O₂, temperatura, flujos, especies por
  zona y FED. Etiquetar si cada referencia es experimento NIST, salida CFAST,
  fixture interno o escenario de producto: no son patrones intercambiables.
- Todo cambio físico nuevo va detrás de un interruptor OFF por defecto. OFF
  debe conservar salidas byte a byte; ON exige presupuesto, pruebas de casos
  límite y mutaciones válidas. Mantener los 346 required PASS y los 78 gaps
  sin reclasificarlos en silencio; aplicar R2-1 y suite global cuando se toque
  `sim/core`. Las cifras son el último baseline conocido, no una dispensa
  para no medir de nuevo.
- No fijar tolerancias empíricas después de ver el resultado candidato.
  Establecerlas en el protocolo a partir de incertidumbre experimental,
  resolución y sensibilidad; informar sesgo, dispersión y fallo por caso.

## Orden de ejecución

| Fase | Trabajo y entrega | Gate de salida |
| --- | --- | --- |
| G3-0. Mapa causal y baseline | Corpus mínimo: sala vacía, sofá solo, sofá + mueble frío, sala amueblada, agregado `legacy_lumped`, dos salas/puerta, puerta y ventana variables, y edificio de dos plantas. Trazas OFF actuales y matriz de dueños de cada término de CO. | Resultados reproducibles, rutas y unidades identificadas; ningún ajuste de física. |
| G3-1. Propiedad del combustible | Inventario de los 14 JSON distribuidos, plantillas/editor y casos de referencia. Clasificar carga de sala, objetos, acabados y contenido no dibujado, con procedencia y modo `explicit_objects`, `legacy_lumped` o `legacy_unknown`. Resolver manualmente las 23 discrepancias y los 7 presets sin objetos antes de migrarlos. Diseñar carga adicional **nombrada**, no inferida por tipo de habitación. | Un solo propietario por MJ y por kg de combustible; ningún escenario de producto ambiguo presentado como validado. Casos de referencia agregados intactos. |
| G3-2. Datos por material/objeto | Fichas versionadas con fuente y unidades para masa/energía, HRR o MLR temporal, calor efectivo, O₂, CO, CO₂, HCN, humo/hollín y condiciones de ventilación/fase. Importar curvas NIST TN 2303/FCD y TN 1453 con checksum, revisar ignitores mezclados y discrepancias entre versiones. Preparar una sala amueblada **reservada para validación externa**. | Familias/materiales del alcance publicado tienen intervalo y procedencia; campos desconocidos son explícitos. No atribuir a mesa/alfombra una medición que incluye cojines; no convertir kg/kg a kg/MJ sin calor correspondiente. |
| G3-3. Libro contable pasivo | Instrumentar sin autoridad física, por objeto y paso: masa perdida, pirólisis, energía, HRR, O₂, CO/CO₂/HCN/humo generados, oxidación y retención. Por sala/zona: entradas, salidas, inventario, proyección y clamps. Comparar fuente agregada con suma de objetos. | Cierre por paso y acumulado de combustible, elementos/especies y energía según tolerancias numéricas predeclaradas. Mueble frío no emite ni altera la química del que arde; sala vacía no crea combustible; OFF idéntico. |
| G3-4. Fuente de incendio y especies | Corregir primero el dueño de HRR/energía (`FireModel` frente a objetos) sin mezclarlo con transporte. Nueva producción por objeto activo y régimen: llama ventilada, ventilación limitada, pirólisis/latencia; separar energía liberada de masa perdida. Usar la misma asignación de combustible para CO, CO₂, HCN, humo, carbono y O₂. Mantener vía agregada explícita para validación. | Sin combustible/CO fantasma ni doble conteo. Curvas HRR, MLR, tasa y acumulado de CO contrastadas contra ensayos individuales y sala amueblada; sensibilidad y errores reportados. El modelo no se aprueba por igualar un único total final. |
| G3-5. Transporte y zonas | Solo tras cerrar la fuente, seguir gas y cada especie por penacho, puerta, huecos, ventana, HVAC, deposición de capa, chorro, oxidación y mezclas. Corregir propietarios canónicos de gas y especie, no imponer una transferencia exclusiva de CO. Contrastar dos salas, multipiso y fixture residencial con sensores a alturas conocidas. | `final − inicial = producción − oxidación + entradas − salidas` por sala y zona; cierre simultáneo de gas, CO, CO₂, O₂ y energía. Comparación temporal con varios casos CFAST **y** al menos un ensayo medido NIST, con geometría/ventilación/sensores homologados. |
| G3-6. FED/SVV y observables | Con concentración zonal validada, probar 0,9/1,5/1,8 m, interfaz móvil y sin capa; aislar CO, HCN, hipoxia, CO₂ y calor con concentraciones impuestas. Revisar `co_lower_ppm`, selector FED, doble representación de CO₂, unidades y acumulación. Separar valor actual, peor histórico, dosis y heurística SVV en UI/log/CSV. | Fórmulas reproducidas independientemente con entradas impuestas; continuidad y monotonía física donde proceda; ningún `SVV=%` presentado como probabilidad médica ni FED como garantía de supervivencia. |
| G3-7. Promoción y producto | Migrar solo escenarios cuyo inventario y familias estén respaldados; revisar visualmente objetos y contenido no dibujado. Ejecutar corpus ON/OFF, mutaciones, producto, global y referencia. Revisar documentación de límites y observables. Decidir activación por perfil, no global. | Acta GO/NO-GO por perfil con evidencia, incertidumbre y exclusiones. Si algún gate falla, flag OFF y salida etiquetada experimental/no cuantitativa. |

## Dependencias que no se pueden saltar

G3-1 y G3-2 pueden avanzar en paralelo **como tareas de documentación/datos**.
G3-3 necesita el inventario de fuentes; G3-4 necesita G3-2 y G3-3; G3-5
necesita una fuente trazable; G3-6 necesita concentraciones fiables. Antes de
promover G3-4/5, cerrar o acotar los defectos de O₂ y energía que alteren
combustión y flujos; en particular no interpretar una curva de CO como error
del rendimiento si su O₂ o su combustible no conservan masa. Un experimento
puede medir fases posteriores antes, pero no convertirlas en física canónica
fuera de orden.

## Matriz mínima de falsación

- Inventario: vacío; un combustible; dos iguales; segundo objeto frío;
  agotado; contenido adicional declarado; legacy agregado; JSON ambiguo.
- Química: mismo objeto con distinta ventilación y O₂; precalentamiento sin
  llama; pirólisis con HRR bajo; transición a flashover; fuego que decae;
  carbono/nitrógeno disponibles; CO generado frente a CO oxidado.
- Transporte: cerrado/abierto; ventana y viento; hueco vertical; HVAC OFF/ON;
  masas zonales casi nulas; cambio de interfaz; especie sin fuente; comparación
  de suma de zonas con total de recinto.
- Exposición: sensor impuesto arriba/abajo, cruce de interfaz, tiempo de
  exposición, reinicio, CO₂ dual, pérdida de visibilidad y calor aislados.
  Ninguna prueba debe tomar como oráculo otra función del mismo motor cuando
  pueda usarse una cuenta independiente.

## Resultados y decisiones que debe entregar cada fase

Cada fase termina con: checkpoint inicial/final; hipótesis y controles;
dataset/versión/checksum; ecuaciones y unidades; trazas antes/después;
presupuesto con residuo máximo y acumulado; sensibilidad; fixtures y
mutaciones; resultado OFF/ON; suites; archivos tocados; limitaciones;
decisión **GO, NO-GO o LIMITADA**. Un NO-GO es un cierre honesto de la
investigación de esa rama, pero **no** autorización de publicación de una
métrica cuantitativa de CO/FED para ella. Commit/push solo con autorización
y según el protocolo de la fase; este plan no los ejecuta.

## Fuentes y documentos de entrada

- [Auditoría de propietarios de combustible](../validation/G3_FUEL_SOURCE_OWNERSHIP_AUDIT_2026-09-27.md).
- [Producción de CO por combustible y estancia](../validation/G3_CO_PRODUCCION_COMBUSTIBLES_ESTANCIA_2026-09-27.md).
- [Procesado CO 2025/2026 y elegibilidad de fuentes G3-2](../validation/G3_CO_FUENTES_ELEGIBILIDAD_2026-09-29.md).
- [Gate de transporte CFAST/NIST](../validation/G3_CO_CFAST_NIST_TRANSPORT_GATE_2026-09-27.md).
- [Diagnóstico de FED/SVV](../validation/G3_FED_SVV_DIAGNOSTICO_2026-09-26.md).
- [Hoja de ruta general](MASTER_ROADMAP_CURRENT.md).
