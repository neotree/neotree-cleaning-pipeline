# Module 08: Drop Auto-Populated Columns

## Purpose

Passes the data frame through unchanged and writes a report saying so. No column is dropped.

## When it runs

After Module 07 and before Module 09.

## What it does

The data frame is not modified. Columns with the `dc` suffix, which hold values entered on the discharge form, are kept alongside the admission-form columns of the same variable.

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 07 |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df` | Data frame, unchanged |
| `reports/08_autopopulated_columns_report.txt` | Number of columns, and a statement that no column was dropped. |

## Function

The module defines no function. The script writes the report and logs the dimensions of `df`.
