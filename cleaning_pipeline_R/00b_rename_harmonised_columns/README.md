# Module 00b: Rename Columns to Harmonised Names (Optional Post-Processing)

## Purpose
Renames the pipeline's internal column names (e.g. `admissionweight`, `datetimeadmission`) to human-readable, snake_case harmonised names (e.g. `admission_weight_kg`, `datetime_admission`) as defined in the data dictionary. This is an **optional** step run after the main pipeline has completed (after Module 15).

---

## When It Runs
After Module 15 (final merge output). It operates on `df_clean` -- the fully cleaned, merged, and deduplicated dataset. It must **not** be run between cleaning steps because intermediate modules rely on the internal naming convention for dictionary lookups.

**This module is disabled by default.** It only runs when `SAVE_HARMONISED = TRUE` is set in `00_setup.r` (or injected from `run_all.r`). When disabled, the module exits immediately with a log message and `df_harmonised` is not created -- nothing downstream depends on it.

---

## Logic

For each column in `df_clean`:

1. The `.value` / `.valuedischarge` suffix is stripped from the column name (e.g. `admissionweight.value` -> `admissionweight`). After Module 15's suffix-stripping step, column names are already bare, so this is a no-op for most columns -- it is retained for safety.
2. The base name is looked up in `cfg$harmonised_map` (a named vector: `question_key -> harmonised_variable_name`, built from the dictionary's `harmonised_variable_name` column in Module 00).
3. If a match is found, the column is renamed to the harmonised name.
4. If no match is found, the column name is left unchanged.

Primary key and system columns (`facility`, `uid`, `uniquekey`, `startedat`, `completedat`, etc.) typically do not have harmonised names and are left as-is.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df_clean` | Final merged, deduplicated dataset produced by Module 15 |
| `cfg$harmonised_map` | Named character vector: `question_key -> harmonised_variable_name` -- built by Module 00 from the data dictionary |

`df_clean` must exist in the environment -- it is created by Module 15 and is not re-loaded from disk.

---

## Outputs

Outputs are only produced when `SAVE_HARMONISED = TRUE` (default is `FALSE`). When disabled, none of these are created.

| Object / File | Description |
|---------------|-------------|
| `df_harmonised` | Dataset with harmonised snake_case column names |
| `output/<file_stem>/<file_stem>_cleaned_harmonised.csv` | CSV in the run's output subfolder, with `_harmonised` appended to the stem |
| `output/<file_stem>/<file_stem>_cleaned_harmonised.rds` | RDS binary, also with `_harmonised` suffix |
| `output/<file_stem>/reports/00b_harmonised_rename_report.txt` | List of all renamed columns (original -> harmonised) and unchanged columns |

---

## Key Function

**`rename_harmonised(df, harmonised_map, report_filepath = NULL)`**

- Iterates over all column names in `df`.
- Strips `.value` suffix, looks up in `harmonised_map`, applies rename if found.
- Returns the renamed data frame.

---

## Notes

- This module is fully **backward-compatible** with Module 15's suffix-stripping change. Since Module 15 now strips `.value` before saving, column names arriving here are already bare (e.g. `admissionweight` instead of `admissionweight.value`). The `sub("\\.value$", "", col)` call inside this module becomes a no-op and causes no harm.
- Columns without a `harmonised_variable_name` in the dictionary (including all system/key columns) are left with their existing names.
- The harmonised output is saved as a separate file -- the Module 15 output (`*_cleaned.csv`) is not overwritten.
- To add or update harmonised names, edit the `harmonised_variable_name` column in the dictionary's Variables sheet, then rebuild the dictionary and re-run `00_setup.r`.
