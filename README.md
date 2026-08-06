
# lexicon_file_conversions

<!-- badges: start -->
<!-- badges: end -->

The goal of lift2csv is to convert a SIL Flex LIFT file into tidy CSV files.

## Installation

You can download the package by clicking on the green code button and selecting "Download ZIP".

## Example

This is a basic example which shows you how to generate the entry table and the sense table. The Sena3 LIFT file can be found in the test folder and was generated from Flex backup file on the SIL Flex website. 

``` bash
Rscript scripts/lift2csv_entry-table.R Sena3.lift > Sena3_entry-table.csv
Rscript scripts/lift2csv_sense-table.R Sena3.lift > Sena3_sense-table.csv
Rscript scripts/lift2csv_join-sense-entry-table.R Sena3.lift > Sena3_join-sense-entry-table.csv
```

## Supported Fields

See [`SPEC.md`](SPEC.md) for the full table/column/LIFT-source reference and the current known limitations — it's the source of truth for the CSV↔LIFT data model, kept in sync with the code as design decisions are made.

## Testing

End-to-end CLI approvals use native `testthat` snapshots.

- Input fixtures stay under `tests/data/<script>/input/`.
- Approved outputs live in `tests/testthat/_snaps/<test-file>/<fixture>.<ext>` as raw files (e.g. a `.csv` or `.lift` file), not markdown-wrapped text — CLI tests use `testthat::expect_snapshot_file()` (via the `expect_cli_stdout_file_snapshot()` helper) rather than `expect_snapshot()`.
- When output changes, `testthat` writes a `.new` snapshot for review.
- Review snapshot diffs before accepting them with `testthat::snapshot_review()` or `testthat::snapshot_accept()`.
- Run the suite with `devtools::test()`, or set `NOT_CRAN=true` first if invoking `testthat::test_dir()`/`Rscript` directly — snapshot tests are otherwise silently skipped. `tests/testthat/setup.R` sets this automatically when unset.

This follows the Emily Bache approval-testing workflow using `testthat` conventions: checked-in snapshots are the approved artifacts, and `.new` files are the review artifacts.

## Copy Selected Entries by GUID

Use `scripts/copy-lift-entries.R` to extract specific `<entry>` elements from a source LIFT file and write a new LIFT document to stdout.

Usage:

``` bash
Rscript scripts/copy-lift-entries.R <source_lift> [guid_file]
```

Arguments:

- `source_lift`: path to source LIFT file.
- `guid_file`: optional text file with one GUID per line.
	- Use `-` to read GUIDs from stdin.
	- If omitted, GUIDs are read from stdin.

Examples:

``` bash
# Read GUIDs from a file
Rscript scripts/copy-lift-entries.R Sena3.lift one-guid.txt > subset.lift

# Read GUIDs from stdin (explicit "-")
printf '0006f482-a078-4cef-9c5a-8bd35b53cf72\n' | \
	Rscript scripts/copy-lift-entries.R Sena3.lift - > subset.lift

# Read multiple GUIDs from stdin (omit guid_file)
printf '0006f482-a078-4cef-9c5a-8bd35b53cf72\n00f99de8-333b-4c51-a306-a6d54b58723a\n' | \
	Rscript scripts/copy-lift-entries.R Sena3.lift > subset.lift
```


