attach_reversals_to_lift <- function(doc, reversal_table) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  if (nrow(reversal_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)

  col_classes <- classify_reversal_columns(names(reversal_table))
  form_cols <- filter(col_classes, kind == "form")

  walk(seq_len(nrow(reversal_table)), ~{
    row <- reversal_table[.x, ]

    sense_node <- xml_find_first(root, sprintf(".//sense[@id='%s']", row$sense_guid))
    if (inherits(sense_node, "xml_missing")) {
      stop(sprintf(
        "Reversal row %d references sense_guid '%s', which was not found in the sense table",
        .x, row$sense_guid
      ), call. = FALSE)
    }

    # Positionally keyed like <example> (SPEC.md's Structural Rules), so
    # <reversal> is emitted unconditionally, even for an all-blank row --
    # dropping one would shift the index of its surviving siblings. No
    # fixture interleaves blank and non-blank reversals on one sense, but
    # this follows the table's own identity model (row order is the only
    # thing carrying it) rather than <pronunciation>'s documented
    # inconsistency, which exists only because no fixture has forced the
    # question there.
    reversal_args <- list(sense_node, "reversal")
    if ("reversal_type" %in% names(row) && has_nonblank(row$reversal_type)) {
      reversal_args$type <- row$reversal_type
    }
    reversal_node <- do.call(xml_add_child, reversal_args)

    form_values <- if (nrow(form_cols) > 0) {
      set_names(as.character(row[form_cols$column]), form_cols$lang)
    } else {
      character()
    }
    add_multitext_children(reversal_node, form_values)
  })

  doc
}
