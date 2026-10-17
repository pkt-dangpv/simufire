# G3 - M4-P2-GD: módulo GD aislado gas/energía/EOS

Fecha: 2026-10-17. Base: `5c140001` (contrato M4-P2, commit local sin push).
**Entrega para revisión, sin commit.** Prototipo puro sin consumidores: no se
conecta al motor, no cambia F2.2 ni el producto, y no elige propiedades del gas
para el producto (son entradas del libro). La sensibilidad temporal del motor
sigue abierta: las pruebas del calentador no la resuelven.
[Contrato](G3_M4_P2_GAS_ENERGY_EOS_CONTRACT_2026-10-17.md) ·
[plan](G3_M4_P2_GAS_ENERGY_EOS_PLAN_2026-10-17.json) (SHA-256 LF `e20814fc…`, sin cambios).

## 1. Discrepancias entre contrato, plan y oráculo (registradas antes de implementar)

Revisión de los tres antes de escribir el GD. Ninguna es física: son de nombres
o de alcance. **No se modificó ninguno de los tres**; se decide cómo las trata
el GD y el auditor.

| Id | Discrepancia | Tratamiento |
| --- | --- | --- |
| D1 | El plan lista `inflow_financing_outflow` aparte; el oráculo (y su test) rechaza ese caso como `overdraft_of_donor` | El GD distingue ambos: `inflow_financing_outflow` si la salida bruta supera el snapshot pero no snapshot + entradas del mismo paso; si no, `overdraft_of_donor`. El auditor los trata como una sola clase |
| D2 | Cantidad de parcela negativa: el oráculo dice `negative_value` y el plan `negative_mass`; el oráculo usa además `o2_out_of_range`, que el plan no lista | El GD usa `negative_mass` y `o2_out_of_range`; el auditor mapea `negative_value` a `negative_mass` |
| D3 | El plan exige `stale_context_or_revision`, `geometry_changed_within_run` y `property_set_changed_within_run`; el oráculo no tiene libro, revisión ni evento | Solo los comprueba el fixture GD; el oráculo no puede auditarlos |
| D4 | Sala sin gas (`U = 0` en las dos capas): el oráculo dividiría por cero; no es caso del contrato | El GD la rechaza como `room_without_gas` (nombre extra) |
| D5 | El contrato (§3) deriva la entalpía sensible con `T_ref`, pero el plan no pone `T_ref` en el libro | El libro GD lleva `reference_temp_k` **solo** para ese observable. Así se puede expresar el mutante `R_from_reference_temperature` |
| D6 | El oráculo admite un único exterior por paso; M4-P1 lleva `T`/`Y` por parcela de frontera | El GD conserva la parcela de M4-P1 (`boundary = {Y, T_k}`); el auditor se niega a auditar un evento con exteriores distintos (no hay ninguno en el plan) |
| D7 | El oráculo guarda el calor como diccionario por capa (una segunda entrada sobrescribiría la primera); M4-P1 admite varias | El GD suma; el auditor suma antes de llamar al oráculo |
| D8 | El mutante `work_not_antisymmetric`: con `W_z` derivado por definición (§5.1.5), romper la antisimetría rompe el cierre de energía de la sala | Su aserción declarada es el cierre de energía de la sala, no la identidad de `W` |

## 2. Implementación

- [`PhysicalGasEnergyEosModel.gd`](../../sim/core/PhysicalGasEnergyEosModel.gd):
  módulo puro sin `class_name`, exports, escenas ni consumidores; su única carga
  es `DetMath` (obligatorio en `sim/` para `pow`). API de M4-P1: `validate`,
  `observables` y `propose`. El recibo lleva copias aisladas de antes y después,
  evento, parcelas con su entalpía y su O₂, calor, por sala `U0`, `U1`, `r`,
  `r^k` y `φ`, por capa `A_z` y `W_z`, y los totales de frontera.
  Base `physical_gas_energy_eos_v1`. El libro lleva `gas = {cp, R}` como
  **entrada**: el módulo no contiene `c_p`, `R`, `γ`, `T_ref` ni `p_ext` literales
  (lo comprueba un test). Regla §5.1 del contrato, con el mismo orden de suma que
  el oráculo.
- [Fixture](../../tests/fixtures/g3_m4_p2_gas_energy_eos.gd): lee el plan JSON y
  toma de él casos, pasos y tolerancias. Cada paso aceptado se audita dentro del
  fixture: entalpía y O₂ de parcela desde el snapshot, cierre de energía por sala
  y del edificio, masa y O₂ pareados, EOS, volumen e interfaz. Emite recibos,
  rechazos y finales para el auditor.
- [Auditor](../../scripts/simulation/audit_g3_m4_p2_gas_energy_eos.py): adaptador
  al oráculo **sin modificar el oráculo**. Rehace cada recibo con `oracle.step`,
  repite los rechazos expresables (clase D1/D2), compara los finales con las
  formas cerradas en `Decimal` y vuelve a calcular C7/C9 con el oráculo.
- Runners: [control](../../scripts/simulation/run_g3_m4_p2_gas_energy_eos.py),
  [mutantes](../../scripts/simulation/run_g3_m4_p2_gas_energy_eos_mutations.py) y
  [cierre](../../scripts/simulation/run_g3_m4_p2_gas_energy_eos_closure.py), todos
  por el monitor. Pruebas offline:
  [`test_g3_m4_p2_gas_energy_eos_gd.py`](../../tests/test_g3_m4_p2_gas_energy_eos_gd.py).
- Inventario M4-B (`test_g3_m4_adapter_diagnosis.py`): admite exactamente esta
  segunda adición pura, conserva los 64 históricos y la de M4-P1, y comprueba que el
  módulo no escribe campos O₂ de sala.
- Arnés compartido de mutantes (`run_g3_o2_m3_reservation_mutations.py`):
  **sin cambios** (sus bytes los fija la evidencia de M3). El runner de M4-P2
  envuelve solo la llamada al monitor para elevar el timeout de lanzamiento de
  180 a 900 s, como su control; lo demás se delega al monitor sin cambios.

SHA-256 de lo ejecutado (texto del checkout):

| Archivo | SHA-256 |
| --- | --- |
| Módulo GD | `c5e5b1992e4411e42f6feba5718e88527b4ba70868454fd90d10b17612845131` |
| Fixture GD | `a683e7cf4bbcc2116c9d91407b6d8b61674cf4b4c75f919735f93e9a6537a760` |
| Auditor | `9bb84c882ae40413f46cbc9df8ba5dee84251dbc4ec1845b755915ceda9fa923` |
| Oráculo (sin cambios desde `5c140001`) | `4c1d34f448c05f5c0a159bf4d0bf88063b0818b233d9a498ca6f5e6cc93174a1` |
| Plan (sin cambios) | `e20814fcbb03bd6ba8e6383c3dac6c3d4aa8069dc426f8a8f1e0346073a32eb5` |

## 3. Resultados nuevos de esta entrega

Registros externos en `%LOCALAPPDATA%/Temp/`, no en Git.

| Verificación | Resultado aceptado | Registro |
| --- | --- | --- |
| Control GD por el monitor | **655 731 checks, 0 fallos**, 132 s, monitor limpio | `simufire_m4p2_control_final_20261017` |
| Auditoría con el oráculo | 95 recibos idénticos al oráculo (diferencia relativa máxima 0,0), 10 rechazos de la misma clase y 36 finales analíticos dentro de 1e-11 | ídem |
| C7 orden (GD) | 1,0125 / 1,0062 / 1,0031 / 1,0015; error a 1/12 s 8,084·10⁻⁵ | ídem |
| C9 orden (GD) | 1,0062 / 1,0031 / 1,0015 / 1,0008; error a 1/12 s 1,973·10⁻⁵ | ídem |
| Mutantes del plan | **16/16 muertos** en su aserción declarada, control en verde, SHA restaurado, sin timeouts ni terminaciones; repetida con el arnés compartido intacto (intento 3) con el mismo resultado | `simufire_m4p2_mutations_r2_20261017` (antes `…_final_…`) |
| Offline nuevos y guardas | 33 PASS (P2-GD, inventario M4, DetMath); 481 guardas offline que escanean `sim/` PASS; arnés compartido 15 PASS | — |

Los errores de C7/C9 del GD coinciden con los del oráculo Python hasta ~10⁻¹⁶.
Los casos de calentador son exactos en GD para 1/60, 1/12, 1 y 60 s y con los
dos juegos de propiedades. Eso **no** dice nada de la sensibilidad temporal del
motor, que sigue abierta.

### Intentos que no cuentan como cierre

1. **Primer control**: el fixture pasó (655 731 checks, 0 fallos) y la auditoría
   validó recibos y rechazos, pero se detuvo en los finales de dt = 1/60. El JSON
   «full precision» de Godot escribe 1/60 como `0.01666666666666666`, 2–3 ulp
   del doble original, y el auditor emparejaba `dt` por igualdad exacta. Se
   corrigió solo la identificación del `dt` (tolerancia relativa 1e-12 para
   reconocer el paso del plan, nunca para comparar física). Ninguna tolerancia
   del plan cambió y el control se repitió entero. Nota permanente: el JSON de
   Godot no reproduce los dobles bit a bit (~10⁻¹⁶ relativo), por debajo de
   las tolerancias de identidad (1e-12).
2. **Primera campaña**: M01 y M02 murieron donde se declaró; M03 superó el
   timeout fijo de 180 s del arnés compartido. Su payload llegó a imprimirse
   entero; el monitor terminó **su propio** proceso, no uno ajeno. Es
   infraestructura, no una muerte: no se contó. El fixture tarda unos 132 s en el
   control y más con muchos fallos. Se añadió el parámetro `timeout_s` y se repitió
   la campaña completa desde el control.
3. **Primera global** (`simufire_m4p2_closure_global_20261017`): 5221 PASS,
   3 FAIL. Uno era de esta entrega:
   `test_g3_m3_current_evidence` fija el SHA-256 del arnés compartido que
   juzgó las campañas M3, y el parámetro `timeout_s` añadido lo cambiaba. No se
   tocó el test ni el registro M3. Se restauró el arnés a HEAD (SHA LF
   `1802038d…`, el registrado), el timeout pasó a un envoltorio en el runner
   de M4-P2 (con un test offline nuevo) y se repitió la campaña de mutantes
   entera y después la global. Los otros dos fallos son históricos, ver §4.
4. Antes del primer control la memoria disponible estaba en 5,84–5,99 GiB, por
   debajo del mínimo de 6. Se esperó sin bajar el umbral ni cerrar procesos;
   se lanzó con 6,15 GiB y la campaña final con 7,66.

## 4. Cadena por tocar `sim/core`

Ejecuciones nuevas del 17-10, secuenciales, todas por el monitor
([cierre](../../scripts/simulation/run_g3_m4_p2_gas_energy_eos_closure.py)),
con el control y la campaña finales como prerrequisitos y verificación de los
SHA-256 del módulo, fixture, auditor, oráculo y plan, de todas las fuentes de
`sim/`, de los nueve stashes y de que no aparezcan `.uid` nuevos. Ninguna vio
procesos Godot ajenos.

| Etapa | Resultado | Duración | Registro |
| --- | --- | --- | --- |
| Referencia (`run_reference_suite_monitored.py`) | **346 requeridos, 0 fallos, 78 huecos**; de 958 archivos del corpus, 957 idénticos y solo `reference_checks.json` cambiado, **solo en `generated_at`** (revisado en el diff, no aceptado automáticamente) | 55,7 min | `simufire_m4p2_closure_reference_20261017` |
| Guardarraíles (`validation_guardrails.py`) | ALL GUARDRAILS PASS, incluida R2-1 (frescura de informes) | 3 s | `simufire_m4p2_closure_guardrails_20261017` |
| Producto (`check_product.py`) | **171 PASS**, 0 FAIL | 10,1 min | `simufire_m4p2_closure_product_20261017` |
| Global (`pytest tests`), repetida tras el intento 3 | **5222 PASS**, 108 skip, 2 xfail; 3 FAIL, ninguno de esta entrega (abajo). La etapa queda `failed` y no se maquilla | 15,7 min | `simufire_m4p2_closure_global_r2_20261017` |
| `tests/test_playable_homes_runtime.py` aislado | 2 PASS (con 7,09 GiB libres) | 30 s | — |

Los tres fallos de la global repetida:

- `test_playable_homes_runtime.py::test_acceptance_rejects_an_actually_drawn_piece_outside_its_room`:
  **no llegó a ejecutarse**, porque la puerta de memoria del monitor se negó a
  lanzar Godot con 5,52 GiB libres. Es infraestructura y no cuenta ni como
  fallo ni como paso. Repetido aislado con memoria suficiente: PASS. En la
  primera global había pasado.
- `test_godot_runtime_defaults.py::test_primary_runners_default_to_godot_471` y
  `test_g3_m2t_transport_closure.py::test_shared_monitor_changes_only_the_three_declared_decoders`:
  **históricos**. Fallan desde `4b88c57e` (15-10, «make tooling portable»),
  que quitó las rutas de Godot cableadas de `scripts/run_scenario.py` y
  `tools/mutation_audit.py`, mientras los dos tests siguen exigiendo esas rutas
  o el AST de `920affb7`. Esos archivos son idénticos a HEAD y fallaron igual en
  las dos globales. No se tocaron: corregirlos es decidir si el test sigue a la
  regla de portabilidad de AGENTS.md, y queda fuera del alcance de M4-P2.

`reference_checks.json` queda modificado en el árbol con el nuevo
`generated_at` para entrar junto con `sim/` en el commit de esta entrega. El
baseline couch_tv y `project.godot` siguen con sus cambios ajenos (el corpus
de la referencia los dio idénticos antes y después).

## 5. Qué queda abierto

- Sin commit (a petición): módulo, fixture, auditor, runners, test, este
  documento, el inventario M4-B, la referencia regenerada y las notas de
  handoff, roadmap, plan G3 y checklist.
- Decisiones para la integración, no tomadas aquí: juego de propiedades del gas
  del producto (`engine_equivalent_293_15`, `cfast_tn1889` u otro) y si la red
  F2.2 migra su energía a `U` con `V·dp` (cambiaría trazas y obligaría a
  regenerar la referencia con revisión de diferencias).
- Sensibilidad temporal del motor: **sigue abierta**. Que el calentador sea
  exacto e independiente del paso en el prototipo no dice nada del motor vivo
  (1/12 s a ×1, 1/3 s a ×20, sin subpasos, `dt` variable con el hilo).
- Siguiente paso concreto: revisión de esta entrega y, con su visto bueno,
  commit; después, diseño de la integración M4-P2 → red F2.2 detrás de un
  interruptor apagado, con las dos decisiones anteriores como prerrequisito.

## 6. Revisión previa al commit (17-10, a petición)

Revisión de M4-P2-GD contra el contrato, el plan y el oráculo **originales**
(sin cambios: plan `e20814fc…`, oráculo `4c1d34f4…`, contrato del commit
`5c140001`). Las §3–4 describen el módulo `c5e5b199…` y pasan a ser evidencia
**histórica**; esta sección registra lo nuevo.

### 6.1 Los ocho desajustes, clasificados

| Id | Clase | Por qué es inocuo, o qué se corrigió |
| --- | --- | --- |
| D1 | Nombre | Mismo rechazo atómico; el GD usa los dos nombres del plan (`PhysicalGasEnergyEosModel.gd:267-270`). Probado con `R inflow_financing_outflow` y `R overdraft_of_donor`; el auditor acepta solo ese par como una clase (`audit_g3_m4_p2_gas_energy_eos.py:25`, con test offline) |
| D2 | Nombre + cobertura | `negative_value` → `negative_mass` (mapa explícito). `o2_out_of_range` es nombre del propio oráculo (`g3_m4_p2_gas_energy_eos_oracle.py:118-119`) para un estado fuera del plan. Ninguna condición del plan sale con un nombre ajeno a la lista: los 20 rechazos del plan se comprueban por su nombre, ahora también vía `propose` para libros inválidos (fixture `:712`, `:721`) |
| D3 | Cobertura | El oráculo no tiene libro ni evento; el fixture prueba los tres motivos. Límite declarado, no corregido: el módulo detecta un cambio de geometría o propiedades **entre el libro y lo que declara el evento** (`:136-146`); si el llamador reescribe el propio libro no hay referencia anterior. Es el diseño de M4-P1 (el libro es la autoridad) |
| D4 | Cobertura | Sala sin gas: `p = 0` y `r = U¹/U⁰` indefinido. El oráculo lanza `ZeroDivisionError` (`oracle.py:220`, ejecutado hoy), no un rechazo; el GD la rechaza con nombre propio (`:377`). El plan no tiene ese estado |
| D5 | Cobertura | `reference_temp_k` solo entra en `E_sensible` (`:114`) y en la validación. **Demostrado nuevo**: el mismo evento con `T_ref` = 283,15/293,15/303,15 K da salas idénticas bit a bit («D5 T_ref inert», fixture `:652` y sig.) |
| D6 | Cobertura | El GD acepta un exterior por parcela; el oráculo, uno por paso. **Nuevo**: evento con dos exteriores distintos auditado en el fixture parcela a parcela («D6 two exteriors»); el auditor sigue sin pasarlo al oráculo (`audit…py:75`) |
| D7 | Comportamiento de interfaz | El oráculo recibe el calor como diccionario por capa (no admite dos entradas); el GD suma. **Nuevo**: calores de 4 + 6 kJ en una capa = 10 kJ de una vez, bit a bit, y el recibo pasa por el oráculo con la suma del auditor («D7 heat sum») |
| D8 | Cobertura de prueba | `W_z` es derivado (§5.1.5): su antisimetría es identidad dada la clausura. M12 cae en «energy closure» y también en «work antisymmetric» |

Ninguno es una diferencia física de la regla §5.1.

### 6.2 Hallazgos y correcciones

| # | Archivo:línea | Hallazgo | Clase | Acción |
| --- | --- | --- | --- | --- |
| F1 | `sim/core/PhysicalGasEnergyEosModel.gd:313-318` (antes `O = O⁰ + ΔO`) | Vaciado completo de una capa a `p` constante (C10b): `m` y `U` quedan en cero exacto, pero el O₂ se descontaba como `(q·O)/m`, que con `q = m` no siempre devuelve `O` (≈10 % de estados aleatorios; p. ej. `m = 36 kg`, `Y = 0,21`: residuo 8,9·10⁻¹⁶ kg). El candidato queda con O₂ sin masa y se rechaza como `candidate:o2_out_of_range`, nombre fuera del plan: incumple C10b y la lista cerrada de §8 | **Comportamiento** | Corregido: una capa vaciada (`retained = 0`, solo posible con `r = 1`) queda con el O₂ que le llega en el paso, cero exacto si no le llega ninguno; parcelas y su O₂ no cambian. **Demostrado antes de corregir**: fixture ampliado contra el módulo `c5e5b199…`, único fallo «C10b O2 rounding accepted» de 657 177 checks (`simufire_m4p2_review_demo_prefix_20261017`) |
| F1-or | `scripts/simulation/g3_m4_p2_gas_energy_eos_oracle.py:188, :250` | El oráculo usa la misma expresión: deja `O = 8,9·10⁻¹⁶` con `m = 0`, que su propio `validate_room` rechaza en el paso siguiente (ejecutado hoy) | Comportamiento (oráculo) | **No se modifica el oráculo** (encargo). El auditor compara con el suelo de masa del plan (1e-12 kg); por ese recibo la diferencia máxima GD–oráculo pasa de 0,0 a 1,7·10⁻¹⁷ relativo |
| F2 | fixture `:395` (antes «C5 H» con `1.0e-9`) | Tolerancia del fixture que no venía del plan, aplicada a una diferencia | Tolerancia inventada | Se compara `H_z` final en la clase exacta del plan (`1e-11`), que es lo que el plan pide |
| F3 | `audit_g3_m4_p2_gas_energy_eos.py:240-243` (antes `1e-9·err + 1e-15`) | Tolerancia inventada en el auditor para C7/C9 | Tolerancia inventada | El fixture publica `T` final y el auditor la compara con la del oráculo en la clase exacta del plan (`1e-11` + suelo 1e-9 K); test offline nuevo que la rompe con 3·`1e-11` |
| F4 | fixture (varias) | Comprobaciones declaradas en el plan que el fixture no hacía: `T_z`, `V_z` e interfaz contra la forma cerrada (C2, C3); `U` y `T` (C4); independencia del paso (C5, C6, C8); O₂ entrante (C8); `U` constante por paso y entalpía de salida acumulada = `Q·t` (C7); `R` heredada variable (C11) | Cobertura | Añadidas con las tolerancias del plan. Pasan también con el módulo sin corregir: no ocultaban nada |
| F5 | — | Sin hallazgo: unidades (kJ, kW·s, Pa = kJ/m³·1000), balances de sala, edificio y capa, trabajo `V·dp` (isentrópica de C2), estados límite (`r = 1`, serie de `φ`, nacimiento, vaciado), rechazos atómicos (sin libro ni recibo, entradas intactas), alias (copias profundas, M15), independencia (el auditor solo importa el oráculo; el fixture recalcula sin usar el cálculo del módulo) y ausencia de consumidores (solo el fixture lo carga) | — | — |
| F6 | Edición | Al editar con `Path.write_text` en Windows, cinco archivos quedaron en CRLF (módulo, fixture, auditor, handoff, roadmap). Lo detectó la prueba de anclas de los mutantes antes de lanzar nada; se devolvieron a LF y los SHA de §6.4 son LF. La demostración F1 corrió con el fixture en CRLF (mismo contenido) | Proceso | — |

Mutantes: las 16 aserciones declaradas son físicas o de contrato (M07 cae en
«C9 order» y «C9 error decreasing», M13 en «parcel snapshot same donor»…);
ninguna muerte se debe a un error de script, a una aserción genérica de
aceptación ni a un timeout. La lista sigue siendo la cerrada del plan.

### 6.3 Tests anteriores a esta entrega (cambio aparte de M4-P2)

`4b88c57e` (15-10, ADR 0006) sustituyó las rutas `C:/Users/dangp/Desktop/…` y
`F:/OneDrive/Escritorio/…` por el resolvedor compartido
`scripts/project_paths.py`/`.ps1` (argumento, `GODOT_EXE`, PATH, Escritorio de
la máquina con preferencia por `v4.7.1-stable` y consola). Dos tests seguían
exigiendo la ruta cableada. Contratos actualizados, sin borrar ni saltar nada:

- `tests/test_godot_runtime_defaults.py`: los cinco ejecutores primarios deben
  delegar en el resolvedor compartido y no contener rutas de máquina; el
  resolvedor Python elige `Godot_v4.7.1-stable_win64_console.exe` frente a
  4.7.1 sin consola, 4.8 y 4.6.3 en un Escritorio con espacios y «ñ»; el de
  PowerShell ordena por `v4.7.1-stable` y luego por consola. Se conserva
  `test_active_runners_do_not_default_to_godot_463`.
- `tests/test_g3_m2t_transport_closure.py`: el AST de `tools/mutation_audit.py`
  sigue congelado frente a `920affb7` salvo los tres decodificadores y **solo**
  el bloque de descubrimiento, que debe ser exactamente el portable; además, sin
  literales con letra de unidad.

Que no se han debilitado: 6 mutantes temporales (ruta cableada en un ejecutor
Python y en uno PowerShell, preferencia 4.7.1 quitada en cada resolvedor,
severidad del monitor cambiada, ruta cableada otra vez en el monitor): **6/6
detectados**, archivos restaurados por SHA. Riesgo residual que el ADR acepta y
no se cambia: un `godot` del PATH tiene precedencia sobre el Escritorio sin
comprobar su versión.

### 6.4 Resultados nuevos

SHA-256 (LF) de lo revisado: módulo `6a7c1f15e2ca34d19ed2fcca6638c71207773144dec1b76b2d9878ff27a3540c`,
fixture `90304bdc8cefef34c50283204582437850d8886876714717ea4609903ec75025`,
auditor `811f5cd39376a644a2d498d9b940940111c56281dfeaadb604ba9252b160e6cc`;
oráculo `4c1d34f4…` y plan `e20814fc…` sin cambios. Registros en
`%LOCALAPPDATA%/Temp/`.

| Verificación | Resultado | Registro |
| --- | --- | --- |
| Demostración F1 (módulo `c5e5b199…`, fixture ampliado) | único fallo «C10b O2 rounding accepted» de 657 177 checks | `simufire_m4p2_review_demo_prefix_20261017` |
| Control (módulo corregido) | **657 199 checks, 0 fallos**; auditoría: 97 recibos (máx. 1,7·10⁻¹⁷ relativo frente al oráculo), 10 rechazos, 36 finales; C7/C9 con `T` final en la clase exacta del plan | `simufire_m4p2_review_control_20261017` |
| Mutantes del plan | **16/16** muertos en su aserción declarada; control en verde; SHA restaurado | `simufire_m4p2_review_mutations_20261017` |
| Referencia | **346/0/78**; 957 de 958 archivos idénticos; solo `generated_at` (diff revisado); 41,8 min | `simufire_m4p2_review_reference_20261017` |
| Guardarraíles | ALL GUARDRAILS PASS (R2-1 incluida) | `simufire_m4p2_review_guardrails_20261017` |
| Producto | **171 PASS**; 10,5 min | `simufire_m4p2_review_product_20261017` |
| Global (`pytest tests`) | **5239 PASS**, 108 skip, 2 xfail, 67 subtests; 1 FAIL ajeno a M4-P2: `tests/test_engine_thread.py:103` (`hud_gets_the_fp_state`), intermitente bajo carga (ver intento 7). La etapa queda `failed` y no se maquilla | 15,1 min | `simufire_m4p2_review_global_r3_20261017` |
| Offline | P2-GD 16, contrato P2 38, inventario M4, DetMath; tests históricos reparados 31 + 25 subtests; 6/6 mutantes temporales de esos tests | — |

Intentos de esta revisión que no cuentan:

5. **Primera global de la revisión** (`simufire_m4p2_review_global_20261017`):
   5238 PASS y 2 FAIL, los dos de inventario y causados por los archivos nuevos
   del contrato de integración (no por M4-P2-GD): el contrato nombra en prosa la
   primitiva de proyección residual de H3.2b y el test de sus testigos nombra
   el interruptor de la red F2.2. Se registraron en las listas de esos tests
   con su motivo, como las entradas existentes (F2.2 y las suites D1–D3), sin
   quitar ninguna comprobación. Los dos tests históricos de `4b88c57e` ya
   pasaron en esa global.
6. **Segunda global de la revisión** (`simufire_m4p2_review_global_r2_20261017`):
   5239 PASS y 1 FAIL de inventario, causado por este mismo registro: el
   intento 5 nombraba la primitiva por su identificador. Se reformuló sin él.
7. **Tercera global** (`simufire_m4p2_review_global_r3_20261017`, la de la
   tabla): el único fallo es
   `test_first_person_and_hud_refresh_on_different_ticks`, de la línea del
   hilo del motor (`1b09e1d4`). Comprueba que, en el tick en que cambia el
   minimapa, su estado es el mismo objeto que el de la vista en primera
   persona; si el hilo publica un estado entre los dos refrescos, eso falla.
   Ese test pasó en las dos globales anteriores, y el módulo aislado
   (`tests/test_engine_thread.py`) pasó 3/3 al repetirlo después (11 PASS
   cada vez). M4-P2-GD no tiene consumidores y no toca `Main.gd` ni las
   vistas. Queda como hallazgo aparte de la línea de FPS, sin corregir aquí.
