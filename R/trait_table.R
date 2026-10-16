trait_table <- function(LIFT_file) {
  doc <- read_xml(LIFT_file)

  # Iterated per entry, not with one absolute xpath per owner, so that each
  # entry's variant-owned rows land before its entry-relation-owned ones,
  # which land before its sense/grammatical-info-owned ones, in the output --
  # matching lift.rng's own declared entry-content order (<variant>, then
  # <relation>, then <sense>), the same nesting-order-matches-source
  # rationale extract_sense_traits() already follows one level down.
  #
  # Direct-child axis throughout (./variant, ./relation, ./sense), so this
  # deliberately excludes sense/subsense/trait,
  # sense/subsense/grammatical-info/trait, variant/relation/trait, and
  # sense/relation/trait: none occurs in any fixture (SPEC.md's Traits Table
  # and Not Yet Specified).
  entries <- xml_find_all(doc, ".//entry")

  bind_rows(
    empty_trait_rows(),
    map_df(entries, ~bind_rows(
      extract_positional_owner_traits(xml_find_all(.x, "./variant", ns = NO_NAMESPACES), "variant"),
      extract_positional_owner_traits(xml_find_all(.x, "./relation", ns = NO_NAMESPACES), "entry-relation"),
      extract_sense_traits(xml_find_all(.x, "./sense", ns = NO_NAMESPACES))
    ))
  )
}
