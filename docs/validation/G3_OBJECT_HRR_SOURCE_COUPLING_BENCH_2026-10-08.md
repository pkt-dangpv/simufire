# G3-4 - Banco diagnóstico de acoplamiento térmico de la fuente HRR prescrita: implementación

Fecha: 2026-10-08. Checkpoint de entrada: `d1da9f95` (main = origin/main =
rama `codex/g3-fed-co-zonal-shareable`, árboles limpios). Trabajo hecho en
`runs/g3_shareable`.

El usuario autoriza implementar y verificar el caso diagnóstico de
acoplamiento térmico del Test016, con interruptor apagado por defecto,
parada enclavada al salir del régimen y sin cola ni relevo automático;
las correcciones documentales previas, cambios acotados en `sim/`, pruebas
y la cadena R2-1 completa. **No autoriza** activar nada en producto ni
representar la combustión real del mueble.

**Corregido el 2026-10-09.** Los dos límites de oxígeno que este informe
dejó escritos se han diagnosticado y el segundo se ha corregido:
[diagnóstico y corrección](G3_OBJECT_HRR_OXYGEN_LIMITS_2026-10-09.md). Los puntos afectados están
marcados abajo. Las cifras de la sección de verificación son las de la
entrega del 08-10; las de la corrección están en ese informe.

Implementa el único caso que dejó abierto el
[diseño del acoplamiento](G3_OBJECT_HRR_SOURCE_COUPLING_DESIGN_2026-10-08.md),
sobre la [fuente aislada](G3_OBJECT_HRR_SOURCE_IMPLEMENTATION_2026-10-08.md).

## Decisión

**Hecho y verificado: un banco diagnóstico.** Una fuente prescrita del
Test016 entrega energía a un recinto sin combustible ni fuego de sala y
debita un oxígeno equivalente. Es el primer camino real en GDScript entre
la fuente y el motor.

| Qué demuestra | Qué no demuestra |
| --- | --- |
| La energía de cada paso es la integral de la fuente, sin filtro ni topes | Ninguna temperatura: el ensayo no tiene recinto |
| El oxígeno debitado es la energía aceptada por un coeficiente declarado | El consumo experimental de oxígeno ni una estequiometría de la silla |
| El calor al gas más el término radiativo es la energía aceptada | Dónde acaba la radiación en un recinto |
| La ruta del fuego de sala no aporta calor, combustible ni especies | La combustión del mueble: no hay masa ni composición |
| Fuera del régimen no se acepta nada, queda enclavado y no hay cola | Qué haría la silla con poco oxígeno |
| Reinicio, revocación y fallo no dejan nada heredado | CO, CO₂, HCN, humo, FED ni SVV: **no evaluados** |

Con el interruptor apagado el motor es idéntico byte a byte al anterior.
CO/FED siguen OFF y NO-GO. Test021 sigue reservado y sin usar.

## Gate previo: dos formulaciones corregidas antes de programar

Registradas en el diseño y en el commit `de857b97`, **antes de que
existiera ninguna corrida acoplada**.

**Oxígeno.** `HRR / 13,1 MJ/kg` no es una reconstrucción exacta del
oxígeno que se midió. Es una **demanda equivalente prescrita**. Usarla
supone la constante genérica de la calorimetría, combustión completa (la
ecuación de NIST resta un término por el CO, del orden del 0,25 % en esta
corrida), y la expansión y la humedad que el calorímetro supuso. No
equivale al total de oxígeno que publica la base de datos, que sale de
otra regla y queda un 7 % por debajo. El banco usa el coeficiente que ya
tiene el sumidero del motor, **0,076 kg/MJ**, sin ajustarlo a ninguna
señal. La prueba verifica `O₂ debitado = energía aceptada × 0,076`: un
contrato de contabilidad, no un consumo experimental ni un cierre químico.

**Pico y paso finito.** La potencia de un paso es la energía de su
intervalo entre la duración del paso. Es una media, y su máximo no es el
pico instantáneo. El criterio A4 original exigía 621,46 kW a un paso
finito y contradecía a A2. Se demostró con un triángulo en forma cerrada
(90, 95 y 97,5 kW para un pico de 100 kW) y se partió en A4a, A4b y A4c.
Ninguna tolerancia se amplió.

## Qué se ha implementado

| Archivo | Cambio |
| --- | --- |
| [`sim/fire/PrescribedThermalSourceCoupling.gd`](../../sim/fire/PrescribedThermalSourceCoupling.gd) | **Nuevo.** El banco: arma, propone, juzga el régimen, confirma y mide. Sin `class_name` ni `@export` |
| [`sim/core/SimulationEngine.gd`](../../sim/core/SimulationEngine.gd) | +115 líneas: interruptor sin `@export`, cuatro enganches en el paso, retirada y creación en el reinicio, ignición e informe |
| [`sim/core/OxygenExchangeSystem.gd`](../../sim/core/OxygenExchangeSystem.gd) | +4 y −1 líneas: el trazador genérico de CO₂ no produce en el recinto del banco |
| [`tests/fixtures/g3_object_hrr_thermal_coupling.gd`](../../tests/fixtures/g3_object_hrr_thermal_coupling.gd) | Fixture sobre el motor real |
| [`scripts/simulation/build_g3_object_hrr_coupling_oracle.py`](../../scripts/simulation/build_g3_object_hrr_coupling_oracle.py) y su [oráculo](../../tests/fixtures/g3_object_hrr_thermal_coupling_oracle.json) | Oráculo independiente, racional exacto |
| [`tests/test_g3_object_hrr_thermal_coupling.py`](../../tests/test_g3_object_hrr_thermal_coupling.py) | Pruebas |
| [`scripts/simulation/run_g3_object_hrr_thermal_coupling_mutations.py`](../../scripts/simulation/run_g3_object_hrr_thermal_coupling_mutations.py) | Campaña de mutaciones de código |

**No se han tocado**, y lo fija una prueba por huella: `PrescribedObjectHrrSource.gd`
y sus datos, y `CombustionSystem.gd`. Tampoco escenarios, plantillas,
editor, catálogo ni autorizaciones de producto.

El interruptor es `g3_prescribed_thermal_source_enabled`, una variable del
motor **sin `@export`**, apagada por defecto. El módulo se carga por ruta
y solo con el interruptor encendido: con él apagado ni siquiera se lee.
Nada fuera del motor, del sistema de oxígeno y de la fixture lo nombra.

El banco **no integra nada**: pide el intervalo a la fuente (`propose`) y
lo confirma (`confirm`). No copia la interpolación ni tiene una segunda
ley. No usa `restore()`.

## Cómo entra en el paso del motor

| Momento | Qué hace el banco |
| --- | --- |
| Después de `_step_fire` | Propone el intervalo, juzga el régimen, pregunta al sumidero qué inventario debitaría y, si todo se cumple, escribe `room.hrr_kw = energía / dt` |
| Después del sumidero de oxígeno y **antes** del calor | Compara el débito real con el comprometido. Si difiere, el sumidero no hizo lo que dijo: retira la potencia antes de que `ThermalSystem` la lea y el banco **falla** |
| Después de `ThermalSystem` | Lee el calor que realmente depositó y lo que contó como radiado |
| Al final de la física del paso | Mide lo que hizo la ruta del fuego de sala en ese recinto |

**Propietarios excluidos, medido en cada paso y no supuesto:**

| Ruta histórica | En el recinto del banco |
| --- | --- |
| `FireModel`, curva `α·t²`, reloj `fire_time_s` | No existen: `room.fire` es nulo y `fire_time_s` vale 0 toda la corrida |
| Filtro, topes, decaimiento, realimentación | No actúan: la potencia de cada paso es la del oráculo |
| Combustible | `fuel_consumed_MJ` = 0 en cada paso y en total |
| Depósito de inquemados | 0 toda la corrida, también al rechazar energía |
| CO, CO₂, HCN y humo generados | 0 en cada paso; inventarios del recinto sin cambio |
| Trazador de CO₂ | No produce: se queda en su valor ambiente, salvo redondeo de 2 · 10⁻¹⁹ |
| Sumidero de oxígeno | **Se conserva**: es quien debita |
| `ThermalSystem` | **Se conserva**: es quien deposita el calor |

## Caso base y reglas del régimen

Un recinto de 2000 m³ (20 × 20 × 5 m) con un hueco de 5 m² al exterior,
sin combustible, sin objetos y sin fuego de sala. Una fuente Test016.

| Regla | Qué juzga | Valor del caso |
| --- | --- | --- |
| R1 | El sumidero debitaría el inventario de sala, con el coeficiente declarado, y puede con toda la demanda del paso | Coeficiente 0,076 kg/MJ |
| R2 | El oxígeno de sala y el de la capa inferior no bajan más de `δ` desde la ignición | `δ = 0,01` |
| R3 | La interfaz de la capa caliente queda a esa altura o más | 0,3 m |
| R4 | Ni fuego de sala, ni combustible, ni supresión en el recinto | — |

`δ` y el criterio de capa son **hipótesis del banco**, declaradas antes de
ejecutar. No son límites físicos validados de la silla. El motor debe
además ser el declarado: modo de oxígeno histórico, diagnóstico de calor
encendido, modificadores del reparto neutros; si no, el caso no arma.

## Resultados dentro del régimen

Tres pasos de tiempo declarados antes de ejecutar. El de 0,7 s no es un
número binario y no divide el soporte; el de 2,5 s tampoco lo divide.

| Paso | Pasos | Energía aceptada, kJ | Rechazada | O₂ debitado, kg | Mayor potencia de paso | Paso | Estado |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1,0 s | 3768 | 115 093,654 999 999 85 | 0 | 8,747 117 78 | 621,125 kW | 1142 | `completed` |
| 0,7 s | 5383 | 115 093,654 999 999 55 | 0 | 8,747 117 78 | 621,274 kW | 1632 | `completed` |
| 2,5 s | 1508 | 115 093,655 | 0 | 8,747 117 78 | 619,662 5 kW | 457 | `completed` |

El oráculo da 115 093,655 kJ. Las tres potencias máximas y sus pasos son
las del oráculo de cada `dt`; ninguna es 621,46 kW, que es el pico
instantáneo y se lee de la fuente (A4a). El paso de mayor potencia es el
que contiene los 1143 s: no hay retraso.

**Balance por paso.** En cada uno de los 10 659 pasos de las tres
corridas se comprueba, con la tolerancia del módulo (10⁻⁹ más 10⁻¹²
relativo):

| Identidad, leída donde el motor la escribe | Peor residuo de un paso |
| --- | --- |
| `room.hrr_kw × dt` = integral independiente del intervalo | 2,3 · 10⁻¹³ kW |
| O₂ del acumulador del sumidero = energía × 0,076 | 2,8 · 10⁻¹⁷ kg |
| calor al gas + término radiativo, de `ThermalSystem` = energía | 4,5 · 10⁻¹³ kJ |

**Balance acumulado**, con χ = 0,35:

| Energía | kJ |
| --- | --- |
| Programada | 115 093,655 |
| Aceptada | 115 093,655 |
| Rechazada | 0 |
| Calor aportado al gas | 74 810,876 |
| Término radiativo contabilizado | 40 282,779 |

**Último paso.** Con 0,7 s el último intervalo dura 0,6 s y con 2,5 s
dura 0,5 s. Su energía se reparte sobre el paso completo, así que
`potencia × dt` es exactamente esa energía. Después del soporte la
potencia es cero, no hay débito y la fuente no se reabre.

### Cuatro fracciones radiativas

La fracción es un dato del caso. En la fuente sigue siendo `null`.

| χ | Clase | Energía aceptada | O₂ debitado | Calor al gas | Término radiativo |
| --- | --- | --- | --- | --- | --- |
| 0,35 | Supuesta: valor del motor y de CFAST | 115 093,655 kJ | 8,747 kg | 74 810,876 kJ | 40 282,779 kJ |
| 0,52 | Estimación del ensayo entero, al aire libre | 115 093,655 kJ | 8,747 kg | 55 244,954 kJ | 59 848,701 kJ |
| 0,4264 | Sensibilidad | 115 093,655 kJ | 8,747 kg | 66 017,721 kJ | 49 075,934 kJ |
| 0,6136 | Sensibilidad | 115 093,655 kJ | 8,747 kg | 44 472,188 kJ | 70 621,467 kJ |

La energía aceptada y el oxígeno son idénticos **bit a bit**, paso a paso,
en las cuatro. Solo cambia el reparto. **Ninguna es una fracción medida
dentro de un recinto.**

El término radiativo es energía que `ThermalSystem` cuenta como radiada.
**No es radiación depositada en paredes**: con la configuración por
defecto del motor no se deposita en ningún sitio. Su destino no se modela
y no se ha inventado un cierre térmico del recinto.

### Lo que el banco mide y no usa

- **Segundo número de oxígeno.** En un recinto con hueco al exterior, el
  motor escribe sobre su número de la capa superior la misma demanda que
  ya debitó de la sala: 8,747 kg en la corrida, en kilogramos de la base
  de ese número. Los tres números de oxígeno del motor no forman una
  partición conservada. El banco lo mide, lo informa aparte y no lo usa
  ni lo corrige. **El diseño decía 9 %; ese valor es el de la otra rama
  del sumidero. Queda corregido aquí.**
  **Corregido el 2026-10-09:** aquí se llamaba a esto «doble uso
  histórico del oxígeno» y se hablaba de «8,747 kg más». No es un
  segundo consumo: es la misma demanda escrita otra vez sobre un número
  solapado, y las dos cifras no se suman. Ver [el diagnóstico](G3_OBJECT_HRR_OXYGEN_LIMITS_2026-10-09.md).
- **Diagnósticos, no valores validados.** En el caso base el oxígeno de
  sala baja como mucho 0,0029 (hasta 0,2061), la interfaz baja hasta
  1,02 m y la capa superior llega a 27,9 °C con χ = 0,35 y a 24,7 °C con
  0,6136. No hay con qué contrastar ninguna de estas cifras.
- El diagnóstico de calor del motor avisa de su propio residuo en el
  recinto pequeño. No es una identidad del banco y no se juzga.

## Salida del régimen

Al fallar una regla no se acepta nada, el estado pasa a
`outside_declared_regime` con su instante y su causa, y queda enclavado
hasta un reinicio. El reloj sigue: cada intervalo se confirma con cero.

| Caso | Sale en | Causa | Energía aceptada |
| --- | --- | --- | --- |
| 60 m³ con una rendija de 0,04 m² | 800 s | Capa caliente por debajo de 0,3 m | 2 650,24 kJ, el 2,3 % |
| El mismo, juzgado solo por el oxígeno | 1005 s | Oxígeno de sala 0,0101 por debajo del inicial | 9 924,80 kJ, el 8,6 % |
| 60 m³ estanco | Primer paso | El sumidero debitaría por otra ruta | 0 |
| Coeficiente declarado distinto del sumidero | Primer paso | No es el coeficiente del sumidero | 0 |
| `δ = 10⁻⁹` | A los pocos pasos | Oxígeno | lo aceptado hasta entonces |
| Criterio de capa por encima del techo | Primer paso | Capa | 0 |

Los dos primeros salen **antes del pico** (1143 s). El diseño estimó
994 s para la salida por oxígeno con una cuenta de escala; el banco da
1005 s, y además muestra que en ese recinto la capa falla antes. La cifra
del diseño era orientativa y no se ha impuesto.

En todos, después de salir:

- potencia cero, ningún débito de oxígeno y ningún calor depositado;
- aceptada + rechazada = 115 093,655 kJ: el reloj llega al final;
- el oxígeno debitado y el calor contados corresponden solo a lo aceptado;
- la energía rechazada **no** pasa al depósito de inquemados ni crea un
  fuego de sala;
- **recuperar el oxígeno no reactiva nada.** Se restituyó el oxígeno del
  recinto, al final de la corrida y a mitad: ningún intervalo vuelve a
  aceptarse.

**Recinto estanco. Corregido el 2026-10-09.** El motor debita ahí sobre
el número de la capa inferior. En la entrega del 08-10 el banco lo
detectaba después del sumidero: retiraba la potencia y no depositaba
calor, pero las escrituras del sumidero quedaban hechas. La cifra que
publicaba, 8,5 · 10⁻⁵ kg, era además la suma de dos escrituras sobre
números con bases distintas. Ahora el banco pregunta la ruta **antes**
de escribir la potencia y rechaza el intervalo sin que el sumidero haya
escrito nada: el recinto queda idéntico al de un motor con el
interruptor apagado. Ver [el diagnóstico](G3_OBJECT_HRR_OXYGEN_LIMITS_2026-10-09.md).

## Segundos propietarios y fallo

Introducidos a mitad de una corrida que estaba entregando:

| Intruso | Resultado |
| --- | --- |
| Un `FireModel` en el recinto | Sale con causa `the_room_has_a_room_fire` |
| Un objeto combustible frío | Sale con causa `the_room_has_fuel` |
| Una carga de sala | Sale con causa `the_room_has_fuel` |
| Supresión dirigida al recinto | Sale con causa `suppression_in_the_room` |
| Un modificador del reparto de calor cambiado | **Falla** y el motor deja de avanzar |

En los cuatro primeros el intervalo se rechaza entero y nada más se
cuenta como del banco. El último es distinto: el motor era el declarado
al armar, y `ThermalSystem` deposita después otra cosa. Ese calor ya está
puesto y no se puede deshacer, así que el banco pasa a `failed`, lo deja
escrito y la simulación se detiene.

## Configuración inválida

**Controles de configuración**, aparte de los mutantes de código. En
todos: fallo explícito con sus motivos, el motor no avanza, y en el
recinto no queda potencia, oxígeno debitado ni rastro del banco. No hay
vuelta a la ruta histórica.

| Qué es inválido | Controles |
| --- | --- |
| El caso: tabla con la misma energía y otro contenido, fracción dentro de la fuente, identidad, recinto, campos, esquema, coeficiente, clase y origen de la fracción, régimen presentado como validado | 21 |
| El motor real: modo de oxígeno explícito o histórico, diagnóstico de calor apagado, modificadores no neutros, fin por extinción, seguimiento de masa de oxígeno | 10 |
| El recinto: carga, tope de potencia, objeto frío, fuego de sala, inquemados | 5 |
| Cada una de las 12 condiciones que el banco pide al motor, cambiada y también omitida, sobre el propio banco | 24 |
| Cada uno de los 4 enganches ausente, y armar dos veces el mismo banco | 5 |

La condición de transporte autoritativo se prueba solo de la segunda
forma: un contrato anterior prohíbe que una fixture nombre ese
interruptor, y se ha respetado.

## Ciclo de vida, sobre el mismo motor

`SimulationEngine` posee una instancia nueva por corrida. Se retira
**por encima** de las guardas de `reset_simulation` y se crea **por
debajo**, con el recinto ya reiniciado.

| Situación | Comprobado |
| --- | --- |
| Reinicio tras una corrida que entregaba | Instancia nueva; la anterior queda retirada e inactiva; reloj y contadores a cero; el recinto sin potencia |
| Propuesta de la corrida anterior | La instancia nueva la rechaza; la retirada no confirma nada |
| Propuesta adelantada por un paso | Rechazada |
| Revocación | Sin instancia, informe inactivo, sin fallo; el mismo motor sigue con el recinto frío |
| Reinicio sin edificio | Retirada, informe inactivo, la potencia que escribió se quita del recinto, el reloj no avanza |
| Edificio no preparado | Lo mismo, con el edificio enlazado |
| Otra tabla | Instancia nueva con su identidad y su total: un triángulo da 1000 kJ, 90 kW con paso de 4 s y 0,076 kg de O₂ |
| Caso rechazado y después uno válido | El fallo no se hereda |
| Reinicio sin ignición | La fuente queda armada y su reloj espera; la ignición lo arranca sin crear fuego de sala |

## Lo que dice el informe del banco

- `not_evaluated`: CO, CO₂, HCN, humo y visibilidad, irritantes, FED,
  SVV, masa de combustible, composición del gas y temperaturas como
  valores validados.
- Los ceros que el motor guarda para esas magnitudes sirven para
  comprobar que no se generó nada. **No son ceros medidos ni una
  condición segura.**
- El estado del gas es diagnóstico e incompleto: se debita oxígeno y no
  se añaden productos ni masa de combustible.
- Solo una corrida `completed` es una reproducción de la entrada.

## Resultados de la verificación

Todo secuencial, un Godot cada vez y siempre bajo el monitor. Mínimo de
6 GiB disponibles sin rebajar; `TEMP`, `TMP` y `basetemp` fuera del
repositorio, y `APPDATA` también salvo en las pruebas de pytest, cuyo
lanzador ya existente fija el suyo bajo `runs/`.

### Fixture y pruebas

- Fixture sobre el motor real: **147 317 comprobaciones en 11 grupos, 0
  fallos**, sin errores de script. El número queda fijado en la prueba.
- [`tests/test_g3_object_hrr_thermal_coupling.py`](../../tests/test_g3_object_hrr_thermal_coupling.py):
  **22 passed**. Vuelve a juzgar fuera de GDScript las tres corridas, las
  cuatro fracciones y las salidas del régimen contra el oráculo.

### Mutaciones de código

Declaradas antes de ejecutar, cada una con el defecto que inyecta y el
grupo de la fixture donde debe verse. Mutan en el árbol de trabajo uno de
los tres archivos del acoplamiento y lo restauran, verificado por
SHA-256, tras cada mutante.

| Campaña | Declarados | Detectados | Donde se esperaba | Inválidos | Supervivientes |
| --- | --- | --- | --- | --- | --- |
| Final, sobre el código final (`…_220937`) | 36 | **36** | **36** | **0** | **0** |

Por familia: potencia del paso 5, oxígeno 5, régimen y enclavamiento 11,
calor 2, armado 5, ciclo de vida 6, informe 2. Por archivo: 29 en el
banco, 6 en el motor y 1 en el sistema de oxígeno. Una muerte es una
fixture que llegó al final e informó de fallos; un error de sintaxis o
de script se habría anotado como inválido y no hubo ninguno.

Lo que no se cuenta:

- Una primera campaña completa (`…_191205`) dio también 36 de 36, pero
  es **anterior a la última corrección** de la fixture y del banco, así
  que no vale. Esperó más de dos horas a la memoria.
- Antes de ella, un intento se detuvo tras el control porque la memoria
  bajó de 6 GiB. No ejecutó ningún mutante.

Los controles de configuración inválida y de segundos propietarios viven
en la fixture y se cuentan aparte, en sus secciones.

### Regresiones de G3 y contratos afectados

Los módulos `tests/test_g3_*.py` más el contrato de fixtures que fallan
cerrado: **1511 passed, 18 skipped**, los omitidos de siempre.

El cambio del motor tocó cuatro contratos anteriores. Tres se adaptaron,
de forma estrecha, y uno se respetó cambiando la fixture:

| Contrato | Qué decía | Qué se hizo |
| --- | --- | --- |
| Aislamiento de la fuente | Nada del motor la nombra | Ahora exactamente un módulo la carga, el banco; el motor sigue sin nombrarla |
| Composición sensible de D1 | El motor no nombra ningún «Prescribed» | El motor nombra una sola vez el banco, por ruta; `CombustionSystem` sigue sin nombrar ninguno |
| Auditor del diseño | Ningún consumidor de la fuente | Un consumidor permitido y declarado; cualquier otro anula el GO |
| Red de presiones | Ninguna fixture nombra su interruptor | **Respetado**: ese control se hace sobre el propio banco, sin tocar el interruptor |

### Identidad con el interruptor apagado

Nueve casos de control (`sofa_vent`, `o2_closed`, `o2_reopen_300` y otros
seis), corridos **antes de tocar `sim/`** y otra vez con el código final.
Siete archivos por caso, comparados byte a byte: registros, trazas,
instantáneas, eventos y escenario.

**9 de 9 idénticos.** Línea base en
`runs/g3_balance_identity_off_ledgeroff_20261008_184303/`; corrida final
en `runs/g3_balance_identity_off_ledgeroff_20261008_224311/`.

### Referencia, guardarraíles, producto y global

| Paso | Resultado |
| --- | --- |
| Referencia completa monitorizada | 18/18 corridas sanas, salida 0, informe nuevo en todas; 51 min |
| Comprobaciones requeridas | **346/346 PASS** |
| Huecos conocidos | **78**, los mismos |
| Guardarraíles, con R2-1 | **ALL GUARDRAILS PASS**, también en una pasada aparte |
| `check_product.py` | **168/168 PASS** |
| Global, `python -m pytest tests -q -p no:cacheprovider` | **4330 passed**, 49 skipped, 2 xfailed, 42 subtests; salida 0; 690,38 s |

Ninguna ciencia se ha rebaselineado.

Corpus `sim/validation/reports/` frente a `d1da9f95`: 382 archivos
versionados, 381 idénticos byte a byte, ninguno distinto solo en
LF/CRLF. En `reference_checks.json` cambia una línea de 19 269,
`generated_at`, de `2026-10-08T13:05:15Z` a `2026-10-08T21:50:18Z`.

La global recoge 26 pruebas más que la suma de las fases anteriores: las
22 del banco y 4 del contrato genérico de fixtures.

Los ocho archivos de código, datos y pruebas de la entrega tienen el
mismo SHA-256 antes de la cadena y después de la global.

### Lo que no salió limpio

- **Dos contratos anteriores fallaron**, encontrados con una global preliminar
  y corregidos antes de la cadena final: el contrato de D1 sobre
  «Prescribed» y el de la red de presiones, arriba. Además, armar dos
  veces el mismo banco lo dejaba en fallo; ahora se rechaza sin tocarlo.
  Toda la cadena se repitió después sobre el código final.
- **Una global no cuenta.** La primera pasada de la cadena final dio
  4329 passed y un fallo: un Godot agotó su tiempo porque el equipo
  estuvo suspendido unas ocho horas y media en mitad de la prueba. Se
  repitió entera: 4330 passed.
- **Memoria.** Durante varias horas hubo menos de 6 GiB disponibles. El
  umbral no se rebajó: la campaña y la cadena esperaron.

### Salud de los procesos

- Todo Godot se lanzó por el monitor: uno cada vez, sin cuadros de error,
  sin procesos ajenos y sin residuos al terminar.
- No se terminó ningún proceso ajeno.
- Memoria disponible antes de cada corrida de referencia: entre 7,73 y
  7,86 GiB.
- El único tiempo agotado es el de la suspensión del equipo, ya contado.

## Límites

- **No es la combustión del mueble.** No hay masa, composición ni
  especies. El objeto no responde al recinto.
- **No cierra la composición del gas.** 8,75 kg de oxígeno desaparecen
  sin productos a cambio.
- **No valida ninguna temperatura.** El ensayo no tiene recinto; las que
  aparecen son diagnósticos del motor.
- El coeficiente de oxígeno es una demanda equivalente. No se ha medido
  en esta silla.
- `δ` y el criterio de capa son hipótesis. Un recinto que las cumple no
  es por eso el régimen del ensayo: el motor no representa el aire libre.
- El motor lleva tres números de oxígeno que no forman una partición. El
  banco contrata con uno y deja escrito lo que pasa en otro.
- El penacho arrastra con su propia fracción convectiva, 0,70, sea cual
  sea χ. Es una incoherencia del motor que se documenta y no se corrige.
- Un único recinto, sin otros objetos, sin propagación y sin supresión.
- La identidad con el interruptor apagado está probada en los casos que
  se listan arriba, no en todas las configuraciones posibles.

## Siguiente gate recomendado

Del usuario. El banco deja probado el camino de propiedad, oxígeno
equivalente y energía. Lo que sigue necesita datos, no código:

1. **La serie numérica de masa** del Test016, que NIST publicó solo como
   figura. Sin ella no hay objeto que arda.
2. **Un ensayo en recinto** con el mismo objeto, para tener con qué
   contrastar una temperatura.

Mientras tanto, un gate posible y **no autorizado**: la emisión prescrita
de CO₂ y CO al aire libre, con las series del conducto de la misma
corrida. No cambiaría el NO-GO de CO/FED.

No se activa producto, no se añaden emisiones y la silla no es un objeto
combustible validado.

Reproducir:

```text
python -m scripts.simulation.build_g3_object_hrr_coupling_oracle --check
python -m pytest tests/test_g3_object_hrr_thermal_coupling.py -q -p no:cacheprovider
python scripts/simulation/run_g3_object_hrr_thermal_coupling_mutations.py
```
