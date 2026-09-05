# Handoff de la línea visual — X-8 cerrado (2026-09-01; cerrado el 2026-09-05)

> **X-8 QUEDÓ CERRADO EL 2026-09-05.** El usuario confirma en ejecución que el
> suelo del rellano, el techo del rellano y los pasillos de la vivienda están
> arreglados, y describe la causa: *«se superponía la capa trasera con la
> delantera»* — z-fighting entre superficies coincidentes, tal como se había
> deducido. Lo cierran `cbadf310`, `1909339b` y `e6712cb7`, ya en `origin/main`.
> **La bisección de §5 no llegó a hacer falta.** Este documento se conserva como
> registro de método: los tres fallos encadenados de §3 y las trampas de §5 son
> lo que sigue teniendo valor. El estado vivo está en
> [AUDITORIA_VISUAL_2026-08-29.md](AUDITORIA_VISUAL_2026-08-29.md).

Estado para retomar la línea visual en otra sesión. La línea del motor va aparte
y tiene su propio handoff en [HANDOFF_CURRENT_STATE.md](HANDOFF_CURRENT_STATE.md).

- **Rama**: `main`, árbol limpio salvo dos `.mp4` de grabaciones y unos `.uid`
  sin seguir de la línea motor.
- **HEAD**: FP-3 cerrada el 2026-09-03; antes de eso, `202ebada` — *fix(view):
  stop the live rebuild from killing the remote debugger*.
- **Suite**: `python scripts/check_product.py` → **32/33**. El único fallo es
  `test_exit0_real_json`, conocido y de la línea motor.
- **Documento vivo**: [AUDITORIA_VISUAL_2026-08-29.md](AUDITORIA_VISUAL_2026-08-29.md).
  Todo el detalle técnico está ahí; esto es solo el resumen para retomar.

---

## 1. Estado de los hallazgos

| Hallazgo | Estado | Quién lo puede mover |
|---|---|---|
| ✅ **X-8** — iluminación inestable en suelo del rellano y paredes del pasillo al mover la cámara | **CERRADO 2026-09-05**: superficies superpuestas (z-fighting), confirmado en ejecución | — |
| 🟠 **FP-3 (F5.1)** — unificar los constructores de suelo, techo, muro y hueco entre `FirstPersonController` y `Visualizer3D` | **CERRADA 2026-09-03** | — |
| ℹ️ **H-6** — autoexposición entre plantas | Declarado fuera del cierre | — |

Todo lo demás de §1-§8 de la auditoría está cerrado, y desde el 2026-09-05 X-8
también. **No queda ningún hallazgo abierto en la línea visual.**

### FP-3, cerrada

Lo que se unificó es el **reparto** de la geometría, no lo que emite cada vista:
el mundo FP levanta arquitectura recorrible con colisión y el visor 3D dibuja
una maqueta translúcida, y eso sigue separado a propósito. Cuatro módulos
nuevos en `view/geometry/` —`BuildingLevels`, `SlabGeometry`,
`WallSideGeometry` y `OpeningPlacement`— con el precedente de `StairGeometry`.

Al juntarlas salieron dos divergencias que ya existían: `_find_next_floor_level_above`
tenía dos contratos distintos para el caso de no haber planta encima (ahora el
valor de reserva viaja explícito en la llamada), y el mundo FP no entendía los
alias cardinales de `wall_side`, así que una ventana declarada al norte se
plantaba sobre el paramento derecho —0,80 m de desplazamiento en el caso
estrecho del guardarraíl, 1,70 m en el ancho— y además nunca llegaba a recortar
el muro. Guardarraíl: `tools/validate_view_geometry_parity.gd`, que monta las
dos vistas sobre el mismo edificio y compara el reparto con 1 mm de tolerancia.
El detalle está en la ficha FP-3 de §5 de la auditoría.

---

## 2. X-8: qué es y qué está descartado

Descripción del usuario: *"en el suelo del rellano aparece iluminación irregular
cuando muevo la cámara, con formas redondas, cuadradas, líneas de sierra... de
forma aleatoria"*, y lo mismo en las paredes del pasillo. Es **un solo fenómeno
en dos sitios**.

Dato de contexto que importa: el renderer es **`gl_compatibility`**
(`project.godot`), no Forward+.

**Encontrado y corregido en el rellano (2026-09-03), a partir de dos hipótesis
del usuario.** Las dos eran ciertas, medidas con
`tools/validate_landing_surfaces.gd` sobre el escenario que el usuario tenía
cargado (`simple_house` en modo **piso**, planta 1, día). Ojo al detalle que
invalidaba la nota anterior: *"el piso patrón no reproduce el fenómeno"* se
midió con `simple_house` como **unifamiliar**, y en unifamiliar **no existe el
rellano del portal**.

1. **Polígonos a la cota del suelo del rellano: tres, coplanarios exactos.**
   `ExteriorContext/DoorPorch_05` solapaba **2,04 m²** con el suelo del rellano
   a **0,0000 m** de desnivel, justo delante de la puerta de la vivienda: el
   porche de entrada se construía *sólo en pisos*, que es justo donde el
   rellano ya pone su propio solado, y a la misma cota exacta. Y los dos
   costados de la caja de escalera de la planta inferior remataban en la cara
   superior del forjado en vez de en su intradós, cruzando la losa en una
   banda de 0,10 × 2,64 m. Corregido; ya no queda nada compartiendo plano con
   ese suelo.
2. **Luz que entra: sí, pero la cocina aporta el 1,2 %.** El **51,2 %** de la
   luz del suelo del rellano viene de fuera atravesando las paredes, porque
   esas omnis no proyectan sombra. El grueso son tres rellenos globales
   (`FP_AmbientFill` 16,6 %, `CityFacadeFill_00` 15,8 %, `ExteriorSoftFill`
   12,2 % = **44,6 %**). Queda medido y **sin tocar**: encender sombras ahí es
   una decisión de coste que afecta a toda la escena.

3. **El techo del rellano tenía el fallo espejo**, y la medianera del pasillo
   uno mucho mayor. Los costados de la caja de escalera de la planta superior
   arrancaban en el intradós del techo en vez de en su trasdós. Y sobre todo:
   **13,44 m² de tabique duplicado entre el pasillo y las habitaciones**. El
   descarte de FP-1 comparaba la caja entera, y eso sólo casa cuando las dos
   salas parten el muro por los mismos sitios; un pasillo no lo hace nunca,
   porque su lado corre a lo largo de varias habitaciones mientras cada
   habitación corta en su propio borde. Corregido llevando por plano qué
   trozos ya tienen fábrica y levantando sólo el hueco que quede.

Para X-8 lo que importó fue la distinción: **una fuga de luz da un brillo
constante equivocado, no un parpadeo**. Lo que cambia al mover la cámara es el
z-fighting, así que de las dos hipótesis la que explicaba el síntoma era la
primera — y así resultó ser. **Confirmado por el usuario en ejecución el
2026-09-05**, tras corregir además el techo del rellano y el tabique duplicado
del pasillo.

El sospechoso de reserva no llegó a hacer falta y queda sin tocar: el plano de
fachada acumula 37,83 m² de superficies coincidentes entre `WallMesh`,
`ExteriorWallSkin` y `OwnFacade`. Están enterradas, no se ven, y ya no hay
síntoma que las señale.

**Descartado con evidencia:**

- **La sombra del sol.** El usuario confirmó que seguía igual tras bajar el
  filtro a calidad 0, subir el bias a 0,18 y acortar el alcance a 15 m. En banco,
  apagar la sombra del todo da 11,46 % de píxeles inestables frente a 10,66 %:
  no mejora.
- **Cámara quieta**: 0,00 % de píxeles inestables. La escena es perfectamente
  estática; el fenómeno depende del movimiento de cámara.
- En banco tampoco tuvieron efecto el límite de luces por objeto (8 → 32), la
  oclusión de contacto ni el ruido de superficie.
- `show_smoke_volume` queda descartado: es el único de los cinco interruptores
  del primer intento que sí se aplicaba en vivo.

**Advertencia sobre esas cifras**: al girar 0,4° con 75° de campo la imagen se
desplaza unos 8 px, así que la métrica global mide sobre todo movimiento
legítimo. La conclusión que se sacó entonces —*"el piso patrón no reproduce el
fenómeno"*— era **falsa**, y costó dos días: se midió con `simple_house` como
unifamiliar, donde no existe el rellano del portal. Corriéndolo como **piso**
sí reproduce. Las correcciones de sombra se conservan porque son defendibles
por sí mismas, no porque estén verificadas como solución de esto.

---

## 3. Tres fallos de método encadenados (para no repetirlos)

Ninguno de los tres era del usuario. Los tres impidieron que la bisección
llegara a dar un solo dato.

1. **Interruptores que solo se leen al construir** (`b962cbc2`). Se pidió apagar
   cinco desde el inspector remoto; cuatro solo se consultan al crear materiales
   y luces, así que tocarlos en caliente no hacía nada. Corregido con setters
   que reconstruyen en vivo.
2. **La reconstrucción deshacía el cambio** (`9879ff0f`). Esos setters llamaban a
   `rebuild_from_building()`, que pasa por `_apply_startup_lighting_options()`, y
   esa función **reescribe** `room_ceiling_lights_enabled` y
   `exterior_lighting_mode` desde el edificio: apagar las luces de techo las
   volvía a encender sola dentro de la misma reconstrucción. Además
   `_place_at_entry()` devolvía al jugador a la puerta en cada cambio, que es lo
   contrario de lo que necesita una comparación.
3. **La reconstrucción tumbaba el depurador** (`202ebada`). Al primer intento
   real, cambiar `exterior_sky_light_cast_shadows` y luego
   `room_ceiling_lights_enabled` mató la conexión:

   ```
   ERROR: Malformed packet received, not an Array.
   ERROR: Remote debugger: Packet too large (1836020852 > 8388612 bytes). Disconnecting.
   --- Debugging process stopped ---
   ```

   Ese tamaño no es real: es basura leída de un stream ya desincronizado. La
   reconstrucción corría **dentro de la llamada que asigna la propiedad**, y
   cuando esa llamada viene del inspector remoto quien la ejecuta es el
   depurador; liberar y recrear cientos de nodos en mitad de su callback le
   rompe el stream.

**Lección transversal, ya escrita como guardarraíl**: un `@export` que solo se
lee al construir el mundo *parece* editable y no lo es, y eso es justo lo
contrario de la regla del proyecto.

---

## 4. Estado del instrumental tras esos arreglos

En `view/fp/FirstPersonController.gd`:

- `_rebuild_if_live()` **solo encola** (guarda `_rebuild_queued`); el trabajo
  vive en `_rebuild_live_deferred()`, que corre al final del frame, fuera del
  callback del depurador, y agrupa en una sola reconstrucción todos los
  interruptores tocados en el mismo frame.
- Esa reconstrucción **no** reaplica las opciones de arranque y **conserva
  posición, guiñada y cabeceo**: se compara desde el mismo punto de vista.
- El guard de reentrada cubre también `rebuild_from_building()`, `setup()` y
  `apply_preset()`. Sin eso, ahora que esas propiedades tienen setter, cada
  reconstrucción normal disparaba otra anidada dentro de sí misma, y aplicar un
  preset una por cada propiedad asignada.
- Se aplican en vivo, además de los del commit anterior: `ambient_fill_enabled`,
  `room_ceiling_lights_cast_shadows`, `opening_lights_cast_shadows`,
  `exterior_context_enabled`, `exterior_lighting_mode`,
  `exterior_facade_fill_enabled`, `exterior_procedural_sky_enabled`,
  `exterior_own_facade_enabled`, `exterior_window_obstacles_enabled`,
  `opposite_facade_enabled`.

En `tests/test_godot_editability.py`, dos guardarraíles nuevos:

- `test_build_time_fp_knobs_apply_live`: exige setter con `_rebuild_if_live()` en
  cada uno de esos interruptores.
- `test_live_rebuild_does_not_undo_the_inspector`: exige que el setter solo
  encole y que el trabajo diferido no reaplique las opciones de arranque ni
  reubique al jugador.

---

## 5. La bisección — no llegó a hacer falta (registro de método)

> Se conserva porque el procedimiento y sobre todo **sus trampas** valen para el
> próximo síntoma visual. X-8 se cerró antes de ejecutarla.

Colocarse donde el artefacto se vea bien (suelo del rellano o pared del
pasillo), moverse un poco para confirmar que está, y apagar **uno cada vez**
sobre `FirstPersonController`.

| Paso | Interruptor | Qué elimina | Si el artefacto desaparece |
|---|---|---|---|
| 1 | `Exterior FP > exterior_context_enabled` | **todo el exterior de una vez**: sol, ciudad, fachadas, luces de ventana, cúpula | es exterior → pasos 2-4 |
| 2 | `exterior_sky_light_cast_shadows` | solo las sombras del sol | sombra del sol (ya descartada una vez) |
| 3 | `exterior_window_obstacles_enabled` | edificios de enfrente y sus luces de ventana | recuento de luces omni por objeto |
| 4 | `exterior_own_facade_enabled` / `opposite_facade_enabled` | fachadas casi coplanarias con el muro | z-fighting entre paramentos |
| 5 | `Iluminacion FP > room_ceiling_lights_enabled` | luces de techo de cada sala | luces interiores |
| 6 | `ambient_fill_enabled` | la omni ambiental global | el relleno ambiental |
| 7 | `Materiales FP > use_procedural_surface_noise` y `surface_contact_ao_enabled` | ruido de superficie y oclusión de contacto | material (ya medido sin efecto en banco) |

El paso 1 es el que más información da. **Si el artefacto sigue ahí con el
exterior apagado, saltar directo al paso 5.**

### Dos vías, y sus trampas

**A) Inspector remoto.** Rápido: no hay que relanzar y no mueve al jugador de
sitio. Debería aguantar ya con la reconstrucción diferida, pero es la vía que
tumbó la conexión una vez.

**B) Sin depurador (recomendada).** `FirstPersonController` existe como nodo en
`scenes/SimulationScene.tscn`. Se deja el interruptor puesto en la escena con el
juego parado y se arranca con F5: una relanzada por paso, cero riesgo de
desconexión.

> **Trampa de la vía B**: `room_ceiling_lights_enabled` y
> `exterior_lighting_mode` **no** se pueden fijar desde la escena, porque
> `_apply_startup_lighting_options()` los impone desde el escenario en cada
> arranque. Para el paso 5 hay que usar la casilla de luces interiores del editor
> de escenarios (`interior_lights_on` en el JSON del escenario), y para día/noche
> el modo del propio escenario. El resto de la tabla sí se puede dejar puesto en
> la escena sin que nadie lo pise.

### Si ningún paso lo elimina

No es iluminación. Los dos sospechosos que quedan:

1. **Z-fighting** entre superficies coincidentes. Encaja con todo lo observado:
   estable con la cámara quieta, cambiante al moverla, indiferente a apagar
   sombras, luces, AO y ruido, y con formas irregulares de borde de sierra. La
   cámara FP usa `near = 0.03` con `far` por defecto, y la escena llega hasta la
   cúpula de 160 m.
2. **Orden de transparencias del overlay 3D**. En primera persona el visor 3D
   sigue corriendo como overlay: `_apply_overlay_visibility()` oculta
   `_rooms_root`, `_openings_root`, etiquetas, Sun y FillLight, pero mantiene
   **`_atmosphere_root` visible**. Ahí viven las capas de humo, que son láminas
   transparentes grandes.

---

## 6. Cabos sueltos menores

- **Grabación de las 00:38** (`Grabación 2026-09-01 003800.mp4`, 13 s, visor 3D):
  se ve una sala en primer plano casi completamente **negra**. No está registrado
  en la auditoría y no se llegó a preguntar de qué iba. La otra grabación
  (`001802.mp4`, 63 s) es la que ya se usó para diagnosticar X-4 y X-7.
- Ninguna de las dos está en git, y son grandes (53 MB y 5 MB).

---

## 7. Verificación

```
python scripts/check_product.py                      # 32/33, fallo conocido de motor
python tests/test_godot_editability.py               # 15/15
<godot> --headless --path . res://tools/validate_view_geometry_parity.tscn
<godot> --headless --path . res://tools/validate_landing_surfaces.tscn
<godot> --headless --path . --check-only --script view/fp/FirstPersonController.gd
```

`validate_landing_surfaces` sirve además como sonda: imprime todas las caras
coplanarias del rellano y el reparto de la luz sobre su suelo, así que para
mirar otro escenario basta cambiar sus constantes de cabecera.

Binario: `C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe`. En Git
Bash el stdout de Godot a veces no llega al pipe: volcar a fichero
(`> .test_tmp/x.txt 2>&1`) y leerlo.

**Nota de método que ya se ganó dos veces**: con síntomas visuales, pedir al
usuario que señale sobre su propio fotograma resuelve en un mensaje lo que tres
rondas de deducción no resuelven.
