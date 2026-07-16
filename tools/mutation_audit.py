"""
R0-2: Harness de mutation testing.

Para cada mutante definido en CaseRunner._MUTATION_TABLE, corre un subconjunto
curado de casos de validación con el flag --validation-mutate=<M> y mide el
kill rate (fracción de mutantes detectados por ≥1 check required FAIL).

USO:
    python tools/mutation_audit.py                    # modo quick (~15 casos)
    python tools/mutation_audit.py --all-cases        # todos los casos (lento)
    python tools/mutation_audit.py --mutants M-HRR M-YCO   # solo estos mutantes
    python tools/mutation_audit.py --timeout 120      # timeout por caso (segundos)

REQUISITOS:
    - GODOT_EXE env var o ejecutable en ubicaciones estándar
    - Python 3.11+
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES_DIR = ROOT / "sim/validation/cases"

# Candidates de ejecutable Godot (mismo patrón que check_product.py)
_GODOT_CANDIDATES = [
    Path("F:/OneDrive/Escritorio/Godot_v4.6.3-stable_win64_console.exe"),
    Path("C:/Users/dangp/Desktop/Godot_v4.6.3-stable_win64_console.exe"),
]

# Todos los mutantes implementados en CaseRunner._MUTATION_TABLE
ALL_MUTANTS = ["M-HRR", "M-ENTR", "M-O2EXT", "M-YCO", "M-YHCN", "M-WALL", "M-VENT", "M-PRES"]

# Subset curado para el modo quick — cubre las principales familias de checks
QUICK_CASES = [
    "cfast_r0_window_360",         # CFAST reference: T/O2/HRR/layer
    "cfast_single_room_closed",    # sellado: presión + O2 depletion
    "cfast_two_room_door_open",    # dos salas: transporte
    "cfast_corridor_chain",        # multi-sala: transporte largo
    "cfast_bedroom_closed_door",   # dormitorio sellado
    "cfast_hvac_residential",      # HVAC: O2/CO/temp
    "cfast_window_break_t180",     # apertura exterior dinámica
    "cfast_fast_growth_closed",    # crecimiento rápido sellado
    "ghanekar_bedroom_hallway",    # referencia empírica Ghanekar
    "v2_sealed_room_o2_depletion", # depleción O2 sala sellada
    "v4_co_remote_rooms",          # CO transporte multi-sala
    "pu_sofa_fec_incapacitation",  # FED/HCN sofá PU
    "victim_fed_incapacitation",   # FED víctima
    "c_balance_high_phi",          # balance de carbono
    "confinement_open_close",      # ventilación exterior dinámica
    "energy_budget_living_room",   # balance energético
    "cfast_two_floor_stairwell",   # multi-planta
]


# ── Godot finder ─────────────────────────────────────────────────────────────

def _find_godot() -> Path | None:
    env_path = os.environ.get("GODOT_EXE")
    if env_path:
        p = Path(env_path)
        if p.exists():
            return p
    for candidate in _GODOT_CANDIDATES:
        if candidate.exists():
            return candidate
    hit = shutil.which("godot")
    if hit:
        return Path(hit)
    return None


# ── Godot case runner ─────────────────────────────────────────────────────────

def run_case(
    godot: Path,
    case_name: str,
    output_path: Path,
    mutant_id: str,
    timeout_s: int = 180,
) -> tuple[bool, str]:
    """Corre un caso Godot con el mutante dado. Devuelve (ok, stderr)."""
    args = [
        str(godot),
        "--headless",
        "--path", str(ROOT),
        "--",
        f"--validation-case={case_name}",
        f"--validation-output={output_path}",
        f"--validation-mutate={mutant_id}",
    ]
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout_s,
            cwd=str(ROOT),
        )
        success = result.returncode == 0 and output_path.exists()
        return success, result.stderr or result.stdout
    except subprocess.TimeoutExpired:
        return False, f"TIMEOUT after {timeout_s}s"
    except Exception as e:
        return False, str(e)


# ── Evaluate checks against temp reports ─────────────────────────────────────

def evaluate_checks_in_tempdir(temp_dir: Path) -> tuple[int, int, list[str]]:
    """
    Importa validate_reference_cases con REPORTS_DIR apuntando a temp_dir y
    ejecuta main(). Devuelve (required_count, failed_count, failed_names).
    """
    vrc_path = ROOT / "scripts/simulation/validate_reference_cases.py"
    import io
    import contextlib

    # Usar nombre único para evitar colisiones en sys.modules
    mod_name = f"vrc_mut_{id(temp_dir)}"
    spec = importlib.util.spec_from_file_location(mod_name, vrc_path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[mod_name] = mod  # necesario para que @dataclass funcione
    spec.loader.exec_module(mod)
    mod.REPORTS_DIR = temp_dir
    buf = io.StringIO()

    failed_names: list[str] = []
    required_count = 0
    failed_count = 0
    try:
        with contextlib.redirect_stdout(buf):
            mod.main()
    except SystemExit:
        pass
    except Exception:
        pass

    # Limpiar módulo del cache para que la próxima llamada use uno fresco
    sys.modules.pop(mod_name, None)

    out_path = temp_dir / "reference_checks.json"
    if out_path.exists():
        data = json.loads(out_path.read_text(encoding="utf-8"))
        checks = data.get("checks", [])
        required = [c for c in checks if c.get("required")]
        failed = [c for c in required if not c.get("pass")]
        required_count = len(required)
        failed_count = len(failed)
        failed_names = [c["name"] for c in failed]

    return required_count, failed_count, failed_names


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description="R0-2: Mutation testing harness — mide kill rate.")
    parser.add_argument(
        "--all-cases", action="store_true",
        help="Corre todos los casos disponibles (lento). Por defecto usa el subset curado."
    )
    parser.add_argument(
        "--mutants", nargs="+", metavar="M",
        help=f"Mutantes a probar (por defecto: todos). Opciones: {' '.join(ALL_MUTANTS)}"
    )
    parser.add_argument(
        "--timeout", type=int, default=180,
        help="Timeout por caso en segundos (default: 180)."
    )
    parser.add_argument(
        "--output", type=Path, default=ROOT / "tools/reports/mutation_results.json",
        help="Ruta de salida del informe JSON."
    )
    parser.add_argument(
        "--no-run", action="store_true",
        help="Salta la ejecución de Godot (usa reports existentes en el directorio de mutación)."
    )
    args = parser.parse_args()

    mutants_to_test = args.mutants or ALL_MUTANTS
    for m in mutants_to_test:
        if m not in ALL_MUTANTS:
            print(f"ERROR: mutante desconocido '{m}'. Opciones: {ALL_MUTANTS}")
            return 1

    # Seleccionar casos
    if args.all_cases:
        cases = sorted(p.stem for p in CASES_DIR.glob("*.json"))
    else:
        cases = [c for c in QUICK_CASES if (CASES_DIR / f"{c}.json").exists()]

    godot = _find_godot()
    if godot is None and not args.no_run:
        print("ERROR: no se encontró Godot. Define GODOT_EXE o añádelo al PATH.")
        return 1

    print("=" * 66)
    print("  R0-2: Mutation Testing — SimuFire")
    print("=" * 66)
    print(f"  Mutantes: {', '.join(mutants_to_test)}")
    print(f"  Casos:    {len(cases)} ({'todos' if args.all_cases else 'curados'})")
    if godot:
        print(f"  Godot:    {godot.name}")
    print()

    # Cargar baseline (checks del motor sin mutaciones)
    baseline_json = ROOT / "sim/validation/reports/reference_checks.json"
    if baseline_json.exists():
        baseline_data = json.loads(baseline_json.read_text(encoding="utf-8"))
        baseline_required = sum(1 for c in baseline_data["checks"] if c["required"])
    else:
        baseline_required = 0

    results: dict[str, dict] = {}

    for mutant in mutants_to_test:
        print(f"  ── {mutant} ──────────────────────────────────────────────────")
        mutant_dir = Path(tempfile.mkdtemp(prefix=f"simufire_mut_{mutant}_"))
        try:
            run_ok = 0
            run_fail = 0
            run_timeout = 0

            if not args.no_run:
                for case_name in cases:
                    output_path = mutant_dir / f"{case_name}.json"
                    t0 = time.monotonic()
                    ok, stderr = run_case(godot, case_name, output_path, mutant, args.timeout)
                    elapsed = time.monotonic() - t0
                    if ok:
                        run_ok += 1
                        print(f"    OK  {case_name:<45} {elapsed:.1f}s")
                    elif "TIMEOUT" in stderr:
                        run_timeout += 1
                        print(f"    TMT {case_name:<45} {elapsed:.1f}s")
                    else:
                        run_fail += 1
                        print(f"    ERR {case_name:<45} {elapsed:.1f}s")
            else:
                # Copiar reports reales para evaluar (útil para debugging)
                real_reports = ROOT / "sim/validation/reports"
                for case_name in cases:
                    src = real_reports / f"{case_name}.json"
                    if src.exists():
                        shutil.copy(src, mutant_dir / f"{case_name}.json")
                        run_ok += 1

            # También copiar los reports no-cubiertos del baseline (para checks que leen
            # múltiples fuentes), pero marcarlos como "sin mutación".
            real_reports = ROOT / "sim/validation/reports"
            for rpt in real_reports.glob("*.json"):
                dst = mutant_dir / rpt.name
                if not dst.exists() and rpt.name != "reference_checks.json":
                    shutil.copy(rpt, dst)

            # Evaluar
            req_count, fail_count, fail_names = evaluate_checks_in_tempdir(mutant_dir)

            killed = fail_count > 0
            kill_rate = fail_count / req_count if req_count > 0 else 0.0

            results[mutant] = {
                "killed": killed,
                "required_checks_evaluated": req_count,
                "checks_failed_by_mutation": fail_count,
                "kill_rate": round(kill_rate, 4),
                "godot_runs_ok": run_ok,
                "godot_runs_fail": run_fail,
                "godot_runs_timeout": run_timeout,
                "failed_check_names": fail_names,
            }

            status = "KILLED" if killed else "SURVIVED"
            print(f"    → {status}: {fail_count}/{req_count} checks fallan ({kill_rate*100:.1f}%)")
            print()

        finally:
            shutil.rmtree(mutant_dir, ignore_errors=True)

    # ── Resumen ───────────────────────────────────────────────────────────────
    killed_count = sum(1 for r in results.values() if r["killed"])
    total = len(results)
    global_kill_rate = killed_count / total if total > 0 else 0.0

    print("=" * 66)
    print(f"  Kill rate global: {killed_count}/{total} mutantes detectados ({global_kill_rate*100:.0f}%)")
    print()
    print(f"  {'Mutante':<12}  {'Estado':<10}  {'Fallos/Req':>12}  {'Kill%':>7}  Checks muertos (muestra)")
    print(f"  {'-'*12}  {'-'*10}  {'-'*12}  {'-'*7}  {'-'*30}")
    for m, r in results.items():
        status = "KILLED" if r["killed"] else "SURVIVED"
        sample = ", ".join(r["failed_check_names"][:2]) if r["failed_check_names"] else "-"
        print(
            f"  {m:<12}  {status:<10}  "
            f"{r['checks_failed_by_mutation']:>5}/{r['required_checks_evaluated']:<6}  "
            f"{r['kill_rate']*100:>6.1f}%  {sample}"
        )
    print()
    if global_kill_rate < 0.9:
        print(f"  AVISO: kill rate {global_kill_rate*100:.0f}% < objetivo 90%.")
        print("  Cada mutante SURVIVED identifica checks que deben diseñarse.")
    else:
        print(f"  OK: kill rate {global_kill_rate*100:.0f}% >= 90%.")
    print("=" * 66)

    # Guardar JSON
    report = {
        "baseline_required_checks": baseline_required,
        "cases_tested": cases,
        "mutants": results,
        "kill_rate_global": round(global_kill_rate, 4),
        "killed_count": killed_count,
        "total_mutants": total,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"  Informe: {args.output}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
