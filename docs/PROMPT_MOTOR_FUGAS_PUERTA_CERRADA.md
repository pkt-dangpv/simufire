# Diagnóstico y diseño: fugas de puertas interiores cerradas

> **Estado (2026-09-22): fases 1, 2, 3A y 3B cerradas; F2.2C y F2.2D1-D3
> integradas detrás de interruptores apagados por defecto; F2.2D4A cierra la
> PERSISTENCIA de esa física prescrita (§20), F2.2D4B1 publica el CATÁLOGO
> trazable de perfiles y el gate científico (§21), y F2.2D4B2A lo conecta al
> EDITOR para configurarlo e inspeccionarlo (§22). Ninguna de las tres calibra
> ni activa: ELA, reparto, exponente, deformación y vidrio siguen
> provisionales, cinco perfiles siguen BLOQUEADOS, los quince siguen con
> `product_activation = false`, y ningún escenario distribuido los declara ni
> los enciende.**
> - **Fase 1**: el modelo puro de fuga de puerta cerrada
>   (`sim/core/ClosedDoorLeakageModel.gd`) está implementado, validado y
>   cerrado (§12).
> - **Fase 2**: la deformación prescrita pura
>   (`sim/core/ClosedDoorDeformationModel.gd`) está implementada, validada y
>   cerrada (§13). La
>   topología de huecos está respaldada por los ensayos; las magnitudes no están
>   calibradas y no hay ley automática temperatura-deformación.
> - **Fase 3A**: la integridad prescrita de paños acristalados
>   (`sim/core/GlazingIntegrityModel.gd`) está implementada (§14). Es
>   determinista y `CRACKED` no ventila.
> - **Fase 3B**: la geometría del camino libre a través de todas las hojas
>   (`sim/core/GlazingOpeningGeometryModel.gd`) está implementada (§15). Es la
>   intersección exacta de las regiones desprendidas, sin caudal.
> - **F2.2-DIAG (2026-09-17, corregida el 2026-09-18)**: el diagnóstico y el
>   diseño de la sobrepresión de recintos cerrados están cerrados en
>   [`PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md`](PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md).
>   **F2.2A** (evaluador puro de ecuaciones locales de presión) y **F2.2B**
>   (solver puro acoplado de presión y aberturas, que promueve
>   `Phase3CoupledPressureSolver`) están implementadas desde el 2026-09-18, y
>   **F2.2C** las integró ese mismo día detrás del interruptor único
>   `pressure_network_solver_enabled`, apagado por defecto.
> - **F2.2D4B2A** (§22): el editor enseña el catálogo, deja elegir un perfil
>   compatible con la abertura, explica su evidencia, su dominio, su fuente y
>   sus advertencias, y guarda la referencia versionada con su copia congelada.
>   Los bloqueados se ven pero no se eligen; los experimentales exigen
>   confirmar el modo experimental. Configurar NO activa: con los interruptores
>   apagados una abertura configurada no aporta ni un elemento a la red.
> - **F2.2D4B1** (§21): catálogo versionado de 15 perfiles con su procedencia a
>   nivel de página, tabla o ecuación, su dominio de ensayo y su estado de
>   evidencia. La relectura BAJÓ de categoría los 12 y 21 cm² (la tabla ASHRAE
>   de origen fue retirada del manual y NIST la deprecia), encontró que una
>   puerta interior realmente medida va de 20 a 234 cm² y que el exponente no es
>   constante sino que va de 0,98 a 0,50 según el espesor de la rendija.
> - **F2.2D4A** (§20): contrato persistente versionado para la clase de fuga, la
>   deformación prescrita, los paños de vidrio y sus historias espaciales.
>   Ausencia = física desactivada; guardar y cargar no toca ningún interruptor;
>   el editor sigue sin mandos. Encontró y cerró dos defectos del formato JSON
>   de Godot (todo número vuelve como `float`, y `stringify` guarda 15 cifras)
>   y uno ajeno (`ignition_room_id` rompía la estabilidad byte a byte).
> - **F2.2D se ha partido en cuatro** (§16): **D1** integra la fuga **fría** de
>   puerta cerrada en la red autoritativa, **D2** la deformación prescrita,
>   **D3** el vidrio y **D4** la calibración de clases. **D1 está integrada
>   desde el 2026-09-18** detrás de `closed_door_leakage_enabled`, apagado por
>   defecto y dependiente del interruptor de la red. **D2 está integrada desde
>   el 2026-09-20** detrás de `closed_door_deformation_enabled`, también apagado
>   por defecto y dependiente de la red. **D3 está integrada desde el
>   2026-09-21** detrás de `glazing_fallout_enabled`, también apagado por
>   defecto y dependiente de la red. D1, D2 y D3 son independientes.
> - **Qué está y qué no está integrado.** La fuga fría de puerta cerrada sí lo
>   está, por la red de presión. La **deformación prescrita (D2) también**; el
>   **desprendimiento prescrito de vidrio (D3) también**. Los modelos térmico y
>   probabilista de rotura **siguen sin existir**: D3 no decide cuándo rompe el
>   vidrio. Ningún escenario normal enciende estas rutas: hay que pedir
>   explícitamente los interruptores y declarar clases, pistas o historias.
>   La ELA, el reparto por cotas y el exponente siguen siendo **provisionales**
>   (§7), pendientes de la calibración de D4.
>
> El diagnóstico de §2-§5 se midió con `main` en
> `b0b31bb6` sin tocar `sim/`.
> La revisión bibliográfica trazable está en
> [`RESEARCH_PUERTAS_CRISTALES_FUGAS_2026-09-16.md`](RESEARCH_PUERTAS_CRISTALES_FUGAS_2026-09-16.md).
>
> **Decisiones del usuario (2026-09-16):**
> - **Área**: ELA a 4 Pa según NIST TN 2329: **12 cm²** para la entrada de
>   vivienda y **21 cm²** como clase interior provisional. NIST emplea este
>   último valor para puertas de garaje/sótano, no como medición universal de
>   puertas interiores; por eso queda marcado como extrapolación hasta
>   calibrarlo. Las puertas desajustadas llevan un override explícito. Los
>   candidatos geométricos L1/L2/L3 de la sonda se descartan como valores (§7).
> - **Flujo**: de grieta, por ley de potencia; una clase de fuga por abertura
>   en el motor (§6.2-§6.3).
> - **Orden**: primero el modelo puro con ΔP impuestas; **F2.2 (sobrepresión)
>   se arregla antes de integrar**; después se integra (§6.6). El límite por
>   paso es solo un cinturón numérico, no sustituye a la presión física.
>   *(Cumplido: F2.2 se resolvió hasta F2.2C el 2026-09-18 y la integración de
>   la fuga fría es F2.2D1, §16.)*
> - **Integridad**: la fuga fría, los huecos por deformación y el
>   desprendimiento de vidrio son mecanismos separados. Una puerta cerrada
>   puede deformarse o perder un paño acristalado sin cambiar su
>   `open_fraction`.

## 1. Problema

Una puerta interior fría con `open_fraction == 0` es estanca. En el portal
(`tests/fixtures/exterior_o2_portal_D_door_to_portal.json`), las viviendas de
arriba con la puerta cerrada no reciben humo aunque el rellano tenga humo y
presión. En la realidad, una puerta cerrada deja pasar gas por la holgura
inferior, por los laterales y por el dintel.

## 2. Rutas actuales de una puerta interior cerrada

`OpeningModel` tiene dos campos que importan aquí:
- `open_fraction`: el estado operativo y visual de la puerta.
- `thermal_gap_fraction`: la deformación del marco. No se guarda en el JSON y
  la calcula `GasExchangeSystem._step_door_deform` en cada paso.

`effective_open_fraction()` es `clamp(open_fraction + thermal_gap_fraction)`.
`_step_door_deform` solo actúa en puertas interiores con `open_fraction < 0.5`:
el hueco crece linealmente desde 0 a 150 °C hasta el 4 % a 350 °C, según la
capa alta más caliente de las dos salas. **Una puerta fría tiene hueco 0**, así
que la deformación no equivale a una fuga permanente.

| Ruta | Qué lee | Puerta fría cerrada | Puerta cerrada deformada |
|---|---|---|---|
| Deformación térmica, `GasExchangeSystem._step_door_deform` | `open_fraction`, T sup | gap 0 | gap hasta 4 % |
| Derrame de humo, `SmokeModel.compute_room_transfers` | puerta: `effective_open_fraction()`; caudal: `open_fraction` (`_compute_transfer_mass_kg_continuous`, `_compute_opening_mass_budget_kg`) | 0 | **0**: pasa la puerta pero el área es `open_fraction` = 0 |
| Parcela de capa alta que acompaña al derrame (`GasExchangeSystem.gd` ~1990) | kg de humo movido | 0 | 0 (no hay derrame) |
| Intercambio de especies de fondo, `_apply_background_species_exchange` | `effective_open_fraction()` | 0 | **sí**: humo, CO, CO₂, HCN, HCl, acroleína y formaldehído, con una heurística de área × 0,035 kg/s/m² × impulso. O₂ × `background_o2_exchange_multiplier` = **0** por defecto. Sin masa de gas ni energía |
| Especies por dos zonas, `_apply_two_zone_opening_species_exchange` | caché de flujo | no está en la caché | no está en la caché (se cae a la de fondo) |
| Caché de flujo, `SimulationEngine._build_opening_flow_cache` | `open_fraction > 0` | excluida | excluida |
| Estado de flujo, `ThermalSystem.build_interior_opening_flow_state` | `open_fraction <= 0` → inactivo | inactivo | inactivo |
| Convección entre salas, `ThermalSystem` (~1320) | `open_fraction <= 0` → salta | nada | **nada** |
| Radiación por aperturas, `ThermalSystem._step_radiation_openings` | `open_fraction` | nada | nada |
| O₂ interior, `OxygenExchangeSystem` (~761) | `open_fraction` | nada | **nada** |
| Masa por zonas Phase 3, `Phase3ZoneMassSystem` (~4657) | `open_fraction` | nada | nada |
| Igualación de presión termodinámica, `_equalize_thermodynamic_pressure_components` | `effective_open_fraction() > 0.001` | separadas | **misma componente**: la presión se iguala al instante, como con la puerta abierta |
| Camino al exterior, `_compute_flow_path_*` | `open_fraction` | cortado | cortado |
| Propagación del fuego, `FireSpreadSystem` | `open_fraction` | nada | nada |
| PPV, sombras Phase 3, clasificación de eventos | `open_fraction` | nada | nada |

**Asimetría confirmada.** Por una puerta cerrada y deformada pasan hoy las
especies y el humo (por la heurística de fondo) y se iguala la presión al
instante. No pasan masa de gas, entalpía, O₂ ni el derrame de humo. La tabla
del enunciado era casi exacta; la corrección es que el derrame de `SmokeModel`
tampoco pasa, porque calcula el caudal con `open_fraction`.

`window_leakage_area_m2` (0,005 m²) solo sirve a las ventanas exteriores
cerradas, y únicamente para la purga por presión (`GasExchangeSystem` ~1537).
No hay que reutilizarlo.

## 3. Método de medición

Los casos están en `runs/leak_diag_20260916/` (ignorado por git):
`make_cases.py`, `cases/`, `out/`, `analyze.py`, `tables.py`,
`metrics_A.json` y `metrics_B.json`. Se ejecutaron con
`scripts/run_scenario.py --phase3-zone-diagnostics`, 600 s y los tres
interruptores que enciende el editor.

- **A**: dos salas de 4 × 4 × 2,5 m, una puerta de 0,92 × 2,05 m entre ellas y
  ninguna otra conexión. Fuego en la 1 (3000 MJ, 1500 kW).
- **Aw**: igual que A, con una ventana cerrada en cada sala, que tiene la fuga
  de envolvente que ya existe.
- **B**: el portal D de tres plantas. Las puertas cerradas son las de las
  viviendas P1 y P2 al rellano (índices 2 y 4).

**Candidatos, emulados solo en la sonda** (áreas **geométricas**, descartadas
como valor el 2026-09-16; ver §7). Cada candidato añade al JSON tres
aperturas `door` finas, con `open_fraction = 1`, **sin tocar el motor**:

| | holgura inferior | holgura perimetral | inferior | laterales (altura completa) | dintel | **total** | fracción equivalente |
|---|---|---|---|---|---|---|---|
| L1 | 3 mm | 1 mm | 28 cm² | 41 cm² | 9 cm² | **78 cm²** | 0,41 % |
| L2 | 8 mm | 2 mm | 74 cm² | 82 cm² | 18 cm² | **174 cm²** | 0,92 % |
| L3 | 15 mm | 3 mm | 138 cm² | 123 cm² | 28 cm² | **289 cm²** | 1,53 % |

Contrastes: la misma área de L2 como `open_fraction` uniforme, solo la holgura
inferior de L2 y solo los laterales y el dintel de L2.

**Aviso importante.** La sonda hace pasar la fuga por las rutas actuales de las
puertas, que son las heurísticas descritas en §2. Mide la **sensibilidad** y
deja ver las incoherencias, pero **no da los números de la física propuesta**.

**Determinismo.** `A_L2_geom` y `B_L2_geom`, repetidos, dan un `sim_log.csv`
idéntico byte a byte.

## 4. Mediciones

#### Caso A

| variante | quemado MJ | HRR pico kW | apagado s | ΔP máx fuego kPa | humo recibido g | 1 g a los s | vis<10 m s | CO ppm | CO₂ ppm | HCN ppm | O₂ mín | T sup °C | T inf °C | O₂ al fuego kg | FED |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| cerrada (hoy) | 70 | 709 | 191 | 349,1 | 4 | 153 | 163 | 5 | 243 | 0,4 | 0,209 | 25,6 | 20,4 | 0,00 | 0,00 |
| L1 78 cm² | 87 | 604 | 231 | 49,5 | 631 | 52 | 54 | 1.124 | 28.606 | 74,7 | 0,206 | 27,6 | 20,8 | 0,13 | 0,34 |
| L2 174 cm² | 66 | 604 | 249 | 13,0 | 518 | 50 | 52 | 751 | 27.546 | 61,0 | 0,205 | 31,8 | 21,8 | 0,20 | 0,22 |
| L3 289 cm² | 74 | 936 | 215 | 11,6 | 801 | 49 | 51 | 4.566 | 35.985 | 59,3 | 0,200 | 44,2 | 32,1 | 0,44 | 3,20 |
| L2 uniforme | 66 | 604 | 264 | 13,1 | 632 | 49 | 51 | 990 | 28.387 | 68,6 | 0,202 | 38,0 | 23,4 | 0,37 | 0,76 |
| L2 solo inferior | 70 | 711 | 191 | 70,3 | 56 | 137 | 137 | 29 | 3.979 | 4,3 | 0,209 | 20,2 | 20,2 | 0,02 | 0,02 |
| L2 solo lat.+dintel | 66 | 604 | 249 | 33,8 | 518 | 50 | 52 | 750 | 27.546 | 61,0 | 0,205 | 31,9 | 21,8 | 0,19 | 0,22 |
| abierta | 138 | 1.404 | 232 | 0,6 | 315 | 48 | 50 | 9.313 | 63.039 | 107,5 | 0,129 | 263,6 | 45,3 | 3,98 | 5,47 |

#### Caso Aw

| variante | quemado MJ | HRR pico kW | apagado s | ΔP máx fuego kPa | humo recibido g | 1 g a los s | vis<10 m s | CO ppm | CO₂ ppm | HCN ppm | O₂ mín | T sup °C | T inf °C | O₂ al fuego kg | FED |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| cerrada (hoy) | 64 | 611 | 194 | 297,5 | 2 | 170 | 183 | 3 | 190 | 0,3 | 0,209 | 20,1 | 20,1 | 0,00 | 0,00 |
| L1 78 cm² | 63 | 609 | 239 | 50,1 | 146 | 52 | 54 | 434 | 15.797 | 34,4 | 0,207 | 24,0 | 20,8 | 0,09 | 0,11 |
| L2 174 cm² | 63 | 609 | 249 | 13,3 | 211 | 50 | 52 | 741 | 24.451 | 55,1 | 0,205 | 26,1 | 21,1 | 0,18 | 0,20 |
| L3 289 cm² | 94 | 1.144 | 185 | 17,5 | 396 | 49 | 51 | 7.256 | 45.244 | 45,6 | 0,203 | 41,6 | 29,8 | 0,31 | 3,83 |
| L2 uniforme | 63 | 609 | 263 | 13,3 | 262 | 49 | 51 | 1.016 | 27.594 | 66,6 | 0,202 | 42,5 | 22,3 | 0,33 | 0,30 |
| L2 solo inferior | 64 | 612 | 199 | 54,3 | 2 | 165 | 177 | 4 | 284 | 0,4 | 0,209 | 20,0 | 20,0 | 0,01 | 0,00 |
| L2 solo lat.+dintel | 63 | 609 | 250 | 34,2 | 211 | 50 | 52 | 748 | 24.654 | 55,7 | 0,206 | 26,1 | 21,1 | 0,17 | 0,20 |
| abierta | 715 | 1.618 | — | 0,9 | 198 | 48 | 50 | 60.199 | 370.329 | 373,5 | 0,002 | 158,2 | 31,6 | 10,56 | 92,72 |

#### Caso B (portal, 600 s)

| variante | quemado MJ | apagado s | humo portal R+2 g | ΔP portal R+2 Pa | humo viv. P1 g | humo viv. P2 g | 1 g en P2 s | vis<10 m P2 s | CO P2 ppm | HCN P2 ppm | O₂ mín P2 | T sup P2 °C | FED P2 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| cerrada (hoy) | 474 | 328 | 507 | 11,8 | 0 | 0 | — | — | 0 | 0,0 | 0,209 | 20,1 | 0,0 |
| L1 78 cm² | 800 | 445 | 327 | 14,7 | 424 | 434 | 187 | 197 | 16.469 | 91,7 | 0,208 | 23,1 | 12,1 |
| L2 174 cm² | 807 | 447 | 348 | 16,2 | 415 | 538 | 181 | 186 | 16.749 | 93,5 | 0,207 | 23,2 | 25,3 |
| L3 289 cm² | 816 | 450 | 356 | 16,9 | 432 | 585 | 177 | 183 | 16.944 | 93,2 | 0,206 | 23,1 | 12,9 |
| L2 uniforme | 818 | 451 | 357 | 17,2 | 434 | 599 | 177 | 181 | 17.001 | 95,5 | 0,205 | 23,1 | 12,1 |
| L2 solo inferior | 474 | 328 | 506 | 11,8 | 0,3 | 0,4 | — | — | 14 | 0,1 | 0,209 | 20,1 | 0,0 |
| L2 solo lat.+dintel | 808 | 448 | 348 | 16,2 | 416 | 539 | 181 | 186 | 16.758 | 93,5 | 0,207 | 23,2 | 25,2 |
| abierta | 1.243 | — | 202 | 18,7 | 138 | 237 | 133 | 159 | 24.413 | 131,4 | 0,131 | 30,7 | 17,6 |

Sentido del flujo en B con L2: la vivienda P2 recibe **70 g** de gas por
arriba y **38 g** por abajo, y pierde **74 g** por abajo. El gas caliente del
rellano entra por la parte alta y sale aire frío por la baja. Pero el **humo
neto** que entra es de **569 g**.

#### Conservación

| caso | residuo de humo g (máx abs) | error de carbono kg (rango) |
|---|---|---|
| A | 0,058 | 0,57–2,43 (cerrada: 0,68) |
| Aw | 0,083 | 0,19–13,47 (cerrada: 0,19) |
| B | 0,087 | 9,82–28,42 (cerrada: 9,82) |

- El inventario de humo cierra en todos los casos, con menos de 0,1 g.
- El `carbon_conservation_error_kg` ya es grande **con la puerta cerrada de
  hoy**, así que no discrimina esta sonda.
- El residuo de atribución de masa y energía por paso sale 0 en todas las
  corridas, porque el diagnóstico no lo rellena en esta ruta. No es evidencia.
- Un balance de O₂ aproximado (O₂ bulk × masa de aire fija) no cierra ni con la
  puerta cerrada, así que no se usa.

## 5. Lo que dicen las mediciones

1. **La puerta cerrada de hoy no es del todo estanca cuando está caliente.**
   En A, el fuego pasa de 150 °C, la puerta se deforma y la receptora recibe
   4 g de humo por la heurística de fondo. Sin O₂ (multiplicador 0), sin calor
   y sin masa.
2. **Las rutas actuales no sirven para una rendija.** Con L1 (78 cm²) llega
   **más humo** que con la puerta abierta: 631 g frente a 315 g en A, y
   424–434 g frente a 138–237 g en B. **Llega a la vez**: visibilidad bajo 10 m
   a los 50–54 s en A, igual que abierta. Casi no cambia con el área: de L1 a L3
   el humo de P1 en B se queda en 415–432 g. La causa es que el derrame de
   `SmokeModel` es una heurística lineal en el área, con multiplicadores de
   temperatura (hasta ×3,5 con 500 °C) y de presión (hasta ×2,5, saturado), y
   un tope del 2,5 %/s del humo de la fuente. Con el disparador en 2,0 m, se
   activa en cuanto baja la capa, sea cual sea el tamaño del hueco.
3. **El humo viaja sin su gas ni su calor.** En B con L2 entran 569 g de humo
   netos con solo 108 g de gas. En A con L1, la receptora se llena de humo
   (visibilidad 0, 28.606 ppm de CO₂) y sube a 27,6 °C; con la puerta abierta,
   a 264 °C. Es la "puerta que transporta humo pero no calor" que el diseño
   tiene que evitar.
4. **La rendija cambia el fuego de otra vivienda.** En B, cualquier candidato
   con laterales y dintel sube el quemado de 474 a 800–818 MJ y retrasa el
   apagado de 328 a 445–451 s, casi sin variar con el área. La parcela de capa
   alta que acompaña al derrame (`GasExchangeSystem.gd` ~1990: ×1,5 del humo
   movido, con un mínimo de 0,03 kg o el 24 % de la capa) vacía la capa del
   rellano y cambia el intercambio con la vivienda del fuego. Es un efecto de
   la heurística, no de 80 cm² de rendija.
5. **La holgura inferior sola apenas hace nada por las rutas actuales**
   (B: el fuego igual que cerrada y 0,3–0,4 g en las viviendas; Aw: 2 g, igual que cerrada). Un hueco de 8 mm de alto solo derrama si la
   capa baja hasta el suelo, y el Bernoulli de dos zonas escala con h^1,5 del
   propio hueco. En la realidad la holgura inferior importa: su caudal depende
   de la ΔP a su cota (el aire frío entra hacia el fuego), no de su altura.
6. **Uniforme frente a geométrica.** Con la misma área, la `open_fraction`
   uniforme mueve más masa por abajo (0,47 kg frente a 0,23 kg en A), calienta
   más la receptora (38 °C frente a 32 °C) y lleva más O₂ al fuego (0,37 kg
   frente a 0,20 kg). **No es la misma física**, y además activaría la
   deformación térmica, la radiación, la propagación del fuego y la caché como
   una puerta de verdad.
7. **El recinto estanco tiene una sobrepresión absurda.** En A y Aw cerradas se
   llega a 297–349 kPa, y las ventanas cerradas (0,005 m²) no la alivian. Con
   una rendija baja a 12–50 kPa, que sigue siendo irreal: una sala real no pasa
   de decenas de Pa. Es la patología ya conocida de presión de recinto cerrado
   (prerrequisito F2.2 en la memoria del proyecto). **Un caudal de orificio con
   √ΔP sobre estos kPa sería desmesurado.**
8. **La fuga sí da algo de aire al fuego y no lo convierte en puerta abierta.**
   En A, L2 lleva 0,20 kg de O₂ al fuego frente a 3,98 kg con la puerta abierta;
   el quemado y el pico quedan cerca de la puerta cerrada. Es la forma que se
   busca, aunque aquí salga por la heurística.

## 6. Diseño propuesto

### 6.1 Tres mecanismos separados

| mecanismo | cuándo | geometría | a qué ruta va |
|---|---|---|---|
| **Fuga permanente** (nueva) | `open_fraction <= EPSILON` y el interruptor encendido | holgura inferior + laterales + dintel (§6.2) | solver de fuga nuevo (§6.3) |
| **Deformación térmica** (existe) | puerta interior con `open_fraction < 0.5` y T > 150 °C | `thermal_gap_fraction` | con el interruptor apagado, igual que hoy. Opción a decidir: con él encendido, que ensanche los laterales y el dintel **dentro del mismo solver** en vez de ir por la heurística de fondo |
| **Apertura voluntaria** | `open_fraction > EPSILON` | hueco de la puerta | rutas actuales; la fuga se desactiva |

La ampliación bibliográfica añade un cuarto estado geométrico que no debe
confundirse con los anteriores: **pérdida de un paño acristalado**. Una grieta
sin caída no abre paso; el vidrio realmente desprendido crea una abertura
rectangular grande en la cota exacta del paño y va al solver Bernoulli de
aberturas. La deformación, en cambio, añade rendijas localizadas al solver de
fugas. Ninguno de los dos modifica `open_fraction`.

`open_fraction` no se toca: sigue siendo el estado operativo y visual.

### 6.2 Dato físico principal: área efectiva de fuga (ELA)

El dato que manda es el **área efectiva de fuga medida a una presión de
referencia**, no la geometría. **El hueco visible y el área efectiva de flujo
son cosas distintas**: la sonda de §3-§4 usaba áreas geométricas de 78-289 cm²,
y el área efectiva de una puerta real es un orden de magnitud menor (§7).

Parámetros del motor:

- `closed_door_effective_leakage_area_m2`: el valor por defecto de la clase
  `interior_tight`;
- `closed_door_leakage_reference_pressure_pa = 4.0`;
- `closed_door_leakage_flow_exponent`: el exponente `n` de la ley de potencia.
  Candidato provisional 0,65, dentro del intervalo 0,6-0,7 que CONTAM
  considera razonable sin dato experimental (TN 1887r1, p. 266); no es una
  calibración de puertas interiores residenciales.
- Convención del ELA (TN 1887r1, ec. 28-29): **ELA a 4 Pa con C_d = 1,0**. No
  hay coeficiente de descarga aparte (ver §12).

**Campo por abertura, en el modelo del motor** (`OpeningModel`), no deducido de
la vista:

- `leakage_class`: `interior_tight` (por defecto provisional en las puertas interiores),
  `entry_tight` (entrada de vivienda al portal) o `none` (estanca, para pruebas
  y huecos que no son puertas);
- `leakage_area_override_m2`: un ELA explícito para casos como una puerta vieja
  o muy desajustada. **No es un valor por defecto.**

El motor **no depende de `view/geometry/OpeningKinds.gd`** para saber si una
puerta es de entrada. Quien lo sabe es el editor (por ejemplo, la herramienta
del portal): escribe `leakage_class` en el JSON, `ScenarioSerializer` lo
conserva y `BuildingModel` lo carga.

**Reparto del ELA en cota.** El área efectiva total se reparte entre tres
elementos, solo para dar **dirección y composición por zonas**, sin cambiar el
total:

- **inferior**: `z ∈ [sill, sill+ε]`;
- **laterales**: `z ∈ [sill, sill+H]`, en N bandas (propuesta: N = 8);
- **dintel**: `z = sill+H`.

Las fracciones se fijan como parámetros. Como punto de partida, la proporción
geométrica de una puerta de paso: unos 40 % abajo, 47 % en laterales y 13 % en
el dintel.

### 6.3 Flujo de grieta por ley de potencia (un estado por puerta y paso)

Una puerta cerrada no es una abertura normal ni un orificio uniforme. Para cada
elemento o banda en la cota z:

1. **Presión a cada lado.** `p_i(z) = p_i,ref − g·∫ρ_i dz`, con las densidades
   de las dos zonas de la sala y su sobrepresión como `p_i,ref`, **sin el
   recorte del plano neutro al 5-90 %** del cálculo de puertas abiertas.
2. **Caudal de grieta con ley de potencia**, calibrado con el ELA a la presión
   de referencia:
   `Q_k = f_k · ELA · sqrt(2·ΔP_ref/ρ) · (|ΔP(z)| / ΔP_ref)^n`, con el signo
   de ΔP y `ṁ = ρ_src·Q` (ELA a 4 Pa, C_d = 1,0). Opcionalmente, una
   regularización **numérica** lineal cerca de ΔP = 0; con 0, ley pura (§12).
3. **Zona de origen y lado receptor**: el origen es la zona de la sala de
   origen en esa cota. Del receptor solo se informa la zona geométrica que
   ocupa esa cota y su densidad. *(Corregido el 2026-09-17: se retira la regla
   "a la capa alta si el gas es más caliente"; la deposición la decide el
   consumidor de transporte, §12.4.)*
4. **Cinturón numérico**: una fracción máxima de la zona de origen por paso.
   **Es solo seguridad numérica.** No valida ni oculta una ΔP fuera de rango:
   si se activa con presiones de más de unos cientos de Pa, cuenta como fallo
   del guardarraíl, no como resultado.

El resultado es una lista de flujos dirigidos
`(sala/zona origen → sala/zona destino, kg)`, calculada **una vez**.

### 6.4 Un solo consumidor, todas las magnitudes

Cada flujo es una parcela con la composición de su zona de origen. Mueve a la
vez:

- **masa de gas** (`upper_gas_kg`/`lower_gas_kg`);
- **entalpía**;
- **O₂**, con propietarios propios del ledger y el recuento `writer_coverage`
  actualizado;
- **humo**;
- **CO, CO₂, HCN, HCl, acroleína y formaldehído**, con su reparto por zonas.

La **presión** no se iguala al instante: las puertas con fuga no entran en
`_equalize_thermodynamic_pressure_components`; se relaja por el caudal.

La fuga **no** alimenta el derrame de `SmokeModel`, la parcela de ~1990, el
intercambio de fondo, la caché de puertas abiertas, la radiación, la
propagación del fuego, el PPV ni la búsqueda de camino al exterior.

### 6.5 Interruptores y activación

- `SimulationEngine.closed_door_leakage_enabled: bool = false` y el
  equivalente en `BuildingModel`; el motor usa `export OR escenario`.
- `ScenarioSerializer.EDITOR_CLOSED_DOOR_LEAKAGE_ENABLED` y el paso por
  `tools/run_scenario_headless.gd`, **solo en la etapa de integración (paso 6
  de §6.6)**.
- Los casos oficiales no lo encienden. Apagado, todo idéntico byte a byte.
- Registrar el interruptor en `scripts/simulation/audit_default_off_flags.py`
  (física viva, fuera del alcance P1R4) y subir `EXPECTED_DECLARATION_COUNT`.

### 6.6 Orden decidido (usuario, 2026-09-16)

1. **Modelo puro de fuga** (`ClosedDoorLeakageModel.gd`), probado con
   diferencias de presión **impuestas y razonables** (0-50 Pa, perfiles con y
   sin capa caliente). Sin conectar al paso del motor. **Hecho y validado
   (2026-09-17, §12); integrado después por D1 (§16).**
2. **Modelo puro de deformación prescrita**, con huecos independientes en
   suelo, laterales y dintel. **Implementado (2026-09-17, §13); integrado
   después por D2 (§18).** No se inventa aún una curva automática para
   puertas residenciales.
3. **Modelo puro de vidrio**, con estado por hoja
   `INTACT -> CRACKED -> PARTIAL_FALLOUT -> OPEN` y conversión del área
   desprendida en una abertura situada en el paño. `CRACKED` ventila cero.
   **Fase 3A (integridad prescrita) implementada el 2026-09-17 (§14), sin
   integrar.** **Fase 3B (geometría del camino libre multicapa) implementada
   el 2026-09-17 (§15), sin integrar**: produce rectángulos, no aberturas del
   motor ni caudales.
4. **No conectar todavía** esos modelos al portal ni activarlos en el editor.
5. **Resolver F2.2** (magnitud física de la sobrepresión de recintos cerrados)
   como cambio separado, también detrás de interruptor. **Diagnóstico y diseño
   cerrados el 2026-09-17 en
   [`PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md`](PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md);
   e implementados después hasta F2.2C.** Referencia (CFAST Model
   Evaluation Guide): en la validación con puerta cerrada se habla de
   sobrepresiones de **varios cientos de Pa**, no de los cientos de kPa medidos
   en §5.7.
6. **Integrar una tubería común de intercambio** con la presión corregida,
   encender explícitamente cada capacidad en el editor y medir de nuevo los
   casos A, Aw y B, más puertas acristaladas y ventanas multicapas.

## 7. Área efectiva: valores provisionales (recalificados el 2026-09-16)

Fuente primaria leída y guardada localmente: [NIST TN 2329](https://doi.org/10.6028/NIST.TN.2329),
pp. 26-29, para viviendas.

| clase | ELA a 4 Pa | m² | uso |
|---|---|---|---|
| `entry_tight` | **12 cm²** | 0,0012 | entrada de vivienda al portal (puerta con burlete) |
| `interior_tight` | **21 cm²** | 0,0021 | clase interior provisional; extrapolada de puerta garaje/sótano |
| override explícito | lo que diga el escenario | — | puerta vieja o muy desajustada; **nunca por defecto** |

- NIST TN 2329 usa **12 cm²** para una puerta exterior y **21 cm²** para una
  puerta entre vivienda y garaje y otra de sótano, como áreas efectivas a 4 Pa.
  Son estimaciones ASHRAE para puertas completas, no una medición universal de
  puertas interiores. El valor de 21 cm² se conserva como candidato
  provisional y debe calibrarse.
- Los trabajos NBSIR 81-2214 y *Analysis and Prediction of Air Leakage Through
  Door Assemblies* insisten en que las grietas estrechas no se comportan como
  un orificio uniforme.
- **L1/L2/L3 (78/174/289 cm²) quedan descartados como valores.** Eran áreas
  geométricas de la sonda, entre 4 y 24 veces por encima de estos ELA. Siguen
  valiendo como sensibilidad (§4-§5).
- Los valores son **provisionales** hasta medirlos con el modelo integrado
  (§6.6, paso 6).

**Efecto jugable esperado** (a comprobar tras la integración): humo débil y
tardío tras una puerta cerrada; la habitación cerrada sigue siendo refugio
durante bastante tiempo; la entrada con burlete protege más que una puerta de
paso. Es la lección de "cierra la puerta", sin convertir la rendija en una
puerta entreabierta.

## 8. Contrato para la implementación

- Interruptor apagado por defecto. Casos oficiales idénticos byte a byte con él
  apagado (CSV y JSON) y la suite de referencia en 346/346 con los mismos gaps.
- El editor lo enciende de forma explícita.
- Con el interruptor encendido:
  - humo distinto de cero tras una puerta cerrada fría;
  - llegada **claramente más tarde y en menor cantidad** que con la puerta
    abierta: tiempo hasta 1 g y hasta visibilidad < 10 m mayor, y humo máximo
    menor;
  - el fuego cerrado recibe algo de O₂: más que la puerta estanca y mucho menos
    que la abierta. El quemado queda lejos del de la puerta abierta.
- Cada parcela conserva masa de gas, entalpía, O₂, humo y especies, y lo
  anotan los ledgers existentes. El sistema es determinista.
- Guardarraíl mínimo de dos salas y guardarraíl integral del portal, en
  `check_product.py`.
- Antes de integrar: tests del modelo puro con ΔP impuestas (caudal = ELA a
  4 Pa; escala con el exponente n; signo y cota; regularización numérica
  cerca de 0; reparto que conserva el total).
- Tras integrar: ningún paso con ΔP entre salas por encima de unos cientos de
  Pa en los casos A, Aw y B, y el cinturón numérico sin activarse.
- Mutaciones que deben morir: no se activa; se activa siempre; el editor no lo
  enciende; se ignoran la clase o el override; el ELA se ignora o no escala;
  se ignoran la presión de referencia o el exponente; flujo de orificio en vez
  de ley de potencia; todo en una cota (sin posición); el
  humo no viaja; el O₂ no viaja; la energía no viaja; la masa sale sin llegar
  (conservación); la puerta con fuga entra en la igualación instantánea de
  presión; la fuga sigue activa con la puerta abierta.

## 9. Riesgos

1. **Sobrepresión de kPa del recinto estanco (F2.2).** Se resuelve **antes** de
   integrar (§6.6). El cinturón numérico no la tapa.
2. **Representatividad del ELA**: 12/21 cm² siguen siendo clases
   provisionales; falta una base experimental específica para puertas
   interiores residenciales y sus estados de ajuste. El reparto 40/47/13 entre
   holgura inferior, laterales y dintel tampoco está medido.
3. **Convención ELA resuelta:** los ELA utilizados están referidos a 4 Pa y
   emplean `Cd = 1,0`, según NIST TN 1887r1. El exponente `n = 0,65` queda
   como candidato provisional dentro del intervalo 0,6-0,7 recomendado por
   CONTAM cuando no existe medición específica. Sigue pendiente calibrarlo para
   las clases reales de puerta.
4. **Doble conteo con la deformación térmica**, que hoy va por la heurística de
   fondo. Con el interruptor encendido no deben actuar las dos a la vez.
5. **Curva de deformación sin calibrar**: los 150-350 °C y 4 % actuales no
   tienen respaldo localizado para puertas residenciales. Solo se implementan
   primero huecos dinámicos prescritos.
6. **Grieta no es desprendimiento**: abrir al primer fallo del vidrio
   sobreventilaría el incendio. El área solo aparece cuando se pierde material.
7. **Auditoría de escritores de O₂**: añadir propietarios y actualizar
   `writer_coverage` (47/25/22 desde el 2026-09-16).
8. **Inventario P1R4**: clasificar los interruptores nuevos y subir
   `EXPECTED_DECLARATION_COUNT`.
9. **R2-1**: tocar `sim/core` obliga a regenerar los informes de referencia.
10. **Rendimiento**: N bandas por puerta cerrada y paso; es barato.
11. **La vista**: el humo bajo la puerta y el vidrio roto necesitan efectos
   propios. Quedan fuera de esta etapa de física.

## 10. Archivos de una implementación posterior

- **Etapa 1 (modelo puro)**: `sim/core/ClosedDoorLeakageModel.gd` y sus tests
  con ΔP impuestas. **Hecha (2026-09-17, §12)**, e **integrada el 2026-09-18**
  por F2.2D1 (§16), que le añadió el ayudante canónico de un segmento;
- **Etapa 2 (deformación prescrita)**: `sim/core/ClosedDoorDeformationModel.gd`
  y sus tests. **Implementada (2026-09-17, §13) e integrada el 2026-09-20**
  por F2.2D2 (§18);
- **Etapa F2.2**: cerrada hasta F2.2C en
  [`PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md`](PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md);
- **Etapa de integración**:
- `sim/core/GasExchangeSystem.gd` (paso de fuga, consumidor, exclusión de la
  igualación de presión);
- `sim/core/OxygenExchangeSystem.gd` o el consumidor único (O₂ con ledger);
- `sim/core/SimulationEngine.gd` (interruptor, parámetros, `_effective_*`,
  configuración, caché);
- `sim/building/OpeningModel.gd` (`leakage_class`, `leakage_area_override_m2`);
- `sim/BuildingModel.gd`, `editor/ScenarioSerializer.gd`,
  `tools/run_scenario_headless.gd`;
- `tools/validate_closed_door_leakage.gd` (nuevo),
  `tests/fixtures/closed_door_leak_two_rooms.json` y
  `tests/fixtures/closed_door_leak_portal.json` (nuevos),
  `scripts/check_product.py`;
- `scripts/simulation/audit_default_off_flags.py` y
  `tests/test_p1r4_flag_activation_inventory.py` (clasificación);
- `sim/validation/reports/*` (regeneración R2-1) y la documentación.

## 11. Ampliación de diseño: puertas deformables y paños acristalados

Esta sección es normativa para la implementación futura y amplía el alcance
original de fugas. Cuando haya conflicto, sustituye la interpretación anterior
de `thermal_gap_fraction` como porcentaje uniforme.

### 11.1 Componente de integridad

La abertura necesita un estado de integridad independiente de su estado
operativo. La propuesta es un componente `OpeningIntegrity` que mantenga:

- fuga permanente en frío: clase, ELA, presión de referencia y override;
- huecos dinámicos: lista de segmentos con cota, longitud/área efectiva y
  origen (`prescribed`, `thermal`, `mechanical`);
- paños acristalados: geometría local, tipo, espesor, número de hojas, borde
  protegido, estado por hoja y fracción desprendida;
- daño de hoja, marco, cerradura y bisagras, reservado para extensiones.

`OpeningModel.open_fraction` sigue describiendo únicamente si una persona ha
abierto la puerta o ventana. La integridad dañada no cambia ese valor.

### 11.2 Contrato de los paños acristalados

Una puerta y una ventana pueden contener cero o más `glazing_panels`. Cada
panel sigue:

`INTACT -> CRACKED -> PARTIAL_FALLOUT -> OPEN`

- `CRACKED` mantiene área de ventilación cero;
- `PARTIAL_FALLOUT` abre solo el área ausente;
- en vidrio múltiple se exige un camino libre coincidente a través de todas
  las hojas antes de crear intercambio;
- el rectángulo resultante conserva anchura, altura y cota reales y usa el
  flujo de abertura grande, no la ley de rendijas;
- la primera versión admite historias prescritas para validación y una
  respuesta probabilista reproducible con semilla fija para escenarios.

No se admite abrir toda la puerta por romper su cristal ni abrir toda la
ventana al primer agrietamiento.

### 11.3 Contrato de deformación

- La deformación añade huecos localizados al dintel, laterales o suelo.
- Esos huecos usan el mismo solver que la fuga fría y se suman sin doble
  conteo de ELA.
- La implementación inicial recibe huecos prescritos. No convierte todavía la
  temperatura de la capa alta en milímetros de apertura.
- La heurística heredada 150-350 °C/4 % queda intacta con los interruptores
  apagados, pero no se reutiliza como calibración del modelo nuevo.
- Los resultados de Prieler se usan para la topología (dintel/cerradura) y las
  pruebas de interfaz, no como valores automáticos de una puerta residencial.

### 11.4 Una única tubería de transporte

Tanto una rendija como un paño perdido producen estados de flujo dirigidos que
se consumen una sola vez. Cada parcela mueve simultáneamente masa de gas,
entalpía, O₂, humo y todas las especies tóxicas. No entra en la igualación
instantánea de presión ni activa la lógica de apertura voluntaria.

### 11.5 Guardarraíles adicionales

- mutación `CRACKED -> OPEN` debe morir;
- mutación que ignora el tipo, espesor, borde o número de hojas debe morir en
  su fixture específico;
- vidrio multicapas con una hoja intacta no puede ventilar;
- el área abierta debe coincidir con el desprendimiento y nunca superarlo;
- un hueco localizado debe cambiar de sentido al invertir el perfil de ΔP;
- deformación prescrita cero debe ser idéntica a la fuga fría sola;
- con los interruptores apagados, la física heredada y los informes oficiales
  permanecen idénticos byte a byte.

### 11.6 Fuentes que gobiernan esta ampliación

La revisión, los enlaces web, los datos extraídos y sus límites de uso están
en [`RESEARCH_PUERTAS_CRISTALES_FUGAS_2026-09-16.md`](RESEARCH_PUERTAS_CRISTALES_FUGAS_2026-09-16.md).
El manual de CONTAM (NIST TN 1887r1) fija la convención ELA a 4 Pa /
C_d = 1,0 y el intervalo 0,6-0,7 del exponente sin dato experimental.
Las copias abiertas se conservan en `docs/literature/NIST`,
`docs/literature/Doors` y `docs/literature/Glass`, registradas en el índice y
en el manifiesto de descargas.

## 12. Fase 1 implementada: modelo puro de fuga (2026-09-16, corregida el 2026-09-17)

`sim/core/ClosedDoorLeakageModel.gd` (sin `class_name`). Este párrafo describe
el cierre original de la fase pura: desde F2.2D1 (§16) el modelo sí lo consume
la red autoritativa, detrás de un interruptor apagado por defecto. No modifica
`open_fraction`; el transporte de humo, O₂, energía y especies pertenece al
aplicador atómico de la red.

### 12.1 Qué dicen las fuentes locales

| cuestión | fuente | lo que fija |
|---|---|---|
| definición de ELA | NIST TN 2329, p. 26 (ec. 1 y leyenda) | ELA en m², con **presión de referencia de 4 Pa**; es el dato del elemento *one-way flow using powerlaw* de CONTAM |
| **convención ELA / Cd** | **NIST TN 1887r1 (CONTAM User Guide), p. 266, ec. 28 y 29** | `L = Q_r·sqrt(ρ/2ΔP_r)/C_d`; dos convenciones habituales: **C_d = 1,0 con ΔP_r = 4 Pa** o C_d = 0,6 con ΔP_r = 10 Pa. `C_b = L·C_d·√2·ΔP_r^(1/2−n)` |
| ley en masa | TN 1887r1, p. 265, ec. 24 | `F = C_b·sqrt(ρ_origen)·ΔP^n` |
| **exponente sin dato experimental** | **TN 1887r1, p. 266** | un valor **entre 0,6 y 0,7 es razonable** si el ensayo no lo da |
| valores | TN 2329, p. 28 | 12 cm² y 21 cm²: *best estimate* de ASHRAE 2001 para una puerta sencilla **con burlete** y **sin burlete**; NIST aplica 21 cm² a la puerta garaje-vivienda y a la de sótano. Son **ELA a 4 Pa**, así que su convención es **C_d = 1,0** |
| uso para una puerta cerrada | TN 2329, p. 29 | la ley de potencia es la adecuada para la fuga de una puerta cerrada |
| exponente en puertas | NBSIR 81-2214, p. 4 y tabla 1 (p. 17); Gross y Haberman 1989, pp. 169, 172-173 | n entre 0,5 y 1,0 según el régimen; 0,5 para holguras de puerta en la tabla; práctica habitual de 0,5/0,625; paso de lineal a raíz cuadrada |
| segmentos en altura | Gross y Haberman, p. 177, observación 4 | dividir las holguras verticales en segmentos cuando la ΔP cambia con la altura |
| dominio | NBSIR 81-2214, pp. 7 y 10 | la ΔP a través de una puerta interior raramente pasa de 50 Pa |

### 12.2 Fórmula final

Con ELA a 4 Pa y C_d = 1,0 (TN 1887r1, ec. 24, 28 y 29), para cada segmento k
de área efectiva `A_k` y `ΔP_k = p_a(z_k) − p_b(z_k)`:

    Q_ref,k = A_k · sqrt(2·ΔP_ref/ρ_origen)          (ΔP_ref = 4 Pa)
    Q_k     = Q_ref,k · (|ΔP_k|/ΔP_ref)^n

- Sentido según el signo de ΔP (positivo, de a a b); `ṁ_k = ρ_origen·Q_k`; masa
  del paso = `ṁ_k·dt`. `ρ_origen` es la densidad de la zona de origen en esa
  cota; la densidad aguas abajo no cambia el caudal.
- **No hay coeficiente de descarga en la API ni en la fórmula**: la convención
  ya lo lleva dentro, así que no se puede aplicar dos veces.
  `discharge_coefficient` se rechaza, y también cualquier presión de referencia
  distinta de 4 Pa. **La convención 10 Pa / C_d 0,6 no está implementada.**
- Regularización numérica opcional: si `zero_pressure_regularization_pa > 0` y
  `0 < |ΔP_k| < ese valor`, `Q_k = Q(valor)·|ΔP_k|/valor`.

Perfil de presión de cada lado:
`p(z) = p_suelo − g·[ρ_inf·min(z, h_i) + ρ_sup·max(0, z − h_i)]`, con g = 9,81.

### 12.3 Parámetros

Todos son obligatorios y ninguno tiene valor oculto.

- `ela_reference_pressure_pa`: tiene que ser 4 Pa
  (`NIST_ELA_REFERENCE_PRESSURE_PA`).
- `flow_exponent`, en [0,5; 1,0]:
  - las fuentes de puertas lo hacen depender del régimen;
  - CONTAM considera razonable 0,6-0,7 sin dato experimental;
  - **0,65 es el candidato provisional** para las futuras integraciones
    (`PROVISIONAL_FLOW_EXPONENT_CANDIDATE`, solo informativo; el modelo no lo
    usa y el llamante sigue pasándolo);
  - **no es una calibración** de puertas interiores residenciales.
- `zero_pressure_regularization_pa` ≥ 0:
  - es un **recurso numérico**, no un dato físico medido ni una transición de
    régimen calibrada;
  - 0 significa ley de potencia pura, y es la configuración recomendada para la
    primera integración salvo necesidad numérica demostrada;
  - con un valor positivo, el empalme es continuo, monótono y conserva el
    signo.
- `pressure_domain_max_pa`: por encima se **marca** `domain_exceeded` y **no
  se recorta**.

Claves rechazadas: `discharge_coefficient`, `reference_pressure_pa` y
`linear_regime_pressure_pa` (el nombre anterior). Las entradas inválidas (NaN,
infinitos, densidad ≤ 0, n fuera de rango, áreas negativas, ids duplicados,
dt < 0) → `valid = false`, sin flujos y con los errores listados; nunca se
recortan.

El reparto `PROVISIONAL_SPLIT` (40/47/13) y las clases `PLANNED_CLASS_ELA_M2`
(`none` 0, `entry_tight` 0,0012 y `interior_tight` 0,0021 m², ELA a 4 Pa con
C_d = 1,0) son constantes informativas. `OpeningModel` no las conoce todavía.

### 12.4 API

- `build_door_segments(ela_m2, sill_z_m, door_height_m, split, side_band_count)`
  → `{valid, errors, segments}`. Los segmentos son `bottom`, `side_00`… y
  `top`, cada uno con `{id, z_m, area_m2}`; la suma es el ELA total a precisión
  de máquina.
- `compute_flows(segments, side_a, side_b, params, dt_s)` →
  `{valid, errors, flows, net_mass_a_to_b_kg_s, gross_mass_kg_s,
  max_abs_dp_pa, domain_exceeded}`, ordenado por `(z_m, segment_id)`.
- Cada lado es `{floor_z_m, interface_height_m, rho_lower_kg_m3,
  rho_upper_kg_m3, p_floor_pa}`.
- Cada flujo lleva:
  - `segment_id`, `z_m`, `area_m2`, `dp_pa` y `direction`;
  - `volume_flow_m3_s`, `signed_volume_flow_m3_s`, `mass_flow_kg_s` y
    `mass_step_kg`;
  - `source_side`, `source_zone` y `source_density_kg_m3`;
  - `destination_side`, `destination_zone_at_height` y
    `destination_density_at_height`.

**El lado receptor solo describe el cruce.** `destination_zone_at_height` es la
zona geométrica que ocupa la cota del segmento en el recinto receptor (medida
desde su propio suelo), y `destination_density_at_height` es la densidad de esa
zona. El solver **no decide** flotabilidad, mezcla, ascenso ni descenso de la
parcela, ni su deposición definitiva en la capa alta o baja: eso corresponde al
futuro consumidor único de transporte, cuando tenga temperatura, entalpía y
composición. Queda retirada la regla anterior de §6.3, que mandaba el gas a la
capa alta si era menos denso que la zona baja receptora.

### 12.5 Pruebas y mutaciones

- `tools/validate_closed_door_leakage_model.gd` (en `check_product.py`): 18
  grupos con ΔP impuestas entre 0 y 50 Pa, más una por encima para el dominio.
  Incluye la comparación directa con la forma de CONTAM (ec. 24 y 29, C_d = 1),
  el rechazo de 10 Pa y de `discharge_coefficient`, la regularización con 0 y
  con valores positivos, y la zona receptora por cota (debajo y encima de la
  interfaz, gas ligero y pesado, suelo del receptor a otra cota).
- `tests/test_closed_door_leakage_model.py`:
  - pureza;
  - convención 4 Pa / C_d 1,0 sin coeficiente en la fórmula;
  - exponente y regularización sin valor oculto;
  - el solver no decide la deposición;
  - no integración;
  - volcado idéntico byte a byte.
- 30 mutaciones muertas (arnés local, sin versionar, en
  `runs/leak_model_20260916/mutate.py`). Entre ellas:
  - un factor 0,6 artificial (C_d aplicado dos veces);
  - aceptar `discharge_coefficient` o la convención de 10 Pa;
  - ignorar la regularización, o aplicarla con 0;
  - restaurar la comparación de densidades;
  - fijar la capa receptora siempre alta o siempre baja;
  - ignorar la cota del segmento en el receptor.

## 13. Fase 2 cerrada: deformación prescrita pura (2026-09-17)

`sim/core/ClosedDoorDeformationModel.gd` (sin `class_name`). Este texto conserva
el contrato del modelo puro. Desde F2.2D2 (§18), un adaptador explícito lo
consume en la red, pero el modelo sigue sin leer temperaturas ni escribir la
fracción de apertura, no usa el hueco térmico heredado del motor
(`_step_door_deform`, 150-350 °C / 4 %), no transporta masa, energía, O₂, humo
ni especies y **no calcula caudales**: el único solver de flujo sigue siendo
`ClosedDoorLeakageModel`.

### 13.1 Qué respalda la evidencia y qué no

- **Topología (respaldada)**: en el ensayo y la simulación de Prieler et al.
  (2023, pp. 16-19, figs. 18-23), los huecos principales aparecen en el
  **borde superior** y en el **lado de la cerradura, por encima de ella**. En
  el lado de bisagras y pasadores los huecos y la fuga son menores. Gross y
  Haberman (p. 177, observación 4) justifican tratar las holguras verticales
  como segmentos a distintas cotas.
- **Magnitudes (no calibradas)**: los valores de esos estudios corresponden a
  una puerta cortafuegos de acero en un horno normalizado. Entre ellos, la
  deformación central de unos 10 mm a los 10 min y los huecos de 0,83-3,7 mm
  de Prieler 2020. **No son valores predeterminados** para puertas
  residenciales, y el modelo no convierte milímetros, deformación central ni
  porcentajes de hoja en área.
- **No hay ley automática temperatura-deformación**: la deformación es una
  historia **prescrita** por quien llama.

### 13.2 Magnitud y pistas

`additional_ela_m2` es **área efectiva adicional**, con la misma convención que
la fuga fría (ELA a 4 Pa con C_d = 1,0). No es área geométrica.

Cada pista es `{id, location, z_m, points, metadata?}`:

- `location` ∈ {`bottom`, `top`, `hinge_side`, `latch_side`};
- `id` es `bottom`, `top`, `hinge_side_NN` o `latch_side_NN` y tiene que ser
  coherente con `location`. `NN` son **exactamente dos dígitos ASCII** `0`-`9`
  (`00`-`99`). Se rechazan signos (`-1`, `+1`), espacios, decimales, letras,
  dígitos Unicode de otros sistemas (de ancho completo, arábigo-índicos) y
  cualquier otra longitud (`1`, `001`, sufijo vacío). No se usa
  `is_valid_int()`, que aceptaría signos;
- `points` es `[[time_s, additional_ela_m2], …]`, con tiempos finitos
  estrictamente crecientes y áreas finitas ≥ 0;
- `metadata` es un diccionario opcional que se conserva como procedencia y
  **no** entra en el cálculo, como cualquier otra clave de la pista.

### 13.3 Evolución temporal

- Antes del primer punto: **0** (`BEFORE_FIRST_POINT_VALUE_M2`); la
  prescripción empieza en su primer punto.
- En cada punto: su valor exacto. Entre puntos: interpolación lineal,
  continua en las uniones.
- Después del último punto: se mantiene el último valor, sin extrapolar.
- El área puede subir, bajar o ambas cosas: el modelo prescribe el estado y
  no supone cómo responde la puerta al enfriarse.

### 13.4 Combinación con la fuga fría

`ELA_total_local = ELA_fría_local + ELA_adicional_deformación`

- Un segmento con el mismo id y la misma cota se fusiona sumando áreas. Con el
  mismo id y otra cota, la combinación se rechaza.
- Un segmento de deformación nuevo (`hinge_side_NN`, `latch_side_NN`) solo se
  inserta si su área evaluada es positiva. Así, una deformación cero deja
  exactamente los segmentos, el total y los caudales de la fuga fría sola.
- La salida va ordenada por `(z_m, id)`. Cada segmento lleva `area_m2`,
  `cold_area_m2`, `additional_area_m2`, `location` y `contributions`
  (procedencia: `cold` o `deformation` con su `track_id`).
- Totales: `cold_ela_total_m2`, `additional_ela_total_m2` y
  `combined_ela_total_m2 = frío + adicional`, a precisión de máquina.

### 13.5 API

- `validate_tracks(tracks)` → `{valid, errors}`.
- `area_at(points, time_s)` evalúa una pista ya validada.
- `evaluate_tracks(tracks, time_s)` →
  `{valid, errors, time_s, segments, additional_ela_total_m2}`. Incluye
  también las pistas de área 0.
- `combine_with_cold(cold_segments, deformation_segments)` →
  `{valid, errors, segments, cold_ela_total_m2, additional_ela_total_m2,
  combined_ela_total_m2}`.
- `evaluate_and_combine(cold_segments, tracks, time_s)` hace las dos cosas y
  añade `time_s` al resultado.
- `side_band_center(sill, height, band, count)` →
  `{valid, errors, z_m}`, con la misma convención de bandas que la fuga fría.
  Comprueba que `sill` sea finito, que `height` sea finita y > 0, que
  `count` ≥ 1 y que 0 ≤ `band` < `count`. Si alguna falla, devuelve
  `valid = false`, el motivo y `z_m = NAN`: nunca divide por cero ni da una
  cota fuera de la puerta. Con entradas válidas, `sill < z_m < sill + height`.

La salida combinada se pasa directamente a
`ClosedDoorLeakageModel.compute_flows`, que solo lee `id`, `z_m` y `area_m2`.

### 13.6 Pruebas

- `tools/validate_closed_door_deformation_model.gd`, registrado en
  `check_product.py`, con 28 grupos:
  - los 25 obligatorios;
  - identidad y ubicación de las pistas;
  - identificadores laterales de exactamente dos dígitos ASCII (casos
    positivos `00`, `01`, `09`, `10` y `99`, y negativos con signo, espacios,
    decimales, letras, dígitos no ASCII y longitudes distintas);
  - precondiciones del centro de banda (primera, última, intermedia, banda
    única, `count` cero o negativo, índice negativo o igual a `count`, altura
    no positiva o no finita);
  - claves ajenas ignoradas (metadatos, temperaturas, hueco térmico);
  - salida solo geométrica.
- `tests/test_closed_door_deformation_model.py`:
  - pureza;
  - sin temperatura, sin fracción de apertura, sin hueco térmico y sin
    caudales;
  - contratos explícitos;
  - no integración;
  - validador en verde y volcado idéntico byte a byte.
- El test de no integración de la fase 1 admite ahora el modelo y el validador
  de la fase 2 como referencias a `ClosedDoorLeakageModel`: el modelo solo lo
  nombra en su documentación y el validador le pasa los segmentos combinados.
- **32 mutaciones muertas** (arnés local, sin versionar, en
  `runs/leak_model_20260916/mutate_deformation.py`). Cada mutación ejecuta el
  validador y los tests estáticos. Entre ellas:
  - volver a aceptar enteros con signo (`-1`, `+1`), letras, dígitos no ASCII
    u otras longitudes;
  - calcular el centro de banda sin validar;
  - aceptar `band == count`, bandas negativas o alturas no positivas.

### 13.7 Pendiente

- Magnitudes de `additional_ela_m2` por clase de puerta, material y exposición.
- Cualquier ley automática temperatura-tiempo-deformación, que solo llegará
  con una calibración defendible para puertas residenciales.
- Calibrar magnitudes y decidir una ley térmica futura sin doble conteo con el
  hueco térmico heredado (riesgo 4 de §9). La integración prescrita ya está
  cerrada en F2.2D2 (§18) y el campo heredado se ignora expresamente.
- Vidrio (§6.6, paso 3) y su integración F2.2D3.

## 14. Fase 3A implementada: integridad prescrita de paños acristalados (2026-09-17)

`sim/core/GlazingIntegrityModel.gd` (sin `class_name`). Es **solo la fase 3A:
integridad prescrita**, no un modelo de vidrio completo. **No está
conectado**: ningún sistema del motor, el editor, la vista ni los escenarios
lo carga, y no hay interruptor nuevo.

### 14.1 Qué hace y qué no

- Describe, **hoja a hoja**, el estado de integridad y la fracción de material
  desprendida que **prescribe** quien llama. Es **determinista**: sin
  temperatura, presión, flujo térmico, tiempo del motor ni aleatoriedad.
- **`CRACKED` no ventila**: la hoja agrietada sigue presente, con fracción 0.
- **No produce aberturas**: ni rectángulos de ventilación, ni área, caudal,
  sentido, diferencia de presión, zonas de origen o destino, ni transporte. No
  toca la fracción de apertura operativa ni el hueco térmico del motor.
- Tipo de vidrio, espesor, número y separación de hojas, marco y borde
  protegido se **validan y se conservan como procedencia**, sin efecto
  automático sobre el estado. Los tiempos y temperaturas de la bibliografía
  (Skelly, Peng, Wang, FSRI) no se usan como valores automáticos.

### 14.2 Contrato

**Panel**: `{id, width_m, height_m, sill_z_m, glass_type, thickness_m,
leaf_count, leaf_spacing_m, frame_material, edge_protection_depth_m, leaves,
metadata?}`

- `id`: texto no vacío. `width_m` y `height_m`: finitos y > 0. `sill_z_m`:
  finito. `thickness_m`: finito y > 0.
- `glass_type`: exactamente `annealed`, `toughened`, `laminated` u `other`,
  sin recortar ni normalizar. `other` exige
  `metadata.glass_type_description` (texto no vacío) y se conserva como
  `other`.
- `frame_material`: texto no vacío.
- `leaf_count`: entero ≥ 1, igual al número real de hojas.
- `leaf_spacing_m`: finito y ≥ 0; con una sola hoja tiene que ser 0.
- `edge_protection_depth_m`: finito y ≥ 0, con
  `2·profundidad < min(ancho, alto)`, para que quede vidrio expuesto.
- `metadata`, si existe, es un diccionario.

**Hoja**: `{id, index, events, metadata?}`, con `id` no vacío y único, e
`index` entero, único y dentro de `[0, leaf_count)`. Con esas tres
condiciones, los índices quedan consecutivos.

**Evento**: `{time_s, state, fallout_fraction}`.

| estado | fracción |
|---|---|
| `INTACT` | exactamente 0 |
| `CRACKED` | exactamente 0 |
| `PARTIAL_FALLOUT` | 0 < f < 1 |
| `OPEN` | exactamente 1 |

- Tiempos finitos, ≥ 0 y estrictamente crecientes. Fracciones finitas dentro
  de [0, 1], que nunca disminuyen: el vidrio no se regenera.
- **Transiciones (contrato estricto)**: `INTACT → CRACKED → PARTIAL_FALLOUT →
  OPEN`, sin saltos ni retrocesos.
  - El primer evento puede ser `INTACT` o `CRACKED`, porque antes de él la
    hoja ya está `INTACT`.
  - Solo `PARTIAL_FALLOUT` puede repetirse, con fracción que no disminuye.
  - Se rechazan `INTACT → PARTIAL_FALLOUT`, `CRACKED → OPEN`, empezar en
    `PARTIAL_FALLOUT` u `OPEN`, y repetir `INTACT`, `CRACKED` u `OPEN`.

### 14.3 Evolución temporal

- Antes del primer evento: `INTACT`, fracción 0, sin evento activo
  (`event_index = -1`, `event_time_s = null`).
- En el instante exacto de un evento entra en vigor su estado.
- Entre eventos y después del último se mantiene el último estado,
  **sin interpolar** ni estados ni fracciones.
- El tiempo evaluado tiene que ser finito y ≥ 0.

### 14.4 API

- `validate_panel(panel)` → `{valid, errors}`.
- `evaluate_panel(panel, time_s)` → `{valid, errors, time_s, panel, leaves,
  damage_summary}`.
  - `panel` conserva identidad, geometría, tipo, espesor, hojas, separación,
    marco, borde y metadatos.
  - `leaves` va ordenado por índice. Cada hoja lleva `{id, index, state,
    fallout_fraction, source: "prescribed", event_index, event_time_s,
    metadata}`.
  - `damage_summary` es **solo diagnóstico**: cuántas hojas hay en cada
    estado. **No hay fracción de ventilación agregada** ni suma de
    fracciones.
- `evaluate_panels(panels, time_s)` → `{valid, errors, time_s, panels}`,
  ordenado por id; rechaza ids repetidos.

La salida no comparte diccionarios con la entrada y las entradas no se
modifican.

### 14.5 Multicapa

Cada hoja (una, dos o tres) tiene su propia historia. **Una fracción por hoja
no demuestra coincidencia**: dos hojas con un 30 % perdido pueden no tener
ningún agujero alineado. Por eso el modelo **no deduce** ningún camino libre ni
ventilación con mínimos, máximos, productos o medias. Tampoco lo hace cuando
una hoja está abierta y otra intacta, ni cuando todas tienen pérdida parcial.

### 14.6 Pruebas

- `tools/validate_glazing_integrity_model.gd`, registrado en
  `check_product.py`, con 28 grupos:
  - los 25 casos obligatorios;
  - saltos de estado rechazados;
  - claves de salida fijas y sin nada parecido a área, abertura, caudal,
    camino o presión;
  - pérdida parcial progresiva.
- `tests/test_glazing_integrity_model.py`:
  - pureza;
  - sin física térmica, aleatoria ni de flujo;
  - contrato estricto de estados;
  - función escalonada;
  - metadatos validados pero inertes;
  - no integración en `sim`, `editor`, `view`, `tools`, `scripts`, `scenes`,
    `ui`, `scenarios`, `tests`, `assets`, `i18n` y `project.godot`;
  - validador en verde y volcado idéntico byte a byte.
- **30 mutaciones muertas por fallos funcionales** (arnés local, sin versionar,
  en `runs/glazing_3a/mutate_glazing.py`).

### 14.7 Decisiones pendientes

- **Saltos de estado**: Wang et al. describen vidrio templado que, una vez
  roto, se desprende casi entero en poco tiempo. Eso podría justificar pasar
  de `CRACKED` a `OPEN` sin `PARTIAL_FALLOUT`, pero **no se admite** mientras no
  haya un contrato aprobado. Una historia prescrita puede representarlo con
  eventos muy próximos.
- **Laminado**: Peng et al. no observaron desprendimiento del vidrio laminado.
  El modelo no lo impone; quien prescribe decide.

### 14.8 Lo que queda para la fase 3B y después

*Nota actualizada (2026-09-21): la geometría de 3B está implementada (§15) y
D3 ya la convierte en aberturas del solver (§19). Siguen fuera el modelo
térmico/probabilista, la persistencia, el editor y la activación de producto.*

- **Fase 3B**: regiones desprendidas **explícitas** por hoja (rectángulos o
  máscaras en coordenadas del paño), su **intersección** entre hojas para
  obtener el camino libre real y la conversión de ese camino en aberturas
  rectangulares situadas en su cota, para el solver de abertura grande.
- Modelo térmico de rotura (tipo BREAK1, diferencia centro-borde, efecto del
  espesor, del marco y del borde protegido) y modelo probabilista de caída con
  semilla fija.
- Impacto mecánico, agua, integración en puertas y ventanas reales, editor,
  serialización y efectos visuales.

## 15. Fase 3B implementada: geometría del camino libre en acristalamiento multicapa (2026-09-17)

`sim/core/GlazingOpeningGeometryModel.gd` (sin `class_name`). Es **solo
geometría**: calcula por dónde queda un camino libre a través de **todas** las
hojas de un paño. **No es un caudal**, **no está conectado** a ningún sistema
del motor, el editor, la vista ni los escenarios, y no hay interruptor nuevo.

### 15.1 Principio

```text
camino_libre = huecos_hoja_0 ∩ huecos_hoja_1 ∩ ... ∩ huecos_hoja_n
```

- **`INTACT` y `CRACKED`** no tienen hueco: bloquean todo el paño.
  **`CRACKED` sigue sin ventilar.**
- **`OPEN`** es el paño completo. Se normaliza dentro del modelo.
- **`PARTIAL_FALLOUT`** deja libre solo la **unión** de sus regiones
  desprendidas.
- La intersección **nunca** se sustituye por mínimos, máximos, productos ni
  promedios de fracciones. Dos hojas con la misma fracción y regiones
  distintas pueden no dejar ningún camino.

### 15.2 Contrato espacial

La entrada tiene dos partes:

1. **Instantánea de la fase 3A**: la salida válida de
   `GlazingIntegrityModel.evaluate_panel`. El modelo 3B **no la reevalúa** ni
   carga el modelo 3A; solo comprueba que sea coherente.
   - `valid == true`;
   - panel con id, ancho y alto finitos y positivos, y cota del alféizar
     finita;
   - hojas con id único, índice entero único, estado conocido y fracción
     compatible con el estado.
2. **Entrada espacial**:

   ```text
   {panel_id, leaves: [{id, index, regions: [{id, x_m, z_m, width_m, height_m, metadata?}]}]}
   ```

   - `panel_id` **exactamente** igual al de la instantánea (§15.2.1).
   - **Exactamente una entrada por hoja**, con el mismo id exacto y el mismo
     índice.
     Se rechazan hojas ausentes, repetidas, desconocidas, sobrantes o con
     índice distinto, incluido un índice real en lugar de entero.
   - **Regiones**:
     - ids no vacíos y únicos **dentro de la hoja**; el mismo id en hojas
       distintas se admite;
     - coordenadas y tamaños finitos;
     - ancho y alto mayores que 0;
     - `metadata` opcional, pero si existe tiene que ser un diccionario;
     - **enteramente dentro del paño**. No se recorta ni se desplaza nada: una
       región que sobresale aunque sea 1e-9 m se rechaza.
   - **Por estado de la hoja**:
     - `INTACT` y `CRACKED` no admiten regiones;
     - `PARTIAL_FALLOUT` exige al menos una;
     - `OPEN` **no admite regiones**. Este es el único contrato: el paño
       completo se deduce del estado.

#### 15.2.1 Identificadores: vacío e identidad son cosas distintas

Corregido el 2026-09-17. La primera versión validaba los ids con la vista
recortada y después emparejaba con ella, así que `"pane_a"` y `" pane_a "` se
daban por el mismo panel, y un panel 3A llamado `" pane_a "` no podía
emparejarse ni escribiendo exactamente `" pane_a "`. La fase 3A siempre
conservó el texto original en su salida; ahora la 3B hace lo mismo.

- **Contenido**: un identificador tiene que ser `String` o `StringName` y no
  puede quedarse vacío al quitarle los espacios exteriores. `strip_edges()` se
  usa **solo** para esa comprobación, en `_is_blank_identifier`. Un
  identificador formado solo por espacios o tabuladores sigue siendo inválido.
- **Identidad**: el identificador real es el **texto original**. No se recorta,
  no se normaliza, no se cambia de caja. Se compara carácter a carácter y se
  devuelve tal cual en `panel_id`, en `leaf_union_areas_m2`, en `contributors`
  y en los mensajes de error.
- Por tanto `"pane_a"` y `" pane_a "` son paneles distintos, `"leaf_0"` y
  `" leaf_0 "` son hojas distintas y `"Leaf_0"` no es `"leaf_0"`. Si la
  instantánea trae `" leaf_0 "`, la entrada espacial tiene que traer
  exactamente `" leaf_0 "`.
- **Regiones**: misma regla. La identidad es exacta, también para detectar
  repetidos dentro de la hoja y como procedencia, así que `"r"` y `" r "` son
  dos regiones distintas y ninguna se normaliza en la salida.
- **Única excepción**: las hojas **repetidas** de la instantánea se detectan
  sobre el texto recortado. La fase 3A ya rechaza dos hojas que solo se
  diferencien en espacios exteriores, así que una instantánea fraudulenta
  tampoco cuela por la 3B.

### 15.3 Coordenadas

- **Locales**: el origen está en la esquina inferior izquierda del paño, con
  `0 ≤ x ≤ ancho` y `0 ≤ z ≤ alto`.
- **Cota global**: `global_sill_z_m = sill_z_m del panel + local_z_m`. Es la
  cota de la **base** de cada rectángulo.

### 15.4 Algoritmo exacto

1. **Rejilla**: los bordes x y z de todas las regiones, más los bordes del
   paño, se ordenan sin repetidos y forman una rejilla. Las celdas salen de los
   propios bordes, así que **no hay rasterización, resolución fija ni
   muestreo**.
2. **Unión dentro de cada hoja**: una celda está en el hueco de una hoja
   `PARTIAL_FALLOUT` si alguna región la **contiene entera**. Su procedencia
   son los ids de esas regiones, ordenados. Si dos regiones se solapan, la
   celda cuenta una sola vez. `OPEN` cubre todas las celdas sin regiones;
   `INTACT` y `CRACKED` no cubren ninguna.
3. **Intersección entre hojas**: una celda es libre si está en el hueco de
   **todas** las hojas.
4. **Fusión determinista** de las celdas libres:
   1. primero, tramos horizontales de celdas contiguas con **la misma
      procedencia**;
   2. después, de abajo arriba, se apilan los tramos con el mismo intervalo x
      y la misma procedencia.

   Nunca se fusiona a través de una celda no libre ni se rellenan huecos. Las
   islas desconectadas se conservan.

### 15.5 Representación canónica

- Los rectángulos son **disjuntos** y salen ordenados por
  `(local_z_m, local_x_m, width_m, height_m)`. Dos rectángulos disjuntos no
  comparten esquina inferior izquierda, así que el orden es total.
- Se numeran en ese orden como `fallout_path_000`, `fallout_path_001`, etc.
- Cada rectángulo lleva:
  - `id`, `local_x_m`, `local_z_m`, `global_sill_z_m`, `width_m` y `height_m`;
  - `area_m2 = width_m * height_m`;
  - `source = "glazing_fallout"`;
  - `contributors`: un elemento por hoja, en orden de índice, con
    `{leaf_id, leaf_index, leaf_state, region_ids}`.
- La hoja se ordena por índice, las regiones por id y el resto sale de la
  rejilla ordenada. Por eso invertir el orden de las hojas o de las regiones
  produce una salida **idéntica byte a byte**.
- El resultado incluye además:
  - `valid`, `errors`, `panel_id`, `panel_width_m`, `panel_height_m`,
    `panel_sill_z_m` y `panel_area_m2`;
  - `open_area_m2`: la suma de los rectángulos;
  - `leaf_union_areas_m2`: por hoja,
    `{leaf_id, leaf_index, state, union_area_m2, geometric_fallout_fraction, prescribed_fallout_fraction}`.
- La salida es una copia: no comparte referencias con las entradas, y las
  entradas no se modifican.
- Una entrada inválida devuelve `valid = false`, sus errores, ningún
  rectángulo y área 0.

### 15.6 Conservación y tolerancia

- En `PARTIAL_FALLOUT`, la unión geométrica de las regiones **sin doble
  conteo** tiene que cumplir dos condiciones:
  - valer más que 0 y menos que el área del paño;
  - coincidir con `area_panel · fallout_fraction` con
    `|fracción_geométrica − fallout_fraction| ≤ FRACTION_TOLERANCE = 1e-9`.
- **La tolerancia solo se usa en esa comprobación.** No interviene en la
  validación de límites, en la rejilla ni en la fusión.
- La geometría es la fuente y la fracción prescrita es el guardarraíl: si no
  coinciden, se rechaza. **Nada se escala** para forzar la coincidencia.
- **Invariantes comprobados** en el validador para cada resultado válido:
  - `0 ≤ open_area_m2 ≤ panel_area_m2`;
  - `open_area_m2 ≤ union_area_m2` de cada hoja;
  - con una sola hoja parcial, `open_area_m2` es igual a su unión;
  - con todas las hojas abiertas, `open_area_m2 == panel_area_m2`;
  - rectángulos disjuntos y dentro del paño;
  - `open_area_m2` es igual a la suma de los rectángulos y al área de
    intersección que el validador calcula aparte, con su propia rejilla y
    prueba de punto medio.

### 15.7 Limitaciones de esta primera versión

- Hojas **rectangulares, alineadas y coextensivas** con el paño: todas tienen
  el mismo ancho, alto y origen.
- Regiones **rectangulares alineadas con los ejes**. No hay curvas, polígonos
  arbitrarios ni hojas giradas, desplazadas o de tamaños distintos.
- La separación entre hojas no interviene: el camino se trata como recto,
  perpendicular al paño.
- Las regiones son **prescritas**: ni rotura térmica automática, ni
  probabilidad de caída, ni impacto mecánico, ni agua.
- Los **modelos térmico** (tipo BREAK1) **y probabilista** del vidrio **no
  están implementados**.

### 15.8 Sin flujo ni integración

- No hay Bernoulli, presión, caudal, sentido, velocidad, masa, volumen ni
  transporte de humo, O₂, energía o especies.
- No lee ni escribe la fracción de apertura operativa (`open_fraction`), el
  hueco térmico (`thermal_gap_fraction`) ni el estado de puertas o ventanas.
- **No lo carga** ningún sistema del motor (incluidos `SimulationEngine`,
  `GasExchangeSystem`, `OxygenExchangeSystem`, `OpeningModel`,
  `BuildingModel` y `ScenarioSerializer`), el editor, los escenarios, las
  fixtures de juego, la vista ni `project.godot`. Un test lo comprueba.
- **El siguiente paso no puede integrar todavía**. Convertir estos rectángulos
  en aberturas del solver de abertura grande exige antes **resolver F2.2** (la
  sobrepresión irreal de recintos cerrados, §6.6) y la tubería común de
  intercambio.

### 15.9 API

```text
compute_open_geometry(integrity_snapshot, spatial) -> {valid, errors, panel_id,
    panel_width_m, panel_height_m, panel_sill_z_m, panel_area_m2, rectangles,
    open_area_m2, leaf_union_areas_m2}
```

### 15.10 Pruebas

- **`tools/validate_glazing_opening_geometry_model.gd`**, registrado en
  `check_product.py`, con 34 grupos y 674 comprobaciones:
  - los 30 casos obligatorios;
  - `OPEN` con regiones rechazado;
  - instantáneas 3A inválidas rechazadas;
  - islas y huecos conservados;
  - identidad exacta de paneles, hojas y regiones (§15.2.1): espacios
    exteriores, mayúsculas, `StringName`, ids en blanco, procedencia
    conservada e instantánea fraudulenta.

  Las instantáneas se construyen con el propio modelo 3A, lo que prueba
  también la cadena 3A → 3B. Por eso el test de aislamiento 3A permite el
  validador y el test de la fase 3B.
- **`tests/test_glazing_opening_geometry_model.py`** comprueba:
  - pureza;
  - que no hay física de flujo, térmica ni aleatoria;
  - que el camino libre es una intersección y no una fórmula de fracciones;
  - la correspondencia entre estados y huecos;
  - la geometría exacta, sin recortes;
  - que la tolerancia solo se usa en la conservación;
  - la salida canónica;
  - la identidad exacta de los identificadores;
  - la no integración;
  - el validador en verde y el volcado idéntico byte a byte.
- **30 mutaciones muertas por fallos funcionales** del validador (arnés local,
  sin versionar, en `runs/glazing_3b/mutate_geometry.py`). Cubren:
  - `CRACKED` abierto;
  - una hoja ignorada;
  - unión en vez de intersección;
  - mínimo, producto y promedio de fracciones;
  - caja envolvente;
  - doble conteo de solapes;
  - regiones fuera del paño, aceptadas o recortadas;
  - tamaños nulos o negativos;
  - regiones en una hoja intacta;
  - fracción sin comprobar;
  - dos errores de cota global;
  - una isla perdida;
  - fusión a través de un hueco;
  - dependencia del orden de las hojas o de las regiones;
  - entradas modificadas;
  - `open_fraction` escrita;
  - presión y caudal calculados;
  - paneles u hojas emparejados por el texto recortado;
  - una versión recortada que se acepta como el identificador original;
  - el id de hoja recortado en `contributors` o en las áreas por hoja;
  - el id de panel recortado en la salida;
  - un id de región normalizado en silencio;
  - ids en blanco aceptados.

  Una mutación que quitaba la copia profunda de `contributors` se descartó por
  **equivalente**: esas listas se crean nuevas y nunca se comparten, así que
  solo la detectaba el test estático.

## 16. Fase F2.2D1 implementada: fuga fría de puerta cerrada en la red autoritativa (2026-09-18)

> **Estado: cerrada.** La fuga permanente de una puerta interior **cerrada y
> fría** ya no es un modelo suelto: es un elemento más de la red autoritativa de
> presión, detrás de `closed_door_leakage_enabled`, apagado por defecto y
> dependiente de `pressure_network_solver_enabled`. Este estado histórico de D1
> fue ampliado por D2 el 2026-09-20 (§18) y por D3 el 2026-09-21 (§19); la
> calibración y activación de producto (D4) **siguen fuera**.

### 16.1 El reparto de F2.2D en cuatro

Lo que el diseño llamaba «F2.2D» eran cuatro trabajos distintos, con riesgos y
evidencias distintas. Se separan para poder cerrarlos de uno en uno:

| | qué integra | estado |
|---|---|---|
| **D1** | fuga **fría** permanente de puerta cerrada (rendijas ELA) | **cerrada (2026-09-18)** |
| **D2** | deformación prescrita de puerta caliente (`ClosedDoorDeformationModel`) | **cerrada (2026-09-20)** |
| **D3** | paños acristalados (`GlazingIntegrityModel` + `GlazingOpeningGeometryModel`) | **cerrada (2026-09-21)** |
| **D4** | calibración de clases de ELA, reparto por cotas y exponente | sin hacer |

A esos cuatro hay que añadir uno que **no estaba en el reparto** y que las
mediciones de §16.12 destapan: la **fuga de envolvente**. F2.2C apagó la purga
que daba área de fuga a las ventanas exteriores cerradas, la red no la
sustituyó, y D1 rechaza expresamente una rendija contra el exterior. Hoy, con la
red encendida, la envolvente queda perfectamente estanca.

### 16.2 El interruptor y su dependencia

`SimulationEngine.closed_door_leakage_enabled` es **uno solo** y nace apagado.
La fuga fría solo existe dentro de la red, así que pedirla sin la red es un
error de configuración explícito: el motor publica
`pressure_network_failure = "closed_door_leakage_requires_pressure_network"` y
un `push_error`. **No se ignora en silencio y no enciende el solver por detrás
para taparlo.** Ningún escenario del producto enciende ninguno de los dos.

### 16.3 Dónde vive cada cosa

- `sim/core/ClosedDoorLeakageModel.gd` — la **ley**. Ya existía (fase 1); D1 le
  añade `compute_segment_flow_from_dp()`, el ayudante canónico de un segmento.
- `sim/core/ClosedDoorLeakageNetworkAdapter.gd` — **nuevo**. Traduce una puerta
  a geometría de rendija. No resuelve presión, no calcula caudal, no toca
  salas y no conoce el editor.
- `sim/core/Phase3CoupledPressureSolver.gd` — integra la rendija **dentro** del
  residuo de Newton, como una clase de elemento más.
- `sim/core/PressureNetworkTransportSystem.gd` — decide qué puerta aporta qué y
  aplica el transporte con el aplicador atómico de F2.2C, sin ruta nueva.

### 16.4 Una sola ley, escrita una vez

El solver **no** reimplementa la ley: llama a
`ClosedDoorLeakageModel.compute_segment_flow_from_dp()`, el mismo ayudante que
usa el modelo puro. Dos copias se habrían separado en cuanto una se corrigiera.
Dentro de `_integrate_crack` no hay ni una potencia, ni una raíz, ni un
coeficiente de descarga.

Tres cosas que la ley **no** es:

1. **No es Bernoulli.** Una rendija no es un orificio: el exponente es **0,65**,
   no 0,5. A 12 Pa (tres veces la referencia) los dos exponentes ya difieren un
   **18 %**, y a 40 Pa un **41 %**.
2. **No lleva un segundo `Cd`.** La definición de ELA (NIST TN 1887r1) es
   «el área que, con `C_d = 1,0` y **4 Pa**, da el caudal medido». Volver a
   multiplicar por 0,61 haría que 21 cm² dejaran de significar lo que mide el
   ensayo.
3. **No usa la densidad ambiente.** La densidad es la del gas **de origen**, la
   del lado del que sale, que es lo que decide cuánta masa lleva ese volumen.

### 16.5 Geometría: la rendija tiene cotas

La ELA se reparte en **40 % holgura inferior, 47 % laterales y 13 % dintel**
(reparto provisional, §6.2), y los laterales se discretizan en **ocho bandas**.
Cada segmento es un punto a su cota, con su propia `dp(z)`: por eso una misma
puerta puede **meter aire frío por abajo y sacar gas caliente por arriba** en el
mismo paso. Las cotas locales que devuelve `build_door_segments` se trasladan a
cotas absolutas en el adaptador, y solo allí.

Como una rendija son muestras discretas y no un vano continuo, el plano neutro
se obtiene **interpolando entre las dos muestras contiguas en las que `dp`
cambia de signo**, con el mismo convenio que una abertura grande: la cota es
`NaN` cuando no hay cruce, y `neutral_plane_inside` exige que caiga
estrictamente dentro de la hoja.

### 16.6 Exclusividad, y la deformación heredada que se desconectó

Una puerta es **o** una abertura grande **o** un conjunto de rendijas, nunca las
dos a la vez. Un `HOLE` nunca tiene fuga; una ventana tampoco; una puerta con
clase `none` y sin override es estanca.

**F2.2C leía `effective_open_fraction()`**, que suma `thermal_gap_fraction`, la
deformación térmica heredada. Esa suma era un acoplamiento accidental: una
puerta cerrada y caliente entraba en la red **como abertura grande de
Bernoulli**, con su vano completo y su `Cd`. D1 lee la fracción **operativa**
(`open_fraction`, y 1,0 para un `HOLE`) y decide el caso cerrado con
`is_closed()`. `effective_open_fraction()` no se borra: las rutas históricas
siguen usándolo y D2 lo necesitará, pero ya no gobierna la red.

### 16.7 Identificadores

F2.2C identificaba una abertura como `op_<a>_<b>_<tipo>`. **Dos puertas iguales
entre las mismas dos salas colisionaban**: la segunda pisaba a la primera. D1
usa el índice canónico de la abertura en el edificio: `op_<i>` para una abertura
grande y `crack_<i>` para su rendija. Único por construcción, estable y
determinista.

### 16.8 Escenario y editor

`OpeningModel` gana `leakage_class` (por defecto `"none"`) y
`leakage_area_override_m2` (por defecto `-1`, «sin override»). El override
válido **manda** sobre la clase. Una clase desconocida o un override no finito o
negativo **se rechazan** en la validación del escenario, no se corrigen por
detrás. El serializador conserva la clase al abrir y cerrar la puerta: es una
propiedad de la carpintería, no de su estado operativo.

Ningún escenario histórico gana fuga sin pedirla: sin `leakage_class` declarada,
el comportamiento es exactamente el de F2.2C.

### 16.9 Compatibilidad: qué cambia y qué no

Tres niveles, y conviene no confundirlos:

1. **Los dos interruptores apagados** (lo que corre hoy en todo el producto):
   byte a byte idéntico. D1 no toca ninguna ruta histórica.
2. **Red encendida, fuga apagada**: **no** es byte a byte idéntico a F2.2C, y
   no debe serlo. Difiere en exactamente dos cosas, y las dos son defectos
   corregidos: el identificador de abertura (antes dos puertas iguales entre las
   mismas salas colisionaban) y la fracción de apertura que lee la red (antes
   sumaba `thermal_gap_fraction`). El contrato de F2.2C se sigue cumpliendo: su
   validador pasa entero.
3. **Los dos encendidos**: aparece la fuga, y solo en las puertas interiores
   cerradas con clase declarada.

### 16.10 Mediciones

Los tres casos del §3 (A, Aw y B) se repitieron 600 s con la red encendida y
cuatro variantes de puerta: **estanca** (cerrada, clase `none`), **12 cm²**,
**21 cm²** y **abierta**. El arnes es `runs/f22d1_20260918/campaign.gd` y los
JSON estan en `runs/f22d1_20260918/campaign/`.

Dos avisos de lectura:

- La columna **ΔP máx puerta** solo existe para una rendija: es un diagnostico
  propio del elemento de grieta, y una abertura grande no lo publica.
- **1 g** y **vis<10 m** son el primer instante en que la sala receptora pasa de
  un gramo de humo y en que su visibilidad baja de 10 m.

#### Caso A (dos salas, 600 s)

| variante | quemado MJ | p máx fuego Pa | p máx receptor Pa | ΔP máx puerta Pa | masa transferida kg | humo receptor g | 1 g a los s | vis<10 m s | O₂ mín receptor | T máx receptor °C | pasos sin red | dominio>50 Pa |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| estanca | 67 | 0,00 | 0,00 | — | 0,000 | 0,0 | no llega | no llega | 0,2090 | 20,1 | 0 | 0 |
| fuga 12 cm² | 70 | 0,00 | 0,70 | 12,77 | 0,773 | 15,6 | 139 | 146 | 0,1975 | 21,4 | 29 | 0 |
| fuga 21 cm² | 70 | 0,00 | 1,04 | 12,05 | 1,383 | 25,6 | 128 | 135 | 0,1971 | 21,9 | 32 | 0 |
| abierta | 148 | 0,65 | 0,28 | — | 286,659 | 1 814,2 | 49 | 52 | 0,1299 | 168,0 | 0 | 0 |

#### Caso Aw (igual que A, con una ventana cerrada por sala)

| variante | quemado MJ | p máx fuego Pa | p máx receptor Pa | ΔP máx puerta Pa | masa transferida kg | humo receptor g | 1 g a los s | vis<10 m s | O₂ mín receptor | T máx receptor °C | pasos sin red | dominio>50 Pa |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| estanca | 67 | 0,00 | 0,00 | — | 0,000 | 0,0 | no llega | no llega | 0,2090 | 20,1 | 0 | 0 |
| fuga 12 cm² | 70 | 0,00 | 0,70 | 12,77 | 0,773 | 15,6 | 139 | 146 | 0,1975 | 21,4 | 29 | 0 |
| fuga 21 cm² | 70 | 0,00 | 1,04 | 12,05 | 1,383 | 25,6 | 128 | 135 | 0,1971 | 21,9 | 32 | 0 |
| abierta | 148 | 0,65 | 0,28 | — | 286,659 | 1 814,2 | 49 | 52 | 0,1299 | 168,0 | 0 | 0 |

#### Caso B (portal D de tres plantas, 600 s)

Fuego en la vivienda P0, con su puerta al portal **abierta**. Las dos
puertas que llevan la variante son las de las viviendas P1 y P2 al
rellano. El receptor de la tabla es la **vivienda P2**, la más lejana.

| variante | quemado MJ | p máx fuego Pa | p máx receptor Pa | ΔP máx puerta Pa | masa transferida kg | humo receptor g | 1 g a los s | vis<10 m s | O₂ mín receptor | T máx receptor °C | pasos sin red | dominio>50 Pa |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| estanca | 68 | 25,09 | 0,00 | — | 577,247 | 0,0 | no llega | no llega | 0,2090 | 20,0 | 2476 | 0 |
| fuga 12 cm² | 68 | 25,91 | -2,24 | 41,94 | 423,867 | 0,0 | no llega | no llega | 0,2090 | 20,0 | 4228 | 0 |
| fuga 21 cm² | 68 | 26,45 | -3,77 | 39,73 | 432,534 | 0,0 | no llega | no llega | 0,2090 | 20,0 | 4202 | 0 |
| abierta | 134 | 34,06 | -32,66 | — | 1 630,778 | 474,2 | 135 | 140 | 0,1509 | 35,0 | 0 | 0 |

Y lo que llega al portal R+2, el rellano al que da esa vivienda:

| variante | humo portal R+2 g | p máx portal R+2 Pa |
|---|---|---|
| estanca | 103,1 | -41,09 |
| fuga 12 cm² | 201,3 | -40,30 |
| fuga 21 cm² | 199,2 | -39,76 |
| abierta | 1 457,3 | -32,90 |

### 16.11 Lo que dicen las mediciones

Antes de leer nada: **solo los casos A y Aw dan evidencia utilizable**. En el
portal (B) la red no converge en más de un tercio de los pasos, y eso invalida
sus números como medida de la fuga (§16.14). Lo que sigue se refiere a A y Aw.

1. **El efecto queda claramente entre la puerta estanca y la abierta**, que es
   el criterio de aceptación. La sala protegida pasa de **no recibir nada** a
   recibir **15,6 g** (12 cm²) y **25,6 g** (21 cm²) de humo, frente a los
   **1 814 g** de la puerta abierta. El primer gramo llega a los **139 s** y
   **129 s** respectivamente, contra los **49 s** de la puerta abierta; y la
   visibilidad baja de 10 m a los **146 s** y **135 s**, contra **52 s**.
2. **La clase mayor fuga más**, en la dirección esperada: 21 cm² mueve
   **1,383 kg** frente a los **0,773 kg** de 12 cm², casi el doble, que es lo
   que cabe esperar de un área 1,75 veces mayor con una ley sublineal.
3. **El O₂ baja poco, y eso también es lo esperado**: 0,1975 y 0,1971 frente al
   0,2090 de la sala estanca y el **0,1299** de la puerta abierta. Una rendija
   no ventila un incendio; deja pasar humo.
4. **La puerta abierta no es una fuga grande.** Mueve **286,7 kg** —dos órdenes
   de magnitud más— y mete calor de verdad en la sala receptora (**168 °C**
   frente a los 21-22 °C de las variantes con rendija). Son fenómenos distintos,
   y la tabla lo enseña.
5. **La ΔP máxima en la rendija no llega a 50 Pa** (12,8 Pa con 12 cm² y 12,1
   con 21 cm²), así que ninguna medición sale del dominio experimental. No se ha
   impuesto ese límite: se ha medido, y la marca `domain_exceeded` existe
   precisamente para cuando se supere.

### 16.12 El caso Aw no aporta nada nuevo, y eso es un hallazgo

**Aw sale idéntico a A hasta el último decimal** en las cuatro variantes
(66,7361 MJ quemados con la puerta estanca, 15,6494 g de humo y 0,77263 kg
movidos con 12 cm², O₂ mínimo 0,197474; y 148,1031 MJ, 1 814,1975 g y O₂ 0,129929
con la puerta abierta). Aw solo se diferencia de A en que cada sala tiene una
**ventana exterior cerrada**, así que el resultado dice algo concreto: **con la
red autoritativa encendida, una ventana exterior cerrada es completamente
inerte**.

No es un fallo de D1; es una consecuencia de F2.2C que D1 deja al descubierto.
La fuga de envolvente de una ventana cerrada vivía en la purga por presión de
`GasExchangeSystem` (`window_leakage_area_m2`, 0,005 m²), y F2.2C la apagó junto
con el resto de rutas de transporte para que la red fuera dueña única. La red no
la sustituyó, y D1 **rechaza expresamente** una rendija contra el exterior
porque la fuga de fachada no es esta fase.

Resultado: con la red encendida, **la envolvente queda perfectamente estanca**.
Hay que arreglarlo, y es trabajo aparte de D2 y D3: una fase de fuga de
envolvente que vuelva a dar a ventanas y puertas exteriores cerradas su área de
fuga, ahora dentro de la red.

### 16.13 El límite honesto: la sala «estanca» pierde masa

Con la puerta estanca, la sala del fuego del caso A **pierde alrededor de un
tercio de su masa de gas mientras se calienta** (48,0 kg a 31,0 kg en 100 s), y
por eso su presión manométrica de la EOS se queda pegada a cero en vez de subir
a las centenas de kPa que tendría un recinto realmente estanco.

Esto **no lo introduce D1 ni F2.2C**: la misma sonda con la red **apagada**
pierde la misma masa hasta el kilogramo (31,0356 kg frente a 31,0348 kg a los
100 s). El sumidero es una ruta histórica que la red autoritativa no posee, y
que este encargo tenía prohibido tocar.

La consecuencia conviene decirla con precisión, porque es fácil equivocarse
al resumirla. Lo que se queda en **torno a 1 Pa** es la diferencia de presión
**entre recintos**, la que produciría la sobrepresión del incendio. Lo que de
verdad mueve la rendija en estas corridas es el término **hidrostático**: cada
segmento ve su propia `dp(z)`, y por eso la ΔP máxima medida en la grieta llega
a **12,8 Pa** aunque las dos salas estén casi a la misma presión. Dicho de otro
modo, **lo que está funcionando es la flotabilidad, no la sobrepresión**.

Por eso las cifras de fuga de §16.10 son una **cota inferior**: falta el empuje
que aportaría un recinto que se presurizara de verdad. El orden entre estanca,
12 cm², 21 cm² y abierta es sólido; las magnitudes se quedan cortas hasta que
esa ruta histórica se arregle.

### 16.14 Convergencia: los pasos en que la red no se aplica

Cuando la red no converge **no se aplica nada**: no hay transporte ese paso, el
motivo se publica en `pressure_network_failure` y no hay vuelta atrás silenciosa
a las rutas históricas. Eso es política de F2.2C, y D1 no la cambia. Lo que sí
hace D1 es dar la cifra:

| caso | variante | pasos | sin aplicar | % | motivo |
|---|---|---|---|---|---|
| A | estanca | 7200 | 0 | 0.0 % | — |
| A | 12 cm² | 7200 | 29 | 0.4 % | solver_iteration_cap (29) |
| A | 21 cm² | 7200 | 32 | 0.4 % | solver_iteration_cap (32) |
| A | abierta | 7200 | 0 | 0.0 % | — |
| Aw | estanca | 7200 | 0 | 0.0 % | — |
| Aw | 12 cm² | 7200 | 29 | 0.4 % | solver_iteration_cap (29) |
| Aw | 21 cm² | 7200 | 32 | 0.4 % | solver_iteration_cap (32) |
| Aw | abierta | 7200 | 0 | 0.0 % | — |
| B | estanca | 7200 | 2476 | 34.4 % | solver_compartment_equations_rejected_candidate (2476) |
| B | 12 cm² | 7200 | 4228 | 58.7 % | solver_compartment_equations_rejected_candidate (4228) |
| B | 21 cm² | 7200 | 4202 | 58.4 % | solver_compartment_equations_rejected_candidate (4202) |
| B | abierta | 7200 | 0 | 0.0 % | — |

Hay que leerla en dos partes, porque son dos problemas distintos:

**En dos recintos (A y Aw) el problema es de la rendija, y es pequeño.** Sin
grieta no falla ni un paso; con grieta fallan **29 de 7 200** (12 cm²) y **32 de
7 200** (21 cm²), un 0,4 %. La causa probable es la propia ley: la derivada de
`|Δp|^0,65` es **infinita en Δp = 0**, así que cada vez que un segmento cruza el
cero la iteración de Newton se encuentra un jacobiano que se dispara. El remedio
ya está montado y validado —`zero_pressure_regularization_pa`, que empalma la
ley con una recta desde el origen— pero D1 lo deja **en cero** a propósito, como
pedía el encargo: primero medir sin él. Ajustarlo es trabajo de D4.

> **Resuelto el 2026-09-18 por F2.2C-R1.** Lo que sigue describe lo que se
> midió con D1 y sigue siendo el registro fiel de aquel momento. La causa quedó
> demostrada después: la red metía el hueco de escalera como vano de Bernoulli
> anclado al suelo del recinto de abajo, y una zona sin inventario podía donar.
> Corregido eso, **P0, P1 y P2 convergen con 0 pasos descartados de 7 200**. La
> pista de las plantas a la misma presión absoluta era real pero secundaria: el
> defecto de datum existía y está corregido, pero no era lo que descartaba los
> pasos. Ver §17 del documento de sobrepresión.

**En el portal de tres plantas (B) el problema es anterior a D1, y es grande.**
Con las dos puertas **estancas y sin ninguna rendija**, la red ya se niega a
aplicarse en **2 476 de 7 200 pasos (34 %)**, y siempre por el mismo motivo:
`solver_compartment_equations_rejected_candidate`, es decir, el evaluador de
F2.2A rechaza el estado candidato.

Aquí había que comprobar algo antes de echarle la culpa a nadie. D1 desconecta
`thermal_gap_fraction` de la red (§16.6), y esa deformación **sigue activa por
defecto** (desde 150 °C, hasta un 4 %); los rellanos de B pasan de 325 °C. Cabía
la posibilidad de que, al dejar de contarla, las viviendas quedaran incomunicadas
y eso rompiera la convergencia. **Se midió, y no es eso**: en las 7 200 llamadas
del caso B el hueco por deformación existe en **84 pasos**, en **una sola
puerta** y con un máximo del **3,6 %**, mientras que los fallos son **2 476**.
Aunque los 84 se debieran enteramente a ese cambio, explicarían el **3 %** de
los fallos. El resto es una limitación de **F2.2C** en una red de seis recintos,
anterior a la fuga fría. Añadir la grieta la empeora
casi al doble: **58,7 %** con 12 cm² y **58,4 %** con 21 cm², sin que el tamaño
de la rendija cambie apenas nada. Lo que rompe la convergencia no es cuánto
fuga, es que haya que resolver una grieta.

Y hay un dato que apunta mejor todavía: **con las puertas abiertas del todo, el
portal converge sin un solo fallo (0 de 7 200)**. Es decir, el problema no es el
tamaño de la red ni el número de recintos, sino los recintos que quedan **casi
o del todo incomunicados**: la vivienda P1 y la P2, cuya única conexión es una
puerta cerrada y una ventana cerrada (que, por §16.12, no conduce nada). El
evaluador de F2.2A rechaza el candidato justo ahí.

La conclusión honesta es incómoda y conviene no maquillarla: **las cifras del
caso B no sirven como evidencia**. Un escenario en el que más de la mitad de los
pasos no transportan nada no mide la fuga, mide la falta de convergencia. La red
autoritativa **todavía no está lista para un portal de varias plantas**, y
arreglar eso es trabajo de F2.2 —del evaluador y del solver—, anterior y ajeno a
D2, D3 y D4.

Conviene además dejar dicho qué se vio en B, porque sorprende y porque alguien
lo va a volver a mirar. Las rendijas **sí mueven masa**: la de la vivienda P2 al
rellano mueve **4,05 kg** con 12 cm² y **6,90 kg** con 21 cm², con una ΔP máxima
de **41,9 Pa**, tres veces la del caso A y aún dentro del dominio experimental.
Y sin embargo **la vivienda P2 no recibe ni un gramo de humo** en ninguna de las
tres variantes cerradas.

No es una contradicción: es el sentido del flujo. Con la red encendida, el
rellano R+2 se queda a presión **negativa** (−41 Pa con las puertas estancas),
así que la rendija sopla **desde la vivienda hacia el rellano**, no al revés. La
vivienda pierde aire limpio en vez de recibir humo.

Y ese −41 Pa tiene una pista medida, que conviene dejar escrita porque acota
mucho la búsqueda. Las tres plantas del portal están a **z = 0, 2,90 y 5,80 m**,
y sus presiones manométricas con las puertas estancas son **+25,11**, **−8,14**
y **−41,09 Pa**. Las diferencias entre plantas son **−33,2** y **−33,0 Pa**,
mientras que la columna hidrostática del aire ambiente entre dos plantas es
ρ·g·Δz = 1,2 · 9,81 · 2,90 = **34,1 Pa**. Coinciden dentro de un 3 %.

Dicho de otro modo: **las tres plantas del portal están prácticamente a la misma
presión absoluta**, y todo el gradiente manométrico que se ve es la columna del
**exterior**. Eso es lo que saldría si la columna de gas **interior** del hueco
de escalera no estuviera pesando en el balance, o si el origen de la presión
manométrica no siguiera la cota. En un portal con un incendio abajo se esperaría
lo contrario: gas caliente, columna interior más ligera que la exterior, y por
tanto sobrepresión **creciente** hacia arriba.

No se afirma aquí cuál de las dos cosas es: es una **hipótesis medida**, no un
diagnóstico. Pero es la primera que hay que comprobar al retomar F2.2, y explica
por qué B no vale todavía como evidencia.

### 16.15 Mutaciones

Las 26 mutaciones del encargo, cada una aplicada sola al código de producción y
comprobada contra el validador que debe matarla. La campaña encontró **tres
cosas que arreglar**, que es para lo que sirve:

1. **`_integrate_opening` reventaba** si le llegaba un elemento de rendija,
   leyendo un `coefficient` que una grieta no tiene. Desde que la red es
   heterogénea, una ruta equivocada tiene que fallar limpiamente: ahora se
   rechaza.
2. **La conservación no distingue «no mover energía» de «mover cero»**: las
   mutaciones que dejaban la energía o el O₂ fuera del transporte sobrevivían a
   la validación de F2.2C. El caso 14 compara ahora lo que sale con lo que
   llega, ruta por ruta.
3. **Nadie contaba las aplicaciones.** Aplicar el transporte dos veces pasaba
   desapercibido, porque dentro de un paso completo del motor las demás rutas
   mueven más masa que la red. `commit_count` lo hace comprobable, y el caso 15
   exige exactamente una aplicación por paso.

También salió a la luz algo que **no** había que arreglar: la exclusividad
abierta/cerrada y el ELA cero están protegidos por **dos guardas
independientes** cada uno, así que ninguna mutación de un solo punto los rompe.
Esas mutaciones se reescribieron para tocar las dos guardas a la vez; siguen
siendo una sola mutación, porque el comportamiento que rompen es uno solo.

| # | mutación | quién la mata | resultado |
|---|---|---|---|
| 1 | La fuga se activa siempre, ignorando el interruptor | validador D1 | **muere** — FAIL: 11 leakage off leaves the closed door sealed |
| 2 | La fuga no se activa nunca | validador D1 | **muere** — FAIL: 08 a closed door only contributes a crack ([]) |
| 3 | La puerta abierta conserva ademas la fuga (dos guardas) | validador D1 | **muere** — FAIL: transport applied (solver_invalid_input) |
| 4 | Las ventanas tienen fuga de puerta | validador D1 | **muere** — FAIL: 11 a window is not a door for the cold leakage |
| 5 | Los huecos tienen fuga | validador D1 | **muere** — FAIL: 11 a hole has no cold leakage |
| 6 | Se ignora `leakage_class` y se usa siempre la interior | validador D1 | **muere** — FAIL: 08 a door with class none stays sealed |
| 7 | Se ignora el override del area | validador D1 | **muere** — FAIL: 11 the override wins over the class (0.0021) |
| 8 | Se intercambian las clases de 12 y 21 cm2 | validador D1 | **muere** — FAIL: 11 the entry class is 12 cm2 (0.0021) |
| 9 | Se aplica Cd = 0,61 encima de la ELA | validador D1 | **muere** — FAIL: 02 12 cm2 at 4 Pa gives the ELA definition (0.001890016 vs 0.003098387 m3/s) |
| 10 | La referencia de la ELA pasa a 10 Pa | validador D1 | **muere** — FAIL: 02 12 cm2 at 4 Pa gives the ELA definition (0.002700503 vs 0.003098387 m3/s) |
| 11 | El exponente de la rendija pasa a 0,5 (orificio) | validador D1 | **muere** — FAIL: 03 the crack law is not the orifice law at 1.0 Pa |
| 12 | Se usa densidad ambiente en vez de la del origen | validador D1 | **muere** — FAIL: 04 the upstream density is the source one |
| 13 | Toda la ELA se coloca en una sola cota | validador D1 | **muere** — FAIL: 05 the crack carries both ways at different heights (0 out high, 0 in low) |
| 14 | Se pierde un segmento lateral | validador D1 | **muere** — FAIL: 02 the segments add up to the full ELA |
| 15 | La fuga se calcula solo al recoger, no en el residuo | validador D1 | **muere** — FAIL: 01 identical rooms converge (invalid) |
| 16 | La rendija no entra en el residuo de Newton | validador D1 | **muere** — FAIL: 05 the crack carries both ways at different heights (4 out high, 0 in low) |
| 17 | Vuelve `effective_open_fraction()` con la deformacion antigua | validador D1 | **muere** — FAIL: 11 a deformed closed door is still only a crack (["op_0"]) |
| 18 | Se transporta masa pero no energia | validador D1 | **muere** — FAIL: 14 the receiver gains the energy the network moved (0.000000000 vs 2.506690265 kJ) |
| 19 | Se transporta masa pero no O2 | validador D1 | **muere** — FAIL: 14 the receiver gains the oxygen that left the source (0.000000000 vs 0.006476414 kg) |
| 20 | Se transporta masa pero no humo ni especies globales | validador F2.2C | **muere** — FAIL: 04 smoke reached the cold room |
| 21 | El transporte se aplica dos veces | validador D1 | **muere** — FAIL: 15 step 1 leaves exactly 1 applications (2) |
| 22 | La presion se iguala al instante | validador F2.2C | **muere** — FAIL: 04 the hot room keeps the higher pressure (0.000 vs 0.000) |
| 23 | La fuga se permite con la red apagada | pytest D1 | **muere** — FAILED tests/test_closed_door_leakage_network.py::test_leakage_without_the_network_is_an_explicit_failure |
| 24 | Vuelve el identificador que colisiona entre dos puertas | validador D1 | **muere** — FAIL: transport applied (solver_invalid_input) |
| 25 | Un ELA de cero produce caudal (dos guardas) | validador D1 | **muere** — FAIL: 10 a zero ELA carries nothing |
| 26 | La dp se recorta en silencio a 50 Pa | validador D1 | **muere** — FAIL: 10 the flow beyond the domain is not clamped (0.028000460 vs 0.049465509) |

**26 de 26 mutaciones mueren.**

### 16.16 Lo que D1 deja fuera

- La **deformación** era trabajo de D2 en el cierre histórico de D1; quedó
  integrada el 2026-09-20 (§18). `thermal_gap_fraction` sigue fuera de la red.
- El cierre histórico de D1 dejaba fuera el **vidrio**; D3 quedó integrada el
  2026-09-21 (§19). Siguen sin existir sus modelos térmico y probabilista.
- La **calibración** (D4): ELA, reparto por cotas y exponente siguen siendo
  provisionales, y con ellos la regularización de §16.14.
- La **fuga de envolvente**: una rendija contra el exterior se rechaza. D1 es
  fuga entre recintos.
- El **encendido en escenarios normales**: sigue haciendo falta pedir los dos
  interruptores y declarar la clase.

Y una cosa que D1 no deja fuera porque no le toca, pero que **bloquea** el uso
real de todo esto: la red autoritativa **no converge** en un portal de varias
plantas (§16.14). Mientras la mitad de los pasos no transporten nada, ni la
fuga fría ni lo que venga después se pueden medir ahí. Es trabajo de F2.2, del
  evaluador de F2.2A y del solver de F2.2B. Este bloqueo quedó resuelto por
  F2.2C-R1 antes de integrar D2; se conserva aquí como historia de D1.

## 17. F2.2-R2-MASS: por qué las cifras de §16 eran una cota inferior (2026-09-19)

§16.13 dejó escrito que las medidas de fuga de D1 eran una **cota inferior**
porque la sala del fuego perdía alrededor de un tercio de su masa de gas
mientras se calentaba, y su presión se quedaba cerca de la ambiente. Esa pérdida
ya está identificada y corregida, y conviene decir con precisión qué cambia y
qué no.

### 17.1 La causa no estaba en la rendija

No estaba en la ELA, ni en el exponente 0,65, ni en el reparto de bandas, ni en
el elemento de grieta. Estaba en la **proyección de zonas**, que reconstruía la
masa inferior del recinto como «volumen libre por densidad del aire a presión
ambiente». Con la red **apagada** la pérdida era la misma al kilogramo, que es
justo lo que §16.13 observó y no pudo explicar entonces.

El balance causal cerró exacto: de los −16,9652 kg perdidos en 100 s, los nueve
propietarios físicos aportaban **0,0000 kg** y `two_zone_boundary_mass_kg`
−16,9652 kg. El tope de la capa superior aportaba **0,0000 kg**: toda la pérdida
venía de la reescritura de la masa inferior. El detalle está en
`docs/PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md` §18.

### 17.2 Lo que cambia para la fuga

Con la masa conservada, el recinto **sí se presuriza**. Eso mueve el régimen de
trabajo de la rendija de sitio:

- Antes, lo que empujaba la grieta era casi solo el término **hidrostático**:
  ΔP entre recintos en torno a 1 Pa, y hasta 12,8 Pa por la altura de la puerta.
- Ahora la **sobrepresión** domina, y la ΔP a través de la rendija sube en
  varios órdenes de magnitud.

Las cifras de §16.10 —15,6 g y 25,6 g de humo transferido— **no se han
retocado, ni se ha recalibrado nada para acercarse a ellas**. Se vuelven a medir
en las mismas condiciones y el resultado se recoge en §17.4. Lo que ya no es
cierto es la razón por la que eran una cota inferior.

### 17.3 Una advertencia nueva, y es importante

Al presurizarse el recinto, la ΔP a través de la rendija se sale del **dominio
experimental** de los datos de los que sale la ley de potencia (NBSIR 81-2214,
hasta unos 50 Pa) durante la mayor parte de la simulación, y por márgenes
grandes.

El motor **no recorta**: registra `domain_exceeded` y sigue aplicando la misma
ley, exactamente como decidió D1. Pero conviene entender qué significa esa
bandera aquí:

- **No** es un fallo numérico. La red converge y la masa se conserva.
- **Sí** es una extrapolación. La ley `Q ∝ ΔP^0,65` se está evaluando muy lejos
  de donde se midió, y nada garantiza que el exponente siga valiendo allí.
- La causa de esas ΔP enormes **no es la rendija**: es que la envolvente
  exterior cerrada era inerte con la red encendida. **R3 lo cerró** el mismo
  19 de septiembre: la envolvente aporta su fuga dentro del residuo del
  solver, y las mediciones de §16.10 y §17.4 son ANTERIORES a ese cambio.
  Se conservan como historia, no como comportamiento actual.
  Un recinto real tiene fugas por fachada que impiden llegar a esas presiones.

Por eso las cifras de fuga **siguen sin ser definitivas**, aunque ya no por el
motivo de §16.13. No son una calibración, no son una cota definitiva y no son
todavía comportamiento publicable.

### 17.4 Medidas nuevas

Caso A, dos salas, 600 s, mismas clases de fuga que §16.10 (12 y 21 cm²):

| variante | quemado kJ | p máx sala fuego Pa | ΔP máx rendija Pa | masa transferida kg | humo en la receptora g | O₂ mín | T máx °C | pasos sin aplicar | pasos > 50 Pa |
|---|---|---|---|---|---|---|---|---|---|
| estanca (A1) | 59 219 | 121 656 | — | 0,000 | 0,000 | 0,1321 | 423,1 | 0 | 0 |
| fuga 12 cm² (A2) | 85 009 | 53 787 | 2 272,2 | 33,925 | **165,836** | 0,1311 | 486,6 | 0 | 5 290 |
| fuga 21 cm² (A3) | 85 511 | 53 608 | 970,1 | 33,161 | **149,031** | 0,1315 | 487,4 | 0 | 3 854 |
| abierta (A4) | 176 008 | 35 909 | — | 591,478 | 2 100,310 | 0,1087 | 565,6 | 0 | 0 |

El orden que exige el criterio de aceptación se mantiene donde importa: las dos
variantes con rendija quedan **entre** la puerta estanca (0 g) y la puerta
abierta (2 100 g), y la abierta sigue siendo claramente la más ventilada.

Frente a §16.10, el humo transferido pasa de 15,6 g a **165,8 g** con 12 cm², y
de 25,6 g a **149,0 g** con 21 cm². No se ha tocado la ELA, ni el exponente, ni
ninguna tolerancia: lo que ha cambiado es que el recinto ahora se presuriza.

### 17.5 El orden entre 12 y 21 cm² se invierte, y eso dice algo

En §16.10 la rendija mayor transfería más humo (25,6 frente a 15,6 g). Ahora
transfiere **menos** (149,0 frente a 165,8 g). No es un fallo: es la consecuencia
de haber cambiado de régimen, y conviene entenderla.

Las dos variantes generan casi el mismo humo (2 934 frente a 2 914 g) y queman
casi lo mismo, así que la diferencia no está en el fuego. Está en el transporte.
Con `Q ∝ A·ΔP^0,65`, al pasar de 12 a 21 cm² el área sube ×1,75 y la ΔP baja
×2,34, con lo que `ΔP^0,65` baja ×1,75: **se cancelan**. Por eso la masa
transportada es casi idéntica (33,9 frente a 33,2 kg). La fuga **se autolimita**
y el área ha dejado de mandar. La diferencia en humo viene del instante en que
ocurre el transporte: la rendija pequeña aguanta presión más tiempo y mueve gas
cuando la sala ya está más cargada.

En §16.10 la ΔP era de unos 12 Pa y la movía la flotabilidad, así que el caudal
lo dominaba el área y más área daba más trasiego. Ahora el recinto es un depósito
a presión y la rendija es su única válvula.

**Esta inversión es, por sí sola, el mejor argumento de que estas cifras no son
una calibración.** El orden cualitativo se da la vuelta en un régimen que los
datos experimentales nunca cubrieron. Hasta que R3 devuelva la fuga de envolvente
y las presiones vuelvan a un rango físico razonable, estas magnitudes describen
el modelo, no una vivienda.

## 18. F2.2D2: deformación prescrita integrada en la red (2026-09-20)

> **Estado: cerrada.** D2 conecta el modelo puro de §13 con la red autoritativa
> de presión. No añade una ley térmica, no calibra áreas y no activa esta física
> en escenarios distribuidos.

### 18.1 Contrato y arquitectura

- `closed_door_deformation_enabled` está apagado por defecto y exige
  `pressure_network_solver_enabled`. Pedir D2 sin la red es un error explícito.
- `OpeningModel.deformation_tracks` es un estado de ejecución deliberadamente
  no persistido. D4 decidirá el contrato de producto, serialización y editor.
- `ClosedDoorDeformationNetworkAdapter` evalúa las pistas en el `sim_time_s`
  autoritativo, convierte una sola vez sus cotas locales a cotas absolutas y
  entrega segmentos al mismo elemento `ela_crack` que usa D1.
- La ley de flujo no se repite: siguen gobernando ELA a 4 Pa, `Cd = 1`, el
  exponente 0,65 provisional, la densidad del gas de origen y la regularización
  canónica de D1. El elemento participa en el residuo de Newton y el aplicador
  atómico mueve masa, energía, O2, humo y especies.
- D1 y D2 son independientes. D2 funciona sin clase de fuga fría; si ambas se
  piden, las áreas fría y adicional se combinan por segmento. D2 no modifica
  `open_fraction` y una puerta abierta excluye la ruta de rendija.
- `thermal_gap_fraction` y la heurística heredada de deformación automática no
  intervienen. Una pista inválida falla cerrada; no se acepta parcialmente.

### 18.2 Identidades protegidas

- D2 apagada conserva exactamente la ruta anterior.
- Una historia cuya área adicional evaluada es cero devuelve el elemento frío
  original sin reconstruirlo: identidad fuerte con D1 sola.
- Una puerta sin pistas no inventa deformación.
- La presión de cada segmento se evalúa en su cota física; no se colapsan
  `bottom`, `top` y los tramos laterales en una única abertura.

Durante la validación apareció un defecto real: una única pista localizada
producía un elemento común con `bottom == top`, que el solver rechazaba aunque
la grieta puntual fuera válida. El elemento conserva ahora el tramo físico
completo entre umbral y dintel, mientras el segmento de grieta permanece en la
cota prescrita. Esto evita inventar altura y mantiene la localización del flujo.

### 18.3 Evidencia funcional

El validador dedicado cierra **41 comprobaciones**. La batería relacionada
cierra **77 pruebas Python**, incluidas las rutas históricas D1 y de red. La
campaña mata **17 de 17 mutaciones válidas**. Dos sustituciones iniciales
afectaban dos coincidencias a la vez y eran mutaciones inválidas del arnés: se
descartaron, se reescribieron con alcance único y murieron por fallo funcional.

Campaña diagnóstica de 600 s, 7 200 pasos, con una historia prescrita de ejemplo
deliberadamente **no calibrada** (ELA superior hasta 0,003 m2 y lado de
cerradura hasta 0,001 m2):

| variante | masa neta a la receptora (kg) | humo en receptora (g) | dp máxima de segmento (Pa) | pasos sin aplicar |
|---|---:|---:|---:|---:|
| estanca | 0,0000 | 0,000 | — | 0 |
| fuga fría D1 | 1,2083 | 6,594 | 5 519,0 | 0 |
| solo D2 prescrita | 0,7513 | 5,603 | 5 751,7 | 0 |
| D1 + D2 | 0,6525 | 9,565 | 5 519,1 | 0 |

Que la masa neta combinada sea menor que con D1 sola no implica menos
intercambio: los segmentos a distintas cotas admiten contraflujo. El humo sí
aumenta en el caso combinado. Las cifras solo demuestran que la topología, el
tiempo, el solver y el transporte están conectados; **no autorizan calibración**.

### 18.4 Límites y siguiente fase

- Las ELA prescritas del ensayo no representan una clase de puerta residencial.
- Las dp de 5,5-5,8 kPa están muy fuera del dominio experimental de unos 50 Pa;
  el motor registra la extrapolación y no recorta el flujo.
- No existe todavía una relación temperatura-tiempo-deformación defendible, ni
  una respuesta automática al calentamiento o al enfriamiento.
- Ningún escenario normal ni el editor activa o serializa D2.
- **D3 quedó cerrada el 2026-09-21** (§19). El siguiente trabajo es **D4**:
  calibración, persistencia, editor y activación conjunta.

### 18.5 Cierre de verificación

- Suite de referencia: **346/346 required PASS**, con los mismos **78** gaps
  documentados; en `reference_checks.json` solo cambió `generated_at`.
- Guardarraíles científicos: **ALL PASS**, incluida la frescura R2-1.
- Suite Python global: **2.855 passed**, **4 skipped**, **42 subtests passed**.
- `check_product.py`: **151/151**.
- Al terminar no quedaba ningún proceso Godot activo.

## 19. F2.2D3: desprendimiento prescrito de vidrio integrado en la red (2026-09-21)

> **Estado: cerrada.** D3 conecta los estados prescritos de 3A y la geometría
> exacta multicapa de 3B con la red autoritativa. No predice rotura por
> temperatura, no usa probabilidad y no activa esta física en el producto.

### 19.1 Contrato y arquitectura

- `glazing_fallout_enabled` está apagado por defecto y exige
  `pressure_network_solver_enabled`; pedir D3 sin la red falla explícitamente.
- `OpeningModel.glazing_panels` y `glazing_spatial` son datos de ejecución, no
  persistidos. Cada historial espacial empieza en 0 s y selecciona la última
  instantánea anterior o igual al `sim_time_s` autoritativo.
- `GlazingFalloutNetworkAdapter` llama primero a `GlazingIntegrityModel` y
  después a `GlazingOpeningGeometryModel`. No copia la intersección geométrica
  ni contiene una segunda ley de caudal.
- Cada rectángulo libre se entrega como `large_opening`, con su ancho, alto y
  cota absolutos, `open_fraction = 1` y el `Cd = 0,61` ya usado por las
  aberturas grandes. El solver conserva la propiedad de Bernoulli, el plano
  neutro, el contraflujo y el transporte atómico.
- En vidrio multicapa solo ventila la intersección espacial realmente libre a
  través de todas las hojas. `CRACKED` sigue dando área cero.
- Una puerta o ventana operativamente abierta aporta solo su vano completo; el
  vidrio se valida pero no se suma. D3 puede coexistir con D1/D2 en puertas y
  con R3 en marcos exteriores cerrados sin sustituir esas rutas.
- En fachada, el viento se aplica una vez y a la altura real del centro de cada
  rectángulo desprendido.

### 19.2 Validación funcional y mutaciones

El validador cubre estados `CRACKED`, `PARTIAL_FALLOUT` y `OPEN`, geometría
absoluta, multicapa alineada y desalineada, límites del hueco anfitrión,
paneles solapados, exclusividad operativa, coexistencia con fuga de marco,
transporte conservativo de humo, viento, tiempo no finito y cableado del motor.

La campaña mata **24 de 24 mutaciones válidas** y restaura los archivos byte a
byte. Entre ellas: interruptor encendido por defecto, dependencia de la red
silenciada, reloj congelado, resultado inválido aceptado, viento omitido,
doble conteo al abrir el vano, cota o umbral perdidos, ancho/alto incorrectos,
clase de flujo equivocada, solape aceptado e instantánea espacial obsoleta.

### 19.3 Medición diagnóstica de 600 s

Caso de dos recintos sin fuego, con un panel de 0,60 x 1,00 m y un estado
inicial deliberadamente presurizado. Son medidas de integración, **no una
calibración ni una predicción de cuándo se rompe el vidrio**:

| variante | pico de presión (Pa) | caudal de pico (kg/s) | humo receptor (g) | pasos rechazados |
|---|---:|---:|---:|---:|
| D3 apagada | 16 485,57 | 0,000 | 0,000 | 0/7 200 |
| `CRACKED` | 16 485,57 | 0,000 | 0,000 | 0/7 200 |
| `PARTIAL_FALLOUT`, 0,30 m² | 12 376,66 | 1,723 | 45,324 | 0/7 200 |
| `OPEN`, 0,60 m² | 10 446,33 | 2,456 | 46,386 | 0/7 200 |
| vano operativo abierto, 2,40 m² | 8 457,02 | 2,315 | 100,084 | 0/7 200 |

OFF y `CRACKED` son idénticos. Todos los casos conservan la masa total dentro
de 2,9e-14 kg y el humo dentro de 4,8e-16 kg. La distribución final de masa y
humo no tiene por qué ser monótona con el área: una abertura grande admite
contraflujo por altura; el pico de caudal tampoco es una medida de flujo neto.

### 19.4 Límites y siguiente fase

- La historia de integridad y las regiones desprendidas se prescriben; no hay
  acoplamiento temperatura-tiempo-rotura, impacto, agua ni azar.
- Tipo de vidrio, espesor, marco y protección de borde conservan procedencia,
  pero todavía no deciden automáticamente el fallo.
- No hay serialización, controles de editor, activación en escenarios normales
  ni efectos visuales.
- El tamaño y posición del panel se validan dentro del hueco anfitrión, pero la
  campaña no calibra un producto de carpintería real.
- El siguiente trabajo es **D4**, con calibración, contrato persistente,
  editor, activación controlada y criterios publicables.

### 19.5 Cierre de verificación

- Campaña dedicada: **24/24 mutaciones válidas muertas**, con restauración
  byte a byte.
- Suite de referencia: **346/346 required PASS**, con los mismos **78 gaps**
  documentados; en `reference_checks.json` solo cambia `generated_at`.
- Guardarraíles científicos: **ALL PASS**.
- `check_product.py`: **152/152**.
- Suite Python global autoritativa (`tests/`): **2.867 passed**, **4 skipped**
  y **42 subtests passed**.
- Las ejecuciones finales se hicieron bajo el monitor de procesos: cero cuadros
  de error y cero procesos Godot residuales.

## 20. F2.2D4A: contrato persistente y gate de calibración (2026-09-22)

> **Estado: cerrada la PERSISTENCIA, no la calibración.** D4A guarda y carga la
> física prescrita que D1, D2 y D3 ya sabían ejecutar, la deja apagada por
> defecto y congela qué parámetros tienen respaldo experimental y cuáles no.
> **D4A no calibra nada**: ni un solo valor ha cambiado de estado de
> «provisional» a «medido», y ninguno se ha retocado.

### 20.1 Gate de evidencia y calibración

Esta es la tabla que congela el estado de la evidencia. Es el criterio de
entrada de D4B: nada de lo marcado **provisional** puede publicarse como
comportamiento de producto sin una calibración propia.

| parámetro | propietario en código | unidad | valor actual | fuente experimental | rango de validez | estado | decisión D4A |
|---|---|---|---|---|---|---|---|
| ELA clase `entry_tight` | `ClosedDoorLeakageModel.PLANNED_CLASS_ELA_M2` | m² | 0,0012 | NIST TN 2329 p. 28 (*best estimate* ASHRAE 2001, puerta sencilla con burlete) | puerta exterior completa, a 4 Pa | **derivado** (estimación normativa, no ensayo propio) | se persiste sin tocar |
| ELA clase `interior_tight` | `ClosedDoorLeakageModel.PLANNED_CLASS_ELA_M2` | m² | 0,0021 | NIST TN 2329 p. 28, aplicado a puerta garaje-vivienda y de sótano | **no hay** medición de puerta interior residencial | **provisional** (extrapolación) | se persiste sin tocar; **queda expresamente abierto** |
| ELA clase `none` | `ClosedDoorLeakageModel.PLANNED_CLASS_ELA_M2` | m² | 0,0 | — | elemento deliberadamente estanco | **medido por definición** | default; ningún escenario distribuido declara otra cosa |
| `leakage_area_override_m2` | `OpeningModel` | m² | −1 = sin override | lo que aporte quien lo declare | el del ensayo que lo respalde | **desconocido** hasta declararlo | se persiste; nunca es un default |
| reparto inferior/laterales/dintel | `ClosedDoorLeakageModel.PROVISIONAL_SPLIT` | — | 0,40 / 0,47 / 0,13 | proporción **geométrica** de una puerta de paso | ninguno: no está medido | **provisional** | sin cambios; D4A no lo persiste por abertura |
| bandas laterales | `ClosedDoorLeakageNetworkAdapter.SIDE_BAND_COUNT` | — | 8 | Gross y Haberman 1989 p. 177 obs. 4 (segmentar en altura) | cualitativo | **derivado** (discretización, no dato) | sin cambios |
| exponente `n` de la ley de potencia | `ClosedDoorLeakageModel.PROVISIONAL_FLOW_EXPONENT_CANDIDATE` | — | 0,65 | NIST TN 1887r1 p. 266 (0,6-0,7 razonable **sin** ensayo); NBSIR 81-2214 tabla 1 usa 0,5 | depende del régimen | **provisional** | sin cambios; sigue sin calibrar por clase de puerta |
| presión de referencia del ELA | `ClosedDoorLeakageModel.NIST_ELA_REFERENCE_PRESSURE_PA` | Pa | 4,0 | NIST TN 1887r1 ec. 28-29; TN 2329 p. 26 | convención cerrada | **medido** (convención normativa; se rechaza cualquier otra) | sin cambios |
| convención `Cd` de la rendija | misma fórmula | — | 1,0, dentro del ELA | NIST TN 1887r1 ec. 28-29 | convención cerrada | **medido** | sin cambios; la convención 10 Pa / 0,6 sigue sin implementarse |
| regularización en Δp ≈ 0 | `Phase3CoupledPressureSolver.DEFAULT_DP_REGULARIZATION_PA` | Pa | 0,01 | ninguna: es acondicionamiento numérico | — | **derivado** (numérico, no físico) | sin cambios |
| dominio experimental de presión | `ClosedDoorLeakageNetworkAdapter.PRESSURE_DOMAIN_MAX_PA` | Pa | 50 | NBSIR 81-2214 pp. 7 y 10 | Δp a través de una puerta interior | **medido** | sin cambios; **se marca y no se recorta**, y hoy se rebasa por órdenes de magnitud (§17.3, §18.4) |
| área adicional por deformación | `OpeningModel.deformation_tracks` (prescrito) | m² | lo que declare el escenario | Prieler 2023 pp. 16-19 da **topología** (dintel y lado de cerradura); Prieler 2020 da 0,83-3,7 mm en **puerta de acero en horno** | ninguno para puerta residencial | **provisional** / **desconocido** | **se persiste**; sigue sin ley temperatura-deformación |
| curva heredada 150-350 °C / 4 % | `GasExchangeSystem._step_door_deform` | — | 4 % a 350 °C | **ninguna** localizada | — | **desconocido** (heurística heredada) | no se toca y sigue **fuera** de la red |
| fuga del marco exterior | `SimulationEngine.window_leakage_area_m2` | m² | 0,005, con `Cd` 0,61 aparte | purga histórica; CFAST usa 0,007344 m² de pared + 0,001040 m² de suelo con `Cd` 0,7 como orden de magnitud | ninguno propio | **provisional** | sin cambios; sigue siendo **global**, no por abertura. Hacerlo por abertura es D4B |
| `Cd` de abertura grande | `Phase3CoupledPressureSolver` y `GlazingFalloutNetworkAdapter.DISCHARGE_COEFFICIENT` | — | 0,61 | valor clásico de orificio, heredado de la purga | orificio | **derivado** | sin cambios |
| geometría, capas y estado de los paños | `OpeningModel.glazing_panels` / `glazing_spatial` (prescrito) | m, — | lo que declare el escenario | Skelly 1990, Peng 2024, Wang 2007, FSRI: describen **cuándo y cómo** rompe, no un valor por defecto | ninguno automático | **provisional** / **desconocido** | **se persiste**; sigue sin ley térmica ni probabilista |
| `Cd` y área del hueco vertical | `PressureNetworkTransportSystem` | —, m² | 0,61 y el área declarada | ninguna | — | **provisional**, **sin calibrar** | sin cambios; queda para D4B |

**Nada de esta tabla se ha recalibrado en D4A.** En particular no se ha tocado
ningún coeficiente para bajar las presiones observadas, y los resultados fuera
del dominio experimental siguen publicándose con su bandera `domain_exceeded`.

### 20.2 El esquema persistente

Vive en `sim/building/PrescribedOpeningPhysicsSchema.gd`, único propietario, y
guarda dentro de cada entrada de `openings_data`:

| clave | qué es | desde |
|---|---|---|
| `leakage_class` | clase de fuga fría (D1) | 2026-09-18 |
| `leakage_area_override_m2` | ELA explícito (D1), opcional | 2026-09-18 |
| `prescribed_physics_schema` | versión del sub-esquema, hoy **1** | **D4A** |
| `deformation_tracks` | historias prescritas de ELA adicional (D2) | **D4A** |
| `glazing_panels` | carpintería del paño e historia de estados por hoja (D3) | **D4A** |
| `glazing_spatial` | instantáneas `{time_s, leaves[].regions[]}` (D3) | **D4A** |

**Defaults y migración.** Ausencia = lista vacía = física desactivada. Un
escenario anterior a D4A no gana ni una clave al volver a guardarlo, y una lista
vacía se borra por la misma razón. La marca de versión se escribe **solo** si
sobrevive alguna lista no vacía, y se borra si no sobrevive ninguna. Una versión
declarada se conserva tal cual; una versión desconocida, unos datos sin versión
y una versión sin datos se **rechazan**, no se degradan en silencio. Subir
`SCHEMA_VERSION` es un cambio de contrato.

**Carpintería frente a estado operativo.** `open_fraction`, `glass_broken` y
`thermal_gap_fraction` son estado operativo. Todo lo anterior es carpintería:
abrir o cerrar la puerta no borra nada, y una puerta guardada abierta conserva
sus paños y sus pistas. Que la física exija puerta cerrada lo decide el paso de
simulación, no el fichero.

**Claves desconocidas.** Se conservan tal cual, en la abertura, la pista, el
paño, la hoja y la región: son procedencia. Lo que se rechaza son los **valores**
fuera de un enumerado conocido (`leakage_class`, `glass_type`, `state`,
`location`) y las claves conocidas con el tipo equivocado.

**Quién valida qué.** El esquema no reimplementa nada: delega en
`ClosedDoorDeformationModel.validate_tracks` para D2 y en
`GlazingFalloutNetworkAdapter.build_opening_elements` —y por tanto en
`GlazingIntegrityModel` y `GlazingOpeningGeometryModel`— para D3, evaluado en
**cada instante declarado** de la historia. Así, un evento de integridad sin su
instantánea espacial se rechaza al cargar y no a mitad de una simulación. El
resultado se descarta entero: no se emite ni se consume ningún elemento.

**Dos propietarios, una sola regla.** `ScenarioSerializer.normalize_opening`
escribe, y es el dueño de la marca de versión; `BuildingModel._validate_openings`
lee y **falla cerrado**. La ruta real de `tools/run_scenario_headless.gd` mete el
JSON directamente en `BuildingModel` sin pasar por el normalizador, así que ahí
el rechazo es explícito y determinista.

### 20.3 Dos defectos del formato, encontrados y cerrados

Los dos son de `JSON` en Godot 4.7.1 y los dos rompían la persistencia de D3.

1. **`JSON.parse_string` devuelve todo número como `float`.** Un `2` escrito en
   el fichero vuelve como `2.0`. `GlazingIntegrityModel` exige `TYPE_INT` en
   `leaf_count` y en el `index` de cada hoja, y `GlazingOpeningGeometryModel`
   rechaza un índice real: **sin corregirlo, una declaración de D3 se guardaba
   bien y se rechazaba al volver a leerla.** El esquema descodifica el tipo
   entero de la lista cerrada de campos enteros, y **solo** cuando el valor es
   exactamente entero: un 2,5 se deja intacto para que lo rechace el modelo
   puro. Esto no repara un escenario malformado, descodifica el formato.
2. **`JSON.stringify` escribe 15 cifras significativas y hunde a cero lo muy
   pequeño.** Medido: 1/3, e, 0,30000000000000004 y 1e-300 no sobreviven al
   viaje. Como una historia prescrita no se puede redondear en silencio, el
   contrato **rechaza** cualquier número que el fichero no devuelva exacto, con
   su ruta y su valor, en vez de guardarlo mutilado.

Y un tercero, ajeno a D4A pero destapado por su prueba de estabilidad:
`ignition_room_id` era el único entero que el normalizador escribía sin
restituir su tipo, así que **guardar, cargar y volver a guardar cualquier
escenario, incluso uno anterior a D4A, no era byte a byte estable**. Se corrige
con una coerción de tipo que solo actúa si la clave ya existe: ningún escenario
gana una clave y ningún valor cambia.

Con los tres cerrados, ida y vuelta es exacta y el fichero es estable byte a
byte **desde la primera escritura**.

### 20.4 Verificación

- `tools/validate_prescribed_physics_persistence.gd`, registrado en
  `check_product.py`: **229 comprobaciones** en once grupos, entre ellos la
  identidad del escenario antiguo, la ida y vuelta exacta, la estabilidad byte a
  byte, la carpintería frente a abrir y cerrar, que ningún interruptor se toca,
  el orden y los instantes de las historias, la identidad exacta de paño y hoja
  —incluidos mayúsculas y espacios exteriores—, **veinticinco rechazos
  explícitos**, las claves desconocidas conservadas, la identidad del motor con
  la física apagada y la ausencia de rutas nuevas de caudal.
- `tests/test_prescribed_physics_persistence.py`: **12 pruebas**, con las listas
  de propietarios y consumidores **cerradas** y el barrido de los catorce
  escenarios distribuidos y las tres fixtures.
- Campaña de mutaciones: **20 de 20 mutaciones válidas muertas**, con
  restauración byte a byte comprobada por SHA-256 tras cada una. Cubre default
  activado, campo omitido al guardar, campo ignorado al cargar, tiempo
  reordenado, cota de paño alterada, panel equivocado, solape aceptado, dato no
  finito aceptado, clase de fuga desconocida aceptada, versión desconocida
  aceptada, estado operativo confundido con carpintería, migración que añade la
  marca de versión, identidad de paño reescrita, entero fraccionario truncado,
  carga sin validar, aliasing del diccionario del escenario, descodificación de
  enteros eliminada, marca de versión sin tipo y la regresión de
  `ignition_room_id`.
  Cinco supervivientes de la primera vuelta y cuatro mutaciones que reventaban
  el validador con un error de ejecución obligaron a reforzar las pruebas: se
  añadió un segundo paño de identidad exacta, la comprobación de aliasing contra
  el diccionario que de verdad entra en el motor, los casos de entero
  fraccionario y de no finito dentro de metadatos inertes, y accesos defensivos
  para que una carga fallida marque el fallo en vez de reventar.
- Suite de referencia completa, obligatoria porque D4A toca `sim/building`:
  **346/346 required PASS** con los mismos **78 gaps** documentados; en
  `reference_checks.json` solo cambió `generated_at`. Todos los guardarraíles
  científicos en verde, R2-1 incluido.

### 20.5 Lo que D4A deja fuera, y es exactamente D4B

- **Calibración.** Todo lo marcado provisional en §20.1 sigue provisional. D4A
  **no** puede declararse calibrada: solo ha cerrado la persistencia.
- **Editor.** No hay ni un control nuevo: ni clase de fuga, ni pistas, ni paños,
  ni regiones. La herramienta del portal tampoco escribe nada de esto.
- **Perfiles calibrados** por clase de puerta, material y ajuste, y por tipo de
  vidrio, espesor, número de hojas y protección de borde.
- **Activación controlada** en escenarios distribuidos: los cinco interruptores
  siguen apagados y ningún escenario los enciende ni declara datos.
- **Fuga de marco por abertura**: hoy `window_leakage_area_m2` es global.
- **Criterios publicables**: el pico de presión del recinto sellado sigue en el
  orden de decenas de kPa y las Δp de la rendija siguen fuera del dominio
  experimental. Eso no se arregla persistiendo datos.
- Siguen sin existir el modelo térmico (tipo BREAK1) y el probabilista de rotura
  de vidrio, y `GlassFailureSystem` sigue sin conectarse.

## 21. F2.2D4B1: catálogo trazable de perfiles y gate científico (2026-09-22)

> **Estado: cerrado el catálogo, no la calibración.** D4B1 releyó página a página
> las seis fuentes de la colección focal, convirtió la tabla de 18 parámetros de
> §20.1 en una matriz trazable y publicó un catálogo versionado de 15 perfiles.
> **Ningún perfil queda activable en producto**, y cinco quedan **bloqueados**
> porque la evidencia no existe o se contradice. No se recalibró ningún valor.

### 21.1 Lo que la relectura cambió respecto de §20.1

Tres correcciones de fondo, todas hacia abajo:

1. **Los 12 y 21 cm² no son «derivados normativos», son `research_only`.**
   NIST TN 2329 (p. 28) dice que son los *best estimates* de la **tabla 1 del
   ASHRAE Fundamentals 2001** para puerta simple **con** y **sin** burlete —no
   «puerta de garaje/sótano», que es solo dónde NIST los aplicó— y añade dos
   cosas que §20.1 no recogía: **esa tabla fue retirada de las ediciones
   posteriores del manual**, y la colección de viviendas de 2025 **deja de
   usarlos**. Un valor cuya fuente primaria ya no se publica y cuyo citador lo
   ha deprecado no puede llamarse derivado.
2. **Sí existen puertas interiores realmente medidas, y 21 cm² es el extremo
   estanco.** Gross y Haberman (tabla 1, p. 176) publican el caudal **medido**
   de 11 conjuntos de puerta a 25 Pa. Transformados a ELA a 4 Pa con el
   exponente de puerta de NBSIR (n = 0,5) dan **de 20,2 a 234,3 cm²**. Los
   21 cm² de ASHRAE caen en el **0,4 %** de ese rango, es decir, pegados al
   suelo: equivalen a un espécimen de laboratorio con 0,6 mm de holgura en
   todos los bordes, no a una puerta instalada. Los 12 cm² son **0,59 veces**
   la puerta más estanca jamás medida en esa muestra.
3. **El exponente no es una constante, y 0,65 no es el valor de una puerta.**
   La tabla 2 de Gross y Haberman (p. 177) permite leer el exponente implícito
   entre 10 y 100 Pa: **0,982** para una rendija de 0,5 mm, **0,773** para
   1 mm, **0,541** para 5 mm y **0,496** para 10 mm. NBSIR (tabla 1, p. 17)
   publica **0,50 para holguras de puerta**. El 0,6-0,7 del que sale el 0,65
   del motor es de CONTAM y se refiere a **aberturas de infiltración**, no a
   rendijas de puerta. El 0,65 queda dentro de la envolvente observada, pero
   corresponde a una rendija de unos 5 mm y contradice el valor específico de
   puerta. Sigue **provisional**, y **no se ha cambiado**: cambiarlo sería
   física, y D4B1 no toca física.

Y una cuarta, sobre el marco exterior: los 0,005 m² del motor son **1,29 veces**
la ventana doméstica más permeable de NBSIR (tabla 3, p. 19), una vez
convertidos sus caudales a área de orificio con el mismo `Cd` = 0,61 que usa el
motor. No es un dato experimental: es una heurística propia, y un resultado
interno de SimuFire no puede presentarse como evidencia.

### 21.2 Matriz de calibración

Estado: **M** medido · **D** derivado · **P** provisional · **X** desconocido.
Uso: **prod** apto para producto · **inv** solo investigación · **blq** bloqueado.

| parámetro | unidad | propietario | valor | aplica a | fuente y localizador | ensayo | rango | muestra | est. | uso | incertidumbre | transformación |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ELA `entry_tight` | m² a 4 Pa, Cd 1 | `ClosedDoorLeakageModel.PLANNED_CLASS_ELA_M2` | 0,0012 | puerta de entrada con burlete | TN 2329 p. 28 → ASHRAE 2001 tabla 1, *best estimated* | ninguno declarado | — | no declarada | **P** | inv | desconocida | ninguna |
| ELA `interior_tight` | m² a 4 Pa, Cd 1 | ídem | 0,0021 | puerta simple **sin** burlete | ídem, fila «not weather-stripped» | ninguno declarado | — | no declarada | **P** | inv | desconocida | ninguna |
| ELA de puertas medidas | m² a 4 Pa, Cd 1 | catálogo (rango) | 0,002017–0,0234 | puertas de escalera, oficina y cortafuegos | Gross-Haberman tabla 1 p. 176; NBSIR tabla 1 p. 17 y tabla 2 p. 18 | presurización, punto único | 25 Pa | 11 conjuntos | **D** | inv | «rango amplio entre puertas incluso de construcción similar» (NBSIR p. 12); modelo-medida ±20 % | `ELA = Q(25)·(4/25)^0,5 / √(8/ρ)`, ρ = 1,204 |
| ELA de puerta de paso residencial | — | — | **no existe** | la puerta del juego | NBSIR p. 8 y p. 12 | — | — | — | **X** | blq | total | — |
| ELA de puerta desajustada | — | — | **no existe** | puerta vieja | NBSIR tabla 2, filas «>15», «>40» | — | 25 Pa | censurada | **X** | blq | no acotada | — |
| convención `Cd` = 1 a 4 Pa | — | `NIST_ELA_REFERENCE_PRESSURE_PA` | 4,0 / 1,0 | toda ELA | TN 1887r1 p. 266, ec. 28-29 | definición | — | — | **M** | prod | ninguna: es la definición | ninguna |
| exponente de flujo | — | `PROVISIONAL_FLOW_EXPONENT_CANDIDATE` | 0,65 | rendija de puerta | TN 1887r1 p. 266 (0,6-0,7, **infiltración**); NBSIR tabla 1 (**0,50**, puertas); Gross-Haberman tabla 2 (0,50-0,98 según espesor) | varios | 10–100 Pa | — | **P** | inv | **fuentes en conflicto**; varía con el espesor de rendija | ninguna |
| reparto inferior/laterales/dintel | — | `PROVISIONAL_SPLIT` | 0,40/0,47/0,13 | rendija de puerta | **ninguna**: proporción geométrica supuesta | — | — | — | **X** | blq | desconocida | — |
| número de bandas laterales | — | `SIDE_BAND_COUNT` | 8 | rendija de puerta | Gross-Haberman p. 177, obs. 4 (segmentar; **no dice cuántas**) | — | — | — | **D** | inv | discretización numérica | ninguna |
| regularización en Δp ≈ 0 | Pa | `DEFAULT_DP_REGULARIZATION_PA` | 0,01 | solver | ninguna: acondicionamiento numérico | — | — | — | **D** | inv | no física | ninguna |
| fuga de marco exterior (motor) | m² geométricos | `window_leakage_area_m2` | 0,005 | ventana exterior cerrada | **purga histórica del propio motor** | ninguno | — | — | **P** | inv | desconocida | ninguna |
| fuga de marco medida | m² geométricos, Cd 0,61 | catálogo (rango) | 0,000342–0,00389 | ventana doméstica 1,2 × 1,0 m | NBSIR tabla 3 p. 19 | permeabilidad | 100 Pa | rangos publicados | **D** | inv | la fuente publica rangos | `A = Q/(Cd·√(2Δp/ρ))`, longitud de rendija 4,4 m |
| `Cd` de abertura grande | — | solver y adaptador D3 | 0,61 | vano y vidrio desprendido | valor clásico de orificio, heredado | — | — | — | **P** | inv | no medida aquí | ninguna |
| deformación adicional por posición | m² de ELA | `deformation_tracks` | lo que prescriba el escenario | puerta cortafuegos de **acero** en horno | Prieler 2023 pp. 16-19; Prieler 2020 | horno normalizado | 16 Pa arriba / 0,2 abajo | 1 conjunto | **P** | inv | no transferible a madera residencial | ninguna (topología, no magnitud) |
| ley térmica de deformación residencial | — | — | **no existe** | puerta residencial | Gross-Haberman p. 176 §3 | — | <300 °C | — | **X** | blq | total | — |
| geometría de paño, capas, espesor | m, hojas | `glazing_panels` | lo que declare el escenario | IGU de recocido | Peng 2024 | panel radiante | ~20 kW/m² | 75 ensayos | **M** | inv | dominio de 200–500 mm | ninguna |
| tipo de vidrio: laminado | — | ídem | sin desprendimiento | laminado con butiral | Peng 2024 §3.1 | panel radiante | ~20 kW/m² | todas las muestras | **M** | inv | exposiciones largas no acotadas | ninguna |
| tipo de vidrio: templado | — | — | **contradictorio** | templado | Peng 2024 (sin grietas) vs Wang 2007 (caída casi total) | panel radiante vs ISO 9705 | — | — | **X** | blq | fuentes incompatibles | — |
| soporte y protección de borde | m, °C | `edge_protection_depth_m` | 0,090 °C crítico | recocido en compartimento | Skelly 1990 | compartimento de dos capas | — | 2 grupos | **D** | inv | mecanismo del caso no protegido «desconocido» | ninguna |
| `CRACKED` / `PARTIAL_FALLOUT` / `OPEN` | fracción | `GlazingIntegrityModel` | 0 / (0,1) / 1 | estados del paño | Peng 2024 tabla 2 | panel radiante | ~20 kW/m² | 16 muestras | **D** | inv | **el 100 % nunca se observó**: el máximo fue 90 % | ninguna |
| dominio de presión | Pa | `PRESSURE_DOMAIN_MAX_PA` | 50 | rendija de puerta | **NBSIR p. 10** | — | — | — | **M** | prod | p. 7 da 100 Pa para presiones interiores en general | ninguna |
| hueco vertical (`Cd`, área) | —, m² | `PressureNetworkTransportSystem` | 0,61 y lo declarado | hueco de forjado | **ninguna**; vía identificada: CONTAM p. 266 (Achakji-Tamura) | — | — | — | **X** | blq | total | — |

### 21.3 Perfiles y decisión GO/NO-GO

`sim/building/OpeningPhysicsProfileCatalog.gd` publica **15 perfiles**: 2
`validated`, 4 `derived`, 4 `research_only` y **5 `blocked`**.
`product_activation` es `false` en **todos**, incluidos los validados: su
dominio experimental no cubre una vivienda real.

| perfil | categoría | estado | decisión |
|---|---|---|---|
| `door.entry.weatherstripped.ashrae2001@1` | puerta | `research_only` | **NO-GO**: tabla ASHRAE retirada y NIST la deprecia |
| `door.interior.not_weatherstripped.ashrae2001@1` | puerta | `research_only` | **NO-GO**: ídem, y cae en el 0,4 % inferior del rango medido |
| `door.interior.installed_measured_range@1` | puerta | `derived` | **NO-GO como valor**: es un rango, y su muestra no tiene ni una puerta residencial. Sirve de envolvente |
| `door.interior.residential_passage@1` | puerta | `blocked` | **NO-GO**: no existe la medición. Se nombra el ensayo que lo desbloquearía |
| `door.interior.loose_fitting@1` | puerta | `blocked` | **NO-GO**: solo cotas inferiores censuradas |
| `frame.exterior.window.legacy_engine_value@1` | marco | `research_only` | **NO-GO**: es una heurística del propio motor, no un dato |
| `frame.exterior.window.measured_range@1` | marco | `derived` | **NO-GO como valor**: rango ligado a un tamaño de ventana |
| `deformation.steel_fire_door.furnace_topology@1` | deformación | `research_only` | **NO-GO**: topología sí, magnitudes de puerta de acero en horno |
| `deformation.residential_door.thermal_law@1` | deformación | `blocked` | **NO-GO**: no hay ley temperatura-deformación defendible |
| `glazing.annealed.igu.radiant_panel@1` | vidrio | `validated` | **GO científico, NO-GO de producto**: dominio de 200–500 mm |
| `glazing.laminated.no_fallout@1` | vidrio | `validated` | ídem: resultado negativo sólido dentro de su dominio |
| `glazing.toughened.contradictory@1` | vidrio | `blocked` | **NO-GO**: Peng y Wang se contradicen, y el contrato de estados no representa la caída casi inmediata |
| `glazing.multilayer.free_path_rule@1` | vidrio | `derived` | **GO como regla**, no como número |
| `glazing.edge_protection.collapse_rule@1` | vidrio | `derived` | **GO como regla**: un borde no protegido no colapsó en ningún ensayo |
| `shaft.vertical_opening.uncalibrated@1` | hueco vertical | `blocked` | **NO-GO**: sin fuente; vía de desbloqueo identificada |

### 21.4 Esquema de versiones y reproducibilidad

**La decisión, escrita antes de programarla:** el escenario guarda **las dos
cosas**, la referencia versionada `(profile_id, profile_version)` **y** una
**copia congelada** de los parámetros efectivos, y **la copia congelada es la
autoritativa para la física**. Solo el identificador dejaría que reeditar el
catálogo cambiara un escenario antiguo; solo la copia congelada perdería la
trazabilidad. Con las dos, cargar resuelve la referencia y **compara**: si el
par no existe, o existe y sus parámetros no coinciden con la copia, la carga
**falla de forma explícita**.

`(profile_id, version)` es **inmutable**: corregir un valor obliga a publicar
una versión nueva y la anterior se conserva. La resolución es por par exacto;
no hay «última versión».

**Migración 1 → 2, explícita y probada.** Un escenario de D4A sigue siendo
válido y, sin perfiles, se vuelve a guardar como **esquema 1**: no gana ni una
clave y sigue siendo byte a byte estable. La marca sube a 2 **solo** cuando hay
un perfil declarado, y nunca baja. Declarar un perfil bajo el esquema 1 se
rechaza, igual que una versión por encima de `SCHEMA_VERSION`.

Un perfil `blocked`, uno sin parámetros, uno de otra categoría, uno manipulado y
un número que el fichero no devuelve exacto **no entran**.

### 21.5 Fuga de marco por abertura

Es lo único que D4B1 añade al motor, y reutiliza la ruta R3 tal cual:
`PressureNetworkTransportSystem._envelope_leak_area_m2()` devuelve el área
**propia** de la abertura si está declarada y, si no, la **global** histórica.
**Nunca las suma.** `ExteriorEnvelopeLeakageAdapter` no cambia ni una línea, el
`Cd` = 0,61 sigue separado del área y el interruptor
`exterior_envelope_leakage_enabled` sigue apagado por defecto. Una abertura sin
área propia se comporta exactamente como antes.

### 21.6 Validación experimental dentro de dominio

El validador hace ensayos **puros**, con Δp impuestas, no simulaciones de
incendio:

- cinco puntos dentro del dominio (1, 4, 10, 25 y 50 Pa), con caudal monótono y
  sin bandera de dominio;
- sentido positivo y negativo: mismo módulo, signo opuesto;
- continuidad alrededor de cero, con caudal nulo exacto en Δp = 0 y simetría;
- escala exacta con el área al doblarla;
- conservación entre segmentos;
- independencia del orden de las aberturas y repetibilidad byte a byte;
- a 5 kPa la bandera `domain_exceeded` se levanta y el caudal **no se recorta**.

Y reproduce, con aritmética explícita, los dos rangos derivados a partir de los
números publicados. **La tolerancia no está inventada**: es media unidad de la
última cifra significativa con la que la fuente imprime el dato (tres cifras).

Los casos de incendio completo siguen siendo diagnóstico de integración, no
calibración.

### 21.7 Verificación

- Validador `tools/validate_opening_physics_profiles.gd`: **257 comprobaciones**
  en once grupos, registrado en `check_product.py`.
- `tests/test_opening_physics_profiles.py`: **21 pruebas**, con la lista de
  consumidores del catálogo **cerrada** a dos ficheros.
- Campaña de mutaciones: **20 de 20 muertas**, con restauración SHA-256.
  Dos supervivientes y un fallo nativo de la primera vuelta destaparon tres
  huecos reales: un perfil bloqueado podía reetiquetarse como derivado sin traer
  datos, la regla de categoría quedaba tapada por la de parámetros, y aplicar un
  perfil con la copia congelada vacía reventaba en vez de fallar cerrado.
- D1, D2, D3, D4A y R3: sus cinco validadores siguen en verde sin tocarlos.

### 21.8 Lo que queda para D4B2

- Mandos de editor para elegir perfil, con los `research_only` y `blocked`
  visiblemente separados de los publicables.
- Política de producto: qué perfil, si alguno, puede encenderse, y con qué
  criterio de aceptación.
- Persistencia de perfiles para **deformación** y **vidrio**: hoy el catálogo
  los publica como referencia, pero ninguna abertura los cuelga.
- Activación controlada en escenarios distribuidos, que sigue sin hacerse.
- Desbloquear lo bloqueado exige **ensayos nuevos**, no más lectura: puerta de
  paso residencial (ASTM E283 / ISO 5925-1, por sentido, 5–100 Pa), ley térmica
  de deformación, y una decisión de contrato sobre `CRACKED → OPEN` antes de
  tocar el templado.
- Siguen sin existir BREAK1 y el modelo probabilista, y `GlassFailureSystem`
  sigue sin conectarse.

## 22. F2.2D4B2A: configuración de perfiles desde el editor (2026-09-22)

> **Estado: cerrada la CONFIGURACIÓN, no la activación.** El editor ya enseña el
> catálogo, deja elegir un perfil compatible, explica su evidencia y su dominio,
> y guarda la referencia versionada con su copia congelada. **Nada de esto
> enciende física**: los cinco interruptores siguen apagados, ningún escenario
> distribuido declara nada y con los interruptores apagados una abertura
> configurada no aporta ni un elemento a la red.

### 22.1 Qué se añadió al editor

Una ficha nueva, **FÍSICA EXPERIMENTAL**, dentro de las propiedades de la
abertura. Toda ella vive en `scenes/ScenarioEditorScene.tscn`: el guardarraíl
U7c exige que no haya un solo `Control` inyectado por código, y se sigue
cumpliendo (127 controles, todos con explicación, unidad, foco de teclado y
tildes).

| mando | qué hace |
|---|---|
| `OpeningPhysicsExperimentalCheck` | confirma el modo experimental; hace falta para elegir un perfil `research_only` |
| `OpeningPhysicsSlotOption` | familia a configurar: fuga fría, fuga de marco, deformación o vidrio. Solo aparecen las que encajan con la abertura |
| `OpeningPhysicsProfileOption` | perfiles de esa familia. Los no seleccionables salen **deshabilitados con su motivo en el tooltip** |
| seis etiquetas | evidencia, aptitud de producto, dominio, fuente, advertencias y parámetros efectivos congelados |
| `OpeningPhysicsStatusLabel` | «Configuración experimental guardada; física no activada en simulación normal.» |
| `OpeningPhysicsList` | la prescripción ya guardada, en su orden: pistas con sus instantes, paños con sus hojas y estados, e instantáneas con sus regiones |
| trece mandos de entrada | identificador, hoja, posición, estado, tipo de vidrio, instante (s), ELA adicional (m²), desprendido (%), X/Z/ancho/alto (m) y número de hojas |
| tres botones | aplicar perfil, añadir a la prescripción, quitar lo seleccionado |

Se usó un `ItemList` y no un `Tree` por un motivo concreto: un `Tree` crea en
tiempo de ejecución un `@Timer@` propio, y el guardarraíl de escena completa
—que recorre **todos** los nodos, no solo los `Control`, pese a lo que dice su
propia documentación— lo cuenta como nodo inyectado por código. Queda anotado
como defecto menor del guardarraíl; no se tocó.

### 22.2 Política de selección

La decide `sim/building/OpeningProfileSelection.gd`, que vive junto al catálogo
para que la interfaz no acabe con su propia copia de los estados de evidencia.

| evidencia | se ve | se elige | condición |
|---|---|---|---|
| `validated` | sí | sí | con el aviso de que su dominio de ensayo **no cubre una vivienda** |
| `derived` | sí | sí | identificado como derivado de un cálculo reproducible |
| `research_only` | sí | sí | **solo con el modo experimental confirmado** |
| `blocked` | sí | **no** | se enseña para explicar qué evidencia falta |
| incompatible con la abertura | sí | **no** | con el motivo concreto |
| sin perfil | sí | sí | **es la opción por defecto** |

Cada fila lleva su estado **en texto** (`MEDIDO`, `DERIVADO`, `EXPERIMENTAL`,
`BLOQUEADO`), su aptitud de producto en texto y, si no se puede elegir, el
motivo en texto. El color, si se usa, es refuerzo. Ninguna etiqueta dice
«seguro», «realista», «estándar residencial» ni «calibrado», y una prueba lee
todos los textos de la escena y del vocabulario para comprobarlo.

Los quince perfiles siguen con `product_activation = false`, y el editor lo
enseña en cada fila.

### 22.3 Compatibilidad, y qué pasa al cambiar el tipo

La regla la pone el **catálogo**, leída de los adaptadores del motor y escrita
una sola vez: `door_leakage` y `deformation` piden puerta interior;
`frame_leakage`, abertura exterior que no sea hueco; `glazing`, puerta o
ventana; un hueco vertical no admite ninguna.

Cambiar el tipo de una abertura con un perfil que dejaría de encajar **no borra
nada en silencio**: `change_type` devuelve `needs_confirmation` y nombra las
ranuras en conflicto. Solo con la confirmación explícita se quitan esos
perfiles, y la prescripción se conserva siempre.

### 22.4 Esquema 3 y migraciones

El esquema sube a **3** con dos ranuras nuevas, `deformation_profile` y
`glazing_profile`. La diferencia con las dos de D4B1 importa: aquellas aportaban
**el número** que el motor consume; estas no aportan ninguno, porque D2 y D3 son
prescripción y las magnitudes las escribe quien monta el escenario. Lo que estas
dos aportan es **procedencia**: con qué ensayo y en qué dominio hay que leer esa
prescripción. Por eso su ranura no declara parámetro obligatorio, y aun así la
copia congelada tiene que coincidir entera con el catálogo.

**Migración 1 → 3 y 2 → 3.** La marca sube al mínimo que exige el contenido y
**nunca baja**: sin perfiles se queda en 1, con perfiles de D4B1 en 2 y con
perfiles de deformación o vidrio en 3. Un escenario de esquema 1 o 2 sigue
cargando tal cual y, si no declara nada nuevo, se vuelve a guardar con su marca
de siempre sin ganar ni una clave. **Ninguna migración enciende física**: solo
mueve el número de versión, y una prueba lo comprueba cargando el escenario en
un motor recién creado.

Se rechazan, de forma explícita: perfil desconocido, versión no publicada,
categoría que no encaja con la abertura, perfil bloqueado, perfil sin
parámetros, copia congelada alterada y número que el fichero no devuelve exacto.

### 22.5 Configuración frente a activación

Cinco cosas separadas, y el código lo hace cumplir:

1. **perfil configurado** — `leakage_profile`, `frame_leakage_profile`,
   `deformation_profile`, `glazing_profile`;
2. **datos físicos persistidos** — `deformation_tracks`, `glazing_panels`,
   `glazing_spatial`, más `leakage_class` y los dos overrides;
3. **estado operativo** — `open_fraction`, `glass_broken`,
   `thermal_gap_fraction`, que el editor de física **no toca**;
4. **interruptores** — los cinco de `SimulationEngine`, que siguen naciendo
   apagados y que ningún fichero del editor nombra;
5. **autorización de producto** — `product_activation`, `false` en los quince.

Medido, no solo afirmado: con los cuatro interruptores apagados y dos aberturas
configuradas —puerta con perfil de fuga y ventana con vidrio prescrito, perfil
de marco y perfil de vidrio—, la red no emite **ningún** elemento de rendija,
de vidrio ni de envolvente.

`ScenarioDocument.replace_opening()` es quien escribe, con su paso de deshacer:
el editor no toca `editor_data` a mano en esta ruta.

### 22.6 Edición de la prescripción

El editor edita **lo que D2 y D3 ya sabían ejecutar**, y no inventa ninguna ley.

- **Deformación**: identificador de la pista, posición (`bottom`, `top`,
  `hinge_side`, `latch_side`), cota, instante en segundos y **ELA adicional en
  m²** —área efectiva, no geométrica—. El punto se inserta en su sitio para que
  la historia siga creciendo en el tiempo. Un instante repetido, un tiempo
  desordenado o un área negativa o no finita **los rechaza el modelo puro**, no
  el editor. No se rellena ninguna curva temperatura-deformación: esa ley sigue
  bloqueada.
- **Vidrio**: paño con su posición dentro del hueco, ancho, alto, tipo y número
  de hojas; estado prescrito por hoja con su instante y su fracción; y regiones
  desprendidas por hoja e instante. El listado explica que `CRACKED` **no crea
  área de ventilación**, que `PARTIAL_FALLOUT` ventila solo la geometría libre
  real a través de todas las hojas y que `OPEN` es el paño entero perdido. Un
  paño fuera del hueco, dos paños solapados o un salto de estado prohibido los
  rechaza D3. El editor **no decide cuándo rompe el vidrio**, y el templado
  sigue bloqueado desde D4B1.

### 22.7 Verificación

- Validador `tools/validate_opening_profile_editor.gd`: **859 comprobaciones**
  en quince grupos, registrado en `check_product.py`.
- `tests/test_opening_profile_editor.py`: **22 pruebas**, con las listas de
  consumidores cerradas y el barrido de los escenarios distribuidos.
- Guardarraíles de escena intactos: **UI del editor 100 % en escena** y
  **127 controles** con explicación, unidad, foco y tildes.
- Campaña de mutaciones: **18 de 18 muertas**, con restauración byte a byte.
  Cubre perfil bloqueado habilitado, advertencia eliminada, `product_activation`
  ignorado, perfil que enciende D3 por su cuenta, perfil incompatible aceptado,
  confirmación experimental omitida, referencia versionada perdida, copia
  congelada vaciada, migración que acepta un perfil bajo el esquema viejo,
  instante duplicado fusionado en silencio, área negativa recortada, paño
  metido a la fuerza dentro del hueco, `CRACKED` descrito como abertura, estado
  operativo que borra el perfil, fuga global y específica sumadas, fórmula de
  caudal copiada al controlador del editor, escenario legado que gana la marca
  de versión y perfil experimental presentado como medido.
  En la primera vuelta dos sobrevivieron y tres reventaban el validador con un
  error de ejecución: las cinco eran debilidades reales de los guardarraíles
  -no se comprobaban las advertencias de la fila ni el rechazo de un área
  negativa tecleada en el mando, y cuatro comprobaciones indexaban un resultado
  sin comprobar antes que existiera- y las cinco quedaron corregidas.
- D1, D2, D3, D4A, D4B1 y R3: sus validadores siguen en verde.
- Cierre final tras regenerar la referencia: **346/346 required PASS**, los
  mismos **78 gaps** y solo `generated_at` modificado en
  `reference_checks.json`; guardarraíles científicos **ALL PASS**, incluido
  R2-1. `check_product.py`: **155/155**. Suite Python global autoritativa
  (`tests/`): **2.922 passed**, **4 skipped** y **42 subtests passed**. El
  monitor terminó sin cuadros de error ni procesos Godot residuales.
- Las cinco listas cerradas de consumidores de D1, D2, 3A, 3B y de la red se
  ampliaron con el controlador del editor, su validador y su suite. La regla que
  vigila que los interruptores no aparezcan en CODIGO es
  `test_the_editor_never_writes_a_switch`; la barrida de escenarios de
  `test_pressure_network_integration` pasa a mirar codigo y no documentacion,
  porque el controlador nombra los interruptores en su cabecera justamente para
  dejar escrito que no los toca.

### 22.8 Lo que queda para D4B2B

- **Activación**: decidir si algún perfil puede encenderse en un escenario de
  producto, con qué criterio de aceptación, y el mando que lo haga. Hoy no
  existe ese mando a propósito.
- **Calibración**: sigue sin cambiar nada. Los quince perfiles siguen con
  `product_activation = false` y cinco siguen bloqueados.
- **Autoría de geometría de vidrio** más cómoda que los mandos actuales, si se
  decide que hace falta.
- Siguen sin existir BREAK1 y el modelo probabilista, y `GlassFailureSystem`
  sigue sin conectarse.
