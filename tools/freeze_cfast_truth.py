"""
R0-3: Congelar verdad CFAST.

Lee todos los ficheros .in y CSV de sim/validation/cfast/ y genera:
  truth/cfast/MANIFEST.json   — hashes SHA-256 de cada fichero + metadata

El MANIFEST permite detectar si algún CSV de referencia cambia sin
intención (stale log, regeneración accidental).  Para verificar integridad:
  python tools/freeze_cfast_truth.py --verify

Para regenerar el manifiesto tras una regeneración intencionada:
  python tools/freeze_cfast_truth.py --update
"""

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFAST_DIR = ROOT / "sim/validation/cfast"
MANIFEST_PATH = ROOT / "truth/cfast/MANIFEST.json"

CFAST_VERSION_NOTE = (
    "CFAST 7.7.x — versión exacta registrada en sim/validation/cfast/codex_cfast_run "
    "si el directorio existe. Para regenerar CSVs instalar CFAST 7.7 y ejecutar "
    "regenerate_truth.ps1."
)


def sha256(path: Path) -> str:
    # Normalize CRLF → LF before hashing so Windows/Linux produce identical digests.
    data = path.read_bytes().replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def build_manifest() -> dict:
    entries = {}
    for pattern in ("*.in", "*.csv"):
        for p in sorted(CFAST_DIR.glob(pattern)):
            rel = p.relative_to(ROOT).as_posix()
            entries[rel] = {
                "sha256": sha256(p),
                "size_bytes": p.stat().st_size,
            }
    return {
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "cfast_version_note": CFAST_VERSION_NOTE,
        "source_dir": CFAST_DIR.relative_to(ROOT).as_posix(),
        "file_count": len(entries),
        "files": entries,
    }


def verify_manifest(manifest: dict) -> bool:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ok = True
    missing = []
    changed = []
    for rel, info in manifest["files"].items():
        p = ROOT / rel
        if not p.exists():
            missing.append(rel)
            ok = False
            continue
        actual = sha256(p)
        if actual != info["sha256"]:
            changed.append((rel, info["sha256"][:12], actual[:12]))
            ok = False

    if missing:
        print(f"  MISSING ({len(missing)}):")
        for f in missing:
            print(f"    {f}")
    if changed:
        print(f"  CHANGED ({len(changed)}):")
        for f, old, new in changed:
            print(f"    {f}  old={old}...  new={new}...")

    total = len(manifest["files"])
    problems = len(missing) + len(changed)
    if ok:
        print(f"  OK: {total}/{total} ficheros CFAST sin cambios.")
    else:
        print(f"  FAIL: {problems}/{total} ficheros con discrepancias.")
    return ok


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Gestiona el manifiesto de verdad CFAST.")
    parser.add_argument("--verify", action="store_true", help="Verifica integridad contra el manifiesto existente.")
    parser.add_argument("--update", action="store_true", help="Regenera el manifiesto (actualiza hashes).")
    args = parser.parse_args()

    if args.verify:
        if not MANIFEST_PATH.exists():
            print(f"ERROR: no existe {MANIFEST_PATH}. Ejecutar sin --verify primero.")
            sys.exit(1)
        with open(MANIFEST_PATH, encoding="utf-8") as f:
            manifest = json.load(f)
        print(f"Verificando {manifest['file_count']} ficheros CFAST...")
        ok = verify_manifest(manifest)
        sys.exit(0 if ok else 1)

    # Crear o actualizar manifiesto
    if MANIFEST_PATH.exists() and not args.update:
        print(f"El manifiesto ya existe en {MANIFEST_PATH}.")
        print("Usar --update para regenerarlo o --verify para comprobar integridad.")
        sys.exit(0)

    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    print(f"Generando manifiesto desde {CFAST_DIR}...")
    manifest = build_manifest()
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    print(f"Manifiesto escrito: {MANIFEST_PATH}")
    print(f"  Ficheros registrados: {manifest['file_count']}")
    print(f"  CFAST version note: {manifest['cfast_version_note'][:60]}...")
    print()
    print("Para verificar integridad en el futuro:")
    print("  python tools/freeze_cfast_truth.py --verify")


if __name__ == "__main__":
    main()
