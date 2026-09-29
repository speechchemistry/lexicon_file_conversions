attach_pronunciations_to_lift <- function(doc, pronunciation_table) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  if (nrow(pronunciation_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)

  col_classes <- classify_pronunciation_columns(names(pronunciation_table))
  form_cols <- filter(col_classes, kind == "form")
  media_label_cols <- filter(col_classes, kind == "media_label")
  field_cols <- filter(col_classes, kind == "field")

  walk(seq_len(nrow(pronunciation_table)), ~{
    row <- pronunciation_table[.x, ]

    entry_node <- xml_find_first(root, sprintf(".//entry[@guid='%s']", row$entry_id))
    if (inherits(entry_node, "xml_missing")) {
      stop(sprintf(
        "Pronunciation row %d references entry_id '%s', which was not found in the entry table",
        .x, row$entry_id
      ), call. = FALSE)
    }

    form_values <- if (nrow(form_cols) > 0) {
      set_names(as.character(row[form_cols$column]), form_cols$lang)
    } else {
      character()
    }
    has_media <- "media_href" %in% names(row) &&
      !is.na(row$media_href) && nzchar(row$media_href)
    field_values <- if (nrow(field_cols) > 0) as.character(row[field_cols$column]) else character()
    location_value <- if ("location" %in% names(row)) row$location else NA_character_

    # same "omit empty optional elements" rule as citation/note: a row with
    # no transcription, audio file, custom field, or trait produces no
    # <pronunciation> at all
    if (!has_nonblank(form_values) && !has_media && !has_nonblank(field_values) &&
        !has_nonblank(location_value)) {
      return(invisible(NULL))
    }

    # Child order -- <form>, then <media> (with its own optional <label>),
    # then <field>, then <trait> -- matches every real occurrence seen
    # (lift.rng itself interleaves all of these, so this is a readability
    # convention, as with the entry-level child order)
    pronunciation_node <- xml_add_child(entry_node, "pronunciation")
    add_multitext_children(pronunciation_node, form_values)
    if (has_media) {
      media_node <- xml_add_child(pronunciation_node, "media", href = row$media_href)
      if (nrow(media_label_cols) > 0) {
        label_values <- set_names(as.character(row[media_label_cols$column]), media_label_cols$lang)
        if (has_nonblank(label_values)) {
          label_node <- xml_add_child(media_node, "label")
          add_multitext_children(label_node, label_values)
        }
      }
    }
    if (nrow(field_cols) > 0) {
      emit_typed_children(pronunciation_node, field_cols, row, "field")
    }
    if (has_nonblank(location_value)) {
      xml_add_child(pronunciation_node, "trait", name = "location", value = row$location)
    }
  })

  doc
}
