attach_traits_to_lift <- function(doc, trait_table) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  if (nrow(trait_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)

  walk(seq_len(nrow(trait_table)), ~{
    row <- trait_table[.x, ]

    sense_node <- xml_find_first(root, sprintf(".//sense[@id='%s']", row$sense_guid))
    if (inherits(sense_node, "xml_missing")) {
      stop(sprintf(
        "Trait row %d references sense_guid '%s', which was not found in the sense table",
        .x, row$sense_guid
      ), call. = FALSE)
    }

    owner_node <- if (identical(row$owner, "sense")) {
      sense_node
    } else if (identical(row$owner, "grammatical-info")) {
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
    } else {
      stop(sprintf(
        "Trait row %d has unrecognised owner '%s' (expected 'sense' or 'grammatical-info')",
        .x, row$owner
      ), call. = FALSE)
    }

    xml_add_child(owner_node, "trait", name = row$trait_name, value = row$trait_value)
  })

  doc
}
