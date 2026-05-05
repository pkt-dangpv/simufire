# SimuFire default house vs FDS reference

Fecha: 2026-05-04

Este informe compara tendencias entre:

- FDS: `external/fds/simufire_simple_house_default.fds`
- SimuFire default: `sim/validation/cases/fds_simple_house_default.json`
- SimuFire tuned experiment: `sim/validation/cases/fds_simple_house_calibrated.json`

No es una validacion cientifica exacta. El caso FDS usa una geometria simplificada con paredes interiores y un fuego prescrito en el Salon para tener una referencia CFD repetible.

## Ejecucion FDS

FDS 6.10.1 completo correctamente el caso `simufire_simple_house_default`.

Comando usado:

```bat
call "C:\Program Files\firemodels\FDS6\bin\fdsinit.bat"
"C:\Program Files\firemodels\FDS6\bin\fds_openmp.exe" simufire_simple_house_default.fds
```

Salidas principales:

- `simufire_simple_house_default_hrr.csv`
- `simufire_simple_house_default_devc.csv`
- `simufire_simple_house_default.smv`

## Resumen HRR

| Modelo | Pico HRR | Tiempo pico | HRR final |
| --- | ---: | ---: | ---: |
| FDS | 1015.9 kW | 167 s | 5.2 kW |
| SimuFire default | 720.9 kW | 168 s | 46.2 kW |
| SimuFire tuned experiment | 779.1 kW | 161 s | 39.6 kW |

Lectura: el tiempo de crecimiento concuerda bien, pero SimuFire queda bajo en potencia pico y mantiene mas HRR residual al final.

## Temperatura superior

| Habitacion | FDS pico | SimuFire default pico | Tuned pico | FDS final | SimuFire default final | Tuned final |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Salon | 335 C | 882 C | 886 C | 117 C | 339 C | 164 C |
| Pasillo | 244 C | 92 C | 296 C | 120 C | 55 C | 126 C |
| Dormitorio1 | 141 C | 20 C | 47 C | 102 C | 20 C | 33 C |
| Dormitorio2 | 133 C | 20 C | 49 C | 107 C | 20 C | 34 C |
| Cocina | 132 C | 20 C | 41 C | 114 C | 20 C | 33 C |
| Bano | 125 C | 20 C | 49 C | 96 C | 20 C | 34 C |

Lectura: el motor base deja demasiado frio el Pasillo y las habitaciones remotas. El tuning ayuda al Pasillo, pero las habitaciones de segundo salto siguen demasiado frias. El Salon sigue demasiado caliente en pico.

## Humo / visibilidad

FDS usa visibilidad menor de 10 m. SimuFire usa aqui `smoke_kg > 0.001 kg`, asi que no son umbrales equivalentes; solo sirven como indicador de orden de llegada.

| Habitacion | FDS vis < 10 m | SimuFire default humo > 1 g | Tuned humo > 1 g |
| --- | ---: | ---: | ---: |
| Salon | 31 s | 19 s | 19 s |
| Pasillo | 52 s | 172 s | 79 s |
| Dormitorio1 | 77 s | 218 s | 115 s |
| Dormitorio2 | 77 s | 216 s | 115 s |
| Cocina | 83 s | 221 s | 115 s |
| Bano | 78 s | 220 s | 115 s |

Lectura: el tuning adelanta el transporte de humo, pero aun llega tarde a las habitaciones remotas frente a FDS.

## O2 y CO2

FDS baja O2 hasta 10-12 % en todas las habitaciones hacia el final. SimuFire mantiene O2 demasiado alto fuera del Salon:

- Pasillo: FDS minimo 10.4 %, SimuFire default 17.8 %, tuned 17.3 %.
- Habitaciones remotas: FDS minimo 11.5-11.7 %, SimuFire queda cerca de 20.5-20.7 %.

CO2 mejora algo en habitaciones remotas con el tuning, pero no queda acoplado de forma consistente a O2. Esto indica que la mezcla/transportes de especies siguen descompensados.

## Diagnostico

- Correcto: el tiempo de crecimiento del incendio coincide bastante bien con FDS.
- Parcialmente corregido: el Pasillo ya recibe calor de forma mucho mas realista que antes.
- Pendiente: el Salon acumula demasiada energia en la capa superior durante el pico.
- Pendiente: el calor no se transporta suficientemente desde Pasillo a Dormitorio1, Dormitorio2, Cocina y Bano.
- Pendiente: O2 y CO2 no estan acoplados como en FDS; SimuFire mueve algo de CO2/humo sin agotar O2 de forma comparable.
- Pendiente: la llegada de humo a habitaciones remotas sigue tardia.

## Cambios aplicados

Se anadio un intercambio termico interior configurable en `ThermalSystem.gd` y se expusieron parametros en `SimulationEngine.gd`.

El nuevo intercambio queda desactivado por defecto para no romper baselines existentes. El caso `fds_simple_house_calibrated.json` lo activa como experimento de calibracion.

Esto no es una calibracion final. Es una primera herramienta estructural: evita que el Pasillo quede frio mientras recibe contaminantes, pero aun hace falta ajustar:

- entrainment/masa de capa superior del Salon
- transporte de calor en puertas de segundo salto
- produccion y derrame de humo
- mezcla O2/CO2 entre estancias
