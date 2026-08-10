---
name: adding-a-lift-field
description: Add support for a new LIFT field/element to the CSV↔LIFT round-trip, covering both the lift2csv (read) and csv2lift (write) directions. Use when asked to support a LIFT element that isn't handled yet, at entry or sense level, whether it becomes a column on an existing table or a table of its own — e.g. a typed note or variant on an entry, an example sentence or additional gloss language on a sense. Also covers supporting an element at a level where it isn't yet read even though another level already handles it (e.g. sense-level notes once entry-level notes work).
---

# Adding a new LIFT field

Procedure for taking a LIFT element from unsupported to fully round-tripping. Four worked examples run throughout:

- the **entry-level** plain `<note>` field (see `plans/entry-level-note.md`);
- the **sense-level** multi-lang `<gloss>` / `<definition>` pair;
- **`<pronunciation>`** (see `plans/entry-level-pronunciation.md`), the first element that did not fit an existing table at all;
- the **sense-level "General Note" + custom `<field>`** pair (see `plans/sense-level-note-and-custom-fields.md`), the first change to support an element *at a second level* when another level already handled it. That case is its own category of work: the extraction and emit code copy cleanly from the level that already works, but naming and the join view do not — see steps 0, 1 and 4.

The ordering matters and is the main thing this skill exists to convey: **do the read direction first, then reuse its CSV output as the fixture for the write direction.** Do not hand-author CSV fixtures.

## 0. Understand the field in the real LIFT model

- Read the two references in [SPEC.md](../../../SPEC.md) §1.1 — `lift.rng` (what the schema permits) and the FLEx technical notes PDF (what FLEx does day to day).
- **Trust real FLEx exports over the PDF when they disagree.** For `<note>`, the PDF documents Restrictions as `<field type="restrictions">`, but real exports emit `<note type="restrictions">`. Reading only the PDF would have produced an xpath that silently merged Restrictions text into the note column.
- **Check the element's cardinality in `lift.rng`, not just its shape.** An element wrapped in `<optional>` with no `zeroOrMore`/`oneOrMore` is capped at one occurrence. When the schema caps it, do **not** write defensive duplicate-handling for it — `sense/grammatical-info` is capped this way, and a proposed "warn on duplicates" helper (mirroring `extract_single_trait()`'s warning for `morph-type`) was correctly rejected as over-engineering. Precedent elsewhere in the codebase is not justification on its own; check whether that precedent's defensive branch is actually load-bearing before copying it. Record the guarantee as a note in the SPEC.md §3/§4 column table — *not* as a §9 "not yet specified" limitation, which would wrongly imply lossiness. Cardinality also decides whether the field can be a column at all — see step 1.
- **Decide which multitext shape the element has** — this drives both the read xpath and the write call:
  - **`<form lang>`-wrapped** (`lexical-unit`, `citation`, `note`, `definition`, custom `field`, `pronunciation`): the element wraps one `<form lang><text>` per writing system. Read with `./definition/form`; write with `add_multitext_children(node, values)`.
  - **`lang` on the element itself** (`gloss`): no wrapper — the element carries `lang` and a `<text>` child, and repeats directly under its parent. Read with `./gloss` (**no** `/form`); write with `add_multitext_children(sense_node, values, tag = "gloss")` and no wrapping element.
  - **An element can carry a second, non-multitext channel alongside its forms.** `<pronunciation>` interleaves `multitext-content` with `<media href>` — an attribute with no `lang` at all, so there is nothing to key a `_<lang>` column on and `add_multitext_children()` does not apply to it. It gets a plain column (`media_href`) and a direct `xml_add_child(node, "media", href = ...)`. Read the element's whole `<define>` in `lift.rng`, not just the part that looks like the field you expect.
- Grep the existing fixtures for the element before assuming its shape:
  ```bash
  grep -rn "<note" tests/testthat/fixtures/lift2csv_entry-table/*.lift
  ```
  Then check whether occurrences are entry-level or sense-level, and tally any `type` attribute variants — a quick Python `xml.etree` script over `entry.findall('note')` is the reliable way, since grep can't tell you nesting depth.
- Ask the user to confirm ambiguous semantics in the FLEx UI. For `<note>` the user checked that filtering for non-blank Note in FLEx returned nothing for a project full of `type="restrictions"` notes — that is what established they are separate fields.
- **Name the column from the FLEx UI label for that field at that level, not from the XML tag.** The same tag is a *different field* at a different level, and FLEx labels them differently: `entry/note` is "Note", but `sense/note` is "General Note" (both distinct again from typed notes like "Phonology Note"). Naming the sense column `note_<lang>` looks consistent in XML terms and is wrong in FLEx terms — users search the CSV for the name the UI shows them. It also collides (step 1). A screenshot of the field in the FLEx pane settles it faster than any amount of schema reading, so ask for one when a tag repeats across levels.

## 1. Decide where it lives: a column, or a table of its own

Every field this skill covered before `<pronunciation>` — `citation`, `note`, custom `field`, sense `gloss`/`definition` — is **at-most-one-per-parent**, and that is the only reason a flat `<prefix>_<lang>` column works at all. Settle this before writing any xpath, because it decides the whole shape of the work:

- **`<optional>` in `lift.rng` → a column.** One value per row. Steps 2–5 apply as written.
- **`<zeroOrMore>` / `<oneOrMore>` → probably its own table.** A single row cannot hold two values for one writing system. `<pronunciation>` is the worked example: `two_pronunciations_with_audio_and_IPA.lift` has one entry with two pronunciations whose forms share a single writing system (`zhi-fonipa-x-etic`: `tsēn` and `tsʼēn`). No prefix scheme represents that in one row, and `pivot_wider` would collide on the duplicate key.

Indexed column names (`pronunciation_1_<lang>`, `pronunciation_2_<lang>`) are the tempting way to dodge a new table. Reject them: the column set becomes data-dependent, and both classifiers then have to parse an index back out of every name.

Do not settle it from the schema alone — **tally the real fixtures (step 0) and check the worst case actually present.** The schema being permissive is an argument; an entry in the repo already holding two is proof, and it is what makes the case to the user.

**Ask the user before committing to a new table.** It is roughly three times the work of a column and adds a CLI flag to `scripts/csv2lift.R`, so it is their call. Bring them the fixture tally, not just the schema quote. `SPEC.md` §7 already anticipates the answer being yes — "further tables are added as optional parameters as their round-trip support is implemented".

**Column names are one namespace across levels, not one per table.** Two tables can each own a `note_en` without either classifier noticing — but they meet in the entry ⋈ sense join view, where `left_join()` silently resolves the clash to `note_en.x` / `note_en.y` and ships it into an approved, human-reviewed CSV. Step 0's FLEx-label rule usually prevents this for free (`note_` vs `general_note_`), which is the right fix: make the names genuinely different because the fields genuinely are. Where a clash stays possible regardless — any two levels that both support custom `<field>`, since the type name comes from the user's data — `join_sense_entry()` (`R/join_sense_entry.R`) disambiguates with an explicit `suffix = c("_sense", "_entry")` instead of dplyr's default. Check both mechanisms before adding a column at a level the join view covers.

**A new table's parent doesn't have to be `<entry>`.** `<pronunciation>` hangs off entries, but the same reasoning applies one level down — `sense/example` and `sense/reversal` (both named in SPEC.md §9 as not-yet-built) are `zeroOrMore` under `<sense>`, not `<entry>`. Name the new table's foreign key after whichever parent it hangs off — `entry_id` for an entry-parented table, `sense_guid` for a sense-parented one — mirroring how `sense_table()` itself uses `entry_id` as its own FK. The parent can even be a table you're building in the same change (e.g. a `translation` table hanging off `sense/example`), not only an existing one. This choice determines the lookup xpath and an ordering dependency in step 4 — read that before assuming entry-level mechanics apply unchanged.

## 2. Get a real fixture

**First check whether the existing fixtures already contain the field** — often no new fixture is needed. Multi-lang gloss and `<definition>` were both already present in `Sena3.lift` (1708 senses with a `pt` gloss, 435 definitions), so that whole task ran on fixtures already in the repo. Use the step-0 Python tally to confirm coverage, not just presence.

**Presence of the element is not coverage of its channels.** `<pronunciation>` was already in `note_and_phonology_notes.lift` — but all 4 occurrences were media-only, with zero `<form>` children. Building from that fixture alone would have shipped an all-blank transcription column that every test still passed, because there was no data to make it fail. Tally each channel separately, and if one is unrepresented, say so and ask for a fixture that has it rather than reporting the field as covered:

```bash
python3 -c "
import xml.etree.ElementTree as ET, glob
for f in sorted(glob.glob('tests/testthat/fixtures/lift2csv_entry-table/*.lift')):
    prons = [p for e in ET.parse(f).getroot().findall('entry') for p in e.findall('pronunciation')]
    print(f, len(prons), 'with form:', sum(1 for p in prons if p.findall('form')),
          'with media:', sum(1 for p in prons if p.findall('media')))
"
```

Only if the field is genuinely absent, ask the user for a real FLEx export containing it, and put it in `tests/testthat/fixtures/lift2csv_entry-table/`. Do not hand-write one: a synthetic fixture only encodes what you already assumed, so it cannot surprise you. The real `note_and_phonology_notes.lift` immediately exposed the typed/untyped `<note>` distinction.

When you do add a new `.lift` fixture:

- Fixtures are auto-discovered — no test code changes needed. `tests/testthat/test-entry-table_end-to-end.R` globs `*.lift` from its fixture directory. **The exception is a new table**, which needs its own `test-<name>-table_end-to-end.R` (a 10-line copy of the sense-table one) and its own fixture directory before anything is discovered at all.
- Fixture directories are **curated per table, not kept at parity** — `lift2csv_sense-table/` does not carry `note_and_phonology_notes.lift`. A new table's directory needs only the fixtures that say something about it: the one with the data, one with parents but no instances, and the empty lexicon.
- `tests/testthat/fixtures/lift2csv_join-sense-entry-table/` is a **separate directory with its own copies** of the shared fixtures, not a symlink. Copy the fixture there too for join coverage — but only if the field can actually reach that view, which is entry ⋈ sense. A pronunciation cannot, so copying it there would add a snapshot and no coverage.

## 3. TDD the read direction (lift2csv)

**Red.** Run the suite and inspect the auto-created baseline:

```bash
Rscript -e 'devtools::test(filter = "entry-table_end-to-end")'
```

A brand-new fixture produces a WARN and an auto-created snapshot, *not* a FAIL. That file is simply whatever today's code emits — read it and confirm the new field is absent. That absence is your red.

**Green.** Add the extraction to [R/entry_table.R](../../../R/entry_table.R), following the `citation` block as the template: `extract_multitext_element()` (from [R/entry_helpers.R](../../../R/entry_helpers.R)) then `pivot_wider(names_glue = "<field>_{lang}")`, then a `left_join` into `combined`.

Use an xpath predicate to exclude variants that are semantically different fields — e.g. `./note[not(@type)]/form`. Without it, two variants sharing a language collide in `pivot_wider`.

**Keep write-direction machinery out of the read step.** `classify_*_columns()` exists only for csv2lift, so editing it while making the reader green costs you the sharpest write red. Adding the sense custom-field fallback during the read step turned step 4's red from "hard error naming the unrecognized column" into "column classified fine, then silently dropped from the emitted XML" — still a real red, but one you have to go hunting for in the snapshot instead of one the test hands you. Touch only the extractor and its `pivot_wider`/`left_join` here.

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

**The codebase is a grid: one column per *level* (the parent element a table hangs off), one row per role that level needs filled.** Adding a field to a level that already exists touches only the cells that field needs; adding a level means filling a whole new column, copied from the closest existing one (usually sense-level):

| entry-level | sense-level | pronunciation-level |
|---|---|---|
| [R/entry_table.R](../../../R/entry_table.R) | [R/sense_table.R](../../../R/sense_table.R) | [R/pronunciation_table.R](../../../R/pronunciation_table.R) |
| [R/entry_helpers.R](../../../R/entry_helpers.R) | [R/sense_helpers.R](../../../R/sense_helpers.R) | [R/pronunciation_helpers.R](../../../R/pronunciation_helpers.R) |
| `extract_multitext_element()` (keys `entry_id`) | `extract_sense_multitext_element()` (keys `sense_guid`, iterates senses) | `extract_pronunciation_multitext()` (keys document position) |
| `classify_entry_columns()` | `classify_sense_columns()` | `classify_pronunciation_columns()` |
| [R/csv2lift_entry.R](../../../R/csv2lift_entry.R) / `entry_table_to_lift()` | [R/csv2lift_sense.R](../../../R/csv2lift_sense.R) / `attach_senses_to_lift()` | [R/csv2lift_pronunciation.R](../../../R/csv2lift_pronunciation.R) / `attach_pronunciations_to_lift()` |
| snapshots `entry-table_end-to-end/` | snapshots `sense-table_end-to-end/` | snapshots `pronunciation-table_end-to-end/` |

`add_multitext_children()` and `has_nonblank()` live in `entry_helpers.R` and are shared by all three (pass `tag =` for the gloss-shaped case).

**The "sense-level" column above is the existing sense table — columns on a sense row — not the same thing as a new table hanging off individual senses.** A table like `sense/example` is a fourth, deeper case: structurally identical to pronunciation-under-entry, but its extractor iterates `.//entry/sense/example` (not `.//entry/pronunciation`) and keys on `sense_guid`, not `entry_id`.

**A table whose element has no id/guid is keyed by position.** `<entry>` has `guid` and `<sense>` has `id`, but `<pronunciation>` has neither, so `extract_pronunciation_multitext()` keys forms on the element's index and that index is dropped before output. Row order then *is* the identity — say so explicitly in SPEC.md, because re-sorting the CSV silently re-orders the emitted elements. `sense/example` would face the same problem one level down (`<example>` has no id either); the fix is the same, just found via `.//entry/sense/example` instead of `.//entry/pronunciation`, with `sense_guid` (not `entry_id`) as the surviving foreign key.

**A classifier ends in the last-underscore custom-field split only where custom `<field>` is actually supported at that level; otherwise it ends in a hard error.** `classify_entry_columns()` and `classify_sense_columns()` both have the fallback, because entry- and sense-level `<field>` round-trip. `classify_pronunciation_columns()` still errors on an unrecognized column, because pronunciation-level `<field>`/`<trait>` aren't read or written at all — silently misclassifying one as a form would be worse than failing. So a new level's classifier **starts strict**, and gains the fallback in the same change that implements custom fields for it, never before.

Also copy the CLI's empty-output convention: `lift2csv_sense-table.R` emits `cat("")` rather than a bare header when `nrow(table) == 0`, so a lexicon with none of the element snapshots as an empty file.

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

## 4. TDD the write direction (csv2lift)

**Use the read direction's output as the fixture.** This is the key step:

```bash
cp tests/testthat/_snaps/entry-table_end-to-end/note_and_phonology_notes.csv \
   tests/testthat/fixtures/csv2lift/note_and_phonology_notes_entries.csv
```

The `_entries.csv` suffix is required — `test-csv2lift_end-to-end.R` globs `*_entries.csv` and picks up an optional matching `*_senses.csv` / `*_pronunciations.csv`. This gives real data on both sides, makes round-trip consistency structural, and removes any chance of inventing a column name the reader would never emit.

**A new table needs a matching `_entries.csv` that may not exist yet.** Produce it the same way — from `lift2csv_entry-table.R`'s own output — which in turn means adding the `.lift` to `fixtures/lift2csv_entry-table/` as well. Adding the `_senses.csv` too is usually worth it: `two_pronunciations_with_audio_and_IPA` is the only fixture exercising entry + pronunciation + sense together, which is what actually proves the child ordering below instead of leaving it asserted. Add the new suffix to the glob in `test-csv2lift_end-to-end.R` — this is the one test file a new table has to edit.

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

**Red.** Run `devtools::test(filter = "csv2lift_end-to-end")` and read the auto-created `.lift` snapshot. It takes one of four shapes depending on what is already in place — name which one you got rather than reporting a generic failure:

| What's missing | The red looks like |
|---|---|
| No branch in the classifier, and the level has a custom-field fallback | Wrong element: `note_en` emitted as `<field type="note">`. The stderr classification log makes it obvious. |
| No branch, and the level's classifier is strict | Hard error: "Unrecognized sense column 'note_en'". |
| Classifier already updated, but no emit block | **Silent drop** — element simply absent from the `<sense>`. The weakest red; avoid creating it (see step 3). |
| A whole new table | `argparser` fails in `preprocess_argv()` because the CLI has no such flag, so the snapshot is empty. |

The bottom two prove absence rather than announcing it, so read the snapshot rather than trusting the pass/fail count.

**Sometimes there is no green step, and the fixture is the whole deliverable.** A new fixture can reveal that the code already handles the case correctly — multiple senses per entry turned out to already work in `attach_senses_to_lift()`, so `sena3_multiple_senses_per_entry` went from auto-created snapshot straight to accept with no implementation edit. Do not manufacture a change to make the cycle look conventional. Inspect the snapshot, confirm it is genuinely right (don't just note that it didn't error), accept it, and say plainly in the commit and in SPEC.md that the fixture closes a coverage gap rather than fixing a defect.

**Green (a new column).** Two edits, plus one check:
- [R/entry_helpers.R](../../../R/entry_helpers.R) — add a branch to `classify_entry_columns()` mirroring the `citation` one (`^<field>_.+$` → `kind = "<field>"`), placed *before* the last-underscore custom-field fallback. Update the "known limitation" comment to name the new reserved prefix.
- [R/csv2lift_entry.R](../../../R/csv2lift_entry.R) — add a `<field>_cols <- filter(col_classes, kind == "<field>")` alongside the others, and an emit block mirroring citation's, positioned to match SPEC.md's canonical child order.
- **Then check the join view** if the new column's level appears in it. `join_sense_entry()` is a *third* consumer of column names that neither classifier sees (step 1), and it is where a cross-level clash surfaces — as `.x`/`.y` columns in an approved CSV. Adding sense-level notes forced the explicit `suffix =` there; the later rename to `general_note_<lang>` stopped the clash happening at all, and the suffix stayed as the fallback for the case still possible.

**Green (a new table).** A new `R/csv2lift_<name>.R` modelled on `csv2lift_sense.R`, plus a flag on `scripts/csv2lift.R`. Three things differ from the column case:

- **Fail fast on an unmatched parent.** Look the parent up — `.//entry[@guid='...']` for an entry-parented table, `.//sense[@id='...']` for a sense-parented one — and `stop()` if it is missing, exactly as `attach_senses_to_lift()` does. A row must never be silently dropped.
- **A table can only attach after its parent nodes exist, and that is a correctness dependency, not just a readability one.** `<entry>` nodes all exist as soon as `entry_table_to_lift()` runs, which is why `attach_pronunciations_to_lift()` and `attach_senses_to_lift()` could go in either order without either one *failing* — call order there only decided XML child position. `<sense>` nodes don't exist until `attach_senses_to_lift()` creates them, so a table hanging off `<sense>` (e.g. `sense/example`) has no choice: its attach call **must** come after `attach_senses_to_lift()` in `scripts/csv2lift.R`, or every lookup fails with the fail-fast error above on the very first row. Work out the attach-call order from the parent chain (entry → sense → example → ...) before wiring the CLI flag, not from what reads nicely.
- **Child order is set by call order, not by where you put the code**, for whichever ordering constraint above leaves free. A column's emit block sits inside `entry_table_to_lift()`, so its position in the function *is* its position in the XML. A table's elements are appended by a later pass over the whole document, so what fixes their place — among siblings that don't have a hard ordering dependency on each other — is the order `scripts/csv2lift.R` makes the `attach_*` calls; pronunciations are attached before senses purely to keep `<pronunciation>` ahead of `<sense>`. Note the chosen order in SPEC.md, or the next person will look for it in the wrong file.

Review the diff, then `snapshot_accept("csv2lift_end-to-end/")`.

## 5. Documentation

- **SPEC.md §3** (or §4 for sense-level): add the column row, insert the classification step and renumber, extend the known-limitation sentence with the new reserved prefix, and update the canonical-child-order / form-order / omit-when-empty bullets.
  - The section may not have a **Column classification algorithm** block yet — §4 didn't until gloss/definition were added. Write one rather than trying to insert a step into a list that isn't there, and state that it must match exactly between directions.
  - Expect to **remove** known-limitation text, not only extend it. Fixing the English-only gloss made §4's whole "only the English gloss is captured" sentence obsolete; leaving it would have contradicted the new column rows.
- **SPEC.md §9**: record what you deliberately did *not* implement (e.g. typed notes), so the boundary is explicit rather than looking like an oversight — and delete the entries your change just implemented. Do not list a schema-guaranteed constraint here: a cap `lift.rng` enforces isn't an unimplemented feature, and belongs in the §3/§4 column table instead (see step 0).
- **A new table gets its own SPEC.md section**, not a row in someone else's. Give it the key/foreign-key line (state which parent's key the FK targets — `entry_id` or `sense_guid`), the column table, the classification algorithm, and a paragraph per direction — §5 is the model. State the attach-call ordering constraint explicitly if the table's parent is itself attached by another table (see step 4) — this is the one fact that isn't visible from reading the column table alone. Inserting a section means **renumbering every later section and fixing the cross-references**, which are easy to miss: `grep -n "§[0-9]" SPEC.md` afterwards and check each one still points where it means to. Also extend §3's canonical-child-order bullet and §7's CLI list.
- **SPEC.md §6** (the join view): only when a column name could clash across levels — record which prefix belongs to which level and why they differ, so the next person doesn't "tidy" them back into agreement.
- **README.md**: only if the CLI surface or examples change — a new table always changes both, and is worth an example showing the new flag.
- Grep for stale TODOs naming the field (`scripts/lift2csv_entry-table.R` carried one for pronunciation for months).

**A column name is a public contract, so renaming one is never a one-line edit.** Expect to touch, in order: the reader's `names_glue`; the classifier's regex *and* the known-limitation comment naming the prefix; every write-direction fixture header that carries the column; the approved snapshots in all three affected directories (`sense-table_`, `join-sense-entry-table_`, `csv2lift_`); SPEC.md's column table, classification algorithm, known-limitation sentence and per-direction paragraph; and the plan file. Re-run and re-review each snapshot set separately rather than accepting in bulk — a pure rename must change headers only, and reviewing is what proves it did. In the plan file, add a revision note rather than rewriting the original text: the rename was a real decision, and editing it out hides why the name is what it is.

## Gotchas

- Run tests with `devtools::test()`, never bare `testthat::test_file()` — the latter fails with "requires 3rd edition".
- `snapshot_accept("name")` without the trailing slash silently matches nothing and reports "No snapshots to update" without erroring. Always re-run the tests to confirm the accept took.
- **"No snapshots to update" has a second, harmless cause**: a brand-new fixture's snapshot is written *directly* (with a WARN), not as a `.new` file, so there is nothing left to accept. Don't chase it as the trailing-slash bug — check whether the snapshot file already exists and is correct. It still needs reviewing; nothing vetted it.
- **Python's `xml.etree` does not implement the xpath you wrote in R.** `findall("note[not(@type)]")` raises `SyntaxError: invalid predicate` — ElementTree supports only a subset with no `not()`. When verifying an R xpath predicate from Python, filter in Python instead: `[n for n in sense.findall('note') if n.get('type') is None]`.
- Verify behaviour no fixture covers by hand rather than leaving it untested-and-unmentioned. The ">1 `<media>` per pronunciation warns and keeps the first" branch has no fixture, so it was checked against a throwaway LIFT file in the scratchpad and the result reported.
- Pause at each red/green/refactor boundary so the user can commit — the history is meant to read as distinct TDD stages.
- Consult `plans/` for prior worked examples; save non-trivial plans there and keep them synced (see AGENTS.md).
