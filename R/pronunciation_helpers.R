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

# Pronunciation-level analogue of classify_etymology_columns(): classifies a
# csv2lift pronunciation CSV's column names into the shapes
# pronunciation_table() produces. Now ends in the same last-underscore
# custom-field fallback as classify_entry_columns()/classify_etymology_columns(),
# since pronunciation-level <field> (cv-pattern, tone, and potentially others)
# is read and written -- unlike <trait>, which stays a hard error via the
# "location" exact-match column below rather than an open fallback, since only
# one pronunciation-level trait name has ever been observed.
classify_pronunciation_columns <- function(col_names) {
  meta_columns <- c("entry_id", "media_href", "location")

  map_df(col_names, function(col) {
    if (col %in% meta_columns) {
      cat(sprintf("Classifying column '%s' as metadata\n", col), file = stderr())
      return(tibble(column = col, kind = "meta", field_type = NA_character_, lang = NA_character_))
    }

    if (grepl("^pronunciation_.+$", col)) {
      lang <- sub("^pronunciation_", "", col)
      cat(sprintf("Classifying column '%s' as pronunciation form, lang=%s\n", col, lang),
          file = stderr())
      return(tibble(column = col, kind = "form", field_type = NA_character_, lang = lang))
    }

    if (grepl("^media_label_.+$", col)) {
      lang <- sub("^media_label_", "", col)
      cat(sprintf("Classifying column '%s' as media label, lang=%s\n", col, lang),
          file = stderr())
      return(tibble(column = col, kind = "media_label", field_type = NA_character_, lang = lang))
    }

    # Custom field: split on the LAST underscore into field type and lang,
    # same known limitation as classify_entry_columns()/
    # classify_etymology_columns() -- a writing-system code containing an
    # underscore, or a custom field literally named "pronunciation",
    # "media_label", or "location" without a trailing underscore, will
    # misclassify here. Real data only exercises "cv-pattern" and "tone"
    # (FLEx's two declared pronunciation-level fields), but nothing restricts
    # this to those two.
    field_type <- sub("_[^_]+$", "", col)
    lang <- sub("^.*_([^_]+)$", "\\1", col)
    cat(sprintf("Classifying column '%s' as field type='%s', lang=%s\n", col, field_type, lang),
        file = stderr())
    tibble(column = col, kind = "field", field_type = field_type, lang = lang)
  })
}
