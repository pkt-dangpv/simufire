# Validation Cases

## Ejecucion recomendada

Usar el wrapper PowerShell del repo para lanzar cada caso con un `--log-file` unico.
Esto evita crashes intermitentes de Godot al reutilizar `user://logs` en ejecuciones
seguidas.

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_case.ps1 -CaseName living_room_hallway
```

Para correr toda la bateria con parada al primer fallo y resumen final:

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_all_cases.ps1
```

Para regenerar los casos de referencia externa y comparar contra el CSV CFAST/NIST
local y las metricas del paper de Ghanekar:

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_reference_checks.ps1
```

Para proteger la sesion de cuelgues, ambos wrappers aceptan `-TimeoutSeconds`:

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_all_cases.ps1 `
  -TimeoutSeconds 120 `
  -ContinueOnFailure
```

Tambien acepta overrides opcionales:

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_case.ps1 `
  -CaseName postfire_decay `
  -ValidationDuration 1900 `
  -ValidationOutput .\sim\validation\reports\postfire_decay.json
```

Y la bateria completa puede seguir aunque falle un caso:

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_all_cases.ps1 `
  -ContinueOnFailure
```

## Ejecucion directa

Si necesitas lanzar Godot manualmente, pasa siempre un `--log-file` absoluto o relativo
al proyecto para no depender del log por defecto de `user://logs`:

```powershell
& 'F:\OneDrive\Escritorio\Godot_v4.6.3-stable_win64_console.exe' `
  --headless `
  --path 'F:\OneDrive\Documentos\GitHub\simufire' `
  --log-file '.godot_validation_logs\living_room_hallway.log' `
  -- `
  --validation-case=living_room_hallway
```

## Casos

- `living_room_hallway`: propagacion corta de humo y calor entre salon y pasillo
- `postfire_decay`: extincion, deposicion de humo residual y retorno termico casi ambiente
- `layer150_tenability`: mismo escenario base prolongado, centrado en `L150` y temperatura a `1.8 m`
- `tmp_r2_window_open_start`: fuego en salon con ventana exterior abierta desde inicio en Dormitorio1; valida contaminantes, calentamiento moderado por ruta remota de ventilacion y que `R0` no se extinga falsamente cuando la ruta `R0 -> pasillo -> R2 -> exterior` sigue abierta
- `cfast_r0_window_360`: caso de ventana a exterior abierta en `t=360 s`, calibrado contra el input/CSV CFAST local de NIST
- `ghanekar_bedroom_hallway`: caso residencial calibrado contra metricas medibles del paper de Ghanekar
- `ul_exterior_water_knockdown`: golpe de agua UL/FSRI de 570 l/min durante 10 s en el compartimento de fuego; valida 95 l aplicados, extraccion termica y reduccion rapida de temperatura/HRR

## Referencias externas

`cfast_r0_window_360` compara HRR, O2, temperaturas, altura de capa y CO de capa
alta contra el CSV local de CFAST/NIST. En ese caso `fed_heat_enabled=false`
porque el objetivo es validar el compartimento contra CFAST, no una exposicion de
victima dentro de la capa caliente.

`ghanekar_bedroom_hallway` usa combustible mixto de dormitorio moderno y una
frontera numerica amplia entre los dos tramos del pasillo. Los checks obligatorios
cubren respuesta de O2, temperatura superior razonable y ausencia de clamp de
temperatura. Siguen como gaps conocidos no bloqueantes el flashover a `0.9 m` y
la temporizacion completa de CO/HCN/FED del paper.

## Eventos de supresion

Los casos pueden incluir `suppression_events` con `time_s`, `room_id`, `duration_s`,
`flow_lpm` y `effectiveness`. El runner reparte el volumen durante la duracion del
evento para representar un golpe corto de agua, como los ensayos UL/FSRI de ataque
transicional.

## Salidas

- reportes JSON en `sim/validation/reports/`
- si existe un baseline con el mismo nombre en `sim/validation/baselines/`, el runner compara y devuelve `PASS/FAIL`
- `run_reference_checks.ps1` escribe `sim/validation/reports/reference_checks.json` con checks obligatorios y gaps conocidos no bloqueantes

## Nota sobre extincion

`time_to_extinction_s` se registra cuando no queda ningun `has_fire` activo. No debe
interpretarse como extincion real un cruce momentaneo por debajo del umbral de HRR.
