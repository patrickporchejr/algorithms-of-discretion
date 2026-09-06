from unittest.mock import patch

import pandas as pd
import pytest

from _helpers import import_script  # noqa: F401 -- adds python/ to sys.path

import grounding_experiment as ge
import grounding_questions

TEST_QUESTIONS = {
    "q_bool": {"type": "boolean", "prompt": "Is X true?", "expected_answer": "TRUE", "rationale": "because X"},
    "q_enum": {
        "type": "enum", "prompt": "Pick one.",
        "choices": {"a": "Option A", "b": "Option B"},
        "expected_answer": "a", "rationale": "because A",
    },
    "q_numeric": {
        "type": "numeric", "prompt": "How many?", "unit": "as a plain number",
        "expected_answer": "10", "tolerance": 2, "rationale": "because 10",
    },
}

DATASHEET = {"motivation": {"purpose": "Audit racial disparities in Texas traffic stops."}}


def _stops_df(n=5):
    return pd.DataFrame({
        "subject_race": ["white", "black", "hispanic", "white", "black"][:n],
        "county_fips": ["48201", "48113", "48453", "48201", "48113"][:n],
        "date": pd.to_datetime(["2016-01-01", "2016-01-05", "2016-02-01", "2016-03-01", "2016-04-01"][:n]),
    })


def test_grounding_questions_battery_is_well_formed():
    for q in grounding_questions.QUESTIONS.values():
        assert q["type"] in ("boolean", "enum", "numeric")
        assert isinstance(q["prompt"], str)
        assert isinstance(q["rationale"], str)
        if q["type"] == "enum":
            assert q["expected_answer"] in q["choices"]
        elif q["type"] == "numeric":
            float(q["expected_answer"])
            assert q["tolerance"] >= 0
        else:
            assert q["expected_answer"] in ("TRUE", "FALSE")


def test_build_data_context_reports_row_and_column_counts_and_sample_size():
    df = _stops_df(n=5)
    ctx = ge.build_data_context(df, n_sample=3, seed=1)
    assert "5 rows" in ctx
    assert f"{len(df.columns)} columns" in ctx
    assert "Random sample of 3 rows" in ctx


def test_build_data_context_caps_the_sample_at_len_data():
    df = _stops_df(n=3)
    ctx = ge.build_data_context(df, n_sample=20, seed=1)
    assert "Random sample of 3 rows" in ctx


def test_build_data_context_pseudonymizes_id_cols_and_relativizes_dates():
    df = _stops_df(n=5)
    ctx = ge.build_data_context(df, n_sample=5, seed=1, id_cols=("county_fips",))
    assert "48201" not in ctx
    assert "region_" in ctx
    assert "day_" in ctx


def test_build_grounding_prompt_naive_excludes_the_datasheet():
    prompt = ge.build_grounding_prompt("naive", "Dataset: 10 rows, 2 columns.", TEST_QUESTIONS)
    assert "datasheet.json" not in prompt["user"]
    assert "Is X true?" in prompt["user"]


def test_build_grounding_prompt_grounded_requires_and_embeds_the_datasheet():
    with pytest.raises(ValueError, match="datasheet.*required"):
        ge.build_grounding_prompt("grounded", "ctx", TEST_QUESTIONS)

    prompt = ge.build_grounding_prompt("grounded", "ctx", TEST_QUESTIONS, datasheet=DATASHEET)
    assert "datasheet.json" in prompt["user"]
    assert DATASHEET["motivation"]["purpose"] in prompt["user"]


def test_build_grounding_prompt_formats_question_types_distinctly():
    prompt = ge.build_grounding_prompt("naive", "ctx", TEST_QUESTIONS)
    assert 'answer exactly "TRUE" or "FALSE"' in prompt["user"]
    assert "multiple choice" in prompt["user"]
    assert '"a": Option A' in prompt["user"]
    assert "numeric -- answer with a plain number, as a plain number" in prompt["user"]


def test_score_answer_exact_match_boolean_enum_tolerance_band_numeric():
    assert ge.score_answer("boolean", "TRUE", "TRUE", None) is True
    assert ge.score_answer("boolean", "FALSE", "TRUE", None) is False
    assert ge.score_answer("enum", "a", "a", None) is True
    assert ge.score_answer("enum", "b", "a", None) is False
    assert ge.score_answer("numeric", "10", "10", 2) is True
    assert ge.score_answer("numeric", "12", "10", 2) is True  # exactly at the tolerance boundary
    assert ge.score_answer("numeric", "13", "10", 2) is False
    assert ge.score_answer("numeric", "not a number", "10", 2) is False


def test_extract_answer_field_returns_the_named_field_from_a_well_formed_entry():
    assert ge.extract_answer_field({"answer": "TRUE", "confidence": 90}, "answer") == "TRUE"
    assert ge.extract_answer_field({"answer": "TRUE", "confidence": 90}, "confidence") == 90


def test_extract_answer_field_returns_none_not_an_error_for_a_missing_field_or_non_dict():
    assert ge.extract_answer_field({"answer": "TRUE"}, "confidence") is None
    assert ge.extract_answer_field(None, "answer") is None
    # Regression: a provider that doesn't honor the forced {answer,
    # confidence} object schema and returns a bare scalar instead.
    assert ge.extract_answer_field("TRUE", "answer") is None
    assert ge.extract_answer_field(42, "answer") is None


def test_response_schema_nests_boolean_answers_with_true_false_string_enum():
    schema = ge.response_schema({"q1": {"type": "boolean"}})
    assert schema["properties"]["q1"]["type"] == "object"
    assert schema["properties"]["q1"]["properties"]["answer"] == {"type": "string", "enum": ["TRUE", "FALSE"]}
    assert schema["properties"]["q1"]["required"] == ["answer", "confidence"]
    assert schema["required"] == ["q1"]
    assert schema["additionalProperties"] is False


def test_response_schema_encodes_enum_answers_using_choice_keys_not_text():
    schema = ge.response_schema({"q2": {"type": "enum", "choices": {"a": "Option A", "b": "Option B"}}})
    assert schema["properties"]["q2"]["properties"]["answer"] == {"type": "string", "enum": ["a", "b"]}


def test_response_schema_encodes_numeric_answers_as_a_bare_number():
    schema = ge.response_schema({"q3": {"type": "numeric"}})
    assert schema["properties"]["q3"]["properties"]["answer"] == {"type": "number"}


def test_run_grounding_experiment_naive_only_when_no_datasheet_path(tmp_path):
    csv_path = tmp_path / "stops.csv"
    _stops_df(5).to_csv(csv_path, index=False)

    def mock_call(system, user, schema, model):
        return {qid: {"answer": q["expected_answer"], "confidence": 90} for qid, q in TEST_QUESTIONS.items()}

    with patch.object(ge, "CLIENTS", {"anthropic": mock_call}):
        result = ge.run_grounding_experiment(
            str(csv_path), None, providers=["anthropic"], models={"anthropic": "test-model"},
            questions=TEST_QUESTIONS,
        )

    conditions = {r["condition"] for r in result["results"]}
    assert conditions == {"naive"}
    assert all(r["correct"] for r in result["results"])


def test_run_grounding_experiment_runs_both_conditions_when_datasheet_given(tmp_path):
    csv_path = tmp_path / "stops.csv"
    _stops_df(5).to_csv(csv_path, index=False)
    datasheet_path = tmp_path / "datasheet.json"
    import json
    datasheet_path.write_text(json.dumps(DATASHEET))

    def mock_call(system, user, schema, model):
        return {qid: {"answer": q["expected_answer"], "confidence": 90} for qid, q in TEST_QUESTIONS.items()}

    with patch.object(ge, "CLIENTS", {"anthropic": mock_call}):
        result = ge.run_grounding_experiment(
            str(csv_path), str(datasheet_path), providers=["anthropic"], models={"anthropic": "test-model"},
            questions=TEST_QUESTIONS,
        )

    conditions = {r["condition"] for r in result["results"]}
    assert conditions == {"naive", "grounded"}


def test_run_grounding_experiment_tolerates_a_bare_scalar_from_one_question(tmp_path):
    csv_path = tmp_path / "stops.csv"
    _stops_df(5).to_csv(csv_path, index=False)

    def mock_call(system, user, schema, model):
        return {
            "q_bool": {"answer": "TRUE", "confidence": 90},
            "q_enum": "a",  # not nested under answer/confidence
            "q_numeric": {"answer": 10, "confidence": 80},
        }

    with patch.object(ge, "CLIENTS", {"anthropic": mock_call}):
        result = ge.run_grounding_experiment(
            str(csv_path), None, providers=["anthropic"], models={"anthropic": "test-model"},
            questions=TEST_QUESTIONS,
        )

    rows = result["results"]
    enum_rows = [r for r in rows if r["question_id"] == "q_enum"]
    assert all(r["answer"] is None for r in enum_rows)
    assert all(not r["correct"] for r in enum_rows)
    bool_rows = [r for r in rows if r["question_id"] == "q_bool"]
    assert all(r["answer"] == "TRUE" for r in bool_rows)


def test_run_grounding_experiment_raises_when_models_missing_a_requested_provider(tmp_path):
    csv_path = tmp_path / "stops.csv"
    _stops_df(5).to_csv(csv_path, index=False)
    with pytest.raises(ValueError, match="missing an entry"):
        ge.run_grounding_experiment(str(csv_path), None, providers=["anthropic"], models={}, questions=TEST_QUESTIONS)


def test_run_grounding_experiment_raises_when_datasheet_path_does_not_exist(tmp_path):
    csv_path = tmp_path / "stops.csv"
    _stops_df(5).to_csv(csv_path, index=False)
    with pytest.raises(FileNotFoundError):
        ge.run_grounding_experiment(
            str(csv_path), str(tmp_path / "missing.json"),
            providers=["anthropic"], models={"anthropic": "test-model"}, questions=TEST_QUESTIONS,
        )


def test_summarize_grounding_trials_collapses_repeats_into_modal_answer_and_agreement():
    results = [
        {"provider": "anthropic", "model": "m", "condition": "naive", "trial": 1, "question_id": "q1",
         "type": "boolean", "prompt": "p", "answer": "TRUE", "confidence": 90.0,
         "expected_answer": "TRUE", "correct": True, "rationale": "r"},
        {"provider": "anthropic", "model": "m", "condition": "naive", "trial": 2, "question_id": "q1",
         "type": "boolean", "prompt": "p", "answer": "FALSE", "confidence": 60.0,
         "expected_answer": "TRUE", "correct": False, "rationale": "r"},
    ]
    summarized = ge.summarize_grounding_trials(results)
    assert len(summarized) == 1
    row = summarized[0]
    assert row["modal_answer"] in ("TRUE", "FALSE")  # tie-break is set-order dependent, just must be one of the two
    assert row["n_trials"] == 2
    assert row["accuracy"] == 0.5
