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
