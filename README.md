
# lexicon_file_conversions

<!-- badges: start -->
<!-- badges: end -->

The goal of lift2csv is to convert a SIL Flex LIFT file into tidy CSV files. The goal of csv2lift is to convert it back again.

## Installation

You can download the package by clicking on the green code button and selecting "Download ZIP".

## Example: LIFT → CSV (lift2csv)

`scripts/lift2csv.R` writes every table it knows how to read (see `R/table_registry.R`) from a LIFT file into `--table-dir <dir>` in one pass, one plainly-named CSV per table (`entries.csv`, `senses.csv`, ...). `sena3.lift` is a real Sena FLEx project export, checked in as a test fixture.

``` bash
Rscript scripts/lift2csv.R tests/testthat/fixtures/lift2csv_entry-table/sena3.lift --table-dir sena3-tables/
```

The same script also writes a single table's CSV to stdout with `--table <name>` — useful for one table at a time:

``` bash
Rscript scripts/lift2csv.R tests/testthat/fixtures/lift2csv_entry-table/sena3.lift --table senses > sena3-sense-table.csv
```
## Example: CSV → LIFT (csv2lift)

`csv2lift.R` does the reverse: it takes an entry-level CSV (required) and, optionally, sense-level, pronunciation-level, and example-level CSVs, and builds a LIFT file. `--table-dir <dir>` discovers all of them at once from a directory laid out the same way `lift2csv.R` writes one above:

``` bash
Rscript scripts/csv2lift.R --table-dir tests/testthat/fixtures/csv2lift/zhi-two-pronunciations-with-audio-and-ipa \
  > zhi-two-pronunciations-with-audio-and-ipa.lift
```

Each table can also be named explicitly with its own `--<table>` flag (an explicit flag overrides a discovered file of the same table) — useful when a CSV isn't named to the `--table-dir` convention, or the entry CSV as a bare positional argument, kept for backward compatibility:

``` bash
Rscript scripts/csv2lift.R tests/testthat/fixtures/csv2lift/sena3-example-duplicate-translation/entries.csv \
  --senses tests/testthat/fixtures/csv2lift/sena3-example-duplicate-translation/senses.csv \
  --examples tests/testthat/fixtures/csv2lift/sena3-example-duplicate-translation/examples.csv \
  > sena3-example-duplicate-translation.lift
```

`--examples` requires `--senses` (or a discovered senses table), since examples attach to `<sense>` elements; the entry table is the only mandatory one. See [`SPEC.md`'s CLI shape section](SPEC.md#csv2lift-cli-shape) for the full CLI shape.

## Supported Fields

See [`SPEC.md`](SPEC.md) for the full table/column/LIFT-source reference and the current known limitations — it's the source of truth for the CSV↔LIFT data model, kept in sync with the code as design decisions are made.

## Testing

End-to-end CLI approvals use native `testthat` snapshots.

- Input fixtures stay under `tests/testthat/fixtures/<script>/`.
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
Rscript scripts/copy-lift-entries.R sena3.lift one-guid.txt > subset.lift

# Read GUIDs from stdin (explicit "-")
printf '0006f482-a078-4cef-9c5a-8bd35b53cf72\n' | \
	Rscript scripts/copy-lift-entries.R sena3.lift - > subset.lift

# Read multiple GUIDs from stdin (omit guid_file)
printf '0006f482-a078-4cef-9c5a-8bd35b53cf72\n00f99de8-333b-4c51-a306-a6d54b58723a\n' | \
	Rscript scripts/copy-lift-entries.R sena3.lift > subset.lift
```


