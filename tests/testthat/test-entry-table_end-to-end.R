test_that("entry-table_end-to-end", {
  input <- "../data/lift2csv_entry-table/input/Sena3.lift"
  expected <- readLines("../data/lift2csv_entry-table/expected/Sena3.csv")

  result <- system2(
    "Rscript",
    args = c("../../scripts/lift2csv_entry-table.R", input),
    stdout = TRUE
  )

  expect_equal(result, expected)
})
