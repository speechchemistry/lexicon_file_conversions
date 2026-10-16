# The single source of truth for which CSV tables csv2lift.R and lift2csv.R
# know about: what each is called, what CLI flag supplies it, how to read it
# from a LIFT file, how to attach it onto a <lift> document, and what
# table(s) must accompany it. See plans/remaining-lift-fields.md's Phase T
# for why this exists. Each table's actual foreign key(s) are documented in
# SPEC.md rather than here -- a registry column can only hold one value per
# table, and the traits table needs two (entry_id and sense_guid).
#
# Row order is attach order. Three orderings are load-bearing: entries comes
# first (its attach_fn creates the document, so the incoming `doc` argument
# is ignored); every table that attaches to a sense comes after senses (the
# `requires` column enforces that the senses table is supplied); and traits
# comes last, because its rows attach into <variant>, <relation> and
# <grammatical-info> elements other passes create. Every other position just
# follows lift.rng's declared child order, for readability (SPEC.md's Entry
# Table and Sense Table).
table_registry <- function() {
  registry <- tribble(
    ~name,              ~cli_flag,             ~help,
    "entries",          "--entries",           "CSV of the entries table (see SPEC.md's Entry Table; also `lift2csv.R --table entries`)",
    "pronunciations",   "--pronunciations",    "CSV of the pronunciations table (see SPEC.md's Pronunciation Table; also `lift2csv.R --table pronunciations`)",
    "variants",         "--variants",          "CSV of the variants table (see SPEC.md's Variant Table; also `lift2csv.R --table variants`)",
    "senses",           "--senses",            "CSV of the senses table (see SPEC.md's Sense Table; also `lift2csv.R --table senses`)",
    "sense-relations",  "--sense-relations",   "CSV of the sense-relations table (see SPEC.md's Sense-Relation Table; also `lift2csv.R --table sense-relations`)",
    "examples",         "--examples",          "CSV of the examples table (see SPEC.md's Example Table; also `lift2csv.R --table examples`)",
    "reversals",        "--reversals",         "CSV of the reversals table (see SPEC.md's Reversal Table; also `lift2csv.R --table reversals`)",
    "entry-relations",  "--entry-relations",   "CSV of the entry-relations table (see SPEC.md's Entry-Relation Table; also `lift2csv.R --table entry-relations`)",
    "etymologies",      "--etymologies",       "CSV of the etymologies table (see SPEC.md's Etymology Table; also `lift2csv.R --table etymologies`)",
    "traits",           "--traits",            "CSV of the traits table (see SPEC.md's Traits Table; also `lift2csv.R --table traits`)"
  )

  registry$read_fn <- list(
    entry_table, pronunciation_table, variant_table, sense_table, sense_relation_table,
    example_table, reversal_table, entry_relation_table, etymology_table, trait_table
  )
  registry$attach_fn <- list(
    function(doc, table) entry_table_to_lift(table),
    attach_pronunciations_to_lift,
    attach_variants_to_lift,
    attach_senses_to_lift,
    attach_sense_relations_to_lift,
    attach_examples_to_lift,
    attach_reversals_to_lift,
    attach_entry_relations_to_lift,
    attach_etymologies_to_lift,
    attach_traits_to_lift
  )
  registry$requires <- list(
    character(0), character(0), character(0), character(0), "senses",
    "senses", "senses", character(0), character(0), "senses"
  )

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
