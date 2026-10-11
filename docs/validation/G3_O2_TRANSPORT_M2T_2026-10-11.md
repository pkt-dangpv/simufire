# G3 — M2-T: gate del transporte de oxígeno

**Estado:** opción D implementada y cierre técnico completo; publicación autorizada.
**Base:** `920affb7`. **CO/FED: OFF/NO-GO.**

## Autorización y avance posteriores al gate inicial

El usuario respondió «sí, lo autorizo todo» a la propuesta de evaluar
el intercambio inmediato y conservativo de O₂ experimental. Se acota a
esa propuesta: **no autoriza M3/M4, CO/FED ni activar el producto**.
Se mantienen la autoridad de masa gaseosa/EOS, el caudal general,
`CombustionSystem.gd`, el sumidero y la dilución de M2-V.

Implementación en `RoomOxygenInventory.gd` y `OxygenExchangeSystem.gd`:

- `exchange_reference_gas_between_rooms` toma el mismo gas de referencia
  en ambos sentidos y calcula ambos paquetes desde los inventarios previos.
  Valida los dos estados antes de confirmar cualquiera; rechaza cantidades
  no finitas/negativas y `q > min(Ca,Cb)` sin cambiar salas ni acumuladores.
- Las rutas activa y de fondo llaman solo esa operación. No se despacha
  deuda ni crédito futuro de O₂. Los acumuladores anotan los dos extremos
  inmediatamente. El interruptor existente permanece OFF, sin exportar.
- El informe v4 declara la aproximación y que las otras especies mantienen
  sus retardos. No es transporte conjunto de masa gaseosa.
- **API histórica conservada para diagnóstico:** `exchange_between_rooms`
  sigue permitiendo inyectar los estados de deuda de las fixtures M1/M3;
  no tiene ningún llamador en subsistemas de simulación. La operación viva
  rechaza mezclar su contrato con una cola histórica inyectada. No afirmar
  que se ha eliminado toda posibilidad de deuda artificial del propietario.

Primera ejecución con Godot, con 6,029 GiB libres antes del lanzamiento:
**3 650 checks, cinco grupos, cero fallos**, exit 0. Monitor con wrapper
console omitido, UI de error suprimida, `timed_out=false`, `faults=[]`,
`error_dialogs=[]`, `cleanup_terminated_pids=[]`, sin procesos residuales y
`process_quiescent=true`. No hubo que parar Godot ni se tocaron procesos
ajenos. Este control no valida las casas completas ni materiales reales.

Regresiones offline posteriores: **199 passed**. La primera pasada dio
183 passed y dos fallos de huellas M2-V que aún vinculaban su medición
histórica al motor actual. Se actualizan esas dos pruebas para verificar
el commit publicado `cefae4ec`, sin editar su evidencia. Pruebas nuevas
fijan que la dilución, sumidero, fuego, otras especies, EOS y activación
siguen sin cambios. No se borran las comprobaciones históricas.

Tras liberar memoria (7,697 GiB al retomar), completado:

- **12/12 mutantes válidos muertos donde se declaró**, cero supervivientes
  ni bajas por sintaxis, y restauración SHA-256 exacta de ambos `.gd`.
- Misma fixture sobre `920affb7`: **712 comprobaciones fallan**, sin error
  de script; fuentes actuales restauradas byte a byte. Implementación
  actual: **3 650 comprobaciones, cero fallos**.
- Casas `o2_closed` y `o2_reopen_300`: **10 800 pasos / 900 s cada una**,
  sin obligaciones ni intercambio diferido de O₂ y sin salas por encima
  del oxígeno exterior. Residuo global máximo por paso: `9,6121e-15 kg`
  y `1,0363e-14 kg`, respectivamente. Se repiten con temporales externos
  antes de la cadena final; no se valida CO/FED ni la energía del fuego.
- Fixtures anteriores: **M1 281, M2 102, M2-V 126**, todas PASS.
  Las expectativas de tránsito natural se sustituyen por ausencia de
  deuda en el modo nuevo; las pruebas de conservación no se relajan.
  La cola histórica se inyecta explícitamente donde se prueba su ciclo
  de vida. Tres primeras tandas fallaron por esas expectativas antiguas,
  no por errores nativos ni de script; se conserva ese resultado.
- **Identidad OFF: 9/9 casos byte a byte**, siete ficheros por caso,
  contra el corpus `g3_balance_identity_off_ledgeroff_20261010_192801`.
- Oráculo, aislamiento del motor y arnés de cierre: **67 passed**, sin
  lanzar Godot. No sumar este recuento a los históricos como si fueran
  pruebas distintas.

## Cadena de cierre del código implementado

Referencia regenerada por el monitor: **18/18 casos, 346/346 required PASS,
0 fallos y los mismos 78 gaps**. R2-1 y todos los guardarraíles PASS.
Producto: **168/168 PASS**, exit 0, 649,96 s, stderr vacío y salud limpia.
Global autoritativa repetida: **4 635 passed, 60 skipped, 2 xfailed,
42 subtests passed**, exit 0, 902,02 s (906,25 s con el monitor).
Arrancó con 7,632 GiB y terminó con 7,409 GiB; stderr vacío, sin timeouts,
cuadros, fallos nativos, procesos residuales ni terminaciones de limpieza.
No se tocaron procesos ajenos. Los skips/xfails no se presentan como PASS.
Se autoriza commit, fast-forward de main y push normal de esta fase,
sin activar producto ni empezar M3/M4.

Corpus: **494 archivos cotejados mediante hashes normalizados a LF;
493 idénticos y solo `generated_at` cambia en `reference_checks.json`**,
de `2026-10-10T19:00:18Z` a `2026-10-11T16:42:44Z`. No se guardó un
manifiesto bruto previo a esa regeneración: no afirmar identidad byte a
byte de todo el corpus. La identidad OFF 9/9 de arriba sí compara bytes.

La referencia se ejecutó completa una vez, no dos. Después de terminar,
la captura del proceso Python exterior falló al decodificar una comilla
UTF-8 como cp1252 y no guardó su salud exterior. Se conserva el fallo;
se aceptan las salidas frescas y los controles estrictos de salud de los
18 monitores internos, comprobando que no cambió su runner publicado ni
ninguna fuente o entrada medida. No se inventa un registro exterior.
Un segundo intento falló antes de Godot: `tasklist` usa OEM, no UTF-8.
El monitor declara ahora OEM para ese inventario y UTF-8 para sus dos
capturas de procesos. No cambia propiedad, limpieza, umbrales ni gravedad;
una prueba AST exige igualdad con la base salvo esos tres decodificadores.
Monitor/arnés: **95 passed** antes de añadir esa prueba AST, sin Godot
(simulaciones y procesos Python inocuos); no sumar recuentos solapados.
Los 12 mutantes de física se reutilizan con fuentes y fixture idénticas;
fueron medidos antes del ajuste de decodificación, no se repitieron después.

Primera global: **3 failed, 4 626 passed, 60 skipped, 2 xfailed,
42 subtests passed**, 920,20 s. Salud limpia, sin fallos nativos ni timeouts.
Los tres fallos son contratos estáticos: el test del APPDATA por defecto
heredaba el override externo; dos búsquedas de consumidores confundían
cuatro inventarios JSON de hashes con dependencias nuevas. Se aisla el
test del valor por defecto y se autorizan exactamente esos cuatro
registros, comprobando su hash y manteniendo el rechazo de registros
arbitrarios, versionados o no. **78 pruebas focalizadas PASS**.
La primera focal tras ese cambio tuvo cuatro `NameError`: un assert
quedó bajo la función nueva; se devolvió a su función original y se repitió.
No cambian primitivas, leyes, tolerancias ni datos de referencia.
La global se repitió completa; referencia y producto se conservan porque
su implementación y entradas no cambiaron. El intento fallido se conserva
en el registro final y no cuenta como cierre.

Estilo, enlaces de los cuatro documentos modificados y `git diff --check`:
PASS. Los 79 `.gd.uid` ajenos y los cuatro stashes del checkpoint quedan
verificados por SHA-256/lista, intactos y fuera del commit; tampoco se
incluye `runs/`. Se publica solo el alcance M2-T y sus pruebas/evidencias.

[Aceptación y casas](G3_O2_TRANSPORT_M2T_ACCEPTANCE_2026-10-11.json) ·
[regresiones e identidad OFF](G3_O2_TRANSPORT_M2T_REGRESSIONS_2026-10-11.json) ·
[cadena de cierre](G3_O2_TRANSPORT_M2T_CLOSURE_2026-10-11.json).

**Siguiente gate, no iniciado:** revisar el contrato M3 contra este
transporte vivo, que ya no crea deuda diferida. La deuda sintética
histórica no demuestra un defecto actual. Sigue pendiente que calor,
combustible y productos respondan a una misma aceptación del paso, y la
autoridad zonal M4. CO/FED siguen OFF/NO-GO; no hay calibración experimental
de esta mezcla ni transporte acoplado de gas y todas sus especies.

Retomada: usar el monitor con al menos 6 GiB (preferible 7–8), temporales
externos y tandas secuenciales. Lanzador vivo:
[`run_g3_o2_transport.py`](../../scripts/simulation/run_g3_o2_transport.py).
Fixture: [`g3_o2_transport_acceptance.gd`](../../tests/fixtures/g3_o2_transport_acceptance.gd).
Mutaciones: [`run_g3_o2_transport_mutations.py`](../../scripts/simulation/run_g3_o2_transport_mutations.py).
El registro inicial offline permanece inmutable y describe la base, no
el motor corregido. El lanzador `run_g3_o2_transport_gate.py --offline-only`
rechazará correctamente el motor nuevo por no ser esa base.

## Historial del gate previo a la autorización (no es el estado actual)

El encargo inicial autorizaba corregir el crédito con deuda, pero exigía
detenerse antes de cambiar el retardo o la autoridad de masa gaseosa/EOS.
El análisis siguiente corresponde a ese alcance, ya ampliado explícitamente.

## Predicciones anteriores a los controles dinámicos

1. La operación actual cierra `ΣM + T` aunque una sala conserva oxígeno
   que debe entregar. La selección lee `M`, no el disponible `M − deuda`.
2. Con concentraciones iguales, el neto histórico es cero.
3. Cambiar «caliente/fría» por «rica/pobre» no basta: el enriquecimiento
   de la casa depende de operaciones pendientes y cambios de composición.
4. La deuda inyectada del control de M3 volverá a rechazar al vencer.
   Es una operación declarada por la fixture, no un evento natural de puerta.
5. La casa reabierta conservará O₂ y repetirá el enriquecimiento; no se
   modifica ninguna ley para esta reproducción.

## Compatibilidad de las alternativas

Oráculo exacto, independiente del motor:
[`g3_m2t_transport_contract.py`](../../scripts/simulation/g3_m2t_transport_contract.py).
Sus cantidades son normalizadas, **no kg medidos ni validación del motor**.

Sea `C` el contenido de referencia fijo de una sala, `x` su fracción
molar y `M = κ C x`, con `κ = M_O₂ / M_aire`. Un intercambio inmediato
simétrico `q ≤ min(Ca,Cb)` da:

```text
Δ = κ q (xb − xa)
Ma' = Ma + Δ; Mb' = Mb − Δ
xa' = (1 − q/Ca) xa + (q/Ca) xb
xb' = (1 − q/Cb) xb + (q/Cb) xa
```

Conserva O₂ y es una mezcla convexa sin techo. Es un control algebraico,
**no una propuesta autorizada de eliminar el retardo**.

### A. Dos paquetes positivos, debitados al despachar

Descontar `κqx` de ambas salas y acreditar al llegar elimina la deuda,
pero no mantiene su concentración si el denominador sigue siendo `C`.
Incluso con `xa = xb = 0,209` y `q = 0,04 C`, ambas pasan a `0,20064`
antes de recibir nada. Conserva O₂ y rompe el equilibrio.

La concentración física de una extracción homogénea seguiría siendo
`M' / [κ(C − q)] = x`. Requiere representar también el contenido de
gas portador retirado. **No basta una cola de O₂ positivo.**

Además, otra operación exterior puede ocupar el hueco antes de llegar el
paquete. El oráculo combina la dilución legal de M2-V con una llegada y
produce enriquecimiento. La dilución grande del contraejemplo comprueba
el contrato de la API; **no representa el caudal de una ventana real**.

### B. Retardar solo el exceso neto, retirándolo de la sala rica

Mantiene el equilibrio de salas iguales y elimina la deuda con signo.
Sin embargo, una llegada positiva aún puede enriquecer al receptor si
otra operación ocupa su capacidad antes de llegar. Proteger esa
capacidad afecta también al exterior y a otros intercambios: no se debe
ocultar con un clamp ni corregir el venteo de M2-V fuera de alcance.

### C. Intercambio emparejado al vencer, contenido fijado al despachar

Mantiene los denominadores mientras espera, pero exige proteger el
oxígeno saliente frente al consumo. El sumidero actual no limita por una
reserva: ese compromiso se diseñó para M3 y no está implementado.
Recalcular la composición al vencer sería otra semántica, un evento de
mezcla diferido, no entregar el contenido despachado.

### D. Intercambio inmediato, simétrico y conservativo

Compatible algebraicamente con la base fija y sin necesidad de deuda.
Pero cambia el retardo de O₂ de la ruta activa. El encargo exige
justificarlo y pedir autorización antes de hacerlo.

## Decisión inicial de alcance, antes de la ampliación autorizada

**NO-GO de implementación bajo todas las restricciones actuales.**
No se afirma que ningún modelo retardado sea posible: se demuestra que
las sustituciones directas anteriores no satisfacen el contrato entero.
Un modelo con gas portador, una capacidad reservada acoplada al exterior
o una semántica distinta del retardo exige una decisión adicional.

Recomendación mínima: evaluar y autorizar explícitamente la retirada del
retardo **solo del intercambio de O₂** en el modo experimental y mantener
el intercambio emparejado. Los retardos de humo y otras especies no se
tocan en esa autorización. La sincronía física entre especies seguiría
siendo un límite declarado; no equivale a validación experimental.

Alternativa de mayor alcance: transportar gas de referencia y O₂ juntos,
derivar la concentración del contenido efectivamente presente y revisar
todos sus consumidores. No se debe confundir ese portador de referencia
con la masa termodinámica real del gas caliente.

## Verificación

Ejecutado en esta sesión, sin iniciar Godot:

- Oráculo y seguridad del monitor: **112 passed**. Las pruebas del monitor
  usan simulaciones y procesos Python inocuos; no son corridas del motor.
- Oráculo y regresión del contrato M3: **67 passed** (35 nuevas y 32 de M3).
  Comparte las 35 pruebas del oráculo con la tanda anterior; no sumar los
  recuentos como pruebas distintas.
- Guardarraíles: **ALL PASS**, R2-1 incluido, 346 required y 78 gaps.
  No se ha regenerado la referencia: `sim/` permanece intacto.
- Última repetición offline: **67 passed**; sintaxis Python, estilo
  GDScript, enlaces de los cuatro documentos y `git diff --check`: PASS.
  El verificador de estilo no sustituye la ejecución de la fixture nueva.
- Reanálisis de las trazas publicadas de las dos casas: 10 800 pasos y
  900 s cada una. Se cotejaron 1 011 fuentes con `920affb7`, normalizando
  únicamente los finales de línea. No son nuevas corridas de Godot.

En `o2_closed` el residuo máximo de la cuenta reportada `ΣM + T` es
`9,6121e-15 kg`; en `o2_reopen_300`, `1,8137e-14 kg`. El Pasillo de esta
última alcanza `x = 0,2201602092` durante 265 pasos por encima de 0,209
(unos 22,08 s), mientras la fracción efectiva que incluye el tránsito
no supera 0,209. Cerrar la cuenta global **no** demuestra que la
composición local ni el oxígeno disponible para arder sean correctos.
Este reanálisis usa las operaciones reportadas para comprobar la cuenta;
no es una medición independiente de todos los flujos físicos.

[Registro offline](G3_O2_TRANSPORT_M2T_OFFLINE_2026-10-11.json), con huellas
de las fuentes y trazas, contraejemplos exactos y la deuda publicada de M3.
`fresh_godot_launches = 0`: no inventa salud de procesos ni reproducciones.

Preparados, pero **sin ejecutar ni dar por validados**:

- [Fixture dinámica](../../tests/fixtures/g3_o2_transport_gate.gd) con
  operaciones directas del propietario y la deuda inyectada de M3.
- [Lanzador monitorizado](../../scripts/simulation/run_g3_o2_transport_gate.py)
  para repetir los controles y las casas de una en una.

Memoria al parar: **5,596 GiB**, por debajo del mínimo de 6 GiB.
No se inició Godot; no hubo nuevos cuadros ni procesos Godot residuales.
La suite global, producto y controles dinámicos siguen pendientes.
No hay commit ni push: el trabajo nuevo se conserva para retomarlo.
`main` sigue limpio en `920affb7`; los cambios están en el worktree
shareable. Los 79 archivos sin seguimiento del checkpoint inicial y
los cuatro stashes permanecen idénticos; ninguna fuente del motor cambia.

Incidencia del arnés offline: el primer intento buscó la clave `cases`
en el registro M3, que usa `controls`; falló antes de emitir un informe.
Se corrigió el lector y el reanálisis terminó correctamente. No se
interpreta aquel fallo como evidencia física.

## Retomada inicial, sustituida por la autorización de arriba

No implementar M3/M4 ni ninguna alternativa de transporte antes de que
el usuario elija el alcance. Si autoriza la opción D, limitarla al O₂
experimental y declarar que conserva los retardos de otras especies:
no afirmar que resuelve el transporte conjunto de gases.

Tras liberar memoria, verificar primero el lanzador y la fixture por el
monitor; después ejecutar secuencialmente las reproducciones y la cadena
aplicable. Una corrección en `sim/` exige además identidad OFF, referencia
completa, mutaciones y pruebas del comportamiento nuevo, no solo este
oráculo. Los defectos de energía del combustible, M3, M4 y CO/FED
permanecen pendientes. El gate no está cerrado ni publicado.
