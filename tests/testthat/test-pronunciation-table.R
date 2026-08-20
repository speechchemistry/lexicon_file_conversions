fixture_dir <- testthat::test_path("fixtures", "lift2csv_pronunciation-table")
script_path <- "../../scripts/lift2csv.R"

for (input_path in fixture_inputs(fixture_dir)) {
  stem <- fixture_stem(input_path)

  test_that(paste0("pronunciation-table_", stem), {
    expect_cli_stdout_file_snapshot(script_path, c(input_path, "--table", "pronunciations"), name = paste0(stem, ".csv"))
  })
}
