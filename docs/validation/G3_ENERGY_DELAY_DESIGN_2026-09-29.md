# Gate B — diseño del destino de la energía retrasada (propuesta, sin implementar)

Fecha: 2026-09-29. Estado: **diseño para revisión; no se ha tocado la física**.

> **Revisión 2026-09-30:** el usuario eligió la **opción D** (§7). La
> recomendación a)+b) de §3 queda **sustituida**: `R` no pasa al depósito de
> gases. Las pruebas F1–F7 de §4 quedan sustituidas por §7.6.
>
> **Revisión 2026-09-30 (tarde), tras los 16 controles:** §8 fija el contrato
> de O₂ y de R posagotamiento. §7.3 queda sustituida por §8.3–§8.4 y §7.6 por
> §8.6 (F4 reformulada). Decisión en §8.9.
>
> **Revisión 2026-09-30 (noche):** §9 recoge el prototipo de D con la cola B en el
> motor real (interruptor OFF en producto), el caso de estrés de O₂ y R2-1.

Entrada: [diagnóstico del presupuesto](G3_ENERGY_BUDGET_DIAGNOSIS_2026-09-29.md)
y libro G3-3. Interruptor `fire_explicit_object_fuel_ownership_enabled`
sigue OFF en producto; CO/FED y G3-4 química siguen NO-GO.

## 1. Mecanismo medido

`room.hrr_kw` sigue al objetivo `T` (llama + latencia) con un filtro de
primer orden **asimétrico**: subida `τ = 6 s × 1,8` sin respuesta de
ventilación (≈10,8 s) y bajada `τ = 20 s`. Un filtro lineal simétrico conserva
la integral cuando la entrada vuelve a cero; este no. Sofá solo (90 s, libro
G3-3, `T = C` porque `G = 0`):

| Rama | `C` MJ | `B` MJ | Retraso en subida (`T > B`) | Exceso en bajada (`B > T`) | Tras agotarse el sofá |
| --- | ---: | ---: | ---: | ---: | --- |
| Legacy (OFF) | 2,999863 | 3,405765 | +0,943684 | −1,349586 | libera 0,214833 MJ con 0,000848 MJ de combustible; HRR aún 20,10 kW a 90 s |
| `explicit_objects` ON | 2,999013 | 2,065228 | +0,933784 | 0 | HRR 0 |

Legacy **crea** calor (bajada más lenta que subida); ON lo impide limitando
`B` a la pirólisis del paso, pero el retraso de la subida queda sin estado:
0,933784 MJ de combustible debitado que nunca se libera ni se guarda.

## 2. Términos, unidades y propietarios propuestos (MJ por paso)

- `C_i`: pirólisis debitada al objeto activo `i` (ya existe, un propietario).
- `R_i`: **inventario de pirolizado aún no liberado** del objeto `i`
  (nuevo estado, ≥ 0). No es humo ni gas retenido: es el desfase del modelo
  de liberación.
- `B_i`: calor sólido liberado atribuido a `i`.
- `G_i`: paso al pool de inquemados existente (`retained_unburned_MJ`), con
  propietario de origen registrado.
- `X_i`: salida declarada de inquemado no oxidado (solo si se aprueba un
  mecanismo; hoy **no** se propone).

Identidad por paso y objeto: `C_i = B_i + ΔR_i + G_i + X_i`, cierre
`1e-9 MJ` como el libro. Restricciones: `B_i ≤ C_i + R_i(prev)` (sin calor
sin combustible); `B_i ≤ max_hrr_kw_i · dt`; ningún término sin propietario.

## 3. Dinámica propuesta

El HRR sigue usando el filtro legacy para su **forma**, pero la liberación
sólida disponible pasa de «pirólisis del paso» a «pirólisis del paso + `R`».
Así la cola de bajada libera lo retrasado en la subida hasta agotar `R`, y
nunca más. Al extinguirse el fuego, el `R` que quede tiene destino
explícito, y ese destino **es la decisión física que hay que aprobar**:

| Opción | Qué supone | Riesgo |
| --- | --- | --- |
| a) Liberar `R` solo mientras hay llama viable | el retraso es inercia térmica de la combustión | con extinción por O₂ quedaría `R` sin destino |
| b) Pasar `R` restante al pool de inquemados al extinguirse | lo pirolizado sin quemar queda como gas combustible que puede arder al ventilar | cambia backdraft/pool; necesita controles subventilados |
| c) Pérdida declarada `X` | inquemado que sale sin oxidarse | exige mecanismo y medida; no hay evidencia hoy |

**Recomendación:** a) + b). No convertir nada en calor inmediato fuera del
filtro, ni en pérdida silenciosa. c) solo con un mecanismo medido.

## 4. Pruebas de falsación (fijadas antes de implementar)

- **F1 conservación**: por paso y objeto `C = B + ΔR + G + X`, residuo ≤ 1e-9 MJ.
- **F2 sin calor sin combustible**: en cada paso `ΣB ≤ ΣC` acumulado, por
  objeto y por sala.
- **F3 agotamiento bien ventilado**: sofá solo hasta apagarse (≥ 300 s):
  `R_final ≤ 1e-9 MJ`, `ΣB/ΣC = 1 ± 1e-6` (sin pérdida declarada).
- **F4 ventilación limitada**: sala cerrada con extinción por O₂ a mitad de
  fuego: todo `R` pasa al pool al extinguirse; una apertura posterior lo
  quema; el calor total nunca supera `ΣC`.
- **F5 varios objetos con límites**: `R_i`, `B_i ≤ max_hrr_i`, sin trasvase
  de `R` entre propietarios; objeto frío con `R = 0`.
- **F6 paso de tiempo**: `dt` 1/12 frente a 1/24 s: `ΣB` dentro del 1 %;
  se informan pico y tiempo al pico, sin ajustarlos.
- **F7 OFF**: identidad byte a byte en los nueve controles; salas legacy
  idénticas con ON.
- **Mutaciones**: permitir `B > C + R` (F2), descartar `R` al extinguirse
  (F1/F3), repartir `R` entre objetos (F5).

## 5. Efectos esperados que se medirán, no se ajustarán

`ΣB/ΣC` del sofá tenderá a 1 en fuegos completos y seguirá < 1 en una
ventana que corte la cola. Cambiarán HRR de cola, temperatura y, por la base
de CO/humo (`actual_solid_burn_kw`), las especies: se etiquetarán como
efecto del combustible y del calor, no como validación química.

## 6. Decisión

**NO-GO** a implementar sin aprobación de la opción de destino (§3).
**GO** a implementar F1–F7 como pruebas del libro en cuanto se apruebe.

## 7. Revisión 2026-09-30 — opción D: `R` es un saldo contable por objeto

Decisión de diseño del usuario: el remanente `R` del suavizado del HRR es un
**saldo energético contable del objeto**, no gas combustible demostrado. No
se transfiere a `retained_unburned_MJ`, no se convierte en CO, calor
inmediato ni combustible disponible para reignición, y no se descarta en
silencio.

### 7.1 Términos (MJ; `kW × dt / 1000`), sin mezclar categorías

| Símbolo | Qué es | Categoría física | Estado hoy |
| --- | --- | --- | --- |
| `C_i` | energía química del combustible **pirolizado** debitada al objeto `i` (`pyrolysis_kw·dt`) | combustible gasificado | existe, un propietario |
| `B_i` | **calor liberado** por la combustión del sólido atribuido a `i` (`actual_solid_burn_kw·dt`) | calor | existe |
| `G_i` | parte de `C_i` que entra en `retained_unburned_MJ` (`0,30·(P−T_s)` con llama) | **combustible físico sin quemar**, puede arder después | existe, por sala (sin dueño de origen) |
| `U_i` | resto `C_i − T_s·dt − G_i`: pirolizado no oxidado que no entra al depósito (70 % con llama; 100 % en fase latente) | combustible físico sin quemar **no transportado** | existe; **pérdida no declarada** (fuera de alcance: solo se declara) |
| `R_i` | parte de `C_i` cuyo calor el filtro aún no ha liberado | **saldo contable**: no ocupa volumen, no transporta especies, no consume O₂ ni produce CO | **no existe**: en ON se pierde; en legacy se sobregira |
| pérdidas térmicas | calor ya liberado que sale por paredes y aperturas | entalpía de la sala | fuera de este balance de combustible |

`T_s = flame_target + smolder_target` (kW). Identidad exacta por paso y
objeto: `C_i = B_i + ΔR_i + G_i + U_i`. `R` **no** es «gas acumulado».

### 7.2 Contraste con CFAST/NIST (documentación ya reunida)

- CFAST TR, NIST TN 1889v1 §3.2, ec. 3.12–3.14, p. 12–13: la pirólisis
  `ṁ_f = Q/H` se prescribe; si el O₂ limita, «the pyrolysis rate does not
  change» y `Q = min(ṁ_f·H, ṁ_e·Y_O2·C_LOL·H_O2)` es **algebraico en cada
  instante, sin filtro temporal**. «Any unburned fuel is tracked by the model,
  and transported […] may burn in the upper layer or at vents if sufficiently
  hot and if additional oxygen is available.»
- CFAST UG, NIST TN 1889v2 cap. 7, p. 24: al alcanzar el límite inferior de
  O₂, calor y productos se sustituyen por «unburned fuel gas which is
  transported from zone to zone until there is sufficient oxygen and a high
  enough temperature»; su umbral es la «Gaseous Ignition Temperature».

Consecuencia: el combustible sin quemar de CFAST es **masa de combustible
producida por limitación de O₂** y corresponde en SimuFire a `G + U` (CFAST
conserva el 100 %, no el 30 %). CFAST **no** tiene análogo de `R`: con buena
ventilación su inquemado es 0, mientras que el ON de SimuFire acumula
`R = τ_r,ef · pico` en el sofá ventilado (§7.4). Pasar `R` a `G` crearía gas
combustible en un fuego bien ventilado, contrario a la base CFAST, y
alimentaría el depósito y los umbrales de backdraft con gas inexistente. `U`
(70 % no transportado) es una divergencia real frente a CFAST; se declara, no
se corrige en esta fase.

### 7.3 Dinámica de la opción D (solo sala `explicit_owned`, interruptor ON)

Por paso, con el filtro legacy sin cambios (`y_f`, subida `τ_r`, bajada `τ_f`)
y `pool_burn` intacto: `S = y_f − pool_burn` (petición sólida del filtro, kW).
Cuotas por débito `w_i = burn_i / Σ burn` (reparto existente con topes).

1. Base: `B⁰ = min(S, T_s)`; retraso `L = T_s − B⁰ ≥ 0`; `R_i += w_i·L·dt`.
2. Liberación: si `S > T_s`, el exceso `E = S − T_s` sale **solo** de los
   `R_i` de objetos **viables**, repartido con topes `R_i/dt` y
   `max_hrr_kw_i − w_i·B⁰` (potencia propia); `R_i −= rel_i·dt`. Sin trasvase
   entre propietarios; lo que no cabe no se libera (y el filtro baja).
3. Viable `i` ⇔ objeto activo al inicio del paso **y** `burn_i > 0` **y**
   `can_flame` **y** no `selected_o2_extinguished`. Un objeto agotado, en fase
   latente, extinguido por O₂ o frío **no** libera `R`.
4. `B_i = w_i·B⁰ + rel_i`; `room.hrr_kw = Σ B_i + pool_burn` (el filtro sigue
   el calor aplicado, como en ON).
5. Extinción o agotamiento: `R_i` se **conserva y se declara** en el libro; no
   se suma a `retained_unburned_MJ`, ni a `remaining_fuel_MJ`, ni a
   `available_MJ`, ni a la condición de actividad del objeto.

Cambio respecto a ON: la cota del calor sólido pasa de `P` a `T_s + R/dt`. Con
O₂ limitante (`T_s < P`), ON puede liberar como calor energía que también se
contabiliza en `G`/`U` (doble uso). Esto **no está medido**; se mide antes
(observable `Σ max(0, B − T_s)·dt` en ON, §7.5 P5).

### 7.4 Hechos medidos: 0,689 (ON) y 1,135 (legacy), sofá solo, 90 s

Libros G3-3 `runs/g3_fuel_ledger_{off,on}_20260929_*/single_object`, sala 0,
`dt = 1/12 s`. Reconstruyendo `y_f` con `τ_r = 10,8 s` y `τ_f = 20 s`, el
filtro reproduce la HRR legacy con error **0,000 kW** en los 1081 pasos
(`filter_attribution` en `analyze_g3_energy_budget.py`).
`τ_ef = dt/(e^{dt/τ}−1)`: 10,758387 s y 19,958362 s. `U = 0` y `G = 0`.

| MJ | Legacy OFF | ON |
| --- | ---: | ---: |
| `C` | 2,999863 | 2,999013 |
| retraso de subida `Σ(T−y_f)`, subida | 0,943684 = 10,758 s · 87,716 kW | 0,933784 = 10,758 s · 86,796 kW |
| exceso de bajada `Σ(T−y_f)`, bajada | −1,349586 = −19,958 s · (87,716 − 20,096) kW | −0,007203 |
| recorte ON `Σ(y_f − B)` | 0 | +0,007203 |
| `B` | **3,405765 → 1,1353** | **2,065228 → 0,6886** |

- ON: `C − B = τ_r,ef · pico` exactamente; el recorte anula toda la bajada. El
  déficit no depende de la ventana (a 90 s ya `y = 0`). **Defecto contable
  demostrado**: 0,933784 MJ debitados al sofá sin estado de destino (ni calor,
  ni `G`, ni `U`, ni declarado).
- Legacy: `B − C = τ_f,ef·D − τ_r,ef·U`; a 90 s la cola sigue en 20,10 kW y el
  sofá se agotó a 81,5 s (0,214833 MJ de calor tras agotarse). Es la ruta
  OFF: **no se modifica**.

### 7.5 Predicciones pre-registradas (antes de ejecutar)

- P1 ON sofá 600 s: `B/C = 0,688636 ± 1e-6` (sin energía tras 90 s).
- P2 legacy sofá 600 s: `B/C → 1 + (τ_f,ef − τ_r,ef)·pico/C = 1,2690` si la
  cola decae sin corte; si el fuego se retira antes con cola `y_c`, restar
  `τ_f,ef·y_c/C`. Se informa cuál ocurre.
- P3 opción D sofá: igual a ON hasta el pico (`R_pico ≈ 0,934 MJ`); en la
  bajada con el sofá aún activo el exceso disponible es 1,135601 MJ
  (trayectoria legacy hasta 81,5 s) > `R_pico`, luego `R` se agota **antes**
  que el sofá: `R_final ≤ 1e-6 MJ` y `B/C = 1 − ε` (ε = residuo del objeto
  ≤ 1 kJ). Es consecuencia de la dinámica, no condición impuesta: con una
  bajada más rápida, `R_final > 0` sería válido.
- P4 `dt = 1/24`: `τ_r,ef` pasa de 10,758 a 10,779 s (+0,19 %); `R_pico` y el
  cociente ON cambian ≲ 0,3 %.
- P5 sala cerrada limitada por O₂ (geometría v7, un objeto de 120 MJ /
  600 kW): observables `R` en la extinción, `ΣG`, `ΣU` y
  `Σ max(0, B − T_s)·dt` en ON. No se predice `R_final`; se exige que no cambie
  mientras el objeto no sea viable.

### 7.6 Pruebas revisadas (sustituyen a §4)

- **F1 conservación**: por paso y objeto `|C_i − B_i − ΔR_i − G_i − U_i| ≤ 1e-9 MJ`;
  `R_i ≥ 0`.
- **F2 sin calor sin combustible**: `Σ B_i ≤ Σ C_i − Σ G_i − Σ U_i` acumulado
  por objeto en todo instante.
- **F3 sofá ventilado**: `R_final` y `B/C` dentro de 1e-3 MJ de la predicción
  P3 calculada con la propia trayectoria; **no** se exige `R_final = 0` por
  decreto. Falsa si `R` baja mientras el objeto no es viable o si hay calor
  tras el agotamiento.
- **F4 limitado por O₂**: mientras el objeto no es viable, `ΔR_i = 0` exacto;
  tras la extinción `R` constante y declarado; `ΣG` no recibe `R` (`G` sigue
  su fórmula con los objetivos del propio paso). **Reapertura**: no se
  presupone que queme `R`; solo puede liberarlo si el objeto vuelve a ser
  viable con su propia pirólisis; si no, `R` queda igual. Falsa si `R` pasa al
  depósito, alimenta reignición o se libera sin pirólisis propia.
- **F5 varios objetos**: `R_i` por dueño, `B_i ≤ max_hrr_kw_i·dt`, sin
  trasvase; objeto frío con `R = 0`.
- **F6 paso temporal**: `1/12` frente a `1/24`: `ΣB` dentro del 1 %, `R_pico`
  según P4; pico y tiempo al pico se informan sin ajustarlos.
- **F7 OFF**: identidad byte a byte de salidas con el interruptor OFF frente al
  motor anterior; salas con carga de sala idénticas con ON.
- **Mutaciones**: `R` al depósito al extinguirse (F4), descartar `R` (F1),
  liberar sin viabilidad (F3/F4), trasvase entre objetos (F5), cota `P` en vez
  de `T_s + R/dt` (F2, si P5 muestra doble uso).

## 8. Revisión 2026-09-30 (tarde) — contrato de O₂ y de `R` posagotamiento

Base: los 16 controles `runs/g3_energy_pre_{off_20260930_171424,on_20260930_172851}`
(8 OFF + 8 ON, todos con salida 0, sin cuadros ni residuos), el código de
`CombustionSystem.gd` (CS), `OxygenExchangeSystem.gd` (OES) y
`SimulationEngine.gd` en HEAD 35d0f978 + cambios sin commit, y dos
herramientas nuevas de solo lectura: `scripts/simulation/replay_g3_option_d.py`
(reconstrucción) y `scripts/simulation/check_g3_option_d_contract.py`
(pruebas K0–K7), con `tests/test_g3_option_d_contract.py`.

Etiquetas: **[M]** medido en los libros; **[C]** leído en el código; **[R]**
reconstrucción fuera de línea (trayectorias ON tomadas como exógenas, sin
realimentación de temperatura ni de O₂); **[H]** hipótesis.

### 8.0 Corrección de la evidencia previa

- [M] El informe anterior contaba «12,6 kJ de `R` liberados en pasos
  limitados por O₂» usando `P > T_s` como detector. Ese detector es
  incompleto [C]:
  - con llama, la pirólisis se estrangula con el mismo factor
    (`pyrolysis_drive = max(flame_drive, latent_drive)`, CS l. 1599), así que
    `P = T_s` aunque el O₂ limite;
  - `P > T_s` solo aparece en la fase latente o con el suelo de pirólisis
    subventilada.

  Con el factor del propio modelo (`flame_drive = o2_hrr_factor ·
  flame_possible`, reconstruido de `sim_log.csv`), **toda** la liberación de
  §7.3 en `o2_closed` (5,44 MJ) ocurre con `flame_drive < 0,95`, y 2,44 MJ de
  ella con `flame_drive < 0,5`. En los casos ventilados, la liberación ocurre
  con `flame_drive ≥ 0,99`.
- [R] Los demás valores del informe se reproducen: `low_power_vent`
  `R_final = 0,9755 MJ`, `two_active_vent` 0,1876 MJ, sofá `R_pico` 0,933784.
  En `o2_closed` sale 1,6265 MJ (antes 1,6248) porque ahora la viabilidad
  incluye `can_flame`, como exige §7.3.

### 8.1 Presupuesto de O₂ trazado hasta su aplicación [C]

Orden del tick con `fire_o2_mode = legacy`, el de todos los controles:
primero `_step_fire` y después `_step_oxygen`, en el mismo paso
(`SimulationEngine.gd:3897–3917`). Según `_uses_pre_hrr_oxygen_step`
(l. 5086), solo `upper/lower/interface` debitan el O₂ antes del fuego.

Cadena de un paso, con su propietario:

| Etapa | Propietario y lugar | Qué es |
| --- | --- | --- |
| Zona de O₂ | `_resolve_fire_o2_selection` (CS l. 2809) | dos zonas: `plume_lower` → `o2_ref = o2_lower` ([M] 100 % de las filas tras 1 s) |
| Factor de O₂ | CS l. 1524, 1575–1582 | `raw = (o2_ref − o2_min)/(o2_full − o2_min)`, **suavizado** con τ 14/32 s → `o2_hrr_factor` |
| Posibilidad de llama | CS l. 1584–1600 | `flame_possible = clamp((o2_ref − o2_min + 0,015)/0,04)`; `flame_drive = o2_hrr_factor · flame_possible`; `can_flame ⇔ flame_drive > 0,08` |
| HRR ideal | CS l. 1648–1675 | `t²·decay(combustible)·rad_feedback`, ≤ Σ `max_hrr_kw` de los objetos activos |
| Pirólisis `P` | CS l. 1701–1713, 1740–1749 | `ideal · max(flame_drive, latent_drive, suelo)`, escalada por el combustible disponible; se debita en l. 2326 y se reparte en l. 2335 |
| Objetivo `T_s` | CS l. 1714–1728 | con llama, `min(P, ideal·flame_drive)`; sin llama, `smolder` |
| `G` | CS l. 1729–1735, 1783 | `0,30·(P − T_s)`, 0 en fase latente; va al depósito |
| Filtro HRR | CS l. 1912–1927 | primer orden asimétrico: τ de subida 10,8 s, de bajada 20 s |
| Tope ON | CS l. 1978 | `B_sol ≤ min(P, Σ cap)` |
| Especies | CS l. 2156, 2221, 2230–2243 | CO sobre `B_sol + pool`; CO₂ sobre `max(HRR, humo)`; tope de carbono por `P` |
| **Débito de O₂** | `OxygenExchangeSystem.step` (OES l. 449–462 bulk, 514–548 upper, 596–625 lower, 629–661 plume) | `hrr_kw · 0,076 · dt · f_ruta`, truncado al 5 % o al 20 % de la masa de O₂ de la zona |

Ecuación del presupuesto por paso, en la ruta `plume_lower` de los controles:

    O2_fuego = min( 0,076 kg/MJ · (B_sol + B_pool) · dt · f_plume ,  0,20 · m_aire_baja · o2_lower )
    O2_total = O2_fuego + 0,076 · (B_sol + B_pool) · dt · 0,09        (desplazamiento superior)
    B_sol    = B0 + Σ_i rel_i                                          (opción D)

Conclusiones:

- **`T_s` no es una cota de oxígeno.** Es un objetivo de HRR: el HRR ideal
  multiplicado por un factor de **concentración suavizado**. Antes de fijar
  el calor no interviene ninguna masa de O₂. Además, `T_s` mezcla el límite de
  O₂ con el de combustible (`decay`) y el de crecimiento (`t²`).
- **El único límite de masa es el tope 5 %/20 % de OES**, y actúa
  **después** de fijar el calor. Trunca el O₂, no el calor: si llegara a
  actuar, habría calor sin su oxígeno. Nadie acota el calor por el O₂
  disponible.
- [M] **K0** comprueba `O2_fuego = 0,076·HRR·dt` con tolerancia absoluta de
  1e-12 kg. Se cumple en todos los pasos de los 16 controles **salvo en el
  paso de extinción** de 9 de ellos: ahí el libro anota calor (≤ 1,15e-6 kg de
  O₂ equivalente, unos 15 J) y el O₂ debitado es 0. Es un defecto previo,
  ajeno a `R`, y se declara aparte.
- [M] El sumidero total de O₂ frente al del fuego es 2,00× en ventilado, 1,09×
  en cerrado (el 0,09 de desplazamiento) y 1,24× en `o2_reopen_700` ON. Es el
  defecto conocido O2-4; se declara aparte y no entra en este contrato.
- Liberar `R` añade `0,076·rel_i` al débito por la misma ruta: la opción D no
  tiene otro canal de O₂. Por eso la liberación necesita un permiso de O₂
  propio (§8.3, L2).

### 8.2 Doble uso medido en ON y su causa [M]

- El O₂ del fuego es exactamente `B / 13,1579 MJ/kg` en cada paso, también con
  O₂ limitante: `B` es combustión real.
- En `ON o2_closed` hay 4,68 MJ de `B − T_s` en pasos con `P > T_s` (el 19 %
  de `G + U`); 2,79 MJ de ellos, con `T_s = 0`.
- Causa [C]: el tope ON es `P` (l. 1978), no `T_s`. En la caída del filtro se
  libera como calor pirolizado que la misma fórmula ya apuntó en `G + U`.
- Con el contrato §8.3, el doble uso es **0 exacto** [R] en los ocho casos:
  `B0 ≤ T_s`, y no hay liberación si `P > T_s`.

### 8.3 Contrato de `R` (sustituye a §7.3)

**Acumulación (A):**

- **A1.** En cada paso, `B0 = min(max(S, 0), T_s)`, con `S = y_f − pool_burn`,
  y `acc_i = w_i · (T_s − B0) · dt`, con `w_i = C_i / Σ C` (débito del paso).
- **A2.** Se acumula **en cualquier estado**, también en las transiciones con
  `state_before` obsoleto: es parte de `C_i`, que ya se debitó, y la identidad
  `C_i = B_i + ΔR_i + G_i + U_i` tiene que cerrar. [R] En `o2_closed` son
  0,0176 MJ en 5 pasos «decaying»; en `o2_reopen_700`, 0,0119 MJ en 3.
- **A3.** Un retraso con `T_s > 0` y `Σ C = 0` es un retraso sin dueño:
  violación (K1).

**Liberación (L):** `rel_i > 0` solo si se cumplen todas estas condiciones:

- **L1 propietario:** (i) llama propia (`active_before`, `C_i > 0`,
  `state_before = flaming`) o (ii) cola propia (§8.4, opción B). **Nunca**
  porque otra fuente mantenga llama en la sala.
- **L2 O₂:** `can_flame`; no `selected_o2_extinguished`; `P − T_s ≤ 1e-9 kW`
  (todo el pirolizado fresco del paso se quema); y
  `B0_i + rel_i ≤ flame_drive · max_hrr_kw_i`.

  [H] Es un **permiso de potencia**: el máximo `T_s` que el factor de O₂
  concedería a un objeto plenamente desarrollado
  (`T_s ≤ flame_drive·ideal ≤ flame_drive·cap`). No es un balance de masa de
  O₂, porque el motor no tiene ninguno. No introduce parámetros nuevos.
- **L3 saldo:** `rel_i ≤ R_i`. El exceso `E = max(0, S − T_s)·dt` se reparte
  entre los dueños elegibles en proporción a `R_i`, con topes y **sin
  trasvase**. Lo que no cabe no se libera.
- **L4:** `R` nunca va a `G`, `U`, `remaining_fuel_MJ`, `available_MJ` ni a la
  condición de actividad. No alimenta reignición ni backdraft.
- **L5 O₂ de la liberación:** `0,076·rel_i` por la ruta del fuego, solo
  cuando L2 lo permite. K0 debe seguir cumpliéndose.

[R] Efecto de L2 frente a §7.3 literal (`none`), con el tratamiento
posagotamiento «conservar» (MJ):

| Caso (ON) | §7.3: liberado / `R_final` | §8 (`rate`): liberado / `R_final` | Violaciones K2 con §7.3 |
| --- | ---: | ---: | ---: |
| sofa_vent | 0,9338 / 0 | 0,9338 / 0 | 0 |
| two_active_vent | 0,8731 / 0,1876 | 0,8731 / 0,1876 | 18 |
| low_power_vent | 0,0944 / 0,9755 | 0,0945 / 0,9755 | 2351 |
| o2_closed | 5,4403 / 1,6265 | 0,1803 / **6,8866 (6,3 % de C)** | 1453 |
| o2_closed_dt24 | 5,4462 / 1,6362 | 0,1722 / 6,9102 | 2907 |
| o2_reopen_300 | 8,0428 / 0 | 6,9979 / 1,0449 | 1449 |
| o2_reopen_700 | 7,2838 / 0,3632 | 2,0283 / 5,6186 | 1451 |

Con §8, el `R_final` de la sala cerrada es la energía cuyo calor el filtro
retrasó y que el O₂ nunca permitió liberar. Se **declara** como `R`, separada
de `U`, y no se convierte en gas (§7.2).

### 8.4 `R` posagotamiento: dos tratamientos comparados [R]

**A — conservar sin liberar.** `R` es un artefacto contable del filtro y queda
declarado para siempre. No consume O₂ ni afecta a la extinción. Cuando el
objeto se agota antes de que el filtro drene, `B/C < 1` de forma permanente.

**B — cola finita ligada al objeto.** `R` es inercia de combustión: el objeto
que se agota **ardiendo** sigue quemando lo ya pirolizado con la constante de
bajada del propio filtro, `rel_i = R_i·(1 − e^{−dt/τ_f})`, τ_f = 20 s. La
cola:

- está sujeta a L2 y consume `0,076·rel_i` por la ruta del fuego;
- termina cuando `R_i/τ_f < 0,25·fire_extinction_hrr_kw`, es decir, 2 kW (el
  umbral con que el motor ya anula el HRR, CS l. 1924–1927); el resto, como
  mucho 0,04 MJ, queda declarado;
- si se interrumpe porque L2 falla, **no se reanuda**;
- dura como máximo `τ_f·ln(R_d/(q_min·τ_f))`, y su calor total está acotado
  por `R_d`.

| Caso (ON, `rate`) | `R_d` | A: `R_final` / `B/C` | B: calor de cola / duración | B: `R_final` / `B/C` | O₂ de la cola |
| --- | ---: | ---: | ---: | ---: | ---: |
| low_power_vent (sofá) | 0,9755 | 0,9755 (16,3 % de C) / 0,8372 | 0,9356 MJ / 63,9 s | 0,0399 / 0,9933 | 0,071 kg |
| two_active_vent (sofa_a) | 0,1876 | 0,1876 / 0,9687 | 0,1476 MJ / 30,9 s | 0,0400 / 0,9933 | 0,011 kg |
| sofa_vent | 0 | 0 / 1,0000 | — | 0 / 1,0000 | — |
| casos O₂ | sin agotamiento en 900 s | idénticos | — | idénticos | — |

- En `low_power_vent`, la cola empieza en `R_d/τ_f` = 48,8 kW, sobre un objeto
  de 100 kW.
- [H] Con B, la HRR de la sala sigue siendo > 0 durante la cola. Por debajo de
  8 kW cuenta como «HRR baja» para el temporizador de extinción (CS
  l. 2071–2077), así que la extinción podría retrasarse hasta unos 36 s (lo
  que tarda la cola en bajar de 48,8 a 8 kW con τ_f). Se medirá; no se
  predice.
- **Recomendación: B.** Con A, la misma física da resultados distintos según
  el orden de dos sucesos: si el filtro drena antes de que se agote el objeto,
  `B/C = 1`; si no, `B/C = 0,837`, con las mismas entradas. B está acotada,
  ligada a su dueño y solo usa constantes que ya existen.
- **Brecha declarada:** τ_f = 20 s es una constante del motor **sin fuente
  experimental**. B no es una validación.
- A es la misma especificación sin L1(ii). Con A, K5 exige que el calor
  posagotamiento sea 0.

### 8.5 Problemas separados, visibles, fuera del cierre

Ninguno de estos términos se usa para aparentar que el balance físico cierra:

- `U`: 18,37 MJ en `ON o2_closed`.
- Merma del depósito por decaimiento: 3,67 MJ.
- `R` declarado: hasta un 6,3 % de C.
- Sumidero O2-4: 1,09–2,00×.
- O₂ ausente en el paso de extinción.
- Doble uso en legacy OFF: 2,83 MJ (legacy no se toca).
- `ON o2_closed` no se extingue en 900 s; OFF se extingue a 528,6 s.

### 8.6 Pruebas de falsación (sustituyen a §7.6; tolerancias fijadas ahora)

Tolerancias:

- `STEP_TOL = 1e-9 MJ` por paso y objeto;
- `POWER_TOL = 1e-6 kW`;
- K0: 1e-12 kg absoluta, por encima de la resolución float64 del delta de un
  total acumulado de unos 10 kg (~2e-15 kg).

| Prueba | Mata | Implementación |
| --- | --- | --- |
| K0 O₂ = Thornton × calor | calor sin su O₂ (tope de OES actuando) | `k0_o2_debit_identity` (libros v2 + v3) |
| K1 conservación (F1, F2) | `C_i ≠ B_i + ΔR_i + G_i + U_i`, `R < 0`, retraso sin dueño | `k1_conservation` |
| K2 presupuesto de O₂ | calor por encima del permiso: liberación sin `can_flame`, con `P > T_s` o por encima de `flame_drive·max_hrr_i` | `k2_o2_budget` |
| K3 llama ajena (F5) | `R_i` liberado sin llama propia ni cola propia | `k3_no_foreign_flame` |
| K4 pérdida silenciosa (F1) | salto de `R` entre pasos, dueño que desaparece con saldo, cierre acumulado | `k4_no_silent_loss` |
| K5 posagotamiento acotado (F3) | calor > `R_d`, cola más rápida que `R/τ_f` o más larga que el límite, reinicio | `k5_bounded_post_depletion` |
| K6 = F4 reformulada | liberación o **disminución** de `R` cuando está prohibida (el aumento por A2 es legítimo) | `k6_hold_when_forbidden` |
| K7 `R` al depósito | `G ≠ 0,30·(P − T_s)·dt` con llama (0 en latente) | `k7_no_r_to_pool` |
| F6 paso temporal | 1/12 frente a 1/24 | predicción §8.7 |
| F7 OFF | identidad byte a byte con el interruptor OFF | sin cambios |

Las 17 pruebas sintéticas de `tests/test_g3_option_d_contract.py` matan estas
mutaciones:

- liberar con `flame_drive` bajo;
- liberar con `P > T_s`;
- liberar desde un objeto frío por la llama de otro;
- borrar `R` en silencio;
- eliminar un dueño con saldo;
- una cola sin fin;
- liberar o disminuir `R` cuando está prohibido;
- calor sin combustible;
- retraso sin dueño;
- `R` al depósito;
- O₂ truncado.

[R] Sobre los 16 controles, `rate` pasa K1–K6 con los dos tratamientos
posagotamiento. §7.3 literal falla K2 en 6 de las 8 familias: todas salvo
`sofa_vent` y `sofa_vent_dt24`.

### 8.7 Predicciones pre-registradas para `--tag optd` (antes de implementar)

En los casos ventilados se fija una tolerancia de ±2 % relativo en MJ y ±1 s
en duraciones, por la realimentación que [R] ignora: entre ON y OFF, el `C`
del sofá difiere un 0,03 %. No hay predicción numérica de `R` en la sala
cerrada.

- **sofa_vent:** `R_pico = 0,934 ± 2 %`; `R_final ≤ 1e-6 MJ`; `B/C ≥ 0,999`;
  A y B, idénticos.
- **sofa_vent_dt24:** `R_pico` dentro del 0,3 % del caso con 1/12; `ΣB`
  dentro del 1 %.
- **low_power_vent (B):** `R_d = 0,976 ± 2 %`; calor de cola `0,936 ± 2 %`;
  duración `63,9 ± 1 s`; `R_final ≤ 0,040 MJ`.
- **two_active_vent (B):** `R_d = 0,188 ± 2 %`; cola `0,148 ± 2 %`; duración
  `30,9 ± 1 s`; `R_final ≤ 0,040 MJ`.
- **Casos O₂ (indicativos):** doble uso `Σ min(B − T_s, P − T_s)⁺ = 0 ± 1e-9
  MJ`; K2 sin violaciones; `R` declarado > 0 y constante mientras la
  liberación esté prohibida; `ΣB` no mayor que la `ΣB` de ON.
- **Todos:** K1–K7 sin violaciones; K0 solo en el paso de extinción (defecto
  previo); F7 byte a byte con OFF.

Si una predicción falla, se conserva el resultado y se explica; no se ajustan
parámetros ni tolerancias.

### 8.8 Lo que el libro del motor tendrá que emitir

Por paso y objeto, los campos de `g3_option_d_replay_v1`:

- `C_MJ`, `B0_MJ`, `acc_MJ`, `rel_MJ`, `G_MJ`, `U_MJ`;
- `R_before_MJ`, `R_after_MJ`;
- `release_allowed`, `reason`, `tail_active`;
- `max_hrr_kw`, `state_before/after`.

Por paso:

- `flame_drive`, `can_flame`, `fresh_all_burn`;
- `Ts_kw`, `P_kw`, `pool_generation_MJ`, `unowned_lag_MJ`.

`flame_drive` debe salir del propio motor, no reconstruirse a partir del CSV.

### 8.9 Decisión

**GO a implementar la opción D con el contrato §8.3 y el tratamiento B**, solo
en salas `explicit_owned` y detrás del interruptor existente, que **sigue OFF
en producto**. Condiciones:

- el libro emite los campos de §8.8;
- K0–K7 se ejecutan sobre `--tag optd` y se contrastan con §8.7;
- F7 se cumple byte a byte.

**NO-GO** a activar el interruptor en producto o a presentar el resultado como
validación: la cota L2 es un permiso de potencia derivado del factor de O₂ del
modelo, no un balance de masa de O₂, y τ_f no tiene fuente.

Si el usuario prefiere A, la implementación es la misma sin L1(ii), y K5 pasa a
exigir que el calor posagotamiento sea 0.

## 9. Prototipo de la opción D en el motor (2026-09-30, noche)

Autorización del usuario: implementar D con la cola B detrás de
`fire_explicit_object_fuel_ownership_enabled`, que sigue **OFF en producto**.
No es validación física de CO/FED. `τ_f = 20 s` no está calibrada. Criterio
decisivo: **ninguna liberación nueva de R produce calor sin su débito de O₂**.

Etiquetas: **[M]** medido en el motor, **[C]** código, **[H]** hipótesis.

### 9.1 Caso de estrés de O₂, fijado antes de tocar la física

`o2_stress_cap` (`scripts/simulation/run_g3_optd_controls.py`) es un salón con
la puerta abierta. Por eso usa la ruta bulk, con un tope del 5 % de la masa de
O₂ de la sala por paso. Tiene un objeto de 300 MJ y 3000 kW, α = 0,188 kW/s²,
`dt = 2 s` y 600 s de duración. Se midió con el motor previo, sin cambios
posteriores:

- [M] Motor previo, ON: el tope trunca el débito en 33 pasos (t = 116–180 s),
  con 75,875 MJ de calor sin sus 5,766 kg de O₂. El R reconstruido es
  positivo (22–25 MJ) en los 33.
- [M] Motor previo, OFF (legacy): 43 pasos truncados y 108,1 MJ de calor
  sin O₂. Es un defecto preexistente del tope y se declara aparte.

Qué distingue el caso:

- el permiso de potencia (`flame_drive`, en el libro);
- el O₂ realmente debitado (`room_o2_consumed_fire_kg`, libro v2);
- el calor sólido, el del depósito y el procedente de R (`optd.base_kw`,
  `actual_pool_burn_kw`, `optd.release_MJ`).

`P = T_s` no cuenta como prueba de oxígeno.

### 9.2 Contrato de O₂ implementado [C]

- **Cota de masa**, cuyo dueño es `OxygenExchangeSystem`:
  `fire_sink_heat_acceptance_floor_MJ(room, dt, 0,076)`. Es una cota
  **inferior**, en MJ, del calor cuyo O₂ aceptará `step()` en el mismo tick
  sin que actúe ningún tope. Es conservadora:
  - toma el mínimo entre bulk (`0,05·M·o2` más las entregas diferidas
    negativas) y plume (`0,20·0,15·M·o2_lower·(1 − entr_max·escala_max)`);
  - devuelve 0 en los modos pre-HRR (upper/lower/interface), en phase2b y en
    la ruta lower.

  Los topes de `step()` pasan a constantes con nombre. Mismos valores:
  la identidad OFF lo confirma.
- **Uso en `CombustionSystem`:** liberación total ≤
  `cota − (B0 + B_pool)·dt`. Si no cabe, se reduce y queda en R
  (`mass_limited`).
- **Permiso de potencia del modelo**, que NO es una cota de O₂. Exige a la vez:
  - `can_flame`;
  - no `selected_o2_extinguished`;
  - `P − T_s ≤ 1e-9 kW`;
  - `B_i ≤ flame_drive·max_hrr_kw_i`.

  K2 se renombra `K2_power_permit`.
- **Guarda de extinción:**
  - en una extinción temprana (antes de especies y débito), D no confirma
    nada y el libro anota solo el calor base;
  - si se prevé una extinción tardía (sin combustible tras el débito, o
    `fire_max_active_s` alcanzado), no se libera R.
- **Especies:** usan el HRR aplicado (incluido R). El tope de carbono de las
  especies suma el carbono de la liberación. `c_burned_total` sigue contando
  el carbono una sola vez, al debitarse.
  Los diagnósticos SF-CBAL `c_preclamp_excess_kg` y `c_postclamp_excess_kg`
  siguen comparando con el carbono del combustible del paso, un contrato fijado
  por `tests/test_carbon_balance.py`. En los pasos con liberación de R incluyen
  el carbono diferido de R (declarado). `c_balance_frac` usa la cota con R.
- **Débito de O₂:** OES aplica `hrr_kw = ΣB_i + B_pool`, que incluye R.

Implementación: `FuelObjectModel` (`g3_r_balance_MJ`, `g3_r_tail_state`),
`CombustionSystem` (`_g3_allocate_owned`, `_g3_option_d_step`,
`_g3_note_uncommitted`, `_g3_apply_owned`, `_g3_end_tails`),
`OxygenExchangeSystem` y `SimulationEngine` (clave de contexto solo con el
interruptor). **Efecto de orden declarado:** la asignación del débito se
evalúa antes de las especies. En ON, los rendimientos ponderados por
precalentamiento ven la superficie ya actualizada en el mismo paso.

### 9.3 Resultados del motor sobre el código final (`runs/g3_optd_final_on_20260930_210047`; idénticos a `g3_optd_optd_on_20260930_192337`) [M]

| Caso | C | B | B/C | R_pico | R_final | Liberado | Pasos con cota de masa | K0: pasos truncados |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| sofa_vent | 2,9990 | 2,9990 | 1,000000 | 0,9338 | 0 | 0,9338 | 0 | 0 |
| sofa_vent_dt24 | 2,9990 | 2,9990 | 1,000000 | 0,9353 | 0 | 0,9353 | 0 | 0 |
| two_active_vent | 5,9985 | 5,9586 | 0,993352 | 1,0607 | 0,0399 | 1,0208 | 0 | 0 |
| low_power_vent | 5,9945 | 5,9546 | 0,993339 | 1,0699 | 0,0399 | 1,0299 | 0 | 1 extinción (9,8 J, sin R) |
| o2_closed | 109,5049 | 82,1149 | 0,749875 | 20,6014 | 20,6014 | 0 | 0 | 0 |
| o2_closed_dt24 | 109,5109 | 82,0621 | 0,749351 | 20,8125 | 20,8125 | 0 | 0 | 0 |
| o2_reopen_300 | 119,9958 | 118,7431 | 0,989560 | 8,0440 | 1,2205 | 6,8235 | 0 | 1 extinción (6,0 J, sin R) |
| o2_reopen_700 | 119,0155 | 97,7628 | 0,821429 | 16,6984 | 14,5901 | 2,1084 | 0 | 0 |
| **o2_stress_cap** | 299,9990 | 299,9606 | 0,999872 | 29,4063 | 0,0384 | 29,3679 | **7** | **33 de calor base (75,875 MJ), 0 con R** |

(Valores en MJ.) Cierre acumulado `C − B − ΔR − G − U` ≤ 6e-14 MJ.

K1, K3–K7 y K9 dan 0 violaciones en los 9 casos. K2 también da 0. K8 da 0.
**K0R (liberación en paso truncado) = 0 en los 9**, incluido el estrés.

La primera tanda (`…_190330`) no se usa para el veredicto. Destapó un defecto
real: D confirmaba R en pasos que acababan en extinción temprana. Eso producía
residuos de K1 de ~1e-5 MJ y una liberación de R dentro de la excepción de
extinción en `o2_reopen_300`. Se corrigió (§9.2, guarda de extinción) y se
repitió la tanda completa.

### 9.4 Predicciones (§8.7 y §9.1) frente al motor [M]

52 de 56 pasan. Fallan cuatro, que se conservan:

- **two_active R_d:** 0,1926 frente a 0,188 ± 2 % (+2,5 %).
- **two_active cola:** 0,1528 frente a 0,148 ± 2 % (+3,2 %). La duración
  (31,5 s) y `R_final ≤ 0,040` sí pasan.

  Causa [M/H]: en el motor, `sofa_a` se agota 0,17 s antes que en la
  trayectoria exógena (98,17 s frente a 98,33 s), por la realimentación que la
  reconstrucción ignora. Queda refutado que la reconstrucción exógena baste a
  ±2 % para objetos de 50 kW.
- **ΣB ≤ ΣB de ON-pre en o2_reopen_300 y o2_reopen_700:** 118,74 frente a
  112,03, y 97,76 frente a 96,42. Mi propia reconstrucción ya daba 118,92 en
  `o2_reopen_300`, así que la desigualdad era incoherente con ella. Queda
  refutado que D nunca libere más calor que ON-pre con O₂ limitante: al
  reabrir, D devuelve el retraso que ON-pre destruía.

Pasan, entre otras:

- sofá: R_pico 0,9338 (predicción 0,934 ± 2 %), R_final 0 y B/C 1,000000;
- dt 1/24: R_pico +0,16 % y ΣB −0,0001 %;
- low_power: R_d 0,9755, cola 0,9356 MJ en 63,9 s y R_final 0,0399;
- casos O₂: doble uso 0, K2 0 y K6 0.

No hubo predicción numérica para `o2_closed`: R = 20,6 MJ (19 % de C),
frente a 6,9 MJ reconstruidos. El calor es el mismo que en ON-pre
(82,11 MJ). La diferencia es que el calor que antes se contaba dos veces ya
no alimenta el filtro, así que los repuntes acumulan más retraso, y este se
declara.

### 9.5 Identidad OFF y mutaciones [M]

- **F7:** en los 9 casos OFF del código final (`runs/g3_optd_final_off_20260930_211954`; también `g3_optd_optd_off_20260930_194200`)
  frente a `g3_energy_pre_off_20260930_171424` y
  `g3_optd_pre_off_20260930_185108`), estos archivos son **idénticos byte a
  byte**: `sim_log.csv`, `sim_log.txt`, `events.json`,
  `fuel_object_state_snapshot.json`, los libros v2 y v3,
  `co_inventory_trace.jsonl` y `scenario.json`. `summary.json` solo difiere
  en `output_dir`.
- Ningún escenario, perfil ni escena activa el interruptor; solo aparece en
  `SimulationEngine.gd` (valor por defecto `false`) y en
  `CombustionSystem.gd`.
- **Mutaciones** (`scripts/simulation/run_g3_optd_mutations.py`): 5 de 5
  detectadas por la prueba que buscan. `CombustionSystem.gd` quedó restaurado
  con SHA-256 verificado.

  | Mutante | Prueba que lo detecta | Violaciones |
  |---|---|---:|
  | MD1, pérdida silenciosa de R | K4 | 2 |
  | MD2, liberación por llama ajena | K3 | 767 |
  | MD3, cola ilimitada | K5 | 4433 |
  | MD4, doble uso | K9 (también K6) | 4517 |
  | MD5, sin cota de masa de O₂ | **K0R** (también K8) | 14 |

  MD5 demuestra que, sin la cota de masa, el caso de estrés libera R en 14
  pasos truncados: calor nuevo sin O₂.
- El mutante antiguo `M3` de `run_g3_fuel_ownership_mutations.py` apunta al
  tope `min(P, cap)`, que ya no existe. Lo sustituyen MD4 y MD5.

### 9.6 Límites que no cierra este trabajo

- **El débito garantizado es el sumidero de OES, no la masa zonal.** [M] En
  `o2_closed`, el inventario `air_mass·o2` de la sala no cierra con los flujos
  registrados: baja entre 0,73 y 0,97 veces el débito del fuego por ventana,
  con residuos de hasta 0,55 kg. En la ruta plume, `step()` aplica el débito
  sobre una base de masa ambigua (H3.2-S0d6). Afecta a todo calor, no solo a
  R, y queda abierto con O2-4 y E1.
- Siguen abiertos:
  - O2-4 (sumidero alto: 1,09–2,00×);
  - `U`;
  - la merma del depósito;
  - el calor base truncado por el tope (75,9 MJ en el estrés);
  - la excepción de extinción: previa ≤ 15,12 J; con D ≤ 9,8 J y sin R;
  - la calibración de `τ_f`.
- La cota de masa es conservadora. Puede retener R que la ruta real habría
  aceptado, pero nunca liberar R sin O₂.

### 9.7 Suites (R2-1) sobre el código final [M]

SHA-256 de los cuatro archivos de `sim/` verificados antes y después de toda la
cadena.

- **Referencia completa, a través del monitor seguro**
  (`scripts/simulation/run_reference_suite_monitored.py`):
  - replica `run_reference_checks.ps1`, pero cada caso se lanza con
    `tools.mutation_audit._run_monitored`, con ≥ 6 GiB libres y sin cuadros
    previos;
  - 18/18 casos con salida 0 e informe nuevo; 3282 s; mínimo 7,1 GiB libres;
  - **346/346 comprobaciones requeridas, 78 gaps**;
  - `reference_checks.json` solo cambia en `generated_at`: las métricas son
    idénticas a las del inicio de la sesión.
- **Guardarraíles científicos:** ALL PASS, incluido `Reports freshness
  (R2-1)`.
- **pytest global:** 3088 passed, 35 skipped, 2 xfailed, 42 subtests, 0
  fallos.
  - La primera pasada, con el código anterior, dio 3 fallos de pruebas
    estáticas (`test_carbon_balance` ×2 y `test_phase3_f31c`). Fijaban el texto
    de los diagnósticos SF-CBAL y el literal `lower_frac < 0.15` que yo había
    cambiado.
  - Se restauró el contrato del código, **no** las pruebas, y se repitió todo:
    tandas ON/OFF, mutaciones, referencia y pytest.
- **`check_product.py`: NO ejecutado.** Lanza Godot con `subprocess.run`
  directo, y su prueba de humo llama a `scripts/run_scenario.py`, que tampoco
  usa el monitor. Esta fase exige lanzar Godot solo mediante el monitor seguro
  (deuda ya declarada en el handoff del 2026-09-29). No se improvisó otro
  lanzamiento.
- Al terminar: ningún proceso Godot, ningún cuadro de error, 7,19 GiB libres.

### 9.8 Decisión

Criterios técnicos cumplidos por el motor real:

- conservación por objeto;
- K0–K9, con **K0R = 0 también en el caso de estrés**;
- mutaciones 5/5;
- identidad OFF 9/9;
- referencia, guardarraíles y pytest global.

La cota de masa de O₂ garantiza el criterio decisivo: ninguna liberación de R
cae en un paso truncado. Sin ella, MD5 lo viola en 14 pasos.

**La fase no se declara cerrada: GO técnico pendiente de `check_product.py`**,
la única suite exigida que no pudo ejecutarse solo con el monitor seguro.
Para cerrarla hace falta una de estas dos cosas:

- un `check_product` con lanzador monitorizado;
- una autorización expresa para ejecutarlo como en pasadas anteriores.

El prototipo sigue OFF en producto y **no** es validación de CO/FED.

Quedan abiertos:

- O2-4;
- `U`;
- la merma del depósito;
- el calor base truncado por el tope de OES;
- la masa zonal de O₂ no autoritativa;
- la calibración de `τ_f`;
- 4 predicciones refutadas (§9.4).

## 10. Cierre de Gate B como prototipo técnico (2026-10-01)

Etiquetas: **[M]** medido, **[C]** leído en el código, **[I]** inferencia
apoyada en medidas, **[H]** hipótesis. No se ha tocado `sim/`: el parche sin
commit de `sim/` y de `reference_checks.json` es idéntico byte a byte al del
inicio de la sesión.

### 10.1 Lanzamientos de Godot alcanzables desde `check_product.py` [C]

| Ruta | Antes | Ahora |
|---|---|---|
| `_run_godot_scene` (38 escenas) | `subprocess.run` | `_run_godot_check` → lanzador monitorizado |
| `_run_godot_script` (42 scripts) | `subprocess.run` | `_run_godot_check` → lanzador monitorizado |
| `_run_run_scenario_smoke` → `python scripts/run_scenario.py` → `res://tools/run_scenario_headless.tscn` | `subprocess.run` en `run_scenario.py` | `run_scenario.py` → lanzador monitorizado |

Las cinco suites Python y `check_gdscript_style.py` no arrancan Godot.

`scripts/godot_monitored_launch.py` es el único punto de lanzamiento y solo
envuelve `tools.mutation_audit._run_monitored`:

- **Estado previo:** si antes de lanzar hay un cuadro de error o un proceso de
  Godot, no se arranca nada y se informa como previo. El proceso previo
  importa porque el monitor mata, al terminar, todo proceso `Godot*` que
  encuentre: un editor abierto moriría como «residuo».
- **Fallos de la ejecución**, con independencia del código de salida: cuadro
  nuevo, timeout, proceso residual, violación de acceso, inventario de
  procesos incompleto y ventana de observación incompleta.
- `check_product.py`: comprobación previa en `main` (no lanza nada), una
  comprobación final «sin procesos ni cuadros al terminar» y código de salida
  distinto de cero para toda comprobación que no valga. Antes, una salida 0
  sin token o con un script que no compila se anotaba como fallo pero la tabla
  la contaba como pasada: hueco preexistente, cerrado aquí.
- `run_scenario.py`: mismos mensajes y códigos; añade `monitor.health.json` a
  la salida. Ya no importa `subprocess`.
- `SIMUFIRE_GODOT_HEALTH_LOG` (opcional) anota un JSON por lanzamiento, también
  los anidados.

### 10.2 Pruebas sin Godot [M]

`tests/test_check_product_monitored_launch.py`: 55 pruebas. Usan el bucle real
del monitor con un hijo Python inofensivo, o `check_product.main` completo con
el monitor simulado. En ambos casos, un comando de Godot que llegue a
`subprocess` por otro camino lanza una excepción.

- cuadro previo y proceso previo: no se lanza y se informa como previo;
- cuadro nuevo, también tras una salida 0 con el token: fallo;
- fallo del proceso: fallo, con su código de salida;
- timeout y proceso residual: nunca PASS;
- ejecución limpia: resultado y comando esperados;
- ruta anidada: `run_scenario.main` lanza por el monitor y falla en los mismos
  casos; en `main`, los 80 + 1 lanzamientos pasan por el monitor en orden.

Regresiones reales: 18 mutaciones temporales del código (vuelta a
`subprocess.run` en cada script, ignorar los fallos del monitor, quitar cada
bloqueo previo, tratar el timeout como salida normal, etc.) y las 18 rompen
alguna prueba. Los tres archivos quedaron restaurados con SHA-256 verificado.

### 10.3 `check_product.py` por la ruta monitorizada [M]

`runs/check_product_monitored_20261001_134706`, desde Claude Code y sin el
sandbox de Codex. Antes de lanzar: 6,63 GiB disponibles, ningún cuadro y ningún
proceso Godot.

- Salida 0, **ALL PRODUCT CHECKS PASS (168 tests)**, 88 filas, 10 min 3 s.
- 81 lanzamientos anotados = las 80 comprobaciones declaradas en `main`, en su
  orden, más el anidado de `run_scenario.py`.
- Los 81: salida 0, sin timeout, sin cuadros, sin residuos, 0 procesos
  terminados por limpieza, interfaz de errores de Windows suprimida y
  `_runtime_health_errors` vacío.
- Al terminar: ningún proceso Godot, ningún cuadro, 6,72 GiB disponibles.

### 10.4 Por qué `o2_closed` da R = 20,60 MJ y la reconstrucción daba 6,89 MJ

Libros: `runs/g3_energy_pre_on_20260930_172851/o2_closed` (ON-pre, la
trayectoria que la reconstrucción tomó como exógena) y
`runs/g3_optd_final_on_20260930_210047/o2_closed` (motor con D). Herramienta de
solo lectura: `scripts/simulation/analyze_g3_optd_r_feedback.py`. Diferencia a
explicar: 20,6014 − 6,8866 = **13,7149 MJ**.

| Parte | MJ | Clase | Cómo se mide |
|---|---:|---|---|
| Orden de aplicación / contabilidad | −5e-14 | [M] | reconstrucción de la trayectoria del propio motor D con su `flame_drive`: R = 20,601428; por paso, la acumulación difiere ≤ 1,7e-16 y la liberación 0 |
| `flame_drive` reconstruido del CSV de 1 s | +0,1803 | [M] | la misma reconstrucción con el `flame_drive` del CSV libera 0,1803 MJ que el motor niega (`power_permit`, 1039 pasos), todo antes de t = 293 s |
| Cota de masa de O₂ | 0 | [M] | 0 pasos `mass_limited` de 10 800; holgura mínima 2,517 MJ por paso frente a 0,158 MJ de exceso del filtro en toda la ejecución |
| Trayectoria (realimentación) | +13,5346 | [M] | reconstrucción sobre la trayectoria D menos reconstrucción sobre ON-pre, ambas con `flame_drive` del CSV |

Suma: 13,7149 MJ.

La parte de trayectoria, desglosada:

- [M] Las dos ejecuciones son idénticas hasta t = 293,25 s. Ese es el primer
  paso en que ON-pre libera calor por encima de `T_s`. Hasta ahí, R = 5,429 MJ
  en el motor y 5,249 MJ en la reconstrucción.
- [M] Después: el motor acumula 15,172 MJ y la reconstrucción 1,637 MJ.
- [M] Identidad `R_final = Σ T_s·dt − B`: `Σ T_s·dt` sube 18,215 MJ (84,501 →
  102,716) y el motor quema 4,500 MJ más que la reconstrucción (82,115 frente
  a 77,615). 18,215 − 4,500 = 13,715.
- [M] `B` no cambia entre ON-pre y D (82,117 y 82,115 MJ), ni el O₂ del fuego
  (6,2409 y 6,2407 kg): el calor total lo fija el inventario de O₂ de la sala.
  La reconstrucción restaba el retraso de un calor que la sala sí quema.
- [M] Desde 360 s, el `flame_drive` de D queda clavado en el umbral de
  `can_flame` (0,08): percentiles 10–90 entre 0,080000 y 0,080078. La llama se
  apaga 86 veces y vuelve en 0,60 s de media; pasa 488 s encendida. En ON-pre
  se apaga 6 veces y tarda 77,8 s en volver; pasa 73 s encendida.
- [M] En cada apagado, el calor aplicado de D cae de 16,9 a 0,08 kW en un
  paso (`B0 = min(filtro, T_s)`), y el filtro vuelve a subir desde ahí con
  τ = 10,8 s hacia un `T_s` medio de 43,7 kW. En ON-pre sigue en 35,4 kW y cae
  con τ = 20 s. La variación ascendente de `T_s` es 4399 kW en D y 754 kW en
  ON-pre.
- [I] Mecanismo: con D, al cruzar el umbral se corta el calor, deja de
  consumirse O₂ y la llama vuelve enseguida; cada reencendido acumula el
  retraso de subida y nunca hay exceso que liberar (0,158 MJ en total). En
  ON-pre el calor sigue cayendo por encima de `T_s`, consume O₂ y la sala
  tarda en volver. Es realimentación de O₂ a través de un umbral discontinuo.
  Coherente con las medidas: 86 ciclos de 5,6 s dan ≈ 16 MJ. No se ha aislado
  con una ejecución de control.
- [M] Canal directo de temperatura (`rad_feedback` sobre `T_s`): ≤ 0,012 MJ.
  Entre 293 y 699 s el HRR ideal está en el tope de potencia de los objetos,
  y desde 699 s lo reduce la fracción de combustible (< 0,15), con
  `rad_feedback` ≤ 1,0017.
- [H] Efecto indirecto de la temperatura sobre el O₂ zonal: no separable con
  estos libros. La capa superior difiere menos de 10 °C tras la divergencia.

`o2_closed_dt24` repite el cuadro: 20,8125 frente a 6,9102 MJ; orden −4e-15,
`flame_drive` +0,1722, cota de masa 0 y trayectoria +13,7301 MJ.

Consecuencia: 15,2 de los 20,6 MJ de R de la sala cerrada miden el ciclo
límite del modelo en el umbral `can_flame`, no combustión retrasada de un
objeto. No se ajusta ninguna constante ni predicción.

### 10.5 Suites sobre el estado final [M]

- Focalizadas: 68 passed (55 nuevas, `test_run_scenario_fail_closed` 10,
  `test_godot_monitor_stale_dialogs` 3).
- pytest global: 3143 passed, 35 skipped, 2 xfailed, 42 subtests, 0 fallos
  (3088 + 55).
- Guardarraíles científicos: ALL PASS, 346/346, 78 gaps, `Reports freshness
  (R2-1)` PASS. La referencia no se regenera: `sim/` no cambia.
- `git diff --check`: limpio.

### 10.6 Decisión

**Gate B se cierra como prototipo técnico:** `check_product.py` da PASS de
forma monitorizada, todas sus rutas de Godot pasan por el monitor, las pruebas
negativas fallan por la causa prevista y no quedan procesos ni cuadros.

**Sigue NO-GO activar la opción D en producto, y esto no es validación física
de CO/FED.** Se suma un motivo: en sala limitada por O₂, R crece por el ciclo
del umbral `can_flame` (§10.4).

Límites que quedan:

- los de §9.6 y §9.8;
- el monitor mata todo proceso `Godot*` al terminar un lanzamiento: abrir el
  editor durante una tanda lo cierra, y con el editor abierto `check_product`
  y `run_scenario` se niegan a lanzar;
- `check_product.py` no comprueba la memoria disponible; la compuerta de
  6 GiB se aplicó desde fuera;
- el mecanismo [I] y el efecto [H] de §10.4 no están aislados con una
  ejecución de control.

## 11. Monitor con propiedad de procesos y ciclo de llama (2026-10-01, tarde)

Etiquetas como en §10. `sim/` sigue sin tocar. La opción D sigue OFF y en
NO-GO para producto; nada de esta sección ajusta la física ni reduce `R`.

### 11.1 El monitor solo termina lo que lanzó [C]

Corrige el primer límite de §10.6. Hasta ahora, la limpieza de
`mutation_audit._run_monitored` hacía `taskkill` sobre todo proceso cuyo
nombre empezara por `Godot`, en tres sitios: cuadro de error, timeout y
residuo tras la salida. Era el único sitio del repositorio que mataba por
nombre.

- El proceso se crea suspendido, entra en un **Job Object** de Windows y se
  reanuda. El núcleo añade al job a todos sus descendientes. La única forma
  que tiene el monitor de matar algo es terminar ese job.
- El job se cierra al acabar el lanzamiento y también si muere el Python que
  vigila (`KILL_ON_JOB_CLOSE`): un Godot ya no queda huérfano si se mata a
  `run_scenario.py` desde fuera.
- Si no puede establecerse la propiedad, no se ejecuta nada.
- Un Godot visto por nombre que no está en el job es **ajeno**: no se termina.
  Se anota en `foreign_godot_processes` y la ejecución se da por contaminada,
  porque un cuadro de error se detecta por título y no se puede atribuir a un
  proceso.
- Un descendiente propio que sobrevive al proceso lanzado tiene un plazo de
  120 s para acabar. Si lo agota, se termina y se informa como residuo,
  también cuando retiene la salida.
- [M] El plazo existe porque el propio motor lanza ayudantes al salir
  (`cmd.exe /c python` para las gráficas, `SimulationEngine._exit_tree`),
  salvo en modo validación o con `suppress_exit_graphs()`. El monitor anterior
  no los veía. Medido: `validate_single_interior_transport_owner.gd` crea 61
  procesos y sus ayudantes tardan 35,1 s en acabar tras salir Godot;
  `p1r8_o2_owner_contract.gd`, 13 procesos y 7,0 s. Con una ventana fija de
  2 s, dos pruebas del pytest global fallaban de forma intermitente por
  ayudantes aún vivos. El Python de esos ayudantes no aparece en el job: solo
  se ven `cmd.exe` y `conhost.exe`.
- El bloqueo inicial ante un cuadro o un Godot previos no cambia, y no toca al
  proceso previo.
- El contrato de salud conserva su nombre (`windows-window-process-exit-v2`):
  el auditor de mutaciones lo valida literalmente en informes ya guardados.
  Los campos nuevos son aditivos.

### 11.2 Memoria de 6 GiB [C]

`check_product.py` no aplica el umbral por sí mismo. El ejecutado en §10.3
dependió de una comprobación externa, hecha una vez antes de empezar.

Ahora es opcional y por lanzamiento: con
`SIMUFIRE_GODOT_MIN_AVAILABLE_GIB=6`, cada lanzamiento, incluido el anidado
de `run_scenario.py`, se niega por debajo de ese valor. Sin la variable no hay
compuerta. No se impone por defecto: los tres flujos de CI (Ubuntu, Python
3.11) no ejecutan `check_product.py`, pytest ni el monitor, y la memoria solo
se mide en Windows.

### 11.3 Línea temporal común de `o2_closed` [M]

`scripts/simulation/analyze_g3_optd_flame_cycles.py` (solo lectura) escribe
`runs/g3_flame_cycle_control_20261001/timeline_1s.csv` (901 filas, ambas
ramas) y `cycles_optd.csv`. El O₂ seleccionado por paso de la rama D se
reconstruye invirtiendo el `flame_drive` del libro; difiere del CSV menos de
1,8e-5.

| Instante | ON-pre | D |
|---|---|---|
| 293,25 s | primer calor por encima de `T_s` | idéntica hasta aquí; `R` = 5,4294 MJ |
| primer apagado | 362,17 s | 372,67 s |
| primer reencendido | 494,92 s (132,75 s después) | 416,17 s (43,5 s después) |
| apagados hasta 900 s | 6 | 86 |
| O₂ seleccionado desde 480 s | 0,11199–0,11298 | 0,11261–0,11264 |
| O₂ superior, 480 → 900 s | 0,11376 → 0,11248 | 0,11512 → 0,11262 |
| capa superior, 480 → 900 s | 41,3 → 29,6 °C | 48,5 → 31,6 °C |

El O₂ al que `factor(x)·flame_possible(x) = 0,08` es 0,11263: en D, el O₂
seleccionado queda clavado en el valor del umbral.

### 11.4 `R` por ciclo: la cifra de 15,2 MJ [M]

- `R` nacido tras la divergencia: **15,1720 MJ**, entero dentro de los 86
  ciclos y entero en los tramos encendidos. Liberado: 0. Entre 293,25 y
  416,17 s no nace nada.
- Por ciclo: mediana 0,2008 MJ (cuartiles 0,1908–0,2038; máximo 0,4948 en el
  primero, de 30,75 s).
- Tramo encendido: mediana 5,50 s. Tramo apagado: **un paso** de mediana
  (máximo 5 pasos). El `flame_drive` baja a 0,079992–0,080000 y vuelve a
  0,080000–0,080054.
- En el tramo encendido `T_s` = 48,0 kW (600 kW × 0,08) y el calor aplicado
  sube desde ≈0 siguiendo el filtro: a los 5,42 s va por 18,94 kW. Después de
  699 s `T_s` baja con la fracción de combustible y los ciclos se alargan
  hasta ≈10 s.
- La forma cerrada `Σ T_s·τ·(1 − e^{−L/τ})` con τ = 10,8 s da 15,239 MJ
  (+0,4 %).
- Por ciclo, el débito de O₂ del fuego iguala el O₂ neto exterior: mediana
  0,99991 (cuartiles 0,980–1,016). El exterior aporta 0,76–0,77 g/s, lo que
  sostiene 10,1 kW; el calor medio medido es ese.
- `o2_closed_dt24`: 97 ciclos, 15,3718 MJ, apagados de un paso (0,042 s),
  tramo encendido de 5,375 s de mediana.

### 11.5 Controles predeclarados y su resultado

Predeclaración escrita antes de ejecutar:
`runs/g3_flame_cycle_control_20261001/PREDECLARATION.md`. Hipótesis: H1
(discontinuidad de `can_flame` + recorte de D + realimentación de O₂), H2
(oscilación exógena del O₂), H3 (artefacto del paso), H4 (retraso genérico
del filtro).

**Control A — contabilidad exacta del motor, entrada fijada [M].** La
reconstrucción que reproduce el libro D (§10.4), con el `flame_drive` medido
levantado a `0,08 + 1e-9` en los 101 pasos en que está por debajo desde
416,17 s. La mayor corrección es 8,05e-6. Lazo abierto.

| | `R` nacido desde 416,17 s |
|---|---:|
| `flame_drive` medido | 15,1720 MJ |
| sin cruces del umbral | 0,4573 MJ |
| atribuible a los cruces | **14,7148 MJ (97,0 %)** |

Predicho con H1: < 1,5 MJ. Predicho con H4: > 12 MJ. **Discrimina: H4 queda
refutada.** Límite: es lazo abierto; sin cruces el calor sería 20,6 MJ en vez
de 5,5 MJ, que el suministro de O₂ no sostiene.

**Control B — arnés en lazo cerrado, suministro fijado.** Ecuaciones del
motor en el lado del fuego y un integrador del exceso de O₂ alimentado por el
O₂ neto exterior medido (medias de 60 s). Sin parámetros ajustados. Desde el
segundo reencendido (447,0 s).

| Prueba | Motor | Arnés | Tolerancia predeclarada | |
|---|---|---|---|---|
| B0, `dt/12`: apagados | 84 | 74 (−11,9 %) | ±15 % | pasa |
| B0: `R` nacido | 14,677 MJ | 14,709 MJ (+0,2 %) | ±10 % | pasa |
| B0: mediana encendido | 5,50 s | 5,33 s (−3,0 %) | ±10 % | pasa |
| B1, `dt/24`: apagados | 95 | 74 (−22,1 %) | ±15 % | **falla** |
| B1: `R` nacido | 14,876 MJ | 14,866 MJ (−0,1 %) | ±10 % | pasa |
| B1: mediana encendido | 5,375 s | 5,33 s (−0,8 %) | ±10 % | pasa |

Intervenciones en el arnés:

- **B2, sin reinicio:** predicho ≤ 15 apagados y apagado medio ≥ 20 s.
  Resultado: 178 apagados, apagado medio 2,2 s. **Predicción fallida.** El
  arnés no reproduce el comportamiento de ON-pre (6 apagados, 77,8 s).
- **B3, objetivo continuo:** `R` nacido 0,40–0,49 MJ para masas de 5 a 60 kg
  (predicho < 1,5: se cumple). La convergencia del calor al suministro solo
  se cumple con 20 kg (10,3 frente a 10,1 kW); con 40 y 60 kg no converge en
  el intervalo (15,4 y 19,0 kW).
- **B4, O₂ congelado:** 0 apagados y 0,516 MJ (se cumple).

Con la regla predeclarada, el fallo de B1 en el recuento y el de B2 invalidan
el arnés como discriminante: le faltan el retardo de `o2_hrr_factor` y la
masa de la zona, que en ON-pre deciden cuánto tarda la llama en volver.

### 11.6 Veredicto

- **Contribución de los cruces del umbral a `R`: demostrada en la
  contabilidad exacta del motor** (control A): 14,71 de los 15,17 MJ. El resto
  (0,46 MJ) es la primera subida. En lazo abierto.
- **Causa del ciclo: mecanismo compatible, causalidad no aislada.** El
  control en lazo cerrado no superó su propia validación.
- Hechos del motor que sí acotan las hipótesis [M]:
  - ON-pre y D solo difieren en el código de la opción D y pasan de 6 a 86
    apagados;
  - a `dt/2` los apagados pasan de 84 a 95 (+13 %), no al doble: H3 no
    explica el ritmo. Lo que sí es numérico es la duración del apagado, un
    paso;
  - el O₂ seleccionado queda en el valor exacto del umbral y cada ciclo cierra
    su balance de O₂.
- [I] Lectura conjunta: el objetivo no puede tomar valores entre ≈0 y 48 kW,
  el suministro solo da para 10 kW, y D reinicia el filtro en cada apagado.
  Coherente con todo lo anterior; no aislado.

### 11.7 Experimentos de motor propuestos, no ejecutados

1. **Sin editar `sim/`.** Repetir `o2_closed` con D y un solo parámetro
   existente cambiado en el escenario de diagnóstico: `fire_hrr_rise_tau_s`
   de 6 a 3 s (τ efectiva 5,4 s). Con H1, el balance de O₂ predice tramos
   encendidos de ≈2,75 s y unos 165 apagados; con H2, los mismos instantes de
   cruce. Coste: dos ejecuciones monitorizadas; no afecta a R2-1. Cambia una
   constante en un escenario de diagnóstico, así que necesita autorización.
2. **Editando `sim/`.** Una clave de diagnóstico, OFF por defecto, que haga
   continuo el objetivo de llama bajo el umbral. Con H1: 0 apagados tras
   416 s y `R` final ≈ 5,9 MJ con el mismo calor total. Coste de R2-1:
   referencia completa por el monitor (18 casos, ≈55 min), identidad OFF 9/9
   y tanda ON (≈30 min), mutaciones MD1–MD5, pytest, `check_product.py` y el
   alta de la clave en el inventario de interruptores. Unas dos horas de
   máquina.

Ninguno convierte un `R` menor en prueba de mayor realismo: miden la causa.

### 11.8 Pruebas, mutaciones y suites [M]

- `tests/test_godot_monitor_process_ownership.py` (13, sin Godot): procesos
  Python inofensivos hacen de proceso lanzado y de descendientes, y un proceso
  vivo de la propia prueba hace de Godot ajeno (el escaneo por nombre está
  guionizado y solo devuelve pids creados por la prueba).
  - descendiente propio colgado, con y sin la salida retenida: se limpia y se
    informa;
  - ayudante propio que acaba a tiempo: se le espera y no se mata;
  - Godot ajeno que aparece tras el lanzamiento: sobrevive y la ejecución
    queda contaminada, también con cuadro de error o timeout;
  - cuadro nuevo: la ejecución falla y solo muere el árbol propio;
  - cuadro o Godot previo: bloqueo inicial, sin tocar el proceso previo;
  - sin propiedad no se ejecuta nada.
- `tests/test_check_product_monitored_launch.py` pasa de 55 a 61: descendiente
  propio y Godot ajeno reales, y la compuerta de memoria opcional.
- Mutaciones: 31 de 31 detectadas en la primera pasada (13 nuevas + las 18 de
  §10.2) y 15 de 15 sobre el monitor final (K01–K14 y M17). Las tres que
  restauran la limpieza por nombre (cuadro, timeout y residuo) mueren porque
  el Godot ajeno de la prueba deja de estar vivo. Archivos restaurados con
  SHA-256 verificado.
- Focalizadas: 87 passed (13 + 61 + 10 + 3).
- pytest global: 3162 passed, 35 skipped, 2 xfailed, 42 subtests, 0 fallos.
- `check_product.py` monitorizado con la compuerta de 6 GiB por lanzamiento
  (`runs/check_product_monitored_20261001_170331`): salida 0, **168 tests**,
  88 filas, 10 min 28 s. 81 lanzamientos, todos bajo Job Object, sin cuadros,
  timeouts, residuos ni procesos ajenos, y 0 procesos terminados. En 5
  lanzamientos el motor dejó ayudantes; el monitor los esperó 54,3 s en total
  (el mayor, 61 procesos y 12,1 s).
- Guardarraíles: ALL PASS, 346/346, 78 gaps, R2-1 PASS. `git diff --check`
  limpio. Al terminar: ningún proceso Godot, ningún cuadro, 6,8 GiB.

## 12. Experimento 1: `o2_closed` con `fire_hrr_rise_tau_s` = 3 s (2026-10-01, noche)

Experimento 1 de §11.7, autorizado por el usuario. Un único cambio en el
escenario diagnóstico: `fire_hrr_rise_tau_s` 6 → 3 (τ efectiva de subida
10,8 → 5,4 s). `sim/` no se toca; la opción D sigue OFF en producto. Evidencia
en `runs/g3_rise_tau_diagnostic_20261001/`; la predicción
(`PREDECLARATION.md`) se escribió antes de lanzar.

### 12.1 Cómo se ejecutó [M]

- **D:** motor actual, `scripts/simulation/run_g3_rise_tau_diagnostic.py`.
- **ON-pre:** el motor anterior a D ya no está en el worktree. Se usó una
  copia diagnóstica del proyecto (`onpre_project/`, 71 MB) con
  `CombustionSystem.gd` sustituido por la instantánea previa a D
  (SHA-256 `560ae0a1…`, del historial de archivos de la sesión que implementó
  D). De 182 scripts de `sim/` y `tools/`, solo ese difiere.
- **Validación de la copia:** a τ = 6 reproduce **byte a byte** los ocho
  archivos de `runs/g3_energy_pre_on_20260930_172851/o2_closed` (CSV, libros
  v2 y v3, trazas). Es el motor ON-pre.
- Tres lanzamientos en secuencia por el monitor, con ≥ 6,57 GiB: salida 0,
  sin cuadros, timeouts, residuos ni procesos ajenos.
- El cambio actuó: el filtro del libro D sigue una subida de 5,4 s con
  residuo 0; con 10,8 s el residuo es 0,37 kW. Las corridas difieren de sus
  controles desde el primer paso.

### 12.2 Opción D: τ = 6 frente a τ = 3 [M]

| Observable | τ = 6 | τ = 3 | Predicho con H1 | |
|---|---:|---:|---:|---|
| Mediana del tramo encendido | 5,50 s | **2,75 s** | 2,75 s ±15 % | cumple |
| Apagados desde el 2.º reencendido | 84 | **158** | ≈165 ±20 % | cumple |
| Duración del apagado (mediana) | 1 paso | 1 paso | 1 paso | cumple |
| `R` por ciclo (mediana) | 0,2008 MJ | **0,1003 MJ** | 0,103 ±15 % | cumple |
| Ritmo de `R` en régimen de ciclos | 32,39 kW | **33,38 kW** (+3,1 %) | igual ±15 % | cumple |
| `R` antes de los ciclos | 5,429 MJ | 2,754 MJ | ≈2,7 ±25 % | cumple |
| O₂ seleccionado desde 480 s | 0,11261–0,11264 | 0,11262–0,11264 | 0,11263 ±5e-5 | cumple |
| Calor total | 82,115 MJ | 82,150 MJ (+0,04 %) | igual ±1,5 % | cumple |
| Débito de O₂ / O₂ exterior por ciclo | 0,9999 | 1,0013 | 1,00 ±3 % | cumple |

Totales:

| | τ = 6 | τ = 3 | Cambio |
|---|---:|---:|---:|
| Ciclos | 86 | 160 | ×1,86 |
| `R` antes de los ciclos | 5,429 | 2,754 | −2,675 MJ |
| `R` nacido en los ciclos | 15,172 | 15,821 | +0,649 MJ |
| `R` final | 20,601 | 18,575 | −2,026 MJ (−9,8 %) |
| `R` liberado | 0 | 0 | |
| Primer apagado / reencendido | 372,7 / 416,2 s | 367,7 / 410,8 s | |
| HRR máximo | 504,6 kW a 133 s | 514,0 kW a 125 s | |
| O₂ del fuego | 6,2407 kg | 6,2434 kg | |
| O₂ exterior | 0,768 g/s (10,10 kW) | 0,767 g/s (10,10 kW) | |

- El balance de O₂ predice el tramo encendido sin ajuste: 5,41 s con τ = 6 y
  2,75 s con τ = 3, frente a 5,42 y 2,67–2,75 s medidos.
- Objetivo encendido 48,0 kW en ambas; el calor aplicado llega a 18,9 y
  18,7 kW antes de cada apagado; el calor medio es 10,0 y 10,1 kW.
- Cierre `C − B − ΔR − G − U`: 6e-14 MJ.

### 12.3 ON-pre: τ = 6 frente a τ = 3 [M]

| | τ = 6 | τ = 3 |
|---|---:|---:|
| Apagados desde 360 s | 6 | 5 |
| Apagado medio | 77,8 s | 83,2 s |
| Tiempo encendido desde 360 s | 72,9 s | 40,6 s |
| Tramo encendido medio | 12,2 s | 8,1 s |
| Calor por encima del objetivo | 4,683 MJ | 5,162 MJ |
| Calor total | 82,117 MJ | 82,139 MJ |
| O₂ seleccionado desde 480 s | 0,11199–0,11298 | 0,11200–0,11296 |

Las cuatro predicciones débiles se cumplen. ON-pre y D con τ = 3 son idénticas
hasta 288,25 s.

### 12.4 Lectura

**Medido.** Con una intervención real en el motor, el ciclo de D responde como
predice el balance de O₂: el doble de ciclos, tramos encendidos a la mitad,
`R` por ciclo a la mitad y el mismo ritmo de `R` (+3 %). La bajada de `R`
final (−2,03 MJ) viene entera de la subida inicial (−2,68 MJ); en el régimen
de ciclos `R` sube 0,65 MJ.

**Lo que refuta.** Una oscilación exógena del O₂ (H2) predecía los mismos
cruces y la mitad de `R`: hay 158 apagados, no 84. Un retraso genérico del
filtro (H4) predecía `R` de ciclos a la mitad: sube un 4 %.

**No es solo sensibilidad al filtro.** El filtro fija cuántos ciclos hay y
cuánto `R` nace en cada uno, pero no el `R` del régimen: lo fija la diferencia
entre el objetivo mínimo con llama (48 kW) y lo que el O₂ sostiene (10 kW).

**[I] Lo que sigue sin demostrarse.** Que la discontinuidad de `can_flame`
sea **necesaria**: en las cuatro corridas el umbral y el recorte de D son los
mismos. Tampoco separa el umbral del recorte.

**Decisión.** Según la regla predeclarada, los resultados **justifican pasar
al experimento causal con una clave diagnóstica en `sim/`** (§11.7, n.º 2):
es el único que prueba la necesidad. No se ha empezado; requiere autorización
y su coste de R2-1.

Observaciones no predeclaradas, sin peso en la decisión:

- la contabilidad exacta sin cruces del umbral (control A) deja 0,236 MJ de
  los 15,821 MJ con τ = 3;
- el arnés de §11.5 da 158 apagados y 15,81 MJ frente a 158 y 15,57 MJ del
  motor. Sigue invalidado por sus fallos predeclarados con τ = 6.

## 13. Experimento causal del umbral de llama: clave diagnóstica (2026-10-01, noche)

Experimento 2 de §11.7. Se añade a `sim/` una clave **estrictamente
diagnóstica**, OFF por defecto. No es un arreglo ni una propuesta de física:
la opción D sigue OFF en producto y en NO-GO, y un `R` menor no es prueba de
mayor realismo. Predeclaración escrita antes de editar `sim/`:
`runs/g3_flame_target_continuity_20261001/PREDECLARATION.md`.

### 13.1 La clave [C]

`SimulationEngine` gana dos variables **sin `@export`** (no aparecen en el
editor), 0 por defecto, que solo llegan al contexto de combustión con
ancho > 0: `fire_diag_flame_target_window` (`w`) y
`fire_diag_flame_target_jump_fraction` (`λ`). `CombustionSystem` gana un
bloque de 72 líneas, todo inserción: tres constantes, la función pura
`g3_diag_flame_target_kw` y una llamada dentro de la rama `can_flame`, justo
después de la asignación original.

Con `θ = 0,08`, `d = flame_drive`, `I = ideal_hrr_kw`, `P` la pirólisis y `S`
el rescoldo que la regla da justo por debajo de `θ`, solo para
`θ < d < θ + w`:

    J          = S + λ·(I·θ − S)
    T_llama(d) = min(P, J + (I·(θ + w) − J)·(d − θ)/w)

- `λ = 0`: continuo en `θ` (vale `S`, el objetivo por debajo del umbral).
- Para todo `λ`: continuo en `θ + w` (vale `I·(θ + w)`, la regla original).
- `λ = 1`: la regla original (simulacro).
- Fuera de la ventana la función devuelve el valor original sin tocarlo.

No cambia `can_flame`, el recorte de D, el filtro HRR, el débito de O₂, la
pirólisis, las especies ni el estado del objeto. Ancho elegido: `w = 0,01`
(más de mil pasos de `flame_drive`; solo altera el objetivo entre 0,08 y
0,09); sensibilidad con `w = 0,002`.

### 13.2 Propiedad aislada [M]

`tests/test_g3_diag_flame_target.py` (13 pruebas) con un fixture de Godot que
evalúa la función en 1728 puntos:

- fuera de la ventana y con la clave OFF devuelve el original **bit a bit**;
- dentro sigue la recta declarada (≤ 1e-9 kW);
- continuidad en el umbral con `λ = 0` y en el borde superior para todo `λ`;
- el salto conservado es la fracción declarada; con `λ = 1`, la regla original;
- la recta crece con `flame_drive` y nunca supera la regla original;
- el bloque es inserción pura: al quitarlo, el archivo no contiene nada suyo;
- `can_flame` no se toca y comparte el umbral; el rescoldo usa la expresión
  del motor; el bloque solo escribe el objetivo de llama;
- las variables no se exportan y ninguna escena, plantilla, caso de
  validación ni script de producto las menciona.

Mutaciones: 9 de 9 detectadas. La que **restaura el salto** cae por la prueba
de continuidad. Archivos restaurados con SHA-256 verificado.

En las corridas, el propio libro confirma el alcance: con la clave ON hay
entre 5136 y 6110 pasos con registro `diag_flame_target`, todos con
`flame_drive` dentro de la ventana, ninguno fuera y ningún paso de la ventana
sin registro; el objetivo coincide con la recta declarada con error ≤ 7e-15 kW.

### 13.3 Controles [M]

`o2_closed`, interruptor G3 en ON, mismas condiciones; solo cambian `w` y `λ`.
Nueve lanzamientos en secuencia por el monitor, todos con salida 0, sin
cuadros, timeouts, residuos ni procesos ajenos. Ventana tardía fija:
450–900 s.

| Corrida | `w` / `λ` | Objetivo en `θ⁺` | Apagados (total / tardíos) | Tramo encendido (mediana) | `R` nacido tardío | `R` final | Objetivo / calor medio tardío |
|---|---|---:|---:|---:|---:|---:|---:|
| D0 clave OFF | — | 48 kW | 86 / 78 | 5,50 s | 14,552 MJ | 20,601 MJ | 42,4 / 10,0 kW |
| D1 simulacro | 0,01 / 1 | 48 kW | 86 / 78 | 5,50 s | 14,552 MJ | 20,601 MJ | 42,4 / 10,0 kW |
| D2 continua | 0,01 / 0 | 0 | **1 / 0** | sin apagados | **0,039 MJ** | 5,691 MJ | 10,3 / 10,2 kW |
| D3 continua estrecha | 0,002 / 0 | 0 | **1 / 0** | sin apagados | **0,197 MJ** | 6,095 MJ | 10,2 / 9,8 kW |
| D4 salto 1/3 | 0,01 / 1/3 | 16 kW | **18 / 17** | 25,4 s | 2,096 MJ | 7,807 MJ | 15,0 / 10,4 kW |
| D6 salto 1/4 | 0,01 / 1/4 | 12 kW | **8 / 7** | 49,9 s | 0,850 MJ | 6,542 MJ | 12,1 / 10,3 kW |
| D5 salto 1/6 | 0,01 / 1/6 | 8 kW | 1 / 0 | sin apagados | 0,039 MJ | 5,715 MJ | 10,3 / 10,3 kW |
| P0 ON-pre, clave OFF | — | 48 kW | 6 / 5 | 12,6 s | — | — | 6,8 / 8,9 kW |
| P2 ON-pre continua | 0,01 / 0 | 0 | **1 / 0** | sin apagados | — | — | 9,2 / 9,3 kW |

- **Identidad:** D0 reproduce byte a byte los ocho archivos del control D;
  P0, los ocho del ON-pre original (la copia ON-pre lleva el mismo bloque).
- **Simulacro:** `sim_log.csv` idéntico byte a byte al de la clave OFF. Los
  libros difieren en el registro de la clave y en 137 de 64 800 líneas por
  redondeo (≤ 1e-13 kW). La clave en sí no altera la dinámica.
- **Apagados:** donde los hay, duran un paso de mediana. Los cruces de 0,08
  en la ventana tardía son 158 (OFF y simulacro), 34 (salto 1/3), 14 (salto
  1/4) y 0 en las demás.
- **O₂ exterior** tardío: 0,765–0,771 g/s en todas (sostiene 10,1 kW);
  débito del fuego 0,74–0,79 g/s en D. El calor medio en 600–900 s es
  9,9–10,2 kW en todas las de D: lo fija el O₂, no el objetivo.
- **O₂ seleccionado** desde 480 s: 0,11261–0,11264 con salto de 48 kW;
  0,11274–0,11297 (continua), 0,11264–0,11272 (estrecha), 0,11253–0,11270
  (1/3), 0,11247–0,11274 (1/4), 0,11257–0,11283 (1/6). El O₂ superior baja de
  ≈0,115 al valor seleccionado en todas. `flame_drive` medio en 600–900 s:
  0,08004 (OFF), 0,08227 (continua), 0,08051 (estrecha), 0,08018, 0,08035 y
  0,08090.
- **Calor total:** 81,41–82,12 MJ (como mucho −0,86 %). O₂ del fuego
  6,187–6,241 kg. HRR máximo 504,6 kW en todas.
- **Cierre** `C − B − ΔR − G − U` ≤ 2e-14 MJ; contrato K1–K9 sin violaciones;
  `R` liberado 0; el depósito no arde en ninguna.
- **La energía no desaparece, cambia de etiqueta.** La pirólisis no cambia
  (≈41 kW medios) y el calor tampoco (≈10 kW). Con el salto, la diferencia se
  anota como `R` (15 MJ). Sin él, como gas no quemado: `G + U` pasa de 6,8 a
  22,7 MJ en la continua. El objetivo baja 13,8–16,9 MJ respecto a la regla
  original, según la variante.

### 13.4 Efecto de la continuidad frente al de bajar la potencia

El calor aplicado medio es ≈10 kW en **todas** las variantes. Lo que cambia es
el objetivo, y las variantes continuas lo dejan bajar justo a lo que el O₂
sostiene. Por eso se predeclaró un control de potencia media: bajar el
objetivo junto al umbral **sin quitar la discontinuidad**.

| | Objetivo medio tardío | ¿Salto? | ¿Abarca 10,1 kW? | ¿Cicla? |
|---|---:|---|---|---|
| OFF / simulacro | 42,4 kW | 48 kW | sí | sí (78) |
| Salto 1/3 | 15,0 kW | 16 kW | sí | sí (17) |
| Salto 1/4 | 12,1 kW | 12 kW | sí | sí (7) |
| Salto 1/6 | 10,3 kW | 8 kW | no | no |
| Continua | 10,3 kW | no | — | no |
| Continua estrecha | 10,2 kW | no | — | no |

Bajar el objetivo de 42 a 15 y a 12 kW no elimina los ciclos mientras quede
un salto que deje fuera los 10,1 kW sostenibles; con 12,1 kW de objetivo
medio (un 18 % por encima de la continua) sigue ciclando. Quitar el salto, o
dejarlo por debajo de lo sostenible, los elimina con el mismo calor medio.

### 13.5 Predicciones frente a resultados

Se cumplen todas las predeclaradas:

- D0 idéntica y D1 dentro de tolerancia (igual a OFF);
- D2: 0 apagados tardíos (≤ 2), 0,039 MJ (≤ 1), objetivo − calor 0,06 kW
  (≤ 0,5), `flame_drive` 0,0819–0,0831 (0,0815–0,0835), `R` final 5,69 (< 7),
  1 apagado en toda la corrida (≤ 3);
- D3: 0 apagados, 0,197 MJ, `flame_drive` 0,0804–0,0807 (0,0803–0,0808);
- D4: 17 apagados (10–25), tramo encendido 25,4 s (20–35), 2,10 MJ (2–4);
- D6: 7 apagados (4–14), tramo encendido 49,9 s (35–90), 0,85 MJ (0,4–2);
- D5: 0 apagados, 0,039 MJ;
- calor total dentro de ±1,5 % y cierre ≤ 1e-9 MJ en todas.

Dos matices: el ritmo de `R` de D4 es 4,7 kW, por debajo del «5–8 kW» que
acompañaba a su rango en MJ (el rango en MJ se cumple); y el `flame_drive` de
D5 es 0,0809 de media frente al ≈0,0805 estimado.

P2 (predicción débil): 0 apagados tardíos y calor por encima del objetivo
2,51 MJ frente a 4,68 MJ. En ON-pre también desaparecen los apagados largos.

### 13.6 Veredicto

**Discontinuidad necesaria**, según los criterios predeclarados: los ciclos
desaparecen en D2 y en D3, y persisten en D4 y D6, que bajan la potencia sin
quitar el salto.

Con la precisión de D5: lo necesario no es un salto cualquiera, sino uno que
**deje fuera la potencia que el O₂ sostiene**. Un salto de 8 kW, por debajo de
los 10,1 kW, no produce ciclos.

Límites:

- un solo escenario (`o2_closed`, 900 s, una geometría, un objeto);
- una sola familia de objetivos continuos (recta) y dos anchos;
- demuestra necesidad en este motor y este caso; no dice qué regla de llama
  es físicamente correcta ni valida CO/FED;
- la clave no es un candidato a producto: con ella la energía que antes era
  `R` pasa a `G + U`.

### 13.7 Cadena R2-1 sobre el código final [M]

`sim/` no cambió desde antes de la primera tanda (SHA-256 de los cuatro
archivos del motor verificados). Todo en secuencia por el monitor, con al
menos 6 GiB antes de cada tanda y sin cuadros ni procesos previos.

- **Identidad con la clave OFF, interruptor G3 en OFF**
  (`runs/g3_optd_diagkey_off_20261001_202705` frente a
  `g3_optd_final_off_20260930_211954`): 9 de 9 casos idénticos byte a byte en
  los ocho archivos de física; `summary.json` solo difiere en la ruta de
  salida.
- **Identidad con la clave OFF, interruptor G3 en ON**
  (`runs/g3_optd_diagkey_on_20261001_204557` frente a
  `g3_optd_final_on_20260930_210047`): 9 de 9 casos idénticos, con la misma
  salvedad.
- **Referencia completa** (`runs/reference_suite_monitored_20261001_214814`):
  18 de 18 casos con salida 0 e informe nuevo, 3228 s, mínimo 6,74 GiB.
  **346/346 comprobaciones requeridas y 78 gaps.** `reference_checks.json`
  solo cambia en `generated_at`: ninguna de las 532 comprobaciones difiere.
- **Guardarraíles:** ALL PASS, incluido `Reports freshness (R2-1)`.
- **`check_product.py` monitorizado**, con la compuerta de 6 GiB por
  lanzamiento (`runs/check_product_monitored_20261001_224245`): salida 0,
  **168 tests**, 11 min 14 s; 81 lanzamientos, sin cuadros, timeouts,
  residuos ni procesos ajenos, 0 procesos terminados.
- **pytest global:** 3177 passed, 37 skipped, 2 xfailed, 42 subtests, 0
  fallos. Son 3216 pruebas: las 3199 anteriores, las 13 nuevas y 4 casos que
  `test_godot_fixture_fail_closed.py` genera para el fixture nuevo (2 pasan y
  2 se omiten).
- Un incidente: el primer intento de la corrida P0 fue rechazado por la
  compuerta de memoria (3,53 GiB disponibles). No se lanzó nada; se repitió
  con 6,47 GiB.
- Al terminar: ningún proceso Godot, ningún cuadro de error.

## 14. Balance físico de combustible, O₂ y productos (2026-10-02)

Fase de análisis y diseño. No se toca `sim/` ni se lanza Godot: todo sale del
código y de libros ya ejecutados. Herramienta de solo lectura:
`scripts/simulation/analyze_g3_fuel_o2_products_balance.py`; libros por paso y
acumulados en `runs/g3_fuel_o2_products_balance_20261002/`. Etiquetas como en
§10, más **[D]** para lo leído en la documentación local de CFAST.

La clave continua de §13 sigue siendo solo diagnóstica. Un `R` menor no es
mayor realismo: aquí se mide adónde va esa energía.

### 14.1 Propietarios y orden de aplicación [C]

Orden del tick con `fire_o2_mode = legacy` (`SimulationEngine`):
`_step_pool_fires` → **`_step_fire`** → `_step_co_oxidation` (apagado) →
`_step_targets` → **`_step_oxygen`** → térmico → supresión → vapor →
intercambio de gases → HVAC → combustible pasivo → `_check_carbon_balance`.
El calor se fija antes de debitar el O₂.

Dentro de `CombustionSystem.step_room_fire`, en este orden: factor de O₂ y
`flame_drive` → HRR ideal → pirólisis `P` → objetivos de llama y rescoldo →
generación al depósito → escala por combustible disponible → **alta en el
depósito** (con tope de capacidad) → objetivo de liberación del depósito →
filtro HRR → reparto sólido/depósito → paso de la opción D → **baja del
depósito** (quema, decaimiento, backdraft) → humo → comprobaciones de
extinción → CO, HCN, irritantes, CO₂ → tope de carbono → alta de especies →
**débito del combustible** → extinción.

| Término | Unidad | Estado físico | Recinto / zona | Propietario |
|---|---|---|---|---|
| `C`, combustible debitado | MJ (sin masa) | sólido que piroliza | objeto; el fuego de la sala lo refleja | `step_room_fire` (`solid_fuel_demand_MJ` = `P·dt`), `_g3_allocate_owned`, `_g3_apply_owned` |
| `B` sólido | MJ de calor | calor liberado | sala | filtro HRR y `_g3_option_d_step` |
| `B` del depósito | MJ de calor | calor liberado | sala | `actual_pool_burn_kw` en `step_room_fire` |
| `R` | MJ | **saldo contable**, no gas | objeto (`g3_r_balance_MJ`) | `_g3_option_d_step`, `_g3_apply_owned` |
| `G` | MJ | «gas sin quemar», sin masa | sala, **sin zona y sin transporte** (`retained_unburned_MJ`) | `step_room_fire`: 30 % de `P − T_s` con llama, 0 en fase latente |
| `U` | MJ | — | **ninguno: no hay variable** | nadie; es lo que queda de `P − T_s` |
| Bajas del depósito | MJ | — | sala | decaimiento `0,0025/s · (1 + 1,5·apertura + 0,5·(1 − temp))`, tope `1,20 MJ/m²`, backdraft `0,6·HRR·dt` (`step_room_fire`); supresión (`SimulationEngine` l. 4508) |
| O₂ del fuego | kg | gas | zona según ruta (bulk, lower, plume) | `OxygenExchangeSystem.step`: `0,076·HRR·dt`, truncado al 5 % o al 20 % de la masa de O₂ de la zona |
| O₂, otros sumideros | kg | gas | zona superior | `OxygenExchangeSystem.step`: desplazamiento `0,09` (defecto O2-4) |
| O₂ exterior | kg | gas | sala | intercambio de gases y fugas |
| CO, HCN, irritantes | kg | gas | sala y zona superior | `step_room_fire` → `_apply_species_generation_result` |
| CO₂ (masa) | kg | gas | sala y zona superior | `step_room_fire` |
| CO₂ (trazador) | fracción molar | gas | zona superior (`co2_upper`) | `OxygenExchangeSystem.step`, a partir del HRR |
| Humo | kg | partículas | sala | `step_room_fire` (`smoke_prod_kg_s`) |
| Carbono | kg | diagnóstico | sala | `c_burned_total_kg = 0,027·C`; `_check_carbon_balance` |

El combustible solo existe en MJ. No hay masa de combustible ni composición:
el carbono sale de un único `fuel_c_kg_per_MJ = 0,027`. Por eso **un MJ de
`R`, `G` o `U` no es una masa de gas**.

### 14.2 El libro independiente: cierre contable [M]

Identidad por paso: `C = B_sólido + retraso + G + U`, con
`retraso = T_s·dt − B_sólido`. Con la opción D el retraso es `ΔR` (coincide
paso a paso, 0 de diferencia); sin ella no tiene dueño. Dos comprobaciones
independientes de la definición: el combustible quitado a los objetos iguala
`C` en todos los pasos, y `C = P·dt` salvo en el paso de extinción.

| Caso (motor D) | `C` | `B` sólido | `R` acumulado / liberado / final | `G` | `U` | Cierre |
|---|---:|---:|---:|---:|---:|---:|
| `sofa_vent` | 2,999 | 2,999 | 0,934 / 0,934 / 0 | 0 | 0 | 2e-16 |
| `low_power_vent` | 5,995 | 5,955 | 1,070 / 1,030 / 0,040 | 0 | 0 | −1e-16 |
| `two_active_vent` | 5,998 | 5,959 | 1,061 / 1,021 / 0,040 | 0 | 0 | −1e-16 |
| `o2_closed` | 109,505 | 82,115 | 20,601 / 0 / 20,601 | 1,199 | 5,590 | −6e-15 |
| `o2_reopen_300` | 119,996 | 118,743 | 8,044 / 6,823 / 1,220 | 0,010 | 0,023 | 4e-15 |
| `o2_closed` continua (§13) | 109,792 | 81,409 | 5,691 / 0 / 5,691 | 6,158 | 16,534 | −1e-14 |

(MJ.) Sin la opción D el retraso no tiene saldo: en `o2_closed` hay 6,02 MJ
de calor por debajo del objetivo y 11,12 MJ por encima con el interruptor OFF,
y 7,07 y 4,68 MJ en ON-pre. Con el interruptor OFF el calor liberado supera
al combustible debitado: +0,807 MJ en `sofa_vent` (3,807 frente a 3,000),
+1,030 en `low_power_vent`, +0,944 en `two_active_vent` y +5,026 en
`o2_reopen_300`. Ese calor sí debita O₂.

### 14.3 Balance físico posterior: qué pasa con `G`, `U` y `R` [M]

| Caso | `G` al depósito | Arde | Decae | Queda al final | `U` sin dueño (con llama / sin llama) |
|---|---:|---:|---:|---:|---:|
| `o2_closed` (D) | 1,199 | **0** | 1,011 | 0,188 | 5,590 (2,03 / 3,56) |
| `o2_closed` continua | 6,158 | **0** | 3,927 | 2,231 | 16,534 (14,00 / 2,53) |
| `o2_reopen_300` (D) | 0,010 | **0** | 0,008 | 0,002 | 0,023 |
| `o2_closed` ON-pre | 6,062 | **0** | 3,675 | 2,387 | 18,366 (1,70 / 16,67) |
| `o2_closed` OFF | 1,943 | **0** | 0,590 | 1,353 | 12,732 (0,97 / 11,76) |

- **El depósito no arde en ninguno de los trece casos**, tampoco al reabrir.
  Todo `G` acaba decayendo o sigue en el depósito al final. El decaimiento
  quita energía sin calor, sin O₂, sin especies y sin transporte.
- Ninguna baja del depósito supera su ley de decaimiento (factor entre 1 y
  3) en ningún paso, así que no hay bajas por tope, backdraft ni supresión
  en estos casos. Por debajo de la ley solo quedan 3e-7 MJ (`o2_reopen_300`
  con D), 1,4e-5 MJ (`o2_reopen_300` OFF) y 2,8e-4 MJ (`o2_closed` OFF).
- **`U` no tiene variable.** Es el 70 % de `P − T_s` con llama y el 100 % en
  fase latente. No está en ningún inventario, zona ni flujo.
- **`R`** queda en el objeto como saldo. No es gas ni vuelve al combustible.

### 14.4 El traslado de 15,9 MJ al hacer continuo el objetivo [M]

`o2_closed` con D, salto frente a objetivo continuo:

| | Salto | Continuo | Diferencia |
|---|---:|---:|---:|
| `C` | 109,505 | 109,792 | +0,287 |
| `B` | 82,115 | 81,409 | −0,706 |
| `R` final | 20,601 | 5,691 | **−14,910** |
| `G` | 1,199 | 6,158 | +4,959 |
| `U` | 5,590 | 16,534 | +10,945 |
| `G + U` | 6,789 | 22,692 | **+15,904** |

(MJ.) `0,287 = −0,706 − 14,910 + 4,959 + 10,945`: cierra. Destino físico de
esos 15,90 MJ: 10,94 a `U` (sin dueño), 2,92 se pierden por decaimiento del
depósito y 2,04 quedan en el depósito. **Ninguno se quema ni consume O₂.** En
carbono, con el factor único del motor: el de `R` baja de 0,556 a 0,154 kg, y
el de `G + U` sube de 0,183 a 0,613 kg.

Lo que sí cambia en los productos, con el mismo calor (−0,9 %) y el mismo O₂
del fuego (−0,054 kg): con el salto hay **0,974 kg más de humo y 0,635 kg más
de CO₂** (3,998 y 6,722 kg frente a 3,024 y 6,087). El CO apenas cambia
(0,360 y 0,355 kg). La causa está en §14.5.

### 14.5 De qué se calculan CO, CO₂ y humo [C] y qué se mide [M]

| Especie | Base del cálculo |
|---|---|
| Humo | `max(B_sólido, T_s·m)` + 38 % de `G` + 42 % de la quema del depósito; `m` entre 1 y 1,4 según el O₂ |
| CO, HCN, irritantes | `B_sólido` + 40 % de la quema del depósito + 8 % de `G`; el rendimiento crece con la falta de O₂ |
| CO₂ (masa) | `max(HRR total, 0,6 · base del humo)` |
| CO₂ (trazador) | HRR × rendimiento × `o2_upper/o2_nominal` |
| Tope de carbono | CO + CO₂ + HCN ≤ `0,027·C` (+ el carbono de la `R` liberada). **El hollín queda fuera** |
| O₂ | solo el calor: `0,076·(B_sólido + B_depósito)` |

Es una combinación: el CO sigue al calor; el humo sigue al mayor de calor y
objetivo; el CO₂ puede seguir al objetivo a través de la base del humo; el O₂
solo sigue al calor.

Hallazgos:

- **Humo y CO₂ sobre el objetivo, no sobre el calor.** Cuando el calor va por
  debajo del objetivo (20,60 MJ en `o2_closed` con D), el humo se produce
  igual y el CO₂ puede producirse sobre el 60 % de esa base. No hay débito de
  O₂ para ello. CO₂ por encima de su rendimiento máximo sobre el calor
  liberado: 0,504 kg en 5817 pasos con el salto, 0,011 kg con el objetivo
  continuo.
- **Doble producción con `R`.** [C] El humo se cuenta al acumular `R` (sobre
  el objetivo) y otra vez al liberarla (sobre el calor). [I] En `sofa_vent`
  los 0,0473 kg de humo equivalen a 3,94 MJ de base con el rendimiento base
  de 0,012 kg/MJ, para 3,00 MJ de combustible: compatible con que los
  0,93 MJ de `R` cuenten dos veces. El libro no da la base ni el rendimiento
  por paso (§14.9), así que no queda medido.
- **Doble base del depósito.** Humo y CO toman el 38 % y el 8 % de `G` al
  generarlo y otro 42 % y 40 % al quemarlo. Aquí no se manifiesta porque el
  depósito no arde.
- **Carbono creado.** El hollín (`0,87·humo`) no entra en el tope. Los
  productos llevan más carbono que el combustible debitado en todos los
  casos: +0,031 kg (+38 %) en `sofa_vent`, +2,515 kg (+85 %) en `o2_closed`,
  +1,484 kg (+50 %) en la continua, +3,089 kg (+95 %) en `o2_reopen_300`.
- **Oxígeno en los productos.** El oxígeno de CO₂ y CO es 0,82 veces el O₂
  debitado con ventilación y 0,75–0,82 en sala cerrada. Hay pasos en que lo
  supera (304 en `sofa_vent`, 5723 en `o2_closed`). El oxígeno propio del
  combustible no está modelado, así que el residuo no se puede cerrar.
- **O₂ truncado.** Solo en `o2_stress_cap`: 5,767 kg sin debitar en 33 pasos;
  ahí el oxígeno de los productos es 1,17 veces el O₂ debitado. En el resto
  solo el paso de extinción queda sin debitar (menos de 1,2e-6 kg).
- **Sumideros de O₂ ajenos al fuego** (O2-4): otro tanto del débito del fuego
  con ventilación (×2,00), ×1,09 en sala cerrada, ×1,44 al reabrir.
- **El CO₂ se lleva dos veces**, con reglas distintas y sin conciliación. En
  `o2_closed` el máximo en la zona superior es 279 059 ppm según el trazador y
  527 806 ppm según la masa; al final, 67 342 y 78 137. Con ventilación, al
  final el trazador da 400 ppm y la masa 3902.
- **Paso de extinción.** Es el único paso con `C ≠ P·dt`: el libro anota
  pirólisis y generación pero no hay débito (≤ 3,5 kJ; en OFF `o2_closed`,
  1,0 kJ entra en el depósito sin combustible).

### 14.6 Contraste con CFAST [D]

Fuente local: NIST TN 1889v1 §2.2 (p. 9), §3.1 (ec. 3.1–3.8) y §3.2
(ec. 3.12–3.14, p. 12–13); TN 1889v2 cap. 7 (§7.2 de este documento).

| | CFAST | SimuFire |
|---|---|---|
| Unidad del combustible | masa: `ṁ_f = Q/ΔH` | MJ, sin masa |
| Pirólisis con O₂ limitado | no cambia; solo arde una parte | no cambia: coincide |
| Calor con O₂ limitado | `min(ṁ_f·ΔH, ṁ_e·Y_O2·C_LOL·ΔH_O2)`, algebraico; `C_LOL` es una tangente hiperbólica, continua | objetivo con salto en 0,08 y filtro temporal; el O₂ se debita después |
| Combustible sin quemar | **todo** se sigue como especie y se transporta por la pluma y los huecos | 30 % al depósito de la sala, sin zona ni transporte; 70 % sin variable |
| Dónde puede arder | en la capa superior o en un hueco, si hay temperatura y O₂ | solo en la sala de origen, con una señal de apertura y O₂ ≥ 13 % |
| Productos | proporcionales al combustible consumido; CO₂ por diferencia de carbono (`ν_CO2 = n_C − ν_CO − ν_HCN − ν_s`) | rendimientos por MJ sobre bases mixtas; hollín fuera del tope de carbono |
| O₂ | por estequiometría, con el oxígeno propio del combustible (`ν_O2`, ec. 3.6) | Thornton sobre el calor; sin oxígeno del combustible |
| Análogo de `R` | no existe | saldo por objeto |

Coincidencias: la pirólisis no depende del O₂ y el calor se limita por O₂ con
13,1 MJ/kg. Diferencias: CFAST conserva masa y carbono por construcción y
transporta el inquemado; SimuFire no. No se importa ningún valor de CFAST.

### 14.7 Residuos sin dueño (declarados, no «pérdidas»)

En `o2_closed` con D, sobre 109,505 MJ debitados:

| Residuo | Cantidad | Propietario |
|---|---:|---|
| `U` | 5,590 MJ (0,151 kg C) | ninguno |
| Decaimiento del depósito | 1,011 MJ | `CombustionSystem`; sin destino |
| `R` final | 20,601 MJ (0,556 kg C) | objeto; no es gas |
| Carbono creado | 2,515 kg | especies: hollín fuera del tope |
| Humo y CO₂ sin calor | base de 20,601 MJ | bases de humo y CO₂ |
| O₂ ajeno al fuego | 0,551 kg | `OxygenExchangeSystem` (O2-4) |
| Oxígeno del combustible | no medible | no modelado |
| Segunda cuenta de CO₂ | hasta 368 104 ppm de diferencia | `OxygenExchangeSystem` y `CombustionSystem` |

### 14.8 Contrato propuesto para la siguiente corrección

Inventarios necesarios, todos con dueño:

1. **Combustible sólido por objeto**, en kg, con su calor de combustión y su
   fracción de carbono. El MJ se deriva.
2. **Combustible gaseoso sin quemar**, en kg, **por zona** y transportado por
   los mismos flujos que las demás especies (pluma, huecos, fugas). Sustituye
   a `G`, a `U` y al decaimiento: el 100 % del pirolizado que no arde entra
   aquí.
3. **O₂ por zona** con un único sumidero del fuego.
4. **Productos** (CO, CO₂, hollín, HCN, H₂O) producidos **solo** por
   combustible que arde.

Reglas:

- **R1, calor aceptado antes del débito.** El calor de un paso es
  `min(combustible que puede arder, O₂ aceptable de la zona / 0,076)`; el O₂
  aceptable sale de `OxygenExchangeSystem` antes de fijar el calor. Lo que no
  cabe no arde y pasa al inventario 2.
- **R2, conservación de carbono.** `C_combustible que arde = C_CO + C_CO2 +
  C_hollín + C_HCN`, con el CO₂ por diferencia.
- **R3, oxígeno.** O₂ debitado = el de la estequiometría de lo quemado.
- **R4, una sola cuenta de cada especie.**
- **R5, el inquemado arde donde está**, cuando su zona tiene O₂ y
  temperatura, con la misma R1.

Decisiones físicas sin datos propios, con alternativas:

| Decisión | Alternativa A | Alternativa B |
|---|---|---|
| Límite de O₂ del calor | función continua tipo `C_LOL` de CFAST | mantener el umbral 0,08 con el inquemado conservado |
| Destino del inquemado | zona superior, por la pluma (CFAST) | mezcla de sala, sin zona |
| Encendido del inquemado | temperatura mínima de gas + O₂ (CFAST) | regla actual de backdraft |
| Retraso del HRR (`R`) | suprimir el filtro en el calor y dejar la inercia en la pirólisis | conservar `R` como saldo, sin especies hasta liberarlo |
| Oxígeno del combustible | composición por material | factor único declarado |

Ninguna alternativa se elige aquí: la A de las dos primeras filas coincide con
CFAST, pero no hay ensayo propio que la sustente.

**Pruebas de falsación.** Son los hallazgos del analizador, que hoy fallan en
el motor actual. Una corrección solo vale si los deja a cero en los seis
casos; mover energía entre `R`, `G` y `U` no cambia ninguno de los marcados
con masa u oxígeno:

- F-E: `C = B + ΔR + G + U`, `C = P·dt`, débito por objeto = `C` (E0, E1, E8);
- F-U: nada de pirolizado sin inventario (E5 = 0);
- F-P: el depósito no pierde sin destino (P1 = 0) y cierra su inventario (P0);
- F-O: O₂ del fuego = Thornton del calor, sin truncar (O0), sin sumideros
  ajenos (O1), y el oxígeno de los productos no supera el debitado más el
  declarado del combustible (O2);
- F-C: carbono de los productos = carbono de lo quemado; ni creado (C1) ni por
  encima de lo quemado (C2), ni sin dueño (C0);
- F-S: ninguna especie sobre una base que no sea calor liberado (S0, S1);
- F-2: una sola cuenta de CO₂.

### 14.9 Observables que faltan

Para cerrar el balance paso a paso, el libro del motor no da:

- base en kW y rendimiento de humo, CO y CO₂ en cada paso, y la escala del
  tope de carbono;
- `o2_hrr_factor` y `flame_drive` en cada paso fuera de la opción D;
- las bajas del depósito por separado (decaimiento, tope, backdraft,
  supresión) y las señales `opening_signal` y `temp_signal`;
- el O₂ debitado por ruta y si se truncó;
- la producción del trazador de CO₂ por paso;
- masa de combustible, calor de combustión y composición por objeto;
- zona de destino de cada especie al generarse;
- agua producida.

`U` no es un observable ausente: no existe en el motor.

### 14.10 Pruebas del analizador [M]

`tests/test_g3_fuel_o2_products_balance.py`: 30 pruebas sobre libros
sintéticos, sin Godot. Parten de un paso que cierra en energía, oxígeno y
carbono con las constantes del motor, cambian un término y exigen el hallazgo
que lo nombra (20 cambios distintos). Cubren además la ruta omitida del libro,
la quema del depósito como ruta de calor, O₂ y carbono, el reparto de `U`, el
inventario del depósito y los libros que no casan. 16 de 16 mutaciones del
analizador detectadas; archivo restaurado.

### 14.11 Decisión

**GO** para diseñar e implementar, detrás de un interruptor OFF, la
corrección con el contrato de §14.8, **empezando por lo que no necesita
ninguna decisión física nueva**:

1. el inventario único del inquemado (acaba con `U` y con el decaimiento sin
   destino);
2. las especies solo sobre calor liberado y el hollín dentro del tope de
   carbono (R2, R4);
3. los observables de §14.9 en el libro.

**NO-GO** para:

- elegir entre las alternativas de la tabla de §14.8 sin que el usuario
  decida: ahí no hay datos propios;
- calibrar rendimientos, activar la opción D o la clave diagnóstica en
  producto, o presentar nada de esto como validación de CO/FED.

Límites: seis casos de un solo recinto y un solo objeto dominante; el carbono
usa el factor único del motor; el oxígeno del combustible no se puede medir.

## 15. Instrumentación del balance físico en el motor (2026-10-02)

Esta fase añade observables. **No corrige ninguna ley física**: `U` sigue sin
inventario, los rendimientos no cambian y las especies siguen calculándose
como antes.

### 15.1 Esquema del observable, fijado antes de editar `sim/`

**Interruptor.** Se reutiliza `CombustionSystem.g3_fuel_ledger_enabled`, el
del libro v3: es diagnóstico, vale `false` por defecto y solo lo enciende
`tools/run_scenario_headless.gd` con `--g3-fuel-ledger-v3`. Cubre este
trabajo, así que **no se crea ningún interruptor nuevo** y no hay nada que
registrar en `audit_default_off_flags.py` (ese auditor solo cubre los
`@export … bool = false` de `SimulationEngine`, y este no lo es).

**Soporte.** Los campos nuevos van en el mismo registro por sala y paso de
`g3_fuel_ledger_v3.jsonl`, en bloques `bal_*`, con `bal_schema` =
`g3_balance_v1`. Los campos v3 anteriores no cambian. Se escriben con
precisión completa, sin redondear.

**Tres clases de valor**, que el analizador no puede confundir:

- **solicitado**: lo que la fórmula pide antes de topes y escalas;
- **aplicado**: lo que la fórmula entrega tras topes y escalas;
- **inventario**: el estado leído de la sala o del objeto antes y después de
  la escritura. No se copia del cálculo: se lee de la variable de estado.

Bloques (un registro por sala y paso; «zona» es la del motor, no una masa de
gas):

| Bloque | Momento del paso | Propietario | Recinto / zona | Campos (unidad) |
|---|---|---|---|---|
| v3 existente | `step_room_fire` y cierre del paso | `CombustionSystem` | objeto y sala | pirólisis pedida y aplicada (MJ), débito (MJ), reparto y restante por objeto antes/después (MJ), calor sólido y del depósito (kW), `G` (MJ), `R` por objeto (MJ) |
| `bal_fuel` | tras el reparto sólido/depósito | `CombustionSystem` | sala | pirólisis, objetivo de llama y de rescoldo, alta pedida al depósito, calor sólido, calor del depósito y liberación de `R` (MJ); `unburned_without_inventory_MJ` con `physical_inventory: false` (es `U`, derivado); `flame_drive`, `o2_hrr_factor`, `can_flame`, `latent_viable` |
| `bal_pool` | tras cada escritura del depósito | `CombustionSystem` | sala, sin zona | estado antes (MJ); alta pedida, capacidad, estado tras el alta (tope); quema pedida y estado tras la quema; tasa, señales de apertura y temperatura, y estado tras el decaimiento; backdraft pedido y estado tras él |
| `bal_extinction` | `_extinguish_room_fire` | `CombustionSystem` | sala | motivo, depósito antes de anularse (MJ), calor y humo cancelados (kW, kg/s) |
| `bal_suppression` | `_apply_suppression_to_room` | `SimulationEngine` | sala | factor, depósito y HRR antes y después |
| `bal_species` | antes y después de `_apply_species_generation_result` | `CombustionSystem` | sala y zona superior | por especie (humo, CO, CO₂ de masa, HCN, HCl, acroleína, formaldehído): términos de la base (kW), regla que la fijó, rendimiento base y aplicado (kg/MJ), solicitado (kg), aplicado (kg), inventario antes/después (kg); tope de carbono: carbono disponible, tope, carbono pedido, escala, si actuó; hollín fuera del tope |
| `bal_o2` | `OxygenExchangeSystem.step`, bucle de sala | `OxygenExchangeSystem` | sala; ruta bulk, upper, lower o plume | HRR leído (kW), kg O₂/MJ, masas de aire de sala y de zona (kg); por ruta: solicitado, tope, aplicado, truncado (kg), fracción antes/después, base de masa, si es la ruta primaria del fuego; ACH, arrastre del penacho y clamps finales; fracciones bulk/upper/lower al entrar y al salir |
| `bal_co2_tracer` | `OxygenExchangeSystem.step`, tras el O₂ | `OxygenExchangeSystem` | zona superior | rama (homogeneiza, produce, relaja), HRR leído, rendimiento, escala por O₂, producido (kg), fracción antes/después y antes del clamp |
| `bal_state_before`, `bal_state_after` | inicio de `step_room_fire`; cierre del paso | lectura de `RoomModel` | sala y zonas | depósito (MJ), O₂ bulk/upper/lower, trazador de CO₂, CO, CO₂, HCN, humo y sus partes de zona superior (kg), humo generado en el paso según `GasExchangeSystem` (kg), acumulados de O₂ del paso (kg) |

Reglas:

- `U` se emite como derivado con `physical_inventory: false`. No es un
  inventario ni una pérdida resuelta.
- No se emite masa ni composición de combustible: el motor no las declara.
  El carbono solo aparece donde el propio motor lo usa (`fuel_c_kg_per_MJ`).
- Ningún bloque escribe en `RoomModel`, `FireModel` ni en los objetos, ni
  entra en una condición física. Con el interruptor OFF no se ejecuta nada.

### 15.2 Implementación [C]

Solo inserciones, todas detrás del interruptor del libro:

| Archivo | Líneas añadidas | Qué observa |
|---|---:|---|
| `sim/fire/CombustionSystem.gd` | 229 | combustible, depósito, especies, tope de carbono, extinción, estado de sala al empezar y al cerrar |
| `sim/core/OxygenExchangeSystem.gd` | 133 | O₂ por ruta y trazador de CO₂ |
| `sim/core/SimulationEngine.gd` | 22 (y 1 sustituida) | entrega la sonda al sistema de O₂; supresión |

- `OxygenExchangeSystem` no tiene interruptor propio: recibe una sonda en sus
  `hooks` solo cuando el libro está activo. Sin sonda no ejecuta nada.
- `GasExchangeSystem` no se toca: el humo añadido se lee de su contador
  `smoke_generated_kg_step` al cerrar el paso.
- El libro es determinista: los 9 controles y el caso continuo, ejecutados
  dos veces de forma independiente, dan el mismo SHA-256 del archivo
  (`055fe6f5…` en `sofa_vent`).
- Las cinco funciones auxiliares del libro van detrás de `_g3_ledger_note`.
  En la primera versión iban delante y separaban la función de la clave
  diagnóstica de §13 de su ancla: pytest global lo detectó
  (`test_the_block_is_a_pure_insertion_in_combustion_system`). Se recolocaron
  72 líneas sin cambiar ninguna y se repitió toda la verificación (§15.8).
- Coste: el archivo del libro pasa de 113 a 237 MB en `sofa_vent` (7201 pasos,
  6 salas).

### 15.3 Analizador [C]

`scripts/simulation/analyze_g3_balance_ledger.py`, de solo lectura. Para cada
escritura recalcula la regla con las entradas registradas y la compara con el
cambio de inventario leído. Tolerancias fijas: 1e-12 absoluta y 1e-9
relativa. Los hallazgos llevan unidad y propietario; «desconocido» cuando el
libro no ve quién escribe.

- **Combustible:** débito frente a lo quitado a los objetos y frente al
  acumulado de la sala; pirólisis sin débito; regla del alta al depósito;
  calor frente a su acumulado; saldo `R` frente al cálculo.
- **Depósito:** cada escritura frente a su regla y la cadena completa. Lo que
  no explique ninguna baja registrada es `P_unrecorded_change`, con
  propietario desconocido.
- **Especies:** base frente a sus términos, solicitado frente a base ×
  rendimiento, aplicado frente a solicitado × escala registrada, inventario
  frente a aplicado.
- **O₂:** solicitado frente a su regla sobre el calor, aplicado frente a
  `min(solicitado, tope)`, inventario frente a aplicado, y la masa de la zona
  frente a la base de masa que usa la ruta.
- **Trazador de CO₂:** producción, incremento y clamp; y las dos cuentas una
  junto a otra, sin conciliarlas.

`U` sale como derivado con `physical_inventory: false`. Nunca como pérdida.

### 15.4 Controles instrumentados [M]

Evidencia en `runs/g3_balance_instrumentation_20261002/` (análisis, objetivo
continuo en `D_continuous_w010_final/`) y
`runs/g3_balance_identity_on_ledgeron_20261002_124442/` (libros). Motor con la
opción D activa en el escenario diagnóstico; el objetivo continuo usa la
clave de §13. Los mismos controles con el interruptor en OFF están en
`analysis_switch_off/`.

| | `sofa_vent` | `o2_closed` | `o2_reopen_300` | `o2_closed` continuo |
|---|---:|---:|---:|---:|
| Débito de combustible (MJ) | 2,999 | 109,505 | 119,996 | 109,792 |
| Calor sólido (MJ) | 2,999 | 82,115 | 118,743 | 81,409 |
| `R`: acumulado / liberado (MJ) | 0,934 / 0,934 | 20,601 / 0 | 8,044 / 6,823 | 5,691 / 0 |
| Alta al depósito (MJ) | 0 | 1,199 | 0,010 | 6,158 |
| `U`, sin inventario (MJ) | 0 | 5,590 | 0,023 | 16,534 |
| Depósito: quema, tope, backdraft, supresión (MJ) | 0 | 0 | 0 | 0 |
| Depósito: decaimiento (MJ) | 0 | 1,011 | 0,008 | 3,927 |
| Depósito al final (MJ) | 0 | 0,188 | 0,002 | 2,231 |
| Humo pedido sobre calor (kg) | 0,0361 | 2,521 | 3,536 | 2,478 |
| Humo pedido por encima del calor (kg) | 0,0112 | 1,478 | 0,507 | 0,546 |
| CO₂ pedido sobre calor (kg) | 0,2492 | 6,107 | 9,000 | 6,065 |
| CO₂ pedido por encima del calor (kg) | 0,0077 | 0,615 | 0,006 | 0,022 |
| Carbono quitado por el tope (kg) | 0 | 0 | 0 | 0 |
| Carbono de productos − combustible (kg) | +0,031 | +2,515 | +3,089 | +1,484 |
| O₂ del fuego: pedido = aplicado (kg) | 0,2279 | 6,2407 | 9,0245 | 6,1871 |
| O₂ del fuego: baja de masa de su zona (kg) | 0,2279 | 4,5538 | 7,7302 | 4,5373 |
| O₂ ajeno al fuego, aplicado (kg) | 0,2279 | 0,5511 | 3,9718 | 0,5452 |
| CO₂ del trazador / CO₂ de masa (kg) | 0,236 / 0,257 | 5,516 / 6,722 | 5,809 / 9,006 | 5,483 / 6,087 |

**Cierre contable.** En los cuatro casos ninguna escritura se aparta de su
regla registrada: depósito, especies, O₂ y trazador cierran contra su
inventario. Los únicos hallazgos de escritura están en el paso de extinción
(§15.6). Eso es cierre contable, no conservación física.

**Conservación física.** No cierra, y ahora está medido dónde:

- `U` no tiene inventario (5,590 MJ en `o2_closed`).
- El decaimiento del depósito no tiene destino (1,011 MJ).
- Los productos llevan más carbono que el combustible (+2,515 kg).
- El O₂ debitado por el fuego no sale entero de la zona de la que se debita
  (§15.5).
- Hay dos cuentas de CO₂ que no coinciden.

### 15.5 Hechos nuevos que §14 no podía ver [M]

1. **Cuándo actúa el tope de carbono.** Con la opción D no actúa en
   `sofa_vent`, `o2_closed`, `o2_reopen_300` ni en el caso continuo (escala 1
   en todos los pasos); solo en `o2_stress_cap` (69 pasos, 0,096 kg de
   carbono). **Con el interruptor OFF, que es el producto, actúa a menudo**:
   2346 de 3025 pasos con fuego en `sofa_vent`, donde deja el CO₂ en 0,184 kg
   de los 0,324 kg pedidos; 771 pasos en `o2_closed` y 6234 en
   `o2_reopen_300`. Ocurre porque en OFF el calor del paso supera al
   combustible debitado en ese paso. En ningún caso el tope evita el exceso
   de carbono: el hollín queda fuera de él.
2. **Humo y CO₂ por encima del calor, medidos.** En `o2_closed` 1,478 kg de
   los 3,998 kg de humo se piden sobre objetivo por encima del calor sólido,
   y 0,615 kg de CO₂ se piden por la regla de la base del humo y no por la
   del calor (5995 pasos). §14.5 lo daba como compatible; ahora es medido.
3. **Ruta del penacho: la fracción de la zona baja con la masa de toda la
   sala.** El motor aplica 6,123 kg a `o2_lower` dividiendo por la masa de
   aire de la sala. Con la masa de la zona inferior, su inventario baja solo
   4,436 kg: **1,687 kg de O₂ debitado no salen de ninguna zona** (8725
   pasos). En `o2_reopen_300` son 1,294 kg. Propietario:
   `OxygenExchangeSystem`; la medición H3.2-S0d6 ya marcaba esta ruta como
   «base de masa ambigua», sin cifra.
4. **Sin fuego no hay paso de depósito.** Tras la extinción el depósito
   restante ni decae ni arde ni se mueve: en `o2_reopen_300` los 0,0016 MJ
   que quedan al extinguirse siguen intactos los 756 pasos restantes. Con el
   interruptor OFF, en `o2_closed` quedan retenidos 1,353 MJ durante 4457
   pasos.
5. **El sumidero ajeno al fuego también se trunca**: 0,113 kg en 333 pasos de
   `o2_reopen_300` y 10,54 kg en `o2_stress_cap`, por el tope del 20 % de la
   zona superior.
6. **El depósito es inerte en `o2_closed`.** Un mutante que lo encoge un
   0,1 % por paso (§15.7) solo cambia la columna `retained_unburned_MJ` del
   CSV; calor, combustible, especies y O₂ quedan idénticos.

### 15.6 Comparación con §14 y origen de las diferencias [M]

| Magnitud (`o2_closed` salvo indicación) | §14 (libro externo) | Observable del motor |
|---|---:|---:|
| `R` final, salto / continuo (MJ) | 20,601 / 5,691 | 20,601 / 5,691 |
| Alta al depósito, salto / continuo (MJ) | 1,199 / 6,158 | 1,199 / 6,158 |
| `U`, salto / continuo (MJ) | 5,590 / 16,534 | 5,590 / 16,534 |
| Traslado `R` → `G + U` (MJ) | −14,910 → +15,904 | −14,910 → +15,904 |
| Decaimiento, salto / continuo (MJ) | 1,011 / 3,927 | 1,011 / 3,927 |
| Carbono excedente (kg) | +2,515 | +2,515 |
| O₂ ajeno al fuego (kg) | 0,551 | 0,551 |
| O₂ truncado en `o2_stress_cap` (kg) | 5,767 | 5,766 |
| CO₂ por encima del calor (kg) | 0,504 | 0,615 |
| Baja del depósito por debajo de su ley, `o2_reopen_300` (MJ) | 3e-7 | 0 |

Los 15,9 MJ se reproducen término a término. Su destino no cambia: 10,945 MJ
a `U`, 2,916 MJ decaídos y 2,043 MJ en el depósito. Ahora se ve además en las
especies: de los 0,974 kg menos de humo del caso continuo, 0,931 kg eran humo
pedido por encima del calor; de los 0,635 kg menos de CO₂, 0,593 kg.

Diferencias y su origen:

- **CO₂ por encima del calor, 0,504 frente a 0,615 kg.** No miden lo mismo.
  §14 contaba el CO₂ por encima del rendimiento máximo (0,0831 kg/MJ) sobre
  el calor: una cota desde fuera. El observable usa el rendimiento aplicado
  en cada paso, que baja con la falta de O₂, y la regla que realmente fijó la
  base. La cifra del motor es la buena; la de §14 era una cota inferior.
- **Baja del depósito por debajo de su ley, 3e-7 MJ.** §14 esperaba
  decaimiento en todos los pasos con depósito. Tras la extinción no hay paso
  de depósito (hecho 4 de §15.5). Con la tasa y las señales registradas
  ninguna baja se aparta de la ley.
- **Paso de extinción.** Es el único con hallazgos de escritura. El libro
  anota pirólisis, calor y humo que el motor cancela al extinguir: 9e-6 MJ y
  3e-7 kg en `o2_reopen_300`. Con la opción D además calcula una liberación
  de `R` que no confirma (3e-6 MJ).

Los datos se conservan tal cual. No se ajustó física ni tolerancias.

### 15.7 Pruebas y mutaciones [M]

**Pruebas sin Godot.** `tests/test_g3_balance_ledger.py`, 65 pruebas:

- un paso sintético que cierra en combustible, depósito, especies, O₂ y
  trazador, construido con aritmética propia;
- 28 cambios de un solo término, cada uno con el hallazgo que lo nombra;
- campos copiados que no prueban conservación: aplicado = solicitado con el
  inventario sin moverse da `S_inventory_write` y `O_inventory`;
- cada baja del depósito en su término (quema, decaimiento, tope, backdraft,
  supresión, agotamiento) y el depósito retenido sin fuego;
- 7 filas reales del motor como muestra
  (`tests/fixtures/g3_balance_v1_sample.jsonl`);
- estáticas sobre `sim/`: ningún bloque guardado por el interruptor escribe en
  sala, fuego u objeto; no hay interruptor nuevo; solo el lanzador headless
  enciende el libro; ningún escenario lleva bloques `bal_*`.

**Mutaciones del analizador:** 22 de 22 detectadas; archivo restaurado byte a
byte.

**Mutaciones del motor.** `scripts/simulation/run_g3_balance_mutations.py`
cambia el motor, ejecuta `o2_closed` por el monitor, analiza el libro y
restaura el archivo (SHA-256 comprobado). Las cuatro son válidas (compilan y
terminan) y las cuatro se detectan; ninguno de sus hallazgos objetivo aparece
en el control sin mutar.

| Mutante | Cambio en el motor | Hallazgo | Pasos | Cantidad |
|---|---|---|---:|---:|
| MB1, baja del depósito omitida | el depósito pierde un 0,1 % tras su última escritura observada | `P_unrecorded_change` | 7282 | 0,907 MJ |
| MB2, escala de carbono no registrada | el tope actúa a la mitad del carbono y no anota su escala | `S_carbon_scale_unrecorded` | 21 798 | −2,057 kg |
| MB3, O₂ truncado sin declarar | la ruta del penacho debita la mitad tras su tope | `O_truncation_undeclared` | 9906 | 4,548 kg |
| MB4, base de especie equivocada | el CO se calcula sobre el objetivo y no sobre el calor | `S_co_basis_rule` | 7311 | — |

MB2 necesita que el tope actúe, y en `o2_closed` no actúa nunca (§15.5): por
eso el mutante lo hace actuar a la mitad del carbono además de callar su
escala. MB3 cambia la trayectoria y arrastra los hallazgos del paso de
extinción; solo cuenta el objetivo.

### 15.8 Identidad y R2-1 sobre el código final [M]

**Identidad.** `scripts/simulation/run_g3_balance_identity.py` ejecuta los 9
controles de la opción D y los compara con las ejecuciones del 01-10,
anteriores a esta instrumentación.

| Interruptor D | Instrumentación | Casos idénticos | Archivos idénticos | Filas del libro v3 distintas al quitar `bal_*` |
|---|---|---:|---:|---:|
| OFF (producto) | OFF | 9 / 9 | 63 / 63 | sin libro |
| OFF | ON | 9 / 9 | 63 / 63 | 0 de 541 824 |
| ON | OFF | 9 / 9 | 63 / 63 | sin libro |
| ON | ON | 9 / 9 | 63 / 63 | 0 de 541 824 |

Por caso se comparan byte a byte `sim_log.csv`, `sim_log.txt`,
`fuel_source_ledger.jsonl`, `co_inventory_trace.jsonl`,
`fuel_object_state_snapshot.json`, `events.json` y `scenario.json`. Con la
instrumentación OFF no se escribe el libro. Con ella ON, todo lo demás sigue
idéntico: los observables leen sin cambiar nada.

**R2-1.**

- Referencia completa por el monitor: 18/18 casos, **346/346 y 78 gaps**
  (`runs/reference_suite_monitored_20261002_141815`). `reference_checks.json`
  solo cambia en `generated_at` respecto al informe del 01-10.
- Guardarraíles: ALL PASS, incluida la frescura de informes (R2-1).
- `check_product.py` monitorizado, con 6 GiB exigidos por lanzamiento:
  salida 0, **168 pruebas**, 81 lanzamientos sin fallos de salud
  (`runs/check_product_monitored_20261002_151549`).
- pytest global: 3272 passed, 37 skipped, 2 xfailed, 42 subtests.
- Sin procesos Godot ni cuadros de error al terminar.

**Dos pasadas.** La primera, con las funciones auxiliares delante de
`_g3_ledger_note`, dio identidad 36/36, mutantes 4/4, referencia 346/346 y
`check_product.py` 168, pero pytest global falló una prueba (§15.2). Tras
recolocarlas se repitió todo: las cifras de esta sección son de la segunda
pasada, sobre el código final (`CombustionSystem.gd` `49ec9bb9…`,
`OxygenExchangeSystem.gd` `091b3faf…`, `SimulationEngine.gd` `6468da6f…`).
Los 10 libros instrumentados son idénticos byte a byte entre las dos
pasadas.

### 15.9 Límites y qué sigue sin medir

- `U` sigue **sin inventario**. La instrumentación lo mide, no lo resuelve.
- El motor no declara masa ni composición del combustible: el libro no las
  emite y el carbono solo usa `fuel_c_kg_per_MJ`.
- No hay agua como producto ni oxígeno propio del combustible, así que el
  balance de oxígeno de los productos sigue abierto.
- El humo y los irritantes no tienen zona de destino al generarse.
- Los cambios de inventario por transporte, depósito de humo, HVAC y
  aberturas no están desglosados aquí; se ven como diferencia entre el estado
  al empezar y al cerrar el paso, con sus contadores.
- Casos de un recinto y un objeto dominante, con los escenarios diagnósticos
  de §9. No es una validación de CO/FED.
- La opción D y la clave de objetivo continuo siguen OFF en producto. CO/FED
  siguen en NO-GO.

## 16. G3-4A: el pirolizado que hoy queda como `U` (2026-10-02)

Rama `codex/g3-fed-co-zonal-shareable`. Objetivo: que el combustible
pirolizado que hoy no tiene inventario deje de desaparecer, sin elegir ningún
parámetro que no esté sostenido por datos.

### 16.1 La tensión entre §14.11 y §14.8, y cómo se resuelve [C]

§14.11 dio GO para «el inventario único del inquemado». §14.8 pide ese
inventario en **kg, por zona y transportado**. Las dos cosas no son la misma:

| | Inventario físico (kg) | Cuenta energética (MJ) |
|---|---|---|
| Qué es | masa de gas combustible en una zona | energía debitada a un objeto que el motor no quema ni guarda |
| Qué necesita | conversión MJ→kg, composición, zona de destino, transporte, regla de ignición y límite de O₂ | nada: es la diferencia entre lo que se debita y lo que el motor hace con ello |
| Puede arder, moverse o diluir | sí | **no** |
| Qué declara hoy el motor | nada | todo |

Lo que el motor declara:

- **Calor de combustión por objeto** (`heat_of_combustion_kj_kg`): vale −1 por
  defecto. Solo lo declaran 4 objetos de 2 casos de validación
  (`char_layer_loi_wood`, `secondary_ignition_demo`). Ningún escenario
  distribuido, ninguna plantilla ni los controles de §14–15 lo declaran.
- **Conversión global** `fire_backdraft_fuel_heat_kj_kg` = 10 000 kJ/kg con
  densidad 0,8 kg/m³: es la que usa la regla LFL/UFL del backdraft sobre el
  depósito. Está comentada como «mix conservador», sin fuente. No coincide
  con los 17 500–30 800 kJ/kg que el propio motor cita para sólidos.
- **Composición:** un único `fuel_c_kg_per_MJ` = 0,027 para todo.
- **Zona y transporte del combustible:** no existen. El depósito es un
  escalar de sala.

**Resolución.** El GO de §14.11 solo puede cumplirse hoy como **cuenta
energética en MJ**. No es el inventario de §14.8 y no lo sustituye: el
inventario en kg sigue sin poder construirse hasta que se decida la
conversión, la zona, el transporte y la ignición. Una cuenta en MJ no se
transporta, no arde y no se presenta como gas.

### 16.2 Altas y bajas actuales de `U`, `G` y `R` [C]

Con el interruptor de propiedad por objeto (`explicit_objects`) activo. `P`
es la pirólisis, `T_s` el objetivo de llama más rescoldo, `B0` el calor del
combustible fresco y `w_i` la parte del débito del paso que toca al objeto
`i`.

| Cuenta | Unidad, propietario | Alta | Baja con destino | Baja sin destino |
|---|---|---|---|---|
| `U` | MJ; **nadie** | ninguna: no hay variable | — | es toda ella: `(P − T_s − G)·dt` por paso |
| `G`, depósito | MJ; sala (`retained_unburned_MJ`), sin zona | `0,30·max(0, P − T_s)·dt`; 0 en fase latente y con la guarda posbackdraft | quema del depósito (calor, O₂ y especies); backdraft (`min(depósito, 0,6·HRR·dt)`) | tope de capacidad (1,20 MJ/m²); decaimiento; supresión (× entre 0,30 y 1); agotamiento (se pone a 0) |
| `R` | MJ; objeto (`g3_r_balance_MJ`), solo opción D | `w_i·(T_s − B0)·dt` al confirmar el paso | liberación por llama propia o por cola (calor con su cota de O₂) | queda varado en el objeto si la cola termina o el fuego se apaga |

Detalles que el contrato tiene que respetar:

- **Paso con extinción temprana.** El motor sale antes del débito: no se
  debita combustible ni se confirma `R`. Pero el alta y el decaimiento del
  depósito ya se han escrito en ese paso. Es un alta sin origen (1,0 kJ en
  `o2_closed` con el interruptor OFF).
- **Sin fuego** no hay paso de depósito: lo que queda no decae ni arde.
- **Backdraft.** El calor lo impone una envolvente (`4·max_hrr·sen`) y el
  depósito pierde `0,6·HRR·dt`. Calor y combustible no están ligados.
- **Lecturas que deciden física.** El depósito decide su liberación, el
  disparo del backdraft (≥ 8 MJ) y varias extinciones (< 0,5 MJ). `R` decide
  su propia liberación. `U` no decide nada porque no existe.
- **Reinicio de escenario:** depósito y `R` vuelven a 0.

### 16.3 Contrato por paso de la cuenta energética

Dos cuentas, las dos en MJ, las dos crecientes y las dos **sin lectura**:
ninguna condición física puede mirarlas.

| Cuenta | Propietario | Alta | Momento |
|---|---|---|---|
| `A_i`, pirolizado sin inventario | objeto `i` | `w_i·(P − T_s − G)·dt` | al confirmar el paso, junto al débito del objeto |
| `E_tope` | sala | `depósito + G·dt − min(capacidad, depósito + G·dt)` | al escribir el alta del depósito |
| `E_decaimiento` | sala | depósito antes − después de decaer | al escribir el decaimiento |
| `E_supresión` | sala | depósito antes − después de la supresión | al aplicar la supresión |
| `E_agotamiento` | sala | depósito antes de ponerse a 0 | al extinguir por agotamiento |

Conservación que debe cumplirse, con inventario leído antes y después:

- **Por objeto y paso confirmado:**
  `débito_i = w_i·B0·dt + ΔR_i(alta) + w_i·G·dt + ΔA_i`.
- **Depósito, por paso:**
  `depósito_después = depósito_antes + G·dt − quema − backdraft − ΔE`,
  con `ΔE` la suma de las cuatro cuentas de sala.
- **Acumulado desde el reinicio:**
  `Σ débito = Σ B0·dt + Σ ΔR(alta) + Σ G·dt(confirmada) + Σ A_i`.

Reglas:

- Las cuentas no son gas: sin masa, sin zona, sin transporte, sin ignición.
- No cambian el débito, el depósito, el calor, el O₂ ni las especies.
- Se reinician con el escenario y no se guardan en los escenarios.
- El alta del depósito en un paso con extinción temprana **no** se tapa: sigue
  siendo un alta sin origen, visible en el libro.

### 16.4 Gate GO/NO-GO antes de editar física

**GO** para la cuenta energética de §16.3, solo en salas `explicit_objects`
y detrás de un interruptor nuevo, OFF por defecto. No exige ninguna decisión
física. **Es contabilidad con estado en el motor, no una corrección física**:
con ella encendida, calor, O₂, especies, depósito y débito son los mismos.

**NO-GO** para cualquier cambio físico en este tramo. Todos necesitan una
decisión que los datos no dan:

| Decisión mínima | Alternativa A | Alternativa B | Evidencia que hay |
|---|---|---|---|
| D1. Qué es `U` | gas pirolizado que sale del sólido (supuesto de CFAST) | sólido que no llega a pirolizar | [evidencia ampliada](G3_D1_IDENTIDAD_INQUEMADO_2026-10-03.md): ambas rutas existen según el régimen; `U` no identifica ninguna |
| D2. Conversión MJ→kg | calor de combustión declarado por objeto | el global de 10 000 kJ/kg del backdraft | solo 4 objetos lo declaran; el global no tiene fuente |
| D3. Zona de destino | capa superior, por la pluma | mezcla de sala | ninguna propia |
| D4. Ignición del inquemado | temperatura de gas y O₂ en su zona | la regla actual del depósito | ninguna propia |
| D5. Límite de O₂ del calor | función continua | el umbral actual | §13 mide el efecto del salto, no cuál es correcto |

D1 sigue siendo la primera, pero la dicotomía A/B de la tabla es un mapa de
los dos extremos, **no una elección física exhaustiva**. La evidencia revisada
el 2026-10-03 retiró la recomendación provisional de convertir todo `U`
en gas. Hay que separar la tasa de salida del objeto de la oxidación y el
transporte de lo ya liberado; la cuenta en MJ no permite inferir el reparto
de masa. Las cuentas de §16.3 siguen válidas porque no asignan fase física.

El diagnóstico de identificabilidad del 2026-10-03 queda cerrado en el
documento D1: confirma ausencia de inventario kg por objeto, MLR usada como
peso/HRR y Hcomb sin base declarada. Se permite como siguiente tramo técnico
un núcleo puro `FuelMassBudgetModel.gd`, sin integración, con liberación y
oxidación independientes, balance de masa/elementos/energía e inputs
sintéticos. Esto **no** supera el gate científico para U ni autoriza una
ley material, transporte, ignición o CO/FED. Su contrato y controles están
en el documento D1. Posteriormente se escribió el
[núcleo aislado](G3_D1_FUEL_MASS_BUDGET_2026-10-03.md), ya compilado y validado:
271 checks / 39 grupos, 10/10 mutantes, referencia 346/346 con 78 gaps,
producto 168/168 y global 3323 passed. No está integrado ni cierra la
identidad física de U, una ley material o CO/FED.

### 16.5 Implementación [C]

Interruptor nuevo `fire_unburned_energy_account_enabled` (`@export`, `false`).
No sirven los existentes: el del libro v3 solo observa y no puede llevar estado
del motor; el de propiedad por objeto tiene que seguir dando las mismas
ejecuciones de la opción D que antes. Está registrado en
`audit_default_off_flags.py` como control pasivo con fixture de activación
(84 declaraciones, 42 respaldadas en ejecución).

| Archivo | Líneas | Qué hace |
|---|---:|---|
| `sim/fire/CombustionSystem.gd` | +69 | cuenta por objeto al confirmar el paso; cuentas de sala del tope, el decaimiento y el agotamiento; libro |
| `sim/core/SimulationEngine.gd` | +20 | interruptor; clave de contexto solo con él encendido; cuenta de la supresión |
| `sim/building/RoomModel.gd` | +11 | cuatro cuentas de sala, a cero al reiniciar |
| `sim/fire/FuelObjectModel.gd` | +6 | cuenta del objeto, a cero al reiniciar |
| `tools/run_scenario_headless.gd` | +14 | la instantánea de objetos muestra las cuentas solo con el interruptor |

Lo que hace, solo en salas `explicit_objects`:

- **Por objeto**, al confirmar el paso:
  `cuenta_i += débito_i · (P − T_s − G) / P`.
- **Por sala**, en el momento de cada escritura del depósito: lo que corta el
  tope, lo que quita el decaimiento, lo que quita la supresión y lo que se
  pierde al agotarse el combustible.
- **En el libro**, con el interruptor encendido: cuenta antes y después por
  objeto, y bloque `bal_account` (`unit: "MJ"`, `physical_inventory: false`).

Lo que no hace: ninguna condición del motor lee las cuentas; no se
transportan, no arden, no tienen masa ni zona y no se guardan en los
escenarios. Hay una prueba estática para cada una de esas cosas.

### 16.6 Antes y después [M]

Los mismos controles de §14–15, con la opción D activa y el libro encendido.
«Antes» es el interruptor nuevo en OFF; «después», en ON. Evidencia en
`runs/g3_unburned_account_20261003/` (análisis e informes de identidad).

| Caso | `U` confirmado (MJ) | Cuenta de objeto, después | Salida del depósito sin arder (MJ) | Cuenta de sala, después | Residuo de la identidad del combustible: antes → después (MJ) |
|---|---:|---:|---:|---:|---|
| `o2_closed` | 5,5895 | 5,5895 | 1,0113 (decaimiento) | 1,0113 | 5,59 → 6,6·10⁻¹³ |
| `o2_closed` continuo | 16,5344 | 16,5344 | 3,9269 (decaimiento) | 3,9269 | 16,53 → 6,8·10⁻¹³ |
| `o2_closed_dt24` | 5,4830 | 5,4830 | 0,9844 (decaimiento) | 0,9844 | 5,48 → 1,9·10⁻¹¹ |
| `o2_reopen_300` | 0,0226 | 0,0226 | 0,0081 (decaimiento) | 0,0081 | 0,023 → −7,9·10⁻¹⁴ |
| `o2_reopen_700` | 5,5014 | 5,5014 | 0,9883 (decaimiento) | 0,9883 | 5,50 → 4,2·10⁻¹³ |
| `sofa_vent`, `low_power_vent`, `two_active_vent`, `sofa_vent_dt24`, `o2_stress_cap` | 0 | 0 | 0 | 0 | ≤ 1,2·10⁻¹³ en ambos |

- **Antes**, el analizador marca `A_unburned_without_account` y
  `A_pool_loss_without_account` en los cinco casos con limitación de O₂.
  **Después**, ninguno de los dos aparece en ningún caso.
- **Los demás hallazgos no cambian**: la ruta del penacho que debita O₂ con
  la masa de la sala (`O_zone_mass_base`) y el paso de extinción. La cuenta no
  los toca, porque no son de su competencia.
- **Rutas que los controles no ejercitan.** En ellos solo hay decaimiento.
  - Supresión: en la fixture (0,0030 MJ) y en el control de los mutantes,
    `o2_closed` con supresión a 400 s (0,0119 MJ).
  - Tope: solo en la fixture, con capacidad reducida a propósito (0,342 MJ).
  - Agotamiento: ningún caso llega a él; solo lo cubren pruebas sintéticas
    del analizador.

### 16.7 Identidad byte a byte [M]

`scripts/simulation/run_g3_unburned_account_controls.py` compara cada caso con
las ejecuciones de §15, hechas antes de G3-4A en el otro checkout. Por caso se
comparan `sim_log.csv`, `sim_log.txt`, `fuel_source_ledger.jsonl`,
`co_inventory_trace.jsonl`, `events.json`, la instantánea de objetos y
`scenario.json`, y el libro v3 cuando se escribe.

| Cuenta | Opción D | Libro | Casos idénticos | Archivos | Libro |
|---|---|---|---:|---:|---|
| OFF | OFF (producto) | OFF | 9/9 | 63/63 | no se escribe |
| OFF | OFF | ON | 9/9 | 63/63 | SHA-256 igual en 9/9 |
| OFF | ON | OFF | 9/9 | 63/63 | no se escribe |
| OFF | ON | ON | 9/9 | 63/63 | SHA-256 igual en 9/9 |
| ON | ON | ON | 10/10 | 60/60 | 606 624 filas iguales al quitar la cuenta |
| ON | OFF (sin `explicit_objects`) | ON | 3/3 | 18/18 | 172 806 filas iguales al quitar la cuenta |

- **Con la cuenta OFF** todo es idéntico al motor anterior, incluido el libro
  completo.
- **Con ella ON** la física es idéntica: registros, trazas, eventos, libro e
  instantánea son iguales al quitar los campos de la cuenta. Solo cambian el
  `scenario.json` (lleva el interruptor) y esos campos.
- **Ningún escenario distribuido cambia.** Hay una prueba estática para ello.

### 16.8 Pruebas y mutaciones [M]

**Pruebas sin Godot y con la fixture del motor:**

- `tests/test_g3_unburned_energy_account.py` (13). La fixture
  `tests/fixtures/g3_unburned_energy_account.gd` ejecuta el motor real cuatro
  veces durante 340 s: cuenta ON, cuenta OFF, capacidad reducida y sala sin
  propiedad por objeto.
  - **Con la cuenta OFF, la identidad del combustible no cierra en 563
    pasos**, por exactamente 0,8255 MJ: la prueba falla sobre el
    comportamiento anterior.
  - Con ella ON cierra en los 4081 pasos confirmados, y la trayectoria (11
    magnitudes por paso) es la misma.
  - Las pruebas estáticas comprueban: ninguna condición lee la cuenta; el
    interruptor vale `false` y solo llega al contexto encendido; ningún
    archivo distribuido lo enciende; no se exporta ni se guarda.
- `tests/test_g3_balance_ledger.py` pasa de 65 a 78. Entre las nuevas, la
  fila anterior sin cuenta tiene que dar exactamente los dos hallazgos «sin
  cuenta».
- Inventario de interruptores: `audit_default_off_flags.py` y las seis
  pruebas que fijan el recuento (83 → 84).

**Mutaciones:**

- **Del motor, 4 de 4 detectadas**, todas válidas y con la física sin
  cambios. `sim/` se restaura byte a byte.

  | Mutante | Hallazgo | Pasos | Cantidad |
  |---|---|---:|---:|
  | MA1, la cuenta del objeto se queda con el 70 % | `A_object_account_write` | 1572 | −1,674 MJ |
  | MA2, el decaimiento no llega a su cuenta | `A_pool_account_write` (decaimiento) | 7282 | −0,999 MJ |
  | MA3, la supresión no llega a su cuenta | `A_pool_account_write` (supresión) | 24 | −0,012 MJ |
  | MA4, la parte que va al depósito se cuenta dos veces | `A_object_account_write` | 1242 | +1,195 MJ |

- **Estáticas, 22 de 22 detectadas**: 14 del analizador y 8 de las fuentes.
  Entre las de las fuentes: una condición física que lee la cuenta, el
  interruptor encendido por defecto, un caso de validación que lo enciende,
  la cuenta exportada como estado y el motor usando la cuenta como
  combustible.

**Pytest temprano.** Se ejecutó pytest global antes de las cadenas largas. Dio
2 fallos:

- la convención de las fixtures pedía una bandera `_failed`: corregido;
- la frescura R2-1 del informe de referencia: esperado hasta regenerarlo.

### 16.9 R2-1 sobre el código final [M]

Secuencial, todo Godot por el monitor. APPDATA, TEMP, TMP y `basetemp` van
fuera del checkout y cada lanzamiento exige 6 GiB.

| Comprobación | Resultado |
|---|---|
| Referencia completa | 18/18 casos, **346/346 y 78 gaps** (`runs/reference_suite_monitored_20261003_023305`) |
| `reference_checks.json` | solo cambia `generated_at` respecto a `1d4f58a6` |
| Guardarraíles | ALL PASS, incluida la frescura R2-1 |
| `check_product.py` | salida 0, **168 pruebas**, 81 lanzamientos sin fallos de salud |
| pytest global | 3302 passed, 37 skipped, 2 xfailed |

Las fixtures de pytest que lanzan Godot lo hacen por
`tests/godot_runtime_launcher.py`, que fija su propio APPDATA en
`runs/godot_test_appdata` dentro del checkout. Es el arnés existente y no se
ha cambiado.

### 16.10 Qué se ha demostrado y qué no

- **Demostrado.** Con el interruptor encendido, cada MJ debitado a un objeto
  en una sala `explicit_objects` queda en calor fresco, saldo `R`, alta pedida
  al depósito o cuenta del objeto, paso a paso y contra el inventario leído.
  Cada MJ que sale del depósito sin arder queda en una cuenta de sala por
  ruta. Con el interruptor apagado el motor es idéntico al anterior.
- **Física cambiada: ninguna.** Calor, O₂, especies, depósito, débito y
  extinciones son idénticos con la cuenta encendida.
- **Sigue siendo observable o contabilidad.**
  - `U` tiene ahora cuenta, pero **no inventario físico**: no es gas, no
    tiene masa ni zona, no se transporta y no puede arder.
  - Siguen igual el depósito congelado sin fuego, el backdraft sin ligar
    calor y combustible, la base de masa de la ruta del penacho, el carbono
    excedente y las dos cuentas de CO₂.

Riesgos:

- **Leer la cuenta como si fuera una corrección.** Mitigado con su nombre, el
  campo `physical_inventory: false`, los comentarios del motor y una prueba
  que falla si la cuenta se presenta como inventario.
- **Que un cambio futuro consuma la cuenta sin decidir D1.** Una cuenta en MJ
  no se puede llevar a una zona ni quemar sin conversión. Una prueba estática
  falla si alguna condición la lee.
- **Cobertura.** Solo cubre salas `explicit_objects`, es decir, con la opción
  D. Las salas `legacy` del producto no tienen cuenta.
- **Rutas poco ejercitadas.** El agotamiento solo está probado con filas
  sintéticas; supresión y tope, solo en la fixture y en el control de los
  mutantes.
- **Coste.** El libro con la cuenta es algo mayor y la fixture añade unos
  110 s a pytest global.

**Decisión para el siguiente tramo:**

- **GO** para dar por cerrada G3-4A como cuenta energética, OFF por defecto.
- **NO-GO** para cualquier inventario físico del inquemado hasta que se
  decida **D1** (qué es `U`). Detrás vienen D2–D5 (§16.4).
- Las especies solo sobre calor liberado y el hollín dentro del tope de
  carbono siguen autorizados como trabajo aparte; no se han mezclado aquí.
- CO/FED siguen en NO-GO.
