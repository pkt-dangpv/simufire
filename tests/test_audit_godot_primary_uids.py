from __future__ import annotations

import json
from pathlib import Path
import subprocess

import pytest

from scripts.simulation import audit_godot_primary_uids as audit


ROOT = Path(__file__).resolve().parents[1]


def _git_deleted_paths(*patterns: str) -> set[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--deleted", "--", *patterns],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return {
        path
        for path in result.stdout.decode("utf-8").split("\0")
        if path
    }


@pytest.mark.parametrize("ending", [b"", b"\n", b"\r\n"])
def test_sidecar_accepts_exact_ascii_uid_with_optional_newline(ending: bytes) -> None:
    assert audit.parse_primary_uid("model.gd.uid", b"uid://abc123" + ending) == "uid://abc123"


@pytest.mark.parametrize(
    "raw",
    [
        b"",
        b" uid://abc",
        b"uid://abc ",
        b"uid://abc\nextra",
        b"\xef\xbb\xbfuid://abc",
        b"uid://abc-def",
        b"uid://",
    ],
)
def test_sidecar_rejects_noncanonical_bytes(raw: bytes) -> None:
    with pytest.raises(ValueError):
        audit.parse_primary_uid("model.gd.uid", raw)


def test_resource_primary_uid_is_independent_of_attribute_order() -> None:
    raw = b'[gd_resource uid="uid://abc123" format=3 type="Resource"]\n'
    assert audit.parse_primary_uid("model.tres", raw) == "uid://abc123"


def test_scene_without_primary_uid_does_not_count_ext_resource_uid() -> None:
    raw = (
        b"[gd_scene load_steps=2 format=3]\n\n"
        b'[ext_resource type="Script" uid="uid://external1" path="res://x.gd" id="1"]\n'
    )
    assert audit.parse_primary_uid("model.tscn", raw) is None


def test_resource_without_primary_uid_is_valid() -> None:
    assert audit.parse_primary_uid("model.tres", b"[gd_resource format=3]\n") is None


@pytest.mark.parametrize(
    "raw",
    [
        b'[gd_resource format=3 uid="uid://abc]\n',
        b'[gd_resource format=3 uid=uid://abc]\n',
        b'[gd_resource format=3 uid="uid://abc" uid="uid://def"]\n',
        b'[resource format=3 uid="uid://abc"]\n',
    ],
)
def test_resource_rejects_malformed_primary_header(raw: bytes) -> None:
    with pytest.raises(ValueError):
        audit.parse_primary_uid("model.tres", raw)


def _write_uid(path: Path, uid: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(uid.encode("ascii") + b"\n")


def test_duplicate_groups_and_paths_are_deterministic(tmp_path: Path) -> None:
    _write_uid(tmp_path / "z.gd.uid", "uid://same")
    _write_uid(tmp_path / "a.gd.uid", "uid://same")
    result = audit.audit_paths(tmp_path, ["z.gd.uid", "a.gd.uid"], "0" * 40)

    assert result["duplicate_groups"] == [
        {"uid": "uid://same", "paths": ["a.gd.uid", "z.gd.uid"]}
    ]


def test_tree_manifest_uses_ordinal_utf8_byte_order(tmp_path: Path) -> None:
    paths = ["phase_d5a_x.gd.uid", "phase_d5a2_x.gd.uid", "Z.gd.uid", "a.gd.uid"]
    for index, path in enumerate(paths):
        _write_uid(tmp_path / path, f"uid://value{index}")
    result = audit.audit_paths(tmp_path, paths, "0" * 40)

    assert [item["path"] for item in result["records"]] == [
        "Z.gd.uid",
        "a.gd.uid",
        "phase_d5a2_x.gd.uid",
        "phase_d5a_x.gd.uid",
    ]


def test_empty_candidate_inventory_fails_closed(tmp_path: Path) -> None:
    with pytest.raises(audit.AuditOperationalError, match="empty"):
        audit.audit_paths(tmp_path, [], "0" * 40)


def test_unreported_missing_candidate_fails_closed(tmp_path: Path) -> None:
    with pytest.raises(audit.AuditOperationalError, match="cannot read missing.gd.uid"):
        audit.audit_paths(tmp_path, ["missing.gd.uid"], "0" * 40)


def test_git_error_fails_closed(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    def fail_git(_repo: Path, *_args: str) -> bytes:
        raise audit.AuditOperationalError("synthetic git failure")

    monkeypatch.setattr(audit, "_run_git", fail_git)
    with pytest.raises(audit.AuditOperationalError, match="synthetic"):
        audit.discover_tracked_candidates(tmp_path)


def test_json_output_is_repeatable(tmp_path: Path) -> None:
    _write_uid(tmp_path / "a.gd.uid", "uid://one")
    result = audit.audit_paths(tmp_path, ["a.gd.uid"], "0" * 40)
    assert audit.json_bytes(result) == audit.json_bytes(json.loads(audit.json_bytes(result)))


def test_atomic_json_writer_leaves_no_temporary_file(tmp_path: Path) -> None:
    result = {"status": "PASS"}
    output = tmp_path / "result.json"
    audit.write_json_atomic(output, result)

    assert json.loads(output.read_text(encoding="utf-8")) == result
    assert list(tmp_path.glob(".result.json.*.tmp")) == []


def test_tracked_godot_primary_uids_are_unique() -> None:
    resolved, checkpoint = audit._repository_identity(ROOT)
    deleted = _git_deleted_paths("*.gd.uid", "*.tscn", "*.tres")
    candidates = [
        path
        for path in audit.discover_tracked_candidates(resolved)
        if path not in deleted
    ]
    result = audit.audit_paths(resolved, candidates, checkpoint)

    assert result["malformed"] == []
    assert result["duplicate_groups"] == []
