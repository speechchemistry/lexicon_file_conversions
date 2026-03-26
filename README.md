
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


