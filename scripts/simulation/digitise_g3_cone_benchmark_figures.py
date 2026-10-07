"""Digitise the n-heptane curves of the controlled-atmosphere cone evaporation tests.

The source is the accepted version of Beji, Helson, Rogaume and Luche, Fire Safety Journal 121
(2021) 103317, as distributed by the Ghent University repository. The article is in copyright,
so neither the document nor the digitised series belongs in this repository: the script reads a
local copy, checks that it is the reviewed file and writes the series outside version control.

What comes out is a digitisation of published figures, never raw data. The figures show one
marker every 15 s; the acquisition was one sample per second and is not recoverable. Each value
is the vertical position of a marker located by matching its shape, with the pixel resolution
of the embedded bitmap as the only stated reading error. Pixels painted with the colour of
another curve are treated as unknown, so a hidden marker is reported as hidden, not guessed.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LOCAL_PDF = ROOT / "runs" / "literature_local" / "Beji_2021_FSJ_103317_accepted_version.pdf"
LOCAL_SERIES = ROOT / "runs" / "literature_local" / "g3_cone_benchmark_digitised_series.json"
PDF_SHA256 = "1c82a8219bdd36ddd074ef8cd7c6e627d67ff337dd1c56e6b52b2922bad945ff"
SOURCE_URL = "https://biblio.ugent.be/publication/8702056"
SCHEMA = "g3_cone_benchmark_digitised_series_v1"
STEP_S = 15.0

# Embedded bitmaps, identified by size and by the SHA-256 of their RGB pixels.
FIGURES = {
    "figure_4": {"pdf_page": 10, "size": [1264, 738], "pixels_sha256": "9dd808002e0bcec53233dc15b072f4c26baab08704cd3be1c67a5e7230266241"},
    "figure_6": {"pdf_page": 17, "size": [1236, 739], "pixels_sha256": "bd8ea74c3e7b9cb9cc6f16d920f30b77b5731cec3b5c5de8c7ab2467b45b4772"},
    "figure_7": {"pdf_page": 17, "size": [1217, 734], "pixels_sha256": "446a699296cba92ac976d673ec24654de70a3d87c927d6ec438b34ee862d4962"},
}

# Frame of each panel in pixels (left, right, top, bottom) and the axis limits printed on it.
PANELS = {
    "figure_4a": {"figure": "figure_4", "frame": [94, 576, 21, 294], "axes": [0.0, 800.0, 0.0, 60.0], "quantity": "mass_loss_rate_per_area", "unit": "g/(m2 s)"},
    "figure_4b": {"figure": "figure_4", "frame": [728, 1209, 21, 294], "axes": [0.0, 400.0, 0.0, 120.0], "quantity": "mass_loss_rate_per_area", "unit": "g/(m2 s)"},
    "figure_6a": {"figure": "figure_6", "frame": [82, 563, 23, 295], "axes": [0.0, 300.0, 0.0, 150.0], "quantity": "temperature_upper_centre", "unit": "degC"},
    "figure_6b": {"figure": "figure_6", "frame": [716, 1197, 23, 295], "axes": [0.0, 150.0, 0.0, 150.0], "quantity": "temperature_upper_centre", "unit": "degC"},
    "figure_7a": {"figure": "figure_7", "frame": [80, 561, 22, 294], "axes": [0.0, 500.0, 0.0, 150.0], "quantity": "temperature_lower_centre", "unit": "degC"},
    "figure_7b": {"figure": "figure_7", "frame": [714, 1195, 22, 294], "axes": [0.0, 250.0, 0.0, 150.0], "quantity": "temperature_lower_centre", "unit": "degC"},
}

# Curves of the corpus. Colour and marker are those of each legend.
CURVES = [
    {"run": "H25#1", "panel": "figure_4a", "colour": "red", "marker": "circle", "t_end_s": 800.0},
    {"run": "H25#2", "panel": "figure_4a", "colour": "blue", "marker": "plus", "t_end_s": 800.0},
    {"run": "H25#3", "panel": "figure_4a", "colour": "magenta", "marker": "star", "t_end_s": 800.0},
    {"run": "H50#1", "panel": "figure_4b", "colour": "red", "marker": "circle", "t_end_s": 390.0},
    {"run": "H50#2", "panel": "figure_4b", "colour": "blue", "marker": "plus", "t_end_s": 390.0},
    {"run": "H50#3", "panel": "figure_4b", "colour": "magenta", "marker": "star", "t_end_s": 390.0},
    {"run": "H25#1", "panel": "figure_6a", "colour": "red", "marker": "circle", "t_end_s": 285.0},
    {"run": "H25#2", "panel": "figure_6a", "colour": "blue", "marker": "plus", "t_end_s": 285.0},
    {"run": "H50#1", "panel": "figure_6b", "colour": "red", "marker": "circle", "t_end_s": 120.0},
    {"run": "H50#2", "panel": "figure_6b", "colour": "blue", "marker": "plus", "t_end_s": 120.0},
    {"run": "H50#3", "panel": "figure_6b", "colour": "magenta", "marker": "star", "t_end_s": 120.0},
    {"run": "H25#1", "panel": "figure_7a", "colour": "red", "marker": "circle", "t_end_s": 480.0},
    {"run": "H25#2", "panel": "figure_7a", "colour": "blue", "marker": "plus", "t_end_s": 480.0},
    {"run": "H50#1", "panel": "figure_7b", "colour": "red", "marker": "circle", "t_end_s": 240.0},
    {"run": "H50#2", "panel": "figure_7b", "colour": "blue", "marker": "plus", "t_end_s": 240.0},
    {"run": "H50#3", "panel": "figure_7b", "colour": "magenta", "marker": "star", "t_end_s": 240.0},
]

COLOURS = ("red", "blue", "magenta", "green", "cyan")
MIN_OWN_FRACTION = 0.5
READING_HALF_WIDTH_PX = 1.5
HIDDEN_HALF_WIDTH_PX = 3.0


def sha256_file(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def colour_mask(pixels, colour: str):
    """Pixels painted with one of the five pure plot colours, antialiased edges included."""
    r, g, b = pixels[:, :, 0], pixels[:, :, 1], pixels[:, :, 2]
    if colour == "red":
        return (r > 200) & (g < 170) & (b < 170)
    if colour == "blue":
        return (b > 200) & (r < 170) & (g < 170)
    if colour == "magenta":
        return (r > 200) & (b > 200) & (g < 170)
    if colour == "green":
        return (g > 180) & (r < 170) & (b < 170)
    if colour == "cyan":
        return (g > 200) & (b > 200) & (r < 170)
    raise ValueError("unknown colour %r" % colour)


def template(marker: str) -> list:
    """Offsets (row, column) covered by a marker centred on the origin."""
    cells = set()
    if marker == "circle":
        # The ring exactly as each legend draws it: nine pixels across, one pixel thick.
        for dx in range(-2, 3):
            cells.add((-4, dx))
            cells.add((4, dx))
        for dy in range(-2, 3):
            cells.add((dy, -4))
            cells.add((dy, 4))
        for dy in (-3, 3):
            for dx in (-4, -3, 3, 4):
                cells.add((dy, dx))
    elif marker in ("plus", "star"):
        for d in range(-5, 6):
            cells.add((d, 0))
            cells.add((0, d))
        if marker == "star":
            for d in range(-3, 4):
                cells.add((d, d))
                cells.add((d, -d))
    else:
        raise ValueError("unknown marker %r" % marker)
    return sorted(cells)


def load_figures(pdf_path: Path) -> dict:
    """RGB arrays of the three figures, refused unless they are the reviewed bitmaps."""
    import numpy as np
    from PIL import Image
    from pypdf import PdfReader

    digest = sha256_file(pdf_path)
    if digest != PDF_SHA256:
        raise ValueError("the document is not the reviewed accepted version: sha256 %s" % digest)
    reader = PdfReader(str(pdf_path))
    found = {}
    for name, spec in FIGURES.items():
        for image in reader.pages[spec["pdf_page"] - 1].images:
            bitmap = Image.open(io.BytesIO(image.data)).convert("RGB")
            if list(bitmap.size) != spec["size"]:
                continue
            pixels = np.asarray(bitmap)
            if hashlib.sha256(pixels.tobytes()).hexdigest() != spec["pixels_sha256"]:
                raise ValueError("%s does not carry the reviewed pixels" % name)
            found[name] = pixels.astype(int)
    missing = sorted(set(FIGURES) - set(found))
    if missing:
        raise ValueError("figures not found in the document: %s" % ", ".join(missing))
    return found


def frame_is_drawn(pixels, frame: list) -> bool:
    """The declared frame must lie on the dark axis lines of the bitmap.

    Curves resting on zero are drawn over the lower axis, so that side also accepts plot colours.
    """
    left, right, top, bottom = frame
    dark = (pixels[:, :, 0] == 38) & (pixels[:, :, 1] == 38) & (pixels[:, :, 2] == 38)
    drawn = dark.copy()
    for name in COLOURS:
        drawn = drawn | colour_mask(pixels, name)
    span_x = right - left + 1
    span_y = bottom - top + 1
    return bool(
        dark[top, left:right + 1].sum() > 0.6 * span_x
        and drawn[bottom, left:right + 1].sum() > 0.6 * span_x
        and dark[bottom, left:right + 1].sum() > 0.2 * span_x
        and dark[top:bottom + 1, left].sum() > 0.6 * span_y
        and dark[top:bottom + 1, right].sum() > 0.6 * span_y
    )


def legend_box(pixels, frame: list):
    """Bounding box of the legend: the only closed dark rectangle strictly inside the frame."""
    left, right, top, bottom = frame
    dark = (pixels[:, :, 0] == 38) & (pixels[:, :, 1] == 38) & (pixels[:, :, 2] == 38)
    rows = []
    for y in range(top + 3, bottom - 2):
        run = best = start = best_start = 0
        for x in range(left + 3, right - 2):
            if dark[y, x]:
                if run == 0:
                    start = x
                run += 1
                if run > best:
                    best, best_start = run, start
            else:
                run = 0
        if 80 <= best <= 200:
            rows.append((y, best_start, best_start + best - 1))
    if len(rows) < 2:
        return None
    x_left = min(r[1] for r in rows)
    x_right = max(r[2] for r in rows)
    return [x_left, x_right, rows[0][0], rows[-1][0]]


def guide_lines(pixels, frame: list) -> dict:
    """Straight dark lines drawn by the authors across a whole panel, in pixels."""
    left, right, top, bottom = frame
    dark = (pixels[:, :, 0] < 120) & (pixels[:, :, 1] < 120) & (pixels[:, :, 2] < 120)
    # A vertical line may cross the legend, which hides part of it; the legend sides are shorter.
    columns = [x for x in range(left + 3, right - 2) if dark[top + 3:bottom - 2, x].sum() > 0.55 * (bottom - top - 5)]
    rows = [y for y in range(top + 3, bottom - 2) if dark[y, left + 3:right - 2].sum() > 0.9 * (right - left - 5)]
    return {"columns": columns, "rows": rows}


def to_value(panel: dict, row: float) -> float:
    _left, _right, top, bottom = panel["frame"]
    _t0, _t1, v0, v1 = panel["axes"]
    return v0 + (bottom - row) / (bottom - top) * (v1 - v0)


def to_column(panel: dict, time_s: float) -> float:
    left, right, _top, _bottom = panel["frame"]
    t0, t1, _v0, _v1 = panel["axes"]
    return left + (time_s - t0) / (t1 - t0) * (right - left)


def read_curve(pixels, panel: dict, colour: str, marker: str, t_end_s: float) -> list:
    """One reading per marker: the row where the marker shape matches best."""
    left, right, top, bottom = panel["frame"]
    own = colour_mask(pixels, colour)
    other = None
    for name in COLOURS:
        if name != colour:
            mask = colour_mask(pixels, name)
            other = mask if other is None else (other | mask)
    box = legend_box(pixels, panel["frame"])
    cells = template(marker)
    height, width = own.shape
    # Strokes land up to one pixel away from the shape of the legend, depending on where the
    # point falls inside its pixel, so a cell also counts when a neighbour carries the colour.
    near = own.copy()
    near[1:, :] |= own[:-1, :]
    near[:-1, :] |= own[1:, :]
    near[:, 1:] |= own[:, :-1]
    near[:, :-1] |= own[:, 1:]
    readings = []
    count = int(round(t_end_s / STEP_S))
    for index in range(count + 1):
        time_s = index * STEP_S
        column = to_column(panel, time_s)
        best = None
        covered = []
        for dx in (0, -1, 1):
            x = int(round(column)) + dx
            for y in range(top - 1, bottom + 2):
                if box and box[0] - 6 <= x <= box[1] + 6 and box[2] - 6 <= y <= box[3] + 6:
                    continue
                hit = exact = hidden = 0
                for dy, ex in cells:
                    yy, xx = y + dy, x + ex
                    if not (0 <= yy < height and 0 <= xx < width):
                        continue
                    if own[yy, xx]:
                        exact += 1
                        hit += 1
                    elif other[yy, xx]:
                        hidden += 1
                    elif near[yy, xx]:
                        hit += 1
                blank = len(cells) - hit - hidden
                if dx == 0 and blank <= 1 and hidden > 0:
                    covered.append(y)
                key = (hit - blank, exact, -abs(dx))
                if best is None or key > best[0]:
                    best = (key, y, dx, hit, hidden)
        if best is None:
            readings.append({"t_s": time_s, "value": None, "status": "inside_legend"})
            continue
        _key, y, dx, hit, hidden = best
        fraction = hit / len(cells)
        if fraction >= MIN_OWN_FRACTION:
            status, half = "read", READING_HALF_WIDTH_PX
        elif (hit + hidden) / len(cells) >= 0.8 and hit > 0:
            status, half = "partly_hidden", HIDDEN_HALF_WIDTH_PX
        elif covered:
            # Nothing of the marker shows, so it lies under another curve: every row where the
            # whole shape is covered is possible, and the reading is that range, not a point.
            scale = (panel["axes"][3] - panel["axes"][2]) / (bottom - top)
            low, high = to_value(panel, max(covered)), to_value(panel, min(covered))
            readings.append({
                "t_s": time_s,
                "value": round(0.5 * (low + high), 4),
                "half_width": round(0.5 * (high - low) + READING_HALF_WIDTH_PX * scale, 4),
                "status": "hidden_under_other_curve",
                "row_px": 0.5 * (min(covered) + max(covered)),
                "column_offset_px": 0,
                "own_fraction": round(fraction, 3),
            })
            continue
        else:
            readings.append({"t_s": time_s, "value": None, "status": "not_found", "own_fraction": round(fraction, 3)})
            continue
        scale = (panel["axes"][3] - panel["axes"][2]) / (bottom - top)
        readings.append({
            "t_s": time_s,
            "value": round(to_value(panel, y), 4),
            "half_width": round(half * scale, 4),
            "status": status,
            "row_px": y,
            "column_offset_px": dx,
            "own_fraction": round(fraction, 3),
        })
    return readings


def digitise(pdf_path: Path = LOCAL_PDF) -> dict:
    figures = load_figures(Path(pdf_path))
    panels = {}
    for name, panel in PANELS.items():
        pixels = figures[panel["figure"]]
        if not frame_is_drawn(pixels, panel["frame"]):
            raise ValueError("%s: the declared frame is not on the axis lines" % name)
        left, right, top, bottom = panel["frame"]
        t0, t1, v0, v1 = panel["axes"]
        guides = guide_lines(pixels, panel["frame"])
        panels[name] = {
            "authors_vertical_line_s": [round(t0 + (x - left) / (right - left) * (t1 - t0), 2) for x in guides["columns"]],
            "authors_horizontal_line": [round(to_value(panel, y), 2) for y in guides["rows"]],
            "quantity": panel["quantity"],
            "unit": panel["unit"],
            "axes": panel["axes"],
            "frame_px": panel["frame"],
            "legend_px": legend_box(pixels, panel["frame"]),
            "seconds_per_px": round((t1 - t0) / (right - left), 6),
            "units_per_px": round((v1 - v0) / (bottom - top), 6),
            "marker_spacing_px": round(STEP_S * (right - left) / (t1 - t0), 3),
        }
    curves = []
    for curve in CURVES:
        panel = PANELS[curve["panel"]]
        readings = read_curve(figures[panel["figure"]], panel, curve["colour"], curve["marker"], curve["t_end_s"])
        curves.append({key: curve[key] for key in ("run", "panel", "colour", "marker")} | {
            "quantity": panel["quantity"], "unit": panel["unit"], "readings": readings,
        })
    body = {
        "schema": SCHEMA,
        "nature": "digitisation of published figures; not raw data",
        "source": {"url": SOURCE_URL, "document_sha256": PDF_SHA256, "figures": FIGURES},
        "method": {
            "marker_step_s": STEP_S,
            "marker_time_assumed": "multiples of 15 s from the left axis, as the markers are drawn",
            "vertical_position": "row of the best match of the marker shape, other curves treated as unknown",
            "reading_half_width_px": READING_HALF_WIDTH_PX,
            "partly_hidden_half_width_px": HIDDEN_HALF_WIDTH_PX,
            "reading_half_width_kind": "bitmap resolution; not an instrument uncertainty",
        },
        "panels": panels,
        "curves": curves,
    }
    body["series_sha256"] = series_sha256(body)
    return body


def series_sha256(body: dict) -> str:
    """Fingerprint of the readings alone, so two digitisations can be compared without publishing them."""
    lines = []
    for curve in body["curves"]:
        for reading in curve["readings"]:
            lines.append("%s|%s|%.1f|%s|%s" % (
                curve["run"], curve["panel"], reading["t_s"],
                "null" if reading.get("value") is None else "%.4f" % reading["value"], reading["status"],
            ))
    return hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()


def load_series(path: Path = LOCAL_SERIES):
    """The local digitisation, or None when this checkout does not hold one."""
    path = Path(path)
    if not path.is_file():
        return None
    body = json.loads(path.read_text(encoding="utf-8"))
    if body.get("schema") != SCHEMA or series_sha256(body) != body.get("series_sha256"):
        raise ValueError("the local digitisation does not match its own fingerprint")
    return body


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--pdf", type=Path, default=LOCAL_PDF, help="local copy of the accepted version")
    parser.add_argument("--out", type=Path, default=LOCAL_SERIES, help="where to write the series, outside version control")
    parser.add_argument("--print-only", action="store_true", help="print a summary and write nothing")
    args = parser.parse_args()
    body = digitise(args.pdf)
    summary = {"series_sha256": body["series_sha256"], "curves": {}}
    for curve in body["curves"]:
        states = [reading["status"] for reading in curve["readings"]]
        summary["curves"]["%s %s" % (curve["panel"], curve["run"])] = {state: states.count(state) for state in sorted(set(states))}
    print(json.dumps(summary, indent=1, ensure_ascii=False))
    if not args.print_only:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(body, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
        print("written", args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
