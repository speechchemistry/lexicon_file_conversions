# Plan: consolidate the per-table lift2csv scripts into the registry

## Context

[Phase T](remaining-lift-fields.md#phase-t--the-table-folder-convention) built `R/table_registry.R` as the single source of truth for which CSV tables the round trip knows about, and `scripts/lift2csv.R --tables <dir>` as the read-side umbrella over it. T1 deliberately left the five per-table `scripts/lift2csv_*.R` scripts in place — "they are the tested public surface, and each is a one-liner over its `read_fn`; the umbrella is additive."

That was right at the time. It stops being right at [Phase B](remaining-lift-fields.md#phase-b--new-tables-whose-data-is-already-in-the-repo), because six more tables are queued (`reversals`, `etymologies`, `traits`, `variants`, `entry-relations`, `sense-relations`) and each one currently costs a hand-copied 20-line script whose only per-table content is a function name and a help string. This plan removes that per-increment cost before the six increments rather than after, on the same reasoning that put Phase T ahead of them.

Five increments, deliberately separable: **R0** closes a hole in the CLI snapshot helper that lets a crashed script pass as a correct empty result; **R1** folds the four registry-table scripts into `lift2csv.R` and renames `--tables` to `--table-dir` in both directions; **R2** deletes two registry fields nothing reads; **R3** drops the `_end-to-end` suffix from test filenames; **R4** folds the four per-table test files' shared loop into a helper.

No increment here is a skill run — like Phase T, this is CLI infrastructure, not a field.

**Status: R0, R1, R2, R3 and R4 done — sequence complete. Next: Phase B (B1).** R0 came first because it strengthens the safety net R1 and R2 lean on: both assert that nothing under `_snaps/` moved, and that assertion is only worth as much as the tests behind it. R3 was sequenced last, after R1 changed what the per-table test files cover, and executed as the **plain suffix drop** (`test-sense-table.R`, `_snaps/sense-table/`) rather than the fuller `test-lift2csv_<name>.R` realignment also considered under [Decisions to settle](#decisions-to-settle) — every rename this increment made is confirmed by `git status` as a clean rename (byte-identical content), and the full suite is green with zero `_snaps/` content changes across all four increments. **R4 was added after those four had landed**, when the directory-digest option under [Decisions to settle](#decisions-to-settle) was re-examined and declined: R0 and R1 had between them already delivered what that option was really for, leaving only the per-table test-file duplication it would have removed as a side effect — which R4 removes directly, and without moving an artifact. It is sequenced before B1 for the same reason R1 was: it removes a per-table cost that six queued tables would otherwise each pay. R4 landed as planned, and is the only increment here that moved no artifact at all: the 29 `*-table` tests kept byte-identical labels and the full suite (71 tests, 100 expectations) is green with `git status --porcelain tests/testthat/_snaps/` empty.

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

## R3 · drop the `_end-to-end` suffix from test filenames

Measured, the suffix does not mean what it says:

| | files | owns a `_snaps/` dir | actually end-to-end |
|---|---|---|---|
| with `_end-to-end` | 7 | 7 | 6 |
| without | 4 | 0 | 3 |

It correlates *perfectly* with owning approved snapshots and only *loosely* with being end-to-end. `test-csv2lift_table-discovery.R` spawns `Rscript scripts/csv2lift.R` five times with no suffix; `test-copy-lift-entries_end-to-end.R` carries a non-snapshot error-path test. Only `test-multitext-span-markup.R` and `test-example-source-note-redundancy.R` are genuinely unit-level, and both already say so in their header comments — better documentation than a filename could be. So the suffix labels the wrong axis, and 9 of 11 files being end-to-end makes it near-uninformative anyway.

**Sequenced after R1, not with it.** R1's whole verification is that no snapshot moved; a simultaneous rename moves all 46 and makes that unreadable. R1 also *changes what these files cover* — all four per-table tests now point at `lift2csv.R` — so the right names were only knowable afterwards.

**Decided: a plain suffix drop** (`test-sense-table.R`, `_snaps/sense-table/`), not the fuller realignment onto `test-lift2csv_<name>.R` that was also on the table. Every one of the four per-table files does test `lift2csv.R` post-R1, which would have made that realignment more honest — but it is a larger rename touching more prose for a naming question that isn't this plan's central concern, and the table name (`sense-table`, `entry-table`, ...) is what actually distinguishes these files from each other; a constant `lift2csv_` prefix would not.

### What was renamed

8 test files, matching 7 `_snaps/` directories (`test-lift2csv.R` never owned one, since R1 removed its byte-comparison snapshot arm):

| before | after |
|---|---|
| `test-entry-table_end-to-end.R` | `test-entry-table.R` |
| `test-sense-table_end-to-end.R` | `test-sense-table.R` |
| `test-pronunciation-table_end-to-end.R` | `test-pronunciation-table.R` |
| `test-example-table_end-to-end.R` | `test-example-table.R` |
| `test-join-sense-entry-table_end-to-end.R` | `test-join-sense-entry-table.R` |
| `test-csv2lift_end-to-end.R` | `test-csv2lift.R` |
| `test-copy-lift-entries_end-to-end.R` | `test-copy-lift-entries.R` |
| `test-lift2csv_end-to-end.R` | `test-lift2csv.R` |

`_snaps/<name>_end-to-end/` → `_snaps/<name>/` for the first seven. `test-csv2lift_table-discovery.R`, `test-example-source-note-redundancy.R`, `test-multitext-span-markup.R` and R0's `test-cli-snapshot-helper.R` already carried no suffix and are untouched.

### Files

- The 8 renames and 7 directory renames above, done via `git mv` so git records them as renames against byte-identical content rather than delete+add.
- Each renamed file's own `test_that()` label strings — e.g. `paste0("entry-table_end-to-end_", stem)` → `paste0("entry-table_", stem)` — since a stale suffix baked into a test's own description is the same problem as one baked into its filename.
- `AGENTS.md`'s Testing Approach: the `snapshot_accept("entry-table_end-to-end/")` example repointed at `entry-table/`, plus a new bullet recording the naming convention itself (why there is no suffix) so the next test file follows it without re-deriving the reasoning here.
- `.claude/skills/adding-a-lift-field/SKILL.md`: every literal `<name>_end-to-end` reference — the read-direction filter example, the snapshot-accept commands, the fixture-copy paths, the write-direction filter, and the new-table checklist's `test-<name>-table_end-to-end.R` template name.
- `plans/remaining-lift-fields.md`: the **forward-looking** references only — B1's script list, the coverage-hole note, the per-field Verification recipe's three `filter=`/`snapshot_accept()` calls, and the "file drop" consequence of Phase T. The **historical** T1/T2/T3 narrative describing what the files were called at the time is left as written, per [AGENTS.md's Markdown Conventions](../AGENTS.md#markdown-conventions) treating a plan as a point-in-time record, with one note added marking that the live names changed here.

### Verification

- Every rename shows as `R` (rename, not delete+add) in `git status --porcelain`, for all 8 files and all 46 snapshot artifacts.
- Full `Rscript -e 'devtools::test()'` green immediately after the `git mv`s and label-string edits, before touching any prose — proving the rename alone is behaviour-neutral.
- `grep -rn "end-to-end\|end_to_end" tests/testthat/*.R .claude/skills/adding-a-lift-field/SKILL.md AGENTS.md` clean (aside from AGENTS.md's unrelated use of "end-to-end" to describe the `adding-a-lift-field` skill itself, and `remaining-lift-fields.md`'s historical narrative, checked separately by hand since its exemption is deliberate, not an oversight).

## R4 · collapse the per-table test files onto a shared helper

Post-R1 the four per-table test files are byte-identical except for two strings — the fixture directory and the `--table` name:

```r
fixture_dir <- testthat::test_path("fixtures", "lift2csv_entry-table")
script_path <- "../../scripts/lift2csv.R"

for (input_path in fixture_inputs(fixture_dir)) {
  stem <- fixture_stem(input_path)

  test_that(paste0("entry-table_", stem), {
    expect_cli_stdout_file_snapshot(script_path, c(input_path, "--table", "entries"), name = paste0(stem, ".csv"))
  })
}
```

That is the same duplication R1 removed from `scripts/`, one directory over: nine lines hand-copied per table, two of which carry content. Six queued Phase B tables means six more copies, and the loop / `fixture_stem` / `paste0` scaffolding is exactly what a copy gets half-right. Move the loop into `helper-cli-snapshots.R` and each file reduces to its two facts:

```r
# tests/testthat/test-entry-table.R
# Approval tests for `lift2csv.R --table entries`, one per curated fixture.
expect_table_snapshots("entries", "lift2csv_entry-table")
```

### Why one thin file per table, and not one file for all four

The tempting version — a single `test-registry-tables.R` looping over `table_registry()` — is the [declined directory-digest decision](#decisions-to-settle) in a smaller costume, and it fails on two **measured** properties of testthat 3.3.2:

**A snapshot directory is named after the test file, and cannot nest.** `expect_snapshot_file(name = "entries/sena3.csv")` does not create `_snaps/registry-tables/entries/`. It emits `cannot create file '_snaps/…/entries/one.csv', reason 'No such file or directory'` and then reports `Adding new file snapshot` anyway — both as **warnings, not failures**, having written nothing. So one test file means one flat directory, and the 24 artifacts would have to be renamed `entries-sena3.csv`, `senses-sena3.csv`, … to avoid colliding on shared fixture stems (`lela-teli-empty-lexicon` occurs in all four).

**`snapshot_accept()`'s `files` matching is exact, with no globbing.** `testthat:::snapshot_meta()` filters on `out$name %in% files | out$test %in% dirs` — so `snapshot_accept("entry-table/")` works today precisely because `entry-table` *is* a directory, while `snapshot_accept("registry-tables/entries-*")` would match nothing and report "No snapshots to update" rather than erroring (the same trap [AGENTS.md's Testing Approach](../AGENTS.md#testing-approach) already documents for the missing trailing slash). Review granularity would collapse to all-24-or-nothing, in a repo whose entire method is per-table approval.

Keeping one file per table keeps `_snaps/<name>-table/` intact, so **no artifact moves at all** — a stronger invariant than R1's or R3's, both of which moved or renamed files while preserving content.

**A registry loop would also be wrong on the merits**, not merely awkward: `fixture_inputs()` errors on a directory with no `.lift` files, so looping the registry would force every table to have a curated fixture directory before its row could land, coupling test scaffolding to registry membership. Phase B adds rows one at a time; a per-table file should appear exactly when that table's fixtures do.

### Behaviour

`expect_table_snapshots(table, fixture_dir, script_path = "../../scripts/lift2csv.R")`:

- Test labels stay **byte-identical to today's**, by deriving the prefix from the fixture directory rather than the table name: `sub("^lift2csv_", "", fixture_dir)` yields `entry-table`, so the label is still `entry-table_sena3` and not `entries_sena3`. [R3](#r3--drop-the-_end-to-end-suffix-from-test-filenames) has just settled these labels; R4 must not churn them again.
- Snapshot names stay `<stem>.csv`, unchanged.
- Both arguments are required, and neither is derived from the other: `entries` → `lift2csv_entry-table` needs irregular singularisation (`entries`→`entry` where `senses`→`sense`), and a rule for that would be more machinery than the two-argument call it replaces.
- **No check that `table` is a registry name.** A typo already fails loudly end-to-end — R1 made `--table bogus` a nonzero-exit usage error listing the valid names, and R0 made the helper assert exit status — so a second guard in the helper would duplicate one that is already tested.

Verified in a throwaway package that `test_that()` calls issued from a helper function at a test file's top level register normally and keep the calling file's own `_snaps/` directory. They do report their location as `test-entry-table.R:1:1`, which is the only line such a file has.

### Files

- `tests/testthat/helper-cli-snapshots.R` — add `expect_table_snapshots()`, with a comment recording *why* it is called once per file instead of looped over the registry (the two measured testthat properties above). That is precisely the refactor a later reader would otherwise "finish".
- `tests/testthat/test-{entry,sense,pronunciation,example}-table.R` — each reduced to a header comment plus one call. **Filenames unchanged**, so no `_snaps/` directory moves.
- `.claude/skills/adding-a-lift-field/SKILL.md` — the new-table checklist's test-file step becomes "add a two-line `test-<name>-table.R` calling `expect_table_snapshots()`", and the read-direction worked example shows the call rather than the loop. This is the increment's whole payoff, so it has to land in the skill or Phase B will not see it.
- `AGENTS.md`'s [Testing Approach](../AGENTS.md#testing-approach) — one bullet: per-table CLI approval tests go through `expect_table_snapshots()`, one file per table so each keeps its own `_snaps/` directory, and why (snapshot names cannot nest; `snapshot_accept()` is exact-match).

**Not changed: `tests/testthat/test-join-sense-entry-table.R`.** It drives `scripts/lift2csv_join-sense-entry-table.R` with no `--table` flag, for the same reason R1 kept that script — the join view is a derived view, not a registry row. Routing it through `script_path` would leave the helper's `table` argument meaningless for one caller.

**No `SPEC.md` change, and no snapshot change.** Like R0, R4 alters how the suite is written, not what the software does.

### TDD

**No honest red is available** — this is a behaviour-preserving test refactor, the same situation as [R2](#r2--delete-the-registrys-two-dead-fields), and manufacturing a failing test for it would be theatre. The invariance check takes its place, and is stronger than a red would be:

1. Add `expect_table_snapshots()` alongside the existing four files, unused. Suite green, nothing moved.
2. Convert **one** file, `test-entry-table.R`, and run the suite: its 7 tests must pass with the **same labels** and **zero `.new` files**. That single conversion is where a mistake shows; the other three are then mechanical.
3. Convert the remaining three, then the docs.

### Verification

- **Not one file under `tests/testthat/_snaps/` changes, and none moves** — `git status --porcelain tests/testthat/_snaps/` empty, `find tests/testthat/_snaps -name '*.new'` empty. R4 is the first increment in this sequence to touch no artifact at all, not even by rename.
- `Rscript -e 'devtools::test()'` fully green with the **test-label list unchanged**. Capture it before and after and diff it rather than eyeballing the count — a silently renamed label is exactly what deriving the prefix from the wrong argument produces, and it would still be green.
- Each converted file is ≤ 3 lines, and `grep -n "fixture_inputs\|fixture_stem\|--table" tests/testthat/test-*-table.R` returns hits only in `test-join-sense-entry-table.R`, proving the loop moved rather than being copied.

## Decisions to settle

**Declined · approval-test the directory instead of the table.** The alternative to `--table` was to snapshot a **manifest** of the filenames `--table-dir` wrote, per fixture, optionally with each file's content in one digest artifact. It was recorded here as live rather than closed because the two grounds an earlier draft dismissed it on turned out to be false — see [R1's opening](#why-a-second-mode-rather-than-reading-from-a-table-directory). Re-examined once R0–R3 had landed and before Phase B starts — the last point at which it would be cheap — it is **declined**, because what R0 and R1 actually shipped took most of its substance:

- **Its best argument is spent.** "Absence from a manifest beats a zero-byte file" mattered because a zero-byte snapshot could not distinguish a correctly empty table from a crash. [R0](#r0--assert-exit-status-in-the-cli-snapshot-helper) closed exactly that by asserting exit status, so the ambiguity the manifest was going to resolve no longer exists.
- **The manifest already exists**, in a better form. R1 added `expect_lift2csv_table_dir_writes()` to `test-lift2csv.R`, asserting the exact set of filenames written across three fixtures chosen for the three cases (pronunciations but no examples, examples but no pronunciations, empty lexicon). The expected filenames are readable in the test file rather than needing a diff of an approved artifact to interpret.
- **`--table` is not going away**, so "it removes single-table-to-stdout unless `--table` is kept anyway" is moot — it is implemented, tested, and cited from the registry's `help` strings and the README.

What remained in favour was only artifact-count reduction — four test files to one, 24 approved CSVs to 8 — bought at a price that grows with Phase B: the curated fixture directories (7 / 7 / 6 / 4 files, deliberately not at parity) dissolve; a unified run puts every fixture through every table's extractor, so the measured +8 s at four tables is roughly ×2.5 at ten; and diff locality goes, since a change to the entry extractor would surface in all 8 fixture digests instead of `_snaps/entry-table/`'s 7 alone. Re-baselining 24 artifacts at once — 60 after Phase B — to buy that is the wrong trade, and the timing argument cuts the same way: because the cost only ever rises, "not now" is "not ever" rather than "later".

The duplication that motivated it is real, though. [R4](#r4--collapse-the-per-table-test-files-onto-a-shared-helper) removes that instead, and pays none of the above: the four files shrink to two lines each behind a shared helper, and not one artifact moves.

**Not proposed: de-duplicating the script bootstrap.** The 5-line `script_path`/`project_dir`/`devtools::load_all()` preamble is identical in every script in `scripts/`. Sharing it needs the same path logic to locate the shared file, trading duplication for indirection at no gain — and R1 removes four of the copies anyway.

## What this buys Phase B

Per new table, before: `R/<name>_table.R`, `R/<name>_helpers.R`, `R/csv2lift_<name>.R`, **`scripts/lift2csv_<name>-table.R`**, a hand-copied 10-line **`tests/testthat/test-<name>-table_end-to-end.R`**, a curated fixture directory, a registry row, a SPEC.md section.

After R1 the first bolded item is gone — the registry row supplies it, the same way Phase T made the row supply the CLI flag, the attach call, the `requires` guard and the test-loop glob. Six queued tables, so six fewer boilerplate files, and one fewer place for a new table to be half-wired. After R4 the second shrinks from ten hand-copied lines to two, which is the same saving applied to the one per-table file that has to keep existing (see [why one thin file per table](#why-one-thin-file-per-table-and-not-one-file-for-all-four)). What is left per table is genuinely per-table: the extractors, the fixtures, the row, the spec section.
