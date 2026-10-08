# G3-4 - Acoplamiento de la fuente prescrita de HRR: diseño y viabilidad

Fecha: 2026-10-08. Checkpoint de entrada: `60754428` (main = origin/main =
rama `codex/g3-fed-co-zonal-shareable`, árboles limpios). Trabajo hecho en
`runs/g3_shareable`. Fase **offline**: sin cambios en `sim/`, escenarios,
perfiles ni producto, y sin Godot.

El usuario autoriza el diagnóstico y el diseño del acoplamiento
experimental, la revisión de bibliografía, pruebas offline y documentación.
**No autoriza** cambios en la física, integrar la fuente ni activarla en
producto. Este documento no implementa nada.

Parte de la
[fuente aislada del 08-10](G3_OBJECT_HRR_SOURCE_IMPLEMENTATION_2026-10-08.md)
y de la [selección del 07-10](G3_OBJECT_FIRE_SOURCE_SELECTION_2026-10-07.md).
Lo aprobado sigue siendo lo mismo: reproducir el HRR medido de una corrida
de una silla al aire libre. Nada de lo que sigue lo convierte en una
predicción.

## Decisión

**Recomendación: una fuente térmica prescrita, sola en su recinto, fuera de
la ruta del fuego de sala.** No es la combustión del mueble y no debe
llamarse así. Entrega calor y debita oxígeno; no consume combustible, no
produce especies y se invalida al salir del régimen del ensayo.

**La alternativa de representar el objeto que arde es NO-GO**: exige masa,
composición y rendimientos que el Test016 no tiene.

Una decisión por observable. Un GO en una no aprueba las demás, y todos
los GO son de **diseño**: implementar sigue sin autorizar.

| Observable | Decisión |
| --- | --- |
| Energía entregada por paso igual a la integral de la tabla | **GO de diseño**, como fuente térmica sola en su recinto |
| Potencia aplicada sin filtro ni topes | **GO de diseño**, fuera de la ruta del fuego de sala |
| Oxígeno debitado por energía aceptada | **GO de diseño**, como demanda equivalente prescrita |
| Respuesta al oxígeno escaso | **NO-GO** como modelo; solo una cota de conservación |
| Indicador de validez del régimen | **GO de diseño** como hipótesis declarada, no como límite validado |
| Reparto convectivo y radiativo | **GO parcial**: 0,52 ± 18 %, del ensayo entero y al aire libre |
| Radiación a superficies del recinto | **NO-GO**: no se midió en un recinto |
| Masa de combustible | **NO-GO**: no hay serie numérica de masa |
| Especies y humo | **NO-GO**: solo totales del ensayo, al aire libre |
| FED y SVV | **NO-GO** |
| Otros objetos en el mismo recinto | **NO-GO**: el motor tiene un fuego por recinto |
| Flashover, propagación y supresión | **NO-GO**, excluidos del primer caso |
| Restaurar el estado del motor | **NO-GO**: el motor reinicia, no restaura |
| Validación externa de temperaturas | **NO-GO**: el ensayo no tiene recinto |
| Activación en producto | **NO-GO** |

CO/FED siguen OFF y NO-GO. Test021 sigue reservado y sin usar. B neto no
se reabre; no se usan heptano, Sandia ni el ensayo de cono.

## Ruta real del motor

Leída en el código de `60754428`, función a función. Los 34 hechos de los
que depende el diseño están fijados por un auditor: si el motor cambia en
cualquiera de ellos, la prueba falla y obliga a releer este documento.

### Orden de un paso

`SimulationEngine.step` (`sim/core/SimulationEngine.gd`), con los
interruptores por defecto:

| Orden | Llamada | Qué hace para el fuego |
| --- | --- | --- |
| 1 | `sim_time_s += dt` | Reloj de la simulación |
| 2 | `_step_pool_fires` | Sube el techo de potencia de un charco |
| 3 | `_step_fire` → `CombustionSystem.step_room_fire` | Decide el HRR de cada recinto, debita combustible y genera especies |
| 4 | `_step_co_oxidation` | Oxida CO; apagado por defecto |
| 5 | `_step_oxygen` → `OxygenExchangeSystem.step` | Debita oxígeno según el HRR del paso |
| 6 | `thermal_system.step` | Reparte el HRR entre gas, paredes y nada |
| 7 | `_step_suppression` | El agua multiplica el HRR ya aplicado |
| 8 | `_step_gas_exchange`, `_step_hvac` | Transporte |
| 9 | `_step_passive_fuel`, `fire_spread_system.step` | Calienta objetos fríos y propaga entre recintos |
| 10 | `_clamp_rooms` | Topes finales |

Con un modo de oxígeno explícito (`upper`, `lower`, `interface`) el paso 5
va antes del 3. El diseño exige el orden por defecto y lo comprueba.

### Quién decide el HRR de sala

Un único fuego por recinto, `room.fire` (`FireModel`). No lo decide ningún
objeto. Entre la curva ideal y la potencia aplicada hay esta cadena, toda
en `CombustionSystem.step_room_fire` salvo los dos últimos:

| Paso | Qué hace |
| --- | --- |
| Curva ideal | `FireModel.compute_hrr_kw`: `α·t²`, con tope `max_hrr_kw` |
| Reloj del fuego | `fire_time_s` avanza `dt` por un factor de oxígeno, no por `dt` |
| Decaimiento | Reduce la curva cuando queda menos del 15 % del combustible |
| Realimentación | Multiplica por la temperatura de la capa superior |
| Factor de oxígeno | Suavizado con constantes de 14 s y 32 s; umbral de llama en 0,08 |
| Escala de combustible | Recorta si la demanda supera lo que queda |
| Corte por oxígeno | Anula todo bajo el límite de extinción elegido |
| Depósito de inquemados | Parte de la pirólisis no arde, se guarda y se libera después |
| Tope de ventilación | `kawagoe_limit_kw` |
| **Filtro** | `_smooth_state_value`: subida de 6 a 10,8 s, bajada de 20 s |
| Multiplicador y backdraft | Factor global y envolvente explosiva |
| Flashover | `SimulationEngine`: `room.hrr_kw *= flashover_hrr_multiplier` |
| Supresión | `SimulationEngine`: `room.hrr_kw *= hrr_factor` |

### Reparto entre objetos

`_sync_explicit_objects_from_active_fire` reparte el HRR **ya decidido**
entre los objetos candidatos, por pesos. El campo `hrr_curve` de un objeto
es uno de esos pesos: no fija su potencia. Con el interruptor G3 de
propiedad encendido, `_g3_allocate_owned` reparte con topes, pero la
potencia total sigue viniendo del fuego de sala.

### Combustible y oxígeno

- **Combustible.** `fire.remaining_fuel_MJ` baja con la **demanda de
  pirólisis**, no con el calor liberado, y los objetos se debitan por su
  parte del reparto. Todo en MJ: no hay kilogramos.
- **Oxígeno.** `OxygenExchangeSystem.step` debita
  `room.hrr_kw × 0,076 kg/MJ × dt`. La condición es `room.hrr_kw > 0`, no
  que exista un fuego: si no lo hay usa el mismo 0,076. El débito de un
  paso se recorta al 5 % del oxígeno del recinto, y el número de oxígeno
  del recinto se usa como fracción de masa (`air_mass_kg * room.o2`, con
  ambiente 0,209).

### Especies

En `step_room_fire`, a partir de rendimientos por MJ: humo, CO (con una ley
exponencial de la razón de equivalencia), HCN, irritantes y CO₂, con un
tope de carbono de 0,027 kg/MJ genérico. Además `OxygenExchangeSystem`
mantiene un trazador de CO₂ de la capa superior que produce
`room.hrr_kw × rendimiento` **para cualquier recinto con potencia**.

### Energía a las zonas

`ThermalSystem.step` lee `room.hrr_kw`:

- **Convección:** `hrr × (1 − χ) × dt` entra en `upper_energy_kj`.
- **Fracción radiativa χ:** la del recinto si algún objeto la declara; si
  no, la del motor, 0,35. Se desplaza hacia 0,50 cuando el oxígeno baja de
  0,12, y llega a ese valor en 0,06.
- **Radiación:** `hrr × χ × hrr_rad_wall_fraction` calienta las paredes.
  **Por defecto esa fracción es cero: la parte radiativa no se deposita en
  ningún sitio y sale del dominio sin anotarse.**
- **Penacho:** el arrastre usa su propia fracción convectiva, 0,70, que no
  depende de χ.

### Inicio, reinicio y restauración

- `_ready` y `reset_simulation` resuelven la autorización experimental y
  llaman a `ignite_room`, que crea el `FireModel` si el recinto tiene algo
  que pueda arder. `reset_simulation` además reinicia recintos y objetos.
- `reset_simulation` retira lo que aportó la corrida anterior **por encima**
  de sus dos guardas (sin edificio, o motor no preparado) y solo aplica una
  autorización nueva por debajo. Es el arreglo de F2.2D4B2B.
- **El motor no tiene restauración de estado.** Solo reinicia.

### Rutas

| Ruta | Cómo entra | Fuego |
| --- | --- | --- |
| Normal | Escena, `_ready`, valores `@export` por defecto | Fuego de sala histórico |
| Validación | `sim/validation/CaseRunner.gd`, `--validation-case`, `engine_overrides` del caso | El mismo, con parámetros del caso; un caso usa `fire_o2_independent` |
| Experimental | 84 interruptores `@export` apagados por defecto; autorización experimental por escenario; interruptores G3 | Variantes del fuego de sala |
| Aislada | Módulos de `sim/fire/` sin `class_name` | Solo fixtures; nada del motor los carga |

`fire_o2_independent` es lo más parecido que existe a un fuego prescrito:
ignora el límite de oxígeno. Sigue pasando por el filtro, el decaimiento,
la realimentación y el tope de ventilación, consume combustible y genera
especies con rendimientos genéricos. No reproduce una curva.

### Propietarios que habría que sustituir o excluir

| Dueño de hoy | Qué posee | En un recinto con fuente prescrita |
| --- | --- | --- |
| `FireModel` y `step_room_fire` | HRR, combustible, especies | **Excluido**: el recinto no tiene fuego de sala |
| Reparto entre objetos | Potencia por objeto | **Excluido**: no hay objetos combustibles |
| Depósito de inquemados y backdraft | Energía retenida | **Excluido** |
| `_try_trigger_flashover` | Multiplica el HRR | No actúa sin fuego de sala; se comprueba |
| Supresión | Multiplica el HRR | **Excluida** del primer caso; si actúa, invalida |
| Sumidero de oxígeno | Débito por HRR | **Se conserva**, con la constante declarada |
| Trazador de CO₂ | CO₂ por HRR genérico | **Excluido**: sería una especie inventada |
| `ThermalSystem` | Calor al gas y a paredes | **Se conserva**, con χ declarada |
| `FireSpreadSystem` | Propagación entre recintos | No parte de un recinto sin fuego de sala |
| `_step_passive_fuel` | Autoignición de objetos | Sin efecto: no hay objetos |
| Rama sin fuego de `step_room_fire` | Pone `hrr_kw` a cero y marca `EXTINGUISHED` en cada paso | El propietario escribe **después** y pone su propia etiqueta de régimen |
| Fin de corrida por extinción | Solo cuenta recintos con fuego de sala | Con `auto_finish_on_extinction` daría la corrida por extinguida; el primer caso lo exige apagado, que es su valor por defecto |

## Alternativas

| | Alternativa | Qué pasa | Decisión |
| --- | --- | --- | --- |
| A0 | Dejar la fuente aislada | Nada cambia | Válida si no se autoriza más |
| A1 | Poner la tabla en `hrr_curve` de un objeto | Es un peso del reparto; la potencia la decide el fuego de sala | **Rechazada** |
| A2 | Usar la tabla como curva ideal del fuego de sala | Pasa por toda la cadena de arriba | **Rechazada** |
| A3 | Fuente térmica prescrita, sola en su recinto | Calor y oxígeno; sin combustible ni especies | **Recomendada** |
| A4 | Objeto que arde, con masa y especies | Exige datos que el ensayo no tiene | **NO-GO** |

**Por qué no A2.** Se ha calculado qué haría el filtro del motor con la
tabla del Test016 en la lectura más favorable: sin factor de oxígeno, sin
topes y sin realimentación.

| Constante de subida | Pico aplicado | Retraso | Energía frente a la tabla | Mayor separación |
| --- | --- | --- | --- | --- |
| 10,8 s | 582,7 kW, el 93,8 % | 6 s | **+5,55 MJ** (+4,8 %) | 174 kW |
| 6,0 s | 605,8 kW, el 97,5 % | 4 s | **+8,88 MJ** (+7,7 %) | 185 kW |

El filtro sube más deprisa de lo que baja, así que rectifica el ruido de
la señal y **añade energía**. Con la subida rápida añade más que la
incertidumbre expandida del calor total del ensayo, 6,4 MJ. El resultado
no depende del paso (0,05, 0,1 y 1 s dan lo mismo dentro de 0,02 MJ). Una
curva que pasa por ahí no puede declararse reproducida.

**Por qué A3 y no más.** Es lo único que el ensayo sostiene: calor en el
tiempo y, por cómo se midió, oxígeno consumido. Lo que el ensayo no da no
se rellena.

## Contrato A: propiedad y ausencia de doble contabilización

**Dueño de la energía:** un propietario nuevo, a nivel de recinto, que
posee la instancia de la fuente. El recinto queda en un modo exclusivo,
`prescribed_thermal_source`.

**Condiciones del recinto, todas obligatorias.** Si falta una, la corrida
no se simula:

- sin carga de sala (`fuel_energy_MJ = 0`, `max_hrr_kw = 0`);
- sin objetos combustibles, explícitos ni proxy;
- sin fuego de sala: `ignite_room` no crea `FireModel` porque no hay nada
  que pueda arder, y `room.fire` vale `null` toda la corrida;
- sin supresión dirigida a ese recinto.

La silla que se vea en pantalla es atrezo. No es inventario combustible.

| Riesgo | Cómo se evita |
| --- | --- |
| Sumar fuente y fuego de sala para el mismo combustible | El recinto no tiene fuego de sala ni combustible. Si aparece un `FireModel`, fallo explícito |
| Repartir otra vez el calor ya asignado | No hay objetos entre los que repartir |
| Suavizar o limitar una curva declarada reproducida | El propietario escribe `room.hrr_kw` después de `_step_fire` y nada de la cadena la toca. Se comprueba paso a paso contra la media del intervalo |
| Consumir combustible histórico mientras otro entrega calor | `fuel_consumed_MJ_total` del recinto debe quedar en cero |

**Fuentes externas de calor.** El motor solo tiene una: el aire de
impulsión de HVAC, que mezcla temperatura sin pasar por `hrr_kw` ni
debitar oxígeno. La fuente prescrita no se modela así porque el oxígeno
que consume es parte de lo que el ensayo midió.

**Convivencia con otros objetos.** No cabe sin romper los contratos
existentes. El motor tiene un fuego por recinto y las cláusulas C2, C3 y
C5 a C9 de propiedad fallan hoy con los interruptores apagados. Dos
escritores de `room.hrr_kw` necesitarían una regla de composición que no
existe. **El primer caso se limita a un objeto prescrito solo en su
recinto.** Otros recintos pueden existir si no contienen combustible.

## Contrato B: oxígeno y salida del régimen

Dos cosas distintas:

1. **Reproducción prescrita dentro del régimen del ensayo.** Es lo que se
   diseña.
2. **Un modelo de combustión que responde al oxígeno y a la ventilación.**
   No queda validado por implementar lo primero, y aquí no se diseña.

### Qué demanda de oxígeno se justifica

> **Corregido el 08-10, antes de implementar.** La primera versión decía
> que dividir el HRR por 13,1 MJ/kg «devuelve el oxígeno consumido». Es
> demasiado. Lo que sigue lo sustituye.

El HRR del ensayo es **calorimetría por consumo de oxígeno**, pero la
relación `HRR / 13,1 MJ/kg` **no es una reconstrucción exacta del oxígeno
que se midió**. Es una **demanda equivalente prescrita**: el oxígeno que
correspondería a ese calor con la constante que el calorímetro supone
para un combustible genérico.

Qué hace falta suponer para usarla, según la ecuación 12 de TN 2077:

| Hipótesis | Qué interviene en la calorimetría real |
| --- | --- |
| El calor por kg de O₂ vale 13,1 MJ/kg | Es la media de combustibles genéricos, con desviación típica de 0,35 MJ/kg. **No se midió en esta silla** |
| Combustión completa | La ecuación resta un término por el CO medido. En esta corrida ronda el 0,25 % del calor, según la reconstrucción aproximada de abajo |
| Expansión de los productos | Un factor de expansión supuesto (1,10 para hidrocarburos) convierte el caudal del conducto en aire entrante |
| Humedad del aire | Se estima con la humedad ambiente; el CSV no la trae |
| Sin corrección por hollín | La ecuación no la aplica |

Por eso **no equivale al total de oxígeno que publica la base de datos**.
Ese total sale de otra regla, la diferencia de fracción en el conducto
por el caudal, que no lleva ni el factor de agotamiento ni la expansión:
8,168 kg, un **7,0 % menos**. Ninguna de las dos cifras es «el oxígeno
exacto».

| Cantidad | Valor |
| --- | --- |
| Constante que supone la calorimetría | 13,1 MJ por kg de O₂ |
| Su incertidumbre | desviación típica 0,35 MJ/kg (2,7 %); TN 2303 la cita como ± 0,5 (3,8 %) |
| Demanda equivalente con esa constante | 0,076 34 kg/MJ; 8,786 kg en la corrida; 0,0474 kg/s en el pico |
| **Coeficiente del banco** | **0,076 kg/MJ: el que ya usa el sumidero del motor.** Equivale a 13,16 MJ/kg, un 0,44 % menos de oxígeno, dentro de la incertidumbre |
| Demanda del banco en la corrida | 8,747 kg de O₂ |

**El coeficiente no se ajusta** para acercarlo al total del conducto ni a
ninguna otra señal. Se toma el del motor para no tocar su sumidero.

**Qué comprueba la prueba y qué no.** La prueba exigirá
`O₂ debitado = energía aceptada × 0,076 kg/MJ`. Eso verifica el contrato
del banco. **No demuestra** el consumo experimental exacto, ni una
estequiometría de la silla, ni un cierre químico.

**Comprobación de coherencia, no entrada.** Una reconstrucción propia y
aproximada del balance del calorímetro, con humedad y expansión
supuestas, da entre 8,48 y 8,66 kg de oxígeno y devuelve entre el 96,3 y
el 98,3 % del calor publicado. Es coherente con la relación y **no se
usa**: no es la ecuación de NIST con sus entradas.

**No se deriva masa de combustible ni ninguna emisión para sostener este
cálculo.**

### Qué ocurre cuando el recinto deja de sostener la fuente

El ensayo se hizo con aire ambiente y arrastre libre. No hay ninguna
medida de esta silla con menos oxígeno. Por tanto **no existe ningún
umbral validado** de oxígeno, temperatura o presión, y este diseño no
inventa ninguno.

| Regla | Qué es | Procedencia |
| --- | --- | --- |
| R1. No hay calor sin su oxígeno equivalente | La energía aceptada no supera la que el inventario del sumidero permite debitar en el paso, y el débito real se compara después con el comprometido | Contabilidad del banco, con el coeficiente declarado |
| R2. El oxígeno que ve la fuente no se aparta del inicial más de `δ` | Indicador del régimen | **Hipótesis.** `δ` es una tolerancia numérica del caso, no un límite físico |
| R3. La capa caliente no envuelve la fuente | Indicador del régimen | **Hipótesis**, con la misma referencia que ya usa el motor |
| R4. Ni supresión ni fuego de sala en el recinto | Condición de propiedad | Contrato A |

El comportamiento propuesto:

- **Qué se detecta.** Al inicio de cada paso, R1 a R4 con el estado del
  recinto. Después del paso, que el oxígeno debitado es el de la energía
  aceptada.
- **Qué se acepta.** Dentro del régimen, toda la energía programada. No
  hay aceptación parcial.
- **Qué se rechaza.** Desde el primer paso en que falla una regla, toda.
- **Cómo se declara.** El estado pasa a `outside_declared_regime`, con
  instante y causa, y **queda enclavado**: no vuelve a ser válido en esa
  corrida.
- **El reloj.** Sigue avanzando: cada intervalo se confirma con cero. La
  curva no se detiene para esperar al recinto.
- **La energía rechazada.** Se anota como rechazada, sin cola. **No se
  convierte en combustible acumulado, en inquemados ni en energía química
  pendiente.** El módulo ya lo impide y el propietario no añade ningún
  depósito.
- **Transición.** **Ninguna.** No hay modelo aprobado para esta silla en
  aire viciado. El fuego de sala no toma el relevo: duplicaría el calor e
  inventaría combustible.

Seguir entregando una potencia recortada después de la salida daría
números verosímiles sin respaldo. Se descarta por eso; es la única
decisión de esta sección que cambia el alcance y queda para el usuario.

### Cuánto dura el régimen en un recinto cerrado

Cuenta de escala, no modelo: un recinto estanco, con la convención de
oxígeno del motor, y tres valores de `δ` declarados antes de calcular.

| Volumen | Demanda total sobre inventario | δ = 0,005 | δ = 0,01 | δ = 0,02 |
| --- | --- | --- | --- | --- |
| 30 m³ | 1,17 | 784 s | 872 s (4 % de la energía) | 994 s |
| 60 m³ | 0,58 | 872 s | 994 s (8 %) | 1095 s |
| 120 m³ | 0,29 | 994 s | 1095 s (16 %) | 1137 s |
| 500 m³ | 0,07 | 1140 s | 1295 s (68 %) | no se alcanza |
| 2000 m³ | 0,02 | no se alcanza | no se alcanza | no se alcanza |

El pico llega a los 1143 s. Una habitación cerrada sale del régimen
**antes del pico**, con menos del 10 % de la energía entregada, y una de
30 m³ ni siquiera contiene el oxígeno de la corrida entera. El primer caso
necesita un recinto muy grande o bien abierto.

## Contrato C: energía, masa y especies

| | Inyectar calor como fuente térmica | Representar un objeto que arde |
| --- | --- | --- |
| Energía | La integral de la tabla | Calor de combustión por masa quemada |
| Masa | Ninguna | Pérdida de masa en el tiempo |
| Oxígeno | Identidad de la calorimetría | Estequiometría del combustible |
| Especies | Ninguna | Rendimientos por régimen |
| Lo que da el Test016 | **Todo lo necesario** | Solo totales del ensayo |

**El estado del motor admite la primera sin inventar nada**: el calor
entra por `room.hrr_kw`, y ni el sumidero de oxígeno ni `ThermalSystem`
piden masa o composición.

**La segunda es NO-GO.** Hasta CFAST, que parte de un HRR prescrito,
exige el calor de combustión y la fórmula del combustible para obtener la
pirólisis y las especies. Dato mínimo que la desbloquearía:

1. la **serie numérica de masa** del Test016, que NIST midió y publicó
   solo como figura;
2. una **composición aprobada** del conjunto, o rendimientos en el tiempo
   de la misma corrida;
3. rendimientos **en recinto y con poco oxígeno** del mismo objeto, si se
   quiere algo más que aire libre.

Lo que la fuente térmica deja abierto, declarado:

- **No añade masa al gas.** La silla perdió 3,241 kg; no se inyectan.
- **Quita oxígeno y no pone productos.** 8,79 kg de O₂ desaparecen sin
  CO₂ ni agua a cambio. La composición del gas del recinto queda
  incompleta.
- **No produce CO, CO₂, HCN, humo ni irritantes.** Sus columnas no son un
  cero medido: son «no evaluado». Visibilidad, FED y SVV del recinto no se
  pueden interpretar, y el informe debe decirlo.

No se producen especies con rendimientos genéricos por comodidad. El
trazador de CO₂ del motor, que lo haría solo, se excluye.

## Contrato D: radiación y convección

Cuatro cosas que no son la misma:

| Cantidad | Qué es | ¿La da el ensayo? |
| --- | --- | --- |
| HRR calorimétrico | Calor químico total | Sí, la tabla |
| Energía depositada en el gas | Lo que calienta la capa | No |
| Radiación a superficies | Lo que reciben paredes y objetos | No en un recinto |
| Energía que sale del dominio | Lo que no se queda | No |

**Qué ofrece el ensayo.** Cinco radiómetros de gran ángulo a 1 m de
altura, cuatro a unos 3 m y uno a 2 m. TN 2303 integra cada uno como
fuente puntual (`4πR²`) y publica para el Test016 una **fracción radiativa
de 0,52**, con incertidumbre expandida del 18 %.

Comprobado aquí:

- La serie del CSV, integrada a 3,00 m, devuelve 53 129 kJ; la tabla
  imprime 53 127 kJ. Es el radiómetro «HF».
- La media de los cinco, 59 859 kJ, entre el calor total, 115,1 MJ, da
  0,520. El denominador que imprime la ecuación del informe (masa perdida
  por 13,1 kJ/g) daría 1,41: la tabla se obtuvo con el calor total.
- Los cinco radiómetros dan entre 0,46 y 0,60.
- Con un solo radiómetro, la fracción instantánea va de 0,34 a 0,51 y
  vale 0,41 en el pico. **Es un valor del ensayo entero, no una serie.**

**Qué significa.** Es la fracción radiada **al entorno, al aire libre**.
No incluye lo que vuelve al propio objeto. No es lo que recibe una pared
de un recinto ni lo que deja de calentar una capa de humo.

**Qué espera el motor.** Una fracción que **no calienta el gas**. Con su
valor por defecto, y con la fracción de pared en cero, esa energía no va a
ningún sitio:

| Fracción | Procedencia | Al gas | Radiado, sin depositar por defecto |
| --- | --- | --- | --- |
| 0,35 | Valor del motor; también el de CFAST por defecto | 74,8 MJ | 40,3 MJ |
| 0,52 | TN 2303, ensayo entero, aire libre | 55,2 MJ | 59,8 MJ |
| 0,43 | Extremo inferior publicado | 66,0 MJ | 49,1 MJ |
| 0,61 | Extremo superior publicado | 44,5 MJ | 70,6 MJ |

Entre 0,35 y 0,52 hay 19,6 MJ de diferencia en lo que calienta el gas: el
17 % de la energía.

**Propuesta:**

- La fracción **no entra en la fuente**. En el módulo sigue siendo `null`.
  Es un dato del caso de acoplamiento, con su clase: `medida, ensayo
  entero, aire libre` o `supuesta`.
- Ningún valor se impone como medido para un recinto.
- Los cuatro de la tabla se corren como **experimento de sensibilidad
  declarado**, no como calibración del material.
- La parte radiada se anota en un término explícito, aunque no se
  deposite. Hoy sale del dominio en silencio.
- Los modificadores del reparto deben quedar neutros y se comprueban:
  multiplicador convectivo en 1, refuerzo por ventana en 0, oxígeno por
  encima de 0,12.
- El arrastre del penacho usa 0,70 con cualquier χ. Es una incoherencia
  del motor que se declara y entra en la sensibilidad; no se corrige aquí.

## Contrato E: ciclo de vida y restauración

**Quién posee la instancia:** `SimulationEngine`, una por recinto
prescrito y por corrida. Sigue la regla de F2.2D4B2B: **retirar siempre,
crear solo cuando se puede.**

| Momento | Qué ocurre |
| --- | --- |
| Se crea | En `reset_simulation`, **por debajo** de las guardas, tras reiniciar los recintos. `open()` valida la tabla entera |
| No abre | Fallo explícito y **no se simula**, ni con la física apagada. Es la regla que ya sigue una autorización que no resuelve |
| Empieza el reloj | En la ignición del recinto. El reloj de la fuente no es `fire_time_s`, que no avanza a ritmo de reloj |
| Se propone | En cada paso, después de `_step_fire`: `propose(t + dt)`. El último intervalo se acorta al final del soporte |
| Se confirma | En el mismo paso, antes del oxígeno y del calor, con toda la energía o con cero |
| Termina | Al final del soporte la fuente ha acabado y la potencia es cero. No se mantiene el último valor |
| Se invalida | Al salir del régimen: estado enclavado, confirmaciones a cero |
| Se descarta | En **todo** `reset_simulation`, **por encima** de las guardas. Informe a inactivo |
| Se reinicia | Instancia **nueva**. El módulo ya rechaza abrir dos veces la misma |
| Se restaura | **No.** Ver abajo |

Casos que el diseño cubre de forma expresa:

- **Reinicio sin edificio.** Se descarta la instancia y el informe queda
  inactivo. No se crea otra. El reloj no avanza.
- **Edificio no preparado.** Lo mismo, con el edificio aún enlazado.
- **Revocación.** Quitar la configuración y reiniciar **el mismo motor**
  deja el recinto en modo normal, sin potencia heredada. Se prueba sobre
  la misma instancia del motor, no sobre una nueva: es justo lo que no
  veía la prueba original de F2.2D4B2B.
- **Reutilización de la instancia.** Prohibida entre corridas. Una
  propuesta de una generación anterior la rechaza el propio módulo.
- **Informe obsoleto.** El informe se lee de la instancia viva cada vez;
  no se guarda una copia. Tras descartar, dice inactivo.
- **Cambio de tabla entre corridas.** Instancia nueva con su propia
  identidad; nada se hereda.

**Restaurar.** El motor no puede restaurar su estado. Restaurar solo la
fuente la dejaría en un instante distinto del de las capas del recinto.
`restore()` no se usa en el acoplamiento. `snapshot()` sirve para auditar
al final de la corrida y para nada más.

## Propietarios, entradas, salidas y unidades

| Magnitud | Dueño | Unidad | De dónde sale |
| --- | --- | --- | --- |
| Tabla HRR(t) | Fuente aislada | kW, s | Test016, identidad `5ac5edf4…8310f090` |
| Reloj de la fuente | Fuente aislada | s desde la ignición | Confirmaciones |
| Energía programada, aceptada y rechazada | Fuente aislada | kJ | Integral exacta |
| Decisión de aceptar | Propietario del recinto | — | R1 a R4 |
| `room.hrr_kw` del paso | Propietario del recinto | kW | Aceptada entre `dt` |
| Oxígeno equivalente debitado | `OxygenExchangeSystem`, inventario de sala | kg | Aceptada × 0,076 kg/MJ |
| Calor al gas | `ThermalSystem` | kJ | Aceptada × (1 − χ) |
| Calor radiado | `ThermalSystem`, término nuevo | kJ | Aceptada × χ |
| Fracción χ | Caso de acoplamiento | — | Declarada, con clase |
| Tolerancia `δ` | Caso de acoplamiento | — | Hipótesis declarada |
| Masa, especies, composición | Nadie | — | `null` |

## Estados y transiciones

| Estado | Entra | Sale |
| --- | --- | --- |
| `inactive` | Sin configuración, o tras cualquier reinicio | Reinicio con configuración válida |
| `failed` | La tabla no abre o el recinto no cumple el contrato A | Reinicio |
| `armed` | Instancia abierta, antes de la ignición | Ignición |
| `replaying` | Ignición; dentro del régimen | Fin del soporte, o falla una regla |
| `outside_declared_regime` | Falla R1, R2, R3 o R4 | Solo por reinicio. **Enclavado** |
| `completed` | Fin del soporte sin haber salido del régimen | Reinicio |

No hay transición de `outside_declared_regime` a `replaying`, ni de
`failed` a simular. Solo `completed` es una reproducción de la entrada.

## Balances

**Comprobables, por paso y acumulados:**

- programada = aceptada + rechazada, con la tolerancia del módulo;
- aceptada acumulada = integral de la tabla (115 093,655 kJ) si el estado
  final es `completed`;
- `room.hrr_kw × dt` = aceptada del paso, sin filtro;
- oxígeno debitado = aceptada × constante declarada;
- aceptada = calor al gas + calor radiado;
- combustible consumido del recinto = 0; especies generadas = 0;
- con el interruptor apagado, salidas idénticas byte a byte.

**Abiertos, y así deben quedar escritos:**

- masa del gas: sin pirolizado y sin productos;
- destino de la radiación en un recinto;
- ningún efecto del recinto sobre la fuente: la curva no responde;
- temperaturas y altura de capa: **no hay con qué contrastarlas**. El
  ensayo no tiene recinto. Un caso en el motor verifica el acoplamiento;
  no valida ninguna temperatura.

## Bibliografía y evidencia

| Decisión | Fuente | Qué afirma o mide | Qué se aplica | Inferencia o hipótesis | Desconocido |
| --- | --- | --- | --- | --- | --- |
| Demanda de oxígeno | [NIST TN 2077](https://doi.org/10.6028/NIST.TN.2077), ecs. 2 a 12 | El HRR se calcula del oxígeno consumido, con O₂, CO₂ y CO medidos, expansión y humedad; 13,1 MJ/kg, desviación 0,35 | La relación entre calor y oxígeno, como demanda equivalente | Que la constante genérica vale para esta silla | La constante propia del objeto |
| Total de oxígeno publicado | [Guía de la FCD](https://www.nist.gov/system/files/documents/2020/11/19/FCD_User_Guide_v4a.pdf), sec. 3 | Regla del total: diferencia de fracción por caudal | Que no es la demanda | La causa exacta del 7 % | Las entradas de la calorimetría de la corrida |
| Fracción radiativa | [NIST TN 2303](https://doi.org/10.6028/NIST.TN.2303), sec. 2.2.1, tablas 3 y 7 | Test016: 0,52 ± 18 %, cinco radiómetros, fuente puntual | Valor del ensayo entero, al aire libre | Usarlo dentro de un recinto | Radiación a superficies; la serie temporal |
| Fuego prescrito limitado por oxígeno | [NIST TN 1889v1](https://doi.org/10.6028/NIST.TN.1889v1), CFAST 7.0.0, secs. 3.1 y 3.2 | El HRR lo fija el usuario y se recorta a `ṁₑ·Y_O₂·C_LOL·13,1 MJ/kg`; límite 0,15 por defecto, independiente de la temperatura; χ = 0,35 por defecto, rango típico 0,05 a 0,4 | Que el recorte por oxígeno es una cota y el límite un valor por defecto | Ninguna: no se adopta el límite | El límite de esta silla |
| Lo mismo, en código | [CFAST 7.7.7](https://github.com/firemodels/cfast/tree/CFAST-7.7.7/Source/CFAST), `fire.f90` y `cfast_parameters.f90` | `o2f = 1.31e7`; `hrr_constrained = min(pyrolysis_rate*hoc, o2_available*o2f)`; pirólisis y especies salen de `hoc` y de la fórmula del combustible | Que un fuego prescrito con masa y especies **exige** calor de combustión y composición | — | — |
| Ensayo | [FCD, Test016](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items/test016), doi:10.18434/mds2-2314 | HRR, caudal, O₂, CO₂, CO y flujo radiante a 1 Hz | Tabla, oxígeno y radiación | — | Masa en el tiempo |

Notas:

- La guía de CFAST 7.0.0 y el código 7.7.7 no suavizan igual el límite de
  oxígeno: la primera con `tanh(800(Y − Y_l) − 4)`, el segundo con una
  transición de 0,01 por encima del límite. No afecta a nada de lo que
  aquí se usa.
- De CFAST se han leído tres archivos, identificados por su huella en el
  registro de entradas, y se citan seis líneas. No se archiva el código.
- TN 2077 se incorpora a la biblioteca local. Es un informe de NIST de
  acceso libre.
- TN 2303 da para las sillas una media de 0,40 ± 0,09. El 0,52 de esta
  corrida está en la parte alta: otra razón para no generalizarlo.
- Ninguna relación empírica se usa fuera de su alcance. No se ha
  contactado con ningún autor.

## Archivos que tocaría una implementación futura

| Archivo | Cambio |
| --- | --- |
| `sim/core/SimulationEngine.gd` | Propietario, ciclo de vida, enganche tras `_step_fire`, fallo que impide simular, informe |
| `sim/building/RoomModel.gd` | Modo del recinto, estado del régimen y su reinicio |
| `sim/core/OxygenExchangeSystem.gd` | Excluir el trazador de CO₂; constante declarada; exponer lo debitado |
| `sim/core/ThermalSystem.gd` | Término explícito de la energía radiada |
| `sim/core/SimulationLogWriter.gd` | Estado del régimen y columnas «no evaluado» |
| Nuevos | Fixture GDScript del caso, pruebas, campaña de mutaciones |

**No se tocan:** `sim/fire/PrescribedObjectHrrSource.gd`,
`sim/fire/CombustionSystem.gd`, escenarios, plantillas, editor, producto.
Si la implementación descubre que necesita `CombustionSystem`, debe
decirlo antes de hacerlo.

El interruptor sería una variable del motor **sin `@export`**, apagada por
defecto, que solo una fixture puede fijar. No entra en el esquema de
escenarios ni en el editor, y por no ser `@export` no altera el recuento
de las 84 declaraciones que vigila `audit_default_off_flags.py`.

## Criterios de aceptación y controles negativos predeclarados

Para una implementación futura. Fijados aquí, antes de que exista.

**Aceptación:**

| | Criterio |
| --- | --- |
| A1 | Apagado: los informes de referencia idénticos byte a byte y los mismos 346 required y 78 gaps |
| A2 | `room.hrr_kw` de cada paso igual a la integral independiente del intervalo propuesto dividida por la **duración completa del paso**, con la tolerancia del módulo. En el último paso el intervalo es más corto que el paso |
| A3 | Energía aceptada acumulada igual a 115 093,655 kJ con la tolerancia del módulo, para tres pasos de tiempo distintos |
| A4a | El pico instantáneo de la fuente es el dato: 621,46 kW a los 1143 s, leído con `hrr_kw()` |
| A4b | El máximo de la potencia por paso y el paso en que cae coinciden con el oráculo **de ese `dt`**. No se exige 621,46 kW a ningún paso finito |
| A4c | El paso que contiene los 1143 s es el que dice el oráculo: no hay retraso por filtro ni por un reloj equivocado |
| A5 | Oxígeno debitado en el inventario de sala igual a la energía aceptada por 0,076 kg/MJ, paso a paso y medido en el sumidero. Verifica el contrato del banco, no un consumo experimental |
| A6 | Calor al gas más calor radiado igual a la energía aceptada, paso a paso |
| A7 | Combustible consumido y especies generadas en el recinto: cero toda la corrida. El trazador de CO₂ no produce: sigue su rama sin fuego |
| A8 | Estado final `completed`, energía rechazada cero, régimen nunca invalidado |
| A9 | Los cuatro valores de χ dan la misma energía aceptada y el mismo oxígeno |
| A10 | Tras el final del soporte la potencia es cero y la fuente no se reabre |
| A11 | Reinicio, reinicio sin edificio, motor no preparado y revocación sobre el mismo motor: sin potencia ni informe heredados |
| A12 | El informe declara no evaluados CO, CO₂, HCN, humo, FED y SVV del recinto |

**Controles negativos.** Cada uno debe hacer fallar un criterio; si pasa,
el criterio no vale:

| | Defecto inyectado | Lo detecta |
| --- | --- | --- |
| N1 | La potencia pasa por el filtro del fuego de sala | A2, A3, A4 |
| N2 | Se usa `fire_time_s` como reloj de la fuente | A2, A4 |
| N3 | Se mantiene el último valor tras el soporte | A10 |
| N4 | El recinto conserva un `FireModel` | A7 y el contrato A |
| N5 | Un objeto combustible frío en el recinto | Contrato A: no se simula |
| N6 | El trazador de CO₂ sigue activo | A7 |
| N7 | El sumidero de oxígeno recorta sin rechazar energía | A5 |
| N8 | La energía rechazada se guarda y se entrega después | A3, A8 |
| N9 | La energía rechazada pasa al depósito de inquemados | A7 |
| N10 | Tras salir del régimen, el estado vuelve a válido | Transiciones |
| N11 | Un recinto de 60 m³, estanco y casi estanco | A8: debe salir del régimen. El instante del cálculo de escala es orientativo, no un valor exigido |
| N12 | Reiniciar reutiliza la instancia anterior | A11 |
| N13 | La fracción radiativa se guarda en la fuente | Contrato D y el módulo |
| N14 | Con un modo de oxígeno explícito | No se simula: el orden del paso no es el declarado |
| N15 | La tabla se sustituye por otra con la misma energía | Identidad de la fuente |

Las tolerancias numéricas son las del módulo. Ninguna se fijará después
de ver un resultado.

### Correcciones del 08-10, registradas antes de ejecutar el acoplamiento

Hechas al leer el sumidero del motor y al preparar el oráculo, **antes de
que exista ningún resultado acoplado**. Ninguna amplía una tolerancia.

**1. Oxígeno.** Reformulado arriba: demanda equivalente prescrita, con el
coeficiente del motor, 0,076 kg/MJ. A5 verifica un contrato de
contabilidad.

**2. Pico y paso finito.** A2 fija la potencia de un paso como la
integral de su intervalo entre la duración del paso. Con un paso finito
eso es una media, y su máximo **no es el pico instantáneo**. La versión
anterior de A4 exigía 621,46 kW «en el paso que contiene los 1143 s» y
contradecía a A2. Demostración con un triángulo de pico 100 kW a los 10 s
y pendientes de 10 kW/s, leído con pasos que empiezan en cero:

| Paso | Dónde cae el pico | Mayor potencia de paso | Forma cerrada |
| --- | --- | --- | --- |
| 4 s | En mitad de un paso | 90 kW | `pico − pendiente·dt/4` |
| 1 s | En el borde de un paso | 95 kW | `pico − pendiente·dt/2` |
| 0,5 s | En el borde de un paso | 97,5 kW | `pico − pendiente·dt/2` |

La energía es la misma en los tres: 1000 kJ. Para el Test016, el oráculo
independiente da:

| Paso | Pasos | Mayor potencia de paso | Paso e intervalo | Frente a 621,46 kW |
| --- | --- | --- | --- | --- |
| 1,0 s | 3768 | 621,125 kW | 1142, de 1142 a 1143 s | −0,335 kW |
| 0,7 s | 5383 | 621,274 kW | 1632, de 1142,4 a 1143,1 s | −0,186 kW |
| 2,5 s | 1508 | 619,663 kW | 457, de 1142,5 a 1145 s | −1,798 kW |

A4 queda partido en A4a, A4b y A4c.

**3. Otras precisiones del contrato**, que no cambian el alcance:

- **Inventario que usa el sumidero.** Con los interruptores por defecto y
  un recinto con hueco al exterior, el motor debita el oxígeno de sala:
  `masa de aire × room.o2`, con masa de aire igual a 1,2 kg/m³ por el
  volumen, y recorta el débito de un paso al 5 % de ese inventario. Esa
  es la ruta que el banco declara. En un recinto **estanco** el motor usa
  otra ruta, sobre el número de la capa inferior y con dos bases de masa
  distintas: ahí el banco no puede cumplir su contrato y se invalida.
- **Números de zona.** El motor lleva además un número de oxígeno para la
  capa superior y otro para la inferior, que no forman con el de sala una
  partición conservada. Para cualquier recinto con potencia aplica a la
  capa superior un débito de «desplazamiento» del 9 % de la demanda y
  mezcla las dos capas. El banco **no lo excluye y no lo usa**: lo mide y
  lo informa aparte. No entra en A5.
- **R2, concreto.** Se vigilan el número de sala y el de la capa
  inferior: el régimen se invalida si alguno baja más de `δ` respecto a
  su valor en la ignición. `δ = 0,01` en el caso base, declarado aquí.
- **R3, concreto.** La interfaz de la capa caliente debe quedar a 0,3 m o
  más del suelo, que es la referencia con la que el motor decide de qué
  capa respira un fuego. Es una hipótesis del banco.
- **Comprobación tras el oxígeno y antes del calor.** El motor debita el
  oxígeno antes de depositar el calor. Si el débito real no es el
  comprometido, la potencia del paso se anula **antes** de que
  `ThermalSystem` la lea: no queda calor contabilizado como válido. El
  oxígeno que el sumidero haya llegado a debitar en ese paso no se puede
  devolver, porque el motor no restaura, y se informa.
- **Último paso.** Se propone solo el tramo dentro del soporte y su
  energía se divide por el paso completo: `potencia × dt` es exactamente
  esa energía, ni se pierde ni se duplica.
- **Trazador de CO₂.** «Cero» era impreciso: el trazador tiene un valor
  ambiente. Lo que se exige es que no produzca.
- **Recinto de 60 m³.** Dos variantes: estanco, que se invalida por la
  ruta del sumidero, y casi estanco, con una rendija al exterior, que se
  invalida al bajar el oxígeno.
- **Fracción radiativa.** Los cuatro valores son 0,35, 0,52, 0,4264 y
  0,6136; los dos últimos son el publicado menos y más su incertidumbre.

## Lo que bloquea el siguiente paso

**Decisiones del usuario:**

1. **Si merece la pena implementar A3.** Verifica el acoplamiento; no
   valida ninguna temperatura porque el ensayo no tiene recinto. Su valor
   es dejar probado el camino de propiedad, oxígeno y energía para cuando
   haya un objeto con datos completos.
2. **Qué hacer al salir del régimen.** Se recomienda parar la entrega y
   enclavar. La alternativa, seguir entregando lo que el oxígeno permita,
   convierte la fuente en un modelo sin respaldo.
3. **Autorizar cambios en `sim/`**, con interruptor apagado y cadena R2-1
   completa.

**Datos que desbloquearían más que una fuente térmica:**

1. la serie numérica de la célula de carga de los Test016 y Test021;
2. una composición aprobada de la silla, cuyas dos descripciones
   publicadas se contradicen;
3. un ensayo **en recinto** con el mismo objeto, para tener con qué
   contrastar temperaturas, y con poco oxígeno, para ir más allá del aire
   libre.

Las series de CO₂ y CO del conducto existen, a 1 Hz y de la misma
corrida. Podrían sostener en el futuro una emisión prescrita al aire
libre. Es un gate aparte, no autorizado, y no cambia el NO-GO de CO/FED.

## Alcance del siguiente encargo, si se autoriza

Un único caso, y nada más:

- una fuente térmica prescrita del Test016, sola en un recinto sin
  combustible, grande o bien ventilado;
- interruptor del motor sin `@export`, apagado por defecto, solo fixture;
- calor por `room.hrr_kw` sin filtro, oxígeno como demanda equivalente
  prescrita, χ declarada en el caso y corrida con sus cuatro valores;
- sin masa, sin especies, sin FED, sin otros objetos, sin supresión, sin
  restauración y sin producto;
- salida del régimen: parar y enclavar, salvo decisión distinta;
- criterios A1 a A12, controles N1 a N15 y cadena R2-1 completa.

**No hay GO para representar la combustión del mueble.**

## Verificación de esta fase

- Auditor offline
  [`audit_g3_object_hrr_coupling.py`](../../scripts/simulation/audit_g3_object_hrr_coupling.py):
  lee el motor como texto, la serie auditada y las lecturas publicadas.
  [Entradas](G3_OBJECT_HRR_COUPLING_INPUTS_2026-10-08.json) y
  [resultado](G3_OBJECT_HRR_COUPLING_AUDIT_2026-10-08.json) versionados;
  `--check` coincide.
- [Pruebas](../../tests/test_g3_object_hrr_coupling_design.py): fijan los
  34 hechos del motor y el orden del paso, comprueban cada cifra contra
  una forma cerrada o una lectura publicada, y confirman que un hecho
  alterado detiene el auditor y que un GO no sobrevive a la pérdida de su
  dato.
- Las dos tablas de TN 2303 se comprobaron sobre la imagen de la página.
- `sim/`, escenarios, perfiles y producto: sin cambios. Godot no se ha
  lanzado: nada de esta fase lo necesita. La referencia no se regenera.

Reproducir:

```text
python -m scripts.simulation.audit_g3_object_hrr_coupling --check
python -m pytest tests/test_g3_object_hrr_coupling_design.py -q -p no:cacheprovider
```

## Límites

- Es un diseño. Ningún criterio de aceptación se ha ejecutado, porque no
  existe el código que tendría que cumplirlo.
- El motor se ha leído en `60754428`. Las anclas detectan que un hecho se
  mueve; no demuestran que la lista de hechos sea completa.
- El contraejemplo del filtro imita una sola pieza de la ruta del fuego de
  sala, la más favorable. La ruta entera se aparta más.
- La cuenta del recinto cerrado ignora fugas, capas y transporte. Da un
  orden de magnitud, no un instante.
- La reconstrucción del oxígeno es aproximada y con humedad supuesta. No
  sustituye a la ecuación de NIST.
- La fracción radiativa es de un ensayo, con cinco radiómetros que
  discrepan un 14 % del calor total entre sí.
- No hay validación predictiva de nada. Test021 sigue sin usarse.
