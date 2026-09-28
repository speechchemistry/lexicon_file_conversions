# One row per <trait>, whichever of the two sense-level attachment points it
# comes from. Unlike every other table, <trait name value> is already a flat
# name/value pair (lift.rng's trait-content has no <optional> around either
# attribute, the same required-attribute shape as <etymology>'s @type/@source
# -- see R/etymology_helpers.R) -- there is no multitext/pivot_wider stage,
# since the node's own two attributes are the row.
#
# owner_index is always NA here (blank in the CSV): a sense has at most one
# <grammatical-info>, and sense_guid already identifies it uniquely, so no
# positional pointer is needed for either owner this covers. It only earns
# its keep once variant/relation-owned traits exist (plans/remaining-lift-fields.md's
# C1b): those owners have no stable id of their own and can repeat per entry,
# so a trait row naming one needs a position to point at.
extract_sense_traits <- function(senses) {
  empty_result <- tibble(
    entry_id = character(),
    sense_guid = character(),
    owner = character(),
    owner_index = character(),
    trait_name = character(),
    trait_value = character()
  )

  if (length(senses) == 0) return(empty_result)

  map_df(senses, ~{
    sense_guid <- xml_attr(.x, "id")
    entry_id <- xml_attr(xml_parent(.x), "guid")

    # Grammatical-info-owned traits before sense-owned ones, matching the
    # nesting order real FLEx output uses (<grammatical-info> is one of a
    # sense's first children, <trait> one of its last -- confirmed against
    # every fixture with both).
    gram_info_traits <- xml_find_all(.x, "./grammatical-info/trait")
    sense_traits <- xml_find_all(.x, "./trait")

    rows <- bind_rows(
      if (length(gram_info_traits) == 0) empty_result else tibble(
        entry_id = entry_id,
        sense_guid = sense_guid,
        owner = "grammatical-info",
        owner_index = NA_character_,
        trait_name = xml_attr(gram_info_traits, "name"),
        trait_value = xml_attr(gram_info_traits, "value")
      ),
      if (length(sense_traits) == 0) empty_result else tibble(
        entry_id = entry_id,
        sense_guid = sense_guid,
        owner = "sense",
        owner_index = NA_character_,
        trait_name = xml_attr(sense_traits, "name"),
        trait_value = xml_attr(sense_traits, "value")
      )
    )

    if (nrow(rows) == 0) return(empty_result)
    rows
  })
}
