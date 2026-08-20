# Guards the CLI snapshot helper itself. A script that dies before writing
# anything leaves zero bytes on stdout, which is byte-identical to a
# legitimately empty table's approved snapshot (six of those exist, e.g.
# _snaps/sense-table/lela-teli-empty-lexicon.csv). The exit status is the
# only thing that separates "correctly produced nothing" from "crashed", so
# the helper has to assert it — see plans/per-table-script-consolidation.md's
# R0.

test_that("expect_cli_stdout_file_snapshot fails when the script exits nonzero", {
  expect_failure(
    expect_cli_stdout_file_snapshot(
      "../../scripts/lift2csv.R",
      c("/nonexistent/missing.lift", "--tables", withr::local_tempdir()),
      name = "nonzero-exit-guard.csv"
    )
  )
})

test_that("cli_status reads both of system2's success conventions", {
  # stdout = <file> returns the status as an integer...
  expect_identical(cli_status(0L), 0L)
  expect_identical(cli_status(1L), 1L)

  # ...while stdout = TRUE returns the output lines and attaches "status"
  # only on failure, so its absence is what success looks like.
  ok <- c("a", "b")
  expect_identical(cli_status(ok), 0L)
  failed <- structure(c("a"), status = 2L)
  expect_identical(cli_status(failed), 2L)
})
