join_sense_entry <- function(LIFT_file) {
  suppressMessages(library(dplyr))

  sense <- sense_table(LIFT_file)
  entry <- entry_table(LIFT_file)

  left_join(sense, entry, by = "entry_id")
}
