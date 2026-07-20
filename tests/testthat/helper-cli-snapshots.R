fixture_inputs <- function(fixture_dir, pattern = "\\.lift$") {
  input_dir <- file.path(fixture_dir, "input")
  inputs <- sort(list.files(input_dir, pattern = pattern, full.names = TRUE))

  if (length(inputs) == 0) {
    stop("No input fixtures found in ", input_dir, call. = FALSE)
  }

  inputs
}

fixture_stem <- function(path) {
  tools::file_path_sans_ext(basename(path))
}

expect_no_legacy_expected_dir <- function(fixture_dir) {
  legacy_dir <- file.path(fixture_dir, "expected")

  testthat::expect_false(
    dir.exists(legacy_dir),
    info = paste("Legacy expected fixture directory should be removed:", legacy_dir)
  )
}

run_cli_stdout <- function(script_path, args) {
  system2(
    "Rscript",
    args = c(script_path, args),
    stdout = TRUE
  )
}

expect_cli_stdout_snapshot <- function(script_path, input_path, transform = identity) {
  testthat::local_reproducible_output(width = 80)

  result <- run_cli_stdout(script_path, input_path)
  lines <- transform(result)

  testthat::expect_snapshot({
    writeLines(lines)
  })
}