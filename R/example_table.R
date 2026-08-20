example_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))
  library(tidyr)

  doc <- read_xml(LIFT_file)

  # Direct-child axis, so this deliberately excludes sense/subsense/example
  # (1 occurrence in Sena3.lift): <subsense> is unsupported (SPEC.md's Not Yet Specified), its
  # senses have no row in the sense table, and an example keyed to one would
  # have a dangling sense_guid FK on write.
  examples <- xml_find_all(doc, ".//entry/sense/example")

  empty_example_meta <- tibble(
    example_index = integer(),
    sense_guid = character(),
    example_source = character()
  )

  # first stage: the foreign key, row position, and @source ("Reference" in
  # FLEx). Guarded on both the outer (zero examples anywhere) and inner
  # (handled per-example below) paths, mirroring pronunciation_table().
  example_meta <- if (length(examples) == 0) {
    empty_example_meta
  } else {
    tibble(
      example_index = seq_along(examples),
      sense_guid = map_chr(examples, ~xml_attr(xml_parent(.x), "id")),
      example_source = map_chr(examples, ~xml_attr(.x, "source"))
    )
  }

  # second stage: the example sentence, one column per writing system found
  forms_long <- extract_example_multitext(examples, "./form")
  forms_wide <- forms_long |>
    pivot_wider(
      id_cols = example_index,
      names_from = lang,
      values_from = text,
      names_glue = "example_{lang}"
    )

  # third stage: the translation. @type is a plain value column
  # (translation_type), not part of a column name — see
  # extract_example_translation()'s comment for why.
  translation <- extract_example_translation(examples)
  translation_forms_wide <- translation$forms |>
    pivot_wider(
      id_cols = example_index,
      names_from = lang,
      values_from = text,
      names_glue = "translation_{lang}"
    )

  # fourth stage: the reference note; reuses the typed-note scheme (SPEC.md's
  # Column Classification), which is deliberately shared across every level.
  note_long <- extract_example_multitext_with_attribute(examples, "./note[@type]", "type", "note_text")
  note_wide <- note_long |>
    pivot_wider(
      id_cols = example_index,
      names_from = c(type, lang),
      names_glue = "note_{type}_{lang}",
      values_from = note_text
    )

  example_meta |>
    left_join(forms_wide, by = "example_index") |>
    left_join(translation$type, by = "example_index") |>
    left_join(translation_forms_wide, by = "example_index") |>
    left_join(note_wide, by = "example_index") |>
    select(-example_index)
}
