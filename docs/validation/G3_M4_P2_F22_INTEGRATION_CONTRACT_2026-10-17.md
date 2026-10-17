# G3 - M4-P2 → F2.2: contrato de integración de la energía con `V·dp`

Contrato: 2026-10-17. **Solo diseño**: sin `sim/`, sin Godot, sin referencia ni
producto. Base: `5c140001` + M4-P2-GD en revisión
([registro](G3_M4_P2_GD_IMPLEMENTATION_2026-10-17.md)). Antecedentes:
[contrato M4-P2](G3_M4_P2_GAS_ENERGY_EOS_CONTRACT_2026-10-17.md) y
[F2.2](../PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md) §13.1, §14.1, §16.
[Plan predeclarado](G3_M4_P2_F22_INTEGRATION_PLAN_2026-10-17.json), SHA-256
LF `5e8a59d63afcf3951ad49b2d2d19a4a61b5277c56e84bb7a61a5ed5370def873`.
M4-C/D, CO/FED y producto siguen OFF/NO-GO. La sensibilidad temporal del
motor sigue **abierta**.

## 0. Qué hace hoy la red (lectura de código)

- Con `pressure_network_solver_enabled` (OFF por defecto) el adaptador
  `PressureNetworkTransportSystem` toma el snapshot **después** de la física
  local del paso (combustión, O₂, térmica, extinción), con `sources = {}`
  (`PressureNetworkTransportSystem.gd:548-588`): el calor local ya está dentro
  de `E_z`.
- Estado por zona: `m_z` y `E_z`, entalpía sensible sobre `T_ref` con
  `c_p = 1,0`. El solver itera la presión manométrica con el residuo
  `R((M − M_ref)·T_ref + E/c_p)/V − p` (`Phase3CoupledPressureSolver.gd:2613-2617`)
  y `R = 101325/(1,2·T_ref)`. Cada segmento lleva `q·E_d/m_d = q·c_p(T_d − T_ref)`;
  el exterior, `c_p(T_ext − T_ref)`.
- El aplicador suma `ΔE` y `Δm` (`:822-880`); escala colectivamente las salidas
  que piden más masa de la que hay (`:655-667`): una capa puede quedar vaciada
  **exactamente**.
- Orden del paso (`SimulationEngine.gd:4150-4214`): física local → red →
  HVAC → combustible pasivo → propagación. Lo que escribe en `E` o `m` después
  de la red cae en el paso siguiente.

## 1. Resultado analítico: F2.2 es la primera ley dividida por γ

Con el mismo calor `Q` y las mismas parcelas `q` a `T`:

```text
F2.2:    Δ(pV/R) = Δm·T_ref + ΔE/c_p = Q/c_p + Σ q·T
M4-P2:   Δ(pV/R) = ΔU/c_v = (Q + Σ q·c_p·T)/c_v = γ·(Q/c_p + Σ q·T)
```

Por tanto **`dp/dt` de la red es exactamente el de la primera ley dividido por
γ** en cualquier estado (γ = 1,40456 con el juego del motor). Consecuencias:

1. Sala estanca: sobrepresión y subida de temperatura /γ (testigo W1 de M4-P2).
2. Sala con fugas o aberturas: el **estado cuasiestacionario es el mismo**
   (con `dp ≈ 0` las dos leyes exigen `Q + Σ q·c_p·T = 0`); el **transitorio**
   es γ veces más lento. Probado en el testigo WI2: en una sala de 50 m³ con
   10 kW y 5·10⁻³ m² de fuga, el cociente de presiones empieza en 1,39–1,40 y
   vale 0,9996 a los 30 s.
3. Por capas: la red no comprime la capa pasiva (`W_z` ausente); el error es
   proporcional a `dp`, pequeño cuando la sala ventila.

La EOS de F2.2 es correcta como identidad (`pV = R·Σ m·T`): lo que cambia es
la evolución de la energía, no la EOS.

## 2. Decisiones previas del usuario

**Autorizadas por el usuario el 17-10, las tres según la recomendación.** El
plan (con hash) no cambia: ya las declaraba como recomendadas.

| Decisión | Recomendación | Motivo |
| --- | --- | --- |
| a. Juego de propiedades | `engine_equivalent_293_15` (`c_p = 1,0`; `R` fija = valor actual a 293,15 K) | Todos los escritores de `E` derivan `T` con `c_p = 1,0`; `cfast_tn1889` (`c_p = 1,012`) obliga a cambiarlos todos y es otro gate |
| b. Adoptar `V·dp` en la red | Sí, tras un interruptor **nuevo**, OFF por defecto | Corrige transitorios y salas estancas sin tocar el producto isobárico |
| c. Inventario inicial con `R` fija | `m = p_ext·V/(R·T_ref)` con el interruptor encendido | Con `1,2·V` y `R` fija, una sala a 283,15 o 303,15 K empieza a ∓3 456 Pa (WI4) |

### 2.1 Alcance de la primera versión: HVAC desactivado (decisión del usuario, 17-10)

El HVAC queda **fuera de la primera versión** y se pondrá en marcha después de
publicarla. Para esta integración:

- No se integra el escritor `HVACSystem` (`_apply_supply_heat`, transporte de
  aire y extracción de humo). Con el interruptor nuevo encendido, un edificio con
  HVAC disponible es un error de configuración explícito, no un caso que se
  ignore ni que se resuelva por la ruta histórica.
- Hoy el HVAC se activa por escenario: 8 presets jugables y 2 escenarios de
  referencia (`compact_apartment_reference`, `long_hallway_reference`) traen
  datos de HVAC. Desactivarlo en producto es una tarea aparte, con su propia
  revisión de escenarios y de referencia; este contrato no la ejecuta.
- Reactivar el HVAC será un gate posterior: sus caudales y su calor entrarán
  como parcelas y calor de M4-P2, con sus casos y mutantes.

## 3. Arquitectura propuesta: corrección en la frontera de la red

Interruptor provisional `pressure_network_internal_energy_enabled`, OFF,
**exige** `pressure_network_solver_enabled` (error explícito si no, como D1–D3
y R3). Recuento de interruptores 84 → 85.

Por paso, con los dos encendidos:

1. **Libro comprometido**: la red guarda `m_z`, `U_z` y `O_z` de su último
   commit. `U_z = (E_z + m_z·c_p·T_ref)/γ` es el adaptador explícito de M4-P2
   §7, con `T_ref` solo como origen de `E`.
2. **Evento local**: en el snapshot, cada zona trae `δm_z`, `δE_z` desde el
   commit anterior (física local, HVAC y combustible pasivo del paso previo).
   Su entalpía absoluta es `A_z = δE_z + δm_z·c_p·T_ref`; se aplica con la
   regla de M4-P2 (`r`, `φ`) desde el libro comprometido. El calor prescrito
   sigue siendo exacto e independiente del paso.
3. **Solver**: la misma red, con el incremento de aberturas multiplicado por γ
   en el residuo **y** en el jacobiano. El estado de partida es el del evento
   local, convertido a `E`; su EOS es la misma identidad.
4. **Evento de aberturas**: las rutas ya escaladas por F2.2C entran como
   parcelas de M4-P2 (donante = snapshot); la regla reparte `U` entre capas
   con `W_z`. Especies y O₂ siguen viajando en los paquetes de F2.2C; la masa de
   M4-P2 y la de los paquetes se comparan.
5. **Escritura**: `E_z = γ·U_z − m_z·c_p·T_ref`; presión publicada
   `(γ−1)·U/V − p_ext(z)`, la misma que el solver convergió.

Alternativas descartadas para este paso: llevar `U` en todo el motor
(reescribir todos los escritores de `E`) o que cada sistema local publique
fuentes en vez de escribir `E`. Las dos son más invasivas; la frontera de la
red da la misma física de sala con un solo punto de cambio. Límite declarado:
dentro del paso, la física local ve temperaturas sin `V·dp` hasta el commit
(separación de operadores, primer orden).

## 4. Conflictos que la implementación debe resolver

| # | Conflicto | Regla |
| --- | --- | --- |
| K1 | El escalado colectivo de F2.2C vacía una capa exactamente; si la presión cambia, M4-P2 la rechaza (`layer_depleted_while_pressure_changes`, WI6) | Partir el paso en la fracción de vaciado o fallar con nombre; nunca dejar un residuo de energía sin masa |
| K2 | Con `R` fija, `RoomModel.reset` siembra `1,2·V` | Con el interruptor, inventario inicial `p_ext·V/(R·T_ref)` (decisión c) |
| K3 | Escritores locales que no sean un par `(δm, δE)` físico (reconstrucciones por EOS, proyecciones) | Inventariarlos con la red encendida antes de programar; uno no físico bloquea |
| K4 | `Phase3ResidualProjection` rechaza energía negativa (F2.2 §23) | Comprobar que no se ejecuta en esa ruta o resolverlo antes |
| K5 | Dos eventos por paso con repartos distintos | `U` de sala exacta; el reparto entre capas difiere en primer orden y se publica (WI5) |
| K6 | `project_room_state` deriva la geometría de capa con `R(T_ref)` (`EquationsScript.zone_geometry_from_state`) | Con `R` fija, la misma `R` en la geometría; dos `R` en un paso es un defecto |

### 4.1 K3/K4: inventario de escritores locales (lectura de código, 17-10)

109 escrituras de `upper/lower_gas_kg` y `upper/lower_energy_kj` en 6 archivos
(unas 30 funciones). Con la red encendida, `ZoneFireSolver.canonical_mass_conservation_enabled`
y `authoritative_transport_enabled` (GasExchange, OxygenExchange, Thermal) se
encienden con ella (`SimulationEngine.gd:1377`, `:1553-1555`). Primera
clasificación; falta comprobar cada compuerta con una ejecución instrumentada:

| Clase | Funciones | Para la integración |
| --- | --- | --- |
| Par físico `(δm, δE)` dentro de la sala | `ZoneFireSolver.apply_lower_to_upper_transfer`, `ThermalSystem._ensure_minimal_upper_gas` (mueve 0,08 m de capa), `_add_flame_region_entrainment` | Transferencia interna: se representa (A_u = −A_l en entalpía); el disparador de la capa mínima es artificial pero conserva |
| Calor sin masa | combustión/pérdidas en `ThermalSystem.step`, `_step_radiation_openings`, `_step_wall_conduction`, `HVACSystem._apply_supply_heat`, `remove_lower_energy_fraction` | Se representa como `δQ_z` |
| Mezcla isobárica declarada | inversión térmica o capa fina en `project_room_state` (reparte E conservando la suma) | Con `r = 1` equivale a M4-P2; se acepta como modelo declarado |
| **Sumidero numérico declarado** | tope de temperatura superior en `project_room_state` y `_clamp_rooms`; tope de escalera `_apply_phase3_stairwell_temperature_cap` (si su flag está activo) | Aparece como calor negativo; hay que publicarlo aparte en el recibo, no esconderlo dentro de `A_z` |
| **Recorte no físico** | `SimulationEngine._clamp_rooms:5581-5584` pone `E ≥ 0` en las dos zonas **sin compuerta**; `ZoneFireSolver.apply_lower_to_upper_transfer` y `add_lower_energy` recortan `E ≥ 0`; `ensure_room_state` recorta masa negativa y siembra `1,2·V` en una sala vacía | **Bloqueante (K3)**. Con la red, F2.2-R2-MASS declara válida la energía sensible negativa (sala por debajo del ambiente), pero `_clamp_rooms` la anula al final de cada paso: crea energía. Posible defecto **ya existente** en la ruta F2.2 encendida, a confirmar con una ejecución antes de integrar |
| Proyección que reescribe E desde T | `reconcile_projected_temperatures`, rama no canónica de `sync_room_upper_layer` | Comprobar que no se ejecutan con la red encendida; si lo hacen, bloquean |
| Geometría con `R(T_ref)` | `EquationsScript.zone_geometry_from_state` dentro de `project_room_state` | **K6 nuevo**: con `R` fija (decisión a) la geometría también debe usarla, o habría dos `R` en el mismo paso |
| Transporte por aberturas | rutas de puertas, escaleras e intercambio de fondo (`ThermalSystem:2925`, `:3115`, …; `GasExchangeSystem:317`, `:1482`, …) | Con compuerta `authoritative_transport_enabled`: deben ser no-op con la red; verificar las de `_apply_doorway_thermal_counterflow`, `_apply_canonical_doorway_exchange` y `_apply_stairwell_heat_bridge` |

Compuertas verificadas en el código con la red encendida:

- `ThermalSystem:1390`: el bucle de aberturas interiores hace `continue` antes
  del contraflujo térmico, la puerta canónica y la mezcla vertical posterior
  (`:1392`, `:1549`, `:1554-1555`). El **puente de escalera** (`:1383`) va antes
  y sigue activo: es calor entre salas sin gas, representable como calor.
- `ThermalSystem:2925`, `:3115`: intercambio de fondo exterior e interior, no-op.
- `ThermalSystem:1654`: la radiación por aberturas siembra la capa superior como
  un paquete de la capa baja de la misma sala (par físico).
- `GasExchangeSystem:317` (presión termodinámica), `:1482` (venteo), `:1767`
  (bucle de aberturas de `step_smoke`, que incluye `_apply_background_species_exchange`
  y las escrituras de `:2074`, `:2249`), `:2729` (limpieza postincendio) y
  `:4244` (PPV, rechazo explícito): no-op con la red. Sigue la física local
  (generación y deposición de humo, renovación ACH).

K4 resuelto: `Phase3ResidualProjection` solo lo usa
`Phase3ResidualProjectionShadow`, una sombra de telemetría con su propio
interruptor (`SimulationEngine.gd:1217`, `:2418-2460`) que no escribe estado.
No está en la ruta de la red: **no bloquea**.

**Confirmado con una ejecución (17-10, sonda fuera del repositorio, por el
monitor):** sala sellada de 57,6 kg con las dos zonas bajo el ambiente
(`E` = −80 y −992 kJ, la siembra del test 08 de F2.2C). Tras **un paso completo**
del motor con la red encendida: `E` = 0 y 0 kJ, `temp_lower_c` = 20 °C,
`overpressure_pa` = 0, transacción aplicada sin fallo; idéntico con la red
apagada. Es decir, la ruta F2.2 encendida **crea 1 072 kJ** en un paso y borra
la depresión por enfriamiento que su contrato declara válida (F2.2-R2-MASS).
El test 08 no lo veía porque aplica solo la transacción de la red. La presión
publicada en 0 Pa indica que el recorte actúa **antes** de que la red lea el
estado (o también antes): el escritor exacto **no está aislado** —
`_clamp_rooms` es uno, y hay otros candidatos en la física local del paso.
Defecto ya existente de F2.2, **bloqueante para la integración**, a aislar y
corregir como gate propio con su propia referencia. Sigue pendiente comprobar
que `reconcile_projected_temperatures` no se ejecuta en esa ruta.

## 5. Casos, tolerancias y mutantes (plan)

El plan fija nueve casos: identidad OFF bit a bit y referencia 346/0/78 (I0);
cada commit repetido por el oráculo de M4-P2 (I1); cociente γ del primer paso
(I2); isentrópica de la capa baja (I3); estado cuasiestacionario igual con
fugas (I4); vaciado con presión cambiante (I5); inventario inicial a 283/293/303 K
(I6); medición de paso a 1/60, 1/12 y 1/3 s (I7, sin umbral nuevo) y
`cfast_single_room_closed` frente a CFAST y frente a OFF (I8, sin cambiar
tolerancias). Tolerancias: las de M4-P2 para recibos y cierres; cociente
`1e-9`, cuasiestacionario 1 %, presión inicial `1e-6` Pa. Doce mutantes GD
cerrados en el plan.

## 6. Testigos de hoy (Python, sin Godot)

[`g3_m4_p2_f22_integration_oracle.py`](../../scripts/simulation/g3_m4_p2_f22_integration_oracle.py)
reproduce la ley de F2.2 desde sus ecuaciones documentadas y la compara con el
oráculo de M4-P2, sin modificarlo.
[`test_g3_m4_p2_f22_integration_contract.py`](../../tests/test_g3_m4_p2_f22_integration_contract.py):

| Testigo | Resultado |
| --- | --- |
| Hash del plan y del plan de M4-P2 | PASS |
| WI1: cociente γ con calor ±, entrada, salida y mixto; EOS de F2.2 = identidad | PASS (5 + 1) |
| WI2: fuga, transitorio /γ y mismo cuasiestacionario | PASS |
| WI3: adaptador `E ↔ U` y entalpía local de `(δm, δE)` | PASS |
| WI4: `1,2·V` con `R` fija → ±3 456 Pa; cero con `p_ext·V/(R·T_ref)` | PASS |
| WI5: un paso en dos eventos | PASS |
| WI6: vaciado por escalado con calor → rechazo | PASS |

**12 passed.** Cinco mutantes temporales del oráculo de integración (ley F2.2
con `c_v`, entalpía local sin el término de masa, fuga integrada con la primera
ley, adaptador sin γ, entrada con entalpía sensible) mueren todos; archivo
restaurado por SHA. Corrección registrada antes de evaluar: el primer
enunciado de WI5 («compone con un evento») era falso para repartos distintos;
se reescribió en el plan antes de ejecutar ningún testigo.

## 7. Qué es nuevo y qué no

Nuevo: lectura de código de §0, la relación exacta de §1, este contrato, el
plan con hash, el oráculo de integración y 12 testigos. No se ejecutó el motor:
las consecuencias para `cfast_single_room_closed`, las fugas reales y la
sensibilidad al paso son **hipótesis** hasta I7–I8.

## 8. Siguiente paso concreto

Decisiones de §2 autorizadas. Antes de programar: commit de M4-P2-GD (para que
la integración sea un diff aparte) e inventario de los escritores locales con
la red encendida (K3, K4). Después, implementar tras el interruptor nuevo,
fixture y auditor con el oráculo de M4-P2, los 12 mutantes y la cadena completa.
