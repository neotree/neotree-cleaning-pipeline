# Module 05: Forward Fill Placeholder Values

## Purpose

Copies a set of fixed placeholder words from a label column into its paired value column where the value is missing.

## When it runs

After Module 04.

## What it does

Columns are paired by name: each `.value` column with the `.label` column of the same variable, and each `.valuedischarge` column with its `.labeldischarge` column. A value column with no label column is skipped.

In each pair, a row is filled when the value is `NA` and the label is exactly one of the placeholders below. The label text is copied into the value column as it is.

| Group | Placeholders |
|-------|--------------|
| None / normal | `None`, `Normal`, `Norm`, `none`, `normal`, `norm`, `NONE`, `NORMAL`, `NORM` |
| True / false | `True`, `False`, `TRUE`, `FALSE` |
| Yes / no | `Yes`, `No`, `YES`, `NO`, `Y`, `N` |

Matching is case-sensitive. Labels in any other form are not copied. The label columns are kept.

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 04 |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df` | Data frame with placeholders copied into the value columns |
| `reports/05_forward_fill_placeholder_report.txt` | Number of placeholders checked, total number of values filled and, for each pair with a fill, the number of values filled. |

## Function

`forward_fill_placeholders(df, placeholders = PLACEHOLDER_VALUES, report_filepath = NULL)` returns the updated data frame. `placeholders` is the character vector of labels that may be copied.
