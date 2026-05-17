# Simufire - Estado de sesion
**Ultima actualizacion**: 15 abril 2026

## Donde queda guardado
- Este estado queda en el repo, en [ESTADO_SESION_2026-04-15.md](/F:/OneDrive/Documentos/GitHub/simufire/ESTADO_SESION_2026-04-15.md:1).
- Como el proyecto esta dentro de `F:\OneDrive\...`, deberia quedar sincronizado online por OneDrive y abrirse en otro ordenador con la misma cuenta.
- Si mas adelante quieres dejarlo tambien fijo en GitHub, habria que hacer commit/push aparte.

## Estado actual del modelo
- Proyecto Godot/GDScript de incendio en vivienda.
- Escenario base: R0 salon, R1 pasillo, R2 dorm1, R3 dorm2, R4 cocina, R5 bano.
- Ventanas automaticas por temperatura desactivadas por defecto.
- El motor ya usa una capa superior acoplada con `upper_gas_kg` y `upper_energy_kj`.
- El O2 ya no se mueve solo entre habitaciones vecinas: ahora hay redistribucion por toda la red de puertas abiertas.
- El humo subventilado ya no depende solo del `HRR` efectivo: hay una base de pirolisis/smolder para que con poco O2 siga apareciendo humo y CO.

## Cambios importantes ya hechos
### `sim/core/SimulationEngine.gd`
- `glass_auto_break_enabled = false` por defecto.
- Aniadido modelo de capa superior con:
  - `upper_gas_kg`
  - `upper_energy_kj`
- `_step_temperature()` rehecho para trabajar con masa/energia reales de la capa superior.
- `_step_oxygen()` ampliado con mezcla conservativa por red completa de puertas abiertas:
  - `o2_network_iterations = 4`
- `_step_smoke()` ahora mueve humo, CO, masa caliente y energia entre salas de forma acoplada.
- Se elimino una perdida artificial de humo cuando la capa bajaba mucho.
- Ajuste reciente para incendio confinado:
  - `fire_smoke_yield_low_o2_multiplier = 7.5`
  - `fire_smoke_basis_min_fraction = 0.40`
  - `fire_smolder_hrr_fraction = 0.10`
  - `fire_smolder_smoke_multiplier = 2.8`
  - `base_spill_kg_s_per_m2 = 0.26`
  - `max_spill_kg_s = 1.4`
  - `max_fraction_out_per_s = 0.08`

### `sim/smoke/SmokeModel.gd`
- La altura de capa ya no depende solo de `smoke_kg`.
- La capa se recalcula usando tambien la masa real de gases calientes.
- Las puertas pueden derramar humo en ambos sentidos en el mismo step.

## Lo ultimo validado en log
Log de referencia:
- `C:\Users\dangp\AppData\Roaming\Godot\app_userdata\simufire\sim_log.txt`

Ultima corrida larga revisada:
- Hasta `TIME=440.1 s`

Comportamiento observado en esa ultima corrida:
- El problema anterior de "el humo se retrae y el fuego muere demasiado pronto" ya no aparece.
- Ahora el edificio si se carga de humo como incendio confinado.
- Pero el ajuste actual probablemente se ha ido demasiado al lado fuerte:
  - `TIME=320.1 s`
    - `ROOM 0 | HRR=170.56 | Smoke=1.5028 | O2=0.1055`
    - `ROOM 1 | HRR=82.88 | Smoke=2.9206 | Layer=0.25 | O2=0.1134`
  - `TIME=400.1 s`
    - `ROOM 0 | HRR=35.76 | Smoke=3.2238 | O2=0.1012`
    - `ROOM 1 | HRR=10.40 | Smoke=5.7243 | Layer=0.00 | O2=0.1018`
  - `TIME=440.1 s`
    - `ROOM 0 | HRR=19.54 | Smoke=4.6994 | O2=0.1007`
    - `ROOM 1 | HRR=4.94 | Smoke=6.3505 | Layer=0.00 | O2=0.1009`

## Diagnostico honesto actual
- Antes:
  - Poco humo
  - El incendio moria pronto
  - El humo no llenaba bien la vivienda
- Ahora:
  - El incendio confinado genera humo de forma mucho mas creible
  - El O2 bajo ya no "mata" visualmente el humo
  - Pero el modelo esta demasiado agresivo en acumulacion de humo y propagacion secundaria
  - El pasillo llega a llenarse por completo muy pronto (`Layer=0.00`)

## Siguiente paso recomendado
Prioridad siguiente:
- Mantener el comportamiento de incendio confinado cargado de humo
- Pero bajar la agresividad de propagacion y llenado total del pasillo

Toques probables para la proxima sesion:
1. Subir el umbral de ignicion secundaria o exigir mas exposicion sostenida antes de encender otras salas.
2. Bajar un poco la base de humo subventilado o el derrame maximo por puerta sin volver al problema anterior.
3. Revisar el pasillo: ahora hace de gran reservorio de humo y se satura demasiado rapido.
4. Rehacer la nota antigua de "sedimentacion de humo" si queremos una fase post-incendio mas realista.

## Nota de revision pendiente
- El finding antiguo sobre mezcla de O2 con dos `lerp` secuenciales ya no es la prioridad central del modelo.
- El problema dominante ahora mismo es de calibracion fisica del humo en incendio confinado, no de sesgo menor en la mezcla local.

## Actualizacion 16 abril 2026
- Se detecto una incoherencia entre la `hot layer` y la `smoke layer`.
- El motor podia bajar mucho la capa caliente y disparar flashover, pero el derrame de humo hacia puertas/ventanas estaba usando la capa mas alta de las dos referencias (`maxf`) en vez de la mas baja.
- Efecto observado:
  - `ROOM 0` entraba en flashover
  - `HotLayer` bajaba por debajo del dintel
  - pero `SmokeLayer` seguia alta y bloqueaba el paso de humo al pasillo
- Fix aplicado:
  - nueva helper `estimate_effective_layer_height_m()` en `sim/smoke/SmokeModel.gd`
  - `compute_outside_vented_kg()` y `compute_room_transfers()` ahora usan la capa efectiva mas baja
  - `SimulationEngine.get_state()` expone `effective_smoke_layer_m`
  - `Main.gd`, `ui/hud.gd` y `view/Visualizer.gd` muestran esa capa efectiva en vez de priorizar solo `smoke_layer_m`

## Verificacion 16 abril 2026
- Corrida headless validada con Godot 4.6.2 local.
- Resultado:
  - a `TIME=180.0 s`, `ROOM 1` ya recibe humo:
    - `Smoke=0.6033`
    - `SmokeLayer=1.72`
    - `HotLayer=1.80`
  - a `TIME=390.1 s`, el humo ya ha llegado tambien a `ROOM 2`, `ROOM 3`, `ROOM 4` y `ROOM 5`
- Con esto queda resuelto el bloqueo principal de propagacion de humo entre estancias.

## Ajuste posterior 16 abril 2026
- Revision posterior del usuario: el humo no debia expandirse por la `hot layer`, sino cuando la `SmokeLayer` visible bajase a `2.0 m`.
- Cambio aplicado:
  - el derrame interior de humo ahora arranca con `smoke_layer_m <= 2.0`
  - la tasa de derrame interior y exterior aumenta con `overpressure_pa`
  - la UI vuelve a dibujar la `smoke_layer_m` real, no la capa efectiva mezclada con la termica
  - el log ahora incluye `P=...Pa` por sala
- Verificacion:
  - `TIME=120.1 s`: `ROOM 0 SmokeLayer=2.17`, `ROOM 1 Smoke=0.0000`
  - `TIME=130.1 s`: `ROOM 0 SmokeLayer=1.99`, `ROOM 1 Smoke=0.0245`
  - `TIME=140.1 s`: con `ROOM 0 P=10.14Pa`, `ROOM 1 Smoke=0.4300`
- Con esto el criterio pedido queda cumplido: el humo empieza a pasar al cruzar `2.0 m` y la presion acelera su expansion.

## Correccion 16 abril 2026 - cola infinita de humo y CO en R0/pasillo
- Problema confirmado en corrida larga:
  - a partir de ~`TIME=760 s`, `ROOM 0` seguia con `HRR~40 kW`, `Smoke~8 kg` y `CO~22000 ppm`
  - el pasillo quedaba alimentado por esa cola y el modelo parecia generar humo/CO "sin fin"
- Causa raiz:
  - en `_step_fire()` la base de humo/CO seguia saliendo del `HRR` ideal previo a limitar por `O2`
  - con `O2` apenas por encima del minimo, la llama real era debil pero el calculo de humo seguia usando una base enorme
  - ademas faltaba una extincion por sofocacion sostenida cerca del umbral de `O2`, asi que el fuego podia quedarse mucho tiempo en modo zombi
- Fix aplicado:
  - la base de humo subventilado ahora se ancla al `room.hrr_kw` real, no al `HRR` ideal pre-limitacion
  - el smolder residual queda acotado a una potencia pequena
  - se anade `fire_starvation_o2_factor = 0.03` para extinguir fuegos que permanecen sofocados durante `fire_extinction_delay_s`
- Verificacion nueva en `sim_log.txt`:
  - `TIME=140.1 s`: `ROOM 0 SmokeLayer=2.00` y `ROOM 1 Smoke=0.0077` -> el humo sigue entrando al pasillo al cruzar los `2.0 m`
  - `TIME=600.1 s`: `ROOM 0 HRR=0.00`, `Smoke=0.7380`, `CO=4415ppm`
  - `TIME=780.0 s`: `ROOM 0 HRR=0.00`, `Smoke=0.7270`, `CO=4350ppm`
- Resultado:
  - desaparece la generacion rapida e indefinida de humo/CO en `R0`
  - el pasillo deja de cargarse artificialmente por esa cola larga

## Correccion 16 abril 2026 - disipacion post-incendio
- Tras quitar la cola infinita, seguia quedando un residuo demasiado estable:
  - `R0` y `R1` conservaban humo y CO durante demasiado tiempo aunque ya no hubiese fuego
  - la causa era que solo se aplicaba la dilucion base por `ACH`, muy debil para la fase de enfriamiento
- Fix aplicado en `SimulationEngine.gd`:
  - nueva fase de limpieza residual cuando `room.fire == null`, `HRR=0` y la sala ya esta enfriando
  - el humo ahora pierde masa por deposicion/asentamiento (`smoke_settling_*`)
  - el CO residual tiene una purga extra en esa misma fase (`co_postfire_purge_*`)
  - la intensidad depende de temperatura y sobrepresion: no toca la propagacion inicial fuerte, entra sobre todo en la cola
- Verificacion:
  - `TIME=140.1 s`: `ROOM 0 SmokeLayer=2.00`, `ROOM 1 Smoke=0.0077` -> se mantiene el criterio de propagacion al cruzar `2.0 m`
  - `TIME=600.1 s`: `ROOM 1 Smoke=0.5755` y `CO=7790ppm`
  - `TIME=780.0 s`: `ROOM 1 Smoke=0.1877` y `CO=4416ppm`
  - `TIME=780.0 s`: `ROOM 0 Smoke=0.4633` y `CO=3472ppm`
- Resultado:
  - el humo residual ya no queda casi congelado en pasillo y estancias
  - la cola post-incendio baja de forma visible sin romper la expansion inicial del humo

## Correccion 16 abril 2026 - separacion de capa de humo y capa termica
- Problema detectado:
  - `h_layer_m` mezclaba humo visible y gas caliente, asi que la UI y parte del motor trataban ambas cosas como si fuesen la misma capa
  - eso hacia dos cosas raras:
    - el `HotLayer` podia quedarse "fantasma" al final aunque la sala ya estuviese a `20 C`
    - los ajustes termicos podian contaminar la interpretacion visual del humo
- Fix aplicado:
  - `RoomModel` ahora guarda `thermal_layer_m` aparte de `h_layer_m`
  - `SmokeModel.recompute_layer_from_mass()` vuelve a representar solo la capa visible de humo
  - `SimulationEngine` calcula la capa termica desde `upper_gas_kg` y la usa para:
    - intercambio de calor entre salas
    - presion/venteo por capa caliente
    - logging y estado tecnico (`hot_layer_m`)
  - la propagacion de incendio y flashover se mantuvieron ligadas a la capa visible de humo para no adelantar el fuego por el mero calor transportado
  - se anadio colapso explicito de capa termica residual cuando la sala ya esta sin fuego, casi isoterma y con humo residual minimo
- Verificacion nueva en `sim_log.txt`:
  - `TIME=140.1 s`: `ROOM 0 SmokeLayer=2.07`, `ROOM 1 Smoke=0.0000`
  - `TIME=150.1 s`: `ROOM 0 SmokeLayer=1.99`, `ROOM 1 Smoke=0.0962`
  - `TIME=1830.1 s`: todas las salas terminan con `SmokeLayer=2.40` y `HotLayer=2.40`
- Resultado:
  - el humo sigue empezando a pasar al pasillo cuando `R0` cruza los `2.0 m`
  - desaparece la `HotLayer` residual falsa al final de la corrida larga
  - HUD y visualizador ya muestran por separado capa visible y capa termica

## Correccion 16 abril 2026 - sobrecalentamiento del pasillo por transferencia termica
- Problema detectado tras separar capas:
  - el pasillo (`ROOM 1`) podia recibir una `temp_upper` casi igual a la del foco en cuanto empezaba a entrar humo
  - la causa era que el calor inter-estancias se movia demasiado "puro" tanto en `_step_temperature()` como en `_step_smoke()`
- Fix aplicado:
  - nueva helper `_compute_interroom_transfer_temp_c()` para que el gas transferido llegue ya mezclado con aire mas frio de la sala destino
  - se redujo el tope de masa caliente que puede cruzar por paso en el intercambio convectivo de puertas
  - el calor que viaja con el humo ya no se toma como una fraccion directa de toda la energia de la capa superior, sino como la energia del gas efectivamente transferido y mezclado
- Verificacion nueva en `sim_log.txt`:
  - `TIME=150.1 s`: `ROOM 1 Up=151.59 C`, `Smoke=0.1135`
  - antes de este ajuste el mismo punto estaba en torno a `Up~792 C`
  - `TIME=1830.1 s`: todas las salas siguen cerrando con `SmokeLayer=2.40` y `HotLayer=2.40`
- Resultado:
  - el pasillo sigue recibiendo calor cuando empieza el derrame, pero ya no como si fuese una extension inmediata del foco
  - se mantiene la propagacion de humo al cruzar `2.0 m` sin reintroducir la capa caliente fantasma del final

## Correccion 16 abril 2026 - gradiente termico e isoterma de 150 C
- Referencia usada:
  - en el PDF `CamScanner 21-11-25 09.25 (2).pdf`, la pagina rotulada `45` resume la supervivencia por `FED`, flujo termico y `altura capa 150 C`
  - la pagina rotulada `47` usa explicitamente la `isoterma 150 C` con cortes de `>1,8 m`, `0,5-1,8 m` y `<0,5 m`
- Situacion anterior:
  - el motor era estrictamente zonal de dos capas, con salto brusco entre `temp_lower_c` y `temp_upper_c`
  - por tanto no habia una cota termica intermedia calculable, solo `HotLayer`
- Fix aplicado:
  - se anade una banda vertical de transicion termica en `SimulationEngine.gd`
  - nuevas helpers:
    - `_estimate_thermal_transition_band_m()`
    - `_estimate_temperature_at_height_m()`
    - `_estimate_isotherm_height_m()`
  - el estado ahora expone:
    - `layer_150c_m`
    - `temp_at_1_8m_c`
    - `temp_at_1_5m_c`
    - `temp_at_1_1m_c`
  - la UI dibuja una linea especifica de `150 C`
- Interpretacion:
  - `L150 = room.height` -> en toda la sala la temperatura queda por debajo de `150 C`
  - `L150 = 0.0` -> incluso a ras de suelo la sala esta por encima de `150 C`
  - `0.5 < L150 < 1.8` -> escenario termicamente comprometido segun el criterio del documento
- Verificacion en `sim_log.txt`:
  - `TIME=150.1 s`: `ROOM 1 Up=151.59`, `Low=20.76`, `L150=2.27`
  - `TIME=150.1 s`: `ROOM 0 Up=900.00`, `Low=238.70`, `L150=0.00`
  - `TIME=1830.1 s`: todas las salas acaban con `L150=2.40`
- Limite actual del modelo:
  - esto es un gradiente vertical aproximado dentro de cada sala
  - no es un campo 2D/3D ni una isoterma inclinada resuelta espacialmente como en un CFD

## Correccion 16 abril 2026 - banco inicial de validacion
- Se implementa `sim/validation/CaseRunner.gd`
- Ejecucion por CLI:
  - `-- --validation-case=living_room_hallway`
  - `-- --validation-case=postfire_decay`
  - `-- --validation-case=layer150_tenability`
- Casos iniciales:
  - `living_room_hallway`: verifica cruce de `SmokeLayer <= 2.0 m` y entrada de humo al pasillo
  - `postfire_decay`: verifica cola post-incendio y retorno a estado cuasi ambiente
  - `layer150_tenability`: verifica `L150`, `T@1.8m` y temperatura de pasillo
- Reportes:
  - se guardan en `sim/validation/reports/*.json`
  - los baselines estan en `sim/validation/baselines/*.json`
- Verificacion hecha:
  - `living_room_hallway`: baseline `PASS`
  - `layer150_tenability`: baseline `PASS`
- Observacion importante sobre `L150`:
  - en `ROOM 0`, cuando toda la altura util supera `150 C`, `L150=0.0` y visualmente la linea queda a ras de suelo
  - en `ROOM 1`, la linea no baja mucho porque el pico de `temp_upper` apenas supera `150 C` y `T@1.8m` se mantiene por debajo (`<150 C`)

## Correccion 16 abril 2026 - limpieza estructural y suavizado de `L150`
- Limpieza aplicada:
  - `Main.gd` deja de escribir el HUD directamente y queda como orquestador simple de `engine -> hud/visualizer`
  - `RoomModel.gd` incorpora `reset_dynamic_state()` y se reutiliza desde `BuildingModel.gd` y `SimulationEngine.gd` para evitar duplicidad en el reseteo de salas
  - `SmokeModel.gd` elimina parametros muertos en `compute_outside_vented_kg()` y `compute_room_transfers()`
  - se mantiene `compute_room_transfer()` solo como wrapper heredado de compatibilidad
  - se elimina un bloque muerto `if false` dentro de `_step_fire()`
- Ajuste sobre la isoterma de `150 C`:
  - `_estimate_thermal_gradient_depth_m()` deja de imponer una banda minima con escalon duro
  - la banda termica minima ahora entra de forma progresiva, evitando que `L150` "salte" demasiado al empezar a calentarse el pasillo
- Efecto observado:
  - en `ROOM 1`, con `Up~151.6 C`, `L150` ya no cae de golpe a una cota intermedia agresiva
  - la isoterma queda practicamente pegada al techo cuando solo una pequena franja supera `150 C`
- Verificacion:
  - corrida headless principal: `ROOM 1` se mantiene con `L150=2.40` en log redondeado, mientras la metrica fina da `room_1_min_l150_m=2.39298`
  - validaciones headless tras la limpieza:
    - `layer150_tenability`: baseline `PASS`
    - `living_room_hallway`: baseline `PASS`
    - `postfire_decay`: baseline `PASS`

## Correccion 16 abril 2026 - `L150` en R0 y primer corte de `BL-04`
- Problema revisado:
  - en `R0`, la isoterma de `150 C` seguia cayendo demasiado de golpe porque el modelo trataba la capa baja como perfectamente uniforme
  - cuando `temp_lower_c` cruzaba `150 C`, `L150` pasaba practicamente al suelo de una sola vez
- Ajuste aplicado:
  - se anade una banda de enfriamiento junto al suelo en `SimulationEngine.gd`
  - el perfil vertical ya no es solo `suelo->lower uniforme->upper`, sino `suelo algo mas frio -> lower -> upper`
  - eso hace que la isoterma no colapse inmediatamente a `0.00 m` cuando la media de la capa baja supera `150 C`
- Verificacion nueva:
  - `TIME=130.1 s`: `ROOM 0 L150=1.73`
  - `TIME=140.1 s`: `ROOM 0 L150=0.22`
  - `TIME=150.1 s`: `ROOM 0 L150=0.16`
  - antes de este ajuste, en ese mismo tramo la linea ya caia a `0.00`
- `BL-04` iniciado:
  - la logica principal de combustión por sala se mueve desde `_step_fire()` en `SimulationEngine.gd` a `CombustionSystem.gd`
  - `ignite_room()` ahora crea el fuego via `combustion_system.create_legacy_room_fire(...)`
  - `SimulationEngine` delega el avance del fuego a `combustion_system.step_room_fire(...)`
  - los proxies `fuel_objects` heredados ya reflejan mejor el combustible restante y el estado (`COLD/DECAYING/FLAMING/BURNED_OUT`)
- Validacion tras este corte:
  - `layer150_tenability`: baseline `PASS`
  - `living_room_hallway`: baseline `PASS`
  - `postfire_decay`: baseline `PASS`

## Correccion 16 abril 2026 - intercambio local de `O2`, debug largo y rebote de `L150`
- Problema revisado:
  - el fuego estaba drenando `O2` de toda la vivienda demasiado pronto por la redistribucion global de especies
  - al cortar eso por completo, el foco se quedaba sin aire demasiado rapido y `R0` entraba en decaimiento prematuro
  - esa extincion temprana hacia que `L150` rebotase hacia arriba de forma poco creible
- Ajuste aplicado:
  - se elimina la redistribucion global de `O2` por red abierta y se reemplaza por un intercambio local por abertura
  - el intercambio interior de `O2` ahora usa un estado comun de flujo por puerta:
    - sala caliente / sala fria
    - banda caliente sobre el dintel
    - empuje por humo y sobrepresion
    - contraflujo inferior minimo por puerta abierta
  - la transferencia termica entre habitaciones reutiliza ese mismo estado, para no tener calor, humo y `O2` desacoplados
  - se anade el caso `sim/validation/cases/long_smoke_o2_debug.json` con `700 s` y log detallado
  - `layer_150c_m` mantiene bajada rapida pero su recuperacion se suaviza (`layer_150c_relax_up_per_s`)
  - se alarga la extincion por agonia y se relaja el criterio de starvation:
    - `fire_extinction_delay_s = 300`
    - `fire_starvation_o2_factor = 0.008`
- Verificacion nueva:
  - `layer150_tenability` sigue en `FAIL` contra el baseline antiguo, pero mejora en lo relevante:
    - `room_0_final_layer_150c_m`: baja de `1.81`/`1.34` a `0.77` con el suavizado nuevo
    - `time_room_0_smoke_layer_2m_s`: `152.75 s`
    - `time_room_1_smoke_start_s`: `152.92 s`
  - corrida larga `long_smoke_o2_debug`:
    - `time_to_extinction_s = 567.92`
    - `TIME=340.1 s`: `ROOM 0 HRR=8.32`, `L150=1.45`
    - `TIME=400.1 s`: `ROOM 0 HRR=7.10`, `L150=2.24`
    - `TIME=600.1 s`: `ROOM 0` ya esta extinguido, pero `ROOM 2-5` siguen cerca de ambiente y no sufren drenaje masivo de `O2`
  - comportamiento de `O2` tras el cambio:
    - `ROOM 1` si participa en el suministro al foco y baja a ~`0.157`
    - `ROOM 2-5` ya no caen a `0.12`; quedan alrededor de `0.204-0.206` en el tramo fuerte, todavia sin humo
- Estado actual:
  - mejora clara: ya no hay “succion global” de `O2`
  - mejora clara: `L150` no pega un salto tan brusco al recuperar
  - pendiente: el humo sigue sin llegar a `ROOM 2-5` en la corrida larga actual; el siguiente ajuste debe ir a la cola subventilada / transferencia sostenida de humo hacia pasillo y dormitorios
