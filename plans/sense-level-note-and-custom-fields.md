# Sense-level untyped `<note>` and custom `<field>`

> **Revision note (post-implementation):** the sense-level untyped note column is named
> `general_note_<lang>`, not `note_<lang>` as drafted below. FLEx's sense pane labels this field
> "General Note" (distinct from the entry-level "Note" field and from typed sense notes like
> Phonology Note), and reusing `note_<lang>` at sense level collided with the entry-level column of
> the same name once both tables fed the entry ⋈ sense join view — `join_sense_entry()`
> (`R/join_sense_entry.R`) needed an explicit `suffix = c("_sense", "_entry")` fix for that. The
> `note_<lang>` references below predate that rename; read them as `general_note_<lang>`.

## Context

The sense table (SPEC.md §4) currently carries only `sense_guid`, `entry_id`, `grammatical_info`,
`gloss_<lang>` and `definition_<lang>`. Everything else FLEx puts on a sense is dropped by lift2csv
and rejected (hard error) by csv2lift. This change adds the two highest-value sense fields that still
fit as plain columns, chosen from a census of what real FLEx exports actually contain rather than from
the schema alone.

### Evidence — sense children across the 1717 senses of `Sena3.lift`

| Sense child | Occurrences | Senses affected | Max per sense | Shape |
| --- | --- | --- | --- | --- |
| `example` | 1296 | 1251 (73%) | 5 | `zeroOrMore` → own table (+ nested `translation`) |
| `note` (untyped) | 632 | 632 (37%) | 1 (630×1 form, 2×2 forms) | `form`-wrapped multitext → **column** |
| `note[@type]` (phonology 199, sociolinguistics 126, grammar 31, source 31, semantics 18, restrictions 1) | 406 | — | 1 per type | type-keyed columns |
| `trait[semantic-domain-ddp4]` | 181 | 156 | 3 | atomic value, repeats → own table |
| `field` (Parsing Note 60, scientific-name 15) | 75 | 75 | 1 per type | `form`-wrapped multitext → **column** |
| `relation` (Synonyms 40, Antonym 4) | 44 | 41 | 2 | `@ref` to another entry/sense |
| `trait[usage-type]` | 16 | 16 | 1 | atomic value |
| `subsense` | 8 | — | — | recursive sense |
| `reversal` | 5 (other fixtures) | — | 3 | `zeroOrMore` |
| `@order` on `sense` | 446 senses | — | — | plain attribute, currently lost |

Rank by coverage per unit of work, not by raw frequency: `<example>` is the most frequent sense child
*and* the most expensive (a table plus a nested translation table). `<note>` and `<field>` are the only
high-frequency candidates that are `<optional>` in `lift.rng` and so fit as columns — together 707
senses of real data, using machinery copied almost verbatim from the entry level. They also close two
SPEC.md §9 items and remove the sense classifier's one asymmetry (no custom-field fallback).

## Read direction (lift2csv) — `R/sense_table.R`

Two additions modelled line-for-line on `entry_table()`:

1. Untyped note:
   ```r
   notes_long <- extract_sense_multitext_element(senses, "./note[not(@type)]/form")
   notes_wide <- pivot_wider(notes_long, id_cols = sense_guid, names_from = lang,
                             values_from = text, names_glue = "note_{lang}")
   ```
   The `[not(@type)]` predicate is load-bearing: `Sena3.lift` has 406 typed sense notes that would
   otherwise collide with the untyped ones in `pivot_wider` (both are `lang="en"`).

2. Custom fields: needs a sense-level analogue of `extract_multitext_with_attribute()`
   (`R/entry_helpers.R`) in `R/sense_helpers.R` — same body, keyed on `sense_guid`, iterating senses.
   Then `pivot_wider(names_from = c(type, lang), names_glue = "{type}_{lang}")`, exactly as
   `entry_table()` does. Yields `Parsing Note_en` and `scientific-name_en`.

Both `left_join`ed onto `sense_meta` after gloss/definition. Every early-return path must return the
typed empty tibble (`adding-a-lift-field` step 3).

## Write direction (csv2lift) — `R/sense_helpers.R`, `R/csv2lift_sense.R`

- `classify_sense_columns()`: add a `^note_.+$` branch, then replace the terminal `stop()` with the
  last-underscore custom-field fallback from `classify_entry_columns()` (returning `field_type`).
  All existing return values gain a `field_type = NA_character_` column so the `map_df` binds.
  Order matters: `note_` before the fallback, or `note_en` becomes a field of type `note`.
- `attach_senses_to_lift()`: after the definition block, emit `<note>` (wrapping element, only when
  `has_nonblank()`) then one `<field type=X>` per distinct field type — a direct copy of
  `R/csv2lift_entry.R:64-71`. Child order: `grammatical-info`, `gloss`, `definition`, `note`, `field`.

## Fixtures and TDD cycle

No new `.lift` fixture is needed — `Sena3.lift` and `Sena3_gloss_initial_b.lift` (21 notes, 2 Parsing
Note, 2 scientific-name across 56 senses) already carry both fields in the sense-table fixture dir.
`two_pronunciations_with_audio_and_IPA.lift` is also already there and is worth checking specifically:
its second sense has a real untyped `<note>` ("Blench083-") sitting alongside `<note type="phonology">`
and `<note type="source">` on the *same* sense — the sharpest available check that the `[not(@type)]`
predicate actually excludes typed notes rather than merely never colliding by accident in Sena3. It has
no sense-level custom `<field>`, only an entry-level one ("Plural Noun"), so it doesn't cover that half.

It is missing from `fixtures/lift2csv_join-sense-entry-table/` (checked: not there today), unlike
`Sena3.lift` and the other three fixtures already copied there. Since an untyped sense note does reach
the entry ⋈ sense join view, copy it in as part of this change for join coverage — the skill's rule for
when a fixture belongs in that directory.

1. **Red (read):** `devtools::test(filter = "sense-table_end-to-end")` — confirm the current approved
   snapshots have no `note_*` / custom-field columns. That absence is the red.
2. **Green (read):** the two extractions above. Review the `.new` snapshots by counting non-blank
   cells against the tallies above (632 `note_en`, 2 `note_pt`, 60 `Parsing Note_en`,
   15 `scientific-name_en` for Sena3), plus the single expected `note_en` for
   `two_pronunciations_with_audio_and_IPA.lift`'s second sense with `note_phonology_en`/
   `note_source_en` NOT appearing (those stay unread — typed notes remain §9 scope), then
   `snapshot_accept("sense-table_end-to-end/")`. Copy the fixture into
   `fixtures/lift2csv_join-sense-entry-table/` and `snapshot_accept("join-sense-entry-table_end-to-end/")`
   (trailing slashes required).
3. **Red (write):** build a new csv2lift fixture pair from the accepted reader output — a real Sena3
   sense row with a non-blank `note_en` *and* a non-blank custom field, plus its matching entry row,
   into `tests/testthat/fixtures/csv2lift/sena3_sense_note_and_field_{senses,entries}.csv`. Values
   copied verbatim from reader output, never invented. Red here is a hard error from
   `classify_sense_columns()` ("Unrecognized sense column 'note_en'"), not a wrong element.
4. **Green (write):** the classifier + emit changes; review the `.lift` snapshot, then
   `snapshot_accept("csv2lift_end-to-end/")`.
5. **Refactor:** the sense- and entry-level `extract_multitext_with_attribute()` bodies differ only in
   the key column — fold into one helper parameterised by key name if it reads cleanly; otherwise keep
   the parallel-files convention the skill documents and say why.

Pause at each red/green/refactor boundary so the history reads as distinct TDD stages.

## Documentation

- **SPEC.md §4**: two new rows in the column table; insert the `^note_(.+)$` step into the
  classification algorithm and replace "else → hard error" with the last-underscore fallback plus the
  same known-limitation sentence §3 carries (reserved sense prefixes now `gloss_`, `definition_`,
  `note_`); update the csv2lift paragraph's child order.
- **SPEC.md §9**: delete the "Sense-level custom `<field>` elements" bullet; narrow the typed-note
  bullet to say untyped notes now round-trip at *both* entry and sense level.
- Record the one accepted lossiness in §9: 2 of 632 untyped sense notes wrap a `<span lang="seh">`
  inside `<text>`; `xml_text()` flattens it, so inline markup is dropped (same as entry level today).

## Verification

```bash
Rscript -e 'devtools::test(filter = "sense-table_end-to-end")'
Rscript -e 'devtools::test(filter = "join-sense-entry-table")'
Rscript -e 'devtools::test(filter = "csv2lift_end-to-end")'
Rscript -e 'devtools::test()'   # full suite
```

Plus a manual round-trip on the real export: `Sena3.lift` → sense CSV → back through
`scripts/csv2lift.R --senses`, and diff the sense subtree of a spot-checked entry against the source.

## Follow-ups (not in this change)

1. **Example sentences** — highest coverage (73% of senses) and the most-requested lexicography field,
   but the largest job: `<example>` has no id (positional key, FK `sense_guid`), carries `@source`
   (744 in Sena3), a `<note type="reference">`, and `zeroOrMore` `<translation type>` each with its
   own multi-lang forms (types seen: Free/Literal/Back translation) — a second table one level deeper,
   attached after `attach_senses_to_lift()`. 407 of 1296 Sena3 examples are `@source`-only with no
   form, so the omit-when-empty rules need care.
2. **Semantic domains** — `trait[@name='semantic-domain-ddp4']`, up to 3 per sense, atomic values:
   a thin `sense_guid, semantic_domain` table (indexed columns are ruled out by the skill).
3. **Typed sense notes** — `note_<type>_<lang>` columns; design shared with entry-level typed notes.
4. ~~**Cheap extra**: `sense/@order` (present on 446 Sena3 senses) is silently lost today — a single
   metadata column would fix it.~~ **Done** — implemented as the `sense_order` metadata column
   (SPEC.md §4). Named `sense_order`, not `order`, to match `sense_guid` and to avoid a future clash
   with the entry-level `@order` attribute in the join view. Copied verbatim, never regenerated from
   row position; the writer omits the attribute when the column is blank *or absent*, so sense CSVs
   produced before the column existed still convert.
