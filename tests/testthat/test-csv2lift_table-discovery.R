# Covers the --tables discovery rule itself (plans/remaining-lift-fields.md's
# Phase T): the folder-prefix half that test-csv2lift_end-to-end.R's flat
# fixtures don't exercise, the error paths a snapshot can't capture (the
# snapshot helper only records stdout), and that an explicit flag overrides
# a discovered file of the same table.

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

test_that("csv2lift_table-discovery_folder-prefix matches the flat-prefix output", {
  folder_prefix <- testthat::test_path("fixtures", "csv2lift-folder", "Sena3_gloss_initial_b")
  flat_prefix <- testthat::test_path("fixtures", "csv2lift", "Sena3_gloss_initial_b")

  folder_out <- run_csv2lift(c("--tables", paste0(folder_prefix, "/")))
  flat_out <- run_csv2lift(c("--tables", flat_prefix))

  expect_cli_success(folder_out)
  expect_identical(as.character(folder_out), as.character(flat_out))
})

test_that("csv2lift_table-discovery_missing-entries_errors", {
  senses_path <- testthat::test_path("fixtures", "csv2lift", "sena3_single_entry_plant_senses.csv")
  expect_usage_error(c("--senses", senses_path), "No entries CSV supplied")
})

test_that("csv2lift_table-discovery_examples-without-senses_errors", {
  # Built under a temp dir, not the checked-in fixtures: this shape (examples
  # with no senses) is only interesting as an error case, so it doesn't earn
  # a place among the static fixtures the way Sena3_gloss_initial_b's folder
  # copy does.
  folder_dir <- withr::local_tempdir()
  file.copy(
    testthat::test_path("fixtures", "csv2lift", "Sena3_gloss_initial_b_entries.csv"),
    file.path(folder_dir, "entries.csv")
  )
  file.copy(
    testthat::test_path("fixtures", "csv2lift", "Sena3_gloss_initial_b_examples.csv"),
    file.path(folder_dir, "examples.csv")
  )

  expect_usage_error(c("--tables", paste0(folder_dir, "/")), "--examples requires --senses")
})

test_that("csv2lift_table-discovery_unrecognised-csv_errors", {
  folder_dir <- withr::local_tempdir()
  file.copy(
    testthat::test_path("fixtures", "csv2lift", "Sena3_gloss_initial_b_entries.csv"),
    file.path(folder_dir, "entries.csv")
  )
  file.copy(
    testthat::test_path("fixtures", "csv2lift", "Sena3_gloss_initial_b_senses.csv"),
    file.path(folder_dir, "sense.csv")
  )

  expect_usage_error(c("--tables", paste0(folder_dir, "/")), "Unrecognised CSV(s)")
})

test_that("csv2lift_table-discovery_explicit-flag-overrides-discovery", {
  # note_and_phonology_notes has entries + pronunciations + senses and no
  # examples, so truncating its senses.csv carries no risk of leaving an
  # example pointing at a sense_guid that no longer exists.
  flat_prefix <- testthat::test_path("fixtures", "csv2lift", "note_and_phonology_notes")

  # A truncated copy of that fixture's own senses.csv: same entry_id values
  # (so the FK still resolves), fewer rows (so the output visibly differs),
  # proving the --senses flag's file was used instead of the discovered one.
  override_dir <- withr::local_tempdir()
  full_senses <- readLines(paste0(flat_prefix, "_senses.csv"))
  writeLines(full_senses[1:2], file.path(override_dir, "override_senses.csv"))

  with_override <- run_csv2lift(c(
    "--tables", flat_prefix,
    "--senses", file.path(override_dir, "override_senses.csv")
  ))
  without_override <- run_csv2lift(c("--tables", flat_prefix))

  expect_cli_success(with_override)
  expect_false(identical(as.character(with_override), as.character(without_override)))
})
