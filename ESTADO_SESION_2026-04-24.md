# Simufire - Estado de sesion
**Ultima actualizacion**: 24 abril 2026

## Objetivo de esta sesion
- Reproducir el caso que comento el usuario:
  - incendio en `R0=Salon`
  - ventana exterior abierta en otra habitacion, no en `R0`
- Ver si el comportamiento parecia poco realista y ajustar el modelo.

## Contexto confirmado al retomar
- Los tres casos oficiales del bloque anterior quedaron en `PASS` antes de empezar esta investigacion:
  - `living_room_hallway`
  - `layer150_tenability`
  - `postfire_decay`
- Repo en `main` con varios cambios locales ya existentes no relacionados solo con esta tarea.

## Caso nuevo creado para reproducir el problema
- Archivo nuevo:
  - `sim/validation/cases/tmp_r2_window_open_start.json`
- Configuracion:
  - plantilla `simple_house`
  - ignicion en `R0`
  - ventana de `R2=Dormitorio1` abierta desde `t=0`
  - duracion `600 s`
  - logging activado en:
    - `sim/validation/reports/tmp_r2_window_open_start.log`
    - `sim/validation/reports/tmp_r2_window_open_start.json`

## Resultado observado antes del ajuste
- El caso se corrio correctamente una vez con:

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_case.ps1 -CaseName tmp_r2_window_open_start
```

- Indicadores poco realistas detectados:
  - abrir la ventana de `R2` apenas cambiaba el desarrollo del fuego en `R0`
  - `R2` se mantenia casi a `20 C` todo el tiempo
  - `R2` recibia muy poca carga toxica comparado con otras salas cerradas
  - otras habitaciones sin ventana abierta seguian acumulando mucho `CO2/CO`

### Evidencia concreta del log previo al ajuste
- En `t=150.1 s`:
  - `R0`: `HRR=1190 kW`, `Up=900 C`, `CO2=18051 ppm`
  - `R1`: `Up=110 C`, `CO2=27445 ppm`
  - `R2`: `Up=20 C`, `Smoke=0.0000`, `CO2=1696 ppm`
- En `t=330.1 s`:
  - `R2`: `Up=20 C`, `Smoke=0.2863`, `CO2=4999 ppm`
  - `R3`: `Up=20 C`, `Smoke=0.2858`, `CO2=24968 ppm`
- Interpretacion:
  - el modelo estaba dejando pasar algo de `O2/CO2` de fondo, pero el camino interior inducido por una ventana exterior remota arrastraba demasiado poco humo/CO/CO2
  - la apertura exterior de `R2` funcionaba mas como una "purga local" que como una via de through-flow para el conjunto del piso

## Cambios implementados en esta sesion

### `sim/core/OxygenExchangeSystem.gd`
- Se aumento el intercambio de fondo por puertas abiertas cuando una de las salas conectadas tiene una abertura exterior abierta.
- Se anadio helper local:
  - `_estimate_room_outside_open_factor(building, room)`
- Objetivo:
  - que una ventana abierta en una sala remota tire mas del recorrido interior y no solo del aire local de esa sala.

### `sim/core/GasExchangeSystem.gd`
- Se anadio mezcla de fondo de especies entre salas a traves de aberturas interiores:
  - humo
  - `CO`
  - `CO upper`
  - `CO2`
- Nuevo metodo:
  - `_apply_background_species_exchange(...)`
- Este intercambio de fondo:
  - usa el area efectiva de la puerta
  - crece con la sobrepresion
  - se refuerza cuando una de las dos salas tiene una abertura exterior abierta
- Objetivo:
  - que el camino interior por puertas abiertas transporte tambien contaminantes cuando el flujo no viene solo como gran derrame de capa caliente.

## Estado exacto al interrumpirse
- Se lanzo una nueva corrida del caso `tmp_r2_window_open_start` despues de los cambios.
- El usuario interrumpio esa corrida antes de que yo pudiera leer y evaluar el nuevo reporte.
- Por eso:
  - **el diagnostico fiable disponible sigue siendo el del reporte/log anterior al ajuste**
  - **la rerun posterior a los cambios aun no esta validada**

## Procesos vivos ahora mismo
- Quedaron dos procesos de Godot arrancados por la corrida interrumpida:
  - `Godot_v4.6.2-stable_win64` PID `25576`
  - `Godot_v4.6.2-stable_win64_console` PID `26140`
- No los he matado para no hacer una accion destructiva no pedida.

## Siguiente paso recomendado
1. Cerrar o matar esos dos procesos de Godot.
2. Repetir el caso:

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_case.ps1 -CaseName tmp_r2_window_open_start
```

3. Revisar:
  - `sim/validation/reports/tmp_r2_window_open_start.json`
  - `sim/validation/reports/tmp_r2_window_open_start.log`

4. Comparar especificamente:
  - `R0`: `peak_hrr_kw`, `peak_temp_upper_c`, `time_to_extinction_s`
  - `R1`: `peak_temp_upper_c`, `CO2`
  - `R2`: `peak_temp_upper_c`, `smoke`, `CO2`, `CO`
  - `R3/R5`: si bajan respecto al caso previo

5. Si el nuevo caso mejora, rerun rapido de regresion:

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_case.ps1 -CaseName living_room_hallway
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_case.ps1 -CaseName layer150_tenability
powershell -ExecutionPolicy Bypass -File .\sim\validation\run_case.ps1 -CaseName postfire_decay
```

## Ficheros tocados hoy en esta tarea
- `sim/validation/cases/tmp_r2_window_open_start.json`
- `sim/core/OxygenExchangeSystem.gd`
- `sim/core/GasExchangeSystem.gd`

