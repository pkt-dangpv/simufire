# Viviendas jugables independientes — 2026-10-07

Estado actualizado 08-10-2026: separación implementada y cadena automática
completa verde. Esta entrega incluye código, viviendas y pruebas; no certifica
estética ni navegación completa y no cierra la reforma arquitectónica 3D/FP.

Reanudación 08-10-2026: publicación del código autorizada si toda la cadena
queda verde. Repetición estática: 64 passed / 42 subtests, diez planos PASS
y estilo GDScript PASS. Aceptación runtime endurecida para rechazar cualquier
`ERROR:`. La memoria inicial estaba por debajo de 6 GiB; no se lanzó Godot
hasta liberar memoria. La cadena completada se registra abajo.

## Alcance y punto de partida

Petición del usuario: corregir viviendas para jugar sin modificar los casos
científicos; commit y push después de verificar. Checkpoint `9d55289a`, rama
`codex/playable-homes-isolated`, checkout auxiliar `runs/playable_homes`; main inicial limpio.

La base se actualizó después por fast-forward a `2e5d764a`, publicación
documental de la selección de fuente G3 desde otra sesión. Se conservaron
ambas entradas del handoff al resolver el conflicto de inserción. El checkout
`runs/g3s` quedó sin nuestros cambios; ninguna pieza ajena entra en este diff.
El trabajo previo a esa actualización está también preservado en el stash
`wip-playable-homes-before-updating-base-2026-10-07`; no se tocaron los dos
stashes históricos del usuario.

Los diez presets aparecen en casos de validación. Antes, producto y ciencia
llamaban a los mismos constructores de `BuildingTemplate`: solo se separaban
el foco y el inicio del jugador. Siete JSON no contienen objetos combustibles.
Esto no equivale a ausencia de atrezo ni a ausencia de combustible agregado.

## Separación

- `create_by_name()` y todos sus constructores/helper históricos permanecen
  idénticos. Siguen siendo la entrada de `CaseRunner` y del runner de casos.
- `create_product_preset()` lee documentos propios en `scenarios/playable/`.
  Conserva la autoría de foco/inicio existente. Un fichero ausente o inválido
  da un error y resultado vacío: no cae silenciosamente en una casa científica.
- La exportación normaliza esos documentos en su propio directorio; nunca
  los reconstruye desde las plantillas científicas ni sobrescribe sus JSON.
- Los `scenarios/preset_*.json` históricos permanecen intactos para fixtures,
  auditorías y trazas. El desplegable no los ofrece como duplicados del catálogo
  jugable; los diez presets se abren por la ruta de producto.
- Un pin independiente registra SHA-256 LF de todos los JSON históricos de
  escenarios/casos y de todas las funciones históricas de la fábrica salvo
  `create_product_preset()`. No fija los nuevos planos jugables.

Esto protege las referencias sin obligar a conservar una vivienda defectuosa
en el juego. Las pruebas de producto sí deben cubrir las viviendas nuevas.

## Defectos y correcciones

| Defecto | Corrección exclusivamente jugable |
| --- | --- |
| Tres conexiones del adosado sin pared compartida: salón–pasillo, pasillo–cocina y vestíbulo–trastero | Pasillo trasero continuo, despacho y cocina reubicados, trastero conectado al pasillo; geometría de sala y rectángulos actualizados juntos |
| Barridos superpuestos en distribuidor/entrada de varios pisos | Las puertas de distribuidor a estancia abren hacia la estancia; lados de pared declarados explícitamente |
| Salida exterior del comedor ranch en una medianera del lavadero | Salida al exterior desde el lavadero; puerta comedor–lavadero se conserva |
| Ventana exterior de cocina Ghanekar frente al baño | Retirada del vano ficticio de la copia jugable; la referencia Ghanekar no cambia |
| Ventana del despacho del adosado frente a la cocina nueva | Ventana al paramento inferior realmente exterior |
| Escalera de dos plantas con configuración implícita y hueco no correspondiente al trazado nuevo | Dos tramos en U, descanso, accesos inferior/superior alineados y hueco del tamaño de la caja |
| Bisagra vertical invertida en FP respecto al plano y visor | Tangente vertical FP `+Z`, en lugar de `-Z`; no cambia el flujo de gas |

El auditor offline comprueba solapes de salas por planta, pared compartida,
exterior real, jambas, barrido dentro de la sala destino, conexión vertical,
tamaño de hueco, acceso desde exterior y solape de envolventes de barrido.
El muestreo de envolventes usa cuadrícula de 5 cm y ángulo de 82° del FP:
es una comprobación geométrica discretizada, no certificación exhaustiva de
colisiones de hojas, muebles o navegación. La aceptación runtime es aparte.

## Mobiliario y límite científico

Los diez documentos piden `visual_furniture_fill`. Se conserva como metadato
de presentación en la sala, OFF/false cuando no se declara. La vista completa
arquetipos ausentes usando el amueblador existente, sin repetir los ya presentes.
El atrezo no entra en `fuel_objects` y no contiene energía, HRR ni rendimientos.

No se modifican inventarios de objetos existentes, cargas MJ por sala,
rendimientos de CO, química, autorización experimental ni interruptores.
Las siete viviendas de carga agregada **siguen sin inventario físico por mueble**.
No se presentan como migradas a `explicit_objects` ni como CO/FED validados.
Esa migración depende de [G3](../planning/G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md).

## Verificación

- Auditor offline: diez viviendas PASS tras correcciones.
- Focal estática inicial: 64 passed, 42 subtests; antes de la aceptación runtime.
- Regresión focal ampliada: 132 passed, 1 deselected, 42 subtests. Incluye
  contratos de perfiles, autorización y persistencia, no la aceptación nueva.
- Focal repetida desde la base `2e5d764a`: 64 passed, 42 subtests.
- Pins: casos, JSON históricos y funciones científicas sin cambios.
- Focal final: 70 passed, 42 subtests (viviendas, autoría/editor e inspector).
- Aceptación runtime: 2.804 checks, diez viviendas, 359 piezas visibles y
  316 de atrezo. Recorrido de serialización editor/runtime incluido.
- Medición de cajas de los nodos FP realmente dibujados, no de la talla
  solicitada al cargador. La primera medición fallaba por confundir ambas;
  corregida sin aumentar tolerancias. Control negativo: desplazar una pieza
  100 m produce rechazo por salir del recinto.
- Referencia completa: 18/18 ejecuciones sanas, 346/346 required, 78 gaps,
  ALL GUARDRAILS PASS incluido R2-1. Se compararon 185 JSON del corpus frente
  a `dd9390a9`: idénticos tras normalizar LF/CRLF; resumen solo `generated_at`.
- Producto: 168/168 PASS. Global: 4.241 passed, 53 skipped, 2 xfailed,
  42 subtests, exit 0 (671,31 s). Godot secuencial con mínimo de 6 GiB,
  temporales externos y sin procesos residuales al terminar.

La referencia precede a una corrección de tres líneas del cargador modular
en `view/`: no dibujar ni contar como válido un contrato rechazado. No cambió
ningún archivo `sim/` ni entrada científica después de la referencia; focal,
producto y global se repitieron sobre ese código final. Logs de referencia:
`runs/reference_suite_monitored_20261008_001716/` (locales, no versionados).
No se borraron assets ni archivos ajenos. Revisión visual humana y recorrido
completo de estas diez viviendas pendientes; headless no los sustituye.

## Uso y mantenimiento

Editar `scenarios/playable/preset_<id>.json` para mejorar una vivienda del
catálogo. No editar constructores históricos para mejorar producto ni renovar
pins de ciencia para hacer pasar una modificación de vivienda.

Prueba offline: `python scripts/simulation/audit_playable_homes.py`.
Pruebas de separación: `tests/test_playable_homes.py`.
Aceptación Godot monitorizada: `tests/test_playable_homes_runtime.py`.

Las futuras modificaciones jugables deben repetir sus contratos de producto;
no renovar los pins científicos para acomodar cambios de las viviendas.
