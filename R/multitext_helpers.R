# Multitext helpers shared by every table, in both directions: reading a
# <form lang><text> value into a CSV cell (multitext_value() and the two
# extractors) and writing one back (set_multitext_text() and the emit helpers).

# Passed as `ns` to every xml_find_all()/xml_find_first() call made on a
# single node inside a loop. xml2's default, xml_ns(x), re-scans the whole
# document for namespace declarations on every call, which took over 90% of
# the readers' run time. LIFT declares no XML namespaces and none of this
# package's XPaths use a prefix, so an empty set gives the same matches.
NO_NAMESPACES <- character()

# LIFT allows an inline <span lang="..."> inside a <text>, tagging a stretch of the value as a
# different writing system (typically an alternate-orthography form quoted inside an English
# note). xml_text() would flatten that and lose the tagging, so the <text>'s mixed content is
# serialised with the <span> tag kept literally and the surrounding text left as-is:
# 'variant: <span lang="seh">nkucauno</span>'. set_multitext_text() is the inverse.
#
# A span keeps whatever attributes it had, in source order: FLEx also exports spans with no
# lang at all (a hyperlink's href/class, a character style's class), and writing those as
# lang="NA" made FLEx add a "Nauru (na)" writing system on import (issue #6).
#
# The tag is rebuilt with sprintf() rather than as.character(child) on purpose: as.character()
# would XML-escape the span's content ("a & b" -> "a &amp; b") while the literal text around it
# stays raw, so the cell would be inconsistently escaped and no longer plain text.
multitext_value <- function(node) {
  text_node <- xml_find_first(node, "./text", ns = NO_NAMESPACES)
  # Fast path for the usual case, a <text> with no <span> (no element
  # children at all): its text is the value. A missing <text> reads as "",
  # as the general path below returns for it.
  if (xml_length(text_node) == 0) {
    return(if (inherits(text_node, "xml_missing")) "" else xml_text(text_node))
  }
  paste0(
    map_chr(xml_contents(text_node), function(child) {
      if (xml_type(child) == "text") return(xml_text(child))
      attrs <- xml_attrs(child)
      sprintf(
        "<span%s>%s</span>",
        paste0(sprintf(" %s=\"%s\"", names(attrs), attrs), collapse = ""),
        xml_text(child)
      )
    }),
    collapse = ""
  )
}

# Reads one multitext value per <form> (or other lang-carrying element)
# matched by `xpath` under each of `nodes`, one row each, in document order.
# `keys` is aligned with `nodes` and becomes the `key_col` column, so the same
# function serves tables keyed by a guid/id (`xml_attr(entries, "guid")`) and
# tables keyed by position (`seq_along(examples)`, for elements with no id of
# their own -- SPEC.md's Data Handling). `nodes` may be a nodeset or a plain
# list of nodes. Always returns the key, lang and value columns, typed, even
# when nothing matches, so the caller's pivot_wider()/left_join() never sees
# missing columns.
extract_multitext <- function(nodes, keys, key_col, xpath, value_col = "text") {
  forms_per_node <- map(nodes, ~xml_find_all(.x, xpath, ns = NO_NAMESPACES))
  forms <- unlist(forms_per_node, recursive = FALSE)

  tibble(
    !!key_col := rep(keys, lengths(forms_per_node)),
    lang = map_chr(forms, ~xml_attr(.x, "lang")),
    !!value_col := map_chr(forms, multitext_value)
  )
}

# As extract_multitext(), for type-keyed elements like <field type> and
# <note type>: finds each `parent_xpath` match under each of `nodes`, then one
# row per <form> inside it, carrying the parent's `attr_name` value as its own
# column. A parent with no <form> produces no rows (and so loses its
# attribute), the same as before; extract_example_translation() handles the
# one place that matters.
extract_multitext_with_attribute <- function(nodes, keys, key_col, parent_xpath, attr_name,
                                             value_col = "text") {
  parents_per_node <- map(nodes, ~xml_find_all(.x, parent_xpath, ns = NO_NAMESPACES))
  parents <- unlist(parents_per_node, recursive = FALSE)
  forms_per_parent <- map(parents, ~xml_find_all(.x, "./form", ns = NO_NAMESPACES))
  forms <- unlist(forms_per_parent, recursive = FALSE)
  forms_per_parent_count <- lengths(forms_per_parent)

  tibble(
    !!key_col := rep(rep(keys, lengths(parents_per_node)), forms_per_parent_count),
    !!attr_name := rep(map_chr(parents, ~xml_attr(.x, attr_name)), forms_per_parent_count),
    lang = map_chr(forms, ~xml_attr(.x, "lang")),
    !!value_col := map_chr(forms, multitext_value)
  )
}

# Shared by every csv2lift writer: an optional element is only emitted when
# at least one of its columns holds text, so blank CSV cells never turn into
# empty <citation>/<note>/<definition>/<pronunciation> elements.
has_nonblank <- function(values) any(!is.na(values) & nzchar(values))

# Inverse of multitext_value(): turns the literal <span lang="..."> tags in a CSV value back into
# real child elements. Built by parsing a constructed XML string because `xml_text()<-` cannot
# produce mixed content (see the plan). The value is walked as alternating literal / span pieces
# rather than substituted in one pass, because only the literal pieces may be XML-escaped — the
# span tags we emit must stay as markup, and escaping them would turn them back into text.
#
# The attribute list is captured whole (any number of name="value" pairs, possibly none) and
# re-emitted with only & and < escaped in the values.
SPAN_MARKUP_PATTERN <- "<span((?: [A-Za-z_:][-A-Za-z0-9_:.]*=\"[^\"]*\")*)>(.*?)</span>"

set_multitext_text <- function(parent_node, value) {
  spans <- stringr::str_match_all(value, SPAN_MARKUP_PATTERN)[[1]]
  literals <- stringr::str_split(value, SPAN_MARKUP_PATTERN)[[1]]

  inner <- escape_xml_text(literals[1])
  for (i in seq_len(nrow(spans))) {
    inner <- paste0(
      inner,
      sprintf("<span%s>%s</span>", escape_xml_attrs(spans[i, 2]), escape_xml_text(spans[i, 3])),
      escape_xml_text(literals[i + 1])
    )
  }

  text_node <- xml_add_child(parent_node, read_xml(paste0("<text>", inner, "</text>")))
  if (nrow(spans) > 0) keep_text_unindented(text_node)
  invisible(text_node)
}

# libxml2's pretty-printer indents the children of any element that has no text-node child,
# so a <text> holding only spans was written across several lines -- and FLEx imports that
# indentation as part of the value. An empty text-node child switches the indenting off for
# this element and serialises to nothing. xml2 has no constructor for a bare text node, so one
# is borrowed from a throwaway element.
keep_text_unindented <- function(text_node) {
  donor <- read_xml("<x>.</x>")
  empty_text <- xml_contents(donor)[[1]]
  xml_text(empty_text) <- ""
  xml_add_child(text_node, empty_text, .where = 0)
}

# Escapes the values inside a captured ' name="value"' attribute list. & and < are the only
# characters that can't appear raw in a double-quoted attribute value (" can't be in a CSV
# span at all, since the pattern stops at it).
escape_xml_attrs <- function(attrs) {
  attrs <- gsub("&", "&amp;", attrs, fixed = TRUE)
  gsub("<", "&lt;", attrs, fixed = TRUE)
}

escape_xml_text <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

# Shared by the two type-keyed emit loops (custom <field>s and typed
# <note type>s, at both entry and sense level): each unique type value in
# type_cols becomes one <tag type="..."> child, populated with one
# <form lang> per non-blank column of that type, omitted entirely if every
# column for that type is blank.
emit_typed_children <- function(parent_node, type_cols, row, tag) {
  walk(unique(type_cols$field_type), ~{
    cols_for_type <- type_cols[type_cols$field_type == .x, ]
    values <- set_names(as.character(row[cols_for_type$column]), cols_for_type$lang)
    if (has_nonblank(values)) {
      child_node <- xml_add_child(parent_node, tag, type = .x)
      add_multitext_children(child_node, values)
    }
  })
}

# Inverse of the multitext-reading helpers: adds one <tag lang><text> child
# per non-blank entry in a named vector (name = lang, value = text). Shared
# by lexical-unit, citation, each custom field's <field> element (tag="form",
# the default), and sense-level gloss (tag="gloss", attaches directly to
# <sense> with no wrapping element, unlike the others).
add_multitext_children <- function(parent_node, lang_values, tag = "form") {
  for (lang in names(lang_values)) {
    text <- lang_values[[lang]]
    if (is.na(text) || !nzchar(text)) next
    form_node <- xml_add_child(parent_node, tag, lang = lang)
    set_multitext_text(form_node, text)
  }
}
