sense_relation_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  doc <- read_xml(LIFT_file)

  # Direct-child axis, so this deliberately excludes sense/subsense/relation
  # (<subsense> is unsupported -- SPEC.md's Not Yet Specified -- and its
  # senses have no row in the sense table), mirroring example_table()'s
  # identical exclusion. zeroOrMore under <sense> (up to 2 per sense in
  # sena3.lift), and relation-content has no id/guid of its own -- the only
  # thing identifying a relation is its position among a sense's own
  # <relation> children.
  relations <- xml_find_all(doc, ".//entry/sense/relation")

  empty_result <- tibble(
    sense_guid = character(),
    relation_type = character(),
    relation_ref = character()
  )

  if (length(relations) == 0) return(empty_result)

  map_df(relations, ~tibble(
    sense_guid = xml_attr(xml_parent(.x), "id"),
    relation_type = xml_attr(.x, "type"),
    # sense/relation/@ref already targets the other sense's own @id, which is
    # always guid-shaped (SPEC.md's Sense Table) -- unlike entry/relation,
    # there is no id/guid distinction to translate between here, so this is
    # a verbatim copy, not a lookup.
    relation_ref = xml_attr(.x, "ref")
  ))
}
