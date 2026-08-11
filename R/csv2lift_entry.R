entry_table_to_lift <- function(entry_table) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))
  library(tibble)

  doc <- xml_new_document()
  root <- xml_add_child(doc, "lift", version = "0.13", producer = "lexicon_file_conversions csv2lift")

  if (nrow(entry_table) == 0) {
    return(doc)
  }

  col_classes <- classify_entry_columns(names(entry_table))

  lexical_unit_cols <- filter(col_classes, kind == "lexical_unit")
  citation_cols <- filter(col_classes, kind == "citation")
  note_cols <- filter(col_classes, kind == "note")
  typed_note_cols <- filter(col_classes, kind == "typed_note")
  field_cols <- filter(col_classes, kind == "field")

  walk(seq_len(nrow(entry_table)), ~{
    row <- entry_table[.x, ]

    entry_args <- list(root, "entry")
    if ("dateCreated" %in% names(row) && !is.na(row$dateCreated) && nzchar(row$dateCreated)) {
      entry_args$dateCreated <- row$dateCreated
    }
    if ("dateModified" %in% names(row) && !is.na(row$dateModified) && nzchar(row$dateModified)) {
      entry_args$dateModified <- row$dateModified
    }
    if ("entry_id" %in% names(row) && !is.na(row$entry_id) && nzchar(row$entry_id)) {
      entry_args$guid <- row$entry_id
    }
    entry <- do.call(xml_add_child, entry_args)

    if (nrow(lexical_unit_cols) > 0) {
      lex_values <- set_names(as.character(row[lexical_unit_cols$column]), lexical_unit_cols$lang)
      if (has_nonblank(lex_values)) {
        lex_node <- xml_add_child(entry, "lexical-unit")
        add_multitext_children(lex_node, lex_values)
      }
    }

    if ("morph_type" %in% names(row) && !is.na(row$morph_type) && nzchar(row$morph_type)) {
      xml_add_child(entry, "trait", name = "morph-type", value = row$morph_type)
    }

    if (nrow(citation_cols) > 0) {
      citation_values <- set_names(as.character(row[citation_cols$column]), citation_cols$lang)
      if (has_nonblank(citation_values)) {
        citation_node <- xml_add_child(entry, "citation")
        add_multitext_children(citation_node, citation_values)
      }
    }

    if (nrow(note_cols) > 0) {
      note_values <- set_names(as.character(row[note_cols$column]), note_cols$lang)
      if (has_nonblank(note_values)) {
        note_node <- xml_add_child(entry, "note")
        add_multitext_children(note_node, note_values)
      }
    }

    if (nrow(typed_note_cols) > 0) {
      emit_typed_children(entry, typed_note_cols, row, "note")
    }

    if (nrow(field_cols) > 0) {
      emit_typed_children(entry, field_cols, row, "field")
    }
  })

  doc
}
