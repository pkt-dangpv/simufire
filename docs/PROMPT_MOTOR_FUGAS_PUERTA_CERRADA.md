# Diagnóstico y diseño: fugas de puertas interiores cerradas

> **Estado (2026-09-16): solo diagnóstico y diseño. No hay física nueva en el
> motor.** Medido con `main` en `b0b31bb6` sin tocar `sim/`.
>
> **Decisiones del usuario (2026-09-16):**
> - **Área**: ELA a 4 Pa según NIST TN 2329: **12 cm²** para la entrada de
>   vivienda al portal y **21 cm²** para una puerta interior corriente. Las
>   puertas desajustadas llevan un override explícito. Los candidatos
>   geométricos L1/L2/L3 de la sonda se descartan como valores (§7).
> - **Flujo**: de grieta, por ley de potencia; una clase de fuga por abertura
>   en el motor (§6.2-§6.3).
> - **Orden**: primero el modelo puro con ΔP impuestas; **F2.2 (sobrepresión)
>   se arregla antes de integrar**; después se integra (§6.6). El límite por
>   paso es solo un cinturón numérico, no sustituye a la presión física.

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

`open_fraction` no se toca: sigue siendo el estado operativo y visual.

### 6.2 Dato físico principal: área efectiva de fuga (ELA)

El dato que manda es el **área efectiva de fuga medida a una presión de
referencia**, no la geometría. **El hueco visible y el área efectiva de flujo
son cosas distintas**: la sonda de §3-§4 usaba áreas geométricas de 78-289 cm²,
y el área efectiva de una puerta real es un orden de magnitud menor (§7).

Parámetros del motor:

- `closed_door_effective_leakage_area_m2`: el valor por defecto de la clase
  `interior_standard`;
- `closed_door_leakage_reference_pressure_pa = 4.0`;
- `closed_door_leakage_flow_exponent`: el exponente `n` de la ley de potencia.
  Se propone 0,65, el valor habitual para grietas, **a confirmar con la fuente**
  junto con la convención de coeficiente de descarga del ELA.

**Campo por abertura, en el modelo del motor** (`OpeningModel`), no deducido de
la vista:

- `leakage_class`: `interior_standard` (por defecto en las puertas interiores),
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
   de ΔP y `ṁ = ρ_src·Q`. Por debajo de una ΔP umbral, un tramo lineal evita la
   derivada infinita en ΔP = 0.
3. **Zona de origen y de destino**: el origen es la zona de la sala de origen
   en esa cota; el destino, la capa alta de la receptora si el gas es más
   caliente que su capa baja, y la baja si no.
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
  `tools/run_scenario_headless.gd`, **solo en la etapa de integración (paso 4
  de §6.6)**.
- Los casos oficiales no lo encienden. Apagado, todo idéntico byte a byte.
- Registrar el interruptor en `scripts/simulation/audit_default_off_flags.py`
  (física viva, fuera del alcance P1R4) y subir `EXPECTED_DECLARATION_COUNT`.

### 6.6 Orden decidido (usuario, 2026-09-16)

1. **Modelo puro de fuga** (`ClosedDoorLeakageModel.gd`), probado con
   diferencias de presión **impuestas y razonables** (0-50 Pa, perfiles con y
   sin capa caliente). Sin conectar al paso del motor.
2. **No conectarlo** todavía al portal ni activarlo en el editor.
3. **Resolver F2.2** (magnitud física de la sobrepresión de recintos cerrados)
   como cambio separado, también detrás de interruptor. Referencia (CFAST Model
   Evaluation Guide): en la validación con puerta cerrada se habla de
   sobrepresiones de **varios cientos de Pa**, no de los cientos de kPa medidos
   en §5.7.
4. **Integrar la fuga** con la presión corregida, encenderla en el editor y
   medir de nuevo los casos A, Aw y B.

## 7. Área efectiva: valores provisionales (decisión del usuario, 2026-09-16)

Fuente primaria **aportada por el usuario** (no se ha vuelto a leer en esta
sesión): NIST TN 2329, pp. 26-29, para viviendas.

| clase | ELA a 4 Pa | m² | uso |
|---|---|---|---|
| `entry_tight` | **12 cm²** | 0,0012 | entrada de vivienda al portal (puerta con burlete) |
| `interior_standard` | **21 cm²** | 0,0021 | puerta interior corriente (sin burlete) |
| override explícito | lo que diga el escenario | — | puerta vieja o muy desajustada; **nunca por defecto** |

- NIST TN 2329 da **12 cm²** para una puerta exterior con burlete y **21 cm²**
  sin él, como área efectiva a 4 Pa. Indica además que, para una puerta
  cerrada, es más apropiado un **flujo de grieta por ley de potencia** que
  tratarla como una abertura normal.
- El trabajo experimental de NIST sobre fugas en puertas (*Estimating Air
  Leakage Through Doors for Smoke Control*) insiste en que las grietas
  estrechas no se comportan como un orificio uniforme.
- **L1/L2/L3 (78/174/289 cm²) quedan descartados como valores.** Eran áreas
  geométricas de la sonda, entre 4 y 24 veces por encima de estos ELA. Siguen
  valiendo como sensibilidad (§4-§5).
- Los valores son **provisionales** hasta medirlos con el modelo integrado
  (§6.6, paso 4).

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
  4 Pa; escala con el exponente n; signo y cota; tramo lineal cerca de 0;
  reparto que conserva el total).
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
2. **Convención del ELA**: el coeficiente de descarga y el exponente asociados
   a los valores de NIST hay que fijarlos con la fuente antes de codificar.
3. **Doble conteo con la deformación térmica**, que hoy va por la heurística de
   fondo. Con el interruptor encendido no deben actuar las dos a la vez.
4. **Auditoría de escritores de O₂**: añadir propietarios y actualizar
   `writer_coverage` (47/25/22 desde el 2026-09-16).
5. **Inventario P1R4**: clasificar el interruptor nuevo y subir
   `EXPECTED_DECLARATION_COUNT`.
6. **R2-1**: tocar `sim/core` obliga a regenerar los informes de referencia.
7. **Rendimiento**: N bandas por puerta cerrada y paso; es barato.
8. **La vista**: el humo bajo la puerta necesita su propio efecto. Queda fuera
   de este trabajo.

## 10. Archivos de una implementación posterior

- **Etapa 1 (modelo puro)**: `sim/core/ClosedDoorLeakageModel.gd` y sus tests
  con ΔP impuestas;
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
