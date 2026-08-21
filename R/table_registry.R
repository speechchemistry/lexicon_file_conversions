# The single source of truth for which CSV tables csv2lift.R and lift2csv.R
# know about: what each is called, what CLI flag supplies it, how to read it
# from a LIFT file, how to attach it onto a <lift> document, and what
# table(s) must accompany it. See plans/remaining-lift-fields.md's Phase T
# for why this exists. Each table's actual foreign key(s) are documented in
# SPEC.md rather than here -- a registry column can only hold one value per
# table, and C1's traits table needs two (entry_id and sense_guid).
#
# Row order is attach order: entries always comes first (its attach_fn
# creates the document rather than attaching to one, so the incoming `doc`
# argument is ignored), then pronunciations, senses, examples, reversals —
# matching the canonical child order documented in SPEC.md's Entry Table.
# examples comes ahead of reversals to match lift.rng's own declared order
# for sense-content's children; both attach to senses independently, so
# nothing about *correctness* requires that relative order, only readability.
table_registry <- function() {
  library(tibble)

  registry <- tribble(
    ~name,            ~cli_flag,           ~help,
    "entries",        "--entries",         "CSV of the entries table (see SPEC.md's Entry Table; also `lift2csv.R --table entries`)",
    "pronunciations", "--pronunciations",  "CSV of the pronunciations table (see SPEC.md's Pronunciation Table; also `lift2csv.R --table pronunciations`)",
    "senses",         "--senses",          "CSV of the senses table (see SPEC.md's Sense Table; also `lift2csv.R --table senses`)",
    "examples",       "--examples",        "CSV of the examples table (see SPEC.md's Example Table; also `lift2csv.R --table examples`)",
    "reversals",      "--reversals",       "CSV of the reversals table (see SPEC.md's Reversal Table; also `lift2csv.R --table reversals`)"
  )

  registry$read_fn <- list(entry_table, pronunciation_table, sense_table, example_table, reversal_table)
  registry$attach_fn <- list(
    function(doc, table) entry_table_to_lift(table),
    attach_pronunciations_to_lift,
    attach_senses_to_lift,
    attach_examples_to_lift,
    attach_reversals_to_lift
  )
  registry$requires <- list(character(0), character(0), character(0), "senses", "senses")

  registry
}

# --table-dir <dir> names a directory, one CSV per table, named after the
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
      "Unrecognised CSV(s) under --table-dir %s: %s (expected one of: %s)",
      table_dir(dir), paste(unknown, collapse = ", "), paste(registry$name, collapse = ", ")
    ), call. = FALSE)
  }

  setNames(as.list(found), found_names)
}
