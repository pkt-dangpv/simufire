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
- Simufire modela `O2`, `CO`, `CO2` y `FED` asfixiante/termico.
- El caso `ghanekar_bedroom_hallway` replica los rasgos principales del ensayo de dormitorio: techo de `2.45 m`, ventana del dormitorio abierta, puerta exterior abierta y transporte por pasillo.
- El pasillo se divide en dos zonas numericas (`Hallway_Near` y `Hallway_Far`); la union entre ambas se trata como frontera amplia, no como puerta fisica.
- Simufire todavia no modela `HCN` ni una sonda localizada a `0.9 m` con retardo de linea de muestreo.

### Estado de calibracion actual
- Ultima corrida de `ghanekar_bedroom_hallway`:
  - `time_room_2_o2_below_20_4pct_s = 176.7 s`
  - `time_room_2_co_above_200ppm_s = 276.3 s`
  - `room_2_peak_co_ppm = 518.9 ppm`
  - `room_2_peak_co2_ppm = 8221.6 ppm`
  - `peak_temp_upper_c_global = 611.1 C`
- `run_reference_checks.ps1` mantiene 28/28 checks obligatorios en `PASS`.
- El check de O2 remoto queda dentro de la ventana del paper (`198 +/- 30 s`).
- El CO remoto supera 200 ppm, pero todavia llega tarde frente al objetivo no bloqueante (`204 +/- 45 s`).

### Interpretacion honesta
- La tendencia fisica ya es coherente: combustible sintetico moderno produce mas humo/CO y el flow-path arrastra gases al pasillo remoto.
- La calibracion no debe leerse como una replica completa de la sonda experimental del paper.
- Para cerrar Ghanekar del todo hace falta modelar medicion a `0.9 m`, `HCN`, retardo de linea de muestreo y mezcla vertical/local, no solo promedios por sala.

## Brechas de modelo mas relevantes

1. Medimos por sala promediada, no en una sonda localizada a `0.9 m`.
2. No existe `HCN`, que en el paper es clave para tenabilidad.
3. Falta retardo de linea de muestreo (`16-23 s`) y postproceso de sonda.
4. Nuestro criterio de `flashover` no es el del paper:
   - paper: `T(0.9 m) > 600 C`
   - Simufire: umbral interno por `temp_upper_c` y descenso de capa.
5. La mezcla vertical/local en pasillos sigue siendo aproximada por zonas.

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
- "coincide con checks obligatorios internos y referencias CFAST/Ghanekar seleccionadas"

y no como:
- "coincide con evidencia experimental residencial a escala real".
