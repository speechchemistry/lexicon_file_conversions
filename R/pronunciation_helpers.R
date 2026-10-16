# lift.rng allows zeroOrMore <media> per <pronunciation>, but the CSV row has
# a single media_href cell (and, below, a single set of media_label_<lang>
# cells). Picking "the" media node once and sharing it is what keeps href and
# label from disagreeing about which media element is "first" -- warn (to
# stderr) rather than silently dropping the extras, mirroring
# extract_single_trait()'s handling of duplicate traits.
extract_first_media <- function(pronunciations) {
  map(pronunciations, ~{
    media <- xml_find_all(.x, "./media", ns = NO_NAMESPACES)
    if (length(media) == 0) return(NULL)
    if (length(media) > 1) {
      warning(sprintf(
        "Entry %s has a pronunciation with %d media elements (%s); using first.",
        xml_attr(xml_parent(.x), "guid"), length(media),
        paste(xml_attr(media, "href"), collapse = ", ")
      ))
    }
    media[[1]]
  })
}

extract_single_media_href <- function(media_nodes) {
  map_chr(media_nodes, ~ if (is.null(.x)) NA_character_ else xml_attr(.x, "href"))
}

# Classifies a csv2lift pronunciations CSV's column names into the shapes
# pronunciation_table() produces (see classify_columns()). Pronunciation-level
# <field> (FLEx's cv-pattern and tone, and potentially others) is read and
# written, so an unrecognised column becomes a custom field. The one
# pronunciation-level trait, location, is an exact-match metadata column.
classify_pronunciation_columns <- function(col_names) {
  classify_columns(
    col_names,
    meta = c("entry_id", "media_href", "location"),
    rules = list(
      prefix_rule("pronunciation_", "form", "pronunciation form"),
      prefix_rule("media_label_", "media_label", "media label")
    ),
    fallback = "field",
    table_label = "pronunciation"
  )
}
