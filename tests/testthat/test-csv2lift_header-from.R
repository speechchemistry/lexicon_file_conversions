# --header-from is a plain per-document flag, not a table-registry row (see
# plans/remaining-lift-fields.md's D2) -- so it gets its own small test file
# rather than a row in test-csv2lift.R's table-dir loop.
test_that("csv2lift_header-from", {
  expect_cli_stdout_file_snapshot(
    "../../scripts/csv2lift.R",
    c(
      "--table-dir", testthat::test_path("fixtures", "csv2lift", "sena3-single-entry-plant"),
      "--header-from", testthat::test_path("fixtures", "lift2csv_entry-table", "sena3.lift")
    ),
    name = "sena3-single-entry-plant.lift"
  )
})

test_that("csv2lift_header-from_no-fields-in-source_warns-and-continues", {
  no_fields_lift <- withr::local_tempfile(fileext = ".lift")
  writeLines('<?xml version="1.0" encoding="UTF-8"?><lift version="0.13"></lift>', no_fields_lift)

  result <- suppressWarnings(system2(
    "Rscript",
    args = c(
      "../../scripts/csv2lift.R",
      "--table-dir", testthat::test_path("fixtures", "csv2lift", "sena3-single-entry-plant"),
      "--header-from", no_fields_lift
    ),
    stdout = TRUE,
    stderr = TRUE
  ))

  expect_cli_success(result)
  expect_true(any(grepl("no <header>/<fields>", result, fixed = TRUE)))
  # "<field " (with the trailing space before an attribute) only ever
  # appears in an emitted <field tag="..."> element, never in the warning
  # message above -- unlike "<header>"/"<fields>", which the message text
  # itself contains, so this is the one substring that actually
  # distinguishes "warned" from "warned AND still wrote a header".
  expect_false(any(grepl("<field ", result, fixed = TRUE)))
})
