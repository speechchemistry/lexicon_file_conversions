# Classify a csv2lift entries CSV's column names into the shapes
# entry_table() produces, so csv2lift can rebuild
# the right LIFT element for each column without re-deriving column-naming
# rules elsewhere.
classify_entry_columns <- function(col_names) {
  meta_columns <- c("entry_id", "entry_lift_id", "dateCreated", "dateModified", "entry_order", "morph_type")

  map_df(col_names, function(col) {
    if (col %in% meta_columns) {
      cat(sprintf("Classifying column '%s' as metadata\n", col), file = stderr())
      return(tibble(column = col, kind = "meta", field_type = NA_character_, lang = NA_character_))
    }

    if (grepl("^citation_.+$", col)) {
      lang <- sub("^citation_", "", col)
      cat(sprintf("Classifying column '%s' as citation, lang=%s\n", col, lang), file = stderr())
      return(tibble(column = col, kind = "citation", field_type = NA_character_, lang = lang))
    }

    # Typed notes are type-keyed exactly like custom <field>s: note_<type>_<lang>, split on the LAST
    # underscore. This pattern requires a second underscore after the prefix so it can never swallow an
    # untyped note_<lang> column — but it must still precede the untyped branch below, which would
    # otherwise match first and read the type as part of the writing system.
    if (grepl("^note_.+_[^_]+$", col)) {
      note_type <- sub("^note_(.+)_[^_]+$", "\\1", col)
      lang <- sub("^note_.+_([^_]+)$", "\\1", col)
      cat(sprintf("Classifying column '%s' as typed note type='%s', lang=%s\n",
                  col, note_type, lang), file = stderr())
      return(tibble(column = col, kind = "typed_note", field_type = note_type, lang = lang))
    }

    if (grepl("^note_.+$", col)) {
      lang <- sub("^note_", "", col)
      cat(sprintf("Classifying column '%s' as note, lang=%s\n", col, lang), file = stderr())
      return(tibble(column = col, kind = "note", field_type = NA_character_, lang = lang))
    }

    if (!grepl("_", col, fixed = TRUE)) {
      cat(sprintf("Classifying column '%s' as lexical-unit, lang=%s\n", col, col), file = stderr())
      return(tibble(column = col, kind = "lexical_unit", field_type = NA_character_, lang = col))
    }

    # Custom field: split on the LAST underscore into field type and lang.
    # Known limitation, accepted rather than solved generally: a writing
    # system code containing an underscore, or a custom field literally
    # named "citation" or "note", will misclassify here — and so will one
    # whose type_lang split happens to spell "entry_lift_id" exactly (or
    # any other meta_columns name above).
    field_type <- sub("_[^_]+$", "", col)
    lang <- sub("^.*_([^_]+)$", "\\1", col)
    cat(sprintf("Classifying column '%s' as field type='%s', lang=%s\n", col, field_type, lang), file = stderr())
    tibble(column = col, kind = "field", field_type = field_type, lang = lang)
  })
}
