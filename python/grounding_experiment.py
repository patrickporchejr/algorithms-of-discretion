"""Run and summarize the naive-vs-grounded LLM datasheet-grounding experiment.

For every requested provider, calls the same flagship model once "naive"
(a compact, pseudonymized description of the dataset only) and, when a
datasheet is supplied, again "grounded" (the identical description plus
the full datasheet.json content and an instruction to consult it first) --
over the fixed grounding_questions.QUESTIONS battery, scoring each answer
against that question's hand-authored expected_answer. Whether a datasheet
is supplied is what decides which conditions run: no datasheet means a
naive-only run, since "grounded" has nothing to ground against.
"""

import json
import os
import random
from datetime import date, datetime

import pandas as pd

import llm_clients
from datasheet import read_datasheet

CLIENTS = {
    "anthropic": llm_clients.call_anthropic,
    "openai": llm_clients.call_openai,
    "gemini": llm_clients.call_gemini,
    "grok": llm_clients.call_grok,
}


def _md_table(rows: list[dict]) -> str:
    """Render a list of same-keyed dicts as a Markdown pipe table."""
    if not rows:
        return "_(no rows)_"
    cols = list(rows[0].keys())

    def fmt(v):
        if v is None:
            return "NA"
        if isinstance(v, float):
            return f"{v:.3g}"
        return str(v)

    body = [[fmt(row.get(c)) for c in cols] for row in rows]
    widths = [max(len(c), *(len(r[i]) for r in body)) for i, c in enumerate(cols)]
    header = "| " + " | ".join(c.ljust(w) for c, w in zip(cols, widths)) + " |"
    sep = "|" + "|".join("-" * (w + 2) for w in widths) + "|"
    lines = ["| " + " | ".join(r[i].ljust(widths[i]) for i in range(len(cols))) + " |" for r in body]
    return "\n".join([header, sep, *lines])


def _pseudonymize_id_col(series: pd.Series) -> pd.Series:
    codes, _ = pd.factorize(series)
    return pd.Series([f"region_{c:02d}" for c in codes], index=series.index)


def _relativize_date_col(series: pd.Series) -> pd.Series:
    base = series.min()
    return series.apply(lambda d: f"day_{(d - base).days}")


def build_data_context(data: pd.DataFrame, n_sample: int = 20, seed: int = 20240101, id_cols: tuple = ()) -> str:
    """Describe a dataset compactly enough to hand to an LLM.

    Stands in for "the dataset" in the naive/grounded prompts. `id_cols`
    and any date-typed columns are pseudonymized/relativized in the sample
    before it's shown (e.g. a real county_fips like 48171 becomes
    "region_07"; a real date becomes "day_412", an offset from the data's
    own earliest date) -- without this, a raw sample of real-world
    identifiers hands the naive condition a shortcut that has nothing to do
    with the datasheet (every Texas FIPS code starts with "48", a real
    calendar date range reveals a year restriction directly). Column
    *types* are still reported honestly -- only the values are obscured.
    """
    schema_lines = [f"- {col} ({data[col].dtype})" for col in data.columns]

    is_date_col = {col: pd.api.types.is_datetime64_any_dtype(data[col]) for col in data.columns}
    redacted = data.copy()
    for col in id_cols:
        if col in redacted.columns:
            redacted[col] = _pseudonymize_id_col(redacted[col])
    for col, is_date in is_date_col.items():
        if is_date:
            redacted[col] = _relativize_date_col(pd.to_datetime(redacted[col]))

    rng = random.Random(seed)
    n = min(n_sample, len(redacted))
    idx = rng.sample(range(len(redacted)), n) if len(redacted) else []
    sample_rows = redacted.iloc[idx].to_dict(orient="records")

    parts = [
        f"Dataset: {len(data)} rows, {len(data.columns)} columns.",
        "",
        "Columns:",
        "\n".join(schema_lines),
    ]
    if id_cols or any(is_date_col.values()):
        parts += [
            "",
            "Note: identifier-like columns and calendar dates below have been "
            'pseudonymized/relativized (e.g. "region_03", "day_412") so this '
            "description doesn't incidentally reveal the dataset's real-world "
            "geographic or temporal provenance -- establishing that is exactly "
            "what a datasheet, not the raw data, is for.",
        ]
    parts += ["", f"Random sample of {n} rows:", _md_table(sample_rows)]
    return "\n".join(parts)


def response_schema(questions: dict) -> dict:
    """Build a JSON Schema describing a strict {answer, confidence} object
    per question. Boolean questions get a TRUE/FALSE string enum (not
    JSON Schema's native boolean type) and enum questions get a string enum
    of choice keys, so scoring can treat every non-numeric question as
    "does this string equal expected_answer" with no type-specific
    branching; numeric questions get a bare number, scored by tolerance
    band (see score_answer())."""
    properties = {}
    for qid, q in questions.items():
        if q["type"] == "boolean":
            answer_schema = {"type": "string", "enum": ["TRUE", "FALSE"]}
        elif q["type"] == "numeric":
            answer_schema = {"type": "number"}
        else:
            answer_schema = {"type": "string", "enum": list(q["choices"].keys())}
        properties[qid] = {
            "type": "object",
            "properties": {
                "answer": answer_schema,
                "confidence": {"type": "integer", "minimum": 0, "maximum": 100},
            },
            "required": ["answer", "confidence"],
            "additionalProperties": False,
        }
    return {
        "type": "object",
        "properties": properties,
        "required": list(questions.keys()),
        "additionalProperties": False,
    }


def build_grounding_prompt(condition: str, data_context: str, questions: dict, datasheet: dict | None = None) -> dict:
    """Build the system/user prompt for one naive-or-grounded LLM call."""
    if condition not in ("naive", "grounded"):
        raise ValueError(f'condition must be "naive" or "grounded", got {condition!r}')

    question_lines = []
    for qid, q in questions.items():
        if q["type"] == "boolean":
            question_lines.append(f'- [{qid}] (boolean -- answer exactly "TRUE" or "FALSE") {q["prompt"]}')
        elif q["type"] == "numeric":
            question_lines.append(f'- [{qid}] (numeric -- answer with a plain number, {q["unit"]}) {q["prompt"]}')
        else:
            choice_lines = "; ".join(f'"{k}": {v}' for k, v in q["choices"].items())
            question_lines.append(f'- [{qid}] (multiple choice -- answer with the choice key, not its text) {q["prompt"]} Choices: {choice_lines}')

    battery = (
        "Answer every question below about the dataset. For each question, also "
        "report your confidence in that specific answer as an integer from 0 "
        "(pure guess) to 100 (certain) -- confidence should reflect how sure you "
        "actually are, not a default value repeated across every question.\n\n"
        + "\n".join(question_lines)
    )

    if condition == "naive":
        system = (
            "You are a careful data analyst. Answer strictly from the dataset "
            "description provided below. Do not draw on outside knowledge of any "
            "specific real-world dataset, agency, or research project this data "
            "might resemble or that you might recognize it as -- reason only from "
            "what is explicitly shown below, plus ordinary statistical/domain "
            "judgment that isn't tied to identifying a specific real-world source. "
            "You must still answer every question, using your best judgment where "
            "the description doesn't say explicitly."
        )
        user = f"{data_context}\n\n{battery}"
    else:
        if datasheet is None:
            raise ValueError("`datasheet` is required when condition='grounded'.")
        system = (
            "You are a careful data analyst. Before answering, read the attached "
            "datasheet.json (a Datasheets-for-Datasets provenance document) in "
            "full and ground every answer in it -- it takes precedence over any "
            "assumption you would otherwise make from the raw data sample alone."
        )
        datasheet_json = json.dumps(datasheet, indent=2)
        user = f"{data_context}\n\ndatasheet.json:\n```json\n{datasheet_json}\n```\n\n{battery}"

    return {"system": system, "user": user}


def extract_answer_field(entry, field: str):
    """Safely pull one field out of one question's {answer, confidence}
    entry. "Forced" structured output isn't guaranteed: a provider can still
    return a bare scalar for one question instead of the nested object the
    schema asked for -- treated as a missing field (None), not a crash."""
    if not isinstance(entry, dict):
        return None
    return entry.get(field)


def score_answer(qtype: str, answer, expected, tolerance) -> bool:
    if qtype == "numeric":
        try:
            a, e = float(answer), float(expected)
        except (TypeError, ValueError):
            return False
        return abs(a - e) <= tolerance
    return answer == expected


def _load_checkpoint(path: str) -> list[dict] | None:
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path) as f:
            rows = json.load(f)
    except (ValueError, OSError):
        return None
    return rows if rows else None


def run_grounding_experiment(
    data_path: str,
    datasheet_path: str | None,
    providers: list[str],
    models: dict,
    questions: dict | None = None,
    id_cols: tuple = ("county_fips",),
    n_repeats: int = 1,
    checkpoint_path: str | None = None,
    restart: bool = False,
) -> dict:
    """Run the naive-vs-grounded LLM datasheet-grounding experiment.

    `datasheet_path=None` runs the naive condition only. Passing a path
    runs naive and grounded both, and requires a real, non-empty datasheet
    at that path (see datasheet.read_datasheet()) -- the grounded condition
    has nothing to ground against otherwise.

    Returns {"results": [row, ...]}, one row per (provider, condition,
    trial, question_id): provider, model, condition, trial, question_id,
    type, prompt, answer, confidence, expected_answer, correct, rationale.
    """
    from grounding_questions import QUESTIONS as _DEFAULT_QUESTIONS

    questions = questions if questions is not None else _DEFAULT_QUESTIONS

    missing_models = [p for p in providers if p not in models]
    if missing_models:
        raise ValueError(f"`models` is missing an entry for: {', '.join(missing_models)}.")

    conditions = ["naive"] if datasheet_path is None else ["naive", "grounded"]
    datasheet = read_datasheet(datasheet_path) if datasheet_path is not None else None

    completed = None if restart else _load_checkpoint(checkpoint_path)

    data = pd.read_csv(data_path)
    data_context = build_data_context(data, id_cols=id_cols)
    schema = response_schema(questions)

    runs: list[dict] = []
    for provider in providers:
        model = models[provider]
        call_fn = CLIENTS[provider]

        for condition in conditions:
            prompt = build_grounding_prompt(
                condition, data_context, questions,
                datasheet=datasheet if condition == "grounded" else None,
            )

            for trial in range(1, n_repeats + 1):
                existing = [
                    r for r in (completed or [])
                    if r["provider"] == provider and r["model"] == model
                    and r["condition"] == condition and r["trial"] == trial
                ]
                if existing:
                    runs.extend(existing)
                    continue

                answers = call_fn(prompt["system"], prompt["user"], schema, model)
                for qid, q in questions.items():
                    entry = answers.get(qid)
                    answer = extract_answer_field(entry, "answer")
                    confidence = extract_answer_field(entry, "confidence")
                    correct = (
                        score_answer(q["type"], answer, q["expected_answer"], q.get("tolerance"))
                        if answer is not None else False
                    )
                    runs.append({
                        "provider": provider, "model": model, "condition": condition, "trial": trial,
                        "question_id": qid, "type": q["type"], "prompt": q["prompt"],
                        "answer": None if answer is None else str(answer),
                        "confidence": None if confidence is None else float(confidence),
                        "expected_answer": q["expected_answer"], "correct": correct,
                        "rationale": q["rationale"],
                    })

                # Checkpoint after every real API call (not cache hits) so a
                # crash on trial N never loses the N-1 calls already billed.
                if checkpoint_path:
                    with open(checkpoint_path, "w") as f:
                        json.dump(runs, f)

    return {"results": runs}


def summarize_grounding_trials(results: list[dict]) -> list[dict]:
    """Collapse repeated-trial rows into one summary row per
    (provider, model, condition, question_id): the modal answer, accuracy,
    agreement (share of trials matching the modal answer -- a single-run
    "changed answer" could just be sampling noise), mean confidence."""
    keys = sorted({
        (r["provider"], r["model"], r["condition"], r["question_id"], r["type"], r["prompt"], r["expected_answer"], r["rationale"])
        for r in results
    }, key=lambda k: (k[0], k[2], k[3]))

    out = []
    for provider, model, condition, question_id, qtype, prompt, expected_answer, rationale in keys:
        rows = [
            r for r in results
            if r["provider"] == provider and r["condition"] == condition and r["question_id"] == question_id
        ]
        answers = [r["answer"] for r in rows if r["answer"] is not None]
        if answers:
            modal_answer = max(set(answers), key=answers.count)
            agreement = sum(1 for a in answers if a == modal_answer) / len(rows)
        else:
            modal_answer, agreement = None, None
        confidences = [r["confidence"] for r in rows if r["confidence"] is not None]
        out.append({
            "provider": provider, "model": model, "condition": condition, "question_id": question_id,
            "type": qtype, "prompt": prompt,
            "modal_answer": modal_answer,
            "accuracy": sum(1 for r in rows if r["correct"]) / len(rows),
            "agreement": agreement,
            "mean_confidence": (sum(confidences) / len(confidences)) if confidences else None,
            "n_trials": len(rows),
            "expected_answer": expected_answer, "rationale": rationale,
        })
    return out


def summarize_accuracy_table(summarized: list[dict]) -> list[dict]:
    """Mean accuracy/confidence per (provider, model, condition)."""
    keys = sorted({(r["provider"], r["model"], r["condition"]) for r in summarized})
    out = []
    for provider, model, condition in keys:
        rows = [r for r in summarized if (r["provider"], r["model"], r["condition"]) == (provider, model, condition)]
        confidences = [r["mean_confidence"] for r in rows if r["mean_confidence"] is not None]
        out.append({
            "provider": provider, "model": model, "condition": condition,
            "accuracy_pct": round(100 * sum(r["accuracy"] for r in rows) / len(rows), 1),
            "mean_confidence": round(sum(confidences) / len(confidences), 1) if confidences else None,
        })
    return out


def format_report(result: dict) -> str:
    """Render a console-printable report: accuracy by provider/condition,
    mean answer stability across trials, and how many question/provider
    pairs changed their majority-vote answer once grounded."""
    results = result["results"]
    if not results:
        return "(no results)"
    summarized = summarize_grounding_trials(results)
    n_trials = max((r["trial"] for r in results), default=0)
    by_condition = summarize_accuracy_table(summarized)

    agreements = [r["agreement"] for r in summarized if r["agreement"] is not None]
    mean_agreement_pct = round(100 * sum(agreements) / len(agreements), 1) if agreements else None

    naive = {(r["provider"], r["question_id"]): r["modal_answer"] for r in summarized if r["condition"] == "naive"}
    grounded = {(r["provider"], r["question_id"]): r["modal_answer"] for r in summarized if r["condition"] == "grounded"}
    comparable_keys = [k for k in naive if k in grounded and naive[k] is not None and grounded[k] is not None]
    n_unanswered = len(set(naive) & set(grounded)) - len(comparable_keys)
    n_changed = sum(1 for k in comparable_keys if naive[k] != grounded[k])

    lines = [
        f"Accuracy by provider/condition (majority vote across {n_trials} trial(s) per question)",
        "",
        _md_table(by_condition),
        "",
    ]
    if mean_agreement_pct is not None:
        lines += [f"Mean answer stability across trials: {mean_agreement_pct}% (share of trials matching the modal answer, per question).", ""]
    if grounded:
        lines.append(f"{n_changed} of {len(comparable_keys)} question/provider pairs changed their majority-vote answer when grounded in the datasheet.")
        if n_unanswered > 0:
            lines.append(f"{n_unanswered} question/provider pair(s) excluded from that comparison -- at least one condition never produced a valid answer in any trial.")
    else:
        lines.append("Naive-only run (no datasheet supplied) -- nothing to compare against a grounded condition.")
    return "\n".join(lines)
