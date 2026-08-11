# Example-level analogue of extract_multitext_element()/extract_sense_multitext_element().
# <example> has no id/guid (unlike <entry>'s guid and <sense>'s id), so its
# forms cannot be keyed on either — they are keyed by the example's position
# among all <entry>/<sense>/<example> elements instead, mirroring
# extract_pronunciation_multitext() (R/pronunciation_helpers.R). Row order is
# what carries identity for this table (SPEC.md 2), so the index must survive
# unchanged from extraction through to the final join.
extract_example_multitext <- function(examples, xpath, value_col = "text") {
  empty_result <- tibble(
    example_index = integer(),
    lang = character(),
    !!value_col := character()
  )

  if (length(examples) == 0) return(empty_result)

  map_df(seq_along(examples), function(index) {
    forms <- xml_find_all(examples[[index]], xpath)
    if (length(forms) == 0) return(empty_result)
    map_df(forms, ~tibble(
      example_index = index,
      lang = xml_attr(.x, "lang"),
      !!value_col := multitext_value(.x)
    ))
  })
}

# Example-level analogue of extract_sense_multitext_with_attribute(), keyed by
# example_index rather than sense_guid for the same reason as above. Used for
# the reference note (note[@type]/form), which — like typed notes elsewhere —
# is capped at one per type per parent by every fixture, so unlike
# <translation> (extract_example_translation() below) no dedup is needed here.
extract_example_multitext_with_attribute <- function(examples, parent_xpath, attr_name,
                                                      value_col = "text") {
  empty_result <- tibble(
    example_index = integer(),
    !!attr_name := character(),
    lang = character(),
    !!value_col := character()
  )

  if (length(examples) == 0) return(empty_result)

  map_df(seq_along(examples), function(index) {
    parents <- xml_find_all(examples[[index]], parent_xpath)
    if (length(parents) == 0) return(empty_result)
    map_df(parents, ~{
      attr_value <- xml_attr(.x, attr_name)
      forms <- xml_find_all(.x, "./form")
      if (length(forms) == 0) return(empty_result)
      map_df(forms, ~tibble(
        example_index = index,
        !!attr_name := attr_value,
        lang = xml_attr(.x, "lang"),
        !!value_col := multitext_value(.x)
      ))
    })
  })
}

# <translation>'s @type is a plain value column (translation_type), not part
# of a column name like typed notes/fields — the FLEx Examples pane shows one
# Translation with one Type per Example (confirmed against a user screenshot),
# and the data agrees: 191 of 192 examples with a translation have exactly
# one. This also has to preserve a translation whose @type is set but which
# carries no <form> children (18 of 193 in Sena3.lift) — a case
# extract_example_multitext_with_attribute() cannot represent, since its
# per-parent branch drops the attribute value entirely when there are no
# forms to pair it with (see R/sense_helpers.R's identical branch for typed
# notes/fields, which never faces this because every fixture's typed note has
# a form).
#
# lift.rng's own schematron asserts at most one <translation> per <example>
# ("Translations should be of different types"), so a second one is invalid
# LIFT that FLEx emitted, not a shape the CSV declines to model. When it
# occurs (1 of 1296 in Sena3.lift), warn on stderr naming the sense and keep
# the first, mirroring extract_single_media_href() (R/pronunciation_helpers.R).
extract_example_translation <- function(examples) {
  empty_type <- tibble(example_index = integer(), translation_type = character())
  empty_forms <- tibble(example_index = integer(), lang = character(), text = character())

  if (length(examples) == 0) return(list(type = empty_type, forms = empty_forms))

  types <- list()
  forms_list <- list()

  for (index in seq_along(examples)) {
    translations <- xml_find_all(examples[[index]], "./translation")
    if (length(translations) == 0) next

    if (length(translations) > 1) {
      warning(sprintf(
        "Sense %s has an example with %d translations; using the first (type=%s).",
        xml_attr(xml_parent(examples[[index]]), "id"),
        length(translations),
        xml_attr(translations[[1]], "type")
      ), call. = FALSE)
    }

    translation <- translations[[1]]
    types[[length(types) + 1]] <- tibble(
      example_index = index,
      translation_type = xml_attr(translation, "type")
    )

    forms <- xml_find_all(translation, "./form")
    if (length(forms) > 0) {
      forms_list[[length(forms_list) + 1]] <- map_df(forms, ~tibble(
        example_index = index,
        lang = xml_attr(.x, "lang"),
        text = multitext_value(.x)
      ))
    }
  }

  list(
    type = if (length(types) == 0) empty_type else bind_rows(types),
    forms = if (length(forms_list) == 0) empty_forms else bind_rows(forms_list)
  )
}
