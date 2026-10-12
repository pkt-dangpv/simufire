# G3 — M4-A: contrato del reparto conservativo de oxígeno

Fecha: 2026-10-12. Base publicada: `993d98ec` (M3).

Actualización posterior: [M4-A1, núcleo puro](G3_O2_M4_PURE_PARTITION_2026-10-12.md)
cerrado técnicamente con autorización «hazlo», sin wiring; cadena completa
verde. El estado y las cifras siguientes conservan la entrega del contrato
offline anterior. No se convierten en validación física del módulo nuevo.

**Estado: diseño y oráculo offline; M4 no está implementado en el motor.**
Sin Godot, cambios en `sim/`, interruptores nuevos ni activación de producto.
**CO/FED OFF/NO-GO.** El trabajo continúa el reparto `M_alta` previsto en
[la autoridad de oxígeno, M4](G3_O2_AUTHORITY_2026-10-09.md), no el antiguo
guard ILV también llamado M4 en los informes de junio.

## 1. Decisión y alcance

- **GO al contrato algebraico y a un futuro núcleo puro GDScript aislado.**
  Un total de sala y un reparto subordinado, con operaciones validadas antes
  de escribir. Los parámetros de mezcla son entradas impuestas, no calibración.
- **NO-GO a conectar el reparto al fuego**, al transporte o a la exposición:
  faltan el adaptador de rutas, las bases zonales y la selección/reserva zonal.
- No levantar el rechazo de varios fuegos, red de presión, banco Test016,
  oxidación de CO, supresión ni propiedad explícita de combustible de M3.
  Cada combinación necesita su propio contrato. No activar estos modos por
  el mero hecho de cerrar el reparto matemático.

El «continúa» del usuario se aplica al siguiente trabajo anunciado:
contrato y pruebas de M4. No autoriza aquí una ley física nueva ni promoción
de producto. Se trabaja en la rama shareable existente; main queda intacto.

## 2. Qué muestra el código actual

Inspección de la base `993d98ec`, no repetición de las mediciones antiguas:

| Ruta | Situación actual | Lo que debe resolver M4 |
| --- | --- | --- |
| `RoomOxygenInventory._select_for_step` | La selección usa kg y fracción del recinto entero | No presentarla como disponibilidad de una capa |
| `OxygenExchangeSystem.step`, sin fuego | Relaja lower y upper por separado, a tasas distintas | Transferencia pareada dentro del total, no dos fuentes |
| Misma función, lower menor del 15 % | Reescribe trazadores a la sala o a un máximo | Colapso explícito conservativo; no usar 15 % como verdad física |
| Misma función, con fuego | Mantiene consumo/arrastre auxiliar, floors y clamps zonales | Sustituir las escrituras; no sumar otro débito al de M3 |
| `ThermalSystem._seed_upper_layer_as_one_packet` (red ON) | Mezcla el número upper con masas de gas | No tomar esta escritura como kg canónicos del reparto; la red sigue rechazada por M3 |
| `LayerInterfaceModel.get_flow_interface_height_m` | Usa la interfaz térmica, no la capa óptica | Una semántica común para geometría; no copiar la altura visible |
| M2-T | O₂ inmediato y simétrico sobre contenido de referencia de sala | El total no especifica qué capa dona o recibe |
| M2-V | Dilución equivalente de sala con entrada/salida | Su delta neto tampoco determina el reparto |

Los fallos H08/H09 son evidencia histórica de la
[autoridad de oxígeno](G3_O2_AUTHORITY_2026-10-09.md), no mediciones nuevas.
[E1](E1_O2_BASE_DE_MASA_2026-09-25.md) sigue impidiendo convertir las masas
de gas heredadas en una autoridad física zonal sin cerrar sus prerrequisitos.
M2-T ya corrigió el crédito/deuda de la ruta viva: no usar ese defecto antiguo
como argumento nuevo para M4. Su API de tránsito firmado sigue diagnóstica.

## 3. Estado, unidades y bases: no confundir reparto con composición real

El propietario de sala conserva `M`, kg de O₂. Solo se añade `U`, kg de O₂
en la zona alta; `L = M − U` es derivado, nunca una segunda autoridad.

Para el núcleo algebraico, las bases impuestas `B_u` y `B_l` expresan kg
de O₂ que corresponderían a una fracción molar de referencia igual a uno.
`B = B_u + B_l > 0`; las fracciones derivadas son `x_u = U/B_u`,
`x_l = L/B_l`, `x_room = M/B`. Se exige `0 ≤ U ≤ B_u`, `0 ≤ L ≤ B_l`.
Una zona de base cero exige inventario cero y concentración **ausente**,
no cero, no ambiente y no división por un epsilon inventado.

Para el futuro adaptador, la candidata coherente con M1 es
`B = n_ref · M_O2`, usando sus constantes ya declaradas. Una partición
geométrica `B_u = B · (H − z)/H` sería una **aproximación de contenido de
referencia**, no la cantidad real de gas caliente. No está aprobada como
concentración física ni base de hipoxia. La temperatura, presión y composición
real pueden invalidarla; no calcular `x` mezclando kg de O₂ reales con una
base heredada que se reescribe sin conservar gas.

Inicialización futura: partir del total canónico y una asignación declarada
(por ejemplo homogénea). Si se admiten datos zonales, deben cerrar contra
`M` o rechazarse antes de escribir. No normalizar silenciosamente trazadores
históricos incompatibles para fabricar un estado inicial «válido».

## 4. Operaciones del oráculo, no leyes físicas

Implementadas solo en
[`g3_m4_partition_contract.py`](../../scripts/simulation/g3_m4_partition_contract.py).

1. **Remap de interfaz:** sobre una partición de referencia uniforme por
   tramos, si crece `B_u`, trasladar la fracción barrida del donante lower:
   `ΔU = L · ΔB_u/B_l`. Si decrece, el donante es upper:
   `U_nuevo = U · B_u_nuevo/B_u`. En ambos casos `ΔL = −ΔU`, `M` invariante.
   En colapso completo, todo `M` queda en la zona existente. Este remap es
   una convención contable propuesta, **no** una ley de arrastre de penacho.
2. **Mezcla impuesta:** `U_objetivo = M · B_u/B`;
   `ΔU = α · (U_objetivo − U)`, `ΔL = −ΔU`, `0 ≤ α ≤ 1`.
   No se define `α(dt)`, ni se importan las tasas históricas 0,03/0,05 s⁻¹.
3. **Presupuesto explícito:** el llamador aporta `ΔU`, `ΔL` y causa;
   `ΔM = ΔU + ΔL`. Un delta de sala solo es insuficiente. El núcleo
   rechaza un candidato sin donante o con sobrellenado, en vez de recortarlo.
   Una transferencia interna tiene `ΔM=0`; consumo/exterior requieren
   débitos y créditos declarados, no inferidos del resultado.

Ninguna operación pregunta qué ley generó esos valores. Por tanto pasar el
oráculo no autoriza escoger la capa que respira el fuego ni producir CO.
El chequeo presupuestario es independiente de la función propuesta, pero
no detecta un reparto equivocado que conserve todo: hay además cuentas
analíticas del perfil barrido y de mezcla. Esa limitación está probada.

## 5. Gates predeclarados de implementación

Tolerancia contable: `1e−9 kg` por operación/paso, heredada del contrato M3.
No se usa para aceptar masa negativa, redondearla a cero ni relajar rechazos.
Las fracciones y estados inválidos se rechazan, incluidos NaN, infinito,
booleanos, causas vacías y entradas de tipo incorrecto.

| Gate | Exigencia | Oráculo separado |
| --- | --- | --- |
| P1–P4 | Cambios de sala/upper/lower = deltas declarados; el par suma el total | Antes/después/recibo, sin reejecutar la operación |
| P5 | Mezcla/remap no cambian `M` | Igualdad del total, no suma de trazadores |
| P6 | El remap conserva `B` | La interfaz cambia reparto, no contenido total |
| P7 | Recibos finitos | NaN no puede pasar por comparación falsa |
| P8 | Remap con donante correcto | Integral manual del perfil antiguo, en ambos sentidos |
| P9 | Mezcla con donación pareada y objetivo declarado | Perfil uniforme invariante; mezcla total analítica |
| P10 | Capa ausente sin oxígeno fantasma | Inventario cero, observable ausente, renacimiento desde donante |
| P11 | Rechazo sin escritura ni recorte | Entrada inmutable e idéntica tras excepción |
| P12 | Sin deriva acumulada | 10 000 remaps y mezclas deterministas |

Falsación offline: recibo con delta total/upper/lower falso, par no cerrado,
cambio de base, NaN y reparto homogéneo incorrecto que sí conserva el total.
Son testigos de defectos del **contrato**, no mutaciones del motor ni campañas
Godot. El futuro núcleo GDScript necesitará mutantes de su código real.

## 6. Trabajo restante, por orden

1. **M4-A1, siguiente entrega:** núcleo puro GDScript con estas operaciones,
   fixture sintética y mutaciones válidas; sin integración ni tasa física.
   Mantener M3/selección de sala congelados. Si se añade en `sim/`, R2-1 exige
   referencia completa, guardarraíles, producto y global por monitor seguro.
2. **M4-B, diagnóstico del adaptador:** inventariar todas las escrituras
   zonales y todos los eventos de gas, interfaz, exterior y puertas de las
   rutas soportadas. Distinguir remap geométrico de transferencia física:
   no aplicar dos veces un penacho porque también cambió la interfaz.
   Entradas/salidas de M2-T/M2-V requieren un reparto explícito defendible.
   Un adaptador que solo cierre inventario de sala sigue NO-GO.
3. **M4-C, autoridad del reparto:** un punto único de escritura de `U`,
   retirar trazadores competidores únicamente en el modo nuevo; conservar
   la selección de sala de M3 hasta el siguiente gate. OFF byte a byte.
   Los observables nuevos deben etiquetarse como contenido de referencia.
4. **M4-D, selección y reserva zonales:** misma selección para fuego y
   sumidero, fuente/deposito/mezcla de zonas declarados, disponibilidad y
   reserva por depósito; una sola fracción del paquete M3. Una capa agotada
   no puede gastar O₂ de la otra por leer el promedio. Resolver el arrastre
   y su calendario antes de admitirlo; no copiar una banda de 0,3 m como
   ley validada. Varios fuegos siguen fuera hasta un contrato específico.
5. **M4-E, contraste:** casos equivalentes CFAST y luego ensayos medidos
   con alturas de sensor, geometría, HRR y ventilación homologados. Medir
   sensibilidad a paso, interfaz y base. Cerrar o acotar el sesgo debido a
   contenido de referencia antes de autorizar hipoxia/FED o producto.

Un gate matemático verde no salta ninguno de los siguientes. No modificar
checks/baselines para convertir la aproximación en evidencia experimental.

## 7. CFAST: referencia consultada y límite de la comparación

Consultado código oficial en la etiqueta **CFAST-7.7.7** el 12-10:

- [`solve.f90`, `update_data`](https://github.com/firemodels/cfast/blob/CFAST-7.7.7/Source/CFAST/solve.f90):
  cuando el O₂ es variable del solver, conserva kg por zona y deriva fracción
  **másica** con la masa de esa zona. No equivale a nuestra base de referencia
  ni a nuestras fracciones molares; comparar exige convertir y declarar bases.
- [`fire.f90`, `do_fire`](https://github.com/firemodels/cfast/blob/CFAST-7.7.7/Source/CFAST/fire.f90):
  el arrastre lleva especies desde lower y resta el mismo flujo del donante.
  La química usa el oxígeno de la zona fuente. Esto apoya operaciones pareadas,
  no los valores de una tasa ni el remap geométrico propuesto aquí.

Se consultaron primero archivos de master y después la etiqueta correcta;
los enlaces anteriores son los usados para estas afirmaciones. No se archiva
código ni se afirma una huella nueva del solver externo. La consulta no es
una corrida CFAST ni un contraste con NIST. La guía TN 1889v1 ya está en la
biblioteca, pero no se ha releído el PDF en esta fase; no atribuirle lectura
nueva. No se importan datos FSRI ni documentos con permiso pendiente.

## 8. Verificación y retomada

Entrega del contrato completada, sin commit/push ni implementación runtime:

- **66 pruebas nuevas PASS**; focal con M1/M2/M3 y evidencia actual:
  **200 passed**, sin exclusiones, en 6,00 s. No sumar los recuentos: las
  66 están dentro de las 200. Ninguna prueba de esta tanda lanza Godot.
- Ocho testigos de recibo/reparto corrupto rechazados por sus controles
  declarados; no se llaman ocho mutantes de motor. Las 10 000 iteraciones
  pertenecen a una prueba determinista del oráculo, no a ticks del producto.
- Cuatro Markdown comprobados, cero enlaces locales rotos. AST de los dos
  Python válido, sin líneas de más de 120 caracteres; `git diff --check` limpio.
- Guardarraíles **ALL PASS**, R2-1 incluido: referencia existente M3 de
  **346/346 y 78 gaps**, sin regeneración ni cambio en ningún informe.
- SHA-256 compuesto (ruta y hash de cada archivo, ordenados) de los **1 010
  archivos versionados de sim/** idéntico antes/después:
  `11a865e246975fec8181184c20716d94e05554a438de6d681da31afc3aa01860`.
  Incluye los informes; no confundir esta cantidad con módulos de motor.
- Los **79 .gd.uid ajenos** siguen idénticos por inventario/hash, y los cuatro
  stashes conservan sus identificadores. Cero procesos Godot al cerrar.
- HEAD sigue en `993d98ec`; main intacto. Seis archivos de esta entrega en la
  rama shareable: cuatro Markdown (tres actualizados y este nuevo), el
  oráculo y su suite. No hay nuevos assets, datasets ni fuentes físicas.

No se repiten producto ni global completa: no se ha tocado runtime, sus
arneses, datos ni casos, y la focal es enteramente offline. Esto no constituye
un PASS nuevo de esas suites ni una dispensa para el siguiente cambio en sim/.
No ejecutar Godot para este oráculo ni regenerar la referencia existente
como si validase M4. Producto, CO/FED y leyes físicas siguen OFF.

Siguiente: implementar **solo M4-A1**, no conectar el reparto al motor.
