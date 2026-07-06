"""Check local Markdown links for missing targets.

External URLs, mail links, anchors within the same document, and image links are
ignored. The checker is intentionally lightweight so it can run in CI without
extra dependencies.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parent.parent
MD_LINK_RE = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
HISTORICAL_PARTS = {
    "archive",
    "audits",
    "literature",
    "sessions",
}
HISTORICAL_PREFIXES = (
    Path("sim/validation"),
)


def is_external(target: str) -> bool:
    lower = target.lower()
    return (
        lower.startswith("http://")
        or lower.startswith("https://")
        or lower.startswith("mailto:")
        or lower.startswith("app://")
    )


def normalize_target(raw: str) -> str:
    target = raw.strip()
    if not target:
        return ""
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    if " " in target and not target.startswith("#"):
        target = target.split(" ")[0]
    return unquote(target)


def is_historical(path: Path) -> bool:
    rel = path.relative_to(ROOT)
    if any(part in HISTORICAL_PARTS for part in rel.parts):
        return True
    return any(rel.is_relative_to(prefix) for prefix in HISTORICAL_PREFIXES)


def resolve_candidate(path: Path, target_path: str) -> Path | None:
    local_candidate = (path.parent / target_path).resolve()
    root_candidate = (ROOT / target_path).resolve()

    for candidate in (local_candidate, root_candidate):
        try:
            candidate.relative_to(ROOT)
        except ValueError:
            continue
        if candidate.exists():
            return candidate
    return None


def check_file(path: Path) -> list[str]:
    rel_path = path.relative_to(ROOT)
    text = path.read_text(encoding="utf-8", errors="replace")
    errors: list[str] = []

    for line_no, line in enumerate(text.splitlines(), start=1):
        for match in MD_LINK_RE.finditer(line):
            target = normalize_target(match.group(1))
            if not target or is_external(target) or target.startswith("#"):
                continue

            target_path = target.split("#", 1)[0]
            if not target_path:
                continue

            candidate = (path.parent / target_path).resolve()
            try:
                candidate.relative_to(ROOT)
            except ValueError:
                errors.append(f"{rel_path}:{line_no}: link escapes repo: {target}")
                continue

            if resolve_candidate(path, target_path) is None:
                errors.append(f"{rel_path}:{line_no}: missing link target: {target}")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Check local Markdown links.")
    parser.add_argument(
        "--all",
        action="store_true",
        help="Include historical audits, sessions, archive, literature and sim/validation docs.",
    )
    args = parser.parse_args()

    all_errors: list[str] = []
    for path in sorted(ROOT.rglob("*.md")):
        if ".git" in path.parts:
            continue
        # .claude/ es workspace de tooling (worktrees de sesiones spawneadas,
        # settings) — sus copias de docs no son parte del repo a lintear.
        if ".claude" in path.parts:
            continue
        if not args.all and is_historical(path):
            continue
        all_errors.extend(check_file(path))

    if all_errors:
        print("Markdown link check failed:")
        for error in all_errors:
            print(f"  - {error}")
        return 1

    print("Markdown link check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
