# SPEC.md — CSV ↔ LIFT Data Model

## 1. Purpose and status

Defines the tables, keys, and column-naming/XML-structure conventions shared by lift2csv (LIFT → CSV) and csv2lift (CSV → LIFT).

This spec is the source of truth. When code and this document disagree, that is a bug: fix whichever is wrong, and update this document immediately whenever a design decision changes — do not let it drift out of sync with the code.

Built incrementally as design decisions are actually made through development; it does not speculate ahead of what is implemented. See "Not Yet Specified" (§9) for what is deliberately left undesigned.

### 1.1 LIFT model references

- [lift.rng](https://github.com/sillsdev/lift-standard/blob/master/lift.rng) — the LIFT RelaxNG schema, the authoritative definition of the format. It shows how flexible the spec actually is (most elements are optional, ordering and repetition are loosely constrained).
- [Technical Notes on LIFT used in FLEx](https://downloads.languagetechnology.org/fieldworks/Documentation/Technical%20Notes%20on%20LIFT%20used%20in%20FLEx.pdf) — describes the practical subset FLEx actually produces/consumes day to day, which is what this project's fixtures and rules are modeled on.

## 2. Conventions used throughout

- **Dates**: `dateCreated`/`dateModified` are ISO 8601 UTC, format `YYYY-MM-DDTHH:MM:SSZ`, copied verbatim between LIFT and CSV — never regenerated or reformatted.
- **CSV reading/writing**: always read every column as character (`col_types = cols(.default = "c")`) and treat blank cells as `NA` (`na = ""`) on read; write with `format_csv(table, na = "")`. This avoids `readr`'s type-guessing silently corrupting round-trips (e.g. a numeric-looking custom field, or a blank cell becoming the literal string `"NA"`).
- **Column/element order**: within any multi-valued group (e.g. the `<form lang>` children of one `<field>`), order must reflect the order elements first appeared in the source LIFT document. Neither direction may re-sort (e.g. alphabetically) — this is what makes round-tripping faithful.

## 3. Entry table

Primary key: `entry_id` (= `entry/@guid`).

| Column                | LIFT source                              | Notes                                                  |
| --------------------- | ---------------------------------------- | ------------------------------------------------------ |
| `entry_id`            | `entry/@guid`                            | primary key                                            |
| `dateCreated`         | `entry/@dateCreated`                     |                                                        |
| `dateModified`        | `entry/@dateModified`                    |                                                        |
| `morph_type`          | `entry/trait[@name='morph-type']/@value` | only first value if duplicated (warns)                 |
| `<lang>` (e.g. `seh`) | `entry/lexical-unit/form`                | one column per writing system found in the source      |
| `citation_<lang>`     | `entry/citation/form`                    | reserved prefix `citation_`                            |
| `note_<lang>`         | `entry/note[not(@type)]/form`            | reserved prefix `note_`; untyped note only (see below) |
| `<field-type>_<lang>` | `entry/field[@type]/form`                | custom fields; split on the **last** underscore        |

**Column classification algorithm** (must match exactly between directions):
1. Exact match against `entry_id`, `dateCreated`, `dateModified`, `morph_type` → metadata.
2. Else matches `^citation_(.+)$` → citation, lang = capture group.
3. Else matches `^note_(.+)$` → note, lang = capture group.
4. Else contains no underscore → lexical-unit, lang = column name.
5. Else → custom field; split on the **last** underscore: field type = everything before, lang = everything after.

Known limitation (accepted, not solved generally): a writing-system code containing an underscore, or a custom field literally named `citation` or `note`, will misclassify.

`<note>` is only read/written when it has no `type` attribute. LIFT/FLEx reuses the `<note>` element for other, unrelated fields distinguished by `type` (e.g. `<note type="restrictions">` is FLEx's separate "Restrictions" field, not its generic "Note" field — confirmed against real FieldWorks-exported data, where filtering for the Note field in FLEx does not surface `restrictions`-typed notes). Typed notes are out of scope for now (see §9).

**LIFT structural rules for building an entry (csv2lift direction):**
- Only `guid` is emitted (from `entry_id`); `id` is never synthesized — FLEx treats `guid` as the true primary key and does not require `id` when `guid` is present.
- Emit `dateCreated`/`dateModified`/`guid` attributes only when non-blank.
- Canonical child element order (not schema-required — `lift.rng` wraps the entry's children in an `<interleave>` — but always emitted this way for readability): `<lexical-unit>`, `<trait name="morph-type">`, `<citation>`, `<note>`, one `<field type=X>` per distinct field type — grouping every lang for that type into one `<field>` element, never one `<field>` per lang — then `<pronunciation>` elements (§5), then `<sense>` elements (§4). Pronunciations and senses are appended by later passes over their own tables, so what fixes their position is the order `scripts/csv2lift.R` calls `attach_pronunciations_to_lift()` and `attach_senses_to_lift()`.
- Within `<lexical-unit>`, `<citation>`, `<note>`, and each `<field>`, `<form lang>` children are emitted in the CSV's own column order (§2) — never re-sorted.
- An entry with no data for a given optional element (lexical-unit/citation/note/morph_type/field) simply omits that element — no empty elements are emitted.
- Zero input rows still produce a valid `<lift version="0.13" producer="..."/>` root with no entries.

## 4. Sense table

Primary key: `sense_guid` (= `sense/@id`). Foreign key: `entry_id`.

| Column                                     | LIFT source                     | Notes                                                                                                                                                                                                                                |
| ------------------------------------------ | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `sense_guid`                               | `sense/@id`                     | primary key                                                                                                                                                                                                                          |
| `entry_id`                                 | (parent `entry/@guid`)          | foreign key → entry table                                                                                                                                                                                                            |
| `sense_order`                              | `sense/@order`                  | copied verbatim, never regenerated from row position (§2). FLEx emits it only on the senses of multi-sense entries — in `Sena3.lift`, on all 446 such senses and on none of the 1271 single-sense ones — so a blank here is normal, not missing data. Named `sense_order` rather than `order` to match `sense_guid` and to stay distinct from the entry-level `@order` attribute (§9) in the join view (§6) |
| `grammatical_info`                         | `sense/grammatical-info/@value` | LIFT permits at most one `grammatical-info` per sense (`lift.rng` wraps it in `<optional>` with no `zeroOrMore`/`oneOrMore`); confirmed by real data — no fixture, including the 1717-sense `Sena3.lift`, has ever had more than one |
| `gloss_<lang>` (e.g. `gloss_en`)           | `sense/gloss[@lang]`            | one column per writing system found in the source; `<gloss>` itself carries `lang` and a `<text>` child, unlike the `<form>`-wrapped multitext elements                                                                              |
| `definition_<lang>` (e.g. `definition_en`) | `sense/definition/form`         | one column per writing system found in the source                                                                                                                                                                                    |
| `general_note_<lang>`                       | `sense/note[not(@type)]/form`   | reserved prefix `general_note_`; untyped note only. FLEx's sense pane labels this field "General Note", distinct from the entry-level "Note" field (§3) and from the typed sense notes (Phonology Note, Grammar Note, etc.) — hence a different reserved prefix from entry-level notes rather than reusing `note_` |
| `<field-type>_<lang>`                       | `sense/field[@type]/form`       | custom fields; split on the **last** underscore, same rule as entry-level custom fields (§3)                                                                                                                                          |

**Column classification algorithm** (must match exactly between directions):
1. Exact match against `sense_guid`, `entry_id`, `sense_order`, `grammatical_info` → metadata.
2. Else matches `^gloss_(.+)$` → gloss, lang = capture group.
3. Else matches `^definition_(.+)$` → definition, lang = capture group.
4. Else matches `^general_note_(.+)$` → note, lang = capture group.
5. Else → custom field; split on the **last** underscore: field type = everything before, lang = everything after.

Known limitation (accepted, not solved generally): a writing-system code containing an underscore, or a custom field literally named `gloss`, `definition`, or `general_note`, will misclassify — the same limitation entry columns have (§3).

**csv2lift direction:** implemented by `attach_senses_to_lift(doc, sense_table)` (`R/csv2lift_sense.R`), using `classify_sense_columns()` (`R/sense_helpers.R`) to classify columns per the algorithm above. For each sense row, the entry to attach it to is found by matching `entry_id` against an existing `entry/@guid` in the document (not a separate `id` lookup — entries have no other stable key). LIFT uses `id` (not `guid`) for `<sense>`; it is emitted from `sense_guid`, omitted if blank. `order` is emitted from `sense_order` and omitted when blank *or when the column is absent entirely* — a sense CSV produced before `sense_order` existed still converts, mirroring the entry writer's `dateCreated`/`dateModified` guard (§3). Canonical child order: `<grammatical-info>`, `<gloss>` (one per non-blank `gloss_<lang>` column, added directly under `<sense>`), `<definition>`, `<note>` (from `general_note_<lang>` columns), one `<field type=X>` per distinct field type — grouping every lang for that type into one `<field>` element, never one `<field>` per lang. `<definition>`, `<note>`, and each `<field>` are only emitted when at least one of their columns is non-blank for that row — same "omit empty elements" rule as entry-level citation/note. If a sense row's `entry_id` does not match any entry already in the document, this is a hard error (fail-fast) — the sense is never silently dropped. Multiple senses per entry is supported in both directions: `sense_table()` (lift2csv) captures every `<sense>` child per entry (exercised by the real `Sena3.lift` fixture, which has entries with up to 6 senses), and `attach_senses_to_lift()` (csv2lift) attaches one `<sense>` per matching row, in CSV row order — proven by the `sena3_multiple_senses_per_entry` fixture.

## 5. Pronunciation table

One row per `<entry>/<pronunciation>`. Foreign key: `entry_id`. **No primary key** — `<pronunciation>` carries no `id` or `guid` in LIFT, unlike `<entry>` (`guid`) and `<sense>` (`id`), so the only thing identifying a pronunciation is its position. Row order is therefore load-bearing in both directions, per §2: neither direction may re-sort, and re-ordering the CSV's rows re-orders the emitted elements.

This is a table of its own rather than columns on the entry table because `lift.rng` wraps `pronunciation` in `<zeroOrMore>`, and real exports use it: `two_pronunciations_with_audio_and_IPA.lift` has one entry with two pronunciations whose forms share a single writing system (`zhi-fonipa-x-etic`: `tsēn` and `tsʼēn`). Two values, one writing system, one entry cannot be represented in one row under any column-naming scheme.

| Column                 | LIFT source                       | Notes                                                                               |
| ---------------------- | --------------------------------- | ----------------------------------------------------------------------------------- |
| `entry_id`             | (parent `entry/@guid`)            | foreign key → entry table                                                           |
| `pronunciation_<lang>` | `entry/pronunciation/form`        | reserved prefix `pronunciation_`; one column per writing system found in the source |
| `media_href`           | `entry/pronunciation/media/@href` | the audio filename; at most one per row (see below)                                 |

**Column classification algorithm** (must match exactly between directions): exact match against `entry_id`, `media_href` → metadata; else matches `^pronunciation_(.+)$` → form, lang = capture group; else → hard error. As with sense columns (§4), and unlike entry columns (§3), there is no last-underscore custom-field fallback — pronunciation-level `<field>`/`<trait>` aren't read or written at all (§9), so misclassifying one as a form would be worse than failing.

**lift2csv direction:** implemented by `pronunciation_table(LIFT_file)` (`R/pronunciation_table.R`). `lift.rng` permits zero or more `<media>` per `<pronunciation>`, but a row holds a single `media_href`; a pronunciation with more than one warns on stderr (naming the entry) and keeps the first, mirroring `extract_single_trait()`'s handling of duplicate traits. A pronunciation with no `<media>` yields a blank `media_href`, and one with no `<form>` children yields blank form columns — both occur in `note_and_phonology_notes.lift`, whose pronunciations are media-only. A lexicon with no pronunciations produces an empty CSV, as `lift2csv_sense-table.R` does for a lexicon with no senses.

**csv2lift direction:** implemented by `attach_pronunciations_to_lift(doc, pronunciation_table)` (`R/csv2lift_pronunciation.R`), using `classify_pronunciation_columns()` (`R/pronunciation_helpers.R`). As with senses, the entry to attach to is found by matching `entry_id` against an existing `entry/@guid`, and a row whose `entry_id` matches no entry is a hard error (fail-fast) — a pronunciation is never silently dropped. Within each `<pronunciation>`, `<form lang>` children are emitted in CSV column order and precede `<media href>`, mirroring the source's child order (`lift.rng` interleaves them, so this is a readability convention as in §3). A row with neither a non-blank form column nor a non-blank `media_href` emits no `<pronunciation>` at all — the same "omit empty optional elements" rule as citation/note/definition.

## 6. Join (entry ⋈ sense) view

Produced by `lift2csv_join-sense-entry-table.R`: a left join of the sense table onto the entry table by `entry_id`, one row per sense, with entry-level columns repeated across all of an entry's senses.

This is a denormalized *view*, not a base table — csv2lift does not consume this shape directly. Building a LIFT file from it would require grouping/de-duplicating the entry-level columns back out; the tool deliberately does not do this. Instead, csv2lift takes normalized per-table CSVs (§7).

Sense and entry columns can in principle share a name — both tables use the `<field-type>_<lang>` custom-field scheme, so an entry-level custom field and a sense-level custom field of the same type and writing system would collide. (Entry-level notes and sense-level notes do not collide: they use different reserved prefixes, `note_` vs `general_note_`, precisely because they are different FLEx fields — see §4.) `join_sense_entry()` (`R/join_sense_entry.R`) resolves any such collision with explicit suffixes (`left_join(..., suffix = c("_sense", "_entry"))`) rather than dplyr's default `.x`/`.y`; a column with no counterpart at the other level keeps its plain name unsuffixed.

## 7. csv2lift CLI shape

- A single script, not one script per table — a LIFT file requires all tables joined together to build one coherent tree. There is no such thing as a "senses-only" LIFT file.
- Takes one CSV per table as a separate parameter: the entry table is required; further tables (senses, etc.) are added as optional parameters as their round-trip support is implemented.
- Internally joins tables by their declared foreign key before building the tree (attaches `<sense>` and `<pronunciation>` children to the `<entry>` whose `guid` matches each row's `entry_id`).
- Currently implemented: `scripts/csv2lift.R` (renamed from `scripts/csv2lift_entry-table.R`), positional `entries_csv` (required) plus `--senses` and `--pronunciations` (both optional). The optional tables are attached pronunciations-first so the emitted child order matches §3.

## 8. Verification

All claims in this spec are checked by the approval tests under `tests/testthat/` (see `AGENTS.md`'s Testing Approach) — golden `.lift`/`.csv` files under `tests/testthat/_snaps/`, generated from fixtures under `tests/testthat/fixtures/`.

If a test's expected output and this spec disagree, that is a bug in one of them — resolve the disagreement explicitly (don't just edit whichever is more convenient) and update this spec if the resolution changes a stated rule.

## 9. Not yet specified

Deliberately undesigned until actually built, to avoid speculating ahead of development:

- Variant, etymology, relations/cross-references, and other entry sub-elements not yet read by lift2csv. This includes `<relation type="_component-lexeme">` (FLEx's "Complex Forms" field), which is stored as one `<relation ref="...">` per component entry, each with an `order` attribute and optional `is-primary`/`complex-form-type` traits.
- Within `<pronunciation>` (§5): the optional `<label>` on a `<media>` element, pronunciation-level `<field>`/`<trait>`/`<annotation>` children (FLEx's "CV Pattern" and "Tone" are `<field>`s here), the `dateCreated`/`dateModified` attributes `extensible-content` allows, and more than one `<media>` per pronunciation — the second and later ones warn and are dropped. None of these appear in any fixture.
- Typed `<note>` elements (e.g. `<note type="restrictions">` at entry level, `<note type="phonology">`/`<note type="source">`/etc. at sense level) — only the untyped note round-trips today, at both entry level (§3) and sense level (§4). Typed notes are semantically distinct FLEx fields that happen to reuse the `<note>` element; they'd need type-keyed columns analogous to custom `<field>` handling.
- Entry-level traits other than `morph-type` (e.g. `environment`, `dialect-labels`), and the entry `order`/`dateDeleted` attributes.
- Sense-level traits (e.g. `semantic-domain-ddp4`, `usage-type`), `<relation>`, `<reversal>`, and `<subsense>`. Also the sense `dateCreated`/`dateModified` attributes `extensible-content` allows — unlike `@order` (§4), these appear on no sense in any fixture, so there is nothing to build against.
- Example sentences (`sense/example`, with its own multi-lang form and nested multi-lang `<translation>`) — not read or written at all.
- Two of the 632 untyped sense notes in `Sena3.lift` wrap an inline `<span lang="...">` inside `<text>`; `xml_text()` flattens it to plain text, dropping the inner language tagging — the same lossiness entry-level notes already have.
- Any `<header>`/`<fields>` custom-field declaration handling.
- Patch-in-place / merge-into-existing-LIFT mode for csv2lift.
