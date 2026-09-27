import json
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

EXPLANATION_PATH = (
    BASE_DIR
    / "tests"
    / "data"
    / "generated_explanations"
    / "basic_room_001_grounded_explanation.json"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main():

    explanation = load_json(EXPLANATION_PATH)

    text = (
        explanation["summary"]
        + " "
        + explanation["explanation"]
    ).lower()

    forbidden_phrases = [
        "debido a la disminución de la presión",
        "debido a la gravedad",
        "provocó el aumento del hrr",
        "provocó un aumento del hrr",
        "causó el aumento del hrr",
        "provocó el aumento de temperatura",
        "causó el aumento de temperatura",
        "permitió la entrada de aire fresco"
    ]

    found = []

    for phrase in forbidden_phrases:
        if phrase in text:
            found.append(phrase)

    assert not found, (
        "La explicación contiene afirmaciones físicas "
        f"no autorizadas: {found}"
    )

    allowed_event_ids = {
        "ventilation_increase_180_room_01",
        "hrr_increase_195_room_01",
        "temperature_increase_195_room_01",
        "smoke_layer_descent_195_room_01"
    }

    used_event_ids = set(
        explanation["event_ids"]
    )

    assert used_event_ids.issubset(
        allowed_event_ids
    ), (
        "La explicación referencia eventos inexistentes: "
        f"{used_event_ids - allowed_event_ids}"
    )

    print(
        "OK: la explicación grounded "
        "no introduce causalidad no autorizada"
    )


if __name__ == "__main__":
    main()