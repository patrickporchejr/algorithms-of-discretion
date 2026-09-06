from unittest.mock import Mock, patch

import pytest

from _helpers import import_script  # noqa: F401 -- adds python/ to sys.path

import llm_clients


def _mock_post(json_body, ok=True, status_code=200):
    resp = Mock()
    resp.ok = ok
    resp.status_code = status_code
    resp.reason = "error"
    resp.json.return_value = json_body
    return resp


def test_require_api_key_raises_a_clear_message_when_unset(monkeypatch):
    monkeypatch.delenv("TESTKEY_NOT_SET", raising=False)
    with pytest.raises(llm_clients.ProviderError, match="TESTKEY_NOT_SET is not set"):
        llm_clients.require_api_key("TESTKEY_NOT_SET")


def test_require_api_key_returns_the_key_when_set(monkeypatch):
    monkeypatch.setenv("TESTKEY_SET", "abc123")
    assert llm_clients.require_api_key("TESTKEY_SET") == "abc123"


@patch("requests.post")
def test_api_error_body_extracts_a_nested_error_message_shape(mock_post):
    mock_post.return_value = _mock_post({"error": {"message": "bad request: missing field"}}, ok=False, status_code=400)
    with pytest.raises(llm_clients.ProviderError, match="bad request: missing field"):
        llm_clients.call_anthropic("sys", "user", schema={}, model="claude-opus-5", api_key="fake-key")


@patch("requests.post")
def test_api_error_body_extracts_a_bare_string_error_shape_without_crashing(mock_post):
    # Regression test: some providers (observed from xAI/Grok) return `error`
    # as a plain string rather than a nested object.
    mock_post.return_value = _mock_post({"error": "rate limit exceeded"}, ok=False, status_code=429)
    with pytest.raises(llm_clients.ProviderError, match="rate limit exceeded"):
        llm_clients.call_anthropic("sys", "user", schema={}, model="claude-opus-5", api_key="fake-key")


@patch("requests.post")
def test_call_anthropic_parses_a_forced_tool_use_response_ignoring_other_blocks(mock_post):
    mock_post.return_value = _mock_post({"content": [
        {"type": "text", "text": "ignored"},
        {"type": "tool_use", "input": {"q1": "TRUE"}},
    ]})
    result = llm_clients.call_anthropic("sys", "user", schema={}, model="claude-opus-5", api_key="fake-key")
    assert result == {"q1": "TRUE"}


@patch("requests.post")
def test_call_anthropic_raises_when_no_tool_use_block_present(mock_post):
    mock_post.return_value = _mock_post({"content": [{"type": "text", "text": "no tool call"}]})
    with pytest.raises(llm_clients.ProviderError, match="no tool_use block"):
        llm_clients.call_anthropic("sys", "user", schema={}, model="claude-opus-5", api_key="fake-key")


@patch("requests.post")
def test_call_openai_parses_a_forced_tool_call_response(mock_post):
    mock_post.return_value = _mock_post({"choices": [
        {"message": {"tool_calls": [{"function": {"arguments": '{"q1":"a"}'}}]}}
    ]})
    result = llm_clients.call_openai("sys", "user", schema={}, model="gpt-5.1", api_key="fake-key")
    assert result == {"q1": "a"}


@patch("requests.post")
def test_call_openai_raises_when_no_tool_call_present(mock_post):
    mock_post.return_value = _mock_post({"choices": [{"message": {"tool_calls": []}}]})
    with pytest.raises(llm_clients.ProviderError, match="no tool call"):
        llm_clients.call_openai("sys", "user", schema={}, model="gpt-5.1", api_key="fake-key")


@patch("requests.post")
def test_call_grok_parses_a_forced_tool_call_response_via_its_own_path(mock_post):
    mock_post.return_value = _mock_post({"choices": [
        {"message": {"tool_calls": [{"function": {"arguments": '{"q1":"a"}'}}]}}
    ]})
    result = llm_clients.call_grok("sys", "user", schema={}, model="grok-4.6", api_key="fake-key")
    assert result == {"q1": "a"}


@patch("requests.post")
def test_call_grok_raises_with_a_grok_specific_message_when_no_tool_call_present(mock_post):
    mock_post.return_value = _mock_post({"choices": [{"message": {"tool_calls": []}}]})
    with pytest.raises(llm_clients.ProviderError, match="Grok response contained no tool call"):
        llm_clients.call_grok("sys", "user", schema={}, model="grok-4.6", api_key="fake-key")


@patch("requests.post")
def test_call_gemini_parses_the_json_mode_response_text(mock_post):
    mock_post.return_value = _mock_post({"candidates": [
        {"content": {"parts": [{"text": '{"q1":"TRUE"}'}]}}
    ]})
    result = llm_clients.call_gemini("sys", "user", schema={"properties": {}, "required": []}, model="gemini-3.1-pro-preview", api_key="fake-key")
    assert result == {"q1": "TRUE"}


@patch("requests.post")
def test_call_gemini_raises_when_no_candidate_content_present(mock_post):
    mock_post.return_value = _mock_post({"candidates": []})
    with pytest.raises(llm_clients.ProviderError, match="no candidate content"):
        llm_clients.call_gemini("sys", "user", schema={"properties": {}, "required": []}, model="gemini-3.1-pro-preview", api_key="fake-key")


def test_gemini_response_schema_uppercases_types_and_drops_enum_for_numeric():
    schema = {
        "properties": {
            "q1": {"properties": {"answer": {"type": "string", "enum": ["TRUE", "FALSE"]}}},
            "q3": {"properties": {"answer": {"type": "number"}}},
        },
        "required": ["q1", "q3"],
    }
    gschema = llm_clients.gemini_response_schema(schema)
    assert gschema["type"] == "OBJECT"
    assert gschema["properties"]["q1"]["properties"]["answer"] == {"type": "STRING", "enum": ["TRUE", "FALSE"]}
    assert gschema["properties"]["q3"]["properties"]["answer"] == {"type": "NUMBER"}
    assert gschema["required"] == ["q1", "q3"]
