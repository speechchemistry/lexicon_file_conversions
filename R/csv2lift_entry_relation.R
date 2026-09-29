attach_entry_relations_to_lift <- function(doc, entry_relation_table) {
  library(xml2)
  library(purrr)

  if (nrow(entry_relation_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)

  walk(seq_len(nrow(entry_relation_table)), ~{
    row <- entry_relation_table[.x, ]

    entry_node <- xml_find_first(root, sprintf(".//entry[@guid='%s']", row$entry_id))
    if (inherits(entry_node, "xml_missing")) {
      stop(sprintf(
        "Entry-relation row %d references entry_id '%s', which was not found in the entry table",
        .x, row$entry_id
      ), call. = FALSE)
    }

    # relation/@ref targets the other entry's @id (SPEC.md's Entry Table),
    # not its @guid, so relation_ref -- a guid, like every other FK in this
    # tool -- has to be translated back the other way here: look the target
    # entry up by guid, then read the @id it was written with.
    #
    # A blank relation_ref is real FLEx data, not a lookup failure: FLEx
    # itself exports <relation ref=""/> for a dangling _component-lexeme
    # relation (its target since deleted). lift2csv already keeps such a
    # row rather than dropping it (warns, leaves relation_ref blank), so
    # this mirrors that choice here -- written back verbatim, with a
    # warning -- rather than treating "no ref at all" the same as "a ref
    # that resolves to nothing" (the stop() below). The column can be
    # absent entirely, not just NA in an present column: when every
    # relation_ref in the table is blank, drop_empty_columns() (Data
    # Handling) removes the column before csv2lift ever sees it.
    if (!("relation_ref" %in% names(row)) || !has_nonblank(row$relation_ref)) {
      warning(sprintf(
        "Entry-relation row %d (entry_id '%s') has a blank relation_ref -- writing <relation ref=\"\"> unchanged, matching the source",
        .x, row$entry_id
      ), call. = FALSE)
      target_id <- ""
    } else {
      target_node <- xml_find_first(root, sprintf(".//entry[@guid='%s']", row$relation_ref))
      if (inherits(target_node, "xml_missing")) {
        stop(sprintf(
          "Entry-relation row %d references relation_ref '%s', which was not found in the entry table",
          .x, row$relation_ref
        ), call. = FALSE)
      }
      target_id <- xml_attr(target_node, "id")
      if (is.na(target_id) || !nzchar(target_id)) {
        stop(sprintf(
          "Entry-relation row %d's relation_ref '%s' names an entry with no entry_lift_id -- relation/@ref requires a target id to write",
          .x, row$relation_ref
        ), call. = FALSE)
      }
    }

    # relation-content requires both @type and @ref (no <optional> wrapper),
    # the same required-attribute shape as <etymology>'s @type/@source
    # (R/csv2lift_etymology.R) -- both always emitted, even as "", unlike an
    # ordinary optional attribute.
    relation_node <- xml_add_child(
      entry_node, "relation",
      type = if (has_nonblank(row$relation_type)) row$relation_type else "",
      ref = target_id
    )

    # @order is genuinely optional (schema-wise) and, in sena3.lift, only
    # ever present on _component-lexeme relations -- absent entirely from
    # lift2csv's own output whenever no relation in the source carries it
    # (Data Handling's empty-column rule), so the column-absence guard here
    # is load-bearing on that ordinary path, mirroring entry_order's.
    if ("relation_order" %in% names(row) && has_nonblank(row$relation_order)) {
      xml_attr(relation_node, "order") <- row$relation_order
    }
  })

  doc
}
