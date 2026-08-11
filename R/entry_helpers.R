# LIFT allows an inline <span lang="..."> inside a <text>, tagging a stretch of the value as a
# different writing system (typically an alternate-orthography form quoted inside an English
# note). xml_text() would flatten that and lose the tagging, so the <text>'s mixed content is
# serialised with the <span> tag kept literally and the surrounding text left as-is:
# 'variant: <span lang="seh">nkucauno</span>'. set_multitext_text() is the inverse.
#
# The tag is rebuilt with sprintf() rather than as.character(child) on purpose: as.character()
# would XML-escape the span's content ("a & b" -> "a &amp; b") while the literal text around it
# stays raw, so the cell would be inconsistently escaped and no longer plain text.
multitext_value <- function(node) {
  text_node <- xml_find_first(node, "./text")
  paste0(
    map_chr(xml_contents(text_node), function(child) {
      if (xml_type(child) == "text") return(xml_text(child))
      sprintf("<span lang=\"%s\">%s</span>", xml_attr(child, "lang"), xml_text(child))
    }),
    collapse = ""
  )
}

extract_multitext_element <- function(entries, xpath, value_col = "text") {
  empty_result <- tibble(
    entry_id = character(),
    lang = character(),
    !!value_col := character()
  )

  if(length(entries) == 0) return(empty_result)

  entries |>
    map_df(~{
      entry_id <- xml_attr(.x, "guid")
      forms <- xml_find_all(.x, xpath)
      if(length(forms) == 0) return(empty_result)
      map_df(forms, ~tibble(
        entry_id = entry_id,
        lang = xml_attr(.x, "lang"),
        !!value_col := multitext_value(.x)
      ))
    })
}

extract_single_trait <- function(entries, trait_name) {
  map_chr(entries, ~{
    entry_id <- xml_attr(.x, "guid")
    traits <- xml_find_all(.x, sprintf("./trait[@name='%s']", trait_name))
    if (length(traits) == 0) return(NA_character_)
    values <- xml_attr(traits, "value")
    # LIFT allows only one trait of a given name per entry; if source data
    # violates that, warn (goes to stderr) rather than silently dropping data.
    if (length(values) > 1) {
      warning(sprintf(
        "Entry %s has %d '%s' traits (%s); using first value.",
        entry_id, length(values), trait_name, paste(values, collapse = ", ")
      ))
    }
    values[1]
  })
}

extract_multitext_with_attribute <- function(entries, parent_xpath, attr_name,
                                             value_col = "text") {
  empty_result <- tibble(
    entry_id = character(),
    !!attr_name := character(),
    lang = character(),
    !!value_col := character()
  )

  if(length(entries) == 0) return(empty_result)

  entries |>
    map_df(~{
      entry_id <- xml_attr(.x, "guid")
      parents <- xml_find_all(.x, parent_xpath)
      if(length(parents) == 0) return(empty_result)
      map_df(parents, ~{
        attr_value <- xml_attr(.x, attr_name)
        forms <- xml_find_all(.x, "./form")
        if(length(forms) == 0) return(empty_result)
        map_df(forms, ~tibble(
          entry_id = entry_id,
          !!attr_name := attr_value,
          lang = xml_attr(.x, "lang"),
          !!value_col := multitext_value(.x)
        ))
      })
    })
}

# Inverse of the extractors above: classify a csv2lift input CSV's column
# names into the four shapes entry_table() produces, so csv2lift can rebuild
# the right LIFT element for each column without re-deriving column-naming
# rules elsewhere.
classify_entry_columns <- function(col_names) {
  meta_columns <- c("entry_id", "dateCreated", "dateModified", "morph_type")

  map_df(col_names, function(col) {
    if (col %in% meta_columns) {
      cat(sprintf("Classifying column '%s' as metadata\n", col), file = stderr())
      return(tibble(column = col, kind = "meta", field_type = NA_character_, lang = NA_character_))
    }

    if (grepl("^citation_.+$", col)) {
      lang <- sub("^citation_", "", col)
      cat(sprintf("Classifying column '%s' as citation, lang=%s\n", col, lang), file = stderr())
      return(tibble(column = col, kind = "citation", field_type = NA_character_, lang = lang))
    }

    # Typed notes are type-keyed exactly like custom <field>s: note_<type>_<lang>, split on the LAST
    # underscore. This pattern requires a second underscore after the prefix so it can never swallow an
    # untyped note_<lang> column — but it must still precede the untyped branch below, which would
    # otherwise match first and read the type as part of the writing system.
    if (grepl("^note_.+_[^_]+$", col)) {
      note_type <- sub("^note_(.+)_[^_]+$", "\\1", col)
      lang <- sub("^note_.+_([^_]+)$", "\\1", col)
      cat(sprintf("Classifying column '%s' as typed note type='%s', lang=%s\n",
                  col, note_type, lang), file = stderr())
      return(tibble(column = col, kind = "typed_note", field_type = note_type, lang = lang))
    }

    if (grepl("^note_.+$", col)) {
      lang <- sub("^note_", "", col)
      cat(sprintf("Classifying column '%s' as note, lang=%s\n", col, lang), file = stderr())
      return(tibble(column = col, kind = "note", field_type = NA_character_, lang = lang))
    }

    if (!grepl("_", col, fixed = TRUE)) {
      cat(sprintf("Classifying column '%s' as lexical-unit, lang=%s\n", col, col), file = stderr())
      return(tibble(column = col, kind = "lexical_unit", field_type = NA_character_, lang = col))
    }

    # Custom field: split on the LAST underscore into field type and lang.
    # Known limitation, accepted rather than solved generally: a writing
    # system code containing an underscore, or a custom field literally
    # named "citation" or "note", will misclassify here.
    field_type <- sub("_[^_]+$", "", col)
    lang <- sub("^.*_([^_]+)$", "\\1", col)
    cat(sprintf("Classifying column '%s' as field type='%s', lang=%s\n", col, field_type, lang), file = stderr())
    tibble(column = col, kind = "field", field_type = field_type, lang = lang)
  })
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
SPAN_MARKUP_PATTERN <- "<span lang=\"([^\"]*)\">(.*?)</span>"

set_multitext_text <- function(parent_node, value) {
  spans <- stringr::str_match_all(value, SPAN_MARKUP_PATTERN)[[1]]
  literals <- stringr::str_split(value, SPAN_MARKUP_PATTERN)[[1]]

  inner <- escape_xml_text(literals[1])
  for (i in seq_len(nrow(spans))) {
    inner <- paste0(
      inner,
      sprintf("<span lang=\"%s\">%s</span>", spans[i, 2], escape_xml_text(spans[i, 3])),
      escape_xml_text(literals[i + 1])
    )
  }

  xml_add_child(parent_node, read_xml(paste0("<text>", inner, "</text>")))
}

escape_xml_text <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
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