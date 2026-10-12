# G3 — M4-B: diagnóstico del adaptador de oxígeno por capas

Fecha: 2026-10-12. Base publicada: `b51af2c0` (M4-A1 puro).
Continuación autorizada al diagnóstico, no al cambio de ley de transporte.

**Diagnóstico estático cerrado; NO-GO a integrar un adaptador físico.**
GO a preparar un contrato offline de eventos con donantes explícitos.
M3 sigue seleccionando el inventario de sala. M4-A1 sigue sin consumidores
de simulación. CO/FED y promoción de producto siguen **OFF/NO-GO**.
No se ejecutó Godot, ni CFAST, ni se añadieron mediciones NIST en esta fase.

## 1. Resultado principal

No basta con sustituir los números de las capas por el núcleo conservativo:

1. Hay varios escritores auxiliares, incluidos los posteriores al paso O2.
2. M2-T obtiene las dos parcelas del **promedio de sala**, no de una capa.
   Elegir ahora una capa donante cambia esa ley cuando hay estratificación.
3. M2-V es dilución equivalente del recinto entero, no una parcela que sale
   necesariamente de upper. ACH tampoco declara capas de entrada y salida.
4. El cambio de interfaz puede ser consecuencia del penacho, de calor sin
   movimiento de gas, de una abertura o de una proyección. Aplicar el remap
   por el cambio total y además una transferencia del penacho puede duplicar
   el mismo paquete. La conservación global no detecta ese error de reparto.

Estos límites se deducen del código y de testigos algebraicos con entradas
impuestas. No son cifras nuevas del incendio de una casa ni una calibración.

## 2. Inventario reproducible y alcance de la búsqueda

[Evidencia estructurada](G3_O2_M4_ADAPTER_DIAGNOSIS_EVIDENCE_2026-10-12.json)
y [auditor de lectura](../../scripts/simulation/audit_g3_m4_layer_writers.py).
Se recorrieron **64 archivos `.gd` de sim/**: **35 sitios de escritura directa**
de `o2_upper/o2_lower`, más dos declaraciones iniciales separadas.
No son 35 rutas activas, ni 35 llamadas por tick.

| Propietario histórico | Sitios | Clasificación de la inspección |
| --- | ---: | --- |
| RoomModel | 2 | Reset de ambas fracciones; no inicialización canónica de U |
| OxygenExchangeSystem | 20 | 14 en step, 3 en exterior, 3 en intercambio interior auxiliar |
| ThermalSystem | 7 | 1 siembra para red, 3 contraflujo, 3 puerta canónica |
| HVACSystem | 4 | Extracción/suministro condicionales; sin operación del dueño O2 |
| PressureNetworkTransportSystem | 2 | Commit zonal de red, combinación rechazada por M3 |

El JSON conserva función, línea, campo, inicio de escritura y huella LF de
cada fuente. Inventario compuesto de los 64 `.gd`:
`a03f8b50343d7598882a9da949b4b9fa8b563c96eeaab16fdf3aeea73110e771`.

El auditor enmascara comentarios y cadenas y excluye `co2_upper`, comparaciones
y declaraciones del recuento de escrituras. **Es lexical, no un análisis AST
de alias ni una demostración de alcanzabilidad.** Se revisaron también los
`set()` dinámicos de core/building: los bucles encontrados escriben especies
CO/CO2/HCN o sus masas, no estas dos fracciones O2. No afirmar que la búsqueda
demuestra ausencia de cualquier escritura indirecta imaginable.

La coincidencia por huella protege esta instantánea completa, no solo las
líneas que coincidieron con la expresión regular. Un cambio futuro obliga a
revisar evidencia y elegibilidad, no a regenerar la lista para ponerla verde.

## 3. Escritores y rutas: lo que realmente permite M3

Fuentes: [OxygenExchangeSystem](../../sim/core/OxygenExchangeSystem.gd),
[ThermalSystem](../../sim/core/ThermalSystem.gd),
[RoomOxygenInventory](../../sim/core/RoomOxygenInventory.gd),
[SimulationEngine](../../sim/core/SimulationEngine.gd).

- OES.step sigue ejecutando consumo/arrastre **auxiliar** de zonas, ACH lower,
  relajaciones independientes (0,05/0,03 s^-1), homogenización bajo 15 % de
  lower y clamps, aunque el total tenga dueño. No importar esas tasas ni el
  floor como leyes conservativas de M4. La escritura del tracker y el modo
  lower directo están condicionados a modos que M3 rechaza; no sumar todos
  los 14 sitios como si se ejecutasen juntos.
- Los tres sitios exteriores de OES están en rutas que el dueño rehúsa cuando
  llega el intercambio térmico exterior. No integrarlos silenciosamente ni
  confundirlos con la infiltración ACH o con M2-V, que sí tienen operaciones.
- Los tres sitios interiores de OES son boosts/relajaciones condicionales
  después del intercambio de sala; no son débitos/créditos pareados de capas.
- Thermal contraflujo reparte un delta histórico 50/50 en la sala caliente;
  la puerta canónica mezcla con diferentes bases y puede depositar retorno
  directamente arriba. Estos flags no quedan todos fijados por el entorno
  requerido del dueño. Hay que retirarlos o rechazarlos explícitamente en
  el modo futuro, no asumir que están apagados por estar M3 activo.
- La siembra térmica como paquete tiene donante lower real, pero su llamador
  corresponde a la red autoritativa. La red sigue expresamente fuera de M3.
- HVAC activo escribe room.o2 y, según hooks/altura, fracciones zonales;
  no recibe RoomOxygenInventory. El entorno requerido no comprueba HVAC.
  El audit final detecta discrepancias del número de sala, pero eso **no** es
  soporte de la ruta ni rechazo previo a sus otras escrituras. HVAC debe
  quedar excluido por contrato explícito antes de un adaptador nuevo.
- PPV, transporte agregado GES y entregas de parcelas GES contienen rechazos
  nombrados ante el dueño; no añadirlos a SUPPORTED_ROUTES por estar en step.
  `refuse_route` ignora cantidades nulas: no significa que todo caso con esos
  subsistemas instalados sea rechazado antes de avanzar.
- El tránsito firmado de M1 solo es API diagnóstica inyectable. No es la ruta
  viva de puertas M2-T; no inventar una nueva cola zonal a partir de ella.

La lista SUPPORTED_ROUTES del dueño describe operaciones de **sala**, no una
lista de mecanismos con origen y destino zonales ya resueltos.

## 4. Calendario y mapa de eventos

En SimulationEngine.step, con el entorno M3 permitido:

1. begin_step y selección/reserva de sala; caché de flujos interiores con el
   estado inicial del tick.
2. Fuego; OES después del fuego: liquidación de reserva, infiltración y
   puertas; también los escritores auxiliares zonales de OES.
3. Thermal: penacho, calor, proyecciones y puertas térmicas.
4. GES: venteo M2-V y otras rutas de humo/especies; después HVAC.
5. Reconcile si procede, clamp y audit_room_numbers al final.

El futuro reparto debe estar disponible al siguiente begin_step, pero no
introducir una selección de capa anterior a cerrar el contrato M4-D.
La caché compartida no garantiza que OES y Thermal apliquen el mismo paquete:
usan cantidades, caps y coeficientes distintos.

| Evento actual | Donante/destino disponibles | Lo que falta para M4 |
| --- | --- | --- |
| Consumo M3 reservado | Depósito de sala, selección y kg exactos | Depósito zonal y calendario, reservado para M4-D |
| ACH | Gas de referencia, exterior y fracción de sala previa al sumidero | Alturas/donantes declarados; el neto no los determina |
| M2-T background | Cantidad igual en ambos sentidos, ambos inventarios previos | Parcela zonal o declaración explícita de homogeneidad |
| M2-T activo | q desde caudal lower/cap; ambos inventarios de sala | No identifica el gas upper saliente ni su composición |
| M2-V | Entrada exterior, mezcla de sala, salida equivalente | No convertir en upper-out/lower-in sin cambiar contrato |
| Penacho térmico dos zonas | ZoneFireSolver preview: kg y kJ lower->upper | Base compatible O2, identidad única, relación con remap |
| Puerta térmica | Cantidades de gas/energía efectivamente aplicadas | No reutilizar q de OES ni sumar ambos como una misma ruta |
| Sync/collapse de interfaz | Altura antes/después, causa de proyección | Separar transferencia representada de remap residual |

ZoneFireSolver.preview_lower_to_upper_transfer devuelve `mass_kg/energy_kj`,
no O2; apply mueve gas y energía, no escribe las dos fracciones.
El shadow de Thermal para ese penacho publica
`o2_kg = moved_mass_kg * o2_lower`: no usa la conversión molar de referencia
`x * gas_kg * M_O2/M_air`. **No consumir ese campo como kg canónicos M4**.
Tampoco corregirlo dentro de este diagnóstico como si bastase añadir el factor:
la base física de gas y la base de referencia siguen siendo diferentes.

El ledger runtime térmico lleva deltas por recinto/apertura, pero no toda la
identidad, base y distribución de capas que exigiría el adaptador. Es lectura
diagnóstica condicionada a su flag, no un bus de transacciones ya disponible.

La interfaz de enrutamiento procede de
[LayerInterfaceModel](../../sim/core/LayerInterfaceModel.gd), que usa la térmica,
no la visible. Matiz: el **driver** heredado de build_interior_opening_flow_state
sí mezcla factores de humo, calor y presión. No afirmar que todo el caudal
heredado es independiente de lo óptico porque el getter de interfaz lo sea.

## 5. Tres testigos independientes, no simulaciones de incendio

[Pruebas offline](../../tests/test_g3_m4_adapter_diagnosis.py) usan el oráculo
de M4-A como estado sintético; no ejecutan el núcleo GDScript ni Godot.

**Neto de sala insuficiente.** M=0,3 kg, U=0,1 kg, bases 1/1 kg O2 de
referencia. Un débito de 0,03 kg puede dejar U=0,07 (debitar upper) o U=0,10
(debitar lower). Ambos cierran el mismo total 0,27 kg. El balance no elige.

**Cambio de ley por donante estratificado.** Para 1 kg de gas de referencia
en cada sentido, sala caliente con x_room=0,20 y x_upper=0,10, retorno a
x=0,21: M2-T da `(0,21-0,20)*kappa ~= 0,0110472 kg O2`; muestrear la capa
alta da `(0,21-0,10)*kappa ~= 0,121520 kg`, kappa=0,031998/0,0289647.
Solo coinciden si el donante muestreado tiene la concentración de sala.
Un futuro cambio zonal necesita contrato nuevo, comparación con M2-T y
decisión explícita; no exigir identidad ON estratificada contra una ley distinta.

**Doble paquete invisible al balance.** M=0,3, U=0,1 y bases 1/2: el remap
a bases 1,5/1,5 transfiere 0,05 kg, U=0,15. Añadir otra vez ese mismo paquete
como penacho deja U=0,20 y conserva M=0,3. Ambos pasan los checks de presupuesto.
Es un testigo del riesgo de contarlo dos veces, no una afirmación de que el
motor hoy ejecute M4 (no lo hace).

## 6. Contrato siguiente propuesto: M4-B1, antes de M4-C

Preparar **solo offline** eventos/recibos y controles adversariales:

- Identidad de generación/tick/etapa, evento físico y contribución; recinto,
  abertura, donante/receptor, zona y estado anterior. El objeto OpeningModel
  o su identidad real, no un nombre que colisione entre dos puertas iguales.
- Magnitud declarada: kg de gas **físico** o de gas **de referencia** y su
  conversión; kg de O2, bases antes/después e interfaz térmica. Cantidad aplicada,
  no la solicitada que un cap recortó ni el delta inferido de toda la sala.
- Transferencia interna, frontera, consumo, mezcla y remap como operaciones
  distintas. Una contribución aceptada una vez; un fallo valida ambos extremos
  antes de escribir M o U. No actualizar M y descubrir después que U no valida.
- Para un movimiento ya representado en la partición, marcar qué cambio de
  interfaz queda cubierto; **no restar kg físicos de una base de referencia**
  sin un modelo declarado. Si no se conoce esa relación, rechazar el evento,
  no adivinar el remap residual a partir de alturas finales.
- Testigos de evento repetido, etapa/generación equivocada, capa ausente,
  donante agotado, dos puertas entre las mismas salas, tipos no numéricos,
  unidades/bases incompatibles y rechazo sin escrituras parciales.
- Resolver la compatibilidad M2-T/M2-V: preservar la mezcla de sala con una
  redistribución **de referencia** explícita no la vuelve transporte físico.
  Adoptar parcelas zonales cambia la ley ON y exige evidencia/gate específico.
  No seleccionar una de estas opciones por hacer cerrar las cuentas.

**NO-GO M4-C/M4-D ahora.** M4-B1 puede falsar contratos sintéticos, pero no
autoriza caudales, tasas de mezcla, selección del fuego, hipoxia ni CO/FED.
Después harán falta adaptador real bajo monitor, trazas por evento/ruta,
OFF byte a byte y cadena R2-1 al tocar sim/. No se salta el contraste M4-E.

## 7. Verificación y publicación

Primera focal nueva: **18 passed**, 0,86 s, sin exclusiones ni Godot.
Comprueba el inventario completo contra fuentes, los tres testigos y los
límites actuales de M2-T/shadow. No son mutaciones del motor.
Focal final con M4-A/A1: **111 passed**, 2,20 s; incluye las 18 nuevas.
Sin exclusiones y sin lanzar Godot. Guardarraíles ALL PASS con R2-1 usando
la referencia vigente de 346/346 y 78 gaps, **no** una referencia regenerada.
Estilo GDScript PASS, AST de los dos Python válido, sin líneas mayores de
120 caracteres, cuatro Markdown modificados sin enlaces rotos y diff limpio.
sim/ versionado sin diff; los 64 .gd mantienen la huella de la inspección.
79 UID ajenos conservan la huella de la fase anterior y los cuatro stashes
sus identificadores. Main limpio antes de integrar; remoto comprobado por
fetch sin avance ajeno. Publicación del diagnóstico autorizada por la
instrucción vigente de commit/push e integración cuando la fase esté verde.
Solo siete archivos propios; UID, runs/ y ramas privadas quedan excluidos.

No se cambian leyes, flags, EOS, transporte, escenarios, editor, exposición,
informes de referencia ni ningún archivo de sim/. No se repiten referencia,
producto ni global Godot: el cambio es un diagnóstico offline con pruebas
propias; no se atribuye un PASS nuevo a esas campañas históricas.
No se descargan datos ni fuentes externas. Las referencias CFAST y NIST del
[contrato anterior](G3_O2_M4_PARTITION_CONTRACT_2026-10-12.md) no se releen ni
se convierten aquí en verificación experimental.
