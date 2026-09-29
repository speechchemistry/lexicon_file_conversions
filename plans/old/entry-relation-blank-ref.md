# Plan: preserve entry-relations with a blank `@ref` on write

## Status

Done. Implemented as designed: `attach_entry_relations_to_lift()` branches on
a blank `relation_ref`, warns on stderr, and writes `ref=""` verbatim. Fixture
added to all four table directories named in [Fixture](#fixture) below.
`SPEC.md`'s Entry-Relation Table documents the write-direction branch.

## Context

Found via a full-corpus roundtrip check against a real FLEx export
(`zhi-flex_lift_2026-09-29.lift`, the source for the `zhi` fixtures): 9 of its
entries carry a dangling `<relation type="_component-lexeme" ref=""/>` — a
complex-form component reference FLEx left empty, presumably after the
referenced component was deleted. `lift2csv` already anticipates this on the
read side ([SPEC.md's Entry-Relation Table](../../SPEC.md#entry-relation-table)
documents it: a ref resolving to no entry warns and leaves `relation_ref`
blank, "not hypothetical in general... but never observed in `sena3.lift`" —
now observed, in `zhi-flex_lift_2026-09-29.lift`). `csv2lift` does not: it
unconditionally resolves `relation_ref` against `.//entry[@guid='...']`, so a
blank value renders as the literal string `'NA'` in the XPath (R's `sprintf`
stringifying `NA`) and hits the existing "target not found" hard-error path —
crashing the whole conversion, not just dropping one row. Filed as
[speechchemistry/lexicon_file_conversions#3](https://github.com/speechchemistry/lexicon_file_conversions/issues/3).

## Decision

**Write the blank ref back verbatim** (`<relation type="_component-lexeme"
ref=""/>`), with a stderr warning, rather than dropping the relation.
Confirmed in conversation over the alternative (drop the row silently-ish
with a warning): this codebase's standing rule is to preserve what the
source holds rather than reconcile or drop it (duplicate
`example_source`/`note_reference` values: both kept, mismatch warned, neither
picked as a winner — [Data Handling](../../SPEC.md#data-handling)'s Redundant
Columns bullet). `lift2csv` already chose to keep this row rather than omit
it from the CSV; `csv2lift` dropping it after the fact would be a second,
asymmetric place the same data disappears, and would break the row-for-row
symmetry this tool relies on elsewhere (a row matching no declared parent is
a hard error, never a silent drop — [Structural Rules](../../SPEC.md#structural-rules-csv2lift-direction)).

## Implementation

`R/csv2lift_entry_relation.R`'s `attach_entry_relations_to_lift()`: before
the existing `target_node <- xml_find_first(...)` lookup, branch on
`is.na(row$relation_ref) || !nzchar(row$relation_ref)`:

- blank → warn on stderr (naming the entry, mirroring `lift2csv`'s own
  read-side warning wording) and write `ref = ""` directly, skipping the
  target lookup and `entry_lift_id` translation entirely.
- non-blank → existing lookup/translation path, unchanged.

## Fixture

Extracted 2 real entries from `zhi-flex_lift_2026-09-29.lift` via
`scripts/copy-lift-entries.R` (guids `17d3aeac-…` and `23ab5b1e-…`) into
`tests/testthat/fixtures/lift2csv_entry-relation-table/zhi-entry-relation-blank-ref.lift`,
plus the same file copied into `lift2csv_entry-table/`, `lift2csv_sense-table/`,
and `lift2csv_traits-table/` (both entries also carry sense-level data and
entry-relation-owned `complex-form-type` traits, so this closes the same gap
in those tables' own coverage rather than leaving it latent — the [D3
pattern](../remaining-lift-fields.md#phase-d--structural-and-blocked-items)).
The read direction's own output becomes the write-direction fixture:
`lift2csv.R --table-dir` on this file, copied into
`tests/testthat/fixtures/csv2lift/zhi-entry-relation-blank-ref/`.

## Verification

1. Red: `tests/testthat/fixtures/csv2lift/zhi-entry-relation-blank-ref/` run
   through `csv2lift.R --table-dir` crashes on current code (confirmed
   manually against the full Zhire file already; the fixture reproduces it
   at small scale).
2. Green: after the fix, the same fixture converts successfully and its
   snapshot is reviewed (not blindly accepted) before approval.
3. `SPEC.md`'s [Entry-Relation Table](../../SPEC.md#entry-relation-table)
   write-direction paragraph gains a sentence on the blank-`relation_ref`
   branch and its warning.
