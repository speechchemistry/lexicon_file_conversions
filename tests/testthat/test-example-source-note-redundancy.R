library(xml2)
library(tibble)

# example/@source and note[@type="reference"] are the same FLEx field
# ("Reference") written twice by the exporter, so the CSV carries both columns
# rather than collapsing them (SPEC.md's Example table / Redundant columns).
# In Sena3.lift the two agree on all 744 examples that have them, which is
# exactly why a user desyncing them in the CSV would otherwise be silent:
# no fixture reaches this shape, and stderr is not snapshotted by the
# end-to-end tests. These are non-snapshot unit tests for that gap, following
# test-multitext-span-markup.R.
one_sense_doc <- function() {
  read_xml(paste0(
    "<lift version=\"0.13\">",
    "<entry guid=\"1ba747b1-0000-0000-0000-000000000000\">",
    "<sense id=\"a1b2c3d4-0000-0000-0000-000000000000\"/>",
    "</entry></lift>"
  ))
}

SENSE_ID <- "a1b2c3d4-0000-0000-0000-000000000000"

example_row <- function(source, note) {
  tibble(sense_guid = SENSE_ID, example_source = source, note_reference_en = note)
}

attach_quietly <- function(doc, tbl) {
  suppressWarnings(suppressMessages(attach_examples_to_lift(doc, tbl)))
}

test_that("disagreeing example_source and note_reference warn, naming the sense", {
  expect_warning(
    suppressMessages(attach_examples_to_lift(one_sense_doc(), example_row("Ref A", "Ref B"))),
    SENSE_ID
  )
})

test_that("both disagreeing values are still emitted unchanged", {
  doc <- one_sense_doc()
  attach_quietly(doc, example_row("Ref A", "Ref B"))

  example_node <- xml_find_first(doc, ".//example")
  expect_equal(xml_attr(example_node, "source"), "Ref A")
  expect_equal(
    xml_text(xml_find_first(example_node, "./note[@type='reference']/form/text")),
    "Ref B"
  )
})

test_that("agreeing values do not warn (the shape all 744 in Sena3.lift have)", {
  expect_no_warning(
    suppressMessages(attach_examples_to_lift(one_sense_doc(), example_row("Ref A", "Ref A")))
  )
})

test_that("one side blank does not warn — absence is not disagreement", {
  expect_no_warning(
    suppressMessages(attach_examples_to_lift(one_sense_doc(), example_row("Ref A", NA_character_)))
  )
  expect_no_warning(
    suppressMessages(attach_examples_to_lift(one_sense_doc(), example_row(NA_character_, "Ref B")))
  )
})

test_that("a non-reference typed note is never compared against example_source", {
  tbl <- tibble(
    sense_guid = SENSE_ID,
    example_source = "Ref A",
    note_phonology_en = "something else entirely"
  )
  expect_no_warning(suppressMessages(attach_examples_to_lift(one_sense_doc(), tbl)))
})
