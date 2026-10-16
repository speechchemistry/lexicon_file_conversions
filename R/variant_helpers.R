# Classifies a csv2lift variants CSV's column names into the shapes
# variant_table() produces (see classify_columns()). Variant-level <field>
# and @ref aren't read or written (SPEC.md's Not Yet Specified), so an
# unrecognised column is an error. Variant-owned <trait>s (morph-type,
# environment) live in the traits table (owner = "variant"), not here.
classify_variant_columns <- function(col_names) {
  classify_columns(
    col_names,
    meta = c("entry_id"),
    rules = list(prefix_rule("variant_", "form", "variant form")),
    fallback = "error",
    table_label = "variant"
  )
}
