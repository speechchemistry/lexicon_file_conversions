entry_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))
  library(tidyr)

  doc = read_xml(LIFT_file)

  # iterate entries once and extract lexical-unit forms + Plural Noun forms
  entries <- xml_find_all(doc, ".//entry")

  # extract lexical-unit forms for each writing system and also get the entry's
  # dateCreated and dateModified attributes
  # first stage: extract entry-level metadata only
  entry_meta <- tibble(
    entry_id = map_chr(entries, ~xml_attr(.x, "guid"), .progress = FALSE),
    dateCreated = map_chr(entries, ~xml_attr(.x, "dateCreated"), .progress = FALSE),
    dateModified = map_chr(entries, ~xml_attr(.x, "dateModified"), .progress = FALSE),
    entry_order = map_chr(entries, ~xml_attr(.x, "order"), .progress = FALSE),
    morph_type = extract_single_trait(entries, "morph-type")
  )
  # second stage: extract lexical-unit forms
  lex_long <- extract_multitext_element(entries, "./lexical-unit/form")

  # since the table is in a long form with a row for each writing system, we
  # need to pivot wider
  lex_wide <- lex_long |>
    pivot_wider(
      id_cols = entry_id,
      names_from = lang,
      values_from = text
    )

  # extract all custom <field> elements (type attribute) and their <form> children
  fields_long <- extract_multitext_with_attribute(entries, "./field", "type", "field_text")

  # pivot so each (field_type, writing-system) becomes a wide column
  # names_glue uses both field name (field_type) and writing system (lang)
  fields_wide <- fields_long |>
    pivot_wider(
      id_cols = entry_id,
      names_from = c(type, lang),
      names_glue = "{type}_{lang}",
      values_from = field_text
    )

  # extract citation forms for each writing system
  citations_long <- extract_multitext_element(entries, "./citation/form")

  # pivot citations wider so each writing system becomes its own column
  citations_wide <- citations_long |>
    pivot_wider(
      id_cols = entry_id,
      names_from = lang,
      values_from = text,
      names_glue = "citation_{lang}"
    )

  # extract plain (untyped) entry-level notes; [not(@type)] excludes typed
  # notes like <note type="restrictions">, which are a distinct FLEx field
  # that happens to reuse the <note> element
  notes_long <- extract_multitext_element(entries, "./note[not(@type)]/form")

  # pivot notes wider so each writing system becomes its own column
  notes_wide <- notes_long |>
    pivot_wider(
      id_cols = entry_id,
      names_from = lang,
      values_from = text,
      names_glue = "note_{lang}"
    )

  # typed entry-level notes: <note type="restrictions"> etc. are separate FLEx fields that reuse the
  # <note> element, so they get type-keyed columns like custom <field>s rather than merging into
  # note_<lang> above. [@type] is the exact complement of the [not(@type)] predicate used there.
  typed_notes_long <- extract_multitext_with_attribute(entries, "./note[@type]", "type", "note_text")

  typed_notes_wide <- typed_notes_long |>
    pivot_wider(id_cols = entry_id, names_from = c(type, lang),
                names_glue = "note_{type}_{lang}", values_from = note_text)

  # join with these extra fields our existing lexeme table
  combined <- entry_meta |>
    left_join(lex_wide, by = "entry_id") |>
    left_join(fields_wide, by = "entry_id") |>
    left_join(citations_wide, by = "entry_id") |>
    left_join(notes_wide, by = "entry_id") |>
    left_join(typed_notes_wide, by = "entry_id")

  combined
}