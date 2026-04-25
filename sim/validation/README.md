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
& 'C:\Users\dangp\Desktop\Godot_v4.6.2-stable_win64_console.exe' `
  --headless `
  --path 'C:\Users\dangp\Documents\GitHub\simufire' `
  --log-file '.godot_validation_logs\living_room_hallway.log' `
  -- `
  --validation-case=living_room_hallway
```

## Casos

- `living_room_hallway`: propagacion corta de humo y calor entre salon y pasillo
- `postfire_decay`: extincion, deposicion de humo residual y retorno termico casi ambiente
- `layer150_tenability`: mismo escenario base prolongado, centrado en `L150` y temperatura a `1.8 m`
- `tmp_r2_window_open_start`: fuego en salon con ventana exterior abierta desde inicio en Dormitorio1; valida contaminantes, calentamiento moderado por ruta remota de ventilacion y que `R0` no se extinga falsamente cuando la ruta `R0 -> pasillo -> R2 -> exterior` sigue abierta

## Salidas

- reportes JSON en `sim/validation/reports/`
- si existe un baseline con el mismo nombre en `sim/validation/baselines/`, el runner compara y devuelve `PASS/FAIL`

## Nota sobre extincion

`time_to_extinction_s` se registra cuando no queda ningun `has_fire` activo. No debe
interpretarse como extincion real un cruce momentaneo por debajo del umbral de HRR.
