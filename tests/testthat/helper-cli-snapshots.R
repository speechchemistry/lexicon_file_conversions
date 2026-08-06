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

run_cli_to_file <- function(script_path, args, out_path, stdin = "") {
  system2(
    "Rscript",
    args = c(script_path, args),
    stdout = out_path,
    stdin = stdin
  )
  out_path
}

expect_cli_stdout_file_snapshot <- function(script_path, args, name, transform = identity, stdin = "") {
  out_path <- withr::local_tempfile()
  run_cli_to_file(script_path, args, out_path, stdin = stdin)
  testthat::expect_snapshot_file(out_path, name = name, compare = testthat::compare_file_text, transform = transform)
}