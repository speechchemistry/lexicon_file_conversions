library(testthat)

normalize_run_timestamp <- function(lines) {
  gsub(
    'dateModified="[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"',
    'dateModified="RUN_TIMESTAMP_UTC"',
    lines,
    perl = TRUE
  )
}

test_that("copy-lift-entries_end-to-end_one-guid", {
  input_lift <- "../data/copy-lift-entries/input/Sena3.lift"
  input_guids <- "../data/copy-lift-entries/input/one-guid.txt"
  expected <- readLines("../data/copy-lift-entries/expected/Sena3_one-guid.lift")

  result <- system2(
    "Rscript",
    args = c("../../scripts/copy-lift-entries.R", input_lift, input_guids),
    stdout = TRUE
  )

  expect_equal(normalize_run_timestamp(result), expected)
})

test_that("copy-lift-entries_end-to-end_duplicate-guid", {
  input_lift <- "../data/copy-lift-entries/input/Sena3.lift"
  input_guids <- "../data/copy-lift-entries/input/duplicate-guid.txt"
  expected <- readLines("../data/copy-lift-entries/expected/Sena3_duplicate-guid.lift")

  result <- system2(
    "Rscript",
    args = c("../../scripts/copy-lift-entries.R", input_lift, input_guids),
    stdout = TRUE
  )

  expect_equal(normalize_run_timestamp(result), expected)
})

test_that("copy-lift-entries_missing-guid_errors", {
  input_lift <- "../data/copy-lift-entries/input/Sena3.lift"
  input_guids <- "../data/copy-lift-entries/input/missing-guid.txt"

  result <- suppressWarnings(system2(
    "Rscript",
    args = c("../../scripts/copy-lift-entries.R", input_lift, input_guids),
    stdout = TRUE,
    stderr = TRUE
  ))

  status <- attr(result, "status")
  expect_false(is.null(status))
  expect_true(status != 0)
  expect_true(any(grepl("ERROR: GUID not found in source file", result, fixed = TRUE)))
})
