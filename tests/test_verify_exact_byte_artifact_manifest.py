from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from scripts.simulation import verify_exact_byte_artifact_manifest as verifier


ROOT = Path(__file__).resolve().parents[1]


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _record(path: str, raw: bytes, *, aliases: bool = False) -> dict[str, object]:
    if aliases:
        return {"path": path, "bytes": len(raw), "sha256": _sha(raw)}
    return {"relative_path": path, "byte_length": len(raw), "worktree_sha256": _sha(raw)}


def _write_manifest(
    tmp_path: Path,
    records: list[dict[str, object]],
    *,
    tree_field: str = "tree_sha256",
    declared_tree: str | None = None,
) -> Path:
    normalized = [
        {
            "relative_path": str(record.get("relative_path", record.get("path"))),
            "sha256": str(record.get("worktree_sha256", record.get("sha256"))),
        }
        for record in records
    ]
    tree = hashlib.sha256(verifier.tree_bytes(normalized, sort_paths=True)).hexdigest()
    manifest = {tree_field: declared_tree or tree, "files": records}
    path = tmp_path / "artifact_manifest.json"
    path.write_text(json.dumps(manifest), encoding="utf-8")
    return path


def test_relative_path_aliases_verify_clean_manifest(tmp_path: Path) -> None:
    raw = b"alpha\r\n"
    (tmp_path / "a.txt").write_bytes(raw)
    manifest = _write_manifest(tmp_path, [_record("a.txt", raw, aliases=True)])

    result = verifier.verify_manifest(tmp_path, manifest)

    assert result["verdict"] == "PASS"
    assert result["path_field"] == "path"
    assert result["length_field"] == "bytes"
    assert result["hash_field"] == "sha256"


def test_worktree_aliases_and_source_tree_field_verify(tmp_path: Path) -> None:
    raw = b"beta\n"
    (tmp_path / "b.txt").write_bytes(raw)
    manifest = _write_manifest(
        tmp_path,
        [_record("b.txt", raw)],
        tree_field="source_tree_sha256",
    )

    result = verifier.verify_manifest(tmp_path, manifest)

    assert result["verdict"] == "PASS"
    assert result["hash_field"] == "worktree_sha256"


def test_case_insensitive_manifest_order_does_not_pass_as_bytewise(tmp_path: Path) -> None:
    upper = b"upper"
    lower = b"lower"
    (tmp_path / "STOP_REPORT.md").write_bytes(upper)
    (tmp_path / "alpha.json").write_bytes(lower)
    records = [
        _record("alpha.json", lower, aliases=True),
        _record("STOP_REPORT.md", upper, aliases=True),
    ]
    manifest_order = [
        {"relative_path": str(record["path"]), "sha256": str(record["sha256"])}
        for record in records
    ]
    wrong_tree = hashlib.sha256(
        verifier.tree_bytes(manifest_order, sort_paths=False)
    ).hexdigest()
    manifest = _write_manifest(tmp_path, records, declared_tree=wrong_tree)

    result = verifier.verify_manifest(tmp_path, manifest)

    assert result["verified_file_count"] == 2
    assert result["mismatch_count"] == 0
    assert result["manifest_order_tree_sha256"] == wrong_tree
    assert result["declared_matches_bytewise_utf8"] is False
    assert result["verdict"] == "FAIL"
    assert result["check_exit_code"] == 1


@pytest.mark.parametrize("mutation", ["length", "hash"])
def test_exact_byte_mismatch_fails(tmp_path: Path, mutation: str) -> None:
    raw = b"original"
    (tmp_path / "a.txt").write_bytes(raw)
    record = _record("a.txt", raw, aliases=True)
    if mutation == "length":
        record["bytes"] = len(raw) + 1
    else:
        record["sha256"] = "0" * 64
    manifest = _write_manifest(tmp_path, [record])

    result = verifier.verify_manifest(tmp_path, manifest)

    assert result["verdict"] == "FAIL"
    assert result["mismatches"][0]["kind"] == "exact_byte_mismatch"


def test_missing_file_is_a_data_failure(tmp_path: Path) -> None:
    raw = b"missing"
    manifest = _write_manifest(tmp_path, [_record("missing.txt", raw, aliases=True)])

    result = verifier.verify_manifest(tmp_path, manifest)

    assert result["verdict"] == "FAIL"
    assert result["mismatches"][0]["kind"] == "missing"


@pytest.mark.parametrize(
    "path",
    ["../escape.txt", "/absolute.txt", "nested\\windows.txt"],
)
def test_noncanonical_or_escaping_path_fails_closed(tmp_path: Path, path: str) -> None:
    raw = b"x"
    manifest = _write_manifest(tmp_path, [_record(path, raw, aliases=True)])

    with pytest.raises(verifier.ManifestOperationalError, match="path"):
        verifier.verify_manifest(tmp_path, manifest)


def test_duplicate_path_fails_closed(tmp_path: Path) -> None:
    raw = b"x"
    (tmp_path / "a.txt").write_bytes(raw)
    record = _record("a.txt", raw, aliases=True)
    manifest = _write_manifest(tmp_path, [record, dict(record)])

    with pytest.raises(verifier.ManifestOperationalError, match="duplicate"):
        verifier.verify_manifest(tmp_path, manifest)


def test_ambiguous_alias_fields_fail_closed(tmp_path: Path) -> None:
    raw = b"x"
    (tmp_path / "a.txt").write_bytes(raw)
    record = _record("a.txt", raw, aliases=True)
    record["relative_path"] = "a.txt"
    manifest = _write_manifest(tmp_path, [record])

    with pytest.raises(verifier.ManifestOperationalError, match="exactly one"):
        verifier.verify_manifest(tmp_path, manifest)


def test_atomic_json_output_has_stable_bytes(tmp_path: Path) -> None:
    result = {"verdict": "PASS", "count": 1}
    output = tmp_path / "result.json"

    verifier.write_json_atomic(output, result)
    first = output.read_bytes()
    verifier.write_json_atomic(output, result)

    assert output.read_bytes() == first == verifier.json_bytes(result)
    assert list(tmp_path.glob(".result.json.*.tmp")) == []


def test_tracked_session36_correction_is_self_consistent() -> None:
    path = (
        ROOT
        / "docs"
        / "validation"
        / "P1R1_SESSION36_MANIFEST_COLLATION_CORRECTION.json"
    )
    correction = json.loads(path.read_text(encoding="utf-8"))
    records = correction["records_in_historical_manifest_order"]
    normalized = [
        {"relative_path": item["relative_path"], "sha256": item["sha256"]}
        for item in records
    ]

    historical = hashlib.sha256(
        verifier.tree_bytes(normalized, sort_paths=False)
    ).hexdigest()
    corrected = hashlib.sha256(
        verifier.tree_bytes(normalized, sort_paths=True)
    ).hexdigest()

    assert correction["finding"] == "P1R1-EVID-002"
    assert correction["status"] == "REMEDIATED_PENDING_INDEPENDENT_REVIEW"
    assert correction["source"]["file_count"] == len(records) == 18
    assert correction["source"]["source_total_bytes"] == sum(
        item["byte_length"] for item in records
    )
    assert historical == correction["historical_record"]["tree_sha256"]
    assert corrected == correction["corrected_semantics"]["tree_sha256"]
    assert historical != corrected
