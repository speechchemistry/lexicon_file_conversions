library(argparser)
library(readr)

script_path <- normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))]))
script_dir <- dirname(script_path)
project_dir <- normalizePath(file.path(script_dir, ".."))
devtools::load_all(project_dir, quiet = TRUE)

p <- arg_parser("This script takes CSVs of entry-level (and optionally sense-level) fields and produces a LIFT file")
p <- add_argument(p, "entries_csv",
                  help="CSV matching lift2csv_entry-table.R's column conventions")
p <- add_argument(p, "--senses",
                  help="CSV matching lift2csv_sense-table.R's column conventions", default = NA)
argv <- parse_args(p)

# na = "" and forcing every column to character avoid readr silently
# corrupting the round trip: blank cells must stay blank (not become "NA"),
# and guid/date/custom-field text that happens to look numeric must not be
# type-guessed and reformatted.
entry_table <- read_csv(argv$entries_csv, na = "", col_types = cols(.default = "c"), show_col_types = FALSE)
doc <- entry_table_to_lift(entry_table)

if (!is.na(argv$senses)) {
  sense_table <- read_csv(argv$senses, na = "", col_types = cols(.default = "c"), show_col_types = FALSE)
  doc <- attach_senses_to_lift(doc, sense_table)
}

cat(as.character(doc))
