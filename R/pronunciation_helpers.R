# A <pronunciation> has no id/guid of its own (unlike <entry>'s guid and
# <sense>'s id), so its forms cannot be keyed the way the entry- and
# sense-level extractors key theirs. They are keyed by the pronunciation's
# position in the document instead, which is also what fixes row order:
# SPEC.md's Data Handling requires both directions to preserve source order rather than
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
# a single media_href cell (and, below, a single set of media_label_<lang>
# cells). Picking "the" media node once and sharing it is what keeps href and
# label from disagreeing about which media element is "first" -- warn (to
# stderr) rather than silently dropping the extras, mirroring
# extract_single_trait()'s handling of duplicate traits.
extract_first_media <- function(pronunciations) {
  map(pronunciations, ~{
    media <- xml_find_all(.x, "./media")
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

# <media>'s optional <label> child is a <form lang>-wrapped multitext, same
# shape as <pronunciation>'s own forms -- but keyed off the chosen media node
# (see extract_first_media() above) rather than the pronunciation node.
extract_media_label_multitext <- function(media_nodes) {
  empty_result <- tibble(
    pronunciation_index = integer(),
    lang = character(),
    text = character()
  )

  if (length(media_nodes) == 0) return(empty_result)

  map_df(seq_along(media_nodes), function(index) {
    node <- media_nodes[[index]]
    if (is.null(node)) return(empty_result)
    forms <- xml_find_all(node, "./label/form")
    if (length(forms) == 0) return(empty_result)
    map_df(forms, ~tibble(
      pronunciation_index = index,
      lang = xml_attr(.x, "lang"),
      text = multitext_value(.x)
    ))
  })
}

# Pronunciation-level analogue of extract_etymology_multitext_with_attribute():
# keyed by pronunciation_index (see extract_pronunciation_multitext() above)
# rather than entry_id, since pronunciations, not entries, are the node being
# iterated. Used for custom <field type> children -- FLEx's "CV Pattern" and
# "Tone" are the only ones seen in real data, but nothing restricts this to
# just those two, so the type is carried through rather than hardcoded.
extract_pronunciation_multitext_with_attribute <- function(pronunciations, parent_xpath, attr_name,
                                                             value_col = "text") {
  empty_result <- tibble(
    pronunciation_index = integer(),
    !!attr_name := character(),
    lang = character(),
    !!value_col := character()
  )

  if (length(pronunciations) == 0) return(empty_result)

  map_df(seq_along(pronunciations), function(index) {
    parents <- xml_find_all(pronunciations[[index]], parent_xpath)
    if (length(parents) == 0) return(empty_result)
    map_df(parents, ~{
      attr_value <- xml_attr(.x, attr_name)
      forms <- xml_find_all(.x, "./form")
      if (length(forms) == 0) return(empty_result)
      map_df(forms, ~tibble(
        pronunciation_index = index,
        !!attr_name := attr_value,
        lang = xml_attr(.x, "lang"),
        !!value_col := multitext_value(.x)
      ))
    })
  })
}

# Pronunciation-level analogue of extract_single_trait() (R/entry_helpers.R),
# keyed by the pronunciation's own position rather than an entry guid --
# "location" is the only pronunciation-level trait name seen in real data,
# always at most one per pronunciation, the same shape morph-type has at the
# entry level, so this is its own column rather than a row in the long
# `traits` table (see SPEC.md's Pronunciation Table).
extract_single_pronunciation_trait <- function(pronunciations, trait_name) {
  map_chr(pronunciations, ~{
    traits <- xml_find_all(.x, sprintf("./trait[@name='%s']", trait_name))
    if (length(traits) == 0) return(NA_character_)
    values <- xml_attr(traits, "value")
    if (length(values) > 1) {
      warning(sprintf(
        "Entry %s has a pronunciation with %d '%s' traits (%s); using first value.",
        xml_attr(xml_parent(.x), "guid"), length(values), trait_name, paste(values, collapse = ", ")
      ))
    }
    values[1]
  })
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
