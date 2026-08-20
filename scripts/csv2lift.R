library(argparser)
library(readr)

script_path <- normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))]))
script_dir <- dirname(script_path)
project_dir <- normalizePath(file.path(script_dir, ".."))
devtools::load_all(project_dir, quiet = TRUE)

# entries_csv used to be a required positional argument. It's now optional
# (an --entries flag or a --tables discovery can supply it instead), and
# argparser's positional arguments cannot be made optional regardless of
# `default` (see plans/remaining-lift-fields.md's Phase T) — so a bare
# leading positional is intercepted here, before argparser ever sees it,
# rather than declared through add_argument(). This is what keeps every
# existing `Rscript csv2lift.R entries.csv --senses ...` invocation working.
raw_argv <- commandArgs(trailingOnly = TRUE)
positional_entries_csv <- NA_character_
if (length(raw_argv) > 0 && !startsWith(raw_argv[1], "-")) {
  positional_entries_csv <- raw_argv[1]
  raw_argv <- raw_argv[-1]
}

registry <- table_registry()

p <- arg_parser("This script takes CSVs of entry-level (and optionally other) LIFT tables and produces a LIFT file")
p <- add_argument(p, "--tables",
                  help = "Directory to discover a CSV per table in (entries.csv, senses.csv, ...). Explicit flags below override a discovered file of the same table.",
                  default = NA)
for (i in seq_len(nrow(registry))) {
  p <- add_argument(p, registry$cli_flag[i], help = registry$help[i], default = NA)
}
argv <- parse_args(p, argv = raw_argv)

discovered <- if (!is.na(argv$tables)) discover_tables(argv$tables, registry) else list()

resolve_path <- function(name) {
  explicit <- argv[[name]]
  if (!is.na(explicit)) return(explicit)
  if (name == "entries" && !is.na(positional_entries_csv)) return(positional_entries_csv)
  discovered[[name]]
}

resolved <- setNames(lapply(registry$name, resolve_path), registry$name)

if (is.null(resolved$entries) || is.na(resolved$entries)) {
  stop("No entries CSV supplied: provide it as a positional argument, --entries, or via --tables <dir>.", call. = FALSE)
}

# Checked up front so a missing required table reads as a CLI usage error,
# not as a per-row lookup failure (e.g. "sense_guid not found") that looks
# like bad data.
for (i in seq_len(nrow(registry))) {
  name <- registry$name[i]
  reqs <- registry$requires[[i]]
  if (length(reqs) == 0) next
  present <- !is.null(resolved[[name]]) && !is.na(resolved[[name]])
  if (!present) next
  missing_reqs <- reqs[vapply(reqs, function(r) is.null(resolved[[r]]) || is.na(resolved[[r]]), logical(1))]
  if (length(missing_reqs) > 0) {
    stop(sprintf(
      "--%s requires %s: attaches to an element the latter table's rows create.",
      name, paste0("--", missing_reqs, collapse = ", ")
    ), call. = FALSE)
  }
}

# Registry row order is attach order (matches SPEC.md's Entry Table canonical
# child order): entries first (its attach_fn creates the document rather
# than attaching to one), then pronunciations, senses, examples.
doc <- NULL
for (i in seq_len(nrow(registry))) {
  name <- registry$name[i]
  path <- resolved[[name]]
  if (is.null(path) || is.na(path)) next
  table <- read_csv(path, na = "", col_types = cols(.default = "c"), trim_ws = FALSE, show_col_types = FALSE)
  doc <- registry$attach_fn[[i]](doc, table)
}

cat(as.character(doc))
