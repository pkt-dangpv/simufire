# Handoff de la línea visual — X-8 abierto (2026-09-01)

Estado para retomar la línea visual en otra sesión. La línea del motor va aparte
y tiene su propio handoff en [HANDOFF_CURRENT_STATE.md](HANDOFF_CURRENT_STATE.md).

- **Rama**: `main`, árbol limpio salvo dos `.mp4` de grabaciones y unos `.uid`
  sin seguir de la línea motor.
- **HEAD**: `202ebada` — *fix(view): stop the live rebuild from killing the remote debugger*.
- **Suite**: `python scripts/check_product.py` → **30/31**. El único fallo es
  `test_exit0_real_json`, conocido y de la línea motor.
- **Documento vivo**: [AUDITORIA_VISUAL_2026-08-29.md](AUDITORIA_VISUAL_2026-08-29.md).
  Todo el detalle técnico está ahí; esto es solo el resumen para retomar.

---

## 1. Lo único que queda abierto

| Hallazgo | Estado | Quién lo puede mover |
|---|---|---|
| 🔴 **X-8** — iluminación inestable en suelo del rellano y paredes del pasillo al mover la cámara | **ABIERTO, causa no identificada** | Necesita al usuario ejecutando el simulador |
| 🟠 **FP-3 (F5.1)** — unificar los constructores de suelo, techo, muro y hueco entre `FirstPersonController` y `Visualizer3D` | Pendiente de trabajo real | Se puede hacer sin el usuario |
| ℹ️ **H-6** — autoexposición entre plantas | Declarado fuera del cierre | — |

Todo lo demás de §1-§8 de la auditoría está cerrado.

---

## 2. X-8: qué es y qué está descartado

Descripción del usuario: *"en el suelo del rellano aparece iluminación irregular
cuando muevo la cámara, con formas redondas, cuadradas, líneas de sierra... de
forma aleatoria"*, y lo mismo en las paredes del pasillo. Es **un solo fenómeno
en dos sitios**.

Dato de contexto que importa: el renderer es **`gl_compatibility`**
(`project.godot`), no Forward+.

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
legítimo. **El piso patrón (`simple_house`) no reproduce el fenómeno.** Las
correcciones de sombra se conservan porque son defendibles por sí mismas, no
porque estén verificadas como solución de esto.

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

## 5. Siguiente paso concreto: la bisección

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
python scripts/check_product.py                      # 30/31, fallo conocido de motor
python tests/test_godot_editability.py               # 15/15
<godot> --headless --path . --check-only --script view/fp/FirstPersonController.gd
```

Binario: `C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe`. En Git
Bash el stdout de Godot a veces no llega al pipe: volcar a fichero
(`> .test_tmp/x.txt 2>&1`) y leerlo.

**Nota de método que ya se ganó dos veces**: con síntomas visuales, pedir al
usuario que señale sobre su propio fotograma resuelve en un mensaje lo que tres
rondas de deducción no resuelven.
