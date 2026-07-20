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
          !!value_col := xml_text(.x)
        ))
      })
    })
}