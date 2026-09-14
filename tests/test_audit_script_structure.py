from __future__ import annotations

import ast
from pathlib import Path
import subprocess

from scripts.simulation import audit_script_structure as audit


ROOT = Path(__file__).resolve().parents[1]


def test_gd_writer_scan_ignores_comments_and_strings() -> None:
    source = '''
# room.o2 = 0.0
var example = "building.state += 1"
func apply_o2():
room.o2 -= consumed
'''
    assert audit.gd_write_candidates("sim/core/Example.gd", source) == [
        {
            "path": "sim/core/Example.gd",
            "line": 5,
            "function": "apply_o2",
            "phase_hint": "runtime",
            "root": "room",
            "field": "o2",
            "operator": "-=",
        }
    ]


def test_gd_writer_scan_classifies_function_phase_hints() -> None:
    source = """
room.o2 = 0.209
func reset_step_counters():
    room.o2_net_transport_kg_step = 0.0
func write_shadow_diagnostics():
    room.phase3_diag_pressure_therm_pa = 1.0
func configure_room():
    room.height_m = 2.4
"""
    writers = audit.gd_write_candidates("sim/core/Example.gd", source)
    assert [writer["function"] for writer in writers] == [
        "<module>",
        "reset_step_counters",
        "write_shadow_diagnostics",
        "configure_room",
    ]
    assert [writer["phase_hint"] for writer in writers] == [
        "module_scope",
        "reset",
        "diagnostic_or_shadow",
        "construction",
    ]


def test_gd_writer_scan_does_not_treat_comparisons_as_assignments() -> None:
    source = "if room.fire == null and room.o2 >= 0.1 and room.o2 != 0.2:\n\tpass\n"
    assert audit.gd_write_candidates("sim/fire/Example.gd", source) == []


def test_gd_comment_stripping_preserves_resource_strings() -> None:
    source = '''
const REAL = preload("res://sim/core/Real.gd") # res://sim/core/Fake.gd
var text = "# still inside a string"
'''
    stripped = audit._gd_without_comments(source)
    assert "res://sim/core/Real.gd" in stripped
    assert "res://sim/core/Fake.gd" not in stripped
    assert "# still inside a string" in stripped


def test_python_entrypoint_distinguishes_cli_and_imported_module() -> None:
    imported = ast.parse("def helper():\n    return 1\n")
    cli = ast.parse('if __name__ == "__main__":\n    raise SystemExit(0)\n')
    assert audit._python_entrypoint("tool.py", imported) == "imported_module"
    assert audit._python_entrypoint("tool.py", cli) == "cli_main_guard"


def test_python_side_effects_are_ast_derived() -> None:
    tree = ast.parse(
        "from pathlib import Path\n"
        "import subprocess\n"
        "Path('out').write_text('x')\n"
        "subprocess.run(['tool'])\n"
        "print('done')\n"
    )
    assert audit.python_side_effects(tree) == [
        "console_or_log_output",
        "external_process",
        "filesystem",
    ]


def test_authority_relevance_is_explicit_for_every_scope() -> None:
    assert audit.authority_relevance_for("runtime_or_application") == "runtime_behavior"
    assert audit.authority_relevance_for("validation") == "validation_contract"
    assert audit.authority_relevance_for("test") == "verification_only"


def test_tarjan_reports_only_real_multi_node_cycles() -> None:
    edges = {"a": {"b"}, "b": {"a"}, "c": {"c"}, "d": set()}
    assert audit._tarjan(list(edges), edges) == [["a", "b"]]


def test_repository_inventory_is_complete_and_has_no_hard_structural_error() -> None:
    result = audit.build_inventory(ROOT)
    summary = result["summary"]
    raw = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT,
    )
    tracked = [
        path
        for part in raw.split(b"\0")
        if part
        for path in [part.decode("utf-8")]
        if (ROOT / path).is_file()
    ]
    expected_scripts = {
        path for path in tracked if Path(path).suffix.lower() in audit.SCRIPT_SUFFIXES
    }

    assert {row["path"] for row in result["scripts"]} == expected_scripts
    assert summary["repository_scripts"] == len(expected_scripts)
    assert summary["python_parse_failures"] == []
    assert summary["duplicate_gdscript_class_names"] == {}
    assert summary["hard_dependency_cycles"] == []
    assert summary["orphan_candidates"] == []
    assert all(row["authority_relevance"] for row in result["scripts"])
    assert all(row["side_effects"] for row in result["scripts"])
    assert all(row["test_coverage"]["status"] for row in result["scripts"])
    assert not any(
        writer["path"] == "sim/core/SimulationStateBuilder.gd"
        for writer in result["state_writers"]
    )
