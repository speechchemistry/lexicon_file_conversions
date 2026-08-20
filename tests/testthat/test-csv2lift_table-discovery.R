# Covers the --tables discovery rule itself (plans/remaining-lift-fields.md's
# Phase T): a trailing slash on the directory being tolerated, the error
# paths a snapshot can't capture (the snapshot helper only records stdout),
# and that an explicit flag overrides a discovered file of the same table.

script_path <- "../../scripts/csv2lift.R"

run_csv2lift <- function(args) {
  suppressWarnings(system2(
    "Rscript",
    args = c(script_path, args),
    stdout = TRUE,
    stderr = TRUE
  ))
}

expect_usage_error <- function(args, pattern) {
  result <- run_csv2lift(args)
  status <- attr(result, "status")
  expect_false(is.null(status))
  expect_true(status != 0)
  expect_true(any(grepl(pattern, result, fixed = TRUE)))
}

# system2()'s "status" attribute is only set on a nonzero exit, not on
# success (it is simply absent, not 0L), so a successful run is asserted by
# its absence rather than by comparing to 0.
expect_cli_success <- function(result) {
  status <- attr(result, "status")
  expect_true(is.null(status) || status == 0)
}

test_that("csv2lift_table-discovery_trailing-slash is tolerated and insignificant", {
  export_dir <- testthat::test_path("fixtures", "csv2lift", "sena3-gloss-initial-b")

  without_slash <- run_csv2lift(c("--tables", export_dir))
  with_slash <- run_csv2lift(c("--tables", paste0(export_dir, "/")))

  expect_cli_success(without_slash)
  expect_identical(as.character(without_slash), as.character(with_slash))
})

test_that("csv2lift_table-discovery_missing-entries_errors", {
  senses_path <- testthat::test_path("fixtures", "csv2lift", "sena3-single-entry-plant", "senses.csv")
  expect_usage_error(c("--senses", senses_path), "No entries CSV supplied")
})

test_that("csv2lift_table-discovery_examples-without-senses_errors", {
  # Built under a temp dir, not the checked-in fixtures: this shape (examples
  # with no senses) is only interesting as an error case, so it doesn't earn
  # a place among the static fixtures the way sena3-gloss-initial-b does.
  export_dir <- testthat::test_path("fixtures", "csv2lift", "sena3-gloss-initial-b")
  tables_dir <- withr::local_tempdir()
  file.copy(file.path(export_dir, "entries.csv"), file.path(tables_dir, "entries.csv"))
  file.copy(file.path(export_dir, "examples.csv"), file.path(tables_dir, "examples.csv"))

  expect_usage_error(c("--tables", tables_dir), "--examples requires --senses")
})

test_that("csv2lift_table-discovery_unrecognised-csv_errors", {
  export_dir <- testthat::test_path("fixtures", "csv2lift", "sena3-gloss-initial-b")
  tables_dir <- withr::local_tempdir()
  file.copy(file.path(export_dir, "entries.csv"), file.path(tables_dir, "entries.csv"))
  file.copy(file.path(export_dir, "senses.csv"), file.path(tables_dir, "sense.csv"))

  expect_usage_error(c("--tables", tables_dir), "Unrecognised CSV(s)")
})

test_that("csv2lift_table-discovery_explicit-flag-overrides-discovery", {
  # zhi-note-and-phonology-notes has entries + pronunciations + senses and no
  # examples, so truncating its senses.csv carries no risk of leaving an
  # example pointing at a sense_guid that no longer exists.
  tables_dir <- testthat::test_path("fixtures", "csv2lift", "zhi-note-and-phonology-notes")

  # A truncated copy of that fixture's own senses.csv: same entry_id values
  # (so the FK still resolves), fewer rows (so the output visibly differs),
  # proving the --senses flag's file was used instead of the discovered one.
  override_dir <- withr::local_tempdir()
  full_senses <- readLines(file.path(tables_dir, "senses.csv"))
  writeLines(full_senses[1:2], file.path(override_dir, "override_senses.csv"))

  with_override <- run_csv2lift(c(
    "--tables", tables_dir,
    "--senses", file.path(override_dir, "override_senses.csv")
  ))
  without_override <- run_csv2lift(c("--tables", tables_dir))

  expect_cli_success(with_override)
  expect_false(identical(as.character(with_override), as.character(without_override)))
})
