library(testthat)

normalize_run_timestamp <- function(lines) {
  gsub(
    'dateModified="[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"',
    'dateModified="RUN_TIMESTAMP_UTC"',
    lines,
    perl = TRUE
  )
}

script_path <- "../../scripts/copy-lift-entries.R"

test_that("copy-lift-entries_end-to-end_one-guid", {
  input_lift <- "fixtures/copy-lift-entries/Sena3.lift"
  input_guids <- "fixtures/copy-lift-entries/one-guid.txt"

  expect_cli_stdout_file_snapshot(
    script_path, c(input_lift, input_guids),
    name = "one-guid.lift", transform = normalize_run_timestamp
  )
})

test_that("copy-lift-entries_end-to-end_duplicate-guid", {
  input_lift <- "fixtures/copy-lift-entries/Sena3.lift"
  input_guids <- "fixtures/copy-lift-entries/duplicate-guid.txt"

  expect_cli_stdout_file_snapshot(
    script_path, c(input_lift, input_guids),
    name = "duplicate-guid.lift", transform = normalize_run_timestamp
  )
})

test_that("copy-lift-entries_end-to-end_guid-from-stdin", {
  input_lift <- "fixtures/copy-lift-entries/Sena3.lift"

  expect_cli_stdout_file_snapshot(
    script_path, c(input_lift, "-"),
    name = "guid-from-stdin.lift", transform = normalize_run_timestamp,
    stdin = "fixtures/copy-lift-entries/one-guid.txt"
  )
})

test_that("copy-lift-entries_end-to-end_guid-from-stdin_when-guid-arg-omitted", {
  input_lift <- "fixtures/copy-lift-entries/Sena3.lift"

  expect_cli_stdout_file_snapshot(
    script_path, input_lift,
    name = "guid-from-stdin_when-guid-arg-omitted.lift", transform = normalize_run_timestamp,
    stdin = "fixtures/copy-lift-entries/one-guid.txt"
  )
})

test_that("copy-lift-entries_missing-guid_errors", {
  input_lift <- "fixtures/copy-lift-entries/Sena3.lift"
  input_guids <- "fixtures/copy-lift-entries/missing-guid.txt"

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
