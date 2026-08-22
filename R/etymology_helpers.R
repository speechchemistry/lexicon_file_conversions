# Etymology-level analogue of extract_pronunciation_multitext() /
# extract_reversal_multitext(): <etymology> has no id/guid of its own, so its
# children are keyed by the etymology's position in the document rather than
# by an attribute. Shared by both <form lang> (the etymon) and <gloss lang>
# (no <form> wrapper, lang lives directly on the element) -- both shapes
# carry `lang` on the node the xpath returns, so one helper covers both.
extract_etymology_multitext <- function(etymologies, xpath) {
  empty_result <- tibble(
    etymology_index = integer(),
    lang = character(),
    text = character()
  )

  if (length(etymologies) == 0) return(empty_result)

  map_df(seq_along(etymologies), function(index) {
    forms <- xml_find_all(etymologies[[index]], xpath)
    if (length(forms) == 0) return(empty_result)
    map_df(forms, ~tibble(
      etymology_index = index,
      lang = xml_attr(.x, "lang"),
      text = multitext_value(.x)
    ))
  })
}

# Etymology-level analogue of extract_multitext_with_attribute(): keyed by
# etymology_index (see above) rather than entry_id, since etymologies, not
# entries, are the node being iterated.
extract_etymology_multitext_with_attribute <- function(etymologies, parent_xpath, attr_name,
                                                         value_col = "text") {
  empty_result <- tibble(
    etymology_index = integer(),
    !!attr_name := character(),
    lang = character(),
    !!value_col := character()
  )

  if (length(etymologies) == 0) return(empty_result)

  map_df(seq_along(etymologies), function(index) {
    parents <- xml_find_all(etymologies[[index]], parent_xpath)
    if (length(parents) == 0) return(empty_result)
    map_df(parents, ~{
      attr_value <- xml_attr(.x, attr_name)
      forms <- xml_find_all(.x, "./form")
      if (length(forms) == 0) return(empty_result)
      map_df(forms, ~tibble(
        etymology_index = index,
        !!attr_name := attr_value,
        lang = xml_attr(.x, "lang"),
        !!value_col := multitext_value(.x)
      ))
    })
  })
}

# Etymology-level analogue of classify_pronunciation_columns(): classifies a
# csv2lift etymology CSV's column names into the shapes etymology_table()
# produces. Unlike pronunciation, etymology-level custom <field>s are read
# and written (comment, languagenotes), so this classifier ends in the same
# last-underscore custom-field fallback as classify_entry_columns()/
# classify_sense_columns() rather than a hard error.
classify_etymology_columns <- function(col_names) {
  meta_columns <- c("entry_id", "etymology_type", "etymology_source")

  map_df(col_names, function(col) {
    if (col %in% meta_columns) {
      cat(sprintf("Classifying column '%s' as metadata\n", col), file = stderr())
      return(tibble(column = col, kind = "meta", field_type = NA_character_, lang = NA_character_))
    }

    if (grepl("^etymology_.+$", col)) {
      lang <- sub("^etymology_", "", col)
      cat(sprintf("Classifying column '%s' as etymology form, lang=%s\n", col, lang),
          file = stderr())
      return(tibble(column = col, kind = "form", field_type = NA_character_, lang = lang))
    }

    if (grepl("^gloss_.+$", col)) {
      lang <- sub("^gloss_", "", col)
      cat(sprintf("Classifying column '%s' as etymology gloss, lang=%s\n", col, lang),
          file = stderr())
      return(tibble(column = col, kind = "gloss", field_type = NA_character_, lang = lang))
    }

    # Custom field: split on the LAST underscore into field type and lang,
    # same known limitation as classify_entry_columns() (a writing system
    # code containing an underscore, or a custom field literally named
    # "etymology" or "gloss", will misclassify here).
    field_type <- sub("_[^_]+$", "", col)
    lang <- sub("^.*_([^_]+)$", "\\1", col)
    cat(sprintf("Classifying column '%s' as field type='%s', lang=%s\n", col, field_type, lang), file = stderr())
    tibble(column = col, kind = "field", field_type = field_type, lang = lang)
  })
}
