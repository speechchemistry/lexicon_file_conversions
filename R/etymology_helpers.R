# Classifies a csv2lift etymologies CSV's column names into the shapes
# etymology_table() produces (see classify_columns()). Etymology-level
# <field> (comment, languagenotes) is read and written, so an unrecognised
# column becomes a custom field.
classify_etymology_columns <- function(col_names) {
  classify_columns(
    col_names,
    meta = c("entry_id", "etymology_type", "etymology_source"),
    rules = list(
      prefix_rule("etymology_", "form", "etymology form"),
      prefix_rule("gloss_", "gloss", "etymology gloss")
    ),
    fallback = "field",
    table_label = "etymology"
  )
}
