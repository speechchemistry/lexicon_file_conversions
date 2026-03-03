lift2csv_sense_table <- function(LIFT_file) {
  library(xml2)
  library(purrr)
  suppressMessages(library(dplyr))
  library(readr)

  doc <- read_xml(LIFT_file)

  # find entry nodes
  entries <- xml_find_all(doc, ".//entry")

  # extract senses into a separate table
  sense_table <- entries |>
    map_df(~{
      entry_id <- xml_attr(.x, "guid")
      senses <- xml_find_all(.x, "./sense")
      if(length(senses) == 0) return(tibble())
      map_df(senses, ~{
        sense_guid <- xml_attr(.x, "id")
        grammatical_info <- xml_attr(xml_find_first(.x, "./grammatical-info"), "value")
        gloss_en <- xml_text(xml_find_first(.x, "./gloss[@lang='en']"))
        #source <- xml_text(xml_find_first(.x, "./note[@type='source']/form"))
        tibble(
          sense_guid = sense_guid,
          entry_id = entry_id,
          grammatical_info = grammatical_info,
          gloss_en = gloss_en#,
          #source = source
        )
      })
    })

  format_csv(sense_table, na = "")
}