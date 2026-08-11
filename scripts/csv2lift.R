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
p <- add_argument(p, "--pronunciations",
                  help="CSV matching lift2csv_pronunciation-table.R's column conventions", default = NA)
p <- add_argument(p, "--examples",
                  help="CSV matching lift2csv_example-table.R's column conventions", default = NA)
argv <- parse_args(p)

# Examples attach to <sense> elements, which only exist once --senses has
# been processed below — check up front so a missing --senses reads as a CLI
# usage error, not a per-row "sense_guid not found" that looks like bad data.
if (!is.na(argv$examples) && is.na(argv$senses)) {
  stop("--examples requires --senses: examples attach to <sense> elements, which the sense table creates.", call. = FALSE)
}

# na = "" and forcing every column to character avoid readr silently
# corrupting the round trip: blank cells must stay blank (not become "NA"),
# and guid/date/custom-field text that happens to look numeric must not be
# type-guessed and reformatted. trim_ws = FALSE for the same reason: a note
# ending "Do not parse: " is real source data, and format_csv() only quotes
# a value for embedded commas/quotes/newlines, not for edge whitespace, so
# read_csv()'s default trim_ws = TRUE would silently drop it on read.
entry_table <- read_csv(argv$entries_csv, na = "", col_types = cols(.default = "c"), trim_ws = FALSE, show_col_types = FALSE)
doc <- entry_table_to_lift(entry_table)

# pronunciations before senses so each entry's children come out in the
# canonical order (SPEC.md 3): both are appended by a second pass, so the
# call order here is what fixes <pronunciation> ahead of <sense>
if (!is.na(argv$pronunciations)) {
  pronunciation_table <- read_csv(argv$pronunciations, na = "", col_types = cols(.default = "c"), trim_ws = FALSE, show_col_types = FALSE)
  doc <- attach_pronunciations_to_lift(doc, pronunciation_table)
}

if (!is.na(argv$senses)) {
  sense_table <- read_csv(argv$senses, na = "", col_types = cols(.default = "c"), trim_ws = FALSE, show_col_types = FALSE)
  doc <- attach_senses_to_lift(doc, sense_table)
}

# Examples attach to <sense> elements, so this call must come after
# attach_senses_to_lift() above — <sense> nodes do not exist before then, so
# this is a correctness dependency, not just a readability convention.
if (!is.na(argv$examples)) {
  example_table <- read_csv(argv$examples, na = "", col_types = cols(.default = "c"), trim_ws = FALSE, show_col_types = FALSE)
  doc <- attach_examples_to_lift(doc, example_table)
}

cat(as.character(doc))
