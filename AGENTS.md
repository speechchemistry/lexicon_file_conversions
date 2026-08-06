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
- Do not speculatively extend `SPEC.md` to cover tables or features that aren't implemented yet; add to it incrementally as each is actually built (see `SPEC.md` §8, "Not yet specified").
- **Split of concerns:** `AGENTS.md` documents how to work in this repo (process, conventions, workflow). `SPEC.md` documents what the software does and guarantees (the CSV↔LIFT data model). Repo-wide engineering conventions that happen to describe behaviour (e.g. stdout/stderr separation) stay in `AGENTS.md` since they apply uniformly across scripts; `SPEC.md` is reserved for the CSV↔LIFT contract specifically.

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
- Use `testthat::expect_snapshot_file()` (via the `expect_cli_stdout_file_snapshot()` helper in `tests/testthat/helper-cli-snapshots.R`) for CLI output, not `expect_snapshot()`. This stores each approved artifact as its own raw file (e.g. `_snaps/<test-file>/<fixture>.csv`) instead of wrapping it in a markdown fence, while keeping the same `.new`/review/accept workflow.
- Follow the Emily Bache approval-testing workflow: checked-in snapshots are the approved artifacts, and `.new` snapshot files are the review artifacts.
- Keep snapshot artifacts human-reviewable and deterministic so diffs are meaningful.
- Do not auto-accept snapshot changes; review them explicitly with `testthat::snapshot_review()` or `testthat::snapshot_accept()`.
- `tests/testthat/setup.R` sets `NOT_CRAN=true` when unset. Both `expect_snapshot()` and `expect_snapshot_file()` silently skip otherwise (only `devtools::test()` sets this for you automatically) — without it, a bare `Rscript -e 'testthat::test_dir(...)'` run or a naive CI script would report all-green while skipping every snapshot-based test.
- Follow TDD for behaviour changes: add/extend the fixture and confirm the corresponding test fails first (red), write the minimum implementation to make it pass (green), then refactor with the tests as a safety net before considering the change done.

