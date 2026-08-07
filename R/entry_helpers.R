extract_multitext_element <- function(entries, xpath, value_col = "text") {
  empty_result <- tibble(
    entry_id = character(),
    lang = character(),
    !!value_col := character()
  )

  if(length(entries) == 0) return(empty_result)

  entries |>
    map_df(~{
      entry_id <- xml_attr(.x, "guid")
      forms <- xml_find_all(.x, xpath)
      if(length(forms) == 0) return(empty_result)
      map_df(forms, ~tibble(
        entry_id = entry_id,
        lang = xml_attr(.x, "lang"),
        !!value_col := xml_text(.x)
      ))
    })
}

extract_single_trait <- function(entries, trait_name) {
  map_chr(entries, ~{
    entry_id <- xml_attr(.x, "guid")
    traits <- xml_find_all(.x, sprintf("./trait[@name='%s']", trait_name))
    if (length(traits) == 0) return(NA_character_)
    values <- xml_attr(traits, "value")
    # LIFT allows only one trait of a given name per entry; if source data
    # violates that, warn (goes to stderr) rather than silently dropping data.
    if (length(values) > 1) {
      warning(sprintf(
        "Entry %s has %d '%s' traits (%s); using first value.",
        entry_id, length(values), trait_name, paste(values, collapse = ", ")
      ))
    }
    values[1]
  })
}

extract_multitext_with_attribute <- function(entries, parent_xpath, attr_name,
                                             value_col = "text") {
  empty_result <- tibble(
    entry_id = character(),
    !!attr_name := character(),
    lang = character(),
    !!value_col := character()
  )

  if(length(entries) == 0) return(empty_result)

  entries |>
    map_df(~{
      entry_id <- xml_attr(.x, "guid")
      parents <- xml_find_all(.x, parent_xpath)
      if(length(parents) == 0) return(empty_result)
      map_df(parents, ~{
        attr_value <- xml_attr(.x, attr_name)
        forms <- xml_find_all(.x, "./form")
        if(length(forms) == 0) return(empty_result)
        map_df(forms, ~tibble(
          entry_id = entry_id,
          !!attr_name := attr_value,
          lang = xml_attr(.x, "lang"),
          !!value_col := xml_text(.x)
        ))
      })
    })
}

# Inverse of the extractors above: classify a csv2lift input CSV's column
# names into the four shapes entry_table() produces, so csv2lift can rebuild
# the right LIFT element for each column without re-deriving column-naming
# rules elsewhere.
classify_entry_columns <- function(col_names) {
  meta_columns <- c("entry_id", "dateCreated", "dateModified", "morph_type")

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
    # named "citation" or "note", will misclassify here.
    field_type <- sub("_[^_]+$", "", col)
    lang <- sub("^.*_([^_]+)$", "\\1", col)
    cat(sprintf("Classifying column '%s' as field type='%s', lang=%s\n", col, field_type, lang), file = stderr())
    tibble(column = col, kind = "field", field_type = field_type, lang = lang)
  })
}

# Inverse of the multitext-reading helpers: adds one <form lang><text> child
# per non-blank entry in a named vector (name = lang, value = text). Shared
# by lexical-unit, citation, and each custom field's <field> element.
add_multitext_children <- function(parent_node, lang_values) {
  for (lang in names(lang_values)) {
    text <- lang_values[[lang]]
    if (is.na(text) || !nzchar(text)) next
    form_node <- xml_add_child(parent_node, "form", lang = lang)
    text_node <- xml_add_child(form_node, "text")
    xml_text(text_node) <- text
  }
}