variant_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))
  library(tidyr)

  doc <- read_xml(LIFT_file)

  # one row per <variant>, not per entry: lift.rng makes variant zeroOrMore,
  # and real data does carry several per entry (up to 8 in sena3.lift)
  variants <- xml_find_all(doc, ".//entry/variant")

  empty_variant_meta <- tibble(
    variant_index = integer(),
    entry_id = character()
  )

  # first stage: just the foreign key and row position. Guarded because a
  # lexicon with no variants at all (or no entries at all) must still yield a
  # typed empty tibble, or the left_join below fails on missing columns
  variant_meta <- if (length(variants) == 0) {
    empty_variant_meta
  } else {
    tibble(
      variant_index = seq_along(variants),
      entry_id = map_chr(variants, ~xml_attr(xml_parent(.x), "guid"))
    )
  }

  # second stage: the variant form, one column per writing system found
  forms_long <- extract_variant_multitext(variants, "./form")
  forms_wide <- forms_long |>
    pivot_wider(
      id_cols = variant_index,
      names_from = lang,
      values_from = text,
      names_glue = "variant_{lang}"
    )

  variant_meta |>
    left_join(forms_wide, by = "variant_index") |>
    select(-variant_index)
}
