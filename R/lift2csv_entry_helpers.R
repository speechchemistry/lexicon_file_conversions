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