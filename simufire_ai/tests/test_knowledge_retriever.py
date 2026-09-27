import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

sys.path.insert(
    0,
    str(BASE_DIR)
)

from knowledge.retriever import retrieve


def main():

    results = retrieve(
        "El HRR ha aumentado durante el incendio"
    )

    assert results, (
        "No se recuperó ninguna entrada."
    )

    first = results[0]["entry"]

    assert (
        first["knowledge_id"]
        == "HRR_001"
    ), (
        "Se esperaba HRR_001 y se obtuvo "
        f"{first['knowledge_id']}"
    )

    print(
        "OK: recuperación de conocimiento"
    )

    print(
        f"- {first['knowledge_id']}: "
        f"{first['title']}"
    )

    print(
        f"- score: {results[0]['score']}"
    )


if __name__ == "__main__":
    main()