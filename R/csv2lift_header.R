# --header-from copies only <header>/<fields> verbatim from a source LIFT
# file: a custom <field> declaration is the only thing that tells FLEx a
# custom field's real type (e.g. MultiUnicode vs. a plain string) instead of
# defaulting one in on import (plans/old/remaining-lift-fields.md's D2). It
# doesn't copy <ranges>. Without them FLEx adds any list value it can't match
# to the target project's lists as a new item, which can duplicate items the
# project already has -- see SPEC.md's csv2lift CLI Shape and the README's
# section on importing into FLEx, which leaves supplying ranges to the user.
insert_header_fields_from_lift <- function(doc, source_lift) {
  if (!file.exists(source_lift)) {
    stop(sprintf("--header-from file not found: %s", source_lift), call. = FALSE)
  }

  source_content <- readr::read_file(source_lift) |> str_remove_all("\r")
  fields_block <- str_extract(source_content, regex("(?s)<fields>.*?</fields>"))

  if (is.na(fields_block)) {
    cat(sprintf("--header-from %s has no <header>/<fields>; no header written.\n", source_lift), file = stderr())
    return(invisible(doc))
  }

  header_node <- read_xml(sprintf("<header>%s</header>", fields_block))
  xml_add_child(xml_root(doc), header_node, .where = 0)

  invisible(doc)
}
