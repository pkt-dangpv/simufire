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
    manifest = {
        "schema": "simufire.test.exact_byte_artifact_manifest.v1",
        "ordering": "bytewise UTF-8 relative path",
        "tree_contract": "relative_path<TAB>lowercase_exact_byte_sha256<LF>",
        "file_count": len(records),
        "total_bytes": sum(
            int(record.get("byte_length", record.get("bytes", 0)))
            for record in records
        ),
        tree_field: declared_tree or tree,
        "files": records,
    }
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


@pytest.mark.parametrize(
    ("extra_field", "extra_value"),
    [
        ("relative_path", "conflicting.txt"),
        ("byte_length", 999),
        ("worktree_sha256", "0" * 64),
    ],
)
def test_partial_conflicting_record_alias_fails_closed(
    tmp_path: Path, extra_field: str, extra_value: object
) -> None:
    first = b"first"
    second = b"second"
    (tmp_path / "a.txt").write_bytes(first)
    (tmp_path / "b.txt").write_bytes(second)
    records = [
        _record("a.txt", first, aliases=True),
        _record("b.txt", second, aliases=True),
    ]
    records[0][extra_field] = extra_value
    manifest = _write_manifest(tmp_path, records)

    with pytest.raises(verifier.ManifestOperationalError, match="exactly one"):
        verifier.verify_manifest(tmp_path, manifest)


@pytest.mark.parametrize("location", ["top_level", "record"])
def test_duplicate_json_key_fails_closed(tmp_path: Path, location: str) -> None:
    raw = b"duplicate-key"
    (tmp_path / "a.txt").write_bytes(raw)
    manifest_path = _write_manifest(
        tmp_path, [_record("a.txt", raw, aliases=True)]
    )
    manifest_text = manifest_path.read_text(encoding="utf-8")
    if location == "top_level":
        manifest_text = manifest_text.replace(
            '"file_count": 1', '"file_count": 999, "file_count": 1', 1
        )
    else:
        manifest_text = manifest_text.replace(
            '"path": "a.txt"', '"path": "ignored.txt", "path": "a.txt"', 1
        )
    manifest_path.write_text(manifest_text, encoding="utf-8")

    with pytest.raises(verifier.ManifestOperationalError, match="duplicate JSON"):
        verifier.verify_manifest(tmp_path, manifest_path)


def test_declared_file_count_mismatch_is_a_data_failure(tmp_path: Path) -> None:
    raw = b"count"
    (tmp_path / "a.txt").write_bytes(raw)
    manifest_path = _write_manifest(tmp_path, [_record("a.txt", raw, aliases=True)])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["file_count"] = 999
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    result = verifier.verify_manifest(tmp_path, manifest_path)

    assert result["verdict"] == "FAIL"
    assert result["verified_file_count"] == 1
    assert result["file_mismatch_count"] == 0
    assert result["metadata_mismatch_count"] == 1
    assert result["mismatches"][0]["kind"] == "declared_file_count_mismatch"


@pytest.mark.parametrize("field", ["total_bytes", "source_total_bytes"])
def test_declared_total_bytes_alias_mismatch_is_a_data_failure(
    tmp_path: Path, field: str
) -> None:
    raw = b"bytes"
    (tmp_path / "a.txt").write_bytes(raw)
    manifest_path = _write_manifest(tmp_path, [_record("a.txt", raw, aliases=True)])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest.pop("total_bytes")
    manifest[field] = 0
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    result = verifier.verify_manifest(tmp_path, manifest_path)

    assert result["verdict"] == "FAIL"
    assert result["declared_total_bytes_field"] == field
    assert result["mismatches"][0]["kind"] == "declared_total_bytes_mismatch"


def test_legacy_integral_float_total_bytes_is_accepted(tmp_path: Path) -> None:
    raw = b"legacy"
    (tmp_path / "a.txt").write_bytes(raw)
    manifest_path = _write_manifest(tmp_path, [_record("a.txt", raw, aliases=True)])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["total_bytes"] = float(len(raw))
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    result = verifier.verify_manifest(tmp_path, manifest_path)

    assert result["verdict"] == "PASS"
    assert result["declared_total_bytes"] == len(raw)


def test_tree_manifest_byte_length_mismatch_is_a_data_failure(tmp_path: Path) -> None:
    raw = b"tree"
    (tmp_path / "a.txt").write_bytes(raw)
    manifest_path = _write_manifest(tmp_path, [_record("a.txt", raw, aliases=True)])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["tree_manifest_bytes"] = 0
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    result = verifier.verify_manifest(tmp_path, manifest_path)

    assert result["verdict"] == "FAIL"
    assert result["mismatches"][0]["kind"] == "declared_tree_manifest_bytes_mismatch"


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("ordering", "case-insensitive locale collation"),
        ("tree_contract", "not-the-binding-contract"),
        ("hash_convention", "normalized text bytes"),
    ],
)
def test_unsupported_contract_metadata_fails_closed(
    tmp_path: Path, field: str, value: str
) -> None:
    raw = b"contract"
    (tmp_path / "a.txt").write_bytes(raw)
    manifest_path = _write_manifest(tmp_path, [_record("a.txt", raw, aliases=True)])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest[field] = value
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(verifier.ManifestOperationalError, match=field):
        verifier.verify_manifest(tmp_path, manifest_path)


def test_missing_contract_declaration_fails_closed(tmp_path: Path) -> None:
    raw = b"contract"
    (tmp_path / "a.txt").write_bytes(raw)
    manifest_path = _write_manifest(tmp_path, [_record("a.txt", raw, aliases=True)])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest.pop("ordering")
    manifest.pop("tree_contract")
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(verifier.ManifestOperationalError, match="ordering contract"):
        verifier.verify_manifest(tmp_path, manifest_path)


@pytest.mark.parametrize(
    "profile", ["session36", "session40", "session41", "session45"]
)
def test_supported_historical_contract_profiles_verify(
    tmp_path: Path, profile: str
) -> None:
    raw = b"historical"
    (tmp_path / "a.txt").write_bytes(raw)
    manifest_path = _write_manifest(tmp_path, [_record("a.txt", raw, aliases=True)])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    if profile == "session36":
        manifest.pop("ordering")
        manifest.pop("tree_contract")
        manifest["hash_contract"] = next(iter(verifier.SUPPORTED_HASH_CONTRACTS))
        manifest["total_bytes"] = float(len(raw))
    elif profile == "session40":
        manifest["ordering"] = "bytewise UTF-8 path order"
    elif profile == "session41":
        manifest.pop("ordering")
        manifest.pop("file_count")
        manifest.pop("total_bytes")
        manifest["tree_ordering"] = next(iter(verifier.SUPPORTED_TREE_ORDERING))
        manifest["tree_contract"] = "path<TAB>lowercase_sha256<LF>"
        manifest["hash_convention"] = next(iter(verifier.SUPPORTED_HASH_CONVENTIONS))
        normalized = [{"relative_path": "a.txt", "sha256": _sha(raw)}]
        manifest["tree_manifest_bytes"] = len(
            verifier.tree_bytes(normalized, sort_paths=True)
        )
    else:
        manifest["ordering"] = (
            "bytewise UTF-8 relative paths; all current paths ASCII"
        )
        manifest["source_total_bytes"] = manifest.pop("total_bytes")
        manifest["source_tree_sha256"] = manifest.pop("tree_sha256")

    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    result = verifier.verify_manifest(tmp_path, manifest_path)

    assert result["verdict"] == "PASS"
    assert result["metadata_mismatch_count"] == 0


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
