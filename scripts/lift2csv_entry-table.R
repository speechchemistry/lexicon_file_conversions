# TO DO
# - add the other entry level fields like morph type and pronunciation

library(xml2)
library(purrr)
suppressMessages(library(dplyr))
library(tidyr)
library(readr)
library(argparser)

p <- arg_parser("This script takes the LIFT file and produces a CSV of the entry table")
p <- add_argument(p, "LIFT_file", 
                  help="SIL Flex lexicon LIFT file")
argv <- parse_args(p)
doc = read_xml(argv$LIFT_file)

# iterate entries once and extract lexical-unit forms + Plural Noun forms
entries <- xml_find_all(doc, ".//entry")

# helper function to extract elements with forms and their lang attributes
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
        !!value_col := xml_text(.x)
      ))
    })
}

# helper function to extract elements with an attribute and their forms
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
          !!value_col := xml_text(.x)
        ))
      })
    })
}

# extract lexical-unit forms for each writing system and also get the entry's 
# dateCreated and dateModified attributes
# first stage: extract entry-level metadata only
entry_meta <- tibble(
  entry_id = map_chr(entries, ~xml_attr(.x, "guid"), .progress = FALSE),
  dateCreated = map_chr(entries, ~xml_attr(.x, "dateCreated"), .progress = FALSE),
  dateModified = map_chr(entries, ~xml_attr(.x, "dateModified"), .progress = FALSE)
)
# second stage: extract lexical-unit forms
lex_long <- extract_multitext_element(entries, "./lexical-unit/form")

# since the table is in a long form with a row for each writing system, we 
# need to pivot wider
lex_wide <- lex_long |>
  pivot_wider(
    id_cols = entry_id,
    names_from = lang,
    values_from = text
  )

# extract all custom <field> elements (type attribute) and their <form> children
fields_long <- extract_multitext_with_attribute(entries, "./field", "type", "field_text")

# pivot so each (field_type, writing-system) becomes a wide column
# names_glue uses both field name (field_type) and writing system (lang)
fields_wide <- fields_long |>
  pivot_wider(
    id_cols = entry_id,
    names_from = c(type, lang),
    names_glue = "{type}_{lang}",
    values_from = field_text
  )

# extract citation forms for each writing system
citations_long <- extract_multitext_element(entries, "./citation/form")

# pivot citations wider so each writing system becomes its own column
citations_wide <- citations_long |>
  pivot_wider(
    id_cols = entry_id,
    names_from = lang,
    values_from = text,
    names_glue = "citation_{lang}"
  )

# join with these extra fields our existing lexeme table
combined <- entry_meta |>
  left_join(lex_wide, by = "entry_id") |>
  left_join(fields_wide, by = "entry_id") |>
  left_join(citations_wide, by = "entry_id")

# write CSV entry_table to stdout
output <- if(nrow(combined) == 0) "" else format_csv(combined, na = "")
cat(output)

