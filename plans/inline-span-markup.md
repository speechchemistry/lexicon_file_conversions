# Inline `<span lang>` markup inside `<text>`

## Context

LIFT allows an inline `<span lang="...">` inside a multitext `<text>`, tagging a stretch of the value as
a different writing system — typically an alternate-orthography form quoted inside an English note:

```xml
<note type="phonology">
  <form lang="en"><text>variant: <span lang="seh">nkucauno</span></text></form>
</note>
```

Every reader in the repo calls `xml_text()` on the form/gloss node, which flattens that to
`variant: nkucauno` and silently drops the tagging. SPEC.md §9 already records this as accepted
lossiness on the strength of it affecting **2 of 632** untyped sense notes.

That number is about to become misleading. The typed-note change (`plans/typed-notes-entry-and-sense.md`)
adds `note_<type>_<lang>` columns, and **120 of 199** Sena3 `note[@type="phonology"]` forms contain a
span (60%) — precisely the alternate-orthography form a lexicographer cares about. So this change lands
**first**, so those columns are born span-preserving:

- Doing spans first changes **4 cells** across all existing approved snapshots.
- Doing typed notes first means re-accepting ~128 changed cells in the same columns afterwards.

## Representation: the literal `<span>` tag in the cell

A span is carried in the CSV cell as the **literal `<span lang="…">…</span>` tag**, with the text around
it left exactly as it is. So `variant: <span lang="seh">nkucauno</span>` round-trips through the cell as,
verbatim, `variant: <span lang="seh">nkucauno</span>`.

Span inventory across every fixture, which is what makes this sufficient:

| property                                | finding                             |
| --------------------------------------- | ----------------------------------- |
| attributes on `<span>`                  | `lang` and nothing else, 924 of 924 |
| element children of `<text>`            | `span` and nothing else             |
| nesting inside a span                   | never                               |
| several spans in one `<text>`           | 54 cases                            |
| text following a span                   | 78 cases                            |
| span content containing `[` or `]`      | 72 of 600                           |
| literal `</span>` in ordinary note text | 0                                   |

### Why not the two alternatives

Both were fully prototyped and round-trip correctly on all seven shapes below; this is a choice between
working options, not a correctness argument.

**Rejected: pandoc bracketed spans, `[nkucauno]{lang=seh}.`** This was an earlier draft of this plan, and
it is strictly worse. Its delimiters are single characters that occur constantly in ordinary lexicographic
text, so span content needs `\`, `[` and `]` backslash-escaped — 72 of 600 spans contain a `]`, and the
first draft's unescaped pattern silently failed on all of them, emitting `[…]{lang=seh}` as literal text
and losing the span. With `</span>` as the terminator that whole problem disappears: **no content escaping
is needed at all**, which removes a matched escape/unescape helper pair, a subtle backslash-ambiguity in
literal text, and an ICU-vs-TRE regex portability trap. The only thing pandoc had going for it was being a
named standard, and `<span lang="seh">` is more self-explanatory than `{lang=seh}` to a lexicographer who
has seen HTML but not pandoc.

**Rejected: the whole cell as an escaped XML fragment.** Tempting, because it makes both directions
one-liners with no regex at all — read is `paste0(vapply(xml_contents(text_node), as.character, ...))`,
write is `read_xml(paste0("<text>", cell, "</text>"))`. The cost is that *every* multitext cell becomes an
XML fragment, so ordinary text must carry entity escapes: `George, Alicete &amp; Mauricio` instead of
`George, Alicete & Mauricio`. That hits **27 existing snapshot cells** (24 in `Sena3.csv`, 3 in
`Sena3_gloss_initial_b.csv`) versus the 4 that actually contain a span, and it imposes the rule
permanently on every future hand-edit: a linguist typing a bare `&` into any cell of any multitext column
makes the CSV unconvertible. Trading hand-editability across all cells for brevity in two functions is the
wrong trade for a format whose entire purpose is being hand-editable.

### Why the writer escapes `&` at all

Worth stating plainly, because it is easy to read as an artefact of the markup choice and it isn't. To
produce mixed content — text, then an element, then more text — the writer has to build the `<text>`
element as a **string** and hand it to `read_xml()`: xml2 has no API for appending a text node beside
existing element children, and `xml_text(node) <- x` *replaces* all contents rather than adding to them.
Anything handed to an XML parser must have `&` and `<` escaped or parsing fails outright, and real Sena3
text contains bare ampersands (`George, Alicete & Mauricio didn't recognize word`).

So the escaping is the price of building mixed content, not of any particular cell syntax. It is needed
identically under the pandoc form. The rejected XML-fragment form is the only one that avoids *us* doing
it — by pushing the obligation onto whoever edits the CSV, which is precisely why it was rejected.

Verified before implementing: all seven shapes round-trip `element → cell → element → cell` identically —
the simple trailing-span case, the bracket-heavy `Parsing Note`, a span that is the entire value, several
spans plus trailing text, `&`/`<`/`>` in both literal text and span content, and brackets with no span at
all. These become the unit test in stage F.

## Read direction

New shared helper in [R/entry_helpers.R](../R/entry_helpers.R) (beside `has_nonblank()` /
`add_multitext_children()`, which all three levels already share):

```r
# LIFT allows an inline <span lang="..."> inside a <text>, tagging a stretch of the value as a
# different writing system (typically an alternate-orthography form quoted inside an English
# note). xml_text() would flatten that and lose the tagging, so the <text>'s mixed content is
# serialised with the <span> tag kept literally and the surrounding text left as-is:
# 'variant: <span lang="seh">nkucauno</span>'. set_multitext_text() is the inverse.
#
# The tag is rebuilt with sprintf() rather than as.character(child) on purpose: as.character()
# would XML-escape the span's content ("a & b" -> "a &amp; b") while the literal text around it
# stays raw, so the cell would be inconsistently escaped and no longer plain text.
multitext_value <- function(node) {
  text_node <- xml_find_first(node, "./text")
  paste0(
    map_chr(xml_contents(text_node), function(child) {
      if (xml_type(child) == "text") return(xml_text(child))
      sprintf("<span lang=\"%s\">%s</span>", xml_attr(child, "lang"), xml_text(child))
    }),
    collapse = ""
  )
}
```

Then replace `xml_text(.x)` with `multitext_value(.x)` at the five extraction sites — the two in
[R/entry_helpers.R](../R/entry_helpers.R), the two in [R/sense_helpers.R](../R/sense_helpers.R), and
the one in [R/pronunciation_helpers.R](../R/pronunciation_helpers.R). Applying it uniformly (no fixture
has a span in a pronunciation form) keeps one rule for all multitext rather than a per-level exception.

Two incidental improvements, both correct: the value now comes from `./text` specifically rather than
all descendant text, so a `<form>` with an `<annotation>` sibling of `<text>` (allowed by `lift.rng`,
present in no fixture) would no longer have its annotation text concatenated in. And a `<text>` with no
children yields `""` via `paste0(character(0), collapse = "")`.

## Write direction

```r
# Inverse of multitext_value(): turns the literal <span lang="..."> tags in a CSV value back into
# real child elements. Built by parsing a constructed XML string because `xml_text()<-` cannot
# produce mixed content (see the plan). The value is walked as alternating literal / span pieces
# rather than substituted in one pass, because only the literal pieces may be XML-escaped — the
# span tags we emit must stay as markup, and escaping them would turn them back into text.
SPAN_MARKUP_PATTERN <- "<span lang=\"([^\"]*)\">(.*?)</span>"

set_multitext_text <- function(parent_node, value) {
  spans <- stringr::str_match_all(value, SPAN_MARKUP_PATTERN)[[1]]
  literals <- stringr::str_split(value, SPAN_MARKUP_PATTERN)[[1]]

  inner <- escape_xml_text(literals[1])
  for (i in seq_len(nrow(spans))) {
    inner <- paste0(
      inner,
      sprintf("<span lang=\"%s\">%s</span>", spans[i, 2], escape_xml_text(spans[i, 3])),
      escape_xml_text(literals[i + 1])
    )
  }

  xml_add_child(parent_node, read_xml(paste0("<text>", inner, "</text>")))
}

escape_xml_text <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}
```

and `add_multitext_children()` swaps its two body lines for `set_multitext_text(form_node, text)`.

The non-greedy `(.*?)` plus a multi-character `</span>` terminator is what makes span content need no
escaping: brackets, braces, `&` and `<` inside content are all just content. `str_split()` on the same
pattern guarantees `length(literals) == nrow(spans) + 1`, so the interleave needs no bounds check, and a
value with no span markup yields one literal and zero spans — the plain-text path.

Verified in R beforehand: `xml_add_child(node, read_xml("<text>…</text>"))` serialises
**byte-identically** to today's `xml_add_child(node, "text")` + `xml_text(text_node) <- …` when the
value contains no span, so no csv2lift snapshot moves except where a span is genuinely present.
`stringr` is already used in the repo via `stringr::` (`R/copy_lift_entries.R`); keep that call style.

## TDD cycle

**A — red (read).** `devtools::test(filter = "sense-table_end-to-end")`. The approved
`_snaps/sense-table_end-to-end/Sena3.csv` holds the flattened text; that is the red. Exactly 4 cells
change, all in Sena3, all sense-level (there are no spans in any currently-read entry-level element):

| sense                                  | column            | becomes                                                                                                                             |
| -------------------------------------- | ----------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `cddee31a-556f-4a76-8e75-2be21302d85f` | `definition_en`   | `<span lang="pt">pull out (nail, tooth, etc.)</span>`                                                                               |
| `d1645b43-54ad-4ae3-86a8-2adc01b10b86` | `general_note_pt` | `<span lang="en">mostra tristeza, disapontamento mas com  submissao</span>`                                                         |
| `f1d582f4-f8a1-4e6c-99f3-039650900166` | `general_note_pt` | `<span lang="en">inclua sentimente de zanga</span>`                                                                                 |
| `e2c0d4bd-f0f9-43a8-8f4e-778deabb7a34` | `Parsing Note_en` | `Question: … not working;<span lang="seh">es +/ {monosyllabic} _ \|eg adyesa; is / [AIU] [C] … </span>` — brackets need no escaping |

**B — green (read).** `multitext_value()` + the five call-site swaps. Accept
`sense-table_end-to-end/` and `join-sense-entry-table_end-to-end/` separately; `entry-table_end-to-end/`
and `pronunciation-table_end-to-end/` must not move at all — that they don't is part of the review.

**C — write fixture.** New `sena3_inline_span_markup_{entries,senses}.csv` under
`tests/testthat/fixtures/csv2lift/`, three rows copied verbatim from the newly accepted snapshots:

- entry `44af4d61-fa9c-4b62-8d30-1c70c2e9361b` + sense `cddee31a-…` — a span that is the *entire*
  text content, in a `definition` whose sibling `pt` form is plain.
- entry `6d5fdb31-6c26-4f20-bab3-8d86a38eea78` + sense `d1645b43-…` — same shape in an untyped
  `<note>`, i.e. a span-only form beside a plain sibling form in one element.
- entry `8d3435f5-a7c2-4628-86de-1b02fe3623f6` + sense `e2c0d4bd-…` — the `Parsing Note` custom field
  (source: `tests/testthat/fixtures/lift2csv_sense-table/Sena3.lift:20288`; today's flattened output:
  `tests/testthat/_snaps/sense-table_end-to-end/Sena3.csv:938`, column 11, 374 chars). It is the
  **only** currently-readable cell with text *before* a span, and the only one whose span content is
  full of `[` `]` brackets. Long enough to be mildly awkward to review, and it has already earned its
  place: writing this row out during planning is what killed the pandoc bracketed-span proposal, by
  showing its delimiters collide with 12% of real span content. Its entry has 2 senses; only this sense
  row is included, which is fine — multi-sense output is already covered by
  `sena3_multiple_senses_per_entry`.

**D — red (write).** `devtools::test(filter = "csv2lift_end-to-end")`. The new fixture auto-creates its
snapshot with a WARN (skill gotcha: not a `.new` to accept, and nothing has vetted it). Read it: the red
is `<text>&lt;span lang="pt"&gt;pull out (nail, tooth, etc.)&lt;/span&gt;</text>` — the tag escaped into
literal text by today's `xml_text(text_node) <- …` instead of becoming a real child element. That escaping
is itself the proof the writer is treating the markup as data. No other csv2lift snapshot moves, because
no other fixture cell contains span markup.

**E — green (write).** `set_multitext_text()` + the `add_multitext_children()` swap. Review that the
three fixture rows produce real `<span lang>` children in the right places, then
`snapshot_accept("csv2lift_end-to-end/")`.

**F — unit-test the shapes no fixture cell reaches.** Real data has two shapes that no
*currently-readable* fixture cell has: several spans in one `<text>` (54 occurrences repo-wide) and a
span followed by trailing text (78). Rather than leave these to a throwaway scratchpad check, add
`tests/testthat/test-multitext-span-markup.R` — a plain (non-snapshot) unit test asserting
`element → cell → element → cell` identity for the seven shapes already proven during planning:

1. trailing span (`variant: <span lang="seh">nkucauno</span>`)
2. bracket-heavy span content, i.e. the `Parsing Note` case that killed the pandoc proposal
3. a span that is the entire value
4. several spans plus trailing text
5. `&` / `<` / `>` in both literal text and span content
6. brackets present but no span — must pass through untouched

This is the one place a non-snapshot test is the right tool: the assertions are small and exact, and
`expect_snapshot_file()` would bury them in a fixture. Case 5 is the one that matters most — it pins the
rule that literal text is XML-escaped on write while the span tags are not, so a later "simplification"
that escapes the whole value (turning spans back into text) or none of it (producing invalid XML on a bare
`&`) fails loudly here rather than silently in a 1717-row CSV.

Then the end-to-end check the suite still cannot do: round-trip a throwaway LIFT file carrying both
uncovered shapes through `lift2csv_sense-table.R` → `csv2lift.R` and report the result, per the skill's
rule for uncovered branches. Both also become structurally covered by
`plans/typed-notes-entry-and-sense.md` (`variant: <span lang="seh">nkucauno</span>` is a trailing-text
case).

Pause for a commit at each of B, C/E, F.

## Documentation

- **SPEC.md §2**: a new convention bullet — an inline `<span lang>` inside a multitext `<text>` is
  carried in the CSV cell as the literal `<span lang="…">…</span>` tag, in both directions, with the text
  around it left exactly as it is (**not** entity-escaped) and the span's `lang` as the only attribute
  represented. State the asymmetry explicitly: on write, literal text is XML-escaped and the span tags are
  not. Both "simplifications" of that rule are broken — escaping the whole value turns spans back into
  text, escaping none of it produces invalid XML on the first bare `&` (which real note text has).
- **SPEC.md §9**: replace the "2 of 632 untyped sense notes lose their inline span" lossiness bullet — it
  is no longer true. What remains, all with zero occurrences in any fixture: a span attribute other than
  `lang` would be dropped, a nested span would not round-trip, and ordinary text that itself contains a
  literal `<span lang="…">…</span>` would be turned into real markup on the way back.

## Follow-ups (not in this change)

1. `plans/typed-notes-entry-and-sense.md` — the change this one unblocks.
2. **`trim_ws` bug** — `scripts/csv2lift.R`'s `read_csv()` leaves `trim_ws = TRUE` and `format_csv`
   doesn't quote a value merely for trailing whitespace, so `"Do not parse: "` round-trips as
   `"Do not parse:"`. Affects 14 of 61 entry `restrictions` notes among others. Its own red, its own
   fixture.
