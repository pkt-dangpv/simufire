#!/usr/bin/env python3
"""Build a deterministic, parser-aware inventory of SimuFire scripts."""

from __future__ import annotations

import argparse
import ast
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import subprocess
from typing import Iterable


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_SUFFIXES = {".gd", ".py", ".ps1", ".psm1", ".sh", ".bat", ".cmd"}
RESOURCE_SUFFIXES = {".tscn", ".tres", ".godot"}
WRITE_ROOTS = (
    "room",
    "building",
    "thermal_system",
    "gas_exchange_system",
    "oxygen_exchange_system",
    "zone_fire_solver",
    "fire",
    "state",
)
WRITE_RE = re.compile(
    rf"\b({'|'.join(WRITE_ROOTS)})\.([A-Za-z_][A-Za-z0-9_]*)\s*"
    r"(\+=|-=|\*=|/=|(?<![=!<>])=(?!=))"
)
RESOURCE_RE = re.compile(r"res://([^\"']+\.(?:gd|py|ps1|psm1|sh|bat|cmd))", re.I)
CLASS_NAME_RE = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
FUNCTION_RE = re.compile(r"^\s*func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
POWERSHELL_FILESYSTEM_RE = re.compile(
    r"\b(?:Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Move-Item|Copy-Item|"
    r"Rename-Item|Compress-Archive|Expand-Archive)\b",
    re.I,
)
POWERSHELL_PROCESS_RE = re.compile(r"\b(?:Start-Process|Stop-Process|Invoke-Expression)\b", re.I)


def _bytewise(values: Iterable[str]) -> list[str]:
    return sorted(values, key=lambda value: value.encode("utf-8"))


def repository_paths(root: Path = ROOT) -> list[str]:
    raw = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root,
    )
    paths = (part.decode("utf-8") for part in raw.split(b"\0") if part)
    return _bytewise(path for path in paths if (root / path).is_file())


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-8", "cp1252"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise UnicodeError(f"cannot decode tracked script: {path}")


def language_for(path: str) -> str:
    return {
        ".gd": "GDScript",
        ".py": "Python",
        ".ps1": "PowerShell",
        ".psm1": "PowerShell",
        ".sh": "shell",
        ".bat": "batch",
        ".cmd": "batch",
    }[Path(path).suffix.lower()]


def scope_for(path: str) -> tuple[str, bool]:
    if path.startswith("external/fds/") and Path(path).suffix.lower() in {".bat", ".cmd"}:
        return "external_reference_runner", False
    if path.startswith("tests/"):
        return "test", True
    if path.startswith(("sim/validation/", "scripts/simulation/", "truth/")):
        return "validation", True
    if path.startswith(("sim/", "Main.gd", "view/", "ui/", "editor/", "scenes/")):
        return "runtime_or_application", True
    if path.startswith(("scripts/", "tools/", "external/fds/")):
        return "tooling", True
    return "repository_support", True


def authority_relevance_for(scope: str) -> str:
    return {
        "runtime_or_application": "runtime_behavior",
        "validation": "validation_contract",
        "test": "verification_only",
        "tooling": "tooling_or_packaging",
        "external_reference_runner": "external_reference_only",
        "repository_support": "repository_support",
    }[scope]


def _gd_without_comments(source: str) -> str:
    output: list[str] = []
    for line in source.splitlines(keepends=True):
        quote = ""
        escaped = False
        kept: list[str] = []
        for char in line:
            if quote:
                kept.append(char)
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == quote:
                    quote = ""
                continue
            if char in {'"', "'"}:
                quote = char
                kept.append(char)
            elif char == "#":
                kept.extend("\n" if line.endswith("\n") else "")
                break
            else:
                kept.append(char)
        output.extend(kept)
    return "".join(output)


def _gd_code_only(source: str) -> str:
    source = _gd_without_comments(source)
    output: list[str] = []
    quote = ""
    escaped = False
    for char in source:
        if quote:
            output.append("\n" if char == "\n" else " ")
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char in {'"', "'"}:
            quote = char
            output.append(" ")
        else:
            output.append(char)
    return "".join(output)


def _writer_phase_hint(function: str) -> str:
    if function == "<module>":
        return "module_scope"
    lowered = function.lower()
    if any(token in lowered for token in ("reset", "clear", "begin_step", "begin_tick")):
        return "reset"
    if any(token in lowered for token in ("diag", "shadow", "metric", "snapshot", "export", "log_")):
        return "diagnostic_or_shadow"
    if any(
        token in lowered
        for token in ("_init", "initialize", "configure", "create", "build", "load", "add_room")
    ):
        return "construction"
    return "runtime"


def gd_write_candidates(path: str, source: str) -> list[dict[str, object]]:
    if not path.startswith(("sim/", "Main.gd")):
        return []
    candidates: list[dict[str, object]] = []
    current_function = "<module>"
    for line_number, line in enumerate(_gd_code_only(source).splitlines(), 1):
        function_match = FUNCTION_RE.match(line)
        if function_match:
            current_function = function_match.group(1)
        for match in WRITE_RE.finditer(line):
            candidates.append(
                {
                    "path": path,
                    "line": line_number,
                    "function": current_function,
                    "phase_hint": _writer_phase_hint(current_function),
                    "root": match.group(1),
                    "field": match.group(2),
                    "operator": match.group(3),
                }
            )
    return candidates


def _python_module(path: str) -> str:
    module = path[:-3].replace("/", ".")
    return module[:-9] if module.endswith(".__init__") else module


def _python_imports(path: str, tree: ast.AST, modules: dict[str, str]) -> set[str]:
    dependencies: set[str] = set()
    package = _python_module(path).split(".")[:-1]
    for node in ast.walk(tree):
        names: list[str] = []
        if isinstance(node, ast.Import):
            names = [alias.name for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            prefix = package[: max(0, len(package) - node.level + 1)] if node.level else []
            base = ".".join(prefix + ([node.module] if node.module else []))
            names = [base] if base else []
        for name in names:
            parts = name.split(".")
            for end in range(len(parts), 0, -1):
                candidate = ".".join(parts[:end])
                if candidate in modules:
                    dependencies.add(modules[candidate])
                    break
    return dependencies


def _python_entrypoint(path: str, tree: ast.Module) -> str:
    if path.startswith("tests/test_"):
        return "pytest_module"
    for node in tree.body:
        if isinstance(node, ast.If) and isinstance(node.test, ast.Compare):
            if "__name__" in ast.unparse(node.test) and "__main__" in ast.unparse(node.test):
                return "cli_main_guard"
    passive = (ast.Import, ast.ImportFrom, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)
    if any(not isinstance(node, passive) for node in tree.body):
        return "top_level_executable"
    return "imported_module"


def _call_name(node: ast.Call) -> str:
    parts: list[str] = []
    target: ast.AST = node.func
    while isinstance(target, ast.Attribute):
        parts.append(target.attr)
        target = target.value
    if isinstance(target, ast.Name):
        parts.append(target.id)
    return ".".join(reversed(parts))


def python_side_effects(tree: ast.AST) -> list[str]:
    effects: set[str] = set()
    filesystem_names = {
        "open", "Path.write_text", "Path.write_bytes", "Path.mkdir", "Path.unlink",
        "Path.rename", "Path.replace", "shutil.copy", "shutil.copy2", "shutil.copytree",
        "shutil.move", "shutil.rmtree", "json.dump",
    }
    filesystem_methods = {
        "write_text", "write_bytes", "mkdir", "unlink", "rename", "replace",
    }
    process_prefixes = ("subprocess.", "os.system")
    network_prefixes = ("requests.", "urllib.request.", "socket.")
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = _call_name(node)
        if (
            name in filesystem_names
            or name in filesystem_methods
            or any(name.endswith(f".{item}") for item in filesystem_names)
        ):
            effects.add("filesystem")
        if name.startswith(process_prefixes):
            effects.add("external_process")
        if name.startswith(network_prefixes):
            effects.add("network")
        if name in {"print", "logging.debug", "logging.info", "logging.warning", "logging.error"}:
            effects.add("console_or_log_output")
    return _bytewise(effects) or ["none_detected"]


def script_side_effects(
    path: str,
    language: str,
    source: str,
    python_tree: ast.AST | None,
    has_state_writes: bool,
) -> list[str]:
    effects: set[str] = set()
    if has_state_writes:
        effects.add("motor_state_write")
    if language == "Python" and python_tree is not None:
        effects.update(item for item in python_side_effects(python_tree) if item != "none_detected")
    elif language == "GDScript":
        code = _gd_code_only(source)
        if re.search(r"\b(?:FileAccess|DirAccess)\b", code):
            effects.add("filesystem")
        if re.search(r"\bOS\.(?:execute|create_process|kill)\s*\(", code):
            effects.add("external_process")
        if re.search(r"\b(?:print|printerr|push_warning|push_error)\s*\(", code):
            effects.add("console_or_log_output")
    elif language == "PowerShell":
        if POWERSHELL_FILESYSTEM_RE.search(source):
            effects.add("filesystem")
        if POWERSHELL_PROCESS_RE.search(source) or re.search(r"(?m)^\s*&\s+", source):
            effects.add("external_process")
        if re.search(r"\b(?:Write-Host|Write-Output|Write-Warning|Write-Error)\b", source, re.I):
            effects.add("console_or_log_output")
    elif language == "batch":
        effects.add("external_process")
        if re.search(r"(?im)^\s*(?:echo|rem)\b", source):
            effects.add("console_or_log_output")
    return _bytewise(effects) or ["none_detected"]


def static_test_references(
    target: str,
    scripts: list[str],
    texts: dict[str, str],
    inbound: dict[str, set[str]],
) -> list[str]:
    if target.startswith("tests/"):
        return [target]
    references = {caller for caller in inbound[target] if caller.startswith("tests/")}
    markers = {target, Path(target).name, Path(target).stem}
    class_match = CLASS_NAME_RE.search(_gd_code_only(texts[target])) if target.endswith(".gd") else None
    if class_match:
        markers.add(class_match.group(1))
    for test_path in scripts:
        if not test_path.startswith("tests/"):
            continue
        source = texts[test_path]
        if any(marker in source for marker in markers):
            references.add(test_path)
    return _bytewise(references)


def _tarjan(nodes: list[str], edges: dict[str, set[str]]) -> list[list[str]]:
    index = 0
    stack: list[str] = []
    on_stack: set[str] = set()
    indices: dict[str, int] = {}
    low: dict[str, int] = {}
    components: list[list[str]] = []

    def visit(node: str) -> None:
        nonlocal index
        indices[node] = low[node] = index
        index += 1
        stack.append(node)
        on_stack.add(node)
        for target in edges.get(node, set()):
            if target not in indices:
                visit(target)
                low[node] = min(low[node], low[target])
            elif target in on_stack:
                low[node] = min(low[node], indices[target])
        if low[node] != indices[node]:
            return
        component: list[str] = []
        while True:
            target = stack.pop()
            on_stack.remove(target)
            component.append(target)
            if target == node:
                break
        if len(component) > 1:
            components.append(_bytewise(component))

    for node in nodes:
        if node not in indices:
            visit(node)
    return sorted(components, key=lambda group: [item.encode("utf-8") for item in group])


def build_inventory(root: Path = ROOT) -> dict[str, object]:
    repository = repository_paths(root)
    scripts = [path for path in repository if Path(path).suffix.lower() in SCRIPT_SUFFIXES]
    texts = {path: read_text(root / path) for path in scripts}
    script_set = set(scripts)
    modules = {_python_module(path): path for path in scripts if path.endswith(".py")}

    class_owners: dict[str, list[str]] = defaultdict(list)
    for path in scripts:
        if path.endswith(".gd"):
            match = CLASS_NAME_RE.search(_gd_code_only(texts[path]))
            if match:
                class_owners[match.group(1)].append(path)
    class_map = {name: owners[0] for name, owners in class_owners.items() if len(owners) == 1}

    resource_callers: dict[str, set[str]] = defaultdict(set)
    for path in repository:
        if Path(path).suffix.lower() not in RESOURCE_SUFFIXES:
            continue
        source = read_text(root / path)
        for target in RESOURCE_RE.findall(_gd_without_comments(source)):
            normalized = target.replace("\\", "/")
            if normalized in script_set:
                resource_callers[normalized].add(path)

    hard_edges: dict[str, set[str]] = {path: set() for path in scripts}
    symbolic_edges: dict[str, set[str]] = {path: set() for path in scripts}
    parser_failures: list[dict[str, object]] = []
    entrypoints: dict[str, str] = {}
    python_trees: dict[str, ast.AST] = {}
    writers: list[dict[str, object]] = []

    for path in scripts:
        language = language_for(path)
        source = texts[path]
        if language == "Python":
            try:
                tree = ast.parse(source, filename=path)
            except SyntaxError as exc:
                parser_failures.append({"path": path, "line": exc.lineno, "message": exc.msg})
                entrypoints[path] = "python_parse_failure"
            else:
                python_trees[path] = tree
                hard_edges[path].update(_python_imports(path, tree, modules))
                entrypoints[path] = _python_entrypoint(path, tree)
        elif language == "GDScript":
            no_comments = _gd_without_comments(source)
            code = _gd_code_only(source)
            for target in RESOURCE_RE.findall(no_comments):
                normalized = target.replace("\\", "/")
                if normalized in script_set:
                    hard_edges[path].add(normalized)
            for class_name, target in class_map.items():
                if target != path and re.search(rf"\b{re.escape(class_name)}\b", code):
                    symbolic_edges[path].add(target)
            hooks = re.findall(r"^\s*func\s+(_ready|_process|_physics_process|_init)\s*\(", code, re.M)
            if path == "Main.gd":
                entrypoints[path] = "application_main"
            elif path.startswith("tests/fixtures/"):
                entrypoints[path] = "godot_fixture"
            elif path.startswith("tools/"):
                entrypoints[path] = "godot_cli_tool"
            elif re.search(r"^\s*@tool\b", code, re.M):
                entrypoints[path] = "editor_tool"
            elif hooks:
                entrypoints[path] = "godot_lifecycle:" + ",".join(sorted(set(hooks)))
            elif resource_callers.get(path):
                entrypoints[path] = "scene_or_resource_script"
            else:
                entrypoints[path] = "loaded_class_or_resource"
            writers.extend(gd_write_candidates(path, source))
        elif language == "batch":
            entrypoints[path] = "external_command_script"
        else:
            entrypoints[path] = "command_script"
        hard_edges[path].discard(path)
        symbolic_edges[path].discard(path)

    inbound: dict[str, set[str]] = defaultdict(set)
    for caller, targets in hard_edges.items():
        for target in targets:
            inbound[target].add(caller)
    for caller, targets in symbolic_edges.items():
        for target in targets:
            inbound[target].add(caller)
    for target, callers in resource_callers.items():
        inbound[target].update(callers)

    rows: list[dict[str, object]] = []
    writers_by_path: dict[str, list[dict[str, object]]] = defaultdict(list)
    for writer in writers:
        writers_by_path[str(writer["path"])].append(writer)
    for path in scripts:
        scope, in_scope = scope_for(path)
        tests = static_test_references(path, scripts, texts, inbound)
        rows.append(
            {
                "path": path,
                "sha256": hashlib.sha256((root / path).read_bytes()).hexdigest(),
                "bytes": (root / path).stat().st_size,
                "language": language_for(path),
                "scope": scope,
                "in_motor_audit_scope": in_scope,
                "authority_relevance": authority_relevance_for(scope),
                "entrypoint": entrypoints[path],
                "hard_dependencies": _bytewise(hard_edges[path]),
                "symbolic_dependencies": _bytewise(symbolic_edges[path]),
                "callers": _bytewise(inbound[path]),
                "side_effects": script_side_effects(
                    path,
                    language_for(path),
                    texts[path],
                    python_trees.get(path),
                    bool(writers_by_path[path]),
                ),
                "test_coverage": {
                    "status": "self_test" if path.startswith("tests/") else (
                        "static_reference_found" if tests else "no_static_test_reference"
                    ),
                    "static_test_references": tests,
                },
            }
        )

    orphan_candidates = [
        row["path"]
        for row in rows
        if row["in_motor_audit_scope"]
        and not row["callers"]
        and row["entrypoint"] in {"imported_module", "loaded_class_or_resource"}
    ]
    duplicate_classes = {
        name: _bytewise(owners) for name, owners in class_owners.items() if len(owners) > 1
    }
    hard_cycles = _tarjan(scripts, hard_edges)
    return {
        "schema": "simufire.script_structure_audit.v1",
        "checkpoint": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True
        ).strip(),
        "summary": {
            "repository_files": len(repository),
            "repository_scripts": len(scripts),
            "in_scope_scripts": sum(bool(row["in_motor_audit_scope"]) for row in rows),
            "counts_by_language": {
                language: sum(row["language"] == language for row in rows)
                for language in _bytewise({str(row["language"]) for row in rows})
            },
            "python_parse_failures": parser_failures,
            "duplicate_gdscript_class_names": duplicate_classes,
            "hard_dependency_cycles": hard_cycles,
            "orphan_candidates": _bytewise(str(path) for path in orphan_candidates),
            "state_writer_candidates": len(writers),
        },
        "scripts": rows,
        "state_writers": writers,
        "limitations": [
            "Godot parser/import and PowerShell AST results are separate native-runtime gates.",
            "Symbolic GDScript references are callers, not hard load edges or cycle proof.",
            "Dynamic dispatch and state-writer ownership require manual classification.",
            "Static test references are discoverability evidence, not executed line or branch coverage.",
            "Side-effect categories are conservative parser/token candidates, not proof that a path executes.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = build_inventory()
    payload = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8", newline="\n")
    else:
        print(payload, end="")
    summary = result["summary"]
    return 1 if any(
        (
            summary["python_parse_failures"],
            summary["duplicate_gdscript_class_names"],
            summary["hard_dependency_cycles"],
        )
    ) else 0


if __name__ == "__main__":
    raise SystemExit(main())
