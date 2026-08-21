---
name: adding-a-lift-field
description: Add support for a new LIFT field/element to the CSV↔LIFT round-trip, covering both the lift2csv (read) and csv2lift (write) directions. Use when asked to support a LIFT element that isn't handled yet, at entry or sense level, whether it becomes a column on an existing table or a table of its own — e.g. a typed note or variant on an entry, an example sentence or additional gloss language on a sense. Also covers supporting an element at a level where it isn't yet read even though another level already handles it (e.g. sense-level notes once entry-level notes work).
---

# Adding a new LIFT field

Procedure for taking a LIFT element from unsupported to fully round-tripping.

**The ordering is the main thing this skill exists to convey: do the read direction first, then reuse its CSV output as the fixture for the write direction.** Do not hand-author CSV fixtures.

**Two paths run through [Get a real fixture](#get-a-real-fixture), [TDD the read direction](#tdd-the-read-direction-lift2csv), [TDD the write direction](#tdd-the-write-direction-csv2lift), and [Documentation](#documentation), and [Decide where it lives](#decide-where-it-lives-a-column-or-a-table-of-its-own) decides which.** A **column on an existing table** is the common case — read straight through and ignore [If it needs a table of its own](#if-it-needs-a-table-of-its-own). A **table of its own** is rarer and roughly 3× the work; those same four steps still apply, but [If it needs a table of its own](#if-it-needs-a-table-of-its-own) collects everything that changes, step by step.

Five worked examples run throughout:

- the **entry-level** plain `<note>` field (see `plans/entry-level-note.md`);
- the **sense-level** multi-lang `<gloss>` / `<definition>` pair;
- **`<pronunciation>`** (see `plans/entry-level-pronunciation.md`), the first element that did not fit an existing table at all;
- the **sense-level "General Note" + custom `<field>`** pair (see `plans/sense-level-note-and-custom-fields.md`), the first change to support an element *at a second level* when another level already handled it: extraction and emit code copy cleanly from the level that already works, but naming does not ([Understand the field](#understand-the-field-in-the-real-lift-model), [Decide where it lives](#decide-where-it-lives-a-column-or-a-table-of-its-own), [TDD the write direction](#tdd-the-write-direction-csv2lift));
- **typed `<note type=…>` at entry *and* sense level** (see `plans/typed-notes-entry-and-sense.md`), the first field keyed by an **open attribute** rather than having a fixed identity. It breaks two rules that hold everywhere else — the column is named from the tag and attribute rather than the FLEx label ([Understand the field](#understand-the-field-in-the-real-lift-model)), and the *same* name is deliberately shared across both levels ([Decide where it lives](#decide-where-it-lives-a-column-or-a-table-of-its-own)) — and is the first field that round-trips content-faithfully but not order-faithfully ([Documentation](#documentation)).

## Understand the field in the real LIFT model

- Read the two references in [SPEC.md's LIFT model references](../../../SPEC.md#lift-model-references) — `lift.rng` (what the schema permits) and the FLEx technical notes PDF (what FLEx does day to day).
- **Trust real FLEx exports over the PDF when they disagree.** For `<note>`, the PDF documents Restrictions as `<field type="restrictions">`, but real exports emit `<note type="restrictions">`. Reading only the PDF would have produced an xpath that silently merged Restrictions text into the note column.
- **Check the element's cardinality in `lift.rng`, not just its shape.** An element wrapped in `<optional>` with no `zeroOrMore`/`oneOrMore` is capped at one occurrence. When the schema caps it, do **not** write defensive duplicate-handling for it — `sense/grammatical-info` is capped this way, and a proposed "warn on duplicates" helper (mirroring `extract_single_trait()`'s warning for `morph-type`) was correctly rejected as over-engineering. Precedent elsewhere in the codebase is not justification on its own; check whether that precedent's defensive branch is actually load-bearing before copying it. Record the guarantee as a note in [SPEC.md's Entry Table](../../../SPEC.md#entry-table)/[Sense Table](../../../SPEC.md#sense-table) column table — *not* as a [Not Yet Specified](../../../SPEC.md#not-yet-specified) limitation, which would wrongly imply lossiness. Cardinality also decides whether the field can be a column at all — see [Decide where it lives](#decide-where-it-lives-a-column-or-a-table-of-its-own).
- **A `<zeroOrMore>` wrapper is not the only cardinality signal — read the element's own `<define>` for `<sch:assert>` rules too.** `translation-content`, `note-content`, `field-content`, and `multitext-content` (for `form`) all wrap a sibling in `zeroOrMore` at one level while asserting, inside that element's own content model, that no two siblings on one parent may share a `type`/`lang`. That assertion can settle a [Decide where it lives](#decide-where-it-lives-a-column-or-a-table-of-its-own) question the outer wrapper alone leaves open: `<translation>` is `zeroOrMore` under `<example>`, which taken alone points at "table of its own" (that step's rule), but the assertion plus real data (at most one per example in all but one instance, which violates the assertion) is what makes a single column safe instead. `git show 5c16259^:resources/lift-0.13.rng` has the historical schema text if the tracked copy is gone; grep it for `sch:assert` near the element.
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
- **Name the column from the FLEx UI label for that field at that level, not from the XML tag.** The same tag is a *different field* at a different level, and FLEx labels them differently: `entry/note` is "Note", but `sense/note` is "General Note" (both distinct again from typed notes like "Phonology Note"). Naming the sense column `note_<lang>` looks consistent in XML terms and is wrong in FLEx terms — users search the CSV for the name the UI shows them. It also collides (see [Decide where it lives](#decide-where-it-lives-a-column-or-a-table-of-its-own)). A screenshot of the field in the FLEx pane settles it faster than any amount of schema reading, so ask for one when a tag repeats across levels.
- **Exception — a field distinguished by an *open* attribute is named from the tag and that attribute, not from the FLEx label.** Typed notes are the worked example: FLEx labels `<note type="phonology">` "Phonology Note", but a `phonology_note_en` column is **indistinguishable from a custom `<field type="phonology_note">`** — both classifiers end in a last-underscore split, so telling them apart would mean hardcoding a closed list of note types that users are free to extend. Hence `note_<type>_<lang>`, keyed the way the XML keys it. Apply this whenever the attribute's value set is user data rather than a fixed vocabulary; the label rule above still governs fields whose identity is fixed (`note` vs `general_note`).
- **Before applying that exception, confirm the attribute actually keys a repeating sibling rather than a single fixed field — the FLEx UI, not the tag, decides which.** Typed notes and custom `<field type>` earn the exception because FLEx lets the user add another note/field of a new type, so two instances can coexist on one parent and the type has to live in the name to tell them apart. `<translation type=…>` looks identical by tag shape, but a screenshot of FLEx's Examples pane shows a Translation control with a Type *dropdown*, and is treated as one value per example, `type` as a plain `translation_type` value column instead, sitting alongside `translation_<lang>` rather than inside its name — even though the same pane can in practice show a second Translation control left at the same Type value (see [SPEC.md's Example Table](../../../SPEC.md#example-table)), so "nothing to add another of" is an assumption about the UI's intent, not something a screenshot rules out. Folding `type` into the name anyway breaks silently on a value set with no accompanying text (a type chosen but no translation typed in): a blank cell can assert nothing, so a row with a type but no text needs a name-based scheme to invent an event that never happened, or drop the value that did. Ask for the screenshot whenever an attribute's cardinality is ambiguous, not only when a tag repeats across levels (the case above) — but treat what it shows as evidence to weigh, not proof of the UI's constraints, since a control that can be duplicated with the same value picked twice does not, by itself, tell you whether that was intended.

## Decide where it lives: a column, or a table of its own

Every field this skill covered before `<pronunciation>` — `citation`, `note`, custom `field`, sense `gloss`/`definition` — is **at-most-one-per-parent**, and that is the only reason a flat `<prefix>_<lang>` column works at all. Settle this before writing any xpath, because it decides the whole shape of the work:

- **`<optional>` in `lift.rng` → a column.** One value per row. The remaining steps apply as written.
- **`<zeroOrMore>` / `<oneOrMore>` → probably its own table.** A single row cannot hold two values for one writing system. `<pronunciation>` is the worked example: `zhi-two-pronunciations-with-audio-and-ipa.lift` has one entry with two pronunciations whose forms share a single writing system (`zhi-fonipa-x-etic`: `tsēn` and `tsʼēn`). No prefix scheme represents that in one row, and `pivot_wider` would collide on the duplicate key. **Then read [If it needs a table of its own](#if-it-needs-a-table-of-its-own).** "Probably" is doing real work here — check [Understand the field](#understand-the-field-in-the-real-lift-model)'s schematron caveat first; a `zeroOrMore` sibling whose own content model caps it tighter (or whose FLEx UI shows one fixed control, not an add-another one) can still be a column.

Indexed column names (`pronunciation_1_<lang>`, `pronunciation_2_<lang>`) are the tempting way to dodge a new table. Reject them: the column set becomes data-dependent, and both classifiers then have to parse an index back out of every name.

Do not settle it from the schema alone — **tally the real fixtures (see [Understand the field](#understand-the-field-in-the-real-lift-model)) and check the worst case actually present.** The schema being permissive is an argument; an entry in the repo already holding two is proof, and it is what makes the case to the user.

**Ask the user before committing to a new table.** It is roughly three times the work of a column and adds a row to `R/table_registry.R` (which is what supplies its CLI flag and its `--table-dir` discovery (and its `--table <name>` reach), both automatically), so it is their call. Bring them the fixture tally, not just the schema quote. [SPEC.md's CLI shape section](../../../SPEC.md#csv2lift-cli-shape) already anticipates the answer being yes — "further tables are added as optional parameters as their round-trip support is implemented".

**Column names are one namespace across levels, not one per table — and nothing in this repo checks that for you.** This is the canonical explanation; later steps only cross-reference it. Two tables can each own a `note_en` without either classifier noticing, and this repo never joins the entry and sense tables to surface it — that join happens in downstream tooling now ([SPEC.md's cross-table collision bullet](../../../SPEC.md#column-classification)), so a clash ships silently in the two separate, individually-correct per-table CSVs and only becomes visible as `.x`/`.y` (or `_x`/`_y`) columns in whatever joins them later. [Understand the field](#understand-the-field-in-the-real-lift-model)'s FLEx-label rule usually prevents this for free (`note_` vs `general_note_`): make the names genuinely different because the fields genuinely are. Where a clash stays possible regardless — any two levels that both support custom `<field>`, since the type name comes from the user's data — there is no `suffix =` mechanism here to lean on; the collision is real and stays a downstream consumer's problem to resolve, which is exactly why it must be named in SPEC.md rather than left to be rediscovered.

**Sometimes the clash is the correct answer.** Typed notes deliberately share `note_<type>_<lang>` across both levels, and `note_restrictions_en` does exist on both tables in `sena3.lift` (61 entry-level notes against a single sense-level one — one instance on the far side is enough to trigger it). That is right, not a defect: the untyped split (`note_` vs `general_note_`) earned its keep because FLEx labels those two fields differently, but a *type's* label is identical at both levels — entry "Restrictions" and sense "Restrictions" are both just "Restrictions", and a per-level prefix would invent a distinction FLEx does not make. Ask which case you are in: **different fields that happen to share a tag → different names; the same field at two levels → the same name, and let whoever joins the tables handle the resulting clash.** Record the reasoning in [SPEC.md's cross-table collision bullet](../../../SPEC.md#column-classification), or someone will later "tidy" the names apart and break the classifier.

## Get a real fixture

> **New table?** [If it needs a table of its own](#if-it-needs-a-table-of-its-own) overrides this step: a new table is the exception to fixture auto-discovery, and its fixture directory is curated separately.

**First check whether the existing fixtures already contain the field** — often no new fixture is needed. Multi-lang gloss and `<definition>` were both already present in `sena3.lift`, so that whole task ran on fixtures already in the repo. Use the [Understand the field](#understand-the-field-in-the-real-lift-model) Python tally to confirm coverage, not just presence.

**Presence of the element is not coverage of its channels.** `<pronunciation>` was already in `zhi-note-and-phonology-notes.lift` — but all 4 occurrences were media-only, with zero `<form>` children. Building from that fixture alone would have shipped an all-blank transcription column that every test still passed, because there was no data to make it fail. Tally each channel separately, and if one is unrepresented, say so and ask for a fixture that has it rather than reporting the field as covered.

**To trim a large source file (e.g. `sena3.lift`) down to just the entries that exercise a channel**, use `scripts/copy-lift-entries.R <source_lift> [guid_file]` — it extracts specific `<entry>` elements by GUID and writes a new LIFT document to stdout, rather than hand-editing XML (see `scripts/copy-lift-entries.spec.md`, `README.md`'s usage example). Every `sena3-single-entry-*` and `sena3-gloss-initial-b` fixture in this repo was minted this way.

```bash
python3 -c "
import xml.etree.ElementTree as ET, glob
for f in sorted(glob.glob('tests/testthat/fixtures/lift2csv_entry-table/*.lift')):
    prons = [p for e in ET.parse(f).getroot().findall('entry') for p in e.findall('pronunciation')]
    print(f, len(prons), 'with form:', sum(1 for p in prons if p.findall('form')),
          'with media:', sum(1 for p in prons if p.findall('media')))
"
```

Only if the field is genuinely absent, ask the user for a real FLEx export containing it, and put it in `tests/testthat/fixtures/lift2csv_entry-table/`. Do not hand-write one: a synthetic fixture only encodes what you already assumed, so it cannot surprise you. The real `zhi-note-and-phonology-notes.lift` immediately exposed the typed/untyped `<note>` distinction.

**A fixture that has the field but is too large to review by eye is a third case, between "already covered" and "genuinely absent."** `sena3.lift`'s 1462 entries already have `sense/example`, so the check above says "covered" — but a snapshot built from all of it has over a thousand rows, which nobody can review line by line. Extract a handful of real `<entry>` elements into a small, focused fixture instead: the same rule [TDD the write direction](#tdd-the-write-direction-csv2lift) states for a CSV row ("extract a representative real row... so the fixture stays focused and its expected output is reviewable by eye") applied one level up, to a whole entry. Still verbatim, still not hand-written — only the selection is new, not the values. Look for one entry that happens to exercise several edge cases at once rather than one fixture per case; a single entry covering a blank instance, an invalid/duplicate one, and inline markup together stays as small as any one of the three would be alone. This does not need the user, since the source data already exists in the repo.

When you do add a new `.lift` fixture:

- Fixtures are auto-discovered — no test code changes needed. `expect_table_snapshots()` (`tests/testthat/helper-cli-snapshots.R`), which `tests/testthat/test-entry-table.R` is a one-line call to, globs `*.lift` from the fixture directory and raises one approval test per file.

## TDD the read direction (lift2csv)

> **New table?** [If it needs a table of its own](#if-it-needs-a-table-of-its-own) adds a whole new column of the grid below — positional keying when the element has no id/guid, and a classifier that starts strict.

**Red.** Run the suite and inspect the auto-created baseline:

```bash
Rscript -e 'devtools::test(filter = "entry-table")'
```

A brand-new fixture produces a WARN and an auto-created snapshot, *not* a FAIL. That file is simply whatever today's code emits — read it and confirm the new field is absent. That absence is your red.

**Green.** Add the extraction to [R/entry_table.R](../../../R/entry_table.R), following the `citation` block as the template: `extract_multitext_element()` (from [R/entry_helpers.R](../../../R/entry_helpers.R)) then `pivot_wider(names_glue = "<field>_{lang}")`, then a `left_join` into `combined`.

Use an xpath predicate to exclude variants that are semantically different fields — e.g. `./note[not(@type)]/form`. Without it, two variants sharing a language collide in `pivot_wider`.

**Keep write-direction machinery out of the read step.** `classify_*_columns()` exists only for csv2lift, so editing it while making the reader green costs you the sharpest write red. Adding the sense custom-field fallback during the read step turned [TDD the write direction](#tdd-the-write-direction-csv2lift)'s red from "hard error naming the unrecognized column" into "column classified fine, then silently dropped from the emitted XML" — still a real red, but one you have to go hunting for in the snapshot instead of one the test hands you. Touch only the extractor and its `pivot_wider`/`left_join` here.

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

**The codebase is a grid: one column per *level* (the parent element a table hangs off), one row per role that level needs filled.** Adding a field to a level that already exists touches only the cells that field needs:

| entry-level | sense-level | pronunciation-level | example-level |
|---|---|---|---|
| [R/entry_table.R](../../../R/entry_table.R) | [R/sense_table.R](../../../R/sense_table.R) | [R/pronunciation_table.R](../../../R/pronunciation_table.R) | [R/example_table.R](../../../R/example_table.R) |
| [R/entry_helpers.R](../../../R/entry_helpers.R) | [R/sense_helpers.R](../../../R/sense_helpers.R) | [R/pronunciation_helpers.R](../../../R/pronunciation_helpers.R) | [R/example_helpers.R](../../../R/example_helpers.R) |
| `extract_multitext_element()` (keys `entry_id`) | `extract_sense_multitext_element()` (keys `sense_guid`, iterates senses) | `extract_pronunciation_multitext()` (keys document position) | `extract_example_multitext()` (keys document position, iterates senses' examples) |
| `classify_entry_columns()` | `classify_sense_columns()` | `classify_pronunciation_columns()` | `classify_example_columns()` |
| [R/csv2lift_entry.R](../../../R/csv2lift_entry.R) / `entry_table_to_lift()` | [R/csv2lift_sense.R](../../../R/csv2lift_sense.R) / `attach_senses_to_lift()` | [R/csv2lift_pronunciation.R](../../../R/csv2lift_pronunciation.R) / `attach_pronunciations_to_lift()` | [R/csv2lift_example.R](../../../R/csv2lift_example.R) / `attach_examples_to_lift()` |
| snapshots `entry-table/` | snapshots `sense-table/` | snapshots `pronunciation-table/` | snapshots `example-table/` |

The grid keeps growing sideways, not down — a fifth level adds a fifth column of these same six rows, not a new kind of row. `example-level` is also the first column keyed by *two* things at once (`sense_guid` as the surviving FK, document position as the row identity), because it is a table hanging off another table (`sense`) rather than off `<entry>` directly — see "If it needs a table of its own" below for what that combination costs.

`add_multitext_children()` and `has_nonblank()` live in `entry_helpers.R` and are shared by all three (pass `tag =` for the gloss-shaped case).

**Review before accepting.** Expect *existing* fixtures to change if they already contained the element. Verify the new column's contents explicitly rather than eyeballing a huge diff:

```bash
python3 -c "
import csv
rows = list(csv.DictReader(open('tests/testthat/_snaps/entry-table/sena3.new.csv')))
nonblank = [r for r in rows if r.get('note_en','').strip()]
print(len(nonblank)); [print(r['entry_id'], repr(r['note_en'])) for r in nonblank]
"
```

Confirm the count matches what you found in [Understand the field](#understand-the-field-in-the-real-lift-model), and that no excluded variant leaked in. Then accept (trailing slash required — see Gotchas):

```bash
Rscript -e 'testthat::snapshot_accept("entry-table/")'
```

## TDD the write direction (csv2lift)

> **New table?** [If it needs a table of its own](#if-it-needs-a-table-of-its-own) adds a paired `entries.csv` you may have to produce first, a new `R/csv2lift_<name>.R`, a registry row, and a hard attach-order constraint.

**Use the read direction's output as the fixture.** This is the key step:

```bash
cp tests/testthat/_snaps/entry-table/zhi-note-and-phonology-notes.csv \
   tests/testthat/fixtures/csv2lift/zhi-note-and-phonology-notes/entries.csv
```

Each fixture is a directory, one CSV per table (`entries.csv`, `senses.csv`, `pronunciations.csv`, ...) — `test-csv2lift.R` discovers every such directory automatically, no test code change needed. `entries.csv` is required in each; the others are picked up whenever present. This gives real data on both sides, makes round-trip consistency structural, and removes any chance of inventing a column name the reader would never emit.

**"Optional" hides a coverage hole — check each fixture directory actually has the companion CSVs its source calls for.** `zhi-note-and-phonology-notes` had no `senses.csv`, so its approved `.lift` held **zero `<sense>` elements** while the source `.lift` had three: green tests, a reviewed snapshot, and an entire level untested. Nothing reports it, because a missing companion is indistinguishable from a fixture that legitimately has no senses. Backfill it as **its own commit, before** the change you came to make — otherwise several whole sense subtrees appear inside your field's diff and neither change is reviewable.

**Adding a column retroactively stales every existing write fixture whose source has that field.** The invariant this step exists to enforce — the write fixture *is* the reader's output — is not a one-time property. The moment `sense_table()` gains `note_<type>_<lang>`, `zhi-two-pronunciations-with-audio-and-ipa/senses.csv` quietly stops being reader output and under-tests the new column, and **nothing fails if you skip the refresh**. Once the read direction is green, re-copy every csv2lift fixture whose source `.lift` contains the new field — and leave the others strictly alone: their byte-identical snapshots are the regression net proving the writer still tolerates the new columns being absent entirely.

A whole-file `cp` is right when the source snapshot is small. When it's `sena3.csv` at 1717 rows, extract a **representative real row** instead, so the fixture stays focused and its expected `.lift` output is reviewable by eye:

```bash
python3 -c "
import csv
rows = list(csv.DictReader(open('tests/testthat/_snaps/sense-table/sena3.csv')))
for r in rows:
    if r['definition_en'].strip() and r['definition_pt'].strip() and r['gloss_pt'].strip():
        print(r); break
"
```

Then pull the **matching** entry row (same `entry_id`) out of `_snaps/entry-table/sena3.csv` for the paired `entries.csv`, keeping both files' header order and values verbatim. Prefer a row whose text has no embedded quotes or commas — it keeps the fixture readable and sidesteps CSV-quoting noise in the diff. The rule the `cp` recipe exists to enforce still holds: every value must be copied from real reader output, never invented.

**Red.** Run `devtools::test(filter = "csv2lift")` and read the auto-created `.lift` snapshot. It takes one of four shapes depending on what is already in place — name which one you got rather than reporting a generic failure:

| What's missing | The red looks like |
|---|---|
| No branch in the classifier, and the level has a custom-field fallback | Wrong element: `note_en` emitted as `<field type="note">`. The stderr classification log makes it obvious. |
| No branch, and the level's classifier is strict | Hard error: "Unrecognized sense column 'note_en'". |
| Classifier already updated, but no emit block | **Silent drop** — element simply absent from the `<sense>`. The weakest red; avoid creating it (see [TDD the read direction](#tdd-the-read-direction-lift2csv)). |
| A whole new table ([If it needs a table of its own](#if-it-needs-a-table-of-its-own)) | `argparser` fails in `preprocess_argv()` because the CLI has no such flag, so the snapshot is empty. |

The bottom two prove absence rather than announcing it, so read the snapshot rather than trusting the pass/fail count.

**Sometimes there is no green step, and the fixture is the whole deliverable.** A new fixture can reveal that the code already handles the case correctly — multiple senses per entry turned out to already work in `attach_senses_to_lift()`, so `sena3-multiple-senses-per-entry` went from auto-created snapshot straight to accept with no implementation edit. Do not manufacture a change to make the cycle look conventional. Inspect the snapshot, confirm it is genuinely right (don't just note that it didn't error), accept it, and say plainly in the commit and in SPEC.md that the fixture closes a coverage gap rather than fixing a defect.

**Green.** Two edits, plus one check:

- [R/entry_helpers.R](../../../R/entry_helpers.R) — add a branch to `classify_entry_columns()` mirroring the `citation` one (`^<field>_.+$` → `kind = "<field>"`). **Place it before every existing branch whose regex overlaps yours, not merely before the custom-field fallback.** The fallback is the usual collision but not the only one: `^note_.+$` (untyped notes) also matches `note_restrictions_en`, and would hand back `lang = "restrictions_en"`. Prefer a pattern that cannot overlap by construction — `^note_.+_[^_]+$` requires a second underscore, so it can never swallow an untyped `note_<lang>` — *and* order it defensively anyway. Update the "known limitation" comment to name the new reserved prefix.
- [R/csv2lift_entry.R](../../../R/csv2lift_entry.R) — add a `<field>_cols <- filter(col_classes, kind == "<field>")` alongside the others, and an emit block mirroring citation's, positioned to match SPEC.md's canonical child order.
- **A type-keyed column reuses the custom-field machinery instead of growing the classifier's schema.** For `note_<type>_<lang>`, return `kind = "typed_note"` and put the type in the *existing* `field_type` column — do not add a fifth `note_type` column, which costs an explicit `NA_character_` in a dozen other branches for a name four lines read. Do **not** instead reuse `kind = "note"` with `field_type = NA` for the untyped case: `cols$field_type == .x` yields `NA` for that row, and `cols[c(TRUE, NA), ]` returns an all-`NA` slice rather than nothing, so the emit loop writes a garbage element instead of skipping. The emit block is then the custom-field loop with the tag swapped (`"field"` → `"note"`); once two such loops exist at a level, extract them (`emit_typed_children()` in `entry_helpers.R`).
- **Then check for a cross-table name clash** if the new column's name could also occur at the other level (entry vs. sense). Nothing in this repo joins the two tables to surface it — that happens in downstream tooling — so a clash ships silently as two individually-correct per-table CSVs, and only becomes visible as `.x`/`.y` columns wherever they're eventually joined. [Decide where it lives](#decide-where-it-lives-a-column-or-a-table-of-its-own) has the rule for whether that's acceptable.

Review the diff, then `snapshot_accept("csv2lift/")`.

## Documentation

> **New table?** [If it needs a table of its own](#if-it-needs-a-table-of-its-own) replaces the first bullet below — a new table gets its own SPEC.md section rather than a column row.

- **[SPEC.md's Entry Table](../../../SPEC.md#entry-table)** (or [Sense Table](../../../SPEC.md#sense-table) for sense-level): add the column row, insert the classification step, extend the known-limitation sentence with the new reserved prefix, and update the canonical-child-order / form-order / omit-when-empty bullets.
  - The section may not have a **Column classification algorithm** block yet — [Sense Table](../../../SPEC.md#sense-table) didn't until gloss/definition were added. Write one rather than trying to insert a step into a list that isn't there, and state that it must match exactly between directions.
  - Expect to **remove** known-limitation text, not only extend it. Fixing the English-only gloss made [Sense Table](../../../SPEC.md#sense-table)'s whole "only the English gloss is captured" sentence obsolete; leaving it would have contradicted the new column rows.
- **[SPEC.md's Not Yet Specified section](../../../SPEC.md#not-yet-specified)**: record what you deliberately did *not* implement (e.g. typed notes), so the boundary is explicit rather than looking like an oversight — and delete the entries your change just implemented. Do not list a schema-guaranteed constraint here: a cap `lift.rng` enforces isn't an unimplemented feature, and belongs in the [Entry Table](../../../SPEC.md#entry-table)/[Sense Table](../../../SPEC.md#sense-table) column table instead (see [Understand the field](#understand-the-field-in-the-real-lift-model)).
- **[SPEC.md's Not Yet Specified section](../../../SPEC.md#not-yet-specified) also holds round-trip infidelities that are not lossiness** — a category the "not yet implemented" framing hides, so it is easy to leave undocumented. Attribute-keyed siblings are the worked example: the CSV carries one *global* column order (first appearance anywhere in the document) while each parent's element order is whatever FLEx emitted, so where the two disagree csv2lift re-orders that parent's siblings. 47 senses in `sena3.lift` hold `(phonology, sociolinguistics)` and re-emit as `(sociolinguistics, phonology)` — content preserved, order not. `<field type>` carries the identical latent exposure and has simply never fired. Say explicitly that this must **not** be "fixed" by sorting the columns: that is a re-sort, flatly against [SPEC.md's Data Handling rule](../../../SPEC.md#data-handling), and only appears to work because FLEx happens to emit its own siblings alphabetically. Check for this whenever you add an attribute-keyed field.
- **Re-derive any figure before writing it into SPEC.md** — counts there are load-bearing claims, and a plan's tally can predate the code or simply be wrong (one asserted 44 reordered senses where the fixture has 47).
- **[SPEC.md's cross-table collision bullet](../../../SPEC.md#column-classification)**: only when a column name could clash across levels — record which prefix belongs to which level and **why they differ, or why they deliberately don't** (see [Decide where it lives](#decide-where-it-lives-a-column-or-a-table-of-its-own)), so the next person doesn't "tidy" distinct names back into agreement or split shared ones apart.
- **README.md**: only if the CLI surface or examples change.
- Grep for stale TODOs naming the field (`scripts/lift2csv_entry-table.R` carried one for pronunciation for months).

**A column name is a public contract, so renaming one is never a one-line edit.** Expect to touch, in order: the reader's `names_glue`; the classifier's regex *and* the known-limitation comment naming the prefix; every write-direction fixture header that carries the column; the approved snapshots in both affected directories (`sense-table_`, `csv2lift_`); SPEC.md's column table, classification algorithm, known-limitation sentence and per-direction paragraph; and the plan file. Re-run and re-review each snapshot set separately rather than accepting in bulk — a pure rename must change headers only, and reviewing is what proves it did. In the plan file, add a revision note rather than rewriting the original text: the rename was a real decision, and editing it out hides why the name is what it is.

## If it needs a table of its own

Only if [Decide where it lives](#decide-where-it-lives-a-column-or-a-table-of-its-own) landed on `<zeroOrMore>` / `<oneOrMore>`. This does not replace the earlier steps — it collects what changes in each of them.

**Design ([Decide where it lives](#decide-where-it-lives-a-column-or-a-table-of-its-own)). A new table's parent doesn't have to be `<entry>`.** `<pronunciation>` hangs off entries, but the same reasoning applies one level down — `sense/reversal` (named in [SPEC.md's Not Yet Specified section](../../../SPEC.md#not-yet-specified) as not-yet-built) is `zeroOrMore` under `<sense>`, not `<entry>`, the same shape `sense/example` turned out to have ([SPEC.md's Example Table](../../../SPEC.md#example-table), `plans/sense-level-example-sentences.md`). Name the new table's foreign key after whichever parent it hangs off — `entry_id` for an entry-parented table, `sense_guid` for a sense-parented one — mirroring how `sense_table()` itself uses `entry_id` as its own FK. The parent can even be a table you're building in the same change, not only an existing one — the example table's `translation_type` turned out not to need this (one Translation per Example, per the FLEx UI), but a genuinely `zeroOrMore` child of a table you're building in the same change would. This choice determines the lookup xpath and the attach-call ordering below.

**Fixtures ([Get a real fixture](#get-a-real-fixture)).** A new table is the exception to fixture auto-discovery: it needs its own `test-<name>-table.R` and its own fixture directory before anything is discovered at all. The test file is two lines — a header comment and one `expect_table_snapshots("<table>", "lift2csv_<name>-table")` call, whose second argument is the fixture directory and whose first is the registry `name` passed through to `--table`. Give it its own file rather than adding it to a shared one: a `_snaps/` directory is named after the test file, so one file per table is what keeps `snapshot_accept("<name>-table/")` able to accept that table alone (the helper's own comment records why). Fixture directories are **curated per table, not kept at parity** — `lift2csv_sense-table/` does not carry `zhi-note-and-phonology-notes.lift`. A new table's directory needs only the fixtures that say something about it: the one with the data, one with parents but no instances, and the empty lexicon.

**Read direction ([TDD the read direction](#tdd-the-read-direction-lift2csv)).** Fill a whole new column of the grid, copied from the closest existing one (usually sense-level). Three things the column path never faces:

- **The grid's "sense-level" column is the existing sense table — columns on a sense row — not a new table hanging off individual senses.** The example table (`R/example_table.R`) is the worked case of this fourth, deeper shape: structurally identical to pronunciation-under-entry, but its extractor iterates `.//entry/sense/example` (not `.//entry/pronunciation`) and keys on `sense_guid`, not `entry_id`.
- **A table whose element has no id/guid is keyed by position.** `<entry>` has `guid` and `<sense>` has `id`, but `<pronunciation>` has neither, so `extract_pronunciation_multitext()` keys forms on the element's index and that index is dropped before output. Row order then *is* the identity — say so explicitly in SPEC.md, because re-sorting the CSV silently re-orders the emitted elements. `<example>` has no id either, one level further down, and faces the identical problem: `extract_example_multitext()` (`R/example_helpers.R`) keys the same way, over `.//entry/sense/example`, with `sense_guid` carried through separately as the surviving foreign key — the position provides row identity, the attribute provides the parent link, and neither can do the other's job.
- **A classifier ends in the last-underscore custom-field split only where custom `<field>` is actually supported at that level; otherwise it ends in a hard error.** `classify_entry_columns()` and `classify_sense_columns()` both have the fallback, because entry- and sense-level `<field>` round-trip. `classify_pronunciation_columns()` still errors on an unrecognized column, because pronunciation-level `<field>`/`<trait>` aren't read or written at all — silently misclassifying one as a form would be worse than failing. So a new level's classifier **starts strict**, and gains the fallback in the same change that implements custom fields for it, never before.

Also copy the CLI's empty-output convention: `lift2csv.R`'s shared `format_table_csv()` emits `""` rather than a bare header when `nrow(table) == 0`, so a lexicon with none of the element snapshots as an empty file — both via `--table <name>` to stdout and, for the write-fixture step below, via `--table-dir`.

**Write direction ([TDD the write direction](#tdd-the-write-direction-csv2lift)).** The fixture directory needs a matching `entries.csv` that may not exist yet. Produce it the same way — from `lift2csv.R --table entries`'s own output — which in turn means adding the `.lift` to `fixtures/lift2csv_entry-table/` as well. Adding `senses.csv` too is usually worth it: `zhi-two-pronunciations-with-audio-and-ipa` is the only fixture exercising entry + pronunciation + sense together, which is what actually proves the child ordering below instead of leaving it asserted. Add a row to `R/table_registry.R` for the new table — that is what makes `--table-dir` discover its CSV (and `--table <name>` reach it directly), and the one registry edit a new table needs; `test-csv2lift.R` itself needs no change, since it discovers fixture directories automatically.

**A new table stales nothing in existing csv2lift fixtures, but opens a coverage hole in them instead.** [TDD the write direction](#tdd-the-write-direction-csv2lift)'s column-case warning ("adding a column retroactively stales every existing write fixture whose source has that field") doesn't apply — no existing `<level>.csv` companion gains a column just because a new table exists elsewhere. What happens instead: any existing fixture directory whose parent rows already own real instances of the new element (in the source `.lift` that directory was built from) will produce an approved `.lift` with **zero** of them, silently, because that directory has no CSV for the new table and nothing forces one. Cross-reference every existing fixture's parent-row keys against the new table's own reader output before calling the write direction done, and add the missing companion CSV to each directory that needs one — leaving every other directory alone, since its byte-identical snapshot is the regression net proving the new table's CSV being absent still works.

Then a new `R/csv2lift_<name>.R` modelled on `csv2lift_sense.R`. Its registry row (added in the write-direction step above) is what wires it into both scripts' CLI surface — nothing in `scripts/csv2lift.R` itself is edited by hand. Four things differ from the column case:

- **Fail fast on an unmatched parent.** Look the parent up — `.//entry[@guid='...']` for an entry-parented table, `.//sense[@id='...']` for a sense-parented one — and `stop()` if it is missing, exactly as `attach_senses_to_lift()` does. A row must never be silently dropped.
- **A table can only attach after its parent nodes exist, and that is a correctness dependency, not just a readability one.** `<entry>` nodes all exist as soon as `entry_table_to_lift()` runs, which is why `attach_pronunciations_to_lift()` and `attach_senses_to_lift()` could go in either order without either one *failing* — row order there only decided XML child position. `<sense>` nodes don't exist until `attach_senses_to_lift()` creates them, so a table hanging off `<sense>` (e.g. `sense/example`) has no choice: its registry row **must** come after the `senses` row in `R/table_registry.R` — registry row order *is* attach order (the file's opening comment says so) — or every lookup fails with the fail-fast error above on the very first row. Work out the row's required position from the parent chain (entry → sense → example → ...) before adding it, not from what reads nicely.
- **Child order is set by registry row order, not by where you put the code**, for whichever ordering constraint above leaves free. A column's emit block sits inside `entry_table_to_lift()`, so its position in the function *is* its position in the XML. A table's elements are appended by a later pass over the whole document, so what fixes their place — among siblings that don't have a hard ordering dependency on each other — is the table's position among the rows of `R/table_registry.R`; pronunciations sit ahead of senses purely to keep `<pronunciation>` ahead of `<sense>`. Note the chosen order in SPEC.md, or the next person will look for it in the wrong file.
- **Re-derive `<pronunciation>`'s "omit when empty" rule for the new table rather than copying it — a positionally-keyed table's identity is its row order, and that changes what "empty" is allowed to do.** A column-shaped element can always be dropped for a blank row, because the parent row survives regardless — the entry or sense still exists with one fewer child either way. A table with no id/guid has no such fallback: if any parent's instances interleave blank and non-blank ones — check the new table's own reader output for this, not the schema — dropping the blank one's element shifts the position, and therefore the identity, of every instance after it on that parent. `<pronunciation>` omits a whole blank row and has gotten away with it only because no fixture happens to interleave blank and non-blank pronunciations on one entry; decide this explicitly for the new table instead of assuming the same default is safe.

**Documentation. A new table gets its own SPEC.md section**, not a row in someone else's. Give it the key/foreign-key line (state which parent's key the FK targets — `entry_id` or `sense_guid`), the column table, the classification algorithm, and a paragraph per direction — [SPEC.md's Pronunciation Table](../../../SPEC.md#pronunciation-table) is the model. State the attach-order constraint explicitly if the table's parent is itself attached by another table — this is the one fact that isn't visible from reading the column table alone. `SPEC.md` headings carry no numbers precisely so a new section can slot in anywhere without a renumbering cascade — give the new heading its own descriptive anchor and link to it (`[SPEC.md's <Name>](../../../SPEC.md#<anchor>)`) rather than reintroducing `§N`. Still grep the repo for the old heading's anchor slug (`grep -rn '#<old-anchor>'`) whenever you rename or restructure a heading, since `AGENTS.md` and this skill both link into `SPEC.md` from outside it. Also extend [SPEC.md's Entry Table](../../../SPEC.md#entry-table) canonical-child-order bullet. Neither the [CLI shape](../../../SPEC.md#csv2lift-cli-shape) list nor README needs a new per-table entry — `--table-dir` and the registry cover every table generically, which is the whole point of `R/table_registry.R` (see `plans/remaining-lift-fields.md`'s Phase T).

## Gotchas

- Run tests with `devtools::test()`, never bare `testthat::test_file()` — the latter fails with "requires 3rd edition".
- `snapshot_accept("name")` without the trailing slash silently matches nothing and reports "No snapshots to update" without erroring. Always re-run the tests to confirm the accept took.
- **"No snapshots to update" has a second, harmless cause**: a brand-new fixture's snapshot is written *directly* (with a WARN), not as a `.new` file, so there is nothing left to accept. Don't chase it as the trailing-slash bug — check whether the snapshot file already exists and is correct. It still needs reviewing; nothing vetted it.
- **Python's `xml.etree` does not implement the xpath you wrote in R.** `findall("note[not(@type)]")` raises `SyntaxError: invalid predicate` — ElementTree supports only a subset with no `not()`. When verifying an R xpath predicate from Python, filter in Python instead: `[n for n in sense.findall('note') if n.get('type') is None]`.
- Verify behaviour no fixture covers by hand rather than leaving it untested-and-unmentioned. The ">1 `<media>` per pronunciation warns and keeps the first" branch has no fixture, so it was checked against a throwaway LIFT file in the scratchpad and the result reported.
- Pause at each red/green/refactor boundary so the user can commit — the history is meant to read as distinct TDD stages.
- Consult `plans/` for prior worked examples; save non-trivial plans there and keep them synced (see AGENTS.md).
