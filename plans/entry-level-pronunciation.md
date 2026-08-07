# Add entry-level `<pronunciation>` support to lift2csv / csv2lift

## Context

`<pronunciation>` is the largest remaining entry-level gap. It is named in `SPEC.md` §8, in the TODO at the top of `scripts/lift2csv_entry-table.R`, and as the motivating example in the `adding-a-lift-field` skill. Today the round trip **silently drops it**: `_snaps/csv2lift_end-to-end/note_and_phonology_notes.lift` contains no `<pronunciation>` at all.

The obvious approach — clone the `<citation>` / `<note>` block — does not work here, and that is why this plan is longer than `plans/entry-level-note.md`:

1. **`<pronunciation>` is `zeroOrMore`**, not `<optional>`. `citation`, `note`, and custom `field` are all at-most-one-per-entry form-wrapped multitexts, which is exactly what makes the flat `<prefix>_<lang>` column shape work. Pronunciation breaks that.
2. **It has two value channels**: `form[@lang]` (phonetic transcription) and `media/@href` (audio file). `@href` has no `lang`, so there is nothing to key a `_<lang>` column on.
3. **Both awkward cases are already in fixture data.** `note_and_phonology_notes.lift` has 4 pronunciations across 3 entries, all media-only with zero `<form>` children, and entry `kerɔ` has **two** of them.

Two findings that settled the design:

- **The data loss is real but small.** Each entry's *first* `<pronunciation>`'s `@href` is byte-identical to its `zhi-Zxxx-x-audio` lexical-unit form, which already round-trips as an ordinary column. But `kerɔ`'s **second** pronunciation, `Blench530-_seek_RMKS.webm`, appears nowhere else in the CSV. A one-pronunciation-per-entry design would not recover it.
- **The `two_pronunciations_with_audio_and_IPA.lift` fixture rules out entry-table columns outright.** Its single entry has two pronunciations whose forms share the *same* writing system (`zhi-fonipa-x-etic`: `tsēn` and `tsʼēn`). Two values, one lang, one entry — `pivot_wider` cannot represent that in one row at all, regardless of prefix choice.

`lift.rng` facts (the tracked copy `resources/lift-0.13.rng` was deleted in commit `5c16259`; recover with `git show 5c16259^:resources/lift-0.13.rng`):

```xml
<zeroOrMore><element name="pronunciation"><ref name="pronunciation-content"/></element></zeroOrMore>

<define name="pronunciation-content">
  <interleave>
    <ref name="multitext-content"/>      <!-- zeroOrMore <form lang><text> -->
    <ref name="extensible-content"/>     <!-- trait / field / annotation, dateCreated/dateModified -->
    <zeroOrMore><element name="media"><ref name="URLRef-content"/></element></zeroOrMore>
  </interleave>
</define>

<define name="URLRef-content">
  <attribute name="href"><data type="anyURI"/></attribute>
  <optional><element name="label"><ref name="multitext-content"/></element></optional>
</define>
```

Entry children are an `<interleave>`, so child order is a readability convention only, never schema-required. `<pronunciation>` has no attributes of its own and no id/guid.

## Approach: a third table, mirroring the sense table

One row per `<pronunciation>`, keyed to its entry by `entry_id`. This is what `SPEC.md` §6 already anticipates — "further tables are added as optional parameters as their round-trip support is implemented" — and it is the only shape that holds two same-lang pronunciations on one entry.

`<pronunciation>` has no id/guid, so the table has **no primary key**. Rows are attached in CSV row order, exactly as `attach_senses_to_lift()` does, and `SPEC.md` §2 already forbids either direction from re-sorting.

| Column | LIFT source | Notes |
|---|---|---|
| `entry_id` | parent `entry/@guid` | foreign key → entry table; no primary key of its own |
| `pronunciation_<lang>` | `pronunciation/form` | reserved prefix `pronunciation_`; one column per writing system found |
| `media_href` | `pronunciation/media/@href` | at most one per pronunciation; warns and keeps the first if the source has more |

Deliberately **not** included, because no real data exercises them (recorded in §8 instead): `media/label`, and pronunciation-level `trait` / `field` / `annotation` / `dateCreated` / `dateModified`.

## Process: TDD (red → green → refactor)

Per `AGENTS.md` and the `adding-a-lift-field` skill: **do the read direction first, then reuse its CSV output verbatim as the write direction's fixture.** Never hand-author a CSV fixture. Pause at each red/green boundary to commit.

## Implementation — read direction (lift2csv)

**New — `R/pronunciation_table.R`**, modelled on `R/sense_table.R`:

- `prons <- xml_find_all(doc, ".//entry/pronunciation")`; `entry_id` comes from `xml_parent()`.
- Use the **typed-empty-tibble guard on both the outer and inner paths** — the skill calls this out, and `lela-teli-empty-lexicon.lift` (zero entries) is exactly the case an inner-only guard never sees.
- Rows are keyed by pronunciation position, not by any LIFT id, so the forms pivot needs a synthetic row index. `extract_multitext_element()` keys on `entry_id` and `extract_sense_multitext_element()` keys on `sense_guid`; neither fits, so add a small local extractor in `R/pronunciation_helpers.R`. `add_multitext_children()` is reused unchanged on the write side.
- More than one `<media>` in one `<pronunciation>`: `warning()` to stderr naming the entry and keeping the first, mirroring `extract_single_trait()`. This is schema-permitted, so the warning is load-bearing rather than defensive padding.

**New — `scripts/lift2csv_pronunciation-table.R`**: a near-copy of `scripts/lift2csv_sense-table.R`, including its `if (nrow(table) == 0) cat("")` branch so pronunciation-free files snapshot as an empty file.

**New — `tests/testthat/test-pronunciation-table_end-to-end.R`**: a copy of the 10-line glob loop in `test-sense-table_end-to-end.R`, pointing at a new `fixtures/lift2csv_pronunciation-table/`.

**New fixture dir — `tests/testthat/fixtures/lift2csv_pronunciation-table/`.** Fixture dirs are curated per table, not full parity (`lift2csv_sense-table/` does not carry `note_and_phonology_notes.lift`). Four fixtures:

- `two_pronunciations_with_audio_and_IPA.lift` — the primary case: two pronunciations, each with both a form and a media href, forms sharing one writing system
- `note_and_phonology_notes.lift` — media-only pronunciations, and two on one entry
- `sena3_single_entry_plant.lift` — entries present, zero pronunciations
- `lela-teli-empty-lexicon.lift` — zero entries

`two_pronunciations_with_audio_and_IPA.lift` also stays in `fixtures/lift2csv_sense-table/` where it was first added; it has two senses with multi-lang glosses, so it earns its place there as extra sense coverage and gets its own accepted snapshot.

**Red:** with only the fixtures and the test file in place (no R code, no CLI script), `devtools::test(filter = "pronunciation-table")` errors — the script does not exist. **Green:** implement, review the auto-created snapshots (an unseen fixture creates its snapshot with a WARN, so read it rather than trusting it), then `snapshot_accept("pronunciation-table_end-to-end/")` — the trailing slash is required.

The entry table and join view are untouched by this direction; no other snapshot should move except the new sense-table one.

## Implementation — write direction (csv2lift)

**Fixture first, copied from the reader's own output:**

```bash
cp tests/testthat/_snaps/pronunciation-table_end-to-end/two_pronunciations_with_audio_and_IPA.csv \
   tests/testthat/fixtures/csv2lift/two_pronunciations_with_audio_and_IPA_pronunciations.csv
```

This needs a matching `_entries.csv`, which does not exist yet — produce it the same way, from `lift2csv_entry-table.R`'s own output for that fixture, which also means adding the `.lift` to `fixtures/lift2csv_entry-table/`. Also add a `_pronunciations.csv` for `note_and_phonology_notes`, whose `_entries.csv` already exists and is byte-identical to the entry-table snapshot.

**New — `R/pronunciation_helpers.R`**: `classify_pronunciation_columns()`. Follow `classify_sense_columns()`'s stricter contract — exact match on `entry_id` / `media_href` → metadata; `^pronunciation_(.+)$` → form, lang = capture group; **else hard error**. Do not copy the entry-level last-underscore custom-field fallback: there are no pronunciation-level custom fields, so silently misclassifying one would be worse than failing.

**New — `R/csv2lift_pronunciation.R`**: `attach_pronunciations_to_lift(doc, pronunciation_table)`, modelled on `R/csv2lift_sense.R`:
- Look up `.//entry[@guid='...']`; **hard error** if not found, matching the sense-level fail-fast — a pronunciation is never silently dropped.
- Add `<pronunciation>`, then `add_multitext_children(pron_node, form_values)`, then `<media href=...>` when `media_href` is non-blank.
- Omit the whole `<pronunciation>` element if the row has neither a non-blank form nor a non-blank `media_href` — the same "no empty elements" rule as citation/note.

**Modify — `scripts/csv2lift.R`**: add `--pronunciations`, calling `attach_pronunciations_to_lift()` **before** `attach_senses_to_lift()` so emitted child order stays `lexical-unit, trait, citation, note, field…, pronunciation…, sense…`.

**Modify — `tests/testthat/test-csv2lift_end-to-end.R`**: alongside the existing `_senses.csv` pickup, attach `--pronunciations <stem>_pronunciations.csv` when present. This is the only test file needing an edit; the rest auto-discover.

**Red:** with only the fixtures added, `devtools::test(filter = "csv2lift_end-to-end")` shows no `<pronunciation>` in the output. **Green:** implement, review, `snapshot_accept("csv2lift_end-to-end/")`.

## Refactor

With tests green, look at the three now-parallel `*_table.R` / `csv2lift_*.R` / `*_helpers.R` triples for duplication worth factoring out — particularly `has_nonblank()`, now defined locally in three files. Re-run the full suite before calling it done.

## Documentation

- **`SPEC.md` §5 (new, renumbering §5–§8 → §6–§9)**: "Pronunciation table" — the column table above, the column-classification algorithm (stated as needing to match exactly between directions), the no-primary-key/row-order rule, the `media_href` cap and its warning, and the fail-fast on unmatched `entry_id`.
- **`SPEC.md` §3**: extend the canonical-child-order bullet to `…, then fields, then pronunciations, then senses`, noting that pronunciations and senses are appended in a second pass and that `lift.rng` makes entry children an `<interleave>`, so order is a readability convention only. §3's reserved-prefix limitation note is unchanged — the entry-table classifier is not touched.
- **`SPEC.md` §6 (CLI shape)**: add `--pronunciations` to the implemented-parameters list.
- **`SPEC.md` §8**: delete "Pronunciation" from the first bullet's list; add a bullet for what is deliberately left out — `media/label`, pronunciation-level `trait`/`field`/`annotation`/date attributes, and more than one `<media>` per pronunciation.
- **`README.md`**: add `lift2csv_pronunciation-table.R` and the `--pronunciations` flag to the usage examples.
- **`scripts/lift2csv_entry-table.R`**: drop `pronunciation` from the TODO comment.

## Verification

1. `Rscript -e 'devtools::test()'` — full suite green.
2. Check the read direction against the source by hand rather than eyeballing the diff:
   ```bash
   python3 -c "
   import csv
   rows = list(csv.DictReader(open('tests/testthat/_snaps/pronunciation-table_end-to-end/two_pronunciations_with_audio_and_IPA.csv')))
   for r in rows: print(r)
   "
   ```
   Expect 2 rows, same `entry_id`, `pronunciation_zhi-fonipa-x-etic` of `tsēn` / `tsʼēn`, and the two distinct hrefs — in source order.
3. Confirm the write direction recovers what was previously lost:
   ```bash
   grep -c "<pronunciation>" tests/testthat/_snaps/csv2lift_end-to-end/note_and_phonology_notes.lift   # expect 4
   grep -c "Blench530-_seek_RMKS.webm" tests/testthat/_snaps/csv2lift_end-to-end/note_and_phonology_notes.lift
   ```
4. End-to-end by hand, proving the round trip is closed for the new fixture:
   ```bash
   Rscript scripts/lift2csv_pronunciation-table.R \
     tests/testthat/fixtures/lift2csv_pronunciation-table/two_pronunciations_with_audio_and_IPA.lift > /tmp/p.csv
   Rscript scripts/csv2lift.R \
     tests/testthat/fixtures/csv2lift/two_pronunciations_with_audio_and_IPA_entries.csv \
     --pronunciations /tmp/p.csv | grep -A3 pronunciation
   ```
5. Confirm `entry-table_end-to-end/` and `join-sense-entry-table_end-to-end/` snapshots are unchanged.
