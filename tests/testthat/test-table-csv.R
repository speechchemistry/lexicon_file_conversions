library(tibble)

# Non-snapshot unit tests for drop_empty_columns()/format_table_csv()
# (R/table_csv.R) -- see plans/prune-empty-columns.md's E1. No subprocess,
# no snapshot: these are plain function calls against in-memory tibbles.

test_that("an all-NA column is dropped", {
  t <- tibble(a = c("x", "y"), b = c(NA_character_, NA_character_))
  expect_identical(names(drop_empty_columns(t)), "a")
})

test_that("an all-blank-string column is dropped", {
  t <- tibble(a = c("x", "y"), b = c("", ""))
  expect_identical(names(drop_empty_columns(t)), "a")
})

test_that("a column mixing NA and blank string is dropped", {
  t <- tibble(a = c("x", "y"), b = c(NA_character_, ""))
  expect_identical(names(drop_empty_columns(t)), "a")
})

test_that("a column with a single non-blank value is kept", {
  t <- tibble(a = c("x", "y"), b = c(NA_character_, "z"))
  expect_identical(names(drop_empty_columns(t)), c("a", "b"))
})

test_that("surviving column order is preserved", {
  t <- tibble(a = c("1", "1"), b = c(NA_character_, NA_character_), c = c("2", "2"))
  expect_identical(names(drop_empty_columns(t)), c("a", "c"))
})

test_that("a row that is entirely blank does not drop a column another row fills", {
  t <- tibble(a = c(NA_character_, "x"), b = c(NA_character_, NA_character_))
  expect_identical(names(drop_empty_columns(t)), "a")
})

test_that("a zero-row typed tibble prunes to zero columns, and formats as an empty string", {
  t <- tibble(a = character(), b = character())
  pruned <- drop_empty_columns(t)
  expect_identical(ncol(pruned), 0L)
  expect_identical(format_table_csv(t), "")
})
