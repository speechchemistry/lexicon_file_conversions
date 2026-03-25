library(argparser)

script_path <- normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))]))
script_dir <- dirname(script_path)
project_dir <- normalizePath(file.path(script_dir, ".."))
devtools::load_all(project_dir, quiet = TRUE)

p <- arg_parser("Extract selected LIFT entries by GUID and write a new LIFT document to stdout")
p <- add_argument(p, "source_lift", help = "Path to source LIFT file")
p <- add_argument(p, "guid_file", help = "File with one GUID per line, '-' for stdin, or omit for stdin", default = "-")
argv <- parse_args(p)

guide_source <- argv$guid_file
if (is.null(guide_source) || !nzchar(guide_source) || identical(guide_source, "-")) {
  guide_source <- "-"
}

tryCatch({
  result <- copy_lift_entries(
    source_lift = argv$source_lift,
    guid_source = guide_source,
    log_progress = TRUE
  )

  cat("Writing output to stdout...\n", file = stderr())
  cat(result$xml)
  cat(sprintf("\nSUCCESS: Wrote %d entries to stdout\n", result$count), file = stderr())
}, error = function(e) {
  cat(sprintf("ERROR: %s\n", conditionMessage(e)), file = stderr())
  quit(save = "no", status = 1)
})
