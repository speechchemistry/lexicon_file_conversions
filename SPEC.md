# SPEC.md — CSV ↔ LIFT Data Model

## 1. Purpose and status

Defines the tables, keys, and column-naming/XML-structure conventions shared by lift2csv (LIFT → CSV) and csv2lift (CSV → LIFT).

This spec is the source of truth. When code and this document disagree, that is a bug: fix whichever is wrong, and update this document immediately whenever a design decision changes — do not let it drift out of sync with the code.

Built incrementally as design decisions are actually made through development; it does not speculate ahead of what is implemented. See "Not Yet Specified" (§8) for what is deliberately left undesigned.

### 1.1 LIFT model references

- [lift.rng](https://github.com/sillsdev/lift-standard/blob/master/lift.rng) — the LIFT RelaxNG schema, the authoritative definition of the format. It shows how flexible the spec actually is (most elements are optional, ordering and repetition are loosely constrained).
- [Technical Notes on LIFT used in FLEx](https://downloads.languagetechnology.org/fieldworks/Documentation/Technical%20Notes%20on%20LIFT%20used%20in%20FLEx.pdf) — describes the practical subset FLEx actually produces/consumes day to day, which is what this project's fixtures and rules are modeled on.

## 2. Conventions used throughout

- **Dates**: `dateCreated`/`dateModified` are ISO 8601 UTC, format `YYYY-MM-DDTHH:MM:SSZ`, copied verbatim between LIFT and CSV — never regenerated or reformatted.
- **CSV reading/writing**: always read every column as character (`col_types = cols(.default = "c")`) and treat blank cells as `NA` (`na = ""`) on read; write with `format_csv(table, na = "")`. This avoids `readr`'s type-guessing silently corrupting round-trips (e.g. a numeric-looking custom field, or a blank cell becoming the literal string `"NA"`).
- **Column/element order**: within any multi-valued group (e.g. the `<form lang>` children of one `<field>`), order must reflect the order elements first appeared in the source LIFT document. Neither direction may re-sort (e.g. alphabetically) — this is what makes round-tripping faithful.

## 3. Entry table

Primary key: `entry_id` (= `entry/@guid`).

| Column | LIFT source | Notes |
|---|---|---|
| `entry_id` | `entry/@guid` | primary key |
| `dateCreated` | `entry/@dateCreated` | |
| `dateModified` | `entry/@dateModified` | |
| `morph_type` | `entry/trait[@name='morph-type']/@value` | only first value if duplicated (warns) |
| `<lang>` (e.g. `seh`) | `entry/lexical-unit/form` | one column per writing system found in the source |
| `citation_<lang>` | `entry/citation/form` | reserved prefix `citation_` |
| `<field-type>_<lang>` | `entry/field[@type]/form` | custom fields; split on the **last** underscore |

**Column classification algorithm** (must match exactly between directions):
1. Exact match against `entry_id`, `dateCreated`, `dateModified`, `morph_type` → metadata.
2. Else matches `^citation_(.+)$` → citation, lang = capture group.
3. Else contains no underscore → lexical-unit, lang = column name.
4. Else → custom field; split on the **last** underscore: field type = everything before, lang = everything after.

Known limitation (accepted, not solved generally): a writing-system code containing an underscore, or a custom field literally named `citation`, will misclassify.

**LIFT structural rules for building an entry (csv2lift direction):**
- Only `guid` is emitted (from `entry_id`); `id` is never synthesized — FLEx treats `guid` as the true primary key and does not require `id` when `guid` is present.
- Emit `dateCreated`/`dateModified`/`guid` attributes only when non-blank.
- Canonical child element order (not schema-required, but always emitted this way for readability): `<lexical-unit>`, `<trait name="morph-type">`, `<citation>`, then one `<field type=X>` per distinct field type — grouping every lang for that type into one `<field>` element, never one `<field>` per lang.
- Within `<lexical-unit>`, `<citation>`, and each `<field>`, `<form lang>` children are emitted in the CSV's own column order (§2) — never re-sorted.
- An entry with no data for a given optional element (lexical-unit/citation/morph_type/field) simply omits that element — no empty elements are emitted.
- Zero input rows still produce a valid `<lift version="0.13" producer="..."/>` root with no entries.

## 4. Sense table

Primary key: `sense_guid` (= `sense/@id`). Foreign key: `entry_id`.

| Column | LIFT source | Notes |
|---|---|---|
| `sense_guid` | `sense/@id` | primary key |
| `entry_id` | (parent `entry/@guid`) | foreign key → entry table |
| `grammatical_info` | `sense/grammatical-info/@value` | only the first match per sense is used |
| `gloss_en` | `sense/gloss[@lang='en']` | English only |

Known limitations (lift2csv direction, pre-existing): only the first `grammatical-info` per sense is captured; only the English gloss is captured; other gloss languages, definitions, and multiple grammatical-info values are dropped.

**csv2lift direction:** implemented by `attach_senses_to_lift(doc, sense_table)` (`R/csv2lift_sense.R`). For each sense row, the entry to attach it to is found by matching `entry_id` against an existing `entry/@guid` in the document (not a separate `id` lookup — entries have no other stable key). LIFT uses `id` (not `guid`) for `<sense>`; it is emitted from `sense_guid`, omitted if blank. `<grammatical-info value=...>` and `<gloss lang="en"><text>...</text></gloss>` are each added only when their source column is non-blank. If a sense row's `entry_id` does not match any entry already in the document, this is a hard error (fail-fast) — the sense is never silently dropped. Multiple senses per entry works by construction but is not yet exercised by a dedicated fixture.

## 5. Join (entry ⋈ sense) view

Produced by `lift2csv_join-sense-entry-table.R`: a left join of the sense table onto the entry table by `entry_id`, one row per sense, with entry-level columns repeated across all of an entry's senses.

This is a denormalized *view*, not a base table — csv2lift does not consume this shape directly. Building a LIFT file from it would require grouping/de-duplicating the entry-level columns back out; the tool deliberately does not do this. Instead, csv2lift takes normalized per-table CSVs (§6).

## 6. csv2lift CLI shape

- A single script, not one script per table — a LIFT file requires all tables joined together to build one coherent tree. There is no such thing as a "senses-only" LIFT file.
- Takes one CSV per table as a separate parameter: the entry table is required; further tables (senses, etc.) are added as optional parameters as their round-trip support is implemented.
- Internally joins tables by their declared foreign key before building the tree (attaches `<sense>` children to the `<entry>` whose `guid` matches each sense row's `entry_id`).
- Currently implemented: `scripts/csv2lift.R` (renamed from `scripts/csv2lift_entry-table.R`), positional `entries_csv` (required) plus `--senses` (optional).

## 7. Verification

All claims in this spec are checked by the approval tests under `tests/testthat/` (see `AGENTS.md`'s Testing Approach) — golden `.lift`/`.csv` files under `tests/testthat/_snaps/`, generated from fixtures under `tests/testthat/fixtures/`.

If a test's expected output and this spec disagree, that is a bug in one of them — resolve the disagreement explicitly (don't just edit whichever is more convenient) and update this spec if the resolution changes a stated rule.

## 8. Not yet specified

Deliberately undesigned until actually built, to avoid speculating ahead of development:

- Pronunciation, variant, etymology, and other entry sub-elements not yet read by lift2csv.
- Multi-lang gloss / multiple grammatical-info per sense.
- Multiple senses per entry: works by construction in `attach_senses_to_lift()`, but not yet exercised by a dedicated fixture.
- Any `<header>`/`<fields>` custom-field declaration handling.
- Patch-in-place / merge-into-existing-LIFT mode for csv2lift.
