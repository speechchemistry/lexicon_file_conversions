# Plan: remove the entry ⋈ sense join view

## Status

Planned, not started. Prerequisite for [plans/prune-empty-columns.md](prune-empty-columns.md)
(see its Sequencing section): landing this first drops that change from 13 snapshot approvals
to 9 and removes one of its two duplicated `nrow(table) == 0` special cases.

## Decision

The join view is historic. Joining the sense and entry tables moves to downstream tooling, so
this repo stops producing the joined shape and emits only the normalized per-table CSVs that
csv2lift already consumes.

The join *itself* is not being abandoned — it moves out. That distinction matters for two
things below: the `entry_order`/`sense_order` naming rationale survives, and the cross-table
column-name collision it resolved becomes a documented hazard rather than a solved problem.

## What is being deleted

| Path | Notes |
| --- | --- |
| `scripts/lift2csv_join-sense-entry-table.R` | the only caller of `join_sense_entry()` |
| `R/join_sense_entry.R` | one function, nothing else calls it |
| `tests/testthat/test-join-sense-entry-table.R` | its own fixture loop, not `expect_table_snapshots()` |
| `tests/testthat/fixtures/lift2csv_join-sense-entry-table/` | 5 `.lift` fixtures — its own copies, not symlinks — including a 1.4M duplicate `sena3.lift`, plus 3 stray `*:Zone.Identifier` files |
| `tests/testthat/_snaps/join-sense-entry-table/` | 5 approved CSVs, 480K |

About 1.9M of the repo, most of it the duplicated `sena3.lift`.

Nothing else in `R/` or `scripts/` references `join_sense_entry`; the CLI script is its sole
consumer, so this is a clean excision rather than an untangling.

## The two parts that are not mechanical

### 1. `entry_order` / `sense_order` keep their names, but the reason needs rewording

[SPEC.md's Entry Table](../SPEC.md#entry-table) and [Sense Table](../SPEC.md#sense-table) each
justify the column name by the join view: "Named `entry_order` rather than `order` … to stay
distinct from the sense-level `@order` attribute in the Join View".

The names stay right — but the stated reason points at something being deleted. Since joining
still happens, just downstream, reword to that rather than dropping the rationale: the two
`@order` attributes must remain distinguishable *when the tables are joined*, wherever that
join runs. Deleting the sentence would leave two oddly-prefixed columns with no recorded reason,
and someone would later "tidy" them to `order`.

### 2. The cross-table collision must be relocated, not deleted

[SPEC.md's Join view](../SPEC.md#join-view) is the only place recording that entry and sense
columns can share a name, and `join_sense_entry()`'s `suffix = c("_sense", "_entry")` is the
only thing that resolves it. **The collision is real on current data**: `note_restrictions_en`
appears in both `_snaps/entry-table/sena3.csv` and `_snaps/sense-table/sena3.csv` (61
entry-level `restrictions` notes against 1 sense-level one — one instance on the far side is
enough), which is why the join snapshot carries `note_restrictions_en_sense` and
`note_restrictions_en_entry`.

Removing the join view does not remove the collision. It **exports** it: a downstream
`left_join(senses, entries, by = "entry_id")` in dplyr silently yields
`note_restrictions_en.x`/`.y`, and pandas' `merge` yields `_x`/`_y`.

So the Join view section's content must be relocated as a consumer-facing rule, not deleted with
it — a new bullet under [Data handling](../SPEC.md#data-handling) or
[Column classification](../SPEC.md#column-classification) saying: column names are unique within
a table, not across tables; `entry_id` is shared deliberately as the foreign key; typed notes
(`note_<type>_<lang>`) are deliberately shared across levels because one FLEx field at two
levels keeps one name; today's live instance is `note_restrictions_en`; a downstream join must
supply its own suffixes.

Do **not** resolve it by renaming. The `adding-a-lift-field` skill's rule — different fields
that share a tag get different names, the same field at two levels keeps the same name — is
still correct, and per-level prefixes would invent a distinction FLEx does not make.

## Steps

One commit per step, `J1:`-style prefixes.

### J1 — prove the test covers it, then delete the code

Deleting code has no natural red phase, so manufacture one cheaply rather than skipping it:
delete `R/join_sense_entry.R` **only**, run `devtools::test(filter = "join-sense-entry-table")`,
and confirm it fails. That proves the test was actually exercising the function rather than
passing vacuously — worth 30 seconds before throwing the test away.

Then delete the remaining four paths from the table above, and confirm:

- `devtools::test()` green.
- `grep -rn "join_sense_entry\|join-sense-entry" --include=*.R --include=*.md . | grep -v '^./plans/'`
  returns nothing.
- No other `_snaps/` directory moved — the join view was read by nothing but its own script, so
  every other approved artifact must be byte-identical. `git diff --stat tests/testthat/_snaps/`
  should show only the deleted directory.

### J2 — SPEC.md

- Delete the `## Join view` section.
- Relocate its collision content per part 2 above.
- Reword the `entry_order` and `sense_order` naming rationales per part 1 above.
- Fix [line 42](../SPEC.md#L42) in Column classification ("one typed-note column name can occur
  on both tables; see Join View for how it's resolved") — repoint at the relocated rule; the
  clause about *how it's resolved* is now false and must change, not just relink.
- The Join view section's closing note that the [Example Table](../SPEC.md#example-table) never
  reaches the view goes with the section — it only existed to bound the view's scope.
- Grep for the dead anchor afterwards: `grep -rn '#join-view' .` should return nothing outside
  `plans/`.

### J3 — AGENTS.md and README.md

- [AGENTS.md:65](../AGENTS.md#L65): drop the trailing exception "`test-join-sense-entry-table.R`
  keeps its own loop: it drives a different script and takes no `--table` flag." With it gone,
  `expect_table_snapshots()` covers every per-table test with no exceptions — a simplification
  of the stated rule, so say it plainly rather than just deleting the clause.
- [README.md:25](../README.md#L25): remove the `lift2csv_join-sense-entry-table.R` usage example.

### J4 — the `adding-a-lift-field` skill

Eight references, two of them load-bearing. Straightforward deletions first: the worked-example
mention (~line 19), the fixture-directory copy rule (~84), the `snapshot_accept("join-sense-entry-table/")`
command (~153), the "then check the join view" step (~205), the SPEC Join View documentation step
(~219), and `join-sense-entry-table_` in the rename checklist's list of affected snapshot
directories (~223).

The load-bearing pair is ~55 and ~57: **"Column names are one namespace across levels, not one
per table"** is built entirely on the join view being where a clash surfaces in a reviewed CSV,
and on `suffix =` being the mechanism that resolves it. Both premises die here. The rule itself
survives and still needs stating — but its enforcement changes from "the join view will show you"
to "nothing in this repo will show you; the collision ships to the consumer." Rewrite it that
way and point at the relocated SPEC rule. Do not simply delete these two paragraphs: they are
the reason `note_` and `general_note_` differ, and that reasoning is still live.

## Verification

- `devtools::test()` green; `git diff --stat tests/testthat/_snaps/` shows only the deleted
  `join-sense-entry-table/` directory.
- `grep -rn "join_sense_entry\|join-sense-entry\|#join-view" . | grep -v '^./plans/'` empty.
- Then re-check [plans/prune-empty-columns.md](prune-empty-columns.md)'s expected-snapshot table
  is down to its 9 rows before starting E1.

## Not touched

- `plans/old/*.md` and `plans/remaining-lift-fields.md`: historic records. Per
  [AGENTS.md's Markdown Conventions](../AGENTS.md#markdown-conventions), a plan describes a past
  decision and is not retroactively edited — several record *why* the join view was deliberately
  kept out of the registry, which stays true of the time it was written.
- `scripts/copy-lift-entries.R` and its spec/tests/fixtures. Also a candidate for removal, but
  independent of this one and with its own decision to make (it is the only tool for minting
  trimmed `.lift` fixtures). Its own plan file if it goes ahead.
