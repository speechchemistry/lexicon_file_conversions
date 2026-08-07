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

    # same "omit empty optional elements" rule as citation/note: a row with
    # neither a transcription nor an audio file produces no <pronunciation>
    if (!has_nonblank(form_values) && !has_media) {
      return(invisible(NULL))
    }

    # <form> children before <media>, matching pronunciation's child order in
    # the source LIFT (lift.rng itself interleaves them, so this is a
    # readability convention, as with the entry-level child order)
    pronunciation_node <- xml_add_child(entry_node, "pronunciation")
    add_multitext_children(pronunciation_node, form_values)
    if (has_media) {
      xml_add_child(pronunciation_node, "media", href = row$media_href)
    }
  })

  doc
}
