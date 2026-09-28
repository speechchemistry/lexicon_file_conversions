# Variant-level analogue of extract_reversal_multitext() (R/reversal_helpers.R):
# <variant> has no id/guid of its own, so its forms are keyed by the
# variant's position among all <entry>/<variant> elements, with entry_id
# carried separately as the surviving foreign key -- the position provides
# row identity, the attribute provides the parent link, mirroring the
# identical reversal/example-table split (SPEC.md's Data Handling). Unlike
# reversal, real data has a variant with no <form> at all (its content is
# entirely in traits not yet read -- SPEC.md's Not Yet Specified), so this
# can return no rows for a variant that still needs a row of its own; that is
# handled by variant_table()'s left_join, not here.
extract_variant_multitext <- function(variants, xpath) {
  empty_result <- tibble(
    variant_index = integer(),
    lang = character(),
    text = character()
  )

  if (length(variants) == 0) return(empty_result)

  map_df(seq_along(variants), function(index) {
    forms <- xml_find_all(variants[[index]], xpath)
    if (length(forms) == 0) return(empty_result)
    map_df(forms, ~tibble(
      variant_index = index,
      lang = xml_attr(.x, "lang"),
      text = multitext_value(.x)
    ))
  })
}

# Variant-level analogue of classify_reversal_columns(): classifies a
# csv2lift variant CSV's column names into the shapes variant_table()
# produces. Follows the pronunciation/example/reversal rule, not the
# entry/sense one -- an unrecognized column is a hard error, with no
# last-underscore custom-field fallback, since variant-level <field>/@ref
# aren't read or written at all (SPEC.md's Not Yet Specified). Variant-owned
# <trait> (morph-type, environment) rides in the traits table once C1b's
# owner_index lands, not as a column here.
classify_variant_columns <- function(col_names) {
  meta_columns <- c("entry_id")

  map_df(col_names, function(col) {
    if (col %in% meta_columns) {
      cat(sprintf("Classifying column '%s' as metadata\n", col), file = stderr())
      return(tibble(column = col, kind = "meta", lang = NA_character_))
    }

    if (grepl("^variant_.+$", col)) {
      lang <- sub("^variant_", "", col)
      cat(sprintf("Classifying column '%s' as variant form, lang=%s\n", col, lang),
          file = stderr())
      return(tibble(column = col, kind = "form", lang = lang))
    }

    stop(sprintf("Unrecognized variant column '%s'", col), call. = FALSE)
  })
}
