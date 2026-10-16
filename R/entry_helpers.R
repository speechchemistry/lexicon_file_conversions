# Classifies a csv2lift entries CSV's column names into the shapes
# entry_table() produces (see classify_columns()). Entry-level <field> is read
# and written, so an unrecognised column becomes a custom field.
classify_entry_columns <- function(col_names) {
  classify_columns(
    col_names,
    meta = c("entry_id", "entry_lift_id", "dateCreated", "dateModified", "entry_order", "morph_type"),
    rules = list(
      prefix_rule("citation_", "citation"),
      TYPED_NOTE_RULE,
      prefix_rule("note_", "note"),
      LEXICAL_UNIT_RULE
    ),
    fallback = "field",
    table_label = "entry"
  )
}
