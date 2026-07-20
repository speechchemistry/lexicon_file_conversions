fixture_dir <- testthat::test_path("..", "data", "lift2csv_sense-table")
script_path <- "../../scripts/lift2csv_sense-table.R"

test_that("sense-table fixtures have no legacy expected directory", {
  expect_no_legacy_expected_dir(fixture_dir)
})

for (input_path in fixture_inputs(fixture_dir)) {
  stem <- fixture_stem(input_path)

  test_that(paste0("sense-table_end-to-end_", stem), {
    expect_cli_stdout_snapshot(script_path, input_path)
  })
}
