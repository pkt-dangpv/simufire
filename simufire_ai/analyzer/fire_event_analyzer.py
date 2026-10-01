import json
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

SCENARIO_PATH = (
    BASE_DIR
    / "scenarios"
    / "basic_room_001.json"
)

STATES_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "simulation_states"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "generated_events"
)

CONFIG_PATH = (
    BASE_DIR
    / "config"
    / "analyzer_thresholds.json"
)


def load_json(path: Path):
    with path.open(
        "r",
        encoding="utf-8"
    ) as f:
        return json.load(f)


def find_action_between(
    scenario,
    start_time,
    end_time
):
    actions = []

    for action in scenario.get(
        "actions",
        []
    ):
        if (
            start_time
            < action["time_s"]
            <= end_time
        ):
            actions.append(action)

    return actions


def get_compartment(
    state,
    compartment_id
):
    for compartment in state[
        "compartments"
    ]:
        if (
            compartment["id"]
            == compartment_id
        ):
            return compartment

    return None


def is_non_increasing(values):

    return all(
        current <= previous
        for previous, current
        in zip(
            values,
            values[1:]
        )
    )


def get_contiguous_history(
    states,
    end_index,
    count,
    max_gap_s
):

    start_index = (
        end_index
        - count
        + 1
    )

    if start_index < 0:
        return []

    history = states[
        start_index:
        end_index + 1
    ]

    for index in range(
        len(history) - 1
    ):
        before = history[index]
        after = history[index + 1]

        gap_s = (
            after["time_s"]
            - before["time_s"]
        )

        if gap_s <= 0:
            return []

        if gap_s > max_gap_s:
            return []

    return history


def analyze(
    before,
    after,
    scenario,
    thresholds=None
):

    if thresholds is None:
        thresholds = load_json(
            CONFIG_PATH
        )

    events = []

    start_time = before["time_s"]
    end_time = after["time_s"]

    actions = find_action_between(
        scenario,
        start_time,
        end_time
    )

    hrr_increase_ratio = (
        thresholds["hrr"][
            "increase_ratio"
        ]
    )

    temperature_increase_c = (
        thresholds["temperature"][
            "upper_layer_increase_c"
        ]
    )

    smoke_descent_m = (
        thresholds["smoke_layer"][
            "descent_m"
        ]
    )

    minimum_o2_increase = (
        thresholds["ventilation"][
            "minimum_o2_increase_percent"
        ]
    )

    for before_room in before[
        "compartments"
    ]:

        room_id = before_room["id"]

        after_room = get_compartment(
            after,
            room_id
        )

        if after_room is None:
            continue

        hrr_before = (
            before_room["hrr_kw"]
        )

        hrr_after = (
            after_room["hrr_kw"]
        )

        temp_before = (
            before_room[
                "upper_layer"
            ][
                "temperature_c"
            ]
        )

        temp_after = (
            after_room[
                "upper_layer"
            ][
                "temperature_c"
            ]
        )

        o2_before = (
            before_room[
                "upper_layer"
            ][
                "o2_percent"
            ]
        )

        o2_after = (
            after_room[
                "upper_layer"
            ][
                "o2_percent"
            ]
        )

        interface_before = (
            before_room[
                "interface_height_m"
            ]
        )

        interface_after = (
            after_room[
                "interface_height_m"
            ]
        )

        # ---------------------------------------------
        # 1. Aumento significativo de HRR
        # ---------------------------------------------

        if (
            hrr_after
            > hrr_before
            * hrr_increase_ratio
        ):

            events.append({
                "schema_version": "0.1",
                "scenario_id":
                    scenario[
                        "scenario_id"
                    ],
                "event_id": (
                    f"hrr_increase_"
                    f"{int(end_time)}_"
                    f"{room_id}"
                ),
                "time_s": end_time,
                "event_type":
                    "hrr_increase",
                "compartment_id":
                    room_id,
                "cause":
                    "detected_change",
                "confidence": 0.95,
                "evidence": [
                    {
                        "variable":
                            "hrr_kw",
                        "previous_value":
                            hrr_before,
                        "value":
                            hrr_after,
                        "unit":
                            "kW",
                        "description":
                            "Aumento significativo "
                            "del HRR"
                    }
                ]
            })

        # ---------------------------------------------
        # 2. Aumento significativo de temperatura
        # ---------------------------------------------

        if (
            temp_after
            - temp_before
            >= temperature_increase_c
        ):

            events.append({
                "schema_version": "0.1",
                "scenario_id":
                    scenario[
                        "scenario_id"
                    ],
                "event_id": (
                    "temperature_increase_"
                    f"{int(end_time)}_"
                    f"{room_id}"
                ),
                "time_s": end_time,
                "event_type":
                    "temperature_increase",
                "compartment_id":
                    room_id,
                "cause":
                    "detected_change",
                "confidence": 0.90,
                "evidence": [
                    {
                        "variable":
                            "upper_layer."
                            "temperature_c",
                        "previous_value":
                            temp_before,
                        "value":
                            temp_after,
                        "unit":
                            "C",
                        "description":
                            "Aumento de temperatura "
                            "de la capa superior"
                    }
                ]
            })

        # ---------------------------------------------
        # 3. Descenso de la interfaz de humo
        # ---------------------------------------------

        if (
            interface_before
            - interface_after
            >= smoke_descent_m
        ):

            events.append({
                "schema_version": "0.1",
                "scenario_id":
                    scenario[
                        "scenario_id"
                    ],
                "event_id": (
                    "smoke_layer_descent_"
                    f"{int(end_time)}_"
                    f"{room_id}"
                ),
                "time_s": end_time,
                "event_type":
                    "smoke_layer_descent",
                "compartment_id":
                    room_id,
                "cause":
                    "detected_change",
                "confidence": 0.95,
                "evidence": [
                    {
                        "variable":
                            "interface_height_m",
                        "previous_value":
                            interface_before,
                        "value":
                            interface_after,
                        "unit":
                            "m",
                        "description":
                            "Descenso de la "
                            "interfaz entre capas"
                    }
                ]
            })

        # ---------------------------------------------
        # 4. Aumento de ventilación tras una apertura
        # ---------------------------------------------

        for action in actions:

            if (
                action["type"]
                == "open"
                and (
                    o2_after
                    - o2_before
                    >= minimum_o2_increase
                )
            ):

                events.append({
                    "schema_version":
                        "0.1",
                    "scenario_id":
                        scenario[
                            "scenario_id"
                        ],
                    "event_id": (
                        "ventilation_increase_"
                        f"{int(action['time_s'])}_"
                        f"{room_id}"
                    ),
                    "time_s":
                        action[
                            "time_s"
                        ],
                    "event_type":
                        "ventilation_increase",
                    "compartment_id":
                        room_id,
                    "cause": (
                        f"{action['target']}"
                        "_opened"
                    ),
                    "confidence":
                        0.95,
                    "evidence": [
                        {
                            "variable":
                                "upper_layer."
                                "o2_percent",
                            "previous_value":
                                o2_before,
                            "value":
                                o2_after,
                            "unit":
                                "%",
                            "description":
                                "Aumento de oxígeno "
                                "tras la apertura"
                        },
                        {
                            "variable":
                                "hrr_kw",
                            "previous_value":
                                hrr_before,
                            "value":
                                hrr_after,
                            "unit":
                                "kW",
                            "description":
                                "Cambio del HRR "
                                "tras la apertura"
                        }
                    ]
                })

    return events


def detect_ventilation_limited_patterns(
    states,
    scenario,
    thresholds
):

    config = thresholds[
        "ventilation_limited"
    ]

    max_gap_s = (
        thresholds["timeline"][
            "max_gap_s"
        ]
    )

    minimum_pre_states = (
        config[
            "minimum_pre_states"
        ]
    )

    minimum_pre_o2_drop = (
        config[
            "minimum_pre_o2_drop_percent"
        ]
    )

    minimum_pre_hrr_drop_ratio = (
        config[
            "minimum_pre_hrr_drop_ratio"
        ]
    )

    minimum_post_o2_increase = (
        config[
            "minimum_post_o2_increase_percent"
        ]
    )

    minimum_post_hrr_ratio = (
        config[
            "minimum_post_hrr_increase_ratio"
        ]
    )

    events = []

    generated_ids = set()

    for action in scenario.get(
        "actions",
        []
    ):

        if action.get("type") != "open":
            continue

        action_time = action["time_s"]

        pre_index = None
        post_index = None

        # Último estado anterior a la apertura.
        for index, state in enumerate(
            states
        ):
            if (
                state["time_s"]
                < action_time
            ):
                pre_index = index
            else:
                break

        if pre_index is None:
            continue

        # Primer estado posterior a la apertura.
        for index in range(
            pre_index + 1,
            len(states)
        ):
            if (
                states[index]["time_s"]
                > action_time
            ):
                post_index = index
                break

        if post_index is None:
            continue

        pre_state = states[
            pre_index
        ]

        post_state = states[
            post_index
        ]

        # La comparación antes/después debe
        # seguir dentro de la ventana temporal
        # admitida por el analizador.
        if (
            post_state["time_s"]
            - pre_state["time_s"]
            > max_gap_s
        ):
            continue

        history = get_contiguous_history(
            states,
            pre_index,
            minimum_pre_states,
            max_gap_s
        )

        if not history:
            continue

        for pre_room in pre_state[
            "compartments"
        ]:

            room_id = pre_room["id"]

            post_room = get_compartment(
                post_state,
                room_id
            )

            if post_room is None:
                continue

            history_rooms = []

            valid_history = True

            for state in history:

                room = get_compartment(
                    state,
                    room_id
                )

                if room is None:
                    valid_history = False
                    break

                history_rooms.append(
                    room
                )

            if not valid_history:
                continue

            o2_values = [
                room[
                    "upper_layer"
                ][
                    "o2_percent"
                ]
                for room
                in history_rooms
            ]

            hrr_values = [
                room["hrr_kw"]
                for room
                in history_rooms
            ]

            temperature_values = [
                room[
                    "upper_layer"
                ][
                    "temperature_c"
                ]
                for room
                in history_rooms
            ]

            # -----------------------------------------
            # FASE PREVIA A LA APERTURA
            #
            # No se utiliza un valor absoluto de O2.
            # Se busca una tendencia temporal:
            #
            # O2 ↓
            # HRR ↓
            # temperatura ↓ o estable
            # -----------------------------------------

            if not is_non_increasing(
                o2_values
            ):
                continue

            if not is_non_increasing(
                hrr_values
            ):
                continue

            if not is_non_increasing(
                temperature_values
            ):
                continue

            pre_o2_drop = (
                o2_values[0]
                - o2_values[-1]
            )

            if (
                pre_o2_drop
                < minimum_pre_o2_drop
            ):
                continue

            first_hrr = hrr_values[0]

            if first_hrr <= 0:
                continue

            pre_hrr_drop_ratio = (
                first_hrr
                - hrr_values[-1]
            ) / first_hrr

            if (
                pre_hrr_drop_ratio
                < minimum_pre_hrr_drop_ratio
            ):
                continue

            # -----------------------------------------
            # FASE POSTERIOR A LA APERTURA
            #
            # Debe observarse:
            #
            # O2 ↑
            # HRR ↑
            # -----------------------------------------

            pre_o2 = o2_values[-1]

            post_o2 = (
                post_room[
                    "upper_layer"
                ][
                    "o2_percent"
                ]
            )

            pre_hrr = hrr_values[-1]

            post_hrr = (
                post_room["hrr_kw"]
            )

            if (
                post_o2
                - pre_o2
                < minimum_post_o2_increase
            ):
                continue

            if pre_hrr <= 0:
                continue

            if (
                post_hrr
                < pre_hrr
                * minimum_post_hrr_ratio
            ):
                continue

            event_id = (
                "ventilation_limited_"
                f"{int(pre_state['time_s'])}_"
                f"{room_id}"
            )

            if event_id in generated_ids:
                continue

            generated_ids.add(
                event_id
            )

            events.append({
                "schema_version":
                    "0.1",
                "scenario_id":
                    scenario[
                        "scenario_id"
                    ],
                "event_id":
                    event_id,
                "time_s":
                    pre_state[
                        "time_s"
                    ],
                "event_type":
                    "ventilation_limited",
                "compartment_id":
                    room_id,

                # Importante:
                # se identifica un patrón temporal,
                # no una causalidad demostrada.
                "cause":
                    "temporal_pattern",

                "confidence":
                    0.85,

                "evidence": [
                    {
                        "variable":
                            "pre_open."
                            "upper_layer."
                            "o2_percent",
                        "previous_value":
                            o2_values[0],
                        "value":
                            o2_values[-1],
                        "unit":
                            "%",
                        "description":
                            "Descenso de oxígeno "
                            "antes de la apertura"
                    },
                    {
                        "variable":
                            "pre_open."
                            "hrr_kw",
                        "previous_value":
                            hrr_values[0],
                        "value":
                            hrr_values[-1],
                        "unit":
                            "kW",
                        "description":
                            "Descenso del HRR "
                            "antes de la apertura"
                    },
                    {
                        "variable":
                            "pre_open."
                            "upper_layer."
                            "temperature_c",
                        "previous_value":
                            temperature_values[
                                0
                            ],
                        "value":
                            temperature_values[
                                -1
                            ],
                        "unit":
                            "C",
                        "description":
                            "Descenso o estabilidad "
                            "de temperatura antes "
                            "de la apertura"
                    },
                    {
                        "variable":
                            "post_open."
                            "upper_layer."
                            "o2_percent",
                        "previous_value":
                            pre_o2,
                        "value":
                            post_o2,
                        "unit":
                            "%",
                        "description":
                            "Aumento de oxígeno "
                            "tras la apertura"
                    },
                    {
                        "variable":
                            "post_open."
                            "hrr_kw",
                        "previous_value":
                            pre_hrr,
                        "value":
                            post_hrr,
                        "unit":
                            "kW",
                        "description":
                            "Aumento del HRR "
                            "tras la apertura"
                    }
                ]
            })

    return events


def analyze_timeline(
    states,
    scenario,
    thresholds=None
):

    if thresholds is None:
        thresholds = load_json(
            CONFIG_PATH
        )

    if len(states) < 2:
        return []

    states = sorted(
        states,
        key=lambda state:
            state["time_s"]
    )

    max_gap_s = (
        thresholds["timeline"][
            "max_gap_s"
        ]
    )

    all_events = []

    # ---------------------------------------------
    # Eventos entre estados consecutivos
    # ---------------------------------------------

    for index in range(
        len(states) - 1
    ):

        before = states[index]
        after = states[
            index + 1
        ]

        gap_s = (
            after["time_s"]
            - before["time_s"]
        )

        if gap_s <= 0:
            continue

        if gap_s > max_gap_s:
            continue

        events = analyze(
            before,
            after,
            scenario,
            thresholds
        )

        all_events.extend(
            events
        )

    # ---------------------------------------------
    # Patrones que necesitan varios estados
    # ---------------------------------------------

    pattern_events = (
        detect_ventilation_limited_patterns(
            states,
            scenario,
            thresholds
        )
    )

    all_events.extend(
        pattern_events
    )

    return all_events


def main():

    scenario = load_json(
        SCENARIO_PATH
    )

    before = load_json(
        STATES_DIR
        / "basic_room_001_t179.json"
    )

    after = load_json(
        STATES_DIR
        / "basic_room_001_t195.json"
    )

    thresholds = load_json(
        CONFIG_PATH
    )

    events = analyze(
        before,
        after,
        scenario,
        thresholds
    )

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    print(
        f"Eventos detectados: "
        f"{len(events)}"
    )

    for event in events:

        output_path = (
            OUTPUT_DIR
            / f"{event['event_id']}.json"
        )

        with output_path.open(
            "w",
            encoding="utf-8"
        ) as f:

            json.dump(
                event,
                f,
                indent=2,
                ensure_ascii=False
            )

        print(
            f"- {event['event_type']}"
            f" -> {output_path.name}"
        )


if __name__ == "__main__":
    main()