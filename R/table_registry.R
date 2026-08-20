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

# A prefix ending in a path separator means "one CSV per table, named after
# the table, inside this folder" (a user's per-export folder); a prefix not
# ending in one means "one CSV per table, named <prefix>_<table>.csv" (the
# flat many-stems-per-directory layout the fixtures use).
is_folder_prefix <- function(prefix) {
  grepl("[/\\\\]$", prefix)
}

table_csv_path <- function(prefix, name) {
  if (is_folder_prefix(prefix)) {
    file.path(prefix, paste0(name, ".csv"))
  } else {
    paste0(prefix, "_", name, ".csv")
  }
}

# Every *.csv in scope for a prefix: the whole folder for a folder prefix,
# or just the files sharing its stem for a flat prefix. Used both to build
# the discovered path list and to catch a CSV whose name matches no
# registered table (a typo'd filename that would otherwise silently drop a
# whole table from the round-trip).
scoped_csvs <- function(prefix) {
  if (is_folder_prefix(prefix)) {
    list.files(prefix, pattern = "\\.csv$", full.names = TRUE)
  } else {
    dir <- dirname(prefix)
    stem <- basename(prefix)
    all_csvs <- list.files(dir, pattern = "\\.csv$", full.names = TRUE)
    all_csvs[startsWith(basename(all_csvs), paste0(stem, "_"))]
  }
}

table_name_from_csv <- function(prefix, path) {
  base <- tools::file_path_sans_ext(basename(path))
  if (is_folder_prefix(prefix)) {
    base
  } else {
    stem <- basename(prefix)
    substring(base, nchar(stem) + 2)
  }
}

# Named list of table name -> CSV path, for every CSV found under `prefix`
# that matches a table in `registry`. Errors on any in-scope CSV that
# matches no registered table, per SPEC.md's Structural rules — a silently
# dropped table is worse than a loud one.
discover_tables <- function(prefix, registry) {
  found <- scoped_csvs(prefix)
  found_names <- vapply(found, function(p) table_name_from_csv(prefix, p), character(1), USE.NAMES = FALSE)

  unknown <- setdiff(found_names, registry$name)
  if (length(unknown) > 0) {
    stop(sprintf(
      "Unrecognised CSV(s) under --tables %s: %s (expected one of: %s)",
      prefix, paste(unknown, collapse = ", "), paste(registry$name, collapse = ", ")
    ), call. = FALSE)
  }

  setNames(as.list(found), found_names)
}
