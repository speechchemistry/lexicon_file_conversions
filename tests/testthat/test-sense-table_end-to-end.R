fixture_dir <- testthat::test_path("fixtures", "lift2csv_sense-table")
script_path <- "../../scripts/lift2csv_sense-table.R"

for (input_path in fixture_inputs(fixture_dir)) {
  stem <- fixture_stem(input_path)

  test_that(paste0("sense-table_end-to-end_", stem), {
    expect_cli_stdout_file_snapshot(script_path, input_path, name = paste0(stem, ".csv"))
  })
}
