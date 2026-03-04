test_that("join-sense-entry-table_end-to-end", {
  input <- "../data/lift2csv_join-sense-entry-table/input/Sena3.lift"
  expected <- readLines("../data/lift2csv_join-sense-entry-table/expected/Sena3_join-sense-entry-table.csv")

  result <- system2(
    "Rscript",
    args = c("../../scripts/lift2csv_join-sense-entry-table.R", input),
    stdout = TRUE
  )

  expect_equal(result, expected)
})
