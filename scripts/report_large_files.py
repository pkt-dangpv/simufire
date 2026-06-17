"""Report large source files by physical line count.

This helper is intentionally read-only and dependency-free. It is meant to keep
the large-file inventory honest while refactors are planned.
"""

from __future__ import annotations

import argparse
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_EXTENSIONS = {".gd", ".py", ".ps1", ".tscn", ".tres", ".md"}
SKIP_PARTS = {".git", ".godot", "__pycache__"}


def iter_files(extensions: set[str]) -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_PARTS for part in path.parts):
            continue
        if path.suffix.lower() in extensions:
            files.append(path)
    return files


def count_lines(path: Path) -> int:
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        return sum(1 for _ in handle)


def main() -> int:
    parser = argparse.ArgumentParser(description="Report large files by line count.")
    parser.add_argument("--min-lines", type=int, default=500)
    parser.add_argument("--top", type=int, default=40)
    parser.add_argument(
        "--extensions",
        default=",".join(sorted(DEFAULT_EXTENSIONS)),
        help="Comma-separated extensions to include, e.g. .gd,.py",
    )
    args = parser.parse_args()

    extensions = {item.strip().lower() for item in args.extensions.split(",") if item.strip()}
    rows: list[tuple[int, Path]] = []
    for path in iter_files(extensions):
        lines = count_lines(path)
        if lines >= args.min_lines:
            rows.append((lines, path.relative_to(ROOT)))

    rows.sort(reverse=True)

    print("| Lines | File |")
    print("|---:|---|")
    for lines, path in rows[: args.top]:
        print(f"| {lines} | `{path.as_posix()}` |")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
