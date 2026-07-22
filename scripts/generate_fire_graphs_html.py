"""
generate_fire_graphs_html.py
----------------------------
Exportador INTERACTIVO (Plotly) paralelo a generate_fire_graphs.py.

Lee el mismo sim_log.csv / sim_log.txt y produce UN SOLO dashboard.html
autocontenido por ejecucion, con:
  - selector de habitacion (dropdown)
  - zoom / pan / hover unificado con valores exactos
  - series activables desde la leyenda
  - lineas verticales de evento (rotura cristal, puertas, ventanas...)
  - marcadores de puntos de inflexion

NO reemplaza al generador matplotlib: reutiliza su parsing (parse_csv_log,
parse_log, find_inflections, EVENT_STYLES) importandolo como modulo, y expone
la MISMA interfaz de argumentos, para poder engancharlo desde Godot igual que
el otro si se decide adoptarlo.

Salida:
  graphs/
    YYYY-MM-DD_HH-MM-SS/
      dashboard.html        <- un archivo, todas las habitaciones

Uso:
  python scripts/generate_fire_graphs_html.py
  python scripts/generate_fire_graphs_html.py --csv ruta.csv --out-root graphs
"""

import os
import re
import sys
import argparse
import shutil
from datetime import datetime

# Reutilizamos TODO el parsing del generador matplotlib (mismo directorio).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_fire_graphs as gfg  # noqa: E402

import plotly.graph_objects as go  # noqa: E402
from plotly.subplots import make_subplots  # noqa: E402


# -----------------------------------------------------------------------
# LAYOUT DE FILAS DEL DASHBOARD (una por metrica)
# -----------------------------------------------------------------------
ROW_TITLES = [
    "HRR (kW)",
    "Temperaturas (C)",
    "Capas / alturas (m)",
    "O2 (%)",
    "CO (ppm)",
    "CO2 (ppm)",
    "FED  /  SVV-Vis (%)",
]
N_ROWS = len(ROW_TITLES)
FED_SVV_ROW = 7  # fila con eje Y secundario


def _room_traces(fig, r, visible):
    """
    Anade al fig todas las trazas de UNA habitacion y devuelve cuantas anadio.
    visible=True solo para la habitacion mostrada por defecto.
    """
    t = r["times"]
    added = 0

    def add(trace, row, secondary=False):
        nonlocal added
        trace.visible = True if visible else "legendonly" if False else visible
        fig.add_trace(trace, row=row, col=1, secondary_y=secondary)
        added += 1

    # --- fila 1: HRR ---
    add(go.Scatter(x=t, y=r["hrr"], name="HRR", legendgroup="hrr",
                   line=dict(color="tomato", width=1.6),
                   hovertemplate="t=%{x:.0f}s<br>HRR=%{y:.0f} kW<extra></extra>"), 1)

    # --- fila 2: Temperaturas ---
    add(go.Scatter(x=t, y=r["temp_up"], name="Capa alta", legendgroup="tup",
                   line=dict(color="orangered", width=1.6),
                   hovertemplate="t=%{x:.0f}s<br>T alta=%{y:.0f} C<extra></extra>"), 2)
    add(go.Scatter(x=t, y=r["temp_low"], name="Capa baja", legendgroup="tlow",
                   line=dict(color="steelblue", width=1.6),
                   hovertemplate="t=%{x:.0f}s<br>T baja=%{y:.0f} C<extra></extra>"), 2)

    # --- fila 3: Capas ---
    add(go.Scatter(x=t, y=r["smoke_lyr"], name="Capa humo", legendgroup="smk",
                   line=dict(color="dimgray", width=1.6),
                   hovertemplate="t=%{x:.0f}s<br>humo=%{y:.2f} m<extra></extra>"), 3)
    add(go.Scatter(x=t, y=r["hot_lyr"], name="Capa caliente", legendgroup="hot",
                   line=dict(color="darkorange", width=1.6),
                   hovertemplate="t=%{x:.0f}s<br>caliente=%{y:.2f} m<extra></extra>"), 3)
    add(go.Scatter(x=t, y=r["l150"], name="Isoterma 150C", legendgroup="l150",
                   line=dict(color="firebrick", width=1.6),
                   hovertemplate="t=%{x:.0f}s<br>150C=%{y:.2f} m<extra></extra>"), 3)

    # --- fila 4: O2 (%) ---
    add(go.Scatter(x=t, y=[v * 100 for v in r["o2"]], name="O2", legendgroup="o2",
                   line=dict(color="dodgerblue", width=1.6),
                   hovertemplate="t=%{x:.0f}s<br>O2=%{y:.1f} %<extra></extra>"), 4)

    # --- fila 5: CO ---
    add(go.Scatter(x=t, y=r["co"], name="CO total", legendgroup="co",
                   line=dict(color="saddlebrown", width=1.6),
                   hovertemplate="t=%{x:.0f}s<br>CO=%{y:.0f} ppm<extra></extra>"), 5)
    add(go.Scatter(x=t, y=r["co_u"], name="CO upper", legendgroup="cou",
                   line=dict(color="peru", width=1.6),
                   hovertemplate="t=%{x:.0f}s<br>CO upper=%{y:.0f} ppm<extra></extra>"), 5)

    # --- fila 6: CO2 ---
    add(go.Scatter(x=t, y=r["co2"], name="CO2", legendgroup="co2",
                   line=dict(color="seagreen", width=1.6),
                   hovertemplate="t=%{x:.0f}s<br>CO2=%{y:.0f} ppm<extra></extra>"), 6)

    # --- fila 7: FED (primario) + SVV/Vis (secundario) ---
    add(go.Scatter(x=t, y=r["fed"], name="FED", legendgroup="fed",
                   line=dict(color="firebrick", width=1.8),
                   hovertemplate="t=%{x:.0f}s<br>FED=%{y:.2f}<extra></extra>"), FED_SVV_ROW)
    add(go.Scatter(x=t, y=r["svv"], name="SVV (%)", legendgroup="svv",
                   line=dict(color="steelblue", width=1.6),
                   hovertemplate="t=%{x:.0f}s<br>SVV=%{y:.0f} %<extra></extra>"),
        FED_SVV_ROW, secondary=True)
    vis_raw = r.get("vis", [])
    if vis_raw:
        vis_pct = [min(v / 30.0, 1.0) * 100.0 for v in vis_raw]
        add(go.Scatter(x=t, y=vis_pct, name="Vis (% de 30m)", legendgroup="vis",
                       line=dict(color="mediumseagreen", width=1.4),
                       hovertemplate="t=%{x:.0f}s<br>Vis=%{y:.0f} %<extra></extra>"),
            FED_SVV_ROW, secondary=True)

    return added


def _add_thresholds(fig):
    """Lineas de referencia (limites) que aplican a todas las habitaciones."""
    fig.add_hline(y=17.0, row=4, col=1, line=dict(color="red", dash="dash", width=1),
                  opacity=0.5, annotation_text="17% O2", annotation_position="top left",
                  annotation_font_size=9)
    fig.add_hline(y=1500, row=5, col=1, line=dict(color="red", dash="dash", width=1),
                  opacity=0.5, annotation_text="1500 ppm", annotation_position="top left",
                  annotation_font_size=9)
    fig.add_hline(y=1.0, row=FED_SVV_ROW, col=1, secondary_y=False,
                  line=dict(color="firebrick", dash="dash", width=1), opacity=0.5,
                  annotation_text="FED=1 incap.", annotation_position="top left",
                  annotation_font_size=9)
    fig.add_hline(y=3.0, row=FED_SVV_ROW, col=1, secondary_y=False,
                  line=dict(color="darkred", dash="dot", width=1), opacity=0.4,
                  annotation_text="FED=3 letal", annotation_position="bottom left",
                  annotation_font_size=9)


def _add_events(fig, events, t_end):
    """Lineas verticales de evento en todas las filas + etiqueta en la superior."""
    for ev in events:
        et = ev["t"]
        if et < 0 or et > t_end:
            continue
        color, label = gfg.EVENT_STYLES.get(ev["type"], ("#888888", ev["type"]))
        details = ev.get("details", {})
        op_id = details.get("opening", "")
        room_a = details.get("room_a", "")
        room_b = details.get("room_b", "")
        full = "%s (op%s: %s<->%s)" % (label, op_id, room_a, room_b) if op_id != "" else label
        fig.add_vline(x=et, row="all", col=1,
                      line=dict(color=color, width=1.1, dash="dash"), opacity=0.4)
        fig.add_annotation(x=et, y=1.0, xref="x", yref="paper",
                           text=full, textangle=-90, showarrow=False,
                           xanchor="left", yanchor="top",
                           font=dict(size=9, color=color))


# -----------------------------------------------------------------------
# MARCA / TEMA SIMUFIRE (mismos colores que ui/SimuFireTheme.gd)
# -----------------------------------------------------------------------
SF_BG = "#000303"        # fondo casi negro del juego
SF_PANEL = "#050d12"     # panel
SF_PLOT_BG = "#081217"   # fondo del area de plot
SF_BORDER = "#2e383f"
SF_ORANGE = "#ff4000"    # acento
SF_BLUE = "#00b3e0"
SF_TEXT = "#e6f0f5"
SF_MUTED = "#7d8c99"
SF_FONT_STACK = "Bahnschrift, 'Segoe UI Semibold', 'Segoe UI', 'Arial Narrow', sans-serif"

_LOGO_SRC = os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "assets", "ui", "simufire_logo_editor.png"))


def _prepare_assets(mode, out_dir):
    """
    Prepara plotly.js y el logo segun el modo, y devuelve un dict:
      { "plotly_head": <etiqueta <script> para el <head>>,
        "logo_src": <src del <img> del logo> }
    Modos plotly.js:
      inline    -> JS embebido (archivo portable, ~4.6 MB) + logo embebido
      shared    -> plotly.min.js + simufire_logo.png UNA vez en el padre,
                   referenciados con '../' (cada dashboard queda pequeno)
      directory -> ambos junto al html
      cdn       -> plotly desde CDN, logo compartido
    """
    parent = os.path.dirname(out_dir.rstrip("/\\")) or out_dir

    # --- plotly.js ---
    if mode == "inline":
        try:
            import plotly.offline as po
            plotly_head = "<script type=\"text/javascript\">%s</script>" % po.get_plotlyjs()
        except Exception as exc:
            print("Aviso: fallo get_plotlyjs (%s); uso CDN." % exc)
            plotly_head = "<script src=\"https://cdn.plot.ly/plotly-2.min.js\" charset=\"utf-8\"></script>"
    elif mode == "cdn":
        plotly_head = "<script src=\"https://cdn.plot.ly/plotly-2.min.js\" charset=\"utf-8\"></script>"
    else:
        # shared (por defecto) / directory
        target_dir = parent if mode != "directory" else out_dir
        js_path = os.path.join(target_dir, "plotly.min.js")
        if not os.path.exists(js_path) or os.path.getsize(js_path) < 1000:
            try:
                import plotly.offline as po
                with open(js_path, "w", encoding="utf-8") as f:
                    f.write(po.get_plotlyjs())
            except Exception as exc:
                print("Aviso: no se pudo escribir plotly.min.js (%s)." % exc)
        rel = "plotly.min.js" if mode == "directory" else "../plotly.min.js"
        plotly_head = "<script src=\"%s\" charset=\"utf-8\"></script>" % rel

    # --- logo ---
    logo_src = ""
    if os.path.exists(_LOGO_SRC):
        if mode == "inline":
            try:
                import base64
                with open(_LOGO_SRC, "rb") as lf:
                    b64 = base64.b64encode(lf.read()).decode("ascii")
                logo_src = "data:image/png;base64,%s" % b64
            except Exception:
                logo_src = ""
        else:
            target_dir = parent if mode != "directory" else out_dir
            dst = os.path.join(target_dir, "simufire_logo.png")
            if not os.path.exists(dst) or os.path.getsize(dst) != os.path.getsize(_LOGO_SRC):
                try:
                    shutil.copy2(_LOGO_SRC, dst)
                except OSError:
                    pass
            logo_src = "simufire_logo.png" if mode == "directory" else "../simufire_logo.png"

    return {"plotly_head": plotly_head, "logo_src": logo_src}


def _wrap_page(plot_div, plotly_head, logo_src, sim_label):
    """Envuelve el div de Plotly en una pagina con la marca SimuFire."""
    date_only = sim_label.split("_")[0] if "_" in sim_label else sim_label
    logo_html = ""
    if logo_src:
        logo_html = "<img class=\"sf-logo\" src=\"%s\" alt=\"SimuFire\">" % logo_src
    return """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SimuFire — Gráficos interactivos %(date)s</title>
%(plotly_head)s
<style>
  html, body { margin:0; padding:0; background:%(bg)s; color:%(text)s;
    font-family:%(font)s; }
  .sf-header { display:flex; align-items:center; gap:16px;
    padding:12px 24px; background:linear-gradient(90deg, %(panel)s 0%%, %(bg)s 70%%);
    border-bottom:2px solid %(orange)s; }
  .sf-logo { height:44px; width:auto; image-rendering:auto; }
  .sf-titles { display:flex; flex-direction:column; line-height:1.15; }
  .sf-title { font-size:25px; font-weight:700; letter-spacing:1.5px; }
  .sf-title .accent { color:%(orange)s; }
  .sf-sub { font-size:12.5px; color:%(muted)s; letter-spacing:0.4px; }
  .sf-plot { padding:6px 16px 18px; }
  .sf-foot { padding:6px 24px 16px; color:%(muted)s; font-size:11px; }
</style>
</head>
<body>
  <div class="sf-header">
    %(logo)s
    <div class="sf-titles">
      <div class="sf-title">SIMU<span class="accent">FIRE</span></div>
      <div class="sf-sub">Gráficos interactivos &nbsp;·&nbsp; %(date)s</div>
    </div>
  </div>
  <div class="sf-plot">%(plot)s</div>
  <div class="sf-foot">SimuFire · gráficas interactivas — arrastra para hacer zoom, doble clic para resetear.</div>
</body>
</html>""" % {
        "date": date_only, "plotly_head": plotly_head, "plot": plot_div,
        "logo": logo_html, "bg": SF_BG, "panel": SF_PANEL, "text": SF_TEXT,
        "orange": SF_ORANGE, "muted": SF_MUTED, "font": SF_FONT_STACK,
    }


def build_dashboard(rooms, events, out_html, sim_label, assets=None):
    room_ids = sorted(rooms.keys(), key=lambda x: str(x))
    if not room_ids:
        return False

    specs = [[{"secondary_y": False}] for _ in range(N_ROWS)]
    specs[FED_SVV_ROW - 1] = [{"secondary_y": True}]

    fig = make_subplots(rows=N_ROWS, cols=1, shared_xaxes=True,
                        vertical_spacing=0.035, subplot_titles=ROW_TITLES,
                        specs=specs)

    # Trazas por habitacion; guardamos el rango de indices de cada una.
    trace_ranges = []
    start = 0
    for i, rid in enumerate(room_ids):
        n = _room_traces(fig, rooms[rid], visible=(i == 0))
        trace_ranges.append((start, start + n))
        start += n
    total_traces = start

    # Eje Y secundario etiqueta
    fig.update_yaxes(title_text="FED", row=FED_SVV_ROW, col=1, secondary_y=False,
                     range=[0, 5])
    fig.update_yaxes(title_text="SVV / Vis (%)", row=FED_SVV_ROW, col=1,
                     secondary_y=True, range=[0, 105])
    fig.update_yaxes(range=[0, 22], row=4, col=1)
    fig.update_xaxes(title_text="Tiempo (s)", row=N_ROWS, col=1)

    _add_thresholds(fig)

    t_end = 1.0
    for rid in room_ids:
        ts = rooms[rid]["times"]
        if ts:
            t_end = max(t_end, max(ts))
    _add_events(fig, events, t_end)

    # Dropdown para elegir habitacion (visibilidad de trazas).
    buttons = []
    for i, rid in enumerate(room_ids):
        vis = [False] * total_traces
        s, e = trace_ranges[i]
        for k in range(s, e):
            vis[k] = True
        name = rooms[rid].get("name", str(rid))
        buttons.append(dict(
            label="ROOM %s  %s" % (rid, name),
            method="update",
            args=[{"visible": vis},
                  {"title.text": "SimuFire — %s — ROOM %s (%s)" % (sim_label, rid, name)}],
        ))

    first_name = rooms[room_ids[0]].get("name", str(room_ids[0]))
    fig.update_layout(
        template="plotly_dark",
        height=1500,
        hovermode="x unified",
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor=SF_PLOT_BG,
        font=dict(color=SF_TEXT, family=SF_FONT_STACK, size=12),
        title=dict(text="ROOM %s — %s" % (room_ids[0], first_name),
                   x=0.5, xanchor="center", font=dict(color=SF_TEXT, size=17)),
        legend=dict(orientation="h", yanchor="bottom", y=-0.06, x=0,
                    bgcolor="rgba(5,13,18,0.6)", font=dict(color=SF_TEXT)),
        margin=dict(t=96, r=40, l=70, b=60),
        hoverlabel=dict(bgcolor=SF_PANEL, bordercolor=SF_BORDER,
                        font=dict(color=SF_TEXT, family=SF_FONT_STACK)),
        updatemenus=[dict(
            buttons=buttons, direction="down", showactive=True,
            x=0.0, xanchor="left", y=1.10, yanchor="top",
            pad=dict(t=4, b=4), bgcolor=SF_PANEL, bordercolor=SF_BORDER,
            font=dict(color=SF_TEXT),
        )],
    )
    # Rejillas y ejes con la paleta del juego en todos los subplots.
    fig.update_xaxes(gridcolor="rgba(255,255,255,0.06)", zerolinecolor=SF_BORDER,
                     linecolor=SF_BORDER, tickfont=dict(color=SF_MUTED))
    fig.update_yaxes(gridcolor="rgba(255,255,255,0.06)", zerolinecolor=SF_BORDER,
                     linecolor=SF_BORDER, tickfont=dict(color=SF_MUTED))
    # Títulos de subplot en color de texto de marca.
    for ann in fig.layout.annotations:
        ann.font.color = SF_TEXT
    fig.add_annotation(text="Habitación:", xref="paper", yref="paper",
                       x=0.0, y=1.135, showarrow=False,
                       font=dict(size=11, color=SF_MUTED), xanchor="left")

    assets = assets or {"plotly_head": "", "logo_src": ""}
    plot_div = fig.to_html(full_html=False, include_plotlyjs=False,
                           config={"displaylogo": False, "responsive": True,
                                   "modeBarButtonsToRemove": ["lasso2d", "select2d"],
                                   "doubleClick": "reset"})
    page = _wrap_page(plot_div, assets.get("plotly_head", ""),
                      assets.get("logo_src", ""), sim_label)
    with open(out_html, "w", encoding="utf-8") as f:
        f.write(page)
    return True


# -----------------------------------------------------------------------
# MAIN (interfaz de argumentos compatible con generate_fire_graphs.py)
# -----------------------------------------------------------------------

def _parse_args():
    p = argparse.ArgumentParser(description="Dashboard HTML interactivo de SimuFire (Plotly)")
    p.add_argument("--log", default=gfg.LOG_PATH)
    p.add_argument("--csv", default=gfg.CSV_PATH)
    p.add_argument("--out-root", default=gfg.DEFAULT_GRAPHS_ROOT)
    p.add_argument("--out-dir", default="",
                   help="Directorio exacto de salida (co-ubicar junto a los PNG). "
                        "Si se da, ignora --out-root y el timestamp.")
    p.add_argument("--latest-file", default="")
    p.add_argument("--copy-log", action="store_true")
    p.add_argument("--copy-csv", action="store_true")
    p.add_argument("--plotlyjs", default="shared",
                   choices=["shared", "inline", "directory", "cdn"],
                   help="Como incluir plotly.js (shared=1 copia compartida, por defecto)")
    p.add_argument("--open", action="store_true", help="Abrir el HTML al terminar")
    return p.parse_args()


def main():
    args = _parse_args()
    log_path = os.path.abspath(args.log)
    csv_path = os.path.abspath(args.csv)
    graphs_root = os.path.abspath(args.out_root)
    sim_label = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")

    events = []
    if os.path.exists(log_path) and os.path.getsize(log_path) > 0:
        try:
            _, _, events = gfg.parse_log(log_path)
        except Exception as exc:
            print("Aviso: no se pudieron leer eventos del TXT: %s" % exc)

    csv_usable = os.path.exists(csv_path) and os.path.getsize(csv_path) > 0
    if csv_usable and os.path.exists(log_path) and os.path.getsize(log_path) > 0:
        if os.path.getmtime(csv_path) < os.path.getmtime(log_path) - 5:
            print("Aviso: CSV mas viejo que el log TXT — usando TXT.")
            csv_usable = False

    if csv_usable:
        print("Leyendo CSV: " + csv_path)
        _, rooms = gfg.parse_csv_log(csv_path)
    else:
        print("Leyendo log TXT: " + log_path)
        _, rooms, events = gfg.parse_log(log_path)

    if not rooms:
        print("Sin datos de habitaciones. Corre la simulacion primero.")
        return 1

    if args.out_dir.strip():
        out_dir = os.path.abspath(args.out_dir)
    else:
        out_dir = os.path.join(graphs_root, sim_label)
    os.makedirs(out_dir, exist_ok=True)
    date_only = sim_label.split("_")[0]
    out_html = os.path.join(out_dir, "graficas_interactivas_%s.html" % date_only)
    print("Habitaciones: %s | Eventos: %d" % (
        sorted(str(k) for k in rooms.keys()), len(events)))

    assets = _prepare_assets(args.plotlyjs, out_dir)
    if not build_dashboard(rooms, events, out_html, sim_label, assets=assets):
        print("No se pudo construir el dashboard.")
        return 1

    if args.copy_log and os.path.exists(log_path):
        try:
            shutil.copy2(log_path, os.path.join(out_dir, "sim_log.txt"))
        except OSError:
            pass
    if args.copy_csv and os.path.exists(csv_path) and os.path.getsize(csv_path) > 0:
        try:
            shutil.copy2(csv_path, os.path.join(out_dir, "sim_log.csv"))
        except OSError:
            pass

    if args.latest_file:
        latest = os.path.abspath(args.latest_file)
        os.makedirs(os.path.dirname(latest) or ".", exist_ok=True)
        with open(latest, "w", encoding="utf-8") as f:
            f.write(out_dir)

    print("\nListo. Dashboard interactivo:\n  " + out_html)

    if args.open:
        try:
            import webbrowser
            webbrowser.open("file://" + out_html.replace("\\", "/"))
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
