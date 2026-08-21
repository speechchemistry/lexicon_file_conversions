reversal_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))
  library(tidyr)

  doc <- read_xml(LIFT_file)

  # Direct-child axis, so this deliberately excludes sense/subsense/reversal
  # (0 occurrences in any fixture, but <subsense> is unsupported regardless --
  # SPEC.md's Not Yet Specified -- and its senses have no row in the sense
  # table, mirroring example_table()'s identical exclusion).
  reversals <- xml_find_all(doc, ".//entry/sense/reversal")

  empty_reversal_meta <- tibble(
    reversal_index = integer(),
    sense_guid = character(),
    reversal_type = character()
  )

  # first stage: the foreign key, row position, and @type. Guarded on both
  # the outer (zero reversals anywhere) and inner (n/a here, no per-parent
  # branching) paths, mirroring example_table().
  reversal_meta <- if (length(reversals) == 0) {
    empty_reversal_meta
  } else {
    tibble(
      reversal_index = seq_along(reversals),
      sense_guid = map_chr(reversals, ~xml_attr(xml_parent(.x), "id")),
      reversal_type = map_chr(reversals, ~xml_attr(.x, "type"))
    )
  }

  # second stage: the reversal form, one column per writing system found
  forms_long <- extract_reversal_multitext(reversals, "./form")
  forms_wide <- forms_long |>
    pivot_wider(
      id_cols = reversal_index,
      names_from = lang,
      values_from = text,
      names_glue = "reversal_{lang}"
    )

  reversal_meta |>
    left_join(forms_wide, by = "reversal_index") |>
    select(-reversal_index)
}
