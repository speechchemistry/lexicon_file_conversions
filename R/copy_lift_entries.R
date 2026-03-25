escape_regex <- function(x) {
  gsub("([][{}()+*^$|\\?.])", "\\\\\\1", x)
}

get_header_from_source <- function(source_content) {
  header_match <- regexpr("(?s)(<header>.*?</header>)", source_content, perl = TRUE)
  if (header_match[1] == -1) {
    stop("No <header> section found in source file", call. = FALSE)
  }

  regmatches(source_content, header_match)[[1]]
}

get_lift_prefix_from_source <- function(source_content) {
  prefix_match <- regexpr("(?s)^(.*?<lift\\b[^>]*>)", source_content, perl = TRUE)
  if (prefix_match[1] == -1) {
    stop("No opening <lift> tag found in source file", call. = FALSE)
  }

  regmatches(source_content, prefix_match)[[1]]
}

find_entry_by_guid <- function(source_content, guid) {
  guid_escaped <- escape_regex(guid)
  entry_start <- regexpr(
    sprintf('<entry[^>]*guid="%s"[^>]*>', guid_escaped),
    source_content,
    perl = TRUE
  )

  if (entry_start[1] == -1) {
    stop(sprintf("GUID not found in source file: %s", guid), call. = FALSE)
  }

  start_pos <- entry_start[1]
  content_tail <- substr(source_content, start_pos, nchar(source_content))

  # Scan only entry open/close tokens and use depth counting to return the
  # full <entry>...</entry> block even if nested XML elements are present.
  token_matches <- gregexpr("</entry>|<entry\\b[^>]*(?<!/)>", content_tail, perl = TRUE)[[1]]
  if (token_matches[1] == -1) {
    stop(sprintf("Could not find closing tag for entry with GUID: %s", guid), call. = FALSE)
  }

  token_lengths <- attr(token_matches, "match.length")
  depth <- 0

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
      return(substr(source_content, start_pos, end_pos))
    }
  }

  stop(sprintf("Could not find closing tag for entry with GUID: %s", guid), call. = FALSE)
}

update_datemodified <- function(entry_xml, new_timestamp) {
  sub(
    '(dateModified=")[^"]*(")',
    sprintf('\\1%s\\2', new_timestamp),
    entry_xml,
    perl = TRUE
  )
}

read_guids <- function(input_source = NULL) {
  if (is.null(input_source) || identical(input_source, "-")) {
    lines <- readLines(file("stdin", open = "r"), warn = FALSE, encoding = "UTF-8")
  } else {
    lines <- readLines(input_source, warn = FALSE, encoding = "UTF-8")
  }

  trimmed <- trimws(lines)
  trimmed[nzchar(trimmed)]
}

copy_lift_entries <- function(source_lift, guid_source = NULL, log_progress = TRUE) {
  if (missing(source_lift) || is.null(source_lift) || !nzchar(source_lift)) {
    stop("source_lift is required", call. = FALSE)
  }

  if (!file.exists(source_lift)) {
    stop(sprintf("Source file not found: %s", source_lift), call. = FALSE)
  }

  source_content <- paste(readLines(source_lift, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  if (log_progress) {
    cat(sprintf("Reading header from %s...\n", source_lift), file = stderr())
  }
  lift_prefix <- get_lift_prefix_from_source(source_content)
  header <- get_header_from_source(source_content)

  if (log_progress) {
    source_label <- if (is.null(guid_source) || identical(guid_source, "-")) "stdin" else guid_source
    cat(sprintf("Reading GUIDs from %s...\n", source_label), file = stderr())
  }

  guids <- read_guids(guid_source)
  if (length(guids) == 0) {
    stop("No GUIDs provided", call. = FALSE)
  }

  if (log_progress) {
    cat(sprintf("Found %d GUID(s)\n", length(guids)), file = stderr())
  }

  # Generate one timestamp per run so all copied entries share the same
  # dateModified value for deterministic run-level behavior.
  current_time <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  entries <- character(length(guids))
  for (i in seq_along(guids)) {
    guid <- guids[[i]]
    if (log_progress) {
      cat(sprintf("[%d/%d] Extracting entry: %s...\n", i, length(guids), guid), file = stderr())
    }
    entry <- find_entry_by_guid(source_content, guid)
    entries[[i]] <- update_datemodified(entry, current_time)
  }

  output <- c(
    lift_prefix,
    header,
    "",
    paste(entries, collapse = "\n\n"),
    "",
    '</lift>'
  )

  list(
    xml = paste(output, collapse = "\n"),
    count = length(entries)
  )
}
