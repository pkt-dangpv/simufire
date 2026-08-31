"""import_visual_layer.py — Importa SOLO la capa grafica desde un clon de la nube.

Pensado para el caso en que el motor local (sim/, scripts/simulation/, ...) va
por otra rama que NO se puede pisar, pero si se quiere traer el trabajo visual
hecho en la nube (view/, shaders, assets de mobiliario, guardarrailes FP).

  Ver que cambiaria:   python scripts/import_visual_layer.py --check
  Aplicar:             python scripts/import_visual_layer.py --apply

El script se niega a escribir un solo byte fuera de la capa grafica. Antes de
copiar hace una auditoria de acoplamiento: si la version de la nube ELIMINA
algun simbolo publico de view/ que el codigo local no-visual (Main.gd, ui/,
editor/, scenes/, scripts/, tools/) todavia usa, aborta y lo lista. Asi el
import solo entra cuando es realmente compatible con el motor local.

Exit codes:
    0 — sin cambios pendientes, o import aplicado correctamente
    1 — auditoria de acoplamiento fallida, o error de uso
    2 — (solo con --check) hay cambios graficos pendientes de importar
"""

import argparse
import filecmp
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent

# --- Que se considera "capa grafica" -------------------------------------
# Arboles que se copian tal cual desde la nube.
VISUAL_TREES = (
    "view",            # visualizadores 2D/3D, primera persona, shaders, .tres
    "assets/fp",       # mobiliario y aberturas de primera persona (GLB + .tscn)
)
# Guardarrailes visuales sueltos (prefijo: se copian todos sus ficheros).
VISUAL_FILE_PREFIXES = (
    "tools/validate_fp_",
)
# De project.godot solo se sincronizan estas claves de render.
PROJECT_GODOT_KEYS = (
    "lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
    "textures/default_filters/anisotropic_filtering_level",
)

# --- Que NO se toca nunca -------------------------------------------------
ENGINE_TREES = ("sim", "scripts/simulation", "truth", "external", "path")

# Codigo local no-visual que consume la API de view/ y que aqui no se toca:
# si la nube borra algo que estos usan, el import no es seguro.
CONSUMER_PATHS = ("Main.gd", "ui", "editor", "scenes", "scripts", "tools")

_SYMBOL_RE = re.compile(r"^(?:func|signal)\s+([A-Za-z0-9_]+)", re.MULTILINE)


def _git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True, text=True, check=True,
    )
    return result.stdout


def _export_ref(repo: Path, ref: str, dest: Path) -> None:
    """Vuelca en dest solo los paths visuales de <ref>."""
    paths = list(VISUAL_TREES)
    for prefix in VISUAL_FILE_PREFIXES:
        parent = str(Path(prefix).parent)
        name = Path(prefix).name
        listing = _git(repo, "ls-tree", "-r", "--name-only", ref, "--", parent)
        paths += [p for p in listing.splitlines() if Path(p).name.startswith(name)]

    archive = dest.parent / "visual.tar"
    with archive.open("wb") as handle:
        subprocess.run(
            ["git", "-C", str(repo), "archive", ref, "--", *paths],
            stdout=handle, check=True,
        )
    with tarfile.open(archive) as tar:
        tar.extractall(dest)
    archive.unlink()


def _is_visual(rel: str) -> bool:
    rel = rel.replace("\\", "/")
    if any(rel == t or rel.startswith(t + "/") for t in VISUAL_TREES):
        return True
    return any(rel.startswith(p) for p in VISUAL_FILE_PREFIXES)


def _plan(staged: Path) -> tuple[list[str], list[str]]:
    """Devuelve (nuevos, modificados) como rutas relativas al repo."""
    added: list[str] = []
    changed: list[str] = []
    for src in sorted(staged.rglob("*")):
        if not src.is_file():
            continue
        rel = src.relative_to(staged).as_posix()
        if not _is_visual(rel):
            raise SystemExit(
                "ABORTADO: el archivo exportado cae fuera de la capa "
                "grafica: " + rel
            )
        local = _REPO_ROOT / rel
        if not local.exists():
            added.append(rel)
        elif not filecmp.cmp(src, local, shallow=False):
            changed.append(rel)
    return added, changed


def _public_symbols(text: str) -> set[str]:
    return {n for n in _SYMBOL_RE.findall(text) if not n.startswith("_")}


def _consumer_text() -> str:
    """Todo el GDScript local que NO es capa grafica."""
    blob = ""
    for path in CONSUMER_PATHS:
        target = _REPO_ROOT / path
        if target.is_file():
            blob += target.read_text(encoding="utf-8", errors="ignore")
        elif target.is_dir():
            for gd in target.rglob("*.gd"):
                if _is_visual(gd.relative_to(_REPO_ROOT).as_posix()):
                    continue
                blob += gd.read_text(encoding="utf-8", errors="ignore")
    return blob


def _audit_coupling(staged: Path, changed: list[str]) -> list[str]:
    """Simbolos publicos de view/ que la nube elimina y el codigo local usa."""
    consumer = _consumer_text()
    breaks: list[str] = []
    for rel in changed:
        if not rel.endswith(".gd"):
            continue
        local = _REPO_ROOT / rel
        if not local.exists():
            continue
        removed = _public_symbols(local.read_text(encoding="utf-8", errors="ignore"))
        cloud_text = (staged / rel).read_text(encoding="utf-8", errors="ignore")
        removed -= _public_symbols(cloud_text)
        for symbol in sorted(removed):
            if re.search(r"\b" + re.escape(symbol) + r"\b", consumer):
                breaks.append(rel + ": " + symbol + "()")
    return breaks


def _engine_dirty() -> list[str]:
    """Ficheros del motor con cambios locales sin commitear (informativo)."""
    dirty = []
    for line in _git(_REPO_ROOT, "status", "--porcelain").splitlines():
        status, rel = line[:2], line[3:].strip().strip('"')
        if status.strip() == "??":
            continue  # artefactos de import de Godot, no trabajo del motor
        if any(rel.startswith(t + "/") for t in ENGINE_TREES):
            dirty.append(rel)
    return dirty


def _sync_project_godot(repo: Path, ref: str, apply: bool) -> list[str]:
    """Sincroniza solo las claves de render de project.godot."""
    cloud = _git(repo, "show", ref + ":project.godot")
    local_path = _REPO_ROOT / "project.godot"
    original = local_path.read_text(encoding="utf-8")
    updated = original
    pending: list[str] = []
    for key in PROJECT_GODOT_KEYS:
        pattern = r"^" + re.escape(key) + r"=.*$"
        match = re.search(pattern, cloud, re.MULTILINE)
        if not match:
            continue
        line = match.group(0)
        if re.search(pattern, updated, re.MULTILINE):
            updated = re.sub(pattern, line, updated, flags=re.MULTILINE)
        else:
            updated = updated.rstrip("\n") + "\n" + line + "\n"
        if line not in original:
            pending.append(line)
    if apply and pending:
        local_path.write_text(updated, encoding="utf-8")
    return pending


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--repo", default=str(_REPO_ROOT / "simufire-main"),
        help="clon de referencia con el trabajo de la nube",
    )
    parser.add_argument(
        "--ref", default="HEAD",
        help="ref del clon a importar (p.ej. origin/main)",
    )
    parser.add_argument(
        "--apply", action="store_true",
        help="escribe los cambios (por defecto solo informa)",
    )
    parser.add_argument(
        "--check", action="store_true",
        help="solo informa; exit 2 si hay cambios pendientes",
    )
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    if not (repo / ".git").exists():
        print("ERROR: " + str(repo) + " no es un repositorio git.")
        return 1

    print("=" * 72)
    print("  Import de capa grafica - SimuFire")
    print("  Origen: " + str(repo) + "  (" + args.ref + ")")
    print("=" * 72)

    with tempfile.TemporaryDirectory() as tmp:
        staged = Path(tmp) / "staged"
        staged.mkdir(parents=True)
        _export_ref(repo, args.ref, staged)
        added, changed = _plan(staged)

        breaks = _audit_coupling(staged, changed)
        if breaks:
            print("")
            print("  AUDITORIA DE ACOPLAMIENTO: FALLA")
            print("  La version de la nube elimina API de view/ que el codigo")
            print("  local no-visual todavia usa. Import abortado:")
            print("")
            for item in breaks:
                print("    - " + item)
            return 1
        print("")
        print("  Auditoria de acoplamiento: OK "
              "(la nube no elimina API de view/ en uso)")

        dirty = _engine_dirty()
        if dirty:
            print("")
            print("  Aviso: " + str(len(dirty)) + " fichero(s) del motor con "
                  "cambios locales. No se tocan.")

        proj = _sync_project_godot(repo, args.ref, args.apply)
        print("")
        print("  Nuevos:      " + str(len(added)))
        print("  Modificados: " + str(len(changed)))
        print("  project.godot (claves de render): " + str(len(proj)))
        for rel in (added + changed)[:20]:
            print("    - " + rel)
        extra = len(added) + len(changed) - 20
        if extra > 0:
            print("    - ... y " + str(extra) + " mas")

        if not (added or changed or proj):
            print("")
            print("  La capa grafica local ya esta al dia.")
            return 0

        if not args.apply:
            print("")
            print("  (simulacion: nada escrito). Aplica con --apply")
            return 2 if args.check else 0

        for rel in added + changed:
            dest = _REPO_ROOT / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(staged / rel, dest)
        print("")
        print("  Aplicado: " + str(len(added) + len(changed)) + " fichero(s).")

    print("")
    print("  Siguiente paso (reimporta assets y valida):")
    print("    <Godot> --headless --path . --import")
    print("    python scripts/check_product.py")
    print("=" * 72)
    return 0


if __name__ == "__main__":
    sys.exit(main())
