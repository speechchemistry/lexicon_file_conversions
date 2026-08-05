fixture_dir <- testthat::test_path("..", "data", "csv2lift_entry-table")
script_path <- "../../scripts/csv2lift_entry-table.R"

for (input_path in fixture_inputs(fixture_dir, pattern = "\\.csv$")) {
  stem <- fixture_stem(input_path)
  test_that(paste0("csv2lift-entry-table_end-to-end_", stem), {
    expect_cli_stdout_file_snapshot(script_path, input_path, name = paste0(stem, ".lift"))
  })
}
