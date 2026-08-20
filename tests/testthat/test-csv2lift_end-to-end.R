fixture_dir <- testthat::test_path("fixtures", "csv2lift")
script_path <- "../../scripts/csv2lift.R"

# One --tables prefix discovers every <stem>_<table>.csv for a stem in one
# flag, instead of one --<table> flag per table file that happens to exist
# (see plans/remaining-lift-fields.md's Phase T). Every stem's output must
# stay byte-identical to what the individual flags produced.
for (entries_path in fixture_inputs(fixture_dir, pattern = "_entries\\.csv$")) {
  stem <- sub("_entries$", "", fixture_stem(entries_path))
  prefix <- file.path(dirname(entries_path), stem)

  test_that(paste0("csv2lift_end-to-end_", stem), {
    expect_cli_stdout_file_snapshot(script_path, c("--tables", prefix), name = paste0(stem, ".lift"))
  })
}
