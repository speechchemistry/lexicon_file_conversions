fixture_dir <- testthat::test_path("fixtures", "csv2lift")
script_path <- "../../scripts/csv2lift.R"

# One export per directory, one CSV per table inside it (entries.csv,
# senses.csv, ...) — see plans/remaining-lift-fields.md's Phase T. --tables
# discovers all of them in one flag.
for (export_dir in sort(list.dirs(fixture_dir, full.names = TRUE, recursive = FALSE))) {
  stem <- basename(export_dir)

  test_that(paste0("csv2lift_end-to-end_", stem), {
    expect_cli_stdout_file_snapshot(script_path, c("--tables", export_dir), name = paste0(stem, ".lift"))
  })
}
