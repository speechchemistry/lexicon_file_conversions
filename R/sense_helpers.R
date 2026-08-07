# Sense-level analogue of extract_multitext_element() in entry_helpers.R.
# Keyed by sense/@id (not entry/@guid) since senses, not entries, are the
# node being iterated.
extract_sense_multitext_element <- function(senses, xpath, value_col = "text") {
  empty_result <- tibble(
    sense_guid = character(),
    lang = character(),
    !!value_col := character()
  )

  if (length(senses) == 0) return(empty_result)

  senses |>
    map_df(~{
      sense_guid <- xml_attr(.x, "id")
      forms <- xml_find_all(.x, xpath)
      if (length(forms) == 0) return(empty_result)
      map_df(forms, ~tibble(
        sense_guid = sense_guid,
        lang = xml_attr(.x, "lang"),
        !!value_col := xml_text(.x)
      ))
    })
}

# Sense-level analogue of classify_entry_columns(): classifies a csv2lift
# sense CSV's column names into the shapes sense_table() produces, so
# csv2lift can rebuild the right LIFT element for each column. Unlike entry
# columns, there is no dynamic custom-field fallback here yet — an
# unrecognized column is a hard error rather than being silently
# misclassified, since sense-level custom fields aren't read/written at all.
classify_sense_columns <- function(col_names) {
  meta_columns <- c("sense_guid", "entry_id", "grammatical_info")

  map_df(col_names, function(col) {
    if (col %in% meta_columns) {
      cat(sprintf("Classifying column '%s' as metadata\n", col), file = stderr())
      return(tibble(column = col, kind = "meta", lang = NA_character_))
    }

    if (grepl("^gloss_.+$", col)) {
      lang <- sub("^gloss_", "", col)
      cat(sprintf("Classifying column '%s' as gloss, lang=%s\n", col, lang), file = stderr())
      return(tibble(column = col, kind = "gloss", lang = lang))
    }

    if (grepl("^definition_.+$", col)) {
      lang <- sub("^definition_", "", col)
      cat(sprintf("Classifying column '%s' as definition, lang=%s\n", col, lang), file = stderr())
      return(tibble(column = col, kind = "definition", lang = lang))
    }

    stop(sprintf("Unrecognized sense column '%s'", col), call. = FALSE)
  })
}
