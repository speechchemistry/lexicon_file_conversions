# csv2lift v2: add sense-level support

## Context

csv2lift v1 (`scripts/csv2lift_entry-table.R`) builds a LIFT file from a single entry-level CSV. `SPEC.md` §4/§6 already flagged sense-level csv2lift as "not yet implemented" and stated the intended shape: one unified script taking multiple normalized table CSVs (entries required, further tables optional), joined internally by foreign key — not one script per table, since a LIFT file is a single tree and senses can't exist without a parent entry. This plan implements that: sense-level round-tripping, and the entry-only script becoming the general `scripts/csv2lift.R`.

This also directly follows from discussing two real user workflows: **(1) editing an existing lexicon** — the user already has normalized `entry_table.csv`/`sense_table.csv` from a prior `lift2csv` export and edits them in place — is what this design serves well. **(2) greenfield authoring from a single flat CSV** is harder with two normalized tables and was explicitly deferred to a future "flatten↔split" helper script (parked in `SPEC.md` §8, not part of this plan).

Verified directly (not guessed) before writing this plan:
- Real ground truth for the shared `sena3_single_entry_plant.lift` fixture: `sense_table()` on it returns exactly `sense_guid=b84dc935-feaf-4489-9434-1da83cfb5e7c, entry_id=f67e332a-b296-4967-ace3-5583ce66e95b, grammatical_info=Verbo, gloss_en=plant`.
- Exact `xml2` output for an entry with one nested sense (ran the real calls, not inferred): `<grammatical-info value="Verbo"/>` renders self-closing (no children, matches real LIFT), followed by `<gloss lang="en"><text>plant</text></gloss>`, both nested inside `<sense id="...">`.
- `argparser` supports mixing one required positional arg with an optional named flag (`--senses`, `default = NA`) — confirmed by running both invocation styles directly.
- Per the LIFT RNG schema and FLEx notes already gathered for v1: senses use `id` (not a separate `guid` attribute like entries) — `sense-content` only ever has an optional `id`.

## Decisions

1. **Rename, don't add a second script**: `scripts/csv2lift_entry-table.R` → `scripts/csv2lift.R`. It now takes a required positional entries CSV plus an optional `--senses` flag. Entries-only invocation stays almost identical to today (`Rscript scripts/csv2lift.R entries.csv`), so existing usage isn't disrupted much.
2. **Sense attachment is a new function**, `attach_senses_to_lift(doc, sense_table)` in a new `R/csv2lift_sense.R` (mirrors the existing `entry_table.R`/`sense_table.R` file split on the forward side) — not folded into `csv2lift_entry.R`, and not a column-classification problem like entry-level (sense columns are fixed: `sense_guid`, `entry_id`, `grammatical_info`, `gloss_en` — no dynamic per-lang columns to classify).
3. **Orphaned foreign key = hard error.** If a sense row's `entry_id` doesn't match any entry already in the doc, `attach_senses_to_lift()` stops with a clear message (fail-fast, matching `copy-lift-entries.R`'s existing error philosophy) rather than silently dropping the sense.
4. **Scope stays minimal, matching v1's restraint**: one sense per entry is fully implemented and tested. Multiple senses per entry, `<gloss>` in other languages, and multiple `grammatical-info` values are explicitly deferred — v2 mirrors exactly what `sense_table()` already extracts (§4's existing known limitations), not an attempt to fix that lossiness as part of this change.
5. **TDD ordering, same as v1**: tests + hand-verified pre-seeded snapshots go in first (red), then implementation (green).

## Implementation

### Step 0 — tests first (red)

1. **Rename existing v1 fixtures/dirs** (content unchanged except the one noted below):
   - `tests/data/csv2lift_entry-table/` → `tests/data/csv2lift/`
   - `input/sena3_single_entry_plant.csv` → `input/sena3_single_entry_plant_entries.csv`
   - `input/lela-teli-empty-lexicon.csv` → `input/lela-teli-empty-lexicon_entries.csv`
   - `input/citation-and-custom-field.csv` → `input/citation-and-custom-field_entries.csv`
   - `tests/testthat/_snaps/csv2lift-entry-table_end-to-end/` → `tests/testthat/_snaps/csv2lift_end-to-end/` — only the **directory** is renamed. The 3 snapshot **filenames inside it stay bare** (`sena3_single_entry_plant.lift`, `lela-teli-empty-lexicon.lift`, `citation-and-custom-field.lift`), matching step 4's test code, which strips `_entries` from the stem *before* building the snapshot name (`name = paste0(stem, ".lift")`). The snapshot is named after the fixture's logical stem, not the input file — this matters because a fixture can have two input files (entries + senses) but only one output (`.lift`) file.
   - `tests/testthat/test-csv2lift-entry-table_end-to-end.R` → `tests/testthat/test-csv2lift_end-to-end.R`

2. **Add one new paired fixture** — `input/sena3_single_entry_plant_senses.csv` (real data, verified above):
   ```
   sense_guid,entry_id,grammatical_info,gloss_en
   b84dc935-feaf-4489-9434-1da83cfb5e7c,f67e332a-b296-4967-ace3-5583ce66e95b,Verbo,plant
   ```

3. **Update the pre-seeded snapshot** for `sena3_single_entry_plant` (this is the only one that changes content — it now includes the attached sense, verified byte-for-byte above):
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
       <sense id="b84dc935-feaf-4489-9434-1da83cfb5e7c">
         <grammatical-info value="Verbo"/>
         <gloss lang="en">
           <text>plant</text>
         </gloss>
       </sense>
     </entry>
   </lift>
   ```
   The other two renamed snapshots (`lela-teli-empty-lexicon.lift`, `citation-and-custom-field.lift`) keep their existing content unchanged — they have no paired `_senses.csv`, so they continue to exercise the entries-only path.

4. **Rewrite the test file** to discover fixture pairs (entries required, senses optional sibling file):
   ```r
   fixture_dir <- testthat::test_path("..", "data", "csv2lift")
   script_path <- "../../scripts/csv2lift.R"

   for (entries_path in fixture_inputs(fixture_dir, pattern = "_entries\\.csv$")) {
     stem <- sub("_entries$", "", fixture_stem(entries_path))
     senses_path <- file.path(dirname(entries_path), paste0(stem, "_senses.csv"))

     args <- entries_path
     if (file.exists(senses_path)) args <- c(args, "--senses", senses_path)

     test_that(paste0("csv2lift_end-to-end_", stem), {
       expect_cli_stdout_file_snapshot(script_path, args, name = paste0(stem, ".lift"))
     })
   }
   ```

At this point: red — `scripts/csv2lift.R` doesn't exist yet (only the old `csv2lift_entry-table.R` does), and even once renamed, `attach_senses_to_lift()` doesn't exist, so the `sena3_single_entry_plant` case fails against the updated (sense-including) snapshot.

### Step 1+ — implement until green

- **`R/csv2lift_sense.R`** (new file) — `attach_senses_to_lift(doc, sense_table)`:
  - Returns `doc` unchanged if `sense_table` has 0 rows.
  - For each row: find the entry node via `xml_find_first(doc, sprintf(".//entry[@guid='%s']", row$entry_id))`; if not found, `stop()` with a clear message naming the sense and the missing `entry_id` (fail-fast, per Decision 3).
  - Add `<sense id=row$sense_guid>` (omit `id` if blank — same "only emit non-blank attributes" rule as entries) as a child of that entry node.
  - If `grammatical_info` is non-blank, add `<grammatical-info value=...>` (self-closing, no children).
  - If `gloss_en` is non-blank, add `<gloss lang="en"><text>...</text></gloss>`.
  - Iterate rows via `purrr::walk`, matching `entry_table_to_lift()`'s established style.

- **`scripts/csv2lift.R`** (renamed from `csv2lift_entry-table.R`):
  - Positional `entries_csv` (required) + `--senses` (optional, `default = NA`).
  - Reads entries CSV → `entry_table_to_lift()` → `doc`.
  - If `--senses` given (`!is.na(argv$senses)`), reads it the same way (`na = ""`, all-character) and calls `attach_senses_to_lift(doc, sense_table)`.
  - `cat(as.character(doc))` as before.

- Iterate until all fixtures pass against the (mostly unchanged, one updated) pre-seeded snapshots — same "don't edit the snapshot to fit the code" discipline as v1.

### Explicitly out of scope for v2

- Multiple senses per entry (should work given the design, but not exercised by a dedicated fixture yet — a natural v3 addition).
- Multi-lang gloss, multiple grammatical-info per sense (mirrors `sense_table()`'s existing forward-direction limitations — not being fixed here).
- The greenfield "flatten a single CSV into entries+senses" helper script discussed separately (parked in `SPEC.md` §8).
- Any other LIFT table beyond entries/senses (variants, etymology, pronunciation, etc.).

## SPEC.md updates (part of this change, per AGENTS.md's "keep SPEC.md in sync" rule)

- §4 (sense table): change "csv2lift direction: not yet implemented" to describe the actual behavior — `id` (not `guid`) is used for senses, attachment is by matching `entry_id` to an entry's `guid`, orphaned `entry_id` is a hard error.
- §6 (csv2lift CLI shape): update to the final, real interface — positional `entries_csv` + optional `--senses` flag — and note the rename from `csv2lift_entry-table.R` is done.
- §8 (not yet specified): remove "Sense-level csv2lift" (now specified); keep the other deferred items; optionally add "multiple senses per entry" as a noted coverage gap if it isn't captured elsewhere.

## Verification

1. Confirm red first (Step 0 alone, before touching implementation): the `sena3_single_entry_plant` case fails against the sense-including snapshot; the other two still pass unchanged (proving the rename alone didn't break entries-only behavior).
2. Confirm green: all fixtures pass unmodified against the pre-seeded snapshots once Step 1+ lands.
3. Round-trip smoke check: `csv2lift.R` on `sena3_single_entry_plant_entries.csv` + `_senses.csv` → `lift2csv_sense-table.R`/`lift2csv_entry-table.R` on the result → confirm values match the originals (same style of check as v1, extended to senses).
4. Full regression suite (`testthat::test_dir("tests/testthat")`, `NOT_CRAN` unset) — confirm nothing else broke, especially the entries-only fixtures.
