"""Scores Presidio on SOTAB columns, in the configurations a user would choose.

    uv run --no-project --python 3.12 --with presidio-analyzer --with "presidio-analyzer[gliner]" \\
        --with "en_core_web_lg @ https://github.com/explosion/spacy-models/releases/download/en_core_web_lg-3.8.0/en_core_web_lg-3.8.0-py3-none-any.whl" \\
        python score_presidio_sotab.py <columns.jsonl> <out.csv> {spacy,gliner}

Each column's distinct values, up to 50 evenly spaced and weighted by rows,
are analyzed one at a time, as presidio-structured analyzes cells. A column is
flagged "strong" when at least half its rows hold a personal entity scoring
0.5 or more, and "any" when one does. Dates, URLs and NRP do not count. The
share of rows holding each entity is kept, so summarize.py can leave out
others, such as LOCATION, without a new run.
"""
import csv
import json
import sys
from collections import Counter

from presidio_analyzer import AnalyzerEngine, RecognizerRegistry
from presidio_analyzer.nlp_engine import NlpEngineProvider

NOT_PERSONAL = {"DATE_TIME", "NRP", "URL"}
source, out, mode = sys.argv[1], sys.argv[2], sys.argv[3]


def engine(mode):
    if mode == "spacy":
        return AnalyzerEngine()
    # Presidio's documented GLiNER set-up: a small spaCy model for tokens,
    # GLiNER in place of spaCy's named-entity recognizer.
    from presidio_analyzer.predefined_recognizers import GLiNERRecognizer
    provider = NlpEngineProvider(nlp_configuration={
        "nlp_engine_name": "spacy", "models": [{"lang_code": "en", "model_name": "en_core_web_sm"}],
    })
    registry = RecognizerRegistry()
    registry.load_predefined_recognizers()
    registry.remove_recognizer("SpacyRecognizer")
    registry.add_recognizer(GLiNERRecognizer(
        model_name="urchade/gliner_multi_pii-v1",
        entity_mapping={"person": "PERSON", "location": "LOCATION", "organization": "ORGANIZATION",
                        "phone number": "PHONE_NUMBER", "email": "EMAIL_ADDRESS", "address": "LOCATION"},
    ))
    return AnalyzerEngine(nlp_engine=provider.create_engine(), registry=registry)


analyzer = engine(mode)
with open(out, "w", newline="") as handle:
    writer = csv.writer(handle)
    writer.writerow(["table", "column", "label", "personal", "strong", "any", "types", "shares"])
    for line in open(source):
        column = json.loads(line)
        counts = Counter(column["values"])
        distinct = list(counts)
        step = max(1, len(distinct) // 50)
        sample = distinct[::step][:50]
        total = sum(counts[v] for v in sample)
        hit, types, rows = 0, Counter(), Counter()
        for value in sample:
            found = {
                r.entity_type for r in analyzer.analyze(text=value[:1000], language="en")
                if r.score >= 0.5 and r.entity_type not in NOT_PERSONAL
            }
            if found:
                hit += counts[value]
                types.update(found)
                for entity in found:
                    rows[entity] += counts[value]
        strong = total > 0 and hit / total >= 0.5
        writer.writerow([
            column["table"], column["column"], column["label"], column["personal"],
            strong, hit > 0, " ".join(t for t, _ in types.most_common()),
            json.dumps({e: round(n / total, 3) for e, n in rows.items()}) if total else "{}",
        ])
