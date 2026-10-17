# G3 - M4-P2: autoridad gas/energía/EOS y calentador prescrito sin combustible

Contrato: 2026-10-17. Base: `4c83638f` (main, sin subir nada nuevo).
**Diseño y protocolo predeclarados; sin módulo GD, sin motor, sin producto.**
Este documento y el [plan de casos y tolerancias](G3_M4_P2_GAS_ENERGY_EOS_PLAN_2026-10-17.json)
se escribieron antes de ejecutar el oráculo o cualquier prueba.
SHA-256 del plan (texto LF): `e20814fcbb03bd6ba8e6383c3dac6c3d4aa8069dc426f8a8f1e0346073a32eb5`.
Antecedente: [M4-P1, parcelas aisladas](G3_O2_M4_PHYSICAL_PARCEL_P1_2026-10-12.md).
M4-C/D, fuego/productos, CO/FED y activación en producto siguen OFF/NO-GO.
La referencia FED CFAST/FDS del 16-10 queda para G3-6.

## 0. Punto de partida comprobado

Git al empezar: `main` en `4c83638f`; locales preservados sin tocar:
`project.godot` (bloque `[editor_plugins]` de Sky3D movido de sitio, mismo
contenido) y `sim/validation/baselines/cfast_multi_fuel_couch_tv.json`
(solo fin de línea: `git diff` sin líneas). Nueve stashes intactos.

M4-P1 coincide con su cierre: módulo, fixture y auditor con los SHA-256
publicados (`b77eb33a…`, `4c405f12…`, `aa683064…`); solo el fixture carga el
módulo. DetMath (`ceccbe71`) no lo tocó.

Cómo trata hoy el motor energía y presión (lectura de código, no medición):

- `ThermalSystem`, `Phase3ZoneMassSystem`, `Phase3CoupledPressureSolver` y
  `CompartmentPressureEquations` usan `c_p = 1,0 kJ/(kg·K)` y
  `T_z = T_ref + E_z/(m_z·c_p)`: `E_z` es **entalpía sensible** sobre el ambiente.
- La EOS canónica de F2.2 (`p = (R/V)(M·T_ref + E/c_p)`) es correcta como
  identidad de gas ideal. Lo que falla es la **ecuación de energía**:
  F2.2A avanza `E` con calor y entalpías de abertura **sin el término
  `V·dp/dt`**. Es la aproximación isobárica (válida si la sala ventila), no la
  primera ley de un volumen rígido. En un recinto estanco con calentador
  `Q` da `Δp = (γ−1)/γ · Q/V` y `ΔT = Q/(m·c_p)`: **la subida de presión y de
  temperatura salen divididas por γ ≈ 1,40** (derivación analítica a partir de
  las ecuaciones documentadas de F2.2A, testigo W1; no es una ejecución del motor). La
  tabla §13.1 de F2.2 ya anotaba «SimuFire usa `c_p`… no `c_v·T`»; lo nuevo
  aquí es cuantificar la consecuencia.
- `R = 101325/(1,2·T_ref)` depende de la temperatura ambiente del escenario
  (`CompartmentPressureEquations.gd:110`, `Phase3CoupledPressureSolver.gd:1272`):
  283,15 K → 298,2; 293,15 K → 288,0; 303,15 K → 278,5 J/(kg·K). Una constante del
  gas no puede depender del escenario; con ella cambia también la γ implícita.
- La ruta F2.2 es experimental (`pressure_network_solver_enabled = false`
  por defecto) y la ODE heredada de `GasExchangeSystem` está OFF por defecto
  (con γ = 1,4 fija frente a γ = 1,4046 implícita en `c_p` y `R`). El producto
  por defecto reconstruye las salas a presión de referencia (aproximación
  isobárica). Nada de esto se cambia en esta entrega.

### 0.1 Sensibilidad al paso temporal: **no resuelta**

- El producto sigue avanzando el motor por 1/12 s acumulado a ×1
  (`Main.gd`, `SIM_STEP_S`). Desde ×5 avanza en cada tick con
  `dt = time_scale/60`: a ×20 el paso es de **1/3 s**.
- `SimulationEngine.step` usa el `dt` recibido tal cual: no hay subpasos.
- Con el hilo trabajador (`aaf83e44`, `1b09e1d4`) el tiempo sigue
  acumulándose mientras un paso corre; el siguiente se lanza con todo lo
  acumulado. Si el paso tarda más que el intervalo, `dt` crece y deja de ser
  uniforme. El margen es menor desde ×5, donde toca un paso por tick
  (16,7 ms) y un paso con fuego desarrollado tarda unos 12 ms más la
  exportación del estado (CHANGELOG del 16-10). No se ha medido cuánto varía.
- DetMath y el hilo garantizan **los mismos números para la misma secuencia
  de `dt`** (`tests/test_engine_thread.py`), no convergencia en `dt`.
- La última criba independiente (14-10, antes de DetMath y del hilo) dio
  2 739 / 1 606 / 1 445 de 23 760 comparaciones fuera de tolerancias exploratorias
  para 1/12, 1/30 y 1/40 s frente a 1/60 s
  ([informe](PRODUCT_CLOCK_SOBREMESA_2026-10-14.md)). No se ha repetido; la
  mejora de FPS no implica equivalencia física. Sigue **NO DEMOSTRADA**.

Este contrato separa por diseño los errores de paso de los de modelo: los
casos de calentador deben ser **independientes del paso al redondeo**, y los
de flujo explícito declaran un orden de convergencia medible (§8).

## 1. Alcance

Una autoridad de **gas inerte calóricamente perfecto** por sala y capa, con
calor prescrito (positivo o negativo), parcelas de masa impuestas (las de
M4-P1) y un exterior infinito. Sin combustible, reacción, HRR, productos,
hollín, CO/FED, radiación, paredes con estado, caudales por orificio, perfil
hidrostático en aberturas, ni Cp variable o dependiente de la composición. El O₂
viaja como fracción másica pasiva (regla de M4-P1) y no altera las propiedades.

La entrega de hoy es solo contrato, plan, oráculo Python independiente y
testigos analíticos. El módulo GD llegará en la fase siguiente (§13).

## 2. Propiedades del gas

| Símbolo | Definición | Papel |
| --- | --- | --- |
| `R` | constante del gas, kJ/(kg·K) | **entrada**, constante en la corrida |
| `c_p` | calor específico a presión constante | **entrada**, constante |
| `c_v` | `c_p − R` | derivada (relación de Mayer) |
| `γ` | `c_p/c_v` | derivada; nunca un literal |
| `k` | `(γ−1)/γ = R/c_p` | derivada |

Requisitos: finitos, `R > 0`, `c_p > R`. `R` **no** depende de `T_ref` ni del
escenario. El libro declara el juego de propiedades y no cambia en la corrida.
Dos juegos de prueba (plan): `engine_equivalent_293_15` (`c_p = 1,0`;
`R = 0,288035…`, el valor actual del motor a 293,15 K, congelado) y
`cfast_tn1889` (`c_p = 1,012`, `R = 0,28914`). Qué juego adopte el producto
se decide en la integración, no aquí.

## 3. Estado conservado y derivado

Base nueva `physical_gas_energy_eos_v1`. Por sala: geometría rígida
(`V`, `A_suelo`, `H`, prisma; `V = A·H`) fija en la corrida. Por capa
`z ∈ {upper, lower}`:

| Conservado (autoridad) | Unidad |
| --- | --- |
| `m_z` masa de gas | kg |
| `U_z` energía interna **absoluta**, `u = c_v·T`, cero a 0 K | kJ |
| `O_z` masa de O₂ (pasiva, regla M4-P1) | kg |

Se elige `U` absoluta porque con ella la EOS de la sala es lineal y exacta
(`p = (γ−1)·U/V`), y el transporte lleva entalpía `h = c_p·T` sin términos de
referencia. Cancelación numérica: `p_abs` ≈ 10⁵ Pa en doble precisión deja
~10⁻¹¹ Pa de redondeo, muy por debajo de los Pa que mueven aberturas.

| Derivada | Fórmula |
| --- | --- |
| `T_z` | `U_z/(m_z·c_v)`; `null` si `m_z = 0` |
| `p_abs` (sala) | `(γ−1)·(U_u+U_l)/V = R·Σ m_z·T_z / V` |
| `p_gauge` | `p_abs − p_ext`, con signo, sin recorte |
| `V_z` | `(γ−1)·U_z/p_abs = V·U_z/U` |
| interfaz | `V_lower/A_suelo` |
| `ρ_z`, `h_z`, `H_z` | `m_z/V_z`, `c_p·T_z`, `γ·U_z` |
| `Y_z` (O₂) | `O_z/m_z` |
| `E_z` sensible de F2.2/M4-P1 | `γ·U_z − m_z·c_p·T_ref` (conversión explícita) |

Prohibido: llevar `T`, `p`, `V_z` o la interfaz como segundo estado;
reconstruir masa desde la EOS; recortar energía o presión. `U_z = 0` si y solo
si `m_z = 0`; una capa con masa y `U_z ≤ 0` se rechaza.

Supuesto declarado: una sola presión termodinámica por sala en la EOS. La
variación hidrostática (`ρ·g·H/p ≈ 3·10⁻⁴`) se usa para caudales en aberturas
(fase posterior), no para el inventario.

## 4. Relación masa–energía–temperatura–volumen–presión

Gas ideal por capa a la presión común: `p·V_z = m_z·R·T_z`. Con `u = c_v·T`,
`m_z·R·T_z = (γ−1)·U_z`. Sumando las capas y usando `V_u + V_l = V`:

```text
p = (γ−1)·U/V          V_z = V·U_z/U          U = U_u + U_l
```

Consecuencias: el cierre de volumen es **identidad** para cualquier reparto de
`U` entre capas; por eso no sirve como prueba del reparto (testigo W5). La
presión depende solo de la energía total de la sala, no de la masa por
separado: masa y energía determinan `T`; energía y volumen, `p`.

## 5. Energía interna, entalpía y trabajo

Primera ley, sala rígida y abierta:

```text
dU_sala = δQ + Σ_entra h·dm − Σ_sale h_donante·dm      (sin p·dV: V fijo)
```

Por capa, con frontera móvil (la interfaz):

```text
dU_z = δQ_z + Σ_entra,z h·dm − Σ_sale,z h_z·dm − p·dV_z
```

`−p·dV_z` es el trabajo que una capa hace sobre la otra; `W_u + W_l = 0`.
Sustituyendo `V_z = (γ−1)·U_z/p`:

```text
γ·dU_z = A_z + V_z·dp      ⇔      dH_z = A_z + V_z·dp
A_z = δQ_z + Σ h·dm_entra,z − Σ h_z·dm_sale,z     (entalpía externa recibida)
```

Es la forma de CFAST (TN 1889v1, ec. 2.5–2.8) en otras variables. Sumada sobre
capas recupera `dU = A` y `dp/dt = (γ−1)/V·Σ ȧ_z`. La entalpía es la cantidad
que **viaja**; la energía interna es la que se **conserva** en el volumen
rígido; `V·dp` es la diferencia entre ambas y el término que falta en F2.2A.

### 5.1 Regla discreta (fijada aquí)

Paso con entradas constantes durante el paso y donaciones calculadas desde el
**snapshot previo** (regla M4-P1):

1. Masas: `m_z¹ = m_z⁰ + entradas − salidas`. Sin sobregiro ni financiación por
   entradas del mismo paso.
2. Entalpía de cada parcela: interior `q·c_p·T_donante⁰ = q·γ·U_d⁰/m_d⁰`;
   entrada exterior `q·c_p·T_ext`; la misma cantidad sale y llega.
3. Sala: `U¹ = U⁰ + Q_sala + H_entra_frontera − H_sale_frontera + Σ H_entre_salas`.
   Las parcelas entre capas de la misma sala **no** entran en esta suma (cancelan
   exactamente, sin redondeo). `p¹ = (γ−1)·U¹/V`, `r = U¹/U⁰ = p¹/p⁰`.
4. Reparto entre capas (solución exacta de `γ·dU_z = a_z·dt + V_z·dp` con
   `a_z` constante):

   ```text
   U_z¹ = r^k·U_z⁰ + φ(r)·A_z,      φ(r) = (r − r^k)/(r − 1),   φ(1) = 1/γ
   ```

   Cerca de `r = 1` se evalúa con serie para no perder precisión. Con `r = 1`
   exacto: `U_z¹ = U_z⁰·(m_z⁰−salidas_z)/m_z⁰ + (δQ_z + H_entra,z)/γ`, que deja
   `U_z¹ = 0` exacto si la capa se vacía.
5. Trabajo recibido por capa: `W_z = U_z¹ − U_z⁰ − A_z`, publicado en el recibo.
   Es derivado por definición: `W_u + W_l = 0` es una identidad de la regla y
   no prueba el reparto. Lo prueban la isentrópica de C2 y las soluciones cerradas.

Propiedades exigidas (y probadas en §8): `Σ U_z¹ = U¹` por construcción; capa
sin entradas → compresión **isentrópica exacta** `U_z¹ = U_z⁰·(p¹/p⁰)^k`; la
regla **compone** exactamente (dos pasos con la misma potencia = un paso), así
que el calentador prescrito es **independiente del paso** al redondeo; `r = 1`
reproduce mezcla isobárica exacta.

Límite declarado: una capa que se vacía en un paso con `r ≠ 1` dejaría un
residuo de energía de primer orden sin masa. **Se rechaza**
(`layer_depleted_while_pressure_changes`); el llamador debe partir el paso. La
evaluación con `h` congelada del snapshot es de primer orden en `dt` para
flujos de salida (casos C7 y C9): ese error se **mide**, no se oculta.

## 6. Balances

| Balance | Ecuación (por paso) | Clase |
| --- | --- | --- |
| Masa por capa | `Δm_z = Σ entra − Σ sale` | exacto |
| Masa del edificio | `ΔM = q_entra_frontera − q_sale_frontera` | exacto |
| Energía por sala | `ΔU_sala = Q_sala + H_entra − H_sale` | exacto |
| Energía por capa | `ΔU_z = A_z + W_z`, `W_u + W_l = 0` (W derivado) | identidad débil |
| Energía del edificio | `ΔU_ed = ΣQ + H_frontera_entra − H_frontera_sale` | exacto |
| Volumen | `V_u + V_l = V`, interfaz en `[0, H]` | identidad |
| EOS | `p·V = R·Σ m_z·T_z = (γ−1)·U` | identidad |
| O₂ | `ΔO_z = Σ q·Y_donante − Σ q·Y_z` (M4-P1) | exacto |

Frontera: el exterior es un depósito infinito con `T_ext > 0`, `p_ext` y
`Y_ext ∈ [0,1]`. Entrada: `q·c_p·T_ext` y `q·Y_ext`. Salida: entalpía y O₂ del
donante en el snapshot. El recibo acumula por evento: calor por capa, masa,
entalpía y O₂ de cada parcela de frontera, `W_z`, y los estados antes/después.
Ningún balance se cierra por diferencia: el auditor rehace cada término desde
el snapshot y las parcelas, como en M4-P1.

## 7. Compatibilidad

- **M4-P1**: su regla `dE = q·E_d/m_d` transporta entalpía sensible; en base
  `U` es la misma entalpía más `q·c_p·T_ref`. P1 era correcto para el
  transporte; le faltaban el trabajo `V·dp` y la EOS. Un libro P1 **no** se
  convierte en silencio: adaptador explícito con `c_p`, `R` y `T_ref`
  declarados (`U_z = (E_z + m_z·c_p·T_ref)/γ`), probado aparte.
- **F2.2**: mismo estado primario (masa y energía por capa) y misma EOS; la
  diferencia es el término `V·dp` y `R` fija. Integrar M4-P2 en la red exigirá
  cambiar la ecuación de energía de F2.2A/B y regenerar referencia **con
  autorización**; esta entrega no lo hace.
- **Producto por defecto**: isobárico; no se toca.

## 8. Casos analíticos y criterios (predeclarados en el plan)

| Caso | Qué prueba | Clase |
| --- | --- | --- |
| C1 | sala estanca, una capa, `Q` constante: `p = p⁰ + (γ−1)Qt/V` | exacto, independiente de `dt` |
| C2 | dos capas, calor solo arriba: capa baja isentrópica | exacto, independiente de `dt` |
| C3 | dos capas, 7/3 kW: solución cerrada de §5.1 | exacto, independiente de `dt` |
| C4 | pérdida a pared: presión manométrica negativa sin recorte | exacto |
| C5 | calor de arriba a abajo con neto cero: `p` constante, `ΔH_z = ±Q` | exacto |
| C6 | penacho isobárico: mezcla con conservación de entalpía | exacto |
| C7 | sala ventilada a `p` constante: `T = T⁰·exp((γ−1)Qt/(γpV))` | orden de convergencia |
| C8 | llenado adiabático desde el exterior: `T` sube sobre `T_ext` | exacto |
| C9 | vaciado adiabático: `T = T⁰·(m/m⁰)^(γ−1)` | orden de convergencia |
| C10a/b | nacimiento de capa; vaciado completo a `p` constante | exacto |
| C10c | vaciado completo con `p` cambiando | rechazo nombrado |
| C11 | `R`, `c_v`, `γ` iguales con ambiente 283/293/303 K | exacto |
| C13 | dos salas, transferencia y calentador: balances del edificio | balance exacto |

Tolerancias (plan, no se ensanchan): clase exacta `1e-11` relativo con suelos
absolutos (masa 1e-12 kg, energía 1e-9 kJ, presión 1e-6 Pa, temperatura
1e-9 K); identidades por paso `1e-12`; independencia del paso `1e-11`; orden
observado en `[0,9; 1,1]` en cada halvado, con error decreciente. El error a
1/12 s de C7 y C9 se publica, sin umbral nuevo. El margen cubre 3 600 pasos de
redondeo; cualquier error de esquema O(dt) en los casos exactos es ≥ 1e-6.

Rechazos nombrados (lista completa en el plan): números no finitos o bool,
`c_p ≤ R`, masa o energía negativas, energía sin masa, sobregiro, entradas que
financian salidas, contexto o revisión obsoletos, duplicados, calor en capa
ausente sin masa, energía de sala o capa no positiva tras el paso, vaciado con
presión cambiante y cambio de geometría o propiedades en la corrida.
Un rechazo no deja candidato, recibo ni revisión nueva.

## 9. Testigos contrafactuales y mutantes

Testigos de diseño (Python, hoy): cada uno **debe fallar** su caso.

| Id | Contrafactual | Debe fallar |
| --- | --- | --- |
| W1 | calor a entalpía `c_p` sin `V·dp` (F2.2A) | C1: `Δp` y `ΔT` divididos por γ |
| W2 | γ = 1,4 literal | C1 con el juego del motor |
| W3 | `R` desde `T_ref` | C11 |
| W4 | reparto por reescalado proporcional | C2: isentrópica y paso |
| W5 | capa pasiva sin comprimir | C2 isentrópica, **con cierre de volumen en verde** |
| W6 | la salida debita `u` en vez de `h` | C9 |

Mutantes GD para la fase de implementación: lista cerrada de 16 en el plan
(`gd_mutants_for_p2_implementation`), con control sano, fallo nombrado en la
aserción declarada y restauración SHA-256. Error de script o nativo nunca es
mutante muerto.

## 10. Protocolo reproducible

Hoy (sin Godot, sin `sim/`):

```text
python -m pytest tests/test_g3_m4_p2_gas_energy_eos_contract.py -q -p no:cacheprovider
```

El oráculo [`g3_m4_p2_gas_energy_eos_oracle.py`](../../scripts/simulation/g3_m4_p2_gas_energy_eos_oracle.py)
es Python puro, sin rutas absolutas ni dependencias externas, y no importa
nada del motor. Calcula las soluciones analíticas en `Decimal` (50 dígitos) y
aplica la regla de §5.1 en doble precisión. El test comprueba el SHA-256 del
plan (texto normalizado a LF) antes de usarlo: si el plan cambia, falla.

Fase GD (siguiente, no iniciada):

1. Módulo puro `sim/core/PhysicalGasEnergyEosModel.gd`, sin `class_name`,
   exports, escenas ni consumidores; contrato de eventos/recibos de M4-P1.
2. Fixture sin motor con los casos del plan; auditor Python = este oráculo,
   que rehace cada recibo desde el snapshot sin llamar al GD.
3. Godot solo por `scripts/godot_monitored_launch.py`: ejecutable normal, UI
   suprimida, JobObject propio, ≥ 6 GiB, una tanda a la vez, temporales fuera
   del repo, sin matar procesos ajenos.
4. Campaña de 16 mutantes; luego, por tocar `sim/core`, la cadena completa:
   referencia R2-1, guardarraíles, producto y global
   `pytest tests -q -p no:cacheprovider`, en secuencia. Solo cambia
   `generated_at`; ningún resultado se ajusta para cerrar.
5. El inventario de módulos GD de M4 pasa a 66 con una sola adición aislada;
   se preservan UID sin seguimiento y stashes.

## 11. Qué es histórico y qué es nuevo

Histórico, no reejecutado hoy: cierre M4-P1 (5 920 checks, 20/20 mutantes,
cadena R2-1), criba de paso del 14-10, F2.2A–D, referencia 346/346 con 78 gaps.
Nuevo hoy: lectura de código de §0, este contrato, el plan con hash, el
oráculo y sus testigos (resultados en §12). Los testigos prueban la **coherencia del diseño**, no
la física del motor ni la de un incendio.

## 12. Ejecución del oráculo (después de fijar el plan)

El plan no cambió entre su hash y la ejecución (lo comprueba el primer test).

| Comprobación | Resultado |
| --- | --- |
| Testigos del contrato | **38 passed**, 1,03 s, sin Godot |
| C1–C3, dos juegos de propiedades | exactos en 1/60, 1/12, 1 y 60 s; mismo `U_z` a 1e-11 |
| C7 orden observado (4→0,25 s) | 1,013 / 1,006 / 1,003 / 1,002 |
| C9 orden observado | 1,006 / 1,003 / 1,002 / 1,001 |
| Error relativo de `T` a 1/12 s | C7 8,08·10⁻⁵ (412,3 K); C9 1,97·10⁻⁵ |
| W1 | `Δp` y `ΔT` de F2.2A = valor de primera ley / γ (γ = 1,40456) |
| Mutantes del oráculo | **8/8 muertos** en sus aserciones, SHA-256 restaurado |
| Focales offline | 370 passed, 25 subtests (M4 histórico, rutas, F2.2A, P2) |
| Enlaces y guardarraíles | Markdown PASS; ALL GUARDRAILS PASS, R2-1 incluido |

El orden 1 y el coeficiente de C7 coinciden con la predicción analítica previa
(`(1 − x/n)^(−n)` frente a `eˣ`: 3,946·10⁻³ previsto y medido a 4 s). Con 1/12 s
el error de la entalpía congelada en estos casos es ~10⁻⁴ o menos; **no**
explica por sí solo la sensibilidad al paso del motor (§0.1), que tiene otras
fuentes no aisladas.

Intentos que no cuentan como cierre:

1. Primera ejecución: 6 fallos de tipo del arnés (`float × Decimal`) en la
   comprobación del trabajo, después de que `U` y `p` hubieran pasado.
   Corregida la conversión en el test; ni oráculo ni tolerancias cambiaron.
2. Primera campaña: `depletion_guard_removed` sobrevivió porque la segunda
   barrera rechaza C10c con el mismo motivo. Faltaba el caso «vaciada y
   rellenada en el mismo paso con `p` cambiando», que el contrato ya declaraba
   rechazo. Se añadió ese test y se repitió la campaña completa: 8/8.

SHA-256 (texto del checkout): oráculo
`4c1d34f448c05f5c0a159bf4d0bf88063b0818b233d9a498ca6f5e6cc93174a1`, test
`ca8b2491ed27f54d8d0534a16a4cd829ffcdfeb5cb712d6771a74724c8236343`. Los guiones
de la campaña y del informe de órdenes quedaron en temporales de la sesión, no
en Git. No se cambió `sim/`, ninguna referencia ni el producto; por eso no se
corrió la cadena R2-1 completa ni la global.

## 13. Siguiente paso concreto

**M4-P2-GD**: implementar `PhysicalGasEnergyEosModel.gd` y su fixture contra
este plan sin cambiarlo, con el oráculo como auditor y la campaña de 16
mutantes. Antes de conectar nada: decidir con el usuario (a) el juego de
propiedades del producto y (b) si la red F2.2 adopta la ecuación de energía
con `V·dp`, lo que regeneraría referencias. Aparte, sin bloquear esto:
repetir la criba de paso con el motor actual a 1/12 s, a ×20 (1/3 s) y con el
paso variable del hilo trabajador.
