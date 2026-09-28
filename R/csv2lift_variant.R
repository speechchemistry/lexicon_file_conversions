attach_variants_to_lift <- function(doc, variant_table) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  if (nrow(variant_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)

  col_classes <- classify_variant_columns(names(variant_table))
  form_cols <- filter(col_classes, kind == "form")

  walk(seq_len(nrow(variant_table)), ~{
    row <- variant_table[.x, ]

    entry_node <- xml_find_first(root, sprintf(".//entry[@guid='%s']", row$entry_id))
    if (inherits(entry_node, "xml_missing")) {
      stop(sprintf(
        "Variant row %d references entry_id '%s', which was not found in the entry table",
        .x, row$entry_id
      ), call. = FALSE)
    }

    # Positionally keyed like <example>/<reversal> (SPEC.md's Structural
    # Rules), so <variant> is emitted unconditionally, even for an all-blank
    # row -- dropping one would shift the index of its surviving siblings.
    # This is the ordinary case here, not a hypothetical: sena3.lift has a
    # real variant with no <form> at all (its only content is a morph-type
    # trait, not yet read -- SPEC.md's Not Yet Specified), so an all-blank
    # row still has to round-trip to an (empty) <variant> element rather than
    # vanish.
    variant_node <- xml_add_child(entry_node, "variant")

    form_values <- if (nrow(form_cols) > 0) {
      set_names(as.character(row[form_cols$column]), form_cols$lang)
    } else {
      character()
    }
    add_multitext_children(variant_node, form_values)
  })

  doc
}
