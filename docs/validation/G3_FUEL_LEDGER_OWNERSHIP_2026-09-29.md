# G3-3 libro contable pasivo y propiedad energética en `explicit_objects` (2026-09-29)

Tres decisiones distintas, cada una con su evidencia:

| Decisión | Estado |
| --- | --- |
| **G3-3 instrumentado** (libro contable pasivo por paso y propietario) | **GO**: cierra numéricamente en los 9 casos y es inerte byte a byte. |
| **Propiedad energética corregida en `explicit_objects`** | **GO experimental, OFF por defecto**: `fire_explicit_object_fuel_ownership_enabled`. Sin activación en producto ni escenarios. |
| **CO/FED validados** | **NO-GO**: la química sigue sin tocar y falla C6; G3-2 sigue NO-GO para `Y_CO(t)` por objeto. |

Entrada: [cierre G3-1](G3_FUEL_OWNERSHIP_CLOSURE_2026-09-29.md) y sus
cláusulas C1–C9. Datos: [cuatro tandas](G3_FUEL_LEDGER_BATCHES_2026-09-29.json)
y [mutaciones](G3_FUEL_OWNERSHIP_MUTATIONS_2026-09-29.json). Ninguna de las 23
salas `legacy_unknown` ni de los 7 presets se ha convertido; escenarios
distribuidos, catálogo y química intactos.

## 1. Libro contable G3-3 (sin autoridad física)

`CombustionSystem.g3_fuel_ledger_enabled` (miembro, no interruptor del
motor) solo lo activa el runner headless con `--g3-fuel-ledger-v3`. Con
false no se ejecuta ninguna instrucción del libro. Cada paso y sala registra
en `g3_fuel_ledger_v3.jsonl`:

- inventario del `FireModel` antes/después, energía demandada sin escalar,
  disponible, factor de escala y consumida (debitada);
- HRR solicitado (`hrr_target_kw`), aplicado en combustión y al final del
  paso del motor; potencia máxima vigente; quemado sólido y de pool;
- generación y combustión del pool de inquemados;
- por objeto: activo/inactivo al inicio del paso, energía antes/después,
  **asignación** del reparto, HRR y tope propios, estado;
- CO, CO₂, HCN y humo generados en el paso.

El analizador puro [`analyze_g3_fuel_ledger.py`](../../scripts/simulation/analyze_g3_fuel_ledger.py)
asigna cada MJ consumido a un propietario: `object:<id>`, `room_load`
(la carga de sala declarada, **término de estancia**), `aggregate` (sala sin
objetos: el proxy) o `unowned` (sala declarada solo con objetos y ningún
objeto debitado). `discarded` es inventario de objeto borrado sin
consumo. Las especies se reparten por fracción de energía consumida: es
**contabilidad**, no química.

**Tolerancia de cierre fijada antes de tocar la física:** `1e-9 MJ` por paso
y `1e-9 MJ × pasos` acumulado; identidad de especies a `1e-12` relativo. Las
magnitudes por paso son 1e-4–1e-1 MJ en float64 (redondeo < 1e-15 MJ); el
umbral físico más pequeño del motor es 1e-6 MJ y el descarte de agotamiento
1e-3 MJ. El 1 % de las comparaciones de comportamiento no se usa aquí.
Cierres comprobados: K1 inventario del fuego por paso, K2 ningún objeto
gana inventario, K3 partición por propietario, K4 acumulados de fuego y
objetos, K5 partición de especies. **Resultado: 0 fallos** en las fases
ledger, OFF y ON de los 9 casos.

**Liberado ≠ consumido.** El HRR es un estado suavizado. El pool puede
retener una fracción de la pirólisis no quemada, pero el
[diagnóstico energético posterior](G3_ENERGY_BUDGET_DIAGNOSIS_2026-09-29.md)
demuestra que en estos nueve controles su generación fue exactamente cero:
la diferencia procede del retraso del HRR, sin inventario intermedio.
Por eso el calor liberado no se cierra contra el consumido: se informa
aparte.
«El fuego no duplica energía liberada» y «cada MJ tiene un único
propietario» son comprobaciones distintas (C1 frente a C2/O1).

## 2. Casos decisivos y comportamiento anterior

Nueve escenarios sintéticos de 90 s (misma geometría y ajustes que G3-0;
MJ como estímulo, no datos de muebles), ejecutados con el monitor seguro:
sala vacía, sofá solo, sofá con silla fría, dos objetos activos, carga de
sala mayor y menor que los objetos, objeto de potencia baja (10 kW), fuente
agregada nombrada (`contenido_agregado`) y sala solo agregada. Tandas:
`before` (motor intacto), `ledger` (libro activo), `off` y `on` (tras la
corrección), todas con exit 0, sin timeout, cuadros de error ni Godot
residual.

| Caso | Modo ON | Fase | Consumido MJ | Por objetos MJ | Sala/agregado MJ | Sin dueño MJ | Descartado MJ | Calor sólido liberado MJ | Liberado sin consumo en el paso MJ | HRR máx kW | CO kg | Humo kg |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| empty_room | aggregate | OFF | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| empty_room | aggregate | ON | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| single_object | explicit_owned | OFF | 2,999863 | 2,999014 | 0 | 0,000849 | 0,000986 | 3,405765 | 1,3496 | 87,72 | 0,00084871 | 0,051679 |
| single_object | explicit_owned | ON | 2,999013 | 2,999013 | 0 | 0 | 0 | 2,065228 | 0 | 86,80 | 0,00082702 | 0,036061 |
| sofa_plus_cold_chair | explicit_owned | OFF | 5,996351 | 3,000000 | 0 | **2,996351** | 0 | 6,137992 | 1,9522 | **168,30** | 0,01192463 | 0,073464 |
| sofa_plus_cold_chair | explicit_owned | ON | 2,999013 | 2,999013 | 0 | 0 | 0 | 2,065228 | 0 | 86,80 | 0,00241480 | 0,033497 |
| two_active_objects | explicit_owned | OFF | 5,738884 | 5,738882 | 0 | 0,000002 | 0,000963 | 5,003335 | 0,3681 | 102,59 | 0,01047424 | 0,061189 |
| two_active_objects | explicit_owned | ON | 5,698013 | 5,698013 | 0 | 0 | 0 | 4,637314 | 0 | 98,59 | 0,01022966 | 0,057261 |
| room_load_above_objects | legacy_room_load | OFF = ON | 2,999863 | 1,000000 | **1,999863** | 0 | 0 | 3,405773 | 1,3496 | 87,72 | 0,00060710 | 0,041614 |
| room_load_below_objects | legacy_room_load | OFF = ON | 1,000000 | 0,999981 | 0,000019 | 0 | 0 | 1,313928 | 0,7616 | 41,62 | 0,00022646 | 0,021173 |
| low_power_object | explicit_owned | OFF | 5,845985 | 5,845984 | 0 | 0,000002 | 0 | 5,254885 | 0,6131 | 111,93 | 0,00190839 | 0,077936 |
| low_power_object | explicit_owned | ON | 3,568255 | 3,568255 | 0 | 0 | 0 | 2,498333 | 0 | 99,45 | 0,00100068 | 0,042923 |
| named_aggregate_source | explicit_owned | OFF | 3,000000 | 2,999038 | 0 | 0,000962 | 0,000962 | 3,527176 | 1,6059 | 100,27 | 0,00078836 | 0,052876 |
| named_aggregate_source | explicit_owned | ON | 2,999003 | 2,999003 | 0 | 0 | 0 | 2,040218 | 0 | 89,12 | 0,00081698 | 0,036059 |
| room_aggregate_only | aggregate | OFF = ON | 2,999863 | 0 | 2,999863 | 0 | 0 | 3,405768 | 1,3496 | 87,72 | 0,00053081 | 0,038406 |

Antes de la corrección (motor intacto, tanda `ledger`), el libro demuestra:

- **Fuego sin propietario:** con la silla fría y sin carga de sala, el tope
  del fuego es la suma de *todos* los objetos: se consumen 2,996351 MJ que
  ningún objeto entrega (la silla conserva sus 3 MJ) y el HRR llega a
  168,30 kW. Con carga de sala 3 MJ y sofá 1 MJ, 1,999863 MJ son propiedad
  de la **carga de estancia**, no de un objeto.
- **Fugas pequeñas pero reales:** el `_sync` legacy ignora demandas
  ≤ 1e-6 MJ, que el fuego sí descuenta (0,000849 MJ sin dueño con el sofá
  solo, 108 pasos), y el agotamiento borra ≤ 1 kJ de inventario sin
  consumo (0,000986 MJ). Ambos explican la desincronía de 1,37e-4 MJ vista
  en G3-1.
- **Calor sin combustible:** el HRR suavizado libera 1,35 MJ brutos en
  pasos en los que supera la pirólisis del propio paso, y sigue liberando
  hasta 30,7 kW cuando ya no queda objeto activo. Con el sofá solo se
  liberan 3,405765 MJ para 2,999863 MJ consumidos (+13,5 %).
- **Potencia por objeto sin tope propio:** el objeto de 10 kW llega por
  encima de su máximo y los dos sofás de 50 kW superan el suyo.
- C1–C9 (G3-1) antes: fallan C2, C3, C8, C9 (silla fría), C9 (dos objetos y
  potencia baja) y C2, C3 (carga de sala mayor). C1 y C4 cumplen.

## 3. Corrección de energía y potencia (`explicit_objects`, OFF por defecto)

Interruptor `SimulationEngine.fire_explicit_object_fuel_ownership_enabled`
(false), pasado por el contexto de combustión. **Solo** actúa en salas sin
`fuel_energy_MJ` ni `max_hrr_kw` de sala y con objetos explícitos: la
propiedad se lee del dato declarado, sin inferir combustible. Las salas con
carga de sala positiva —las 23 `legacy_unknown`, los 7 presets y las 13
iguales— siguen por la ruta legacy aunque el interruptor esté ON. Una carga
adicional se declara como objeto **nombrado** (caso `named_aggregate_source`).

Con ON, en `sim/fire/CombustionSystem.gd`:

1. El conjunto activo se fija al inicio del paso con el mismo criterio de
   candidato que legacy (foco primario, autoignición, llama, pirólisis,
   precalentamiento ≥ 6 o flashover). Un objeto inactivo no aporta energía
   ni eleva el tope.
2. Tope de potencia = Σ `max_hrr_kw` de activos; energía disponible por paso
   = Σ min(restante, `max_hrr_kw`·dt).
3. Reparto con topes (*water-filling*) con los pesos legacy: cada MJ
   consumido se debita de un objeto activo, sin superar su energía ni su
   potencia. El `FireModel` refleja el inventario de objetos.
4. El calor sólido liberado en el paso no supera la pirólisis del paso (ya
   debitada) ni el tope de potencia: no hay calor sin propietario.
5. Rendimientos, pesos de química, ignición y calentamiento **sin cambios**.

Resultado ON en los 5 casos `explicit_owned`: 0 MJ sin dueño, 0 descartado,
nada debitado a objetos inactivos, sin calor sin combustible y sin objetos
por encima de su tope (O1–O5 = 0 fallos); cierres K1–K5 sin fallos. En C1–C9
solo queda `room_load_above_objects` (C2, C3), que es legacy por diseño. La
silla fría conserva 3,0 MJ y el sofá consume lo mismo que solo (cociente
1,0000003).

**Efecto en especies, etiquetado como efecto del combustible consumido y del
calor liberado, no como validación química:** con el sofá solo el CO generado
baja un 2,6 % y el humo un 30,2 %, porque desaparece la cola de calor sin
combustible; con la silla fría el CO baja un 79,7 % porque deja de quemarse la
energía de la silla. **C6 sigue fallando en ON:** mismo combustible y mismo HRR
con y sin silla fría, pero CO ×2,92 y humo ×0,93, por la media ponderada de
rendimientos que incluye objetos fríos. Eso es química (G3-4), no propiedad.

**Límites de la corrección:**

- Calor liberado/consumido pasa de 1,135 (legacy, sofá solo) a 0,689 (ON): la
  cola sin combustible desaparece, pero sigue sin liberarse la pirólisis
  retrasada en la subida. **En este control no hay generación de pool**:
  el 70 % no retenido de otra ruta no explica la cifra. Véase el
  [desglose por paso](G3_ENERGY_BUDGET_DIAGNOSIS_2026-09-29.md). La física
  energética ON permanece NO-GO para producto.
- Un objeto que se activa por radiación durante el paso entra en el paso
  siguiente (retardo de un paso).
- Un residuo ≤ 1 kJ queda en el objeto agotado (sin descarte): la
  conservación cierra exacta.
- El impulso de flashover (`SimulationEngine`) y los picos de backdraft
  quedan acotados por los topes de objetos activos solo en salas
  `explicit_owned`; no se ha validado ese régimen.
- La ruta del charco de líquidos que eleva `fire.max_hrr_kw` no está cubierta.

## 4. Mutaciones, identidad OFF y suites

| Mutante (ruta ON) | Caso | Detectado por |
| --- | --- | --- |
| M1 objeto inactivo contado como activo | silla fría | oráculo independiente: la silla debe conservar 3,0 MJ (O3 no lo ve porque el mutante falsea también la bandera de actividad) |
| M2 sin tope de potencia por objeto | potencia baja | O4 (además O1, K1, K4) |
| M3 calor no acotado por la pirólisis del paso | sofá solo | O5 |
| M4 demanda pequeña no debitada | sofá solo | O1 (además K1, K4) |

Los cuatro detectados; `CombustionSystem.gd` restaurado con SHA-256 idéntico
tras cada mutante.

**Identidad OFF:** `sim_log.csv`, `events.json`, traza CO, libro v2 y
snapshot de objetos idénticos byte a byte en 9/9 casos entre `before` y
`ledger` (libro inerte) y entre `before` y `off` (corrección apagada).

Suites: ver §5.

## 5. Suites de regresión

Se tocaron `sim/core` (una exportación y una clave de contexto) y `sim/fire`,
así que se aplicó R2-1:

- **Suite de referencia completa** (`run_reference_checks.ps1`, 18 casos) una
  sola vez, sin otro Godot, bajo monitor que mataba el proceso por debajo de
  5 GiB libres o ante un cuadro de error: 3012 s, mínimo 7,22 GiB libres,
  `Resultado final: PASS`, sin Godot residual. **346/346 required PASS, 78
  gaps**, sin reclasificar.
- `reference_checks.json` cambia en algo más que `generated_at`, y se
  explica entero: el contenido de las 532 comprobaciones (métricas,
  veredictos, tolerancias) es idéntico. Cambian (a) las rutas absolutas de
  `references`, porque el informe anterior se generó en el checkout
  principal y este en el worktree G3, y (b) `bytes`/`sha256` de 38
  artefactos de entrada de la procedencia (`.in`, CSV CFAST, JSON de casos):
  los 38 se reproducen exactamente convirtiendo LF → CRLF, es decir, solo
  difieren los finales de línea del checkout (CRLF en el principal, LF en el
  worktree). Los informes por caso no cambian; solo aparecen `.log` ignorados.
- **Guardarraíles científicos**: ALL PASS (R2-1 incluido, con el informe
  regenerado junto al motor sin commit: deben commitearse juntos).
- **Producto** (`check_product.py`): 167/167 PASS.
- **Inventario de interruptores default-OFF** (P1R4): el nuevo interruptor se
  clasifica como física viva fuera del alcance diagnóstico, como
  `fed_co_zonal_enabled`; recuentos 83 declarados / 42 fuera de alcance.
- **pytest global**: la primera pasada dio 3046 PASS y 5 fallos, todos tests
  estáticos que fijan `EXPECTED_DECLARATION_COUNT = 82` con la nota «el G3
  posterior lo subió»; se actualizaron a 83 igual que en `a764a600`, sin
  relajar ninguna otra comprobación. Segunda pasada completa: **3051 passed,
  35 skipped, 2 xfailed, 42 subtests**, 0 fallos.

## 6. Siguiente fase

- **GO** para usar el libro como instrumento; el diagnóstico posterior
  localiza el desfase energético en el suavizado del HRR, pero **NO-GO**
  para declarar cerrada la física de energía ON. Falta un destino explícito
  de la pirólisis aún no liberada y controles de ventilación limitada.
- **GO** para diseñar G3-4 (química por objeto activo: C6) detrás de otro
  interruptor OFF, sin rendimientos inventados: G3-2 sigue NO-GO para
  `Y_CO(t)` por objeto.
- **NO-GO** para activar el interruptor en producto, migrar escenarios o
  presentar CO/FED como validados.
