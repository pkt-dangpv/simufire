"""Isolated, reproducible post-simulation analyses and bound Q&A.

Analysis is entirely deterministic. Only `ask` calls Ollama, unless the caller
supplies a classifier (the deterministic tests do so).
"""

import argparse
import copy
import hashlib
from importlib.metadata import version
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))

from analyzer.build_grounded_facts import build_facts
from analyzer.assessment_coverage import build_assessment_coverage
from analyzer.measurement_evidence import snapshot
from analyzer.fire_event_analyzer import analyze_timeline
from knowledge.context_builder import build_context
from knowledge.retriever import load_entries
from llm.plan_question import create_question_plan
from llm.question_context import context_fingerprint, load_schema, unique_index, validate_context, validate_schema
from llm.render_question_answer import render_question_answer


PIPELINE_VERSION = "0.3"
ARTIFACTS = (
    "scenario.json", "states.json", "thresholds.json", "knowledge.json",
    "events.json", "facts.json", "context.json",
)


def validate_identifier(value):
    # Portable directory names, including Windows device-name restrictions.
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", value):
        raise ValueError("Identificador: usa 1–80 letras ASCII, números, guiones o guiones bajos")
    if value.upper() in {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}:
        raise ValueError("Identificador reservado en Windows")
    return value


def read_json(path):
    def pairs(items):
        value = {}
        for key, item in items:
            if key in value:
                raise ValueError(f"Clave JSON duplicada: {key}")
            value[key] = item
        return value

    def invalid_constant(value):
        raise ValueError(f"Número JSON no finito: {value}")

    return json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=pairs,
                      parse_constant=invalid_constant)


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True,
                                    allow_nan=False) + "\n", encoding="utf-8")


def engine_fingerprint():
    """Record deterministic source/schema content rather than an uncommitted Git HEAD."""
    sources = [BASE_DIR / name for name in (
        "pipeline.py", "analyzer/fire_event_analyzer.py", "analyzer/action_context.py",
        "analyzer/build_grounded_facts.py", "knowledge/context_builder.py",
        "llm/question_context.py",
        "analyzer/assessment_coverage.py", "analyzer/measurement_evidence.py", "llm/question_scope.py",
    )]
    sources.extend(sorted((BASE_DIR / "schemas").glob("*.json")))
    return context_fingerprint({
        path.relative_to(BASE_DIR).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sources
    })


def normalize_inputs(scenario, states, thresholds, entries):
    # Reject NaN/Infinity before schema checks; deep copies prevent caller mutation.
    values = copy.deepcopy([scenario, states, thresholds, entries])
    context_fingerprint(values)
    scenario, states, thresholds, entries = values
    validate_schema(scenario, load_schema("scenario.schema.json"), "Escenario")
    if scenario["schema_version"] != "0.1":
        raise ValueError("Versión de escenario no soportada")
    duration = scenario["simulation"]["duration_s"]
    rooms = unique_index(scenario["compartments"], "id")
    openings = unique_index(scenario["openings"], "id")
    fires = unique_index(scenario["fires"], "id")
    for opening in openings.values():
        endpoints = (opening["from"], opening["to"])
        if any(item not in rooms and item != "outside" for item in endpoints) or not any(item in rooms for item in endpoints):
            raise ValueError("Apertura con compartimentos desconocidos")
    for fire in fires.values():
        if fire["compartment"] not in rooms:
            raise ValueError("Fuego en compartimento desconocido")
    action_keys = set()
    for action in scenario["actions"]:
        key = (action["time_s"], action["type"], action["target"])
        if key in action_keys:
            raise ValueError("Acción duplicada")
        action_keys.add(key)
        targets = openings if action["type"] in ("open", "close", "break") else {**fires, **rooms}
        if action["target"] not in targets or action["time_s"] > duration:
            raise ValueError("Acción con target o tiempo inválido")
    if not isinstance(states, list) or not states:
        raise ValueError("Se necesita al menos un estado de simulación")
    times = set()
    for state in states:
        validate_schema(state, load_schema("simulation_state.schema.json"), "Estado")
        if state["schema_version"] != "0.1":
            raise ValueError("Versión de estado no soportada")
        if state["scenario_id"] != scenario["scenario_id"]:
            raise ValueError("Estado de otro escenario")
        if state["time_s"] in times or state["time_s"] > duration:
            raise ValueError("Tiempo de estado duplicado o fuera de duración")
        times.add(state["time_s"])
        state_rooms = unique_index(state["compartments"], "id")
        if set(state_rooms) != set(rooms):
            raise ValueError("Los compartimentos del estado no coinciden con el escenario")
        for room_id, room in state_rooms.items():
            if room["interface_height_m"] > rooms[room_id]["height_m"]:
                raise ValueError("Interfaz de humo fuera del compartimento")
        state["compartments"].sort(key=lambda item: item["id"])
    for key in ("compartments", "openings", "fires"):
        scenario[key].sort(key=lambda item: item["id"])
    scenario["actions"].sort(key=lambda item: (item["time_s"], item["type"], item["target"]))
    states.sort(key=lambda item: item["time_s"])
    validate_schema(thresholds, load_schema("analyzer_thresholds.schema.json"), "Umbrales")
    if not isinstance(entries, list):
        raise ValueError("El conocimiento debe ser una lista")
    for entry in entries:
        validate_schema(entry, load_schema("knowledge_entry.schema.json"), "Conocimiento")
    unique_index(entries, "knowledge_id")
    entries.sort(key=lambda item: item["knowledge_id"])
    return scenario, states, thresholds, entries


def build_analysis(scenario, states, run_id, *, thresholds=None, entries=None):
    validate_identifier(run_id)
    thresholds = read_json(BASE_DIR / "config/analyzer_thresholds.json") if thresholds is None else thresholds
    entries = load_entries() if entries is None else entries
    scenario, states, thresholds, entries = normalize_inputs(scenario, states, thresholds, entries)
    events = analyze_timeline(states, scenario, thresholds)
    fact_scenario = copy.deepcopy(scenario)
    # The input scenario can contain a schedule beyond the recorded states.
    # Such actions are not recorded occurrences in this analysis.
    fact_scenario["actions"] = [action for action in scenario["actions"]
                               if states[0]["time_s"] <= action["time_s"] <= states[-1]["time_s"]]
    facts = build_facts(fact_scenario, events)
    coverage = build_assessment_coverage(scenario, states, thresholds)
    context = build_context(scenario["scenario_id"], facts, events, entries, run_id=run_id,
                            analysis_coverage=coverage, include_general_knowledge=True,
                            measurement_snapshot=snapshot(scenario, states, thresholds))
    artifacts = dict(zip(ARTIFACTS, (scenario, states, thresholds, entries, events, facts, context)))
    manifest = {
        "schema_version": "0.1", "pipeline_version": PIPELINE_VERSION,
        "run_id": run_id, "scenario_id": scenario["scenario_id"],
        "engine_sha256": engine_fingerprint(),
        "runtime_versions": {"python": sys.version.split()[0], "jsonschema": version("jsonschema")},
        "artifact_sha256": {name: context_fingerprint(value) for name, value in artifacts.items()},
    }
    return {"manifest.json": manifest, **artifacts}


def publish_directory(destination, artifacts):
    """Publish a complete directory in one rename, refusing an existing result."""
    destination = Path(destination)
    if destination.exists():
        raise FileExistsError(f"Ya existe {destination}; usa otro identificador")
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Coordinate concurrent writers and avoid replacing even an empty directory.
    lock = destination.parent / f".{destination.name}.lock"
    temporary = None
    lock_file = lock.open("x", encoding="utf-8")
    try:
        if destination.exists():
            raise FileExistsError(f"Ya existe {destination}; usa otro identificador")
        temporary = Path(tempfile.mkdtemp(prefix=".simufire-", dir=destination.parent))
        for name, value in artifacts.items():
            write_json(temporary / name, value)
        temporary.rename(destination)
    finally:
        if temporary is not None and temporary.exists():
            if temporary.resolve().parent != destination.parent.resolve() or not temporary.name.startswith(".simufire-"):
                raise ValueError("Carpeta temporal fuera de la ruta de publicación")
            shutil.rmtree(temporary)
        lock_file.close()
        lock.unlink()
    return destination


def analyze_run(scenario, states, run_id, output_root, *, thresholds=None, entries=None):
    artifacts = build_analysis(scenario, states, run_id, thresholds=thresholds, entries=entries)
    return publish_directory(Path(output_root) / run_id, artifacts)


def load_run(run_dir, *, replay=False):
    run_dir = Path(run_dir)
    manifest = read_json(run_dir / "manifest.json")
    validate_schema(manifest, load_schema("analysis_run.schema.json"), "Manifiesto")
    validate_identifier(manifest["run_id"])
    artifacts = {name: read_json(run_dir / name) for name in ARTIFACTS}
    for name, value in artifacts.items():
        if context_fingerprint(value) != manifest["artifact_sha256"][name]:
            raise ValueError(f"Contenido modificado: {name}")
    context = artifacts["context.json"]
    validate_context(context)
    if context.get("run_id") != manifest["run_id"] or context["scenario_id"] != manifest["scenario_id"]:
        raise ValueError("Contexto de otra ejecución o escenario")
    if context.get("source_events") != artifacts["events.json"] or context["scenario_facts"] != artifacts["facts.json"]:
        raise ValueError("Eventos o hechos mezclados en la ejecución")
    if artifacts["scenario.json"]["scenario_id"] != manifest["scenario_id"]:
        raise ValueError("Escenario mezclado en la ejecución")
    if "measurement_snapshot" in context:
        expected = snapshot(artifacts["scenario.json"], artifacts["states.json"], artifacts["thresholds.json"])
        if context["measurement_snapshot"] != expected:
            raise ValueError("Mediciones mezcladas en la ejecución")
    if replay:
        if manifest["engine_sha256"] != engine_fingerprint():
            raise ValueError("El motor ha cambiado; la reproducción exige la misma versión de código")
        if manifest["runtime_versions"] != {"python": sys.version.split()[0], "jsonschema": version("jsonschema")}:
            raise ValueError("La reproducción exige las mismas versiones de Python y jsonschema")
        rebuilt = build_analysis(
            artifacts["scenario.json"], artifacts["states.json"], manifest["run_id"],
            thresholds=artifacts["thresholds.json"], entries=artifacts["knowledge.json"],
        )
        if rebuilt != {"manifest.json": manifest, **artifacts}:
            raise ValueError("El análisis no coincide con su reproducción determinista")
    return {"manifest.json": manifest, **artifacts}


def ask_run(run_dir, question, question_id, *, classifier=None):
    validate_identifier(question_id)
    if not isinstance(question, str) or not question.strip():
        raise ValueError("La pregunta está vacía")
    artifacts = load_run(run_dir)
    destination = Path(run_dir) / "questions" / question_id
    if destination.exists():
        raise FileExistsError("question_id ya existe en esta ejecución")
    context = artifacts["context.json"]
    plan = create_question_plan(context, question, question_id, classifier=classifier)
    answer = render_question_answer(context, plan)
    # Recheck immutable artifacts after a potentially slow Ollama call.
    if load_run(run_dir) != artifacts:
        raise ValueError("La ejecución cambió durante la pregunta")
    publish_directory(destination, {
        "question.json": {"run_id": context["run_id"], "question_id": question_id,
                          "question": question.strip(), "source_context_sha256": context_fingerprint(context)},
        "plan.json": plan, "answer.json": answer,
    })
    return answer


def main():
    parser = argparse.ArgumentParser(description="SimuFire AI: análisis aislados y preguntas")
    commands = parser.add_subparsers(dest="command", required=True)
    analyze = commands.add_parser("analyze")
    analyze.add_argument("--scenario", type=Path, required=True)
    analyze.add_argument("--states-dir", type=Path, required=True, help="Carpeta con estados JSON de una sola ejecución")
    analyze.add_argument("--run-id", required=True)
    analyze.add_argument("--output-root", type=Path, required=True)
    analyze.add_argument("--thresholds", type=Path, default=BASE_DIR / "config/analyzer_thresholds.json")
    ask = commands.add_parser("ask")
    ask.add_argument("--run-dir", type=Path, required=True)
    ask.add_argument("--question-id", required=True)
    ask.add_argument("--question", required=True)
    verify = commands.add_parser("verify")
    verify.add_argument("--run-dir", type=Path, required=True)
    verify.add_argument("--replay", action="store_true", help="Repetir detectores con entradas y conocimiento guardados")
    args = parser.parse_args()
    try:
        if args.command == "analyze":
            states = [read_json(path) for path in sorted(args.states_dir.glob("*.json"))]
            path = analyze_run(read_json(args.scenario), states, args.run_id, args.output_root,
                               thresholds=read_json(args.thresholds))
            print(f"OK: análisis guardado en {path}")
        elif args.command == "ask":
            answer = ask_run(args.run_dir, args.question, args.question_id)
            print(answer["answer"])
            if answer["source_ids"]:
                print("FUENTES: " + ", ".join(answer["source_ids"]))
            print(f"OK: pregunta guardada en {args.run_dir / 'questions' / args.question_id}")
        else:
            load_run(args.run_dir, replay=args.replay)
            print("OK: ejecución verificada" + (" y reproducida" if args.replay else ""))
    except (OSError, ValueError, TimeoutError) as error:
        parser.exit(1, f"ERROR: {error}\n")


if __name__ == "__main__":
    main()
