# SPEC.md — CSV ↔ LIFT Data Model

## 1. Purpose and status

Defines the tables, keys, and column-naming/XML-structure conventions shared by lift2csv (LIFT → CSV) and csv2lift (CSV → LIFT).

This spec is the source of truth. When code and this document disagree, that is a bug: fix whichever is wrong, and update this document immediately whenever a design decision changes — do not let it drift out of sync with the code.

Built incrementally as design decisions are actually made through development; it does not speculate ahead of what is implemented. See "Not Yet Specified" (§9) for what is deliberately left undesigned.

### 1.1 LIFT model references

- [lift.rng](https://github.com/sillsdev/lift-standard/blob/master/lift.rng) — the LIFT RelaxNG schema, the authoritative definition of the format. It shows how flexible the spec actually is (most elements are optional, ordering and repetition are loosely constrained).
- [Technical Notes on LIFT used in FLEx](https://downloads.languagetechnology.org/fieldworks/Documentation/Technical%20Notes%20on%20LIFT%20used%20in%20FLEx.pdf) — describes the practical subset FLEx actually produces/consumes day to day, which is what this project's fixtures and rules are modeled on.

## 2. Conventions used throughout

Each table section (§3–§5) states only its own column names and any deviation from these shared rules.

### 2.1 Data handling

- **Dates**: `dateCreated`/`dateModified` are ISO 8601 UTC, format `YYYY-MM-DDTHH:MM:SSZ`, copied verbatim between LIFT and CSV — never regenerated or reformatted.
- **CSV reading/writing**: always read every column as character (`col_types = cols(.default = "c")`) and treat blank cells as `NA` (`na = ""`) on read; write with `format_csv(table, na = "")`. This avoids `readr`'s type-guessing silently corrupting round-trips (e.g. a numeric-looking custom field, or a blank cell becoming the literal string `"NA"`).
- **Column/element order**: within any multi-valued group (e.g. the `<form lang>` children of one `<field>`), order must reflect the order elements first appeared in the source LIFT document. Neither direction may re-sort (e.g. alphabetically) — this is what makes round-tripping faithful.
- **Writing system comes from the data, not from the field's declaration**: a column is created for whatever `lang` each `<form>`/`<gloss>` actually carries. Neither direction consults or enforces the writing system a field is *declared* with in FLEx, so a value whose `lang` disagrees with that declaration gets its own column and round-trips unchanged rather than being normalised or flagged. Real example: in `Sena3.lift` the entry-level custom field `Plural` is declared "First Vernacular Writing System" and 518 of its 520 values are `lang="seh"`, but 2 are `lang="en"` — FLEx shows those in the same grid column, so they are easy to miss there. Those two entries get a blank `Plural_seh` and a filled `Plural_en`, and convert back to `<field type="Plural"><form lang="en">` exactly as they were. This is deliberate: the tool preserves what the export holds, and splitting by actual `lang` makes such anomalies *more* visible than the source application does. Correcting one is then a CSV edit (move the value to the `Plural_seh` cell) rather than a tool change. An entry carrying both writing systems for one field is representable too — it fills both columns and is written back as a single `<field>` with two `<form>` children in column order (§3) — though no fixture has one.
- **Inline `<span lang>` inside a multitext `<text>`**: LIFT allows a `<text>` to tag a stretch of its value as a different writing system with an inline `<span lang="...">` — typically an alternate-orthography form quoted inside an English note. This is carried in the CSV cell as the literal `<span lang="…">…</span>` tag, in both directions, with the text around it left exactly as it is and the span's `lang` as the only attribute represented. The two directions are asymmetric: on write, the literal text around a span is XML-escaped but the span tags themselves are not (`multitext_value()`/`set_multitext_text()`, `R/entry_helpers.R`). Escaping the whole value would turn spans back into text; escaping none of it produces invalid XML on the first bare `&`, which real note text has.
- **Column/element order across distinct attribute-keyed siblings**: the first-appearance rule above fixes order *within* one multi-valued group (e.g. the `<form lang>` children of one `<field>`), but not the relative order of distinct **attribute-keyed siblings** — custom `<field type>`s, and typed `<note type>`s (§3, §4) — of the same parent. The CSV carries one global column order (first appearance across the whole document), while each parent's own element order is whatever the source LIFT happened to emit; when those disagree for a given parent, csv2lift re-orders that parent's siblings to match the global column order on the way back. Content is preserved; only sibling order changes (see §9 for the real figure).

### 2.2 Column classification

- **Classification is by column name alone, and must match exactly between the two directions** — lift2csv's column naming and csv2lift's column parsing are the same rule read in opposite directions. Every table applies the same shape, in this order: fixed metadata names matched exactly; then reserved prefixes (`citation_`, `gloss_`, `definition_`, `general_note_`, `pronunciation_`, `note_`); then, on the entry and sense tables, a fallback treating any remaining column as a custom `<field>`. The pronunciation table has no fallback and hard-errors instead (§5).
- **Last-underscore splitting**: the custom-field fallback splits a column on its **last** underscore — field type is everything before, writing system everything after. Typed notes (`note_<type>_<lang>`) use the same split on the remainder after `note_`. A typed note's step must therefore precede the custom-field fallback, or `note_phonology_en` would be read as `<field type="note_phonology">`.
- **Known limitation of name-based classification** (accepted, not solved generally): a writing-system code containing an underscore will misclassify; so will a custom field named exactly like one of the reserved prefixes without its trailing underscore (`citation`, `note`, `gloss`, `definition`, `general_note`), or one whose type itself begins with `note_` (e.g. a field named `note_foo`), since typed notes share that prefix's namespace.
- **Typed notes are named `note_<type>_<lang>` at every level**, deliberately sharing one column name across the entry (§3) and sense (§4) tables rather than taking a per-level prefix (as untyped notes do, `note_` vs `general_note_`) or a FLEx-label-derived name. Two reasons:
  - The type vocabulary is open user data — a label-derived name like `phonology_note_en` can't be told apart from a custom field without hardcoding a closed list of known types.
  - Unlike untyped notes — where FLEx genuinely labels the entry and sense fields differently ("Note" vs "General Note") — a given type's FLEx label is the *same* at both levels (entry "Restrictions" and sense "Restrictions" are both just "Restrictions"). An artificial per-level prefix would mark a distinction FLEx does not make.

  The consequence is that one typed-note column name can occur on both tables; §6 covers how the join view resolves that.

### 2.3 Structural rules (csv2lift direction)

- **Canonical child element order is a readability convention, not a schema requirement**: `lift.rng` wraps element children in `<interleave>`, so nothing in LIFT fixes their order. Each table section states the order this tool always emits.
- **Empty optional elements are never emitted**: an element is written only when at least one of its columns is non-blank for that row. This covers entry-level lexical-unit/citation/note/typed note/morph_type/field (§3), sense-level definition/note/typed note/field (§4), and a whole `<pronunciation>` whose row has neither a form nor a `media_href` (§5).
- **Foreign keys fail fast**: sense and pronunciation rows are attached to the entry whose existing `entry/@guid` matches their `entry_id` (entries have no other stable key). A row matching no entry is a hard error — the sense or pronunciation is never silently dropped.

## 3. Entry table

Primary key: `entry_id` (= `entry/@guid`).

| Column                                             | LIFT source                              | Notes                                                                                   |
| -------------------------------------------------- | ---------------------------------------- | --------------------------------------------------------------------------------------- |
| `entry_id`                                         | `entry/@guid`                            | primary key                                                                             |
| `dateCreated`                                      | `entry/@dateCreated`                     |                                                                                         |
| `dateModified`                                     | `entry/@dateModified`                    |                                                                                         |
| `morph_type`                                       | `entry/trait[@name='morph-type']/@value` | only first value if duplicated (warns)                                                  |
| `<lang>` (e.g. `seh`)                              | `entry/lexical-unit/form`                | one column per writing system found in the source                                       |
| `citation_<lang>`                                  | `entry/citation/form`                    | reserved prefix `citation_`                                                             |
| `note_<lang>`                                      | `entry/note[not(@type)]/form`            | reserved prefix `note_`; untyped note only (see below)                                  |
| `note_<type>_<lang>` (e.g. `note_restrictions_en`) | `entry/note[@type]/form`                 | typed notes (§2.2); `restrictions` is the only entry-level type in `Sena3.lift`, with 61 |
| `<field-type>_<lang>`                              | `entry/field[@type]/form`                | custom fields                                                                           |

**Column classification algorithm** (§2.2):
1. Exact match against `entry_id`, `dateCreated`, `dateModified`, `morph_type` → metadata.
2. Else matches `^citation_(.+)$` → citation, lang = capture group.
3. Else matches `^note_.+_[^_]+$` (i.e. at least two underscores after the `note_` prefix) → typed note. Must precede step 4, or a typed note's type would be read as part of the writing system — entry-level untyped and typed notes share the `note_` prefix, so their order is load-bearing in a way the sense table's is not (§4).
4. Else matches `^note_(.+)$` → note (untyped), lang = capture group.
5. Else contains no underscore → lexical-unit, lang = column name.
6. Else → custom field.

`<note>` is read/written untyped (`[not(@type)]`) into `note_<lang>` and typed (`[@type]`) into `note_<type>_<lang>`, mirroring custom `<field>` handling. LIFT/FLEx reuses the `<note>` element for other, unrelated fields distinguished by `type` (e.g. `<note type="restrictions">` is FLEx's separate "Restrictions" field, not its generic "Note" field — confirmed against real FieldWorks-exported data, where filtering for the Note field in FLEx does not surface `restrictions`-typed notes).

**csv2lift direction:**
- Only `guid` is emitted (from `entry_id`); `id` is never synthesized — FLEx treats `guid` as the true primary key and does not require `id` when `guid` is present.
- Emit `dateCreated`/`dateModified`/`guid` attributes only when non-blank.
- Canonical child element order (§2.3): `<lexical-unit>`, `<trait name="morph-type">`, `<citation>`, `<note>`, one `<note type=X>` per distinct note type, one `<field type=X>` per distinct field type — grouping every lang for that type into one `<note>`/`<field>` element, never one per lang — then `<pronunciation>` elements (§5), then `<sense>` elements (§4). Pronunciations and senses are appended by later passes over their own tables, so what fixes their position is the order `scripts/csv2lift.R` calls `attach_pronunciations_to_lift()` and `attach_senses_to_lift()`.
- Within `<lexical-unit>`, `<citation>`, `<note>`, and each typed `<note>`/`<field>`, `<form lang>` children are emitted in the CSV's own column order (§2.1) — never re-sorted.
- Zero input rows still produce a valid `<lift version="0.13" producer="..."/>` root with no entries.

## 4. Sense table

Primary key: `sense_guid` (= `sense/@id`). Foreign key: `entry_id`.

| Column                                                                   | LIFT source                     | Notes                                                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------------------------------------------------------------ | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sense_guid`                                                             | `sense/@id`                     | primary key                                                                                                                                                                                                                                                                                                                                                                                               |
| `entry_id`                                                               | (parent `entry/@guid`)          | foreign key → entry table                                                                                                                                                                                                                                                                                                                                                                                 |
| `sense_order`                                                            | `sense/@order`                  | copied verbatim, never regenerated from row position (§2.1). FLEx emits it only on the senses of multi-sense entries — in `Sena3.lift`, on all 446 such senses and on none of the 1271 single-sense ones — so a blank here is normal, not missing data. Named `sense_order` rather than `order` to match `sense_guid` and to stay distinct from the entry-level `@order` attribute (§9) in the join view (§6) |
| `grammatical_info`                                                       | `sense/grammatical-info/@value` | LIFT permits at most one `grammatical-info` per sense (`lift.rng` wraps it in `<optional>` with no `zeroOrMore`/`oneOrMore`); confirmed by real data — no fixture, including the 1717-sense `Sena3.lift`, has ever had more than one                                                                                                                                                                        |
| `gloss_<lang>` (e.g. `gloss_en`)                                         | `sense/gloss[@lang]`            | one column per writing system found in the source; `<gloss>` itself carries `lang` and a `<text>` child, unlike the `<form>`-wrapped multitext elements                                                                                                                                                                                                                                                    |
| `definition_<lang>` (e.g. `definition_en`)                               | `sense/definition/form`         | one column per writing system found in the source                                                                                                                                                                                                                                                                                                                                                         |
| `general_note_<lang>`                                                    | `sense/note[not(@type)]/form`   | reserved prefix `general_note_`; untyped note only. FLEx's sense pane labels this field "General Note", distinct from the entry-level "Note" field (§3) and from the typed sense notes (Phonology Note, Grammar Note, etc.) — hence a different reserved prefix from entry-level notes rather than reusing `note_`                                                                                           |
| `note_<type>_<lang>` (e.g. `note_phonology_en`, FLEx's "Phonology Note") | `sense/note[@type]/form`        | typed notes (§2.2). `Sena3.lift`'s sense-level types are `phonology` (199), `sociolinguistics` (126), `grammar` (31), `source` (31), `semantics` (18), `restrictions` (1)                                                                                                                                                                                                                                   |
| `<field-type>_<lang>`                                                    | `sense/field[@type]/form`       | custom fields                                                                                                                                                                                                                                                                                                                                                                                             |

**Column classification algorithm** (§2.2):
1. Exact match against `sense_guid`, `entry_id`, `sense_order`, `grammatical_info` → metadata.
2. Else matches `^gloss_(.+)$` → gloss, lang = capture group.
3. Else matches `^definition_(.+)$` → definition, lang = capture group.
4. Else matches `^general_note_(.+)$` → note, lang = capture group.
5. Else matches `^note_.+_[^_]+$` (i.e. at least two underscores after the `note_` prefix) → typed note. Order vs step 4 is free (the two prefixes are disjoint, unlike at entry level — §3); order vs step 6 is load-bearing (§2.2).
6. Else → custom field.

**lift2csv direction:** `sense_table()` captures every `<sense>` child per entry — exercised by the real `Sena3.lift` fixture, which has entries with up to 6 senses.

**csv2lift direction:** implemented by `attach_senses_to_lift(doc, sense_table)` (`R/csv2lift_sense.R`), using `classify_sense_columns()` (`R/sense_helpers.R`) to classify columns per the algorithm above. LIFT uses `id` (not `guid`) for `<sense>`; it is emitted from `sense_guid`, omitted if blank. `order` is emitted from `sense_order` and omitted when blank *or when the column is absent entirely* — a sense CSV produced before `sense_order` existed still converts, mirroring the entry writer's `dateCreated`/`dateModified` guard (§3). Canonical child order (§2.3): `<grammatical-info>`, `<gloss>` (one per non-blank `gloss_<lang>` column, added directly under `<sense>`), `<definition>`, `<note>` (from `general_note_<lang>` columns), one `<note type=X>` per distinct note type, one `<field type=X>` per distinct field type — grouping every lang for that type into one `<note>`/`<field>` element, never one per lang. One `<sense>` is attached per matching row, in CSV row order — proven by the `sena3_multiple_senses_per_entry` fixture.

## 5. Pronunciation table

One row per `<entry>/<pronunciation>`. Foreign key: `entry_id`. **No primary key** — `<pronunciation>` carries no `id` or `guid` in LIFT, unlike `<entry>` (`guid`) and `<sense>` (`id`), so the only thing identifying a pronunciation is its position. Row order is therefore load-bearing in both directions, per §2.1: neither direction may re-sort, and re-ordering the CSV's rows re-orders the emitted elements.

| Column                 | LIFT source                       | Notes                                                                               |
| ---------------------- | --------------------------------- | ----------------------------------------------------------------------------------- |
| `entry_id`             | (parent `entry/@guid`)            | foreign key → entry table                                                           |
| `pronunciation_<lang>` | `entry/pronunciation/form`        | reserved prefix `pronunciation_`; one column per writing system found in the source |
| `media_href`           | `entry/pronunciation/media/@href` | the audio filename; at most one per row (see below)                                 |

**Column classification algorithm** (§2.2): exact match against `entry_id`, `media_href` → metadata; else matches `^pronunciation_(.+)$` → form, lang = capture group; else → hard error. Unlike both entry (§3) and sense (§4) columns, there is no last-underscore custom-field fallback — pronunciation-level `<field>`/`<trait>` aren't read or written at all (§9), so misclassifying one as a form would be worse than failing.

**lift2csv direction:** implemented by `pronunciation_table(LIFT_file)` (`R/pronunciation_table.R`). `lift.rng` permits zero or more `<media>` per `<pronunciation>`, but a row holds a single `media_href`; a pronunciation with more than one warns on stderr (naming the entry) and keeps the first, mirroring `extract_single_trait()`'s handling of duplicate traits. A pronunciation with no `<media>` yields a blank `media_href`, and one with no `<form>` children yields blank form columns — both occur in `note_and_phonology_notes.lift`, whose pronunciations are media-only. A lexicon with no pronunciations produces an empty CSV, as `lift2csv_sense-table.R` does for a lexicon with no senses.

**csv2lift direction:** implemented by `attach_pronunciations_to_lift(doc, pronunciation_table)` (`R/csv2lift_pronunciation.R`), using `classify_pronunciation_columns()` (`R/pronunciation_helpers.R`). Canonical child order (§2.3): within each `<pronunciation>`, `<form lang>` children are emitted in CSV column order and precede `<media href>`, mirroring the source's child order.

**Why a table of its own** rather than columns on the entry table: `lift.rng` wraps `pronunciation` in `<zeroOrMore>`, and real exports use it. `two_pronunciations_with_audio_and_IPA.lift` has one entry with two pronunciations whose forms share a single writing system (`zhi-fonipa-x-etic`: `tsēn` and `tsʼēn`). Two values, one writing system, one entry cannot be represented in one row under any column-naming scheme.

## 6. Join (entry ⋈ sense) view

Produced by `lift2csv_join-sense-entry-table.R`: a left join of the sense table onto the entry table by `entry_id`, one row per sense, with entry-level columns repeated across all of an entry's senses.

This is a denormalized *view*, not a base table — csv2lift does not consume this shape directly. Building a LIFT file from it would require grouping/de-duplicating the entry-level columns back out; the tool deliberately does not do this. Instead, csv2lift takes normalized per-table CSVs (§7).

Sense and entry columns can in principle share a name — both tables use the `<field-type>_<lang>` custom-field scheme, so an entry-level custom field and a sense-level custom field of the same type and writing system would collide. (Entry-level *untyped* notes and sense-level *untyped* notes do not collide: they use different reserved prefixes, `note_` vs `general_note_`, precisely because they are different FLEx fields — see §4.) `join_sense_entry()` (`R/join_sense_entry.R`) resolves any such collision with explicit suffixes (`left_join(..., suffix = c("_sense", "_entry"))`) rather than dplyr's default `.x`/`.y`; a column with no counterpart at the other level keeps its plain name unsuffixed.

Typed notes are the opposite case: `note_<type>_<lang>` is *deliberately* shared across levels (§2.2), and does clash on real data — `Sena3.lift` has 61 entry-level and 1 sense-level `restrictions` note, so its join snapshot contains `note_restrictions_en_sense` and `note_restrictions_en_entry`. This is not a bug to "fix" by giving typed notes a per-level prefix; the `_sense`/`_entry` suffixing above is exactly the mechanism for two identically-named fields at different levels, and this is the first real data to exercise it.

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
- **Sibling re-order on distinct attribute-keyed elements** (§2.1): the global first-appearance column order can disagree with a given parent's own element order for custom `<field type>`s and typed `<note type>`s, and csv2lift re-orders to match the column order on round-trip. Real figure: 47 senses in `Sena3.lift` hold `<note type="phonology">` before `<note type="sociolinguistics">` locally, but the CSV's global column order (established by whichever type's `(type, lang)` pair first appeared anywhere in the document) puts `note_sociolinguistics_en` first, so all 47 re-emit as `(sociolinguistics, phonology)`. `<field type>` has the identical latent exposure — the CSV column-naming scheme is the same — it has simply never fired on any fixture's field data. Do **not** "fix" this by sorting columns; that would violate the first-appearance rule (§2.1) and only works here because FLEx happens to sort its own typed-note siblings alphabetically.
- **`<note>` cardinality per type is a fixture fact, not a schema guarantee**: `lift.rng` wraps `note` in `zeroOrMore`, so LIFT permits more than one `<note>` of the same `type` on one parent. Every fixture has at most one per type per parent (both entry- and sense-level), which is what permits the flat `note_<type>_<lang>` column (§3, §4); a source with two same-typed notes on one parent is unhandled.
- `sense/example/note[@type="reference"]` (744 occurrences in `Sena3.lift`) and `sense/subsense/note` remain unread — both are excluded by the typed-note extractors' direct-child `./note` axis, gated on example-sentence support (see the "Example sentences" and `<subsense>` bullets below) rather than being a typed-note gap.
- Entry-level traits other than `morph-type` (e.g. `environment`, `dialect-labels`), and the entry `order`/`dateDeleted` attributes.
- Sense-level traits (e.g. `semantic-domain-ddp4`, `usage-type`), `<relation>`, `<reversal>`, and `<subsense>`. Also the sense `dateCreated`/`dateModified` attributes `extensible-content` allows — unlike `@order` (§4), these appear on no sense in any fixture, so there is nothing to build against.
- Example sentences (`sense/example`, with its own multi-lang form and nested multi-lang `<translation>`) — not read or written at all.
- Inline `<span lang>` markup (§2.1) is preserved except for: a span attribute other than `lang` (dropped), a nested span (would not round-trip), and ordinary text that itself contains a literal `<span lang="…">…</span>` string (turned into real markup on the way back). None of these occur in any fixture.
- Any `<header>`/`<fields>` custom-field declaration handling.
- Patch-in-place / merge-into-existing-LIFT mode for csv2lift.
