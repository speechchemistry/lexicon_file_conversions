# Foreign-key lookups shared by the csv2lift attach_*_to_lift() writers.
# Each writer indexes the nodes its rows point at once per pass, instead of
# running a whole-document `.//entry[@guid='...']` search for every row, which
# made writing grow roughly with the square of the lexicon's size.

# Stops with an error naming every value of `column` that occurs more than
# once in `table`, before anything is written (SPEC.md's Structural Rules).
# Blank values are ignored: a row with no key writes no guid/id, and nothing
# can point at it anyway. Does nothing when the column is absent.
stop_on_duplicate_values <- function(table, column) {
  if (!column %in% names(table)) return(invisible(NULL))
  values <- table[[column]]
  values <- values[!is.na(values) & nzchar(values)]
  duplicates <- unique(values[duplicated(values)])
  if (length(duplicates) > 0) {
    stop(sprintf(
      "Duplicate %s value(s), must be unique: %s",
      column, paste(duplicates, collapse = ", ")
    ), call. = FALSE)
  }
  invisible(NULL)
}

# An environment (a hash table) mapping each node's `attr` value to the node,
# over every match of `xpath` under `root`. stop_on_duplicate_values() rules
# out duplicate entry_id/sense_guid values before any index is built; on a
# duplicate anyway the first node in document order wins. Blank values are
# skipped: csv2lift never writes a blank guid/id, and a blank key can never
# be looked up successfully anyway.
index_nodes <- function(root, xpath, attr) {
  index <- new.env(hash = TRUE, parent = emptyenv())
  walk(xml_find_all(root, xpath), ~add_indexed_node(index, xml_attr(.x, attr), .x))
  index
}

# Adds one node under `key` unless that key is already taken (first wins, as
# above). attach_senses_to_lift() uses this directly for the senses it creates
# mid-pass, since a later row's subsense can attach to them.
add_indexed_node <- function(index, key, node) {
  if (is.na(key) || !nzchar(key) || exists(key, envir = index, inherits = FALSE)) return(invisible(index))
  assign(key, node, envir = index)
  invisible(index)
}

# The node indexed under `key`, or a hard error naming the row, the column,
# and the table the key should have come from (SPEC.md's Structural Rules:
# an unmatched foreign key is never silently dropped).
require_node <- function(index, key, row_label, key_col, table_label) {
  node <- if (is.na(key) || !nzchar(key)) NULL else get0(key, envir = index, inherits = FALSE)
  if (is.null(node)) {
    stop(sprintf(
      "%s references %s '%s', which was not found in the %s",
      row_label, key_col, key, table_label
    ), call. = FALSE)
  }
  node
}

# For a traits row owned by an element with no id of its own (<variant>,
# entry-level <relation>): owner_index is that element's 1-based position
# among `nodes`, its entry's own children of that kind (SPEC.md's Traits
# Table). Returns the node, or a hard error when owner_index is missing,
# not an integer, or out of range.
require_owner_index <- function(nodes, row, row_index, owner, element) {
  has_owner_index <- "owner_index" %in% names(row) && has_nonblank(row$owner_index)
  owner_index <- if (has_owner_index) suppressWarnings(as.integer(row$owner_index)) else NA_integer_
  if (is.na(owner_index) || owner_index < 1 || owner_index > length(nodes)) {
    stop(sprintf(
      "Trait row %d has owner = '%s' and owner_index '%s', which does not match any <%s> on entry '%s'",
      row_index, owner, if (has_owner_index) row$owner_index else NA, element, row$entry_id
    ), call. = FALSE)
  }
  nodes[[owner_index]]
}
