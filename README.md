
# lexicon_file_conversions

<!-- badges: start -->
<!-- badges: end -->

The goal of lift2csv is to convert a SIL Flex LIFT file into tidy CSV files.

## Installation

You can download the package by clicking on the green code button and selecting "Download ZIP2".

## Example

This is a basic example which shows you how to generate the entry table and the sense table. The Sena3 LIFT file can be found in the test folder and was generated from Flex backup file on the SIL Flex website. 

``` bash
Rscript scripts/lift2csv_entry-table.R Sena3.lift > Sena3_entry-table.csv
Rscript scripts/lift2csv_sense-table.R Sena3.lift > Sena3_sense-table.csv
```

