# lift2csv.R
# Reads a LIFT file and writes it out as CSV, in one of two modes:
#   --table <name>     writes one registry table's CSV to stdout
#   --table-dir <dir>  writes every table in the registry (see
#                       R/table_registry.R) as one CSV under <dir>, in one
#                       pass -- the read-side counterpart to csv2lift.R's
#                       --table-dir discovery.
# Exactly one of the two must be given.

library(argparser)
library(readr)

script_path <- normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))]))
script_dir <- dirname(script_path)
project_dir <- normalizePath(file.path(script_dir, ".."))
devtools::load_all(project_dir, quiet = TRUE)

registry <- table_registry()

p <- arg_parser("This script takes a LIFT file and writes it as CSV, one table to stdout (--table) or every table into a directory (--table-dir)")
p <- add_argument(p, "LIFT_file", help = "SIL Flex lexicon LIFT file")
p <- add_argument(p, "--table", help = sprintf("Write one table's CSV to stdout (one of: %s)", paste(registry$name, collapse = ", ")), default = NA)
p <- add_argument(p, "--table-dir", help = "Directory to write every table's CSV into (entries.csv, senses.csv, ...)", default = NA)
argv <- parse_args(p)

if (!is.na(argv$table) && !is.na(argv$table_dir)) {
  stop("--table and --table-dir are mutually exclusive: one table to stdout, or every table into a directory.", call. = FALSE)
}
if (is.na(argv$table) && is.na(argv$table_dir)) {
  stop("Supply either --table <name> or --table-dir <dir>.", call. = FALSE)
}
if (!is.na(argv$table_dir) && file.exists(argv$table_dir) && !dir.exists(argv$table_dir)) {
  stop(sprintf("--table-dir %s already exists as a file, not a directory. Remove or rename it and try again.", argv$table_dir), call. = FALSE)
}

# format_table_csv() (R/table_csv.R) is shared by both modes so the
# empty-column/empty-table convention is enforced identically regardless of
# which mode a table is reached through.

if (!is.na(argv$table)) {
  row <- which(registry$name == argv$table)
  if (length(row) == 0) {
    stop(sprintf("Unrecognised --table %s (expected one of: %s)", argv$table, paste(registry$name, collapse = ", ")), call. = FALSE)
  }

  table <- registry$read_fn[[row]](argv$LIFT_file)
  cat(format_table_csv(table))
} else {
  for (i in seq_len(nrow(registry))) {
    name <- registry$name[i]
    table <- registry$read_fn[[i]](argv$LIFT_file)

    # A table with no rows for this LIFT file is omitted entirely, not
    # written as an empty file: csv2lift.R's --table-dir discovery treats
    # any CSV present as "this table should be attached", and the set of
    # files present is how a table folder documents what the lexicon
    # actually contains -- a folder with no pronunciations.csv means no
    # pronunciations, not an empty one. entries is the exception -- it is
    # the one mandatory table, so its CSV is always written, empty or not.
    if (nrow(table) == 0 && name != "entries") next

    out_path <- table_csv_path(argv$table_dir, name)
    dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
    cat(format_table_csv(table), file = out_path)
  }
}
