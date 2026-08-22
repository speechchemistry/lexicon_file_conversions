# Approval tests for `lift2csv.R --table etymologies`, one per curated fixture.
# The loop lives in expect_table_snapshots() (helper-cli-snapshots.R), which
# documents why each table keeps its own test file and _snaps/ directory.
expect_table_snapshots("etymologies", "lift2csv_etymology-table")
