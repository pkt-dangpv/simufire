# G3 — M4-A1: núcleo puro del reparto de oxígeno

Fecha: 2026-10-12. Base publicada: `993d98ec`. Rama shareable existente.

**Estado: cerrado técnicamente como núcleo puro; cadena final verde.**
Publicación autorizada tras revisar staged; no integración ni activación física.
[Evidencia actual y huellas](G3_O2_M4_PURE_PARTITION_EVIDENCE_2026-10-12.json).
Autorización: el usuario respondió «hazlo» al núcleo puro GDScript y sus pruebas.
No autoriza conectar una capa al fuego, variar caudales, activar producto ni
levantar los rechazos de M3. **CO/FED OFF/NO-GO.**

## 1. Cambio real y límites

Nuevo módulo
[`OxygenReferencePartition.gd`](../../sim/core/OxygenReferencePartition.gd),
sin `class_name`, exportaciones, interruptores ni instancias persistentes:

- Total `M` declarado como entrada y reparto `U`; `L=M-U` derivado.
- Construcción/validación, observables, remap, mezcla impuesta y presupuesto
  explícito. Candidatos inválidos devuelven rechazo sin estado ni recibo.
- Ninguna función modifica su entrada. Las salidas y los recibos son copias
  independientes; cambiar una salida no cambia el recibo ni la entrada.
- Capa ausente: inventario cero y observable `null`, no epsilon, ambiente ni
  concentración cero. No floors/clamps para ocultar sobregiros.
- No tasa de mezcla, penacho ni composición de gas. Las bases son kg de O₂
  a fracción molar de referencia uno, no masa física de gas caliente.

Es implementación del [contrato M4-A](G3_O2_M4_PARTITION_CONTRACT_2026-10-12.md),
no wiring: ningún subsistema de simulación lo carga. M3 continúa leyendo
el depósito de sala. Fuego, selección, transporte, EOS, editor y producto
mantienen sus archivos de la base publicada.

## 2. Verificación ejecutada

Fixture sintética
[`g3_o2_m4_partition.gd`](../../tests/fixtures/g3_o2_m4_partition.gd), sin motor
ni edificio: **160 304 comprobaciones PASS**. Incluye 10 000 remaps/mezclas
deterministas (no ticks del producto), con deriva del total exactamente cero.
18 salidas contrastadas con el oráculo Python independiente. Los balances
usan `1e-9 kg`, sin usar esa tolerancia para aceptar masa negativa.

La matriz cubre donantes en ambos sentidos, mezcla total/parcial/nula,
creación/colapso de capa, presupuestos, booleanos/texto/null, NaN/INF,
base total desbordada, capacidad, rechazo atómico y copias independientes.
La batería inicial Python/oráculo/runner tuvo **92 pruebas**; focal junto con
contratos M1/M2/M3: **226 passed**, sin exclusiones. La revisión del inventario
añadió una prueba: final **93 nuevas / 227 focales PASS** (§6). Las nuevas
están incluidas en las focales; no se suman como suites diferentes.

Dos campañas completas de **14/14 mutaciones válidas** detectadas donde se
predeclaró, 15 lanzamientos sanos en cada una, control 160 304 PASS y
restauración SHA-256 del único `.gd` mutado. La primera registraba el módulo
pero no la huella de la fixture. Se repitió completa tras añadir ese dato;
**la segunda es la evidencia usada para el cierre**, sin sumar las campañas.
Los dos controles independientes pasaron también; ninguno presentó errores
de script, nativos, timeout, cuadros o procesos residuales.

Defectos A01–A14: donante incorrecto al crecer/encoger, ambiente inventado al
colapsar, mezcla omitida/unidireccional, delta pareado ausente, presupuesto
de sala sin actualizar, negativo pequeño permitido, capacidad sin validar,
booleano como número, ausente como cero, alias estado/recibo, rango de mezcla
ignorado y techo ambiente que destruye inventario. No se cuenta ninguna
muerte por sintaxis o infraestructura.

## 3. Lo que se corrigió durante la preparación

- La prueba estática de etiquetas falló una vez (**1 failed / 78 passed**):
  no contemplaba la composición `label + " rejected"` de la fixture.
  Se comprueba esa composición, sin cambiar las aserciones de Godot ni sus
  etiquetas predeclaradas. Repetición: 79 passed; después, 226 focales PASS.
- Un extremo algebraico no estaba cubierto en M4-A: bases finitas cuya
  suma desborda. GDScript y Python lo rechazan. Los productos se calculan
  como inventario por razón acotada para evitar un desbordamiento intermedio
  evitable. No se altera ninguna ecuación de runtime del motor.
- Se revisaron antes de ejecutar los mutantes de colapso y alias para que
  introdujeran realmente el defecto declarado. No hubo supervivientes en
  las dos campañas ejecutadas. No inventar intentos de Godot que no ocurrieron.

## 4. Lanzamiento seguro

Se usa el monitor existente sin modificarlo: evita el wrapper console,
suprime los cuadros de error Windows, posee solo sus procesos por Job Object,
comprueba la memoria mínima de 6 GiB y verifica reposo al terminar.
Temporales APPDATA/TEMP/TMP y logs fuera del checkout; una tanda Godot a la vez.
Al empezar había 6,395 GiB y ningún Godot. No se pidió liberar más memoria.

Registro del control aceptado:
`%LOCALAPPDATA%/Temp/simufire_m4a1_control_bound_20261012/result.json`.
Mutaciones aceptadas:
`%LOCALAPPDATA%/Temp/simufire_m4a1_mutations_bound_20261012/results.json`.
Estos logs no se versionan; el resumen y las huellas se incorporarán al cierre.

## 5. Primera cadena larga — conservada como historial

R2-1 exige repetir referencia al añadir el módulo en `sim/core`, aunque no
tenga ningún llamador vivo. Se ejecuta por
[`run_g3_o2_m4_closure.py`](../../scripts/simulation/run_g3_o2_m4_closure.py):
prueba y mutaciones ligadas por hash; los cuatro `.gd` de M3 deben seguir
idénticos a su evidencia publicada. Se coteja corpus antes/después y se
rechaza cualquier cambio distinto de `reference_checks.json.generated_at`.

Orden, estrictamente secuencial:

1. **Referencia PASS**: 18/18 casos, 346/346 required, cero fallos y los
   mismos 78 gaps. 493/494 archivos brutos iguales; únicamente cambia
   `reference_checks.json.generated_at`. 3 202,25 s, monitor sano.
   Resultado externo en
   `%LOCALAPPDATA%/Temp/simufire_m4a1_reference_20261012/result.json`.
   Suite interna: `runs/reference_suite_monitored_20261012_141120/`.
2. **Producto 168/168 PASS**, 635,98 s, monitor sano.
3. **Guardarraíles ALL PASS**, R2-1 incluido, 3,15 s, monitor sano.
4. Global autoritativa `pytest tests -q -p no:cacheprovider`, con basetemp
   externo; **PASS: 4 829 passed, 70 skipped, 2 xfailed y 42 subtests passed**,
   exit 0, 920,07 s de pytest / 923,73 s del monitor. Memoria 6,716 GiB al
   empezar y 6,676 al terminar. Stderr vacío, sin timeout, cuadros, errores
   nativos, residuos ni terminaciones de limpieza. Resultado terminal en
   `%LOCALAPPDATA%/Temp/simufire_m4a1_global_20261012/result.json`.
5. Estilo GDScript, enlaces de los cinco Markdown y diff limpios. Ocho
   archivos del módulo/fixture/oráculo/arneses/tests idénticos por SHA-256 LF
   a los medidos; los cuatro `.gd` de M3 mantienen sus huellas publicadas.
   Los 79 UID y cuatro stashes conservan inventario y hashes/identificadores.
   Revisión staged y publicación solo de esta fase; no incorporar `runs/`,
   UID, originales FSRI, proyecto ni archivos ajenos.

No contar una suite como PASS mientras siga en curso. No cambiar código,
fixture ni oráculo medidos durante la cadena. Si la referencia se detiene
por memoria/salud, guardar la causa y reanudar desde el gate correcto; no
rebajar el umbral ni matar Godot ajenos. No publicar con R2-1 pendiente.

Incidencia de ejecución, no de física: el control de permisos rechazó el
primer intento de guardarraíles porque aún interpretaba producto como activo.
Se verificó su registro `passed`, exit 0, reposo y ausencia de residuos,
y se comprobó cero Python/Godot en el equipo. Después se autorizó el mismo
comando y pasó. Se hizo otra comprobación de reposo antes de global. No hubo
solapamiento, cambio de monitor ni intento de eludir el rechazo.

Los 70 skips y dos xfails se reportan como tales, no como cobertura física.
Las 92 pruebas nuevas focalizadas sí pasaron sin exclusiones. Los recuentos
globales son los observados, no una suma inferida del baseline y la focal.
La evidencia JSON se creó después de la global a partir de sus registros:
no añade implementación, pruebas ni valores físicos. No se repite referencia
por cambios exclusivamente documentales con los ocho archivos medidos intactos.

`reference_checks.json` cambia una línea: `generated_at`, de
`2026-10-11T23:17:54Z` a `2026-10-12T13:04:39Z`. Las huellas de fuentes
versionadas en la evidencia se normalizan a LF: no confundir el hash bruto
CRLF de un informe de Windows con el blob LF que guarda Git.

## 6. Retomada y siguiente gate

La primera cadena quedó verde, pero la revisión staged reprodujo un defecto
de reproducibilidad: el inventario histórico M2-T rechaza un archivo nuevo
cuando pasa de untracked a tracked (`tracked source set changed`). Se conserva
ese rechazo y el arnés histórico sin modificar. M4 tiene ahora su propio
snapshot LF del contenido actual, con el módulo explícito incluso antes de
versionarlo. Una prueba verifica igualdad antes/después de Git add, neutralidad
de CRLF/LF y rechazo de un cambio real de contenido.

Focal con el arreglo: **227 passed** (93 nuevas incluidas). Un primer intento
dio 226 passed / 1 error por no poder crear `tmp_path` en el sandbox; no lanzó
Godot. Se repitió con basetemp externo y pasó. Global final por monitor en
`%LOCALAPPDATA%/Temp/simufire_m4a1_global_repeat_20261012/result.json`.
Núcleo, fixture, oráculo, mutaciones y leyes del motor mantienen sus bytes;
no se repite referencia ni falsación por un cambio de arnés/test: se repitió global.
Resultado final: **4 830 passed, 70 skipped, 2 xfailed, 42 subtests**, exit 0,
918,85 s pytest / 922,63 s monitor. Memoria 6,698->6,591 GiB, stderr vacío,
sin timeouts, cuadros, errores nativos, residuos ni limpiezas forzadas.
La evidencia conserva ambas globales y las huellas de los dos arneses:
referencia/producto/guardarraíles se midieron con el anterior; el arnés final
incluye el nuevo inventario y está juzgado por la segunda global con Git add.
No se atribuye retroactivamente una ejecución a bytes de arnés que no tenía.

Main queda en `993d98ec`, sin cambios de esta entrega. Se conservan los 79
UID ajenos y los cuatro stashes; no entran en el commit. Sin datos FSRI nuevos,
`runs/`, proyecto, escenarios ni activaciones de física.

M4-A1 queda **GO técnico aislado**, nunca validación de concentración real.
Siguiente: **M4-B, diagnóstico del adaptador y de sus
donantes**, sin conectar el reparto al fuego ni autorizar exposición.
