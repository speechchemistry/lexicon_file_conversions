# The single source of truth for which CSV tables csv2lift.R and lift2csv.R
# know about: what each is called, what CLI flag supplies it, how to read it
# from a LIFT file, how to attach it onto a <lift> document, what table(s)
# must accompany it, and which column is its foreign key. See plans/
# remaining-lift-fields.md's Phase T for why this exists.
#
# Row order is attach order: entries always comes first (its attach_fn
# creates the document rather than attaching to one, so the incoming `doc`
# argument is ignored), then pronunciations, senses, examples — matching the
# canonical child order documented in SPEC.md's Entry Table.
table_registry <- function() {
  library(tibble)

  registry <- tribble(
    ~name,            ~cli_flag,           ~help,
    "entries",        "--entries",         "CSV matching lift2csv_entry-table.R's column conventions",
    "pronunciations", "--pronunciations",  "CSV matching lift2csv_pronunciation-table.R's column conventions",
    "senses",         "--senses",          "CSV matching lift2csv_sense-table.R's column conventions",
    "examples",       "--examples",        "CSV matching lift2csv_example-table.R's column conventions"
  )

  registry$read_fn <- list(entry_table, pronunciation_table, sense_table, example_table)
  registry$attach_fn <- list(
    function(doc, table) entry_table_to_lift(table),
    attach_pronunciations_to_lift,
    attach_senses_to_lift,
    attach_examples_to_lift
  )
  registry$fk <- c(NA_character_, "entry_id", "entry_id", "sense_guid")
  registry$requires <- list(character(0), character(0), character(0), "senses")
  registry$creates_doc <- c(TRUE, FALSE, FALSE, FALSE)

  registry
}

# --tables <dir> names a directory, one CSV per table, named after the
# table (entries.csv, senses.csv, ...). A trailing slash is tolerated but
# not required or significant — normalized away so a path built from it
# (e.g. in an error message) never shows a doubled slash.
table_dir <- function(dir) {
  sub("/+$", "", dir)
}

table_csv_path <- function(dir, name) {
  file.path(table_dir(dir), paste0(name, ".csv"))
}

# Every *.csv directly inside `dir`. Used both to build the discovered path
# list and to catch a CSV whose name matches no registered table (a typo'd
# filename that would otherwise silently drop a whole table from the round
# trip).
scoped_csvs <- function(dir) {
  list.files(table_dir(dir), pattern = "\\.csv$", full.names = TRUE)
}

# Named list of table name -> CSV path, for every CSV found in `dir` that
# matches a table in `registry`. Errors on any CSV that matches no
# registered table, per SPEC.md's Structural rules — a silently dropped
# table is worse than a loud one.
discover_tables <- function(dir, registry) {
  found <- scoped_csvs(dir)
  found_names <- tools::file_path_sans_ext(basename(found))

  unknown <- setdiff(found_names, registry$name)
  if (length(unknown) > 0) {
    stop(sprintf(
      "Unrecognised CSV(s) under --tables %s: %s (expected one of: %s)",
      table_dir(dir), paste(unknown, collapse = ", "), paste(registry$name, collapse = ", ")
    ), call. = FALSE)
  }

  setNames(as.list(found), found_names)
}
