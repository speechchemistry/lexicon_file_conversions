pronunciation_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))
  library(tidyr)

  doc <- read_xml(LIFT_file)

  # one row per <pronunciation>, not per entry: lift.rng makes pronunciation
  # zeroOrMore, and real exports do carry several per entry
  pronunciations <- xml_find_all(doc, ".//entry/pronunciation")

  empty_pronunciation_meta <- tibble(
    pronunciation_index = integer(),
    entry_id = character(),
    media_href = character()
  )

  # <pronunciation>'s zero-or-more <media> collapses to at most one column
  # set (media_href, media_label_<lang>), so the first media node is picked
  # once here and shared by both -- see extract_first_media()'s own comment
  # for why that sharing matters.
  media_nodes <- extract_first_media(pronunciations)

  # first stage: the foreign key and the audio filename. Guarded because a
  # lexicon with no pronunciations at all (or no entries at all) must still
  # yield a typed empty tibble, or the left_join below fails on missing columns
  pronunciation_meta <- if (length(pronunciations) == 0) {
    empty_pronunciation_meta
  } else {
    tibble(
      pronunciation_index = seq_along(pronunciations),
      entry_id = map_chr(pronunciations, ~xml_attr(xml_parent(.x), "guid")),
      media_href = extract_single_media_href(media_nodes)
    )
  }

  # second stage: the phonetic transcription, one column per writing system
  forms_long <- extract_pronunciation_multitext(pronunciations, "./form")
  forms_wide <- forms_long |>
    pivot_wider(
      id_cols = pronunciation_index,
      names_from = lang,
      values_from = text,
      names_glue = "pronunciation_{lang}"
    )

  # third stage: the media's own <label>, one column per writing system found
  media_label_long <- extract_media_label_multitext(media_nodes)
  media_label_wide <- media_label_long |>
    pivot_wider(
      id_cols = pronunciation_index,
      names_from = lang,
      values_from = text,
      names_glue = "media_label_{lang}"
    )

  # fourth stage: custom <field type> children (cv-pattern, tone, ...),
  # type-keyed exactly like entry-level custom fields
  fields_long <- extract_pronunciation_multitext_with_attribute(pronunciations, "./field", "type", "field_text")
  fields_wide <- fields_long |>
    pivot_wider(
      id_cols = pronunciation_index,
      names_from = c(type, lang),
      names_glue = "{type}_{lang}",
      values_from = field_text
    )

  # fifth stage: the "location" trait -- always at most one per
  # pronunciation in real data, so a plain column rather than a row in the
  # long `traits` table (see extract_single_pronunciation_trait()'s comment)
  location_tbl <- tibble(
    pronunciation_index = seq_along(pronunciations),
    location = extract_single_pronunciation_trait(pronunciations, "location")
  )

  pronunciation_meta |>
    left_join(forms_wide, by = "pronunciation_index") |>
    # media_href relocated so column order mirrors <pronunciation>'s own
    # child order (forms, then media, then field, then trait); the index was
    # only ever a join key. media_label_wide/fields_wide/location_tbl are
    # left_joined afterward so they land after media_href, in that order.
    relocate(media_href, .after = last_col()) |>
    left_join(media_label_wide, by = "pronunciation_index") |>
    left_join(fields_wide, by = "pronunciation_index") |>
    left_join(location_tbl, by = "pronunciation_index") |>
    select(-pronunciation_index)
}
