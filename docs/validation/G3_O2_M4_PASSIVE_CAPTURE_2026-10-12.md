# G3 — M4-B2: captura pasiva del motor real

Fecha: 2026-10-12. Base publicada `98ee4775`.
Continuación autorizada a la captura descrita en
[M4-B1](G3_O2_M4_EVENT_CONTRACT_2026-10-12.md).

**Captura cerrada para cuatro controles declarados; adaptador físico NO-GO.**
Se ejecutó SimulationEngine real, no solo un oráculo Python. Los casos son
sintéticos, no ensayos medidos ni las viviendas distribuidas del videojuego.
CO/FED y promoción de producto siguen OFF/NO-GO. No cambios en sim/.

## 1. Implementación de observación, no de física

[Fixture GD](../../tests/fixtures/g3_o2_m4_route_capture.gd),
[lanzador/análisis](../../scripts/simulation/run_g3_o2_m4_route_capture.py),
[testigos offline](../../tests/test_g3_m4_route_capture.py) y
[evidencia](G3_O2_M4_PASSIVE_CAPTURE_EVIDENCE_2026-10-12.json).

Subclases **solo en la fixture** de OES, Thermal, ZoneFireSolver y GES
copian el estado ya configurado de sus servicios y llaman cada función padre
una sola vez, con los mismos argumentos y retornando su resultado original.
La observación lee/copias snapshots y recibos; no aplica parcelas ni cambia
flujos, capas, demanda, masa, energía o interruptores de física.
El observador térmico se vincula al solver observado, no al desplazado.

Cada caso construye un mundo vanilla y otro observado. Después de configurar
las aberturas y **en cada tick**, exige igualdad de la serialización de los
campos primitivos de RoomModel, fuego, muebles y aberturas, más el informe
canónico O2, tiempo y fallo de sala. JSON ordenado a precisión completa.
NaN y los infinitos se etiquetan de forma distinta; no se convierten en null
para fabricar identidad. No implica que todos los sentinelas del motor sean
finitos ni que cada estructura interna/archivo de salida se haya comparado.

No se compara OFF/ON de una física nueva: se compara **observador/sin
observador sobre los mismos bytes de motor**, con M3 ON únicamente en estos
controles. M4-A1 y el contrato offline M4-B1 no se conectan a la simulación.

## 2. Casos y resultado final

Se reutiliza el constructor de M3: dos recintos de 48 y 38,4 m3, un objeto
sintético de 1 100 MJ y 700 kW máximos. No valida un sofá material real ni sus
yields. No hay HVAC ni fuego secundario. Tick 0,25 s, propiedades y umbrales
del motor sin recalibrar. La segunda puerta y la ventana son aberturas
diagnósticas normales con índice real diferente; no archivos de escenario editados.

| Caso | Horizonte | Ticks por mundo | q interior de referencia, kg | q de dilución M2-V, kg |
| --- | ---: | ---: | ---: | ---: |
| Sellado | 60 s | 240 | 0 | 0 |
| Una puerta abierta | 60 s | 240 | 14,552630 | 0 |
| Dos puertas entre las mismas salas | 60 s | 240 | 27,798290 | 0 |
| Ventana exterior cerrada | 300 s | 1 200 | 0 | 0,496405 |

q interior es la suma de la cantidad igual intercambiada **por sentido** de
M2-T, no suma de ambos sentidos ni masa física total evacuada. La dilución
M2-V es cantidad equivalente de gas de referencia de su dueño; no kg de
humo ni la masa física que sale por la ventana.

**3 844 comprobaciones PASS, cuatro pares idénticos en los estados comparados,
cero fallos y todos los propietarios armed.** 1 920 ticks por variante,
3 840 ejecuciones del paso entre los ocho mundos. No sumar intentos previos.
Desviación máxima del balance global O2 por tick: **5,85e-15 kg**.
Conversión M2-T máxima: **1,39e-17 kg**; entrada/salida M2-V contrastadas
independientemente: máximo **5,42e-20 kg**.

El penacho dona lower->upper 22,876196 / 29,568080 / 29,736488 / 59,267490 kg
de gas según caso. Es el gas del solver, **no kg O2 ni una base de referencia**.
La ventana incluye también transferencias de siembra mínima: la causa se
etiqueta por el llamador real, separada del penacho. No sumar preview y apply.

## 3. Qué está disponible y qué sigue faltando

| Ruta observada | Datos realmente leídos | Elegibilidad actual para M4 |
| --- | --- | --- |
| Consumo/ACH | Cantidad aceptada y operaciones canónicas, estado antes/después | Sala, no depósito zonal del fuego |
| Puertas M2-T | Índice de abertura, q post-caps, dos parcelas O2, fracciones de sala previas | Sin petición pre-cap ni donante zonal |
| Penacho/siembra | Petición que llega al solver, preview aceptado, aplicación pareada de gas | Base gas físico y paquete O2 zonal sin mapa |
| Sync térmico | Causa, interfaz y masas antes/después | No es una parcela ni cobertura física de remap |
| M2-V | Operación de dilución y q equivalente, exterior, volumen, entrada/salida O2 | Sala agregada; no atribución por abertura/capa |

La petición del solver ya incorpora límites térmicos previos: no llamarla
caudal bruto sin recorte. Las capas O2 que aparecen en el snapshot están
etiquetadas **auxiliary_fraction_not_inventory**. No convertirlas en kg
canónicos multiplicándolas por las masas calientes de gas.

Los ids de observación incluyen caso/tick/llamada y sirven para no repetir
filas; no son el id físico autoritativo que exige M4-B1. Preview, apply,
contenedor OES y resumen de tick observan distintos niveles de una operación.
El auditor suma presupuestos solo desde tick_summary, q de puertas solo
desde sus callbacks y gas de penacho solo desde apply. Un testigo comprueba
que un contenedor repetido no duplica el transporte.

Quedan sin medir elegibilidad HVAC/PPV, red de presión, apertura exterior
caliente, tránsito diagnóstico y varios fuegos. No levantar sus rechazos ni
atribuirles soporte por el resultado de estos controles. Las cuatro rutas
siguen **NO-GO para un adaptador físico zonal**: conservar el total y copiar
un recibo no decide distribución, composición o cobertura de interfaz.

## 4. Seguridad, pruebas y trazabilidad

Memoria antes del primer intento: **6,891 GiB**. Cada solicitud al monitor
exige mínimo 6 GiB, temporales APPDATA/TEMP/TMP externos y un solo Godot.
No se ejecuta Godot directamente: el monitor usa el ejecutable normal,
evita el wrapper de consola, suprime UI de errores y conserva el JobObject
de sus propios descendientes. No termina procesos ajenos.

Captura aceptada final: 19:29:36–19:30:03 UTC, returncode 0, stderr vacío,
sin timeout, cuadros, procesos ajenos/residuales ni limpieza por terminación.
Resultado completo y cuatro JSONL con hashes:
`%LOCALAPPDATA%/Temp/simufire_m4b2_capture_final_20261012/`.
El JSON versionado conserva los resultados, salud y hashes; los registros
brutos permanecen externos y no se publican como archivos del producto.

**15 pruebas offline nuevas; focal 241 passed**, 3,40 s. Incluye las 226
anteriores y repite su falsación Python; no son nuevos mutantes de GD.
Los testigos corrompen identidad, ticks, abertura, conversión, presupuesto,
paquetes de gas y M2-V con total aparentemente cerrado. Cantidades no finitas
se rechazan. Los snapshots no se reparan para pasar una prueba.

Motor GD: inventario LF de los 64 archivos idéntico a M4-B; ninguno modificado.
Referencia y otros informes intactos. Guardarraíles y R2-1 PASS sobre los
346/346 y 78 gaps vigentes. No se repiten referencia, producto ni global
Godot: no hay cambio de sim/, sus datos/consumidores ni del monitor común.
No atribuir a esas campañas un PASS nuevo por ejecutar esta fixture.
79 UID y cuatro stashes preservados; ninguna rama privada se publica.

## 5. Intentos no finales y correcciones

- Constructor OpeningModel sin sus cinco argumentos obligatorios: error
  de parseo en la fixture, sin cuadro ni residuo. Se corrigió la llamada,
  no el motor ni el monitor. Ese intento no cuenta.
- Primeros 60 s: controles terminaron pero la ventana no activó M2-V;
  el gate falló como debía. Se anunció y extendió solo su horizonte a 300 s,
  sin tocar umbrales, leyes ni geometría para forzar un caudal.
- Capturas intermedias de 300 s: el serializador avisaba de NaN->null.
  Son historial, no la prueba final de identidad. Se añadió codificación
  explícita no finita, comparación de aberturas y causa de siembra mínima;
  se repitieron los pares completos. El análisis final también contrasta M2-V.
- Un testigo Decimal se transcribió mal: 1 failed / 14 passed. Se corrigieron
  los dos literales a los resultados de la cuenta independiente; el analizador
  y el motor no se ajustaron. Focal final completa verde.

## 6. Retomada

La captura pasiva queda implementada y probada para el alcance anterior;
**no es una corrección física** ni autoriza M4-C/D, CO/FED o producto.
No hay consulta nueva CFAST/NIST ni ensayo experimental externo.

Siguiente gate: decidir con diseño y evidencia cómo relacionar el gas físico,
el contenido de referencia y el depósito O2 zonal, y qué política sustituiría
o conservaría M2-T/M2-V. No implementar por defecto un reparto geométrico,
50/50, un boost ni otra tasa para hacer cerrar las cuentas. Antes de tocar
la autoridad viva deberá estar cerrado ese contrato; si exige sim/, habrá
cadena R2-1 por monitor. La reserva zonal M4-D y el contraste M4-E no se saltan.

Publicación autorizada de los ocho archivos propios de esta entrega,
excluyendo UID, runs/, registros temporales y ramas privadas.
