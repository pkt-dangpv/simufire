#!/usr/bin/env python3
"""Summarize passive Phase 3 projection traces emitted by the headless runner."""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


METRICS = (
    "ensure_mass_delta_kg",
    "ensure_energy_delta_kj",
    "temperature_projection_energy_delta_kj",
    "upper_cap_mass_delta_kg",
    "upper_cap_energy_delta_kj",
    "lower_projection_mass_delta_kg",
    "lower_projection_energy_delta_kj",
    "total_mass_delta_kg",
    "total_energy_delta_kj",
)


def load_events(path: Path) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"invalid JSON at {path}:{line_number}: {exc}") from exc
            if not isinstance(event, dict):
                raise ValueError(f"expected an object at {path}:{line_number}")
            events.append(event)
    if not events:
        raise ValueError(f"projection trace is empty: {path}")
    return events


def _finite_float(event: dict[str, Any], key: str) -> float:
    value = float(event.get(key, 0.0))
    if not math.isfinite(value):
        raise ValueError(f"non-finite {key} in projection trace")
    return value


def _peak(events: Iterable[dict[str, Any]], metric: str) -> dict[str, Any]:
    event = max(events, key=lambda item: abs(_finite_float(item, metric)))
    return {
        "value": _finite_float(event, metric),
        "sim_time_s": _finite_float(event, "sim_time_s"),
        "room_id": int(event.get("room_id", -1)),
        "call_index": int(event.get("call_index", -1)),
        "cause": str(event.get("cause", "unspecified")),
    }


def summarize(events: list[dict[str, Any]]) -> dict[str, Any]:
    by_step: dict[tuple[float, int], list[dict[str, Any]]] = defaultdict(list)
    for event in events:
        key = (_finite_float(event, "sim_time_s"), int(event.get("room_id", -1)))
        by_step[key].append(event)

    step_summaries: list[dict[str, Any]] = []
    for (sim_time_s, room_id), step_events in sorted(by_step.items()):
        ordered = sorted(step_events, key=lambda item: int(item.get("call_index", -1)))
        step_summaries.append(
            {
                "sim_time_s": sim_time_s,
                "room_id": room_id,
                "call_count": len(ordered),
                "causes": [str(item.get("cause", "unspecified")) for item in ordered],
                "total_mass_delta_kg": sum(
                    _finite_float(item, "total_mass_delta_kg") for item in ordered
                ),
                "total_energy_delta_kj": sum(
                    _finite_float(item, "total_energy_delta_kj") for item in ordered
                ),
            }
        )

    cause_counts = Counter(str(event.get("cause", "unspecified")) for event in events)
    call_counts = Counter(step["call_count"] for step in step_summaries)
    return {
        "event_count": len(events),
        "step_count": len(step_summaries),
        "cause_counts": dict(sorted(cause_counts.items())),
        "calls_per_step": {str(key): value for key, value in sorted(call_counts.items())},
        "metric_peaks": {metric: _peak(events, metric) for metric in METRICS},
        "step_mass_peak": max(
            step_summaries, key=lambda item: abs(item["total_mass_delta_kg"])
        ),
        "step_energy_peak": max(
            step_summaries, key=lambda item: abs(item["total_energy_delta_kj"])
        ),
    }


def _print_summary(summary: dict[str, Any]) -> None:
    print(
        "Projection trace: "
        f"{summary['event_count']} events, {summary['step_count']} room-steps"
    )
    print("Calls per room-step:", summary["calls_per_step"])
    print("Causes:")
    for cause, count in summary["cause_counts"].items():
        print(f"  {cause}: {count}")
    print("Absolute peaks:")
    for metric, peak in summary["metric_peaks"].items():
        print(
            f"  {metric}: {peak['value']:.9g} "
            f"at t={peak['sim_time_s']:.6g}s room={peak['room_id']} "
            f"call={peak['call_index']} cause={peak['cause']}"
        )
    for label in ("step_mass_peak", "step_energy_peak"):
        peak = summary[label]
        print(
            f"{label}: t={peak['sim_time_s']:.6g}s room={peak['room_id']} "
            f"dm={peak['total_mass_delta_kg']:.9g} kg "
            f"de={peak['total_energy_delta_kj']:.9g} kJ"
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="projection_trace.jsonl path")
    parser.add_argument("--json-out", type=Path, help="optional summary JSON path")
    args = parser.parse_args(argv)

    try:
        summary = summarize(load_events(args.trace))
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    _print_summary(summary)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
