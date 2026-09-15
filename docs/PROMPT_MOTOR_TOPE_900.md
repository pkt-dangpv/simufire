# Diagnóstico: el tope de 900 °C tapa capas superiores casi vacías

> **A y B hechos el 2026-09-15** (decisión del usuario: las dos, con
> interruptor), los dos **apagados por defecto**:
>
> - **A** `thin_upper_layer_min_mass_fraction` (`SimulationEngine` →
>   `ZoneFireSolver`, 0 = apagado): por debajo de esa fracción de la masa de la
>   zona, `project_room_state` mezcla la capa superior con la inferior
>   conservando energía, por la misma rama que las inversiones térmicas. Solo
>   en el solver de dos zonas (el de serie). En el patio de este documento, con
>   0,002: **las zonas del patio pasan de 900 °C (recortado) a 369 °C** y la sala
>   del fuego no se mueve (557 → 556 °C).
> - **B** `upper_radiative_loss_full_c` (`SimulationEngine` y `ThermalSystem`,
>   -1 = seguir al tope): techo propio de la rampa radiativa en las tres rampas
>   (`ThermalSystem._compute_upper_radiative_loss_kj`, el contexto de pared
>   canónico y `SimulationEngine`). Con -1 es el tope, así que los 20 casos con
>   tope 480 irradian igual.
> - Guardarraíl `tools/validate_upper_layer_temperature.gd` (en
>   `check_product.py`, ~17 s) con el patio como fixture
>   (`tests/fixtures/upper_layer_thin_patio.json`). **12/12 mutaciones
>   muertas**: capa fina nunca detectada, mezcla de capas gruesas, fracción que
>   no llega al solver, motor que ignora la del escenario, editor que no la
>   enciende, `BuildingModel` que no la carga, mezcla que no conserva energía,
>   `ThermalSystem` y motor que ignoran el techo radiativo, techo bajo el
>   arranque tomado como fijado, rampa que vuelve al tope y `configure` que no
>   lee el techo. Con los dos apagados, `cfast_two_room_door_open` (tope 480)
>   sale idéntico byte a byte (CSV y JSON) al informe versionado.
> - **Dónde se enciende A** (decisión del usuario, 2026-09-15): en los
>   escenarios del editor, igual que el viento por altura.
>   `ScenarioSerializer.EDITOR_THIN_UPPER_LAYER_MIN_MASS_FRACTION = 0,002` va en
>   el JSON de ejecución, `BuildingModel` lo carga y el motor aplica el del
>   escenario si es mayor que 0 (`_effective_thin_upper_layer_min_mass_fraction`).
>   Las plantillas del catálogo y los casos de validación siguen a 0.

Medido el 2026-09-15, **sin tocar código**. Motivo: el tope de 900,0 °C salió en
tres configuraciones del portal y del patio (`PROMPT_MOTOR_PORTAL.md`,
`PROMPT_MOTOR_PATIO.md`) y un número redondo clavado huele a recorte, no a
resultado.

## Cómo se midió

- Escenarios: el patio de tres plantas del 2026-09-11 y la variante B del
  portal del 2026-09-13, 300 s, con `scripts/run_scenario.py`.
- Dos topes: el de serie (`max_upper_temp_c = 900`) y 5000 °C vía
  `engine_overrides`.
- Con `--phase3-zone-diagnostics` para tener `upper_gas_kg`, `upper_energy_kj`
  y `lower_gas_kg` en el CSV. **Es pasivo**: `temp_upper_c` idéntica fila a fila
  (máx. |ΔT| = 0,000000 °C) frente a la misma pasada sin la opción.

## Lo que sale

| zona | tope | T capa sup. | masa capa sup. | espesor | masa capa inf. |
|---|---|---|---|---|---|
| Patio P1 | 900 | 900 °C | **8,6 g** | 0,5 cm | 21,6 kg |
| Portal R (variante B) | 900 | 900 °C | **0,7 g** | 0,0 cm | 55,6 kg |
| Patio P0 | 900 | 823 °C | 24,6 g | 1,2 cm | 21,6 kg |
| Patio P0 | 5000 | **2945 °C** | **2,8 g** | 0,4 cm | 21,7 kg |
| Patio P1 | 5000 | **2218 °C** | 16,3 g | 1,8 cm | 21,5 kg |
| Vivienda P0 (fuego de verdad) | 900 | 580 °C | 14,6 kg | 177 cm | 15,3 kg |

**En todos los picos de 900 °C —y en los de casi 3000 °C con el tope subido— la
capa superior tiene gramos de gas y un espesor de milímetros.** La temperatura
sale de `T = T_amb + E / (m·cp)` (`ZoneFireSolver.project_room_state`,
`ThermalSystem._estimate_raw_upper_temp_c`): unos pocos kJ que entran en unos
gramos dan temperaturas imposibles (una llama no pasa de ~1200 °C). Es una
**singularidad numérica de capa casi vacía**, no calor: esos gramos llevan
1–36 kJ, nada en el balance. El tope de 900 °C no es un resultado; es el
parche que la tapa.

## Tres hallazgos más

1. **La telemetría del recorte no puede enseñarlo.** Al recortar, la energía
   sobrante se descarta (`upper_energy_kj = m·(T_tope − T_amb)`), así que en la
   siguiente proyección `temp_upper_raw_c` vuelve a salir 900 y
   `temp_upper_clamped` se apaga. El TXT marca `RawUp=900.0 | Cap=N` en pasos
   que sí recortaron (`CapT` > 0). Solo subiendo el tope se ve el valor real.
2. **Subir el tope cambia la física, no solo la lectura.** La activación de la
   pérdida radiativa de la capa superior es lineal entre
   `upper_radiative_loss_start_c` (80) y `max_upper_temp_c`
   (`ThermalSystem` ~2832 y ~2399, `SimulationEngine` ~2605): con tope 900 la
   capa irradia al 100 % a 900 °C; con tope 5000, al 17 %. Por eso la vivienda
   del fuego del portal pasa de 554 a 861 °C al subir el tope. Un tope numérico
   no debería gobernar una pérdida física.
3. **Dónde se nota hoy.** `temp_upper_c` de esas zonas alimenta lo que lee la
   temperatura de capa: el HUD y la vista, el término de calor de la FED (Patio
   P1 marca `Q:0.0020`), la radiación a objetos y blancos y el efecto
   chimenea. Las masas de humo y las presiones del portal y del patio no
   dependen de esto, y por eso se movían con coherencia.

## Qué se podría hacer (sin decidir)

- **A. Masa mínima de capa superior.** Por debajo de un umbral (fracción de la
  masa de la zona, o espesor mínimo), la temperatura que se informa y se usa es
  la de la mezcla de las dos capas (energía total / masa total), no la de la
  lámina. Conserva la energía y quita la singularidad en el origen. Detrás de
  interruptor apagado por defecto: la suite no se mueve.
- **B. Desacoplar la radiación del tope.** Un parámetro propio para el techo de
  la rampa radiativa (por defecto 900, así que no cambia nada) para que el tope
  pueda subir sin cambiar cuánto irradia la capa.
- **C. Las dos.** A arregla la causa; B deja medir sin contaminar.

Ficheros de la medición (cuaderno de la sesión): `patio.json`, `portal_B.json`,
`leer_tope.py`, `leer_diag.py`.
