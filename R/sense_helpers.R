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
        !!value_col := multitext_value(.x)
      ))
    })
}

# Sense-level analogue of extract_multitext_with_attribute() in
# entry_helpers.R. Keyed by sense/@id since senses, not entries, are the
# node being iterated.
extract_sense_multitext_with_attribute <- function(senses, parent_xpath, attr_name,
                                                    value_col = "text") {
  empty_result <- tibble(
    sense_guid = character(),
    !!attr_name := character(),
    lang = character(),
    !!value_col := character()
  )

  if (length(senses) == 0) return(empty_result)

  senses |>
    map_df(~{
      sense_guid <- xml_attr(.x, "id")
      parents <- xml_find_all(.x, parent_xpath)
      if (length(parents) == 0) return(empty_result)
      map_df(parents, ~{
        attr_value <- xml_attr(.x, attr_name)
        forms <- xml_find_all(.x, "./form")
        if (length(forms) == 0) return(empty_result)
        map_df(forms, ~tibble(
          sense_guid = sense_guid,
          !!attr_name := attr_value,
          lang = xml_attr(.x, "lang"),
          !!value_col := multitext_value(.x)
        ))
      })
    })
}

# Sense-level analogue of classify_entry_columns(): classifies a csv2lift
# sense CSV's column names into the shapes sense_table() produces, so
# csv2lift can rebuild the right LIFT element for each column.
classify_sense_columns <- function(col_names) {
  meta_columns <- c("sense_guid", "entry_id", "sense_order", "grammatical_info")

  map_df(col_names, function(col) {
    if (col %in% meta_columns) {
      cat(sprintf("Classifying column '%s' as metadata\n", col), file = stderr())
      return(tibble(column = col, kind = "meta", field_type = NA_character_, lang = NA_character_))
    }

    if (grepl("^gloss_.+$", col)) {
      lang <- sub("^gloss_", "", col)
      cat(sprintf("Classifying column '%s' as gloss, lang=%s\n", col, lang), file = stderr())
      return(tibble(column = col, kind = "gloss", field_type = NA_character_, lang = lang))
    }

    if (grepl("^definition_.+$", col)) {
      lang <- sub("^definition_", "", col)
      cat(sprintf("Classifying column '%s' as definition, lang=%s\n", col, lang), file = stderr())
      return(tibble(column = col, kind = "definition", field_type = NA_character_, lang = lang))
    }

    if (grepl("^general_note_.+$", col)) {
      lang <- sub("^general_note_", "", col)
      cat(sprintf("Classifying column '%s' as note, lang=%s\n", col, lang), file = stderr())
      return(tibble(column = col, kind = "note", field_type = NA_character_, lang = lang))
    }

    # Custom field: split on the LAST underscore into field type and lang,
    # same known limitation as classify_entry_columns() (a writing system
    # code containing an underscore, or a custom field literally named
    # "gloss"/"definition"/"general_note", will misclassify here).
    field_type <- sub("_[^_]+$", "", col)
    lang <- sub("^.*_([^_]+)$", "\\1", col)
    cat(sprintf("Classifying column '%s' as field type='%s', lang=%s\n", col, field_type, lang), file = stderr())
    tibble(column = col, kind = "field", field_type = field_type, lang = lang)
  })
}
