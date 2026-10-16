# Classifies a csv2lift senses CSV's column names into the shapes
# sense_table() produces (see classify_columns()). The untyped sense note
# ("General Note" in FLEx) has its own general_note_ prefix, distinct from
# the typed note_<type>_<lang> columns. Sense-level <field> is read and
# written, so an unrecognised column becomes a custom field.
classify_sense_columns <- function(col_names) {
  classify_columns(
    col_names,
    meta = c("sense_guid", "entry_id", "sense_order", "grammatical_info", "parent_sense_guid"),
    rules = list(
      prefix_rule("gloss_", "gloss"),
      prefix_rule("definition_", "definition"),
      prefix_rule("general_note_", "note"),
      TYPED_NOTE_RULE
    ),
    fallback = "field",
    table_label = "sense"
  )
}
