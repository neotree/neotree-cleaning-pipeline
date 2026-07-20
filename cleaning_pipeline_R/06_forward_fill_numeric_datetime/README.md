# Module 06: Forward Fill Numeric and Datetime Values

## Purpose
Recovers numeric and datetime values that were recorded in `.label` columns instead of their paired `.value` columns. After recovery, all `.label` / `.labeldischarge` columns are dropped -- they are no longer needed after this point.

---

## When It Runs
After Module 05 (placeholder fill). All remaining useful content in `.label` columns that could not be recovered as a categorical placeholder is extracted here as a numeric or datetime value.

---

## Logic

For each paired `.value` / `.label` column (and `.valuedischarge` / `.labeldischarge`), the module processes rows where `.value` is `NA` but `.label` is not:

1. **Numeric coercion** -- attempts to convert the `.label` content to a number. Rows where this succeeds are filled in `.value` with the numeric result.
2. **Datetime coercion** -- for rows still empty after numeric fill, attempts to parse the `.label` content as a date/time using `lubridate::parse_date_time()` with multiple format patterns (`ymd HMS`, `ymd`, `dmy HMS`, `dmy`, `mdy`, etc.). Rows where parsing succeeds are filled in `.value` with the datetime string.
3. **Drop label columns** -- regardless of whether any fills occurred, the `.label` / `.labeldischarge` column is dropped after processing.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 05 with `.value` / `.label` column pairs |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df` | Data frame with numeric/datetime values recovered; all `.label` and `.labeldischarge` columns removed |
| `reports/06_forward_fill_numeric_datetime_report.txt` | Per-column count of values filled (optional) |

---

## Key Function

**`forward_fill_numeric_datetime(df, report_filepath = NULL)`**

- Builds a mapping of `.value` -> `.label` column pairs (and `.valuedischarge` -> `.labeldischarge`).
- For each pair: numeric fill first, then datetime fill for remaining NAs.
- Drops the `.label` column after processing each pair.
- Returns the updated data frame without any `.label` columns.

---

## Notes

- Numeric coercion is attempted before datetime to avoid a number like `"29"` being parsed as a date.
- Values that cannot be coerced to either numeric or datetime are left as `NA` in `.value` -- no forced or approximate conversions are made.
- This is the last step that references `.label` columns; Module 07 drops any `.label` columns that remain (e.g. those without a corresponding `.value` partner).
