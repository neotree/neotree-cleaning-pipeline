# Module 03: Duplicate Column Merging

## Purpose
Consolidates columns that appear more than once under the same name -- an artefact that can occur in Metabase exports or joined datasets -- into a single column that retains the maximum available data.

---

## When It Runs
After Module 02 (frame shift correction). Duplicate column names must be resolved before dictionary-based value cleaning, which performs lookups by exact column name.

---

## Logic

For each group of columns sharing the same name:

1. **Select the primary copy** -- the one with the most non-null values.
2. **Fill gaps** -- for any row where the primary copy is `NA`, attempt to fill it from the remaining duplicates (in order).
3. **Drop the secondary copies** -- only the merged primary column is retained.

If a column name appears only once, it is left entirely unchanged.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 02, which may contain duplicate column names |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df` | Data frame with one column per unique name, data intelligently merged |
| `reports/03_duplicate_column_report.txt` | List of merged column groups and non-null counts (optional) |

---

## Key Function

**`merge_duplicate_columns(df, report_filepath = NULL)`**

- Groups columns by name.
- For each duplicated group, selects the copy with the highest non-null count as the primary, then fills its NAs from the others.
- Returns a data frame with no duplicate column names.

---

## Notes

- No data is lost: any non-null value present in any copy of a column is preserved in the merged result.
- This step is particularly relevant for Metabase exports, which occasionally produce duplicate column instances.
- The report lists each merged group and the non-null count of the winning primary copy.
- `as.data.frame()` is called with `check.names = FALSE` to prevent base-R's `make.names()` from silently sanitising non-syntactic column names (e.g. `<28wks/1kg`, `$symptomreviewneurology`, `cleftlipand/orpalate`). These names are clinically meaningful and must be preserved exactly as produced by Module 01.
