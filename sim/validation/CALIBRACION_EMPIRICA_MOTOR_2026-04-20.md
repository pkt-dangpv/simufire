# Calibracion Empirica del Motor - 2026-04-20

## Estado actual

Se ha dejado activa en el motor la transferencia explicita de calor hacia la capa baja a traves de `lower_layer_warming_rate`, ya cableada entre:
- `sim/core/SimulationEngine.gd`
- `sim/core/ThermalSystem.gd`

Ese cambio pasa a formar parte del comportamiento normal del motor. No hace falta una variante especial del caso para usarlo.

## Benchmark principal usado

Caso empirico:
- `sim/validation/cases/ghanekar_bedroom_hallway.json`

Reporte canónico actualizado:
- `sim/validation/reports/ghanekar_bedroom_hallway.json`

Microcalibracion:
- `sim/validation/MICRO_CALIBRACION_GHANEKAR_2026-04-20.md`
- `sim/validation/reports/micro_sweeps/ghanekar_micro_calibration_2026-04-20.json`

## Resultado de la calibracion elegida

La mejor calibracion provisional no ha sido una combinacion exotica de overrides, sino el propio motor actual con `lower_layer_warming_rate` ya activo.

Metricas del caso canonico:
- `time_room_0_temp_0_9m_above_600c_s = 198.58 s`
- `time_room_2_o2_below_20_4pct_s = 137.75 s`
- `time_room_2_co_above_200ppm_s = 147.00 s`
- `time_room_2_co_above_1200ppm_s = 153.75 s`
- `time_room_2_smoke_start_s = 146.33 s`

Comparado con Ghanekar dormitorio:
- `flashover`: objetivo `186 +/- 18 s`
- `tDeltaO2 hallway`: objetivo `198 +/- 18 s`
- `tDeltaCO hallway`: objetivo `204 +/- 18 s`
- `IDLH`: objetivo `216 +/- 12 s`

## Lo que ya queda razonablemente bien

### 1. Criterio de flashover a 0.9 m

El motor ya reproduce el benchmark de `flashover` del dormitorio de forma razonable:
- modelo: `198.58 s`
- experimento: `186 +/- 18 s`

Eso mete al modelo dentro de la banda experimental de este benchmark para el compartimento de fuego.

### 2. Acoplamiento termico upper/lower

La zona respirable del compartimento de fuego ya no queda artificialmente fria como antes.
Ese era el mayor defecto del modelo frente al paper.

## Lo que sigue quedando corto

### 1. Transporte axial al final del pasillo

El pasillo distal sigue respondiendo demasiado pronto:
- `O2`: ~`60 s` antes del benchmark central
- `CO`: ~`57 s` antes
- proxy `IDLH`: ~`62 s` antes

### 2. Mezcla espacial demasiado gruesa

La causa mas probable ya no es un simple coeficiente, sino la representacion:
- el pasillo sigue siendo un conjunto de volúmenes lumped
- no hay retardo axial interno real dentro de cada tramo
- no hay sonda localizada con retardo de linea de muestreo
- no hay HVAC pasivo explicito

## Decision de calibracion tomada

Se mantiene como calibracion provisional del motor:
- activar `lower_layer_warming_rate` en la termica del motor
- no sobreescribir los defaults con variantes agresivas del barrido

Motivo:
- las variantes que mejoraban la temperatura respirable adelantaban demasiado el flashover
- las variantes que intentaban amortiguar el pasillo no recuperaban suficiente tiempo
- el mejor compromiso global ha sido el motor actual ya cableado

## Que significa "realista" ahora mismo

Con el estado actual podemos decir:
- el compartimento de fuego del benchmark dormitorio ya tiene una respuesta termica mucho mas creible
- el modelo sigue siendo demasiado rapido en el transporte de gases hacia el extremo del pasillo

Asi que el limite de realismo ya no esta tanto en la energia del fuego, sino en la resolucion espacial del transporte.

## Siguiente salto de realismo de verdad

Si queremos mejorar de forma material a partir de aqui, los siguientes cambios ya no son de ajuste fino sino de modelo:

1. Subdividir el transporte en corredor y estancias conectadas con mas resolucion axial.
2. Añadir sonda localizada a `0.9 m` con opcion de retardo de analizador (`16-23 s`).
3. Introducir `CO2`, `HCN` y `FED`.
4. Modelar mejor ventilacion pasiva/HVAC del ensayo.

## Regresion interna

Intente relanzar `long_smoke_o2_debug` para una comprobacion rapida fuera del caso empirico, pero el wrapper local corto por timeout antes de cerrar. No lo uso como validacion final de esta calibracion.
