fixture_inputs <- function(fixture_dir, pattern = "\\.lift$") {
  inputs <- sort(list.files(fixture_dir, pattern = pattern, full.names = TRUE))

  if (length(inputs) == 0) {
    stop("No input fixtures found in ", fixture_dir, call. = FALSE)
  }

  inputs
}

fixture_stem <- function(path) {
  tools::file_path_sans_ext(basename(path))
}

# system2() reports the exit status two different ways depending on how
# stdout was captured, and the difference is what let a crashed script pass
# as a correct empty result for so long:
#   stdout = <file> -> returns the status as an integer (0 on success)
#   stdout = TRUE   -> returns the output lines, with a "status" attribute
#                      attached *only on failure* (absent, not 0L, on success)
# Both shapes funnel through here so no caller has to remember which it got.
cli_status <- function(result) {
  if (is.character(result)) {
    status <- attr(result, "status")
    return(if (is.null(status)) 0L else as.integer(status))
  }

  as.integer(result)
}

expect_cli_success <- function(result, what = "CLI invocation") {
  status <- cli_status(result)

  if (identical(status, 0L)) {
    testthat::succeed()
  } else {
    testthat::fail(sprintf("%s exited with status %d (expected 0)", what, status))
  }
}

run_cli_to_file <- function(script_path, args, out_path, stdin = "") {
  system2(
    "Rscript",
    args = c(script_path, args),
    stdout = out_path,
    stdin = stdin
  )
}

expect_cli_stdout_file_snapshot <- function(script_path, args, name, transform = identity, stdin = "") {
  out_path <- withr::local_tempfile()
  status <- run_cli_to_file(script_path, args, out_path, stdin = stdin)

  # A script that dies before writing anything leaves zero bytes on stdout,
  # which is byte-identical to the approved snapshot of a legitimately empty
  # table — so without this the test passes, and on a first run will even
  # auto-approve the crash as a new baseline. Return rather than fall
  # through: comparing the snapshot of a failed run only buries the real
  # failure under a spurious mismatch.
  if (!identical(cli_status(status), 0L)) {
    expect_cli_success(status, what = basename(script_path))
    return(invisible(NULL))
  }

  testthat::expect_snapshot_file(out_path, name = name, compare = testthat::compare_file_text, transform = transform)
}

# One approval test per curated fixture in `fixture_dir`, each pinning the
# stdout of `lift2csv.R --table <table>` (plans/per-table-script-consolidation.md's
# R4). The label prefix is derived from the fixture directory rather than from
# `table`, so it stays what it has always been: entry-table_<stem>, not
# entries_<stem>.
#
# Called once per test file, deliberately NOT looped over table_registry() from
# a single file. Two properties of testthat 3.3.2, both measured, rule that out:
#   * A _snaps/ directory is named after the *test file*, and cannot nest.
#     expect_snapshot_file(name = "entries/sena3.csv") warns "cannot create
#     file ... reason 'No such file or directory'" and then reports "Adding new
#     file snapshot" anyway -- warnings, not failures, having written nothing.
#     One test file therefore means one flat directory, and the tables share
#     fixture stems (lela-teli-empty-lexicon is in all four), so every artifact
#     would need renaming with a table prefix.
#   * snapshot_accept()'s `files` matching is exact, with no globbing --
#     snapshot_meta() filters on `name %in% files | test %in% dirs`, which is
#     why snapshot_accept("entry-table/") works: entry-table is a real
#     directory. A single shared directory could only ever be accepted whole.
# One file per table keeps per-table review, and keeps every approved artifact
# exactly where it already is.
#
# `table` is deliberately not checked against the registry: `--table <typo>` is
# already a nonzero-exit usage error listing the valid names, which the status
# assertion below turns into a test failure.
expect_table_snapshots <- function(table, fixture_dir,
                                   script_path = "../../scripts/lift2csv.R") {
  label_prefix <- sub("^lift2csv_", "", fixture_dir)

  for (input_path in fixture_inputs(testthat::test_path("fixtures", fixture_dir))) {
    stem <- fixture_stem(input_path)

    testthat::test_that(paste0(label_prefix, "_", stem), {
      expect_cli_stdout_file_snapshot(
        script_path,
        c(input_path, "--table", table),
        name = paste0(stem, ".csv")
      )
    })
  }
}
