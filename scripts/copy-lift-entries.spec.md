# copy-lift-entries.R Specification

## Purpose

Define the behavior of scripts/copy-lift-entries.R, a command-line tool that:
- extracts selected <entry> elements from a source LIFT file by GUID,
- updates each extracted entry dateModified value to the current UTC timestamp,
- emits a complete LIFT document to stdout.

## Scope

This specification covers:
- command-line interface
- input/output streams
- GUID ordering and duplication behavior
- dateModified update behavior
- error behavior

This specification does not cover:
- full XML schema validation
- malformed XML recovery
- automatic GUID deduplication

## Command-Line Interface

Script name:
- scripts/copy-lift-entries.R

Invocation:
- Rscript scripts/copy-lift-entries.R <source_lift> [guid_file]

Arguments:
- source_lift: required path to source LIFT file
- guid_file: optional path to text file with one GUID per line
  - if guid_file is omitted, GUIDs are read from stdin
  - if guid_file is -, GUIDs are read from stdin

Output destination:
- LIFT XML output is written to stdout

Logging and errors:
- progress messages are written to stderr
- error messages are written to stderr

## Input Rules

### Source LIFT

Required input. Source file must exist.

Expected source content:
- one <header>...</header> section
- one or more <entry ...>...</entry> blocks

### GUID Input

GUIDs are read line-by-line from either:
- guid_file, or
- stdin

Parsing rules:
- blank lines are ignored
- non-blank lines are used exactly as provided

## Processing Rules

1. Read source file content.
2. Extract the first <header>...</header> block.
3. Read GUIDs in input order.
4. Generate a single run timestamp in UTC format YYYY-MM-DDTHH:MM:SSZ.
5. For each GUID in order:
   - locate matching <entry ... guid="..."> start tag,
   - extract full entry XML through its matching </entry>,
   - replace dateModified attribute value with the run timestamp.
6. Build output document in this order:
   - source document prefix up to and including opening <lift ...> tag
   - extracted header block
   - extracted entries in GUID input order
   - closing </lift>
7. Write complete output document to stdout.

## Ordering and Duplication

- Output entry order matches GUID input order.
- Repeated GUIDs are preserved (no deduplication).

## Error Behavior

The script exits non-zero and writes an ERROR message to stderr when:
- source_lift is missing
- source_lift does not exist
- header block is not found
- no GUIDs are provided after parsing
- a requested GUID is not found
- matching entry closing tag cannot be resolved
- any unexpected runtime error occurs

Failure model:
- fail-fast on first unrecoverable error

## Streams Contract

- stdout: only LIFT XML output
- stderr: progress, success, and error messages

## Output Envelope (Current)

The emitted document currently uses:
- the source file's original prefix from the beginning of file through the opening <lift ...> tag
- the source file's extracted <header>...</header>
- a closing </lift> tag

## Acceptance Criteria

A run is correct when all conditions hold:
- output LIFT document is written to stdout and can be redirected
- output contains one header section and a closing </lift>
- output includes one entry per requested GUID, preserving order and duplicates
- every included entry has dateModified updated to the run UTC timestamp
- if any requested GUID is invalid or missing, process exits non-zero and reports ERROR on stderr
