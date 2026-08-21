# Reversal-level analogue of extract_example_multitext() (R/example_helpers.R):
# <reversal> has no id/guid of its own, so its forms are keyed by the
# reversal's position among all <entry>/<sense>/<reversal> elements, with
# sense_guid carried separately as the surviving foreign key -- the position
# provides row identity, the attribute provides the parent link, mirroring
# the identical example-table split (SPEC.md's Data Handling).
extract_reversal_multitext <- function(reversals, xpath) {
  empty_result <- tibble(
    reversal_index = integer(),
    lang = character(),
    text = character()
  )

  if (length(reversals) == 0) return(empty_result)

  map_df(seq_along(reversals), function(index) {
    forms <- xml_find_all(reversals[[index]], xpath)
    if (length(forms) == 0) return(empty_result)
    map_df(forms, ~tibble(
      reversal_index = index,
      lang = xml_attr(.x, "lang"),
      text = multitext_value(.x)
    ))
  })
}

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
