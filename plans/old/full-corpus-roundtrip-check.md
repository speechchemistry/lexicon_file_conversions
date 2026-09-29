# Plan: formalise the full-`sena3.lift` round-trip check

## Status

Done. `tests/testthat/test-sena3-full-corpus-roundtrip.R` exists, matching
the [Design](#design) sketch below (loops `table_registry()`, no `_snaps/`
directory, asserts CLI success before comparing). The [Verification](#verification)
checklist's duplicate-`<translation>` check is confirmed: it fires as a WARN,
not a FAIL, identically on both the original and round-tripped read. This
test is still actively cited elsewhere as the standing confirmation for new
tables' round-trip losslessness — see `plans/remaining-lift-fields.md`.

## Context

Every table-adding increment in [`plans/remaining-lift-fields.md`](../remaining-lift-fields.md) has, as its last verification step, a manual spot check: run the full `tests/testthat/fixtures/lift2csv_entry-table/sena3.lift` (1462 entries) through `lift2csv.R --table-dir` then `csv2lift.R --table-dir`, and confirm the new table's data survives the round trip unchanged. B1, B2, C1a, and C2 each did this by hand, in a scratch directory, and reported a count in the commit/plan prose (e.g. C2: "168 variants, identical count, order, entry guid, and form text before and after"). None of it is a committed test — it is re-derived from scratch, off the record, every time.

It has already caught real defects this way: the blank-`<grammatical-info>`-needs-a-wrapper case in C1a, and the silent coverage holes in B1/B2/C1a/C2 (an existing `csv2lift/` fixture directory missing a companion CSV for a table its source `.lift` actually has data for). Both were found by running the check against the full corpus, not against the small curated fixtures — the curated fixtures are deliberately narrow ([the skill's "Get a real fixture"](../../.claude/skills/adding-a-lift-field/SKILL.md#get-a-real-fixture)), so they cannot by themselves prove a table's behaviour holds at 1462-entries-of-real-data scale.

**Goal of this plan:** make that spot check a standing, committed test, so it runs on every `devtools::test()` rather than being re-derived by hand each increment — while keeping [Testing Approach](../../AGENTS.md#testing-approach)'s human-reviewability rule intact, which is what already rules out a byte-for-byte snapshot of the full round-tripped `.lift` (1462 entries is not eyeball-reviewable, which is exactly why the curated per-table fixtures exist in the first place).

## Why an invariant test, not a snapshot

A snapshot test (`expect_snapshot_file()`) needs a human to review the `.new` file before accepting it. A full-corpus `.lift` fails that immediately — nobody is going to read a multi-thousand-line XML diff line by line, and a bad accept would be as invisible as the existing coverage holes were before someone went looking for them by hand.

Instead: for each table currently in `R/table_registry.R`, read the **original** `sena3.lift` with that table's own `read_fn`, read the **round-tripped** `.lift` with the same `read_fn`, and assert the two tibbles are `identical()` — same rows, same order, same values. No XML is compared directly; the table's own reader is the comparator, exactly as the manual spot checks above already did it (e.g. C2's Python script, but done through the tool's own R functions and column shapes, per table, rather than hand-rolled per increment).

This design has two properties worth calling out explicitly:

- **It grows for free.** The test loops over `table_registry()`'s rows rather than naming tables by hand. When C1b, C3, D1, etc. land, each is covered by this test the moment its registry row exists — zero edits to this test file. This is the direct answer to "should we delay until all tables are done": the test doesn't need to know how many tables exist, so there is no batching benefit to waiting, and no partial-coverage caveat to word carefully — it always covers exactly whatever is currently implemented, which is exactly the corpus of guarantees [SPEC.md](../../SPEC.md) currently makes.
- **It tolerates the round-trip's one documented, accepted infidelity for free too.** [SPEC.md's Data Handling](../../SPEC.md#data-handling) documents that sibling order among distinct attribute-keyed elements (typed `<note type>`, custom `<field type>`) can legitimately change on round-trip (47 senses in `sena3.lift` re-emit `(sociolinguistics, phonology)` from a source `(phonology, sociolinguistics)`) — this is a deliberate, spec'd behaviour, not a bug. A raw XML diff would have to special-case it or fail on it. Comparing via each table's own `read_fn` sidesteps this entirely: the reader extracts by xpath/column, not by sibling position, so it produces the identical tibble regardless of which order the siblings ended up in. The one place this reasoning needs a second look is the duplicate-`<translation>`/duplicate-`<media>` cases ([Not Yet Specified](../../SPEC.md#not-yet-specified)) — those are read-time lossy (`extract_example_translation()` warns and keeps only the first) on the **original** file too, so comparing "original, read once" against "round-tripped, read once" already reflects the same already-applied loss on both sides and should still match; this is asserted, not just argued, in [Verification](#verification) below.

## Design

New test file, e.g. `tests/testthat/test-sena3-full-corpus-roundtrip.R`. No `_snaps/` directory — this is an invariant assertion, not a snapshot.

```r
sena3_path <- testthat::test_path("fixtures", "lift2csv_entry-table", "sena3.lift")

# Built once, at file-parse time or in a setup helper: run the full corpus
# through lift2csv --table-dir then csv2lift --table-dir, exactly as the
# manual spot check has done by hand every increment.
tables_dir <- withr::local_tempdir()
system2("Rscript", c("../../scripts/lift2csv.R", sena3_path, "--table-dir", tables_dir))
roundtrip_path <- withr::local_tempfile()
system2("Rscript", c("../../scripts/csv2lift.R", "--table-dir", tables_dir), stdout = roundtrip_path)

registry <- table_registry()

for (i in seq_len(nrow(registry))) {
  name <- registry$name[i]
  read_fn <- registry$read_fn[[i]]

  test_that(paste0("sena3_full-roundtrip_", name), {
    expect_identical(read_fn(sena3_path), read_fn(roundtrip_path))
  })
}
```

(Sketch only — exact `withr`/`test_that` scoping, and whether the round-trip build belongs in a `setup-*.R` file so it runs once rather than per test file, needs settling at implementation time.)

## Decisions settled

**Shell out via `Rscript`, not in-process.** Matches [Testing Approach](../../AGENTS.md#testing-approach)'s "nearly every CLI test in this suite is end-to-end" convention and what the manual spot check has always done — the sketch above is the settled shape, not an option to reconsider. Trades a little speed (two extra `Rscript` invocations parsing the 1462-entry file) for testing the same surface as every other CLI test: if a future change to argument parsing or the registry-driven attach loop in `scripts/csv2lift.R` itself broke the round trip, an in-process version calling `read_fn`/`attach_fn` directly would not catch it, since it bypasses the scripts entirely.

**Supplants the per-increment manual spot check, with one carve-out.** Once this test exists, an increment's commit/plan prose no longer needs to hand-report a full-corpus round-trip count (B1/B2/C1a/C2's "confirmed lossless: identical counts..." paragraphs) — the test *is* that confirmation, permanently, rather than a one-time claim in prose that can quietly go stale the moment a later increment changes something upstream. Worth saying explicitly in `plans/remaining-lift-fields.md`'s per-increment write-ups going forward, once this lands.

The carve-out: this only replaces the **round-trip-losslessness** check specifically. It does not replace the separate, still-necessary full-corpus *tallying* every increment already does under [the skill's "Understand the field"](../../.claude/skills/adding-a-lift-field/SKILL.md#understand-the-field-in-the-real-lift-model)/["Get a real fixture"](../../.claude/skills/adding-a-lift-field/SKILL.md#get-a-real-fixture) steps — counting occurrences, distinct values, and cardinality (e.g. C2's "168 variants across 131 entries, max 8 on one entry," C1a's "24 senses repeat `semantic-domain-ddp4`") to decide column vs. table and to choose which real entries a curated fixture should extract. That analysis feeds design decisions and fixture selection before code exists to round-trip anything; this test only checks that whatever gets built stays lossless afterward. The two are easy to conflate because both start from "run a script over `sena3.lift` and count something," but they answer different questions and neither makes the other unnecessary.

## Verification

- Every table currently in `R/table_registry.R` passes when compared this way — this is expected to be true immediately (it's exactly what every past increment already checked by hand), so a first run should be all green, not red/green.
- Deliberately confirm the duplicate-`<translation>` case (`example_table()`'s one occurrence, entry `d5cb3ce5-…`) reads identically on both sides despite being read-time lossy, rather than assuming it from the reasoning above.
- Confirm the test actually fails when it should: temporarily reintroduce a known-fixed bug (e.g. skip the on-demand `<grammatical-info>` wrapper C1a added) and confirm this test — not just the curated-fixture ones — catches it, before trusting it as a safety net.
