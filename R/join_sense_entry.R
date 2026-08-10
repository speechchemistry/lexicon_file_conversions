join_sense_entry <- function(LIFT_file) {
  suppressMessages(library(dplyr))

  sense <- sense_table(LIFT_file)
  entry <- entry_table(LIFT_file)

  # Sense- and entry-level columns can now share a name (e.g. note_en, or a
  # custom field present at both levels) since both tables draw from the
  # same reserved-prefix scheme. Disambiguate explicitly rather than
  # accepting dplyr's default .x/.y suffixes.
  left_join(sense, entry, by = "entry_id", suffix = c("_sense", "_entry"))
}
