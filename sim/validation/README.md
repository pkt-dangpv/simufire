# Validation Cases

Ejecutar un caso headless:

```powershell
& 'C:\Users\dangp\Desktop\Godot_v4.6.2-stable_win64.exe' --headless --path 'C:\Users\dangp\Documents\GitHub\simufire' -- --validation-case=living_room_hallway
```

Casos iniciales:

- `living_room_hallway`: propagacion de humo y calor entre salon y pasillo
- `postfire_decay`: cola post-incendio y limpieza residual
- `layer150_tenability`: seguimiento de `L150` y temperatura a `1.8 m`

Salidas:

- reportes JSON en `sim/validation/reports/`
- si existe un baseline con el mismo nombre en `sim/validation/baselines/`, el runner compara y devuelve `PASS/FAIL`
