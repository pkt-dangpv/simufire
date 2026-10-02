# G3-1 — Gate dinámico de cargas de estancia y objeto desiguales

Fecha: 2026-09-27. Estado: **diagnóstico reproducido; NO-GO para migración
automática o CO por mueble**. No cambia la física. Complementa el
[inventario estático](G3_FUEL_SOURCE_OWNERSHIP_AUDIT_2026-09-27.md) y el
[baseline de especies](G3_FUEL_SOURCE_DYNAMIC_BASELINE_2026-09-27.md).
El [cierre G3-1 del 29-09](G3_FUEL_OWNERSHIP_CLOSURE_2026-09-29.md) repite
estos controles junto con sala vacía, dos objetos, objeto frío y un caso real.

## Controles y salud

`scripts/simulation/run_g3_fuel_ownership_gate.py` generó cuatro escenarios
artificiales con igual geometría, ignición, ventilación, flags y tope nominal
de 100 kW. Sólo variaron los MJ declarados en la estancia y el sofá. No son
valores de mobiliario propuestos para producto. Duración solicitada: 90 s;
última fila 90,1 s, 91 snapshots y 1.081 pasos por caso. Resultados, hashes
de escenarios, trazas por paso y monitores en
`runs/g3_fuel_ownership_gate_20260927_205802/` (ignorado por Git).

Los cuatro monitores: exit 0, sin timeout ni cuadros de error, cero procesos
Godot residuales y `process_quiescent = true`. Las sumas del libro por paso
reconcilian con el CSV para combustible de sala, CO, humo y O₂ según la
precisión de cada columna. El residuo máximo de CO fue `1,13e-19 kg` y el
de humo `1,18e-17 kg` entre todos los pasos/casos. Esto es cierre de
contadores internos, no validación experimental.

| Caso | MJ sala | MJ sofá | Consumo fuego/sala MJ | Consumo sofá MJ | Sofá remanente MJ | HRR máx kW |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Sólo estancia | 3 | — | 2,999863 | — | — | 87,68 |
| Sólo sofá | 0 | 3 | 2,999863 | 3,000000 | 0 | 87,68 |
| Estancia 3, sofá 1 | 3 | 1 | 2,999863 | 1,000000 | 0 | 87,68 |
| Estancia 1, sofá 3 | 1 | 3 | 1,000000 | 0,999981 | 2,000019 | 41,60 |

En **estancia 3 / sofá 1**, el sofá se agota a `t = 39,0833 s`. Tras ello
el fuego aún consume **1,998060 MJ** durante 612 pasos y alcanza un HRR
posterior de `87,717 kW`; ese consumo ya no puede atribuirse al sofá
explícito. El `room_proxy_0` refleja el consumo de estancia de 2,999863 MJ,
pero no se suma como otro objeto explícito. No sabemos si los 2 MJ restantes
representarían contenido no dibujado: el escenario deliberado no declara
ninguna fuente material para ellos.

En **estancia 1 / sofá 3**, el fuego se limita a 1 MJ y quedan unos 2 MJ
de combustible en el sofá. El CSV `fuel_remaining_MJ ≈ 2,000019` refleja
ese remanente del objeto, **no** capacidad disponible para seguir quemando
en la ruta del fuego de sala. Así, ni el remanente visible ni el objeto
explícito son por sí solos el propietario autoritativo del límite de HRR.

La lectura de código concuerda con la medición:
`CombustionSystem._resolve_room_fuel_energy_MJ()` prioriza un
`room.fuel_energy_MJ` positivo antes de sumar objetos; sólo usa los objetos
cuando la estancia declara cero. Los cuatro casos aíslan esa precedencia,
pero no autorizan a reinterpretar las 23 discrepancias distribuidas como
combustible ficticio: podrían incluir contenido real no dibujado, que hoy
carece de nombre y procedencia.

## Gate y límites

- **NO-GO** para corregir CO cambiando sólo el `yield` del sofá, para
  sustituir automáticamente `fuel_energy_MJ` de las 23 salas discrepantes
  por la suma de sus muebles o para añadir la diferencia como «contenido
  oculto» sin fuente trazable.
- La vía futura `explicit_objects` debe derivar el tope del inventario
  explícito y detener la producción al agotarse, salvo fuentes adicionales
  **nombradas**. La vía `legacy_lumped` debe mantener intactos los casos de
  referencia. Las salas ambiguas permanecen `legacy_unknown` hasta revisar
  su procedencia; estos modos son diseño, **no están implementados**.
- Falta comprobar identidad OFF/ON del nuevo modo cuando exista, transporte
  y especies por objeto, y curvas frente a ensayos. La diferencia de
  `≈1,37e-4 MJ` entre acumulado de sala y objeto único al final del control
  de 3 MJ queda como detalle de sincronización/precisión por investigar;
  no se ha forzado una igualdad artificial.
- El proxy puede mostrar `burned_out` con HRR positivo al último instante;
  la presentación de ese estado no se toma como segundo fuego físico.

## Reproducción y contexto del checkout

La rama G3 estaba en el stash automático de GitHub Desktop tras el cambio
externo a `main`. Se recuperó con `stash apply` **sin consumir el stash** en
un worktree aislado de `codex/g3-fed-co-zonal`; `main` y sus cambios locales
quedaron intactos. Una primera ejecución allí no produjo datos porque el
checkout nuevo aún no tenía caché de clases Godot; terminó por timeout y
sin procesos residuales. La importación monitorizada del proyecto terminó
con exit 0 y sin errores, y la tanda siguiente es la reportada arriba.
Los `.gd.uid` generados por esa importación no forman parte de G3.
