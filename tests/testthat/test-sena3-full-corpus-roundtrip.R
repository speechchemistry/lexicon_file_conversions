# Formalises the full-sena3.lift round-trip spot check every table-adding
# increment has done by hand (plans/full-corpus-roundtrip-check.md): run the
# whole 1462-entry corpus through lift2csv.R --table-dir then
# csv2lift.R --table-dir, and confirm each registered table's own reader
# extracts identical data from the original and the round-tripped file. No
# _snaps/ directory -- this is an invariant assertion, not a snapshot: a
# byte-for-byte diff of a 1462-entry .lift file is not human-reviewable
# (AGENTS.md's Testing Approach), which is exactly why the curated per-table
# fixtures exist instead. Comparing via each table's own read_fn rather than
# raw XML also means this test is unaffected by SPEC.md's one documented,
# accepted round-trip infidelity (attribute-keyed sibling reorder) -- a
# reader extracts by xpath/column, not by sibling position.
#
# Loops table_registry() rather than naming tables by hand, so a future
# table (C1b, C3, D1, ...) is covered the moment its registry row exists,
# with no edit to this file.

sena3_path <- testthat::test_path("fixtures", "lift2csv_entry-table", "sena3.lift")

lift2csv_path <- "../../scripts/lift2csv.R"
csv2lift_path <- "../../scripts/csv2lift.R"

tables_dir <- withr::local_tempdir()
lift2csv_status <- system2("Rscript", c(lift2csv_path, sena3_path, "--table-dir", tables_dir),
                           stdout = FALSE, stderr = FALSE)

roundtrip_path <- withr::local_tempfile()
csv2lift_status <- system2("Rscript", c(csv2lift_path, "--table-dir", tables_dir),
                            stdout = roundtrip_path, stderr = FALSE)

test_that("sena3_full-roundtrip_setup succeeds", {
  expect_cli_success(lift2csv_status, what = "lift2csv.R")
  expect_cli_success(csv2lift_status, what = "csv2lift.R")
})

registry <- table_registry()

for (i in seq_len(nrow(registry))) {
  name <- registry$name[i]
  read_fn <- registry$read_fn[[i]]

  test_that(paste0("sena3_full-roundtrip_", name), {
    expect_identical(read_fn(sena3_path), read_fn(roundtrip_path))
  })
}
