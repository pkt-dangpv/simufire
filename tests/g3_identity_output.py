"""Strict reading of the output of a before/after identity fixture.

An identity fixture hashes every result of a corpus and prints one digest line
and a completion marker. It has no PASS marker on purpose: it cannot judge its
own digest, the test that pins it does. So the comparison has to refuse
anything short of one complete, well formed report, and this is where that is
decided. Its negative controls are in tests/test_g3_identity_fixture_controls.py.
"""
import json
import re

KEYS = {"cases", "valid", "rejected", "sha256"}


def identity_payload(stdout: str, stderr: str, prefix: str) -> dict:
    """The digest report of one complete run, or an AssertionError."""
    text = (stdout or "") + (stderr or "")
    assert "SCRIPT ERROR" not in text and "Parse Error" not in text, "the fixture did not run cleanly"
    lines = (stdout or "").splitlines()
    reports = [index for index, line in enumerate(lines) if line.startswith(prefix + " ")]
    assert len(reports) == 1, f"expected one digest line, found {len(reports)}"
    done = [index for index, line in enumerate(lines) if line.strip() == prefix + "_DONE"]
    assert len(done) == 1 and done[0] > reports[0], "the corpus did not reach its completion marker"
    try:
        payload = json.loads(lines[reports[0]][len(prefix) + 1:])
    except ValueError as error:
        raise AssertionError(f"truncated or malformed digest line: {error}") from error
    assert isinstance(payload, dict) and set(payload) == KEYS, "unexpected digest fields"
    for key in ("cases", "valid", "rejected"):
        assert type(payload[key]) is int and payload[key] >= 0, key
    assert payload["cases"] == payload["valid"] + payload["rejected"] > 0, "the counters do not add up"
    assert isinstance(payload["sha256"], str) and re.fullmatch(r"[0-9a-f]{64}", payload["sha256"]), "not a digest"
    return payload
