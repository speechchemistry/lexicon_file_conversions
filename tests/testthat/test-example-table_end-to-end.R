fixture_dir <- testthat::test_path("fixtures", "lift2csv_example-table")
script_path <- "../../scripts/lift2csv.R"

for (input_path in fixture_inputs(fixture_dir)) {
  stem <- fixture_stem(input_path)

  test_that(paste0("example-table_end-to-end_", stem), {
    expect_cli_stdout_file_snapshot(script_path, c(input_path, "--table", "examples"), name = paste0(stem, ".csv"))
  })
}
