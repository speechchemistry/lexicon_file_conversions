attach_senses_to_lift <- function(doc, sense_table) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  if (nrow(sense_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)

  col_classes <- classify_sense_columns(names(sense_table))
  gloss_cols <- filter(col_classes, kind == "gloss")
  definition_cols <- filter(col_classes, kind == "definition")
  note_cols <- filter(col_classes, kind == "note")
  field_cols <- filter(col_classes, kind == "field")

  walk(seq_len(nrow(sense_table)), ~{
    row <- sense_table[.x, ]

    entry_node <- xml_find_first(root, sprintf(".//entry[@guid='%s']", row$entry_id))
    if (inherits(entry_node, "xml_missing")) {
      stop(sprintf(
        "Sense %s references entry_id '%s', which was not found in the entry table",
        row$sense_guid, row$entry_id
      ), call. = FALSE)
    }

    sense_args <- list(entry_node, "sense")
    if (!is.na(row$sense_guid) && nzchar(row$sense_guid)) {
      sense_args$id <- row$sense_guid
    }
    sense_node <- do.call(xml_add_child, sense_args)

    if (!is.na(row$grammatical_info) && nzchar(row$grammatical_info)) {
      xml_add_child(sense_node, "grammatical-info", value = row$grammatical_info)
    }

    if (nrow(gloss_cols) > 0) {
      gloss_values <- set_names(as.character(row[gloss_cols$column]), gloss_cols$lang)
      add_multitext_children(sense_node, gloss_values, tag = "gloss")
    }

    if (nrow(definition_cols) > 0) {
      definition_values <- set_names(as.character(row[definition_cols$column]), definition_cols$lang)
      if (has_nonblank(definition_values)) {
        definition_node <- xml_add_child(sense_node, "definition")
        add_multitext_children(definition_node, definition_values)
      }
    }

    if (nrow(note_cols) > 0) {
      note_values <- set_names(as.character(row[note_cols$column]), note_cols$lang)
      if (has_nonblank(note_values)) {
        note_node <- xml_add_child(sense_node, "note")
        add_multitext_children(note_node, note_values)
      }
    }

    if (nrow(field_cols) > 0) {
      walk(unique(field_cols$field_type), ~{
        type_cols <- field_cols[field_cols$field_type == .x, ]
        field_values <- set_names(as.character(row[type_cols$column]), type_cols$lang)
        if (has_nonblank(field_values)) {
          field_node <- xml_add_child(sense_node, "field", type = .x)
          add_multitext_children(field_node, field_values)
        }
      })
    }
  })

  doc
}
