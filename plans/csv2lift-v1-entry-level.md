# csv2lift v1: entry-level CSV → LIFT converter

**Status:** Done. Step 0 (test harness) and Step 1+ (implementation) are both complete — all 3 pre-seeded snapshots pass against `R/csv2lift_entry.R` + `R/entry_helpers.R` additions + `scripts/csv2lift_entry-table.R`, with no edits to the pre-seeded expectations except fixing one snapshot that had been hand-authored with the wrong `<form>` order (caught before implementation, see the ordering-rule note below). Full regression suite and a round-trip smoke test both pass.

## Context

This repo currently only converts LIFT → CSV ("lift2csv"). The user wants to start building the reverse direction (csv2lift) now, deliberately before lift2csv itself is complete, so that round-tripping surfaces design issues early while complexity is still low. There is no prior attempt at csv2lift in git history and no existing LIFT-writing infrastructure in the repo (the closest thing, `copy_lift_entries.R`, does regex/string-surgery on raw text rather than building an XML tree, and is treated as an unrelated utility, not a template, per the user).

Investigation (direct file reads of `R/entry_table.R`, `R/entry_helpers.R`, `R/sense_table.R`, `R/copy_lift_entries.R`, plus `resources/lift-0.13.rng` and SIL's "Technical Notes on LIFT used in FLEx") established:
- lift2csv's column-naming conventions (bare lang code for lexical-unit, `citation_<lang>`, `<type>_<lang>` for custom fields) are produced by `tidyr::pivot_wider(names_glue=...)` in `R/entry_table.R` and are otherwise undocumented in code — only in README prose.
- A minimal valid LIFT entry only needs a `guid` (FLEx's actual primary key) — no separate `id` is required. `entry_table()` never captured `id` in the first place, so there's nothing to round-trip there.
- The LIFT RNG schema treats entry children as an unordered `<interleave>`, but FLEx's own docs show a fixed canonical order (lexical-unit → citation → sense...) matching its UI — worth emitting that order for readability even though not schema-required.
- `<field type="X">` must appear once per type with multiple `<form lang>` children grouped inside it — not one `<field>` per type+lang combination.

**Decisions already confirmed with the user:**
1. v1 generates a brand-new, self-contained LIFT file directly from a CSV (not a patch/merge into an existing LIFT file).
2. v1 scope is entry-level fields only — matching exactly what `entry_table()` exports today (`entry_id`/guid, `dateCreated`, `dateModified`, `morph_type`, bare-lang lexical-unit columns, `citation_<lang>`, `<type>_<lang>` custom fields). Sense-level fields (gloss, grammatical-info) are a deliberate near-follow-up, not v1 — code should not preclude that extension, but should not stub it out either.
3. No large upfront refactor. The one small "prep" step (a column-name classifier) is folded directly into building csv2lift rather than done as a separate refactor.
4. **Testing convention (updated from the original version of this plan):** since planning began, the repo's whole CLI approval-testing convention changed — `expect_snapshot()` (markdown-wrapped stdout) was replaced repo-wide by `expect_snapshot_file()` (raw per-fixture files under `tests/testthat/_snaps/`), via the shared `expect_cli_stdout_file_snapshot()` helper in `tests/testthat/helper-cli-snapshots.R`, with `tests/testthat/setup.R` forcing `NOT_CRAN=true` so these tests don't silently skip. csv2lift's tests should use this exact same convention rather than introducing a separate hand-authored `expected/*.lift` pattern.
5. **TDD ordering:** tests and their expected output go in *first*, before any implementation exists — see "Step 0" below. This works cleanly with approval testing here because the exact expected XML for each fixture is fully determined by the design above; it can be hand-derived and pre-seeded as the approved snapshot rather than generated from a first passing run.

## Implementation

### Step 0 — tests first (red) — THIS is what's being implemented now

1. **Author the 3 input fixtures** under `tests/data/csv2lift_entry-table/input/`. Where a real existing fixture already covers a case, reuse its name and its actual `entry_table()` output verbatim rather than inventing new data; only fall back to a hand-authored fixture where no existing one fits.

   `sena3_single_entry_plant.csv` — real data, copied verbatim from the already-verified `entry_table()` output for `tests/data/lift2csv_entry-table/input/sena3_single_entry_plant.lift` (see `tests/testthat/_snaps/entry-table_end-to-end/sena3_single_entry_plant.csv`). Covers lexical-unit + morph_type + citation:
   ```
   entry_id,dateCreated,dateModified,morph_type,seh,citation_seh
   f67e332a-b296-4967-ace3-5583ce66e95b,2006-08-23T21:07:21Z,2006-09-22T20:14:24Z,stem,bzwal,bzwala
   ```

   `lela-teli-empty-lexicon.csv` — real data, matching the real `lela-teli-empty-lexicon.lift` fixture's `entry_table()` output, which is a genuinely empty (0-byte) file, not header-only — confirmed by inspecting `tests/testthat/_snaps/entry-table_end-to-end/lela-teli-empty-lexicon.csv` (0 bytes) and by testing directly that `readr::read_csv()` on a 0-byte file cleanly returns a 0×0 tibble with no warning. So this fixture file itself should be created with **zero bytes**, no header row.

   `citation-and-custom-field.csv` — no existing standalone fixture has a `<field type=...>` element, so this one stays hand-authored (confirmed with the user — deliberately synthetic, not presented as sourced from an existing file). Exercises citation detection and multi-lang grouping under one `<field>` (the trickiest correctness point):
   ```
   entry_id,dateCreated,dateModified,morph_type,seh,citation_seh,Plural_seh,Plural_en
   f67e332a-b296-4967-ace3-5583ce66e95b,2006-08-23T21:07:21Z,2006-09-22T20:14:24Z,stem,bzwal,bzwala,bzwala-bzwala,plants
   ```

2. **Pre-seed the approved snapshots** at `tests/testthat/_snaps/csv2lift-entry-table_end-to-end/<fixture>.lift`, hand-authored to the exact byte-for-byte content the design implies. Verified directly by running the intended `xml2` calls in isolation (not against real code, since none exists yet) — this is the literal expected content, not a sketch:

   `sena3_single_entry_plant.lift`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <lift version="0.13" producer="lexicon_file_conversions csv2lift">
     <entry dateCreated="2006-08-23T21:07:21Z" dateModified="2006-09-22T20:14:24Z" guid="f67e332a-b296-4967-ace3-5583ce66e95b">
       <lexical-unit>
         <form lang="seh">
           <text>bzwal</text>
         </form>
       </lexical-unit>
       <trait name="morph-type" value="stem"/>
       <citation>
         <form lang="seh">
           <text>bzwala</text>
         </form>
       </citation>
     </entry>
   </lift>
   ```

   `lela-teli-empty-lexicon.lift`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <lift version="0.13" producer="lexicon_file_conversions csv2lift"/>
   ```

   `citation-and-custom-field.lift`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <lift version="0.13" producer="lexicon_file_conversions csv2lift">
     <entry dateCreated="2006-08-23T21:07:21Z" dateModified="2006-09-22T20:14:24Z" guid="f67e332a-b296-4967-ace3-5583ce66e95b">
       <lexical-unit>
         <form lang="seh">
           <text>bzwal</text>
         </form>
       </lexical-unit>
       <trait name="morph-type" value="stem"/>
       <citation>
         <form lang="seh">
           <text>bzwala</text>
         </form>
       </citation>
       <field type="Plural">
         <form lang="en">
           <text>plants</text>
         </form>
         <form lang="seh">
           <text>bzwala-bzwala</text>
         </form>
       </field>
     </entry>
   </lift>
   ```

   **Ordering rule (clarified with the user):** `field`'s two `<form>` children must come out in the CSV's own column order (`seh` before `en`, matching `Plural_seh,Plural_en` in the header) — never re-sorted. This mirrors `entry_table()`'s forward direction: `pivot_wider` derives its column order from the order `<form>` elements appear in the original LIFT document (`xml_find_all` returns nodes in document order), so a faithful round trip means csv2lift must preserve whatever order the CSV already gives it, not impose its own (e.g. alphabetical) ordering. `classify_entry_columns()` already does this naturally, since it maps over `col_names` in the order given and never reorders.

3. **Write `tests/testthat/test-csv2lift-entry-table_end-to-end.R`**, using the existing shared helpers unchanged:
   ```r
   fixture_dir <- testthat::test_path("..", "data", "csv2lift_entry-table")
   script_path <- "../../scripts/csv2lift_entry-table.R"

   for (input_path in fixture_inputs(fixture_dir, pattern = "\\.csv$")) {
     stem <- fixture_stem(input_path)
     test_that(paste0("csv2lift-entry-table_end-to-end_", stem), {
       expect_cli_stdout_file_snapshot(script_path, input_path, name = paste0(stem, ".lift"))
     })
   }
   ```

At this point the suite is red: `scripts/csv2lift_entry-table.R` doesn't exist, so `Rscript` fails and the tests fail against the pre-seeded expected content — not a vague error, a concrete diff target to implement toward. **This is where implementation stops for now.**

### Step 1+ — implement until green (NOT part of this implementation pass — future work)

- **`R/entry_helpers.R`** (existing file — add two functions alongside the three lift2csv extractors, since they are their direct inverses):
  - `classify_entry_columns(col_names)` — classifies each CSV column name into: meta column (exact match against `entry_id`/`dateCreated`/`dateModified`/`morph_type`), citation column (`^citation_(.+)$`), bare lexical-unit lang column (no underscore), or custom field column (has an underscore — split on the **last** underscore into `type`/`lang`). Emit a stderr diagnostic per classified column (matches `AGENTS.md`'s stderr-for-diagnostics convention and directly serves the "see what issues we face" goal).
  - `add_multitext_children(parent_node, lang_values)` — given an `xml_node` and a named vector (name = lang, value = text, blank/`NA` skipped), adds one `<form lang><text>` child per entry. This is the single reusable primitive for lexical-unit, citation, and each field type.
  - **Documented known limitation** (code comment, not solved generally): if a writing-system code itself contains an underscore, or a custom field is literally named `citation`, classification will misfire. Accepted and out of scope for v1.

- **`R/csv2lift_entry.R`** — `entry_table_to_lift(entry_table)`, takes the entry-level tibble (same shape `entry_table()` produces, or a CSV read into the same shape) and returns an `xml2::xml_document`. Builds the tree with `xml2::xml_new_document()` / `xml_add_child()`:
  - root `<lift version="0.13" producer="lexicon_file_conversions csv2lift">`
  - one `<entry dateCreated=... dateModified=... guid=...>` per row (omit any of the three attributes that are `NA`/blank)
  - `<lexical-unit>` with one `<form lang><text>` per non-blank bare-lang column
  - `<trait name="morph-type" value=...>` if `morph_type` is present
  - `<citation>` with one `<form lang><text>` per non-blank `citation_<lang>` column
  - one `<field type="X">` per distinct custom-field type, containing one `<form lang><text>` per lang for that type (group columns by type first — do not emit one `<field>` per column)
  - Zero-row input still produces a valid, minimal `<lift .../>` root with no entries — no special-cased empty-string output.

- **`scripts/csv2lift_entry-table.R`** — CLI script, exact skeleton mirror of `scripts/lift2csv_entry-table.R` (`commandArgs`/`load_all`/`argparser`), but:
  - reads the CSV with `readr::read_csv(argv$CSV_file, na = "", col_types = cols(.default = "c"), show_col_types = FALSE)` — both `na = ""` and forcing all columns to character are required, otherwise blank cells and type-guessed columns (e.g. numeric-looking custom fields) would silently corrupt the round trip.
  - calls `entry_table_to_lift()` and writes with `cat(as.character(doc))` to stdout; errors to stderr per convention.

- Iterate until `Rscript scripts/csv2lift_entry-table.R <fixture>.csv` output matches the pre-seeded snapshot exactly for all three fixtures (green). Do not touch the pre-seeded `_snaps/` files to make a test pass — if output legitimately needs to differ from what was pre-seeded (e.g. a design detail turns out wrong once real code hits it), that's a real conversation to have, not a snapshot to quietly update.

Optionally, once green: a smoke-test round trip using the existing `tests/data/lift2csv_entry-table/input/sena3_single_entry_plant.lift` fixture (LIFT → `entry_table()` → CSV → `entry_table_to_lift()`), checking semantic content survives — kept as a clearly separate, non-snapshot test since the original has an `id` attribute, a `<sense>`, and a `<header>` this tool won't reproduce.

### Explicitly out of scope for v1

- Sense-level fields (structure `entry_table_to_lift` so a future `sense_table_to_lift`-style companion can attach `<sense>` children later, but don't build it now).
- `<header>` / `<header><fields>` custom-field declarations (confirmed schema-optional; FLEx defaults custom fields to MultiUnicode on import without them).
- Patch-in-place / merge-into-existing-LIFT mode.
- Any general fix for the column-name-split ambiguity beyond the documented last-underscore rule.
- Matching FLEx's own compact (non-indented) export formatting — pretty-printed `xml2` output is the deliberate choice, since v1 is fresh-generation, not byte-for-byte patching.

## Verification

1. Confirm red first: after Step 0, before any implementation exists, run the new test file and confirm it fails (script missing) — a real check that the pre-seeded expectations are wired up, not just sitting unused.
2. Confirm green without silent rewrites: once implemented (Step 1+, later), run the suite and confirm all three tests pass against the pre-seeded snapshots *as originally hand-authored* — no `.new` files appear, and nothing needed to be regenerated/accepted. If a test fails, fix the implementation to match the hand-authored expectation; don't edit the expectation to match the implementation unless the hand-authored version turns out to have been wrong (a real, callable-out decision, not a quiet edit).
3. `Rscript scripts/csv2lift_entry-table.R tests/data/csv2lift_entry-table/input/citation-and-custom-field.csv` — inspect stdout manually as an extra sanity check beyond the automated comparison.
4. Round-trip smoke check: run `scripts/lift2csv_entry-table.R` on the new tool's own output and confirm the resulting CSV matches the original CSV's non-metadata columns (validates the reversal logic is actually inverse-correct, not just schema-valid).
5. Full suite: `Rscript -e "devtools::load_all(); testthat::test_dir('tests/testthat')"` to confirm no regressions to the existing lift2csv tests.
