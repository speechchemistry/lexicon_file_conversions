# How csv2lift reads a table's CSV column names (SPEC.md's Column
# Classification). Each table declares its rules in a short
# classify_<table>_columns() wrapper next to its reader, and they all share
# classify_columns() below.

# A column named <prefix><lang>, e.g. citation_seh. `label` is the name used
# in the "Classifying column" stderr line.
prefix_rule <- function(prefix, kind, label = kind) {
  list(pattern = paste0("^", prefix, "(.+)$"), kind = kind, label = label, typed = FALSE)
}

# Typed notes are type-keyed exactly like custom <field>s: note_<type>_<lang>,
# split on the LAST underscore. The pattern needs a second underscore after
# the prefix, so it can never swallow an untyped note_<lang> column, but it
# must come before any broader rule that would otherwise match first (an
# untyped note_ prefix, the custom-field fallback, or a table's own form
# prefix) and read the type as part of the writing system.
TYPED_NOTE_RULE <- list(pattern = "^note_(.+)_([^_]+)$", kind = "typed_note", label = "typed note", typed = TRUE)

# An entry's lexical-unit columns are named by their writing system alone,
# with no underscore at all (seh, en).
LEXICAL_UNIT_RULE <- list(pattern = "^([^_]*)$", kind = "lexical_unit", label = "lexical-unit", typed = FALSE)

# Classifies each of `col_names` into one row of `column`, `kind`,
# `field_type` (the type of a typed note or custom field, else NA) and
# `lang`, logging each decision to stderr. `meta` names are matched exactly
# and first; then `rules` are tried in order and the first match wins. A
# column matching nothing either becomes a custom <field> (`fallback =
# "field"`) or stops with an error naming it (`fallback = "error"`). A table
# uses "field" only when it reads and writes <field> children, so that
# elsewhere a misspelt column fails loudly instead of being written out as a
# made-up field.
#
# The custom-field fallback splits on the LAST underscore into field type
# and lang. Known limitation, accepted rather than solved generally: a
# writing-system code containing an underscore, or a custom field whose
# name collides with one of the table's own rules (e.g. a field literally
# named "citation" on entries), will misclassify.
classify_columns <- function(col_names, meta, rules, fallback = c("field", "error"), table_label) {
  fallback <- match.arg(fallback)

  map_df(col_names, function(col) {
    if (col %in% meta) {
      log_classification(col, "metadata")
      return(classified_column(col, "meta"))
    }

    for (rule in rules) {
      match <- regmatches(col, regexec(rule$pattern, col))[[1]]
      if (length(match) == 0) next
      if (rule$typed) {
        log_classification(col, sprintf("%s type='%s', lang=%s", rule$label, match[2], match[3]))
        return(classified_column(col, rule$kind, field_type = match[2], lang = match[3]))
      }
      log_classification(col, sprintf("%s, lang=%s", rule$label, match[2]))
      return(classified_column(col, rule$kind, lang = match[2]))
    }

    if (fallback == "error") {
      stop(sprintf("Unrecognized %s column '%s'", table_label, col), call. = FALSE)
    }

    field_type <- sub("_[^_]+$", "", col)
    lang <- sub("^.*_([^_]+)$", "\\1", col)
    log_classification(col, sprintf("field type='%s', lang=%s", field_type, lang))
    classified_column(col, "field", field_type = field_type, lang = lang)
  })
}

classified_column <- function(column, kind, field_type = NA_character_, lang = NA_character_) {
  tibble(column = column, kind = kind, field_type = field_type, lang = lang)
}

log_classification <- function(col, description) {
  cat(sprintf("Classifying column '%s' as %s\n", col, description), file = stderr())
}
