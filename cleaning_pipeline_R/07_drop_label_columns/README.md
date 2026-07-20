# Module 07: Drop Label Columns and Resolve Prefix Duplicates

## Purpose
Removes all remaining `.label` / `.labeldischarge` columns (any that survived Modules 05-06) and resolves cases where both a bare column and a `.value` column exist for the same variable -- keeping whichever contains more data.

---

## When It Runs
After Module 06 (numeric/datetime forward fill). At this point all useful content has been extracted from `.label` columns; they are now redundant.

---

## Logic

**Step 1 -- Drop all `.label` columns**
Any column whose name contains the string `"label"` is dropped unconditionally.

**Step 2 -- Resolve bare vs `.value` duplicates**
After label columns are removed, columns are grouped by their prefix (the portion before the first `.`). For each group:

| Situation | Decision |
|-----------|----------|
| Only a `.value` column exists (e.g. `age.value`) | Keep `age.value` |
| Only a bare column exists (e.g. `age`) | Keep `age` |
| Both `age` and `age.value` exist | Compare non-null counts; keep the one with more data. On a tie, keep the bare column. |
| Neither -- other suffix variants (e.g. only `age.valuedischarge`) | Keep the first column in the group |

The original column order is preserved; only columns that lose the comparison are dropped.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 06 with `.label` columns removed and `.value` columns populated |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df` | Data frame with all label columns dropped and prefix duplicates resolved |
| `reports/07_drop_columns_report.txt` | Per-prefix decision log: which column was kept and which was dropped (optional) |

---

## Key Function

**`drop_unwanted_columns(df, report_filepath = NULL)`**

- Drops all columns containing `"label"` in their name.
- Groups remaining columns by prefix and resolves bare vs `.value` conflicts by non-null count.
- Returns the pruned data frame.

---

## Notes

- Column names at this stage still retain the `.value` suffix (e.g. `age.value`). Suffix stripping is performed at the very end of the pipeline, in Module 15, after all validation is complete.
- This step mirrors the Jupyter pipeline's `drop_unwanted_columns()` function exactly.
