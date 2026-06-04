#!/usr/bin/env python3
"""Freeze and compare the Pre-M1 legacy/two-zone validation contract."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / "sim" / "validation" / "legacy_two_zone_manifest.json"
DEFAULT_REFERENCE = ROOT / "sim" / "validation" / "baselines" / "contracts" / "legacy_two_zone_reference.json"
DEFAULT_LEGACY_REPORTS = ROOT / "sim" / "validation" / "reports" / "mode_comparison" / "legacy"
DEFAULT_CANDIDATE_REPORTS = ROOT / "sim" / "validation" / "reports" / "mode_comparison" / "two-zone"
DEFAULT_COMPARISON = ROOT / "sim" / "validation" / "reports" / "contracts" / "legacy_two_zone_comparison.json"


class ContractError(RuntimeError):
    pass


def _load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ContractError(f"No se pudo leer JSON {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ContractError(f"JSON raiz no es objeto: {path}")
    return data


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _cases(manifest: dict[str, Any]) -> dict[str, Any]:
    cases = manifest.get("cases")
    if not isinstance(cases, dict) or not cases:
        raise ContractError("El manifiesto no contiene cases")
    return cases


def _git_head() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def validate_reference(manifest: dict[str, Any], reference: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if reference.get("format_version") != manifest.get("format_version"):
        errors.append("format_version no coincide")
    if reference.get("engine_mode") != "legacy":
        errors.append("engine_mode de la referencia debe ser legacy")

    ref_cases = reference.get("cases")
    if not isinstance(ref_cases, dict):
        return errors + ["la referencia no contiene cases"]

    manifest_cases = _cases(manifest)
    if set(ref_cases) != set(manifest_cases):
        errors.append("los casos de la referencia no coinciden exactamente con el manifiesto")

    for case_name, case_spec in manifest_cases.items():
        ref_case = ref_cases.get(case_name, {})
        ref_metrics = ref_case.get("metrics", {}) if isinstance(ref_case, dict) else {}
        spec_metrics = case_spec.get("metrics", {}) if isinstance(case_spec, dict) else {}
        if set(ref_metrics) != set(spec_metrics):
            errors.append(f"{case_name}: las metricas congeladas no coinciden con el manifiesto")
            continue
        for metric_name, value in ref_metrics.items():
            if not _is_number(value):
                errors.append(f"{case_name}.{metric_name}: valor legacy no numerico/finito")
    return errors


def freeze_reference(
    manifest: dict[str, Any],
    reports_dir: Path,
    output_path: Path,
) -> dict[str, Any]:
    frozen_cases: dict[str, Any] = {}
    for case_name, case_spec in _cases(manifest).items():
        report_path = reports_dir / f"{case_name}.json"
        report = _load_json(report_path)
        if report.get("case") != case_name:
            raise ContractError(f"{case_name}: nombre de caso incorrecto en {report_path}")
        if report.get("engine_mode") != "legacy":
            raise ContractError(f"{case_name}: solo se puede congelar un reporte engine_mode=legacy")
        baseline = report.get("baseline", {})
        if isinstance(baseline, dict) and baseline and baseline.get("all_pass") is False:
            raise ContractError(f"{case_name}: baseline del caso FAIL; no se congela")
        report_metrics = report.get("metrics", {})
        if not isinstance(report_metrics, dict):
            raise ContractError(f"{case_name}: metrics ausente")

        values: dict[str, float] = {}
        for metric_name in case_spec.get("metrics", {}):
            value = report_metrics.get(metric_name)
            if not _is_number(value):
                raise ContractError(f"{case_name}.{metric_name}: metrica ausente/no numerica")
            values[metric_name] = float(value)
        frozen_cases[case_name] = {
            "sim_time_s": float(report.get("sim_time_s", 0.0)),
            "metrics": values,
        }

    reference = {
        "format_version": manifest.get("format_version", 1),
        "engine_mode": "legacy",
        "frozen_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_commit": _git_head(),
        "manifest": str(DEFAULT_MANIFEST.relative_to(ROOT)).replace("\\", "/"),
        "cases": frozen_cases,
    }
    _write_json(output_path, reference)
    return reference


def _evaluate_metric(legacy: float, candidate: float, rule: dict[str, Any]) -> dict[str, Any]:
    delta = candidate - legacy
    abs_delta = abs(delta)
    relative_delta = abs_delta / max(abs(legacy), 1e-12)
    checks: list[bool] = []
    allowed_delta: float | None = None

    if "abs_tolerance" in rule or "rel_tolerance" in rule:
        allowed_delta = max(
            float(rule.get("abs_tolerance", 0.0)),
            abs(legacy) * float(rule.get("rel_tolerance", 0.0)),
        )
        checks.append(abs_delta <= allowed_delta + 1e-12)
    if "min_value" in rule:
        checks.append(candidate >= float(rule["min_value"]))
    if "max_value" in rule:
        checks.append(candidate <= float(rule["max_value"]))
    if "max_abs_value" in rule:
        checks.append(abs(candidate) <= float(rule["max_abs_value"]))

    return {
        "legacy": legacy,
        "candidate": candidate,
        "delta": delta,
        "abs_delta": abs_delta,
        "relative_delta": relative_delta,
        "allowed_delta": allowed_delta,
        "required": bool(rule.get("required", True)),
        "rule": rule,
        "pass": all(checks) if checks else True,
    }


def compare_reports(
    manifest: dict[str, Any],
    reference: dict[str, Any],
    candidate_dir: Path,
    expected_mode: str,
) -> dict[str, Any]:
    reference_errors = validate_reference(manifest, reference)
    if reference_errors:
        raise ContractError("; ".join(reference_errors))

    required_count = 0
    failed_required_count = 0
    non_gating_count = 0
    failed_non_gating_count = 0
    contract_errors: list[str] = []
    case_results: dict[str, Any] = {}

    for case_name, case_spec in _cases(manifest).items():
        try:
            report = _load_json(candidate_dir / f"{case_name}.json")
        except ContractError as exc:
            contract_errors.append(str(exc))
            continue
        if report.get("case") != case_name:
            contract_errors.append(f"{case_name}: report.case incorrecto")
            continue
        if report.get("engine_mode") != expected_mode:
            contract_errors.append(
                f"{case_name}: engine_mode={report.get('engine_mode')!r}, esperado {expected_mode!r}"
            )
            continue
        candidate_metrics = report.get("metrics", {})
        if not isinstance(candidate_metrics, dict):
            contract_errors.append(f"{case_name}: metrics ausente")
            continue

        checks: dict[str, Any] = {}
        for metric_name, rule in case_spec.get("metrics", {}).items():
            candidate_value = candidate_metrics.get(metric_name)
            legacy_value = reference["cases"][case_name]["metrics"][metric_name]
            if not _is_number(candidate_value):
                contract_errors.append(f"{case_name}.{metric_name}: candidato ausente/no numerico")
                continue
            result = _evaluate_metric(float(legacy_value), float(candidate_value), rule)
            checks[metric_name] = result
            if result["required"]:
                required_count += 1
                if not result["pass"]:
                    failed_required_count += 1
            else:
                non_gating_count += 1
                if not result["pass"]:
                    failed_non_gating_count += 1
        case_results[case_name] = {
            "rationale": case_spec.get("rationale", ""),
            "checks": checks,
        }

    all_required_pass = not contract_errors and failed_required_count == 0
    return {
        "format_version": manifest.get("format_version", 1),
        "reference_mode": "legacy",
        "candidate_mode": expected_mode,
        "reference_source_commit": reference.get("source_commit", "unknown"),
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "required_count": required_count,
        "failed_required_count": failed_required_count,
        "non_gating_count": non_gating_count,
        "failed_non_gating_count": failed_non_gating_count,
        "contract_errors": contract_errors,
        "all_required_pass": all_required_pass,
        "cases": case_results,
    }


def _print_comparison(result: dict[str, Any]) -> None:
    print()
    print("=" * 72)
    print("  Legacy / Two-Zone Comparison")
    print("=" * 72)
    print(f"  Candidate mode       : {result['candidate_mode']}")
    print(
        f"  Required comparisons : "
        f"{result['required_count'] - result['failed_required_count']}/{result['required_count']} PASS"
    )
    print(
        f"  Non-gating deltas    : "
        f"{result['failed_non_gating_count']}/{result['non_gating_count']} outside observation tolerance"
    )
    print(f"  Contract errors      : {len(result['contract_errors'])}")
    print(f"  Result               : {'PASS' if result['all_required_pass'] else 'FAIL'}")
    print("=" * 72)
    print()


def _path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ROOT / path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    parser.add_argument("--reference", default=str(DEFAULT_REFERENCE))
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("check-reference")

    freeze_parser = subparsers.add_parser("freeze")
    freeze_parser.add_argument("--reports-dir", default=str(DEFAULT_LEGACY_REPORTS))
    freeze_parser.add_argument("--output", default=str(DEFAULT_REFERENCE))

    compare_parser = subparsers.add_parser("compare")
    compare_parser.add_argument("--candidate-dir", default=str(DEFAULT_CANDIDATE_REPORTS))
    compare_parser.add_argument("--expected-mode", choices=["legacy", "two-zone"], default="two-zone")
    compare_parser.add_argument("--output", default=str(DEFAULT_COMPARISON))

    args = parser.parse_args(argv)
    try:
        manifest = _load_json(_path(args.manifest))
        reference_path = _path(args.reference)
        if args.command == "freeze":
            reference = freeze_reference(manifest, _path(args.reports_dir), _path(args.output))
            errors = validate_reference(manifest, reference)
            if errors:
                raise ContractError("; ".join(errors))
            print(f"Referencia legacy congelada: {_path(args.output)}")
            return 0

        reference = _load_json(reference_path)
        errors = validate_reference(manifest, reference)
        if errors:
            raise ContractError("; ".join(errors))
        if args.command == "check-reference":
            metric_count = sum(len(case["metrics"]) for case in reference["cases"].values())
            print(f"Legacy/two-zone contract PASS: {len(reference['cases'])} casos, {metric_count} metricas")
            return 0

        result = compare_reports(manifest, reference, _path(args.candidate_dir), args.expected_mode)
        _write_json(_path(args.output), result)
        _print_comparison(result)
        return 0 if result["all_required_pass"] else 1
    except ContractError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
