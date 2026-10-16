# Determinismo del motor

Requisito: el motor debe dar **exactamente los mismos números** en cualquier
máquina, sistema operativo, hilo y build (editor o programa exportado).

## Qué lo rompía (medido el 2026-10-15)

- El Godot 4.7.1 oficial de Windows está compilado con MinGW. Sus `exp`, `pow`,
  `log`, `sin`, `cos` y `atan2` van dentro del ejecutable y usan la FPU x87,
  cuya precisión depende del hilo: en un hilo trabajador `exp` y `pow` dan otro
  último bit que en el principal (mingw-w64 lo documenta: los hilos nuevos
  arrancan con la x87 a 53 bits). `tanh` y `log10` vienen de la `msvcrt.dll`
  del sistema. Linux, Android, macOS e iOS usan otras bibliotecas matemáticas.
- El modelo amplifica una diferencia de un bit: con el escenario de la huella,
  hasta ~19 °C momentáneos en la capa caliente de la sala 1 hacia los 184 s y
  objetos combustibles que empiezan a pirolizar un paso antes o después. Un
  control con un bit de diferencia en el paso de tiempo da lo mismo: es la
  sensibilidad del modelo cerca de sus umbrales, no un defecto de los hilos.
- La aritmética básica (+ − × ÷) y `sqrt` siguen IEEE 754 y son iguales en
  cualquier procesador.

## Solución

`sim/core/DetMath.gd`: `exp`, `log`, `pow`, `sin`, `cos`, `tanh`, `lerpf` e
`inverse_lerp` escritas en GDScript con solo + − × ÷, `sqrt` y comparaciones
(algoritmos de fdlibm; `pow` en doble-doble). Todo `sim/` las llama como
`DetMath.<función>`. Sin compilar nada por plataforma: funciona igual donde
corra Godot.

- Precisión frente a precisión arbitraria (`tests/test_det_math.py`): `exp`,
  `log`, `sin`, `cos` < 0,76 ulp; `pow` ≤ 1,84 ulp; `tanh` ≤ 2,1 ulp.
- Mismos bits en el hilo principal y en un hilo trabajador (test y huella).
- `lerpf` e `inverse_lerp` repiten la fórmula de Godot: en x86-64 la huella no
  cambió al sustituirlas; protegen de la fusión FMA del compilador en ARM.
- Coste: ~+2 % en el paso del motor (8,73 → 8,93 ms de media, 10 min simulados).
- Guarda: `test_sim_routes_transcendental_math_through_detmath` falla si una
  línea de `sim/` vuelve a llamar a la función de Godot.

Cambiar `DetMath.gd` cambia los números del motor: regenerar la referencia y
la huella.

## Referencia regenerada (2026-10-15)

- Suite de referencia completa con DetMath: 346/346 obligatorias, ninguna de
  las 532 comprobaciones cambia de estado, 30 valores se mueven (mediana 0,05 %;
  la mayor obligatoria, el pico de Ghanekar, 536,7 → 540,7 °C; la mayor en
  total, un tiempo de FED no bloqueante, +5,5 %).
- Los 78 huecos conocidos mantienen su clasificación; su evidencia
  (`sim/validation/evidence/p1r8_gap_disposition_evidence.json`) se refrescó
  copiando del agregado solo valores y huellas de artefactos (11 valores nuevos).
- P1R7: mismos fallos esperados en los dos casos retirados; se refrescaron los
  hashes de sus informes.
- La huella de la ruta OFF del validador de transporte se re-fijó.
- Los registros de G3 que guardan bytes de `sim/` comparan ahora el código sin
  el enrutado (`scripts/simulation/detmath_routing.py`): el resultado es byte a
  byte el que juzgaron sus campañas, es decir, no cambió nada más.

## Huella

```powershell
python -X utf8 tools/determinism_fingerprint.py run --out <huella.json> --worker
python -X utf8 tools/determinism_fingerprint.py compare <a.json> <b.json>
```

Escenario fijo (`tools/determinism_fingerprint_options.json`), 7200 pasos de
1/12 s, SHA-256 del estado exportado cada 600 pasos, en el hilo principal y en
uno trabajador, más las huellas de DetMath (`det_*`, deben coincidir siempre) y
de las funciones de Godot (`godot_*`, solo información).

| Huella | Máquina | Estado |
|---|---|---|
| `fingerprint_laptop_ryzen7_5700U_2026-10-15.json` | Portátil, AMD Ryzen 7 5700U, Windows 11, editor 4.7.1 | Con DetMath |

## Pendiente

- Correr la huella en el sobremesa (otro AMD) y en el programa exportado
  (faltan las plantillas de exportación en el portátil).
- Móviles: comprobar en ARM que coincide. Riesgos conocidos sin medir: funciones
  vectoriales de Godot en `sim/` (`length`, `distance_to`, `dot`, en float32), la
  lectura de literales decimales por el analizador de GDScript y el tratamiento
  de subnormales. Para correr la huella allí hará falta un modo dentro del
  programa (los builds exportados no aceptan `--script`).
