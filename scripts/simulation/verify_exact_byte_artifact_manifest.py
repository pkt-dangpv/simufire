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
import math
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
TOTAL_BYTES_FIELDS = ("source_total_bytes", "total_bytes")
SHA256 = re.compile(r"[0-9a-fA-F]{64}\Z")

SUPPORTED_ORDERING = {
    "bytewise UTF-8 path order",
    "bytewise UTF-8 relative path",
    "bytewise UTF-8 relative paths; all current paths ASCII",
}
SUPPORTED_TREE_ORDERING = {
    "ordinal UTF-8 byte order, equivalent to LC_ALL=C for these ASCII paths",
}
SUPPORTED_TREE_CONTRACTS = {
    "path<TAB>lowercase_sha256<LF>",
    "relative_path<TAB>lowercase_exact_byte_sha256<LF>",
}
SUPPORTED_HASH_CONTRACTS = {
    "exact bytes; tree sorted ordinal/bytewise UTF-8 relative path with LF",
}
SUPPORTED_HASH_CONVENTIONS = {
    "SHA-256 over exact worktree bytes without EOL normalization",
}


class ManifestOperationalError(RuntimeError):
    """The manifest could not be evaluated completely and unambiguously."""


def _path_key(value: str) -> bytes:
    return value.encode("utf-8")


def _reject_duplicate_object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ManifestOperationalError(f"duplicate JSON object key: {key!r}")
        result[key] = value
    return result


def _select_record_field(
    records: list[dict[str, Any]], candidates: Iterable[str], label: str
) -> str:
    candidate_names = tuple(candidates)
    selected: set[str] = set()
    for index, record in enumerate(records):
        matches = [name for name in candidate_names if name in record]
        if len(matches) != 1:
            raise ManifestOperationalError(
                f"files[{index}] must define exactly one supported {label} field; "
                f"found {matches}"
            )
        selected.add(matches[0])
    if len(selected) != 1:
        raise ManifestOperationalError(
            f"manifest records must use one consistent supported {label} field; "
            f"found {sorted(selected)}"
        )
    return selected.pop()


def _select_tree_field(manifest: dict[str, Any]) -> str:
    matches = [name for name in TREE_FIELDS if name in manifest]
    if len(matches) != 1:
        raise ManifestOperationalError(
            f"manifest must define exactly one supported tree hash field; found {matches}"
        )
    return matches[0]


def _select_optional_field(
    manifest: dict[str, Any], candidates: Iterable[str], label: str
) -> str | None:
    matches = [name for name in candidates if name in manifest]
    if len(matches) > 1:
        raise ManifestOperationalError(
            f"manifest must define at most one supported {label} field; found {matches}"
        )
    return matches[0] if matches else None


def _non_negative_integer(value: Any, label: str, *, allow_integral_float: bool) -> int:
    if isinstance(value, bool):
        raise ManifestOperationalError(f"{label} must be a non-negative integer")
    if isinstance(value, int):
        result = value
    elif (
        allow_integral_float
        and isinstance(value, float)
        and math.isfinite(value)
        and value.is_integer()
    ):
        result = int(value)
    else:
        raise ManifestOperationalError(f"{label} must be a non-negative integer")
    if result < 0:
        raise ManifestOperationalError(f"{label} must be a non-negative integer")
    return result


def _validate_contract_value(
    manifest: dict[str, Any], field: str, supported: set[str]
) -> str | None:
    if field not in manifest:
        return None
    value = manifest[field]
    if not isinstance(value, str) or value not in supported:
        raise ManifestOperationalError(f"unsupported {field}: {value!r}")
    return value


def _validate_contract_metadata(manifest: dict[str, Any]) -> dict[str, str]:
    schema = manifest.get("schema")
    if not isinstance(schema, str) or not schema:
        raise ManifestOperationalError("manifest schema must be a non-empty string")

    checked: dict[str, str] = {"schema": schema}
    declarations = {
        "ordering": _validate_contract_value(manifest, "ordering", SUPPORTED_ORDERING),
        "tree_ordering": _validate_contract_value(
            manifest, "tree_ordering", SUPPORTED_TREE_ORDERING
        ),
        "tree_contract": _validate_contract_value(
            manifest, "tree_contract", SUPPORTED_TREE_CONTRACTS
        ),
        "hash_contract": _validate_contract_value(
            manifest, "hash_contract", SUPPORTED_HASH_CONTRACTS
        ),
        "hash_convention": _validate_contract_value(
            manifest, "hash_convention", SUPPORTED_HASH_CONVENTIONS
        ),
    }
    for field, value in declarations.items():
        if value is not None:
            checked[field] = value

    ordering_fields = ("ordering", "tree_ordering", "hash_contract")
    if not any(declarations[field] is not None for field in ordering_fields):
        raise ManifestOperationalError(
            "manifest must declare a supported bytewise ordering contract"
        )
    if declarations["tree_contract"] is None and declarations["hash_contract"] is None:
        raise ManifestOperationalError("manifest must declare a supported tree contract")
    return checked


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
        manifest = json.loads(
            manifest_bytes.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_object_pairs,
        )
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ManifestOperationalError(f"cannot read manifest: {exc}") from exc
    if not isinstance(manifest, dict):
        raise ManifestOperationalError("manifest root must be an object")
    contract_fields = _validate_contract_metadata(manifest)
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

    declared_file_count = None
    if "file_count" in manifest:
        declared_file_count = _non_negative_integer(
            manifest["file_count"], "file_count", allow_integral_float=False
        )
    total_bytes_field = _select_optional_field(
        manifest, TOTAL_BYTES_FIELDS, "total byte count"
    )
    declared_total_bytes = None
    if total_bytes_field is not None:
        declared_total_bytes = _non_negative_integer(
            manifest[total_bytes_field],
            total_bytes_field,
            allow_integral_float=True,
        )
    declared_tree_manifest_bytes = None
    if "tree_manifest_bytes" in manifest:
        declared_tree_manifest_bytes = _non_negative_integer(
            manifest["tree_manifest_bytes"],
            "tree_manifest_bytes",
            allow_integral_float=False,
        )

    normalized: list[dict[str, str]] = []
    file_mismatches: list[dict[str, Any]] = []
    metadata_mismatches: list[dict[str, Any]] = []
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
            file_mismatches.append(
                {"path": relative_path, "kind": "missing", "detail": str(exc)}
            )
            normalized.append({"relative_path": relative_path, "sha256": expected_hash})
            continue
        actual_hash = hashlib.sha256(raw).hexdigest()
        total_bytes += len(raw)
        if len(raw) != expected_length or actual_hash != expected_hash:
            file_mismatches.append(
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
    if declared_file_count is not None and declared_file_count != len(records):
        metadata_mismatches.append(
            {
                "kind": "declared_file_count_mismatch",
                "expected": declared_file_count,
                "actual": len(records),
            }
        )
    if declared_total_bytes is not None and declared_total_bytes != total_bytes:
        metadata_mismatches.append(
            {
                "kind": "declared_total_bytes_mismatch",
                "field": total_bytes_field,
                "expected": declared_total_bytes,
                "actual": total_bytes,
            }
        )
    if (
        declared_tree_manifest_bytes is not None
        and declared_tree_manifest_bytes != len(bytewise_tree_bytes)
    ):
        metadata_mismatches.append(
            {
                "kind": "declared_tree_manifest_bytes_mismatch",
                "expected": declared_tree_manifest_bytes,
                "actual": len(bytewise_tree_bytes),
            }
        )
    mismatches = file_mismatches + metadata_mismatches
    passed = not mismatches and ordering_matches
    return {
        "schema": "simufire.exact_byte_artifact_manifest_verification.v1",
        "source_manifest_schema": manifest["schema"],
        "root": resolved_root.as_posix(),
        "manifest": resolved_manifest.as_posix(),
        "manifest_bytes": len(manifest_bytes),
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "path_field": path_field,
        "length_field": length_field,
        "hash_field": hash_field,
        "tree_field": tree_field,
        "contract_fields_checked": contract_fields,
        "file_count": len(records),
        "declared_file_count": declared_file_count,
        "verified_file_count": len(records) - len(file_mismatches),
        "total_bytes": total_bytes,
        "declared_total_bytes_field": total_bytes_field,
        "declared_total_bytes": declared_total_bytes,
        "tree_manifest_bytes": len(bytewise_tree_bytes),
        "declared_tree_manifest_bytes": declared_tree_manifest_bytes,
        "declared_tree_sha256": declared_tree,
        "manifest_order_tree_sha256": manifest_order_tree,
        "bytewise_utf8_tree_sha256": bytewise_tree,
        "declared_matches_bytewise_utf8": ordering_matches,
        "file_mismatch_count": len(file_mismatches),
        "metadata_mismatch_count": len(metadata_mismatches),
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
