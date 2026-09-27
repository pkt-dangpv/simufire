import json
import re
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

ENTRIES_DIR = (
    BASE_DIR
    / "knowledge"
    / "entries"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def normalize(text: str) -> str:
    return text.lower().strip()


def tokenize(text: str) -> set[str]:
    return set(
        re.findall(
            r"[a-zA-Z0-9_áéíóúñü]+",
            normalize(text)
        )
    )


def load_entries():
    entries = []

    for path in sorted(ENTRIES_DIR.glob("*.json")):
        entries.append(
            load_json(path)
        )

    return entries


# -------------------------------------------------
# RECUPERACION POR TEXTO
# Se mantiene para preguntas futuras del usuario.
# -------------------------------------------------

def score_entry(query: str, entry: dict) -> int:

    query_tokens = tokenize(query)

    title_tokens = tokenize(
        entry.get("title", "")
    )

    content_tokens = tokenize(
        entry.get("content", "")
    )

    tag_tokens = set()

    for tag in entry.get("tags", []):
        tag_tokens.update(
            tokenize(tag)
        )

    topic_tokens = tokenize(
        entry.get("topic", "")
    )

    score = 0

    score += len(
        query_tokens & tag_tokens
    ) * 5

    score += len(
        query_tokens & topic_tokens
    ) * 5

    score += len(
        query_tokens & title_tokens
    ) * 3

    score += len(
        query_tokens & content_tokens
    )

    return score


def retrieve(
    query: str,
    limit: int = 5,
    minimum_score: int = 5
):

    entries = load_entries()

    results = []

    for entry in entries:

        score = score_entry(
            query,
            entry
        )

        if score >= minimum_score:

            results.append(
                {
                    "score": score,
                    "entry": entry
                }
            )

    results.sort(
        key=lambda item: item["score"],
        reverse=True
    )

    return results[:limit]


# -------------------------------------------------
# RECUPERACION ESTRUCTURADA POR TOPICS
# Esta se usara para analizar simulaciones.
# -------------------------------------------------

def retrieve_by_topics(
    topics,
    limit: int = 10
):

    if not topics:
        return []

    requested_topics = set(topics)

    entries = load_entries()

    results = []

    for entry in entries:

        entry_topic = entry.get("topic")

        if entry_topic in requested_topics:

            results.append(
                {
                    "score": 100,
                    "matched_topic": entry_topic,
                    "entry": entry
                }
            )

    results.sort(
        key=lambda item: (
            item["entry"]["knowledge_id"]
        )
    )

    return results[:limit]