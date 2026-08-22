attach_etymologies_to_lift <- function(doc, etymology_table) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  if (nrow(etymology_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)

  col_classes <- classify_etymology_columns(names(etymology_table))
  form_cols <- filter(col_classes, kind == "form")
  gloss_cols <- filter(col_classes, kind == "gloss")
  field_cols <- filter(col_classes, kind == "field")

  walk(seq_len(nrow(etymology_table)), ~{
    row <- etymology_table[.x, ]

    entry_node <- xml_find_first(root, sprintf(".//entry[@guid='%s']", row$entry_id))
    if (inherits(entry_node, "xml_missing")) {
      stop(sprintf(
        "Etymology row %d references entry_id '%s', which was not found in the entry table",
        .x, row$entry_id
      ), call. = FALSE)
    }

    # @type and @source are both required by etymology-content (lift.rng has
    # no <optional> around either attribute), unlike every other attribute
    # this codebase emits conditionally -- so both are always written, even
    # as an empty string, rather than omitted when blank. Guarded on column
    # presence, not just blankness: @source is "" on every etymology in every
    # fixture, so drop_empty_columns() (R/table_csv.R) removes
    # etymology_source from lift2csv's own output entirely -- this is the
    # ordinary path, not a legacy-CSV edge case, mirroring entry_order's
    # identical column-absence guard (SPEC.md's Entry Table).
    etymology_type <- if ("etymology_type" %in% names(row) && !is.na(row$etymology_type)) row$etymology_type else ""
    etymology_source <- if ("etymology_source" %in% names(row) && !is.na(row$etymology_source)) row$etymology_source else ""

    # Positionally keyed like <example>/<reversal> (SPEC.md's Structural
    # Rules), so <etymology> is emitted unconditionally, even for an
    # all-blank row -- dropping one would shift the index of its surviving
    # siblings. This is not a hypothetical: 48 of 105 etymologies in
    # sena3.lift carry no <form> at all (the etymon is only ever recorded in
    # the "comment" custom field for those), so a row with blank
    # etymology_<lang>/gloss_<lang> columns is the common case, not an edge
    # case reached only by extrapolation.
    etymology_node <- xml_add_child(entry_node, "etymology", type = etymology_type, source = etymology_source)

    # Child order -- <form>, then <gloss>, then <field> -- matches the
    # source's own child order in every shape observed (unlike lift.rng's
    # own declared order for etymology-content, which lists extensible-
    # content/field first).
    form_values <- if (nrow(form_cols) > 0) {
      set_names(as.character(row[form_cols$column]), form_cols$lang)
    } else {
      character()
    }
    add_multitext_children(etymology_node, form_values)

    if (nrow(gloss_cols) > 0) {
      gloss_values <- set_names(as.character(row[gloss_cols$column]), gloss_cols$lang)
      add_multitext_children(etymology_node, gloss_values, tag = "gloss")
    }

    if (nrow(field_cols) > 0) {
      emit_typed_children(etymology_node, field_cols, row, "field")
    }
  })

  doc
}
