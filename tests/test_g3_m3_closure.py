"""The long closure may not start on incomplete/changed M3 evidence. Offline."""
import copy

import pytest

from scripts.simulation import run_g3_o2_m3_closure as closure


def inputs():
    current = {"synthetic": "digest"}
    campaign = {"declared": 14, "executed": 14, "killed_where_expected": 14,
                "originals_intact": True, "sources_before": current, "sources_after": current}
    evidence = {"sources_sha256_raw": current,
                "campaigns": {"integration": copy.deepcopy(campaign), "owner": copy.deepcopy(campaign)},
                "off": {"identical_cases": 9, "total_cases": 9, "clean_launches": 9},
                "unlimited": {"identical_controls": 4}}
    case = {"whole": True, "budget": {"steps": 10800, "closes_in_every_step": True},
            "heat_budget": {"steps": 10800, "largest_step_gap_kg": 0.0, "no_late_clipping": True}}
    houses = {"stage": "houses", "state": "passed", "sources_sha256_raw": current,
              "houses": {"o2_closed": copy.deepcopy(case), "o2_reopen_300": copy.deepcopy(case)}}
    return evidence, houses, current


def test_complete_evidence_allows_the_next_closure_stage_without_launching_it():
    closure.require_prerequisites(*inputs())


@pytest.mark.parametrize("defect", ["engine", "owner", "integration", "off", "unlimited", "unfinished",
                                   "changed_case", "refusal", "steps", "balance", "heat", "clip"])
def test_incomplete_evidence_is_refused_before_launch(defect):
    evidence, houses, current = inputs()
    if defect == "engine":
        houses["sources_sha256_raw"] = {"synthetic": "other"}
    elif defect in ("owner", "integration"):
        evidence["campaigns"][defect]["killed_where_expected"] = 13
    elif defect == "off":
        evidence["off"]["identical_cases"] = 8
    elif defect == "unlimited":
        evidence["unlimited"]["identical_controls"] = 3
    elif defect == "unfinished":
        houses["state"] = "in_progress"
    elif defect == "changed_case":
        houses["houses"]["simplified"] = houses["houses"].pop("o2_closed")
    else:
        case = houses["houses"]["o2_closed"]
        if defect == "refusal":
            case["whole"] = False
        elif defect == "steps":
            case["budget"]["steps"] = 10799
        elif defect == "balance":
            case["budget"]["closes_in_every_step"] = False
        elif defect == "heat":
            case["heat_budget"]["largest_step_gap_kg"] = 1e-8
        elif defect == "clip":
            case["heat_budget"]["no_late_clipping"] = False
    with pytest.raises(RuntimeError):
        closure.require_prerequisites(evidence, houses, current)
