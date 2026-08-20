# Plan: consolidate the per-table lift2csv scripts into the registry

## Context

[Phase T](remaining-lift-fields.md#phase-t--the-table-folder-convention) built `R/table_registry.R` as the single source of truth for which CSV tables the round trip knows about, and `scripts/lift2csv.R --tables <dir>` as the read-side umbrella over it. T1 deliberately left the five per-table `scripts/lift2csv_*.R` scripts in place — "they are the tested public surface, and each is a one-liner over its `read_fn`; the umbrella is additive."

That was right at the time. It stops being right at [Phase B](remaining-lift-fields.md#phase-b--new-tables-whose-data-is-already-in-the-repo), because six more tables are queued (`reversals`, `etymologies`, `traits`, `variants`, `entry-relations`, `sense-relations`) and each one currently costs a hand-copied 20-line script whose only per-table content is a function name and a help string. This plan removes that per-increment cost before the six increments rather than after, on the same reasoning that put Phase T ahead of them.

Three increments, deliberately separable: **R0** closes a hole in the CLI snapshot helper that lets a crashed script pass as a correct empty result; **R1** folds the four registry-table scripts into `lift2csv.R` and renames `--tables` to `--table-dir` in both directions; **R2** deletes two registry fields nothing reads. A proposed **R3** (test-file naming) is recorded under [Decisions to settle](#decisions-to-settle) and is *not* approved.

No increment here is a skill run — like Phase T, this is CLI infrastructure, not a field.

**Status: not started. Sequence R0 → R1 → R2 → (R3 if approved), then Phase B (B1).** R0 comes first because it strengthens the safety net the other two lean on: R1 and R2 both assert that nothing under `_snaps/` moved, and that assertion is only worth as much as the tests behind it. None of the three changes a single approved snapshot.

## R0 · assert exit status in the CLI snapshot helper

### The hole

`expect_cli_stdout_file_snapshot()` captures stdout to a file and compares it to the approved snapshot. It never looks at the process's exit status — `run_cli_to_file()` calls `system2()` and discards its return value. So a script that dies before writing anything produces zero bytes of stdout, which matches an approved zero-byte snapshot, and the test passes:

| invocation | exit status | stdout |
|---|---|---|
| `lift2csv_sense-table.R lela-teli-empty-lexicon.lift` (correct) | 0 | 0 bytes |
| `lift2csv_sense-table.R /nonexistent/missing.lift` (crash) | 1 | 0 bytes |

Six approved snapshots sit at zero bytes and are therefore untested in this specific way:

```
_snaps/entry-table_end-to-end/lela-teli-empty-lexicon.csv
_snaps/example-table_end-to-end/lela-teli-empty-lexicon.csv
_snaps/example-table_end-to-end/sena3-single-entry-plant.csv
_snaps/pronunciation-table_end-to-end/lela-teli-empty-lexicon.csv
_snaps/pronunciation-table_end-to-end/sena3-single-entry-plant.csv
_snaps/sense-table_end-to-end/lela-teli-empty-lexicon.csv
```

### The fix

Assert the exit status inside the helper. `system2()` already returns it — verified: `0` for the empty lexicon, `1` for the crash, with stdout redirected to a file in both cases. This is a two-line change to `helper-cli-snapshots.R`, and it closes the hole for **all 46 approved snapshots**, not only the six empty ones.

It also covers most of what [SKILL.md's typed-empty-tibble warning](../.claude/skills/adding-a-lift-field/SKILL.md#L104) guards against: a `map_df` over a zero-length list yields a **no-column** tibble, and the failure it describes — `left_join` erroring with "Join columns in 'x' must be present in the data" — is an R error, so it exits nonzero and the status check catches it. The residual gap is narrow and worth naming rather than glossing: a table whose empty path returns a no-column tibble *and* which has no downstream join would still emit zero bytes and exit 0. Nothing in the current four tables is in that position, and a new table's own snapshot review is the backstop.

**Skip-empty stays exactly as it is.** A table with no rows still gets no file under `--tables`, and `cat("")` still writes zero bytes on stdout. Those conventions were never the defect; the test method was. An earlier draft of this plan proposed making empty output non-empty (always emitting the header) to make the crash distinguishable — that was solving the right problem in the wrong place. It would have changed six snapshots and a spec rule to fix something a status check fixes for free, and it would have destroyed the property that makes a table folder readable: **the set of files present tells you what the lexicon actually contains.** No pronunciations, no `pronunciations.csv`.

### Why exit status and not stderr

Stderr is legitimately non-empty on correct runs, so it cannot be the gate. Measured: `lift2csv_example-table.R` on `sena3-example-duplicate-translation.lift` exits 0 having written 141 bytes to stderr —

```
Warning message:
Sense 9c29d3f5-...-a71ad81c0cc1 has an example with 2 translations; using the first (type=Literal translation).
```

That is the documented duplicate-translation warning working as designed, and `sena3.lift` produces the same class of warning on the sense table. Asserting "stderr is empty" would fail on correct runs; asserting "stderr contains no error" reduces to pattern-matching prose that the code is free to reword. Exit status is the process contract, it is already there, and it is unambiguous — this is also what [AGENTS.md's CLI Script Conventions](../AGENTS.md#cli-script-conventions) implies by reserving stderr for "progress, diagnostics, and errors" alike.

### Files

- `tests/testthat/helper-cli-snapshots.R` — `run_cli_to_file()` returns the status alongside the path; `expect_cli_stdout_file_snapshot()` asserts it is 0 before comparing the snapshot. Order matters: a status failure should be the reported error, not a confusing snapshot mismatch underneath it.
- **Promote `expect_cli_success()`** out of `test-csv2lift_table-discovery.R` into the helper file and reuse it, rather than writing a second status check beside it. Note the wrinkle its own comment already documents: `system2(stdout = TRUE)` signals success by the **absence** of a `"status"` attribute, whereas `system2(stdout = <file>)` returns the status as an integer. Two call shapes, two conventions — the helper should absorb both and say so in a comment, since this is precisely the trap that let the hole exist.
- `tests/testthat/test-lift2csv_end-to-end.R` — its `system2()` calls pass `stdout = FALSE, stderr = FALSE` and ignore the status too. Assert it there as well.
- `AGENTS.md`'s [Testing Approach](../AGENTS.md#testing-approach) — one line recording that CLI snapshot tests assert exit status, and why stderr is not asserted. This is a repo-wide testing convention, so it belongs here rather than in `SPEC.md`, per the split of concerns.

**No `SPEC.md` change, and no snapshot change.** R0 alters how the suite checks, not what the software does.

### TDD

1. **Red.** Add a test asserting the helper *rejects* a nonzero-exit invocation — `expect_failure(expect_cli_stdout_file_snapshot(<crashing invocation>, ...))` against a throwaway snapshot name. It fails today: the helper signals nothing, so there is no failure for `expect_failure()` to catch. That inversion is the hole, expressed as a test.
2. **Green.** Add the status assertion to the helper.
3. **Refactor.** Promote `expect_cli_success()` and de-duplicate the two status conventions behind it.

### Verification

- **Not one file under `_snaps/` changes** — all 46, all 7 directories. R0 adds an assertion; it must not move an artifact.
- `Rscript -e 'devtools::test()'` fully green, confirming all six zero-byte cases do exit 0 (spot-checked already: entry, sense, pronunciation ×2 and example ×2 on the empty-lexicon and single-entry-plant fixtures all return 0).
- The red test from step 1 passes, and stays in the suite as the regression guard.

## R1 · fold the four scripts into `lift2csv.R --table <name>`, and rename `--tables` to `--table-dir`

Add a second output mode to `scripts/lift2csv.R`: `--table <name>` writes exactly one registry table's CSV to **stdout**, byte-for-byte what `scripts/lift2csv_<name>-table.R` writes today, `cat("")` empty case included.

**And rename `--tables <dir>` to `--table-dir <dir>` in both directions**, `lift2csv.R` and `csv2lift.R` alike. `--table` beside `--tables` is a one-character difference carrying two quite different meanings — one table to stdout versus every table into a directory. `argparser` resolves the pair correctly (checked: `--table senses` sets `table` and leaves `tables` at `NA`, and the converse), so this is not a parser problem; it is a reader problem, and the parser being fine is exactly what makes it dangerous. `--table-dir` names what the value is.

Renaming in `csv2lift.R` too is not scope creep: [Phase T](remaining-lift-fields.md#phase-t--the-table-folder-convention) built the table folder as **one** convention spanning both directions, so leaving csv2lift on `--tables` would move the confusion from within one script to between two. `csv2lift.R --table-dir` also reads correctly alongside its per-table flags (`--entries`, `--senses`, …), which are unchanged.

**No deprecation alias.** `--tables` is removed outright, consistent with [T2](remaining-lift-fields.md#t2--drop-flat-mode-folder-only-discovery) deleting flat mode rather than deprecating it. Say so explicitly here so it is a decision rather than an oversight — if there are invocations outside this repo, this is the point to add an alias instead.

Minor consistency note: SPEC.md and the plans call this "the table folder convention" while the flag will say `dir`. Worth settling one way in R1's doc pass; I would move the prose to "table directory" and leave the flag short, since the flag is the surface users actually type.

### Why a second mode rather than reading from a table directory

**First, two arguments an earlier draft of this plan made that do not hold, recorded so they are not made again.**

*"You cannot approval-test a directory."* False. A directory is perfectly approval-testable: snapshot a **manifest** (the sorted list of filenames written) as an artifact in its own right, optionally alongside each present file's content. For the empty case a manifest is in fact **better** than what we have — absence from a manifest is unambiguous, whereas a zero-byte file is precisely the ambiguity [R0](#r0--assert-exit-status-in-the-cli-snapshot-helper) exists to resolve. The claim that the six zero-byte snapshots are "unreachable" from a directory run was wrong; they are reachable, just represented differently.

*"Test cost rules it out."* The figure quoted (+28 s per fixture) came from comparing one invocation against another instead of whole-suite against whole-suite, and ignored that the four per-table test files **share fixtures** — 24 invocations over only 8 distinct `.lift` files. Measured properly on `sena3.lift` (1462 entries / 1717 senses):

| | wall clock |
|---|---|
| today, per-table: entry 13.6 s + sense 21.1 s + example 6.7 s | **41.4 s** |
| one `--table-dir` run producing all four tables | **49.3 s** |

About **+8 s**, not +84 s, and R startup is only 0.63 s so batching saves nothing to offset it. The +8 s is `sena3.lift` paying for a pronunciation extraction that per-table curation currently skips. That is noise in a suite measured in minutes. The gap does widen with registry size — a unified run puts every fixture through every table's extractor, where curation does not — but that is a modest trend, not a blocker.

**What actually justifies `--table`,** having discarded those two:

**It keeps R1 a provable refactor.** With `--table`, all 24 per-table approved CSVs stay byte-identical, so "no artifact moved" is the verification. A manifest-and-digest restructure re-baselines every one of them, and re-approving 24 artifacts at once is exactly the situation where a genuine regression rides along unnoticed. That is a process argument rather than a technical one, and it is the strongest of the three.

**Per-table fixture curation is a documented design choice.** [SKILL.md](../.claude/skills/adding-a-lift-field/SKILL.md#L231) states fixture directories are "curated per table, not kept at parity" — a new table's directory carries only the fixtures that say something about it, which is why `lift2csv_pronunciation-table/` holds 4 files and `lift2csv_sense-table/` holds 7. A unified per-fixture digest dissolves that: every fixture is forced through every table.

**Single-table-to-stdout is a real capability**, advertised in the README. Without it, `--table senses > senses.csv` becomes "run everything, then go find the file".

None of these forbid the directory-digest design — they say it is a different change with its own merits, which is why it is written up under [Decisions to settle](#decisions-to-settle) rather than dismissed.

### Behaviour

- `--table <name>`: `name` must match a registry `name`. An unrecognised name is a **hard usage error listing the valid names**, mirroring `discover_tables()`'s unknown-CSV error — a typo must not exit 0 having printed nothing.
- `--table` and `--table-dir` together: usage error. They disagree about destination (stdout versus a directory) *and* about the empty case (zero bytes versus no file at all), so there is no coherent both.
- **Neither flag: usage error.** This is a latent bug fixed in passing, and it is in scope precisely because R1 makes the directory flag no longer the only mode. Today `Rscript scripts/lift2csv.R foo.lift` with no `--tables` writes `NA/entries.csv` and `NA/senses.csv` — a directory literally named `NA`, from `NA` flowing through `table_dir()` into `file.path()`. Confirmed by running it.

### Files

**Changed**

- `scripts/lift2csv.R` — the `--table` mode and the three guards above, plus a comment recording that the two modes differ deliberately in the empty case: stdout always produces *something* (zero bytes), a directory can omit the file entirely, and the omission is the signal. The existing skip-empty comment already explains half of this and should be extended rather than replaced.
- `tests/testthat/test-{entry,sense,pronunciation,example}-table_end-to-end.R` — `script_path` becomes `../../scripts/lift2csv.R` and the args gain `--table <name>`. **Filenames unchanged**, so no `_snaps/` directory moves. (Renaming them is [R3](#decisions-to-settle), deliberately not here.)
- `tests/testthat/test-lift2csv_end-to-end.R` — drop the per-table byte-comparison arm and the `per_table_script` list. Once both modes read through one `registry$read_fn` loop, "umbrella output equals per-table output" no longer tests anything: the bug class it guarded against stops existing rather than going untested. Keep the filename-set assertion, which is the umbrella's own contract and the *only* test of the skip-empty rule. Add coverage for the three new usage errors.
- `tests/testthat/test-csv2lift_end-to-end.R` and `tests/testthat/test-csv2lift_table-discovery.R` — both pass `--tables`; the latter also asserts on the error-message text. Their snapshots must not move.
- `scripts/csv2lift.R` — `--tables` becomes `--table-dir`: the `add_argument()` call, the `argv$tables` reads, and the "No entries CSV supplied: provide it as a positional argument, --entries, or via --tables <dir>" error message.
- `R/table_registry.R` — `discover_tables()`'s unknown-CSV error message names the flag too. Also the four `help` strings name scripts that will not exist. Rewrite as e.g. `"CSV of the entries table (see SPEC.md's Entry Table)"`.
- `README.md` — the five per-table lines at [README.md:24-28](../README.md#L24-L28) collapse to one `--table` example (keep one, not four: the point is that the flag is uniform across tables), and every `--tables` occurrence in both the lift2csv and csv2lift sections becomes `--table-dir`.
- `SPEC.md` — [line 181](../SPEC.md#L181) ("The per-table scripts … are unchanged and remain the tested public surface for one table at a time") is directly falsified; rewrite as the two modes of one script, keeping the skip-empty rule's description intact. [Line 132](../SPEC.md#L132) cites `lift2csv_sense-table.R` by name for the empty-CSV convention — repoint it at `--table`, leaving the rule itself unchanged. [Line 163](../SPEC.md#L163) attributes the join view to `lift2csv_join-sense-entry-table.R` — still correct, leave it.
- `.claude/skills/adding-a-lift-field/SKILL.md` — [line 239](../.claude/skills/adding-a-lift-field/SKILL.md#L239) (the `cat("")` convention: the rule survives, but it names a deleted script), [line 241](../.claude/skills/adding-a-lift-field/SKILL.md#L241) and [line 221](../.claude/skills/adding-a-lift-field/SKILL.md#L221) (stale-TODO grep example), and the per-table-script line in the new-table checklist. Also fold in the "CLI flag / attach-call order in `scripts/csv2lift.R`" staleness that [T2's notes](remaining-lift-fields.md#t2--drop-flat-mode-folder-only-discovery) already flagged as worth a pass before B1 — it predates the registry and is in the same paragraphs.
- `plans/remaining-lift-fields.md` — the round-trip spot check at [line 296](remaining-lift-fields.md#L296) invokes two deleted scripts, and the [Files touched](remaining-lift-fields.md#files-touched-pattern-per-increment) grid still lists `scripts/lift2csv_<name>-table.R` as per-table work. Update both, and add a line noting this plan superseded them.

**Deleted**

- `scripts/lift2csv_entry-table.R` (also carrying a stale TODO about `variant`/`etymology` that Phase B answers)
- `scripts/lift2csv_sense-table.R`
- `scripts/lift2csv_pronunciation-table.R`
- `scripts/lift2csv_example-table.R`

**Explicitly kept**

`scripts/lift2csv_join-sense-entry-table.R` stays, with its test and its 5 snapshots. [T1 settled](remaining-lift-fields.md#the-registry) that the join view is not a registry row — it is a derived view, csv2lift does not accept it, and it must not appear in a table folder. It therefore has no `--table` name to be reached by, and folding it in would mean inventing a registry entry that `--tables` must then be taught to skip. Its boilerplate is the price of it being genuinely different.

`plans/old/*` references are history and are left alone, per [AGENTS.md's Markdown Conventions](../AGENTS.md#markdown-conventions).

### TDD

A real red is available, so use it rather than treating this as untestable refactoring:

1. **Red.** Repoint all four per-table test files at `lift2csv.R --table <name>` before the flag exists. All 24 snapshot tests fail — argparser rejects the unknown flag, the script writes nothing, and every snapshot comparison sees an empty file. Add the three usage-error tests to `test-lift2csv_end-to-end.R`; they fail too.
2. **Green.** Implement `--table` plus the three guards in `scripts/lift2csv.R`. All 24 return to passing **with no `.new` file produced** — that is the assertion, not a snapshot diff to review.
3. **Refactor.** Delete the four scripts, then update docs. Deleting last means the suite is green across the deletion, so anything that still depended on them fails loudly.

### Verification

- **The load-bearing invariant: not one file under `tests/testthat/_snaps/` changes.** All 46 approved files, all 7 directories. Prove it, don't assert it — `git status --porcelain tests/testthat/_snaps/` empty, and `find tests/testthat/_snaps -name '*.new'` empty, after a full run.
- `Rscript -e 'devtools::test()'` fully green.
- `Rscript scripts/lift2csv.R <fixture>.lift --table senses` byte-identical to `git show HEAD:scripts/lift2csv_sense-table.R`'s output for the same fixture, checked on `sena3.lift` (largest) and `lela-teli-empty-lexicon.lift` (the empty case, which must still be exactly zero bytes). R0 changes no output, so the pre-R0 scripts are a valid baseline here.
- The three usage errors each exit nonzero with a message naming the problem, and `--table typo` lists the valid names.
- **The rename must be provably cosmetic.** Every `csv2lift_end-to-end` snapshot byte-identical, and `--table-dir` accepted with and without a trailing slash exactly as `--tables` was ([T2](remaining-lift-fields.md#t2--drop-flat-mode-folder-only-discovery) made that equivalence a tested property, so the test survives the rename rather than being rewritten).
- `grep -rn '\-\-tables' --include='*.R' --include='*.md' . | grep -v '^./plans/'` returns nothing: the flag is gone from code and live docs, and error-message text was renamed along with the flag rather than left describing a flag that no longer exists.
- Post-deletion grep, run **after** the files are gone rather than from a list assembled before — [T3's stated lesson](remaining-lift-fields.md#t3--normalise-fixture-names-to-kebab-case) after a hardcoded reference survived a pre-move grep:
  ```bash
  grep -rn "lift2csv_entry-table\.R\|lift2csv_sense-table\.R\|lift2csv_pronunciation-table\.R\|lift2csv_example-table\.R" \
    --include="*.R" --include="*.md" . | grep -v "^./plans/old/"
  ```
  Expected: no hits outside `plans/old/`.

## R2 · delete the registry's two dead fields

`R/table_registry.R` sets `fk` and `creates_doc`. **Nothing reads either** — `grep -rn "creates_doc\|\$fk"` over `R/`, `scripts/` and `tests/` returns only the two assignment lines. Both are documentation written in the wrong place.

- `fk` was already flagged in [T1's notes](remaining-lift-fields.md#the-registry) as "a mild smell that should either earn its keep in a later increment or be deleted rather than left as decoration". It has not earned it, and it is now known to be the **wrong shape** for what is coming: [C1's traits table](remaining-lift-fields.md#phase-c--traits-then-the-two-trait-bearing-tables) has two foreign keys (`entry_id` *and* `sense_guid`), which a single-value field cannot express. Keeping it means C1 must either widen it or lie in it.
- `creates_doc` is the same case and was never flagged. `entries` is distinguished in practice by its `attach_fn` ignoring the incoming `doc`, and by being row 1 of an ordered registry — the boolean restates that without being consulted.

Nothing is lost: `SPEC.md` documents every table's keys properly and in more detail than a registry column can ([Sense Table](../SPEC.md#sense-table), [Pronunciation Table](../SPEC.md#pronunciation-table), [Example Table](../SPEC.md#example-table), and [Structural rules](../SPEC.md#structural-rules-csv2lift-direction)'s fail-fast paragraph).

**No TDD red is available here, and inventing one would be dishonest** — dead code has no failing test by definition. The verification is the grep above proving no reader exists, plus a fully green `devtools::test()` with **no test file and no snapshot touched at all**. If any test changes, the fields were not dead and R2 is wrong.

Kept separate from R1 so R1's "no snapshot changed" claim is checked against an otherwise-untouched tree.

## Decisions to settle

**R3 (proposed, not approved) · drop the `_end-to-end` suffix from test filenames.** Measured, the suffix does not mean what it says:

| | files | owns a `_snaps/` dir | actually end-to-end |
|---|---|---|---|
| with `_end-to-end` | 7 | 7 | 6 |
| without | 4 | 0 | 3 |

It correlates *perfectly* with owning approved snapshots and only *loosely* with being end-to-end. `test-csv2lift_table-discovery.R` spawns `Rscript scripts/csv2lift.R` five times with no suffix; `test-copy-lift-entries_end-to-end.R` carries a non-snapshot error-path test. Only `test-multitext-span-markup.R` and `test-example-source-note-redundancy.R` are genuinely unit-level, and both already say so in their header comments — better documentation than a filename could be. So the suffix labels the wrong axis, and 9 of 11 files being end-to-end makes it near-uninformative anyway.

**Sequence it after R1, never with it.** R1's whole verification is that no snapshot moved; a simultaneous rename moves all 46 and makes that unreadable. R1 also *changes what these files cover* — all four per-table tests will point at `lift2csv.R` — so the right names are only knowable afterwards.

Sub-decision, open: whether R3 is a **plain suffix drop** (`test-sense-table.R`, `_snaps/sense-table/`) or also **realigns the names on what they now cover** (`test-lift2csv_senses.R`, with the umbrella as `test-lift2csv_tables.R`). The second is more honest post-R1 — every one of those files tests `scripts/lift2csv.R` — but it is a larger rename and touches more prose. Either way the cost is 46 approved files moving across 7 directories with **byte-identical content**, so git detects renames rather than delete+add, exactly as [T2's fold-in](remaining-lift-fields.md#t2--drop-flat-mode-folder-only-discovery) did. Prose to update: `AGENTS.md`'s Testing Approach (2 mentions, including the `_snaps/<test-file>/` path convention and the `snapshot_accept("entry-table_end-to-end/")` example), `SKILL.md` (14), `plans/remaining-lift-fields.md` (20), plus the `test_that()` label strings inside each file, which embed the suffix too.

**Also open (raised while costing R1) · approval-test the directory instead of the table.** The alternative to `--table` is to snapshot a **manifest** of the filenames `--table-dir` wrote, per fixture, optionally with each file's content in one digest artifact. This was initially dismissed on two grounds that turned out to be false — see [R1's opening](#why-a-second-mode-rather-than-reading-from-a-table-directory) — so it deserves recording as a live option rather than a closed one.

In its favour: absence-from-a-manifest is a cleaner assertion of the empty case than a zero-byte file; the four per-table test files collapse into one; and it would drop the per-table snapshot count from 24 artifacts to 8. Against: it re-baselines all 24 approved CSVs at once, which is where a real regression hides; it dissolves the documented per-table fixture curation; it costs about +8 s of suite time now and more per table added; and it removes single-table-to-stdout unless `--table` is kept anyway.

Sequencing, if it is wanted: **after** R1, never instead of it. R1 with `--table` reaches the same end state (one script, registry-driven, four boilerplate files gone) while keeping every artifact byte-identical — so it can be verified. Restructuring the artifacts afterwards is then a change whose diff is *only* the restructuring, reviewed on its own. Doing both at once means neither is checkable. This also naturally pairs with [R3](#decisions-to-settle) above, since both are about how the test suite is organised rather than what the software does.

**Not proposed: de-duplicating the script bootstrap.** The 5-line `script_path`/`project_dir`/`devtools::load_all()` preamble is identical in every script in `scripts/`. Sharing it needs the same path logic to locate the shared file, trading duplication for indirection at no gain — and R1 removes four of the copies anyway.

## What this buys Phase B

Per new table, before: `R/<name>_table.R`, `R/<name>_helpers.R`, `R/csv2lift_<name>.R`, **`scripts/lift2csv_<name>-table.R`**, `tests/testthat/test-<name>-table_end-to-end.R`, a curated fixture directory, a registry row, a SPEC.md section.

After R1 the bolded item is gone — the registry row supplies it, the same way Phase T made the row supply the CLI flag, the attach call, the `requires` guard and the test-loop glob. Six queued tables, so six fewer boilerplate files, and one fewer place for a new table to be half-wired.
