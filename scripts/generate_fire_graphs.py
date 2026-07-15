"""
generate_fire_graphs.py
-----------------------
Lee sim_log.txt generado por SimulationLogWriter.gd y produce graficas
organizadas por habitacion. Se lanza automaticamente cuando la simulacion
termina (desde SimulationEngine._on_sim_finished()).

  graphs/
    YYYY-MM-DD_HH-MM-SS/
      ROOM_0_Salon/
        hrr.png           <- puntos de inflexion + eventos marcados
        temperaturas.png
        capas.png
        gases.png
        fed_svv.png
"""

import os
import re
import sys
import argparse
import shutil
import csv

_MPL_CACHE_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", ".matplotlib-cache")
)
os.makedirs(_MPL_CACHE_DIR, exist_ok=True)
os.environ.setdefault("MPLCONFIGDIR", _MPL_CACHE_DIR)

import matplotlib
matplotlib.use("Agg")  # Sin GUI, para no interferir con Godot
import matplotlib.pyplot as plt
from matplotlib.transforms import blended_transform_factory
from datetime import datetime

# -----------------------------------------------------------------------
# CONFIGURACION
# -----------------------------------------------------------------------
_project_log = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "sim_log.txt")
)
_godot_user_log = os.path.join(
    os.environ.get("APPDATA", ""),
    r"Godot\app_userdata\simufire\sim_log.txt"
)
_project_csv = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "sim_log.csv")
)
_godot_user_csv = os.path.join(
    os.environ.get("APPDATA", ""),
    r"Godot\app_userdata\simufire\sim_log.csv"
)

# Prioridad: log del proyecto (res://) siempre que exista y no este vacio;
# si no, se usa el de user:// como respaldo.
if os.path.exists(_project_log) and os.path.getsize(_project_log) > 0:
    LOG_PATH = _project_log
elif os.path.exists(_godot_user_log):
    LOG_PATH = _godot_user_log
else:
    LOG_PATH = _project_log

if os.path.exists(_project_csv) and os.path.getsize(_project_csv) > 0:
    CSV_PATH = _project_csv
elif os.path.exists(_godot_user_csv):
    CSV_PATH = _godot_user_csv
else:
    CSV_PATH = _project_csv

DEFAULT_GRAPHS_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "graphs")
)

# -----------------------------------------------------------------------
# ESTILOS DE EVENTOS
# -----------------------------------------------------------------------
EVENT_STYLES = {
    "glass_break":  ("#e74c3c", "Rotura cristal"),
    "door_open":    ("#27ae60", "Puerta abre"),
    "door_close":   ("#e67e22", "Puerta cierra"),
    "window_open":  ("#2980b9", "Ventana abre"),
    "window_close": ("#8e44ad", "Ventana cierra"),
    "sim_end":      ("#2c3e50", "Fin sim"),
}

# -----------------------------------------------------------------------
# PARSEO DEL LOG
# -----------------------------------------------------------------------

def parse_log(path):
    """
    Devuelve:
      - sim_time_label: string YYYY-MM-DD_HH-MM-SS (modificacion del archivo)
      - rooms:  dict  room_id -> { "name", "times", "hrr", ... }
      - events: list  [ {"t": float, "type": str, "details": dict}, ... ]
    """
    if not os.path.exists(path):
        raise FileNotFoundError("No se encontro el archivo de log: " + path)

    # Fecha/hora de modificacion del log
    mtime = os.path.getmtime(path)
    sim_time_label = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d_%H-%M-%S")

    rooms   = {}
    events  = []
    current_time = None

    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()

            # ------ Marca de tiempo ------
            m = re.match(r"^TIME=([0-9.]+)\s*s", line)
            if m:
                current_time = float(m.group(1))
                continue

            # ------ Evento ------
            if line.startswith("EVENT "):
                _parse_event_line(line, events)
                continue

            # ------ Linea de habitacion ------
            if not line.startswith("ROOM"):
                continue
            if current_time is None:
                continue

            parts = [p.strip() for p in line.split("|")]
            if len(parts) < 6:
                continue

            try:
                room_token = parts[0]
                room_raw = room_token.split(None, 1)[1] if " " in room_token else "?"
                # Formato puede ser "0" o "0(Salon)"
                m_name = re.match(r'^(\d+)\(([^)]+)\)$', room_raw.strip())
                if m_name:
                    room_id = int(m_name.group(1))
                    room_name = m_name.group(2)
                else:
                    try:
                        room_id = int(room_raw)
                        room_name = room_raw
                    except ValueError:
                        room_id = room_raw
                        room_name = room_raw

                def _val(s, prefix, strip_suffix=""):
                    idx = s.find(prefix + "=")
                    if idx == -1:
                        return 0.0
                    v = s[idx + len(prefix) + 1:]
                    if strip_suffix:
                        v = v.replace(strip_suffix, "")
                    m2 = re.match(r"[+-]?[0-9.]+", v.strip())
                    return float(m2.group()) if m2 else 0.0

                def _find_val(prefix, strip_suffix=""):
                    anchor = prefix + "="
                    for p in parts[1:]:
                        idx = p.find(anchor)
                        if idx == -1:
                            continue
                        before = p[idx - 1] if idx > 0 else " "
                        if before.isalpha():
                            continue
                        return _val(p, prefix, strip_suffix)
                    return 0.0

                hrr       = _find_val("HRR")
                temp_up   = _find_val("Up")
                temp_low  = _find_val("Low")
                smoke     = _find_val("Smoke")
                vis       = _find_val("Vis")
                smoke_lyr = _find_val("SmokeLayer")
                hot_lyr   = _find_val("HotLayer")
                l150      = _find_val("L150")
                press     = _find_val("P", "Pa")
                o2        = _find_val("O2")
                co        = _find_val("CO", "ppm")
                co_u      = _find_val("COu", "ppm")
                co2       = _find_val("CO2", "ppm")

                fed = 0.0
                svv = 0.0
                for part in parts[1:]:
                    mf = re.search(r"FED=([0-9.]+)", part)
                    ms = re.search(r"SVV=([0-9.]+)", part)
                    if mf:
                        fed = float(mf.group(1))
                    if ms:
                        svv = float(ms.group(1))

            except Exception:
                continue

            if room_id not in rooms:
                rooms[room_id] = {
                    "name": str(room_name),
                    "times": [], "hrr": [], "temp_up": [], "temp_low": [],
                    "smoke": [], "vis": [], "smoke_lyr": [], "hot_lyr": [], "l150": [],
                    "press": [], "o2": [], "co": [], "co_u": [], "co2": [],
                    "fed": [], "svv": [],
                }

            r = rooms[room_id]
            r["times"].append(current_time)
            r["hrr"].append(hrr)
            r["temp_up"].append(temp_up)
            r["temp_low"].append(temp_low)
            r["smoke"].append(smoke)
            r["vis"].append(vis)
            r["smoke_lyr"].append(smoke_lyr)
            r["hot_lyr"].append(hot_lyr)
            r["l150"].append(l150)
            r["press"].append(press)
            r["o2"].append(o2)
            r["co"].append(co)
            r["co_u"].append(co_u)
            r["co2"].append(co2)
            r["fed"].append(fed)
            r["svv"].append(svv)

    return sim_time_label, rooms, events


def _parse_event_line(line, events):
    """Parsea 'EVENT t=600.0 type=door_open opening=2 ...' y agrega a events."""
    mt = re.search(r"t=([0-9.]+)", line)
    mtype = re.search(r"type=(\S+)", line)
    if not mt or not mtype:
        return
    ev = {"t": float(mt.group(1)), "type": mtype.group(1), "details": {}}
    for key in ("opening", "room_a", "room_b", "frac", "kind"):
        mk = re.search(key + r"=([^\s]+)", line)
        if mk:
            val = mk.group(1)
            try:
                ev["details"][key] = int(val)
            except ValueError:
                try:
                    ev["details"][key] = float(val)
                except ValueError:
                    ev["details"][key] = val
    events.append(ev)


def _float(row, key, default=0.0):
    value = row.get(key, "")
    if value is None or value == "":
        return default
    try:
        return float(value)
    except ValueError:
        return default


def parse_csv_log(path):
    """
    Lee sim_log.csv. Es la fuente preferente para graficas porque contiene una
    fila por habitacion y tiempo, sin depender del formato humano del TXT.
    """
    if not os.path.exists(path):
        raise FileNotFoundError("No se encontro el archivo CSV: " + path)

    mtime = os.path.getmtime(path)
    sim_time_label = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d_%H-%M-%S")
    rooms = {}

    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            room_token = row.get("room_id", "")
            if room_token == "":
                continue
            try:
                room_id = int(room_token)
            except ValueError:
                room_id = room_token
            if room_id not in rooms:
                rooms[room_id] = {
                    "name": str(row.get("room_name", room_id)),
                    "times": [], "hrr": [], "temp_up": [], "temp_low": [],
                    "smoke": [], "vis": [], "smoke_lyr": [], "hot_lyr": [], "l150": [],
                    "press": [], "o2": [], "co": [], "co_u": [], "co2": [],
                    "fed": [], "svv": [],
                }
            r = rooms[room_id]
            r["times"].append(_float(row, "time_s"))
            r["hrr"].append(_float(row, "hrr_kw"))
            r["temp_up"].append(_float(row, "temp_upper_c"))
            r["temp_low"].append(_float(row, "temp_lower_c"))
            r["smoke"].append(_float(row, "smoke_kg"))
            r["vis"].append(_float(row, "visibility_m", 30.0))
            r["smoke_lyr"].append(_float(row, "smoke_layer_m"))
            r["hot_lyr"].append(_float(row, "hot_layer_m"))
            r["l150"].append(_float(row, "layer_150c_m"))
            r["press"].append(_float(row, "overpressure_pa"))
            r["o2"].append(_float(row, "o2"))
            r["co"].append(_float(row, "co_ppm"))
            r["co_u"].append(_float(row, "co_upper_ppm"))
            r["co2"].append(_float(row, "co2_ppm"))
            r["fed"].append(_float(row, "fed"))
            r["svv"].append(_float(row, "svv_worst_pct", 100.0))

    for room in rooms.values():
        _normalize_room_series(room)
    return sim_time_label, rooms


def _normalize_room_series(room):
    times = room.get("times", [])
    if not times:
        return
    keys = [k for k in room.keys() if isinstance(room.get(k), list) and k != "times"]
    order = sorted(range(len(times)), key=lambda i: times[i])
    dedup = {}
    for i in order:
        dedup[float(times[i])] = i
    sorted_times = sorted(dedup.keys())
    new_values = {"times": sorted_times}
    for key in keys:
        values = room.get(key, [])
        new_values[key] = [values[dedup[t]] if dedup[t] < len(values) else 0.0 for t in sorted_times]
    if sorted_times and sorted_times[0] > 0.001:
        new_values["times"].insert(0, 0.0)
        for key in keys:
            first = new_values[key][0] if new_values[key] else 0.0
            new_values[key].insert(0, first)
    room.update(new_values)


# -----------------------------------------------------------------------
# DETECCION DE PUNTOS DE INFLEXION
# -----------------------------------------------------------------------

def find_inflections(times, values, window_frac=0.05, min_pct=10.0, min_gap_s=40.0):
    """
    Devuelve lista de (time, value) donde la curva cambia mas bruscamente.
    window_frac : fraccion del total de muestras usada como ventana de calculo
    min_pct     : cambio minimo como % del rango total de la serie
    min_gap_s   : separacion minima en segundos entre dos inflexiones anotadas
    """
    n = len(times)
    if n < 7:
        return []
    v_range = max(values) - min(values)
    if v_range < 1e-6:
        return []
    threshold = v_range * min_pct / 100.0
    w = max(1, int(n * window_frac))

    # Cambio absoluto en ventana 2*w centrada en cada punto
    changes = []
    for i in range(w, n - w):
        changes.append(abs(values[i + w] - values[i - w]))

    # Maximos locales que superen el umbral
    results = []
    last_t = times[0] - min_gap_s
    for i in range(1, len(changes) - 1):
        if changes[i] < threshold:
            continue
        if changes[i] >= changes[i - 1] and changes[i] >= changes[i + 1]:
            idx = i + w  # indice en times/values
            ti, vi = times[idx], values[idx]
            if ti - last_t >= min_gap_s:
                results.append((ti, vi))
                last_t = ti
    return results


# -----------------------------------------------------------------------
# ANOTACION DE EVENTOS E INFLEXIONES
# -----------------------------------------------------------------------

def _annotate_events(axes_list, events, xlim):
    """
    Dibuja lineas verticales de evento en todos los ejes.
    El texto del evento va en el eje superior, pegado al margen derecho
    de la linea, rotado 90 grados.
    """
    x_span = xlim[1] - xlim[0]
    for ev in events:
        et = ev["t"]
        if et < xlim[0] or et > xlim[1]:
            continue
        estyle = EVENT_STYLES.get(ev["type"], ("#888888", ev["type"]))
        color, label = estyle
        details = ev.get("details", {})
        op_id  = details.get("opening", "")
        room_a = details.get("room_a", "")
        room_b = details.get("room_b", "")
        if op_id != "":
            full_label = "%s\n(op%s: %s<->%s)" % (label, op_id, room_a, room_b)
        else:
            full_label = label

        for ax_idx, ax in enumerate(axes_list):
            ax.axvline(et, color=color, alpha=0.40, linewidth=1.1,
                       linestyle="--", zorder=2)
            # Texto solo en el eje superior (idx==0)
            if ax_idx == 0:
                trans = blended_transform_factory(ax.transData, ax.transAxes)
                ax.text(et + x_span * 0.004, 0.97, full_label,
                        transform=trans, ha="left", va="top",
                        fontsize=6, color=color, rotation=90,
                        linespacing=1.2, clip_on=False, zorder=3)


def _annotate_inflections(ax, inflections, fmt_fn=None):
    """
    Pone una marca discreta en la base del eje (eje X) en cada punto de
    inflexion: linea gris sutil + etiqueta con tiempo y valor rotada 45 grados.
    """
    if not inflections:
        return
    trans = blended_transform_factory(ax.transData, ax.transAxes)
    for ti, vi in inflections:
        ax.axvline(ti, color="#bbbbbb", alpha=0.45, linewidth=0.8, zorder=1)
        val_str = fmt_fn(vi) if fmt_fn else ""
        label = ("t=%ds\n%s" % (int(round(ti)), val_str)) if val_str else ("t=%ds" % int(round(ti)))
        ax.text(ti, -0.02, label,
                transform=trans, ha="center", va="top",
                fontsize=6.5, color="#555555", rotation=45, clip_on=False)


# -----------------------------------------------------------------------
# GENERACION DE GRAFICAS
# -----------------------------------------------------------------------

def _save(fig, path):
    fig.tight_layout(pad=1.35)
    fig.savefig(path, dpi=120, bbox_inches="tight", pad_inches=0.24)
    plt.close(fig)


def plot_room(room_id, r, room_dir, events=None):
    t = r["times"]
    if not t:
        print("  ROOM %s: sin datos, se omite." % room_id)
        return

    events = events or []
    t_end = max(t) if max(t) > 0 else 1.0
    xlim = (0, t_end)
    name = r["name"]

    # --- HRR ---
    fig, ax = plt.subplots(figsize=(9, 4))
    ax.plot(t, r["hrr"], color="tomato", linewidth=1.5)
    inflx_hrr = find_inflections(t, r["hrr"], min_pct=8.0)
    _annotate_inflections(ax, inflx_hrr, fmt_fn=lambda v: "%.0fkW" % v)
    _annotate_events([ax], events, xlim)
    ax.set_title("HRR -- ROOM %s %s" % (room_id, name))
    ax.set_xlabel("Tiempo (s)")
    ax.set_ylabel("HRR (kW)")
    ax.set_xlim(*xlim)
    ax.set_ylim(bottom=0)
    ax.grid(True, alpha=0.3)
    _save(fig, os.path.join(room_dir, "hrr.png"))

    # --- Temperaturas ---
    fig, ax = plt.subplots(figsize=(9, 4))
    ax.plot(t, r["temp_up"],  label="Capa alta (C)", color="orangered", linewidth=1.5)
    ax.plot(t, r["temp_low"], label="Capa baja (C)", color="steelblue", linewidth=1.5)
    inflx_temp = find_inflections(t, r["temp_up"], min_pct=8.0)
    _annotate_inflections(ax, inflx_temp, fmt_fn=lambda v: "%.0fC" % v)
    _annotate_events([ax], events, xlim)
    ax.set_title("Temperaturas -- ROOM %s %s" % (room_id, name))
    ax.set_xlabel("Tiempo (s)")
    ax.set_ylabel("Temperatura (C)")
    ax.set_xlim(*xlim)
    ax.legend(fontsize=8)
    ax.grid(True, alpha=0.3)
    _save(fig, os.path.join(room_dir, "temperaturas.png"))

    # --- Capas ---
    fig, ax = plt.subplots(figsize=(9, 4))
    ax.plot(t, r["smoke_lyr"], label="Capa humo (m)",      color="dimgray",    linewidth=1.5)
    ax.plot(t, r["hot_lyr"],   label="Capa caliente (m)",  color="darkorange", linewidth=1.5, linestyle="--")
    ax.plot(t, r["l150"],      label="Isoterma 150C (m)",  color="firebrick",  linewidth=1.5, linestyle=":")
    # Parametros mas selectivos: la capa de humo tiene variacion gradual → exigir cambios grandes
    inflx_smoke = find_inflections(t, r["smoke_lyr"], window_frac=0.08, min_pct=18.0, min_gap_s=150.0)
    _annotate_inflections(ax, inflx_smoke, fmt_fn=lambda v: "%.2fm" % v)
    _annotate_events([ax], events, xlim)
    ax.set_title("Capas -- ROOM %s %s" % (room_id, name))
    ax.set_xlabel("Tiempo (s)")
    ax.set_ylabel("Altura (m)")
    ax.set_xlim(*xlim)
    ax.set_ylim(bottom=0)
    ax.legend(fontsize=8)
    ax.grid(True, alpha=0.3)
    _save(fig, os.path.join(room_dir, "capas.png"))

    # --- Gases ---
    fig, axes = plt.subplots(3, 1, figsize=(9, 9), sharex=True)

    axes[0].plot(t, [v * 100 for v in r["o2"]], color="dodgerblue", linewidth=1.5)
    axes[0].set_ylabel("O2 (%)")
    axes[0].set_ylim(0, 22)
    axes[0].axhline(17.0, color="red", linestyle="--", alpha=0.5, label="Limite 17%")
    axes[0].legend(fontsize=8)
    axes[0].grid(True, alpha=0.3)

    axes[1].plot(t, r["co"],   label="CO total (ppm)",     color="saddlebrown", linewidth=1.5)
    axes[1].plot(t, r["co_u"], label="CO upper zone (ppm)", color="peru",        linewidth=1.5, linestyle="--")
    axes[1].set_ylabel("CO (ppm)")
    axes[1].set_ylim(bottom=0)
    axes[1].axhline(1500, color="red", linestyle="--", alpha=0.5, label="1500 ppm")
    axes[1].legend(fontsize=8)
    axes[1].grid(True, alpha=0.3)

    axes[2].plot(t, r["co2"], color="seagreen", linewidth=1.5)
    axes[2].set_ylabel("CO2 (ppm)")
    axes[2].set_ylim(bottom=0)
    axes[2].set_xlabel("Tiempo (s)")
    axes[2].grid(True, alpha=0.3)
    # Inflexiones solo en CO2 (la mas dinamica)
    inflx_co2 = find_inflections(t, r["co2"], min_pct=10.0)
    _annotate_inflections(axes[2], inflx_co2, fmt_fn=lambda v: "%.0fppm" % v)

    # Eventos en los 3 paneles (label solo en el superior)
    _annotate_events(list(axes), events, xlim)

    fig.suptitle("Gases -- ROOM %s %s" % (room_id, name))
    axes[0].set_xlim(*xlim)
    _save(fig, os.path.join(room_dir, "gases.png"))

    # --- FED / SVV ---
    fig, ax1 = plt.subplots(figsize=(9, 4))
    c_fed = "firebrick"
    fed_vals = r["fed"]
    fed_display_max = max(5.0, min(10.0, max(fed_vals) * 1.1)) if fed_vals else 5.0
    ax1.plot(t, fed_vals, color=c_fed, linewidth=1.5, label="FED")
    ax1.axhline(1.0, color=c_fed, linestyle="--", alpha=0.5, label="FED=1 (incap.)")
    ax1.axhline(3.0, color="darkred", linestyle=":", alpha=0.4, label="FED=3 (letal)")
    fed_max_val = max(fed_vals) if fed_vals else 0.0
    if fed_max_val > fed_display_max:
        ax1.text(0.98, 0.97, "max FED=%.1f" % fed_max_val,
                 transform=ax1.transAxes, ha="right", va="top",
                 fontsize=8, color=c_fed)
    inflx_fed = find_inflections(t, fed_vals, min_pct=8.0)
    _annotate_inflections(ax1, inflx_fed, fmt_fn=lambda v: "%.2f" % v)
    ax1.set_xlabel("Tiempo (s)")
    ax1.set_ylabel("FED", color=c_fed)
    ax1.tick_params(axis="y", labelcolor=c_fed)
    ax1.set_xlim(*xlim)
    ax1.set_ylim(0, fed_display_max)

    ax2 = ax1.twinx()
    c_svv = "steelblue"
    ax2.plot(t, r["svv"], color=c_svv, linewidth=1.5, label="SVV (%)")
    # Visibilidad escalada a 0-100% (30 m = 100%) para mostrar por qué SVV baja
    # antes de que FED acumule: la sala se llena de humo más rápido que la dosis.
    vis_raw = r.get("vis", [])
    if vis_raw:
        vis_pct = [min(v / 30.0, 1.0) * 100.0 for v in vis_raw]
        ax2.plot(t, vis_pct, color="mediumseagreen", linewidth=1.0,
                 linestyle=":", alpha=0.75, label="Vis (% de 30m)")
    ax2.set_ylabel("SVV / Vis (%)", color=c_svv)
    ax2.tick_params(axis="y", labelcolor=c_svv)
    ax2.set_ylim(0, 105)

    _annotate_events([ax1], events, xlim)

    lines1, labels1 = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, labels1 + labels2, fontsize=8)
    fig.suptitle("FED / SVV -- ROOM %s %s\n(SVV=0 antes de FED=1 → humo reduce visibilidad antes de incapacitar)" % (room_id, name))
    ax1.grid(True, alpha=0.3)
    _save(fig, os.path.join(room_dir, "fed_svv.png"))

    print("  ROOM %s (%s): %d muestras, %d eventos -> %s" % (
        room_id, name, len(t), len(events), os.path.basename(room_dir)))


# -----------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------

def _parse_args():
    parser = argparse.ArgumentParser(description="Genera graficas de SimuFire desde sim_log.txt")
    parser.add_argument("--log", default=LOG_PATH, help="Ruta del log de simulacion")
    parser.add_argument("--csv", default=CSV_PATH, help="Ruta del CSV de simulacion")
    parser.add_argument("--out-root", default=DEFAULT_GRAPHS_ROOT, help="Carpeta donde crear la subcarpeta de graficas")
    parser.add_argument("--latest-file", default="", help="Archivo donde escribir la carpeta final generada")
    parser.add_argument("--copy-log", action="store_true", help="Copia el log usado dentro de la carpeta final")
    parser.add_argument("--copy-csv", action="store_true", help="Copia el CSV usado dentro de la carpeta final")
    return parser.parse_args()


def main():
    args = _parse_args()
    log_path = os.path.abspath(args.log)
    csv_path = os.path.abspath(args.csv)
    graphs_root = os.path.abspath(args.out_root)

    sim_label = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")

    events = []
    if os.path.exists(log_path) and os.path.getsize(log_path) > 0:
        try:
            _, _, events = parse_log(log_path)
        except Exception as exc:
            print("Aviso: no se pudieron leer eventos del log TXT: %s" % exc)

    csv_usable = os.path.exists(csv_path) and os.path.getsize(csv_path) > 0
    if csv_usable and os.path.exists(log_path) and os.path.getsize(log_path) > 0:
        csv_mtime = os.path.getmtime(csv_path)
        log_mtime = os.path.getmtime(log_path)
        if csv_mtime < log_mtime - 5:
            print("Aviso: CSV (%s) es mas viejo que el log TXT — usando TXT." % csv_path)
            csv_usable = False

    if csv_usable:
        print("Leyendo CSV: " + csv_path)
        _, rooms = parse_csv_log(csv_path)
    else:
        print("Leyendo log: " + log_path)
        _, rooms, events = parse_log(log_path)

    if not rooms:
        print("El log no contiene datos de habitaciones. Corre la simulacion primero.")
        return 1

    out_root = os.path.join(graphs_root, sim_label)
    os.makedirs(out_root, exist_ok=True)
    print("Carpeta de salida: " + out_root)
    print("Habitaciones: %s  |  Eventos: %d\n" % (
        sorted(str(k) for k in rooms.keys()), len(events)))

    for room_id in sorted(rooms.keys(), key=lambda x: str(x)):
        r = rooms[room_id]
        safe_name = re.sub(r"[^A-Za-z0-9_-]", "_", str(r["name"]))
        room_dir = os.path.join(out_root, "ROOM_%s_%s" % (room_id, safe_name))
        os.makedirs(room_dir, exist_ok=True)
        plot_room(room_id, r, room_dir, events=events)

    if args.copy_log:
        try:
            shutil.copy2(log_path, os.path.join(out_root, "sim_log.txt"))
        except OSError as exc:
            print("Aviso: no se pudo copiar el log: %s" % exc)

    if args.copy_csv:
        if os.path.exists(csv_path) and os.path.getsize(csv_path) > 0:
            try:
                shutil.copy2(csv_path, os.path.join(out_root, "sim_log.csv"))
            except OSError as exc:
                print("Aviso: no se pudo copiar el CSV: %s" % exc)
        else:
            print("Aviso: no se encontro CSV para copiar: %s" % csv_path)

    if args.latest_file:
        latest_path = os.path.abspath(args.latest_file)
        latest_dir = os.path.dirname(latest_path)
        if latest_dir:
            os.makedirs(latest_dir, exist_ok=True)
        with open(latest_path, "w", encoding="utf-8") as f:
            f.write(out_root)

    print("\nListo. Graficas en:\n  " + out_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
