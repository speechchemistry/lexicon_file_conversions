# Plan: add the remaining LIFT fields

## Context

The CSV↔LIFT round-trip currently covers four tables (entry, sense, pronunciation, example) and, within them, `lexical-unit`, `citation`, untyped + typed `note`, custom `field`, `morph-type`, `gloss`, `definition`, `grammatical-info/@value`, `pronunciation`/`media`, and `example` with its translation and reference note. Everything else in a real FLEx export is dropped on read and absent on write — [SPEC.md's Not yet specified](../SPEC.md#not-yet-specified) lists it as prose, but nobody has costed it or put it in an order.

This plan is that inventory and that order, derived by tallying every element path and attribute actually present in the checked-in fixtures (`Sena3.lift`, 1462 entries / 1717 senses, plus the five small ones) rather than from the schema alone. Outcome: a sequence of increments, each one a self-contained run of the [`adding-a-lift-field` skill](../.claude/skills/adding-a-lift-field/SKILL.md) (read direction first, its CSV output becomes the write fixture), so the work can stop cleanly after any increment.

**Status: planning only — no code written yet.** Keep this file synced as the [decisions below](#decisions-to-settle) land, per [AGENTS.md's Working Style](../AGENTS.md).

## What is actually left (measured, not guessed)

Counts are from `tests/testthat/fixtures/lift2csv_entry-table/Sena3.lift` unless noted. "max/parent" is what decides column vs. table per [the skill's "Decide where it lives" step](../.claude/skills/adding-a-lift-field/SKILL.md#decide-where-it-lives-a-column-or-a-table-of-its-own).

| LIFT item | Count | max/parent | Shape | Increment |
| --- | --- | --- | --- | --- |
| `entry/@order` | 108 | 1 | column `entry_order` | A1 |
| `entry/@id` (`headword_guid`, ≠ guid) | 1462 | 1 | column, name TBD | A2 |
| `sense/reversal` (`@type` + form) | 5 (in 2 small fixtures) | 2 | **new table** | B1 |
| `entry/etymology` (`@type`, `@source`, form, gloss, `field type=comment/languagenotes`) | 105 | 1 (schema: many) | **new table** | B2 |
| `sense/trait` (`semantic-domain-ddp4` 181, `usage-type` 16) | 197 | 3, names repeat | **new long table** | C1 |
| `sense/grammatical-info/trait` (`inflection-feature`, `type`, `*-slot`, `from-part-of-speech`) | 1078 | 4, names repeat | same long table | C1 |
| `entry/variant` (form + `morph-type`/`environment` traits) | 168 | 8 | **new table** (+ traits via C1) | C2 |
| `entry/relation` (`@type`/`@ref`/`@order` + traits) | 31 | 3 | **new table** (+ traits via C1) | C3 |
| `sense/relation` (`@type`/`@ref`) | 44 | 2 | **new table** (+ traits via C1) | C3 |
| `sense/subsense` (recursive `<sense>`) | 8 | 1 deep | column `parent_sense_guid` on sense table | D1 |
| `header/fields` + `header/ranges` | 11 + 27 | — | verbatim passthrough, not a table | D2 |
| pronunciation `field` (cv-pattern, tone) / `trait`, media `@label` | **0 in any fixture** (declared in headers only) | — | blocked on a real export | D3 |
| `entry/@dateDeleted`, sense/example/pronunciation dates, `annotation`, `illustration`, `variant/pronunciation`, `variant/relation`, `relation/usage`, `reversal/main` | 0 | — | stay in Not yet specified | — |

Two findings that reorder the work:

- **`entry/relation/@ref` targets `entry/@id`, not `@guid`** — all 31 refs resolve against the `headword_guid` form, none against the bare guid. So A2 (`entry/@id`) is a **prerequisite** for C3: emitting relations without it produces dangling refs. (`sense/relation/@ref` targets `sense/@id`, all 44 resolve, so that half is already keyable.)
- **`entry/@id` is fully derived, so A2 is a redundancy question rather than a data-recovery one.** Measured over all 1462 entries: `@id` = headword + (`@order` or `""`) + `"_"` + `@guid`, where headword is the citation form when present (848 entries) else the lexical-unit form (506), and the homograph digit (108 entries) *is* `@order` — identical on all 108. Nothing unexplained, no escaping. Every input is therefore in the entry CSV once A1 lands, and `@id` could be synthesized on write instead of stored.
- **Traits repeat the same `name` on one parent, and `lift.rng` permits it** — `trait-content` carries no `sch:assert` on uniqueness, and real data repeats `semantic-domain-ddp4` (24 senses) and `environment` (4 variants). That rules out flat `trait_<name>` columns at every level and is why C1 comes before C2/C3 rather than each table growing its own trait columns.

## Increments

Each is a separate skill run with its own red/green/refactor commits, SPEC.md update, and snapshot review. Pause between them for a commit ([skill Gotchas](../.claude/skills/adding-a-lift-field/SKILL.md#gotchas)).

### Phase A — entry-table columns (cheap, no new tables)

**A1 · `entry/@order` → `entry_order`.** Warm-up, exactly the shape of `sense_order`. Read in `entry_table()`'s `entry_meta` block (`R/entry_table.R`); add to `meta_columns` in `classify_entry_columns()` (`R/entry_helpers.R`); emit in `entry_table_to_lift()` (`R/csv2lift_entry.R`) alongside the existing `dateCreated`/`dateModified`/`guid` guards, omitted when blank *or absent*, mirroring `attach_senses_to_lift()`'s `order` handling. Refreshes every `entry-table_`, `join-sense-entry-table_` and `csv2lift_` snapshot whose source has `@order`.

**A2 · `entry/@id` → new column.** Same three edits. Emitting `@id` at all is a deliberate revision of [SPEC.md's Entry table](../SPEC.md#entry-table) rule "`id` is never synthesized": storing it verbatim is not synthesis, and C3's relation refs need it to resolve. The column name will contain an underscore, so it needs an exact-match `meta_columns` entry ahead of the custom-field fallback, plus a line in the known-limitation comment.

Because `@id` is derivable (see above), three options — settle before starting, since they differ in output, not just in tidiness:

| | Behaviour | Cost |
| --- | --- | --- |
| **Store verbatim** (recommended) | column carried through unchanged | one redundant column; matches the stance [SPEC.md's Example table](../SPEC.md#example-table) takes on `@source` vs `note[@type="reference"]` — FLEx wrote it twice, so the tool carries both |
| Synthesize on write | no new column | encodes FLEx's headword rule into csv2lift, and needs a writing-system choice the CSV deliberately does not record. A user editing a citation form silently changes every derived id while the relations CSV still holds the old refs — **every ref then dangles** |
| Skip entirely | current behaviour | fine until C3; relation refs would then point at ids no entry in the output carries |

Recommendation is verbatim storage, on the strength of that middle row: it is the only option under which a headword edit leaves refs resolving.

### Phase B — new tables whose data is already in the repo

**B1 · `sense/reversal` → reversal table (`--reversals`).** Sense-parented, positionally keyed: `two_pronunciations_with_audio_and_IPA.lift` has one sense with **two reversals of the same `@type="en"`**, so no `reversal_<type>` column scheme works. Copy the example table wholesale — it is the same shape one level up (`R/example_table.R`, `R/example_helpers.R`, `R/csv2lift_example.R`, `test-example-table_end-to-end.R`), keying rows on document position with `sense_guid` as the surviving FK. Columns: `sense_guid`, `reversal_type`, `reversal_<lang>`; classifier starts strict (no custom-field fallback). Attach after `attach_senses_to_lift()`.

Note the pre-existing coverage hole this closes: `_snaps/csv2lift_end-to-end/note_and_phonology_notes.lift` and `two_pronunciations_with_audio_and_IPA.lift` are approved snapshots holding **zero** `<reversal>` while their sources have 2 and 3 — exactly [the skill's "a new table opens a coverage hole"](../.claude/skills/adding-a-lift-field/SKILL.md#if-it-needs-a-table-of-its-own) case. Both stems need a `_reversals.csv` companion.

**B2 · `entry/etymology` → etymology table (`--etymologies`).** Entry-parented. Max 1 per entry in the data, but FLEx's Entry pane lets a user add more and `lift.rng` wraps it in `zeroOrMore`, so a table (not columns) — same call as `<pronunciation>`. Columns: `entry_id`, `etymology_type`, `etymology_source` (always empty string in Sena3 — carried anyway, both attributes are *required* by `etymology-content`), `etymology_<lang>` (the form), `gloss_<lang>` (10 present, en/pt), and the inner custom fields as type-keyed columns reusing `emit_typed_children()` (`comment`, `languagenotes`; 46 etymologies carry both). Fixture: `Sena3_gloss_initial_b.lift` already has 5 etymologies, so no new export needed; extract a small focused entry per [the skill's third fixture case](../.claude/skills/adding-a-lift-field/SKILL.md#get-a-real-fixture) if the snapshot is unwieldy.

### Phase C — traits, then the two trait-bearing tables

**C1 · a long `traits` table (`--traits`).** The one shape that survives repeated `name`s. One row per trait, document order preserved:

| Column | Meaning |
| --- | --- |
| `entry_id` | FK → entry table (always filled) |
| `sense_guid` | FK → sense table; filled when `owner` is `sense`/`grammatical-info`, blank otherwise |
| `owner` | `sense`, `grammatical-info`, `variant`, or `relation` |
| `owner_index` | 1-based position of the owner among that parent's like-owner siblings; blank for `sense`/`grammatical-info` (at most one each) |
| `trait_name`, `trait_value` | the pair, verbatim |

Scope deliberately excludes entry-level traits: `morph-type` keeps its existing dedicated `morph_type` column (a public contract already in every snapshot), and no other entry-level trait occurs in any fixture, so it stays in Not yet specified rather than being speculatively covered. Read xpath at sense level is `./trait`; at gram-info level `./grammatical-info/trait`.

Implementable in two halves so the first is small: **C1a** `owner ∈ {sense, grammatical-info}` (no `owner_index` needed — ship the column blank), which covers 1275 of the 1275 traits present today; **C1b** extends it to `variant`/`relation` owners as part of C2/C3, which is where `owner_index` first earns its keep. Attach pass runs **last** in `scripts/csv2lift.R` (after senses, variants and relations exist); an `owner_index` matching no owner row is a hard error, per [SPEC.md's Structural rules](../SPEC.md#structural-rules-csv2lift-direction).

**C2 · `entry/variant` → variant table (`--variants`).** Entry-parented, positionally keyed (up to 8 per entry, at most one `<form>` each, always `lang="seh"` in Sena3). Columns: `entry_id`, `variant_<lang>`. Its `morph-type` and `environment` traits ride in C1's traits table with `owner = "variant"` — that is what makes the 4 variants carrying 2–3 `environment` traits representable without inventing a delimiter or dropping data. Schema also allows `variant/@ref`, `variant/field`, `variant/pronunciation`, `variant/relation`; none occur, all stay unimplemented and documented.

**C3 · `entry/relation` + `sense/relation` → relation tables.** Needs A2 done. Two tables, one per level, matching the codebase's one-column-per-level grid: `--entry-relations` (`entry_id`, `relation_type`, `relation_ref`, `relation_order`) and `--sense-relations` (`sense_guid`, `relation_type`, `relation_ref`). Both positionally keyed. Entry-relation traits (`is-primary`, `complex-form-type`, `variant-type`, one relation repeating a name) ride in C1's traits table with `owner = "relation"`. `relation_order` is copied verbatim, never regenerated. `relation/usage` and `variant/relation` do not occur; leave unimplemented.

If two tables/flags for one element feels heavy, the alternative is one `relations` table with both `entry_id` and `sense_guid` and exactly one filled — cheaper CLI, but the first table in the repo that spans two levels. Recommend the two-table version; flag it in the commit so it is a visible choice.

### Phase D — structural and blocked items

**D1 · `sense/subsense` → `parent_sense_guid` on the sense table.** 8 in Sena3, one level deep, each with its own `@id`. Add a `parent_sense_guid` column (blank = a direct sense of the entry); switch `sense_table()`'s axis from `./sense` to a recursive walk; in `attach_senses_to_lift()`, emit parentless rows first, then rows whose parent exists, as `<subsense>` (the tag differs from `<sense>`). Then widen the FK lookups that currently say `.//sense[@id=…]` to match `<subsense>` too, and `example_table()`'s `.//entry/sense/example` axis to include the 1 subsense example — which is what retires three separate Not-yet-specified entries at once. Do this **after** Phase C, since every sense-parented table (examples, reversals, traits) inherits the widened lookup.

**D2 · `header` passthrough.** `<header>/<fields>` (11 custom-field declarations with English descriptions) and `<header>/<ranges>` (27 `href`s into an external `.lift-ranges` file) are per-document metadata, not per-entry data, and a CSV round-trip of them buys little. Proposal: a `--header-from <lift-file>` flag on `scripts/csv2lift.R` that copies the `<header>` element verbatim into the output. Whether this is needed at all depends on whether FLEx will import a header-less LIFT cleanly — see [Decisions](#decisions-to-settle).

**D3 · pronunciation-level `field`/`trait`, media `@label`.** Genuinely blocked: zero occurrences in any fixture (Sena3 has no `<pronunciation>` at all; the two small pronunciation fixtures carry only forms and media). `cv-pattern` and `tone` are *declared* in every header, so the data exists in other projects. Per [the skill's fixture rule](../.claude/skills/adding-a-lift-field/SKILL.md#get-a-real-fixture), ask for a real export rather than hand-writing one; until then this stays in Not yet specified.

## Decisions to settle

Recommendations are in the increments above; these are the four points where a different answer changes the work. Each is answerable when its increment starts — none of them block Phase A.

1. **A2: store `entry/@id`, derive it, or skip it** — see the table in A2; recommendation is store. If stored, the name needs settling too: `entry_lift_id` is the suggestion (descriptive, and `entry_id` is taken by the guid). Renaming later is expensive: [the skill spells out](../.claude/skills/adding-a-lift-field/SKILL.md#documentation) that a column name is a public contract touching reader, classifier, every fixture header, three snapshot directories and SPEC.md.
2. **C1's table shape** — one unified long `traits` table (recommended: one flag, one SPEC section, one test file, and future trait kinds need no new code) versus per-level trait tables (`--sense-traits`, `--variant-traits`, …: no cross-CSV positional coupling, but 3–4 more tables). The unified version's only real cost is `owner_index` pointing at another CSV's row position, which a fail-fast lookup makes loud rather than silent.
3. **C3 one relations table or two** — see C3.
4. **D2 at all** — does FLEx need `<header>` to import csv2lift output, and is import-into-FLEx even a goal for this tool? If the answer is "not a goal", D2 drops off the list entirely.

## Verification

Per increment, in this order:

1. `Rscript -e 'devtools::test(filter = "<table>-table_end-to-end")'` — read direction. A brand-new fixture auto-creates its snapshot with a WARN, so **read the file**; that absence is the red.
2. Verify the new column/table contents against the tallies in the inventory table above with a throwaway `python3 -c` over the `.new` CSV (counts must match: 108 `entry_order`, 105 etymologies, 197 sense traits, 1078 gram-info traits, 168 variants, 31 + 44 relations, 5 reversals). Re-derive any figure before it goes into SPEC.md.
3. `Rscript -e 'testthat::snapshot_accept("<name>-table_end-to-end/")'` (trailing slash required) and the same for `join-sense-entry-table_end-to-end/` where the level reaches that view; re-run to confirm the accept took.
4. Refresh every `tests/testthat/fixtures/csv2lift/*_<level>.csv` whose source `.lift` contains the new field by re-copying reader output — and leave the rest strictly alone, since their byte-identical snapshots prove the writer still tolerates the columns being absent.
5. `Rscript -e 'devtools::test(filter = "csv2lift_end-to-end")'` — write direction; review the `.lift` diff before accepting.
6. Full `Rscript -e 'devtools::test()'` green, then SPEC.md updated in the same change (column row or new section, classification algorithm, canonical child order, CLI shape list, and deletion of the Not-yet-specified entries the increment retires), plus a README example for each new flag.

End-to-end round-trip spot check after each new table, using the largest fixture that exercises it:

```bash
Rscript scripts/lift2csv_entry-table.R <fixture>.lift > /tmp/e.csv
Rscript scripts/lift2csv_<new>-table.R <fixture>.lift > /tmp/n.csv
Rscript scripts/csv2lift.R /tmp/e.csv --<new> /tmp/n.csv > /tmp/out.lift
# then diff element/attribute tallies between <fixture>.lift and /tmp/out.lift
```

## Files touched (pattern, per increment)

A column increment touches the level's four files plus docs: `R/<level>_table.R` (extract + `pivot_wider` + `left_join`), `R/<level>_helpers.R` (`classify_<level>_columns()`), `R/csv2lift_<level>.R` (emit block, positioned to match SPEC.md's canonical child order), and `SPEC.md`.

A new table adds a fifth column to that grid — `R/<name>_table.R`, `R/<name>_helpers.R`, `R/csv2lift_<name>.R`, `scripts/lift2csv_<name>-table.R`, a flag in `scripts/csv2lift.R`, `tests/testthat/test-<name>-table_end-to-end.R`, a curated `tests/testthat/fixtures/lift2csv_<name>-table/` directory, the `*_<name>.csv` glob in `tests/testthat/test-csv2lift_end-to-end.R`, its own SPEC.md section, and a README example.
