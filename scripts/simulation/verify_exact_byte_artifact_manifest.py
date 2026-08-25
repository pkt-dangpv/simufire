"""Verify exact-byte artifact manifests and their bytewise path tree.

This tool verifies stored evidence. It never rewrites a source artifact or
normalizes line endings. A PASS says that every listed file matches and that
the declared aggregate tree uses UTF-8 byte ordering; it makes no claim about
the scientific meaning of the files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


PATH_FIELDS = ("relative_path", "path")
LENGTH_FIELDS = ("byte_length", "bytes")
HASH_FIELDS = ("sha256", "worktree_sha256")
TREE_FIELDS = ("source_tree_sha256", "tree_sha256")
SHA256 = re.compile(r"[0-9a-fA-F]{64}\Z")


class ManifestOperationalError(RuntimeError):
    """The manifest could not be evaluated completely and unambiguously."""


def _path_key(value: str) -> bytes:
    return value.encode("utf-8")


def _select_record_field(
    records: list[dict[str, Any]], candidates: Iterable[str], label: str
) -> str:
    matches = [name for name in candidates if all(name in record for record in records)]
    if len(matches) != 1:
        raise ManifestOperationalError(
            f"manifest must define exactly one supported {label} field; found {matches}"
        )
    return matches[0]


def _select_tree_field(manifest: dict[str, Any]) -> str:
    matches = [name for name in TREE_FIELDS if name in manifest]
    if len(matches) != 1:
        raise ManifestOperationalError(
            f"manifest must define exactly one supported tree hash field; found {matches}"
        )
    return matches[0]


def _relative_path(value: Any) -> str:
    if not isinstance(value, str) or not value:
        raise ManifestOperationalError("artifact path must be a non-empty string")
    if "\\" in value:
        raise ManifestOperationalError(f"artifact path is not forward-slash normalized: {value!r}")
    parsed = PurePosixPath(value)
    if parsed.is_absolute() or parsed.as_posix() != value or ".." in parsed.parts:
        raise ManifestOperationalError(f"artifact path is not a canonical relative path: {value!r}")
    return value


def _sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or SHA256.fullmatch(value) is None:
        raise ManifestOperationalError(f"{label} must be a 64-digit SHA-256")
    return value.lower()


def tree_bytes(records: Iterable[dict[str, str]], *, sort_paths: bool) -> bytes:
    material = list(records)
    if sort_paths:
        material.sort(key=lambda item: _path_key(item["relative_path"]))
    text = "".join(
        f"{item['relative_path']}\t{item['sha256'].lower()}\n" for item in material
    )
    return text.encode("utf-8")


def verify_manifest(root: Path, manifest_path: Path) -> dict[str, Any]:
    resolved_root = root.resolve()
    resolved_manifest = manifest_path.resolve()
    try:
        manifest_bytes = resolved_manifest.read_bytes()
        manifest = json.loads(manifest_bytes.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ManifestOperationalError(f"cannot read manifest: {exc}") from exc
    if not isinstance(manifest, dict):
        raise ManifestOperationalError("manifest root must be an object")
    raw_records = manifest.get("files")
    if not isinstance(raw_records, list) or not raw_records:
        raise ManifestOperationalError("manifest files must be a non-empty list")
    if not all(isinstance(record, dict) for record in raw_records):
        raise ManifestOperationalError("every manifest file record must be an object")

    records: list[dict[str, Any]] = list(raw_records)
    path_field = _select_record_field(records, PATH_FIELDS, "path")
    length_field = _select_record_field(records, LENGTH_FIELDS, "byte length")
    hash_field = _select_record_field(records, HASH_FIELDS, "file hash")
    tree_field = _select_tree_field(manifest)
    declared_tree = _sha256(manifest[tree_field], tree_field)

    normalized: list[dict[str, str]] = []
    mismatches: list[dict[str, Any]] = []
    seen: set[str] = set()
    total_bytes = 0
    for index, record in enumerate(records):
        relative_path = _relative_path(record[path_field])
        if relative_path in seen:
            raise ManifestOperationalError(f"duplicate artifact path: {relative_path}")
        seen.add(relative_path)
        expected_hash = _sha256(record[hash_field], f"files[{index}].{hash_field}")
        expected_length = record[length_field]
        if isinstance(expected_length, bool) or not isinstance(expected_length, int):
            raise ManifestOperationalError(
                f"files[{index}].{length_field} must be a non-negative integer"
            )
        if expected_length < 0:
            raise ManifestOperationalError(
                f"files[{index}].{length_field} must be a non-negative integer"
            )

        target = (resolved_root / Path(relative_path)).resolve()
        try:
            target.relative_to(resolved_root)
        except ValueError as exc:
            raise ManifestOperationalError(f"artifact escapes root: {relative_path}") from exc
        try:
            raw = target.read_bytes()
        except OSError as exc:
            mismatches.append({"path": relative_path, "kind": "missing", "detail": str(exc)})
            normalized.append({"relative_path": relative_path, "sha256": expected_hash})
            continue
        actual_hash = hashlib.sha256(raw).hexdigest()
        total_bytes += len(raw)
        if len(raw) != expected_length or actual_hash != expected_hash:
            mismatches.append(
                {
                    "path": relative_path,
                    "kind": "exact_byte_mismatch",
                    "expected_length": expected_length,
                    "actual_length": len(raw),
                    "expected_sha256": expected_hash,
                    "actual_sha256": actual_hash,
                }
            )
        normalized.append({"relative_path": relative_path, "sha256": actual_hash})

    bytewise_tree_bytes = tree_bytes(normalized, sort_paths=True)
    manifest_order_tree_bytes = tree_bytes(normalized, sort_paths=False)
    bytewise_tree = hashlib.sha256(bytewise_tree_bytes).hexdigest()
    manifest_order_tree = hashlib.sha256(manifest_order_tree_bytes).hexdigest()
    ordering_matches = declared_tree == bytewise_tree
    passed = not mismatches and ordering_matches
    return {
        "schema": "simufire.exact_byte_artifact_manifest_verification.v1",
        "root": resolved_root.as_posix(),
        "manifest": resolved_manifest.as_posix(),
        "manifest_bytes": len(manifest_bytes),
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "path_field": path_field,
        "length_field": length_field,
        "hash_field": hash_field,
        "tree_field": tree_field,
        "file_count": len(records),
        "verified_file_count": len(records) - len(mismatches),
        "total_bytes": total_bytes,
        "declared_tree_sha256": declared_tree,
        "manifest_order_tree_sha256": manifest_order_tree,
        "bytewise_utf8_tree_sha256": bytewise_tree,
        "declared_matches_bytewise_utf8": ordering_matches,
        "mismatch_count": len(mismatches),
        "mismatches": mismatches,
        "verdict": "PASS" if passed else "FAIL",
        "check_exit_code": 0 if passed else 1,
    }


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
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = verify_manifest(args.root, args.manifest)
        if args.json_out is not None:
            write_json_atomic(args.json_out, result)
    except ManifestOperationalError as exc:
        print(f"Artifact manifest verification operational error: {exc}", file=sys.stderr)
        return 2

    print(
        "Artifact manifest verification: "
        f"{result['verified_file_count']}/{result['file_count']} files, "
        f"{result['mismatch_count']} mismatches, "
        f"bytewise tree {'PASS' if result['declared_matches_bytewise_utf8'] else 'FAIL'}"
    )
    return int(result["check_exit_code"])


if __name__ == "__main__":
    raise SystemExit(main())
