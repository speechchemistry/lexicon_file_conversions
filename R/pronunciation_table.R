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

  # first stage: the foreign key and the audio filename. Guarded because a
  # lexicon with no pronunciations at all (or no entries at all) must still
  # yield a typed empty tibble, or the left_join below fails on missing columns
  pronunciation_meta <- if (length(pronunciations) == 0) {
    empty_pronunciation_meta
  } else {
    tibble(
      pronunciation_index = seq_along(pronunciations),
      entry_id = map_chr(pronunciations, ~xml_attr(xml_parent(.x), "guid")),
      media_href = extract_single_media_href(pronunciations)
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

  pronunciation_meta |>
    left_join(forms_wide, by = "pronunciation_index") |>
    # media_href last so column order mirrors <pronunciation>'s own child
    # order (forms then media); the index was only ever a join key
    relocate(media_href, .after = last_col()) |>
    select(-pronunciation_index)
}
