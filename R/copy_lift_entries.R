copy_lift_entries <- function(source_lift, guid_source = NULL, log_progress = TRUE) {
  # Stage 1: Validate required source input.
  if (missing(source_lift) || is.null(source_lift) || !nzchar(source_lift)) {
    stop("source_lift is required", call. = FALSE)
  }

  if (!file.exists(source_lift)) {
    stop(sprintf("Source file not found: %s", source_lift), call. = FALSE)
  }

  if (log_progress) {
    cat(sprintf("Reading header from %s...\n", source_lift), file = stderr())
  }

  # Stage 2: Load and normalize source XML content.
  source_content <- readr::read_file(source_lift) |>
    stringr::str_remove_all("\r")
  source_doc <- xml2::read_xml(source_content)

  # Stage 3: Extract source envelope pieces used in output assembly.
  lift_prefix <- stringr::str_extract(source_content, stringr::regex("(?s)^.*?<lift\\b[^>]*>"))
  if (is.na(lift_prefix)) {
    stop("No opening <lift> tag found in source file", call. = FALSE)
  }

  header <- stringr::str_extract(source_content, stringr::regex("(?s)<header>.*?</header>"))
  if (is.na(header)) {
    stop("No <header> section found in source file", call. = FALSE)
  }

  if (log_progress) {
    source_label <- if (is.null(guid_source) || identical(guid_source, "-")) "stdin" else guid_source
    cat(sprintf("Reading GUIDs from %s...\n", source_label), file = stderr())
  }

  # Stage 4: Read and clean GUID input lines.
  if (is.null(guid_source) || identical(guid_source, "-")) {
    stdin_con <- file("stdin", open = "r")
    on.exit(close(stdin_con), add = TRUE)
    lines <- readLines(con = stdin_con, warn = FALSE)
  } else {
    lines <- readr::read_lines(guid_source, lazy = FALSE)
  }
  guids <- trimws(lines)
  guids <- guids[nzchar(guids)]

  if (length(guids) == 0) {
    stop("No GUIDs provided", call. = FALSE)
  }

  if (log_progress) {
    cat(sprintf("Found %d GUID(s)\n", length(guids)), file = stderr())
  }

  # Stage 5: Generate one run-level timestamp for all output entries.
  # Generate one timestamp per run so all copied entries share the same
  # dateModified value for deterministic run-level behavior.
  current_time <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  # Stage 6: Validate that every requested GUID exists in the source.
  guid_index <- tibble::tibble(
    idx = seq_along(guids),
    guid = guids,
    exists_in_source = vapply(guids, function(g) {
      node <- xml2::xml_find_first(source_doc, sprintf('.//entry[@guid="%s"]', g))
      !inherits(node, "xml_missing")
    }, logical(1))
  )

  missing_guid_row <- dplyr::filter(guid_index, !.data$exists_in_source) |> dplyr::slice(1)
  if (nrow(missing_guid_row) > 0) {
    stop(sprintf("GUID not found in source file: %s", missing_guid_row$guid[[1]]), call. = FALSE)
  }

  if (log_progress) {
    purrr::walk2(guid_index$idx, guid_index$guid, ~{
      cat(sprintf("[%d/%d] Extracting entry: %s...\n", .x, nrow(guid_index), .y), file = stderr())
    })
  }

  # Stage 7: Extract each entry block and update dateModified.
  # Preserve source formatting by extracting each full <entry>...</entry>
  # block from the original content and only replacing dateModified.
  entries <- purrr::map_chr(guid_index$guid, ~{
    guid <- .x
    guid_escaped <- stringr::str_replace_all(guid, "([.+*?^${}\\[\\]|\\\\\\(\\)])", "\\\\\\1")
    entry_start <- stringr::str_locate(
      source_content,
      stringr::regex(sprintf('<entry[^>]*guid="%s"[^>]*>', guid_escaped))
    )
    if (is.na(entry_start[1])) {
      stop(sprintf("GUID not found in source file: %s", guid), call. = FALSE)
    }

    start_pos <- entry_start[1]
    content_tail <- substr(source_content, start_pos, nchar(source_content))

    # Depth counting ensures we return the correct closing </entry> for the
    # matched entry start tag, not an inner or later tag.
    token_matches <- gregexpr("</entry>|<entry\\b[^>]*(?<!/)>", content_tail, perl = TRUE)[[1]]
    if (token_matches[1] == -1) {
      stop(sprintf("Could not find closing tag for entry with GUID: %s", guid), call. = FALSE)
    }

    token_lengths <- attr(token_matches, "match.length")
    depth <- 0
    end_pos <- NA_integer_

    for (idx in seq_along(token_matches)) {
      token_pos <- token_matches[idx]
      token_len <- token_lengths[idx]
      token <- substr(content_tail, token_pos, token_pos + token_len - 1)

      if (startsWith(token, "</entry>")) {
        depth <- depth - 1
      } else {
        depth <- depth + 1
      }

      if (depth == 0) {
        end_pos <- start_pos + token_pos + token_len - 2
        break
      }
    }

    if (is.na(end_pos)) {
      stop(sprintf("Could not find closing tag for entry with GUID: %s", guid), call. = FALSE)
    }

    entry_xml <- substr(source_content, start_pos, end_pos)
    stringr::str_replace(
      entry_xml,
      stringr::regex('(dateModified=")[^"]*(")'),
      sprintf('\\1%s\\2', current_time)
    )
  })

  # Stage 8: Assemble final LIFT document output in order.
  output <- c(
    lift_prefix,
    header,
    "",
    paste(entries, collapse = "\n\n"),
    "",
    '</lift>'
  )

  final_xml <- paste(output, collapse = "\n") |>
    stringr::str_remove_all("\r")

  list(
    xml = final_xml,
    count = length(entries)
  )
}
