# One row per <trait>, whichever of the two sense-level attachment points it
# comes from. Unlike every other table, <trait name value> is already a flat
# name/value pair (lift.rng's trait-content has no <optional> around either
# attribute, the same required-attribute shape as <etymology>'s @type/@source
# -- see R/etymology_helpers.R) -- there is no multitext/pivot_wider stage,
# since the node's own two attributes are the row.
#
# owner_index is always NA here (blank in the CSV): a sense has at most one
# <grammatical-info>, and sense_guid already identifies it uniquely, so no
# positional pointer is needed for either owner this covers. It earns its
# keep for the variant-owned rows extract_variant_traits() (below) produces:
# <variant> has no stable id of its own and can repeat per entry (up to 8 in
# sena3.lift), so a trait row naming one needs a position to point at.
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

# Variant-owned trait rows -- entry-parented, unlike extract_sense_traits()
# above. sense_guid is always NA here: a <variant> hangs directly off
# <entry>, with no sense involved at all. owner_index is the variant's
# 1-based position among the entry's own <variant> siblings (the caller
# already scopes `variants` to one entry's children, so seq_along() is that
# position directly) -- <variant> has no id/guid of its own (SPEC.md's
# Variant Table), so position is the only way a trait row can point back at
# a specific one when an entry has more than one.
extract_variant_traits <- function(variants) {
  empty_result <- tibble(
    entry_id = character(),
    sense_guid = character(),
    owner = character(),
    owner_index = character(),
    trait_name = character(),
    trait_value = character()
  )

  if (length(variants) == 0) return(empty_result)

  map_df(seq_along(variants), function(index) {
    variant <- variants[[index]]
    traits <- xml_find_all(variant, "./trait")
    if (length(traits) == 0) return(empty_result)

    tibble(
      entry_id = xml_attr(xml_parent(variant), "guid"),
      sense_guid = NA_character_,
      owner = "variant",
      owner_index = as.character(index),
      trait_name = xml_attr(traits, "name"),
      trait_value = xml_attr(traits, "value")
    )
  })
}
