# Plan: add the remaining LIFT fields

## Context

The CSV↔LIFT round-trip currently covers four tables (entry, sense, pronunciation, example) and, within them, `lexical-unit`, `citation`, untyped + typed `note`, custom `field`, `morph-type`, `gloss`, `definition`, `grammatical-info/@value`, `pronunciation`/`media`, and `example` with its translation and reference note. Everything else in a real FLEx export is dropped on read and absent on write — [SPEC.md's Not yet specified](../SPEC.md#not-yet-specified) lists it as prose, but nobody has costed it or put it in an order.

This plan is that inventory and that order, derived by tallying every element path and attribute actually present in the checked-in fixtures (`sena3.lift`, 1462 entries / 1717 senses, plus the five small ones) rather than from the schema alone. Outcome: a sequence of increments, each one a self-contained run of the [`adding-a-lift-field` skill](../.claude/skills/adding-a-lift-field/SKILL.md) (read direction first, its CSV output becomes the write fixture), so the work can stop cleanly after any increment. The one exception is [Phase T](#phase-t--the-table-folder-convention), which is CLI infrastructure rather than a field and so is not a skill run.

**Status: A1, A2, T1, T2 and T3 done — Phase T complete. Next: Phase B (B1).** Keep this file synced as remaining [decisions below](#decisions-to-settle) land, per [AGENTS.md's Working Style](../AGENTS.md).

Companion plan: [redundant-columns-and-entry-id.md](old/redundant-columns-and-entry-id.md) revisits whether carrying redundant/derivable columns is a good idea at all, and settles A2 and part of D2 against the FLEx LIFT documentation. A2, C3, D2 and [decisions 1 and 4](#decisions-to-settle) below have been updated from its findings.

## What is actually left (measured, not guessed)

Counts are from `tests/testthat/fixtures/lift2csv_entry-table/sena3.lift` unless noted. "max/parent" is what decides column vs. table per [the skill's "Decide where it lives" step](../.claude/skills/adding-a-lift-field/SKILL.md#decide-where-it-lives-a-column-or-a-table-of-its-own).

| LIFT item                                                                                                                                                             | Count                                           | max/parent       | Shape                                     | Increment |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- | ---------------- | ----------------------------------------- | --------- |
| `entry/@order`                                                                                                                                                        | 108                                             | 1                | column `entry_order`                      | A1        |
| `entry/@id` (`headword_guid`, ≠ guid)                                                                                                                                 | 1462                                            | 1                | column, name TBD                          | A2        |
| `sense/reversal` (`@type` + form)                                                                                                                                     | 5 (in 2 small fixtures)                         | 2                | **new table**                             | B1        |
| `entry/etymology` (`@type`, `@source`, form, gloss, `field type=comment/languagenotes`)                                                                               | 105                                             | 1 (schema: many) | **new table**                             | B2        |
| `sense/trait` (`semantic-domain-ddp4` 181, `usage-type` 16)                                                                                                           | 197                                             | 3, names repeat  | **new long table**                        | C1        |
| `sense/grammatical-info/trait` (`inflection-feature`, `type`, `*-slot`, `from-part-of-speech`)                                                                        | 1078                                            | 4, names repeat  | same long table                           | C1        |
| `entry/variant` (form + `morph-type`/`environment` traits)                                                                                                            | 168                                             | 8                | **new table** (+ traits via C1)           | C2        |
| `entry/relation` (`@type`/`@ref`/`@order` + traits)                                                                                                                   | 31                                              | 3                | **new table** (+ traits via C1)           | C3        |
| `sense/relation` (`@type`/`@ref`)                                                                                                                                     | 44                                              | 2                | **new table** (+ traits via C1)           | C3        |
| `sense/subsense` (recursive `<sense>`)                                                                                                                                | 8                                               | 1 deep           | column `parent_sense_guid` on sense table | D1        |
| `header/fields` + `header/ranges`                                                                                                                                     | 11 + 27                                         | —                | verbatim passthrough, not a table         | D2        |
| pronunciation `field` (cv-pattern, tone) / `trait`, media `@label`                                                                                                    | **0 in any fixture** (declared in headers only) | —                | blocked on a real export                  | D3        |
| `entry/@dateDeleted`, sense/example/pronunciation dates, `annotation`, `illustration`, `variant/pronunciation`, `variant/relation`, `relation/usage`, `reversal/main` | 0                                               | —                | stay in Not yet specified                 | —         |

Two findings that reorder the work:

- **`entry/relation/@ref` targets `entry/@id`, not `@guid`** — all 31 refs resolve against the `headword_guid` form, none against the bare guid. So A2 (`entry/@id`) is a **prerequisite** for C3: without an `@id` there is nothing for a ref to point at. (`sense/relation/@ref` targets `sense/@id`, all 44 resolve, so that half is already keyable.) The FLEx documentation states this as one rule for both levels — "References to entries and senses within the LIFT file use the id string" — which holds at sense level because "the sense id has always been a guid" (verified: 1717/1717 guid-shaped).
- **`entry/@id` is fully derived, so A2 is a redundancy question rather than a data-recovery one.** Measured over all 1462 entries: `@id` = headword + (`@order` or `""`) + `"_"` + `@guid`, where headword is the citation form when present (848 entries) else the lexical-unit form (506), and the homograph digit (108 entries) *is* `@order` — identical on all 108. Nothing unexplained, no escaping. Every input is therefore in the entry CSV once A1 lands, and `@id` could be synthesized on write instead of stored. **The FLEx documentation settles which to do** — see [redundant-columns-and-entry-id.md](old/redundant-columns-and-entry-id.md).
- **Traits repeat the same `name` on one parent, and `lift.rng` permits it** — `trait-content` carries no `sch:assert` on uniqueness, and real data repeats `semantic-domain-ddp4` (24 senses) and `environment` (4 variants). That rules out flat `trait_<name>` columns at every level and is why C1 comes before C2/C3 rather than each table growing its own trait columns.

## Increments

Each is a separate skill run with its own red/green/refactor commits, SPEC.md update, and snapshot review. Pause between them for a commit ([skill Gotchas](../.claude/skills/adding-a-lift-field/SKILL.md#gotchas)).

### Phase A — entry-table columns (cheap, no new tables)

**A1 · `entry/@order` → `entry_order`. Done.** Warm-up, exactly the shape of `sense_order`. Read in `entry_table()`'s `entry_meta` block (`R/entry_table.R`); added to `meta_columns` in `classify_entry_columns()` (`R/entry_helpers.R`); emitted in `entry_table_to_lift()` (`R/csv2lift_entry.R`) alongside the existing `dateCreated`/`dateModified`/`guid` guards, omitted when blank *or absent*, mirroring `attach_senses_to_lift()`'s `order` handling. Refreshed every `entry-table_` and `join-sense-entry-table_` snapshot (the column is new for all of them), plus the two `csv2lift_` fixtures/snapshots whose source entries actually carry `@order` (`zhi-note-and-phonology-notes`, `sena3-note-trailing-whitespace`); the other `csv2lift_` fixtures' selected rows carry no `@order` so nothing round-trips there. Confirmed 108/1462 `sena3.lift` entries carry `@order`, matching the plan's tally, and that it equals the homograph digit in `@id`. SPEC.md's Entry Table, Sense Table (cross-reference) and Not Yet Specified sections updated; no README change needed (README doesn't enumerate columns).

**A2 · `entry/@id` → `entry_lift_id`. Done.** Same three edits. Read in `entry_table()`'s `entry_meta` block, right after `entry_id`; added as an exact-match entry in `meta_columns` (ahead of the custom-field fallback, as an exact match already is); emitted as `id` in `entry_table_to_lift()`, positioned between `dateModified` and `guid` to match FLEx's own attribute order, guarded on non-blank exactly like the other entry attributes. Emitting `@id` at all is a deliberate revision of [SPEC.md's Entry table](../SPEC.md#entry-table) rule "`id` is never synthesized": storing it verbatim is not synthesis, and C3's relation refs need it to resolve.

Refreshed all 12 non-empty `entry-table_`/`join-sense-entry-table_`/`csv2lift_` fixtures and snapshots — every entry in every fixture carries `@id`, so this one lands everywhere (unlike A1's `entry_order`, which only touched 2 of the 12 `csv2lift_` fixtures). Confirmed 1462/1462 unique in `sena3.lift`, and that `entry_lift_id` = headword + (`@order` or `""`) + `"_"` + `@guid` for every sampled row (headword = citation form when present, else lexical-unit form), matching the plan's derivation. The write-side uniqueness check and the blank/absent-column backward-compatibility path were both verified by hand against throwaway CSVs (no fixture covers either, per [the skill's Gotchas](../.claude/skills/adding-a-lift-field/SKILL.md#gotchas)) — a duplicate `entry_lift_id` is a hard error, and an entry CSV with no `entry_lift_id` column still converts, producing `guid` but no `id` exactly as before. SPEC.md's Entry Table, Column Classification (known-limitation bullet), Structural Rules, and Not Yet Specified sections updated — the old `entry/@id` limitation bullet (with its LT-21075 hazard note) moved into Entry Table's prose now that the field is implemented.

Because `@id` is derivable (see above), there were three options. **Settled: store verbatim**, on the FLEx documentation rather than on a judgement call — reasoning and quotes in [redundant-columns-and-entry-id.md](old/redundant-columns-and-entry-id.md).

|                                | Behaviour                        | Cost                                                                                                                                                                                                                                              |
| ------------------------------ | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Store verbatim** (settled)   | column carried through unchanged | one derivable column. The doc makes `@id` an opaque within-file handle — "any text as long as it is unique in the LIFT file", and "any non-guid id will be converted to a guid during import" — so there is no semantic content to keep in sync   |
| Synthesize on write            | no new column                    | regenerates a string whose content the consumer discards, encodes a WeSay convention ("normally… the lexeme form and guid") into csv2lift, needs a writing-system choice the CSV does not record, and builds the LT-21075 hazard in by construction |
| Skip entirely                  | current behaviour                | fine until C3; relation refs would then point at ids no entry in the output carries                                                                                                                                                                |

Because `@id` is only required to be unique, the write-side guard is a **uniqueness check** across the `entry_lift_id` column — not a check that it still matches the headword or carries the guid as a suffix, both of which the doc treats as convention rather than rule. A duplicate is a hard error, per [SPEC.md's Structural rules](../SPEC.md#structural-rules-csv2lift-direction).

### Phase T — the table folder convention

Out of alphabetical order deliberately: **Phase T runs before B1/B2**, and is the only phase here that changes no data model, no CSV column and no snapshot content.

**T1 · Done.** Built as designed below, with three deviations from the draft, all narrower/simpler than planned: (1) `entries` got its own `--entries` flag in the registry rather than being handled purely as a positional special-case — the leading-bare-positional interception (`raw_argv[1]` not starting with `-`) still runs first and takes priority, so every existing invocation keeps working unchanged, but `--entries` is also now a documented, registry-uniform way to supply it, which `--tables`'s override rule needed anyway. (2) The single planned `lift_table_paths()` helper became three small ones in `R/table_registry.R` — `table_csv_path()`, `scoped_csvs()`, `table_name_from_csv()` — plus `discover_tables()`, which does the discovery-plus-unknown-CSV-check together; splitting them avoided one function doing regex-fragile name parsing and validation at once (`scoped_csvs()`/`table_name_from_csv()` use `startsWith()`/`substring()` rather than regex on a prefix, so a fixture stem containing regex metacharacters can't misparse). (3) The entry table's mandatory-supply rule ended up as "positional, `--entries`, *or* discovery" — a strict superset of the plan's "positional or discovered" — since once `--entries` existed alongside the other per-table flags there was no reason to special-case it out of the override precedence.

All 12 `csv2lift_end-to-end` snapshots came out byte-identical after the refactor (verified before writing the new discovery test file). `test-csv2lift_table-discovery.R` covers the folder-vs-flat equivalence, the three error paths, and the override case — the override and examples-without-senses/unrecognised-CSV fixtures are built at test time under `withr::local_tempdir()` rather than checked in, since (per [Testing Approach](../AGENTS.md#testing-approach)) only the folder-shaped positive case (`tests/testthat/fixtures/csv2lift-folder/sena3-gloss-initial-b/`) earns a place as a static fixture; the error shapes don't. `scripts/lift2csv.R` (new) and `SPEC.md`/`README.md` updated as planned.

**T1 · a table registry and a `--tables <prefix>` discovery flag.** Motivation: the four tables of today become up to ten by the end of Phase D (`entries`, `senses`, `pronunciations`, `examples`, `reversals`, `etymologies`, `traits`, `variants`, `entry-relations`, `sense-relations`). Two costs grow linearly with that count and neither is about the data model:

- **The CLI is unusable at ten flags.** Ten `Rscript scripts/lift2csv_*.R` invocations to dump one export, then a ten-flag `csv2lift.R` call to rebuild it.
- **Each new table is edited into three unrelated places.** A flag block in `scripts/csv2lift.R`, an attach call whose *position in the file* silently encodes canonical child order, and a line in `tests/testthat/test-csv2lift_end-to-end.R`'s discovery loop — plus a README example and a [SPEC.md CLI shape](../SPEC.md#csv2lift-cli-shape) bullet. That is 5 of the 9 items in [Files touched](#files-touched-pattern-per-increment), and none of them is the interesting part of a table.

The convention already exists; it just isn't in the tool. `test-csv2lift_end-to-end.R` discovers its fixtures as `<stem>_entries.csv` / `_senses.csv` / `_pronunciations.csv` / `_examples.csv` and builds the flag list from whichever files exist. T1 codifies proven practice rather than inventing a scheme.

#### The registry

One table of metadata, one row per table, in a new `R/table_registry.R`. Every field is something currently implicit in the position or wording of code elsewhere:

| Field           | Replaces                                                                                                                             |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `name`          | the CSV filename suffix (`senses` → `<prefix>_senses.csv`), currently duplicated in the test loop and the fixture filenames           |
| `flag`          | the `add_argument()` block in `scripts/csv2lift.R`                                                                                    |
| `read_fn`       | the read-direction entry point (`sense_table()`, `example_table()`, …), currently reached only via a per-table `scripts/lift2csv_*.R` |
| `attach_fn`     | `attach_senses_to_lift()` etc.; `entries` is special — `entry_table_to_lift()` *creates* the document rather than attaching to it      |
| `attach_order`  | the call order in `scripts/csv2lift.R:40-56`, which is load-bearing for canonical child order and documented only in a comment        |
| `requires`      | the hand-written `--examples requires --senses` guard at `scripts/csv2lift.R:23-25`                                                    |
| `fk`            | the FK column (`entry_id`, `sense_guid`), currently stated only in SPEC.md prose                                                       |

C1 needs `attach_order` to be explicit anyway — its traits table must attach **last**, after variants and relations exist ([C1](#phase-c--traits-then-the-two-trait-bearing-tables)) — so the registry is where that constraint stops being a comment about call order and becomes data. As built, `attach_order` is not a separate field: registry *row order* is attach order, which is one less thing to keep consistent.

**`fk` is documentation-only as built** — nothing reads it, because each table's FK resolution lives inside its own `attach_*_to_lift()`. Two consequences: C1's traits table needs no registry change despite having two FKs (`entry_id` *and* `sense_guid`), and the field is a mild smell that should either earn its keep in a later increment or be deleted rather than left as decoration.

The join view (`lift2csv_join-sense-entry-table.R`) is **not** a registry row: it is a derived view, csv2lift does not accept it, and it must not appear in a table folder.

#### The discovery rule

One rule, one code path: `--tables <prefix>` finds `<prefix>_<name>.csv` for each registry row, except that **a prefix ending in the path separator means bare filenames**.

```
--tables exports/Sena3/                            → exports/Sena3/entries.csv, senses.csv, etymologies.csv, …
--tables fixtures/csv2lift/sena3-gloss-initial-b   → …_entries.csv, …_senses.csv, …
```

The trailing-slash case is a user's per-export folder; the no-slash case is the flat many-stems-in-one-directory layout `tests/testthat/fixtures/csv2lift/` already uses. Because both fall out of the same `lift_table_paths(prefix)` helper, the test suite exercises exactly the path a user takes.

Rules to build in from the start:

- **Explicit flags stay, and win.** They are a published contract in README and SPEC.md, and they are the escape hatch when a user's files aren't named to convention. `--tables dir/ --senses other.csv` uses `other.csv` for senses and discovery for the rest.
- **An unrecognised `*.csv` in scope is a hard error.** This is the one genuine regression versus explicit flags: a typo'd `sense.csv` silently drops a whole table, where a typo'd `--senses` path errors. Erroring on any in-scope CSV whose name matches no registry row closes it, and matches [SPEC.md's Structural rules](../SPEC.md#structural-rules-csv2lift-direction). "In scope" means, for a folder prefix, every `*.csv` in the folder; for a flat prefix, every `<prefix>_*.csv`.
- **The `entries_csv` positional becomes optional, but an entry table is still mandatory.** Exactly one of the positional or a discovered `entries.csv` must be present; neither is a usage error, and so is a `--tables` folder with no `entries.csv`. Every other table stays optional-if-absent. (`argparser` treats a bare positional as required, so this is a real change to the `add_argument()` call, not just a validation tweak — and `csv2lift.R --tables dir/` with no positional has to be a supported invocation for the round-trip check in [Verification](#verification) to be a two-liner.)
- **`requires` is still enforced.** A folder will usually have both `senses.csv` and `examples.csv` or neither, but a folder with examples and no senses must still fail as a usage error, not as a per-row "sense_guid not found".

#### Read side, same registry

`Rscript scripts/lift2csv.R <file>.lift --tables out/` loops the registry and writes every table in one pass. This is the larger ergonomic win — it is what makes the round-trip spot check in [Verification](#verification) a two-line command instead of one invocation per table. Keep the existing per-table `scripts/lift2csv_<name>-table.R` scripts unchanged (they are the tested public surface, and each is a one-liner over its `read_fn`); the umbrella is additive.

#### Verification (differs from a field increment)

The point of T1 is that **nothing in `_snaps/` changes**. That makes for an unusually clean TDD cycle:

1. **Red:** switch `test-csv2lift_end-to-end.R`'s loop from per-table flags to a single `--tables file.path(fixture_dir, stem)` argument. All 12 stems fail, because `--tables` does not exist yet.
2. **Green:** registry + `lift_table_paths()` + the flag. All 12 `csv2lift_end-to-end` snapshots must come out **byte-identical** — same CSVs in, same LIFT out. A single changed snapshot means the refactor changed behaviour and is wrong.
3. New `test-csv2lift_table-discovery.R` covering the three error paths and the override, following the exit-status-plus-stderr-grep pattern of `test-copy-lift-entries_end-to-end.R`'s `copy-lift-entries_missing-guid_errors` (the snapshot helper only captures stdout, so error paths are asserted, not snapshotted): unrecognised CSV in scope, missing `entries.csv`, examples-without-senses under `--tables`, and an explicit flag overriding a discovered file.
4. A folder-shaped fixture for the trailing-slash case — one stem copied into `tests/testthat/fixtures/csv2lift-folder/sena3-gloss-initial-b/{entries,senses,examples}.csv` — so both halves of the discovery rule are covered, not just the flat one the existing fixtures happen to use.
5. `Rscript -e 'devtools::test()'` green, then SPEC.md's [csv2lift CLI shape](../SPEC.md#csv2lift-cli-shape) rewritten around the registry and the discovery rule, and a README example replacing the multi-flag ones (keep one flag example, since flags remain supported).

Files touched: `R/table_registry.R` (new), `scripts/csv2lift.R` (flags and attach loop both driven from the registry), `scripts/lift2csv.R` (new umbrella), `tests/testthat/test-csv2lift_end-to-end.R`, `tests/testthat/test-csv2lift_table-discovery.R` (new), `tests/testthat/fixtures/csv2lift-folder/` (new), `SPEC.md`, `README.md`. No `R/<level>_table.R`, `R/<level>_helpers.R` or `R/csv2lift_<level>.R` file is touched — if one is, the increment has grown beyond its scope.

**Two defects T1 shipped, both fixed by T2 below:**

- **`scripts/lift2csv.R` has no test.** The verification list above did not include one and the implementation followed it, so the new umbrella is the only script in `scripts/` with zero coverage. This gets worse per increment, not better: registering a table in the registry silently grows the umbrella's output, so a table could be written under the wrong filename, or wrongly skipped by the empty-table rule, with nothing failing. The five per-table `lift2csv_<name>-table.R` scripts are all snapshot-tested; this one must be too.
- **A fixture stem that is a prefix of another stem breaks flat discovery.** `scoped_csvs()` scopes a flat prefix by `startsWith(name, "<stem>_")`, so a longer stem sharing that prefix is pulled into the shorter one's scope and then trips the unrecognised-CSV guard. Demonstrated with a throwaway directory: with `plant_entries.csv` and `plant_extra_entries.csv` present, `--tables <dir>/plant` dies with `Unrecognised CSV(s) … extra_entries`. No current stem collides so the suite is green, but B1 and B2 both add fixture stems, and the failure would read as a discovery bug rather than a naming clash. **Until T2 lands, a new fixture stem must not be a prefix of an existing one.**

#### T2 · drop flat mode, folder-only discovery

**Done.** T1 shipped two discovery modes because the fixtures were already laid out flat and moving 34 files was out of scope. Keeping both is the wrong trade: flat mode exists to serve one directory's historical layout, and it is the source of most of T1's remaining complexity and both defects above. T2 deletes it.

Built as designed below. The two invariants both held: `csv2lift_end-to-end` snapshots came out byte-identical (`FAIL 0 | WARN 0`, and every approved file's checksum unchanged), and the `sena3-gloss-initial-b` fold-in was git-detected as three renames rather than delete+add. `table_dir()` also normalizes a trailing slash away (`sub("/+$", "", dir)`) rather than merely tolerating it, so `--tables dir` and `--tables dir/` are identical, including in error messages — replacing the dropped folder-vs-flat equivalence test with a trailing-slash-tolerance one in `test-csv2lift_table-discovery.R`. The missing `lift2csv.R` coverage landed as `test-lift2csv_end-to-end.R`, covering the two fixtures the plan named (with vs. without pronunciations) plus a third (the empty lexicon, confirming `entries.csv` is still written when every table is empty). One live-doc fix found and applied beyond the plan's file list: `.claude/skills/adding-a-lift-field/SKILL.md` still described the flat `_entries.csv` suffix convention as the write-fixture procedure — corrected to the directory form. Its "CLI flag" / "attach-call order in `scripts/csv2lift.R`" language predates the registry (a T1-era staleness, not a T2 one) and is unfixed — worth a pass before B1.

The two modes, concretely — 13 exports either way:

```
flat    tests/testthat/fixtures/csv2lift/zhi-note-and-phonology-notes_entries.csv
        tests/testthat/fixtures/csv2lift/zhi-note-and-phonology-notes_senses.csv
        → --tables tests/testthat/fixtures/csv2lift/zhi-note-and-phonology-notes

folder  tests/testthat/fixtures/csv2lift/zhi-note-and-phonology-notes/entries.csv
        tests/testthat/fixtures/csv2lift/zhi-note-and-phonology-notes/senses.csv
        → --tables tests/testthat/fixtures/csv2lift/zhi-note-and-phonology-notes
```

What dropping flat mode buys:

- **The CLI contract loses a wart.** `--tables <dir>` becomes just a directory, with no rule that `foo` and `foo/` mean different things. Trailing-slash-significance is invisible in a shell whose tab-completion adds slashes unpredictably, and is exactly the sort of rule that produces a baffling error much later.
- **Four helpers become two.** `is_folder_prefix()` and `table_name_from_csv()` disappear outright (a table's name simply *is* its basename sans extension); `table_csv_path()` and `scoped_csvs()` each collapse from a two-branch function to one line.
- **The prefix-collision defect above cannot occur.** No stems means no stem can prefix another.
- **Filenames stop growing with the table count.** By the end of Phase D flat mode would be producing `zhi-note-and-phonology-notes_entry-relations.csv`; folder mode produces `entry-relations.csv`.
- **`_reversals.csv`-style companions become `reversals.csv` inside the export's own directory**, which is what makes B1's coverage-hole fix a plain file drop (see [B1](#phase-b--new-tables-whose-data-is-already-in-the-repo)).

**No capability is lost.** The explicit per-table flags (`--entries`, `--senses`, …) stay, and they — not flat mode — are the escape hatch for files not named to convention. Flat mode is a filesystem-organisation preference, not a property of the data.

**Table-name convention, settled here** since T2 makes the name purely a filename: **kebab-case, plural nouns** — `entries`, `senses`, `entry-relations`, `sense-relations`. One string serves as both the CLI flag (`--entry-relations`, matching universal flag convention) and the filename, so there is nothing to transform between the two surfaces. Folder-only removes the structural half of the argument (with no `<stem>_` joint, `_` is no longer doing delimiter work), leaving the flag-matches-filename half, which still decides it. Do **not** invert to `relations-entry`/`relations-sense` merely so the pair sorts adjacently in a listing — it reads wrong as a flag. This settles the naming half of [C3](#phase-c--traits-then-the-two-trait-bearing-tables).

Work: `git mv` the 34 CSVs into 13 directories; fold `tests/testthat/fixtures/csv2lift-folder/` back into `fixtures/csv2lift/` as just another export (the directory stops being a special case and disappears); rewrite `test-csv2lift_end-to-end.R`'s loop to iterate directories instead of globbing `_entries.csv`; drop the now-meaningless folder-vs-flat equivalence test from `test-csv2lift_table-discovery.R` and keep the rest; simplify the four helpers in `R/table_registry.R`; update `SPEC.md` and `README.md`.

Verification: **every `csv2lift_end-to-end` snapshot must again come out byte-identical** — snapshot names derive from the stem, which becomes the directory name, so nothing in `_snaps/` moves or changes. Plus the missing coverage from T1: a snapshot test for `scripts/lift2csv.R` asserting **the set of filenames it writes** for two fixtures (one with pronunciations, one without, so the skip-empty-table rule is exercised in both directions) and byte-comparing each written CSV against the corresponding per-table script's output — that pins the naming rule and the skip rule without duplicating any table's content snapshots.

**T2 keeps every fixture name exactly as it is.** The names are being normalised, but in [T3](#t3--normalise-fixture-names-to-kebab-case) as a separate commit — a restructure and a rename must not share a diff, since each has its own single verifiable invariant and mixing them means a failure tells you nothing about which change caused it.

#### T3 · normalise fixture names to kebab-case

**Done.** Fixture names were inconsistent in case (`Sena3_` vs `sena3_`, `IPA`), in separator (`citation-and-custom-field` vs `note_and_phonology_notes`), and in whether they carried their source project at all (10 of 15 didn't).

Built as designed below. Executed as a scripted, exact-path-segment rename (directory name or file stem matched in full, never a substring) rather than a global find/replace — that made the longest-name-first ordering a belt-and-braces precaution rather than a correctness requirement, since exact-segment matching can't confuse `Sena3` with `Sena3_gloss_initial_b` regardless of order. `git mv` recorded all 96 files as pure renames; the checksum multiset under `tests/testthat/fixtures/` and `tests/testthat/_snaps/` (content only, not paths) was byte-identical before and after, confirmed twice — once right after the renames, again after the reference updates below. `FAIL 0 | WARN 0` on the full suite, both times.

**One live reference not on the plan's list, found the hard way:** `test-lift2csv_end-to-end.R` (added in T2, after this plan's "4 test files" tally was written) also hardcoded three fixture names and wasn't caught by the pre-rename grep — it surfaced as 4 real `FAIL`s (a `readLines()` on a path that no longer existed) on the first post-rename test run, not silently. Fixed alongside the planned four. Lesson for the next rename-shaped increment: re-grep for hardcoded names *after* the file move, not only from a list assembled before it, since intervening increments add files the earlier tally couldn't have known about.

The `zhi` prefix (ISO 639-3 for Zhire) and lowercased `sena3` landed exactly as mapped below; `lela-teli-empty-lexicon` was untouched, as expected. `SPEC.md`, `README.md`, `.claude/skills/adding-a-lift-field/SKILL.md`, and this plan's own forward-looking references (Phase B onward) were updated to the new names; this plan's historical narrative for already-completed increments (T1, T2, and this section's own before/after map and hazard note) intentionally keeps the old names where they describe what was true *at the time*, per [AGENTS.md's point-in-time-record treatment of plans](../AGENTS.md#markdown-conventions).

**Scope is bigger than a fixture-directory rename, which is why this is its own increment.** These names are not just csv2lift export directories — the same name identifies a `.lift` input in up to 5 `lift2csv_*` fixture families and an approved snapshot in up to 6 `_snaps/` directories. Measured: **14 of 15 names change, touching 96 files** (`sena3_single_entry_plant` alone appears in 13). `lela-teli-empty-lexicon` is already conformant and keeps its 10 files untouched.

That makes it **all-or-nothing per name**. Renaming only the csv2lift export directories would leave `csv2lift/sena3-single-entry-plant/` derived from `lift2csv_entry-table/sena3_single_entry_plant.lift` — a worse inconsistency than the one being fixed.

**Rule: lowercase kebab-case, `<source>-<what-it-tests>`.** One rule for every filesystem name in the repo, matching [T2's kebab table filenames](#t2--drop-flat-mode-folder-only-discovery), so a path reads uniformly end to end (`sena3-gloss-initial-b/entry-relations.csv`). The `<source>` prefixes are deliberately not all the same *kind* of identifier — `sena3` is a FLEx project name, `zhi` is the ISO 639-3 code for Zhire, `lela-teli` is a project name — and that is accepted: what the prefix has to do is make provenance visible, not be drawn from one registry.

| current                                          | new                                              |
| ------------------------------------------------ | ------------------------------------------------ |
| `Sena3`                                          | `sena3`                                          |
| `Sena3_gloss_initial_b`                           | `sena3-gloss-initial-b`                           |
| `citation-and-custom-field`                       | `sena3-citation-and-custom-field`                 |
| `sena3_entry_and_sense_typed_notes`               | `sena3-entry-and-sense-typed-notes`               |
| `sena3_example_duplicate_translation`             | `sena3-example-duplicate-translation`             |
| `sena3_gloss_and_definition_multilang`            | `sena3-gloss-and-definition-multilang`            |
| `sena3_inline_span_markup`                        | `sena3-inline-span-markup`                        |
| `sena3_multiple_senses_per_entry`                 | `sena3-multiple-senses-per-entry`                 |
| `sena3_note_trailing_whitespace`                  | `sena3-note-trailing-whitespace`                  |
| `sena3_sense_note_and_field`                      | `sena3-sense-note-and-field`                      |
| `sena3_single_entry_plant`                        | `sena3-single-entry-plant`                        |
| `sena3_single_entry_two_custom_fields_river_mud`  | `sena3-single-entry-two-custom-fields-river-mud`  |
| `note_and_phonology_notes`                        | `zhi-note-and-phonology-notes`                    |
| `two_pronunciations_with_audio_and_IPA`            | `zhi-two-pronunciations-with-audio-and-ipa`        |
| `lela-teli-empty-lexicon`                         | *unchanged*                                       |

**Substitution hazard, verified: `Sena3` is a prefix of `Sena3_gloss_initial_b`.** A per-name `sed` in arbitrary order would rewrite `Sena3_gloss_initial_b` to `sena3_gloss_initial_b` via the short rule and never reach the long one, leaving a half-renamed name that still resolves to nothing. Apply renames **longest name first**, or anchor each rule on the whole basename. Nothing else in the set collides.

**Two invariants make this provable rather than hopeful:**

1. **The multiset of file checksums under `tests/testthat/` is byte-identical before and after.** A rename cannot change content, so any shift means something was edited, dropped or duplicated. Capture it before starting.
2. **`WARN 0`, not just `FAIL 0`.** This is the trap: if a fixture is renamed and its snapshot is not, `expect_snapshot_file()` auto-creates a fresh snapshot with a **WARN** ([AGENTS.md's Testing Approach](../AGENTS.md#testing-approach)), so the suite reports green while silently accepting unvetted output and orphaning the approved file. Pair it with an explicit sweep for snapshots having no matching fixture and fixtures having no matching snapshot.

**Live references to update** (the rename is not just file moves): 4 test files hardcode fixture names — `test-csv2lift_table-discovery.R`, `test-copy-lift-entries_end-to-end.R`, `test-example-source-note-redundancy.R`, `test-multitext-span-markup.R` — plus `SPEC.md`, `README.md`, `.claude/skills/adding-a-lift-field/SKILL.md`, and this plan. The `test-*_end-to-end.R` discovery loops glob and need no edit.

**`plans/old/*.md` is deliberately left alone.** Every archived plan references these names heavily, and [AGENTS.md's Markdown Conventions](../AGENTS.md#markdown-conventions) treat a plan as a point-in-time historical record rather than a live document. The map above stays in this file as the translation table, so an old plan remains navigable without rewriting history.

### Phase B — new tables whose data is already in the repo

**B1 · `sense/reversal` → reversal table (`--reversals`).** Sense-parented, positionally keyed: `zhi-two-pronunciations-with-audio-and-ipa.lift` has one sense with **two reversals of the same `@type="en"`**, so no `reversal_<type>` column scheme works. Copy the example table wholesale — it is the same shape one level up (`R/example_table.R`, `R/example_helpers.R`, `R/csv2lift_example.R`, `test-example-table_end-to-end.R`), keying rows on document position with `sense_guid` as the surviving FK. Columns: `sense_guid`, `reversal_type`, `reversal_<lang>`; classifier starts strict (no custom-field fallback). Attach after `attach_senses_to_lift()`.

Note the pre-existing coverage hole this closes: `_snaps/csv2lift_end-to-end/zhi-note-and-phonology-notes.lift` and `zhi-two-pronunciations-with-audio-and-ipa.lift` are approved snapshots holding **zero** `<reversal>` while their sources have 2 and 3 — exactly [the skill's "a new table opens a coverage hole"](../.claude/skills/adding-a-lift-field/SKILL.md#if-it-needs-a-table-of-its-own) case. Both stems need a `reversals.csv` companion in their export directory.

Since [T1](#phase-t--the-table-folder-convention), adding that companion is a **plain file drop** — `test-csv2lift_end-to-end.R` discovers whatever tables an export directory holds, so no test file is edited to bring a new table into an existing stem's round trip. The flip side is that the file's mere *presence* changes an approved snapshot, where previously a test-loop edit made the intent explicit. So this is a moment to read the `.new` diff rather than accept it: the expected change is `<reversal>` elements appearing where the source always had them, and nothing else moving.

**B2 · `entry/etymology` → etymology table (`--etymologies`).** Entry-parented. Max 1 per entry in the data, but FLEx's Entry pane lets a user add more and `lift.rng` wraps it in `zeroOrMore`, so a table (not columns) — same call as `<pronunciation>`. Columns: `entry_id`, `etymology_type`, `etymology_source` (always empty string in Sena3 — carried anyway, both attributes are *required* by `etymology-content`), `etymology_<lang>` (the form), `gloss_<lang>` (10 present, en/pt), and the inner custom fields as type-keyed columns reusing `emit_typed_children()` (`comment`, `languagenotes`; 46 etymologies carry both). Fixture: `sena3-gloss-initial-b.lift` already has 5 etymologies, so no new export needed; extract a small focused entry per [the skill's third fixture case](../.claude/skills/adding-a-lift-field/SKILL.md#get-a-real-fixture) if the snapshot is unwieldy.

### Phase C — traits, then the two trait-bearing tables

**C1 · a long `traits` table (`--traits`).** The one shape that survives repeated `name`s. One row per trait, document order preserved:

| Column                      | Meaning                                                                                                                        |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `entry_id`                  | FK → entry table (always filled)                                                                                               |
| `sense_guid`                | FK → sense table; filled when `owner` is `sense`/`grammatical-info`, blank otherwise                                           |
| `owner`                     | `sense`, `grammatical-info`, `variant`, or `relation`                                                                          |
| `owner_index`               | 1-based position of the owner among that parent's like-owner siblings; blank for `sense`/`grammatical-info` (at most one each) |
| `trait_name`, `trait_value` | the pair, verbatim                                                                                                             |

Scope deliberately excludes entry-level traits: `morph-type` keeps its existing dedicated `morph_type` column (a public contract already in every snapshot), and no other entry-level trait occurs in any fixture, so it stays in Not yet specified rather than being speculatively covered. Read xpath at sense level is `./trait`; at gram-info level `./grammatical-info/trait`.

Implementable in two halves so the first is small: **C1a** `owner ∈ {sense, grammatical-info}` (no `owner_index` needed — ship the column blank), which covers 1275 of the 1275 traits present today; **C1b** extends it to `variant`/`relation` owners as part of C2/C3, which is where `owner_index` first earns its keep. Attach pass runs **last** — it is the last row of `R/table_registry.R`, whose row order *is* attach order since [T1](#phase-t--the-table-folder-convention) (after senses, variants and relations exist); an `owner_index` matching no owner row is a hard error, per [SPEC.md's Structural rules](../SPEC.md#structural-rules-csv2lift-direction).

**The registry's `requires` field must stay `"senses"` only — do not list `variants`/`relations` there.** `requires` is a static per-table declaration (it is what turns `--examples` without `--senses` into a usage error rather than a per-row FK failure), but this table's requirements are a property of its *data*: a traits CSV holding only `owner = "sense"` rows needs no variant or relation table, and declaring all three would reject that perfectly valid file. So declare the always-true part (`senses` — every trait row carries `entry_id`, and the sense/gram-info owners dominate) and let the `variant`/`relation` owner lookups fail fast **per row** at attach time, which is both the mechanism [SPEC.md's Structural rules](../SPEC.md#structural-rules-csv2lift-direction) already documents for foreign keys and what the `owner_index` hard error above already calls for. No registry change is needed; the temptation to make `requires` a predicate function should be resisted for the same reason.

**C2 · `entry/variant` → variant table (`--variants`).** Entry-parented, positionally keyed (up to 8 per entry, at most one `<form>` each, always `lang="seh"` in Sena3). Columns: `entry_id`, `variant_<lang>`. Its `morph-type` and `environment` traits ride in C1's traits table with `owner = "variant"` — that is what makes the 4 variants carrying 2–3 `environment` traits representable without inventing a delimiter or dropping data. Schema also allows `variant/@ref`, `variant/field`, `variant/pronunciation`, `variant/relation`; none occur, all stay unimplemented and documented.

**C3 · `entry/relation` + `sense/relation` → relation tables.** Needs A2 done. Two tables, one per level, matching the codebase's one-column-per-level grid: `--entry-relations` (`entry_id`, `relation_type`, `relation_ref`, `relation_order`) and `--sense-relations` (`sense_guid`, `relation_type`, `relation_ref`). Both positionally keyed. These are the first multi-word table names, so they are the first to exercise [T2's kebab-case rule](#t2--drop-flat-mode-folder-only-discovery) — registry names `entry-relations`/`sense-relations`, giving flags `--entry-relations`/`--sense-relations` and files `entry-relations.csv`/`sense-relations.csv` inside an export directory, one string for both surfaces. Entry-relation traits (`is-primary`, `complex-form-type`, `variant-type`, one relation repeating a name) ride in C1's traits table with `owner = "relation"`. `relation_order` is copied verbatim, never regenerated. `relation/usage` and `variant/relation` do not occur; leave unimplemented.

**`relation_ref` holds the target's guid, not the raw `@id` string**, translated to the target entry's stored `entry_lift_id` on write. Copying the `@id` verbatim would embed another row's headword and guid in a text field, while every other FK in the repo is a guid ([SPEC.md's Structural rules](../SPEC.md#structural-rules-csv2lift-direction)); guid-keying also hides the doc's entry-uses-id/sense-uses-guid asymmetry and makes csv2lift responsible for internal consistency regardless of user edits. Lossless: all 31 entry refs carry the target guid as the after-last-underscore suffix, so both directions recover exactly. See [redundant-columns-and-entry-id.md](old/redundant-columns-and-entry-id.md).

One import behaviour to design around when this is built: the FLEx doc warns that for Collection-type relations "the import process will try to unify the relation sets… If collection references overlap in a way that cannot be unified, the import log will list multiple Combined Collections… If there are many of these, the result will probably be very bad."

If two tables/flags for one element feels heavy, the alternative is one `relations` table with both `entry_id` and `sense_guid` and exactly one filled — cheaper CLI, but the first table in the repo that spans two levels. Recommend the two-table version; flag it in the commit so it is a visible choice.

### Phase D — structural and blocked items

**D1 · `sense/subsense` → `parent_sense_guid` on the sense table.** 8 in Sena3, one level deep, each with its own `@id`. Add a `parent_sense_guid` column (blank = a direct sense of the entry); switch `sense_table()`'s axis from `./sense` to a recursive walk; in `attach_senses_to_lift()`, emit parentless rows first, then rows whose parent exists, as `<subsense>` (the tag differs from `<sense>`). Then widen the FK lookups that currently say `.//sense[@id=…]` to match `<subsense>` too, and `example_table()`'s `.//entry/sense/example` axis to include the 1 subsense example — which is what retires three separate Not-yet-specified entries at once. Do this **after** Phase C, since every sense-parented table (examples, reversals, traits) inherits the widened lookup.

**D2 · `header` passthrough — narrowed to `<fields>` only.** `<header>/<fields>` (11 custom-field declarations with English descriptions) and `<header>/<ranges>` (27 `href`s into an external `.lift-ranges` file) are per-document metadata, not per-entry data, and a CSV round-trip of them buys little. Proposal: a `--header-from <lift-file>` flag on `scripts/csv2lift.R` copying `<header>/<fields>` into the output.

**D2 is not a registry row.** It takes a LIFT file rather than a CSV and is per-document rather than per-table, so it does not belong in `R/table_registry.R` and must not be forced in — it is a plain flag on `scripts/csv2lift.R`, handled outside the registry loop. [T1](#phase-t--the-table-folder-convention) did, however, create an alternative worth weighing when D2 is built: discovery only scopes `*.csv`, so an export directory can carry a `header.lift` alongside its CSVs and be ignored today, which means D2 could pick it up by convention instead of by flag. Noted as newly available, not recommended — a flag is more explicit, and the convention would be invisible.

The FLEx doc settles the "will FLEx import a header-less LIFT" question: "**The header element is optional in a LIFT file**", and the doc's own minimal importable example has none. The two halves differ, though:

- **`<ranges>`: drop it.** "On import into FLEx, any references to range elements in senses and entries will try to find an existing item in the FLEx list. If not found, a new item will be added." Nothing lost but import-log noise — and the `href`s are absolute paths to one machine's `.lift-ranges` file, so copying them verbatim is worse than omitting them.
- **`<fields>`: keep it, for custom-field typing only.** "The fields element is not used during import, **except for FLEx custom fields**. Without a field definition for a custom field, the import will create a custom field in the target project, but it defaults to a MultiUnicode field with `kwsAnalVerns` as the selector." The payload is the `qaa-x-spec` pseudo-writing-system carrying `Class=`/`Type=`/`WsSelector=`. Dropping it preserves all data and degrades the schema — Sena3's 11 declarations would all arrive as MultiUnicode/`kwsAnalVerns`.

So D2 is only worth building if importing into a *fresh* FLEx project is a goal — see [Decisions](#decisions-to-settle). Details in [redundant-columns-and-entry-id.md](old/redundant-columns-and-entry-id.md).

**D3 · pronunciation-level `field`/`trait`, media `@label`.** Genuinely blocked: zero occurrences in any fixture (Sena3 has no `<pronunciation>` at all; the two small pronunciation fixtures carry only forms and media). `cv-pattern` and `tone` are *declared* in every header, so the data exists in other projects. Per [the skill's fixture rule](../.claude/skills/adding-a-lift-field/SKILL.md#get-a-real-fixture), ask for a real export rather than hand-writing one; until then this stays in Not yet specified.

## Decisions to settle

Recommendations are in the increments above; these are the points where a different answer changes the work. Each is answerable when its increment starts — none of them block Phase A.

1. ~~**A2's column name.**~~ **Settled and implemented**: `entry_lift_id`, store verbatim, per the FLEx documentation — see A2 and [redundant-columns-and-entry-id.md](old/redundant-columns-and-entry-id.md).
2. **C1's table shape** — one unified long `traits` table (recommended: one flag, one SPEC section, one test file, and future trait kinds need no new code) versus per-level trait tables (`--sense-traits`, `--variant-traits`, …: no cross-CSV positional coupling, but 3–4 more tables). The unified version's only real cost is `owner_index` pointing at another CSV's row position, which a fail-fast lookup makes loud rather than silent.
3. **C3 one relations table or two** — see C3.
4. **D2 at all** — the "does FLEx need `<header>` to import" half is **answered: no**, the element is optional (see D2). What remains is the other half: is import-into-FLEx even a goal for this tool? If not, D2 drops off the list entirely; if it is, D2 is `<fields>`-only and exists purely so custom fields arrive with their declared types.
5. ~~**T1's prefix rule.**~~ **Settled, then superseded**: T1 shipped one `--tables <prefix>` where a trailing path separator switches from `<prefix>_<name>.csv` to `<name>.csv`. [T2](#t2--drop-flat-mode-folder-only-discovery) drops the flat half entirely, so the trailing-separator rule goes away with it and `--tables <dir>` becomes just a directory.
6. ~~**T2's fixture directory names.**~~ **Settled and implemented in [T3](#t3--normalise-fixture-names-to-kebab-case)**, as its own increment after T2. The question as originally framed was scoped wrong: these turned out not to be 13 csv2lift export-directory names but 15 fixture names shared across 6 fixture families and 7 snapshot directories, so the rename touched 96 files and was all-or-nothing per name. Full map, hazards and invariants are in T3; `zhi` (ISO 639-3 for Zhire) prefixes the two Zhire fixtures, and lowercasing `Sena3` → `sena3` was accepted so that one rule covers every path in the repo.

## Verification

Per **field** increment, in this order. T1 is not a field increment and carries [its own verification steps](#verification-differs-from-a-field-increment) — no snapshot in `_snaps/` may change.

1. `Rscript -e 'devtools::test(filter = "<table>-table_end-to-end")'` — read direction. A brand-new fixture auto-creates its snapshot with a WARN, so **read the file**; that absence is the red.
2. Verify the new column/table contents against the tallies in the inventory table above with a throwaway `python3 -c` over the `.new` CSV (counts must match: 108 `entry_order`, 105 etymologies, 197 sense traits, 1078 gram-info traits, 168 variants, 31 + 44 relations, 5 reversals). Re-derive any figure before it goes into SPEC.md.
3. `Rscript -e 'testthat::snapshot_accept("<name>-table_end-to-end/")'` (trailing slash required) and the same for `join-sense-entry-table_end-to-end/` where the level reaches that view; re-run to confirm the accept took.
4. Refresh every `tests/testthat/fixtures/csv2lift/<stem>/<level>.csv` whose source `.lift` contains the new field by re-copying reader output — and leave the rest strictly alone, since their byte-identical snapshots prove the writer still tolerates the columns being absent.
5. `Rscript -e 'devtools::test(filter = "csv2lift_end-to-end")'` — write direction; review the `.lift` diff before accepting.
6. Full `Rscript -e 'devtools::test()'` green, then SPEC.md updated in the same change (column row or new section, classification algorithm, canonical child order, CLI shape list, and deletion of the Not-yet-specified entries the increment retires), plus a README example for each new flag.

End-to-end round-trip spot check after each new table, using the largest fixture that exercises it:

```bash
Rscript scripts/lift2csv.R <fixture>.lift --table entries > /tmp/e.csv
Rscript scripts/lift2csv.R <fixture>.lift --table <new> > /tmp/n.csv
Rscript scripts/csv2lift.R /tmp/e.csv --<new> /tmp/n.csv > /tmp/out.lift
# then diff element/attribute tallies between <fixture>.lift and /tmp/out.lift
```

After T1 this becomes two lines regardless of how many tables the fixture exercises, which is the point of building it first (`--tables` below is `--table-dir` as of `plans/per-table-script-consolidation.md`'s R1, which also folded the four per-table scripts above into `lift2csv.R --table <name>`):

```bash
Rscript scripts/lift2csv.R <fixture>.lift --table-dir /tmp/rt/
Rscript scripts/csv2lift.R --table-dir /tmp/rt/ > /tmp/out.lift
```

## Files touched (pattern, per increment)

A column increment touches the level's four files plus docs: `R/<level>_table.R` (extract + `pivot_wider` + `left_join`), `R/<level>_helpers.R` (`classify_<level>_columns()`), `R/csv2lift_<level>.R` (emit block, positioned to match SPEC.md's canonical child order), and `SPEC.md`.

A new table adds a fifth column to that grid — `R/<name>_table.R`, `R/<name>_helpers.R`, `R/csv2lift_<name>.R`, `scripts/lift2csv_<name>-table.R`, a flag in `scripts/csv2lift.R`, `tests/testthat/test-<name>-table_end-to-end.R`, a curated `tests/testthat/fixtures/lift2csv_<name>-table/` directory, the `*_<name>.csv` glob in `tests/testthat/test-csv2lift_end-to-end.R`, its own SPEC.md section, and a README example. (This paragraph describes the state before [`plans/per-table-script-consolidation.md`](per-table-script-consolidation.md), left as written since it explains why Phase T was sequenced first; see that plan for what a new table costs now.)

**After [Phase T](#phase-t--the-table-folder-convention), five of those nine collapse into one registry row.** The flag, the attach call and its position, the `requires` guard, the test-loop glob and the SPEC.md CLI bullet all become fields in `R/table_registry.R`; the README's per-flag example becomes unnecessary because `--tables` covers every table at once. What is left per new table is the genuinely per-table work: the three `R/` files, the `scripts/lift2csv_<name>-table.R` one-liner, the test file, the fixture directory, the registry row, and the SPEC.md section describing the table's columns and keys. That is the reason Phase T comes before the six remaining tables rather than after them.

**Superseded by [`plans/per-table-script-consolidation.md`](per-table-script-consolidation.md) (R0-R2), run before Phase B.** The `scripts/lift2csv_<name>-table.R` one-liner above is no longer part of a new table's cost — `lift2csv.R --table <name>` reaches it via the registry row alone, the same way `--tables` (renamed `--table-dir`) already did for the directory case. A new table's cost is now: the three `R/` files, the test file, the fixture directory, the registry row, and the SPEC.md section.

Two further consequences of Phase T, both of which reduce per-increment work but need naming right up front:

- **Adding a table to an *existing* export's round trip is a file drop, not a code change.** Dropping `reversals.csv` into a fixture's export directory is enough for `test-csv2lift_end-to-end.R` to pick it up. Read the resulting snapshot diff rather than accepting it — see [B1](#phase-b--new-tables-whose-data-is-already-in-the-repo).
- **The registry name is simultaneously the CLI flag and the CSV filename**, so it is user-visible in two places and expensive to change later. Kebab-case plural nouns, per [T2](#t2--drop-flat-mode-folder-only-discovery).
