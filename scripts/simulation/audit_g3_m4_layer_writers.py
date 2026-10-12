"""Read-only M4-B lexical inventory, NOT a reachability or physical-flow proof.

Direct assignments are inventoried across sim/*.gd. Comments/string literals
are masked, declarations are separate, and function names are retained.
Dynamic property names, alias writes and dictionary state need manual review.
No Godot, subprocess, runtime import, report write or simulation mutation.
"""
import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
ASSIGN = re.compile(r"\bo2_(upper|lower)(?:\s*:\s*\w+)?\s*(?:[+*/-]=|=(?!=))")
FUNCTION = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\(")
DECLARATION = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*var\s+o2_(upper|lower)\b")


def mask_noncode(source):
    """Preserve offsets/newlines while masking strings and # comments."""
    chars = list(source)
    index = 0
    while index < len(source):
        if source[index] == "#":
            end = source.find("\n", index)
            end = len(source) if end < 0 else end
        elif source[index] in ("'", '"'):
            quote = source[index]
            delimiter = quote * 3 if source.startswith(quote * 3, index) else quote
            end = index + len(delimiter)
            while end < len(source):
                if source[end] == "\\":
                    end += 2
                elif source.startswith(delimiter, end):
                    end += len(delimiter)
                    break
                else:
                    end += 1
            end = min(end, len(source))
        else:
            index += 1
            continue
        for offset in range(index, end):
            if chars[offset] not in "\r\n":
                chars[offset] = " "
        index = end
    return "".join(chars)


def scan(source, path):
    rows = []
    function = "<top-level>"
    originals = source.splitlines()
    for line_number, code in enumerate(mask_noncode(source).splitlines(), 1):
        found = FUNCTION.match(code)
        if found:
            function = found.group(1)
        for assignment in ASSIGN.finditer(code):
            rows.append({"path": path, "line": line_number, "function": function,
                         "field": "o2_" + assignment.group(1),
                         "declaration": bool(DECLARATION.match(code)),
                         "source": originals[line_number - 1].strip()})
    return rows


def inventory(root=ROOT):
    hashes = {}
    rows = []
    for path in sorted((root / "sim").rglob("*.gd")):
        relative = path.relative_to(root).as_posix()
        raw = path.read_bytes()
        hashes[relative] = hashlib.sha256(raw.replace(b"\r\n", b"\n")).hexdigest()
        rows.extend(scan(raw.decode("utf-8-sig"), relative))
    digest = hashlib.sha256("\n".join(f"{p}:{h}" for p, h in hashes.items()).encode()).hexdigest()
    writes = [row for row in rows if not row["declaration"]]
    return {"schema": "g3_m4_direct_layer_writers_v1", "scope": "lexical_direct_assignments_only",
            "runtime_executed": False, "physical_validation": False,
            "gd_file_count": len(hashes), "gd_inventory_lf_sha256": digest,
            "source_hashes_lf": hashes, "declarations": [r for r in rows if r["declaration"]],
            "write_count": len(writes), "writes": writes}


if __name__ == "__main__":
    print(json.dumps(inventory(), ensure_ascii=False, indent=2))
