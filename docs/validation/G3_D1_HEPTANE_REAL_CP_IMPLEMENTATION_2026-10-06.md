# G3/D1 - Implementación aislada de los esquemas reales de Cp del n-heptano

Fecha: 2026-10-06. Checkpoint de entrada: `628393d8` (main = rama shareable,
locales y remotas). Implementa en GDScript los dos esquemas reales que
aprobaron los gates del
[05-10](G3_D1_HEPTANE_REAL_PROFILE_ELIGIBILITY_2026-10-05.md) (gas) y del
[06-10](G3_D1_HEPTANE_LIQUID_ELIGIBILITY_2026-10-06.md) (líquido).

Alcance: evaluación aislada de la propiedad. **No** hay predicción de
temperatura ni de evaporación, inversión h→T, presupuesto B, calor latente
nuevo, corrección de gas real, otro combustible ni integración en motor,
EOS, transporte, editor o producto. El ledger y el propietario sensible
**siguen rechazando** perfiles reales. CO/FED siguen OFF y NO-GO; B neto
sigue NO-GO y es un gate aparte.

## Qué cambia en GDScript

Dos archivos de `sim/fire/`:

| Archivo | Cambio |
| --- | --- |
| `SensibleEnthalpyModel.gd` | El bucle de integración de `evaluate` pasa, sin tocar su aritmética, a la función compartida `integrate(samples, temperature)`. `validate_profile` y `evaluate` conservan entradas, rechazos, mensajes, campos y valores. No valida esquemas reales. |
| `HeptaneRealCpProfiles.gd` (nuevo) | Contenido aprobado de los dos esquemas, validación estricta contra ese contenido y evaluación mediante `integrate` del helper. No contiene ninguna integral propia. |

El helper tiene ahora dos consumidores aislados: el ledger de masa y este
adaptador. Ningún archivo de motor, editor, interfaz o producto carga el
adaptador.

Funciones públicas del adaptador:

- `approved_profile(schema)`: copia independiente del perfil aprobado.
- `validate_profile(profile)`: acepta solo un perfil igual, valor a valor y
  tipo a tipo, al contenido aprobado de su esquema.
- `evaluate(profile, temperature_k)`: Cp y entalpía sensible con signo,
  h(T) − h(298,15 K).
- `evaluate_interval(profile, start_k, end_k)`: h(final) − h(inicial), con
  signo, ambos extremos dentro del soporte.

## Contrato

Esquemas cerrados: `g3_real_liquid_isobaric_cp_v1` y
`g3_real_ideal_gas_cp_v1`, con los diecinueve campos que fijaron los gates.
No se añade un tercer contrato.

| | Líquido | Gas |
| --- | --- | --- |
| Magnitud | Cp isobárico a 100 000 Pa, convertido desde Csat | Cp° de gas ideal |
| `caloric_model` | `declared_liquid` | `ideal_gas` |
| Nodos | 14 | 19 |
| Soporte ITS-90 | 279,985531 a 371,102911 K | 298,135458 a 469,991581 K |
| Referencia | 298,15 K y 100 000 Pa | 298,15 K y 100 000 Pa |
| Masa molar | 100,20 g/mol, la de la fuente | 100,20 g/mol, la de la fuente |
| Unidad | kJ/(kg·K) | kJ/(kg·K) |

**Vinculación al contenido.** El llamador no declara un hash: el validador
compara el perfil entero con la constante `APPROVED` del propio script.
Cualquier diferencia de clave, tipo, longitud o valor se rechaza y se
localiza en el mensaje. Los números son siempre `float`; un `int`
numéricamente igual también se rechaza. Esta vinculación no es una firma ni
prueba el origen de un perfil: quien edite el script cambia la constante.
Lo que la sostiene es el bloque generado y los pins descritos más abajo.

Se rechaza por tanto: fuente o contenido distinto, nodos alterados,
remuestreados o fuera del soporte, unidades, masa molar, escala o
referencia distintas, fase, modelo o ruta incompatibles, Csat sin
convertir, NaN, infinito, booleanos, texto, tipos incorrectos, campos de
más o de menos, clases de evidencia elevadas e incertidumbre ausente
sustituida por cero.

**Consultas.** Sin extrapolación; entalpía con signo; los desbordamientos
los rechaza la integral compartida; la entrada no se modifica y los
resultados son copias independientes.

**Resultado válido.** Además de Cp y entalpía: esquema, sustancia, fase,
modelo, ruta, referencia, escala, masa molar, soporte, procedencia y
estado de calibración; el intervalo integrado `enthalpy_interval_k`; las
clases de evidencia que ese intervalo atraviesa, recortadas a él; los
errores declarados del perfil, con sus valores ausentes como `null`; y
`total_uncertainty_quantified: false`. Los límites son los del intervalo
integrado, no solo los del punto final.

**Rechazo.** `valid: false`, lista de errores no vacía y candidato vacío.

En ambos casos, ámbito
`real_primary_source_property_isolated_not_fire_validation` y cuatro
aprobaciones en `false`: `physical_approval`, `integration_enabled`,
`product_activation` y `ledger_composition_approval`.

## De dónde salen los datos

Los nodos no se transcriben. `scripts/simulation/build_g3_heptane_real_cp_profiles.py`
toma los perfiles candidatos de los dos auditores offline y escribe el
bloque `APPROVED` del adaptador. Una prueba falla si el bloque del script
deja de coincidir con lo que producen los auditores, y estos a su vez fijan
por hash sus fuentes y sus registros de revisión.

- Líquido: Csat de NBS RP2526 convertido a Cp a 100 kPa con la identidad
  completa y con datos de densidad cuyo origen es el National Institute of
  Standards and Technology, ThermoML/Data Archive, doi:10.18434/mds2-2422.
  Los valores son derivados aquí; no son valores del NIST. La mención
  figura también en la cabecera del script.
- Gas: ecuaciones 22 y 23 de NBS RP2526.
- La tabla de la reevaluación de 1994 (JPCRD), con derechos reservados, no
  forma parte del perfil. Una prueba comprueba que ningún nodo coincide con
  sus valores citados.

Un cambio respecto al gate del 05-10: el contenido aprobado del gas
incorpora tres límites que estableció el gate del 06-10 y que antes no
viajaban con el perfil: `scale_conversion_kind:
approximate_on_smoothed_values`, `scale_approximation_residual_percent:
null` y `molar_mass_and_scale_verified_at_origin: false`. El esquema no
estaba implementado; su auditor y su resultado guardado se actualizan.

## Qué es propiedad real derivada y qué sigue supuesto

| Elemento | Naturaleza |
| --- | --- |
| Cp del líquido, 280-360 K de la fuente | Derivado de una tabla de mediciones; error probable de la fuente ±0,1 % |
| Cp del líquido, 360-370 K | La misma tabla; la fuente dice que el error crece y no da valor: `null` |
| Cp del líquido, 370 K al punto de ebullición | Interpolación hacia una fila fuera de la parte ajustada de la tabla |
| Conversión Csat → Cp | Identidad exacta con entradas aproximadas; residuo declarado 0,01 J/(mol·K); artículo de la densidad no inspeccionado |
| Cp del gas, 298,16-370 K | **Supuesto adoptado por la fuente**, no medición |
| Cp del gas, 370-466 K | Correlación de calorimetría citada |
| Cp del gas, 466-470 K | Extrapolación tabulada por la fuente |
| Masa molar y escala de la calorimetría del gas | **Supuestos sin verificar en origen** |
| Conversión a ITS-90 | **Aproximada**: se convierten valores suavizados. Líquido: hasta 0,056 % frente a la evaluación publicada. Gas: sin residuo medible, `null` |
| Gas real | No se corrige |
| Incertidumbre total | No cuantificada |

Fuera del soporte no hay dato: el líquido acaba en su punto de ebullición a
100 kPa y el gas en 470 K, lejos de temperaturas de llama.

## Identidad del esquema sintético

- **Corpus bit a bit.** 933 validaciones y evaluaciones sintéticas (565
  aceptadas y 368 rechazadas: perfiles de 2 a 21 nodos, nodos, interiores,
  vecinos de un ulp, extremos, NaN, infinitos, tipos y campos inválidos) se
  serializan con `var_to_bytes` y se resumen con SHA-256. El resumen es
  `521425c7…fad950a8` con el helper de `628393d8`, tomado antes de tocarlo,
  y el mismo con el helper final. Cubre valores, tipos, orden de claves y
  mensajes.
- **Fixture histórica S01-S20:** 342 comprobaciones, sin cambiar ninguna
  expectativa.
- **Campaña histórica del helper:** las 19 mutaciones predeclaradas siguen
  aplicando sobre el código extraído. Resultado en la cadena final.
- Prueba estática: una sola aparición de `integral += area` en el helper,
  dentro de `integrate`, y ninguna integral propia en el adaptador.

## Los seis requisitos del gate del líquido

| Requisito | Estado |
| --- | --- |
| 1. Extraer la integral y añadir validadores de los dos esquemas | Hecho. Los validadores viven en el adaptador, no en el helper, para que el ledger siga viendo solo el esquema sintético |
| 2. Fijar procedencia y rechazar remuestreo, extrapolación, fase cruzada, unidades, masa molar o referencia | Hecho por vinculación al contenido. Límite: no es una firma |
| 3. Conservar niveles de evidencia y errores declarados, con los ausentes | Hecho, y viajan con cada resultado |
| 4. Mención al NIST y no incorporar la tabla de 1994 | Hecho |
| 5. Etiquetado de una cadena con propiedad real y presupuesto sintético | **Limitado a propósito:** no hay cadena híbrida. El ledger y el propietario rechazan perfiles reales y conservan sus etiquetas `synthetic_*`. La composición queda para otra fase |
| 6. Cadena R2-1 y mutantes ejecutados en Godot | Hecho; ver cadena final |

## Aislamiento

- El helper rechaza un perfil real por su esquema sintético, sin cambios.
- El ledger (`propose_phase_sensible`) y el propietario sensible
  (`initialize`) aceptan el control sintético y rechazan el mismo material
  con un perfil real en el líquido, en el vapor o en ambos. La fixture lo
  ejecuta en Godot.
- Ledger, proveedor, caller de referencia y propietario sensible conservan
  sus cuatro hashes y no contienen ninguna referencia a esquemas reales.
- El adaptador rechaza perfiles sintéticos.

## Pruebas en Godot

Fixture `tests/fixtures/g3_heptane_real_cp.gd`, grupos R01-R10, **1417
comprobaciones**. Sus valores esperados se generan en Python a partir de
los auditores, con la reescritura en Python de la integral canónica; no
salen del adaptador. La prueba de pytest añade valores de mano tomados de
filas impresas de la fuente.

| Grupo | Qué comprueba |
| --- | --- |
| R01 | Contenido aprobado: nodos, soporte, etiquetas, masa molar, referencia, clases; cada nodo del líquido es Cp convertido y no Csat |
| R02 | Cp y entalpía en todos los nodos, puntos medios, referencia y puntos interiores; cero exacto en la referencia; signo por debajo y por encima |
| R03 | Intervalos parciales y de varios tramos: valor, antisimetría, aditividad, igualdad con la diferencia de evaluaciones y clases del intervalo |
| R04 | Sin extrapolación ni consultas no finitas, booleanas o de texto, en consulta y en intervalo |
| R05 | Límites que acompañan al resultado: intervalo integrado, clases recortadas, errores declarados, ausentes como `null`, sin incertidumbre total |
| R06 | Validación estricta: campos de más y de menos, etiquetas, tipos, nodos escalados, desplazados, quitados, añadidos o invertidos, Csat sin convertir, evidencia elevada, incertidumbre rellenada |
| R07 | Copias independientes, entrada intacta y constante aprobada sin alterar |
| R08 | Ámbito y las cuatro aprobaciones en `false`, en aceptaciones y rechazos |
| R09 | Mismo resultado, bit a bit, que el esquema sintético con los mismos nodos; la integral compartida rechaza desbordamiento y extrapolación |
| R10 | Aislamiento de helper, ledger y propietario sensible |

Contraste con valores independientes de ambas implementaciones:

- Gas, entre los nodos extremos: 348,416 kJ/kg en GDScript frente a
  34 912 / 100,20 = 348,423 de la columna de entalpía impresa.
- Líquido, de la referencia al punto de ebullición: 174,599 kJ/kg
  frente a 174,59 deducido de la columna de entalpía impresa.

## Mutaciones en Godot

`scripts/simulation/run_g3_heptane_real_cp_mutations.py`: 55 mutantes
predeclarados que ejecutan el GDScript real en un proyecto aislado. Tres
familias:

- **A, código del adaptador (26):** vinculación al contenido, tipos, campos
  de más y de menos, tolerancia, NaN, etiquetas, signo e integral del
  intervalo, límites solo del punto final, clases de evidencia, referencia
  fuera del intervalo, incertidumbre total, límites declarados, aliasing,
  las cuatro aprobaciones, ámbito y consultas no finitas.
- **D, contenido aprobado (20):** masa molar del motor, escala, referencia,
  fase, modelo, ruta, evidencia elevada, incertidumbre ausente rellenada,
  supuestos del gas dados por verificados, escala declarada exacta, Csat
  sin convertir, J/kJ, nodo quitado, etiqueta nativa y soporte ampliado.
- **H, integral compartida del helper (9):** signo, referencia, Cp del
  extremo, tramo parcial, tramos intermedios, recorte en vez de rechazo,
  calor latente, desbordamiento y esquema sintético sin comprobar.

Un mutante cuenta como muerto solo si la fixture termina y declara
comprobaciones fallidas; un error de sintaxis o de script es una corrida
inválida. Los controles offline de los gates anteriores no son mutantes del
motor; estos sí ejecutan GDScript.

## Cadena final sobre el código final

Tandas largas secuenciales, por `godot_monitored_launch.py` y
`run_reference_suite_monitored.py`; nunca Godot directo y ningún proceso
ajeno terminado. APPDATA, TEMP, TMP y basetemp nuevos bajo el temporal
externo `simufire_real_cp_impl_20261006_01`. Los cinco módulos de
`sim/fire` y las tres fixtures conservaron su SHA-256 desde antes de las
campañas hasta el final de la cadena. Sin procesos Godot residuales.

**Mutaciones, sobre el código final.** Once campañas, once controles en
verde, 228 mutantes muertos, ningún superviviente ni corrida inválida,
fuentes intactas:

| Campaña | Resultado |
| --- | --- |
| Adaptador real (nueva) | 55/55 |
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

Evidencia de la nueva: `runs/g3_heptane_real_cp_mutations_20261006_095806/`.

**Referencia (R2-1, exigida al tocar `sim/`): PASS.** 18/18 casos, salida
0, informe nuevo y errores de salud vacíos en todos; stderr vacío;
3201,8 s sumados; mínimo disponible antes de lanzar un caso 7,30 GiB; logs
sin `SCRIPT ERROR`, `Parse Error` ni violación de acceso. Comparador:
**346/346 required PASS, 78 gaps**. ALL GUARDRAILS PASS, R2-1 incluido.
Evidencia: `runs/reference_suite_monitored_20261006_101432/`.

Identidad de informes, tres nociones que no se mezclan:

- *Bytes.* Los **160 informes de caso** son idénticos byte a byte a la
  copia tomada antes de la tanda.
- *Fin de línea.* `reference_checks.json` sale de la suite con CRLF
  (SHA-256 `7338914d…219d174d`) y Git lo guarda en LF
  (`35fb5dda…5ae026d8`). Son dos secuencias de bytes con dos hashes.
- *Contenido.* En ese resumen cambia una sola línea de 19 269,
  `generated_at` (2026-10-05T19:17:53Z → 2026-10-06T09:08:01Z); la
  comparación estructural da esa única clave.

**Producto: PASS.** `scripts/check_product.py` monitorizado: **168/168**,
salida 0, stderr vacío.

**Global: PASS.** `python -m pytest tests -q -p no:cacheprovider` con
basetemp externo nuevo: **3946 passed, 43 skipped, 2 xfailed, 42
subtests**, salida 0, 623,30 s, stderr vacío; 7,14 GiB disponibles antes y
después. Respecto a la última global publicada (3727 / 41 / 2, en
`64a6803e`): 200 pruebas de los dos gates offline, 13 de esta fase y 8 de
las comprobaciones genéricas de fixtures sobre las dos fixtures nuevas.
Los dos saltos nuevos son de esas comprobaciones sobre la fixture de
identidad, que no tiene marcador PASS porque no emite veredicto propio: lo
da la comparación de su resumen.

**Offline.** Auditores del gas y del líquido reproducen sus resultados
guardados; campañas offline en Python 28/28 y 34/34, repetidas por el
cambio en el auditor del gas. Bloques generados al día. Estilo GDScript
PASS; enlaces de los documentos modificados PASS; `git diff --check`
limpio.

## Intentos que no cuentan

- **Primera campaña de mutaciones del adaptador**
  (`…_094733`): detenida en el primer mutante. Sin la vinculación al
  contenido, la fixture evaluaba un perfil sin lista de nodos y Godot daba
  error de script, que no es una muerte. Se corrigió la fixture para no
  evaluar esos perfiles y el runner para registrar todos los resultados.
- **Segunda campaña** (`…_094817`): 55/55, pero anterior a añadir la
  mención al NIST en la cabecera del adaptador. Sustituida por la final.
- **Referencia lanzada sin querer** (`…_095410`): el runner no tiene
  analizador de argumentos y `--help` lo arrancó, sin el aislamiento de
  entorno previsto. Se detuvo durante su segundo caso; no quedó ningún
  proceso y ningún informe cambió. No cuenta.
- **Primer intento de producto**: abortó antes de ejecutar ninguna prueba
  por un error de decodificación al leer la salida de un subproceso. Se
  repitió con UTF-8 heredado por los subprocesos; esa es la corrida válida.

## Límites de esta fase

- La evaluación es de una propiedad aislada. No predice ningún incendio.
- La vinculación al contenido no es una firma.
- Los valores esperados de la fixture y el adaptador parten de los mismos
  perfiles aprobados; lo que la fixture demuestra es que el GDScript los
  evalúa como la integral canónica, no que los perfiles sean correctos. Eso
  lo sostienen los dos gates offline y sus límites.
- La incertidumbre total no está cuantificada y la del gas por debajo de
  370 K no existe en la fuente.
- La composición con el ledger, y por tanto cualquier corrida con
  propiedades reales, queda para otra fase.

## Siguiente gate pendiente

Decisión del usuario, no iniciada: cómo componer estos perfiles reales con
el ledger y el propietario sensible, que hoy son sintéticos y los rechazan.
Aparte y sin relación de orden: B neto, y el gas por encima de 470 K.
CO/FED siguen OFF y NO-GO.
