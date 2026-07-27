"""Every Godot fixture must fail closed.

`SceneTree.quit()` only *requests* a shutdown; it returns and execution
continues. Three shapes therefore let a failing fixture still report success:

1. `if _failed: quit(1)` followed by an unconditional PASS print, because the
   `quit(1)` falls through and the later `quit(0)` overwrites the exit code;
2. a helper that calls `quit(nonzero)` and returns to a caller that goes on to
   print the PASS marker;
3. a bare GDScript `assert()`, which halts the function without ever reaching
   `quit()`, so the process hangs instead of exiting non-zero.

All three were present in this repository and were fixed. These contracts stop
them coming back. They are static, so they cost nothing in CI; the empirical
proof is the negative-control sweep documented alongside the fix.
"""
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "tests" / "fixtures"
FIXTURES = sorted(FIXTURE_DIR.glob("*.gd"))

PASS_MARKER = "PASS"


def _strip_comments(source: str) -> str:
    out = []
    for line in source.splitlines():
        quote_count = 0
        cut = len(line)
        for index, char in enumerate(line):
            if char == '"':
                quote_count += 1
            elif char == "#" and quote_count % 2 == 0:
                cut = index
                break
        out.append(line[:cut])
    return "\n".join(out)


def _functions(lines):
    starts = [i for i, l in enumerate(lines) if l.startswith("func ")]
    for position, start in enumerate(starts):
        end = starts[position + 1] if position + 1 < len(starts) else len(lines)
        name = lines[start].split("(")[0].replace("func ", "").strip()
        yield name, start, end


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip())


def _quit_argument(line: str) -> str | None:
    if "quit(" not in line:
        return None
    tail = line.split("quit(", 1)[1]
    depth, arg = 1, []
    for char in tail:
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                break
        arg.append(char)
    return "".join(arg).strip()


def _reachable_after(lines, quit_index, end):
    """Lines reachable sequentially after a quit, skipping else/elif arms.

    A `quit(1)` inside `if failed:` cannot reach the `else:` arm, so a fixture
    that puts its PASS print there is already safe and must not be flagged.
    """
    reachable = []
    quit_indent = _indent(lines[quit_index])
    index = quit_index + 1
    while index < end:
        line = lines[index]
        if not line.strip():
            index += 1
            continue
        indent = _indent(line)
        if indent >= quit_indent:
            reachable.append(index)
            index += 1
            continue
        stripped = line.strip()
        if stripped.startswith("else:") or stripped.startswith("elif "):
            arm_indent = indent
            index += 1
            while index < end and (
                not lines[index].strip() or _indent(lines[index]) > arm_indent
            ):
                index += 1
            continue
        reachable.append(index)
        index += 1
    return reachable


def _fixture_id(path: Path) -> str:
    return path.name


def test_fixture_directory_is_not_empty():
    assert FIXTURES, "no Godot fixtures found to audit"


@pytest.mark.parametrize("path", FIXTURES, ids=_fixture_id)
def test_failing_quit_cannot_reach_the_pass_marker(path: Path):
    """Shape 1: a fall-through `quit(nonzero)` must not reach PASS or quit(0)."""
    lines = _strip_comments(path.read_text(encoding="utf-8")).splitlines()
    for name, start, end in _functions(lines):
        for index in range(start + 1, end):
            argument = _quit_argument(lines[index])
            if argument is None or argument in ("", "0"):
                continue
            tail = _reachable_after(lines, index, end)
            if tail and lines[tail[0]].strip() == "return":
                continue
            for candidate in tail:
                statement = lines[candidate].strip()
                if statement == "return":
                    break
                assert PASS_MARKER not in statement or "print" not in statement, (
                    f"{path.name}:{index + 1} in {name}(): quit({argument}) "
                    f"falls through to the PASS marker at line {candidate + 1}"
                )
                candidate_argument = _quit_argument(lines[candidate])
                assert candidate_argument not in ("", "0"), (
                    f"{path.name}:{index + 1} in {name}(): quit({argument}) "
                    f"falls through to quit(0) at line {candidate + 1}, which "
                    f"overwrites the failing exit code"
                )


@pytest.mark.parametrize("path", FIXTURES, ids=_fixture_id)
def test_only_the_exit_function_may_call_quit(path: Path):
    """Shape 2: a helper that quits still returns to a caller that reaches PASS.

    Failures must be recorded in a flag and the exit taken at a single guarded
    site, so no helper may call `quit(nonzero)`.
    """
    lines = _strip_comments(path.read_text(encoding="utf-8")).splitlines()
    exit_function = None
    for name, start, end in _functions(lines):
        for index in range(start, end):
            if "print" in lines[index] and PASS_MARKER in lines[index]:
                exit_function = name
    if exit_function is None:
        pytest.skip("fixture has no PASS marker")
    for name, start, end in _functions(lines):
        if name == exit_function:
            continue
        for index in range(start, end):
            argument = _quit_argument(lines[index])
            if argument is None or argument in ("", "0"):
                continue
            raise AssertionError(
                f"{path.name}:{index + 1}: helper {name}() calls "
                f"quit({argument}) and then returns to {exit_function}(), "
                f"which still reaches the PASS marker. Set a failure flag "
                f"instead and guard the single exit."
            )


@pytest.mark.parametrize("path", FIXTURES, ids=_fixture_id)
def test_no_bare_gdscript_assert(path: Path):
    """Shape 3: `assert()` halts the function without ever calling quit().

    The process then hangs until the harness timeout instead of exiting
    non-zero, which reads as an infrastructure failure rather than a test
    failure.
    """
    lines = _strip_comments(path.read_text(encoding="utf-8")).splitlines()
    for index, line in enumerate(lines):
        stripped = line.strip()
        assert not stripped.startswith("assert("), (
            f"{path.name}:{index + 1}: bare assert() halts the fixture without "
            f"calling quit(), so a failure hangs instead of exiting non-zero. "
            f"Use a failure-flag helper."
        )


@pytest.mark.parametrize("path", FIXTURES, ids=_fixture_id)
def test_fixture_with_a_pass_marker_has_a_failure_channel(path: Path):
    """A fixture that can only succeed is not a test."""
    source = _strip_comments(path.read_text(encoding="utf-8"))
    if "print" not in source or PASS_MARKER not in source:
        pytest.skip("fixture has no PASS marker")
    assert "_failed" in source, (
        f"{path.name}: has a PASS marker but no failure flag, so nothing can "
        f"stop it reporting success"
    )
    assert "quit(1)" in source, (
        f"{path.name}: has a PASS marker but never exits non-zero"
    )
