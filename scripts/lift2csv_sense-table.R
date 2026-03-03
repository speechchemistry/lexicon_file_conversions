# lift2csv_sense-table.R
# Extracts <sense> rows from a LIFT file and writes CSV to stdout

library(argparser)

script_path <- normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))]))
script_dir <- dirname(script_path)
project_dir <- normalizePath(file.path(script_dir, ".."))
devtools::load_all(project_dir, quiet = TRUE)

p <- arg_parser("This script takes the LIFT file and produces a CSV of the sense table")
p <- add_argument(p, "LIFT_file",
                  help = "SIL Flex lexicon LIFT file")
argv <- parse_args(p)
cat(lift2csv_sense_table(argv$LIFT_file))
