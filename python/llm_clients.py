"""Provider clients for the naive-vs-grounded LLM datasheet-grounding eval.

Every provider is forced to answer via structured output/tool use rather
than free text, so scoring never depends on parsing prose -- see
grounding_experiment.response_schema() for the schema each call is forced
against. Plain `requests` calls against each provider's REST API (no
provider SDKs) to keep the dependency footprint the same as the rest of
this project's Python side.
"""

import os

import requests


class ProviderError(RuntimeError):
    """A provider returned an error response, or a response this client
    can't parse into the expected {question_id: {answer, confidence}} shape."""


def _api_error_body(resp: requests.Response) -> str:
    """Extract a provider's own error message from a failed response.

    Every provider returns a JSON error body on 4xx/5xx with more detail
    than a bare status code -- but the shape isn't uniform: at least one
    provider (xAI) returns `error` as a bare string rather than a nested
    `{message: ...}` object, so this checks for both before falling back to
    the raw response text.
    """
    try:
        info = resp.json()
    except ValueError:
        return resp.text
    if isinstance(info, dict):
        err = info.get("error")
        msg = err.get("message") if isinstance(err, dict) else err
        msg = msg or info.get("message")
        if msg:
            return str(msg)
    return resp.text


def _post(url, headers, json_body):
    resp = requests.post(url, headers=headers, json=json_body, timeout=120)
    if not resp.ok:
        raise ProviderError(f"{resp.status_code} {resp.reason}: {_api_error_body(resp)}")
    return resp.json()


def require_api_key(env_var: str) -> str:
    key = os.environ.get(env_var, "")
    if not key:
        raise ProviderError(
            f"{env_var} is not set. Add it to a repo-root .env file (see .env.example) "
            "before running the grounding experiment."
        )
    return key


def call_anthropic(system: str, user: str, schema: dict, model: str, api_key: str | None = None) -> dict:
    """Force a single tool call against `schema` via Anthropic's Messages API."""
    api_key = api_key or require_api_key("ANTHROPIC_API_KEY")
    body = _post(
        "https://api.anthropic.com/v1/messages",
        headers={"x-api-key": api_key, "anthropic-version": "2023-06-01"},
        json_body={
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": [{"role": "user", "content": user}],
            "tools": [
                {
                    "name": "submit_answers",
                    "description": "Submit your answers to the question battery.",
                    "input_schema": schema,
                }
            ],
            "tool_choice": {"type": "tool", "name": "submit_answers"},
        },
    )
    tool_use = [block for block in body.get("content", []) if block.get("type") == "tool_use"]
    if not tool_use:
        raise ProviderError("Anthropic response contained no tool_use block; expected a forced submit_answers call.")
    return tool_use[0]["input"]


def _call_openai_compatible(base_url: str, provider_name: str, system: str, user: str, schema: dict, model: str, api_key: str) -> dict:
    """Shared request path behind call_openai() and call_grok() -- xAI's Grok
    API is explicitly OpenAI-compatible (same /chat/completions shape, same
    Bearer auth, same tools/tool_choice contract)."""
    import json as _json

    body = _post(
        base_url,
        headers={"Authorization": f"Bearer {api_key}"},
        json_body={
            "model": model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "submit_answers",
                        "description": "Submit your answers to the question battery.",
                        "parameters": schema,
                    },
                }
            ],
            "tool_choice": {"type": "function", "function": {"name": "submit_answers"}},
        },
    )
    tool_calls = body["choices"][0]["message"].get("tool_calls") or []
    if not tool_calls:
        raise ProviderError(f"{provider_name} response contained no tool call; expected a forced submit_answers call.")
    return _json.loads(tool_calls[0]["function"]["arguments"])


def call_openai(system: str, user: str, schema: dict, model: str, api_key: str | None = None) -> dict:
    api_key = api_key or require_api_key("OPENAI_API_KEY")
    return _call_openai_compatible("https://api.openai.com/v1/chat/completions", "OpenAI", system, user, schema, model, api_key)


def call_grok(system: str, user: str, schema: dict, model: str, api_key: str | None = None) -> dict:
    api_key = api_key or require_api_key("XAI_API_KEY")
    return _call_openai_compatible("https://api.x.ai/v1/chat/completions", "Grok", system, user, schema, model, api_key)


def gemini_response_schema(schema: dict) -> dict:
    """Convert a response_schema() JSON Schema into Gemini's OpenAPI-subset
    shape: uppercase type names, no `additionalProperties`, and (per
    observed 400s on unsupported keywords) no minimum/maximum bounds -- the
    0-100 confidence range is enforced by prompt instructions instead."""
    properties = {}
    for qid, prop in schema["properties"].items():
        answer = prop["properties"]["answer"]
        answer_schema = {"type": answer["type"].upper()}
        if "enum" in answer:
            answer_schema["enum"] = answer["enum"]
        properties[qid] = {
            "type": "OBJECT",
            "properties": {"answer": answer_schema, "confidence": {"type": "INTEGER"}},
            "required": ["answer", "confidence"],
        }
    return {"type": "OBJECT", "properties": properties, "required": schema["required"]}


def call_gemini(system: str, user: str, schema: dict, model: str, api_key: str | None = None) -> dict:
    """Same forced-structured-output contract as the other clients, via
    Gemini's native JSON response mode rather than a tool/function call --
    Gemini returns the schema-conformant JSON directly as response text."""
    import json as _json

    api_key = api_key or require_api_key("GEMINI_API_KEY")
    body = _post(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}",
        headers={},
        json_body={
            "system_instruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": [{"text": user}]}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": gemini_response_schema(schema),
            },
        },
    )
    # A blocked/filtered prompt returns an empty `candidates` list rather
    # than a candidate with empty content.
    candidates = body.get("candidates") or []
    answer_text = candidates[0]["content"]["parts"][0]["text"] if candidates else None
    if not answer_text:
        raise ProviderError("Gemini response contained no candidate content; expected JSON text matching the schema.")
    return _json.loads(answer_text)
