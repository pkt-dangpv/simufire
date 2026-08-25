"""Audit single ownership of tracked Godot primary UIDs.

This is a repository identity check. It does not claim that Godot imports,
loads, or executes any resource successfully.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


UID_TEXT = re.compile(r"uid://[A-Za-z0-9]+\Z")
UID_SIDECAR = re.compile(rb"(uid://[A-Za-z0-9]+)(?:\r?\n)?\Z")
HEADER = re.compile(r"^\[(gd_resource|gd_scene)(.*)\]$")
DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[2]


class AuditOperationalError(RuntimeError):
    """The inventory could not be evaluated completely."""


def _path_key(value: str) -> bytes:
    return value.encode("utf-8", errors="surrogateescape")


def _run_git(repo_root: Path, *args: str) -> bytes:
    try:
        completed = subprocess.run(
            ["git", "-C", str(repo_root), *args],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as exc:
        raise AuditOperationalError(f"cannot execute git: {exc}") from exc
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise AuditOperationalError(f"git {' '.join(args)} failed: {detail}")
    return completed.stdout


def _repository_identity(repo_root: Path) -> tuple[Path, str]:
    resolved = repo_root.resolve()
    top_level_raw = _run_git(resolved, "rev-parse", "--show-toplevel")
    try:
        top_level = Path(top_level_raw.decode("utf-8").strip()).resolve()
    except UnicodeDecodeError as exc:
        raise AuditOperationalError("git repository root is not valid UTF-8") from exc
    if top_level != resolved:
        raise AuditOperationalError(
            f"repository root is ambiguous: requested {resolved}, git reports {top_level}"
        )
    checkpoint = _run_git(resolved, "rev-parse", "HEAD").decode("ascii").strip()
    if not re.fullmatch(r"[0-9a-f]{40}", checkpoint):
        raise AuditOperationalError(f"invalid HEAD object id: {checkpoint!r}")
    return resolved, checkpoint


def discover_tracked_candidates(repo_root: Path) -> list[str]:
    raw = _run_git(
        repo_root,
        "ls-files",
        "-z",
        "--",
        "*.gd.uid",
        "*.tres",
        "*.tscn",
    )
    chunks = raw.split(b"\0")
    if chunks and chunks[-1] == b"":
        chunks.pop()
    try:
        paths = [chunk.decode("utf-8", errors="surrogateescape").replace("\\", "/") for chunk in chunks]
    except UnicodeError as exc:
        raise AuditOperationalError(f"tracked path cannot be decoded: {exc}") from exc
    if len(paths) != len(set(paths)):
        raise AuditOperationalError("git returned duplicate candidate paths")
    paths.sort(key=_path_key)
    if not paths:
        raise AuditOperationalError("tracked Godot UID candidate inventory is empty")
    return paths


def _header_attributes(line: str) -> tuple[str, dict[str, list[str]]]:
    match = HEADER.fullmatch(line)
    if not match:
        raise ValueError("first non-empty line is not a valid Godot resource/scene header")
    kind, body = match.groups()
    attributes: dict[str, list[str]] = defaultdict(list)
    index = 0
    while index < len(body):
        while index < len(body) and body[index].isspace():
            index += 1
        if index == len(body):
            break
        key_match = re.match(r"[A-Za-z_][A-Za-z0-9_]*", body[index:])
        if key_match is None:
            raise ValueError(f"malformed header attribute near {body[index:]!r}")
        key = key_match.group(0)
        index += len(key)
        if index >= len(body) or body[index] != "=":
            raise ValueError(f"header attribute {key!r} has no value")
        index += 1
        if index >= len(body):
            raise ValueError(f"header attribute {key!r} has an empty value")
        if body[index] == '"':
            start = index
            index += 1
            escaped = False
            while index < len(body):
                char = body[index]
                if char == '"' and not escaped:
                    index += 1
                    break
                if char == "\\" and not escaped:
                    escaped = True
                else:
                    escaped = False
                index += 1
            else:
                raise ValueError(f"header attribute {key!r} has an unterminated quote")
            value = body[start:index]
        else:
            start = index
            while index < len(body) and not body[index].isspace():
                index += 1
            value = body[start:index]
        if index < len(body) and not body[index].isspace():
            raise ValueError(f"malformed delimiter after header attribute {key!r}")
        attributes[key].append(value)
    return kind, attributes


def parse_primary_uid(relative_path: str, raw: bytes) -> str | None:
    if relative_path.endswith(".gd.uid"):
        match = UID_SIDECAR.fullmatch(raw)
        if match is None:
            raise ValueError("sidecar must contain exactly one ASCII UID token and optional newline")
        return match.group(1).decode("ascii")

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"resource is not valid UTF-8: {exc}") from exc
    line = next((item for item in text.splitlines() if item.strip()), None)
    if line is None:
        raise ValueError("resource is empty")
    _kind, attributes = _header_attributes(line)
    uid_values = attributes.get("uid", [])
    if len(uid_values) > 1:
        raise ValueError("resource header contains duplicate primary uid attributes")
    if not uid_values:
        return None
    quoted = uid_values[0]
    if len(quoted) < 2 or not quoted.startswith('"') or not quoted.endswith('"'):
        raise ValueError("primary uid must be quoted")
    uid = quoted[1:-1]
    if UID_TEXT.fullmatch(uid) is None:
        raise ValueError(f"invalid primary uid token: {uid!r}")
    return uid


def audit_paths(repo_root: Path, paths: Iterable[str], checkpoint: str) -> dict[str, Any]:
    ordered_paths = sorted(paths, key=_path_key)
    if not ordered_paths:
        raise AuditOperationalError("tracked Godot UID candidate inventory is empty")
    if len(ordered_paths) != len(set(ordered_paths)):
        raise AuditOperationalError("candidate inventory contains duplicate paths")

    records: list[dict[str, Any]] = []
    malformed: list[dict[str, str]] = []
    no_primary_uid: list[str] = []
    for relative_path in ordered_paths:
        path = repo_root / Path(relative_path)
        try:
            raw = path.read_bytes()
        except OSError as exc:
            raise AuditOperationalError(f"cannot read {relative_path}: {exc}") from exc
        try:
            uid = parse_primary_uid(relative_path, raw)
        except ValueError as exc:
            malformed.append({"path": relative_path, "reason": str(exc)})
            continue
        if uid is None:
            no_primary_uid.append(relative_path)
            continue
        records.append(
            {
                "path": relative_path,
                "uid": uid,
                "byte_length": len(raw),
                "sha256": hashlib.sha256(raw).hexdigest(),
            }
        )

    records.sort(key=lambda item: _path_key(item["path"]))
    malformed.sort(key=lambda item: _path_key(item["path"]))
    no_primary_uid.sort(key=_path_key)
    owners: dict[str, list[str]] = defaultdict(list)
    for record in records:
        owners[record["uid"]].append(record["path"])
    duplicates = [
        {"uid": uid, "paths": sorted(paths_for_uid, key=_path_key)}
        for uid, paths_for_uid in owners.items()
        if len(paths_for_uid) > 1
    ]
    duplicates.sort(key=lambda item: _path_key(item["uid"]))

    tree_text = "".join(
        f"{item['path']}\t{item['uid']}\t{item['sha256']}\n" for item in records
    )
    tree_bytes = tree_text.encode("utf-8", errors="surrogateescape")
    failed = bool(malformed or duplicates)
    return {
        "schema": "simufire.godot_primary_uid_audit.v1",
        "checkpoint": checkpoint,
        "repo_root": repo_root.as_posix(),
        "ordering": "ordinal UTF-8 byte order",
        "tree_contract": "relative_path<TAB>uid<TAB>lowercase_exact_byte_sha256<LF>",
        "candidate_count": len(ordered_paths),
        "primary_uid_count": len(records),
        "no_primary_uid_count": len(no_primary_uid),
        "malformed_count": len(malformed),
        "duplicate_group_count": len(duplicates),
        "records": records,
        "no_primary_uid": no_primary_uid,
        "malformed": malformed,
        "duplicate_groups": duplicates,
        "tree_manifest_bytes": len(tree_bytes),
        "tree_sha256": hashlib.sha256(tree_bytes).hexdigest(),
        "verdict": "FAIL" if failed else "PASS",
        "check_exit_code": 1 if failed else 0,
    }


def audit_repository(repo_root: Path = DEFAULT_REPO_ROOT) -> dict[str, Any]:
    resolved, checkpoint = _repository_identity(repo_root)
    return audit_paths(resolved, discover_tracked_candidates(resolved), checkpoint)


def json_bytes(result: dict[str, Any]) -> bytes:
    return (json.dumps(result, indent=2, ensure_ascii=True) + "\n").encode("utf-8")


def write_json_atomic(path: Path, result: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix=f".{path.name}.", suffix=".tmp", dir=path.parent, delete=False
        ) as handle:
            temporary = Path(handle.name)
            handle.write(json_bytes(result))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=DEFAULT_REPO_ROOT)
    parser.add_argument("--json", "--json-out", dest="json_out", type=Path)
    parser.add_argument("--check", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = audit_repository(args.repo)
        if args.json_out is not None:
            write_json_atomic(args.json_out, result)
    except AuditOperationalError as exc:
        print(f"Godot primary UID audit operational error: {exc}", file=sys.stderr)
        return 2

    print(
        "Godot primary UID audit: "
        f"{result['candidate_count']} candidates, "
        f"{result['primary_uid_count']} primary UIDs, "
        f"{result['malformed_count']} malformed, "
        f"{result['duplicate_group_count']} duplicate groups"
    )
    for group in result["duplicate_groups"]:
        print(f"  {group['uid']}: {', '.join(group['paths'])}")
    if args.check:
        return int(result["check_exit_code"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
