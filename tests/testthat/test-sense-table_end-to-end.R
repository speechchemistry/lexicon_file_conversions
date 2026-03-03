test_that("sense-table_end-to-end", {
  input <- "../data/lift2csv_sense-table/input/Sena3_gloss_initial_b.lift"
  expected <- readLines("../data/lift2csv_sense-table/expected/Sena3_gloss_initial_b.csv")

  result <- system2(
    "Rscript",
    args = c("../../scripts/lift2csv_sense-table.R", input),
    stdout = TRUE
  )

  expect_equal(result, expected)
})

test_that("sense-table_end-to-end_empty-lexicon", {
  input <- "../data/lift2csv_sense-table/input/lela-teli-empty-lexicon.lift"
  expected <- readLines("../data/lift2csv_sense-table/expected/lela-teli-empty-lexicon.csv")

  result <- system2(
    "Rscript",
    args = c("../../scripts/lift2csv_sense-table.R", input),
    stdout = TRUE
  )

  expect_equal(result, expected)
})
