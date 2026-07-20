# AGENTS.md

Guidance for human and AI contributors working in this repository.

## Scope

- This file applies to the whole repository.

## Core Principles

- Prefer common, well-maintained libraries and packages over custom ad hoc logic.
- Keep changes focused and minimal for the requested task.
- Do not modify unrelated files.

## Working Style

- Before changing behaviour, check existing patterns in nearby files and follow them.
- When behaviour changes are non-trivial, ask for confirmation before implementing.
- If a requirement is ambiguous and could alter behaviour, ask a clarifying yes/no question first.

## Libraries And Dependencies

- Reuse existing dependencies and idioms already present in the repo when possible.
- Add a new package only when it clearly improves reliability, readability, or maintainability.
- Prefer widely adopted packages over hand-rolled implementations.

## R Code Conventions

- Add brief comments for non-obvious logic so future readers can follow intent.

## CLI Script Conventions

- For scripts that emit machine-readable output:
  - Write result content only to stdout.
  - Write progress, diagnostics, and errors to stderr.

## Testing Approach

- Prefer native `testthat` snapshot tests for CLI and file-conversion workflows when outputs are large or awkward to assert inline.
- Keep input fixtures under `tests/data/<script>/input/` and let `testthat` manage approved artifacts under `tests/testthat/_snaps/`.
- Follow the Emily Bache approval-testing workflow: checked-in snapshots are the approved artifacts, and `.new` snapshot files are the review artifacts.
- Keep snapshot artifacts human-reviewable and deterministic so diffs are meaningful.
- Do not auto-accept snapshot changes; review them explicitly with `testthat::snapshot_review()` or `testthat::snapshot_accept()`.

