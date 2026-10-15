# Module 07: Drop Label Columns

## Purpose

Drops the remaining label columns and keeps one column for each variable prefix.

## When it runs

After Module 06.

## What it does

1. Every column whose name contains `label` is dropped.
2. The remaining columns are grouped by prefix, the part of the name before the first `.`. One column is kept in each group and the others are dropped.

| Columns in the group | Column kept |
|----------------------|-------------|
| Both the bare column (`x`) and `x.value` | The one with more non-missing values; the bare column on a tie |
| `x.value` but no bare column | `x.value` |
| The bare column but no `x.value` | The bare column |
| Neither | The first column of the group |

A group holds every column with the same prefix, so a column with another suffix, such as `x.valuedischarge`, is dropped when `x` or `x.value` is kept.

The kept columns stay in their original order.

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 06 |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df` | Data frame with no label columns and one column per prefix |
| `reports/07_drop_columns_report.txt` | For each prefix with a dropped column in step 2, the column kept and the columns dropped. Columns dropped in step 1 are not listed. |

## Function

`drop_unwanted_columns(df, report_filepath = NULL)` returns the reduced data frame.
