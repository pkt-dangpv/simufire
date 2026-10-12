# G3 — M4-B1: contrato offline de eventos de oxígeno

Fecha: 2026-10-12. Base publicada `163b24f4`.
Continuación autorizada al contrato anunciado en
[M4-B](G3_O2_M4_ADAPTER_DIAGNOSIS_2026-10-12.md), no a integrar física nueva.

**Cerrado como contrato sintético offline. NO-GO al adaptador físico,
M4-C/M4-D, hipoxia y producto. CO/FED OFF/NO-GO.**
No se ha ejecutado Godot ni modificado ningún archivo de sim/.

## 1. Entrega y alcance

- [Contrato Python](../../scripts/simulation/g3_m4_event_contract.py), puro:
  instantáneas, eventos, candidatos y recibos inmutables. No importa el motor,
  no guarda ficheros ni tiene un escritor vivo de M/U.
- [Pruebas y falsación](../../tests/test_g3_m4_event_contract.py): donantes,
  receptores, dos puertas entre las mismas salas, unidades, calendario impuesto,
  ausencia de capa y rechazo sin escritura parcial.
- [Evidencia verificable](G3_O2_M4_EVENT_CONTRACT_EVIDENCE_2026-10-12.json):
  huellas LF, resultados, mutantes aceptados e intentos que no cuentan.

Se usa el Partition del oráculo M4-A, sin modificarlo, y no el núcleo GDScript.
M4-A1 conserva sus bytes y sigue sin llamadores de simulación. No se convierte
esta entrega en una implementación de M4 en el paso de física.

## 2. Qué exige un evento

| Elemento | Contrato offline |
| --- | --- |
| Context | Generación y tick enteros no negativos; etapa exacta oxygen/thermal/gas/reconcile |
| Room | Id, revisión, M/U y bases B_u/B_l, interfaz y altura; comparación exacta de snapshot |
| Opening | UID registrado y recintos asociados; dos puertas iguales necesitan UIDs distintos |
| Event | Id del evento físico, causa, participantes exactos, contribuciones y abertura si procede |
| Parcel | Origen/destino explícitos, capa upper/lower, kg O2 aceptados, cantidad/base de referencia |
| Mix/Remap | Operación separada, parámetros impuestos y un solo recinto |
| Receipt | Estado antes/después de cada participante y deltas upper/lower |

No se crea una identidad de puerta con `op_a_b_tipo`. Los UIDs de este banco
son sintéticos y registrados; **el motor todavía no los proporciona**.

Un estado esperado obsoleto por inventario, interfaz o revisión se rechaza.
No se reconstruye a partir del promedio ni se normalizan los trazadores
históricos para fabricar una instantánea válida.

La etapa es una precondición impuesta por el llamador, no una demostración
del calendario real del motor. No se implementa aquí begin_step/reset ni
la retirada de un propietario vivo. El contrato no permite la etapa fire:
no modela la selección/reserva del fuego de M4-D.

## 3. Unidades y atomicidad

Solo las parcelas `reference_dry_air_v1` tienen conversión aprobada en este
contrato: `kg_O2 = x_molar * kg_gas_ref * (0,031998/0,0289647)`.
El donante se lee de la **instantánea zonal anterior**; la frontera de entrada
declara su fracción molar. Los kg O2 deben coincidir con esa conversión dentro
del umbral contable 1e-9 kg, no sustituirse por una fracción multiplicada por kg.

Una parcela marcada como gas físico, una base ambigua o un campo sin unidad
conocida se rechazan. No basta añadir el factor molar al penacho heredado:
seguimos sin un mapa aprobado entre su gas físico y el contenido de referencia.

Transferencia, entrada exterior, salida exterior y consumo tienen formas
distintas. El consumo sintético declara kg O2 y depósito; **no** define HRR,
coeficiente estequiométrico, reserva, fuego elegible ni una política de capa.
Los valores son cantidades ya aceptadas e impuestas, no demandas a recortar.

Dentro de un evento se suman todas las donaciones por depósito antes de
construir candidatos. Una entrada simultánea no financia una donación que
exceda lo disponible previamente. También se limita el total de gas de
referencia al contenido declarado del donante, incluso si tiene cero O2.
No hay clamp/floor ni tolerancia para autorizar inventario negativo.

Se validan todos los extremos y el candidato completo antes de devolver el
nuevo Book. Un receptor sobrellenado no modifica al donante ni registra el
evento como aceptado. El Book anterior, sus instantáneas y el recibo son
inmutables. Esto es atomicidad de **propuesta offline**, no una transacción ya
instalada alrededor de las escrituras de RoomOxygenInventory.

Las bases permanecen fijas en las parcelas: se contrasta presupuesto de O2
de referencia, **no conservación física del gas**. No interpretar un crédito
de O2 como masa/volumen nuevo de una zona térmica.

## 4. Interfaz, mezcla e identidad: no duplicar una representación

El id físico aceptado se guarda por generación/tick, independiente de etapa
y del nombre de la contribución. Repetirlo, renombrar su contribución o usarlo
otra vez como remap en otra etapa se rechaza.

Un evento es parcelas, una mezcla impuesta o un remap geométrico; no una suma
de representaciones sin contrato. El remap rechaza `physical_transfer`, una
representación desconocida o `covered_by_event_id`: no calcula un barrido
residual a partir de alturas finales ni descuenta kg físicos de B_u.

Mix y Remap usan las operaciones matemáticas ya definidas en M4-A. La mezcla
recibe alpha, sin alpha(dt). El remap recibe B_u e interfaz; no deduce una
base física de gas, ni aprueba B_u=B*(H-z)/H como concentración real. Esas
entradas son independientes e impuestas: validar sus rangos y snapshots no
demuestra que correspondan al mismo campo físico. Esa relación sigue pendiente.

**Límite de identidad:** con un id físico nuevo y una causa declarada distinta,
la contabilidad no descubre que el productor ha etiquetado dos veces la misma
parcela real. El productor autoritativo deberá dar identidades confiables y
un contrato de cobertura; este banco no prueba esa integración.

## 5. Verificación independiente y falsación

audit_receipt no llama apply_event. Comprueba estados, deltas, revisiones,
alturas, participantes, conversión de referencia, donaciones brutas y piernas
aceptadas. Para mix/remap usa expresiones algebraicas alternativas del perfil
impuesto, no solo conservación total. Un reparto equivocado que conserve M
es detectado por esos controles. No valida el origen real del id ni una ley
de flujo, ni reemplaza la comprobación de abertura del candidato.

Resultado focal final: **226 passed**, 3,09 s, sin exclusiones ni Godot.
Incluye **115 pruebas nuevas** de esta fase; no sumar ambos recuentos.
Una prueba ejecuta 500 eventos sintéticos alternados con deriva total dentro
de 1e-9 kg; no son 500 ticks de un incendio de producto.

**12/12 mutantes del contrato Python detectados** por su testigo declarado:
identidad, contexto, conversión molar, promedio en vez de capa, donación
bruta, abertura, contribución duplicada, snapshot obsoleto, representación,
Book mutable, auditor de piernas y mezcla omitida.

Se compilan en memoria, no se escribe código mutado en disco. Cada testigo
debe pasar tanto con el módulo original como con un clon sin modificar.
Solo cuentan fallos por aserción/resultado de contrato, no sintaxis, importación
o error accidental. Los dos mutantes de muestreo/conversión rehúsan una
parcela predeclarada válida: ese rechazo se clasifica por su testigo como
incumplimiento, no como fallo del intérprete. El testigo solo admite el
rechazo exacto de conversión predeclarado: un error accidental de tipos/carga
no cuenta como detección. Los bytes de la fuente se comprueban intactos en
cada mutación. **No son 12 mutaciones del motor GD.**

Intentos que no cuentan:

- Primera tanda: 4 failed / 106 passed. El helper conservaba endpoints de la
  clase original al probar módulos mutados, causando rechazos por tipos.
  No se acepta esa campaña; se construyen endpoints del módulo actual y
  se añade el control en clon sin modificar.
- Tras reforzar el auditor: 1 failed / 111 passed por ancla de mutación
  duplicada. Se acota al bloque de aplicación; no es una muerte válida.
- La tanda final añade el mutante de mezcla omitida y queda toda verde.

Revisión staged posterior: el auditor no fijaba las dos bases zonales ni
la interfaz para parcelas, aunque apply_event sí las dejaba intactas.
Se añadió ese chequeo y dos testigos de recibos alterados que conservan
las masas; se repitió toda la focal/falsación sobre los bytes finales.
La anterior focal 224 PASS no sustituye la final 226 PASS registrada.

Guardarraíles **ALL PASS**, R2-1 incluido, sobre la referencia vigente
346/346 y 78 gaps. No se regenera referencia ni se repiten producto/global
Godot: no hay cambios de sim/, arneses de lanzamiento ni datos de producto.
No atribuir PASS nuevo a esas suites ni al núcleo GD en esta fase.
Estilo GDScript, AST Python y diff limpios; cero enlaces rotos en los cuatro
Markdown modificados. 79 UID y cuatro stashes conservan sus huellas/ids;
los 64 archivos GD mantienen el inventario LF de M4-B, sin cambio de sim/.

## 6. Retomada y decisiones que siguen abiertas

Contrato offline cerrado; **no** adaptador real, autoridad zonal, selección
del fuego, calibración ni exposición. Ninguna política de compatibilidad
M2-T/M2-V se escoge aquí: las parcelas impuestas del banco no reemplazan
la mezcla de sala viva ni autorizan resultados distintos en producto.

Siguiente trabajo propuesto, M4-B2: diseñar y obtener captura pasiva de
eventos reales por ruta/etapa, con cantidades antes de agregación y caps,
identidad y geometría. Juzgar qué productores pueden emitir el contrato y
cuáles deben seguir rechazados. No reconstruir donantes a partir del neto
de sala ni usar las fracciones auxiliares como inventarios medidos.

La compatibilidad de M2-T/M2-V y la conversión gas físico/referencia deben
decidirse con evidencia antes de M4-C. Si la captura requiere sim/, usar el
monitor seguro, memoria comprobada, tandas secuenciales y cadena R2-1;
no Godot directo ni activación de producto. No saltar la reserva M4-D ni
el contraste CFAST/NIST M4-E. No se consultaron nuevas fuentes externas
ni se descargaron datasets en esta entrega.

Publicación autorizada por la instrucción vigente de commit/push e
integración cuando la fase esté verificada. Solo archivos propios de este
contrato; preservar UID, stashes, runs/ y ramas privadas.
