# SimuFire FDS comparison cases

This folder contains FDS 6 reference cases for comparing SimuFire trends. These are engineering comparison cases, not exact validation datasets.

The folder contains a `.gdignore` file so Godot does not import FDS output CSV
files as translation resources. FDS CSV headers contain units such as `kg/s`,
which can confuse Godot's CSV translation importer.

## Default simple house

`simufire_simple_house_default.fds` approximates SimuFire's default `create_simple_house()` template in:

`res://sim/templates/BuildingTemplate.gd`

Rooms:
- Salon: 48.0 m3
- Pasillo: 25.2 m3
- Dormitorio1: 25.2 m3
- Dormitorio2: 16.8 m3
- Cocina: 36.0 m3
- Bano: 16.8 m3

Doors:
- Salon <-> Pasillo
- Cocina <-> Pasillo
- Dormitorio1 <-> Pasillo
- Dormitorio2 <-> Pasillo
- Bano <-> Pasillo

The geometry uses the same rectangular room footprint as the Godot template, one floor, 2.4 m height, closed exterior openings, open interior doors, and a prescribed t-squared fire in Salon using SimuFire's default fire-growth alpha.

## Run

From this folder:

```bat
call "C:\Program Files\firemodels\FDS6\bin\fdsinit.bat"
"C:\Program Files\firemodels\FDS6\bin\fds_openmp.exe" simufire_simple_house_default.fds
```

Or double-click:

```bat
run_simufire_simple_house_default.bat
```

The batch file runs from its own folder, keeps generated files beside the `.fds` input, and then opens Smokeview.

## View results

```bat
"C:\Program Files\firemodels\FDS6\bin\smokeview.exe" simufire_simple_house_default.smv
```

The batch file also tries `C:\Program Files\firemodels\SMV6\smokeview.exe` as a fallback.

## Main output files

FDS generates files such as:
- `simufire_simple_house_default_hrr.csv`
- `simufire_simple_house_default_devc.csv`
- `simufire_simple_house_default.smv`
- Smokeview slice files for temperature, O2, CO2, visibility, and velocity

`simufire_simple_house_default_devc.csv` contains the room sensor time series.
The simple-house case records temperature, O2, CO, CO2 and visibility at room points.

## Comparison variables

Use this case to compare SimuFire logs against FDS trends:
- global HRR
- upper/lower gas temperature by room
- O2 depletion by room
- CO increase by room
- CO2 increase by room
- smoke/visibility spread by room
- FED inputs (CO, O2, CO2 and heat exposure)
- flow path behavior through interior doors

## Measurement comparison report

After running FDS and a SimuFire validation case, create a quick Markdown report:

```bat
python compare_simple_house_results.py
```

This writes:

`simufire_simple_house_measurement_report.md`

The report compares aligned trend metrics. SimuFire CSV output now includes
`visibility_m`, derived from whole-room smoke concentration. The visibility
estimate is only a calibration aid; FDS visibility is a device quantity at
breathing height.

## Small apartment case

`simufire_small_apartment.fds` and `run_simufire_small_apartment.bat` are retained as a standalone historical FDS comparison. The unused legacy SimuFire template they once approximated has been retired; this case is not part of the active SimuFire validation corpus.
