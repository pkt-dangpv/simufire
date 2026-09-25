# Matriz G4/G5 — estabilidad de producto y distribución Windows

> **Fecha:** 24 de septiembre de 2026 (tercera pasada: D-2 sin tocar FDS, y D-5)
> **Gates:** G4 (producto estable) y G5 (distribución)
> **Base:** [plan de publicación vigente](../PLAN_PUBLICACION_2026-10-30.md) ·
> [ámbito G0/G2](MATRIZ_G0_G2_AMBITO_EVIDENCIA.md) ·
> [auditoría de crashes headless](../validation/GODOT_471_HEADLESS_CRASH_AUDIT.md)
>
> **G0 sigue abierto.** La ruta histórica de venteo y sus efectos en los cinco
> escenarios aún no están evaluados; este documento no los da por buenos.

---

## G5 · Distribución Windows

### 1. Cómo arranca hoy el proyecto

| elemento | valor |
|---|---|
| Godot | `4.7.1.stable.official.a13da4feb` (verificado) |
| Escena principal | `res://scenes/MainMenu.tscn` |
| Renderer | `GL Compatibility` |
| Icono | `res://icon.svg` |
| Nombre | `SimuFire` |

**Rutas de escritura en tiempo de ejecución** (todas bajo `user://`, ninguna
absoluta): `simufire.cfg`, `startup_sim_options.json`,
`last_editor_runtime_template.json`, `editor_scenario.json`,
`return_to_editor.flag`, `sim_log.csv`, `sim_log.txt`, `sim_log_targets.csv`,
`latest_graphs_dir.txt`. En un build exportado, `user://` cae en
`%APPDATA%/Godot/app_userdata/SimuFire`.

**Dependencia externa opcional:** la generación de gráficas PNG invoca Python.
El juego comprueba `check_python_available()` y muestra un aviso en el HUD si
falta; **no se bloquea ni falla**. La instalación debe declarar que sin Python
con matplotlib no hay gráficas exportadas, y que el resto funciona igual.

### 2. Estado del empaquetado

| requisito | estado |
|---|---|
| `export_presets.cfg` en el repositorio | **ausente**, y `.gitignore:6` lo ignora a propósito |
| Plantilla versionable del preset | **creada y corregida**: `export_presets.cfg.template` (ver D-4) |
| **Plantillas de exportación de Godot 4.7.1** | **AUSENTES — 0 entradas en `%APPDATA%/Godot/export_templates`** (recomprobado) |
| Build generado | **no**, imposible sin plantillas |
| Instalación en máquina limpia | **no probada** |

**Bloqueo activo de G5:** sin plantillas de exportación instaladas no se puede
generar ningún ejecutable. Datos medidos de la descarga, para decidir:

| dato | valor |
|---|---|
| Origen | release oficial `godotengine/godot`, etiqueta `4.7.1-stable`, activo `Godot_v4.7.1-stable_export_templates.tpz` |
| Tamaño del paquete | **1 280 486 955 B = 1,19 GiB** (medido con `HTTP HEAD`, `Content-Length`) |
| Espacio necesario | ~1,2 GiB de descarga + extracción a `%APPDATA%/Godot/export_templates/4.7.1.stable/`; **contar ~2,5 GiB de pico** mientras coexisten `.tpz` y extraído |
| Disco libre en C: | 268,1 GiB — sobra de largo |
| Alcance | el `.tpz` trae **todas** las plataformas; no hay descarga oficial solo-Windows |

**No la he descargado**: es una descarga grande hacia la máquina del usuario y
una decisión suya. Vía alternativa sin línea de comandos:
`Editor → Gestionar plantillas de exportación` dentro de Godot.

### 3. Procedimiento de exportación documentado

Una vez instaladas las plantillas:

```powershell
# 1. preparar el preset (una sola vez)
Copy-Item export_presets.cfg.template export_presets.cfg

# 2. carpeta de salida FUERA del arbol versionado
$out = "$env:USERPROFILE\SimuFire_build"
New-Item -ItemType Directory -Force $out | Out-Null

# 3. exportar release
& "C:\ruta\a\Godot_v4.7.1-stable_win64_console.exe" `
    --headless --path . `
    --export-release "Windows Desktop" "$out\SimuFire.exe"
```

Notas del procedimiento, no opcionales:

- La salida va a `%USERPROFILE%\SimuFire_build`, **fuera del repositorio**. No
  se versiona ningún binario ni `.pck`.
- `export_path` queda vacío en la plantilla justamente para que la ruta la fije
  el comando y no se filtre una ruta personal al fichero.
- `codesign/enable=false`: **no hay firma**. Windows SmartScreen avisará al
  ejecutar. Firmar exige un certificado, que es decisión y coste del usuario.
- `exclude_filter` deja fuera `docs/`, `runs/`, `graphs/`, `tests/`, `tools/`,
  `scripts/`, `sim/validation/cfast/`, `sim/validation/reports/`, `truth/` y
  `external/`. El build no distribuye informes ni utillaje de validación.
- `include_filter` **es obligatorio** y antes estaba vacío (D-4). Con
  `export_filter="all_resources"` Godot empaqueta recursos, pero un `.json` no
  es un recurso y se queda fuera. El producto carga cuatro familias de `.json`
  por ruta `res://`, así que la lista las nombra explícitamente:
  `i18n/*.json` (todo el texto de la interfaz), `scenarios/*.json` (el
  desplegable de escenarios), `sim/validation/cases/cfast_*.json` (las entradas
  «CFAST: …» del mismo desplegable) y
  `sim/validation/baseline_gate_dispositions.json` (`CaseRunner`). Son 725 KB
  en total.
- Los `cfast_*.json` se incluyen **a propósito**, aunque sean casos de
  validación: el editor los ofrece en su desplegable, y excluirlos haría que el
  build enseñase una lista más corta que el proyecto sin decirlo. Si se prefiere
  no distribuirlos, hay que quitarlos del desplegable, no solo del paquete.

### 4. Verificado aquí frente a pendiente en máquina limpia

| comprobación | estado |
|---|---|
| Versión de Godot | ✅ verificado |
| Escena principal, renderer, iconos | ✅ verificado |
| Rutas `user://` sin absolutas | ✅ verificado |
| Degradación sin Python | ✅ verificado en código |
| Preset versionable sin datos personales | ✅ creado |
| Ficheros de datos incluidos en el paquete | ✅ **corregido** (D-4); antes ninguno |
| Gráficas PNG / dashboard en un build | ❌ **rotas** (D-3), no es un problema de preset |
| **Generación del ejecutable** | ❌ **bloqueado**: sin plantillas |
| **Arranque del ejecutable** | ❌ no ejecutable aún |
| **Instalación en máquina Windows limpia** | ❌ **pendiente**, requiere otra máquina |

**G5 = NO-GO, abierto.** Exportar un EXE no cerraría el gate por sí solo: el
criterio del plan es que *otra* máquina pueda instalar y ejecutar la misma
versión sin el entorno de desarrollo, y eso no se puede comprobar aquí.

---

## G4 · Estabilidad visual y funcional

### 5. Matriz de prueba para los cinco escenarios de G0

Leyenda: **H** verificable headless · **V** requiere observación visual humana ·
✅ verificado · ⏳ pendiente

| # | comprobación | tipo | estado |
|---|---|---|---|
| 1 | El escenario carga sin errores de validación | H | ✅ **5/5, 0 errores** |
| 2 | Avisos de revisión declarados | H | ✅ **5/5 con 0 avisos** tras cerrar D-1 y D-2 |
| 3 | La plantilla runtime carga en el motor | H | ✅ 5/5 |
| 4 | Ejecución de 120 s sin excepción | H | ✅ 5/5 |
| 5 | HRR y FED evolucionan | H | ✅ 5/5 |
| 6 | Los cinco interruptores siguen apagados | H | ✅ **5/5, 0 ON** |
| 7 | Sin procesos Godot residuales | H | ✅ 0 |
| 8 | Editor → escenario → simulación (flujo) | H | ✅ vía `validate_editor_to_sim_flow` |
| 9 | Reproducibilidad de ejecución | H | ✅ vía `check_product` |
| 10 | Guardar / cargar / reabrir desde la interfaz | **V** | ⏳ |
| 11 | Vista 2D: planta, aberturas, etiquetas | **V** | ⏳ |
| 12 | Vista 3D: geometría y transición desde 2D | **V** | ⏳ |
| 13 | Primera persona: movimiento, escaleras, colisión | **V** | ⏳ — ya **posible en los 5**; antes 2 no tenían por dónde entrar |
| 14 | Humo: densidad, capa, visibilidad | **V** | ⏳ |
| 15 | Aberturas: abrir/cerrar en vivo | **V** | ⏳ |
| 16 | HUD: legibilidad, FED y índice de condiciones | **V** | ⏳ |
| 17 | Gráficas nativas y PNG | **V** | ⏳ |
| 18 | Ejecución prolongada (>15 min) con memoria estable | **V/H** | ⏳ |
| 19 | Rendimiento (fps) en el escenario de 13 salas | **V** | ⏳ |
| 20 | Salida limpia de la aplicación | **V** | ⏳ |

**Nota de método:** existen pruebas manuales previas del usuario. Lo que falta no
es «probar la interfaz», sino una **campaña sistemática documentada** con
evidencia reproducible, que es lo que esta matriz organiza.

### 6. Resultados medidos (headless, 120 s por escenario)

| escenario | salas | aberturas | errores | avisos | t_sim | FED sala 0 | HRR máx | interruptores ON |
|---|---|---|---|---|---|---|---|---|
| `compact_apartment_reference` | 5 | 7 | **0** | 0 | 120,0 | 0,0066 | 631,2 kW | **0** |
| `preset_simple_house` | 6 | 11 | **0** | 2 | 120,0 | 0,0184 | 623,4 kW | **0** |
| `long_hallway_reference` | 6 | 8 | **0** | 0 | 120,0 | 0,0163 | 486,6 kW | **0** |
| `preset_two_storey_house` | 13 | 23 | **0** | 1 | 120,0 | 0,0024 | 617,6 kW | **0** |
| `two_storey_reference` | 8 | 12 | **0** | 0 | 120,0 | 0,0055 | 593,5 kW | **0** |

Sin crashes nativos, sin diálogos de error, **0 procesos residuales**, con
lanzador seguro y temporales aislados.

Los avisos de la columna «avisos» eran D-1 y D-2. Tras corregirlos, los cinco
escenarios del ámbito G0 salen con **0 avisos** (§7.2). El resto de la tabla no
se ha vuelto a medir en esta pasada: solo cambian los dos escenarios tocados, y
sus cifras nuevas están en §7.2.

### 7. Defectos y carencias observados

| # | hallazgo | escenarios | estado |
|---|---|---|---|
| **D-1** | **Sin punto de inicio en primera persona** | `preset_simple_house`, `preset_two_storey_house` | **corregido en datos**, pendiente de comprobación visual |
| **D-2** | Sin foco de ignición declarado | `preset_simple_house` | **CERRADO**: foco declarado y casos FDS byte a byte idénticos |
| **D-3** | El generador de gráficas no puede funcionar en un build exportado | todos | **abierto**, no corregido |
| **D-4** | La plantilla de exportación no incluía ningún fichero de datos | — | **corregido** en `export_presets.cfg.template` |
| **D-5** | R2-1 no vigila `sim/templates/`, que sí mueve resultados de validación | — | **corregido**; R2-1 ahora da FAIL y pide regenerar |
| **D-6** | Los `scenarios/preset_*.json` versionados están desfasados respecto a su plantilla | los 10 presets | **abierto**, no corregido |

### 7.1 D-1 y D-2 — qué se ha cambiado y por qué

**Dónde está la fuente de verdad.** `scenarios/preset_*.json` no es un fichero
escrito a mano: lo **genera** `tools/export_presets_to_scenarios.gd` a partir de
`sim/templates/BuildingTemplate.gd`. Corregir solo el JSON dejaría la carencia
dentro del generador, lista para volver. La corrección está en la plantilla; el
JSON distribuido se ha puesto al día únicamente en los campos afectados.

**D-1, dónde empieza el jugador.** Los tres escenarios que ya funcionaban
arrancan siempre en la sala de circulación —`Pasillo distribuidor`, `Recibidor`,
`Pasillo PB`—, nunca en la sala del incendio. `player_start.position_m` es
**local a la sala** (`ScenarioDocument.set_player_start`, y
`FirstPersonController._place_at_entry` la vuelve a recortar contra el
rectángulo). Se ha seguido ese mismo criterio:

| escenario | sala de inicio | por qué esa sala | local (m) | mundo (m) | yaw |
|---|---|---|---|---|---|
| `preset_simple_house` | 1 `Pasillo` | las **cinco** puertas interiores dan a ella y lleva la puerta de entrada (muro `top`, centrada) | (0,75 · 0,75) | (5,75 · 0,75) | 180° |
| `preset_two_storey_house` | 1 `Recibidor distribuidor PB` | reparte a salón, cocina, aseo y lavadero, abre al hueco de escalera y lleva la puerta de entrada | (1,10 · 0,75) | (6,90 · 0,75) | 180° |

Ambos caen 0,75 m por dentro de la puerta de entrada —la misma distancia que usa
el motor cuando no hay `player_start` y entra por la puerta— centrados en el
ancho del pasillo y mirando hacia el fondo de la vivienda (`yaw 180°` = +y del
plano). Comprobado en ejecución, no supuesto:

| comprobación | `preset_simple_house` | `preset_two_storey_house` |
|---|---|---|
| dentro de la sala | sí | sí |
| holgura al muro más cercano | 0,75 m (radio del jugador: 0,24 m) | 0,75 m |
| objeto más cercano | 0,05 m, la alfombra del pasillo — **fuera de ella** | sin objetos declarados |
| es la sala del incendio | no | no |

**D-2, dónde empieza el fuego.** La sala es el **salón (id 0)**, y no por asumir
el fallback: es la sala con más carga de fuego de la casa (6000 MJ de 16 700),
es la que fijan los dos casos FDS de esta misma plantilla
(`sim/validation/cases/fds_simple_house_{default,calibrated}.json`,
`ignition_room_id: 0`) y es la que usa la variante por objetos
`scenarios/simple_house_objects.json`. Dentro de la sala, el objeto marcado es
`salon_sofa`, **el mismo que ya marcaba** `simple_house_objects.json`.

Esto sí cambia el comportamiento. Sin marca, el motor elegía por puntuación
(`CombustionSystem._select_room_ignition_object`) y salía **`salon_alfombra`**:
la alfombra, por tener la temperatura de ignición más baja de la sala (275 °C
frente a 310 °C del sofá). Es decir, el incendio arrancaba en una alfombra por
un efecto lateral de la heurística, que es exactamente lo que el aviso
denunciaba.

### 7.2 Medición antes y después (120 s por escenario, headless)

| medida | antes | después |
|---|---|---|
| `preset_simple_house` · avisos | **2** | **0** |
| `preset_simple_house` · objeto de ignición | `salon_alfombra` | `salon_sofa` |
| `preset_simple_house` · HRR máx | 628,8 kW | 629,2 kW (+0,06 %) |
| `preset_simple_house` · FED sala 0 | 0,0235 | 0,0235 |
| `preset_simple_house` · interruptores ON | 0 | 0 |
| `preset_two_storey_house` · avisos | **1** | **0** |
| `preset_two_storey_house` · objeto de ignición | `2p_salon_alfombra` | `2p_salon_alfombra` (sin cambio) |
| `preset_two_storey_house` · HRR máx | 622,6 kW | 622,6 kW |
| `preset_two_storey_house` · FED sala 0 | 0,0051 | 0,0051 |
| `preset_two_storey_house` · interruptores ON | 0 | 0 |

`preset_two_storey_house` no cambia nada de física: solo gana el punto de
inicio. Los cinco interruptores experimentales siguen apagados en los dos.

### 7.3 Efecto sobre los casos FDS — resuelto separando autoría de plantilla

**La causa.** Los dos casos FDS calibrados declaran `"template":
"simple_house"` y `CaseRunner._build_case_template` los construye con
`BuildingTemplate.create_by_name()` — la **misma** función de la que salía el
preset distribuido. No existía ninguna costura entre «plantilla que se valida» y
«escenario que se distribuye», así que marcar el sofá como foco dentro de
`create_simple_house()` llegaba también a la validación y movía el FED de
`fds_simple_house_default` hasta un 1,17 %. Ni `_build_case_template` ni
`_apply_template_overrides` copian `ignition_room_id` ni marcas de objeto desde
el caso: el foco venía **solo** de la plantilla, por eso el caso lo heredaba
entero.

**La costura.** `sim/templates/BuildingTemplate.gd` gana una capa explícita de
contenido de autor, `PRESET_AUTHORING`, y un punto de entrada
`create_product_preset()`:

| ruta | función | qué recibe |
|---|---|---|
| Generador de `scenarios/` (`tools/export_presets_to_scenarios.gd`) | `create_product_preset` | plantilla **+** autoría |
| Desplegable `preset://` del editor (`editor/ScenarioEditor.gd`) | `create_product_preset` | plantilla **+** autoría |
| «Nueva simulación» del menú (`sim/BuildingModel.gd:_ready`) | `create_product_preset` | plantilla **+** autoría |
| `sim/validation/CaseRunner.gd` | `create_by_name` | plantilla desnuda |
| `tools/run_scenario_headless.gd` | `create_by_name` | plantilla desnuda |
| resto de validadores y sondas de `tools/` | `create_by_name` | plantilla desnuda |

`create_simple_house()` y `create_two_storey_house()` vuelven a ser **byte a
byte** lo que eran: el diff de `BuildingTemplate.gd` es **99 inserciones y 0
supresiones**. La autoría no puede alcanzar la validación porque la validación
no pasa por la función que la aplica.

**Identidad demostrada, no tolerancia.** `fds_simple_house_default` reejecutado
(260 s) contra la ejecución previa al arreglo:

| artefacto | resultado |
|---|---|
| `sim_log.csv` | **idéntico** — `sha256 34cf79594be4da14…`, 1 409 664 B en ambos |
| `sim_log.txt` | **idéntico** |
| `events.json` | **idéntico** |
| `summary.json` | idéntico salvo `output_dir` (la carpeta temporal de cada ejecución) |

Para contraste, la versión anterior del arreglo —el sofá marcado dentro de la
plantilla— daba `sha256 19fcb17f5db55486…` y 1 409 625 B. No se acepta ninguna
desviación: se exige y se obtiene el mismo fichero.

**Y sigue declarado donde importa.** Comprobado en ejecución:

| | `create_by_name` (validación) | `create_product_preset` (producto) |
|---|---|---|
| `preset_simple_house` · avisos | 2 | **0** |
| `preset_simple_house` · objeto marcado | ninguno | `salon_sofa` |
| `preset_simple_house` · `ignition_room_id` | ausente | 0 |
| `preset_two_storey_house` · avisos | 1 | **0** |
| `preset_two_storey_house` · inicio FP | ausente | presente |

**Sobrevive a una exportación.** Ejecutado el generador real
(`tools/export_presets_to_scenarios.tscn`): `preset_simple_house.json` sale con
`ignition_room_id: 0`, `salon_sofa` marcado y `player_start`, y
`preset_two_storey_house.json` con su `player_start`. Después se han revertido
los diez ficheros y se han vuelto a aplicar a mano solo los campos de D-1 y D-2,
para mantener D-6 separada (§7.6).

### 7.4 D-3 — el generador de gráficas no puede funcionar en un build

`SimulationEngine._launch_graph_generator` hace
`ProjectSettings.globalize_path("res://scripts/generate_fire_graphs.py")` (y lo
mismo con el dashboard HTML). En un build exportado `res://` vive dentro del
`.pck`, así que esa ruta **no existe en disco** y el proceso de Python no puede
arrancar, haya Python instalado o no. Incluir los `.py` en el paquete no lo
arregla: habría que extraerlos a `user://` antes de invocarlos, y eso es un
cambio de código, no de preset. La §1 de este documento decía que sin Python
«el resto funciona igual»; eso sigue siendo cierto, pero **con** Python las
gráficas tampoco saldrán en el build hasta que se arregle esto.

### 7.5 D-5 — R2-1 ya cubre `sim/templates/`

`scripts/simulation/validation_guardrails.py` listaba como rutas que invalidan
`reference_checks.json`: `sim/core`, `sim/fire`, `sim/building`,
`sim/resources` y `sim/validation/cases`. Su propio comentario decía «motor
GDScript, **presets** y definiciones de casos», pero los presets viven en
`sim/templates/`, que no estaba. Esta fase lo demostró de la peor manera: un
cambio solo ahí movió el FED de un caso FDS casi un 1 % con R2-1 en verde.

**Corregido:** `sim/templates` entra en `_ENGINE_PATHS`. No se ha tocado ningún
umbral, tolerancia ni valor de referencia; solo se amplía qué cuenta como
cambio de motor.

**Prueba de mutación** (`tests/test_guardrails.py`, cuatro casos nuevos sobre un
repositorio git aislado, sin Godot):

| prueba | qué demuestra |
|---|---|
| `test_sim_templates_is_guarded` | la ruta está en el contrato |
| `test_rc1_uncommitted_template_change_without_regeneration` | un cambio sin commitear en la plantilla da **FAIL** y nombra el fichero |
| `test_rc1_template_committed_after_report` | un commit de plantilla posterior al reporte da **FAIL** |
| `test_template_mutation_fails_then_restores_byte_for_byte` | verde → mutación → **rojo** → restauración → verde, con SHA-256 del fichero restaurado igual al original |

La mutación que usa la prueba es del mismo tipo que abrió D-5: añadir
`is_primary_ignition_source` a la plantilla.

**Consecuencia inmediata, y es la correcta:** con `sim/templates/BuildingTemplate.gd`
modificado y sin commitear, **R2-1 da FAIL ahora mismo** y pide regenerar
(§8). Es el guardarraíl haciendo su trabajo por primera vez en esta ruta.

**Observación colateral, no corregida:** `sim/BuildingModel.gd` está en la raíz
de `sim/`, no dentro de `sim/building/`, así que **tampoco lo cubre R2-1**. Esta
fase lo modifica (un cambio de llamada, sin física) y el guardarraíl no lo
menciona. Ampliar la cobertura ahí es otra decisión, con su propia regeneración.

### 7.6 D-6 — los presets versionados están desfasados

Al regenerar con `tools/export_presets_to_scenarios.tscn`, los **diez**
`scenarios/preset_*.json` salen distintos de lo versionado, no solo los dos de
esta fase: aparecen `building_total_floors`, `leakage_class: "none"` en cada
abertura, `wind_speed_m_s`/`wind_direction_deg`, las plantas pasan de `PB`/`P1`
a `R`/`R+1`, y dos ficheros cambian de sangrado. Es deriva de esquema acumulada
desde la última exportación. Se ha visto además que el generador escribe los
`float` con precisión de 32 bits (`1.10000002384186` donde el origen dice
`1.10`), así que una regeneración masiva movería también decimales sin que
cambie nada real. **He revertido los ocho ajenos** y he aplicado a
mano solo los campos de D-1 y D-2, para que el diff de esta fase sea exactamente
la corrección pedida. La puesta al día del resto es una tarea aparte, con su
propia medición.

---

## 8. R2-1: bloqueo inicial y cierre posterior

En la primera pasada, con solo 4,86–4,94 GB libres, la regeneración no se lanzó:
`sim/templates/BuildingTemplate.gd` estaba modificado y R2-1 fallaba por
frescura, no por un resultado científico. Se conservó ese rojo hasta disponer
de memoria suficiente.

El 25-09, junto al cierre P3b descrito en
[E1 §8.7](../validation/E1_O2_BASE_DE_MASA_2026-09-25.md), la referencia se
regeneró bajo monitor y terminó PASS. `reference_checks.json` solo cambió en
`generated_at`: **346/346 requeridos PASS, 78 gaps**, todas las métricas
idénticas. R2-1 está verde con las modificaciones de `sim/templates`,
`sim/BuildingModel.gd` y `sim/core` presentes. El informe debe incluirse en el
mismo commit que esos cambios para conservar la frescura tras el commit.

Después, `check_product.py` pasó 165/165 y la suite Python global terminó con
3002 passed, 9 skipped, 2 xfailed y 42 subtests; el test real de guardarraíles
ya no falla. Esto no cierra la observación visual G4 ni la exportación G5.

## Estado de los gates

| gate | estado | qué falta |
|---|---|---|
| **G4** | **ABIERTO** | 11 de 20 comprobaciones requieren observación visual humana. D-1 y D-2 están cerrados **en datos**, no visualmente: nadie ha entrado todavía en primera persona en esos dos escenarios |
| **G5** | **ABIERTO, bloqueado** | plantillas de exportación; después, build, D-3 y máquina limpia |

**Ningún gate pasa a PASS.** D-2 sí queda cerrado (§7.3), y D-5 corregido con
prueba de mutación (§7.5). D-1 sigue **corregido en datos y sin comprobar
visualmente**: es la fila 13 de la matriz y no la cierra ninguna ejecución
headless. Hace falta arrancar la interfaz, entrar en primera persona en
`preset_simple_house` y en `preset_two_storey_house`, y mirar. No se ha hecho
aquí por tres razones a la vez: el procedimiento de
[la auditoría de crashes](../validation/GODOT_471_HEADLESS_CRASH_AUDIT.md)
prohíbe lanzar el ejecutable gráfico directamente, la memoria libre está por
debajo de la referencia operativa, y una sesión gráfica no deja evidencia
observable sin alguien delante de la pantalla.

## Siguiente paso ejecutable

1. **Entrar en primera persona** en `preset_simple_house` y
   `preset_two_storey_house` y confirmar visualmente D-1 (fila 13). Es la única
   parte de D-1 que sigue sin evidencia.
2. **Instalar las plantillas de exportación de Godot 4.7.1** (1,19 GiB, §2). Es
   lo único que desbloquea G5 y se hace desde el propio editor.
3. **D-3**: decidir si las gráficas deben funcionar en el build. Si sí, hay que
   extraer los `.py` a `user://` antes de invocarlos.
4. **D-6**: poner al día los diez presets, con su propia medición (§7.6).
