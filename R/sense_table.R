sense_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))
  library(tidyr)

  doc <- read_xml(LIFT_file)

  # find entry nodes
  entries <- xml_find_all(doc, ".//entry")

  empty_sense_meta <- tibble(
    sense_guid = character(),
    entry_id = character(),
    sense_order = character(),
    grammatical_info = character(),
    parent_sense_guid = character()
  )

  # first stage: sense-level metadata only (sense_guid, entry_id, sense_order,
  # grammatical_info, parent_sense_guid). extract_sense_metadata()
  # (R/sense_helpers.R) recurses into each top-level sense's own <subsense>
  # children, so a sense's row is immediately followed by its subsenses' own
  # rows, matching document order.
  #
  # FLEx emits @order only on the senses of multi-sense entries (446 of 446
  # such senses in Sena3.lift, and on none of the 1271 single-sense ones,
  # nor on any of its 8 subsenses). Copied verbatim, never regenerated from
  # row position — same rule as the entry dates (§2).
  sense_meta <- if (length(entries) == 0) {
    empty_sense_meta
  } else {
    entries |>
      map_df(~{
        entry_id <- xml_attr(.x, "guid")
        senses <- xml_find_all(.x, "./sense")
        if(length(senses) == 0) return(empty_sense_meta)
        map_df(senses, ~extract_sense_metadata(.x, entry_id))
      })
  }

  # Widened to include subsenses (any depth, via .//subsense) alongside
  # top-level senses, so every multitext stage below -- gloss, definition,
  # general note, custom field, typed note -- covers subsense-owned data too:
  # sena3.lift's 8 subsenses carry gloss (8), definition (1), and one typed
  # note (`note type="semantics"`), all through the identical sense-content
  # shape subsense reuses. These helpers key purely by the node's own @id, so
  # widening the node list is the only change needed here.
  senses <- xml_find_all(doc, ".//entry/sense | .//subsense")

  # second stage: multi-lang gloss; <gloss lang><text> mirrors <form lang><text>
  gloss_long <- extract_sense_multitext_element(senses, "./gloss")
  gloss_wide <- gloss_long |>
    pivot_wider(
      id_cols = sense_guid,
      names_from = lang,
      values_from = text,
      names_glue = "gloss_{lang}"
    )

  # multi-lang definition; <definition><form lang><text> mirrors entry <citation>
  definition_long <- extract_sense_multitext_element(senses, "./definition/form")
  definition_wide <- definition_long |>
    pivot_wider(
      id_cols = sense_guid,
      names_from = lang,
      values_from = text,
      names_glue = "definition_{lang}"
    )

  # plain (untyped) sense-level notes; FLEx's sense pane labels this field
  # "General Note", distinct from both the entry-level "Note" field (§3) and
  # the typed sense notes (Phonology Note, Grammar Note, etc.), so it gets
  # its own reserved prefix rather than reusing "note_". [not(@type)]
  # excludes those typed notes, which are distinct FLEx fields that happen
  # to reuse the <note> element.
  notes_long <- extract_sense_multitext_element(senses, "./note[not(@type)]/form")
  notes_wide <- notes_long |>
    pivot_wider(
      id_cols = sense_guid,
      names_from = lang,
      values_from = text,
      names_glue = "general_note_{lang}"
    )

  # custom <field> elements (type attribute) and their <form> children
  fields_long <- extract_sense_multitext_with_attribute(senses, "./field", "type", "field_text")
  fields_wide <- fields_long |>
    pivot_wider(
      id_cols = sense_guid,
      names_from = c(type, lang),
      names_glue = "{type}_{lang}",
      values_from = field_text
    )

  # typed sense-level notes: <note type="phonology"> etc. are separate FLEx fields that reuse the
  # <note> element, so they get type-keyed columns like custom <field>s rather than merging into
  # general_note_<lang> above. [@type] is the exact complement of the [not(@type)] predicate used there.
  typed_notes_long <- extract_sense_multitext_with_attribute(senses, "./note[@type]", "type", "note_text")
  typed_notes_wide <- typed_notes_long |>
    pivot_wider(
      id_cols = sense_guid,
      names_from = c(type, lang),
      names_glue = "note_{type}_{lang}",
      values_from = note_text
    )

  sense_meta |>
    left_join(gloss_wide, by = "sense_guid") |>
    left_join(definition_wide, by = "sense_guid") |>
    left_join(notes_wide, by = "sense_guid") |>
    left_join(fields_wide, by = "sense_guid") |>
    left_join(typed_notes_wide, by = "sense_guid")
}