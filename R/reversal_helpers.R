# Reversal-level analogue of classify_pronunciation_columns(): classifies a
# csv2lift reversal CSV's column names into the shapes reversal_table()
# produces. Follows the pronunciation/example rule, not the entry/sense one
# -- an unrecognized column is a hard error, with no last-underscore
# custom-field fallback, since reversal-level <field> isn't read or written
# at all (SPEC.md's Not Yet Specified).
classify_reversal_columns <- function(col_names) {
  meta_columns <- c("sense_guid", "reversal_type")

  map_df(col_names, function(col) {
    if (col %in% meta_columns) {
      cat(sprintf("Classifying column '%s' as metadata\n", col), file = stderr())
      return(tibble(column = col, kind = "meta", lang = NA_character_))
    }

    if (grepl("^reversal_.+$", col)) {
      lang <- sub("^reversal_", "", col)
      cat(sprintf("Classifying column '%s' as reversal form, lang=%s\n", col, lang),
          file = stderr())
      return(tibble(column = col, kind = "form", lang = lang))
    }

    stop(sprintf("Unrecognized reversal column '%s'", col), call. = FALSE)
  })
}
