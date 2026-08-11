# lift2csv_example-table.R
# Extracts <example> rows from a LIFT file and writes CSV to stdout

library(argparser)
library(readr)

script_path <- normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))]))
script_dir <- dirname(script_path)
project_dir <- normalizePath(file.path(script_dir, ".."))
devtools::load_all(project_dir, quiet = TRUE)

p <- arg_parser("This script takes the LIFT file and produces a CSV of the example table")
p <- add_argument(p, "LIFT_file",
                  help = "SIL Flex lexicon LIFT file")
argv <- parse_args(p)
table <- example_table(argv$LIFT_file)
if (nrow(table) == 0) {
    cat("")
} else {
    cat(format_csv(table, na = ""))
}
