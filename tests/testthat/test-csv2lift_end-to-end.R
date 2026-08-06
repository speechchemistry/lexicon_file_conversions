fixture_dir <- testthat::test_path("..", "data", "csv2lift")
script_path <- "../../scripts/csv2lift.R"

for (entries_path in fixture_inputs(fixture_dir, pattern = "_entries\\.csv$")) {
  stem <- sub("_entries$", "", fixture_stem(entries_path))
  senses_path <- file.path(dirname(entries_path), paste0(stem, "_senses.csv"))

  args <- entries_path
  if (file.exists(senses_path)) args <- c(args, "--senses", senses_path)

  test_that(paste0("csv2lift_end-to-end_", stem), {
    expect_cli_stdout_file_snapshot(script_path, args, name = paste0(stem, ".lift"))
  })
}
