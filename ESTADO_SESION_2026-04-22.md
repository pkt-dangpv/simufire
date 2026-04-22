# Simufire — Estado de sesion
**Ultima actualizacion**: 22 abril 2026

## Resumen ejecutivo
Sesion centrada en dos bloques:
1. **Calibración científica** del motor contra literatura publicada (ISO 13571, ISO 19706, SFPE Handbook, NIST CFAST, FSRI).
2. **Automatización de gráficas**: el juego genera las gráficas solo al pararse, con eventos marcados y puntos de inflexión anotados.

Todas las implementaciones anteriores (sesiones 15-21 abril) siguen activas.

---

## Cambios de esta sesion

### 1. Corrección parámetros de calibración en `sim/core/SimulationEngine.gd`

#### L150 relax_down — bug de discretización dt=10s
| Parámetro | Antes | Después | Motivo |
|---|---|---|---|
| `layer_150c_relax_down_per_s` | 0.35 | **0.05** | Con dt=10s: lerp=3.5 → clamp 1.0 → descenso instantáneo. Ahora lerp=0.50 (suave) |
| `layer_150c_relax_up_per_s`  | 0.03 | **0.01** | Subida aún más gradual para simetría física |

#### Yields CO2 — alineación ISO 19706 (madera)
| Parámetro | Antes | Después | Fuente |
|---|---|---|---|
| `co2_base_yield_kg_per_MJ` | 0.1000 | **0.0831** | ISO 19706: 1.33 kg/kg ÷ 16 MJ/kg (bien ventilado) |
| `co2_min_yield_kg_per_MJ` | 0.0715 | **0.0594** | ISO 19706: 0.95 kg/kg ÷ 16 MJ/kg (déficit O2) |

Efecto esperado: CO2 máximo baja de ~15% a ~10-12%, FED se reduce de valores >600 a rango realista.

### 2. Corrección etiquetas CO en `scripts/generate_fire_graphs.py`
- `"CO lower"` → `"CO total (ppm)"` (campo CO = CO total del cuarto)
- `"CO upper"` → `"CO upper zone (ppm)"` (campo COu = CO en capa superior)

### 3. Escala FED práctica en gráficas
- Eje Y limitado a 5–10 unidades (el mínimo útil visible), no 0–625
- Línea de referencia `FED=3 (letal)` añadida (además de `FED=1 incapacitación`)
- Si el FED máximo supera la escala, se anota el valor real en la esquina

### 4. Sistema de registro automático de eventos
**Nuevo método en `sim/core/SimulationLogWriter.gd`:**
```gdscript
func append_event(sim_time_s: float, event_type: String, details: String) -> void
```
Escribe líneas inmediatas al log con formato:
```
EVENT t=1015.7 type=door_open opening=5 kind=door room_a=1 room_b=-1 frac=1.00
```

**`sim/core/GlassFailureSystem.gd`** — nuevo array `newly_broken_indices`:
- Se limpia al inicio de cada `step()`
- Almacena índices de ventanas que se rompen por primera vez este step

**`sim/core/SimulationEngine.gd`** — detección de eventos en cada step:
- `glass_break`: detectado en `step()` via `glass_failure_system.newly_broken_indices`
- `door_open / door_close`: comparando `open_fraction` anterior vs actual (umbral 5%)
- `window_open / window_close`: igual que puertas
- Estado prev guardado en `_prev_open_fracs: Dictionary`

Tipos de evento registrados:
| Tipo | Color en gráfica | Descripción |
|---|---|---|
| `glass_break` | Rojo | Rotura automática de cristal por temperatura |
| `door_open` | Verde | Usuario/simulación abre puerta |
| `door_close` | Naranja | Usuario/simulación cierra puerta |
| `window_open` | Azul | Usuario/simulación abre ventana |
| `window_close` | Violeta | Usuario/simulación cierra ventana |
| `sim_end` | Gris oscuro | Fin de simulación (natural o forzado) |

### 5. Generación automática de gráficas al parar el juego
**`sim/core/SimulationEngine.gd`** — dos nuevos métodos:

```gdscript
func _on_sim_finished() -> void   # fuego extinguido naturalmente
func _exit_tree() -> void         # usuario pulsa Stop o cierra ventana
```

`_exit_tree()` es el hook principal: Godot lo llama siempre que el juego se detiene.
Lanza Python con `cmd.exe /c python <ruta_script>` (necesario en Windows para encontrar Python en el PATH del sistema). Solo se ejecuta una vez por simulación gracias a `_graphs_launched: bool`.

### 6. Gráficas con anotaciones automáticas en `scripts/generate_fire_graphs.py`

#### Puntos de inflexión
Función `find_inflections(times, values, window_frac, min_pct, min_gap_s)`:
- Calcula cambio absoluto en ventana deslizante de `window_frac * N` puntos
- Devuelve máximos locales que superen `min_pct` del rango total
- Garantiza separación mínima de `min_gap_s` segundos entre anotaciones
- Cada inflexión: línea vertical gris sutil + etiqueta `t=Xs / valor` a 45°

#### Eventos en gráficas
Función `_annotate_events(axes_list, events, xlim)`:
- Línea vertical semitransparente del color del tipo de evento
- Etiqueta rotada 90° en el eje superior con nombre del evento + apertura + salas
- Visible en todos los paneles de una gráfica multi-panel

#### Parseo de eventos en el log
Función `_parse_event_line(line, events)`:
- Parsea líneas `EVENT t=... type=... opening=... room_a=... room_b=... frac=...`
- Los campos numéricos se convierten automáticamente (int/float)

#### Firma actualizada
`plot_room(room_id, r, room_dir, events=None)` — acepta la lista de eventos global.
`parse_log(path)` — devuelve tres valores: `(sim_time_label, rooms, events)`

---

## Estado de los ficheros clave

| Fichero | Estado |
|---|---|
| `sim/core/SimulationEngine.gd` | ✅ Calibración + eventos + _exit_tree + _launch_graph_generator |
| `sim/core/SimulationLogWriter.gd` | ✅ append_event() añadido |
| `sim/core/GlassFailureSystem.gd` | ✅ newly_broken_indices añadido |
| `sim/core/ThermalSystem.gd` | Sin cambios hoy |
| `sim/core/GasExchangeSystem.gd` | Sin cambios hoy (fix anterior de max_allowed activo) |
| `sim/smoke/SmokeModel.gd` | Sin cambios hoy (fix anterior de layer_relax_down activo) |
| `scripts/generate_fire_graphs.py` | ✅ Eventos + inflexiones + escala FED + etiquetas CO |
| `sim/templates/BuildingTemplate.gd` | Sin cambios hoy (puerta principal starts closed activo) |

---

## Verificación con log de simulación (22 abril, t=3100s)

### Eventos detectados
```
EVENT t=1015.7 type=door_open  opening=5 room_a=1 room_b=-1 frac=1.00
EVENT t=2093.4 type=window_open opening=6 room_a=0 room_b=-1 frac=1.00
EVENT t=2836.5 type=door_close opening=5 room_a=1 room_b=-1 frac=0.00
```

### Observaciones del log (problemas pendientes de calibración)
- **FED sigue muy alto**: ROOM 0 FED=59.6 a t=3100s. Reducción de CO2 yield ayudará en
  próxima simulación, pero el modelo de eliminación de CO2 por ACH es muy lento
  (CO2 acumulándose a 8-12% en cuartos sin ventilación exterior).
- **HRR mantenido**: ROOM 2 y ROOM 3 muestran 150-200 kW a t=3100s con O2~5%.
  Fuegos limitados por ventilación pero sin extinguirse — comportamiento razonable.
- **Pasillo (ROOM 1)**: Up=545°C, Low=399°C — temperaturas muy altas para pasillo.
  Posible problema de transmisión de calor excesiva por puertas abiertas.

---

## Tareas pendientes (próximas sesiones)

### Alta prioridad
- [ ] **Correr nueva simulación** con los parámetros calibrados (CO2 yield 0.0831/0.0594,
      L150 relax 0.05/0.01) y comparar gráficas con las del 22 abril.
- [ ] **CO2 acumulación excesiva**: el modelo de purga por ACH (`ach_infiltration=0.70`)
      elimina ~0.000194/s × co2_kg. A 100 kW estacionario con ventanas cerradas,
      CO2 converge a ~50 kg (>50%) — físicamente imposible. Investigar:
      - ¿Se está aplicando correctamente `ach_infiltration` en `GasExchangeSystem`?
      - Posible que falte el flujo de salida por aperturas para gases al exterior.

### Media prioridad
- [ ] **Temperatura pasillo excesiva**: ROOM 1 (pasillo) a 545°C — probable que la
      transmisión de calor desde ROOM 2/3 (dormitorios con fuegos activos) por las
      puertas abiertas sea demasiado directa. Revisar `ThermalSystem.step_inter_room_heat`.
- [ ] **Añadir FED_HCN**: brecha conocida vs ISO 13571. En materiales poliuretano
      aporta ~20-30% adicional al FED. No crítico para madera, sí para muebles modernos.
- [ ] **Flashover en ROOM 2/3**: Upper=840°C / 780°C con todo el combustible disponible.
      Verificar si flashover_triggered se registra correctamente en el log.

### Baja prioridad
- [ ] **Nomenclatura de aperturas en HUD**: los índices (0, 5, 6...) son confusos.
      Considerar etiquetar con "Puerta Salon-Pasillo", "Ventana Salon", etc.
- [ ] **sim_log.txt crece sin límite**: una simulación de 3100s genera ~2500 líneas.
      Considerar rotación o límite de tamaño.

---

## Comandos útiles

```powershell
# Regenerar gráficas manualmente con el log existente
cd "f:\OneDrive\Documentos\GitHub\simufire"
python scripts/generate_fire_graphs.py

# Ver eventos en el log
Select-String "^EVENT" sim_log.txt

# Ver último snapshot
Get-Content sim_log.txt -Tail 30
```

---

## Contexto técnico de referencia

### Parámetros de calibración actuales (SimulationEngine.gd)
```gdscript
layer_150c_relax_down_per_s = 0.05   # lerp=0.50 con dt=10s
layer_150c_relax_up_per_s   = 0.01   # lerp=0.10 con dt=10s
co2_base_yield_kg_per_MJ    = 0.0831 # ISO 19706 madera ventilada
co2_min_yield_kg_per_MJ     = 0.0594 # ISO 19706 madera déficit O2
ach_infiltration             = 0.70   # residencial típico
glass_auto_break_enabled     = false  # manual por defecto
time_scale                   = 5.0   # 5x tiempo real
extinction_grace_s           = 30.0
```

### Formato de líneas del log
```
TIME=1015.0 s
ROOM 0(Salon) | HRR=... | Up=... | Low=... | Smoke=... | SmokeLayer=... |
  HotLayer=... | L150=... | P=...Pa | O2=... | CO=...ppm | COu=...ppm |
  CO2=...ppm | FED=... | SVV=...% [ZONA] | FuelH=... | FuelP=... | ...
EVENT t=1015.7 type=door_open opening=5 kind=door room_a=1 room_b=-1 frac=1.00
```

### Estructura de carpetas de gráficas
```
graphs/
  YYYY-MM-DD_HH-MM-SS/     <- timestamp de modificación del sim_log.txt
    ROOM_0_Salon/
      hrr.png              <- inflexiones + eventos
      temperaturas.png
      capas.png
      gases.png            <- 3 paneles: O2, CO, CO2
      fed_svv.png          <- FED escala 0-5, líneas FED=1 y FED=3
    ROOM_1_Pasillo/
      ...
```
