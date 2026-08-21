# AGENTS.md

Guidance for human and AI contributors working in this repository.

## Scope

- This file applies to the whole repository.

## Core Principles

- Prefer common, well-maintained libraries and packages over custom ad hoc logic.
- Keep changes focused and minimal for the requested task.
- Do not modify unrelated files.

## Specification

- `SPEC.md` is the source of truth for the CSV↔LIFT data model (tables, keys, column-naming, LIFT structural conventions shared by lift2csv and csv2lift).
- Whenever a change alters or clarifies a rule `SPEC.md` covers, update `SPEC.md` in the same change — do not let it drift out of sync with the code.
- If code and `SPEC.md` disagree, that is a bug: fix whichever is wrong, do not silently favour one.
- Do not speculatively extend `SPEC.md` to cover tables or features that aren't implemented yet; add to it incrementally as each is actually built (see [SPEC.md's Not Yet Specified section](SPEC.md#not-yet-specified)).
- **Split of concerns:** `AGENTS.md` documents how to work in this repo (process, conventions, workflow). `SPEC.md` documents what the software does and guarantees (the CSV↔LIFT data model). Repo-wide engineering conventions that happen to describe behaviour (e.g. stdout/stderr separation) stay in `AGENTS.md` since they apply uniformly across scripts; `SPEC.md` is reserved for the CSV↔LIFT contract specifically.

## Skills

Task-specific procedures live under `.claude/skills/<name>/SKILL.md` rather than in this file, so `AGENTS.md` stays a set of always-applicable rules. Add a new skill when a procedure is followed occasionally rather than always.

- `adding-a-lift-field` — end-to-end procedure for supporting a new LIFT element in both directions (read direction first, then reuse its CSV output as the write direction's fixture).

## Markdown Conventions

- **Don't number Markdown headings** (`## 3. Entry table`, `## 1. Decide where it lives`) in any file in this repo — `SPEC.md`, skills (`SKILL.md`), and other reference docs — unless there's a specific reason a given file needs it. A numbered heading shifts whenever a section is inserted or reordered above it, silently breaking every cross-reference to that section, both within the file and in every other file that cites it.
- **Reference a heading elsewhere by Markdown anchor link and its actual name, not a number**: `[SPEC.md's Entry Table](SPEC.md#entry-table)`, not `SPEC.md §3`; `[the "Decide where it lives" step](.claude/skills/adding-a-lift-field/SKILL.md#decide-where-it-lives-a-column-or-a-table-of-its-own)`, not `SKILL.md §1`. An anchor link survives reordering; only a heading rename breaks it, and that's a one-time, greppable fix (`grep -rn '#anchor-slug'`) rather than a renumbering cascade. When renaming a heading that other files link into, grep the repo for its old anchor slug and update every match.
- **Exception: `plans/*.md` keep whatever numbering they already have.** A plan is a point-in-time historical record, not a live document — one that narrates a past renumbering (e.g. "renumbers §6–§9 → §7–§10") is describing history, and rewriting it to match current headings would falsify that history. Don't retroactively edit a plan's own numbering or its `SPEC.md §N` / `SKILL.md §N` citations; write new plans following the anchor-link convention above instead.

## Working Style

- Before changing behaviour, check existing patterns in nearby files and follow them.
- When behaviour changes are non-trivial, ask for confirmation before implementing.
- If a requirement is ambiguous and could alter behaviour, ask a clarifying yes/no question first.
- Ask clarifying questions in plain chat text, not via a multiple-choice/quick-answer UI widget.
- Save non-trivial implementation plans to `plans/<descriptive-name>.md` in the repo (not only wherever the tool's own ephemeral plan-mode file lives), so they're preserved and reviewable via git history. This is not a one-time save: whenever the plan is revised (e.g. new information surfaces mid-planning), re-sync `plans/<name>.md` with the latest approved version before or immediately after implementation starts.

## Libraries And Dependencies

- Reuse existing dependencies and idioms already present in the repo when possible.
- Add a new package only when it clearly improves reliability, readability, or maintainability.
- Prefer widely adopted packages over hand-rolled implementations.

## R Code Conventions

- Add brief comments for non-obvious logic so future readers can follow intent.
- Prefer tidyverse idioms (`purrr`, `dplyr`, `stringr`, `tibble`) for iteration and data manipulation. Base R is fine for scalar NA/blank checks (`is.na(x) || !nzchar(x)`) and simple control flow, where a tidyverse equivalent wouldn't add clarity.

## CLI Script Conventions

- For scripts that emit machine-readable output:
  - Write result content only to stdout.
  - Write progress, diagnostics, and errors to stderr.

## Testing Approach

- Prefer native `testthat` snapshot tests for CLI and file-conversion workflows when outputs are large or awkward to assert inline.
- Keep input fixtures under `tests/testthat/fixtures/<script>/` and let `testthat` manage approved artifacts under `tests/testthat/_snaps/`.
- **Test filenames don't carry an `_end-to-end` suffix.** Nearly every CLI test in this suite is end-to-end (it spawns the real script via `Rscript`), so the suffix distinguished almost nothing and correlated with "owns a `_snaps/` directory" more than with actually being end-to-end — a non-snapshot test like `test-csv2lift_table-discovery.R` never carried it. A file that is genuinely unit-level (no subprocess, no snapshot) should say so in its own header comment instead, which is more informative than a filename tag (see `test-multitext-span-markup.R`).
- **Per-table CLI approval tests go through `expect_table_snapshots()`** (`tests/testthat/helper-cli-snapshots.R`), so each per-table test file is one call rather than a hand-copied loop. Keep **one test file per table**: a `_snaps/` directory is named after the test file and snapshot names cannot nest (`name = "entries/x.csv"` warns and writes nothing), and `snapshot_accept()`'s `files` matching is exact with no globbing — so a single shared directory could only ever be accepted whole, losing per-table review. `test-join-sense-entry-table.R` keeps its own loop: it drives a different script and takes no `--table` flag.
- Use `testthat::expect_snapshot_file()` (via the `expect_cli_stdout_file_snapshot()` helper in `tests/testthat/helper-cli-snapshots.R`) for CLI output, not `expect_snapshot()`. This stores each approved artifact as its own raw file (e.g. `_snaps/<test-file>/<fixture>.csv`) instead of wrapping it in a markdown fence, while keeping the same `.new`/review/accept workflow.
- CLI snapshot tests **assert the process exit status is 0** before comparing the snapshot (`expect_cli_success()` / `expect_cli_stdout_file_snapshot()` in `tests/testthat/helper-cli-snapshots.R`). Without it a script that dies before writing anything leaves zero bytes on stdout, which is byte-identical to the approved snapshot of a legitimately empty table — the test passes, and on a first run it will even auto-approve the crash as the new baseline. Do **not** assert that stderr is empty instead: warnings are legitimate output on a successful run (e.g. the duplicate-translation warning `sena3-example-duplicate-translation.lift` produces), so stderr cannot distinguish success from failure. Note `system2()` reports status two ways — an integer when `stdout` is a file, a `"status"` attribute present only on failure when `stdout = TRUE` — which `cli_status()` normalises.
- Follow the Emily Bache approval-testing workflow: checked-in snapshots are the approved artifacts, and `.new` snapshot files are the review artifacts.
- Keep snapshot artifacts human-reviewable and deterministic so diffs are meaningful.
- Do not auto-accept snapshot changes; review them explicitly with `testthat::snapshot_review()` or `testthat::snapshot_accept()`.
- `tests/testthat/setup.R` sets `NOT_CRAN=true` when unset. Both `expect_snapshot()` and `expect_snapshot_file()` silently skip otherwise (only `devtools::test()` sets this for you automatically) — without it, a bare `Rscript -e 'testthat::test_dir(...)'` run or a naive CI script would report all-green while skipping every snapshot-based test.
- Run tests with `devtools::test()` (optionally `devtools::test(filter = "some-regex")` to scope to matching test files) rather than a raw `testthat::test_file()`/`test_dir()` call — `expect_snapshot_file()` requires testthat's 3rd edition, which a raw call doesn't enable and fails with "requires 3rd edition", whereas `devtools::test()` sets it up correctly alongside `NOT_CRAN`.
- When a fixture has no existing snapshot yet, `expect_snapshot_file()` creates one automatically on first run with a WARN (not a FAIL) instead of producing a `.new` file to diff. That auto-created file is just whatever the current code happens to output, not a vetted-correct baseline — read it before trusting it, especially when using it as the TDD "red" reference for a not-yet-implemented behaviour.
- `testthat::snapshot_accept()` / `snapshot_reject()` / `snapshot_review()`'s `files` argument needs a trailing slash to match a snapshot directory, e.g. `snapshot_accept("entry-table/")`. Passing the bare name (`"entry-table"`) matches nothing and silently reports "No snapshots to update" — it does not error, so double-check the accept actually took effect (re-run the tests) rather than trusting the one-line output.
- Follow TDD for behaviour changes: add/extend the fixture and confirm the corresponding test fails first (red), write the minimum implementation to make it pass (green), then refactor with the tests as a safety net before considering the change done.

