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
  typed_note_cols <- filter(col_classes, kind == "typed_note")
  field_cols <- filter(col_classes, kind == "field")

  # A row is a subsense's when parent_sense_guid is non-blank -- a column a
  # sense CSV written before D1 existed omits entirely, same column-absence
  # guard as sense_order below. Computed once, vectorised over the whole
  # column, rather than per row.
  parent_sense_guid_col <- if ("parent_sense_guid" %in% names(sense_table)) {
    sense_table$parent_sense_guid
  } else {
    rep(NA_character_, nrow(sense_table))
  }
  is_subsense_row <- !is.na(parent_sense_guid_col) & nzchar(parent_sense_guid_col)

  walk(seq_len(nrow(sense_table)), ~{
    row <- sense_table[.x, ]

    entry_node <- xml_find_first(root, sprintf(".//entry[@guid='%s']", row$entry_id))
    if (inherits(entry_node, "xml_missing")) {
      stop(sprintf(
        "Sense %s references entry_id '%s', which was not found in the entry table",
        row$sense_guid, row$entry_id
      ), call. = FALSE)
    }

    # <subsense> reuses sense-content verbatim (SPEC.md's Sense Table), so
    # its own child emission below is identical either way -- only the
    # attach point and tag name differ. Attached to whichever sense/subsense
    # node has this row's parent_sense_guid as its own @id, rather than to
    # entry_node directly. This relies on the table's own row order putting
    # a parent's row before its subsense's (extract_sense_metadata()'s
    # depth-first read order guarantees it for reader output; a
    # hand-reordered CSV that violates it fails fast below, same as any
    # other unmatched FK).
    parent_node <- if (is_subsense_row[.x]) {
      node <- xml_find_first(root, sprintf(".//*[self::sense or self::subsense][@id='%s']", row$parent_sense_guid))
      if (inherits(node, "xml_missing")) {
        stop(sprintf(
          "Sense %s references parent_sense_guid '%s', which was not found in the sense table",
          row$sense_guid, row$parent_sense_guid
        ), call. = FALSE)
      }
      node
    } else {
      entry_node
    }

    sense_args <- list(parent_node, if (is_subsense_row[.x]) "subsense" else "sense")
    if (!is.na(row$sense_guid) && nzchar(row$sense_guid)) {
      sense_args$id <- row$sense_guid
    }
    # Guarded on the column existing, not just being non-blank: a sense CSV
    # written before sense_order existed omits it entirely, and must still
    # convert. Mirrors entry_table_to_lift()'s dateCreated/dateModified guard.
    if ("sense_order" %in% names(row) && !is.na(row$sense_order) && nzchar(row$sense_order)) {
      sense_args$order <- row$sense_order
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

    if (nrow(typed_note_cols) > 0) {
      emit_typed_children(sense_node, typed_note_cols, row, "note")
    }

    if (nrow(field_cols) > 0) {
      emit_typed_children(sense_node, field_cols, row, "field")
    }
  })

  doc
}
