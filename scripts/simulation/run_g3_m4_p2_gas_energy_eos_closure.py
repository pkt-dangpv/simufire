"""Sequential R2-1 closure stages for the isolated M4-P2 gas/energy/EOS addition.

Requires a current audited control and the 16 predeclared kills; no source mutation,
commit, push, product activation, lowering of the memory gate or direct Godot
invocation. Any reference difference beyond generated_at stops the stage.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch
from scripts.simulation import audit_g3_m4_p2_gas_energy_eos as audit
from scripts.simulation import run_g3_m4_p2_gas_energy_eos as pure
from scripts.simulation import run_g3_m4_p2_gas_energy_eos_mutations as mutants
from scripts.simulation import run_g3_o2_transport_closure as safe
from scripts.simulation import run_g3_o2_transport_gate as gate


def prerequisites(control, campaign, current, control_path):
    if (control.get("state") != "passed" or control.get("source_sha256_raw") != current
            or control.get("integration_validated") is not False
            or control.get("product_properties_chosen") is not False
            or control.get("engine_timestep_sensitivity_resolved") is not False):
        raise RuntimeError("control no longer binds current sources/scope")
    payload = json.loads((Path(control_path) / "payload.json").read_text(encoding="utf-8"))
    audit.audit_payload(payload)
    if (campaign.get("error") is not None or campaign.get("integration_validated") is not False
            or campaign.get("declared") != len(mutants.MUTATIONS)
            or campaign.get("executed") != len(mutants.MUTATIONS)
            or campaign.get("killed_where_expected") != len(mutants.MUTATIONS)
            or not campaign.get("originals_intact") or not campaign.get("all_sources_restored")
            or campaign.get("source_sha256_raw") != current
            or campaign.get("sha256_before") != campaign.get("sha256_after")
            or campaign.get("sha256_after") != {pure.MODEL: current[pure.MODEL]}):
        raise RuntimeError("mutation campaign incomplete or stale")
    results = campaign.get("results", [])
    if len(results) != len(mutants.MUTATIONS) + 1 or results[0]["verdict"] != "pass":
        raise RuntimeError("missing mutation control")
    if {r["name"] for r in results[1:]} != set(mutants.MUTATIONS):
        raise RuntimeError("mutation coverage")
    declared = mutants.harness.machinery.plan(mutants.MUTATIONS, tuple(mutants.MUTATIONS))
    _, variants = mutants.harness.machinery.prepared(mutants.MUTATIONS, (pure.MODEL,))
    if campaign.get("plan") != declared:
        raise RuntimeError("mutation plan changed")
    for item in results:
        if item["name"] != "control":
            expected = declared[item["name"]]["expected_in"]
            variant_sha = mutants.harness.sha(variants[item["name"]][1].encode("utf-8"))
            if (item["verdict"] != "killed" or not item["seen_where_expected"]
                    or item.get("expected_in") != expected
                    or not any(f.startswith(expected) for f in item.get("failures", []))
                    or item.get("mutant_sha256") != variant_sha):
                raise RuntimeError("mutation not killed at current declared bytes/assertion")
        if (godot_monitored_launch.infrastructure_faults(item["health"])
                or item["health"].get("cleanup_terminated_pids") != []):
            raise RuntimeError("unhealthy mutant/control")
    if (godot_monitored_launch.infrastructure_faults(control["health"])
            or control["health"].get("cleanup_terminated_pids") != []):
        raise RuntimeError("unhealthy pure fixture")


def source_inventory():
    paths = set(gate.git("ls-files", "sim/", "tools/run_scenario_headless.gd").decode().splitlines())
    paths.add(pure.MODEL)  # same set before and after staging this isolated addition
    return {p: hashlib.sha256((ROOT / p).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
            for p in sorted(paths)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=("reference", "product", "guardrails", "global"), required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--control", type=Path, required=True)
    parser.add_argument("--mutations", type=Path, required=True)
    args = parser.parse_args()
    if not sys.flags.utf8_mode:
        raise RuntimeError("use python -X utf8")
    os.environ.update(PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
    work = args.work.resolve()
    gate.prepare_environment(work)
    os.environ["SIMUFIRE_GODOT_TEST_APPDATA"] = str(work / "appdata")
    os.chdir(ROOT)
    control = json.loads(args.control.read_text(encoding="utf-8"))
    campaign = json.loads(args.mutations.read_text(encoding="utf-8"))
    current = pure.current_hashes()
    prerequisites(control, campaign, current, args.control.resolve().parent)
    sources, uids = source_inventory(), safe.preserved_files()
    stashes = gate.git("stash", "list", "--format=%H").decode().splitlines()
    corpus_before = safe.corpus()
    reference_before = json.loads((ROOT / safe.REFERENCE).read_text(encoding="utf-8"))
    record = {"schema": "g3_m4p2_closure_stage_v1", "state": "in_progress", "stage": args.stage,
              "source_sha256_raw": current, "sources_lf_sha256": sources,
              "preserved_uid_sha256": uids, "stashes": stashes,
              "integration_validated": False, "product_properties_chosen": False,
              "engine_timestep_sensitivity_resolved": False}
    commands = {
        "reference": ([sys.executable, "scripts/simulation/run_reference_suite_monitored.py"], 7200),
        "product": ([sys.executable, "scripts/check_product.py"], 2400),
        "guardrails": ([sys.executable, "scripts/simulation/validation_guardrails.py"], 300),
        "global": ([sys.executable, "-m", "pytest", "tests", "-q", "-p", "no:cacheprovider",
                    "--basetemp", str(work / "pytest-global")], 3600),
    }
    safe.emit(work / "result.json", record)
    try:
        command, timeout = commands[args.stage]
        record["execution"] = safe.monitored(args.stage, command, work, timeout)
        if args.stage == "reference":
            after = safe.corpus()
            changed = sorted(p for p in corpus_before.keys() | after.keys() if corpus_before.get(p) != after.get(p))
            new = json.loads((ROOT / safe.REFERENCE).read_text(encoding="utf-8"))
            strip_time = lambda value: {k: v for k, v in value.items() if k != "generated_at"}
            if (changed != [safe.REFERENCE] or strip_time(reference_before) != strip_time(new)
                    or (new["required_count"], new["failed_required_count"], new["known_gap_count"]) != (346, 0, 78)):
                raise RuntimeError("reference changes beyond generated_at: " + repr(changed))
            record["corpus"] = {"raw_before": corpus_before, "raw_after": after,
                                "files": len(corpus_before), "identical": len(corpus_before) - 1,
                                "changed": changed, "only_generated_at": True,
                                "required": 346, "failed_required": 0, "gaps": 78}
        new_sources = source_inventory()
        if set(new_sources) != set(sources) or any(
                new_sources[p] != sha for p, sha in sources.items() if p != safe.REFERENCE):
            raise RuntimeError("runtime sources changed during closure")
        if pure.current_hashes() != current:
            raise RuntimeError("pure sources changed during closure")
        if uids != safe.preserved_files() or stashes != gate.git("stash", "list", "--format=%H").decode().splitlines():
            raise RuntimeError("UID/stashes changed")
        record["state"] = "passed"
    except Exception as exc:
        record.update(state="failed", error=str(exc))
        raise
    finally:
        safe.emit(work / "result.json", record)
        print(f"M4-P2 {args.stage}: {record['state']}; {work}", flush=True)


if __name__ == "__main__":
    main()
