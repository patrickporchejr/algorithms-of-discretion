#' Build a JSON Schema describing a strict answer-plus-confidence object
#'
#' Every LLM provider is forced to answer via structured output/tool use
#' rather than free text, so the naive-vs-grounded comparison never depends
#' on parsing prose. Boolean questions get a `"TRUE"`/`"FALSE"` string enum
#' (not JSON Schema's native `boolean` type) and enum questions get a
#' string enum of choice keys, so [run_grounding_experiment()]'s scoring can
#' treat every non-numeric question as "does this string equal
#' `expected_answer`" with no type-specific branching; `"numeric"`
#' questions get a bare `number` instead, scored by tolerance band (see
#' `score_answer()` in grounding_experiment.R). Each question's answer is
#' itself nested as `{answer, confidence}` (`confidence` a 0-100 integer),
#' not a bare scalar -- self-reported confidence is what lets the report
#' distinguish "grounding changed the answer" from "grounding changed how
#' sure the model was," which can differ even when the raw answer doesn't.
#'
#' @param questions A question list in the shape of [grounding_questions()].
#' @return A JSON-Schema-shaped R list, ready to pass as `schema` to
#'   [call_anthropic()] / [call_openai()] / [call_grok()] / [call_gemini()]
#'   (the latter via [gemini_response_schema()], since Gemini uses a
#'   different schema dialect).
#' @keywords internal
grounding_response_schema <- function(questions) {
  properties <- lapply(questions, function(q) {
    answer_schema <- if (identical(q$type, "boolean")) {
      list(type = "string", enum = list("TRUE", "FALSE"))
    } else if (identical(q$type, "numeric")) {
      list(type = "number")
    } else {
      list(type = "string", enum = as.list(names(q$choices)))
    }
    list(
      type = "object",
      properties = list(
        answer = answer_schema,
        confidence = list(type = "integer", minimum = 0, maximum = 100)
      ),
      required = list("answer", "confidence"),
      additionalProperties = FALSE
    )
  })
  list(
    type = "object",
    properties = stats::setNames(properties, names(questions)),
    required = as.list(names(questions)),
    additionalProperties = FALSE
  )
}

#' Convert a grounding_response_schema() into Gemini's OpenAPI-subset shape
#'
#' Gemini's `responseSchema` uses an OpenAPI-3.0 subset: uppercase type
#' names (`"OBJECT"`/`"STRING"`/`"NUMBER"`/`"INTEGER"`, not their lowercase
#' JSON-Schema equivalents), no `additionalProperties` keyword, and (per
#' observed 400s on unsupported keywords) no `minimum`/`maximum` bounds --
#' the 0-100 confidence range is enforced by prompt instructions instead.
#' [grounding_response_schema()]'s output is always exactly two levels
#' (an object of per-question `{answer, confidence}` objects), so this is a
#' direct, non-recursive translation rather than a general JSON-Schema
#' converter.
#'
#' @param schema A JSON-Schema list from [grounding_response_schema()].
#' @return A schema list shaped for Gemini's `generationConfig.responseSchema`.
#' @keywords internal
gemini_response_schema <- function(schema) {
  list(
    type = "OBJECT",
    properties = lapply(schema$properties, function(p) {
      answer_type <- toupper(p$properties$answer$type)
      answer_enum <- p$properties$answer$enum
      # jsonlite's NULL-serialization for a present-but-NULL list element is
      # not something to rely on -- omit the "enum" key outright for
      # numeric questions instead of passing enum = NULL through.
      answer_schema <- if (is.null(answer_enum)) list(type = answer_type) else list(type = answer_type, enum = answer_enum)
      list(
        type = "OBJECT",
        properties = list(answer = answer_schema, confidence = list(type = "INTEGER")),
        required = list("answer", "confidence")
      )
    }),
    required = schema$required
  )
}

#' Extract a provider's own error message from a failed response
#'
#' All three providers return a JSON error body on 4xx/5xx with more detail
#' than httr2's default "HTTP 400 Bad Request" -- wired into every client via
#' `httr2::req_error(body = ...)` to surface it. `is.list()` guards every
#' `$`/`[[` access below because at least one provider (xAI) returns `error`
#' as a bare string rather than a nested `{message: ...}` object, and `$` on
#' an atomic vector errors instead of returning NULL (see
#' `test-llm_clients.R`'s regression test for this shape).
#'
#' @param resp An httr2 response object.
#' @return A character vector to append to the error message.
#' @keywords internal
api_error_body <- function(resp) {
  info <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
  if (is.list(info)) {
    err <- info$error
    msg <- if (is.list(err)) err$message else err
    msg <- msg %||% info$message
    if (!is.null(msg) && length(msg) > 0) return(as.character(msg)[[1]])
  }
  tryCatch(httr2::resp_body_string(resp), error = function(e) NULL)
}

#' @keywords internal
require_api_key <- function(env_var) {
  key <- Sys.getenv(env_var)
  if (!nzchar(key)) {
    rlang::abort(sprintf(
      "%s is not set. Add it to a repo-root .env file (see README) before running the grounding experiment.",
      env_var
    ))
  }
  key
}

#' Call Anthropic's Messages API for a forced structured-output answer
#'
#' Forces a single tool call (`tool_choice`) against `schema` so the
#' response is always a strict, parseable answer object -- never free text
#' that would need prompt-specific parsing.
#'
#' @param system System prompt string.
#' @param user User prompt string (the data context, question battery, and
#'   -- for the "grounded" condition -- the datasheet content).
#' @param schema A JSON-Schema list from [grounding_response_schema()].
#' @param model Model name, e.g. `"claude-opus-5"`.
#' @param api_key API key. Default reads `ANTHROPIC_API_KEY` from the
#'   environment.
#' @return A named list of `question_id -> answer` matching `schema`.
#' @export
call_anthropic <- function(system, user, schema, model, api_key = require_api_key("ANTHROPIC_API_KEY")) {
  req <- httr2::request("https://api.anthropic.com/v1/messages") |>
    httr2::req_headers(
      "x-api-key" = api_key,
      "anthropic-version" = "2023-06-01"
    ) |>
    httr2::req_body_json(list(
      model = model,
      max_tokens = 1024,
      system = system,
      messages = list(list(role = "user", content = user)),
      tools = list(list(
        name = "submit_answers",
        description = "Submit your answers to the question battery.",
        input_schema = schema
      )),
      tool_choice = list(type = "tool", name = "submit_answers")
    )) |>
    httr2::req_error(body = api_error_body)

  resp <- httr2::req_perform(req) |> httr2::resp_body_json()

  tool_use <- Filter(function(block) identical(block$type, "tool_use"), resp$content)
  if (length(tool_use) == 0) {
    rlang::abort("Anthropic response contained no tool_use block; expected a forced submit_answers call.")
  }
  tool_use[[1]]$input
}

#' Call an OpenAI-compatible Chat Completions API for a forced-tool answer
#'
#' Shared implementation behind [call_openai()] and [call_grok()] -- xAI's
#' Grok API is explicitly OpenAI-compatible (same `/chat/completions` shape,
#' same Bearer auth, same `tools`/`tool_choice` contract), so this is one
#' request-building path parameterized by base URL and provider name (used
#' only for the error message) rather than two near-identical copies.
#'
#' @param base_url The provider's chat completions endpoint.
#' @param provider_name Used only in the "no tool call" error message.
#' @inheritParams call_anthropic
#' @keywords internal
call_openai_compatible <- function(base_url, provider_name, system, user, schema, model, api_key) {
  req <- httr2::request(base_url) |>
    httr2::req_auth_bearer_token(api_key) |>
    httr2::req_body_json(list(
      model = model,
      messages = list(
        list(role = "system", content = system),
        list(role = "user", content = user)
      ),
      tools = list(list(
        type = "function",
        "function" = list(
          name = "submit_answers",
          description = "Submit your answers to the question battery.",
          parameters = schema
        )
      )),
      tool_choice = list(type = "function", "function" = list(name = "submit_answers"))
    )) |>
    httr2::req_error(body = api_error_body)

  resp <- httr2::req_perform(req) |> httr2::resp_body_json()

  tool_calls <- resp$choices[[1]]$message$tool_calls
  if (length(tool_calls) == 0) {
    rlang::abort(sprintf("%s response contained no tool call; expected a forced submit_answers call.", provider_name))
  }
  jsonlite::fromJSON(tool_calls[[1]]$"function"$arguments, simplifyVector = FALSE)
}

#' Call OpenAI's Chat Completions API for a forced structured-output answer
#'
#' Same forced-structured-output contract as [call_anthropic()], via a
#' forced tool call instead of Anthropic's `tool_choice`.
#'
#' @inheritParams call_anthropic
#' @param api_key API key. Default reads `OPENAI_API_KEY` from the
#'   environment.
#' @return A named list of `question_id -> answer` matching `schema`.
#' @export
call_openai <- function(system, user, schema, model, api_key = require_api_key("OPENAI_API_KEY")) {
  call_openai_compatible("https://api.openai.com/v1/chat/completions", "OpenAI", system, user, schema, model, api_key)
}

#' Call xAI's Grok API for a forced structured-output answer
#'
#' Grok's API is explicitly OpenAI-compatible -- same `/chat/completions`
#' shape, same forced-tool-call contract -- so this is [call_openai()]'s
#' logic pointed at a different base URL and key, via [call_openai_compatible()].
#'
#' @inheritParams call_anthropic
#' @param api_key API key. Default reads `XAI_API_KEY` from the environment.
#' @return A named list of `question_id -> answer` matching `schema`.
#' @export
call_grok <- function(system, user, schema, model, api_key = require_api_key("XAI_API_KEY")) {
  call_openai_compatible("https://api.x.ai/v1/chat/completions", "Grok", system, user, schema, model, api_key)
}

#' Call Google's Gemini API for a forced structured-output answer
#'
#' Same forced-structured-output contract as [call_anthropic()]/
#' [call_openai()], via Gemini's native JSON response mode
#' (`responseMimeType = "application/json"` + `responseSchema`) rather than
#' a tool/function call -- Gemini returns the schema-conformant JSON
#' directly as the response text.
#'
#' @inheritParams call_anthropic
#' @param api_key API key. Default reads `GEMINI_API_KEY` from the
#'   environment.
#' @return A named list of `question_id -> answer` matching `schema`.
#' @export
call_gemini <- function(system, user, schema, model, api_key = require_api_key("GEMINI_API_KEY")) {
  req <- httr2::request("https://generativelanguage.googleapis.com") |>
    httr2::req_url_path_append("v1beta", "models", paste0(model, ":generateContent")) |>
    httr2::req_url_query(key = api_key) |>
    httr2::req_body_json(list(
      system_instruction = list(parts = list(list(text = system))),
      contents = list(list(role = "user", parts = list(list(text = user)))),
      generationConfig = list(
        responseMimeType = "application/json",
        responseSchema = gemini_response_schema(schema)
      )
    )) |>
    httr2::req_error(body = api_error_body)

  resp <- httr2::req_perform(req) |> httr2::resp_body_json()

  # A blocked/filtered prompt returns an empty `candidates` array rather
  # than a candidate with empty content, so length() must be checked before
  # any [[1]] indexing -- indexing an empty list errors, it doesn't
  # propagate a NULL the way a missing named element would.
  answer_text <- if (length(resp$candidates) > 0) resp$candidates[[1]]$content$parts[[1]]$text else NULL
  if (is.null(answer_text)) {
    rlang::abort("Gemini response contained no candidate content; expected JSON text matching the schema.")
  }
  jsonlite::fromJSON(answer_text, simplifyVector = FALSE)
}
