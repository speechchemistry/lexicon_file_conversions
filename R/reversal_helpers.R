# Classifies a csv2lift reversals CSV's column names into the shapes
# reversal_table() produces (see classify_columns()). Reversal-level <field>
# isn't read or written (SPEC.md's Not Yet Specified), so an unrecognised
# column is an error.
classify_reversal_columns <- function(col_names) {
  classify_columns(
    col_names,
    meta = c("sense_guid", "reversal_type"),
    rules = list(prefix_rule("reversal_", "form", "reversal form")),
    fallback = "error",
    table_label = "reversal"
  )
}
