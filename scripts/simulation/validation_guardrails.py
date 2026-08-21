"""
validation_guardrails.py — Entrypoint único para verificar el estado de salud de SimuFire
antes de cualquier cambio de código.

Ejecuta (silenciosamente) la lógica de:
  - phase2e_preflight.py   → 7 checks sentinel de Phase 2E
  - gap_inventory_check.py → sincronización de conteo de gaps

Uso:
    python scripts/simulation/validation_guardrails.py
    python scripts/simulation/validation_guardrails.py --json path/to/reference_checks.json
    python scripts/simulation/validation_guardrails.py --verbose   # muestra salida completa

Código de salida:
    0 — todos los guardrails PASS
    1 — algún guardrail FAIL
"""

import sys
import io
import json
import argparse
import contextlib
from pathlib import Path

# En Windows, piped stdout puede usar cp1252; reconfigure para UTF-8 si disponible
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Añadir el directorio de scripts al path para importar los módulos hermanos
_scripts_dir = Path(__file__).resolve().parent
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

import phase2e_preflight
import gap_inventory_check
import legacy_two_zone_compare

# Herramienta R0-3 — puede no existir en sesiones anteriores al commit
try:
    import importlib.util as _ilu
    _fp = Path(__file__).resolve().parent.parent.parent / "tools/freeze_cfast_truth.py"
    _spec = _ilu.spec_from_file_location("freeze_cfast_truth", _fp)
    _mod = _ilu.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    _verify_cfast_truth = _mod.verify_manifest
    _manifest_path = _mod.MANIFEST_PATH
except Exception:
    _verify_cfast_truth = None
    _manifest_path = None


# ---------------------------------------------------------------------------
# R1-3 — Physics override linter
# ---------------------------------------------------------------------------

# Claves de motor que NO deben aparecer en ningún caso de validación.
# Son knobs de calibración del motor, no parámetros del experimento.
_PHYSICS_OVERRIDE_KEYS: frozenset[str] = frozenset({
    "fire_hrr_global_multiplier",
    "vent_bernoulli_flow_multiplier",
    "two_zone_convective_heat_multiplier",
    "doorway_o2_upper_routing_gain",
    "phase2h_lower_cf_drain_coeff",
    "outside_open_upper_heat_boost",
    "fire_co_vent_limited_multiplier",
    "background_species_exchange_kg_s_m2",
    "hot_gas_species_carry_fraction",
})

# Exenciones (stem, clave) — deuda conocida, anterior al linter.
# Cada entrada debe llevar el porqué y la condición de retirada.  Una exención
# NO legitima el override: sigue siendo deuda; el linter la reporta como nota.
_PHYSICS_OVERRIDE_EXEMPTIONS: frozenset[tuple[str, str]] = frozenset({
    # Phase 9 C4 (commit b5c63ce9, 2026-06): calibración O2 del pool fire
    # abierto vía vent_bernoulli_flow_multiplier=0.45.  Anterior al linter
    # R1-3.  Retirarlo requiere sesión de motor (mover el valor a defaults o
    # recalibrar el caso) + regenerar baselines — fuera de alcance de una
    # sesión de validación.  Retirar esta exención en la misma sesión que
    # elimine el override del JSON.
    ("cfast_pool_fire_open", "vent_bernoulli_flow_multiplier"),
})


def _check_physics_overrides(repo_root: Path) -> tuple[int, str]:
    """R1-3: detecta overrides de física del motor en casos de validación."""
    cases_dir = repo_root / "sim/validation/cases"
    violations: list[str] = []
    exempted: list[str] = []
    for case_file in sorted(cases_dir.glob("*.json")):
        try:
            case = json.loads(case_file.read_text(encoding="utf-8"))
        except Exception:
            continue
        overrides = case.get("engine_overrides", {})
        for key in overrides:
            if key in _PHYSICS_OVERRIDE_KEYS:
                if (case_file.stem, key) in _PHYSICS_OVERRIDE_EXEMPTIONS:
                    exempted.append(f"    {case_file.stem}: {key} = {overrides[key]}")
                else:
                    violations.append(f"    {case_file.stem}: {key} = {overrides[key]}")
    if violations:
        lines = ["R1-3: overrides de física del motor en casos de validación:"]
        lines.extend(violations)
        lines.append(
            f"  {len(violations)} violaciones. Mueve estos valores al motor (defaults) "
            "y elimínalos del JSON del caso."
        )
        return 1, "\n".join(lines)
    lines = ["R1-3: sin overrides de física no exentos en casos de validación. OK"]
    if exempted:
        lines.append(f"  Exenciones activas ({len(exempted)}, deuda documentada):")
        lines.extend(exempted)
    return 0, "\n".join(lines)


# ---------------------------------------------------------------------------
# PHY-P1 — Metric plausibility (species ppm <= 100% of the mixture)
# ---------------------------------------------------------------------------

# Una fracción molar no puede superar 1e6 ppm (100% de la mezcla).  Detectado
# en la auditoría 2026-07-06: el CO₂ bulk de salas RECEPTORAS superaba el 100%
# en 7 casos (1.02e6–2.10e6 ppm; nunca en el fire room).  Corregido en F0 Plan B
# (2026-07-07): limitador de equilibrio por concentración en el transporte CO₂
# inter-room (GasExchangeSystem + ThermalSystem) — el receptor no puede quedar
# por encima de la concentración de la fuente.  Allowlist vaciada tras el fix.
#
# Las parejas (stem, métrica) listadas aquí son excepciones conocidas.
# Cualquier violación NUEVA (otro caso u otra métrica) dispara FAIL — el bug
# no puede crecer en silencio.  Retirar cada entrada cuando un fix la corrija.
_PPM_CEILING = 1_000_000.0

_KNOWN_PPM_VIOLATIONS: dict[str, frozenset[str]] = {}


def _check_metric_plausibility(repo_root: Path) -> tuple[int, str]:
    """PHY-P1: ninguna métrica *_ppm de los reports puede superar 1e6 (100%)."""
    reports_dir = repo_root / "sim/validation/reports"
    if not reports_dir.is_dir():
        return 0, "PHY-P1: directorio de reports no encontrado — check omitido."
    new_violations: list[str] = []
    known_seen: list[str] = []
    for report_file in sorted(reports_dir.glob("*.json")):
        stem = report_file.stem
        if stem.startswith(("tmp_", "_tmp")) or stem == "reference_checks":
            continue
        try:
            data = json.loads(report_file.read_text(encoding="utf-8"))
        except Exception:
            continue
        metrics = data.get("metrics", {})
        allowed = _KNOWN_PPM_VIOLATIONS.get(stem, frozenset())
        for key, value in metrics.items():
            if not key.endswith("_ppm") or not isinstance(value, (int, float)):
                continue
            if value > _PPM_CEILING:
                entry = f"    {stem}: {key} = {value:.3e} ppm (> 1e6 = 100%)"
                if key in allowed:
                    known_seen.append(entry)
                else:
                    new_violations.append(entry)
    if new_violations:
        lines = ["PHY-P1: métricas ppm físicamente imposibles NO registradas:"]
        lines.extend(new_violations)
        lines.append(
            "  Una fracción molar no puede superar el 100% de la mezcla. "
            "Investigar antes de aceptar el report."
        )
        return 1, "\n".join(lines)
    lines = ["PHY-P1: sin violaciones ppm nuevas. OK"]
    if known_seen:
        lines.append(
            f"  Violaciones conocidas ({len(known_seen)}, bug motor bulk-CO2 receptoras, "
            "pendiente sesión motor):"
        )
        lines.extend(known_seen)
    return 0, "\n".join(lines)


# ---------------------------------------------------------------------------
# R2-1 — Reports freshness vs engine/cases
# ---------------------------------------------------------------------------

# Rutas cuyo cambio invalida reference_checks.json: motor GDScript, presets
# y definiciones de casos de validación.
_ENGINE_PATHS: tuple[str, ...] = (
    "sim/core",
    "sim/fire",
    "sim/building",
    "sim/resources",
    "sim/validation/cases",
)


def _check_reports_freshness(repo_root: Path, json_path: Path) -> tuple[int, str]:
    """R2-1: reference_checks.json debe ser posterior al último cambio de motor/casos.

    Sin esto se puede modificar el motor y "validar" contra reports viejos sin
    que nada proteste.  Usa git (no mtimes: un checkout los resetea).  Si git
    no está disponible o el historial es shallow (CI), el check se omite con
    nota — nunca da falso FAIL por entorno.
    """
    import subprocess

    def _git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", *args], cwd=repo_root, capture_output=True, text=True
        )

    try:
        rel_json = json_path.resolve().relative_to(repo_root)
    except ValueError:
        return 0, "R2-1: JSON fuera del repo — check omitido."

    probe = _git("rev-parse", "--is-inside-work-tree")
    if probe.returncode != 0 or probe.stdout.strip() != "true":
        return 0, "R2-1: git no disponible — check omitido."

    # 1) Cambios sin commitear en motor/casos mientras el reporte está limpio.
    st_engine = _git("status", "--porcelain", "--", *_ENGINE_PATHS)
    dirty_engine = [ln.strip() for ln in st_engine.stdout.splitlines() if ln.strip()]
    st_json = _git("status", "--porcelain", "--", str(rel_json))
    json_dirty = bool(st_json.stdout.strip())
    if dirty_engine and not json_dirty:
        lines = [
            "R2-1: cambios sin commitear en motor/casos y el reporte NO fue regenerado:",
        ]
        lines.extend(f"    {ln}" for ln in dirty_engine[:10])
        if len(dirty_engine) > 10:
            lines.append(f"    ... (+{len(dirty_engine) - 10})")
        lines.append(
            "  Regenera el corpus y el reporte con: "
            "sim/validation/run_reference_checks.ps1"
        )
        return 1, "\n".join(lines)

    # 2) Último commit que tocó motor/casos vs último que tocó el reporte.
    t_engine = _git("log", "-1", "--format=%ct", "--", *_ENGINE_PATHS).stdout.strip()
    t_json = _git("log", "-1", "--format=%ct", "--", str(rel_json)).stdout.strip()
    if not t_engine or not t_json:
        return 0, "R2-1: historial git incompleto (shallow clone) — check omitido."
    if int(t_engine) > int(t_json):
        h_engine = _git("log", "-1", "--format=%h %ad", "--date=short",
                        "--", *_ENGINE_PATHS).stdout.strip()
        h_json = _git("log", "-1", "--format=%h %ad", "--date=short",
                      "--", str(rel_json)).stdout.strip()
        return 1, (
            "R2-1: el motor/casos cambió DESPUÉS de la última regeneración del reporte:\n"
            f"    último commit motor/casos : {h_engine}\n"
            f"    último commit del reporte : {h_json}\n"
            "  Los checks required podrían estar validando código antiguo.\n"
            "  Regenera el corpus y el reporte con: "
            "sim/validation/run_reference_checks.ps1"
        )
    return 0, "R2-1: reports al día respecto a motor/casos. OK"


# ---------------------------------------------------------------------------
# PHY-C1 — Carbon/HCN sentinel checks
# ---------------------------------------------------------------------------

# Checks que deben estar presentes, ser required=True y pass=True en reference_checks.json.
# Confirman que: (a) el balance elemental de carbono incluye HCN (SF-AUD-032), y
# (b) HCN se produce en casos PU foam con yield calibrado (PHY-C2, Purser bounds).
_CARBON_HCN_SENTINELS: list[str] = [
    "c_balance_high_phi_room_0_peak_c_balance_frac",
    "pu_sofa_fec_incapacitation_room_0_peak_c_balance_frac",
    "pu_sofa_fec_incapacitation_room_0_peak_hcn_upper_ppm",
    "victim_fed_incapacitation_room_0_peak_c_balance_frac",
    "victim_fed_incapacitation_room_0_peak_hcn_upper_ppm",
]


def _check_carbon_hcn_sentinels(data: dict) -> tuple[int, str]:
    """
    Verifica que los checks sentinel de balance C/HCN estén presentes,
    sean required=True y pasen. Devuelve (exit_code, summary_str).
    """
    checks_by_name = {c["name"]: c for c in data.get("checks", [])}
    lines: list[str] = []
    failed = False
    for sentinel in _CARBON_HCN_SENTINELS:
        c = checks_by_name.get(sentinel)
        if c is None:
            lines.append(f"  MISSING  {sentinel}")
            failed = True
        elif not c.get("required", False):
            lines.append(f"  NOT-REQ  {sentinel}  (actual={c.get('actual')})")
            failed = True
        elif not c.get("pass", False):
            lines.append(f"  FAIL     {sentinel}  (actual={c.get('actual')})")
            failed = True
        else:
            lines.append(f"  PASS     {sentinel}  (actual={c.get('actual')})")
    return (1 if failed else 0, "\n".join(lines))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _run_silent(fn: callable, extra_argv: list[str] | None = None) -> tuple[int, str]:
    """Ejecuta fn() con stdout redirigido; devuelve (exit_code, output_str)."""
    old_argv = sys.argv[:]
    if extra_argv is not None:
        sys.argv = [sys.argv[0]] + extra_argv
    buf = io.StringIO()
    rc = 1
    try:
        with contextlib.redirect_stdout(buf):
            rc = fn()
    except SystemExit as e:
        rc = e.code if isinstance(e.code, int) else 1
    finally:
        sys.argv = old_argv
    return rc, buf.getvalue()


def _load_json(json_path: Path) -> dict | None:
    try:
        return json.loads(json_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _check_gap_inventory_sync(data: dict | None, inventory_path: Path) -> tuple[int, str]:
    """Check only inventory counts; required failures have their own guardrail."""
    if data is None:
        return 1, "Gap inventory sync: reference JSON is unreadable."

    documented = gap_inventory_check.extract_documented_gap_count(inventory_path)
    known_gap_count = data.get("known_gap_count")
    checks = data.get("checks", [])
    real_gap_count = len(
        [check for check in checks if not check.get("required") and not check.get("pass")]
    )

    if documented is None:
        return 1, f"Gap inventory sync: cannot parse {inventory_path}."
    if documented == known_gap_count == real_gap_count:
        return 0, f"Gap inventory sync: {documented} documented and observed."
    return 1, (
        "Gap inventory sync mismatch: "
        f"documented={documented}, JSON={known_gap_count}, observed={real_gap_count}."
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validation guardrails — verifica todos los checks de salud de SimuFire."
    )
    parser.add_argument(
        "--json", default=None, metavar="PATH",
        help="Ruta a reference_checks.json (por defecto: sim/validation/reports/reference_checks.json)",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Mostrar la salida completa de cada guardrail además del resumen.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent.parent
    json_path = Path(args.json) if args.json else repo_root / "sim/validation/reports/reference_checks.json"

    if not json_path.exists():
        print(f"\n  ERROR: no se encontró {json_path}")
        print("  Ejecuta: python scripts/simulation/validate_reference_cases.py\n")
        return 1

    # Argumentos a pasar a cada sub-script
    json_argv = ["--json", str(json_path)]

    W = 72
    _src = json_path.relative_to(repo_root) if json_path.is_relative_to(repo_root) else json_path
    print()
    print("=" * W)
    print("  Validation Guardrails — SimuFire")
    print(f"  Fuente: {_src}")
    print("=" * W)

    # -- Leer JSON para resumen propio ------------------------------------------
    data = _load_json(json_path)
    req_count    = data.get("required_count",    "?") if data else "?"
    failed_req   = data.get("failed_required_count", "?") if data else "?"
    all_req_pass = data.get("all_required_pass", False) if data else False
    gap_count    = data.get("known_gap_count",   "?") if data else "?"

    # Clasificar los required fallidos: VALID_GAP permitidos vs no permitidos.
    # El gate pasa solo si TODOS los fallos required están en la allowlist
    # KNOWN_VALID_GAP_REQUIRED_FAILURES (documentada en GAPS_INVENTORY.md).
    checks = data.get("checks", []) if data else []
    valid_gap_fails, unexpected_fails = gap_inventory_check.classify_required_failures(checks)
    if not all_req_pass and not valid_gap_fails and not unexpected_fails:
        # JSON declara fallos required pero checks no los contiene → corrupto.
        unexpected_fails = ["<inconsistencia: all_required_pass=False sin checks required fallidos>"]
    req_ok = not unexpected_fails

    # -- Ejecutar guardrails ----------------------------------------------------
    rc_sentinel,   out_sentinel   = _run_silent(phase2e_preflight.main, json_argv)
    _,             out_gaps       = _run_silent(gap_inventory_check.main, json_argv)
    rc_gaps,       out_gap_sync   = _check_gap_inventory_sync(
        data, repo_root / "docs/validation/GAPS_INVENTORY.md"
    )
    rc_carbon,     out_carbon     = (0, "(sin datos)") if data is None else _check_carbon_hcn_sentinels(data)
    rc_two_zone,   out_two_zone   = _run_silent(legacy_two_zone_compare.main, ["check-reference"])
    rc_phy_lint,   out_phy_lint   = _check_physics_overrides(repo_root)
    rc_fresh,      out_fresh      = _check_reports_freshness(repo_root, json_path)
    rc_plaus,      out_plaus      = _check_metric_plausibility(repo_root)

    # R0-3: integridad de la verdad CFAST
    rc_cfast_truth = 0
    out_cfast_truth = "(herramienta R0-3 no disponible)"
    if _verify_cfast_truth is not None and _manifest_path is not None:
        if _manifest_path.exists():
            import json as _json
            with open(_manifest_path, encoding="utf-8") as _f:
                _manifest = _json.load(_f)
            _buf = io.StringIO()
            with contextlib.redirect_stdout(_buf):
                _ok = _verify_cfast_truth(_manifest)
            rc_cfast_truth = 0 if _ok else 1
            out_cfast_truth = _buf.getvalue()
        else:
            out_cfast_truth = "(MANIFEST.json no generado aún — ejecutar: python tools/freeze_cfast_truth.py)"

    # -- Resumen compacto -------------------------------------------------------
    def _tag(rc: int) -> str:
        return "PASS" if rc == 0 else "FAIL"

    req_icon = "OK" if req_ok else "!!"
    if all_req_pass:
        req_label = f"{req_count}/{req_count} PASS"
    elif req_ok:
        req_label = f"PASS ({len(valid_gap_fails)} VALID_GAP)"
    else:
        req_label = f"FAIL ({len(unexpected_fails)} no permitidos)"

    print()
    print(f"  {'Guardrail':<32}  {'Resultado':>10}")
    print(f"  {'-'*32}  {'-'*10}")
    print(f"  {'Required checks':<32}  {req_label:>12}  [{req_icon}]")
    print(f"  {'Known gaps (JSON)':<32}  {str(gap_count):>12}")
    print(f"  {'Gap inventory sync':<32}  {_tag(rc_gaps):>12}")
    print(f"  {'Phase 2E sentinels (7)':<32}  {_tag(rc_sentinel):>12}")
    print(f"  {'Carbon/HCN sentinels (5)':<32}  {_tag(rc_carbon):>12}")
    print(f"  {'Legacy/two-zone contract':<32}  {_tag(rc_two_zone):>12}")
    print(f"  {'CFAST truth integrity (R0-3)':<32}  {_tag(rc_cfast_truth):>12}")
    print(f"  {'Physics override linter (R1-3)':<32}  {_tag(rc_phy_lint):>12}")
    print(f"  {'Reports freshness (R2-1)':<32}  {_tag(rc_fresh):>12}")
    print(f"  {'Metric plausibility (PHY-P1)':<32}  {_tag(rc_plaus):>12}")

    # -- Salida verbose ---------------------------------------------------------
    if args.verbose:
        print()
        print("─" * W)
        print("  [Detalle] Phase 2E Preflight")
        print("─" * W)
        print(out_sentinel)
        print("─" * W)
        print("  [Detalle] Gap Inventory Check")
        print("─" * W)
        print(out_gap_sync)
        print(out_gaps)
        print("─" * W)
        print("  [Detalle] Carbon/HCN Sentinels (PHY-C1/C2)")
        print("─" * W)
        print(out_carbon)
        print("─" * W)
        print("  [Detalle] Legacy/two-zone contract (Pre-M1)")
        print("─" * W)
        print(out_two_zone)
        print("─" * W)
        print("  [Detalle] Physics override linter (R1-3)")
        print("─" * W)
        print(out_phy_lint)
        print("─" * W)
        print("  [Detalle] Reports freshness (R2-1)")
        print("─" * W)
        print(out_fresh)
        print("─" * W)
        print("  [Detalle] Metric plausibility (PHY-P1)")
        print("─" * W)
        print(out_plaus)

    # -- Resultado global -------------------------------------------------------
    all_ok = (req_ok and rc_sentinel == 0 and rc_gaps == 0
              and rc_carbon == 0 and rc_two_zone == 0
              and rc_cfast_truth == 0 and rc_phy_lint == 0
              and rc_fresh == 0 and rc_plaus == 0)
    print()
    print("-" * W)
    print()
    if all_ok:
        print("  ALL GUARDRAILS PASS -- working tree listo.")
        if valid_gap_fails:
            print(f"    ({len(valid_gap_fails)} required FAIL aceptados como VALID_GAP — "
                  "ver GAPS_INVENTORY.md)")
    else:
        print("  GUARDRAIL(S) FAILED:")
        if not req_ok:
            print(f"    - Required checks: {len(unexpected_fails)} FAIL(s) no permitidos:")
            for n in unexpected_fails:
                print(f"        {n}")
        if rc_sentinel != 0:
            print("    - Phase 2E sentinels: ejecuta --verbose para detalles")
        if rc_gaps != 0:
            print("    - Gap inventory sync: ejecuta --verbose para detalles")
        if rc_carbon != 0:
            print("    - Carbon/HCN sentinels: ejecuta --verbose para detalles")
        if rc_two_zone != 0:
            print("    - Legacy/two-zone contract: regenera o corrige la referencia Pre-M1")
        if rc_cfast_truth != 0:
            print("    - CFAST truth integrity: CSVs modificados — ejecutar regenerate_truth.ps1 si fue intencionado")
        if rc_phy_lint != 0:
            print("    - Physics override linter (R1-3): elimina engine knobs de los JSONs de validación")
        if rc_fresh != 0:
            print("    - Reports freshness (R2-1): motor/casos más recientes que el reporte — regenerar")
        if rc_plaus != 0:
            print("    - Metric plausibility (PHY-P1): métricas ppm > 100% no registradas — investigar")
        print()
        print("  Para diagnóstico completo:")
        print("    python scripts/simulation/validation_guardrails.py --verbose")

    print("=" * W)
    print()

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
