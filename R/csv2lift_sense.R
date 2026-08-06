attach_senses_to_lift <- function(doc, sense_table) {
  library(xml2)
  library(purrr)

  if (nrow(sense_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)

  walk(seq_len(nrow(sense_table)), ~{
    row <- sense_table[.x, ]

    entry_node <- xml_find_first(root, sprintf(".//entry[@guid='%s']", row$entry_id))
    if (inherits(entry_node, "xml_missing")) {
      stop(sprintf(
        "Sense %s references entry_id '%s', which was not found in the entry table",
        row$sense_guid, row$entry_id
      ), call. = FALSE)
    }

    sense_args <- list(entry_node, "sense")
    if (!is.na(row$sense_guid) && nzchar(row$sense_guid)) {
      sense_args$id <- row$sense_guid
    }
    sense_node <- do.call(xml_add_child, sense_args)

    if (!is.na(row$grammatical_info) && nzchar(row$grammatical_info)) {
      xml_add_child(sense_node, "grammatical-info", value = row$grammatical_info)
    }

    if (!is.na(row$gloss_en) && nzchar(row$gloss_en)) {
      gloss_node <- xml_add_child(sense_node, "gloss", lang = "en")
      text_node <- xml_add_child(gloss_node, "text")
      xml_text(text_node) <- row$gloss_en
    }
  })

  doc
}
