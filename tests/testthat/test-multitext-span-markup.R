library(xml2)
library(purrr)

# Non-snapshot unit tests for shapes real Sena3 data has (spans-in-one-text,
# trailing text after a span) that no currently-readable fixture cell reaches
# on its own -- see plans/old/inline-span-markup.md stage F. Case 5 pins the
# escaping asymmetry: literal text is XML-escaped on write, span tags are
# not, so a "simplification" either direction would fail here.
round_trip_cell <- function(text_inner_xml) {
  node <- read_xml(sprintf("<form lang=\"en\"><text>%s</text></form>", text_inner_xml))
  cell <- multitext_value(node)

  root <- read_xml("<root/>")
  rebuilt_form <- xml_add_child(root, "form", lang = "en")
  set_multitext_text(rebuilt_form, cell)

  list(cell = cell, cell_again = multitext_value(rebuilt_form))
}

test_that("trailing span round-trips element to cell to element to cell", {
  expected <- "variant: <span lang=\"seh\">nkucauno</span>"
  r <- round_trip_cell(expected)
  expect_equal(r$cell, expected)
  expect_equal(r$cell_again, expected)
})

test_that("bracket-heavy span content round-trips (the Parsing Note shape)", {
  expected <- paste0(
    "Question: monosyllabic rule not working;",
    "<span lang=\"seh\">es +/ {monosyllabic} _ |eg adyesa; is / [AIU] [C] ... _ |eg kufambisa</span>"
  )
  r <- round_trip_cell(expected)
  expect_equal(r$cell, expected)
  expect_equal(r$cell_again, expected)
})

test_that("a span that is the entire value round-trips", {
  expected <- "<span lang=\"pt\">pull out (nail, tooth, etc.)</span>"
  r <- round_trip_cell(expected)
  expect_equal(r$cell, expected)
  expect_equal(r$cell_again, expected)
})

test_that("several spans plus trailing text round-trip", {
  expected <- "<span lang=\"a\">one</span> and <span lang=\"b\">two</span> trailing"
  r <- round_trip_cell(expected)
  expect_equal(r$cell, expected)
  expect_equal(r$cell_again, expected)
})

test_that("& / < / > in both literal text and span content round-trip", {
  source_xml <- paste0(
    "A &amp; B &lt;C&gt; D ",
    "<span lang=\"x\">E &amp; F &lt;G&gt; H</span>",
    " I &amp; J"
  )
  expected_cell <- "A & B <C> D <span lang=\"x\">E & F <G> H</span> I & J"
  r <- round_trip_cell(source_xml)
  expect_equal(r$cell, expected_cell)
  expect_equal(r$cell_again, expected_cell)
})

test_that("brackets present but no span pass through untouched", {
  expected <- "no span here [bracket] {brace} plain"
  r <- round_trip_cell(expected)
  expect_equal(r$cell, expected)
  expect_equal(r$cell_again, expected)
})

# Issue #6: FLEx exports spans with no lang -- a character style and a
# hyperlink to an interlinear text (both real Zhire shapes). The cell keeps
# whatever attributes the span had, in source order, rather than inventing
# lang="NA".
test_that("a span with only a class attribute round-trips", {
  expected <- "SILCAWL0283- SILCAWL0<span class=\"Default Paragraph Characters\">283</span>-"
  r <- round_trip_cell(expected)
  expect_equal(r$cell, expected)
  expect_equal(r$cell_again, expected)
})

test_that("a hyperlink span keeps href and class in source order", {
  expected <- paste0(
    "<span href=\"silfw://localhost/link?tool%3dinterlinearEdit%26guid%3d38f9c211-15aa-46cc-b380-84684d29e27a%26tag%3d\"",
    " class=\"Hyperlink\">pronouns 1.1</span>"
  )
  r <- round_trip_cell(expected)
  expect_equal(r$cell, expected)
  expect_equal(r$cell_again, expected)
})

test_that("& in a span attribute value round-trips", {
  r <- round_trip_cell("<span href=\"a?x=1&amp;y=2\">link</span>")
  expect_equal(r$cell, "<span href=\"a?x=1&y=2\">link</span>")
  expect_equal(r$cell_again, r$cell)
})

# libxml2's pretty-printer indents the children of an element with no
# text-node child, and FLEx imports that indentation as data -- so a <text>
# holding only a span must still serialise on one line.
test_that("a span-only <text> is written without added whitespace", {
  root <- read_xml("<root/>")
  form <- xml_add_child(root, "form", lang = "en")
  set_multitext_text(form, "<span lang=\"zhi\">the surface is cold</span>")
  expect_match(
    as.character(root),
    "<text><span lang=\"zhi\">the surface is cold</span></text>",
    fixed = TRUE
  )
})
