test_that("grounding_response_schema nests boolean answers as {answer, confidence}, answer a TRUE/FALSE string enum", {
  qs <- list(q1 = list(type = "boolean"))
  schema <- grounding_response_schema(qs)
  expect_equal(schema$properties$q1$type, "object")
  expect_equal(schema$properties$q1$properties$answer$type, "string")
  expect_equal(unlist(schema$properties$q1$properties$answer$enum), c("TRUE", "FALSE"))
  expect_equal(schema$properties$q1$properties$confidence$type, "integer")
  expect_equal(unlist(schema$properties$q1$required), c("answer", "confidence"))
  expect_equal(unlist(schema$required), "q1")
  expect_false(schema$additionalProperties)
})

test_that("grounding_response_schema encodes enum answers using their choice keys, not choice text", {
  qs <- list(q2 = list(type = "enum", choices = c(a = "Option A", b = "Option B")))
  schema <- grounding_response_schema(qs)
  expect_equal(schema$properties$q2$properties$answer$type, "string")
  expect_equal(unlist(schema$properties$q2$properties$answer$enum), c("a", "b"))
})

test_that("grounding_response_schema encodes numeric answers as a bare number, no enum", {
  qs <- list(q3 = list(type = "numeric"))
  schema <- grounding_response_schema(qs)
  expect_equal(schema$properties$q3$properties$answer$type, "number")
  expect_null(schema$properties$q3$properties$answer$enum)
})

test_that("gemini_response_schema uppercases nested types and drops additionalProperties/enum for numeric", {
  schema <- grounding_response_schema(list(
    q1 = list(type = "boolean"),
    q2 = list(type = "enum", choices = c(a = "Option A", b = "Option B")),
    q3 = list(type = "numeric")
  ))
  gschema <- gemini_response_schema(schema)
  expect_equal(gschema$type, "OBJECT")

  expect_equal(gschema$properties$q1$type, "OBJECT")
  expect_equal(gschema$properties$q1$properties$answer$type, "STRING")
  expect_equal(unlist(gschema$properties$q1$properties$answer$enum), c("TRUE", "FALSE"))
  expect_equal(gschema$properties$q1$properties$confidence$type, "INTEGER")
  expect_equal(unlist(gschema$properties$q1$required), c("answer", "confidence"))

  expect_equal(gschema$properties$q2$properties$answer$type, "STRING")
  expect_equal(unlist(gschema$properties$q2$properties$answer$enum), c("a", "b"))

  expect_equal(gschema$properties$q3$properties$answer$type, "NUMBER")
  expect_null(gschema$properties$q3$properties$answer$enum)

  expect_null(gschema$additionalProperties)
  expect_equal(unlist(gschema$required), c("q1", "q2", "q3"))
})

test_that("require_api_key aborts with a clear message when the env var is unset", {
  withr::local_envvar(c(TESTKEY_NOT_SET = ""))
  expect_error(require_api_key("TESTKEY_NOT_SET"), "TESTKEY_NOT_SET is not set")
})

test_that("require_api_key returns the key when the env var is set", {
  withr::local_envvar(c(TESTKEY_SET = "abc123"))
  expect_equal(require_api_key("TESTKEY_SET"), "abc123")
})

test_that("call_anthropic parses a forced tool_use response, ignoring other content blocks", {
  fake_resp <- list(content = list(
    list(type = "text", text = "ignored"),
    list(type = "tool_use", input = list(q1 = "TRUE"))
  ))
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) structure(list(), class = "httr2_response"),
    resp_body_json = function(resp, ...) fake_resp,
    .package = "httr2"
  )
  result <- call_anthropic("sys", "user", schema = list(), model = "claude-opus-5", api_key = "fake-key")
  expect_equal(result, list(q1 = "TRUE"))
})

test_that("call_anthropic aborts when no tool_use block is present", {
  fake_resp <- list(content = list(list(type = "text", text = "no tool call")))
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) structure(list(), class = "httr2_response"),
    resp_body_json = function(resp, ...) fake_resp,
    .package = "httr2"
  )
  expect_error(
    call_anthropic("sys", "user", schema = list(), model = "claude-opus-5", api_key = "fake-key"),
    "no tool_use block"
  )
})

test_that("call_openai parses a forced tool-call response", {
  fake_resp <- list(choices = list(list(message = list(tool_calls = list(
    list("function" = list(arguments = '{"q1":"a"}'))
  )))))
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) structure(list(), class = "httr2_response"),
    resp_body_json = function(resp, ...) fake_resp,
    .package = "httr2"
  )
  result <- call_openai("sys", "user", schema = list(), model = "gpt-5.1", api_key = "fake-key")
  expect_equal(result, list(q1 = "a"))
})

test_that("call_openai aborts when no tool call is present", {
  fake_resp <- list(choices = list(list(message = list(tool_calls = list()))))
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) structure(list(), class = "httr2_response"),
    resp_body_json = function(resp, ...) fake_resp,
    .package = "httr2"
  )
  expect_error(
    call_openai("sys", "user", schema = list(), model = "gpt-5.1", api_key = "fake-key"),
    "no tool call"
  )
})

test_that("call_grok parses a forced tool-call response, using its own OpenAI-compatible path", {
  fake_resp <- list(choices = list(list(message = list(tool_calls = list(
    list("function" = list(arguments = '{"q1":"a"}'))
  )))))
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) structure(list(), class = "httr2_response"),
    resp_body_json = function(resp, ...) fake_resp,
    .package = "httr2"
  )
  result <- call_grok("sys", "user", schema = list(), model = "grok-4.6", api_key = "fake-key")
  expect_equal(result, list(q1 = "a"))
})

test_that("call_grok aborts with a Grok-specific message when no tool call is present", {
  fake_resp <- list(choices = list(list(message = list(tool_calls = list()))))
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) structure(list(), class = "httr2_response"),
    resp_body_json = function(resp, ...) fake_resp,
    .package = "httr2"
  )
  expect_error(
    call_grok("sys", "user", schema = list(), model = "grok-4.6", api_key = "fake-key"),
    "Grok response contained no tool call"
  )
})

test_that("call_gemini parses the JSON-mode response text", {
  fake_resp <- list(candidates = list(list(content = list(parts = list(
    list(text = '{"q1":"TRUE"}')
  )))))
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) structure(list(), class = "httr2_response"),
    resp_body_json = function(resp, ...) fake_resp,
    .package = "httr2"
  )
  result <- call_gemini("sys", "user", schema = list(), model = "gemini-3.1-pro-preview", api_key = "fake-key")
  expect_equal(result, list(q1 = "TRUE"))
})

test_that("call_gemini aborts when no candidate content is present", {
  fake_resp <- list(candidates = list())
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) structure(list(), class = "httr2_response"),
    resp_body_json = function(resp, ...) fake_resp,
    .package = "httr2"
  )
  expect_error(
    call_gemini("sys", "user", schema = list(), model = "gemini-3.1-pro-preview", api_key = "fake-key"),
    "no candidate content"
  )
})
