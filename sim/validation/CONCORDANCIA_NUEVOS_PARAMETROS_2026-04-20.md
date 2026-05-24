# Prueba de concordancia con parametros actuales

Fecha de ejecucion:
- `2026-04-20`

Caso ejecutado:
- `long_smoke_o2_debug`

Comando ejecutado:

```powershell
& 'F:\OneDrive\Escritorio\Godot_v4.6.3-stable_win64_console.exe' --headless --path 'F:\OneDrive\Documentos\GitHub\simufire' -- --validation-case long_smoke_o2_debug
```

Salida generada:
- `sim/validation/reports/long_smoke_o2_debug.json`
- `sim/validation/reports/long_smoke_o2_debug.log`

Marca temporal del reporte:
- `2026-04-20 07:23:31`

## Resultado bruto de la corrida

Metricas principales:

- `time_room_1_smoke_start_s = 126.75 s` (`2.11 min`)
- `time_room_0_smoke_layer_2m_s = 126.67 s` (`2.11 min`)
- `time_room_0_temp_1_8m_above_150c_s = 110.50 s` (`1.84 min`)
- `time_to_extinction_s = 318.25 s` (`5.30 min`)
- `room_1_peak_temp_upper_c = 190.27 C`
- `room_1_peak_co_ppm = 6750 ppm`

Lecturas de `ROOM 1` en el log:

- `130.1 s`: `O2 = 17.23 %`, `CO = 2436 ppm`
- `140.1 s`: `O2 = 16.67 %`, `CO = 4064 ppm`
- `150.1 s`: `O2 = 17.01 %`, `CO = 6322 ppm`
- `160.0 s`: `O2 = 17.62 %`, `CO = 5286 ppm`

## Contraste con referencia empirica

Referencia usada:
- `Evolution of combustion gas concentrations in full-scale residential fire environments`
- resumen local en `sim/validation/EMPIRICAL_REFERENCE_GHANEKAR_2026.md`

Benchmarks de dormitorio del paper:

- respuesta inicial de gases en pasillo: `3.3 +/- 0.3 min`
- `time_to_IDLH = 3.6 +/- 0.2 min`

## Concordancia observada

### Transporte al pasillo

- Simufire: `2.11 min`
- Paper dormitorio: `3.3 +/- 0.3 min`
- Desviacion: `-1.19 min`

Interpretacion:
- el modelo sigue llevando humo al pasillo demasiado pronto.

### Condiciones severas en pasillo

Proxy usado:
- `ROOM 1` del caso actual como aproximacion bruta al pasillo.

Observacion:
- ya a `130.1 s` (`2.17 min`) el pasillo proxy cae a `17.23 %` de `O2` y marca `2436 ppm` de `CO`.
- a `150.1 s` (`2.50 min`) el `CO` sube a `6322 ppm`.

Comparacion:
- el paper sitia `IDLH` del dormitorio en `3.6 +/- 0.2 min`.
- nuestro proxy entra en condiciones muy severas entre `2.2` y `2.5 min`.

Interpretacion:
- el modelo sigue siendo demasiado agresivo en la contaminacion temprana del pasillo.

### Duracion del incendio

- Simufire extingue el fuego a `5.30 min`.
- El benchmark de dormitorio del paper aun tiene `vent failure` a `3.8 min` e `intervention` a `4.9 min`.

Interpretacion:
- con el escenario actual, el fuego arranca fuerte pero se agota o estrangula pronto.

## Conclusion

Con los parametros actuales, la concordancia empirica sigue siendo insuficiente.

Lo que se mantiene igual respecto al analisis anterior:

- el humo llega demasiado pronto al pasillo,
- el pasillo entra en condiciones severas antes que el benchmark experimental,
- y el patron apunta otra vez a la misma causa estructural:
  - interior demasiado abierto,
  - exterior demasiado poco ventilado,
  - caso de validacion no equivalente al ensayo real.

## Decision tecnica

No tiene sentido seguir interpretando `long_smoke_o2_debug` como validacion empirica directa.

El siguiente paso correcto sigue siendo:

1. crear un caso nuevo `ghanekar_bedroom_hallway`,
2. replicar su ventilacion inicial,
3. anadir sonda a altura fija en pasillo,
4. y recalibrar sobre ese caso antes de tocar mas coeficientes.

## Nota de ejecucion

- Tambien se intento lanzar `postfire_decay`, pero la herramienta agotó el timeout antes de completar la corrida y no se ha usado para este contraste empirico.
