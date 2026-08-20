# Covers scripts/lift2csv.R, the read-side registry umbrella (plans/
# remaining-lift-fields.md's Phase T; --table and the --table-dir rename are
# plans/per-table-script-consolidation.md's R1).
# It has no per-table content snapshot of its own — each table's content is
# already pinned by its own <name>-table.R snapshot test, now run
# through --table <name> on this same script — so this pins what is
# genuinely --table-dir's own: which filenames it writes (the skip-empty-
# table rule), plus the CLI usage errors --table introduced.

script_path <- "../../scripts/lift2csv.R"
entry_fixture_dir <- testthat::test_path("fixtures", "lift2csv_entry-table")

expect_lift2csv_table_dir_writes <- function(lift_file, expected_tables) {
  out_dir <- withr::local_tempdir()
  status <- system2("Rscript", args = c(script_path, lift_file, "--table-dir", out_dir), stdout = FALSE, stderr = FALSE)
  expect_cli_success(status, what = "lift2csv.R")

  written <- sort(tools::file_path_sans_ext(list.files(out_dir, pattern = "\\.csv$")))
  expect_identical(written, sort(expected_tables))
}

test_that("lift2csv_with-pronunciations writes entries, senses, pronunciations (no examples)", {
  expect_lift2csv_table_dir_writes(
    file.path(entry_fixture_dir, "zhi-two-pronunciations-with-audio-and-ipa.lift"),
    c("entries", "senses", "pronunciations")
  )
})

test_that("lift2csv_without-pronunciations writes entries, senses, examples (no pronunciations)", {
  expect_lift2csv_table_dir_writes(
    file.path(entry_fixture_dir, "sena3-gloss-initial-b.lift"),
    c("entries", "senses", "examples")
  )
})

test_that("lift2csv_empty-lexicon still writes entries.csv, the one mandatory table", {
  expect_lift2csv_table_dir_writes(
    file.path(entry_fixture_dir, "lela-teli-empty-lexicon.lift"),
    c("entries")
  )
})

run_lift2csv <- function(args) {
  suppressWarnings(system2("Rscript", args = c(script_path, args), stdout = TRUE, stderr = TRUE))
}

expect_usage_error <- function(args, pattern) {
  result <- run_lift2csv(args)
  status <- cli_status(result)
  expect_false(identical(status, 0L))
  expect_true(any(grepl(pattern, result, fixed = TRUE)))
}

test_that("lift2csv_table-and-table-dir-together_errors", {
  lift_file <- file.path(entry_fixture_dir, "lela-teli-empty-lexicon.lift")
  expect_usage_error(c(lift_file, "--table", "entries", "--table-dir", withr::local_tempdir()), "mutually exclusive")
})

test_that("lift2csv_neither-flag_errors", {
  lift_file <- file.path(entry_fixture_dir, "lela-teli-empty-lexicon.lift")
  expect_usage_error(lift_file, "Supply either --table")
})

test_that("lift2csv_unrecognised-table-name_errors_and_lists_valid_names", {
  lift_file <- file.path(entry_fixture_dir, "lela-teli-empty-lexicon.lift")
  expect_usage_error(c(lift_file, "--table", "bogus"), "Unrecognised --table bogus")
  expect_usage_error(c(lift_file, "--table", "bogus"), "entries, pronunciations, senses, examples")
})
