#!/usr/bin/env python3
"""H2.6 opening-network topology inventory. Read-only.

The coupled pressure solver sees one unknown per room and couples them through
the interior opening graph, so what matters for its numerics is the SHAPE of
that graph, not the fire. Topology lives in the scenario templates under
`scenarios/`; the 108 validation cases under `sim/validation/cases/` override
fire, ventilation and window state on top of a template, so they inherit its
network.

This script classifies each template's opening network so a minimal corpus can
be chosen that covers the most topological classes.

Ten of the fourteen classes are static geometry and are decided here. The
remaining four - neutral plane inside the vent, unidirectional flow,
bidirectional counterflow, and near-zero / sign-changing pressure - are
properties of a particular solve, not of the network, and are reported by the
solver at runtime (`neutral_plane_inside`, `counterflow_connection_count`,
`delta_p_pa`). They are listed here as runtime-determined so the inventory does
not silently claim coverage it cannot see.

Exterior is room id -1.

IMPORTANT - static network vs effective network
-----------------------------------------------
The static classification below is an UPPER BOUND on what the solver sees. The
coupled solver is invoked per connected component of rooms joined by currently
OPEN interior openings, so doors and windows that a case shuts through its
`opening_overrides` are simply not in its graph. `cfast_corridor_chain` runs on
the `simple_house` template, which is statically a star, yet the captured solve
has three rooms and two openings - a linear chain. Classes C1, C2 and C3
therefore appear at runtime out of larger networks and must be counted from
real solves, not from template geometry.

`--from-run` reads the coupled-solver preview columns of one or more run CSVs
and reports the effective `(room_count, opening_count)` the solver actually
worked on, plus the runtime-only classes.
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SCENARIO_DIR = ROOT / "scenarios"
CASE_DIR = ROOT / "sim/validation/cases"
EXTERIOR = -1

STATIC_CLASSES = {
    "C1_single_room_exterior": "one interior room with an exterior opening",
    "C2_two_rooms_one_link": "exactly two rooms joined by one interior link",
    "C3_linear_chain": "a path: every interior room has degree <= 2, no cycle",
    "C4_star": "one hub adjacent to >= 3 leaves",
    "C5_branched_tree": "acyclic, max interior degree >= 3, not a pure star",
    "C6_interior_loop": "at least one independent cycle in the interior graph",
    "C7_multi_floor": "rooms on more than one floor level",
    "C8_parallel_openings": "more than one opening between the same room pair",
    "C9_interior_and_exterior": "interior links and exterior openings coexist",
    "C10_asymmetric_vents": "openings differ in sill, height, width or fraction",
}

RUNTIME_CLASSES = {
    "C11_neutral_plane_inside": "neutral plane strictly inside a vent span",
    "C12_unidirectional_flow": "a vent carrying flow one way only",
    "C13_counterflow": "a vent carrying both directions at once",
    "C14_near_zero_dp": "opening dp near zero or changing sign",
}


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def interior_edges(openings: list[dict]) -> list[tuple[int, int]]:
    edges = []
    for opening in openings:
        a, b = int(opening.get("a", EXTERIOR)), int(opening.get("b", EXTERIOR))
        if a != EXTERIOR and b != EXTERIOR:
            edges.append((min(a, b), max(a, b)))
    return edges


def exterior_openings(openings: list[dict]) -> list[dict]:
    return [
        o for o in openings
        if int(o.get("a", EXTERIOR)) == EXTERIOR
        or int(o.get("b", EXTERIOR)) == EXTERIOR
    ]


def components(nodes: set[int], adjacency: dict[int, set[int]]) -> list[set[int]]:
    seen: set[int] = set()
    out = []
    for node in sorted(nodes):
        if node in seen:
            continue
        stack, group = [node], set()
        while stack:
            current = stack.pop()
            if current in group:
                continue
            group.add(current)
            stack.extend(adjacency[current] - group)
        seen |= group
        out.append(group)
    return out


def floor_levels(rooms: list[dict]) -> set[float]:
    return {float(r.get("floor_level_z_m", 0.0)) for r in rooms}


def classify(name: str, data: dict[str, Any]) -> dict[str, Any]:
    rooms = data.get("rooms_data", [])
    openings = data.get("openings_data", [])
    edges = interior_edges(openings)
    unique_edges = set(edges)
    exteriors = exterior_openings(openings)

    interior_nodes = {n for edge in unique_edges for n in edge}
    adjacency: dict[int, set[int]] = defaultdict(set)
    for a, b in unique_edges:
        adjacency[a].add(b)
        adjacency[b].add(a)
    for room_index in range(len(rooms)):
        adjacency.setdefault(room_index, set())

    all_nodes = set(range(len(rooms)))
    comps = components(all_nodes, adjacency)
    degrees = {n: len(adjacency[n]) for n in all_nodes}
    max_degree = max(degrees.values()) if degrees else 0
    # Independent cycles: |E| - |V| + |components| over the interior graph.
    cycles = len(unique_edges) - len(all_nodes) + len(comps)

    parallel = len(edges) - len(unique_edges)
    levels = floor_levels(rooms)

    hub_count = sum(1 for n in all_nodes if degrees[n] >= 3)
    leaf_like = max_degree >= 3 and cycles <= 0

    def vents_differ(key: str) -> bool:
        values = {round(float(o.get(key, 0.0)), 6) for o in openings}
        return len(values) > 1

    covered = set()
    if len(rooms) >= 1 and exteriors:
        # Only counts as the single-room class if some room's whole world is
        # one exterior vent and no interior link.
        for room_index in all_nodes:
            if degrees[room_index] == 0 and any(
                room_index in (int(o.get("a", EXTERIOR)), int(o.get("b", EXTERIOR)))
                for o in exteriors
            ):
                covered.add("C1_single_room_exterior")
                break
    if len(all_nodes) == 2 and len(unique_edges) == 1:
        covered.add("C2_two_rooms_one_link")
    if unique_edges and cycles <= 0 and max_degree <= 2:
        covered.add("C3_linear_chain")
    if hub_count >= 1 and cycles <= 0:
        covered.add("C4_star" if hub_count == 1 and len(unique_edges) == max_degree
                    else "C5_branched_tree")
    if leaf_like and "C4_star" not in covered:
        covered.add("C5_branched_tree")
    if cycles > 0:
        covered.add("C6_interior_loop")
    if len(levels) > 1:
        covered.add("C7_multi_floor")
    if parallel > 0:
        covered.add("C8_parallel_openings")
    if unique_edges and exteriors:
        covered.add("C9_interior_and_exterior")
    if any(vents_differ(k) for k in
           ("sill_m", "height_m", "width_m", "open_fraction")):
        covered.add("C10_asymmetric_vents")

    return {
        "template": name,
        "rooms": len(rooms),
        "interior_links": len(unique_edges),
        "parallel_extra": parallel,
        "exterior_openings": len(exteriors),
        "max_degree": max_degree,
        "components": len(comps),
        "independent_cycles": max(cycles, 0),
        "floor_levels": len(levels),
        "classes": sorted(covered),
    }


def cases_by_template() -> dict[str, list[str]]:
    out: dict[str, list[str]] = defaultdict(list)
    for path in sorted(CASE_DIR.glob("*.json")):
        try:
            data = load(path)
        except Exception:
            continue
        out[str(data.get("template", "?"))].append(path.stem)
    return out


def greedy_cover(rows: list[dict[str, Any]]) -> list[str]:
    """Smallest set of templates covering the most static classes."""
    remaining = set()
    for row in rows:
        remaining |= set(row["classes"])
    chosen: list[str] = []
    pool = {row["template"]: set(row["classes"]) for row in rows}
    while remaining:
        best = max(pool, key=lambda t: (len(pool[t] & remaining), -len(pool[t])))
        gain = pool[best] & remaining
        if not gain:
            break
        chosen.append(best)
        remaining -= gain
        del pool[best]
    return chosen


PREFIX = "phase3_shadow_coupled_solver_"


def _key(opening: dict) -> tuple:
    return (
        int(opening.get("a", EXTERIOR)),
        int(opening.get("b", EXTERIOR)),
        str(opening.get("type", "")),
    )


def case_effective_graph(case_path: Path) -> dict[str, Any]:
    """The interior network a case actually leaves open.

    A case sits on a template and then applies `opening_overrides`; an opening
    with `open_fraction == 0` is simply absent from the solver's graph. Because
    the edges are known here - unlike in the CSV, which carries only counts -
    this is where chain, star and branched tree can honestly be told apart.
    `opening_events` are reported separately: they change the graph mid-run.
    """
    case = load(case_path)
    template = SCENARIO_DIR / f"preset_{case.get('template', '')}.json"
    if not template.exists():
        return {"case": case_path.stem, "error": "template not found"}
    data = load(template)
    rooms = data.get("rooms_data", [])

    state = {_key(o): float(o.get("open_fraction", 0.0))
             for o in data.get("openings_data", [])}
    for override in case.get("opening_overrides", []):
        key = _key(override)
        pair = (key[1], key[0], key[2])
        if key in state:
            state[key] = float(override.get("open_fraction", 0.0))
        elif pair in state:
            state[pair] = float(override.get("open_fraction", 0.0))

    edges = {(min(a, b), max(a, b)) for (a, b, _), frac in state.items()
             if frac > 0.0 and a != EXTERIOR and b != EXTERIOR}
    exterior_open = sum(1 for (a, b, _), frac in state.items()
                        if frac > 0.0 and (a == EXTERIOR or b == EXTERIOR))

    adjacency: dict[int, set[int]] = defaultdict(set)
    for a, b in edges:
        adjacency[a].add(b)
        adjacency[b].add(a)
    nodes = set(adjacency)
    comps = components(nodes, adjacency) if nodes else []
    largest = max(comps, key=len) if comps else set()
    sub = {(a, b) for a, b in edges if a in largest}
    degrees = {n: len(adjacency[n] & largest) for n in largest}
    max_degree = max(degrees.values()) if degrees else 0
    cycles = len(sub) - len(largest) + 1 if largest else 0

    shape = "empty"
    covered = set()
    if len(largest) == 1:
        shape, covered = "single", {"C1_single_room_exterior"}
    elif len(largest) == 2:
        shape, covered = "two_rooms_one_link", {"C2_two_rooms_one_link"}
    elif cycles > 0:
        shape, covered = "loop", {"C6_interior_loop"}
    elif max_degree <= 2:
        shape, covered = "chain", {"C3_linear_chain"}
    elif sum(1 for n in largest if degrees[n] >= 3) == 1 \
            and len(sub) == max_degree:
        shape, covered = "star", {"C4_star"}
    else:
        shape, covered = "branched_tree", {"C5_branched_tree"}

    if edges and exterior_open:
        covered.add("C9_interior_and_exterior")
    if len(floor_levels(rooms)) > 1 and len(largest) > 1:
        levels_in = {float(rooms[n].get("floor_level_z_m", 0.0))
                     for n in largest if n < len(rooms)}
        if len(levels_in) > 1:
            covered.add("C7_multi_floor")

    return {
        "case": case_path.stem,
        "template": case.get("template"),
        "component_rooms": len(largest),
        "component_links": len(sub),
        "max_degree": max_degree,
        "independent_cycles": max(cycles, 0),
        "exterior_open": exterior_open,
        "opening_events": len(case.get("opening_events", [])),
        "shape": shape,
        "classes": sorted(covered),
    }


def effective_from_run(csv_path: Path) -> dict[str, Any]:
    """What the solver actually solved, read from a run CSV. Read-only."""
    import csv as _csv

    with csv_path.open(encoding="utf-8-sig", newline="") as handle:
        rows = [r for r in _csv.DictReader(handle)
                if float(r.get(f"{PREFIX}enabled_flag", 0) or 0) > 0]
    if not rows:
        return {"csv": csv_path.name, "active_rows": 0}

    def fnum(row: dict, field: str) -> float:
        return float(row.get(f"{PREFIX}{field}", 0) or 0)

    shapes: dict[tuple[int, int], int] = defaultdict(int)
    for row in rows:
        shapes[(int(fnum(row, "room_count")), int(fnum(row, "opening_count")))] += 1

    counterflow = max(fnum(r, "counterflow_connection_count") for r in rows)
    violations = max(fnum(r, "counterflow_violation_count") for r in rows)

    # Counts alone cannot separate chain from star from branched tree: 5r/4o is
    # any of the three. Only what the counts genuinely prove is claimed here;
    # the fine shape comes from `case_effective_graph`, which knows the edges.
    covered = set()
    for (room_count, opening_count), _ in shapes.items():
        if room_count == 1:
            covered.add("C1_single_room_exterior")
        if room_count == 2:
            covered.add("C2_two_rooms_one_link")
        if opening_count >= room_count and room_count >= 3:
            covered.add("C6_interior_loop")
    if counterflow > 0:
        covered.add("C13_counterflow")
        covered.add("C11_neutral_plane_inside")
    return {
        "csv": csv_path.name,
        "active_rows": len(rows),
        "shapes": {f"{k[0]}r/{k[1]}o": v for k, v in sorted(shapes.items())},
        "max_counterflow_connections": counterflow,
        "counterflow_violations": violations,
        "classes": sorted(covered),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json-out", type=Path, default=None)
    parser.add_argument(
        "--from-run", type=Path, nargs="*", default=None,
        help="run CSVs to read the EFFECTIVE solver topology from",
    )
    parser.add_argument(
        "--cases", nargs="*", default=None,
        help="case stems whose effective open network should be classified",
    )
    args = parser.parse_args()

    if args.cases:
        print("=" * 92)
        print("  Effective open network per case (template + opening_overrides)")
        print("=" * 92)
        print(f"{'case':<38}{'template':<26}{'rooms':>6}{'lnk':>5}"
              f"{'deg':>5}{'cyc':>5}{'ext':>5}{'ev':>4}  shape")
        print("-" * 92)
        union, report = set(), []
        for stem in args.cases:
            info = case_effective_graph(CASE_DIR / f"{stem}.json")
            report.append(info)
            if "error" in info:
                print(f"{stem:<38}{info['error']}")
                continue
            union |= set(info["classes"])
            print(f"{info['case']:<38}{str(info['template']):<26}"
                  f"{info['component_rooms']:>6}{info['component_links']:>5}"
                  f"{info['max_degree']:>5}{info['independent_cycles']:>5}"
                  f"{info['exterior_open']:>5}{info['opening_events']:>4}"
                  f"  {info['shape']}")
        print(f"\nClasses covered by this corpus: {', '.join(sorted(union))}")
        missing = set(STATIC_CLASSES) - union
        if missing:
            print(f"Static classes NOT covered: {', '.join(sorted(missing))}")
        if args.json_out:
            args.json_out.write_text(
                json.dumps({"cases": report, "classes": sorted(union)}, indent=2),
                encoding="utf-8")
            print(f"wrote {args.json_out}")
        return 0

    if args.from_run:
        print("=" * 78)
        print("  Effective solver topology observed at runtime")
        print("=" * 78)
        union = set()
        report = []
        for csv_path in args.from_run:
            info = effective_from_run(csv_path)
            report.append(info)
            union |= set(info.get("classes", []))
            print(f"\n{info['csv']}  active_rows={info['active_rows']}")
            if info.get("shapes"):
                print(f"  shapes (rooms/openings): {info['shapes']}")
                print(f"  max counterflow connections: "
                      f"{info['max_counterflow_connections']:.0f}"
                      f"   violations: {info['counterflow_violations']:.0f}")
                print(f"  classes: {', '.join(info['classes']) or '-'}")
        print(f"\nRuntime classes observed: {', '.join(sorted(union)) or '-'}")
        if args.json_out:
            args.json_out.write_text(
                json.dumps({"runs": report, "classes": sorted(union)}, indent=2),
                encoding="utf-8",
            )
            print(f"wrote {args.json_out}")
        return 0

    rows = []
    for path in sorted(SCENARIO_DIR.glob("preset_*.json")):
        rows.append(classify(path.stem.replace("preset_", ""), load(path)))

    by_template = cases_by_template()

    print("=" * 78)
    print("  H2.6 opening-network topology inventory")
    print("=" * 78)
    header = (
        f"{'template':<26}{'rooms':>6}{'links':>6}{'par':>5}"
        f"{'ext':>5}{'deg':>5}{'comp':>6}{'cyc':>5}{'lvl':>5}  classes"
    )
    print(header)
    print("-" * 78)
    for row in rows:
        tags = ",".join(c.split("_")[0] for c in row["classes"])
        print(
            f"{row['template']:<26}{row['rooms']:>6}{row['interior_links']:>6}"
            f"{row['parallel_extra']:>5}{row['exterior_openings']:>5}"
            f"{row['max_degree']:>5}{row['components']:>6}"
            f"{row['independent_cycles']:>5}{row['floor_levels']:>5}  {tags}"
        )

    print()
    print("Static class coverage across all templates:")
    union = set()
    for row in rows:
        union |= set(row["classes"])
    for key, description in STATIC_CLASSES.items():
        mark = "yes" if key in union else "NO "
        holders = [r["template"] for r in rows if key in r["classes"]]
        print(f"  [{mark}] {key:<28} {description}")
        if holders:
            print(f"         {len(holders)} template(s): {', '.join(holders[:4])}"
                  + (" ..." if len(holders) > 4 else ""))

    print()
    print("Runtime-determined classes (not decidable from geometry):")
    for key, description in RUNTIME_CLASSES.items():
        print(f"  [rt ] {key:<28} {description}")

    print()
    cover = greedy_cover(rows)
    print(f"Minimal template cover ({len(cover)}): {', '.join(cover)}")
    print()
    print("Validation cases available per covering template:")
    for template in cover:
        cases = by_template.get(template, [])
        print(f"  {template:<26} {len(cases):>3} case(s)")
        if cases:
            print(f"       e.g. {', '.join(cases[:5])}")

    missing = set(STATIC_CLASSES) - union
    if missing:
        print()
        print("STATIC CLASSES WITH NO TEMPLATE:")
        for key in sorted(missing):
            print(f"  - {key}: {STATIC_CLASSES[key]}")

    if args.json_out:
        args.json_out.write_text(
            json.dumps(
                {
                    "templates": rows,
                    "minimal_cover": cover,
                    "static_classes_covered": sorted(union),
                    "static_classes_missing": sorted(missing),
                    "runtime_classes": sorted(RUNTIME_CLASSES),
                    "cases_by_template": {k: v for k, v in by_template.items()},
                },
                indent=2,
            ),
            encoding="utf-8",
        )
        print(f"\nwrote {args.json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
