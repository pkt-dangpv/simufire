# Referencia Empirica - Ghanekar 2026

Fuente local:
- `F:\OneDrive\Escritorio\Evolution of combustion gas concentrations in full-scale residential fire.pdf`

Referencia:
- Shruti Ghanekar, "Evolution of combustion gas concentrations in full-scale residential fire environments", Fire Safety Journal 162 (2026) 104724.

## Por que importa para Simufire

Este paper aporta datos de escala real para contrastar la evolucion temporal de:
- `O2`
- `CO2`
- `CO`
- `HCN`
- tiempos a `flashover`
- tiempos a `IDLH`
- tiempos a `FED`

Eso lo convierte en una referencia mucho mas fuerte que nuestros baselines actuales, que hoy validan contra escenarios internos del repo.

## Escenario experimental del paper

### Estructura
- Vivienda unifamiliar de una planta, `160 m2`, tipo ranch.
- Altura de techo: `2.45 m`.
- Cuatro dormitorios, dos banos y zona abierta cocina-salon.
- HVAC apagado pero con rejillas abiertas para movimiento pasivo de aire y gases.

### Medicion
- Punto de muestreo en el extremo del pasillo a `0.9 m` de altura.
- Frecuencia de muestreo: `1 Hz`.
- Tiempo de transporte del gas hasta analizadores: `16-23 s`.

### Ventilacion inicial
- Puerta principal abierta en todos los experimentos.
- Ventana del compartimento de fuego abierta/removida desde el inicio:
  - dormitorio: `1.8 m x 0.6 m`
  - cocina: `0.9 m x 0.9 m`

### Definicion de flashover
- Se considera `flashover` cuando la temperatura a `0.9 m` en el compartimento de fuego supera `600 C`.

## Benchmarks extraidos del paper

### Dormitorio
- `time_to_flashover = 3.1 +/- 0.3 min`
- `time_to_vent_failure = 3.8 +/- 0.4 min`
- `time_to_intervention = 4.9 +/- 0.3 min`

- Respuesta inicial en pasillo a `0.9 m`:
  - `tDeltaO2 = 3.3 +/- 0.3 min`
  - `tDeltaCO2 = 3.3 +/- 0.3 min`
  - `tDeltaCO = 3.4 +/- 0.3 min`
  - `tDeltaHCN = 3.3 +/- 0.2 min`

- Cambio maximo antes de intervencion:
  - `DeltaO2 = -9.25 +/- 1.65 vol%`
  - `DeltaCO2 = +8.53 +/- 1.85 vol%`
  - `DeltaCO = +1.42 +/- 0.50 vol%`
  - `DeltaHCN = +97 +/- 47 ppm`

- Tenabilidad:
  - `time_to_IDLH = 3.6 +/- 0.2 min`
  - `time_to_FED_0_3 = 3.7 +/- 0.2 min`
  - `time_to_FED_1 = 3.7 +/- 0.2 min`

### Cocina / salon
- `time_to_flashover = 14.9 +/- 0.5 min`
- `time_to_vent_failure = 15.2 +/- 1.8 min`
- `time_to_intervention = 16.8 +/- 0.9 min`

- Respuesta inicial en pasillo a `0.9 m`:
  - `tDeltaO2 = 6.7 +/- 1.4 min`
  - `tDeltaCO2 = 6.8 +/- 1.6 min`
  - `tDeltaCO = 8.0 +/- 2.2 min`
  - `tDeltaHCN = 9.8 +/- 3.5 min`

- Cambio maximo antes de intervencion:
  - `DeltaO2 = -19.88 +/- 1.27 vol%`
  - `DeltaCO2 = +19.79 +/- 0.77 vol%`
  - `DeltaCO > +4.83 +/- 0.46 vol%`
  - `DeltaHCN = +660 +/- 211 ppm`

- Tenabilidad:
  - `time_to_IDLH = 10.7 +/- 1.7 min`
  - `time_to_FED_0_3 = 9.1 +/- 2.0 min`
  - `time_to_FED_1 = 10.4 +/- 2.1 min`

## Lo que esto dice sobre nuestro simulador actual

### Lo comparable hoy
- Simufire ya modela `O2` y `CO`.
- Simufire todavia no modela:
  - `CO2`
  - `HCN`
  - `FED`
  - un punto de sonda a `0.9 m` con retardo de transporte

### Diferencia de escenario
- Nuestro caso principal actual usa `simple_house` en [`BuildingTemplate.gd`](/F:/OneDrive/Documentos/GitHub/simufire/sim/templates/BuildingTemplate.gd:1).
- Ese escenario no replica el del paper:
  - geometrias distintas
  - puertas interiores distintas
  - sin puerta principal exterior abierta
  - ventanas exteriores cerradas por defecto (`open_fraction = 0.0`)
  - fuego principal en `salon` o diagnostico interno, no en dormitorio/cocina del ensayo

### Contraste con la corrida larga actual del repo
- Corrida fresca ejecutada hoy:
  - [`long_smoke_o2_debug.json`](/F:/OneDrive/Documentos/GitHub/simufire/sim/validation/reports/long_smoke_o2_debug.json:1)
  - [`long_smoke_o2_debug.log`](/F:/OneDrive/Documentos/GitHub/simufire/sim/validation/reports/long_smoke_o2_debug.log:1)

- Hitos actuales:
  - `time_room_1_smoke_start_s = 126.75 s` (`2.11 min`)
  - `time_to_extinction_s = 318.25 s` (`5.30 min`)

- Lectura del pasillo en la corrida larga:
  - a `130.1 s` (`2.17 min`): `ROOM 1 O2 = 17.23 %`, `CO = 2436 ppm`
  - a `150.1 s` (`2.50 min`): `ROOM 1 O2 = 17.01 %`, `CO = 6322 ppm`

### Interpretacion honesta
- Si tomamos `ROOM 1` como proxy burdo del pasillo, el modelo entra en condiciones `IDLH` bastante antes que el benchmark empirico de dormitorio (`3.6 min`).
- El desajuste no demuestra por si solo que la fisica este mal, porque la configuracion de ventilacion y geometria no coincide con la del paper.
- Pero si demuestra que hoy no podemos decir que el modelo este calibrado contra esta evidencia experimental.

## Brechas de modelo mas relevantes

1. Medimos por sala promediada, no en una sonda localizada a `0.9 m`.
2. No existe `CO2`, asi que no podemos contrastar dilucion/ventilacion con el paper.
3. No existe `HCN`, que en el paper es clave para tenabilidad.
4. No existe calculo de `IDLH` y `FED` a partir de especies medidas.
5. Nuestro criterio de `flashover` no es el del paper:
   - paper: `T(0.9 m) > 600 C`
   - Simufire: umbral interno por `temp_upper_c` y descenso de capa.
6. La ventilacion inicial del benchmark experimental no esta representada.

## Siguiente paso recomendado

1. Crear un caso nuevo de validacion empirica inspirado en este paper:
   - `ghanekar_bedroom_hallway_0_9m`
   - `ghanekar_kitchen_hallway_0_9m`
2. Anadir sonda de gases a altura fija:
   - `O2`
   - `CO`
   - despues `CO2` y `HCN`
3. Implementar postproceso de tenabilidad:
   - umbrales `IDLH`
   - `FED`
4. Ajustar primero ventilacion y transporte al pasillo antes de recalibrar yields toxicos.

## Decision de producto / validacion

Hasta tener esos casos, los `PASS` actuales deben leerse como:
- "coincide con nuestros baselines internos"

y no como:
- "coincide con evidencia experimental residencial a escala real".
