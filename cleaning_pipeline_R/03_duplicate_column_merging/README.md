# Module 03: Duplicate Column Merging

## Purpose

Merges columns that share the same name into one column per name.

## When it runs

After Module 02.

## What it does

A column whose name appears once is left as it is. For each name that appears more than once:

1. The copy with the most non-missing values is taken as the primary. On a tie, the first copy is taken.
2. Each row where the primary is `NA` is filled from the other copies, in column order.
3. The merged column is kept and the other copies are dropped.

Each merged column takes the position of the first column with that name. Column names are kept exactly as they are.

If no name is duplicated, the data frame is returned unchanged.

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 02 |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df` | Data frame with one column per name |
| `reports/03_duplicate_column_report.txt` | Number of columns before and after merging, number of duplicate columns and, for each merged name, the number of copies and the non-missing count of the primary copy. States that no duplicates were found when that is the case. |

## Function

`merge_duplicate_columns(df, report_filepath = NULL)` returns the merged data frame.
