"""Regression coverage for source-based dependencies and compartment isolation."""

import copy
import json
import sys
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE_DIR))

from analyzer.build_grounded_facts import build_facts
from analyzer.fire_event_analyzer import analyze, analyze_timeline
from llm.plan_question import resolve_fact_dependencies
from llm.question_context import validate_context


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def two_room_scenario():
    scenario = load_json(BASE_DIR / "scenarios/basic_room_001.json")
    scenario["compartments"].append({**scenario["compartments"][0], "id": "room_02"})
    scenario["openings"].append({**scenario["openings"][0], "id": "door_02", "from": "room_02"})
    scenario["fires"].append({**scenario["fires"][0], "id": "fire_02", "compartment": "room_02"})
    return scenario


class GroundedDependencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.basic = load_json(BASE_DIR / "scenarios/basic_room_001.json")
        states = [load_json(p) for p in sorted(
            (BASE_DIR / "tests/data/ventilation_limited_states").glob("vl_case_t*.json"),
        )]
        cls.base_events = analyze_timeline(states, cls.basic)
        cls.templates = {e["event_type"]: e for e in cls.base_events}
        cls.fact_validator = Draft202012Validator(load_json(BASE_DIR / "schemas/grounded_fact.schema.json"))

    def setUp(self):
        self.scenario = two_room_scenario()

    def event(self, kind, time, room="room_01", target="door_01", action_time=None, interval=None):
        event = copy.deepcopy(self.templates[kind])
        event.update(time_s=time, compartment_id=room, event_id=f"{kind}_{time}_{room}_{target}")
        if kind in ("ventilation_increase", "ventilation_limited"):
            event.update(action_target=target, action_time_s=(
                action_time if action_time is not None else time + (kind == "ventilation_limited")
            ))
            if kind == "ventilation_increase":
                event["cause"] = f"{target}_opened"
        if interval is None:
            interval = (time - 1, time + 15) if kind == "ventilation_increase" else (time - 16, time)
            if kind == "ventilation_limited":
                interval = (time - 30, time + 16)
        event["evidence_interval_s"] = dict(zip(("start", "end"), interval))
        return event

    def checked_facts(self, events, scenario=None):
        scenario = scenario or self.scenario
        before = copy.deepcopy((scenario, events))
        facts = build_facts(scenario, events)
        self.assertEqual((scenario, events), before, "The builder mutated source data")
        ids = {f["fact_id"]: f for f in facts}
        self.assertEqual(len(ids), len(facts))
        for fact in facts:
            self.fact_validator.validate(fact)
            self.assertIs(fact["causal"], False)
            selected = []
            resolve_fact_dependencies(fact["fact_id"], ids, selected, set())
            self.assertEqual(selected[-1], fact["fact_id"])
        if facts:
            validate_context({
                "schema_version": "0.1", "scenario_id": scenario["scenario_id"],
                "scenario_facts": facts, "source_events": events, "technical_knowledge": [],
                "rules": {key: True for key in (
                    "scenario_facts_are_authoritative", "knowledge_is_general_theory",
                    "do_not_convert_association_into_causation", "do_not_invent_missing_variables",
                    "do_not_invent_phenomena", "distinguish_scenario_from_general_theory",
                )},
            })
        return facts

    def test_basic_room_keeps_historical_ids_and_dependencies(self):
        facts = self.checked_facts(copy.deepcopy(self.base_events), self.basic)
        self.assertEqual([f["fact_id"] for f in facts], [f"FACT_{i:03d}" for i in range(1, 11)])
        expected = {
            "FACT_002": ["FACT_001"],
            "FACT_006": ["FACT_001", "FACT_002", "FACT_003"],
            "FACT_007": ["FACT_001", "FACT_002", "FACT_005"],
            "FACT_008": ["FACT_004"], "FACT_009": ["FACT_002"],
        }
        for fact in facts:
            self.assertEqual(fact["requires_fact_ids"], expected.get(fact["fact_id"], []))
        self.assertEqual(facts[-1]["certainty"], "moderate")
        self.assertIn("antes de la apertura de door_01", facts[-1]["statement"])

    def test_no_actions_and_sparse_event_sets(self):
        self.scenario["actions"] = []
        for kinds in ([], ["hrr_increase"], ["temperature_increase"],
                      ["smoke_layer_descent"], ["hrr_increase", "temperature_increase"]):
            with self.subTest(kinds=kinds):
                facts = self.checked_facts([self.event(k, 195) for k in kinds])
                for fact in facts:
                    if fact["fact_type"] == "limitation":
                        self.assertEqual(fact["knowledge_topics"], ["smoke_layer"])
                        self.assertEqual(len(fact["requires_fact_ids"]), 1)
                    else:
                        self.assertEqual(fact["requires_fact_ids"], [])

    def test_shifted_numbers_link_actual_action(self):
        self.scenario["actions"].append({"type": "open", "target": "door_02", "time_s": 100})
        events = [self.event("ventilation_increase", 180), self.event("hrr_increase", 195)]
        facts = self.checked_facts(events)
        association = next(f for f in facts if f["knowledge_topics"] == ["ventilation"])
        action = next(f for f in facts if f["fact_type"] == "action" and f["action_target"] == "door_01")
        self.assertEqual(association["requires_fact_ids"], [action["fact_id"]])
        self.assertEqual(action["fact_id"], "FACT_002")
        self.assertEqual(association["fact_id"], "FACT_003")

    def test_other_scenario_and_names_use_their_own_sources(self):
        scenario = copy.deepcopy(self.basic)
        scenario["scenario_id"] = "different_scenario"
        scenario["compartments"][0]["id"] = "kitchen"
        scenario["openings"][0].update(id="kitchen_window", type="window", **{"from": "kitchen"})
        scenario["fires"][0]["compartment"] = "kitchen"
        scenario["actions"][0]["target"] = "kitchen_window"
        events = [self.event("ventilation_increase", 180, "kitchen", "kitchen_window"),
                  self.event("temperature_increase", 195, "kitchen", "kitchen_window")]
        for event in events:
            event["scenario_id"] = "different_scenario"
        facts = self.checked_facts(events, scenario)
        self.assertTrue(all(f["scenario_id"] == "different_scenario" for f in facts))
        self.assertTrue(all(f.get("compartment_id", "kitchen") == "kitchen" for f in facts))
        limitation = next(f for f in facts if f["fact_type"] == "limitation")
        self.assertIn("la ventana", limitation["statement"])
        self.assertEqual(limitation["action_target"], "kitchen_window")

    def test_input_order_does_not_change_facts(self):
        self.scenario["actions"].append({"type": "open", "target": "door_02", "time_s": 100})
        events = [self.event("ventilation_increase", 180), self.event("hrr_increase", 195),
                  self.event("smoke_layer_descent", 195), self.event("temperature_increase", 195)]
        expected = self.checked_facts(events)
        changed = copy.deepcopy(self.scenario)
        for key in ("actions", "openings", "compartments"):
            changed[key].reverse()
        self.assertEqual(self.checked_facts(list(reversed(events)), changed), expected)

    def test_each_opening_keeps_its_own_oxygen_and_limitations(self):
        self.scenario["actions"].append({"type": "open", "target": "door_02", "time_s": 200})
        events = [self.event("ventilation_increase", 180), self.event("hrr_increase", 195),
                  self.event("ventilation_increase", 200, "room_02", "door_02"),
                  self.event("hrr_increase", 215, "room_02", "door_02")]
        facts = self.checked_facts(events)
        by_id = {f["fact_id"]: f for f in facts}
        oxygen = [f for f in facts if f["knowledge_topics"] == ["oxygen"]]
        limitations = [f for f in facts if f["fact_type"] == "limitation"]
        self.assertEqual(len(oxygen), 2)
        self.assertEqual(len(limitations), 2)
        for fact in oxygen + limitations:
            for dependency in fact["requires_fact_ids"]:
                source = by_id[dependency]
                if source["fact_type"] == "action":
                    self.assertEqual(source["action_target"], fact["action_target"])
                if "compartment_id" in source:
                    self.assertEqual(source["compartment_id"], fact["compartment_id"])

    def test_repeated_openings_in_same_room_use_correct_interval(self):
        self.scenario["openings"].append({**self.scenario["openings"][0], "id": "window_01", "type": "window"})
        self.scenario["actions"] = [{"type": "open", "target": "door_01", "time_s": 50},
                                    {"type": "open", "target": "window_01", "time_s": 180}]
        events = [self.event("ventilation_increase", 50), self.event("hrr_increase", 60),
                  self.event("ventilation_increase", 180, target="window_01"),
                  self.event("hrr_increase", 195)]
        facts = self.checked_facts(events)
        limitations = [f for f in facts if f["fact_type"] == "limitation"]
        self.assertEqual([(f["time_s"], f["action_target"]) for f in limitations],
                         [(60, "door_01"), (195, "window_01")])
        self.assertIn("la ventana", limitations[1]["statement"])

    def test_no_causal_limitation_across_rooms_or_before_opening(self):
        for event in (self.event("hrr_increase", 195, "room_02"), self.event("hrr_increase", 175)):
            with self.subTest(event=event["event_id"]):
                facts = self.checked_facts([self.event("ventilation_increase", 180), event])
                self.assertFalse(any(f["fact_type"] == "limitation" for f in facts))

    def test_no_pairing_outside_measurement_interval(self):
        effect = self.event("hrr_increase", 300, interval=(290, 300))
        facts = self.checked_facts([self.event("ventilation_increase", 180), effect])
        self.assertFalse(any(f["fact_type"] == "limitation" for f in facts))

    def test_intervening_local_action_blocks_pairing(self):
        events = [self.event("ventilation_increase", 180), self.event("hrr_increase", 195)]
        for target, expected in (("door_01", 0), ("door_02", 1)):
            with self.subTest(target=target):
                scenario = copy.deepcopy(self.scenario)
                scenario["actions"].append({"type": "close", "target": target, "time_s": 190})
                facts = self.checked_facts(events, scenario)
                self.assertEqual(sum(f["fact_type"] == "limitation" for f in facts), expected)

    def test_limitation_time_and_source_ignore_unrelated_later_event(self):
        effect = self.event("hrr_increase", 195)
        facts = self.checked_facts([self.event("ventilation_increase", 180), effect,
                                    self.event("temperature_increase", 999, "room_02")])
        limitation = next(f for f in facts if f["fact_type"] == "limitation")
        self.assertEqual(limitation["time_s"], 195)
        self.assertEqual(limitation["event_ids"], ["ventilation_increase_180_room_01_door_01", effect["event_id"]])

    def test_missing_previous_value_does_not_create_phantom_dependency(self):
        event = self.event("hrr_increase", 195)
        del event["evidence"][0]["previous_value"]
        facts = self.checked_facts([self.event("ventilation_increase", 180), event])
        self.assertFalse(any("hrr" in f["knowledge_topics"] for f in facts))

    def test_legacy_pattern_chooses_opening_in_its_room(self):
        self.scenario["actions"] = [{"type": "open", "target": "door_02", "time_s": 180},
                                    {"type": "open", "target": "door_01", "time_s": 190}]
        event = self.event("ventilation_limited", 179, action_time=190)
        del event["action_target"], event["action_time_s"]
        fact = self.checked_facts([event])[-1]
        self.assertIn("door_01", fact["statement"])
        self.assertNotIn("door_02", fact["statement"])
        self.assertEqual(fact["action_time_s"], 190)

    def test_pattern_does_not_name_missing_or_ambiguous_opening(self):
        event = self.event("ventilation_limited", 179)
        del event["action_target"], event["action_time_s"]
        for ambiguous in (False, True):
            with self.subTest(ambiguous=ambiguous):
                scenario = copy.deepcopy(self.scenario)
                scenario["actions"] = []
                if ambiguous:
                    scenario["openings"].append({**scenario["openings"][0], "id": "other_door"})
                    scenario["actions"] = [{"type": "open", "target": target, "time_s": 180}
                                            for target in ("door_01", "other_door")]
                fact = self.checked_facts([event], scenario)[-1]
                self.assertNotIn("antes de la apertura", fact["statement"])
                self.assertNotIn("action_target", fact)
                self.assertEqual(fact["certainty"], "moderate")

    def test_rejects_foreign_duplicate_and_invalid_provenance(self):
        event = self.event("ventilation_increase", 180)
        cases = [
            [{**event, "scenario_id": "foreign"}], [event, copy.deepcopy(event)],
            [{**event, "compartment_id": "unknown"}], [{**event, "action_target": "door_02"}],
            [{**event, "action_time_s": 190}],
            [{**event, "evidence_interval_s": {"start": 195, "end": 179}}],
        ]
        for events in cases:
            with self.subTest(events=events):
                with self.assertRaises(ValueError):
                    build_facts(self.scenario, events)

    def test_duplicate_actions_are_rejected(self):
        self.scenario["actions"].append(copy.deepcopy(self.scenario["actions"][0]))
        with self.assertRaisesRegex(ValueError, "Acción duplicada"):
            build_facts(self.scenario, [])

    def test_context_rejects_cycle_missing_event_and_cross_room_reference(self):
        context = load_json(BASE_DIR / "tests/data/instructor_context/basic_room_001_vl_test_instructor.json")
        for kind in ("cycle", "missing_event", "cross_room"):
            with self.subTest(kind=kind):
                changed = copy.deepcopy(context)
                if kind == "cycle":
                    changed["scenario_facts"][0]["requires_fact_ids"] = [changed["scenario_facts"][0]["fact_id"]]
                elif kind == "missing_event":
                    changed["scenario_facts"][0]["event_ids"] = ["missing"]
                else:
                    changed["scenario_facts"][1]["compartment_id"] = "room_02"
                    changed["scenario_facts"][0]["compartment_ids"] = ["room_01"]
                with self.assertRaises(ValueError):
                    validate_context(changed)


class AnalyzerScopeTests(unittest.TestCase):
    def setUp(self):
        self.scenario = two_room_scenario()
        self.before = load_json(BASE_DIR / "tests/data/simulation_states/basic_room_001_t179.json")
        self.after = load_json(BASE_DIR / "tests/data/simulation_states/basic_room_001_t195.json")
        for state in (self.before, self.after):
            state["compartments"].append({**copy.deepcopy(state["compartments"][0]), "id": "room_02"})

    def ventilation_events(self):
        return [e for e in analyze(self.before, self.after, self.scenario)
                if e["event_type"] == "ventilation_increase"]

    def test_opening_does_not_apply_to_unconnected_room(self):
        events = self.ventilation_events()
        self.assertEqual([e["compartment_id"] for e in events], ["room_01"])
        self.assertEqual(events[0]["action_target"], "door_01")
        self.assertEqual(events[0]["action_time_s"], 180)
        self.assertEqual(events[0]["evidence_interval_s"], {"start": 179, "end": 195})

    def test_internal_opening_applies_to_both_endpoints(self):
        self.scenario["openings"][0]["to"] = "room_02"
        self.assertEqual({e["compartment_id"] for e in self.ventilation_events()}, {"room_01", "room_02"})

    def test_unknown_target_does_not_gain_an_association(self):
        self.scenario["actions"][0]["target"] = "unknown_door"
        self.assertEqual(self.ventilation_events(), [])

    def test_multiple_local_actions_are_not_attributed_to_one_opening(self):
        self.scenario["openings"].append({**self.scenario["openings"][0], "id": "other_door"})
        self.scenario["actions"].append({"type": "open", "target": "other_door", "time_s": 185})
        self.assertEqual(self.ventilation_events(), [])
        self.assertTrue(any(e["event_type"] == "hrr_increase" for e in analyze(self.before, self.after, self.scenario)))

    def test_separate_rooms_keep_separate_openings(self):
        self.scenario["actions"].append({"type": "open", "target": "door_02", "time_s": 185})
        self.assertEqual({(e["compartment_id"], e["action_target"]) for e in self.ventilation_events()},
                         {("room_01", "door_01"), ("room_02", "door_02")})

    def pattern_events(self):
        states = [load_json(p) for p in sorted(
            (BASE_DIR / "tests/data/ventilation_limited_states").glob("vl_case_t*.json"),
        )]
        for state in states:
            state["compartments"].append({**copy.deepcopy(state["compartments"][0]), "id": "room_02"})
        return [e for e in analyze_timeline(states, self.scenario) if e["event_type"] == "ventilation_limited"]

    def test_pattern_is_scoped_and_keeps_physical_flags(self):
        events = self.pattern_events()
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["compartment_id"], "room_01")
        self.assertEqual(events[0]["cause"], "temporal_pattern")
        self.assertEqual(events[0]["confidence"], 0.85)
        self.assertEqual(events[0]["action_target"], "door_01")
        self.assertEqual(events[0]["evidence_interval_s"], {"start": 150, "end": 195})

    def test_pattern_rejects_intervening_local_action(self):
        self.scenario["actions"].append({"type": "close", "target": "door_01", "time_s": 185})
        self.assertEqual(self.pattern_events(), [])

    def test_fractional_times_keep_distinct_event_ids(self):
        first = copy.deepcopy(self.after)
        second = copy.deepcopy(self.after)
        first["time_s"], second["time_s"] = 195.1, 195.9
        second["compartments"][0]["hrr_kw"] *= 2
        events_a = analyze(self.before, first, self.scenario)
        events_b = analyze(first, second, self.scenario)
        hrr_a = next(e for e in events_a if e["event_type"] == "hrr_increase" and e["compartment_id"] == "room_01")
        hrr_b = next(e for e in events_b if e["event_type"] == "hrr_increase")
        self.assertNotEqual(hrr_a["event_id"], hrr_b["event_id"])
        build_facts(self.scenario, events_a + events_b)

    def test_action_order_and_unrelated_room_do_not_change_pattern(self):
        self.scenario["actions"].append({"type": "open", "target": "door_02", "time_s": 185})
        expected = self.pattern_events()
        self.scenario["actions"].reverse()
        self.assertEqual(self.pattern_events(), expected)
        self.assertEqual({(e["compartment_id"], e["action_target"]) for e in expected},
                         {("room_01", "door_01"), ("room_02", "door_02")})


if __name__ == "__main__":
    unittest.main(verbosity=2)
