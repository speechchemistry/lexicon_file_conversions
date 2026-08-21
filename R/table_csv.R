# A column is dropped only when no row holds a non-blank value in it -- NA
# and "" count alike, since na = "" on read and write makes them
# indistinguishable in the CSV anyway (see SPEC.md's Data Handling). A
# zero-row table therefore prunes to zero columns, which format_csv() renders
# as "" -- the empty-table convention falls out of this rule rather than
# needing its own nrow() guard.
drop_empty_columns <- function(table) {
  suppressMessages(library(dplyr))

  dplyr::select(table, dplyr::where(function(col) any(!is.na(col) & nzchar(col))))
}

format_table_csv <- function(table) {
  library(readr)

  readr::format_csv(drop_empty_columns(table), na = "")
}
