# Diagnóstico y diseño: fugas de puertas interiores cerradas

> **Estado (2026-09-17): fases 1 y 2 cerradas; fase 3A implementada.**
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
>   determinista, `CRACKED` no ventila y todavía no hay conversión espacial a
>   aberturas.
> - **Nada está integrado**: ningún sistema carga estos modelos en el paso de
>   simulación, no hay física nueva activa y ningún escenario la usa. Siguen
>   pendientes la fase 3B (regiones desprendidas e intersección entre hojas),
>   el modelo térmico y el probabilista del vidrio, F2.2 y la integración
>   (§6.6).
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
   (2026-09-17, §12); sin integrar.**
2. **Modelo puro de deformación prescrita**, con huecos independientes en
   suelo, laterales y dintel. **Implementado (2026-09-17, §13); sin
   integrar.** No se inventa aún una curva automática para
   puertas residenciales.
3. **Modelo puro de vidrio**, con estado por hoja
   `INTACT -> CRACKED -> PARTIAL_FALLOUT -> OPEN` y conversión del área
   desprendida en una abertura situada en el paño. `CRACKED` ventila cero.
   **Fase 3A (integridad prescrita) implementada el 2026-09-17 (§14), sin
   integrar.** La conversión a aberturas es de la fase 3B.
4. **No conectar todavía** esos modelos al portal ni activarlos en el editor.
5. **Resolver F2.2** (magnitud física de la sobrepresión de recintos cerrados)
   como cambio separado, también detrás de interruptor. Referencia (CFAST Model
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
  con ΔP impuestas. **Hecha (2026-09-17, §12)**, sin integrar;
- **Etapa 2 (deformación prescrita)**: `sim/core/ClosedDoorDeformationModel.gd`
  y sus tests. **Implementada (2026-09-17, §13)**, sin integrar;
- **Etapa F2.2**: por definir en su propio documento;
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

`sim/core/ClosedDoorLeakageModel.gd` (sin `class_name`). **No está conectado**:
ningún sistema del motor, el editor ni el lanzador de escenarios lo carga, y no
hay interruptor nuevo. No modifica `open_fraction` ni ninguna entrada, y no
transporta todavía humo, O₂, energía ni especies.

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

`sim/core/ClosedDoorDeformationModel.gd` (sin `class_name`). **No está
conectado**: ningún sistema del motor, el editor ni el lanzador de escenarios
lo carga, y no hay interruptor nuevo. No lee temperaturas, no escribe la
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
- Decidir cómo convive con el hueco térmico heredado sin doble conteo
  (riesgo 4 de §9).
- Vidrio (§6.6, paso 3), F2.2 e integración.

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

- **Fase 3B**: regiones desprendidas **explícitas** por hoja (rectángulos o
  máscaras en coordenadas del paño), su **intersección** entre hojas para
  obtener el camino libre real y la conversión de ese camino en aberturas
  rectangulares situadas en su cota, para el solver de abertura grande.
- Modelo térmico de rotura (tipo BREAK1, diferencia centro-borde, efecto del
  espesor, del marco y del borde protegido) y modelo probabilista de caída con
  semilla fija.
- Impacto mecánico, agua, integración en puertas y ventanas reales, editor,
  serialización y efectos visuales.
