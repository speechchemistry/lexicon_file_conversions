# Add sense-level `<example>` (example sentences) to lift2csv / csv2lift

## Context

**This is the largest remaining sense-level gap, and the right next task.**

`sense/example` is named in [SPEC.md](../SPEC.md) §9 twice, and it is the canonical worked example the `adding-a-lift-field` skill uses for its §6 "table of its own" path (five mentions — the skill was written in anticipation of this case). Today the round trip **silently drops every example sentence**: no `_snaps/csv2lift_end-to-end/*.lift` contains an `<example>`.

Implementing it also closes the §9 item it gates: the 744 `sense/example/note[@type="reference"]` occurrences in `Sena3.lift`.

A design sketch already exists at `plans/sense-level-note-and-custom-fields.md:134-139` (Follow-ups #1). **No new fixture is needed from the user** — every case is already in the repo.

## What the schema, the data, and the FLEx UI say

`lift.rng` (recover with `git show 5c16259^:resources/lift-0.13.rng`):

```xml
<zeroOrMore><element name="example"><ref name="example-content"/></element></zeroOrMore>

<define name="example-content">
  <optional><attribute name="source"/></optional>   <!-- the only attribute -->
  <interleave>
    <ref name="multitext-content"/>                 <!-- zeroOrMore <form lang><text> -->
    <ref name="extensible-content"/>                <!-- trait/field/annotation + dates -->
    <zeroOrMore><element name="translation"><ref name="translation-content"/></element></zeroOrMore>
    <zeroOrMore><element name="note"><ref name="note-content"/></element></zeroOrMore>
  </interleave>
</define>

<define name="translation-content">
  <ref name="multitext-content"/>
  <optional><attribute name="type"/><!-- back | free | literal --></optional>
  <sch:rule context="translation">
    <sch:assert test="not(preceding-sibling::translation[@type=current()/@type])">
      Translations should be of different types.
</define>
```

`<example>` has **no `id`/`guid`** — the same positional-identity situation as `<pronunciation>` (SPEC.md §5), one level deeper.

**The FLEx Examples pane is what settles the translation design** (user-supplied screenshot): each Example block shows one *Example* (multi-writing-system), one *Translation* (multi-writing-system), one *Type* **drop-down**, one *Reference* box, and *Publish Example In*. So `type` is an attribute **of the single translation**, not a key distinguishing sibling translations — which makes it a plain column, not part of a column name.

Tally of `Sena3.lift` (1717 senses, 1296 examples) — re-derive every figure before it goes into SPEC.md:

| examples per sense | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| senses | 466 | 1213 | 34 | 2 | 1 | 1 |

`zeroOrMore` genuinely fires → **table of its own** (SKILL.md §1). Example shapes, as (`@source`, #`form`, #`translation`, #`note`):

| count | shape |
|---|---|
| 659 | source + 1 note, no form, no translation |
| **407** | **completely empty `<example/>` — no attributes, no children** |
| 100 | 1 form + 1 translation |
| 70 | source + 1 form + 1 translation + 1 note |
| 29 | 1 form only |
| 15 | 1 translation only |
| 9 | source + 1 form + 1 note |
| 6 | source + 1 translation + 1 note |
| 1 | 1 form + **2 translations of the same type** (see below) |

Channel facts, all verified directly:
- `example/form` — **never more than one per example**; always `lang="seh"` in this corpus.
- `example/note` — at most one per example (744), always `type="reference"`, always `lang="en"`.
- `example/translation` — 1104 examples have none, **191 have exactly one**, 1 has two. **All 193 carry a `type`**; types are `Free translation` (190), `Literal translation` (2), `Back translation` (1). Forms per translation: 1 ×138, 2 ×37, **0 ×18**. Translation form langs: `pt` 167, `en` 45.
- `@source` is present on **exactly** the 744 note-bearing examples and is **byte-identical** to the note text in all 744. The screenshot confirms why: FLEx shows a single *Reference* box, and the exporter writes it to both channels.

## Design: one new table, `example`

One row per `sense/example`. **Foreign key `sense_guid`** (SKILL.md §6: name the FK after the parent it hangs off). **No primary key** — positional identity, so row order is load-bearing in both directions, exactly as SPEC.md §5 states for pronunciation.

| Column | LIFT source | Notes |
|---|---|---|
| `sense_guid` | parent `sense/@id` | foreign key → sense table |
| `example_source` | `example/@source` | FLEx's "Reference"; attribute of `<example>` itself, so it sorts with the metadata |
| `example_<lang>` (e.g. `example_seh`) | `example/form` | reserved prefix `example_`; the sentence itself |
| `translation_type` | `example/translation/@type` | plain value column — FLEx's Type drop-down. **Not** part of a column name |
| `translation_<lang>` (e.g. `translation_pt`) | `example/translation/form` | reserved prefix `translation_`; the translation text |
| `note_reference_<lang>` | `example/note[@type]/form` | reuses the existing `note_<type>_<lang>` typed-note scheme, which SPEC.md §2.2 states applies "at every level" |

**Why `translation_type` is a column and not a name component.** The typed-note / custom-field scheme (`note_<type>_<lang>`) exists because those elements *repeat* on one parent, keyed by an open attribute — the name is the only place the key can live. A translation does not repeat: FLEx offers one Translation with one Type per Example, and the data agrees (191 of 192). Folding the type into the header would also make the 18 translations that have a **type but no text** unrepresentable, since a blank cell cannot assert "this type exists and is empty". As a value column they round-trip exactly.

**Column classification algorithm** (strict — SKILL.md §6: a new level's classifier starts strict and gains a custom-field fallback only when example-level `<field>` is actually implemented):

1. Exact match `sense_guid`, `example_source`, `translation_type` → metadata.
2. `^note_.+_[^_]+$` → typed note, type + lang by last-underscore split.
3. `^example_.+$` → form, lang = remainder.
4. `^translation_.+$` → translation form, lang = remainder.
5. Else → **hard error**, as `classify_pronunciation_columns()` does.

**Step 1 is load-bearing ordering, in the way SPEC.md §3's step 3-before-4 is** — `example_source` matches `^example_.+$` and `translation_type` matches `^translation_.+$`, so both would otherwise classify as forms with `lang = "source"` / `lang = "type"`. Say "must precede" in the SPEC algorithm and comment it in the code. `media_href` never faced this, because it does not begin with `pronunciation_`.

Record the mirror-image limitation in SPEC.md §2.2, in the same class as the existing ones: a writing system coded `source` or `type` would be swallowed by step 1. None exists — the fixtures use only `en, ha, pt, qaa-x-spec, seh, zhi, zhi-Zxxx-x-audio, zhi-fonipa-x-{emic,etic,pitch}` — but the ordering makes it possible, so it is stated rather than defended against.

### Decisions carried into this design

**(a) `@source` and `note[@type="reference"]` get two columns, not one.** They are one FLEx field ("Reference") written twice by the exporter — identical in all 744 cases. Two columns is the faithful choice, and consistent with SPEC.md §2.1's established stance that the tool preserves what the export holds and makes anomalies *more* visible than FLEx does (the `Plural_seh`/`Plural_en` precedent). Collapsing to one column would also have to invent a `lang` for the note on write, which the source actually carries. Document in §9 that the two always agree in practice, that FLEx shows a single box, and that the tool does not reconcile them if a user edits one cell.

**(b) Emit `<example/>` for blank rows — this is a correctness rule, not a cosmetic one.** 407 of 1296 examples are bare `<example/>`. SPEC.md §2.3's "empty optional elements are never emitted" applies to elements *nested inside* a row, never to the row's own element. Six senses **interleave** empty and non-empty examples (`EF` ×4, `FE` ×1, `EE` ×1) — and when identity is purely positional, dropping an empty example **shifts the index of its surviving siblings**. That failure mode does not exist for `<pronunciation>`, which is what distinguishes the two cases.

Same principle one level down: **emit `<translation>` whenever `translation_type` is non-blank**, even with no text — that is what preserves the 18 empty translations.

**(c) The one duplicate-type translation: warn and keep the first.** Entry `d5cb3ce5-cbf9-4c51-8d1f-5964ce10a703` has an example with two `<translation type="Literal translation">`. FLEx's own UI cannot produce this (one Translation, one Type per Example), and `lift.rng`'s schematron explicitly forbids it — so it is invalid LIFT that FLEx emitted, not a shape the CSV declines to model. Warn on stderr naming the sense and keep the first, mirroring `extract_single_media_href()` (`R/pronunciation_helpers.R:30-43`) and `extract_single_trait()`. Do **not** hard-error: that would make `Sena3.lift` — the fixture six test files depend on — unconvertible. Do the dedup explicitly in the extractor *before* the pivot, since `pivot_wider`'s default on duplicate keys is silent list-columns. Record in §9 as the single known lossy case, 1 of 1296.

## Implementation — read direction (lift2csv) first

Per AGENTS.md and SKILL.md: read direction first, then reuse its CSV output verbatim as the write fixture. **Never hand-author a CSV fixture.** Pause at each red/green boundary to commit.

**New `R/example_helpers.R`** — the positional analogues of `R/sense_helpers.R:4,29`:

```r
extract_example_multitext(examples, xpath)
#   -> tibble(example_index = integer(), lang = character(), text = character())
extract_example_multitext_with_attribute(examples, parent_xpath, attr_name, value_col = "text")
keep_first_per_key(long, keys)        # warn + slice(1), mirrors extract_single_media_href()
classify_example_columns(col_names)   # strict; metadata exact-match FIRST
```

This is SKILL.md §3's "fourth, deeper case": it needs **both** channels — `sense_guid` as the surviving FK *and* a positional index as the join key. Take `sense_guid` from `xml_parent()` in the **meta stage only** and key the long tables purely on `example_index`, exactly as `pronunciation_table()` does (`R/pronunciation_table.R:26-28,43,47`). Keying on `sense_guid` would collide across a sense's 2–5 examples.

**Typed empty tibbles on every early-return path, plus an outer guard** (SKILL.md §3). Three call sites, all live in the chosen fixtures: the outer `length(examples) == 0` guard (hit by both `lela-teli-empty-lexicon.lift` with zero entries *and* `sena3_single_entry_plant.lift` with senses but no examples — two distinct paths); the inner `length(forms) == 0` guard (all 407 bare examples); and the inner-inner guard for a translation with no forms (the 18) — note that with `translation_type` as its own column, that guard no longer loses them.

**New `R/example_table.R`** — `example_table(LIFT_file)`, modelled on `R/pronunciation_table.R`, over `xml_find_all(doc, ".//entry/sense/example")` with `sense_guid` from `xml_attr(xml_parent(.x), "id")`, and `select(-example_index)` before returning.

The direct-child axis deliberately **excludes `sense/subsense/example`** — `Sena3.lift` has exactly one, under one of its 8 subsenses. `<subsense>` is unsupported (SPEC.md §9) and its senses have no row in the sense table, so an example keyed to one would have a dangling FK and hard-error on write. This mirrors how the typed-note extractors' `./note` axis already excludes `example/note` today. Record it in §9 next to the existing `<subsense>` bullet so the 1296 figure is reproducible.

**New `scripts/lift2csv_example-table.R`** — near-copy of `scripts/lift2csv_sense-table.R`, including its `if (nrow(table) == 0) cat("")` branch.

**New `tests/testthat/test-example-table_end-to-end.R`** — the 10-line glob loop copied from `test-sense-table_end-to-end.R`.

**New `tests/testthat/fixtures/lift2csv_example-table/`** — curated, not at parity (SKILL.md §6):

| fixture | why |
|---|---|
| `Sena3_gloss_initial_b.lift` | **primary**: 47 examples — 36 source+note-only, 6 bare, 2 form+translation, 2 form+translation+note+source, 1 form+note+source; translations in `pt` and `en`, both 1-form and 2-form; one sense with 2 examples. Small enough to review by eye |
| `sena3_single_entry_two_custom_fields_river_mud.lift` | minimal: 1 example, source + reference note, no form, no translation |
| `sena3_example_duplicate_translation.lift` (new, minted in-repo) | the only fixture proving (b)'s sibling shift and (c)'s warning |
| `sena3_single_entry_plant.lift` | senses present, zero examples |
| `lela-teli-empty-lexicon.lift` | zero entries |
| `Sena3.lift` | full scale; the source of every SPEC figure and the only fixture hitting the warn path |

The new fixture needs nothing from the user — entry `d5cb3ce5` covers a bare `<example/>` **followed by** a full one (the `EF` interleave), the duplicate `Literal translation`, and `<span lang="en">` markup inside both an example form and a translation form:

```bash
echo d5cb3ce5-cbf9-4c51-8d1f-5964ce10a703 | \
  Rscript scripts/copy-lift-entries.R tests/testthat/fixtures/lift2csv_sense-table/Sena3.lift -
```

Note `copy-lift-entries.R` rewrites `dateModified` to now (`scripts/copy-lift-entries.spec.md` §1) — mint it once and commit it rather than regenerating. Do **not** copy any example fixture into `fixtures/lift2csv_join-sense-entry-table/`: examples cannot reach that view (SKILL.md §2).

**Red:** with only the fixtures and test file in place, `devtools::test(filter = "example-table")` errors — the script does not exist. **Green:** implement, then *read* the auto-created snapshots (a new fixture writes its snapshot directly with a WARN, so nothing has vetted it), verify counts against the tally above with a Python pass, then `snapshot_accept("example-table_end-to-end/")` — **trailing slash required**. No other snapshot should move.

## Implementation — write direction (csv2lift)

**Fixtures, copied from the reader's own output** (`cp` from `_snaps/example-table_end-to-end/` into `fixtures/csv2lift/<stem>_examples.csv`).

**No existing `*_senses.csv` goes stale.** `sense_table()` is untouched, so every sense CSV remains byte-identical reader output — SKILL.md §4's retro-staling rule fires when a column is added to an *existing* table, and a new table stales nothing. Confirm by re-running rather than assuming.

What this *does* create is SKILL.md §4's coverage hole: a stem whose senses own examples in the source but has no `_examples.csv` produces an approved `.lift` with zero `<example>` — green, reviewed, and untested. Six existing stems are affected (`sena3_inline_span_markup` 2 examples, `sena3_note_trailing_whitespace` 2, `sena3_entry_and_sense_typed_notes` 1, `sena3_gloss_and_definition_multilang` 1, `sena3_multiple_senses_per_entry` 1, `sena3_sense_note_and_field` 1) — **verify this list against the code's own output before relying on it**. Leave `sena3_single_entry_plant`, `note_and_phonology_notes` and `two_pronunciations_with_audio_and_IPA` strictly alone: their byte-identical snapshots are the regression net proving the writer still tolerates the flag being absent.

Two new stems need a full set (`_entries.csv` + `_senses.csv` + `_examples.csv`), produced from the entry and sense readers' own output: `sena3_example_duplicate_translation` (small, review end-to-end by eye) and `Sena3_gloss_initial_b` (47 examples of coverage — extract a representative real row per SKILL.md §4 rather than the whole 48-entry file).

**New `R/csv2lift_example.R`** — `attach_examples_to_lift(doc, example_table)`, modelled on `R/csv2lift_sense.R`:
- Look up `.//sense[@id='%s']` from `sense_guid`; **hard error** if missing, matching `R/csv2lift_sense.R:22-28`. A row is never silently dropped.
- `xml_add_child(sense_node, "example")` — **unconditional**, per (b); then `source` attribute when non-blank.
- Child order inside `<example>`: `<form>`, `<translation>`, `<note>` — which **matches the source** in every observed shape.
- `<translation>` emitted when `translation_type` is non-blank **or** any `translation_<lang>` is non-blank; `type` attribute set when non-blank; text via `add_multitext_children()`.
- `<note type="reference">` via the existing `emit_typed_children()` (`R/entry_helpers.R:183`), reused unchanged.

**Modify `scripts/csv2lift.R`** — add `--examples`, called **strictly after** `attach_senses_to_lift()`: `<sense>` nodes do not exist until that runs, so this is a correctness dependency, not a readability one (SKILL.md §6). Final order: `entry_table_to_lift()` → `attach_pronunciations_to_lift()` → `attach_senses_to_lift()` → `attach_examples_to_lift()`.

Add an up-front usage guard the script does not currently need: `--examples` without `--senses` should `stop()` immediately naming the cause, rather than producing a per-row "sense_guid not found" that reads as a data error when it is a CLI error.

**Modify `tests/testthat/test-csv2lift_end-to-end.R`** — add `_examples.csv` to the companion glob. The only test file needing an edit.

**Red:** `argparser` fails in `preprocess_argv()` because there is no such flag, so the snapshot is empty — SKILL.md §4's fourth red shape. **Green:** implement, review, `snapshot_accept("csv2lift_end-to-end/")`.

## Refactor

Four parallel `*_table.R` / `*_helpers.R` / `csv2lift_*.R` triples will exist. `extract_pronunciation_multitext()` and `extract_example_multitext()` are the same positional shape; the `*_multitext_with_attribute` variants will have three copies (`R/entry_helpers.R`, `R/sense_helpers.R`, new) — past the rule of three, so fold them into one parameterised helper. Re-run the full suite before calling it done.

Optionally align `<pronunciation>`'s all-blank-row rule to always-emit for consistency with (b) — no approved pronunciation snapshot exercises the drop branch (`R/csv2lift_pronunciation.R:36-38`), so this moves zero snapshots. If left divergent, document why in both sections.

**Revision note (post-implementation).** Neither optional item above was taken:

- The write-direction emit primitives (`has_nonblank()`, `add_multitext_children()`, `emit_typed_children()`) are already shared across all three levels without duplication — `R/csv2lift_example.R` reuses them as-is, matching the refactor the pronunciation plan actually completed. The read-direction *extractors*, however, are a deliberate per-level "grid" (SKILL.md's own framing: one column per level, one row per role), and the existing entry/sense `*_multitext_with_attribute` pair was never unified despite being just as duplicative — direct precedent that this codebase keeps per-level extractors separate rather than generalizing across levels. Forcing a merge here would also cross a real type boundary (character keys for entry/sense vs. an integer positional key for example), adding a parameter and branching that outweighs the ~15 lines saved. Left as three separate functions.
- `<pronunciation>`'s all-blank-row rule was left as omit-when-empty rather than switched to always-emit, to keep this change scoped to the example table. The divergence is documented in SPEC.md §2.3.

## Documentation

- **New SPEC.md §6 "Example table"**, placed after the sense table it hangs off, which **renumbers §6–§9 → §7–§10**. There are ~31 `§n` references in SPEC.md and ~14 across SKILL.md / AGENTS.md / README.md — do the renumber in one commit and `grep -n "§[0-9]"` afterwards, checking each still points where it means to. Model on §5: key/FK line, column table, classification algorithm (must match exactly between directions), no-PK/row-order rule, a paragraph per direction, the always-emit deviation, and the attach-order constraint — the one fact not visible from the column table.
- **SPEC.md §4**: extend the sense canonical-child-order bullet to end `…, then <example>s`, appended by a later pass fixed by call order in `scripts/csv2lift.R`. **State that this disagrees with FLEx's own order**, which puts `<example>` *before* `<note>` (412 senses are `grammatical-info, gloss, example, note`). Permitted by §2.3's `<interleave>` argument, but it is the first emitted-order divergence from the source, and reviewers of the round-trip diff will notice it.
- **SPEC.md §2.2**: add `example_`, `translation_` to the reserved-prefix list (noting they are reserved only on the example table) and to the known-limitation sentence.
- **SPEC.md §2.3**: state that omit-when-empty stops at the row — a positionally-keyed table emits its element for every row — with the 407 figure and the interleave argument.
- **SPEC.md §7** (renumbered CLI): add `--examples` and the `--examples`-requires-`--senses` guard.
- **SPEC.md §10** (renumbered): delete the "Example sentences" bullet and the `sense/example/note[@type="reference"]` half of the typed-note bullet (keep `sense/subsense/note`); add bullets for the duplicate-translation loss (1 of 1296, with the schematron quote), the `@source`/reference-note redundancy, the `subsense/example` exclusion, and example-level `trait`/`field`/`annotation`/date attributes. Check whether the attribute-keyed sibling re-order infidelity now applies to anything here — with `translation_type` as a value column, it should not.
- **README.md**: add `lift2csv_example-table.R` and a `--examples` example.
- Grep for stale TODOs naming examples.

## Commit sequence

Pause at each boundary so the history reads as distinct TDD stages (SKILL.md Gotchas).

0. **Save this plan** to `plans/sense-level-example-sentences.md` — its own new file, per AGENTS.md; re-sync it whenever the design shifts.
1. **Read red** — fixture dir + `test-example-table_end-to-end.R` only.
2. **Read green** — `R/example_helpers.R` (extractors only, **no classifier** — SKILL.md §3), `R/example_table.R`, `scripts/lift2csv_example-table.R`; verify and accept `example-table_end-to-end/`. The SPEC renumber rides here.
3. **Write red** — `_examples.csv` fixtures for the two new stems and the six affected existing ones, plus the `test-csv2lift_end-to-end.R` glob edit.
4. **Write green** — `classify_example_columns()`, `R/csv2lift_example.R`, `--examples` + the usage guard; review and accept `csv2lift_end-to-end/`.
5. **Refactor** — with the suite green.
6. **Docs** — remaining SPEC.md and README.md edits.

Do not merge 1–2 or 3–4, and do not touch `classify_example_columns()` during step 2: SKILL.md §3 warns that doing so downgrades step 3's red from a clean `argparser` failure to a silent drop.

## Verification

1. `Rscript -e 'devtools::test()'` — full suite green.
2. Read direction checked against the source by hand, not by eyeballing the diff:
   ```bash
   python3 -c "
   import csv
   rows = list(csv.DictReader(open('tests/testthat/_snaps/example-table_end-to-end/Sena3_gloss_initial_b.csv')))
   print(len(rows))                                                   # expect 47
   print(sum(1 for r in rows if r['example_source']))                 # expect 39
   print(sum(1 for r in rows if not any(v.strip() for v in r.values())))  # expect 6 bare examples
   print(sum(1 for r in rows if r['translation_type']))               # expect 4
   "
   ```
3. Confirm the 18 empty translations survive in the full file — `translation_type` filled with every `translation_<lang>` blank — and that they re-emit as `<translation type="Free translation"></translation>`.
4. Confirm the write direction recovers the empty examples: `grep -c "<example" _snaps/csv2lift_end-to-end/sena3_example_duplicate_translation.lift` — expect 2, in source order, the bare one first.
5. Confirm the duplicate-translation warning fires on `Sena3.lift`, naming the sense.
6. Closed round trip by hand for the primary fixture:
   ```bash
   Rscript scripts/lift2csv_example-table.R \
     tests/testthat/fixtures/lift2csv_example-table/Sena3_gloss_initial_b.lift > /tmp/ex.csv
   Rscript scripts/csv2lift.R <entries.csv> --senses <senses.csv> --examples /tmp/ex.csv | grep -A6 "<example"
   ```
7. Confirm `entry-table_end-to-end/`, `sense-table_end-to-end/`, `pronunciation-table_end-to-end/` and `join-sense-entry-table_end-to-end/` snapshots are all unchanged.
