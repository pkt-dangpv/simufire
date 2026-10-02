# G3 — Propiedad del combustible: estancia frente a objetos (2026-09-27)

Estado: **auditoría estática; NO-GO para sustituir cargas o rendimientos en el
motor**. Esta nota complementa [la evidencia de producción de CO](G3_CO_PRODUCCION_COMBUSTIBLES_ESTANCIA_2026-09-27.md).
No se ha ejecutado Godot ni se ha medido aquí la sensibilidad dinámica. La
mezcla de fuentes es un mecanismo plausible del error de CO, **no una causa
cuantificada ni única** del desfase con CFAST.

## Qué existe hoy

1. `RoomModel` conserva `fuel_energy_MJ` y `max_hrr_kw` propios de la estancia.
   `CombustionSystem.ensure_room_fuel_objects()` crea un objeto `room_proxy_*`
   cuando hay carga de estancia. Si además hay objetos explícitos, el proxy se
   excluye de las sumas de objetos mediante `_should_skip_object_for_room()`:
   **no afirmar que ambos arden siempre dos veces**.
2. Al crear `FireModel`, `_resolve_room_fuel_energy_MJ()` y
   `_resolve_room_max_hrr_kw()` dan prioridad a los valores positivos de la
   estancia **antes** de sumar los objetos explícitos. Un escenario que declara
   4 300 MJ de sala y 2 620 MJ en muebles puede, por tanto, iniciar un fuego
   con el límite energético de 4 300 MJ aunque los objetos describan otro
   inventario. Hay que medir la evolución y el cierre antes de decir cuánta
   energía extra llega a liberarse.
3. Para CO, CO₂ y HCN, las funciones `_resolve_room_*_yield_kg_per_MJ()`
   calculan un rendimiento medio por estancia con objetos que aún conservan
   combustible, **incluidos los fríos/no participantes**. La ponderación usa
   `max_hrr_kw`, precalentamiento y estado, pero no la energía realmente
   consumida por cada objeto en ese paso. Después la química aplica esa media
   a una base energética del fuego de sala. Añadir un segundo mueble sin
   encenderlo puede cambiar el rendimiento calculado del primero.
4. El catálogo del editor (`ObjectLibrary.CATALOG`) ofrece 38 arquetipos, pero
   declara expresamente que sus cifras son **estimaciones de ingeniería, no
   mediciones de laboratorio**. Al crear un objeto sólo escribe energía,
   potencia máxima, umbrales de ignición y rendimientos de humo y CO; fija el
   mismo consumo de O₂ para todos. No escribe HCN ni CO₂: al cargar el objeto,
   `FuelObjectModel` aporta HCN = `0.00004 kg/MJ` para todos y CO₂ = `-1`
   (sentinela que conduce al valor global). El modelo admite muchos otros
   campos por objeto, pero el catálogo no los caracteriza.
5. `ScenarioReview._check_ignition()` suma `fuel_energy_MJ` de estancia y
   muebles para decidir si existe combustible. Es un criterio de presencia,
   **no un balance**, pero muestra que la interfaz tampoco expresa una fuente
   única. No se ha probado que esta suma altere directamente el HRR.

## Alcance de los JSON distribuidos

Auditoría de los **14 archivos `scenarios/*.json`**, campo `rooms_data`;
comparación exacta de `room.fuel_energy_MJ` con la suma de los
`fuel_objects[*].fuel_energy_MJ` de esa sala:

| Medida | Resultado |
| --- | ---: |
| Salas totales | 109 |
| Salas con carga positiva de estancia | 107 |
| Salas con objetos explícitos | 36 |
| Salas con ambos y energía distinta | 23 |
| Presets `preset_*.json` sin objetos en ninguna sala | 7 de 10 |

Ejemplos: `compact_apartment_reference.json`, «Salon cocina», 4 300 MJ de
estancia frente a 2 620 MJ en objetos; `preset_two_storey_house.json`,
«Salon-comedor PB», 8 500 frente a 3 220 MJ. Los tres casos `*_reference.json`
y los presets de producto **no son la misma población**; se conservan como
familias separadas. La discrepancia puede representar contenido no dibujado,
pero los JSON no declaran esa procedencia ni si el número de sala es total o
complemento. No se puede resolver eligiendo silenciosamente uno de los dos.

## Contrato de diseño propuesto (a validar)

- Cada carga combustible tiene **un solo propietario**. En escenarios de
  producto, los objetos explícitos aportan su masa/energía; acabados,
  revestimientos o contenido no visible requieren una fuente **nombrada** con
  cantidad, material y procedencia. El tipo de estancia por sí solo no crea
  combustible ni especies. El total de sala es derivado/diagnóstico, no otro
  fuego en paralelo.
- Los casos de referencia CFAST/FDS con fuego prescrito o carga agregada
  conservan una vía `legacy_lumped` **explícita**, separada de los escenarios
  amueblados. No reescribir automáticamente sus 346 casos ni cambiar su
  química al migrar presets. Un JSON antiguo ambiguo queda etiquetado como
  `legacy_unknown` hasta clasificación; no inferir que la diferencia entre
  total y muebles es siempre contenido oculto.
- Para cada arquetipo/material: masa combustible o energía con calor efectivo
  declarado, curva HRR o ley de pérdida de masa, área/geometría, ignición,
  fracción radiativa, O₂ y rendimientos de CO, CO₂, HCN y humo/hollín **por
  régimen**, con fuente, intervalo de incertidumbre y estado `medido`,
  `estimado` o `desconocido`. No rellenar ceros o valores globales como si
  fueran medidas; un sofá puede tener materiales y tratamientos distintos.
- Generación por paso: atribuir pérdida de masa/energía y especies a cada
  objeto **activo**; luego sumar objetos, oxidación y transporte a nivel de
  sala. La fase sombra debe cerrar energía y especies sin tocar la física
  histórica. Solo una fase opt-in validada podrá tomar autoridad.

## Orden y gates

1. Inventario reproducible de todos los presets, referencias y plantillas:
   `room_total`, suma de objetos, diferencia, fuentes no dibujadas, origen de
   cada valor y modo `legacy_lumped`/`explicit_objects`/`legacy_unknown`.
   Clasificar manualmente las 23 discrepancias; ninguna conversión destructiva.
2. Contratos estáticos: sala verdaderamente vacía = cero combustible generado;
   sofá único = sólo su carga; añadir una silla fría no altera CO del sofá;
   y ninguna fuente aparece dos veces en editor, `FireModel` y libro contable.
3. Contabilidad pasiva por objeto y régimen de HRR, combustible consumido,
   CO, CO₂, HCN y O₂. Comparar sumas con el incendio de sala y conservar OFF
   byte a byte; medir escenarios con/sin objetos antes de decidir migración.
4. Fijar fichas experimentales y curvas con procedencia (NIST TN 2303/FCD,
   TN 1453 y ensayos de estancia completa) y sólo entonces migrar presets
   seleccionados tras revisión humana de su mobiliario. Validar curvas y
   totales; no calibrar a un solo ppm CFAST.
5. Implementar nueva fuente de especies bajo interruptor OFF por defecto,
   guardarraíles, mutaciones y suite de referencia. Después estudiar transporte
   zonal y FED/SVV. La decisión de activación en producto sigue separada.

**Decisión actual:** la hipótesis del usuario se confirma como problema de
representación y de atribución, no aún como explicación cuantificada del CO
observado. El siguiente trabajo ejecutable es el inventario/gate 1, no asignar
rendimientos arbitrarios a los 38 muebles.

## Checkpoint G3-1 estático (2026-09-27)

El inventario anterior ya es reproducible sin Godot:

```powershell
python scripts/simulation/audit_g3_fuel_sources.py
python scripts/simulation/audit_g3_fuel_sources.py --json
```

El segundo comando incluye las 14 huellas SHA-256 de entrada, cada sala,
sus objetos, energía y potencia declaradas y diferencia. **No edita JSON**
ni infiere combustible oculto. Su prueba focalizada exige los recuentos
actuales y falla para energía negativa/no finita, IDs duplicados y objetos
asignados a otra sala.

| Forma observada | Salas | Interpretación permitida |
| --- | ---: | --- |
| Estancia con carga, sin objetos | 71 | Carga heredada sin propietario material declarado. |
| Estancia y objetos con energía/potencia coincidentes | 13 | Posible total reflejado; **no está demostrada** esa intención. |
| Estancia y objetos discrepantes | 23 | Ambigüedad por clasificar, no «combustible oculto» automático. |
| Sin combustible declarado | 2 | Control estático; falta confirmar dinámica. |

Las 23 discrepancias están en `compact_apartment_reference.json` (salas
0–4), `long_hallway_reference.json` (0–5), `preset_two_storey_house.json`
(0, 3, 8, 9, 10, 12) y `two_storey_reference.json` (0, 2, 3, 5, 6, 7).
Los siete presets sin objetos son `preset_compact_apartment.json`,
`preset_piso_mediterraneo.json`, `preset_ranch_family_house.json`,
`preset_row_house_ground_floor.json`, `preset_three_bed_apartment.json`,
`preset_two_bed_apartment.json` y `preset_uk_bungalow.json`.

Hay **107 objetos explícitos** en los JSON: los 107 declaran rendimiento de
CO, ninguno declara rendimiento de HCN ni de CO₂. Esos dos últimos quedan
en los defaults del modelo, no medidos por cada mueble. Ninguna de las 109
salas puede etiquetarse aún como `explicit_objects` o `legacy_lumped` de
forma autoritativa solo con la igualdad de totales. Falta revisar procedencia
de los valores de las plantillas en `BuildingTemplate.gd`, decidir qué
representan las 23 diferencias y registrar la respuesta en el escenario.

Primera lectura de `BuildingTemplate.gd`: el comentario de `create_simple_house()`
define `fuel_energy_MJ` como carga total por superficie × densidad y después
su layout asigna muebles cuya suma coincide con esa carga. Esa es una pista
de total **reflejado**, no una declaración persistida en el JSON ni una medida
de cada mueble. `create_two_storey_house()` asigna cargas de sala y sólo seis
de trece salas reciben objetos explícitos; esos seis no suman el total. Los
presets de una sola fuente agregada se construyen con `_make_room()` y no
aportan un inventario material. No se ha encontrado en los 14 JSON un campo
de propiedad/procedencia del combustible. La decisión de si el resto de carga
de dos plantas representa acabados u objetos omitidos sigue abierta.

Verificación del auditor: **10/10 pruebas focalizadas PASS**; primer intento
dentro del sandbox no alcanzó las pruebas con `tmp_path` por permisos de
pytest, y la repetición autorizada terminó en verde. Sin ejecución Godot ni
cambio de física en este checkpoint.

### G3-0: control dinámico ejecutado

`scripts/simulation/run_g3_fuel_baseline.py` prepara cinco escenarios
controlados con la misma geometría y ajustes: carga solo de estancia; sofá
con total reflejado en la estancia; el mismo sofá más una silla configurada
para no prender; sofá sin carga de estancia; y estancia de ignición vacía.
Lanza cada caso por separado con el monitor nativo, exige artefactos frescos
y salud limpia, y guarda entradas, hashes, logs, métricas y salud en `runs/`.
No activa física experimental ni modifica los escenarios distribuidos.

Las 13 pruebas focalizadas de auditor y preparación del control pasan. El
primer intento se detuvo antes de abrir Godot por menos de 6 GiB libres;
después se completaron dos tandas de cinco casos con salud limpia. El
snapshot comprobó que la silla no ardió y aun así elevó 2,92 veces el CO
generado con HRR/energía casi iguales. Resultado, límites y artefactos en
[baseline dinámico G3-0](G3_FUEL_SOURCE_DYNAMIC_BASELINE_2026-09-27.md).
