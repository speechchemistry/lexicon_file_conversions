trait_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))

  doc <- read_xml(LIFT_file)

  # Direct-child axis, so this deliberately excludes sense/subsense/trait and
  # sense/subsense/grammatical-info/trait (<subsense> is unsupported --
  # SPEC.md's Not Yet Specified -- and its senses have no row in the sense
  # table, mirroring example_table()'s identical exclusion).
  senses <- xml_find_all(doc, ".//entry/sense")

  extract_sense_traits(senses)
}
