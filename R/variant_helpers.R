# Variant-level analogue of classify_reversal_columns(): classifies a
# csv2lift variant CSV's column names into the shapes variant_table()
# produces. Follows the pronunciation/example/reversal rule, not the
# entry/sense one -- an unrecognized column is a hard error, with no
# last-underscore custom-field fallback, since variant-level <field>/@ref
# aren't read or written at all (SPEC.md's Not Yet Specified). Variant-owned
# <trait> (morph-type, environment) rides in the traits table (owner =
# "variant"), not as a column here.
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
