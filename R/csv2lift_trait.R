attach_traits_to_lift <- function(doc, trait_table) {
  if (nrow(trait_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)
  entries <- index_nodes(root, ".//entry", "guid")
  senses <- index_nodes(root, ".//sense", "id")

  walk(seq_len(nrow(trait_table)), ~{
    row <- trait_table[.x, ]

    owner_node <- if (row$owner %in% c("sense", "grammatical-info")) {
      sense_node <- require_node(senses, row$sense_guid, sprintf("Trait row %d", .x), "sense_guid", "sense table")

      if (identical(row$owner, "sense")) {
        sense_node
      } else {
        gram_info_node <- xml_find_first(sense_node, "./grammatical-info")
        # attach_senses_to_lift() only creates <grammatical-info> when
        # grammatical_info is non-blank (SPEC.md's "empty optional elements
        # are never emitted" rule) -- but real data has a sense whose
        # <grammatical-info value=""> is blank yet still wraps a <trait>
        # (sena3.lift entry 8d3435f5, sense e2c0d4bd), so that rule cannot be
        # the whole story once traits nest inside it. Created here with
        # value="" to match exactly what the source had, rather than treating
        # the missing wrapper as an error: the wrapper's *presence* carries no
        # value information beyond @value itself, which is already blank on
        # both sides. This unavoidably lands the element after every other
        # sense child already attached by this point, rather than in its
        # canonical first-child position -- a readability-only deviation, the
        # same kind already accepted for e.g. <example> vs <note> (SPEC.md's
        # Sense Table).
        if (inherits(gram_info_node, "xml_missing")) {
          gram_info_node <- xml_add_child(sense_node, "grammatical-info", value = "")
        }
        gram_info_node
      }
    } else if (identical(row$owner, "variant")) {
      entry_node <- require_node(entries, row$entry_id, sprintf("Trait row %d", .x), "entry_id", "entry table")

      # <variant> has no id/guid of its own (SPEC.md's Variant Table), so
      # owner_index -- the variant's 1-based position among this entry's own
      # <variant> siblings -- is the only way to point back at a specific
      # one, mirroring extract_variant_traits() (R/trait_helpers.R), which
      # produced it on the way in.
      require_owner_index(xml_find_all(entry_node, "./variant"), row, .x, "variant", "variant")
    } else if (identical(row$owner, "entry-relation")) {
      entry_node <- require_node(entries, row$entry_id, sprintf("Trait row %d", .x), "entry_id", "entry table")

      # <relation> has no id/guid of its own (SPEC.md's Entry-Relation
      # Table), so owner_index -- the relation's 1-based position among this
      # entry's own <relation> siblings -- is the only way to point back at
      # a specific one, mirroring extract_entry_relation_traits()
      # (R/trait_helpers.R), which produced it on the way in.
      require_owner_index(xml_find_all(entry_node, "./relation"), row, .x, "entry-relation", "relation")
    } else {
      stop(sprintf(
        "Trait row %d has unrecognised owner '%s' (expected 'sense', 'grammatical-info', 'variant', or 'entry-relation')",
        .x, row$owner
      ), call. = FALSE)
    }

    xml_add_child(owner_node, "trait", name = row$trait_name, value = row$trait_value)
  })

  doc
}
