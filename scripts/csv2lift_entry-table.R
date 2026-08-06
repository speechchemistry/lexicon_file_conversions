library(argparser)
library(readr)

script_path <- normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))]))
script_dir <- dirname(script_path)
project_dir <- normalizePath(file.path(script_dir, ".."))
devtools::load_all(project_dir, quiet = TRUE)

p <- arg_parser("This script takes a CSV of entry-level fields and produces a LIFT file")
p <- add_argument(p, "CSV_file",
                  help="CSV matching lift2csv_entry-table.R's column conventions")
argv <- parse_args(p)

# na = "" and forcing every column to character avoid readr silently
# corrupting the round trip: blank cells must stay blank (not become "NA"),
# and guid/date/custom-field text that happens to look numeric must not be
# type-guessed and reformatted.
entry_table <- read_csv(argv$CSV_file, na = "", col_types = cols(.default = "c"), show_col_types = FALSE)
doc <- entry_table_to_lift(entry_table)
cat(as.character(doc))
