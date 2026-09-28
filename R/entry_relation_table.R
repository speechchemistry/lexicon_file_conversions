entry_relation_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  doc <- read_xml(LIFT_file)

  # zeroOrMore under <entry> (up to 3 per entry in sena3.lift), and
  # relation-content has no id/guid of its own -- the only thing identifying
  # a relation is its position among an entry's own <relation> children.
  relations <- xml_find_all(doc, ".//entry/relation")

  empty_result <- tibble(
    entry_id = character(),
    relation_type = character(),
    relation_ref = character(),
    relation_order = character()
  )

  if (length(relations) == 0) return(empty_result)

  # relation/@ref holds the target entry's @id (a headword+guid string,
  # SPEC.md's Entry Table), not its @guid -- confirmed against every ref in
  # sena3.lift. Translated here to the target's guid, so relation_ref is a
  # guid like every other FK in this tool, not a raw @id string embedding
  # another row's headword. Built once over every entry in the document
  # (not just ones with relations), since a ref can target an entry that
  # only ever appears as someone else's target.
  all_entries <- xml_find_all(doc, ".//entry")
  id_to_guid <- set_names(xml_attr(all_entries, "guid"), xml_attr(all_entries, "id"))

  map_df(relations, ~{
    ref_id <- xml_attr(.x, "ref")
    entry_id <- xml_attr(xml_parent(.x), "guid")

    target_guid <- if (ref_id %in% names(id_to_guid)) {
      id_to_guid[[ref_id]]
    } else {
      # Not hypothetical in general (a ref can outlive the entry it named),
      # but never observed in sena3.lift -- every one of its 31 refs
      # resolves. Warn rather than fail the whole read over one row.
      cat(sprintf(
        "WARNING: entry '%s' has a relation referencing id '%s', which matches no entry in this document -- relation_ref left blank\n",
        entry_id, ref_id
      ), file = stderr())
      NA_character_
    }

    tibble(
      entry_id = entry_id,
      relation_type = xml_attr(.x, "type"),
      relation_ref = target_guid,
      relation_order = xml_attr(.x, "order")
    )
  })
}
