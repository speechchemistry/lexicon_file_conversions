---
name: adding-a-lift-field
description: Add support for a new LIFT field/element to the CSV↔LIFT round-trip, covering both the lift2csv (read) and csv2lift (write) directions. Use when asked to support a LIFT element that isn't handled yet, at either the entry or sense level — e.g. pronunciation or a typed note on an entry, or an example sentence or additional gloss language on a sense.
---

# Adding a new LIFT field

Procedure for taking a LIFT element from unsupported to fully round-tripping. Two worked examples run throughout: the **entry-level** plain `<note>` field (see `plans/entry-level-note.md`), and the **sense-level** multi-lang `<gloss>` / `<definition>` pair — which is also where the sense-level guidance below comes from.

The ordering matters and is the main thing this skill exists to convey: **do the read direction first, then reuse its CSV output as the fixture for the write direction.** Do not hand-author CSV fixtures.

## 0. Understand the field in the real LIFT model

- Read the two references in [SPEC.md](../../../SPEC.md) §1.1 — `lift.rng` (what the schema permits) and the FLEx technical notes PDF (what FLEx does day to day).
- **Trust real FLEx exports over the PDF when they disagree.** For `<note>`, the PDF documents Restrictions as `<field type="restrictions">`, but real exports emit `<note type="restrictions">`. Reading only the PDF would have produced an xpath that silently merged Restrictions text into the note column.
- **Check the element's cardinality in `lift.rng`, not just its shape.** An element wrapped in `<optional>` with no `zeroOrMore`/`oneOrMore` is capped at one occurrence. When the schema caps it, do **not** write defensive duplicate-handling for it — `sense/grammatical-info` is capped this way, and a proposed "warn on duplicates" helper (mirroring `extract_single_trait()`'s warning for `morph-type`) was correctly rejected as over-engineering. Precedent elsewhere in the codebase is not justification on its own; check whether that precedent's defensive branch is actually load-bearing before copying it. Record the guarantee as a note in the SPEC.md §3/§4 column table — *not* as a §8 "not yet specified" limitation, which would wrongly imply lossiness.
- **Decide which of the two multitext shapes the element has** — this drives both the read xpath and the write call:
  - **`<form lang>`-wrapped** (`lexical-unit`, `citation`, `note`, `definition`, custom `field`): the element wraps one `<form lang><text>` per writing system. Read with `./definition/form`; write with `add_multitext_children(node, values)`.
  - **`lang` on the element itself** (`gloss`): no wrapper — the element carries `lang` and a `<text>` child, and repeats directly under its parent. Read with `./gloss` (**no** `/form`); write with `add_multitext_children(sense_node, values, tag = "gloss")` and no wrapping element.
- Grep the existing fixtures for the element before assuming its shape:
  ```bash
  grep -rn "<note" tests/testthat/fixtures/lift2csv_entry-table/*.lift
  ```
  Then check whether occurrences are entry-level or sense-level, and tally any `type` attribute variants — a quick Python `xml.etree` script over `entry.findall('note')` is the reliable way, since grep can't tell you nesting depth.
- Ask the user to confirm ambiguous semantics in the FLEx UI. For `<note>` the user checked that filtering for non-blank Note in FLEx returned nothing for a project full of `type="restrictions"` notes — that is what established they are separate fields.

## 1. Get a real fixture

**First check whether the existing fixtures already contain the field** — often no new fixture is needed. Multi-lang gloss and `<definition>` were both already present in `Sena3.lift` (1708 senses with a `pt` gloss, 435 definitions), so that whole task ran on fixtures already in the repo. Use the step-0 Python tally to confirm coverage, not just presence.

Only if the field is genuinely absent, ask the user for a real FLEx export containing it, and put it in `tests/testthat/fixtures/lift2csv_entry-table/`. Do not hand-write one: a synthetic fixture only encodes what you already assumed, so it cannot surprise you. The real `note_and_phonology_notes.lift` immediately exposed the typed/untyped `<note>` distinction.

When you do add a new `.lift` fixture:

- Fixtures are auto-discovered — no test code changes needed. `tests/testthat/test-entry-table_end-to-end.R` globs `*.lift` from its fixture directory.
- `tests/testthat/fixtures/lift2csv_join-sense-entry-table/` is a **separate directory with its own copies** of the shared fixtures, not a symlink. Copy the fixture there too for join coverage.

## 2. TDD the read direction (lift2csv)

**Red.** Run the suite and inspect the auto-created baseline:

```bash
Rscript -e 'devtools::test(filter = "entry-table_end-to-end")'
```

A brand-new fixture produces a WARN and an auto-created snapshot, *not* a FAIL. That file is simply whatever today's code emits — read it and confirm the new field is absent. That absence is your red.

**Green.** Add the extraction to [R/entry_table.R](../../../R/entry_table.R), following the `citation` block as the template: `extract_multitext_element()` (from [R/entry_helpers.R](../../../R/entry_helpers.R)) then `pivot_wider(names_glue = "<field>_{lang}")`, then a `left_join` into `combined`.

Use an xpath predicate to exclude variants that are semantically different fields — e.g. `./note[not(@type)]/form`. Without it, two variants sharing a language collide in `pivot_wider`.

**Always return a *typed* empty tibble from every early-return path.** `map_df` over a zero-length list — or a bare `tibble()` returned when a node has no children — produces a tibble with **no columns**, and the downstream `left_join(by = "sense_guid")` then fails with `Join columns in 'x' must be present in the data`. Define the empty shape once and reuse it, *and* guard the outer call when the node list itself is empty (the empty-lexicon fixture has zero entries, which the inner guard never sees):

```r
empty_sense_meta <- tibble(sense_guid = character(), entry_id = character(),
                           grammatical_info = character())

sense_meta <- if (length(entries) == 0) {
  empty_sense_meta                                    # outer guard: no entries at all
} else {
  map_df(entries, ~{
    senses <- xml_find_all(.x, "./sense")
    if (length(senses) == 0) return(empty_sense_meta)  # inner guard: entry has no senses
    ...
  })
}
```

`extract_multitext_element()` already does this via its `empty_result`, which is why the entry-level path never trips over it — but any new extractor you write must.

**Sense-level fields use a parallel set of files and functions**, not the entry-level ones:

| entry-level | sense-level |
|---|---|
| [R/entry_table.R](../../../R/entry_table.R) | [R/sense_table.R](../../../R/sense_table.R) |
| [R/entry_helpers.R](../../../R/entry_helpers.R) | [R/sense_helpers.R](../../../R/sense_helpers.R) |
| `extract_multitext_element()` (keys `entry_id`) | `extract_sense_multitext_element()` (keys `sense_guid`, iterates senses) |
| `classify_entry_columns()` | `classify_sense_columns()` |
| [R/csv2lift_entry.R](../../../R/csv2lift_entry.R) / `entry_table_to_lift()` | [R/csv2lift_sense.R](../../../R/csv2lift_sense.R) / `attach_senses_to_lift()` |
| snapshots `entry-table_end-to-end/` | snapshots `sense-table_end-to-end/` |

`add_multitext_children()` is shared by both (pass `tag =` for the gloss-shaped case). One deliberate asymmetry: `classify_sense_columns()` treats an unrecognized column as a **hard error**, whereas `classify_entry_columns()` falls back to a last-underscore custom-field split — sense-level custom `<field>` elements aren't supported at all, so silently misclassifying one would be worse than failing. Preserve that unless you're adding sense-level custom fields.

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

A whole-file `cp` is right when the source snapshot is small. When it's `Sena3.csv` at 1717 rows, extract a **representative real row** instead, so the fixture stays focused and its expected `.lift` output is reviewable by eye:

```bash
python3 -c "
import csv
rows = list(csv.DictReader(open('tests/testthat/_snaps/sense-table_end-to-end/Sena3.csv')))
for r in rows:
    if r['definition_en'].strip() and r['definition_pt'].strip() and r['gloss_pt'].strip():
        print(r); break
"
```

Then pull the **matching** entry row (same `entry_id`) out of `_snaps/entry-table_end-to-end/Sena3.csv` for the paired `_entries.csv`, keeping both files' header order and values verbatim. Prefer a row whose text has no embedded quotes or commas — it keeps the fixture readable and sidesteps CSV-quoting noise in the diff. The rule the `cp` recipe exists to enforce still holds: every value must be copied from real reader output, never invented.

**Red.** Run `devtools::test(filter = "csv2lift_end-to-end")` and read the auto-created `.lift` snapshot. Expect the field to fall through to the generic custom-field branch — `note_en` produced `<field type="note">` instead of `<note>`. The stderr classification log makes this obvious.

**Sometimes there is no green step, and the fixture is the whole deliverable.** A new fixture can reveal that the code already handles the case correctly — multiple senses per entry turned out to already work in `attach_senses_to_lift()`, so `sena3_multiple_senses_per_entry` went from auto-created snapshot straight to accept with no implementation edit. Do not manufacture a change to make the cycle look conventional. Inspect the snapshot, confirm it is genuinely right (don't just note that it didn't error), accept it, and say plainly in the commit and in SPEC.md that the fixture closes a coverage gap rather than fixing a defect.

**Green.** Two edits:
- [R/entry_helpers.R](../../../R/entry_helpers.R) — add a branch to `classify_entry_columns()` mirroring the `citation` one (`^<field>_.+$` → `kind = "<field>"`), placed *before* the last-underscore custom-field fallback. Update the "known limitation" comment to name the new reserved prefix.
- [R/csv2lift_entry.R](../../../R/csv2lift_entry.R) — add a `<field>_cols <- filter(col_classes, kind == "<field>")` alongside the others, and an emit block mirroring citation's, positioned to match SPEC.md's canonical child order.

Review the diff, then `snapshot_accept("csv2lift_end-to-end/")`.

## 4. Documentation

- **SPEC.md §3** (or §4 for sense-level): add the column row, insert the classification step and renumber, extend the known-limitation sentence with the new reserved prefix, and update the canonical-child-order / form-order / omit-when-empty bullets.
  - The section may not have a **Column classification algorithm** block yet — §4 didn't until gloss/definition were added. Write one rather than trying to insert a step into a list that isn't there, and state that it must match exactly between directions.
  - Expect to **remove** known-limitation text, not only extend it. Fixing the English-only gloss made §4's whole "only the English gloss is captured" sentence obsolete; leaving it would have contradicted the new column rows.
- **SPEC.md §8**: record what you deliberately did *not* implement (e.g. typed notes), so the boundary is explicit rather than looking like an oversight — and delete the entries your change just implemented. Do not list a schema-guaranteed constraint here: a cap `lift.rng` enforces isn't an unimplemented feature, and belongs in the §3/§4 column table instead (see step 0).
- **README.md**: only if the CLI surface or examples change.

## Gotchas

- Run tests with `devtools::test()`, never bare `testthat::test_file()` — the latter fails with "requires 3rd edition".
- `snapshot_accept("name")` without the trailing slash silently matches nothing and reports "No snapshots to update" without erroring. Always re-run the tests to confirm the accept took.
- Pause at each red/green/refactor boundary so the user can commit — the history is meant to read as distinct TDD stages.
- Consult `plans/` for prior worked examples; save non-trivial plans there and keep them synced (see AGENTS.md).
