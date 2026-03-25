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

