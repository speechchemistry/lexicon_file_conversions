trait_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  doc <- read_xml(LIFT_file)

  # Iterated per entry, not with one absolute xpath per owner, so that each
  # entry's variant-owned rows land before its sense/grammatical-info-owned
  # ones in the output -- matching lift.rng's own declared entry-content
  # order (<variant> precedes <sense>), the same nesting-order-matches-source
  # rationale extract_sense_traits() already follows one level down.
  #
  # Direct-child axis throughout (./variant, ./sense), so this deliberately
  # excludes sense/subsense/trait, sense/subsense/grammatical-info/trait, and
  # variant/relation/trait (<subsense> and <relation> are unsupported --
  # SPEC.md's Not Yet Specified -- and neither has a row in any table this
  # tool builds), mirroring example_table()'s identical exclusion.
  entries <- xml_find_all(doc, ".//entry")

  empty_result <- tibble(
    entry_id = character(),
    sense_guid = character(),
    owner = character(),
    owner_index = character(),
    trait_name = character(),
    trait_value = character()
  )

  if (length(entries) == 0) return(empty_result)

  map_df(entries, ~{
    variant_rows <- extract_variant_traits(xml_find_all(.x, "./variant"))
    sense_rows <- extract_sense_traits(xml_find_all(.x, "./sense"))

    rows <- bind_rows(variant_rows, sense_rows)
    if (nrow(rows) == 0) return(empty_result)
    rows
  })
}
