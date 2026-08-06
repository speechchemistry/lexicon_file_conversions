# Add entry-level `<note>` support to csv2lift / lift2csv

## Context

While adding LIFT-model reference links to `SPEC.md`, we compared the current entry-level implementation against the LIFT schema (`lift.rng`) and FLEx's technical notes and found several unimplemented entry sub-elements (pronunciation, etymology, relations/cross-references, variants, additional traits, `order`/`dateDeleted`). Of these, plain entry-level `<note>` (FLEx's "Note" field, stored as `LexEntry.Comment`) is the simplest: it's an untyped multitext element structurally identical to `<citation>` — no nested sub-fields, no cross-entry references. This plan adds it end-to-end, following the citation pattern exactly, as the first of these gaps to close.

`<note>` here means the untyped entry-level note only. Sense-level notes and the various `<field type="...">`-based FLEx "notes" (bibliography, restrictions, etc.) are out of scope — those already round-trip today via the generic custom-field mechanism.

**Important correction from checking real fixtures:** entry-level `<note>` is not always untyped in the wild. `Sena3.lift` (already checked in) has 67 direct entry-level `<note>` children: 61 are `<note type="restrictions">` and only 6 are the plain untyped note. The FLEx technical-notes PDF's own example XML shows restrictions as `<field type="restrictions">`, which contradicts this real FieldWorks-exported fixture — and the user confirmed in FLEx itself that filtering entries for non-blank "Note" turns up nothing in that project, i.e. FLEx treats `type="restrictions"` as its own distinct "Restrictions" field, not as the generic Note field, even though LIFT happens to reuse the same `<note>` element for both. So the read-side xpath **must** exclude typed notes explicitly (`./note[not(@type)]/form`, not `./note/form`) — otherwise restrictions text would get merged into the `note_<lang>` column, and an entry with both a typed and an untyped note in the same language would make `pivot_wider` collide. `type="restrictions"` stays out of scope for this change (it deserves its own type-keyed-column treatment later, analogous to custom fields).

## Process: TDD (red → green → refactor)

This repo's convention (per prior commit history, e.g. "TDD red stage" / "TDD green stage" commits) is to always write the failing test first. This feature follows the full red/green/refactor cycle — see step ordering below and the "AGENTS.md update" section.

1. **Red:** add the fixture changes described under "Test fixtures" below *first*, then run the test suite. Both the csv2lift and lift2csv snapshot tests for the touched fixtures should fail/error (missing `note`/`note_seh` handling) — confirming the test actually exercises the new behavior before any implementation exists.
2. **Green:** implement the code changes below with the minimum needed to make those tests pass, reviewing and accepting the resulting snapshots (see "Verification").
3. **Refactor:** with the tests green as a safety net, look over the new code and its immediate surroundings (`entry_table.R`, `entry_helpers.R`, `csv2lift_entry.R`) for any duplication or awkwardness introduced by adding the third near-identical multitext block (lexical-unit/citation/note now all follow the same shape) — e.g. whether the repetition across the three blocks is still clear as-is or would read better factored out — then re-run the full suite to confirm it's still green before considering the change done.

## Implementation

Mirror `<citation>` handling in every file it appears, using column prefix `note_<lang>` (reserved, same convention as `citation_<lang>`).

1. **`R/entry_table.R`** (lift2csv direction) — after the citation block (lines 46-56), add an equivalent block:
   ```r
   notes_long <- extract_multitext_element(entries, "./note[not(@type)]/form")
   notes_wide <- notes_long |>
     pivot_wider(id_cols = entry_id, names_from = lang, values_from = text, names_glue = "note_{lang}")
   ```
   and join it into `combined` alongside `citations_wide` (line 62). The `[not(@type)]` predicate is required — see the correction note under "Context" above.

2. **`R/entry_helpers.R`** — in `classify_entry_columns()`, add a `note` branch mirroring the citation branch (lines 84-88): match `^note_(.+)$`, capture group is the lang, `kind = "note"`. Place it as its own `if` block near the citation check. Extend the "known limitation" comment (lines 96-98) to also mention a field literally named `note` (or a writing-system code containing an underscore) as misclassification risks, since the same last-underscore ambiguity now applies to both prefixes.

3. **`R/csv2lift_entry.R`** — mirror the citation block (lines 49-55):
   - Add `note_cols <- filter(col_classes, kind == "note")` alongside `citation_cols` (line 17).
   - Add a block right after the citation block that builds `note_values`, checks `has_nonblank()`, and emits `<note>` + `add_multitext_children()` — same shape as citation but no attribute on the element itself.
   - Element order: place `<note>` immediately after `<citation>`, before the `<field>` loop (matches `lift.rng`'s relative ordering of citation/note among entry children, and keeps with the existing non-schema-strict-but-consistent ordering convention already documented in `SPEC.md` §3).

## AGENTS.md update

Two bullets, both in "Working Style" / "Testing Approach" as appropriate:

- **TDD (Testing Approach):** codify the convention that's already followed in practice (visible in commit history) but not yet written down: for a behavior change, add/extend the fixture and confirm the corresponding test fails first (red), write the minimum implementation to make it pass (green), then refactor with tests as a safety net before considering the change done.
- **Keep the repo plan copy in sync (Working Style):** extend the existing "save non-trivial implementation plans to `plans/<descriptive-name>.md`" bullet to clarify it's not a one-time save — whenever the plan is revised (e.g. after new information surfaces mid-planning, as happened here), re-sync `plans/<name>.md` with the latest approved version before or immediately after exiting plan mode, not just when first drafted.

## SPEC.md updates (§3 Entry table)

- Add table row: `note_<lang>` | `entry/note/form` | reserved prefix `note_`.
- Column classification algorithm: insert a step for the `^note_(.+)$` match (between the existing citation step and the custom-field step), renumbering as needed.
- Extend the "known limitation" sentence to cover both `citation` and `note` as field-type names that would misclassify.
- Canonical child element order bullet: `<lexical-unit>`, `<trait name="morph-type">`, `<citation>`, `<note>`, then fields.
- Extend the "`<form lang>` children emitted in CSV column order" bullet and the "omits empty optional elements" bullet to include `<note>`.

## Test fixtures (approval-test style, no new test-*.R code needed — the existing loops auto-discover fixtures)

- **csv2lift direction:** add a `note_seh` column (with a value) to `tests/testthat/fixtures/csv2lift/citation-and-custom-field_entries.csv` — this fixture already exercises citation + custom field together, so adding note tests all three interacting in one entry.
- **lift2csv direction:** already covered — the user has added a real-world fixture, `tests/testthat/fixtures/lift2csv_entry-table/note_and_phonology_notes.lift`, containing exactly one untyped entry-level `<note>` per entry (3 entries), *plus* sense-level plain/phonology/source notes and `<pronunciation>` elements that must stay untouched. This is good regression coverage: the snapshot should show a `note_en` column with only the entry-level text, and no leakage from the sense-level notes. No fixture edit needed on our part for this direction.
  - **Note directories are NOT shared between the two lift2csv-side tests** — `test-entry-table_end-to-end.R` reads `fixtures/lift2csv_entry-table/`, but `test-join-sense-entry-table_end-to-end.R` reads a *separate* directory, `fixtures/lift2csv_join-sense-entry-table/`, which holds its own duplicate copies of the shared fixtures (confirmed identical via `diff` for `sena3_single_entry_plant.lift`). To get join-table coverage too, copy `note_and_phonology_notes.lift` into `fixtures/lift2csv_join-sense-entry-table/` as well.
  - Side effect to expect during Green: `Sena3.lift` (already checked in, used by both directories) contains 6 genuine untyped entry-level notes today (see the "Context" correction above) that have never been extracted. Implementing `./note[not(@type)]/form` will surface them, so `Sena3.csv`'s existing snapshot in *both* `_snaps/entry-table_end-to-end/` and `_snaps/join-sense-entry-table_end-to-end/` will change too — review those diffs alongside the new fixture's when accepting.

## Verification

1. **Red:** add the `note_seh` CSV column and copy `note_and_phonology_notes.lift` into `fixtures/lift2csv_join-sense-entry-table/` (fixture-only changes, no code yet), then run the test suite (`devtools::test()` or the project's usual `Rscript` invocation) and confirm the touched tests fail/error — `note_and_phonology_notes` has no accepted baseline yet (new fixture, both directions), and `citation-and-custom-field` should mismatch on the new column. `Sena3` is untouched at this point, so it should still pass — it only goes stale once the code change in step 2 makes it start emitting `note_en`, which is expected and reviewed there, not a sign anything's wrong now.
2. **Green:** after implementing the code changes, re-run the test suite. The modified/new fixtures — plus `Sena3`, previously untouched — will now produce new `.new` snapshot files since expected output changed.
3. Review the diffs with `testthat::snapshot_review()` (or inspect the `.new` files directly) to confirm the emitted `<note>` XML and extracted `note_seh`/`note_en` columns look correct — including that `Sena3`'s newly-surfaced notes are the expected 6 untyped ones and no `restrictions`-typed text leaked in — then accept with `testthat::snapshot_accept()` — per `AGENTS.md`, snapshots are never auto-accepted.
4. Confirm all other existing snapshots remain unchanged (no unrelated fixture should be affected).
5. **Refactor:** after any cleanup from the refactor step, re-run the full test suite once more to confirm everything is still green.
