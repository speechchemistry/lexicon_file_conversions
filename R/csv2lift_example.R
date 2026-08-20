attach_examples_to_lift <- function(doc, example_table) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  if (nrow(example_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)

  col_classes <- classify_example_columns(names(example_table))
  form_cols <- filter(col_classes, kind == "form")
  translation_form_cols <- filter(col_classes, kind == "translation_form")
  note_cols <- filter(col_classes, kind == "typed_note")

  walk(seq_len(nrow(example_table)), ~{
    row <- example_table[.x, ]

    sense_node <- xml_find_first(root, sprintf(".//sense[@id='%s']", row$sense_guid))
    if (inherits(sense_node, "xml_missing")) {
      stop(sprintf(
        "Example row %d references sense_guid '%s', which was not found in the sense table",
        .x, row$sense_guid
      ), call. = FALSE)
    }

    warn_on_reference_disagreement(row, note_cols, .x)

    # Unlike every other optional element in this model, <example> is
    # emitted unconditionally: identity here is purely positional (SPEC.md
    # 6), so dropping a blank row would shift the index of its surviving
    # siblings — six senses in Sena3.lift interleave blank and non-blank
    # examples.
    example_args <- list(sense_node, "example")
    if ("example_source" %in% names(row) && has_nonblank(row$example_source)) {
      example_args$source <- row$example_source
    }
    example_node <- do.call(xml_add_child, example_args)

    if (nrow(form_cols) > 0) {
      form_values <- set_names(as.character(row[form_cols$column]), form_cols$lang)
      add_multitext_children(example_node, form_values)
    }

    # <translation> is emitted when there's a type OR any text — not gated on
    # has_nonblank(type) alone, since one of the 18 in Sena3.lift has a type
    # but no text, and losing that type would be a silent regression from
    # what example_table() extracted.
    translation_type <- if ("translation_type" %in% names(row)) row$translation_type else NA_character_
    translation_values <- if (nrow(translation_form_cols) > 0) {
      set_names(as.character(row[translation_form_cols$column]), translation_form_cols$lang)
    } else {
      character()
    }
    has_translation_type <- !is.na(translation_type) && nzchar(translation_type)
    if (has_translation_type || has_nonblank(translation_values)) {
      translation_args <- list(example_node, "translation")
      if (has_translation_type) translation_args$type <- translation_type
      translation_node <- do.call(xml_add_child, translation_args)
      add_multitext_children(translation_node, translation_values)
    }

    if (nrow(note_cols) > 0) {
      emit_typed_children(example_node, note_cols, row, "note")
    }
  })

  doc
}
