# Module 00b: Rename Columns to Harmonised Names

## Purpose

Produces a copy of the cleaned dataset in which each column carries the harmonised variable name given in the data dictionary.

## When it runs

After Module 15, on `df_clean`. It stops if `df_clean` does not exist. It does nothing unless `cfg$save_harmonised` is `TRUE`.

## What it does

For each column, the suffix `.valuedischarge` or `.value` is removed to give the base name.

| Base name | Result |
|-----------|--------|
| A `question_key` in `cfg$harmonised_map` | The column is renamed to its harmonised name. |
| Not in the map | The column keeps its name. |

Columns with any other suffix, such as `.label`, are looked up under their full name.

Before writing, `assert_pii_removed()` checks the renamed data frame. The data frame is then written as CSV, with `NA` as an empty field, and as RDS.

## Inputs

| Object | Description |
|--------|-------------|
| `df_clean` | Data frame from Module 15 |
| `cfg$harmonised_map` | Named vector: `question_key` to harmonised name |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df_harmonised` | Data frame with harmonised column names |
| `<cleaned output name>_harmonised.csv`, `<cleaned output name>_harmonised.rds` | Written beside the cleaned outputs, from `cfg$output_csv` and `cfg$output_rds` |
| `reports/00b_harmonised_rename_report.txt` | Number of columns renamed and unchanged; each renamed column with its new name; the names of the unchanged columns. Column names only. |

## Function

`rename_harmonised(df, harmonised_map, report_filepath = NULL)` returns the data frame with harmonised column names.

## Configuration

| Setting | Effect |
|---------|--------|
| `SAVE_HARMONISED` | `TRUE` runs the module and writes its outputs. `FALSE` skips it; `df_harmonised` is not created. |
