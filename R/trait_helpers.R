# The traits table's columns, as a typed zero-row tibble.
empty_trait_rows <- function() {
  tibble(
    entry_id = character(),
    sense_guid = character(),
    owner = character(),
    owner_index = character(),
    trait_name = character(),
    trait_value = character()
  )
}

# One value per node for a trait name LIFT allows at most once per owner
# (an entry's morph-type, a pronunciation's location), which is why each is a
# plain column rather than rows in the traits table. If the data has more
# than one anyway, warn (to stderr) naming the owner and every value, and keep
# the first rather than silently dropping data. `describe_owner(node)` starts
# the warning, e.g. "Entry <guid> has".
extract_single_trait <- function(nodes, trait_name, describe_owner) {
  map_chr(nodes, ~{
    values <- xml_attr(xml_find_all(.x, sprintf("./trait[@name='%s']", trait_name), ns = NO_NAMESPACES), "value")
    if (length(values) == 0) return(NA_character_)
    if (length(values) > 1) {
      warning(sprintf(
        "%s %d '%s' traits (%s); using first value.",
        describe_owner(.x), length(values), trait_name, paste(values, collapse = ", ")
      ))
    }
    values[1]
  })
}

# One row per <trait>, whichever of the two sense-level attachment points it
# comes from. Unlike every other table, <trait name value> is already a flat
# name/value pair (lift.rng's trait-content has no <optional> around either
# attribute) -- there is no multitext/pivot_wider stage, since the node's own
# two attributes are the row.
#
# owner_index is always NA here (blank in the CSV): a sense has at most one
# <grammatical-info>, and sense_guid already identifies it uniquely, so no
# positional pointer is needed for either owner this covers. It's needed
# only for the owners extract_positional_owner_traits() (below) covers.
extract_sense_traits <- function(senses) {
  map_df(senses, ~{
    sense_guid <- xml_attr(.x, "id")
    entry_id <- xml_attr(xml_parent(.x), "guid")

    # Grammatical-info-owned traits before sense-owned ones, matching the
    # nesting order real FLEx output uses (<grammatical-info> is one of a
    # sense's first children, <trait> one of its last -- confirmed against
    # every fixture with both).
    gram_info_traits <- xml_find_all(.x, "./grammatical-info/trait", ns = NO_NAMESPACES)
    sense_traits <- xml_find_all(.x, "./trait", ns = NO_NAMESPACES)

    bind_rows(
      empty_trait_rows(),
      if (length(gram_info_traits) > 0) tibble(
        entry_id = entry_id,
        sense_guid = sense_guid,
        owner = "grammatical-info",
        owner_index = NA_character_,
        trait_name = xml_attr(gram_info_traits, "name"),
        trait_value = xml_attr(gram_info_traits, "value")
      ),
      if (length(sense_traits) > 0) tibble(
        entry_id = entry_id,
        sense_guid = sense_guid,
        owner = "sense",
        owner_index = NA_character_,
        trait_name = xml_attr(sense_traits, "name"),
        trait_value = xml_attr(sense_traits, "value")
      )
    )
  })
}

# Trait rows for one entry's own children of a kind that has no id/guid --
# <variant> (owner "variant") or entry-level <relation> (owner
# "entry-relation"), both of which can repeat per entry (up to 8 variants and
# 3 relations in sena3.lift). owner_index is the child's 1-based position
# among `nodes`, which the caller scopes to that one entry's children, so
# position is how a trait row points back at a specific one (SPEC.md's
# Traits Table). sense_guid is always NA: both hang directly off <entry>.
extract_positional_owner_traits <- function(nodes, owner) {
  map_df(seq_along(nodes), function(index) {
    node <- nodes[[index]]
    traits <- xml_find_all(node, "./trait", ns = NO_NAMESPACES)
    if (length(traits) == 0) return(empty_trait_rows())

    tibble(
      entry_id = xml_attr(xml_parent(node), "guid"),
      sense_guid = NA_character_,
      owner = owner,
      owner_index = as.character(index),
      trait_name = xml_attr(traits, "name"),
      trait_value = xml_attr(traits, "value")
    )
  })
}
