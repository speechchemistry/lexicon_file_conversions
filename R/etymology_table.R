etymology_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))
  library(tidyr)

  doc <- read_xml(LIFT_file)

  # one row per <etymology>, not per entry: lift.rng makes etymology
  # zeroOrMore (real data never exceeds 1 per entry, but the schema permits
  # more, so this is a table rather than a column, mirroring <pronunciation>)
  etymologies <- xml_find_all(doc, ".//entry/etymology")

  empty_etymology_meta <- tibble(
    etymology_index = integer(),
    entry_id = character(),
    etymology_type = character(),
    etymology_source = character()
  )

  # first stage: the foreign key, row position, and the two required
  # attributes. Guarded because a lexicon with no etymologies at all (or no
  # entries at all) must still yield a typed empty tibble, or the left_join
  # below fails on missing columns
  etymology_meta <- if (length(etymologies) == 0) {
    empty_etymology_meta
  } else {
    tibble(
      etymology_index = seq_along(etymologies),
      entry_id = map_chr(etymologies, ~xml_attr(xml_parent(.x), "guid")),
      etymology_type = map_chr(etymologies, ~xml_attr(.x, "type")),
      etymology_source = map_chr(etymologies, ~xml_attr(.x, "source"))
    )
  }

  # second stage: the etymon form, one column per writing system found
  forms_long <- extract_etymology_multitext(etymologies, "./form")
  forms_wide <- forms_long |>
    pivot_wider(
      id_cols = etymology_index,
      names_from = lang,
      values_from = text,
      names_glue = "etymology_{lang}"
    )

  # third stage: the gloss; <gloss lang><text> carries lang directly on
  # itself, mirroring sense-level gloss rather than the <form>-wrapped shapes
  gloss_long <- extract_etymology_multitext(etymologies, "./gloss")
  gloss_wide <- gloss_long |>
    pivot_wider(
      id_cols = etymology_index,
      names_from = lang,
      values_from = text,
      names_glue = "gloss_{lang}"
    )

  # fourth stage: custom <field type> children (comment, languagenotes),
  # type-keyed exactly like entry-level custom fields
  fields_long <- extract_etymology_multitext_with_attribute(etymologies, "./field", "type", "field_text")
  fields_wide <- fields_long |>
    pivot_wider(
      id_cols = etymology_index,
      names_from = c(type, lang),
      names_glue = "{type}_{lang}",
      values_from = field_text
    )

  etymology_meta |>
    left_join(forms_wide, by = "etymology_index") |>
    left_join(gloss_wide, by = "etymology_index") |>
    left_join(fields_wide, by = "etymology_index") |>
    select(-etymology_index)
}
