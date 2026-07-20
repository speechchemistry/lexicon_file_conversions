fixture_dir <- testthat::test_path("..", "data", "lift2csv_join-sense-entry-table")
script_path <- "../../scripts/lift2csv_join-sense-entry-table.R"

for (input_path in fixture_inputs(fixture_dir)) {
  stem <- fixture_stem(input_path)

  test_that(paste0("join-sense-entry-table_end-to-end_", stem), {
    expect_cli_stdout_snapshot(script_path, input_path)
  })
}
