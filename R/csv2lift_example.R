attach_examples_to_lift <- function(doc, example_table) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  if (nrow(example_table) == 0) {
    return(doc)
  }

  root <- xml_root(doc)

  col_classes <- classify_example_columns(names(example_table))
  form_cols <- filter(col_classes, kind == "form")
  translation_form_cols <- filter(col_classes, kind == "translation_form")
  note_cols <- filter(col_classes, kind == "typed_note")

  walk(seq_len(nrow(example_table)), ~{
    row <- example_table[.x, ]

    # Matches <subsense> too (SPEC.md's Sense Table): an example can hang
    # directly off one, since subsense reuses sense-content verbatim.
    sense_node <- xml_find_first(root, sprintf(".//*[self::sense or self::subsense][@id='%s']", row$sense_guid))
    if (inherits(sense_node, "xml_missing")) {
      stop(sprintf(
        "Example row %d references sense_guid '%s', which was not found in the sense table",
        .x, row$sense_guid
      ), call. = FALSE)
    }

    warn_on_reference_disagreement(row, note_cols, .x)

    # Unlike every other optional element in this model, <example> is
    # emitted unconditionally: identity here is purely positional (SPEC.md's
    # Structural Rules), so dropping a blank row would shift the index of its surviving
    # siblings — six senses in Sena3.lift interleave blank and non-blank
    # examples.
    #
    # Inserted before any existing <subsense> child, rather than appended,
    # when the sense has one: <subsense> is lift.rng's declared last child
    # of sense-content, and real FLEx output agrees (unlike <note>, which
    # separately, already, lands after <example> regardless of source
    # order — SPEC.md's Sense Table). attach_senses_to_lift() attaches a
    # subsense as part of its own registry pass, entirely before this table's
    # own pass starts, so appending here would always land a sense's own
    # example after its subsense (and after everything the subsense itself
    # contains, including a nested example of its own) even when the source
    # had it the other way around — sena3.lift entry e0aa351f-… does, and
    # inserting-before is what keeps that entry's own example, and its
    # subsense's separate nested example, in their original relative order.
    existing_subsense <- xml_find_first(sense_node, "./subsense")
    has_subsense <- !inherits(existing_subsense, "xml_missing")

    example_attrs <- list()
    if ("example_source" %in% names(row) && has_nonblank(row$example_source)) {
      example_attrs$source <- row$example_source
    }
    example_node <- if (has_subsense) {
      do.call(xml_add_sibling, c(list(existing_subsense, "example", .where = "before"), example_attrs))
    } else {
      do.call(xml_add_child, c(list(sense_node, "example"), example_attrs))
    }

    if (nrow(form_cols) > 0) {
      form_values <- set_names(as.character(row[form_cols$column]), form_cols$lang)
      add_multitext_children(example_node, form_values)
    }

    # <translation> is emitted when there's a type OR any text — not gated on
    # has_nonblank(type) alone, since one of the 18 in Sena3.lift has a type
    # but no text, and losing that type would be a silent regression from
    # what example_table() extracted.
    translation_type <- if ("translation_type" %in% names(row)) row$translation_type else NA_character_
    translation_values <- if (nrow(translation_form_cols) > 0) {
      set_names(as.character(row[translation_form_cols$column]), translation_form_cols$lang)
    } else {
      character()
    }
    has_translation_type <- !is.na(translation_type) && nzchar(translation_type)
    if (has_translation_type || has_nonblank(translation_values)) {
      translation_args <- list(example_node, "translation")
      if (has_translation_type) translation_args$type <- translation_type
      translation_node <- do.call(xml_add_child, translation_args)
      add_multitext_children(translation_node, translation_values)
    }

    if (nrow(note_cols) > 0) {
      emit_typed_children(example_node, note_cols, row, "note")
    }
  })

  doc
}
