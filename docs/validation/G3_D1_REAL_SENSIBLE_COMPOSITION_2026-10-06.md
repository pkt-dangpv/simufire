# G3/D1 - Composición aislada: perfiles reales de n-heptano, ledger sensible y propietario atómico

Fecha: 2026-10-06. Checkpoint de entrada: `472705f1` (main = rama shareable,
locales y remotas, árboles limpios). Compone por primera vez los dos
perfiles reales
[implementados en aislamiento](G3_D1_HEPTANE_REAL_CP_IMPLEMENTATION_2026-10-06.md)
con el ledger sensible y con un propietario atómico. La vía sintética
existente queda intacta.

## Qué es y qué no es

Es un prototipo aislado y versionado. **No es un incendio validado ni una
predicción de evaporación.** Combina cinco cosas de procedencia distinta,
y cada informe las separa:

| Pieza | Naturaleza | Etiqueta en el informe |
| --- | --- | --- |
| Cp del líquido y del gas | Propiedad real derivada o correlacionada, con límites | `real_limited_primary_source_property` |
| Química y calor latente | Prototipo de referencia declarado, átomos nominales | `declared_prototype_reference_nominal_CHO_not_heptane_calibration` |
| Programa de emisión | Entrada prescrita | `prescribed_input_not_predicted_evaporation` |
| Calentamiento | Entrada prescrita, por paso | `prescribed_input_per_step` |
| Presupuesto térmico B | Sintético e independiente | `synthetic_independent_initial_budget` |

Aprobaciones, todas en `false`: `scientific_approval`,
`predictive_evaporation_approval`, `engine_integration`,
`production_activation`, `co_fed_approval`, `fire_validation_approval`, y
en el ledger `physical_approval`, `integration_enabled`,
`product_activation`.

Nada de motor, EOS, transporte, editor, escenarios o producto carga la
composición. CO/FED siguen OFF y NO-GO. B neto sigue NO-GO y es un gate
aparte.

## Contrato previo

Fijado antes de implementar. La estructura elegida es la mínima que
reutiliza los propietarios canónicos: no se copia ni el ledger ni el
propietario.

### Esquemas versionados nuevos

| Nivel | Vía sintética (sin cambios) | Vía real (nueva) |
| --- | --- | --- |
| Perfil de Cp | `g3_synthetic_isobaric_cp_v1` | `g3_real_liquid_isobaric_cp_v1`, `g3_real_ideal_gas_cp_v1` (ya existentes) |
| Estado de fases | `g3_phase_sensible_state_v1` | `g3_phase_real_sensible_state_v1` |
| Material | `g3_phase_sensible_material_v1` | `g3_phase_real_sensible_material_v1` |
| Resultado del ledger | `g3_phase_sensible_budget_v1` | `g3_phase_real_sensible_budget_v1` |
| Contexto | `g3_prescribed_sensible_context_v1` | `g3_prescribed_real_sensible_context_v1` |
| Seed | `g3_prescribed_sensible_seed_v1` | `g3_prescribed_real_sensible_seed_v1` |
| Request | `g3_prescribed_sensible_request_v1` | `g3_prescribed_real_sensible_request_v1` |
| Snapshot | `g3_prescribed_sensible_snapshot_v1` | `g3_prescribed_real_sensible_snapshot_v1` |
| Versión del propietario | `prescribed_sensible_phase_controller_v1` | `prescribed_real_sensible_phase_controller_v1` |

El material de referencia sigue siendo `g3_phase_reference_CHO_material_v1`
en las dos vías: es la misma química declarada.

**Los esquemas sintéticos no aceptan perfiles reales, ni en silencio ni de
otro modo.** Cada entrada del ledger es un contrato cerrado: nombres de
esquema, proveedor de propiedades y alcance van juntos y los fija el
contrato, no el llamador. Ningún parámetro permite pedir «el ledger
sintético con perfiles reales» ni lo contrario.

### Campos y tipos

Los campos son los mismos de la vía sintética; cambian los nombres de
esquema y el contenido admitido de los perfiles. Todos los objetos son
cerrados: una clave de más o de menos se rechaza.

- **Estado de fases** (10 campos): `schema`, `component_id` (texto no
  vacío), y ocho números finitos: `initial_fuel_mass_kg`, `liquid_fuel_kg`,
  `vapour_fuel_kg`, `o2_kg`, `thermal_budget_kj` (no negativos),
  `deposited_heat_kj`, `liquid_sensible_kj`, `vapour_sensible_kj` (con
  signo).
- **Material** (5): `schema`, `component_id`, `reference_material`,
  `liquid_profile`, `vapour_profile`.
- **Petición al ledger** (6 números no negativos): `dt_s`, `release_kg`,
  `oxidation_kg`, `heat_liquid_kj`, `heat_vapour_kj`,
  `emitted_vapour_temperature_k`.
- **Contexto** (5): `schema`, `program`, `material`, `attribution`, `seed`.
- **Seed** (6): `schema`, `initial_o2_kg`, `initial_thermal_budget_kj`,
  `initial_liquid_sensible_kj` (con signo), `energy_boundary_kind`,
  `energy_boundary_provenance`.
- **Request** (6): `schema`, `end_time_s` (tiempo físico absoluto),
  `oxidation_kg`, `heat_liquid_kj`, `heat_vapour_kj`,
  `emitted_vapour_temperature_k`. Masas y calor son por paso.
- **Snapshot** (7): `schema`, `context_fingerprint`, `generation` (entero),
  `physical_time_s`, `progress`, `phase`, `totals` (once acumuladores
  finitos).

Un `bool`, un texto o un contenedor donde va un número se rechazan sin
error de script.

### Identidad de componente y vinculación de contenido

- `component_id` es `n-heptane` en perfiles, material, estado, programa y
  atribución; cualquier desacuerdo se rechaza.
- Cada perfil debe ser **igual, valor a valor y tipo a tipo, al contenido
  aprobado** de su esquema. Lo comprueba el adaptador en cada llamada del
  ledger. Un nodo movido en 1e-9, una incertidumbre ausente rellenada con
  un número, una clase de evidencia renombrada o una masa molar cambiada a
  la nominal se rechazan.
- La identidad del contexto es `SHA-256(versión del propietario +
  serialización canónica del contexto completo)`: claves ordenadas, texto
  entre comillas y los ocho bytes IEEE-754 de cada número. Cubre perfiles,
  programa, material, atribución y seed. Cada snapshot la lleva.
- **No es una firma ni autentica una historia.** Cualquiera puede
  recalcularla; solo liga un snapshot al contenido del contexto. El informe
  lo dice: `context_content_binding_not_signature_or_history_proof`.

### Cuentas y límites de cada fase

Cuatro cuentas separadas, en kJ: A (potencial químico de lo que queda),
S (entalpía sensible con signo de líquido y vapor, respecto de 298,15 K),
B (presupuesto térmico) y Q (calor depositado). La suma A+S+B+Q se
conserva: no hay enfriamiento ni pérdidas.

Cada fase se valida **contra su propio soporte**, en entalpía:

| Fase | Soporte del perfil | Entalpía específica admitida |
| --- | --- | --- |
| Líquido | 279,985531 a 371,102911 K | −40,165 a 174,599 kJ/kg |
| Vapor | 298,135458 a 469,991581 K | −0,024 a 348,392 kJ/kg |

Se comprueba el estado inicial, el estado tras calentar y el estado final
de cada fase, y la temperatura prescrita del vapor emitido contra el
soporte del gas. **No se extrapola, no se recorta y no hay tope
artificial:** lo que cae fuera se rechaza. **No se impone una temperatura
común:** el líquido puede estar cerca de su extremo superior mientras el
vapor sale 99 K por encima de lo que el perfil líquido admite. Una fase
ausente debe tener sensible exactamente cero.

### Resultado aceptado y rechazo

- **Aceptado:** `valid = true`, el estado candidato, las cuentas del paso y
  el informe. En el propietario, además, la evidencia de la temperatura de
  emisión.
- **Rechazado:** `valid = false`, lista de errores no vacía, candidato
  vacío, informe con todas las aprobaciones en `false`, y **ningún bit del
  estado escrito**. Un calentamiento que no cabe en B rechaza el paso
  entero; no se aplica en parte.
- **Paso de duración cero:** aceptado como no-op exacto. No se aplica nada
  de lo prescrito y no cambia ningún bit de la raíz.

### Alcance científico de los informes

Además de las etiquetas de la tabla inicial, el informe del propietario
real lleva, por fase presente: procedencia del perfil, masa molar de la
fuente, errores declarados sin tocar (los ausentes siguen `null`) y las
clases de evidencia atravesadas entre la referencia y la entalpía
específica confirmada. Cada paso lleva la evidencia de su temperatura de
emisión, marcada `temperature_is_prescribed_not_predicted`. No hay
incertidumbre total (`total_uncertainty_quantified = false`) y no se
infiere ninguna temperatura a partir de una entalpía
(`temperature_inferred = false`).

## Qué cambia en GDScript

Cuatro archivos de `sim/fire/`, uno de ellos solo en un comentario:

| Archivo | Cambio |
| --- | --- |
| `FuelMassBudgetModel.gd` | El cuerpo de `propose_phase_sensible` pasa, sin tocar su aritmética, al núcleo compartido `_phase_sensible(estado, petición, material, contrato)`. Dos contratos cerrados: `SENSIBLE_SYNTHETIC` y `SENSIBLE_REAL`. `propose_phase_sensible` conserva nombre, entradas, rechazos, mensajes y valores; se añade `propose_phase_sensible_real`. El ledger precarga ahora también el adaptador real. |
| `PrescribedSensiblePhaseController.gd` | Cuatro puntos de extensión con el comportamiento de siempre: `_label` (nombres de esquema y versión), `_ledger` (entrada del ledger), `_admits` (aceptación de un estado) y `_confirmed` (lectura de un preview antes de escribir). `_fingerprint` y `_seed_phase` pasan de estáticas a de instancia para leer esos nombres. El serializador de identidad escribe ahora `true`, `false` y `null`. |
| `PrescribedRealSensiblePhaseController.gd` (nuevo) | Sucesor versionado que **hereda** del propietario sensible. Redefine los cuatro puntos de extensión, añade la evidencia al paso y al informe, y nada más: no contiene integral, estequiometría, balance, tolerancia, recorte ni estado propio. |
| `HeptaneRealCpProfiles.gd` | Solo la frase de cabecera que decía que ningún ledger ni propietario lo consumía: ahora nombra a sus dos únicos consumidores, aislados. Código y contenido aprobado, sin cambios. |

Ninguna de las funciones congeladas del ledger (`propose`,
`propose_phase_reference`, `_accepted_masses`, `_oxidation_quantities`,
`_mass_element_balance` y las demás) cambia: sus hashes por función siguen
fijados.

**Por qué el serializador.** Los perfiles reales contienen `bool` y `null`
(aprobaciones y errores ausentes). El serializador v1 los reducía a una
marca de tipo, de modo que `true` y `false` daban la misma identidad.
Ningún contexto sintético aceptado contiene esos tipos, así que el cambio
no mueve ninguna identidad sintética; lo demuestra la huella de la cadena.

## Ninguna ley nueva

| Ley | Dónde vive | Cómo se reutiliza |
| --- | --- | --- |
| Integral de la entalpía sensible | `SensibleEnthalpyModel.integrate` | A través de `HeptaneRealCpProfiles.evaluate` |
| Validación de perfiles reales | `HeptaneRealCpProfiles.validate_profile` | Proveedor del contrato real |
| Masa, CHO, productos y límites | `_accepted_masses`, `_oxidation_quantities`, `_mass_element_balance`, `propose_phase_reference` | Las llama el mismo núcleo, una vez cada una |
| Programa de emisión y acuse | `PrescribedFuelReleaseModel` | Heredado sin cambios |
| Contabilidad sensible | Núcleo `_phase_sensible` | El mismo código para los dos contratos |

No hay otra integral, otra estequiometría ni otro balance. El orden es el
de siempre: calentar, emitir, mezclar, oxidar.

- **A, S, B y Q separados.** Cada cuenta cierra por sí misma en cada paso.
- **Entalpía con signo.** Un líquido por debajo de 298,15 K tiene sensible
  negativo y lo conserva; el vapor quemado entrega a Q su sensible con
  signo.
- **Q no financia nada.** B solo decrece. Con B vacío y Q de 943 kJ, la
  emisión siguiente es cero y un calentamiento de 1 kJ se rechaza.
- **Coste de emisión:** latente + h del vapor a la temperatura prescrita −
  h específica del líquido tras calentar. Con las propiedades reales y el
  latente declarado ese coste no puede ser ≤ 0: va de 191 a 754 kJ/kg.
- **Mezcla por entalpía**, ponderada por masa. No se promedian
  temperaturas.

## Dos bases de masa

Conviven dos, con propósitos distintos, y **no se reconcilian**:

| Base | Valor | Para qué |
| --- | --- | --- |
| Masa molar de los perfiles | 100,20 g/mol, la de las fuentes | Convertir a kJ/(kg·K) los calores molares tabulados |
| Base atómica del prototipo | Nominal, C = 12 y H = 1 (C₇H₁₆ = 100,0) | Estequiometría: O₂, CO₂ y agua por kg |

No se cambia una para que coincida con la otra: un perfil con la masa
molar puesta a 100,0 se rechaza, y un material de referencia con otra base
atómica también. El informe lo expone con
`profiles_molar_mass_role`, `atom_mass_basis_role` y
`mass_bases_reconciled = false`.

**Consecuencia, declarada y no oculta en una tolerancia.** El O₂ requerido
por kg es 3,5200 con átomos nominales y 3,5126 con pesos atómicos
estándar: 0,21 % de diferencia. Para CO₂ es 0,18 % y para agua 0,12 %. Las
masas de O₂ y de productos son, por tanto, las del prototipo nominal y no
las del heptano real. Es uno de los motivos por los que la química no se
presenta como calibración. Las cuentas A, S, B y Q no dependen de ello.

**Calor latente.** El latente es el declarado por la auditoría de fases:
36,65 kJ/mol de TN 2126-upd1, 365,768 kJ/kg sobre 100,20 g/mol. No se
recalcula aquí. La fuente del gas da 36 547 J/mol a 298,16 K y saturación,
más 76 J/mol hasta gas ideal: 36,62 kJ/mol. Son compatibles dentro de los
±0,20 kJ/mol que declara TN 2126 y **siguen sin reconciliarse**
(`vaporization_reconciled_with_tn2126 = false` en el gate del gas). Es una
diferencia de 0,27 kJ/kg en el coste de emisión, por debajo de lo que esta
fase puede afirmar de todos modos.

## Soporte y evidencia

- Las incertidumbres ausentes siguen ausentes: `null` en el perfil, `null`
  en el informe. Rellenar una con un número hace que el perfil se rechace.
- Las clases de evidencia se propagan sin mejorar. El vapor a 371 K
  atraviesa el tramo que la fuente **supone** por debajo de 370 K y el
  correlacionado por encima; por encima de 466 K, el extrapolado. Las tres
  llegan al informe con su nombre.
- No se fabrica una incertidumbre total.
- La evidencia de una fase se decide **en entalpía**: se compara la
  entalpía específica confirmada con la de los extremos de cada tramo. No
  se deduce una temperatura para la fase.

## Propietario atómico y veredicto positivo

Todo lo que sigue se hereda del propietario sensible y se ha probado con
la vía real: una sola raíz agregada, preview puro, copias profundas del
contexto y de todo lo que se devuelve, commit que recalcula la intención y
nunca recibe un candidato, generaciones y conflictos, restauración
completa con generación nueva, relojes físico y de fuente, acumuladores
finitos y no-op exacto.

**La historia térmica no se reconstruye desde la masa.** Dos historias con
las mismas masas difieren en 119 kJ de sensible líquido, 122 kJ de B y
0,6 kJ de Q. El snapshot lleva esas cuentas y la restauración las exige
todas: masas frías con una cuenta térmica caliente se rechazan.

**Veredicto positivo explícito.** El propietario sintético decide por
ausencia de errores. En Godot 4.7.1 una función tipada que aborta devuelve
el valor por defecto de su tipo y el llamador continúa, de modo que una
comprobación que se detiene sin añadir errores deja pasar el estado. La
vía real no repite ese patrón:

- `_admits` acepta un estado solo si la comprobación devuelve su auditoría
  canónica con `valid` booleano y verdadero **y** no añadió errores. Si la
  comprobación se calla, añade el motivo y rechaza.
- Los tres puntos de aceptación (inicializar, previsualizar y restaurar)
  deciden por el **valor devuelto** por `_admits`, no por la lista de
  errores. Si es `_admits` quien aborta, su valor por defecto es `false`.
- `_confirmed` deja llegar a la escritura solo un preview con `valid`
  booleano verdadero, candidato no vacío y paso.
- Un commit o una restauración que termina sin resultado explícito se
  devuelve como rechazo explicado.

En la vía sintética los mismos puntos conservan su regla anterior; este
encargo no extiende el arreglo por analogía.

## Oráculos: independencia del método y de los datos

Los oráculos se fijaron antes de escribir la fixture y **no salen del
candidato**. `scripts/simulation/build_g3_real_sensible_composition.py`
no importa ni ejecuta GDScript.

| | ¿Independiente? | Detalle |
| --- | --- | --- |
| Método | **Sí** | La ley del paso se reescribe en Python desde su contrato. La emisión prescrita se integra con la primitiva, no con trapecios. El caso analítico suma los trapecios de los nodos por su cuenta. La identidad del contexto se recalcula fuera de Godot. |
| Datos de propiedad | **No** | Los mismos dos perfiles aprobados. |
| Química y latente | **No** | La misma auditoría de fases. |

Lo que la fixture demuestra es que el GDScript compone como dice el
contrato, no que los perfiles o el prototipo sean correctos. Como
contraste ajeno a las dos implementaciones, el caso analítico se compara
con las columnas H **impresas** de las tablas de las fuentes: 190,90 kJ/kg
para el gas a 400 K y 73,38 y 97,30 kJ/kg para el líquido a 330 y 340 K,
con 0,05 a 0,06 kJ/kg de margen.

Una observación de la ejecución: Godot no siempre redondea un literal
decimal como Python. Un valor del bloque aprobado difiere en dos unidades
del último bit. Por eso la identidad se recalcula a partir de los ocho
bytes de cada número tal como Godot los tiene, no de sus decimales.

## Identidad de la vía sintética

Como se extrajo lógica compartida, se demuestra la identidad del
comportamiento anterior de tres maneras:

1. **Huella de la cadena.** `tests/fixtures/g3_sensible_chain_identity.gd`
   serializa bit a bit 1985 resultados del ledger y del propietario
   sintéticos (799 aceptados y 1186 rechazados: propuestas, previews,
   commits, restauraciones, snapshots e informes) y los resume en un
   SHA-256. Capturada sobre `472705f1` **antes** de tocar nada:
   `aa407250140841a203f4e3c07c415d6b24d2ca8d6338b0794b19b7ad9e2681c9`. Es
   la misma después de cada una de las ediciones.
2. **Deshacer textual.** `undo_real_contract_edits` y
   `undo_successor_hooks` retiran del ledger y del propietario exactamente
   las ediciones declaradas y reproducen los hashes de `472705f1`
   (`7ab01e16…` y `63ea6042…`). Los pins históricos de esos dos módulos
   **no se mueven**: se comparan con el archivo deshecho.
3. **Fixtures y campañas históricas**, repetidas sobre el código final.

La huella del helper de la fase anterior tampoco cambia: 933 resultados,
`521425c7…`.

## Los skips genéricos de las fixtures de identidad

Las fixtures de identidad imprimen una huella y **ningún marcador PASS**:
no pueden juzgar su propia huella; la juzga la prueba que la fija. Por eso
dos contratos genéricos de `test_godot_fixture_fail_closed.py`, que buscan
un marcador PASS, las saltan con «fixture has no PASS marker». Esos
contratos protegen un mensaje de éxito que aquí no existe.

Lo que debe cumplirse en su lugar es que la comparación falle ante una
salida ausente, truncada o alterada. Se demuestra con controles negativos
sobre la **salida real** de cada fixture
(`tests/test_g3_identity_fixture_controls.py`):

- **Ausente:** salida vacía, sin la línea de huella o solo con el marcador
  final.
- **Truncada:** línea cortada, huella de 40 caracteres, flujo cortado
  antes del final, marcador de fin ausente o antes de la huella.
- **Alterada:** un dígito de la huella, contadores que suman igual,
  contadores que no suman, campos de más, tipos cambiados, línea
  duplicada, error de script en la salida.
- **Cambio real de comportamiento:** en una copia aislada, una sola ley
  cambiada; el corpus termina y la huella ya no coincide.

Toda lectura de esas huellas pasa por un lector estricto
(`tests/g3_identity_output.py`). **No se añade un marcador PASS y no se
elimina ningún skip.** La fixture nueva de la cadena añade dos skips del
mismo tipo, por la misma razón.

## Pruebas en Godot

`tests/fixtures/g3_real_sensible_composition.gd` ejecuta el GDScript real:
3670 comprobaciones en catorce grupos, sin errores de script.

| Grupo | Qué demuestra |
| --- | --- |
| K01 | Entrada real del ledger: esquema, alcance y aprobaciones; ninguna entrada acepta el contrato de la otra; soporte y calentamiento todo o nada en el propio ledger. |
| K02 | Caso analítico por tramos con propiedades reales: líquido en un nodo, calentado exactamente hasta el siguiente, vapor en un nodo. |
| K03 | Once secuencias prescritas contra el oráculo: cuentas del paso, estado, relojes, A, S, B y Q, cierre de cada cuenta por separado, total conservado y clases de evidencia. |
| K04 | Mezcla por entalpía: cuatro mezclas del corpus en las que un promedio de temperaturas daría otra entalpía, entre 0,5 y 16 kJ/kg. |
| K05 | Emisión limitada por B, oxidación limitada por O₂ y por inventario; con B vacío, Q no paga nada. |
| K06 | Dos historias con las mismas masas y distinto calentamiento; la restauración exige todas las cuentas térmicas. |
| K07 | Corrida continua frente a reinicio: mismo estado, bit a bit. |
| K08 | Restauración rechazada sin escritura: 33 campos alterados, snapshots parciales, generaciones ajenas. |
| K09 | Falta de confirmación positiva, con tres dobles: comprobación que calla, puerta que se detiene y preview sin resultado explícito. |
| K10 | Identidad: las 209 hojas del contexto la mueven una a una; doce contextos alterados rechazan el snapshot original; perfiles alterados bajo el mismo esquema, rechazados. |
| K11 | Separación: el propietario sintético rechaza el contexto real, también disfrazado; y al revés. |
| K12 | Soporte y desbordamiento: extremos aceptados, un 1e-9 fuera rechazado, `NaN`, infinitos, `bool` y texto rechazados. |
| K13 | Raíz única, preview puro, copias profundas, generaciones, no-op exacto y acumuladores iguales a la suma de los pasos. |
| K14 | Etiquetas: qué es real, qué es declarado y qué es sintético; presupuesto y emisión no admiten un nombre mejor. |

Casos pedidos y dónde están: entalpía negativa y referencia (`cold_liquid`,
con el líquido a −40 kJ/kg y el vapor emitido a 298,14 K); fases ausentes
(`exhaust`, líquido agotado, y el vapor inicial); masas pequeñas
(`small_mass`, 1e-9 kg); aislamiento de producto (pruebas estáticas en
`tests/test_g3_real_sensible_composition.py`).

## Mutaciones en Godot

**Campaña de la composición**
(`scripts/simulation/run_g3_real_sensible_composition_mutations.py`): 94
variantes predeclaradas, cada una en una copia aislada de los seis scripts
y de la fixture. Control en verde, **94/94 muertas**, ningún superviviente
y ninguna corrida inválida; fuentes de trabajo intactas por SHA-256. Un
error de análisis o de script no cuenta como muerte. Evidencia:
`runs/g3_real_sensible_composition_mutations_20261006_183819/`.

| Familia | Nº | Qué inyecta |
| --- | --- | --- |
| L, núcleo del ledger | 24 | Soporte ignorado; proveedor equivocado en cada sentido; emisión recortada al soporte; sensible omitido en la emisión, en la mezcla y en la oxidación; promedio en vez de suma de entalpías; Q que paga la emisión o entra en B; calentamiento que no cabe y se descarta; oxidar antes de emitir; calor en un paso nulo; signo recortado; pérdida nueva; perfil sin vincular a componente o a fase; esquemas sin comprobar; alcance reetiquetado; integración activada; fase ausente con sensible. |
| B, propietario heredado | 39 | Cada uno de los cinco puntos de aceptación ignorado; restauración que pierde la historia térmica o la reconstruye desde la masa; commit parcial; identidades térmicas omitidas; preview que escribe; alias del snapshot; contexto sin copiar; identidad sin perfiles, seed, programa, material o atribución; `bool` y `null` sin serializar; decimales en vez de bits; presupuesto y emisión sin comprobar; informe que reetiqueta el presupuesto; aprobaciones; relojes; esquemas. |
| C, propietario de la composición | 27 | Veredicto no exigido o laxo; puerta retirada; preview sin confirmar que llega a escribir o que se devuelve como válido; entrada o nombres sintéticos; evidencia omitida o inflada; errores declarados omitidos; presupuesto, química, emisión, propiedades y alcance reetiquetados; bases de masa «reconciliadas»; incertidumbre total; temperatura inferida o presentada como predicha; CO/FED y validación aprobados; preview que escribe; rechazo mudo; masa molar nominal. |
| F, controles del oráculo | 4 | Un número del bloque esperado movido una parte por millón: la fixture lo lee de verdad. |

Corresponden a lo pedido: ignorar soporte o evidencia, reetiquetar el
presupuesto, omitir sensible en emisión, mezcla u oxidación, autofinanciar
con Q, saltarse la validación positiva, restauración parcial, perfil o
contexto equivocado, historia reconstruida desde la masa, escritura en
preview y activación o integración indebida.

**Campañas históricas.** Se repiten las once de la cadena aislada sobre el
código final. Nueve copian un archivo que cambió (el ledger, el
propietario o ambos). Dos, el helper sintético y el replay medido, no
dependen de nada modificado y habrían conservado su evidencia por hash; se
repiten igualmente. Once controles en verde, **228/228 muertas**, ningún
superviviente ni corrida inválida, fuentes intactas:

| Campaña | Resultado |
| --- | --- |
| Helper sintético | 19/19 |
| Presupuesto de masa | 10/10 |
| Referencia de fases | 12/12 |
| Emisión prescrita | 11/11 |
| Replay medido | 11/11 |
| Caller de referencia | 18/18 |
| Ledger sensible | 23/23 |
| Propietario sensible | 40/40 |
| Guardas de tipo | 12/12 |
| Veredicto positivo | 17/17 |
| Adaptador real | 55/55 |

**Conservan su evidencia por hash, sin repetir:** las campañas del motor
sobre `CombustionSystem.gd` (balance, propiedad del combustible, opción D
y cuenta del inquemado). Ninguna de sus fuentes cambia: en `sim/` solo se
modifican dos archivos de la cadena aislada y se añade uno, y nada del
motor los carga. La suite de referencia cubre el motor.

## Pins y allowlists adaptados

Adaptación estrecha; no se borra ningún contrato.

Ningún hash histórico se mueve: se comparan con el archivo **deshecho**.

| Prueba o runner | Cambio | Por qué |
| --- | --- | --- |
| `test_g3_type_guard_contracts.py`, `test_g3_reference_caller_positive_verdict.py`, `test_g3_sensible_phase_controller.py`, `test_g3_heptane_real_cp_profiles.py` | Los hashes de `FuelMassBudgetModel` y `PrescribedSensiblePhaseController` se comprueban tras deshacer las ediciones de esta fase | Los dos módulos cambian; el pin sigue demostrando que no cambió nada más |
| `test_g3_fuel_mass_budget.py` | Precargas del ledger: de una a dos, ambas nombradas | El contrato real nombra su proveedor |
| `test_g3_heptane_real_cp_profiles.py` | Consumidores del adaptador: de ninguno a exactamente el ledger y el propietario real | La composición existe; los dos siguen aislados |
| `test_g3_sensible_phase_budget.py` | El núcleo llama a `properties.evaluate`; se exige que la entrada sintética lleve el contrato sintético; el propietario real entra en la lista de llamadores aislados | El proveedor lo fija el contrato |
| `test_g3_sensible_phase_controller.py` | El sucesor puede heredar del propietario y llamar a la entrada real | Es el único consumidor nuevo |
| Siete runners de mutación | Copian también `HeptaneRealCpProfiles.gd` | El ledger lo precarga; sin él la copia aislada no carga |
| `run_g3_sensible_owner_mutations.py` | Cinco anclas reapuntadas (identidad, auditoría del seed y tres esquemas) | El texto pasa por `_label` y `_ledger`; cada mutante inyecta el mismo defecto |
| `run_g3_sensible_phase_mutations.py` | Dos anclas reapuntadas (esquemas de estado y material) | El nombre viene del contrato |

## Cadena final sobre el código final

Tandas largas secuenciales, por `godot_monitored_launch.py` y
`run_reference_suite_monitored.py`; nunca Godot directo y ningún proceso
ajeno terminado. El runner de referencia no se sondeó con `--help`.
APPDATA, TEMP, TMP y basetemp nuevos bajo el temporal externo
`simufire_real_composition_20261006_01`. Los siete módulos de la cadena en
`sim/fire` y las tres fixtures conservaron su SHA-256 desde antes de las
campañas finales hasta el final de la cadena. Sin procesos Godot
residuales.

**Fixture de la composición:** 3670 comprobaciones, catorce grupos, sin
errores de script. **Huella de la cadena sintética:** 1985 resultados,
`aa407250…2681c9`, la capturada antes de tocar nada.

**Mutaciones, sobre el código final.** Doce campañas, doce controles en
verde, **322 mutantes muertos** (94 de la composición y 228 históricos),
ningún superviviente ni corrida inválida, fuentes intactas.

**Referencia (R2-1, exigida al tocar `sim/`): PASS.** 18/18 casos, salida
0, informe nuevo y errores de salud vacíos en todos; stderr vacío;
3137,3 s sumados; mínimo disponible antes de lanzar un caso 7,68 GiB; logs
sin `SCRIPT ERROR`, `Parse Error` ni violación de acceso. Comparador:
**346/346 required PASS, 78 gaps**. ALL GUARDRAILS PASS, R2-1 incluido.
Evidencia: `runs/reference_suite_monitored_20261006_191542/`.

Identidad de informes, tres nociones que no se mezclan:

- *Bytes.* Los **160 informes de caso** son idénticos byte a byte a la
  copia tomada antes de la tanda.
- *Fin de línea.* `reference_checks.json` sale de la suite con CRLF
  (SHA-256 `9162b3c1…9547450d`) y Git lo guarda en LF
  (`964dbf66…6781b1d4`). Son dos secuencias de bytes con dos hashes.
- *Contenido.* En ese resumen cambia una sola línea de 19 269,
  `generated_at` (2026-10-06T09:08:01Z → 2026-10-06T18:08:04Z); la
  comparación estructural da esa única clave.

**Producto: PASS.** `scripts/check_product.py` monitorizado: **168/168**,
salida 0, stderr vacío.

**Global: PASS.** `python -m pytest tests -q -p no:cacheprovider` con
basetemp externo nuevo: **3981 passed, 45 skipped, 2 xfailed, 42 subtests**, salida 0, 675,30 s, stderr vacío;
7,66 GiB disponibles antes y 7,70 después. Respecto a la última global publicada (3946 / 43 / 2, en `472705f1`): 18 pruebas de la composición, 11 de los controles de identidad y 8 de las comprobaciones genéricas de fixtures sobre las dos fixtures nuevas. Los dos saltos nuevos son de esas comprobaciones sobre la fixture de identidad de la cadena, por la razón explicada arriba.

**Offline.** Bloque de expectativas generado al día. Estilo GDScript
PASS; enlaces de los documentos modificados PASS; `git diff --check`
limpio. Las cifras de la cadena se escribieron en la documentación después
de la global, sin tocar código ni pruebas; a continuación se repitieron,
sin Godot, las pruebas que leen esos documentos y las estáticas de esta
fase: 141 y 38 en verde. Ya publicado `c7f4f00b` y con memoria liberada
por el usuario (7,79 GiB disponibles), se repitieron esos módulos enteros
sobre ese commit: **156 passed**, incluidas las 15 pruebas que lanzan
Godot; árbol limpio y ningún proceso Godot residual.

## Intentos que no cuentan

- **Primera ejecución de la fixture.** Sin errores de script, 3338
  comprobaciones y varios fallos. Uno era un **defecto real del
  candidato**: un commit devolvía como válido un preview sin confirmar,
  aunque no lo escribía. Se corrigió en el propietario. Los demás eran de
  la fixture o del oráculo: el O₂ consumido calculado por diferencia, que
  pierde precisión con masas pequeñas; una temperatura de 371,2 K
  clasificada por error como fuera del soporte del gas; y la identidad
  recalculada desde decimales, que no coincide con Godot.
- **Tanda G3 previa a adaptar los pins.** 12 pruebas rotas, todas pins y
  anclas que la nueva dependencia mueve por diseño. Sirvió para listar qué
  adaptar; no cuenta.
- **Primera campaña de la composición** (`…_160822`): detenida en su
  tercer mutante por la guarda de memoria, 5,88 GiB disponibles frente a
  los 6 exigidos. **No se bajó el umbral.** Su segundo mutante dio una
  corrida inválida: un propietario que no llegaba a inicializarse hacía que
  la fixture escribiera en un snapshot vacío, y el informe leía campos de
  un perfil que el adaptador no aprobaba. Se corrigieron las dos cosas.
- **Pausa por memoria.** Con un navegador del usuario abierto, la memoria
  disponible osciló entre 2,7 y 6,2 GiB durante unos quince minutos. No
  se lanzó Godot en ese tiempo ni se terminó ningún proceso ajeno; se
  siguió con trabajo offline.
- **Segunda campaña** (`…_161730`): completa, 90/94. Tres supervivientes y
  una inválida, resueltas una a una:
  - *Emisión recortada al soporte* y *calentamiento que no cabe y se
    descarta* sobrevivían porque el propietario los detiene con una
    segunda barrera. Se añadieron comprobaciones en el propio ledger.
  - *La generación avanza en un paso nulo* sobrevivía porque un no-op no
    escribe. Ahora el preview de un paso nulo debe proponer la raíz
    confirmada, bit a bit.
  - *La restauración ignora la puerta del estado guardado* era inválida:
    sin comprobación alguna se escribe un snapshot mal formado y el
    propietario aborta. Se redefinió como la regla antigua, decidir por
    ausencia de errores, que es lo que el encargo prohíbe repetir.
- **Tanda parcial de esos cuatro** (`…_163951`): 4/4. Sustituida por la
  campaña completa.
- **Primera cadena completa** (campaña `…_164112`, referencia
  `…_171841`): toda en verde, con las mismas cifras de pruebas y mutantes
  que la final. Al revisar el diff antes de publicar se vio que la cabecera
  del adaptador real seguía afirmando que ningún ledger ni propietario lo
  consumía, lo que esta fase hace falso. Se corrigió esa frase. Como
  cambia un archivo de `sim/`, **la cadena entera se repitió sobre el
  código final** y las cifras de este informe son las de la repetición.
- **Repetición focal tras documentar.** Al repetir los módulos de esta
  fase después de escribir las cifras, las 15 pruebas que lanzan Godot se
  negaron a arrancar por la guarda de memoria, con 5,4 GiB disponibles y un
  navegador del usuario abierto. No se bajó el umbral. Esas 15 no leen
  documentación y habían pasado en la global sobre el mismo código; las 141
  restantes, que sí incluyen las que la leen, pasaron. Esa tanda no cuenta;
  la que cuenta es la repetición posterior con memoria liberada, 156
  passed, recogida en la cadena final.

## Qué sigue sin validar

- **No es un incendio.** No hay llama, penacho, zona, EOS ni transporte.
- **La emisión no se predice.** El programa de emisión y la temperatura
  del vapor emitido son entradas. Evaluar un Cp de gas ideal a una
  temperatura prescrita no dice cuánto vapor hay disponible ni a qué
  temperatura sale: no hay presión de vapor, equilibrio de fases ni
  transferencia de calor y masa en la superficie.
- **B es sintético.** No procede de ningún flujo de calor medido ni
  calculado. Un B predictivo es el gate de B neto, que sigue NO-GO.
- **La química es un prototipo declarado**, con átomos nominales y sin
  productos de combustión incompleta.
- **Las propiedades tienen los límites de sus gates:** gas ideal sin
  corrección de gas real, supuesto por debajo de 370 K, extrapolado por
  encima de 466 K y sin soporte por encima de 470 K; líquido convertido
  desde Csat; escala de temperatura convertida de forma aproximada;
  incertidumbre total sin cuantificar.
- **Tolerancias heredadas.** Las del ledger son absolutas (1e-12 kg y
  1e-9 kJ). Con masas del orden de 1e-9 kg el cierre de masa pierde poder;
  el caso de masa pequeña se compara aquí con el oráculo en relativo.

**Por qué no hay CO/FED.** CO y FED necesitan productos de combustión
incompleta, transporte y exposición. Aquí la oxidación es completa por
contrato, no hay zonas y la emisión no se predice. Ninguna de esas piezas
existe en esta composición, así que no hay nada que activar: CO/FED siguen
OFF y NO-GO.

## Siguiente gate pendiente

Decisión del usuario, no iniciada. Esta fase **no** conecta la composición
al incendio activo, no amplía el gas, no implementa un B predictivo y no
activa CO/FED. Siguen abiertos, sin relación de orden entre ellos: B neto,
el gas por encima de 470 K y qué haría falta para que la emisión deje de
ser una entrada prescrita.
