# Covers scripts/lift2csv.R, the read-side registry umbrella added alongside
# csv2lift.R's --tables discovery (plans/remaining-lift-fields.md's Phase T).
# It has no per-table content snapshot of its own — each table's content is
# already pinned by its own lift2csv_<name>-table.R snapshot test — so this
# pins the two things that are genuinely its own: which filenames it writes
# (the skip-empty-table rule), and that each file it writes is byte-identical
# to what the corresponding per-table script produces for the same input.

script_path <- "../../scripts/lift2csv.R"
entry_fixture_dir <- testthat::test_path("fixtures", "lift2csv_entry-table")

per_table_script <- list(
  entries = "../../scripts/lift2csv_entry-table.R",
  senses = "../../scripts/lift2csv_sense-table.R",
  pronunciations = "../../scripts/lift2csv_pronunciation-table.R",
  examples = "../../scripts/lift2csv_example-table.R"
)

expect_lift2csv_umbrella_matches_per_table_scripts <- function(lift_file, expected_tables) {
  out_dir <- withr::local_tempdir()
  system2("Rscript", args = c(script_path, lift_file, "--tables", out_dir), stdout = FALSE, stderr = FALSE)

  written <- sort(tools::file_path_sans_ext(list.files(out_dir, pattern = "\\.csv$")))
  expect_identical(written, sort(expected_tables))

  for (name in expected_tables) {
    umbrella_out <- readLines(file.path(out_dir, paste0(name, ".csv")))
    per_table_out <- system2("Rscript", args = c(per_table_script[[name]], lift_file), stdout = TRUE)
    expect_identical(umbrella_out, per_table_out, info = name)
  }
}

test_that("lift2csv_end-to-end_with-pronunciations writes entries, senses, pronunciations (no examples)", {
  expect_lift2csv_umbrella_matches_per_table_scripts(
    file.path(entry_fixture_dir, "two_pronunciations_with_audio_and_IPA.lift"),
    c("entries", "senses", "pronunciations")
  )
})

test_that("lift2csv_end-to-end_without-pronunciations writes entries, senses, examples (no pronunciations)", {
  expect_lift2csv_umbrella_matches_per_table_scripts(
    file.path(entry_fixture_dir, "Sena3_gloss_initial_b.lift"),
    c("entries", "senses", "examples")
  )
})

test_that("lift2csv_end-to-end_empty-lexicon still writes entries.csv, the one mandatory table", {
  expect_lift2csv_umbrella_matches_per_table_scripts(
    file.path(entry_fixture_dir, "lela-teli-empty-lexicon.lift"),
    c("entries")
  )
})
