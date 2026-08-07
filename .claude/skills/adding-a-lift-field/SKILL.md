---
name: adding-a-lift-field
description: Add support for a new LIFT field/element to the CSV↔LIFT round-trip, covering both the lift2csv (read) and csv2lift (write) directions. Use when asked to support a LIFT element that isn't handled yet — e.g. pronunciation, etymology, variant, relation, a typed note, or an entry attribute/trait beyond morph-type.
---

# Adding a new LIFT field

Procedure for taking a LIFT element from unsupported to fully round-tripping. Worked example throughout: the entry-level plain `<note>` field, added in `plans/entry-level-note.md`.

The ordering matters and is the main thing this skill exists to convey: **do the read direction first, then reuse its CSV output as the fixture for the write direction.** Do not hand-author CSV fixtures.

## 0. Understand the field in the real LIFT model

- Read the two references in [SPEC.md](../../../SPEC.md) §1.1 — `lift.rng` (what the schema permits) and the FLEx technical notes PDF (what FLEx does day to day).
- **Trust real FLEx exports over the PDF when they disagree.** For `<note>`, the PDF documents Restrictions as `<field type="restrictions">`, but real exports emit `<note type="restrictions">`. Reading only the PDF would have produced an xpath that silently merged Restrictions text into the note column.
- Grep the existing fixtures for the element before assuming its shape:
  ```bash
  grep -rn "<note" tests/testthat/fixtures/lift2csv_entry-table/*.lift
  ```
  Then check whether occurrences are entry-level or sense-level, and tally any `type` attribute variants — a quick Python `xml.etree` script over `entry.findall('note')` is the reliable way, since grep can't tell you nesting depth.
- Ask the user to confirm ambiguous semantics in the FLEx UI. For `<note>` the user checked that filtering for non-blank Note in FLEx returned nothing for a project full of `type="restrictions"` notes — that is what established they are separate fields.

## 1. Get a real fixture

Ask the user for a real FLEx export containing the field, and put it in `tests/testthat/fixtures/lift2csv_entry-table/`. Do not hand-write one: a synthetic fixture only encodes what you already assumed, so it cannot surprise you. The real `note_and_phonology_notes.lift` immediately exposed the typed/untyped `<note>` distinction.

Fixtures are auto-discovered — no test code changes needed. `tests/testthat/test-entry-table_end-to-end.R` globs `*.lift` from its fixture directory.

Note that `tests/testthat/fixtures/lift2csv_join-sense-entry-table/` is a **separate directory with its own copies** of the shared fixtures, not a symlink. Copy the fixture there too for join coverage.

## 2. TDD the read direction (lift2csv)

**Red.** Run the suite and inspect the auto-created baseline:

```bash
Rscript -e 'devtools::test(filter = "entry-table_end-to-end")'
```

A brand-new fixture produces a WARN and an auto-created snapshot, *not* a FAIL. That file is simply whatever today's code emits — read it and confirm the new field is absent. That absence is your red.

**Green.** Add the extraction to [R/entry_table.R](../../../R/entry_table.R), following the `citation` block as the template: `extract_multitext_element()` (from [R/entry_helpers.R](../../../R/entry_helpers.R)) then `pivot_wider(names_glue = "<field>_{lang}")`, then a `left_join` into `combined`. For sense-level fields the equivalent is `R/sense_table.R`.

Use an xpath predicate to exclude variants that are semantically different fields — e.g. `./note[not(@type)]/form`. Without it, two variants sharing a language collide in `pivot_wider`.

**Review before accepting.** Expect *existing* fixtures to change if they already contained the element. Verify the new column's contents explicitly rather than eyeballing a huge diff:

```bash
python3 -c "
import csv
rows = list(csv.DictReader(open('tests/testthat/_snaps/entry-table_end-to-end/Sena3.new.csv')))
nonblank = [r for r in rows if r.get('note_en','').strip()]
print(len(nonblank)); [print(r['entry_id'], repr(r['note_en'])) for r in nonblank]
"
```

Confirm the count matches what you found in step 0, and that no excluded variant leaked in. Then accept — **the directory filter needs a trailing slash**:

```bash
Rscript -e 'testthat::snapshot_accept("entry-table_end-to-end/")'
Rscript -e 'testthat::snapshot_accept("join-sense-entry-table_end-to-end/")'
```

## 3. TDD the write direction (csv2lift)

**Use the read direction's output as the fixture.** This is the key step:

```bash
cp tests/testthat/_snaps/entry-table_end-to-end/note_and_phonology_notes.csv \
   tests/testthat/fixtures/csv2lift/note_and_phonology_notes_entries.csv
```

The `_entries.csv` suffix is required — `test-csv2lift_end-to-end.R` globs `*_entries.csv` and picks up an optional matching `*_senses.csv`. This gives real data on both sides, makes round-trip consistency structural, and removes any chance of inventing a column name the reader would never emit.

**Red.** Run `devtools::test(filter = "csv2lift_end-to-end")` and read the auto-created `.lift` snapshot. Expect the field to fall through to the generic custom-field branch — `note_en` produced `<field type="note">` instead of `<note>`. The stderr classification log makes this obvious.

**Green.** Two edits:
- [R/entry_helpers.R](../../../R/entry_helpers.R) — add a branch to `classify_entry_columns()` mirroring the `citation` one (`^<field>_.+$` → `kind = "<field>"`), placed *before* the last-underscore custom-field fallback. Update the "known limitation" comment to name the new reserved prefix.
- [R/csv2lift_entry.R](../../../R/csv2lift_entry.R) — add a `<field>_cols <- filter(col_classes, kind == "<field>")` alongside the others, and an emit block mirroring citation's, positioned to match SPEC.md's canonical child order.

Review the diff, then `snapshot_accept("csv2lift_end-to-end/")`.

## 4. Documentation

- **SPEC.md §3** (or §4 for sense-level): add the column row, insert the classification step and renumber, extend the known-limitation sentence with the new reserved prefix, and update the canonical-child-order / form-order / omit-when-empty bullets.
- **SPEC.md §8**: record what you deliberately did *not* implement (e.g. typed notes), so the boundary is explicit rather than looking like an oversight.
- **README.md**: only if the CLI surface or examples change.

## Gotchas

- Run tests with `devtools::test()`, never bare `testthat::test_file()` — the latter fails with "requires 3rd edition".
- `snapshot_accept("name")` without the trailing slash silently matches nothing and reports "No snapshots to update" without erroring. Always re-run the tests to confirm the accept took.
- Pause at each red/green/refactor boundary so the user can commit — the history is meant to read as distinct TDD stages.
- Consult `plans/` for prior worked examples; save non-trivial plans there and keep them synced (see AGENTS.md).
