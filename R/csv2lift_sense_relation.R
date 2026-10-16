attach_sense_relations_to_lift <- function(doc, sense_relation_table) {
  if (nrow(sense_relation_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)
  senses <- index_nodes(root, ".//sense", "id")

  walk(seq_len(nrow(sense_relation_table)), ~{
    row <- sense_relation_table[.x, ]

    sense_node <- require_node(senses, row$sense_guid, sprintf("Sense-relation row %d", .x), "sense_guid", "sense table")

    # sense/relation/@ref already targets the other sense's own @id, which
    # is always guid-shaped (SPEC.md's Sense Table), so relation_ref is
    # written back verbatim -- no id/guid translation needed here, unlike
    # entry-relations (R/csv2lift_entry_relation.R). Still resolved against
    # the sense table before writing, so a bad ref fails fast rather than
    # producing a LIFT file whose <relation ref> points at nothing.
    target_node <- require_node(senses, row$relation_ref, sprintf("Sense-relation row %d", .x), "relation_ref", "sense table")

    # relation-content requires both @type and @ref (no <optional> wrapper),
    # the same required-attribute shape as <etymology>'s @type/@source
    # (R/csv2lift_etymology.R) -- both always emitted, even as "", unlike an
    # ordinary optional attribute. No @order here: sense/relation never
    # carries one in sena3.lift (SPEC.md's Sense-Relation Table).
    xml_add_child(
      sense_node, "relation",
      type = if (has_nonblank(row$relation_type)) row$relation_type else "",
      ref = row$relation_ref
    )
  })

  doc
}
