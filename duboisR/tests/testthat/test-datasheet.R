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
