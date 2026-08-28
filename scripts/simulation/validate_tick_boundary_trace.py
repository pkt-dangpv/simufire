"""Validate the ordered P1R2 runtime trace without inspecting source text."""

from __future__ import annotations

from collections import defaultdict
from typing import Any


def validate_trace(events: list[dict[str, Any]]) -> list[str]:
    failures: list[str] = []
    by_tick: dict[int, list[str]] = defaultdict(list)
    for index, event in enumerate(events):
        if not isinstance(event, dict):
            failures.append(f"event {index} is not an object")
            continue
        tick = event.get("tick")
        name = event.get("event")
        if not isinstance(tick, int) or tick < 1 or not isinstance(name, str):
            failures.append(f"event {index} has invalid tick/name")
            continue
        by_tick[tick].append(name)

    if len(by_tick) < 3:
        failures.append(f"expected first, steady and final ticks; found {len(by_tick)}")

    for tick, names in sorted(by_tick.items()):
        for required in ("tick_begin", "auxiliary_sync", "post_physics_mutation", "log_boundary"):
            if names.count(required) != 1:
                failures.append(f"tick {tick}: expected one {required}, found {names.count(required)}")
        if all(name in names for name in ("tick_begin", "auxiliary_sync", "post_physics_mutation")):
            if not names.index("tick_begin") < names.index("auxiliary_sync") < names.index(
                "post_physics_mutation"
            ):
                failures.append(f"tick {tick}: auxiliary sync is not before physics")
        if "post_physics_mutation" in names:
            boundary = names.index("post_physics_mutation")
            if "auxiliary_sync" in names[boundary + 1 :]:
                failures.append(f"tick {tick}: auxiliary sync occurs after physics")

    final_tick = max(by_tick, default=0)
    if final_tick:
        final_names = by_tick[final_tick]
        if final_names.count("final_snapshot") != 1:
            failures.append(
                f"tick {final_tick}: expected one final_snapshot, found "
                f"{final_names.count('final_snapshot')}"
            )
        elif final_names[-1] != "final_snapshot":
            failures.append(f"tick {final_tick}: final_snapshot is not the final event")
    return failures
