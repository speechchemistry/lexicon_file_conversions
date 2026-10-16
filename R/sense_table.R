sense_table <- function(LIFT_file) {
  doc <- read_xml(LIFT_file)

  # Every <sense> and <subsense> (any depth), one row each. <subsense> reuses
  # sense-content verbatim (lift.rng), so a subsense's row has the identical
  # shape -- only parent_sense_guid (the immediate parent's own id; NA for a
  # top-level sense) distinguishes it. The union comes back in document
  # order, which is depth-first: a sense's row is immediately followed by its
  # subsenses' rows, in turn followed by theirs -- the order csv2lift relies
  # on to attach each subsense to an already-created parent (SPEC.md's Sense
  # Table). Every multitext stage below therefore covers subsense-owned data
  # too (sena3.lift's 8 subsenses carry gloss, definition and a typed note).
  senses <- xml_find_all(doc, ".//entry/sense | .//subsense")
  sense_guids <- xml_attr(senses, "id")

  # first stage: sense-level metadata only.
  #
  # FLEx emits @order only on the senses of multi-sense entries (446 of 446
  # such senses in Sena3.lift, and on none of the 1271 single-sense ones,
  # nor on any of its 8 subsenses). Copied verbatim, never regenerated from
  # row position -- same rule as the entry dates (SPEC.md's Entry Table).
  sense_meta <- tibble(
    sense_guid = sense_guids,
    entry_id = xml_attr(xml_find_first(senses, "ancestor::entry[1]"), "guid"),
    sense_order = xml_attr(senses, "order"),
    grammatical_info = xml_attr(xml_find_first(senses, "./grammatical-info"), "value"),
    parent_sense_guid = if_else(xml_name(senses) == "subsense", xml_attr(xml_find_first(senses, "parent::*"), "id"), NA_character_)
  )

  # second stage: multi-lang gloss; <gloss lang><text> mirrors <form lang><text>
  gloss_long <- extract_multitext(senses, sense_guids, "sense_guid", "./gloss")
  gloss_wide <- gloss_long |>
    pivot_wider(
      id_cols = sense_guid,
      names_from = lang,
      values_from = text,
      names_glue = "gloss_{lang}"
    )

  # multi-lang definition; <definition><form lang><text> mirrors entry <citation>
  definition_long <- extract_multitext(senses, sense_guids, "sense_guid", "./definition/form")
  definition_wide <- definition_long |>
    pivot_wider(
      id_cols = sense_guid,
      names_from = lang,
      values_from = text,
      names_glue = "definition_{lang}"
    )

  # plain (untyped) sense-level notes; FLEx's sense pane labels this field
  # "General Note", distinct from both the entry-level "Note" field (SPEC.md's
  # Entry Table) and
  # the typed sense notes (Phonology Note, Grammar Note, etc.), so it gets
  # its own reserved prefix rather than reusing "note_". [not(@type)]
  # excludes those typed notes, which are distinct FLEx fields that happen
  # to reuse the <note> element.
  notes_long <- extract_multitext(senses, sense_guids, "sense_guid", "./note[not(@type)]/form")
  notes_wide <- notes_long |>
    pivot_wider(
      id_cols = sense_guid,
      names_from = lang,
      values_from = text,
      names_glue = "general_note_{lang}"
    )

  # custom <field> elements (type attribute) and their <form> children
  fields_long <- extract_multitext_with_attribute(senses, sense_guids, "sense_guid", "./field", "type", "field_text")
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
  typed_notes_long <- extract_multitext_with_attribute(senses, sense_guids, "sense_guid", "./note[@type]", "type", "note_text")
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