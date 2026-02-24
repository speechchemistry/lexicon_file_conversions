# lift2csv_sense-table.R
# Extracts <sense> rows from a LIFT file and writes CSV to stdout

library(xml2)
library(purrr)
suppressMessages(library(dplyr))
library(readr)
library(argparser)

p <- arg_parser("This script takes the LIFT file and produces a CSV of the sense table")
p <- add_argument(p, "LIFT_file",
                  help = "SIL Flex lexicon LIFT file")
argv <- parse_args(p)

doc <- read_xml(argv$LIFT_file)

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
      tibble(
        sense_guid = sense_guid,
        entry_id = entry_id,
        grammatical_info = grammatical_info,
        gloss_en = gloss_en
      )
    })
  })

# write CSV to stdout
cat(format_csv(sense_table, na = ""))
