library(xml2)
library(tibble)

# Unit-level (no subprocess, no snapshot) characterisation tests for how
# csv2lift reads CSV column names, ahead of plans/refactor-dedupe-and-speedup.md's
# table-driven classifier phase. Fixtures only ever contain correctly named
# columns, so nothing else pins:
#   * the unknown-column rule: a table that supports <field> treats an unknown
#     column as a custom field, a table that doesn't stops with an error;
#   * the ordering rules that keep typed notes and metadata columns from being
#     swallowed by a broader pattern.
# Tests go through each table's attach_fn and check the LIFT it writes, never
# the classify_*_columns() helpers, which the refactor replaces.

ENTRY_A <- "aaaaaaaa-0000-0000-0000-000000000000"
SENSE_A <- "5a5a5a5a-0000-0000-0000-000000000000"

# The classifiers log one line per column to stderr via cat(), which
# suppressMessages() doesn't catch.
quietly <- function(expr) {
  utils::capture.output(result <- expr, type = "message")
  result
}

entry_doc <- function() {
  quietly(entry_table_to_lift(tibble(entry_id = ENTRY_A, seh = "a")))
}

sense_doc <- function() {
  quietly(attach_senses_to_lift(entry_doc(), tibble(
    sense_guid = SENSE_A, entry_id = ENTRY_A, grammatical_info = NA_character_
  )))
}

form_text <- function(node, xpath) {
  xml_text(xml_find_all(node, paste0(xpath, "/text")))
}

test_that("entries: unknown, note, typed note and citation columns each map to their own element", {
  doc <- quietly(entry_table_to_lift(tibble(
    entry_id = ENTRY_A,
    seh = "a",
    Plural_seh = "plural form",
    citation_seh = "citation form",
    note_en = "plain note",
    note_restrictions_en = "restriction note"
  )))
  entry <- xml_find_first(xml_root(doc), ".//entry")

  expect_equal(form_text(entry, "./lexical-unit/form[@lang='seh']"), "a")
  expect_equal(form_text(entry, "./field[@type='Plural']/form[@lang='seh']"), "plural form")
  expect_equal(form_text(entry, "./citation/form[@lang='seh']"), "citation form")
  expect_equal(form_text(entry, "./note[not(@type)]/form[@lang='en']"), "plain note")
  expect_equal(form_text(entry, "./note[@type='restrictions']/form[@lang='en']"), "restriction note")
  expect_length(xml_find_all(entry, "./field[@type='note_restrictions' or @type='note' or @type='citation']"), 0)
})

test_that("entries: a custom field's type is everything before the last underscore", {
  doc <- quietly(entry_table_to_lift(tibble(entry_id = ENTRY_A, `Parsing Note_en` = "x", `a_b_c_en` = "y")))
  entry <- xml_find_first(xml_root(doc), ".//entry")

  expect_equal(form_text(entry, "./field[@type='Parsing Note']/form[@lang='en']"), "x")
  expect_equal(form_text(entry, "./field[@type='a_b_c']/form[@lang='en']"), "y")
})

test_that("senses: unknown, gloss, definition, general note and typed note columns each map to their own element", {
  doc <- quietly(attach_senses_to_lift(entry_doc(), tibble(
    sense_guid = SENSE_A,
    entry_id = ENTRY_A,
    grammatical_info = NA_character_,
    gloss_en = "gloss",
    definition_en = "definition",
    general_note_en = "general note",
    note_phonology_en = "phonology note",
    `scientific-name_en` = "Homo sapiens"
  )))
  sense <- xml_find_first(xml_root(doc), ".//sense")

  expect_equal(form_text(sense, "./gloss[@lang='en']"), "gloss")
  expect_equal(form_text(sense, "./definition/form[@lang='en']"), "definition")
  expect_equal(form_text(sense, "./note[not(@type)]/form[@lang='en']"), "general note")
  expect_equal(form_text(sense, "./note[@type='phonology']/form[@lang='en']"), "phonology note")
  expect_equal(form_text(sense, "./field[@type='scientific-name']/form[@lang='en']"), "Homo sapiens")
  expect_length(xml_find_all(sense, "./field[starts-with(@type, 'note') or starts-with(@type, 'general')]"), 0)
})

test_that("etymologies: unknown, etymon form and gloss columns each map to their own element", {
  doc <- quietly(attach_etymologies_to_lift(entry_doc(), tibble(
    entry_id = ENTRY_A,
    etymology_type = "proto",
    etymology_seh = "etymon",
    gloss_en = "etymon gloss",
    comment_en = "a comment"
  )))
  etymology <- xml_find_first(xml_root(doc), ".//etymology")

  expect_equal(xml_attr(etymology, "type"), "proto")
  expect_equal(form_text(etymology, "./form[@lang='seh']"), "etymon")
  expect_equal(form_text(etymology, "./gloss[@lang='en']"), "etymon gloss")
  expect_equal(form_text(etymology, "./field[@type='comment']/form[@lang='en']"), "a comment")
})

test_that("pronunciations: unknown, form, media label and location columns each map to their own element", {
  doc <- quietly(attach_pronunciations_to_lift(entry_doc(), tibble(
    entry_id = ENTRY_A,
    `pronunciation_seh-fonipa` = "a",
    media_href = "a.wav",
    media_label_en = "label",
    `tone_seh-fonipa` = "H",
    location = "Village"
  )))
  pronunciation <- xml_find_first(xml_root(doc), ".//pronunciation")

  expect_equal(form_text(pronunciation, "./form[@lang='seh-fonipa']"), "a")
  expect_equal(xml_attr(xml_find_first(pronunciation, "./media"), "href"), "a.wav")
  expect_equal(form_text(pronunciation, "./media/label/form[@lang='en']"), "label")
  expect_equal(form_text(pronunciation, "./field[@type='tone']/form[@lang='seh-fonipa']"), "H")
  expect_equal(xml_attr(xml_find_first(pronunciation, "./trait[@name='location']"), "value"), "Village")
})

test_that("examples: metadata and typed-note columns are not read as a form in some language", {
  doc <- sense_doc()
  quietly(attach_examples_to_lift(doc, tibble(
    sense_guid = SENSE_A,
    example_source = "Ref A",
    example_seh = "sentence",
    translation_type = "Free translation",
    translation_en = "translation",
    note_reference_en = "Ref A"
  )))
  example <- xml_find_first(xml_root(doc), ".//example")

  expect_equal(xml_attr(example, "source"), "Ref A")
  expect_equal(form_text(example, "./form[@lang='seh']"), "sentence")
  expect_equal(xml_attr(xml_find_first(example, "./translation"), "type"), "Free translation")
  expect_equal(form_text(example, "./translation/form[@lang='en']"), "translation")
  expect_equal(form_text(example, "./note[@type='reference']/form[@lang='en']"), "Ref A")
  expect_length(xml_find_all(example, ".//form[@lang='source' or @lang='type' or @lang='reference_en']"), 0)
})

test_that("tables without <field> support stop on an unknown column, naming it", {
  attach_with_unknown_column <- list(
    example = function() attach_examples_to_lift(sense_doc(), tibble(sense_guid = SENSE_A, mystery_en = "x")),
    variant = function() attach_variants_to_lift(entry_doc(), tibble(entry_id = ENTRY_A, mystery_en = "x")),
    reversal = function() attach_reversals_to_lift(sense_doc(), tibble(sense_guid = SENSE_A, mystery_en = "x"))
  )

  for (table in names(attach_with_unknown_column)) {
    expect_error(
      quietly(attach_with_unknown_column[[table]]()),
      paste0("Unrecognized ", table, " column 'mystery_en'"),
      info = table
    )
  }
})
