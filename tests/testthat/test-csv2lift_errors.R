library(xml2)
library(tibble)

# Unit-level (no subprocess, no snapshot) characterisation tests for the
# csv2lift error paths no fixture reaches: every foreign-key lookup, the
# subsense-before-parent ordering rule, the traits table's owner/owner_index
# checks, and duplicate entry_lift_id. Added ahead of
# plans/refactor-dedupe-and-speedup.md's writer node lookup phase, which
# rewrites every one of these lookups.
#
# Each test calls a registry attach_fn and matches only the stable parts of
# the message (the offending value, the column, the table it should have been
# found in), not the full wording -- see the plan's characterisation tests
# phase for why.

ENTRY_A <- "aaaaaaaa-0000-0000-0000-000000000000"
ENTRY_B <- "bbbbbbbb-0000-0000-0000-000000000000"
ENTRY_NO_LIFT_ID <- "cccccccc-0000-0000-0000-000000000000"
SENSE_A <- "5a5a5a5a-0000-0000-0000-000000000000"
SUBSENSE_A <- "5b5b5b5b-0000-0000-0000-000000000000"
MISSING <- "deadbeef-0000-0000-0000-000000000000"

# The classifiers log one line per column to stderr via cat(), which
# suppressMessages() doesn't catch.
quietly <- function(expr) {
  utils::capture.output(result <- expr, type = "message")
  result
}

# Entries A and B (with entry_lift_ids) plus one with no entry_lift_id; entry A
# has one sense, which has one subsense; entry B has one variant and one
# entry-relation pointing at A, so owner_index 1 is valid for both owners.
base_doc <- function() {
  doc <- quietly(entry_table_to_lift(tibble(
    entry_id = c(ENTRY_A, ENTRY_B, ENTRY_NO_LIFT_ID),
    entry_lift_id = c("a_1", "b_2", NA),
    seh = c("a", "b", "c")
  )))
  doc <- quietly(attach_senses_to_lift(doc, tibble(
    sense_guid = c(SENSE_A, SUBSENSE_A),
    entry_id = c(ENTRY_A, ENTRY_A),
    grammatical_info = NA_character_,
    parent_sense_guid = c(NA, SENSE_A)
  )))
  doc <- quietly(attach_variants_to_lift(doc, tibble(entry_id = ENTRY_B, variant_seh = "bb")))
  quietly(attach_entry_relations_to_lift(doc, tibble(
    entry_id = ENTRY_B, relation_type = "Compare", relation_ref = ENTRY_A
  )))
}

test_that("every entry-keyed writer errors on an entry_id not in the entry table", {
  attach_with_missing_entry <- list(
    pronunciations = function(doc) attach_pronunciations_to_lift(doc, tibble(entry_id = MISSING, pronunciation_seh = "x")),
    variants = function(doc) attach_variants_to_lift(doc, tibble(entry_id = MISSING, variant_seh = "x")),
    senses = function(doc) attach_senses_to_lift(doc, tibble(sense_guid = "new-sense", entry_id = MISSING, grammatical_info = NA)),
    entry_relations = function(doc) attach_entry_relations_to_lift(doc, tibble(entry_id = MISSING, relation_type = "Compare", relation_ref = ENTRY_A)),
    etymologies = function(doc) attach_etymologies_to_lift(doc, tibble(entry_id = MISSING, etymology_type = "proto")),
    variant_traits = function(doc) attach_traits_to_lift(doc, tibble(entry_id = MISSING, owner = "variant", owner_index = "1", trait_name = "n", trait_value = "v")),
    entry_relation_traits = function(doc) attach_traits_to_lift(doc, tibble(entry_id = MISSING, owner = "entry-relation", owner_index = "1", trait_name = "n", trait_value = "v"))
  )

  for (name in names(attach_with_missing_entry)) {
    expect_error(
      quietly(attach_with_missing_entry[[name]](base_doc())),
      paste0("entry_id '", MISSING, "'.*not found in the entry table"),
      info = name
    )
  }
})

test_that("an entry-relation's relation_ref must name an entry in the entry table", {
  expect_error(
    quietly(attach_entry_relations_to_lift(base_doc(), tibble(
      entry_id = ENTRY_A, relation_type = "Compare", relation_ref = MISSING
    ))),
    paste0("relation_ref '", MISSING, "'.*not found in the entry table")
  )
})

test_that("an entry-relation's target must have an entry_lift_id to write as @ref", {
  expect_error(
    quietly(attach_entry_relations_to_lift(base_doc(), tibble(
      entry_id = ENTRY_A, relation_type = "Compare", relation_ref = ENTRY_NO_LIFT_ID
    ))),
    ENTRY_NO_LIFT_ID
  )
})

test_that("a blank entry-relation relation_ref warns and is written as ref=\"\"", {
  doc <- base_doc()
  expect_warning(
    quietly(attach_entry_relations_to_lift(doc, tibble(
      entry_id = ENTRY_A, relation_type = "_component-lexeme", relation_ref = NA_character_
    ))),
    "blank relation_ref"
  )
  relation <- xml_find_first(xml_root(doc), sprintf(".//entry[@guid='%s']/relation", ENTRY_A))
  expect_equal(xml_attr(relation, "ref"), "")
})

test_that("every top-level-sense-keyed writer errors on a sense_guid not in the sense table", {
  attach_with_missing_sense <- list(
    reversals = function(doc) attach_reversals_to_lift(doc, tibble(sense_guid = MISSING, reversal_en = "x")),
    sense_relations = function(doc) attach_sense_relations_to_lift(doc, tibble(sense_guid = MISSING, relation_type = "Synonyms", relation_ref = SENSE_A)),
    sense_traits = function(doc) attach_traits_to_lift(doc, tibble(sense_guid = MISSING, owner = "sense", trait_name = "n", trait_value = "v")),
    grammatical_info_traits = function(doc) attach_traits_to_lift(doc, tibble(sense_guid = MISSING, owner = "grammatical-info", trait_name = "n", trait_value = "v"))
  )

  for (name in names(attach_with_missing_sense)) {
    expect_error(
      quietly(attach_with_missing_sense[[name]](base_doc())),
      paste0("sense_guid '", MISSING, "'.*not found in the sense table"),
      info = name
    )
  }
})

test_that("a sense-relation's relation_ref must name a sense in the sense table", {
  expect_error(
    quietly(attach_sense_relations_to_lift(base_doc(), tibble(
      sense_guid = SENSE_A, relation_type = "Synonyms", relation_ref = MISSING
    ))),
    paste0("relation_ref '", MISSING, "'.*not found in the sense table")
  )
})

# SPEC.md's Not Yet Specified: subsense-owned reversals, relations and traits
# are deliberately unsupported, so these writers look up top-level <sense>
# only. Update this test when SPEC.md widens any of them.
test_that("reversals, sense-relations and sense traits do not attach to a subsense", {
  attach_to_subsense <- list(
    reversals = function(doc) attach_reversals_to_lift(doc, tibble(sense_guid = SUBSENSE_A, reversal_en = "x")),
    sense_relations = function(doc) attach_sense_relations_to_lift(doc, tibble(sense_guid = SUBSENSE_A, relation_type = "Synonyms", relation_ref = SENSE_A)),
    sense_traits = function(doc) attach_traits_to_lift(doc, tibble(sense_guid = SUBSENSE_A, owner = "sense", trait_name = "n", trait_value = "v"))
  )

  for (name in names(attach_to_subsense)) {
    expect_error(
      quietly(attach_to_subsense[[name]](base_doc())),
      paste0("'", SUBSENSE_A, "'.*not found in the sense table"),
      info = name
    )
  }
})

test_that("examples attach to a subsense but error on a sense_guid in neither", {
  doc <- base_doc()
  quietly(attach_examples_to_lift(doc, tibble(sense_guid = SUBSENSE_A, example_seh = "ex")))
  expect_length(xml_find_all(xml_root(doc), sprintf(".//subsense[@id='%s']/example", SUBSENSE_A)), 1)

  expect_error(
    quietly(attach_examples_to_lift(base_doc(), tibble(sense_guid = MISSING, example_seh = "ex"))),
    paste0("sense_guid '", MISSING, "'.*not found in the sense table")
  )
})

# SPEC.md's Sense Table: a parent row must precede its subsense's row.
test_that("a subsense row before its parent row errors on the parent_sense_guid", {
  doc <- quietly(entry_table_to_lift(tibble(entry_id = ENTRY_A, seh = "a")))
  expect_error(
    quietly(attach_senses_to_lift(doc, tibble(
      sense_guid = c(SUBSENSE_A, SENSE_A),
      entry_id = c(ENTRY_A, ENTRY_A),
      grammatical_info = NA_character_,
      parent_sense_guid = c(SENSE_A, NA)
    ))),
    paste0("parent_sense_guid '", SENSE_A, "'.*not found in the sense table")
  )
})

test_that("a variant or entry-relation trait's owner_index must point at an existing element", {
  bad_indexes <- c(blank = NA, non_integer = "x", zero = "0", too_high = "2")

  for (owner in c("variant", "entry-relation")) {
    for (case in names(bad_indexes)) {
      expect_error(
        quietly(attach_traits_to_lift(base_doc(), tibble(
          entry_id = ENTRY_B, owner = owner, owner_index = bad_indexes[[case]],
          trait_name = "n", trait_value = "v"
        ))),
        paste0("owner = '", owner, "'.*owner_index.*", ENTRY_B),
        info = paste(owner, case)
      )
    }
  }
})

test_that("a variant or entry-relation trait with no owner_index column at all errors", {
  for (owner in c("variant", "entry-relation")) {
    expect_error(
      quietly(attach_traits_to_lift(base_doc(), tibble(
        entry_id = ENTRY_B, owner = owner, trait_name = "n", trait_value = "v"
      ))),
      paste0("owner = '", owner, "'.*owner_index"),
      info = owner
    )
  }
})

test_that("a valid owner_index attaches the trait to that element", {
  doc <- base_doc()
  quietly(attach_traits_to_lift(doc, tibble(
    entry_id = ENTRY_B, owner = c("variant", "entry-relation"), owner_index = "1",
    trait_name = c("morph-type", "complex-form-type"), trait_value = c("stem", "Compound")
  )))
  entry_b <- sprintf(".//entry[@guid='%s']", ENTRY_B)
  expect_equal(xml_attr(xml_find_first(xml_root(doc), paste0(entry_b, "/variant/trait")), "value"), "stem")
  expect_equal(xml_attr(xml_find_first(xml_root(doc), paste0(entry_b, "/relation/trait")), "value"), "Compound")
})

test_that("an unrecognised trait owner errors, naming the owner", {
  expect_error(
    quietly(attach_traits_to_lift(base_doc(), tibble(
      entry_id = ENTRY_A, owner = "pronunciation", trait_name = "n", trait_value = "v"
    ))),
    "unrecognised owner 'pronunciation'"
  )
})

test_that("a duplicate entry_lift_id errors, naming the duplicate", {
  expect_error(
    quietly(entry_table_to_lift(tibble(
      entry_id = c(ENTRY_A, ENTRY_B), entry_lift_id = c("same_1", "same_1"), seh = c("a", "b")
    ))),
    "Duplicate entry_lift_id.*same_1"
  )
})
