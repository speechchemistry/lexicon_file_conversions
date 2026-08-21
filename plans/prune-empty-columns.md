# Plan: prune all-blank columns from lift2csv output

## Status

Done. E1–E5 executed as written: 9 snapshot changes (join view was already removed first), all matching the predicted table exactly; `_snaps/csv2lift/` byte-identical throughout; format-time pruning in `R/table_csv.R` as the weakly-preferred option. Own file; does not touch `plans/remaining-lift-fields.md`.

## Decision

An emitted CSV carries no column that is blank in every row. This extends to columns
the rule that `--table-dir` already applies to whole tables ([SPEC.md's CLI shape](../SPEC.md#csv2lift-cli-shape) omits a table with no rows) and that csv2lift
already applies to elements ([Structural Rules](../SPEC.md#structural-rules-csv2lift-direction):
"empty optional elements are never emitted").

### Why (the arguments that survived review)

- **Consistency, and one fewer special case.** `scripts/lift2csv.R`'s `format_table_csv()`
  is `if (nrow(table) == 0) "" else format_csv(table, na = "")` — an explicit suppression
  of the header `format_csv()` would otherwise emit. `scripts/lift2csv_join-sense-entry-table.R`
  duplicates it. Under the new rule a zero-row table prunes to zero columns, and
  `format_csv()` on a zero-column tibble returns `""` (measured, see Verified facts).
  Both special cases become derivable and are deleted.
- **The schema is already data-dependent.** Every `<lang>`- and `<type>`-keyed column
  exists only when the document carries a value for it ([Data Handling](../SPEC.md#data-handling)).
  Pruning the handful of remaining structural columns removes an exception to a property
  the tool already has, rather than introducing a new one.
- **The columns affected are exactly the ones SPEC already calls information-free.**
  `entry_order` and `sense_order` are documented as "a blank here is normal, not missing
  data" ([Entry Table](../SPEC.md#entry-table), [Sense Table](../SPEC.md#sense-table)).

### Arguments considered and rejected

- *An empty column is a template telling the user what they may fill in.* Real, but a
  guidance document covers it, and the structural columns are already enumerated in SPEC.
- *Backward compatibility — absence would become ambiguous with "CSV predates the column".*
  Void: the tool has no users, and no such CSV exists.
- *Schema uniformity across fixtures.* Circular — it argued uniformity is good because the
  fixtures are uniform. Under pruning a narrow fixture's schema is simply correct for its
  content.
- *`morph_type` absent would be ambiguous with "lift2csv doesn't read morph-type".* Bad
  example: every entry in every fixture carries a `morph-type` trait (0 of 1462 missing in
  `sena3.lift`), so it can never be an empty column.

## Sequencing: the join view is being removed first

Joining the sense and entry tables moves out of this repo — it will happen in downstream
tooling — so `scripts/lift2csv_join-sense-entry-table.R`, `R/join_sense_entry.R`,
`tests/testthat/test-join-sense-entry-table.R`, `fixtures/lift2csv_join-sense-entry-table/`
(5 fixtures) and `_snaps/join-sense-entry-table/` (5) go with it. **Do that change first.**
It shrinks this one from 13 snapshot approvals to 9 and from two duplicated
`nrow(table) == 0` special cases to one, since the join script carries its own copy.

The four `join-sense-entry-table/` rows in the table below therefore do not apply, and E2's
join-script bullet drops.

**Carry-over that the removal change must settle, not this one:** `note_restrictions_en` is
present on *both* `entries.csv` and `senses.csv` (`sena3`: 61 entry-level notes against 1
sense-level), and `join_sense_entry()`'s `suffix = c("_sense", "_entry")` is the only thing in
the repo that resolves it. Removing the join view does not remove the collision — it exports
it. A downstream `left_join(senses, entries, by = "entry_id")` silently produces
`note_restrictions_en.x`/`.y`. [SPEC.md's Join view](../SPEC.md#join-view) documents a
resolution that will cease to exist, so the removal should replace it with a consumer-facing
note (entries and senses can share a column name; today's instance is `note_restrictions_en`;
a downstream join must supply its own suffixes) rather than renaming anything — renaming would
contradict the `adding-a-lift-field` skill's rule that one FLEx field at two levels keeps one
name, which is still right.

## The rule, precisely

A column is empty when no row holds a non-empty-string value in it — `NA` and `""` count
alike, since `na = ""` on read and write makes them indistinguishable in the CSV anyway.
Column order among survivors is unchanged (first-appearance order still holds).

Consequence worth naming: this is the only case where the rule can touch a *data-driven*
column. `<form lang="x"><text/></form>` — a real `lang` with empty text — yields `""`, so
its whole `lang` column prunes and the empty `<form>` does not round-trip. No fixture has
one (zero empty `<text/>` elements repo-wide), so per the no-defensive-code convention this
is recorded in [Not Yet Specified](../SPEC.md#not-yet-specified), not handled.

## Where it goes: format time, not the table builders

Prune in a shared `format_table_csv()` used by the read-side script(s), **not** inside
`entry_table()`/`sense_table()`/`example_table()`/`pronunciation_table()`.

```r
# R/table_csv.R (new)
drop_empty_columns <- function(table) {
  dplyr::select(table, dplyr::where(function(col) any(!is.na(col) & nzchar(col))))
}

# No nrow() guard: a zero-row table prunes to zero columns, and format_csv()
# on a zero-column tibble is exactly "".
format_table_csv <- function(table) {
  readr::format_csv(drop_empty_columns(table), na = "")
}
```

This is a **weak preference, not a design argument** — the two options are nearly equivalent:

- **For format time:** one edit instead of four, and the builders stay faithful extractors
  whose typed-empty-tibble guards (there for `left_join` correctness inside the builder, per
  the `adding-a-lift-field` skill) are left alone.
- **For builder level:** SPEC describes a table *as* its CSV contract, so pruning there makes
  `entry_table()`'s return value match the emitted CSV exactly.

Nothing in the test suite can tell the difference: no test calls a table builder directly
(`grep "entry_table(\|sense_table(\|example_table(\|pronunciation_table(" tests/` is empty),
so all coverage is via the CLI either way. Either choice deletes the `nrow(table) == 0` guard,
since a zero-row table prunes to zero columns under both.

**Superseded reason, recorded so it isn't re-litigated:** the original deciding argument was
that format-time pruning also catches a column non-blank *only* on senseless entries, which
`left_join(sense, entry)` drops from the join view — unpruned under builder-level pruning.
That argument is void now the join view is being removed (see Sequencing), and it never had a
fixture behind it: `sena3.lift` has 0 senseless entries of 1462.

## Verified facts this plan rests on

Measured before planning, not assumed:

| Claim | Result |
| --- | --- |
| `format_csv(tibble(a=character(),b=character()), na="")` | `"a,b\n"` — bare header, which is why line 38's `""` exists |
| Same tibble with all columns pruned (`ncol == 0`) | `""` exactly — so the guard is redundant under the new rule |
| `select(where(\(col) any(!is.na(col) & nzchar(col))))` | drops all-`NA`, all-`""`, and mixed `NA`/`""`; keeps order |
| Empty `<text/>` elements across all fixtures | none |
| Entries lacking a `morph-type` trait | 0 of 1462 in `sena3.lift`; 0 in every other fixture |
| Senseless entries in `sena3.lift` | 0 of 1462 |

## Expected snapshot changes: 9 files, and no others

(13 if the join-view removal in Sequencing has not landed yet; the four
`join-sense-entry-table/` rows are listed for that case only.)

Derived by pruning each approved snapshot offline. Any deviation from this list during
review means the implementation is wrong — check it before accepting.

| Snapshot | Column(s) dropped |
| --- | --- |
| `entry-table/sena3-gloss-initial-b.csv` | `entry_order` |
| `entry-table/sena3-single-entry-plant.csv` | `entry_order` |
| `entry-table/sena3-single-entry-two-custom-fields-river-mud.csv` | `entry_order` |
| `entry-table/zhi-two-pronunciations-with-audio-and-ipa.csv` | `entry_order` |
| `sense-table/sena3-single-entry-plant.csv` | `sense_order` |
| `sense-table/sena3-single-entry-two-custom-fields-river-mud.csv` | `sense_order` |
| `sense-table/zhi-note-and-phonology-notes.csv` | `sense_order` |
| `example-table/sena3-example-duplicate-translation.csv` | `example_source` |
| `example-table/sena3-single-entry-two-custom-fields-river-mud.csv` | `translation_type` |
| `join-sense-entry-table/sena3-single-entry-plant.csv` | `sense_order`, `entry_order` |
| `join-sense-entry-table/sena3-single-entry-two-custom-fields-river-mud.csv` | `sense_order`, `entry_order` |
| `join-sense-entry-table/zhi-note-and-phonology-notes.csv` | `sense_order` |
| `join-sense-entry-table/zhi-two-pronunciations-with-audio-and-ipa.csv` | `entry_order` |

**Unchanged**, and each is a meaningful control: every `sena3.csv` (the full file fills all
four columns), `entry-table/zhi-note-and-phonology-notes.csv`, the `sense-table` and
`example-table` `sena3-gloss-initial-b.csv`, all four `pronunciation-table` snapshots, and
the four already-zero-byte empty-table snapshots.

**Every `_snaps/csv2lift/` artifact must be byte-identical.** A blank column emitted nothing
on the write side, so pruning it cannot change the LIFT output. This is the regression check
that the change is output-preserving; a single changed csv2lift snapshot means a bug.

## Steps

Each step is one commit, red → green → refactor, in the `E1:`/`E2:` style of the `R1`–`R4`
series. Run tests with `devtools::test()` (per [AGENTS.md's Testing Approach](../AGENTS.md#testing-approach));
never auto-accept snapshots.

### E1 — unit-test the helper (red), then implement it (green)

New `tests/testthat/test-table-csv.R`, with a header comment stating it is genuinely
unit-level (no subprocess, no snapshot) per the filename convention. Cases:

- all-`NA` column dropped; all-`""` column dropped; mixed `NA`/`""` dropped
- column with a single non-blank value kept
- surviving column order preserved
- zero-row typed tibble → `ncol == 0`, and `format_table_csv()` returns `""`
- a row whose every value is blank does **not** drop the column if another row fills it
  (guards against a row-wise/column-wise mix-up)

Red first: the file `R/table_csv.R` does not exist, so the test errors. Then add
`R/table_csv.R` as sketched above. Nothing calls it yet, so no snapshot moves.

### E2 — wire both scripts to it, delete both special cases

- `scripts/lift2csv.R`: delete the local `format_table_csv()`; the shared one is loaded by
  `devtools::load_all()`. Keep the `--table-dir` skip (`if (nrow(table) == 0 && name != "entries") next`)
  exactly as is — it decides which *files* exist, which csv2lift's discovery depends on, and
  is a row rule, not a column rule.
- `scripts/lift2csv_join-sense-entry-table.R`, **only if the join view survives Sequencing**:
  replace the `if (nrow(table) == 0)` block with `cat(format_table_csv(table))`. If it is being
  removed, that deletion is its own change and this bullet drops.

This turns the 13 snapshots above red. Review with `testthat::snapshot_review()`, check the
diffs against the table, then accept per directory **with a trailing slash** —
`snapshot_accept("entry-table/")` etc. — and re-run to confirm the accept took effect.

Verify `_snaps/csv2lift/` produced no `.new` files at all.

### E3 — regenerate the csv2lift input fixtures that are meant to be lift2csv output

The `adding-a-lift-field` skill's write-direction step reuses lift2csv's own output as the
csv2lift input fixture, so where a matching `lift2csv_*` fixture exists, regenerate:

- `csv2lift/sena3-gloss-initial-b/entries.csv`, `csv2lift/sena3-single-entry-plant/entries.csv`,
  `csv2lift/zhi-two-pronunciations-with-audio-and-ipa/entries.csv` (lose `entry_order`)
- `csv2lift/zhi-note-and-phonology-notes/senses.csv` (loses `sense_order`)
- `csv2lift/sena3-example-duplicate-translation/examples.csv` (loses `example_source`)

**Deliberately leave the csv2lift-only fixtures alone** — `sena3-citation-and-custom-field`,
`sena3-entry-and-sense-typed-notes`, `sena3-gloss-and-definition-multilang`,
`sena3-inline-span-markup`, `sena3-multiple-senses-per-entry`, `sena3-note-trailing-whitespace`,
`sena3-sense-note-and-field`. Several are hand-authored subsets that already omit
`sense_order` entirely, and the ones that still carry an all-blank `entry_order` now earn
their keep as coverage that csv2lift accepts a hand-edited CSV *containing* an empty column.
Note that in the fixture rationale rather than silently normalising them.

csv2lift snapshots must still be byte-identical after this step.

### E4 — SPEC.md

- **[Data Handling](../SPEC.md#data-handling)**: new bullet stating the two-part column set —
  structural columns (keys, attributes, `@type`/`@source` value columns) versus data-driven
  `<lang>`/`<type>`-keyed ones — and the rule that neither kind is emitted when blank in
  every row, with `NA` and `""` treated alike. Cross-reference the element-level rule in
  [Structural Rules](../SPEC.md#structural-rules-csv2lift-direction) and the table-level rule
  in [CLI shape](../SPEC.md#csv2lift-cli-shape) as the same rule at three
  granularities.
- **[CLI shape](../SPEC.md#csv2lift-cli-shape)**: record that the empty-table zero-byte
  output is now a *consequence* of the column rule, not a special case, and that the
  `--table-dir` skip remains a row rule.
- **[Entry Table](../SPEC.md#entry-table) / [Sense Table](../SPEC.md#sense-table)**: the
  `entry_order` and `sense_order` rows say "a blank here is normal, not missing data" — extend
  to note the column is absent entirely when no row fills it.
- **[Example Table](../SPEC.md#example-table)**: same for `example_source` and `translation_type`.
  The type-only-translation guarantee ("a type-only translation round-trips rather than being
  silently dropped") is unaffected — `translation_type` is only pruned when *no* row fills it —
  but say so, since the two rules read as if they conflict.
- **The three absent-column notes** ([entry_lift_id](../SPEC.md#entry-table),
  `dateCreated`/`dateModified`/`order`, [sense_order](../SPEC.md#sense-table)): reword off the
  backward-compatibility framing ("a CSV produced before X existed still converts") onto its
  two live justifications — a hand-authored partial CSV, and now lift2csv's own output, which
  omits the column whenever it would be blank. The `%in% names(row)` guards become
  load-bearing on the tool's own round trip rather than on history.
- **[Not Yet Specified](../SPEC.md#not-yet-specified)**: the empty-`<text/>` fidelity loss above.

### E5 — the skill

`.claude/skills/adding-a-lift-field/SKILL.md` line ~239 documents `format_table_csv()` emitting
`""` when `nrow(table) == 0`. Reword to the column rule with the empty-table output as its
consequence, and point at `R/table_csv.R` as the shared location. The typed-empty-tibble
guidance (~line 104) stays as is — it is about `left_join` inside a builder, which pruning
does not touch.

## Verification

- `devtools::test()` green, with the 13 expected snapshot changes accepted and no others.
- No `.new` files under `_snaps/csv2lift/` at any point.
- `git diff --stat tests/testthat/_snaps/csv2lift/` empty.
- Spot-check the round trip end to end on `sena3-single-entry-plant`: `lift2csv.R --table-dir`
  then `csv2lift.R --table-dir` reproduces the same LIFT as before the change.

## Considered: does a downstream joiner change the decision?

No. Now that the join happens in other tooling, `entries.csv`/`senses.csv` are an interface to
that consumer, which reopens schema stability in a forward-looking form — not backward
compatibility. It still loses: any consumer already has to tolerate absent columns, since
`gloss_pt` exists only when some sense carries a Portuguese gloss. Pruning the structural
columns extends a requirement the consumer already has rather than creating a new one.

## Out of scope

- Whether an empty table should emit a header-only CSV as an editing template. The opposite
  question to this one, deliberately left for its own decision — resolving it that way would
  reintroduce a special case this plan removes.
- Any `--keep-empty-columns` flag. Both directions would need testing for a mode nobody has
  asked for.
