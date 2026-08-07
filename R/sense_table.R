sense_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))
  library(tidyr)

  doc <- read_xml(LIFT_file)

  # find entry nodes
  entries <- xml_find_all(doc, ".//entry")

  empty_sense_meta <- tibble(
    sense_guid = character(),
    entry_id = character(),
    grammatical_info = character()
  )

  # first stage: sense-level metadata only (sense_guid, entry_id, grammatical_info)
  sense_meta <- if (length(entries) == 0) {
    empty_sense_meta
  } else {
    entries |>
      map_df(~{
        entry_id <- xml_attr(.x, "guid")
        senses <- xml_find_all(.x, "./sense")
        if(length(senses) == 0) return(empty_sense_meta)
        map_df(senses, ~{
          tibble(
            sense_guid = xml_attr(.x, "id"),
            entry_id = entry_id,
            grammatical_info = xml_attr(xml_find_first(.x, "./grammatical-info"), "value")
          )
        })
      })
  }

  senses <- xml_find_all(doc, ".//entry/sense")

  # second stage: multi-lang gloss; <gloss lang><text> mirrors <form lang><text>
  gloss_long <- extract_sense_multitext_element(senses, "./gloss")
  gloss_wide <- gloss_long |>
    pivot_wider(
      id_cols = sense_guid,
      names_from = lang,
      values_from = text,
      names_glue = "gloss_{lang}"
    )

  # multi-lang definition; <definition><form lang><text> mirrors entry <citation>
  definition_long <- extract_sense_multitext_element(senses, "./definition/form")
  definition_wide <- definition_long |>
    pivot_wider(
      id_cols = sense_guid,
      names_from = lang,
      values_from = text,
      names_glue = "definition_{lang}"
    )

  sense_meta |>
    left_join(gloss_wide, by = "sense_guid") |>
    left_join(definition_wide, by = "sense_guid")
}