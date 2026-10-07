# Assets de SimuFire: guía para arte

Documento de entrega para decidir la reforma completa:
[sistema actual, objetivos y decisiones para la diseñadora](../../docs/architecture/GUIA_REFORMA_VISUAL_3D_FP_DISENADORA_2026-10-07.md).

Alcance de la publicación: documentación. El inspector, banco y contrato
optativo descritos debajo siguen en el checkout WIP `runs/playable_homes`,
rama `codex/playable-homes-isolated`; no están incluidos en `main` con esta
entrega. Las secciones siguientes distinguen ese prototipo del catálogo actual.

## Qué se puede editar aquí

- `furniture/*.tscn`: wrappers de mobiliario; muchos instancian un GLB en
  `furniture/gltfs/`. Las vistas 3D y FP comparten este catálogo.
- `openings/*.tscn`: paneles de puertas y ventanas, no la pared que los aloja.
- Paredes, suelos, techos, hall y escaleras **no son un único asset de vivienda**:
  se generan desde las salas y aperturas del escenario y sus reglas de vista.

## Por qué un modelo puede cambiar al entrar en el juego

Actualmente el cargador ajusta la malla a una talla de arquetipo. Puede girarla
90° para alinear el lado largo, aplicar escalas distintas por eje, centrar su
huella y apoyar su base en Y=0. El autoamueblador puede después cambiar la pose
o el tamaño de algunas piezas. El wrapper original no muestra esos cambios.

No compensar esto encogiendo o girando repetidamente el GLB a ciegas. Primero
comparar escena original y ejecución; corregir la política que produce el
cambio. El contrato optativo nuevo ya tiene implementación y controles
sintéticos; la migración del catálogo y la reorganización siguen pendientes.

## Dónde se generan las partes de una vivienda

| Parte | Archivo/regla que la genera |
| --- | --- |
| Paredes de maqueta | `view/3d/geometry/RoomShellFactory.gd` |
| Paredes y techos FP | `view/fp/FirstPersonController.gd`, `_create_walls` / `_create_ceilings` |
| Losas y huecos | `view/geometry/SlabGeometry.gd` |
| Escaleras | `view/geometry/StairGeometry.gd` y constructores de cada vista |
| Portal modelado y rellano | `view/geometry/PortalGeometry.gd` |
| Portal/contexto decorativo | `FirstPersonController._create_landing_recess` y constructores de exterior |
| Tamaño del mueble | `view/furniture/FurnitureDimensions.gd` |
| Ajuste del modelo | `view/3d/furniture/FurnitureAssetLoader.gd` |
| Distribución automática | `FurnitureRoomLayout.gd` / `FurnitureRoomGrammar.gd` |

## Banco de comparación (V0)

Estado: inspector, catálogo y arranque del banco verificados en Godot bajo
monitor. Pendiente revisar su aspecto con la diseñadora: el arranque headless
no certifica estética ni iluminación.

Abrir `tools/preview_visual_asset.tscn` en Godot y elegir `archetype` en el
inspector del nodo raíz; ejecutar esa escena. Izquierda: wrapper original,
con sus transformaciones de autor. Derecha: resultado del cargador del juego
para `requested_footprint_m`. Suelo cuadriculado en metros; rojo +X, azul +Z.
El banco no recoloca muebles en una habitación ni ejecuta el motor de incendio.
Por tanto aísla importación/ajuste, no toda la ruta del editor.

`tools/inspect_visual_assets.gd` produce medidas y transformaciones reales
de ese mismo cargador. Sus resultados no son medidas experimentales de fuego.
Ejecutarlo mediante el monitor de pruebas, no abrir tandas Godot en paralelo.

## Contrato optativo de autor (catálogo pendiente de migración)

Para un wrapper de **mobiliario**, declarar en su raíz local:

```text
metadata/simufire_transform_mode = "authored_meters_v1"
metadata/simufire_front_axis = "-z"
```

Metros, +Y vertical, frente -Z, raíz identidad y pivote centrado en planta
sobre Y=0 (tolerancia de 1 mm). Corregir unidades/ejes del archivo fuente una
vez, explícitamente en el wrapper o al exportar. No en un ajuste inferido por
el juego. No marcar el contrato antes de comprobar esas condiciones.

En este modo el cargador conserva medidas y orientación del asset; solo
convierte unidades de la vista. La distribución conserva el centro que declara
el escenario y su `rotation_deg`, sin encogerlo ni girarlo para hacerlo caber.
La posición de la ficha visual se deriva de ese centro y del tamaño visual;
no reescribe la posición ni la huella del objeto combustible.

Si no cabe o invade el paso de puerta, expone `visual_placement_issues` en el
nodo runtime y un aviso, sin corregir la pose. Todavía no es un panel de avisos
del editor ni un validador exhaustivo de colisiones entre muebles manuales.
Reiniciar el banco tras cambiar un wrapper: no se ha cerrado el hot-reload de
cachés de tamaños. No modificar la química/carga de fuego para cuadrar arte.

Referencia sintética: `examples/authored_meter_reference.tscn`, caja asimétrica
de 1,2 × 1,0 × 0,4 m. Elegir `authored_meter_reference` en el banco: cambiar
`requested_footprint_m` no debe cambiar la caja. No es un mueble distribuido.

Los 38 arquetipos inspeccionados siguen en `legacy_fit`. No se impone el
contrato retrospectivamente. Puertas/ventanas, modularidad de cocinas y
adaptación paramétrica requieren contratos propios, todavía pendientes.

Plan y estado: [limpieza 3D/FP](../../docs/planning/VISUAL_3D_FP_CLEANUP_2026-10-07.md).
