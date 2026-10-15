# Module 01: Standardise Column Headers

## Purpose

Gives every column a standard lower-case name and drops the `.parentKey` columns.

## When it runs

After Module 00a. It works on `df_raw`, the de-identified data frame, and never reads the raw CSV.

## What it does

The module stops if `df_raw` does not exist. It then calls `assert_pii_removed()` with `check_run_id = TRUE`, which stops the run unless `df_raw` is the object Module 00a produced for the current input.

Each column name is standardised:

1. Leading and trailing whitespace is removed.
2. Whitespace around dots is removed.
3. All remaining spaces and underscores are removed.
4. The name is converted to lower case.

| Raw name | Standardised name |
|----------|-------------------|
| `Unique Key`, `unique_key` | `uniquekey` |
| `BabyCry.value`, `Baby Cry . Value` | `babycry.value` |

Columns listed in `cfg$reserved_column_renames` are then renamed, so that a data field does not share a name with a key column. For example, `facility.value` becomes `facilityname.value` in the dataset for which that rename is configured.

Columns whose names end in `.parentkey` are dropped. No other column is dropped.

## Inputs

| Object | Description |
|--------|-------------|
| `df_raw` | De-identified data frame from Module 00a |
| `cfg$reserved_column_renames` | Named vector: standardised name to new name, or `NULL` |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df` | Data frame with standardised column names |
| `reports/01_column_standardisation_report.txt` | Number of columns on entry, names standardised, reserved renames, `.parentKey` columns dropped and columns remaining; the names of the dropped columns. |

## Function

`clean_columns(df, report_filepath = NULL)` returns the data frame with standardised column names and without the `.parentKey` columns.

## Configuration

| Setting | Effect |
|---------|--------|
| `RESERVED_COLUMN_RENAMES` | Per dataset, the standardised column names to rename and their new names. |
