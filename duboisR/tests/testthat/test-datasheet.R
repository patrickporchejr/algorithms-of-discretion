test_that("use_datasheet writes the template", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "datasheet.md")
  out <- use_datasheet(path, format = "md", open = FALSE)
  expect_true(file.exists(path))
  expect_equal(out, path)
  content <- readLines(path)
  expect_true(any(grepl("^# Datasheet", content)))
  expect_true(any(grepl("^## Motivation", content)))
  expect_true(any(grepl("^## Maintenance", content)))
})

test_that("use_datasheet refuses to overwrite without overwrite = TRUE", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "datasheet.md")
  use_datasheet(path, open = FALSE)
  expect_error(use_datasheet(path, open = FALSE), "already exists")
  expect_no_error(use_datasheet(path, overwrite = TRUE, open = FALSE))
})

test_that("use_datasheet supports the qmd format", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "datasheet.qmd")
  use_datasheet(path, format = "qmd", open = FALSE)
  content <- readLines(path)
  expect_true(any(grepl("^---", content)))
  expect_true(any(grepl("^## Motivation", content)))
})

test_that("read_datasheet returns NULL and a message for a missing path", {
  expect_message(res <- read_datasheet("does/not/exist.json"), "No datasheet found")
  expect_null(res)
})

test_that("read_datasheet parses the example fixture correctly", {
  fixture_path <- testthat::test_path("fixtures", "datasheet_example.json")
  res <- read_datasheet(fixture_path)
  expect_equal(res$motivation$purpose, "To audit racial disparities in Texas traffic stops using the Wells-Du Bois Protocol.")
  expect_equal(res$composition$sensitive_data, "Yes -- race and sex are sensitive attributes.")
})

test_that("seed_datasheet_answers creates a new file when none exists", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "datasheet.json")
  seed_datasheet_answers(list(motivation = list(purpose = "Demo purpose.")), path = path)
  res <- read_datasheet(path)
  expect_equal(res$motivation$purpose, "Demo purpose.")
})

test_that("seed_datasheet_answers fills blanks but does not clobber an existing answer by default", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "datasheet.json")
  seed_datasheet_answers(list(motivation = list(purpose = "Original.", funder = "Nobody.")), path = path)

  seed_datasheet_answers(list(motivation = list(purpose = "Overwritten?", funder = "Somebody.")), path = path)
  res <- read_datasheet(path)
  expect_equal(res$motivation$purpose, "Original.")
  expect_equal(res$motivation$funder, "Nobody.")
})

test_that("seed_datasheet_answers fills a genuinely blank question even when the section already exists", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "datasheet.json")
  seed_datasheet_answers(list(motivation = list(purpose = "Original.")), path = path)

  seed_datasheet_answers(list(motivation = list(funder = "Filled in later.")), path = path)
  res <- read_datasheet(path)
  expect_equal(res$motivation$purpose, "Original.")
  expect_equal(res$motivation$funder, "Filled in later.")
})

test_that("seed_datasheet_answers overwrites existing answers when overwrite_existing = TRUE", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "datasheet.json")
  seed_datasheet_answers(list(motivation = list(purpose = "Original.")), path = path)

  seed_datasheet_answers(list(motivation = list(purpose = "Replaced.")), path = path, overwrite_existing = TRUE)
  res <- read_datasheet(path)
  expect_equal(res$motivation$purpose, "Replaced.")
})

test_that("datasheet_schema returns the same section/question keys seed_datasheet_answers validates against", {
  schema <- datasheet_schema()
  expect_true(all(c("motivation", "composition", "uses", "maintenance") %in% names(schema)))
  expect_equal(schema$motivation$title, "Motivation")
  expect_true("purpose" %in% names(schema$motivation$questions))
  expect_type(schema$motivation$questions[["purpose"]], "character")
})

test_that("seed_datasheet_answers warns and skips unrecognized section/question keys", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "datasheet.json")
  expect_warning(
    seed_datasheet_answers(list(not_a_real_section = list(x = "y")), path = path),
    "not a known datasheet section"
  )
  expect_warning(
    seed_datasheet_answers(list(motivation = list(not_a_real_question = "y")), path = path),
    "not a known datasheet question"
  )
  res <- read_datasheet(path)
  expect_null(res$not_a_real_section)
  expect_null(res$motivation$not_a_real_question)
})
