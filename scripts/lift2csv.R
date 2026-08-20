# lift2csv.R
# Reads a LIFT file and writes every table in the registry (see
# R/table_registry.R) as one CSV under --tables <prefix>, in one pass —
# the read-side counterpart to csv2lift.R's --tables discovery.

library(argparser)
library(readr)

script_path <- normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))]))
script_dir <- dirname(script_path)
project_dir <- normalizePath(file.path(script_dir, ".."))
devtools::load_all(project_dir, quiet = TRUE)

p <- arg_parser("This script takes a LIFT file and writes one CSV per table into --tables <prefix>")
p <- add_argument(p, "LIFT_file", help = "SIL Flex lexicon LIFT file")
p <- add_argument(p, "--tables",
                  help = "Prefix to write per-table CSVs under: a folder ending in '/' (files named entries.csv, senses.csv, ...) or a stem (files named <stem>_entries.csv, <stem>_senses.csv, ...)")
argv <- parse_args(p)

registry <- table_registry()

for (i in seq_len(nrow(registry))) {
  name <- registry$name[i]
  table <- registry$read_fn[[i]](argv$LIFT_file)

  # A table with no rows for this LIFT file is omitted entirely, not written
  # as an empty file: csv2lift.R's --tables discovery treats any CSV present
  # as "this table should be attached", so writing an empty file for every
  # table regardless of content would make every table's optionality
  # disappear. entries is the exception — it is the one mandatory table, so
  # its CSV is always written, empty or not, exactly like
  # scripts/lift2csv_entry-table.R does today.
  if (nrow(table) == 0 && name != "entries") next

  out_path <- table_csv_path(argv$tables, name)
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)

  if (nrow(table) == 0) {
    cat("", file = out_path)
  } else {
    cat(format_csv(table, na = ""), file = out_path)
  }
}
