# Approval tests for `lift2csv.R --table pronunciations`, one per curated fixture.
# The loop lives in expect_table_snapshots() (helper-cli-snapshots.R), which
# documents why each table keeps its own test file and _snaps/ directory.
expect_table_snapshots("pronunciations", "lift2csv_pronunciation-table")
