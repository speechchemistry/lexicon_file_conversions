library(tibble)

# Unit-level (no subprocess, no snapshot) characterisation tests for reader
# shapes that no fixture contains, ahead of plans/old/refactor-dedupe-and-speedup.md's
# generic reader extractors phase:
#   * the "more than one, keep the first" warnings for an entry's morph-type
#     trait and a pronunciation's <media> and location trait -- no fixture
#     triggers any of them, so the golden-master check can't see them either;
#   * media-label alignment when a pronunciation without <media> comes before
#     one with a labelled <media> -- every fixture's pronunciations either all
#     have media or none do, so a label landing on the wrong row would go
#     unnoticed.
# Each test writes an inline LIFT document to a temp file and calls the
# table's registry read_fn, which takes a path.

ENTRY_A <- "aaaaaaaa-0000-0000-0000-000000000000"

lift_file <- function(entry_body, env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".lift", .local_envir = env)
  writeLines(c(
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    "<lift version=\"0.13\">",
    sprintf("<entry guid=\"%s\" id=\"a_%s\">", ENTRY_A, ENTRY_A),
    entry_body,
    "</entry>",
    "</lift>"
  ), path)
  path
}

test_that("two morph-type traits on an entry warn with both values and keep the first", {
  path <- lift_file(c(
    "<trait name=\"morph-type\" value=\"stem\"/>",
    "<trait name=\"morph-type\" value=\"root\"/>"
  ))

  expect_warning(
    entries <- entry_table(path),
    paste0(ENTRY_A, ".*2 'morph-type' traits.*stem, root")
  )
  expect_equal(entries$morph_type, "stem")
})

test_that("two <media> on a pronunciation warn with both hrefs and keep the first href and its label", {
  path <- lift_file(c(
    "<pronunciation>",
    "<media href=\"first.wav\"><label><form lang=\"en\"><text>first label</text></form></label></media>",
    "<media href=\"second.wav\"><label><form lang=\"en\"><text>second label</text></form></label></media>",
    "</pronunciation>"
  ))

  expect_warning(
    pronunciations <- pronunciation_table(path),
    paste0(ENTRY_A, ".*2 media elements.*first\\.wav, second\\.wav")
  )
  expect_equal(pronunciations$media_href, "first.wav")
  expect_equal(pronunciations$media_label_en, "first label")
})

test_that("two location traits on a pronunciation warn with both values and keep the first", {
  path <- lift_file(c(
    "<pronunciation>",
    "<trait name=\"location\" value=\"Village A\"/>",
    "<trait name=\"location\" value=\"Village B\"/>",
    "</pronunciation>"
  ))

  expect_warning(
    pronunciations <- pronunciation_table(path),
    paste0(ENTRY_A, ".*2 'location' traits.*Village A, Village B")
  )
  expect_equal(pronunciations$location, "Village A")
})

test_that("a media label lands on its own pronunciation's row when an earlier pronunciation has no media", {
  path <- lift_file(c(
    "<pronunciation><form lang=\"seh-fonipa\"><text>no media</text></form></pronunciation>",
    "<pronunciation><form lang=\"seh-fonipa\"><text>labelled</text></form>",
    "<media href=\"labelled.wav\"><label><form lang=\"en\"><text>the label</text></form></label></media>",
    "</pronunciation>",
    "<pronunciation><form lang=\"seh-fonipa\"><text>unlabelled</text></form>",
    "<media href=\"unlabelled.wav\"/>",
    "</pronunciation>"
  ))

  pronunciations <- pronunciation_table(path)

  expect_equal(pronunciations$`pronunciation_seh-fonipa`, c("no media", "labelled", "unlabelled"))
  expect_equal(pronunciations$media_href, c(NA, "labelled.wav", "unlabelled.wav"))
  expect_equal(pronunciations$media_label_en, c(NA, "the label", NA))
})
