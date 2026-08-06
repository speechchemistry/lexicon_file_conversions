# Add AGENTS.md/SPEC.md split-of-concerns note

Add one bullet to `AGENTS.md`'s existing "## Specification" section (already approved verbatim by the user in chat):

> **Split of concerns:** `AGENTS.md` documents how to work in this repo (process, conventions, workflow). `SPEC.md` documents what the software does and guarantees (the CSV↔LIFT data model). Repo-wide engineering conventions that happen to describe behavior (e.g. stdout/stderr separation) stay in `AGENTS.md` since they apply uniformly across scripts; `SPEC.md` is reserved for the CSV↔LIFT contract specifically.

No other changes. This is a single-bullet documentation addition, already agreed word-for-word in chat.
