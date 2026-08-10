# A <pronunciation> has no id/guid of its own (unlike <entry>'s guid and
# <sense>'s id), so its forms cannot be keyed the way the entry- and
# sense-level extractors key theirs. They are keyed by the pronunciation's
# position in the document instead, which is also what fixes row order:
# SPEC.md 2 requires both directions to preserve source order rather than
# re-sort, and row order is the only thing carrying it for this table.
extract_pronunciation_multitext <- function(pronunciations, xpath) {
  empty_result <- tibble(
    pronunciation_index = integer(),
    lang = character(),
    text = character()
  )

  if (length(pronunciations) == 0) return(empty_result)

  map_df(seq_along(pronunciations), function(index) {
    forms <- xml_find_all(pronunciations[[index]], xpath)
    if (length(forms) == 0) return(empty_result)
    map_df(forms, ~tibble(
      pronunciation_index = index,
      lang = xml_attr(.x, "lang"),
      text = multitext_value(.x)
    ))
  })
}

# lift.rng allows zeroOrMore <media> per <pronunciation>, but the CSV row has
# a single media_href cell. Warn (to stderr) rather than silently dropping the
# extras, mirroring extract_single_trait()'s handling of duplicate traits.
extract_single_media_href <- function(pronunciations) {
  map_chr(pronunciations, ~{
    media <- xml_find_all(.x, "./media")
    if (length(media) == 0) return(NA_character_)
    hrefs <- xml_attr(media, "href")
    if (length(hrefs) > 1) {
      warning(sprintf(
        "Entry %s has a pronunciation with %d media elements (%s); using first href.",
        xml_attr(xml_parent(.x), "guid"), length(hrefs), paste(hrefs, collapse = ", ")
      ))
    }
    hrefs[1]
  })
}

# Pronunciation-level analogue of classify_sense_columns(): classifies a
# csv2lift pronunciation CSV's column names into the shapes
# pronunciation_table() produces. Follows the sense rule, not the entry one —
# an unrecognized column is a hard error, with no last-underscore custom-field
# fallback, since pronunciation-level <field>/<trait> aren't read or written
# at all and silently misclassifying one as a form would be worse than failing.
classify_pronunciation_columns <- function(col_names) {
  meta_columns <- c("entry_id", "media_href")

  map_df(col_names, function(col) {
    if (col %in% meta_columns) {
      cat(sprintf("Classifying column '%s' as metadata\n", col), file = stderr())
      return(tibble(column = col, kind = "meta", lang = NA_character_))
    }

    if (grepl("^pronunciation_.+$", col)) {
      lang <- sub("^pronunciation_", "", col)
      cat(sprintf("Classifying column '%s' as pronunciation form, lang=%s\n", col, lang),
          file = stderr())
      return(tibble(column = col, kind = "form", lang = lang))
    }

    stop(sprintf("Unrecognized pronunciation column '%s'", col), call. = FALSE)
  })
}
