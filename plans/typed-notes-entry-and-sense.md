# Typed `<note type="...">` at entry and sense level

## Context

`plans/sense-level-note-and-custom-fields.md` follow-up #3 — *"Typed sense notes — `note_<type>_<lang>`
columns; design shared with entry-level typed notes"*. Today both directions handle only the **untyped**
`<note>` (entry column `note_<lang>`, sense column `general_note_<lang>`); every typed note is dropped
by lift2csv and misclassified by csv2lift. SPEC.md §9 records the deferral and already names the
intended design: "type-keyed columns analogous to custom `<field>` handling".

**Depends on `plans/inline-span-markup.md` landing first.** 120 of 199 Sena3 phonology notes contain an
inline `<span lang="seh">`; with spans preserved, the new columns are born faithful instead of needing
~128 cells re-accepted later.

Census of the existing fixtures — **no new `.lift` fixture is needed**, every channel is already covered:

| level | types present | counts |
| --- | --- | --- |
| `entry/note[@type]` | `restrictions` only, lang `en`, always one `<form>`, no spans | 61 in `Sena3.lift`, 3 in `Sena3_gloss_initial_b.lift` |
| `entry/sense/note[@type]` | phonology 199, sociolinguistics 126, grammar 31, source 31, semantics 18, restrictions 1 | 406 in `Sena3.lift`; 16 in `Sena3_gloss_initial_b`; 5 in `note_and_phonology_notes`; 3 in `two_pronunciations_with_audio_and_IPA` |

Cardinality: **max same-type-per-parent is 1 in every fixture**, which is what permits a flat column.
`lift.rng` wraps `note` in `zeroOrMore`, so the schema does *not* guarantee it — per the skill's step 1
the justification is the fixture tally, and SPEC must say so rather than implying a schema cap.

Out of scope, and already excluded by the existing direct-child `./note` axis:
`sense/example/note[@type="reference"]` (744 in Sena3, gated behind example support) and
`sense/subsense/note` (1).

## Naming: `note_<type>_<lang>` at both levels, deliberately shared

Confirmed with the user. This deviates from the skill's "name the column from the FLEx UI label" rule
(FLEx labels these "Phonology Note", "Restrictions") because the type vocabulary is open user data — a
label-derived `phonology_note_en` cannot be told from a custom field without hardcoding a closed list of
types.

It also means `note_restrictions_en` exists on **both** tables (Sena3 has 61 entry-level `restrictions`
notes and one sense-level one), so `join_sense_entry()`'s existing `suffix = c("_sense", "_entry")` fires
on real data for the first time, producing `note_restrictions_en_sense` / `note_restrictions_en_entry` in
the Sena3 join snapshot.

That is the *right* outcome, and the reasoning has to be recorded or someone will "tidy" the names back
into a `note_` / `general_note_`-style split and break the classifier. The untyped split earned its keep
because FLEx genuinely labels those two fields differently ("Note" at entry level vs "General Note" at
sense level) — the names differ because the fields differ. Typed notes use the *same* FLEx label at both
levels: entry "Restrictions" and sense "Restrictions" are both just "Restrictions". An artificial
`sense_note_` prefix would mark a distinction FLEx does not make, and the join view's suffix is exactly
the mechanism for two identically-named fields at different levels — which is what SPEC §6 already says
it is for.

## Read direction

Both extractors already exist and need **no change** — `extract_multitext_with_attribute()`
([R/entry_helpers.R](../R/entry_helpers.R)) and `extract_sense_multitext_with_attribute()`
([R/sense_helpers.R](../R/sense_helpers.R)) hardcode `./form` children, which is `<note>`'s exact shape,
and their `empty_result` is already the typed empty tibble the skill's step-3 rule demands.

[R/entry_table.R](../R/entry_table.R), after the `notes_wide` block, mirroring `fields_wide`:

```r
# typed entry-level notes: <note type="restrictions"> etc. are separate FLEx fields that reuse the
# <note> element, so they get type-keyed columns like custom <field>s rather than merging into
# note_<lang> above. [@type] is the exact complement of the [not(@type)] predicate used there.
typed_notes_long <- extract_multitext_with_attribute(entries, "./note[@type]", "type", "note_text")

typed_notes_wide <- typed_notes_long |>
  pivot_wider(id_cols = entry_id, names_from = c(type, lang),
              names_glue = "note_{type}_{lang}", values_from = note_text)
```

then append `left_join(typed_notes_wide, by = "entry_id")` to the `combined` chain.
[R/sense_table.R](../R/sense_table.R) gets the same with
`extract_sense_multitext_with_attribute(senses, "./note[@type]", "type", "note_text")`,
`id_cols = sense_guid`, and `left_join(typed_notes_wide, by = "sense_guid")` appended.

**Appended at the end of both chains, not adjacent to the untyped note column**, so the snapshot diff is
purely additive at the right edge of the header — the only thing that makes a 1717-row `Sena3.csv` diff
reviewable. CSV column order has never matched XML child order anyway (entry `<field>` columns already
precede `citation_`/`note_` while the elements follow them).

Expected new columns, for the review checklist — column order is first appearance of the `(type, lang)`
**pair** in document order:

| snapshot | new columns (non-blank counts) |
| --- | --- |
| `entry-table/Sena3.csv` | `note_restrictions_en` (61) |
| `entry-table/Sena3_gloss_initial_b.csv` | `note_restrictions_en` (3) |
| `sense-table/Sena3.csv` | `note_sociolinguistics_en`(126), `note_phonology_en`(199), `note_grammar_en`(31), `note_semantics_en`(11), `note_source_en`(31), `note_semantics_pt`(8), `note_restrictions_en`(1) |
| `sense-table/Sena3_gloss_initial_b.csv` | `note_grammar_en`(2), `note_phonology_en`(7), `note_sociolinguistics_en`(5), `note_semantics_en`(1), `note_source_en`(1) |
| `sense-table/note_and_phonology_notes.csv` | `note_phonology_en`(2), `note_source_en`(3) |
| `sense-table/two_pronunciations_with_audio_and_IPA.csv` | `note_source_en`(2), `note_phonology_en`(1) |
| `join-sense-entry-table/Sena3.csv` | the 7 sense + 1 entry columns, `note_restrictions_en` split into `…_sense` / `…_entry` |
| `join-.../note_and_phonology_notes.csv`, `join-.../two_pronunciations…csv` | +2 sense columns each, no suffixing |
| every other snapshot, all of `pronunciation-table/` | unchanged |

Two review traps that look like bugs and aren't: `note_semantics_en` and `note_semantics_pt` are **not
adjacent** in Sena3's header (the first `pt` semantics form appears after the first `source` form), and
`note_semantics_en` is 11 not 10 (10 `en`-only notes plus 1 inside the single `en`+`pt` element).

## Write direction

**Classifiers.** [R/entry_helpers.R](../R/entry_helpers.R) — insert **immediately before** the existing
`^note_.+$` branch. Placement is load-bearing: that branch matches `note_restrictions_en` too and would
hand back `lang = "restrictions_en"`.

```r
# Typed notes are type-keyed exactly like custom <field>s: note_<type>_<lang>, split on the LAST
# underscore. This pattern requires a second underscore after the prefix so it can never swallow an
# untyped note_<lang> column — but it must still precede the untyped branch below, which would
# otherwise match first and read the type as part of the writing system.
if (grepl("^note_.+_[^_]+$", col)) {
  note_type <- sub("^note_(.+)_[^_]+$", "\\1", col)
  lang <- sub("^note_.+_([^_]+)$", "\\1", col)
  cat(sprintf("Classifying column '%s' as typed note type='%s', lang=%s\n",
              col, note_type, lang), file = stderr())
  return(tibble(column = col, kind = "typed_note", field_type = note_type, lang = lang))
}
```

[R/sense_helpers.R](../R/sense_helpers.R) — same body, placed after the `^general_note_.+$` branch and
before the custom-field fallback. Order vs `general_note_` is free (both regexes are `^`-anchored and
the prefixes are disjoint); order vs the fallback is load-bearing, or `note_phonology_en` becomes
`<field type="note_phonology">`.

Reuse the existing `field_type` column with a new `kind = "typed_note"`. Do **not** add a fifth
`note_type` column — that costs `NA_character_` in ~12 existing branches for a name only four lines
read. Do **not** instead reuse `kind = "note"` with `field_type = NA` for untyped: the emit idiom
`cols[cols$field_type == .x, ]` yields a row of `NA`s under `NA == "x"` and would emit a garbage note.

Classification is strictly additive — only names with ≥2 underscores after a `note_` prefix change
behaviour, and no fixture, snapshot or CSV contains one. Checked: `note_en` → untyped note (one segment,
no match); `general_note_en`, `Parsing Note_en`, `scientific-name_en`,
`Plural Noun_zhi-Zxxx-x-audio`, `citation_seh`, `seh`, `gloss_pt`, `definition_en` → all unchanged;
`note_restrictions_en` / `note_semantics_pt` → typed note.

**Emit blocks.** [R/csv2lift_entry.R](../R/csv2lift_entry.R) and
[R/csv2lift_sense.R](../R/csv2lift_sense.R): add
`typed_note_cols <- filter(col_classes, kind == "typed_note")`, then the existing `field_cols` loop with
`"field"` → `"note"`, positioned **between** the untyped `<note>` block and the `<field>` block:

```r
if (nrow(typed_note_cols) > 0) {
  walk(unique(typed_note_cols$field_type), ~{
    type_cols <- typed_note_cols[typed_note_cols$field_type == .x, ]
    note_values <- set_names(as.character(row[type_cols$column]), type_cols$lang)
    if (has_nonblank(note_values)) {
      note_node <- xml_add_child(entry, "note", type = .x)   # sense_node in csv2lift_sense.R
      add_multitext_children(note_node, note_values)
    }
  })
}
```

That position is what real FLEx exports do, not just a readability choice: 6 Sena3 entries emit
`(…, note[restrictions], field[Plural])` and 12 senses emit
`(…, note[], note[phonology], note[sociolinguistics])`.

## TDD cycle

**A — red (read).** `devtools::test(filter = "entry-table_end-to-end")` and
`filter = "sense-table_end-to-end"`. All snapshots are approved, so the red is the *absence* of every
column in the table above — confirm with `head -1` on the two Sena3 snapshots.

**B — green (read).** The two `R/*_table.R` edits only. **Do not touch the classifiers here** (skill
step 3) — that is what keeps stage D's red a hard wrong-element rather than a silent drop. Verify counts
with the `csv.DictReader` recipe, then accept `entry-table_end-to-end/`,
`sense-table_end-to-end/` and `join-sense-entry-table_end-to-end/` separately (trailing slash required).
Review the join snapshot specifically for the `_sense`/`_entry` suffix pair — a new shape in an approved
artifact.

**C — write fixtures.** Three changes under `tests/testthat/fixtures/csv2lift/`:

1. **New** `note_and_phonology_notes_senses.csv` — whole-file copy of the newly accepted
   `_snaps/sense-table_end-to-end/note_and_phonology_notes.csv` (3 rows). This fixture set has no
   `_senses.csv` today, so its approved `.lift` currently has *zero* `<sense>` elements and will gain 3
   whole sense subtrees. That part of the diff is a coverage fix, not a typed-note change — land it as
   its own commit **before** stage E so the typed-note diff stays isolated.
2. **Refresh** `two_pronunciations_with_audio_and_IPA_senses.csv` from the newly accepted sense
   snapshot. Its source has untyped + phonology + source notes on one sense, so leaving it stale breaks
   the skill's invariant that the write fixture *is* the reader's output.
3. **New pair** `sena3_entry_and_sense_typed_notes_{entries,senses}.csv` — required, because no small
   fixture has an entry-level typed note. Two real rows, copied verbatim from the accepted Sena3
   snapshots:
   - entry `7ecbb299-bf35-4795-a5cc-8d38ce8b891c` (`infa`) + sense `6895e856-…` — an entry
     `note[restrictions]` **and** a sense with an untyped note alongside `note[phonology]`. Chosen for
     clean text: no embedded double quotes and no leading/trailing whitespace (see follow-up 1). Its
     sense also carries an `<example>` with `note[@type="reference"]`, which must **not** appear in the
     output — the negative check that the direct-child axis holds.
   - entry `708ff551-9116-458a-b6a9-ea8eab0beff0` + its single sense — the `note[semantics]` carrying
     both `en` and `pt` forms, proving one `<note type=X>` groups every lang rather than emitting one
     note per lang.

   Leave every other csv2lift fixture alone; their byte-identical snapshots are the regression net
   proving the writer tolerates typed-note columns being absent entirely.

**D — red (write).** `devtools::test(filter = "csv2lift_end-to-end")`. Per the skill's four-shape table:
`sena3_entry_and_sense_typed_notes` auto-creates a snapshot with a WARN containing
`<field type="note_restrictions">` / `<field type="note_phonology">` — wrong element via the
custom-field fallback, visible in the stderr classification log; `two_pronunciations_with_audio_and_IPA`
and `note_and_phonology_notes` FAIL with `.new` files showing the same wrong element.

**E — green (write).** The two classifier branches and the two emit blocks. Review each `.lift` snapshot
against its source: element is `<note type=…>` not `<field type=…>`; typed notes sit after the untyped
`<note>` and before `<field>`; the semantics note is one element with two `<form>`s; spans survive as
`<span lang>` (thanks to `plans/inline-span-markup.md`). Then `snapshot_accept("csv2lift_end-to-end/")`.

**F — refactor.** The entry and sense typed-note emit blocks are byte-identical apart from the parent
node, and near-identical to the two custom-field blocks beside them. Four such blocks is the point where
extracting a shared helper may beat the parallel-files convention. Judgement call — if kept parallel,
say why in the commit.

Pause for a commit at each of B, C, E, F.

## Documentation

- **SPEC.md §3**: new column row `note_<type>_<lang>` ← `entry/note[@type]/form`; insert the typed-note
  classification step and renumber; extend the known-limitation sentence to say the `note_` prefix now
  covers two shapes distinguished by segment count (one segment after the prefix = the untyped note's
  writing system; two or more = type plus writing system, split on the **last** underscore) and that a
  custom field whose type begins with `note_` now misclassifies; add `<note type=X>` to the
  canonical-child-order bullet and the omit-when-empty rule.
- **SPEC.md §4**: the same for the sense table, plus the naming rationale above.
- **SPEC.md §2**: the first-appearance rule fixes order *within* a multi-valued group but cannot fix the
  relative order of distinct **attribute-keyed siblings** (custom `<field type>`, typed `<note type>`):
  the CSV carries one global column order, so a parent whose elements appear in a different relative
  order than the document-wide first-appearance order is re-ordered on the way back. Content is
  preserved; only sibling order changes.
- **SPEC.md §6**: `note_<type>_<lang>` is shared across levels and does clash on real data, so
  `suffix = c("_sense", "_entry")` is now load-bearing rather than hypothetical.
- **SPEC.md §9**: delete the typed-note bullet. Add: (a) the sibling-reorder limitation with its real
  figure — 44 Sena3 senses hold `(phonology, sociolinguistics)` and re-emit as
  `(sociolinguistics, phonology)`, because column order is global-first-appearance while element order
  per parent is whatever FLEx emitted (alphabetical by type in every fixture); `<field type>` has the
  identical latent exposure and has simply never fired. Do **not** "fix" this by sorting the columns —
  that is a re-sort, flatly against §2, and only works because FLEx happens to sort. (b) `note` is
  `zeroOrMore` in `lift.rng`, so the one-per-type-per-parent assumption rests on the fixture tally, not
  the schema. (c) `sense/example/note[@type="reference"]` (744 in Sena3) and `subsense/note` remain
  unread.
- Strike through follow-up #3 in `plans/sense-level-note-and-custom-fields.md` as done, following that
  file's existing revision-note convention.
- No README change (no CLI surface change). `grep -n "§[0-9]" SPEC.md` afterwards — no section is
  inserted, so cross-references should be stable, but check.

## Verification

```bash
Rscript -e 'devtools::test(filter = "entry-table_end-to-end")'
Rscript -e 'devtools::test(filter = "sense-table_end-to-end")'
Rscript -e 'devtools::test(filter = "join-sense-entry-table")'
Rscript -e 'devtools::test(filter = "csv2lift_end-to-end")'
Rscript -e 'devtools::test()'   # full suite
```

Plus a manual round trip the suite cannot do (there is no lift→csv→lift idempotence test):
`Sena3.lift` → entry + sense CSVs → `scripts/csv2lift.R --senses` → diff a spot-checked entry's subtree
against the source, expecting exactly the documented infidelity (reordered typed-note siblings) and
nothing else.

## Follow-ups (not in this change)

1. **`trim_ws` bug** — `scripts/csv2lift.R`'s `read_csv()` leaves `trim_ws = TRUE`, and `format_csv`
   doesn't quote a value merely for trailing whitespace, so `"Do not parse: "` round-trips as
   `"Do not parse:"`. Affects 14 of 61 entry `restrictions` notes, 2 phonology and 5 untyped sense
   notes. Currently unexercised (no fixture cell has padding, and the stage-C rows were chosen to keep
   it that way). A real one-line fix, but it needs its own red and its own fixture.
2. **Example sentences** (`sense/example`) — still the highest-coverage unread field (73% of senses),
   and the gate on `example/note[@type="reference"]`.
3. **Semantic domains** — `trait[@name='semantic-domain-ddp4']`, up to 3 per sense.
