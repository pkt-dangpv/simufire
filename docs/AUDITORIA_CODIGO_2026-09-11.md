# Auditoría del código visual y de UI — 2026-09-11

El usuario lo pidió así: *«audita el trabajo realizado en estas sesiones. revisa
código, que quede limpio y conforme a las reglas de buenas prácticas de
programación»*, con autorización para **auditar y arreglar todo el código de la
parte visual y de UI**.

Esta auditoría no opina: **mide**. Se escribieron dos medidores, se corrigieron
*los medidores* cuando mentían —que pasó dos veces— y solo después se tocó una
línea de código.

Superficie: `editor/`, `view/`, `ui/` y `sim/building/` — **76 ficheros `.gd`**,
1,5 MB, 1552 funciones.

---

## 1. Resumen

| | antes | después |
|---|---:|---:|
| Reglas de estilo rotas | 16 | **0** |
| Funciones privadas que nadie llama | 9 | **0** |
| Pares de funciones casi idénticas (≥86 %, ≥5 líneas) | 21 | **4** |

Los 4 pares que quedan se dejan **a conciencia**, y el §6 dice por qué cada uno.
El §7 cuenta el hallazgo que no buscaba nadie: un guardarraíl que decía `PASS`
sin haber comprobado nada.

Y dos fallos latentes que aparecieron al quitar las copias: un nombre de nodo que
Godot no admite (§4.1) y las dos vistas construyendo la misma ficha del mobiliario
con **una diferencia ya metida** (§4.2).

---

## 2. Cómo se ha medido, y las dos veces que el medidor mintió

El medidor de estilo (`scripts/check_gdscript_style.py`) dio **119 hallazgos** en
su primera pasada. **103 eran suyos, no del código**:

- **95 «función sin tipo de retorno»**: leía solo la primera línea de la firma, y
  este repositorio parte las firmas largas en varias líneas con el `->` al final.
  Ninguna de esas 95 estaba mal.
- **5 «marca TODO»**: `TODO` es también la palabra castellana *todo*, y aquí se
  comenta en castellano. Ahora la regla exige que vaya seguida de dos puntos o
  paréntesis, que es como se escribe la marca de verdad.
- **9 «parámetro sin tipo»**: partía la lista de parámetros por comas, y un valor
  por defecto como `Color(1, 1, 1)` lleva comas dentro: un parámetro se contaba
  como tres.

Es exactamente la lección de D-6, aplicada a sí misma: **una sonda que miente en
un detalle obliga a verificar todo lo que enseña**. Corregido el medidor, quedaron
**16 hallazgos reales** — y uno de esos dieciséis también resultó falso (§3.4).

---

## 3. Lo que se ha arreglado

### 3.1 Nueve funciones privadas que nadie llamaba

63 líneas de código muerto. No es solo peso: **una de ellas era la versión vieja
y con el fallo** de una función que sí se usa.

| función | dónde | qué era |
|---|---|---|
| `_outflow_color` | `view/3d/smoke/SmokeOpeningCurtain3D.gd` | **La versión con el fallo.** Mezclaba hasta un **58 %** hacia el naranja con constantes clavadas; sus dos hermanas vivas usan un `tint` ajustable. El comentario que tiene justo encima explica ese mismo 58 % como la causa de que el vano se leyera «como una caja anaranjada». Se quedó ahí, esperando a que alguien la copiara. |
| `_interact_with_nearest_opening` | `view/fp/FirstPersonController.gd` | La interacción **vieja**, de abrir/cerrar de golpe (0 ó 1), sustituida por la de mantener pulsado con pasos de apertura. |
| `_next_opening_fraction` | `view/fp/FirstPersonController.gd` | Envoltorio de una línea de la misma época. |
| `_shared_side` | `view/fp/FirstPersonController.gd` | Envoltorio de un envoltorio: llamaba a `_shared_side_data`, que llama a `WallSideGeometry.shared_side`. |
| `_select_stair_turn_option` | `editor/ScenarioEditor.gd` | **La cuarta copia** del mapa modo↔item del desplegable de escaleras (§3.2). |
| `_update_stair_angle_label`, `_close_preview_3d`, `_bind_check_row` | `editor/ScenarioEditor.gd` | Delegadores de una línea sin ningún llamante. |
| `_center_on_side` | `view/furniture/FurnitureRoomLayout.gd` | Ayudante de colocación que ya no usa nadie. |

### 3.2 El desplegable de giro de escalera: un mapa de tres entradas, escrito cuatro veces

`auto` / `recta` / `180°` ↔ ids `0` / `1` / `2` estaba en cuatro sitios: al poblar
el desplegable, al traducir de modo a id, al traducir de id a modo, y en la
función muerta del §3.1. Ahora hay **una tabla ordenada** —`STAIR_TURN_MODES`,
donde la posición *es* el id— y las etiquetas pasan además por `tr()`, que antes
no lo hacían.

Cuatro copias de un mapa de tres entradas es como se acaba con un desplegable que
enseña una cosa y guarda otra.

### 3.3 Cuatro parámetros sin tipo

`building` en tres funciones de `view/furniture/` (se usa como `BuildingModel`, y
ahora lo dice) y `rid` en `ui/charts/NativeChartsWindow.gd` (es un `int`, y de
paso `_room_ids` pasa a `Array[int]`).

### 3.4 Y uno que no era un fallo

El único `print()` de la línea visual está dentro de
`_log_fp_temperature_diagnostics` y gobernado por `@export var fp_debug_temp_log`,
que es **exactamente la regla de la casa**: lo que se pueda gobernar desde el
editor, se gobierna desde el editor. La regla del medidor se ajustó para no
contarlo, en vez de mutilar el diagnóstico.

---

## 4. Las copias, y los dos fallos que escondían

De **21 pares** casi idénticos a **4**. Lo importante no es el número: es que
varios eran **la misma función en las dos vistas**, que es el mecanismo exacto que
ya se pagó en FP-3 —una ventana declarada al norte plantada sobre el paramento
derecho porque cada vista resolvía el dato a su manera—.

Tres módulos nuevos recogen lo que estaba repartido:

| módulo | qué recoge | copias que había |
|---|---|---|
| `sim/ScenarioValues.gd` | Leer un `Vector2` del formato guardado. | **6**, en tres capas |
| `view/ViewScenarioRead.gd` | Lo que las tres vistas leen del mismo escenario: registros por id, la caja de las salas, la posición de un detector o víctima, el estado de un mueble y **la ficha completa del mobiliario**. | 2-3 cada una |
| `view/3d/geometry/MeshFactory.gd` | Las piezas sueltas de una escena 3D: una caja, un material, metros→mundo y un nombre de nodo válido. | 2 cada una |

Además: el `stylebox` del editor era byte a byte el de `SimuFireTheme`; el atajo
de teclado de play/pausa del HUD era una copia del manejador del botón; los dos
buscadores de ancla del mobiliario diferían solo en un filtro, que ahora es un
argumento con nombre; y la regla «para ocultar una fila se oculta la caja, no el
mando» estaba en el editor y en su panel de propiedades.

### 4.1 Un nombre de nodo que Godot no admite

Las dos versiones de «límpiame este texto para usarlo como nombre de nodo» no
limpiaban lo mismo. La del rellano (`RoomShellFactory._safe_name`) **dejaba pasar
los dos puntos**, que Godot **no admite** en el nombre de un nodo: una sala
llamada `Salón: grande` daba un nombre inválido, Godot lo renombraba por su
cuenta, y quien después buscara ese nodo por su nombre no lo encontraría. La
versión de primera persona sí los limpiaba.

Al juntarlas se ha conservado la estricta. El fallback sigue siendo distinto
—`"room"` y `"marker"`— y ahora viaja como argumento, porque esa diferencia sí
tiene sentido.

### 4.2 Las dos vistas ya habían empezado a separarse

`_build_static_fuel_object_snapshots` (visor 3D) y
`_build_static_fp_fuel_object_snapshots` (primera persona) construyen la ficha de
cada mueble —id, sitio, medidas, carga de fuego, HRR y en qué estado arde— con
**catorce campos copiados a mano**. Y ya no eran iguales: la de primera persona
**se salta los objetos `room_proxy_`** y la del visor no.

Catorce campos duplicados es un campo nuevo que llega a una sola vista. Ahora hay
un constructor único y la diferencia tiene nombre: `skip_room_proxies`, que
primera persona pasa en `true` — un `room_proxy_` no es un mueble, es la carga de
fuego de la sala repartida.

---

## 5. La red que lo mantiene

`scripts/check_gdscript_style.py`, **en la suite**. Ocho reglas, y cada una se
puso después de encontrar el fallo que describe, no por gusto. Probado con cuatro
mutaciones, las cuatro cazadas:

| mutación | qué dijo |
|---|---|
| una función privada que nadie llama | `funcion privada que nadie llama 1` |
| un parámetro sin tipo y sin tipo de retorno | `parametro sin tipo` + `funcion sin tipo de retorno` |
| espacios al final de línea | `espacios sobrantes al final de linea` |
| una función pegada a la anterior | `funcion sin dos lineas en blanco delante` |

Una regla que no se vigila vuelve: el hueco de separación que se arregló en el
§3 llevaba ahí desde antes de esta tanda, en `main`.

---

## 6. Lo que se deja a conciencia

**Cuatro pares casi idénticos que NO se han tocado**, y el motivo de cada uno:

1. **`distance_to_segment`** (`editor/PlanGeometry.gd`) y
   **`distance_point_to_segment`** (`view/2d/openings/OpeningGeometry2D.gd`). Es
   una fórmula cerrada de seis líneas, sin un solo parámetro libre: no puede
   derivar. Juntarlas obligaría a meter geometría del plano en `sim/`, que es la
   única capa de la que pueden depender las dos
   (`docs/architecture/MODULE_BOUNDARIES.md`), y eso es peor que la copia.
2. **`body_font`** y **`title_font`** (`ui/SimuFireTheme.gd`): dos tipografías
   distintas con la misma forma. Son paralelas a propósito.
3. **`create_flame`** y **`create_ceiling_cap`** (`view/3d/fire/FireMaterialFactory.gd`):
   igual, dos materiales hermanos.

**Y dos copias que están en la línea del motor, que no es la que se ha autorizado
tocar aquí.** Quedan reportadas para quien trabaje esa línea:

- `sim/BuildingModel.gd::_vector2_from_variant` es **la sexta copia** del lector
  de `Vector2`. `sim/ScenarioValues.to_vector2` ya existe y está en su misma capa:
  es cambiar el cuerpo por una llamada.
- `sim/fire/CombustionSystem.gd` (sobre la línea 2450) tiene **una tercera copia**
  del mapa estado→nombre (`"pyrolyzing"`, `"flaming"`…). Esa importa más que las
  otras: sus nombres acaban en los informes de validación, así que una deriva
  entre esa copia y la de las vistas cambia lo que se lee en un informe sin que
  falle nada.

---

## 7. El hallazgo mayor: un guardarraíl que aprobaba sin mirar

Apareció por accidente, midiendo otra cosa. `validate_landing_surfaces` tardaba
**126 s** y la suite le daba 60, así que la reventaba con un `TimeoutExpired`.
Para saber si la culpa era de esta tanda se hizo un A/B: restaurar `view/` a
`HEAD` y volver a medir. Salió **8 s** y con `LANDING SURFACES VALIDATION PASS`.

Y ese 8 s era mentira. En esa pasada **cuatro scripts no compilaban** —la versión
de `HEAD` no tenía aún la función pública que el controlador ya llamaba— y la
comprobación imprimió `PASS` igualmente:

```
SCRIPT ERROR: Parse Error: Static function "is_ventilation_limited_regime()" not found
ERROR: Failed to load script "res://tools/validate_landing_surfaces.gd"
SCRIPT ERROR: Invalid call. Nonexistent function 'new' in base 'GDScript'.
...
LANDING SURFACES VALIDATION PASS
```

**El mecanismo**: Godot no devuelve código de error cuando un script del que
depende la comprobación no compila. La comprobación arranca, sus `new()` devuelven
`null`, nadie apunta un fallo, la lista de fallos queda vacía y el guardarraíl
imprime su `PASS` **sin haber construido ni un mundo**. Un guardarraíl que aprueba
sin mirar es peor que no tenerlo: parece una red.

Repasados los 49 guardarraíles, **27 no cuentan en ningún sitio cuánto trabajo
llegaron a hacer**, así que podrían caer en lo mismo. Arreglarlos de uno en uno
sería mucho ruido y dejaría el agujero abierto para el siguiente, de modo que el
arreglo va en **dos sitios**:

1. **En la comprobación que lo destapó**: `validate_landing_surfaces` cuenta los
   casos que de verdad ha medido y falla si no son los siete. Probado con
   mutación —romper el nombre de una función de `FPVisibilityOverlay`—: antes
   decía `PASS`, ahora dice *«solo se midieron 0 de los 7 casos: algo impidió
   montar el mundo (¿un script que no compila?)»* y devuelve 1.
2. **En la suite, para las 49**: si en la salida de Godot hay un fallo de
   compilación —`Parse Error:`, `Compile Error:`, `Failed to compile depended
   scripts`, `Compilation failed`, `Failed to load script`—, **el token de éxito
   no vale** y la comprobación cuenta como fallida. Un `push_error` normal, como
   el `VALIDATION FAILED` de un guardarraíl que sí ha mirado, no dispara la regla.

### El límite de tiempo, y lo que tapaba

Y una conclusión del A/B que también importa: **los 126 s no los ha traído esta
tanda**. Con `view/` en `HEAD` y compilando de verdad, la misma comprobación tarda
**130 s** y calcula los mismos sólidos (886, 780, 651, 710, 1056, 761, 909). Es la
comprobación más cara del repositorio —monta el mundo FP siete veces y lanza 2448
rayos en cada una—, y no era la única: `validate_furniture_layout` tarda **101 s
con mi código y 101 s con el de `HEAD`**, midiendo las mismas 318 piezas.

Dos cosas estaban mal en la suite, y ninguna era el código medido:

1. **El límite por defecto de 60 s no da para las comprobaciones pesadas de esta
   máquina.** Sube a **300 s**, con la medición escrita al lado. Un límite
   generoso solo cuesta tiempo cuando algo se cuelga de verdad; uno corto
   convierte una comprobación lenta en un fallo que no existe — y me costó dos
   ejecuciones completas creer que había roto algo.
2. **Un límite superado tumbaba la suite entera.** `subprocess.run(timeout=…)`
   lanza `TimeoutExpired`, nadie lo capturaba, y la ejecución moría con un
   traceback perdiendo el resultado de **todas** las demás comprobaciones. Ahora
   es **una comprobación fallida** con su mensaje —*«se pasó del límite de N s»*—
   y la suite sigue. Verificado poniéndole 1 s a una comprobación buena.

---

## 8. Lo que esto no era

No se ha tocado el comportamiento a propósito en ningún sitio salvo los dos
fallos del §4, y los dos van en la dirección de lo que ya hacía la mitad correcta.
Hay un tercer cambio de comportamiento, pequeño y deliberado, que viene de la
tanda de D-1 y está documentado en el §19.4 de `AUDITORIA_EDITOR_2026-09-06.md`:
un marcador de una sala sin rectángulo ya no se pinta en el origen del plano.
