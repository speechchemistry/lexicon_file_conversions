# Plan: de-duplicate the per-table code and speed up both directions

## Context

Every table was added by copying its nearest neighbour (the [`adding-a-lift-field` skill](../.claude/skills/adding-a-lift-field/SKILL.md) effectively prescribes it), so the code now carries several families of near-identical functions that differ only in a key column name, plus per-row whole-document XPath searches on the write side. The design itself — [`R/table_registry.R`](../R/table_registry.R), thin CLI scripts, `SPEC.md` as the contract, per-table approval tests — is sound and is **not** being changed.

Baseline, measured on `tests/testthat/fixtures/lift2csv_entry-table/sena3.lift` (1462 entries / 1725 sense rows), calling each registry `read_fn` / `attach_fn` directly:

| Table          | read (s) | attach (s) |
| -------------- | -------- | ---------- |
| entries        | 11.1     | 1.8        |
| senses         | 25.9     | 7.2        |
| traits         | 11.6     | 7.1        |
| examples       | 3.8      | 12.4       |
| everything else| < 1 each | < 1 each   |
| **total**      | **~54**  | **~30**    |

Outcome: the same CSV and LIFT output, byte for byte, from noticeably less code and in noticeably less time; adding a new table afterwards means declaring things rather than copying functions.

**This is a pure refactor.** No phase may change any CSV or LIFT output, any error/warning text, or any CLI behaviour. Anything that would is listed under [Decisions to settle](#decisions-to-settle) and is out of scope unless approved separately.

## Safety net

- The per-table snapshot tests (`tests/testthat/_snaps/*`) pin every reader's CSV output and every writer's LIFT output. They are the primary guard: a refactor phase is done only when `devtools::test()` passes with **no** `.new` snapshot files produced.
- **Caveat about `test-sena3-full-corpus-roundtrip.R`:** it compares each table's reader on the original vs. the round-tripped file, so a reader regression shows up on both sides and cancels out. It guards the writers, not the readers.
- **Reader golden master (temporary, not checked in).** The per-table snapshots cover the whole of `sena3.lift` only for entries, senses and examples. Traits, variants, etymologies, entry-relations, sense-relations and pronunciations are snapshotted only on small curated fixtures. So before the first phase, a scratch script runs every registry `read_fn` over every `.lift` fixture under `tests/testthat/fixtures/` (including the full `sena3.lift`) and writes the `format_table_csv()` output to a scratch directory. After each phase that can affect readers (package hygiene, because import masking such as `dplyr::filter` vs `stats::filter` could change behaviour, and the generic-extractor phase), the script reruns and the two directories must be byte-identical, warnings included (captured separately). Nothing is added to the repo: whole-corpus CSVs aren't human-reviewable snapshots ([AGENTS.md's Testing Approach](../AGENTS.md#testing-approach)), and the check is only needed while this refactor is in flight.
- **Characterisation tests**, added in [their own phase](#phase-characterisation-tests) before any refactoring, for the behaviour the refactor rewrites but no current test exercises.
- Re-time the table above after the reader and writer phases and record the numbers in this file.
- One phase per commit; the suite is green between phases. Never run two `devtools::test()` invocations at once.

## Phases, in order

The order puts the safety net first, then the mechanical, low-risk change, then the two big wins, then the classifier rework, which is easiest once the helpers have settled. Comment cleanup happens inside each phase as files are touched, with a final sweep at the end.

### Phase: characterisation tests

**Status: done.** Implemented as `test-csv2lift_errors.R`, `test-csv2lift_column-classification.R` and `test-lift2csv_rare-shapes.R` (78 expectations, all passing against the pre-refactor code). A mutation check confirmed the media-label alignment test fails if media-less pronunciations are dropped before label rows are numbered.

These pin existing, specified behaviour that the refactor rewrites but no current test exercises. They're characterisation tests, so there's no red step: each must pass against the current code before any refactoring starts. Found by running every reader over every fixture and listing the error and warning paths no fixture reaches.

**How they're written**, so they protect the refactor rather than restrict it:

- **Test through stable entry points only:** the registry's `read_fn` / `attach_fn` (e.g. `attach_variants_to_lift()`, `entry_table()`) or the CLI. Never call the internal helpers this refactor replaces or renames (`classify_*_columns()`, `extract_*_multitext*()`, `extract_single_trait()`) and never check their intermediate tibbles. Check the resulting CSV columns and values, LIFT elements, or the error raised.
- **Match message content, not exact wording:** use a regex over the stable parts (the bad key value, the column name, "not found in the … table"). Today's foreign-key messages come in two shapes ("Pronunciation row 3 references …" vs "Sense <guid> references …"), and these tests shouldn't freeze that inconsistency. The refactor still keeps the wording unchanged; this only leaves room to tidy it later.
- **Warnings:** check message content with `expect_warning(regexp = …)`, not how many fire, in what order, or the call shown. Vectorising may change those without changing what's reported.
- **Pin only specified behaviour.** Duplicate keys are deliberately not pinned; see [Decisions to settle](#decisions-to-settle).
- Inputs are small in-memory tibbles or inline LIFT strings written to a `withr::local_tempfile()`, not new snapshot fixtures.

**What they cover:**

- **Writer error paths** (rewritten in [the writer node lookup phase](#phase-writer-node-lookup)), in a new `test-csv2lift_errors.R`:
  - a foreign key that isn't found, one case per lookup kind: entry by guid (e.g. pronunciations), top-level sense by id (e.g. reversals), sense-or-subsense by id (examples), and a sense-relation's `relation_ref`
  - a subsense row before its parent row (the parent-not-found error, required by `SPEC.md`'s Sense Table)
  - the trait writer's `owner_index` checks for `variant` and `entry-relation` owners: blank, non-integer, out of range
  - an unrecognised trait `owner`
  - a duplicate `entry_lift_id`
  - (A table supplied without the table it requires, e.g. `--examples` without `--senses`, was already covered by `test-csv2lift_table-discovery.R`.)
- **Unknown-column handling** (rewritten in [the classifier phase](#phase-table-driven-column-classifiers)), through each table's `attach_fn`:
  - In tables that support custom fields (entry, sense, etymology, pronunciation), an unknown column becomes `<field type="X"><form lang="Y">`.
  - In tables that don't (example, variant, reversal), an unknown column stops with "Unrecognized <table> column".
  - Ordering rules: `note_restrictions_en` becomes a typed `<note type="restrictions">`, not a `<field type="note_restrictions">`, at entry, sense and example level. `example_source` and `translation_type` are metadata, not a form in a language called "source" or "type". At sense level, `general_note_en` is an untyped note.
- **Reader warnings no fixture triggers** (rewritten in [the generic reader extractors phase](#phase-generic-reader-extractors)), each from a small inline LIFT snippet:
  - two `morph-type` traits on one entry: the warning names the entry, and the first value is kept
  - two `<media>` on one pronunciation: the warning names both hrefs, and the first href and its label are kept
  - two `location` traits on one pronunciation: the first value is kept
- **Media-label alignment** (rewritten in the same phase): an entry whose first pronunciation has no `<media>` and whose second has a `<media>` with a `<label>`. The label must land on the second row, not the first. No current fixture mixes pronunciations with and without media.

### Phase: package hygiene

**Status: done.** Golden master byte-identical and full suite green afterwards. Imports are declared in `R/imports.R` (roxygen) and `NAMESPACE` is generated by `devtools::document()`. No import-conflict warnings on load.

- `DESCRIPTION`: replace the placeholder Title/Description/Authors, and add `Imports:` for every package the `R/` and `scripts/` code actually uses (`xml2`, `dplyr`, `tidyr`, `purrr`, `tibble`, `readr`, `stringr`, `argparser`, `devtools`), with `withr` under `Suggests` alongside `testthat`. `devtools` is in `Imports`, not `Suggests`, because every CLI script calls `devtools::load_all()` at runtime. `rlang` isn't needed: `:=` and `!!` are only ever captured by `tibble()`, never called.
- `NAMESPACE`: add `import()` / `importFrom()` directives so `devtools::load_all()` makes those functions visible to package code. Hand-written or via a single `R/imports.R` roxygen block (`#' @import xml2 purrr ...` + `devtools::document()`) — prefer the roxygen route since `DESCRIPTION` already declares `Roxygen`.
- Delete every `library()` / `suppressMessages(library(dplyr))` call from inside functions in `R/` (23 files). The `library(argparser)` / `library(readr)` calls at the top of the `scripts/` stay — those are scripts, not package code.
- Watch for masking: `dplyr::filter` vs `stats::filter`, `purrr::set_names` vs `rlang::set_names`. Explicit `importFrom()` for the conflicting names avoids surprises.
- README: add a one-line "install dependencies" step (`devtools::install_deps()`), now that `DESCRIPTION` actually lists them.

### Phase: writer node lookup

Replaces the 14 `xml_find_first(root, sprintf(".//entry[@guid='%s']", ...))`-per-row lookups and their copy-pasted `stop()` calls.

- New `R/csv2lift_lookup.R`:
  - `index_nodes(root, xpath, attr)` — one `xml_find_all()` and returns the nodes as a named list keyed by `attr`. On a duplicate key keep the **first** (document order), which is what `xml_find_first()` returns today. That preserves current behaviour without endorsing it: duplicate keys are a [future error](#decisions-to-settle), and once that lands, this is the natural place to detect them.
  - `require_node(index, key, row_label, key_col, table_label)` — returns the node or `stop()`s with exactly today's text: `"<row_label> references <key_col> '<key>', which was not found in the <table_label>"`. `row_label` covers both existing shapes ("Pronunciation row 3", "Sense <guid>").
  - `require_owner_index(nodes, row, row_index, owner, element)` — the `owner_index` parse/range check pasted twice in `R/csv2lift_trait.R`, keeping its message text.
- **Keep the two sense-lookup scopes distinct** — this is deliberate per [SPEC.md's Not Yet Specified](../SPEC.md#not-yet-specified), not an inconsistency to tidy up: examples and subsense parents look up `sense | subsense`; reversals, sense-relations and traits look up top-level `sense` only. Build one index per scope.
- Each `attach_*` builds its index once at the start of its pass. `attach_senses_to_lift()` is the exception: a subsense's parent may have been created earlier in the same pass, so it must add each newly created sense/subsense node to its parent index as it goes.
- Verify xml2 node handles stay valid across later `xml_add_child()` / `xml_add_sibling()` calls on the same document (they should, since they're libxml2 pointers), with the full-corpus round-trip test as the check.

### Phase: generic reader extractors

Replaces the ~12 copied extractors (`extract_multitext_element`, `extract_sense_multitext_element`, `extract_example_multitext`, `extract_pronunciation_multitext`, `extract_etymology_multitext`, `extract_reversal_multitext`, `extract_variant_multitext`, `extract_media_label_multitext`, and the `_with_attribute` variants) with two generic ones.

- New `R/multitext_helpers.R`, which also takes over the already-cross-cutting helpers now sitting in `R/entry_helpers.R` (`multitext_value`, `set_multitext_text`, `keep_text_unindented`, `escape_xml_*`, `SPAN_MARKUP_PATTERN`, `has_nonblank`, `add_multitext_children`, `emit_typed_children`):
  - `extract_multitext(nodes, keys, key_col, xpath, value_col = "text")` — `keys` is a vector aligned with `nodes` that the caller computes (`xml_attr(entries, "guid")`, `xml_attr(senses, "id")`, or `seq_along(examples)`), so one function covers guid-, id- and position-keyed tables.
  - `extract_multitext_with_attribute(nodes, keys, key_col, parent_xpath, attr_name, value_col = "text")`.
  - Implementation: `xml_find_all(nodes, xpath, flatten = FALSE)` (xml2 ≥ 1.3; 1.6.0 installed) gives one nodeset per parent, so keys are expanded with `rep(keys, lengths(...))` and `lang` / text are read with one vectorised `xml_attr()` and one `map_chr(multitext_value)` over the flattened forms — building one tibble per table instead of one per `<form>`. This is where most of the read time goes.
  - Both always return a correctly typed zero-row tibble on empty input, which removes every hand-written `empty_result <- tibble(...)`.
  - Key column type must match what each caller's `left_join` uses today: `integer` for the position-keyed tables, `character` otherwise.
- `extract_media_label_multitext()` passes the chosen media nodes (dropping `NULL`s) with their pronunciation indices as keys, which keeps the "first media" sharing intact.
- Merge `extract_single_trait()` and `extract_single_pronunciation_trait()` into one helper that takes the warning message's subject as an argument, so both warning texts stay identical.
- `R/trait_helpers.R`: the three identical `empty_result` tibbles become one `empty_trait_rows()`. `extract_variant_traits()` and `extract_entry_relation_traits()` differ only in `owner` and become one `extract_positional_owner_traits(nodes, owner)`.
- The `*_table()` readers keep their structure (meta stage → one `pivot_wider` per column family → `left_join`s); only the extractor calls change.
- Also worth timing: `extract_sense_metadata()`'s recursion and `entry_table()`'s six separate `map_chr` passes over `entries`. Vectorise them only if they still show up in the profile after the extractor change.

### Phase: table-driven column classifiers

Replaces the seven `classify_*_columns()` functions (each a hand-written `grepl` → `sub` → `cat` → `tibble` ladder).

- One `classify_columns(col_names, meta, rules, fallback, table_label)` in a new `R/column_classification.R`:
  - `meta` — exact-match metadata column names (always checked first, as now).
  - `rules` — an ordered list of `(pattern, kind)` entries; the typed-note rule (`^note_(.+)_([^_]+)$`, which yields both `field_type` and `lang`) is one shared rule constant, not seven copies.
  - `fallback` — `"field"` (last-underscore custom-field split) or `"error"`. The rule: **a table falls back to custom-field when, and only when, it reads and writes `<field>` children of its element.** Today that's entry, sense, etymology and pronunciation. Example, variant and reversal don't read `<field>`, so an unknown column there is a typo or unsupported data and must fail loudly. Supporting `<field>` on one of those tables later means flipping its `fallback` as part of that change. This matches every table's current behaviour exactly; the phase only makes the rule explicit. The error text stays `"Unrecognized <table> column '<col>'"`.
  - Always returns the same four columns `column, kind, field_type, lang` (`classify_variant_columns()` currently omits `field_type`).
- Each table's `classify_*_columns()` becomes a few-line wrapper declaring its rules, or the rules move into a column on the registry. Prefer thin wrappers in the per-table helper files: the rule order is table-specific and reads better next to the reader that produces those columns.
- Keep the per-column "Classifying column …" stderr lines exactly as now unless [decision 1](#decisions-to-settle) says otherwise.
- `SPEC.md`'s Column Classification section and the skill's classifier step name these functions. Update both to describe declaring rules instead of writing a ladder.

### Phase: comment and doc sweep

Done inside each phase for the files it touches, then a final pass over anything left:

- Fix stale comments: `R/variant_helpers.R` ("once C1b's owner_index lands" — it has landed), `scripts/csv2lift.R:75` (lists only three tables), and `R/sense_table.R:29` / `:72` (`§2` / `§3` → anchor links, per [AGENTS.md's Markdown Conventions](../AGENTS.md#markdown-conventions)).
- Trim comments that restate `SPEC.md` rationale or quote fixture statistics down to the non-obvious *why* plus a `SPEC.md` anchor link. The prime example is the 40-line attach-order header in `R/table_registry.R`. Comments that explain code-local subtleties (e.g. `keep_text_unindented()`, the `argparser` hyphen/underscore note) stay.
- `SPEC.md` names the extractor and classifier functions in several places (e.g. `extract_pronunciation_multitext` ×4, `extract_reversal_multitext` ×3, `classify_` ×6). Update every reference to the new names in the phase that renames them, not at the end (see [AGENTS.md's Specification](../AGENTS.md#specification)). Do the same for `.claude/skills/adding-a-lift-field/SKILL.md`, whose steps should end up shorter: "call the generic extractor with your key" instead of "write an `extract_<table>_multitext()` analogue".

## Out of scope

- The registry design, CLI flags, CSV column naming, and the snapshot test layout.
- Widening the subsense axes for reversals, relations and traits (deliberately excluded per [SPEC.md's Not Yet Specified](../SPEC.md#not-yet-specified)).
- `R/copy_lift_entries.R` / `scripts/copy-lift-entries.R`: separate tool, no duplication with the rest. It gets only the `library()` removal from the package-hygiene phase, if it needs it.

## Decisions to settle

No decisions are still open; these record what was settled.

1. **Classifier stderr noise: settled, left as-is for now.** csv2lift writes one "Classifying column '…' as …" line per column per table to stderr (dozens on a real table folder). No test asserts it. Collapsing it to one summary line per table, keeping per-column detail only for custom-field fallbacks, is a possible later change. It would be a visible behaviour change, so it needs separate approval.
2. ~~**Unknown-column policy.**~~ Settled: it stays per-table, following the rule in [the classifier phase](#phase-table-driven-column-classifiers) (fall back to custom-field only when the table supports `<field>`). The current split already follows that rule.
3. **Duplicate keys: a future error, out of scope here.** If a CSV has two rows with the same `entry_id` (entries) or `sense_guid` (senses), csv2lift currently writes both. Every later foreign-key lookup then silently attaches to the first one, because `xml_find_first()` returns the first match in document order. That's accidental, not designed. The intended behaviour is a hard error, like the existing duplicate `entry_lift_id` check in `R/csv2lift_entry.R`. This refactor keeps first-match-wins (see [the writer node lookup phase](#phase-writer-node-lookup)) and deliberately doesn't pin it with a test. Making it an error is a follow-up behaviour change, with its own red-then-green test and a `SPEC.md` update to its Structural Rules section.
