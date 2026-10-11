"""Offline topology/door-sweep checks for authored playable homes, not physics."""
from __future__ import annotations

import argparse
import itertools
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EPS = 0.01  # same geometric adjacency allowance as the views
NORMAL = {"top": (0, 1), "bottom": (0, -1), "left": (1, 0), "right": (-1, 0)}


def shared_side(a: dict, b: dict) -> tuple[str, float, float] | None:
    for side, distance, lo, hi in (
        ("right", a["x"] + a["w"] - b["x"], max(a["y"], b["y"]),
         min(a["y"] + a["h"], b["y"] + b["h"])),
        ("left", a["x"] - b["x"] - b["w"], max(a["y"], b["y"]),
         min(a["y"] + a["h"], b["y"] + b["h"])),
        ("bottom", a["y"] + a["h"] - b["y"], max(a["x"], b["x"]),
         min(a["x"] + a["w"], b["x"] + b["w"])),
        ("top", a["y"] - b["y"] - b["h"], max(a["x"], b["x"]),
         min(a["x"] + a["w"], b["x"] + b["w"])),
    ):
        if abs(distance) < EPS and hi - lo > 0.05:
            return side, lo, hi
    return None


def door_pose(data: dict, op: dict) -> dict | None:
    a = data["room_rect_m"][str(op["a"])]
    if op["b"] != -1:
        shared = shared_side(a, data["room_rect_m"][str(op["b"])])
        if shared is None:
            return None
        side, lo, hi = shared
    else:
        side = op["wall"]
        horizontal = side in ("top", "bottom")
        lo = a["x"] if horizontal else a["y"]
        hi = lo + (a["w"] if horizontal else a["h"])
    horizontal = side in ("top", "bottom")
    width = min(op["width_m"], hi - lo)
    offset = op.get("offset_m", 0.5)
    center_axis = lo + (hi - lo) * offset if op.get("offset_is_fraction", True) else (
        a["x"] if horizontal else a["y"]) + offset
    center_axis = max(lo + width / 2, min(hi - width / 2, center_axis))
    if horizontal:
        center = (center_axis, a["y"] + (a["h"] if side == "bottom" else 0))
        tangent = (1, 0)
    else:
        center = (a["x"] + (a["w"] if side == "right" else 0), center_axis)
        # Canonical left/right starts at lower Z in plan, overview and FP.
        tangent = (0, 1)
    sign = -1 if op.get("hinge_side", "left") == "left" else 1
    hinge = tuple(center[k] + sign * tangent[k] * width / 2 for k in (0, 1))
    closed = tuple(-sign * tangent[k] for k in (0, 1))
    direction = 1 if op.get("swing_direction", "in") == "in" else -1
    normal = tuple(direction * v for v in NORMAL[side])
    return {"hinge": hinge, "closed": closed, "normal": normal, "width": width,
            "side": side, "lo": lo, "hi": hi}


def sweep_contains(pose: dict, point: tuple[float, float]) -> bool:
    delta = tuple(point[k] - pose["hinge"][k] for k in (0, 1))
    closed = sum(delta[k] * pose["closed"][k] for k in (0, 1))
    normal = sum(delta[k] * pose["normal"][k] for k in (0, 1))
    # Sweep envelope up to FP's 82 degrees, inset from hinge/frame.
    return (closed > 0.04 and normal > 0.04
            and normal < closed * math.tan(math.radians(82))
            and math.hypot(*delta) < pose["width"] - 0.025)


def sweep_overlap(a: dict, b: dict) -> bool:
    # Conservative 5 cm grid in the overlap of the two radius bounds.
    lo = [max(a["hinge"][k] - a["width"], b["hinge"][k] - b["width"]) for k in (0, 1)]
    hi = [min(a["hinge"][k] + a["width"], b["hinge"][k] + b["width"]) for k in (0, 1)]
    for ix in range(math.ceil(lo[0] / 0.05), math.floor(hi[0] / 0.05) + 1):
        for iy in range(math.ceil(lo[1] / 0.05), math.floor(hi[1] / 0.05) + 1):
            point = (ix * 0.05, iy * 0.05)
            if sweep_contains(a, point) and sweep_contains(b, point):
                return True
    return False


def audit(data: dict) -> list[str]:
    errors = []
    rooms = {int(r["id"]): r for r in data["rooms_data"]}
    rects = data["room_rect_m"]
    graph = {i: set() for i in rooms}
    poses = []
    vertical_rooms = set()
    for a, b in itertools.combinations(rooms, 2):
        if abs(rooms[a].get("floor_level_z_m", 0) - rooms[b].get("floor_level_z_m", 0)) > EPS:
            continue
        ra, rb = rects[str(a)], rects[str(b)]
        overlap = [min(ra[k] + ra[s], rb[k] + rb[s]) - max(ra[k], rb[k])
                   for k, s in (("x", "w"), ("y", "h"))]
        if min(overlap) > EPS:
            errors.append(f"rooms {a}/{b}: overlap")
    for index, op in enumerate(data["openings_data"]):
        a, b = int(op["a"]), int(op["b"])
        if a not in rooms or (b != -1 and b not in rooms):
            errors.append(f"opening {index}: missing room")
            continue
        graph[a].add(b)
        if b != -1:
            graph[b].add(a)
        if op.get("is_vertical", False):
            vertical_rooms.update((a, b))
            if b == -1 or abs(rooms[a].get("floor_level_z_m", 0) - rooms[b].get("floor_level_z_m", 0)) < 0.2:
                errors.append(f"opening {index}: vertical connection without distinct floors")
            elif shared_rect_area(rects[str(a)], rects[str(b)]) < op["width_m"] * op["height_m"] - EPS:
                errors.append(f"opening {index}: shaft larger than floor overlap")
            continue
        if b != -1 and shared_side(rects[str(a)], rects[str(b)]) is None:
            errors.append(f"opening {index}: rooms {a}/{b} have no shared wall")
            continue
        if b == -1:
            pose = door_pose(data, op)
            if pose is not None:
                horizontal = pose["side"] in ("top", "bottom")
                tangent_axis = 0 if horizontal else 1
                center = (pose["hinge"][tangent_axis]
                          + pose["closed"][tangent_axis] * pose["width"] / 2)
                for other_id, other_room in rooms.items():
                    if other_id == a or abs(other_room.get("floor_level_z_m", 0)
                                            - rooms[a].get("floor_level_z_m", 0)) > EPS:
                        continue
                    shared = shared_side(rects[str(a)], rects[str(other_id)])
                    if shared and shared[0] == pose["side"] and min(
                            center + pose["width"] / 2, shared[2]) - max(
                            center - pose["width"] / 2, shared[1]) > EPS:
                        errors.append(f"opening {index}: exterior opening faces room {other_id}")
                        break
        if op["type"] != "door":
            continue
        pose = door_pose(data, op)
        if pose is None:
            continue
        if op["width_m"] > pose["hi"] - pose["lo"] - 0.08 + EPS:
            errors.append(f"door {index}: no space for jambs")
        if b != -1 and op.get("wall", "") != pose["side"]:
            errors.append(f"door {index}: undeclared/inconsistent wall for visual swing")
        target = a if op.get("swing_direction", "in") == "in" else b
        if target != -1:
            room = rects[str(target)]
            for angle in (15, 30, 45, 60, 82):
                radians = math.radians(angle)
                tip = tuple(pose["hinge"][k] + pose["width"] * (
                    math.cos(radians) * pose["closed"][k] + math.sin(radians) * pose["normal"][k])
                    for k in (0, 1))
                if not (room["x"] - EPS <= tip[0] <= room["x"] + room["w"] + EPS
                        and room["y"] - EPS <= tip[1] <= room["y"] + room["h"] + EPS):
                    errors.append(f"door {index}: sweep crosses target room boundary")
                    break
        level = rooms[a].get("floor_level_z_m", 0)
        for previous_index, previous_level, previous in poses:
            if abs(level - previous_level) < EPS and sweep_overlap(pose, previous):
                errors.append(f"doors {previous_index}/{index}: overlapping sweep envelopes")
        poses.append((index, level, pose))
    reached = {-1}
    pending = [-1]
    while pending:
        node = pending.pop()
        neighbors = (i for i in rooms if -1 in graph[i]) if node == -1 else graph[node]
        for neighbor in neighbors:
            if neighbor not in reached:
                reached.add(neighbor)
                pending.append(neighbor)
    for room_id, room in rooms.items():
        if room_id not in reached:
            errors.append(f"room {room_id}: unreachable from exterior")
        if room["kind"] == "escalera" and room_id not in vertical_rooms:
            errors.append(f"room {room_id}: staircase without a vertical connection")
    return errors


def shared_rect_area(a: dict, b: dict) -> float:
    return math.prod(max(0, min(a[k] + a[s], b[k] + b[s]) - max(a[k], b[k]))
                     for k, s in (("x", "w"), ("y", "h")))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=ROOT / "scenarios/playable")
    args = parser.parse_args()
    paths = sorted(args.directory.glob("preset_*.json"))
    if not paths:
        print("FAIL: no playable homes")
        return 1
    failed = 0
    for path in paths:
        errors = audit(json.loads(path.read_text(encoding="utf-8")))
        print(f"{path.name}: {'FAIL' if errors else 'PASS'}")
        for error in errors:
            print("  " + error)
        failed += bool(errors)
    return int(bool(failed))


if __name__ == "__main__":
    raise SystemExit(main())
