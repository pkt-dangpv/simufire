# G3 — M3: implementación de la aceptación de combustión

## Autorización y estado

El 11 de octubre el usuario autoriza actualizar el contrato e implementar M3,
con el aumento de flashover dentro de la propuesta del paso siguiente, solo
en el modo experimental. Producto y CO/FED permanecen OFF/NO-GO.

Base: `0a15248a`, motor M2-T `28f74c4d`. Trabajo en el checkout aislado
`runs/g3_shareable`; `main` no recibe cambios sin la cadena de cierre.
Los 79 `.gd.uid` ajenos y los cuatro stashes deben conservarse.

**Cierre técnico completo (2026-10-12); publicación autorizada.** La reserva y la liquidación están
conectadas al fuego, al sumidero y al flashover en el motor real experimental.
La fixture ampliada pasa 477 comprobaciones. La falsación final de integración
y propietario pasa 14/14 en cada campaña; identidad OFF 9/9 y ON sin limitación
4/4 byte a byte. Las dos casas pasan sus 900 s completos; referencia, producto,
guardarraíles y global repetida están verdes. Se cierra la transacción M3 solo
en su alcance experimental; O2-3 de la ruta histórica no se declara corregido
y conserva su xfail. CO/FED y producto siguen OFF/NO-GO.
Las secciones de avance siguientes conservan las fotos históricas; el cierre
vigente y los intentos que no cuentan se recogen al final.

## Actualización del contrato

El [contrato previo](G3_O2_M3_CONTRACT_2026-10-11.md) se apoyaba en una
deuda diferida que el [transporte M2-T](G3_O2_TRANSPORT_M2T_2026-10-11.md)
ya no genera. Los controles con deuda serán explícitamente sintéticos,
no demostración de un fallo actual en una casa. La garantía pendiente es
que ninguna potencia aceptada tenga un débito de oxígeno insuficiente.

Se conserva la decisión después del filtro y sus guardas, antes de escribir
calor, combustible, depósito o productos. La reserva no modifica el inventario;
el sumidero liquida exactamente lo reservado, sin el tope histórico del 5 %.
Una misma fracción de aceptación se aplica a todas las cantidades extensivas.
Esto no corrige por sí solo el presupuesto energético histórico del combustible,
no calibra los rendimientos y no convierte el inventario de sala en zonal (M4).

El flashover no podrá multiplicar una potencia ya aceptada. Su evento y la
propuesta de ganancia se registrarán, y el salto de potencia se someterá a la
aceptación del paso siguiente. La ruta OFF conserva la secuencia histórica.
No incorporar química, oxidación de CO ni propiedad experimental del combustible
a esta transacción: las combinaciones no soportadas deben rechazarse de forma
explícita, no ignorarse. No ampliar a otros modos de combustión sin sus controles.

## Primera pieza: propietario de la reserva

Evidencia histórica de la primera pieza, anterior a los cambios de integración.
El JSON de reserva liga aquellos bytes por SHA-256; no liga automáticamente
el propietario actual. Su campaña se ha repetido sobre los bytes integrados;
la evidencia actual se recoge al final, sin reatribuir la histórica.

- `reserve_combustion`: valida propietario, selección, corrida, paso, cantidad
  y coeficiente; usa la disponibilidad canónica, y rechaza una segunda reserva.
- `consume_reserved_combustion`: exige la misma selección y el calor aceptado;
  liquida lo reservado por una única ruta contable. El débito histórico no
  puede saltarse la aceptación si esta extensión está armada.
- Las operaciones de intercambio y las llegadas protegen lo reservado antes
  de modificar inventarios o acumuladores. Se protegen también las obligaciones
  negativas explícitamente inyectadas para diagnóstico.
- El cierre y la apertura del paso siguiente rechazan una reserva sin liquidar;
  `discard` la elimina al terminar la corrida.
- El cálculo de dilución M2-V sigue siendo único, compartido por la comprobación
  previa y la operación que confirma; no se introduce una segunda ley de flujo.

Fixture juzgada: [reserva M3](../../tests/fixtures/g3_o2_m3_reservation.gd).
Lanzador: [monitor de reserva M3](../../scripts/simulation/run_g3_o2_m3_reservation.py).
Guardas estáticas complementarias:
[tests de contrato](../../tests/test_g3_m3_reservation_contract.py).

## Gate pendiente antes del cierre

Comprobación offline de esta primera pieza: **102 passed**, que incluye 20
guardas estáticas, 15 controles del arnés y los 67 contratos previos M3/M2-T. Enlaces
del informe sin roturas y `git diff --check` limpio. El intento de ejecutar la
fixture por el monitor se rechazó **antes de arrancar Godot**, con 5,84 GiB
disponibles frente al mínimo de 6 GiB. El runner terminó con código 1 por esa
guarda; no es un fallo nativo ni un resultado de la fixture.
La fixture corregida pasó con **94 comprobaciones, 0 fallos**, código 0,
sin timeout, cuadros, procesos residuales ni terminaciones de limpieza.
El monitor usó el ejecutable regular headless, evitó el wrapper de consola,
suprimió el UI de errores de Windows y fue propietario del único proceso.
Registro local: `simufire_m3_reservation_20261011_e0b30824ee39487482142462e4a6cf3f`
en el directorio temporal externo; inicio UTC 20:28:31, final 20:28:34.
Esto valida únicamente la reserva aislada, no su integración en el motor.

Un intento anterior sí arrancó Godot, pero no cuenta: el edificio sintético
de la fixture no implementaba `get_room`; produjo errores de script y el
monitor terminó el proceso al vencer 180 s. Sin cuadro nativo ni residuos.
Se añadió ese método y una guarda estática, y solo después se obtuvo el
PASS anterior. No confundir este error del arnés con un fallo de física ni
con una muerte válida de mutante.

Después se amplió la fixture para contrastar disponibilidad falsificada por
el llamador, inventario cambiado, llegada positiva pendiente, calor cero y
cambio del coeficiente. Campaña final: **126 comprobaciones PASS y 14/14
mutantes muertos en las aserciones predeclaradas**, sin supervivientes ni
errores de script, timeouts, cuadros, residuos o terminaciones de limpieza.
SHA-256 del propietario antes/después idéntico en cada restauración.
[Registro público acotado](G3_O2_M3_RESERVATION_ACCEPTANCE_2026-10-11.json)
y [arnés](../../scripts/simulation/run_g3_o2_m3_reservation_mutations.py).
Es falsación del propietario aislado, **no** de la integración pendiente.

Intentos adicionales que no cuentan: el primer clasificador del arnés
exigía un banner PASS que esta fixture no emite, y rechazó un control
saludable; se corrigió el clasificador y se fijaron sus rechazos offline.
En la primera campaña R09 quitó la guarda de reserva pendiente y la
fixture leyó el índice -1 de una lista vacía: error de script y timeout
monitorizado, sin cuadro nativo ni residuos; las fuentes se restauraron.
La aserción ahora comprueba la lista antes de leerla y R09 muere por
la aserción prevista en la repetición completa. No se cuentan los ocho
mutantes anteriores de ese intento como una segunda campaña aceptada.

Siguen pendientes referencia, producto y global de este cambio.

Comprobación final de esta pieza: 102 tests offline repetidos, estilo GDScript
PASS, enlaces de los tres documentos PASS y `git diff --check` limpio.
Memoria final 6,40 GiB, cero procesos Godot; se mantiene el mínimo de 6 GiB
y una sola tanda simultánea, sin pedir más memoria al usuario. Los 79 `.gd.uid`
ajenos coinciden por SHA-256 y los cuatro stashes siguen intactos.
`main` limpio e intacto; no hay commit ni push de M3.

Después del rechazo: cero procesos Godot; los 79 archivos ajenos coinciden
por SHA-256 con el checkpoint y los cuatro stashes conservan sus hashes y
descripciones. `main` continúa limpio en `0a15248a`.

1. Propietario aislado: 126 PASS y 14/14 mutantes válidos; no equivale a M3 integrado.
2. Integración escrita: propuesta, aceptación y confirmación del fuego/sumidero.
3. Flashover diferido, extinción, rechazo, reinicio y casos limitantes: 477 PASS.
4. Falsación con mutantes válidos y restauración exacta de fuentes.
5. Identidad OFF y controles ON donde nada limita contra la base M2-T.
6. Casas completas, referencia R2-1, guardarraíles, producto y global secuenciales.
7. Documentación de resultados reales, revisión del diff y publicación normal.

No ejecutar Godot directamente ni rebajar la guarda de memoria. No usar una
prueba estática o un oráculo Python como evidencia de integración del motor.

## Integración real en curso

Cambios funcionales en cuatro archivos GDScript: `CombustionSystem.gd`,
`RoomOxygenInventory.gd`, `OxygenExchangeSystem.gd` y `SimulationEngine.gd`.
La misma clave privada experimental activa M3; no hay interruptor de producto
nuevo. Se rechazan explícitamente fuego prescrito, propiedad experimental del
combustible, oxidación de CO, supresión activa y más de un fuego.

El fuego guarda propuesta de depósito, potencia post-filtro y humo en locales.
Tras sus guardas reserva oxígeno antes de escribir las cantidades aceptadas.
Se aplica una fracción común al calor, combustible, humo, especies, contadores
de carbono y potencia de los objetos explícitos. Los rendimientos y el techo
de carbono se evalúan sobre la propuesta, no se recalculan con la potencia
aceptada. La variación completa del depósito, incluido su decaimiento propuesto,
se escala con esa fracción: es el contrato técnico, no una calibración de pérdidas.

El sumidero liquida exactamente la reserva, sin volver a recortar al 5 %.
Una reserva sin liquidar detiene el paso antes del sistema térmico; no se inventa
una combustión alternativa. El flashover conserva el evento y propone la ganancia
para el tick siguiente: el propietario impide gastarla en el mismo tick y la borra
al reiniciar. La retirada tardía por combustible agotado pasa al inicio del tick
siguiente, de modo que no borra un calor ya aceptado. La ruta OFF conserva su orden.

[Fixture real](../../tests/fixtures/g3_o2_m3_integration.gd): 477 comprobaciones,
incluido motor completo durante 120 ticks, combustible final, reserva nula,
débito del inventario entero, mueble explícito, rechazo antes de calor y flashover.
La corrida aceptada del 11 de octubre, UTC 21:37:52–21:37:58, no tuvo errores
de script, timeout, cuadros, residuos ni terminaciones de limpieza. Es una
comprobación técnica de integración, no validación de incendios, CO o FED.

Intentos de integración que no cuentan: un alias `Engine` chocaba con el tipo
nativo y dio error de parseo; se cambió y se fijó una guarda estática. Una prueba
suponía que un remanente de combustible con fracción de curva de 1e-9 se agotaría
en un tick: medido, consumía solo 3,4467e-11 MJ. Se corrigió el montaje sintético
para probar realmente el último tick, sin cambiar la ley de combustible. En la
primera falsación integrada, I09 retiraba el fuego y la fixture leía `room.fire`
nulo: error de script, no muerte válida. Ahora conserva el recurso original y
repite la campaña completa. Ninguno de estos intentos mostró fallo nativo.

Los tests de ruta del contrato inicial quedan ligados al commit `cefae4ec`
que midió su diagnóstico, no al código M3 que corrige esa ruta. Se conservan
las aserciones y sus fuentes históricas; la integración actual tiene sus
propias guardas estructurales y fixture juzgada, no se exime de comprobación.

## Verificación del 12 de octubre: resultados aceptados, cierre pendiente

[Evidencia técnica actual](G3_O2_M3_CURRENT_TECHNICAL_EVIDENCE_2026-10-11.json):
fuentes y arneses juzgados por SHA-256, distintos del registro histórico inicial.
El control integrado hace 477 comprobaciones; 14/14 mutantes fallan en la
aserción predeclarada. Propietario actual: 126 checks y 14/14 mutantes válidos.
Las 30 ejecuciones de las dos campañas tienen salud limpia y restauración exacta.

Cuatro controles ON sin limitación, a dt 2/1/0,5/0,25 s y durante 30 s:
675 checks en cada versión, cuatro trazas byte a byte iguales a M2-T.
No sustituyen un incendio completo ni validan comportamiento físico.
Identidad OFF: nueve de nueve casos iguales, siete archivos por caso y ausencia
del ledger experimental; nueve monitores saludables. Fuentes sin modificar.
Regresión viva M2-T sobre M3: 3 650 checks PASS por el monitor.
Focal offline final: 319 passed, una prueba Godot deliberadamente excluida
para no solapar tandas. Incluye controles del verificador, contratos vigentes
y evidencia histórica. Estilo GDScript PASS y diff sin errores.

Dos arreglos de comprobación, no de motor: la tanda OFF acabó 9/9 pero su wrapper
buscaba un log compartido que el lanzador histórico no escribe. Se conservó el
fallo original y se revisaron identidad y nueve monitores reales sin relanzar
Godot, exigiendo que el registro original ligase los mismos bytes del motor.
El analizador de casas conservaba el antiguo tope del 5 %: ahora tiene política
explícita, histórica por defecto y débito exacto solo al pedir M3. Una prueba con
déficit 0,026 kg distingue ambas; el oráculo de reserva/calor se juzga por separado.
Una primera prueba sintética de salud omitía dos campos del monitor y falló;
se completó la fixture, sin rebajar los rechazos. Repetición: 71 passed.

Contratos históricos actualizados con procedencia: las fuentes del diagnóstico
M3 siguen `cefae4ec`, la congelación de Combustion en M2 sigue `461fa9c0`,
la de M2-V sigue `cefae4ec`, y la evidencia M2-T y la protección previa Test016
siguen `28f74c4d`. Sus hashes y aserciones antiguas no se mueven. El motor de hoy
tiene fixture M3 propia, falsación y límites de cambio por función, no una exención.
En la focal anterior fallaron 17 pines de forma o procedencia, corregidos sin
eliminar pruebas. La comparación de la rama legacy del sumidero sigue exacta.

Pendientes: referencia completa R2-1, producto, guardarraíles y global.
No hay commit ni push parcial de M3; producto y CO/FED continúan OFF/NO-GO.

La primera regresión de venteo dejó W08 vivo: M2-T ya no crea la cola histórica
que eliminaba ese mutante. No fue un PASS ni un defecto del transporte inmediato.
Se conserva la fixture histórica y se añade una derivada M3 con tránsito
explícitamente sintético: inventario más cola, dilución y llegada única.
La repetición con ese control pasó control y W01, pero se paró antes de W02
por 5,98 GiB frente a la guarda de 6. Fuentes restauradas por SHA-256, sin
Godot residual; no cuenta como campaña completa. Un reintento único empieza
con 6,24 GiB y sin otras pruebas concurrentes. No pedir más RAM al usuario.

Ese reintento se detuvo al clasificar W02: sus 22 fallos se resumían en 20
mensajes, porque la fixture histórica conserva como máximo ocho por grupo.
No se contó como una muerte válida ni como un fallo del motor. El clasificador
de esa fixture exige ahora que la suma completa y el número retenido por grupo
coincidan exactamente; nueve pruebas offline fijan también los rechazos nativos,
de script y de formato. El clasificador M3 original y sus bytes falsados no cambian.
La fixture derivada suprime gráficas después del reset (la padre lo hacía antes
y el reset anulaba esa supresión); evita procesos auxiliares sin cambiar física.

Repetición final aceptada: 138 checks PASS, 16/16 mutantes válidos donde se
declaró, 17 monitores saludables y fuentes restauradas byte a byte. W08 cae
por el tránsito sintético de la API diagnóstica; no por crear deuda en M2-T.
Registro y resumen por aserción añadidos a la evidencia técnica actual.

Las dos casas intactas pasan: `o2_closed` y `o2_reopen_300`, 10 800 pasos
y 900 s cada una, fuentes iguales a las de falsación e identidad. Los balances
de traza por habitación y edificio y el calor respaldado en cada tick pasan
a 1e-9 kg. C1/C2 pasan sus criterios históricos sobre CSV redondeado: sus
residuos de unos 3–5e-9 kg no se presentan como inferiores a 1e-9.
No hay deuda, enriquecimiento ni clip
tardío. Los monitores de ambas están limpios. La evidencia actual recoge las
trazas por SHA-256 y sus cifras, sin convertir CO emitido en una validación.

Las casas tienen cero pasos con fracción menor que uno: ejercitan la ruta real
incluyendo flashover/extinción, no la limitación por reserva. Esa limitación,
el débito del inventario entero y el rechazo están juzgados en la fixture
sintética integrada. Calor/debito medidos: cerrada 87,462082 MJ / 6,647118 kg;
reabierta 125,816872 MJ / 9,562082 kg, con residuo por tick menor de 5,6e-16 kg.
No se usa esto como cierre del balance combustible/calor ni de CO/FED.

## Cadena larga del 12 de octubre

Referencia aceptada: 18 casos, 346/346 required, 0 fallos y los mismos 78 gaps;
corpus bruto 493/494 idéntico, solo `reference_checks.json.generated_at`.
Monitor limpio, 3 263,55 s. Producto 168/168, 646,48 s y salud limpia.
Guardarraíles ALL PASS, R2-1 incluido. Ningún byte del motor cambió.

Primera global: 9 failed, 4 725 passed, 68 skipped, 2 xfailed y 42 subtests,
937,56 s. Sin timeout, cuadro, fallo nativo, proceso residual ni limpieza forzada.
No se presenta como verde. Ocho fallos procedían del diseño Test016 de octubre 8:
su auditor vivo rechaza correctamente la forma M3, y ese rechazo ocultaba los
mutantes de otras anclas. La reproducción histórica ahora lee el commit declarado
`60754428`; ni auditor ni registros históricos se modifican. Una prueba nueva
exige que el auditor vivo siga rechazando aquel diseño sobre M3: no hay GO heredado.
La fixture viva del banco se había ejecutado en esa global sin fallo.

El noveno era F3.1: buscaba `room.retained_unburned_MJ = minf`, que ahora es
`proposed_pool_MJ = minf`. Se fija la garantía real: las cinco fuentes se anulan
antes de calcular la propuesta, y la ruta legacy la confirma como antes.
Reparaciones solo en tests: focal 48 passed. Hay que repetir global completa;
no hace falta repetir referencia ni falsación de un motor que conserva sus bytes.

## Cierre final del 12 de octubre

Global autoritativa repetida, monitorizada y con temporales/basetemp externos:
**4 735 passed, 68 skipped, 2 xfailed, 42 subtests passed**, exit 0,
893,31 s de pytest (897,93 s del monitor). Memoria 6,754 GiB al inicio y
6,679 al terminar. Sin timeout, error nativo, cuadros, procesos residuales
ni terminaciones de limpieza. Los skips y xfails no equivalen a cobertura física.
La primera global fallida y la focal de 48 quedan registradas arriba; no se ocultan.

Referencia: 346/346, 78 gaps, 493/494 archivos brutos idénticos, solo
`generated_at`. Producto: 168/168. Guardarraíles ALL PASS, R2-1 incluido.
Los hashes confirman que la global repetida usa los mismos cuatro `.gd`
y que el corpus no cambió después de la referencia. La extensión del reporte
del propietario es aditiva sobre v4; su modo y las reservas se declaran,
sin convertir la API diagnóstica histórica en transporte retardado de producto.

La fase queda cerrada técnicamente y autorizada para commit/integración/push;
ninguna ley se activa por defecto en escenarios distribuidos. Siguen fuera
del alcance materiales, balance físico combustible/calor, producción real
de especies, masas/composición zonal, M4 y CO/FED. Dos casas no ejercitan
la fracción limitada: esa cobertura sigue siendo sintética y explícita.
