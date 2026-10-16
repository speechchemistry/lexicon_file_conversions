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
